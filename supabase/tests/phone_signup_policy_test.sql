-- Phone Auth B1: the Before User Created phone policy (20261122120000).
--
-- Run with `supabase test db` against the local stack. Everything runs as
-- postgres, the owner of the policy tables, so the hook's decisions are tested
-- here independently of RLS; the grants and the supabase_auth_admin SELECT
-- policies are asserted from the catalog. Nothing here enables the hook.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(44);

-- ---------------------------------------------------------------------------
-- Structure and defaults
-- ---------------------------------------------------------------------------

select has_table('public', 'phone_auth_policy', 'the phone sign-up policy table exists');
select has_table('public', 'phone_auth_allowlist', 'the phone sign-up allowlist exists');
select has_function('public', 'before_user_created_phone_policy', array['jsonb'],
  'the Before User Created hook function exists');

select is((select count(*) from public.phone_auth_policy), 1::bigint,
  'there is exactly one policy row');
select is((select mode from public.phone_auth_policy), 'closed',
  'phone sign-ups are closed by default');

select throws_ok($$ insert into public.phone_auth_policy (singleton, mode) values (true, 'open') $$,
  '23505', null, 'a second policy row cannot be added');
select throws_ok($$ insert into public.phone_auth_policy (singleton, mode) values (false, 'open') $$,
  '23514', null, 'the policy row is a singleton');
select throws_ok($$ update public.phone_auth_policy set mode = 'public' $$,
  '23514', null, 'only closed, allowlist and open are valid modes');
select throws_ok($$ insert into public.phone_auth_allowlist (phone_e164) values ('+447700900123') $$,
  '23514', null, 'the allowlist refuses a non-UAE number');
select throws_ok($$ insert into public.phone_auth_allowlist (phone_e164) values ('971501234567') $$,
  '23514', null, 'the allowlist stores numbers only as +9715XXXXXXXX');
select throws_ok($$ insert into public.phone_auth_allowlist (phone_e164) values ('+97141234567') $$,
  '23514', null, 'the allowlist refuses a UAE landline');

-- ---------------------------------------------------------------------------
-- Privileges, RLS and function properties
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.before_user_created_phone_policy(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.before_user_created_phone_policy(jsonb)', 'execute')
  and not has_function_privilege('service_role', 'public.before_user_created_phone_policy(jsonb)', 'execute'),
  'anon, authenticated and service_role cannot execute the hook');
select ok(has_function_privilege('supabase_auth_admin', 'public.before_user_created_phone_policy(jsonb)', 'execute'),
  'supabase_auth_admin can execute the hook');
select ok(not has_table_privilege('anon', 'public.phone_auth_policy', 'select,insert,update,delete,truncate,references,trigger')
  and not has_table_privilege('authenticated', 'public.phone_auth_policy', 'select,insert,update,delete,truncate,references,trigger')
  and not has_table_privilege('service_role', 'public.phone_auth_policy', 'select,insert,update,delete,truncate,references,trigger'),
  'clients and service_role have no access to the policy table');
select ok(not has_table_privilege('anon', 'public.phone_auth_allowlist', 'select,insert,update,delete,truncate,references,trigger')
  and not has_table_privilege('authenticated', 'public.phone_auth_allowlist', 'select,insert,update,delete,truncate,references,trigger')
  and not has_table_privilege('service_role', 'public.phone_auth_allowlist', 'select,insert,update,delete,truncate,references,trigger'),
  'clients and service_role have no access to the allowlist');
select ok(has_table_privilege('supabase_auth_admin', 'public.phone_auth_policy', 'select')
  and has_table_privilege('supabase_auth_admin', 'public.phone_auth_allowlist', 'select')
  and not has_table_privilege('supabase_auth_admin', 'public.phone_auth_policy', 'insert,update,delete,truncate')
  and not has_table_privilege('supabase_auth_admin', 'public.phone_auth_allowlist', 'insert,update,delete,truncate'),
  'supabase_auth_admin can only read both tables');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.phone_auth_policy'::regclass, 'public.phone_auth_allowlist'::regclass)),
  'row level security is enabled on both tables');
