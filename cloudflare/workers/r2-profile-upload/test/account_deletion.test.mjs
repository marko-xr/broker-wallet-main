// Behavioural tests for account deletion: POST /account/delete, the upload
// quarantine used by POST /authorize, and the scheduled finalizer.
//
// Run with: npm test   (or a bare `node --test` from this directory)
//
// Supabase Auth, PostgREST (including the account_deletion_jobs table) and the
// R2 binding are in-memory fakes that record every call and share one clock,
// so each test can assert what did and did not happen, and when.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ABANDONED_JOB_AFTER_MS,
  CLEANUP_WINDOW_MS,
  FINALIZER_SAFETY_MARGIN_MS,
  MAX_SIGNING_DELAY_MS,
  PENDING_RECONCILE_AFTER_MS,
  SIGNED_PUT_TTL_SECONDS,
  assertPresignedWithin,
  assertUploadsAllowed,
  handleAccountDeletion,
  runDeletionFinalizer,
} from '../account_deletion.js';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE = 'sb_publishable_test';
const SECRET = 'sb_secret_TEST_SECRET_VALUE';
const BUCKET = 'broker-wallet-media';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
const PASSWORD = 'Correct-Horse-9';

const PUT_TTL_MS = SIGNED_PUT_TTL_SECONDS * 1000;
const START = Date.parse('2026-09-13T08:00:00Z');
const EMPTY_SUMMARY = { finalized: 0, cleanupFailed: 0, stamped: 0, reconciled: 0, cancelled: 0 };

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function token(sub, amr = [{ method: 'password', timestamp: 1 }]) {
  return `${base64Url({ alg: 'HS256' })}.${base64Url({ sub, amr })}.signature`;
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

function amzDate(ms) {
  return new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

function presigned(key, signedAtMs) {
  return `https://r2.test/${BUCKET}/${key}?X-Amz-Expires=300&X-Amz-Date=${amzDate(signedAtMs)}&X-Amz-Signature=abc`;
}

class Clock {
  constructor(ms = START) {
    this.ms = ms;
  }
  now = () => new Date(this.ms);
  advance(ms) {
    this.ms += ms;
  }
}

class FakeBucket {
  constructor(keys = []) {
    this.objects = new Set(keys);
    this.sticky = new Set();
    this.failDeletes = false;
    this.failLists = false;
    this.deleteCalls = [];
    this.listCalls = 0;
  }

  async list({ prefix, cursor, limit }) {
    this.listCalls += 1;
    if (this.failLists) throw new Error('R2 unavailable');
    const all = [...this.objects].filter((key) => key.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0;
    const page = all.slice(start, start + limit);
    const next = start + page.length;
    return {
      objects: page.map((key) => ({ key })),
      truncated: next < all.length,
      cursor: next < all.length ? String(next) : undefined,
    };
  }

  async delete(keys) {
    const list = Array.isArray(keys) ? keys : [keys];
    this.deleteCalls.push(list);
    this.onDelete?.();
    if (this.failDeletes) throw new Error('R2 unavailable');
    for (const key of list) {
      if (!this.sticky.has(key)) this.objects.delete(key);
    }
  }
}

/** Matches a PostgREST filter value such as `eq.x`, `in.(a,b)` or `lte.<iso>`. */
function matches(rowValue, filter) {
  const dot = filter.indexOf('.');
  const op = filter.slice(0, dot);
  const operand = filter.slice(dot + 1);
  if (op === 'eq') return String(rowValue) === operand;
  if (op === 'in') return operand.slice(1, -1).split(',').includes(String(rowValue));
  if (op === 'lte') return rowValue !== null && Date.parse(rowValue) <= Date.parse(operand);
  if (op === 'is' && operand === 'null') return rowValue === null || rowValue === undefined;
  throw new Error(`unsupported filter ${filter}`);
}

const RESERVED_PARAMS = new Set(['select', 'order', 'limit', 'offset', 'on_conflict']);

function filterRows(rows, searchParams) {
  return rows.filter((row) =>
    [...searchParams.entries()].every(([column, filter]) => RESERVED_PARAMS.has(column) || matches(row[column], filter)),
  );
}

/** An in-memory Supabase answering exactly the requests the Worker makes. */
class FakeSupabase {
  constructor(clock) {
    this.clock = clock;
    this.users = new Map([
      [ALICE, { id: ALICE, email: 'alice@example.test', identities: [{ provider: 'email' }] }],
      [BOB, { id: BOB, email: 'bob@example.test', identities: [{ provider: 'email' }] }],
    ]);
    this.passwords = new Map([
      ['alice@example.test', { password: PASSWORD, userId: ALICE }],
      ['bob@example.test', { password: 'Bob-Password-1', userId: BOB }],
    ]);
    this.validTokens = new Set();
    this.media = [];
    this.jobs = [];
    this.calls = [];
    this.adminDeleteBehaviour = 'normal'; // normal | fail | throw | throw-after-delete
    this.adminGetBehaviour = 'normal'; // normal | fail
    this.jobsUnavailable = false;
    this.passwordStatus = null;
    this.passwordGrantUserOverride = null;
    this.beforeAdminDelete = null;
  }

  issue(userId, amr) {
    const value = token(userId, amr);
    this.validTokens.add(value);
    return value;
  }

  job(userId) {
    return this.jobs.find((row) => row.user_id === userId) ?? null;
  }

  insertJob(fields) {
    const at = this.clock.now().toISOString();
    const row = {
      bucket: BUCKET,
      status: 'quarantined',
      created_at: at,
      updated_at: at,
      auth_deleted_at: null,
      cleanup_not_before: null,
      cleanup_attempts: 0,
      last_error_code: null,
      ...fields,
    };
    this.assertJobConstraints(row);
    this.jobs.push(row);
    return row;
  }

  // Mirrors the migration's CHECK constraints and NOT NULL columns.
  assertJobConstraints(row) {
    const valid = ['quarantined', 'auth_delete_pending', 'auth_deleted', 'cleanup_failed'];
    assert.ok(typeof row.bucket === 'string' && row.bucket.trim() !== '', 'bucket constraint');
    assert.ok(valid.includes(row.status), `status constraint: ${row.status}`);
    const deleted = row.status === 'auth_deleted' || row.status === 'cleanup_failed';
    assert.equal(deleted, row.auth_deleted_at !== null, `auth_deleted_at constraint for ${row.status}`);
    assert.ok(row.cleanup_not_before === null || deleted, 'stamp only after auth delete');
    assert.ok(
      row.cleanup_not_before === null || Date.parse(row.cleanup_not_before) >= Date.parse(row.created_at),
      'stamp sanity constraint',
    );
  }

  fetch = async (url, init = {}) => {
    const parsed = new URL(url);
    const method = init.method ?? 'GET';
    const headers = init.headers ?? {};
    this.calls.push({ method, path: parsed.pathname, search: parsed.search, headers, body: init.body });

    // Current Supabase API-key semantics: a secret key travels only in `apikey`.
    for (const value of Object.values(headers)) {
      if (value !== headers.apikey) {
        assert.equal(String(value).includes('sb_secret_'), false, 'secret key outside the apikey header');
      }
    }
    if (headers.apikey === SECRET) {
      assert.equal(headers.Authorization, undefined, 'no Authorization header on secret-key calls');
    }
    if (headers.Authorization) {
      assert.equal(headers.apikey, PUBLISHABLE, 'a user JWT is paired with the publishable key');
    }

    if (parsed.pathname === '/auth/v1/user') {
      const bearer = (headers.Authorization ?? '').slice('Bearer '.length);
      if (!this.validTokens.has(bearer)) return json({ error_code: 'bad_jwt' }, 403);
      const sub = JSON.parse(Buffer.from(bearer.split('.')[1], 'base64url').toString()).sub;
      const user = this.users.get(sub);
      if (!user) return json({ error_code: 'user_not_found' }, 403);
      return json(user);
    }

    if (parsed.pathname === '/auth/v1/token') {
      assert.equal(headers.apikey, PUBLISHABLE);
      if (this.passwordStatus) return json({ error_code: 'over_request_rate_limit' }, this.passwordStatus);
      const { email, password } = JSON.parse(init.body);
      const record = this.passwords.get(email);
      if (!record || record.password !== password || !this.users.has(record.userId)) {
        return json({ error_code: 'invalid_credentials' }, 400);
      }
      return json({ access_token: 'verification-access-token', user: { id: this.passwordGrantUserOverride ?? record.userId } });
    }

    if (parsed.pathname === '/auth/v1/logout') return new Response(null, { status: 204 });

    if (parsed.pathname === '/rest/v1/account_deletion_jobs') {
      assert.equal(headers.apikey, SECRET);
      if (this.jobsUnavailable) return json({ message: 'unavailable' }, 503);
      const prefer = headers.Prefer ?? '';
      if (method === 'GET') {
        let rows = filterRows(this.jobs, parsed.searchParams);
        const limit = parsed.searchParams.get('limit');
        if (limit) rows = rows.slice(0, Number(limit));
        return json(rows.map((row) => ({ ...row })));
      }
      if (method === 'POST') {
        const body = JSON.parse(init.body);
        const existing = this.job(body.user_id);
        if (existing && prefer.includes('ignore-duplicates')) return json([], 201);
        if (existing && prefer.includes('merge-duplicates')) {
          const merged = { ...existing, ...body, updated_at: this.clock.now().toISOString() };
          this.assertJobConstraints(merged);
          Object.assign(existing, merged);
          return json([], 201);
        }
        assert.equal(existing, null, 'primary key');
        const row = this.insertJob(body);
        return json(prefer.includes('return=representation') ? [row] : [], 201);
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(init.body);
        const rows = filterRows(this.jobs, parsed.searchParams);
        for (const row of rows) {
          const next = { ...row, ...patch, updated_at: this.clock.now().toISOString() };
          this.assertJobConstraints(next);
          Object.assign(row, next);
        }
        return json(rows.map((row) => ({ ...row })));
      }
      if (method === 'DELETE') {
        const rows = filterRows(this.jobs, parsed.searchParams);
        this.jobs = this.jobs.filter((row) => !rows.includes(row));
        return new Response(null, { status: 204 });
      }
    }

    if (parsed.pathname === '/rest/v1/media_objects') {
      assert.equal(headers.apikey, SECRET);
      const owner = parsed.searchParams.get('owner_id')?.replace(/^eq\./, '');
      if (method === 'GET') {
        const limit = Number(parsed.searchParams.get('limit'));
        const offset = Number(parsed.searchParams.get('offset'));
        return json(this.media.filter((row) => row.owner_id === owner).slice(offset, offset + limit));
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(init.body);
        for (const row of this.media) if (row.owner_id === owner) Object.assign(row, patch);
        return new Response(null, { status: 204 });
      }
    }

    if (parsed.pathname.startsWith('/auth/v1/admin/users/')) {
      assert.equal(headers.apikey, SECRET);
      const userId = decodeURIComponent(parsed.pathname.split('/').pop());
      if (method === 'GET') {
        if (this.adminGetBehaviour === 'fail') return json({ error_code: 'unexpected_failure' }, 500);
        const user = this.users.get(userId);
        return user ? json(user) : json({ error_code: 'user_not_found' }, 404);
      }
      assert.equal(method, 'DELETE');
      assert.equal(JSON.parse(init.body).should_soft_delete, false);
      this.beforeAdminDelete?.();
      if (this.adminDeleteBehaviour === 'fail') return json({ error_code: 'unexpected_failure' }, 500);
      if (this.adminDeleteBehaviour === 'throw') throw new Error('connection reset');
      const existed = this.users.delete(userId);
      this.media = this.media.filter((row) => row.owner_id !== userId); // the cascade
      if (this.adminDeleteBehaviour === 'throw-after-delete') throw new Error('connection reset');
      return existed ? json({}) : json({ error_code: 'user_not_found' }, 404);
    }

    throw new Error(`unexpected request ${method} ${parsed.pathname}`);
  };

  callsTo(path, method) {
    return this.calls.filter((call) => call.path.startsWith(path) && (!method || call.method === method));
  }
}

function mediaRow(ownerId, id, overrides = {}) {
  return { id, owner_id: ownerId, bucket: BUCKET, object_key: `profiles/${ownerId}/${id}.jpg`, status: 'ready', ...overrides };
}

function setup({ bucketKeys = [], bucketName = BUCKET } = {}) {
  const clock = new Clock();
  const supabase = new FakeSupabase(clock);
  const bucket = new FakeBucket(bucketKeys);
  const env = {
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE,
    SUPABASE_SECRET_KEY: SECRET,
    R2_BUCKET_NAME: bucketName,
    MEDIA_BUCKET: bucket,
  };
  return { clock, supabase, bucket, env };
}

async function callDelete(ctx, { authorization, body = { password: PASSWORD } } = {}) {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (authorization !== undefined) headers.set('Authorization', authorization);
  const request = new Request('https://media-api.test/account/delete', {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
  const response = await handleAccountDeletion(request, ctx.env, {
    respond,
    fetchImpl: ctx.supabase.fetch,
    now: ctx.clock.now,
  });
  const text = await response.text();
  return { status: response.status, text, body: text ? JSON.parse(text) : null };
}

function finalize(ctx) {
  return runDeletionFinalizer(ctx.env, { fetchImpl: ctx.supabase.fetch, now: ctx.clock.now });
}

/** One cron run that stamps, then the first run at which the stamp is due. */
async function stampThenFinalize(ctx) {
  await finalize(ctx);
  ctx.clock.advance(CLEANUP_WINDOW_MS);
  return finalize(ctx);
}

/** What POST /authorize does around signing, with the fake clock. */
async function authorizeUpload(ctx, userId, key, { signingDelayMs = 0 } = {}) {
  const checkedAt = ctx.clock.ms;
  await assertUploadsAllowed(userId, ctx.env, ctx.supabase.fetch);
  const url = presigned(key, checkedAt + signingDelayMs);
  assertPresignedWithin(url, checkedAt + MAX_SIGNING_DELAY_MS);
  return { url, expiresAt: checkedAt + signingDelayMs + PUT_TTL_MS };
}

async function rejects(promise, code) {
  await assert.rejects(promise, (error) => error.code === code);
}

async function captureConsoleErrors(run) {
  const original = console.error;
  const lines = [];
  console.error = (...args) => lines.push(args.map(String).join(' '));
  try {
    return { result: await run(), lines };
  } finally {
    console.error = original;
  }
}

// ===========================================================================
// POST /account/delete
// ===========================================================================

test('deletes exactly the verified account and leaves a server-owned finalization job', async () => {
  const aliceKey = `profiles/${ALICE}/a1.jpg`;
  const aliceOrphan = `profiles/${ALICE}/orphan-without-metadata.png`;
  const bobKey = `profiles/${BOB}/b1.jpg`;
  const ctx = setup({ bucketKeys: [aliceKey, aliceOrphan, bobKey] });
  ctx.supabase.media = [mediaRow(ALICE, 'a1'), mediaRow(BOB, 'b1')];

  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });

  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { status: 'deleted', mediaObjectsRemoved: 2 });
  assert.equal(ctx.bucket.objects.has(aliceKey), false);
  assert.equal(ctx.bucket.objects.has(aliceOrphan), false);
  assert.equal(ctx.bucket.objects.has(bobKey), true);
  assert.equal(ctx.supabase.users.has(ALICE), false);
  assert.equal(ctx.supabase.users.has(BOB), true);

  const job = ctx.supabase.job(ALICE);
  assert.equal(job.status, 'auth_deleted');
  assert.equal(job.bucket, BUCKET);
  assert.equal(job.cleanup_not_before, null, 'the request path never sets the finalization time');
  assert.equal(ctx.supabase.job(BOB), null);

  // Order: the job is claimed before any R2 delete, and advanced before the auth delete.
  const calls = ctx.supabase.calls;
  const claim = calls.findIndex((call) => call.path.endsWith('account_deletion_jobs') && call.method === 'POST');
  const advance = calls.findIndex((call) => call.path.endsWith('account_deletion_jobs') && call.method === 'PATCH');
  const adminDelete = calls.findIndex((call) => call.path.startsWith('/auth/v1/admin/users/') && call.method === 'DELETE');
  const password = calls.findIndex((call) => call.path === '/auth/v1/token');
  assert.ok(password < claim && claim < advance && advance < adminDelete);
  assert.match(calls[advance].search, /status=eq\.quarantined/, 'advance is a compare-and-set');
  assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/', 'DELETE')[0].path, `/auth/v1/admin/users/${ALICE}`);
  for (const call of ctx.supabase.callsTo('/rest/v1/media_objects', 'GET')) {
    assert.match(call.search, new RegExp(`owner_id=eq\\.${ALICE}`));
  }
});

test('no bearer token: refused before any Supabase or R2 call', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  const result = await callDelete(ctx, {});
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, { error: 'session_expired' });
  assert.equal(ctx.supabase.calls.length, 0);
  assert.equal(ctx.bucket.deleteCalls.length, 0);
});

