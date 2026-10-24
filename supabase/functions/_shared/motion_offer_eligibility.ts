import { IntroductoryOfferEligibilitySignatureCreator } from "npm:@apple/app-store-server-library@3.1.0";
import { isMotionAppId, type MotionAppId } from "./motion_purchase_claim.ts";
import { appleApps, StoreConfigurationError } from "./motion_store_provider.ts";

// One Motion+ free trial per Motion account on the App Store. Each app's
// Motion+ is in its own subscription group, so Apple would offer the trial
// again in every app. After the account's first Motion+ trial the server
// signs `allowIntroductoryOffer=false` for StoreKit 2's
// Product.PurchaseOption.introductoryOfferEligibility(compactJWS:), which the
// app passes with the purchase. Before that, nothing is signed and Apple's own
// eligibility applies.

export interface OfferEligibilityDeps {
  /** Authenticated Motion user ID for the bearer token, or null. */
  authenticate(token: string): Promise<string | null>;
  /** True when the account used its Motion+ trial; null on error. */
  trialUsed(userId: string): Promise<boolean | null>;
  /** Signs the denial for this app's product and the customer's transaction. */
  signDenial(
    appId: MotionAppId,
    productId: string,
    appTransactionId: string,
  ): string;
}

const TRANSACTION_ID = /^[0-9A-Za-z_-]{1,64}$/;

function json(body: unknown, status: number): Response {
  return Response.json(body, { status });
}

export function createOfferEligibilityHandler(
  deps: OfferEligibilityDeps,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "unauthorized" }, 401);
    }
    let body: Record<string, unknown>;
    try {
      const raw = await request.text();
      if (raw.length > 1024) throw new Error("too large");
      body = JSON.parse(raw);
    } catch {
      return json({ error: "invalid_request" }, 400);
    }
    const { appId, productId, appTransactionId } = body ?? {};
    if (
      !isMotionAppId(appId) ||
      (productId !== `com.yulalab.${appId}.motionplus.monthly` &&
        productId !== `com.yulalab.${appId}.motionplus.yearly`) ||
      typeof appTransactionId !== "string" ||
      !TRANSACTION_ID.test(appTransactionId)
    ) return json({ error: "invalid_request" }, 400);
    const userId = await deps.authenticate(
      authorization.slice("Bearer ".length),
    );
    if (!userId) return json({ error: "unauthorized" }, 401);
    const used = await deps.trialUsed(userId);
    if (used === null) return json({ error: "server_unavailable" }, 503);
    if (!used) return json({ trialAvailable: true }, 200);
    try {
      return json({
        trialAvailable: false,
        introductoryOfferEligibilityJws: deps.signDenial(
          appId,
          productId as string,
          appTransactionId,
        ),
      }, 200);
    } catch (error) {
      return json({
        error: error instanceof StoreConfigurationError
          ? "store_not_configured"
          : "server_unavailable",
      }, 503);
    }
  };
}

/** Production signer: the App Store Connect In-App Purchase key (ES256). */
export function signIntroductoryOfferDenial(
  appId: MotionAppId,
  productId: string,
  appTransactionId: string,
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): string {
  const key = env("MOTION_APPLE_IAP_PRIVATE_KEY");
  const keyId = env("MOTION_APPLE_IAP_KEY_ID");
  const issuer = env("MOTION_APPLE_IAP_ISSUER_ID");
  if (!key || !keyId || !issuer) {
    throw new StoreConfigurationError("App Store signing key is missing");
  }
  return new IntroductoryOfferEligibilitySignatureCreator(
    key.replaceAll("\\n", "\n"),
    keyId,
    issuer,
    appleApps[appId].bundleId,
  ).createSignature(productId, false, appTransactionId);
}
