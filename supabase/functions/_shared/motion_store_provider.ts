import { Buffer } from "node:buffer";
import {
  APIException,
  AppStoreServerAPIClient,
  Environment,
  ReceiptUtility,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import {
  type MotionAppId,
  type ProviderState,
  type ProviderVerifiedPurchase,
  purchaseScope,
} from "./motion_purchase_claim.ts";

// App Store IDs were read back from App Store Connect on 2026-09-24. Store
// responses are also checked against the corresponding bundle and app ID.
export const appleApps: Record<
  MotionAppId,
  { bundleId: string; appAppleId: number }
> = {
  ostinato: { bundleId: "com.yulalab.ostinato", appAppleId: 6794717868 },
  gravita: { bundleId: "com.yulalab.gravita", appAppleId: 6794714365 },
  choreia: { bundleId: "com.yulalab.choreia", appAppleId: 6794721329 },
  jablab: { bundleId: "com.yulalab.jablab", appAppleId: 6794715669 },
  lissom: { bundleId: "com.yulalab.lissom", appAppleId: 6794715023 },
};

export interface StoreEvidence {
  originatingAppId: MotionAppId;
  productId: string;
  verificationData: string;
  transactionId?: string;
}

export class StoreConfigurationError extends Error {}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new StoreConfigurationError(`${name} is missing`);
  return value;
}

export function appleRootCertificates(): Buffer[] {
  let encoded: unknown;
  try {
    encoded = JSON.parse(requiredEnv("MOTION_APPLE_ROOT_CAS_BASE64"));
  } catch {
    throw new StoreConfigurationError("Apple root certificates are invalid");
  }
  if (
    !Array.isArray(encoded) || encoded.length < 1 || encoded.length > 8 ||
    encoded.some((item) => typeof item !== "string" || item.length < 100)
  ) throw new StoreConfigurationError("Apple root certificates are invalid");
  return encoded.map((item) => Buffer.from(item, "base64"));
}

function appleClient(appId: MotionAppId, environment: Environment) {
  return new AppStoreServerAPIClient(
    requiredEnv("MOTION_APPLE_IAP_PRIVATE_KEY").replaceAll("\\n", "\n"),
    requiredEnv("MOTION_APPLE_IAP_KEY_ID"),
    requiredEnv("MOTION_APPLE_IAP_ISSUER_ID"),
    appleApps[appId].bundleId,
    environment,
  );
}

function appleState(status: number | undefined): ProviderState | null {
  switch (status) {
    case 1:
      return "active";
    case 2:
      return "expired";
    case 3:
      return "hold";
    case 4:
      return "grace";
    case 5:
      return "revoked";
    default:
      return null;
  }
}

export async function appleStatusWithFallback<T>(
  request: (environment: Environment) => Promise<T>,
): Promise<{ environment: Environment; status: T }> {
  try {
    return {
      environment: Environment.PRODUCTION,
      status: await request(Environment.PRODUCTION),
    };
  } catch (error) {
    // Apple recommends a sandbox lookup only for a transaction that the
    // production environment does not contain. Other faults must surface.
    if (
      !(error instanceof APIException) || error.httpStatusCode !== 404 ||
      error.apiError !== 4040010
    ) throw error;
  }
  return {
    environment: Environment.SANDBOX,
    status: await request(Environment.SANDBOX),
  };
}

export async function verifyApplePurchase(
  evidence: StoreEvidence,
): Promise<ProviderVerifiedPurchase[]> {
  const app = appleApps[evidence.originatingAppId];
  let transactionId = evidence.transactionId;
  if (!transactionId && evidence.verificationData) {
    try {
      transactionId = new ReceiptUtility().extractTransactionIdFromAppReceipt(
        evidence.verificationData,
      ) ?? undefined;
    } catch {
      return [];
    }
  }
  if (!transactionId || !/^\d{1,32}$/.test(transactionId)) return [];

  const { environment, status } = await appleStatusWithFallback(
    (target) =>
      appleClient(evidence.originatingAppId, target)
        .getAllSubscriptionStatuses(transactionId),
  );
  if (
    status.bundleId !== app.bundleId ||
    status.environment !== environment ||
    (environment === Environment.PRODUCTION &&
      status.appAppleId !== app.appAppleId)
  ) return [];

  const verifier = new SignedDataVerifier(
    appleRootCertificates(),
    true,
    environment,
    app.bundleId,
    environment === Environment.PRODUCTION ? app.appAppleId : undefined,
  );
  const claims: ProviderVerifiedPurchase[] = [];
  for (const group of status.data ?? []) {
    for (const item of group.lastTransactions ?? []) {
      const state = appleState(item.status);
      if (!state || !item.signedTransactionInfo) continue;
      const transaction = await verifier.verifyAndDecodeTransaction(
        item.signedTransactionInfo,
      );
      if (
        !transaction.originalTransactionId ||
        transaction.originalTransactionId !== item.originalTransactionId ||
        !transaction.productId ||
        !purchaseScope(
          "apple",
          evidence.originatingAppId,
          transaction.productId,
        ) ||
        !transaction.appAccountToken
      ) continue;
      let expiry = transaction.expiresDate;
      if (state === "grace") {
        if (!item.signedRenewalInfo) continue;
        const renewal = await verifier.verifyAndDecodeRenewalInfo(
          item.signedRenewalInfo,
        );
        if (
          renewal.originalTransactionId !== transaction.originalTransactionId
        ) {
          continue;
        }
        expiry = renewal.gracePeriodExpiresDate;
      }
      if (typeof expiry !== "number" || !Number.isFinite(expiry)) continue;
      claims.push({
        store: "apple",
        originatingAppId: evidence.originatingAppId,
        productId: transaction.productId,
        accountMarker: transaction.appAccountToken,
        reference: transaction.originalTransactionId,
        state: transaction.revocationDate ? "revoked" : state,
        expiresAt: new Date(expiry).toISOString(),
        // Introductory offer (offerType 1) taken as a free trial.
        freeTrial: transaction.offerType === 1 &&
          String(transaction.offerDiscountType) === "FREE_TRIAL",
      });
    }
  }
  return claims;
}

