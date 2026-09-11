-- =============================================================================
-- Broker Wallet: phone security migration validation
--
-- Run in the Supabase SQL Editor as the default `postgres` role, or with
-- `psql -f`. Needs no pgTAP, no extension and no schedule. It checks the same
-- behavior as supabase/tests/phone_security_test.sql against the real hosted
-- auth schema, before the migrations are applied for real.
--
-- What it does:
--   1. pre-checks everything the migrations and this script depend on;
--   2. installs both migrations from their exact file text (only their own
--      `begin;` / `commit;` lines are left out, so they run inside this
--      transaction; the Flutter test suite fails if this copy drifts);
--   3. exercises the grants and the new Auth trigger with temporary test users,
--      alongside the two Auth triggers the project already has;
--   4. undoes all of it, twice over:
--        - inside the run: every install and test step is in a savepoint that
--          is always rolled back before the report is written, which also
--          releases the table lock on auth.users straight away. The post
--          checks prove this;
--        - at the end: `rollback;` discards what is left (the report itself).
--      There is no COMMIT anywhere in this file.
--
-- Reading the result: the grid shows one row per check. Row 0 is the verdict:
--   PASSED - every check passed, and everything was undone.
--   FAILED - see the FAIL rows. Nothing was kept either way.
-- INFO rows are facts about the database, not checks.
--
-- Safety:
--   * No real account is written. Test users have reserved ids, `.invalid`
--     emails and numbers under country code 999, which has never been
--     assigned to any country. The script refuses to run if any of them
--     already exists, if any real account has a phone change in progress, or
--     if auth.users / public.profiles has a trigger this project did not
--     create (which could do something a rollback cannot undo). No SMS is sent
--     and Supabase Auth is not called.
--   * Installing the trigger locks auth.users. Supabase Auth requests wait
--     (they do not fail) for the second or so this takes. lock_timeout stops
--     the script from queueing behind a long transaction. Run it at a quiet
--     time.
--   * The editor may warn about a "destructive operation" because the
--     migration text contains `drop trigger if exists`. At this point that
--     trigger does not exist, and the whole run is rolled back.
-- =============================================================================

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table phone_validation_results (
  seq integer primary key,
  result text not null,
  check_name text not null,
  detail text
) on commit drop;

do $validation$
declare
  -- Reserved test identities.
  user_a constant uuid := '5ec0de00-0000-4000-8000-00000000000a';
  user_b constant uuid := '5ec0de00-0000-4000-8000-00000000000b';
  user_c constant uuid := '5ec0de00-0000-4000-8000-00000000000c';
  user_d constant uuid := '5ec0de00-0000-4000-8000-00000000000d';
  test_ids constant uuid[] := array[user_a, user_b, user_c, user_d];
  test_email_domain constant text := '@phone-validation.invalid';

  -- Test numbers, stored the way Supabase Auth stores them (no leading +).
  number_a constant text := '99900000001';  -- A's confirmed phone
  number_1 constant text := '99900000002';  -- the contested pending number
  number_d constant text := '99900000003';  -- D's abandoned attempt
  number_b constant text := '99900000004';  -- B's completed change
  test_numbers constant text[] := array[number_a, number_1, number_d, number_b];

  results jsonb := '[]'::jsonb;
  stage text := 'starting';
  completed boolean := false;
  affected integer;
  cleared integer;
  detail_text text;
  flag boolean;
  failures integer;
  passes integer;

  pre_guard_installed boolean;
  pre_function_count integer;
  pre_phone_number_writable boolean;
  pre_phone_e164_writable boolean;
