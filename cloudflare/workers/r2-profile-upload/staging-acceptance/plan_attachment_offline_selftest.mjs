// Offline self-test of plan_attachment_staging_acceptance.mjs.
//
// Runs the REAL worker.js (behind its staging gate) against an in-memory Supabase (client RLS
// behaviour, the active-session authority and the Worker's service-role access, including the
// plan functions of migration 20261012233000 as a model), an in-memory private R2 and the
// acceptance runner itself, with no network. It proves the runner's own sequencing and
// assertions are consistent with the Worker's designed behaviour, and, with deliberately
// injected faults, that its checks actually fail when the system under test misbehaves.
//
// It proves nothing about hosted Supabase, Cloudflare or R2 (that is what the owner-run
// acceptance is for). Run:
//   node cloudflare/workers/r2-profile-upload/staging-acceptance/plan_attachment_offline_selftest.mjs

import { randomUUID } from 'node:crypto';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import worker from '../worker.js';
import { run } from './plan_attachment_staging_acceptance.mjs';

const SUPABASE_HOST = 'rbvcnvqpdqrhywcgxkne.supabase.co';
const WORKER_HOST = 'r2-profile-upload-staging.selftest.workers.dev';
const R2_HOST = 'r2.selftest.example.com';
const PUBLISHABLE = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const SECRET = 'sb_secret_SELFTEST';
const BUCKET = 'broker-wallet-media-staging';
const GATE = 'selftest-gate-key';
const A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const B_UID = '5b5b5b5b-5b5b-4b5b-8b5b-5b5b5b5b5b5b';
const MIB = 1024 * 1024;
const DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
// The plan rules the migration's plan_attachment_rules() encodes.
const RULES = {
  'image/jpeg': { ext: 'jpg', kind: 'image', max: 10 * MIB },
  'image/png': { ext: 'png', kind: 'image', max: 10 * MIB },
  'image/webp': { ext: 'webp', kind: 'image', max: 10 * MIB },
  'application/pdf': { ext: 'pdf', kind: 'pdf', max: 25 * MIB },
  'application/msword': { ext: 'doc', kind: 'unknown', max: 25 * MIB },
  [DOCX]: { ext: 'docx', kind: 'unknown', max: 25 * MIB },
};

const json = (body, status = 200) => new Response(body === null ? null : JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});

const b64url = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
/** A user access token the way Supabase Auth issues it: a JWT whose claims carry the Auth `session_id`. */
const fakeAccessToken = (uid, sessionId, n) =>
  `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url({ sub: uid, role: 'authenticated', session_id: sessionId })}.tok-sig-${n}`;

function matches(value, filter) {
  if (filter.startsWith('not.')) return !matches(value, filter.slice(4));
  const dot = filter.indexOf('.');
  const op = filter.slice(0, dot);
  const arg = filter.slice(dot + 1);
  if (op === 'eq') return String(value) === arg;
  if (op === 'is' && arg === 'null') return value === null || value === undefined;
  if (op === 'lt') return value != null && Date.parse(value) < Date.parse(arg);
  if (op === 'in') return arg.slice(1, -1).split(',').includes(String(value));
  if (op === 'like') {
    const parts = arg.split('*').map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    return new RegExp(`^${parts.join('.*')}$`).test(String(value ?? ''));
  }
  throw new Error(`unsupported filter ${filter}`);
}
const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'on_conflict']);
const filterRows = (rows, search) => rows.filter((row) =>
  [...search.entries()].every(([k, f]) => RESERVED.has(k) || k.includes('.') || matches(row[k], f)));
