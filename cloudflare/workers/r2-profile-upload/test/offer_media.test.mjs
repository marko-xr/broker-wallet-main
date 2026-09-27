// Behavioural tests for the Offer Media routes:
//   POST /offer-media/authorize
//   POST /offer-media/confirm
//   GET  /offer-media
//   POST /offer-media/remove
// and for the scheduled Offer-media sweeps (runOfferMediaSweeps).
//
// Run with: npm test   (or a bare `node --test` from this directory)
//
// Tests go through the Worker's own real HTTP entrypoint (`worker.fetch`),
// not internal functions — Supabase Auth/PostgREST is an in-memory fake
// reached by temporarily replacing `globalThis.fetch` for the duration of
// each test, and the R2 binding is a small in-memory fake bucket. Assertions
// check observable state (row counts, field values, bucket contents), not
// merely that some helper was invoked.
//
// The database function `confirm_offer_media_upload` is emulated below with
// the same outcomes as its SQL. JavaScript runs each emulated call to
// completion, which stands in for the real function's lock on the Offer row;
// the SQL itself is exercised separately against a real database
// (supabase/validation/offer_media_confirm_validation.sql). These are local
// tests: they prove the Worker's logic, not hosted behaviour.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import worker, { runOfferMediaSweeps } from '../worker.js';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE = 'sb_publishable_test';
const SECRET = 'sb_secret_TEST_SECRET_VALUE';
const BUCKET = 'broker-wallet-media-staging';
// The other environment's bucket. Staging and production share one database,
// so rows from both appear side by side there.
const OTHER_BUCKET = 'broker-wallet-media';
const WORKER_ORIGIN = 'https://media-api.test';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
const OFFER_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
// A second Offer owned by Alice, and Bob's own Offer.
const OFFER_A2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const OFFER_BOB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

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

function isoAgo(ms) {
  return new Date(Date.now() - ms).toISOString();
}

/** Matches simple PostgREST filters: eq.x, is.null, lt.x and like.x* (with `*`
 * as the wildcard). Enough for these tests. */
function matches(rowValue, filter) {
  const dot = filter.indexOf('.');
  const op = filter.slice(0, dot);
  const operand = filter.slice(dot + 1);
  if (op === 'eq') return String(rowValue) === operand;
  if (op === 'is' && operand === 'null') return rowValue === null || rowValue === undefined;
  if (op === 'lt') {
    if (rowValue === null || rowValue === undefined) return false;
    return Date.parse(rowValue) < Date.parse(operand);
  }
  if (op === 'like') {
    const escaped = operand.split('*').map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    return new RegExp(`^${escaped.join('.*')}$`).test(String(rowValue ?? ''));
  }
  throw new Error(`unsupported filter ${filter}`);
}

const RESERVED_PARAMS = new Set(['select', 'order', 'limit', 'offset', 'on_conflict']);

/** Top-level filters only; `resource.column` filters apply to embeddings. */
function filterRows(rows, searchParams) {
  return rows.filter((row) =>
    [...searchParams.entries()].every(
      ([column, filter]) => RESERVED_PARAMS.has(column) || column.includes('.') || matches(row[column], filter),
    ),
  );
}

/** Applies `order=<column>.<asc|desc>` and `limit=<n>`. */
function orderAndLimit(rows, searchParams) {
  const result = [...rows];
  const order = searchParams.get('order');
  if (order) {
    const [column, direction = 'asc'] = order.split('.');
    result.sort((a, b) => {
      const left = a[column];
      const right = b[column];
      const compared = typeof left === 'number' && typeof right === 'number'
        ? left - right
        : String(left ?? '').localeCompare(String(right ?? ''));
      return direction === 'desc' ? -compared : compared;
    });
  }
  const limit = searchParams.get('limit');
  return limit === null ? result : result.slice(0, Number(limit));
}

function wantsRepresentation(headers) {
  return String(headers.Prefer ?? '').includes('return=representation');
}

/** A minimal in-memory Supabase REST + Auth fake for exactly what the Offer
 * Media routes and sweeps call. */
