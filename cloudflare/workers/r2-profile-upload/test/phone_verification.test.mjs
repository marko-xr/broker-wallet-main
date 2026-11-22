// Behavioural tests for the Model X phone routes (phone_verification.js).
//
// Run with: npm test   (or a bare `node --test` from this directory)
//
// Supabase Auth, the PostgREST service-role functions and the SMS verification
// provider are in-memory fakes that record every call, so each test can assert
// what did and did not happen. The provider fake exists only here: production
// has no provider (providerFromEnv returns null) until the owner chooses one.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  CONTACT_PHONE_CONFIRM_PATH,
  CONTACT_PHONE_START_PATH,
  PHONE_IDENTITY_CONFIRM_PATH,
  PHONE_IDENTITY_START_PATH,
  VerificationProviderError,
  handlePhoneVerificationRequest,
  providerFromEnv,
} from '../phone_verification.js';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE = 'sb_publishable_test';
const SECRET = 'sb_secret_TEST_SECRET_VALUE';
const ENV = { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE, SUPABASE_SECRET_KEY: SECRET };

const ALICE = '11111111-1111-4111-8111-111111111111'; // email account
const PAT = '33333333-3333-4333-8333-333333333333'; // phone account
const SESSION_A = 'aaaaaaaa-0000-4000-8000-000000000001';
const SESSION_A_OLD = 'aaaaaaaa-0000-4000-8000-000000000002';
const SESSION_P = 'bbbbbbbb-0000-4000-8000-000000000001';
const PAT_PHONE = '971501111111';
const CONTACT = '+971503333333';
const NEW_NUMBER = '+971507777777';
const PROVIDER_CODE = '654321';
const SUPABASE_CODE = '123456';

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function token(sub, sessionId, amr = [{ method: 'password', timestamp: 1 }]) {
  const claims = { sub, amr, ...(sessionId === undefined ? {} : { session_id: sessionId }) };
  return `${base64Url({ alg: 'HS256' })}.${base64Url(claims)}.signature`;
}

function respond(body, status, _env, extraHeaders = {}) {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...extraHeaders },
  });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function refusal(message) {
  return json({ code: 'P0001', message, details: null, hint: null }, 400);
}

// ---------------------------------------------------------------------------
// In-memory Supabase
// ---------------------------------------------------------------------------

