// Trusted billing operations. No route trusts an account id from a request:
// a user route takes it from the verified token, and the job route needs a secret.
//
//   POST /sync             signed-in user: re-read this account's Play purchases
//   POST /play/prepare     signed-in user: the opaque reference for a Play purchase
//   POST /play/verify      signed-in user: verify purchase tokens with Google
//   POST /reconcile        scheduled job: missed events, then due Tap renewals
//   POST /tap/session      signed-in user: public key and server price for checkout
//   POST /tap/checkout     signed-in user: start the card payment
//   POST /tap/verify       signed-in user: re-read a returning charge from Tap
//   POST /tap/renewal      signed-in user: turn card auto-renewal off or on
//   POST /tap/card         signed-in user: start replacing the saved card
//   POST /tap/card/verify  signed-in user: re-read a returning card change
//   POST /tap/webhook      Tap: verified by hash, then re-read from Tap
//
// All Tap routes answer 503 until TAP_BILLING_ENABLED=true. Renewals additionally
// need TAP_RENEWALS_ENABLED=true, because they charge saved cards.

import { processPlayToken } from "../subscription-webhooks/play_service.ts";
import type { PlayDeps } from "../subscription-webhooks/play_service.ts";
import { openToken } from "../subscription-webhooks/token_vault.ts";
import { verifyTapHash } from "../subscription-webhooks/tap.ts";
import type { TapCharge } from "../subscription-webhooks/tap.ts";
import { constantTimeEqual, hmacSha256Hex, sha256Hex } from "../subscription-webhooks/provider_event.ts";
import type { TapAuthorizeView, TapChargeView, TapClient } from "./tap_client.ts";

export interface BillingDeps {
  play: PlayDeps | null;
  reconcileSecret: string;
  verifyUser: (token: string) => Promise<{ id: string; email: string | null; phone: string | null } | null>;
  isCurrentSession: (token: string) => Promise<boolean>;
  rpc: (name: string, args: Record<string, unknown>) => Promise<any>;
  tap: TapClient | null;
  tapSecret: string;
  tapPublicKey: string;
  /** When set, a charge that names another merchant is refused. */
  tapMerchantId: string;
  tapBillingEnabled: boolean;
  tapRenewalsEnabled: boolean;
  /** The Tap mode this deployment must see on every charge. */
  tapLiveMode: boolean;
  tapReturnUrl: string;
  tapWebhookUrl: string;
  /** Exact web app origins allowed to call this function from a browser. */
  allowedOrigins?: string[];
}

const SYNC_INTERVAL_SECONDS = 20;
const VERIFY_INTERVAL_SECONDS = 3;
const MAX_BODY_BYTES = 64 * 1024;
const MAX_PLAY_TOKENS = 5;
const MAX_PLAY_TOKEN_LENGTH = 4096;
const VOIDED_LOOKBACK_MS = 2 * 24 * 60 * 60 * 1000;
const TAP_TOKEN = /^tok_[A-Za-z0-9_-]{4,128}$/;
const TAP_CHARGE = /^chg_[A-Za-z0-9_-]{4,128}$/;
const TAP_AUTHORIZE = /^auth_[A-Za-z0-9_-]{4,128}$/;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
const refuse = (status: number, code: string) => json(status, { ok: false, code });

async function signedInUser(request: Request, deps: BillingDeps) {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return null;
  const user = await deps.verifyUser(token).catch(() => null);
  if (!user) return null;
  return (await deps.isCurrentSession(token).catch(() => false)) ? user : null;
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) return null;
    const body = JSON.parse(raw);
    return typeof body === "object" && body !== null && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

const merchantMatches = (deps: BillingDeps, merchantId: string | null) =>
  !deps.tapMerchantId || !merchantId || merchantId === deps.tapMerchantId;

// ---------------------------------------------------------------------------
// Google Play
// ---------------------------------------------------------------------------

function playOutcomeResponse(outcomes: string[], ackFailed: boolean): Response {
  // A purchase that belongs to another account is never moved here.
  if (outcomes.includes("ownership_conflict")) return refuse(409, "purchase_linked_to_another_account");
  if (outcomes.includes("unlinked")) return refuse(409, "purchase_not_linked");
  return json(200, { ok: true, outcomes, ackPending: ackFailed });
}

