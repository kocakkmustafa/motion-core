import { reviewGrantIsActive } from "./motion_review_access.ts";

const alice = "11111111-1111-1111-1111-111111111111";
const bob = "22222222-2222-2222-2222-222222222222";
const now = new Date("2026-09-25T00:00:00Z");

Deno.test("store review access requires the authenticated owner", () => {
  const grant = {
    user_id: alice,
    purpose: "store_review",
    expires_at: "2026-10-25T00:00:00Z",
  };
  if (!reviewGrantIsActive(grant, alice, now)) throw Error("owner denied");
  if (reviewGrantIsActive(grant, bob, now)) throw Error("other user granted");
});

Deno.test("expired or malformed store review grants never unlock access", () => {
  for (
    const expires_at of [
      "2026-09-24T23:59:59Z",
      "2026-09-25T00:00:00Z",
      "not-a-time",
    ]
  ) {
    if (
      reviewGrantIsActive(
        {
          user_id: alice,
          purpose: "store_review",
          expires_at,
        },
        alice,
        now,
      )
    ) throw Error(`unexpected grant: ${expires_at}`);
  }
  if (
    reviewGrantIsActive(
      {
        user_id: alice,
        purpose: "customer",
        expires_at: "2026-10-25T00:00:00Z",
      },
      alice,
      now,
    )
  ) throw Error("wrong purpose granted");
  if (reviewGrantIsActive(null, alice, now)) throw Error("missing grant");
});
