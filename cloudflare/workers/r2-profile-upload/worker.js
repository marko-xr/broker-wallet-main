import { AwsClient } from 'aws4fetch';
import {
  ACCOUNT_DELETE_PATH,
  AccountDeletionError,
  MAX_SIGNING_DELAY_MS,
  SIGNED_PUT_TTL_SECONDS,
  assertPresignedWithin,
  assertUploadsAllowed,
  handleAccountDeletion,
  runDeletionFinalizer,
} from './account_deletion.js';
import { stagingRequestAllowed } from './staging_gate.js';

/**
 * Private profile-image and offer-media lifecycle worker.
 *
 * Public endpoints:
 *   POST /authorize              (profile image)
 *   POST /confirm                (profile image)
 *   GET  /profile-image-url      (profile image)
 *   POST /offer-media/authorize
 *   POST /offer-media/confirm
 *   GET  /offer-media
 *   POST /offer-media/remove
 *   POST /owner-media/authorize
 *   POST /owner-media/confirm
 *   GET  /owner-media
 *   POST /owner-media/remove
 *   POST /account/delete   (see account_deletion.js)
 *
 * Scheduled:
 *   account deletion finalizer (see account_deletion.js)
 *   offer-media cleanup sweeps (runOfferMediaSweeps; OFF unless configured)
 *   owner-media cleanup sweeps (runOwnerMediaSweeps; OFF unless configured)
 *
 * Owner media (the Owner records' private photos and videos) is the same
 * lifecycle as Offer media, run for a different parent record: the same types,
 * limits, idempotency, removal and sweeps, with its own table (`owners`), link
 * table (`owner_media`), key segment (`profiles/<uid>/owners/<ownerRecordId>/`)
 * and confirm function (`confirm_owner_media_upload`). See MEDIA_PARENTS.
 *
 * Offer media identity: the app generates each item's `mediaObjectId` once,
 * on the device, and it stays the item's identity everywhere — the
 * `media_objects` row, the R2 key and the app's local cache. Authorize,
 * confirm and remove are idempotent on it, so retrying the same logical
 * upload can never create a second object.
 *
 * Offer media deliberately reuses the profile image's own R2 object-key
 * prefix, `profiles/<uid>/...` (nesting under it as
 * `profiles/<uid>/offers/<offerId>/<mediaId>.<ext>`), rather than a separate
 * top-level prefix. `account_deletion.js`'s `removeAccountMedia` inventories
 * every `media_objects` row for the account and requires every object key to
 * start with that same per-account prefix — see its own comment: "a key
 * outside the account's prefix... deletion stops rather than orphan it." A
 * separate `offers/...` prefix would make that check throw
 * `media_cleanup_failed` for any account that ever attached offer media,
 * breaking account deletion. Nesting under the existing prefix keeps offer
 * media inside the account-deletion sweep with no change to that file.
 */

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_OFFER_VIDEO_BYTES = 100 * 1024 * 1024;
// Owner decision: at most 10 media items (images and videos together) per
// Offer. Enforced atomically at confirm time by the database function
// `confirm_offer_media_upload`, which locks the Offer row, counts its ready
// media in this bucket, attaches the upload at the next position and marks it
// ready in one transaction, so two concurrent confirms can never both take
// the last place.
const MAX_MEDIA_PER_OFFER = 10;
// Owner decision: three minutes per video, enforced here on the trusted
// server, not only in the app. The tolerance absorbs encoder rounding (a clip
// the camera reports as 3:00 can measure a few tens of milliseconds over).
const MAX_VIDEO_DURATION_MS = 3 * 60 * 1000;
const VIDEO_DURATION_TOLERANCE_MS = 1000;
// Bounds on reading an ISO base-media file's box structure: a video's `moov`
// box may sit at the end of the file (phone cameras usually write it last), so
// it is reached by walking top-level box headers, each a tiny ranged read,
// rather than by downloading the file.
const MAX_BOX_WALK_STEPS = 24;
const BOX_HEADER_BYTES = 16;
const MOOV_SCAN_BYTES = 512;
// Offer media only. Profile images keep their own image-only allowlist
// (isAllowedContentType below), which this table deliberately does not touch.
// `acceptsUploads: false` keeps a type readable for media that already exists
// while refusing new uploads of it: the app converts HEIC/HEIF photos to JPEG
// on the device, so new Offer media never depends on platform HEIF decoding.
const OFFER_MEDIA_TYPES = {
  'image/jpeg': { extension: 'jpg', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES, acceptsUploads: true },
  'image/png': { extension: 'png', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES, acceptsUploads: true },
  'image/webp': { extension: 'webp', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES, acceptsUploads: true },
  'image/heic': { extension: 'heic', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES, acceptsUploads: false },
  'video/mp4': { extension: 'mp4', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES, acceptsUploads: true },
  'video/quicktime': { extension: 'mov', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES, acceptsUploads: true },
  'video/3gpp': { extension: '3gp', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES, acceptsUploads: true },
};
const OFFER_MEDIA_CONFIRM_RPC = '/rest/v1/rpc/confirm_offer_media_upload';
// Scheduled Offer-media cleanup. Ships `off` (a missing or unknown value is
// also off); `dry_run` performs the same selections and only counts them;
// `on` deletes. Owner decision: media of a soft-deleted Offer and failed
// uploads are kept this long before the sweep removes them.
const OFFER_MEDIA_SWEEP_MODES = new Set(['off', 'dry_run', 'on']);
const OFFER_MEDIA_SWEEP_BATCH = 10;
const OFFER_MEDIA_SWEEP_DRY_RUN_LIMIT = 100;
const OFFER_MEDIA_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
// Every sweep is confined to Offer media keys; profile images are never
// touched by it.
const OFFER_MEDIA_KEY_PATTERN = 'profiles/*/offers/*';
// Owner decision (2026-09-28): Owner media follows the Offer media rules —
// the same types and size limits (OFFER_MEDIA_TYPES), three minutes per video,
// at most 10 items per Owner record, and 7 days' retention for the media of a
// soft-deleted Owner. The limit is enforced atomically at confirm time by
// `confirm_owner_media_upload`, exactly as for Offers.
const MAX_MEDIA_PER_OWNER = 10;
const OWNER_MEDIA_CONFIRM_RPC = '/rest/v1/rpc/confirm_owner_media_upload';
const OWNER_MEDIA_KEY_PATTERN = 'profiles/*/owners/*';

/**
 * The records private media can belong to. Everything that differs between an
 * Offer's media and an Owner's is here; the lifecycle itself — types, sizes,
 * duration, idempotent authorize/confirm/remove and the sweeps — is shared.
 *
 * Each parent keeps its own route prefix, its own confirm function and its own
 * key segment, so neither can attach, list or remove the other's media: every
 * check below compares a row's object key with the parent's own key.
 */