class FakeSupabase {
  constructor() {
    this.users = new Map([
      [ALICE, { id: ALICE }],
      [BOB, { id: BOB }],
    ]);
    this.validTokens = new Set([token(ALICE), token(BOB)]);
    this.offers = [
      { id: OFFER_A, owner_id: ALICE, deleted_at: null },
      { id: OFFER_A2, owner_id: ALICE, deleted_at: null },
      { id: OFFER_BOB, owner_id: BOB, deleted_at: null },
    ];
    this.mediaObjects = [];
    this.offerMedia = [];
    this.deletionJobs = [];
    this.calls = [];
    this.rpcCalls = [];
    this.failConfirmRpc = false;
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

    if (parsed.pathname === '/rest/v1/rpc/confirm_offer_media_upload') {
      assert.equal(method, 'POST');
      const params = JSON.parse(init.body);
      this.rpcCalls.push(params);
      if (this.failConfirmRpc) return json({ message: 'simulated database failure' }, 500);
      return json([this.confirmOfferMediaUpload(params)]);
    }

    if (parsed.pathname === '/rest/v1/account_deletion_jobs') {
      return json(filterRows(this.deletionJobs, parsed.searchParams));
    }

    if (parsed.pathname === '/rest/v1/offers') {
      return json(filterRows(this.offers, parsed.searchParams));
    }

    if (parsed.pathname === '/rest/v1/media_objects') {
      if (method === 'POST') {
        const body = JSON.parse(init.body);
        // Primary key: a second insert of the same id is refused.
        if (this.mediaObjects.some((row) => row.id === body.id)) return json({ code: '23505' }, 409);
        const at = new Date().toISOString();
        this.mediaObjects.push({ created_at: at, updated_at: at, ...body });
        return json([], 201);
      }
      if (method === 'GET') {
        return json(orderAndLimit(filterRows(this.mediaObjects, parsed.searchParams), parsed.searchParams));
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(init.body);
        const rows = filterRows(this.mediaObjects, parsed.searchParams);
        for (const row of rows) Object.assign(row, patch, { updated_at: new Date().toISOString() });
        return json(wantsRepresentation(headers) ? rows.map((row) => ({ ...row })) : [], 200);
      }
      if (method === 'DELETE') {
        const doomed = filterRows(this.mediaObjects, parsed.searchParams);
        this.mediaObjects = this.mediaObjects.filter((row) => !doomed.includes(row));
        // FK: offer_media.media_id references media_objects ON DELETE CASCADE.
        const gone = new Set(doomed.map((row) => row.id));
        this.offerMedia = this.offerMedia.filter((link) => !gone.has(link.media_id));
        return json(wantsRepresentation(headers) ? doomed.map((row) => ({ ...row })) : [], 200);
      }
    }

    if (parsed.pathname === '/rest/v1/offer_media') {
      if (method === 'POST') {
        // Only legacy test fixtures insert links directly now; the Worker
        // attaches through the database function.
        const body = JSON.parse(init.body);
        this.offerMedia.push({ ...body });
        return json([], 201);
      }
      if (method === 'GET') {
        const select = parsed.searchParams.get('select') ?? '';
        let rows = filterRows(this.offerMedia, parsed.searchParams).map((link) => ({
          link,
          media: this.mediaObjects.find((m) => m.id === link.media_id) ?? null,
          offer: this.offers.find((o) => o.id === link.offer_id) ?? null,
        }));
        for (const [key, filter] of parsed.searchParams.entries()) {
          if (!key.includes('.')) continue;
          const [resource, column] = key.split('.');
          const pick = resource === 'offers' ? (row) => row.offer : (row) => row.media;
          rows = rows.filter((row) => pick(row) !== null && matches(pick(row)[column], filter));
        }
        if (select.includes('media_objects!inner')) rows = rows.filter((row) => row.media !== null);
        if (select.includes('offers!inner')) rows = rows.filter((row) => row.offer !== null);
        const shaped = rows.map(({ link, media, offer }) => ({
          ...link,
          media_objects: media ? { ...media } : null,
          offers: offer ? { ...offer } : null,
        }));
        return json(orderAndLimit(shaped, parsed.searchParams));
      }
      if (method === 'DELETE') {
        const doomed = filterRows(this.offerMedia, parsed.searchParams);
        this.offerMedia = this.offerMedia.filter((link) => !doomed.includes(link));
        return json([], 200);
      }
    }

    throw new Error(`unexpected request ${method} ${parsed.pathname}`);
  };

  /** Mirrors the SQL of `confirm_offer_media_upload`, outcome for outcome. */
  confirmOfferMediaUpload(p) {
    const offer = this.offers.find(
      (o) => o.id === p.p_offer_id && o.owner_id === p.p_user_id && (o.deleted_at === null || o.deleted_at === undefined),
    );
    if (!offer) return { outcome: 'offer_not_found', media_ordinal: null };

    const prefix = `profiles/${p.p_user_id}/offers/${p.p_offer_id}/`;
    const media = this.mediaObjects.find(
      (m) => m.id === p.p_media_id && m.owner_id === p.p_user_id && m.bucket === p.p_bucket,
    );
    if (!media || !String(media.object_key).startsWith(prefix)) {
      return { outcome: 'media_not_found', media_ordinal: null };
    }

    const readyFields = {
      status: 'ready',
      size_bytes: p.p_observed_size,
      content_type: p.p_observed_content_type,
      duration_ms: p.p_duration_ms,
      updated_at: new Date().toISOString(),
    };
    const existing = this.offerMedia.find((l) => l.offer_id === p.p_offer_id && l.media_id === p.p_media_id);
    if (existing) {
      if (media.status === 'pending_upload') Object.assign(media, readyFields);
      return { outcome: 'already_attached', media_ordinal: existing.ordinal };
    }
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status', media_ordinal: null };

    const ready = this.offerMedia.filter((l) => {
      if (l.offer_id !== p.p_offer_id) return false;
      const m = this.mediaObjects.find((x) => x.id === l.media_id);
      return m && m.bucket === p.p_bucket && m.status === 'ready';
    }).length;
    if (ready >= p.p_max_items) return { outcome: 'limit_reached', media_ordinal: null };

    const gallery = this.offerMedia.filter((l) => l.offer_id === p.p_offer_id && l.role === 'gallery');
    const ordinal = gallery.length === 0 ? 0 : Math.max(...gallery.map((l) => l.ordinal)) + 1;
    this.offerMedia.push({ offer_id: p.p_offer_id, media_id: p.p_media_id, role: 'gallery', ordinal });
    Object.assign(media, readyFields);
    return { outcome: 'attached', media_ordinal: ordinal };
  }

