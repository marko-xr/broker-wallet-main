import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { runToolkitDocumentCleanup } from '../worker.js';
import { accountObjectPrefix, removeAccountMedia } from '../account_deletion.js';
import {
  TOOLKIT_DOCUMENT_TYPES,
  TOOLKIT_LIMIT_CEILINGS,
  TOOLKIT_LIMIT_DEFAULTS,
  toolkitDocumentsEnabled,
  toolkitKeyDocumentId,
  toolkitLimits,
  toolkitObjectKey,
} from '../toolkit_documents.js';
import {
  ALICE, BOB, BUCKET, DOC_1, DOC_2, DOC_3, jpegBytes, makeState, pdfBytes, pngBytes, sha256Hex,
} from './toolkit_fakes.mjs';

let state;
let originalFetch;
beforeEach(() => {
  state = makeState();
  originalFetch = globalThis.fetch;
  globalThis.fetch = state.supabase.fetch;
});
afterEach(() => { globalThis.fetch = originalFetch; });

async function call(method, path, { user = ALICE, body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const bearer = token ?? (user === ALICE ? 'Bearer token-a' : user === BOB ? 'Bearer token-b' : null);
  if (bearer) headers.Authorization = bearer;
  const response = await worker.fetch(new Request(`https://worker.test${path}`, {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), state.env, {});
  return { status: response.status, body: await response.json(), headers: response.headers };
}
const post = (path, body, options) => call('POST', path, { ...options, body });
const get = (path, options) => call('GET', path, options);

const KEY = (user, id, ext = 'pdf') => `profiles/${user}/toolkit-documents/${id}.${ext}`;
function authBody(overrides = {}) {
  const bytes = pdfBytes();
  return {
    documentId: DOC_1, documentType: 'scanner', title: 'Lease scan', contentType: 'application/pdf',
    contentLength: bytes.length, contentSha256: sha256Hex(bytes), pageCount: 2,
    sourceCreatedAt: '2026-10-19T08:00:00.000Z', ...overrides,
  };
}

/** Authorize, put the bytes where the signed URL points, and confirm. */
async function uploadReady(documentId, {
  user = ALICE, type = 'scanner', title = 'Doc', bytes = pdfBytes(),
  contentType = 'application/pdf', ext = 'pdf',
} = {}) {
  const authorized = await post('/toolkit-documents/authorize',
    authBody({
      documentId, documentType: type, title, contentType, contentLength: bytes.length,
      contentSha256: sha256Hex(bytes), pageCount: contentType === 'application/pdf' ? 2 : 1,
    }), { user });
  assert.equal(authorized.status, 200, JSON.stringify(authorized.body));
  state.bucket.put(KEY(user, documentId, ext), bytes, contentType);
  const confirmed = await post('/toolkit-documents/confirm', { documentId }, { user });
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  return { authorized, confirmed };
}

// ---------------------------------------------------------------------------
// Inactive by default
// ---------------------------------------------------------------------------

test('every route answers 404 and touches nothing while the feature is off', async () => {
  for (const env of [{ TOOLKIT_DOCUMENTS_ENABLED: undefined }, { TOOLKIT_DOCUMENTS_ENABLED: 'false' },
    { TOOLKIT_DOCUMENTS_ENABLED: 'TRUE' }, { TOOLKIT_DOCUMENTS_ENABLED: '1' }]) {
    state = makeState(env);
    globalThis.fetch = (...args) => { throw new Error(`unexpected network call ${args[0]}`); };
    for (const [method, path] of [
      ['POST', '/toolkit-documents/authorize'], ['POST', '/toolkit-documents/confirm'],
      ['GET', '/toolkit-documents'], ['GET', '/toolkit-documents/download'],
      ['POST', '/toolkit-documents/status'], ['POST', '/toolkit-documents/rename'],
      ['POST', '/toolkit-documents/remove']]) {
      const result = await call(method, path, { body: method === 'POST' ? {} : undefined });
      assert.equal(result.status, 404, `${method} ${path} with ${JSON.stringify(env)}`);
      assert.deepEqual(result.body, { error: 'Not found' });
    }
  }
  assert.equal(toolkitDocumentsEnabled({ TOOLKIT_DOCUMENTS_ENABLED: 'true' }), true);
  assert.equal(toolkitDocumentsEnabled({}), false);
});

test('an unknown path or wrong method under /toolkit-documents is a plain 404', async () => {
  assert.equal((await get('/toolkit-documents/nope')).status, 404);
  assert.equal((await post('/toolkit-documents', {})).status, 404);
  assert.equal((await get('/toolkit-documents/authorize')).status, 404);
  assert.equal((await post('/toolkit-documents/download', {})).status, 404);
});

test('the scheduled sweep does nothing unless its own mode is set', async () => {
  state.supabase.seedReady(state.bucket, { id: DOC_1, size: 100 });
  state.supabase.before.list_toolkit_document_cleanup = () => assert.fail('off must not query');
  const report = await runToolkitDocumentCleanup({ ...state.env });
  assert.equal(report.mode, 'off');
  const unknown = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'yes' });
  assert.equal(unknown.mode, 'off');
});

// ---------------------------------------------------------------------------
// Identity, session and limits
// ---------------------------------------------------------------------------

test('a missing, malformed or rejected token is 401; a replaced session is 403; an unavailable check is 503', async () => {
  assert.equal((await get('/toolkit-documents', { user: null })).status, 401);
  assert.equal((await get('/toolkit-documents', { token: 'Basic abc' })).status, 401);
  assert.equal((await get('/toolkit-documents', { token: 'Bearer nobody' })).status, 401);
  state.supabase.sessionCurrent = false;
  const replaced = await get('/toolkit-documents');
  assert.equal(replaced.status, 403);
  assert.equal(replaced.body.code, 'session_superseded');
  state.supabase.sessionCurrent = true;
  state.supabase.sessionUnavailable = true;
  const unavailable = await get('/toolkit-documents');
  assert.equal(unavailable.status, 503);
  assert.equal(unavailable.body.code, 'session_check_unavailable');
  assert.equal(state.supabase.rpcNames.length, 0, 'no document function ran for an unverified caller');
});

test('the account is the token\'s account: a body that names another owner changes nothing', async () => {
  const result = await post('/toolkit-documents/authorize', authBody({ ownerId: BOB, userId: BOB, objectKey: KEY(BOB, DOC_1) }));
  assert.equal(result.status, 200);
  const row = state.supabase.row(DOC_1);
  assert.equal(row.owner_id, ALICE);
  assert.equal(row.object_key, KEY(ALICE, DOC_1));
});

test('limits default, clamp to their ceilings and ignore invalid values', () => {
  assert.deepEqual({ ...toolkitLimits({}) }, { ...TOOLKIT_LIMIT_DEFAULTS });
  const clamped = toolkitLimits({ TOOLKIT_DOC_MAX_BYTES: '999999999999', TOOLKIT_DOC_MAX_PENDING: '3', TOOLKIT_DOC_MAX_ACCOUNT_DOCUMENTS: '9999999' });
  assert.equal(clamped.documentBytes, TOOLKIT_LIMIT_CEILINGS.documentBytes);
  assert.equal(clamped.pendingUploads, 3);
  assert.equal(clamped.accountDocuments, TOOLKIT_LIMIT_CEILINGS.accountDocuments);
  const invalid = toolkitLimits({ TOOLKIT_DOC_MAX_BYTES: '-5', TOOLKIT_DOC_MAX_PENDING: 'abc', TOOLKIT_DOC_MAX_NEW_PER_HOUR: '0', TOOLKIT_DOC_MAX_ATTEMPTS: '1e3' });
  assert.equal(invalid.documentBytes, TOOLKIT_LIMIT_DEFAULTS.documentBytes);
  assert.equal(invalid.pendingUploads, TOOLKIT_LIMIT_DEFAULTS.pendingUploads);
  assert.equal(invalid.newPerHour, TOOLKIT_LIMIT_DEFAULTS.newPerHour);
  assert.equal(invalid.attemptsPerUpload, TOOLKIT_LIMIT_DEFAULTS.attemptsPerUpload);
  for (const [name, ceiling] of Object.entries(TOOLKIT_LIMIT_CEILINGS)) {
    assert.ok(TOOLKIT_LIMIT_DEFAULTS[name] <= ceiling, name);
  }
});

