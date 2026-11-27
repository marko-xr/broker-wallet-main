import { assertEquals } from "jsr:@std/assert@1";
import { handleTestControl, isStagingDeployment, TestControlDeps } from "./handler.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const STAGING = "https://abcdefghijklmnopqrst.supabase.co";

function deps(calls: [string, string][], over: Partial<TestControlDeps> = {}): TestControlDeps {
  return {
    deploymentEnvironment: "staging",
    supabaseUrl: STAGING,
    verifyUser: (token) => Promise.resolve(token === "good" ? USER : null),
    isCurrentSession: () => Promise.resolve(true),
    control: (userId, action) => {
      calls.push([userId, action]);
      return Promise.resolve({ ok: true, state: { plan: "plus" } });
    },
    ...over,
  };
}

const call = (body: unknown, token: string | null = "good", method = "POST") =>
  new Request("https://x.test/subscription-test-control", {
    method,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

Deno.test("only a declared Staging deployment off the production project qualifies", () => {
  assertEquals(isStagingDeployment("staging", STAGING), true);
  assertEquals(isStagingDeployment("production", STAGING), false);
  assertEquals(isStagingDeployment("", STAGING), false);
  assertEquals(isStagingDeployment("staging", "https://rbvcnvqpdqrhywcgxkne.supabase.co"), false);
  assertEquals(isStagingDeployment("staging", "http://abcdefghijklmnopqrst.supabase.co"), false);
});

Deno.test("production refuses even a valid user, before reading anything", async () => {
  const calls: [string, string][] = [];
  let verified = false;
  const response = await handleTestControl(
    call({ action: "plus_on" }),
    deps(calls, {
      supabaseUrl: "https://rbvcnvqpdqrhywcgxkne.supabase.co",
      verifyUser: () => {
        verified = true;
        return Promise.resolve(USER);
      },
    }),
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "not_staging");
  assertEquals(verified, false);
  assertEquals(calls.length, 0);
});

Deno.test("a flag alone cannot make the production project Staging", async () => {
  const calls: [string, string][] = [];
  const response = await handleTestControl(
    call({ action: "plus_on" }),
    deps(calls, { deploymentEnvironment: "staging", supabaseUrl: "https://rbvcnvqpdqrhywcgxkne.supabase.co" }),
  );
  assertEquals(response.status, 403);
  assertEquals(calls.length, 0);
});

Deno.test("no token or a bad token is refused", async () => {
  const calls: [string, string][] = [];
  assertEquals((await handleTestControl(call({ action: "plus_on" }, null), deps(calls))).status, 401);
  assertEquals((await handleTestControl(call({ action: "plus_on" }, "bad"), deps(calls))).status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("a replaced session is refused", async () => {
  const calls: [string, string][] = [];
  const response = await handleTestControl(
    call({ action: "plus_on" }),
    deps(calls, { isCurrentSession: () => Promise.resolve(false) }),
  );
  assertEquals(response.status, 403);
  assertEquals(calls.length, 0);
});

Deno.test("the body cannot name an account, a plan or anything extra", async () => {
  const calls: [string, string][] = [];
  for (
    const body of [
      { action: "plus_on", user_id: "22222222-2222-4222-8222-222222222222" },
      { action: "plus_on", plan: "plus" },
      { plan: "plus" },
      { action: "grant_real_plus" },
      { action: 1 },
      ["plus_on"],
      null,
    ]
  ) {
    assertEquals((await handleTestControl(call(body), deps(calls))).status, 400);
  }
  assertEquals(calls.length, 0);
});

Deno.test("the action always applies to the token's own account", async () => {
  const calls: [string, string][] = [];
  const response = await handleTestControl(call({ action: "plus_on" }), deps(calls));
  assertEquals(response.status, 200);
  assertEquals(calls, [[USER, "plus_on"]]);
});

Deno.test("an account outside the allowlist is refused", async () => {
  const response = await handleTestControl(
    call({ action: "plus_on" }),
    deps([], { control: () => Promise.resolve({ ok: false, code: "not_allowlisted" }) }),
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "not_allowlisted");
});

Deno.test("a database without a staging marker refuses", async () => {
  const response = await handleTestControl(
    call({ action: "plus_on" }),
    deps([], { control: () => Promise.reject({ code: "PBT01" }) }),
  );
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "not_staging");
});

Deno.test("only POST is accepted", async () => {
  assertEquals((await handleTestControl(call(null, "good", "GET"), deps([]))).status, 405);
});
