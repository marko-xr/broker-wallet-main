/**
 * Permanent deletion of a Broker Wallet account, and the server-owned work that
 * must outlive it.
 *
 *   POST /account/delete        handleAccountDeletion    (the account's own request)
 *   scheduled (cron trigger)    runDeletionFinalizer     (no client involved)
 *   POST /authorize             assertUploadsAllowed + assertPresignedWithin
 *
 * Why this lives in the profile-image Worker rather than a Supabase Edge
 * Function: the account's private R2 objects must be removed, and this Worker
 * already holds the `MEDIA_BUCKET` binding and the Supabase server secret. No
 * R2 credential goes to Supabase and no credential of any kind goes to Flutter.
 *
 * AUTHORITY
 *   While the account exists, the account is taken ONLY from the bearer token as
 *   verified by Supabase Auth (`GET /auth/v1/user`). A client-supplied user id is
 *   never used, and one that differs from the verified account is refused.
 *
 *   Once `auth.users` is deleted, that token proves nothing and nothing here
 *   accepts it: a request whose token Supabase Auth rejects gets
 *   `session_expired` and no cleanup of any kind. All remaining work is driven
 *   by the `account_deletion_jobs` row, created from the verified id before the
 *   account was deleted and readable only with the server secret. The R2 prefix
 *   is derived from that row, so a retry or a finalizer run can only ever reach
 *   `profiles/<that id>/`.
 *
 * ORDER (POST /account/delete)
 *   1. verify token; refuse a mismatched body id or a recovery session
 *   2. re-verify the password server-side (the device session is untouched)
 *   3. claim the job row (status `quarantined`) -> /authorize stops signing
 *   4. inventory media by `owner_id` = verified id plus the R2 prefix; refuse
 *      unknown locations; delete; prove the prefix empty
 *   5. job -> `auth_delete_pending` (compare-and-set), then Supabase Auth admin
 *      delete; an ambiguous result is resolved by reading the user back
 *   6. job -> `auth_deleted`: this bucket's existing job is advanced by
 *      compare-and-set; if the job is absent (abandoned meanwhile) it is
 *      recreated with a conflict-ignoring insert; another bucket's job is never
 *      merge-overwritten. Then a best-effort immediate prefix sweep
 *   Any failure before 5 cancels the job, so an account that was not deleted
 *   is never left unable to upload.
 *
 * SIGNED PUT RACE
 *   Maximum signed PUT lifetime: /authorize reads the clock (t0), checks for a
 *   job, signs, and refuses a URL whose X-Amz-Date is later than
 *   t0 + MAX_SIGNING_DELAY_MS (60 s). With X-Amz-Expires = 300 s, every issued
 *   URL is dead by t0 + 360 s.
 *
 *   A check that found no job ran before the job was committed, and the job
 *   was committed before its status became `auth_deleted`. The finalizer stamps
 *   `cleanup_not_before` = (its own clock when it first reads that
 *   `auth_deleted` row) + 360 s + FINALIZER_SAFETY_MARGIN_MS (120 s), and
 *   sweeps only after that. The stamp is read after the row was committed, so it
 *   is later than every t0 the quarantine could have missed. Each quantity is
 *   read on a Cloudflare clock (the signing isolate, R2's validation, the cron
 *   isolate). No Postgres clock takes part in the guarantee, and the 120 s
 *   margin covers clock difference inside Cloudflare's NTP-synchronised fleet,
 *   which Cloudflare does not publish a bound for. The sweep is idempotent, and
 *   a job is deleted only after its prefix has been proven empty at or after
 *   `cleanup_not_before`.
 *
 * SECRET KEY
 *   The Supabase secret key (`sb_secret_...`) is sent only in the `apikey`
 *   header, and only on server-to-Supabase calls. It is never placed in an
 *   Authorization header. A user's JWT travels only as `Authorization: Bearer`,
 *   paired with the publishable key.
 *
 * Responses carry only fixed error codes. Nothing here logs a token, password,
 * email, user id, object key, signed URL or error object.
 */

export const ACCOUNT_DELETE_PATH = '/account/delete';