begin
  -- State before the run, compared again after it.
  select exists (
    select 1 from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname = 'guard_pending_phone_change'
      and not tgisinternal
  ) into pre_guard_installed;

  select count(*) into pre_function_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('phone_change_grace_period', 'guard_pending_phone_change', 'clear_stale_phone_changes');

  pre_phone_number_writable := has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'UPDATE');
  pre_phone_e164_writable := has_column_privilege('authenticated', 'public.profiles', 'phone_e164', 'UPDATE');

  -- ===========================================================================
  -- Everything that changes anything happens inside this block. Its exception
  -- clause makes it a savepoint, and it always ends by raising, so all of it
  -- is rolled back before the report below is written.
  -- ===========================================================================
  begin
    -- -------------------------------------------------------------------------
    -- 1. Pre-checks
    -- -------------------------------------------------------------------------
    stage := 'running pre-checks';

    results := results || jsonb_build_object(
      'ok', current_user = 'postgres',
      'check', 'pre: running as postgres, which will own the new functions',
      'detail', 'current_user = ' || current_user);

    results := results || jsonb_build_object(
      'ok', pg_has_role(current_user, 'authenticated', 'MEMBER'),
      'check', 'pre: can act as the authenticated role to simulate a signed-in client');

    select count(*) into affected
    from information_schema.columns
    where table_schema = 'auth' and table_name = 'users'
      and column_name in ('phone', 'phone_change', 'phone_change_token', 'phone_change_sent_at');
    results := results || jsonb_build_object(
      'ok', affected = 4,
      'check', 'pre: auth.users has phone, phone_change, phone_change_token, phone_change_sent_at',
      'detail', affected || ' of 4 present');

    select is_nullable into detail_text
    from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'phone_change_sent_at';
    results := results || jsonb_build_object(
      'ok', coalesce(detail_text = 'YES', false),
      'check', 'pre: phone_change_sent_at is nullable (the cleanup sets it to NULL)',
      'detail', 'is_nullable = ' || coalesce(detail_text, 'column missing'));

    results := results || jsonb_build_object(
      'ok', has_table_privilege('auth.users', 'INSERT')
        and has_table_privilege('auth.users', 'UPDATE')
        and has_table_privilege('auth.users', 'TRIGGER'),
      'check', 'pre: postgres has INSERT, UPDATE and TRIGGER on auth.users',
      'detail', format('insert=%s update=%s trigger=%s',
        has_table_privilege('auth.users', 'INSERT')::text,
        has_table_privilege('auth.users', 'UPDATE')::text,
        has_table_privilege('auth.users', 'TRIGGER')::text));

    select format('row security=%s, %s bypasses RLS=%s',
                  c.relrowsecurity::text, r.rolname, r.rolbypassrls::text),
           not c.relrowsecurity or r.rolbypassrls
    into detail_text, flag
    from pg_class c, pg_roles r
    where c.oid = 'auth.users'::regclass and r.rolname = current_user;
    results := results || jsonb_build_object(
      'ok', flag,
      'check', 'pre: the functions'' owner can read and clear any auth.users row',
      'detail', detail_text);

    select count(*) into affected from auth.users where coalesce(phone_change, '') <> '';
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'pre: no real account has a phone change in progress, so nothing real is touched',
      'detail', affected || ' pending');

    select count(*) into affected
    from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname in ('on_auth_user_created', 'on_auth_user_identity_updated')
      and not tgisinternal
      and tgenabled <> 'D';
    results := results || jsonb_build_object(
      'ok', affected = 2,
      'check', 'pre: existing triggers on_auth_user_created and on_auth_user_identity_updated are enabled',
      'detail', affected || ' of 2 enabled');

    select string_agg(format('%s on %s', t.tgname, t.tgrelid::regclass), ', ' order by t.tgname)
    into detail_text
    from pg_trigger t
    where not t.tgisinternal
      and (
        (t.tgrelid = 'auth.users'::regclass
          and t.tgname not in ('on_auth_user_created', 'on_auth_user_identity_updated', 'guard_pending_phone_change'))
        or (t.tgrelid = 'public.profiles'::regclass
          and t.tgname not in ('profiles_bump_sync_version', 'profiles_validate_direct_media'))
      );
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'pre: auth.users and public.profiles carry only this project''s triggers',
      'detail', coalesce('unexpected: ' || detail_text, 'none unexpected'));

    select count(*) into affected
    from pg_proc p
    join pg_roles r on r.oid = p.proowner
    where p.oid in ('public.handle_new_auth_user()'::regprocedure, 'public.sync_auth_identity_to_profile()'::regprocedure)
      and p.prosecdef
      and r.rolname = 'postgres';
    results := results || jsonb_build_object(
      'ok', affected = 2,
      'check', 'pre: handle_new_auth_user and sync_auth_identity_to_profile are SECURITY DEFINER owned by postgres',
      'detail', affected || ' of 2');

    select count(*) into affected
    from auth.users
    where id = any(test_ids)
      or email like '%' || test_email_domain
      or phone = any(test_numbers)
      or phone_change = any(test_numbers);
    select affected + count(*) into affected
    from public.profiles
    where id = any(test_ids) or phone_number = any(test_numbers);
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'pre: the reserved test ids, emails and numbers are unused',
      'detail', affected || ' in use');

    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: pg_cron',
      'detail', case when exists (select 1 from pg_extension where extname = 'pg_cron')
        then 'installed: the migration schedules the 15-minute sweep'
        else 'not installed: the migration skips scheduling; the trigger does not depend on it' end);

    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: guard state before this run',
      'detail', case when pre_guard_installed
        then 'guard_pending_phone_change is already installed (re-validation)'
        else 'not installed yet' end);

    select format('auth.users is owned by %s; %s is %s member of it',
                  o.rolname, current_user,
                  case when pg_has_role(current_user, o.oid, 'MEMBER') then 'a' else 'not a' end)
    into detail_text
    from pg_class c join pg_roles o on o.oid = c.relowner
    where c.oid = 'auth.users'::regclass;
    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: auth.users ownership (re-running the migration once the trigger exists needs it)',
      'detail', detail_text);

    if exists (
      select 1 from jsonb_array_elements(results) e
      where not (e ? 'info') and not coalesce((e ->> 'ok')::boolean, false)
    ) then
      raise exception 'a pre-check failed; nothing was installed';
    end if;

    -- -------------------------------------------------------------------------
    -- 2. Install the migrations, exact file text
    -- -------------------------------------------------------------------------
    stage := 'installing 20260911000100_revoke_client_profile_phone_writes.sql';
    execute $migration_20260911000100$
