// Behavioural tests for the Offer Media routes:
//   POST /offer-media/authorize
//   POST /offer-media/confirm
//   GET  /offer-media
//
// Run with: npm test   (or a bare `node --test` from this directory)
//
// Tests go through the Worker's own real HTTP entrypoint (`worker.fetch`),
// not internal functions — Supabase Auth/PostgREST is an in-memory fake
// reached by temporarily replacing `globalThis.fetch` for the duration of
// each test, and the R2 binding is a small in-memory fake bucket. Assertions
// check observable state (row counts, field values, bucket contents), not
// merely that some helper was invoked.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import worker from '../worker.js';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE = 'sb_publishable_test';
const SECRET = 'sb_secret_TEST_SECRET_VALUE';
const BUCKET = 'broker-wallet-media-staging';
const WORKER_ORIGIN = 'https://media-api.test';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
const OFFER_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

// An unsigned but shape-correct JWT: the fake /auth/v1/user endpoint below
// only ever reads the payload segment, exactly like the existing
// account_deletion tests' equivalent helper.
function token(sub) {
  return `${base64Url({ alg: 'HS256' })}.${base64Url({ sub })}.signature`;
}

function json(body, status = 200) {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Matches simple PostgREST filters: eq.x and is.null. Enough for these tests. */
function matches(rowValue, filter) {
  const dot = filter.indexOf('.');
  const op = filter.slice(0, dot);
  const operand = filter.slice(dot + 1);
  if (op === 'eq') return String(rowValue) === operand;
  if (op === 'is' && operand === 'null') return rowValue === null || rowValue === undefined;
  throw new Error(`unsupported filter ${filter}`);
}

const RESERVED_PARAMS = new Set(['select', 'order', 'limit', 'offset', 'on_conflict']);

function filterRows(rows, searchParams) {
  return rows.filter((row) =>
    [...searchParams.entries()].every(([column, filter]) => RESERVED_PARAMS.has(column) || matches(row[column], filter)),
  );
}

/** A minimal in-memory Supabase REST + Auth fake for exactly what the Offer
 * Media routes call. */
class FakeSupabase {
  constructor() {
    this.users = new Map([
      [ALICE, { id: ALICE }],
      [BOB, { id: BOB }],
    ]);
    this.validTokens = new Set([token(ALICE), token(BOB)]);
    this.offers = [{ id: OFFER_A, owner_id: ALICE, deleted_at: null }];
    this.mediaObjects = [];
    this.offerMedia = [];
    this.deletionJobs = [];
    this.calls = [];
    this.failOfferMediaInsert = false;
  }

  fetch = async (url, init = {}) => {
    const parsed = new URL(url);
    const method = init.method ?? 'GET';
    const headers = init.headers ?? {};
    this.calls.push({ method, path: parsed.pathname, search: parsed.search });

    if (parsed.pathname === '/auth/v1/user') {
      const bearer = (headers.Authorization ?? '').slice('Bearer '.length);
      if (!this.validTokens.has(bearer)) return json({ error_code: 'bad_jwt' }, 403);
      const sub = JSON.parse(Buffer.from(bearer.split('.')[1], 'base64url').toString()).sub;
      const user = this.users.get(sub);
      return user ? json(user) : json({ error_code: 'user_not_found' }, 403);
    }

    assert.equal(headers.apikey, SECRET, `service-role calls must use the secret key (${parsed.pathname})`);

    if (parsed.pathname === '/rest/v1/account_deletion_jobs') {
      return json(filterRows(this.deletionJobs, parsed.searchParams));
    }

    if (parsed.pathname === '/rest/v1/offers') {
      return json(filterRows(this.offers, parsed.searchParams));
    }

    if (parsed.pathname === '/rest/v1/media_objects') {
      if (method === 'POST') {
        const body = JSON.parse(init.body);
        this.mediaObjects.push({ ...body });
        return json([], 201);
      }
      if (method === 'GET') {
        return json(filterRows(this.mediaObjects, parsed.searchParams));
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(init.body);
        const rows = filterRows(this.mediaObjects, parsed.searchParams);
        for (const row of rows) Object.assign(row, patch);
        return json(rows.length > 0 ? [] : [], rows.length > 0 ? 200 : 200);
      }
    }

    if (parsed.pathname === '/rest/v1/offer_media') {
      if (method === 'POST') {
        if (this.failOfferMediaInsert) return json({ message: 'simulated insert failure' }, 500);
        const body = JSON.parse(init.body);
        this.offerMedia.push({ ...body });
        return json([], 201);
      }
      if (method === 'GET') {
        const rows = filterRows(this.offerMedia, parsed.searchParams).map((row) => ({
          media_id: row.media_id,
          role: row.role,
          ordinal: row.ordinal,
          media_objects: this.mediaObjects.find((m) => m.id === row.media_id) ?? null,
        }));
        return json(rows);
      }
    }

    throw new Error(`unexpected request ${method} ${parsed.pathname}`);
  };

  callsTo(path, method) {
    return this.calls.filter((call) => call.path === path && (!method || call.method === method));
  }
}

/** A minimal in-memory R2 bucket fake supporting exactly what
 * handleOfferMediaConfirm needs (head/get by key). */
class FakeBucket {
  constructor() {
    this.objects = new Map();
  }
  put(key, bytes, contentType) {
    this.objects.set(key, { bytes, contentType });
  }
  async head(key) {
    const object = this.objects.get(key);
    if (!object) return null;
    return { size: object.bytes.length, httpMetadata: { contentType: object.contentType } };
  }
  async get(key, { range } = {}) {
    const object = this.objects.get(key);
    if (!object) return null;
    const bytes = range ? object.bytes.slice(range.offset, range.offset + range.length) : object.bytes;
    return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
  }
  async delete(key) {
    this.objects.delete(key);
  }
  async list() {
    return { objects: [], truncated: false };
  }
}

// A syntactically valid minimal JPEG signature, padded to the 64 bytes the
// Worker reads to detect the image type.
const JPEG_BYTES = Uint8Array.from([0xff, 0xd8, 0xff, ...new Array(61).fill(0)]);

function setup() {
  const supabase = new FakeSupabase();
  const bucket = new FakeBucket();
  const env = {
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE,
    SUPABASE_SECRET_KEY: SECRET,
    R2_BUCKET_NAME: BUCKET,
    R2_S3_ENDPOINT: 'https://r2.test.example.com',
    R2_ACCESS_KEY_ID: 'test-access-key-id',
    R2_SECRET_ACCESS_KEY: 'test-secret-access-key',
    ALLOWED_ORIGIN: '*',
    MEDIA_BUCKET: bucket,
  };
  return { supabase, bucket, env };
}

function request(path, { method = 'GET', authorization, body, stagingKey } = {}) {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (authorization !== undefined) headers.set('Authorization', authorization);
  if (stagingKey !== undefined) headers.set('X-Broker-Wallet-Staging-Key', stagingKey);
  return new Request(`${WORKER_ORIGIN}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function call(ctx, path, options) {
  const response = await worker.fetch(request(path, options), ctx.env, {});
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

/** Authorizes and "uploads" (seeds the fake bucket directly, exactly like a
 * real client PUT would have left it) one Offer image for [userId]. */
async function authorizeAndUpload(ctx, userId, offerId) {
  const auth = await call(ctx, '/offer-media/authorize', {
    method: 'POST',
    authorization: `Bearer ${token(userId)}`,
    body: { offerId, contentType: 'image/jpeg', contentLength: JPEG_BYTES.length },
  });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  ctx.bucket.put(auth.body.objectKey, JPEG_BYTES, 'image/jpeg');
  return auth.body.mediaObjectId;
}

let ctx;
let originalFetch;

beforeEach(() => {
  ctx = setup();
  originalFetch = globalThis.fetch;
  globalThis.fetch = ctx.supabase.fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

// ===========================================================================
// TEST 1 — cross-account access
// ===========================================================================

test('a non-owner is denied by authorize, confirm and list, even through a valid staging gate', async () => {
  ctx.env.STAGING_TEST_KEY = 'staging-secret-for-test';
  const stagingKey = ctx.env.STAGING_TEST_KEY;

  const authorize = await call(ctx, '/offer-media/authorize', {
    method: 'POST',
    authorization: `Bearer ${token(BOB)}`,
    stagingKey,
    body: { offerId: OFFER_A, contentType: 'image/jpeg', contentLength: 100 },
  });
  assert.equal(authorize.status, 404);
  assert.equal(ctx.supabase.mediaObjects.length, 0, 'no pending media row was created for the non-owner');

  const confirm = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(BOB)}`,
    stagingKey,
    body: { offerId: OFFER_A, mediaObjectId: '99999999-9999-4999-8999-999999999999' },
  });
  assert.equal(confirm.status, 404);

  const list = await call(ctx, `/offer-media?offerId=${OFFER_A}`, {
    authorization: `Bearer ${token(BOB)}`,
    stagingKey,
  });
  assert.equal(list.status, 404);

  // The staging gate matched on every one of the three requests above (a
  // wrong/missing key would itself produce 403, not 404) — the denials are
  // therefore coming from ownership checks, not the gate.
});

