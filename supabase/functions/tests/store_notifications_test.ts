// CORE-R3 K2: store server notifications. Nothing runs before the request
// proves its origin (Apple JWS chain, Google OIDC token); a verified notice
// only triggers a store re-verification of the matching stored rows.
import {
  type AppleNotice,
  createNotificationHandler,
  type NotificationDeps,
  verifyAppleNotification,
  verifyGoogleOidc,
} from "../_shared/motion_store_notifications.ts";
import type {
  RefreshResult,
  StoredEntitlement,
} from "../_shared/motion_entitlement_refresh.ts";
import { StoreConfigurationError } from "../_shared/motion_store_provider.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const now = new Date("2026-10-25T12:00:00Z");
const audience =
  "https://example.invalid/functions/v1/motion-store-notifications/google";
const pushAccount = "rtdn-push@example-project.iam.gserviceaccount.com";
const row: StoredEntitlement = {
  user_id: "11111111-1111-4111-8111-111111111111",
  app_id: "motion_plus",
  store: "google",
  product_id: "jablab_motion_plus",
  original_transaction_id: "play-token-1",
};

// Self-generated test certificates (public only): a CA used as the
// configured "Apple root" and an unrelated leaf in x5c. The chain is not
// Apple's, so verification must fail closed.
const TEST_ROOT =
  "MIIDLTCCAhWgAwIBAgIULUIyy6LsQrNlkT+vUtyS6l9uoMowDQYJKoZIhvcNAQELBQAwHjEcMBoGA1UEAwwTRWtpcDIgbG9jYWwgdGVzdCBDQTAeFw0yNjEwMjQyMzEzMDVaFw0yNjEwMjYyMzEzMDVaMB4xHDAaBgNVBAMME0VraXAyIGxvY2FsIHRlc3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCfoEl6bbzthfCmuyX4DqTnpqY8ZnIvMUa33oaLhno0jBoSsklDrUUp9rYets87Rxlcp4e1qOsXRECtpmzy178JKx69ATxKA1hZ8EJzogI8fEPxSlkBdWT1LN26DISQD+xSJFBAScnJ+XhunzyAAyt0TadvyYzq8MW51RuPM72f35vB7iLdt7IVeVDx51TUb2wYruqPaT7aUtCDv01DmC14XO23/A2NexO9op9vbcD8o2jruLjkf4Li2YBRlDKxPHnSObuI0sfuGK5nkhadNbiKnAFV3aI3u7IcAikR1aBAX6ItuEJRZa8DHRbwi4fxV6P0CyqC5QMk6BtGwRS0xJQjAgMBAAGjYzBhMB0GA1UdDgQWBBRyfHC0Fn+F+DA4EJAbSfrBEbGh8DAfBgNVHSMEGDAWgBRyfHC0Fn+F+DA4EJAbSfrBEbGh8DAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwICBDANBgkqhkiG9w0BAQsFAAOCAQEAhq89Immfaa0iXYFCQDo7SK/Rx7AUi2npJQbVJGGZYJ0UxmOuk5QqOraegBeYq8Ina99vS3OjKBs2YMb9z2m0S0KMuTRKVdUznsOjf3GyuOkMQ/btKkuZ6oT30E1wMEXChK4VvvKPQ6cTzHzy2yS9zaGusCx2G69OjbmWnUxJiK0x4yZorRMyQTlsc/Ljrd+Ffb2fjtrsrrnPR6CXwcQgACULQK/H2/fTrBnej45S69S/XmSnulddHiUAu/YR/PNLIp1+zRIZDZPgbe8zU2TvimhTr0m/KP1l7v3+/qM3R37KxopqPOhe/6Mdj4tyGXBo8nMRfE8/UylXrCa4vlcdUw==";
const TEST_LEAF =
  "MIIDODCCAiCgAwIBAgIUKePE8+gAf5dfjsNcuN/SgEhmWVMwDQYJKoZIhvcNAQELBQAwHjEcMBoGA1UEAwwTRWtpcDIgbG9jYWwgdGVzdCBDQTAeFw0yNjEwMjQyMzEzMDVaFw0yNjEwMjYyMzEzMDVaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAM+ef7dozTrw/hCaakknFiia834N+7wBHYePgYhKtgpN8BKS6dEka0CvY9llPoJ08senPUbONY1pmBSI18MkFnUBdx1Ht0zdOXS2LIJp2xG7yhj6f76K/stv2bIzNAZImUhZAjWL7ZUKctQ0nIDyBmnBskhgoZe7oDfVToLscE8xtT/j3oZ0x8AIqXuSkNxoQJRiMC5R5I5yHfdpJZW2isvLv0PE8gneEOCd7URdsVtrFc61R2FnOYEkNg1rNL6tkTd45HmThPCl1Hpik3gABY6zrXq4pznBORKdm6C3SSkTgNlVDlozH7NTW2FF+P0CVievxHbM8sxPdu51hwUKB1UCAwEAAaN4MHYwFAYDVR0RBA0wC4IJbG9jYWxob3N0MAkGA1UdEwQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwEwHQYDVR0OBBYEFOGDGBaUH/vJ75wvekcZ7jiCkfNDMB8GA1UdIwQYMBaAFHJ8cLQWf4X4MDgQkBtJ+sERsaHwMA0GCSqGSIb3DQEBCwUAA4IBAQCSUneIgUg1EvRl2RzRlcXRGIIxC1/izyt0fJ1nKirGDezdrwAsnWOXmnm1AE4Ts1bFFK6VI58ZTDYohVWmH5C9R9ahQMlkHde/9rvyW/lw9yVl5JuZHmkPiOues02r+8U/OJVI4AG/reWxvb+X/vVMMJ94K0Te0lGbsup0q6l/wrC+0x4t4RIeYiR4gqzhEvfUnMEwNCh9g21K+Uwv6M1SwMbis0ErmFKS8T1HqyH9+8oCV9ZjhYcptjk84krjkANdboDRu3MAd1MGkEeK3PUlR4nVXsVr6/TpS6v8ox+iG5f3EmQnOLGb343fZWaF7CHzA5RH2QNRJ6URHuBtgEqL";

