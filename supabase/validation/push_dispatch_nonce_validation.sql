-- SOURCE ONLY. Rollback-only validation of 20261121090000_push_dispatch_nonce.sql.
-- Run only with the owner's approval, as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/push_dispatch_nonce_validation.sql
-- The migration is included inside ONE transaction that always ends in
-- ROLLBACK; nothing is created, called over the network or printed (no nonce
-- value appears in any result).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.push_dispatch_nonces') is not null
     or to_regprocedure('public.issue_push_dispatch_nonce()') is not null
     or to_regprocedure('public.fire_due_follow_up_reminders(integer)') is null
     or not pg_has_role('postgres', 'service_role', 'member') then
    raise exception 'nonce validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20261121090000_push_dispatch_nonce.sql

do $issue$
declare
  v_nonce text := public.issue_push_dispatch_nonce();
  v_nonce2 text := public.issue_push_dispatch_nonce();
begin
  if v_nonce !~ '^[0-9a-f]{64}$' or v_nonce = v_nonce2 then
    raise exception 'issue did not return two distinct 64-hex nonces';
  end if;
  if exists (select 1 from public.push_dispatch_nonces where nonce_hash in (v_nonce, v_nonce2))
     or (select count(*) from public.push_dispatch_nonces) <> 2 then
    raise exception 'a raw nonce is stored, or not exactly two hashes';
  end if;
  perform set_config('bw_validation.n1', v_nonce, true);
  perform set_config('bw_validation.n2', v_nonce2, true);
end;
$issue$;

set local role service_role;
do $service$
begin
  if not public.consume_push_dispatch_nonce(current_setting('bw_validation.n1')) then
    raise exception 'a fresh nonce was not accepted';
  end if;
  if public.consume_push_dispatch_nonce(current_setting('bw_validation.n1')) then
    raise exception 'a nonce was accepted twice';
  end if;
  if public.consume_push_dispatch_nonce('not-a-nonce')
     or public.consume_push_dispatch_nonce(null)
     or public.consume_push_dispatch_nonce(repeat('a', 64)) then
    raise exception 'a malformed or unknown nonce was accepted';
  end if;
  begin
    perform public.issue_push_dispatch_nonce();
    raise exception 'service_role could issue a nonce';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.push_dispatch_nonces;
    raise exception 'service_role could read the nonce table';
  exception when insufficient_privilege then null;
  end;
end;
$service$;
reset role;

-- An expired nonce is refused.
update public.push_dispatch_nonces set expires_at = now() - interval '1 second';
set local role service_role;
do $expired$
begin
  if public.consume_push_dispatch_nonce(current_setting('bw_validation.n2')) then
    raise exception 'an expired nonce was accepted';
  end if;
end;
$expired$;
reset role;

do $clients$
declare
  v_role text;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    if has_table_privilege(v_role, 'public.push_dispatch_nonces', 'select')
       or has_table_privilege(v_role, 'public.push_dispatch_nonces', 'insert')
       or has_table_privilege(v_role, 'public.push_dispatch_nonces', 'delete')
       or has_function_privilege(v_role, 'public.issue_push_dispatch_nonce()', 'execute')
       or has_function_privilege(v_role, 'public.consume_push_dispatch_nonce(text)', 'execute') then
      raise exception '% can reach the nonce table or functions', v_role;
    end if;
  end loop;
end;
$clients$;

-- Open nonces are capped.
do $cap$
begin
  delete from public.push_dispatch_nonces;
  for i in 1..100 loop
    perform public.issue_push_dispatch_nonce();
  end loop;
  begin
    perform public.issue_push_dispatch_nonce();
    raise exception 'more than 100 open nonces were allowed';
  exception when program_limit_exceeded then null;
  end;
end;
$cap$;

select 'push_dispatch_nonce_validation: PASS' as result;
rollback;