// ---------------------------------------------------------------------------
// Object key containment
// ---------------------------------------------------------------------------

test('the object key is account-prefixed, exact, and recognized only when exact', () => {
  assert.equal(toolkitObjectKey(ALICE, DOC_1, 'application/pdf'), `profiles/${ALICE}/toolkit-documents/${DOC_1}.pdf`);
  assert.equal(toolkitObjectKey(ALICE, DOC_1, 'image/jpeg'), `profiles/${ALICE}/toolkit-documents/${DOC_1}.jpg`);
  assert.equal(toolkitObjectKey(ALICE, DOC_1, 'image/png'), `profiles/${ALICE}/toolkit-documents/${DOC_1}.png`);
  assert.equal(toolkitObjectKey(ALICE, DOC_1, 'image/gif'), null);
  assert.equal(toolkitObjectKey(ALICE, DOC_1, undefined), null);
  for (const [type, ext] of [['application/pdf', 'pdf'], ['image/jpeg', 'jpg'], ['image/png', 'png']]) {
    assert.deepEqual(toolkitKeyDocumentId(ALICE, toolkitObjectKey(ALICE, DOC_1, type)), { documentId: DOC_1, contentType: type }, ext);
  }
  for (const bad of [
    `profiles/${BOB}/toolkit-documents/${DOC_1}.pdf`,
    `profiles/${ALICE}/toolkit-documents/../${DOC_1}.pdf`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1}.PDF`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1}.jpeg`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1}.gif`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1}`,
    `profiles/${ALICE}/toolkit-documents/.pdf`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1}.pdf/extra`,
    `profiles/${ALICE}/toolkit-documents/${DOC_1.toUpperCase()}.pdf`,
    `profiles/${ALICE}/offers/${DOC_1}.pdf`,
    `profiles/${ALICE}/${DOC_1}.pdf`,
    `profiles/${ALICE}/toolkit-documents/not-a-uuid.pdf`,
    null, undefined, 42,
  ]) {
    assert.equal(toolkitKeyDocumentId(ALICE, bad), null, String(bad));
  }
});

test('Delete Account compatibility: the key is inside the account prefix and never another\'s', () => {
  for (const id of [DOC_1, DOC_2, DOC_3]) {
    for (const type of ['application/pdf', 'image/jpeg', 'image/png']) {
      assert.ok(toolkitObjectKey(ALICE, id, type).startsWith(accountObjectPrefix(ALICE)));
      assert.ok(!toolkitObjectKey(ALICE, id, type).startsWith(accountObjectPrefix(BOB)));
    }
  }
});

test('Delete Account removes every Toolkit object of the account and only that account\'s (PDF)', async () => {
  await uploadReady(DOC_1);
  await uploadReady(DOC_2, { type: 'signature' });
  await uploadReady(DOC_3, { user: BOB });
  state.bucket.put(`profiles/${ALICE}/${DOC_3}.jpg`, new Uint8Array([1]), 'image/jpeg');
  // A pending upload whose row exists but whose bytes landed: also under the prefix.
  state.bucket.put(KEY(ALICE, 'd0c00004-0000-4000-8000-000000000004'), pdfBytes());
  const removed = await removeAccountMedia(ALICE, state.env, state.supabase.fetch, () => new Date());
  assert.equal(removed, 4);
  assert.deepEqual([...state.bucket.objects.keys()], [KEY(BOB, DOC_3)]);
});

// ---------------------------------------------------------------------------
// authorize
// ---------------------------------------------------------------------------

test('authorize creates a pending row and returns a signed PUT for exactly the account key', async () => {
  const result = await post('/toolkit-documents/authorize', authBody());
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
  assert.equal(result.body.status, 'pending');
  assert.equal(result.body.documentId, DOC_1);
  assert.equal(result.body.expiresInSeconds, 300);
  assert.equal('objectKey' in result.body, false, 'the key is never handed to the client');
  const url = new URL(result.body.presignedUrl);
  assert.equal(url.pathname, `/${BUCKET}/${KEY(ALICE, DOC_1)}`);
  assert.equal(url.searchParams.get('X-Amz-Expires'), '300');
  const row = state.supabase.row(DOC_1);
  assert.deepEqual(
    { status: row.status, bucket: row.bucket, type: row.document_type, size: row.size_bytes, pages: row.page_count },
    { status: 'pending_upload', bucket: BUCKET, type: 'scanner', size: pdfBytes().length, pages: 2 });
});

test('authorize accepts all four tools and nothing else', async () => {
  for (const [index, type] of TOOLKIT_DOCUMENT_TYPES.entries()) {
    const id = `d0c1000${index}-0000-4000-8000-00000000000${index}`;
    assert.equal((await post('/toolkit-documents/authorize', authBody({ documentId: id, documentType: type }))).status, 200, type);
  }
  for (const type of ['notes', 'quotation', '', 'SCANNER', null, 7]) {
    const result = await post('/toolkit-documents/authorize', authBody({ documentType: type }));
    assert.equal(result.status, 400, String(type));
    assert.equal(result.body.code, 'unsupported_document_type');
  }
});

test('authorize refuses anything that is not a PDF within the limits, before any row exists', async () => {
  const cases = [
    [{ contentType: 'image/jpeg', documentType: 'combine_pdfs' }, 400, 'unsupported_media_type'],
    [{ contentType: 'image/gif' }, 400, 'unsupported_media_type'],
    [{ contentType: 'application/pdf; charset=binary' }, 400, 'unsupported_media_type'],
    [{ contentType: 'application/x-msdownload' }, 400, 'unsupported_media_type'],
    [{ contentType: undefined }, 400, 'unsupported_media_type'],
    [{ contentLength: 0 }, 400, 'invalid_request'],
    [{ contentLength: -1 }, 400, 'invalid_request'],
    [{ contentLength: 12.5 }, 400, 'invalid_request'],
    [{ contentLength: '100' }, 400, 'invalid_request'],
    [{ contentLength: TOOLKIT_LIMIT_DEFAULTS.documentBytes + 1 }, 413, 'document_too_large'],
    [{ documentId: 'not-a-uuid' }, 400, 'invalid_request'],
    [{ documentId: undefined }, 400, 'invalid_request'],
    [{ contentSha256: 'ABC' }, 400, 'invalid_request'],
    [{ contentSha256: 'A'.repeat(64) }, 400, 'invalid_request'],
    [{ pageCount: 0 }, 400, 'invalid_request'],
    [{ pageCount: 100001 }, 400, 'invalid_request'],
    [{ pageCount: 'two' }, 400, 'invalid_request'],
    [{ sourceCreatedAt: 'yesterday' }, 400, 'invalid_request'],
    [{ sourceCreatedAt: '2026-13-45T99:00:00Z' }, 400, 'invalid_request'],
  ];
  for (const [overrides, status, code] of cases) {
    const result = await post('/toolkit-documents/authorize', authBody(overrides));
    assert.equal(result.status, status, JSON.stringify(overrides));
    if (code) assert.equal(result.body.code, code, JSON.stringify(overrides));
  }
  assert.equal(state.supabase.all().length, 0);
  assert.equal(state.supabase.rpcNames.length, 0, 'rejected before the database is asked');
});

test('titles must be trimmed, printable and at most 200 characters', async () => {
  for (const title of ['', ' padded', 'padded ', 'a\u0000b', 'tab\there', 'line\nbreak', 'evil\u202Efdp', 'iso\u2066late', 'x'.repeat(201), null, 5]) {
    const result = await post('/toolkit-documents/authorize', authBody({ title }));
    assert.equal(result.status, 400, JSON.stringify(title));
    assert.equal(result.body.code, 'invalid_title');
  }
  for (const title of ['x', 'x'.repeat(200), 'عقد إيجار', '契約書 📄', 'a b']) {
    const result = await post('/toolkit-documents/authorize', authBody({ title, documentId: crypto.randomUUID() }));
    assert.equal(result.status, 200, title);
  }
});

test('a retried authorize resumes the same row and never creates a second object identity', async () => {
  const first = await post('/toolkit-documents/authorize', authBody());
  const retry = await post('/toolkit-documents/authorize', authBody());
  assert.equal(first.status, 200);
  assert.equal(retry.status, 200);
  assert.equal(state.supabase.all().length, 1);
  assert.equal(state.supabase.row(DOC_1).upload_attempts, 2);
  assert.equal(new URL(retry.body.presignedUrl).pathname, new URL(first.body.presignedUrl).pathname);
});

test('reusing an id for a different file, tool or hash is refused', async () => {
  await post('/toolkit-documents/authorize', authBody({ contentSha256: 'a'.repeat(64) }));
  for (const overrides of [{ contentLength: 999 }, { documentType: 'signature' }, { contentSha256: 'b'.repeat(64) },
    { contentType: 'image/jpeg', pageCount: 1 }]) {
    const result = await post('/toolkit-documents/authorize', authBody({ contentSha256: 'a'.repeat(64), ...overrides }));
    assert.equal(result.status, 409, JSON.stringify(overrides));
    assert.equal(result.body.code, 'idempotency_mismatch');
  }
});

test('another account can neither take nor learn about an existing id', async () => {
  await uploadReady(DOC_1);
  const probe = await post('/toolkit-documents/authorize', authBody(), { user: BOB });
  assert.equal(probe.status, 409);
  assert.equal(probe.body.code, 'document_id_unavailable');
  assert.equal(state.supabase.row(DOC_1).owner_id, ALICE);
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
});

test('a ready document is not uploaded twice', async () => {
  await uploadReady(DOC_1);
  const again = await post('/toolkit-documents/authorize', authBody());
  assert.equal(again.status, 200);
  assert.deepEqual({ status: again.body.status, alreadyConfirmed: again.body.alreadyConfirmed }, { status: 'ready', alreadyConfirmed: true });
  assert.equal('presignedUrl' in again.body, false);
});

test('anti-abuse limits answer fixed codes, with Retry-After where waiting helps', async () => {
  state.env.TOOLKIT_DOC_MAX_PENDING = '2';
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }));
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  const pending = await post('/toolkit-documents/authorize', authBody({ documentId: DOC_3 }));
  assert.equal(pending.status, 429);
  assert.equal(pending.body.code, 'too_many_pending_uploads');
  assert.ok(Number(pending.headers.get('Retry-After')) > 0);

  state = makeState({ TOOLKIT_DOC_MAX_NEW_PER_HOUR: '1' });
  globalThis.fetch = state.supabase.fetch;
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }));
  const hourly = await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  assert.equal(hourly.status, 429);
  assert.equal(hourly.body.code, 'rate_limited');

  state = makeState({ TOOLKIT_DOC_MAX_ACCOUNT_DOCUMENTS: '1' });
  globalThis.fetch = state.supabase.fetch;
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }));
  const documents = await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  assert.equal(documents.status, 409);
  assert.equal(documents.body.code, 'document_limit_reached');

  state = makeState({ TOOLKIT_DOC_MAX_ACCOUNT_BYTES: String(pdfBytes().length + 10) });
  globalThis.fetch = state.supabase.fetch;
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }));
  const bytes = await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  assert.equal(bytes.status, 409);
  assert.equal(bytes.body.code, 'storage_limit_reached');

  state = makeState({ TOOLKIT_DOC_MAX_BYTES: '50' });
  globalThis.fetch = state.supabase.fetch;
  const large = await post('/toolkit-documents/authorize', authBody());
  assert.equal(large.status, 413);
  assert.equal(large.body.code, 'document_too_large');
});

test('no upload URL is issued while the account is being deleted', async () => {
  state.supabase.deletionJobs = [{ user_id: ALICE, status: 'deleting' }];
  const result = await post('/toolkit-documents/authorize', authBody());
  assert.equal(result.status, 409);
  assert.equal(result.body.code, 'deletion_in_progress');
  assert.equal('presignedUrl' in result.body, false);
});

// ---------------------------------------------------------------------------
// confirm
// ---------------------------------------------------------------------------

test('confirm makes the document ready only after the bytes are verified', async () => {
  await post('/toolkit-documents/authorize', authBody());
  const early = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(early.status, 409);
  assert.equal(early.body.code, 'upload_incomplete');
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');

  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes(), 'application/pdf', '"abc"');
  const done = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(done.status, 200);
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
  assert.equal(state.supabase.row(DOC_1).observed_etag, '"abc"');
});

test('a retried confirm after a lost response is idempotent', async () => {
  await uploadReady(DOC_1);
  const again = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyConfirmed, true);
});

test('confirm rejects and removes bytes of the wrong size, type or shape', async () => {
  const bad = [
    ['wrong size', pdfBytes(10), 'application/pdf', 422, 'upload_rejected'],
    ['wrong content type', pdfBytes(), 'application/x-msdownload', 422, 'media_type_mismatch'],
    ['not a PDF', new Uint8Array(pdfBytes().length).fill(0x41), 'application/pdf', 422, 'media_type_mismatch'],
    ['truncated (no EOF marker)', (() => { const b = pdfBytes(); b.fill(0x20, b.length - 16); return b; })(), 'application/pdf', 422, 'media_type_mismatch'],
  ];
  for (const [label, bytes, contentType, status, code] of bad) {
    state = makeState();
    globalThis.fetch = state.supabase.fetch;
    await post('/toolkit-documents/authorize', authBody({ contentLength: pdfBytes().length }));
    state.bucket.put(KEY(ALICE, DOC_1), bytes, contentType);
    const result = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
    assert.equal(result.status, status, label);
    assert.equal(result.body.code, code, label);
    assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), false, `${label}: the bad object is removed`);
    assert.equal(state.supabase.row(DOC_1).status, 'pending_upload', `${label}: not confirmed`);
    // ...and the device can simply upload again.
    state.bucket.put(KEY(ALICE, DOC_1), pdfBytes());
    assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200, `${label}: retry`);
  }
});

test('another account cannot confirm, and an unknown id is not found', async () => {
  await post('/toolkit-documents/authorize', authBody());
  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes());
  const other = await post('/toolkit-documents/confirm', { documentId: DOC_1 }, { user: BOB });
  assert.equal(other.status, 404);
  assert.equal(other.body.code, 'document_not_found');
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_2 })).status, 404);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: 'nope' })).status, 400);
});

test('a row bound to another bucket or key is never served, signed or deleted by this Worker', async () => {
  state.supabase.seedReady(state.bucket, { id: DOC_1, size: 200, objectBucket: 'broker-wallet-media' });
  state.supabase.seedReady(state.bucket, { id: DOC_2, size: 200, key: `profiles/${ALICE}/toolkit-documents/${DOC_1}.pdf` });
  for (const id of [DOC_1, DOC_2]) {
    const download = await get(`/toolkit-documents/download?documentId=${id}`);
    assert.equal(download.status, 409, id);
    assert.equal(download.body.code, 'document_mismatch');
  }
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.alreadyRemoved, true, 'a row of another bucket is not this Worker\'s to remove');
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
});

// ---------------------------------------------------------------------------
// download
// ---------------------------------------------------------------------------

test('download returns a fresh short-lived signed read for a ready document', async () => {
  const bytes = pdfBytes(300);
  await post('/toolkit-documents/authorize', authBody({ contentLength: bytes.length, contentSha256: 'c'.repeat(64) }));
  state.bucket.put(KEY(ALICE, DOC_1), bytes);
  await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  const result = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
  assert.equal(result.body.sizeBytes, bytes.length);
  assert.equal(result.body.contentSha256, 'c'.repeat(64));
  assert.equal(result.body.expiresInSeconds, 900);
  assert.equal(new URL(result.body.url).pathname, `/${BUCKET}/${KEY(ALICE, DOC_1)}`);
  assert.equal(new URL(result.body.url).searchParams.get('X-Amz-Expires'), '900');
  assert.equal(JSON.stringify(result.body).includes('profiles/'), true, 'only inside the signed URL');
  assert.equal('objectKey' in result.body, false);
  assert.equal(JSON.stringify(state.supabase.rows.get(DOC_1)).includes('X-Amz-Signature'), false, 'no URL is stored');
});

test('download never serves another account\'s, a pending, a deleted or a missing document', async () => {
  await uploadReady(DOC_1);
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  await uploadReady(DOC_3);
  await post('/toolkit-documents/remove', { documentId: DOC_3 });

  const other = await get(`/toolkit-documents/download?documentId=${DOC_1}`, { user: BOB });
  assert.deepEqual([other.status, other.body.code], [404, 'document_not_found']);
  const pending = await get(`/toolkit-documents/download?documentId=${DOC_2}`);
  assert.deepEqual([pending.status, pending.body.code], [409, 'document_not_ready']);
  const deleted = await get(`/toolkit-documents/download?documentId=${DOC_3}`);
  assert.deepEqual([deleted.status, deleted.body.code], [410, 'document_deleted']);

  state.bucket.objects.delete(KEY(ALICE, DOC_1));
  const missing = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.deepEqual([missing.status, missing.body.code], [404, 'object_missing']);

  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes(5));
  const changed = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.deepEqual([changed.status, changed.body.code], [409, 'object_changed']);

  // The same size but another object (a late signed PUT after the confirmation).
  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes(), 'application/pdf', '"swapped"');
  state.supabase.row(DOC_1).size_bytes = pdfBytes().length;
  const swapped = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.deepEqual([swapped.status, swapped.body.code], [409, 'object_changed']);
  assert.equal((await get('/toolkit-documents/download')).status, 400);
});

// ---------------------------------------------------------------------------
// list / status
// ---------------------------------------------------------------------------

function seedMany(count, { user = ALICE, type = 'scanner', start = 0 } = {}) {
  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const id = `d0d00${String(start + i).padStart(3, '0')}-0000-4000-8000-000000000000`;
    ids.push(id);
    state.supabase.seedReady(state.bucket, {
      id, owner: user, type, title: `Doc ${start + i}`, size: 100 + i,
      createdAt: new Date(Date.UTC(2026, 9, 1, 0, 0, start + i)).toISOString(),
    });
  }
  return ids;
}

test('list pages through the account\'s ready documents, newest first, without overlap', async () => {
  const ids = seedMany(5);
  seedMany(3, { user: BOB, start: 50 });
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 })); // pending: not listed
  const seen = [];
  let cursor = null;
  let pages = 0;
  do {
    const result = await get(`/toolkit-documents?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
    assert.equal(result.status, 200);
    assert.ok(result.body.documents.length <= 2);
    seen.push(...result.body.documents.map((d) => d.documentId));
    assert.equal('usage' in result.body, cursor === null, 'usage only on the first page');
    cursor = result.body.nextCursor;
    pages += 1;
  } while (cursor);
  assert.equal(pages, 3);
  assert.deepEqual(seen, [...ids].reverse());
  assert.equal(new Set(seen).size, 5);
});

