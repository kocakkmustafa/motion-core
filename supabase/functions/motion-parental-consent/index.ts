import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import { consentEmail } from "../_shared/motion_consent_copy.ts";
import { allowedOrigins, preflight, withCors } from "../_shared/motion_cors.ts";
import {
  sendSmtpMail,
  type SmtpConfig,
  smtpConfigFromEnv,
} from "../_shared/motion_smtp.ts";

// Parental/guardian consent for a Motion teen account below its country's
// digital-consent age. Three actions:
//   request (teen bearer token): mail one approval link to the parent.
//   view (token): masked request summary for the consent page.
//   decide (token): approve opens account features; deny deletes the account.
// The parent address is never stored in clear; the link token only as digest.
// Mail goes out through Google Workspace SMTP (465, implicit TLS; see
// _shared/motion_smtp.ts). Without a complete MOTION_SMTP_* configuration the
// request fails closed with mail_unavailable.
// The consent page calls view/decide from the browser: origins listed in
// MOTION_CONSENT_ALLOWED_ORIGINS (default https://yulalab.com) get CORS.

const TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const RESEND_AFTER_MS = 10 * 60 * 1000;
const MAX_REQUESTS_PER_DAY = 5;
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
  smtp: SmtpConfig | null;
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
    smtp: smtpConfigFromEnv(),
    pageUrl: Deno.env.get("MOTION_CONSENT_PAGE_URL") ??
      "https://yulalab.com/motion/consent",
  };
}

function sendMail(
  env: Env,
  to: string,
  subject: string,
  text: string,
): Promise<boolean> {
  if (!env.smtp) return Promise.resolve(false);
  return sendSmtpMail(env.smtp, { to, subject, text });
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

async function findByToken(env: Env, linkToken: unknown) {
  if (typeof linkToken !== "string" || linkToken.length < 32) return null;
  const admin = createClient(env.url, env.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data } = await admin
    .from("motion_parental_consents")
    .select("user_id,status,expires_at,locale")
    .eq("token_digest", await digest(linkToken))
    .maybeSingle();
  return data ? { admin, row: data } : null;
}

async function handleView(
  env: Env,
  body: Record<string, unknown>,
): Promise<Response> {
  const found = await findByToken(env, body.token);
  if (!found) return Response.json({ error: "invalid_link" }, { status: 404 });
  const { admin, row } = found;
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
  const { admin, row } = found;
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
    default:
      return Response.json({ error: "invalid_action" }, { status: 400 });
  }
}
