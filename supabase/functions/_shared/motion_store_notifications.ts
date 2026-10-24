import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { motionAppIds } from "./motion_purchase_claim.ts";
import type {
  RefreshResult,
  StoredEntitlement,
} from "./motion_entitlement_refresh.ts";
import {
  appleApps,
  appleRootCertificates,
  StoreConfigurationError,
} from "./motion_store_provider.ts";

// Store server notifications (App Store Server Notifications V2, Google Play
// Real-time developer notifications). Every request must prove its origin
// before anything else runs: Apple's JWS chain to the Apple root CAs, or a
// Google-signed OIDC token for the configured push audience and service
// account. A verified notification is only a trigger: the matching stored
// rows are re-verified with the store, never written from the payload.

export type AppleNotice =
  | { kind: "test" }
  | { kind: "transaction"; originalTransactionId: string }
  | { kind: "other" };

export interface NotificationDeps {
  /** Verified notice, or null when the signature/app/environment is invalid. */
  verifyApple(signedPayload: string): Promise<AppleNotice | null>;
  /** Google's current OIDC signing keys (JWKS `keys`). */
  googleKeys(): Promise<JsonWebKey[]>;
  env(name: string): string | undefined;
  /** Rows for one store transaction; null on a database error. */
  findRows(
    store: "apple" | "google",
    originalTransactionId: string,
  ): Promise<StoredEntitlement[] | null>;
  refresh(row: StoredEntitlement, now: Date): Promise<RefreshResult>;
  now(): Date;
}

const MAX_BODY = 256 * 1024;
const GOOGLE_ISSUERS = new Set([
  "https://accounts.google.com",
  "accounts.google.com",
]);
const packageApps = new Set(motionAppIds.map((app) => `com.yulalab.${app}`));

function json(body: unknown, status: number): Response {
  return Response.json(body, { status });
}

function base64UrlBytes(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "===".slice((value.length + 3) % 4);
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function base64UrlJson(value: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(new TextDecoder().decode(base64UrlBytes(value)));
    return typeof parsed === "object" && parsed !== null ? parsed : null;
  } catch {
    return null;
  }
}

async function readBody(request: Request): Promise<unknown> {
  const text = await request.text();
  if (text.length > MAX_BODY) throw new Error("too large");
  return JSON.parse(text);
}

/**
 * Verifies a Google-signed OIDC token (RS256) for the Pub/Sub push
 * subscription: issuer, audience, service account e-mail, expiry.
 */
export async function verifyGoogleOidc(
  token: string,
  keys: JsonWebKey[],
  audience: string,
  serviceAccount: string,
  now: Date,
): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 3) return false;
  const header = base64UrlJson(parts[0]);
  const claims = base64UrlJson(parts[1]);
  if (!header || !claims || header.alg !== "RS256") return false;
  const key = keys.find((candidate) =>
    (candidate as { kid?: string }).kid === header.kid &&
    candidate.kty === "RSA"
  );
  if (!key) return false;
  let valid = false;
  try {
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      { kty: key.kty, n: key.n, e: key.e, alg: "RS256", ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      base64UrlBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    return false;
  }
  const seconds = now.getTime() / 1000;
  return valid &&
    typeof claims.iss === "string" && GOOGLE_ISSUERS.has(claims.iss) &&
    claims.aud === audience &&
    claims.email === serviceAccount &&
    claims.email_verified === true &&
    typeof claims.exp === "number" && claims.exp > seconds - 60 &&
    typeof claims.iat === "number" && claims.iat < seconds + 60;
}

async function refreshTransaction(
  deps: NotificationDeps,
  store: "apple" | "google",
  originalTransactionId: string,
): Promise<Response> {
  const rows = await deps.findRows(store, originalTransactionId);
  if (rows === null) return json({ error: "server_unavailable" }, 503);
  const now = deps.now();
  for (const row of rows) {
    const result = await deps.refresh(row, now);
    // A non-2xx answer makes Apple / Pub/Sub retry the delivery later.
    if (!result.ok) return json({ error: result.error }, 503);
    if (!result.trialRecorded) {
      return json({ error: "server_unavailable" }, 503);
    }
  }
  // An unknown transaction is fine: the app's verify call records it.
  return json({ ok: true, refreshed: rows.length }, 200);
}

async function handleApple(
  request: Request,
  deps: NotificationDeps,
): Promise<Response> {
  let signedPayload: unknown;
  try {
    signedPayload = (await readBody(request) as { signedPayload?: unknown })
      ?.signedPayload;
  } catch {
    return json({ error: "unauthorized" }, 401);
  }
  if (typeof signedPayload !== "string" || signedPayload.length > MAX_BODY) {
    return json({ error: "unauthorized" }, 401);
  }
  let notice: AppleNotice | null;
  try {
    notice = await deps.verifyApple(signedPayload);
  } catch (error) {
    return json(
      {
        error: error instanceof StoreConfigurationError
          ? "store_not_configured"
          : "store_unavailable",
      },
      503,
    );
  }
  if (!notice) return json({ error: "unauthorized" }, 401);
  if (notice.kind !== "transaction") return json({ ok: true }, 200);
  return refreshTransaction(deps, "apple", notice.originalTransactionId);
}