  callsTo(path, method) {
    return this.calls.filter((call) => call.path === path && (!method || call.method === method));
  }
}

/** A minimal in-memory R2 bucket fake supporting what the Offer Media routes
 * need (head/get by key, delete), with delete failures on demand. */
class FakeBucket {
  constructor() {
    this.objects = new Map();
    this.reads = [];
    this.failDeletes = false;
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
    if (this.failDeletes) throw new Error('simulated R2 failure');
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
 * real client PUT would have left it) one Offer image for [userId], the way
 * an older app build does: without its own media id. */
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

  const afterFirst = { ...ctx.supabase.mediaObjects.find((row) => row.id === mediaObjectId) };
  assert.equal(afterFirst.status, 'ready');
  assert.equal(ctx.supabase.offerMedia.length, 1, 'exactly one association after the first confirm');

  const second = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  assert.equal(second.status, 200);
  assert.equal(second.body.alreadyConfirmed, true);
  assert.equal(second.body.ordinal, first.body.ordinal);

  // Observable state, not call counts: still exactly one association, media
  // object state unchanged by the retry.
  assert.equal(ctx.supabase.offerMedia.length, 1, 'the retry created no second association');
  const afterSecond = ctx.supabase.mediaObjects.find((row) => row.id === mediaObjectId);
  assert.equal(afterSecond.status, 'ready');
  assert.deepEqual(afterSecond, afterFirst, 'the media row is byte-identical after the idempotent retry');
});

// ===========================================================================
// TEST 3 — a failed attach loses nothing and is retryable
// ===========================================================================

test('a failed attach leaves the upload pending and retryable: nothing ready, nothing linked, nothing lost', async () => {
  const mediaObjectId = await authorizeAndUpload(ctx, ALICE, OFFER_A);
  const key = `profiles/${ALICE}/offers/${OFFER_A}/${mediaObjectId}.jpg`;
  ctx.supabase.failConfirmRpc = true;

  const failed = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  // 502: a transport/database failure, not a verdict on the upload.
  assert.equal(failed.status, 502);
  const row = ctx.supabase.mediaObjects.find((m) => m.id === mediaObjectId);
  assert.equal(row.status, 'pending_upload', 'never ready without its attachment');
  assert.equal(ctx.supabase.offerMedia.length, 0, 'no association exists');
  assert.equal(ctx.bucket.objects.has(key), true, 'the uploaded bytes are kept for the retry');

  ctx.supabase.failConfirmRpc = false;
  const retried = await call(ctx, '/offer-media/confirm', {
    method: 'POST',
    authorization: `Bearer ${token(ALICE)}`,
    body: { offerId: OFFER_A, mediaObjectId },
  });
  assert.equal(retried.status, 200, JSON.stringify(retried.body));
  assert.equal(row.status, 'ready');
  assert.equal(ctx.supabase.offerMedia.length, 1);
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
  const brands = [major, '\0\0\0\0', ...compatible].join('');
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

/** A ready item attached directly in the database, e.g. by the other
 * environment's Worker or by another device before this test's requests. */
function seedReadyMedia(ctx, { ownerId = ALICE, offerId = OFFER_A, bucket = BUCKET, ordinal, contentType = 'image/jpeg' }) {
  const id = crypto.randomUUID();
  const extension = { 'image/jpeg': 'jpg', 'image/heic': 'heic', 'video/mp4': 'mp4' }[contentType];
  const objectKey = `profiles/${ownerId}/offers/${offerId}/${id}.${extension}`;
  const at = new Date().toISOString();
  ctx.supabase.mediaObjects.push({
    id,
    owner_id: ownerId,
    bucket,
    object_key: objectKey,
    media_type: contentType.startsWith('video/') ? 'video' : 'image',
    content_type: contentType,
    size_bytes: 64,
    status: 'ready',
    created_at: at,
    updated_at: at,
  });
  ctx.supabase.offerMedia.push({ offer_id: offerId, media_id: id, role: 'gallery', ordinal });
  if (bucket === BUCKET) ctx.bucket.put(objectKey, JPEG_BYTES, contentType);
  return { id, objectKey };
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

test('an upload larger than it declared is refused at confirm by its real size', async () => {
  const image = await upload(ctx, 'image/jpeg', concat(JPEG_BYTES, new Uint8Array(10 * 1024 * 1024)), 64);
  const imageResult = await confirm(ctx, ALICE, OFFER_A, image.mediaObjectId);
  assert.equal(imageResult.status, 422);
  assert.equal(imageResult.body.code, 'image_too_large');
  assert.equal(ctx.bucket.objects.has(image.objectKey), false);

  const video = await upload(ctx, 'video/mp4', concat(MP4_BYTES, new Uint8Array(100 * 1024 * 1024)), 64);
  const videoResult = await confirm(ctx, ALICE, OFFER_A, video.mediaObjectId);
  assert.equal(videoResult.status, 422);
  assert.equal(videoResult.body.code, 'video_too_large');
  assert.equal(ctx.supabase.mediaObjects.find((m) => m.id === video.mediaObjectId).status, 'failed');
  assert.equal(ctx.supabase.offerMedia.length, 0);
});

test('unsupported containers are refused before anything is created', async () => {
  for (const type of ['video/x-matroska', 'video/webm', 'application/pdf', 'video/MP4', 'toString', 'image/heic']) {
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
    ['image/jpeg', HEIC_BYTES],
    ['video/mp4', new Uint8Array(64)],
  ];
  for (const [type, bytes] of cases) {
    const auth = await upload(ctx, type, bytes);
    const result = await confirm(ctx, ALICE, OFFER_A, auth.mediaObjectId);
    assert.equal(result.status, 422, `${type} with mismatching bytes`);
    assert.equal(result.body.code, 'media_type_mismatch');
    const row = ctx.supabase.mediaObjects.find((m) => m.id === auth.mediaObjectId);
    assert.equal(row.status, 'failed');
    assert.equal(ctx.bucket.objects.has(auth.objectKey), false);
  }
  assert.equal(ctx.supabase.offerMedia.length, 0);
});

test('the Offer is linked at server-chosen positions; a client ordinal is ignored', async () => {
  const first = await upload(ctx, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, first.mediaObjectId, { ordinal: 7, role: 'cover' })).status, 200);
  const second = await upload(ctx, 'video/mp4', MP4_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, second.mediaObjectId, { ordinal: 0 })).status, 200);

  assert.deepEqual(
    ctx.supabase.offerMedia.map((link) => [link.role, link.ordinal]),
    [['gallery', 0], ['gallery', 1]],
  );
  // The Worker hands the database function this environment's bucket and
  // the product limit; nothing from the client.
  assert.equal(ctx.supabase.rpcCalls[0].p_bucket, BUCKET);
  assert.equal(ctx.supabase.rpcCalls[0].p_max_items, 10);
  assert.equal(ctx.supabase.rpcCalls[0].p_user_id, ALICE);
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
  row.created_at = isoAgo(25 * HOUR_MS);

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
  // device), so only one place is left for two confirms racing for it.
  seedReadyMedia(ctx, { ordinal: 8 });

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
  // A state only an older Worker version could leave behind.
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
  assert.equal(row.duration_ms ?? null, null, 'no duration is written for a photo');
});

