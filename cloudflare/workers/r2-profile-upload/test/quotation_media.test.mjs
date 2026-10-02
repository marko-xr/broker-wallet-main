import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { runQuotationMediaSweeps } from '../worker.js';

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';
const QUOTE_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const QUOTE_A2 = 'abababab-abab-4bab-8bab-abababababab';
const QUOTE_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const BUCKET = 'broker-wallet-media-staging';
const SUPABASE_URL = 'https://project.supabase.test';
const SECRET = 'test-service-key';
const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, ...new Array(61).fill(0)]);
const PDF = new TextEncoder().encode('%PDF-1.7\n1 0 obj\n%%EOF');

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}

function matches(value, filter) {
  if (filter === 'is.null') return value == null;
  if (filter === 'not.is.null') return value != null;
  if (filter.startsWith('eq.')) return String(value) === filter.slice(3);
  if (filter.startsWith('like.')) {
    const regex = `^${filter.slice(5).split('*').map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*')}$`;
    return new RegExp(regex).test(String(value ?? ''));
  }
  if (filter.startsWith('lt.')) return Date.parse(value) < Date.parse(filter.slice(3));
  if (filter.startsWith('in.(')) return filter.slice(4, -1).split(',').includes(value);
  throw new Error(`Unsupported fake filter ${filter}`);
}

function filtered(rows, search) {
  return rows.filter((row) => [...search.entries()].every(([key, value]) =>
    ['select', 'order', 'limit'].includes(key) || key.includes('.') || matches(row[key], value)));
}

class FakeBucket {
  objects = new Map();
  failDeleteKey = null;
  put(key, bytes, contentType) { this.objects.set(key, { bytes, contentType }); }
  async head(key) {
    const value = this.objects.get(key);
    return value ? { size: value.bytes.length, httpMetadata: { contentType: value.contentType } } : null;
  }
  async get(key, { range } = {}) {
    const value = this.objects.get(key);
    if (!value) return null;
    const bytes = range ? value.bytes.slice(range.offset, range.offset + range.length) : value.bytes;
    return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
  }
  async delete(key) {
    if (key === this.failDeleteKey) throw new Error('simulated R2 delete failure');
    this.objects.delete(key);
  }
}

class FakeSupabase {
  constructor() {
    this.quotes = [
      { id: QUOTE_A, owner_id: ALICE, deleted_at: null, office_logo_media_id: null, pdf_media_id: null, version: 1 },
      { id: QUOTE_A2, owner_id: ALICE, deleted_at: null, office_logo_media_id: null, pdf_media_id: null, version: 1 },
      { id: QUOTE_B, owner_id: BOB, deleted_at: null, office_logo_media_id: null, pdf_media_id: null, version: 1 },
    ];
    this.media = [];
    this.links = [];
    this.rpcCalls = [];
  }

