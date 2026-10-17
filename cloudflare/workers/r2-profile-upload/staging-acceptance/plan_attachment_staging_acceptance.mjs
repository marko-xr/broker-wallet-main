// Broker Wallet — Offer / Owner land-plan and plot-plan attachment staging acceptance.
//
// Run it only through run_plan_attachment_staging_acceptance.ps1, in the owner's own
// terminal, against the STAGING Worker (`r2-profile-upload-staging`, private bucket
// `broker-wallet-media-staging`) and the shared hosted database. The launcher asks for the
// staging gate key and the two test accounts' credentials with masked input and hands them to
// this process alone.
//
// Output and the JSON report hold PASS/FAIL per check, HTTP statuses, Worker codes and
// record/media ids. Never a token, key, password, email, account id, object key, presigned PUT
// URL or signed GET URL.
//
// What it proves, in order (section name in brackets):
//   [gate]          the staging key gate, and 401 without a session, on the eight plan routes
//   [session-gate]  the Single Active Device gate on those eight routes: a claimed session is
//                   accepted; a sign-in that never claimed is 403 session_superseded; a
//                   session that a newer one replaced is 403 session_superseded and cannot
//                   reclaim
//   [offer-plan]    an Offer's plan end to end: empty, JPEG, signed read with the exact bytes,
//                   outside the gallery, replacement that cannot lose the old plan (an
//                   unconfirmed upload, XLSX and PPTX renamed .docx, a stale slot), the PDF
//                   that replaces it, the old object retired, removal
//   [owner-plan]    an Owner's plan: DOC, XLS and PPT renamed .doc refused, DOCX replacing it,
//                   removal, then PNG replaced by WebP
//   [refuse]        unsupported types, over-size images and documents (refused at authorize,
//                   so nothing huge is uploaded), a type that is not its bytes, missing and
//                   unknown records, the three-waiting-uploads cap
//   [isolation]     another account, the other kind of record, another record, a gallery file
//                   used as a plan; the database: no client can write a plan pointer or call
//                   a plan function; a plan keeps the record's version and updated_at
//   [regression]    the existing Offer and Owner gallery routes, and one Quotation and one
//                   Profile route, still answer as before
//   [cleanup]       every plan removed, every candidate withdrawn, every test record
//                   soft-deleted, and no media row this run made is left outside a terminal
//                   state
//
// Accounts:
//   A  the designated test-only account (its uid must equal BW_E2E_A_UID, default
//      317d7619-01da-4420-8c7f-fe7c3fc2d6e7, as in the Quotation runner). Owns every
//      Offer and Owner under test.
//   B  a second test-only account, used for the cross-account checks and for the extra
//      sessions of the session gate.
//
// Every record it creates is new and disposable (names start "staging-e2e"). It never
// modifies a row it did not create, never confirms a profile image, and never deletes an
// account.
//
// Single Active Device: the database and the Worker refuse every session that is not the
// account's ACTIVE Broker Wallet session, and a password sign-in creates a new, unclaimed one.
// So each session signs in, is proven to belong to a test account, and only then CLAIMS
// (app_session_claim.mjs), exactly as the app does after a fresh sign-in. Claiming ENDS the
// account's other sessions, which is why the launcher asks for an explicit acknowledgement and
// why A and B must be designated or disposable test-only accounts, never a real user's.
//
// BW_E2E_OFFLINE_CHECK=1 exercises the local helpers and fixtures only (no network).
// Node built-ins only: no `npm install` is needed.

import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  AppSessionClaimError, claimAppSession, claimSessionForRun, isAppSessionCurrent, sessionIdFromAccessToken,
} from './app_session_claim.mjs';
import { makeDoc, makeDocx, makePdf, makePpt, makePptx, makeXls, makeXlsx } from './plan_attachment_fixtures.mjs';

const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const STAGING_BUCKET = 'broker-wallet-media-staging';
const STAGING_HEADER = 'X-Broker-Wallet-Staging-Key';
const STAGING_URL_PATTERN = /^https:\/\/r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$/;
const DESIGNATED_A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const R2_HOST_SUFFIX = '.r2.cloudflarestorage.com';
const MIB = 1024 * 1024;
const MAX_IMAGE_BYTES = 10 * MIB;
const MAX_DOCUMENT_BYTES = 25 * MIB;
const PUT_TTL = 300;
const GET_TTL = 900;
const SUPERSEDED = 'session_superseded';
const DOCX_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');
const RUN_ID = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

const KINDS = Object.freeze({
  offer: Object.freeze({
    name: 'Offer', plan: '/offer-plan', gallery: '/offer-media', idField: 'offerId', segment: 'offer-plans',
    table: 'offers', notFound: 'offer_not_found', confirmRpc: 'confirm_offer_plan_upload',
    removeRpc: 'remove_offer_plan', rpcParent: 'p_offer_id', linkTable: 'offer_media', linkColumn: 'offer_id',
  }),
  owner: Object.freeze({
    name: 'Owner', plan: '/owner-plan', gallery: '/owner-media', idField: 'ownerRecordId', segment: 'owner-plans',
    table: 'owners', notFound: 'owner_not_found', confirmRpc: 'confirm_owner_plan_upload',
    removeRpc: 'remove_owner_plan', rpcParent: 'p_owner_record_id', linkTable: 'owner_media', linkColumn: 'owner_record_id',
  }),
});
const OTHER = Object.freeze({ offer: 'owner', owner: 'offer' });

const TYPES = Object.freeze({
  jpeg: { label: 'JPEG', contentType: 'image/jpeg', ext: 'jpg', mediaType: 'image', kind: 'image' },
  png: { label: 'PNG', contentType: 'image/png', ext: 'png', mediaType: 'image', kind: 'image' },
  webp: { label: 'WebP', contentType: 'image/webp', ext: 'webp', mediaType: 'image', kind: 'image' },
  pdf: { label: 'PDF', contentType: 'application/pdf', ext: 'pdf', mediaType: 'pdf', kind: 'document' },
  doc: { label: 'DOC', contentType: 'application/msword', ext: 'doc', mediaType: 'unknown', kind: 'document' },
  docx: { label: 'DOCX', contentType: DOCX_TYPE, ext: 'docx', mediaType: 'unknown', kind: 'document' },
});

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

