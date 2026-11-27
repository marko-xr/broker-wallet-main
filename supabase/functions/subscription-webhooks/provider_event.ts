// The provider-neutral event every adapter produces, and the one way it reaches
// the database. Entitlement logic lives in SQL; adapters only translate.

export type SubscriptionState =
  | "active"
  | "cancel_scheduled"
  | "billing_issue"
  | "paused"
  | "expired"
  | "refunded"
  | "revoked"
  | "unknown";

export interface ProviderEvent {
  provider: "google_play" | "app_store" | "tap";
  eventId: string;
  eventType: string;
  eventAt: string;
  userId: string;
  providerSubscriptionId: string;
  productId: string | null;
  billingCycle: "monthly" | "annual" | null;
  state: SubscriptionState;
  autoRenew: boolean;
  startedAt: string | null;
  paidThroughAt: string | null;
  graceUntil: string | null;
  environment: "production" | "sandbox";
}

/** Why a verified event was deliberately not applied. Never grants anything. */
export interface IgnoredEvent {
  ignored: string;
}

export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Compares two strings without an early exit on the first difference. */
export function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return difference === 0;
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(message: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(message));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The arguments of public.apply_subscription_provider_event. */
export function toRpcArgs(event: ProviderEvent, payloadSha256: string) {
  return {
    p_provider: event.provider,
    p_event_id: event.eventId,
    p_event_type: event.eventType,
    p_event_at: event.eventAt,
    p_user_id: event.userId,
    p_provider_subscription_id: event.providerSubscriptionId,
    p_product_id: event.productId,
    p_billing_cycle: event.billingCycle,
    p_state: event.state,
    p_auto_renew: event.autoRenew,
    p_started_at: event.startedAt,
    p_paid_through_at: event.paidThroughAt,
    p_grace_until: event.graceUntil,
    p_environment: event.environment,
    p_payload_sha256: payloadSha256,
  };
}