test('an invalid token is refused and creates nothing', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  const result = await callDelete(ctx, { authorization: `Bearer ${token(ALICE)}` });
  assert.equal(result.status, 401);
  assert.equal(ctx.supabase.jobs.length, 0);
  assert.equal(ctx.bucket.deleteCalls.length, 0);
});

test('a client-supplied user id for another account is refused before anything else', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${BOB}/b1.jpg`] });
  ctx.supabase.media = [mediaRow(BOB, 'b1')];
  for (const field of ['userId', 'user_id', 'uid', 'id']) {
    const result = await callDelete(ctx, {
      authorization: `Bearer ${ctx.supabase.issue(ALICE)}`,
      body: { password: PASSWORD, [field]: BOB },
    });
    assert.equal(result.status, 403, field);
    assert.deepEqual(result.body, { error: 'account_mismatch' });
  }
  assert.equal(ctx.supabase.callsTo('/auth/v1/token').length, 0);
  assert.equal(ctx.supabase.jobs.length, 0);
  assert.equal(ctx.bucket.deleteCalls.length, 0);
  assert.equal(ctx.supabase.users.size, 2);
});

test('a matching client user id is tolerated but never used', async () => {
  const ctx = setup();
  const result = await callDelete(ctx, {
    authorization: `Bearer ${ctx.supabase.issue(ALICE)}`,
    body: { password: PASSWORD, userId: ALICE },
  });
  assert.equal(result.status, 200);
});

test('a password-recovery session cannot delete the account', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  const recovery = ctx.supabase.issue(ALICE, [{ method: 'recovery', timestamp: 1 }]);
  const result = await callDelete(ctx, { authorization: `Bearer ${recovery}` });
  assert.equal(result.status, 403);
  assert.deepEqual(result.body, { error: 'recovery_session' });
  assert.equal(ctx.supabase.callsTo('/auth/v1/token').length, 0);
  assert.equal(ctx.supabase.jobs.length, 0);
});

test('a wrong or missing password creates no job and does not block uploads', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.supabase.media = [mediaRow(ALICE, 'a1')];
  const bearer = `Bearer ${ctx.supabase.issue(ALICE)}`;

  const wrong = await callDelete(ctx, { authorization: bearer, body: { password: 'wrong-password' } });
  assert.equal(wrong.status, 403);
  assert.deepEqual(wrong.body, { error: 'reauthentication_failed' });

  const missing = await callDelete(ctx, { authorization: bearer, body: {} });
  assert.deepEqual(missing.body, { error: 'reauthentication_failed' });

  assert.equal(ctx.supabase.jobs.length, 0);
  assert.equal(ctx.supabase.callsTo('/rest/v1/media_objects').length, 0);
  assert.equal(ctx.bucket.deleteCalls.length, 0);
  await assertUploadsAllowed(ALICE, ctx.env, ctx.supabase.fetch);
});

test('rate limiting, unsupported providers and a mismatched password grant delete nothing', async () => {
  const limited = setup();
  limited.supabase.passwordStatus = 429;
  assert.deepEqual((await callDelete(limited, { authorization: `Bearer ${limited.supabase.issue(ALICE)}` })).body, {
    error: 'rate_limited',
  });

  const phoneOnly = setup();
  phoneOnly.supabase.users.set(ALICE, { id: ALICE, email: '', identities: [{ provider: 'phone' }] });
  assert.deepEqual((await callDelete(phoneOnly, { authorization: `Bearer ${phoneOnly.supabase.issue(ALICE)}` })).body, {
    error: 'reauthentication_unsupported',
  });

  const crossed = setup();
  crossed.supabase.passwordGrantUserOverride = BOB;
  assert.deepEqual((await callDelete(crossed, { authorization: `Bearer ${crossed.supabase.issue(ALICE)}` })).body, {
    error: 'account_mismatch',
  });
  assert.equal(crossed.supabase.callsTo('/auth/v1/logout').length, 1, 'the verification session is revoked');

  for (const ctx of [limited, phoneOnly, crossed]) {
    assert.equal(ctx.supabase.jobs.length, 0);
    assert.equal(ctx.supabase.users.has(ALICE), true);
  }
});

test('unknown media stops deletion, deletes nothing and releases the quarantine', async () => {
  for (const tamper of [{ bucket: 'some-other-bucket' }, { object_key: `profiles/${BOB}/b1.jpg` }]) {
    const bobKey = `profiles/${BOB}/b1.jpg`;
    const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`, bobKey] });
    ctx.supabase.media = [mediaRow(ALICE, 'a1'), mediaRow(ALICE, 'x1', tamper)];
    const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
    assert.equal(result.status, 502);
    assert.deepEqual(result.body, { error: 'media_cleanup_failed' });
    assert.equal(ctx.bucket.deleteCalls.length, 0);
    assert.equal(ctx.bucket.objects.has(bobKey), true);
    assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/').length, 0);
    assert.equal(ctx.supabase.job(ALICE), null);
    await assertUploadsAllowed(ALICE, ctx.env, ctx.supabase.fetch);
  }
});

