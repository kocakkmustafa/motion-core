import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import { consentEmail } from "../_shared/motion_consent_copy.ts";
import { deviceConsentEmail } from "../_shared/motion_device_consent_copy.ts";
import { allowedOrigins, preflight, withCors } from "../_shared/motion_cors.ts";
import {
  readSmtpConfig,
  type SmtpConfigRead,
  type SmtpOutcome,
  submitSmtpMail,
} from "../_shared/motion_smtp.ts";

// Parental/guardian consent for a Motion teen account below its country's
// digital-consent age. Three actions:
//   request (teen bearer token): mail one approval link to the parent.
//   view (token): masked request summary for the consent page.
//   decide (token): approve opens account features; deny deletes the account.
// Under-13 device path (no account, no session; VELI-01 / ADR-008):
//   request_device {deviceToken, parentEmail, locale}: mail one link.
//   status {deviceToken}: the device reads none/pending/approved/denied/expired.
//   withdraw {token}: the parent withdraws an approved account consent.
// view/decide also accept a device link. Only digests are stored; the parent
// digest goes when the parent decides. A denial leaves the token digest until
// the device reads it (or 30 days) and one anonymous decision row.
// The parent address is never stored in clear; the link token only as digest.
// Mail goes out through Google Workspace SMTP (465, implicit TLS; see
// _shared/motion_smtp.ts). Without a complete MOTION_SMTP_* configuration the
// request fails closed with mail_unavailable. A failed mail logs one
// secret-free line (failure class, stage, reply code or the missing variable's
// name); the response stays 503 mail_unavailable.
// The consent page calls view/decide from the browser: origins listed in
// MOTION_CONSENT_ALLOWED_ORIGINS (default https://yulalab.com and
// https://www.yulalab.com) get CORS.

const TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const RESEND_AFTER_MS = 10 * 60 * 1000;
const MAX_REQUESTS_PER_DAY = 5;
const DEVICE_TOKEN = /^[A-Za-z0-9_-]{43,128}$/;
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{2,63}$/;

async function digest(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  if (!local || !domain) return "***";
  return `${local[0]}***@${domain}`;
}

type Env = {
  url: string;
  publishable: string;
  serviceKey: string;
  smtp: SmtpConfigRead;
  pageUrl: string;
};

function readEnv(): Env | null {
  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) return null;
  return {
    url,
    publishable,
    serviceKey,
    smtp: readSmtpConfig(),
    pageUrl: Deno.env.get("MOTION_CONSENT_PAGE_URL") ??
      "https://yulalab.com/motion/consent",
  };
}

// Never the address, subject, link or SMTP reply text: only the outcome.
export function mailFailureLog(
  outcome: Exclude<SmtpOutcome, { ok: true }>,
  issue?: string,
): string {
  return JSON.stringify({
    event: "motion_consent_mail_failed",
    failure: outcome.failure,
    stage: outcome.stage,
    ...(outcome.code === undefined ? {} : { code: outcome.code }),
    ...(issue === undefined ? {} : { issue }),
  });
}

async function sendMail(
  env: Env,
  to: string,
  subject: string,
  text: string,
): Promise<boolean> {
  if (!env.smtp.config) {
    console.error(
      mailFailureLog(
        { ok: false, failure: "config", stage: "config" },
        env.smtp.issue,
      ),
    );
    return false;
  }
  const outcome = await submitSmtpMail(env.smtp.config, { to, subject, text });
  if (!outcome.ok) console.error(mailFailureLog(outcome));
  return outcome.ok;
}

