-- =============================================================================
-- Broker Wallet: account deletion cascade validation (rollback only)
--
-- Run in the Supabase SQL Editor as the default `postgres` role, or with
-- `psql -f`. Needs no pgTAP and no extension.
--
-- It installs migration 20260913000100_account_deletion_jobs.sql from its
-- exact file text (only its own `begin;` / `commit;` lines are left out, so it
-- runs inside this transaction; the Flutter test suite fails if this copy
-- drifts) — or, if that table already exists, validates the existing one — and
-- then rolls everything back.
--
-- What it proves:
--   0. the deletion job table is service-role only (RLS on, no policies, no
--      anon/authenticated privileges), has no foreign key, requires a bucket,
--      rejects invalid states and an early cleanup stamp, and its row SURVIVES
--      the account's auth.users deletion and can then be stamped;
--   1. every foreign key that references auth.users or public.profiles either
--      cascades or sets NULL — nothing can block deleting an account;
--   2. deleting a synthetic auth.users row (as supabase_auth_admin, the role
--      Supabase Auth's admin delete runs as, when this session may assume it)
--      removes its profile and every row it owns, including child rows and
--      its media metadata, through the project's own triggers;
--   3. another account's data is untouched, and the deleted account's
--      references in other accounts' notifications and in audit_logs are set
--      to NULL rather than blocking or cascading into someone else's data.
--
-- It also reports, as INFO, facts the retention decision needs: how many
-- audit_logs / revenuecat_webhook_events / notifications rows exist and which
-- JSON keys audit_logs.details uses. It never prints row contents.
--
-- Safety:
--   * No real account is touched. Test users have reserved ids and `.invalid`
--     emails; the script refuses to run if any of them exists.
--   * Every write happens inside a block that always ends by raising, so it is
--     rolled back before the report is written. The post checks prove it, and
--     the final `rollback;` discards the report. There is no COMMIT.
--   * No Supabase Auth API is called, no email is sent, no R2 object exists
--     for these ids and none is touched.
-- =============================================================================

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table account_deletion_validation_results (
  seq integer primary key,
  result text not null,
  check_name text not null,
  detail text
) on commit drop;

do $validation$
declare
  user_a constant uuid := 'de1e7e00-0000-4000-8000-00000000000a';  -- deleted
  user_b constant uuid := 'de1e7e00-0000-4000-8000-00000000000b';  -- kept
  test_ids constant uuid[] := array[user_a, user_b];
  test_email_domain constant text := '@account-deletion-validation.invalid';

  media_avatar constant uuid := 'de1e7e00-0000-4000-8000-0000000000a1';
  media_thumb constant uuid := 'de1e7e00-0000-4000-8000-0000000000a2';
  media_logo constant uuid := 'de1e7e00-0000-4000-8000-0000000000a3';
  offer_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a4';
  offer_b constant uuid := 'de1e7e00-0000-4000-8000-0000000000b4';
  request_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a5';
  quotation_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a6';
  owner_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a7';
  note_to_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a8';
  note_from_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000b8';
  audit_by_a constant uuid := 'de1e7e00-0000-4000-8000-0000000000a9';
  audit_by_b constant uuid := 'de1e7e00-0000-4000-8000-0000000000b9';

  results jsonb := '[]'::jsonb;
  stage text := 'starting';
  completed boolean := false;
  affected integer;
  detail_text text;
  flag boolean;
  failures integer;
  passes integer;
  deleted_as text;
  pre_jobs_table_exists boolean;
begin
  pre_jobs_table_exists := to_regclass('public.account_deletion_jobs') is not null;

  begin
    -- -------------------------------------------------------------------------
    -- 1. Pre-checks
    -- -------------------------------------------------------------------------
    stage := 'running pre-checks';

    results := results || jsonb_build_object(
      'ok', current_user = 'postgres',
      'check', 'pre: running as postgres',
      'detail', 'current_user = ' || current_user);

    select count(*) into affected
    from auth.users
    where id = any(test_ids) or email like '%' || test_email_domain;
    select affected + count(*) into affected from public.profiles where id = any(test_ids);
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'pre: the reserved test ids and emails are unused',
      'detail', affected || ' in use');

    -- Any foreign key onto auth.users or public.profiles whose delete action is
    -- NO ACTION or RESTRICT would make account deletion fail.
    select string_agg(format('%s.%s (%s)', c.conrelid::regclass, c.conname, c.confdeltype), ', ' order by c.conrelid::regclass::text)
    into detail_text
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
      and c.confdeltype not in ('c', 'n');
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'schema: every foreign key onto auth.users / public.profiles cascades or sets NULL',
      'detail', coalesce('blocking: ' || detail_text, 'none blocking'));

    select string_agg(column_ref, ', ' order by column_ref)
    into detail_text
    from (
      select format('%s.%s', r.relname, a.attname) as column_ref
      from pg_constraint c
      join pg_class r on r.oid = c.conrelid
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
      where c.contype = 'f'
        and c.confrelid = 'public.profiles'::regclass
        and c.confdeltype = 'n'
    ) set_null_columns;
    results := results || jsonb_build_object(
      'ok', detail_text = 'audit_logs.actor_id, audit_logs.target_user_id, notifications.sender_user_id',
      'check', 'schema: only audit_logs actor/target and notifications sender are SET NULL onto profiles',
      'detail', coalesce(detail_text, 'none'));

    select confdeltype = 'c' into flag
    from pg_constraint
    where conrelid = 'public.profiles'::regclass and contype = 'f' and confrelid = 'auth.users'::regclass;
    results := results || jsonb_build_object(
      'ok', coalesce(flag, false),
      'check', 'schema: public.profiles.id -> auth.users.id is ON DELETE CASCADE');

    select string_agg(format('%s on %s', t.tgname, t.tgrelid::regclass), ', ' order by t.tgname)
    into detail_text
    from pg_trigger t
    where not t.tgisinternal
      and t.tgenabled <> 'D'
      and t.tgrelid = 'auth.users'::regclass
      and (t.tgtype & 8) = 8;  -- fires on DELETE
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'pre: no DELETE trigger on auth.users that a rollback could not undo',
      'detail', coalesce('present: ' || detail_text, 'none'));

    select exists (
      select 1 from pg_roles where rolname = 'supabase_auth_admin'
    ) and pg_has_role(current_user, 'supabase_auth_admin', 'MEMBER') into flag;
    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: role used for the delete',
      'detail', case when flag
        then 'supabase_auth_admin (the role Supabase Auth deletes users as)'
        else 'postgres (this session cannot assume supabase_auth_admin; foreign key actions still run with table-owner rights)' end);

    -- Facts for the retention decision. Counts and key names only, no content.
    select count(*) into affected from public.audit_logs;
    select string_agg(distinct k, ', ') into detail_text
    from public.audit_logs, lateral jsonb_object_keys(details) as k;
    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: audit_logs rows and the keys used in details',
      'detail', format('%s rows; details keys: %s', affected, coalesce(detail_text, 'none')));

    select count(*) into affected from public.revenuecat_webhook_events;
    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: revenuecat_webhook_events rows (app_user_id and payload have no foreign key and are not deleted with an account)',
      'detail', affected || ' rows');

    select count(*) into affected from public.notifications where sender_user_id is not null;
    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: notifications that name a sender (their title/body text is not rewritten when the sender is deleted)',
      'detail', affected || ' rows');

    begin
      execute 'select count(*) from storage.objects' into affected;
      results := results || jsonb_build_object(
        'info', true,
        'check', 'info: Supabase Storage objects (account deletion does not clean Storage)',
        'detail', affected || ' objects');
    exception when others then
      results := results || jsonb_build_object(
        'info', true,
        'check', 'info: Supabase Storage objects',
        'detail', 'not readable: ' || sqlstate);
    end;

    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: account_deletion_jobs before this run',
      'detail', case when pre_jobs_table_exists
        then 'already exists: validating the existing table, not installing'
        else 'not present: installing the migration inside this transaction' end);

    if exists (
      select 1 from jsonb_array_elements(results) e
      where not (e ? 'info') and not coalesce((e ->> 'ok')::boolean, false)
    ) then
      raise exception 'a pre-check failed; nothing was written';
    end if;

    -- -------------------------------------------------------------------------
    -- 1a. Install the deletion job migration, exact file text
    -- -------------------------------------------------------------------------
    stage := 'installing 20260913000100_account_deletion_jobs.sql';
    if not pre_jobs_table_exists then
      execute $migration_20260913000100$
