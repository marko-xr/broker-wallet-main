// Builds the Google Play dependencies from function secrets. Missing or malformed
// configuration returns null, so every Play route stays closed.

import { GooglePlayClient } from "./google_play.ts";
import type { PlayConfig } from "./google_play.ts";
import { parseServiceAccount, publisherTokenSource } from "./google_auth.ts";
import type { PlayDeps } from "./play_service.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

export function playConfigFromEnv(): PlayConfig | null {
  const packageName = env("GOOGLE_PLAY_PACKAGE_NAME");
  const productId = env("GOOGLE_PLAY_PRODUCT_ID");
  try {
    const basePlanCycles = JSON.parse(env("GOOGLE_PLAY_BASE_PLANS") || "null");
    if (!packageName || !productId || typeof basePlanCycles !== "object" || basePlanCycles === null) {
      return null;
    }
    const cycles = Object.values(basePlanCycles);
    if (cycles.length === 0 || cycles.some((c) => c !== "monthly" && c !== "annual")) return null;
    return { packageName, productId, basePlanCycles };
  } catch {
    return null;
  }
}

export function playDepsFromEnv(rpc: PlayDeps["rpc"]): PlayDeps | null {
  const config = playConfigFromEnv();
  const account = parseServiceAccount(env("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"));
  const vaultKey = env("BILLING_TOKEN_KEY");
  if (!config || !account || !vaultKey) return null;
  return {
    client: new GooglePlayClient(config.packageName, publisherTokenSource(account)),
    config,
    vaultKey,
    rpc,
    now: Date.now,
  };
}

export function serviceRpc(): PlayDeps["rpc"] {
  const supabaseUrl = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  return async (name, args) => {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(args),
    });
    if (!response.ok) throw new Error("rpc_failed");
    const body = await response.text();
    return body ? JSON.parse(body) : null;
  };
}
