// Encrypts Google Play purchase tokens at rest with AES-256-GCM. The key is a
// function secret and never reaches the database or a client. The token's SHA-256
// is bound as additional data, so a ciphertext cannot be moved to another row.

const encoder = new TextEncoder();

function fromBase64(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

async function importKey(keyBase64: string): Promise<CryptoKey> {
  const raw = fromBase64(keyBase64);
  if (raw.length !== 32) throw new Error("vault_key_invalid");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function sealToken(keyBase64: string, token: string, tokenSha256: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: encoder.encode(tokenSha256) },
    await importKey(keyBase64),
    encoder.encode(token),
  );
  return `v1.${toBase64(iv)}.${toBase64(new Uint8Array(cipher))}`;
}

export async function openToken(keyBase64: string, sealed: string, tokenSha256: string): Promise<string> {
  const [version, iv, cipher] = sealed.split(".");
  if (version !== "v1" || !iv || !cipher) throw new Error("vault_format_invalid");
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64(iv), additionalData: encoder.encode(tokenSha256) },
    await importKey(keyBase64),
    fromBase64(cipher),
  );
  return new TextDecoder().decode(plain);
}
