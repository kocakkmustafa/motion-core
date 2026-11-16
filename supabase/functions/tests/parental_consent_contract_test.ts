// Exercise the production consent handler with a fixture transport; no remote
// accounts. Mail goes over real SMTP to a loopback fake server (plain text is
// allowed only towards loopback). The parent address never reaches storage.
import {
  consentEmail,
  consentLocales,
} from "../_shared/motion_consent_copy.ts";
import {
  deviceConsentEmail,
  deviceConsentLocales,
} from "../_shared/motion_device_consent_copy.ts";
import { FakeSmtp } from "./fake_smtp.ts";

const teen = "00000000-0000-4000-8000-000000000003";
let handler: (request: Request) => Promise<Response>;
let restricted = true;
const smtp = new FakeSmtp();
const mails = smtp.mails;
let upserts: Record<string, unknown>[] = [];
let updates: Record<string, unknown>[] = [];
let deleted: string[] = [];
let stored: Record<string, unknown> | null = null;
let deviceRows: Record<string, unknown>[] = [];
let decisions: Record<string, unknown>[] = [];
let counters = new Map<string, number>();
let onSlot: (() => void) | undefined;
let authCalls = 0;
let onDevicePatch: (() => void) | undefined;

// PostgREST filters of the fixture: eq.<v> and gte.<v> on any column.
function matches(row: Record<string, unknown>, url: string): boolean {
  for (const [key, raw] of new URL(url).searchParams) {
    if (raw.startsWith("eq.")) {
      if (String(row[key]) !== raw.slice(3)) return false;
    } else if (raw.startsWith("gte.")) {
      if (!(String(row[key]) >= raw.slice(4))) return false;
    }
  }
  return true;
}

Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
Deno.env.set("SUPABASE_ANON_KEY", "fixture-public");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-server");
Deno.env.set("MOTION_SMTP_HOST", "127.0.0.1");
Deno.env.set("MOTION_SMTP_PORT", String(smtp.port));
Deno.env.set("MOTION_SMTP_TLS", "none");
Deno.env.set("MOTION_SMTP_USER", "consent@example.invalid");
Deno.env.set("MOTION_SMTP_PASSWORD", "fixture-app-password");
Deno.env.set("MOTION_MAIL_FROM", "Motion <no-reply@example.invalid>");
Deno.env.set("MOTION_CONSENT_PAGE_URL", "https://example.invalid/consent");
Deno.serve = ((callback: unknown) => {
  handler = callback as typeof handler;
  return {} as Deno.HttpServer;
}) as typeof Deno.serve;

globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = String(input instanceof Request ? input.url : input);
  const method = init?.method ??
    (input instanceof Request ? input.method : "GET");
  const body = init?.body ? JSON.parse(String(init.body)) : undefined;
  if (url.endsWith("/auth/v1/user")) {
    authCalls++;
    return Response.json({
      id: teen,
      aud: "authenticated",
      email: "teen@example.invalid",
      created_at: "2026-10-21T00:00:00Z",
      app_metadata: {},
      user_metadata: {},
    });
  }
  if (url.includes("/auth/v1/admin/users/" + teen)) {
    if (method === "DELETE") {
      deleted.push(teen);
      return Response.json({ id: teen });
    }
    return Response.json({
      id: teen,
      aud: "authenticated",
      email: "teen@example.invalid",
      created_at: "2026-10-21T00:00:00Z",
      app_metadata: {},
      user_metadata: {},
    });
  }
  if (url.endsWith("/rest/v1/rpc/motion_consent_mail_slot")) {
    // Mirrors the SQL: all keys or none, day keyed, never decremented.
    const day = new Date().toISOString().slice(0, 10);
    const keys: string[] = body.p_keys;
    if (keys.some((k) => (counters.get(`${k}|${day}`) ?? 0) >= body.p_limit)) {
      return Response.json(false);
    }
    for (const k of keys) {
      counters.set(`${k}|${day}`, (counters.get(`${k}|${day}`) ?? 0) + 1);
    }
    onSlot?.();
    return Response.json(true);
  }
  if (url.includes("/rest/v1/rpc/motion_consent_mail_slot_release")) {
    const day = new Date().toISOString().slice(0, 10);
    for (const k of body.p_keys as string[]) {
      const at = `${k}|${day}`;
      counters.set(at, Math.max((counters.get(at) ?? 0) - 1, 0));
    }
    return new Response(null, { status: 204 });
  }
  if (url.includes("/rest/v1/rpc/motion_device_consent_request")) {
    // Mirrors the state-guarded upsert of the SQL function.
    const row = deviceRows.find((r) =>
      r.device_token_digest === body.p_device_digest
    );
    const fresh = {
      status: "pending",
      method: "email_link",
      parent_email_digest: body.p_parent_digest,
      link_digest: body.p_link_digest,
      locale: body.p_locale,
      expires_at: body.p_expires_at,
      requested_at: new Date().toISOString(),
      decided_at: null,
    };
    if (!row) {
      deviceRows.push({
        device_token_digest: body.p_device_digest,
        created_at: new Date().toISOString(),
        requests_today: 1,
        ...fresh,
      });
      return Response.json("ok");
    }
    const staleApproval = row.status === "approved" &&
      Date.parse(String(row.created_at)) < Date.now() - 30 * 24 * 60 * 60_000;
    const lapsed = row.status === "expired" || staleApproval ||
      (row.status === "pending" &&
        (String(row.expires_at) < new Date().toISOString() ||
          Date.parse(String(row.requested_at)) <= Date.now() - 10 * 60_000));
    if (!lapsed) {
      return Response.json(row.status === "pending" ? "too_soon" : row.status);
    }
    const restart = row.status === "expired" || staleApproval ||
      String(row.expires_at) < new Date().toISOString();
    Object.assign(row, fresh, {
      requests_today: Number(row.requests_today) + 1,
      ...(restart ? { created_at: new Date().toISOString() } : {}),
    });
    return Response.json("ok");
  }
  if (url.includes("/rest/v1/rpc/motion_account_restricted")) {
    return Response.json(restricted);
  }
  if (url.includes("/rest/v1/motion_device_consents")) {
    if (method === "GET") {
      return Response.json(deviceRows.filter((r) => matches(r, url)));
    }
    if (method === "POST") {
      const at = deviceRows.findIndex((r) =>
        r.device_token_digest === body.device_token_digest
      );
      if (at >= 0) deviceRows[at] = { ...deviceRows[at], ...body };
      else deviceRows.push({ requests_today: 1, ...body });
      return new Response(null, { status: 201 });
    }
    if (method === "PATCH") {
      onDevicePatch?.();
      const hit = deviceRows.filter((r) => matches(r, url));
      for (const r of hit) Object.assign(r, body);
      return Response.json(hit);
    }
    if (method === "DELETE") {
      deviceRows = deviceRows.filter((r) => !matches(r, url));
      return new Response(null, { status: 204 });
    }
  }
  if (url.includes("/rest/v1/motion_consent_decisions") && method === "POST") {
    decisions.push(body);
    return new Response(null, { status: 201 });
  }
  if (url.includes("/rest/v1/motion_parental_consents")) {
    if (method === "GET") {
      const match = stored && matches(stored, url) ? stored : null;
      // maybeSingle() reads a plain JSON array and maps [] to null.
      return Response.json(match ? [match] : []);
    }
    if (method === "POST") {
      upserts.push(body);
      stored = { ...body };
      return new Response(null, { status: 201 });
    }
    if (method === "PATCH") {
      updates.push(body);
      const hit = stored !== null && matches(stored, url);
      if (hit) stored = { ...stored, ...body };
      return Response.json(hit ? [stored] : []);
    }
  }
  return Response.json({ message: "unexpected " + method + " " + url }, {
    status: 500,
  });
}) as typeof fetch;