test('list reports usage and limits, filters by tool, and rejects bad input', async () => {
  seedMany(2, { type: 'signature' });
  seedMany(1, { type: 'scanner', start: 10 });
  const all = await get('/toolkit-documents');
  assert.deepEqual(all.body.usage, { readyCount: 3, readyBytes: 100 + 101 + 100, pendingCount: 0, pendingBytes: 0 });
  assert.equal(all.body.limits.documentBytes, TOOLKIT_LIMIT_DEFAULTS.documentBytes);
  const signed = await get('/toolkit-documents?documentType=signature');
  assert.equal(signed.body.documents.length, 2);
  assert.ok(signed.body.documents.every((d) => d.documentType === 'signature'));
  for (const query of ['limit=0', 'limit=101', 'limit=abc', 'documentType=notes', 'cursor=@@@', `cursor=${btoa('x|y')}`]) {
    assert.equal((await get(`/toolkit-documents?${query}`)).status, 400, query);
  }
  const view = all.body.documents[0];
  assert.deepEqual(Object.keys(view).sort(), ['contentSha256', 'contentType', 'createdAt', 'documentId', 'documentType', 'pageCount', 'sha256Verified', 'sizeBytes', 'sourceCreatedAt', 'title', 'version']);
});

test('list shows nothing of another account or another bucket', async () => {
  seedMany(2, { user: BOB });
  state.supabase.seedReady(state.bucket, { id: DOC_1, size: 100, objectBucket: 'broker-wallet-media' });
  const result = await get('/toolkit-documents');
  assert.deepEqual(result.body.documents, []);
});

