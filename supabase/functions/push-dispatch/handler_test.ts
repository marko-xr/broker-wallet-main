// deno test --allow-env --allow-net=127.0.0.1 --no-config supabase/functions/push-dispatch/handler_test.ts
//
// Runs the real handler (index.ts) with fetch replaced by a fake Supabase,
// Google OAuth and FCM. No real network, no real keys.
import { assertEquals } from 'jsr:@std/assert@1';

const realFetch = globalThis.fetch;
const calls: { url: string; body: unknown }[] = [];
let fcmAnswer: { status: number; body: unknown } = { status: 200, body: { name: 'projects/broker-wallet/messages/1' } };
let claimed: unknown[] = [];
const VALID_NONCE = '0123456789abcdef'.repeat(4);
const issuedNonces = new Set<string>([VALID_NONCE]);

// A throwaway RSA key in the service-account shape (generated per run).
const keys = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'],
);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', keys.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
function serviceAccount(project: string) {
  return JSON.stringify({ project_id: project, client_email: 'svc@example.iam.gserviceaccount.com', private_key: pem });
}

Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service-role-test');
Deno.env.set('PUSH_DISPATCH_SECRET', 'test-secret-value');
Deno.env.set('FCM_SERVICE_ACCOUNT_JSON', serviceAccount('broker-wallet'));

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  if (url.startsWith('http://127.0.0.1')) return realFetch(input, init);
  const body = init?.body instanceof URLSearchParams ? Object.fromEntries(init.body) :
    typeof init?.body === 'string' ? JSON.parse(init.body) : null;
  calls.push({ url, body });
  const reply = (status: number, b: unknown) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });
  if (url.endsWith('/rpc/fire_due_follow_up_reminders')) return reply(200, 1);
  if (url.endsWith('/rpc/claim_push_delivery_jobs')) return reply(200, claimed);
  if (url.endsWith('/rpc/complete_push_delivery_job')) return reply(200, true);
  if (url.endsWith('/rpc/consume_push_dispatch_nonce')) {
    const nonce = (body as { p_nonce: string }).p_nonce;
    const ok = issuedNonces.delete(nonce);
    return reply(200, ok);
  }
  if (url.startsWith('https://oauth2.googleapis.com/token')) return reply(200, { access_token: 'ya29.test', expires_in: 3600 });
  if (url.startsWith('https://fcm.googleapis.com/')) return reply(fcmAnswer.status, fcmAnswer.body);
  return reply(404, {});
}) as typeof fetch;

const port = 18000 + Math.floor(Math.random() * 1000);
const realServe = Deno.serve;
let server: Deno.HttpServer | null = null;
// index.ts calls Deno.serve(handler); bind it to a local test port.
(Deno as unknown as { serve: unknown }).serve = (handler: Deno.ServeHandler) => {
  server = realServe({ port, hostname: '127.0.0.1', onListen() {} }, handler);
  return server;
};
await import('./index.ts');
(Deno as unknown as { serve: unknown }).serve = realServe;

const base = `http://127.0.0.1:${port}/`;
const post = (body: unknown, secret?: string) =>
  realFetch(base, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(secret ? { 'x-dispatch-secret': secret } : {}) },
    body: JSON.stringify(body),
  });
const job = {
  job_id: 'j1', notification_id: '11111111-1111-4111-8111-111111111111', device_id: 'd1',
  token: 'device-token', locale: 'ar', target: 'request', attempt: 1,
};

