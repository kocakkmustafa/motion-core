import {
  type ProviderVerifiedPurchase,
  purchaseScope,
} from "./motion_purchase_claim.ts";

// One Motion+ free trial per Motion account (migration 20261025120000).

/** The minimal admin-client surface used here. */
export interface LedgerTable {
  // deno-lint-ignore no-explicit-any
  from(table: "motion_trial_ledger"): any;
}

/**
 * Records a store-verified Motion+ free-trial purchase for the account. The
 * first record wins (later ones are ignored). Returns false only when the
 * write failed; non-trial or non-Motion+ claims need no record.
 */
export async function recordMotionPlusTrial(
  admin: LedgerTable,
  userId: string,
  claim: ProviderVerifiedPurchase,
): Promise<boolean> {
  if (!claim.freeTrial) return true;
  const scope = purchaseScope(
    claim.store,
    claim.originatingAppId,
    claim.productId,
    claim.basePlanId,
  );
  if (scope !== "motion_plus") return true;
  const { error } = await admin.from("motion_trial_ledger").upsert({
    user_id: userId,
    scope: "motion_plus",
    store: claim.store,
    app_id: claim.originatingAppId,
    original_transaction_id: claim.reference,
  }, { onConflict: "user_id", ignoreDuplicates: true });
  return !error;
}

/** True when the account already used its Motion+ trial; null on error. */
export async function motionPlusTrialUsed(
  admin: LedgerTable,
  userId: string,
): Promise<boolean | null> {
  const { data, error } = await admin.from("motion_trial_ledger")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) return null;
  return data !== null;
}