function b64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-")
    .replaceAll("/", "_").replaceAll("=", "");
}

const googleKey = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);
const otherKey = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);
const publicJwk = {
  ...(await crypto.subtle.exportKey("jwk", googleKey.publicKey)),
  kid: "test-kid",
};

async function oidc(
  claims: Record<string, unknown>,
  key: CryptoKey = googleKey.privateKey,
  kid = "test-kid",
): Promise<string> {
  const seconds = Math.floor(now.getTime() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", kid, typ: "JWT" }));
  const body = b64url(JSON.stringify({
    iss: "https://accounts.google.com",
    aud: audience,
    email: pushAccount,
    email_verified: true,
    iat: seconds - 10,
    exp: seconds + 3600,
    ...claims,
  }));
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${head}.${body}`),
    ),
  );
  return `${head}.${body}.${b64url(signature)}`;
}

function deps(overrides: Partial<NotificationDeps> = {}) {
  const calls = { find: [] as string[], refresh: 0 };
  const d: NotificationDeps = {
    verifyApple: () => Promise.resolve(null),
    googleKeys: () => Promise.resolve([publicJwk]),
    env: (name) =>
      ({
        MOTION_RTDN_AUDIENCE: audience,
        MOTION_RTDN_PUSH_SERVICE_ACCOUNT: pushAccount,
      })[name],
    findRows: (store, id) => {
      calls.find.push(`${store}:${id}`);
      return Promise.resolve(id === "unknown" ? [] : [row]);
    },
    refresh: (): Promise<RefreshResult> => {
      calls.refresh++;
      return Promise.resolve({
        ok: true,
        granting: false,
        appId: null,
        claim: null,
        trialRecorded: true,
      });
    },
    now: () => now,
    ...overrides,
  };
  return { d, calls };
}

function apple(body: unknown) {
  return new Request(
    "https://x.invalid/functions/v1/motion-store-notifications/apple",
    {
      method: "POST",
      body: typeof body === "string" ? body : JSON.stringify(body),
    },
  );
}

function google(token: string | null, data: unknown) {
  const headers: Record<string, string> = {};
  if (token !== null) headers.Authorization = `Bearer ${token}`;
  return new Request(
    "https://x.invalid/functions/v1/motion-store-notifications/google",
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        message: { data: b64url(JSON.stringify(data)), messageId: "1" },
        subscription: "projects/p/subscriptions/s",
      }),
    },
  );
}

const playNotice = {
  version: "1.0",
  packageName: "com.yulalab.jablab",
  eventTimeMillis: "1792900000000",
  subscriptionNotification: {
    version: "1.0",
    notificationType: 13,
    purchaseToken: "play-token-1",
    subscriptionId: "jablab_motion_plus",
  },
};

Deno.test("Apple: unsigned or unverifiable requests touch nothing", async () => {
  for (
    const body of ["not json", {}, { signedPayload: 7 }, {
      signedPayload: "a.b.c",
    }]
  ) {
    const { d, calls } = deps();
    const response = await createNotificationHandler(d)(apple(body));
    assert(response.status === 401, `401 for ${JSON.stringify(body)}`);
    assert(calls.find.length === 0 && calls.refresh === 0, "no DB/store call");
  }
});

Deno.test("Apple: a verified transaction notice re-verifies its rows", async () => {
  const notice: AppleNotice = {
    kind: "transaction",
    originalTransactionId: "2000000000000001",
  };
  const { d, calls } = deps({ verifyApple: () => Promise.resolve(notice) });
  const response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 200, "accepted");
  assert(calls.find.join() === "apple:2000000000000001", "row lookup");
  assert(calls.refresh === 1, "store re-verification");
});

Deno.test("Apple: test notices are acknowledged; failures ask for a retry", async () => {
  let { d, calls } = deps({
    verifyApple: () => Promise.resolve({ kind: "test" }),
  });
  let response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 200 && calls.find.length === 0, "test notice");
  ({ d } = deps({
    verifyApple: () => Promise.reject(new StoreConfigurationError("roots")),
  }));
  response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 503, "configuration error retried");
  ({ d, calls } = deps({
    verifyApple: () =>
      Promise.resolve({ kind: "transaction", originalTransactionId: "1" }),
    refresh: () =>
      Promise.resolve(
        { ok: false, error: "store_unavailable" } as RefreshResult,
      ),
  }));
  response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 503, "store outage retried");
  ({ d, calls } = deps({
    verifyApple: () =>
      Promise.resolve({
        kind: "transaction",
        originalTransactionId: "unknown",
      }),
  }));
  response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 200 && calls.refresh === 0, "unknown transaction");
});

Deno.test("Apple: the production verifier rejects a foreign bundle or chain", async () => {
  const forged = (bundleId: string) =>
    `${b64url(JSON.stringify({ alg: "ES256", x5c: [TEST_LEAF, TEST_ROOT] }))}.${
      b64url(JSON.stringify({
        notificationType: "DID_RENEW",
        data: { bundleId, environment: "Production", appAppleId: 6794715669 },
      }))
    }.${b64url("signature")}`;
  const previous = Deno.env.get("MOTION_APPLE_ROOT_CAS_BASE64");
  Deno.env.set("MOTION_APPLE_ROOT_CAS_BASE64", JSON.stringify([TEST_ROOT]));
  try {
    assert(
      await verifyAppleNotification(forged("com.example.other")) === null,
      "foreign bundle",
    );
    assert(
      await verifyAppleNotification(forged("com.yulalab.jablab")) === null,
      "untrusted chain",
    );
    assert(await verifyAppleNotification("garbage") === null, "malformed");
  } finally {
    if (previous === undefined) Deno.env.delete("MOTION_APPLE_ROOT_CAS_BASE64");
    else Deno.env.set("MOTION_APPLE_ROOT_CAS_BASE64", previous);
  }
});

Deno.test("Google: only a valid push token for our audience and account passes", async () => {
  const seconds = Math.floor(now.getTime() / 1000);
  const bad = [
    null,
    "not-a-jwt",
    await oidc({}, otherKey.privateKey),
    await oidc({}, googleKey.privateKey, "other-kid"),
    await oidc({ aud: "https://evil.example" }),
    await oidc({ email: "someone@example.iam.gserviceaccount.com" }),
    await oidc({ email_verified: false }),
    await oidc({ iss: "https://evil.example" }),
    await oidc({ exp: seconds - 3600 }),
  ];
  for (const token of bad) {
    const { d, calls } = deps();
    const response = await createNotificationHandler(d)(
      google(token, playNotice),
    );
    assert(response.status === 401, `401 for token #${bad.indexOf(token)}`);
    assert(calls.find.length === 0 && calls.refresh === 0, "no DB/store call");
  }
  const valid = await verifyGoogleOidc(
    await oidc({}),
    [publicJwk],
    audience,
    pushAccount,
    now,
  );
  assert(valid === true, "valid token verifies");
});

