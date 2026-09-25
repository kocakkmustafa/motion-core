import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  entitlementWriteFromProvider,
  isMotionAppId,
  type MotionAppId,
  type MotionStore,
  originatingAppForStoredProduct,
} from "../_shared/motion_purchase_claim.ts";
import {
  StoreConfigurationError,
  verifyApplePurchase,
  verifyGooglePurchase,
} from "../_shared/motion_store_provider.ts";
import { reviewGrantIsActive } from "../_shared/motion_review_access.ts";

interface StoredEntitlement {
  user_id: string;
  app_id: string;
  store: MotionStore;
  product_id: string;
  original_transaction_id: string;
}

function response(error: string, status: number): Response {
  return Response.json({ error }, { status });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response("method_not_allowed", 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return response("unauthorized", 401);
  }
  let appId: MotionAppId;
  try {
    const raw = await request.text();
    if (raw.length > 200) return response("invalid_request", 400);
    const body: unknown = JSON.parse(raw);
    if (
      typeof body !== "object" || body === null ||
      !("appId" in body) || !isMotionAppId(body.appId)
    ) return response("invalid_request", 400);
    appId = body.appId;
  } catch {
    return response("invalid_request", 400);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) {
    return response("server_unavailable", 503);
  }
  const auth = createClient(url, publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error: authError } = await auth.auth.getUser(
    authorization.slice("Bearer ".length),
  );
  if (authError || !data.user) return response("unauthorized", 401);
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const now = new Date();
  const { data: reviewGrant, error: reviewLookupError } = await admin
    .from("motion_store_review_access")
    .select("user_id,purpose,expires_at")
    .eq("user_id", data.user.id)
    .maybeSingle();
  if (reviewLookupError) return response("membership_unavailable", 503);
  if (reviewGrantIsActive(reviewGrant, data.user.id, now)) {
    return Response.json({ active: true, anyActive: true });
  }
  const recentExpiry = new Date(now.getTime() - 45 * 24 * 60 * 60 * 1000);
  const { data: rows, error: lookupError } = await admin
    .from("motion_entitlements")
    .select("user_id,app_id,store,product_id,original_transaction_id")
    .eq("user_id", data.user.id)
    .in("state", ["active", "grace", "expired"])
    .gte("expires_at", recentExpiry.toISOString())
    .limit(21);
  if (lookupError || !rows || rows.length > 20) {
    return response("membership_unavailable", 503);
  }

  let active = false;
  let anyActive = false;
  for (const rawRow of rows) {
    const row = rawRow as StoredEntitlement;
    if (row.store !== "apple" && row.store !== "google") {
      return response("membership_unavailable", 503);
    }
    const origin = originatingAppForStoredProduct(row.store, row.product_id);
    if (!origin || !row.original_transaction_id) {
      return response("membership_unavailable", 503);
    }
    let claims;
    try {
      const evidence = {
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
        ? await verifyApplePurchase(evidence)
        : await verifyGooglePurchase(evidence);
    } catch (error) {
      return response(
        error instanceof StoreConfigurationError
          ? "store_not_configured"
          : "store_unavailable",
        503,
      );
    }
    const matching = claims.filter(
      (claim) => claim.reference === row.original_transaction_id,
    );
    if (matching.length > 1) return response("membership_unavailable", 503);
    if (matching.length === 0) {
      // A provider-confirmed missing transaction must not retain an older
      // active row until its original expiry or be retried every refresh.
      const { error } = await admin.from("motion_entitlements")
        .update({
          state: "revoked",
          expires_at: now.toISOString(),
          verified_at: now.toISOString(),
        })
        .eq("store", row.store)
        .eq("original_transaction_id", row.original_transaction_id)
        .eq("user_id", data.user.id);
      if (error) return response("membership_unavailable", 503);
      continue;
    }
    const verified = await entitlementWriteFromProvider(
      matching[0],
      data.user.id,
      now,
    );
    if (!verified) {
      // Account token mismatch or unsupported product is an explicit denial.
      const { error } = await admin.from("motion_entitlements")
        .update({
          state: "revoked",
          expires_at: now.toISOString(),
          verified_at: now.toISOString(),
        })
        .eq("store", row.store)
        .eq("original_transaction_id", row.original_transaction_id)
        .eq("user_id", data.user.id);
      if (error) return response("membership_unavailable", 503);
      continue;
    }
    const { error: updateError } = await admin.from("motion_entitlements")
      .update(verified)
      .eq("store", row.store)
      .eq("original_transaction_id", row.original_transaction_id)
      .eq("user_id", data.user.id);
    if (updateError) return response("membership_unavailable", 503);
    if (
      (verified.state === "active" || verified.state === "grace") &&
      new Date(verified.expires_at) > now
    ) {
      anyActive = true;
      if (verified.app_id === appId || verified.app_id === "motion_plus") {
        active = true;
      }
    }
  }
  return Response.json({ active, anyActive });
});
