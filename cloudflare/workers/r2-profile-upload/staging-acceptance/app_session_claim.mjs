// Broker Wallet — the Single Active Device claim step for the acceptance runners.
//
// Why. A runner signs in with the Supabase Auth password grant, which creates a
// NEW Auth session each time. Since migration 20261005175500 the database lets
// only the account's one ACTIVE Broker Wallet session reach app data, and the
// Worker asks it before every profile, media and account-deletion route
// (`is_current_app_session`: worker.js verifySupabaseTokenAndGetUserId and
// account_deletion.js deleteCallingAccount). A session that has not claimed is
// refused: 403 `session_superseded` from the Worker, and no rows (or the same
// message from `save_quotation`) from direct REST calls.
//
// What. Exactly what the app does after a fresh sign-in
// (lib/src/services/app_session_coordinator.dart): call the existing RPC
//
//   POST /rest/v1/rpc/claim_current_app_session   body {}   authenticated only
//
// with the access token the runner actually received from Auth, accept only the
// JSON answer `true`, then ask the Worker's own authority once more,
//
//   POST /rest/v1/rpc/is_current_app_session      body {}   read-only
//
// and require `true` again. Nothing here chooses, invents or writes a session
// id: the server reads `auth.uid()` and the JWT `session_id` itself. The decoded
// `session_id` is used only to refuse a token that cannot be claimed and to tell
// two sessions apart in a report as a one-way tag.
//
// Refused before any request: a key that is not a publishable key (so a
// service-role or secret key can never be sent as the user's claim identity), a
// token that is not an `authenticated` user's access token, and a token with no
// session id.
//
// Claiming ENDS every other session of the same account. That is the product
// rule (one active device), so use this only with disposable or designated
// test-only accounts; the launchers ask for an explicit acknowledgement first.
//
// Output discipline: errors carry a fixed code and an HTTP status only. Never a
// token, session id, account id, response body or URL.
//
// Node built-ins only: no `npm install` is needed.

import { createHash } from 'node:crypto';

export const CLAIM_RPC = '/rest/v1/rpc/claim_current_app_session';
export const CHECK_RPC = '/rest/v1/rpc/is_current_app_session';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PUBLISHABLE_PREFIX = 'sb_publishable_';

/** A fixed reason code (and HTTP status when there was one); nothing the server or caller sent. */
export class AppSessionClaimError extends Error {
  constructor(code, status = null) {
    super(`app session ${code}${status === null ? '' : ` (HTTP ${status})`}`);
    this.name = 'AppSessionClaimError';
    this.code = code;
    this.status = status;
  }
}

/** The claims in an access token's payload, or null. Correlation only: the database decides who is current. */
export function accessTokenClaims(accessToken) {
  try {
    const parts = String(accessToken).split('.');
    if (parts.length !== 3) return null;
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return claims && typeof claims === 'object' && !Array.isArray(claims) ? claims : null;
  } catch (_) {
    return null;
  }
}

/** The JWT `session_id` claim when it is a UUID, otherwise null. */
export function sessionIdFromAccessToken(accessToken) {
  const id = accessTokenClaims(accessToken)?.session_id;
  return typeof id === 'string' && UUID.test(id) ? id : null;
}

/** A short one-way tag, so a report can tell two sessions apart without holding either id. */
export function sessionTag(sessionId) {
  return createHash('sha256').update(`broker-wallet-session:${sessionId}`).digest('hex').slice(0, 8);
}

/** Refuses anything that is not a user's access token plus a publishable key; returns the session id. */
function userSessionId({ supabaseUrl, publishableKey, accessToken }) {
  if (typeof supabaseUrl !== 'string' || !supabaseUrl.startsWith('https://')) {
    throw new AppSessionClaimError('insecure_url');
  }
  if (typeof publishableKey !== 'string' || !publishableKey.startsWith(PUBLISHABLE_PREFIX)) {
    throw new AppSessionClaimError('not_a_publishable_key');
  }
  if (accessTokenClaims(accessToken)?.role !== 'authenticated') {
    throw new AppSessionClaimError('not_a_user_session');
  }
  const sessionId = sessionIdFromAccessToken(accessToken);
  if (!sessionId) throw new AppSessionClaimError('no_session_id');
  return sessionId;
}

