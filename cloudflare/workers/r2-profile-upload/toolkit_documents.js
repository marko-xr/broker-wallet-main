/**
 * Toolkit cloud documents: the private, account-owned documents of Scanner,
 * Combine PDFs, Images to PDF and Document Signature. Every tool stores PDFs; the
 * Scanner may also store its JPEG / PNG scans, as the original bytes (see
 * toolkit_content.js).
 *
 *   POST /toolkit-documents/authorize  reserve (or resume) an upload
 *   POST /toolkit-documents/confirm    verify the stored bytes, make it ready
 *   GET  /toolkit-documents            the account's ready documents, paged
 *   POST /toolkit-documents/status     state of known ids (reconciliation)
 *   GET  /toolkit-documents/download   a fresh short-lived signed read
 *   POST /toolkit-documents/rename     rename, compare-and-swap on the version
 *   POST /toolkit-documents/remove     delete the document and its object
 *
 * SOURCE ONLY until the owner has approved the migration, the staging run and
 * the rollout. Every route answers the same 404 as an unknown path unless
 * TOOLKIT_DOCUMENTS_ENABLED is exactly "true", and the scheduled sweep does
 * nothing unless TOOLKIT_DOCUMENT_SWEEP_MODE is configured.
 *
 * Security model (the same as the other private media routes):
 *   - The account id is always the one the verified bearer token names, after the
 *     Single Active Device gate; it is never read from the body or the query.
 *   - The object key is never taken from the client. It is derived here from the
 *     verified account id and the document id, compared with the key stored on
 *     the row, and pinned in the database by a CHECK constraint:
 *       profiles/<account id>/toolkit-documents/<document id>.<pdf|jpg|png>
 *     with the extension taken from the verified content type, never from the client.
 *     That is inside the account prefix Delete Account already lists and
 *     deletes (account_deletion.js removeAccountMedia), so no change to account
 *     deletion is needed and no object can be orphaned by it.
 *   - Another account's document id is indistinguishable from an unknown one.
 *   - All state changes go through service-role-only database functions, which
 *     also enforce the anti-abuse limits atomically. Nothing here is a
 *     subscription quota.
 *   - No signed URL, object key or credential is stored or logged.
 *   - An object is written once. The signed PUT carries `If-None-Match: *` in its signed
 *     headers, so a PUT URL replayed after the object exists is refused by R2 (412) instead
 *     of replacing the bytes. Proven here only against a MODEL of R2's documented behavior;
 *     the real R2 behavior with a presigned URL must be proven on staging before enabling.
 *   - Abandoned-upload cleanup is claim-first (claim_abandoned_toolkit_document): the row
 *     leaves `pending_upload` under its row lock, so it can never become ready, and only
 *     then is the object removed. A ready document's object is never touched by it.
 *
 * Dependencies are injected (see handleToolkitDocumentRequest) so this module
 * imports only the pure sibling toolkit_content.js: the tests run it with no
 * package installed, like account_deletion.js.
 */

import {
  HEAD_BYTES,
  TAIL_BYTES,
  contentTypeAllowedForTool,
  contentTypeOfExtension,
  hasValidFraming,
  toolkitExtension,
} from './toolkit_content.js';

export const TOOLKIT_PATH = '/toolkit-documents';
export const TOOLKIT_KEY_SEGMENT = 'toolkit-documents';
export const TOOLKIT_DOCUMENT_TYPES = Object.freeze(['scanner', 'combine_pdfs', 'image_to_pdf', 'signature']);

const MIB = 1024 * 1024;
const GIB = 1024 * MIB;

/**
 * Anti-abuse and storage-safety limits. The defaults are the RECOMMENDED initial
 * operational profile and are NOT final: the owner approves the numbers. NOT subscription quotas: paid-plan
 * entitlement (RevenueCat) is separate future work. The defaults apply when a
 * variable is missing or invalid; a value above a ceiling is lowered to it, and
 * the database function refuses anything above the same ceilings.
 */
export const TOOLKIT_LIMIT_DEFAULTS = Object.freeze({
  documentBytes: 50 * MIB,
  imageBytes: 25 * MIB,
  accountBytes: 1 * GIB,
  accountDocuments: 1000,
  pendingUploads: 5,
  newPerHour: 120,
  attemptsPerUpload: 10,
});
export const TOOLKIT_LIMIT_CEILINGS = Object.freeze({
  documentBytes: 250 * MIB,
  imageBytes: 64 * MIB,
  accountBytes: 20 * GIB,
  accountDocuments: 5000,
  pendingUploads: 20,
  newPerHour: 1000,
  attemptsPerUpload: 100,
});
const LIMIT_VARIABLES = Object.freeze({
  documentBytes: 'TOOLKIT_DOC_MAX_BYTES',
  imageBytes: 'TOOLKIT_DOC_MAX_IMAGE_BYTES',
  accountBytes: 'TOOLKIT_DOC_MAX_ACCOUNT_BYTES',
  accountDocuments: 'TOOLKIT_DOC_MAX_ACCOUNT_DOCUMENTS',
  pendingUploads: 'TOOLKIT_DOC_MAX_PENDING',
  newPerHour: 'TOOLKIT_DOC_MAX_NEW_PER_HOUR',
  attemptsPerUpload: 'TOOLKIT_DOC_MAX_ATTEMPTS',
});

