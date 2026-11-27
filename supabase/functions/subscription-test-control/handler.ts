// The Staging-only subscription test control.
//
// Refuses before doing anything unless this deployment is declared Staging and
// is not the production project. The account is ALWAYS the one in the caller's
// verified token: a body naming any account, plan or extra field is refused.
// The database then repeats the decision (staging marker + allowlist).

export const PRODUCTION_PROJECT_REF = "rbvcnvqpdqrhywcgxkne";

export const ALLOWED_ACTIONS = new Set([
  "status",
  "plus_on",
  "plus_off",
  "auto_renew_off",
  "expired",
  "reset_usage",
]);

export interface TestControlDeps {
  deploymentEnvironment: string;
  supabaseUrl: string;
  /** The account of a valid user token, or null. Checked by Supabase Auth. */
  verifyUser: (token: string) => Promise<string | null>;
  /** Whether that token belongs to the account's current app session. */
  isCurrentSession: (token: string) => Promise<boolean>;
  /** Calls public.staging_test_control with the service role. */
  control: (userId: string, action: string) => Promise<Record<string, unknown>>;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

const refuse = (status: number, code: string) => json(status, { ok: false, code });

export function isStagingDeployment(environment: string, supabaseUrl: string): boolean {
  return environment === "staging" &&
    supabaseUrl.startsWith("https://") &&
    !supabaseUrl.includes(PRODUCTION_PROJECT_REF);
}

export async function handleTestControl(request: Request, deps: TestControlDeps): Promise<Response> {
  if (!isStagingDeployment(deps.deploymentEnvironment, deps.supabaseUrl)) {
    return refuse(403, "not_staging");
  }
  if (request.method !== "POST") return refuse(405, "method_not_allowed");

  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!token) return refuse(401, "unauthenticated");
  const userId = await deps.verifyUser(token).catch(() => null);
  if (!userId) return refuse(401, "unauthenticated");
  if (!(await deps.isCurrentSession(token).catch(() => false))) {
    return refuse(403, "session_superseded");
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return refuse(400, "invalid_request");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return refuse(400, "invalid_request");
  }
  const keys = Object.keys(body);
  const action = (body as Record<string, unknown>).action;
  if (keys.length !== 1 || keys[0] !== "action" || typeof action !== "string" || !ALLOWED_ACTIONS.has(action)) {
    return refuse(400, "invalid_request");
  }

  try {
    const result = await deps.control(userId, action);
    if (result.ok !== true) return refuse(403, String(result.code ?? "refused"));
    return json(200, { ok: true, state: result.state });
  } catch (error) {
    const code = (error as { code?: unknown })?.code;
    return code === "PBT01" ? refuse(403, "not_staging") : refuse(503, "unavailable");
  }
}
