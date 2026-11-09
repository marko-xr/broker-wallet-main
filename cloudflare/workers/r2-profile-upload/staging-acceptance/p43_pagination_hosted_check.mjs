// Broker Wallet — P4.3b authenticated pagination check on the hosted project.
//
// OWNER-RUN ONLY, through run_p43_pagination_check.ps1, in the owner's own
// terminal. The hosted project is PRODUCTION (staging shares it).
//
// What it does, in this order, each state-changing step behind its own typed
// approval (answered at the keyboard; nothing runs without a terminal):
//
//   SIGN IN   one password sign-in of the dedicated test account → session S1.
//             No retry on failure. The account must be the one whose id the
//             owner gave, and never account A (the phone's account).
//   (read)    S1 is not claimed yet: the database must report it not current
//             and every list must come back empty with count 0 (the
//             Single Active Device gate), not as an error.
//   CLAIM     S1 claims the account's active app session, as the app does
//             after a sign-in. This ENDS every other session of the account.
//   (read)    The GET-only checks of p43_pagination_readonly_checks.mjs on all
//             six lists.
//   DISPLACE  (only with BW_P43_DISPLACEMENT=1) a second sign-in S2 claims;
//             S1 must then see empty lists, not be current, and be refused a
//             reclaim; S2 must see S1's counts.
//   cleanup   always, after any sign-in: release the active claim of the
//             session that holds it, then sign each session out with
//             scope=local (only that session; never the account's others).
//
// Writes it makes when approved (and nothing else): Auth creates one session per
// sign-in (and updates the account's last sign-in time); a claim inserts a
// permanent public.app_session_claims row and upserts public.user_active_sessions;
// release deletes that account's user_active_sessions row; sign-out ends the
// session. No app data (requests, offers, …) is created, changed or deleted.
//
// Output and the JSON report (reports/, git-ignored) hold PASS/FAIL, statuses,
// row COUNTS and header shapes. Never a password, token, email, account or row
// id, timestamp, row content or URL.
//
// Commands:  node p43_pagination_hosted_check.mjs plan   (no network)
//            node p43_pagination_hosted_check.mjs run    (hosted; launcher only)
// Node built-ins only: no `npm install` is needed.

import { createInterface } from 'node:readline/promises';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { AppSessionClaimError, claimAndVerifyAppSession, claimAppSession, isAppSessionCurrent } from './app_session_claim.mjs';
import {
  ConfigError, TABLES, checkGateClosed, checkList, getOnly, loadPagingContract, loadSupabaseConfig,
  pageQuery, parseContentRange, sanitize,
} from './p43_pagination_readonly_checks.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPORTS = join(HERE, 'reports');

/** Account A — the owner's phone account (same value as DESIGNATED_A_UID in quotation_media_production_smoke.mjs). Never used here. */
export const ACCOUNT_A_UID = '317d7619-01da-4420-8c7f-fe7c3fc2d6e7';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export const APPROVALS = Object.freeze({ signIn: 'SIGN IN', claim: 'CLAIM', displace: 'DISPLACE' });

class StopRun extends Error {}

// ---------------------------------------------------------------------------
// Configuration (no network)
// ---------------------------------------------------------------------------

function boundedInt(env, name, fallback, min, max) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) throw new ConfigError(`${name} must be a whole number from ${min} to ${max}`);
  return n;
}

