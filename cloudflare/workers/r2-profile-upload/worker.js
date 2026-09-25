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
 *   POST /account/delete   (see account_deletion.js)
 *
 * Scheduled:
 *   account deletion finalizer (see account_deletion.js)
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
// Offer. Enforced atomically at confirm time by the `offer_media`
// unique (offer_id, role, ordinal) constraint: every Offer item is linked
// under role 'gallery' into one of exactly this many ordinal slots, so two
// concurrent confirms can never both take the last slot.
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
const OFFER_MEDIA_ROLE = 'gallery';
// Offer media only. Profile images keep their own image-only allowlist
// (isAllowedContentType below), which this table deliberately does not touch.
const OFFER_MEDIA_TYPES = {
  'image/jpeg': { extension: 'jpg', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES },
  'image/png': { extension: 'png', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES },
  'image/webp': { extension: 'webp', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES },
  'image/heic': { extension: 'heic', mediaType: 'image', maxBytes: MAX_IMAGE_BYTES },
  'video/mp4': { extension: 'mp4', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES },
  'video/quicktime': { extension: 'mov', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES },
  'video/3gpp': { extension: '3gp', mediaType: 'video', maxBytes: MAX_OFFER_VIDEO_BYTES },
};
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
      if (request.method === 'POST' && path === '/offer-media/authorize') return await handleOfferMediaAuthorize(request, env);
      if (request.method === 'POST' && path === '/offer-media/confirm') return await handleOfferMediaConfirm(request, env);
      if (request.method === 'GET' && path === '/offer-media') return await handleOfferMediaList(request, env);
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
  },
};

