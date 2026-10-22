// Broker Wallet — Toolkit Cloud Documents: real-R2 STAGING acceptance runner (C3B.5A).
//
// Run it only through run_toolkit_staging_acceptance.ps1, in the owner's own terminal, against the STAGING
// Worker (`r2-profile-upload-staging`, private bucket `broker-wallet-media-staging`) and the shared hosted
// Supabase project. Nothing in this file has been run against a hosted system by the agent that wrote it:
// toolkit_offline_selftest.mjs runs it against the real Worker code with in-memory doubles.
//
// Phases (BW_E2E_PHASES, letters, run in this order A B C(isolation) D C(sessions) E):
//   A  basic real-R2 smoke: PDF first (STOP on failure), then Scanner JPEG and PNG: authorize, PUT with every
//      signed header, confirm, list, signed GET, byte length + SHA-256 of the download, original format kept,
//      and what `sha256Verified` really means (a wrong digest claim is used to tell Worker verification from a claim)
//   B  write-once: replay of the same signed PUT with different bytes (and without the signed header) must be
//      refused by R2; the object and the document stay intact. An overwrite is a SECURITY BLOCKER.
//   C  isolation: account B cannot list / download / rename / remove / re-authorize account A's document;
//      direct PostgREST stays RLS-constrained; then (at the end of the run) a superseded session is refused
//   D  lifecycle: rename + stale version, idempotent confirm, remove + tombstone, repeated remove, incomplete and
//      wrong-size uploads, retry after a lost PUT answer
//   E  cleanup safety: the sweep stays OFF and is never triggered; reports which invariants this run cannot prove
//
// Scope of writes: ONLY new synthetic documents titled "staging-e2e-toolkit-<run>", owned by the two supplied
// disposable test accounts, in the staging bucket. The runner asks the Worker to hide/remove them,
// but final R2 deletion and tombstones may require a later attempt after the signed-URL window. It never touches an existing document, a real account or an unknown object, never sends
// a secret key (only the publishable key), never targets Production.
//
// Output and the JSON report hold PASS/FAIL per check, HTTP statuses and fixed codes. Never a token, key,
// password, e-mail, account id, document id, object key, presigned URL or signed GET URL.
//
// Single Active Device: each account signs in, is checked to belong to this Supabase project, and CLAIMS its
// session (app_session_claim.mjs), which ends the account's other sessions. A second explicit confirmation is
// required in this process before the first document is created or the first byte is PUT.
//
// Node built-ins only: no `npm install` is needed.

import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  AppSessionClaimError, accessTokenClaims, claimAppSession, claimSessionForRun,
} from './app_session_claim.mjs';

export const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
export const PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
export const STAGING_BUCKET = 'broker-wallet-media-staging';
export const STAGING_HEADER = 'X-Broker-Wallet-Staging-Key';
export const STAGING_URL_PATTERN = /^https:\/\/r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$/;
export const WRITE_CONFIRMATION = 'CREATE TEST DOCUMENTS';
const R2_HOST_SUFFIX = '.r2.cloudflarestorage.com';
const SUPERSEDED = 'session_superseded';
const TITLE_PREFIX = 'staging-e2e-toolkit';
const PHASE_LETTERS = new Set(['A', 'B', 'C', 'D', 'E']);

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');
const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

class StepError extends Error {}
/** Stops the run: continuing would only create documents that cannot finish. */
export class FatalError extends StepError {}
/** An overwrite of a confirmed object: the one result that must never be ignored. */
export class SecurityBlocker extends FatalError {}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

/** Removes anything URL-, token-, e-mail-, id- or key-shaped, so nothing sensitive is ever printed. */
export function sanitize(value) {
  return String(value ?? '')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<jwt>')
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '<email>')
    .replace(/profiles\/\S+/g, '<key>')
    .replace(UUID_RE, '<id>')
    .slice(0, 300);
}

// ---------------------------------------------------------------------------
// Fixtures: tiny, valid containers, unique per run
// ---------------------------------------------------------------------------

export function makePdf(label, runId) {
  // Produce a genuine single-page PDF, including cross-reference offsets and startxref.
  // A magic header plus %%EOF is insufficient: normal PDF readers require a valid xref.
  const parts = [`%PDF-1.4\n% ${TITLE_PREFIX} ${label} ${runId} ${randomUUID()}\n`];
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>',
  ];
  const offsets = [0];
  for (const [index, body] of objects.entries()) {
    offsets.push(Buffer.byteLength(parts.join(''), 'latin1'));
    parts.push(`${index + 1} 0 obj\n${body}\nendobj\n`);
  }
  const xrefStart = Buffer.byteLength(parts.join(''), 'latin1');
  parts.push(`xref\n0 ${offsets.length}\n0000000000 65535 f \n`);
  for (const offset of offsets.slice(1)) parts.push(`${String(offset).padStart(10, '0')} 00000 n \n`);
  parts.push(`trailer\n<< /Root 1 0 R /Size ${offsets.length} >>\nstartxref\n${xrefStart}\n%%EOF\n`);
  return Buffer.from(parts.join(''), 'latin1');
}

/** A tiny JPEG: the fixture file, with a unique comment segment so each run's bytes differ. */
export function makeJpeg(base, tag) {
  const comment = Buffer.from(`${TITLE_PREFIX} ${tag}`, 'latin1');
  const segment = Buffer.concat([Buffer.from([0xff, 0xfe, (comment.length + 2) >> 8, (comment.length + 2) & 0xff]), comment]);
  return Buffer.concat([base.subarray(0, 2), segment, base.subarray(2)]);
}

