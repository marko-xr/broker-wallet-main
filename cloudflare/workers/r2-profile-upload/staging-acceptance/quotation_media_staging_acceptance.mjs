// Broker Wallet — Quotation private media staging acceptance.
//
// Run it only through run_quotation_media_staging_acceptance.ps1, in the
// owner's own terminal, against the STAGING Worker (`r2-profile-upload-staging`,
// private bucket `broker-wallet-media-staging`). The launcher hands the staging
// gate key and the two test accounts' credentials to this process alone.
//
// Output and the JSON report hold PASS/FAIL per check, HTTP statuses, Worker
// codes and record/media ids. Never a token, key, password, email, object key,
// presigned PUT URL or signed GET URL.
//
// Accounts:
//   A  the designated test-only account (uid must equal BW_E2E_A_UID, default
//      317d7619-01da-4420-8c7f-fe7c3fc2d6e7). Owns every Quotation under test.
//   B  a temporary second account, used only for the cross-user checks.
//
// Every Quotation / Offer / Owner record it creates is new and disposable
// (titles and names start "staging-e2e"). It never modifies a row it did not
// create and never confirms a profile image. It leaves its records in place
// (the sweeps are off); the report lists their ids for the narrow cleanup.
//
// BW_E2E_OFFLINE_CHECK=1 exercises the local helpers only (no network).
// Node built-ins only: no `npm install` is needed.

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const STAGING_BUCKET = 'broker-wallet-media-staging';
const STAGING_HEADER = 'X-Broker-Wallet-Staging-Key';
const STAGING_URL_PATTERN = /^https:\/\/r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$/;
const DESIGNATED_A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const R2_HOST_SUFFIX = '.r2.cloudflarestorage.com';
const MAX_LOGO_BYTES = 10 * 1024 * 1024;
const MAX_PDF_BYTES = 20 * 1024 * 1024;
const PUT_TTL = 300;
const GET_TTL = 900;

const ROLES = Object.freeze({
  office_logo: { link: 'logo', column: 'office_logo_media_id', mediaType: 'image', folder: 'office_logo' },
  quotation_pdf: { link: 'pdf', column: 'pdf_media_id', mediaType: 'pdf', folder: 'quotation_pdf' },
});
const EXTENSIONS = Object.freeze({
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf',
});
const OFFER = Object.freeze({
  name: 'Offer', route: '/offer-media', idField: 'offerId', linkTable: 'offer_media', linkColumn: 'offer_id',
  segment: 'offers', notFound: 'offer_not_found',
});
const OWNER = Object.freeze({
  name: 'Owner', route: '/owner-media', idField: 'ownerRecordId', linkTable: 'owner_media', linkColumn: 'owner_record_id',
  segment: 'owners', notFound: 'owner_not_found',
});

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');
const RUN_ID = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

const results = [];
const created = { quotations: [], media: [], offers: [], owners: [] };
let cfg;
let startedAt;

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
export function sanitize(value) {
  return String(value ?? '')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<jwt>')
    .slice(0, 300);
}

