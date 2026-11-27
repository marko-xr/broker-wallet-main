// Constructed Google and Tap payloads only: this proves our logic, never a real
// provider integration.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { handleWebhook } from "./handler.ts";
import type { WebhookDeps } from "./handler.ts";
import { GooglePlayClient, mapPlaySubscription, parsePlayNotification } from "./google_play.ts";
import type { PlayConfig, PlaySnapshot } from "./google_play.ts";
import { verifyPushToken } from "./google_auth.ts";
import type { JwkSet } from "./google_auth.ts";
import type { PlayDeps } from "./play_service.ts";
import { openToken, sealToken } from "./token_vault.ts";
import { tapAmount, tapHashInput, verifyTapHash } from "./tap.ts";
import { constantTimeEqual, hmacSha256Hex, sha256Hex } from "./provider_event.ts";

const REF = "11111111-1111-4111-8111-111111111111";
const AS_OF = "2026-11-24T10:00:00.000Z";
const FUTURE = "2026-12-24T10:00:00.000Z";
const PAST = "2026-11-01T10:00:00.000Z";
const config: PlayConfig = {
  packageName: "com.example.app",
  productId: "plus",
  basePlanCycles: { monthly: "monthly", annual: "annual" },
};
const purchase = (over: Record<string, unknown> = {}, item: Record<string, unknown> = {}) => ({
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  startTime: "2026-11-01T10:00:00Z",
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  externalAccountIdentifiers: { obfuscatedExternalAccountId: REF },
  lineItems: [{
    productId: "plus",
    expiryTime: FUTURE,
    latestSuccessfulOrderId: "GPA.1",
    autoRenewingPlan: { autoRenewEnabled: true },
    offerDetails: { basePlanId: "monthly" },
    ...item,
  }],
  ...over,
});
const map = (over: Record<string, unknown> = {}, item: Record<string, unknown> = {}) =>
  mapPlaySubscription(purchase(over, item), config, AS_OF) as PlaySnapshot;
const ignored = (raw: unknown) => (mapPlaySubscription(raw, config, AS_OF) as { ignored?: string }).ignored;

Deno.test("constant-time compare is exact", () => {
  assertEquals(constantTimeEqual("abc", "abc"), true);
  assertEquals(constantTimeEqual("abc", "abd"), false);
  assertEquals(constantTimeEqual("abc", "abcd"), false);
});

Deno.test("Tap hash input follows the documented order", () => {
  assertEquals(
    tapHashInput({
      id: "chg_1",
      amount: 20,
      currency: "AED",
      status: "CAPTURED",
      reference: { gateway: "g1", payment: "p1" },
      transaction: { created: "1700" },
    }),
    "x_idchg_1x_amount20.00x_currencyAEDx_gateway_referenceg1x_payment_referencep1x_statusCAPTUREDx_created1700",
  );
  assertEquals(tapAmount(180, "AED"), "180.00");
  assertEquals(tapAmount(20, "AED"), "20.00");
  assertEquals(tapAmount(10, "USD"), null);
});

Deno.test("a Tap hash must match the charge", async () => {
  const charge = {
    id: "chg_1",
    amount: 20,
    currency: "AED",
    status: "CAPTURED",
    reference: { gateway: "", payment: "p" },
    transaction: { created: "1" },
  };
  const good = await hmacSha256Hex("tap", tapHashInput(charge)!);
  assertEquals(await verifyTapHash("tap", good, charge), true);
  assertEquals(await verifyTapHash("tap", good, { ...charge, amount: 1 }), false);
  assertEquals(await verifyTapHash("tap", null, charge), false);
});

