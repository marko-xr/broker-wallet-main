import { AwsClient } from 'aws4fetch';

/**
 * Private profile-image lifecycle worker.
 *
 * Public endpoints:
 *   POST /authorize
 *   POST /confirm
 *   GET  /profile-image-url
 */

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const PUT_URL_TTL_SECONDS = 300;
const GET_URL_TTL_SECONDS = 900;
const PENDING_CLEANUP_AGE_MS = 24 * 60 * 60 * 1000;
const SIGNATURE_BYTES_TO_READ = 64;
const MEDIA_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return corsResponse(null, 204, env);

    const path = new URL(request.url).pathname;
    try {
      if (request.method === 'POST' && path === '/authorize') return await handleAuthorize(request, env);
      if (request.method === 'POST' && path === '/confirm') return await handleConfirm(request, env);
      if (request.method === 'GET' && path === '/profile-image-url') return await handleProfileImageUrl(request, env);
      return corsResponse({ error: 'Not found' }, 404, env);
    } catch (error) {
      console.error('[r2-profile-upload] request failed', error);
      return corsResponse(
        { error: error instanceof WorkerError ? error.message : 'Internal error' },
        error instanceof WorkerError ? error.status : 500,
        env,
      );
    }
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
    const presignedUrl = await createPresignedR2Url({
      env,
      method: 'PUT',
      objectKey,
      contentType,
      expiresInSeconds: PUT_URL_TTL_SECONDS,
    });
    return corsResponse(
      { presignedUrl, mediaObjectId, objectKey, expiresInSeconds: PUT_URL_TTL_SECONDS },
      200,
      env,
      { 'Cache-Control': 'no-store' },
    );
  } catch (error) {
    await bestEffortDeletePendingMedia(mediaObjectId, userId, env);
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
  const headers = {
    apikey: env.SUPABASE_SECRET_KEY,
    'Content-Type': 'application/json',
    Prefer: options.preferRepresentation ? 'return=representation' : 'return=minimal',
  };
  return fetch(`${env.SUPABASE_URL}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function rejectInvalidUpload(row, userId, env, reason) {
  await bestEffortDeleteInvalidObjectAndMarkFailed(row, userId, env);
  throw new WorkerError(reason, 422);
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
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}