Deno.test("Google: a verified subscription notice re-verifies its token", async () => {
  const { d, calls } = deps();
  const response = await createNotificationHandler(d)(
    google(await oidc({}), playNotice),
  );
  assert(response.status === 200, "accepted");
  assert(
    calls.find.join() === "google:play-token-1" && calls.refresh === 1,
    "refreshed",
  );
});

Deno.test("Google: foreign package, test notices and missing settings", async () => {
  let { d, calls } = deps();
  let response = await createNotificationHandler(d)(
    google(await oidc({}), { ...playNotice, packageName: "com.example.other" }),
  );
  assert(response.status === 400 && calls.find.length === 0, "foreign package");
  ({ d, calls } = deps());
  response = await createNotificationHandler(d)(
    google(await oidc({}), {
      version: "1.0",
      packageName: "com.yulalab.lissom",
      testNotification: { version: "1.0" },
    }),
  );
  assert(response.status === 200 && calls.find.length === 0, "test notice");
  ({ d, calls } = deps({ env: () => undefined }));
  response = await createNotificationHandler(d)(
    google(await oidc({}), playNotice),
  );
  assert(response.status === 503 && calls.find.length === 0, "not configured");
});

Deno.test("only POST to a known store path", async () => {
  const { d } = deps();
  const handler = createNotificationHandler(d);
  assert(
    (await handler(new Request("https://x.invalid/f/apple"))).status === 405,
    "GET",
  );
  assert(
    (await handler(
      new Request("https://x.invalid/f/other", { method: "POST" }),
    )).status === 404,
    "unknown path",
  );
});

Deno.test("a verified trial that cannot be recorded is retried", async () => {
  const { d } = deps({
    verifyApple: () =>
      Promise.resolve({ kind: "transaction", originalTransactionId: "1" }),
    refresh: () =>
      Promise.resolve({
        ok: true,
        granting: true,
        appId: "motion_plus",
        claim: null,
        trialRecorded: false,
      }),
  });
  const response = await createNotificationHandler(d)(
    apple({ signedPayload: "x.y.z" }),
  );
  assert(response.status === 503, "ledger failure asks for a retry");
});
