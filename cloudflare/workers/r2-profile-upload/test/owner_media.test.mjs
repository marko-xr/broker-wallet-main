// Behavioural tests for the Owner Media routes:
//   POST /owner-media/authorize
//   POST /owner-media/confirm
//   GET  /owner-media
//   POST /owner-media/remove
// and for the scheduled Owner-media sweeps (runOwnerMediaSweeps).
//
// Owner media runs the Offer media lifecycle for a different parent record
// (see MEDIA_PARENTS in worker.js); offer_media.test.mjs covers the shared
// lifecycle in depth. These tests prove the Owner wiring: the Owner table,
// link table, key segment and confirm function, the Owner limit, account
// isolation, and that an Offer's media can never be attached, listed or
// removed through an Owner (nor the other way round). They also prove that the
// abandoned-upload cleanup every authorize runs stays within one media entity:
// the profile image, one Offer or one Owner record, never the whole account.
//
// Run with: npm test   (or a bare `node --test` from this directory)
//
// Same approach as offer_media.test.mjs: requests go through `worker.fetch`,
// Supabase Auth/PostgREST is an in-memory fake reached through a temporary
// `globalThis.fetch`, and the R2 binding is an in-memory bucket. The database
// function `confirm_owner_media_upload` is emulated outcome for outcome; the
// SQL itself is exercised against a database by
// supabase/tests/owner_media_confirm_test.sql and
// supabase/validation/owner_media_confirm_validation.sql. Local tests: they
// prove the Worker's logic, not hosted behaviour.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import worker, { runOfferMediaSweeps, runOwnerMediaSweeps } from '../worker.js';

const SUPABASE_URL = 'https://project.supabase.test';
const PUBLISHABLE = 'sb_publishable_test';
const SECRET = 'sb_secret_TEST_SECRET_VALUE';
const BUCKET = 'broker-wallet-media-staging';
const OTHER_BUCKET = 'broker-wallet-media';
const WORKER_ORIGIN = 'https://media-api.test';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
// Alice's Owner records, and Bob's.
const OWNER_A = 'a0a0a0a0-a0a0-4a0a-8a0a-a0a0a0a0a0a0';
const OWNER_A2 = 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1';
const OWNER_BOB = 'b0b0b0b0-b0b0-4b0b-8b0b-b0b0b0b0b0b0';
// Alice's Offer, for the cross-parent checks.
const OFFER_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

function base64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

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

function newId() {
  return crypto.randomUUID();
}

/** Simple PostgREST filters: eq.x, is.null, lt.x and like.x* (`*` wildcard),
 * each optionally negated with `not.`. */