const JOBS_PATH = '/rest/v1/account_deletion_jobs';
const PROFILE_OBJECT_PREFIX = 'profiles/';
const INVENTORY_PAGE_SIZE = 500;
const INVENTORY_MAX_PAGES = 200;
const R2_LIST_LIMIT = 1000;
const R2_DELETE_BATCH = 1000;
const MAX_PASSWORD_LENGTH = 1024;
const FINALIZER_BATCH = 25;
const JOB_WRITE_ATTEMPTS = 3;
const USER_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CLIENT_USER_ID_FIELDS = ['userId', 'user_id', 'uid', 'id'];

/** X-Amz-Expires of every signed profile-image PUT URL. worker.js uses this. */
export const SIGNED_PUT_TTL_SECONDS = 300;

/** Bound between the /authorize quarantine check and the signature date. */
export const MAX_SIGNING_DELAY_MS = 60 * 1000;

/** Finalization waits this long beyond the latest possible PUT URL expiry. */
export const FINALIZER_SAFETY_MARGIN_MS = 120 * 1000;

/** Stamp-to-sweep delay: longest PUT URL life plus the safety margin (480 s). */
export const CLEANUP_WINDOW_MS = SIGNED_PUT_TTL_SECONDS * 1000 + MAX_SIGNING_DELAY_MS + FINALIZER_SAFETY_MARGIN_MS;

/**
 * An `auth_delete_pending` or `quarantined` job this old, whose account still
 * exists, belongs to a request that died; it is cancelled so the account can
 * upload again. Far beyond any real request duration.
 */
export const ABANDONED_JOB_AFTER_MS = 60 * 60 * 1000;

/** An `auth_delete_pending` job this old is reconciled against Supabase Auth. */
export const PENDING_RECONCILE_AFTER_MS = 15 * 60 * 1000;

export const JobStatus = Object.freeze({
  quarantined: 'quarantined',
  authDeletePending: 'auth_delete_pending',
  authDeleted: 'auth_deleted',
  cleanupFailed: 'cleanup_failed',
});

/** Fixed error codes returned to the app. The app maps each one to UI copy. */
export const DeletionErrorCode = Object.freeze({
  sessionExpired: 'session_expired',
  accountMismatch: 'account_mismatch',
  recoverySession: 'recovery_session',
  invalidRequest: 'invalid_request',
  reauthenticationFailed: 'reauthentication_failed',
  reauthenticationUnsupported: 'reauthentication_unsupported',
  rateLimited: 'rate_limited',
  deletionInProgress: 'deletion_in_progress',
  deletionPending: 'deletion_pending',
  mediaCleanupFailed: 'media_cleanup_failed',
  serverDeleteFailed: 'server_delete_failed',
  serviceUnavailable: 'service_unavailable',
  unknown: 'unknown',
});

export class AccountDeletionError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

// ===========================================================================
// POST /account/delete
// ===========================================================================

/**
 * Handles the request and always resolves to a Response; it never rejects, so
 * the caller can hand the same promise to `ctx.waitUntil`.
 */
export async function handleAccountDeletion(request, env, { respond, fetchImpl = fetch, now = () => new Date() }) {
  try {
    const result = await deleteCallingAccount(request, env, fetchImpl, now);
    return respond(result, 200, env, { 'Cache-Control': 'no-store' });
  } catch (error) {
    if (error instanceof AccountDeletionError) {
      console.error('[account-delete] refused', error.code);
      return respond({ error: error.code }, error.status, env, { 'Cache-Control': 'no-store' });
    }
    console.error('[account-delete] unexpected failure');
    return respond({ error: DeletionErrorCode.unknown }, 500, env, { 'Cache-Control': 'no-store' });
  }
}

