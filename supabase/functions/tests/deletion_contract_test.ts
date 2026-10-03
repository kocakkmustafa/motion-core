// Exercise the production handler with a fixture transport; no remote accounts.
const alice = "00000000-0000-4000-8000-000000000001";
const bob = "00000000-0000-4000-8000-000000000002";
let handler: (request: Request) => Promise<Response>;
let deleted: string[] = [];
let denyAuth = false;
let failDelete = false;
const originalServe = Deno.serve;
const originalFetch = globalThis.fetch;
Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
Deno.env.set("SUPABASE_ANON_KEY", "fixture-public");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-server");
Deno.serve = ((callback: unknown) => {
  handler = callback as typeof handler;
  return {} as Deno.HttpServer;
}) as typeof Deno.serve;
globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const url = String(input instanceof Request ? input.url : input);
  if (url.endsWith("/auth/v1/user")) {
    return Promise.resolve(
      Response.json(
        denyAuth ? { message: "invalid token" } : {
          id: alice,
          aud: "authenticated",
          created_at: "2026-10-02T00:00:00Z",
          app_metadata: {},
          user_metadata: {},
        },
        { status: denyAuth ? 401 : 200 },
      ),
    );
  }
  if (
    url.endsWith("/auth/v1/admin/users/" + alice) && init?.method === "DELETE"
  ) {
    deleted.push(alice);
    return Promise.resolve(
      Response.json(
        failDelete ? { message: "fixture failure" } : { id: alice },
        { status: failDelete ? 500 : 200 },
      ),
    );
  }
  throw new Error("Unexpected fixture request: " + url);
}) as typeof fetch;
await import("../motion-delete-account/index.ts");
Deno.serve = originalServe;
function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}
async function call(
  body: unknown,
  options: { method?: string; authorization?: string } = {},
) {
  const method = options.method ?? "POST";
  return handler(
    new Request("http://127.0.0.1/delete", {
      method,
      headers: {
        "Authorization": options.authorization ?? "Bearer fixture-token",
        "Content-Type": "application/json",
      },
      body: method === "POST" ? JSON.stringify(body) : undefined,
    }),
  );
}
for (
  const [name, body, expected, count] of [
    [
      "UUID owned positive",
      { confirmation: "DELETE", expectedUserId: alice },
      200,
      1,
    ],
    [
      "mismatched UUID never deletes",
      { confirmation: "DELETE", expectedUserId: bob },
      409,
      0,
    ],
    ["legacy token authority compatible", { confirmation: "DELETE" }, 200, 1],
    ["missing confirmation never deletes", { expectedUserId: alice }, 400, 0],
    ["null body never deletes", null, 400, 0],
  ] as const
) {
  Deno.test(name, async () => {
    deleted = [];
    denyAuth = false;
    failDelete = false;
    const r = await call(body);
    const data = await r.json();
    assert(r.status === expected, "status");
    assert(deleted.length === count, "delete count");
    if (expected === 200) {
      assert(data.deleted === true && data.userId === alice, "strict receipt");
    }
  });
}
Deno.test("no bearer never deletes", async () => {
  deleted = [];
  const r = await call({ confirmation: "DELETE" }, { authorization: "bad" });
  assert(r.status === 401, "status");
  assert(deleted.length === 0, "delete count");
});
Deno.test("invalid token never deletes", async () => {
  deleted = [];
  denyAuth = true;
  const r = await call({ confirmation: "DELETE" });
  assert(r.status === 401, "status");
  assert(deleted.length === 0, "delete count");
  denyAuth = false;
});
Deno.test("admin failure never supplies deletion receipt", async () => {
  deleted = [];
  failDelete = true;
  const r = await call({ confirmation: "DELETE" });
  const data = await r.json();
  assert(r.status === 500 && data.deleted === undefined, "receipt");
  failDelete = false;
});
Deno.test("GET never deletes", async () => {
  deleted = [];
  const r = await call(null, { method: "GET" });
  assert(r.status === 405 && deleted.length === 0, "method guard");
});
Deno.test("fixture transport closed", () => {
  globalThis.fetch = originalFetch;
});
