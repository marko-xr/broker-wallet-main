import { ActiveSessionUnavailable, isCurrentAppSession } from './active_session.js';
import {
  AccountDeletionError,
  DeletionErrorCode,
  loadVerifiedIdentity,
  tokenCarriesRecoveryMethod,
  verifyAccountPassword,
} from './account_deletion.js';

/**
 * Phone numbers under Model X (supabase/migrations/20261122130000_phone_identity_model_x.sql).
 *
 *   POST /account/contact-phone/start     email account: send a code to a contact number
 *   POST /account/contact-phone/confirm   email account: check the code, store the number
 *   POST /account/phone-identity/start    phone account: start changing its sign-in number
 *   POST /account/phone-identity/confirm  phone account: prove both numbers, change it
 *
 * WHAT A CODE CAN DO
 *   A contact-number code proves only that the caller can receive SMS at that
 *   number. It is checked here with the SMS provider's verification API and
 *   then stored as a CONTACT number in public.profiles by the service role. It
 *   never reaches Supabase Auth, never creates or returns a session, and never
 *   makes the number usable for signing in: email accounts never hold
 *   auth.users.phone (a database guard refuses it).
 *
 * AUTHORITY
 *   The account is taken only from the bearer token as verified by Supabase
 *   Auth (`GET /auth/v1/user`), the session from that token's `session_id`
 *   claim, and the request must come from the account's current app session
 *   (Single Active Device). A recovery session is refused. Every database step
 *   is a service-role function bound to (account, session), so a code started
 *   from one session cannot be completed from another, and a superseded or
 *   stolen older session is refused before anything is sent.
 *
 * SIGN-IN NUMBER CHANGE (phone accounts)
 *   Possession of the current number is proven with a Supabase sign-in code
 *   sent to the number taken from the verified identity (never from the
 *   request) and checked server-side; the session that check creates is
 *   revoked before anything else, and a failed revocation stops the change.
 *   The account password is accepted instead when the account has one. The new
 *   number is proven through the provider. Only then does the database issue a
 *   single-use grant for exactly that number, which its auth.users guard
 *   consumes when this Worker writes the number with the Auth Admin API.
 *   Supabase's own self-service phone change is refused by the database.
 *
 * PROVIDER
 *   No SMS verification provider is chosen yet. `providerFromEnv` returns null,
 *   and every route that needs one answers 503 `verification_unavailable`
 *   before writing anything. A provider adapter implements:
 *     start(phoneE164)              -> { ref }   (sends the code)
 *     check({ phoneE164, code, ref }) -> 'approved' | 'rejected' | 'expired'
 *   and throws VerificationProviderError('rate_limited' | 'invalid_number' |
 *   'unavailable') on failure. Tests inject an isolated fake.
 *
 * Responses carry only fixed codes. Nothing here logs a token, password,
 * phone number, code, user id or provider reference.
 */

export const CONTACT_PHONE_START_PATH = '/account/contact-phone/start';
export const CONTACT_PHONE_CONFIRM_PATH = '/account/contact-phone/confirm';
export const PHONE_IDENTITY_START_PATH = '/account/phone-identity/start';
export const PHONE_IDENTITY_CONFIRM_PATH = '/account/phone-identity/confirm';
export const PHONE_VERIFICATION_PATHS = Object.freeze([
  CONTACT_PHONE_START_PATH,
  CONTACT_PHONE_CONFIRM_PATH,
  PHONE_IDENTITY_START_PATH,
  PHONE_IDENTITY_CONFIRM_PATH,
]);

/** Lifetime of a verification record; matches common provider code lifetimes. */
export const VERIFICATION_TTL_SECONDS = 600;