await import("../motion-parental-consent/index.ts");

function reset() {
  restricted = true;
  smtp.options = {};
  mails.length = 0;
  upserts = [];
  updates = [];
  deleted = [];
  stored = null;
  deviceRows = [];
  decisions = [];
  counters = new Map();
  onSlot = undefined;
  onDevicePatch = undefined;
  authCalls = 0;
}

function post(body: unknown, token?: string) {
  return handler(
    new Request("http://local/motion-parental-consent", {
      method: "POST",
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: JSON.stringify(body),
    }),
  );
}

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function sha256(value: string) {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(hash)).map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
}

function linkToken(): string {
  const text = mails.at(-1)!.text;
  return /#token=([A-Za-z0-9_-]+)/.exec(text)![1];
}

Deno.test("request mails one link and stores only digests", async () => {
  reset();
  const response = await post(
    {
      action: "request",
      parentEmail: " Parent@Example.invalid ",
      locale: "tr",
    },
    "teen-token",
  );
  assert(response.status === 200, `status ${response.status}`);
  assert(mails.length === 1, "one mail");
  assert(mails[0].to === "<parent@example.invalid>", "normalised recipient");
  assert(mails[0].subject.includes("Motion"), "localized subject");
  assert(
    mails[0].text.includes("https://example.invalid/consent#token="),
    "link in fragment",
  );
  const row = upserts[0];
  assert(
    !JSON.stringify(row).includes("parent@example.invalid"),
    "no clear parent email",
  );
  assert(
    row.parent_email_digest === await sha256("parent@example.invalid"),
    "email digest",
  );
  assert(row.token_digest === await sha256(linkToken()), "token digest");
  assert(!JSON.stringify(row).includes(linkToken()), "no clear token");
  assert(row.status === "pending", "pending");
});

Deno.test("request requires a teen bearer and a restricted account", async () => {
  reset();
  let response = await post({
    action: "request",
    parentEmail: "p@example.invalid",
  });
  assert(response.status === 401, "bearer required");
  restricted = false;
  response = await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  assert(response.status === 409, "consent not required");
  assert(mails.length === 0 && upserts.length === 0, "nothing sent or stored");
});

Deno.test("request rejects own address, bad address and unavailable mail", async () => {
  reset();
  let response = await post(
    { action: "request", parentEmail: "teen@example.invalid" },
    "teen-token",
  );
  assert(response.status === 400, "own address");
  response = await post(
    { action: "request", parentEmail: "nope" },
    "teen-token",
  );
  assert(response.status === 400, "invalid address");
  smtp.options = { authReply: "535 5.7.8 bad credentials" };
  const { result, logged } = await capturingErrors(() =>
    post(
      { action: "request", parentEmail: "p@example.invalid" },
      "teen-token",
    )
  );
  assert(result.status === 503, "mail unavailable");
  assert(
    (await result.json()).error === "mail_unavailable",
    "same public error",
  );
  assert(upserts.length === 0, "no pending row without a delivered mail");
  assert(
    JSON.stringify(logged) === JSON.stringify([
      '{"event":"motion_consent_mail_failed","failure":"auth","stage":"auth","code":535}',
    ]),
    `auth failure line ${logged}`,
  );
});