Deno.test({ name: 'push-dispatch handler', sanitizeOps: false, sanitizeResources: false }, async (t) => {
  await t.step('rejects calls without or with a wrong secret, and non-POST', async () => {
    calls.length = 0;
    assertEquals((await post({})).status, 401);
    assertEquals((await post({}, 'wrong')).status, 401);
    const get = await realFetch(base);
    await get.body?.cancel();
    assertEquals(get.status, 405);
    assertEquals(calls.length, 0, 'nothing reached Supabase or Google');
  });

  await t.step('check mode: key, OAuth and a validate_only FCM probe; nothing else', async () => {
    calls.length = 0;
    fcmAnswer = { status: 400, body: { error: { status: 'INVALID_ARGUMENT' } } };
    const r = await post({ mode: 'check' }, 'test-secret-value');
    const out = await r.json();
    assertEquals([r.status, out.ok, out.oauth, out.fcm_api], [200, true, true, 'enabled']);
    assertEquals(calls.map((c) => new URL(c.url).hostname), ['oauth2.googleapis.com', 'fcm.googleapis.com']);
    const probe = calls[1].body as { validate_only: boolean; message: { token: string } };
    assertEquals(probe.validate_only, true);
    assertEquals(probe.message.token, 'bw-fcm-api-check-not-a-real-token');
  });

  await t.step('check mode reports a disabled FCM API', async () => {
    calls.length = 0;
    fcmAnswer = { status: 403, body: { error: { status: 'PERMISSION_DENIED' } } };
    const out = await (await post({ mode: 'check' }, 'test-secret-value')).json();
    assertEquals([out.ok, out.fcm_api], [false, 'disabled_or_denied']);
    assertEquals(calls.some((c) => c.url.includes('/rpc/')), false, 'no database call');
  });

  await t.step('a normal run fires, claims, sends and completes', async () => {
    calls.length = 0;
    claimed = [job];
    fcmAnswer = { status: 200, body: { name: 'projects/broker-wallet/messages/1' } };
    const r = await post({}, 'test-secret-value');
    const out = await r.json();
    assertEquals([out.fired, out.claimed, out.sent], [1, 1, 1]);
    const fcm = calls.find((c) => c.url.includes('fcm.googleapis.com'))!;
    assertEquals(fcm.url, 'https://fcm.googleapis.com/v1/projects/broker-wallet/messages:send');
    const done = calls.find((c) => c.url.endsWith('/rpc/complete_push_delivery_job'))!;
    assertEquals((done.body as Record<string, unknown>).p_outcome, 'sent');
  });

  await t.step('SENDER_ID_MISMATCH fails the job and keeps the device', async () => {
    calls.length = 0;
    claimed = [job];
    fcmAnswer = { status: 403, body: { error: { status: 'PERMISSION_DENIED', details: [{ errorCode: 'SENDER_ID_MISMATCH' }] } } };
    await (await post({}, 'test-secret-value')).json();
    const done = calls.find((c) => c.url.endsWith('/rpc/complete_push_delivery_job'))!.body as Record<string, unknown>;
    assertEquals(done.p_outcome, 'failed');
    assertEquals(done.p_device_id, undefined, 'no device deletion');
  });

  await t.step('UNREGISTERED removes the device', async () => {
    calls.length = 0;
    claimed = [job];
    fcmAnswer = { status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } };
    await (await post({}, 'test-secret-value')).json();
    const done = calls.find((c) => c.url.endsWith('/rpc/complete_push_delivery_job'))!.body as Record<string, unknown>;
    assertEquals([done.p_outcome, done.p_device_id], ['invalid_token', 'd1']);
  });

  const postNonce = (nonce: string) =>
    realFetch(base, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-dispatch-nonce': nonce },
      body: '{}',
    });

  await t.step('a scheduler nonce works exactly once', async () => {
    calls.length = 0;
    claimed = [];
    const first = await postNonce(VALID_NONCE);
    assertEquals(first.status, 200);
    await first.body?.cancel();
    assertEquals((calls[0].body as { p_nonce: string }).p_nonce, VALID_NONCE);
    const again = await postNonce(VALID_NONCE);
    await again.body?.cancel();
    assertEquals(again.status, 401, 'a replayed nonce is refused');
  });

  await t.step('a malformed nonce is refused without a database call', async () => {
    calls.length = 0;
    for (const bad of ['', 'abc', 'Z'.repeat(64), `${VALID_NONCE}0`, "' or 1=1 --"]) {
      const r = await postNonce(bad);
      await r.body?.cancel();
      assertEquals(r.status, 401, bad);
    }
    assertEquals(calls.length, 0);
  });

  await t.step('a 503 is retried with the provider delay', async () => {
    calls.length = 0;
    claimed = [job];
    fcmAnswer = { status: 503, body: {} };
    await (await post({}, 'test-secret-value')).json();
    const done = calls.find((c) => c.url.endsWith('/rpc/complete_push_delivery_job'))!.body as Record<string, unknown>;
    assertEquals(done.p_outcome, 'retry');
  });

  await server!.shutdown();
});