test('an R2 failure keeps the account, cancels the job and allows a retry', async () => {
  const key = `profiles/${ALICE}/a1.jpg`;
  const ctx = setup({ bucketKeys: [key] });
  ctx.supabase.media = [mediaRow(ALICE, 'a1')];
  ctx.bucket.failDeletes = true;
  const bearer = `Bearer ${ctx.supabase.issue(ALICE)}`;

  const failed = await callDelete(ctx, { authorization: bearer });
  assert.deepEqual(failed.body, { error: 'media_cleanup_failed' });
  assert.equal(ctx.supabase.users.has(ALICE), true);
  assert.equal(ctx.supabase.job(ALICE), null);

  ctx.bucket.failDeletes = false;
  assert.equal((await callDelete(ctx, { authorization: bearer })).status, 200);
  assert.equal(ctx.bucket.objects.has(key), false);
});

test('an object that survives deletion is caught before the auth delete', async () => {
  const key = `profiles/${ALICE}/a1.jpg`;
  const ctx = setup({ bucketKeys: [key] });
  ctx.bucket.sticky.add(key);
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.deepEqual(result.body, { error: 'media_cleanup_failed' });
  assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/').length, 0);
});

test('a definite auth-delete failure is confirmed by reading the user back, then cancelled', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.supabase.media = [mediaRow(ALICE, 'a1')];
  ctx.supabase.adminDeleteBehaviour = 'fail';
  const bearer = `Bearer ${ctx.supabase.issue(ALICE)}`;

  const first = await callDelete(ctx, { authorization: bearer });
  assert.equal(first.status, 502);
  assert.deepEqual(first.body, { error: 'server_delete_failed' });
  assert.equal(ctx.supabase.users.has(ALICE), true);
  assert.equal(ctx.supabase.job(ALICE), null);
  assert.equal(ctx.supabase.media[0].status, 'deleted', 'metadata tells the truth about the removed object');

  ctx.supabase.adminDeleteBehaviour = 'normal';
  assert.equal((await callDelete(ctx, { authorization: bearer })).status, 200);
  assert.equal(ctx.supabase.users.has(ALICE), false);
});