const LIST_DEFAULT_LIMIT = 50;
const LIST_MAX_LIMIT = 100;
const STATUS_MAX_IDS = 50;
const MAX_TITLE_LENGTH = 200;
const MAX_PAGE_COUNT = 100000;
// The signed PUT outlives a delete by at most its own lifetime, so the object
// is removed again (and the tombstone written) once it cannot be live.
const DELETE_SETTLE_MARGIN_SECONDS = 60;

const SWEEP_MODES = new Set(['off', 'dry_run', 'on']);
const SWEEP_BATCH = 10;
const SWEEP_DRY_RUN_LIMIT = 100;
export const ABANDONED_UPLOAD_AGE_MS = 24 * 60 * 60 * 1000;
// Claim-first cleanup. A claim is a lease: another cleanup takes the row over only after
// it expires, and this one removes the object only well inside it (a cleanup that stalled
// past the deadline leaves the row claimed and the next one finishes it).
export const DISCARD_LEASE_SECONDS = 15 * 60;
export const DISCARD_DELETE_DEADLINE_MS = 60 * 1000;
/**
 * Headers every Toolkit signed PUT is signed with. The device must send them exactly
 * (authorize returns them as `uploadHeaders`); a PUT without them fails the signature.
 */
export const TOOLKIT_PUT_SIGNED_HEADERS = Object.freeze({ 'if-none-match': '*' });
export const TOOLKIT_UPLOAD_HEADERS = Object.freeze({ 'If-None-Match': '*' });
export const TOMBSTONE_RETENTION_MS = 180 * 24 * 60 * 60 * 1000;

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/;
const SHA256_HEX = /^[0-9a-f]{64}$/;
// Control characters and bidi override / isolate controls (matches the table).
const UNSAFE_TITLE = /[\u0000-\u001f\u007f\u202A-\u202E\u2066-\u2069]/u;

export function toolkitDocumentsEnabled(env) {
  return env?.TOOLKIT_DOCUMENTS_ENABLED === 'true';
}

export function toolkitLimits(env) {
  const limits = {};
  for (const [name, variable] of Object.entries(LIMIT_VARIABLES)) {
    const raw = env?.[variable];
    const parsed = typeof raw === 'string' && /^[0-9]{1,12}$/.test(raw.trim()) ? Number(raw.trim()) : NaN;
    const value = Number.isSafeInteger(parsed) && parsed >= 1 ? parsed : TOOLKIT_LIMIT_DEFAULTS[name];
    limits[name] = Math.min(value, TOOLKIT_LIMIT_CEILINGS[name]);
  }
  return Object.freeze(limits);
}

/** The account's key prefix for Toolkit documents. */
export function toolkitKeyPrefix(userId) {
  return `profiles/${userId}/${TOOLKIT_KEY_SEGMENT}/`;
}

/**
 * The one object key a document can have, or null for a content type that is not
 * accepted. The extension comes from the content type only.
 */
export function toolkitObjectKey(userId, documentId, contentType) {
  const extension = toolkitExtension(contentType);
  return extension === null ? null : `${toolkitKeyPrefix(userId)}${documentId}.${extension}`;
}

/**
 * Whether [key] is exactly the key of one of [userId]'s documents: its id and
 * content type, or null. Used to refuse anything that is not.
 */
