import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  createOfferEligibilityHandler,
  signIntroductoryOfferDenial,
} from "../_shared/motion_offer_eligibility.ts";
import { motionPlusTrialUsed } from "../_shared/motion_trial_ledger.ts";

// POST {appId, productId, appTransactionId} with the Motion bearer token.
// → {trialAvailable: true} or {trialAvailable: false,
//    introductoryOfferEligibilityJws} (App Store Motion+ products only).

function clients() {
  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) return null;
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  return {
    auth: createClient(url, publishable, options),
    admin: createClient(url, serviceKey, options),
  };
}

Deno.serve(createOfferEligibilityHandler({
  async authenticate(token) {
    const c = clients();
    if (!c) return null;
    const { data, error } = await c.auth.auth.getUser(token);
    return error || !data.user ? null : data.user.id;
  },
  trialUsed(userId) {
    const c = clients();
    return c ? motionPlusTrialUsed(c.admin, userId) : Promise.resolve(null);
  },
  signDenial: (appId, productId, appTransactionId) =>
    signIntroductoryOfferDenial(appId, productId, appTransactionId),
}));
