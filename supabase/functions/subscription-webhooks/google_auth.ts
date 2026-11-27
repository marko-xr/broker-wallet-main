// Google identity, using standard RS256 through WebCrypto:
// - verifies the OIDC token Pub/Sub attaches to each authenticated push;
// - signs the service-account assertion for the Android Publisher API.

export interface JwkSet {
  keys: (JsonWebKey & { kid?: string })[];
}

export interface PushIdentity {
  /** The push subscription's configured audience. */
  audience: string;
  /** The service account the push subscription authenticates as. */
  serviceAccountEmail: string;
}

const GOOGLE_ISSUERS = new Set(["accounts.google.com", "https://accounts.google.com"]);
const CLOCK_SKEW_SECONDS = 60;
const encoder = new TextEncoder();

function base64UrlToBytes(value: string): Uint8Array<ArrayBuffer> {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeJson(part: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(new TextDecoder().decode(base64UrlToBytes(part)));
    return typeof value === "object" && value !== null ? value : null;
  } catch {
    return null;
  }
}

/** True only for a valid, unexpired Google token for exactly this push identity. */
export async function verifyPushToken(
  token: string,
  identity: PushIdentity,
  nowSeconds: number,
  loadKeys: () => Promise<JwkSet>,
): Promise<boolean> {
  if (!identity.audience || !identity.serviceAccountEmail) return false;
  const parts = token.split(".");
  if (parts.length !== 3) return false;
  const header = decodeJson(parts[0]);
  const claims = decodeJson(parts[1]);
  if (!header || !claims || header.alg !== "RS256" || typeof header.kid !== "string") return false;
  if (
    !GOOGLE_ISSUERS.has(String(claims.iss)) ||
    claims.aud !== identity.audience ||
    claims.email !== identity.serviceAccountEmail ||
    claims.email_verified !== true ||
    typeof claims.exp !== "number" ||
    claims.exp + CLOCK_SKEW_SECONDS < nowSeconds ||
    (typeof claims.iat === "number" && claims.iat - CLOCK_SKEW_SECONDS > nowSeconds)
  ) {
    return false;
  }
  try {
    const jwk = (await loadKeys()).keys.find((key) => key.kid === header.kid);
    if (!jwk) return false;
    const key = await crypto.subtle.importKey(
      "jwk",
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      base64UrlToBytes(parts[2]),
      encoder.encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    return false;
  }
}

/** Google's published signing keys, cached for ten minutes. */
export function googleKeyLoader(send: typeof fetch = fetch, now: () => number = Date.now) {
  let cached: { keys: JwkSet; until: number } | null = null;
  return async (): Promise<JwkSet> => {
    if (cached && cached.until > now()) return cached.keys;
    const response = await send("https://www.googleapis.com/oauth2/v3/certs");
    if (!response.ok) throw new Error("google_keys_unavailable");
    const keys = await response.json() as JwkSet;
    cached = { keys, until: now() + 600_000 };
    return keys;
  };
}

export interface ServiceAccount {
  client_email: string;
  private_key: string;
}

export function parseServiceAccount(raw: string): ServiceAccount | null {
  try {
    const value = JSON.parse(raw);
    if (typeof value?.client_email !== "string" || typeof value?.private_key !== "string") return null;
    return { client_email: value.client_email, private_key: value.private_key };
  } catch {
    return null;
  }
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

const PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

/** Exchanges a signed assertion for an access token, cached until shortly before expiry. */
export function publisherTokenSource(
  account: ServiceAccount,
  send: typeof fetch = fetch,
  now: () => number = Date.now,
) {
  let cached: { token: string; until: number } | null = null;
  return async (): Promise<string> => {
    if (cached && cached.until > now()) return cached.token;
    const issued = Math.floor(now() / 1000);
    const head = bytesToBase64Url(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
    const claims = bytesToBase64Url(encoder.encode(JSON.stringify({
      iss: account.client_email,
      scope: PUBLISHER_SCOPE,
      aud: TOKEN_URL,
      iat: issued,
      exp: issued + 3600,
    })));
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      await importPrivateKey(account.private_key),
      encoder.encode(`${head}.${claims}`),
    );
    const response = await send(TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${head}.${claims}.${bytesToBase64Url(new Uint8Array(signature))}`,
      }),
    });
    if (!response.ok) throw new Error("google_token_unavailable");
    const body = await response.json();
    if (typeof body?.access_token !== "string") throw new Error("google_token_invalid");
    const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
    cached = { token: body.access_token, until: now() + Math.max(lifetime - 120, 60) * 1000 };
    return body.access_token;
  };
}