-- Server-owned record of an account deletion that outlives the account.
--
-- Deleting `auth.users` cascades through `public.profiles` and removes every
-- row that names the account, including `media_objects`. Two things must still
-- happen after that point, and neither can be authorized by the deleted
-- account's own session, which Supabase Auth no longer accepts:
--
--   1. Upload quarantine. While a deletion is in progress the media Worker must
--      not issue a signed R2 PUT URL for the account. The Worker checks this
--      table immediately before signing.
--   2. Deferred R2 finalization. A signed PUT URL issued before the quarantine
--      began stays valid for its TTL and can create an object after the account
--      is gone. The Worker's scheduled finalizer sweeps `profiles/<user_id>/`
--      in `bucket` once `cleanup_not_before` has passed, by which time no URL
--      for that prefix can still be valid.
--
-- The row is the only server-side authority for that cleanup: `user_id` comes
-- from a Supabase-verified session when the row is created, never from a
-- client afterwards, and the R2 location is derived from `bucket` and
-- `user_id`.
--
-- `user_id` deliberately has NO foreign key. A foreign key to `auth.users` or
-- `public.profiles` would either block the account deletion or cascade this row
-- away with it, which is exactly what the row exists to survive.
--
-- `bucket` scopes the job to the Worker that created it. A finalizer only acts
-- on jobs for its own bucket, so a staging Worker and the production Worker can
-- never finalize each other's jobs.
--
-- The row holds no email, name, phone, token, password, object key or URL. It
-- is deleted when finalization completes, and when a deletion is abandoned
-- before the account was deleted.
--
-- Access: service_role only (the media Worker's server secret). anon and
-- authenticated have no privileges and RLS is enabled with no policies, so the
-- table is invisible to every client session even if a grant were added by
-- mistake.
--
-- Lifecycle:
--   quarantined          uploads blocked; R2 cleanup running; auth user exists
--   auth_delete_pending  set immediately before the Supabase Auth admin delete
--   auth_deleted         auth user confirmed gone; awaiting finalization
--   cleanup_failed       a finalization attempt failed; retried by the finalizer
-- (completed or abandoned jobs are deleted, not kept in a terminal state)
--
-- `cleanup_not_before` has no default and is NULL until the finalizer stamps
-- it, on its own Cloudflare clock, the first time it reads the job as
-- `auth_deleted` / `cleanup_failed`: stamp time + 300 s maximum PUT URL lifetime
-- + 60 s bound between the Worker's quarantine check and signing + 120 s safety
-- margin. The database clock takes no part in that guarantee. The
-- `cleanup_not_before >= created_at` check is only a sanity guard against a
-- corrupt stamp.

create table public.account_deletion_jobs (
  user_id uuid primary key,
  bucket text not null,
  status text not null default 'quarantined',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  auth_deleted_at timestamptz,
  cleanup_not_before timestamptz,
  cleanup_attempts integer not null default 0,
  last_error_code text,
  constraint account_deletion_jobs_bucket_nonempty
    check (btrim(bucket) <> ''),
  constraint account_deletion_jobs_status_valid
    check (status in ('quarantined', 'auth_delete_pending', 'auth_deleted', 'cleanup_failed')),
  constraint account_deletion_jobs_auth_deleted_consistent
    check ((status in ('auth_deleted', 'cleanup_failed')) = (auth_deleted_at is not null)),
  constraint account_deletion_jobs_stamp_only_after_auth_delete
    check (cleanup_not_before is null or status in ('auth_deleted', 'cleanup_failed')),
  constraint account_deletion_jobs_stamp_sane
    check (cleanup_not_before is null or cleanup_not_before >= created_at),
  constraint account_deletion_jobs_attempts_nonnegative
    check (cleanup_attempts >= 0),
  constraint account_deletion_jobs_error_code_format
    check (last_error_code is null or last_error_code ~ '^[a-z_]{1,64}$')
);

create index account_deletion_jobs_finalizer_idx
  on public.account_deletion_jobs (bucket, status, cleanup_not_before);

create index account_deletion_jobs_reconcile_idx
  on public.account_deletion_jobs (bucket, status, updated_at);

create trigger account_deletion_jobs_updated_at
  before update on public.account_deletion_jobs
  for each row execute function public.set_updated_at();

alter table public.account_deletion_jobs enable row level security;

revoke all on table public.account_deletion_jobs from public;
revoke all on table public.account_deletion_jobs from anon;
revoke all on table public.account_deletion_jobs from authenticated;
grant select, insert, update, delete on table public.account_deletion_jobs to service_role;
$migration_20260913000100$;
    end if;
    results := results || jsonb_build_object(
      'ok', true,
      'check', 'install: 20260913000100_account_deletion_jobs.sql',
      'detail', case when pre_jobs_table_exists then 'skipped: table already present' else 'installed' end);

    -- -------------------------------------------------------------------------
    -- 1b. The job table is server-only and cannot hold an invalid state
    -- -------------------------------------------------------------------------
    stage := 'checking the deletion job table';

    select c.relrowsecurity into flag from pg_class c where c.oid = 'public.account_deletion_jobs'::regclass;
    select count(*) into affected from pg_policy where polrelid = 'public.account_deletion_jobs'::regclass;
    results := results || jsonb_build_object(
      'ok', coalesce(flag, false) and affected = 0,
      'check', 'jobs: row level security is enabled and there are no policies',
      'detail', format('rls=%s policies=%s', coalesce(flag::text, 'null'), affected));

    select string_agg(format('%s:%s', role_name, privilege), ', ')
    into detail_text
    from unnest(array['anon', 'authenticated']) as role_name,
         unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as privilege
    where has_table_privilege(role_name, 'public.account_deletion_jobs', privilege);
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'jobs: anon and authenticated have no privilege on the table',
      'detail', coalesce('granted: ' || detail_text, 'none'));

    results := results || jsonb_build_object(
      'ok', has_table_privilege('service_role', 'public.account_deletion_jobs', 'SELECT')
        and has_table_privilege('service_role', 'public.account_deletion_jobs', 'INSERT')
        and has_table_privilege('service_role', 'public.account_deletion_jobs', 'UPDATE')
        and has_table_privilege('service_role', 'public.account_deletion_jobs', 'DELETE'),
      'check', 'jobs: service_role can select, insert, update and delete');

    select count(*) into affected
    from pg_constraint where conrelid = 'public.account_deletion_jobs'::regclass and contype = 'f';
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'jobs: no foreign key, so a job cannot block or be cascaded by the deletion',
      'detail', affected || ' foreign keys');

    if exists (
      select 1 from jsonb_array_elements(results) e
      where not (e ? 'info') and not coalesce((e ->> 'ok')::boolean, false)
    ) then
      raise exception 'the deletion job table is not shaped as required';
    end if;

    -- -------------------------------------------------------------------------
    -- 2. Two synthetic accounts with data in every owned table
    -- -------------------------------------------------------------------------
    stage := 'creating test accounts';

    insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
    values
      (user_a, 'a' || test_email_domain, '{"name":"Deletion A"}'::jsonb, now(), now()),
      (user_b, 'b' || test_email_domain, '{"name":"Deletion B"}'::jsonb, now(), now());

    select count(*) into affected from public.profiles where id = any(test_ids);
    results := results || jsonb_build_object(
      'ok', affected = 2,
      'check', 'setup: on_auth_user_created created both profiles',
      'detail', affected || ' of 2');

    begin
      insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
      values (user_a::text, user_a, jsonb_build_object('sub', user_a::text, 'email', 'a' || test_email_domain), 'email', now(), now(), now());
      results := results || jsonb_build_object('info', true, 'check', 'setup: synthetic auth.identities row created');
    exception when others then
      results := results || jsonb_build_object('info', true, 'check', 'setup: synthetic auth.identities row skipped', 'detail', sqlstate);
    end;

    begin
      insert into auth.sessions (id, user_id, created_at, updated_at)
      values (gen_random_uuid(), user_a, now(), now());
      results := results || jsonb_build_object('info', true, 'check', 'setup: synthetic auth.sessions row created');
    exception when others then
      results := results || jsonb_build_object('info', true, 'check', 'setup: synthetic auth.sessions row skipped', 'detail', sqlstate);
    end;

    stage := 'creating owned rows';

    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, status)
    values
      (media_avatar, user_a, 'broker-wallet-media', format('profiles/%s/%s.jpg', user_a, media_avatar), 'image', 'image/jpeg', 'ready'),
      (media_thumb, user_a, 'broker-wallet-media', format('profiles/%s/%s.jpg', user_a, media_thumb), 'image', 'image/jpeg', 'ready'),
      (media_logo, user_a, 'broker-wallet-media', format('profiles/%s/%s.png', user_a, media_logo), 'image', 'image/png', 'ready');
    update public.media_objects set thumbnail_media_id = media_thumb where id = media_avatar;
    update public.profiles set profile_media_id = media_avatar where id = user_a;
    insert into public.profile_media (profile_id, media_id, role) values (user_a, media_avatar, 'avatar');

    insert into public.offers (id, owner_id, offer_type) values (offer_a, user_a, 'sell'), (offer_b, user_b, 'rent');
    insert into public.offer_areas (offer_id, area) values (offer_a, 'Validation Area');
    insert into public.offer_media (offer_id, media_id) values (offer_a, media_thumb);
    insert into public.requests (id, owner_id, request_type) values (request_a, user_a, 'rent');
    insert into public.request_areas (request_id, area) values (request_a, 'Validation Area');
    insert into public.owners (id, owner_id, name) values (owner_a, user_a, 'Validation Owner');
    insert into public.offices (owner_id, office_name) values (user_a, 'Validation Office');
    insert into public.brokers (owner_id, name) values (user_a, 'Validation Broker');
    insert into public.watchmen (owner_id, name) values (user_a, 'Validation Watchman');
    insert into public.quotations (id, owner_id, property_title, office_logo_media_id)
    values (quotation_a, user_a, 'Validation Quotation', media_logo);
    insert into public.quotation_downpayments (quotation_id, method, sequence_number, amount)
    values (quotation_a, 'cash', 1, 1);

    insert into public.favorite_offers (owner_id, target_id) values (user_a, offer_b), (user_b, offer_a);
    insert into public.feedback (owner_id, rating) values (user_a, 5);
    insert into public.push_devices (owner_id, token_value, token_hash, platform)
    values (user_a, 'validation-token', 'validation-hash-' || user_a, 'android');
    insert into public.idempotency_keys (owner_id, key, operation) values (user_a, 'validation', 'validation');
    insert into public.usage_counters (owner_id, section) values (user_a, 'offers');
    insert into public.revenuecat_entitlements (user_id, entitlement_id) values (user_a, 'validation');

    insert into public.notifications (id, recipient_id, title, body, category, sender_user_id, offer_id)
    values
      (note_to_a, user_a, 'Validation', 'To A', 'system', user_b, offer_b),
      (note_from_a, user_b, 'Validation', 'From A', 'match', user_a, offer_a);
    insert into public.audit_logs (id, actor_id, target_user_id, action)
    values
      (audit_by_a, user_a, user_a, 'validation.self'),
      (audit_by_b, user_b, user_a, 'validation.other');

    results := results || jsonb_build_object('ok', true, 'check', 'setup: rows created in every owned table');

    -- -------------------------------------------------------------------------
    -- 2b. The deletion job for A, created the way the Worker creates it
    -- -------------------------------------------------------------------------
    stage := 'exercising the deletion job table';

    insert into public.account_deletion_jobs (user_id, bucket) values (user_a, 'validation-bucket');
    select format('status=%s stamp=%s', status, coalesce(cleanup_not_before::text, 'null'))
    into detail_text
    from public.account_deletion_jobs where user_id = user_a;
    results := results || jsonb_build_object(
      'ok', detail_text = 'status=quarantined stamp=null',
      'check', 'jobs: a new job is quarantined and has no cleanup_not_before until the finalizer stamps it',
      'detail', detail_text);

    begin
      insert into public.account_deletion_jobs (user_id) values (gen_random_uuid());
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: a job must name its bucket', 'detail', 'accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '23502', 'check', 'jobs: a job must name its bucket', 'detail', sqlstate);
    end;

    begin
      update public.account_deletion_jobs set cleanup_not_before = now() + interval '8 minutes' where user_id = user_a;
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: cleanup_not_before cannot be stamped before the auth user is deleted', 'detail', 'accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '23514', 'check', 'jobs: cleanup_not_before cannot be stamped before the auth user is deleted', 'detail', sqlstate);
    end;

    begin
      insert into public.account_deletion_jobs (user_id, bucket) values (user_a, 'validation-bucket');
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: one job per account (primary key)', 'detail', 'duplicate accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '23505', 'check', 'jobs: one job per account (primary key)', 'detail', sqlstate);
    end;

    begin
      update public.account_deletion_jobs set status = 'finished' where user_id = user_a;
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: an unknown status is rejected', 'detail', 'accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '23514', 'check', 'jobs: an unknown status is rejected', 'detail', sqlstate);
    end;

    begin
      update public.account_deletion_jobs set status = 'auth_deleted' where user_id = user_a;
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: auth_deleted requires auth_deleted_at', 'detail', 'accepted');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '23514', 'check', 'jobs: auth_deleted requires auth_deleted_at', 'detail', sqlstate);
    end;

    begin
      perform set_config('request.jwt.claims', json_build_object('sub', user_a, 'role', 'authenticated')::text, true);
      set local role authenticated;
      perform count(*) from public.account_deletion_jobs;
      set local role none;
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: a signed-in client cannot read the table, even its own row', 'detail', 'read allowed');
    exception when others then
      results := results || jsonb_build_object(
        'ok', sqlstate = '42501', 'check', 'jobs: a signed-in client cannot read the table, even its own row', 'detail', sqlstate);
    end;
    perform set_config('request.jwt.claims', '', true);

    update public.account_deletion_jobs set status = 'auth_delete_pending' where user_id = user_a;

    -- -------------------------------------------------------------------------
    -- 3. Delete account A the way Supabase Auth's admin delete does
    -- -------------------------------------------------------------------------
    stage := 'deleting account A';

    if pg_has_role(current_user, 'supabase_auth_admin', 'MEMBER') then
      set local role supabase_auth_admin;
      deleted_as := 'supabase_auth_admin';
    else
      deleted_as := current_user;
    end if;

    begin
      delete from auth.users where id = user_a;
      get diagnostics affected = row_count;
      set local role none;
      results := results || jsonb_build_object(
        'ok', affected = 1,
        'check', 'delete: auth.users row for A deleted without a foreign key or trigger error',
        'detail', format('%s row(s) as %s', affected, deleted_as));
    exception when others then
      set local role none;
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'delete: auth.users row for A deleted without a foreign key or trigger error',
        'detail', format('as %s: %s: %s', deleted_as, sqlstate, sqlerrm));
      raise exception 'deletion failed; nothing further can be checked';
    end;

    -- -------------------------------------------------------------------------
    -- 4. What A owned is gone
    -- -------------------------------------------------------------------------
    stage := 'checking deleted data';

    select string_agg(format('%s=%s', name, n), ', ')
    into detail_text
    from (
      select 'profiles' as name, count(*) as n from public.profiles where id = user_a
      union all select 'media_objects', count(*) from public.media_objects where owner_id = user_a
      union all select 'profile_media', count(*) from public.profile_media where profile_id = user_a
      union all select 'offers', count(*) from public.offers where owner_id = user_a
      union all select 'offer_areas', count(*) from public.offer_areas where offer_id = offer_a
      union all select 'offer_media', count(*) from public.offer_media where offer_id = offer_a
      union all select 'requests', count(*) from public.requests where owner_id = user_a
      union all select 'request_areas', count(*) from public.request_areas where request_id = request_a
      union all select 'owners', count(*) from public.owners where owner_id = user_a
      union all select 'offices', count(*) from public.offices where owner_id = user_a
      union all select 'brokers', count(*) from public.brokers where owner_id = user_a
      union all select 'watchmen', count(*) from public.watchmen where owner_id = user_a
      union all select 'quotations', count(*) from public.quotations where owner_id = user_a
      union all select 'quotation_downpayments', count(*) from public.quotation_downpayments where quotation_id = quotation_a
      union all select 'favorite_offers(by A)', count(*) from public.favorite_offers where owner_id = user_a
      union all select 'favorite_offers(on A offer)', count(*) from public.favorite_offers where target_id = offer_a
      union all select 'feedback', count(*) from public.feedback where owner_id = user_a
      union all select 'push_devices', count(*) from public.push_devices where owner_id = user_a
      union all select 'idempotency_keys', count(*) from public.idempotency_keys where owner_id = user_a
      union all select 'usage_counters', count(*) from public.usage_counters where owner_id = user_a
      union all select 'revenuecat_entitlements', count(*) from public.revenuecat_entitlements where user_id = user_a
      union all select 'notifications(to A)', count(*) from public.notifications where recipient_id = user_a
      union all select 'auth.identities', count(*) from auth.identities where user_id = user_a
      union all select 'auth.sessions', count(*) from auth.sessions where user_id = user_a
    ) counts
    where n > 0;
    results := results || jsonb_build_object(
      'ok', detail_text is null,
      'check', 'cascade: A''s profile, media metadata, listings, quotations, favorites, feedback, devices, counters, entitlements, notifications and auth rows are gone',
      'detail', coalesce('left behind: ' || detail_text, 'nothing left behind'));

    select format('exists=%s status=%s', count(*), coalesce(max(status), 'none'))
    into detail_text
    from public.account_deletion_jobs where user_id = user_a;
    results := results || jsonb_build_object(
      'ok', detail_text = 'exists=1 status=auth_delete_pending',
      'check', 'jobs: A''s deletion job survives the auth.users deletion, so finalization keeps its authority',
      'detail', detail_text);

    begin
      update public.account_deletion_jobs
      set status = 'auth_deleted', auth_deleted_at = now()
      where user_id = user_a;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1, 'check', 'jobs: the job can move to auth_deleted after the account is gone',
        'detail', affected || ' row(s)');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: the job can move to auth_deleted after the account is gone',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    begin
      update public.account_deletion_jobs
      set cleanup_not_before = now() + interval '480 seconds'
      where user_id = user_a and cleanup_not_before is null;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 1, 'check', 'jobs: the finalizer''s compare-and-set stamp applies once the auth user is gone',
        'detail', affected || ' row(s)');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false, 'check', 'jobs: the finalizer''s compare-and-set stamp applies once the auth user is gone',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- -------------------------------------------------------------------------
    -- 5. What belongs to B survives; references to A are anonymized
    -- -------------------------------------------------------------------------
    stage := 'checking kept data';

    select format('profile=%s offer=%s', count(*) filter (where p.id is not null), (select count(*) from public.offers where id = offer_b))
    into detail_text
    from public.profiles p where p.id = user_b;
    results := results || jsonb_build_object(
      'ok', detail_text = 'profile=1 offer=1',
      'check', 'isolation: account B and B''s own offer are untouched',
      'detail', detail_text);

    select format('exists=%s sender=%s offer=%s',
                  count(*), coalesce(max(sender_user_id::text), 'null'), coalesce(max(offer_id::text), 'null'))
    into detail_text
    from public.notifications where id = note_from_a;
    results := results || jsonb_build_object(
      'ok', detail_text = 'exists=1 sender=null offer=null',
      'check', 'anonymize: B''s notification from A is kept with sender and offer set to NULL',
      'detail', detail_text);

    select string_agg(format('%s actor=%s target=%s', action, coalesce(actor_id::text, 'null'), coalesce(target_user_id::text, 'null')), '; ' order by action)
    into detail_text
    from public.audit_logs where id in (audit_by_a, audit_by_b);
    results := results || jsonb_build_object(
      'ok', detail_text = format('validation.other actor=%s target=null; validation.self actor=null target=null', user_b),
      'check', 'anonymize: audit_logs rows are kept with references to A set to NULL',
      'detail', detail_text);

    -- -------------------------------------------------------------------------
    -- 6. Deleting again is a no-op, not an error
    -- -------------------------------------------------------------------------
    stage := 'repeating the delete';

    begin
      delete from auth.users where id = user_a;
      get diagnostics affected = row_count;
      results := results || jsonb_build_object(
        'ok', affected = 0,
        'check', 'idempotent: deleting the same account again affects nothing and raises nothing',
        'detail', affected || ' row(s)');
    exception when others then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'idempotent: deleting the same account again affects nothing and raises nothing',
        'detail', sqlstate || ': ' || sqlerrm);
    end;

    completed := true;
    raise exception using errcode = 'P0001', message = 'account_deletion_validation_rollback';
  exception when others then
    if not completed then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'validation stopped while ' || stage,
        'detail', sqlstate || ': ' || sqlerrm);
    end if;
  end;

  -- ===========================================================================
  -- 7. Post-checks: everything above was undone
  -- ===========================================================================
  select count(*) into affected
  from auth.users where id = any(test_ids) or email like '%' || test_email_domain;
  select affected + count(*) into affected from public.profiles where id = any(test_ids);
  select affected + count(*) into affected from public.audit_logs where id in (audit_by_a, audit_by_b);
  select affected + count(*) into affected from public.notifications where id in (note_to_a, note_from_a);
  results := results || jsonb_build_object(
    'ok', affected = 0,
    'check', 'post: no test account, profile, audit row or notification remains',
    'detail', affected || ' remaining');

  results := results || jsonb_build_object(
    'ok', (to_regclass('public.account_deletion_jobs') is not null) = pre_jobs_table_exists,
    'check', 'post: account_deletion_jobs is back to its state before the run',
    'detail', case when pre_jobs_table_exists then 'still present (was present)' else 'absent again (was absent)' end);

  if pre_jobs_table_exists then
    execute 'select count(*) from public.account_deletion_jobs where user_id = $1' into affected using user_a;
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'post: no test deletion job remains',
      'detail', affected || ' remaining');
  end if;

  insert into pg_temp.account_deletion_validation_results (seq, result, check_name, detail)
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
  from pg_temp.account_deletion_validation_results;

  insert into pg_temp.account_deletion_validation_results (seq, result, check_name, detail)
  values (
    0,
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end,
    format('ACCOUNT DELETION CASCADE VALIDATION %s: %s passed, %s failed',
           case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures),
    case
      when not completed then 'The run stopped early; see the last FAIL row. Nothing was kept.'
      else 'All changes were rolled back inside the run (see post row); the final ROLLBACK discards this report.'
    end);

  raise notice 'ACCOUNT DELETION CASCADE VALIDATION %: % passed, % failed',
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures;
end;
$validation$;

select seq as "#", result, check_name, detail
from pg_temp.account_deletion_validation_results
order by seq;

rollback;
