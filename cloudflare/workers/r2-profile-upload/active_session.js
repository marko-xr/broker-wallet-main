/** Check the caller's already verified JWT against the database authority.
 * The RPC reads auth.uid() and session_id from that JWT; no client ID is sent.
 * A failed check or unavailable database never authorizes business data.
 */
export class ActiveSessionUnavailable extends Error {}

export async function isCurrentAppSession(authorization, env, fetchImpl = fetch) {
  try {
    const response = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/is_current_app_session`, {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: authorization,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!response.ok) throw new ActiveSessionUnavailable();
    const answer = await response.json();
    if (answer !== true && answer !== false) throw new ActiveSessionUnavailable();
    return answer;
  } catch (error) {
    if (error instanceof ActiveSessionUnavailable) throw error;
    throw new ActiveSessionUnavailable();
  }
}
