// push-dispatch: turns due follow-up reminders into inbox rows, then delivers
// queued pushes through FCM HTTP v1 to the account's CURRENT device only.
//
// Called every minute by pg_cron (supabase/deploy/notifications_n2_schedule.sql)
// with a single-use `x-dispatch-nonce` header (see migration
// 20261121090000_push_dispatch_nonce). Manual checks use the static
// `x-dispatch-secret`, which never goes through pg_net. Deployed with
// verify_jwt = false because the caller is the scheduler, not a user; the
// caller is checked here, before anything else.
//
// Request body:
//   {}                 normal run: fire due reminders, claim, send, complete
//   {"mode":"check"}   configuration check only: verifies the service account
//                      belongs to the expected Firebase project, that Google
//                      issues an FCM access token, and (FCM `validate_only` to
//                      a fake token) that the FCM v1 API is enabled for it.
//                      Touches no reminder, no job, no device, delivers nothing.
//
// Secrets (Supabase Edge Function secrets, never Flutter, never Git):
//   PUSH_DISPATCH_SECRET      random string for manual check calls only
//   FCM_SERVICE_ACCOUNT_JSON  Firebase service account key (project broker-wallet)
// Provided by the platform: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
import {
  buildMessage,
  classify,
  type ClaimedJob,
  EXPECTED_FIREBASE_PROJECT,
  type Outcome,
  parseServiceAccount,
  probeApiState,
  sameSecret,
  type ServiceAccount,
  signedAssertion,
  validateOnlyProbe,
} from './fcm.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const DISPATCH_SECRET = Deno.env.get('PUSH_DISPATCH_SECRET');
const BATCH = 50;
const CONCURRENCY = 8;
const TIMEOUT_MS = 10_000;
const NONCE_SHAPE = /^[0-9a-f]{64}$/;

let cachedToken: { value: string; expiresAt: number } | null = null;
let account: ServiceAccount | null = null;

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  });
}

/** Fixed code for logs and responses; never a message, token or payload. */
function code(error: unknown): string {
  return error instanceof Error
    ? error.message.replace(/[^a-z0-9_]/g, '_').slice(0, 64)
    : 'unknown';
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) {
    // Status only: a PostgREST body can echo arguments (tokens).
    throw new Error(`rpc_${name}_http_${response.status}`);
  }
  return await response.json() as T;
}

/** Loads the service account and refuses one from another Firebase project. */
function serviceAccount(): ServiceAccount {
  account ??= parseServiceAccount(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON'));
  if (account.project_id !== EXPECTED_FIREBASE_PROJECT) {
    throw new Error('fcm_project_mismatch');
  }
  return account;
}

async function accessToken(force = false): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (!force && cachedToken && cachedToken.expiresAt - 120 > now) return cachedToken.value;
  const sa = serviceAccount();
  const assertion = await signedAssertion(sa, now);
  const response = await fetch(sa.token_uri ?? 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`oauth_http_${response.status}`);
  const body = await response.json() as { access_token?: string; expires_in?: number };
  if (!body.access_token) throw new Error('oauth_no_token');
  cachedToken = { value: body.access_token, expiresAt: now + (body.expires_in ?? 3600) };
  return cachedToken.value;
}

async function send(job: ClaimedJob, retriedAuth = false): Promise<Outcome> {
  let response: Response;
  try {
    const token = await accessToken(retriedAuth);
    response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(buildMessage(job)),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      },
    );
  } catch (_) {
    return { kind: 'retry', error: 'network', retryAfterSeconds: null };
  }
  let body: unknown = null;
  try {
    body = await response.json();
  } catch (_) {
    body = null;
  }
  const outcome = classify(response.status, body, response.headers.get('retry-after'));
  if (outcome.kind === 'auth' && !retriedAuth) return send(job, true);
  return outcome;
}

