// Reads a DECRYPTED Broker Wallet backup stream on stdin and prints counts only:
// never a row, never a value. Usage: gpg -d file | node verify_backup.mjs baseline.json [plain-sha256]
import crypto from 'node:crypto';
import fs from 'node:fs';

const [baselinePath, expectedSha] = process.argv.slice(2);
const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
const hash = crypto.createHash('sha256');

const parts = [];
let part = null;
let copyTable = null;
let copyRows = 0;
const rows = {};          // "schema.table" -> rows, from the data part
const historyRows = {};   // from the history_data part
const schema = { tables: 0, rls: 0, policies: 0, functions: 0, triggers: 0, views: 0 };
let roleStatements = 0;
let carry = '';

function line(l) {
  if (l.startsWith('-- BW-BACKUP-PART ')) { part = l.slice(18).trim(); parts.push(part); return; }
  if (copyTable) {
    if (l === '\\.') { (part === 'history_data' ? historyRows : rows)[copyTable] = copyRows; copyTable = null; }
    else copyRows++;
    return;
  }
  const copy = /^COPY "([^"]+)"\."([^"]+)" .* FROM stdin;$/.exec(l);
  if (copy) { copyTable = `${copy[1]}.${copy[2]}`; copyRows = 0; return; }
  if (part === 'roles' && /^(ALTER|CREATE|GRANT) /.test(l)) roleStatements++;
  if (part !== 'schema') return;
  if (/^CREATE TABLE IF NOT EXISTS "public"\./.test(l)) schema.tables++;
  else if (/^ALTER TABLE "public"\."[^"]+" ENABLE ROW LEVEL SECURITY;$/.test(l)) schema.rls++;
  else if (/^CREATE POLICY .* ON "public"\./.test(l)) schema.policies++;
  else if (/^CREATE OR REPLACE FUNCTION "public"\./.test(l)) schema.functions++;
  else if (/^CREATE OR REPLACE TRIGGER /.test(l)) schema.triggers++;
  else if (/^CREATE OR REPLACE VIEW "public"\./.test(l)) schema.views++;
}

process.stdin.on('data', (chunk) => {
  hash.update(chunk);
  const text = carry + chunk.toString('utf8');
  const lines = text.split('\n');
  carry = lines.pop();
  for (const l of lines) line(l.replace(/\r$/, ''));
});

process.stdin.on('end', () => {
  if (carry) line(carry);
  const sha = hash.digest('hex');
  const volatile = new Set(baseline.volatile);
  const mismatches = [];
  const missing = [];
  for (const [table, expected] of Object.entries(baseline.tables)) {
    if (!(table in rows)) { missing.push(table); continue; }
    if (rows[table] !== expected) {
      mismatches.push({ table, backup: rows[table], production: expected, volatile: volatile.has(table) });
    }
  }
  const extra = Object.keys(rows).filter((t) => !(t in baseline.tables));
  const order = ['roles', 'schema', 'restore-setting', 'data', 'restore-setting', 'history_schema', 'history_data', 'end'];
  const historyCount = historyRows['supabase_migrations.schema_migrations'];
  const expectedSchema = baseline.schema;
  const schemaOk = Object.keys(expectedSchema).every((k) => schema[k] === expectedSchema[k]);
  const hardMismatches = mismatches.filter((m) => !m.volatile);
  const result = {
    plaintextSha256: sha,
    plaintextShaMatchesEncryptionTime: expectedSha ? sha === expectedSha : null,
    partsInOrder: JSON.stringify(parts) === JSON.stringify(order),
    parts,
    roleStatements,
    schema,
    schemaMatchesProduction: schemaOk,
    dataTables: Object.keys(rows).length,
    dataRowsBySchema: Object.entries(rows).reduce((a, [t, n]) => { const s = t.split('.')[0]; a[s] = (a[s] || 0) + n; return a; }, {}),
    missingTables: missing,
    extraTables: extra,
    rowMismatches: mismatches,
    historyRows: historyCount,
    historyMatches: historyCount === baseline.migrations,
  };
  result.verdict = result.partsInOrder && result.plaintextShaMatchesEncryptionTime !== false && schemaOk
    && missing.length === 0 && hardMismatches.length === 0 && result.historyMatches && roleStatements > 0
    ? 'PASS' : 'FAIL';
  console.log(JSON.stringify(result, null, 1));
  process.exitCode = result.verdict === 'PASS' ? 0 : 3;
});