export function toolkitKeyDocumentId(userId, key) {
  if (typeof key !== 'string') return null;
  const prefix = toolkitKeyPrefix(userId);
  if (!key.startsWith(prefix)) return null;
  const name = key.slice(prefix.length);
  const dot = name.lastIndexOf('.');
  if (dot < 1) return null;
  const id = name.slice(0, dot);
  const contentType = contentTypeOfExtension(name.slice(dot + 1));
  if (contentType === null) return null;
  // Canonical form only: the database writes lower-case UUIDs.
  return UUID_PATTERN.test(id) && id === id.toLowerCase() &&
    key === toolkitObjectKey(userId, id, contentType) ? { documentId: id, contentType } : null;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

function routeFor(method, path) {
  if (path === TOOLKIT_PATH) return method === 'GET' ? 'list' : null;
  if (!path.startsWith(`${TOOLKIT_PATH}/`)) return null;
  const tail = path.slice(TOOLKIT_PATH.length + 1);
  if (method === 'GET' && tail === 'download') return 'download';
  if (method === 'POST' && ['authorize', 'confirm', 'status', 'rename', 'remove'].includes(tail)) return tail;
  return null;
}

/**
 * Answers a Toolkit document request, or returns null when the request is not
 * one (the caller then answers its usual 404).
 *
 * [deps]: { respond, WorkerError, verifyUser, supabase, signPut, signGet,
 *   requireUuid, requireConfiguredBucket, putTtlSeconds, getTtlSeconds }
 *   respond(body, status, env, headers)   JSON response with CORS headers
 *   verifyUser(request, env)              verified account id (session gated)
 *   supabase(env, method, path, body, options)  service-role PostgREST call
 *   signPut({ env, userId, objectKey, contentType })  signed PUT URL
 *   signGet({ env, objectKey })           signed GET URL
 */
export async function handleToolkitDocumentRequest(request, env, deps) {
  const route = routeFor(request.method, new URL(request.url).pathname);
  if (!route) return null;
  // Disabled is indistinguishable from a path that does not exist.
  if (!toolkitDocumentsEnabled(env)) return deps.respond({ error: 'Not found' }, 404, env);

  deps.requireConfiguredBucket(env);
  const userId = await deps.verifyUser(request, env);
  const context = { env, deps, userId, limits: toolkitLimits(env) };
  switch (route) {
    case 'authorize': return authorize(request, context);
    case 'confirm': return confirm(request, context);
    case 'list': return list(request, context);
    case 'status': return status(request, context);
    case 'download': return download(request, context);
    case 'rename': return rename(request, context);
    default: return remove(request, context);
  }
}

// ---------------------------------------------------------------------------
// authorize
// ---------------------------------------------------------------------------

// An abandoned-upload cleanup owns the row for a moment; the device retries.
const CLEANUP_IN_PROGRESS = Object.freeze({
  status: 503, code: 'document_cleanup_in_progress', message: 'Upload cleanup is in progress', retryAfter: 60,
});

const AUTHORIZE_REFUSALS = Object.freeze({
  document_deleted: { status: 410, code: 'document_deleted', message: 'Document was deleted' },
  id_unavailable: { status: 409, code: 'document_id_unavailable', message: 'Document id is not available' },
  idempotency_mismatch: { status: 409, code: 'idempotency_mismatch', message: 'Document id was used for another file' },
  too_large: { status: 413, code: 'document_too_large', message: 'Document is too large' },
  stale_document: { status: 409, code: 'stale_document', message: 'Document predates this account\'s deletion history' },
  storage_limit: { status: 409, code: 'storage_limit_reached', message: 'Cloud storage limit reached' },
  document_limit: { status: 409, code: 'document_limit_reached', message: 'Cloud document limit reached' },
  too_many_pending: { status: 429, code: 'too_many_pending_uploads', message: 'Too many uploads are waiting', retryAfter: 120 },
  rate_limited: { status: 429, code: 'rate_limited', message: 'Too many requests', retryAfter: 300 },
  cleanup_in_progress: CLEANUP_IN_PROGRESS,
});

async function authorize(request, { env, deps, userId, limits }) {
  const body = await readBody(request, deps);
  const documentId = deps.requireUuid(body.documentId, 'documentId');
  const documentType = requireType(body.documentType, deps);
  const title = requireTitle(body.title, deps);
  // The format is what the client DECLARES; the Worker proves it at confirm time
  // and builds the key from it. Anything but an exact accepted MIME type, or a
  // format this tool may not store, is refused: nothing is converted or guessed.
  const contentType = body.contentType;
  if (!contentTypeAllowedForTool(documentType, contentType)) {
    throw new deps.WorkerError('Unsupported content type for this document type', 400, 'unsupported_media_type');
  }
  const size = body.contentLength;
  if (!Number.isInteger(size) || size < 1) {
    throw new deps.WorkerError('contentLength is required', 400, 'invalid_request');
  }
  const cap = contentType === 'application/pdf' ? limits.documentBytes : limits.imageBytes;
  if (size > cap) {
    throw new deps.WorkerError('Document is too large', 413, 'document_too_large');
  }
  let pageCount = optionalInteger(body.pageCount, 1, MAX_PAGE_COUNT, 'pageCount', deps);
  if (contentType !== 'application/pdf' && pageCount !== null && pageCount !== 1) {
    throw new deps.WorkerError('An image is one page', 400, 'invalid_request');
  }
  // The device's SHA-256 and creation time are required. The digest is a claim
  // until the Worker verifies it (see sha256_verified); the creation time is what
  // the tombstone floor compares.
  const sha256 = requireSha256(body.contentSha256, deps);
  const sourceCreatedAt = requireTimestamp(body.sourceCreatedAt, deps);
  const acknowledgeStale = optionalBoolean(body.acknowledgeStale, 'acknowledgeStale', deps);

  const result = await rpc(deps, env, 'authorize_toolkit_document_upload', {
    p_user_id: userId,
    p_document_id: documentId,
    p_document_type: documentType,
    p_content_type: contentType,
    p_title: title,
    p_size_bytes: size,
    p_page_count: pageCount,
    p_content_sha256: sha256,
    p_source_created_at: sourceCreatedAt,
    p_bucket: env.R2_BUCKET_NAME,
    p_max_document_bytes: limits.documentBytes,
    p_max_image_bytes: limits.imageBytes,
    p_max_account_bytes: limits.accountBytes,
    p_max_account_documents: limits.accountDocuments,
    p_max_pending: limits.pendingUploads,
    p_max_new_per_hour: limits.newPerHour,
    p_max_attempts: limits.attemptsPerUpload,
    p_acknowledge_stale: acknowledgeStale,
  });

  const refusal = AUTHORIZE_REFUSALS[result?.outcome];
  if (refusal) return refuse(deps, env, refusal);
  if (result?.outcome === 'already_ready') {
    return noStore(deps, env, { status: 'ready', documentId, alreadyConfirmed: true });
  }
  if (result?.outcome !== 'created' && result?.outcome !== 'resumed') {
    throw new deps.WorkerError('Upload could not be authorized', 502);
  }
  const presignedUrl = await deps.signPut({
    env,
    userId,
    objectKey: toolkitObjectKey(userId, documentId, contentType),
    contentType,
  });
  return noStore(deps, env, {
    status: 'pending',
    documentId,
    presignedUrl,
    // Part of the signature: the PUT must send these headers exactly.
    uploadHeaders: TOOLKIT_UPLOAD_HEADERS,
    expiresInSeconds: deps.putTtlSeconds,
  });
}

// ---------------------------------------------------------------------------
// confirm
// ---------------------------------------------------------------------------

async function confirm(request, { env, deps, userId }) {
  const body = await readBody(request, deps);
  const documentId = deps.requireUuid(body.documentId, 'documentId');
  const doc = await loadOwnedDocument(deps, env, userId, documentId);

  if (doc.status === 'ready') {
    return noStore(deps, env, {
      documentId, version: doc.version, alreadyConfirmed: true, sha256Verified: doc.sha256_verified === true,
    });
  }
  if (doc.status === 'pending_delete' || doc.status === 'deleted') {
    throw new deps.WorkerError('Document was deleted', 410, 'document_deleted');
  }
  // A claimed upload can never become ready; its object is being removed. Nothing is
  // read or deleted here.
  if (doc.status === 'pending_discard') {
    return refuse(deps, env, CLEANUP_IN_PROGRESS);
  }

  // The minimum server-side checks before a document may be "ready". Each one
  // that fails removes the stored object and leaves the document pending, so the
  // device can simply upload again:
  //  1. the object exists                                  (else upload_incomplete)
  //  2. its byte length equals the authorized length
  //  3. its stored content type equals the declared one, exactly
  //  4. its leading bytes identify the declared format
  //  5. its leading and trailing bytes are that format's framing (not truncated)
  //  6. optionally (TOOLKIT_DOC_VERIFY_SHA256) its SHA-256 equals the device's
  const object = await env.MEDIA_BUCKET.head(doc.object_key);
  if (!object) throw new deps.WorkerError('Upload has not arrived', 409, 'upload_incomplete');
  if (object.size !== Number(doc.size_bytes)) {
    await deleteIfUnchanged(env, doc.object_key, object.etag);
    throw new deps.WorkerError('Uploaded size does not match the authorized size', 422, 'upload_rejected');
  }
  if (object.httpMetadata?.contentType !== doc.content_type) {
    await deleteIfUnchanged(env, doc.object_key, object.etag);
    throw new deps.WorkerError('Uploaded type does not match authorized metadata', 422, 'media_type_mismatch');
  }
  if (!(await hasExpectedFraming(env, doc.object_key, doc.content_type, object.size))) {
    await deleteIfUnchanged(env, doc.object_key, object.etag);
    throw new deps.WorkerError('Uploaded file is not a complete file of the declared type', 422, 'media_type_mismatch');
  }

  let sha256Verified = false;
  if (env.TOOLKIT_DOC_VERIFY_SHA256 === 'true') {
    if (typeof deps.sha256OfObject !== 'function') {
      throw new deps.WorkerError('Digest verification is not available', 500);
    }
    const actual = await deps.sha256OfObject(env, doc.object_key, object.size);
    if (actual === null) throw new deps.WorkerError('Upload has not arrived', 409, 'upload_incomplete');
    if (actual !== doc.content_sha256) {
      await deleteIfUnchanged(env, doc.object_key, object.etag);
      throw new deps.WorkerError('Uploaded bytes do not match the declared digest', 422, 'integrity_mismatch');
    }
    sha256Verified = true;
  }

  const result = await rpc(deps, env, 'confirm_toolkit_document_upload', {
    p_user_id: userId,
    p_document_id: documentId,
    p_bucket: env.R2_BUCKET_NAME,
    p_observed_size: object.size,
    p_observed_content_type: object.httpMetadata.contentType,
    p_observed_etag: typeof object.etag === 'string' ? object.etag : null,
    p_sha256_verified: sha256Verified,
  });
  switch (result?.outcome) {
    case 'confirmed':
      return noStore(deps, env, { documentId, version: result.version, sha256Verified });
    case 'already_confirmed':
      return noStore(deps, env, { documentId, version: result.version, alreadyConfirmed: true });
    case 'document_deleted':
      throw new deps.WorkerError('Document was deleted', 410, 'document_deleted');
    case 'cleanup_in_progress':
      return refuse(deps, env, CLEANUP_IN_PROGRESS);
    case 'not_found':
      throw new deps.WorkerError('Document not found', 404, 'document_not_found');
    case 'size_mismatch':
      throw new deps.WorkerError('Uploaded size does not match the authorized size', 422, 'upload_rejected');
    case 'type_mismatch':
      throw new deps.WorkerError('Uploaded type does not match authorized metadata', 422, 'media_type_mismatch');
    default:
      throw new deps.WorkerError('Document could not be confirmed', 502);
  }
}

/**
 * Reads the first and last bytes of the stored object and checks the declared
 * format's framing (see toolkit_content.js). Proves the container, not the pixels
 * or pages, and not a digest.
 */
async function hasExpectedFraming(env, key, contentType, size) {
  const head = await env.MEDIA_BUCKET.get(key, { range: { offset: 0, length: Math.min(size, HEAD_BYTES) } });
  if (!head) return false;
  const tailLength = Math.min(size, TAIL_BYTES);
  const tail = await env.MEDIA_BUCKET.get(key, { range: { offset: size - tailLength, length: tailLength } });
  if (!tail) return false;
  return hasValidFraming(
    contentType,
    new Uint8Array(await head.arrayBuffer()),
    new Uint8Array(await tail.arrayBuffer()),
    size,
  );
}

// ---------------------------------------------------------------------------
// list / status / download
// ---------------------------------------------------------------------------

async function list(request, { env, deps, userId, limits }) {
  const params = new URL(request.url).searchParams;
  const limit = listLimit(params.get('limit'), deps);
  const documentType = params.get('documentType');
  if (documentType !== null) requireType(documentType, deps);
  const cursor = decodeCursor(params.get('cursor'), deps);

  const rows = await rpcRows(deps, env, 'list_toolkit_documents', {
    p_user_id: userId,
    p_bucket: env.R2_BUCKET_NAME,
    p_limit: limit + 1,
    p_before_created_at: cursor?.createdAt ?? null,
    p_before_id: cursor?.id ?? null,
    p_document_type: documentType,
  });
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  const body = {
    documents: page.map(documentView),
    nextCursor: rows.length > limit && last ? encodeCursor(last.created_at, last.id) : null,
  };
  if (cursor === null) {
    const usage = (await rpcRows(deps, env, 'toolkit_document_usage', { p_user_id: userId }))[0];
    body.usage = {
      readyCount: Number(usage?.ready_count ?? 0),
      readyBytes: Number(usage?.ready_bytes ?? 0),
      pendingCount: Number(usage?.pending_count ?? 0),
      pendingBytes: Number(usage?.pending_bytes ?? 0),
    };
    body.limits = {
      documentBytes: limits.documentBytes,
      imageBytes: limits.imageBytes,
      accountBytes: limits.accountBytes,
      accountDocuments: limits.accountDocuments,
    };
  }
  return noStore(deps, env, body);
}

function documentView(row) {
  return {
    documentId: row.id,
    documentType: row.document_type,
    contentType: row.content_type,
    title: row.title,
    sizeBytes: Number(row.size_bytes),
    pageCount: row.page_count ?? null,
    contentSha256: row.content_sha256,
    sha256Verified: row.sha256_verified === true,
    sourceCreatedAt: row.source_created_at,
    createdAt: row.created_at,
    version: Number(row.version),
  };
}

async function status(request, { env, deps, userId }) {
  const body = await readBody(request, deps);
  const ids = body.documentIds;
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > STATUS_MAX_IDS) {
    throw new deps.WorkerError(`documentIds must hold 1 to ${STATUS_MAX_IDS} ids`, 400, 'invalid_request');
  }
  const unique = [...new Set(ids.map((id) => deps.requireUuid(id, 'documentIds')))];
  const rows = await rpcRows(deps, env, 'toolkit_document_statuses', {
    p_user_id: userId,
    p_bucket: env.R2_BUCKET_NAME,
    p_ids: unique,
  });
  const known = new Map(rows.map((row) => [row.id, row]));
  // `deleting` and `deleted` both mean "do not bring this back".
  const stateOf = {
    pending_upload: 'pending', pending_discard: 'pending', ready: 'ready', pending_delete: 'deleted', deleted: 'deleted',
  };
  return noStore(deps, env, {
    documents: unique.filter((id) => known.has(id)).map((id) => ({
      documentId: id,
      state: stateOf[known.get(id).status] ?? 'unknown',
      version: Number(known.get(id).version),
    })),
    // No row for these ids in this account: never synced, or a tombstone old
    // enough to have been purged. Not proof the document never existed.
    unknownIds: unique.filter((id) => !known.has(id)),
  });
}

