import {
  entitlementWriteFromProvider,
  type MotionStore,
  originatingAppForStoredProduct,
  type ProviderVerifiedPurchase,
} from "./motion_purchase_claim.ts";
import {
  StoreConfigurationError,
  type StoreEvidence,
  verifyApplePurchase,
  verifyGooglePurchase,
} from "./motion_store_provider.ts";
import { recordMotionPlusTrial } from "./motion_trial_ledger.ts";

// One stored entitlement row re-verified with its store. Shared by the
// membership check (pull) and the store server notifications (push): a
// notification is only a trigger, the stored row changes only after the
// store itself confirms the current state.

export interface StoredEntitlement {
  user_id: string;
  app_id: string;
  store: MotionStore;
  product_id: string;
  original_transaction_id: string;
}

export type RefreshError =
  | "membership_unavailable"
  | "store_not_configured"
  | "store_unavailable";

export type RefreshResult =
  | {
    ok: true;
    /** Active or grace with a future expiry after this refresh. */
    granting: boolean;
    /** Scope of the refreshed row ("motion_plus" or an app ID); null when revoked. */
    appId: string | null;
    /** The store-verified claim the row was written from, if any. */
    claim: ProviderVerifiedPurchase | null;
    /** False when a verified Motion+ trial could not be recorded. */
    trialRecorded: boolean;
  }
  | { ok: false; error: RefreshError };

export interface StoreVerifiers {
  apple: (evidence: StoreEvidence) => Promise<ProviderVerifiedPurchase[]>;
  google: (evidence: StoreEvidence) => Promise<ProviderVerifiedPurchase[]>;
}

const defaultVerifiers: StoreVerifiers = {
  apple: verifyApplePurchase,
  google: verifyGooglePurchase,
};

/** The minimal admin-client surface this module writes through. */
export interface EntitlementTable {
  // deno-lint-ignore no-explicit-any
  from(table: "motion_entitlements" | "motion_trial_ledger"): any;
}

async function updateRow(
  admin: EntitlementTable,
  row: StoredEntitlement,
  values: Record<string, unknown>,
): Promise<boolean> {
  const { error } = await admin.from("motion_entitlements")
    .update(values)
    .eq("store", row.store)
    .eq("original_transaction_id", row.original_transaction_id)
    .eq("user_id", row.user_id);
  return !error;
}

export async function refreshStoredEntitlement(
  admin: EntitlementTable,
  row: StoredEntitlement,
  now: Date,
  verifiers: StoreVerifiers = defaultVerifiers,
): Promise<RefreshResult> {
  const fail = (error: RefreshError): RefreshResult => ({ ok: false, error });
  if (row.store !== "apple" && row.store !== "google") {
    return fail("membership_unavailable");
  }
  const origin = originatingAppForStoredProduct(row.store, row.product_id);
  if (!origin || !row.original_transaction_id) {
    return fail("membership_unavailable");
  }
  let claims: ProviderVerifiedPurchase[];
  try {
    const evidence: StoreEvidence = {
      originatingAppId: origin,
      productId: row.product_id,
      transactionId: row.store === "apple"
        ? row.original_transaction_id
        : undefined,
      verificationData: row.store === "google"
        ? row.original_transaction_id
        : "",
    };
    claims = row.store === "apple"
      ? await verifiers.apple(evidence)
      : await verifiers.google(evidence);
  } catch (error) {
    return fail(
      error instanceof StoreConfigurationError
        ? "store_not_configured"
        : "store_unavailable",
    );
  }
  const revoked = {
    state: "revoked",
    expires_at: now.toISOString(),
    verified_at: now.toISOString(),
  };
  const matching = claims.filter(
    (claim) => claim.reference === row.original_transaction_id,
  );
  if (matching.length > 1) return fail("membership_unavailable");
  if (matching.length === 0) {
    // A provider-confirmed missing transaction must not retain an older
    // active row until its original expiry or be retried every refresh.
    if (!await updateRow(admin, row, revoked)) {
      return fail("membership_unavailable");
    }
    return {
      ok: true,
      granting: false,
      appId: null,
      claim: null,
      trialRecorded: true,
    };
  }
  const verified = await entitlementWriteFromProvider(
    matching[0],
    row.user_id,
    now,
  );
  if (!verified) {
    // Account token mismatch or unsupported product is an explicit denial.
    if (!await updateRow(admin, row, revoked)) {
      return fail("membership_unavailable");
    }
    return {
      ok: true,
      granting: false,
      appId: null,
      claim: null,
      trialRecorded: true,
    };
  }
  if (!await updateRow(admin, row, { ...verified })) {
    return fail("membership_unavailable");
  }
  return {
    ok: true,
    granting: (verified.state === "active" || verified.state === "grace") &&
      new Date(verified.expires_at) > now,
    appId: verified.app_id,
    claim: matching[0],
    trialRecorded: await recordMotionPlusTrial(admin, row.user_id, matching[0]),
  };
}
