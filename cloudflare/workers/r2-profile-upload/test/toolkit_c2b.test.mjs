// C2B corrections, proven against the Worker with the in-memory doubles in toolkit_fakes.mjs.
//
//   A. Abandoned-upload cleanup is claim-first: it can never delete a ready document's object.
//   B. A signed PUT is write-once: replaying it after the object exists is refused.
//
// WHAT THESE TESTS ARE: deterministic interleavings. A hook fires at the exact step where the
// race window is (after the sweep listed a row, before it claims it; after the claim, before the
// object removal), and the device's calls are made through the real routes. The database is a
// MODEL of the SQL outcome for outcome (the real SQL is exercised by supabase/tests/
// toolkit_documents_test.sql and by the Worker-on-real-SQL integration run); R2 is a MODEL of its
// documented conditional PutObject behavior. They do NOT prove how real R2 treats a presigned PUT
// that carries If-None-Match: that is a staging proof (docs/toolbox/cloud-documents-rollout.md).
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { runToolkitDocumentCleanup } from '../worker.js';
import { DISCARD_DELETE_DEADLINE_MS, DISCARD_LEASE_SECONDS, TOOLKIT_UPLOAD_HEADERS } from '../toolkit_documents.js';
import {
  ALICE, BOB, DOC_1, DOC_2, jpegBytes, makeState, pdfBytes, sha256Hex,
} from './toolkit_fakes.mjs';

let state;
let originalFetch;
beforeEach(() => {
  state = makeState();
  originalFetch = globalThis.fetch;
  globalThis.fetch = state.supabase.fetch;
});
afterEach(() => { globalThis.fetch = originalFetch; });

async function call(method, path, { user = ALICE, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  headers.Authorization = user === ALICE ? 'Bearer token-a' : 'Bearer token-b';
  const response = await worker.fetch(new Request(`https://worker.test${path}`, {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), state.env, {});
  return { status: response.status, body: await response.json(), headers: response.headers };
}
const post = (path, body, options) => call('POST', path, { ...options, body });
const get = (path, options) => call('GET', path, options);

const KEY = (user, id, ext = 'pdf') => `profiles/${user}/toolkit-documents/${id}.${ext}`;
function authBody(documentId = DOC_1, bytes = pdfBytes(), overrides = {}) {
  return {
    documentId, documentType: 'scanner', title: 'Lease scan', contentType: 'application/pdf',
    contentLength: bytes.length, contentSha256: sha256Hex(bytes), pageCount: 2,
    sourceCreatedAt: '2026-10-19T08:00:00.000Z', ...overrides,
  };
}
const HOUR = 60 * 60 * 1000;
const MIN = 60 * 1000;

/** The device's PUT to a signed URL, sending exactly the headers the Worker said to send. */
function devicePut(authorized, bytes = pdfBytes(), { sendHeaders = true, contentType = 'application/pdf' } = {}) {
  return state.bucket.putViaSignedUrl(authorized.body.presignedUrl, {
    headers: sendHeaders ? { ...(authorized.body.uploadHeaders ?? {}), 'Content-Type': contentType } : { 'Content-Type': contentType },
    bytes,
    contentType,
  });
}

async function authorizePending(id = DOC_1, bytes = pdfBytes()) {
  const authorized = await post('/toolkit-documents/authorize', authBody(id, bytes));
  assert.equal(authorized.status, 200, JSON.stringify(authorized.body));
  return authorized;
}

/** A pending upload whose authorization is 25 hours old (abandoned). */
async function abandonedUpload(id = DOC_1, { withObject = true } = {}) {
  const authorized = await authorizePending(id);
  if (withObject) assert.equal(devicePut(authorized).status, 200);
  state.supabase.row(id).last_authorized_at = new Date(Date.now() - 25 * HOUR).toISOString();
  return authorized;
}

const sweepOn = (options = {}) => runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'on' }, options);
const KEY1 = KEY(ALICE, DOC_1);

// ---------------------------------------------------------------------------
// A. Abandoned-upload cleanup is claim-first
// ---------------------------------------------------------------------------

