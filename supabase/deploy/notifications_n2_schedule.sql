-- Notifications N2/N3 scheduler. NOT a migration and NOT applied automatically.
-- Run ONLY with the owner's approval, as postgres, on project
-- rbvcnvqpdqrhywcgxkne, AFTER:
--   1. migrations 20261120130000_follow_up_reminders_and_push_delivery and
--      20261121090000_push_dispatch_nonce applied;
--   2. Edge Function `push-dispatch` deployed with nonce support,
--      FCM_SERVICE_ACCOUNT_JSON set;
--   3. Vault bw_push_dispatch_url = https://<ref>.supabase.co/functions/v1/push-dispatch
--      (the URL is not a secret).
--
-- No long-lived secret is ever sent through pg_net: pg_net's request queue is
-- readable and writable by PUBLIC on this platform and postgres cannot revoke
-- that (proven 2026-11-21). Each dispatch call carries a fresh single-use
-- nonce from public.issue_push_dispatch_nonce() (only its hash is stored, it
-- expires in 2 minutes and push-dispatch consumes it once).
--
-- One transaction: a failed check undoes everything, extensions included.
-- What it schedules (nothing else):
--   bw-fire-follow-up-reminders  every minute  plain SQL: due reminders -> inbox + job
--   bw-push-dispatch             every minute  POST to push-dispatch with a nonce
--   bw-prune-push-delivery-jobs  daily 03:17   deletes ONLY finished delivery jobs
--                                              older than 30 days
-- It also deletes the old Vault entry bw_push_dispatch_secret (no longer used).
--
-- Rollback (stops all scheduling; inbox rows, jobs and the Vault URL stay):
--   select cron.unschedule('bw-push-dispatch');
--   select cron.unschedule('bw-fire-follow-up-reminders');
--   select cron.unschedule('bw-prune-push-delivery-jobs');
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regprocedure('public.fire_due_follow_up_reminders(integer)') is null
     or to_regprocedure('public.prune_push_delivery_jobs()') is null
     or to_regprocedure('public.issue_push_dispatch_nonce()') is null
     or to_regprocedure('public.consume_push_dispatch_nonce(text)') is null
     or has_function_privilege('anon', 'public.issue_push_dispatch_nonce()', 'execute')
     or has_function_privilege('authenticated', 'public.issue_push_dispatch_nonce()', 'execute')
     or has_function_privilege('service_role', 'public.issue_push_dispatch_nonce()', 'execute')
     or not exists (select 1 from vault.decrypted_secrets
                    where name = 'bw_push_dispatch_url'
                      and decrypted_secret = 'https://rbvcnvqpdqrhywcgxkne.supabase.co/functions/v1/push-dispatch')
  then
    raise exception 'scheduler preflight failed (migrations, nonce grants or Vault URL)';
  end if;
end;
$preflight$;

-- The static dispatch secret is no longer used by the scheduler.
delete from vault.secrets where name = 'bw_push_dispatch_secret';

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $existing$
begin
  if exists (select 1 from cron.job where jobname like 'bw-%') then
    raise exception 'scheduler preflight failed: bw-* cron jobs already exist';
  end if;
end;
$existing$;

select cron.schedule(
  'bw-fire-follow-up-reminders',
  '* * * * *',
  $$select public.fire_due_follow_up_reminders(200)$$
);

select cron.schedule(
  'bw-push-dispatch',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'bw_push_dispatch_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-dispatch-nonce', public.issue_push_dispatch_nonce()
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $$
);

select cron.schedule(
  'bw-prune-push-delivery-jobs',
  '17 3 * * *',
  $$select public.prune_push_delivery_jobs()$$
);

-- Guard: no scheduled command may carry or read a long-lived secret.
do $guard$
begin
  if exists (select 1 from cron.job
              where jobname like 'bw-%'
                and (command ilike '%x-dispatch-secret%'
                     or command ilike '%bw_push_dispatch_secret%'
                     or command ilike '%service_role%'
                     or command ilike '%authorization%'))
     or (select count(*) from cron.job where jobname like 'bw-%') <> 3
     or exists (select 1 from vault.secrets where name = 'bw_push_dispatch_secret') then
    raise exception 'scheduler guard failed: a job would carry a long-lived secret';
  end if;
end;
$guard$;

commit;

select jobname, schedule, active from cron.job where jobname like 'bw-%' order by jobname;