test('an ambiguous auth delete that did happen is recognised as deleted', async () => {
  const ctx = setup();
  ctx.supabase.adminDeleteBehaviour = 'throw-after-delete';
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 200);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_deleted');
});

test('an unresolvable auth delete stays pending and the finalizer settles it', async () => {
  const late = `profiles/${ALICE}/late.jpg`;
  const ctx = setup();
  ctx.supabase.adminDeleteBehaviour = 'throw-after-delete';
  ctx.supabase.adminGetBehaviour = 'fail';

  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 503);
  assert.deepEqual(result.body, { error: 'deletion_pending' });
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_delete_pending');
  await rejects(assertUploadsAllowed(ALICE, ctx.env, ctx.supabase.fetch), 'deletion_in_progress');

  ctx.bucket.objects.add(late);
  ctx.supabase.adminGetBehaviour = 'normal';

  ctx.clock.advance(PENDING_RECONCILE_AFTER_MS - 1000);
  await finalize(ctx);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_delete_pending', 'not reconciled early');

  ctx.clock.advance(2000);
  assert.equal((await finalize(ctx)).reconciled, 1);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_deleted');

  assert.equal((await stampThenFinalize(ctx)).finalized, 1);
  assert.equal(ctx.supabase.job(ALICE), null);
  assert.equal(ctx.bucket.objects.has(late), false);
});

