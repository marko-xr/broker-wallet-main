// Broker Wallet — Quotation private media PRODUCTION smoke (narrow).
//
// Run it only through run_quotation_media_production_smoke.ps1, in the owner's
// own terminal. It targets the PRODUCTION Worker (https://media-api.brokerwallet.ae,
// private bucket `broker-wallet-media`) after the Quotation-capable Worker is
// promoted, as the designated test-only account A only (uid must equal
// BW_E2E_A_UID, default 317d7619-01da-4420-8c7f-fe7c3fc2d6e7). There is no
// staging gate on Production and no second account.
//
// It is deliberately NOT the 203-check staging suite. It proves, once each:
//   - the Quotation routes are live and authenticated (credential-free checks);
//   - one office logo and one PDF go through authorize → private signed PUT →
//     confirm → hosted read-back → signed GET → remove, in the PRODUCTION
//     bucket under the exact expected key prefix;
//   - the shared Worker's Offer, Owner and profile routes still answer, and do
//     not collide with the Quotation routes (no media is created or kept there).
//
// It creates ONE temporary Quotation, plus one temporary Offer and one Owner
// (names start "production-smoke"), and leaves them in place — the sweeps are
// off. The report lists their ids for a narrow cleanup of exactly those ids.
//
// Output and the JSON report hold PASS/FAIL, HTTP statuses, Worker codes and
// record/media ids. Never a token, password, email, object key or URL.
// Node built-ins only: no `npm install` is needed.

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const PROD_URL = 'https://media-api.brokerwallet.ae';
const PROD_BUCKET = 'broker-wallet-media';
const DESIGNATED_A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const R2_HOST_SUFFIX = '.r2.cloudflarestorage.com';
const PUT_TTL = 300;
const GET_TTL = 900;
const RETIRED = ['pending_delete', 'deleted'];

const ROLES = Object.freeze({
  office_logo: { link: 'logo', column: 'office_logo_media_id', mediaType: 'image', folder: 'office_logo' },
  quotation_pdf: { link: 'pdf', column: 'pdf_media_id', mediaType: 'pdf', folder: 'quotation_pdf' },
});
const EXTENSIONS = Object.freeze({ 'image/jpeg': 'jpg', 'application/pdf': 'pdf' });
const OFFER = Object.freeze({ name: 'Offer', route: '/offer-media', idField: 'offerId', segment: 'offers', notFound: 'offer_not_found' });
const OWNER = Object.freeze({ name: 'Owner', route: '/owner-media', idField: 'ownerRecordId', segment: 'owners', notFound: 'owner_not_found' });

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');
const RUN_ID = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

const results = [];
const created = { quotations: [], media: [], offers: [], owners: [] };
let cfg;
let startedAt;