export const PhoneErrorCode = Object.freeze({
  sessionExpired: 'session_expired',
  sessionSuperseded: 'session_superseded',
  sessionMismatch: 'session_mismatch',
  recoverySession: 'recovery_session',
  accountMismatch: 'account_mismatch',
  invalidRequest: 'invalid_request',
  invalidPhone: 'invalid_phone',
  invalidCode: 'invalid_code',
  phoneUnavailable: 'phone_unavailable',
  phoneAlreadyVerified: 'phone_already_verified',
  notAvailableForAccount: 'not_available_for_account',
  currentProofFailed: 'current_proof_failed',
  reauthenticationUnsupported: 'reauthentication_unsupported',
  rateLimited: 'rate_limited',
  tooManyAttempts: 'too_many_attempts',
  verificationExpired: 'verification_expired',
  verificationNotFound: 'verification_not_found',
  verificationUnavailable: 'verification_unavailable',
  phoneChangeFailed: 'phone_change_failed',
  serviceUnavailable: 'service_unavailable',
  unknown: 'unknown',
});

export class PhoneVerificationError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

/** Thrown by a provider adapter. */
export class VerificationProviderError extends Error {
  constructor(kind) {
    super(kind);
    this.kind = kind;
  }
}

/** No provider is chosen yet (owner decision). Never a fallback, never a stub. */
export function providerFromEnv(_env) {
  return null;
}

const UAE_MOBILE_E164 = /^\+9715[0-9]{8}$/;
const PROVIDER_CODE = /^[0-9]{4,10}$/;
const SUPABASE_CODE = /^[0-9]{6,10}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PROVIDER_REF = 200;

const E = PhoneErrorCode;
const fail = (code, status) => new PhoneVerificationError(code, status);

// Database refusals (raised by the service-role functions) -> fixed responses.
const RPC_REFUSALS = Object.freeze({
  phone_unavailable: [E.phoneUnavailable, 409],
  phone_already_verified: [E.phoneAlreadyVerified, 409],
  not_available_for_account: [E.notAvailableForAccount, 409],
  too_many_requests: [E.rateLimited, 429],
  invalid_request: [E.invalidRequest, 400],
  verification_not_found: [E.verificationNotFound, 404],
  session_mismatch: [E.sessionMismatch, 403],
  current_number_not_proven: [E.currentProofFailed, 403],
});

const DELETION_TO_PHONE = Object.freeze({
  [DeletionErrorCode.sessionExpired]: [E.sessionExpired, 401],
  [DeletionErrorCode.reauthenticationFailed]: [E.currentProofFailed, 403],
  [DeletionErrorCode.reauthenticationUnsupported]: [E.reauthenticationUnsupported, 409],
  [DeletionErrorCode.accountMismatch]: [E.accountMismatch, 403],
  [DeletionErrorCode.rateLimited]: [E.rateLimited, 429],
  [DeletionErrorCode.serviceUnavailable]: [E.serviceUnavailable, 503],
});

/**
 * Returns a Response for the four phone routes, or null for any other path.
 * Never rejects.
 */
export async function handlePhoneVerificationRequest(request, env, { respond, fetchImpl = fetch, provider } = {}) {
  const path = new URL(request.url).pathname;
  if (request.method !== 'POST' || !PHONE_VERIFICATION_PATHS.includes(path)) return null;
  const headers = { 'Cache-Control': 'no-store' };
  try {
    const deps = {
      env,
      fetchImpl,
      provider: provider === undefined ? providerFromEnv(env) : provider,
      clientIp: request.headers.get('CF-Connecting-IP') || '',
    };
    let result;
    if (path === CONTACT_PHONE_START_PATH) result = await startContactPhone(request, deps);
    else if (path === CONTACT_PHONE_CONFIRM_PATH) result = await confirmContactPhone(request, deps);
    else if (path === PHONE_IDENTITY_START_PATH) result = await startPhoneIdentityChange(request, deps);
    else result = await confirmPhoneIdentityChange(request, deps);
    return respond(result, 200, env, headers);
  } catch (error) {
    if (error instanceof PhoneVerificationError) {
      console.error('[phone-verify] refused', error.code);
      return respond({ error: error.code }, error.status, env, headers);
    }
    console.error('[phone-verify] unexpected failure');
    return respond({ error: E.unknown }, 500, env, headers);
  }
}

// ---------------------------------------------------------------------------
// Contact number (email accounts)
// ---------------------------------------------------------------------------