test('status answers per id and treats a deleting document as deleted', async () => {
  await uploadReady(DOC_1);
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2 }));
  await uploadReady(DOC_3);
  state.bucket.failDeleteKey = KEY(ALICE, DOC_3);
  await post('/toolkit-documents/remove', { documentId: DOC_3 }); // stays pending_delete
  const OTHER = 'd0c00009-0000-4000-8000-000000000009';
  await uploadReady(OTHER, { user: BOB });
  const result = await post('/toolkit-documents/status', { documentIds: [DOC_1, DOC_2, DOC_3, OTHER, DOC_1, 'd0c0000a-0000-4000-8000-00000000000a'] });
  assert.equal(result.status, 200);
  const byId = Object.fromEntries(result.body.documents.map((d) => [d.documentId, d.state]));
  assert.deepEqual(byId, { [DOC_1]: 'ready', [DOC_2]: 'pending', [DOC_3]: 'deleted' });
  assert.deepEqual(result.body.unknownIds.sort(), [OTHER, 'd0c0000a-0000-4000-8000-00000000000a'].sort());
  for (const documentIds of [[], 'x', null, Array(51).fill(DOC_1), ['nope']]) {
    assert.equal((await post('/toolkit-documents/status', { documentIds })).status, 400, JSON.stringify(documentIds)?.slice(0, 30));
  }
});

// ---------------------------------------------------------------------------
// rename
// ---------------------------------------------------------------------------

test('rename is a compare-and-swap on the version and answers the current title when stale', async () => {
  await uploadReady(DOC_1, { title: 'First' });
  const version = state.supabase.row(DOC_1).version;
  const renamed = await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'Second', expectedVersion: version });
  assert.equal(renamed.status, 200);
  assert.deepEqual({ title: renamed.body.title, version: renamed.body.version }, { title: 'Second', version: version + 1 });

  const stale = await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'Third', expectedVersion: version });
  assert.equal(stale.status, 409);
  assert.deepEqual({ code: stale.body.code, currentTitle: stale.body.currentTitle, currentVersion: stale.body.currentVersion },
    { code: 'stale_version', currentTitle: 'Second', currentVersion: version + 1 });
  assert.equal(state.supabase.row(DOC_1).title, 'Second');
});

