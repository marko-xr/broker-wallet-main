// Broker Wallet — offline self-test of the P4.3b pagination check. No network:
// the global fetch is replaced by one that throws, and every hosted step runs
// against an in-memory fake of Auth + PostgREST that follows the Single Active
// Device SQL (claim / is_current / release, permanent claim history) and the
// restrictive session gate. Faults are injected to prove each check can fail.
//
//   node p43_pagination_offline_selftest.mjs
//
// Node built-ins only.

import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  CONFIG_SOURCE, ConfigError, SERVICE_SOURCE, checkOrder, getOnly, keysetFilter, loadPagingContract,
  loadSupabaseConfig, microsOf, pageQuery, parseContentRange, rangeShape, sanitize,
} from './p43_pagination_readonly_checks.mjs';
import { ACCOUNT_A_UID, APPROVALS, loadRunConfig, run } from './p43_pagination_hosted_check.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

globalThis.fetch = async () => { throw new Error('REAL NETWORK ATTEMPTED'); };

let passed = 0;
const failures = [];
async function test(name, fn) {
  try {
    await fn();
    passed++;
  } catch (error) {
    failures.push(`${name}: ${error?.message}`);
  }
}
function assert(ok, message) {
  if (!ok) throw new Error(message);
}

// ---------------------------------------------------------------------------
// Fake hosted project
// ---------------------------------------------------------------------------

const URL_ = 'https://abcdefghijklmnop.supabase.co';
const KEY = 'sb_publishable_selftestKEY_000';
const TEST_UID = '1a1a1a1a-2b2b-4c3c-8d4d-5e5e5e5e5e5e';
const OTHER_UID = '99999999-8888-4777-8666-555555555555';
const EMAIL = 'p43-selftest@example.test';
const PASSWORD = 'Selftest-Password-123!';

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (claims) => `eyJ${b64({ alg: 'HS256' }).slice(3)}.${b64(claims)}.c2ln`;

/** PostgREST-like text: fraction trimmed of trailing zeros, "+00:00". */
function pgText(us) {
  const ms = Number(us / 1000n);
  const frac = String(us % 1000000n).padStart(6, '0').replace(/0+$/, '');
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, `${frac ? `.${frac}` : ''}+00:00`);
}

function makeRows(n, ownerId, { ties = true } = {}) {
  const rows = [];
  let us = 1_793_000_000_000_000n;
  for (let i = 0; i < n; i++) {
    if (!ties || i % 3 !== 0) us -= BigInt(1 + (i * 7919) % 1_000_003); // ties: every 3rd row shares a time
    rows.push({ id: randomUUID(), owner_id: ownerId, created_at: pgText(us), deleted_at: null, _us: us, name: `secret-row-${i}` });
  }
  return rows;
}

