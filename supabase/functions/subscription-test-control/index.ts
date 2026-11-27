// SOURCE ONLY. Deploy to an isolated Staging project, never to production, with
// BW_DEPLOYMENT_ENV=staging. The handler refuses on any other deployment.

import { handleTestControl } from "./handler.ts";

Deno.serve((request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  return handleTestControl(request, {
    deploymentEnvironment: Deno.env.get("BW_DEPLOYMENT_ENV") ?? "",
    supabaseUrl,
    verifyUser: async (token) => {
      const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
        headers: { apikey: anonKey, authorization: `Bearer ${token}` },
      });
      if (!response.ok) return null;
      const user = await response.json();
      return typeof user?.id === "string" ? user.id : null;
    },
    isCurrentSession: async (token) => {
      const response = await fetch(`${supabaseUrl}/rest/v1/rpc/is_current_app_session`, {
        method: "POST",
        headers: {
          apikey: anonKey,
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: "{}",
      });
      return response.ok && (await response.json()) === true;
    },
    control: async (userId, action) => {
      const response = await fetch(`${supabaseUrl}/rest/v1/rpc/staging_test_control`, {
        method: "POST",
        headers: {
          apikey: serviceKey,
          authorization: `Bearer ${serviceKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ p_user: userId, p_action: action }),
      });
      const body = await response.json().catch(() => null);
      if (!response.ok) throw { code: body?.code };
      return body;
    },
  });
});
