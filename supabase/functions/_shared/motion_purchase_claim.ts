// This module accepts only provider-verified purchase facts. It never parses
// a client receipt or grants a right from a client-supplied user identifier.
export const motionAppIds = [
  "ostinato",
  "gravita",
  "choreia",
  "jablab",
  "lissom",
] as const;

export type MotionAppId = (typeof motionAppIds)[number];
export type MotionStore = "apple" | "google";
export type ProviderState =
  | "active"
  | "grace"
  | "canceled"
  | "expired"
  | "hold"
  | "revoked";

export interface ProviderVerifiedPurchase {
  store: MotionStore;
  originatingAppId: MotionAppId;
  productId: string;
  basePlanId?: string;
  accountMarker: string;
  reference: string;
  state: ProviderState;
  expiresAt: string;
}

export interface EntitlementWrite {
  user_id: string;
  app_id: MotionAppId | "motion_plus";
  store: MotionStore;
  product_id: string;
  original_transaction_id: string;
  state: "active" | "grace" | "expired" | "revoked";
  expires_at: string;
  verified_at: string;
}

const userIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isMotionAppId(value: unknown): value is MotionAppId {
  return typeof value === "string" &&
    motionAppIds.some((candidate) => candidate === value);
}

export function originatingAppForStoredProduct(
  store: MotionStore,
  productId: string,
): MotionAppId | null {
  for (const appId of motionAppIds) {
    if (
      store === "apple" &&
      (productId === `com.yulalab.${appId}.individual.monthly` ||
        productId === `com.yulalab.${appId}.individual.yearly` ||
        productId === `com.yulalab.${appId}.motionplus.monthly` ||
        productId === `com.yulalab.${appId}.motionplus.yearly`)
    ) return appId;
    if (
      store === "google" &&
      (productId === `${appId}_individual` ||
        productId === `${appId}_motion_plus`)
    ) return appId;
  }
  return null;
}

export async function expectedAccountMarker(
  store: MotionStore,
  userId: string,
): Promise<string | null> {
  if (!userIdPattern.test(userId)) return null;
  const normalized = userId.toLowerCase();
  if (store === "apple") return normalized;
  const bytes = new TextEncoder().encode(normalized);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// The product namespace is fixed in source so an unrelated IAP cannot unlock
// a Motion course. Google base plans are checked separately from product IDs.
export function purchaseScope(
  store: MotionStore,
  originatingAppId: MotionAppId,
  productId: string,
  basePlanId?: string,
): MotionAppId | "motion_plus" | null {
  for (const scope of ["individual", "motionplus"] as const) {
    if (store === "apple") {
      for (const period of ["monthly", "yearly"] as const) {
        if (
          productId ===
            `com.yulalab.${originatingAppId}.${scope}.${period}`
        ) return scope === "motionplus" ? "motion_plus" : originatingAppId;
      }
    } else if (
      productId ===
        `${originatingAppId}_${
          scope === "motionplus" ? "motion_plus" : scope
        }` &&
      (basePlanId === "monthly" || basePlanId === "yearly")
    ) {
      return scope === "motionplus" ? "motion_plus" : originatingAppId;
    }
  }
  return null;
}

export async function entitlementWriteFromProvider(
  purchase: ProviderVerifiedPurchase,
  authenticatedUserId: string,
  now: Date,
): Promise<EntitlementWrite | null> {
  const marker = await expectedAccountMarker(
    purchase.store,
    authenticatedUserId,
  );
  const scope = purchaseScope(
    purchase.store,
    purchase.originatingAppId,
    purchase.productId,
    purchase.basePlanId,
  );
  if (
    marker === null ||
    purchase.accountMarker !== marker ||
    scope === null ||
    purchase.reference.length === 0 ||
    purchase.reference.length > 2048 ||
    !Number.isFinite(now.getTime())
  ) return null;

  const expiry = new Date(purchase.expiresAt);
  if (!Number.isFinite(expiry.getTime())) return null;
  let state: EntitlementWrite["state"];
  if (purchase.state === "revoked") state = "revoked";
  else if (purchase.state === "hold" || purchase.state === "expired") {
    state = "expired";
  } else if (expiry <= now) state = "expired";
  else if (purchase.state === "grace") state = "grace";
  else if (purchase.state === "active" || purchase.state === "canceled") {
    // Google cancellation retains access through its paid expiry.
    state = "active";
  } else return null;

  return {
    user_id: authenticatedUserId,
    app_id: scope,
    store: purchase.store,
    product_id: purchase.productId,
    original_transaction_id: purchase.reference,
    state,
    expires_at: expiry.toISOString(),
    verified_at: now.toISOString(),
  };
}
