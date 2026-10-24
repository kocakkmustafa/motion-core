// The shared row refresh used by the membership check and by store server
// notifications: only a store-confirmed claim changes a stored row.
import {
  refreshStoredEntitlement,
  type StoredEntitlement,
  type StoreVerifiers,
} from "./motion_entitlement_refresh.ts";
import type { ProviderVerifiedPurchase } from "./motion_purchase_claim.ts";
import { StoreConfigurationError } from "./motion_store_provider.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

const userId = "11111111-1111-4111-8111-111111111111";
const now = new Date("2026-10-25T12:00:00Z");
const row: StoredEntitlement = {
  user_id: userId,
  app_id: "jablab",
  store: "apple",
  product_id: "com.yulalab.jablab.motionplus.monthly",
  original_transaction_id: "2000000000000001",
};

function fakeAdmin(fail = false) {
  const updates: { values: Record<string, unknown>; filters: string[] }[] = [];
  return {
    updates,
    from(_table: "motion_entitlements") {
      const entry = {
        values: {} as Record<string, unknown>,
        filters: [] as string[],
      };
      const chain = {
        update(values: Record<string, unknown>) {
          entry.values = values;
          return chain;
        },
        eq(column: string, value: string) {
          entry.filters.push(`${column}=${value}`);
          if (entry.filters.length === 3) {
            updates.push(entry);
            return Promise.resolve({ error: fail ? { message: "db" } : null });
          }
          return chain;
        },
      };
      return chain;
    },
  };
}

function claim(
  overrides: Partial<ProviderVerifiedPurchase> = {},
): ProviderVerifiedPurchase {
  return {
    store: "apple",
    originatingAppId: "jablab",
    productId: row.product_id,
    accountMarker: userId,
    reference: row.original_transaction_id,
    state: "active",
    expiresAt: "2026-11-25T12:00:00Z",
    ...overrides,
  };
}

function verifiers(
  result: ProviderVerifiedPurchase[] | Error,
): StoreVerifiers & { calls: number } {
  const v = {
    calls: 0,
    apple: () => {
      v.calls++;
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    },
    google: () => Promise.reject(new Error("wrong store")),
  };
  return v;
}

Deno.test("a store-confirmed active claim is written and grants", async () => {
  const admin = fakeAdmin();
  const result = await refreshStoredEntitlement(
    admin,
    row,
    now,
    verifiers([claim()]),
  );
  assert(result.ok && result.granting, "granting");
  assert(result.ok && result.appId === "motion_plus", "Motion+ scope");
  assert(admin.updates.length === 1, "one write");
  assert(admin.updates[0].values.state === "active", "active state");
  assert(
    admin.updates[0].filters.join() ===
      `store=apple,original_transaction_id=${row.original_transaction_id},user_id=${userId}`,
    "row scoped write",
  );
});

Deno.test("a missing or foreign transaction is revoked", async () => {
  for (
    const claims of [
      [],
      [claim({ accountMarker: "22222222-2222-4222-8222-222222222222" })],
    ]
  ) {
    const admin = fakeAdmin();
    const result = await refreshStoredEntitlement(
      admin,
      row,
      now,
      verifiers(claims),
    );
    assert(result.ok && !result.granting && result.appId === null, "denied");
    assert(admin.updates[0].values.state === "revoked", "revoked write");
  }
});

Deno.test("store and database failures never write a grant", async () => {
  const cases: [Error | ProviderVerifiedPurchase[], boolean, string][] = [
    [new StoreConfigurationError("missing key"), false, "store_not_configured"],
    [new Error("network"), false, "store_unavailable"],
    [[claim(), claim()], false, "membership_unavailable"],
    [[claim()], true, "membership_unavailable"],
  ];
  for (const [result, dbFails, expected] of cases) {
    const admin = fakeAdmin(dbFails);
    const outcome = await refreshStoredEntitlement(
      admin,
      row,
      now,
      verifiers(result),
    );
    assert(!outcome.ok && outcome.error === expected, expected);
  }
});

Deno.test("an unknown product is rejected before any store call", async () => {
  const v = verifiers([claim()]);
  const result = await refreshStoredEntitlement(
    fakeAdmin(),
    { ...row, product_id: "com.example.other" },
    now,
    v,
  );
  assert(!result.ok && result.error === "membership_unavailable", "rejected");
  assert(v.calls === 0, "no store call");
});