async function handleGoogle(
  request: Request,
  deps: NotificationDeps,
): Promise<Response> {
  const audience = deps.env("MOTION_RTDN_AUDIENCE");
  const serviceAccount = deps.env("MOTION_RTDN_PUSH_SERVICE_ACCOUNT");
  if (!audience || !serviceAccount) {
    return json({ error: "store_not_configured" }, 503);
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }
  let keys: JsonWebKey[];
  try {
    keys = await deps.googleKeys();
  } catch {
    return json({ error: "store_unavailable" }, 503);
  }
  const trusted = await verifyGoogleOidc(
    authorization.slice("Bearer ".length),
    keys,
    audience,
    serviceAccount,
    deps.now(),
  );
  if (!trusted) return json({ error: "unauthorized" }, 401);
  let notification: Record<string, unknown> | null;
  try {
    const body = await readBody(request) as {
      message?: { data?: unknown };
    };
    const data = body?.message?.data;
    if (typeof data !== "string") throw new Error("no data");
    notification = base64UrlJson(data);
  } catch {
    return json({ error: "invalid_request" }, 400);
  }
  if (
    !notification || typeof notification.packageName !== "string" ||
    !packageApps.has(notification.packageName)
  ) return json({ error: "invalid_request" }, 400);
  const subscription = notification.subscriptionNotification as
    | { purchaseToken?: unknown }
    | undefined;
  if (!subscription) return json({ ok: true }, 200); // test / one-time / voided
  const token = subscription.purchaseToken;
  if (typeof token !== "string" || token.length === 0 || token.length > 4096) {
    return json({ error: "invalid_request" }, 400);
  }
  return refreshTransaction(deps, "google", token);
}

export function createNotificationHandler(
  deps: NotificationDeps,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const path = new URL(request.url).pathname;
    if (path.endsWith("/apple")) return handleApple(request, deps);
    if (path.endsWith("/google")) return handleGoogle(request, deps);
    return json({ error: "not_found" }, 404);
  };
}

/**
 * Production Apple verification: the payload's bundle ID and environment
 * choose the verifier, which then checks the x5c chain against the Apple
 * root CAs and requires the same bundle/app/environment inside the payload.
 */
export async function verifyAppleNotification(
  signedPayload: string,
): Promise<AppleNotice | null> {
  const unverified = base64UrlJson(signedPayload.split(".")[1] ?? "");
  const data = unverified?.data as
    | { bundleId?: unknown; environment?: unknown }
    | undefined;
  const app = Object.values(appleApps).find((candidate) =>
    candidate.bundleId === data?.bundleId
  );
  const environment = data?.environment === Environment.PRODUCTION
    ? Environment.PRODUCTION
    : data?.environment === Environment.SANDBOX
    ? Environment.SANDBOX
    : null;
  if (!app || !environment) return null;
  const verifier = new SignedDataVerifier(
    appleRootCertificates(),
    true,
    environment,
    app.bundleId,
    environment === Environment.PRODUCTION ? app.appAppleId : undefined,
  );
  let decoded;
  try {
    decoded = await verifier.verifyAndDecodeNotification(signedPayload);
  } catch {
    return null;
  }
  if (decoded.notificationType === "TEST") return { kind: "test" };
  const signedTransaction = decoded.data?.signedTransactionInfo;
  if (!signedTransaction) return { kind: "other" };
  try {
    const transaction = await verifier.verifyAndDecodeTransaction(
      signedTransaction,
    );
    return transaction.originalTransactionId
      ? {
        kind: "transaction",
        originalTransactionId: transaction.originalTransactionId,
      }
      : { kind: "other" };
  } catch {
    return null;
  }
}

let cachedGoogleKeys: { keys: JsonWebKey[]; until: number } | null = null;

export async function fetchGoogleKeys(): Promise<JsonWebKey[]> {
  if (cachedGoogleKeys && cachedGoogleKeys.until > Date.now()) {
    return cachedGoogleKeys.keys;
  }
  const response = await fetch("https://www.googleapis.com/oauth2/v3/certs");
  if (!response.ok) throw new Error("Google certificates unavailable");
  const body = await response.json() as { keys?: JsonWebKey[] };
  if (!Array.isArray(body.keys)) throw new Error("Google certificates invalid");
  cachedGoogleKeys = { keys: body.keys, until: Date.now() + 60 * 60 * 1000 };
  return body.keys;
}