// ===========================================================================
// IDEMPOTENT LIFECYCLE — the app's own media id is the identity end to end
// ===========================================================================

function newId() {
  return crypto.randomUUID();
}

async function authorizeId(ctx, {
  userId = ALICE,
  offerId = OFFER_A,
  mediaObjectId,
  contentType = 'image/jpeg',
  contentLength = JPEG_BYTES.length,
} = {}) {
  return call(ctx, '/offer-media/authorize', {
    method: 'POST',
    authorization: `Bearer ${token(userId)}`,
    body: { offerId, mediaObjectId, contentType, contentLength },
  });
}

/** One logical upload under [mediaObjectId]: authorize, then the PUT's bytes. */
async function uploadWithId(ctx, mediaObjectId, contentType, bytes, { offerId = OFFER_A } = {}) {
  const auth = await authorizeId(ctx, { offerId, mediaObjectId, contentType, contentLength: bytes.length });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  if (auth.body.status === 'pending') ctx.bucket.put(auth.body.objectKey, bytes, contentType);
  return auth.body;
}

async function remove(ctx, userId, offerId, mediaObjectId) {
  return call(ctx, '/offer-media/remove', {
    method: 'POST',
    authorization: `Bearer ${token(userId)}`,
    body: { offerId, mediaObjectId },
  });
}

async function list(ctx, userId = ALICE, offerId = OFFER_A) {
  return call(ctx, `/offer-media?offerId=${offerId}`, { authorization: `Bearer ${token(userId)}` });
}

const rowOf = (id) => ctx.supabase.mediaObjects.find((m) => m.id === id);
const linksOf = (id) => ctx.supabase.offerMedia.filter((l) => l.media_id === id);

test('image lifecycle: the app\'s id becomes the row, the key and the listed item', async () => {
  const id = newId();
  const auth = await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal(auth.status, 'pending');
  assert.equal(auth.mediaObjectId, id);
  assert.equal(auth.objectKey, `profiles/${ALICE}/offers/${OFFER_A}/${id}.jpg`);
  assert.ok(auth.presignedUrl.startsWith('https://r2.test.example.com/'));
  assert.equal(auth.expiresInSeconds, 300, 'the upload authorization keeps its 300-second lifetime');

  const confirmed = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.equal(confirmed.body.ordinal, 0);
  assert.equal(rowOf(id).status, 'ready');
  assert.equal(ctx.supabase.mediaObjects.length, 1);
  assert.equal(linksOf(id).length, 1);

  const listed = await list(ctx);
  assert.equal(listed.status, 200);
  assert.equal(listed.body.expiresInSeconds, 900);
  assert.deepEqual(
    listed.body.media.map((m) => [m.mediaObjectId, m.mediaType, m.durationMs]),
    [[id, 'image', null]],
  );
});

