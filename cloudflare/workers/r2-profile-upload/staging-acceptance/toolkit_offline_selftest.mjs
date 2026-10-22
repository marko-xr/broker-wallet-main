// Offline self-test of toolkit_staging_acceptance.mjs. NO network, NO hosted system: the runner is driven
// against the REAL Worker code (worker.js + toolkit_documents.js, including the staging gate and the real
// presigner) with in-memory doubles for Supabase Auth, the session RPCs, PostgREST and R2 (the doubles from
// ../test/toolkit_fakes.mjs; the R2 PUT is a MODEL of its documented conditional-PutObject behavior).
//
// What this proves: the runner's logic, its stop conditions and its output discipline. What it does NOT prove:
// anything about real R2, real Supabase Auth or the deployed staging Worker — that is what the owner-run
// acceptance is for.
//
//   node staging-acceptance/toolkit_offline_selftest.mjs
//
// Not part of `npm test` (Node's default discovery does not match this file name).

import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import worker from '../worker.js';
import { ALICE, BOB, SECRET, makeState } from '../test/toolkit_fakes.mjs';
import {
  PUBLISHABLE_KEY, STAGING_BUCKET, STAGING_HEADER, SUPABASE_URL, WRITE_CONFIRMATION, assertStagingR2Url, loadConfig, makePdf, makePng, parsePhases, run, sanitize,
} from './toolkit_staging_acceptance.mjs';

const WORKER_URL = 'https://r2-profile-upload-staging.selftest.workers.dev';
const STAGING_KEY = 'selftest-staging-gate-key-value';
const A_EMAIL = 'owner-a@selftest.example';
const B_EMAIL = 'owner-b@selftest.example';
const A_PASSWORD = 'selftest-password-AAA';
const B_PASSWORD = 'selftest-password-BBB';
const R2_HOST = 'acct.r2.cloudflarestorage.com';