  fetch = async (url, init = {}) => {
    const parsed = new URL(url);
    if (parsed.pathname === '/auth/v1/user') {
      const token = init.headers?.Authorization;
      return token === 'Bearer token-a' ? json({ id: ALICE })
        : token === 'Bearer token-b' ? json({ id: BOB }) : json({}, 401);
    }
    assert.equal(init.headers?.apikey, SECRET);
    const { pathname, searchParams: search } = parsed;
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const returning = String(init.headers?.Prefer).includes('return=representation');
    if (pathname === '/rest/v1/account_deletion_jobs') return json([]);
    if (pathname === '/rest/v1/quotations') {
      const rows = filtered(this.quotes, search);
      if (method === 'GET') return json(rows);
      if (method === 'PATCH') {
        for (const row of rows) { Object.assign(row, body); row.version += 1; }
        return json(returning ? rows : []);
      }
    }
    if (pathname === '/rest/v1/media_objects') {
      if (method === 'POST') {
        if (this.media.some((m) => m.id === body.id)) return json({ code: '23505' }, 409);
        const at = new Date().toISOString();
        this.media.push({ ...body, created_at: at, updated_at: at });
        return json([], 201);
      }
      if (method === 'PATCH' && this.beforeMediaPatch) {
        const hook = this.beforeMediaPatch;
        this.beforeMediaPatch = null;
        hook();
      }
      const rows = filtered(this.media, search);
      if (method === 'GET') return json(rows);
      if (method === 'PATCH') {
        for (const row of rows) Object.assign(row, body);
        return json(returning ? rows : []);
      }
      if (method === 'DELETE') {
        for (const row of rows) this.media.splice(this.media.indexOf(row), 1);
        return json(returning ? rows : []);
      }
    }
    if (pathname === '/rest/v1/quotation_media') {
      const rows = filtered(this.links, search);
      if (method === 'GET') {
        if (String(search.get('select')).includes('!inner')) {
          const embedded = rows.map((link) => ({ ...link,
            quotations: this.quotes.find((q) => q.id === link.quotation_id),
            media_objects: this.media.find((m) => m.id === link.media_id),
          })).filter((link) => link.quotations && link.media_objects &&
            [...search.entries()].every(([key, filter]) => {
              if (!key.includes('.')) return true;
              const [resource, field] = key.split('.');
              return matches(link[resource]?.[field], filter);
            }));
          return json(embedded);
        }
        return json(rows);
      }
      if (method === 'DELETE') {
        for (const row of rows) this.links.splice(this.links.indexOf(row), 1);
        return json([]);
      }
    }
    if (pathname === '/rest/v1/rpc/confirm_quotation_media_upload') {
      this.rpcCalls.push({ fn: 'confirm', ...body });
      return json([this.confirm(body)]);
    }
    if (pathname === '/rest/v1/rpc/remove_quotation_media') {
      this.rpcCalls.push({ fn: 'remove', ...body });
      return json([this.remove(body)]);
    }
    throw new Error(`Unexpected fake API call ${method} ${pathname}`);
  };

  confirm(p) {
    const quote = this.quotes.find((q) => q.id === p.p_quotation_id &&
      q.owner_id === p.p_user_id && q.deleted_at === null);
    if (!quote) return { outcome: 'quotation_not_found' };
    const column = p.p_role === 'office_logo' ? 'office_logo_media_id' : 'pdf_media_id';
    const linkRole = p.p_role === 'office_logo' ? 'logo' : 'pdf';
    const current = quote[column];
    const media = this.media.find((m) => m.id === p.p_media_id && m.owner_id === p.p_user_id &&
      m.bucket === p.p_bucket && m.object_key.startsWith(`profiles/${p.p_user_id}/quotations/${quote.id}/${p.p_role}/`));
    if (!media) return { outcome: 'media_not_found' };
    if (current === media.id && media.status === 'ready') {
      return { outcome: 'already_attached', resulting_version: quote.version };
    }
    if (current !== p.p_expected_media_id) return { outcome: 'stale_replacement', resulting_version: quote.version };
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status' };
    if (this.links.some((l) => l.media_id === media.id)) return { outcome: 'media_already_bound' };
    this.links = this.links.filter((l) => !(l.quotation_id === quote.id && l.role === linkRole));
    this.links.push({ quotation_id: quote.id, media_id: media.id, role: linkRole, ordinal: 0 });
    Object.assign(media, { status: 'ready', size_bytes: p.p_observed_size, content_type: p.p_observed_content_type });
    quote[column] = media.id;
    quote.version += 1;
    if (current) this.media.find((m) => m.id === current).status = 'pending_delete';
    return { outcome: 'attached', previous_media_id: current, resulting_version: quote.version };
  }

  remove(p) {
    const quote = this.quotes.find((q) => q.id === p.p_quotation_id &&
      q.owner_id === p.p_user_id && q.deleted_at === null);
    if (!quote) return { outcome: 'quotation_not_found' };
    const column = p.p_role === 'office_logo' ? 'office_logo_media_id' : 'pdf_media_id';
    const current = quote[column];
    if (!current) return { outcome: 'already_removed', resulting_version: quote.version };
    if (current !== p.p_expected_media_id) return { outcome: 'stale_replacement', resulting_version: quote.version };
    quote[column] = null;
    quote.version += 1;
    this.links = this.links.filter((l) => l.media_id !== current);
    this.media.find((m) => m.id === current).status = 'pending_delete';
    return { outcome: 'removed', previous_media_id: current, resulting_version: quote.version };
  }
}