test('video lifecycle: the measured duration is recorded and listed', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'video/mp4', videoFile('isom', ['isom'], 30));
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);
  const listed = await list(ctx);
  assert.deepEqual(
    listed.body.media.map((m) => [m.mediaObjectId, m.mediaType, m.contentType, m.durationMs]),
    [[id, 'video', 'video/mp4', 30000]],
  );
});

test('mixed photos and videos keep the order they were confirmed in', async () => {
  const ids = [newId(), newId(), newId()];
  await uploadWithId(ctx, ids[0], 'image/jpeg', JPEG_BYTES);
  await uploadWithId(ctx, ids[1], 'video/quicktime', MOV_BYTES);
  await uploadWithId(ctx, ids[2], 'image/jpeg', JPEG_BYTES);
  for (const id of ids) assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);

  const listed = await list(ctx);
  assert.deepEqual(
    listed.body.media.map((m) => [m.mediaObjectId, m.mediaType, m.ordinal]),
    [[ids[0], 'image', 0], [ids[1], 'video', 1], [ids[2], 'image', 2]],
  );
});

test('retrying authorize with the same id resumes the same row and key, never a second object', async () => {
  const id = newId();
  const first = await authorizeId(ctx, { mediaObjectId: id });
  const second = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(second.body.status, 'pending');
  assert.equal(second.body.objectKey, first.body.objectKey);
  assert.ok(second.body.presignedUrl, 'a fresh upload URL for the same key');
  assert.equal(ctx.supabase.mediaObjects.length, 1, 'still exactly one media object');
});

test('an interrupted upload is resumed under the same id and attached exactly once', async () => {
  const id = newId();
  assert.equal((await authorizeId(ctx, { mediaObjectId: id })).status, 200);

  // The PUT never arrived.
  const early = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(early.status, 409);
  assert.equal(early.body.code, 'upload_incomplete');
  assert.equal(rowOf(id).status, 'pending_upload', 'not failed: the same id can still succeed');
  assert.equal(linksOf(id).length, 0);

  const resumed = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(resumed.status, 200);
  ctx.bucket.put(resumed.body.objectKey, JPEG_BYTES, 'image/jpeg');
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);

  const again = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyConfirmed, true);
  assert.equal(ctx.supabase.mediaObjects.length, 1);
  assert.equal(linksOf(id).length, 1);
});

test('once an item is ready, retrying the whole upload skips the PUT and duplicates nothing', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);

  const retry = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.status, 'ready');
  assert.equal(retry.body.presignedUrl, undefined, 'nothing to upload again');
  assert.equal(ctx.supabase.mediaObjects.length, 1);
  assert.equal(ctx.supabase.offerMedia.length, 1);
});

test('an id can never be reused for a different Offer, type or size', async () => {
  const id = newId();
  assert.equal((await authorizeId(ctx, { mediaObjectId: id })).status, 200);
  const before = { ...rowOf(id) };

  for (const changed of [{ offerId: OFFER_A2 }, { contentType: 'image/png' }, { contentLength: JPEG_BYTES.length + 1 }]) {
    const result = await authorizeId(ctx, { mediaObjectId: id, ...changed });
    assert.equal(result.status, 409, JSON.stringify(changed));
    assert.equal(result.body.code, 'idempotency_mismatch');
  }
  assert.deepEqual(rowOf(id), before, 'the original row is untouched');
  assert.equal(ctx.supabase.mediaObjects.length, 1);
});

test('another account can never take over an id that is already in use', async () => {
  const id = newId();
  assert.equal((await authorizeId(ctx, { mediaObjectId: id })).status, 200);
  const before = { ...rowOf(id) };

  const bob = await authorizeId(ctx, { userId: BOB, offerId: OFFER_BOB, mediaObjectId: id });
  assert.equal(bob.status, 409);
  assert.equal(bob.body.code, 'media_id_conflict');
  assert.equal(bob.body.presignedUrl, undefined);
  assert.deepEqual(rowOf(id), before);
  assert.equal(ctx.supabase.mediaObjects.length, 1);
});

test('a rejected upload is final for its id', async () => {
  const id = newId();
  const auth = await uploadWithId(ctx, id, 'image/jpeg', MP4_BYTES);
  const rejected = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(rejected.status, 422);
  assert.equal(rowOf(id).status, 'failed');
  assert.equal(ctx.bucket.objects.has(auth.objectKey), false);

  const reauthorized = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(reauthorized.status, 409);
  assert.equal(reauthorized.body.code, 'upload_rejected');
  const reconfirmed = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(reconfirmed.status, 409);
  assert.equal(reconfirmed.body.code, 'upload_rejected');
  assert.equal(ctx.supabase.offerMedia.length, 0);
});

test('malformed ids are refused and ids are canonicalized to lower case', async () => {
  const bad = await authorizeId(ctx, { mediaObjectId: 'not-a-uuid' });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.code, 'invalid_request');
  assert.equal(ctx.supabase.mediaObjects.length, 0);

  const id = newId();
  const upper = await authorizeId(ctx, { offerId: OFFER_A.toUpperCase(), mediaObjectId: id.toUpperCase() });
  assert.equal(upper.status, 200, JSON.stringify(upper.body));
  assert.equal(upper.body.mediaObjectId, id);
  assert.equal(upper.body.objectKey, `profiles/${ALICE}/offers/${OFFER_A}/${id}.jpg`);
  ctx.bucket.put(upper.body.objectKey, JPEG_BYTES, 'image/jpeg');
  assert.equal((await confirm(ctx, ALICE, OFFER_A.toUpperCase(), id.toUpperCase())).status, 200);
  assert.equal(rowOf(id).status, 'ready');
});

