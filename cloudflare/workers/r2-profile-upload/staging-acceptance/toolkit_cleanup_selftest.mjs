import test from 'node:test';
import assert from 'node:assert/strict';
import { validateManifest, GuardError, applyExactNine } from './toolkit_cleanup_exact9.mjs';

const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
const labels = {
  '20261020T124143Z': ['a-pdf', 'a-jpeg', 'a-png', 'a-wrong-claim'],
  '20261020T124907Z': ['b-writeonce'],
  '20261020T150501Z': ['c-owned-by-a', 'c-owned-by-b'],
  '20261020T150959Z': ['d-lifecycle-renamed', 'd-retry'],
};
function manifest() {
  let i = 1;
  const records = Object.entries(labels).flatMap(([run, names]) => names.map((name) => ({
    documentId: `33333333-3333-4333-8333-${String(i++).padStart(12, '0')}`,
    ownerId: name === 'c-owned-by-b' ? b : a,
    bucket: 'broker-wallet-media-staging',
    title: `staging-e2e-toolkit-${run}-${name}`,
    status: 'pending_delete',
    lastAuthorizedAt: '2026-10-20T15:00:00Z', deletedAt: '2026-10-20T15:01:00Z',
  })));
  return { schemaVersion: 1, bucket: 'broker-wallet-media-staging', records };
}
const NOW = Date.parse('2026-10-20T20:00:00Z');
function fails(m, code, now = NOW) {
  assert.throws(() => validateManifest(m, now), (e) => e instanceof GuardError && e.message === code);
}
test('valid scope contains exactly eight A and one B', () => {
  const v = validateManifest(manifest(), NOW);
  assert.equal(v.forA.length, 8);
  assert.equal(v.forB.length, 1);
});
test('ten or eight rows refuse', () => {
  const ten = manifest(); ten.records.push(structuredClone(ten.records[0])); fails(ten, 'must_contain_exactly_nine_rows');
  const eight = manifest(); eight.records.pop(); fails(eight, 'must_contain_exactly_nine_rows');
});
test('production bucket, bad schema and changed scope refuse', () => {
  const m = manifest(); m.bucket = 'broker-wallet-media'; fails(m, 'wrong_project_or_bucket');
  const n = manifest(); n.schemaVersion = 2; fails(n, 'wrong_project_or_bucket');
  const o = manifest(); o.records[0].bucket = 'broker-wallet-media'; fails(o, 'wrong_bucket_or_status');
});
test('ready row / abandoned or unexpected title refuse', () => {
  const m = manifest(); m.records[0].status = 'ready'; fails(m, 'wrong_bucket_or_status');
  const n = manifest(); n.records[0].title = 'random-private-document'; fails(n, 'unexpected_title_or_run');
});
test('duplicate id or title refuse', () => {
  const m = manifest(); m.records[1].documentId = m.records[0].documentId; fails(m, 'duplicate_document_or_title');
  const n = manifest(); n.records[1].title = n.records[0].title; fails(n, 'duplicate_document_or_title');
});
test('wrong account distribution refuses', () => {
  const m = manifest(); m.records[1].ownerId = b; fails(m, 'unexpected_document_account');
  const n = manifest(); n.records[6].ownerId = a; fails(n, 'expected_two_distinct_accounts');
});
test('no deletion while signed PUT window has not settled', () => {
  const m = manifest(); m.records[0].lastAuthorizedAt = '2026-10-20T19:55:00Z'; fails(m, 'signed_upload_window_not_settled');
  const n = manifest(); n.records[0].deletedAt = '2026-10-20T19:51:00Z'; fails(n, 'signed_upload_window_not_settled');
});
test('extra unexpected fields refuse', () => {
  const m = manifest(); m.records[0].objectKey = 'profiles/secret'; fails(m, 'row_shape_invalid');
});
test('apply without a second authorization cannot even attempt a network call', async () => {
  const v = validateManifest(manifest(), NOW);
  await assert.rejects(() => applyExactNine(v, {approved: '0'}), (e) => e instanceof GuardError && e.message === 'approval_missing');
});