test('a retry after the account is gone is session_expired and cleans nothing', async () => {
  const ctx = setup();
  const bearer = `Bearer ${ctx.supabase.issue(ALICE)}`;
  assert.equal((await callDelete(ctx, { authorization: bearer })).status, 200);

  const late = `profiles/${ALICE}/late-upload.jpg`;
  ctx.bucket.objects.add(late);
  const callsBefore = ctx.supabase.calls.length;
  const listsBefore = ctx.bucket.listCalls;
  const jobBefore = { ...ctx.supabase.job(ALICE) };

  const retry = await callDelete(ctx, { authorization: bearer });
  assert.equal(retry.status, 401);
  assert.deepEqual(retry.body, { error: 'session_expired' });

  // Only the Supabase Auth check ran: the deleted account's token authorized
  // no R2 access, no job change and no admin call.
  const retryCalls = ctx.supabase.calls.slice(callsBefore);
  assert.deepEqual(retryCalls.map((call) => call.path), ['/auth/v1/user']);
  assert.equal(ctx.bucket.listCalls, listsBefore);
  assert.equal(ctx.bucket.objects.has(late), true);
  assert.deepEqual(ctx.supabase.job(ALICE), jobBefore);

  // The server-owned finalizer removes it once due.
  await stampThenFinalize(ctx);
  assert.equal(ctx.bucket.objects.has(late), false);
});

test('a concurrent second request cannot run a second auth delete', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  const bearer = `Bearer ${ctx.supabase.issue(ALICE)}`;
  const results = await Promise.all([
    callDelete(ctx, { authorization: bearer }),
    callDelete(ctx, { authorization: bearer }),
  ]);
  assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/', 'DELETE').length, 1);
  assert.ok(results.some((result) => result.status === 200));
  for (const result of results) {
    assert.ok([200, 409].includes(result.status), JSON.stringify(result.body));
  }
  assert.equal(ctx.supabase.users.has(ALICE), false);
});

test('an existing job past quarantine refuses a new request for a still-existing account', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.supabase.insertJob({ user_id: ALICE, status: 'auth_delete_pending' });
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 409);
  assert.deepEqual(result.body, { error: 'deletion_in_progress' });
  assert.equal(ctx.bucket.deleteCalls.length, 0);
  assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/').length, 0);
});

test('a job abandoned during an in-flight auth delete is recreated and finalized normally', async () => {
  const key = `profiles/${ALICE}/uploaded-while-unquarantined.jpg`;
  const ctx = setup();
  ctx.supabase.beforeAdminDelete = () => {
    // Simulates the finalizer cancelling this job while the delete was stalled,
    // and an upload landing while the account was briefly unquarantined.
    ctx.clock.advance(ABANDONED_JOB_AFTER_MS + 1000);
    ctx.supabase.jobs = [];
    ctx.bucket.objects.add(key);
  };
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 200);
  const job = ctx.supabase.job(ALICE);
  assert.equal(job.status, 'auth_deleted');
  assert.equal(job.bucket, BUCKET);
  assert.equal(job.cleanup_not_before, null);
  assert.equal((await stampThenFinalize(ctx)).finalized, 1);
  assert.equal(ctx.bucket.objects.has(key), false);
});

test('the job table being unavailable fails closed before anything is deleted', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.supabase.jobsUnavailable = true;
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 503);
  assert.deepEqual(result.body, { error: 'service_unavailable' });
  assert.equal(ctx.bucket.deleteCalls.length, 0);
  assert.equal(ctx.supabase.users.has(ALICE), true);
});

test('the inventory pages through large media sets', async () => {
  const ctx = setup();
  ctx.supabase.media = Array.from({ length: 1203 }, (_, index) => mediaRow(ALICE, `m${String(index).padStart(5, '0')}`));
  for (const row of ctx.supabase.media) ctx.bucket.objects.add(row.object_key);
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 200);
  assert.equal(result.body.mediaObjectsRemoved, 1203);
  assert.equal(ctx.bucket.objects.size, 0);
});

test('a malformed body or missing configuration is refused without side effects', async () => {
  const malformed = setup();
  assert.deepEqual(
    (await callDelete(malformed, { authorization: `Bearer ${malformed.supabase.issue(ALICE)}`, body: 'not json' })).body,
    { error: 'invalid_request' },
  );
  assert.equal(malformed.supabase.jobs.length, 0);

  const unconfigured = setup();
  delete unconfigured.env.SUPABASE_SECRET_KEY;
  const result = await callDelete(unconfigured, { authorization: `Bearer ${unconfigured.supabase.issue(ALICE)}` });
  assert.equal(result.status, 503);
  assert.equal(unconfigured.supabase.calls.length, 0);
});

// ===========================================================================
// Upload quarantine and the signed PUT race
// ===========================================================================

test('/authorize refuses to sign while a deletion job exists, and fails closed', async () => {
  const ctx = setup();
  await assertUploadsAllowed(ALICE, ctx.env, ctx.supabase.fetch);

  ctx.supabase.insertJob({ user_id: ALICE });
  await rejects(authorizeUpload(ctx, ALICE, `profiles/${ALICE}/x.jpg`), 'deletion_in_progress');
  await assertUploadsAllowed(BOB, ctx.env, ctx.supabase.fetch);

  ctx.supabase.jobsUnavailable = true;
  await rejects(assertUploadsAllowed(BOB, ctx.env, ctx.supabase.fetch), 'service_unavailable');
});

test('a signature dated later than the quarantine check allows is refused', () => {
  const checkedAt = START;
  assert.doesNotThrow(() => assertPresignedWithin(presigned('k', checkedAt + MAX_SIGNING_DELAY_MS), checkedAt + MAX_SIGNING_DELAY_MS));
  assert.throws(
    () => assertPresignedWithin(presigned('k', checkedAt + MAX_SIGNING_DELAY_MS + 1000), checkedAt + MAX_SIGNING_DELAY_MS),
    (error) => error.code === 'service_unavailable',
  );
  assert.throws(() => assertPresignedWithin('https://r2.test/k?X-Amz-Signature=x', checkedAt), (error) => error.code === 'service_unavailable');
});