test('RACE: the device confirms between the sweep listing a stale upload and claiming it - the verified object is never deleted', async () => {
  await abandonedUpload();
  let interleaved = false;
  state.supabase.before.claim_abandoned_toolkit_document = async () => {
    interleaved = true; // the sweep has listed the row; the device wins the race
    const again = await post('/toolkit-documents/authorize', authBody());
    assert.equal(again.status, 200);
    const confirmed = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
    assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  };
  const report = await sweepOn();
  assert.equal(interleaved, true, 'the interleaving really happened');
  assert.deepEqual(state.bucket.deleted, [], 'no object was deleted');
  assert.equal(state.bucket.objects.has(KEY1), true);
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
  assert.equal(report.abandonedUploads, 0);
  assert.equal(report.failures, 0);
  const download = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.equal(download.status, 200, 'the document is still usable');
});

test('RACE: the device re-authorizes between the listing and the claim - the upload in progress is left alone', async () => {
  await abandonedUpload();
  state.supabase.before.claim_abandoned_toolkit_document = async () => {
    assert.equal((await post('/toolkit-documents/authorize', authBody())).status, 200);
  };
  const report = await sweepOn();
  assert.deepEqual(state.bucket.deleted, []);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
  assert.equal(report.abandonedUploads, 0);
  assert.equal(state.bucket.objects.has(KEY1), true);
});