const orderLimit = (rows, search) => {
  const out = [...rows];
  const order = search.get('order');
  if (order) {
    const [col, dir = 'asc'] = order.split('.');
    out.sort((a, b) => (typeof a[col] === 'number' ? a[col] - b[col] : String(a[col] ?? '').localeCompare(String(b[col] ?? ''))) * (dir === 'desc' ? -1 : 1));
  }
  return search.get('limit') === null ? out : out.slice(0, Number(search.get('limit')));
};
const project = (rows, search) => {
  const select = search.get('select');
  if (!select || select === '*' || select.includes('(')) return rows;
  const cols = select.split(',');
  return rows.map((r) => Object.fromEntries(cols.map((c) => [c, r[c]])));
};
const withoutOwnerFilter = (search) => new URLSearchParams([...search].filter(([k]) => k !== 'owner_id'));

class Bucket {
  objects = new Map();
  put(key, bytes, contentType) { this.objects.set(key, { bytes, contentType }); }
  async head(key) { const o = this.objects.get(key); return o ? { size: o.bytes.length, httpMetadata: { contentType: o.contentType } } : null; }
  async get(key, { range } = {}) {
    const o = this.objects.get(key);
    if (!o) return null;
    const b = range ? o.bytes.slice(range.offset, range.offset + range.length) : o.bytes;
    return { arrayBuffer: async () => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) };
  }
  async delete(key) { for (const k of Array.isArray(key) ? key : [key]) this.objects.delete(k); }
  async list() { return { objects: [], truncated: false }; }
}

class World {
  constructor(opts = {}) {
    this.opts = opts;
    this.bucket = new Bucket();
    this.users = [
      { id: A_UID, email: 'a@selftest.invalid', password: 'pa' },
      { id: B_UID, email: 'b@selftest.invalid', password: 'pb' },
    ];
    this.tokens = new Map(); // access token -> account id
    this.tokenSessions = new Map(); // access token -> its Auth session id (the JWT `session_id`)
    this.authSessions = new Map(); // auth.sessions: session id -> account id
    this.activeSession = new Map(); // public.user_active_sessions: account id -> active session id
    this.claimLedger = new Map(); // public.app_session_claims: session id -> account id (permanent)
    this.media = [];
    this.offers = []; this.owners = []; this.ownerMedia = []; this.offerMedia = [];
    this.env = {
      SUPABASE_URL: `https://${SUPABASE_HOST}`, SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE, SUPABASE_SECRET_KEY: SECRET,
      R2_BUCKET_NAME: BUCKET, R2_S3_ENDPOINT: `https://${R2_HOST}`, R2_ACCESS_KEY_ID: 'k', R2_SECRET_ACCESS_KEY: 's',
      ALLOWED_ORIGIN: '*', MEDIA_BUCKET: this.bucket,
      ...(('gate' in opts ? opts.gate : GATE) ? { STAGING_TEST_KEY: 'gate' in opts ? opts.gate : GATE } : {}),
    };
  }

