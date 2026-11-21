-- RECOVERY ONLY. Undoes 20261121090000_push_dispatch_nonce. Run only with the
-- owner's approval, as postgres, AFTER unscheduling 'bw-push-dispatch'
-- (its command calls public.issue_push_dispatch_nonce()).
begin;
set local lock_timeout = '3s';

do $preflight$
declare
  v_scheduled boolean := false;
begin
  if current_user <> 'postgres' or to_regclass('public.push_dispatch_nonces') is null then
    raise exception 'nonce recovery preflight failed: the migration is not applied';
  end if;
  -- Dynamic SQL: cron.job may not exist at all (pg_cron not installed).
  if to_regclass('cron.job') is not null then
    execute $q$select exists (select 1 from cron.job where command like '%issue_push_dispatch_nonce%')$q$
      into v_scheduled;
  end if;
  if v_scheduled then
    raise exception 'nonce recovery preflight failed: unschedule bw-push-dispatch first';
  end if;
end;
$preflight$;

drop function if exists public.consume_push_dispatch_nonce(text);
drop function if exists public.issue_push_dispatch_nonce();
drop table if exists public.push_dispatch_nonces;
delete from supabase_migrations.schema_migrations where version = '20261121090000';

commit;
