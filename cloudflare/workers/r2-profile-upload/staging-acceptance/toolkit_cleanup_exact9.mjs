// C3B.7 — Prepared ONLY. No hosted calls in default --check mode.
// Real cleanup (--apply) requires separately authorized execution, trusted manifest,
// two disposable-account logins, Single Active Device claims, and explicit confirmation.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const STAGING_WORKER = 'https://r2-profile-upload-staging.mohammed-developer-code.workers.dev';
export const SUPABASE_URL = 'https://rbvcnvqpdqrhywcgxkne.supabase.co';
export const STAGING_BUCKET = 'broker-wallet-media-staging';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz';
const STAGING_KEY_HEADER = 'X-Broker-Wallet-Staging-Key';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIN_SETTLE_MS = 10 * 60 * 1000;
const HERE = dirname(fileURLToPath(import.meta.url));
// Keep the manifest OUTSIDE Git/worktree on Windows; it contains disposable account/document ids.
const MANIFEST_FILE = join(process.env.LOCALAPPDATA ? join(process.env.LOCALAPPDATA, 'BrokerWallet', 'C3B7') : HERE, 'toolkit_cleanup_exact9_manifest.json');
const EXPECTED = Object.freeze({
  '20261020T124143Z': ['a-pdf', 'a-jpeg', 'a-png', 'a-wrong-claim'],
  '20261020T124907Z': ['b-writeonce'],
  '20261020T150501Z': ['c-owned-by-a', 'c-owned-by-b'],
  '20261020T150959Z': ['d-lifecycle-renamed', 'd-retry'],
});

export class GuardError extends Error { constructor(code) { super(code); this.name = 'GuardError'; } }
function requireValue(condition, code) { if (!condition) throw new GuardError(code); }
const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

export function validateManifest(manifest, now = Date.now()) {
  requireValue(isPlainObject(manifest) && Object.keys(manifest).sort().join(',') === 'bucket,records,schemaVersion', 'schema_invalid');
  requireValue(manifest.schemaVersion === 1 && manifest.bucket === STAGING_BUCKET, 'wrong_project_or_bucket');
  requireValue(Array.isArray(manifest.records) && manifest.records.length === 9, 'must_contain_exactly_nine_rows');
  const expectedTitles = new Set(Object.entries(EXPECTED).flatMap(([run, labels]) =>
    labels.map((label) => `staging-e2e-toolkit-${run}-${label}`)));
  const seenIds = new Set();
  const seenTitles = new Set();
  const rowsByLabel = new Map();

  for (const row of manifest.records) {
    requireValue(isPlainObject(row) &&
      Object.keys(row).sort().join(',') === 'bucket,deletedAt,documentId,lastAuthorizedAt,ownerId,status,title', 'row_shape_invalid');
    requireValue(row.bucket === STAGING_BUCKET && row.status === 'pending_delete', 'wrong_bucket_or_status');
    requireValue(typeof row.documentId === 'string' && UUID.test(row.documentId), 'bad_document_id');
    requireValue(typeof row.ownerId === 'string' && UUID.test(row.ownerId), 'bad_owner_id');
    requireValue(typeof row.title === 'string' && expectedTitles.has(row.title), 'unexpected_title_or_run');
    const id = row.documentId.toLowerCase();
    requireValue(!seenIds.has(id) && !seenTitles.has(row.title), 'duplicate_document_or_title');
    seenIds.add(id); seenTitles.add(row.title);
    rowsByLabel.set(row.title, row);
    for (const field of ['lastAuthorizedAt', 'deletedAt']) {
      requireValue(typeof row[field] === 'string' && /(?:Z|[+-]\d{2}(?::?\d{2})?)$/i.test(row[field]), 'invalid_timestamp');
      const ts = Date.parse(row[field]);
      requireValue(Number.isFinite(ts) && ts > 0 && ts <= now - MIN_SETTLE_MS, 'signed_upload_window_not_settled');
    }
  }
  requireValue(seenTitles.size === expectedTitles.size, 'missing_expected_document');

  const ownerA = rowsByLabel.get('staging-e2e-toolkit-20261020T124143Z-a-pdf').ownerId.toLowerCase();
  const ownerB = rowsByLabel.get('staging-e2e-toolkit-20261020T150501Z-c-owned-by-b').ownerId.toLowerCase();
  requireValue(ownerA !== ownerB, 'expected_two_distinct_accounts');
  for (const [title, row] of rowsByLabel.entries()) {
    const belongsB = title === 'staging-e2e-toolkit-20261020T150501Z-c-owned-by-b';
    requireValue(row.ownerId.toLowerCase() === (belongsB ? ownerB : ownerA), 'unexpected_document_account');
  }
  return {
    count: manifest.records.length,
    forA: manifest.records.filter((r) => r.ownerId.toLowerCase() === ownerA),
    forB: manifest.records.filter((r) => r.ownerId.toLowerCase() === ownerB),
    ownerA,
    ownerB,
  };
}

export function readAndValidateManifest(path = MANIFEST_FILE) {
  let input;
  try { input = JSON.parse(readFileSync(path, 'utf8')); }
  catch (_) { throw new GuardError('manifest_missing_or_invalid_json'); }
  return validateManifest(input);
}