test('RACE: after the claim the document can neither be authorized, confirmed nor renamed, so it can never become ready', async () => {
  await abandonedUpload();
  let observed = null;
  state.bucket.beforeDelete = async () => { // claimed, object not yet removed
    observed = {
      row: state.supabase.row(DOC_1).status,
      authorize: await post('/toolkit-documents/authorize', authBody()),
      confirm: await post('/toolkit-documents/confirm', { documentId: DOC_1 }),
      rename: await post('/toolkit-documents/rename', { documentId: DOC_1, title: 'New title', expectedVersion: 1 }),
      status: await post('/toolkit-documents/status', { documentIds: [DOC_1] }),
      download: await get(`/toolkit-documents/download?documentId=${DOC_1}`),
      bob: await post('/toolkit-documents/authorize', authBody(), { user: BOB }),
    };
    state.bucket.beforeDelete = null;
  };
  const report = await sweepOn();
  assert.equal(observed.row, 'pending_discard');
  for (const name of ['authorize', 'confirm', 'rename']) {
    assert.equal(observed[name].status, 503, name);
    assert.equal(observed[name].body.code, 'document_cleanup_in_progress', name);
    assert.equal(observed[name].headers.get('Retry-After'), '60', name);
  }
  assert.deepEqual(observed.status.body.documents, [{ documentId: DOC_1, state: 'pending', version: observed.status.body.documents[0].version }]);
  assert.equal(observed.download.status, 409);
  // Another account learns nothing about the claim.
  assert.equal(observed.bob.status, 409);
  assert.equal(observed.bob.body.code, 'document_id_unavailable');
  assert.equal(report.abandonedUploads, 1);
  assert.equal(state.supabase.row(DOC_1), undefined, 'no tombstone for an abandoned upload');
  assert.equal(state.bucket.objects.has(KEY1), false);
  // The id is usable again, and a retried upload completes.
  const again = await authorizePending();
  assert.equal(devicePut(again).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('RACE: the user deletes the document while its cleanup holds the claim - the delete wins and tombstones it', async () => {
  await abandonedUpload();
  let removed = null;
  state.bucket.beforeDelete = async () => {
    state.bucket.beforeDelete = null;
    removed = await post('/toolkit-documents/remove', { documentId: DOC_1 });
  };
  const report = await sweepOn();
  assert.equal(removed.status, 200);
  assert.equal(state.supabase.row(DOC_1).status, 'deleted', 'the delete path wrote its tombstone');
  assert.equal(state.supabase.row(DOC_1).discard_claimed_at, null);
  assert.equal(report.abandonedUploads, 0, 'the cleanup did not discard a document that is being deleted');
  assert.equal(report.failures, 0);
  assert.equal(state.bucket.objects.has(KEY1), false);
  assert.equal((await post('/toolkit-documents/authorize', authBody())).status, 410, 'and it does not come back');
});

test('RACE: two cleanups on the same row - exactly one claims, the object is removed once', async () => {
  await abandonedUpload();
  let nested = null;
  state.supabase.before.claim_abandoned_toolkit_document = async () => {
    state.supabase.before.claim_abandoned_toolkit_document = null;
    nested = await sweepOn(); // a second cleanup that listed the same row runs to completion first
  };
  const first = await sweepOn();
  assert.equal(nested.abandonedUploads, 1);
  assert.equal(first.abandonedUploads, 0, 'the row was already gone when the first one claimed');
  assert.deepEqual(state.bucket.deleted, [KEY1], 'removed exactly once');
  assert.equal(state.supabase.row(DOC_1), undefined);
});

test('RACE: a second cleanup that starts while the first holds the claim neither lists nor removes anything', async () => {
  await abandonedUpload();
  let nested = null;
  state.bucket.beforeDelete = async () => {
    state.bucket.beforeDelete = null;
    state.supabase.rpcNames.length = 0;
    nested = await sweepOn();
  };
  const first = await sweepOn();
  assert.equal(nested.abandonedUploads, 0);
  assert.equal(nested.failures, 0);
  assert.equal(first.abandonedUploads, 1);
  assert.equal(state.supabase.rpcNames.includes('claim_abandoned_toolkit_document'), false, 'nothing to claim during the lease');
  assert.deepEqual(state.bucket.deleted, [KEY1]);
});

test('a failed object removal leaves the row claimed and recoverable; after the lease another cleanup finishes it', async () => {
  await abandonedUpload();
  state.bucket.failDeleteKey = KEY1;
  const first = await sweepOn();
  assert.equal(first.failures, 1);
  assert.equal(first.abandonedUploads, 0);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_discard', 'still claimed, never ready');
  assert.equal(state.bucket.objects.has(KEY1), true, 'the object is still there');

  // Within the lease nothing is retried, and the device is told to wait.
  const early = await sweepOn();
  assert.equal(early.abandonedUploads + early.failures, 0);
  assert.equal((await post('/toolkit-documents/authorize', authBody())).status, 503);

  // The lease passes and storage works again: the next cleanup takes the row over under a new claim.
  const oldClaim = state.supabase.row(DOC_1).discard_claimed_at;
  state.supabase.row(DOC_1).discard_claimed_at = new Date(Date.now() - (DISCARD_LEASE_SECONDS + 60) * 1000).toISOString();
  state.bucket.failDeleteKey = null;
  const later = await sweepOn();
  assert.equal(later.abandonedUploads, 1);
  assert.equal(state.supabase.row(DOC_1), undefined);
  assert.equal(state.bucket.objects.has(KEY1), false);
  assert.notEqual(oldClaim, undefined);
});

test('a cleanup that stalled past its deadline does not delete: the row stays claimed for the next one', async () => {
  await abandonedUpload();
  const base = Date.now();
  let calls = 0;
  const report = await sweepOn({
    now: () => {
      calls += 1;
      // call 1: sweep start; call 2: before the claim; call 3: after the claim, past the deadline
      return calls <= 2 ? base : base + DISCARD_DELETE_DEADLINE_MS + 1000;
    },
  });
  assert.equal(report.failures, 1);
  assert.deepEqual(state.bucket.deleted, []);
  assert.equal(state.bucket.objects.has(KEY1), true);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_discard');
});

test('a dry run claims nothing and changes nothing', async () => {
  await abandonedUpload();
  const report = await runToolkitDocumentCleanup({ ...state.env, TOOLKIT_DOCUMENT_SWEEP_MODE: 'dry_run' });
  assert.equal(report.abandonedUploads, 1);
  assert.equal(state.supabase.rpcNames.includes('claim_abandoned_toolkit_document'), false);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
  assert.deepEqual(state.bucket.deleted, []);
});

test('a ready document is never claimed or deleted, whatever its age', async () => {
  const authorized = await authorizePending();
  assert.equal(devicePut(authorized).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
  state.supabase.row(DOC_1).last_authorized_at = new Date(Date.now() - 400 * 24 * HOUR).toISOString();
  const report = await sweepOn();
  assert.equal(report.abandonedUploads + report.failures, 0);
  assert.deepEqual(state.bucket.deleted, []);
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
});

test('the cleanup only ever claims its own bucket\'s rows and removes only the key the claim returned', async () => {
  await abandonedUpload();
  state.supabase.row(DOC_1).bucket = 'broker-wallet-media'; // production's row, seen by the staging Worker
  const report = await sweepOn();
  assert.equal(report.abandonedUploads + report.failures, 0);
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
  assert.deepEqual(state.bucket.deleted, []);
});

test('a confirm against a claimed upload neither examines nor deletes anything', async () => {
  await abandonedUpload();
  state.bucket.failDeleteKey = KEY1;
  await sweepOn(); // claimed; the object is still there because its removal failed
  state.bucket.failDeleteKey = null;
  state.bucket.put(KEY1, new TextEncoder().encode('junk')); // would be rejected and removed if examined
  const removedBefore = state.bucket.deleted.length;
  const confirm = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirm.status, 503);
  assert.equal(confirm.body.code, 'document_cleanup_in_progress');
  assert.equal(state.bucket.deleted.length, removedBefore);
  assert.equal(state.bucket.objects.has(KEY1), true);
});

test('RACE: the cleanup claims the row after the confirm read it but before the confirm commits - the confirm is refused', async () => {
  await abandonedUpload();
  state.supabase.before.confirm_toolkit_document_upload = () => {
    state.supabase.before.confirm_toolkit_document_upload = null;
    const claimed = state.supabase.rpc('claim_abandoned_toolkit_document', {
      p_user_id: ALICE, p_document_id: DOC_1, p_bucket: state.env.R2_BUCKET_NAME,
      p_cutoff: new Date().toISOString(), p_lease_seconds: DISCARD_LEASE_SECONDS,
    });
    assert.equal(claimed[0].outcome, 'claimed');
  };
  const confirm = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirm.status, 503);
  assert.equal(confirm.body.code, 'document_cleanup_in_progress');
  assert.equal(state.supabase.row(DOC_1).status, 'pending_discard', 'it did not become ready');
  assert.equal((await sweepOn()).abandonedUploads, 0, 'the lease is still valid');
});

test('the cleanup never removes a key other than the row\'s own, even if the claim answers with another', async () => {
  await abandonedUpload();
  const other = KEY(ALICE, DOC_2);
  state.bucket.put(other, pdfBytes());
  state.supabase.after.claim_abandoned_toolkit_document = (result) => { result[0].object_key = other; };
  const report = await sweepOn();
  assert.equal(report.failures, 1);
  assert.deepEqual(state.bucket.deleted, []);
  assert.equal(state.bucket.objects.has(other), true);
  assert.equal(state.bucket.objects.has(KEY1), true);
});

// ---------------------------------------------------------------------------
// B. A signed PUT is write-once
// ---------------------------------------------------------------------------

test('authorize tells the device which header the PUT must carry and signs it', async () => {
  const authorized = await authorizePending();
  assert.deepEqual(authorized.body.uploadHeaders, TOOLKIT_UPLOAD_HEADERS);
  assert.deepEqual(authorized.body.uploadHeaders, { 'If-None-Match': '*' });
  const url = new URL(authorized.body.presignedUrl);
  assert.equal(url.searchParams.get('X-Amz-SignedHeaders'), 'host;if-none-match');
  assert.equal(url.searchParams.get('X-Amz-Expires'), '300');
  assert.equal(url.pathname, `/broker-wallet-media-staging/${KEY1}`);
});

test('MODEL: a PUT that omits the signed header fails the signature and stores nothing', async () => {
  const authorized = await authorizePending();
  assert.equal(devicePut(authorized, pdfBytes(), { sendHeaders: false }).status, 403);
  assert.equal(state.bucket.objects.has(KEY1), false);
});

test('REPLAY: the same signed PUT cannot replace a confirmed object, and the document stays usable', async () => {
  const authorized = await authorizePending();
  assert.equal(devicePut(authorized).status, 200);
  const confirmed = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirmed.status, 200);
  const before = state.bucket.objects.get(KEY1);

  const replay = devicePut(authorized, pdfBytes(64 + 5)); // other bytes, same URL, within its lifetime
  assert.equal(replay.status, 412);
  assert.equal(state.bucket.objects.get(KEY1), before, 'the stored object is untouched');
  assert.equal(state.bucket.objects.get(KEY1).etag, before.etag);

  const download = await get(`/toolkit-documents/download?documentId=${DOC_1}`);
  assert.equal(download.status, 200, 'no object_changed: the replay changed nothing');
  assert.equal((await get('/toolkit-documents')).body.documents.length, 1);
});

test('REPLAY: a replay before the confirm is refused too, and the confirm still verifies the first bytes', async () => {
  const authorized = await authorizePending();
  const good = pdfBytes();
  assert.equal(devicePut(authorized, good).status, 200);
  assert.equal(devicePut(authorized, pdfBytes(64 + 9)).status, 412);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
  assert.deepEqual(state.bucket.objects.get(KEY1).bytes, good);
});

test('LOST CONFIRM RESPONSE: the retry learns the document is already in the cloud and uploads nothing', async () => {
  const authorized = await authorizePending();
  assert.equal(devicePut(authorized).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200); // response lost
  const again = await post('/toolkit-documents/authorize', authBody());
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, { status: 'ready', documentId: DOC_1, alreadyConfirmed: true });
  assert.equal(again.body.presignedUrl, undefined, 'no new write URL is issued for a ready document');
  const confirmedAgain = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirmedAgain.body.alreadyConfirmed, true);
});