class StepError extends Error {}
/** Stops the whole run: continuing would only create rows that cannot finish. */
class FatalError extends StepError {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function loadImages() {
  const fixture = (name) => readFileSync(join(HERE, 'fixtures', name));
  return { jpeg: fixture('photo.jpg'), png: fixture('photo.png'), webp: fixture('photo.webp') };
}

/** Same format, different bytes: trailing data after a JPEG/PNG is ignored by readers. */
function variant(bytes) {
  return Buffer.concat([bytes, randomBytes(16)]);
}

/** A minimal, structurally plain PDF whose bytes are unique per [label]. */
export function makePdf(label) {
  const text = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' +
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' +
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n' +
    `% staging-e2e ${label} ${randomUUID()}\n` +
    'trailer\n<< /Root 1 0 R /Size 4 >>\n%%EOF\n';
  return Buffer.from(text, 'latin1');
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

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
    // Auth's fixed reason code only; never the email or anything the caller sent.
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

async function getBytes(url) {
  const res = await timedFetch(url, {}, 600_000);
  return { status: res.status, bytes: Buffer.from(await res.arrayBuffer()) };
}

// ---------------------------------------------------------------------------
// Quotation operations
// ---------------------------------------------------------------------------

const qAuthorize = (s, quotationId, role, expectedMediaId, mediaObjectId, contentType, contentLength, originalFileName = 'e2e') =>
  callWorker(s, 'POST', '/quotation-media/authorize',
    { quotationId, role, expectedMediaId, mediaObjectId, contentType, contentLength, originalFileName });
const qConfirm = (s, quotationId, role, mediaObjectId, expectedMediaId) =>
  callWorker(s, 'POST', '/quotation-media/confirm', { quotationId, role, mediaObjectId, expectedMediaId }, { timeout: 120_000 });
const qRemove = (s, quotationId, role, expectedMediaId, mediaObjectId) =>
  callWorker(s, 'POST', '/quotation-media/remove',
    { quotationId, role, expectedMediaId, ...(mediaObjectId ? { mediaObjectId } : {}) });
const qList = (s, quotationId) => callWorker(s, 'GET', `/quotation-media?quotationId=${quotationId}`);

function coded(r) {
  return `HTTP ${r.status}${r.body?.code ? ` ${r.body.code}` : ''}`;
}

/** The exact private key the Worker must issue for an upload. */
function expectedKey(uid, quotationId, role, mediaId, contentType) {
  return `profiles/${uid}/quotations/${quotationId}/${ROLES[role].folder}/${mediaId}.${EXTENSIONS[contentType]}`;
}

/** A signed URL is short-lived, signed, and addresses the private staging bucket and exactly [objectKey]. */
function isPrivateStagingUrl(url, objectKey, ttl) {
  try {
    const u = new URL(url);
    const encoded = objectKey.split('/').map(encodeURIComponent).join('/');
    return u.protocol === 'https:' && u.hostname.endsWith(cfg.r2HostSuffix) &&
      u.pathname === `/${STAGING_BUCKET}/${encoded}` &&
      u.searchParams.get('X-Amz-Expires') === String(ttl) && u.searchParams.has('X-Amz-Signature');
  } catch (_) {
    return false;
  }
}

function unsigned(url) {
  const u = new URL(url);
  u.search = '';
  return u.toString();
}

function rememberMedia(session, quotationId, role, id, contentType) {
  created.media.push({ id, role, quotationId, account: session.label, contentType });
}

/** authorize (+ private PUT). Confirm is separate, so stale and mismatch cases can be driven. */
async function stage(s, quotationId, role, expectedMediaId, bytes, contentType, { id = randomUUID(), name = 'e2e', put = true } = {}) {
  const out = { id, role, quotationId, bytes, contentType };
  const auth = await qAuthorize(s, quotationId, role, expectedMediaId, id, contentType, bytes.length, name);
  out.authStatus = auth.status;
  out.authCode = auth.body?.code;
  out.authBody = auth.body;
  if (auth.status !== 200 || auth.body?.status !== 'pending') return out;
  rememberMedia(s, quotationId, role, id, contentType);
  out.url = auth.body.presignedUrl;
  out.objectKey = auth.body.objectKey;
  if (put) out.putStatus = await putBytes(out.url, bytes, contentType);
  return out;
}

async function bind(s, out, expectedMediaId) {
  const conf = await qConfirm(s, out.quotationId, out.role, out.id, expectedMediaId);
  out.confirmStatus = conf.status;
  out.confirmBody = conf.body;
  return conf;
}

function describe(out) {
  return `authorize ${out.authStatus}${out.authCode ? ` ${out.authCode}` : ''}` +
    (out.putStatus !== undefined ? `, PUT ${out.putStatus}` : '') +
    (out.confirmStatus !== undefined ? `, confirm ${out.confirmStatus}${out.confirmBody?.code ? ` ${out.confirmBody.code}` : ''}` : '');
}

// ---------------------------------------------------------------------------
// Hosted read-back (through the signed-in account's own RLS)
// ---------------------------------------------------------------------------

async function qState(s, id) {
  const r = await rest(s, 'GET', `/rest/v1/quotations?id=eq.${id}&select=id,owner_id,version,deleted_at,office_logo_media_id,pdf_media_id`);
  return { status: r.status, row: Array.isArray(r.body) ? (r.body[0] ?? null) : undefined, raw: r.body };
}

/** The row, `null` when RLS hides it / it does not exist, `undefined` when the read failed. */
async function mediaRow(s, id) {
  const r = await rest(s, 'GET', `/rest/v1/media_objects?id=eq.${id}&select=id,owner_id,bucket,object_key,media_type,content_type,size_bytes,status`);
  return r.status === 200 && Array.isArray(r.body) ? (r.body[0] ?? null) : undefined;
}

async function linkRows(s, quotationId) {
  const r = await rest(s, 'GET', `/rest/v1/quotation_media?quotation_id=eq.${quotationId}&select=quotation_id,media_id,role,ordinal`);
  return r.status === 200 && Array.isArray(r.body) ? r.body : null;
}

async function version(s, id) {
  const st = await qState(s, id);
  return st.row ? Number(st.row.version) : NaN;
}

const RETIRED = ['pending_delete', 'deleted'];

async function saveQuotation(s, id, label) {
  const r = await rest(s, 'POST', '/rest/v1/rpc/save_quotation', {
    p_quotation_id: id,
    p_expected_version: null,
    p_header: {
      property_title: `staging-e2e ${RUN_ID} ${label}`, property_type: null, parking: null, subtitle: null,
      display_date: null, start_date_text: null, end_date_text: null, currency_code: 'AED',
      professional_fee: null, total_amount: null, number_of_installments: null, payment_type: null,
      insurance_amount: null, insurance_returnable: null, office_name: 'staging-e2e',
      custom_note: null, welcome_message_mode: 'auto', custom_welcome_message: null,
    },
    p_downpayments: [],
    p_government_fees: null,
    p_administrative_fees: [],
  });
  const row = Array.isArray(r.body) ? r.body[0] : r.body;
  return { status: r.status, row, body: r.body };
}

async function createQuotation(s, label) {
  const id = randomUUID();
  const saved = await saveQuotation(s, id, label);
  const ok = saved.status === 200 && saved.row?.quotation_id === id && Number(saved.row?.resulting_version) === 1;
  check('setup', `temporary Quotation ${label} created through save_quotation by ${s.label}`, ok,
    `HTTP ${saved.status} v${saved.row?.resulting_version ?? '?'} ${saved.row?.outcome ?? ''} id ${id}`);
  if (!ok) throw new FatalError(`could not create Quotation ${label}`);
  created.quotations.push({ label, id, account: s.label });
  const st = await qState(s, id);
  check('setup', `Quotation ${label} reads back: owned by ${s.label}, live, version 1, no media`,
    st.row?.owner_id === s.uid && st.row.deleted_at === null && Number(st.row.version) === 1 &&
    st.row.office_logo_media_id === null && st.row.pdf_media_id === null,
    st.row ? `v${st.row.version}` : `HTTP ${st.status}`);
  return id;
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

async function sectionGate() {
  const probe = `/quotation-media?quotationId=${randomUUID()}`;
  const none = await callWorker(null, 'GET', probe, undefined, { key: null });
  check('gate', 'without the staging key: 403', none.status === 403, `HTTP ${none.status}`);
  const wrong = await callWorker(null, 'GET', probe, undefined, { key: `wrong-${randomUUID()}` });
  check('gate', 'with a wrong staging key: 403', wrong.status === 403, `HTTP ${wrong.status}`);
  for (const route of ['authorize', 'confirm', 'remove']) {
    const r = await callWorker(null, 'POST', `/quotation-media/${route}`, {}, { key: null });
    check('gate', `Quotation ${route} without the staging key: 403`, r.status === 403, `HTTP ${r.status}`);
  }
  const anonymous = await callWorker(null, 'GET', probe);
  if (anonymous.status === 404) {
    throw new FatalError('GET /quotation-media answered 404 before authentication: the Quotation routes are not deployed on this staging version');
  }
  check('gate', 'with the key but without a session: 401 on list (the Quotation routes are deployed)', anonymous.status === 401, `HTTP ${anonymous.status}`);
  for (const route of ['authorize', 'confirm', 'remove']) {
    const r = await callWorker(null, 'POST', `/quotation-media/${route}`, {});
    check('unauthenticated', `Quotation ${route} with the key but no session: 401`, r.status === 401, `HTTP ${r.status}`);
  }
  const forged = { token: 'not-a-valid-session' };
  const forgedList = await callWorker(forged, 'GET', probe);
  check('invalid-auth', 'an invalid session token on list: 401', forgedList.status === 401, `HTTP ${forgedList.status}`);
  const forgedAuth = await callWorker(forged, 'POST', '/quotation-media/authorize',
    { quotationId: randomUUID(), role: 'office_logo', expectedMediaId: null, contentType: 'image/jpeg', contentLength: 100 });
  check('invalid-auth', 'an invalid session token on authorize: 401', forgedAuth.status === 401, `HTTP ${forgedAuth.status}`);
}

async function sectionLogoRefusals(c) {
  const { a, q1 } = c;
  const base = { quotationId: q1, role: 'office_logo', expectedMediaId: null, contentType: 'image/jpeg', contentLength: 100 };
  const badRole = await callWorker(a, 'POST', '/quotation-media/authorize', { ...base, role: 'logo' });
  check('logo-refuse', "the link-table role name 'logo' is not an API role: 400 invalid_request",
    badRole.status === 400 && badRole.body?.code === 'invalid_request', coded(badRole));
  const { expectedMediaId, ...noExpected } = base;
  const missing = await callWorker(a, 'POST', '/quotation-media/authorize', noExpected);
  check('logo-refuse', 'expectedMediaId is required: 400 invalid_request',
    missing.status === 400 && missing.body?.code === 'invalid_request', coded(missing));
  for (const type of ['application/pdf', 'image/gif', 'image/heic', 'text/plain']) {
    const r = await callWorker(a, 'POST', '/quotation-media/authorize', { ...base, contentType: type });
    check('logo-refuse', `office_logo as ${type}: 400 unsupported_media_type`,
      r.status === 400 && r.body?.code === 'unsupported_media_type', coded(r));
  }
  const big = await callWorker(a, 'POST', '/quotation-media/authorize', { ...base, contentLength: MAX_LOGO_BYTES + 1 });
  check('logo-refuse', 'a logo over 10 MiB: 400 media_too_large', big.status === 400 && big.body?.code === 'media_too_large', coded(big));
  const zero = await callWorker(a, 'POST', '/quotation-media/authorize', { ...base, contentLength: 0 });
  check('logo-refuse', 'a zero-byte logo: 400', zero.status === 400, coded(zero));
  const st = await qState(a, q1);
  check('logo-refuse', 'no refusal changed the Quotation', st.row && st.row.office_logo_media_id === null && st.row.pdf_media_id === null, `v${st.row?.version}`);
}

/** JPEG → PNG → WebP → JPEG: authorize, private PUT, confirm, read-back, signed GET, replacement, idempotency, stale. */
async function sectionLogo(c) {
  const { a, q1, images } = c;
  const S = 'logo';
  let ver = await version(a, q1);

  // JPEG
  const jpeg = await stage(a, q1, 'office_logo', null, images.jpeg, 'image/jpeg', { name: 'logo.jpg' });
  check(S, 'JPEG authorize → private PUT: pending, image, same id', jpeg.authStatus === 200 && jpeg.putStatus === 200 &&
    jpeg.authBody?.mediaType === 'image' && jpeg.authBody?.mediaObjectId === jpeg.id, describe(jpeg));
  if (!jpeg.url) throw new FatalError('the first logo could not be authorized');
  check(S, 'the object key is exactly profiles/<A>/quotations/<Q>/office_logo/<mediaId>.jpg',
    jpeg.objectKey === expectedKey(a.uid, q1, 'office_logo', jpeg.id, 'image/jpeg'));
  check(S, 'the signed PUT is short-lived and addresses the private staging bucket and that exact key',
    isPrivateStagingUrl(jpeg.url, jpeg.objectKey, PUT_TTL));
  const resumed = await qAuthorize(a, q1, 'office_logo', null, jpeg.id, 'image/jpeg', images.jpeg.length);
  check(S, 'authorizing the same id again resumes the same pending upload (idempotent authorize)',
    resumed.status === 200 && resumed.body?.status === 'pending' && resumed.body?.mediaObjectId === jpeg.id, coded(resumed));
  const pendingRow = await mediaRow(a, jpeg.id);
  check(S, 'its media_objects row: pending_upload, staging bucket, exact key, image/jpeg, declared size',
    pendingRow?.status === 'pending_upload' && pendingRow.bucket === STAGING_BUCKET && pendingRow.object_key === jpeg.objectKey &&
    pendingRow.content_type === 'image/jpeg' && pendingRow.media_type === 'image' && Number(pendingRow.size_bytes) === images.jpeg.length,
    pendingRow?.status ?? 'no row');
  const bare = await getBytes(unsigned(jpeg.url));
  check(S, 'the bucket is private: the bare object URL without a signature is refused',
    bare.status !== 200 && bare.status !== 206, `HTTP ${bare.status}`);
  // The PUT above already landed, so the early-confirm check uses a fresh, never-uploaded id.
  const fresh = await stage(a, q1, 'office_logo', null, images.jpeg, 'image/jpeg', { put: false });
  const beforePut = fresh.authStatus === 200 ? await qConfirm(a, q1, 'office_logo', fresh.id, null) : { status: null, body: null };
  check(S, 'a confirm before the bytes arrive: 409 upload_incomplete (nothing is bound)',
    beforePut.status === 409 && beforePut.body?.code === 'upload_incomplete', coded(beforePut));
  if (fresh.authStatus === 200) {
    const cancelled = await qRemove(a, q1, 'office_logo', null, fresh.id);
    check(S, 'that never-uploaded id is withdrawn', cancelled.status === 200 && cancelled.body?.removed === true, coded(cancelled));
  }

  const conf = await bind(a, jpeg, null);
  check(S, 'JPEG confirm binds it (previous media null)', conf.status === 200 && conf.body?.mediaObjectId === jpeg.id &&
    (conf.body?.previousMediaId ?? null) === null && !conf.body?.cleanupPending, coded(conf));
  ver += 1;
  const st1 = await qState(a, q1);
  check(S, 'hosted read-back: office_logo_media_id is the JPEG, pdf_media_id null, version +1',
    st1.row?.office_logo_media_id === jpeg.id && st1.row.pdf_media_id === null && Number(st1.row.version) === ver, `v${st1.row?.version}`);
  const row1 = await mediaRow(a, jpeg.id);
  check(S, 'hosted read-back: media_objects ready, image/jpeg, real size, staging bucket, owner A, exact key',
    row1?.status === 'ready' && row1.owner_id === a.uid && row1.bucket === STAGING_BUCKET && row1.content_type === 'image/jpeg' &&
    row1.media_type === 'image' && Number(row1.size_bytes) === images.jpeg.length && row1.object_key === jpeg.objectKey, row1?.status ?? 'no row');
  const links1 = await linkRows(a, q1);
  check(S, "hosted read-back: exactly one quotation_media link, role 'logo', ordinal 0, to this media",
    links1?.length === 1 && links1[0].media_id === jpeg.id && links1[0].role === 'logo' && links1[0].ordinal === 0 && links1[0].quotation_id === q1,
    `${links1?.length ?? '?'} link(s)`);
  check(S, 'no signed URL is stored in the Quotation or media rows',
    !/X-Amz|https?:/.test(JSON.stringify([st1.raw, row1])));

  const list1 = await qList(a, q1);
  const item1 = list1.body?.media?.office_logo;
  check(S, 'owner signed retrieval: lists the JPEG, no PDF yet, short-lived signed URL',
    list1.status === 200 && item1?.mediaObjectId === jpeg.id && item1.contentType === 'image/jpeg' && list1.body.media.quotation_pdf === null &&
    list1.body.expiresInSeconds === GET_TTL && isPrivateStagingUrl(item1.url, jpeg.objectKey, GET_TTL), coded(list1));
  if (item1?.url) {
    const got = await getBytes(item1.url);
    check(S, 'the signed GET returns the exact JPEG bytes', got.status === 200 && sha256(got.bytes) === sha256(images.jpeg), `HTTP ${got.status}`);
    jpeg.signedGet = item1.url;
  }

  const again = await qConfirm(a, q1, 'office_logo', jpeg.id, null);
  check(S, 'a repeated confirm is idempotent (alreadyConfirmed), version unchanged',
    again.status === 200 && again.body?.alreadyConfirmed === true && (await version(a, q1)) === ver, coded(again));
  const reReady = await qAuthorize(a, q1, 'office_logo', jpeg.id, jpeg.id, 'image/jpeg', images.jpeg.length);
  check(S, 'authorizing the bound id with the current slot answers ready (idempotent authorize)',
    reReady.status === 200 && reReady.body?.status === 'ready' && reReady.body?.mediaObjectId === jpeg.id, coded(reReady));
  const reStale = await qAuthorize(a, q1, 'office_logo', null, jpeg.id, 'image/jpeg', images.jpeg.length);
  check(S, 'authorizing it with a stale (empty) slot: 409 stale_replacement', reStale.status === 409 && reStale.body?.code === 'stale_replacement', coded(reStale));

  // PNG replaces JPEG
  const png = await stage(a, q1, 'office_logo', jpeg.id, images.png, 'image/png', { name: 'logo.png' });
  const pngConf = png.putStatus === 200 ? await bind(a, png, jpeg.id) : { status: null, body: null };
  check(S, 'PNG replacement: authorize → PUT → confirm (expected = JPEG); the JPEG is reported as previous',
    png.authStatus === 200 && png.putStatus === 200 && pngConf.status === 200 && pngConf.body?.previousMediaId === jpeg.id && !pngConf.body?.cleanupPending,
    describe(png));
  check(S, 'the PNG key is under .../office_logo/ with the .png extension', png.objectKey === expectedKey(a.uid, q1, 'office_logo', png.id, 'image/png'));
  ver += 1;
  const stPng = await qState(a, q1);
  check(S, 'hosted read-back: the new slot wins (PNG), version +1',
    stPng.row?.office_logo_media_id === png.id && Number(stPng.row.version) === ver, `v${stPng.row?.version}`);
  const oldJpeg = await mediaRow(a, jpeg.id);
  check(S, 'the previous JPEG left the live lifecycle (pending_delete, or deleted once its bytes were removed)',
    RETIRED.includes(oldJpeg?.status), oldJpeg?.status ?? 'no row');
  note(S, `previous media state after replacement: ${oldJpeg?.status ?? 'unknown'}`);
  const linksPng = await linkRows(a, q1);
  check(S, 'exactly one logo link remains, and it is the PNG', linksPng?.length === 1 && linksPng[0].media_id === png.id && linksPng[0].role === 'logo',
    `${linksPng?.length ?? '?'} link(s)`);
  if (jpeg.signedGet) {
    const old = await getBytes(jpeg.signedGet);
    check(S, "the replaced JPEG's bytes are gone from private R2 (its earlier signed link no longer returns them)", old.status !== 200 && old.status !== 206, `HTTP ${old.status}`);
  }
  const listPng = await qList(a, q1);
  const itemPng = listPng.body?.media?.office_logo;
  const gotPng = itemPng?.url ? await getBytes(itemPng.url) : null;
  check(S, 'signed GET now returns the PNG bytes', itemPng?.mediaObjectId === png.id && gotPng?.status === 200 && sha256(gotPng.bytes) === sha256(images.png),
    `HTTP ${gotPng?.status ?? listPng.status}`);

  // WebP replaces PNG
  const webp = await stage(a, q1, 'office_logo', png.id, images.webp, 'image/webp', { name: 'logo.webp' });
  const webpConf = webp.putStatus === 200 ? await bind(a, webp, png.id) : { status: null, body: null };
  check(S, 'WebP replacement: authorize → PUT → confirm (expected = PNG)', webp.authStatus === 200 && webp.putStatus === 200 &&
    webpConf.status === 200 && webpConf.body?.previousMediaId === png.id, describe(webp));
  check(S, 'the WebP key is under .../office_logo/ with the .webp extension', webp.objectKey === expectedKey(a.uid, q1, 'office_logo', webp.id, 'image/webp'));
  ver += 1;
  const stWebp = await qState(a, q1);
  const listWebp = await qList(a, q1);
  const itemWebp = listWebp.body?.media?.office_logo;
  const gotWebp = itemWebp?.url ? await getBytes(itemWebp.url) : null;
  check(S, 'hosted read-back and signed GET: the WebP holds the slot, exact bytes, version +1',
    stWebp.row?.office_logo_media_id === webp.id && Number(stWebp.row.version) === ver && itemWebp?.contentType === 'image/webp' &&
    gotWebp?.status === 200 && sha256(gotWebp.bytes) === sha256(images.webp), `v${stWebp.row?.version}`);
  const oldPng = await mediaRow(a, png.id);
  check(S, 'the previous PNG left the live lifecycle', RETIRED.includes(oldPng?.status), oldPng?.status ?? 'no row');

  // Stale replacement: two replacements race for the same slot.
  const s1 = await stage(a, q1, 'office_logo', webp.id, images.jpeg, 'image/jpeg', { name: 'stale.jpg' });
  const winnerBytes = variant(images.jpeg);
  const s2 = await stage(a, q1, 'office_logo', webp.id, winnerBytes, 'image/jpeg', { name: 'winner.jpg' });
  const winConf = s2.putStatus === 200 ? await bind(a, s2, webp.id) : { status: null, body: null };
  check(S, 'two replacements race: the second (winner) confirms and takes the slot', s1.putStatus === 200 && s2.putStatus === 200 &&
    winConf.status === 200 && winConf.body?.previousMediaId === webp.id, `${describe(s2)}`);
  ver += 1;
  const staleConf = await bind(a, s1, webp.id);
  check(S, 'the older replacement cannot overwrite the newer slot: 409 stale_replacement', staleConf.status === 409 && staleConf.body?.code === 'stale_replacement', coded(staleConf));
  const stAfterStale = await qState(a, q1);
  const staleRow = await mediaRow(a, s1.id);
  const staleLinks = await linkRows(a, q1);
  check(S, 'the slot still holds the winner; the stale upload is not ready and not linked; version unchanged',
    stAfterStale.row?.office_logo_media_id === s2.id && Number(stAfterStale.row.version) === ver && staleRow?.status === 'pending_upload' &&
    !staleLinks?.some((l) => l.media_id === s1.id), `${staleRow?.status ?? 'no row'}`);
  const staleAuthorize = await qAuthorize(a, q1, 'office_logo', webp.id, randomUUID(), 'image/jpeg', 100);
  check(S, 'authorizing against the superseded slot: 409 stale_replacement', staleAuthorize.status === 409 && staleAuthorize.body?.code === 'stale_replacement', coded(staleAuthorize));
  const staleRemove = await qRemove(a, q1, 'office_logo', webp.id);
  check(S, 'a stale remove (expected = the superseded WebP) while a newer logo holds the slot: 409 stale_replacement',
    staleRemove.status === 409 && staleRemove.body?.code === 'stale_replacement', coded(staleRemove));
  const stillWinner = await qState(a, q1);
  check(S, 'the winner is untouched by the stale remove', stillWinner.row?.office_logo_media_id === s2.id && Number(stillWinner.row.version) === ver);
  const cancel = await qRemove(a, q1, 'office_logo', s2.id, s1.id);
  const cancelledRow = await mediaRow(a, s1.id);
  check(S, 'the stale pending upload is cancelled (removed) without touching the bound winner',
    cancel.status === 200 && cancel.body?.removed === true && cancelledRow?.status === 'deleted' &&
    (await qState(a, q1)).row?.office_logo_media_id === s2.id, coded(cancel));

  c.logo = { id: s2.id, key: s2.objectKey, bytes: winnerBytes };
  c.ver = ver;
}

/** Quotation PDF: valid type, refusals, upload, bind, read-back, regeneration, idempotency, stale. */
async function sectionPdf(c) {
  const { a, q1 } = c;
  const S = 'pdf';
  let ver = await version(a, q1);

  const refusals = [['image/jpeg', 'quotation_pdf as image/jpeg'], ['text/plain', 'quotation_pdf as text/plain'], ['image/png', 'quotation_pdf as image/png']];
  for (const [type, label] of refusals) {
    const r = await callWorker(a, 'POST', '/quotation-media/authorize',
      { quotationId: q1, role: 'quotation_pdf', expectedMediaId: null, contentType: type, contentLength: 100 });
    check(S, `${label}: 400 unsupported_media_type`, r.status === 400 && r.body?.code === 'unsupported_media_type', coded(r));
  }
  const big = await callWorker(a, 'POST', '/quotation-media/authorize',
    { quotationId: q1, role: 'quotation_pdf', expectedMediaId: null, contentType: 'application/pdf', contentLength: MAX_PDF_BYTES + 1 });
  check(S, 'a PDF over 20 MiB: 400 media_too_large', big.status === 400 && big.body?.code === 'media_too_large', coded(big));

  const pdf1Bytes = makePdf('v1');
  const pdf1 = await stage(a, q1, 'quotation_pdf', null, pdf1Bytes, 'application/pdf', { name: 'quotation.pdf' });
  check(S, 'PDF authorize → private PUT: pending, pdf, same id', pdf1.authStatus === 200 && pdf1.putStatus === 200 &&
    pdf1.authBody?.mediaType === 'pdf' && pdf1.authBody?.mediaObjectId === pdf1.id, describe(pdf1));
  if (!pdf1.url) throw new FatalError('the first PDF could not be authorized');
  check(S, 'the object key is exactly profiles/<A>/quotations/<Q>/quotation_pdf/<mediaId>.pdf',
    pdf1.objectKey === expectedKey(a.uid, q1, 'quotation_pdf', pdf1.id, 'application/pdf'));
  check(S, 'the signed PUT is short-lived and addresses the private staging bucket and that exact key', isPrivateStagingUrl(pdf1.url, pdf1.objectKey, PUT_TTL));
  const bare = await getBytes(unsigned(pdf1.url));
  check(S, 'the bucket is private: the bare PDF URL without a signature is refused', bare.status !== 200 && bare.status !== 206, `HTTP ${bare.status}`);
  const conf = await bind(a, pdf1, null);
  check(S, 'PDF confirm binds it (previous media null)', conf.status === 200 && conf.body?.mediaObjectId === pdf1.id &&
    (conf.body?.previousMediaId ?? null) === null, coded(conf));
  ver += 1;
  const st1 = await qState(a, q1);
  check(S, 'hosted read-back: pdf_media_id is the PDF, version +1, the logo slot is untouched',
    st1.row?.pdf_media_id === pdf1.id && Number(st1.row.version) === ver && st1.row.office_logo_media_id === c.logo.id, `v${st1.row?.version}`);
  const row1 = await mediaRow(a, pdf1.id);
  check(S, 'hosted read-back: media_objects ready, application/pdf, media_type pdf, real size, staging bucket, exact key',
    row1?.status === 'ready' && row1.owner_id === a.uid && row1.bucket === STAGING_BUCKET && row1.content_type === 'application/pdf' &&
    row1.media_type === 'pdf' && Number(row1.size_bytes) === pdf1Bytes.length && row1.object_key === pdf1.objectKey, row1?.status ?? 'no row');
  const links1 = await linkRows(a, q1);
  check(S, "hosted read-back: one 'pdf' link and one 'logo' link, each ordinal 0",
    links1?.length === 2 && links1.some((l) => l.role === 'pdf' && l.media_id === pdf1.id && l.ordinal === 0) &&
    links1.some((l) => l.role === 'logo' && l.media_id === c.logo.id && l.ordinal === 0), `${links1?.length ?? '?'} link(s)`);
  const logoRow = await mediaRow(a, c.logo.id);
  check(S, 'the logo media is still ready (PDF operations never touch the logo)', logoRow?.status === 'ready', logoRow?.status ?? 'no row');
  const list1 = await qList(a, q1);
  const item1 = list1.body?.media?.quotation_pdf;
  const got1 = item1?.url ? await getBytes(item1.url) : null;
  check(S, 'owner signed retrieval: the PDF is listed beside the logo; the signed GET returns the exact PDF bytes',
    list1.status === 200 && item1?.mediaObjectId === pdf1.id && item1.contentType === 'application/pdf' &&
    list1.body.media.office_logo?.mediaObjectId === c.logo.id && got1?.status === 200 && sha256(got1.bytes) === sha256(pdf1Bytes) &&
    isPrivateStagingUrl(item1.url, pdf1.objectKey, GET_TTL), coded(list1));
  pdf1.signedGet = item1?.url;
  const again = await qConfirm(a, q1, 'quotation_pdf', pdf1.id, null);
  check(S, 'a repeated confirm is idempotent (alreadyConfirmed), version unchanged',
    again.status === 200 && again.body?.alreadyConfirmed === true && (await version(a, q1)) === ver, coded(again));

  // Bytes that are not a PDF, declared as one.
  const bad = await stage(a, q1, 'quotation_pdf', pdf1.id, c.images.jpeg, 'application/pdf', { name: 'not-a-pdf.pdf' });
  const badConf = bad.putStatus === 200 ? await bind(a, bad, pdf1.id) : { status: null, body: null };
  const badRow = await mediaRow(a, bad.id);
  check(S, 'JPEG bytes declared as a PDF: confirm refused 422 media_type_mismatch; the row is failed; the slot is unchanged',
    badConf.status === 422 && badConf.body?.code === 'media_type_mismatch' && badRow?.status === 'failed' &&
    (await qState(a, q1)).row?.pdf_media_id === pdf1.id, `${coded(badConf)} ${badRow?.status ?? ''}`);
  if (bad.authStatus === 200) {
    const drop = await qRemove(a, q1, 'quotation_pdf', pdf1.id, bad.id);
    check(S, 'the refused upload is withdrawn', drop.status === 200 && drop.body?.removed === true, coded(drop));
  }

  // Regeneration.
  const pdf2Bytes = makePdf('v2');
  const pdf2 = await stage(a, q1, 'quotation_pdf', pdf1.id, pdf2Bytes, 'application/pdf', { name: 'quotation-v2.pdf' });
  const conf2 = pdf2.putStatus === 200 ? await bind(a, pdf2, pdf1.id) : { status: null, body: null };
  check(S, 'regeneration: authorize → PUT → confirm (expected = first PDF); the first is reported as previous',
    pdf2.authStatus === 200 && pdf2.putStatus === 200 && conf2.status === 200 && conf2.body?.previousMediaId === pdf1.id && !conf2.body?.cleanupPending, describe(pdf2));
  ver += 1;
  const st2 = await qState(a, q1);
  check(S, 'hosted read-back: the new PDF holds the slot, version +1, the logo is untouched',
    st2.row?.pdf_media_id === pdf2.id && Number(st2.row.version) === ver && st2.row.office_logo_media_id === c.logo.id, `v${st2.row?.version}`);
  const old1 = await mediaRow(a, pdf1.id);
  check(S, 'the previous PDF left the live lifecycle (pending_delete, or deleted once its bytes were removed)', RETIRED.includes(old1?.status), old1?.status ?? 'no row');
  note(S, `previous PDF state after regeneration: ${old1?.status ?? 'unknown'}`);
  if (pdf1.signedGet) {
    const old = await getBytes(pdf1.signedGet);
    check(S, "the replaced PDF's bytes are gone from private R2", old.status !== 200 && old.status !== 206, `HTTP ${old.status}`);
  }
  const list2 = await qList(a, q1);
  const got2 = list2.body?.media?.quotation_pdf?.url ? await getBytes(list2.body.media.quotation_pdf.url) : null;
  check(S, 'signed GET returns the regenerated PDF, not the first', list2.body?.media?.quotation_pdf?.mediaObjectId === pdf2.id &&
    got2?.status === 200 && sha256(got2.bytes) === sha256(pdf2Bytes) && sha256(pdf2Bytes) !== sha256(pdf1Bytes), `HTTP ${got2?.status ?? list2.status}`);

  // Stale replacement.
  const p1 = await stage(a, q1, 'quotation_pdf', pdf2.id, makePdf('stale'), 'application/pdf', { name: 'stale.pdf' });
  const winBytes = makePdf('winner');
  const p2 = await stage(a, q1, 'quotation_pdf', pdf2.id, winBytes, 'application/pdf', { name: 'winner.pdf' });
  const winConf = p2.putStatus === 200 ? await bind(a, p2, pdf2.id) : { status: null, body: null };
  check(S, 'two PDF regenerations race: the second confirms and takes the slot', p1.putStatus === 200 && p2.putStatus === 200 &&
    winConf.status === 200 && winConf.body?.previousMediaId === pdf2.id, describe(p2));
  ver += 1;
  const staleConf = await bind(a, p1, pdf2.id);
  check(S, 'the older regeneration cannot overwrite the newer slot: 409 stale_replacement', staleConf.status === 409 && staleConf.body?.code === 'stale_replacement', coded(staleConf));
  const stale = await qState(a, q1);
  const staleRow = await mediaRow(a, p1.id);
  check(S, 'the slot still holds the winner; the stale upload is not ready; version unchanged',
    stale.row?.pdf_media_id === p2.id && Number(stale.row.version) === ver && staleRow?.status === 'pending_upload', staleRow?.status ?? 'no row');
  const staleAuthorize = await qAuthorize(a, q1, 'quotation_pdf', pdf1.id, randomUUID(), 'application/pdf', 100);
  check(S, 'authorizing against a superseded PDF slot: 409 stale_replacement', staleAuthorize.status === 409 && staleAuthorize.body?.code === 'stale_replacement', coded(staleAuthorize));
  const staleRemove = await qRemove(a, q1, 'quotation_pdf', pdf2.id);
  check(S, 'a stale remove (expected = the superseded PDF) while a newer PDF holds the slot: 409 stale_replacement',
    staleRemove.status === 409 && staleRemove.body?.code === 'stale_replacement' && (await qState(a, q1)).row?.pdf_media_id === p2.id, coded(staleRemove));
  const cancel = await qRemove(a, q1, 'quotation_pdf', p2.id, p1.id);
  check(S, 'the stale pending PDF is cancelled without touching the bound winner',
    cancel.status === 200 && cancel.body?.removed === true && (await mediaRow(a, p1.id))?.status === 'deleted', coded(cancel));

  c.pdf = { id: p2.id, key: p2.objectKey, bytes: winBytes };
  c.ver = ver;
}

/** Wrong role and cross-parent (same owner, two Quotations), checked while both slots are bound. */
async function sectionRoleAndParent(c) {
  const { a, q1, q2, images } = c;
  const S = 'role-parent';
  const before1 = await qState(a, q1);
  const before2 = await qState(a, q2);

  const x = await stage(a, q1, 'office_logo', c.logo.id, images.jpeg, 'image/jpeg', { name: 'wrong-role.jpg' });
  const y = await stage(a, q1, 'quotation_pdf', c.pdf.id, makePdf('wrong-role'), 'application/pdf', { name: 'wrong-role.pdf' });
  check(S, 'two pending uploads exist for the wrong-role checks (a logo and a PDF)', x.putStatus === 200 && y.putStatus === 200, `${x.authStatus}/${y.authStatus}`);

  const asPdf = await qConfirm(a, q1, 'quotation_pdf', x.id, c.pdf.id);
  check(S, 'an office_logo upload cannot bind as quotation_pdf: 409 media_mismatch', asPdf.status === 409 && asPdf.body?.code === 'media_mismatch', coded(asPdf));
  const asLogo = await qConfirm(a, q1, 'office_logo', y.id, c.logo.id);
  check(S, 'a quotation_pdf upload cannot bind as office_logo: 409 media_mismatch', asLogo.status === 409 && asLogo.body?.code === 'media_mismatch', coded(asLogo));
  const removeWrongRole = await qRemove(a, q1, 'quotation_pdf', c.pdf.id, x.id);
  check(S, 'an office_logo id cannot be cancelled through the quotation_pdf role: 409 media_mismatch',
    removeWrongRole.status === 409 && removeWrongRole.body?.code === 'media_mismatch', coded(removeWrongRole));

  const onQ2 = await qConfirm(a, q2, 'office_logo', x.id, null);
  check(S, "the object key's Quotation segment must match: confirming it on another Quotation: 409 media_mismatch",
    onQ2.status === 409 && onQ2.body?.code === 'media_mismatch', coded(onQ2));
  const removeOnQ2 = await qRemove(a, q2, 'office_logo', null, x.id);
  check(S, "cancelling it through another Quotation: 409 media_mismatch", removeOnQ2.status === 409 && removeOnQ2.body?.code === 'media_mismatch', coded(removeOnQ2));
  const reuseOnQ2 = await qAuthorize(a, q2, 'office_logo', null, x.id, 'image/jpeg', images.jpeg.length);
  check(S, 'reusing the id to authorize on another Quotation: 409 idempotency_mismatch (cross-parent)',
    reuseOnQ2.status === 409 && reuseOnQ2.body?.code === 'idempotency_mismatch', coded(reuseOnQ2));

  const after1 = await qState(a, q1);
  const after2 = await qState(a, q2);
  check(S, 'neither Quotation changed (slots and versions)',
    after1.row?.office_logo_media_id === before1.row?.office_logo_media_id && after1.row?.pdf_media_id === before1.row?.pdf_media_id &&
    Number(after1.row?.version) === Number(before1.row?.version) && after2.row?.office_logo_media_id === null &&
    after2.row?.pdf_media_id === null && Number(after2.row?.version) === Number(before2.row?.version));
  const dropX = await qRemove(a, q1, 'office_logo', c.logo.id, x.id);
  const dropY = await qRemove(a, q1, 'quotation_pdf', c.pdf.id, y.id);
  check(S, 'both pending uploads are withdrawn', dropX.status === 200 && dropY.status === 200, `${dropX.status}/${dropY.status}`);
}

/** A soft-deleted Quotation refuses every media operation. */
async function sectionDeleted(c) {
  const { a, images } = c;
  const S = 'deleted';
  const q3 = await createQuotation(a, 'A-deleted');
  const pending = await stage(a, q3, 'office_logo', null, images.jpeg, 'image/jpeg', { put: false });
  check(S, 'a pending upload exists on the live Quotation before it is deleted', pending.authStatus === 200, describe(pending));
  const del = await rest(a, 'PATCH', `/rest/v1/quotations?id=eq.${q3}`, { deleted_at: new Date().toISOString() }, 'return=minimal');
  const afterDelete = await qState(a, q3);
  check(S, 'the owner soft-deletes it through the only column clients may update (deleted_at)',
    (del.status === 200 || del.status === 204) && (afterDelete.row === null || (afterDelete.row?.deleted_at ?? null) !== null),
    `HTTP ${del.status}, ${afterDelete.row === null ? 'row hidden from the owner' : 'deleted_at set'}`);
  const authorize = await qAuthorize(a, q3, 'office_logo', null, randomUUID(), 'image/jpeg', images.jpeg.length);
  check(S, 'authorize on the deleted Quotation: 404 quotation_not_found', authorize.status === 404 && authorize.body?.code === 'quotation_not_found', coded(authorize));
  const confirm = await qConfirm(a, q3, 'office_logo', pending.id, null);
  check(S, 'confirm on the deleted Quotation: 404 quotation_not_found', confirm.status === 404 && confirm.body?.code === 'quotation_not_found', coded(confirm));
  const list = await qList(a, q3);
  check(S, 'list on the deleted Quotation: 404 quotation_not_found', list.status === 404 && list.body?.code === 'quotation_not_found', coded(list));
  const remove = await qRemove(a, q3, 'office_logo', null, pending.id);
  check(S, 'remove on the deleted Quotation: 404 quotation_not_found', remove.status === 404 && remove.body?.code === 'quotation_not_found', coded(remove));
  const pdfAuthorize = await qAuthorize(a, q3, 'quotation_pdf', null, randomUUID(), 'application/pdf', 100);
  check(S, 'a PDF authorize on the deleted Quotation: 404 quotation_not_found', pdfAuthorize.status === 404, coded(pdfAuthorize));
  const row = await mediaRow(a, pending.id);
  check(S, 'the pending upload was neither bound nor changed by any of it', row?.status === 'pending_upload', row?.status ?? 'no row');
}

/** Direct client writes to the server-controlled media columns and tables stay denied. */
async function sectionDirectWrites(c) {
  const { a, q1 } = c;
  const S = 'direct-write';
  const before = await qState(a, q1);
  const unchanged = async () => {
    const now = await qState(a, q1);
    return now.row?.office_logo_media_id === before.row?.office_logo_media_id && now.row?.pdf_media_id === before.row?.pdf_media_id &&
      Number(now.row?.version) === Number(before.row?.version) && now.row?.owner_id === before.row?.owner_id && now.row?.deleted_at === null;
  };
  const denied = (r) => r.status >= 400;

  const logoWrite = await rest(a, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { office_logo_media_id: randomUUID() });
  check(S, 'a direct write to office_logo_media_id is denied and changes nothing', denied(logoWrite) && await unchanged(), `HTTP ${logoWrite.status} ${logoWrite.body?.code ?? ''}`);
  const pdfWrite = await rest(a, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { pdf_media_id: randomUUID() });
  check(S, 'a direct write to pdf_media_id is denied and changes nothing', denied(pdfWrite) && await unchanged(), `HTTP ${pdfWrite.status} ${pdfWrite.body?.code ?? ''}`);
  const nulling = await rest(a, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { office_logo_media_id: null, pdf_media_id: null });
  check(S, 'a direct write that clears both media ids is denied and changes nothing', denied(nulling) && await unchanged(), `HTTP ${nulling.status}`);
  const bump = await rest(a, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { version: 999 });
  check(S, 'a direct write to version is denied and changes nothing', denied(bump) && await unchanged(), `HTTP ${bump.status}`);
  const del = await rest(a, 'DELETE', `/rest/v1/quotations?id=eq.${q1}`);
  check(S, 'a direct DELETE of the Quotation is denied and the row remains', denied(del) && await unchanged(), `HTTP ${del.status}`);
  const link = await rest(a, 'POST', '/rest/v1/quotation_media', { quotation_id: q1, media_id: randomUUID(), role: 'logo', ordinal: 1 });
  check(S, 'a direct INSERT into quotation_media is denied', denied(link), `HTTP ${link.status} ${link.body?.code ?? ''}`);
  const media = await rest(a, 'POST', '/rest/v1/media_objects', {
    id: randomUUID(), owner_id: a.uid, bucket: STAGING_BUCKET, object_key: `profiles/${a.uid}/quotations/${q1}/office_logo/${randomUUID()}.jpg`,
    media_type: 'image', content_type: 'image/jpeg', size_bytes: 1, status: 'ready',
  });
  check(S, 'a direct INSERT into media_objects is denied', denied(media), `HTTP ${media.status} ${media.body?.code ?? ''}`);
  const rpcConfirm = await rest(a, 'POST', '/rest/v1/rpc/confirm_quotation_media_upload', {
    p_user_id: a.uid, p_quotation_id: q1, p_media_id: randomUUID(), p_role: 'office_logo', p_bucket: STAGING_BUCKET,
    p_expected_media_id: randomUUID(), p_observed_size: 1, p_observed_content_type: 'image/jpeg',
  });
  check(S, 'a signed-in client cannot execute confirm_quotation_media_upload', rpcConfirm.status === 401 || rpcConfirm.status === 403 || rpcConfirm.status === 404,
    `HTTP ${rpcConfirm.status} ${rpcConfirm.body?.code ?? ''}`);
  const rpcRemove = await rest(a, 'POST', '/rest/v1/rpc/remove_quotation_media', {
    p_user_id: a.uid, p_quotation_id: q1, p_role: 'office_logo', p_bucket: STAGING_BUCKET, p_expected_media_id: randomUUID(),
  });
  check(S, 'a signed-in client cannot execute remove_quotation_media', rpcRemove.status === 401 || rpcRemove.status === 403 || rpcRemove.status === 404,
    `HTTP ${rpcRemove.status} ${rpcRemove.body?.code ?? ''}`);
  const inject = await rest(a, 'POST', '/rest/v1/rpc/save_quotation', {
    p_quotation_id: q1, p_expected_version: before.row ? Number(before.row.version) : 1,
    p_header: {
      property_title: 'x', property_type: null, parking: null, subtitle: null, display_date: null, start_date_text: null,
      end_date_text: null, currency_code: 'AED', professional_fee: null, total_amount: null, number_of_installments: null,
      payment_type: null, insurance_amount: null, insurance_returnable: null, office_name: 'x', custom_note: null,
      welcome_message_mode: 'auto', custom_welcome_message: null, office_logo_media_id: randomUUID(), pdf_media_id: randomUUID(),
    },
    p_downpayments: [], p_government_fees: null, p_administrative_fees: [],
  });
  check(S, 'save_quotation refuses media ids smuggled into its header (server-controlled fields)', denied(inject) && await unchanged(),
    `HTTP ${inject.status} ${inject.body?.code ?? ''}`);
  const rows = await Promise.all([c.logo.id, c.pdf.id].map((id) => mediaRow(a, id)));
  check(S, 'the bound media rows are still ready after all of it', rows.every((r) => r?.status === 'ready'), rows.map((r) => r?.status).join('/'));
}

/** B against A's resources, while A's logo and PDF are bound. */
async function sectionCrossUser(c) {
  const { a, b, q1, qB, images } = c;
  const S = 'cross-user';
  const ids = [c.logo.id, c.pdf.id];
  const snap = async () => {
    const st = await qState(a, q1);
    const rows = [];
    for (const id of ids) rows.push((await mediaRow(a, id))?.status ?? null);
    return JSON.stringify({ v: st.row?.version, l: st.row?.office_logo_media_id, p: st.row?.pdf_media_id, d: st.row?.deleted_at, rows });
  };
  const before = await snap();

  const list = await qList(b, q1);
  check(S, "B cannot list A's Quotation media (404 quotation_not_found, no URL)",
    list.status === 404 && list.body?.code === 'quotation_not_found' && !JSON.stringify(list.body).includes('http'), coded(list));
  const authLogo = await qAuthorize(b, q1, 'office_logo', c.logo.id, randomUUID(), 'image/jpeg', images.jpeg.length);
  check(S, "B cannot authorize an office_logo upload against A's Quotation (404)", authLogo.status === 404 && authLogo.body?.code === 'quotation_not_found', coded(authLogo));
  const authPdf = await qAuthorize(b, q1, 'quotation_pdf', c.pdf.id, randomUUID(), 'application/pdf', 100);
  check(S, "B cannot authorize a quotation_pdf upload against A's Quotation (404)", authPdf.status === 404 && authPdf.body?.code === 'quotation_not_found', coded(authPdf));
  const authNull = await qAuthorize(b, q1, 'office_logo', null, randomUUID(), 'image/jpeg', images.jpeg.length);
  check(S, "B cannot authorize against A's Quotation even with a guessed (empty) slot: still 404, not 409", authNull.status === 404, coded(authNull));
  const confLogo = await qConfirm(b, q1, 'office_logo', c.logo.id, c.logo.id);
  check(S, "B cannot confirm A's logo on A's Quotation (404)", confLogo.status === 404, coded(confLogo));
  const confPdf = await qConfirm(b, q1, 'quotation_pdf', c.pdf.id, c.pdf.id);
  check(S, "B cannot confirm A's PDF on A's Quotation (404)", confPdf.status === 404, coded(confPdf));
  const remLogo = await qRemove(b, q1, 'office_logo', c.logo.id);
  const remPdf = await qRemove(b, q1, 'quotation_pdf', c.pdf.id);
  check(S, "B cannot remove A's logo or PDF (404)", remLogo.status === 404 && remPdf.status === 404, `${remLogo.status}/${remPdf.status}`);

  // A's media ids on B's own parent.
  const takeLogo = await qAuthorize(b, qB, 'office_logo', null, c.logo.id, 'image/jpeg', images.jpeg.length);
  check(S, "B cannot take over A's logo media id on B's own Quotation (409 media_id_conflict)", takeLogo.status === 409 && takeLogo.body?.code === 'media_id_conflict', coded(takeLogo));
  const takePdf = await qAuthorize(b, qB, 'quotation_pdf', null, c.pdf.id, 'application/pdf', 100);
  check(S, "B cannot take over A's PDF media id on B's own Quotation (409 media_id_conflict)", takePdf.status === 409 && takePdf.body?.code === 'media_id_conflict', coded(takePdf));
  const bindLogo = await qConfirm(b, qB, 'office_logo', c.logo.id, null);
  const bindPdf = await qConfirm(b, qB, 'quotation_pdf', c.pdf.id, null);
  check(S, "B cannot bind A's media to B's own Quotation (404 media_not_found)", bindLogo.status === 404 && bindPdf.status === 404 &&
    bindLogo.body?.code === 'media_not_found', `${coded(bindLogo)} / ${coded(bindPdf)}`);

  // B's media on A's Quotation, and A's attempt to use B's media.
  const bMedia = await stage(b, qB, 'office_logo', null, images.jpeg, 'image/jpeg', { name: 'b-logo.jpg' });
  check(S, "B's own upload on B's Quotation is authorized and uploaded (positive control)", bMedia.authStatus === 200 && bMedia.putStatus === 200, describe(bMedia));
  const bOnA = await qConfirm(b, q1, 'office_logo', bMedia.id, c.logo.id);
  check(S, "B cannot bind B's media to A's Quotation (404 quotation_not_found)", bOnA.status === 404 && bOnA.body?.code === 'quotation_not_found', coded(bOnA));
  const bAsPdf = await qConfirm(b, qB, 'quotation_pdf', bMedia.id, null);
  check(S, "B's logo cannot bind as a PDF even on B's own Quotation (409 media_mismatch: wrong role)", bAsPdf.status === 409 && bAsPdf.body?.code === 'media_mismatch', coded(bAsPdf));
  const aTakesB = await qConfirm(a, q1, 'office_logo', bMedia.id, c.logo.id);
  check(S, "A cannot bind B's media to A's Quotation (404 media_not_found)", aTakesB.status === 404 && aTakesB.body?.code === 'media_not_found', coded(aTakesB));
  const aReuse = await qAuthorize(a, q1, 'office_logo', c.logo.id, bMedia.id, 'image/jpeg', images.jpeg.length);
  check(S, "A cannot take over B's media id (409 media_id_conflict)", aReuse.status === 409 && aReuse.body?.code === 'media_id_conflict', coded(aReuse));

  // RLS, as B.
  const qRows = await rest(b, 'GET', `/rest/v1/quotations?id=eq.${q1}&select=id`);
  const mRows = await rest(b, 'GET', `/rest/v1/media_objects?id=in.(${ids.join(',')})&select=id`);
  const lRows = await rest(b, 'GET', `/rest/v1/quotation_media?quotation_id=eq.${q1}&select=media_id`);
  check(S, "RLS: B cannot read A's Quotation, media rows or media links",
    qRows.status === 200 && qRows.body?.length === 0 && mRows.status === 200 && mRows.body?.length === 0 && lRows.status === 200 && lRows.body?.length === 0,
    `${qRows.body?.length ?? '?'}/${mRows.body?.length ?? '?'}/${lRows.body?.length ?? '?'} row(s)`);
  const bDelete = await rest(b, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { deleted_at: new Date().toISOString() });
  const bSlot = await rest(b, 'PATCH', `/rest/v1/quotations?id=eq.${q1}`, { office_logo_media_id: bMedia.id });
  check(S, "B cannot soft-delete A's Quotation or write its media id", (bDelete.status >= 400 || bDelete.status === 204 || bDelete.status === 200) && bSlot.status >= 400,
    `HTTP ${bDelete.status}/${bSlot.status}`);
  const bRpc = await rest(b, 'POST', '/rest/v1/rpc/confirm_quotation_media_upload', {
    p_user_id: a.uid, p_quotation_id: q1, p_media_id: c.logo.id, p_role: 'office_logo', p_bucket: STAGING_BUCKET,
    p_expected_media_id: c.logo.id, p_observed_size: 1, p_observed_content_type: 'image/jpeg',
  });
  check(S, 'B cannot call confirm_quotation_media_upload directly (as A or otherwise)', bRpc.status === 401 || bRpc.status === 403 || bRpc.status === 404, `HTTP ${bRpc.status}`);
  const bSave = await rest(b, 'POST', '/rest/v1/rpc/save_quotation', {
    p_quotation_id: q1, p_expected_version: 1,
    p_header: { property_title: 'hijack', property_type: null, parking: null, subtitle: null, display_date: null, start_date_text: null, end_date_text: null,
      currency_code: 'AED', professional_fee: null, total_amount: null, number_of_installments: null, payment_type: null, insurance_amount: null,
      insurance_returnable: null, office_name: 'x', custom_note: null, welcome_message_mode: 'auto', custom_welcome_message: null },
    p_downpayments: [], p_government_fees: null, p_administrative_fees: [],
  });
  check(S, "B cannot overwrite A's Quotation through save_quotation", bSave.status >= 400, `HTTP ${bSave.status} ${bSave.body?.code ?? ''}`);

  const after = await snap();
  check(S, "A's Quotation, version, slots and media states are exactly as before all of B's attempts", before === after);
  const aList = await qList(a, q1);
  const aGot = aList.body?.media?.office_logo?.url ? await getBytes(aList.body.media.office_logo.url) : null;
  check(S, "A can still retrieve the logo, with the exact bytes", aList.status === 200 && aList.body.media.office_logo?.mediaObjectId === c.logo.id &&
    aGot?.status === 200 && sha256(aGot.bytes) === sha256(c.logo.bytes), `HTTP ${aGot?.status ?? aList.status}`);

  // Positive control: B can do everything on its own Quotation.
  const bConf = await qConfirm(b, qB, 'office_logo', bMedia.id, null);
  check(S, "positive control: B confirms its own logo on its own Quotation (so the denials above are about ownership)", bConf.status === 200 && bConf.body?.mediaObjectId === bMedia.id, coded(bConf));
  const bList = await qList(b, qB);
  const bGot = bList.body?.media?.office_logo?.url ? await getBytes(bList.body.media.office_logo.url) : null;
  check(S, "positive control: B retrieves its own logo", bGot?.status === 200 && sha256(bGot.bytes) === sha256(images.jpeg), `HTTP ${bGot?.status ?? bList.status}`);
  const bKey = (await mediaRow(b, bMedia.id))?.object_key;
  check(S, "B's object lives under B's own prefix, never A's", bKey === expectedKey(b.uid, qB, 'office_logo', bMedia.id, 'image/jpeg') && !String(bKey).includes(a.uid));
  const bRemove = await qRemove(b, qB, 'office_logo', bMedia.id);
  check(S, "positive control: B removes its own logo", bRemove.status === 200 && bRemove.body?.removed === true, coded(bRemove));
}

/** The shared Worker's existing routes still behave, and Quotation routing does not collide with them. */
async function sectionRegression(c) {
  const { a, q1, images } = c;
  const S = 'regression';
  const parents = [
    { parent: OFFER, bytes: images.jpeg, type: 'image/jpeg', ext: 'jpg', create: async () => {
      const id = randomUUID();
      const r = await rest(a, 'POST', '/rest/v1/offers', { id, owner_id: a.uid, offer_type: 'rent', notes: `staging-e2e ${RUN_ID} quotation-regression` }, 'return=minimal');
      check(S, 'a disposable Offer is created', r.status === 201, `HTTP ${r.status} id ${id}`);
      if (r.status !== 201) throw new FatalError('could not create the Offer');
      created.offers.push({ id, account: a.label });
      return id;
    } },
    { parent: OWNER, bytes: images.png, type: 'image/png', ext: 'png', create: async () => {
      const id = randomUUID();
      const r = await rest(a, 'POST', '/rest/v1/owners', { id, owner_id: a.uid, name: `staging-e2e ${RUN_ID} quotation-regression`, notes: 'Quotation staging regression (disposable)' }, 'return=minimal');
      check(S, 'a disposable Owner is created', r.status === 201, `HTTP ${r.status} id ${id}`);
      if (r.status !== 201) throw new FatalError('could not create the Owner');
      created.owners.push({ id, account: a.label });
      return id;
    } },
  ];

  const live = {};
  for (const spec of parents) {
    const { parent, bytes, type, ext } = spec;
    const parentId = await spec.create();
    const mediaId = randomUUID();
    const auth = await callWorker(a, 'POST', `${parent.route}/authorize`,
      { [parent.idField]: parentId, mediaObjectId: mediaId, contentType: type, contentLength: bytes.length, originalFileName: 'regression' });
    const keyOk = auth.body?.objectKey === `profiles/${a.uid}/${parent.segment}/${parentId}/${mediaId}.${ext}`;
    check(S, `${parent.name} authorize still issues a private upload under its own prefix (profiles/<A>/${parent.segment}/<id>/)`,
      auth.status === 200 && auth.body?.status === 'pending' && keyOk && auth.body?.mediaType === 'image', coded(auth));
    if (auth.status !== 200) continue;
    created.media.push({ id: mediaId, role: `${parent.name} (regression)`, quotationId: null, account: a.label, contentType: type });
    const put = await putBytes(auth.body.presignedUrl, bytes, type);
    const conf = await callWorker(a, 'POST', `${parent.route}/confirm`, { [parent.idField]: parentId, mediaObjectId: mediaId }, { timeout: 120_000 });
    check(S, `${parent.name}: private PUT → confirm unchanged (200, bound to this ${parent.name})`, put === 200 && conf.status === 200 && conf.body?.[parent.idField] === parentId, `PUT ${put}, confirm ${conf.status}`);
    const again = await callWorker(a, 'POST', `${parent.route}/confirm`, { [parent.idField]: parentId, mediaObjectId: mediaId });
    check(S, `${parent.name}: a repeated confirm is idempotent (alreadyConfirmed)`, again.status === 200 && again.body?.alreadyConfirmed === true, coded(again));
    const list = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${parentId}`);
    const item = Array.isArray(list.body?.media) ? list.body.media.find((m) => m.mediaObjectId === mediaId) : null;
    const got = item?.url ? await getBytes(item.url) : null;
    check(S, `${parent.name}: listing and signed GET return the exact bytes`, Boolean(item) && got?.status === 200 && sha256(got.bytes) === sha256(bytes), `HTTP ${list.status}/${got?.status ?? '-'}`);
    const links = await rest(a, 'GET', `/rest/v1/${parent.linkTable}?media_id=eq.${mediaId}&select=${parent.linkColumn},media_id`);
    check(S, `${parent.name}: linked once in ${parent.linkTable}, to this ${parent.name} only`, links.status === 200 && links.body?.length === 1 && links.body[0][parent.linkColumn] === parentId, `${links.body?.length ?? '?'} link(s)`);
    const unknown = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${randomUUID()}`);
    check(S, `${parent.name}: an unknown ${parent.name} is still 404 ${parent.notFound}`, unknown.status === 404 && unknown.body?.code === parent.notFound, coded(unknown));
    live[parent.name] = { parentId, mediaId, bytes, type };
  }

  // Quotation routing does not collide with Offer or Owner.
  const before = await qState(a, q1);
  for (const parent of [OFFER, OWNER]) {
    const asQuotation = await qList(a, live[parent.name]?.parentId ?? randomUUID());
    check(S, `an ${parent.name} id on the Quotation routes: 404 quotation_not_found`, asQuotation.status === 404 && asQuotation.body?.code === 'quotation_not_found', coded(asQuotation));
    const quotationAs = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${q1}`);
    check(S, `a Quotation id on the ${parent.name} routes: 404 ${parent.notFound}`, quotationAs.status === 404 && quotationAs.body?.code === parent.notFound, coded(quotationAs));
    const spec = live[parent.name];
    if (!spec) continue;
    const logoOnQ = await qConfirm(a, q1, 'office_logo', spec.mediaId, c.logo.id);
    check(S, `${parent.name} media cannot be confirmed as a Quotation logo: 409 media_mismatch`, logoOnQ.status === 409 && logoOnQ.body?.code === 'media_mismatch', coded(logoOnQ));
    const reuse = await qAuthorize(a, q1, 'office_logo', c.logo.id, spec.mediaId, spec.type, spec.bytes.length);
    check(S, `${parent.name} media id cannot be reused for a Quotation upload: 409 idempotency_mismatch`, reuse.status === 409 && reuse.body?.code === 'idempotency_mismatch', coded(reuse));
    // A PDF is not an Offer/Owner media type at all, so its authorize is refused earlier (400) than an id reuse (409).
    for (const [label, mediaId, type, len, refusal] of [
      ['Quotation logo', c.logo.id, 'image/jpeg', c.logo.bytes.length, [409, 'idempotency_mismatch']],
      ['Quotation PDF', c.pdf.id, 'application/pdf', c.pdf.bytes.length, [400, 'unsupported_media_type']],
    ]) {
      const conf = await callWorker(a, 'POST', `${parent.route}/confirm`, { [parent.idField]: spec.parentId, mediaObjectId: mediaId });
      check(S, `a ${label} id cannot be confirmed on the ${parent.name} routes: 409 media_mismatch`, conf.status === 409 && conf.body?.code === 'media_mismatch', coded(conf));
      const auth = await callWorker(a, 'POST', `${parent.route}/authorize`,
        { [parent.idField]: spec.parentId, mediaObjectId: mediaId, contentType: type, contentLength: len, originalFileName: 'collide' });
      check(S, `a ${label} id cannot be authorized on the ${parent.name} routes: ${refusal[0]} ${refusal[1]}`, auth.status === refusal[0] && auth.body?.code === refusal[1], coded(auth));
    }
    const wrongList = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${spec.parentId}`);
    check(S, `the ${parent.name}'s listing contains only its own media (no Quotation logo/PDF)`,
      wrongList.status === 200 && wrongList.body?.media?.length === 1 && wrongList.body.media[0].mediaObjectId === spec.mediaId, `${wrongList.body?.media?.length ?? '?'} item(s)`);
  }
  const after = await qState(a, q1);
  check(S, 'none of it changed the Quotation (slots and version)', after.row?.office_logo_media_id === before.row?.office_logo_media_id &&
    after.row?.pdf_media_id === before.row?.pdf_media_id && Number(after.row?.version) === Number(before.row?.version));

  // Offer / Owner removal still tombstones and refuses reuse.
  for (const parent of [OFFER, OWNER]) {
    const spec = live[parent.name];
    if (!spec) continue;
    const removed = await callWorker(a, 'POST', `${parent.route}/remove`, { [parent.idField]: spec.parentId, mediaObjectId: spec.mediaId });
    const row = await mediaRow(a, spec.mediaId);
    check(S, `${parent.name}: removal still succeeds and tombstones the media (deleted)`, removed.status === 200 && removed.body?.removed === true && row?.status === 'deleted', `${coded(removed)} ${row?.status ?? ''}`);
    const back = await callWorker(a, 'POST', `${parent.route}/authorize`,
      { [parent.idField]: spec.parentId, mediaObjectId: spec.mediaId, contentType: spec.type, contentLength: spec.bytes.length, originalFileName: 'again' });
    check(S, `${parent.name}: a removed id still answers 410 media_removed`, back.status === 410 && back.body?.code === 'media_removed', coded(back));
  }

  // Profile route smoke (read-only; never confirms a profile image).
  const profile = await callWorker(a, 'GET', '/profile-image-url');
  check(S, 'profile: the image lookup still answers 200 for the account', profile.status === 200, `HTTP ${profile.status}`);
  const anonymous = await callWorker(null, 'GET', '/profile-image-url');
  check(S, 'profile: the lookup without a session is still 401', anonymous.status === 401, `HTTP ${anonymous.status}`);
  const foreign = await callWorker(a, 'POST', '/authorize', { userId: randomUUID(), contentType: 'image/jpeg', contentLength: images.jpeg.length });
  check(S, 'profile: a foreign userId in the body is still refused (403)', foreign.status === 403, `HTTP ${foreign.status}`);
}

/** Removal of the bound logo and PDF, idempotency, and the final state. */
async function sectionRemoval(c) {
  const { a, q1 } = c;
  const S = 'removal';
  const logoList = await qList(a, q1);
  const logoUrl = logoList.body?.media?.office_logo?.url;
  const pdfUrl = logoList.body?.media?.quotation_pdf?.url;
  let ver = await version(a, q1);

  const removeLogo = await qRemove(a, q1, 'office_logo', c.logo.id);
  ver += 1;
  const st1 = await qState(a, q1);
  const logoRow = await mediaRow(a, c.logo.id);
  check(S, 'removing the bound logo: 200 removed, the previous media is reported', removeLogo.status === 200 && removeLogo.body?.removed === true &&
    removeLogo.body?.previousMediaId === c.logo.id, coded(removeLogo));
  check(S, 'hosted read-back: the logo slot is cleared (version +1), the PDF slot is untouched',
    st1.row?.office_logo_media_id === null && st1.row.pdf_media_id === c.pdf.id && Number(st1.row.version) === ver, `v${st1.row?.version}`);
  check(S, 'the removed logo left the live lifecycle (pending_delete, or deleted once its bytes were removed)', RETIRED.includes(logoRow?.status), logoRow?.status ?? 'no row');
  const links = await linkRows(a, q1);
  check(S, "its 'logo' link is gone and the 'pdf' link remains", links?.length === 1 && links[0].role === 'pdf' && links[0].media_id === c.pdf.id, `${links?.length ?? '?'} link(s)`);
  if (logoUrl) {
    const gone = await getBytes(logoUrl);
    check(S, "the removed logo's bytes are gone from private R2 (its earlier signed link no longer returns them)", gone.status !== 200 && gone.status !== 206, `HTTP ${gone.status}`);
  }
  const listed = await qList(a, q1);
  check(S, 'owner retrieval: the logo is now null, the PDF still listed', listed.status === 200 && listed.body?.media?.office_logo === null &&
    listed.body.media.quotation_pdf?.mediaObjectId === c.pdf.id, coded(listed));
  const again = await qRemove(a, q1, 'office_logo', null);
  check(S, 'removing an already-empty slot is idempotent: 200, version unchanged', again.status === 200 && (await version(a, q1)) === ver, coded(again));
  const staleAfter = await qRemove(a, q1, 'office_logo', c.logo.id);
  check(S, 'a stale remove naming the old logo against the now-empty slot changes nothing (200 idempotent, version unchanged)',
    staleAfter.status === 200 && (await version(a, q1)) === ver, coded(staleAfter));

  const removePdf = await qRemove(a, q1, 'quotation_pdf', c.pdf.id);
  ver += 1;
  const st2 = await qState(a, q1);
  const pdfRow = await mediaRow(a, c.pdf.id);
  check(S, 'removing the bound PDF: 200 removed, the previous media is reported', removePdf.status === 200 && removePdf.body?.removed === true &&
    removePdf.body?.previousMediaId === c.pdf.id, coded(removePdf));
  check(S, 'hosted read-back: both media slots are null, version +1', st2.row?.office_logo_media_id === null && st2.row.pdf_media_id === null &&
    Number(st2.row.version) === ver, `v${st2.row?.version}`);
  check(S, 'the removed PDF left the live lifecycle', RETIRED.includes(pdfRow?.status), pdfRow?.status ?? 'no row');
  check(S, 'no quotation_media links remain for the Quotation', (await linkRows(a, q1))?.length === 0);
  if (pdfUrl) {
    const gone = await getBytes(pdfUrl);
    check(S, "the removed PDF's bytes are gone from private R2", gone.status !== 200 && gone.status !== 206, `HTTP ${gone.status}`);
  }
  const againPdf = await qRemove(a, q1, 'quotation_pdf', null);
  check(S, 'removing an already-empty PDF slot is idempotent: 200, version unchanged', againPdf.status === 200 && (await version(a, q1)) === ver, coded(againPdf));
  const finalList = await qList(a, q1);
  check(S, 'final owner retrieval: no logo and no PDF', finalList.status === 200 && finalList.body?.media?.office_logo === null && finalList.body.media.quotation_pdf === null);
  const q2 = await qState(a, c.q2);
  check(S, "the second Quotation was never touched (version 1, no media)", Number(q2.row?.version) === 1 && q2.row.office_logo_media_id === null && q2.row.pdf_media_id === null);
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
    startedAt,
    finishedAt: new Date().toISOString(),
    workerHost: new URL(cfg.workerUrl).host,
    bucket: STAGING_BUCKET,
    summary: { pass, fail },
    ...extra,
    results,
    created,
  };
  mkdirSync(dirname(cfg.reportPath), { recursive: true });
  writeFileSync(cfg.reportPath, JSON.stringify(report, null, 2));
  console.log(`\n${fail === 0 ? 'ALL PASSED' : 'FAILURES'}: ${pass} passed, ${fail} failed. Report: ${cfg.reportPath}`);
  return fail;
}