function makeWorld(overrides = {}) {
  const w = {
    users: {
      [ALICE]: { id: ALICE, email: 'alice@example.test', phone: '', identities: [{ provider: 'email' }] },
      [PAT]: {
        id: PAT, email: '', phone: PAT_PHONE, phone_confirmed_at: '2026-11-01T00:00:00Z', identities: [{ provider: 'phone' }],
      },
    },
    methods: { [ALICE]: 'email', [PAT]: 'phone' },
    passwords: {},
    // token -> { valid, current }
    tokens: new Map(),
    held: new Set(['+971502222222']),
    records: new Map(),
    grants: new Map(),
    contact: {},
    calls: [],
    otpStatus: 200,
    revokeOk: true,
    adminMode: 'ok', // 'ok' | 'fail' | 'fail-after-apply'
    sadUnavailable: false,
    rpcDown: false,
    nextId: 1,
    ...overrides,
  };
  w.issue = (sub, sessionId, { current = true, amr } = {}) => {
    const t = token(sub, sessionId, amr);
    w.tokens.set(t, { sub, current });
    return t;
  };
  w.count = (pred) => w.calls.filter(pred).length;
  w.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const method = init.method || 'GET';
    const headers = init.headers || {};
    const body = init.body ? JSON.parse(init.body) : undefined;
    const call = { path: u.pathname + u.search, method, headers, body };
    w.calls.push(call);
    const bearer = (headers.Authorization || '').replace(/^Bearer /, '');

    if (u.pathname === '/auth/v1/user') {
      const t = w.tokens.get(bearer);
      if (!t) return json({ msg: 'invalid' }, 401);
      return json(w.users[t.sub]);
    }
    if (u.pathname === '/rest/v1/rpc/is_current_app_session') {
      if (w.sadUnavailable) return json({}, 503);
      return json(w.tokens.get(bearer)?.current === true);
    }
    if (u.pathname.startsWith('/rest/v1/rpc/')) {
      assert.equal(headers.apikey, SECRET, 'verification functions are called with the server secret only');
      assert.equal(headers.Authorization, undefined, 'no user token on service-role calls');
      if (w.rpcDown) throw new TypeError('network');
      return rpc(w, u.pathname.slice('/rest/v1/rpc/'.length), body);
    }
    if (u.pathname === '/auth/v1/otp') {
      assert.equal(headers.apikey, PUBLISHABLE);
      return json({}, w.otpStatus);
    }
    if (u.pathname === '/auth/v1/verify') {
      assert.equal(headers.apikey, PUBLISHABLE);
      const holder = Object.values(w.users).find((x) => x.phone === body.phone);
      if (body.type !== 'sms' || !holder || body.token !== SUPABASE_CODE) return json({ msg: 'Token has expired or is invalid' }, 403);
      const userId = w.verifyAs || holder.id;
      return json({ access_token: `check-session-${w.nextId++}`, user: { id: userId } });
    }
    if (u.pathname === '/auth/v1/token') {
      const user = Object.values(w.users).find((x) => x.email === body.email);
      if (!user || w.passwords[user.id] !== body.password) return json({ msg: 'invalid' }, 400);
      return json({ access_token: 'password-check-session', user: { id: user.id } });
    }
    if (u.pathname === '/auth/v1/logout') {
      if (u.searchParams.get('scope') === 'local' && !w.revokeOk) return json({ msg: 'error' }, 500);
      return new Response(null, { status: 204 });
    }
    if (u.pathname.startsWith('/auth/v1/admin/users/')) {
      assert.equal(headers.apikey, SECRET);
      const id = decodeURIComponent(u.pathname.split('/').pop());
      const user = w.users[id];
      if (method === 'GET') return user ? json(user) : json({}, 404);
      if (method === 'PUT') {
        if (w.adminMode === 'fail') return json({ msg: 'Database error updating user' }, 500);
        // The database guard: only against an unconsumed grant for this number.
        const grant = w.grants.get(id);
        if (!grant || grant.consumed || grant.digits !== body.phone) return json({ msg: 'Database error updating user' }, 500);
        grant.consumed = true;
        user.phone = body.phone;
        if (w.adminMode === 'fail-after-apply') return json({ msg: 'timeout' }, 504);
        return json(user);
      }
    }
    throw new Error(`unexpected request ${method} ${u.pathname}`);
  };
  return w;
}

function rpc(w, name, a) {
  if (name === 'phone_verification_start') {
    if (w.startRefusal) return refusal(w.startRefusal);
    const method = w.methods[a.p_user];
    if ((a.p_purpose === 'contact' && method !== 'email') || (a.p_purpose === 'identity_change' && method !== 'phone')) {
      return refusal('not_available_for_account');
    }
    if (w.held.has(a.p_phone)) return refusal('phone_unavailable');
    for (const r of w.records.values()) {
      if (r.user === a.p_user && r.purpose === a.p_purpose && r.status === 'pending') r.status = 'superseded';
    }
    const id = `00000000-0000-4000-8000-${String(w.nextId++).padStart(12, '0')}`;
    w.records.set(id, {
      id, user: a.p_user, session: a.p_session, purpose: a.p_purpose, phone: a.p_phone,
      ref: null, attempts: 0, status: 'pending', expired: false, currentProven: false,
    });
    return json(id);
  }
  const r = w.records.get(a.p_id);
  if (name === 'phone_verification_attach') {
    const ok = !!r && r.user === a.p_user && r.status === 'pending' && r.ref === null;
    if (ok) r.ref = a.p_provider_ref;
    return json(ok);
  }
  if (name === 'phone_verification_fail') {
    const ok = !!r && r.user === a.p_user && r.status === 'pending';
    if (ok) r.status = 'failed';
    return json(ok);
  }
  if (!r || r.user !== a.p_user) return refusal('verification_not_found');
  if (r.session !== a.p_session) return refusal('session_mismatch');
  if (name === 'phone_verification_attempt') {
    const row = (result, extra = {}) => json([{ result, phone_e164: null, provider_ref: null, purpose: r.purpose, current_proven: false, ...extra }]);
    if (r.status === 'verified' && r.purpose === 'contact') return row('already_verified', { phone_e164: r.phone });
    if (r.status !== 'pending' || r.ref === null) return refusal('verification_not_found');
    if (r.expired) { r.status = 'failed'; return row('verification_expired'); }
    if (r.attempts >= 5) { r.status = 'failed'; return row('too_many_attempts'); }
    r.attempts += 1;
    return row('ok', { phone_e164: r.phone, provider_ref: r.ref, current_proven: r.currentProven });
  }
  if (name === 'contact_phone_confirm') {
    if (r.purpose !== 'contact') return refusal('verification_not_found');
    if (r.status === 'verified') return json('verified');
    if (r.status !== 'pending') return json('verification_expired');
    if (w.held.has(r.phone)) { r.status = 'failed'; return json('phone_unavailable'); }
    r.status = 'verified';
    w.contact[r.user] = r.phone;
    return json('verified');
  }
  if (name === 'phone_identity_current_proven') {
    const ok = r.purpose === 'identity_change' && r.status === 'pending' && !r.expired;
    if (ok) r.currentProven = true;
    return json(ok);
  }
  if (name === 'phone_identity_change_grant') {
    if (w.grantOverride !== undefined) return json(w.grantOverride);
    if (r.purpose !== 'identity_change') return refusal('verification_not_found');
    if (r.status !== 'pending') return json('verification_expired');
    if (!r.currentProven) return refusal('current_number_not_proven');
    if (w.held.has(r.phone)) { r.status = 'failed'; return json('phone_unavailable'); }
    r.status = 'verified';
    w.grants.set(r.user, { digits: r.phone.slice(1), consumed: false });
    return json('granted');
  }
  throw new Error(`unexpected rpc ${name}`);
}