async function download(request, { env, deps, userId }) {
  const documentId = deps.requireUuid(new URL(request.url).searchParams.get('documentId'), 'documentId');
  const doc = await loadOwnedDocument(deps, env, userId, documentId);
  if (doc.status === 'pending_delete' || doc.status === 'deleted') {
    throw new deps.WorkerError('Document was deleted', 410, 'document_deleted');
  }
  if (doc.status !== 'ready') {
    throw new deps.WorkerError('Document is not in the cloud yet', 409, 'document_not_ready');
  }
  const object = await env.MEDIA_BUCKET.head(doc.object_key);
  if (!object) throw new deps.WorkerError('Document file is missing from storage', 404, 'object_missing');
  // The signed PUT is write-once (If-None-Match: *), so a replay should be refused by R2.
  // Whether R2 honors that on a presigned URL is a staging proof, so the stored file must
  // still be the very object that was verified (same size and same etag).
  if (object.size !== Number(doc.size_bytes) ||
      (doc.observed_etag && object.etag !== doc.observed_etag)) {
    throw new deps.WorkerError('Document file does not match its record', 409, 'object_changed');
  }
  const url = await deps.signGet({ env, objectKey: doc.object_key });
  return noStore(deps, env, {
    documentId,
    documentType: doc.document_type,
    contentType: doc.content_type,
    title: doc.title,
    sizeBytes: Number(doc.size_bytes),
    pageCount: doc.page_count ?? null,
    contentSha256: doc.content_sha256,
    sha256Verified: doc.sha256_verified === true,
    version: Number(doc.version),
    url,
    expiresInSeconds: deps.getTtlSeconds,
  });
}

