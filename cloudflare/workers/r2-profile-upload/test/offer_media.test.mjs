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

/** Matches simple PostgREST filters: eq.x, is.null and like.x* (with `*` as
 * the wildcard). Enough for these tests. */
function matches(rowValue, filter) {
  const dot = filter.indexOf('.');
  const op = filter.slice(0, dot);
  const operand = filter.slice(dot + 1);
  if (op === 'eq') return String(rowValue) === operand;
  if (op === 'is' && operand === 'null') return rowValue === null || rowValue === undefined;
  if (op === 'like') {
    const escaped = operand.split('*').map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    return new RegExp(`^${escaped.join('.*')}$`).test(String(rowValue ?? ''));
  }
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
      if (method === 'DELETE') {
        const doomed = new Set(filterRows(this.mediaObjects, parsed.searchParams));
        this.mediaObjects = this.mediaObjects.filter((row) => !doomed.has(row));
        return json([], 200);
      }
    }

    if (parsed.pathname === '/rest/v1/offer_media') {
      if (method === 'POST') {
        if (this.failOfferMediaInsert) return json({ message: 'simulated insert failure' }, 500);
        const body = JSON.parse(init.body);
        // The real table's constraints: primary key (offer_id, media_id) —
        // skipped under ignore-duplicates, exactly like ON CONFLICT DO
        // NOTHING — and unique (offer_id, role, ordinal), which still raises.
        const ignoreDuplicates = String(headers.Prefer ?? '').includes('resolution=ignore-duplicates');
        if (this.offerMedia.some((row) => row.offer_id === body.offer_id && row.media_id === body.media_id)) {
          return ignoreDuplicates ? json([], 201) : json({ code: '23505' }, 409);
        }
        if (this.offerMedia.some((row) => row.offer_id === body.offer_id && row.role === body.role && row.ordinal === body.ordinal)) {
          return json({ code: '23505', message: 'duplicate key value violates unique constraint' }, 409);
        }
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
    this.reads = [];
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
    this.reads.push(bytes.length);
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

// ===========================================================================
// VIDEO SUPPORT, SIGNATURES AND THE 10-ITEM LIMIT
// ===========================================================================

/** A 64-byte ISO base-media header: an `ftyp` box with [major] then [compatible]. */
function isoBaseMedia(major, compatible = []) {
  const brands = [major, '\0\0\0\0', ...compatible].join('');
  const boxSize = 8 + brands.length;
  const bytes = new Uint8Array(64);
  bytes.set([0, 0, 0, boxSize], 0);
  bytes.set([...'ftyp'].map((c) => c.charCodeAt(0)), 4);
  bytes.set([...brands].map((c) => c.charCodeAt(0)), 8);
  return bytes;
}

function box(type, payload) {
  const bytes = new Uint8Array(8 + payload.length);
  new DataView(bytes.buffer).setUint32(0, bytes.length);
  bytes.set([...type].map((c) => c.charCodeAt(0)), 4);
  bytes.set(payload, 8);
  return bytes;
}

/** A `moov` box whose `mvhd` declares [seconds] at a 1000 Hz timescale. */
function moovBox(seconds, { version = 0 } = {}) {
  const timescale = 1000;
  const duration = Math.round(seconds * timescale);
  const body = new Uint8Array(version === 1 ? 108 : 96);
  const view = new DataView(body.buffer);
  body[0] = version;
  const at = 4 + (version === 1 ? 16 : 8);
  view.setUint32(at, timescale);
  if (version === 1) {
    view.setUint32(at + 4, 0);
    view.setUint32(at + 8, duration);
  } else {
    view.setUint32(at + 4, duration);
  }
  return box('moov', box('mvhd', body));
}

function concat(...parts) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}

/** A complete, walkable video file: ftyp, then media data, then `moov` last —
 * the layout a phone camera actually writes. */
function videoFile(major, compatible, seconds = 30, options = {}) {
  const brands = [major, '    ', ...compatible].join('');
  return concat(
    box('ftyp', Uint8Array.from([...brands].map((c) => c.charCodeAt(0)))),
    box('mdat', new Uint8Array(64)),
    moovBox(seconds, options),
  );
}

const MP4_BYTES = videoFile('isom', ['isom', 'iso2', 'avc1', 'mp41']);
const SAMSUNG_MP4_BYTES = videoFile('mp42', ['isom', 'mp42']);
const MOV_BYTES = videoFile('qt  ', ['qt  ']);
const HEIC_BYTES = isoBaseMedia('heic', ['mif1', 'heic']);

async function authorize(ctx, userId, offerId, contentType, contentLength = 64) {
  return call(ctx, '/offer-media/authorize', {
    method: 'POST',
    authorization: `Bearer ${token(userId)}`,
    body: { offerId, contentType, contentLength },
  });
}

async function confirm(ctx, userId, offerId, mediaObjectId, extra = {}) {
  return call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(userId)}`,
    body: { offerId, mediaObjectId, ...extra },
  });
}

/** Authorizes [contentType], then stores [bytes] as the client PUT would. */
async function upload(ctx, contentType, bytes, contentLength = bytes.length) {
  const auth = await authorize(ctx, ALICE, OFFER_A, contentType, contentLength);
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  ctx.bucket.put(auth.body.objectKey, bytes, contentType);
  return auth.body;
}

async function confirmedItems(ctx, count) {
  for (let i = 0; i < count; i += 1) {
    const { mediaObjectId } = await upload(ctx, 'image/jpeg', JPEG_BYTES);
    const result = await confirm(ctx, ALICE, OFFER_A, mediaObjectId);
    assert.equal(result.status, 200, JSON.stringify(result.body));
  }
}

test('an MP4 video is authorized as a video, confirmed from its real bytes and listed as a video', async () => {
  const auth = await upload(ctx, 'video/mp4', MP4_BYTES, 60 * 1024 * 1024);
  assert.equal(auth.mediaType, 'video');
  assert.ok(auth.objectKey.endsWith(`/offers/${OFFER_A}/${auth.mediaObjectId}.mp4`));
  const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
  assert.equal(row.media_type, 'video');

  const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(row.status, 'ready');

  const list = await call(ctx, `/offer-media?offerId=${OFFER_A}`, { authorization: `Bearer ${token(ALICE)}` });
  assert.equal(list.status, 200);
  assert.equal(list.body.media.length, 1);
  assert.equal(list.body.media[0].mediaType, 'video');
  assert.equal(list.body.media[0].contentType, 'video/mp4');
});

test('Samsung (mp42) MP4 and iPhone QuickTime videos are both accepted', async () => {
  const samsung = await upload(ctx, 'video/mp4', SAMSUNG_MP4_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, samsung.mediaObjectId)).status, 200);

  const iphone = await upload(ctx, 'video/quicktime', MOV_BYTES);
  assert.ok(iphone.objectKey.endsWith('.mov'));
  assert.equal((await confirm(ctx, ALICE, OFFER_A, iphone.mediaObjectId)).status, 200);
});

test('size limits are per kind: videos up to 100 MB, images still 10 MB', async () => {
  assert.equal((await authorize(ctx, ALICE, OFFER_A, 'video/mp4', 100 * 1024 * 1024)).status, 200);

  const bigVideo = await authorize(ctx, ALICE, OFFER_A, 'video/mp4', 100 * 1024 * 1024 + 1);
  assert.equal(bigVideo.status, 400);
  assert.equal(bigVideo.body.code, 'video_too_large');

  const bigImage = await authorize(ctx, ALICE, OFFER_A, 'image/jpeg', 10 * 1024 * 1024 + 1);
  assert.equal(bigImage.status, 400);
  assert.equal(bigImage.body.code, 'image_too_large');
});

test('unsupported containers are refused before anything is created', async () => {
  for (const type of ['video/x-matroska', 'video/webm', 'application/pdf', 'video/MP4', 'toString']) {
    const result = await authorize(ctx, ALICE, OFFER_A, type);
    assert.equal(result.status, 400, type);
    assert.equal(result.body.code, 'unsupported_media_type', type);
  }
  assert.equal(ctx.supabase.mediaObjects.length, 0);
});

test('bytes that do not match the authorized type are rejected, marked failed and deleted', async () => {
  const cases = [
    ['video/mp4', JPEG_BYTES],
    ['video/mp4', HEIC_BYTES],
    ['video/quicktime', MP4_BYTES],
    ['image/jpeg', MP4_BYTES],
    ['video/mp4', new Uint8Array(64)],
  ];
  for (const [type, bytes] of cases) {
    const auth = await upload(ctx, type, bytes);
    const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);
    assert.equal(result.status, 422, `${type} with mismatching bytes`);
    const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
    assert.equal(row.status, 'failed');
    assert.equal(ctx.bucket.objects.has(auth.objectKey), false);
  }
  assert.equal(ctx.supabase.offerMedia.length, 0);
});

test('the Offer is linked into server-chosen slots; a client ordinal is ignored', async () => {
  const first = await upload(ctx, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, first.mediaObjectId, { ordinal: 7, role: 'cover' })).status, 200);
  const second = await upload(ctx, 'video/mp4', MP4_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, second.mediaObjectId, { ordinal: 0 })).status, 200);

  assert.deepEqual(
    ctx.supabase.offerMedia.map((link) => [link.role, link.ordinal]),
    [['gallery', 0], ['gallery', 1]],
  );
});

test('an 11th item is refused at authorize once 10 are attached', async () => {
  await confirmedItems(ctx, 10);
  const eleventh = await authorize(ctx, ALICE, OFFER_A, 'video/mp4');
  assert.equal(eleventh.status, 409);
  assert.equal(eleventh.body.code, 'offer_media_limit_reached');
  assert.equal(ctx.supabase.offerMedia.length, 10);
});

test('uploads still in flight count toward the limit', async () => {
  await confirmedItems(ctx, 8);
  await upload(ctx, 'video/mp4', MP4_BYTES);
  await upload(ctx, 'image/jpeg', JPEG_BYTES);
  const refused = await authorize(ctx, ALICE, OFFER_A, 'image/jpeg');
  assert.equal(refused.status, 409);
  assert.equal(refused.body.code, 'offer_media_limit_reached');
});

test('an abandoned pending upload older than the cleanup window stops counting', async () => {
  await confirmedItems(ctx, 9);
  const stale = await upload(ctx, 'video/mp4', MP4_BYTES);
  const row = ctx.supabase.mediaObjects.find((m) => m.id === stale.mediaObjectId);
  row.created_at = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();

  const fresh = await authorize(ctx, ALICE, OFFER_A, 'image/jpeg');
  assert.equal(fresh.status, 200, JSON.stringify(fresh.body));
  assert.equal(
    ctx.supabase.mediaObjects.some((m) => m.id === stale.mediaObjectId),
    false,
    'the abandoned upload was cleaned up',
  );
  assert.equal(ctx.bucket.objects.has(stale.objectKey), false);
});

test('concurrent confirms can never exceed 10: the loser is rejected and cleaned up', async () => {
  await confirmedItems(ctx, 8);
  const a = await upload(ctx, 'video/mp4', MP4_BYTES);
  const b = await upload(ctx, 'image/jpeg', JPEG_BYTES);
  // A ninth item is attached behind both uploads' backs (e.g. from a second
  // device), so only one slot is left for two confirms racing for it.
  ctx.supabase.offerMedia.push({ offer_id: OFFER_A, media_id: 'external', role: 'gallery', ordinal: 8 });

  const results = await Promise.all([
    confirm(ctx, ALICE, OFFER_A, a.mediaObjectId),
    confirm(ctx, ALICE, OFFER_A, b.mediaObjectId),
  ]);
  const statuses = results.map((r) => r.status).sort();
  assert.deepEqual(statuses, [200, 409]);
  const loser = results.find((r) => r.status === 409);
  assert.equal(loser.body.code, 'offer_media_limit_reached');

  assert.equal(ctx.supabase.offerMedia.length, 10, 'never more than 10 links');
  const ordinals = ctx.supabase.offerMedia.map((link) => link.ordinal).sort((x, y) => x - y);
  assert.deepEqual(ordinals, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const failed = ctx.supabase.mediaObjects.filter((m) => m.status === 'failed');
  assert.equal(failed.length, 1);
  assert.equal(ctx.bucket.objects.has(failed[0].object_key), false, 'the losing upload was deleted');
});

test('a retried confirm of an already-linked but not-ready item finishes without a second link', async () => {
  const auth = await upload(ctx, 'video/mp4', MP4_BYTES);
  ctx.supabase.offerMedia.push({ offer_id: OFFER_A, media_id: auth.mediaObjectId, role: 'gallery', ordinal: 0 });

  const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(ctx.supabase.offerMedia.length, 1);
  assert.equal(ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId).status, 'ready');
});

test('profile images stay image-only: /authorize still refuses a video', async () => {
  const result = await call(ctx, '/authorize', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { contentType: 'video/mp4', contentLength: 64 },
  });
  assert.equal(result.status, 400);
  assert.equal(ctx.supabase.mediaObjects.length, 0);
});

test('existing image object keys are unchanged', async () => {
  const auth = await upload(ctx, 'image/jpeg', JPEG_BYTES);
  assert.equal(auth.objectKey, `profiles/${ALICE}/offers/${OFFER_A}/${auth.mediaObjectId}.jpg`);
  assert.equal(auth.mediaType, 'image');
});

// ===========================================================================
// SERVER-SIDE VIDEO DURATION — the app's 3-minute check is a courtesy; this
// is the rule, and it binds any client.
// ===========================================================================

test('a video of exactly three minutes is accepted and its duration recorded',
  async () => {
    const auth = await upload(ctx, 'video/mp4', videoFile('isom', ['isom'], 180));
    const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);

    assert.equal(result.status, 200, JSON.stringify(result.body));
    const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
    assert.equal(row.status, 'ready');
    assert.equal(row.duration_ms, 180000, 'the measured duration is persisted');
  });

test('a video longer than three minutes is refused however it was uploaded',
  async () => {
    const auth = await upload(ctx, 'video/mp4', videoFile('isom', ['isom'], 185));
    const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);

    assert.equal(result.status, 422);
    assert.equal(result.body.code, 'video_too_long');
    const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
    assert.equal(row.status, 'failed', 'the over-long upload is not left usable');
    assert.equal(ctx.bucket.objects.has(auth.objectKey), false);
    assert.equal(ctx.supabase.offerMedia.length, 0, 'it was never attached');
  });

test('a clip a fraction over three minutes is still accepted: the tolerance '
  + 'absorbs encoder rounding, one second of it', async () => {
  const auth = await upload(ctx, 'video/mp4', videoFile('isom', ['isom'], 180.5));
  assert.equal((await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId)).status, 200);

  const over = await upload(ctx, 'video/mp4', videoFile('isom', ['isom'], 181.5));
  const refused = await confirm(ctx, ALICE, OFFER_A, over.mediaObjectId);
  assert.equal(refused.status, 422);
  assert.equal(refused.body.code, 'video_too_long');
});

test('the duration is read from a moov at the end of the file, and from a '
  + '64-bit mvhd', async () => {
  const cameraLayout = await upload(ctx, 'video/mp4', videoFile('mp42', ['isom'], 42));
  assert.equal((await confirm(ctx, ALICE, OFFER_A, cameraLayout.mediaObjectId)).status, 200);
  assert.equal(
    ctx.supabase.mediaObjects.find((m) => m.id === cameraLayout.mediaObjectId).duration_ms,
    42000,
  );

  const version1 = await upload(
    ctx,
    'video/quicktime',
    videoFile('qt  ', ['qt  '], 12, { version: 1 }),
  );
  assert.equal((await confirm(ctx, ALICE, OFFER_A, version1.mediaObjectId)).status, 200);
  assert.equal(
    ctx.supabase.mediaObjects.find((m) => m.id === version1.mediaObjectId).duration_ms,
    12000,
  );
});

test('a video whose structure carries no readable duration fails closed',
  async () => {
    // A well-formed ftyp and media data, but no moov: nothing proves how long
    // this is, so it is refused rather than accepted on trust.
    const auth = await upload(
      ctx,
      'video/mp4',
      concat(
        box('ftyp', Uint8Array.from([...'isomisom'].map((c) => c.charCodeAt(0)))),
        box('mdat', new Uint8Array(128)),
      ),
    );
    const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);

    assert.equal(result.status, 422);
    assert.equal(result.body.code, 'unsupported_media_type');
    assert.equal(
      ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId).status,
      'failed',
    );
  });

test('reading a duration never downloads the media data', async () => {
  // 40 MB of media data around a small moov: the walk must stay in the box
  // headers. The fake bucket records every ranged read it serves.
  const big = concat(
    box('ftyp', Uint8Array.from([...'isomisom'].map((c) => c.charCodeAt(0)))),
    box('mdat', new Uint8Array(40 * 1024 * 1024)),
    moovBox(30),
  );
  const auth = await upload(ctx, 'video/mp4', big);
  ctx.bucket.reads.length = 0;

  assert.equal((await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId)).status, 200);

  const total = ctx.bucket.reads.reduce((sum, read) => sum + read, 0);
  assert.ok(total < 4096, `read ${total} bytes, expected a few hundred`);
});

test('an image is never subjected to a duration check', async () => {
  const auth = await upload(ctx, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId)).status, 200);
  const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
  assert.equal(row.duration_ms, undefined, 'no duration is written for a photo');
});