async function deleteCallingAccount(request, env, fetchImpl, now) {
  requireDeletionConfiguration(env);

  const authorization = request.headers.get('Authorization') || '';
  if (!authorization.startsWith('Bearer ') || authorization.length <= 'Bearer '.length) {
    throw new AccountDeletionError(DeletionErrorCode.sessionExpired, 401);
  }

  const identity = await loadVerifiedIdentity(authorization, env, fetchImpl);
  const userId = identity.id;

  const body = await readDeletionBody(request);
  for (const field of CLIENT_USER_ID_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(body, field) && body[field] !== userId) {
      throw new AccountDeletionError(DeletionErrorCode.accountMismatch, 403);
    }
  }

  if (tokenCarriesRecoveryMethod(authorization)) {
    throw new AccountDeletionError(DeletionErrorCode.recoverySession, 403);
  }

  await verifyAccountPassword(identity, body.password, env, fetchImpl);

  await claimDeletionJob(userId, env, fetchImpl);

  let mediaObjectsRemoved;
  try {
    mediaObjectsRemoved = await removeAccountMedia(userId, env, fetchImpl, now);
  } catch (error) {
    await cancelJob(userId, [JobStatus.quarantined], env, fetchImpl);
    throw error;
  }

  const advanced = await compareAndSetJob(
    userId,
    [JobStatus.quarantined],
    { status: JobStatus.authDeletePending },
    env,
    fetchImpl,
  );
  if (!advanced) {
    // Another request advanced or cancelled this job while ours ran.
    throw new AccountDeletionError(DeletionErrorCode.deletionInProgress, 409);
  }

  const authState = await deleteAuthUser(userId, env, fetchImpl);
  if (authState === 'exists') {
    await cancelJob(userId, [JobStatus.authDeletePending], env, fetchImpl);
    throw new AccountDeletionError(DeletionErrorCode.serverDeleteFailed, 502);
  }
  if (authState === 'unknown') {
    // The job stays `auth_delete_pending`; the finalizer resolves it.
    throw new AccountDeletionError(DeletionErrorCode.deletionPending, 503);
  }

  const recorded = await recordAuthDeleted(userId, env, fetchImpl, now);
  if (!recorded) console.error('[account-delete] job record failed');
  await sweepAccountPrefix(userId, env);

  return { status: 'deleted', mediaObjectsRemoved };
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/**
 * Supabase Auth's verdict on the token. Every rejection is `session_expired`:
 * a deleted account's token is not evidence of anything, so it is never
 * decoded here to pick an account to act on.
 */
