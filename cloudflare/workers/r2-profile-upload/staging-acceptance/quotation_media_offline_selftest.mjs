// Offline self-test of quotation_media_staging_acceptance.mjs.
//
// Runs the REAL worker.js (behind its staging gate) against an in-memory
// Supabase (client RLS behaviour + the Worker's service-role access), an
// in-memory private R2 and the acceptance runner itself, with no network. It
// proves the runner's own sequencing and assertions are consistent with the
// Worker's designed behaviour, and — with deliberately injected faults — that
// its checks actually fail when the system under test misbehaves.
//
// It proves nothing about hosted Supabase, Cloudflare or R2. Run:
//   node cloudflare/workers/r2-profile-upload/staging-acceptance/quotation_media_offline_selftest.mjs

import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import worker from '../worker.js';
import { run } from './quotation_media_staging_acceptance.mjs';
import { run as runProductionSmoke } from './quotation_media_production_smoke.mjs';

const SUPABASE_HOST = 'rbvcnvqpdqrhywcgxkne.supabase.co';
const WORKER_HOST = 'r2-profile-upload-staging.selftest.workers.dev';
const R2_HOST = 'r2.selftest.example.com';
const PUBLISHABLE = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const SECRET = 'sb_secret_SELFTEST';
const BUCKET = 'broker-wallet-media-staging';
const GATE = 'selftest-gate-key';
const A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const B_UID = '5b5b5b5b-5b5b-4b5b-8b5b-5b5b5b5b5b5b';

const HEADER_KEYS = ['property_title', 'property_type', 'parking', 'subtitle', 'display_date', 'start_date_text', 'end_date_text',
  'currency_code', 'professional_fee', 'total_amount', 'number_of_installments', 'payment_type', 'insurance_amount',
  'insurance_returnable', 'office_name', 'custom_note', 'welcome_message_mode', 'custom_welcome_message'];

const json = (body, status = 200) => new Response(body === null ? null : JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});

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
  async delete(key) { this.objects.delete(key); }
  async list() { return { objects: [], truncated: false }; }
}

class World {
  constructor(opts = {}) {
    this.opts = opts;
    this.workerHost = opts.workerHost ?? WORKER_HOST;
    this.bucketName = opts.bucket ?? BUCKET;
    this.bucket = new Bucket();
    this.users = [
      { id: A_UID, email: 'a@selftest.invalid', password: 'pa' },
      { id: B_UID, email: 'b@selftest.invalid', password: 'pb' },
    ];
    this.tokens = new Map();
    this.quotes = []; this.media = []; this.links = [];
    this.owners = []; this.offers = []; this.ownerMedia = []; this.offerMedia = [];
    this.env = {
      SUPABASE_URL: `https://${SUPABASE_HOST}`, SUPABASE_PUBLISHABLE_KEY: PUBLISHABLE, SUPABASE_SECRET_KEY: SECRET,
      R2_BUCKET_NAME: this.bucketName, R2_S3_ENDPOINT: `https://${R2_HOST}`, R2_ACCESS_KEY_ID: 'k', R2_SECRET_ACCESS_KEY: 's',
      ALLOWED_ORIGIN: '*', MEDIA_BUCKET: this.bucket,
      ...(('gate' in opts ? opts.gate : GATE) ? { STAGING_TEST_KEY: 'gate' in opts ? opts.gate : GATE } : {}),
    };
  }