async function startContactPhone(request, deps) {
  const caller = await authorizeCaller(request, deps);
  const body = await readBody(request);
  const phone = requireUaeMobile(body.phone);
  const provider = requireProvider(deps);

  const id = await rpc(deps, 'phone_verification_start', {
    p_user: caller.userId,
    p_session: caller.sessionId,
    p_purpose: 'contact',
    p_phone: phone,
    p_ttl_seconds: VERIFICATION_TTL_SECONDS,
  });
  if (!isUuid(id)) throw fail(E.serviceUnavailable, 503);

  await sendProviderCode(provider, phone, id, caller, deps);
  return { verificationId: id, expiresInSeconds: VERIFICATION_TTL_SECONDS };
}

async function confirmContactPhone(request, deps) {
  const caller = await authorizeCaller(request, deps);
  const body = await readBody(request);
  const id = requireUuid(body.verificationId);
  const code = requireCode(body.code, PROVIDER_CODE);
  const provider = requireProvider(deps);

  const attempt = await countAttempt(deps, id, caller);
  if (attempt.purpose !== 'contact') throw fail(E.verificationNotFound, 404);
  if (attempt.result === 'already_verified') {
    return { status: 'verified', phone: attempt.phone_e164 };
  }
  requireAttemptOk(attempt);

  const verdict = await checkProviderCode(provider, attempt, code, id, caller, deps);
  if (verdict !== 'approved') throw verdict;

  const outcome = await rpc(deps, 'contact_phone_confirm', {
    p_id: id, p_user: caller.userId, p_session: caller.sessionId,
  });
  if (outcome === 'verified') return { status: 'verified', phone: attempt.phone_e164 };
  if (outcome === 'phone_unavailable') throw fail(E.phoneUnavailable, 409);
  if (outcome === 'verification_expired') throw fail(E.verificationExpired, 410);
  throw fail(E.serviceUnavailable, 503);
}

// ---------------------------------------------------------------------------
// Sign-in number change (phone accounts)
// ---------------------------------------------------------------------------

async function startPhoneIdentityChange(request, deps) {
  const caller = await authorizeCaller(request, deps);
  const body = await readBody(request);
  const phone = requireUaeMobile(body.newPhone);
  const proof = body.currentProof === undefined ? 'sms' : body.currentProof;
  if (proof !== 'sms' && proof !== 'password') throw fail(E.invalidRequest, 400);
  if (proof === 'password' && !hasEmailIdentity(caller.identity)) {
    throw fail(E.reauthenticationUnsupported, 409);
  }
  const currentPhone = confirmedPhoneOf(caller.identity);
  if (!currentPhone) throw fail(E.notAvailableForAccount, 409);
  const provider = requireProvider(deps);

  const id = await rpc(deps, 'phone_verification_start', {
    p_user: caller.userId,
    p_session: caller.sessionId,
    p_purpose: 'identity_change',
    p_phone: phone,
    p_ttl_seconds: VERIFICATION_TTL_SECONDS,
  });
  if (!isUuid(id)) throw fail(E.serviceUnavailable, 503);

  if (proof === 'sms') {
    try {
      await requestCurrentNumberCode(currentPhone, deps);
    } catch (error) {
      await closeRecord(deps, id, caller);
      throw error;
    }
  }
  await sendProviderCode(provider, phone, id, caller, deps);
  return { verificationId: id, expiresInSeconds: VERIFICATION_TTL_SECONDS, currentProof: proof };
}

