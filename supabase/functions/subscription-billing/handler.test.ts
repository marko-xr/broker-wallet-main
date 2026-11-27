// Fakes for Tap, Google and the database. These prove the routes' refusals and
// ordering, not a real provider integration.
import { assertEquals } from "jsr:@std/assert@1";
import { handleBilling } from "./handler.ts";
import type { BillingDeps } from "./handler.ts";
import { parseAuthorize, parseCharge, TapClient } from "./tap_client.ts";
import { hmacSha256Hex, sha256Hex } from "../subscription-webhooks/provider_event.ts";
import { tapHashInput } from "../subscription-webhooks/tap.ts";
import { GooglePlayClient } from "../subscription-webhooks/google_play.ts";
import type { PlayDeps } from "../subscription-webhooks/play_service.ts";
import { sealToken } from "../subscription-webhooks/token_vault.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const ORDER = "22222222-2222-4222-8222-222222222222";
const UPDATE = "33333333-3333-4333-8333-333333333333";
const VAULT = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
const charge = (over: Record<string, unknown> = {}) => ({
  id: "chg_abcd",
  status: "CAPTURED",
  amount: 20,
  currency: "AED",
  live_mode: false,
  merchant: { id: "mer_1" },
  reference: { order: ORDER, gateway: "g", payment: "p" },
  customer: { id: "cus_1" },
  card: { id: "card_1", brand: "VISA", last_four: "4242", exp_month: 1, exp_year: 27 },
  payment_agreement: { id: "agr_1" },
  transaction: { url: "https://checkout.test/1", created: "1700" },
  ...over,
});
const authorize = (over: Record<string, unknown> = {}) => ({
  id: "auth_abcd",
  status: "AUTHORIZED",
  live_mode: false,
  metadata: { bw_card_update: UPDATE },
  customer: { id: "cus_1" },
  card: { id: "card_2", brand: "VISA", last_four: "1111" },
  payment_agreement: { id: "agr_2" },
  transaction: { url: "https://checkout.test/2" },
  ...over,
});
const playPurchase = (over: Record<string, unknown> = {}) => ({
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  externalAccountIdentifiers: { obfuscatedExternalAccountId: USER },
  lineItems: [{
    productId: "plus",
    expiryTime: "2027-01-01T00:00:00Z",
    autoRenewingPlan: { autoRenewEnabled: true },
    offerDetails: { basePlanId: "monthly" },
  }],
  ...over,
});

type Calls = [string, any][];
const tapRequests: string[] = [];

function playDeps(calls: Calls, stored: unknown, rpc: PlayDeps["rpc"]): PlayDeps {
  const send = ((url: string) => {
    calls.push([`google:${url.split("/applications/")[1]}`, null]);
    if (stored === null) return Promise.resolve(new Response("{}", { status: 404 }));
    if (String(url).includes("voidedpurchases")) return Promise.resolve(new Response("{}"));
    return Promise.resolve(new Response(JSON.stringify(stored)));
  }) as typeof fetch;
  return {
    client: new GooglePlayClient("com.example.app", () => Promise.resolve("access"), send),
    config: { packageName: "com.example.app", productId: "plus", basePlanCycles: { monthly: "monthly" } },
    vaultKey: VAULT,
    now: () => 1_800_000_000_000,
    rpc,
  };
}