  fetch = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    if (url.host === WORKER_HOST) return worker.fetch(new Request(url, init), this.env, {});
    if (url.host === R2_HOST) return this.r2(url, init);
    if (url.host === SUPABASE_HOST) return this.supabase(url, init);
    throw new Error(`unexpected host ${url.host}`);
  };

  r2(url, init) {
    const prefix = `/${BUCKET}/`;
    if (!url.pathname.startsWith(prefix)) return new Response('NoSuchBucket', { status: 404 });
    const key = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!url.searchParams.has('X-Amz-Signature') && !this.opts.publicBucket) return new Response('AccessDenied', { status: 403 });
    if ((init.method ?? 'GET') === 'PUT') {
      this.bucket.put(key, new Uint8Array(init.body), init.headers?.['Content-Type']);
      return new Response('', { status: 200 });
    }
    const object = this.bucket.objects.get(key);
    if (!object) return new Response('NoSuchKey', { status: 404 });
    const bytes = this.opts.corruptReads ? Uint8Array.from(object.bytes, (b, i) => (i === object.bytes.length - 1 ? b ^ 0xff : b)) : object.bytes;
    return new Response(bytes, { status: 200 });
  }

  supabase(url, init) {
    const p = url.pathname;
    const bearer = String(init.headers?.Authorization ?? '').replace(/^Bearer /, '');
    if (p === '/auth/v1/token') {
      const body = JSON.parse(init.body);
      const user = this.users.find((u) => u.email === body.email && u.password === body.password);
      if (!user) return json({ error_code: 'invalid_credentials' }, 400);
      // Like Supabase Auth, every password sign-in is a NEW Auth session, not yet claimed.
      const sessionId = randomUUID();
      const token = fakeAccessToken(user.id, sessionId, this.tokens.size);
      this.tokens.set(token, user.id);
      this.tokenSessions.set(token, sessionId);
      this.authSessions.set(sessionId, user.id);
      return json({ access_token: token, user: { id: user.id } });
    }
    if (p === '/auth/v1/user') {
      const uid = this.tokens.get(bearer);
      return uid ? json({ id: uid }) : json({ error_code: 'bad_jwt' }, 403);
    }
    if (init.headers?.apikey === SECRET) return this.service(url, init);
    if (init.headers?.apikey === PUBLISHABLE && this.tokens.has(bearer)) return this.client(url, init, this.tokens.get(bearer), bearer);
    return json({ message: 'invalid api key' }, 401);
  }

  // ---- signed-in client (RLS) -------------------------------------------
  client(url, init, uid, token) {
    const p = url.pathname;
    const s = url.searchParams;
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const denied = () => json({ code: '42501', message: 'permission denied' }, 403);
    const read = (rows, visible) => json(project(orderLimit(filterRows(rows.filter(visible), s), s), s));
    if (p === '/rest/v1/rpc/claim_current_app_session') return this.claimRpc(token, uid);
    if (p === '/rest/v1/rpc/is_current_app_session') return json(this.isCurrent(token, uid));
    if (!this.isCurrent(token, uid)) return method === 'GET' ? json([]) : denied();
    const mine = (r) => this.opts.leakReads || r.owner_id === uid;
    if (p === '/rest/v1/media_objects') return method === 'GET' ? read(this.media, mine) : denied();
    for (const [table, rows, linkTable, linkRows, col] of [
      ['owners', this.owners, 'owner_media', this.ownerMedia, 'owner_record_id'],
      ['offers', this.offers, 'offer_media', this.offerMedia, 'offer_id'],
    ]) {
      if (p === `/rest/v1/${table}`) {
        if (method === 'GET') return read(rows, mine);
        if (method === 'POST') {
          if (body.owner_id !== uid) return denied();
          if ('plan_media_id' in body && !this.opts.clientWritesPlanPointer) return denied();
          rows.push({ deleted_at: null, plan_media_id: null, version: 1, updated_at: '2026-10-01T00:00:00.000Z', ...body });
          return new Response(null, { status: 201 });
        }
        if (method === 'PATCH') {
          const onlyDeleted = Object.keys(body).every((k) => k === 'deleted_at');
          if (!onlyDeleted && !this.opts.clientWritesPlanPointer) return denied();
          for (const r of filterRows(rows, s)) if (r.owner_id === uid) Object.assign(r, body);
          return new Response(null, { status: 204 });
        }
        return denied();
      }
      if (p === `/rest/v1/${linkTable}`) return method === 'GET' ? read(linkRows, (l) => rows.some((r) => r.id === l[col] && r.owner_id === uid)) : denied();
    }
    const planRpc = /^\/rest\/v1\/rpc\/(confirm|remove)_(offer|owner)_plan(?:_upload)?$/.exec(p);
    if (planRpc && this.opts.clientCallsPlanRpc) return json([this.planRpc(planRpc[2], planRpc[1], body)]);
    if (p.startsWith('/rest/v1/rpc/')) return denied();
    return json({ message: `unexpected client call ${method} ${p}` }, 500);
  }

  /** public.is_current_app_session(): the account's one active session, which must still exist in auth.sessions. */
  isCurrent(token, uid) {
    const sessionId = this.tokenSessions.get(token);
    if (!sessionId || this.authSessions.get(sessionId) !== uid) return false;
    if (this.opts.gateAcceptsAnySession) return true; // fault: the gate never refuses a valid sign-in
    if (this.opts.ignoreSupersession) return this.claimLedger.get(sessionId) === uid; // fault: a replaced session stays current
    return this.activeSession.get(uid) === sessionId;
  }

  /** public.claim_current_app_session(): a fresh session claims once; only the still-active claimant may repeat. */
  claimRpc(token, uid) {
    const sessionId = this.tokenSessions.get(token);
    const refuse = (message) => json({ code: '42501', details: null, hint: null, message }, 403);
    if (!sessionId || this.authSessions.get(sessionId) !== uid) return refuse('session_missing');
    if (this.claimLedger.has(sessionId) && !this.opts.reclaimAllowed) { // fault: a displaced session may reclaim
      return this.activeSession.get(uid) === sessionId ? json(true) : refuse('session_superseded');
    }
    this.claimLedger.set(sessionId, uid);
    this.activeSession.set(uid, sessionId);
    return json(true);
  }

  // ---- the Worker's service-role access ---------------------------------
  service(url, init) {
    const p = url.pathname;
    const s = url.searchParams;
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const rep = String(init.headers?.Prefer).includes('return=representation');
    if (p === '/rest/v1/account_deletion_jobs') return json([]);
    if (p === '/rest/v1/profiles') return json([{ id: 'x', profile_media_id: null }]);
    // No Quotation exists in this world: the regression probe's unknown id finds none.
    if (p === '/rest/v1/quotations') return json([]);
    const planRpc = /^\/rest\/v1\/rpc\/(confirm|remove)_(offer|owner)_plan(?:_upload)?$/.exec(p);
    if (planRpc) {
      try {
        return json([this.planRpc(planRpc[2], planRpc[1], body)]);
      } catch (_) {
        return json({ code: 'P0001', message: 'raised' }, 400);
      }
    }
    if (p === '/rest/v1/rpc/confirm_owner_media_upload') {
      return json([this.confirmGallery(body, this.owners, body.p_owner_record_id, this.ownerMedia, 'owner_record_id', 'owners', 'owner_not_found')]);
    }
    if (p === '/rest/v1/rpc/confirm_offer_media_upload') {
      return json([this.confirmGallery(body, this.offers, body.p_offer_id, this.offerMedia, 'offer_id', 'offers', 'offer_not_found')]);
    }
    if (p === '/rest/v1/offers' || p === '/rest/v1/owners') {
      const rows = p === '/rest/v1/offers' ? this.offers : this.owners;
      const matched = filterRows(rows, this.opts.serviceIgnoresOwner ? withoutOwnerFilter(s) : s);
      if (method === 'GET') return json(matched);
      if (method === 'PATCH') { for (const r of matched) Object.assign(r, body); return json(rep ? matched : []); }
    }
    if (p === '/rest/v1/media_objects') {
      if (method === 'POST') {
        if (this.media.some((m) => m.id === body.id)) return json({ code: '23505' }, 409);
        const at = new Date().toISOString();
        this.media.push({ ...body, created_at: at, updated_at: at });
        return json([], 201);
      }
      const rows = orderLimit(filterRows(this.media, s), s);
      if (method === 'GET') return json(rows);
      if (method === 'PATCH') { for (const r of rows) Object.assign(r, body); return json(rep ? rows : []); }
      if (method === 'DELETE') {
        const gone = new Set(rows.map((r) => r.id));
        this.media = this.media.filter((m) => !gone.has(m.id));
        this.ownerMedia = this.ownerMedia.filter((l) => !gone.has(l.media_id));
        this.offerMedia = this.offerMedia.filter((l) => !gone.has(l.media_id));
        return json(rep ? rows : []);
      }
    }
    for (const [table, rows, parents, parentResource, col] of [
      ['owner_media', this.ownerMedia, this.owners, 'owners', 'owner_record_id'],
      ['offer_media', this.offerMedia, this.offers, 'offers', 'offer_id'],
    ]) {
      if (p !== `/rest/v1/${table}`) continue;
      if (method === 'GET') return json(orderLimit(this.readLinks(rows, parents, parentResource, col, s), s));
      if (method === 'DELETE') {
        const doomed = filterRows(rows, s);
        if (table === 'owner_media') this.ownerMedia = this.ownerMedia.filter((l) => !doomed.includes(l));
        else this.offerMedia = this.offerMedia.filter((l) => !doomed.includes(l));
        return json([]);
      }
    }
    return json({ message: `unexpected service call ${method} ${p}` }, 500);
  }

  readLinks(links, parents, parentResource, parentColumn, s) {
    const select = s.get('select') ?? '';
    let rows = filterRows(links, s).map((link) => ({
      link, media: this.media.find((m) => m.id === link.media_id) ?? null, parent: parents.find((x) => x.id === link[parentColumn]) ?? null,
    }));
    for (const [key, filter] of s.entries()) {
      if (!key.includes('.')) continue;
      const [resource, column] = key.split('.');
      const pick = resource === parentResource ? (r) => r.parent : (r) => r.media;
      rows = rows.filter((r) => pick(r) !== null && matches(pick(r)[column], filter));
    }
    if (select.includes('media_objects!inner')) rows = rows.filter((r) => r.media !== null);
    if (select.includes(`${parentResource}!inner`)) rows = rows.filter((r) => r.parent !== null);
    return rows.map(({ link, media, parent }) => ({ ...link, media_objects: media ? { ...media } : null, [parentResource]: parent ? { ...parent } : null }));
  }

  confirmGallery(p, parents, parentId, links, linkColumn, segment, notFound) {
    const parent = parents.find((r) => r.id === parentId && r.owner_id === p.p_user_id && (r.deleted_at ?? null) === null);
    if (!parent) return { outcome: notFound, media_ordinal: null };
    const prefix = `profiles/${p.p_user_id}/${segment}/${parentId}/`;
    const media = this.media.find((m) => m.id === p.p_media_id && m.owner_id === p.p_user_id && m.bucket === p.p_bucket);
    if (!media || !String(media.object_key).startsWith(prefix)) return { outcome: 'media_not_found', media_ordinal: null };
    const ready = { status: 'ready', size_bytes: p.p_observed_size, content_type: p.p_observed_content_type, duration_ms: p.p_duration_ms, updated_at: new Date().toISOString() };
    const existing = links.find((l) => l[linkColumn] === parentId && l.media_id === p.p_media_id);
    if (existing) { if (media.status === 'pending_upload') Object.assign(media, ready); return { outcome: 'already_attached', media_ordinal: existing.ordinal }; }
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status', media_ordinal: null };
    const gallery = links.filter((l) => l[linkColumn] === parentId && l.role === 'gallery');
    const ordinal = gallery.length === 0 ? 0 : Math.max(...gallery.map((l) => l.ordinal)) + 1;
    links.push({ [linkColumn]: parentId, media_id: p.p_media_id, role: 'gallery', ordinal });
    Object.assign(media, ready);
    return { outcome: 'attached', media_ordinal: ordinal };
  }

  /** The SQL functions of migration 20261012233000, as a model. */
  planRpc(kind, fn, p) {
    const parents = kind === 'offer' ? this.offers : this.owners;
    const parentId = kind === 'offer' ? p.p_offer_id : p.p_owner_record_id;
    const segment = kind === 'offer' ? 'offer-plans' : 'owner-plans';
    const parent = parents.find((x) => x.id === parentId && x.owner_id === p.p_user_id);
    if (!parent || parent.deleted_at) return { outcome: `${kind}_not_found` };
    const current = parent.plan_media_id ?? null;
    const expected = p.p_expected_media_id ?? null;
    const prefix = `profiles/${p.p_user_id}/${segment}/${parent.id}/`;
    // The guard trigger keeps the record's own stamps on a change that touches only the pointer.
    const stamp = () => { if (this.opts.versionBumped) { parent.version += 1; parent.updated_at = new Date().toISOString(); } };
    if (fn === 'remove') {
      if (!current) return { outcome: 'already_removed' };
      if (current !== expected) return { outcome: 'stale_replacement' };
      const old = this.media.find((m) => m.id === current);
      if (!old || old.status !== 'ready' || old.bucket !== p.p_bucket || !old.object_key.startsWith(prefix)) return { outcome: 'invalid_state' };
      parent.plan_media_id = null;
      stamp();
      old.status = 'pending_delete';
      return { outcome: 'removed', previous_media_id: current };
    }
    const rules = RULES[p.p_observed_content_type];
    if (!rules || !Number.isInteger(p.p_observed_size) || p.p_observed_size < 1 || p.p_observed_size > rules.max) throw new Error('raised');
    const media = this.media.find((m) => m.id === p.p_media_id && m.owner_id === p.p_user_id && m.bucket === p.p_bucket);
    if (!media || media.object_key !== `${prefix}${media.id}.${rules.ext}` || media.content_type !== p.p_observed_content_type || media.media_type !== rules.kind) {
      return { outcome: 'media_not_found' };
    }
    if (current === media.id && media.status === 'ready') return { outcome: 'already_attached' };
    if (!this.opts.ignoreStale && current !== expected) return { outcome: 'stale_replacement' };
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status' };
    if (current) {
      const old = this.media.find((m) => m.id === current);
      if (!old || old.status !== 'ready' || old.bucket !== p.p_bucket || !old.object_key.startsWith(prefix)) return { outcome: 'invalid_state' };
    }
    Object.assign(media, { status: 'ready', size_bytes: p.p_observed_size, content_type: p.p_observed_content_type });
    parent.plan_media_id = media.id;
    stamp();
    if (this.opts.planAlsoGalleryLink) {
      const links = kind === 'offer' ? this.offerMedia : this.owners && this.ownerMedia;
      links.push({ [kind === 'offer' ? 'offer_id' : 'owner_record_id']: parent.id, media_id: media.id, role: 'gallery', ordinal: links.length });
    }
    if (current && !this.opts.keepPreviousReady) this.media.find((m) => m.id === current).status = 'pending_delete';
    return { outcome: 'attached', previous_media_id: current };
  }
}