// ---------------------------------------------------------------------------
// rename / remove
// ---------------------------------------------------------------------------

async function rename(request, { env, deps, userId }) {
  const body = await readBody(request, deps);
  const documentId = deps.requireUuid(body.documentId, 'documentId');
  const title = requireTitle(body.title, deps);
  const expectedVersion = body.expectedVersion;
  if (!Number.isInteger(expectedVersion) || expectedVersion < 1) {
    throw new deps.WorkerError('expectedVersion is required', 400, 'invalid_request');
  }
  const result = await rpc(deps, env, 'rename_toolkit_document', {
    p_user_id: userId,
    p_document_id: documentId,
    p_title: title,
    p_expected_version: expectedVersion,
  });
  switch (result?.outcome) {
    case 'renamed':
      return noStore(deps, env, { documentId, title: result.title, version: Number(result.version) });
    case 'stale_version':
      // The caller reconciles: the remote title and version are the truth.
      return deps.respond({
        error: 'Document changed',
        code: 'stale_version',
        currentTitle: result.title,
        currentVersion: Number(result.version),
      }, 409, env, { 'Cache-Control': 'no-store' });
    case 'document_deleted':
      throw new deps.WorkerError('Document was deleted', 410, 'document_deleted');
    case 'cleanup_in_progress':
      return refuse(deps, env, CLEANUP_IN_PROGRESS);
    case 'not_found':
      throw new deps.WorkerError('Document not found', 404, 'document_not_found');
    default:
      throw new deps.WorkerError('Document could not be renamed', 502);
  }
}