function deps(calls: Calls, stored: unknown = charge(), over: Partial<BillingDeps> = {}, playState: unknown = playPurchase()): BillingDeps {
  const tapFetch = (url: string, init: RequestInit) => {
    tapRequests.push(`${init.method} ${url}`);
    if (init.method === "GET") return Promise.resolve(new Response(JSON.stringify(url.includes("/authorize/") ? authorize() : stored)));
    if (url.endsWith("/tokens")) return Promise.resolve(new Response('{"id":"tok_1"}'));
    if (url.endsWith("/void")) return Promise.resolve(new Response("{}"));
    if (url.endsWith("/authorize")) return Promise.resolve(new Response(JSON.stringify(authorize({ status: "INITIATED" }))));
    return Promise.resolve(new Response(JSON.stringify(charge({ status: "INITIATED" }))));
  };
  const rpc: BillingDeps["rpc"] = (name, args) => {
    calls.push([name, args]);
    if (name === "tap_create_order") return Promise.resolve({ order_id: ORDER, amount: 20, currency: "AED", tap_customer_id: null });
    if (name === "subscription_sync_claim") return Promise.resolve(true);
    if (name === "tap_settle_charge") return Promise.resolve("captured");
    if (name === "tap_charge_owner" || name === "tap_card_update_owner") return Promise.resolve(USER);
    if (name === "tap_card_update_create") return Promise.resolve({ update_id: UPDATE, tap_customer_id: "cus_1" });
    if (name === "tap_card_update_settle") return Promise.resolve("applied");
    if (name === "play_account_ref") return Promise.resolve("44444444-4444-4444-8444-444444444444");
    if (name === "play_apply_snapshot") return Promise.resolve({ outcome: "processed", acknowledge: false });
    if (["tap_claim_due_renewals", "tap_claim_stale_charges", "subscription_claim_reconcile_batch", "play_user_purchases", "play_claim_orphans", "play_purchase_ciphertexts"].includes(name)) {
      return Promise.resolve([]);
    }
    return Promise.resolve("ok");
  };
  return {
    play: playDeps(calls, playState, rpc),
    reconcileSecret: "job",
    verifyUser: (t) => Promise.resolve(t === "good" ? { id: USER, email: null, phone: "+971501234567" } : null),
    isCurrentSession: () => Promise.resolve(true),
    rpc,
    tap: new TapClient("sk_test", tapFetch),
    tapSecret: "sk_test",
    tapPublicKey: "pk_test_1",
    tapMerchantId: "mer_1",
    tapBillingEnabled: true,
    tapRenewalsEnabled: false,
    tapLiveMode: false,
    tapReturnUrl: "https://app.test/return",
    tapWebhookUrl: "https://x.test/tap/webhook",
    ...over,
  };
}
const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  new Request(`https://x.test/subscription-billing${path}`, { method: "POST", headers, body: JSON.stringify(body) });
const user = { authorization: "Bearer good" };
const names = (calls: Calls) => calls.map(([n]) => n);
const signed = async (body: Record<string, unknown>) =>
  post("/tap/webhook", body, { hashstring: await hmacSha256Hex("sk_test", tapHashInput(body)!) });

