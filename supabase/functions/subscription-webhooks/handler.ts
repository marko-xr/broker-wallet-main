// Google Play real-time developer notifications, pushed by Cloud Pub/Sub:
//   POST /subscription-webhooks/google-play
// The push must carry a valid Google OIDC token for our configured push identity.
// A notification only names a purchase token; the state is read from Google.
// Tap's webhook is served by the subscription-billing function.

import { parsePlayNotification, PLAY_NOTIFICATION_REVOKED } from "./google_play.ts";
import { processPlayToken } from "./play_service.ts";
import type { PlayDeps } from "./play_service.ts";
import { sha256Hex } from "./provider_event.ts";

export interface WebhookDeps {
  play: PlayDeps | null;
  /** Verifies the bearer token of a Pub/Sub push. */
  verifyPush: (token: string) => Promise<boolean>;
}

const MAX_BODY_BYTES = 64 * 1024;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function decodeMessage(data: unknown): unknown {
  if (typeof data !== "string") return null;
  try {
    const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

export async function handleWebhook(request: Request, deps: WebhookDeps): Promise<Response> {
  if (request.method !== "POST") return json(405, { ok: false, code: "method_not_allowed" });
  if (!new URL(request.url).pathname.endsWith("/google-play")) {
    return json(404, { ok: false, code: "not_found" });
  }
  if (!deps.play) return json(503, { ok: false, code: "not_configured" });

  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token || !(await deps.verifyPush(token).catch(() => false))) {
    return json(401, { ok: false, code: "invalid_signature" });
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return json(413, { ok: false, code: "too_large" });
  }
  let envelope: any;
  try {
    envelope = JSON.parse(raw);
  } catch {
    return json(400, { ok: false, code: "invalid_body" });
  }
  const messageId = envelope?.message?.messageId;
  const notification = parsePlayNotification(decodeMessage(envelope?.message?.data));
  // A malformed message will never parse: acknowledged so Pub/Sub stops retrying.
  if (typeof messageId !== "string" || !messageId || !notification) {
    return json(200, { ok: true, outcome: "ignored", reason: "malformed" });
  }
  if (notification.packageName !== deps.play.config.packageName) {
    return json(200, { ok: true, outcome: "ignored", reason: "other_package" });
  }
  if (notification.kind === "test" || notification.kind === "other") {
    return json(200, { ok: true, outcome: "ignored", reason: notification.kind });
  }

  const voided = notification.kind === "voided";
  const revoked = !voided && notification.notificationType === PLAY_NOTIFICATION_REVOKED;
  try {
    const result = await processPlayToken(deps.play, notification.purchaseToken, {
      caller: null,
      eventId: `rtdn:${messageId}`,
      eventType: voided ? "VOIDED" : `NOTIFICATION_${notification.notificationType}`,
      terminalState: voided ? "refunded" : revoked ? "revoked" : undefined,
      payloadSha256: await sha256Hex(raw),
    });
    // A non-2xx answer makes Pub/Sub deliver the same message again.
    if (result.ackFailed) return json(503, { ok: false, code: "acknowledge_failed" });
    return json(200, { ok: true, outcome: result.outcome });
  } catch {
    return json(500, { ok: false, code: "apply_failed" });
  }
}