const MEDIA_PARENTS = Object.freeze({
  offer: Object.freeze({
    title: 'Offer',
    noun: 'offer',
    idField: 'offerId',
    table: 'offers',
    linkTable: 'offer_media',
    linkColumn: 'offer_id',
    keySegment: 'offers',
    keyPattern: OFFER_MEDIA_KEY_PATTERN,
    confirmRpc: OFFER_MEDIA_CONFIRM_RPC,
    rpcParentParam: 'p_offer_id',
    maxItems: MAX_MEDIA_PER_OFFER,
    notFoundCode: 'offer_not_found',
    limitCode: 'offer_media_limit_reached',
    sweepModeVar: 'OFFER_MEDIA_SWEEP_MODE',
    sweepLogTag: 'offer-media-sweep',
    deletedParentReportKey: 'deletedOfferMedia',
  }),
  owner: Object.freeze({
    title: 'Owner',
    noun: 'owner',
    idField: 'ownerRecordId',
    table: 'owners',
    linkTable: 'owner_media',
    linkColumn: 'owner_record_id',
    keySegment: 'owners',
    keyPattern: OWNER_MEDIA_KEY_PATTERN,
    confirmRpc: OWNER_MEDIA_CONFIRM_RPC,
    rpcParentParam: 'p_owner_record_id',
    maxItems: MAX_MEDIA_PER_OWNER,
    notFoundCode: 'owner_not_found',
    limitCode: 'owner_media_limit_reached',
    sweepModeVar: 'OWNER_MEDIA_SWEEP_MODE',
    sweepLogTag: 'owner-media-sweep',
    deletedParentReportKey: 'deletedOwnerMedia',
  }),
});
// ISO base-media `ftyp` brands, matched case-sensitively as written in the
// file. HEIF image brands are handled by detectImageMimeFromBytes.
const MP4_BRANDS = new Set(['isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V ', 'M4VH', 'M4VP', 'dash', 'mmp4', 'MSNV', 'f4v ']);
const QUICKTIME_BRANDS = new Set(['qt  ']);
const THREE_GPP_BRANDS = new Set(['3gp4', '3gp5', '3gp6', '3gp7', '3ge6', '3ge7', '3gg6']);
// Shared with account deletion, whose finalization window is derived from it.
const PUT_URL_TTL_SECONDS = SIGNED_PUT_TTL_SECONDS;
const GET_URL_TTL_SECONDS = 900;
const PENDING_CLEANUP_AGE_MS = 24 * 60 * 60 * 1000;
const SIGNATURE_BYTES_TO_READ = 64;
const MEDIA_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') return corsResponse(null, 204, env);

    // Staging only (no-op when STAGING_TEST_KEY is not bound, as in production).
    // Runs before any Supabase, R2 or account logic.
    if (!(await stagingRequestAllowed(request, env))) {
      return corsResponse({ error: 'Forbidden' }, 403, env);
    }

    const path = new URL(request.url).pathname;
    if (request.method === 'POST' && path === ACCOUNT_DELETE_PATH) {
      // Handed to waitUntil as well, so a client that disconnects mid-request
      // does not cancel a deletion between its R2 cleanup and its auth delete.
      // The handler never rejects and returns only fixed error codes.
      const deletion = handleAccountDeletion(request, env, { respond: corsResponse });
      ctx?.waitUntil?.(deletion);
      return deletion;
    }
    try {
      if (request.method === 'POST' && path === '/authorize') return await handleAuthorize(request, env);
      if (request.method === 'POST' && path === '/confirm') return await handleConfirm(request, env);
      if (request.method === 'GET' && path === '/profile-image-url') return await handleProfileImageUrl(request, env);
      if (request.method === 'POST' && path === '/offer-media/authorize') return await handleMediaAuthorize(request, env, MEDIA_PARENTS.offer);
      if (request.method === 'POST' && path === '/offer-media/confirm') return await handleMediaConfirm(request, env, MEDIA_PARENTS.offer);
      if (request.method === 'GET' && path === '/offer-media') return await handleMediaList(request, env, MEDIA_PARENTS.offer);
      if (request.method === 'POST' && path === '/offer-media/remove') return await handleMediaRemove(request, env, MEDIA_PARENTS.offer);
      if (request.method === 'POST' && path === '/owner-media/authorize') return await handleMediaAuthorize(request, env, MEDIA_PARENTS.owner);
      if (request.method === 'POST' && path === '/owner-media/confirm') return await handleMediaConfirm(request, env, MEDIA_PARENTS.owner);
      if (request.method === 'GET' && path === '/owner-media') return await handleMediaList(request, env, MEDIA_PARENTS.owner);
      if (request.method === 'POST' && path === '/owner-media/remove') return await handleMediaRemove(request, env, MEDIA_PARENTS.owner);
      return corsResponse({ error: 'Not found' }, 404, env);
    } catch (error) {
      console.error('[r2-profile-upload] request failed', error);
      return corsResponse(
        error instanceof WorkerError
          ? { error: error.message, ...(error.code ? { code: error.code } : {}) }
          : { error: 'Internal error' },
        error instanceof WorkerError ? error.status : 500,
        env,
      );
    }
  },

  // Server-owned completion of account deletions. Needs no client and accepts
  // no client identity; see runDeletionFinalizer.
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(runDeletionFinalizer(env));
    // Independent of the finalizer and never reject. Each does nothing unless
    // its own OFFER_MEDIA_SWEEP_MODE / OWNER_MEDIA_SWEEP_MODE is explicitly
    // configured.
    ctx.waitUntil(runOfferMediaSweeps(env));
    ctx.waitUntil(runOwnerMediaSweeps(env));
  },
};

async function handleAuthorize(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  await bestEffortCleanupAbandonedPending(userId, env, profileCleanupScope(userId));

  const body = await readJson(request);
  const { userId: bodyUserId, contentType, contentLength, originalFileName } = body;
  if (bodyUserId !== undefined && bodyUserId !== userId) {
    throw new WorkerError('userId in body does not match authenticated user', 403);
  }
  if (!isAllowedContentType(contentType)) {
    throw new WorkerError('Unsupported content type', 400);
  }
  if (!Number.isInteger(contentLength) || contentLength < 1 || contentLength > MAX_IMAGE_BYTES) {
    throw new WorkerError('contentLength must be an integer between 1 and 10485760 bytes', 400);
  }

  const mediaObjectId = crypto.randomUUID();
  const objectKey = expectedObjectKey(userId, mediaObjectId, contentType);
  const insertRes = await supabaseServiceFetch(env, 'POST', '/rest/v1/media_objects', {
    id: mediaObjectId,
    owner_id: userId,
    bucket: env.R2_BUCKET_NAME,
    object_key: objectKey,
    media_type: 'image',
    content_type: contentType,
    size_bytes: contentLength,
    original_file_name: sanitizeOriginalFileName(originalFileName),
    status: 'pending_upload',
  });
  if (!insertRes.ok) {
    throw new WorkerError('Failed to create pending media metadata', 502);
  }

  try {
    // Account deletion quarantine. The clock is read BEFORE the check and the
    // signature date is bounded by it, so every URL issued here expires before
    // any deletion job that this check could have missed is finalized.
    const quarantineCheckedAt = Date.now();
    await assertUploadsAllowed(userId, env);
    const presignedUrl = await createPresignedR2Url({
      env,
      method: 'PUT',
      objectKey,
      contentType,
      expiresInSeconds: PUT_URL_TTL_SECONDS,
    });
    assertPresignedWithin(presignedUrl, quarantineCheckedAt + MAX_SIGNING_DELAY_MS);
    return corsResponse(
      { presignedUrl, mediaObjectId, objectKey, expiresInSeconds: PUT_URL_TTL_SECONDS },
      200,
      env,
      { 'Cache-Control': 'no-store' },
    );
  } catch (error) {
    await bestEffortDeletePendingMedia(mediaObjectId, userId, env);
    if (error instanceof AccountDeletionError) {
      throw new WorkerError(
        error.code === 'deletion_in_progress' ? 'Account deletion in progress' : 'Upload authorization unavailable',
        error.status,
      );
    }
    throw error;
  }
}

async function handleConfirm(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const { mediaObjectId } = await readJson(request);
  if (typeof mediaObjectId !== 'string' || !MEDIA_ID_PATTERN.test(mediaObjectId)) {
    throw new WorkerError('mediaObjectId is required', 400);
  }

  const row = await loadOwnedMedia(mediaObjectId, userId, env);
  if (row.bucket !== env.R2_BUCKET_NAME || !isExpectedObjectKey(row, userId)) {
    throw new WorkerError('Media object is not in the configured profile-image bucket', 409);
  }
  if (row.status === 'ready') {
    const linkedId = await loadProfileMediaId(userId, env);
    if (linkedId === mediaObjectId) {
      return corsResponse({ profileMediaId: mediaObjectId, alreadyConfirmed: true }, 200, env);
    }
  }
  if (row.status !== 'pending_upload' && row.status !== 'ready') {
    throw new WorkerError(`Unexpected media status: ${row.status}`, 409);
  }

  const r2Object = await env.MEDIA_BUCKET.head(row.object_key);
  if (!r2Object) {
    await rejectInvalidUpload(row, userId, env, 'Object not found in R2');
  }
  if (r2Object.size < 1 || r2Object.size > MAX_IMAGE_BYTES) {
    await rejectInvalidUpload(row, userId, env, 'R2 object size is invalid');
  }

  const signatureObject = await env.MEDIA_BUCKET.get(row.object_key, {
    range: { offset: 0, length: SIGNATURE_BYTES_TO_READ },
  });
  if (!signatureObject) {
    await rejectInvalidUpload(row, userId, env, 'R2 object body not found');
  }
  const signatureBytes = new Uint8Array(await signatureObject.arrayBuffer());
  const detectedContentType = detectImageMimeFromBytes(signatureBytes);
  const observedContentType = r2Object.httpMetadata?.contentType ?? null;
  if (
    !detectedContentType ||
    detectedContentType !== row.content_type ||
    (observedContentType !== null && observedContentType !== row.content_type)
  ) {
    await rejectInvalidUpload(row, userId, env, 'Uploaded image type does not match authorized metadata');
  }

  const confirmRes = await supabaseServiceFetch(
    env,
    'POST',
    '/rest/v1/rpc/confirm_profile_media_upload',
    {
      p_user_id: userId,
      p_media_id: mediaObjectId,
      p_observed_size: r2Object.size,
      p_observed_content_type: observedContentType || detectedContentType,
    },
    { preferRepresentation: true },
  );
  if (!confirmRes.ok) throw new WorkerError('Profile confirm RPC failed', 502);

  const confirmRows = await confirmRes.json();
  const result = Array.isArray(confirmRows) ? confirmRows[0] : confirmRows;
  const previousMediaId = result?.previous_media_id ?? null;
  if (previousMediaId && previousMediaId !== mediaObjectId) {
    await bestEffortDeleteMediaById(previousMediaId, userId, env);
  }
  return corsResponse(
    {
      profileMediaId: mediaObjectId,
      previousMediaId,
      replacementCleanupAttempted: Boolean(previousMediaId && previousMediaId !== mediaObjectId),
    },
    200,
    env,
  );
}

