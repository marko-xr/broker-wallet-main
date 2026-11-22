-- SOURCE ONLY. Removes exactly what 20261122120000_phone_signup_policy.sql
-- created, and nothing else. Run only with the owner's approval, as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_signup_policy_rollback.sql
--
-- BEFORE RUNNING: if the Before User Created hook is enabled in
-- Supabase Dashboard -> Authentication -> Hooks, disable it first. Dropping the
-- function while the hook still points at it makes every sign-up fail,
-- email included.
--
-- No other table, function, trigger, policy, grant or row is touched. The two
-- dropped tables hold only the phone sign-up mode and allowlist.
--
-- If the migration was applied with `supabase db push`, its history entry is
-- corrected afterwards as a separate owner step:
--   supabase migration repair --status reverted 20261122120000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.phone_auth_policy') is null
     or to_regclass('public.phone_auth_allowlist') is null
     or to_regprocedure('public.before_user_created_phone_policy(jsonb)') is null then
    raise exception 'phone signup policy rollback preflight failed: objects not present';
  end if;
end;
$preflight$;

drop function public.before_user_created_phone_policy(jsonb);
drop table public.phone_auth_allowlist;
drop table public.phone_auth_policy;

do $postflight$
begin
  if to_regclass('public.phone_auth_policy') is not null
     or to_regclass('public.phone_auth_allowlist') is not null
     or to_regprocedure('public.before_user_created_phone_policy(jsonb)') is not null then
    raise exception 'phone signup policy rollback postflight failed';
  end if;
end;
$postflight$;

select 'phone_signup_policy_rollback: DONE' as result;
commit;
