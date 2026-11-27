-- STAGING ONLY. Never add this file to supabase/migrations and never run it on
-- production. It installs the owner's private pre-launch test facility on top of
-- the same versioned production schema, by replacing three constant seams.
--
-- Install (owner step, on the isolated Staging project only):
--   psql -X -v ON_ERROR_STOP=1 -f supabase/staging/subscription_test_mode.sql
--   psql -X -v ON_ERROR_STOP=1 -v staging_ref=<20-char ref> -v test_user=<auth user id> \
--     -f supabase/staging/activate_test_account.sql
-- Remove: supabase/staging/remove_subscription_test_mode.sql
--
-- The facility is inert until activate_test_account.sql writes the staging marker.
-- It never writes a provider record, never deletes a record and never changes
-- usage, except for the separately named reset_usage action.
begin;

do $preflight$
begin
  if current_user <> 'postgres' then
    raise exception 'Run as postgres';
  end if;
  if to_regprocedure('public.subscription_override_entitlement(uuid)') is null then
    raise exception 'The subscription migration is not applied here';
  end if;
  if exists (select 1 from public.subscription_provider_records where environment = 'production') then
    raise exception 'This database holds production subscriptions: it is not a Staging project';
  end if;
end;
$preflight$;

create table public.deployment_environment (
  singleton boolean primary key default true,
  environment text not null,
  project_ref text not null,
  declared_at timestamptz not null default pg_catalog.now(),
  constraint deployment_environment_one_row check (singleton),
  constraint deployment_environment_only_staging check (environment = 'staging'),
  constraint deployment_environment_not_production
    check (project_ref <> 'rbvcnvqpdqrhywcgxkne'),
  constraint deployment_environment_ref_shape check (project_ref ~ '^[a-z0-9]{20}$')
);

create table public.staging_test_allowlist (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  added_at timestamptz not null default pg_catalog.now(),
  note text
);

create table public.staging_test_entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  scenario text not null,
  started_at timestamptz not null default pg_catalog.now(),
  paid_through_at timestamptz not null,
  expires_at timestamptz not null,
  updated_at timestamptz not null default pg_catalog.now(),
  constraint staging_test_scenario_known
    check (scenario in ('plus', 'plus_auto_renew_off', 'expired')),
  constraint staging_test_expiry_bounded
    check (expires_at <= started_at + interval '7 days')
);

create table public.staging_test_audit (
  id bigint generated always as identity primary key,
  user_id uuid,
  action text not null,
  outcome text not null,
  previous_scenario text,
  next_scenario text,
  created_at timestamptz not null default pg_catalog.now()
);

do $lockdown$
declare
  v_table text;
begin
  foreach v_table in array array[
    'deployment_environment', 'staging_test_allowlist',
    'staging_test_entitlements', 'staging_test_audit'
  ] loop
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format(
      'revoke all on public.%I from public, anon, authenticated, service_role', v_table);
  end loop;
end;
$lockdown$;

create function public.subscription_is_staging()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.deployment_environment as d where d.environment = 'staging'
  );
$function$;

create or replace function public.subscription_accepts_sandbox()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.subscription_is_staging();
$function$;