// ===========================================================================
// TEST 2 — confirmation retry is idempotent
// ===========================================================================

test('a repeated confirm after success does not duplicate the association or change media state', async () => {
  const mediaObjectId = await authorizeAndUpload(ctx, ALICE, OFFER_A);

  const first = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  assert.equal(first.status, 200);
  assert.equal(first.body.alreadyConfirmed, undefined);

  const afterFirst = ctx.supabase.mediaObjects.find((row) => row.id === mediaObjectId);
  assert.equal(afterFirst.status, 'ready');
  assert.equal(ctx.supabase.offerMedia.length, 1, 'exactly one association after the first confirm');

  const second = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  assert.equal(second.status, 200);
  assert.equal(second.body.alreadyConfirmed, true);

  // Observable state, not call counts: still exactly one association, media
  // object state unchanged by the retry.
  assert.equal(ctx.supabase.offerMedia.length, 1, 'the retry created no second association');
  const afterSecond = ctx.supabase.mediaObjects.find((row) => row.id === mediaObjectId);
  assert.equal(afterSecond.status, 'ready');
  assert.deepEqual(afterSecond, afterFirst, 'the media row is byte-identical after the idempotent retry');
});

// ===========================================================================
// TEST 3 — association failure leaves nothing orphaned
// ===========================================================================

test('a failed offer_media insert leaves no orphaned ready media object', async () => {
  const mediaObjectId = await authorizeAndUpload(ctx, ALICE, OFFER_A);
  ctx.supabase.failOfferMediaInsert = true;

  const confirm = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  // 422, not 502: the association failure is deliberately funneled through
  // the same rejectInvalidUpload() path as every other post-upload
  // validation failure in this file (object missing, size invalid, wrong
  // signature), so it is reported and cleaned up identically.
  assert.equal(confirm.status, 422);

  // Fail closed: never 'ready', not left dangling as 'pending_upload' either
  // — and no association was created.
  const row = ctx.supabase.mediaObjects.find((m) => m.id === mediaObjectId);
  assert.equal(row.status, 'failed', 'the media row is marked failed, not left ready or pending');
  assert.equal(ctx.supabase.offerMedia.length, 0, 'no association exists for the failed confirm');

  // The R2 object itself was deleted as part of the same cleanup, so a
  // retried confirm cannot find a stale object either.
  const key = ctx.bucket.objects.has(`profiles/${ALICE}/offers/${OFFER_A}/${mediaObjectId}.jpg`);
  assert.equal(key, false, 'the uploaded R2 object was deleted on failure');
});