-- The profile phone columns are a mirror of Supabase Auth identity, not
-- client-editable profile data.
--
-- `public.sync_auth_identity_to_profile()` (SECURITY DEFINER, owned by
-- postgres) copies `auth.users.phone` into `phone_number`, derives
-- `phone_e164`, and derives `is_phone_verified` from `phone_confirmed_at`.
-- While clients could also write `phone_number` / `phone_e164` directly, a
-- profile could show a number that Supabase Auth never confirmed, and a stale
-- client copy could overwrite a freshly confirmed one. Phone changes now go
-- through Supabase Auth's own verified phone-change flow only.
--
-- The baseline grants UPDATE column by column after revoking everything from
-- anon and authenticated, so revoking these two columns leaves exactly
-- `name` and `preferences` client-writable. SELECT is unchanged: the app reads
-- its own profile's phone. `is_phone_verified` was never client-writable.
--
-- Trusted writers are unaffected: the sync trigger runs as its owner
-- (postgres), and service_role keeps its privileges.

revoke update (phone_number, phone_e164) on public.profiles from authenticated;
revoke update (phone_number, phone_e164) on public.profiles from anon;
$migration_20260911000100$;
    results := results || jsonb_build_object(
      'ok', true,
      'check', 'install: 20260911000100_revoke_client_profile_phone_writes.sql');

    stage := 'installing 20260911000200_guard_pending_phone_changes.sql';
    execute $migration_20260911000200$
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
$migration_20260911000200$;
    results := results || jsonb_build_object(
      'ok', true,
      'check', 'install: 20260911000200_guard_pending_phone_changes.sql');

    -- -------------------------------------------------------------------------
    -- 3. Installed objects and grants
    -- -------------------------------------------------------------------------
    stage := 'checking installed objects and grants';

    results := results || jsonb_build_object(
      'ok', not has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'UPDATE')
        and not has_column_privilege('authenticated', 'public.profiles', 'phone_e164', 'UPDATE'),
      'check', 'grants: authenticated cannot UPDATE profiles.phone_number or phone_e164');

    results := results || jsonb_build_object(
      'ok', not has_column_privilege('anon', 'public.profiles', 'phone_number', 'UPDATE')
        and not has_column_privilege('anon', 'public.profiles', 'phone_e164', 'UPDATE'),
      'check', 'grants: anon cannot UPDATE profiles.phone_number or phone_e164');

    results := results || jsonb_build_object(
      'ok', not has_column_privilege('authenticated', 'public.profiles', 'is_phone_verified', 'UPDATE'),
      'check', 'grants: authenticated still cannot UPDATE profiles.is_phone_verified');

    results := results || jsonb_build_object(
      'ok', has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE')
        and has_column_privilege('authenticated', 'public.profiles', 'preferences', 'UPDATE'),
      'check', 'grants: authenticated can still UPDATE profiles.name and preferences');

    results := results || jsonb_build_object(
      'ok', has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'SELECT'),
      'check', 'grants: authenticated can still read profiles.phone_number');

    select format('type bits=%s enabled=%s function=%s columns=%s',
                  t.tgtype, t.tgenabled, t.tgfoid::regprocedure,
                  (select string_agg(a.attname, ',' order by a.attname)
                   from pg_attribute a
                   where a.attrelid = t.tgrelid and a.attnum = any(t.tgattr::int2[])))
    into detail_text
    from pg_trigger t
    where t.tgrelid = 'auth.users'::regclass
      and t.tgname = 'guard_pending_phone_change'
      and not t.tgisinternal
      -- row-level (1), BEFORE (2), UPDATE (16) only; no INSERT/DELETE/TRUNCATE/INSTEAD
      and t.tgtype = (1 | 2 | 16)
      and t.tgenabled = 'O'
      and t.tgfoid = 'public.guard_pending_phone_change()'::regprocedure
      and t.tgattr::int2[] = array[(
        select attnum from pg_attribute
        where attrelid = 'auth.users'::regclass and attname = 'phone_change'
      )]::int2[];
    results := results || jsonb_build_object(
      'ok', detail_text is not null,
      'check', 'trigger: guard_pending_phone_change is BEFORE UPDATE OF phone_change, FOR EACH ROW, enabled',
      'detail', coalesce(detail_text, 'missing or shaped differently'));

    select count(*) into affected
    from pg_proc p
    join pg_roles r on r.oid = p.proowner
    where p.oid in ('public.guard_pending_phone_change()'::regprocedure,
                    'public.clear_stale_phone_changes()'::regprocedure)
      and p.prosecdef
      and r.rolname = 'postgres'
      and p.proconfig @> array['search_path=""'];
    results := results || jsonb_build_object(
      'ok', affected = 2,
      'check', 'functions: guard and sweep are SECURITY DEFINER, owned by postgres, search_path pinned to empty',
      'detail', affected || ' of 2');

    results := results || jsonb_build_object(
      'ok', (select proconfig @> array['search_path=""'] and not prosecdef
             from pg_proc where oid = 'public.phone_change_grace_period()'::regprocedure),
      'check', 'functions: phone_change_grace_period pins search_path and is not SECURITY DEFINER');

    select string_agg(format('%s:%s', fn, role_name), ', ')
    into detail_text
    from unnest(array['public.phone_change_grace_period()',
                      'public.guard_pending_phone_change()',
                      'public.clear_stale_phone_changes()']) as fn,
         unnest(array['anon', 'authenticated']) as role_name
    where has_function_privilege(role_name, fn, 'EXECUTE');
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'functions: anon and authenticated cannot EXECUTE any of the three',
      'detail', coalesce('executable: ' || detail_text, 'none executable'));

    -- -------------------------------------------------------------------------
    -- 4. Test users, created through the existing profile trigger
    -- -------------------------------------------------------------------------
    stage := 'creating test users';

    insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
    values
      (user_a, 'a' || test_email_domain, '{"name":"Validation A"}'::jsonb, now(), now()),
      (user_b, 'b' || test_email_domain, '{"name":"Validation B"}'::jsonb, now(), now()),
      (user_c, 'c' || test_email_domain, '{"name":"Validation C"}'::jsonb, now(), now()),
      (user_d, 'd' || test_email_domain, '{"name":"Validation D"}'::jsonb, now(), now());

    select count(*) into affected from public.profiles where id = any(test_ids);
    results := results || jsonb_build_object(
      'ok', affected = 4,
      'check', 'auth: on_auth_user_created still creates a profile for each new user',
      'detail', affected || ' of 4 profiles');

    -- -------------------------------------------------------------------------
    -- 5. A signed-in client cannot write the phone mirror
    -- -------------------------------------------------------------------------
    stage := 'simulating a signed-in client';

    begin
      perform set_config('request.jwt.claim.sub', user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
      set local role authenticated;
      update public.profiles set phone_number = '+971500000000' where id = user_a;
      set local role none;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'client: a signed-in user cannot write its own profiles.phone_number',
        'detail', 'the write was accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '42501',
        'check', 'client: a signed-in user cannot write its own profiles.phone_number',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      perform set_config('request.jwt.claim.sub', user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
      set local role authenticated;
      update public.profiles set phone_e164 = '+971500000000' where id = user_a;
      set local role none;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'client: a signed-in user cannot write its own profiles.phone_e164',
        'detail', 'the write was accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '42501',
        'check', 'client: a signed-in user cannot write its own profiles.phone_e164',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      perform set_config('request.jwt.claim.sub', user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
      set local role authenticated;
      update public.profiles set name = 'Validation A renamed' where id = user_a;
      get diagnostics affected = row_count;
      set local role none;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'client: a signed-in user can still rename its own profile',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'client: a signed-in user can still rename its own profile',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    -- -------------------------------------------------------------------------
    -- 6. The trusted sync still maintains the mirror
    -- -------------------------------------------------------------------------
    stage := 'checking the identity sync';

    begin
      update auth.users
      set phone = number_a, phone_confirmed_at = now(), updated_at = now()
      where id = user_a;
      select format('phone_number=%s is_phone_verified=%s',
                    coalesce(phone_number, 'null'), is_phone_verified::text)
      into detail_text
      from public.profiles where id = user_a;
      results := results || jsonb_build_object(
        'ok', detail_text = format('phone_number=%s is_phone_verified=true', number_a),
        'check', 'auth: a confirmed phone still syncs into the profile mirror',
        'detail', detail_text);
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'auth: a confirmed phone still syncs into the profile mirror',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- -------------------------------------------------------------------------
    -- 7. The pending phone-change guard
    -- Every request below changes the number or the token, as a real
    -- Supabase Auth (re)send does. now() is fixed for the whole transaction.
    -- -------------------------------------------------------------------------
    stage := 'exercising the pending phone-change guard';

    begin
      update auth.users
      set phone_change = number_1, phone_change_token = 'validation-token-b1', phone_change_sent_at = now()
      where id = user_b;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'guard: an account can start a phone change',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: an account can start a phone change',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    results := results || jsonb_build_object(
      'ok', exists (
        select 1 from pg_locks l
        where l.locktype = 'advisory'
          and l.pid = pg_backend_pid()
          and l.granted
          and l.objsubid = 1
          and ((l.classid::bigint << 32) | l.objid::bigint)
            = hashtextextended('broker_wallet.phone_change:' || number_1, 0)
      ),
      'check', 'guard: the request took the per-number advisory lock that serializes concurrent requests');

    select format('phone_number=%s is_phone_verified=%s',
                  coalesce(phone_number, 'null'), is_phone_verified::text)
    into detail_text
    from public.profiles where id = user_b;
    results := results || jsonb_build_object(
      'ok', detail_text = 'phone_number=null is_phone_verified=false',
      'check', 'guard: a pending number never reaches the profile mirror',
      'detail', detail_text);

    begin
      update auth.users
      set phone_change = number_1, phone_change_token = 'validation-token-c1', phone_change_sent_at = now()
      where id = user_c;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: a second account cannot hold the same live pending number',
        'detail', 'the write was accepted: two accounts hold the same pending number');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = 'P0001' and sqlerrm = 'phone_change_unavailable',
        'check', 'guard: a second account cannot hold the same live pending number',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    select count(*) into affected from auth.users where phone_change = number_1;
    results := results || jsonb_build_object(
      'ok', affected = 1,
      'check', 'guard: after the refusal exactly one account holds the pending number',
      'detail', affected || ' holder(s)');

    begin
      update auth.users
      set phone_change = number_1, phone_change_token = 'validation-token-b2', phone_change_sent_at = now()
      where id = user_b;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'guard: the same account can request a new code for its own pending number',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: the same account can request a new code for its own pending number',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- B abandons its attempt: it outlives the grace period. phone_change is
    -- not in this SET list, so the guard does not fire.
    update auth.users
    set phone_change_sent_at = now() - interval '1 hour'
    where id = user_b;

    begin
      update auth.users
      set phone_change = number_1, phone_change_token = 'validation-token-c2', phone_change_sent_at = now()
      where id = user_c;
      get diagnostics affected = row_count;
      select format('B phone_change=%s token=%s sent_at=%s; C phone_change=%s',
                    coalesce(nullif(b.phone_change, ''), 'none'),
                    coalesce(nullif(b.phone_change_token, ''), 'none'),
                    coalesce(b.phone_change_sent_at::text, 'none'),
                    coalesce(nullif(c.phone_change, ''), 'none'))
      into detail_text
      from auth.users b, auth.users c
      where b.id = user_b and c.id = user_c;
      results := results || jsonb_build_object(
        'ok', affected = 1
          and detail_text = format('B phone_change=none token=none sent_at=none; C phone_change=%s', number_1),
        'check', 'guard: a stale attempt is cleared (number, token, send time) and the new request proceeds',
        'detail', detail_text);
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: a stale attempt is cleared (number, token, send time) and the new request proceeds',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update auth.users
      set phone_change = number_a, phone_change_token = 'validation-token-c3', phone_change_sent_at = now()
      where id = user_c;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: a number confirmed on another account cannot become pending',
        'detail', 'the write was accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = 'P0001' and sqlerrm = 'phone_change_unavailable',
        'check', 'guard: a number confirmed on another account cannot become pending',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- -------------------------------------------------------------------------
    -- 8. The documented periodic cleanup
    -- -------------------------------------------------------------------------
    stage := 'exercising the stale cleanup';

    update auth.users
    set phone_change = number_d, phone_change_token = 'validation-token-d1',
        phone_change_sent_at = now() - interval '2 hours'
    where id = user_d;

    begin
      cleared := public.clear_stale_phone_changes();
      select format('cleared=%s; D=%s; C=%s; A phone=%s', cleared,
                    coalesce(nullif(d.phone_change, ''), 'none'),
                    coalesce(nullif(c.phone_change, ''), 'none'),
                    a.phone)
      into detail_text
      from auth.users a, auth.users c, auth.users d
      where a.id = user_a and c.id = user_c and d.id = user_d;
      results := results || jsonb_build_object(
        'ok', detail_text = format('cleared=1; D=none; C=%s; A phone=%s', number_1, number_a),
        'check', 'sweep: clears only the stale attempt, keeps the live one and every confirmed phone',
        'detail', detail_text);
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'sweep: clears only the stale attempt, keeps the live one and every confirmed phone',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- -------------------------------------------------------------------------
    -- 9. Unrelated Supabase Auth writes are never refused
    -- C still holds pending number_1. An administrative write now makes it
    -- D's confirmed phone (the guard does not watch `phone`), so a guard
    -- evaluated for C would refuse from here on.
    -- -------------------------------------------------------------------------
    stage := 'checking unrelated Auth writes';

    begin
      update auth.users set phone = number_1, phone_confirmed_at = now() where id = user_d;
      select phone_number into detail_text from public.profiles where id = user_d;
      results := results || jsonb_build_object(
        'ok', detail_text = number_1,
        'check', 'auth: an administrative phone write is not guarded and still syncs',
        'detail', 'profile phone_number=' || coalesce(detail_text, 'null'));
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'auth: an administrative phone write is not guarded and still syncs',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update auth.users set updated_at = now(), last_sign_in_at = now() where id = user_c;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'auth: a sign-in style update that does not touch phone_change is unaffected',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'auth: a sign-in style update that does not touch phone_change is unaffected',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update auth.users
      set phone_change = phone_change,
          phone_change_token = phone_change_token,
          phone_change_sent_at = phone_change_sent_at,
          raw_app_meta_data = raw_app_meta_data,
          raw_user_meta_data = raw_user_meta_data,
          updated_at = now()
      where id = user_c;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'auth: a full-row re-save with an unchanged pending change is never refused',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'auth: a full-row re-save with an unchanged pending change is never refused',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update auth.users
      set phone_change = phone_change, phone_change_token = 'validation-token-c4', phone_change_sent_at = now()
      where id = user_c;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: resending a code for a number now confirmed elsewhere is refused',
        'detail', 'the write was accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = 'P0001' and sqlerrm = 'phone_change_unavailable',
        'check', 'guard: resending a code for a number now confirmed elsewhere is refused',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update auth.users
      set phone_change = '', phone_change_token = '', phone_change_sent_at = null
      where id = user_c;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'guard: clearing a pending change neither recurses nor fails',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'guard: clearing a pending change neither recurses nor fails',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- -------------------------------------------------------------------------
    -- 10. A normal Supabase Auth phone change completes end to end
    -- -------------------------------------------------------------------------
    stage := 'completing a normal phone change';

    begin
      update auth.users
      set phone_change = number_b, phone_change_token = 'validation-token-b3', phone_change_sent_at = now()
      where id = user_b;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'flow: a fresh phone change can be requested',
        'detail', affected || ' row(s) updated');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'flow: a fresh phone change can be requested',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      -- The columns Supabase Auth writes when a phone_change code is verified.
      update auth.users
      set phone = phone_change,
          phone_change = '',
          phone_change_token = '',
          phone_confirmed_at = now()
      where id = user_b;
      select format('auth phone=%s pending=%s; profile phone_number=%s is_phone_verified=%s',
                    u.phone, coalesce(nullif(u.phone_change, ''), 'none'),
                    coalesce(p.phone_number, 'null'), p.is_phone_verified::text)
      into detail_text
      from auth.users u join public.profiles p on p.id = u.id
      where u.id = user_b;
      results := results || jsonb_build_object(
        'ok', detail_text = format('auth phone=%s pending=none; profile phone_number=%s is_phone_verified=true',
                                   number_b, number_b),
        'check', 'flow: confirming the change succeeds and reaches the profile as verified',
        'detail', detail_text);
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'flow: confirming the change succeeds and reaches the profile as verified',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- Undo everything in this block, including the installed migrations.
    completed := true;
    raise exception using errcode = 'P0001', message = 'phone_validation_rollback';
  exception when others then
    if not completed then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'validation stopped while ' || stage,
        'detail', sqlstate || ': ' || sqlerrm);
    end if;
  end;

  -- ===========================================================================
  -- 11. Post-checks: the rollback above really undid everything
  -- ===========================================================================
  results := results || jsonb_build_object(
    'ok', exists (
      select 1 from pg_trigger
      where tgrelid = 'auth.users'::regclass
        and tgname = 'guard_pending_phone_change'
        and not tgisinternal
    ) = pre_guard_installed,
    'check', 'post: the guard trigger is back to its state before the run');

  select count(*) into affected
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('phone_change_grace_period', 'guard_pending_phone_change', 'clear_stale_phone_changes');
  results := results || jsonb_build_object(
    'ok', affected = pre_function_count,
    'check', 'post: the new functions are back to their state before the run',
    'detail', format('%s before, %s after', pre_function_count, affected));

  results := results || jsonb_build_object(
    'ok', has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'UPDATE') = pre_phone_number_writable
      and has_column_privilege('authenticated', 'public.profiles', 'phone_e164', 'UPDATE') = pre_phone_e164_writable,
    'check', 'post: the profile phone grants are back to their state before the run');

  select count(*) into affected
  from auth.users
  where id = any(test_ids) or email like '%' || test_email_domain or phone = any(test_numbers);
  select affected + count(*) into affected from public.profiles where id = any(test_ids);
  results := results || jsonb_build_object(
    'ok', affected = 0,
    'check', 'post: no test user or test profile remains',
    'detail', affected || ' remaining');

  select string_agg(distinct l.mode, ', ')
  into detail_text
  from pg_locks l
  where l.pid = pg_backend_pid()
    and (
      l.locktype = 'advisory'
      or (l.locktype = 'relation' and l.relation = 'auth.users'::regclass and l.mode <> 'AccessShareLock')
    );
  results := results || jsonb_build_object(
    'ok', detail_text is null,
    'check', 'post: this session no longer blocks Supabase Auth (no advisory lock, no write lock on auth.users)',
    'detail', coalesce('still held: ' || detail_text, 'none held'));

  -- ===========================================================================
  -- Report
  -- ===========================================================================
  insert into pg_temp.phone_validation_results (seq, result, check_name, detail)
  select ord,
         case
           when e ? 'info' then 'INFO'
           when coalesce((e ->> 'ok')::boolean, false) then 'PASS'
           else 'FAIL'
         end,
         e ->> 'check',
         e ->> 'detail'
  from jsonb_array_elements(results) with ordinality as entry(e, ord);

  select count(*) filter (where result = 'FAIL'), count(*) filter (where result = 'PASS')
  into failures, passes
  from pg_temp.phone_validation_results;

  insert into pg_temp.phone_validation_results (seq, result, check_name, detail)
  values (
    0,
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end,
    format('PHONE SECURITY VALIDATION %s: %s passed, %s failed',
           case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures),
    case
      when not completed then 'The run stopped early; see the last FAIL row. Nothing was kept.'
      else 'All changes were rolled back inside the run (see post rows); the final ROLLBACK discards this report.'
    end);

  raise notice 'PHONE SECURITY VALIDATION %: % passed, % failed',
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures;
end;
$validation$;

select seq as "#", result, check_name, detail
from pg_temp.phone_validation_results
order by seq;

rollback;