create or replace function public.subscription_override_entitlement(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := pg_catalog.now();
  v_test public.staging_test_entitlements%rowtype;
begin
  if not public.subscription_is_staging() or not exists (
    select 1 from public.staging_test_allowlist as a where a.user_id = p_user
  ) then
    return null;
  end if;
  select t.* into v_test from public.staging_test_entitlements as t
    where t.user_id = p_user and t.expires_at > v_now;
  if not found then
    return null;
  end if;
  if v_test.scenario = 'plus' then
    return pg_catalog.jsonb_build_object(
      'is_plus', true, 'status', 'plus_renewing', 'source', 'test',
      'cycle', 'annual', 'provider', null, 'auto_renew', true, 'had_plus', true,
      'started_at', v_test.started_at, 'paid_through', v_test.expires_at,
      'next_charge_at', null);
  elsif v_test.scenario = 'plus_auto_renew_off' and v_test.paid_through_at > v_now then
    return pg_catalog.jsonb_build_object(
      'is_plus', true, 'status', 'plus_cancel_scheduled', 'source', 'test',
      'cycle', 'monthly', 'provider', null, 'auto_renew', false, 'had_plus', true,
      'started_at', v_test.started_at, 'paid_through', v_test.paid_through_at,
      'next_charge_at', null);
  end if;
  return pg_catalog.jsonb_build_object(
    'is_plus', false, 'status', 'free', 'source', 'test', 'cycle', null,
    'provider', null, 'auto_renew', false, 'had_plus', true,
    'started_at', v_test.started_at, 'paid_through', v_test.paid_through_at,
    'next_charge_at', null);
end;
$function$;

create or replace function public.subscription_test_mode_state(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_available boolean;
  v_test public.staging_test_entitlements%rowtype;
begin
  v_available := public.subscription_is_staging() and exists (
    select 1 from public.staging_test_allowlist as a where a.user_id = p_user);
  if v_available then
    select t.* into v_test from public.staging_test_entitlements as t
      where t.user_id = p_user and t.expires_at > pg_catalog.now();
  end if;
  return pg_catalog.jsonb_build_object(
    'available', v_available,
    'scenario', case when v_available then v_test.scenario end,
    'expires_at', case when v_available then v_test.expires_at end);
end;
$function$;

-- p_user is the account the Edge Function verified from the caller's JWT.
create function public.staging_test_control(p_user uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_previous text;
  v_next text;
  v_now timestamptz := pg_catalog.now();
begin
  if not public.subscription_is_staging() then
    raise exception using errcode = 'PBT01', message = 'not_staging';
  end if;
  if p_user is null or p_action is null or p_action not in (
    'status', 'plus_on', 'plus_off', 'auto_renew_off', 'expired', 'reset_usage'
  ) then
    raise exception using errcode = 'PBT03', message = 'invalid_action';
  end if;

  if not exists (select 1 from public.staging_test_allowlist as a where a.user_id = p_user) then
    insert into public.staging_test_audit (user_id, action, outcome)
      values (p_user, p_action, 'rejected_not_allowlisted');
    return pg_catalog.jsonb_build_object('ok', false, 'code', 'not_allowlisted');
  end if;

  perform public.subscription_lock(p_user);
  select t.scenario into v_previous from public.staging_test_entitlements as t
    where t.user_id = p_user;
  v_next := v_previous;

  if p_action = 'plus_on' then
    v_next := 'plus';
  elsif p_action = 'auto_renew_off' then
    v_next := 'plus_auto_renew_off';
  elsif p_action = 'expired' then
    v_next := 'expired';
  elsif p_action = 'plus_off' then
    v_next := null;
    delete from public.staging_test_entitlements as t where t.user_id = p_user;
  elsif p_action = 'reset_usage' then
    -- Fixture reset for the allowlisted account only. Records stay.
    delete from public.usage_events as e where e.owner_id = p_user;
    delete from public.item_edit_usage as e where e.owner_id = p_user;
    delete from public.item_media_grants as g where g.owner_id = p_user;
    update public.usage_counters as u set lifetime_created_count = 0
      where u.owner_id = p_user;
  end if;

  if p_action in ('plus_on', 'auto_renew_off', 'expired') then
    insert into public.staging_test_entitlements as t (
      user_id, scenario, started_at, paid_through_at, expires_at)
    values (
      p_user, v_next, v_now,
      case v_next
        when 'plus_auto_renew_off' then v_now + interval '2 hours'
        when 'expired' then v_now
        else v_now + interval '72 hours' end,
      v_now + interval '72 hours')
    on conflict (user_id) do update set
      scenario = excluded.scenario,
      started_at = excluded.started_at,
      paid_through_at = excluded.paid_through_at,
      expires_at = excluded.expires_at,
      updated_at = v_now;
  end if;

  if p_action <> 'status' then
    insert into public.staging_test_audit (
      user_id, action, outcome, previous_scenario, next_scenario)
    values (p_user, p_action, 'applied', v_previous, v_next);
  end if;
  return pg_catalog.jsonb_build_object(
    'ok', true, 'state', public.subscription_state_for(p_user));
end;
$function$;

revoke all on function public.subscription_is_staging() from public, anon, authenticated, service_role;
revoke all on function public.subscription_accepts_sandbox() from public, anon, authenticated, service_role;
revoke all on function public.subscription_override_entitlement(uuid) from public, anon, authenticated, service_role;
revoke all on function public.subscription_test_mode_state(uuid) from public, anon, authenticated, service_role;
revoke all on function public.staging_test_control(uuid, text) from public, anon, authenticated;
grant execute on function public.staging_test_control(uuid, text) to service_role;

commit;
