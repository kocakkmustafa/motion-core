import {
  entitlementWriteFromProvider,
  expectedAccountMarker,
  originatingAppForStoredProduct,
  type ProviderVerifiedPurchase,
  purchaseScope,
} from "./motion_purchase_claim.ts";

const alice = "11111111-1111-1111-1111-111111111111";
const bob = "22222222-2222-2222-2222-222222222222";
const now = new Date("2026-09-24T16:00:00Z");

function apple(overrides: Partial<ProviderVerifiedPurchase> = {}) {
  return {
    store: "apple",
    originatingAppId: "ostinato",
    productId: "com.yulalab.ostinato.individual.monthly",
    accountMarker: alice,
    reference: "apple-original-1",
    state: "active",
    expiresAt: "2026-10-24T16:00:00Z",
    ...overrides,
  } as ProviderVerifiedPurchase;
}

Deno.test("fixed product map respects app and Motion+ scope", () => {
  if (
    purchaseScope(
      "apple",
      "ostinato",
      "com.yulalab.ostinato.motionplus.yearly",
    ) !== "motion_plus"
  ) throw Error("Motion+ scope");
  if (
    purchaseScope(
      "apple",
      "ostinato",
      "com.yulalab.gravita.individual.yearly",
    ) !== null
  ) throw Error("cross-app product");
  if (
    purchaseScope("google", "jablab", "jablab_individual", "yearly") !==
      "jablab"
  ) throw Error("Google plan");
  if (
    purchaseScope("google", "jablab", "jablab_individual", "trial") !== null
  ) throw Error("unsupported plan");
  if (
    originatingAppForStoredProduct(
      "apple",
      "com.yulalab.lissom.motionplus.yearly",
    ) !== "lissom"
  ) throw Error("Apple origin");
  if (
    originatingAppForStoredProduct("google", "choreia_motion_plus") !==
      "choreia"
  ) throw Error("Google origin");
  if (
    originatingAppForStoredProduct("google", "stranger_motion_plus") !== null
  ) throw Error("unknown origin");
});

Deno.test("the store marker is bound to the authenticated UUID", async () => {
  const googleMarker = await expectedAccountMarker("google", alice);
  if (googleMarker?.length !== 64) throw Error("Google hash");
  const valid = await entitlementWriteFromProvider(apple(), alice, now);
  if (valid?.app_id !== "ostinato" || valid.state !== "active") {
    throw Error("valid purchase");
  }
  if (await entitlementWriteFromProvider(apple(), bob, now) !== null) {
    throw Error("cross-user claim");
  }
  if (
    await entitlementWriteFromProvider(
      apple({ accountMarker: "" }),
      alice,
      now,
    ) !== null
  ) throw Error("missing token");
  if (await entitlementWriteFromProvider(apple(), "not-a-uuid", now) !== null) {
    throw Error("invalid user");
  }
});

Deno.test("Google Motion+ can cover all apps only with its own account marker", async () => {
  const marker = await expectedAccountMarker("google", alice);
  const claim = apple({
    store: "google",
    originatingAppId: "lissom",
    productId: "lissom_motion_plus",
    basePlanId: "yearly",
    accountMarker: marker!,
    reference: "play-token-1",
  });
  const row = await entitlementWriteFromProvider(claim, alice, now);
  if (row?.app_id !== "motion_plus" || row.store !== "google") {
    throw Error("Motion+ row");
  }
  if (
    await entitlementWriteFromProvider(
      { ...claim, productId: "jablab_motion_plus" },
      alice,
      now,
    ) !== null
  ) throw Error("cross-package product");
});

Deno.test("provider state and expiry deny revoked, held and expired rights", async () => {
  for (
    const [providerState, expected] of [
      ["grace", "grace"],
      ["canceled", "active"],
      ["hold", "expired"],
      ["revoked", "revoked"],
      ["expired", "expired"],
    ] as const
  ) {
    const row = await entitlementWriteFromProvider(
      apple({ state: providerState }),
      alice,
      now,
    );
    if (row?.state !== expected) throw Error(`state ${providerState}`);
  }
  const elapsed = await entitlementWriteFromProvider(
    apple({ expiresAt: "2026-09-23T16:00:00Z" }),
    alice,
    now,
  );
  if (elapsed?.state !== "expired") throw Error("elapsed expiry");
  if (
    await entitlementWriteFromProvider(
      apple({ expiresAt: "unknown" }),
      alice,
      now,
    ) !== null
  ) throw Error("invalid expiry");
});