async function timedFetch(url, options = {}) {
  return fetch(url, { ...options, signal: AbortSignal.timeout(30_000), redirect: 'error' });
}
async function readJson(response) { try { return await response.json(); } catch (_) { return null; } }

async function signIn(label, email, password, expectedUserId) {
  requireValue(email && password, 'credentials_missing');
  const response = await timedFetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = await readJson(response);
  requireValue(response.status === 200 && typeof body?.access_token === 'string' &&
    typeof body?.user?.id === 'string', `signin_${label}_failed`);
  requireValue(body.user.id.toLowerCase() === expectedUserId, `account_${label}_not_expected_owner`);
  const { accessTokenClaims } = await import('./app_session_claim.mjs');
  const claims = accessTokenClaims(body.access_token);
  requireValue(claims?.iss === `${SUPABASE_URL}/auth/v1` && claims?.role === 'authenticated' &&
    claims?.sub?.toLowerCase() === expectedUserId, `account_${label}_wrong_token`);
  return { label, uid: expectedUserId, token: body.access_token };
}

async function verifiedWorkerRequest(session, key, path, method = 'POST', data) {
  requireValue(path.startsWith('/toolkit-documents/'), 'bad_worker_route');
  const response = await timedFetch(`${STAGING_WORKER}${path}`, {
    method,
    headers: {
      [STAGING_KEY_HEADER]: key,
      Authorization: `Bearer ${session.token}`,
      ...(data === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  return { code: response.status, body: await readJson(response) };
}

async function claim(session) {
  const { claimAndVerifyAppSession } = await import('./app_session_claim.mjs');
  await claimAndVerifyAppSession({
    supabaseUrl: SUPABASE_URL, publishableKey: SUPABASE_PUBLISHABLE_KEY, accessToken: session.token,
  });
}

export async function applyExactNine(validated, config) {
  // Fail closed BEFORE sign-in/session claim, and keep all external side effects in --apply only.
  requireValue(config?.approved === '1' && config?.confirmation === 'DELETE EXACT NINE TEST DOCUMENTS', 'approval_missing');
  requireValue(typeof config.stagingKey === 'string' && config.stagingKey.length >= 16, 'staging_key_missing');
  requireValue(validated.count === 9 && validated.forA.length === 8 && validated.forB.length === 1, 'scope_drift');
  const gate = await timedFetch(`${STAGING_WORKER}/toolkit-documents`, { method: 'GET', headers: { [STAGING_KEY_HEADER]: config.stagingKey } });
  // Correct staging key with no bearer JWT responds 401. Any other code stops, BEFORE auth session claims.
  requireValue(gate.status === 401, 'staging_gate_not_verified');
  const A = await signIn('A', config.aEmail, config.aPassword, validated.ownerA);
  const B = await signIn('B', config.bEmail, config.bPassword, validated.ownerB);
  await claim(A); await claim(B);

  let completed = 0;
  // Only the immutable allowlisted IDs loaded from the validated manifest are ever used.
  for (const [session, records] of [[A, validated.forA], [B, validated.forB]]) {
    for (const row of records) {
      const response = await verifiedWorkerRequest(session, config.stagingKey,
        '/toolkit-documents/remove', 'POST', { documentId: row.documentId });
      // No cleanupPending => Worker reports the R2 delete + DB finalize successfully.
      // AlreadyRemoved is deliberately NOT accepted as proof: unknown/cross-account ids get that too.
      requireValue(response.code === 200 && response.body?.documentId === row.documentId &&
        response.body?.removed === true && response.body?.alreadyRemoved !== true &&
        response.body?.cleanupPending !== true, `remove_incomplete_after_${completed}_documents`);
      completed += 1;
      console.log(`PASS [cleanup] ${completed}/9 finalized by Worker`);
    }
  }
  return completed;
}

export async function cli(argv = process.argv.slice(2)) {
  const mode = argv.length === 0 ? '--check' : argv[0];
  requireValue(argv.length <= 1 && ['--check', '--apply'].includes(mode), 'usage_check_or_apply');
  const validated = readAndValidateManifest();
  if (mode === '--check') {
    console.log('PASS: immutable nine-document scope validated locally; 8 for account A, 1 for account B.');
    console.log('NO NETWORK. NO SIGN-IN. NO SESSION CLAIM. NO R2 OR DATABASE MUTATION.');
    return;
  }
  const env = process.env;
  const completed = await applyExactNine(validated, {
    approved: env.BW_C3B7_APPROVED, confirmation: env.BW_C3B7_CONFIRM,
    stagingKey: env.BW_C3B7_STAGING_KEY,
    aEmail: env.BW_C3B7_A_EMAIL, aPassword: env.BW_C3B7_A_PASSWORD,
    bEmail: env.BW_C3B7_B_EMAIL, bPassword: env.BW_C3B7_B_PASSWORD,
  });
  console.log(`DONE: ${completed}/9 targeted Worker removals finalized. Independent R2 read-back remains a separate gate.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  cli().catch((error) => {
    // Never include error.message from network/provider: fixed local codes only.
    console.error(`STOP: ${error instanceof GuardError ? error.message : 'unexpected_or_network_failure'}`);
    process.exitCode = 2;
  });
}
