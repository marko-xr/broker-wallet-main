// Direct Google Play Billing, server side. Google's purchases.subscriptionsv2 record
// is the only source of truth: a client callback or a notification only says which
// purchase token to look at. Nothing here grants anything by itself.

import type { SubscriptionState } from "./provider_event.ts";
import { UUID_PATTERN } from "./provider_event.ts";

export interface PlayConfig {
  packageName: string;
  productId: string;
  /** Exact Play base plan ids mapped to a billing cycle. */
  basePlanCycles: Record<string, "monthly" | "annual">;
}

export interface PlaySnapshot {
  productId: string;
  basePlanId: string;
  billingCycle: "monthly" | "annual";
  state: SubscriptionState;
  autoRenew: boolean;
  startedAt: string | null;
  paidThroughAt: string | null;
  graceUntil: string | null;
  environment: "production" | "sandbox";
  orderId: string | null;
  accountRef: string | null;
  linkedPurchaseToken: string | null;
  ackPending: boolean;
}

const text = (value: unknown): string | null =>
  typeof value === "string" && value.trim() !== "" ? value : null;

function isoTime(value: unknown): string | null {
  const raw = text(value);
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

/** During hold or pause Google gives no access, whatever date the record carries. */
const notAfter = (time: string | null, limit: string): string | null =>
  time === null ? null : new Date(Math.min(Date.parse(time), Date.parse(limit))).toISOString();

export function mapPlaySubscription(
  raw: unknown,
  config: PlayConfig,
  asOf: string,
): PlaySnapshot | { ignored: string } {
  if (typeof raw !== "object" || raw === null) return { ignored: "malformed" };
  const purchase = raw as Record<string, any>;
  const items = Array.isArray(purchase.lineItems) ? purchase.lineItems : [];
  const item = items.find((entry: any) => entry?.productId === config.productId);
  if (!item) return { ignored: "unknown_product" };
  // Plus is an auto-renewing plan. A prepaid item is not a product we sell.
  if (typeof item.autoRenewingPlan !== "object" || item.autoRenewingPlan === null) {
    return { ignored: "not_auto_renewing" };
  }
  const basePlanId = text(item.offerDetails?.basePlanId);
  const billingCycle = basePlanId ? config.basePlanCycles[basePlanId] : undefined;
  if (!basePlanId || (billingCycle !== "monthly" && billingCycle !== "annual")) {
    return { ignored: "unknown_base_plan" };
  }

  const expiry = isoTime(item.expiryTime);
  const renewing = item.autoRenewingPlan.autoRenewEnabled === true;
  let state: SubscriptionState;
  let autoRenew = false;
  let paidThroughAt = expiry;
  let graceUntil: string | null = null;
  switch (purchase.subscriptionState) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      state = renewing ? "active" : "cancel_scheduled";
      autoRenew = renewing;
      break;
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      state = "billing_issue";
      autoRenew = renewing;
      graceUntil = expiry;
      break;
    case "SUBSCRIPTION_STATE_ON_HOLD":
      state = "billing_issue";
      autoRenew = renewing;
      paidThroughAt = notAfter(expiry, asOf);
      break;
    case "SUBSCRIPTION_STATE_PAUSED":
      state = "paused";
      autoRenew = renewing;
      paidThroughAt = notAfter(expiry, asOf);
      break;
    case "SUBSCRIPTION_STATE_CANCELED":
      state = "cancel_scheduled";
      break;
    case "SUBSCRIPTION_STATE_EXPIRED":
      state = "expired";
      break;
    default:
      // Pending, pending-canceled or a value we do not know: never access.
      state = "unknown";
      paidThroughAt = null;
  }
  // An entitled state without a date is not a state to act on.
  if ((state === "active" || state === "cancel_scheduled") && !expiry) {
    return { ignored: "missing_expiry" };
  }

  const reference = text(purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId);
  const outOfApp = purchase.outOfAppPurchaseContext ?? purchase.outofAppPurchaseContext;
  return {
    productId: config.productId,
    basePlanId,
    billingCycle,
    state,
    autoRenew,
    startedAt: isoTime(purchase.startTime),
    paidThroughAt,
    graceUntil,
    environment: purchase.testPurchase !== undefined && purchase.testPurchase !== null
      ? "sandbox"
      : "production",
    orderId: text(item.latestSuccessfulOrderId) ?? text(purchase.latestOrderId),
    accountRef: reference && UUID_PATTERN.test(reference) ? reference : null,
    linkedPurchaseToken: text(purchase.linkedPurchaseToken) ?? text(outOfApp?.expiredPurchaseToken),
    ackPending: purchase.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
  };
}

