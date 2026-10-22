// Test doubles for the Toolkit document routes: an in-memory R2 bucket and an
// in-memory Supabase that answers the Worker's auth, session, deletion-job and
// Toolkit RPC calls. The RPC model mirrors supabase/migrations/
// 20261019100000_toolkit_cloud_documents.sql outcome for outcome; the real SQL is
// exercised separately by supabase/tests/toolkit_documents_test.sql.
import assert from 'node:assert/strict';

export const ALICE = '11111111-1111-4111-8111-111111111111';
export const BOB = '22222222-2222-4222-8222-222222222222';
export const BUCKET = 'broker-wallet-media-staging';
export const SUPABASE_URL = 'https://project.supabase.test';
export const SECRET = 'test-service-key';
export const DOC_1 = 'd0c00001-0000-4000-8000-000000000001';
export const DOC_2 = 'd0c00002-0000-4000-8000-000000000002';
export const DOC_3 = 'd0c00003-0000-4000-8000-000000000003';

import { createHash } from 'node:crypto';

export function jpegBytes(extra = 64) {
  return Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, ...new Array(extra).fill(0x11), 0xff, 0xd9]);
}

export function pngBytes(extra = 64) {
  const ihdr = [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 16, 0, 0, 0, 16, 8, 2, 0, 0, 0, 0, 0, 0, 0];
  return Uint8Array.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...ihdr,
    ...new Array(extra + 30).fill(0x22),
    0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);
}

export function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function pdfBytes(extra = 64) {
  const body = new TextEncoder().encode('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n' + 'x'.repeat(extra) + '\n%%EOF\n');
  return body;
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}

export class FakeBucket {
  objects = new Map();
  failDeleteKey = null;
  deleted = [];
  put(key, bytes, contentType = 'application/pdf', etag = `"etag-${this.objects.size + 1}"`) {
    this.objects.set(key, { bytes, contentType, etag });
  }
  async head(key) {
    const value = this.objects.get(key);
    return value ? { size: value.bytes.length, etag: value.etag, httpMetadata: { contentType: value.contentType } } : null;
  }
  // Hook for race tests: runs at the start of every read (ranged or not).
  onGet = null;
  async get(key, { range } = {}) {
    await this.onGet?.(key);
    const value = this.objects.get(key);
    if (!value) return null;
    const bytes = range ? value.bytes.slice(range.offset, range.offset + range.length) : value.bytes;
    return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
  }
  // Hook for race tests: runs just before a delete takes effect.
  beforeDelete = null;
  /**
   * MODEL of a presigned PUT against R2, NOT R2: it implements what Cloudflare documents
   * (conditional PutObject headers evaluated atomically against committed state; 412 on
   * `If-None-Match: *` when the key exists) and what SigV4 requires (every header listed in
   * X-Amz-SignedHeaders must be sent). Whether R2 honors a conditional header on a PRESIGNED PUT
   * is not stated in its documentation and is therefore a staging proof, not something this proves.
   */
  putViaSignedUrl(signedUrl, { headers = {}, bytes, contentType = 'application/pdf' }) {
    const url = new URL(signedUrl);
    const signed = (url.searchParams.get('X-Amz-SignedHeaders') ?? '').split(';').filter(Boolean);
    const sent = Object.fromEntries(Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value]));
    for (const name of signed) {
      if (name !== 'host' && sent[name] === undefined) return { status: 403, code: 'SignatureDoesNotMatch' };
    }
    const key = decodeURIComponent(url.pathname.split('/').slice(2).join('/'));
    if (sent['if-none-match'] === '*' && this.objects.has(key)) return { status: 412, code: 'PreconditionFailed' };
    this.put(key, bytes, contentType, `"put-${++this.putCounter}"`);
    return { status: 200 };
  }
  putCounter = 0;
  async delete(keyOrKeys) {
    for (const key of Array.isArray(keyOrKeys) ? keyOrKeys : [keyOrKeys]) {
      await this.beforeDelete?.(key);
      if (key === this.failDeleteKey) throw new Error('simulated R2 delete failure');
      this.deleted.push(key);
      this.objects.delete(key);
    }
  }
  async list({ prefix = '', cursor, limit = 1000 } = {}) {
    const keys = [...this.objects.keys()].filter((key) => key.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0;
    const page = keys.slice(start, start + limit);
    const truncated = start + limit < keys.length;
    return { objects: page.map((key) => ({ key })), truncated, cursor: truncated ? String(start + limit) : undefined };
  }
}