function matches(rowValue, filter) {
  if (filter.startsWith('not.')) return !matches(rowValue, filter.slice('not.'.length));
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

function filterRows(rows, searchParams) {
  return rows.filter((row) =>
    [...searchParams.entries()].every(
      ([column, filter]) => RESERVED_PARAMS.has(column) || column.includes('.') || matches(row[column], filter),
    ),
  );
}

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

/**
 * The link tables the Worker reads: each link embeds its media object and its
 * parent record, and `<resource>.<column>` filters apply to the embeddings.
 */
function readLinks(links, parents, parentResource, parentColumn, mediaObjects, searchParams) {
  const select = searchParams.get('select') ?? '';
  let rows = filterRows(links, searchParams).map((link) => ({
    link,
    media: mediaObjects.find((m) => m.id === link.media_id) ?? null,
    parent: parents.find((p) => p.id === link[parentColumn]) ?? null,
  }));
  for (const [key, filter] of searchParams.entries()) {
    if (!key.includes('.')) continue;
    const [resource, column] = key.split('.');
    const pick = resource === parentResource ? (row) => row.parent : (row) => row.media;
    rows = rows.filter((row) => pick(row) !== null && matches(pick(row)[column], filter));
  }
  if (select.includes('media_objects!inner')) rows = rows.filter((row) => row.media !== null);
  if (select.includes(`${parentResource}!inner`)) rows = rows.filter((row) => row.parent !== null);
  return rows.map(({ link, media, parent }) => ({
    ...link,
    media_objects: media ? { ...media } : null,
    [parentResource]: parent ? { ...parent } : null,
  }));
}

/** An in-memory Supabase REST + Auth fake for the Owner (and, for the
 * cross-parent checks, Offer) media routes and sweeps. */
class FakeSupabase {
  constructor() {
    this.users = new Map([
      [ALICE, { id: ALICE }],
      [BOB, { id: BOB }],
    ]);
    this.validTokens = new Set([token(ALICE), token(BOB)]);
    this.owners = [
      { id: OWNER_A, owner_id: ALICE, deleted_at: null },
      { id: OWNER_A2, owner_id: ALICE, deleted_at: null },
      { id: OWNER_BOB, owner_id: BOB, deleted_at: null },
    ];
    this.offers = [{ id: OFFER_A, owner_id: ALICE, deleted_at: null }];
    this.mediaObjects = [];
    this.ownerMedia = [];
    this.offerMedia = [];
    this.deletionJobs = [];
    this.calls = [];
    this.rpcCalls = [];
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

    if (parsed.pathname === '/rest/v1/rpc/confirm_owner_media_upload') {
      const params = JSON.parse(init.body);
      this.rpcCalls.push({ fn: 'owner', ...params });
      return json([this.confirm(params, {
        parents: this.owners,
        parentId: params.p_owner_record_id,
        links: this.ownerMedia,
        linkColumn: 'owner_record_id',
        segment: 'owners',
        notFound: 'owner_not_found',
      })]);
    }
    if (parsed.pathname === '/rest/v1/rpc/confirm_offer_media_upload') {
      const params = JSON.parse(init.body);
      this.rpcCalls.push({ fn: 'offer', ...params });
      return json([this.confirm(params, {
        parents: this.offers,
        parentId: params.p_offer_id,
        links: this.offerMedia,
        linkColumn: 'offer_id',
        segment: 'offers',
        notFound: 'offer_not_found',
      })]);
    }

    if (parsed.pathname === '/rest/v1/account_deletion_jobs') {
      return json(filterRows(this.deletionJobs, parsed.searchParams));
    }
    if (parsed.pathname === '/rest/v1/owners') return json(filterRows(this.owners, parsed.searchParams));
    if (parsed.pathname === '/rest/v1/offers') return json(filterRows(this.offers, parsed.searchParams));

    if (parsed.pathname === '/rest/v1/media_objects') {
      if (method === 'POST') {
        const body = JSON.parse(init.body);
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
        // FK: both link tables reference media_objects ON DELETE CASCADE.
        const gone = new Set(doomed.map((row) => row.id));
        this.ownerMedia = this.ownerMedia.filter((link) => !gone.has(link.media_id));
        this.offerMedia = this.offerMedia.filter((link) => !gone.has(link.media_id));
        return json(wantsRepresentation(headers) ? doomed.map((row) => ({ ...row })) : [], 200);
      }
    }

    if (parsed.pathname === '/rest/v1/owner_media') {
      if (method === 'GET') {
        const rows = readLinks(this.ownerMedia, this.owners, 'owners', 'owner_record_id', this.mediaObjects, parsed.searchParams);
        return json(orderAndLimit(rows, parsed.searchParams));
      }
      if (method === 'DELETE') {
        const doomed = filterRows(this.ownerMedia, parsed.searchParams);
        this.ownerMedia = this.ownerMedia.filter((link) => !doomed.includes(link));
        return json([], 200);
      }
    }

    if (parsed.pathname === '/rest/v1/offer_media') {
      if (method === 'GET') {
        const rows = readLinks(this.offerMedia, this.offers, 'offers', 'offer_id', this.mediaObjects, parsed.searchParams);
        return json(orderAndLimit(rows, parsed.searchParams));
      }
      if (method === 'DELETE') {
        const doomed = filterRows(this.offerMedia, parsed.searchParams);
        this.offerMedia = this.offerMedia.filter((link) => !doomed.includes(link));
        return json([], 200);
      }
    }

    throw new Error(`unexpected request ${method} ${parsed.pathname}`);
  };

  /** Mirrors the SQL of confirm_owner_media_upload / confirm_offer_media_upload. */
  confirm(p, { parents, parentId, links, linkColumn, segment, notFound }) {
    const parent = parents.find(
      (row) => row.id === parentId && row.owner_id === p.p_user_id && (row.deleted_at === null || row.deleted_at === undefined),
    );
    if (!parent) return { outcome: notFound, media_ordinal: null };

    const prefix = `profiles/${p.p_user_id}/${segment}/${parentId}/`;
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
    const existing = links.find((l) => l[linkColumn] === parentId && l.media_id === p.p_media_id);
    if (existing) {
      if (media.status === 'pending_upload') Object.assign(media, readyFields);
      return { outcome: 'already_attached', media_ordinal: existing.ordinal };
    }
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status', media_ordinal: null };

    const ready = links.filter((l) => {
      if (l[linkColumn] !== parentId) return false;
      const m = this.mediaObjects.find((x) => x.id === l.media_id);
      return m && m.bucket === p.p_bucket && m.status === 'ready';
    }).length;
    if (ready >= p.p_max_items) return { outcome: 'limit_reached', media_ordinal: null };

    const gallery = links.filter((l) => l[linkColumn] === parentId && l.role === 'gallery');
    const ordinal = gallery.length === 0 ? 0 : Math.max(...gallery.map((l) => l.ordinal)) + 1;
    links.push({ [linkColumn]: parentId, media_id: p.p_media_id, role: 'gallery', ordinal });
    Object.assign(media, readyFields);
    return { outcome: 'attached', media_ordinal: ordinal };
  }
}

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

const JPEG_BYTES = Uint8Array.from([0xff, 0xd8, 0xff, ...new Array(61).fill(0)]);

function box(type, payload) {
  const bytes = new Uint8Array(8 + payload.length);
  new DataView(bytes.buffer).setUint32(0, bytes.length);
  bytes.set([...type].map((c) => c.charCodeAt(0)), 4);
  bytes.set(payload, 8);
  return bytes;
}

function moovBox(seconds) {
  const timescale = 1000;
  const body = new Uint8Array(96);
  const view = new DataView(body.buffer);
  view.setUint32(12, timescale);
  view.setUint32(16, Math.round(seconds * timescale));
  return box('moov', box('mvhd', body));
}

function concat(...parts) {
  const bytes = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}

/** ftyp, media data, then `moov` last — the layout a phone camera writes. */
function mp4(seconds) {
  const brands = ['isom', '\0\0\0\0', 'isom', 'mp42'].join('');
  return concat(
    box('ftyp', Uint8Array.from([...brands].map((c) => c.charCodeAt(0)))),
    box('mdat', new Uint8Array(64)),
    moovBox(seconds),
  );
}

let ctx;
let originalFetch;

beforeEach(() => {
  const supabase = new FakeSupabase();
  const bucket = new FakeBucket();
  ctx = {
    supabase,
    bucket,
    env: {
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE,
      SUPABASE_SECRET_KEY: SECRET,
      R2_BUCKET_NAME: BUCKET,
      R2_S3_ENDPOINT: 'https://r2.test.example.com',
      R2_ACCESS_KEY_ID: 'test-access-key-id',
      R2_SECRET_ACCESS_KEY: 'test-secret-access-key',
      ALLOWED_ORIGIN: '*',
      MEDIA_BUCKET: bucket,
    },
  };
  originalFetch = globalThis.fetch;
  globalThis.fetch = supabase.fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

async function call(path, { method = 'GET', user, body } = {}) {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (user) headers.set('Authorization', `Bearer ${token(user)}`);
  const request = new Request(`${WORKER_ORIGIN}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const response = await worker.fetch(request, ctx.env, {});
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

function authorize(user, ownerRecordId, { mediaObjectId, contentType = 'image/jpeg', contentLength = JPEG_BYTES.length } = {}) {
  return call('/owner-media/authorize', {
    method: 'POST',
    user,
    body: { ownerRecordId, contentType, contentLength, ...(mediaObjectId ? { mediaObjectId } : {}) },
  });
}

function confirm(user, ownerRecordId, mediaObjectId) {
  return call('/owner-media/confirm', { method: 'POST', user, body: { ownerRecordId, mediaObjectId } });
}

function remove(user, ownerRecordId, mediaObjectId) {
  return call('/owner-media/remove', { method: 'POST', user, body: { ownerRecordId, mediaObjectId } });
}

function list(user, ownerRecordId) {
  return call(`/owner-media?ownerRecordId=${ownerRecordId}`, { user });
}

/** Authorizes with the app's own id, "uploads" the bytes, confirms. */
async function upload(user, ownerRecordId, { bytes = JPEG_BYTES, contentType = 'image/jpeg' } = {}) {
  const mediaObjectId = newId();
  const auth = await authorize(user, ownerRecordId, { mediaObjectId, contentType, contentLength: bytes.length });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  ctx.bucket.put(auth.body.objectKey, bytes, contentType);
  const confirmed = await confirm(user, ownerRecordId, mediaObjectId);
  return { mediaObjectId, objectKey: auth.body.objectKey, confirmed };
}

const rowOf = (id) => ctx.supabase.mediaObjects.find((row) => row.id === id);
const ownerLinksOf = (id) => ctx.supabase.ownerMedia.filter((link) => link.media_id === id);

// ===========================================================================
// Lifecycle
// ===========================================================================

test('an Owner photo is authorized under the Owner key, confirmed through the Owner function and listed', async () => {
  const { mediaObjectId, objectKey, confirmed } = await upload(ALICE, OWNER_A);

  assert.equal(objectKey, `profiles/${ALICE}/owners/${OWNER_A}/${mediaObjectId}.jpg`);
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.deepEqual(confirmed.body, { ownerRecordId: OWNER_A, mediaObjectId, ordinal: 0 });
  assert.equal(rowOf(mediaObjectId).status, 'ready');
  assert.deepEqual(ownerLinksOf(mediaObjectId).map((l) => l.owner_record_id), [OWNER_A]);
  assert.equal(ctx.supabase.offerMedia.length, 0, 'nothing reached the Offer link table');
  assert.deepEqual(ctx.supabase.rpcCalls.map((c) => c.fn), ['owner']);
  assert.equal(ctx.supabase.rpcCalls[0].p_owner_record_id, OWNER_A);
  assert.equal(ctx.supabase.rpcCalls[0].p_max_items, 10);

  const listed = await list(ALICE, OWNER_A);
  assert.equal(listed.status, 200);
  assert.equal(listed.body.ownerRecordId, OWNER_A);
  assert.equal(listed.body.media.length, 1);
  assert.equal(listed.body.media[0].mediaObjectId, mediaObjectId);
  assert.equal(listed.body.media[0].mediaType, 'image');
  assert.match(listed.body.media[0].url, /^https:\/\/r2\.test\.example\.com\//);
});

test('confirm and authorize are idempotent on the app\'s id', async () => {
  const { mediaObjectId } = await upload(ALICE, OWNER_A);

  const again = await confirm(ALICE, OWNER_A, mediaObjectId);
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyConfirmed, true);
  assert.equal(ownerLinksOf(mediaObjectId).length, 1, 'no second link');

  const reauthorized = await authorize(ALICE, OWNER_A, { mediaObjectId });
  assert.equal(reauthorized.status, 200);
  assert.equal(reauthorized.body.status, 'ready', 'a ready item needs no second upload');
  assert.equal(ctx.supabase.mediaObjects.length, 1, 'no second row');
});

test('a video is accepted up to three minutes and refused beyond, as for Offers', async () => {
  const ok = await upload(ALICE, OWNER_A, { bytes: mp4(180), contentType: 'video/mp4' });
  assert.equal(ok.confirmed.status, 200, JSON.stringify(ok.confirmed.body));
  assert.equal(rowOf(ok.mediaObjectId).duration_ms, 180000);

  const long = await upload(ALICE, OWNER_A, { bytes: mp4(200), contentType: 'video/mp4' });
  assert.equal(long.confirmed.status, 422);
  assert.equal(long.confirmed.body.code, 'video_too_long');
  assert.equal(rowOf(long.mediaObjectId).status, 'failed');
  assert.equal(ownerLinksOf(long.mediaObjectId).length, 0);
});

// ===========================================================================
// Isolation
// ===========================================================================

test('another account is refused on every Owner route and gets nothing created', async () => {
  const { mediaObjectId } = await upload(ALICE, OWNER_A);

  const authorized = await authorize(BOB, OWNER_A, { mediaObjectId: newId() });
  assert.equal(authorized.status, 404);
  assert.equal(authorized.body.code, 'owner_not_found');
  assert.equal((await confirm(BOB, OWNER_A, mediaObjectId)).status, 404);
  assert.equal((await list(BOB, OWNER_A)).status, 404);
  assert.equal((await remove(BOB, OWNER_A, mediaObjectId)).status, 404);

  // Bob, on his own Owner, cannot name Alice's media either.
  const takeover = await authorize(BOB, OWNER_BOB, { mediaObjectId });
  assert.equal(takeover.status, 409);
  assert.equal(takeover.body.code, 'media_id_conflict');
  const bobConfirm = await confirm(BOB, OWNER_BOB, mediaObjectId);
  assert.equal(bobConfirm.status, 404);
  const bobRemove = await remove(BOB, OWNER_BOB, mediaObjectId);
  assert.equal(bobRemove.status, 200);
  assert.equal(bobRemove.body.alreadyRemoved, true, 'nothing about Alice\'s media is revealed');

  assert.equal(rowOf(mediaObjectId).status, 'ready', 'Alice\'s media is untouched');
  assert.equal(ctx.supabase.mediaObjects.length, 1, 'no row was created for Bob');
});

test('an Offer\'s media can never be attached, listed or removed through an Owner', async () => {
  // Alice uploads to her Offer.
  const offerMediaId = newId();
  const offerAuth = await call('/offer-media/authorize', {
    method: 'POST',
    user: ALICE,
    body: { offerId: OFFER_A, mediaObjectId: offerMediaId, contentType: 'image/jpeg', contentLength: JPEG_BYTES.length },
  });
  assert.equal(offerAuth.status, 200);
  assert.equal(offerAuth.body.objectKey, `profiles/${ALICE}/offers/${OFFER_A}/${offerMediaId}.jpg`);
  ctx.bucket.put(offerAuth.body.objectKey, JPEG_BYTES, 'image/jpeg');

  // The same id through her Owner record: refused before anything changes.
  const reused = await authorize(ALICE, OWNER_A, { mediaObjectId: offerMediaId });
  assert.equal(reused.status, 409);
  assert.equal(reused.body.code, 'idempotency_mismatch');
  const crossConfirm = await confirm(ALICE, OWNER_A, offerMediaId);
  assert.equal(crossConfirm.status, 409);
  assert.equal(crossConfirm.body.code, 'media_mismatch');
  assert.equal(ctx.supabase.ownerMedia.length, 0);
  assert.equal(rowOf(offerMediaId).status, 'pending_upload');

  // Attached to the Offer, it is not listed on the Owner and cannot be removed there.
  const offerConfirm = await call('/offer-media/confirm', {
    method: 'POST',
    user: ALICE,
    body: { offerId: OFFER_A, mediaObjectId: offerMediaId },
  });
  assert.equal(offerConfirm.status, 200);
  assert.deepEqual((await list(ALICE, OWNER_A)).body.media, []);
  const crossRemove = await remove(ALICE, OWNER_A, offerMediaId);
  assert.equal(crossRemove.status, 409);
  assert.equal(crossRemove.body.code, 'media_mismatch');
  assert.equal(rowOf(offerMediaId).status, 'ready', 'the Offer keeps its media');

  // And an Owner's media never shows up on the Offer.
  const { mediaObjectId: ownerMediaId } = await upload(ALICE, OWNER_A);
  const offerList = await call(`/offer-media?offerId=${OFFER_A}`, { user: ALICE });
  assert.deepEqual(offerList.body.media.map((m) => m.mediaObjectId), [offerMediaId]);
  const ownerViaOffer = await call('/offer-media/remove', {
    method: 'POST',
    user: ALICE,
    body: { offerId: OFFER_A, mediaObjectId: ownerMediaId },
  });
  assert.equal(ownerViaOffer.status, 409);
  assert.equal(rowOf(ownerMediaId).status, 'ready');
});

test('one Owner record\'s media cannot be confirmed onto another of the same account', async () => {
  const mediaObjectId = newId();
  const auth = await authorize(ALICE, OWNER_A, { mediaObjectId });
  ctx.bucket.put(auth.body.objectKey, JPEG_BYTES, 'image/jpeg');

  const moved = await confirm(ALICE, OWNER_A2, mediaObjectId);
  assert.equal(moved.status, 409);
  assert.equal(moved.body.code, 'media_mismatch');
  assert.equal(ctx.supabase.ownerMedia.length, 0);
});

test('a soft-deleted Owner is refused by every route', async () => {
  const { mediaObjectId } = await upload(ALICE, OWNER_A);
  ctx.supabase.owners.find((o) => o.id === OWNER_A).deleted_at = new Date().toISOString();

  for (const response of [
    await authorize(ALICE, OWNER_A, { mediaObjectId: newId() }),
    await confirm(ALICE, OWNER_A, mediaObjectId),
    await list(ALICE, OWNER_A),
    await remove(ALICE, OWNER_A, mediaObjectId),
  ]) {
    assert.equal(response.status, 404);
    assert.equal(response.body.code, 'owner_not_found');
  }
  assert.equal(rowOf(mediaObjectId).status, 'ready', 'kept until the retention sweep');
});

// ===========================================================================
// The limit
// ===========================================================================

test('an Owner holds at most 10 items: the 11th is refused at authorize', async () => {
  for (let i = 0; i < 10; i += 1) {
    const { confirmed } = await upload(ALICE, OWNER_A);
    assert.equal(confirmed.status, 200);
  }
  const eleventh = await authorize(ALICE, OWNER_A, { mediaObjectId: newId() });
  assert.equal(eleventh.status, 409);
  assert.equal(eleventh.body.code, 'owner_media_limit_reached');
  assert.equal(ownerLinksOfOwner(OWNER_A), 10);

  // Another Owner record of the same account is counted separately.
  const other = await upload(ALICE, OWNER_A2);
  assert.equal(other.confirmed.status, 200);
});

function ownerLinksOfOwner(ownerRecordId) {
  return ctx.supabase.ownerMedia.filter((link) => link.owner_record_id === ownerRecordId).length;
}

// ===========================================================================
// Removal
// ===========================================================================

test('removing an Owner item unlinks it, deletes its bytes, tombstones it and is idempotent', async () => {
  const { mediaObjectId, objectKey } = await upload(ALICE, OWNER_A);

  const removed = await remove(ALICE, OWNER_A, mediaObjectId);
  assert.equal(removed.status, 200);
  assert.equal(removed.body.ownerRecordId, OWNER_A);
  assert.equal(removed.body.removed, true);
  assert.equal(removed.body.cleanupPending, undefined);
  assert.equal(rowOf(mediaObjectId).status, 'deleted');
  assert.equal(ownerLinksOf(mediaObjectId).length, 0);
  assert.equal(ctx.bucket.objects.has(objectKey), false);
  assert.deepEqual((await list(ALICE, OWNER_A)).body.media, []);

  const again = await remove(ALICE, OWNER_A, mediaObjectId);
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyRemoved, true);

  const reused = await authorize(ALICE, OWNER_A, { mediaObjectId });
  assert.equal(reused.status, 410, 'a removed id is final');
});

test('cancelling a queued Owner upload withdraws its row and bytes', async () => {
  const mediaObjectId = newId();
  const auth = await authorize(ALICE, OWNER_A, { mediaObjectId });
  ctx.bucket.put(auth.body.objectKey, JPEG_BYTES, 'image/jpeg');

  const removed = await remove(ALICE, OWNER_A, mediaObjectId);
  assert.equal(removed.status, 200);
  assert.equal(rowOf(mediaObjectId), undefined);
  assert.equal(ctx.bucket.objects.has(auth.body.objectKey), false);
});

// ===========================================================================
// Abandoned-upload cleanup at authorize — one media entity, never the account
// ===========================================================================

/**
 * A pending upload row and its bytes, keyed as the Worker keys them: the
 * profile image when [segment] is omitted, otherwise the Offer or Owner
 * record [parentId]. Created [ageMs] ago (25 h: past the 24 h cutoff).
 */
function seedPending({ ownerId = ALICE, segment, parentId, bucket = BUCKET, ageMs = 25 * HOUR_MS } = {}) {
  const id = newId();
  const objectKey = segment
    ? `profiles/${ownerId}/${segment}/${parentId}/${id}.jpg`
    : `profiles/${ownerId}/${id}.jpg`;
  const at = isoAgo(ageMs);
  ctx.supabase.mediaObjects.push({
    id,
    owner_id: ownerId,
    bucket,
    object_key: objectKey,
    media_type: 'image',
    content_type: 'image/jpeg',
    size_bytes: JPEG_BYTES.length,
    status: 'pending_upload',
    created_at: at,
    updated_at: at,
  });
  if (bucket === BUCKET) ctx.bucket.put(objectKey, JPEG_BYTES, 'image/jpeg');
  return { id, objectKey, bucket };
}

/** An abandoned upload for every entity of Alice's, and ones no cleanup of hers may touch. */
function seedAbandonedUploads() {
  return {
    ownerA: seedPending({ segment: 'owners', parentId: OWNER_A }),
    ownerA2: seedPending({ segment: 'owners', parentId: OWNER_A2 }),
    offerA: seedPending({ segment: 'offers', parentId: OFFER_A }),
    profile: seedPending(),
    ownerARecent: seedPending({ segment: 'owners', parentId: OWNER_A, ageMs: HOUR_MS }),
    ownerAOtherBucket: seedPending({ segment: 'owners', parentId: OWNER_A, bucket: OTHER_BUCKET }),
    bobOwner: seedPending({ ownerId: BOB, segment: 'owners', parentId: OWNER_BOB }),
    bobProfile: seedPending({ ownerId: BOB }),
  };
}

function assertWithdrawn(item, label) {
  assert.equal(rowOf(item.id), undefined, `${label}: row withdrawn`);
  assert.equal(ctx.bucket.objects.has(item.objectKey), false, `${label}: bytes withdrawn`);
}

function assertKept(item, label) {
  assert.equal(rowOf(item.id)?.status, 'pending_upload', `${label}: row kept`);
  if (item.bucket === BUCKET) assert.equal(ctx.bucket.objects.has(item.objectKey), true, `${label}: bytes kept`);
}

/** Exactly [withdrawn] of the seeded uploads is gone; every other one is intact. */
function assertOnlyWithdrawn(seeded, withdrawn) {
  for (const [label, item] of Object.entries(seeded)) {
    if (label === withdrawn) assertWithdrawn(item, label);
    else assertKept(item, label);
  }
}

test('an Owner authorize withdraws only that Owner record\'s abandoned uploads', async () => {
  const seeded = seedAbandonedUploads();

  const auth = await authorize(ALICE, OWNER_A, { mediaObjectId: newId() });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  // Not the Offer's, not the profile image's, not another Owner record's.
  assertOnlyWithdrawn(seeded, 'ownerA');
});

test('an Offer authorize withdraws only that Offer\'s abandoned uploads, never an Owner\'s or the profile image\'s', async () => {
  const seeded = seedAbandonedUploads();

  const auth = await call('/offer-media/authorize', {
    method: 'POST',
    user: ALICE,
    body: { offerId: OFFER_A, mediaObjectId: newId(), contentType: 'image/jpeg', contentLength: JPEG_BYTES.length },
  });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  assertOnlyWithdrawn(seeded, 'offerA');
});

test('a profile-image authorize withdraws only abandoned profile-image uploads, never Offer or Owner media', async () => {
  const seeded = seedAbandonedUploads();

  const auth = await call('/authorize', {
    method: 'POST',
    user: ALICE,
    body: { contentType: 'image/jpeg', contentLength: JPEG_BYTES.length },
  });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  assertOnlyWithdrawn(seeded, 'profile');
});

test('older abandoned uploads of other entities cannot crowd one entity\'s out of the cleanup batch', async () => {
  const offerUploads = Array.from({ length: 12 }, () => seedPending({ segment: 'offers', parentId: OFFER_A, ageMs: 72 * HOUR_MS }));
  const ownerUpload = seedPending({ segment: 'owners', parentId: OWNER_A });

  const auth = await authorize(ALICE, OWNER_A, { mediaObjectId: newId() });
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  assertWithdrawn(ownerUpload, 'the Owner\'s own abandoned upload');
  for (const item of offerUploads) assertKept(item, 'an older Offer upload');
});

// ===========================================================================
// Scheduled sweeps — Owner sweeps have their own switch and ship OFF
// ===========================================================================

function seedReady(parent, parentId, { deletedDaysAgo } = {}) {
  const id = newId();
  const segment = parent === 'owner' ? 'owners' : 'offers';
  const objectKey = `profiles/${ALICE}/${segment}/${parentId}/${id}.jpg`;
  ctx.supabase.mediaObjects.push({
    id,
    owner_id: ALICE,
    bucket: BUCKET,
    object_key: objectKey,
    media_type: 'image',
    content_type: 'image/jpeg',
    size_bytes: 64,
    status: 'ready',
    created_at: isoAgo(10 * DAY_MS),
    updated_at: isoAgo(10 * DAY_MS),
  });
  const links = parent === 'owner' ? ctx.supabase.ownerMedia : ctx.supabase.offerMedia;
  const column = parent === 'owner' ? 'owner_record_id' : 'offer_id';
  links.push({ [column]: parentId, media_id: id, role: 'gallery', ordinal: links.length });
  ctx.bucket.put(objectKey, JPEG_BYTES, 'image/jpeg');
  if (deletedDaysAgo !== undefined) {
    const parents = parent === 'owner' ? ctx.supabase.owners : ctx.supabase.offers;
    parents.find((p) => p.id === parentId).deleted_at = isoAgo(deletedDaysAgo * DAY_MS);
  }
  return { id, objectKey };
}

test('Owner sweeps do nothing unless OWNER_MEDIA_SWEEP_MODE is configured, whatever the Offer switch says', async () => {
  seedReady('owner', OWNER_A, { deletedDaysAgo: 8 });
  ctx.env.OFFER_MEDIA_SWEEP_MODE = 'on';
  for (const mode of [undefined, '', 'OFF', 'yes', 'off']) {
    ctx.env.OWNER_MEDIA_SWEEP_MODE = mode;
    const before = ctx.supabase.calls.length;
    const report = await runOwnerMediaSweeps(ctx.env);
    assert.equal(report.mode, 'off', String(mode));
    assert.equal(ctx.supabase.calls.length, before, `no database call in mode ${String(mode)}`);
  }
});

test('Owner sweeps: dry_run only counts; on removes a deleted Owner\'s media after 7 days and nothing of an Offer', async () => {
  const old = seedReady('owner', OWNER_A, { deletedDaysAgo: 8 });
  const recent = seedReady('owner', OWNER_A2, { deletedDaysAgo: 6 });
  const offerOld = seedReady('offer', OFFER_A, { deletedDaysAgo: 8 });

  ctx.env.OWNER_MEDIA_SWEEP_MODE = 'dry_run';
  const dry = await runOwnerMediaSweeps(ctx.env);
  assert.deepEqual(dry, {
    mode: 'dry_run',
    abandonedUploads: 0,
    deletedOwnerMedia: 1,
    pendingDeletes: 0,
    failedUploads: 0,
    errors: 0,
  });
  assert.equal(rowOf(old.id).status, 'ready', 'a dry run changes nothing');

  ctx.env.OWNER_MEDIA_SWEEP_MODE = 'on';
  const applied = await runOwnerMediaSweeps(ctx.env);
  assert.deepEqual(applied, {
    mode: 'on',
    abandonedUploads: 0,
    deletedOwnerMedia: 1,
    pendingDeletes: 1,
    failedUploads: 0,
    errors: 0,
  });
  assert.equal(rowOf(old.id).status, 'deleted');
  assert.equal(ownerLinksOf(old.id).length, 0);
  assert.equal(ctx.bucket.objects.has(old.objectKey), false);
  assert.equal(rowOf(recent.id).status, 'ready', 'an Owner deleted 6 days ago keeps its media');
  assert.equal(rowOf(offerOld.id).status, 'ready', 'Offer media is left to the Offer sweeps');
  assert.equal(ctx.bucket.objects.has(offerOld.objectKey), true);
});

test('the Offer sweep report is unchanged and never touches Owner media', async () => {
  const ownerOld = seedReady('owner', OWNER_A, { deletedDaysAgo: 8 });
  const offerOld = seedReady('offer', OFFER_A, { deletedDaysAgo: 8 });
  ctx.env.OFFER_MEDIA_SWEEP_MODE = 'on';

  const report = await runOfferMediaSweeps(ctx.env);
  assert.deepEqual(report, {
    mode: 'on',
    abandonedUploads: 0,
    deletedOfferMedia: 1,
    pendingDeletes: 1,
    failedUploads: 0,
    errors: 0,
  });
  assert.equal(rowOf(offerOld.id).status, 'deleted');
  assert.equal(rowOf(ownerOld.id).status, 'ready');
  assert.equal(ctx.bucket.objects.has(ownerOld.objectKey), true);
});