function check(section, name, ok, detail = '') {
  results.push({ section, name, ok: Boolean(ok), detail: sanitize(detail) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${section}] ${name}${detail ? `  (${sanitize(detail)})` : ''}`);
  return Boolean(ok);
}

/** Removes anything URL- or token-shaped, so no link or credential is printed. */
export function sanitize(value) {
  return String(value ?? '')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<jwt>')
    .slice(0, 300);
}

class StepError extends Error {}
class FatalError extends StepError {}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function loadJpeg() {
  return readFileSync(join(HERE, 'fixtures', 'photo.jpg'));
}

export function makePdf(label) {
  const text = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' +
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' +
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n' +
    `% production-smoke ${label} ${randomUUID()}\n` +
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
    const reason = String(body?.error_code ?? body?.error ?? '').replace(/[^a-z0-9_]/gi, '').slice(0, 40);
    throw new FatalError(`sign-in ${label} failed (HTTP ${res.status}${reason ? ` ${reason}` : ''})`);
  }
  return { label, token: body.access_token, uid: body.user.id };
}

async function callWorker(session, method, path, body, { timeout = 60_000 } = {}) {
  const headers = {};
  if (session) headers.Authorization = `Bearer ${session.token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await timedFetch(`${cfg.workerUrl}${path}`,
    { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }, timeout);
  return { status: res.status, body: await safeJson(res) };
}

async function rest(session, method, path, body, prefer) {
  const headers = { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${session.token}` };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;
  const res = await timedFetch(`${SUPABASE_URL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
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

const coded = (r) => `HTTP ${r.status}${r.body?.code ? ` ${r.body.code}` : ''}`;
const qAuthorize = (s, quotationId, role, expectedMediaId, mediaObjectId, contentType, contentLength) =>
  callWorker(s, 'POST', '/quotation-media/authorize',
    { quotationId, role, expectedMediaId, mediaObjectId, contentType, contentLength, originalFileName: 'production-smoke' });
const qConfirm = (s, quotationId, role, mediaObjectId, expectedMediaId) =>
  callWorker(s, 'POST', '/quotation-media/confirm', { quotationId, role, mediaObjectId, expectedMediaId }, { timeout: 120_000 });
const qRemove = (s, quotationId, role, expectedMediaId) =>
  callWorker(s, 'POST', '/quotation-media/remove', { quotationId, role, expectedMediaId });
const qList = (s, quotationId) => callWorker(s, 'GET', `/quotation-media?quotationId=${quotationId}`);

function expectedKey(uid, quotationId, role, mediaId, contentType) {
  return `profiles/${uid}/quotations/${quotationId}/${ROLES[role].folder}/${mediaId}.${EXTENSIONS[contentType]}`;
}

/** Short-lived, signed, and addressing the PRODUCTION bucket and exactly [objectKey]. */
function isPrivateProductionUrl(url, objectKey, ttl) {
  try {
    const u = new URL(url);
    const encoded = objectKey.split('/').map(encodeURIComponent).join('/');
    return u.protocol === 'https:' && u.hostname.endsWith(cfg.r2HostSuffix) && u.pathname === `/${PROD_BUCKET}/${encoded}` &&
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

async function qState(s, id) {
  const r = await rest(s, 'GET', `/rest/v1/quotations?id=eq.${id}&select=id,owner_id,version,deleted_at,office_logo_media_id,pdf_media_id`);
  return { status: r.status, row: Array.isArray(r.body) ? (r.body[0] ?? null) : undefined, raw: r.body };
}

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

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

async function sectionCredentialFree() {
  const S = 'credential-free';
  const probe = `/quotation-media?quotationId=${randomUUID()}`;
  const list = await callWorker(null, 'GET', probe);
  if (list.status === 404) {
    throw new FatalError('GET /quotation-media answered 404: the Quotation routes are not live on Production');
  }
  check(S, 'Quotation list without a session: 401 (the routes are live)', list.status === 401, `HTTP ${list.status}`);
  for (const route of ['authorize', 'confirm', 'remove']) {
    const r = await callWorker(null, 'POST', `/quotation-media/${route}`, {});
    check(S, `Quotation ${route} without a session: 401`, r.status === 401, `HTTP ${r.status}`);
  }
  const forged = { token: 'not-a-valid-session' };
  const badList = await callWorker(forged, 'GET', probe);
  const badAuth = await callWorker(forged, 'POST', '/quotation-media/authorize',
    { quotationId: randomUUID(), role: 'office_logo', expectedMediaId: null, contentType: 'image/jpeg', contentLength: 100 });
  check(S, 'an invalid session token: 401 on list and authorize', badList.status === 401 && badAuth.status === 401, `${badList.status}/${badAuth.status}`);
  const unknown = await callWorker(null, 'GET', '/nope');
  check(S, 'an unknown route: 404', unknown.status === 404, `HTTP ${unknown.status}`);
  for (const [label, method, path] of [
    ['Offer authorize', 'POST', '/offer-media/authorize'], ['Owner authorize', 'POST', '/owner-media/authorize'],
    ['profile authorize', 'POST', '/authorize'], ['profile image lookup', 'GET', '/profile-image-url'],
  ]) {
    const r = await callWorker(null, method, path, method === 'POST' ? {} : undefined);
    check(S, `${label} without a session: 401 (authentication wall unchanged)`, r.status === 401, `HTTP ${r.status}`);
  }
}

async function createQuotation(a) {
  const id = randomUUID();
  const r = await rest(a, 'POST', '/rest/v1/rpc/save_quotation', {
    p_quotation_id: id, p_expected_version: null,
    p_header: {
      property_title: `production-smoke ${RUN_ID}`, property_type: null, parking: null, subtitle: null, display_date: null,
      start_date_text: null, end_date_text: null, currency_code: 'AED', professional_fee: null, total_amount: null,
      number_of_installments: null, payment_type: null, insurance_amount: null, insurance_returnable: null,
      office_name: 'production-smoke', custom_note: null, welcome_message_mode: 'auto', custom_welcome_message: null,
    },
    p_downpayments: [], p_government_fees: null, p_administrative_fees: [],
  });
  const row = Array.isArray(r.body) ? r.body[0] : r.body;
  const ok = r.status === 200 && row?.quotation_id === id && Number(row?.resulting_version) === 1;
  check('setup', 'ONE temporary Production Quotation created through save_quotation', ok, `HTTP ${r.status} v${row?.resulting_version ?? '?'} id ${id}`);
  if (!ok) throw new FatalError('could not create the temporary Quotation');
  created.quotations.push({ label: 'production-smoke', id, account: 'A' });
  const st = await qState(a, id);
  check('setup', 'it reads back: owned by A, live, version 1, no media',
    st.row?.owner_id === a.uid && st.row.deleted_at === null && Number(st.row.version) === 1 &&
    st.row.office_logo_media_id === null && st.row.pdf_media_id === null);
  return id;
}

/** One role, once: authorize → PUT → confirm → read-back → signed GET → remove → read-back. */
async function smokeMedia(c, role, bytes, contentType, S) {
  const { a, q } = c;
  const spec = ROLES[role];
  let ver = await version(a, q);
  const id = randomUUID();
  const auth = await qAuthorize(a, q, role, null, id, contentType, bytes.length);
  const key = auth.body?.objectKey;
  check(S, 'authorize: 200 pending, same id, expected media type',
    auth.status === 200 && auth.body?.status === 'pending' && auth.body?.mediaObjectId === id && auth.body?.mediaType === spec.mediaType, coded(auth));
  if (auth.status !== 200) throw new FatalError(`${role} authorize failed`);
  created.media.push({ id, role, quotationId: q, account: 'A', contentType });
  check(S, `object key is exactly profiles/<A>/quotations/<Q>/${spec.folder}/<mediaId>.${EXTENSIONS[contentType]}`,
    key === expectedKey(a.uid, q, role, id, contentType));
  check(S, 'the signed PUT is short-lived and addresses the PRODUCTION bucket (broker-wallet-media) and that exact key',
    isPrivateProductionUrl(auth.body.presignedUrl, key, PUT_TTL));
  const put = await putBytes(auth.body.presignedUrl, bytes, contentType);
  check(S, 'the private signed PUT succeeds', put === 200, `HTTP ${put}`);
  const bare = await getBytes(unsigned(auth.body.presignedUrl));
  check(S, 'the bucket is private: the bare object URL without a signature is refused', bare.status !== 200 && bare.status !== 206, `HTTP ${bare.status}`);
  const conf = await qConfirm(a, q, role, id, null);
  check(S, 'confirm binds it (previous media null)', conf.status === 200 && conf.body?.mediaObjectId === id && (conf.body?.previousMediaId ?? null) === null, coded(conf));
  ver += 1;
  const st = await qState(a, q);
  check(S, `hosted read-back: ${spec.column} is this media, version +1, the other slot untouched`,
    st.row?.[spec.column] === id && Number(st.row.version) === ver, `v${st.row?.version}`);
  const row = await mediaRow(a, id);
  check(S, 'hosted read-back: media_objects ready, owner A, bucket broker-wallet-media, exact key, real size, correct type',
    row?.status === 'ready' && row.owner_id === a.uid && row.bucket === PROD_BUCKET && row.object_key === key &&
    row.content_type === contentType && row.media_type === spec.mediaType && Number(row.size_bytes) === bytes.length, row?.status ?? 'no row');
  const links = await linkRows(a, q);
  check(S, `hosted read-back: one quotation_media link, role '${spec.link}', ordinal 0, to this media`,
    links?.length === 1 && links[0].media_id === id && links[0].role === spec.link && links[0].ordinal === 0, `${links?.length ?? '?'} link(s)`);
  check(S, 'no signed URL is stored in the Quotation or media rows', !/X-Amz|https?:/.test(JSON.stringify([st.raw, row])));
  const list = await qList(a, q);
  const item = list.body?.media?.[role];
  const got = item?.url ? await getBytes(item.url) : null;
  check(S, 'owner signed GET: short-lived, production bucket, exact bytes',
    list.status === 200 && item?.mediaObjectId === id && isPrivateProductionUrl(item.url, key, GET_TTL) &&
    got?.status === 200 && sha256(got.bytes) === sha256(bytes), `HTTP ${got?.status ?? list.status}`);
  const rem = await qRemove(a, q, role, id);
  check(S, 'remove succeeds and reports the removed media', rem.status === 200 && rem.body?.removed === true && rem.body?.previousMediaId === id, coded(rem));
  ver += 1;
  const after = await qState(a, q);
  const retired = await mediaRow(a, id);
  const linksAfter = await linkRows(a, q);
  check(S, 'hosted read-back: the slot is cleared (version +1), the link is gone, the media left the live lifecycle',
    after.row?.[spec.column] === null && Number(after.row.version) === ver && linksAfter?.length === 0 && RETIRED.includes(retired?.status),
    `v${after.row?.version}, ${retired?.status ?? 'no row'}`);
  if (item?.url) {
    const gone = await getBytes(item.url);
    check(S, 'the object bytes are gone from private R2 (the earlier signed link no longer returns them)', gone.status !== 200 && gone.status !== 206, `HTTP ${gone.status}`);
  }
  const empty = await qList(a, q);
  check(S, 'owner retrieval afterwards: the slot is null', empty.status === 200 && empty.body?.media?.[role] === null, coded(empty));
}

async function sectionRegression(c) {
  const { a, q } = c;
  const S = 'regression';
  const jpeg = c.jpeg;
  const live = {};
  for (const parent of [OFFER, OWNER]) {
    const id = randomUUID();
    const insert = parent === OFFER
      ? { id, owner_id: a.uid, offer_type: 'rent', notes: `production-smoke ${RUN_ID}` }
      : { id, owner_id: a.uid, name: `production-smoke ${RUN_ID}`, notes: 'Quotation production smoke (temporary)' };
    const made = await rest(a, 'POST', parent === OFFER ? '/rest/v1/offers' : '/rest/v1/owners', insert, 'return=minimal');
    check(S, `a temporary ${parent.name} record is created`, made.status === 201, `HTTP ${made.status} id ${id}`);
    if (made.status !== 201) continue;
    (parent === OFFER ? created.offers : created.owners).push({ id, account: 'A' });
    live[parent.name] = id;
    const list = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${id}`);
    check(S, `${parent.name}: authenticated list answers 200 with no media`, list.status === 200 && Array.isArray(list.body?.media) && list.body.media.length === 0, coded(list));
    const unknown = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${randomUUID()}`);
    check(S, `${parent.name}: an unknown ${parent.name} is 404 ${parent.notFound}`, unknown.status === 404 && unknown.body?.code === parent.notFound, coded(unknown));
    const mediaId = randomUUID();
    const auth = await callWorker(a, 'POST', `${parent.route}/authorize`,
      { [parent.idField]: id, mediaObjectId: mediaId, contentType: 'image/jpeg', contentLength: jpeg.length, originalFileName: 'production-smoke' });
    const keyOk = auth.body?.objectKey === `profiles/${a.uid}/${parent.segment}/${id}/${mediaId}.jpg`;
    check(S, `${parent.name}: authorize answers 200 pending under its own prefix (profiles/<A>/${parent.segment}/<id>/), PRODUCTION bucket URL`,
      auth.status === 200 && auth.body?.status === 'pending' && keyOk && isPrivateProductionUrl(auth.body.presignedUrl, auth.body.objectKey, PUT_TTL), coded(auth));
    if (auth.status === 200) created.media.push({ id: mediaId, role: `${parent.name} (regression, never uploaded)`, quotationId: null, account: 'A', contentType: 'image/jpeg' });
    const withdraw = auth.status === 200
      ? await callWorker(a, 'POST', `${parent.route}/remove`, { [parent.idField]: id, mediaObjectId: mediaId })
      : { status: null, body: null };
    const row = await mediaRow(a, mediaId);
    check(S, `${parent.name}: the never-uploaded authorization is withdrawn (200), leaving no live media`,
      withdraw.status === 200 && (row === null || RETIRED.includes(row?.status)), `${coded(withdraw)} ${row === null ? 'row gone' : row?.status ?? ''}`);
  }
  // Routing isolation: ids never cross between Quotation, Offer and Owner routes.
  for (const parent of [OFFER, OWNER]) {
    if (live[parent.name]) {
      const asQuotation = await qList(a, live[parent.name]);
      check(S, `an ${parent.name} id on the Quotation routes: 404 quotation_not_found`, asQuotation.status === 404 && asQuotation.body?.code === 'quotation_not_found', coded(asQuotation));
    }
    const quotationAs = await callWorker(a, 'GET', `${parent.route}?${parent.idField}=${q}`);
    check(S, `the Quotation id on the ${parent.name} routes: 404 ${parent.notFound}`, quotationAs.status === 404 && quotationAs.body?.code === parent.notFound, coded(quotationAs));
  }
  const profile = await callWorker(a, 'GET', '/profile-image-url');
  check(S, 'profile: the image lookup answers 200 for the account', profile.status === 200, `HTTP ${profile.status}`);
  const foreign = await callWorker(a, 'POST', '/authorize', { userId: randomUUID(), contentType: 'image/jpeg', contentLength: jpeg.length });
  check(S, 'profile: a foreign userId in the body is refused (403)', foreign.status === 403, `HTTP ${foreign.status}`);
  const st = await qState(a, q);
  check(S, 'none of it touched the temporary Quotation (no media bound)', st.row?.office_logo_media_id === null && st.row.pdf_media_id === null);
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
    runId: RUN_ID, kind: 'production-smoke', startedAt, finishedAt: new Date().toISOString(),
    workerHost: new URL(cfg.workerUrl).host, bucket: PROD_BUCKET, summary: { pass, fail }, ...extra, results, created,
  };
  mkdirSync(dirname(cfg.reportPath), { recursive: true });
  writeFileSync(cfg.reportPath, JSON.stringify(report, null, 2));
  console.log(`\n${fail === 0 ? 'ALL PASSED' : 'FAILURES'}: ${pass} passed, ${fail} failed. Report: ${cfg.reportPath}`);
  return fail;
}

/** Runs the production smoke with [config]; resolves to the process exit code. */
export async function run(config) {
  cfg = { r2HostSuffix: R2_HOST_SUFFIX, ...config };
  startedAt = new Date().toISOString();
  console.log(`Quotation media PRODUCTION smoke ${RUN_ID} against ${new URL(cfg.workerUrl).host}\n`);
  let accounts = {};
  try {
    await section('credential-free', sectionCredentialFree);
    const a = await signIn('A', cfg.a);
    if (!check('setup', 'account A is the designated test account', a.uid === cfg.a.expectedUid)) {
      throw new FatalError('the signed-in account is not the designated test account; nothing was written');
    }
    accounts = { a: a.uid };
    const c = { a, jpeg: loadJpeg() };
    c.q = await createQuotation(a);
    await section('logo', () => smokeMedia(c, 'office_logo', c.jpeg, 'image/jpeg', 'logo'));
    await section('pdf', () => smokeMedia(c, 'quotation_pdf', makePdf('smoke'), 'application/pdf', 'pdf'));
    await section('regression', () => sectionRegression(c));
  } catch (error) {
    check('run', 'run completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
  }
  return writeReport({ accounts }) === 0 ? 0 : 1;
}

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing ${name}. Run this through run_quotation_media_production_smoke.ps1.`);
    process.exit(2);
  }
  return value;
}

function loadConfig() {
  const workerUrl = (process.env.BW_PROD_WORKER_URL || PROD_URL).replace(/\/+$/, '');
  if (workerUrl !== PROD_URL) {
    console.error(`BW_PROD_WORKER_URL must be ${PROD_URL} (the production Worker).`);
    process.exit(2);
  }
  return {
    workerUrl,
    a: { email: required('BW_E2E_A_EMAIL').trim(), password: required('BW_E2E_A_PASSWORD'), expectedUid: process.env.BW_E2E_A_UID || DESIGNATED_A_UID },
    reportPath: process.env.BW_E2E_REPORT_PATH || join(REPORTS, `quotation_media_production_smoke_${RUN_ID}.json`),
  };
}

function offlineCheck() {
  const ok = loadJpeg()[0] === 0xff && makePdf('x').toString('latin1', 0, 8) === '%PDF-1.4' &&
    expectedKey('u', 'q', 'quotation_pdf', 'm', 'application/pdf') === 'profiles/u/quotations/q/quotation_pdf/m.pdf' &&
    sanitize('see https://x.test/a?X-Amz-Signature=abc now') === 'see <url> now' && randomBytes(1).length === 1 &&
    PROD_URL === 'https://media-api.brokerwallet.ae' && PROD_BUCKET === 'broker-wallet-media';
  console.log(ok ? 'OFFLINE CHECK PASSED' : 'OFFLINE CHECK FAILED');
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.BW_E2E_OFFLINE_CHECK === '1') offlineCheck();
  run(loadConfig()).then((code) => process.exit(code));
}
