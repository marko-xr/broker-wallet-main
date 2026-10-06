import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ActiveSessionUnavailable, isCurrentAppSession } from '../active_session.js';

const env = {
  SUPABASE_URL: 'https://project.supabase.test',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
};

test('uses the caller JWT and returns true only for the database true result', async () => {
  let calls = 0;
  const fetchImpl = async (url, init) => {
    calls++;
    assert.equal(url, `${env.SUPABASE_URL}/rest/v1/rpc/is_current_app_session`);
    assert.equal(init.method, 'POST');
    assert.equal(init.headers.Authorization, 'Bearer old-or-new-jwt');
    assert.equal(init.headers.apikey, env.SUPABASE_PUBLISHABLE_KEY);
    assert.deepEqual(JSON.parse(init.body), {});
    return new Response('true', { status: 200 });
  };
  assert.equal(await isCurrentAppSession('Bearer old-or-new-jwt', env, fetchImpl), true);
  assert.equal(calls, 1);
});

test('denies a displaced session and fails closed on unavailable answers', async () => {
  assert.equal(await isCurrentAppSession('Bearer jwt', env,
    async () => new Response('false', { status: 200 })), false);
  for (const response of [
    new Response('{}', { status: 200 }),
    new Response('true', { status: 403 }),
  ]) {
    await assert.rejects(
      isCurrentAppSession('Bearer jwt', env, async () => response),
      ActiveSessionUnavailable,
    );
  }
  await assert.rejects(
    isCurrentAppSession('Bearer jwt', env, async () => { throw Error('offline'); }),
    ActiveSessionUnavailable,
  );
});
