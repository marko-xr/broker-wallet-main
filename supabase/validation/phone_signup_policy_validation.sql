-- SOURCE ONLY. Rollback-only validation of 20261122120000_phone_signup_policy.sql.
-- Run only with the owner's approval, as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_signup_policy_validation.sql
-- The migration is included inside ONE transaction that always ends in
-- ROLLBACK: nothing is created, no Auth setting or hook is touched, nothing is
-- called over the network, and no phone number of a real person is used.
--
-- On the hosted project postgres is not a member of supabase_auth_admin, so the
-- hook's decisions are exercised as postgres (the tables' owner, not subject to
-- RLS) and supabase_auth_admin's access is asserted from the catalog.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.phone_auth_policy') is not null
     or to_regclass('public.phone_auth_allowlist') is not null
     or to_regprocedure('public.before_user_created_phone_policy(jsonb)') is not null
     or not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')
     or not has_schema_privilege('supabase_auth_admin', 'public', 'usage') then
    raise exception 'phone signup policy validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20261122120000_phone_signup_policy.sql

do $grants$
declare
  v_role text;
begin
  foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(v_role, 'public.before_user_created_phone_policy(jsonb)', 'execute')
       or has_table_privilege(v_role, 'public.phone_auth_policy', 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege(v_role, 'public.phone_auth_allowlist', 'select,insert,update,delete,truncate,references,trigger') then
      raise exception '% can reach the phone signup policy', v_role;
    end if;
  end loop;
  if not has_function_privilege('supabase_auth_admin', 'public.before_user_created_phone_policy(jsonb)', 'execute')
     or not has_table_privilege('supabase_auth_admin', 'public.phone_auth_policy', 'select')
     or not has_table_privilege('supabase_auth_admin', 'public.phone_auth_allowlist', 'select')
     or has_table_privilege('supabase_auth_admin', 'public.phone_auth_policy', 'insert,update,delete,truncate')
     or has_table_privilege('supabase_auth_admin', 'public.phone_auth_allowlist', 'insert,update,delete,truncate') then
    raise exception 'supabase_auth_admin access is not exactly execute + read';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public'
         and tablename in ('phone_auth_policy', 'phone_auth_allowlist')
         and cmd = 'SELECT'
         and roles = array['supabase_auth_admin']::name[]) <> 2
     or (select count(*) from pg_policies
          where schemaname = 'public'
            and tablename in ('phone_auth_policy', 'phone_auth_allowlist')) <> 2
     or not (select bool_and(relrowsecurity) from pg_class
              where oid in ('public.phone_auth_policy'::regclass, 'public.phone_auth_allowlist'::regclass)) then
    raise exception 'RLS or the supabase_auth_admin read policies are not as designed';
  end if;
  if exists (select 1 from pg_proc
              where oid = 'public.before_user_created_phone_policy(jsonb)'::regprocedure
                and (prosecdef or provolatile <> 's')) then
    raise exception 'the hook must be SECURITY INVOKER and STABLE';
  end if;
end;
$grants$;

do $decisions$
declare
  v_refused constant jsonb := '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb;
  -- Fictional numbers in the UAE mobile shape; no real person's number.
  v_listed constant text := '971500000001';
  v_unlisted constant text := '971500000002';
begin
  if (select count(*) from public.phone_auth_policy) <> 1
     or (select mode from public.phone_auth_policy) <> 'closed' then
    raise exception 'the policy must start as exactly one closed row';
  end if;

  -- Table rules: one policy row, valid modes, UAE mobile numbers only.
  begin
    insert into public.phone_auth_policy (singleton, mode) values (false, 'open');
    raise exception 'a second policy row was accepted';
  exception when check_violation then null;
  end;
  begin
    update public.phone_auth_policy set mode = 'public';
    raise exception 'an unknown mode was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.phone_auth_allowlist (phone_e164) values ('+447700900123');
    raise exception 'a non-UAE allowlist number was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.phone_auth_allowlist (phone_e164) values (v_listed);
    raise exception 'an allowlist number without + was accepted';
  exception when check_violation then null;
  end;

  -- closed
  if public.before_user_created_phone_policy('{"user":{"email":"v@example.test","phone":""}}') <> '{}'::jsonb
     or public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', '+' || v_listed))) <> v_refused
     or public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', v_listed))) <> v_refused then
    raise exception 'closed mode is not enforced';
  end if;

  -- allowlist
  update public.phone_auth_policy set mode = 'allowlist';
  insert into public.phone_auth_allowlist (phone_e164) values ('+' || v_listed);
  if public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', v_listed))) <> '{}'::jsonb
     or public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', '+' || v_listed))) <> '{}'::jsonb
     or public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', v_unlisted))) <> v_refused then
    raise exception 'allowlist mode is not enforced';
  end if;

  -- open
  update public.phone_auth_policy set mode = 'open';
  if public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', v_unlisted))) <> '{}'::jsonb
     or public.before_user_created_phone_policy('{"user":{"phone":"+447700900123"}}') <> v_refused
     or public.before_user_created_phone_policy('{"user":{"phone":"97141234567"}}') <> v_refused
     or public.before_user_created_phone_policy('{"user":{"phone":"97150000000"}}') <> v_refused
     or public.before_user_created_phone_policy('{"user":{"phone":"9715000000011"}}') <> v_refused
     or public.before_user_created_phone_policy(jsonb_build_object('user',
          jsonb_build_object('phone', v_unlisted, 'user_metadata', '{"name":"x"}'::jsonb))) <> v_refused
     or public.before_user_created_phone_policy(jsonb_build_object('user',
          jsonb_build_object('phone', v_unlisted, 'user_metadata', '{}'::jsonb))) <> '{}'::jsonb
     or public.before_user_created_phone_policy('{"user":{"email":"v@example.test","phone":"","user_metadata":{"name":"V"}}}') <> '{}'::jsonb then
    raise exception 'open mode or the number/metadata rules are not enforced';
  end if;

  -- Fail closed for phone, never for email.
  alter table public.phone_auth_policy rename to phone_auth_policy_unreadable;
  if public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', v_unlisted))) <> v_refused
     or public.before_user_created_phone_policy('{"user":{"email":"v@example.test","phone":""}}') <> '{}'::jsonb then
    raise exception 'the hook does not fail closed for phone only';
  end if;
  alter table public.phone_auth_policy_unreadable rename to phone_auth_policy;
end;
$decisions$;

select 'phone_signup_policy_validation: PASS' as result;
rollback;