async function handleSync(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.play) return refuse(503, "not_configured");
  if (!(await deps.rpc("subscription_sync_claim", { p_user: user.id, p_min_seconds: SYNC_INTERVAL_SECONDS }))) {
    return refuse(429, "too_soon");
  }
  const outcomes: string[] = [];
  let ackFailed = false;
  try {
    const rows = await deps.rpc("play_user_purchases", { p_user: user.id }) as any[];
    for (const row of rows ?? []) {
      const token = await openToken(deps.play.vaultKey, row.token_ciphertext, row.token_sha256);
      const result = await processPlayToken(deps.play, token, {
        caller: user.id,
        eventId: `sync:${row.token_sha256}:${deps.play.now()}`,
        eventType: "RECONCILED",
      });
      outcomes.push(result.outcome);
      ackFailed ||= result.ackFailed;
    }
  } catch {
    return refuse(503, "provider_unavailable");
  }
  return playOutcomeResponse(outcomes, ackFailed);
}

async function handlePlayPrepare(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.play) return refuse(503, "not_configured");
  const accountRef = await deps.rpc("play_account_ref", { p_user: user.id });
  if (typeof accountRef !== "string") return refuse(409, "no_account");
  return json(200, { ok: true, accountRef });
}

/** The client names purchase tokens and nothing else: Google says what they are. */
async function handlePlayVerify(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.play) return refuse(503, "not_configured");
  const body = await readBody(request);
  const tokens = body?.purchaseTokens;
  if (
    !body || Object.keys(body).length !== 1 || !Array.isArray(tokens) || tokens.length === 0 ||
    tokens.length > MAX_PLAY_TOKENS ||
    tokens.some((t) => typeof t !== "string" || t.length === 0 || t.length > MAX_PLAY_TOKEN_LENGTH)
  ) {
    return refuse(400, "invalid_request");
  }
  if (!(await deps.rpc("subscription_sync_claim", { p_user: user.id, p_min_seconds: VERIFY_INTERVAL_SECONDS }))) {
    return refuse(429, "too_soon");
  }
  const outcomes: string[] = [];
  let ackFailed = false;
  try {
    for (const token of tokens as string[]) {
      const result = await processPlayToken(deps.play, token, {
        caller: user.id,
        eventId: `verify:${await sha256Hex(token)}:${deps.play.now()}`,
        eventType: "CLIENT_VERIFY",
      });
      outcomes.push(result.outcome);
      ackFailed ||= result.ackFailed;
    }
  } catch {
    return refuse(503, "provider_unavailable");
  }
  if (outcomes.every((o) => o === "not_found" || o.startsWith("ignored:"))) {
    return refuse(404, "purchase_not_found");
  }
  return playOutcomeResponse(outcomes, ackFailed);
}

async function reconcilePlay(deps: BillingDeps) {
  const tally: Record<string, number> = {};
  const bump = (key: string) => (tally[key] = (tally[key] ?? 0) + 1);
  const play = deps.play;
  if (!play) return { skipped: true };

  const batch = await deps.rpc("subscription_claim_reconcile_batch", { p_limit: 50 }) as any[];
  const hashes = (batch ?? []).filter((r) => r.provider === "google_play").map((r) => r.provider_subscription_id);
  const sealed = hashes.length
    ? await deps.rpc("play_purchase_ciphertexts", { p_hashes: hashes }) as any[]
    : [];
  for (const row of sealed ?? []) {
    try {
      const token = await openToken(play.vaultKey, row.token_ciphertext, row.token_sha256);
      const result = await processPlayToken(play, token, {
        caller: null,
        eventId: `reconcile:${row.token_sha256}:${play.now()}`,
        eventType: "RECONCILED",
      });
      bump(result.ackFailed ? "ack_failed" : result.outcome);
    } catch {
      bump("error");
    }
  }

  // Refunds whose notification never arrived. Needs the financial-data permission.
  try {
    let page: string | undefined;
    do {
      const { purchases, next } = await play.client.voidedSince(play.now() - VOIDED_LOOKBACK_MS, page);
      const seen = new Set<string>();
      for (const voided of purchases) {
        if (seen.has(voided.purchaseToken)) continue;
        seen.add(voided.purchaseToken);
        const hash = await sha256Hex(voided.purchaseToken);
        const known = await deps.rpc("play_purchase_ciphertexts", { p_hashes: [hash] }) as any[];
        if (!known?.length) continue;
        const result = await processPlayToken(play, voided.purchaseToken, {
          caller: null,
          // Stable per order, so a repeated listing applies nothing new.
          eventId: `voided:${hash}:${voided.orderId ?? "unknown"}`,
          eventType: "VOIDED",
          terminalState: "refunded",
        });
        bump(`voided_${result.outcome}`);
      }
      page = next ?? undefined;
    } while (page);
  } catch {
    bump("voided_error");
  }

  // A deleted account must not keep being charged by Google.
  const orphans = await deps.rpc("play_claim_orphans", { p_limit: 25 }) as any[];
  for (const row of orphans ?? []) {
    try {
      const token = await openToken(play.vaultKey, row.token_ciphertext, row.token_sha256);
      await play.client.cancel(row.product_id, token);
      await deps.rpc("play_mark_orphan_canceled", { p_token_sha256: row.token_sha256 });
      bump("orphan_canceled");
    } catch {
      bump("orphan_error");
    }
  }
  return tally;
}