async function handleRequest(
  env: Env,
  authorization: string | null,
  body: Record<string, unknown>,
): Promise<Response> {
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  const parentEmail = typeof body.parentEmail === "string"
    ? body.parentEmail.trim().toLowerCase()
    : "";
  const locale = typeof body.locale === "string" &&
      /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8})?$/.test(body.locale)
    ? body.locale
    : "en";
  if (!EMAIL.test(parentEmail)) {
    return Response.json({ error: "invalid_parent_email" }, { status: 400 });
  }
  const auth = createClient(env.url, env.publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data, error } = await auth.auth.getUser(token);
  if (error || !data.user) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  const teen = data.user;
  if (teen.email && teen.email.toLowerCase() === parentEmail) {
    return Response.json({ error: "parent_email_is_teen" }, { status: 400 });
  }
  const admin = createClient(env.url, env.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: restricted, error: restrictedError } = await admin.rpc(
    "motion_account_restricted",
    { p_user_id: teen.id },
  );
  if (restrictedError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (restricted !== true) {
    return Response.json({ error: "consent_not_required" }, { status: 409 });
  }
  const { data: existing } = await admin
    .from("motion_parental_consents")
    .select("status,requested_at,requests_today,requests_day")
    .eq("user_id", teen.id)
    .maybeSingle();
  const now = Date.now();
  const today = new Date(now).toISOString().slice(0, 10);
  const requestsToday = existing?.requests_day === today
    ? Number(existing.requests_today ?? 0)
    : 0;
  if (existing?.status === "approved") {
    return Response.json({ error: "already_approved" }, { status: 409 });
  }
  // A withdrawn consent is final (database trigger too): no new pending.
  if (existing?.status === "withdrawn") {
    return Response.json({ error: "already_decided" }, { status: 409 });
  }
  if (
    existing?.status === "pending" &&
    now - Date.parse(existing.requested_at) < RESEND_AFTER_MS
  ) {
    return Response.json({ error: "too_soon" }, { status: 429 });
  }
  if (requestsToday >= MAX_REQUESTS_PER_DAY) {
    return Response.json({ error: "daily_limit" }, { status: 429 });
  }

  const linkToken = randomToken();
  const expiresAt = new Date(now + TOKEN_TTL_MS).toISOString();
  // Fragment: the token never reaches a web server access log.
  const link = `${env.pageUrl}#token=${linkToken}`;
  const copy = consentEmail(locale, {
    link,
    expiresAt: expiresAt.slice(0, 10),
  });
  if (!(await sendMail(env, parentEmail, copy.subject, copy.text))) {
    return Response.json({ error: "mail_unavailable" }, { status: 503 });
  }
  const { error: writeError } = await admin
    .from("motion_parental_consents")
    .upsert({
      user_id: teen.id,
      status: "pending",
      parent_email_digest: await digest(parentEmail),
      token_digest: await digest(linkToken),
      manage_digest: await digest(linkToken),
      locale,
      requested_at: new Date(now).toISOString(),
      expires_at: expiresAt,
      decided_at: null,
      requests_today: requestsToday + 1,
      requests_day: today,
    });
  if (writeError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  return Response.json({ status: "pending", expiresAt });
}

function adminClient(env: Env) {
  return createClient(env.url, env.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function findByToken(env: Env, linkToken: unknown) {
  if (typeof linkToken !== "string" || linkToken.length < 32) return null;
  const admin = adminClient(env);
  const hashed = await digest(linkToken);
  const { data } = await admin
    .from("motion_parental_consents")
    .select("user_id,status,expires_at,locale")
    .eq("token_digest", hashed)
    .maybeSingle();
  if (data) return { admin, row: data, device: null };
  const { data: device } = await admin
    .from("motion_device_consents")
    .select("device_token_digest,status,expires_at,locale")
    .eq("link_digest", hashed)
    .maybeSingle();
  return device ? { admin, row: null, device } : null;
}

async function handleView(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  const found = await findByToken(env, body.token);
  if (!found) return Response.json({ error: "invalid_link" }, { status: 404 });
  const { admin, row, device } = found;
  if (device) {
    if (
      device.status !== "pending" || Date.parse(device.expires_at) < Date.now()
    ) {
      return Response.json({ status: "expired" }, { status: 410 });
    }
    return Response.json({
      status: "pending",
      subject: "device",
      expiresAt: device.expires_at,
      locale: device.locale,
    });
  }
  if (row.status !== "pending" || Date.parse(row.expires_at) < Date.now()) {
    return Response.json({ status: "expired" }, { status: 410 });
  }
  const { data } = await admin.auth.admin.getUserById(row.user_id);
  return Response.json({
    status: "pending",
    teenEmail: maskEmail(data.user?.email ?? ""),
    expiresAt: row.expires_at,
    locale: row.locale,
  });
}

type Admin = ReturnType<typeof adminClient>;

// Anonymous trace (status + week + method, no key). Written only after the
// state change took effect, so a double decision leaves one row. A failed
// trace is logged without any secret; the decision itself stands.
async function recordDecision(
  admin: Admin,
  status: "approved" | "denied" | "withdrawn",
) {
  const { error } = await admin
    .from("motion_consent_decisions")
    .insert({ status, method: "email_link" });
  if (error) {
    console.error(JSON.stringify({ event: "motion_consent_trace_failed" }));
  }
}

async function decideDevice(
  admin: Admin,
  device: { device_token_digest: string },
  decision: "approve" | "deny",
): Promise<Response> {
  const approved = decision === "approve";
  const { data, error } = await admin
    .from("motion_device_consents")
    .update({
      status: approved ? "approved" : "denied",
      parent_email_digest: null,
      ...(approved ? {} : { link_digest: null }),
      decided_at: new Date().toISOString(),
    })
    .eq("device_token_digest", device.device_token_digest)
    .eq("status", "pending")
    .select("device_token_digest");
  if (error) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!data || data.length === 0) {
    return Response.json({ status: "expired" }, { status: 410 });
  }
  await recordDecision(admin, approved ? "approved" : "denied");
  return Response.json({ status: approved ? "approved" : "denied" });
}

async function handleDecide(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  const decision = body.decision;
  if (decision !== "approve" && decision !== "deny") {
    return Response.json({ error: "invalid_decision" }, { status: 400 });
  }
  const found = await findByToken(env, body.token);
  if (!found) return Response.json({ error: "invalid_link" }, { status: 404 });
  const { admin, row, device } = found;
  if (device) {
    if (
      device.status !== "pending" || Date.parse(device.expires_at) < Date.now()
    ) {
      return Response.json({ status: "expired" }, { status: 410 });
    }
    return decideDevice(admin, device, decision);
  }
  if (row.status !== "pending" || Date.parse(row.expires_at) < Date.now()) {
    return Response.json({ status: "expired" }, { status: 410 });
  }
  if (decision === "approve") {
    const { error } = await admin
      .from("motion_parental_consents")
      .update({
        status: "approved",
        token_digest: null,
        decided_at: new Date().toISOString(),
      })
      .eq("user_id", row.user_id)
      .eq("status", "pending");
    if (error) {
      return Response.json({ error: "server_unavailable" }, { status: 503 });
    }
    return Response.json({ status: "approved" });
  }
  // Denial removes the teen account entirely (data minimisation). The Auth
  // delete cascades product rows and writes the anonymous deletion receipt.
  const { error } = await admin.auth.admin.deleteUser(row.user_id);
  if (error) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  return Response.json({ status: "denied" });
}

// request_device, status and withdraw ignore the Authorization header: the
// child has no session, nothing here is logged, and no request is tied to an
// identity (a stray bearer neither helps nor hurts).
async function handleRequestDevice(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  const parentEmail = typeof body.parentEmail === "string"
    ? body.parentEmail.trim().toLowerCase()
    : "";
  const locale = typeof body.locale === "string" &&
      /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8})?$/.test(body.locale)
    ? body.locale
    : "en";
  if (!EMAIL.test(parentEmail)) {
    return Response.json({ error: "invalid_parent_email" }, { status: 400 });
  }
  if (
    typeof body.deviceToken !== "string" || !DEVICE_TOKEN.test(body.deviceToken)
  ) {
    return Response.json({ error: "invalid_device_token" }, { status: 400 });
  }
  const admin = adminClient(env);
  const deviceDigest = await digest(body.deviceToken);
  const parentDigest = await digest(parentEmail);
  const { data: existing, error: readError } = await admin
    .from("motion_device_consents")
    .select("status,requested_at,expires_at,created_at")
    .eq("device_token_digest", deviceDigest)
    .maybeSingle();
  if (readError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  const now = Date.now();
  // An approval nobody used within 30 days is dead (consume refuses it): the
  // device may start over, like after an expiry.
  const staleApproval = existing?.status === "approved" &&
    Date.parse(existing.created_at) < now - RETENTION_MS;
  if (existing?.status === "approved" && !staleApproval) {
    return Response.json({ error: "already_approved" }, { status: 409 });
  }
  if (existing?.status === "denied" || existing?.status === "withdrawn") {
    return Response.json({ error: "already_decided" }, { status: 409 });
  }
  if (
    existing?.status === "pending" &&
    now - Date.parse(existing.requested_at) < RESEND_AFTER_MS
  ) {
    return Response.json({ error: "too_soon" }, { status: 429 });
  }
  // Reserve a mail before sending, atomically in the database: at most five
  // per parent address and five per device token per UTC day, counted in
  // append-only day counters that no decision or purge of a consent row
  // touches. A token redirected to other addresses is counted on the token
  // key. Day-keyed, so up to twice that across midnight; no global limit.
  const { data: slot, error: slotError } = await admin.rpc(
    "motion_consent_mail_slot",
    {
      p_keys: [`p:${parentDigest}`, `d:${deviceDigest}`],
      p_limit: MAX_REQUESTS_PER_DAY,
    },
  );
  if (slotError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (slot !== true) {
    return Response.json({ error: "daily_limit" }, { status: 429 });
  }
  const slotKeys = [`p:${parentDigest}`, `d:${deviceDigest}`];
  // Best effort, atomic in the database: give the slot back when no mail
  // went out or the request lost a race it did not cause.
  const releaseSlot = async () => {
    await admin.rpc("motion_consent_mail_slot_release", { p_keys: slotKeys });
  };

  const linkToken = randomToken();
  const expiresAt = new Date(now + TOKEN_TTL_MS).toISOString();
  const link = `${env.pageUrl}#token=${linkToken}`;
  const copy = deviceConsentEmail(locale, {
    link,
    expiresAt: expiresAt.slice(0, 10),
  });
  if (!(await sendMail(env, parentEmail, copy.subject, copy.text))) {
    await releaseSlot();
    return Response.json({ error: "mail_unavailable" }, { status: 503 });
  }
  // State-guarded write: a row decided since the read above stays decided.
  const { data: outcome, error: writeError } = await admin.rpc(
    "motion_device_consent_request",
    {
      p_device_digest: deviceDigest,
      p_parent_digest: parentDigest,
      p_link_digest: await digest(linkToken),
      p_locale: locale,
      p_expires_at: expiresAt,
    },
  );
  if (writeError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (outcome === "approved") {
    return Response.json({ error: "already_approved" }, { status: 409 });
  }
  if (outcome === "denied" || outcome === "withdrawn") {
    return Response.json({ error: "already_decided" }, { status: 409 });
  }
  if (outcome === "too_soon") {
    await releaseSlot();
    return Response.json({ error: "too_soon" }, { status: 429 });
  }
  if (outcome !== "ok") {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  return Response.json({ status: "pending", expiresAt });
}

async function handleStatus(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  if (
    typeof body.deviceToken !== "string" || !DEVICE_TOKEN.test(body.deviceToken)
  ) {
    return Response.json({ error: "invalid_device_token" }, { status: 400 });
  }
  const admin = adminClient(env);
  const deviceDigest = await digest(body.deviceToken);
  const { data, error } = await admin
    .from("motion_device_consents")
    .select("status,expires_at,decided_at,created_at")
    .eq("device_token_digest", deviceDigest)
    .maybeSingle();
  if (error) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!data) return Response.json({ status: "none" });
  const decidedAt = data.decided_at ? { decidedAt: data.decided_at } : {};
  if (data.status === "denied") {
    // Read once: the device has its answer, drop the token digest now.
    await admin
      .from("motion_device_consents")
      .delete()
      .eq("device_token_digest", deviceDigest)
      .eq("status", "denied");
    return Response.json({ status: "denied", ...decidedAt });
  }
  if (data.status === "withdrawn") {
    return Response.json({ status: "withdrawn", ...decidedAt });
  }
  if (data.status === "approved") {
    // Same 30 day window as motion_consume_device_consent.
    if (Date.parse(data.created_at) < Date.now() - RETENTION_MS) {
      return Response.json({ status: "expired" });
    }
    return Response.json({ status: "approved", ...decidedAt });
  }
  const lapsed = data.status === "expired" ||
    Date.parse(data.expires_at) < Date.now();
  if (lapsed) return Response.json({ status: "expired" });
  return Response.json({ status: "pending", expiresAt: data.expires_at });
}

async function handleWithdraw(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  if (typeof body.token !== "string" || body.token.length < 32) {
    return Response.json({ error: "invalid_link" }, { status: 404 });
  }
  const admin = adminClient(env);
  const manage = await digest(body.token);
  // Two passes: a device approval can be consumed into an account between
  // the lookup and the update; the second pass then finds the account row.
  for (let pass = 0; pass < 2; pass++) {
    const account = await withdrawAccount(admin, manage);
    if (account) return account;
    const device = await withdrawDevice(admin, manage);
    if (device !== "raced") return device;
  }
  return Response.json({ error: "already_decided" }, { status: 409 });
}

// null: no account row for this manage digest.
async function withdrawAccount(
  admin: Admin,
  manage: string,
): Promise<Response | null> {
  const { data, error } = await admin
    .from("motion_parental_consents")
    .select("user_id,status")
    .eq("manage_digest", manage)
    .maybeSingle();
  if (error) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!data) return null;
  if (data.status === "withdrawn") {
    return Response.json({ status: "withdrawn" });
  }
  if (data.status !== "approved") {
    return Response.json({ error: "not_approved" }, { status: 409 });
  }
  const { data: changed, error: updateError } = await admin
    .from("motion_parental_consents")
    .update({ status: "withdrawn", decided_at: new Date().toISOString() })
    .eq("user_id", data.user_id)
    .eq("status", "approved")
    .select("user_id");
  if (updateError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!changed || changed.length === 0) {
    // Changed under us: never claim a withdrawal that did not happen.
    return Response.json({ error: "already_decided" }, { status: 409 });
  }
  await recordDecision(admin, "withdrawn");
  return Response.json({ status: "withdrawn" });
}

// The parent withdraws before the child finished sign-up: the approved device
// row becomes withdrawn and can no longer be consumed (consume takes approved
// only); it is removed with the 30 day clock. "raced": the row vanished or
// changed under the update (e.g. consumed into an account): look again.
async function withdrawDevice(
  admin: Admin,
  linkDigest: string,
): Promise<Response | "raced"> {
  const { data, error } = await admin
    .from("motion_device_consents")
    .select("device_token_digest,status,created_at")
    .eq("link_digest", linkDigest)
    .maybeSingle();
  if (error) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!data) return Response.json({ error: "invalid_link" }, { status: 404 });
  if (data.status === "withdrawn") {
    return Response.json({ status: "withdrawn" });
  }
  if (data.status !== "approved") {
    return Response.json({ error: "not_approved" }, { status: 409 });
  }
  const { data: changed, error: updateError } = await admin
    .from("motion_device_consents")
    .update({ status: "withdrawn", decided_at: new Date().toISOString() })
    .eq("device_token_digest", data.device_token_digest)
    .eq("status", "approved")
    .select("device_token_digest");
  if (updateError) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  if (!changed || changed.length === 0) return "raced";
  await recordDecision(admin, "withdrawn");
  return Response.json({ status: "withdrawn" });
}

Deno.serve(async (request: Request) => {
  const allowed = allowedOrigins(
    Deno.env.get("MOTION_CONSENT_ALLOWED_ORIGINS"),
  );
  if (request.method === "OPTIONS") return preflight(request, allowed);
  return withCors(request, await handle(request), allowed);
});

async function handle(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }
  const env = readEnv();
  if (!env) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }
  if (typeof body !== "object" || body === null) {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }
  const payload = body as Record<string, unknown>;
  switch (payload.action) {
    case "request":
      return handleRequest(env, request.headers.get("Authorization"), payload);
    case "view":
      return handleView(env, payload);
    case "decide":
      return handleDecide(env, payload);
    case "request_device":
      return handleRequestDevice(env, payload);
    case "status":
      return handleStatus(env, payload);
    case "withdraw":
      return handleWithdraw(env, payload);
    default:
      return Response.json({ error: "invalid_action" }, { status: 400 });
  }
}