// ---------------------------------------------------------------------------
// Isolated fake provider (tests only)
// ---------------------------------------------------------------------------

function fakeProvider({ startError, checkError, verdict } = {}) {
  const p = {
    sent: [],
    checks: [],
    async start(phoneE164) {
      if (startError) throw startError;
      p.sent.push(phoneE164);
      return { ref: `VE${p.sent.length}` };
    },
    async check({ phoneE164, code, ref }) {
      p.checks.push({ phoneE164, code, ref });
      if (checkError) throw checkError;
      if (verdict) return verdict;
      return code === PROVIDER_CODE ? 'approved' : 'rejected';
    },
  };
  return p;
}

async function post(w, path, { auth, body, provider, raw } = {}) {
  const headers = { 'Content-Type': 'application/json', 'CF-Connecting-IP': '198.51.100.7' };
  if (auth) headers.Authorization = `Bearer ${auth}`;
  const request = new Request(`https://worker.test${path}`, {
    method: 'POST',
    headers,
    body: raw ?? JSON.stringify(body ?? {}),
  });
  const response = await handlePhoneVerificationRequest(request, ENV, {
    respond, fetchImpl: w.fetch, provider,
  });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

const rpcCalls = (w, name) => w.calls.filter((c) => c.path === `/rest/v1/rpc/${name}`);
const authCalls = (w, path) => w.calls.filter((c) => c.path.startsWith(path));

async function startedContact(w, provider, auth) {
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth, body: { phone: CONTACT }, provider });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.verificationId;
}

// ===========================================================================
// Provider selection
// ===========================================================================

test('no provider is configured in production: providerFromEnv returns null', () => {
  assert.equal(providerFromEnv({ ...ENV, ANY_PROVIDER_KEY: 'x' }), null);
});

test('without a provider every route answers 503 before writing anything', async () => {
  const w = makeWorld();
  const a = w.issue(ALICE, SESSION_A);
  const p = w.issue(PAT, SESSION_P);
  for (const [path, auth, body] of [
    [CONTACT_PHONE_START_PATH, a, { phone: CONTACT }],
    [CONTACT_PHONE_CONFIRM_PATH, a, { verificationId: '00000000-0000-4000-8000-000000000001', code: PROVIDER_CODE }],
    [PHONE_IDENTITY_START_PATH, p, { newPhone: NEW_NUMBER }],
    [PHONE_IDENTITY_CONFIRM_PATH, p, { verificationId: '00000000-0000-4000-8000-000000000001', newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }],
  ]) {
    const r = await post(w, path, { auth, body, provider: null });
    assert.equal(r.status, 503, path);
    assert.deepEqual(r.body, { error: 'verification_unavailable' });
  }
  assert.equal(w.count((c) => c.path.startsWith('/rest/v1/rpc/phone_') || c.path.startsWith('/rest/v1/rpc/contact_')), 0);
  assert.equal(authCalls(w, '/auth/v1/otp').length, 0);
});