/** Developer notification, already taken out of its Pub/Sub envelope. */
export type PlayNotification =
  | { kind: "subscription"; packageName: string; purchaseToken: string; notificationType: number }
  | { kind: "voided"; packageName: string; purchaseToken: string; orderId: string | null }
  | { kind: "test"; packageName: string }
  | { kind: "other"; packageName: string };

export function parsePlayNotification(raw: unknown): PlayNotification | null {
  if (typeof raw !== "object" || raw === null) return null;
  const body = raw as Record<string, any>;
  const packageName = text(body.packageName);
  if (!packageName) return null;
  if (body.testNotification) return { kind: "test", packageName };
  if (body.subscriptionNotification) {
    const token = text(body.subscriptionNotification.purchaseToken);
    const type = body.subscriptionNotification.notificationType;
    if (!token || !Number.isInteger(type)) return null;
    return { kind: "subscription", packageName, purchaseToken: token, notificationType: type };
  }
  if (body.voidedPurchaseNotification) {
    const voided = body.voidedPurchaseNotification;
    // productType 1 is a subscription; a one-time product is not ours.
    if (voided.productType !== 1) return { kind: "other", packageName };
    const token = text(voided.purchaseToken);
    if (!token) return null;
    return { kind: "voided", packageName, purchaseToken: token, orderId: text(voided.orderId) };
  }
  return { kind: "other", packageName };
}

export const PLAY_NOTIFICATION_REVOKED = 12;

export interface VoidedPurchase {
  purchaseToken: string;
  orderId: string | null;
}

/** The Android Publisher calls this system uses. */
export class GooglePlayClient {
  private readonly base: string;
  private readonly accessToken: () => Promise<string>;
  private readonly send: typeof fetch;

  constructor(packageName: string, accessToken: () => Promise<string>, send: typeof fetch = fetch) {
    this.base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
      encodeURIComponent(packageName);
    this.accessToken = accessToken;
    this.send = send;
  }

  private async call(method: string, path: string): Promise<Response> {
    return this.send(`${this.base}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${await this.accessToken()}`,
        accept: "application/json",
        ...(method === "POST" ? { "content-type": "application/json" } : {}),
      },
      ...(method === "POST" ? { body: "{}" } : {}),
    });
  }

  /** Null means Google does not know this token for this app. */
  async getSubscription(token: string): Promise<unknown | null> {
    const response = await this.call("GET", `/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`);
    if (response.status === 404 || response.status === 410) return null;
    if (!response.ok) throw new Error(`play_http_${response.status}`);
    return response.json();
  }

  async acknowledge(productId: string, token: string): Promise<void> {
    const response = await this.call(
      "POST",
      `/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:acknowledge`,
    );
    if (!response.ok) throw new Error(`play_ack_${response.status}`);
  }

  async cancel(productId: string, token: string): Promise<void> {
    const response = await this.call(
      "POST",
      `/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:cancel`,
    );
    if (!response.ok) throw new Error(`play_cancel_${response.status}`);
  }

  /** One page of subscription orders voided since [startMillis]. */
  async voidedSince(
    startMillis: number,
    pageToken?: string,
  ): Promise<{ purchases: VoidedPurchase[]; next: string | null }> {
    const query = new URLSearchParams({ type: "1", startTime: String(startMillis), maxResults: "1000" });
    if (pageToken) query.set("token", pageToken);
    const response = await this.call("GET", `/purchases/voidedpurchases?${query}`);
    if (!response.ok) throw new Error(`play_voided_${response.status}`);
    const body = await response.json();
    const list = Array.isArray(body?.voidedPurchases) ? body.voidedPurchases : [];
    return {
      purchases: list
        .filter((entry: any) => text(entry?.purchaseToken))
        .map((entry: any) => ({ purchaseToken: entry.purchaseToken, orderId: text(entry.orderId) })),
      next: text(body?.tokenPagination?.nextPageToken),
    };
  }
}
