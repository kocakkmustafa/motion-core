import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  entitlementWriteFromProvider,
  isMotionAppId,
} from "../_shared/motion_purchase_claim.ts";
import {
  StoreConfigurationError,
  type StoreEvidence,
  verifyApplePurchase,
  verifyGooglePurchase,
} from "../_shared/motion_store_provider.ts";
import { recordMotionPlusTrial } from "../_shared/motion_trial_ledger.ts";

type PurchaseRequest = StoreEvidence & { store: "apple" | "google" };

function readPurchaseRequest(value: unknown): PurchaseRequest | null {
  if (typeof value !== "object" || value === null) return null;
  const body = value as Record<string, unknown>;
  if (
    !isMotionAppId(body.originatingAppId) ||
    (body.store !== "apple" && body.store !== "google") ||
    typeof body.productId !== "string" ||
    body.productId.length < 1 || body.productId.length > 160 ||
    typeof body.verificationData !== "string" ||
    body.verificationData.length > 200000 ||
    (body.transactionId !== undefined &&
      typeof body.transactionId !== "string")
  ) return null;
  return {
    originatingAppId: body.originatingAppId,
    store: body.store,
    productId: body.productId,
    verificationData: body.verificationData,
    transactionId: body.transactionId as string | undefined,
  };
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  let body: PurchaseRequest | null;
  try {
    const raw = await request.text();
    if (raw.length > 220000) {
      return Response.json({ error: "invalid_request" }, { status: 400 });
    }
    body = readPurchaseRequest(JSON.parse(raw));
  } catch {
    body = null;
  }
  if (!body) {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }

  const auth = createClient(url, publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error: authError } = await auth.auth.getUser(
    authorization.slice("Bearer ".length),
  );
  if (authError || !data.user) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  let verified;
  try {
    verified = body.store === "apple"
      ? await verifyApplePurchase(body)
      : await verifyGooglePurchase(body);
  } catch (error) {
    // Never treat provider timeouts, configuration faults or invalid signed
    // data as an unverified but usable purchase.
    const code = error instanceof StoreConfigurationError
      ? "store_not_configured"
      : "store_unavailable";
    return Response.json({ error: code }, { status: 503 });
  }
  const matching = verified.filter((claim) =>
    claim.productId === body.productId
  );
  if (matching.length !== 1) {
    return Response.json({ error: "purchase_not_verified" }, { status: 403 });
  }
  const row = await entitlementWriteFromProvider(
    matching[0],
    data.user.id,
    new Date(),
  );
  if (!row) {
    return Response.json({ error: "purchase_not_verified" }, { status: 403 });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: existing, error: lookupError } = await admin
    .from("motion_entitlements")
    .select("user_id,app_id,product_id")
    .eq("store", row.store)
    .eq("original_transaction_id", row.original_transaction_id)
    .maybeSingle();
  if (lookupError) {
    return Response.json({ error: "verification_write_failed" }, {
      status: 503,
    });
  }
  if (existing && existing.user_id !== data.user.id) {
    return Response.json({ error: "purchase_account_conflict" }, {
      status: 409,
    });
  }
  const write = existing
    ? admin.from("motion_entitlements")
      .update(row)
      .eq("store", row.store)
      .eq("original_transaction_id", row.original_transaction_id)
      .eq("user_id", data.user.id)
    : admin.from("motion_entitlements")
      .upsert(row, { onConflict: "user_id,app_id,store,product_id" });
  const { error: writeError } = await write;
  // A Motion+ purchase that started a free trial is recorded once per
  // account; a failed record keeps the verification retryable.
  if (
    writeError ||
    !await recordMotionPlusTrial(admin, data.user.id, matching[0])
  ) {
    return Response.json({ error: "verification_write_failed" }, {
      status: 503,
    });
  }
  return Response.json({
    userId: row.user_id,
    appId: row.app_id,
    productId: row.product_id,
    state: row.state,
    expiresAt: row.expires_at,
    lastVerifiedAt: row.verified_at,
  });
});
