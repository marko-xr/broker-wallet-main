// Tests for the staging-only HTTP access gate and the configuration around it.
//
// worker.js imports aws4fetch, which is not installed in the repository, so its
// wiring is checked from source; the gate itself is exercised directly.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { STAGING_KEY_HEADER, constantTimeEqual, stagingRequestAllowed } from '../staging_gate.js';

const KEY = 'staging-test-key-0f3a9c1e-long-random-value';
const read = (relative) => readFileSync(fileURLToPath(new URL(relative, import.meta.url)), 'utf8').replace(/\r\n/g, '\n');

function request(headers = {}) {
  return new Request('https://r2-profile-upload-staging.example.workers.dev/account/delete', {
    method: 'POST',
    headers,
  });
}

test('staging: a missing key is refused', async () => {
  assert.equal(await stagingRequestAllowed(request(), { STAGING_TEST_KEY: KEY }), false);
});

test('staging: a wrong, empty, prefixed or extended key is refused', async () => {
  const env = { STAGING_TEST_KEY: KEY };
  // (Surrounding whitespace is not a case: the Fetch Headers API strips it from
  // every header value before any code sees it.)
  for (const value of ['wrong', '', KEY.slice(0, -1), `${KEY}x`, KEY.toUpperCase(), `x${KEY}`]) {
    assert.equal(await stagingRequestAllowed(request({ [STAGING_KEY_HEADER]: value }), env), false, JSON.stringify(value));
  }
});

test('staging: the correct key is allowed through to endpoint logic', async () => {
  assert.equal(await stagingRequestAllowed(request({ [STAGING_KEY_HEADER]: KEY }), { STAGING_TEST_KEY: KEY }), true);
});

test('staging: the key is a separate layer — the user Authorization header does not satisfy it', async () => {
  const env = { STAGING_TEST_KEY: KEY };
  assert.equal(await stagingRequestAllowed(request({ Authorization: `Bearer ${KEY}` }), env), false);
});

test('staging: a bound but empty key fails closed for every request', async () => {
  for (const value of ['', KEY]) {
    assert.equal(await stagingRequestAllowed(request({ [STAGING_KEY_HEADER]: value }), { STAGING_TEST_KEY: '' }), false);
  }
});

test('production: with no STAGING_TEST_KEY bound, every request proceeds unchanged', async () => {
  for (const env of [{}, { STAGING_TEST_KEY: undefined }, { R2_BUCKET_NAME: 'broker-wallet-media' }]) {
    assert.equal(await stagingRequestAllowed(request(), env), true);
    assert.equal(await stagingRequestAllowed(request({ [STAGING_KEY_HEADER]: 'anything' }), env), true);
  }
});

test('the comparison is exact', async () => {
  assert.equal(await constantTimeEqual(KEY, KEY), true);
  assert.equal(await constantTimeEqual(KEY, `${KEY} `), false);
  assert.equal(await constantTimeEqual('', ''), true);
});

test('the gate never logs or returns the key', () => {
  const source = read('../staging_gate.js');
  assert.equal(/console\./.test(source), false);
  const worker = read('../worker.js');
  const gateBlock = worker.slice(worker.indexOf('stagingRequestAllowed(request, env)'), worker.indexOf('const path = new URL'));
  assert.match(gateBlock, /corsResponse\(\{ error: 'Forbidden' \}, 403, env\)/);
  assert.equal(gateBlock.includes('STAGING_TEST_KEY'), false);
});

test('worker.js runs the gate before any route, Supabase, R2 or account logic', () => {
  const worker = read('../worker.js');
  const fetchBody = worker.slice(worker.indexOf('async fetch(request, env, ctx)'), worker.indexOf('async scheduled('));
  const gate = fetchBody.indexOf('await stagingRequestAllowed(request, env)');
  assert.ok(gate > 0);
  for (const later of ['ACCOUNT_DELETE_PATH', 'handleAccountDeletion', "'/authorize'", "'/confirm'", "'/profile-image-url'"]) {
    assert.ok(fetchBody.indexOf(later) > gate, `${later} must come after the gate`);
  }
  // Only a CORS preflight is answered before it.
  const beforeGate = fetchBody.slice(0, gate);
  assert.match(beforeGate, /request\.method === 'OPTIONS'\) return corsResponse\(null, 204, env\)/);
  assert.equal((beforeGate.match(/return /g) ?? []).length, 1);
  // Cron is not an HTTP request and is not gated.
  const scheduled = worker.slice(worker.indexOf('async scheduled('));
  assert.equal(scheduled.slice(0, scheduled.indexOf('},')).includes('stagingRequestAllowed'), false);
});

test('STAGING_TEST_KEY is required by staging only, never by production', () => {
  // Configuration only; comments are allowed to mention the staging key.
  const toml = read('../wrangler.toml')
    .split('\n')
    .filter((line) => !line.trim().startsWith('#'))
    .join('\n');
  const stagingStart = toml.indexOf('[env.staging]');
  assert.ok(stagingStart > 0);
  const production = toml.slice(0, stagingStart);
  const staging = toml.slice(stagingStart);

  assert.equal(production.includes('STAGING_TEST_KEY'), false);
  const productionSecrets = production.slice(production.indexOf('[secrets]'));
  for (const name of ['SUPABASE_SECRET_KEY', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY']) {
    assert.ok(productionSecrets.includes(`"${name}"`), name);
  }

  const stagingSecrets = staging.slice(staging.indexOf('[env.staging.secrets]'));
  const required = [...stagingSecrets.matchAll(/"([A-Z0-9_]+)"/g)].map((match) => match[1]);
  assert.deepEqual(required, ['SUPABASE_SECRET_KEY', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'STAGING_TEST_KEY']);

  assert.match(staging, /bucket_name = "broker-wallet-media-staging"/);
  assert.match(staging, /R2_BUCKET_NAME = "broker-wallet-media-staging"/);
  assert.match(staging, /workers_dev = true/);
  assert.equal(/\broutes?\s*=/.test(toml), false, 'no route in any environment');
  assert.equal(/custom_domain/.test(toml), false);
});

test('the bootstrap placeholder can do nothing', () => {
  const placeholder = read('../staging-bootstrap/placeholder.js');
  const code = placeholder
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  for (const forbidden of ['await', 'env', 'SUPABASE', 'R2', 'import ', 'scheduled', 'http', 'crypto']) {
    assert.equal(code.includes(forbidden), false, forbidden);
  }
  // Its only handler takes no arguments, so it cannot read a request or a binding.
  assert.match(code, /async fetch\(\) \{\n\s+return new Response\(null, \{ status: 404 \}\);\n\s+\},/);

  const config = read('../staging-bootstrap/wrangler.toml')
    .split('\n')
    .filter((line) => !line.trim().startsWith('#'))
    .join('\n');
  assert.match(config, /^name = "r2-profile-upload-staging"$/m);
  assert.match(config, /^workers_dev = false$/m);
  for (const forbidden of ['[triggers]', 'r2_buckets', '[vars]', 'secrets', 'route']) {
    assert.equal(config.includes(forbidden), false, forbidden);
  }
});