test('other paths and methods are not handled here', async () => {
  const w = makeWorld();
  const request = new Request('https://worker.test/account/delete', { method: 'POST', body: '{}' });
  assert.equal(await handlePhoneVerificationRequest(request, ENV, { respond, fetchImpl: w.fetch }), null);
  const get = new Request(`https://worker.test${CONTACT_PHONE_START_PATH}`, { method: 'GET' });
  assert.equal(await handlePhoneVerificationRequest(get, ENV, { respond, fetchImpl: w.fetch }), null);
});

// ===========================================================================
// Unauthorized access (every route)
// ===========================================================================

test('no bearer token: 401 and nothing called', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { body: { phone: CONTACT }, provider });
  assert.equal(r.status, 401);
  assert.deepEqual(r.body, { error: 'session_expired' });
  assert.equal(w.calls.length, 0);
  assert.equal(provider.sent.length, 0);
});

test('a token Supabase Auth rejects: 401, no record, no SMS', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: token(ALICE, SESSION_A), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 401);
  assert.equal(rpcCalls(w, 'phone_verification_start').length, 0);
  assert.equal(provider.sent.length, 0);
});

test('a superseded session (Single Active Device) is refused before any SMS', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const old = w.issue(ALICE, SESSION_A_OLD, { current: false });
  for (const [path, body] of [
    [CONTACT_PHONE_START_PATH, { phone: CONTACT }],
    [CONTACT_PHONE_CONFIRM_PATH, { verificationId: '00000000-0000-4000-8000-000000000001', code: PROVIDER_CODE }],
  ]) {
    const r = await post(w, path, { auth: old, body, provider });
    assert.equal(r.status, 403);
    assert.deepEqual(r.body, { error: 'session_superseded' });
  }
  const oldPat = w.issue(PAT, 'bbbbbbbb-0000-4000-8000-000000000009', { current: false });
  const r = await post(w, PHONE_IDENTITY_START_PATH, { auth: oldPat, body: { newPhone: NEW_NUMBER }, provider });
  assert.equal(r.status, 403);
  assert.equal(provider.sent.length, 0);
  assert.equal(authCalls(w, '/auth/v1/otp').length, 0);
  assert.equal(w.count((c) => c.path.startsWith('/rest/v1/rpc/phone_')), 0);
});

test('the session check being unavailable never authorizes', async () => {
  const w = makeWorld({ sadUnavailable: true });
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 503);
  assert.deepEqual(r.body, { error: 'service_unavailable' });
  assert.equal(provider.sent.length, 0);
});

test('a password-recovery session is refused', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const t = w.issue(ALICE, SESSION_A, { amr: [{ method: 'recovery', timestamp: 1 }] });
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: t, body: { phone: CONTACT }, provider });
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: 'recovery_session' });
  assert.equal(provider.sent.length, 0);
});

test('a token without a session id is refused', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, undefined), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 401);
  assert.equal(provider.sent.length, 0);
});

test('missing server configuration: 503, nothing called', async () => {
  const w = makeWorld();
  const request = new Request(`https://worker.test${CONTACT_PHONE_START_PATH}`, {
    method: 'POST', headers: { Authorization: `Bearer ${w.issue(ALICE, SESSION_A)}` }, body: '{}',
  });
  const response = await handlePhoneVerificationRequest(request, { SUPABASE_URL }, { respond, fetchImpl: w.fetch, provider: fakeProvider() });
  assert.equal(response.status, 503);
  assert.equal(w.calls.length, 0);
});

// ===========================================================================
// Contact number (email account)
// ===========================================================================

test('contact number: start and confirm store a contact number and never touch Supabase Auth', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const start = await post(w, CONTACT_PHONE_START_PATH, { auth, body: { phone: CONTACT, userId: PAT }, provider });
  assert.equal(start.status, 200);
  assert.equal(start.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(provider.sent, [CONTACT]);
  const startArgs = rpcCalls(w, 'phone_verification_start')[0].body;
  assert.equal(startArgs.p_user, ALICE, 'the account comes from the verified token, never the body');
  assert.equal(startArgs.p_session, SESSION_A);
  assert.equal(startArgs.p_purpose, 'contact');
  assert.equal(rpcCalls(w, 'phone_verification_attach')[0].body.p_provider_ref, 'VE1');

  const confirm = await post(w, CONTACT_PHONE_CONFIRM_PATH, {
    auth, body: { verificationId: start.body.verificationId, code: PROVIDER_CODE }, provider,
  });
  assert.equal(confirm.status, 200);
  assert.deepEqual(confirm.body, { status: 'verified', phone: CONTACT });
  assert.deepEqual(provider.checks, [{ phoneE164: CONTACT, code: PROVIDER_CODE, ref: 'VE1' }]);
  assert.equal(w.contact[ALICE], CONTACT);
  // A provider code never grants Auth access and the number never reaches Auth.
  assert.equal(w.users[ALICE].phone, '');
  for (const path of ['/auth/v1/otp', '/auth/v1/verify', '/auth/v1/token', '/auth/v1/admin', '/auth/v1/logout']) {
    assert.equal(authCalls(w, path).length, 0, path);
  }
  assert.ok(!JSON.stringify(confirm.body).includes('token'));
});