test('an account being deleted gets no upload URL, new or resumed', async () => {
  const id = newId();
  assert.equal((await authorizeId(ctx, { mediaObjectId: id })).status, 200);
  ctx.supabase.deletionJobs.push({ user_id: ALICE, bucket: BUCKET, status: 'quarantined' });

  const resumed = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(resumed.status, 409);
  assert.equal(resumed.body.code, 'deletion_in_progress');
  assert.equal(rowOf(id).status, 'pending_upload', 'a resumed row is kept, not withdrawn');

  const freshId = newId();
  const fresh = await authorizeId(ctx, { mediaObjectId: freshId });
  assert.equal(fresh.status, 409);
  assert.equal(fresh.body.code, 'deletion_in_progress');
  assert.equal(rowOf(freshId), undefined, 'a row created by the refused request is withdrawn');
});

test('HEIC is refused for new Offer uploads, but HEIC stored earlier still lists', async () => {
  const refused = await authorizeId(ctx, { mediaObjectId: newId(), contentType: 'image/heic' });
  assert.equal(refused.status, 400);
  assert.equal(refused.body.code, 'unsupported_media_type');
  assert.equal(ctx.supabase.mediaObjects.length, 0);

  const legacy = seedReadyMedia(ctx, { ordinal: 0, contentType: 'image/heic' });
  const listed = await list(ctx);
  assert.deepEqual(listed.body.media.map((m) => [m.mediaObjectId, m.contentType]), [[legacy.id, 'image/heic']]);
});

// ===========================================================================
// REMOVAL
// ===========================================================================

test('removing a ready item unlinks it, deletes its bytes, tombstones it and frees its place', async () => {
  await confirmedItems(ctx, 10);
  const victim = (await list(ctx)).body.media[3];
  const key = rowOf(victim.mediaObjectId).object_key;

  const removed = await remove(ctx, ALICE, OFFER_A, victim.mediaObjectId);
  assert.equal(removed.status, 200, JSON.stringify(removed.body));
  assert.equal(removed.body.removed, true);
  assert.equal(removed.body.cleanupPending, undefined);
  assert.equal(rowOf(victim.mediaObjectId).status, 'deleted');
  assert.ok(rowOf(victim.mediaObjectId).deleted_at);
  assert.equal(linksOf(victim.mediaObjectId).length, 0);
  assert.equal(ctx.bucket.objects.has(key), false);
  assert.equal((await list(ctx)).body.media.length, 9);

  const eleventh = await authorize(ctx, ALICE, OFFER_A, 'image/jpeg');
  assert.equal(eleventh.status, 200, 'the removal freed a place');

  const again = await remove(ctx, ALICE, OFFER_A, victim.mediaObjectId);
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyRemoved, true);
});

test('a removed item\'s id is final', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);
  assert.equal((await remove(ctx, ALICE, OFFER_A, id)).status, 200);

  const reauthorized = await authorizeId(ctx, { mediaObjectId: id });
  assert.equal(reauthorized.status, 410);
  assert.equal(reauthorized.body.code, 'media_removed');
  const reconfirmed = await confirm(ctx, ALICE, OFFER_A, id);
  assert.equal(reconfirmed.status, 410);
  assert.equal(ctx.supabase.offerMedia.length, 0);
});

test('cancelling a queued upload withdraws its row and bytes and frees its place', async () => {
  await confirmedItems(ctx, 9);
  const id = newId();
  const auth = await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);

  const full = await authorizeId(ctx, { mediaObjectId: newId() });
  assert.equal(full.status, 409, 'the queued upload holds the tenth place');
  assert.equal(full.body.code, 'offer_media_limit_reached');

  const cancelled = await remove(ctx, ALICE, OFFER_A, id);
  assert.equal(cancelled.status, 200);
  assert.equal(rowOf(id), undefined);
  assert.equal(ctx.bucket.objects.has(auth.objectKey), false);

  assert.equal((await authorizeId(ctx, { mediaObjectId: newId() })).status, 200);
});

test('removing a failed upload deletes its row', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'image/jpeg', MP4_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 422);
  assert.equal((await remove(ctx, ALICE, OFFER_A, id)).status, 200);
  assert.equal(rowOf(id), undefined);
});

test('removal is scoped to the caller\'s own media on the named Offer', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);

  const onAlicesOffer = await remove(ctx, BOB, OFFER_A, id);
  assert.equal(onAlicesOffer.status, 404);
  assert.equal(onAlicesOffer.body.code, 'offer_not_found');

  // Bob naming Alice's media on his own Offer learns nothing and changes nothing.
  const onBobsOffer = await remove(ctx, BOB, OFFER_BOB, id);
  assert.equal(onBobsOffer.status, 200);
  assert.equal(onBobsOffer.body.alreadyRemoved, true);

  // Alice naming the item under a different one of her Offers is refused.
  const wrongOffer = await remove(ctx, ALICE, OFFER_A2, id);
  assert.equal(wrongOffer.status, 409);
  assert.equal(wrongOffer.body.code, 'media_mismatch');

  assert.equal(rowOf(id).status, 'ready');
  assert.equal(linksOf(id).length, 1);
});