test('signed PUT race T0-T4: a late upload after auth deletion is always finalized', async () => {
  const key = `profiles/${ALICE}/in-flight.jpg`;
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/avatar.jpg`] });

  // T0: /authorize issues a URL just before deletion begins, signed as late as
  // the Worker allows.
  const issued = await authorizeUpload(ctx, ALICE, key, { signingDelayMs: MAX_SIGNING_DELAY_MS });

  // T1-T2: the deletion runs a second later and removes the auth user.
  ctx.clock.advance(1000);
  assert.equal((await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` })).status, 200);

  // The very next cron run stamps the job. Even at its earliest, the stamp
  // leaves the full window after the latest possible URL expiry.
  assert.equal((await finalize(ctx)).stamped, 1);
  const job = ctx.supabase.job(ALICE);
  const notBefore = Date.parse(job.cleanup_not_before);
  assert.ok(notBefore - issued.expiresAt >= FINALIZER_SAFETY_MARGIN_MS, 'margin after the latest URL expiry');

  // No new URL can be issued now.
  await rejects(authorizeUpload(ctx, ALICE, `profiles/${ALICE}/new.jpg`), 'deletion_in_progress');

  // T3: the still-valid URL is used just before it expires.
  ctx.clock.ms = issued.expiresAt - 1000;
  ctx.bucket.objects.add(key);

  // A finalizer run before cleanup_not_before leaves the job and object alone.
  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);
  assert.ok(ctx.supabase.job(ALICE));
  assert.ok(ctx.bucket.objects.has(key));

  // T4 is prevented: the first run at cleanup_not_before removes it.
  ctx.clock.ms = notBefore;
  const summary = await finalize(ctx);
  assert.equal(summary.finalized, 1);
  assert.equal(ctx.bucket.objects.has(key), false);
  assert.equal(ctx.supabase.job(ALICE), null);
  assert.ok(ctx.clock.ms > issued.expiresAt, 'no URL for the prefix is valid any more');
});

test('the finalization stamp is read after the jobs are listed, not before', async () => {
  const ctx = setup();
  ctx.supabase.insertJob({ user_id: ALICE, status: 'auth_deleted', auth_deleted_at: new Date(START).toISOString() });
  const originalFetch = ctx.supabase.fetch;
  ctx.supabase.fetch = async (url, init) => {
    const response = await originalFetch(url, init);
    // The listing takes 30 s to come back.
    if (String(url).includes('cleanup_not_before=is.null')) ctx.clock.advance(30 * 1000);
    return response;
  };
  await finalize(ctx);
  assert.equal(Date.parse(ctx.supabase.job(ALICE).cleanup_not_before), START + 30 * 1000 + CLEANUP_WINDOW_MS);
});

test('the window is the longest PUT URL life plus an explicit margin', () => {
  assert.equal(SIGNED_PUT_TTL_SECONDS, 300);
  assert.equal(MAX_SIGNING_DELAY_MS, 60 * 1000);
  assert.equal(FINALIZER_SAFETY_MARGIN_MS, 120 * 1000);
  assert.equal(CLEANUP_WINDOW_MS, 480 * 1000);
});

// ===========================================================================
// Scheduled finalizer
// ===========================================================================