test('rename of a pending upload works; another account, a deleted or an invalid rename does not', async () => {
  await post('/toolkit-documents/authorize', authBody());
  const pending = await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'Renamed while pending', expectedVersion: 1 });
  assert.equal(pending.status, 200);

  const other = await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'Mine', expectedVersion: 2 }, { user: BOB });
  assert.equal(other.status, 404);
  assert.equal(state.supabase.row(DOC_1).title, 'Renamed while pending');

  for (const body of [
    { documentId: DOC_1, title: '', expectedVersion: 2 },
    { documentId: DOC_1, title: ' x', expectedVersion: 2 },
    { documentId: DOC_1, title: 'ok' },
    { documentId: DOC_1, title: 'ok', expectedVersion: 0 },
    { documentId: DOC_1, title: 'ok', expectedVersion: '2' },
    { documentId: 'nope', title: 'ok', expectedVersion: 2 },
  ]) {
    assert.equal((await post('/toolkit-documents/rename', body)).status, 400, JSON.stringify(body));
  }

  await post('/toolkit-documents/remove', { documentId: DOC_1 });
  const deleted = await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'Back', expectedVersion: 3 });
  assert.equal(deleted.status, 410);
});

// ---------------------------------------------------------------------------
// remove, races and recovery
// ---------------------------------------------------------------------------

test('remove deletes the object, then leaves a tombstone, and is idempotent', async () => {
  await uploadReady(DOC_1);
  state.supabase.clock = () => Date.now() + 10 * 60 * 1000; // past the signed-PUT window
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.removed, true);
  assert.equal('cleanupPending' in removed.body, false);
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), false);
  assert.equal(state.supabase.row(DOC_1).status, 'deleted');

  const again = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadyRemoved, true);

  // The id is burned: nothing can resurrect it.
  const resurrect = await post('/toolkit-documents/authorize', authBody());
  assert.equal(resurrect.status, 410);
  assert.equal(resurrect.body.code, 'document_deleted');
  const confirmAfter = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirmAfter.status, 410);
});

test('removing another account\'s or an unknown id changes nothing and says nothing', async () => {
  await uploadReady(DOC_1);
  const before = JSON.stringify([...state.supabase.rows.values()]);
  const other = await post('/toolkit-documents/remove', { documentId: DOC_1 }, { user: BOB });
  const unknown = await post('/toolkit-documents/remove', { documentId: DOC_2 });
  assert.deepEqual([other.status, unknown.status], [200, 200]);
  assert.deepEqual(other.body, { removed: true, documentId: DOC_1, alreadyRemoved: true });
  assert.deepEqual(unknown.body, { removed: true, documentId: DOC_2, alreadyRemoved: true });
  assert.equal(JSON.stringify([...state.supabase.rows.values()]), before);
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), true, 'the object is untouched');
});

test('a delete whose R2 removal fails is hidden everywhere and finished by the sweep', async () => {
  await uploadReady(DOC_1);
  state.bucket.failDeleteKey = KEY(ALICE, DOC_1);
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.cleanupPending, true);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_delete');
  assert.deepEqual((await get('/toolkit-documents')).body.documents, []);
  assert.equal((await get(`/toolkit-documents/download?documentId=${DOC_1}`)).status, 410);

  state.bucket.failDeleteKey = null;
  state.supabase.clock = () => Date.now() + 60 * 60 * 1000;
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' }, { now: () => Date.now() + 60 * 60 * 1000 });
  assert.equal(report.pendingDeletes, 1);
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), false);
  assert.equal(state.supabase.row(DOC_1).status, 'deleted');
  // A repeated remove after the sweep is still a clean no-op.
  assert.equal((await post('/toolkit-documents/remove', { documentId: DOC_1 })).body.alreadyRemoved, true);
});

test('delete while an upload is in flight: the late PUT is removed, never resurrected', async () => {
  await post('/toolkit-documents/authorize', authBody());
  // The device deletes before its upload ends; the signed PUT is still valid.
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.cleanupPending, true, 'the tombstone waits for the signed PUT to expire');
  assert.equal(state.supabase.row(DOC_1).status, 'pending_delete');

  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes()); // the late PUT lands after the delete
  const confirm = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirm.status, 410);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_delete');

  const later = () => Date.now() + 15 * 60 * 1000;
  state.supabase.clock = later;
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' }, { now: later });
  assert.equal(report.pendingDeletes, 1);
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), false, 'the late object is gone');
  assert.equal(state.supabase.row(DOC_1).status, 'deleted');
  assert.equal((await post('/toolkit-documents/authorize', authBody())).status, 410);
});

test('a confirm that races a delete never leaves a ready document that was deleted', async () => {
  await post('/toolkit-documents/authorize', authBody());
  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes());
  // The delete lands between the Worker's object check and its confirm call.
  state.supabase.before.confirm_toolkit_document_upload = () => {
    state.supabase.rpc('begin_toolkit_document_delete', { p_user_id: ALICE, p_document_id: DOC_1, p_bucket: BUCKET, p_expected_status: null });
  };
  const confirm = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirm.status, 410);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_delete');
});

test('a timeout after the server confirmed is recovered by status and an idempotent confirm', async () => {
  await post('/toolkit-documents/authorize', authBody());
  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes());
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200); // response "lost"
  const status = await post('/toolkit-documents/status', { documentIds: [DOC_1] });
  assert.equal(status.body.documents[0].state, 'ready');
  const retry = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.deepEqual([retry.status, retry.body.alreadyConfirmed], [200, true]);
  assert.equal(state.supabase.all().length, 1);
});

// ---------------------------------------------------------------------------
// Sweeps
// ---------------------------------------------------------------------------

test('the sweep removes only idle abandoned uploads, with no tombstone, and the id stays usable', async () => {
  await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }));
  state.bucket.put(KEY(ALICE, DOC_1), pdfBytes()); // bytes arrived, never confirmed
  await uploadReady(DOC_2);
  const recent = 'd0c00005-0000-4000-8000-000000000005';
  const day = 24 * 60 * 60 * 1000;
  // DOC_1 was authorized 25 hours ago; the other pending upload just now.
  state.supabase.row(DOC_1).last_authorized_at = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
  await post('/toolkit-documents/authorize', authBody({ documentId: recent }));
  void day;

  const dry = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'dry_run' });
  assert.equal(dry.abandonedUploads, 1);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload', 'dry run changes nothing');
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), true);

  const live = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' });
  assert.equal(live.abandonedUploads, 1);
  assert.equal(state.supabase.row(DOC_1), undefined, 'no tombstone for an abandoned upload');
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_1)), false);
  assert.equal(state.supabase.row(recent).status, 'pending_upload');
  assert.equal(state.supabase.row(DOC_2).status, 'ready');
  // A slow device can still upload that document.
  assert.equal((await post('/toolkit-documents/authorize', authBody({ documentId: DOC_1 }))).status, 200);
});

test('the sweep never acts on another bucket\'s rows or on a row that does not hold its exact key', async () => {
  state.supabase.seedReady(state.bucket, { id: DOC_1, size: 100, objectBucket: 'broker-wallet-media' });
  const stray = state.supabase.seedReady(state.bucket, { id: DOC_2, size: 100 });
  Object.assign(stray, { status: 'pending_upload', confirmed_at: null, last_authorized_at: new Date(0).toISOString(), object_key: `profiles/${BOB}/toolkit-documents/${DOC_2}.pdf` });
  state.supabase.row(DOC_1).status = 'pending_upload';
  state.supabase.row(DOC_1).confirmed_at = null;
  state.supabase.row(DOC_1).last_authorized_at = new Date(0).toISOString();
  state.bucket.put(`profiles/${BOB}/toolkit-documents/${DOC_2}.pdf`, pdfBytes());
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' });
  assert.equal(report.abandonedUploads, 0);
  assert.equal(state.bucket.objects.has(`profiles/${BOB}/toolkit-documents/${DOC_2}.pdf`), true);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
});

