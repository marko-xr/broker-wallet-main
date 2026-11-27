// SOURCE ONLY: not deployed. Deploy with --no-verify-jwt: Tap and the scheduler
// hold no Supabase token, and every route authenticates its caller itself.

import { handleBilling } from "./handler.ts";
import { TapClient } from "./tap_client.ts";
import { playDepsFromEnv, serviceRpc } from "../subscription-webhooks/play_env.ts";

const env = (name: string) => Deno.env.get(name) ?? "";
const rpc = serviceRpc();
const play = playDepsFromEnv(rpc);

Deno.serve((request) => {
  const supabaseUrl = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY");
  const tapSecret = env("TAP_SECRET_KEY");

  return handleBilling(request, {
    play,
    reconcileSecret: env("SUBSCRIPTION_RECONCILE_SECRET"),
    verifyUser: async (token) => {
      const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
        headers: { apikey: anonKey, authorization: `Bearer ${token}` },
      });
      if (!response.ok) return null;
      const user = await response.json();
      if (typeof user?.id !== "string") return null;
      return {
        id: user.id,
        email: typeof user.email === "string" ? user.email : null,
        phone: typeof user.phone === "string" && user.phone ? `+${user.phone.replace(/^\+/, "")}` : null,
      };
    },
    isCurrentSession: async (token) => {
      const response = await fetch(`${supabaseUrl}/rest/v1/rpc/is_current_app_session`, {
        method: "POST",
        headers: { apikey: anonKey, authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: "{}",
      });
      return response.ok && (await response.json()) === true;
    },
    rpc,
    tap: tapSecret ? new TapClient(tapSecret) : null,
    tapSecret,
    tapPublicKey: env("TAP_PUBLIC_KEY"),
    tapMerchantId: env("TAP_MERCHANT_ID"),
    tapBillingEnabled: env("TAP_BILLING_ENABLED") === "true",
    tapRenewalsEnabled: env("TAP_RENEWALS_ENABLED") === "true",
    tapLiveMode: env("TAP_LIVE_MODE") === "true",
    tapReturnUrl: env("TAP_RETURN_URL"),
    tapWebhookUrl: `${supabaseUrl}/functions/v1/subscription-billing/tap/webhook`,
    allowedOrigins: env("BILLING_ALLOWED_ORIGINS").split(",").map((o) => o.trim()).filter(Boolean),
  });
});