async function callRpc({ supabaseUrl, publishableKey, accessToken, path, fetchImpl, timeoutMs }) {
  try {
    const response = await fetchImpl(`${supabaseUrl}${path}`, {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
      signal: AbortSignal.timeout(timeoutMs),
    });
    let body = null;
    try {
      body = await response.json();
    } catch (_) {
      body = null;
    }
    return { status: response.status, body };
  } catch (_) {
    throw new AppSessionClaimError('unavailable');
  }
}

/** PostgREST puts the SQL exception text in `message`; only the two fixed words are ever read. */
function refusal(status, body) {
  const message = typeof body?.message === 'string' ? body.message : '';
  if (message.includes('session_superseded')) return new AppSessionClaimError('session_superseded', status);
  if (message.includes('session_missing')) return new AppSessionClaimError('session_missing', status);
  if (status === 404) return new AppSessionClaimError('function_missing', status);
  return new AppSessionClaimError(status >= 500 ? 'unavailable' : 'rejected', status);
}

/**
 * Claims the session that [accessToken] belongs to. Resolves `{ sessionTag }`
 * only when the database answers `true`; otherwise throws [AppSessionClaimError]
 * (`session_superseded` when a newer session already claimed: a displaced
 * session can never reclaim).
 */
export async function claimAppSession({ supabaseUrl, publishableKey, accessToken, fetchImpl = fetch, timeoutMs = 30_000 }) {
  const sessionId = userSessionId({ supabaseUrl, publishableKey, accessToken });
  const { status, body } = await callRpc({ supabaseUrl, publishableKey, accessToken, path: CLAIM_RPC, fetchImpl, timeoutMs });
  if (status === 200) {
    if (body === true) return { sessionTag: sessionTag(sessionId) };
    throw new AppSessionClaimError('unexpected_answer', status);
  }
  throw refusal(status, body);
}

/** The Worker's own authority, read-only: is [accessToken]'s session the account's active one? */
export async function isAppSessionCurrent({ supabaseUrl, publishableKey, accessToken, fetchImpl = fetch, timeoutMs = 30_000 }) {
  userSessionId({ supabaseUrl, publishableKey, accessToken });
  const { status, body } = await callRpc({ supabaseUrl, publishableKey, accessToken, path: CHECK_RPC, fetchImpl, timeoutMs });
  if (status === 200) {
    if (body === true || body === false) return body;
    throw new AppSessionClaimError('unexpected_answer', status);
  }
  throw refusal(status, body);
}

/** Claim, then require the database to confirm the same session is current. */
export async function claimAndVerifyAppSession(args) {
  const { sessionTag: tag } = await claimAppSession(args);
  if ((await isAppSessionCurrent(args)) !== true) throw new AppSessionClaimError('not_current');
  return { sessionTag: tag };
}

/**
 * The runner-facing step. [session] is the `{ label, token }` a runner's own
 * signIn returned; [check] and [FatalError] are that runner's own. Records one
 * PASS, or one FAIL and a FatalError: continuing would only produce 403s and
 * rows that cannot be written. Call it only AFTER the runner has proved the
 * account is the intended test account, because claiming ends the account's
 * other sessions.
 */
export async function claimSessionForRun({ session, supabaseUrl, publishableKey, check, FatalError, section = 'setup', fetchImpl }) {
  try {
    const { sessionTag: tag } = await claimAndVerifyAppSession({
      supabaseUrl, publishableKey, accessToken: session.token, fetchImpl,
    });
    session.tag = tag;
    check(section, `account ${session.label} claimed the active app session and the database confirms it is current (session ${tag})`, true);
    return tag;
  } catch (error) {
    if (!(error instanceof AppSessionClaimError)) throw error;
    check(section, `account ${session.label} claimed the active app session`, false, error.message);
    throw new FatalError(`account ${session.label} could not claim the active app session (${error.code}); nothing was written`);
  }
}