async function confirmPhoneIdentityChange(request, deps) {
  const caller = await authorizeCaller(request, deps);
  const body = await readBody(request);
  const id = requireUuid(body.verificationId);
  const newCode = requireCode(body.newCode, PROVIDER_CODE);
  const usePassword = typeof body.password === 'string' && body.password.length > 0;
  const currentCode = usePassword ? null : body.currentCode;
  const currentPhone = confirmedPhoneOf(caller.identity);
  if (!currentPhone) throw fail(E.notAvailableForAccount, 409);
  const provider = requireProvider(deps);

  const attempt = await countAttempt(deps, id, caller);
  if (attempt.purpose !== 'identity_change') throw fail(E.verificationNotFound, 404);
  requireAttemptOk(attempt);

  if (!attempt.current_proven) {
    if (usePassword) {
      await provePassword(caller.identity, body.password, deps);
    } else {
      await proveCurrentNumber(currentPhone, requireCode(currentCode, SUPABASE_CODE), caller, deps);
    }
    const recorded = await rpc(deps, 'phone_identity_current_proven', {
      p_id: id, p_user: caller.userId, p_session: caller.sessionId,
    });
    if (recorded !== true) throw fail(E.verificationExpired, 410);
  }

  const verdict = await checkProviderCode(provider, attempt, newCode, id, caller, deps);
  if (verdict !== 'approved') throw verdict;

  const granted = await rpc(deps, 'phone_identity_change_grant', {
    p_id: id, p_user: caller.userId, p_session: caller.sessionId,
  });
  if (granted === 'phone_unavailable') throw fail(E.phoneUnavailable, 409);
  if (granted === 'verification_expired') throw fail(E.verificationExpired, 410);
  if (granted !== 'granted') throw fail(E.serviceUnavailable, 503);

  const digits = attempt.phone_e164.slice(1);
  await writeSignInNumber(caller.userId, digits, deps);
  await bestEffortSignOutOtherSessions(caller.authorization, deps);
  return { status: 'changed', phone: attempt.phone_e164 };
}

// ---------------------------------------------------------------------------
// Caller
// ---------------------------------------------------------------------------

async function authorizeCaller(request, deps) {
  const { env, fetchImpl } = deps;
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY || !env.SUPABASE_SECRET_KEY) {
    throw fail(E.serviceUnavailable, 503);
  }
  const authorization = request.headers.get('Authorization') || '';
  if (!authorization.startsWith('Bearer ') || authorization.length <= 'Bearer '.length) {
    throw fail(E.sessionExpired, 401);
  }
  let identity;
  try {
    identity = await loadVerifiedIdentity(authorization, env, fetchImpl);
  } catch (error) {
    throw fromDeletionError(error);
  }
  // Read only after Supabase Auth accepted this exact token.
  const sessionId = tokenClaims(authorization)?.session_id;
  if (!isUuid(sessionId)) throw fail(E.sessionExpired, 401);

  let current;
  try {
    current = await isCurrentAppSession(authorization, env, fetchImpl);
  } catch (error) {
    if (error instanceof ActiveSessionUnavailable) throw fail(E.serviceUnavailable, 503);
    throw error;
  }
  if (!current) throw fail(E.sessionSuperseded, 403);
  if (tokenCarriesRecoveryMethod(authorization)) throw fail(E.recoverySession, 403);
  return { identity, userId: identity.id, sessionId, authorization };
}

function tokenClaims(authorization) {
  try {
    const payload = authorization.slice('Bearer '.length).split('.')[1];
    if (!payload) return null;
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(normalized + '='.repeat((4 - (normalized.length % 4)) % 4)));
  } catch (_) {
    return null;
  }
}

function hasEmailIdentity(identity) {
  const email = typeof identity.email === 'string' ? identity.email.trim() : '';
  const identities = Array.isArray(identity.identities) ? identity.identities : [];
  return email !== '' && identities.some((entry) => entry?.provider === 'email');
}

/** The account's confirmed sign-in number from the verified identity, as Supabase stores it (no '+'). */
function confirmedPhoneOf(identity) {
  const phone = typeof identity.phone === 'string' ? identity.phone.replace(/^\+/, '') : '';
  if (!/^9715[0-9]{8}$/.test(phone) || !identity.phone_confirmed_at) return '';
  return phone;
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

async function readBody(request) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    throw fail(E.invalidRequest, 400);
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw fail(E.invalidRequest, 400);
  return body;
}

function requireUaeMobile(value) {
  if (typeof value !== 'string' || !UAE_MOBILE_E164.test(value)) throw fail(E.invalidPhone, 400);
  return value;
}

function requireUuid(value) {
  if (!isUuid(value)) throw fail(E.invalidRequest, 400);
  return value.toLowerCase();
}

function requireCode(value, pattern) {
  if (typeof value !== 'string' || !pattern.test(value)) throw fail(E.invalidCode, 422);
  return value;
}

function isUuid(value) {
  return typeof value === 'string' && UUID.test(value);
}