// ---------------------------------------------------------------------------
// Tap: settlement and renewals
// ---------------------------------------------------------------------------

async function settle(deps: BillingDeps, charge: TapChargeView, orderId: string): Promise<string> {
  return String(await deps.rpc("tap_settle_charge", {
    p_order: orderId,
    p_charge_id: charge.id,
    p_status: charge.status,
    p_amount: charge.amount,
    p_currency: charge.currency,
    p_live: charge.liveMode,
    p_customer_id: charge.customerId,
    p_card_id: charge.cardId,
    p_agreement_id: charge.agreementId,
    p_card: charge.card,
  }));
}

async function settleCardUpdate(deps: BillingDeps, view: TapAuthorizeView): Promise<string> {
  if (!view.updateId) return "unknown_update";
  const outcome = String(await deps.rpc("tap_card_update_settle", {
    p_update: view.updateId,
    p_authorize_id: view.id,
    p_status: view.status,
    p_customer_id: view.customerId,
    p_card_id: view.cardId,
    p_agreement_id: view.agreementId,
    p_card: view.card,
  }));
  // The hold has done its job. Tap also voids it automatically within the hour.
  if (view.status === "AUTHORIZED" && (outcome === "applied" || outcome === "needs_review")) {
    await deps.tap?.voidAuthorize(view.id).catch(() => undefined);
  }
  return outcome;
}

async function runRenewals(deps: BillingDeps) {
  const tally: Record<string, number> = {};
  const bump = (key: string) => (tally[key] = (tally[key] ?? 0) + 1);
  if (!deps.tap || !deps.tapBillingEnabled || !deps.tapRenewalsEnabled) return { skipped: true };
  const due = await deps.rpc("tap_claim_due_renewals", { p_limit: 50 }) as any[];
  for (const row of due ?? []) {
    try {
      const charge = await deps.tap.chargeRenewal({
        orderId: row.order_id,
        amount: Number(row.amount),
        customerId: row.tap_customer_id,
        cardId: row.tap_card_id,
        agreementId: row.tap_agreement_id,
        webhookUrl: deps.tapWebhookUrl,
        redirectUrl: deps.tapReturnUrl,
        description: "Broker Wallet Plus renewal",
      });
      if (!charge || charge.liveMode !== deps.tapLiveMode || !merchantMatches(deps, charge.merchantId)) {
        bump("needs_review");
        continue;
      }
      await deps.rpc("tap_attach_charge", { p_order: row.order_id, p_charge_id: charge.id });
      // A renewal is settled only by the verified webhook or a later re-read.
      bump(charge.status === "CAPTURED" ? await settle(deps, charge, row.order_id) : "submitted");
    } catch {
      // The order stays open. Its unique attempt key prevents a second charge.
      bump("error");
    }
  }
  return tally;
}

/** Charges whose webhook never came: Tap's own record decides. */
async function reconcileTapCharges(deps: BillingDeps) {
  const tally: Record<string, number> = {};
  const bump = (key: string) => (tally[key] = (tally[key] ?? 0) + 1);
  if (!deps.tap || !deps.tapBillingEnabled) return { skipped: true };
  const stale = await deps.rpc("tap_claim_stale_charges", { p_limit: 50 }) as any[];
  for (const row of stale ?? []) {
    try {
      const charge = await deps.tap.getCharge(row.tap_charge_id);
      if (!charge || charge.orderId !== row.order_id) bump("unconfirmed");
      else if (charge.liveMode !== deps.tapLiveMode || !merchantMatches(deps, charge.merchantId)) bump("needs_review");
      else bump(await settle(deps, charge, row.order_id));
    } catch {
      bump("error");
    }
  }
  return tally;
}