test('a removal whose R2 delete fails is reported, hidden at once, and finished by the sweep', async () => {
  const id = newId();
  const auth = await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);

  ctx.bucket.failDeletes = true;
  const removed = await remove(ctx, ALICE, OFFER_A, id);
  assert.equal(removed.status, 200);
  assert.equal(removed.body.cleanupPending, true);
  assert.equal(rowOf(id).status, 'pending_delete');
  assert.equal(linksOf(id).length, 0);
  assert.equal((await list(ctx)).body.media.length, 0, 'no longer listed');

  ctx.bucket.failDeletes = false;
  ctx.env.OFFER_MEDIA_SWEEP_MODE = 'on';
  const report = await runOfferMediaSweeps(ctx.env);
  assert.equal(report.pendingDeletes, 1);
  assert.equal(rowOf(id).status, 'deleted');
  assert.equal(ctx.bucket.objects.has(auth.objectKey), false);
});

test('a new item after a removal goes to the end, never into the gap', async () => {
  const ids = [newId(), newId(), newId()];
  for (const id of ids) {
    await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
    assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);
  }
  assert.equal((await remove(ctx, ALICE, OFFER_A, ids[1])).status, 200);

  const latest = newId();
  await uploadWithId(ctx, latest, 'video/mp4', MP4_BYTES);
  const confirmed = await confirm(ctx, ALICE, OFFER_A, latest);
  assert.equal(confirmed.body.ordinal, 3);

  assert.deepEqual((await list(ctx)).body.media.map((m) => m.mediaObjectId), [ids[0], ids[2], latest]);
});