function fakeServer({ sizes, maxRows = null, faults = {} } = {}) {
  const tables = {};
  for (const [t, n] of Object.entries(sizes)) {
    tables[t] = [...makeRows(n, TEST_UID), ...makeRows(4, OTHER_UID),
      ...makeRows(2, TEST_UID).map((r) => ({ ...r, deleted_at: '2026-01-01T00:00:00+00:00' }))];
  }
  const sessions = new Map(); // session_id → uid
  const claims = new Set();
  let active = null; // { uid, session }
  const calls = [];
  const byText = new Map();
  for (const rows of Object.values(tables)) for (const r of rows) byText.set(r.created_at, r._us);
  byText.set('1970-01-01T00:00:00+00:00', 0n);

  const reply = (status, body, headers = {}) => new Response(body === undefined ? null : JSON.stringify(body),
    { status, headers: { 'content-type': 'application/json', ...headers } });
  const who = (init) => {
    const token = String(init.headers?.Authorization ?? '').replace(/^Bearer /, '');
    try {
      const c = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
      return sessions.has(c.session_id) ? { uid: c.sub, session: c.session_id } : null;
    } catch (_) { return null; }
  };
  const rowsVisible = (me) => (faults.gateRowsLeak ? Boolean(me) : current(me));
  const current = (me) => !faults.gateOff ? Boolean(me && active && active.uid === me.uid && active.session === me.session && sessions.has(me.session)) : true;

  async function fetchImpl(url, init = {}) {
    const u = new URL(url);
    const method = init.method ?? 'GET';
    calls.push({ method, path: u.pathname, search: u.search });
    if (u.origin !== URL_) return reply(404, { code: 'host' });
    if (init.headers?.apikey !== KEY) return reply(401, { code: 'key' });
    if (method === 'POST' && u.pathname === '/auth/v1/token') {
      const body = JSON.parse(init.body);
      if (faults.signInRefused || body.email !== EMAIL || body.password !== PASSWORD) return reply(400, { error_code: 'invalid_credentials' });
      const uid = faults.wrongAccount ? OTHER_UID : TEST_UID;
      const session = randomUUID();
      sessions.set(session, uid);
      return reply(200, { access_token: jwt({ sub: uid, role: 'authenticated', session_id: session }), refresh_token: 'refresh-secret-xyz', user: { id: uid } });
    }
    if (method === 'POST' && u.pathname === '/auth/v1/logout') {
      const me = who(init);
      if (me) sessions.delete(me.session);
      return new Response(null, { status: 204 });
    }
    const me = who(init);
    if (method === 'POST' && u.pathname === '/rest/v1/rpc/claim_current_app_session') {
      if (faults.claimBroken) return reply(500, { message: 'boom' });
      if (!me) return reply(401, { message: 'session_missing' });
      if (claims.has(me.session)) {
        if (faults.reclaimAllowed) { active = { uid: me.uid, session: me.session }; return reply(200, true); }
        return active?.session === me.session ? reply(200, true) : reply(403, { code: '42501', message: 'session_superseded' });
      }
      claims.add(me.session);
      active = { uid: me.uid, session: me.session };
      return reply(200, true);
    }
    if (method === 'POST' && u.pathname === '/rest/v1/rpc/is_current_app_session') return reply(200, faults.gateOff ? true : current(me));
    if (method === 'POST' && u.pathname === '/rest/v1/rpc/release_current_app_session') {
      const was = Boolean(me && active?.session === me.session);
      if (was) active = null;
      return reply(200, was);
    }
    const table = u.pathname.replace('/rest/v1/', '');
    if (method !== 'GET' || !tables[table]) return reply(404, { code: 'unexpected' });
    const q = u.searchParams;
    let rows = tables[table].filter((r) => me && (faults.rlsLeak || r.owner_id === me.uid));
    if (!rowsVisible(me)) rows = [];
    const owner = q.get('owner_id');
    if (owner && !faults.ownerFilterIgnored) rows = rows.filter((r) => `eq.${r.owner_id}` === owner);
    if (q.get('deleted_at') === 'is.null') rows = rows.filter((r) => r.deleted_at === null);
    rows.sort((a, b) => (a._us === b._us ? (a.id < b.id ? 1 : -1) : (a._us < b._us ? 1 : -1)));
    if (faults.misorder && rows.length > 3) [rows[1], rows[2]] = [rows[2], rows[1]];
    const or = q.get('or');
    if (or) {
      const m = /^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([0-9a-f-]{36})\)\)$/.exec(or);
      if (!m || m[1] !== m[2] || !byText.has(m[1])) return reply(400, { code: '22007' });
      const at = byText.get(m[1]);
      if (!faults.ignoreCursor) rows = rows.filter((r) => r._us < at || (r._us === at && r.id < m[3]));
      if (faults.skipAfterCursor && rows.length > 1) rows = rows.slice(1); // still in order, one row silently missing
      if (faults.repeatAcrossPages && rows.length) {
        const prev = tables[table].find((r) => r.id === m[3]);
        if (prev) rows = [prev, ...rows];
      }
    }
    const total = rows.length;
    let take = Number(q.get('limit') ?? total);
    if (maxRows !== null && take > maxRows) take = maxRows;
    const page = rows.slice(0, take).map(({ _us, ...r }) => r);
    if (faults.foreignRow && page.length && !or && take > 0) page[page.length - 1] = { ...page[page.length - 1], owner_id: OTHER_UID };
    const counting = String(init.headers?.Prefer ?? '').includes('count=exact');
    const range = page.length === 0 ? `*/${counting ? total : '*'}` : `0-${page.length - 1}/${counting ? total : '*'}`;
    const headers = faults.noContentRange ? {} : { 'content-range': range };
    return reply(page.length < total && counting ? 206 : 200, page, headers);
  }
  return { fetchImpl, calls, tables, claimsCount: () => claims.size, active: () => active };
}

