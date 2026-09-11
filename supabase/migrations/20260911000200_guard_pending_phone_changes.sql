-- Prevents Supabase Auth phone-change verification from resolving to the
-- wrong account.
--
-- Documented risk (Supabase troubleshooting: "Unexpected behavior with
-- auth.updateUser({ phone }): Phone linked to incorrect user ID"):
-- verification locates the account through `auth.users.phone_change`, that
-- column is not unique, and when several accounts hold the same pending
-- number — typically from abandoned attempts — a successful code can update
-- the first matching account rather than the one that asked.
--
-- Supabase's documented mitigation is to treat unconfirmed attempts as stale
-- after a grace period and clear their `phone_change`. That narrows the
-- window but, as a periodic job, cannot stop two accounts from holding the
-- same pending number *within* the window. This migration applies the
-- documented cleanup and closes the window at the moment it would open:
--
--   1. A BEFORE UPDATE OF phone_change trigger on auth.users. When an account
--      starts a phone change, stale attempts for the same number on other
--      accounts are cleared (the documented rule), and if a live attempt or a
--      confirmed phone for that number remains on another account the write
--      is refused. At most one account can therefore hold a given pending
--      number, so a code can only ever resolve to one account. Concurrent
--      requests for the same number are serialized with a transaction-scoped
--      advisory lock, so two sessions cannot both pass the check before either
--      commits.
--   2. A sweep function for the same stale rule, scheduled every 15 minutes
--      when pg_cron is available, bounding how long abandoned state persists.
--
-- Official vs custom: only the stale-attempt cleanup is Supabase's documented
-- mitigation. The write-time single-holder guard (1) — the refusal, the
-- advisory lock, the re-save and SKIP LOCKED rules — is this project's own
-- hardening built on top of it, not a Supabase-prescribed implementation. It
-- depends on Supabase Auth's internal phone_change / phone_change_token /
-- phone_change_sent_at columns, so it is re-validated whenever Supabase Auth
-- is upgraded (supabase/validation/phone_security_validation.sql).
--
-- Nothing here alters Supabase-managed auth schema objects: no columns,
-- constraints or indexes are added to auth.users. A trigger on auth.users is
-- the pattern Supabase documents for reacting to auth changes, and this
-- project already relies on two (profile creation and identity sync). The
-- functions live in public, run as their owner (postgres), pin search_path,
-- and are not executable by anon or authenticated. No client ever reads
-- auth.users, and a refusal reaches the client only as Supabase Auth's generic
-- "Database error updating user" — nothing about any other account is
-- disclosed.

begin;

-- Fail loudly if the Supabase Auth columns this relies on are not present,
-- rather than creating a guard that silently does nothing.
do $$
begin
  if (
    select count(*)
    from information_schema.columns
    where table_schema = 'auth'
      and table_name = 'users'
      and column_name in ('phone', 'phone_change', 'phone_change_token', 'phone_change_sent_at')
  ) <> 4 then
    raise exception 'auth.users is missing the phone change columns this guard depends on';
  end if;
end;
$$;

-- How long an unconfirmed phone change stays live. Must be at least the
-- hosted SMS OTP expiry and at least the SMS provider's own code lifetime
-- (Twilio Verify: 10 minutes by default), so a still-valid code is never
-- orphaned by another account's request. Defined once; the trigger and the
-- sweep both use it.
create or replace function public.phone_change_grace_period()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '15 minutes'
$$;

revoke all on function public.phone_change_grace_period() from public;
revoke all on function public.phone_change_grace_period() from anon;
revoke all on function public.phone_change_grace_period() from authenticated;

create or replace function public.guard_pending_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Clearing or completing a change (Supabase Auth empties phone_change on
  -- successful verification) can never create ambiguity.
  if coalesce(new.phone_change, '') = '' then
    return new;
  end if;

  -- `UPDATE OF phone_change` fires whenever the column is in the SET list,
  -- even when its value is unchanged — and Supabase Auth may write every
  -- column when it saves a user for an unrelated reason. Such a re-save
  -- creates no new pending holder, so it is left alone. Guarding it would
  -- only add lock traffic, and could fail an unrelated sign-in or profile
  -- update with an Auth 500 for as long as the stale state persisted.
  -- A (re)send always changes the token and send time, so it is still guarded.
  if new.phone_change is not distinct from old.phone_change
     and new.phone_change_token is not distinct from old.phone_change_token
     and new.phone_change_sent_at is not distinct from old.phone_change_sent_at
  then
    return new;
  end if;

  -- Serialize every write that sets this pending number, so concurrent
  -- requests for it run the check below one at a time against committed data.
  perform pg_advisory_xact_lock(
    hashtextextended('broker_wallet.phone_change:' || new.phone_change, 0)
  );

  -- Documented mitigation: an unconfirmed attempt for this number on another
  -- account that has outlived the grace period is abandoned. Clear it.
  --
  -- SKIP LOCKED: this session already holds its own row and the advisory
  -- lock, so waiting on another account's row lock could deadlock with a
  -- session doing the reverse. A row that is locked right now is being
  -- written, not abandoned; it is skipped, and the check below then counts it
  -- as a holder and refuses — failing safe instead of waiting.
  update auth.users
  set phone_change = '',
      phone_change_token = '',
      phone_change_sent_at = null
  where id in (
    select stale.id
    from auth.users as stale
    where stale.phone_change = new.phone_change
      and stale.id <> new.id
      and (
        stale.phone_change_sent_at is null
        or stale.phone_change_sent_at < now() - public.phone_change_grace_period()
      )
    for update skip locked
  );

  -- Whatever remains is a live attempt on another account, a stale one that
  -- could not be cleared just now, or the number is already that account's
  -- confirmed phone. Two pending rows for one number is exactly the ambiguity
  -- to prevent, so refuse this one. Staleness is deliberately not considered
  -- here: counting every remaining holder is what keeps the result
  -- single-holder even when a stale row was skipped.
  if exists (
    select 1
    from auth.users
    where id <> new.id
      and (phone_change = new.phone_change or phone = new.phone_change)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'phone_change_unavailable';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_pending_phone_change() from public;
revoke all on function public.guard_pending_phone_change() from anon;
revoke all on function public.guard_pending_phone_change() from authenticated;

drop trigger if exists guard_pending_phone_change on auth.users;
create trigger guard_pending_phone_change
  before update of phone_change on auth.users
  for each row execute function public.guard_pending_phone_change();

-- The documented periodic cleanup, applied to every account. Only pending
-- changes are touched: a confirmed `phone` is never modified.
create or replace function public.clear_stale_phone_changes()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleared integer;
begin
  update auth.users
  set phone_change = '',
      phone_change_token = '',
      phone_change_sent_at = null
  where coalesce(phone_change, '') <> ''
    and (
      phone_change_sent_at is null
      or phone_change_sent_at < now() - public.phone_change_grace_period()
    );

  get diagnostics cleared = row_count;
  return cleared;
end;
$$;

revoke all on function public.clear_stale_phone_changes() from public;
revoke all on function public.clear_stale_phone_changes() from anon;
revoke all on function public.clear_stale_phone_changes() from authenticated;

-- Start from a clean slate. The trigger also fires when Supabase Auth
-- re-saves an unchanged pending value, so any abandoned duplicates that
-- predate this guard are cleared as it is installed.
select public.clear_stale_phone_changes();

-- Schedule the sweep when pg_cron is enabled. The trigger above is what
-- guarantees correctness; the sweep only bounds how long abandoned state is
-- kept, so its absence never reopens the ambiguity.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'clear-stale-phone-changes';

    perform cron.schedule(
      'clear-stale-phone-changes',
      '*/15 * * * *',
      'select public.clear_stale_phone_changes()'
    );
  end if;
end;
$$;

commit;
