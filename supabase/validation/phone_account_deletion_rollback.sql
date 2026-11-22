-- SOURCE ONLY. Reverses 20261122140000_phone_account_deletion.sql. Run only
-- with the owner's approval, as postgres, from an LF copy of this file:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_account_deletion_rollback.sql
--
-- BEFORE RUNNING: deploy a Worker without the phone deletion path first (or
-- accept that phone accounts then get "temporarily unavailable" on Delete
-- Account). Email accounts' password path does not use these objects.
--
-- Removes the challenge table and its three functions. The table holds only
-- short-lived challenges (account, session, counters, times): no number, code
-- or token, and nothing worth keeping.
--
-- If the migration was applied with `supabase db push`, its history entry is
-- corrected afterwards as a separate owner step:
--   supabase migration repair --status reverted 20261122140000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.account_deletion_challenges') is null
     or to_regprocedure('public.account_deletion_challenge_issue(uuid,uuid)') is null then
    raise exception 'phone account deletion rollback preflight failed: objects not present';
  end if;
end;
$preflight$;

drop function public.account_deletion_challenge_consume(uuid, uuid);
drop function public.account_deletion_challenge_attempt(uuid, uuid);
drop function public.account_deletion_challenge_issue(uuid, uuid);
drop table public.account_deletion_challenges;

do $postflight$
begin
  if to_regclass('public.account_deletion_challenges') is not null
     or exists (select 1 from pg_proc
                 where pronamespace = 'public'::regnamespace
                   and proname like 'account_deletion_challenge_%') then
    raise exception 'phone account deletion rollback postflight failed';
  end if;
end;
$postflight$;

select 'phone_account_deletion_rollback: DONE' as result;
commit;