Deno.test("every Tap route is closed until billing is enabled", async () => {
  const calls: Calls = [];
  const off = deps(calls, charge(), { tapBillingEnabled: false });
  for (const [path, body] of [
    ["/tap/session", { cycle: "monthly" }],
    ["/tap/checkout", { cycle: "monthly" }],
    ["/tap/verify", { chargeId: "chg_abcd" }],
    ["/tap/renewal", { autoRenew: false }],
    ["/tap/card", {}],
    ["/tap/card/verify", { authorizeId: "auth_abcd" }],
  ] as [string, unknown][]) {
    assertEquals((await handleBilling(post(path, body, user), off)).status, 503, path);
  }
  assertEquals((await handleBilling(post("/tap/webhook", charge()), off)).status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("the session gives the server price and only this mode's public key", async () => {
  const calls: Calls = [];
  const answer = await (await handleBilling(post("/tap/session", { cycle: "annual" }, user), deps(calls))).json();
  assertEquals([answer.publicKey, answer.amount, answer.currency], ["pk_test_1", 180, "AED"]);
  const crossed = deps(calls, charge(), { tapPublicKey: "pk_live_1" });
  assertEquals((await handleBilling(post("/tap/session", { cycle: "monthly" }, user), crossed)).status, 503);
  const reverse = deps(calls, charge(), { tapLiveMode: true });
  assertEquals((await handleBilling(post("/tap/session", { cycle: "monthly" }, user), reverse)).status, 503);
});

Deno.test("checkout names a cycle and at most a card token", async () => {
  const calls: Calls = [];
  for (
    const body of [
      { cycle: "daily" },
      { cycle: "monthly", amount: 1 },
      { cycle: "monthly", user_id: "x" },
      { cycle: "monthly", token: "card_123" },
      { cycle: "monthly", token: 5 },
      {},
    ]
  ) {
    assertEquals((await handleBilling(post("/tap/checkout", body, user), deps(calls))).status, 400);
  }
  assertEquals(calls.length, 0);
});

Deno.test("checkout needs a signed-in current session", async () => {
  const calls: Calls = [];
  assertEquals((await handleBilling(post("/tap/checkout", { cycle: "monthly" }), deps(calls))).status, 401);
  const replaced = deps(calls, charge(), { isCurrentSession: () => Promise.resolve(false) });
  assertEquals((await handleBilling(post("/tap/checkout", { cycle: "monthly" }, user), replaced)).status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("checkout stops cleanly when the database refuses the sale", async () => {
  const calls: Calls = [];
  const base = deps(calls);
  const refusing = {
    ...base,
    rpc: (name: string, args: Record<string, unknown>) =>
      name === "tap_create_order" ? Promise.reject(new Error("tax_profile_incomplete")) : base.rpc(name, args),
  };
  tapRequests.length = 0;
  const response = await handleBilling(post("/tap/checkout", { cycle: "monthly" }, user), refusing);
  assertEquals([response.status, (await response.json()).code], [503, "billing_not_ready"]);
  assertEquals(tapRequests.length, 0);
});

Deno.test("checkout never activates anything by itself", async () => {
  const calls: Calls = [];
  const answer = await (await handleBilling(post("/tap/checkout", { cycle: "monthly", token: "tok_abcd" }, user), deps(calls))).json();
  assertEquals([answer.ok, answer.chargeId, answer.checkoutUrl], [true, "chg_abcd", "https://checkout.test/1"]);
  assertEquals(names(calls).includes("tap_settle_charge"), false);
});

Deno.test("a forged webhook touches nothing", async () => {
  const calls: Calls = [];
  const response = await handleBilling(post("/tap/webhook", charge(), { hashstring: "0".repeat(64) }), deps(calls));
  assertEquals(response.status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("the settled status comes from Tap's record, not the webhook", async () => {
  const calls: Calls = [];
  await handleBilling(await signed(charge()), deps(calls, charge({ status: "DECLINED" })));
  const settle = calls.find(([n]) => n === "tap_settle_charge")!;
  assertEquals(settle[1].p_status, "DECLINED");
});

Deno.test("a charge Tap cannot confirm is retried, not settled", async () => {
  const calls: Calls = [];
  const response = await handleBilling(await signed(charge()), deps(calls, { id: "chg_other" }));
  assertEquals(response.status, 503);
  assertEquals(names(calls).includes("tap_settle_charge"), false);
});

Deno.test("a charge from the other Tap mode or merchant is not settled", async () => {
  for (const stored of [charge({ live_mode: true }), charge({ merchant: { id: "mer_other" } })]) {
    const calls: Calls = [];
    const response = await handleBilling(await signed(charge()), deps(calls, stored));
    assertEquals((await response.json()).outcome, "wrong_mode");
    assertEquals(names(calls).includes("tap_settle_charge"), false);
  }
});

Deno.test("a returning browser can only settle its own charge, from Tap's record", async () => {
  const calls: Calls = [];
  const declined = deps(calls, charge({ status: "DECLINED" }));
  await handleBilling(post("/tap/verify", { chargeId: "chg_abcd" }, user), declined);
  assertEquals(calls.find(([n]) => n === "tap_settle_charge")![1].p_status, "DECLINED");

  const other: Calls = [];
  const base = deps(other);
  const foreign = { ...base, rpc: (name: string, args: Record<string, unknown>) => name === "tap_charge_owner" ? Promise.resolve("someone-else") : base.rpc(name, args) };
  assertEquals((await handleBilling(post("/tap/verify", { chargeId: "chg_abcd" }, user), foreign)).status, 404);
  assertEquals(names(other).includes("tap_settle_charge"), false);
});

Deno.test("a card change is settled from Tap's record and voids its hold", async () => {
  const calls: Calls = [];
  tapRequests.length = 0;
  const started = await (await handleBilling(post("/tap/card", { token: "tok_abcd" }, user), deps(calls))).json();
  assertEquals([started.ok, started.authorizeId], [true, "auth_abcd"]);
  assertEquals(names(calls).includes("tap_card_update_settle"), false);
  const verified = await (await handleBilling(post("/tap/card/verify", { authorizeId: "auth_abcd" }, user), deps(calls))).json();
  assertEquals(verified.outcome, "applied");
  assertEquals(tapRequests.some((r) => r.startsWith("POST") && r.endsWith("/authorize/auth_abcd/void")), true);
});

Deno.test("the job needs its secret", async () => {
  const calls: Calls = [];
  assertEquals((await handleBilling(post("/reconcile", {}), deps(calls))).status, 401);
  assertEquals((await handleBilling(post("/reconcile", {}, { "x-reconcile-secret": "no" }), deps(calls))).status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("with renewals off the job claims no renewal", async () => {
  const calls: Calls = [];
  const response = await handleBilling(post("/reconcile", {}, { "x-reconcile-secret": "job" }), deps(calls));
  assertEquals((await response.json()).renewals, { skipped: true });
  assertEquals(names(calls).includes("tap_claim_due_renewals"), false);
});

Deno.test("the job re-reads open charges from Tap", async () => {
  const calls: Calls = [];
  const base = deps(calls);
  const withStale = { ...base, rpc: (name: string, args: Record<string, unknown>) => name === "tap_claim_stale_charges" ? Promise.resolve([{ order_id: ORDER, tap_charge_id: "chg_abcd" }]) : base.rpc(name, args) };
  const answer = await (await handleBilling(post("/reconcile", {}, { "x-reconcile-secret": "job" }), withStale)).json();
  assertEquals(answer.charges, { captured: 1 });
});

Deno.test("the job cancels renewal for a deleted account", async () => {
  const calls: Calls = [];
  const hash = await sha256Hex("orphan");
  const sealed = await sealToken(VAULT, "orphan", hash);
  const base = deps(calls);
  const rpc = (name: string, args: Record<string, unknown>) =>
    name === "play_claim_orphans"
      ? Promise.resolve([{ token_sha256: hash, token_ciphertext: sealed, product_id: "plus" }])
      : base.rpc(name, args);
  const answer = await (await handleBilling(post("/reconcile", {}, { "x-reconcile-secret": "job" }), { ...base, rpc, play: { ...base.play!, rpc } })).json();
  assertEquals(answer.store.orphan_canceled, 1);
  assertEquals(calls.some(([n]) => n.includes("/tokens/orphan:cancel")), true);
});

Deno.test("Play prepare and verify are for the token's own account", async () => {
  const calls: Calls = [];
  const prepared = await (await handleBilling(post("/play/prepare", {}, user), deps(calls))).json();
  assertEquals(prepared.accountRef, "44444444-4444-4444-8444-444444444444");
  assertEquals(calls.find(([n]) => n === "play_account_ref")![1].p_user, USER);

  await handleBilling(post("/play/verify", { purchaseTokens: ["tok"] }, user), deps(calls));
  const applied = calls.find(([n]) => n === "play_apply_snapshot")!;
  assertEquals(applied[1].p_caller, USER);
  assertEquals(JSON.stringify(applied[1]).includes('"tok"'), false);
});

Deno.test("Play verify accepts tokens and nothing else", async () => {
  const calls: Calls = [];
  for (
    const body of [
      {},
      { purchaseTokens: [] },
      { purchaseTokens: "tok" },
      { purchaseTokens: [1] },
      { purchaseTokens: ["a", "b", "c", "d", "e", "f"] },
      { purchaseTokens: ["tok"], user_id: "x" },
      { purchaseTokens: ["x".repeat(5000)] },
    ]
  ) {
    assertEquals((await handleBilling(post("/play/verify", body, user), deps(calls))).status, 400);
  }
  assertEquals(calls.length, 0);
  assertEquals((await handleBilling(post("/play/verify", { purchaseTokens: ["tok"] }), deps(calls))).status, 401);
});

Deno.test("a purchase on another account is refused, and an unknown one is not found", async () => {
  const conflict: Calls = [];
  const base = deps(conflict);
  const rpc = (name: string, args: Record<string, unknown>) =>
    name === "play_apply_snapshot" ? Promise.resolve({ outcome: "ownership_conflict", acknowledge: false }) : base.rpc(name, args);
  const refused = await handleBilling(post("/play/verify", { purchaseTokens: ["tok"] }, user), { ...base, rpc, play: { ...base.play!, rpc } });
  assertEquals([refused.status, (await refused.json()).code], [409, "purchase_linked_to_another_account"]);

  const missing = await handleBilling(post("/play/verify", { purchaseTokens: ["tok"] }, user), deps([], charge(), {}, null));
  assertEquals([missing.status, (await missing.json()).code], [404, "purchase_not_found"]);
});

Deno.test("a closed Play channel answers 503 and calls nothing", async () => {
  const calls: Calls = [];
  const off = deps(calls, charge(), { play: null });
  for (const path of ["/sync", "/play/prepare", "/play/verify"]) {
    assertEquals((await handleBilling(post(path, { purchaseTokens: ["t"] }, user), off)).status, 503);
  }
  assertEquals(calls.length, 0);
});

Deno.test("a malformed charge or authorize is not one", () => {
  assertEquals(parseCharge(null), null);
  assertEquals(parseCharge({ id: "x", status: "CAPTURED", amount: 1, currency: "AED", live_mode: true }), null);
  assertEquals(parseCharge(charge({ live_mode: undefined })), null);
  assertEquals(parseCharge(charge({ amount: "abc" })), null);
  assertEquals(parseAuthorize(null), null);
  assertEquals(parseAuthorize(authorize({ id: "chg_1" })), null);
  assertEquals(parseAuthorize(authorize({ live_mode: "true" })), null);
});

Deno.test("a browser may call only from an exact configured origin", async () => {
  const d = deps([], charge(), { allowedOrigins: ["https://app.test"] });
  const preflight = (origin: string) =>
    handleBilling(new Request("https://x.test/subscription-billing/tap/session", { method: "OPTIONS", headers: { origin } }), d);
  const good = await preflight("https://app.test");
  assertEquals([good.status, good.headers.get("access-control-allow-origin")], [204, "https://app.test"]);
  for (const origin of ["https://evil.test", "https://app.test.evil.test", "null"]) {
    const bad = await preflight(origin);
    assertEquals([bad.status, bad.headers.get("access-control-allow-origin")], [403, null]);
  }
  const foreign = await handleBilling(post("/tap/session", { cycle: "monthly" }, { ...user, origin: "https://evil.test" }), d);
  assertEquals(foreign.headers.get("access-control-allow-origin"), null);
});

Deno.test("only POST is accepted, and unknown paths are not found", async () => {
  const calls: Calls = [];
  assertEquals((await handleBilling(new Request("https://x.test/sync"), deps(calls))).status, 405);
  assertEquals((await handleBilling(post("/nope", {}), deps(calls))).status, 404);
});
