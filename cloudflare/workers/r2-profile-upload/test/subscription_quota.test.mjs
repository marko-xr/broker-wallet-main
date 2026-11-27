// The Worker's side of the subscription quota: how the database's refusals reach
// the app, and the media gate. The database itself is faked here; its rules are
// proven in supabase/tests/subscription_quotas_test.sql.
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import worker, { assertSubscriptionAllowsMediaChange } from '../worker.js';
import { ALICE, DOC_1, makeState, pdfBytes, sha256Hex } from './toolkit_fakes.mjs';

let state;
let originalFetch;
let refusals;
beforeEach(() => {
  state = makeState();
  refusals = {};
  originalFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    const url = typeof input === 'string' ? input : input.url;
    const name = new URL(url).pathname.replace('/rest/v1/rpc/', '');
    if (refusals[name]) {
      const { status, body } = refusals[name];
      return Promise.resolve(new Response(JSON.stringify(body), { status }));
    }
    return state.supabase.fetch(input, init);
  };
});
afterEach(() => { globalThis.fetch = originalFetch; });

async function post(path, body) {
  const response = await worker.fetch(new Request(`https://worker.test${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer token-a' },
    body: JSON.stringify(body),
  }), state.env, {});
  return { status: response.status, body: await response.json() };
}

const bytes = pdfBytes();
const KEY = `profiles/${ALICE}/toolkit-documents/${DOC_1}.pdf`;
const authBody = {
  documentId: DOC_1, documentType: 'scanner', title: 'Doc', contentType: 'application/pdf',
  contentLength: bytes.length, contentSha256: sha256Hex(bytes), pageCount: 2,
  sourceCreatedAt: '2026-10-19T08:00:00.000Z',
};

for (const code of ['PBQ01', 'PBQ03']) {
  test(`an authorize refused with ${code} gets no upload link`, async () => {
    refusals.authorize_toolkit_document_upload = { status: 400, body: { code } };
    const result = await post('/toolkit-documents/authorize', authBody);
    assert.equal(result.status, 409);
    assert.equal(result.body.code, 'document_limit_reached');
    assert.equal(result.body.presignedUrl, undefined);
  });
}

test('a plan that cannot be verified refuses as unavailable', async () => {
  refusals.authorize_toolkit_document_upload = { status: 400, body: { code: 'PBQ06' } };
  const result = await post('/toolkit-documents/authorize', authBody);
  assert.equal(result.status, 503);
  assert.equal(result.body.code, 'session_check_unavailable');
});

test('any other database failure stays a plain backend error', async () => {
  refusals.authorize_toolkit_document_upload = { status: 500, body: { code: 'XX000' } };
  assert.equal((await post('/toolkit-documents/authorize', authBody)).status, 502);
});

test('a confirm refused by the plan removes the uploaded bytes', async () => {
  assert.equal((await post('/toolkit-documents/authorize', authBody)).status, 200);
  state.bucket.put(KEY, bytes, 'application/pdf');
  refusals.confirm_toolkit_document_upload = { status: 400, body: { code: 'PBQ01' } };
  const result = await post('/toolkit-documents/confirm', { documentId: DOC_1 });
  assert.equal(result.status, 409);
  assert.equal(result.body.code, 'document_limit_reached');
  assert.equal(await state.bucket.head(KEY), null);
});

test('a confirm that merely failed keeps the bytes for the retry', async () => {
  assert.equal((await post('/toolkit-documents/authorize', authBody)).status, 200);
  state.bucket.put(KEY, bytes, 'application/pdf');
  refusals.confirm_toolkit_document_upload = { status: 500, body: {} };
  assert.equal((await post('/toolkit-documents/confirm', { documentId: DOC_1 })).status, 502);
  assert.notEqual(await state.bucket.head(KEY), null);
});

// ---------------------------------------------------------------------------
// The media gate
// ---------------------------------------------------------------------------

const ITEM = '33333333-3333-4333-8333-333333333333';
const MEDIA = '44444444-4444-4444-8444-444444444444';
const gate = (env) => assertSubscriptionAllowsMediaChange(env, ALICE, 'offers', ITEM, MEDIA);

function answering(status, value) {
  const calls = [];
  globalThis.fetch = (input, init) => {
    calls.push({ url: String(input.url ?? input), body: JSON.parse(init.body) });
    return Promise.resolve(new Response(JSON.stringify(value), { status }));
  };
  return calls;
}

test('the gate is off unless the deployment turns it on', async () => {
  for (const value of [undefined, 'off', 'true', 'ON']) {
    const calls = answering(200, 'read_only');
    await gate({ ...state.env, SUBSCRIPTION_ENFORCEMENT: value });
    assert.equal(calls.length, 0);
  }
});

test('the gate asks about this account, item and media', async () => {
  const calls = answering(200, 'allowed');
  await gate({ ...state.env, SUBSCRIPTION_ENFORCEMENT: 'on' });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /subscription_authorize_media_change$/);
  assert.deepEqual(calls[0].body, { p_user: ALICE, p_section: 'offers', p_item: ITEM, p_media: MEDIA });
});

for (const [decision, code] of [['read_only', 'subscription_read_only'], ['edit_required', 'subscription_edit_required']]) {
  test(`the gate refuses ${decision}`, async () => {
    answering(200, decision);
    await assert.rejects(gate({ ...state.env, SUBSCRIPTION_ENFORCEMENT: 'on' }),
      (error) => error.status === 403 && error.code === code);
  });
}

test('an unexpected answer refuses', async () => {
  answering(200, 'something_else');
  await assert.rejects(gate({ ...state.env, SUBSCRIPTION_ENFORCEMENT: 'on' }),
    (error) => error.status === 403);
});

test('a backend that cannot answer refuses', async () => {
  answering(500, {});
  await assert.rejects(gate({ ...state.env, SUBSCRIPTION_ENFORCEMENT: 'on' }),
    (error) => error.status === 503 && error.code === 'session_check_unavailable');
});

test('all six media-changing routes pass through the gate after the ownership check', () => {
  const source = fs.readFileSync(new URL('../worker.js', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  for (const [handler, ownership] of [
    ['handleMediaAuthorize', 'assertOwnsParent'],
    ['handleMediaRemove', 'assertOwnsParent'],
    ['handleQuotationAuthorize', 'loadOwnedQuotation'],
    ['handleQuotationRemove', 'loadOwnedQuotation'],
    ['handlePlanAuthorize', 'loadOwnedPlanParent'],
    ['handlePlanRemove', 'loadOwnedPlanParent'],
  ]) {
    const start = source.indexOf(`async function ${handler}(`);
    assert.notEqual(start, -1, handler);
    const body = source.slice(start, source.indexOf('\n}\n', start));
    const owned = body.indexOf(`await ${ownership}(`);
    const gated = body.indexOf('await assertSubscriptionAllowsMediaChange(');
    assert.ok(owned !== -1 && gated > owned, `${handler} checks ownership, then the plan`);
  }
});