Deno.test("each Play state keeps its own meaning", () => {
  assertEquals([map().state, map().autoRenew], ["active", true]);
  const off = map({}, { autoRenewingPlan: { autoRenewEnabled: false } });
  assertEquals([off.state, off.autoRenew, off.paidThroughAt], ["cancel_scheduled", false, FUTURE]);
  const canceled = map({ subscriptionState: "SUBSCRIPTION_STATE_CANCELED" });
  assertEquals([canceled.state, canceled.autoRenew, canceled.paidThroughAt], ["cancel_scheduled", false, FUTURE]);
  const grace = map({ subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" });
  assertEquals([grace.state, grace.graceUntil], ["billing_issue", FUTURE]);
  assertEquals(map({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" }, { expiryTime: PAST }).state, "expired");
});

Deno.test("account hold and pause give no access, whatever date Google carries", () => {
  for (const subscriptionState of ["SUBSCRIPTION_STATE_ON_HOLD", "SUBSCRIPTION_STATE_PAUSED"]) {
    const snapshot = map({ subscriptionState });
    assertEquals(snapshot.paidThroughAt, AS_OF);
    assertEquals(snapshot.graceUntil, null);
  }
});

Deno.test("a pending or unknown Play state never carries an entitlement", () => {
  for (const subscriptionState of ["SUBSCRIPTION_STATE_PENDING", "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED", "NEW_VALUE"]) {
    const snapshot = map({ subscriptionState });
    assertEquals([snapshot.state, snapshot.paidThroughAt], ["unknown", null]);
  }
});

Deno.test("only the configured auto-renewing product counts", () => {
  assertEquals(ignored(null), "malformed");
  assertEquals(ignored(purchase({}, { productId: "other" })), "unknown_product");
  assertEquals(ignored(purchase({}, { offerDetails: { basePlanId: "weekly" } })), "unknown_base_plan");
  assertEquals(ignored(purchase({}, { autoRenewingPlan: undefined, prepaidPlan: {} })), "not_auto_renewing");
  assertEquals(ignored(purchase({}, { expiryTime: undefined })), "missing_expiry");
});

Deno.test("a test purchase is labelled sandbox", () => {
  assertEquals(map().environment, "production");
  assertEquals(map({ testPurchase: {} }).environment, "sandbox");
});

Deno.test("only a well-formed account reference is read", () => {
  assertEquals(map().accountRef, REF);
  assertEquals(map({ externalAccountIdentifiers: { obfuscatedExternalAccountId: "someone" } }).accountRef, null);
  assertEquals(map({ externalAccountIdentifiers: undefined }).accountRef, null);
});

Deno.test("a replaced token is reported from either Google field", () => {
  assertEquals(map({ linkedPurchaseToken: "old" }).linkedPurchaseToken, "old");
  assertEquals(map({ outOfAppPurchaseContext: { expiredPurchaseToken: "old2" } }).linkedPurchaseToken, "old2");
});

Deno.test("notifications parse by kind", () => {
  assertEquals(parsePlayNotification({ packageName: "p", testNotification: {} })?.kind, "test");
  assertEquals(
    parsePlayNotification({ packageName: "p", subscriptionNotification: { purchaseToken: "t", notificationType: 4 } })?.kind,
    "subscription",
  );
  assertEquals(
    parsePlayNotification({ packageName: "p", voidedPurchaseNotification: { purchaseToken: "t", productType: 1 } })?.kind,
    "voided",
  );
  assertEquals(
    parsePlayNotification({ packageName: "p", voidedPurchaseNotification: { purchaseToken: "t", productType: 2 } })?.kind,
    "other",
  );
  assertEquals(parsePlayNotification({ subscriptionNotification: {} }), null);
  assertEquals(parsePlayNotification({ packageName: "p", subscriptionNotification: { notificationType: 4 } }), null);
});

Deno.test("the token vault opens only its own ciphertext", async () => {
  const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));
  const other = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));
  const sealed = await sealToken(key, "purchase-token", "a".repeat(64));
  assertEquals(sealed.includes("purchase-token"), false);
  assertEquals(await openToken(key, sealed, "a".repeat(64)), "purchase-token");
  await assertRejects(() => openToken(key, sealed, "b".repeat(64)));
  await assertRejects(() => openToken(other, sealed, "a".repeat(64)));
  await assertRejects(() => sealToken("c2hvcnQ=", "x", "a".repeat(64)));
});

// A real RS256 key pair, standing in for Google's signing key.
const pair = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true,
  ["sign", "verify"],
);
const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
const keys: JwkSet = { keys: [{ ...jwk, kid: "k1" }] };
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encode = (value: unknown) => b64url(new TextEncoder().encode(JSON.stringify(value)));
const identity = { audience: "https://x.test/push", serviceAccountEmail: "push@example.iam.gserviceaccount.com" };
const NOW = 2_000_000;
const goodClaims = {
  iss: "https://accounts.google.com",
  aud: identity.audience,
  email: identity.serviceAccountEmail,
  email_verified: true,
  iat: NOW - 10,
  exp: NOW + 3000,
};
async function jwt(claims: Record<string, unknown> = goodClaims, header: Record<string, unknown> = { alg: "RS256", kid: "k1" }) {
  const body = `${encode(header)}.${encode(claims)}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, new TextEncoder().encode(body));
  return `${body}.${b64url(new Uint8Array(signature))}`;
}
const verify = (token: string) => verifyPushToken(token, identity, NOW, () => Promise.resolve(keys));

Deno.test("a push token must be Google's, for this subscription, and current", async () => {
  assertEquals(await verify(await jwt()), true);
  assertEquals(await verify(await jwt({ ...goodClaims, aud: "other" })), false);
  assertEquals(await verify(await jwt({ ...goodClaims, email: "attacker@example.com" })), false);
  assertEquals(await verify(await jwt({ ...goodClaims, email_verified: false })), false);
  assertEquals(await verify(await jwt({ ...goodClaims, iss: "https://evil.test" })), false);
  assertEquals(await verify(await jwt({ ...goodClaims, exp: NOW - 120 })), false);
  assertEquals(await verify(await jwt(goodClaims, { alg: "none", kid: "k1" })), false);
  assertEquals(await verify(await jwt(goodClaims, { alg: "RS256", kid: "unknown" })), false);
  assertEquals(await verify("not.a.jwt"), false);
});

Deno.test("a push token with an altered body fails its signature", async () => {
  const [head, , signature] = (await jwt()).split(".");
  const forged = encode({ ...goodClaims, email: identity.serviceAccountEmail, exp: NOW + 9999 });
  assertEquals(await verify(`${head}.${forged}.${signature}`), false);
});

// The real client, over a fake transport, so URLs and verbs are exercised too.
function play(
  calls: [string, any][],
  stored: unknown,
  over: { rpc?: PlayDeps["rpc"]; ackStatus?: number } = {},
): { deps: PlayDeps; urls: string[] } {
  const urls: string[] = [];
  const send = ((url: string, init: RequestInit) => {
    urls.push(`${init.method} ${url}`);
    if (String(url).endsWith(":acknowledge")) return Promise.resolve(new Response("{}", { status: over.ackStatus ?? 200 }));
    if (stored === null) return Promise.resolve(new Response("{}", { status: 404 }));
    return Promise.resolve(new Response(JSON.stringify(stored)));
  }) as typeof fetch;
  return {
    urls,
    deps: {
      client: new GooglePlayClient(config.packageName, () => Promise.resolve("access"), send),
      config,
      vaultKey: btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
      now: () => Date.parse(AS_OF),
      rpc: over.rpc ?? ((name, args) => {
        calls.push([name, args]);
        return Promise.resolve(
          name === "play_apply_snapshot"
            ? { outcome: "processed", acknowledge: args.p_ack_pending === true }
            : null,
        );
      }),
    },
  };
}

async function push(notification: Record<string, unknown>, token: string | null, packageName = config.packageName) {
  const data = btoa(JSON.stringify({ packageName, ...notification }));
  return new Request("https://x.test/subscription-webhooks/google-play", {
    method: "POST",
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: JSON.stringify({ message: { data, messageId: "m1" }, subscription: "s" }),
  });
}
const webhookDeps = (playDeps: PlayDeps | null): WebhookDeps => ({
  play: playDeps,
  verifyPush: (token) => Promise.resolve(token === "good"),
});
const renewed = { subscriptionNotification: { purchaseToken: "tok", notificationType: 2 } };

Deno.test("a push without a valid token reads and applies nothing", async () => {
  const calls: [string, any][] = [];
  const { deps, urls } = play(calls, purchase());
  assertEquals((await handleWebhook(await push(renewed, null), webhookDeps(deps))).status, 401);
  assertEquals((await handleWebhook(await push(renewed, "forged"), webhookDeps(deps))).status, 401);
  assertEquals([calls.length, urls.length], [0, 0]);
});

Deno.test("a push for another app or a test message changes nothing", async () => {
  const calls: [string, any][] = [];
  const { deps, urls } = play(calls, purchase());
  assertEquals((await handleWebhook(await push(renewed, "good", "com.other"), webhookDeps(deps))).status, 200);
  assertEquals((await handleWebhook(await push({ testNotification: {} }, "good"), webhookDeps(deps))).status, 200);
  assertEquals([calls.length, urls.length], [0, 0]);
});

Deno.test("the applied state comes from Google, not from the notification", async () => {
  const calls: [string, any][] = [];
  const { deps, urls } = play(calls, purchase({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" }, { expiryTime: PAST }));
  assertEquals((await handleWebhook(await push(renewed, "good"), webhookDeps(deps))).status, 200);
  assertEquals(urls[0].includes("/purchases/subscriptionsv2/tokens/tok"), true);
  assertEquals(calls[0][1].p_state, "expired");
  assertEquals(calls[0][1].p_event_id, "rtdn:m1");
  assertEquals(calls[0][1].p_token_sha256, await sha256Hex("tok"));
  assertEquals(JSON.stringify(calls[0][1]).includes('"tok"'), false);
});

Deno.test("a new purchase is acknowledged only after the database accepts it", async () => {
  const calls: [string, any][] = [];
  const { deps, urls } = play(calls, purchase({ acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" }));
  assertEquals((await handleWebhook(await push(renewed, "good"), webhookDeps(deps))).status, 200);
  assertEquals(urls.some((u) => u.startsWith("POST") && u.endsWith("/purchases/subscriptions/plus/tokens/tok:acknowledge")), true);
  assertEquals(calls.map(([name]) => name), ["play_apply_snapshot", "play_mark_acknowledged"]);
});

Deno.test("a purchase the database refuses is never acknowledged", async () => {
  const { deps, urls } = play([], purchase({ acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" }), {
    rpc: () => Promise.resolve({ outcome: "ownership_conflict", acknowledge: false }),
  });
  await handleWebhook(await push(renewed, "good"), webhookDeps(deps));
  assertEquals(urls.some((u) => u.endsWith(":acknowledge")), false);
});

Deno.test("a failed acknowledgement asks Pub/Sub to deliver again", async () => {
  const calls: [string, any][] = [];
  const { deps } = play(calls, purchase({ acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" }), { ackStatus: 500 });
  assertEquals((await handleWebhook(await push(renewed, "good"), webhookDeps(deps))).status, 503);
  assertEquals(calls.map(([name]) => name), ["play_apply_snapshot"]);
});

Deno.test("a refund or revocation ends access once Google stops granting it", async () => {
  const expired = purchase({ subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" }, { expiryTime: PAST });
  let calls: [string, any][] = [];
  await handleWebhook(
    await push({ voidedPurchaseNotification: { purchaseToken: "tok", productType: 1, orderId: "GPA.1" } }, "good"),
    webhookDeps(play(calls, expired).deps),
  );
  assertEquals(calls[0][1].p_state, "refunded");
  calls = [];
  await handleWebhook(
    await push({ subscriptionNotification: { purchaseToken: "tok", notificationType: 12 } }, "good"),
    webhookDeps(play(calls, expired).deps),
  );
  assertEquals(calls[0][1].p_state, "revoked");
});

Deno.test("refunding an older order leaves a still-active subscription alone", async () => {
  const calls: [string, any][] = [];
  await handleWebhook(
    await push({ voidedPurchaseNotification: { purchaseToken: "tok", productType: 1 } }, "good"),
    webhookDeps(play(calls, purchase()).deps),
  );
  assertEquals(calls[0][1].p_state, "active");
});

Deno.test("a token Google does not know applies nothing", async () => {
  const calls: [string, any][] = [];
  const response = await handleWebhook(await push(renewed, "good"), webhookDeps(play(calls, null).deps));
  assertEquals((await response.json()).outcome, "not_found");
  assertEquals(calls.length, 0);
});

Deno.test("a database failure answers 500 so Pub/Sub retries", async () => {
  const { deps } = play([], purchase(), { rpc: () => Promise.reject(new Error("down")) });
  assertEquals((await handleWebhook(await push(renewed, "good"), webhookDeps(deps))).status, 500);
});

Deno.test("an unconfigured route applies nothing", async () => {
  assertEquals((await handleWebhook(await push(renewed, "good"), webhookDeps(null))).status, 503);
});

Deno.test("the webhook function serves only the Google route", async () => {
  const { deps } = play([], purchase());
  for (const path of ["revenuecat", "tap"]) {
    const request = new Request(`https://x.test/subscription-webhooks/${path}`, { method: "POST", body: "{}" });
    assertEquals((await handleWebhook(request, webhookDeps(deps))).status, 404);
  }
  assertEquals(
    (await handleWebhook(new Request("https://x.test/subscription-webhooks/google-play"), webhookDeps(deps))).status,
    405,
  );
});