const SIZES = { requests: 7, offers: 0, owners: 1, offices: 3, brokers: 1201, watchmen: 12 };

function testConfig(extra = {}) {
  return loadRunConfig({ BW_P43_EMAIL: EMAIL, BW_P43_PASSWORD: PASSWORD, BW_P43_TEST_USER_ID: TEST_UID, ...extra },
    { config: `'SUPABASE_URL',\n defaultValue: '${URL_}'\n'SUPABASE_PUBLISHABLE_KEY',\n defaultValue: '${KEY}'` });
}

async function runFake({ sizes = SIZES, maxRows = null, faults = {}, answers = [APPROVALS.signIn, APPROVALS.claim, APPROVALS.displace], env = { BW_P43_DISPLACEMENT: '1' } } = {}) {
  const server = fakeServer({ sizes, maxRows, faults });
  const lines = [];
  const asked = [];
  const queue = [...answers];
  const outcome = await run(testConfig(env), {
    fetchImpl: server.fetchImpl,
    ask: async (q) => { asked.push(q); lines.push(q); return queue.shift() ?? ''; },
    log: (l) => lines.push(l),
  });
  return { ...outcome, server, out: lines.join('\n'), asked };
}

const failed = (o, pattern) => o.results.some((r) => !r.ok && pattern.test(r.name));
const passedAll = (o) => o.results.every((r) => r.ok);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

await test('reads the real paging contract from the app source', () => {
  const c = loadPagingContract();
  assert(c.pageSize === 500 && c.maxPages === 40 && c.maxListRows === 20000, 'page contract');
  assert(c.columns.requests.includes('request_areas(area,ordinal)') && c.columns.offers.includes('offer_areas(area,ordinal)'), 'columns');
  assert(!/\s/.test(c.columns.requests), 'whitespace stripped like postgrest-dart');
  assert(['owners', 'offices', 'brokers', 'watchmen'].every((t) => c.columns[t] === '*'), 'star lists');
});

await test('reads the real Supabase URL and a publishable key from the app source', () => {
  const s = loadSupabaseConfig();
  assert(s.supabaseUrl.startsWith('https://') && s.publishableKey.startsWith('sb_publishable_'), 'config');
});

await test('refuses a changed paging contract', () => {
  const src = readFileSync(SERVICE_SOURCE, 'utf8');
  for (const broken of [
    src.replace(".order('id', ascending: false)", ''),
    src.replace("_wholeList('watchmen', '*',", "_oldRead('watchmen', '*',"),
    src.replace('static const int _pageSize = 500;', ''),
    src.replace("'and(created_at.eq.${after.at},id.lt.${after.id})'", "'id.lt.${after.id}'"),
  ]) {
    let threw = false;
    try { loadPagingContract(broken); } catch (e) { threw = e instanceof ConfigError; }
    assert(threw, 'a broken contract was accepted');
  }
  let threw = false;
  try { loadSupabaseConfig(readFileSync(CONFIG_SOURCE, 'utf8').replace('sb_publishable_', 'sb_secret_')); } catch (e) { threw = e instanceof ConfigError; }
  assert(threw, 'a secret key was accepted');
});

await test('timestamptz parsing (0–6 fraction digits, offsets, garbage)', () => {
  assert(microsOf('2026-11-03T12:34:56+00:00') === microsOf('2026-11-03T12:34:56.000000+00:00'), 'no fraction');
  assert(microsOf('2026-11-03T12:34:56.1+00:00') - microsOf('2026-11-03T12:34:56+00:00') === 100000n, '.1');
  assert(microsOf('2026-11-03T12:34:56.09+00:00') < microsOf('2026-11-03T12:34:56.1+00:00'), '.09 < .1 (string order would say otherwise)');
  assert(microsOf('2026-11-03T12:34:56.123456+00:00') - microsOf('2026-11-03T12:34:56.123455+00:00') === 1n, 'microsecond');
  assert(microsOf('2026-11-03T16:34:56+04:00') === microsOf('2026-11-03T12:34:56Z'), 'offset');
  assert(microsOf('2026-11-03 12:34:56+00:00') === null && microsOf('not-a-time') === null && microsOf(null) === null, 'garbage');
});