async function handleAuthorize(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  await bestEffortCleanupAbandonedPending(userId, env);

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

async function handleOfferMediaAuthorize(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);

  const body = await readJson(request);
  const { offerId, contentType, contentLength, originalFileName } = body;
  if (typeof offerId !== 'string' || !MEDIA_ID_PATTERN.test(offerId)) {
    throw new WorkerError('offerId is required', 400);
  }
  if (!isAllowedOfferContentType(contentType)) {
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

  await assertOwnsOffer(offerId, userId, env);
  await bestEffortCleanupAbandonedPending(userId, env);
  // Early, friendly refusal so a full Offer never transfers a 100 MB upload
  // for nothing. Not the atomic guarantee: that is the ordinal-slot
  // allocation in handleOfferMediaConfirm.
  await assertOfferMediaCapacity(offerId, userId, env);

  const mediaObjectId = crypto.randomUUID();
  const objectKey = offerObjectKey(userId, offerId, mediaObjectId, contentType);
  const insertRes = await supabaseServiceFetch(env, 'POST', '/rest/v1/media_objects', {
    id: mediaObjectId,
    owner_id: userId,
    bucket: env.R2_BUCKET_NAME,
    object_key: objectKey,
    media_type: offerType.mediaType,
    content_type: contentType,
    size_bytes: contentLength,
    original_file_name: sanitizeOriginalFileName(originalFileName),
    status: 'pending_upload',
  });
  if (!insertRes.ok) {
    throw new WorkerError('Failed to create pending media metadata', 502);
  }

  try {
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
      {
        presignedUrl,
        mediaObjectId,
        objectKey,
        mediaType: offerType.mediaType,
        expiresInSeconds: PUT_URL_TTL_SECONDS,
      },
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

async function handleOfferMediaConfirm(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const { offerId, mediaObjectId, role, ordinal } = await readJson(request);
  if (typeof offerId !== 'string' || !MEDIA_ID_PATTERN.test(offerId)) {
    throw new WorkerError('offerId is required', 400);
  }
  if (typeof mediaObjectId !== 'string' || !MEDIA_ID_PATTERN.test(mediaObjectId)) {
    throw new WorkerError('mediaObjectId is required', 400);
  }
  // The client's role/ordinal are no longer trusted: every Offer item is
  // linked as 'gallery' into a server-chosen slot (see linkOfferMediaIntoSlot),
  // which is what makes the per-Offer limit atomic. Accepted and ignored so
  // older clients that still send them keep working.
  void role;
  void ordinal;

  await assertOwnsOffer(offerId, userId, env);

  const row = await loadOwnedMedia(mediaObjectId, userId, env);
  if (row.bucket !== env.R2_BUCKET_NAME || !isExpectedOfferObjectKey(row, userId, offerId)) {
    throw new WorkerError('Media object is not in the configured offer-media location', 409);
  }
  if (row.status === 'ready') {
    // 'ready' is only ever reached below, after the offer_media link already
    // succeeded — see the ordering note further down. A retry that arrives
    // after the client missed the first response is therefore already fully
    // done; nothing further to do.
    return corsResponse({ offerId, mediaObjectId, alreadyConfirmed: true }, 200, env);
  }
  if (row.status !== 'pending_upload') {
    throw new WorkerError(`Unexpected media status: ${row.status}`, 409);
  }

  const r2Object = await env.MEDIA_BUCKET.head(row.object_key);
  if (!r2Object) {
    await rejectInvalidUpload(row, userId, env, 'Object not found in R2');
  }
  const offerType = OFFER_MEDIA_TYPES[row.content_type];
  if (r2Object.size < 1 || r2Object.size > offerType.maxBytes) {
    await rejectInvalidUpload(row, userId, env, 'R2 object size is invalid');
  }

  const signatureObject = await env.MEDIA_BUCKET.get(row.object_key, {
    range: { offset: 0, length: SIGNATURE_BYTES_TO_READ },
  });
  if (!signatureObject) {
    await rejectInvalidUpload(row, userId, env, 'R2 object body not found');
  }
  const signatureBytes = new Uint8Array(await signatureObject.arrayBuffer());
  const detectedContentType = detectOfferMediaMimeFromBytes(signatureBytes);
  const observedContentType = r2Object.httpMetadata?.contentType ?? null;
  if (
    !detectedContentType ||
    detectedContentType !== row.content_type ||
    (observedContentType !== null && observedContentType !== row.content_type)
  ) {
    await rejectInvalidUpload(row, userId, env, 'Uploaded media type does not match authorized metadata');
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

  // Linked to the offer BEFORE being marked ready — deliberately, so that if
  // this insert fails, the media row is still 'pending_upload' and the
  // existing bestEffortDeleteInvalidObjectAndMarkFailed helper's own
  // `status=eq.pending_upload` guard (shared with the profile-image path)
  // still correctly matches it, rather than needing a second, separately
  // guarded cleanup path. A row linked-but-not-yet-ready is invisible to
  // /offer-media (it filters on status='ready'), so this ordering is safe to
  // observe mid-flight, and idempotent to retry: ignoreDuplicates makes a
  // second insert of the same link a no-op.
  await linkOfferMediaIntoSlot(row, offerId, userId, env);

  const markReadyRes = await supabaseServiceFetch(
    env,
    'PATCH',
    `/rest/v1/media_objects?id=eq.${encodeURIComponent(mediaObjectId)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload`,
    {
      status: 'ready',
      size_bytes: r2Object.size,
      content_type: observedContentType || detectedContentType,
      ...(durationMs === null ? {} : { duration_ms: durationMs }),
    },
  );
  if (!markReadyRes.ok) {
    // The link now exists but the row is stuck 'pending_upload'. Not
    // silently reported as success: the client sees this failure and a
    // retry re-enters this same function, re-validates the still-pending
    // row, and safely retries just the mark-ready step (the link insert
    // above is idempotent).
    throw new WorkerError('Failed to mark offer media ready', 502);
  }

  return corsResponse({ offerId, mediaObjectId }, 200, env);
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
 * Links a validated upload to its Offer in the first free ordinal slot, and
 * is the atomic enforcement of MAX_MEDIA_PER_OFFER.
 *
 * Every Offer item is linked as role 'gallery' with an ordinal in
 * [0, MAX_MEDIA_PER_OFFER). The existing `offer_media` unique
 * (offer_id, role, ordinal) constraint lets only one insert own each slot, so
 * however many confirms race, at most MAX_MEDIA_PER_OFFER can succeed: a
 * loser gets 409 (unique violation) and tries the next free slot, and when no
 * slot is left the upload is rejected and cleaned up. No migration and no
 * count-then-insert race.
 *
 * `on_conflict=offer_id,media_id` with ignore-duplicates keeps a retried
 * confirm of an already-linked item idempotent without masking a slot
 * collision, which is a different unique constraint and still raises.
 */
async function linkOfferMediaIntoSlot(row, offerId, userId, env) {
  const linksRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/offer_media?offer_id=eq.${encodeURIComponent(offerId)}&select=media_id,role,ordinal`,
  );
  if (!linksRes.ok) {
    // Leave the row pending: a retry re-enters here safely.
    throw new WorkerError('Failed to read offer media', 502);
  }
  const links = (await linksRes.json()) ?? [];
  if (links.some((link) => link.media_id === row.id)) return;
  if (links.length >= MAX_MEDIA_PER_OFFER) {
    await rejectInvalidUpload(row, userId, env, 'Offer media limit reached', 409, 'offer_media_limit_reached');
  }

  const taken = new Set(
    links.filter((link) => link.role === OFFER_MEDIA_ROLE).map((link) => link.ordinal),
  );
  for (let slot = 0; slot < MAX_MEDIA_PER_OFFER; slot += 1) {
    if (taken.has(slot)) continue;
    const linkRes = await supabaseServiceFetch(
      env,
      'POST',
      '/rest/v1/offer_media?on_conflict=offer_id,media_id',
      { offer_id: offerId, media_id: row.id, role: OFFER_MEDIA_ROLE, ordinal: slot },
      { ignoreDuplicates: true },
    );
    if (linkRes.ok) return;
    if (linkRes.status === 409) continue; // slot won by a concurrent confirm
    await rejectInvalidUpload(row, userId, env, 'Failed to attach media to the offer');
  }
  await rejectInvalidUpload(row, userId, env, 'Offer media limit reached', 409, 'offer_media_limit_reached');
}

/**
 * Refuses an authorize when the Offer already holds, or is currently
 * receiving, MAX_MEDIA_PER_OFFER items. Counts linked items plus this
 * account's still-pending uploads for this Offer that are younger than the
 * abandoned-upload cutoff, so an interrupted upload stops counting once it is
 * old enough to be cleaned up rather than blocking the Offer forever.
 */
async function assertOfferMediaCapacity(offerId, userId, env) {
  const linksRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/offer_media?offer_id=eq.${encodeURIComponent(offerId)}&select=media_id`,
  );
  if (!linksRes.ok) throw new WorkerError('Failed to read offer media', 502);
  const linkedIds = new Set(((await linksRes.json()) ?? []).map((link) => link.media_id));

  const prefix = `profiles/${userId}/offers/${offerId}/`;
  const pendingRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload&object_key=like.${encodeURIComponent(prefix)}*&select=id,created_at`,
  );
  if (!pendingRes.ok) throw new WorkerError('Failed to read pending offer media', 502);
  const cutoff = Date.now() - PENDING_CLEANUP_AGE_MS;
  const pendingInFlight = ((await pendingRes.json()) ?? []).filter((pending) => {
    if (linkedIds.has(pending.id)) return false;
    const createdAt = Date.parse(pending.created_at);
    return Number.isNaN(createdAt) || createdAt > cutoff;
  });

  if (linkedIds.size + pendingInFlight.length >= MAX_MEDIA_PER_OFFER) {
    throw new WorkerError('Offer media limit reached', 409, 'offer_media_limit_reached');
  }
}

async function handleOfferMediaList(request, env) {
  requireConfiguredBucket(env);
  const userId = await verifySupabaseTokenAndGetUserId(request, env);
  const offerId = new URL(request.url).searchParams.get('offerId');
  if (typeof offerId !== 'string' || !MEDIA_ID_PATTERN.test(offerId)) {
    throw new WorkerError('offerId is required', 400);
  }

  await assertOwnsOffer(offerId, userId, env);

  const linksRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/offer_media?offer_id=eq.${encodeURIComponent(offerId)}&select=media_id,role,ordinal,media_objects(id,bucket,object_key,status,content_type)&order=ordinal.asc`,
  );
  if (!linksRes.ok) throw new WorkerError('Failed to read offer media', 502);
  const links = (await linksRes.json()) ?? [];

  const media = [];
  for (const link of links) {
    const object = link.media_objects;
    if (!object || object.status !== 'ready') continue;
    if (object.bucket !== env.R2_BUCKET_NAME || !isExpectedOfferObjectKey(object, userId, offerId)) continue;
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
      url,
    });
  }

  return corsResponse(
    { offerId, media, expiresInSeconds: GET_URL_TTL_SECONDS },
    200,
    env,
    { 'Cache-Control': 'no-store' },
  );
}

async function assertOwnsOffer(offerId, userId, env) {
  const offerRes = await supabaseServiceFetch(
    env,
    'GET',
    `/rest/v1/offers?id=eq.${encodeURIComponent(offerId)}&owner_id=eq.${encodeURIComponent(userId)}&deleted_at=is.null&select=id`,
  );
  if (!offerRes.ok) throw new WorkerError('Failed to verify offer ownership', 502);
  const rows = await offerRes.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    throw new WorkerError('Offer not found or not owned by user', 404);
  }
}

