// Pure FCM HTTP v1 helpers for the push-dispatch Edge Function.
// No Deno or npm imports: the same file runs under Deno (Supabase) and under
// Node's test runner (`node --test supabase/functions/push-dispatch`).

export type Target = 'request' | 'offer';

export interface ClaimedJob {
  job_id: string;
  notification_id: string;
  device_id: string;
  token: string;
  locale: string | null;
  target: Target;
  attempt: number;
}

export type Outcome =
  | { kind: 'sent'; messageId: string }
  | { kind: 'retry'; error: string; retryAfterSeconds: number | null }
  | { kind: 'invalid_token'; error: string }
  | { kind: 'failed'; error: string }
  | { kind: 'auth'; error: string };

/**
 * Lock-screen text. Deliberately generic: no client name, phone, price,
 * location or record title ever leaves the database in a push.
 */
const TEXT = {
  en: {
    title: 'Follow-up reminder',
    request: 'A request is due for follow-up.',
    offer: 'An offer is due for follow-up.',
  },
  ar: {
    title: 'تذكير متابعة',
    request: 'حان موعد متابعة طلب.',
    offer: 'حان موعد متابعة عرض.',
  },
} as const;

export const ANDROID_CHANNEL_ID = 'follow_up_reminders';

export function buildMessage(job: ClaimedJob): Record<string, unknown> {
  const lang = job.locale === 'ar' ? 'ar' : 'en';
  const text = TEXT[lang];
  return {
    message: {
      token: job.token,
      notification: {
        title: text.title,
        body: job.target === 'offer' ? text.offer : text.request,
      },
      // Identifiers only. The app re-reads the inbox under RLS after the
      // user is signed in; a push never grants access to anything.
      data: {
        notification_id: job.notification_id,
        kind: 'follow_up',
        target: job.target,
      },
      android: {
        priority: 'HIGH',
        ttl: '86400s',
        notification: {
          channel_id: ANDROID_CHANNEL_ID,
          tag: job.notification_id,
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    },
  };
}

/**
 * A `validate_only` request to a token that cannot exist. FCM checks the API,
 * the credentials and the message without delivering anything to anyone.
 */
export function validateOnlyProbe(): Record<string, unknown> {
  return {
    validate_only: true,
    message: {
      token: 'bw-fcm-api-check-not-a-real-token',
      notification: { title: 'check', body: 'check' },
    },
  };
}

export type ApiState = 'enabled' | 'disabled_or_denied' | 'unauthorized' | 'unknown';

/**
 * Reads the probe's answer. 400/404 mean FCM processed the request and only
 * rejected the fake token: the API is enabled and the key is authorized.
 */
export function probeApiState(status: number): ApiState {
  if (status === 400 || status === 404 || (status >= 200 && status < 300)) return 'enabled';
  if (status === 403) return 'disabled_or_denied';
  if (status === 401) return 'unauthorized';
  return 'unknown';
}

/** A fixed lower-case code; never a provider message or a token. */
export function errorCode(value: string | null | undefined, fallback: string): string {
  const code = (value ?? '').toLowerCase().replace(/[^a-z0-9_]/g, '_').replace(/_+/g, '_')
    .replace(/^_|_$/g, '').slice(0, 64);
  return code.length > 0 ? code : fallback;
}

function retryAfter(header: string | null): number | null {
  if (!header) return null;
  const seconds = Number(header);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.min(Math.ceil(seconds), 3600);
  const date = Date.parse(header);
  if (Number.isFinite(date)) {
    return Math.min(Math.max(Math.ceil((date - Date.now()) / 1000), 1), 3600);
  }
  return null;
}

/** FCM v1 error details carry `errorCode` in a google.firebase.fcm type. */
function fcmErrorCode(body: unknown): string | null {
  const error = (body as { error?: { status?: string; details?: unknown[] } })?.error;
  for (const detail of error?.details ?? []) {
    const code = (detail as { errorCode?: string })?.errorCode;
    if (typeof code === 'string') return code;
  }
  return typeof error?.status === 'string' ? error.status : null;
}

/**
 * Maps an FCM v1 `messages:send` response to what the queue should do.
 * https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
 */
export function classify(status: number, body: unknown, retryAfterHeader: string | null): Outcome {
  if (status >= 200 && status < 300) {
    const name = (body as { name?: unknown })?.name;
    return { kind: 'sent', messageId: typeof name === 'string' ? name.slice(0, 200) : '' };
  }
  const code = fcmErrorCode(body);
  // Only FCM's own "this token is gone" answer removes a device. A sender or
  // argument error is OUR configuration or message: deleting the device
  // would silently cut a valid phone off.
  if (code === 'SENDER_ID_MISMATCH') {
    return { kind: 'failed', error: 'sender_id_mismatch' };
  }
  if (status === 404 || code === 'UNREGISTERED') {
    return { kind: 'invalid_token', error: errorCode(code, 'unregistered') };
  }
  if (status === 401) return { kind: 'auth', error: 'http_401' };
  if (status === 429 || code === 'QUOTA_EXCEEDED') {
    return { kind: 'retry', error: 'quota_exceeded', retryAfterSeconds: retryAfter(retryAfterHeader) };
  }
  if (status >= 500 || code === 'UNAVAILABLE' || code === 'INTERNAL') {
    return { kind: 'retry', error: errorCode(code, `http_${status}`), retryAfterSeconds: retryAfter(retryAfterHeader) };
  }
  // INVALID_ARGUMENT (400) can mean a bad token or a bad message; it is a
  // permanent failure for this job, but the device is kept. A device whose
  // token is really gone is removed by FCM's UNREGISTERED answer later.
  return { kind: 'failed', error: errorCode(code, `http_${status}`) };
}

// --- OAuth 2.0 service-account token (RS256 JWT bearer grant) --------------

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

/** The Firebase project of the Android app (android/app/google-services.json). */
export const EXPECTED_FIREBASE_PROJECT = 'broker-wallet';

export function parseServiceAccount(json: string | undefined | null): ServiceAccount {
  if (!json) throw new Error('fcm_service_account_missing');
  const parsed = JSON.parse(json) as Partial<ServiceAccount>;
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error('fcm_service_account_invalid');
  }
  return parsed as ServiceAccount;
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\n|\s/g, '');
  const binary = atob(body);
  const out = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export async function signedAssertion(account: ServiceAccount, nowSeconds: number): Promise<string> {
  const encoder = new TextEncoder();
  const header = base64Url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64Url(encoder.encode(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(`${header}.${claims}`)),
  );
  return `${header}.${claims}.${base64Url(signature)}`;
}

/** Constant-time comparison for the scheduler's shared secret. */
export function sameSecret(a: string | null, b: string | null | undefined): boolean {
  if (!a || !b) return false;
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}
