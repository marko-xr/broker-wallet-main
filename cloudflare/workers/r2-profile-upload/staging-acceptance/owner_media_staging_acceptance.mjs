// Broker Wallet — Owner private media staging acceptance.
//
// Run it only through run_owner_media_staging_acceptance.ps1, in the owner's
// own terminal, against the STAGING Worker (`r2-profile-upload-staging`,
// private bucket `broker-wallet-media-staging`). The launcher asks for the
// staging gate key and the two disposable test accounts' passwords with masked
// input and hands them to this process alone.
//
// Output and the JSON reports hold PASS/FAIL per check, HTTP statuses, Worker
// codes and record/media ids. Never a token, key, password, email, account id,
// object key, presigned PUT URL or signed GET URL.
//
// Modes (BW_E2E_MODE):
//   full       gate, Owner authorize/PUT/confirm/list/signed GET, video range
//              reads, removal, idempotency and retry, the ten-item limit,
//              cross-account and cross-parent isolation, a focused Offer
//              regression, a non-destructive profile regression, and phase 1
//              of the F1 check (seeds abandoned uploads, writes a state file).
//   f1-verify  phase 2 of the F1 check, at least 24 h 10 min after phase 1:
//              an authorize withdraws only its OWN entity's abandoned uploads.
//              Needs BW_E2E_F1_STATE (the phase 1 state file).
//
// Every record it creates is new and disposable (names start "staging-e2e").
// It never modifies or deletes a row it did not create, and it never confirms a
// profile image, so no account's profile photo is replaced.
//
// BW_E2E_OFFLINE_CHECK=1 exercises the local helpers only (no network).
// Node built-ins only: no `npm install` is needed.

import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const STAGING_BUCKET = 'broker-wallet-media-staging';
const STAGING_HEADER = 'X-Broker-Wallet-Staging-Key';
const STAGING_URL_PATTERN = /^https:\/\/r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$/;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_VIDEO_BYTES = 100 * 1024 * 1024;
const MAX_ITEMS = 10;
const MAX_DURATION_MS = 181_000;
// The Worker's abandoned-upload cutoff (worker.js PENDING_CLEANUP_AGE_MS), plus
// a margin so clock skew cannot make phase 2 of the F1 check run early.
const PENDING_CLEANUP_AGE_MS = 24 * 60 * 60 * 1000;
const F1_MARGIN_MS = 10 * 60 * 1000;

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');
const RUN_ID = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
const env = process.env;

const OWNER = Object.freeze({
  name: 'Owner',
  route: '/owner-media',
  idField: 'ownerRecordId',
  linkTable: 'owner_media',
  linkColumn: 'owner_record_id',
  rpc: 'confirm_owner_media_upload',
  rpcParentParam: 'p_owner_record_id',
  notFound: 'owner_not_found',
  limitCode: 'owner_media_limit_reached',
});
const OFFER = Object.freeze({
  name: 'Offer',
  route: '/offer-media',
  idField: 'offerId',
  linkTable: 'offer_media',
  linkColumn: 'offer_id',
  rpc: 'confirm_offer_media_upload',
  rpcParentParam: 'p_offer_id',
  notFound: 'offer_not_found',
  limitCode: 'offer_media_limit_reached',
});

const MP4_BRANDS = new Set(['isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V ', 'M4VH', 'M4VP', 'dash', 'mmp4', 'MSNV', 'f4v ']);
const QT_BRANDS = new Set(['qt  ']);
const GPP_BRANDS = new Set(['3gp4', '3gp5', '3gp6', '3gp7', '3ge6', '3ge7', '3gg6']);

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

const results = [];
const created = { owners: [], offers: [], media: [] };