  fetch = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    if (url.host === this.workerHost) return worker.fetch(new Request(url, init), this.env, {});
    if (url.host === R2_HOST) return this.r2(url, init);
    if (url.host === SUPABASE_HOST) return this.supabase(url, init);
    throw new Error(`unexpected host ${url.host}`);
  };

  r2(url, init) {
    const prefix = `/${this.bucketName}/`;
    if (!url.pathname.startsWith(prefix)) return new Response('NoSuchBucket', { status: 404 });
    const key = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!url.searchParams.has('X-Amz-Signature') && !this.opts.publicBucket) return new Response('AccessDenied', { status: 403 });
    if ((init.method ?? 'GET') === 'PUT') {
      this.bucket.put(key, new Uint8Array(init.body), init.headers?.['Content-Type']);
      return new Response('', { status: 200 });
    }
    const object = this.bucket.objects.get(key);
    return object ? new Response(object.bytes, { status: 200 }) : new Response('NoSuchKey', { status: 404 });
  }

  supabase(url, init) {
    const p = url.pathname;
    const bearer = String(init.headers?.Authorization ?? '').replace(/^Bearer /, '');
    if (p === '/auth/v1/token') {
      const body = JSON.parse(init.body);
      const user = this.users.find((u) => u.email === body.email && u.password === body.password);
      if (!user) return json({ error_code: 'invalid_credentials' }, 400);
      const token = `tok-${user.id}-${this.tokens.size}`;
      this.tokens.set(token, user.id);
      return json({ access_token: token, user: { id: user.id } });
    }
    if (p === '/auth/v1/user') {
      const uid = this.tokens.get(bearer);
      return uid ? json({ id: uid }) : json({ error_code: 'bad_jwt' }, 403);
    }
    if (init.headers?.apikey === SECRET) return this.service(url, init);
    if (init.headers?.apikey === PUBLISHABLE && this.tokens.has(bearer)) return this.client(url, init, this.tokens.get(bearer));
    return json({ message: 'invalid api key' }, 401);
  }

  // ---- signed-in client (RLS) -------------------------------------------
  client(url, init, uid) {
    const p = url.pathname;
    const s = url.searchParams;
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : null;
    const denied = () => json({ code: '42501', message: 'permission denied' }, 403);
    const ownsQuote = (id) => this.quotes.some((q) => q.id === id && q.owner_id === uid);
    const read = (rows, visible) => json(project(orderLimit(filterRows(rows.filter(visible), s), s), s));
    if (p === '/rest/v1/quotations') {
      if (method === 'GET') return read(this.quotes, (q) => this.opts.leakReads || q.owner_id === uid);
      if (method === 'PATCH') {
        const onlyDeleted = Object.keys(body).every((k) => k === 'deleted_at');
        if (!onlyDeleted && !this.opts.clientWritesMediaColumn) return denied();
        for (const q of filterRows(this.quotes, s)) if (q.owner_id === uid && q.deleted_at === null) Object.assign(q, body);
        return new Response(null, { status: 204 });
      }
      return denied();
    }
    if (p === '/rest/v1/media_objects') return method === 'GET' ? read(this.media, (m) => m.owner_id === uid) : denied();
    if (p === '/rest/v1/quotation_media') return method === 'GET' ? read(this.links, (l) => ownsQuote(l.quotation_id)) : denied();
    for (const [table, rows, linkRows, col] of [['owners', this.owners, this.ownerMedia, 'owner_record_id'], ['offers', this.offers, this.offerMedia, 'offer_id']]) {
      if (p === `/rest/v1/${table}`) {
        if (method === 'GET') return read(rows, (r) => r.owner_id === uid);
        if (method === 'POST' && body.owner_id === uid) { rows.push({ deleted_at: null, ...body }); return new Response(null, { status: 201 }); }
        return denied();
      }
      const linkTable = table === 'owners' ? 'owner_media' : 'offer_media';
      if (p === `/rest/v1/${linkTable}`) return method === 'GET' ? read(linkRows, (l) => rows.some((r) => r.id === l[col] && r.owner_id === uid)) : denied();
    }
    if (p === '/rest/v1/rpc/save_quotation') return this.saveQuotation(uid, body);
    if (p.startsWith('/rest/v1/rpc/')) return denied();
    return json({ message: `unexpected client call ${method} ${p}` }, 500);
  }

  saveQuotation(uid, b) {
    const bad = () => json({ code: 'PQT05', message: 'invalid_payload' }, 400);
    const header = b.p_header;
    if (!header || Object.keys(header).some((k) => !HEADER_KEYS.includes(k)) || !HEADER_KEYS.every((k) => k in header)) return bad();
    const existing = this.quotes.find((q) => q.id === b.p_quotation_id);
    if (b.p_expected_version === null) {
      if (existing) return json({ code: 'PQT06', message: 'quotation_id_conflict' }, 400);
      const at = new Date().toISOString();
      this.quotes.push({ id: b.p_quotation_id, owner_id: uid, deleted_at: null, office_logo_media_id: null, pdf_media_id: null, version: 1, property_title: header.property_title });
      return json([{ quotation_id: b.p_quotation_id, resulting_version: 1, outcome: 'created', created_at: at, updated_at: at }]);
    }
    if (!existing || existing.owner_id !== uid) return json({ code: 'PQT02', message: 'quotation_not_found' }, 400);
    if (existing.version !== b.p_expected_version) return json({ code: 'PQT04', message: 'version_conflict' }, 400);
    existing.version += 1;
    return json([{ quotation_id: existing.id, resulting_version: existing.version, outcome: 'updated' }]);
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
    if (p === '/rest/v1/rpc/confirm_quotation_media_upload') return json([this.confirmQuotation(body)]);
    if (p === '/rest/v1/rpc/remove_quotation_media') return json([this.removeQuotation(body)]);
    if (p === '/rest/v1/rpc/confirm_owner_media_upload') {
      return json([this.confirmGallery(body, this.owners, body.p_owner_record_id, this.ownerMedia, 'owner_record_id', 'owners', 'owner_not_found')]);
    }
    if (p === '/rest/v1/rpc/confirm_offer_media_upload') {
      return json([this.confirmGallery(body, this.offers, body.p_offer_id, this.offerMedia, 'offer_id', 'offers', 'offer_not_found')]);
    }
    if (p === '/rest/v1/quotations') {
      const rows = filterRows(this.quotes, this.opts.serviceIgnoresOwner ? new URLSearchParams([...s].filter(([k]) => k !== 'owner_id')) : s);
      if (method === 'GET') return json(rows);
      if (method === 'PATCH') { for (const r of rows) { Object.assign(r, body); r.version += 1; } return json(rep ? rows : []); }
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
        this.links = this.links.filter((l) => !gone.has(l.media_id));
        this.ownerMedia = this.ownerMedia.filter((l) => !gone.has(l.media_id));
        this.offerMedia = this.offerMedia.filter((l) => !gone.has(l.media_id));
        return json(rep ? rows : []);
      }
    }
    if (p === '/rest/v1/quotation_media') {
      const rows = filterRows(this.links, s);
      if (method === 'GET') return json(rows);
      if (method === 'DELETE') { this.links = this.links.filter((l) => !rows.includes(l)); return json([]); }
    }
    if (p === '/rest/v1/owners') return json(filterRows(this.owners, s));
    if (p === '/rest/v1/offers') return json(filterRows(this.offers, s));
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

  confirmQuotation(p) {
    const quote = this.quotes.find((q) => q.id === p.p_quotation_id && q.owner_id === p.p_user_id && q.deleted_at === null);
    if (!quote) return { outcome: 'quotation_not_found' };
    const column = p.p_role === 'office_logo' ? 'office_logo_media_id' : 'pdf_media_id';
    const linkRole = p.p_role === 'office_logo' ? 'logo' : 'pdf';
    const current = quote[column];
    const media = this.media.find((m) => m.id === p.p_media_id && m.owner_id === p.p_user_id && m.bucket === p.p_bucket &&
      m.object_key.startsWith(`profiles/${p.p_user_id}/quotations/${quote.id}/${p.p_role}/`));
    if (!media) return { outcome: 'media_not_found' };
    if (current === media.id && media.status === 'ready') return { outcome: 'already_attached', resulting_version: quote.version };
    if (!this.opts.ignoreStale && current !== p.p_expected_media_id) return { outcome: 'stale_replacement', resulting_version: quote.version };
    if (media.status !== 'pending_upload') return { outcome: 'invalid_status' };
    if (this.links.some((l) => l.media_id === media.id)) return { outcome: 'media_already_bound' };
    this.links = this.links.filter((l) => !(l.quotation_id === quote.id && l.role === linkRole));
    this.links.push({ quotation_id: quote.id, media_id: media.id, role: linkRole, ordinal: 0 });
    Object.assign(media, { status: 'ready', size_bytes: p.p_observed_size, content_type: p.p_observed_content_type });
    quote[column] = media.id;
    quote.version += 1;
    if (current && !this.opts.keepPreviousReady) this.media.find((m) => m.id === current).status = 'pending_delete';
    return { outcome: 'attached', previous_media_id: current, resulting_version: quote.version };
  }

  removeQuotation(p) {
    const quote = this.quotes.find((q) => q.id === p.p_quotation_id && q.owner_id === p.p_user_id && q.deleted_at === null);
    if (!quote) return { outcome: 'quotation_not_found' };
    const column = p.p_role === 'office_logo' ? 'office_logo_media_id' : 'pdf_media_id';
    const current = quote[column];
    if (!current) return { outcome: 'already_removed', resulting_version: quote.version };
    if (current !== p.p_expected_media_id) return { outcome: 'stale_replacement', resulting_version: quote.version };
    quote[column] = null;
    quote.version += 1;
    if (!this.opts.removeLeavesLink) this.links = this.links.filter((l) => l.media_id !== current);
    this.media.find((m) => m.id === current).status = this.opts.removeKeepsReady ? 'ready' : 'pending_delete';
    return { outcome: 'removed', previous_media_id: current, resulting_version: quote.version };
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
      reportPath: join(mkdtempSync(join(tmpdir(), 'qm-selftest-')), 'report.json'),
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

// No gate key, token, signed-URL material or URL may appear in the runner's output.
const text = base.lines.join('\n');
for (const needle of [GATE, 'X-Amz-', 'tok-', 'https://', '@selftest.invalid']) {
  if (text.includes(needle)) { console.log(`LEAK: output contains ${needle}`); problems += 1; }
}

const mutations = [
  // [label, faults, pattern a FAIL line must match | null = the run must still pass entirely]
  ['clients can write office_logo_media_id directly', { clientWritesMediaColumn: true }, /direct write/],
  ["RLS leaks A's Quotation to B", { leakReads: true }, /RLS: B cannot read/],
  ['the bucket is public (unsigned GET works)', { publicBucket: true }, /bucket is private/],
  ['the Worker stops filtering Quotations by owner', { serviceIgnoresOwner: true }, /B cannot (list|authorize|confirm|remove)/],
  ['replaced media is never retired by the database', { keepPreviousReady: true }, /left the live lifecycle/],
  // The Worker checks the slot itself before the database call, so a database that ignored
  // expected_media_id would still not let a stale write win: defence in depth, no failure expected.
  ['the database ignores expected_media_id (the Worker guard still holds)', { ignoreStale: true }, null],
  // Likewise the Worker's own removal step unlinks the media, so a database that left the link behind is repaired.
  ['the database leaves the quotation_media link on removal (the Worker unlinks it)', { removeLeavesLink: true }, null],
];
for (const [label, opts, expected] of mutations) {
  const result = await runWorld(opts);
  const fails = failedLines(result.lines);
  const ok = expected === null ? fails.length === 0 : fails.some((l) => expected.test(l));
  console.log(`MUTATION ${ok ? (expected === null ? 'HELD    ' : 'DETECTED') : 'MISSED  '}: ${label} (${fails.length} FAIL line(s))`);
  if (!ok) { problems += 1; for (const l of fails.slice(0, 5)) console.log(`  ${l}`); }
}


// ---- Production smoke runner, against the same real worker.js bound as the PRODUCTION Worker ----
async function runSmoke(opts = {}) {
  const world = new World({ workerHost: 'media-api.brokerwallet.ae', bucket: 'broker-wallet-media', gate: '', ...opts });
  const realFetch = globalThis.fetch;
  const realLog = console.log;
  const realError = console.error;
  const lines = [];
  globalThis.fetch = (u, i) => world.fetch(u, i);
  console.log = (...a) => lines.push(a.join(' '));
  console.error = () => {};
  let code;
  try {
    code = await runProductionSmoke({
      workerUrl: 'https://media-api.brokerwallet.ae', r2HostSuffix: '.example.com',
      a: { email: 'a@selftest.invalid', password: 'pa', expectedUid: A_UID },
      reportPath: join(mkdtempSync(join(tmpdir(), 'qm-smoke-selftest-')), 'report.json'),
    });
  } finally {
    globalThis.fetch = realFetch;
    console.log = realLog;
    console.error = realError;
  }
  return { code, lines, world };
}

const smoke = await runSmoke();
const smokeFails = failedLines(smoke.lines);
const smokePasses = smoke.lines.filter((l) => l.startsWith('PASS')).length;
console.log(`
PRODUCTION SMOKE (no faults): exit ${smoke.code}, ${smokePasses} PASS, ${smokeFails.length} FAIL`);
for (const line of smokeFails) console.log(`  ${line}`);
if (smoke.code !== 0 || smokeFails.length > 0) problems += 1;
const smokeText = smoke.lines.join('\n');
for (const needle of ['X-Amz-', 'tok-', 'https://', '@selftest.invalid']) {
  if (smokeText.includes(needle)) { console.log(`LEAK: smoke output contains ${needle}`); problems += 1; }
}
if (smoke.world.media.some((m) => m.bucket !== 'broker-wallet-media')) { console.log('smoke wrote a non-production bucket row'); problems += 1; }
if ([...smoke.world.bucket.objects.keys()].length !== 0) { console.log(`smoke left ${smoke.world.bucket.objects.size} object(s) in the bucket`); problems += 1; }
console.log(`  fake-production leftovers after the smoke: ${smoke.world.quotes.length} quotation(s), ${smoke.world.bucket.objects.size} object(s)`);

const smokeMutations = [
  ['the Worker is bound to the STAGING bucket instead of production', { bucket: 'broker-wallet-media-staging' }, /PRODUCTION bucket|bucket broker-wallet-media|bucket is private|exact key/],
  ['the bucket is public (unsigned GET works)', { publicBucket: true }, /bucket is private/],
  ['the database leaves removed media live (its bytes would never be retired)', { removeKeepsReady: true }, /left the live lifecycle|bytes are gone/],
];
for (const [label, opts, expected] of smokeMutations) {
  const result = await runSmoke(opts);
  const fails = failedLines(result.lines);
  const detected = fails.some((l) => expected.test(l));
  console.log(`SMOKE MUTATION ${detected ? 'DETECTED' : 'MISSED  '}: ${label} (${fails.length} FAIL line(s))`);
  if (!detected) { problems += 1; for (const l of fails.slice(0, 5)) console.log(`  ${l}`); }
}

console.log(problems === 0 ? '\nSELF-TEST PASSED' : `\nSELF-TEST FAILED (${problems} problem(s))`);
process.exit(problems === 0 ? 0 : 1);