test('contact number: only UAE mobile numbers, validated before any network beyond the caller check', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  for (const phone of ['971503333333', '+447700900123', '+97141234567', '+9715012345678', 123, '']) {
    const r = await post(w, CONTACT_PHONE_START_PATH, { auth, body: { phone }, provider });
    assert.equal(r.status, 400, String(phone));
    assert.deepEqual(r.body, { error: 'invalid_phone' });
  }
  const bad = await post(w, CONTACT_PHONE_START_PATH, { auth, raw: 'not json', provider });
  assert.deepEqual(bad.body, { error: 'invalid_request' });
  assert.equal(rpcCalls(w, 'phone_verification_start').length, 0);
  assert.equal(provider.sent.length, 0);
});

test('contact number: a number that belongs to another account is refused before any SMS', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { phone: '+971502222222' }, provider });
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: 'phone_unavailable' });
  assert.equal(provider.sent.length, 0);
});

test('contact number: a phone account has no contact-number flow', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(PAT, SESSION_P), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: 'not_available_for_account' });
  assert.equal(provider.sent.length, 0);
});

test('contact number: database rate limit -> 429, no SMS', async () => {
  const w = makeWorld({ startRefusal: 'too_many_requests' });
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 429);
  assert.deepEqual(r.body, { error: 'rate_limited' });
  assert.equal(provider.sent.length, 0);
});

test('contact number: provider failures close the record and map to fixed codes', async () => {
  for (const [kind, status, code] of [
    ['unavailable', 503, 'verification_unavailable'],
    ['rate_limited', 429, 'rate_limited'],
    ['invalid_number', 400, 'invalid_phone'],
  ]) {
    const w = makeWorld();
    const provider = fakeProvider({ startError: new VerificationProviderError(kind) });
    const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { phone: CONTACT }, provider });
    assert.equal(r.status, status, kind);
    assert.deepEqual(r.body, { error: code });
    assert.equal(rpcCalls(w, 'phone_verification_fail').length, 1);
    assert.equal([...w.records.values()][0].status, 'failed');
  }
  const w = makeWorld();
  const r = await post(w, CONTACT_PHONE_START_PATH, {
    auth: w.issue(ALICE, SESSION_A), body: { phone: CONTACT }, provider: fakeProvider({ startError: new Error('boom') }),
  });
  assert.equal(r.status, 503);
});

test('contact number: a wrong code keeps the record; the right code then succeeds', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, provider, auth);
  const wrong = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: '000000' }, provider });
  assert.equal(wrong.status, 422);
  assert.deepEqual(wrong.body, { error: 'invalid_code' });
  assert.equal(rpcCalls(w, 'contact_phone_confirm').length, 0);
  const right = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  assert.equal(right.status, 200);
  assert.equal(w.records.get(id).attempts, 2, 'every code was counted');
});

test('contact number: a malformed code is refused without asking the provider', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, provider, auth);
  for (const code of ['12', 'abcdef', '12345678901', 123456]) {
    const r = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code }, provider });
    assert.equal(r.status, 422, String(code));
  }
  const badId = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: 'x', code: PROVIDER_CODE }, provider });
  assert.equal(badId.status, 400);
  assert.equal(provider.checks.length, 0);
  assert.equal(rpcCalls(w, 'phone_verification_attempt').length, 0);
});

test('contact number: another session of the same account cannot complete the code', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const id = await startedContact(w, provider, w.issue(ALICE, SESSION_A));
  // The same account signs in elsewhere and that session becomes current.
  const other = w.issue(ALICE, SESSION_A_OLD);
  const r = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth: other, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: 'session_mismatch' });
  assert.equal(provider.checks.length, 0);
});