test('the finalizer acts only on due jobs and only inside each job\'s own prefix', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/late.jpg`, `profiles/${BOB}/b1.jpg`] });
  ctx.supabase.insertJob({ user_id: ALICE, status: 'auth_deleted', auth_deleted_at: new Date(START).toISOString() });

  assert.deepEqual(await finalize(ctx), { ...EMPTY_SUMMARY, stamped: 1 });
  assert.equal(ctx.bucket.objects.size, 2);

  ctx.clock.advance(CLEANUP_WINDOW_MS - 1000);
  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);
  assert.equal(ctx.bucket.objects.size, 2);

  ctx.clock.advance(1000);
  assert.equal((await finalize(ctx)).finalized, 1);
  assert.equal(ctx.bucket.objects.has(`profiles/${ALICE}/late.jpg`), false);
  assert.equal(ctx.bucket.objects.has(`profiles/${BOB}/b1.jpg`), true);
  assert.equal(ctx.supabase.callsTo('/rest/v1/media_objects').length, 0);
  assert.equal(ctx.supabase.callsTo('/auth/v1/user').length, 0, 'no client identity is involved');
});

test('a failed finalization is recorded and retried until it succeeds', async () => {
  const ctx = setup({ bucketKeys: [`profiles/${ALICE}/late.jpg`] });
  ctx.supabase.insertJob({ user_id: ALICE, status: 'auth_deleted', auth_deleted_at: new Date(START).toISOString() });
  await finalize(ctx);
  ctx.clock.advance(CLEANUP_WINDOW_MS);

  ctx.bucket.failDeletes = true;
  assert.equal((await finalize(ctx)).cleanupFailed, 1);
  assert.equal(ctx.supabase.job(ALICE).status, 'cleanup_failed');
  assert.equal(ctx.supabase.job(ALICE).cleanup_attempts, 1);
  assert.equal(ctx.supabase.job(ALICE).last_error_code, 'media_cleanup_failed');

  await finalize(ctx);
  assert.equal(ctx.supabase.job(ALICE).cleanup_attempts, 2);

  ctx.bucket.failDeletes = false;
  assert.equal((await finalize(ctx)).finalized, 1);
  assert.equal(ctx.supabase.job(ALICE), null);
  assert.equal(ctx.bucket.objects.size, 0);
});

test('abandoned quarantines are cancelled only when the account still exists and only after an hour', async () => {
  const ctx = setup();
  ctx.supabase.insertJob({ user_id: ALICE });

  ctx.clock.advance(ABANDONED_JOB_AFTER_MS - 1000);
  await finalize(ctx);
  assert.equal(ctx.supabase.job(ALICE).status, 'quarantined');

  ctx.clock.advance(2000);
  assert.equal((await finalize(ctx)).cancelled, 1);
  assert.equal(ctx.supabase.job(ALICE), null);
  await assertUploadsAllowed(ALICE, ctx.env, ctx.supabase.fetch);
});

test('a pending job whose account still exists is kept for an hour, then cancelled', async () => {
  const ctx = setup();
  ctx.supabase.insertJob({ user_id: ALICE, status: 'auth_delete_pending' });

  ctx.clock.advance(PENDING_RECONCILE_AFTER_MS + 1000);
  await finalize(ctx);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_delete_pending');

  ctx.clock.advance(ABANDONED_JOB_AFTER_MS);
  assert.equal((await finalize(ctx)).cancelled, 1);
  assert.equal(ctx.supabase.job(ALICE), null);
});

test('a quarantined account deleted by other means is still finalized', async () => {
  const key = `profiles/${ALICE}/a1.jpg`;
  const ctx = setup({ bucketKeys: [key] });
  ctx.supabase.insertJob({ user_id: ALICE });
  ctx.supabase.users.delete(ALICE);

  ctx.clock.advance(ABANDONED_JOB_AFTER_MS + 1000);
  assert.equal((await finalize(ctx)).reconciled, 1);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_deleted');
  assert.equal((await stampThenFinalize(ctx)).finalized, 1);
  assert.equal(ctx.bucket.objects.has(key), false);
});

test('a finalizer only touches jobs for its own bucket', async () => {
  const productionKey = `profiles/${ALICE}/a1.jpg`;
  const ctx = setup({ bucketKeys: [productionKey] });
  // A job created by a Worker bound to a different bucket (for example staging).
  ctx.supabase.insertJob({
    user_id: ALICE,
    bucket: 'broker-wallet-media-staging',
    status: 'auth_deleted',
    auth_deleted_at: new Date(START).toISOString(),
  });
  ctx.supabase.insertJob({ user_id: BOB, bucket: 'broker-wallet-media-staging' });
  ctx.supabase.users.delete(BOB);

  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);
  ctx.clock.advance(ABANDONED_JOB_AFTER_MS * 2);
  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);

  assert.equal(ctx.supabase.job(ALICE).cleanup_not_before, null);
  assert.equal(ctx.supabase.job(BOB).status, 'quarantined');
  assert.equal(ctx.bucket.objects.has(productionKey), true);
  assert.equal(ctx.bucket.deleteCalls.length, 0);
});

test('the finalizer never rejects, whatever fails', async () => {
  const ctx = setup();
  ctx.supabase.jobsUnavailable = true;
  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);
  delete ctx.env.MEDIA_BUCKET;
  assert.deepEqual(await finalize(ctx), EMPTY_SUMMARY);
});

// ===========================================================================
// Job ownership across buckets (production and staging share one table)
// ===========================================================================

const STAGING_BUCKET = 'broker-wallet-media-staging';

function jobSnapshot(ctx, userId) {
  const job = ctx.supabase.job(userId);
  return job ? { ...job } : null;
}

for (const [label, workerBucket, jobBucket] of [
  ['1. a production job cannot be claimed by staging', STAGING_BUCKET, BUCKET],
  ['2. a staging job cannot be claimed by production', BUCKET, STAGING_BUCKET],
]) {
  test(`${label}; 6-7. it never reaches the auth delete or R2`, async () => {
    const key = `profiles/${ALICE}/a1.jpg`;
    const ctx = setup({ bucketKeys: [key], bucketName: workerBucket });
    ctx.supabase.insertJob({ user_id: ALICE, bucket: jobBucket, status: 'quarantined' });
    const before = jobSnapshot(ctx, ALICE);

    const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });

    assert.equal(result.status, 409);
    assert.deepEqual(result.body, { error: 'deletion_in_progress' });
    assert.deepEqual(jobSnapshot(ctx, ALICE), before, 'the other bucket\'s job is untouched');
    assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/').length, 0);
    assert.equal(ctx.supabase.callsTo('/rest/v1/media_objects').length, 0);
    assert.equal(ctx.bucket.deleteCalls.length, 0);
    assert.equal(ctx.bucket.objects.has(key), true);
    assert.equal(ctx.supabase.users.has(ALICE), true);
    for (const call of ctx.supabase.callsTo('/rest/v1/account_deletion_jobs')) {
      assert.ok(['GET', 'POST'].includes(call.method), `no ${call.method} on another bucket's job`);
    }
  });
}

test('3. staging cannot compare-and-set a job that production took over mid-request', async () => {
  const ctx = setup({ bucketName: STAGING_BUCKET, bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.bucket.onDelete = () => {
    // While staging's R2 cleanup runs, the uid's job now belongs to production.
    const job = ctx.supabase.job(ALICE);
    if (job) job.bucket = BUCKET;
  };

  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });

  assert.equal(result.status, 409);
  assert.deepEqual(result.body, { error: 'deletion_in_progress' });
  const job = ctx.supabase.job(ALICE);
  assert.equal(job.bucket, BUCKET);
  assert.equal(job.status, 'quarantined', 'not advanced by staging');
  assert.equal(ctx.supabase.callsTo('/auth/v1/admin/users/').length, 0);
  assert.equal(ctx.supabase.users.has(ALICE), true);
  for (const call of ctx.supabase.callsTo('/rest/v1/account_deletion_jobs', 'PATCH')) {
    assert.match(call.search, /bucket=eq\.broker-wallet-media-staging/);
  }
});

test('4. staging cannot cancel a production job', async () => {
  const ctx = setup({ bucketName: STAGING_BUCKET, bucketKeys: [`profiles/${ALICE}/a1.jpg`] });
  ctx.bucket.failDeletes = true;
  ctx.bucket.onDelete = () => {
    const job = ctx.supabase.job(ALICE);
    if (job) job.bucket = BUCKET;
  };

  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });

  assert.deepEqual(result.body, { error: 'media_cleanup_failed' });
  const job = ctx.supabase.job(ALICE);
  assert.ok(job, 'the production job was not deleted by staging');
  assert.equal(job.bucket, BUCKET);
  for (const call of ctx.supabase.callsTo('/rest/v1/account_deletion_jobs', 'DELETE')) {
    assert.match(call.search, /bucket=eq\.broker-wallet-media-staging/);
  }
});