await test('Content-Range parsing and shapes', () => {
  assert(parseContentRange('0-499/1201').total === 1201 && rangeShape('0-499/1201') === 'a-b/T', 'a-b/T');
  assert(rangeShape('*/0') === '*/0' && parseContentRange('*/0').total === 0, '*/0');
  assert(rangeShape('0-1/*') === 'a-b/*' && parseContentRange('0-1/*').total === null, 'no count');
  assert(rangeShape(null) === 'absent' && rangeShape('bytes 0-1/2') === 'malformed', 'absent/malformed');
});

await test('order check: strict created_at DESC, id DESC, no repeats', () => {
  const a = { id: 'bbbbbbbb-0000-4000-8000-000000000000', created_at: '2026-11-03T12:00:00.5+00:00' };
  const b = { id: 'aaaaaaaa-0000-4000-8000-000000000000', created_at: '2026-11-03T12:00:00.5+00:00' };
  const c = { id: 'cccccccc-0000-4000-8000-000000000000', created_at: '2026-11-03T11:00:00+00:00' };
  assert(checkOrder([a, b, c]).ok, 'valid order with a tie');
  assert(!checkOrder([b, a, c]).ok, 'tie in id ASC accepted');
  assert(!checkOrder([c, a]).ok, 'older first accepted');
  assert(!checkOrder([a, a]).ok, 'repeat accepted');
  assert(!checkOrder([{ ...a, id: a.id.toUpperCase() }]).ok, 'uppercase id accepted');
  assert(!checkOrder([{ ...a, created_at: '2026-11-03 12:00:00' }]).ok, 'bad time accepted');
});

await test('page query matches the client: two-key order, limit, %2B-encoded raw cursor', () => {
  const q = pageQuery({ columns: 'id,owner_id', ownerId: TEST_UID, limit: 500, cursor: { rawAt: '2026-11-03T12:34:56.123456+00:00', id: OTHER_UID } });
  assert(q.includes('%2B00%3A00') && !q.includes('+00'), 'plus encoded');
  const p = new URLSearchParams(q);
  assert(p.get('order') === 'created_at.desc.nullslast,id.desc.nullslast' && p.get('limit') === '500', 'order/limit');
  assert(p.get('owner_id') === `eq.${TEST_UID}` && p.get('deleted_at') === 'is.null', 'filters');
  assert(p.get('or') === keysetFilter('2026-11-03T12:34:56.123456+00:00', OTHER_UID), 'keyset');
  assert(p.get('or') === `(created_at.lt.2026-11-03T12:34:56.123456+00:00,and(created_at.eq.2026-11-03T12:34:56.123456+00:00,id.lt.${OTHER_UID}))`, 'keyset text = client text');
});

await test('getOnly sends GET only, to the six tables only, without retry', async () => {
  const seen = [];
  const get = getOnly({ supabaseUrl: URL_, publishableKey: KEY, fetchImpl: async (u, init) => { seen.push(init.method); throw new Error('down'); } });
  const r = await get('requests', 'select=id', { accessToken: 't' });
  assert(r.status === 0 && r.error === 'network' && seen.length === 1 && seen[0] === 'GET', 'one GET, no retry');
  let threw = false;
  try { await get('user_active_sessions', 'select=*', { accessToken: 't' }); } catch (_) { threw = true; }
  assert(threw && seen.length === 1, 'non-list table refused before sending');
});

await test('run config: required values, account A refused, bounds', () => {
  const base = { BW_P43_EMAIL: EMAIL, BW_P43_PASSWORD: PASSWORD, BW_P43_TEST_USER_ID: TEST_UID };
  const bad = [
    { ...base, BW_P43_EMAIL: '' }, { ...base, BW_P43_PASSWORD: '' }, { ...base, BW_P43_TEST_USER_ID: '' },
    { ...base, BW_P43_TEST_USER_ID: TEST_UID.toUpperCase() }, { ...base, BW_P43_TEST_USER_ID: ACCOUNT_A_UID },
    { ...base, BW_P43_WALK_LIMIT: '0' }, { ...base, BW_P43_WALK_LIMIT: '11' }, { ...base, BW_P43_WALK_PAGES: 'x' },
  ];
  for (const env of bad) {
    let threw = false;
    try { loadRunConfig(env); } catch (e) { threw = e instanceof ConfigError; }
    assert(threw, `accepted ${Object.keys(env).find((k) => env[k] !== base[k]) ?? 'bad env'}`);
  }
  const ok = loadRunConfig(base);
  assert(ok.walkLimit === 2 && ok.maxWalkPages === 5 && ok.displacement === false && ok.contract.pageSize === 500, 'defaults');
});