async function runWorld(opts = {}) {
  const world = new World(opts);
  const realFetch = globalThis.fetch;
  const realLog = console.log;
  const realError = console.error;
  const lines = [];
  globalThis.fetch = (u, i) => world.fetch(u, i);
  console.log = (...a) => lines.push(a.join(' '));
  console.error = () => {};
  let code;
  try {
    code = await run({
      workerUrl: `https://${WORKER_HOST}`, stagingKey: GATE, r2HostSuffix: '.example.com',
      a: { email: 'a@selftest.invalid', password: 'pa', expectedUid: A_UID },
      b: { email: 'b@selftest.invalid', password: 'pb', expectedUid: B_UID },
      reportPath: join(mkdtempSync(join(tmpdir(), 'plan-selftest-')), 'report.json'),
    });
  } finally {
    globalThis.fetch = realFetch;
    console.log = realLog;
    console.error = realError;
  }
  return { code, lines, world };
}

const failedLines = (lines) => lines.filter((l) => l.startsWith('FAIL'));
let problems = 0;

const base = await runWorld();
const baseFails = failedLines(base.lines);
const passes = base.lines.filter((l) => l.startsWith('PASS')).length;
console.log(`BASELINE (no faults): exit ${base.code}, ${passes} PASS, ${baseFails.length} FAIL`);
for (const line of baseFails) console.log(`  ${line}`);
if (base.code !== 0 || baseFails.length > 0) problems += 1;

