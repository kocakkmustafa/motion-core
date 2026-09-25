import {
  APIException,
  Environment,
} from "npm:@apple/app-store-server-library@3.1.0";
import {
  appleStatusWithFallback,
  verifyGooglePurchase,
} from "./motion_store_provider.ts";

Deno.test("Apple status lookup uses production when it succeeds", async () => {
  const calls: Environment[] = [];
  const result = await appleStatusWithFallback((environment) => {
    calls.push(environment);
    return Promise.resolve("production-status");
  });
  if (
    result.environment !== Environment.PRODUCTION ||
    result.status !== "production-status" ||
    calls.length !== 1 || calls[0] !== Environment.PRODUCTION
  ) throw Error("production status lookup was not retained");
});

Deno.test("Apple transaction-not-found retries exactly once in sandbox", async () => {
  const calls: Environment[] = [];
  const result = await appleStatusWithFallback((environment) => {
    calls.push(environment);
    if (environment === Environment.PRODUCTION) {
      return Promise.reject(
        new APIException(404, 4040010, "Transaction id not found"),
      );
    }
    return Promise.resolve("sandbox-status");
  });
  if (
    result.environment !== Environment.SANDBOX ||
    result.status !== "sandbox-status" ||
    calls.length !== 2 ||
    calls[0] !== Environment.PRODUCTION ||
    calls[1] !== Environment.SANDBOX
  ) throw Error("sandbox fallback was not used");
});

Deno.test("Apple auth errors never fall back to sandbox", async () => {
  const calls: Environment[] = [];
  let rejected = false;
  try {
    await appleStatusWithFallback((environment) => {
      calls.push(environment);
      return Promise.reject(new APIException(401, 4010000, "Unauthorized"));
    });
  } catch (error) {
    rejected = error instanceof APIException && error.httpStatusCode === 401;
  }
  if (!rejected || calls.length !== 1 || calls[0] !== Environment.PRODUCTION) {
    throw Error("provider auth failure was masked by sandbox fallback");
  }
});

const evidence = {
  originatingAppId: "jablab" as const,
  productId: "jablab_individual",
  verificationData: "mock-play-purchase-token",
};

function toBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

Deno.test("Google verifier signs OAuth assertion and reads only the named package", async () => {
  const key = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const privateKey = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", key.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    toBase64(privateKey)
  }\n-----END PRIVATE KEY-----`;
  const account = JSON.stringify({
    client_email: "motion-test@example.iam.gserviceaccount.com",
    private_key: pem,
  });
  const previousSecret = Deno.env.get("MOTION_GOOGLE_PLAY_SERVICE_ACCOUNT");
  const originalFetch = globalThis.fetch;
  Deno.env.set("MOTION_GOOGLE_PLAY_SERVICE_ACCOUNT", account);
  let tokenCalls = 0;
  let purchaseCalls = 0;
  try {
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      if (url === "https://oauth2.googleapis.com/token") {
        tokenCalls++;
        const body = new URLSearchParams(String(init?.body));
        const assertion = body.get("assertion") ?? "";
        const parts = assertion.split(".");
        if (parts.length !== 3) throw Error("invalid JWT");
        const signature = Uint8Array.from(
          atob(parts[2].replaceAll("-", "+").replaceAll("_", "/")),
          (char) => char.charCodeAt(0),
        );
        const valid = await crypto.subtle.verify(
          "RSASSA-PKCS1-v1_5",
          key.publicKey,
          signature,
          new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
        );
        if (!valid) throw Error("invalid OAuth signature");
        return Response.json({ access_token: "test-oauth-token" });
      }
      purchaseCalls++;
      if (
        !url.includes("/applications/com.yulalab.jablab/") ||
        !url.endsWith("/tokens/mock-play-purchase-token") ||
        new Headers(init?.headers).get("Authorization") !==
          "Bearer test-oauth-token"
      ) throw Error("wrong Play lookup");
      return Response.json({
        subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
        externalAccountIdentifiers: {
          obfuscatedExternalAccountId: "a".repeat(64),
        },
        lineItems: [
          {
            productId: "jablab_individual",
            expiryTime: "2026-10-24T16:00:00Z",
            offerDetails: { basePlanId: "monthly" },
          },
          {
            productId: "gravita_individual",
            expiryTime: "2026-10-24T16:00:00Z",
            offerDetails: { basePlanId: "monthly" },
          },
        ],
      });
    };
    const claims = await verifyGooglePurchase(evidence);
    if (
      claims.length !== 1 || claims[0].productId !== "jablab_individual" ||
      claims[0].reference !== evidence.verificationData ||
      tokenCalls !== 1 || purchaseCalls !== 1
    ) throw Error("Google verified claim mismatch");
  } finally {
    globalThis.fetch = originalFetch;
    if (previousSecret === undefined) {
      Deno.env.delete("MOTION_GOOGLE_PLAY_SERVICE_ACCOUNT");
    } else {
      Deno.env.set("MOTION_GOOGLE_PLAY_SERVICE_ACCOUNT", previousSecret);
    }
  }
});

Deno.test("invalid Play evidence never produces a claim", async () => {
  if (
    (await verifyGooglePurchase({ ...evidence, verificationData: "" }))
      .length !== 0
  ) {
    throw Error("empty token accepted");
  }
  if (
    (await verifyGooglePurchase({
      ...evidence,
      verificationData: "x".repeat(4097),
    })).length !== 0
  ) throw Error("oversized token accepted");
});