let state;
let originalFetch;
beforeEach(() => {
  const supabase = new FakeSupabase();
  const bucket = new FakeBucket();
  state = { supabase, bucket, env: {
    SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    SUPABASE_SECRET_KEY: SECRET, R2_BUCKET_NAME: BUCKET,
    R2_S3_ENDPOINT: 'https://r2.test.example.com',
    R2_ACCESS_KEY_ID: 'test-access', R2_SECRET_ACCESS_KEY: 'test-secret',
    MEDIA_BUCKET: bucket,
  } };
  originalFetch = globalThis.fetch;
  globalThis.fetch = supabase.fetch;
});
afterEach(() => { globalThis.fetch = originalFetch; });

async function call(path, user = ALICE, body) {
  const method = body === undefined ? 'GET' : 'POST';
  const response = await worker.fetch(new Request(`https://worker.test${path}`, {
    method,
    headers: { Authorization: user === ALICE ? 'Bearer token-a' : 'Bearer token-b',
      'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), state.env, {});
  return { status: response.status, body: await response.json() };
}

async function authorize(role, quote = QUOTE_A, expectedMediaId = null, contentType = role === 'office_logo' ? 'image/jpeg' : 'application/pdf', bytes = role === 'office_logo' ? JPEG : PDF, user = ALICE) {
  const mediaObjectId = crypto.randomUUID();
  const result = await call('/quotation-media/authorize', user,
    { quotationId: quote, role, expectedMediaId, mediaObjectId, contentType, contentLength: bytes.length });
  return { ...result, mediaObjectId, bytes, contentType };
}

async function upload(role, quote = QUOTE_A, expectedMediaId = null, bytes = role === 'office_logo' ? JPEG : PDF) {
  const auth = await authorize(role, quote, expectedMediaId, undefined, bytes);
  assert.equal(auth.status, 200, JSON.stringify(auth.body));
  state.bucket.put(auth.body.objectKey, bytes, auth.contentType);
  const confirmed = await call('/quotation-media/confirm', ALICE,
    { quotationId: quote, role, mediaObjectId: auth.mediaObjectId, expectedMediaId });
  return { ...auth, confirmed };
}

const quote = () => state.supabase.quotes[0];
const media = (id) => state.supabase.media.find((m) => m.id === id);

test('office logo and PDF use separate private keys, RPC roles and signed owner retrieval', async () => {
  const logo = await upload('office_logo');
  assert.equal(logo.confirmed.status, 200, JSON.stringify(logo.confirmed.body));
  assert.equal(logo.body.objectKey, `profiles/${ALICE}/quotations/${QUOTE_A}/office_logo/${logo.mediaObjectId}.jpg`);
  const pdf = await upload('quotation_pdf');
  assert.equal(pdf.confirmed.status, 200, JSON.stringify(pdf.confirmed.body));
  assert.equal(pdf.body.objectKey, `profiles/${ALICE}/quotations/${QUOTE_A}/quotation_pdf/${pdf.mediaObjectId}.pdf`);
  assert.equal(media(pdf.mediaObjectId).media_type, 'pdf');
  assert.deepEqual(state.supabase.links.map((l) => l.role), ['logo', 'pdf']);
  const listed = await call(`/quotation-media?quotationId=${QUOTE_A}`);
  assert.equal(listed.status, 200);
  assert.match(listed.body.media.office_logo.url, /^https:\/\/r2\.test\.example\.com\//);
  assert.match(listed.body.media.quotation_pdf.url, /^https:\/\/r2\.test\.example\.com\//);
  assert.equal((await call(`/quotation-media?quotationId=${QUOTE_A}`, BOB)).status, 404);
  assert.equal((await call(`/quotation-media?quotationId=${QUOTE_B}`, ALICE)).status, 404);
  const retry = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: logo.mediaObjectId, expectedMediaId: null });
  assert.equal(retry.body.alreadyConfirmed, true);
  assert.equal(quote().version, 3);
});

test('authorize and confirm reject foreign quote, cross-parent and wrong role', async () => {
  assert.equal((await authorize('office_logo', QUOTE_B)).status, 404);
  const own = await authorize('office_logo');
  assert.equal(own.status, 200);
  state.bucket.put(own.body.objectKey, JPEG, 'image/jpeg');
  assert.equal((await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A2, role: 'office_logo', mediaObjectId: own.mediaObjectId, expectedMediaId: null })).status, 409);
  assert.equal((await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: own.mediaObjectId, expectedMediaId: null })).status, 409);
  assert.equal((await call('/quotation-media/confirm', BOB,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: own.mediaObjectId, expectedMediaId: null })).status, 404);
  assert.equal((await call('/quotation-media/remove', BOB,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: own.mediaObjectId, expectedMediaId: null })).status, 404);
  const wrongParentRemove = await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A2, role: 'office_logo', mediaObjectId: own.mediaObjectId, expectedMediaId: null });
  assert.equal(wrongParentRemove.status, 409);
  assert.equal(wrongParentRemove.body.code, 'media_mismatch');
  assert.equal(media(own.mediaObjectId).status, 'pending_upload');
  assert.equal(state.supabase.links.length, 0);
});