const SIX = { pending_upload: 'pending_upload', ready: 'ready', pending_delete: 'pending_delete', deleted: 'deleted' };

export class FakeSupabase {
  rows = new Map();
  floors = new Map();
  clock = () => Date.now();
  sessionCurrent = true;
  sessionUnavailable = false;
  deletionJobs = [];
  rpcNames = [];
  // Hooks for race tests: called before the named RPC runs.
  before = {};
  // Called with the RPC's result just after it ran (before the Worker sees it).
  after = {};
  claimSeq = 0;

  iso(ms = this.clock()) { return new Date(ms).toISOString(); }

  fetch = async (url, init = {}) => {
    const parsed = new URL(url);
    const method = init.method ?? 'GET';
    if (parsed.pathname === '/auth/v1/user') {
      const token = init.headers?.Authorization;
      return token === 'Bearer token-a' ? json({ id: ALICE })
        : token === 'Bearer token-b' ? json({ id: BOB }) : json({}, 401);
    }
    if (parsed.pathname === '/rest/v1/rpc/is_current_app_session') {
      if (this.sessionUnavailable) return json({}, 500);
      return json(this.sessionCurrent);
    }
    assert.equal(init.headers?.apikey, SECRET, 'service calls carry the server secret');
    if (parsed.pathname === '/rest/v1/account_deletion_jobs') return json(this.deletionJobs);
    if (parsed.pathname === '/rest/v1/media_objects') return json([]);
    const match = /^\/rest\/v1\/rpc\/(.+)$/.exec(parsed.pathname);
    if (match && method === 'POST') {
      const name = match[1];
      this.rpcNames.push(name);
      await this.before[name]?.();
      const result = this.rpc(name, JSON.parse(init.body));
      await this.after[name]?.(result);
      return json(result);
    }
    throw new Error(`Unexpected fake API call ${method} ${parsed.pathname}`);
  };

  row(id) { return this.rows.get(id); }
  all() { return [...this.rows.values()]; }

  /** Seeds a ready document with its bytes already in [bucket]. */
  seedReady(bucket, { id, owner = ALICE, type = 'scanner', title = 'Doc', size, createdAt, key, objectBucket = BUCKET }) {
    const row = {
      id, owner_id: owner, document_type: type, title, content_type: 'application/pdf',
      size_bytes: size, page_count: 1, content_sha256: 'a'.repeat(64), sha256_verified: false, bucket: objectBucket,
      object_key: key ?? `profiles/${owner}/toolkit-documents/${id}.pdf`, observed_etag: '"e"',
      status: 'ready', source_created_at: createdAt ?? this.iso(), upload_attempts: 1,
      last_authorized_at: createdAt ?? this.iso(), confirmed_at: createdAt ?? this.iso(),
      deleted_at: null, created_at: createdAt ?? this.iso(), updated_at: this.iso(), version: 2,
    };
    this.rows.set(id, row);
    if (bucket) {
      bucket.put(row.object_key, pdfBytes(size - pdfBytes(0).length > 0 ? size - pdfBytes(0).length : 0),
        'application/pdf', row.observed_etag);
    }
    return row;
  }