async function handleProfileImageUrl(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const mediaObjectId = await loadProfileMediaId(userId, env);
  if (!mediaObjectId) {
    return corsResponse({ profileMediaId: null, profileImageUrl: null }, 200, env, { 'Cache-Control': 'no-store' });
  }

  const mediaRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.ready&select=id,bucket,object_key,content_type`,
  );
  if (!mediaRes.ok) throw new WorkerError('Failed to read profile media metadata', 502);
  const media = (await mediaRes.json())?.[0];
  if (!media) {
    return corsResponse({ profileMediaId: mediaObjectId, profileImageUrl: null }, 200, env, { 'Cache-Control': 'no-store' });
  }
  if (media.bucket !== env.R2_BUCKET_NAME || !isExpectedObjectKey(media, userId)) {
    throw new WorkerError('Profile media is not in the configured profile-image bucket', 409);
  }

  const profileImageUrl = await createPresignedR2Url({
    env,
    method: 'GET',
    objectKey: media.object_key,
    expiresInSeconds: GET_URL_TTL_SECONDS,
  });
  return corsResponse(
    { profileMediaId: mediaObjectId, profileImageUrl, expiresInSeconds: GET_URL_TTL_SECONDS },
    200,
    env,
    { 'Cache-Control': 'no-store' },
  );
}

/**
 * Starts (or resumes) one upload of [parent] media: `POST /offer-media/authorize`
 * with `offerId`, or `POST /owner-media/authorize` with `ownerRecordId`.
 */
async function handleMediaAuthorize(request, env, parent) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);

  const body = await readJson(request);
  const parentId = requireUuid(body[parent.idField], parent.idField);
  // The app sends the id it generated for this item, which makes authorize
  // idempotent: a retry of the same logical upload resumes the same row and
  // R2 key instead of creating a second object. Older builds send none and
  // get a server-generated id, as before.
  const requestedId = body.mediaObjectId == null ? null : requireUuid(body.mediaObjectId, 'mediaObjectId');
  const { contentType, contentLength, originalFileName } = body;
  if (!acceptsOfferUpload(contentType)) {
    throw new WorkerError('Unsupported content type', 400, 'unsupported_media_type');
  }
  const offerType = OFFER_MEDIA_TYPES[contentType];
  if (!Number.isInteger(contentLength) || contentLength < 1 || contentLength > offerType.maxBytes) {
    throw new WorkerError(
      `contentLength must be an integer between 1 and ${offerType.maxBytes} bytes`,
      400,
      offerType.mediaType === 'video' ? 'video_too_large' : 'image_too_large',
    );
  }

  await assertOwnsParent(parent, parentId, userId, env);
  await bestEffortCleanupAbandonedPending(userId, env, parentCleanupScope(parent, userId, parentId));

  const mediaObjectId = requestedId ?? crypto.randomUUID();
  const upload = {
    parent,
    userId,
    parentId,
    mediaObjectId,
    contentType,
    contentLength,
    offerType,
    objectKey: parentObjectKey(parent, userId, parentId, mediaObjectId, contentType),
  };

  if (requestedId) {
    const existing = await findMediaById(requestedId, env);
    if (existing) return resumeMediaUpload(existing, upload, env);
  }

  // Early, friendly refusal so a full Offer or Owner never transfers a 100 MB
  // upload for nothing. Not the guarantee: that is the database function at
  // confirm.
  await assertParentMediaCapacity(parent, parentId, userId, env, mediaObjectId);

  const insertRes = await supabaseServiceFetch(env, 'POST', '/rest/v1/media_objects', {
    id: mediaObjectId,
    owner_id: userId,
    bucket: env.R2_BUCKET_NAME,
    object_key: upload.objectKey,
    media_type: offerType.mediaType,
    content_type: contentType,
    size_bytes: contentLength,
    original_file_name: sanitizeOriginalFileName(originalFileName),
    status: 'pending_upload',
  });
  if (!insertRes.ok) {
    if (requestedId && insertRes.status === 409) {
      // A concurrent request for the same id created the row first.
      const raced = await findMediaById(requestedId, env);
      if (raced) return resumeMediaUpload(raced, upload, env);
    }
    throw new WorkerError('Failed to create pending media metadata', 502);
  }
  return signMediaUpload(upload, env, { createdNow: true });
}

/**
 * Answers an authorize for an id that already has a `media_objects` row.
 *
 * The id stays bound to the account, parent record (Offer or Owner), key and
 * type it was first authorized for; anything else is refused without touching
 * the row — an id first used for an Offer can never be resumed as an Owner's,
 * because the object key names the parent. A pending row is re-signed for the
 * same key (a partial earlier upload is simply overwritten), a ready one needs
 * no upload at all, and a rejected or removed one is final for this id.
 */
async function resumeMediaUpload(row, upload, env) {
  if (row.owner_id !== upload.userId) {
    // Another account's row: refused, and nothing about it is revealed.
    throw new WorkerError('Media id is not available', 409, 'media_id_conflict');
  }
  if (
    row.bucket !== env.R2_BUCKET_NAME ||
    row.object_key !== upload.objectKey ||
    row.content_type !== upload.contentType
  ) {
    throw new WorkerError('Media id was used for a different upload', 409, 'idempotency_mismatch');
  }
  switch (row.status) {
    case 'pending_upload':
      if (Number(row.size_bytes) !== upload.contentLength) {
        throw new WorkerError('Media id was used for a different upload', 409, 'idempotency_mismatch');
      }
      return signMediaUpload(upload, env, { createdNow: false });
    case 'ready':
      if (!(await findParentMediaLink(upload.parent, upload.parentId, row.id, env))) {
        throw new WorkerError(`Media is not attached to this ${upload.parent.noun}`, 409, 'invalid_state');
      }
      return corsResponse(
        {
          status: 'ready',
          mediaObjectId: row.id,
          objectKey: row.object_key,
          mediaType: upload.offerType.mediaType,
        },
        200,
        env,
        { 'Cache-Control': 'no-store' },
      );
    case 'failed':
      throw new WorkerError('This upload was rejected', 409, 'upload_rejected');
    case 'pending_delete':
    case 'deleted':
      throw new WorkerError('This media was removed', 410, 'media_removed');
    default:
      throw new WorkerError(`Unexpected media status: ${row.status}`, 409, 'invalid_state');
  }
}

/** Issues the signed PUT for [upload], subject to the account-deletion quarantine. */
async function signMediaUpload(upload, env, { createdNow }) {
  try {
    const quarantineCheckedAt = Date.now();
    await assertUploadsAllowed(upload.userId, env);
    const presignedUrl = await createPresignedR2Url({
      env,
      method: 'PUT',
      objectKey: upload.objectKey,
      contentType: upload.contentType,
      expiresInSeconds: PUT_URL_TTL_SECONDS,
    });
    assertPresignedWithin(presignedUrl, quarantineCheckedAt + MAX_SIGNING_DELAY_MS);
    return corsResponse(
      {
        status: 'pending',
        presignedUrl,
        mediaObjectId: upload.mediaObjectId,
        objectKey: upload.objectKey,
        mediaType: upload.offerType.mediaType,
        expiresInSeconds: PUT_URL_TTL_SECONDS,
      },
      200,
      env,
      { 'Cache-Control': 'no-store' },
    );
  } catch (error) {
    // Only a row this request created is withdrawn. A resumed row may already
    // hold uploaded bytes and stays for the next attempt.
    if (createdNow) await bestEffortDeletePendingMedia(upload.mediaObjectId, upload.userId, env);
    if (error instanceof AccountDeletionError) {
      const inProgress = error.code === 'deletion_in_progress';
      throw new WorkerError(
        inProgress ? 'Account deletion in progress' : 'Upload authorization unavailable',
        error.status,
        inProgress ? 'deletion_in_progress' : undefined,
      );
    }
    throw error;
  }
}

/**
 * Verifies an uploaded file and attaches it to its parent record:
 * `POST /offer-media/confirm` or `POST /owner-media/confirm`.
 */
async function handleMediaConfirm(request, env, parent) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const body = await readJson(request);
  const parentId = requireUuid(body[parent.idField], parent.idField);
  const mediaObjectId = requireUuid(body.mediaObjectId, 'mediaObjectId');
  // A client's role/ordinal are neither trusted nor needed: the database
  // function chooses the position. Older builds still send them; ignored.

  await assertOwnsParent(parent, parentId, userId, env);

  const row = await findOwnedMedia(mediaObjectId, userId, env);
  if (!row) throw new WorkerError('Media object not found or not owned by user', 404, 'media_not_found');
  if (row.bucket !== env.R2_BUCKET_NAME || !isExpectedParentObjectKey(parent, row, userId, parentId)) {
    throw new WorkerError(`Media object is not in the configured ${parent.noun}-media location`, 409, 'media_mismatch');
  }
  if (row.status === 'ready') {
    // Ready is only ever set together with the attachment, in one database
    // transaction, so a retry after a lost response finds the work done.
    const link = await findParentMediaLink(parent, parentId, mediaObjectId, env);
    if (!link) throw new WorkerError(`Media is not attached to this ${parent.noun}`, 409, 'invalid_state');
    return corsResponse(
      { [parent.idField]: parentId, mediaObjectId, ordinal: link.ordinal, alreadyConfirmed: true },
      200,
      env,
    );
  }
  if (row.status === 'failed') {
    throw new WorkerError('This upload was rejected', 409, 'upload_rejected');
  }
  if (row.status === 'pending_delete' || row.status === 'deleted') {
    throw new WorkerError('This media was removed', 410, 'media_removed');
  }
  if (row.status !== 'pending_upload') {
    throw new WorkerError(`Unexpected media status: ${row.status}`, 409, 'invalid_state');
  }

  const r2Object = await env.MEDIA_BUCKET.head(row.object_key);
  if (!r2Object) {
    // The bytes have not arrived: an interrupted or never-started upload.
    // Nothing is marked failed — the app uploads again under the same id.
    throw new WorkerError('The upload has not arrived', 409, 'upload_incomplete');
  }
  const offerType = OFFER_MEDIA_TYPES[row.content_type];
  if (r2Object.size > offerType.maxBytes) {
    await rejectInvalidUpload(
      row,
      userId,
      env,
      'R2 object size is invalid',
      422,
      offerType.mediaType === 'video' ? 'video_too_large' : 'image_too_large',
    );
  }
  if (r2Object.size < 1) {
    await rejectInvalidUpload(row, userId, env, 'R2 object size is invalid', 422, 'unsupported_media_type');
  }

  const signatureObject = await env.MEDIA_BUCKET.get(row.object_key, {
    range: { offset: 0, length: SIGNATURE_BYTES_TO_READ },
  });
  if (!signatureObject) {
    throw new WorkerError('The upload has not arrived', 409, 'upload_incomplete');
  }
  const signatureBytes = new Uint8Array(await signatureObject.arrayBuffer());
  const detectedContentType = detectOfferMediaMimeFromBytes(signatureBytes);
  const observedContentType = r2Object.httpMetadata?.contentType ?? null;
  if (
    !detectedContentType ||
    detectedContentType !== row.content_type ||
    (observedContentType !== null && observedContentType !== row.content_type)
  ) {
    await rejectInvalidUpload(
      row,
      userId,
      env,
      'Uploaded media type does not match authorized metadata',
      422,
      'media_type_mismatch',
    );
  }

  // A video's real duration is measured from the uploaded bytes themselves.
  // The app checks this too, but a client check is a courtesy, not a rule: the
  // only enforcement that binds every caller is this one.
  let durationMs = null;
  if (offerType.mediaType === 'video') {
    durationMs = await readVideoDurationMs(row.object_key, r2Object.size, env);
    if (durationMs === null) {
      await rejectInvalidUpload(
        row,
        userId,
        env,
        'Video duration could not be read',
        422,
        'unsupported_media_type',
      );
    }
    if (durationMs > MAX_VIDEO_DURATION_MS + VIDEO_DURATION_TOLERANCE_MS) {
      await rejectInvalidUpload(row, userId, env, 'Video is longer than the limit', 422, 'video_too_long');
    }
  }

  const attach = await attachParentMedia(
    parent,
    {
      userId,
      parentId,
      mediaObjectId,
      size: r2Object.size,
      contentType: observedContentType || detectedContentType,
      durationMs,
    },
    env,
  );
  switch (attach.outcome) {
    case 'attached':
    case 'already_attached':
      return corsResponse({ [parent.idField]: parentId, mediaObjectId, ordinal: attach.ordinal }, 200, env);
    case 'limit_reached':
      return rejectInvalidUpload(row, userId, env, `${parent.title} media limit reached`, 409, parent.limitCode);
    case parent.notFoundCode:
      throw new WorkerError(`${parent.title} not found or not owned by user`, 404, parent.notFoundCode);
    default:
      throw new WorkerError('Media could not be attached', 409, 'invalid_state');
  }
}

/**
 * Attaches a validated upload to its parent record and marks it ready: one
 * call to the parent's service-role-only database function
 * (`confirm_offer_media_upload` / `confirm_owner_media_upload`), which does
 * both in a single transaction under a lock on the parent row. It also
 * enforces the parent's item limit (counting ready media in this bucket) and
 * assigns the next position, so there is no "attached but not ready" state and
 * no count-then-insert race. Idempotent: an attached item reports
 * `already_attached`. The parent-not-found outcome is `offer_not_found` /
 * `owner_not_found`.
 */
async function attachParentMedia(parent, { userId, parentId, mediaObjectId, size, contentType, durationMs }, env) {
  const res = await supabaseServiceFetch(
    env,
    'POST',
    parent.confirmRpc,
    {
      p_user_id: userId,
      [parent.rpcParentParam]: parentId,
      p_media_id: mediaObjectId,
      p_bucket: env.R2_BUCKET_NAME,
      p_max_items: parent.maxItems,
      p_observed_size: size,
      p_observed_content_type: contentType,
      p_duration_ms: durationMs,
    },
    { preferRepresentation: true },
  );
  if (!res.ok) {
    // Nothing is marked failed: the row stays pending and a retried confirm
    // repeats this same idempotent step.
    throw new WorkerError(`Failed to attach ${parent.noun} media`, 502);
  }
  const rows = await res.json();
  const result = Array.isArray(rows) ? rows[0] : rows;
  return { outcome: result?.outcome ?? null, ordinal: result?.media_ordinal ?? null };
}

/**
 * The duration of an ISO base-media video (MP4/MOV/3GP) in milliseconds, read
 * from its `moov > mvhd` header, or null when it cannot be determined.
 *
 * Deliberately reads only box headers and one small window around `mvhd`,
 * never the media data: a 100 MB video costs a handful of ranged reads of a
 * few hundred bytes. Failing to parse returns null and the caller fails
 * closed — a file whose structure cannot be read is not accepted.
 */
async function readVideoDurationMs(objectKey, objectSize, env) {
  try {
    let offset = 0;
    for (let step = 0; step < MAX_BOX_WALK_STEPS && offset + 8 <= objectSize; step += 1) {
      const header = await readBytes(objectKey, offset, BOX_HEADER_BYTES, env);
      if (!header || header.length < 8) return null;

      const type = String.fromCharCode(header[4], header[5], header[6], header[7]);
      let size = readUint32(header, 0);
      let headerSize = 8;
      if (size === 1) {
        if (header.length < 16) return null;
        // 64-bit size: the high word is only relevant for boxes far larger
        // than anything accepted here, so a set high word means "past the end".
        if (readUint32(header, 8) !== 0) return null;
        size = readUint32(header, 12);
        headerSize = 16;
      } else if (size === 0) {
        size = objectSize - offset; // extends to end of file
      }
      if (size < headerSize) return null;

      if (type === 'moov') {
        const moov = await readBytes(objectKey, offset + headerSize, Math.min(size - headerSize, MOOV_SCAN_BYTES), env);
        return moov ? parseMvhdDurationMs(moov) : null;
      }
      offset += size;
    }
    return null;
  } catch (error) {
    console.error('[r2-profile-upload] video duration read failed', error);
    return null;
  }
}

/** The duration in [moovBytes], found by locating its `mvhd` child. */
function parseMvhdDurationMs(moovBytes) {
  for (let i = 0; i + 4 <= moovBytes.length; i += 1) {
    if (
      moovBytes[i] !== 0x6d || // m
      moovBytes[i + 1] !== 0x76 || // v
      moovBytes[i + 2] !== 0x68 || // h
      moovBytes[i + 3] !== 0x64 // d
    ) {
      continue;
    }
    const body = i + 4;
    if (body >= moovBytes.length) return null;
    const version = moovBytes[body];
    // version/flags (4), then creation and modification times, timescale,
    // duration — 32-bit fields in version 0, 64-bit times in version 1.
    const timescaleAt = body + 4 + (version === 1 ? 16 : 8);
    if (version === 1) {
      if (timescaleAt + 12 > moovBytes.length) return null;
      const timescale = readUint32(moovBytes, timescaleAt);
      if (readUint32(moovBytes, timescaleAt + 4) !== 0) return null; // implausibly long
      const duration = readUint32(moovBytes, timescaleAt + 8);
      return timescale > 0 ? Math.round((duration / timescale) * 1000) : null;
    }
    if (timescaleAt + 8 > moovBytes.length) return null;
    const timescale = readUint32(moovBytes, timescaleAt);
    const duration = readUint32(moovBytes, timescaleAt + 4);
    if (timescale === 0 || duration === 0xffffffff) return null;
    return Math.round((duration / timescale) * 1000);
  }
  return null;
}

async function readBytes(objectKey, offset, length, env) {
  if (length <= 0) return null;
  const part = await env.MEDIA_BUCKET.get(objectKey, { range: { offset, length } });
  if (!part) return null;
  return new Uint8Array(await part.arrayBuffer());
}

function readUint32(bytes, offset) {
  return (
    ((bytes[offset] << 24) >>> 0) +
    (bytes[offset + 1] << 16) +
    (bytes[offset + 2] << 8) +
    bytes[offset + 3]
  );
}

/**
 * Refuses an authorize when the parent record (Offer or Owner) already holds,
 * or is currently receiving, its item limit: its ready media in this bucket
 * plus this account's still-pending uploads for it (other than
 * [excludeMediaId], the item being authorized) that are younger than the
 * abandoned-upload cutoff, so an interrupted upload stops counting once it is
 * old enough to be cleaned up rather than blocking the record forever.
 *
 * Only this bucket's media is counted, which keeps environments apart where
 * they share one database: staging test media never fills a production Offer.
 */
async function assertParentMediaCapacity(parent, parentId, userId, env, excludeMediaId) {
  const linksRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/${parent.linkTable}?${parent.linkColumn}=eq.${encodeURIComponent(parentId)}&select=media_id,media_objects(bucket,status)`,
  );
  if (!linksRes.ok) throw new WorkerError(`Failed to read ${parent.noun} media`, 502);
  const ready = ((await linksRes.json()) ?? []).filter(
    (link) => link.media_objects?.bucket === env.R2_BUCKET_NAME && link.media_objects?.status === 'ready',
  ).length;

  const prefix = parentKeyPrefix(parent, userId, parentId);
  const pendingRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_upload&object_key=like.${encodeURIComponent(prefix)}*&select=id,created_at`,
  );
  if (!pendingRes.ok) throw new WorkerError(`Failed to read pending ${parent.noun} media`, 502);
  const cutoff = Date.now() - PENDING_CLEANUP_AGE_MS;
  const inFlight = ((await pendingRes.json()) ?? []).filter((pending) => {
    if (pending.id === excludeMediaId) return false;
    const createdAt = Date.parse(pending.created_at);
    return Number.isNaN(createdAt) || createdAt > cutoff;
  }).length;

  if (ready + inFlight >= parent.maxItems) {
    throw new WorkerError(`${parent.title} media limit reached`, 409, parent.limitCode);
  }
}

/**
 * The parent record's ready media, each with a fresh short-lived signed GET:
 * `GET /offer-media?offerId=` or `GET /owner-media?ownerRecordId=`.
 */
async function handleMediaList(request, env, parent) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const parentId = requireUuid(new URL(request.url).searchParams.get(parent.idField), parent.idField);

  await assertOwnsParent(parent, parentId, userId, env);

  const linksRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/${parent.linkTable}?${parent.linkColumn}=eq.${encodeURIComponent(parentId)}&select=media_id,role,ordinal,media_objects(id,bucket,object_key,status,content_type,duration_ms)&order=ordinal.asc`,
  );
  if (!linksRes.ok) throw new WorkerError(`Failed to read ${parent.noun} media`, 502);
  const links = (await linksRes.json()) ?? [];

  const media = [];
  for (const link of links) {
    const object = link.media_objects;
    if (!object || object.status !== 'ready') continue;
    if (object.bucket !== env.R2_BUCKET_NAME || !isExpectedParentObjectKey(parent, object, userId, parentId)) continue;
    const url = await createPresignedR2Url({
      env,
      method: 'GET',
      objectKey: object.object_key,
      expiresInSeconds: GET_URL_TTL_SECONDS,
    });
    media.push({
      mediaObjectId: object.id,
      role: link.role,
      ordinal: link.ordinal,
      contentType: object.content_type,
      mediaType: OFFER_MEDIA_TYPES[object.content_type].mediaType,
      durationMs: object.duration_ms ?? null,
      url,
    });
  }

  return corsResponse(
    { [parent.idField]: parentId, media, expiresInSeconds: GET_URL_TTL_SECONDS },
    200,
    env,
    { 'Cache-Control': 'no-store' },
  );
}