async function handleReconcile(request: Request, deps: BillingDeps): Promise<Response> {
  const secret = request.headers.get("x-reconcile-secret") ?? "";
  if (!deps.reconcileSecret || !constantTimeEqual(secret, deps.reconcileSecret)) {
    return refuse(401, "unauthorized");
  }
  const store = await reconcilePlay(deps);
  const charges = await reconcileTapCharges(deps);
  return json(200, { ok: true, store, charges, renewals: await runRenewals(deps) });
}

// ---------------------------------------------------------------------------
// Tap: customer routes
// ---------------------------------------------------------------------------

async function handleTapSession(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tap || !deps.tapBillingEnabled || !deps.tapPublicKey) return refuse(503, "not_configured");
  // A key from the other Tap mode must never reach a browser.
  if (deps.tapPublicKey.startsWith("pk_live_") !== deps.tapLiveMode) return refuse(503, "not_configured");
  const body = await readBody(request);
  const cycle = body?.cycle;
  if (!body || Object.keys(body).length !== 1 || (cycle !== "monthly" && cycle !== "annual")) {
    return refuse(400, "invalid_request");
  }
  return json(200, {
    ok: true,
    publicKey: deps.tapPublicKey,
    amount: cycle === "annual" ? 180 : 20,
    currency: "AED",
  });
}

async function handleCheckout(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tap || !deps.tapBillingEnabled) return refuse(503, "not_configured");
  const body = await readBody(request);
  if (!body) return refuse(400, "invalid_request");
  const keys = Object.keys(body);
  const cycle = body.cycle;
  const token = body.token;
  // The client names a cycle and at most a Tap card token: never an amount or an account.
  if (
    keys.some((key) => key !== "cycle" && key !== "token") ||
    (cycle !== "monthly" && cycle !== "annual") ||
    (token !== undefined && (typeof token !== "string" || !TAP_TOKEN.test(token)))
  ) {
    return refuse(400, "invalid_request");
  }

  let order: any;
  try {
    order = await deps.rpc("tap_create_order", { p_user: user.id, p_cycle: cycle });
  } catch {
    // Includes an incomplete tax profile: no sale may start without a valid invoice.
    return refuse(503, "billing_not_ready");
  }
  if (order?.refused) return refuse(409, order.refused);
  const phone = /^\+([1-9]\d{0,2})(\d{6,12})$/.exec(user.phone ?? order.customer_phone ?? "");
  const customer: Record<string, unknown> = order.tap_customer_id
    ? { id: order.tap_customer_id }
    : {
      first_name: "Broker Wallet customer",
      ...(user.email ? { email: user.email } : {}),
      // Tap requires a phone number to save a card for renewals.
      ...(phone ? { phone: { country_code: phone[1], number: phone[2] } } : {}),
    };
  if (!order.tap_customer_id && !phone) return refuse(422, "phone_required");

  let charge: TapChargeView | null;
  try {
    charge = await deps.tap.createCheckout({
      orderId: order.order_id,
      amount: Number(order.amount),
      customer,
      sourceId: typeof token === "string" ? token : "src_card",
      redirectUrl: deps.tapReturnUrl,
      webhookUrl: deps.tapWebhookUrl,
      description: `Broker Wallet Plus ${cycle}`,
    });
  } catch {
    return refuse(502, "provider_unavailable");
  }
  if (!charge || charge.liveMode !== deps.tapLiveMode || !merchantMatches(deps, charge.merchantId)) {
    return refuse(502, "provider_unavailable");
  }
  // Only a charge that needs no further step may come back without a page to open.
  if (!charge.transactionUrl && charge.status !== "CAPTURED") return refuse(502, "provider_unavailable");
  await deps.rpc("tap_attach_charge", { p_order: order.order_id, p_charge_id: charge.id });
  // Neither this answer nor a redirect grants anything: see /tap/verify and the webhook.
  return json(200, { ok: true, chargeId: charge.id, checkoutUrl: charge.transactionUrl });
}