const results = [];
const created = { offers: [], owners: [], media: [] };
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

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const coded = (r) => `HTTP ${r.status}${r.body?.code ? ` ${r.body.code}` : r.code ? ` ${r.code}` : ''}`;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function loadFixtures() {
  const image = (name) => readFileSync(join(HERE, 'fixtures', name));
  return {
    jpeg: image('photo.jpg'),
    png: image('photo.png'),
    webp: image('photo.webp'),
    pdf: makePdf('plan'),
    doc: makeDoc(),
    docx: makeDocx('plan'),
    xlsx: makeXlsx(),
    pptx: makePptx(),
    xls: makeXls(),
    ppt: makePpt(),
  };
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

/** Claims [session] as its account's one active session; the database confirms it is current. */
const claimSession = (session) => claimSessionForRun({
  session, supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, check, FatalError,
});

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
// Plan operations
// ---------------------------------------------------------------------------

const planAuthorize = (kind, s, parentId, { id, expected = null, contentType, length, name = 'plan' }) =>
  callWorker(s, 'POST', `${KINDS[kind].plan}/authorize`, {
    [KINDS[kind].idField]: parentId,
    expectedMediaId: expected,
    mediaObjectId: id,
    contentType,
    contentLength: length,
    originalFileName: name,
  });

const planConfirm = (kind, s, parentId, id, expected = null) =>
  callWorker(s, 'POST', `${KINDS[kind].plan}/confirm`,
    { [KINDS[kind].idField]: parentId, mediaObjectId: id, expectedMediaId: expected }, { timeout: 120_000 });

const planRemove = (kind, s, parentId, expected = null, id) =>
  callWorker(s, 'POST', `${KINDS[kind].plan}/remove`,
    { [KINDS[kind].idField]: parentId, expectedMediaId: expected, ...(id ? { mediaObjectId: id } : {}) });

async function planGet(kind, s, parentId) {
  const r = await callWorker(s, 'GET', `${KINDS[kind].plan}?${KINDS[kind].idField}=${parentId}`);
  return { status: r.status, code: r.body?.code, plan: r.body && 'plan' in r.body ? r.body.plan : undefined, body: r.body };
}

/** The exact private key the Worker must issue for a plan upload. */
const expectedKey = (kind, uid, parentId, id, ext) => `profiles/${uid}/${KINDS[kind].segment}/${parentId}/${id}.${ext}`;

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

/** The same URL without its signature: what anyone could try who learned only the bucket and the key. */
function unsigned(url) {
  const u = new URL(url);
  u.search = '';
  return u.toString();
}

function rememberMedia(kind, s, parentId, id, contentType, route = 'plan') {
  created.media.push({ id, kind, route, parentId, account: s.label, contentType });
}

/** authorize (+ private PUT). Confirm is separate, so stale, early and mismatch cases can be driven. */
async function stage(kind, s, parentId, expected, type, bytes, { id = randomUUID(), name = 'plan', put = true } = {}) {
  const out = { kind, id, parentId, type, bytes };
  const auth = await planAuthorize(kind, s, parentId, { id, expected, contentType: type.contentType, length: bytes.length, name });
  out.authStatus = auth.status;
  out.authCode = auth.body?.code;
  out.authBody = auth.body;
  if (auth.status !== 200 || auth.body?.status !== 'pending') return out;
  rememberMedia(kind, s, parentId, id, type.contentType);
  out.url = auth.body.presignedUrl;
  out.urlOk = isPrivateStagingUrl(out.url, expectedKey(kind, s.uid, parentId, id, type.ext), auth.body.expiresInSeconds ?? PUT_TTL);
  if (put) out.putStatus = await putBytes(out.url, bytes, type.contentType);
  return out;
}

async function bind(s, out, expected) {
  const conf = await planConfirm(out.kind, s, out.parentId, out.id, expected);
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

/** The row, `null` when RLS hides it / it does not exist, `undefined` when the read failed. */
async function mediaRow(s, id) {
  const r = await rest(s, 'GET', `/rest/v1/media_objects?id=eq.${id}&select=id,bucket,media_type,content_type,size_bytes,status`);
  return r.status === 200 && Array.isArray(r.body) ? (r.body[0] ?? null) : undefined;
}

/** The record's own row (RLS), with its plan pointer and version stamps. */
async function parentRow(kind, s, id) {
  const r = await rest(s, 'GET', `/rest/v1/${KINDS[kind].table}?id=eq.${id}&select=id,plan_media_id,version,updated_at,deleted_at`);
  return r.status === 200 && Array.isArray(r.body) ? (r.body[0] ?? null) : undefined;
}

async function galleryLinks(kind, s, parentId) {
  const K = KINDS[kind];
  const r = await rest(s, 'GET', `/rest/v1/${K.linkTable}?${K.linkColumn}=eq.${parentId}&select=media_id`);
  return r.status === 200 && Array.isArray(r.body) ? r.body : null;
}

async function galleryList(kind, s, parentId) {
  const K = KINDS[kind];
  const r = await callWorker(s, 'GET', `${K.gallery}?${K.idField}=${parentId}`);
  return { status: r.status, code: r.body?.code, media: Array.isArray(r.body?.media) ? r.body.media : [] };
}

const RETIRED = ['deleted'];

async function createParent(kind, s, label) {
  const K = KINDS[kind];
  const id = randomUUID();
  const body = kind === 'offer'
    ? { id, owner_id: s.uid, offer_type: 'rent', notes: `staging-e2e ${RUN_ID} ${label}` }
    : { id, owner_id: s.uid, name: `staging-e2e ${RUN_ID} ${label}`, notes: 'Plan attachment staging acceptance (disposable)' };
  const r = await rest(s, 'POST', `/rest/v1/${K.table}`, body, 'return=minimal');
  check('setup', `new staging-only ${K.name} ${label} created by ${s.label}`, r.status === 201, `HTTP ${r.status} id ${id}`);
  if (r.status !== 201) throw new FatalError(`could not create ${K.name} ${label}`);
  created[`${kind}s`].push({ label, id, account: s.label });
  return id;
}

// ---------------------------------------------------------------------------
// The eight plan routes
// ---------------------------------------------------------------------------

/**
 * Every plan route. [current] says what a CURRENT session sees without any write: the read
 * answers "no such record" for a random id, and the three POST routes stop at the missing id
 * (400 invalid_request) before they read or write anything.
 */
function planRoutes() {
  return Object.keys(KINDS).flatMap((kind) => {
    const K = KINDS[kind];
    const post = (name, path) => ({ name: `${K.name} plan ${name}`, method: 'POST', path: `${K.plan}${path}`, body: {}, current: (r) => r.status === 400 && r.body?.code === 'invalid_request' });
    return [
      { name: `${K.name} plan read`, method: 'GET', path: `${K.plan}?${K.idField}=${randomUUID()}`, current: (r) => r.status === 404 && r.body?.code === K.notFound },
      post('authorize', '/authorize'),
      post('confirm', '/confirm'),
      post('remove', '/remove'),
    ];
  });
}

const isSuperseded = (r) => r.status === 403 && r.body?.code === SUPERSEDED;

/** [session]'s answer on each route: how many did not answer as [expect] says, and which. */
async function sweep(session, expect, { routes, onlyProbed = false, key }) {
  const chosen = onlyProbed ? routes.filter((route) => route.current) : routes;
  const wrong = [];
  for (const route of chosen) {
    const r = await callWorker(session, route.method, route.path, route.body, key === undefined ? {} : { key });
    if (!expect(r, route)) wrong.push(`${route.name} ${coded(r)}`);
  }
  return { total: chosen.length, wrong };
}

function verdict({ total, wrong }) {
  if (wrong.length === 0) return `${total}/${total} routes`;
  const shown = wrong.slice(0, 4).join('; ');
  return `${total - wrong.length}/${total} as expected; wrong: ${shown}${wrong.length > 4 ? ` (+${wrong.length - 4} more)` : ''}`;
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

async function sectionGate() {
  const S = 'gate';
  const routes = planRoutes();
  const none = await sweep(null, (r) => r.status === 403, { routes, key: null });
  check(S, `without the staging key: 403 on all ${routes.length} plan routes`, none.wrong.length === 0, verdict(none));
  const wrong = await sweep(null, (r) => r.status === 403, { routes, key: `wrong-${randomUUID()}` });
  check(S, `with a wrong staging key: 403 on all ${routes.length} plan routes`, wrong.wrong.length === 0, verdict(wrong));
  const anonymous = await sweep(null, (r) => r.status === 401, { routes });
  if (anonymous.wrong.some((w) => w.endsWith('HTTP 404'))) {
    throw new FatalError('a plan route answered 404 before authentication: the plan routes are not deployed on this staging version');
  }
  check(S, `with the key but without a session: 401 on all ${routes.length} plan routes (they are deployed)`, anonymous.wrong.length === 0, verdict(anonymous));
  const forged = await sweep({ token: 'not-a-valid-session' }, (r) => r.status === 401, { routes });
  check(S, `with the key and an invalid session token: 401 on all ${routes.length} plan routes`, forged.wrong.length === 0, verdict(forged));
}

async function sectionSessionGate(c) {
  const S = 'session-gate';
  const routes = planRoutes();
  const args = (session) => ({ supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, accessToken: session.token });
  const accepted = (r, route) => !isSuperseded(r) && r.status !== 401 && route.current(r);
  const allRefused = (session) => sweep(session, isSuperseded, { routes });
  const probedAccepted = (session) => sweep(session, accepted, { routes, onlyProbed: true });
  const tryClaim = async (session) => {
    try {
      await claimAppSession(args(session));
      return { ok: true, code: null };
    } catch (error) {
      if (error instanceof AppSessionClaimError) return { ok: false, code: error.code };
      throw error;
    }
  };
  const current = c.b; // claimed during setup: B's active session

  const first = await probedAccepted(current);
  check(S, 'A) the claimed session is accepted on all eight plan routes (no write is made)', first.wrong.length === 0, verdict(first));
  check(S, 'A) the database confirms the claimed session is current', (await isAppSessionCurrent(args(current))) === true);

  // C) a sign-in that never claims.
  const unclaimed = await signIn('B-unclaimed', cfg.b);
  const currentId = sessionIdFromAccessToken(current.token);
  const unclaimedId = sessionIdFromAccessToken(unclaimed.token);
  check(S, 'a second sign-in is a different Auth session from the claimed one', unclaimedId !== null && unclaimedId !== currentId);
  check(S, 'the database says a session that never claimed is not current', (await isAppSessionCurrent(args(unclaimed))) === false);
  const unclaimedOut = await allRefused(unclaimed);
  check(S, 'C) a never-claimed session is refused on all eight plan routes: 403 session_superseded', unclaimedOut.wrong.length === 0, verdict(unclaimedOut));
  const undisturbed = await probedAccepted(current);
  check(S, 'signing in without claiming displaced nothing: the claimed session is still accepted', undisturbed.wrong.length === 0, verdict(undisturbed));

  // B) a newer session claims and replaces the older one.
  const replacement = await signIn('B-replacement', cfg.b);
  await claimSession(replacement);
  const winner = await probedAccepted(replacement);
  check(S, 'B) the session that claimed last is accepted on all eight plan routes', winner.wrong.length === 0, verdict(winner));
  const displaced = await allRefused(current);
  check(S, 'B) the superseded session is refused on all eight plan routes: 403 session_superseded', displaced.wrong.length === 0, verdict(displaced));
  check(S, 'the database says the superseded session is no longer current', (await isAppSessionCurrent(args(current))) === false);
  const reclaim = await tryClaim(current);
  check(S, 'a displaced session cannot reclaim: its claim is refused with session_superseded',
    !reclaim.ok && reclaim.code === SUPERSEDED, reclaim.ok ? 'the claim was accepted' : reclaim.code);
  const kept = await probedAccepted(replacement);
  check(S, 'the refused reclaim displaced nothing: the replacement is still accepted', kept.wrong.length === 0, verdict(kept));
  const stillRefused = await allRefused(unclaimed);
  check(S, 'the never-claimed session is still refused after the replacement claimed', stillRefused.wrong.length === 0, verdict(stillRefused));
  // B's session for the rest of the run is the one that is current now. It is account B's
  // for every purpose that follows (the records it creates, the cleanup), so it is called B.
  replacement.label = 'B';
  c.b = replacement;
}

/** authorize → private PUT → confirm, then everything a plan must be afterwards. */
async function attachAndVerify(c, kind, s, parentId, expected, type, bytes, name) {
  const S = `${kind}-plan`;
  const label = `${KINDS[kind].name} ${type.label}`;
  const out = await stage(kind, s, parentId, expected, type, bytes, { name });
  check(S, `${label}: authorize reserves a private upload (one signed PUT for exactly the plan's key; the answer carries no key)`,
    out.authStatus === 200 && out.urlOk === true && out.authBody?.objectKey === undefined && out.authBody?.mediaType === type.mediaType, describe(out));
  if (out.authStatus !== 200) throw new StepError(`${label}: authorize failed`);
  check(S, `${label}: the private PUT is accepted`, out.putStatus === 200, `PUT ${out.putStatus}`);
  const conf = await bind(s, out, expected);
  check(S, `${label}: confirm proves the bytes and attaches the plan`,
    conf.status === 200 && conf.body?.mediaObjectId === out.id && (conf.body?.previousMediaId ?? null) === expected, coded(conf));
  return verifyCurrent(c, kind, s, parentId, out, type, bytes, name);
}

/** The old plan's object must be gone and its row retired once a replacement or a removal confirmed. */
async function expectRetired(c, kind, s, old, why) {
  const S = `${kind}-plan`;
  const label = `${KINDS[kind].name} ${old.type.label}`;
  const row = await mediaRow(s, old.id);
  check(S, `${label}: ${why}: its row is retired (deleted), never left ready or waiting`, row !== null && row !== undefined && RETIRED.includes(row.status), row ? row.status : 'no row');
  if (old.signedUrl) {
    const read = await getBytes(old.signedUrl);
    check(S, `${label}: ${why}: its private object is gone`, read.status === 404, `HTTP ${read.status}`);
  }
}

async function sectionOfferPlan(c) {
  const kind = 'offer';
  const S = 'offer-plan';
  const { a, fx } = c;
  const offer = c.offer1;

  const empty = await planGet(kind, a, offer);
  check(S, 'a new Offer has no plan: 200 with plan null', empty.status === 200 && empty.plan === null, coded(empty));
  const before = await parentRow(kind, a, offer);

  // An upload that has not arrived cannot be confirmed; a confirm that comes first changes nothing.
  const early = await stage(kind, a, offer, null, TYPES.jpeg, fx.jpeg, { name: 'plot-plan.jpg', put: false });
  check(S, 'JPEG: authorize before the bytes exist answers pending', early.authStatus === 200 && early.urlOk === true, describe(early));
  const tooSoon = await bind(a, early, null);
  check(S, 'JPEG: confirm before the bytes arrive: 409 upload_incomplete, nothing marked failed',
    tooSoon.status === 409 && tooSoon.body?.code === 'upload_incomplete', coded(tooSoon));
  check(S, 'JPEG: still no plan after that early confirm', (await planGet(kind, a, offer)).plan === null);
  early.putStatus = await putBytes(early.url, fx.jpeg, TYPES.jpeg.contentType);
  check(S, 'JPEG: the bytes arrive (private PUT)', early.putStatus === 200, `PUT ${early.putStatus}`);
  const attached = await bind(a, early, null);
  check(S, 'JPEG: confirm now attaches the plan (no previous plan)',
    attached.status === 200 && attached.body?.mediaObjectId === early.id && (attached.body?.previousMediaId ?? null) === null, coded(attached));
  const repeat = await bind(a, early, null);
  check(S, 'JPEG: a repeated confirm (a lost answer) reports alreadyConfirmed and changes nothing',
    repeat.status === 200 && repeat.body?.alreadyConfirmed === true, coded(repeat));
  const sameId = await planAuthorize(kind, a, offer, { id: early.id, expected: null, contentType: TYPES.jpeg.contentType, length: fx.jpeg.length });
  check(S, "JPEG: authorizing the current plan's own id answers ready: nothing to upload again",
    sameId.status === 200 && sameId.body?.status === 'ready' && !sameId.body?.presignedUrl, coded(sameId));
  const verified = await verifyCurrent(c, kind, a, offer, early, TYPES.jpeg, fx.jpeg, 'plot-plan.jpg');

  // The plan is its own attachment: outside the gallery, and the record's stamps stay.
  const gallery = await galleryList(kind, a, offer);
  check(S, "the plan is not an item of the Offer's gallery: the gallery list is empty", gallery.status === 200 && gallery.media.length === 0, `HTTP ${gallery.status}, ${gallery.media.length} item(s)`);
  const links = await galleryLinks(kind, a, offer);
  check(S, 'the plan has no offer_media link', links?.length === 0, `${links?.length ?? '?'} link(s)`);
  const after = await parentRow(kind, a, offer);
  check(S, "attaching a plan keeps the Offer's version and updated_at (it is an attachment, not an edit)",
    before && after && String(before.version) === String(after.version) && before.updated_at === after.updated_at,
    before && after ? `version ${before.version} -> ${after.version}` : 'no row');

  // F) A replacement can fail in four ways before it confirms; the old plan stays the plan through all of them.
  const replacement = await stage(kind, a, offer, early.id, TYPES.pdf, fx.pdf, { name: 'plot-plan.pdf' });
  check(S, 'PDF replacement: authorize and private PUT work while the JPEG is still the plan',
    replacement.authStatus === 200 && replacement.urlOk === true && replacement.putStatus === 200, describe(replacement));
  let now = await planGet(kind, a, offer);
  check(S, 'F) an uploaded but unconfirmed replacement changes nothing: the JPEG is still the plan', now.plan?.mediaObjectId === early.id, coded(now));
  check(S, 'F) the old plan stays ready while the replacement waits', (await mediaRow(a, early.id))?.status === 'ready');

  for (const [label, type, bytes] of [['XLSX renamed .docx', TYPES.docx, fx.xlsx], ['PPTX renamed .docx', TYPES.docx, fx.pptx]]) {
    const fake = await stage(kind, a, offer, early.id, type, bytes, { name: 'plan.docx' });
    const refused = await bind(a, fake, early.id);
    check(S, `F) ${label}: confirm is refused 422 media_type_mismatch`, refused.status === 422 && refused.body?.code === 'media_type_mismatch', `${describe(fake)}`);
    const row = await mediaRow(a, fake.id);
    check(S, `F) ${label}: the candidate is marked failed and its bytes are dropped`, row?.status === 'failed', row ? row.status : 'no row');
    now = await planGet(kind, a, offer);
    check(S, `F) ${label}: the old plan is still the plan`, now.plan?.mediaObjectId === early.id, coded(now));
    const again = await bind(a, fake, early.id);
    check(S, `F) ${label}: the refused upload stays refused (409 upload_rejected)`, again.status === 409 && again.body?.code === 'upload_rejected', coded(again));
    const withdrawn = await planRemove(kind, a, offer, early.id, fake.id);
    check(S, `F) ${label}: the failed candidate can be withdrawn`, withdrawn.status === 200 && withdrawn.body?.removed === true, coded(withdrawn));
  }

  const staleConfirm = await bind(a, replacement, null);
  check(S, 'F) a replacement that names the wrong current plan is refused: 409 stale_replacement', staleConfirm.status === 409 && staleConfirm.body?.code === 'stale_replacement', coded(staleConfirm));
  const staleId = randomUUID();
  const staleAuth = await planAuthorize(kind, a, offer, { id: staleId, expected: null, contentType: TYPES.pdf.contentType, length: fx.pdf.length });
  check(S, 'F) authorizing a new upload that does not name the current plan: 409 stale_replacement', staleAuth.status === 409 && staleAuth.body?.code === 'stale_replacement', coded(staleAuth));
  check(S, 'F) that refused authorize created no media row', (await mediaRow(a, staleId)) === null);
  now = await planGet(kind, a, offer);
  check(S, 'F) after every failed replacement the JPEG is still the plan', now.plan?.mediaObjectId === early.id, coded(now));

  // The valid replacement.
  const switched = await bind(a, replacement, early.id);
  check(S, 'PDF: the valid replacement confirms and becomes the plan; the answer names the plan it replaced',
    switched.status === 200 && switched.body?.mediaObjectId === replacement.id && switched.body?.previousMediaId === early.id, coded(switched));
  const pdf = await verifyCurrent(c, kind, a, offer, replacement, TYPES.pdf, fx.pdf, 'plot-plan.pdf');
  await expectRetired(c, kind, a, early, 'after the replacement');
  const replay = await bind(a, early, replacement.id);
  check(S, 'the replaced plan can never be confirmed again: 410 media_removed', replay.status === 410 && replay.body?.code === 'media_removed', coded(replay));

  // Removal.
  const staleRemove = await planRemove(kind, a, offer, early.id);
  check(S, 'remove that names a plan that is no longer current: 409 stale_replacement', staleRemove.status === 409 && staleRemove.body?.code === 'stale_replacement', coded(staleRemove));
  check(S, 'a refused removal leaves the plan', (await planGet(kind, a, offer)).plan?.mediaObjectId === replacement.id);
  const removed = await planRemove(kind, a, offer, replacement.id);
  check(S, 'remove names the current plan: it is removed', removed.status === 200 && removed.body?.removed === true && removed.body?.previousMediaId === replacement.id, coded(removed));
  const gone = await planGet(kind, a, offer);
  check(S, 'afterwards the Offer has no plan again', gone.status === 200 && gone.plan === null, coded(gone));
  await expectRetired(c, kind, a, replacement, 'after the removal');
  const parent = await parentRow(kind, a, offer);
  check(S, 'afterwards the record pointer is cleared and its version and updated_at are still the original ones',
    parent?.plan_media_id === null && before && String(parent.version) === String(before.version) && parent.updated_at === before.updated_at);
  const again = await planRemove(kind, a, offer, null);
  check(S, 'removing when there is no plan is harmless', again.status === 200 && again.body?.removed === true && (again.body?.previousMediaId ?? null) === null, coded(again));
  return { jpeg: verified, pdf };
}

/** Reads the plan again and checks it is [out]: the same checks as after an attach, without the upload. */
async function verifyCurrent(c, kind, s, parentId, out, type, bytes, name) {
  const S = `${kind}-plan`;
  const label = `${KINDS[kind].name} ${type.label}`;
  const got = await planGet(kind, s, parentId);
  const plan = got.plan;
  check(S, `${label}: the plan is read back with its type, name and size`,
    got.status === 200 && plan?.mediaObjectId === out.id && plan.contentType === type.contentType && plan.kind === type.kind &&
    plan.fileName === name && plan.sizeBytes === bytes.length, `${coded(got)} ${plan ? `${plan.kind} ${plan.contentType} ${plan.sizeBytes}` : 'no plan'}`);
  if (!plan?.url) throw new StepError(`${label}: no signed read was returned`);
  out.signedUrl = plan.url;
  check(S, `${label}: the signed read is a short-lived private link for exactly the plan's key`,
    isPrivateStagingUrl(plan.url, expectedKey(kind, s.uid, parentId, out.id, type.ext), got.body?.expiresInSeconds ?? GET_TTL));
  const read = await getBytes(plan.url);
  check(S, `${label}: the signed read returns the exact bytes`, read.status === 200 && sha256(read.bytes) === sha256(bytes), `HTTP ${read.status}, sha256 ${sha256(read.bytes).slice(0, 16)}`);
  const bare = await getBytes(unsigned(plan.url));
  check(S, `${label}: the object is not readable without the signature (the bucket is private)`, bare.status !== 200 && bare.status !== 206, `HTTP ${bare.status}`);
  const row = await mediaRow(s, out.id);
  check(S, `${label}: the media row is ready, in the staging bucket, with the real type and size`,
    row?.status === 'ready' && row.bucket === STAGING_BUCKET && row.media_type === type.mediaType &&
    row.content_type === type.contentType && Number(row.size_bytes) === bytes.length, row ? `${row.status} ${row.bucket} ${row.media_type} ${row.size_bytes}` : 'no row');
  const parent = await parentRow(kind, s, parentId);
  check(S, `${label}: the record's own pointer names this plan`, parent?.plan_media_id === out.id, parent ? 'pointer set' : 'no row');
  return out;
}

async function sectionOwnerPlan(c) {
  const kind = 'owner';
  const S = 'owner-plan';
  const { a, fx } = c;
  const owner = c.owner1;

  const empty = await planGet(kind, a, owner);
  check(S, 'a new Owner has no plan: 200 with plan null', empty.status === 200 && empty.plan === null, coded(empty));
  const before = await parentRow(kind, a, owner);
  const doc = await attachAndVerify(c, kind, a, owner, null, TYPES.doc, fx.doc, 'plot-plan.doc');

  for (const [label, bytes] of [['XLS renamed .doc', fx.xls], ['PPT renamed .doc', fx.ppt]]) {
    const fake = await stage(kind, a, owner, doc.id, TYPES.doc, bytes, { name: 'plan.doc' });
    const refused = await bind(a, fake, doc.id);
    check(S, `${label}: confirm is refused 422 media_type_mismatch`, refused.status === 422 && refused.body?.code === 'media_type_mismatch', describe(fake));
    const row = await mediaRow(a, fake.id);
    check(S, `${label}: the candidate is marked failed and its bytes are dropped`, row?.status === 'failed', row ? row.status : 'no row');
    const now = await planGet(kind, a, owner);
    check(S, `${label}: the DOC is still the plan`, now.plan?.mediaObjectId === doc.id, coded(now));
    const withdrawn = await planRemove(kind, a, owner, doc.id, fake.id);
    check(S, `${label}: the failed candidate can be withdrawn`, withdrawn.status === 200 && withdrawn.body?.removed === true, coded(withdrawn));
  }

  const docx = await attachAndVerify(c, kind, a, owner, doc.id, TYPES.docx, fx.docx, 'plot-plan.docx');
  await expectRetired(c, kind, a, doc, 'after the replacement');
  const removed = await planRemove(kind, a, owner, docx.id);
  check(S, 'remove names the current DOCX plan: it is removed', removed.status === 200 && removed.body?.removed === true && removed.body?.previousMediaId === docx.id, coded(removed));
  const gone = await planGet(kind, a, owner);
  check(S, 'afterwards the Owner has no plan again', gone.status === 200 && gone.plan === null, coded(gone));
  await expectRetired(c, kind, a, docx, 'after the removal');

  // The two other image types, replacing one another.
  const png = await attachAndVerify(c, kind, a, owner, null, TYPES.png, fx.png, 'plot-plan.png');
  const webp = await attachAndVerify(c, kind, a, owner, png.id, TYPES.webp, fx.webp, 'plot-plan.webp');
  await expectRetired(c, kind, a, png, 'after the replacement');
  const last = await planRemove(kind, a, owner, webp.id);
  check(S, 'remove names the current WebP plan: it is removed', last.status === 200 && last.body?.removed === true, coded(last));
  await expectRetired(c, kind, a, webp, 'after the removal');
  const parent = await parentRow(kind, a, owner);
  check(S, "the Owner's pointer is clear and its version and updated_at are the original ones after every change",
    parent?.plan_media_id === null && before && String(parent.version) === String(before.version) && parent.updated_at === before.updated_at);
}

async function sectionRefusals(c) {
  const kind = 'offer';
  const S = 'refuse';
  const { a, fx } = c;
  const offer = c.offer2;
  const authorizeAs = (contentType, length, extra = {}) => planAuthorize(kind, a, offer, { id: randomUUID(), contentType, length, ...extra });

  for (const contentType of ['image/gif', 'image/svg+xml', 'image/heic', 'application/zip', 'application/x-msdownload',
    'application/vnd.android.package-archive', 'application/octet-stream', 'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'video/mp4', 'text/html']) {
    const r = await authorizeAs(contentType, 1000);
    check(S, `authorize refuses ${contentType}: 400 unsupported_media_type`, r.status === 400 && r.body?.code === 'unsupported_media_type', coded(r));
  }
  const bigImage = await authorizeAs('image/jpeg', MAX_IMAGE_BYTES + 1);
  check(S, 'a JPEG over 10 MiB is refused at authorize: 400 image_too_large', bigImage.status === 400 && bigImage.body?.code === 'image_too_large', coded(bigImage));
  for (const type of [TYPES.pdf, TYPES.doc, TYPES.docx]) {
    const id = randomUUID();
    const r = await planAuthorize(kind, a, offer, { id, contentType: type.contentType, length: MAX_DOCUMENT_BYTES + 1 });
    check(S, `a ${type.label} over 25 MiB is refused at authorize, with no upload: 400 document_too_large`, r.status === 400 && r.body?.code === 'document_too_large', coded(r));
    check(S, `a refused ${type.label} authorize left no media row`, (await mediaRow(a, id)) === null);
  }
  // The limits themselves are allowed: authorized without any upload, then withdrawn.
  for (const [label, type, length] of [['a 25 MiB PDF', TYPES.pdf, MAX_DOCUMENT_BYTES], ['a 10 MiB PNG', TYPES.png, MAX_IMAGE_BYTES]]) {
    const id = randomUUID();
    const r = await planAuthorize(kind, a, offer, { id, contentType: type.contentType, length });
    if (r.status === 200) rememberMedia(kind, a, offer, id, type.contentType);
    check(S, `${label} (exactly at the limit) is accepted at authorize`, r.status === 200 && r.body?.status === 'pending', coded(r));
    const withdrawn = await planRemove(kind, a, offer, null, id);
    check(S, `${label}: the unused reservation is withdrawn`, withdrawn.status === 200 && withdrawn.body?.removed === true, coded(withdrawn));
  }
  const noExpected = await callWorker(a, 'POST', `${KINDS[kind].plan}/authorize`, {
    [KINDS[kind].idField]: offer, mediaObjectId: randomUUID(), contentType: 'image/jpeg', contentLength: 100,
  });
  check(S, 'authorize without expectedMediaId is refused: 400 invalid_request', noExpected.status === 400 && noExpected.body?.code === 'invalid_request', coded(noExpected));
  const noParent = await callWorker(a, 'POST', `${KINDS[kind].plan}/authorize`, { expectedMediaId: null, mediaObjectId: randomUUID(), contentType: 'image/jpeg', contentLength: 100 });
  check(S, 'authorize without the record id is refused: 400 invalid_request', noParent.status === 400 && noParent.body?.code === 'invalid_request', coded(noParent));
  const unknown = await planAuthorize(kind, a, randomUUID(), { id: randomUUID(), contentType: 'image/jpeg', length: 100 });
  check(S, 'authorize for a record that does not exist: 404 offer_not_found', unknown.status === 404 && unknown.body?.code === 'offer_not_found', coded(unknown));

  // A type that is not its bytes.
  const disguised = await stage(kind, a, offer, null, TYPES.jpeg, fx.png, { name: 'plan.jpg' });
  const mismatch = await bind(a, disguised, null);
  check(S, 'a PNG declared as a JPEG is refused at confirm: 422 media_type_mismatch', mismatch.status === 422 && mismatch.body?.code === 'media_type_mismatch', describe(disguised));
  check(S, 'that Offer still has no plan', (await planGet(kind, a, offer)).plan === null);
  const spare = await planRemove(kind, a, offer, null, disguised.id);
  check(S, 'the refused candidate is withdrawn', spare.status === 200 && spare.body?.removed === true, coded(spare));

  // At most three uploads wait for one record.
  const waiting = [];
  for (let i = 0; i < 3; i++) {
    const id = randomUUID();
    const r = await planAuthorize(kind, a, offer, { id, contentType: 'image/jpeg', length: fx.jpeg.length });
    if (r.status === 200) { waiting.push(id); rememberMedia(kind, a, offer, id, 'image/jpeg'); }
  }
  check(S, 'three plan uploads may wait for one Offer', waiting.length === 3, `${waiting.length} accepted`);
  const fourth = await authorizeAs('image/jpeg', fx.jpeg.length);
  check(S, 'a fourth waiting upload is refused: 409 plan_upload_limit', fourth.status === 409 && fourth.body?.code === 'plan_upload_limit', coded(fourth));
  let withdrawnAll = true;
  for (const id of waiting) {
    const r = await planRemove(kind, a, offer, null, id);
    withdrawnAll &&= r.status === 200 && r.body?.removed === true;
  }
  check(S, 'the three waiting uploads are withdrawn', withdrawnAll);
  const free = await authorizeAs('image/jpeg', fx.jpeg.length);
  if (free.status === 200) { rememberMedia(kind, a, offer, free.body.mediaObjectId, 'image/jpeg'); await planRemove(kind, a, offer, null, free.body.mediaObjectId); }
  check(S, 'after the withdrawals a new upload may wait again', free.status === 200, coded(free));
}

async function sectionIsolation(c) {
  const S = 'isolation';
  const { a, b, fx } = c;
  // Fixtures: an Offer and an Owner of A, each holding a plan; B's own Offer and Owner.
  const offerPlan = await stage('offer', a, c.offerIso, null, TYPES.jpeg, fx.jpeg, { name: 'iso.jpg' });
  await bind(a, offerPlan, null);
  const ownerPlan = await stage('owner', a, c.ownerIso, null, TYPES.docx, fx.docx, { name: 'iso.docx' });
  await bind(a, ownerPlan, null);
  check(S, "setup: A's Offer and A's Owner each hold a plan", offerPlan.confirmStatus === 200 && ownerPlan.confirmStatus === 200, `${offerPlan.confirmStatus}/${ownerPlan.confirmStatus}`);
  const unchanged = async (label) => {
    const o = await planGet('offer', a, c.offerIso);
    const w = await planGet('owner', a, c.ownerIso);
    return check(S, `${label}: A's Offer plan and Owner plan are untouched`, o.plan?.mediaObjectId === offerPlan.id && w.plan?.mediaObjectId === ownerPlan.id, `${coded(o)} / ${coded(w)}`);
  };

  // Another account.
  for (const [kind, parent, plan] of [['offer', c.offerIso, offerPlan], ['owner', c.ownerIso, ownerPlan]]) {
    const K = KINDS[kind];
    const read = await planGet(kind, b, parent);
    check(S, `B cannot read A's ${K.name} plan: 404 ${K.notFound}`, read.status === 404 && read.code === K.notFound, coded(read));
    const auth = await planAuthorize(kind, b, parent, { id: randomUUID(), expected: plan.id, contentType: 'image/png', length: fx.png.length });
    check(S, `B cannot authorize on A's ${K.name}: 404 ${K.notFound}`, auth.status === 404 && auth.body?.code === K.notFound, coded(auth));
    const conf = await planConfirm(kind, b, parent, plan.id, plan.id);
    check(S, `B cannot confirm on A's ${K.name}: 404 ${K.notFound}`, conf.status === 404 && conf.body?.code === K.notFound, coded(conf));
    const rem = await planRemove(kind, b, parent, plan.id);
    check(S, `B cannot remove A's ${K.name} plan: 404 ${K.notFound}`, rem.status === 404 && rem.body?.code === K.notFound, coded(rem));
    const takeId = await planAuthorize(kind, b, c[`${kind}B`], { id: plan.id, contentType: plan.type.contentType, length: plan.bytes.length });
    check(S, `B cannot use A's media id for B's own ${K.name}: 409 media_id_conflict`, takeId.status === 409 && takeId.body?.code === 'media_id_conflict', coded(takeId));
    check(S, `B cannot read A's plan media row through RLS`, (await mediaRow(b, plan.id)) === null);
    check(S, `B cannot read A's ${K.name} record or its pointer through RLS`, (await parentRow(kind, b, parent)) === null);
  }
  await unchanged('after every cross-account attempt');

  // The other kind of record: an id is only ever good for its own kind.
  for (const kind of ['offer', 'owner']) {
    const K = KINDS[kind];
    const other = OTHER[kind];
    const wrongParent = kind === 'offer' ? c.ownerIso : c.offerIso;
    const read = await planGet(kind, a, wrongParent);
    check(S, `an ${KINDS[other].name} id on the ${K.name} plan route: read answers 404 ${K.notFound}`, read.status === 404 && read.code === K.notFound, coded(read));
    const auth = await planAuthorize(kind, a, wrongParent, { id: randomUUID(), contentType: 'image/png', length: fx.png.length });
    check(S, `an ${KINDS[other].name} id on the ${K.name} plan route: authorize answers 404 ${K.notFound}`, auth.status === 404 && auth.body?.code === K.notFound, coded(auth));
  }
  // A plan's media id on the other kind's routes, and on another record of the same kind.
  const crossKinds = [
    ['the Offer plan on the Owner routes', 'owner', c.ownerIso, ownerPlan.id, offerPlan],
    ['the Owner plan on the Offer routes', 'offer', c.offerIso, offerPlan.id, ownerPlan],
  ];
  for (const [label, kind, parent, currentId, foreign] of crossKinds) {
    const auth = await planAuthorize(kind, a, parent, { id: foreign.id, expected: currentId, contentType: foreign.type.contentType, length: foreign.bytes.length });
    check(S, `${label}: authorize with that media id is refused 409 idempotency_mismatch`, auth.status === 409 && auth.body?.code === 'idempotency_mismatch', coded(auth));
    const conf = await planConfirm(kind, a, parent, foreign.id, currentId);
    check(S, `${label}: confirm is refused 409 media_mismatch`, conf.status === 409 && conf.body?.code === 'media_mismatch', coded(conf));
    const rem = await planRemove(kind, a, parent, currentId, foreign.id);
    check(S, `${label}: remove naming it as the candidate is refused 409 media_mismatch`, rem.status === 409 && rem.body?.code === 'media_mismatch', coded(rem));
  }
  for (const [label, kind, other, plan] of [
    ["Offer A's plan on another Offer of A", 'offer', c.offer2, offerPlan],
    ["Owner A's plan on another Owner of A", 'owner', c.owner2, ownerPlan],
  ]) {
    const auth = await planAuthorize(kind, a, other, { id: plan.id, contentType: plan.type.contentType, length: plan.bytes.length });
    check(S, `${label}: authorize with that media id is refused 409 idempotency_mismatch`, auth.status === 409 && auth.body?.code === 'idempotency_mismatch', coded(auth));
    const conf = await planConfirm(kind, a, other, plan.id, null);
    check(S, `${label}: confirm is refused 409 media_mismatch`, conf.status === 409 && conf.body?.code === 'media_mismatch', coded(conf));
    const rem = await planRemove(kind, a, other, null, plan.id);
    check(S, `${label}: remove naming it as the candidate is refused 409 media_mismatch`, rem.status === 409 && rem.body?.code === 'media_mismatch', coded(rem));
    check(S, `${label}: the other record still has no plan`, (await planGet(kind, a, other)).plan === null);
  }
  await unchanged('after every cross-kind and cross-record attempt');

  // A file under the gallery's key prefix is not a plan.
  const gid = randomUUID();
  const gauth = await callWorker(a, 'POST', '/offer-media/authorize', { offerId: c.offerIso, mediaObjectId: gid, contentType: 'image/jpeg', contentLength: fx.jpeg.length, originalFileName: 'gallery.jpg' });
  if (gauth.status === 200) rememberMedia('offer', a, c.offerIso, gid, 'image/jpeg', 'gallery');
  const gput = gauth.status === 200 ? await putBytes(gauth.body.presignedUrl, fx.jpeg, 'image/jpeg') : null;
  const gconf = await callWorker(a, 'POST', '/offer-media/confirm', { offerId: c.offerIso, mediaObjectId: gid });
  check(S, 'a gallery photo is uploaded to the same Offer through the existing gallery routes', gauth.status === 200 && gput === 200 && gconf.status === 200, `authorize ${gauth.status}, PUT ${gput}, confirm ${gconf.status}`);
  const wrongPrefix = await planConfirm('offer', a, c.offerIso, gid, offerPlan.id);
  check(S, "wrong key prefix: a gallery file cannot be confirmed as the Offer's plan (409 media_mismatch)", wrongPrefix.status === 409 && wrongPrefix.body?.code === 'media_mismatch', coded(wrongPrefix));
  const wrongRemove = await planRemove('offer', a, c.offerIso, offerPlan.id, gid);
  check(S, 'wrong key prefix: nor can it be withdrawn or removed through the plan routes (409 media_mismatch)', wrongRemove.status === 409 && wrongRemove.body?.code === 'media_mismatch', coded(wrongRemove));
  const wrongAuth = await planAuthorize('offer', a, c.offerIso, { id: gid, expected: offerPlan.id, contentType: 'image/jpeg', length: fx.jpeg.length });
  check(S, 'wrong key prefix: its id cannot be reused to authorize a plan (409 idempotency_mismatch)', wrongAuth.status === 409 && wrongAuth.body?.code === 'idempotency_mismatch', coded(wrongAuth));
  const gallery = await galleryList('offer', a, c.offerIso);
  check(S, "the Offer's gallery lists the one photo and not the plan; the plan does not count toward the gallery",
    gallery.status === 200 && gallery.media.length === 1 && gallery.media[0].mediaObjectId === gid, `HTTP ${gallery.status}, ${gallery.media.length} item(s)`);
  const gread = gallery.media[0]?.url ? await getBytes(gallery.media[0].url) : null;
  check(S, 'the gallery photo still reads back byte for byte', gread?.status === 200 && sha256(gread.bytes) === sha256(fx.jpeg), gread ? `HTTP ${gread.status}` : 'no link');
  const gremoved = await callWorker(a, 'POST', '/offer-media/remove', { offerId: c.offerIso, mediaObjectId: gid });
  check(S, 'the gallery photo is removed through the gallery route', gremoved.status === 200 && gremoved.body?.removed === true, coded(gremoved));
  await unchanged('after the gallery file attempts');

  // The database: no client writes a plan pointer or calls a plan function.
  const patch = await rest(a, 'PATCH', `/rest/v1/offers?id=eq.${c.offerIso}`, { plan_media_id: null });
  check(S, 'database: a signed-in client cannot clear an Offer plan pointer (column privilege)', [401, 403].includes(patch.status), `HTTP ${patch.status} ${patch.body?.code ?? ''}`);
  const patchOwner = await rest(a, 'PATCH', `/rest/v1/owners?id=eq.${c.ownerIso}`, { plan_media_id: randomUUID() });
  check(S, 'database: a signed-in client cannot point an Owner at any media (column privilege)', [401, 403].includes(patchOwner.status), `HTTP ${patchOwner.status} ${patchOwner.body?.code ?? ''}`);
  const newId = randomUUID();
  const insert = await rest(a, 'POST', '/rest/v1/offers', { id: newId, owner_id: a.uid, offer_type: 'rent', plan_media_id: offerPlan.id }, 'return=minimal');
  check(S, 'database: a signed-in client cannot create an Offer that already has a plan pointer', [401, 403].includes(insert.status), `HTTP ${insert.status} ${insert.body?.code ?? ''}`);
  check(S, 'database: that refused insert created no row', (await parentRow('offer', a, newId)) === null);
  for (const kind of ['offer', 'owner']) {
    const K = KINDS[kind];
    const confirm = await rest(a, 'POST', `/rest/v1/rpc/${K.confirmRpc}`, {
      p_user_id: a.uid, [K.rpcParent]: randomUUID(), p_media_id: randomUUID(), p_bucket: STAGING_BUCKET, p_expected_media_id: null, p_observed_size: 1, p_observed_content_type: 'image/jpeg',
    });
    check(S, `database: a signed-in client cannot execute ${K.confirmRpc}`, [401, 403, 404].includes(confirm.status), `HTTP ${confirm.status} ${confirm.body?.code ?? ''}`);
    const remove = await rest(a, 'POST', `/rest/v1/rpc/${K.removeRpc}`, { p_user_id: a.uid, [K.rpcParent]: randomUUID(), p_bucket: STAGING_BUCKET, p_expected_media_id: null });
    check(S, `database: a signed-in client cannot execute ${K.removeRpc}`, [401, 403, 404].includes(remove.status), `HTTP ${remove.status} ${remove.body?.code ?? ''}`);
  }
  const rules = await rest(a, 'POST', '/rest/v1/rpc/plan_attachment_rules', { p_content_type: 'application/pdf' });
  check(S, 'database: a signed-in client cannot execute plan_attachment_rules', [401, 403, 404].includes(rules.status), `HTTP ${rules.status} ${rules.body?.code ?? ''}`);
  const pointer = await parentRow('offer', a, c.offerIso);
  check(S, "database: the Offer's pointer is still the plan after every refused write", pointer?.plan_media_id === offerPlan.id);
  c.isolation = { offerPlan, ownerPlan };
}

async function sectionRegression(c) {
  const S = 'regression';
  const { a, b, fx } = c;
  for (const [kind, parent, bytes, type] of [['offer', c.offer2, fx.jpeg, TYPES.jpeg], ['owner', c.owner2, fx.png, TYPES.png]]) {
    const K = KINDS[kind];
    const id = randomUUID();
    const auth = await callWorker(a, 'POST', `${K.gallery}/authorize`, { [K.idField]: parent, mediaObjectId: id, contentType: type.contentType, contentLength: bytes.length, originalFileName: 'gallery' });
    if (auth.status === 200) rememberMedia(kind, a, parent, id, type.contentType, 'gallery');
    const put = auth.status === 200 ? await putBytes(auth.body.presignedUrl, bytes, type.contentType) : null;
    const conf = await callWorker(a, 'POST', `${K.gallery}/confirm`, { [K.idField]: parent, mediaObjectId: id });
    check(S, `${K.name} gallery: authorize → private PUT → confirm still works`, auth.status === 200 && put === 200 && conf.status === 200, `authorize ${auth.status}, PUT ${put}, confirm ${conf.status}`);
    const list = await galleryList(kind, a, parent);
    const item = list.media.find((m) => m.mediaObjectId === id);
    check(S, `${K.name} gallery: the photo is listed once`, list.status === 200 && list.media.length === 1 && Boolean(item), `HTTP ${list.status}, ${list.media.length} item(s)`);
    const read = item?.url ? await getBytes(item.url) : null;
    check(S, `${K.name} gallery: the signed read returns the exact bytes`, read?.status === 200 && sha256(read.bytes) === sha256(bytes), read ? `HTTP ${read.status}` : 'no link');
    const links = await galleryLinks(kind, a, parent);
    check(S, `${K.name} gallery: the photo is linked once`, links?.length === 1, `${links?.length ?? '?'} link(s)`);
    const removed = await callWorker(a, 'POST', `${K.gallery}/remove`, { [K.idField]: parent, mediaObjectId: id });
    check(S, `${K.name} gallery: removal still works`, removed.status === 200 && removed.body?.removed === true, coded(removed));
    const gone = await callWorker(a, 'POST', `${K.gallery}/confirm`, { [K.idField]: parent, mediaObjectId: id });
    check(S, `${K.name} gallery: a removed photo answers 410 media_removed`, gone.status === 410 && gone.body?.code === 'media_removed', coded(gone));
  }
  const quotation = await callWorker(a, 'GET', `/quotation-media?quotationId=${randomUUID()}`);
  check(S, 'Quotation media: the list route is alive and gated (an unknown Quotation answers 404 quotation_not_found)', quotation.status === 404 && quotation.body?.code === 'quotation_not_found', coded(quotation));
  for (const session of [a, b]) {
    const profile = await callWorker(session, 'GET', '/profile-image-url');
    const bucketNote = profile.status === 409 && /profile-image bucket/.test(profile.body?.error ?? '');
    check(S, `Profile media: the image lookup route is alive for account ${session.label} (200, or 409 when its image lives in another bucket)`,
      profile.status === 200 || bucketNote, `HTTP ${profile.status}${bucketNote ? ' (the profile image is in another bucket: expected for a designated account whose image is in the production bucket)' : ''}`);
  }
}

/** Removes everything this run made, then proves no media row it made is left outside a terminal state. */
async function cleanup(c) {
  const S = 'cleanup';
  const sessions = { A: c.a, B: c.b };
  const failures = [];
  const attempt = async (what, fn) => {
    try {
      await fn();
    } catch (error) {
      failures.push(`${what}: ${error?.message ?? error}`);
    }
  };
  for (const [kind, list] of [['offer', created.offers], ['owner', created.owners]]) {
    for (const parent of list) {
      const s = sessions[parent.account];
      if (!s) continue;
      await attempt(`${kind} ${parent.label} plan`, async () => {
        const got = await planGet(kind, s, parent.id);
        if (got.plan?.mediaObjectId) await planRemove(kind, s, parent.id, got.plan.mediaObjectId);
      });
    }
  }
  for (const media of created.media) {
    const s = sessions[media.account];
    if (!s) continue;
    await attempt(`media ${media.id}`, async () => {
      const row = await mediaRow(s, media.id);
      if (!row || row.status === 'deleted') return;
      const K = KINDS[media.kind];
      if (media.route === 'gallery') {
        if (row.status !== 'pending_delete') await callWorker(s, 'POST', `${K.gallery}/remove`, { [K.idField]: media.parentId, mediaObjectId: media.id });
      } else if (['pending_upload', 'failed', 'pending_delete'].includes(row.status)) {
        await planRemove(media.kind, s, media.parentId, null, media.id);
      }
    });
  }
  for (const [kind, list] of [['offer', created.offers], ['owner', created.owners]]) {
    for (const parent of list) {
      const s = sessions[parent.account];
      if (!s) continue;
      await attempt(`${kind} ${parent.label} soft delete`, async () => {
        const r = await rest(s, 'PATCH', `/rest/v1/${KINDS[kind].table}?id=eq.${parent.id}`, { deleted_at: new Date().toISOString() }, 'return=minimal');
        if (![200, 204].includes(r.status)) throw new Error(`HTTP ${r.status}`);
      });
    }
  }
  check(S, 'every test Offer and Owner this run created is soft-deleted (no real record was touched)',
    failures.filter((f) => f.includes('soft delete')).length === 0, failures.filter((f) => f.includes('soft delete')).join('; '));

  const leftovers = [];
  for (const media of created.media) {
    const s = sessions[media.account];
    if (!s) continue;
    const row = await mediaRow(s, media.id);
    if (row === undefined) leftovers.push(`${media.kind} ${media.id}: unreadable`);
    else if (row !== null && !['deleted', 'failed'].includes(row.status)) leftovers.push(`${media.kind} ${media.id}: ${row.status}`);
  }
  check(S, `no media row this run made is left outside a terminal state (${created.media.length} checked): every plan object is removed from the staging bucket`,
    leftovers.length === 0, leftovers.length ? leftovers.slice(0, 6).join('; ') : '');
  const still = [];
  for (const [kind, list] of [['offer', created.offers], ['owner', created.owners]]) {
    for (const parent of list) {
      const s = sessions[parent.account];
      const row = s ? await parentRow(kind, s, parent.id) : undefined;
      if (row && row.plan_media_id) still.push(`${kind} ${parent.id}`);
    }
  }
  check(S, 'no test record still points at a plan', still.length === 0, still.join('; '));
  if (failures.length) note(S, `${failures.length} cleanup step(s) did not finish: ${failures.slice(0, 4).join(' | ')}`);
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
  results.length = 0;
  created.offers.length = 0;
  created.owners.length = 0;
  created.media.length = 0;
  const fx = loadFixtures();
  console.log(`Plan attachment staging acceptance ${RUN_ID} against ${new URL(cfg.workerUrl).host}\n`);
  const c = { fx };
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
    if (cfg.b.expectedUid && !check('setup', 'account B matches the expected test account id', b.uid === cfg.b.expectedUid)) {
      throw new FatalError('the signed-in account B is not the expected test account');
    }
    accounts = { a: a.uid, b: b.uid };
    c.a = a;
    c.b = b;
    // Both accounts are now proven to be the intended test accounts, so claiming (which ends
    // any other session of an account) cannot reach an unintended one.
    note('setup', 'claiming the active app session for A and B ends any other session of those two test accounts');
    await claimSession(a);
    await claimSession(b);
    await section('session-gate', () => sectionSessionGate(c));

    c.offer1 = await createParent('offer', a, 'A-offer-lifecycle');
    c.offer2 = await createParent('offer', a, 'A-offer-second');
    c.offerIso = await createParent('offer', a, 'A-offer-isolation');
    c.owner1 = await createParent('owner', a, 'A-owner-lifecycle');
    c.owner2 = await createParent('owner', a, 'A-owner-second');
    c.ownerIso = await createParent('owner', a, 'A-owner-isolation');
    c.offerB = await createParent('offer', c.b, 'B-offer');
    c.ownerB = await createParent('owner', c.b, 'B-owner');

    await section('offer-plan', () => sectionOfferPlan(c));
    await section('owner-plan', () => sectionOwnerPlan(c));
    await section('refuse', () => sectionRefusals(c));
    await section('isolation', () => sectionIsolation(c));
    await section('regression', () => sectionRegression(c));
  } catch (error) {
    check('run', 'run completed', false, error instanceof StepError ? error.message : `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
  }
  if (c.a && c.b) {
    try {
      await cleanup(c);
    } catch (error) {
      check('cleanup', 'cleanup completed', false, `${error?.name ?? 'Error'}: ${error?.message ?? ''}`);
    }
  }
  return writeReport({ accounts }) === 0 ? 0 : 1;
}

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing ${name}. Run this through run_plan_attachment_staging_acceptance.ps1.`);
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
  if (process.env.BW_E2E_ACK_SESSION_CLAIM !== '1') {
    console.error('This run claims the active app session of accounts A and B and ends any other session of them. Run it through run_plan_attachment_staging_acceptance.ps1, which asks you to acknowledge that.');
    process.exit(2);
  }
  return {
    workerUrl,
    stagingKey: required('BW_E2E_STAGING_KEY'),
    a,
    b,
    reportPath: process.env.BW_E2E_REPORT_PATH || join(REPORTS, `plan_attachment_${RUN_ID}.json`),
  };
}

function offlineCheck() {
  const fx = loadFixtures();
  const ok = fx.jpeg[0] === 0xff && fx.jpeg[1] === 0xd8 && fx.png[0] === 0x89 && fx.webp.toString('latin1', 8, 12) === 'WEBP' &&
    fx.pdf.toString('latin1', 0, 8) === '%PDF-1.4' && sha256(makePdf('a')) !== sha256(makePdf('a')) &&
    fx.docx.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04])) && fx.xlsx.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04])) &&
    fx.pptx.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04])) && fx.doc.subarray(0, 8).equals(Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) &&
    fx.xls.length > 4096 && fx.ppt.length > 4096 &&
    expectedKey('offer', 'u', 'p', 'm', 'jpg') === 'profiles/u/offer-plans/p/m.jpg' &&
    expectedKey('owner', 'u', 'p', 'm', 'docx') === 'profiles/u/owner-plans/p/m.docx' &&
    sanitize('see https://x.test/a?X-Amz-Signature=abc now') === 'see <url> now' &&
    sanitize('token eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl end') === 'token <jwt> end' &&
    STAGING_URL_PATTERN.test('https://r2-profile-upload-staging.example.workers.dev') &&
    !STAGING_URL_PATTERN.test('https://media-api.brokerwallet.ae') && planRoutes().length === 8;
  console.log(ok ? 'OFFLINE CHECK PASSED' : 'OFFLINE CHECK FAILED');
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.BW_E2E_OFFLINE_CHECK === '1') offlineCheck();
  run(loadConfig()).then((code) => process.exit(code));
}