/**
 * Removes one media item from a parent record (Offer or Owner) the caller
 * owns: `POST /offer-media/remove` or `POST /owner-media/remove`. Idempotent.
 *
 * - Never attached (`pending_upload` or `failed`): the row and any bytes that
 *   arrived are withdrawn. This is also how the app cancels a queued upload
 *   and frees the place it reserved.
 * - Ready: marked `pending_delete` first, which on its own takes it out of the
 *   listing and the limit; then unlinked, its R2 object deleted and the row
 *   kept as a `deleted` tombstone. A step that does not finish here is
 *   finished by the scheduled sweep, and the response says so.
 * - Already removed, or no such media for this account: success, and nothing
 *   is revealed about media the caller does not own.
 * - Media of the same account under a different parent (another Offer, or an
 *   Offer's media sent to the Owner route): refused as `media_mismatch`.
 */
async function handleMediaRemove(request, env, parent) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const body = await readJson(request);
  const parentId = requireUuid(body[parent.idField], parent.idField);
  const mediaObjectId = requireUuid(body.mediaObjectId, 'mediaObjectId');

  await assertOwnsParent(parent, parentId, userId, env);
  const ids = { [parent.idField]: parentId, mediaObjectId };

  // Every write below is guarded by the status it expects, so a concurrent
  // confirm can never be undone; if the row changed underneath, it is read
  // once more and handled in its new state.
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const row = await findOwnedMedia(mediaObjectId, userId, env);
    if (!row || row.status === 'deleted') {
      return removalResponse(env, { ...ids, alreadyRemoved: true });
    }
    if (row.bucket !== env.R2_BUCKET_NAME || !isExpectedParentObjectKey(parent, row, userId, parentId)) {
      throw new WorkerError(`Media object does not belong to this ${parent.noun}`, 409, 'media_mismatch');
    }
    if (row.status === 'pending_upload' || row.status === 'failed') {
      // Row first: once it is gone no confirm can attach it, so deleting the
      // bytes afterwards can never leave a ready item without its object.
      if (await deleteMediaRowIfStatus(row.id, row.status, env)) {
        const objectDeleted = await bestEffortDeleteObject(row.object_key, env);
        return removalResponse(env, { ...ids, ...(objectDeleted ? {} : { cleanupPending: true }) });
      }
      continue;
    }
    if (row.status === 'ready') {
      if (await markMediaPendingDelete(row.id, 'ready', env)) {
        return removalResponse(env, { ...ids, ...(await completeMediaRemoval(parent, row, env)) });
      }
      continue;
    }
    if (row.status === 'pending_delete') {
      return removalResponse(env, {
        ...ids,
        alreadyRemoved: true,
        ...(await completeMediaRemoval(parent, row, env)),
      });
    }
    throw new WorkerError(`Unexpected media status: ${row.status}`, 409, 'invalid_state');
  }
  throw new WorkerError('Media changed during removal; try again', 409, 'invalid_state');
}