// Every console.error line during [work]; nothing else is captured.
async function capturingErrors<T>(work: () => Promise<T>) {
  const logged: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logged.push(args.join(" "));
  try {
    return { result: await work(), logged };
  } finally {
    console.error = original;
  }
}

Deno.test("mail failure lines name the class and never a secret", async () => {
  reset();
  const secrets = [
    "p@example.invalid",
    "teen@example.invalid",
    "consent@example.invalid",
    "fixture-app-password",
    "bad credentials",
    "#token=",
  ];
  const cases: [string, () => void, string][] = [
    [
      "config",
      () => Deno.env.delete("MOTION_SMTP_PASSWORD"),
      '{"event":"motion_consent_mail_failed","failure":"config","stage":"config","issue":"missing:MOTION_SMTP_PASSWORD"}',
    ],
    [
      "network",
      () => Deno.env.set("MOTION_SMTP_PORT", "1"),
      '{"event":"motion_consent_mail_failed","failure":"network","stage":"connect"}',
    ],
    [
      "recipient",
      () => smtp.options = { rcptReply: "550 5.1.1 no such user" },
      '{"event":"motion_consent_mail_failed","failure":"recipient","stage":"rcpt","code":550}',
    ],
  ];
  for (const [name, breakIt, line] of cases) {
    reset();
    breakIt();
    try {
      const { result, logged } = await capturingErrors(() =>
        post(
          { action: "request", parentEmail: "p@example.invalid" },
          "teen-token",
        )
      );
      assert(result.status === 503, `${name}: 503`);
      assert(
        (await result.json()).error === "mail_unavailable",
        `${name}: public error`,
      );
      assert(upserts.length === 0, `${name}: no row`);
      assert(
        JSON.stringify(logged) === JSON.stringify([line]),
        `${name}: ${logged}`,
      );
      for (const secret of secrets) {
        assert(!logged.join("\n").includes(secret), `${name}: ${secret}`);
      }
    } finally {
      Deno.env.set("MOTION_SMTP_PASSWORD", "fixture-app-password");
      Deno.env.set("MOTION_SMTP_PORT", String(smtp.port));
    }
  }
});

Deno.test("an app password stored with Google's spaces still logs in", async () => {
  reset();
  Deno.env.set("MOTION_SMTP_PASSWORD", " abcd efgh ijkl mnop\n");
  try {
    const { result, logged } = await capturingErrors(() =>
      post(
        { action: "request", parentEmail: "p@example.invalid" },
        "teen-token",
      )
    );
    assert(result.status === 200, "mail accepted");
    assert(logged.length === 0, "success logs nothing");
    assert(
      mails.at(-1)!.auth === "\0consent@example.invalid\0abcdefghijklmnop",
      "spaces removed before AUTH PLAIN",
    );
  } finally {
    Deno.env.set("MOTION_SMTP_PASSWORD", "fixture-app-password");
  }
});

Deno.test("a fresh pending request is rate limited", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  const again = await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  assert(again.status === 429, `status ${again.status}`);
  assert(mails.length === 1, "no second mail");
});

Deno.test("view masks the teen address; approve consumes the token", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  const token = linkToken();
  const view = await post({ action: "view", token });
  const summary = await view.json();
  assert(view.status === 200, "view ok");
  assert(summary.teenEmail === "t***@example.invalid", "masked");
  const approve = await post({ action: "decide", token, decision: "approve" });
  assert(approve.status === 200, "approved");
  assert(updates.at(-1)!.status === "approved", "status approved");
  assert(updates.at(-1)!.token_digest === null, "token consumed");
  assert(deleted.length === 0, "account kept");
});

Deno.test("deny deletes the teen account; wrong token is rejected", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  const bad = await post({
    action: "decide",
    token: "x".repeat(43),
    decision: "deny",
  });
  assert(bad.status === 404, "invalid link");
  assert(deleted.length === 0, "nothing deleted by a wrong token");
  const deny = await post({
    action: "decide",
    token: linkToken(),
    decision: "deny",
  });
  assert(deny.status === 200, "denied");
  assert(deleted.length === 1, "account deleted");
});

Deno.test("expired link cannot decide", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  stored = { ...stored!, expires_at: "2000-01-01T00:00:00Z" };
  const response = await post({
    action: "decide",
    token: linkToken(),
    decision: "approve",
  });
  assert(response.status === 410, "expired");
  assert(updates.length === 0 && deleted.length === 0, "no decision");
});

Deno.test("fourteen locales fill both placeholders once", () => {
  assert(consentLocales.length === 14, "fourteen locales");
  for (const locale of consentLocales) {
    const filled = consentEmail(locale, {
      link: "L{expiresAt}",
      expiresAt: "D",
    });
    assert(
      filled.text.includes("L{expiresAt}"),
      `${locale} link inserted once`,
    );
    assert(!/\{link\}/.test(filled.text), `${locale} link placeholder`);
    assert(filled.text.includes("D"), `${locale} expiry`);
  }
  assert(
    consentEmail("es-MX", { link: "l", expiresAt: "d" }).subject ===
      consentEmail("es-419", { link: "l", expiresAt: "d" }).subject,
    "es variant",
  );
  assert(
    consentEmail("xx", { link: "l", expiresAt: "d" }).subject ===
      consentEmail("en", { link: "l", expiresAt: "d" }).subject,
    "fallback",
  );
});