/** Runs the whole acceptance with [config]; resolves to the process exit code. */
export async function run(config) {
  cfg = { r2HostSuffix: R2_HOST_SUFFIX, ...config };
  startedAt = new Date().toISOString();
  const images = loadImages();
  console.log(`Quotation media staging acceptance ${RUN_ID} against ${new URL(cfg.workerUrl).host}\n`);
  let accounts = {};
  try {
    await section('gate', sectionGate);
    const a = await signIn('A', cfg.a);
    if (!check('setup', 'account A is the designated test account', a.uid === cfg.a.expectedUid)) {
      throw new FatalError('the signed-in account A is not the designated test account; nothing was written');
    }
    const b = await signIn('B', cfg.b);
    if (!check('setup', 'account B is a different account from A', b.uid !== a.uid)) {
      throw new FatalError('A and B must be two different accounts');
    }
    if (cfg.b.expectedUid && !check('setup', 'account B matches the expected temporary account id', b.uid === cfg.b.expectedUid)) {
      throw new FatalError('the signed-in account B is not the expected temporary account');
    }
    accounts = { a: a.uid, b: b.uid };
    const c = { a, b, images };
    c.q1 = await createQuotation(a, 'A-main');
    c.q2 = await createQuotation(a, 'A-second');
    c.qB = await createQuotation(b, 'B-control');

    await section('logo-refuse', () => sectionLogoRefusals(c));
    await section('logo', () => sectionLogo(c));
    if (!c.logo) throw new FatalError('the office-logo section did not leave a bound logo; later sections need it');
    await section('pdf', () => sectionPdf(c));
    if (!c.pdf) throw new FatalError('the PDF section did not leave a bound PDF; later sections need it');
    await section('role-parent', () => sectionRoleAndParent(c));
    await section('deleted', () => sectionDeleted(c));
    await section('direct-write', () => sectionDirectWrites(c));
    await section('cross-user', () => sectionCrossUser(c));
    await section('regression', () => sectionRegression(c));
    await section('removal', () => sectionRemoval(c));
  } catch (error) {
    check('run', 'run completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
  }
  return writeReport({ accounts }) === 0 ? 0 : 1;
}

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing ${name}. Run this through run_quotation_media_staging_acceptance.ps1.`);
    process.exit(2);
  }
  return value;
}

function loadConfig() {
  const workerUrl = required('BW_E2E_WORKER_URL').replace(/\/+$/, '');
  if (!STAGING_URL_PATTERN.test(workerUrl)) {
    console.error('BW_E2E_WORKER_URL must be the staging workers.dev URL (https://r2-profile-upload-staging.<subdomain>.workers.dev).');
    process.exit(2);
  }
  const a = { email: required('BW_E2E_A_EMAIL').trim(), password: required('BW_E2E_A_PASSWORD'), expectedUid: process.env.BW_E2E_A_UID || DESIGNATED_A_UID };
  const b = { email: required('BW_E2E_B_EMAIL').trim(), password: required('BW_E2E_B_PASSWORD'), expectedUid: process.env.BW_E2E_B_UID || null };
  if (a.email.toLowerCase() === b.email.toLowerCase()) {
    console.error('Accounts A and B must be different accounts.');
    process.exit(2);
  }
  return {
    workerUrl,
    stagingKey: required('BW_E2E_STAGING_KEY'),
    a,
    b,
    reportPath: process.env.BW_E2E_REPORT_PATH || join(REPORTS, `quotation_media_${RUN_ID}.json`),
  };
}

function offlineCheck() {
  const images = loadImages();
  const pdf = makePdf('check');
  const ok = images.jpeg[0] === 0xff && images.jpeg[1] === 0xd8 && images.png[0] === 0x89 && images.webp.toString('latin1', 8, 12) === 'WEBP' &&
    pdf.toString('latin1', 0, 8) === '%PDF-1.4' && sha256(makePdf('a')) !== sha256(makePdf('a')) &&
    sanitize('see https://x.test/a?X-Amz-Signature=abc now') === 'see <url> now' &&
    sanitize('token eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl end') === 'token <jwt> end' &&
    expectedKey('u', 'q', 'office_logo', 'm', 'image/webp') === 'profiles/u/quotations/q/office_logo/m.webp' &&
    expectedKey('u', 'q', 'quotation_pdf', 'm', 'application/pdf') === 'profiles/u/quotations/q/quotation_pdf/m.pdf' &&
    STAGING_URL_PATTERN.test('https://r2-profile-upload-staging.example.workers.dev') &&
    !STAGING_URL_PATTERN.test('https://media-api.brokerwallet.ae') && DESIGNATED_A_UID.length === 36;
  console.log(ok ? 'OFFLINE CHECK PASSED' : 'OFFLINE CHECK FAILED');
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.BW_E2E_OFFLINE_CHECK === '1') offlineCheck();
  run(loadConfig()).then((code) => process.exit(code));
}