function removalResponse(env, body) {
  return corsResponse({ removed: true, ...body }, 200, env, { 'Cache-Control': 'no-store' });
}

/**
 * Finishes removing a media object already marked `pending_delete`: unlinks
 * it from [parent]'s link table, deletes its R2 object and tombstones the row
 * as `deleted`. Each step is idempotent; one that does not complete leaves the
 * row in `pending_delete` — neither listed nor counted — for the sweep to
 * finish.
 */
async function completeMediaRemoval(parent, row, env) {
  const unlinked = await supabaseServiceFetch(
    env,
    'DELETE',
    `/rest/v1/${parent.linkTable}?media_id=eq.${encodeURIComponent(row.id)}`,
  );
  if (!unlinked.ok) return { cleanupPending: true };
  if (!(await bestEffortDeleteObject(row.object_key, env))) return { cleanupPending: true };
  const tombstoned = await supabaseServiceFetch(
    env,
    'PATCH',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(row.id)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_delete`,
    { status: 'deleted' },
  );
  return tombstoned.ok ? {} : { cleanupPending: true };
}

/**
 * Refuses unless [userId] owns the live (not soft-deleted) [parent] record
 * [parentId]. The 404 is only ever answered after the ownership query itself
 * succeeded, so the app may treat it as authoritative.
 */
async function assertOwnsParent(parent, parentId, userId, env) {
  const parentRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/${parent.table}?id=eq.${encodeURIComponent(parentId)}&owner_id=eq.${encodeURIComponent(userId)}&deleted_at=is.null&select=id`,
  );
  if (!parentRes.ok) throw new WorkerError(`Failed to verify ${parent.noun} ownership`, 502);
  const rows = await parentRes.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    throw new WorkerError(`${parent.title} not found or not owned by user`, 404, parent.notFoundCode);
  }
}