const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = (claims) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(claims)}.signature`;

/** A world: the real Worker + in-memory Supabase / R2, and a router that stands in for the network. */
function makeWorld({ r2 = 'model', verifySha = false, issuer = `${SUPABASE_URL}/auth/v1` } = {}) {
  const state = makeState({
    SUPABASE_URL, R2_BUCKET_NAME: STAGING_BUCKET, R2_S3_ENDPOINT: `https://${R2_HOST}`, STAGING_TEST_KEY: STAGING_KEY,
    TOOLKIT_DOCUMENT_SWEEP_MODE: 'off', ...(verifySha ? { TOOLKIT_DOC_VERIFY_SHA256: 'true' } : {}),
  });
  const users = new Map([[A_EMAIL, { id: ALICE, password: A_PASSWORD }], [B_EMAIL, { id: BOB, password: B_PASSWORD }]]);
  const sessionUser = new Map();
  const active = new Map();
  const displaced = new Set();
  const clientRequests = [];
  let counter = 0;
  const claimsOf = (headers) => {
    const token = (headers?.Authorization ?? '').replace(/^Bearer /, '');
    try { return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')); } catch (_) { return null; }
  };
  const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const keyOf = (url) => decodeURIComponent(new URL(url).pathname.split('/').slice(2).join('/'));

  async function router(input, init = {}) {
    const url = String(input);
    const parsed = new URL(url);
    if (parsed.host === new URL(SUPABASE_URL).host) {
      if (parsed.pathname === '/auth/v1/token') {
        const { email, password } = JSON.parse(init.body);
        const user = users.get(email);
        if (!user || user.password !== password) return json({ error_code: 'invalid_credentials' }, 400);
        counter += 1;
        const sessionId = `5e550000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
        sessionUser.set(sessionId, user.id);
        return json({ access_token: jwt({ iss: issuer, sub: user.id, role: 'authenticated', session_id: sessionId }), user: { id: user.id } });
      }
      if (parsed.pathname === '/auth/v1/user') {
        const claims = claimsOf(init.headers);
        return claims?.sub ? json({ id: claims.sub }) : json({}, 401);
      }
      if (parsed.pathname === '/rest/v1/rpc/claim_current_app_session' || parsed.pathname === '/rest/v1/rpc/is_current_app_session') {
        const claims = claimsOf(init.headers);
        if (!claims) return json({}, 401);
        if (parsed.pathname.endsWith('is_current_app_session')) return json(active.get(claims.sub) === claims.session_id);
        if (displaced.has(claims.session_id)) return json({ message: 'session_superseded' }, 400);
        const previous = active.get(claims.sub);
        if (previous && previous !== claims.session_id) displaced.add(previous);
        active.set(claims.sub, claims.session_id);
        return json(true);
      }
      const clientCall = init.headers?.apikey === PUBLISHABLE_KEY;
      if (clientCall && parsed.pathname.startsWith('/rest/v1/rpc/')) return json({ message: 'permission denied for function' }, 403);
      if (clientCall && parsed.pathname === '/rest/v1/toolkit_documents') {
        const method = init.method ?? 'GET';
        if (method !== 'GET') return json({ message: 'permission denied for table toolkit_documents' }, 403);
        const claims = claimsOf(init.headers);
        const select = (parsed.searchParams.get('select') ?? '').split(',');
        if (select.some((c) => ['object_key', 'bucket', 'observed_etag', 'discard_claimed_at', 'upload_attempts'].includes(c))) {
          return json({ message: 'permission denied for table toolkit_documents' }, 403);
        }
        const wanted = (parsed.searchParams.get('id') ?? '').replace(/^eq\./, '');
        if (active.get(claims?.sub) !== claims?.session_id) return json([]);
        return json(state.supabase.all().filter((r) => r.owner_id === claims.sub && r.status === 'ready' && (!wanted || r.id === wanted))
          .map((r) => Object.fromEntries(select.map((c) => [c, r[c]]))));
      }
      return state.supabase.fetch(url, init);
    }
    if (parsed.host === new URL(WORKER_URL).host) return worker.fetch(new Request(url, init), state.env, {});
    if (parsed.host === R2_HOST) {
      if ((init.method ?? 'GET') === 'PUT') {
        if (r2 === 'put500') return new Response('<Error><Code>InternalError</Code></Error>', { status: 500 });
        const headers = { ...(init.headers ?? {}) };
        const bytes = new Uint8Array(init.body);
        const contentType = headers['Content-Type'] ?? headers['content-type'] ?? 'application/octet-stream';
        let result;
        if (r2 === 'fail-open') {
          // A store that ignores If-None-Match: the security defect the runner must catch.
          state.bucket.put(keyOf(url), bytes, contentType, `"x${++counter}"`);
          result = { status: 200 };
        } else if (r2 === 'unsigned-header') {
          // Conditional works when sent, but a PUT without the header is accepted.
          const sent = Object.keys(headers).some((n) => n.toLowerCase() === 'if-none-match');
          if (!sent) { state.bucket.put(keyOf(url), bytes, contentType, `"y${++counter}"`); result = { status: 200 }; }
          else result = state.bucket.putViaSignedUrl(url, { headers, bytes, contentType });
        } else {
          result = state.bucket.putViaSignedUrl(url, { headers, bytes, contentType });
        }
        return new Response(result.status === 200 ? '' : `<Error><Code>${result.code}</Code></Error>`, { status: result.status });
      }
      const object = state.bucket.objects.get(keyOf(url));
      return object ? new Response(object.bytes, { status: 200, headers: { 'Content-Type': object.contentType } }) : new Response('<Error><Code>NoSuchKey</Code></Error>', { status: 404 });
    }
    throw new Error(`unexpected host in the self-test: ${parsed.host}`);
  }

  return {
    state, clientRequests, active, router,
    clientFetch: async (input, init = {}) => { clientRequests.push({ url: String(input), headers: init.headers ?? {}, method: init.method ?? 'GET' }); return router(input, init); },
  };
}

function configFor(overrides = {}) {
  return {
    workerUrl: WORKER_URL, stagingKey: STAGING_KEY, phases: parsePhases('ABCDE'),
    a: { email: A_EMAIL, password: A_PASSWORD, expectedUid: null }, b: { email: B_EMAIL, password: B_PASSWORD, expectedUid: null },
    reportPath: join(mkdtempSync(join(tmpdir(), 'toolkit-selftest-')), 'report.json'), ...overrides,
  };
}

async function runWorld(world, config, { ask } = {}) {
  const original = globalThis.fetch;
  globalThis.fetch = world.router; // the Worker's own outbound calls
  const lines = [];
  try {
    const code = await run(config, { fetchImpl: world.clientFetch, log: (line) => lines.push(String(line)), ask: ask ?? (async () => WRITE_CONFIRMATION) });
    return { code, lines, report: JSON.parse(readFileSync(config.reportPath, 'utf8')) };
  } finally {
    globalThis.fetch = original;
  }
}

test('generated PDF has valid xref offsets and PNG ancillary CRC matches data', () => {
  const pdf = makePdf('fixture-check', 'offline').toString('latin1');
  assert.ok(pdf.startsWith('%PDF-1.4\n'));
  const match = /startxref\n(\d+)\n%%EOF\n$/.exec(pdf);
  assert.ok(match, 'PDF startxref is present');
  const xref = Number(match[1]);
  assert.ok(pdf.slice(xref).startsWith('xref\n0 4\n'), 'startxref points to the xref table');
  const entries = pdf.slice(xref).split('\n').slice(3, 6);
  assert.equal(entries.length, 3);
  for (let i = 0; i < 3; i++) {
    const at = Number(entries[i].slice(0, 10));
    assert.ok(pdf.slice(at).startsWith(`${i + 1} 0 obj\n`), `xref entry ${i + 1}`);
  }

  const bytes = makePng(readFileSync(join(import.meta.dirname, 'fixtures', 'photo.png')), 'fixture-check');
  const crc32 = (buf) => {
    let crc = 0xffffffff;
    for (const byte of buf) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
  };
  let pos = 8;
  let foundText = false;
  while (pos + 12 <= bytes.length) {
    const len = bytes.readUInt32BE(pos);
    assert.ok(pos + len + 12 <= bytes.length, 'complete PNG chunk');
    const name = bytes.toString('latin1', pos + 4, pos + 8);
    const chunkBody = bytes.subarray(pos + 4, pos + 8 + len);
    assert.equal(bytes.readUInt32BE(pos + len + 8), crc32(chunkBody), `${name} chunk CRC`);
    if (name === 'tEXt') foundText = true;
    pos += len + 12;
  }
  assert.ok(foundText, 'contains an inserted text chunk');
  assert.equal(pos, bytes.length, 'all bytes belong to PNG chunks');
});

const HIDDEN = new Set(['pending_delete', 'deleted']);
const failures = (report) => report.results.filter((r) => r.ok === false).map((r) => `${r.section}: ${r.name}`);

test('all phases pass against the real Worker code, create only runner documents and remove every one', async () => {
  const world = makeWorld();
  const { code, report, lines } = await runWorld(world, configFor());
  assert.deepEqual(failures(report), []);
  assert.equal(code, 0, lines.slice(-6).join('\n'));
  const sections = new Set(report.results.map((r) => r.section));
  for (const s of ['setup', 'A', 'B', 'C', 'D', 'E', 'cleanup']) assert.ok(sections.has(s), s);
  assert.ok(report.passed >= 100, `only ${report.passed} checks`);
  const rows = world.state.supabase.all();
  assert.ok(rows.length >= 8, 'documents were created');
  // Right after an upload the Worker defers the tombstone until the signed-URL window has passed (sweep OFF):
  // the document is hidden from every read and its object is gone.
  assert.ok(rows.every((r) => HIDDEN.has(r.status)), 'every document the run created is removed (hidden from reads)');
  assert.deepEqual(world.state.bucket.objects.size, 0, 'no object is left in R2');
  const rpcs = new Set(world.state.supabase.rpcNames);
  assert.ok(!rpcs.has('claim_abandoned_toolkit_document') && !rpcs.has('discard_abandoned_toolkit_document') && !rpcs.has('list_toolkit_document_cleanup'), 'the sweep is never triggered');
  assert.equal(report.securityBlocker, false);
});

test('the PDF goes first and a failure there stops the run before JPEG and PNG', async () => {
  const world = makeWorld({ r2: 'put500' });
  const { code, report } = await runWorld(world, configFor({ phases: parsePhases('A') }));
  assert.notEqual(code, 0);
  assert.ok(failures(report).some((f) => f.includes('signed PUT')));
  const names = report.results.map((r) => r.name).join('\n');
  assert.ok(!/a-jpeg|a-png/.test(names), 'no other format was attempted');
  assert.deepEqual(world.state.supabase.all().map((r) => r.title).filter((t) => /a-jpeg|a-png/.test(t)), []);
  assert.ok(world.state.supabase.all().every((r) => HIDDEN.has(r.status)), 'what was created is removed');
});

test('digest verification ON is recognized: a wrong claim is refused and the flag is true', async () => {
  const world = makeWorld({ verifySha: true });
  const { code, report } = await runWorld(world, configFor({ phases: parsePhases('A') }));
  assert.equal(code, 0, failures(report).join('\n'));
  assert.ok(report.results.some((r) => /verification is ON/.test(r.name)));
});

test('digest verification OFF is recognized and sha256Verified is reported as a claim, not verification', async () => {
  const { report } = await runWorld(makeWorld(), configFor({ phases: parsePhases('A') }));
  assert.ok(report.results.some((r) => /verification is OFF/.test(r.name)));
  assert.ok(report.results.some((r) => /reflects Worker verification/.test(r.name) && r.ok === true));
});

test('SECURITY BLOCKER: a store that accepts an overwrite is caught, reported and cleaned up', async () => {
  for (const r2 of ['fail-open', 'unsigned-header']) {
    const world = makeWorld({ r2 });
    const { code, report } = await runWorld(world, configFor({ phases: parsePhases('B') }));
    assert.equal(code, 3, r2);
    assert.equal(report.securityBlocker, true, r2);
    assert.ok(failures(report).some((f) => /refused by R2|SECURITY BLOCKER/.test(f)), r2);
    assert.ok(world.state.supabase.all().every((x) => HIDDEN.has(x.status)), `${r2}: runner documents removed`);
  }
});

test('write-once is enforced and reported with the actual R2 answer, never an assumed code', async () => {
  const { report } = await runWorld(makeWorld(), configFor({ phases: parsePhases('B') }));
  assert.deepEqual(failures(report), []);
  assert.ok(report.results.some((r) => /R2's actual answer to the replay: HTTP 412/.test(r.name)));
});

test('nothing is created or PUT unless the second confirmation is typed exactly', async () => {
  for (const answer of ['', 'yes', 'create test documents']) {
    const world = makeWorld();
    const { code } = await runWorld(world, configFor(), { ask: async () => answer });
    assert.notEqual(code, 0);
    assert.equal(world.state.supabase.all().length, 0, `"${answer}": no document row`);
    assert.equal(world.state.bucket.objects.size, 0);
    assert.ok(!world.state.supabase.rpcNames.includes('authorize_toolkit_document_upload'));
  }
});

test('a token from another Supabase project is refused before any claim or write', async () => {
  const world = makeWorld({ issuer: 'https://someone-else.supabase.co/auth/v1' });
  const { code } = await runWorld(world, configFor());
  assert.notEqual(code, 0);
  assert.equal(world.active.size, 0, 'no session was claimed');
  assert.equal(world.state.supabase.all().length, 0);
});

test('an account that is not the expected one stops the run before any claim or write', async () => {
  const world = makeWorld();
  const config = configFor();
  config.b.expectedUid = '99999999-9999-4999-8999-999999999999';
  const { code } = await runWorld(world, config);
  assert.notEqual(code, 0);
  assert.equal(world.state.supabase.all().length, 0);
  assert.equal(world.active.size, 0);
});

test('output and report never contain a secret, token, e-mail, id, key or URL; the client never sends a secret key', async () => {
  const world = makeWorld();
  const { lines, report } = await runWorld(world, configFor());
  const text = `${lines.join('\n')}\n${JSON.stringify(report)}`;
  const forbidden = [A_EMAIL, B_EMAIL, A_PASSWORD, B_PASSWORD, STAGING_KEY, SECRET, PUBLISHABLE_KEY, 'eyJ', 'X-Amz', R2_HOST, 'profiles/', ALICE, BOB, 'presigned', 'https://'];
  for (const word of forbidden) assert.ok(!text.includes(word), `output contains ${word.slice(0, 12)}…`);
  assert.ok(!/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(text), 'output contains an id');
  for (const request of world.clientRequests) {
    const headers = Object.values(request.headers).map(String).join(' ');
    assert.ok(!headers.includes(SECRET), 'the runner never sends the service key');
    const apikey = request.headers.apikey;
    if (apikey !== undefined) assert.equal(apikey, PUBLISHABLE_KEY, 'only the publishable key is ever sent as apikey');
    const host = new URL(request.url).host;
    assert.ok([new URL(SUPABASE_URL).host, new URL(WORKER_URL).host, R2_HOST].includes(host), 'only staging hosts are contacted');
    if (host === R2_HOST) assert.ok(new URL(request.url).pathname.startsWith(`/${STAGING_BUCKET}/`), 'only the staging bucket is touched');
  }
  assert.equal(sanitize('a@b.example https://x.y/z profiles/u/k eyJaa.bb.cc 11111111-1111-4111-8111-111111111111'), '<email> <url> <key> <jwt> <id>');
});

test('the Worker URL must be the staging Worker; production, other hosts and weak settings are refused', () => {
  const base = {
    BW_E2E_WORKER_URL: WORKER_URL, BW_E2E_STAGING_KEY: 'k', BW_E2E_A_EMAIL: A_EMAIL, BW_E2E_A_PASSWORD: 'p', BW_E2E_B_EMAIL: B_EMAIL,
    BW_E2E_B_PASSWORD: 'p', BW_E2E_ACK_SESSION_CLAIM: '1', BW_E2E_PHASES: 'AB',
  };
  const attempt = (over) => {
    const errors = [];
    try {
      loadConfig({ ...base, ...over }, (code) => errors.push(code), (message) => errors.push(message));
    } catch (_) { /* the injected exit throws */ }
    return errors;
  };
  assert.deepEqual(attempt({}), [], 'a complete staging configuration is accepted');
  for (const url of ['https://r2-profile-upload.mohammed-developer-code.workers.dev', 'https://media-api.brokerwallet.ae', 'http://r2-profile-upload-staging.x.workers.dev',
    'https://r2-profile-upload-staging.x.workers.dev.evil.example', 'https://evil.example/r2-profile-upload-staging.x.workers.dev']) {
    assert.notDeepEqual(attempt({ BW_E2E_WORKER_URL: url }), [], url);
  }
  assert.notDeepEqual(attempt({ BW_E2E_ACK_SESSION_CLAIM: '' }), [], 'the session-claim acknowledgement is required');
  assert.notDeepEqual(attempt({ BW_E2E_B_EMAIL: A_EMAIL.toUpperCase() }), [], 'A and B must differ');
  assert.notDeepEqual(attempt({ BW_E2E_PHASES: 'AZ' }), [], 'unknown phase');
  assert.notDeepEqual(attempt({ BW_E2E_STAGING_KEY: '' }), [], 'the staging key is required');
  assert.deepEqual([...parsePhases('abd')].sort(), ['A', 'B', 'D']);
});

test('a signed URL is used only if it is the staging bucket\'s and this account\'s Toolkit prefix', () => {
  const session = { uid: ALICE };
  const ok = `https://${R2_HOST}/${STAGING_BUCKET}/profiles/${ALICE}/toolkit-documents/d.pdf?X-Amz-Signature=x`;
  assert.doesNotThrow(() => assertStagingR2Url(ok, session));
  for (const bad of [
    `https://${R2_HOST}/broker-wallet-media/profiles/${ALICE}/toolkit-documents/d.pdf`,
    `https://${R2_HOST}/${STAGING_BUCKET}/profiles/${BOB}/toolkit-documents/d.pdf`,
    `https://${R2_HOST}/${STAGING_BUCKET}/profiles/${ALICE}/offers/d.pdf`,
    `https://evil.example/${STAGING_BUCKET}/profiles/${ALICE}/toolkit-documents/d.pdf`,
    `http://${R2_HOST}/${STAGING_BUCKET}/profiles/${ALICE}/toolkit-documents/d.pdf`,
    'not a url',
  ]) assert.throws(() => assertStagingR2Url(bad, session), bad.slice(0, 40));
});

test('the staging gate header is sent to the Worker and a wrong key is refused by the real gate', async () => {
  const world = makeWorld();
  const response = await world.router(`${WORKER_URL}/toolkit-documents?limit=1`, { headers: { Authorization: 'Bearer x', [STAGING_HEADER]: 'wrong' } });
  assert.equal(response.status, 403);
  const none = await world.router(`${WORKER_URL}/toolkit-documents?limit=1`, { headers: { Authorization: 'Bearer x' } });
  assert.equal(none.status, 403);
});
