import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  refreshStoredEntitlement,
  type StoredEntitlement,
} from "../_shared/motion_entitlement_refresh.ts";
import {
  createNotificationHandler,
  fetchGoogleKeys,
  verifyAppleNotification,
} from "../_shared/motion_store_notifications.ts";

// App Store Server Notifications V2 → POST …/motion-store-notifications/apple
// Google Play RTDN (Pub/Sub push, OIDC) → POST …/motion-store-notifications/google
// verify_jwt=false: the stores authenticate with their own signatures.

function admin() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

Deno.serve(createNotificationHandler({
  verifyApple: verifyAppleNotification,
  googleKeys: fetchGoogleKeys,
  env: (name) => Deno.env.get(name),
  now: () => new Date(),
  async findRows(store, originalTransactionId) {
    const client = admin();
    if (!client) return null;
    const { data, error } = await client.from("motion_entitlements")
      .select("user_id,app_id,store,product_id,original_transaction_id")
      .eq("store", store)
      .eq("original_transaction_id", originalTransactionId)
      .limit(5);
    return error ? null : (data ?? []) as StoredEntitlement[];
  },
  refresh(row, now) {
    const client = admin();
    if (!client) {
      return Promise.resolve({ ok: false, error: "membership_unavailable" });
    }
    return refreshStoredEntitlement(client, row, now);
  },
}));
