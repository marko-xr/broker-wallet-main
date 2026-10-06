BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '60s';

-- All catalog checks run before the migration body changes anything.
DO $preflight$
BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('public.user_active_sessions') IS NOT NULL
     OR to_regclass('public.app_session_claims') IS NOT NULL
     OR to_regprocedure('public.is_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.claim_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.release_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.save_quotation_session_internal(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') IS NOT NULL
     OR to_regprocedure('public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
     )
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public' AND policyname = 'app_session_gate'
     )
  THEN
    RAISE EXCEPTION 'hosted readiness preflight failed';
  END IF;
END;
$preflight$;

-- Exact body of 20261005175500_single_active_app_session.sql follows.

create table public.user_active_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active_session_id uuid not null,
  claimed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A replaced Supabase session may still have a valid access JWT. Keeping its
-- claim here until the user is deleted prevents that session from reclaiming.
create table public.app_session_claims (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  claimed_at timestamptz not null default now()
);
create index app_session_claims_user_id_idx on public.app_session_claims(user_id);

alter table public.user_active_sessions enable row level security;
alter table public.app_session_claims enable row level security;
revoke all on public.user_active_sessions, public.app_session_claims from public, anon, authenticated;
grant select on public.user_active_sessions to authenticated;
create policy user_active_sessions_select_own on public.user_active_sessions
  for select to authenticated using (user_id = (select auth.uid()));
-- Intentionally no client policy or grant for claim history, and no direct
-- INSERT/UPDATE/DELETE grant on active state. Only trusted functions mutate it.

create function public.is_current_app_session()
returns boolean language sql stable security definer set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and (auth.jwt()->>'session_id') is not null
    and exists (
      select 1 from public.user_active_sessions active
      join auth.sessions session on session.id = active.active_session_id
      where active.user_id = (select auth.uid())
        and active.active_session_id = (auth.jwt()->>'session_id')::uuid
        and session.user_id = active.user_id
    );
$function$;
revoke all on function public.is_current_app_session() from public, anon, authenticated;
grant execute on function public.is_current_app_session() to authenticated, service_role;

create function public.claim_current_app_session()
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_session uuid;
begin
  if v_user is null or nullif(auth.jwt()->>'session_id', '') is null then
    raise exception using errcode = '42501', message = 'session_missing';
  end if;
  v_session := (auth.jwt()->>'session_id')::uuid;
  -- Serialize all claims for one account. Lock order is the successful claim
  -- order; the last committed new claim owns the account.
  perform 1 from auth.users where id = v_user for update;
  if not found or not exists (
    select 1 from auth.sessions where id = v_session and user_id = v_user
  ) then
    raise exception using errcode = '42501', message = 'session_missing';
  end if;

  if exists (select 1 from public.app_session_claims where session_id = v_session) then
    if exists (
      select 1 from public.user_active_sessions
      where user_id = v_user and active_session_id = v_session
    ) then
      return true; -- Only the still-active claimant may retry.
    end if;
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;

  insert into public.app_session_claims(session_id, user_id) values (v_session, v_user);
  insert into public.user_active_sessions(user_id, active_session_id)
  values (v_user, v_session)
  on conflict (user_id) do update
    set active_session_id = excluded.active_session_id,
        claimed_at = now(), updated_at = now();
  return true;
end;
$function$;
revoke all on function public.claim_current_app_session() from public, anon, authenticated;
grant execute on function public.claim_current_app_session() to authenticated;

create function public.release_current_app_session()
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_session uuid;
begin
  if v_user is null or nullif(auth.jwt()->>'session_id', '') is null then
    return false;
  end if;
  v_session := (auth.jwt()->>'session_id')::uuid;
  delete from public.user_active_sessions
  where user_id = v_user and active_session_id = v_session;
  return found;
end;
$function$;
revoke all on function public.release_current_app_session() from public, anon, authenticated;
grant execute on function public.release_current_app_session() to authenticated;

-- Keep all existing permissive ownership/business policies. These restrictive
-- policies are ANDed with them for every authenticated app-data operation.
do $block$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles', 'revenuecat_entitlements', 'plan_limits', 'usage_counters',
    'requests', 'request_areas', 'offers', 'offer_areas', 'owners', 'offices',
    'brokers', 'watchmen', 'quotations', 'quotation_downpayments',
    'quotation_government_fees', 'quotation_administrative_fees',
    'media_objects', 'offer_media', 'owner_media', 'quotation_media',
    'profile_media', 'favorite_offers', 'favorite_requests',
    'favorite_owners', 'favorite_offices', 'favorite_brokers',
    'favorite_watchmen', 'feedback', 'notifications', 'push_devices',
    'app_versions', 'idempotency_keys'
  ] loop
    execute format(
      'create policy app_session_gate on public.%I as restrictive for all to authenticated using ((select public.is_current_app_session())) with check ((select public.is_current_app_session()))',
      v_table
    );
  end loop;
end;
$block$;

-- The one client-callable SECURITY DEFINER business RPC bypasses RLS. Keep
-- its implementation intact behind a non-client-callable, session-gated shim.
alter function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  rename to save_quotation_session_internal;
revoke all on function public.save_quotation_session_internal(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
create function public.save_quotation(
  p_quotation_id uuid, p_expected_version bigint, p_header jsonb,
  p_downpayments jsonb, p_government_fees jsonb, p_administrative_fees jsonb
)
returns table (
  quotation_id uuid, resulting_version bigint, outcome text,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = ''
as $function$
begin
  if not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  return query select * from public.save_quotation_session_internal(
    p_quotation_id, p_expected_version, p_header, p_downpayments,
    p_government_fees, p_administrative_fees
  );
end;
$function$;
revoke all on function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  to authenticated;

-- This row is a deliberate exception to the app-data gate: the displaced
-- session must still read its own changed row for Realtime logout detection.
alter publication supabase_realtime add table public.user_active_sessions;

-- Verify the migration's objects and permissions before rolling back.
DO $verify$
BEGIN
  IF to_regclass('public.user_active_sessions') IS NULL
     OR to_regclass('public.app_session_claims') IS NULL
     OR to_regprocedure('public.is_current_app_session()') IS NULL
     OR to_regprocedure('public.claim_current_app_session()') IS NULL
     OR to_regprocedure('public.release_current_app_session()') IS NULL
     OR to_regprocedure('public.save_quotation_session_internal(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') IS NULL
     OR (SELECT count(*) FROM pg_policies
         WHERE schemaname = 'public' AND policyname = 'app_session_gate') <> 32
     OR NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'user_active_sessions'
     )
     OR has_table_privilege('authenticated', 'public.user_active_sessions', 'INSERT')
     OR has_table_privilege('authenticated', 'public.user_active_sessions', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.user_active_sessions', 'DELETE')
     OR has_function_privilege('anon', 'public.claim_current_app_session()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'migration catalog verification failed';
  END IF;
END;
$verify$;

ROLLBACK;

-- A successful rollback restores the original catalog state.
DO $post_rollback$
BEGIN
  IF to_regclass('public.user_active_sessions') IS NOT NULL
     OR to_regclass('public.app_session_claims') IS NOT NULL
     OR to_regprocedure('public.is_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.claim_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.release_current_app_session()') IS NOT NULL
     OR to_regprocedure('public.save_quotation_session_internal(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') IS NOT NULL
     OR to_regprocedure('public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') IS NULL
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public' AND policyname = 'app_session_gate'
     )
     OR EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'user_active_sessions'
     )
  THEN
    RAISE EXCEPTION 'rollback verification failed';
  END IF;
END;
$post_rollback$;

SELECT 'rollback_verified' AS result;