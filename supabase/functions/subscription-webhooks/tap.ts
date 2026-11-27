// Tap Payments webhook verification.
//
// Implemented from Tap's documentation: the `hashstring` header is HMAC-SHA256,
// keyed with the secret API key, over the concatenated charge fields below.
//
// THIS ROUTE NEVER GRANTS ACCESS. Tap's webhook for real billing is handled by the
// subscription-billing function, which matches a server-created order and re-reads
// the charge. A CAPTURED webhook here, or a successful redirect, proves nothing.

import { constantTimeEqual, hmacSha256Hex } from "./provider_event.ts";

export interface TapCharge {
  id?: unknown;
  amount?: unknown;
  currency?: unknown;
  status?: unknown;
  reference?: { gateway?: unknown; payment?: unknown } | null;
  transaction?: { created?: unknown } | null;
}

function text(value: unknown): string {
  return value === null || value === undefined ? "" : String(value);
}

/** Tap's documented decimals: AED has two. */
export function tapAmount(amount: unknown, currency: unknown): string | null {
  if (currency !== "AED") return null;
  const value = typeof amount === "number" ? amount : Number(text(amount));
  if (!Number.isFinite(value) || value < 0) return null;
  return value.toFixed(2);
}

export function tapHashInput(charge: TapCharge): string | null {
  const amount = tapAmount(charge.amount, charge.currency);
  if (amount === null) return null;
  return `x_id${text(charge.id)}` +
    `x_amount${amount}` +
    `x_currency${text(charge.currency)}` +
    `x_gateway_reference${text(charge.reference?.gateway)}` +
    `x_payment_reference${text(charge.reference?.payment)}` +
    `x_status${text(charge.status)}` +
    `x_created${text(charge.transaction?.created)}`;
}

export async function verifyTapHash(
  secret: string,
  header: string | null,
  charge: TapCharge,
): Promise<boolean> {
  if (!secret || !header) return false;
  const input = tapHashInput(charge);
  if (input === null) return false;
  const expected = await hmacSha256Hex(secret, input);
  return constantTimeEqual(expected, header.trim().toLowerCase());
}