// Legal pre-review Annex D (lawyer-approved TR/EN): after the decline
// paragraph, every locale says deleting the account does not cancel a store
// subscription and links the privacy page.
Deno.test("every locale says account deletion does not cancel a store subscription", () => {
  const approved: Record<string, string> = {
    en:
      "The teen may have bought a subscription through the store's family controls (e.g. Ask to Buy, Google Play parental approval). Deleting the account does not cancel it; you can manage it in the Apple or Google account. Details: https://yulalab.com/privacy/motion",
    tr:
      "Genç, mağazanın aile denetimleriyle (ör. Satın Almak İçin Sor, Google Play ebeveyn onayı) abonelik almış olabilir. Hesabın silinmesi bu aboneliği iptal etmez; aboneliği Apple veya Google hesabından yönetebilirsiniz. Ayrıntılar: https://yulalab.com/privacy/motion",
  };
  for (const locale of consentLocales) {
    const paragraphs = consentEmail(locale, { link: "L", expiresAt: "D" })
      .text.split("\n\n");
    const note = paragraphs.at(-2)!;
    assert(
      paragraphs.length === 7 &&
        paragraphs.at(-1) === "YULAlab · support@yulalab.com",
      `${locale} paragraph count and footer`,
    );
    assert(
      note.endsWith("https://yulalab.com/privacy/motion") &&
        note.includes("Apple") && note.includes("Google Play"),
      `${locale} store subscription note`,
    );
    assert(paragraphs.at(-3)!.includes("30"), `${locale} note follows decline`);
    if (locale in approved) {
      assert(note === approved[locale], `${locale} approved wording`);
    }
  }
});