interface GoogleServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

function base64Url(input: Uint8Array): string {
  return btoa(String.fromCharCode(...input)).replaceAll("+", "-")
    .replaceAll("/", "_").replaceAll("=", "");
}

function googleServiceAccount(): GoogleServiceAccount {
  let value: unknown;
  try {
    value = JSON.parse(requiredEnv("MOTION_GOOGLE_PLAY_SERVICE_ACCOUNT"));
  } catch {
    throw new StoreConfigurationError("Google service account is invalid");
  }
  if (
    typeof value !== "object" || value === null ||
    !("client_email" in value) || !("private_key" in value) ||
    typeof value.client_email !== "string" ||
    typeof value.private_key !== "string" ||
    !value.client_email.endsWith(".iam.gserviceaccount.com") ||
    !value.private_key.includes("BEGIN PRIVATE KEY")
  ) throw new StoreConfigurationError("Google service account is invalid");
  return value as GoogleServiceAccount;
}

async function googleAccessToken(): Promise<string> {
  const account = googleServiceAccount();
  const header = base64Url(new TextEncoder().encode(JSON.stringify({
    alg: "RS256",
    typ: "JWT",
  })));
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 300,
  })));
  const signingInput = `${header}.${payload}`;
  const pem = account.private_key.replaceAll("\\n", "\n")
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (letter) => letter.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  const assertion = `${signingInput}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error("Google OAuth token request failed");
  const body: unknown = await response.json();
  if (
    typeof body !== "object" || body === null ||
    !("access_token" in body) || typeof body.access_token !== "string"
  ) throw new Error("Google OAuth token response is invalid");
  return body.access_token;
}

function googleState(value: unknown): ProviderState | null {
  switch (value) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      return "active";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return "grace";
    case "SUBSCRIPTION_STATE_CANCELED":
      return "canceled";
    case "SUBSCRIPTION_STATE_EXPIRED":
      return "expired";
    case "SUBSCRIPTION_STATE_ON_HOLD":
    case "SUBSCRIPTION_STATE_PAUSED":
      return "hold";
    case "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED":
      return "revoked";
    default:
      return null;
  }
}

/** Play tag on the developer-determined Motion+ trial offer (CORE-09). */
export const MOTION_PLUS_TRIAL_OFFER_TAG = "motion-plus-trial";

// A purchase in (or bought through) a free-trial phase: the offer carries the
// Motion trial tag, or Play reports the free-trial offer phase (field placement
// differs between Play API notes, so both the line item and the purchase are
// read; confirmed only in sandbox).
export function googleFreeTrial(
  record: Record<string, unknown>,
  line: Record<string, unknown>,
): boolean {
  const offer = line.offerDetails as { offerTags?: unknown } | undefined;
  const tags = Array.isArray(offer?.offerTags) ? offer.offerTags : [];
  const phase = (line.offerPhase ?? record.offerPhase) as
    | Record<string, unknown>
    | undefined;
  return tags.includes(MOTION_PLUS_TRIAL_OFFER_TAG) ||
    (typeof phase === "object" && phase !== null && "freeTrial" in phase);
}

export async function verifyGooglePurchase(
  evidence: StoreEvidence,
): Promise<ProviderVerifiedPurchase[]> {
  const token = evidence.verificationData;
  if (!token || token.length > 4096) return [];
  const packageName = `com.yulalab.${evidence.originatingAppId}`;
  const accessToken = await googleAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${
      encodeURIComponent(token)
    }`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (response.status === 404) return [];
  if (!response.ok) throw new Error("Google purchase lookup failed");
  const data: unknown = await response.json();
  if (typeof data !== "object" || data === null) return [];
  const record = data as Record<string, unknown>;
  const state = googleState(record.subscriptionState);
  const external = record.externalAccountIdentifiers;
  if (
    !state || typeof external !== "object" || external === null ||
    !Array.isArray(record.lineItems)
  ) return [];
  const accountMarker = (external as Record<string, unknown>)
    .obfuscatedExternalAccountId;
  if (typeof accountMarker !== "string") return [];
  const claims: ProviderVerifiedPurchase[] = [];
  for (const raw of record.lineItems) {
    if (typeof raw !== "object" || raw === null) continue;
    const line = raw as Record<string, unknown>;
    const offer = line.offerDetails;
    if (typeof offer !== "object" || offer === null) continue;
    const basePlanId = (offer as Record<string, unknown>).basePlanId;
    if (
      typeof line.productId !== "string" ||
      typeof line.expiryTime !== "string" ||
      typeof basePlanId !== "string" ||
      !purchaseScope(
        "google",
        evidence.originatingAppId,
        line.productId,
        basePlanId,
      )
    ) continue;
    claims.push({
      store: "google",
      originatingAppId: evidence.originatingAppId,
      productId: line.productId,
      basePlanId,
      accountMarker,
      reference: token,
      state,
      expiresAt: line.expiryTime,
      freeTrial: googleFreeTrial(record, line),
    });
  }
  return claims;
}