async function complete(job: ClaimedJob, outcome: Outcome): Promise<void> {
  const args: Record<string, unknown> = { p_job_id: job.job_id };
  switch (outcome.kind) {
    case 'sent':
      Object.assign(args, { p_outcome: 'sent', p_provider_message_id: outcome.messageId });
      break;
    case 'retry':
      Object.assign(args, {
        p_outcome: 'retry', p_error: outcome.error,
        p_retry_after_seconds: outcome.retryAfterSeconds,
      });
      break;
    case 'auth':
      Object.assign(args, { p_outcome: 'retry', p_error: outcome.error });
      break;
    case 'invalid_token':
      Object.assign(args, { p_outcome: 'invalid_token', p_error: outcome.error, p_device_id: job.device_id });
      break;
    case 'failed':
      Object.assign(args, { p_outcome: 'failed', p_error: outcome.error });
      break;
  }
  await rpc('complete_push_delivery_job', args);
}

/**
 * Who may run the dispatcher:
 *   - the scheduler, with a single-use `x-dispatch-nonce` it got from
 *     public.issue_push_dispatch_nonce() a moment earlier (consumed here, so
 *     a copy read from pg_net's queue is worthless afterwards);
 *   - the owner/agent for manual checks, with the static `x-dispatch-secret`
 *     (never sent through pg_net).
 * A malformed nonce is refused without touching the database.
 */
async function authorized(request: Request): Promise<boolean> {
  if (sameSecret(request.headers.get('x-dispatch-secret'), DISPATCH_SECRET)) return true;
  const nonce = request.headers.get('x-dispatch-nonce');
  if (!nonce || !NONCE_SHAPE.test(nonce)) return false;
  try {
    return (await rpc<boolean>('consume_push_dispatch_nonce', { p_nonce: nonce })) === true;
  } catch (_) {
    return false;
  }
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  if (!(await authorized(request))) {
    return new Response(null, { status: 401 });
  }

  let mode = 'run';
  try {
    const body = await request.json() as { mode?: unknown };
    if (body?.mode === 'check') mode = 'check';
  } catch (_) {
    // An empty or non-JSON body is a normal run.
  }

  // Configuration first: a wrong or missing key stops here, before any
  // reminder is fired or any job is leased.
  try {
    serviceAccount();
    if (mode === 'check') {
      const token = await accessToken(true);
      const probe = await fetch(
        `https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(validateOnlyProbe()),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        },
      );
      await probe.body?.cancel();
      const fcmApi = probeApiState(probe.status);
      return json({
        ok: fcmApi === 'enabled', mode, project: EXPECTED_FIREBASE_PROJECT,
        oauth: true, fcm_api: fcmApi, fcm_probe_status: probe.status,
      });
    }
  } catch (error) {
    const c = code(error);
    console.error(JSON.stringify({ event: 'push_dispatch_config_error', code: c }));
    return json({ ok: false, mode, code: c }, 500);
  }

  const counts = {
    fired: 0, claimed: 0, sent: 0, retry: 0, invalid_token: 0, failed: 0, complete_failed: 0,
  };
  try {
    counts.fired = await rpc<number>('fire_due_follow_up_reminders', { p_limit: 200 });
    const jobs = await rpc<ClaimedJob[]>('claim_push_delivery_jobs', {
      p_limit: BATCH, p_lease_seconds: 60,
    });
    counts.claimed = jobs.length;
    for (let i = 0; i < jobs.length; i += CONCURRENCY) {
      await Promise.all(jobs.slice(i, i + CONCURRENCY).map(async (job) => {
        const outcome = await send(job);
        const key = outcome.kind === 'auth' ? 'retry' : outcome.kind;
        counts[key] += 1;
        try {
          await complete(job, outcome);
        } catch (_) {
          // The job stays leased and is reclaimed after its lease; Android
          // replaces a repeated notification with the same tag, so a resend
          // never shows twice.
          counts.complete_failed += 1;
        }
      }));
    }
  } catch (error) {
    const c = code(error);
    console.error(JSON.stringify({ event: 'push_dispatch_error', code: c, ...counts }));
    return json({ ok: false, code: c, ...counts }, 500);
  }
  console.log(JSON.stringify({ event: 'push_dispatch', ...counts }));
  return json({ ok: true, ...counts });
});