function check(section, name, ok, detail = '') {
  results.push({ section, name, ok: Boolean(ok), detail: sanitize(detail) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${section}] ${name}${detail ? `  (${sanitize(detail)})` : ''}`);
  return Boolean(ok);
}

function note(section, text) {
  results.push({ section, name: text, ok: null, detail: '' });
  console.log(`INFO  [${section}] ${text}`);
}

/** Removes anything URL- or token-shaped, so no link or credential is printed. */
function sanitize(value) {
  return String(value ?? '')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<jwt>')
    .slice(0, 300);
}

/** A stable, non-reversible tag for an account, so phase 2 can prove it is the same one. */
function fingerprint(uid) {
  return createHash('sha256').update(`broker-wallet-f1:${uid}`).digest('hex').slice(0, 16);
}

class StepError extends Error {}

/** Stops the whole run: continuing would only create rows that cannot finish. */
class FatalError extends StepError {}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

function required(name) {
  const value = env[name];
  if (!value) {
    console.error(`Missing ${name}. Run this through run_owner_media_staging_acceptance.ps1.`);
    process.exit(2);
  }
  return value;
}

function loadConfig() {
  const mode = env.BW_E2E_MODE || 'full';
  if (mode !== 'full' && mode !== 'f1-verify') {
    console.error('BW_E2E_MODE must be full or f1-verify.');
    process.exit(2);
  }
  const workerUrl = required('BW_E2E_WORKER_URL').replace(/\/+$/, '');
  if (!STAGING_URL_PATTERN.test(workerUrl)) {
    console.error('BW_E2E_WORKER_URL must be the staging workers.dev URL (https://r2-profile-upload-staging.<subdomain>.workers.dev).');
    process.exit(2);
  }
  return {
    mode,
    workerUrl,
    stagingKey: required('BW_E2E_STAGING_KEY'),
    a: { email: required('BW_E2E_A_EMAIL').trim(), password: required('BW_E2E_A_PASSWORD') },
    b: { email: required('BW_E2E_B_EMAIL').trim(), password: required('BW_E2E_B_PASSWORD') },
    videoPath: mode === 'full' ? required('BW_E2E_VIDEO_PATH') : null,
    longVideoPath: env.BW_E2E_LONG_VIDEO_PATH || null,
    statePath: mode === 'f1-verify' ? required('BW_E2E_F1_STATE') : null,
    reportPath: env.BW_E2E_REPORT_PATH || join(REPORTS, `owner_media_${mode}_${RUN_ID}.json`),
  };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function loadImages() {
  const fixture = (name) => readFileSync(join(HERE, 'fixtures', name));
  return { jpeg: fixture('photo.jpg'), png: fixture('photo.png'), webp: fixture('photo.webp') };
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

/** The container type of a video from its leading bytes, like the Worker. */
function detectVideoType(bytes) {
  if (bytes.length < 12 || bytes.toString('latin1', 4, 8) !== 'ftyp') return null;
  const typeOf = (brand) =>
    MP4_BRANDS.has(brand) ? 'video/mp4'
      : QT_BRANDS.has(brand) ? 'video/quicktime'
        : GPP_BRANDS.has(brand) ? 'video/3gpp'
          : null;
  const major = typeOf(bytes.toString('latin1', 8, 12));
  if (major) return major;
  const boxSize = bytes.readUInt32BE(0);
  const end = Math.min(bytes.length, boxSize >= 16 ? boxSize : bytes.length);
  for (let offset = 16; offset + 4 <= end; offset += 4) {
    const byCompatible = typeOf(bytes.toString('latin1', offset, offset + 4));
    if (byCompatible) return byCompatible;
  }
  return null;
}

function loadVideo(path) {
  const bytes = readFileSync(path);
  return { bytes, type: detectVideoType(bytes), name: path.split(/[\\/]/).pop(), sha256: sha256(bytes) };
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

let cfg;
let startedAt;

async function timedFetch(url, init = {}, timeoutMs = 60_000) {
  return fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
}

async function safeJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return null;
  }
}

async function signIn(label, creds) {
  const res = await timedFetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: creds.email, password: creds.password }),
  });
  const body = await safeJson(res);
  if (!res.ok || !body?.access_token || !body?.user?.id) {
    // Auth's fixed reason code (e.g. invalid_credentials, email_not_confirmed);
    // never the email or anything the caller sent.
    const reason = String(body?.error_code ?? body?.error ?? '').replace(/[^a-z0-9_]/gi, '').slice(0, 40);
    throw new FatalError(`sign-in ${label} failed (HTTP ${res.status}${reason ? ` ${reason}` : ''})`);
  }
  return { label, token: body.access_token, uid: body.user.id };
}

async function callWorker(session, method, path, body, { key, timeout = 60_000 } = {}) {
  const headers = {};
  const gateKey = key === undefined ? cfg.stagingKey : key;
  if (gateKey !== null) headers[STAGING_HEADER] = gateKey;
  if (session) headers.Authorization = `Bearer ${session.token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await timedFetch(
    `${cfg.workerUrl}${path}`,
    { method, headers, body: body === undefined ? undefined : JSON.stringify(body) },
    timeout,
  );
  return { status: res.status, body: await safeJson(res) };
}

async function rest(session, method, path, body, prefer) {
  const headers = { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${session.token}` };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;
  const res = await timedFetch(`${SUPABASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await safeJson(res) };
}

async function putBytes(url, bytes, contentType) {
  const res = await timedFetch(url, { method: 'PUT', headers: { 'Content-Type': contentType }, body: bytes }, 600_000);
  await res.arrayBuffer().catch(() => {});
  return res.status;
}

async function getBytes(url, range) {
  const res = await timedFetch(url, { headers: range ? { Range: range } : {} }, 600_000);
  return { status: res.status, bytes: Buffer.from(await res.arrayBuffer()) };
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

async function createOwner(session, label) {
  const id = randomUUID();
  const r = await rest(
    session,
    'POST',
    '/rest/v1/owners',
    { id, owner_id: session.uid, name: `staging-e2e ${RUN_ID} ${label}`, notes: 'Owner media staging acceptance (disposable)' },
    'return=minimal',
  );
  check('setup', `new staging-only Owner ${label} created by ${session.label}`, r.status === 201, `HTTP ${r.status} id ${id}`);
  if (r.status !== 201) throw new FatalError(`could not create Owner ${label}`);
  created.owners.push({ label, id, account: session.label });
  return id;
}

async function createOffer(session, label) {
  const id = randomUUID();
  const r = await rest(
    session,
    'POST',
    '/rest/v1/offers',
    { id, owner_id: session.uid, offer_type: 'rent', notes: `staging-e2e ${RUN_ID} ${label}` },
    'return=minimal',
  );
  check('setup', `new staging-only Offer ${label} created by ${session.label}`, r.status === 201, `HTTP ${r.status} id ${id}`);
  if (r.status !== 201) throw new FatalError(`could not create Offer ${label}`);
  created.offers.push({ label, id, account: session.label });
  return id;
}

async function authorize(parent, session, parentId, id, bytesOrLength, contentType, name = 'e2e') {
  const contentLength = typeof bytesOrLength === 'number' ? bytesOrLength : bytesOrLength.length;
  return callWorker(session, 'POST', `${parent.route}/authorize`, {
    [parent.idField]: parentId,
    mediaObjectId: id,
    contentType,
    contentLength,
    originalFileName: name,
  });
}

async function confirm(parent, session, parentId, id) {
  return callWorker(session, 'POST', `${parent.route}/confirm`, { [parent.idField]: parentId, mediaObjectId: id }, { timeout: 120_000 });
}

async function remove(parent, session, parentId, id) {
  return callWorker(session, 'POST', `${parent.route}/remove`, { [parent.idField]: parentId, mediaObjectId: id });
}

async function list(parent, session, parentId) {
  const r = await callWorker(session, 'GET', `${parent.route}?${parent.idField}=${parentId}`);
  return { status: r.status, code: r.body?.code, media: Array.isArray(r.body?.media) ? r.body.media : [] };
}

function remember(parent, parentId, session, id, contentType) {
  created.media.push({ id, parent: parent.name, parentId, account: session.label, contentType });
}

/** authorize → PUT → confirm, as the app's queue does. */
async function upload(parent, session, parentId, { id = randomUUID(), bytes, contentType, name }) {
  const out = { id };
  const auth = await authorize(parent, session, parentId, id, bytes, contentType, name);
  out.authStatus = auth.status;
  out.authCode = auth.body?.code;
  out.mediaType = auth.body?.mediaType;
  out.returnedId = auth.body?.mediaObjectId;
  if (auth.status !== 200 || auth.body?.status !== 'pending') return out;
  remember(parent, parentId, session, id, contentType);
  out.putStatus = await putBytes(auth.body.presignedUrl, bytes, contentType);
  const conf = await confirm(parent, session, parentId, id);
  out.confirmStatus = conf.status;
  out.confirmCode = conf.body?.code;
  out.ordinal = conf.body?.ordinal;
  out.confirmedParent = conf.body?.[parent.idField];
  return out;
}

function uploaded(out) {
  return out.authStatus === 200 && out.putStatus === 200 && out.confirmStatus === 200;
}

function describe(out) {
  return `authorize ${out.authStatus}${out.authCode ? ` ${out.authCode}` : ''}` +
    (out.putStatus !== undefined ? `, PUT ${out.putStatus}` : '') +
    (out.confirmStatus !== undefined ? `, confirm ${out.confirmStatus}${out.confirmCode ? ` ${out.confirmCode}` : ''}` : '') +
    (out.ordinal !== undefined && out.ordinal !== null ? `, ordinal ${out.ordinal}` : '');
}

function coded(r) {
  return `HTTP ${r.status}${r.body?.code ? ` ${r.body.code}` : r.code ? ` ${r.code}` : ''}`;
}

async function mediaRows(session, id) {
  const r = await rest(session, 'GET', `/rest/v1/media_objects?id=eq.${id}&select=id,status,bucket,media_type,content_type,size_bytes,duration_ms,created_at`);
  return r.status === 200 && Array.isArray(r.body) ? r.body : null;
}

async function linkRows(parent, session, id) {
  const r = await rest(session, 'GET', `/rest/v1/${parent.linkTable}?media_id=eq.${id}&select=${parent.linkColumn},media_id,ordinal`);
  return r.status === 200 && Array.isArray(r.body) ? r.body : null;
}

function rpcBody(parent, uid, parentId, mediaId) {
  return {
    p_user_id: uid,
    [parent.rpcParentParam]: parentId,
    p_media_id: mediaId,
    p_bucket: STAGING_BUCKET,
    p_max_items: MAX_ITEMS,
    p_observed_size: 1,
    p_observed_content_type: 'image/jpeg',
    p_duration_ms: null,
  };
}

// ---------------------------------------------------------------------------
// Sections — full run
// ---------------------------------------------------------------------------

async function sectionGate() {
  const probe = `/owner-media?ownerRecordId=${randomUUID()}`;
  const none = await callWorker(null, 'GET', probe, undefined, { key: null });
  check('gate', 'without the staging key: 403', none.status === 403, `HTTP ${none.status}`);
  const wrong = await callWorker(null, 'GET', probe, undefined, { key: `wrong-${randomUUID()}` });
  check('gate', 'with a wrong staging key: 403', wrong.status === 403, `HTTP ${wrong.status}`);
  const post = await callWorker(null, 'POST', '/owner-media/authorize', {}, { key: null });
  check('gate', 'Owner authorize without the staging key: 403', post.status === 403, `HTTP ${post.status}`);
  const anonymous = await callWorker(null, 'GET', probe);
  if (anonymous.status === 404) {
    throw new FatalError('GET /owner-media answered 404 before authentication: the Owner media routes are not deployed on this staging version');
  }
  check('gate', 'with the key but without a session: 401 (the Owner routes are deployed)', anonymous.status === 401, `HTTP ${anonymous.status}`);
  const forged = await callWorker({ token: 'not-a-valid-session' }, 'GET', probe);
  check('gate', 'with the key and an invalid session token: 401', forged.status === 401, `HTTP ${forged.status}`);
}

async function sectionDatabase(a) {
  for (const parent of [OWNER, OFFER]) {
    const r = await rest(a, 'POST', `/rest/v1/rpc/${parent.rpc}`, rpcBody(parent, a.uid, randomUUID(), randomUUID()));
    const code = r.body?.code ?? '';
    check('database', `a signed-in client cannot execute ${parent.rpc}`,
      r.status === 401 || r.status === 403 || r.status === 404, `HTTP ${r.status} ${code}`);
    if (r.status === 404) {
      // PostgREST may hide a function the role cannot execute. The first
      // confirm below proves whether it exists (a missing one answers 502).
      note('database', `${parent.rpc} is hidden from clients or missing (${code}); the first confirm decides which`);
    }
  }
}

async function sectionOwnerAuthorize(a, owner, offer) {
  const missing = await callWorker(a, 'POST', '/owner-media/authorize', { mediaObjectId: randomUUID(), contentType: 'image/jpeg', contentLength: 100 });
  check('owner-authorize', 'without ownerRecordId: 400 invalid_request', missing.status === 400 && missing.body?.code === 'invalid_request', coded(missing));
  const unknownId = randomUUID();
  const unknown = await authorize(OWNER, a, randomUUID(), unknownId, 100, 'image/jpeg');
  check('owner-authorize', 'an Owner record that does not exist: 404 owner_not_found', unknown.status === 404 && unknown.body?.code === 'owner_not_found', coded(unknown));
  const offerAsOwner = await authorize(OWNER, a, offer, randomUUID(), 100, 'image/jpeg');
  check('owner-authorize', "the account's own Offer id sent as an Owner record: 404 owner_not_found",
    offerAsOwner.status === 404 && offerAsOwner.body?.code === 'owner_not_found', coded(offerAsOwner));
  const noRow = await mediaRows(a, unknownId);
  check('owner-authorize', 'a refused authorize creates no row', noRow?.length === 0, `${noRow?.length ?? '?'} row(s)`);
  const empty = await list(OWNER, a, owner);
  check('owner-authorize', 'a new Owner record lists no media', empty.status === 200 && empty.media.length === 0, `HTTP ${empty.status}`);
}

async function sectionOwnerImages(a, owner, images) {
  const expected = [
    ['JPEG', images.jpeg, 'image/jpeg', 'photo.jpg'],
    ['PNG', images.png, 'image/png', 'photo.png'],
    ['WebP', images.webp, 'image/webp', 'photo.webp'],
  ];
  const ids = {};
  for (const [label, bytes, type, name] of expected) {
    const out = await upload(OWNER, a, owner, { bytes, contentType: type, name });
    ids[label] = out.id;
    check('owner-image', `${label} photo: Owner authorize → private PUT → confirm`,
      uploaded(out) && out.mediaType === 'image' && out.returnedId === out.id && out.confirmedParent === owner, describe(out));
    if (out.confirmStatus === 502) {
      throw new FatalError('Owner confirm answered 502: confirm_owner_media_upload is missing or failing');
    }
  }
  const listed = await list(OWNER, a, owner);
  check('owner-image', 'listing returns the three photos, in upload order', listed.status === 200 &&
    listed.media.slice(0, 3).map((m) => m.mediaObjectId).join() === [ids.JPEG, ids.PNG, ids.WebP].join(), `HTTP ${listed.status}, ${listed.media.length} item(s)`);
  for (const [label, bytes, type] of expected) {
    const item = listed.media.find((m) => m.mediaObjectId === ids[label]);
    if (!item) {
      check('owner-image', `${label} is listed`, false);
      continue;
    }
    check('owner-image', `${label} is listed as ${type}`, item.mediaType === 'image' && item.contentType === type, `${item.mediaType} ${item.contentType}`);
    const got = await getBytes(item.url);
    check('owner-image', `${label} signed GET returns the exact bytes`, got.status === 200 && sha256(got.bytes) === sha256(bytes),
      `HTTP ${got.status}, sha256 ${sha256(got.bytes).slice(0, 16)}`);
  }
  const rows = await mediaRows(a, ids.JPEG);
  check('owner-image', 'the JPEG row is ready, image, in the staging bucket, with the real size', rows?.length === 1 &&
    rows[0].status === 'ready' && rows[0].bucket === STAGING_BUCKET && rows[0].media_type === 'image' && Number(rows[0].size_bytes) === images.jpeg.length,
  rows?.[0] ? `${rows[0].status} ${rows[0].bucket} ${rows[0].size_bytes}` : 'no row');
  const links = await linkRows(OWNER, a, ids.JPEG);
  check('owner-image', 'it is linked once in owner_media, to this Owner, at position 0', links?.length === 1 &&
    links[0].owner_record_id === owner && links[0].ordinal === 0, `${links?.length ?? '?'} link(s)`);
  return ids;
}

async function sectionOwnerVideo(a, owner, video) {
  const out = await upload(OWNER, a, owner, { bytes: video.bytes, contentType: video.type, name: video.name });
  check('owner-video', `${video.type} (${(video.bytes.length / 1048576).toFixed(2)} MiB): Owner authorize → private PUT → confirm`,
    uploaded(out) && out.mediaType === 'video', describe(out));
  const listed = await list(OWNER, a, owner);
  const item = listed.media.find((m) => m.mediaObjectId === out.id);
  check('owner-video', 'listed as a video with a server-measured duration', Boolean(item) && item.mediaType === 'video' &&
    Number.isInteger(item.durationMs) && item.durationMs > 0 && item.durationMs <= MAX_DURATION_MS,
  item ? `${item.mediaType}, ${item.durationMs} ms` : 'not listed');
  if (item) {
    const head = await getBytes(item.url, 'bytes=0-65535');
    check('owner-video', 'ranged read of the first 64 KiB answers 206 with the right bytes', head.status === 206 &&
      sha256(head.bytes) === sha256(video.bytes.subarray(0, 65536)), `HTTP ${head.status}, ${head.bytes.length} bytes`);
    const tailStart = Math.max(0, video.bytes.length - 4096);
    const tail = await getBytes(item.url, `bytes=${tailStart}-`);
    check('owner-video', 'ranged read of the last 4 KiB (a seek to the end) answers 206 with the right bytes', tail.status === 206 &&
      sha256(tail.bytes) === sha256(video.bytes.subarray(tailStart)), `HTTP ${tail.status}, ${tail.bytes.length} bytes`);
    const full = await getBytes(item.url);
    check('owner-video', 'full signed GET returns the exact bytes', full.status === 200 && sha256(full.bytes) === video.sha256,
      `HTTP ${full.status}, sha256 ${sha256(full.bytes).slice(0, 16)}`);
  }
  const rows = await mediaRows(a, out.id);
  check('owner-video', 'the row is ready, video, with duration_ms recorded', rows?.length === 1 && rows[0].status === 'ready' &&
    rows[0].media_type === 'video' && Number(rows[0].duration_ms) > 0, rows?.[0] ? `${rows[0].status} ${rows[0].media_type} ${rows[0].duration_ms}` : 'no row');
  return out.id;
}

async function sectionOwnerRetry(a, ownerOne, ownerTwo, images) {
  const id = randomUUID();
  const first = await authorize(OWNER, a, ownerOne, id, images.jpeg, 'image/jpeg');
  const second = await authorize(OWNER, a, ownerOne, id, images.jpeg, 'image/jpeg');
  if (first.status === 200) remember(OWNER, ownerOne, a, id, 'image/jpeg');
  check('owner-retry', 'authorizing the same id twice answers pending both times, for the same key', first.status === 200 && second.status === 200 &&
    first.body?.status === 'pending' && second.body?.status === 'pending' && first.body?.objectKey === second.body?.objectKey,
  `HTTP ${first.status}/${second.status}`);
  let rows = await mediaRows(a, id);
  check('owner-retry', 'exactly one media row exists for that id', rows?.length === 1 && rows[0].status === 'pending_upload', `${rows?.length ?? '?'} row(s)`);

  const early = await confirm(OWNER, a, ownerOne, id);
  check('owner-retry', 'confirm before the bytes arrive: 409 upload_incomplete, nothing marked failed', early.status === 409 &&
    early.body?.code === 'upload_incomplete', coded(early));
  rows = await mediaRows(a, id);
  check('owner-retry', 'the row is still pending_upload', rows?.[0]?.status === 'pending_upload', rows?.[0]?.status ?? 'no row');

  const put = second.status === 200 ? await putBytes(second.body.presignedUrl, images.jpeg, 'image/jpeg') : null;
  const done = await confirm(OWNER, a, ownerOne, id);
  const again = await confirm(OWNER, a, ownerOne, id);
  check('owner-retry', 'a confirm after the upload attaches it', put === 200 && done.status === 200, `PUT ${put}, confirm ${done.status}`);
  check('owner-retry', 'a repeated confirm (lost answer) reports the same position and changes nothing',
    again.status === 200 && again.body?.alreadyConfirmed === true && again.body?.ordinal === done.body?.ordinal,
    `HTTP ${again.status}, ordinal ${again.body?.ordinal} vs ${done.body?.ordinal}`);
  const links = await linkRows(OWNER, a, id);
  check('owner-retry', 'the item is linked exactly once', links?.length === 1, `${links?.length ?? '?'} link(s)`);

  const readyAgain = await authorize(OWNER, a, ownerOne, id, images.jpeg, 'image/jpeg');
  check('owner-retry', 'authorizing an attached id answers ready: nothing to upload again', readyAgain.status === 200 &&
    readyAgain.body?.status === 'ready' && !readyAgain.body?.presignedUrl, `HTTP ${readyAgain.status} ${readyAgain.body?.status ?? ''}`);
  rows = await mediaRows(a, id);
  check('owner-retry', 'still exactly one media row after every retry', rows?.length === 1 && rows[0].status === 'ready', `${rows?.length ?? '?'} row(s)`);

  const elsewhere = await authorize(OWNER, a, ownerTwo, id, images.jpeg, 'image/jpeg');
  check('owner-retry', 'the same id for another Owner record is refused (409 idempotency_mismatch)', elsewhere.status === 409 &&
    elsewhere.body?.code === 'idempotency_mismatch', coded(elsewhere));

  const other = randomUUID();
  const a1 = await authorize(OWNER, a, ownerOne, other, images.jpeg, 'image/jpeg');
  if (a1.status === 200) remember(OWNER, ownerOne, a, other, 'image/jpeg');
  const a2 = await authorize(OWNER, a, ownerOne, other, images.jpeg.length + 1, 'image/jpeg');
  check('owner-retry', 'the same id with a different size is refused (409 idempotency_mismatch)', a1.status === 200 && a2.status === 409 &&
    a2.body?.code === 'idempotency_mismatch', `HTTP ${a1.status}/${a2.status} ${a2.body?.code ?? ''}`);
  const cleaned = await remove(OWNER, a, ownerOne, other);
  rows = await mediaRows(a, other);
  check('owner-retry', 'removing that never-uploaded item deletes its row', cleaned.status === 200 && rows?.length === 0,
    `HTTP ${cleaned.status}, ${rows?.length ?? '?'} row(s)`);
}

async function sectionOwnerRefusals(a, owner, images, longVideo) {
  const spoof = randomUUID();
  const auth = await authorize(OWNER, a, owner, spoof, images.png, 'image/jpeg');
  if (auth.status === 200) remember(OWNER, owner, a, spoof, 'image/jpeg');
  const put = auth.status === 200 ? await putBytes(auth.body.presignedUrl, images.png, 'image/jpeg') : null;
  const conf = await confirm(OWNER, a, owner, spoof);
  check('owner-refuse', 'PNG bytes declared as JPEG: confirm refuses 422 media_type_mismatch', auth.status === 200 && put === 200 &&
    conf.status === 422 && conf.body?.code === 'media_type_mismatch', `authorize ${auth.status}, PUT ${put}, confirm ${coded(conf)}`);
  const rows = await mediaRows(a, spoof);
  check('owner-refuse', 'the spoofed upload is marked failed', rows?.[0]?.status === 'failed', rows?.[0]?.status ?? 'no row');
  const retry = await authorize(OWNER, a, owner, spoof, images.png, 'image/jpeg');
  check('owner-refuse', 'the refused id stays refused (409 upload_rejected)', retry.status === 409 && retry.body?.code === 'upload_rejected', coded(retry));
  const listed = await list(OWNER, a, owner);
  check('owner-refuse', 'the refused item is never listed', !listed.media.some((m) => m.mediaObjectId === spoof), `${listed.media.length} listed`);

  const bigImage = randomUUID();
  const tooBig = await authorize(OWNER, a, owner, bigImage, MAX_IMAGE_BYTES + 1, 'image/jpeg');
  check('owner-refuse', 'a photo over 10 MiB is refused before upload (image_too_large)', tooBig.status === 400 && tooBig.body?.code === 'image_too_large', coded(tooBig));
  const noRow = await mediaRows(a, bigImage);
  check('owner-refuse', 'and no row is created for it', noRow?.length === 0, `${noRow?.length ?? '?'} row(s)`);

  const bigVideo = await authorize(OWNER, a, owner, randomUUID(), MAX_VIDEO_BYTES + 1, 'video/mp4');
  check('owner-refuse', 'a video over 100 MiB is refused before upload (video_too_large)', bigVideo.status === 400 && bigVideo.body?.code === 'video_too_large', coded(bigVideo));

  const heic = await authorize(OWNER, a, owner, randomUUID(), 1000, 'image/heic');
  check('owner-refuse', 'a new HEIC upload is refused (the app converts HEIC to JPEG first)', heic.status === 400 && heic.body?.code === 'unsupported_media_type', coded(heic));

  const pdf = await authorize(OWNER, a, owner, randomUUID(), 1000, 'application/pdf');
  check('owner-refuse', 'a document is refused (Owner media is photos and videos only)', pdf.status === 400 && pdf.body?.code === 'unsupported_media_type', coded(pdf));

  if (longVideo) {
    const out = await upload(OWNER, a, owner, { bytes: longVideo.bytes, contentType: longVideo.type, name: longVideo.name });
    check('owner-refuse', 'a video over 3:01 is refused by the server after measuring it (422 video_too_long)', out.authStatus === 200 && out.putStatus === 200 &&
      out.confirmStatus === 422 && out.confirmCode === 'video_too_long', describe(out));
    const longRows = await mediaRows(a, out.id);
    check('owner-refuse', 'the over-long video is marked failed', longRows?.[0]?.status === 'failed', longRows?.[0]?.status ?? 'no row');
  } else {
    note('owner-refuse', 'over-3-minute video not run (no -LongVideoPath given)');
  }
}

async function sectionOwnerLimit(a, owner, images, video) {
  const outs = [];
  for (let i = 0; i < MAX_ITEMS; i += 1) {
    const isVideo = i === 4;
    outs.push(await upload(OWNER, a, owner, isVideo
      ? { bytes: video.bytes, contentType: video.type, name: video.name }
      : { bytes: images.jpeg, contentType: 'image/jpeg', name: `photo-${i}.jpg` }));
  }
  check('owner-limit', 'ten items (nine photos and one video) are accepted on one Owner', outs.every(uploaded),
    outs.map((o, i) => `${i}:${o.confirmStatus ?? o.authStatus}`).join(' '));
  check('owner-limit', 'they take positions 0 to 9 in order', outs.map((o) => o.ordinal).join() === '0,1,2,3,4,5,6,7,8,9',
    outs.map((o) => o.ordinal).join(','));

  const eleventh = randomUUID();
  const refused = await authorize(OWNER, a, owner, eleventh, images.jpeg, 'image/jpeg');
  check('owner-limit', 'the eleventh item is refused before upload (409 owner_media_limit_reached)', refused.status === 409 &&
    refused.body?.code === OWNER.limitCode, coded(refused));
  const noRow = await mediaRows(a, eleventh);
  check('owner-limit', 'and nothing is created for it', noRow?.length === 0, `${noRow?.length ?? '?'} row(s)`);

  const removed = await remove(OWNER, a, owner, outs[3].id);
  let listed = await list(OWNER, a, owner);
  check('owner-limit', 'removing one of the ten frees a place', removed.status === 200 && listed.media.length === MAX_ITEMS - 1,
    `HTTP ${removed.status}, ${listed.media.length} listed`);

  const retried = await upload(OWNER, a, owner, { id: eleventh, bytes: images.jpeg, contentType: 'image/jpeg', name: 'photo-11.jpg' });
  check('owner-limit', 'the same eleventh id now goes through and is appended at position 10, not into the gap',
    uploaded(retried) && retried.ordinal === 10, describe(retried));
  listed = await list(OWNER, a, owner);
  check('owner-limit', 'the Owner lists exactly ten items again', listed.media.length === MAX_ITEMS &&
    listed.media[listed.media.length - 1].mediaObjectId === eleventh, `${listed.media.length} listed`);
}

async function sectionOwnerRemove(a, owner, images) {
  const target = await upload(OWNER, a, owner, { bytes: images.png, contentType: 'image/png', name: 'remove-me.png' });
  if (!check('owner-remove', 'a PNG to remove is uploaded and ready', uploaded(target), describe(target))) return;
  const readyId = target.id;
  const before = await list(OWNER, a, owner);
  const item = before.media.find((m) => m.mediaObjectId === readyId);
  const first = await remove(OWNER, a, owner, readyId);
  check('owner-remove', 'removing a ready photo succeeds', first.status === 200 && first.body?.removed === true && !first.body?.alreadyRemoved,
    `HTTP ${first.status}${first.body?.cleanupPending ? ', cleanupPending' : ''}`);
  const after = await list(OWNER, a, owner);
  check('owner-remove', 'it is no longer listed', !after.media.some((m) => m.mediaObjectId === readyId), `${after.media.length} listed`);
  const rows = await mediaRows(a, readyId);
  check('owner-remove', 'its row is tombstoned deleted', rows?.[0]?.status === 'deleted', rows?.[0]?.status ?? 'no row');
  const links = await linkRows(OWNER, a, readyId);
  check('owner-remove', 'its owner_media link is gone', links?.length === 0, `${links?.length ?? '?'} link(s)`);
  if (item) {
    const old = await getBytes(item.url);
    check('owner-remove', 'its bytes are gone from private R2 (the earlier signed link no longer returns them)', old.status !== 200 && old.status !== 206,
      `HTTP ${old.status}`);
  }
  const second = await remove(OWNER, a, owner, readyId);
  check('owner-remove', 'removing it again is harmless (alreadyRemoved)', second.status === 200 && second.body?.alreadyRemoved === true, `HTTP ${second.status}`);
  const reAuth = await authorize(OWNER, a, owner, readyId, images.png, 'image/png');
  const reConf = await confirm(OWNER, a, owner, readyId);
  check('owner-remove', 'a removed id can never come back (410 media_removed on authorize and confirm)',
    reAuth.status === 410 && reAuth.body?.code === 'media_removed' && reConf.status === 410 && reConf.body?.code === 'media_removed',
    `HTTP ${reAuth.status}/${reConf.status}`);
  const reAuthOther = await authorize(OWNER, a, owner, readyId, images.jpeg, 'image/jpeg');
  check('owner-remove', 'a removed id reused for a different file is refused too (409 idempotency_mismatch)',
    reAuthOther.status === 409 && reAuthOther.body?.code === 'idempotency_mismatch', coded(reAuthOther));

  const pending = randomUUID();
  const auth = await authorize(OWNER, a, owner, pending, images.jpeg, 'image/jpeg');
  if (auth.status === 200) remember(OWNER, owner, a, pending, 'image/jpeg');
  const put = auth.status === 200 ? await putBytes(auth.body.presignedUrl, images.jpeg, 'image/jpeg') : null;
  const withdrawn = await remove(OWNER, a, owner, pending);
  const pendingRows = await mediaRows(a, pending);
  check('owner-remove', 'an uploaded but unconfirmed item is withdrawn: row deleted', auth.status === 200 && put === 200 &&
    withdrawn.status === 200 && pendingRows?.length === 0, `authorize ${auth.status}, PUT ${put}, remove ${withdrawn.status}, ${pendingRows?.length ?? '?'} row(s)`);
  const late = await confirm(OWNER, a, owner, pending);
  check('owner-remove', 'a confirm arriving after the withdrawal cannot attach it', late.status === 404 || late.status === 409 || late.status === 410, coded(late));
}

/** The existing Offer routes after the MEDIA_PARENTS refactor: one focused pass. */
async function sectionOfferRegression(a, offer, images) {
  const out = await upload(OFFER, a, offer, { bytes: images.jpeg, contentType: 'image/jpeg', name: 'offer.jpg' });
  check('offer', 'Offer JPEG: authorize → private PUT → confirm (unchanged routes and answers)',
    uploaded(out) && out.mediaType === 'image' && out.confirmedParent === offer, describe(out));
  if (!uploaded(out)) return null;
  const again = await confirm(OFFER, a, offer, out.id);
  check('offer', 'a repeated Offer confirm reports the same position', again.status === 200 && again.body?.alreadyConfirmed === true &&
    again.body?.ordinal === out.ordinal && again.body?.offerId === offer, `HTTP ${again.status}`);
  const listed = await list(OFFER, a, offer);
  const item = listed.media.find((m) => m.mediaObjectId === out.id);
  check('offer', 'the Offer lists it as image/jpeg', Boolean(item) && item.mediaType === 'image' && item.contentType === 'image/jpeg',
    `HTTP ${listed.status}, ${listed.media.length} item(s)`);
  if (item) {
    const got = await getBytes(item.url);
    check('offer', 'its signed GET returns the exact bytes', got.status === 200 && sha256(got.bytes) === sha256(images.jpeg), `HTTP ${got.status}`);
  }
  const links = await linkRows(OFFER, a, out.id);
  check('offer', 'linked once in offer_media, to this Offer', links?.length === 1 && links[0].offer_id === offer, `${links?.length ?? '?'} link(s)`);

  const png = await upload(OFFER, a, offer, { bytes: images.png, contentType: 'image/png', name: 'offer-remove.png' });
  const removed = uploaded(png) ? await remove(OFFER, a, offer, png.id) : { status: null };
  const rows = await mediaRows(a, png.id);
  check('offer', 'removing an Offer photo tombstones it deleted', uploaded(png) && removed.status === 200 && rows?.[0]?.status === 'deleted',
    `${describe(png)}, remove ${removed.status}, ${rows?.[0]?.status ?? 'no row'}`);
  const back = await authorize(OFFER, a, offer, png.id, images.png, 'image/png');
  check('offer', 'a removed Offer media id answers 410 media_removed', back.status === 410 && back.body?.code === 'media_removed', coded(back));
  const unknown = await list(OFFER, a, randomUUID());
  check('offer', 'an unknown Offer still answers 404 offer_not_found', unknown.status === 404 && unknown.code === 'offer_not_found', coded(unknown));
  return out.id;
}

/** One account, three parents: nothing crosses between Owners, or between Owners and Offers. */
async function sectionCrossParent(a, ownerOne, ownerTwo, offer, ownerMediaId, offerMediaId, images) {
  const cases = [
    ["an Offer's media on the Owner routes", OWNER, ownerOne, offerMediaId],
    ["an Owner's media on the Offer routes", OFFER, offer, ownerMediaId],
    ["one Owner's media on another Owner's routes", OWNER, ownerTwo, ownerMediaId],
  ];
  for (const [label, parent, parentId, mediaId] of cases) {
    if (!mediaId) {
      check('cross-parent', `${label}: prerequisite media exists`, false, 'an earlier section did not produce it');
      continue;
    }
    const auth = await authorize(parent, a, parentId, mediaId, images.jpeg, 'image/jpeg');
    check('cross-parent', `${label}: authorize refused (409 idempotency_mismatch)`, auth.status === 409 && auth.body?.code === 'idempotency_mismatch', coded(auth));
    const conf = await confirm(parent, a, parentId, mediaId);
    check('cross-parent', `${label}: confirm refused (409 media_mismatch)`, conf.status === 409 && conf.body?.code === 'media_mismatch', coded(conf));
    const rem = await remove(parent, a, parentId, mediaId);
    check('cross-parent', `${label}: remove refused (409 media_mismatch)`, rem.status === 409 && rem.body?.code === 'media_mismatch', coded(rem));
    const listed = await list(parent, a, parentId);
    check('cross-parent', `${label}: never listed there`, listed.status === 200 && !listed.media.some((m) => m.mediaObjectId === mediaId),
      `HTTP ${listed.status}, ${listed.media.length} listed`);
  }
  const ownerAsOffer = await list(OFFER, a, ownerOne);
  check('cross-parent', 'an Owner record id on the Offer routes: 404 offer_not_found', ownerAsOffer.status === 404 && ownerAsOffer.code === 'offer_not_found', coded(ownerAsOffer));
  const offerAsOwner = await list(OWNER, a, offer);
  check('cross-parent', 'an Offer id on the Owner routes: 404 owner_not_found', offerAsOwner.status === 404 && offerAsOwner.code === 'owner_not_found', coded(offerAsOwner));

  const ownerStill = await list(OWNER, a, ownerOne);
  const offerStill = await list(OFFER, a, offer);
  const ownerRow = ownerMediaId ? await mediaRows(a, ownerMediaId) : null;
  const offerRow = offerMediaId ? await mediaRows(a, offerMediaId) : null;
  check('cross-parent', 'both items are still ready and listed where they belong', ownerStill.media.some((m) => m.mediaObjectId === ownerMediaId) &&
    offerStill.media.some((m) => m.mediaObjectId === offerMediaId) && ownerRow?.[0]?.status === 'ready' && offerRow?.[0]?.status === 'ready',
  `${ownerRow?.[0]?.status ?? 'no row'} / ${offerRow?.[0]?.status ?? 'no row'}`);
}

async function sectionCrossAccount(a, b, ownerOfA, mediaOfA, ownerOfB, images) {
  const listed = await list(OWNER, b, ownerOfA);
  check('cross-account', "B cannot list A's Owner media (404 owner_not_found)", listed.status === 404 && listed.code === 'owner_not_found', coded(listed));
  const auth = await authorize(OWNER, b, ownerOfA, randomUUID(), images.jpeg, 'image/jpeg');
  check('cross-account', "B cannot authorize an upload to A's Owner (404)", auth.status === 404, coded(auth));
  const conf = await confirm(OWNER, b, ownerOfA, mediaOfA);
  check('cross-account', "B cannot confirm A's Owner media (404)", conf.status === 404, coded(conf));
  const rem = await remove(OWNER, b, ownerOfA, mediaOfA);
  check('cross-account', "B cannot remove A's Owner media (404)", rem.status === 404, coded(rem));
  const steal = await authorize(OWNER, b, ownerOfB, mediaOfA, images.jpeg, 'image/jpeg');
  check('cross-account', "B cannot take over A's media id on B's own Owner (409 media_id_conflict)", steal.status === 409 &&
    steal.body?.code === 'media_id_conflict', coded(steal));
  const stealRemove = await remove(OWNER, b, ownerOfB, mediaOfA);
  check('cross-account', "B removing A's media id through B's own Owner reveals and changes nothing (alreadyRemoved)",
    stealRemove.status === 200 && stealRemove.body?.alreadyRemoved === true, `HTTP ${stealRemove.status}`);
  const rows = await mediaRows(b, mediaOfA);
  check('cross-account', "B cannot read A's media rows (RLS)", rows?.length === 0, `${rows?.length ?? '?'} row(s)`);
  const links = await rest(b, 'GET', `/rest/v1/owner_media?owner_record_id=eq.${ownerOfA}&select=media_id`);
  check('cross-account', "B cannot read A's owner_media links (RLS)", links.status === 200 && Array.isArray(links.body) && links.body.length === 0,
    `HTTP ${links.status}, ${Array.isArray(links.body) ? links.body.length : '?'} row(s)`);
  const ownerRow = await rest(b, 'GET', `/rest/v1/owners?id=eq.${ownerOfA}&select=id`);
  check('cross-account', "B cannot read A's Owner record (RLS)", ownerRow.status === 200 && Array.isArray(ownerRow.body) && ownerRow.body.length === 0,
    `HTTP ${ownerRow.status}`);
  const rpc = await rest(b, 'POST', `/rest/v1/rpc/${OWNER.rpc}`, rpcBody(OWNER, a.uid, ownerOfA, mediaOfA));
  check('cross-account', 'B cannot call confirm_owner_media_upload directly', rpc.status === 401 || rpc.status === 403 || rpc.status === 404,
    `HTTP ${rpc.status} ${rpc.body?.code ?? ''}`);
  const stillThere = await list(OWNER, a, ownerOfA);
  const row = await mediaRows(a, mediaOfA);
  check('cross-account', "A's media is untouched by all of it", stillThere.status === 200 &&
    stillThere.media.some((m) => m.mediaObjectId === mediaOfA) && row?.[0]?.status === 'ready', `${stillThere.media.length} listed`);
}

/**
 * The profile-image routes, without replacing anything: reads, refusals and
 * one authorize that is never uploaded or confirmed. The account's profile
 * photo (if any) is compared before and after, never changed.
 * Returns the id of the pending (never confirmed) profile upload, or null.
 */
async function sectionProfile(a, images) {
  const before = await callWorker(a, 'GET', '/profile-image-url');
  check('profile', 'the profile image lookup answers 200', before.status === 200, `HTTP ${before.status}`);
  const beforeId = before.body?.profileMediaId ?? null;
  note('profile', beforeId
    ? 'the account has a profile photo: it is only read, never replaced'
    : 'the account has no profile photo: none is set by this run');
  if (before.body?.profileImageUrl) {
    const got = await getBytes(before.body.profileImageUrl);
    check('profile', 'the existing profile photo downloads through its signed link (read only)', got.status === 200 && got.bytes.length > 0, `HTTP ${got.status}`);
  }
  const anonymous = await callWorker(null, 'GET', '/profile-image-url');
  check('profile', 'the profile image lookup without a session: 401', anonymous.status === 401, `HTTP ${anonymous.status}`);
  const video = await callWorker(a, 'POST', '/authorize', { contentType: 'video/mp4', contentLength: 1000 });
  check('profile', 'profile images stay image-only (a video is refused, 400)', video.status === 400, `HTTP ${video.status}`);
  const foreign = await callWorker(a, 'POST', '/authorize', { userId: randomUUID(), contentType: 'image/jpeg', contentLength: images.jpeg.length });
  check('profile', 'a body userId that is not the signed-in account is refused (403)', foreign.status === 403, `HTTP ${foreign.status}`);

  const auth = await callWorker(a, 'POST', '/authorize', { contentType: 'image/jpeg', contentLength: images.jpeg.length, originalFileName: 'avatar.jpg' });
  const id = auth.status === 200 ? auth.body?.mediaObjectId : null;
  check('profile', 'profile authorize issues a private upload directly under the account prefix (never uploaded or confirmed here)',
    auth.status === 200 && typeof auth.body?.presignedUrl === 'string' && Boolean(id) && auth.body?.objectKey === `profiles/${a.uid}/${id}.jpg`,
    `HTTP ${auth.status}`);
  if (id) created.media.push({ id, parent: 'profile (pending, never confirmed)', parentId: null, account: a.label, contentType: 'image/jpeg' });
  const rows = id ? await mediaRows(a, id) : null;
  check('profile', 'that row is pending_upload and is not the profile photo', rows?.[0]?.status === 'pending_upload' && id !== beforeId,
    rows?.[0]?.status ?? 'no row');
  const after = await callWorker(a, 'GET', '/profile-image-url');
  check('profile', 'the profile photo is unchanged after the run', after.status === 200 && (after.body?.profileMediaId ?? null) === beforeId,
    `HTTP ${after.status}`);
  return id;
}

/**
 * Phase 1 of the F1 check: one abandoned upload (authorized, never uploaded)
 * per entity — two of A's Owners, one of A's Offers, A's profile image and one
 * of B's Owners — then proves a fresh authorize withdraws none of them while
 * they are recent. Phase 2 (f1-verify) needs them older than 24 h.
 */
async function sectionF1Seed(a, b, ownerOfB, profilePendingId, images) {
  const records = {
    ownerOne: await createOwner(a, 'F1-owner-one'),
    ownerTwo: await createOwner(a, 'F1-owner-two'),
    offer: await createOffer(a, 'F1-offer'),
    ownerOfB,
  };
  const seeds = {};
  const seed = async (label, parent, session, parentId) => {
    const id = randomUUID();
    const r = await authorize(parent, session, parentId, id, images.jpeg, 'image/jpeg', `f1-${label}.jpg`);
    const ok = r.status === 200 && r.body?.status === 'pending';
    check('f1-seed', `abandoned upload seeded for ${label} (authorized, never uploaded)`, ok, coded(r));
    if (ok) {
      remember(parent, parentId, session, id, 'image/jpeg');
      seeds[label] = { id, parent: parent.name, parentId, account: session.label };
    }
  };
  await seed('ownerOne', OWNER, a, records.ownerOne);
  await seed('ownerTwo', OWNER, a, records.ownerTwo);
  await seed('offer', OFFER, a, records.offer);
  await seed('accountB', OWNER, b, records.ownerOfB);
  if (profilePendingId) {
    seeds.profile = { id: profilePendingId, parent: 'profile', parentId: null, account: a.label };
    check('f1-seed', 'abandoned upload seeded for profile (the profile section\'s never-confirmed authorize)', true);
  } else {
    check('f1-seed', 'abandoned upload seeded for profile', false, 'the profile section produced no pending upload');
  }

  // Recent uploads are never withdrawn, whatever the entity.
  const trigger = randomUUID();
  const t = await authorize(OWNER, a, records.ownerOne, trigger, images.jpeg, 'image/jpeg', 'f1-trigger.jpg');
  if (t.status === 200) remember(OWNER, records.ownerOne, a, trigger, 'image/jpeg');
  const sessions = { A: a, B: b };
  let allPending = t.status === 200;
  for (const [label, s] of Object.entries(seeds)) {
    const rows = await mediaRows(sessions[s.account], s.id);
    if (rows?.[0]?.status !== 'pending_upload') allPending = false;
    if (rows?.[0]?.status !== 'pending_upload') note('f1-seed', `${label} is ${rows?.[0]?.status ?? 'missing'} after the trigger`);
  }
  check('f1-seed', 'a fresh Owner authorize withdraws none of the recent abandoned uploads', allPending, `trigger ${coded(t)}`);
  const withdrawn = await remove(OWNER, a, records.ownerOne, trigger);
  const gone = await mediaRows(a, trigger);
  check('f1-seed', 'the trigger upload is withdrawn again', withdrawn.status === 200 && gone?.length === 0, `HTTP ${withdrawn.status}`);

  const state = {
    kind: 'owner-media-f1-state',
    runId: RUN_ID,
    seededAt: new Date().toISOString(),
    earliestVerifyAt: new Date(Date.now() + PENDING_CLEANUP_AGE_MS + F1_MARGIN_MS).toISOString(),
    workerHost: new URL(cfg.workerUrl).host,
    accounts: { A: fingerprint(a.uid), B: fingerprint(b.uid) },
    records,
    seeds,
  };
  const stateFile = `f1_state_${RUN_ID}.json`;
  writeFileSync(join(REPORTS, stateFile), JSON.stringify(state, null, 2));
  note('f1-seed', `F1 phase 2 state written to reports/${stateFile}; run -Mode F1Verify after ${state.earliestVerifyAt}`);
  return stateFile;
}

// ---------------------------------------------------------------------------
// F1 phase 2
// ---------------------------------------------------------------------------

async function runF1Verify(images) {
  let state;
  try {
    state = JSON.parse(readFileSync(cfg.statePath, 'utf8'));
  } catch (_) {
    console.error('The F1 state file could not be read.');
    process.exit(2);
  }
  if (state?.kind !== 'owner-media-f1-state' || !state.seeds || !state.records) {
    console.error('That file is not an Owner media F1 state file.');
    process.exit(2);
  }
  if (state.workerHost !== new URL(cfg.workerUrl).host) {
    console.error('The F1 state file was written against a different Worker host.');
    process.exit(2);
  }
  console.log(`F1 phase 2 for phase 1 run ${state.runId}\n`);

  const a = await signIn('A', cfg.a);
  const b = await signIn('B', cfg.b);
  if (!check('f1-verify', 'account A is the account that seeded phase 1', fingerprint(a.uid) === state.accounts.A) ||
    !check('f1-verify', 'account B is the account that seeded phase 1', fingerprint(b.uid) === state.accounts.B)) {
    throw new FatalError('sign in with the same two accounts as the phase 1 run');
  }
  const sessions = { A: a, B: b };
  const seeds = state.seeds;
  const expected = ['ownerOne', 'ownerTwo', 'offer', 'profile', 'accountB'];
  // undefined: never seeded; null: no row (withdrawn); otherwise the row.
  const status = async (label) => (seeds[label]
    ? (await mediaRows(sessions[seeds[label].account], seeds[label].id))?.[0] ?? null
    : undefined);
  const shown = (row) => (row === undefined ? 'not seeded' : row?.status ?? 'deleted');

  // Preconditions: every seed exists, is still pending and is old enough.
  // Nothing is changed unless all of them hold.
  check('f1-verify', 'phase 1 seeded all five abandoned uploads', expected.every((label) => seeds[label]),
    `seeded: ${Object.keys(seeds).join(', ') || 'none'}`);
  let tooYoung = null;
  for (const label of Object.keys(seeds)) {
    const row = await status(label);
    check('f1-verify', `${label}: the seeded upload is still pending_upload before any trigger`, row?.status === 'pending_upload', row?.status ?? 'missing');
    const age = row ? Date.now() - Date.parse(row.created_at) : 0;
    if (row && age < PENDING_CLEANUP_AGE_MS + F1_MARGIN_MS) tooYoung = label;
  }
  if (tooYoung) {
    note('f1-verify', `too early: ${tooYoung} is not yet 24 h 10 min old; run again after ${state.earliestVerifyAt}. Nothing was changed.`);
    return 3;
  }
  if (results.some((r) => r.ok === false)) {
    throw new FatalError('a seeded upload is missing before any trigger (are the sweeps really off?); the check cannot decide');
  }

  const expectPending = async (step, labels) => {
    for (const label of labels) {
      const row = await status(label);
      check('f1-verify', `${step}: ${label}'s abandoned upload is left alone`, row?.status === 'pending_upload', shown(row));
    }
  };
  const expectGone = async (step, label) => {
    const row = await status(label);
    check('f1-verify', `${step}: its own abandoned upload (${label}) is withdrawn`, row === null, shown(row));
  };
  const triggerParent = async (step, parent, parentId) => {
    const id = randomUUID();
    const r = await authorize(parent, a, parentId, id, images.jpeg, 'image/jpeg', 'f1-trigger.jpg');
    const ok = check('f1-verify', `${step}: the trigger authorize succeeds`, r.status === 200 && r.body?.status === 'pending', coded(r));
    if (ok) remember(parent, parentId, a, id, 'image/jpeg');
    return async () => {
      if (!ok) return;
      const w = await remove(parent, a, parentId, id);
      const row = await mediaRows(a, id);
      check('f1-verify', `${step}: the trigger upload is withdrawn again`, w.status === 200 && row?.length === 0, `HTTP ${w.status}`);
    };
  };

  let step = "authorize on A's first Owner";
  let withdraw = await triggerParent(step, OWNER, state.records.ownerOne);
  await expectGone(step, 'ownerOne');
  await expectPending(step, ['ownerTwo', 'offer', 'profile', 'accountB']);
  await withdraw();

  step = "authorize on A's Offer";
  withdraw = await triggerParent(step, OFFER, state.records.offer);
  await expectGone(step, 'offer');
  await expectPending(step, ['ownerTwo', 'profile', 'accountB']);
  await withdraw();

  step = "authorize of A's profile image";
  const photoBefore = await callWorker(a, 'GET', '/profile-image-url');
  const p = await callWorker(a, 'POST', '/authorize', { contentType: 'image/jpeg', contentLength: images.jpeg.length, originalFileName: 'f1-trigger.jpg' });
  check('f1-verify', `${step}: the trigger authorize succeeds (never uploaded or confirmed)`, p.status === 200, `HTTP ${p.status}`);
  if (p.status === 200) {
    created.media.push({ id: p.body?.mediaObjectId, parent: 'profile (pending, never confirmed)', parentId: null, account: a.label, contentType: 'image/jpeg' });
  }
  await expectGone(step, 'profile');
  await expectPending(step, ['ownerTwo', 'accountB']);
  const photoAfter = await callWorker(a, 'GET', '/profile-image-url');
  check('f1-verify', `${step}: the profile photo is unchanged`, photoBefore.status === 200 && photoAfter.status === 200 &&
    (photoBefore.body?.profileMediaId ?? null) === (photoAfter.body?.profileMediaId ?? null), `HTTP ${photoBefore.status}/${photoAfter.status}`);

  step = "authorize on A's second Owner";
  withdraw = await triggerParent(step, OWNER, state.records.ownerTwo);
  await expectGone(step, 'ownerTwo');
  await expectPending(step, ['accountB']);
  await withdraw();

  // Account B's abandoned upload survived every one of A's authorizes; B
  // withdraws it now, which leaves no seeded row behind.
  const own = await remove(OWNER, b, state.records.ownerOfB, seeds.accountB.id);
  const left = await status('accountB');
  check('f1-verify', "B withdraws its own seeded upload afterwards (cleanup of the check's data)", own.status === 200 && left === null,
    `HTTP ${own.status}, ${shown(left)}`);
  return 0;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function section(name, fn) {
  try {
    return await fn();
  } catch (error) {
    check(name, 'section completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
    if (error instanceof FatalError) throw error;
    return undefined;
  }
}

function writeReport(extra = {}) {
  const pass = results.filter((r) => r.ok === true).length;
  const fail = results.filter((r) => r.ok === false).length;
  const report = {
    runId: RUN_ID,
    mode: cfg.mode,
    startedAt,
    finishedAt: new Date().toISOString(),
    workerHost: new URL(cfg.workerUrl).host,
    bucket: STAGING_BUCKET,
    summary: { pass, fail },
    ...extra,
    results,
    created,
  };
  writeFileSync(cfg.reportPath, JSON.stringify(report, null, 2));
  console.log(`\n${fail === 0 ? 'ALL PASSED' : 'FAILURES'}: ${pass} passed, ${fail} failed. Report: ${cfg.reportPath}`);
  return fail;
}

async function runFull(images) {
  const video = loadVideo(cfg.videoPath);
  if (!video.type) {
    console.error('The video file is not an MP4, MOV or 3GP container.');
    process.exit(2);
  }
  const longVideo = cfg.longVideoPath ? loadVideo(cfg.longVideoPath) : null;
  let f1StatePath = null;

  try {
    await section('gate', sectionGate);
    const a = await signIn('A', cfg.a);
    const b = await signIn('B', cfg.b);
    if (!check('setup', 'accounts A and B are different accounts', a.uid !== b.uid)) {
      throw new FatalError('A and B must be two different disposable accounts');
    }
    await section('database', () => sectionDatabase(a));

    const ownerOne = await createOwner(a, 'A1');
    const ownerTwo = await createOwner(a, 'A2');
    const ownerLimit = await createOwner(a, 'A3-limit');
    const offer = await createOffer(a, 'A-offer');
    const ownerOfB = await createOwner(b, 'B1');

    await section('owner-authorize', () => sectionOwnerAuthorize(a, ownerOne, offer));
    const imageIds = (await section('owner-image', () => sectionOwnerImages(a, ownerOne, images))) ?? {};
    const videoId = await section('owner-video', () => sectionOwnerVideo(a, ownerOne, video));
    await section('owner-retry', () => sectionOwnerRetry(a, ownerOne, ownerTwo, images));
    await section('owner-refuse', () => sectionOwnerRefusals(a, ownerOne, images, longVideo));
    await section('owner-limit', () => sectionOwnerLimit(a, ownerLimit, images, video));
    await section('owner-remove', () => sectionOwnerRemove(a, ownerOne, images));
    const offerMediaId = await section('offer', () => sectionOfferRegression(a, offer, images));
    await section('cross-parent', () => sectionCrossParent(a, ownerOne, ownerTwo, offer, imageIds.JPEG, offerMediaId, images));
    await section('cross-account', () => sectionCrossAccount(a, b, ownerOne, videoId ?? imageIds.JPEG, ownerOfB, images));
    const profilePending = await section('profile', () => sectionProfile(a, images));
    f1StatePath = await section('f1-seed', () => sectionF1Seed(a, b, ownerOfB, profilePending, images));
  } catch (error) {
    check('run', 'run completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
  }
  return writeReport({ f1StateFile: f1StatePath }) === 0 ? 0 : 1;
}

async function offlineCheck() {
  const images = loadImages();
  const mp4Head = Buffer.alloc(32);
  mp4Head.writeUInt32BE(24, 0);
  mp4Head.write('ftypisom', 4, 'latin1');
  mp4Head.write('isommp42', 16, 'latin1');
  const movHead = Buffer.alloc(32);
  movHead.writeUInt32BE(20, 0);
  movHead.write('ftypqt  ', 4, 'latin1');
  const ok = images.jpeg[0] === 0xff && images.jpeg[1] === 0xd8 && images.png[0] === 0x89 && images.webp.toString('latin1', 8, 12) === 'WEBP' &&
    detectVideoType(mp4Head) === 'video/mp4' && detectVideoType(movHead) === 'video/quicktime' && detectVideoType(images.png) === null &&
    sanitize('see https://x.test/a?X-Amz-Signature=abc now') === 'see <url> now' &&
    sanitize('token eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl end') === 'token <jwt> end' &&
    fingerprint('00000000-0000-4000-8000-000000000000').length === 16 &&
    STAGING_URL_PATTERN.test('https://r2-profile-upload-staging.example.workers.dev') &&
    !STAGING_URL_PATTERN.test('https://media-api.brokerwallet.ae');
  console.log(ok ? 'OFFLINE CHECK PASSED' : 'OFFLINE CHECK FAILED');
  if (env.BW_E2E_VIDEO_PATH) {
    const video = loadVideo(env.BW_E2E_VIDEO_PATH);
    console.log(`video: ${video.type ?? 'not a supported container'}, ${video.bytes.length} bytes`);
  }
  process.exit(ok ? 0 : 1);
}

async function main() {
  if (env.BW_E2E_OFFLINE_CHECK === '1') return offlineCheck();
  cfg = loadConfig();
  mkdirSync(REPORTS, { recursive: true });
  const images = loadImages();
  startedAt = new Date().toISOString();
  console.log(`Owner media staging acceptance ${RUN_ID} (${cfg.mode}) against ${new URL(cfg.workerUrl).host}\n`);

  if (cfg.mode === 'full') {
    process.exit(await runFull(images));
  }
  let code;
  try {
    code = await runF1Verify(images);
  } catch (error) {
    check('run', 'run completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
    code = 1;
  }
  const fail = writeReport({ f1StateFile: basename(cfg.statePath) });
  process.exit(code === 3 ? 3 : fail === 0 && code === 0 ? 0 : 1);
}

main();