/** Everything a hosted run needs, validated before any request. */
export function loadRunConfig(env = process.env, sources = {}) {
  const email = (env.BW_P43_EMAIL ?? '').trim();
  const password = env.BW_P43_PASSWORD ?? '';
  const expectedUid = (env.BW_P43_TEST_USER_ID ?? '').trim();
  if (!email || !email.includes('@')) throw new ConfigError('BW_P43_EMAIL is missing (the launcher asks for it)');
  if (!password) throw new ConfigError('BW_P43_PASSWORD is missing (the launcher asks for it)');
  if (!UUID.test(expectedUid)) throw new ConfigError('BW_P43_TEST_USER_ID must be the test account\'s user id (lowercase uuid)');
  if (expectedUid === ACCOUNT_A_UID) throw new ConfigError('BW_P43_TEST_USER_ID is account A (the phone\'s account); use the dedicated test account');
  return {
    ...loadSupabaseConfig(sources.config),
    contract: loadPagingContract(sources.service),
    email, password, expectedUid,
    displacement: env.BW_P43_DISPLACEMENT === '1',
    walkLimit: boundedInt(env, 'BW_P43_WALK_LIMIT', 2, 1, 10),
    maxWalkPages: boundedInt(env, 'BW_P43_WALK_PAGES', 5, 1, 20),
  };
}

// ---------------------------------------------------------------------------
// Session steps (state-changing; each one only after its approval)
// ---------------------------------------------------------------------------

async function json(response) {
  try { return await response.json(); } catch (_) { return null; }
}

