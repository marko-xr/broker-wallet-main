// Broker Wallet — P4.3b read-only pagination checks (GET only).
//
// The six entity lists of the Flutter app read pages through
// SupabaseCoreEntitiesService._pagedRows (lib/src/services/
// supabase_core_entities_service.dart). This module sends the SAME requests,
// read from that source file rather than copied, with an access token it is
// given, and checks what the hosted PostgREST answers:
//
//   - exact count and the Content-Range header of the first page;
//   - the production page (limit 500) and how many rows it really holds, which
//     shows the hosted row cap (max_rows) when a list is larger than it;
//   - created_at DESC, id DESC order, strictly, inside and across pages;
//   - the keyset cursor (raw created_at text + id), walked with a SMALL page
//     (default 2) and compared with the production page: same rows, same order,
//     none repeated, none skipped;
//   - a complete walk with the production page size, only when a list holds
//     more than one production page (never claimed otherwise);
//   - ownership: every row is the signed-in account's, a query without the
//     owner filter counts the same (RLS), another owner id counts 0;
//   - empty answers: a cursor older than every row, and another owner's list.
//
// Nothing here signs in, claims, releases or writes: every request goes through
// getOnly(), which refuses any method but GET. Output is aggregate only — row
// counts, statuses, header shapes and PASS/FAIL. Never a row, id, timestamp,
// token or URL.
//
// Node built-ins only: no `npm install` is needed.

import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = join(HERE, '..', '..', '..', '..');
export const CONFIG_SOURCE = join(REPO_ROOT, 'lib', 'src', 'config', 'supabase_config.dart');
export const SERVICE_SOURCE = join(REPO_ROOT, 'lib', 'src', 'services', 'supabase_core_entities_service.dart');

export const TABLES = Object.freeze(['requests', 'offers', 'owners', 'offices', 'brokers', 'watchmen']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** A configuration problem found before any request. */
export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

// ---------------------------------------------------------------------------
// The production contract, read from the app's own source
// ---------------------------------------------------------------------------

/** URL and publishable key exactly as the app is built with by default. */
export function loadSupabaseConfig(source = readFileSync(CONFIG_SOURCE, 'utf8')) {
  const url = /'SUPABASE_URL',\s*defaultValue:\s*'([^']+)'/.exec(source)?.[1];
  const key = /'SUPABASE_PUBLISHABLE_KEY',\s*defaultValue:\s*'([^']+)'/.exec(source)?.[1];
  if (!url || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)) {
    throw new ConfigError('could not read an https Supabase URL from supabase_config.dart');
  }
  if (!key || !key.startsWith('sb_publishable_')) {
    throw new ConfigError('could not read a publishable key from supabase_config.dart');
  }
  return { supabaseUrl: url, publishableKey: key };
}

/**
 * The page contract of `_pagedRows`: page size, page bound, row bound and the
 * columns each list selects (postgrest-dart strips the whitespace of a select).
 * Refuses a source whose contract this tool was not written for.
 */