export async function loadVerifiedIdentity(authorization, env, fetchImpl) {
  let response;
  try {
    response = await fetchImpl(`${env.SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: authorization },
    });
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }

  if (response.ok) {
    const user = await readJsonOrNull(response);
    if (!user || typeof user.id !== 'string' || !USER_ID_PATTERN.test(user.id)) {
      throw new AccountDeletionError(DeletionErrorCode.sessionExpired, 401);
    }
    return user;
  }
  if (response.status >= 500) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
  throw new AccountDeletionError(DeletionErrorCode.sessionExpired, 401);
}

/**
 * Reads the `amr` claim of a token Supabase Auth has just accepted for an
 * existing account. Used only to REFUSE a password-recovery session.
 */
export function tokenCarriesRecoveryMethod(authorization) {
  const claims = decodeTokenClaims(authorization);
  const amr = Array.isArray(claims?.amr) ? claims.amr : [];
  return amr.some((entry) => entry === 'recovery' || entry?.method === 'recovery');
}

function decodeTokenClaims(authorization) {
  try {
    const token = authorization.slice('Bearer '.length);
    const payload = token.split('.')[1];
    if (!payload) return null;
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
    return JSON.parse(atob(padded));
  } catch (_) {
    return null;
  }
}

async function readDeletionBody(request) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.invalidRequest, 400);
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AccountDeletionError(DeletionErrorCode.invalidRequest, 400);
  }
  return body;
}

// ---------------------------------------------------------------------------
// Reauthentication
// ---------------------------------------------------------------------------

/**
 * Re-verifies the account password against the verified account's email.
 * Google, Apple and phone accounts need their own confirmation here before
 * they ship; until then they are refused rather than waved through.
 */
export async function verifyAccountPassword(identity, password, env, fetchImpl) {
  const email = typeof identity.email === 'string' ? identity.email.trim() : '';
  const identities = Array.isArray(identity.identities) ? identity.identities : [];
  const hasEmailIdentity = identities.some((entry) => entry?.provider === 'email');
  if (!email || !hasEmailIdentity) {
    throw new AccountDeletionError(DeletionErrorCode.reauthenticationUnsupported, 409);
  }
  if (typeof password !== 'string' || password.length === 0 || password.length > MAX_PASSWORD_LENGTH) {
    throw new AccountDeletionError(DeletionErrorCode.reauthenticationFailed, 403);
  }

  let response;
  try {
    response = await fetchImpl(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }

  if (response.status === 429) {
    throw new AccountDeletionError(DeletionErrorCode.rateLimited, 429);
  }
  if (response.status >= 500) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
  if (!response.ok) {
    throw new AccountDeletionError(DeletionErrorCode.reauthenticationFailed, 403);
  }

  const session = await readJsonOrNull(response);
  await bestEffortRevokeSession(session?.access_token, env, fetchImpl);
  if (session?.user?.id !== identity.id) {
    throw new AccountDeletionError(DeletionErrorCode.accountMismatch, 403);
  }
}

async function bestEffortRevokeSession(accessToken, env, fetchImpl) {
  if (typeof accessToken !== 'string' || !accessToken) return;
  try {
    await fetchImpl(`${env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${accessToken}` },
    });
  } catch (_) {
    // Deleting the account removes every session it has.
  }
}

// ---------------------------------------------------------------------------
// Deletion job
// ---------------------------------------------------------------------------

// JOB OWNERSHIP
//   `user_id` is the one-account primary key, shared by every Worker that uses
//   this Supabase project (production and staging). A job may be mutated only
//   by the Worker whose `R2_BUCKET_NAME` equals the job's `bucket`: every
//   compare-and-set, cancellation and recreation below filters on it, and a job
//   owned by another bucket is refused, never reused, advanced, cancelled or
//   overwritten. Reading is different: `assertUploadsAllowed` blocks uploads
//   when a job exists in ANY bucket, because any deletion in progress must stop
//   new uploads for the account.

function ownBucketFilter(env) {
  return `bucket=eq.${encodeURIComponent(env.R2_BUCKET_NAME)}`;
}

/**
 * Creates the `quarantined` job, or reuses a `quarantined` one this Worker's
 * bucket left from an earlier attempt. A job in another bucket, or in any later
 * status, means another deletion owns this account: the request is refused
 * before anything is deleted.
 */
async function claimDeletionJob(userId, env, fetchImpl) {
  let inserted;
  try {
    inserted = await supabaseSecretFetch(
      env,
      fetchImpl,
      'POST',
      `${JOBS_PATH}?on_conflict=user_id`,
      { user_id: userId, bucket: env.R2_BUCKET_NAME, status: JobStatus.quarantined },
      'resolution=ignore-duplicates,return=representation',
    );
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
  if (!inserted.ok) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
  const rows = await readJsonOrNull(inserted);
  if (Array.isArray(rows) && rows.length === 1) return;

  const existing = await loadJob(userId, env, fetchImpl);
  if (!existing) throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  if (existing.bucket !== env.R2_BUCKET_NAME) {
    console.error('[account-delete] job owned by another bucket');
    throw new AccountDeletionError(DeletionErrorCode.deletionInProgress, 409);
  }
  if (existing.status === JobStatus.quarantined) return;
  throw new AccountDeletionError(DeletionErrorCode.deletionInProgress, 409);
}

/** Reads the job for [userId] in ANY bucket, including its owning bucket. */
async function loadJob(userId, env, fetchImpl) {
  try {
    const response = await supabaseSecretFetch(
      env,
      fetchImpl,
      'GET',
      `${JOBS_PATH}?user_id=eq.${encodeURIComponent(userId)}&select=user_id,bucket,status`,
    );
    if (!response.ok) throw new Error('job read failed');
    const rows = await readJsonOrNull(response);
    if (!Array.isArray(rows)) throw new Error('job read failed');
    return rows[0] ?? null;
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
}

/** Updates this bucket's job only if it is still in one of [fromStatuses]. */
async function compareAndSetJob(userId, fromStatuses, patch, env, fetchImpl) {
  try {
    const response = await supabaseSecretFetch(
      env,
      fetchImpl,
      'PATCH',
      `${JOBS_PATH}?user_id=eq.${encodeURIComponent(userId)}&${ownBucketFilter(env)}&status=${statusFilter(fromStatuses)}`,
      patch,
      'return=representation',
    );
    if (!response.ok) return false;
    const rows = await readJsonOrNull(response);
    return Array.isArray(rows) && rows.length === 1;
  } catch (_) {
    return false;
  }
}

/** Deletes this bucket's job only if it is still in one of [fromStatuses]. */
async function cancelJob(userId, fromStatuses, env, fetchImpl) {
  try {
    const response = await supabaseSecretFetch(
      env,
      fetchImpl,
      'DELETE',
      `${JOBS_PATH}?user_id=eq.${encodeURIComponent(userId)}&${ownBucketFilter(env)}&status=${statusFilter(fromStatuses)}`,
    );
    return response.ok;
  } catch (_) {
    console.error('[account-delete] job cancel failed');
    return false;
  }
}

/**
 * Records that the auth user is gone, without ever writing another bucket's
 * job.
 *
 *   1. Advance this bucket's job (normally `auth_delete_pending`) to
 *      `auth_deleted` by compare-and-set.
 *   2. If nothing matched, read the job:
 *        - this bucket's job is already `auth_deleted` / `cleanup_failed`
 *          (the finalizer reconciled it first) -> done;
 *        - another bucket owns the uid -> leave it untouched and fail;
 *        - no job at all (the finalizer abandoned it while the admin delete was
 *          stalled) -> recreate it with a plain INSERT that ignores conflicts.
 *   3. An insert that loses a race to a concurrent row is re-read on the next
 *      attempt, so a row another bucket inserted is never overwritten.
 *
 * A recreated row's `cleanup_not_before` is stamped by the finalizer only after
 * this insert is committed, so it still lies after any URL issued while the
 * account was briefly unquarantined.
 */
async function recordAuthDeleted(userId, env, fetchImpl, now) {
  const deletedAt = now().toISOString();
  for (let attempt = 0; attempt < JOB_WRITE_ATTEMPTS; attempt += 1) {
    try {
      if (
        await compareAndSetJob(
          userId,
          [JobStatus.authDeletePending, JobStatus.quarantined],
          { status: JobStatus.authDeleted, auth_deleted_at: deletedAt },
          env,
          fetchImpl,
        )
      ) {
        return true;
      }

      const existing = await loadJob(userId, env, fetchImpl);
      if (existing) {
        if (existing.bucket !== env.R2_BUCKET_NAME) {
          console.error('[account-delete] job owned by another bucket');
          return false;
        }
        if (existing.status === JobStatus.authDeleted || existing.status === JobStatus.cleanupFailed) {
          return true;
        }
        continue;
      }

      const inserted = await supabaseSecretFetch(
        env,
        fetchImpl,
        'POST',
        `${JOBS_PATH}?on_conflict=user_id`,
        {
          user_id: userId,
          bucket: env.R2_BUCKET_NAME,
          status: JobStatus.authDeleted,
          auth_deleted_at: deletedAt,
        },
        'resolution=ignore-duplicates,return=representation',
      );
      if (inserted.ok) {
        const rows = await readJsonOrNull(inserted);
        if (Array.isArray(rows) && rows.length === 1) return true;
      }
    } catch (_) {
      // Retried below.
    }
  }
  return false;
}

function statusFilter(statuses) {
  return statuses.length === 1 ? `eq.${statuses[0]}` : `in.(${statuses.join(',')})`;
}

// ---------------------------------------------------------------------------
// Upload quarantine (used by POST /authorize)
// ---------------------------------------------------------------------------

/**
 * Refuses to authorize an upload while any deletion job exists for the
 * account. Fails closed: if the job table cannot be read, no URL is issued.
 */
export async function assertUploadsAllowed(userId, env, fetchImpl = fetch) {
  const job = await loadJob(userId, env, fetchImpl);
  if (job) {
    throw new AccountDeletionError(DeletionErrorCode.deletionInProgress, 409);
  }
}

/**
 * Refuses a presigned URL whose signature date is later than [notAfterMs].
 * This bounds every issued URL's expiry independently of how the signer picks
 * its date.
 */
export function assertPresignedWithin(presignedUrl, notAfterMs) {
  const signedAt = presignedSignatureTime(presignedUrl);
  if (signedAt === null || signedAt > notAfterMs) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
}

export function presignedSignatureTime(presignedUrl) {
  try {
    const value = new URL(presignedUrl).searchParams.get('X-Amz-Date') ?? '';
    const match = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(value);
    if (!match) return null;
    const [, y, mo, d, h, mi, s] = match.map(Number);
    return Date.UTC(y, mo - 1, d, h, mi, s);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// R2 cleanup
// ---------------------------------------------------------------------------

export function accountObjectPrefix(userId) {
  return `${PROFILE_OBJECT_PREFIX}${userId}/`;
}

/**
 * Removes every R2 object the account owns and proves none remain.
 *
 * The inventory is the union of the account's `media_objects` rows and its own
 * R2 prefix, both derived from the verified id. A row pointing anywhere else —
 * another bucket, or a key outside the account's prefix — is media this Worker
 * does not know how to clean, so deletion stops rather than orphan it.
 */
export async function removeAccountMedia(userId, env, fetchImpl, now) {
  const prefix = accountObjectPrefix(userId);
  const rows = await loadAccountMediaRows(userId, env, fetchImpl);

  for (const row of rows) {
    if (row.bucket !== env.R2_BUCKET_NAME || typeof row.object_key !== 'string' || !row.object_key.startsWith(prefix)) {
      console.error('[account-delete] media outside the account prefix');
      throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
    }
  }

  const keys = new Set(rows.map((row) => row.object_key));
  try {
    for (const key of await listPrefix(env, prefix)) keys.add(key);
    await deleteKeys(env, [...keys]);
    await assertPrefixEmpty(env, prefix);
  } catch (_) {
    throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
  }

  if (rows.length > 0) {
    await bestEffortMarkMediaDeleted(userId, env, fetchImpl, now);
  }
  return keys.size;
}

async function loadAccountMediaRows(userId, env, fetchImpl) {
  const rows = [];
  for (let page = 0; page < INVENTORY_MAX_PAGES; page += 1) {
    const offset = page * INVENTORY_PAGE_SIZE;
    let response;
    try {
      response = await supabaseSecretFetch(
        env,
        fetchImpl,
        'GET',
        `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}&select=id,bucket,object_key,status&order=id.asc&limit=${INVENTORY_PAGE_SIZE}&offset=${offset}`,
      );
    } catch (_) {
      throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
    }
    if (!response.ok) {
      throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
    }
    const batch = await readJsonOrNull(response);
    if (!Array.isArray(batch)) {
      throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
    }
    rows.push(...batch);
    if (batch.length < INVENTORY_PAGE_SIZE) return rows;
  }
  throw new AccountDeletionError(DeletionErrorCode.mediaCleanupFailed, 502);
}

async function listPrefix(env, prefix) {
  const keys = [];
  let cursor;
  do {
    const listing = await env.MEDIA_BUCKET.list({ prefix, cursor, limit: R2_LIST_LIMIT });
    for (const object of listing.objects ?? []) keys.push(object.key);
    cursor = listing.truncated ? listing.cursor : undefined;
  } while (cursor);
  return keys;
}

async function deleteKeys(env, keys) {
  for (let index = 0; index < keys.length; index += R2_DELETE_BATCH) {
    // R2 deletes are idempotent: a key that is already gone is not an error.
    await env.MEDIA_BUCKET.delete(keys.slice(index, index + R2_DELETE_BATCH));
  }
}

/** Deletes whatever is listed under [prefix], twice if needed, and throws if anything remains. */
async function assertPrefixEmpty(env, prefix) {
  let remaining = await listPrefix(env, prefix);
  if (remaining.length > 0) {
    await deleteKeys(env, remaining);
    remaining = await listPrefix(env, prefix);
  }
  if (remaining.length > 0) throw new Error('objects remain');
}

async function bestEffortMarkMediaDeleted(userId, env, fetchImpl, now) {
  try {
    const response = await supabaseSecretFetch(
      env,
      fetchImpl,
      'PATCH',
      `/rest/v1/media_objects?owner_id=eq.${encodeURIComponent(userId)}`,
      { status: 'deleted', deleted_at: now().toISOString() },
    );
    if (!response.ok) console.error('[account-delete] media status update failed');
  } catch (_) {
    console.error('[account-delete] media status update failed');
  }
}

async function sweepAccountPrefix(userId, env) {
  try {
    const prefix = accountObjectPrefix(userId);
    const keys = await listPrefix(env, prefix);
    if (keys.length > 0) await deleteKeys(env, keys);
  } catch (_) {
    console.error('[account-delete] immediate prefix sweep failed');
  }
}

// ---------------------------------------------------------------------------
// Auth deletion
// ---------------------------------------------------------------------------

/**
 * Permanently deletes `auth.users`; `public.profiles` and everything owned
 * through it follow by `ON DELETE CASCADE`.
 *
 * Returns 'deleted', 'exists' or 'unknown'. Anything other than a clean success
 * is settled by reading the user back, never assumed.
 */
export async function deleteAuthUser(userId, env, fetchImpl) {
  try {
    const response = await fetchImpl(`${env.SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
      method: 'DELETE',
      headers: adminHeaders(env),
      body: JSON.stringify({ should_soft_delete: false }),
    });
    if (response.ok || response.status === 404) return 'deleted';
  } catch (_) {
    // Settled below.
  }
  return readAuthUserState(userId, env, fetchImpl);
}

