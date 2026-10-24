// CORE-R3 K3: one Motion+ free trial per Motion account.
import {
  createOfferEligibilityHandler,
  type OfferEligibilityDeps,
  signIntroductoryOfferDenial,
} from "../_shared/motion_offer_eligibility.ts";
import type { ProviderVerifiedPurchase } from "../_shared/motion_purchase_claim.ts";
import {
  googleFreeTrial,
  StoreConfigurationError,
} from "../_shared/motion_store_provider.ts";
import {
  motionPlusTrialUsed,
  recordMotionPlusTrial,
} from "../_shared/motion_trial_ledger.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const userId = "11111111-1111-4111-8111-111111111111";

function ledger(options: { fail?: boolean; row?: boolean } = {}) {
  const writes: { values: Record<string, unknown>; options: unknown }[] = [];
  return {
    writes,
    from(_table: "motion_trial_ledger") {
      return {
        upsert(values: Record<string, unknown>, upsertOptions: unknown) {
          writes.push({ values, options: upsertOptions });
          return Promise.resolve({
            error: options.fail ? { message: "db" } : null,
          });
        },
        select() {
          return {
            eq: () => ({
              maybeSingle: () =>
                Promise.resolve(
                  options.fail ? { data: null, error: { message: "db" } } : {
                    data: options.row ? { user_id: userId } : null,
                    error: null,
                  },
                ),
            }),
          };
        },
      };
    },
  };
}

function claim(
  overrides: Partial<ProviderVerifiedPurchase> = {},
): ProviderVerifiedPurchase {
  return {
    store: "apple",
    originatingAppId: "jablab",
    productId: "com.yulalab.jablab.motionplus.monthly",
    accountMarker: userId,
    reference: "2000000000000001",
    state: "active",
    expiresAt: "2026-11-08T12:00:00Z",
    freeTrial: true,
    ...overrides,
  };
}

Deno.test("only a verified Motion+ free trial is recorded, first wins", async () => {
  const table = ledger();
  assert(await recordMotionPlusTrial(table, userId, claim()), "recorded");
  assert(table.writes.length === 1, "one write");
  assert(
    JSON.stringify(table.writes[0].options) ===
      JSON.stringify({ onConflict: "user_id", ignoreDuplicates: true }),
    "first record wins",
  );
  assert(table.writes[0].values.app_id === "jablab", "originating app");
  for (
    const other of [
      claim({ freeTrial: false }),
      claim({ freeTrial: undefined }),
      claim({ productId: "com.yulalab.jablab.individual.monthly" }),
      claim({ productId: "com.example.other" }),
    ]
  ) {
    const empty = ledger();
    assert(await recordMotionPlusTrial(empty, userId, other), "no-op ok");
    assert(empty.writes.length === 0, `no record for ${other.productId}`);
  }
  assert(
    await recordMotionPlusTrial(ledger({ fail: true }), userId, claim()) ===
      false,
    "write failure reported",
  );
  const play = ledger();
  await recordMotionPlusTrial(
    play,
    userId,
    claim({
      store: "google",
      productId: "jablab_motion_plus",
      basePlanId: "yearly",
      reference: "play-token",
    }),
  );
  assert(play.writes[0].values.store === "google", "Play trial recorded");
});

Deno.test("trial lookup distinguishes used, unused and unknown", async () => {
  assert(
    await motionPlusTrialUsed(ledger({ row: true }), userId) === true,
    "used",
  );
  assert(await motionPlusTrialUsed(ledger(), userId) === false, "unused");
  assert(
    await motionPlusTrialUsed(ledger({ fail: true }), userId) === null,
    "unknown",
  );
});

function request(body: unknown, token: string | null = "token") {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request(
    "https://x.invalid/functions/v1/motion-offer-eligibility",
    {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    },
  );
}

function deps(overrides: Partial<OfferEligibilityDeps> = {}) {
  const calls = { sign: 0 };
  const d: OfferEligibilityDeps = {
    authenticate: (token) => Promise.resolve(token === "token" ? userId : null),
    trialUsed: () => Promise.resolve(true),
    signDenial: () => {
      calls.sign++;
      return "signed.jws.value";
    },
    ...overrides,
  };
  return { d, calls };
}

const valid = {
  appId: "lissom",
  productId: "com.yulalab.lissom.motionplus.yearly",
  appTransactionId: "704289572311429985",
};