test('5. recording the auth delete never overwrites another bucket\'s job', async () => {
  const ctx = setup();
  ctx.supabase.beforeAdminDelete = () => {
    // The production job disappeared and another bucket now owns the uid.
    ctx.supabase.jobs = [];
    ctx.supabase.insertJob({ user_id: ALICE, bucket: STAGING_BUCKET, status: 'auth_delete_pending' });
  };
  const before = () => jobSnapshot(ctx, ALICE);

  const { result, lines } = await captureConsoleErrors(() =>
    callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` }),
  );

  assert.equal(result.status, 200, 'the account itself was deleted');
  const job = before();
  assert.equal(job.bucket, STAGING_BUCKET);
  assert.equal(job.status, 'auth_delete_pending');
  assert.equal(job.auth_deleted_at, null);
  assert.ok(lines.includes('[account-delete] job owned by another bucket'));
  for (const call of ctx.supabase.callsTo('/rest/v1/account_deletion_jobs', 'POST')) {
    assert.match(call.headers.Prefer, /ignore-duplicates/, 'no merge upsert is ever sent');
  }
});

test('recording the auth delete recreates an absent job only with an ignoring insert', async () => {
  const ctx = setup();
  ctx.supabase.beforeAdminDelete = () => {
    ctx.supabase.jobs = [];
  };
  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });
  assert.equal(result.status, 200);
  const job = ctx.supabase.job(ALICE);
  assert.equal(job.bucket, BUCKET);
  assert.equal(job.status, 'auth_deleted');
});

test('recording the auth delete accepts this bucket\'s job already reconciled by the finalizer', async () => {
  const ctx = setup();
  ctx.supabase.beforeAdminDelete = () => {
    const job = ctx.supabase.job(ALICE);
    job.status = 'auth_deleted';
    job.auth_deleted_at = ctx.clock.now().toISOString();
  };
  const { result, lines } = await captureConsoleErrors(() =>
    callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` }),
  );
  assert.equal(result.status, 200);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_deleted');
  assert.equal(lines.includes('[account-delete] job record failed'), false);
});

test('8. uploads are blocked when a deletion job exists in ANY bucket', async () => {
  const production = setup();
  production.supabase.insertJob({ user_id: ALICE, bucket: STAGING_BUCKET });
  await rejects(assertUploadsAllowed(ALICE, production.env, production.supabase.fetch), 'deletion_in_progress');

  const staging = setup({ bucketName: STAGING_BUCKET });
  staging.supabase.insertJob({ user_id: ALICE, bucket: BUCKET });
  await rejects(assertUploadsAllowed(ALICE, staging.env, staging.supabase.fetch), 'deletion_in_progress');
});

test('9. a same-bucket quarantined job left by an earlier attempt is safely reused', async () => {
  const key = `profiles/${ALICE}/a1.jpg`;
  const ctx = setup({ bucketKeys: [key] });
  ctx.supabase.insertJob({ user_id: ALICE, status: 'quarantined' });

  const result = await callDelete(ctx, { authorization: `Bearer ${ctx.supabase.issue(ALICE)}` });

  assert.equal(result.status, 200);
  assert.equal(ctx.supabase.job(ALICE).status, 'auth_deleted');
  assert.equal(ctx.supabase.job(ALICE).bucket, BUCKET);
  assert.equal(ctx.bucket.objects.has(key), false);
});

test('10-12. each finalizer finalizes its own bucket\'s jobs and never the other\'s', async () => {
  const stagingKey = `profiles/${ALICE}/late.jpg`;
  const productionKey = `profiles/${BOB}/late.jpg`;
  const staging = setup({ bucketName: STAGING_BUCKET, bucketKeys: [stagingKey] });
  const production = setup({ bucketKeys: [productionKey] });
  // One shared job table.
  production.supabase = staging.supabase;
  production.clock = staging.clock;
  staging.supabase.insertJob({
    user_id: ALICE,
    bucket: STAGING_BUCKET,
    status: 'auth_deleted',
    auth_deleted_at: new Date(START).toISOString(),
  });
  staging.supabase.insertJob({
    user_id: BOB,
    bucket: BUCKET,
    status: 'auth_deleted',
    auth_deleted_at: new Date(START).toISOString(),
  });

  // The staging cron alone: only the staging job is stamped and finalized.
  assert.equal((await finalize(staging)).stamped, 1);
  assert.equal(staging.supabase.job(BOB).cleanup_not_before, null);
  staging.clock.advance(CLEANUP_WINDOW_MS);
  assert.equal((await finalize(staging)).finalized, 1);
  assert.equal(staging.supabase.job(ALICE), null);
  assert.equal(staging.bucket.objects.has(stagingKey), false);
  assert.ok(staging.supabase.job(BOB), 'production job untouched by staging');
  assert.equal(production.bucket.objects.has(productionKey), true);

  // 10. Production still finalizes its own job normally.
  assert.equal((await stampThenFinalize(production)).finalized, 1);
  assert.equal(production.supabase.job(BOB), null);
  assert.equal(production.bucket.objects.has(productionKey), false);
});

// ===========================================================================
// Leaks
// ===========================================================================

test('responses and logs never contain secrets, tokens, passwords, ids or object keys', async () => {
  const scenarios = [
    (ctx) => {
      ctx.supabase.media = [mediaRow(ALICE, 'a1')];
      ctx.bucket.objects.add(`profiles/${ALICE}/a1.jpg`);
    },
    (ctx) => {
      ctx.supabase.passwords.get('alice@example.test').password = 'something-else';
    },
    (ctx) => {
      ctx.supabase.media = [mediaRow(ALICE, 'a1', { bucket: 'elsewhere' })];
    },
    (ctx) => {
      ctx.supabase.adminDeleteBehaviour = 'fail';
    },
    (ctx) => {
      ctx.supabase.adminDeleteBehaviour = 'throw';
      ctx.supabase.adminGetBehaviour = 'fail';
    },
    (ctx) => {
      ctx.env.MEDIA_BUCKET.list = () => {
        throw new Error(`boom ${SECRET} ${PASSWORD} profiles/${ALICE}`);
      };
    },
  ];

  for (const prepare of scenarios) {
    const ctx = setup();
    prepare(ctx);
    const issued = ctx.supabase.issue(ALICE);
    const { result, lines } = await captureConsoleErrors(async () => {
      const response = await callDelete(ctx, { authorization: `Bearer ${issued}` });
      ctx.clock.advance(ABANDONED_JOB_AFTER_MS * 2);
      await finalize(ctx);
      return response;
    });
    const forbidden = [SECRET, PASSWORD, issued, 'verification-access-token', `profiles/${ALICE}`, ALICE, 'alice@example.test'];
    for (const value of forbidden) {
      assert.equal(result.text.includes(value), false, `response leaked ${value}`);
      for (const line of lines) assert.equal(line.includes(value), false, `log leaked ${value}`);
    }
  }
});