test('old tombstones are purged after 180 days, recent ones stay', async () => {
  await uploadReady(DOC_1);
  await uploadReady(DOC_2);
  state.supabase.clock = () => Date.now() + 10 * 60 * 1000;
  await post('/toolkit-documents/remove', { documentId: DOC_1 });
  await post('/toolkit-documents/remove', { documentId: DOC_2 });
  state.supabase.row(DOC_1).deleted_at = new Date(Date.now() - 181 * 24 * 60 * 60 * 1000).toISOString();
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' });
  assert.equal(report.oldTombstones, 1);
  assert.equal(state.supabase.row(DOC_1), undefined);
  assert.equal(state.supabase.row(DOC_2).status, 'deleted');
});

test('a failing sweep step is counted, never thrown, and never logs ids or keys', async () => {
  const logs = [];
  const originalError = console.error;
  const originalLog = console.log;
  console.error = (...args) => logs.push(args.join(' '));
  console.log = (...args) => logs.push(args.join(' '));
  try {
    state.supabase.rpc = () => { throw new Error(`boom ${KEY(ALICE, DOC_1)}`); };
    const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' });
    assert.equal(report.failures, 3);
  } finally {
    console.error = originalError;
    console.log = originalLog;
  }
  assert.ok(logs.length > 0);
  for (const line of logs) {
    assert.equal(line.includes('profiles/'), false);
    assert.equal(line.includes(ALICE), false);
  }
});

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

test('the scheduled handler runs the Toolkit cleanup under its own switch', async () => {
  const waited = [];
  await worker.scheduled({}, state.env, { waitUntil: (promise) => waited.push(promise) });
  await Promise.all(waited);
  assert.ok(waited.length >= 7);
  assert.equal(state.supabase.rpcNames.includes('list_toolkit_document_cleanup'), false, 'off by default');
});

// ===========================================================================
// C1.1: Scanner images, forged content, integrity, route authorization,
// tombstones and the stale offline queue
// ===========================================================================

const FORMATS = {
  pdf: { contentType: 'application/pdf', ext: 'pdf', make: pdfBytes, pages: 2 },
  jpeg: { contentType: 'image/jpeg', ext: 'jpg', make: jpegBytes, pages: 1 },
  png: { contentType: 'image/png', ext: 'png', make: pngBytes, pages: 1 },
};

async function authorizeFormat(format, { id = DOC_1, tool = 'scanner', user = ALICE, bytes = FORMATS[format].make(), overrides = {} } = {}) {
  return post('/toolkit-documents/authorize', authBody({
    documentId: id, documentType: tool, contentType: FORMATS[format].contentType,
    contentLength: bytes.length, contentSha256: sha256Hex(bytes), pageCount: FORMATS[format].pages, ...overrides,
  }), { user });
}

test('the Scanner stores JPEG and PNG scans as original bytes, with separate tool and format fields', async () => {
  for (const [format, id] of [['jpeg', DOC_1], ['png', DOC_2]]) {
    const { contentType, ext } = FORMATS[format];
    const bytes = FORMATS[format].make();
    const authorized = await authorizeFormat(format, { id, bytes });
    assert.equal(authorized.status, 200, format);
    assert.equal(new URL(authorized.body.presignedUrl).pathname, `/${BUCKET}/${KEY(ALICE, id, ext)}`);
    const row = state.supabase.row(id);
    assert.deepEqual(
      { tool: row.document_type, format: row.content_type, key: row.object_key },
      { tool: 'scanner', format: contentType, key: KEY(ALICE, id, ext) });
    state.bucket.put(KEY(ALICE, id, ext), bytes, contentType);
    const confirmed = await post('/toolkit-documents/confirm', { documentId: id });
    assert.equal(confirmed.status, 200, format);
    const download = await get(`/toolkit-documents/download?documentId=${id}`);
    assert.equal(download.status, 200);
    assert.deepEqual(
      { type: download.body.documentType, format: download.body.contentType, size: download.body.sizeBytes, sha: download.body.contentSha256 },
      { type: 'scanner', format: contentType, size: bytes.length, sha: sha256Hex(bytes) });
    assert.equal(new URL(download.body.url).pathname, `/${BUCKET}/${KEY(ALICE, id, ext)}`);
  }
  const listed = (await get('/toolkit-documents')).body.documents;
  assert.deepEqual(listed.map((d) => d.contentType).sort(), ['image/jpeg', 'image/png']);
  assert.ok(listed.every((d) => d.documentType === 'scanner'));
});

test('only the Scanner may store an image; every other tool is PDF only', async () => {
  for (const tool of ['combine_pdfs', 'image_to_pdf', 'signature']) {
    for (const format of ['jpeg', 'png']) {
      const result = await authorizeFormat(format, { tool });
      assert.equal(result.status, 400, `${tool} ${format}`);
      assert.equal(result.body.code, 'unsupported_media_type');
    }
    assert.equal((await authorizeFormat('pdf', { tool, id: crypto.randomUUID() })).status, 200, tool);
  }
  assert.equal(state.supabase.all().length, 3, 'only the three PDFs exist');
});

test('a forged or unusual MIME label is refused before any row exists', async () => {
  for (const contentType of ['image/gif', 'image/webp', 'image/heic', 'IMAGE/JPEG', 'image/jpeg; charset=utf-8',
    'image/jpg', 'application/octet-stream', 'text/html', 'image/svg+xml', '', null, 7, ['image/png']]) {
    const result = await post('/toolkit-documents/authorize', authBody({ contentType }));
    assert.equal(result.status, 400, JSON.stringify(contentType));
    assert.equal(result.body.code, 'unsupported_media_type');
  }
  assert.equal(state.supabase.rpcNames.length, 0);
});

test('a client-supplied key, file name or extension is ignored: the server builds the whole key', async () => {
  const bytes = jpegBytes();
  const result = await post('/toolkit-documents/authorize', authBody({
    contentType: 'image/jpeg', contentLength: bytes.length, contentSha256: sha256Hex(bytes), pageCount: 1,
    objectKey: `profiles/${BOB}/toolkit-documents/x.pdf`, fileName: '../../evil.exe', extension: 'exe', filename: 'a.html',
    bucket: 'other-bucket', ownerId: BOB,
  }));
  assert.equal(result.status, 200);
  assert.equal(new URL(result.body.presignedUrl).pathname, `/${BUCKET}/${KEY(ALICE, DOC_1, 'jpg')}`);
  const row = state.supabase.row(DOC_1);
  assert.deepEqual([row.object_key, row.bucket, row.owner_id], [KEY(ALICE, DOC_1, 'jpg'), BUCKET, ALICE]);
});

test('an image is one page and has its own, smaller, size limit', async () => {
  const bytes = pngBytes();
  const manyPages = await authorizeFormat('png', { overrides: { pageCount: 3 } });
  assert.deepEqual([manyPages.status, manyPages.body.code], [400, 'invalid_request']);
  const tooBig = await authorizeFormat('png', { overrides: { contentLength: TOOLKIT_LIMIT_DEFAULTS.imageBytes + 1 } });
  assert.deepEqual([tooBig.status, tooBig.body.code], [413, 'document_too_large']);
  assert.equal(state.supabase.rpcNames.length, 0, 'refused by the Worker before the database is asked');
  assert.ok(TOOLKIT_LIMIT_DEFAULTS.imageBytes < TOOLKIT_LIMIT_DEFAULTS.documentBytes);
  // The same length is fine for a PDF, whose limit is larger.
  const pdf = await authorizeFormat('pdf', { overrides: { contentLength: TOOLKIT_LIMIT_DEFAULTS.imageBytes + 1 } });
  assert.equal(pdf.status, 200);
  // The image limit is configurable and clamped to its ceiling.
  state = makeState({ TOOLKIT_DOC_MAX_IMAGE_BYTES: String(bytes.length - 1) });
  globalThis.fetch = state.supabase.fetch;
  assert.equal((await authorizeFormat('png', { bytes })).status, 413);
  assert.equal(toolkitLimits({ TOOLKIT_DOC_MAX_IMAGE_BYTES: '999999999999' }).imageBytes, TOOLKIT_LIMIT_CEILINGS.imageBytes);
});

