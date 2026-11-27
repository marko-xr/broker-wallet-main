// One path from a Google Play purchase token to the database, shared by the app's
// verify call, real-time notifications and the reconciliation job.

import { mapPlaySubscription } from "./google_play.ts";
import type { GooglePlayClient, PlayConfig } from "./google_play.ts";
import { sha256Hex } from "./provider_event.ts";
import type { SubscriptionState } from "./provider_event.ts";
import { sealToken } from "./token_vault.ts";

export interface PlayDeps {
  client: GooglePlayClient;
  config: PlayConfig;
  vaultKey: string;
  rpc: (name: string, args: Record<string, unknown>) => Promise<any>;
  now: () => number;
}

export interface PlayRequest {
  /** The signed-in account asking, or null for a notification or the job. */
  caller: string | null;
  eventId: string;
  eventType: string;
  /** A revocation or refund: applied when Google no longer grants access. */
  terminalState?: "revoked" | "refunded";
  payloadSha256?: string | null;
}

export interface PlayResult {
  outcome: string;
  /** Google must be told again; the caller should report a retryable failure. */
  ackFailed: boolean;
}

const ENTITLED: ReadonlySet<SubscriptionState> = new Set([
  "active",
  "cancel_scheduled",
  "billing_issue",
  "paused",
]);

export async function processPlayToken(
  deps: PlayDeps,
  purchaseToken: string,
  request: PlayRequest,
): Promise<PlayResult> {
  // Taken before the read: a later read always has the later event time, so an
  // older answer arriving last is recorded as stale instead of winning.
  const asOf = new Date(deps.now()).toISOString();
  const raw = await deps.client.getSubscription(purchaseToken);
  if (raw === null) return { outcome: "not_found", ackFailed: false };
  const snapshot = mapPlaySubscription(raw, deps.config, asOf);
  if ("ignored" in snapshot) return { outcome: `ignored:${snapshot.ignored}`, ackFailed: false };

  const state = request.terminalState && !ENTITLED.has(snapshot.state)
    ? request.terminalState
    : snapshot.state;
  const tokenSha256 = await sha256Hex(purchaseToken);
  const result = await deps.rpc("play_apply_snapshot", {
    p_token_sha256: tokenSha256,
    p_token_ciphertext: await sealToken(deps.vaultKey, purchaseToken, tokenSha256),
    p_caller: request.caller,
    p_account_ref: snapshot.accountRef,
    p_product_id: snapshot.productId,
    p_base_plan_id: snapshot.basePlanId,
    p_order_id: snapshot.orderId,
    p_linked_sha256: snapshot.linkedPurchaseToken ? await sha256Hex(snapshot.linkedPurchaseToken) : null,
    p_event_id: request.eventId,
    p_event_type: request.eventType,
    p_event_at: asOf,
    p_billing_cycle: snapshot.billingCycle,
    p_state: state,
    p_auto_renew: snapshot.autoRenew,
    p_started_at: snapshot.startedAt,
    p_paid_through_at: snapshot.paidThroughAt,
    p_grace_until: snapshot.graceUntil,
    p_environment: snapshot.environment,
    p_ack_pending: snapshot.ackPending,
    p_payload_sha256: request.payloadSha256 ?? null,
  });
  const outcome = String(result?.outcome ?? "invalid");

  let ackFailed = false;
  if (result?.acknowledge === true) {
    try {
      await deps.client.acknowledge(snapshot.productId, purchaseToken);
      await deps.rpc("play_mark_acknowledged", { p_token_sha256: tokenSha256 });
    } catch {
      // The entitlement stands. A retry or the job acknowledges within Google's window.
      ackFailed = true;
    }
  }
  return { outcome, ackFailed };
}