test('contact number: attempt cap and expiry are enforced before the provider is asked', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, provider, auth);
  w.records.get(id).attempts = 5;
  const capped = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  assert.equal(capped.status, 429);
  assert.deepEqual(capped.body, { error: 'too_many_attempts' });

  const id2 = await startedContact(w, provider, auth);
  w.records.get(id2).expired = true;
  const expired = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id2, code: PROVIDER_CODE }, provider });
  assert.equal(expired.status, 410);
  assert.equal(provider.checks.length, 0);
});

test('contact number: provider says expired -> record closed; provider down -> 503 and nothing stored', async () => {
  const w = makeWorld();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, fakeProvider(), auth);
  const expired = await post(w, CONTACT_PHONE_CONFIRM_PATH, {
    auth, body: { verificationId: id, code: PROVIDER_CODE }, provider: fakeProvider({ verdict: 'expired' }),
  });
  assert.equal(expired.status, 410);
  assert.equal(w.records.get(id).status, 'failed');

  const id2 = await startedContact(w, fakeProvider(), auth);
  const down = await post(w, CONTACT_PHONE_CONFIRM_PATH, {
    auth, body: { verificationId: id2, code: PROVIDER_CODE }, provider: fakeProvider({ checkError: new Error('timeout') }),
  });
  assert.equal(down.status, 503);
  assert.deepEqual(down.body, { error: 'verification_unavailable' });
  assert.equal(rpcCalls(w, 'contact_phone_confirm').length, 0);
  assert.equal(w.contact[ALICE], undefined);
});

test('contact number: a retry after a lost response is answered without a new code', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, provider, auth);
  await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  const again = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: '111111' }, provider });
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, { status: 'verified', phone: CONTACT });
  assert.equal(provider.checks.length, 1);
});

test('contact number: another account taking the number first wins the race', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(ALICE, SESSION_A);
  const id = await startedContact(w, provider, auth);
  w.held.add(CONTACT);
  const r = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: 'phone_unavailable' });
});

test('contact number: database unreachable -> 503, nothing sent', async () => {
  const w = makeWorld({ rpcDown: true });
  const provider = fakeProvider();
  const r = await post(w, CONTACT_PHONE_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { phone: CONTACT }, provider });
  assert.equal(r.status, 503);
  assert.equal(provider.sent.length, 0);
});

// ===========================================================================
// Sign-in number change (phone account)
// ===========================================================================

async function startedIdentity(w, provider, auth, body = { newPhone: NEW_NUMBER }) {
  const r = await post(w, PHONE_IDENTITY_START_PATH, { auth, body, provider });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.verificationId;
}

test('sign-in number change: the current number comes from the verified account, never the request', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  await startedIdentity(w, provider, auth, { newPhone: NEW_NUMBER, currentPhone: '971509999999' });
  const otp = authCalls(w, '/auth/v1/otp');
  assert.equal(otp.length, 1);
  assert.deepEqual(otp[0].body, { phone: PAT_PHONE, create_user: false });
  assert.equal(otp[0].headers['Sb-Forwarded-For'], '198.51.100.7');
  assert.deepEqual(provider.sent, [NEW_NUMBER]);
  assert.equal(rpcCalls(w, 'phone_verification_start')[0].body.p_purpose, 'identity_change');
});

test('sign-in number change: full flow proves both numbers, revokes the check session and writes through the Admin API', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.deepEqual(r.body, { status: 'changed', phone: NEW_NUMBER });
  const order = w.calls.map((c) => c.path).filter((p) => !p.startsWith('/auth/v1/user') && !p.includes('is_current_app_session'));
  const at = (p) => order.findIndex((x) => x.startsWith(p));
  assert.ok(at('/auth/v1/verify') < at('/auth/v1/logout?scope=local'));
  assert.ok(at('/auth/v1/logout?scope=local') < at('/rest/v1/rpc/phone_identity_current_proven'));
  assert.ok(at('/rest/v1/rpc/phone_identity_current_proven') < at('/rest/v1/rpc/phone_identity_change_grant'));
  assert.ok(at('/rest/v1/rpc/phone_identity_change_grant') < at('/auth/v1/admin/users/'));
  const verify = authCalls(w, '/auth/v1/verify')[0];
  assert.deepEqual(verify.body, { type: 'sms', phone: PAT_PHONE, token: SUPABASE_CODE });
  const revoke = authCalls(w, '/auth/v1/logout?scope=local')[0];
  assert.match(revoke.headers.Authorization, /^Bearer check-session-/);
  const admin = w.calls.find((c) => c.method === 'PUT');
  assert.deepEqual(admin.body, { phone: NEW_NUMBER.slice(1), phone_confirm: true });
  assert.equal(admin.headers.Authorization, undefined, 'the secret key travels only as apikey');
  assert.equal(w.users[PAT].phone, NEW_NUMBER.slice(1));
  assert.equal(authCalls(w, '/auth/v1/logout?scope=others').length, 1, 'other sessions are signed out');
  assert.ok(!JSON.stringify(r.body).includes('check-session'), 'no session is ever returned');
});