await test('full fake run with displacement: every check passes and nothing secret is printed', async () => {
  const o = await runFake();
  assert(o.code === 0 && passedAll(o), `failures: ${o.results.filter((r) => !r.ok).map((r) => r.name).join('; ')}`);
  const signIns = o.server.calls.filter((c) => c.path === '/auth/v1/token').length;
  const logouts = o.server.calls.filter((c) => c.path === '/auth/v1/logout');
  assert(signIns === 2 && logouts.length === 2 && logouts.every((c) => c.search === '?scope=local'), 'two sign-ins, two local sign-outs');
  assert(o.server.active() === null && o.server.claimsCount() === 2, 'claim released; claim history kept (2 rows)');
  assert(o.server.calls.filter((c) => c.path.startsWith('/rest/v1/') && !c.path.startsWith('/rest/v1/rpc/')).every((c) => c.method === 'GET'), 'table calls are GET only');
  const secrets = [PASSWORD, EMAIL, TEST_UID, OTHER_UID, 'refresh-secret-xyz', 'eyJ', KEY, 'secret-row-'];
  for (const rows of Object.values(o.server.tables)) for (const r of rows) secrets.push(r.id, r.created_at);
  const leaked = secrets.filter((s) => o.out.includes(s) || JSON.stringify(o.results).includes(s) || JSON.stringify(o.facts).includes(s));
  assert(leaked.length === 0, `printed ${leaked.length} secret/identifying value(s)`);
  const brokers = o.facts.lists.find((f) => f.table === 'brokers');
  assert(brokers.total === 1201 && brokers.productionMultiPage === '3 pages, 1201 of 1201', 'production multi-page');
  const offers = o.facts.lists.find((f) => f.table === 'offers');
  assert(offers.total === 0 && offers.firstPageRows === 0, 'empty list');
  const requests = o.facts.lists.find((f) => f.table === 'requests');
  assert(requests.walked === 7 && requests.walkComplete && requests.productionMultiPage === 'not exercised', 'small walk complete, no multi-page claim');
  const watchmen = o.facts.lists.find((f) => f.table === 'watchmen');
  assert(watchmen.walked === 10 && !watchmen.walkComplete, 'walk bounded to 5 pages × 2');
});

await test('without displacement: one sign-in, S1 releases', async () => {
  const o = await runFake({ answers: [APPROVALS.signIn, APPROVALS.claim], env: {} });
  assert(o.code === 0 && passedAll(o), 'passes');
  assert(o.server.calls.filter((c) => c.path === '/auth/v1/token').length === 1 && o.server.active() === null, 'one sign-in, released');
  assert(!o.asked.some((q) => q.includes(APPROVALS.displace)), 'displacement not asked');
});

await test('declining SIGN IN sends nothing', async () => {
  const o = await runFake({ answers: ['sign in'] });
  assert(o.code === 3 && o.server.calls.length === 0, `sent ${o.server.calls.length}`);
});

await test('declining CLAIM: no claim, gate checked unclaimed, S1 signed out locally', async () => {
  const o = await runFake({ answers: [APPROVALS.signIn, 'no'] });
  const paths = o.server.calls.map((c) => c.path);
  assert(!paths.includes('/rest/v1/rpc/claim_current_app_session') && !paths.includes('/rest/v1/rpc/release_current_app_session'), 'no claim/release');
  assert(o.results.filter((r) => r.section === 'gate-unclaimed').every((r) => r.ok), 'gate closed while unclaimed');
  assert(o.server.calls.filter((c) => c.path === '/auth/v1/logout' && c.search === '?scope=local').length === 1 && o.code === 1, 'signed out; run reported as stopped');
});

await test('refused sign-in is not retried and nothing else is sent', async () => {
  const o = await runFake({ faults: { signInRefused: true } });
  assert(o.server.calls.length === 1 && o.code === 1, `calls ${o.server.calls.length}`);
  assert(o.out.includes('invalid_credentials') && !o.out.includes(PASSWORD), 'reason code only');
});