test('media in the other environment\'s bucket is neither counted nor listed', async () => {
  for (let ordinal = 0; ordinal < 9; ordinal += 1) {
    seedReadyMedia(ctx, { bucket: OTHER_BUCKET, ordinal });
  }
  await confirmedItems(ctx, 10);

  const listed = await list(ctx);
  assert.equal(listed.body.media.length, 10);
  assert.ok(listed.body.media.every((m) => rowOf(m.mediaObjectId).bucket === BUCKET));
  assert.deepEqual(listed.body.media.map((m) => m.ordinal), [9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
  assert.equal((await authorize(ctx, ALICE, OFFER_A, 'image/jpeg')).status, 409);
});

test('every route refuses a soft-deleted Offer', async () => {
  const id = newId();
  await uploadWithId(ctx, id, 'image/jpeg', JPEG_BYTES);
  assert.equal((await confirm(ctx, ALICE, OFFER_A, id)).status, 200);
  ctx.supabase.offers.find((o) => o.id === OFFER_A).deleted_at = new Date().toISOString();

  for (const result of [
    await authorizeId(ctx, { mediaObjectId: newId() }),
    await confirm(ctx, ALICE, OFFER_A, id),
    await list(ctx),
    await remove(ctx, ALICE, OFFER_A, id),
  ]) {
    assert.equal(result.status, 404);
    assert.equal(result.body.code, 'offer_not_found');
  }
  assert.equal(rowOf(id).status, 'ready', 'kept until the retention sweep');
});

// ===========================================================================
// SCHEDULED SWEEPS — ship OFF; dry_run only counts; on applies
// ===========================================================================

/** The scenario every sweep test starts from. */
function seedSweepScenario(ctx) {
  const stalePending = { id: newId(), created: isoAgo(25 * HOUR_MS) };
  const freshPending = { id: newId(), created: isoAgo(HOUR_MS) };
  const staleProfilePending = { id: newId(), created: isoAgo(25 * HOUR_MS) };
  const otherBucketPending = { id: newId(), created: isoAgo(25 * HOUR_MS) };
  const oldFailed = { id: newId(), updated: isoAgo(8 * DAY_MS) };
  const recentFailed = { id: newId(), updated: isoAgo(DAY_MS) };

  const push = (id, fields) => {
    ctx.supabase.mediaObjects.push({
      id,
      owner_id: ALICE,
      bucket: BUCKET,
      object_key: `profiles/${ALICE}/offers/${OFFER_A}/${id}.jpg`,
      media_type: 'image',
      content_type: 'image/jpeg',
      size_bytes: 64,
      created_at: isoAgo(HOUR_MS),
      updated_at: isoAgo(HOUR_MS),
      ...fields,
    });
    const row = ctx.supabase.mediaObjects.at(-1);
    if (row.status === 'pending_upload') ctx.bucket.put(row.object_key, JPEG_BYTES, 'image/jpeg');
    return row;
  };
  push(stalePending.id, { status: 'pending_upload', created_at: stalePending.created });
  push(freshPending.id, { status: 'pending_upload', created_at: freshPending.created });
  push(staleProfilePending.id, {
    status: 'pending_upload',
    created_at: staleProfilePending.created,
    object_key: `profiles/${ALICE}/${staleProfilePending.id}.jpg`,
  });
  push(otherBucketPending.id, { status: 'pending_upload', created_at: otherBucketPending.created, bucket: OTHER_BUCKET });
  push(oldFailed.id, { status: 'failed', updated_at: oldFailed.updated });
  push(recentFailed.id, { status: 'failed', updated_at: recentFailed.updated });

  // Offer A deleted 8 days ago, Offer A2 deleted 6 days ago, each with one
  // ready item.
  const oldOfferMedia = seedReadyMedia(ctx, { offerId: OFFER_A, ordinal: 0 });
  const recentOfferMedia = seedReadyMedia(ctx, { offerId: OFFER_A2, ordinal: 0 });
  ctx.supabase.offers.find((o) => o.id === OFFER_A).deleted_at = isoAgo(8 * DAY_MS);
  ctx.supabase.offers.find((o) => o.id === OFFER_A2).deleted_at = isoAgo(6 * DAY_MS);

  return {
    stalePending,
    freshPending,
    staleProfilePending,
    otherBucketPending,
    oldFailed,
    recentFailed,
    oldOfferMedia,
    recentOfferMedia,
  };
}

function snapshot(ctx) {
  return JSON.stringify({
    media: ctx.supabase.mediaObjects,
    links: ctx.supabase.offerMedia,
    objects: [...ctx.bucket.objects.keys()].sort(),
  });
}

test('sweeps do nothing at all unless explicitly configured', async () => {
  seedSweepScenario(ctx);
  const before = snapshot(ctx);
  for (const mode of [undefined, '', 'OFF', 'yes', 'true', 'off']) {
    ctx.env.OFFER_MEDIA_SWEEP_MODE = mode;
    const callsBefore = ctx.supabase.calls.length;
    const report = await runOfferMediaSweeps(ctx.env);
    assert.equal(report.mode, 'off', String(mode));
    assert.equal(ctx.supabase.calls.length, callsBefore, `no database call in mode ${String(mode)}`);
  }
  assert.equal(snapshot(ctx), before);
});

test('dry_run counts what it would do and changes nothing', async () => {
  seedSweepScenario(ctx);
  const before = snapshot(ctx);
  ctx.env.OFFER_MEDIA_SWEEP_MODE = 'dry_run';

  const report = await runOfferMediaSweeps(ctx.env);
  assert.deepEqual(report, {
    mode: 'dry_run',
    abandonedUploads: 1,
    deletedOfferMedia: 1,
    pendingDeletes: 0,
    failedUploads: 1,
    errors: 0,
  });
  assert.equal(snapshot(ctx), before, 'nothing was changed');
  for (const call of ctx.supabase.calls.filter((c) => c.path.startsWith('/rest/'))) {
    assert.equal(call.method, 'GET', 'a dry run only reads');
  }
});

test('on: only what the lifecycle names is removed, in this bucket, for Offer media', async () => {
  const s = seedSweepScenario(ctx);
  ctx.env.OFFER_MEDIA_SWEEP_MODE = 'on';

  const logged = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args) => logged.push(args.join(' '));
  console.error = (...args) => logged.push(args.join(' '));
  let report;
  try {
    report = await runOfferMediaSweeps(ctx.env);
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }

  assert.deepEqual(report, {
    mode: 'on',
    abandonedUploads: 1,
    deletedOfferMedia: 1,
    pendingDeletes: 1,
    failedUploads: 1,
    errors: 0,
  });

  // Abandoned for over a day: gone with its bytes.
  assert.equal(rowOf(s.stalePending.id), undefined);
  assert.equal(ctx.bucket.objects.has(`profiles/${ALICE}/offers/${OFFER_A}/${s.stalePending.id}.jpg`), false);
  // Recent, profile-image and other-bucket pending rows: untouched.
  assert.equal(rowOf(s.freshPending.id).status, 'pending_upload');
  assert.equal(rowOf(s.staleProfilePending.id).status, 'pending_upload');
  assert.equal(rowOf(s.otherBucketPending.id).status, 'pending_upload');

  // Media of the Offer deleted 8 days ago: unlinked, bytes gone, tombstoned.
  assert.equal(rowOf(s.oldOfferMedia.id).status, 'deleted');
  assert.equal(linksOf(s.oldOfferMedia.id).length, 0);
  assert.equal(ctx.bucket.objects.has(s.oldOfferMedia.objectKey), false);
  // The Offer deleted 6 days ago keeps its media for now.
  assert.equal(rowOf(s.recentOfferMedia.id).status, 'ready');
  assert.equal(linksOf(s.recentOfferMedia.id).length, 1);
  assert.equal(ctx.bucket.objects.has(s.recentOfferMedia.objectKey), true);

  // Failed more than 7 days ago: row removed. Recent failure: kept.
  assert.equal(rowOf(s.oldFailed.id), undefined);
  assert.equal(rowOf(s.recentFailed.id).status, 'failed');

  // The log carries counts only: no id, key, URL or token.
  assert.ok(logged.length > 0);
  for (const line of logged) {
    assert.equal(/[0-9a-f]{8}-[0-9a-f]{4}-/i.test(line), false, line);
    assert.equal(line.includes('profiles/'), false, line);
    assert.equal(line.includes('http'), false, line);
  }

  // Running again finds nothing new to do.
  const second = await runOfferMediaSweeps(ctx.env);
  assert.equal(second.abandonedUploads + second.deletedOfferMedia + second.pendingDeletes + second.failedUploads, 0);
});