function requireProvider(deps) {
  const provider = deps.provider;
  if (!provider || typeof provider.start !== 'function' || typeof provider.check !== 'function') {
    throw fail(E.verificationUnavailable, 503);
  }
  return provider;
}

// ---------------------------------------------------------------------------
// Verification records (service-role functions)
// ---------------------------------------------------------------------------

async function rpc(deps, name, args) {
  const { env, fetchImpl } = deps;
  let response;
  try {
    response = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_SECRET_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    });
  } catch (_) {
    throw fail(E.serviceUnavailable, 503);
  }
  const body = await readJsonOrNull(response);
  if (response.ok) return body;
  const refusal = response.status < 500 && typeof body?.message === 'string' ? RPC_REFUSALS[body.message] : null;
  if (refusal) throw fail(refusal[0], refusal[1]);
  throw fail(E.serviceUnavailable, 503);
}

async function countAttempt(deps, id, caller) {
  const rows = await rpc(deps, 'phone_verification_attempt', {
    p_id: id, p_user: caller.userId, p_session: caller.sessionId,
  });
  const row = Array.isArray(rows) ? rows[0] : null;
  if (!row || typeof row.result !== 'string') throw fail(E.serviceUnavailable, 503);
  return row;
}

function requireAttemptOk(attempt) {
  if (attempt.result === 'verification_expired') throw fail(E.verificationExpired, 410);
  if (attempt.result === 'too_many_attempts') throw fail(E.tooManyAttempts, 429);
  if (attempt.result !== 'ok' || typeof attempt.phone_e164 !== 'string' || !UAE_MOBILE_E164.test(attempt.phone_e164)) {
    throw fail(E.verificationNotFound, 404);
  }
}