export async function readAuthUserState(userId, env, fetchImpl) {
  try {
    const response = await fetchImpl(`${env.SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
      method: 'GET',
      headers: adminHeaders(env),
    });
    if (response.status === 404) return 'deleted';
    if (response.ok) {
      const user = await readJsonOrNull(response);
      return user?.id === userId ? 'exists' : 'unknown';
    }
  } catch (_) {
    // Unknown.
  }
  return 'unknown';
}

/** The secret key goes in `apikey` only; see SECRET KEY above. */
function adminHeaders(env) {
  return {
    apikey: env.SUPABASE_SECRET_KEY,
    'Content-Type': 'application/json',
  };
}

// ===========================================================================
// Scheduled finalizer
// ===========================================================================

/**
 * Finishes what an account's own request could not. Runs from the Worker's
 * cron trigger with the server secret only; no client, token or client id is
 * involved, and every account it touches comes from a job row in THIS Worker's
 * bucket, so a staging Worker and the production Worker never finalize each
 * other's jobs.
 *
 *   1. `auth_deleted` / `cleanup_failed` past `cleanup_not_before`: sweep the
 *      prefix, prove it empty, delete the job. On failure -> `cleanup_failed`.
 *   2. `auth_deleted` / `cleanup_failed` not yet stamped: stamp
 *      `cleanup_not_before` = now + CLEANUP_WINDOW_MS (never finalized in the
 *      same run).
 *   3. `auth_delete_pending` older than 15 minutes: read the user back.
 *      Gone -> `auth_deleted` (stamped on a later run). Still there and older
 *      than 60 minutes -> cancel.
 *   4. `quarantined` older than 60 minutes: gone -> `auth_deleted` (deleted by
 *      other means, so its prefix still needs finalizing); still there ->
 *      cancel.
 *
 * Never rejects.
 */
export async function runDeletionFinalizer(env, { fetchImpl = fetch, now = () => new Date() } = {}) {
  const summary = { finalized: 0, cleanupFailed: 0, stamped: 0, reconciled: 0, cancelled: 0 };
  try {
    requireDeletionConfiguration(env);
    const at = now();
    const ours = ownBucketFilter(env);
    const deletedStatuses = `status=in.(${JobStatus.authDeleted},${JobStatus.cleanupFailed})`;

    for (const job of await listJobs(
      env,
      fetchImpl,
      `${ours}&${deletedStatuses}&cleanup_not_before=lte.${at.toISOString()}&order=cleanup_not_before.asc`,
    )) {
      if (!isUserId(job.user_id)) continue;
      try {
        await assertPrefixEmpty(env, accountObjectPrefix(job.user_id));
        if (await cancelJob(job.user_id, [JobStatus.authDeleted, JobStatus.cleanupFailed], env, fetchImpl)) {
          summary.finalized += 1;
        }
      } catch (_) {
        summary.cleanupFailed += 1;
        console.error('[account-delete] finalization failed');
        await compareAndSetJob(
          job.user_id,
          [JobStatus.authDeleted, JobStatus.cleanupFailed],
          {
            status: JobStatus.cleanupFailed,
            cleanup_attempts: (Number.isInteger(job.cleanup_attempts) ? job.cleanup_attempts : 0) + 1,
            last_error_code: DeletionErrorCode.mediaCleanupFailed,
          },
          env,
          fetchImpl,
        );
      }
    }

    const unstamped = await listJobs(env, fetchImpl, `${ours}&${deletedStatuses}&cleanup_not_before=is.null`);
    // Read AFTER the listing returned: every listed row was committed before
    // this moment, which is what makes the stamp later than any t0 the
    // quarantine could have missed. A clock read before the listing would not be.
    const stampValue = new Date(now().getTime() + CLEANUP_WINDOW_MS).toISOString();
    for (const job of unstamped) {
      if (!isUserId(job.user_id)) continue;
      try {
        const response = await supabaseSecretFetch(
          env,
          fetchImpl,
          'PATCH',
          `${JOBS_PATH}?user_id=eq.${encodeURIComponent(job.user_id)}&${ownBucketFilter(env)}&cleanup_not_before=is.null`,
          { cleanup_not_before: stampValue },
          'return=representation',
        );
        const rows = response.ok ? await readJsonOrNull(response) : null;
        if (Array.isArray(rows) && rows.length === 1) summary.stamped += 1;
      } catch (_) {
        console.error('[account-delete] cleanup stamp failed');
      }
    }

    const pendingCutoff = new Date(at.getTime() - PENDING_RECONCILE_AFTER_MS).toISOString();
    const abandonedCutoff = at.getTime() - ABANDONED_JOB_AFTER_MS;
    for (const job of await listJobs(
      env,
      fetchImpl,
      `${ours}&status=in.(${JobStatus.authDeletePending},${JobStatus.quarantined})&updated_at=lte.${pendingCutoff}&order=updated_at.asc`,
    )) {
      if (!isUserId(job.user_id)) continue;
      const updatedAt = Date.parse(job.updated_at);
      const abandoned = !Number.isNaN(updatedAt) && updatedAt <= abandonedCutoff;
      if (job.status === JobStatus.quarantined && !abandoned) continue;

      const state = await readAuthUserState(job.user_id, env, fetchImpl);
      if (state === 'deleted') {
        if (
          await compareAndSetJob(
            job.user_id,
            [job.status],
            { status: JobStatus.authDeleted, auth_deleted_at: at.toISOString() },
            env,
            fetchImpl,
          )
        ) {
          summary.reconciled += 1;
        }
      } else if (state === 'exists' && abandoned) {
        if (await cancelJob(job.user_id, [job.status], env, fetchImpl)) summary.cancelled += 1;
      }
    }
  } catch (_) {
    console.error('[account-delete] finalizer run failed');
  }
  return summary;
}

async function listJobs(env, fetchImpl, filter) {
  const response = await supabaseSecretFetch(
    env,
    fetchImpl,
    'GET',
    `${JOBS_PATH}?${filter}&select=user_id,status,updated_at,cleanup_attempts&limit=${FINALIZER_BATCH}`,
  );
  if (!response.ok) throw new Error('job list failed');
  const rows = await readJsonOrNull(response);
  return Array.isArray(rows) ? rows : [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isUserId(value) {
  return typeof value === 'string' && USER_ID_PATTERN.test(value);
}

function requireDeletionConfiguration(env) {
  if (
    !env.SUPABASE_URL ||
    !env.SUPABASE_PUBLISHABLE_KEY ||
    !env.SUPABASE_SECRET_KEY ||
    !env.R2_BUCKET_NAME ||
    !env.MEDIA_BUCKET
  ) {
    throw new AccountDeletionError(DeletionErrorCode.serviceUnavailable, 503);
  }
}

function supabaseSecretFetch(env, fetchImpl, method, path, body, prefer = 'return=minimal') {
  return fetchImpl(`${env.SUPABASE_URL}${path}`, {
    method,
    headers: {
      apikey: env.SUPABASE_SECRET_KEY,
      'Content-Type': 'application/json',
      Prefer: prefer,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function readJsonOrNull(response) {
  try {
    return await response.json();
  } catch (_) {
    return null;
  }
}