await test('a different signed-in account stops before any claim or list read', async () => {
  const o = await runFake({ faults: { wrongAccount: true } });
  const paths = o.server.calls.map((c) => c.path);
  assert(paths.filter((p) => p !== '/auth/v1/token' && p !== '/auth/v1/logout').length === 0, `sent ${paths.join(',')}`);
  assert(o.code === 1 && failed(o, /dedicated test account/), 'reported');
});

await test('a failed claim stops the run and still signs out', async () => {
  const o = await runFake({ faults: { claimBroken: true } });
  assert(o.code === 1 && failed(o, /S1 claimed/), 'claim failure reported');
  assert(!o.server.calls.some((c) => c.path === '/rest/v1/rpc/release_current_app_session'), 'nothing to release');
  assert(o.server.calls.some((c) => c.path === '/auth/v1/logout'), 'signed out');
  assert(o.server.calls.filter((c) => c.path === '/rest/v1/rpc/claim_current_app_session').length === 1, 'claim not retried');
});

await test('a server cap below the page size is observed and paging still completes', async () => {
  const o = await runFake({ maxRows: 300 });
  const brokers = o.facts.lists.find((f) => f.table === 'brokers');
  assert(brokers.serverCap === 'observed 300' && brokers.firstPageRows === 300, `cap ${brokers.serverCap}`);
  assert(brokers.productionMultiPage === '5 pages, 1201 of 1201' && passedAll(o), 'complete under the cap');
});

for (const [fault, pattern] of [
  ['misorder', /first page strictly/],
  ['ignoreCursor', /keyset walk|continues strictly/],
  ['repeatAcrossPages', /keyset walk|continues strictly/],
  ['rlsLeak', /without the owner filter/],
  ['noContentRange', /exact count present/],
  ['foreignRow', /belongs to the signed-in account/],
  ['gateOff', /gate closed|not the account's active session/],
  ['ownerFilterIgnored', /another owner id/],
  ['skipAfterCursor', /keyset walk \(limit/],
  ['gateRowsLeak', /gate closed/],
  ['reclaimAllowed', /refused a reclaim/],
]) {
  await test(`fault ${fault} is caught`, async () => {
    const o = await runFake({ faults: { [fault]: true } });
    assert(o.code === 1 && failed(o, pattern), `not caught; failures: ${o.results.filter((r) => !r.ok).map((r) => r.name).join('; ') || 'none'}`);
    assert(o.server.active() === null || fault === 'gateOff', 'cleanup released the claim');
  });
}

await test('sanitize hides urls, tokens, keys, uuids and times', () => {
  const s = sanitize(`x ${URL_}/a eyJa.b.c sb_publishable_abc ${TEST_UID} 2026-11-03T12:34:56.1+00:00`);
  assert(!s.includes('supabase.co') && !s.includes('eyJ') && !s.includes('sb_publishable') && !s.includes(TEST_UID) && !s.includes('2026-11'), s);
});

const script = join(HERE, 'p43_pagination_hosted_check.mjs');
const childEnv = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('BW_')));

await test('hosted "run" refuses without a terminal, before reading credentials', () => {
  const r = spawnSync(process.execPath, [script, 'run'], { input: `${APPROVALS.signIn}\n`, env: childEnv, encoding: 'utf8' });
  assert(r.status === 2 && /needs the owner at a terminal/.test(r.stderr), `exit ${r.status}`);
});

await test('"plan" prints the steps and sends nothing', () => {
  const r = spawnSync(process.execPath, [script, 'plan'], { env: childEnv, encoding: 'utf8' });
  assert(r.status === 0 && /no request was sent/.test(r.stdout) && /SIGN IN/.test(r.stdout) && /scope=local/.test(r.stdout), `exit ${r.status}`);
});

await test('unknown command is refused', () => {
  const r = spawnSync(process.execPath, [script], { env: childEnv, encoding: 'utf8' });
  assert(r.status === 2, `exit ${r.status}`);
});

console.log(`${failures.length === 0 ? 'OFFLINE SELFTEST PASSED' : 'OFFLINE SELFTEST FAILED'}: ${passed} passed, ${failures.length} failed`);
for (const f of failures) console.log(`  FAIL ${f}`);
process.exit(failures.length === 0 ? 0 : 1);