async function closeRecord(deps, id, caller) {
  try {
    await rpc(deps, 'phone_verification_fail', { p_id: id, p_user: caller.userId });
  } catch (_) {
    // The record expires on its own.
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

async function sendProviderCode(provider, phone, id, caller, deps) {
  let ref;
  try {
    const started = await provider.start(phone);
    ref = started?.ref;
  } catch (error) {
    await closeRecord(deps, id, caller);
    throw providerFailure(error);
  }
  if (typeof ref !== 'string' || ref.length === 0 || ref.length > MAX_PROVIDER_REF) {
    await closeRecord(deps, id, caller);
    throw fail(E.verificationUnavailable, 503);
  }
  const attached = await rpc(deps, 'phone_verification_attach', { p_id: id, p_user: caller.userId, p_provider_ref: ref });
  if (attached !== true) {
    await closeRecord(deps, id, caller);
    throw fail(E.serviceUnavailable, 503);
  }
}

/** Resolves to 'approved' or to the PhoneVerificationError to throw. */
async function checkProviderCode(provider, attempt, code, id, caller, deps) {
  let verdict;
  try {
    verdict = await provider.check({ phoneE164: attempt.phone_e164, code, ref: attempt.provider_ref });
  } catch (error) {
    // The attempt is already counted; nothing was stored.
    return providerFailure(error);
  }
  if (verdict === 'approved') return 'approved';
  if (verdict === 'rejected') return fail(E.invalidCode, 422);
  if (verdict === 'expired') {
    await closeRecord(deps, id, caller);
    return fail(E.verificationExpired, 410);
  }
  return fail(E.verificationUnavailable, 503);
}

function providerFailure(error) {
  const kind = error instanceof VerificationProviderError ? error.kind : 'unavailable';
  if (kind === 'rate_limited') return fail(E.rateLimited, 429);
  if (kind === 'invalid_number') return fail(E.invalidPhone, 400);
  return fail(E.verificationUnavailable, 503);
}

// ---------------------------------------------------------------------------
// Current sign-in number / password (Supabase Auth)
// ---------------------------------------------------------------------------

function authHeaders(deps, extra = {}) {
  const headers = { apikey: deps.env.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json', ...extra };
  // Per-client rate limiting on Supabase Auth instead of the Worker's address
  // (to be confirmed on the staging project).
  if (deps.clientIp) headers['Sb-Forwarded-For'] = deps.clientIp;
  return headers;
}

async function requestCurrentNumberCode(currentPhone, deps) {
  let response;
  try {
    response = await deps.fetchImpl(`${deps.env.SUPABASE_URL}/auth/v1/otp`, {
      method: 'POST',
      headers: authHeaders(deps),
      // create_user:false: this can only ever reach the existing account.
      body: JSON.stringify({ phone: currentPhone, create_user: false }),
    });
  } catch (_) {
    throw fail(E.serviceUnavailable, 503);
  }
  if (response.ok) return;
  if (response.status === 429) throw fail(E.rateLimited, 429);
  throw fail(E.verificationUnavailable, 503);
}

async function proveCurrentNumber(currentPhone, code, caller, deps) {
  let response;
  try {
    response = await deps.fetchImpl(`${deps.env.SUPABASE_URL}/auth/v1/verify`, {
      method: 'POST',
      headers: authHeaders(deps),
      body: JSON.stringify({ type: 'sms', phone: currentPhone, token: code }),
    });
  } catch (_) {
    throw fail(E.serviceUnavailable, 503);
  }
  if (response.status === 429) throw fail(E.rateLimited, 429);
  if (response.status >= 500) throw fail(E.serviceUnavailable, 503);
  if (!response.ok) throw fail(E.currentProofFailed, 403);

  const session = await readJsonOrNull(response);
  // The check session must not survive, whatever else happens.
  const revoked = await revokeSession(session?.access_token, deps);
  if (session?.user?.id !== caller.userId) throw fail(E.accountMismatch, 403);
  if (!revoked) throw fail(E.serviceUnavailable, 503);
}

async function provePassword(identity, password, deps) {
  try {
    await verifyAccountPassword(identity, password, deps.env, deps.fetchImpl);
  } catch (error) {
    throw fromDeletionError(error);
  }
}

async function revokeSession(accessToken, deps) {
  if (typeof accessToken !== 'string' || !accessToken) return false;
  try {
    const response = await deps.fetchImpl(`${deps.env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: deps.env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${accessToken}` },
    });
    return response.ok;
  } catch (_) {
    return false;
  }
}

async function bestEffortSignOutOtherSessions(authorization, deps) {
  try {
    await deps.fetchImpl(`${deps.env.SUPABASE_URL}/auth/v1/logout?scope=others`, {
      method: 'POST',
      headers: { apikey: deps.env.SUPABASE_PUBLISHABLE_KEY, Authorization: authorization },
    });
  } catch (_) {
    // Older sessions are already refused by Single Active Device.
  }
}

// ---------------------------------------------------------------------------
// Auth Admin API write (consumes the database grant)
// ---------------------------------------------------------------------------

async function writeSignInNumber(userId, digits, deps) {
  const { env, fetchImpl } = deps;
  const url = `${env.SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`;
  const admin = { apikey: env.SUPABASE_SECRET_KEY, 'Content-Type': 'application/json' };
  try {
    const response = await fetchImpl(url, {
      method: 'PUT',
      headers: admin,
      body: JSON.stringify({ phone: digits, phone_confirm: true }),
    });
    if (response.ok) {
      const user = await readJsonOrNull(response);
      if (user?.id === userId && String(user?.phone || '').replace(/^\+/, '') === digits) return;
    }
  } catch (_) {
    // Settled below by reading the account back.
  }
  try {
    const response = await fetchImpl(url, { method: 'GET', headers: admin });
    if (response.ok) {
      const user = await readJsonOrNull(response);
      if (user?.id === userId && String(user?.phone || '').replace(/^\+/, '') === digits) return;
    }
  } catch (_) {
    // Unknown.
  }
  throw fail(E.phoneChangeFailed, 502);
}

// ---------------------------------------------------------------------------

function fromDeletionError(error) {
  if (error instanceof AccountDeletionError) {
    const mapped = DELETION_TO_PHONE[error.code];
    if (mapped) return fail(mapped[0], mapped[1]);
    return fail(E.serviceUnavailable, 503);
  }
  return error;
}

async function readJsonOrNull(response) {
  try {
    return await response.json();
  } catch (_) {
    return null;
  }
}