// CORE-04: the YULAlab consent page calls view/decide from the browser.
function fromOrigin(method: string, origin: string | null, body?: unknown) {
  const headers: Record<string, string> = {};
  if (origin !== null) headers.Origin = origin;
  if (method === "OPTIONS") {
    headers["Access-Control-Request-Method"] = "POST";
    headers["Access-Control-Request-Headers"] = "content-type";
  }
  return handler(
    new Request("http://local/motion-parental-consent", {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
}

// K-3 (27 Oct 2026): exactly the apex and www site are allowed by default.
const SITE_ORIGINS = ["https://yulalab.com", "https://www.yulalab.com"];

Deno.test("preflight from the site origins is allowed without wildcard", async () => {
  Deno.env.delete("MOTION_CONSENT_ALLOWED_ORIGINS");
  for (const origin of SITE_ORIGINS) {
    const response = await fromOrigin("OPTIONS", origin);
    assert(response.status === 204, `${origin} preflight 204`);
    const h = response.headers;
    assert(h.get("Access-Control-Allow-Origin") === origin, "echoed origin");
    assert(
      h.get("Access-Control-Allow-Methods") === "POST, OPTIONS",
      "methods",
    );
    assert(
      h.get("Access-Control-Allow-Headers") ===
        "authorization, x-client-info, apikey, content-type",
      "headers",
    );
    assert(h.get("Access-Control-Max-Age") === "600", "max age");
    assert(h.get("Vary") === "Origin", "vary");
  }
});

Deno.test("site origins read view answers from the default list", async () => {
  reset();
  Deno.env.delete("MOTION_CONSENT_ALLOWED_ORIGINS");
  for (const origin of SITE_ORIGINS) {
    const view = await fromOrigin("POST", origin, {
      action: "view",
      token: "x".repeat(43),
    });
    assert(
      view.headers.get("Access-Control-Allow-Origin") === origin,
      `${origin} view`,
    );
    assert(view.headers.get("Vary") === "Origin", `${origin} vary`);
  }
});

Deno.test("an unlisted origin gets no CORS grant", async () => {
  Deno.env.delete("MOTION_CONSENT_ALLOWED_ORIGINS");
  for (
    const origin of [
      "https://evil.example",
      "http://yulalab.com",
      "https://yulalab.com.evil.example",
      "https://preview.yulalab.com",
      "https://www.yulalab.com:8443",
      "null",
    ]
  ) {
    const pre = await fromOrigin("OPTIONS", origin);
    assert(pre.status === 403, `${origin} preflight refused`);
    assert(
      !pre.headers.has("Access-Control-Allow-Origin"),
      `${origin} no ACAO`,
    );
    const view = await fromOrigin("POST", origin, {
      action: "view",
      token: "x".repeat(43),
    });
    assert(!view.headers.has("Access-Control-Allow-Origin"), `${origin} view`);
    assert(view.headers.get("Vary") === "Origin", `${origin} vary`);
  }
});

Deno.test("view, decide and error answers carry the allowed origin", async () => {
  reset();
  restricted = true;
  Deno.env.set(
    "MOTION_CONSENT_ALLOWED_ORIGINS",
    "https://yulalab.com/, https://preview.example.invalid",
  );
  try {
    await post({
      action: "request",
      parentEmail: "p@example.invalid",
      locale: "en",
    }, "t");
    const token = linkToken();
    for (
      const origin of ["https://yulalab.com", "https://preview.example.invalid"]
    ) {
      const pre = await fromOrigin("OPTIONS", origin);
      assert(pre.status === 204, `${origin} listed`);
    }
    const origin = "https://preview.example.invalid";
    const view = await fromOrigin("POST", origin, { action: "view", token });
    assert(view.status === 200, "view ok");
    assert(view.headers.get("Access-Control-Allow-Origin") === origin, "view");
    assert((await view.json()).status === "pending", "view body intact");
    const bad = await fromOrigin("POST", origin, {
      action: "decide",
      token,
      decision: "maybe",
    });
    assert(bad.status === 400, "invalid decision");
    assert(bad.headers.get("Access-Control-Allow-Origin") === origin, "error");
    const decide = await fromOrigin("POST", origin, {
      action: "decide",
      token,
      decision: "approve",
    });
    assert(decide.status === 200, "decide ok");
    assert(
      decide.headers.get("Access-Control-Allow-Origin") === origin,
      "decide",
    );
    assert((await decide.json()).status === "approved", "decide body intact");
    const gone = await fromOrigin("POST", origin, { action: "view", token });
    assert(
      gone.headers.get("Access-Control-Allow-Origin") === origin,
      "404/410",
    );
  } finally {
    Deno.env.delete("MOTION_CONSENT_ALLOWED_ORIGINS");
  }
});

Deno.test("GET stays 405 and app requests without Origin are unchanged", async () => {
  Deno.env.delete("MOTION_CONSENT_ALLOWED_ORIGINS");
  const get = await fromOrigin("GET", "https://yulalab.com");
  assert(get.status === 405, "GET 405");
  assert(
    get.headers.get("Access-Control-Allow-Origin") === "https://yulalab.com",
    "405 readable by the page",
  );
  const app = await fromOrigin("POST", null, { action: "nope" });
  assert(app.status === 400, "invalid action");
  assert(!app.headers.has("Access-Control-Allow-Origin"), "no ACAO for app");
});

Deno.test("mail is submitted over SMTP with the configured sender", () => {
  // Every mail above went through the real SMTP client to the loopback server.
  assert(smtp.commands.includes("EHLO motion.yulalab.com"), "EHLO seen");
  assert(
    smtp.commands.includes("MAIL FROM:<no-reply@example.invalid>"),
    "envelope sender",
  );
});

// VELI-01 (ADR-008): under-13 device path, no account and no session.
const DEVICE = "d".repeat(43);

function device(
  extra: Record<string, unknown> = {},
  parent = "p@example.invalid",
) {
  return post({
    action: "request_device",
    deviceToken: DEVICE,
    parentEmail: parent,
    locale: "en",
    ...extra,
  });
}

function ago(minutes: number): string {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

Deno.test("request_device mails one link without a session and stores only digests", async () => {
  reset();
  const response = await device();
  assert(response.status === 200, `status ${response.status}`);
  const answer = await response.json();
  assert(answer.status === "pending" && answer.expiresAt, "pending answer");
  assert(mails.length === 1, "one mail");
  assert(mails[0].to === "<p@example.invalid>", "recipient");
  assert(!mails[0].text.includes(DEVICE), "device token never mailed");
  const row = deviceRows[0];
  const serialized = JSON.stringify(row);
  assert(!serialized.includes("p@example.invalid"), "no clear parent email");
  assert(!serialized.includes(DEVICE), "no raw device token");
  assert(!serialized.includes(linkToken()), "no raw link token");
  assert(row.device_token_digest === await sha256(DEVICE), "device digest");
  assert(
    row.parent_email_digest === await sha256("p@example.invalid"),
    "parent digest",
  );
  assert(row.link_digest === await sha256(linkToken()), "link digest");
  assert(row.status === "pending" && row.method === "email_link", "pending");
  assert(!("user_id" in row), "no account key");
  assert(upserts.length === 0, "account table untouched");
});

Deno.test("request_device validates the token and the address", async () => {
  reset();
  for (const deviceToken of [undefined, "", "short", "!".repeat(43), 5]) {
    const response = await device({ deviceToken });
    assert(response.status === 400, `token ${deviceToken}`);
    assert((await response.json()).error === "invalid_device_token", "error");
  }
  const bad = await device({}, "nope");
  assert(bad.status === 400, "bad address");
  assert((await bad.json()).error === "invalid_parent_email", "address error");
  assert(
    mails.length === 0 && deviceRows.length === 0,
    "nothing sent or stored",
  );
});

Deno.test("request_device fails closed: no row without a delivered mail", async () => {
  reset();
  smtp.options = { authReply: "535 5.7.8 bad credentials" };
  const { result } = await capturingErrors(() => device());
  assert(result.status === 503, "mail unavailable");
  assert((await result.json()).error === "mail_unavailable", "public error");
  assert(deviceRows.length === 0, "no pending row");
});

Deno.test("request_device: a fresh pending request is too_soon and counts nothing", async () => {
  reset();
  await device();
  const soon = await device();
  assert(soon.status === 429, "too soon");
  assert((await soon.json()).error === "too_soon", "too_soon code");
  assert(mails.length === 1, "no second mail");
  assert(
    counters.get(`d:${await sha256(DEVICE)}|${today()}`) === 1,
    "refusal reserved no slot",
  );
});

Deno.test("device approve keeps the token digest, drops the parent digest, leaves an anonymous trace", async () => {
  reset();
  await device();
  const token = linkToken();
  const view = await post({ action: "view", token });
  const summary = await view.json();
  assert(view.status === 200 && summary.status === "pending", "view");
  assert(summary.subject === "device", "device subject");
  assert(!("teenEmail" in summary), "no teen address for a device");
  const approve = await post({ action: "decide", token, decision: "approve" });
  assert(approve.status === 200, "approved");
  assert((await approve.json()).status === "approved", "approved body");
  const row = deviceRows[0];
  assert(row.status === "approved", "status approved");
  assert(row.parent_email_digest === null, "parent digest removed");
  assert(
    row.link_digest === await sha256(token),
    "link digest kept as manage digest",
  );
  assert(
    row.device_token_digest === await sha256(DEVICE),
    "token digest kept",
  );
  assert(deleted.length === 0, "no account involved");
  assert(
    JSON.stringify(decisions) ===
      JSON.stringify([{ status: "approved", method: "email_link" }]),
    "anonymous trace only",
  );
  const status = await post({ action: "status", deviceToken: DEVICE });
  const body = await status.json();
  assert(body.status === "approved" && body.decidedAt, "device reads approval");
  const again = await device();
  assert(again.status === 409, "approved cannot restart");
  assert((await again.json()).error === "already_approved", "already_approved");
  const replay = await post({ action: "decide", token, decision: "deny" });
  assert(replay.status === 410, "a decided link is closed");
});

Deno.test("device deny wipes parent and link digests; the device reads denied once", async () => {
  reset();
  await device();
  const token = linkToken();
  const deny = await post({ action: "decide", token, decision: "deny" });
  assert(deny.status === 200, "denied");
  assert((await deny.json()).status === "denied", "denied body");
  const row = deviceRows[0];
  assert(row.status === "denied", "status denied");
  assert(row.parent_email_digest === null, "parent digest removed");
  assert(row.link_digest === null, "link digest removed");
  assert(
    row.device_token_digest === await sha256(DEVICE),
    "token digest kept for the device",
  );
  assert(
    JSON.stringify(decisions) ===
      JSON.stringify([{ status: "denied", method: "email_link" }]),
    "anonymous trace only",
  );
  const restart = await device();
  assert(restart.status === 409, "denied cannot restart");
  assert((await restart.json()).error === "already_decided", "already_decided");
  const first = await post({ action: "status", deviceToken: DEVICE });
  assert((await first.json()).status === "denied", "device reads denied");
  assert(deviceRows.length === 0, "token digest gone after the read");
  const second = await post({ action: "status", deviceToken: DEVICE });
  assert((await second.json()).status === "none", "then none");
});

Deno.test("status answers none, pending, expired and rejects a bad token", async () => {
  reset();
  let answer = await (await post({ action: "status", deviceToken: DEVICE }))
    .json();
  assert(answer.status === "none", "none");
  await device();
  answer = await (await post({ action: "status", deviceToken: DEVICE })).json();
  assert(answer.status === "pending" && answer.expiresAt, "pending");
  deviceRows[0].expires_at = "2000-01-01T00:00:00Z";
  answer = await (await post({ action: "status", deviceToken: DEVICE })).json();
  assert(answer.status === "expired", "expired");
  const bad = await post({ action: "status", deviceToken: "x" });
  assert(bad.status === 400, "bad token");
  assert((await bad.json()).error === "invalid_device_token", "bad token code");
});

Deno.test("an expired device link cannot decide and can restart", async () => {
  reset();
  await device();
  const token = linkToken();
  deviceRows[0].expires_at = "2000-01-01T00:00:00Z";
  const response = await post({ action: "decide", token, decision: "approve" });
  assert(response.status === 410, "expired");
  assert(decisions.length === 0, "no decision");
  deviceRows[0].requested_at = ago(11);
  deviceRows[0].created_at = ago(60 * 24 * 20);
  const first = deviceRows[0].created_at;
  deviceRows[0].status = "expired";
  const restart = await device();
  assert(restart.status === 200, "restart");
  assert(deviceRows[0].status === "pending", "pending again");
  assert(deviceRows[0].created_at !== first, "retention clock restarts");
  assert(deviceRows[0].requests_today === 2, "counters kept");
});

Deno.test("withdraw moves an approved account consent to withdrawn", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  const token = linkToken();
  assert(stored!.manage_digest === await sha256(token), "manage digest stored");
  const early = await post({ action: "withdraw", token });
  assert(early.status === 409, "pending cannot be withdrawn");
  await post({ action: "decide", token, decision: "approve" });
  const response = await post({ action: "withdraw", token });
  assert(response.status === 200, "withdrawn");
  assert((await response.json()).status === "withdrawn", "withdrawn body");
  assert(
    updates.at(-1)!.status === "withdrawn" && updates.at(-1)!.decided_at,
    "row updated",
  );
  assert(decisions.at(-1)!.status === "withdrawn", "anonymous trace");
  const again = await post({ action: "withdraw", token });
  assert((await again.json()).status === "withdrawn", "idempotent");
  const bad = await post({ action: "withdraw", token: "z".repeat(43) });
  assert(bad.status === 404, "unknown link");
});

Deno.test("the 13+ account path is unchanged: approval leaves the parent digest", async () => {
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  await post({ action: "decide", token: linkToken(), decision: "approve" });
  assert(
    !("parent_email_digest" in updates.at(-1)!),
    "account path does not touch the parent digest",
  );
  assert(deviceRows.length === 0, "device table untouched");
});

Deno.test("the device mail is neutral and falls back to English", () => {
  assert(deviceConsentLocales.join() === "en,tr", "en and tr written");
  for (const locale of ["en", "tr", "de", "xx"]) {
    const filled = deviceConsentEmail(locale, {
      link: "L{expiresAt}",
      expiresAt: "D",
    });
    assert(
      filled.text.includes("L{expiresAt}") && !/\{link\}/.test(filled.text),
      `${locale} link once`,
    );
    assert(!/\bteen\b|Genç/i.test(filled.text), `${locale} no teen wording`);
  }
  assert(
    deviceConsentEmail("de", { link: "l", expiresAt: "d" }).subject ===
      deviceConsentEmail("en", { link: "l", expiresAt: "d" }).subject,
    "fallback",
  );
});

// VELI-01 review fixes: atomic counters, final withdrawal, device withdraw.
Deno.test("mail counters are per parent and per device token, and outlive decisions", async () => {
  reset();
  await device();
  for (let i = 2; i <= 5; i++) {
    deviceRows[0].requested_at = ago(11);
    assert((await device()).status === 200, `request ${i}`);
  }
  deviceRows[0].requested_at = ago(11);
  const sixth = await device();
  assert(sixth.status === 429, "sixth refused");
  assert((await sixth.json()).error === "daily_limit", "daily_limit");
  // Same token redirected to another address is counted on the token key.
  const redirect = await device({}, "other@example.invalid");
  assert(redirect.status === 429, "token redirect counted");
  assert(mails.length === 5, "no sixth mail");
  // A decision or a purge of the consent row does not reset the counters.
  deviceRows = [];
  const rotated = await device({ deviceToken: "g".repeat(43) });
  assert(rotated.status === 429, "parent counter survives row deletion");
  assert(mails.length === 5, "still five mails");
  // A refused reservation counts nothing on the other key (all or nothing).
  const free = await device(
    { deviceToken: "h".repeat(43) },
    "z@example.invalid",
  );
  assert(free.status === 200, "fresh parent and token");
  assert(
    counters.get(`p:${await sha256("p@example.invalid")}|${today()}`) === 5,
    "parent counter stays at five",
  );
});

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

Deno.test("request_device never revives a row decided after the read", async () => {
  for (const decided of ["approved", "denied", "withdrawn"]) {
    reset();
    await device();
    deviceRows[0].requested_at = ago(11);
    onSlot = () => {
      Object.assign(deviceRows[0], {
        status: decided,
        parent_email_digest: null,
      });
    };
    const response = await device();
    onSlot = undefined;
    assert(response.status === 409, `${decided} status ${response.status}`);
    assert(
      (await response.json()).error ===
        (decided === "approved" ? "already_approved" : "already_decided"),
      `${decided} error`,
    );
    assert(deviceRows[0].status === decided, `${decided} row kept`);
  }
});

Deno.test("a withdrawn device row cannot restart", async () => {
  reset();
  await device();
  await post({ action: "decide", token: linkToken(), decision: "approve" });
  await post({ action: "withdraw", token: linkToken() });
  const again = await device();
  assert(again.status === 409, "withdrawn cannot restart");
  assert((await again.json()).error === "already_decided", "already_decided");
});

Deno.test("account request on a withdrawn consent is already_decided", async () => {
  reset();
  stored = {
    user_id: teen,
    status: "withdrawn",
    requested_at: ago(60 * 24),
    requests_today: 1,
    requests_day: "2000-01-01",
  };
  const response = await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  assert(response.status === 409, `status ${response.status}`);
  assert((await response.json()).error === "already_decided", "error");
  assert(mails.length === 0 && upserts.length === 0, "no mail, no pending row");
});

Deno.test("device withdraw: approved and unconsumed becomes withdrawn, once", async () => {
  reset();
  await device();
  const token = linkToken();
  const early = await post({ action: "withdraw", token });
  assert(early.status === 409, "pending cannot be withdrawn");
  await post({ action: "decide", token, decision: "approve" });
  const response = await post({ action: "withdraw", token });
  assert(response.status === 200, "withdrawn");
  assert((await response.json()).status === "withdrawn", "body");
  assert(deviceRows[0].status === "withdrawn", "row withdrawn");
  const status = await (await post({ action: "status", deviceToken: DEVICE }))
    .json();
  assert(status.status === "withdrawn", "device reads withdrawn");
  const again = await post({ action: "withdraw", token });
  assert((await again.json()).status === "withdrawn", "idempotent");
  assert(
    JSON.stringify(decisions.map((d) => d.status)) ===
      JSON.stringify(["approved", "withdrawn"]),
    "one trace per decision",
  );
});

Deno.test("status: an approval older than 30 days reads expired", async () => {
  reset();
  await device();
  await post({ action: "decide", token: linkToken(), decision: "approve" });
  let answer = await (await post({ action: "status", deviceToken: DEVICE }))
    .json();
  assert(answer.status === "approved", "fresh approval");
  deviceRows[0].created_at = ago(60 * 24 * 31);
  answer = await (await post({ action: "status", deviceToken: DEVICE })).json();
  assert(answer.status === "expired", "31 day approval expired");
});

Deno.test("a double decision leaves one anonymous trace", async () => {
  reset();
  await device();
  const token = linkToken();
  const both = await Promise.all([
    post({ action: "decide", token, decision: "approve" }),
    post({ action: "decide", token, decision: "approve" }),
  ]);
  const codes = both.map((r) => r.status).sort();
  assert(JSON.stringify(codes) === "[200,410]", `codes ${codes}`);
  assert(decisions.length === 1, `traces ${decisions.length}`);
  const late = await post({ action: "decide", token, decision: "deny" });
  assert(late.status === 410, "late decision refused");
  assert(decisions.length === 1, "still one trace");
});

Deno.test("request_device and status ignore the Authorization header", async () => {
  reset();
  const plain = await device();
  const plainBody = await plain.json();
  reset();
  const withHeader = await post({
    action: "request_device",
    deviceToken: DEVICE,
    parentEmail: "p@example.invalid",
    locale: "en",
  }, "some-bearer");
  const headerBody = await withHeader.json();
  assert(withHeader.status === plain.status, "same status");
  assert(
    Object.keys(headerBody).join() === Object.keys(plainBody).join(),
    "same shape",
  );
  const status = await post(
    { action: "status", deviceToken: DEVICE },
    "some-bearer",
  );
  assert((await status.json()).status === "pending", "same status answer");
  assert(
    authCalls === 0,
    "the bearer is never verified or tied to an identity",
  );
});

// Second review round.
Deno.test("an approval older than 30 days lets the device start over", async () => {
  reset();
  await device();
  await post({ action: "decide", token: linkToken(), decision: "approve" });
  const fresh = await device();
  assert(fresh.status === 409, "a live approval still blocks");
  deviceRows[0].created_at = ago(60 * 24 * 31);
  const restart = await device();
  assert(restart.status === 200, `restart ${restart.status}`);
  assert(deviceRows[0].status === "pending", "pending again");
  assert(
    Date.parse(String(deviceRows[0].created_at)) > Date.now() - 60_000,
    "retention clock reset like an expiry",
  );
});

Deno.test("a mail that cannot be sent gives its slot back", async () => {
  reset();
  smtp.options = { authReply: "535 5.7.8 bad credentials" };
  for (let i = 0; i < 8; i++) {
    const { result } = await capturingErrors(() => device());
    assert(result.status === 503, `attempt ${i}`);
  }
  const day = new Date().toISOString().slice(0, 10);
  assert(
    (counters.get(`p:${await sha256("p@example.invalid")}|${day}`) ?? 0) === 0,
    "parent slots returned",
  );
  assert(
    (counters.get(`d:${await sha256(DEVICE)}|${day}`) ?? 0) === 0,
    "token slots returned",
  );
  smtp.options = {};
  assert((await device()).status === 200, "mail works once SMTP is back");
});

Deno.test("a too_soon race gives its slot back", async () => {
  reset();
  await device();
  deviceRows[0].requested_at = ago(11);
  onSlot = () => {
    deviceRows[0].requested_at = new Date().toISOString();
  };
  const response = await device();
  onSlot = undefined;
  assert(response.status === 429, "too_soon from the guarded write");
  assert((await response.json()).error === "too_soon", "code");
  const day = new Date().toISOString().slice(0, 10);
  assert(
    counters.get(`d:${await sha256(DEVICE)}|${day}`) === 1,
    "only the first request keeps its slot",
  );
});

Deno.test("withdraw never claims a withdrawal that did not happen", async () => {
  // The device approval is consumed into an account between lookup and update.
  reset();
  await device();
  const token = linkToken();
  await post({ action: "decide", token, decision: "approve" });
  onDevicePatch = () => {
    deviceRows = [];
    stored = {
      user_id: teen,
      status: "approved",
      method: "device_token_email",
      manage_digest: deviceLink,
    };
  };
  const deviceLink = await sha256(token);
  const response = await post({ action: "withdraw", token });
  onDevicePatch = undefined;
  assert(response.status === 200, `status ${response.status}`);
  assert((await response.json()).status === "withdrawn", "withdrawn body");
  assert(stored!.status === "withdrawn", "the account row is withdrawn");
  assert(
    JSON.stringify(decisions.map((d) => d.status)) ===
      JSON.stringify(["approved", "withdrawn"]),
    "one trace for the withdrawal",
  );

  // The row vanished and no account has it: a clear error, never success.
  reset();
  await device();
  const lost = linkToken();
  await post({ action: "decide", token: lost, decision: "approve" });
  onDevicePatch = () => {
    deviceRows = [];
  };
  const gone = await post({ action: "withdraw", token: lost });
  onDevicePatch = undefined;
  assert(gone.status === 404, `gone ${gone.status}`);
  assert(decisions.length === 1, "no withdrawal trace");

  // Account row changed under the update: conflict, no success.
  reset();
  await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  const t = linkToken();
  await post({ action: "decide", token: t, decision: "approve" });
  stored = { ...stored!, status: "approved" };
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (
      url.includes("/rest/v1/motion_parental_consents") &&
      (init?.method ?? "GET") === "PATCH"
    ) {
      return Promise.resolve(Response.json([]));
    }
    return realFetch(input, init);
  }) as typeof fetch;
  try {
    const conflict = await post({ action: "withdraw", token: t });
    assert(conflict.status === 409, `conflict ${conflict.status}`);
    assert((await conflict.json()).error === "already_decided", "code");
    assert(
      decisions.length === 0 || decisions.at(-1)!.status !== "withdrawn",
      "no trace",
    );
  } finally {
    globalThis.fetch = realFetch;
  }
});

Deno.test({
  name: "close the loopback SMTP server",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: () => smtp.close(),
});