async function remove(request, { env, deps, userId }) {
  const body = await readBody(request, deps);
  const documentId = deps.requireUuid(body.documentId, 'documentId');
  const begun = await rpc(deps, env, 'begin_toolkit_document_delete', {
    p_user_id: userId,
    p_document_id: documentId,
    p_bucket: env.R2_BUCKET_NAME,
    p_expected_status: null,
  });
  // Another account's id and an unknown id answer alike, so removal is
  // idempotent and reveals nothing.
  if (begun?.outcome === 'not_found' || begun?.outcome === 'already_deleted') {
    return noStore(deps, env, { removed: true, documentId, alreadyRemoved: true });
  }
  if (begun?.outcome !== 'marked' && begun?.outcome !== 'already_pending') {
    throw new deps.WorkerError('Document could not be removed', 502);
  }
  const objectKey = begun.object_key;
  const parsedKey = toolkitKeyDocumentId(userId, objectKey);
  if (!parsedKey || parsedKey.documentId !== documentId) {
    // Never delete a key the row should not hold; the row stays pending_delete
    // (hidden from every read) for the owner to inspect.
    throw new deps.WorkerError('Document does not match its storage record', 409, 'document_mismatch');
  }
  const cleanupPending = !(await finishRemoval(deps, env, userId, documentId, objectKey));
  return noStore(deps, env, { removed: true, documentId, ...(cleanupPending ? { cleanupPending: true } : {}) });
}

