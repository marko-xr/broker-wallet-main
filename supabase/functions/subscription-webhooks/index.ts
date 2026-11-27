// Google Play notifications: POST /subscription-webhooks/google-play.
// Deploy with --no-verify-jwt: Pub/Sub holds no Supabase token. The route verifies
// Pub/Sub's own Google OIDC token instead.
// SOURCE ONLY: not deployed, and no Pub/Sub subscription points at it yet.

import { handleWebhook } from "./handler.ts";
import { googleKeyLoader, verifyPushToken } from "./google_auth.ts";
import { playDepsFromEnv, serviceRpc } from "./play_env.ts";

const loadKeys = googleKeyLoader();
const play = playDepsFromEnv(serviceRpc());

Deno.serve((request) =>
  handleWebhook(request, {
    play,
    verifyPush: (token) =>
      verifyPushToken(
        token,
        {
          audience: Deno.env.get("GOOGLE_PLAY_PUSH_AUDIENCE") ?? "",
          serviceAccountEmail: Deno.env.get("GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT") ?? "",
        },
        Math.floor(Date.now() / 1000),
        loadKeys,
      ),
  })
);