/** The account's key prefix for one parent record's media. */
function parentKeyPrefix(parent, userId, parentId) {
  return `profiles/${userId}/${parent.keySegment}/${parentId}/`;
}

function parentObjectKey(parent, userId, parentId, mediaObjectId, contentType) {
  const extension = OFFER_MEDIA_TYPES[contentType]?.extension;
  // Deliberately nested under the existing profile-image account prefix —
  // see the file header comment for why.
  return `${parentKeyPrefix(parent, userId, parentId)}${mediaObjectId}.${extension}`;
}

function isExpectedParentObjectKey(parent, row, userId, parentId) {
  return (
    isAllowedOfferContentType(row.content_type) &&
    row.object_key === parentObjectKey(parent, userId, parentId, row.id, row.content_type)
  );
}

function isAllowedOfferContentType(contentType) {
  return typeof contentType === 'string' && Object.hasOwn(OFFER_MEDIA_TYPES, contentType);
}

/** Whether [contentType] may be newly uploaded as Offer media. */
function acceptsOfferUpload(contentType) {
  return isAllowedOfferContentType(contentType) && OFFER_MEDIA_TYPES[contentType].acceptsUploads === true;
}

/** A client-supplied UUID in canonical lower case; a 400 when malformed. */
function requireUuid(value, name) {
  if (typeof value !== 'string' || !MEDIA_ID_PATTERN.test(value)) {
    throw new WorkerError(`${name} is required`, 400, 'invalid_request');
  }
  return value.toLowerCase();
}

/** The media row with [mediaObjectId] under any owner, or null. */
async function findMediaById(mediaObjectId, env) {
  const res = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&select=id,owner_id,bucket,object_key,status,content_type,size_bytes`,
  );
  if (!res.ok) throw new WorkerError('Failed to load media object', 502);
  return (await res.json())?.[0] ?? null;
}

/** [userId]'s media row with [mediaObjectId], or null. */
async function findOwnedMedia(mediaObjectId, userId, env) {
  const res = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}&select=id,bucket,object_key,status,content_type`,
  );
  if (!res.ok) throw new WorkerError('Failed to load media object', 502);
  return (await res.json())?.[0] ?? null;
}

async function findParentMediaLink(parent, parentId, mediaObjectId, env) {
  const res = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/${parent.linkTable}?${parent.linkColumn}=eq.${encodeURIComponent(parentId)}&media_id=eq.${encodeURIComponent(mediaObjectId)}&select=media_id,ordinal`,
  );
  if (!res.ok) throw new WorkerError(`Failed to read ${parent.noun} media`, 502);
  return (await res.json())?.[0] ?? null;
}

/** Deletes a media row of this bucket only while it still has [status]. */
async function deleteMediaRowIfStatus(mediaObjectId, status, env) {
  const res = await supabaseServiceFetch(
    env,
    'DELETE',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.${encodeURIComponent(status)}`,
    undefined,
    { preferRepresentation: true },
  );
  if (!res.ok) throw new WorkerError('Failed to update media metadata', 502);
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

/** Moves a media row of this bucket from [fromStatus] to `pending_delete`. */
async function markMediaPendingDelete(mediaObjectId, fromStatus, env) {
  const res = await supabaseServiceFetch(
    env,
    'PATCH',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.${encodeURIComponent(fromStatus)}`,
    { status: 'pending_delete', deleted_at: new Date().toISOString() },
    { preferRepresentation: true },
  );
  if (!res.ok) throw new WorkerError('Failed to update media metadata', 502);
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

/** Deletes one R2 object; false when R2 refused. Never logs the key. */
async function bestEffortDeleteObject(objectKey, env) {
  try {
    await env.MEDIA_BUCKET.delete(objectKey);
    return true;
  } catch (_) {
    console.error('[r2-profile-upload] object deletion failed');
    return false;
  }
}

async function verifySupabaseTokenAndGetUserId(request, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) {
    throw new WorkerError('Missing Supabase public runtime configuration', 500);
  }
  const authorization = request.headers.get('Authorization') || '';
  if (!authorization.startsWith('Bearer ')) {
    throw new WorkerError('Missing or malformed Authorization header', 401);
  }
  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: authorization },
  });
  if (!userRes.ok) throw new WorkerError('Invalid or expired Supabase access token', 401);
  const userId = (await userRes.json())?.id;
  if (!userId || typeof userId !== 'string') {
    throw new WorkerError('Supabase token validation returned no user id', 401);
  }
  return userId;
}

async function loadOwnedMedia(mediaObjectId, userId, env) {
  const mediaRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}&select=id,bucket,object_key,status,content_type,size_bytes`,
  );
  if (!mediaRes.ok) throw new WorkerError('Failed to load media object', 502);
  const row = (await mediaRes.json())?.[0];
  if (!row) throw new WorkerError('Media object not found or not owned by user', 404);
  return row;
}