  rpc(name, p) {
    const now = this.clock();
    const bump = (row) => { row.version += 1; row.updated_at = this.iso(now); };
    switch (name) {
      case 'authorize_toolkit_document_upload': {
        const cap = p.p_content_type === 'application/pdf' ? p.p_max_document_bytes : p.p_max_image_bytes;
        if (p.p_size_bytes > cap) return [{ outcome: 'too_large' }];
        const existing = this.rows.get(p.p_document_id);
        if (existing) {
          if (existing.owner_id !== p.p_user_id) return [{ outcome: 'id_unavailable' }];
          if (['pending_delete', 'deleted'].includes(existing.status)) return [{ outcome: 'document_deleted', status: existing.status, version: existing.version }];
          if (existing.status === 'pending_discard') return [{ outcome: 'cleanup_in_progress', status: existing.status, version: existing.version }];
          if (existing.bucket !== p.p_bucket || existing.document_type !== p.p_document_type ||
              existing.content_type !== p.p_content_type ||
              existing.size_bytes !== p.p_size_bytes ||
              existing.content_sha256 !== p.p_content_sha256) {
            return [{ outcome: 'idempotency_mismatch', status: existing.status, version: existing.version }];
          }
          if (existing.status === 'ready') return [{ outcome: 'already_ready', status: 'ready', version: existing.version }];
          if (existing.upload_attempts >= p.p_max_attempts) return [{ outcome: 'rate_limited' }];
          existing.upload_attempts += 1;
          existing.last_authorized_at = this.iso(now);
          bump(existing);
          return [{ outcome: 'resumed', status: 'pending_upload', version: existing.version }];
        }
        const floor = this.floors.get(p.p_user_id);
        if (floor !== undefined && Date.parse(p.p_source_created_at) <= floor && !p.p_acknowledge_stale) {
          return [{ outcome: 'stale_document' }];
        }
        const mine = this.all().filter((r) => r.owner_id === p.p_user_id);
        if (mine.filter((r) => Date.parse(r.created_at) > now - 3600000).length >= p.p_max_new_per_hour) return [{ outcome: 'rate_limited' }];
        const live = mine.filter((r) => ['pending_upload', 'ready'].includes(r.status));
        if (live.filter((r) => r.status === 'pending_upload').length >= p.p_max_pending) return [{ outcome: 'too_many_pending' }];
        if (live.length >= p.p_max_account_documents) return [{ outcome: 'document_limit' }];
        if (live.reduce((sum, r) => sum + r.size_bytes, 0) + p.p_size_bytes > p.p_max_account_bytes) return [{ outcome: 'storage_limit' }];
        const created = this.iso(now);
        const extension = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' }[p.p_content_type];
        this.rows.set(p.p_document_id, {
          id: p.p_document_id, owner_id: p.p_user_id, document_type: p.p_document_type, title: p.p_title,
          content_type: p.p_content_type, size_bytes: p.p_size_bytes, page_count: p.p_page_count ?? null,
          content_sha256: p.p_content_sha256, sha256_verified: false, bucket: p.p_bucket,
          object_key: `profiles/${p.p_user_id}/toolkit-documents/${p.p_document_id}.${extension}`,
          observed_etag: null, status: 'pending_upload', upload_attempts: 1, last_authorized_at: created,
          source_created_at: Date.parse(p.p_source_created_at) <= now + 86400000 ? p.p_source_created_at : created,
          confirmed_at: null, deleted_at: null, created_at: created, updated_at: created, version: 1,
        });
        return [{ outcome: 'created', status: 'pending_upload', version: 1 }];
      }
      case 'confirm_toolkit_document_upload': {
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id || row.bucket !== p.p_bucket) return [{ outcome: 'not_found' }];
        if (['pending_delete', 'deleted'].includes(row.status)) return [{ outcome: 'document_deleted', version: row.version }];
        if (row.status === 'pending_discard') return [{ outcome: 'cleanup_in_progress', version: row.version }];
        if (row.status === 'ready') return [{ outcome: 'already_confirmed', version: row.version }];
        if (row.size_bytes !== p.p_observed_size) return [{ outcome: 'size_mismatch', version: row.version }];
        if (row.content_type !== p.p_observed_content_type) return [{ outcome: 'type_mismatch', version: row.version }];
        Object.assign(row, { status: 'ready', confirmed_at: this.iso(now), observed_etag: p.p_observed_etag, sha256_verified: p.p_sha256_verified });
        bump(row);
        return [{ outcome: 'confirmed', version: row.version }];
      }
      case 'rename_toolkit_document': {
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id) return [{ outcome: 'not_found' }];
        if (['pending_delete', 'deleted'].includes(row.status)) return [{ outcome: 'document_deleted', version: row.version }];
        if (row.status === 'pending_discard') return [{ outcome: 'cleanup_in_progress', version: row.version }];
        if (row.title === p.p_title) return [{ outcome: 'renamed', title: row.title, version: row.version }];
        if (row.version !== p.p_expected_version) return [{ outcome: 'stale_version', title: row.title, version: row.version }];
        row.title = p.p_title;
        bump(row);
        return [{ outcome: 'renamed', title: row.title, version: row.version }];
      }
      case 'begin_toolkit_document_delete': {
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id || row.bucket !== p.p_bucket) return [{ outcome: 'not_found' }];
        const out = (outcome) => [{ outcome, object_key: row.object_key, last_authorized_at: row.last_authorized_at }];
        if (row.status === 'deleted') return out('already_deleted');
        if (p.p_expected_status && row.status !== p.p_expected_status) return out('status_changed');
        if (row.status === 'pending_delete') return out('already_pending');
        row.status = 'pending_delete';
        row.deleted_at = this.iso(now);
        row.discard_claimed_at = null;
        bump(row);
        return out('marked');
      }
      case 'finalize_toolkit_document_delete': {
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id || row.bucket !== p.p_bucket) return [{ outcome: 'not_found' }];
        if (row.status === 'deleted') return [{ outcome: 'already_deleted' }];
        if (row.status !== 'pending_delete') return [{ outcome: 'not_pending' }];
        if (row.last_authorized_at && Date.parse(row.last_authorized_at) + p.p_min_upload_age_seconds * 1000 > now) return [{ outcome: 'too_soon' }];
        row.status = 'deleted';
        row.title = 'Deleted document';
        bump(row);
        return [{ outcome: 'deleted' }];
      }
      case 'claim_abandoned_toolkit_document': {
        if (!(p.p_lease_seconds >= 60 && p.p_lease_seconds <= 3600)) throw new Error('Invalid Toolkit document claim');
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id || row.bucket !== p.p_bucket) return [{ outcome: 'not_found' }];
        if (row.status === 'pending_discard') {
          if (Date.parse(row.discard_claimed_at) > now - p.p_lease_seconds * 1000) return [{ outcome: 'claim_held' }];
        } else if (row.status !== 'pending_upload' || !row.last_authorized_at ||
                   Date.parse(row.last_authorized_at) > Date.parse(p.p_cutoff)) {
          return [{ outcome: 'not_abandoned' }];
        }
        // A distinct identity per claim (the SQL uses the statement clock).
        const claimedAt = `${this.iso(now).slice(0, -1)}${String(++this.claimSeq).padStart(3, '0')}Z`;
        row.status = 'pending_discard';
        row.discard_claimed_at = claimedAt;
        bump(row);
        return [{ outcome: 'claimed', object_key: row.object_key, claimed_at: claimedAt }];
      }
      case 'discard_abandoned_toolkit_document': {
        const row = this.rows.get(p.p_document_id);
        if (!row || row.owner_id !== p.p_user_id || row.bucket !== p.p_bucket) return [{ outcome: 'not_found' }];
        if (row.status !== 'pending_discard' || row.discard_claimed_at !== p.p_claimed_at) return [{ outcome: 'not_claimed' }];
        this.rows.delete(row.id);
        return [{ outcome: 'discarded' }];
      }
      case 'list_toolkit_documents': {
        let rows = this.all().filter((r) => r.owner_id === p.p_user_id && r.bucket === p.p_bucket && r.status === 'ready' &&
          (!p.p_document_type || r.document_type === p.p_document_type));
        rows.sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : (a.id < b.id ? 1 : -1)));
        if (p.p_before_created_at) {
          rows = rows.filter((r) => r.created_at < p.p_before_created_at ||
            (r.created_at === p.p_before_created_at && r.id < p.p_before_id));
        }
        return rows.slice(0, p.p_limit).map(({ id, document_type, content_type, title, size_bytes, page_count, content_sha256, sha256_verified, source_created_at, created_at, confirmed_at, version }) =>
          ({ id, document_type, content_type, title, size_bytes, page_count, content_sha256, sha256_verified, source_created_at, created_at, confirmed_at, version }));
      }
      case 'get_toolkit_document': {
        const row = this.rows.get(p.p_document_id);
        return row && row.owner_id === p.p_user_id ? [{ ...row }] : [];
      }
      case 'toolkit_document_statuses':
        return p.p_ids.map((id) => this.rows.get(id)).filter((r) => r && r.owner_id === p.p_user_id && r.bucket === p.p_bucket)
          .map((r) => ({ id: r.id, status: r.status, version: r.version }));
      case 'toolkit_document_usage': {
        const mine = this.all().filter((r) => r.owner_id === p.p_user_id);
        const sum = (status) => mine.filter((r) => r.status === status).reduce((s, r) => s + r.size_bytes, 0);
        const count = (status) => mine.filter((r) => r.status === status).length;
        return [{ ready_count: count('ready'), ready_bytes: sum('ready'), pending_count: count('pending_upload'), pending_bytes: sum('pending_upload') }];
      }
      case 'list_toolkit_document_cleanup': {
        const cutoff = Date.parse(p.p_cutoff);
        const pick = {
          abandoned_pending: (r) => r.status === 'pending_upload' && Date.parse(r.last_authorized_at) <= cutoff,
          stuck_discard: (r) => r.status === 'pending_discard' && Date.parse(r.discard_claimed_at) <= cutoff,
          pending_delete: (r) => r.status === 'pending_delete' && Date.parse(r.deleted_at) <= cutoff,
          old_tombstones: (r) => r.status === 'deleted' && Date.parse(r.deleted_at) <= cutoff,
        }[p.p_kind];
        return this.all().filter((r) => r.bucket === p.p_bucket && pick(r)).slice(0, p.p_limit)
          .map(({ id, owner_id, bucket, object_key, status }) => ({ id, owner_id, bucket, object_key, status }));
      }
      case 'purge_toolkit_document_tombstone': {
        const row = this.rows.get(p.p_document_id);
        if (row && row.owner_id === p.p_user_id && row.status === 'deleted' && Date.parse(row.deleted_at) <= Date.parse(p.p_cutoff)) {
          this.floors.set(row.owner_id, Math.max(this.floors.get(row.owner_id) ?? 0, Date.parse(row.deleted_at)));
          this.rows.delete(row.id);
          return true;
        }
        return false;
      }
      default:
        throw new Error(`Unexpected fake RPC ${name}`);
    }
  }
}

export function makeState(overrides = {}) {
  const supabase = new FakeSupabase();
  const bucket = new FakeBucket();
  return {
    supabase,
    bucket,
    env: {
      SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test', SUPABASE_SECRET_KEY: SECRET,
      R2_BUCKET_NAME: BUCKET, R2_S3_ENDPOINT: 'https://r2.test.example.com',
      R2_ACCESS_KEY_ID: 'test-access', R2_SECRET_ACCESS_KEY: 'test-secret',
      MEDIA_BUCKET: bucket, TOOLKIT_DOCUMENTS_ENABLED: 'true', ...overrides,
    },
  };
}
