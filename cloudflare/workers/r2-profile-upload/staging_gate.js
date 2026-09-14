/**
 * Staging-only HTTP access gate.
 *
 * The staging Worker (`r2-profile-upload-staging`) is reachable at a public
 * workers.dev URL and talks to the real Broker Wallet Supabase project. An
 * unpublished URL is not access control, so when the `STAGING_TEST_KEY` secret
 * is bound, every HTTP request except a CORS preflight must carry the same
 * value in `X-Broker-Wallet-Staging-Key` before any Supabase, R2 or account
 * logic runs.
 *
 * Production never binds `STAGING_TEST_KEY`, so for production this gate is a
 * no-op and behaviour is unchanged. A bound but empty key denies everything:
 * a misconfigured staging Worker fails closed.
 *
 * This layer is in addition to, never instead of, the user's JWT and password
 * that `/account/delete` still requires. Scheduled (cron) runs are not HTTP
 * requests and are not gated.
 *
 * The key is never logged and never returned. The comparison hashes both
 * values with SHA-256 and compares the fixed-length digests without an early
 * exit, so neither the key's length nor a matching prefix is observable.
 */

export const STAGING_KEY_HEADER = 'X-Broker-Wallet-Staging-Key';

/** Returns true when the request may proceed to endpoint logic. */
export async function stagingRequestAllowed(request, env) {
  const expected = env?.STAGING_TEST_KEY;
  if (expected === undefined || expected === null) return true;
  if (typeof expected !== 'string' || expected.length === 0) return false;

  const supplied = request.headers.get(STAGING_KEY_HEADER);
  if (typeof supplied !== 'string' || supplied.length === 0) return false;

  return constantTimeEqual(supplied, expected);
}

export async function constantTimeEqual(a, b) {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(a)),
    crypto.subtle.digest('SHA-256', encoder.encode(b)),
  ]);
  const x = new Uint8Array(left);
  const y = new Uint8Array(right);
  let difference = 0;
  for (let index = 0; index < x.length; index += 1) {
    difference |= x[index] ^ y[index];
  }
  return difference === 0;
}