async function loadProfileMediaId(userId, env) {
  const profileRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=profile_media_id`,
  );
  if (!profileRes.ok) throw new WorkerError('Failed to read profile media linkage', 502);
  return (await profileRes.json())?.[0]?.profile_media_id ?? null;
}

async function createPresignedR2Url({ env, method, objectKey, contentType, expiresInSeconds }) {
  requireConfiguredBucket(env);
  if (!env.R2_S3_ENDPOINT || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
    throw new WorkerError('Missing R2 signing runtime configuration', 500);
  }
  const encodedKey = objectKey.split('/').map(encodeURIComponent).join('/');
  const signedUrl = new URL(`${env.R2_S3_ENDPOINT}/${env.R2_BUCKET_NAME}/${encodedKey}`);
  signedUrl.searchParams.set('X-Amz-Expires', String(expiresInSeconds));
  const headers = contentType ? { 'content-type': contentType } : {};
  const aws = new AwsClient({ accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY });
  const signedRequest = await aws.sign(new Request(signedUrl, { method, headers }), {
    aws: { signQuery: true, service: 's3', region: 'auto' },
  });
  return signedRequest.url;
}

async function supabaseServiceFetch(env, method, path, body, options = {}) {
  if (!env.SUPABASE_SECRET_KEY) throw new WorkerError('Missing Supabase server secret', 500);
  const preferParts = [options.preferRepresentation ? 'return=representation' : 'return=minimal'];
  // ON CONFLICT DO NOTHING instead of PostgREST's default merge-duplicates,
  // matching the same client-side pattern already used for Favorites inserts
  // (see FavoriteService.addToFavorites) — makes a retried offer_media link
  // insert idempotent instead of erroring on the primary key.
  if (options.ignoreDuplicates) preferParts.push('resolution=ignore-duplicates');
  const headers = {
    apikey: env.SUPABASE_SECRET_KEY,
    'Content-Type': 'application/json',
    Prefer: preferParts.join(','),
  };
  return fetch(`${env.SUPABASE_URL}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function rejectInvalidUpload(row, userId, env, reason, status = 422, code = undefined) {
  await bestEffortDeleteInvalidObjectAndMarkFailed(row, userId, env);
  throw new WorkerError(reason, status, code);
}

async function bestEffortDeleteInvalidObjectAndMarkFailed(row, userId, env) {
  try {
    await env.MEDIA_BUCKET.delete(row.object_key);
  } catch (error) {
    console.error('[r2-profile-upload] invalid object deletion failed', error);
  }
  try {
    const marked = await supabaseServiceFetch(
      env,
      'PATCH',
      `/rest/v1/media_objects?id=eq.${encodeURIComponent(row.id)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload`,
      { status: 'failed' },
    );
    // Not silently ignored. The row then stays pending_upload, which the
    // abandoned-upload cleanup removes once it is old enough.
    if (!marked.ok) console.error('[r2-profile-upload] failed-status update was refused', marked.status);
  } catch (error) {
    console.error('[r2-profile-upload] failed-status update failed', error);
  }
}

async function bestEffortDeletePendingMedia(mediaObjectId, userId, env) {
  try {
    await supabaseServiceFetch(
      env,
      'DELETE',
      `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload`,
    );
  } catch (error) {
    console.error('[r2-profile-upload] pending metadata cleanup failed', error);
  }
}

async function bestEffortDeleteMediaById(mediaObjectId, userId, env) {
  try {
    const row = await loadOwnedMedia(mediaObjectId, userId, env);
    if (row.bucket !== env.R2_BUCKET_NAME || !isExpectedObjectKey(row, userId)) return;
    await env.MEDIA_BUCKET.delete(row.object_key);
    const deleted = await supabaseServiceFetch(
      env,
      'DELETE',
      `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}`,
    );
    if (!deleted.ok) throw new Error('metadata deletion failed');
  } catch (error) {
    console.error('[r2-profile-upload] replaced media cleanup failed', error);
  }
}

/**
 * Withdraws abandoned uploads — `pending_upload` for longer than
 * PENDING_CLEANUP_AGE_MS — of ONE media entity, the one [scope] names: the
 * caller's profile image (profileCleanupScope), or one Offer's or one Owner's
 * media (parentCleanupScope). At most 10 per call, only the caller's rows,
 * only in this bucket. Best effort: never throws.
 *
 * Never account-wide: an authorize for one entity must not withdraw an upload
 * the app may still be retrying for another — a different Offer or Owner, or
 * the profile image — however old it is. The key filter is part of the query,
 * so another entity's older rows cannot fill the batch, and every row is
 * checked against the entity's exact key again before anything is deleted.
 */
async function bestEffortCleanupAbandonedPending(userId, env, scope) {
  try {
    const response = await supabaseServiceFetch(
      env,
      'GET',
      `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_upload${scope.keyFilter}&select=id,object_key,content_type,created_at&limit=10&order=created_at.asc`,
    );
    if (!response.ok) return;
    const cutoff = Date.now() - PENDING_CLEANUP_AGE_MS;
    for (const row of (await response.json()) ?? []) {
      if (!scope.includes(row)) continue;
      const createdAt = Date.parse(row.created_at);
      if (!Number.isNaN(createdAt) && createdAt <= cutoff) {
        try { await env.MEDIA_BUCKET.delete(row.object_key); } catch (_) { /* metadata cleanup still applies */ }
        await supabaseServiceFetch(
          env,
          'DELETE',
          `/rest/v1/media_objects?id=eq.${encodeURIComponent(row.id)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload`,
        );
      }
    }
  } catch (error) {
    console.error('[r2-profile-upload] abandoned pending cleanup failed', error);
  }
}

/**
 * The caller's profile image: keys directly under the account prefix,
 * `profiles/<uid>/<mediaId>.<ext>` — never the Offer and Owner media nested
 * below it (`profiles/<uid>/<segment>/<id>/...`).
 */
function profileCleanupScope(userId) {
  const accountPrefix = `profiles/${userId}/`;
  return {
    keyFilter:
      `&object_key=like.${encodeURIComponent(accountPrefix)}*` +
      `&object_key=not.like.${encodeURIComponent(`${accountPrefix}*/*`)}`,
    includes: (row) => isExpectedObjectKey(row, userId),
  };
}

/** One Offer's or one Owner's media: keys under that record's own prefix. */
function parentCleanupScope(parent, userId, parentId) {
  return {
    keyFilter: `&object_key=like.${encodeURIComponent(parentKeyPrefix(parent, userId, parentId))}*`,
    includes: (row) => isExpectedParentObjectKey(parent, row, userId, parentId),
  };
}

/**
 * Scheduled cleanup of Offer media. Returns a count-only report, never throws,
 * and never logs ids, keys or URLs.
 *
 * The mode comes from OFFER_MEDIA_SWEEP_MODE: `off` — also any missing or
 * unknown value — does nothing at all; `dry_run` runs the same selections and
 * only counts them; `on` applies them. Every sweep is confined to this
 * Worker's bucket and to Offer media keys, handles a small batch per run, and
 * guards each write by the status it expects, so it can never undo a
 * concurrent confirm and repeating it is harmless.
 *
 *   abandonedUploads   pending_upload older than 24 h: the row, then its bytes
 *   deletedOfferMedia  ready media of an Offer soft-deleted more than 7 days
 *                      ago: marked pending_delete
 *   pendingDeletes     pending_delete: unlinked, bytes deleted, tombstoned
 *                      `deleted`
 *   failedUploads      failed older than 7 days: the row (its bytes were
 *                      deleted at rejection; deleted again, idempotently)
 */
export function runOfferMediaSweeps(env, options = {}) {
  return runMediaSweeps(MEDIA_PARENTS.offer, env, options);
}

/**
 * Scheduled cleanup of Owner media: the same four sweeps as
 * [runOfferMediaSweeps], confined to Owner media keys (`profiles/*\/owners/*`)
 * and to the `owner_media` / `owners` tables, with its own switch,
 * OWNER_MEDIA_SWEEP_MODE (missing or unknown is `off`). Its report names the
 * soft-deleted-parent sweep `deletedOwnerMedia`.
 */
export function runOwnerMediaSweeps(env, options = {}) {
  return runMediaSweeps(MEDIA_PARENTS.owner, env, options);
}

async function runMediaSweeps(parent, env, { now = () => Date.now() } = {}) {
  const configured = env?.[parent.sweepModeVar];
  const mode = OFFER_MEDIA_SWEEP_MODES.has(configured) ? configured : 'off';
  const report = {
    mode,
    abandonedUploads: 0,
    [parent.deletedParentReportKey]: 0,
    pendingDeletes: 0,
    failedUploads: 0,
    errors: 0,
  };
  if (mode === 'off') return report;
  if (!env.R2_BUCKET_NAME || !env.MEDIA_BUCKET || !env.SUPABASE_URL || !env.SUPABASE_SECRET_KEY) {
    console.error(`[${parent.sweepLogTag}] missing configuration`);
    report.errors += 1;
    return report;
  }

  const context = {
    parent,
    env,
    at: now(),
    apply: mode === 'on',
    limit: mode === 'on' ? OFFER_MEDIA_SWEEP_BATCH : OFFER_MEDIA_SWEEP_DRY_RUN_LIMIT,
  };
  const sweeps = [
    ['abandonedUploads', sweepAbandonedUploads],
    [parent.deletedParentReportKey, sweepDeletedParentMedia],
    ['pendingDeletes', sweepPendingDeletes],
    ['failedUploads', sweepFailedUploads],
  ];
  for (const [name, sweep] of sweeps) {
    try {
      const result = await sweep(context);
      report[name] = result.count;
      report.errors += result.errors;
    } catch (_) {
      report.errors += 1;
    }
  }
  console.log(
    `[${parent.sweepLogTag}] mode=${mode} abandonedUploads=${report.abandonedUploads} ` +
      `${parent.deletedParentReportKey}=${report[parent.deletedParentReportKey]} pendingDeletes=${report.pendingDeletes} ` +
      `failedUploads=${report.failedUploads} errors=${report.errors}`,
  );
  return report;
}

async function sweepAbandonedUploads({ parent, env, at, apply, limit }) {
  const cutoff = new Date(at - PENDING_CLEANUP_AGE_MS).toISOString();
  const rows = await selectRows(
    env,
    `/rest/v1/media_objects?bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_upload` +
      `&created_at=lt.${encodeURIComponent(cutoff)}&object_key=like.${encodeURIComponent(parent.keyPattern)}` +
      `&select=id,object_key&order=created_at.asc&limit=${limit}`,
  );
  if (!apply) return { count: rows.length, errors: 0 };
  let count = 0;
  let errors = 0;
  for (const row of rows) {
    try {
      // Row first: once it is gone no confirm can attach it, so deleting the
      // bytes afterwards can never leave a ready item without its object.
      if (!(await deleteMediaRowIfStatus(row.id, 'pending_upload', env))) continue;
      if (await bestEffortDeleteObject(row.object_key, env)) count += 1;
      else errors += 1;
    } catch (_) {
      errors += 1;
    }
  }
  return { count, errors };
}

/**
 * Ready media of a parent record (Offer or Owner) soft-deleted more than the
 * retention period ago: marked `pending_delete`. Owner decision: the same 7
 * days for both.
 */
async function sweepDeletedParentMedia({ parent, env, at, apply, limit }) {
  const cutoff = new Date(at - OFFER_MEDIA_RETENTION_MS).toISOString();
  const rows = await selectRows(
    env,
    `/rest/v1/${parent.linkTable}?select=media_id,${parent.table}!inner(deleted_at),media_objects!inner(id,bucket,status)` +
      `&${parent.table}.deleted_at=lt.${encodeURIComponent(cutoff)}` +
      `&media_objects.bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&media_objects.status=eq.ready` +
      `&limit=${limit}`,
  );
  if (!apply) return { count: rows.length, errors: 0 };
  let count = 0;
  let errors = 0;
  for (const row of rows) {
    try {
      // From here the item is neither listed nor counted; the pending-delete
      // sweep owns finishing it, even if this run stops early.
      if (await markMediaPendingDelete(row.media_id, 'ready', env)) count += 1;
    } catch (_) {
      errors += 1;
    }
  }
  return { count, errors };
}

async function sweepPendingDeletes({ parent, env, apply, limit }) {
  const rows = await selectRows(
    env,
    `/rest/v1/media_objects?bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_delete` +
      `&object_key=like.${encodeURIComponent(parent.keyPattern)}` +
      `&select=id,object_key&order=updated_at.asc&limit=${limit}`,
  );
  if (!apply) return { count: rows.length, errors: 0 };
  let count = 0;
  let errors = 0;
  for (const row of rows) {
    try {
      const result = await completeMediaRemoval(parent, row, env);
      if (result.cleanupPending) errors += 1;
      else count += 1;
    } catch (_) {
      errors += 1;
    }
  }
  return { count, errors };
}

async function sweepFailedUploads({ parent, env, at, apply, limit }) {
  const cutoff = new Date(at - OFFER_MEDIA_RETENTION_MS).toISOString();
  const rows = await selectRows(
    env,
    `/rest/v1/media_objects?bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.failed` +
      `&updated_at=lt.${encodeURIComponent(cutoff)}&object_key=like.${encodeURIComponent(parent.keyPattern)}` +
      `&select=id,object_key&order=updated_at.asc&limit=${limit}`,
  );
  if (!apply) return { count: rows.length, errors: 0 };
  let count = 0;
  let errors = 0;
  for (const row of rows) {
    try {
      if (!(await deleteMediaRowIfStatus(row.id, 'failed', env))) continue;
      await bestEffortDeleteObject(row.object_key, env);
      count += 1;
    } catch (_) {
      errors += 1;
    }
  }
  return { count, errors };
}

async function selectRows(env, path) {
  const res = await supabaseServiceFetch(env, 'GET', path);
  if (!res.ok) throw new WorkerError('Failed to read media metadata', 502);
  const rows = await res.json();
  return Array.isArray(rows) ? rows : [];
}

function requireConfiguredBucket(env) {
  if (!env.R2_BUCKET_NAME || !env.MEDIA_BUCKET) {
    throw new WorkerError('Missing configured R2 bucket', 500);
  }
}

function isAllowedContentType(contentType) {
  return ['image/jpeg', 'image/png', 'image/webp', 'image/heic'].includes(contentType);
}

function expectedObjectKey(userId, mediaObjectId, contentType) {
  const extension = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic' }[contentType];
  return `profiles/${userId}/${mediaObjectId}.${extension}`;
}

function isExpectedObjectKey(row, userId) {
  return isAllowedContentType(row.content_type) && row.object_key === expectedObjectKey(userId, row.id, row.content_type);
}

function sanitizeOriginalFileName(value) {
  if (typeof value !== 'string') return null;
  const name = value.replace(/[\\/]/g, '/').split('/').pop().replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return name ? name.slice(0, 255) : null;
}

function detectImageMimeFromBytes(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return 'image/png';
  if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return 'image/webp';
  if (bytes.length >= 12 && bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
    for (let offset = 8; offset + 3 < bytes.length; offset += 4) {
      const brand = String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]).toLowerCase();
      if (['heic', 'heix', 'hevc', 'hevx'].includes(brand)) return 'image/heic';
    }
  }
  return null;
}

/**
 * Offer media only: the real container type of an uploaded file from its
 * leading bytes. Images use the same detector as profile images. Videos are
 * ISO base-media files whose `ftyp` box names a brand; the major brand is
 * authoritative, and compatible brands are consulted only when the major
 * brand is unknown and the file is not a HEIF image. Anything else is null.
 * This proves the container, not the codec inside it.
 */
function detectOfferMediaMimeFromBytes(bytes) {
  if (!isIsoBaseMedia(bytes)) return detectImageMimeFromBytes(bytes);

  const major = brandAt(bytes, 8);
  const byMajor = videoMimeForBrand(major);
  if (byMajor) return byMajor;

  const image = detectImageMimeFromBytes(bytes);
  if (image) return image;

  const boxSize = ((bytes[0] << 24) >>> 0) + (bytes[1] << 16) + (bytes[2] << 8) + bytes[3];
  const end = Math.min(bytes.length, boxSize >= 16 ? boxSize : bytes.length);
  for (let offset = 16; offset + 4 <= end; offset += 4) {
    const byCompatible = videoMimeForBrand(brandAt(bytes, offset));
    if (byCompatible) return byCompatible;
  }
  return null;
}

function isIsoBaseMedia(bytes) {
  return bytes.length >= 12 && bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70;
}

function brandAt(bytes, offset) {
  return String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
}

function videoMimeForBrand(brand) {
  if (MP4_BRANDS.has(brand)) return 'video/mp4';
  if (QUICKTIME_BRANDS.has(brand)) return 'video/quicktime';
  if (THREE_GPP_BRANDS.has(brand)) return 'video/3gpp';
  return null;
}

async function readJson(request) {
  try {
    const body = await request.json();
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('invalid body');
    return body;
  } catch (_) {
    throw new WorkerError('Request body must be a JSON object', 400);
  }
}

function corsResponse(body, status, env, extraHeaders = {}) {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: {
      'Access-Control-Allow-Origin': env.ALLOWED_ORIGIN || '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
  });
}

class WorkerError extends Error {
  // [code] is an optional stable, machine-readable reason the client maps to
  // a localized message; [message] stays diagnostic English.
  constructor(message, status = 400, code = undefined) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