function offerObjectKey(userId, offerId, mediaObjectId, contentType) {
  const extension = OFFER_MEDIA_TYPES[contentType]?.extension;
  // Deliberately nested under the existing profile-image account prefix —
  // see the file header comment for why.
  return `profiles/${userId}/offers/${offerId}/${mediaObjectId}.${extension}`;
}

function isExpectedOfferObjectKey(row, userId, offerId) {
  return isAllowedOfferContentType(row.content_type) && row.object_key === offerObjectKey(userId, offerId, row.id, row.content_type);
}

function isAllowedOfferContentType(contentType) {
  return typeof contentType === 'string' && Object.hasOwn(OFFER_MEDIA_TYPES, contentType);
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
    await supabaseServiceFetch(
      env,
      'PATCH',
      `/rest/v1/media_objects?id=eq.${encodeURIComponent(row.id)}&owner_id=eq.${encodeURIComponent(userId)}&status=eq.pending_upload`,
      { status: 'failed' },
    );
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

async function bestEffortCleanupAbandonedPending(userId, env) {
  try {
    const response = await supabaseServiceFetch(
      env,
      'GET',
      `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}&bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}&status=eq.pending_upload&select=id,object_key,created_at&limit=10&order=created_at.asc`,
    );
    if (!response.ok) return;
    const cutoff = Date.now() - PENDING_CLEANUP_AGE_MS;
    for (const row of (await response.json()) ?? []) {
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