// No gate key, token, signed-URL material, URL, email or storage key may appear in the runner's output.
const text = base.lines.join('\n');
for (const needle of [GATE, 'X-Amz-', 'tok-sig', 'eyJ', 'https://', '@selftest.invalid', 'profiles/', A_UID, B_UID]) {
  if (text.includes(needle)) { console.log(`LEAK: output contains ${needle}`); problems += 1; }
}

// What the run leaves behind: nothing in the bucket, every media row terminal, every test record soft-deleted, no plan pointer.
const leftObjects = base.world.bucket.objects.size;
const liveMedia = base.world.media.filter((m) => !['deleted', 'failed'].includes(m.status));
const liveParents = [...base.world.offers, ...base.world.owners].filter((r) => r.deleted_at === null);
const pointers = [...base.world.offers, ...base.world.owners].filter((r) => r.plan_media_id);
console.log(`  after the run: ${leftObjects} object(s) in the bucket, ${liveMedia.length} live media row(s), ${liveParents.length} undeleted test record(s), ${pointers.length} plan pointer(s)`);
if (leftObjects !== 0 || liveMedia.length !== 0 || liveParents.length !== 0 || pointers.length !== 0) problems += 1;
const planRows = base.world.media.filter((m) => /\/(offer|owner)-plans\//.test(m.object_key));
console.log(`  plan media rows created by the run: ${planRows.length}, statuses: ${[...new Set(planRows.map((m) => m.status))].join(', ')}`);

const mutations = [
  // [label, faults, pattern a FAIL line must match | null = the run must still pass entirely]
  ['clients can write the plan pointer directly', { clientWritesPlanPointer: true }, /a signed-in client cannot (clear|point|create)/],
  ['clients can execute the plan functions', { clientCallsPlanRpc: true }, /cannot execute (confirm|remove)_/],
  ["RLS leaks A's records and media to B", { leakReads: true }, /RLS/],
  ["the Worker's plan lookups stop filtering by owner", { serviceIgnoresOwner: true }, /B cannot/],
  ['the database keeps a replaced plan ready (never retired)', { keepPreviousReady: true }, /retired|object is gone/],
  ['the bucket is public (unsigned GET works)', { publicBucket: true }, /without the signature/],
  ['stored bytes come back corrupted', { corruptReads: true }, /exact bytes/],
  ["attaching a plan bumps the record's version and updated_at", { versionBumped: true }, /version and updated_at/],
  ['a plan is also stored as a gallery link', { planAlsoGalleryLink: true }, /gallery list is empty|no offer_media link/],
  ['the staging key gate is not enforced (no STAGING_TEST_KEY)', { gate: '' }, /without the staging key|wrong staging key/],
  // Single Active Device: the real worker.js asks this database authority before every route.
  ['the gate accepts a session that never claimed', { gateAcceptsAnySession: true }, /never-claimed/],
  ['a replaced session stays current (the database ignores supersession)', { ignoreSupersession: true }, /superseded session is refused/],
  ['a displaced session can claim again', { reclaimAllowed: true }, /cannot reclaim/],
  // The Worker checks the slot itself before the database call, so a database that ignored
  // expected_media_id would still not let a stale write win: defence in depth, no failure expected.
  ['the database ignores expected_media_id (the Worker guard still holds)', { ignoreStale: true }, null],
];
for (const [label, opts, expected] of mutations) {
  const result = await runWorld(opts);
  const fails = failedLines(result.lines);
  const ok = expected === null ? fails.length === 0 : fails.some((l) => expected.test(l));
  console.log(`MUTATION ${ok ? (expected === null ? 'HELD    ' : 'DETECTED') : 'MISSED  '}: ${label} (${fails.length} FAIL line(s))`);
  if (!ok) { problems += 1; for (const l of fails.slice(0, 5)) console.log(`  ${l}`); }
}

console.log(problems === 0 ? '\nSELF-TEST PASSED' : `\nSELF-TEST FAILED (${problems} problem(s))`);
process.exit(problems === 0 ? 0 : 1);
