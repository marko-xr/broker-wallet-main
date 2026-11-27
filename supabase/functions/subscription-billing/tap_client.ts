// Tap Payments REST calls, from Tap's API reference: charges, authorize, tokens from
// saved cards, Bearer secret key, idempotency through reference.idempotent (24 hours).
// Response shapes are parsed strictly: anything unexpected fails closed.
// Not yet exercised against Tap: this must be proven with a Tap test key before
// TAP_BILLING_ENABLED is turned on.

export const TAP_API = "https://api.tap.company/v2";

export interface TapCardView {
  brand: string | null;
  last_four: string | null;
  exp_month: number | null;
  exp_year: number | null;
}

export interface TapChargeView {
  id: string;
  status: string;
  amount: number;
  currency: string;
  liveMode: boolean;
  orderId: string | null;
  merchantId: string | null;
  customerId: string | null;
  cardId: string | null;
  agreementId: string | null;
  transactionUrl: string | null;
  card: TapCardView | null;
}

export interface TapAuthorizeView {
  id: string;
  status: string;
  liveMode: boolean;
  updateId: string | null;
  merchantId: string | null;
  customerId: string | null;
  cardId: string | null;
  agreementId: string | null;
  transactionUrl: string | null;
  card: TapCardView | null;
}

export type TapFetch = (url: string, init: RequestInit) => Promise<Response>;

const text = (value: unknown): string | null => (typeof value === "string" && value.trim() !== "" ? value : null);

function whole(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isInteger(parsed) ? parsed : null;
}

function parseCard(raw: unknown): TapCardView | null {
  if (typeof raw !== "object" || raw === null) return null;
  const card = raw as Record<string, unknown>;
  return {
    brand: text(card.brand),
    last_four: text(card.last_four),
    exp_month: whole(card.exp_month),
    exp_year: whole(card.exp_year),
  };
}

export function parseCharge(raw: unknown): TapChargeView | null {
  if (typeof raw !== "object" || raw === null) return null;
  const c = raw as Record<string, any>;
  const id = text(c.id);
  const status = text(c.status);
  const currency = text(c.currency);
  const amount = typeof c.amount === "number" ? c.amount : Number(c.amount);
  if (!id || !id.startsWith("chg_") || !status || !currency || !Number.isFinite(amount) || typeof c.live_mode !== "boolean") {
    return null;
  }
  return {
    id,
    status,
    amount,
    currency,
    liveMode: c.live_mode,
    orderId: text(c.reference?.order),
    merchantId: text(c.merchant?.id) ?? text(c.merchant_id),
    customerId: text(c.customer?.id),
    cardId: text(c.card?.id),
    agreementId: text(c.payment_agreement?.id),
    transactionUrl: text(c.transaction?.url),
    card: parseCard(c.card),
  };
}

export function parseAuthorize(raw: unknown): TapAuthorizeView | null {
  if (typeof raw !== "object" || raw === null) return null;
  const a = raw as Record<string, any>;
  const id = text(a.id);
  const status = text(a.status);
  if (!id || !id.startsWith("auth_") || !status || typeof a.live_mode !== "boolean") return null;
  return {
    id,
    status,
    liveMode: a.live_mode,
    updateId: text(a.metadata?.bw_card_update),
    merchantId: text(a.merchant?.id) ?? text(a.merchant_id),
    customerId: text(a.customer?.id),
    cardId: text(a.card?.id),
    agreementId: text(a.payment_agreement?.id),
    transactionUrl: text(a.transaction?.url),
    card: parseCard(a.card),
  };
}

export class TapClient {
  private readonly secret: string;
  private readonly send: TapFetch;

  constructor(secret: string, send: TapFetch = fetch) {
    this.secret = secret;
    this.send = send;
  }

  private async call(method: string, path: string, body?: unknown): Promise<unknown> {
    const response = await this.send(`${TAP_API}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${this.secret}`,
        accept: "application/json",
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) throw new Error(`tap_http_${response.status}`);
    return response.json();
  }

  async getCharge(id: string): Promise<TapChargeView | null> {
    const charge = parseCharge(await this.call("GET", `/charges/${encodeURIComponent(id)}`));
    return charge?.id === id ? charge : null;
  }

  async getAuthorize(id: string): Promise<TapAuthorizeView | null> {
    const authorize = parseAuthorize(await this.call("GET", `/authorize/${encodeURIComponent(id)}`));
    return authorize?.id === id ? authorize : null;
  }

  /**
   * The first, customer-present payment: 3-D Secure, card saved for renewals.
   * [sourceId] is a one-time token from Tap's card component, or `src_card` for
   * Tap's hosted page.
   */
  async createCheckout(input: {
    orderId: string;
    amount: number;
    customer: Record<string, unknown>;
    sourceId: string;
    redirectUrl: string;
    webhookUrl: string;
    description: string;
  }): Promise<TapChargeView | null> {
    return parseCharge(await this.call("POST", "/charges", {
      amount: input.amount,
      currency: "AED",
      customer_initiated: true,
      threeDSecure: true,
      save_card: true,
      description: input.description,
      customer: input.customer,
      source: { id: input.sourceId },
      redirect: { url: input.redirectUrl },
      post: { url: input.webhookUrl },
      reference: { transaction: input.orderId, order: input.orderId, idempotent: input.orderId },
      metadata: { bw_order: input.orderId },
    }));
  }

  /** A merchant-initiated renewal on the saved card and its payment agreement. */
  async chargeRenewal(input: {
    orderId: string;
    amount: number;
    customerId: string;
    cardId: string;
    agreementId: string;
    webhookUrl: string;
    redirectUrl: string;
    description: string;
  }): Promise<TapChargeView | null> {
    const token = await this.call("POST", "/tokens", {
      saved_card: { card_id: input.cardId, customer_id: input.customerId },
    }) as { id?: unknown };
    const tokenId = text(token?.id);
    if (!tokenId || !tokenId.startsWith("tok_")) throw new Error("tap_token_invalid");
    return parseCharge(await this.call("POST", "/charges", {
      amount: input.amount,
      currency: "AED",
      customer_initiated: false,
      threeDSecure: false,
      save_card: false,
      description: input.description,
      payment_agreement: { id: input.agreementId },
      customer: { id: input.customerId },
      source: { id: tokenId },
      redirect: { url: input.redirectUrl },
      post: { url: input.webhookUrl },
      reference: { transaction: input.orderId, order: input.orderId, idempotent: input.orderId },
      metadata: { bw_order: input.orderId },
    }));
  }

  /**
   * Verifies and saves a replacement card with a small hold under 3-D Secure.
   * The hold is voided right after it succeeds, and by Tap after one hour at most.
   */
  async authorizeCard(input: {
    updateId: string;
    customerId: string;
    sourceId: string;
    redirectUrl: string;
    webhookUrl: string;
  }): Promise<TapAuthorizeView | null> {
    return parseAuthorize(await this.call("POST", "/authorize", {
      amount: 1,
      currency: "AED",
      customer_initiated: true,
      threeDSecure: true,
      save_card: true,
      auto: { type: "VOID", time: 1 },
      description: "Broker Wallet card verification",
      customer: { id: input.customerId },
      source: { id: input.sourceId },
      redirect: { url: input.redirectUrl },
      post: { url: input.webhookUrl },
      reference: { transaction: input.updateId, order: input.updateId, idempotent: input.updateId },
      metadata: { bw_card_update: input.updateId },
    }));
  }

  async voidAuthorize(id: string): Promise<void> {
    await this.call("POST", `/authorize/${encodeURIComponent(id)}/void`, {});
  }
}