export function loadPagingContract(source = readFileSync(SERVICE_SOURCE, 'utf8')) {
  const int = (name) => Number(new RegExp(`static const int ${name} = (\\d+);`).exec(source)?.[1]);
  const cols = (name) => new RegExp(`static const String ${name} = '''([\\s\\S]*?)'''`).exec(source)?.[1]?.replace(/\s+/g, '');
  const pageSize = int('_pageSize');
  const maxPages = int('_maxPages');
  const maxListRows = int('_maxListRows');
  const requestColumns = cols('_requestColumns');
  const offerColumns = cols('_offerColumns');
  const lists = {
    requests: /_wholeList\('requests', _requestColumns,/.test(source),
    offers: /_wholeList\('offers', _offerColumns,/.test(source),
    owners: /_wholeList\('owners', '\*',/.test(source),
    offices: /_wholeList\('offices', '\*',/.test(source),
    brokers: /_wholeList\('brokers', '\*',/.test(source),
    watchmen: /_wholeList\('watchmen', '\*',/.test(source),
  };
  const shape = /\.order\('created_at', ascending: false\)\s*\.order\('id', ascending: false\)\s*\.limit\(_pageSize\)/.test(source) &&
    /'created_at\.lt\.\$\{after\.at\},'\s*'and\(created_at\.eq\.\$\{after\.at\},id\.lt\.\$\{after\.id\}\)'/.test(source) &&
    /\.eq\('owner_id', ownerId\)\s*\.isFilter\('deleted_at', null\)/.test(source);
  const missing = Object.entries(lists).filter(([, ok]) => !ok).map(([t]) => t);
  if (!Number.isInteger(pageSize) || !Number.isInteger(maxPages) || !Number.isInteger(maxListRows) ||
      !requestColumns || !offerColumns || missing.length || !shape) {
    throw new ConfigError(`the paging contract in supabase_core_entities_service.dart is not the one this tool checks${missing.length ? ` (${missing.join(', ')})` : ''}`);
  }
  return {
    pageSize, maxPages, maxListRows,
    columns: { requests: requestColumns, offers: offerColumns, owners: '*', offices: '*', brokers: '*', watchmen: '*' },
  };
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/** Removes anything URL-, token- or uuid-shaped, so nothing identifying is printed. */
export function sanitize(value) {
  return String(value ?? '')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<jwt>')
    .replace(/sb_(publishable|secret)_[\w-]+/g, '<key>')
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '<uuid>')
    .replace(/\d{4}-\d{2}-\d{2}T[\d:.]+([+-]\d{2}:\d{2}|Z)?/g, '<time>')
    .slice(0, 300);
}

/**
 * A PostgREST timestamptz ("2026-11-03T12:34:56.123456+00:00"; 0–6 fraction
 * digits; offset or Z) as microseconds since the epoch, or null.
 */
export function microsOf(text) {
  const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?([+-]\d{2}:\d{2}|Z)$/.exec(String(text));
  if (!m) return null;
  const ms = Date.parse(`${m[1]}T${m[2]}${m[4]}`);
  if (Number.isNaN(ms)) return null;
  return BigInt(ms) * 1000n + BigInt((m[3] ?? '').padEnd(6, '0'));
}

/** Content-Range "a-b/T", "*\/T" or with "*" totals, parsed; null when absent or malformed. */
export function parseContentRange(header) {
  if (header == null) return null;
  const m = /^(?:(\d+)-(\d+)|\*)\/(\d+|\*)$/.exec(String(header).trim());
  if (!m) return { malformed: true };
  return {
    from: m[1] == null ? null : Number(m[1]),
    to: m[2] == null ? null : Number(m[2]),
    total: m[3] === '*' ? null : Number(m[3]),
  };
}

/** The shape of a Content-Range header with its numbers hidden: "a-b/T", "*\/0", "*\/*". */
export function rangeShape(header) {
  if (header == null) return 'absent';
  const r = parseContentRange(header);
  if (r.malformed) return 'malformed';
  const left = r.from == null ? '*' : 'a-b';
  const right = r.total == null ? '*' : (r.total === 0 ? '0' : 'T');
  return `${left}/${right}`;
}

/**
 * Checks that [rows] are strictly newest first by (created_at, id), each id a
 * canonical lowercase uuid seen once; [after] is the previous page's last key.
 * Returns { ok, problem, last }.
 */
export function checkOrder(rows, after = null, seen = new Set()) {
  let previous = after;
  for (const row of rows) {
    const id = row?.id;
    const at = microsOf(row?.created_at);
    if (typeof id !== 'string' || !UUID.test(id)) return { ok: false, problem: 'id is not a lowercase uuid' };
    if (at === null) return { ok: false, problem: 'created_at is not a timestamptz text' };
    if (seen.has(id)) return { ok: false, problem: 'a row came twice' };
    if (previous && !(at < previous.at || (at === previous.at && id < previous.id))) {
      return { ok: false, problem: 'a row is not strictly after the one before it' };
    }
    seen.add(id);
    previous = { at, id, rawAt: row.created_at };
  }
  return { ok: true, problem: '', last: previous };
}

/** The `or` keyset filter `_pagedRows` sends after a row (raw created_at text). */
export function keysetFilter(rawAt, id) {
  return `(created_at.lt.${rawAt},and(created_at.eq.${rawAt},id.lt.${id}))`;
}

/** The query string of one list page, in the client's own parameter order. */
export function pageQuery({ columns, ownerId, cursor = null, limit, ownerFilter = true }) {
  const p = new URLSearchParams();
  p.set('select', columns);
  if (ownerFilter) p.set('owner_id', `eq.${ownerId}`);
  p.set('deleted_at', 'is.null');
  if (cursor) p.set('or', keysetFilter(cursor.rawAt, cursor.id));
  p.set('order', 'created_at.desc.nullslast,id.desc.nullslast');
  p.set('limit', String(limit));
  return p.toString();
}

// ---------------------------------------------------------------------------
// GET-only transport
// ---------------------------------------------------------------------------

/**
 * A fetch that can only GET [supabaseUrl]/rest/v1/<table>. No retry: one call,
 * one answer. Resolves { status, range, rows } or { status, range, error }.
 */
export function getOnly({ supabaseUrl, publishableKey, fetchImpl = fetch, timeoutMs = 30_000, onRequest = () => {} }) {
  return async function get(table, query, { count = false, accessToken }) {
    if (!TABLES.includes(table)) throw new Error('getOnly: not one of the six list tables');
    const headers = { apikey: publishableKey, Authorization: `Bearer ${accessToken}`, Accept: 'application/json' };
    if (count) headers.Prefer = 'count=exact';
    const init = { method: 'GET', headers, signal: AbortSignal.timeout(timeoutMs) };
    if (init.method !== 'GET') throw new Error('getOnly: GET only');
    onRequest(table);
    let response;
    try {
      response = await fetchImpl(`${supabaseUrl}/rest/v1/${table}?${query}`, init);
    } catch (_) {
      return { status: 0, range: null, error: 'network' };
    }
    const range = response.headers.get('content-range');
    let body = null;
    try {
      body = await response.json();
    } catch (_) {
      body = null;
    }
    if (response.status === 200 || response.status === 206) {
      return Array.isArray(body) ? { status: response.status, range, rows: body } : { status: response.status, range, error: 'not_a_list' };
    }
    const code = typeof body?.code === 'string' ? body.code.replace(/[^A-Z0-9]/gi, '').slice(0, 12) : '';
    return { status: response.status, range, error: code || 'http' };
  };
}

// ---------------------------------------------------------------------------
// The checks
// ---------------------------------------------------------------------------

/**
 * While the session is NOT the account's active one (never claimed, or
 * displaced), the database's restrictive app_session_gate hides every row:
 * each list must answer 200, [] and Content-Range "*\/0" — no error.
 */
export async function checkGateClosed({ get, contract, ownerId, accessToken, check, section }) {
  for (const table of TABLES) {
    const r = await get(table, pageQuery({ columns: contract.columns[table], ownerId, limit: contract.pageSize }), { count: true, accessToken });
    const total = parseContentRange(r.range)?.total;
    check(section, `${table}: gate closed ⇒ 200, no rows, count 0`,
      r.status === 200 && r.rows?.length === 0 && total === 0,
      `HTTP ${r.status}${r.error ? ` ${r.error}` : ''}, rows ${r.rows?.length ?? '-'}, range ${rangeShape(r.range)}`);
  }
}

/** All checks of one list for the ACTIVE session. Returns aggregate facts for the summary. */
export async function checkList({ get, contract, table, ownerId, accessToken, check, section, walkLimit = 2, maxWalkPages = 5 }) {
  const columns = contract.columns[table];
  const fact = { table, total: null, firstPageRows: null, firstStatus: null, serverCap: 'unknown', walked: 0, walkComplete: false, productionMultiPage: 'not exercised' };

  // 1) The production first page, exactly as the app sends it.
  const first = await get(table, pageQuery({ columns, ownerId, limit: contract.pageSize }), { count: true, accessToken });
  const range = parseContentRange(first.range);
  const total = range && !range.malformed ? range.total : null;
  if (!check(section, `${table}: first page (limit ${contract.pageSize}, count=exact) answers 200/206 with a list`,
    (first.status === 200 || first.status === 206) && Array.isArray(first.rows),
    `HTTP ${first.status}${first.error ? ` ${first.error}` : ''}`)) return fact;
  if (!check(section, `${table}: exact count present in Content-Range`, Number.isInteger(total),
    `range ${rangeShape(first.range)}`)) return fact;
  const rows = first.rows;
  fact.total = total;
  fact.firstPageRows = rows.length;
  const expectedShape = rows.length === 0 ? '*/0' : 'a-b/T';
  check(section, `${table}: Content-Range shape matches the rows`,
    rangeShape(first.range) === expectedShape && (rows.length === 0 || (range.from === 0 && range.to === rows.length - 1)),
    `range ${rangeShape(first.range)}, rows ${rows.length}, count ${total}`);
  check(section, `${table}: page holds at most ${contract.pageSize} rows and no more than the count`,
    rows.length <= contract.pageSize && rows.length <= total, `rows ${rows.length}, count ${total}`);
  // The client accepts 200 and 206 alike; which one the host sends is recorded, not judged.
  fact.firstStatus = `${first.status}${rows.length < total ? ' (page short of the count)' : ''}`;
  if (rows.length < Math.min(total, contract.pageSize)) fact.serverCap = `observed ${rows.length}`;
  else if (rows.length === contract.pageSize) fact.serverCap = `≥ ${contract.pageSize}`;
  else fact.serverCap = `≥ ${rows.length} (list smaller than a page)`;

  const order = checkOrder(rows);
  check(section, `${table}: first page strictly created_at DESC, id DESC, no repeats`, order.ok, order.problem);
  check(section, `${table}: every row belongs to the signed-in account`, rows.every((r) => r.owner_id === ownerId),
    `${rows.filter((r) => r.owner_id !== ownerId).length} other`);
  if (columns === '*') {
    check(section, `${table}: no deleted row in the list`, rows.every((r) => r.deleted_at === null),
      `${rows.filter((r) => r.deleted_at !== null).length} deleted`);
  }

  // 2) Ownership / RLS: no owner filter ⇒ the same count; another owner ⇒ 0.
  const unfiltered = await get(table, pageQuery({ columns: 'id', ownerId, limit: 0, ownerFilter: false }), { count: true, accessToken });
  check(section, `${table}: without the owner filter RLS still counts only this account's rows`,
    (unfiltered.status === 200 || unfiltered.status === 206) && parseContentRange(unfiltered.range)?.total === total,
    `HTTP ${unfiltered.status}, range ${rangeShape(unfiltered.range)}`);
  const other = await get(table, pageQuery({ columns: 'id', ownerId: randomUUID(), limit: contract.pageSize }), { count: true, accessToken });
  check(section, `${table}: another owner id ⇒ 200, no rows, "*/0"`,
    other.status === 200 && other.rows?.length === 0 && rangeShape(other.range) === '*/0',
    `HTTP ${other.status}, rows ${other.rows?.length ?? '-'}, range ${rangeShape(other.range)}`);

  // 3) Legitimate empty page: a cursor older than every row.
  const empty = await get(table, pageQuery({ columns, ownerId, limit: walkLimit, cursor: { rawAt: '1970-01-01T00:00:00+00:00', id: '00000000-0000-0000-0000-000000000000' } }), { accessToken });
  check(section, `${table}: cursor older than every row ⇒ 200 and an empty list`,
    empty.status === 200 && empty.rows?.length === 0, `HTTP ${empty.status}, rows ${empty.rows?.length ?? '-'}, range ${rangeShape(empty.range)}`);

  // 4) Small-page keyset walk, compared with the production page.
  if (total === 0) {
    check(section, `${table}: list is empty — keyset walk not applicable`, true, 'count 0');
    return fact;
  }
  const walkedIds = [];
  const seen = new Set();
  let cursor = null;
  let walkOk = true;
  for (let pageNo = 0; pageNo < maxWalkPages && walkedIds.length < total; pageNo++) {
    const page = await get(table, pageQuery({ columns, ownerId, limit: walkLimit, cursor }), { accessToken });
    if (page.status !== 200 || !Array.isArray(page.rows)) {
      walkOk = check(section, `${table}: keyset page ${pageNo + 1} answers 200`, false, `HTTP ${page.status}${page.error ? ` ${page.error}` : ''}`);
      break;
    }
    if (page.rows.length === 0) break;
    const o = checkOrder(page.rows, cursor && { at: microsOf(cursor.rawAt), id: cursor.id }, seen);
    if (!o.ok) {
      walkOk = check(section, `${table}: keyset page ${pageNo + 1} continues strictly after the cursor`, false, o.problem);
      break;
    }
    walkedIds.push(...page.rows.map((r) => r.id));
    cursor = o.last;
  }
  fact.walked = walkedIds.length;
  fact.walkComplete = walkOk && walkedIds.length === total;
  if (walkOk) {
    const prefix = rows.slice(0, walkedIds.length).map((r) => r.id);
    const same = walkedIds.length > 0 && walkedIds.every((id, i) => id === prefix[i]);
    check(section, `${table}: keyset walk (limit ${walkLimit}) returns the production page's rows in the same order, none repeated or skipped`,
      same, `walked ${walkedIds.length} of ${total}${fact.walkComplete ? ' (complete)' : ' (prefix only)'}`);
  }

  // 5) Production-size multi-page walk, only when the list needs it.
  if (total > rows.length) {
    const all = [...rows.map((r) => r.id)];
    const seenAll = new Set(all);
    let at = order.last;
    let pages = 1;
    let ok = order.ok;
    while (ok && all.length < total && pages < contract.maxPages) {
      const page = await get(table, pageQuery({ columns, ownerId, limit: contract.pageSize, cursor: at }), { accessToken });
      pages++;
      if (page.status !== 200 || !Array.isArray(page.rows) || page.rows.length === 0) break;
      const o = checkOrder(page.rows, at, seenAll);
      if (!o.ok) { ok = false; break; }
      all.push(...page.rows.map((r) => r.id));
      at = o.last;
    }
    fact.productionMultiPage = `${pages} pages, ${all.length} of ${total}`;
    check(section, `${table}: production paging (limit ${contract.pageSize}) collects exactly the count, ordered, no repeats`,
      ok && all.length === total, fact.productionMultiPage);
  }
  return fact;
}