test('the device digest and creation time are required, and an acknowledgement must be a boolean', async () => {
  for (const overrides of [
    { contentSha256: undefined }, { contentSha256: null }, { sourceCreatedAt: undefined }, { sourceCreatedAt: null },
    { acknowledgeStale: 'yes' }, { acknowledgeStale: 1 },
  ]) {
    const result = await post('/toolkit-documents/authorize', authBody(overrides));
    assert.deepEqual([result.status, result.body.code], [400, 'invalid_request'], JSON.stringify(overrides));
  }
  assert.equal(state.supabase.all().length, 0);
});

test('forged content is refused for every declared/actual combination and the object is removed', async () => {
  for (const declared of Object.keys(FORMATS)) {
    for (const actual of Object.keys(FORMATS)) {
      if (declared === actual) continue;
      state = makeState();
      globalThis.fetch = state.supabase.fetch;
      const bytes = FORMATS[actual].make();
      assert.equal((await authorizeFormat(declared, { bytes })).status, 200);
      // The client labels the upload with the declared type but sends other bytes...
      state.bucket.put(KEY(ALICE, DOC_1, FORMATS[declared].ext), bytes, FORMATS[declared].contentType);
      const forged = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
      assert.deepEqual([forged.status, forged.body.code], [422, 'media_type_mismatch'], `${actual} as ${declared}`);
      assert.equal(state.bucket.objects.size, 0);
      assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
      // ...or labels it honestly with the actual type, which is not the declared one.
      state.bucket.put(KEY(ALICE, DOC_1, FORMATS[declared].ext), bytes, FORMATS[actual].contentType);
      const relabelled = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
      assert.deepEqual([relabelled.status, relabelled.body.code], [422, 'media_type_mismatch'], `${actual} labelled ${actual}`);
      assert.equal(state.bucket.objects.size, 0);
    }
  }
});

test('a missing stored content type, or random bytes, never makes a document ready', async () => {
  const bytes = jpegBytes();
  await authorizeFormat('jpeg', { bytes });
  state.bucket.objects.set(KEY(ALICE, DOC_1, 'jpg'), { bytes, contentType: undefined, etag: '"x"' });
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 422);
  const noise = new Uint8Array(bytes.length).map((_, i) => (i * 37) % 251);
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), noise, 'image/jpeg');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 422);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
});

test('truncated images and PDFs are not complete containers', async () => {
  const cases = {
    'jpeg without its end marker': ['jpeg', (b) => b.slice(0, b.length - 2)],
    'jpeg with trailing junk': ['jpeg', (b) => Uint8Array.from([...b, 1, 2, 3])],
    'png without IEND': ['png', (b) => b.slice(0, b.length - 12)],
    'png with a zero-size IHDR': ['png', (b) => { const c = b.slice(); c[16] = c[17] = c[18] = c[19] = 0; return c; }],
    'png with a wrong IHDR length': ['png', (b) => { const c = b.slice(); c[11] = 12; return c; }],
    'pdf without %%EOF': ['pdf', (b) => b.slice(0, b.length - 8)],
  };
  for (const [label, [format, damage]] of Object.entries(cases)) {
    state = makeState();
    globalThis.fetch = state.supabase.fetch;
    const bytes = damage(FORMATS[format].make());
    assert.equal((await authorizeFormat(format, { bytes })).status, 200, label);
    state.bucket.put(KEY(ALICE, DOC_1, FORMATS[format].ext), bytes, FORMATS[format].contentType);
    const result = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
    assert.deepEqual([result.status, result.body.code], [422, 'media_type_mismatch'], label);
    assert.equal(state.supabase.row(DOC_1).status, 'pending_upload', label);
  }
  // JPEG may end with a few padding zeros after its end marker.
  state = makeState();
  globalThis.fetch = state.supabase.fetch;
  const padded = Uint8Array.from([...jpegBytes(), 0, 0, 0, 0]);
  await authorizeFormat('jpeg', { bytes: padded });
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), padded, 'image/jpeg');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('without digest verification the digest stays a device claim; with it the Worker proves it', async () => {
  // Off (the default): ready, and honestly marked as not server-verified.
  const bytes = pngBytes();
  await authorizeFormat('png', { bytes, overrides: { contentSha256: 'e'.repeat(64) } });
  state.bucket.put(KEY(ALICE, DOC_1, 'png'), bytes, 'image/png');
  const unverified = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.deepEqual([unverified.status, unverified.body.sha256Verified], [200, false]);
  const download = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.deepEqual([download.body.sha256Verified, download.body.contentSha256], [false, 'e'.repeat(64)]);

  // On: a matching digest is recorded as verified...
  state = makeState({ TOOLKIT_DOC_VERIFY_SHA256: 'true' });
  globalThis.fetch = state.supabase.fetch;
  await authorizeFormat('png', { bytes });
  state.bucket.put(KEY(ALICE, DOC_1, 'png'), bytes, 'image/png');
  const verified = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.deepEqual([verified.status, verified.body.sha256Verified], [200, true]);
  assert.equal(state.supabase.row(DOC_1).sha256_verified, true);
  const listed = (await get('/toolkit-documents')).body.documents[0];
  assert.equal(listed.sha256Verified, true);

  // ...and a different digest is refused, the object removed, the document left pending.
  state = makeState({ TOOLKIT_DOC_VERIFY_SHA256: 'true' });
  globalThis.fetch = state.supabase.fetch;
  await authorizeFormat('png', { bytes, overrides: { contentSha256: 'e'.repeat(64) } });
  state.bucket.put(KEY(ALICE, DOC_1, 'png'), bytes, 'image/png');
  const mismatch = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.deepEqual([mismatch.status, mismatch.body.code], [422, 'integrity_mismatch']);
  assert.equal(state.bucket.objects.size, 0);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
});

test('the ETag is an object-identity token, never taken as a digest', async () => {
  const bytes = jpegBytes();
  await authorizeFormat('jpeg', { bytes, overrides: { contentSha256: 'f'.repeat(64) } });
  // An ETag that looks like the declared SHA-256 proves nothing.
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), bytes, 'image/jpeg', '"' + 'f'.repeat(64) + '"');
  const result = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(result.body.sha256Verified, false);
});

test('an interrupted confirmation of an image resumes, and a late replacement object is detected', async () => {
  const bytes = jpegBytes();
  await authorizeFormat('jpeg', { bytes });
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).body.code, 'upload_incomplete');
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), bytes, 'image/jpeg', '"first"');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).body.alreadyConfirmed, true);
  // A signed PUT used again after the confirmation replaces the object: caught on download.
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), bytes, 'image/jpeg', '"second"');
  const swapped = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.deepEqual([swapped.status, swapped.body.code], [409, 'object_changed']);
});

test('every route refuses a replaced session before any document function runs', async () => {
  state.supabase.sessionCurrent = false;
  const routes = [
    ['POST', '/toolkit-documents/authorize', authBody()],
    ['POST', '/toolkit-documents/confirm', { documentId: DOC_1 }],
    ['GET', '/toolkit-documents', undefined],
    ['POST', '/toolkit-documents/status', { documentIds: [DOC_1] }],
    ['GET', `/toolkit-documents/download?documentId=${DOC_1}`, undefined],
    ['POST', '/toolkit-documents/rename', { documentId: DOC_1, title: 'x', expectedVersion: 1 }],
    ['POST', '/toolkit-documents/remove', { documentId: DOC_1 }],
  ];
  for (const [method, path, body] of routes) {
    const result = await call(method, path, { body });
    assert.deepEqual([result.status, result.body.code], [403, 'session_superseded'], path);
  }
  assert.equal(state.supabase.rpcNames.length, 0);
  state.supabase.sessionCurrent = true;
  for (const [method, path, body] of routes) {
    const none = await call(method, path, { body, user: null });
    assert.equal(none.status, 401, path);
  }
});