Deno.test("eligibility: a used trial gets a signed denial for Motion+", async () => {
  const { d, calls } = deps();
  const response = await createOfferEligibilityHandler(d)(request(valid));
  const body = await response.json();
  assert(response.status === 200 && body.trialAvailable === false, "denied");
  assert(body.introductoryOfferEligibilityJws === "signed.jws.value", "JWS");
  assert(calls.sign === 1, "signed once");
});

Deno.test("eligibility: an unused trial signs nothing", async () => {
  const { d, calls } = deps({ trialUsed: () => Promise.resolve(false) });
  const response = await createOfferEligibilityHandler(d)(request(valid));
  const body = await response.json();
  assert(response.status === 200 && body.trialAvailable === true, "available");
  assert(
    !("introductoryOfferEligibilityJws" in body) && calls.sign === 0,
    "no JWS",
  );
});

Deno.test("eligibility: auth, product and failure guards", async () => {
  const cases: [Request, Partial<OfferEligibilityDeps>, number][] = [
    [request(valid, null), {}, 401],
    [request(valid, "other"), {}, 401],
    [
      request({ ...valid, productId: "com.yulalab.lissom.individual.yearly" }),
      {},
      400,
    ],
    [
      request({ ...valid, productId: "com.yulalab.jablab.motionplus.yearly" }),
      {},
      400,
    ],
    [request({ ...valid, appId: "other" }), {}, 400],
    [request({ ...valid, appTransactionId: "x y" }), {}, 400],
    [request(valid), { trialUsed: () => Promise.resolve(null) }, 503],
    [
      request(valid),
      {
        signDenial: () => {
          throw new StoreConfigurationError("missing key");
        },
      },
      503,
    ],
  ];
  for (const [req, overrides, status] of cases) {
    const { d } = deps(overrides);
    const response = await createOfferEligibilityHandler(d)(req);
    assert(
      response.status === status,
      `expected ${status}, got ${response.status}`,
    );
  }
});

function b64urlDecode(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "===".slice((value.length + 3) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

Deno.test("the production signer emits Apple's introductory-offer-eligibility JWS", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----`;
  const env: Record<string, string> = {
    MOTION_APPLE_IAP_PRIVATE_KEY: pem.replaceAll("\n", "\\n"),
    MOTION_APPLE_IAP_KEY_ID: "TESTKEY123",
    MOTION_APPLE_IAP_ISSUER_ID: "00000000-0000-0000-0000-000000000000",
  };
  const jws = signIntroductoryOfferDenial(
    "lissom",
    valid.productId,
    valid.appTransactionId,
    (name) => env[name],
  );
  const [head, payload, signature] = jws.split(".");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(head)));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(payload)));
  assert(header.alg === "ES256" && header.kid === "TESTKEY123", "header");
  assert(claims.aud === "introductory-offer-eligibility", "audience");
  assert(claims.iss === env.MOTION_APPLE_IAP_ISSUER_ID, "issuer");
  assert(claims.bid === "com.yulalab.lissom", "bundle");
  assert(claims.productId === valid.productId, "product");
  assert(claims.allowIntroductoryOffer === false, "denial");
  assert(claims.transactionId === valid.appTransactionId, "transaction");
  assert(
    typeof claims.nonce === "string" && claims.nonce.length >= 32,
    "nonce",
  );
  const verified = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    b64urlDecode(signature),
    new TextEncoder().encode(`${head}.${payload}`),
  );
  assert(verified, "ES256 signature verifies with the key's public half");
  let missing = false;
  try {
    signIntroductoryOfferDenial(
      "lissom",
      valid.productId,
      "1",
      () => undefined,
    );
  } catch (error) {
    missing = error instanceof StoreConfigurationError;
  }
  assert(missing, "missing key is a configuration error");
});

Deno.test("Play trial detection: Motion+ trial tag or free-trial phase", () => {
  const line = (offer: Record<string, unknown>, extra = {}) => ({
    productId: "jablab_motion_plus",
    offerDetails: { basePlanId: "monthly", ...offer },
    ...extra,
  });
  assert(
    googleFreeTrial({}, line({ offerTags: ["motion-plus-trial"] })),
    "tag",
  );
  assert(
    googleFreeTrial({}, line({}, { offerPhase: { freeTrial: {} } })),
    "line phase",
  );
  assert(
    googleFreeTrial({ offerPhase: { freeTrial: {} } }, line({})),
    "purchase phase",
  );
  assert(
    !googleFreeTrial({}, line({ offerId: "free-trial", offerTags: [] })),
    "untagged",
  );
  assert(
    !googleFreeTrial({}, line({}, { offerPhase: { basePrice: {} } })),
    "base price",
  );
});
