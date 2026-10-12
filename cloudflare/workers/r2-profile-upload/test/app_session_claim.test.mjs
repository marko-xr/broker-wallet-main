import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  AppSessionClaimError,
  CHECK_RPC,
  CLAIM_RPC,
  claimAndVerifyAppSession,
  claimAppSession,
  claimSessionForRun,
  isAppSessionCurrent,
  sessionIdFromAccessToken,
  sessionTag,
} from '../staging-acceptance/app_session_claim.mjs';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE_KEY = 'sb_publishable_test';
const SESSION_ID = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

function jwt(claims) {
  const part = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${part({ alg: 'HS256', typ: 'JWT' })}.${part(claims)}.signature-not-checked`;
}
const userToken = (claims = {}) => jwt({ sub: 'user', role: 'authenticated', session_id: SESSION_ID, ...claims });
const args = (extra = {}) => ({
  supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, accessToken: userToken(), ...extra,
});
const reply = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});

test('reads the session id only from a well-formed claim', () => {
  assert.equal(sessionIdFromAccessToken(userToken()), SESSION_ID);
  for (const bad of [
    'not-a-jwt', 'a.b', 'a.b.c.d', 'a.%%%.c', '',
    jwt({ role: 'authenticated' }), jwt({ session_id: 'not-a-uuid' }), jwt({ session_id: 42 }),
  ]) {
    assert.equal(sessionIdFromAccessToken(bad), null, String(bad));
  }
});

test('the session tag is short, stable and tells two sessions apart', () => {
  const tag = sessionTag(SESSION_ID);
  assert.match(tag, /^[0-9a-f]{8}$/);
  assert.equal(sessionTag(SESSION_ID), tag);
  assert.notEqual(sessionTag('1a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'), tag);
});

test('claims through the existing RPC with the caller token and no client identity', async () => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, init });
    return reply(true);
  };
  const out = await claimAppSession(args({ fetchImpl }));
  assert.deepEqual(out, { sessionTag: sessionTag(SESSION_ID) });
  assert.equal(CLAIM_RPC, '/rest/v1/rpc/claim_current_app_session');
  assert.equal(seen.length, 1);
  assert.equal(seen[0].url, `${SUPABASE_URL}${CLAIM_RPC}`);
  assert.equal(seen[0].init.method, 'POST');
  assert.equal(seen[0].init.headers.apikey, PUBLISHABLE_KEY);
  assert.equal(seen[0].init.headers.Authorization, `Bearer ${userToken()}`);
  assert.deepEqual(JSON.parse(seen[0].init.body), {});
});

test('maps every refusal to a fixed code without echoing the response', async () => {
  const cases = [
    [reply({ code: '42501', message: 'session_superseded' }, 403), 'session_superseded', 403],
    [reply({ code: '42501', message: 'session_missing' }, 403), 'session_missing', 403],
    [reply({ message: 'Could not find the function' }, 404), 'function_missing', 404],
    [reply({ message: 'JWT expired' }, 401), 'rejected', 401],
    [reply({ message: 'boom' }, 503), 'unavailable', 503],
    [reply(false), 'unexpected_answer', 200],
    [reply({ ok: true }), 'unexpected_answer', 200],
  ];
  for (const [response, code, status] of cases) {
    await assert.rejects(claimAppSession(args({ fetchImpl: async () => response })), (error) => {
      assert.ok(error instanceof AppSessionClaimError);
      assert.equal(error.code, code);
      assert.equal(error.status, status);
      assert.ok(!error.message.includes(userToken()) && !error.message.includes(SESSION_ID));
      return true;
    });
  }
  await assert.rejects(
    claimAppSession(args({ fetchImpl: async () => { throw new Error('offline'); } })),
    (error) => error instanceof AppSessionClaimError && error.code === 'unavailable' && error.status === null,
  );
});

test('refuses anything that is not a user session before any request is sent', async () => {
  let sent = 0;
  const fetchImpl = async () => {
    sent += 1;
    return reply(true);
  };
  const attempts = [
    [{ publishableKey: 'sb_secret_service' }, 'not_a_publishable_key'],
    [{ publishableKey: 'eyJhbGciOiJIUzI1NiJ9.legacy.key' }, 'not_a_publishable_key'],
    [{ accessToken: jwt({ role: 'service_role', session_id: SESSION_ID }) }, 'not_a_user_session'],
    [{ accessToken: jwt({ role: 'anon', session_id: SESSION_ID }) }, 'not_a_user_session'],
    [{ accessToken: 'not-a-jwt' }, 'not_a_user_session'],
    [{ accessToken: jwt({ role: 'authenticated' }) }, 'no_session_id'],
    [{ accessToken: jwt({ role: 'authenticated', session_id: 'x' }) }, 'no_session_id'],
    [{ supabaseUrl: 'http://project.supabase.test' }, 'insecure_url'],
  ];
  for (const [override, code] of attempts) {
    for (const call of [claimAppSession, isAppSessionCurrent, claimAndVerifyAppSession]) {
      await assert.rejects(
        call(args({ ...override, fetchImpl })),
        (error) => error instanceof AppSessionClaimError && error.code === code,
        `${call.name} ${code}`,
      );
    }
  }
  assert.equal(sent, 0);
});

test("verifies the claim with the Worker's own check and fails closed", async () => {
  const paths = [];
  const answering = (answers) => async (url) => {
    paths.push(new URL(url).pathname);
    return reply(answers.shift());
  };
  const out = await claimAndVerifyAppSession(args({ fetchImpl: answering([true, true]) }));
  assert.equal(out.sessionTag, sessionTag(SESSION_ID));
  assert.equal(CHECK_RPC, '/rest/v1/rpc/is_current_app_session');
  assert.deepEqual(paths, [CLAIM_RPC, CHECK_RPC]);

  await assert.rejects(
    claimAndVerifyAppSession(args({ fetchImpl: answering([true, false]) })),
    (error) => error instanceof AppSessionClaimError && error.code === 'not_current',
  );
  await assert.rejects(
    claimAndVerifyAppSession(args({ fetchImpl: answering([false]) })),
    (error) => error instanceof AppSessionClaimError && error.code === 'unexpected_answer',
  );
});

test('the check returns the database boolean and refuses any other answer', async () => {
  assert.equal(await isAppSessionCurrent(args({ fetchImpl: async () => reply(true) })), true);
  assert.equal(await isAppSessionCurrent(args({ fetchImpl: async () => reply(false) })), false);
  for (const response of [reply({}), reply('yes'), reply(null), reply(true, 403)]) {
    await assert.rejects(
      isAppSessionCurrent(args({ fetchImpl: async () => response })),
      AppSessionClaimError,
    );
  }
});

test("the run step records the outcome and stops the run with the runner's own error", async () => {
  class FatalError extends Error {}
  const checks = [];
  const check = (section, name, ok, detail = '') => {
    checks.push({ section, name, ok, detail });
    return ok;
  };
  const base = { supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, check, FatalError };

  const session = { label: 'A', token: userToken() };
  const tag = await claimSessionForRun({ ...base, session, fetchImpl: async () => reply(true) });
  assert.equal(tag, sessionTag(SESSION_ID));
  assert.equal(session.tag, tag);
  assert.equal(checks.length, 1);
  assert.equal(checks[0].ok, true);
  assert.ok(checks[0].name.includes(tag));
  assert.ok(!checks[0].name.includes(SESSION_ID) && !checks[0].name.includes(session.token));

  const refused = { label: 'B', token: userToken() };
  await assert.rejects(
    claimSessionForRun({
      ...base, session: refused, fetchImpl: async () => reply({ message: 'session_superseded' }, 403),
    }),
    (error) => error instanceof FatalError && error.message.includes('session_superseded') &&
      !error.message.includes(refused.token),
  );
  assert.equal(checks.length, 2);
  assert.equal(checks[1].ok, false);
  assert.equal(refused.tag, undefined);
});