test('another account cannot read, confirm, rename or remove an image, and nothing of it changes', async () => {
  const bytes = pngBytes();
  await authorizeFormat('png', { id: DOC_2, bytes });
  state.bucket.put(KEY(ALICE, DOC_2, 'png'), bytes, 'image/png');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_2 })).status, 200);
  const before = JSON.stringify(state.supabase.row(DOC_2));
  const attempts = [
    await get(`/toolkit-documents/download?documentId=${DOC_2}`, { user: BOB }),
    await post('/toolkit-documents/confirm', { documentId: DOC_2 }, { user: BOB }),
    await post('/toolkit-documents/rename', { documentId: DOC_2, title: 'Mine', expectedVersion: 2 }, { user: BOB }),
  ];
  assert.deepEqual(attempts.map((a) => a.status), [404, 404, 404]);
  assert.deepEqual((await get('/toolkit-documents', { user: BOB })).body.documents, []);
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_2 }, { user: BOB });
  assert.equal(removed.body.alreadyRemoved, true);
  const taken = await authorizeFormat('png', { id: DOC_2, bytes, user: BOB });
  assert.deepEqual([taken.status, taken.body.code], [409, 'document_id_unavailable']);
  assert.equal(JSON.stringify(state.supabase.row(DOC_2)), before);
  assert.equal(state.bucket.objects.has(KEY(ALICE, DOC_2, 'png')), true);
});

test('wrong object keys, extensions and ids are never served, signed or deleted', async () => {
  const OTHER = 'd0c00009-0000-4000-8000-000000000009';
  const rows = {
    'a key naming another document': { id: DOC_1, key: KEY(ALICE, OTHER) },
    'a key in another account': { id: DOC_2, key: KEY(BOB, DOC_2) },
    'a jpeg row with a .pdf key': { id: DOC_3, key: KEY(ALICE, DOC_3, 'pdf'), contentType: 'image/jpeg' },
    'a png row with a .jpg key': { id: OTHER, key: KEY(ALICE, OTHER, 'jpg'), contentType: 'image/png' },
    'a key with traversal': { id: 'd0c0000a-0000-4000-8000-00000000000a', key: `profiles/${ALICE}/toolkit-documents/../x.pdf` },
  };
  for (const [label, { id, key, contentType }] of Object.entries(rows)) {
    const row = state.supabase.seedReady(state.bucket, { id, size: 200, key });
    if (contentType) row.content_type = contentType;
    for (const result of [
      await get(`/toolkit-documents/download?documentId=${id}`),
      await post('/toolkit-documents/confirm', { documentId: id }),
    ]) {
      assert.deepEqual([result.status, result.body.code], [409, 'document_mismatch'], label);
    }
  }
  const removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  assert.equal(removed.status, 409, 'a row whose key is not its own is never deleted');
  assert.equal(state.bucket.objects.has(KEY(ALICE, OTHER)), true);
  for (const bad of ['not-a-uuid', '', '../x', 'D0C00001-0000-4000-8000-000000000001-extra', 42]) {
    assert.equal((await post('/toolkit-documents/confirm', { documentId: bad })).status, 400, String(bad));
  }
  // Upper-case ids are canonicalized, never a different document.
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_2.toUpperCase() })).body.code, 'document_mismatch');
});

test('Delete Account removes the account\'s PDFs, JPEGs and PNGs and nobody else\'s', async () => {
  await uploadReady(DOC_1);
  await uploadReady(DOC_2, { contentType: 'image/jpeg', bytes: jpegBytes(), ext: 'jpg' });
  await uploadReady(DOC_3, { contentType: 'image/png', bytes: pngBytes(), ext: 'png' });
  const BOBS = 'd0c0000b-0000-4000-8000-00000000000b';
  await uploadReady(BOBS, { user: BOB, contentType: 'image/png', bytes: pngBytes(), ext: 'png' });
  for (const key of state.bucket.objects.keys()) {
    assert.ok(key.startsWith(key.includes(BOB) ? accountObjectPrefix(BOB) : accountObjectPrefix(ALICE)), key);
  }
  const removed = await removeAccountMedia(ALICE, state.env, state.supabase.fetch, () => new Date());
  assert.equal(removed, 3);
  assert.deepEqual([...state.bucket.objects.keys()], [KEY(BOB, BOBS, 'png')]);
});

test('an expired tombstone cannot resurrect a deleted document; a stale queued document needs an explicit acknowledgement', async () => {
  const day = 24 * 60 * 60 * 1000;
  await uploadReady(DOC_1);
  state.supabase.clock = () => Date.now() + 10 * 60 * 1000;
  assert.equal((await post('/toolkit-documents/remove', { documentId: DOC_1 })).status, 200);
  const deletedAt = Date.now() - 181 * day;
  state.supabase.row(DOC_1).deleted_at = new Date(deletedAt).toISOString();

  // While the tombstone exists the id is simply dead.
  assert.equal((await post('/toolkit-documents/authorize', authBody())).status, 410);

  // The retention sweep purges it and the account remembers the latest purged deletion time.
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' });
  assert.equal(report.oldTombstones, 1);
  assert.equal(state.supabase.row(DOC_1), undefined);
  assert.equal(state.supabase.floors.get(ALICE), deletedAt);

  // An old offline queue replaying the same document is NOT re-created...
  const stale = await post('/toolkit-documents/authorize', authBody({ sourceCreatedAt: new Date(deletedAt - day).toISOString() }));
  assert.deepEqual([stale.status, stale.body.code], [409, 'stale_document']);
  assert.equal(state.supabase.row(DOC_1), undefined);
  assert.equal(stale.headers.get('Cache-Control'), 'no-store');
  // ...nor is any other document the device made before then...
  const other = await post('/toolkit-documents/authorize', authBody({ documentId: DOC_2, sourceCreatedAt: new Date(deletedAt - 5 * day).toISOString() }));
  assert.equal(other.body.code, 'stale_document');
  // ...unless the user explicitly acknowledged it.
  const acknowledged = await post('/toolkit-documents/authorize',
    authBody({ sourceCreatedAt: new Date(deletedAt - day).toISOString(), acknowledgeStale: true }));
  assert.equal(acknowledged.status, 200);
  // A document made after that time is unaffected, and so is another account.
  assert.equal((await post('/toolkit-documents/authorize', authBody({ documentId: DOC_3, sourceCreatedAt: new Date(deletedAt + day).toISOString() }))).status, 200);
  const bobs = await post('/toolkit-documents/authorize',
    authBody({ documentId: 'd0c0000c-0000-4000-8000-00000000000c', sourceCreatedAt: new Date(deletedAt - day).toISOString() }), { user: BOB });
  assert.equal(bobs.status, 200);
});

test('a repeated delete and a delete racing a retried upload leave exactly one tombstone', async () => {
  await authorizeFormat('jpeg');
  assert.equal((await post('/toolkit-documents/remove', { documentId: DOC_1 })).status, 200);
  assert.equal((await post('/toolkit-documents/remove', { documentId: DOC_1 })).status, 200);
  // The retried upload of the same id after the delete is refused and creates nothing.
  const retry = await authorizeFormat('jpeg');
  assert.deepEqual([retry.status, retry.body.code], [410, 'document_deleted']);
  state.bucket.put(KEY(ALICE, DOC_1, 'jpg'), jpegBytes(), 'image/jpeg');
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 410);
  assert.equal(state.supabase.all().length, 1);
  assert.equal(state.supabase.all()[0].title === 'Lease scan' || state.supabase.all()[0].status !== 'ready', true);
});