test('sign-in number change: a wrong current code stops everything', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: '999999' }, provider,
  });
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: 'current_proof_failed' });
  assert.equal(provider.checks.length, 0);
  assert.equal(rpcCalls(w, 'phone_identity_current_proven').length, 0);
  assert.equal(rpcCalls(w, 'phone_identity_change_grant').length, 0);
  assert.equal(w.users[PAT].phone, PAT_PHONE);
});

test('sign-in number change: if the check session cannot be revoked, nothing changes', async () => {
  const w = makeWorld({ revokeOk: false });
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 503);
  assert.equal(rpcCalls(w, 'phone_identity_current_proven').length, 0);
  assert.equal(w.calls.filter((c) => c.method === 'PUT').length, 0);
});

test('sign-in number change: a check session for another account is revoked and refused', async () => {
  const w = makeWorld({ verifyAs: ALICE });
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: 'account_mismatch' });
  assert.equal(authCalls(w, '/auth/v1/logout?scope=local').length, 1);
  assert.equal(w.calls.filter((c) => c.method === 'PUT').length, 0);
});

test('sign-in number change: a mistyped new code does not spend the current-number code again', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const first = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: '000000', currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(first.status, 422);
  assert.deepEqual(first.body, { error: 'invalid_code' });
  assert.equal(w.users[PAT].phone, PAT_PHONE);
  const second = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE }, provider,
  });
  assert.equal(second.status, 200, JSON.stringify(second.body));
  assert.equal(authCalls(w, '/auth/v1/verify').length, 1, 'the current number was proven once');
});

test('sign-in number change: the account password can prove the account instead of an SMS', async () => {
  const w = makeWorld();
  w.users[PAT].email = 'pat@example.test';
  w.users[PAT].identities.push({ provider: 'email' });
  w.passwords[PAT] = 'Correct-Horse-9';
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth, { newPhone: NEW_NUMBER, currentProof: 'password' });
  assert.equal(authCalls(w, '/auth/v1/otp').length, 0, 'no SMS to the current number');
  const wrong = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, password: 'wrong' }, provider,
  });
  assert.equal(wrong.status, 403);
  assert.deepEqual(wrong.body, { error: 'current_proof_failed' });
  const ok = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, password: 'Correct-Horse-9' }, provider,
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
});

test('sign-in number change: password proof is refused for an account without a password', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, PHONE_IDENTITY_START_PATH, {
    auth: w.issue(PAT, SESSION_P), body: { newPhone: NEW_NUMBER, currentProof: 'password' }, provider,
  });
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: 'reauthentication_unsupported' });
  assert.equal(provider.sent.length, 0);
});

test('sign-in number change: an email account cannot use it (no SMS of any kind)', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, PHONE_IDENTITY_START_PATH, { auth: w.issue(ALICE, SESSION_A), body: { newPhone: NEW_NUMBER }, provider });
  assert.equal(r.status, 409);
  assert.deepEqual(r.body, { error: 'not_available_for_account' });
  assert.equal(authCalls(w, '/auth/v1/otp').length, 0);
  assert.equal(provider.sent.length, 0);
});

test('sign-in number change: a number held by another account is refused before any SMS', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const r = await post(w, PHONE_IDENTITY_START_PATH, { auth: w.issue(PAT, SESSION_P), body: { newPhone: '+971502222222' }, provider });
  assert.equal(r.status, 409);
  assert.equal(authCalls(w, '/auth/v1/otp').length, 0);
  assert.equal(provider.sent.length, 0);
});

test('sign-in number change: Supabase refusing the current-number code closes the record', async () => {
  const w = makeWorld({ otpStatus: 429 });
  const provider = fakeProvider();
  const r = await post(w, PHONE_IDENTITY_START_PATH, { auth: w.issue(PAT, SESSION_P), body: { newPhone: NEW_NUMBER }, provider });
  assert.equal(r.status, 429);
  assert.equal(provider.sent.length, 0);
  assert.equal([...w.records.values()][0].status, 'failed');
});