/** One password sign-in. No retry. Resolves { token, uid } or throws StopRun with a fixed reason. */
async function signIn(cfg, fetchImpl, label) {
  let response;
  try {
    response = await fetchImpl(`${cfg.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: cfg.publishableKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: cfg.email, password: cfg.password }),
      signal: AbortSignal.timeout(30_000),
    });
  } catch (_) {
    throw new StopRun(`sign-in ${label} could not reach Auth (not retried)`);
  }
  const body = await json(response);
  if (!response.ok || typeof body?.access_token !== 'string' || typeof body?.user?.id !== 'string') {
    const reason = String(body?.error_code ?? body?.error ?? '').replace(/[^a-z0-9_]/gi, '').slice(0, 40);
    throw new StopRun(`sign-in ${label} refused (HTTP ${response.status}${reason ? ` ${reason}` : ''}; not retried)`);
  }
  return { label, token: body.access_token, uid: body.user.id };
}

/** release_current_app_session: deletes the account's active row only if this session holds it. */
async function release(cfg, fetchImpl, session) {
  try {
    const response = await fetchImpl(`${cfg.supabaseUrl}/rest/v1/rpc/release_current_app_session`, {
      method: 'POST',
      headers: { apikey: cfg.publishableKey, Authorization: `Bearer ${session.token}`, 'Content-Type': 'application/json' },
      body: '{}',
      signal: AbortSignal.timeout(30_000),
    });
    return { status: response.status, released: (await json(response)) === true };
  } catch (_) {
    return { status: 0, released: false };
  }
}

/** Ends THIS session only (scope=local); the account's other sessions are untouched. */
async function signOutLocal(cfg, fetchImpl, session) {
  try {
    const response = await fetchImpl(`${cfg.supabaseUrl}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: cfg.publishableKey, Authorization: `Bearer ${session.token}` },
      signal: AbortSignal.timeout(30_000),
    });
    return response.status;
  } catch (_) {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// The run
// ---------------------------------------------------------------------------

export function describePlan(cfg) {
  return [
    'P4.3b hosted pagination check — PRODUCTION project (staging shares it).',
    `Test account: ${cfg.expectedUid ? `the one with id …${cfg.expectedUid.slice(-6)}` : 'the id given at run time'} (account A is refused).`,
    `Lists: ${TABLES.join(', ')}. Production page ${cfg.contract.pageSize}; keyset walk limit ${cfg.walkLimit}, up to ${cfg.maxWalkPages} pages per list.`,
    `Steps needing approval: "${APPROVALS.signIn}" (one sign-in), "${APPROVALS.claim}" (claim the active session — ends the test account's other sessions)` +
      (cfg.displacement ? `, "${APPROVALS.displace}" (second sign-in + claim, displacing the first).` : '. Displacement: off.'),
    'Cleanup after any sign-in: release the claim, sign out with scope=local. No app data is written.',
  ];
}

/**
 * Runs the check. [ask] shows a question and resolves the typed answer;
 * [log] prints one line. Resolves { code, results, facts }.
 */
export async function run(cfg, { fetchImpl = fetch, ask, log = console.log } = {}) {
  const results = [];
  const facts = { lists: [], cleanup: [] };
  const check = (section, name, ok, detail = '') => {
    results.push({ section, name: sanitize(name), ok: Boolean(ok), detail: sanitize(detail) });
    log(`${ok ? 'PASS' : 'FAIL'}  [${section}] ${sanitize(name)}${detail ? `  (${sanitize(detail)})` : ''}`);
    return Boolean(ok);
  };
  const approve = async (word, what) => {
    const answer = await ask(`\n${what}\nType ${word} to continue, anything else stops: `);
    return answer === word;
  };
  const rest = { supabaseUrl: cfg.supabaseUrl, publishableKey: cfg.publishableKey, fetchImpl };
  const get = getOnly(rest);
  const sessions = [];
  let holder = null; // the session that holds the active claim, if any

  for (const line of describePlan(cfg)) log(line);
  try {
    if (!await approve(APPROVALS.signIn, 'Step 1: sign in once as the dedicated test account (creates one Auth session).')) {
      log('Stopped before sign-in. Nothing was sent.');
      return { code: 3, results, facts };
    }
    const s1 = await signIn(cfg, fetchImpl, 'S1');
    sessions.push(s1);
    if (!check('setup', 'signed-in account is the dedicated test account given by the owner, not account A',
      s1.uid === cfg.expectedUid && s1.uid !== ACCOUNT_A_UID)) {
      throw new StopRun('signed in to a different account than the one given; nothing was claimed or read');
    }

    // Unclaimed: the gate must hide every row (read-only).
    let current;
    try { current = await isAppSessionCurrent({ ...rest, accessToken: s1.token }); } catch (e) { current = e instanceof AppSessionClaimError ? `error ${e.code}` : 'error'; }
    check('gate-unclaimed', 'a fresh, unclaimed session is not the account\'s active session', current === false, String(current));
    await checkGateClosed({ get, contract: cfg.contract, ownerId: s1.uid, accessToken: s1.token, check, section: 'gate-unclaimed' });

    if (!await approve(APPROVALS.claim, 'Step 2: claim the active app session for S1 (ends every other session of the test account).')) {
      throw new StopRun('stopped before the claim');
    }
    try {
      await claimAndVerifyAppSession({ ...rest, accessToken: s1.token });
      holder = s1;
      check('claim', 'S1 claimed and the database confirms it is current', true);
    } catch (e) {
      check('claim', 'S1 claimed and the database confirms it is current', false, e instanceof AppSessionClaimError ? e.code : 'error');
      throw new StopRun('the claim failed (not retried)');
    }

    for (const table of TABLES) {
      facts.lists.push(await checkList({
        get, contract: cfg.contract, table, ownerId: s1.uid, accessToken: s1.token, check,
        section: 'lists', walkLimit: cfg.walkLimit, maxWalkPages: cfg.maxWalkPages,
      }));
    }

    if (cfg.displacement) {
      if (!await approve(APPROVALS.displace, 'Step 3: sign in again (S2) and claim with it, displacing S1.')) {
        throw new StopRun('stopped before the displacement step');
      }
      const s2 = await signIn(cfg, fetchImpl, 'S2');
      sessions.push(s2);
      if (!check('displace', 'S2 is the same test account', s2.uid === cfg.expectedUid)) throw new StopRun('S2 is a different account');
      try {
        await claimAndVerifyAppSession({ ...rest, accessToken: s2.token });
        holder = s2;
        check('displace', 'S2 claimed and is current', true);
      } catch (e) {
        check('displace', 'S2 claimed and is current', false, e instanceof AppSessionClaimError ? e.code : 'error');
        throw new StopRun('the S2 claim failed (not retried)');
      }
      let s1Now;
      try { s1Now = await isAppSessionCurrent({ ...rest, accessToken: s1.token }); } catch (e) { s1Now = 'error'; }
      check('displace', 'S1 is no longer current', s1Now === false, String(s1Now));
      await checkGateClosed({ get, contract: cfg.contract, ownerId: s1.uid, accessToken: s1.token, check, section: 'displace' });
      let reclaim = 'claimed';
      try { await claimAppSession({ ...rest, accessToken: s1.token }); } catch (e) { reclaim = e instanceof AppSessionClaimError ? e.code : 'error'; }
      check('displace', 'the displaced S1 is refused a reclaim (session_superseded)', reclaim === 'session_superseded', reclaim);
      if (reclaim === 'claimed') holder = s1;
      for (const fact of facts.lists) {
        if (fact.total === null) continue;
        const r = await get(fact.table, pageQuery({ columns: 'id', ownerId: s2.uid, limit: 0 }), { count: true, accessToken: s2.token });
        check('displace', `${fact.table}: S2 sees the same count S1 saw`, parseContentRange(r.range)?.total === fact.total, `HTTP ${r.status}`);
      }
    }
  } catch (error) {
    if (error instanceof StopRun) check('run', 'run completed', false, error.message);
    else check('run', 'run completed', false, `${error?.name ?? 'Error'}: ${sanitize(error?.message)}`);
  } finally {
    if (holder) {
      const r = await release(cfg, fetchImpl, holder);
      facts.cleanup.push({ step: `release ${holder.label}`, status: r.status, released: r.released });
      check('cleanup', `release the active claim held by ${holder.label}`, r.status === 200 && r.released, `HTTP ${r.status}`);
    }
    for (const s of sessions.reverse()) {
      const status = await signOutLocal(cfg, fetchImpl, s);
      facts.cleanup.push({ step: `sign out ${s.label} (scope=local)`, status });
      check('cleanup', `sign out ${s.label} with scope=local`, status === 204 || status === 200, `HTTP ${status}`);
    }
  }

  const fail = results.filter((r) => !r.ok).length;
  log('\nSummary (counts only):');
  for (const f of facts.lists) {
    log(`  ${f.table.padEnd(9)} count ${f.total ?? '-'} | first page ${f.firstPageRows ?? '-'} rows, HTTP ${f.firstStatus ?? '-'} | server cap ${f.serverCap} | ` +
      `walk ${f.walked}${f.walkComplete ? ' (complete)' : ''} | production multi-page: ${f.productionMultiPage}`);
  }
  log(`${fail === 0 ? 'ALL PASSED' : 'FAILURES'}: ${results.length - fail} passed, ${fail} failed.`);
  return { code: fail === 0 ? 0 : 1, results, facts };
}

function writeReport(outcome) {
  const runId = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
  const path = join(REPORTS, `p43_pagination_${runId}.json`);
  mkdirSync(REPORTS, { recursive: true });
  writeFileSync(path, JSON.stringify({ runId, kind: 'p43-pagination', results: outcome.results, facts: outcome.facts }, null, 2));
  console.log(`Report: reports/p43_pagination_${runId}.json`);
}

async function main(command) {
  if (command === 'plan') {
    const cfg = { ...loadSupabaseConfig(), contract: loadPagingContract(), expectedUid: null,displacement: process.env.BW_P43_DISPLACEMENT === '1', walkLimit: 2, maxWalkPages: 5 };
    for (const line of describePlan(cfg)) console.log(line);
    console.log('Plan only: no request was sent.');
    return 0;
  }
  if (command !== 'run') {
    console.error('Usage: node p43_pagination_hosted_check.mjs plan | run   (run only through run_p43_pagination_check.ps1)');
    return 2;
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error('Refused: the hosted run needs the owner at a terminal to approve each step. Nothing was sent.');
    return 2;
  }
  const cfg = loadRunConfig();
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const outcome = await run(cfg, { ask: (q) => rl.question(q) });
    writeReport(outcome);
    return outcome.code;
  } finally {
    rl.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv[2]).then((code) => process.exit(code), (error) => {
    console.error(error instanceof ConfigError ? `Refused: ${error.message}. Nothing was sent.` : `Error: ${sanitize(error?.message)}`);
    process.exit(2);
  });
}
