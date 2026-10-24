import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  isMotionAppId,
  type MotionAppId,
} from "../_shared/motion_purchase_claim.ts";
import {
  refreshStoredEntitlement,
  type StoredEntitlement,
} from "../_shared/motion_entitlement_refresh.ts";
import { reviewGrantIsActive } from "../_shared/motion_review_access.ts";
import { motionPlusTrialUsed } from "../_shared/motion_trial_ledger.ts";

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
    return Response.json({
      active: true,
      anyActive: true,
      motionPlusTrialAvailable: false,
    });
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
    const result = await refreshStoredEntitlement(
      admin,
      { ...(rawRow as StoredEntitlement), user_id: data.user.id },
      now,
    );
    if (!result.ok) return response(result.error, 503);
    if (result.granting) {
      anyActive = true;
      if (result.appId === appId || result.appId === "motion_plus") {
        active = true;
      }
    }
  }
  // One Motion+ free trial per account (read after the refresh above, which
  // records a newly verified trial). Unknown → no trial is offered.
  const trialUsed = await motionPlusTrialUsed(admin, data.user.id);
  return Response.json({
    active,
    anyActive,
    motionPlusTrialAvailable: trialUsed === false,
  });
});