/** A browser came back from checkout. Only Tap's own record decides what happened. */
async function handleTapVerify(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tap || !deps.tapBillingEnabled) return refuse(503, "not_configured");
  const body = await readBody(request);
  const chargeId = body?.chargeId;
  if (!body || Object.keys(body).length !== 1 || typeof chargeId !== "string" || !TAP_CHARGE.test(chargeId)) {
    return refuse(400, "invalid_request");
  }
  // Another account's charge looks exactly like one that does not exist.
  if ((await deps.rpc("tap_charge_owner", { p_charge_id: chargeId })) !== user.id) {
    return refuse(404, "not_found");
  }
  let charge: TapChargeView | null;
  try {
    charge = await deps.tap.getCharge(chargeId);
  } catch {
    return refuse(503, "provider_unavailable");
  }
  if (!charge?.orderId) return refuse(503, "provider_unavailable");
  if (charge.liveMode !== deps.tapLiveMode || !merchantMatches(deps, charge.merchantId)) {
    return refuse(409, "charge_rejected");
  }
  try {
    return json(200, { ok: true, outcome: await settle(deps, charge, charge.orderId) });
  } catch {
    return refuse(500, "apply_failed");
  }
}

async function handleTapRenewal(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tapBillingEnabled) return refuse(503, "not_configured");
  const body = await readBody(request);
  if (!body || typeof body.autoRenew !== "boolean" || Object.keys(body).length !== 1) {
    return refuse(400, "invalid_request");
  }
  const outcome = await deps.rpc("tap_set_auto_renew", { p_user: user.id, p_on: body.autoRenew });
  return json(200, { ok: true, outcome });
}

async function handleCardStart(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tap || !deps.tapBillingEnabled) return refuse(503, "not_configured");
  const body = await readBody(request);
  const token = body?.token;
  if (
    !body || Object.keys(body).some((key) => key !== "token") ||
    (token !== undefined && (typeof token !== "string" || !TAP_TOKEN.test(token)))
  ) {
    return refuse(400, "invalid_request");
  }
  const update = await deps.rpc("tap_card_update_create", { p_user: user.id });
  if (update?.refused) return refuse(409, update.refused);
  let view: TapAuthorizeView | null;
  try {
    view = await deps.tap.authorizeCard({
      updateId: update.update_id,
      customerId: update.tap_customer_id,
      sourceId: typeof token === "string" ? token : "src_card",
      redirectUrl: deps.tapReturnUrl,
      webhookUrl: deps.tapWebhookUrl,
    });
  } catch {
    return refuse(502, "provider_unavailable");
  }
  if (!view || view.liveMode !== deps.tapLiveMode || !merchantMatches(deps, view.merchantId)) {
    return refuse(502, "provider_unavailable");
  }
  if (!view.transactionUrl && view.status !== "AUTHORIZED") return refuse(502, "provider_unavailable");
  await deps.rpc("tap_card_update_attach", { p_update: update.update_id, p_authorize_id: view.id });
  return json(200, { ok: true, authorizeId: view.id, checkoutUrl: view.transactionUrl });
}

async function handleCardVerify(request: Request, deps: BillingDeps): Promise<Response> {
  const user = await signedInUser(request, deps);
  if (!user) return refuse(401, "unauthenticated");
  if (!deps.tap || !deps.tapBillingEnabled) return refuse(503, "not_configured");
  const body = await readBody(request);
  const authorizeId = body?.authorizeId;
  if (!body || Object.keys(body).length !== 1 || typeof authorizeId !== "string" || !TAP_AUTHORIZE.test(authorizeId)) {
    return refuse(400, "invalid_request");
  }
  if ((await deps.rpc("tap_card_update_owner", { p_authorize_id: authorizeId })) !== user.id) {
    return refuse(404, "not_found");
  }
  let view: TapAuthorizeView | null;
  try {
    view = await deps.tap.getAuthorize(authorizeId);
  } catch {
    return refuse(503, "provider_unavailable");
  }
  if (!view?.updateId) return refuse(503, "provider_unavailable");
  if (view.liveMode !== deps.tapLiveMode || !merchantMatches(deps, view.merchantId)) {
    return refuse(409, "charge_rejected");
  }
  try {
    return json(200, { ok: true, outcome: await settleCardUpdate(deps, view) });
  } catch {
    return refuse(500, "apply_failed");
  }
}

// ---------------------------------------------------------------------------
// Tap: webhook
// ---------------------------------------------------------------------------

/** Tap's documented hash input for a refund object. */
async function refundHashValid(secret: string, header: string | null, refund: any): Promise<boolean> {
  if (!secret || !header || refund?.currency !== "AED") return false;
  const amount = Number(refund.amount);
  if (!Number.isFinite(amount)) return false;
  const input = `x_id${refund.id ?? ""}x_amount${amount.toFixed(2)}x_currency${refund.currency}` +
    `x_gateway_reference${refund.reference?.gateway ?? ""}x_payment_reference${refund.reference?.payment ?? ""}` +
    `x_status${refund.status ?? ""}x_created${refund.created ?? ""}`;
  return constantTimeEqual(await hmacSha256Hex(secret, input), header.trim().toLowerCase());
}

