// node --test supabase/functions/push-dispatch/fcm.test.ts   (Node >= 23.6)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import {
  EXPECTED_FIREBASE_PROJECT,
  buildMessage,
  classify,
  errorCode,
  parseServiceAccount,
  probeApiState,
  sameSecret,
  signedAssertion,
  validateOnlyProbe,
  type ClaimedJob,
} from './fcm.ts';

const job: ClaimedJob = {
  job_id: 'j1',
  notification_id: '11111111-1111-4111-8111-111111111111',
  device_id: 'd1',
  token: 'device-token',
  locale: 'ar',
  target: 'offer',
  attempt: 1,
};

test('message carries generic localized text and identifiers only', () => {
  const m = buildMessage(job).message as Record<string, any>;
  assert.equal(m.token, 'device-token');
  assert.equal(m.notification.title, 'تذكير متابعة');
  assert.equal(m.notification.body, 'حان موعد متابعة عرض.');
  assert.deepEqual(m.data, { notification_id: job.notification_id, kind: 'follow_up', target: 'offer' });
  assert.equal(m.android.notification.channel_id, 'follow_up_reminders');
  for (const value of Object.values(m.data)) assert.equal(typeof value, 'string');
  const en = buildMessage({ ...job, locale: null, target: 'request' }).message as Record<string, any>;
  assert.equal(en.notification.title, 'Follow-up reminder');
  assert.equal(en.notification.body, 'A request is due for follow-up.');
});

test('FCM responses map to queue outcomes', () => {
  assert.deepEqual(classify(200, { name: 'projects/p/messages/1' }, null), { kind: 'sent', messageId: 'projects/p/messages/1' });
  const unregistered = { error: { status: 'NOT_FOUND', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } };
  assert.equal(classify(404, unregistered, null).kind, 'invalid_token');
  const mismatch = { error: { status: 'PERMISSION_DENIED', details: [{ errorCode: 'SENDER_ID_MISMATCH' }] } };
  // Our configuration or message is wrong: the job fails, the device stays.
  assert.deepEqual(classify(403, mismatch, null), { kind: 'failed', error: 'sender_id_mismatch' });
  assert.deepEqual(classify(400, { error: { status: 'INVALID_ARGUMENT' } }, null), { kind: 'failed', error: 'invalid_argument' });
  // Only FCM's "token gone" answer removes the device.
  const unregistered400 = { error: { status: 'INVALID_ARGUMENT', details: [{ errorCode: 'UNREGISTERED' }] } };
  assert.equal(classify(400, unregistered400, null).kind, 'invalid_token');
  assert.deepEqual(classify(429, {}, '120'), { kind: 'retry', error: 'quota_exceeded', retryAfterSeconds: 120 });
  assert.deepEqual(classify(503, null, null), { kind: 'retry', error: 'http_503', retryAfterSeconds: null });
  assert.equal(classify(401, {}, null).kind, 'auth');
  assert.equal(classify(403, { error: { status: 'PERMISSION_DENIED' } }, null).kind, 'failed');
});

test('the expected Firebase project is the Android app\'s project', async () => {
  const { readFileSync } = await import('node:fs');
  const gs = JSON.parse(readFileSync('android/app/google-services.json', 'utf8'));
  assert.equal(EXPECTED_FIREBASE_PROJECT, gs.project_info.project_id);
});

test('the FCM API probe never targets a real device and reads FCM answers', () => {
  const probe = validateOnlyProbe() as { validate_only: boolean; message: { token: string } };
  assert.equal(probe.validate_only, true);
  assert.equal(probe.message.token, 'bw-fcm-api-check-not-a-real-token');
  assert.equal(probeApiState(400), 'enabled');
  assert.equal(probeApiState(404), 'enabled');
  assert.equal(probeApiState(403), 'disabled_or_denied');
  assert.equal(probeApiState(401), 'unauthorized');
  assert.equal(probeApiState(500), 'unknown');
});

test('error codes never carry free text', () => {
  assert.equal(errorCode('Token: abc DEF!', 'x'), 'token_abc_def');
  assert.equal(errorCode('', 'fallback'), 'fallback');
  assert.match(errorCode('A'.repeat(200), 'x'), /^[a-z0-9_]{1,64}$/);
});

test('shared secret comparison', () => {
  assert.equal(sameSecret('abc', 'abc'), true);
  assert.equal(sameSecret('abc', 'abd'), false);
  assert.equal(sameSecret('abc', 'abcd'), false);
  assert.equal(sameSecret(null, 'abc'), false);
  assert.equal(sameSecret('abc', undefined), false);
});

test('service account JWT is RS256-signed and verifiable', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  const account = parseServiceAccount(JSON.stringify({
    project_id: 'broker-wallet', client_email: 'svc@example.iam.gserviceaccount.com', private_key: pem,
  }));
  const jwt = await signedAssertion(account, 1_700_000_000);
  const [h, c, s] = jwt.split('.');
  const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assert.equal(claims.exp - claims.iat, 3600);
  const ok = createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, Buffer.from(s, 'base64url'));
  assert.equal(ok, true);
  assert.throws(() => parseServiceAccount(''), /fcm_service_account_missing/);
  assert.throws(() => parseServiceAccount('{}'), /fcm_service_account_invalid/);
});