/** Deletes the object, then writes the tombstone. False when it must be retried. */
async function finishRemoval(deps, env, userId, documentId, objectKey) {
  if (!(await bestEffortDelete(env, objectKey))) return false;
  try {
    const finalized = await rpc(deps, env, 'finalize_toolkit_document_delete', {
      p_user_id: userId,
      p_document_id: documentId,
      p_bucket: env.R2_BUCKET_NAME,
      p_min_upload_age_seconds: deps.putTtlSeconds + DELETE_SETTLE_MARGIN_SECONDS,
    });
    return finalized?.outcome === 'deleted' || finalized?.outcome === 'already_deleted';
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Scheduled cleanup
// ---------------------------------------------------------------------------

/**
 * Cleans up Toolkit documents. Count-only report; never throws, never logs ids,
 * keys or URLs. Mode (TOOLKIT_DOCUMENT_SWEEP_MODE): `off` (also any missing or
 * unknown value) does nothing; `dry_run` only counts; `on` applies.
 *
 *   abandonedUploads  authorized, never confirmed, idle for 24 h (or claimed by an
 *                     earlier cleanup that never finished): CLAIM the row first (it can
 *                     then never become ready), remove the object, then discard the row
 *                     for that exact claim (no tombstone: nobody deleted it)
 *   pendingDeletes    a delete that stopped half way: finish it
 *   oldTombstones     tombstones older than 180 days are purged
 */
export async function runToolkitDocumentSweeps(env, deps, { now = () => Date.now() } = {}) {
  const requested = env?.TOOLKIT_DOCUMENT_SWEEP_MODE;
  const mode = SWEEP_MODES.has(requested) ? requested : 'off';
  const report = { mode, abandonedUploads: 0, pendingDeletes: 0, oldTombstones: 0, failures: 0 };
  if (mode === 'off' || !env?.MEDIA_BUCKET || !env?.R2_BUCKET_NAME) return report;
  const apply = mode === 'on';
  const limit = apply ? SWEEP_BATCH : SWEEP_DRY_RUN_LIMIT;
  const at = now();
  const iso = (ms) => new Date(ms).toISOString();
  const candidates = async (kind, cutoffMs) => rpcRows(deps, env, 'list_toolkit_document_cleanup', {
    p_kind: kind, p_bucket: env.R2_BUCKET_NAME, p_cutoff: iso(cutoffMs), p_limit: limit,
  });
  const guarded = async (step) => {
    try { await step(); } catch (_) { report.failures += 1; console.error('[toolkit-documents-sweep] step failed'); }
  };
  // Only a row whose key is exactly its own account's is ever acted on.
  const sound = (row) => row.bucket === env.R2_BUCKET_NAME &&
    toolkitKeyDocumentId(row.owner_id, row.object_key)?.documentId === row.id;

  await guarded(async () => {
    const cutoff = at - ABANDONED_UPLOAD_AGE_MS;
    const rows = [
      ...(await candidates('abandoned_pending', cutoff)),
      // A cleanup that claimed a row and never finished it (its object removal failed or the
      // Worker stopped): claimed again once the lease has passed.
      ...(await candidates('stuck_discard', at - DISCARD_LEASE_SECONDS * 1000)),
    ];
    for (const row of rows) {
      if (!sound(row)) continue;
      if (!apply) { report.abandonedUploads += 1; continue; }
      const outcome = await discardAbandonedUpload(deps, env, row, cutoff, now);
      if (outcome === 'discarded') report.abandonedUploads += 1;
      else if (outcome === 'failed') report.failures += 1;
    }
  });
  await guarded(async () => {
    const settle = (deps.putTtlSeconds + 2 * DELETE_SETTLE_MARGIN_SECONDS) * 1000;
    for (const row of await candidates('pending_delete', at - settle)) {
      if (!sound(row)) continue;
      if (!apply) { report.pendingDeletes += 1; continue; }
      if (await finishRemoval(deps, env, row.owner_id, row.id, row.object_key)) report.pendingDeletes += 1;
      else report.failures += 1;
    }
  });
  await guarded(async () => {
    const cutoff = at - TOMBSTONE_RETENTION_MS;
    for (const row of await candidates('old_tombstones', cutoff)) {
      if (!apply) { report.oldTombstones += 1; continue; }
      const purged = await rpc(deps, env, 'purge_toolkit_document_tombstone', {
        p_user_id: row.owner_id, p_document_id: row.id, p_cutoff: iso(cutoff),
      });
      if (purged === true || purged?.purge_toolkit_document_tombstone === true) report.oldTombstones += 1;
    }
  });
  console.log(`[toolkit-documents-sweep] mode=${mode} abandoned=${report.abandonedUploads} ` +
    `pendingDeletes=${report.pendingDeletes} tombstones=${report.oldTombstones} failures=${report.failures}`);
  return report;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function readBody(request, deps) {
  try {
    const body = await request.json();
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('invalid body');
    return body;
  } catch (_) {
    throw new deps.WorkerError('Request body must be a JSON object', 400);
  }
}

function requireType(value, deps) {
  if (typeof value !== 'string' || !TOOLKIT_DOCUMENT_TYPES.includes(value)) {
    throw new deps.WorkerError('Unsupported document type', 400, 'unsupported_document_type');
  }
  return value;
}

/** A trimmed, printable title of 1 to 200 characters. */
function requireTitle(value, deps) {
  const valid = typeof value === 'string' && value.length > 0 && value === value.trim() &&
    [...value].length <= MAX_TITLE_LENGTH && !UNSAFE_TITLE.test(value);
  if (!valid) throw new deps.WorkerError('Invalid document title', 400, 'invalid_title');
  return value;
}

function optionalInteger(value, min, max, name, deps) {
  if (value === undefined || value === null) return null;
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new deps.WorkerError(`${name} is invalid`, 400, 'invalid_request');
  }
  return value;
}

function requireSha256(value, deps) {
  if (typeof value !== 'string' || !SHA256_HEX.test(value)) {
    throw new deps.WorkerError('contentSha256 must be 64 lower-case hex characters', 400, 'invalid_request');
  }
  return value;
}

function requireTimestamp(value, deps) {
  if (typeof value !== 'string' || !ISO_TIMESTAMP.test(value) || Number.isNaN(Date.parse(value))) {
    throw new deps.WorkerError('sourceCreatedAt must be an ISO-8601 timestamp', 400, 'invalid_request');
  }
  return value;
}

function optionalBoolean(value, name, deps) {
  if (value === undefined || value === null) return false;
  if (typeof value !== 'boolean') {
    throw new deps.WorkerError(`${name} must be a boolean`, 400, 'invalid_request');
  }
  return value;
}

function listLimit(raw, deps) {
  if (raw === null) return LIST_DEFAULT_LIMIT;
  if (!/^[0-9]{1,3}$/.test(raw) || Number(raw) < 1 || Number(raw) > LIST_MAX_LIMIT) {
    throw new deps.WorkerError(`limit must be 1 to ${LIST_MAX_LIMIT}`, 400, 'invalid_request');
  }
  return Number(raw);
}

// The cursor is opaque to the client: base64url of `<created_at>|<id>`, kept as
// the database wrote it (microsecond precision matters for keyset paging).
function encodeCursor(createdAt, id) {
  return btoa(`${createdAt}|${id}`).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function decodeCursor(raw, deps) {
  if (raw === null || raw === '') return null;
  try {
    const padded = raw.replaceAll('-', '+').replaceAll('_', '/');
    const [createdAt, id, extra] = atob(padded).split('|');
    if (extra === undefined && ISO_TIMESTAMP.test(createdAt) && UUID_PATTERN.test(id)) {
      return { createdAt, id: id.toLowerCase() };
    }
  } catch (_) { /* falls through */ }
  throw new deps.WorkerError('cursor is invalid', 400, 'invalid_request');
}

function refuse(deps, env, refusal) {
  return deps.respond(
    { error: refusal.message, code: refusal.code },
    refusal.status,
    env,
    { 'Cache-Control': 'no-store', ...(refusal.retryAfter ? { 'Retry-After': String(refusal.retryAfter) } : {}) },
  );
}

function noStore(deps, env, body) {
  return deps.respond(body, 200, env, { 'Cache-Control': 'no-store' });
}

/**
 * The account's own document, or a 404. The row's bucket, key and type must be
 * exactly what this Worker would have created for this account and id.
 */
async function loadOwnedDocument(deps, env, userId, documentId) {
  const rows = await rpcRows(deps, env, 'get_toolkit_document', { p_user_id: userId, p_document_id: documentId });
  const doc = rows[0];
  if (!doc) throw new deps.WorkerError('Document not found', 404, 'document_not_found');
  if (doc.owner_id !== userId || doc.id !== documentId ||
      doc.bucket !== env.R2_BUCKET_NAME ||
      toolkitObjectKey(userId, documentId, doc.content_type) === null ||
      doc.object_key !== toolkitObjectKey(userId, documentId, doc.content_type)) {
    // Not this Worker's object (another bucket, or a row that does not hold the
    // exact key). Nothing is read, signed or deleted for it.
    throw new deps.WorkerError('Document does not match its storage record', 409, 'document_mismatch');
  }
  return doc;
}

async function rpc(deps, env, name, args) {
  return (await rpcRows(deps, env, name, args))[0] ?? null;
}

async function rpcRows(deps, env, name, args) {
  const response = await deps.supabase(env, 'POST', `/rest/v1/rpc/${name}`, args, { preferRepresentation: true });
  if (!response.ok) throw new deps.WorkerError('Failed to reach document metadata', 502);
  const body = await response.json();
  if (Array.isArray(body)) return body;
  // A scalar function (purge) answers a bare value.
  return body === null || body === undefined ? [] : [body];
}

/**
 * Claim-first removal of one abandoned upload. Returns 'discarded', 'skipped' (nothing to do:
 * the row was re-authorized, confirmed, deleted or is held by another cleanup, and NOTHING was
 * deleted) or 'failed' (the row stays claimed and is retried after the lease).
 *
 * Why this is safe without trusting a status read: the claim is the row's own compare-and-set
 * under its row lock. A row that was already confirmed (or re-authorized) cannot be claimed,
 * and a claimed row can neither be confirmed nor authorized again, so the object removed below
 * belongs to a document that cannot become ready. The only remaining assumption is time: the
 * object is removed within DISCARD_DELETE_DEADLINE_MS of the claim, far inside the lease.
 */
async function discardAbandonedUpload(deps, env, row, cutoffMs, now) {
  const startedAt = now();
  let claim;
  try {
    claim = await rpc(deps, env, 'claim_abandoned_toolkit_document', {
      p_user_id: row.owner_id, p_document_id: row.id, p_bucket: env.R2_BUCKET_NAME,
      p_cutoff: new Date(cutoffMs).toISOString(), p_lease_seconds: DISCARD_LEASE_SECONDS,
    });
  } catch (_) {
    return 'failed';
  }
  if (claim?.outcome !== 'claimed') return 'skipped';
  // Never delete a key the row should not hold; the row stays claimed for the owner to inspect.
  const parsed = toolkitKeyDocumentId(row.owner_id, claim.object_key);
  if (!parsed || parsed.documentId !== row.id || typeof claim.claimed_at !== 'string') return 'failed';
  // A stalled cleanup must not delete after its lease may have been taken over.
  if (now() - startedAt > DISCARD_DELETE_DEADLINE_MS) return 'failed';
  if (!(await bestEffortDelete(env, claim.object_key))) return 'failed';
  try {
    const result = await rpc(deps, env, 'discard_abandoned_toolkit_document', {
      p_user_id: row.owner_id, p_document_id: row.id, p_bucket: env.R2_BUCKET_NAME,
      // The claim identity exactly as the database returned it.
      p_claimed_at: claim.claimed_at,
    });
    return result?.outcome === 'discarded' ? 'discarded' : 'skipped';
  } catch (_) {
    return 'failed';
  }
}

/**
 * Removes an object a confirm just rejected, but only if it is still the object that was
 * examined (same ETag). Narrows the window in which a slow rejection could remove a newer,
 * valid upload; R2 has no conditional delete, so this narrows it, it does not close it.
 */
async function deleteIfUnchanged(env, objectKey, examinedEtag) {
  try {
    const current = await env.MEDIA_BUCKET.head(objectKey);
    if (!current) return true;
    if (typeof examinedEtag === 'string' && current.etag !== examinedEtag) return false;
  } catch (_) {
    return false;
  }
  return bestEffortDelete(env, objectKey);
}

async function bestEffortDelete(env, objectKey) {
  try {
    await env.MEDIA_BUCKET.delete(objectKey);
    return true;
  } catch (_) {
    console.error('[toolkit-documents] object deletion failed');
    return false;
  }
}