/** PNG CRC-32 (ISO 3309), computed over chunk type and chunk data. */
function pngCrc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** A valid PNG: add a unique tEXt chunk with its mandatory CRC before IEND. */
export function makePng(base, tag) {
  const data = Buffer.from(`Comment\0${TITLE_PREFIX} ${tag}`, 'latin1');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeAndData = Buffer.concat([Buffer.from('tEXt', 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(pngCrc32(typeAndData));
  const chunk = Buffer.concat([length, typeAndData, crc]);
  const iend = base.length - 12;
  return Buffer.concat([base.subarray(0, iend), chunk, base.subarray(iend)]);
}

function loadFixtures(runId) {
  const image = (name) => readFileSync(join(HERE, 'fixtures', name));
  const jpegBase = image('photo.jpg');
  const pngBase = image('photo.png');
  return {
    pdf: (label) => makePdf(label, runId),
    jpeg: (tag) => makeJpeg(jpegBase, `${tag} ${runId}`),
    png: (tag) => makePng(pngBase, `${tag} ${runId}`),
  };
}

// ---------------------------------------------------------------------------
// Run context
// ---------------------------------------------------------------------------

let ctx;

function check(section, name, ok, detail = '') {
  ctx.results.push({ section, name, ok: Boolean(ok), detail: sanitize(detail) });
  ctx.log(`${ok ? 'PASS' : 'FAIL'}  [${section}] ${name}${detail ? `  (${sanitize(detail)})` : ''}`);
  return Boolean(ok);
}

function note(section, text) {
  ctx.results.push({ section, name: sanitize(text), ok: null, detail: '' });
  ctx.log(`INFO  [${section}] ${sanitize(text)}`);
}

/** Records a failed check and stops the run when [fatal]. */
function must(section, name, ok, detail = '', fatal = true) {
  check(section, name, ok, detail);
  if (!ok && fatal) throw new FatalError(`${section}: ${name}`);
  return ok;
}

const coded = (r) => `HTTP ${r.status}${r.body?.code ? ` ${r.body.code}` : r.code ? ` ${r.code}` : ''}`;
const isOk = (status) => status >= 200 && status < 300;

async function timedFetch(url, init = {}, timeoutMs = 60_000) {
  return ctx.fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
}

async function safeJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Auth, claims and the Worker
// ---------------------------------------------------------------------------

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
  const claims = accessTokenClaims(body.access_token);
  // The token must be this project's: refuse anything minted by another Supabase project.
  if (claims?.iss !== `${SUPABASE_URL}/auth/v1`) throw new FatalError(`sign-in ${label}: the token is not from the expected Supabase project`);
  return { label, token: body.access_token, uid: body.user.id };
}

const claimSession = (session) => claimSessionForRun({
  session, supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, check, FatalError, section: 'setup', fetchImpl: ctx.fetch,
});

async function callWorker(session, method, path, body, { key, timeout = 60_000 } = {}) {
  const headers = {};
  const gateKey = key === undefined ? ctx.config.stagingKey : key;
  if (gateKey !== null) headers[STAGING_HEADER] = gateKey;
  if (session) headers.Authorization = `Bearer ${session.token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await timedFetch(`${ctx.config.workerUrl}${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }, timeout);
  return { status: res.status, body: await safeJson(res), headers: res.headers };
}

async function rest(session, method, path, body) {
  const headers = { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${session.token}` };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await timedFetch(`${SUPABASE_URL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: res.status, body: await safeJson(res) };
}

// ---------------------------------------------------------------------------
// R2 (signed URLs only; every URL is checked before a byte is sent)
// ---------------------------------------------------------------------------

/** Refuses a signed URL that is not the private STAGING bucket's, so nothing can reach Production R2. */
export function assertStagingR2Url(rawUrl, session) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch (_) {
    throw new FatalError('the Worker returned an invalid signed URL');
  }
  if (url.protocol !== 'https:' || !url.hostname.endsWith(R2_HOST_SUFFIX)) throw new FatalError('the signed URL is not an R2 URL');
  if (!url.pathname.startsWith(`/${STAGING_BUCKET}/`)) throw new FatalError('the signed URL is not for the staging bucket');
  const key = decodeURIComponent(url.pathname.slice(STAGING_BUCKET.length + 2));
  if (!key.startsWith(`profiles/${session.uid}/toolkit-documents/`)) throw new FatalError('the signed URL is not for this account\'s Toolkit documents');
  return url;
}

function r2Code(text) {
  const match = /<Code>([A-Za-z]{1,40})<\/Code>/.exec(text ?? '');
  return match ? match[1] : '';
}

async function r2Put(session, signedUrl, headers, bytes, contentType) {
  assertStagingR2Url(signedUrl, session);
  const res = await timedFetch(signedUrl, { method: 'PUT', headers: { ...headers, 'Content-Type': contentType }, body: bytes }, 600_000);
  const text = await res.text().catch(() => '');
  return { status: res.status, code: r2Code(text) };
}

async function r2Get(session, signedUrl) {
  assertStagingR2Url(signedUrl, session);
  const res = await timedFetch(signedUrl, {}, 600_000);
  return { status: res.status, bytes: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type') };
}

// ---------------------------------------------------------------------------
// Document operations
// ---------------------------------------------------------------------------

function newDoc(label, owner, session, spec, bytes, { claimedSha } = {}) {
  const doc = {
    label, owner, id: randomUUID(), spec, bytes, sha: sha256(bytes), claimedSha: claimedSha ?? sha256(bytes),
    title: `${TITLE_PREFIX}-${ctx.runId}-${label}`, removed: false, session,
  };
  ctx.created.push(doc);
  return doc;
}

const authorizeBody = (doc, over = {}) => ({
  documentId: doc.id, documentType: doc.spec.tool, title: doc.title, contentType: doc.spec.contentType,
  contentLength: doc.bytes.length, contentSha256: doc.claimedSha, pageCount: doc.spec.contentType === 'application/pdf' ? 1 : 1,
  sourceCreatedAt: new Date().toISOString(), ...over,
});

const authorize = (s, doc, over) => callWorker(s, 'POST', '/toolkit-documents/authorize', authorizeBody(doc, over));
const confirm = (s, doc) => callWorker(s, 'POST', '/toolkit-documents/confirm', { documentId: doc.id }, { timeout: 120_000 });
const listDocs = (s) => callWorker(s, 'GET', '/toolkit-documents?limit=100');
const downloadTicket = (s, doc) => callWorker(s, 'GET', `/toolkit-documents/download?documentId=${doc.id}`);
const rename = (s, doc, title, expectedVersion) => callWorker(s, 'POST', '/toolkit-documents/rename', { documentId: doc.id, title, expectedVersion });
const remove = (s, doc) => callWorker(s, 'POST', '/toolkit-documents/remove', { documentId: doc.id });
const statusOf = (s, doc) => callWorker(s, 'POST', '/toolkit-documents/status', { documentIds: [doc.id] });

const FORMATS = {
  pdf: { tool: 'scanner', contentType: 'application/pdf', label: 'PDF' },
  jpeg: { tool: 'scanner', contentType: 'image/jpeg', label: 'Scanner JPEG' },
  png: { tool: 'scanner', contentType: 'image/png', label: 'Scanner PNG' },
};

function makeBytes(format, tag) {
  return format === 'pdf' ? ctx.fixtures.pdf(tag) : ctx.fixtures[format](tag);
}

/** authorize -> PUT (with the signed headers) -> optionally confirm. Returns what each step answered. */
async function upload(section, session, doc, { confirmIt = true, fatal = true } = {}) {
  const a = await authorize(session, doc);
  must(section, `${doc.label}: authorize answers a pending upload`, a.status === 200 && a.body?.status === 'pending' && typeof a.body?.presignedUrl === 'string', coded(a), fatal);
  doc.url = a.body.presignedUrl;
  doc.uploadHeaders = a.body.uploadHeaders ?? {};
  must(section, `${doc.label}: authorize returns the write-once header the PUT must carry`, doc.uploadHeaders['If-None-Match'] === '*', '', fatal);
  const put = await r2Put(session, doc.url, doc.uploadHeaders, doc.bytes, doc.spec.contentType);
  must(section, `${doc.label}: the signed PUT (with every signed header) is accepted by R2`, isOk(put.status), `HTTP ${put.status}${put.code ? ` ${put.code}` : ''}`, fatal);
  if (!confirmIt) return { a, put };
  const c = await confirm(session, doc);
  must(section, `${doc.label}: confirm makes the document ready`, c.status === 200 && Number.isInteger(c.body?.version), coded(c), fatal);
  doc.version = c.body.version;
  doc.sha256Verified = c.body.sha256Verified;
  return { a, put, c };
}

async function verifyRoundTrip(section, session, doc) {
  const list = await listDocs(session);
  const entry = (list.body?.documents ?? []).find((d) => d.documentId === doc.id);
  must(section, `${doc.label}: list shows the document with its tool, format, size and digest`,
    list.status === 200 && entry && entry.documentType === doc.spec.tool && entry.contentType === doc.spec.contentType
      && entry.sizeBytes === doc.bytes.length && entry.contentSha256 === doc.claimedSha && entry.title === doc.title, coded(list));
  const ticket = await downloadTicket(session, doc);
  must(section, `${doc.label}: download returns a signed read with the recorded size, digest and format`,
    ticket.status === 200 && typeof ticket.body?.url === 'string' && ticket.body.sizeBytes === doc.bytes.length
      && ticket.body.contentSha256 === doc.claimedSha && ticket.body.contentType === doc.spec.contentType, coded(ticket));
  const got = await r2Get(session, ticket.body.url);
  must(section, `${doc.label}: the signed GET succeeds`, got.status === 200, `HTTP ${got.status}`);
  must(section, `${doc.label}: downloaded byte length equals the original (${doc.bytes.length})`, got.bytes.length === doc.bytes.length, `${got.bytes.length}`);
  must(section, `${doc.label}: downloaded SHA-256 equals the original`, sha256(got.bytes) === doc.sha);
  must(section, `${doc.label}: the file kept its original format (no conversion)`, Buffer.compare(got.bytes, doc.bytes) === 0
    && (doc.spec.contentType !== 'image/jpeg' || got.bytes[0] === 0xff)
    && (doc.spec.contentType !== 'image/png' || got.bytes[0] === 0x89), got.contentType ?? '');
  return { entry, ticket };
}

/** Re-reads the object through a fresh signed GET and returns its SHA-256 (independent of any earlier answer). */
async function downloadedSha(session, doc) {
  const ticket = await downloadTicket(session, doc);
  if (ticket.status !== 200) return { status: ticket.status, sha: null, code: ticket.body?.code };
  const got = await r2Get(session, ticket.body.url);
  return { status: got.status, sha: got.status === 200 ? sha256(got.bytes) : null };
}

// ---------------------------------------------------------------------------
// Phase A
// ---------------------------------------------------------------------------

async function phaseA() {
  const s = ctx.A;
  note('A', 'Starting with ONE PDF; any failure stops the phase before JPEG and PNG.');
  const pdf = newDoc('a-pdf', 'A', s, FORMATS.pdf, makeBytes('pdf', 'a-pdf'));
  await upload('A', s, pdf);
  await verifyRoundTrip('A', s, pdf);
  ctx.docs.aPdf = pdf;
  for (const format of ['jpeg', 'png']) {
    const doc = newDoc(`a-${format}`, 'A', s, FORMATS[format], makeBytes(format, `a-${format}`));
    await upload('A', s, doc);
    await verifyRoundTrip('A', s, doc);
    ctx.docs[`a${format}`] = doc;
  }
  // What `sha256Verified` really means: a document whose digest CLAIM is wrong is accepted only if the Worker
  // does not hash the stored object; if the Worker verifies, it refuses it. Either way the flag must match.
  const wrong = newDoc('a-wrong-claim', 'A', s, FORMATS.pdf, makeBytes('pdf', 'a-wrong-claim'), { claimedSha: sha256(Buffer.from(`not these bytes ${ctx.runId}`)) });
  await upload('A', s, wrong, { confirmIt: false });
  const claimed = await confirm(s, wrong);
  const verificationOn = claimed.status === 422 && claimed.body?.code === 'integrity_mismatch';
  const verificationOff = claimed.status === 200 && claimed.body?.sha256Verified === false;
  must('A', 'a wrong digest claim is either refused (Worker verification ON) or accepted unverified (OFF); never accepted as "verified"', verificationOn || verificationOff, coded(claimed));
  if (verificationOff) {
    note('A', 'Worker digest verification is OFF on staging (TOOLKIT_DOC_VERIFY_SHA256 unset): sha256Verified is false for every document and the stored digest is only the device\'s claim.');
    must('A', 'sha256Verified is false for the correctly-hashed documents too (it reflects Worker verification, not the client claim)',
      ctx.docs.aPdf.sha256Verified === false && ctx.docs.ajpeg.sha256Verified === false && ctx.docs.apng.sha256Verified === false);
  } else {
    note('A', 'Worker digest verification is ON on staging: the wrong claim was refused (the Worker removed the object).');
    must('A', 'sha256Verified is true for the correctly-hashed documents', ctx.docs.aPdf.sha256Verified === true && ctx.docs.ajpeg.sha256Verified === true && ctx.docs.apng.sha256Verified === true);
  }
}

// ---------------------------------------------------------------------------
// Phase B
// ---------------------------------------------------------------------------

async function phaseB() {
  const s = ctx.A;
  const doc = newDoc('b-writeonce', 'A', s, FORMATS.pdf, makeBytes('pdf', 'b-writeonce'));
  const { a } = await upload('B', s, doc, { confirmIt: false });
  const signed = new URL(a.body.presignedUrl).searchParams.get('X-Amz-SignedHeaders') ?? '';
  must('B', 'the signed PUT URL lists if-none-match among its signed headers', signed.split(';').includes('if-none-match'), signed);
  const other = makeBytes('pdf', 'b-writeonce-OVERWRITE-attempt');
  let overwritten = false;

  const noHeader = await r2Put(s, doc.url, {}, other, doc.spec.contentType);
  check('B', 'a PUT that omits the signed If-None-Match header is refused by R2', !isOk(noHeader.status), `HTTP ${noHeader.status}${noHeader.code ? ` ${noHeader.code}` : ''}`);
  if (isOk(noHeader.status)) overwritten = true;

  const before = await r2Put(s, doc.url, doc.uploadHeaders, other, doc.spec.contentType);
  if (isOk(before.status)) overwritten = true;
  // The first PUT already stored the original bytes, so a second PUT with the header must be refused.
  check('B', 'replay of the same signed PUT URL (same headers, different bytes) is refused by R2', !isOk(before.status), `HTTP ${before.status}${before.code ? ` ${before.code}` : ''}`);
  note('B', `R2's actual answer to the replay: HTTP ${before.status}${before.code ? ` ${before.code}` : ''}`);
  if (overwritten) {
    const confirmed = await confirm(s, doc);
    const sha = await downloadedSha(s, doc);
    check('B', 'SECURITY BLOCKER: the stored object still has the original SHA-256', sha.sha === doc.sha, `confirm ${coded(confirmed)}`);
    throw new SecurityBlocker('B: R2 accepted a replayed signed PUT: write-once is NOT enforced');
  }
  const c = await confirm(s, doc);
  must('B', 'confirm after the refused replays makes the document ready', c.status === 200, coded(c));
  const first = await downloadedSha(s, doc);
  must('B', 'independent download: the object has the ORIGINAL SHA-256', first.sha === doc.sha, `HTTP ${first.status}`);

  const afterConfirm = await r2Put(s, doc.url, doc.uploadHeaders, makeBytes('pdf', 'b-after-confirm'), doc.spec.contentType);
  if (isOk(afterConfirm.status)) {
    const sha = await downloadedSha(s, doc);
    check('B', 'SECURITY BLOCKER: replay AFTER the confirm was accepted by R2', false, `HTTP ${afterConfirm.status}; object ${sha.sha === doc.sha ? 'unchanged' : 'CHANGED'}`);
    throw new SecurityBlocker('B: a confirmed object can be replaced by replaying its signed PUT');
  }
  check('B', 'replay AFTER the confirm is refused by R2', true, `HTTP ${afterConfirm.status}${afterConfirm.code ? ` ${afterConfirm.code}` : ''}`);
  const second = await downloadedSha(s, doc);
  must('B', 'the confirmed document is still usable and its SHA-256 is unchanged', second.sha === doc.sha, `HTTP ${second.status}`);
  const again = await authorize(s, doc);
  must('B', 'authorize for the ready document answers "already in the cloud" with no new URL', again.status === 200 && again.body?.alreadyConfirmed === true && again.body?.presignedUrl === undefined, coded(again));
  ctx.docs.bDoc = doc;
}

// ---------------------------------------------------------------------------
// Phase C: isolation (before the lifecycle) and sessions (after it)
// ---------------------------------------------------------------------------

async function ensureConfirmedDoc(label, owner, session, format = 'pdf') {
  const existing = ctx.docs[`ready-${label}`];
  if (existing && !existing.removed) return existing;
  const doc = newDoc(label, owner, session, FORMATS[format], makeBytes(format, label));
  await upload('C', session, doc);
  ctx.docs[`ready-${label}`] = doc;
  return doc;
}

async function phaseCIsolation() {
  const a = ctx.A;
  const b = ctx.B;
  const aDoc = await ensureConfirmedDoc('c-owned-by-a', 'A', a);
  const bDoc = await ensureConfirmedDoc('c-owned-by-b', 'B', b);
  const listB = await listDocs(b);
  must('C', 'B lists its own document and not A\'s', listB.status === 200 && (listB.body.documents ?? []).some((d) => d.documentId === bDoc.id) && !(listB.body.documents ?? []).some((d) => d.documentId === aDoc.id), coded(listB));
  const listA = await listDocs(a);
  must('C', 'A does not see B\'s document', listA.status === 200 && !(listA.body.documents ?? []).some((d) => d.documentId === bDoc.id), coded(listA));
  const dl = await downloadTicket(b, aDoc);
  must('C', 'B cannot download A\'s document (404 document_not_found)', dl.status === 404 && dl.body?.code === 'document_not_found', coded(dl));
  const rn = await rename(b, aDoc, 'hijacked', 1);
  must('C', 'B cannot rename A\'s document (404)', rn.status === 404, coded(rn));
  const rm = await remove(b, aDoc);
  must('C', 'B\'s remove of A\'s document is a silent no-op', rm.status === 200 && rm.body?.alreadyRemoved === true, coded(rm));
  const st = await statusOf(b, aDoc);
  must('C', 'B\'s status query does not reveal A\'s document', st.status === 200 && (st.body?.documents ?? []).length === 0 && (st.body?.unknownIds ?? []).length === 1, coded(st));
  const take = await authorize(b, aDoc);
  must('C', 'B cannot take A\'s document id (409 document_id_unavailable)', take.status === 409 && take.body?.code === 'document_id_unavailable' && take.body?.presignedUrl === undefined, coded(take));
  const intact = await downloadedSha(a, aDoc);
  must('C', 'no cross-account mutation: A\'s document is intact (original SHA-256)', intact.sha === aDoc.sha, `HTTP ${intact.status}`);
  const intactB = await downloadedSha(b, bDoc);
  must('C', 'B\'s document is intact too', intactB.sha === bDoc.sha, `HTTP ${intactB.status}`);

  // Direct PostgREST: RLS-constrained, no key or bucket, no writes, no functions. Only random ids are ever sent.
  const ghost = randomUUID();
  const ownRows = await rest(a, 'GET', `/rest/v1/toolkit_documents?select=id,title,status&id=eq.${aDoc.id}`);
  must('C', 'A reads its own ready document through PostgREST (allowed columns)', ownRows.status === 200 && Array.isArray(ownRows.body) && ownRows.body.length === 1, `HTTP ${ownRows.status}`);
  const otherRows = await rest(a, 'GET', `/rest/v1/toolkit_documents?select=id&id=eq.${bDoc.id}`);
  must('C', 'A cannot read B\'s document through PostgREST (RLS)', otherRows.status === 200 && Array.isArray(otherRows.body) && otherRows.body.length === 0, `HTTP ${otherRows.status}`);
  const bRows = await rest(b, 'GET', `/rest/v1/toolkit_documents?select=id&id=eq.${aDoc.id}`);
  must('C', 'B cannot read A\'s document through PostgREST (RLS)', bRows.status === 200 && Array.isArray(bRows.body) && bRows.body.length === 0, `HTTP ${bRows.status}`);
  for (const column of ['object_key', 'bucket', 'observed_etag', 'discard_claimed_at']) {
    const r = await rest(a, 'GET', `/rest/v1/toolkit_documents?select=${column}&id=eq.${aDoc.id}`);
    must('C', `the ${column} column is not readable by a signed-in client`, r.status >= 400 && r.status < 500, `HTTP ${r.status}`);
  }
  const ins = await rest(a, 'POST', '/rest/v1/toolkit_documents', { id: ghost, owner_id: a.uid, document_type: 'scanner', content_type: 'application/pdf', title: 'x', size_bytes: 1, content_sha256: '0'.repeat(64), bucket: 'x', object_key: 'x' });
  must('C', 'a client cannot INSERT a document row (and the row would be invalid anyway)', ins.status >= 400 && ins.status < 500, `HTTP ${ins.status}`);
  const upd = await rest(a, 'PATCH', `/rest/v1/toolkit_documents?id=eq.${ghost}`, { title: 'x' });
  must('C', 'a client cannot UPDATE a document row (random id)', upd.status >= 400 && upd.status < 500, `HTTP ${upd.status}`);
  const del = await rest(a, 'DELETE', `/rest/v1/toolkit_documents?id=eq.${ghost}`);
  must('C', 'a client cannot DELETE a document row (random id)', del.status >= 400 && del.status < 500, `HTTP ${del.status}`);
  for (const fn of ['claim_abandoned_toolkit_document', 'list_toolkit_documents', 'authorize_toolkit_document_upload']) {
    const r = await rest(a, 'POST', `/rest/v1/rpc/${fn}`, {});
    must('C', `a client cannot call ${fn}`, r.status >= 400 && r.status < 500, `HTTP ${r.status}`);
  }
}

async function phaseCSessions() {
  const old = ctx.A;
  const aDoc = await ensureConfirmedDoc('c-owned-by-a', 'A', old);
  note('C', 'Session checks run last: they replace account A\'s active session.');
  const fresh = await signIn('A2', ctx.config.a);
  const unclaimed = await callWorker(fresh, 'GET', '/toolkit-documents?limit=5');
  must('C', 'a new sign-in that never claimed is refused by the Worker (403 session_superseded)', unclaimed.status === 403 && unclaimed.body?.code === SUPERSEDED, coded(unclaimed));
  await claimSession(fresh);
  fresh.label = 'A';
  const oldList = await callWorker(old, 'GET', '/toolkit-documents?limit=5');
  must('C', 'A\'s superseded session is refused by the Worker (403 session_superseded)', oldList.status === 403 && oldList.body?.code === SUPERSEDED, coded(oldList));
  const oldDownload = await downloadTicket(old, aDoc);
  must('C', 'the superseded session cannot download either', oldDownload.status === 403 && oldDownload.body?.code === SUPERSEDED, coded(oldDownload));
  const oldRows = await rest(old, 'GET', `/rest/v1/toolkit_documents?select=id&id=eq.${aDoc.id}`);
  must('C', 'the superseded session reads no rows through PostgREST', oldRows.status === 200 && Array.isArray(oldRows.body) && oldRows.body.length === 0, `HTTP ${oldRows.status}`);
  let reclaim = 'reclaimed';
  try {
    await claimAppSession({ supabaseUrl: SUPABASE_URL, publishableKey: PUBLISHABLE_KEY, accessToken: old.token, fetchImpl: ctx.fetch });
  } catch (error) {
    reclaim = error instanceof AppSessionClaimError ? error.code : 'error';
  }
  must('C', 'the superseded session cannot claim again', reclaim === SUPERSEDED, reclaim);
  const current = await callWorker(fresh, 'GET', '/toolkit-documents?limit=100');
  must('C', 'the new session works and sees A\'s document', current.status === 200 && (current.body.documents ?? []).some((d) => d.documentId === aDoc.id), coded(current));
  ctx.A = fresh;
  for (const doc of ctx.created) if (doc.owner === 'A') doc.session = fresh;
}

// ---------------------------------------------------------------------------
// Phase D
// ---------------------------------------------------------------------------

async function phaseD() {
  const s = ctx.A;
  const doc = newDoc('d-lifecycle', 'A', s, FORMATS.pdf, makeBytes('pdf', 'd-lifecycle'));
  await upload('D', s, doc);
  const renamed = await rename(s, doc, `${doc.title}-renamed`, doc.version);
  must('D', 'rename with the expected version succeeds and advances the version', renamed.status === 200 && renamed.body?.version > doc.version, coded(renamed));
  const stale = await rename(s, doc, `${doc.title}-stale`, doc.version);
  check('D', 'a rename with the old version is refused with the current title and version (409 stale_version)', stale.status === 409 && stale.body?.code === 'stale_version' && stale.body?.currentVersion === renamed.body.version, coded(stale));
  const confirmAgain = await confirm(s, doc);
  check('D', 'a repeated confirm is idempotent', confirmAgain.status === 200 && confirmAgain.body?.alreadyConfirmed === true, coded(confirmAgain));
  const reAuthorize = await authorize(s, doc);
  check('D', 'a repeated save of a ready document uploads nothing', reAuthorize.status === 200 && reAuthorize.body?.alreadyConfirmed === true && reAuthorize.body?.presignedUrl === undefined, coded(reAuthorize));
  const list = await listDocs(s);
  check('D', 'list shows the renamed title', (list.body?.documents ?? []).some((d) => d.documentId === doc.id && d.title === `${doc.title}-renamed`), coded(list));

  const removed = await remove(s, doc);
  check('D', 'remove succeeds', removed.status === 200 && removed.body?.removed === true, `${coded(removed)}${removed.body?.cleanupPending ? ' cleanupPending' : ''}`);
  const again = await remove(s, doc);
  check('D', 'a repeated remove is safe (idempotent)', again.status === 200 && again.body?.removed === true, coded(again));
  const gone = await downloadTicket(s, doc);
  check('D', 'a removed document cannot be downloaded (410 document_deleted)', gone.status === 410 && gone.body?.code === 'document_deleted', coded(gone));
  const state = await statusOf(s, doc);
  check('D', 'status reports deleted state (may still be pending tombstone)', state.status === 200 && state.body?.documents?.[0]?.state === 'deleted', coded(state));
  const revive = await authorize(s, doc);
  check('D', 'a deleted document id cannot be re-created (410 document_deleted)', revive.status === 410 && revive.body?.code === 'document_deleted', coded(revive));
  const listAfter = await listDocs(s);
  check('D', 'list no longer shows it', !(listAfter.body?.documents ?? []).some((d) => d.documentId === doc.id), coded(listAfter));
  doc.removed = true;

  // Incomplete upload, then wrong size, then the retry after a lost PUT answer.
  const retry = newDoc('d-retry', 'A', s, FORMATS.pdf, makeBytes('pdf', 'd-retry'));
  const first = await authorize(s, retry);
  must('D', 'retry doc: authorize', first.status === 200, coded(first));
  const early = await confirm(s, retry);
  check('D', 'confirm before any byte arrived is refused (409 upload_incomplete)', early.status === 409 && early.body?.code === 'upload_incomplete', coded(early));
  const shortBytes = retry.bytes.subarray(0, Math.floor(retry.bytes.length / 2));
  const shortPut = await r2Put(s, first.body.presignedUrl, first.body.uploadHeaders ?? {}, shortBytes, retry.spec.contentType);
  must('D', 'a truncated upload reaches R2 (to be rejected by the confirm)', isOk(shortPut.status), `HTTP ${shortPut.status}`);
  const wrongSize = await confirm(s, retry);
  check('D', 'the confirm rejects the wrong-size object (422 upload_rejected)', wrongSize.status === 422 && wrongSize.body?.code === 'upload_rejected', coded(wrongSize));
  const second = await authorize(s, retry);
  must('D', 'the same document can be authorized again after the rejection (retry within limits)', second.status === 200 && second.body?.status === 'pending', coded(second));
  const goodPut = await r2Put(s, second.body.presignedUrl, second.body.uploadHeaders ?? {}, retry.bytes, retry.spec.contentType);
  check('D', 'the retried PUT succeeds because the rejected object was removed', isOk(goodPut.status), `HTTP ${goodPut.status}${goodPut.code ? ` ${goodPut.code}` : ''}`);
  // Lost PUT answer: the device does not know it succeeded and asks again.
  const third = await authorize(s, retry);
  must('D', 'authorize again (lost PUT answer)', third.status === 200 && third.body?.status === 'pending', coded(third));
  const duplicate = await r2Put(s, third.body.presignedUrl, third.body.uploadHeaders ?? {}, retry.bytes, retry.spec.contentType);
  check('D', 'the repeated PUT is refused because the object exists (write-once)', !isOk(duplicate.status), `HTTP ${duplicate.status}${duplicate.code ? ` ${duplicate.code}` : ''}`);
  const done = await confirm(s, retry);
  check('D', 'the confirm accepts that same object', done.status === 200, coded(done));
  const sha = await downloadedSha(s, retry);
  check('D', 'the retried document downloads with the original SHA-256', sha.sha === retry.sha, `HTTP ${sha.status}`);
  ctx.docs.dRetry = retry;
}

// ---------------------------------------------------------------------------
// Phase E (no hosted write; the sweep is never triggered)
// ---------------------------------------------------------------------------

async function phaseE() {
  for (const path of ['/toolkit-documents/sweep', '/toolkit-documents/cleanup']) {
    const r = await callWorker(ctx.A, 'POST', path, {});
    check('E', `no HTTP route can trigger a cleanup (${path} answers 404)`, r.status === 404, `HTTP ${r.status}`);
  }
  note('E', 'The sweep stays OFF (TOOLKIT_DOCUMENT_SWEEP_MODE = off) and this runner never changes it.');
  const survivors = Object.values(ctx.docs).filter((d) => d && d.session && !d.removed && d.sha);
  let intact = 0;
  for (const doc of survivors) {
    const r = await downloadedSha(doc.owner === 'A' ? ctx.A : ctx.B, doc);
    if (r.sha === doc.sha) intact += 1;
  }
  check('E', `every confirmed document of this run is still intact before cleanup (${intact} of ${survivors.length})`, intact === survivors.length);
  note('E', 'NOT VERIFIED_HOSTED by this run (needs a separately authorized window with the sweep in dry_run, then on): the claim-first abandoned-upload cleanup on real objects — claiming only stale pending uploads, never a ready one; the 15-minute lease takeover; a user delete during a claim; cleanup_in_progress (503) answers; stuck-claim recovery.');
  note('E', 'Verifiable without the sweep and checked above: ready documents survive every user operation of this run, and no route can trigger a cleanup.');
}

// ---------------------------------------------------------------------------
// Cleanup, report, orchestration
// ---------------------------------------------------------------------------

async function cleanup() {
  let removed = 0;
  let deferred = 0;
  const failures = [];
  for (const doc of ctx.created) {
    if (doc.removed) continue;
    const session = doc.owner === 'A' ? ctx.A : ctx.B;
    if (!session) continue;
    try {
      const r = await remove(session, doc);
      if (r.status === 200 && r.body?.removed === true) {
        doc.removed = true;
        removed += 1;
        if (r.body.cleanupPending === true) deferred += 1;
      } else {
        failures.push(`${doc.label} ${coded(r)}`);
      }
    } catch (_) {
      failures.push(`${doc.label} unreachable`);
    }
  }
  const pending = ctx.created.filter((d) => !d.removed).length;
  check('cleanup', `all runner-created documents received a removal response (${ctx.created.length - pending} of ${ctx.created.length}; ${removed} this step; ${deferred} pending finalization)`, pending === 0, failures.join('; '));
  for (const [owner, session] of [['A', ctx.A], ['B', ctx.B]]) {
    if (!session) continue;
    const list = await listDocs(session).catch(() => null);
    const mine = new Set(ctx.created.filter((d) => d.owner === owner).map((d) => d.id));
    const left = (list?.body?.documents ?? []).filter((d) => mine.has(d.documentId)).length;
    check('cleanup', `account ${owner}'s list shows none of this run's documents`, list?.status === 200 && left === 0, list ? `${left} left` : 'unreachable');
  }
  note('cleanup', `${deferred} removal calls returned cleanupPending: ready documents are hidden, but a fresh signed PUT may remain live and physical deletion/tombstone finalization is NOT yet proven. Re-check those test-only documents after the signed-URL window in a separately approved follow-up; do not claim no staging leftovers. No unrelated document was intentionally targeted.`);
}

function writeReport(extra = {}) {
  const failed = ctx.results.filter((r) => r.ok === false);
  const report = {
    run: ctx.runId, started: ctx.startedAt, finished: new Date().toISOString(), worker: 'staging', phases: [...ctx.config.phases].join(''),
    passed: ctx.results.filter((r) => r.ok === true).length, failed: failed.length, results: ctx.results, ...extra,
  };
  mkdirSync(dirname(ctx.config.reportPath), { recursive: true });
  writeFileSync(ctx.config.reportPath, `${JSON.stringify(report, null, 2)}\n`);
  ctx.log(`\n${report.passed} passed, ${report.failed} failed. Report: ${ctx.config.reportPath}`);
  return report.failed;
}

/** Runs the selected phases with [config]; resolves to the process exit code. [io] injects fetch, ask and log for tests. */
export async function run(config, io = {}) {
  ctx = {
    config, runId: new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z'), startedAt: new Date().toISOString(),
    results: [], created: [], docs: {}, A: null, B: null,
    fetch: io.fetchImpl ?? fetch, log: io.log ?? console.log, ask: io.ask ?? defaultAsk,
  };
  ctx.fixtures = loadFixtures(ctx.runId);
  let blocker = false;
  try {
    ctx.log(`Toolkit staging acceptance ${ctx.runId} — phases ${[...config.phases].join('')} — STAGING Worker only.`);
    ctx.A = await signIn('A', config.a);
    ctx.B = await signIn('B', config.b);
    must('setup', 'accounts A and B are different accounts', ctx.A.uid !== ctx.B.uid);
    if (config.a.expectedUid) must('setup', 'account A is the expected account', ctx.A.uid === config.a.expectedUid);
    if (config.b.expectedUid) must('setup', 'account B is the expected account', ctx.B.uid === config.b.expectedUid);
    await claimSession(ctx.A);
    await claimSession(ctx.B);
    ctx.log('\nAbout to create SYNTHETIC test documents owned by the two test accounts in the STAGING bucket (and PUT bytes to R2).');
    ctx.log(`They are titled "${TITLE_PREFIX}-${ctx.runId}-…" and removed again at the end. Nothing else is touched.`);
    const answer = await ctx.ask(`Type ${WRITE_CONFIRMATION} to continue: `);
    if (answer !== WRITE_CONFIRMATION) throw new FatalError('the write confirmation was not given; nothing was created');

    const has = (letter) => config.phases.has(letter);
    if (has('A')) await phaseA();
    if (has('B')) await phaseB();
    if (has('C')) await phaseCIsolation();
    if (has('D')) await phaseD();
    if (has('C')) await phaseCSessions();
    if (has('E')) await phaseE();
  } catch (error) {
    if (error instanceof SecurityBlocker) blocker = true;
    check('run', error instanceof StepError ? 'the run stopped' : 'unexpected error', false, error?.message ?? String(error));
    ctx.log(`STOPPED: ${sanitize(error?.message)}`);
  } finally {
    try {
      if (ctx.A || ctx.B) await cleanup();
    } catch (error) {
      check('cleanup', 'cleanup finished', false, error?.message ?? String(error));
    }
  }
  const failed = writeReport({ securityBlocker: blocker });
  return failed === 0 ? 0 : (blocker ? 3 : 1);
}

async function defaultAsk(prompt) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question(prompt)).trim();
  } finally {
    rl.close();
  }
}