test('role MIME and uploaded bytes are enforced', async () => {
  assert.equal((await authorize('quotation_pdf', QUOTE_A, null, 'image/jpeg')).status, 400);
  assert.equal((await authorize('office_logo', QUOTE_A, null, 'application/pdf')).status, 400);
  const bad = await authorize('quotation_pdf');
  state.bucket.put(bad.body.objectKey, JPEG, 'application/pdf');
  const result = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: bad.mediaObjectId, expectedMediaId: null });
  assert.equal(result.status, 422);
  assert.equal(result.body.code, 'media_type_mismatch');
  assert.equal(media(bad.mediaObjectId).status, 'failed');
  assert.equal(quote().pdf_media_id, null);
  const removed = await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: bad.mediaObjectId,
      expectedMediaId: null });
  assert.equal(removed.status, 200);
  assert.equal(media(bad.mediaObjectId).status, 'deleted');
});

test('invalid-byte rejection never deletes bytes after a concurrent confirm wins', async () => {
  const pending = await authorize('quotation_pdf');
  state.bucket.put(pending.body.objectKey, JPEG, 'application/pdf');
  state.supabase.beforeMediaPatch = () => {
    media(pending.mediaObjectId).status = 'ready';
    quote().pdf_media_id = pending.mediaObjectId;
    quote().version += 1;
    state.supabase.links.push({ quotation_id: QUOTE_A, media_id: pending.mediaObjectId,
      role: 'pdf', ordinal: 0 });
  };
  const result = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: pending.mediaObjectId,
      expectedMediaId: null });
  assert.equal(result.status, 409);
  assert.equal(result.body.code, 'invalid_state');
  assert.equal(media(pending.mediaObjectId).status, 'ready');
  assert.equal(state.bucket.objects.has(pending.body.objectKey), true);
});