test('LOST PUT RESPONSE: the retried PUT is refused because the object exists, and the confirm accepts that same object', async () => {
  const first = await authorizePending();
  assert.equal(devicePut(first).status, 200); // arrived; the device never saw the answer
  const second = await authorizePending();
  assert.equal(second.body.status, 'pending');
  assert.equal(devicePut(second).status, 412, 'write-once: the device must go on to confirm');
  const confirmed = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.equal(state.supabase.row(DOC_1).status, 'ready');
});

test('EXISTING OBJECT, wrong size: the confirm rejects and removes it, and the next PUT succeeds', async () => {
  state.bucket.put(KEY1, pdfBytes(300)); // junk left by an earlier attempt
  const authorized = await authorizePending();
  assert.equal(devicePut(authorized).status, 412);
  const rejected = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(rejected.status, 422);
  assert.equal(rejected.body.code, 'upload_rejected');
  assert.equal(state.bucket.objects.has(KEY1), false, 'the conflicting object is gone');
  assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
  const retry = await authorizePending();
  assert.equal(devicePut(retry).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('EXISTING OBJECT, right size but not that file type: rejected and removed, retry works', async () => {
  const expected = pdfBytes();
  state.bucket.put(KEY1, jpegBytes(expected.length - 6), 'application/pdf'); // JPEG bytes under a PDF label
  assert.equal(state.bucket.objects.get(KEY1).bytes.length, expected.length);
  await authorizePending();
  const rejected = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(rejected.status, 422);
  assert.equal(rejected.body.code, 'media_type_mismatch');
  assert.equal(state.bucket.objects.has(KEY1), false);
  const retry = await authorizePending();
  assert.equal(devicePut(retry).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('EXISTING OBJECT that cannot be removed: the document never becomes ready, and recovers once removal works', async () => {
  state.bucket.put(KEY1, pdfBytes(300));
  state.bucket.failDeleteKey = KEY1;
  await authorizePending();
  for (let attempt = 0; attempt < 2; attempt += 1) {
    assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 422);
    assert.equal(state.supabase.row(DOC_1).status, 'pending_upload');
    assert.equal(devicePut(await authorizePending()).status, 412, 'still write-once while the junk object exists');
  }
  state.bucket.failDeleteKey = null;
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 422);
  assert.equal(state.bucket.objects.has(KEY1), false);
  assert.equal(devicePut(await authorizePending()).status, 200);
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('a rejected confirm does not remove an object that was replaced while it was examined', async () => {
  state.bucket.put(KEY1, new TextEncoder().encode('X'.repeat(pdfBytes().length)), 'application/pdf', '"junk"');
  await authorizePending();
  let reads = 0;
  state.bucket.onGet = () => {
    reads += 1;
    if (reads === 2) { // between the head read and the tail read a valid upload lands
      state.bucket.objects.set(KEY1, { bytes: pdfBytes(), contentType: 'application/pdf', etag: '"fresh"' });
    }
  };
  const rejected = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(rejected.status, 422, 'the examined (mixed) bytes are not a complete file');
  assert.equal(state.bucket.objects.get(KEY1)?.etag, '"fresh"', 'the newer object was not deleted');
  state.bucket.onGet = null;
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 200);
});

test('a signed URL is never returned for another account\'s or a claimed document, and a second device cannot replay it as its own', async () => {
  const mine = await authorizePending();
  const bobs = await post('/toolkit-documents/authorize', authBody(DOC_1), { user: BOB });
  assert.equal(bobs.status, 409);
  assert.equal(bobs.body.presignedUrl, undefined);
  assert.ok(mine.body.presignedUrl.includes(ALICE), 'the URL is bound to the account prefix');
  const other = await post('/toolkit-documents/authorize', authBody(DOC_2, pdfBytes()), { user: BOB });
  assert.equal(other.status, 200);
  assert.ok(other.body.presignedUrl.includes(BOB));
  assert.ok(!other.body.presignedUrl.includes(ALICE));
});