export function parsePhases(raw) {
  const letters = String(raw ?? 'A').toUpperCase().replace(/[^A-Z]/g, '');
  const set = new Set(letters);
  if (!set.size || [...set].some((l) => !PHASE_LETTERS.has(l))) throw new Error('BW_E2E_PHASES may only contain the letters A, B, C, D, E');
  return set;
}

export function loadConfig(env = process.env, exit = (code) => process.exit(code), err = console.error) {
  const fail = (message) => { err(message); exit(2); throw new Error(message); };
  const required = (name) => env[name] || fail(`${name} is required. Run through run_toolkit_staging_acceptance.ps1.`);
  const workerUrl = required('BW_E2E_WORKER_URL').replace(/\/+$/, '');
  if (!STAGING_URL_PATTERN.test(workerUrl)) fail('BW_E2E_WORKER_URL must be the staging workers.dev URL (https://r2-profile-upload-staging.<subdomain>.workers.dev). Production is never a target.');
  const a = { email: required('BW_E2E_A_EMAIL').trim(), password: required('BW_E2E_A_PASSWORD'), expectedUid: env.BW_E2E_A_UID || null };
  const b = { email: required('BW_E2E_B_EMAIL').trim(), password: required('BW_E2E_B_PASSWORD'), expectedUid: env.BW_E2E_B_UID || null };
  if (a.email.toLowerCase() === b.email.toLowerCase()) fail('Accounts A and B must be different accounts.');
  if (env.BW_E2E_ACK_SESSION_CLAIM !== '1') fail('This run claims the active app session of accounts A and B and ends any other session of them. Run it through run_toolkit_staging_acceptance.ps1, which asks you to acknowledge that.');
  let phases;
  try {
    phases = parsePhases(env.BW_E2E_PHASES);
  } catch (error) {
    fail(error.message);
  }
  return { workerUrl, stagingKey: required('BW_E2E_STAGING_KEY'), a, b, phases, reportPath: env.BW_E2E_REPORT_PATH || join(REPORTS, `toolkit_staging_${new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z')}.json`) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(loadConfig()).then((code) => process.exit(code));
}