test('replacement uses slot CAS, stale upload cannot win, removal tombstones old bytes', async () => {
  const original = await upload('office_logo');
  const a = await authorize('office_logo', QUOTE_A, original.mediaObjectId);
  const b = await authorize('office_logo', QUOTE_A, original.mediaObjectId);
  state.bucket.put(a.body.objectKey, JPEG, 'image/jpeg');
  state.bucket.put(b.body.objectKey, JPEG, 'image/jpeg');
  const win = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: a.mediaObjectId,
      expectedMediaId: original.mediaObjectId });
  assert.equal(win.status, 200);
  assert.equal(media(original.mediaObjectId).status, 'deleted');
  assert.equal(state.bucket.objects.has(original.body.objectKey), false);
  const stale = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: b.mediaObjectId,
      expectedMediaId: original.mediaObjectId });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.code, 'stale_replacement');
  assert.equal(quote().office_logo_media_id, a.mediaObjectId);
  assert.equal(media(b.mediaObjectId).status, 'pending_upload');
  const removed = await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', expectedMediaId: a.mediaObjectId });
  assert.equal(removed.status, 200);
  assert.equal(quote().office_logo_media_id, null);
  assert.equal(media(a.mediaObjectId).status, 'deleted');
  assert.equal(state.supabase.links.length, 0);
  assert.equal((await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', expectedMediaId: a.mediaObjectId })).status, 200);
});

test('pending cancellation, deleted quote refusal and disabled sweep are scoped', async () => {
  const pending = await authorize('quotation_pdf');
  const canceled = await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: pending.mediaObjectId, expectedMediaId: null });
  assert.equal(canceled.status, 200);
  assert.equal(media(pending.mediaObjectId).status, 'deleted');
  quote().deleted_at = new Date().toISOString();
  assert.equal((await authorize('office_logo')).status, 404);
  assert.equal((await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'quotation_pdf', mediaObjectId: pending.mediaObjectId, expectedMediaId: null })).status, 404);
  assert.equal((await call(`/quotation-media?quotationId=${QUOTE_A}`)).status, 404);
  assert.deepEqual(await runQuotationMediaSweeps(state.env), {
    mode: 'off', abandonedUploads: 0, deletedQuotationMedia: 0,
    pendingDeletes: 0, failedUploads: 0, errors: 0,
  });
});

test('enabled Quotation sweep retires only old soft-deleted Quotation PDF', async () => {
  const pdf = await upload('quotation_pdf');
  assert.equal(pdf.confirmed.status, 200);
  const unrelated = await upload('office_logo', QUOTE_A2);
  assert.equal(unrelated.confirmed.status, 200);
  quote().deleted_at = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString();
  state.env.QUOTATION_MEDIA_SWEEP_MODE = 'on';
  const report = await runQuotationMediaSweeps(state.env);
  assert.equal(report.deletedQuotationMedia, 1);
  assert.equal(report.pendingDeletes, 1);
  assert.equal(report.errors, 0);
  assert.equal(quote().pdf_media_id, null);
  assert.equal(media(pdf.mediaObjectId).status, 'deleted');
  assert.equal(state.bucket.objects.has(pdf.body.objectKey), false);
  assert.equal(state.supabase.quotes[1].office_logo_media_id, unrelated.mediaObjectId);
  assert.equal(media(unrelated.mediaObjectId).status, 'ready');
  assert.equal(state.bucket.objects.has(unrelated.body.objectKey), true);
});

test('a failed replacement cleanup is retryable without disturbing the new logo', async () => {
  const original = await upload('office_logo');
  const replacement = await authorize('office_logo', QUOTE_A, original.mediaObjectId);
  state.bucket.put(replacement.body.objectKey, JPEG, 'image/jpeg');
  state.bucket.failDeleteKey = original.body.objectKey;
  const confirmed = await call('/quotation-media/confirm', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: replacement.mediaObjectId,
      expectedMediaId: original.mediaObjectId });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.cleanupPending, true);
  assert.equal(media(original.mediaObjectId).status, 'pending_delete');
  assert.equal(quote().office_logo_media_id, replacement.mediaObjectId);
  state.bucket.failDeleteKey = null;
  const retry = await call('/quotation-media/remove', ALICE,
    { quotationId: QUOTE_A, role: 'office_logo', mediaObjectId: original.mediaObjectId,
      expectedMediaId: replacement.mediaObjectId });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.alreadyRemoved, true);
  assert.equal(media(original.mediaObjectId).status, 'deleted');
  assert.equal(quote().office_logo_media_id, replacement.mediaObjectId);
  assert.equal(media(replacement.mediaObjectId).status, 'ready');
});