async function handleTapWebhook(request: Request, deps: BillingDeps): Promise<Response> {
  if (!deps.tap || !deps.tapBillingEnabled || !deps.tapSecret) return refuse(503, "not_configured");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) return refuse(413, "too_large");
  let body: any;
  try {
    body = JSON.parse(raw);
  } catch {
    return refuse(400, "invalid_body");
  }
  const header = request.headers.get("hashstring");

  if (typeof body?.id === "string" && body.id.startsWith("re_")) {
    if (!(await refundHashValid(deps.tapSecret, header, body))) return refuse(401, "invalid_signature");
    try {
      const outcome = await deps.rpc("tap_record_refund", {
        p_refund_id: body.id,
        p_charge_id: body.charge_id,
        p_status: body.status,
        p_amount: Number(body.amount),
      });
      return json(200, { ok: true, outcome });
    } catch {
      return refuse(500, "apply_failed");
    }
  }

  if (!(await verifyTapHash(deps.tapSecret, header, body as TapCharge))) {
    return refuse(401, "invalid_signature");
  }

  if (typeof body?.id === "string" && body.id.startsWith("auth_")) {
    let view: TapAuthorizeView | null;
    try {
      view = await deps.tap.getAuthorize(body.id);
    } catch {
      return refuse(503, "provider_unavailable");
    }
    if (!view?.updateId) return refuse(503, "provider_unavailable");
    if (view.liveMode !== deps.tapLiveMode || !merchantMatches(deps, view.merchantId)) {
      return json(200, { ok: true, outcome: "wrong_mode" });
    }
    try {
      return json(200, { ok: true, outcome: await settleCardUpdate(deps, view) });
    } catch {
      return refuse(500, "apply_failed");
    }
  }

  // The webhook says which charge to look at; Tap's own record says what happened.
  let charge: TapChargeView | null;
  try {
    charge = await deps.tap.getCharge(String(body.id));
  } catch {
    return refuse(503, "provider_unavailable");
  }
  if (!charge || !charge.orderId) return refuse(503, "provider_unavailable");
  if (charge.liveMode !== deps.tapLiveMode || !merchantMatches(deps, charge.merchantId)) {
    return json(200, { ok: true, outcome: "wrong_mode" });
  }
  try {
    return json(200, { ok: true, outcome: await settle(deps, charge, charge.orderId) });
  } catch {
    return refuse(500, "apply_failed");
  }
}

/**
 * The web app calls this function from a browser. Only an exact, configured origin
 * gets CORS headers. This is not authorization: every route still checks its caller.
 */
export async function handleBilling(request: Request, deps: BillingDeps): Promise<Response> {
  const origin = request.headers.get("origin");
  const allowed = origin !== null && (deps.allowedOrigins ?? []).includes(origin);
  if (request.method === "OPTIONS") {
    if (!allowed) return new Response(null, { status: 403 });
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": origin,
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-runtime, x-supabase-client-version",
        "access-control-max-age": "600",
        vary: "origin",
      },
    });
  }
  const response = await route(request, deps);
  if (allowed) {
    response.headers.set("access-control-allow-origin", origin);
    response.headers.set("vary", "origin");
  }
  return response;
}

function route(request: Request, deps: BillingDeps): Promise<Response> | Response {
  if (request.method !== "POST") return refuse(405, "method_not_allowed");
  const path = new URL(request.url).pathname;
  if (path.endsWith("/tap/webhook")) return handleTapWebhook(request, deps);
  if (path.endsWith("/tap/session")) return handleTapSession(request, deps);
  if (path.endsWith("/tap/checkout")) return handleCheckout(request, deps);
  if (path.endsWith("/tap/card/verify")) return handleCardVerify(request, deps);
  if (path.endsWith("/tap/card")) return handleCardStart(request, deps);
  if (path.endsWith("/tap/verify")) return handleTapVerify(request, deps);
  if (path.endsWith("/tap/renewal")) return handleTapRenewal(request, deps);
  if (path.endsWith("/play/prepare")) return handlePlayPrepare(request, deps);
  if (path.endsWith("/play/verify")) return handlePlayVerify(request, deps);
  if (path.endsWith("/reconcile")) return handleReconcile(request, deps);
  if (path.endsWith("/sync")) return handleSync(request, deps);
  return refuse(404, "not_found");
}