select is((select count(*) from pg_policies
            where schemaname = 'public'
              and tablename in ('phone_auth_policy', 'phone_auth_allowlist')),
  2::bigint, 'each table has exactly one policy');
select is((select count(*) from pg_policies
            where schemaname = 'public'
              and tablename in ('phone_auth_policy', 'phone_auth_allowlist')
              and cmd = 'SELECT'
              and roles = array['supabase_auth_admin']::name[]),
  2::bigint, 'both policies are SELECT-only for supabase_auth_admin');
select ok((select not p.prosecdef and p.provolatile = 's'
            from pg_proc p
           where p.oid = 'public.before_user_created_phone_policy(jsonb)'::regprocedure),
  'the hook is SECURITY INVOKER and STABLE (it never writes)');
select ok((select 'search_path=""' = any(p.proconfig)
            from pg_proc p
           where p.oid = 'public.before_user_created_phone_policy(jsonb)'::regprocedure),
  'the hook pins an empty search_path');

-- ---------------------------------------------------------------------------
-- Decisions: closed (default)
-- ---------------------------------------------------------------------------

select is(public.before_user_created_phone_policy('{"user":{"email":"a@example.test","phone":""}}'),
  '{}'::jsonb, 'closed: an email sign-up is allowed');
select is(public.before_user_created_phone_policy('{"user":{"email":"a@example.test"}}'),
  '{}'::jsonb, 'closed: a sign-up without a phone field is allowed');
select is(public.before_user_created_phone_policy('{"user":{"phone":"+971501234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'closed: a UAE mobile number with + is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'closed: a UAE mobile number without + is refused');

-- ---------------------------------------------------------------------------
-- Decisions: allowlist
-- ---------------------------------------------------------------------------

update public.phone_auth_policy set mode = 'allowlist';
insert into public.phone_auth_allowlist (phone_e164) values ('+971501234567');

select is(public.before_user_created_phone_policy('{"user":{"phone":"+971501234567"}}'),
  '{}'::jsonb, 'allowlist: a listed number with + is allowed');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567"}}'),
  '{}'::jsonb, 'allowlist: a listed number without + is allowed');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971509999999"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'allowlist: an unlisted UAE number is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567","user_metadata":{"name":"x"}}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'allowlist: a listed number carrying metadata is refused');

-- ---------------------------------------------------------------------------
-- Decisions: open
-- ---------------------------------------------------------------------------

update public.phone_auth_policy set mode = 'open';

select is(public.before_user_created_phone_policy('{"user":{"phone":"971559876543"}}'),
  '{}'::jsonb, 'open: a UAE mobile number is allowed');
select is(public.before_user_created_phone_policy('{"user":{"phone":"+447700900123"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a non-UAE number is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"97141234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a UAE landline is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"97150123456"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a number one digit short is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"9715012345678"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a number one digit long is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"+97150123456a"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a number with a letter is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"+971 501234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: a number with a space is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567","user_metadata":{"name":"x"}}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: metadata at creation is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567","user_metadata":[]}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'open: non-object metadata is refused');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567","user_metadata":{}}}'),
  '{}'::jsonb, 'open: empty metadata is allowed');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567","user_metadata":null}}'),
  '{}'::jsonb, 'open: null metadata is allowed');
select is(public.before_user_created_phone_policy('{"user":{"email":"a@example.test","phone":"","user_metadata":{"name":"A"}}}'),
  '{}'::jsonb, 'open: the metadata rule never applies to an email sign-up');

-- ---------------------------------------------------------------------------
-- Fail closed for phone, never for email
-- ---------------------------------------------------------------------------

delete from public.phone_auth_policy;
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'a missing policy row refuses a phone sign-up');

insert into public.phone_auth_policy (singleton, mode) values (true, 'open');
alter table public.phone_auth_policy rename to phone_auth_policy_unreadable;
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501234567"}}'),
  '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb,
  'an unreadable policy refuses a phone sign-up (fail closed)');
select is(public.before_user_created_phone_policy('{"user":{"email":"a@example.test","phone":""}}'),
  '{}'::jsonb, 'an unreadable policy never affects an email sign-up');
alter table public.phone_auth_policy_unreadable rename to phone_auth_policy;

select * from finish();
rollback;
