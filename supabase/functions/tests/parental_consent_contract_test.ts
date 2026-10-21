// Exercise the production consent handler with a fixture transport; no remote
// accounts, no mail provider. The parent address never reaches storage.
import {
  consentEmail,
  consentLocales,
} from "../_shared/motion_consent_copy.ts";

const teen = "00000000-0000-4000-8000-000000000003";
let handler: (request: Request) => Promise<Response>;
let restricted = true;
let mailOk = true;
let mails: { to: string[]; subject: string; text: string }[] = [];
let upserts: Record<string, unknown>[] = [];
let updates: Record<string, unknown>[] = [];
let deleted: string[] = [];
let stored: Record<string, unknown> | null = null;

Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
Deno.env.set("SUPABASE_ANON_KEY", "fixture-public");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-server");
Deno.env.set("MOTION_MAIL_API_URL", "http://127.0.0.1:9/mail");
Deno.env.set("MOTION_MAIL_API_KEY", "fixture-mail");
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
  if (url.endsWith("/mail")) {
    if (mailOk) mails.push(body);
    return new Response(null, { status: mailOk ? 200 : 500 });
  }
  if (url.endsWith("/auth/v1/user")) {
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
  if (url.includes("/rest/v1/rpc/motion_account_restricted")) {
    return Response.json(restricted);
  }
  if (url.includes("/rest/v1/motion_parental_consents")) {
    if (method === "GET") {
      const tokenFilter = new URL(url).searchParams.get("token_digest");
      const match = stored &&
          (!tokenFilter || tokenFilter === `eq.${stored.token_digest}`)
        ? stored
        : null;
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
      stored = { ...stored, ...body };
      return new Response(null, { status: 204 });
    }
  }
  return Response.json({ message: "unexpected " + method + " " + url }, {
    status: 500,
  });
}) as typeof fetch;

await import("../motion-parental-consent/index.ts");

function reset() {
  restricted = true;
  mailOk = true;
  mails = [];
  upserts = [];
  updates = [];
  deleted = [];
  stored = null;
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
  assert(mails[0].to[0] === "parent@example.invalid", "normalised recipient");
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
  mailOk = false;
  response = await post(
    { action: "request", parentEmail: "p@example.invalid" },
    "teen-token",
  );
  assert(response.status === 503, "mail unavailable");
  assert(upserts.length === 0, "no pending row without a delivered mail");
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