test('sign-in number change: the number taken meanwhile -> 409 and no Admin write', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  w.held.add(NEW_NUMBER);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 409);
  assert.equal(w.calls.filter((c) => c.method === 'PUT').length, 0);
});

test('sign-in number change: an ambiguous Admin result is settled by reading the account back', async () => {
  const applied = makeWorld({ adminMode: 'fail-after-apply' });
  let provider = fakeProvider();
  let auth = applied.issue(PAT, SESSION_P);
  let id = await startedIdentity(applied, provider, auth);
  let r = await post(applied, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 200);

  const refused = makeWorld({ adminMode: 'fail' });
  provider = fakeProvider();
  auth = refused.issue(PAT, SESSION_P);
  id = await startedIdentity(refused, provider, auth);
  r = await post(refused, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 502);
  assert.deepEqual(r.body, { error: 'phone_change_failed' });
  assert.equal(refused.users[PAT].phone, PAT_PHONE);
  assert.equal(authCalls(refused, '/auth/v1/logout?scope=others').length, 0);
});

test('sign-in number change: an unexpected grant answer never reaches the Admin API', async () => {
  const w = makeWorld({ grantOverride: null });
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth, body: { verificationId: id, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 503);
  assert.equal(w.calls.filter((c) => c.method === 'PUT').length, 0);
});

test('contact route: a sign-in-number verification is refused before the provider is asked', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const auth = w.issue(PAT, SESSION_P);
  const id = await startedIdentity(w, provider, auth);
  const r = await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: PROVIDER_CODE }, provider });
  assert.equal(r.status, 404);
  assert.equal(provider.checks.length, 0);
  assert.equal(rpcCalls(w, 'contact_phone_confirm').length, 0);
});

test('sign-in number change: a contact verification id cannot be used to change a sign-in number', async () => {
  const w = makeWorld();
  const provider = fakeProvider();
  const contactId = await startedContact(w, provider, w.issue(ALICE, SESSION_A));
  // Pat cannot see Alice's record at all.
  const r = await post(w, PHONE_IDENTITY_CONFIRM_PATH, {
    auth: w.issue(PAT, SESSION_P), body: { verificationId: contactId, newCode: PROVIDER_CODE, currentCode: SUPABASE_CODE }, provider,
  });
  assert.equal(r.status, 404);
  assert.equal(w.calls.filter((c) => c.method === 'PUT').length, 0);
});

// ===========================================================================
// Wiring and isolation
// ===========================================================================

test('worker.js routes the four paths to this module, after the staging gate', () => {
  const source = readFileSync(new URL('../worker.js', import.meta.url), 'utf8');
  assert.match(source, /import \{ PHONE_VERIFICATION_PATHS, handlePhoneVerificationRequest \} from '\.\/phone_verification\.js';/);
  const gate = source.indexOf('stagingRequestAllowed(request, env)');
  const route = source.indexOf('PHONE_VERIFICATION_PATHS.includes(path)');
  assert.ok(gate > 0 && route > gate, 'the phone routes run behind the staging gate');
});

test('the module imports no package (its tests run without npm ci)', () => {
  const source = readFileSync(new URL('../phone_verification.js', import.meta.url), 'utf8');
  const imports = [...source.matchAll(/^import [\s\S]*? from '([^']+)';$/gm)].map((m) => m[1]);
  assert.deepEqual(imports.sort(), ['./account_deletion.js', './active_session.js']);
});

test('no phone number, code, token or provider reference is logged', async () => {
  const logged = [];
  const original = console.error;
  console.error = (...args) => logged.push(args.join(' '));
  try {
    const w = makeWorld();
    const provider = fakeProvider();
    const auth = w.issue(ALICE, SESSION_A);
    const id = await startedContact(w, provider, auth);
    await post(w, CONTACT_PHONE_CONFIRM_PATH, { auth, body: { verificationId: id, code: '000000' }, provider });
    await post(w, CONTACT_PHONE_START_PATH, { auth, body: { phone: '+971502222222' }, provider });
  } finally {
    console.error = original;
  }
  const text = logged.join('\n');
  assert.ok(logged.length >= 2);
  for (const secret of ['971503333333', '971502222222', '000000', 'VE1', ALICE, 'Bearer']) {
    assert.ok(!text.includes(secret), secret);
  }
});
