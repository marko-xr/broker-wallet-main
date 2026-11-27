-- Server-authoritative subscriptions, lifetime creation quotas and per-item
-- Free edit limits. SOURCE ONLY until the owner approves a hosted apply.
--
-- What this migration decides (and Flutter never does):
--   * Whether an account has Plus: subscription_entitlement(), from verified
--     provider records, on the database clock. Unknown is never Plus.
--   * Free: 5 successful creations per quota_section for the life of the
--     account. Deleting never gives one back.
--   * Free: 3 successful content edits per item. Plus-period edits do not use
--     them, and used ones never reset.
--   * Not Plus and any section above 5 (typically after Plus ended): the whole
--     account is read-only for creation and content edits. Delete stays.
--
-- ROLLOUT IS TWO STEPS, so no app build breaks:
--   1. This migration is ADDITIVE. Existing builds keep their direct writes and
--      behave exactly as before; new builds can already use the new functions.
--   2. Once every build in use has SUBSCRIPTION_BACKEND=true and the Worker is
--      deployed, the owner runs public.subscription_cutover(): it records the
--      baseline, closes the direct client writes and switches on the Quotation
--      and Toolkit charges, in one transaction. public.subscription_cutback()
--      reverses it without losing any usage history.
--
-- After cutover:
--   * The six core tables, their area tables and the Quotation aggregate have
--     no direct client INSERT or content UPDATE. The only client write left is
--     the soft delete, restricted to stamping deleted_at once.
--   * create_core_entity, update_core_entity and save_quotation do the write
--     and the count in ONE transaction, under a per-account advisory lock.
--   * Toolkit documents are charged by triggers on toolkit_documents, so the
--     service-role functions the Worker calls cannot skip the count.
--
-- The Staging test facility is NOT part of this schema. It is a separate overlay
-- (supabase/staging/) installed only on an isolated Staging project. Here its
-- three seams are constants that can grant nothing.
--
-- search_path is empty everywhere; every reference is schema-qualified. No
-- begin/commit here, so a rollback-only validation can include this file.

do $owner_check$
begin
  if current_user <> 'postgres' then
    raise exception 'The subscription migration must run as postgres';
  end if;
end;
$owner_check$;

-- ---------------------------------------------------------------------------
-- Approved Free limits (the existing, previously empty configuration table)
-- ---------------------------------------------------------------------------

insert into public.plan_limits (plan_code, section, counter_basis, limit_value, reset_period)
select 'free', s.section, 'lifetime_created', 5, 'lifetime'
from pg_catalog.unnest(pg_catalog.enum_range(null::public.quota_section)) as s(section)
on conflict (plan_code, section) do update
  set counter_basis = excluded.counter_basis,
      limit_value = excluded.limit_value,
      reset_period = excluded.reset_period;

-- ---------------------------------------------------------------------------
-- Provider-neutral subscription records and their event log
-- ---------------------------------------------------------------------------

create table public.subscription_provider_records (
  id uuid primary key default gen_random_uuid(),
  -- SET NULL: a late event for a deleted account can never re-attach it.
  user_id uuid references public.profiles(id) on delete set null,
  provider text not null,
  provider_subscription_id text not null,
  product_id text,
  billing_cycle text,
  state text not null,
  auto_renew boolean not null default false,
  environment text not null,
  started_at timestamptz,
  paid_through_at timestamptz,
  grace_until timestamptz,
  last_event_at timestamptz not null,
  last_event_id text not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint subscription_records_provider_known
    check (provider in ('google_play', 'app_store', 'tap')),
  constraint subscription_records_external_id_clean
    check (pg_catalog.btrim(provider_subscription_id) <> ''
           and pg_catalog.char_length(provider_subscription_id) <= 255),
  constraint subscription_records_cycle_known
    check (billing_cycle is null or billing_cycle in ('monthly', 'annual')),
  -- Cancellation, billing trouble, expiry, refund and revocation stay separate.
  constraint subscription_records_state_known
    check (state in ('active', 'cancel_scheduled', 'billing_issue', 'paused',
                     'expired', 'refunded', 'revoked', 'unknown')),
  constraint subscription_records_environment_known
    check (environment in ('production', 'sandbox')),
  constraint subscription_records_provider_unique
    unique (provider, provider_subscription_id)
);
create index subscription_records_user_idx
  on public.subscription_provider_records (user_id, paid_through_at desc);

create table public.billing_events (
  provider text not null,
  event_id text not null,
  event_type text not null,
  event_at timestamptz not null,
  received_at timestamptz not null default pg_catalog.now(),
  user_id uuid references public.profiles(id) on delete set null,
  provider_subscription_id text,
  outcome text not null,
  -- A digest proves what was received without keeping customer data.
  payload_sha256 text,
  primary key (provider, event_id),
  constraint billing_events_provider_known
    check (provider in ('google_play', 'app_store', 'tap')),
  constraint billing_events_outcome_known
    check (outcome in ('processing', 'processed', 'stale', 'no_account',
                       'ownership_conflict', 'ignored')),
  constraint billing_events_digest_format
    check (payload_sha256 is null or payload_sha256 ~ '^[0-9a-f]{64}$')
);
create index billing_events_user_idx on public.billing_events (user_id, event_at desc);

-- ---------------------------------------------------------------------------
-- Usage history
-- ---------------------------------------------------------------------------

create table public.item_edit_usage (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  section public.quota_section not null,
  item_id uuid not null,
  free_edits_used smallint not null default 0,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (owner_id, section, item_id),
  constraint item_edit_usage_range check (free_edits_used between 0 and 3)
);

create table public.usage_events (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  section public.quota_section not null,
  item_id uuid not null,
  kind text not null,
  request_id uuid,
  charged_free_allowance boolean not null,
  plan_at_event text not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint usage_events_kind_known check (kind in ('create', 'edit')),
  constraint usage_events_plan_known check (plan_at_event in ('free', 'plus', 'test_plus'))
);
-- One charge per created item, and one result per save request.
create unique index usage_events_one_create_idx
  on public.usage_events (owner_id, section, item_id) where kind = 'create';
create unique index usage_events_request_idx
  on public.usage_events (owner_id, request_id) where request_id is not null;

-- Which media a charged save may change through the Worker. One save is one
-- edit however many files it adds or removes; a null media_id covers a file
-- whose id is not known at save time (the land plan) for a short window.
create table public.item_media_grants (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  section public.quota_section not null,
  item_id uuid not null,
  media_id uuid,
  expires_at timestamptz not null
);
create unique index item_media_grants_one_idx on public.item_media_grants (
  owner_id, section, item_id,
  coalesce(media_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

-- ---------------------------------------------------------------------------
-- Rollout state
-- ---------------------------------------------------------------------------

create table public.subscription_rollout (
  singleton boolean primary key default true,
  enforced boolean not null default false,
  baseline text,
  changed_at timestamptz not null default pg_catalog.now(),
  constraint subscription_rollout_one_row check (singleton),
  constraint subscription_rollout_baseline_known
    check (baseline is null or baseline in ('actual', 'capped'))
);
insert into public.subscription_rollout (singleton) values (true);

create table public.subscription_rollout_log (
  id bigint generated always as identity primary key,
  action text not null,
  baseline text,
  accounts_over_limit bigint,
  at timestamptz not null default pg_catalog.now(),
  constraint subscription_rollout_log_action_known check (action in ('cutover', 'cutback'))
);

-- ---------------------------------------------------------------------------
-- Deny by default: none of these tables is reachable by a client role
-- ---------------------------------------------------------------------------

do $lockdown$
declare
  v_table text;
begin
  foreach v_table in array array[
    'subscription_provider_records', 'billing_events', 'item_edit_usage',
    'usage_events', 'item_media_grants', 'subscription_rollout', 'subscription_rollout_log'
  ] loop
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format(
      'revoke all on public.%I from public, anon, authenticated, service_role', v_table);
  end loop;
end;
$lockdown$;

-- ---------------------------------------------------------------------------
-- Entitlement and access
-- ---------------------------------------------------------------------------

-- The three points where the Staging overlay attaches. In this schema they are
-- constants: no sandbox purchase counts, no override exists, no test control.
create function public.subscription_accepts_sandbox()
returns boolean
language sql
stable
set search_path = ''
as $function$
  select false;
$function$;

create function public.subscription_override_entitlement(p_user uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select null::jsonb;
$function$;

create function public.subscription_test_mode_state(p_user uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select '{"available": false, "scenario": null, "expires_at": null}'::jsonb;
$function$;

create function public.subscription_enforced()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((select r.enforced from public.subscription_rollout as r), false);
$function$;

-- The one definition of "has Plus". Time is the database's own.
create function public.subscription_entitlement(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := pg_catalog.now();
  v_sandbox boolean := public.subscription_accepts_sandbox();
  v_override jsonb := public.subscription_override_entitlement(p_user);
  v_record public.subscription_provider_records%rowtype;
  v_had_plus boolean;
begin
  if v_override is not null then
    return v_override;
  end if;

  -- A sandbox purchase never grants anything on a production database.
  select r.* into v_record
  from public.subscription_provider_records as r
  where r.user_id = p_user
    and (r.environment = 'production' or (v_sandbox and r.environment = 'sandbox'))
    and (
      (r.state in ('active', 'cancel_scheduled', 'paused') and r.paid_through_at > v_now)
      or (r.state = 'billing_issue'
          and greatest(r.paid_through_at, r.grace_until) > v_now)
    )
  order by greatest(r.paid_through_at, r.grace_until) desc nulls last, r.id
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'is_plus', true,
      'status', case
        when v_record.state = 'billing_issue' then 'payment_issue'
        when v_record.state = 'active' and v_record.auto_renew then 'plus_renewing'
        else 'plus_cancel_scheduled' end,
      'source', 'provider',
      'cycle', v_record.billing_cycle,
      'provider', v_record.provider,
      'auto_renew', v_record.auto_renew and v_record.state = 'active',
      'had_plus', true,
      'started_at', v_record.started_at,
      'paid_through', v_record.paid_through_at,
      'next_charge_at', case
        when v_record.state = 'active' and v_record.auto_renew then v_record.paid_through_at
      end);
  end if;

  select exists (
    select 1 from public.subscription_provider_records as r
    where r.user_id = p_user and r.state <> 'unknown'
      and (r.environment = 'production' or (v_sandbox and r.environment = 'sandbox'))
  ) into v_had_plus;

  return pg_catalog.jsonb_build_object(
    'is_plus', false, 'status', 'free', 'source', 'none', 'cycle', null,
    'provider', null, 'auto_renew', false, 'had_plus', v_had_plus,
    'started_at', null, 'paid_through', null, 'next_charge_at', null);
end;
$function$;

-- Entitlement plus the account-wide consequence of the usage history.
create function public.subscription_access(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_entitlement jsonb := public.subscription_entitlement(p_user);
  v_is_plus boolean := (v_entitlement ->> 'is_plus')::boolean;
  v_over boolean;
begin
  select exists (
    select 1
    from public.usage_counters as u
    join public.plan_limits as l on l.plan_code = 'free' and l.section = u.section
    where u.owner_id = p_user and u.lifetime_created_count > l.limit_value
  ) into v_over;

  if v_is_plus then
    return v_entitlement || pg_catalog.jsonb_build_object('read_only', false);
  end if;
  return v_entitlement || pg_catalog.jsonb_build_object(
    'read_only', v_over,
    'status', case
      when v_over then 'expired_over_limit'
      when (v_entitlement ->> 'had_plus')::boolean then 'expired_within_free'
      else 'free' end);
end;
$function$;

-- Every quota decision of one account runs under this lock.
create function public.subscription_lock(p_user uuid)
returns void
language sql
set search_path = ''
as $function$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('subscription_quota:' || p_user::text, 0));
$function$;

create function public.subscription_plan_label(p_access jsonb)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when not (p_access ->> 'is_plus')::boolean then 'free'
    when p_access ->> 'source' = 'test' then 'test_plus'
    else 'plus' end;
$function$;

-- ---------------------------------------------------------------------------
-- Charging: inside the caller's transaction, so a failed write charges nothing
-- ---------------------------------------------------------------------------

create function public.subscription_charge_create(
  p_user uuid, p_section public.quota_section, p_item uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_access jsonb;
  v_is_plus boolean;
  v_limit integer;
  v_used bigint;
begin
  perform public.subscription_lock(p_user);
  if exists (
    select 1 from public.usage_events as e
    where e.owner_id = p_user and e.section = p_section
      and e.item_id = p_item and e.kind = 'create'
  ) then
    return;
  end if;

  v_access := public.subscription_access(p_user);
  v_is_plus := (v_access ->> 'is_plus')::boolean;
  if not v_is_plus and (v_access ->> 'read_only')::boolean then
    raise exception using errcode = 'PBQ03', message = 'account_read_only',
      detail = p_section::text;
  end if;

  select l.limit_value into v_limit from public.plan_limits as l
    where l.plan_code = 'free' and l.section = p_section;
  if v_limit is null then
    -- A missing limit never means unlimited.
    raise exception using errcode = 'PBQ06', message = 'quota_unavailable';
  end if;

  insert into public.usage_counters (owner_id, section)
    values (p_user, p_section) on conflict (owner_id, section) do nothing;
  select u.lifetime_created_count into v_used from public.usage_counters as u
    where u.owner_id = p_user and u.section = p_section for update;
  if not v_is_plus and v_used >= v_limit then
    raise exception using errcode = 'PBQ01', message = 'creation_limit_reached',
      detail = p_section::text;
  end if;

  update public.usage_counters as u
    set lifetime_created_count = u.lifetime_created_count + 1
    where u.owner_id = p_user and u.section = p_section;
  insert into public.usage_events (
    owner_id, section, item_id, kind, charged_free_allowance, plan_at_event)
  values (p_user, p_section, p_item, 'create', not v_is_plus,
          public.subscription_plan_label(v_access));
end;
$function$;

create function public.subscription_charge_edit(
  p_user uuid, p_section public.quota_section, p_item uuid, p_request uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_access jsonb;
  v_is_plus boolean;
  v_used integer;
begin
  perform public.subscription_lock(p_user);
  v_access := public.subscription_access(p_user);
  v_is_plus := (v_access ->> 'is_plus')::boolean;
  if not v_is_plus and (v_access ->> 'read_only')::boolean then
    raise exception using errcode = 'PBQ03', message = 'account_read_only',
      detail = p_section::text;
  end if;

  if v_is_plus then
    select e.free_edits_used into v_used from public.item_edit_usage as e
      where e.owner_id = p_user and e.section = p_section and e.item_id = p_item;
    insert into public.usage_events (
      owner_id, section, item_id, kind, request_id, charged_free_allowance, plan_at_event)
    values (p_user, p_section, p_item, 'edit', p_request, false,
            public.subscription_plan_label(v_access));
    return coalesce(v_used, 0);
  end if;

  insert into public.item_edit_usage (owner_id, section, item_id)
    values (p_user, p_section, p_item)
    on conflict (owner_id, section, item_id) do nothing;
  select e.free_edits_used into v_used from public.item_edit_usage as e
    where e.owner_id = p_user and e.section = p_section and e.item_id = p_item
    for update;
  if v_used >= 3 then
    raise exception using errcode = 'PBQ02', message = 'edit_limit_reached',
      detail = p_section::text;
  end if;
  update public.item_edit_usage as e
    set free_edits_used = e.free_edits_used + 1, updated_at = pg_catalog.now()
    where e.owner_id = p_user and e.section = p_section and e.item_id = p_item;
  insert into public.usage_events (
    owner_id, section, item_id, kind, request_id, charged_free_allowance, plan_at_event)
  values (p_user, p_section, p_item, 'edit', p_request, true, 'free');
  return v_used + 1;
end;
$function$;

create function public.subscription_grant_media(
  p_user uuid, p_section public.quota_section, p_item uuid,
  p_media uuid[], p_ttl interval)
returns void
language sql
security definer
set search_path = ''
as $function$
  insert into public.item_media_grants (owner_id, section, item_id, media_id, expires_at)
  -- A null id covers files whose id is not known yet, so it stays short-lived.
  select p_user, p_section, p_item, m.media_id,
         pg_catalog.now() + case when m.media_id is null
                                 then least(p_ttl, interval '1 hour') else p_ttl end
  from pg_catalog.unnest(p_media) as m(media_id)
  on conflict (owner_id, section, item_id,
               coalesce(media_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set expires_at = greatest(public.item_media_grants.expires_at, excluded.expires_at);
$function$;

-- ---------------------------------------------------------------------------
-- The six core entities: one atomic create and one atomic update
-- ---------------------------------------------------------------------------

-- The exact columns a client may set. Everything else is server-owned.
create function public.subscription_entity_columns(p_section text)
returns text[]
language sql
immutable
set search_path = ''
as $function$
  select case p_section
    when 'requests' then array[
      'request_type', 'selected_city', 'location_text', 'phone_number', 'country_code',
      'phone_e164', 'min_price', 'max_price', 'square_footage', 'notes', 'property_type',
      'specific_property_type', 'rooms', 'bathrooms', 'status']
    when 'offers' then array[
      'offer_type', 'selected_city', 'location_text', 'phone_number', 'country_code',
      'phone_e164', 'min_price', 'max_price', 'square_footage', 'notes', 'property_type',
      'specific_property_type', 'rooms', 'bathrooms', 'pickup_location_text',
      'pickup_latitude', 'pickup_longitude', 'pickup_address',
      'legacy_uploaded_file_name', 'status']
    when 'owners' then array[
      'name', 'phone_number', 'country_code', 'phone_e164', 'property_type_text',
      'property_location', 'notes', 'pickup_location_text', 'pickup_latitude',
      'pickup_longitude', 'pickup_address', 'legacy_uploaded_file_name']
    when 'offices' then array[
      'office_name', 'manager_name', 'country_code', 'phone_number', 'phone_e164',
      'office_location', 'notes', 'pickup_location_text', 'pickup_latitude',
      'pickup_longitude', 'pickup_address']
    when 'brokers' then array['name', 'country_code', 'phone_number', 'phone_e164', 'notes']
    when 'watchmen' then array[
      'name', 'country_code', 'phone_number', 'phone_e164', 'building_name', 'notes',
      'building_location', 'pickup_location_text', 'pickup_latitude', 'pickup_longitude',
      'pickup_address']
  end;
$function$;

create function public.subscription_require_columns(p_section text, p_payload jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_columns text[] := public.subscription_entity_columns(p_section);
begin
  if v_columns is null or p_payload is null
     or pg_catalog.jsonb_typeof(p_payload) <> 'object'
     or not (p_payload ?& v_columns)
     or exists (select 1 from pg_catalog.jsonb_object_keys(p_payload) as k(key)
                where k.key <> all(v_columns)) then
    raise exception using errcode = 'PBQ04', message = 'invalid_payload';
  end if;
  return v_columns;
end;
$function$;

create function public.subscription_pick(p_doc jsonb, p_columns text[])
returns jsonb
language sql
immutable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from pg_catalog.jsonb_each(p_doc) as e where e.key = any(p_columns);
$function$;

create function public.subscription_parse_areas(p_section text, p_areas jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_item jsonb;
  v_area text;
  v_result text[] := array[]::text[];
begin
  if p_areas is null or pg_catalog.jsonb_typeof(p_areas) <> 'array'
     or (p_section not in ('requests', 'offers') and pg_catalog.jsonb_array_length(p_areas) > 0)
     or pg_catalog.jsonb_array_length(p_areas) > 200 then
    raise exception using errcode = 'PBQ04', message = 'invalid_payload';
  end if;
  for v_item in select e.value from pg_catalog.jsonb_array_elements(p_areas) as e loop
    if pg_catalog.jsonb_typeof(v_item) <> 'string' then
      raise exception using errcode = 'PBQ04', message = 'invalid_payload';
    end if;
    v_area := pg_catalog.btrim(v_item #>> '{}');
    if v_area <> '' and not (v_area = any(v_result)) then
      v_result := pg_catalog.array_append(v_result, v_area);
    end if;
  end loop;
  return v_result;
end;
$function$;

create function public.subscription_stored_areas(p_section text, p_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_areas text[];
begin
  if p_section = 'requests' then
    select coalesce(pg_catalog.array_agg(a.area order by a.ordinal), array[]::text[])
      into v_areas from public.request_areas as a where a.request_id = p_id;
  elsif p_section = 'offers' then
    select coalesce(pg_catalog.array_agg(a.area order by a.ordinal), array[]::text[])
      into v_areas from public.offer_areas as a where a.offer_id = p_id;
  else
    v_areas := array[]::text[];
  end if;
  return v_areas;
end;
$function$;

create function public.subscription_replace_areas(p_section text, p_id uuid, p_areas text[])
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_section = 'requests' then
    delete from public.request_areas as a where a.request_id = p_id;
    insert into public.request_areas (request_id, ordinal, area)
      select p_id, (t.ord - 1)::integer, t.area
      from pg_catalog.unnest(p_areas) with ordinality as t(area, ord);
  elsif p_section = 'offers' then
    delete from public.offer_areas as a where a.offer_id = p_id;
    insert into public.offer_areas (offer_id, ordinal, area)
      select p_id, (t.ord - 1)::integer, t.area
      from pg_catalog.unnest(p_areas) with ordinality as t(area, ord);
  end if;
end;
$function$;

create function public.subscription_require_caller()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  return v_user;
end;
$function$;

-- p_id is the idempotency identity of one logical create: the app keeps it
-- across retries of the same form. An identical retry is a replay and charges
-- nothing; the same id with different content is refused.
create function public.create_core_entity(
  p_section text,
  p_id uuid,
  p_payload jsonb,
  p_areas jsonb default '[]'::jsonb,
  p_media_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := public.subscription_require_caller();
  v_columns text[];
  v_areas text[];
  v_list text;
  v_values text;
  v_inserted uuid;
  v_stored jsonb;
  v_submitted jsonb;
begin
  if p_id is null or p_media_ids is null or pg_catalog.cardinality(p_media_ids) > 25 then
    raise exception using errcode = 'PBQ04', message = 'invalid_payload';
  end if;
  v_columns := public.subscription_require_columns(p_section, p_payload);
  v_areas := public.subscription_parse_areas(p_section, p_areas);
  perform public.subscription_lock(v_user);

  select pg_catalog.string_agg(pg_catalog.format('%I', c), ', '),
         pg_catalog.string_agg(pg_catalog.format('r.%I', c), ', ')
    into v_list, v_values from pg_catalog.unnest(v_columns) as c;

  execute pg_catalog.format(
    'insert into public.%1$I (id, owner_id, %2$s) '
    'select $1, $2, %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $3) as r '
    'on conflict (id) do nothing returning id',
    p_section, v_list, v_values)
    into v_inserted using p_id, v_user, p_payload;

  if v_inserted is null then
    execute pg_catalog.format(
      'select pg_catalog.to_jsonb(t) from public.%I as t where t.id = $1 and t.owner_id = $2',
      p_section) into v_stored using p_id, v_user;
    if v_stored is null or v_stored ->> 'deleted_at' is not null then
      raise exception using errcode = 'PBQ04', message = 'item_not_available';
    end if;
    execute pg_catalog.format(
      'select pg_catalog.to_jsonb(r) from pg_catalog.jsonb_populate_record(null::public.%I, $1) as r',
      p_section) into v_submitted using p_payload;
    if public.subscription_pick(v_stored, v_columns)
         <> public.subscription_pick(v_submitted, v_columns)
       or public.subscription_stored_areas(p_section, p_id) <> v_areas then
      raise exception using errcode = 'PBQ05', message = 'item_id_conflict';
    end if;
    return pg_catalog.jsonb_build_object('outcome', 'replayed', 'item_id', p_id);
  end if;

  -- A refusal here rolls the insert back with it.
  perform public.subscription_charge_create(v_user, p_section::public.quota_section, p_id);
  perform public.subscription_replace_areas(p_section, p_id, v_areas);
  perform public.subscription_grant_media(
    v_user, p_section::public.quota_section, p_id, p_media_ids, interval '30 days');
  return pg_catalog.jsonb_build_object('outcome', 'created', 'item_id', p_id);
end;
$function$;

-- One user save. p_request_id makes a repeated delivery of the same save a
-- replay. Lifecycle status and legacy file names are not content: changing only
-- those charges nothing and stays possible for a read-only account.
create function public.update_core_entity(
  p_section text,
  p_id uuid,
  p_request_id uuid,
  p_payload jsonb,
  p_areas jsonb default '[]'::jsonb,
  p_media_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := public.subscription_require_caller();
  v_columns text[];
  v_content text[];
  v_areas text[];
  v_old_areas text[];
  v_list text;
  v_values text;
  v_stored jsonb;
  v_submitted jsonb;
  v_changed boolean;
  v_content_changed boolean;
  v_edits integer;
  v_used_section text;
  v_used_item uuid;
  v_new_media boolean;
begin
  if p_id is null or p_request_id is null or p_media_ids is null
     or pg_catalog.cardinality(p_media_ids) > 25 then
    raise exception using errcode = 'PBQ04', message = 'invalid_payload';
  end if;
  v_columns := public.subscription_require_columns(p_section, p_payload);
  v_areas := public.subscription_parse_areas(p_section, p_areas);
  perform public.subscription_lock(v_user);

  select e.section::text, e.item_id into v_used_section, v_used_item
    from public.usage_events as e
    where e.owner_id = v_user and e.request_id = p_request_id;
  if found then
    -- One request id belongs to one save of one item.
    if v_used_section <> p_section or v_used_item <> p_id then
      raise exception using errcode = 'PBQ05', message = 'item_id_conflict';
    end if;
    return pg_catalog.jsonb_build_object('outcome', 'replayed', 'item_id', p_id);
  end if;

  execute pg_catalog.format(
    'select pg_catalog.to_jsonb(t) from public.%I as t '
    'where t.id = $1 and t.owner_id = $2 for update', p_section)
    into v_stored using p_id, v_user;
  if v_stored is null or v_stored ->> 'deleted_at' is not null then
    raise exception using errcode = 'PBQ04', message = 'item_not_available';
  end if;

  execute pg_catalog.format(
    'select pg_catalog.to_jsonb(r) from pg_catalog.jsonb_populate_record(null::public.%I, $1) as r',
    p_section) into v_submitted using p_payload;
  v_old_areas := public.subscription_stored_areas(p_section, p_id);
  select pg_catalog.array_agg(c) into v_content from pg_catalog.unnest(v_columns) as c
    where c <> all(array['status', 'legacy_uploaded_file_name']);

  v_changed := public.subscription_pick(v_stored, v_columns)
                 <> public.subscription_pick(v_submitted, v_columns)
               or v_old_areas <> v_areas;
  -- Media an earlier charged save already covers costs nothing again, so a
  -- retried save after a partial upload failure is not a second edit.
  v_new_media := exists (
    select 1 from pg_catalog.unnest(p_media_ids) as m(media_id)
    where not exists (
      select 1 from public.item_media_grants as g
      where g.owner_id = v_user and g.section = p_section::public.quota_section
        and g.item_id = p_id and g.expires_at > pg_catalog.now()
        and g.media_id is not distinct from m.media_id
    )
  );
  v_content_changed := public.subscription_pick(v_stored, v_content)
                         <> public.subscription_pick(v_submitted, v_content)
                       or v_old_areas <> v_areas
                       or v_new_media;

  if not v_changed and not v_content_changed then
    return pg_catalog.jsonb_build_object('outcome', 'unchanged', 'item_id', p_id);
  end if;

  if v_content_changed then
    v_edits := public.subscription_charge_edit(
      v_user, p_section::public.quota_section, p_id, p_request_id);
  end if;

  if v_changed then
    select pg_catalog.string_agg(pg_catalog.format('%I', c), ', '),
           pg_catalog.string_agg(pg_catalog.format('r.%I', c), ', ')
      into v_list, v_values from pg_catalog.unnest(v_columns) as c;
    execute pg_catalog.format(
      'update public.%1$I as t set (%2$s) = ('
      'select %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) as r) '
      'where t.id = $2 and t.owner_id = $3',
      p_section, v_list, v_values) using p_payload, p_id, v_user;
    if v_old_areas <> v_areas then
      perform public.subscription_replace_areas(p_section, p_id, v_areas);
    end if;
  end if;

  if v_new_media then
    perform public.subscription_grant_media(
      v_user, p_section::public.quota_section, p_id, p_media_ids, interval '30 days');
  end if;
  return pg_catalog.jsonb_build_object(
    'outcome', case when v_content_changed then 'updated' else 'status_updated' end,
    'item_id', p_id, 'edits_used', v_edits);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Quotations: the existing atomic save, now charged in the same transaction
-- ---------------------------------------------------------------------------

create function public.subscription_quotation_content(p_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'header', pg_catalog.to_jsonb(q) - array[
      'id', 'owner_id', 'office_logo_media_id', 'pdf_media_id',
      'created_at', 'updated_at', 'version', 'deleted_at'],
    'downpayments', (
      select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'sequence_number', d.sequence_number, 'method', d.method,
        'due_at', d.due_at, 'amount', d.amount) order by d.sequence_number), '[]'::jsonb)
      from public.quotation_downpayments as d where d.quotation_id = q.id),
    'government', (
      select pg_catalog.to_jsonb(g) - 'quotation_id'
      from public.quotation_government_fees as g where g.quotation_id = q.id),
    'administrative', (
      select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'ordinal', a.ordinal, 'title', a.title, 'amount', a.amount) order by a.ordinal), '[]'::jsonb)
      from public.quotation_administrative_fees as a where a.quotation_id = q.id))
  from public.quotations as q where q.id = p_id;
$function$;

create or replace function public.save_quotation(
  p_quotation_id uuid, p_expected_version bigint, p_header jsonb,
  p_downpayments jsonb, p_government_fees jsonb, p_administrative_fees jsonb
)
returns table (
  quotation_id uuid, resulting_version bigint, outcome text,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := public.subscription_require_caller();
  v_before jsonb;
  v_after jsonb;
  v_result record;
begin
  if not public.subscription_enforced() then
    return query select * from public.save_quotation_session_internal(
      p_quotation_id, p_expected_version, p_header, p_downpayments,
      p_government_fees, p_administrative_fees
    );
    return;
  end if;

  perform public.subscription_lock(v_user);
  if p_expected_version is not null then
    select public.subscription_quotation_content(q.id) into v_before
      from public.quotations as q
      where q.id = p_quotation_id and q.owner_id = v_user;
  end if;

  select * into v_result from public.save_quotation_session_internal(
    p_quotation_id, p_expected_version, p_header, p_downpayments,
    p_government_fees, p_administrative_fees
  );

  if v_result.outcome = 'created' then
    perform public.subscription_charge_create(v_user, 'quotations', p_quotation_id);
  elsif v_result.outcome = 'updated' then
    v_after := public.subscription_quotation_content(p_quotation_id);
    if v_after is distinct from v_before then
      -- A refusal rolls the whole aggregate write back.
      perform public.subscription_charge_edit(
        v_user, 'quotations', p_quotation_id, null);
    end if;
  end if;

  return query select v_result.quotation_id, v_result.resulting_version,
    v_result.outcome, v_result.created_at, v_result.updated_at;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Toolkit: reserve at authorize, charge once when the document becomes ready
-- ---------------------------------------------------------------------------

-- Fresh pending uploads hold a place; one abandoned for a day stops holding it,
-- so a failed upload never consumes an allowance.
create function public.toolkit_document_quota_reserve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_section public.quota_section := new.document_type::public.quota_section;
  v_access jsonb;
  v_limit integer;
  v_used bigint;
  v_pending bigint;
begin
  perform public.subscription_lock(new.owner_id);
  v_access := public.subscription_access(new.owner_id);
  if (v_access ->> 'is_plus')::boolean then
    return new;
  end if;
  if (v_access ->> 'read_only')::boolean then
    raise exception using errcode = 'PBQ03', message = 'account_read_only',
      detail = v_section::text;
  end if;
  select l.limit_value into v_limit from public.plan_limits as l
    where l.plan_code = 'free' and l.section = v_section;
  if v_limit is null then
    raise exception using errcode = 'PBQ06', message = 'quota_unavailable';
  end if;
  select coalesce((select u.lifetime_created_count from public.usage_counters as u
                   where u.owner_id = new.owner_id and u.section = v_section), 0)
    into v_used;
  select pg_catalog.count(*) into v_pending from public.toolkit_documents as d
    where d.owner_id = new.owner_id and d.document_type = new.document_type
      and d.status = 'pending_upload'
      and d.last_authorized_at > pg_catalog.now() - interval '24 hours';
  if v_used + v_pending >= v_limit then
    raise exception using errcode = 'PBQ01', message = 'creation_limit_reached',
      detail = v_section::text;
  end if;
  return new;
end;
$function$;

create function public.toolkit_document_quota_commit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.subscription_charge_create(
    new.owner_id, new.document_type::public.quota_section, new.id);
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Reads for the app and the Worker
-- ---------------------------------------------------------------------------

create function public.subscription_state_for(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_access jsonb := public.subscription_access(p_user);
  v_usage jsonb;
  v_items jsonb;
begin
  select pg_catalog.jsonb_object_agg(s.section, coalesce(u.lifetime_created_count, 0))
    into v_usage
    from pg_catalog.unnest(pg_catalog.enum_range(null::public.quota_section)) as s(section)
    left join public.usage_counters as u on u.owner_id = p_user and u.section = s.section;

  select coalesce(pg_catalog.jsonb_agg(t.item order by t.at desc), '[]'::jsonb) into v_items
  from (
    select e.updated_at as at, pg_catalog.jsonb_build_object(
      'section', e.section, 'item_id', e.item_id, 'edits_used', e.free_edits_used,
      'title', case e.section
        when 'owners' then (select x.name from public.owners as x where x.id = e.item_id and x.owner_id = p_user)
        when 'brokers' then (select x.name from public.brokers as x where x.id = e.item_id and x.owner_id = p_user)
        when 'watchmen' then (select x.name from public.watchmen as x where x.id = e.item_id and x.owner_id = p_user)
        when 'offices' then (select x.office_name from public.offices as x where x.id = e.item_id and x.owner_id = p_user)
        when 'offers' then (select x.location_text from public.offers as x where x.id = e.item_id and x.owner_id = p_user)
        when 'requests' then (select x.location_text from public.requests as x where x.id = e.item_id and x.owner_id = p_user)
        when 'quotations' then (select x.property_title from public.quotations as x where x.id = e.item_id and x.owner_id = p_user)
      end) as item
    from public.item_edit_usage as e
    where e.owner_id = p_user and e.free_edits_used > 0
    order by e.updated_at desc
    limit 100
  ) as t;

  return pg_catalog.jsonb_build_object(
    'plan', case when (v_access ->> 'is_plus')::boolean then 'plus' else 'free' end,
    'status', v_access ->> 'status',
    'read_only', (v_access ->> 'read_only')::boolean,
    'is_test', v_access ->> 'source' = 'test',
    'cycle', v_access -> 'cycle',
    'provider', v_access -> 'provider',
    'auto_renew', (v_access ->> 'auto_renew')::boolean,
    'started_at', v_access -> 'started_at',
    'paid_through', v_access -> 'paid_through',
    'next_charge_at', v_access -> 'next_charge_at',
    'server_now', pg_catalog.now(),
    'limits', pg_catalog.jsonb_build_object('creations', 5, 'edits_per_item', 3),
    'usage', v_usage,
    'items', v_items,
    'test_mode', public.subscription_test_mode_state(p_user));
end;
$function$;

create function public.get_subscription_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  return public.subscription_state_for(public.subscription_require_caller());
end;
$function$;

-- Worker only: may this account change this media of this item now?
create function public.subscription_authorize_media_change(
  p_user uuid, p_section text, p_item uuid, p_media uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_access jsonb;
begin
  if p_user is null or p_item is null
     or p_section not in ('offers', 'owners', 'quotations') then
    raise exception using errcode = 'PBQ04', message = 'invalid_payload';
  end if;
  v_access := public.subscription_access(p_user);
  if (v_access ->> 'is_plus')::boolean then
    return 'allowed';
  end if;
  if (v_access ->> 'read_only')::boolean then
    return 'read_only';
  end if;
  -- A Quotation's PDF and logo follow its save and are not a separate edit.
  if p_section = 'quotations' then
    return 'allowed';
  end if;
  if exists (
    select 1 from public.item_media_grants as g
    where g.owner_id = p_user and g.section = p_section::public.quota_section
      and g.item_id = p_item and g.expires_at > pg_catalog.now()
      and (g.media_id is null or g.media_id = p_media)
  ) then
    return 'allowed';
  end if;
  return 'edit_required';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Verified provider events (called only by the webhook Edge Function)
-- ---------------------------------------------------------------------------

-- Outcomes: processed, duplicate, stale (older than what is known),
-- no_account (never creates or re-attaches one), ownership_conflict (a purchase
-- is never moved between accounts here), ignored (an unknown state for a known
-- record changes nothing).
create function public.apply_subscription_provider_event(
  p_provider text,
  p_event_id text,
  p_event_type text,
  p_event_at timestamptz,
  p_user_id uuid,
  p_provider_subscription_id text,
  p_product_id text,
  p_billing_cycle text,
  p_state text,
  p_auto_renew boolean,
  p_started_at timestamptz,
  p_paid_through_at timestamptz,
  p_grace_until timestamptz,
  p_environment text,
  p_payload_sha256 text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record public.subscription_provider_records%rowtype;
  v_outcome text;
  v_account boolean;
begin
  if p_provider is null or p_provider not in ('google_play', 'app_store', 'tap')
     or nullif(pg_catalog.btrim(p_event_id), '') is null
     or nullif(pg_catalog.btrim(p_event_type), '') is null
     or p_event_at is null
     or nullif(pg_catalog.btrim(p_provider_subscription_id), '') is null
     or p_state is null
     or p_state not in ('active', 'cancel_scheduled', 'billing_issue', 'paused',
                        'expired', 'refunded', 'revoked', 'unknown')
     or p_environment is null or p_environment not in ('production', 'sandbox')
     or p_auto_renew is null then
    raise exception using errcode = 'PBP01', message = 'invalid_provider_event';
  end if;

  insert into public.billing_events (
    provider, event_id, event_type, event_at, provider_subscription_id, outcome, payload_sha256)
  values (p_provider, p_event_id, p_event_type, p_event_at,
          p_provider_subscription_id, 'processing', p_payload_sha256)
  on conflict (provider, event_id) do nothing;
  if not found then
    return 'duplicate';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'subscription_provider:' || p_provider || ':' || p_provider_subscription_id, 0));

  select exists (select 1 from public.profiles as p where p.id = p_user_id) into v_account;
  select r.* into v_record from public.subscription_provider_records as r
    where r.provider = p_provider and r.provider_subscription_id = p_provider_subscription_id
    for update;

  if found then
    if v_record.user_id is null then
      v_outcome := 'no_account';
    elsif p_user_id is distinct from v_record.user_id then
      v_outcome := 'ownership_conflict';
    elsif p_event_at < v_record.last_event_at then
      v_outcome := 'stale';
    elsif p_state = 'unknown' then
      v_outcome := 'ignored';
    else
      update public.subscription_provider_records as r set
        product_id = coalesce(p_product_id, r.product_id),
        billing_cycle = coalesce(p_billing_cycle, r.billing_cycle),
        state = p_state,
        auto_renew = p_auto_renew,
        environment = p_environment,
        started_at = coalesce(r.started_at, p_started_at),
        paid_through_at = coalesce(p_paid_through_at, r.paid_through_at),
        grace_until = case when p_state = 'billing_issue' then p_grace_until end,
        last_event_at = p_event_at,
        last_event_id = p_event_id,
        updated_at = pg_catalog.now()
      where r.id = v_record.id;
      v_outcome := 'processed';
    end if;
  elsif not v_account then
    v_outcome := 'no_account';
  else
    insert into public.subscription_provider_records (
      user_id, provider, provider_subscription_id, product_id, billing_cycle, state,
      auto_renew, environment, started_at, paid_through_at, grace_until,
      last_event_at, last_event_id)
    values (
      p_user_id, p_provider, p_provider_subscription_id, p_product_id, p_billing_cycle,
      p_state, p_auto_renew, p_environment, p_started_at, p_paid_through_at,
      case when p_state = 'billing_issue' then p_grace_until end, p_event_at, p_event_id);
    v_outcome := 'processed';
  end if;

  update public.billing_events as e
    set outcome = v_outcome,
        user_id = case when v_account then p_user_id end
    where e.provider = p_provider and e.event_id = p_event_id;
  return v_outcome;
end;
$function$;

-- ---------------------------------------------------------------------------
-- The guard installed at cutover
-- ---------------------------------------------------------------------------

-- A second wall behind the grants: if a client grant is ever widened by
-- mistake, the only row change a client role can make is the soft delete.
create function public.guard_core_entity_client_write()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- Area tables have no deleted_at, so the field is only read on core tables.
  if tg_op = 'UPDATE' and tg_table_name not in ('request_areas', 'offer_areas') then
    if old.deleted_at is null and new.deleted_at is not null
       and (pg_catalog.to_jsonb(new) - array['deleted_at', 'updated_at', 'version'])
           = (pg_catalog.to_jsonb(old) - array['deleted_at', 'updated_at', 'version']) then
      return new;
    end if;
  end if;
  raise exception using errcode = '42501', message = 'direct_write_not_allowed';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Cutover: one explicit, transactional, reversible step
-- ---------------------------------------------------------------------------

-- p_baseline decides what the existing rows count for:
--   'actual'  every surviving row counts, soft-deleted rows and Toolkit tombstones
--             included. Accounts above 5 become read-only at once.
--   'capped'  the count stops at the limit. Accounts above 5 cannot add more in
--             that section but are not read-only.
-- Rows hard-deleted before this point cannot be reconstructed either way, so the
-- baseline is a lower bound. An existing higher counter is never lowered.
create function public.subscription_cutover(p_baseline text, p_confirm text)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_table text;
  v_over bigint;
begin
  if current_user <> 'postgres' then
    raise exception 'Only the database owner can run the cutover';
  end if;
  if p_confirm is distinct from 'ENFORCE'
     or p_baseline is null or p_baseline not in ('actual', 'capped') then
    raise exception 'subscription_cutover needs a baseline (actual or capped) and the word ENFORCE';
  end if;
  perform 1 from public.subscription_rollout as r where r.enforced for update;
  if found then
    return pg_catalog.jsonb_build_object('outcome', 'already_enforced');
  end if;

  -- No direct write can slip in between the count and the revoke.
  lock table public.requests, public.offers, public.owners, public.offices,
    public.brokers, public.watchmen, public.request_areas, public.offer_areas,
    public.quotations, public.toolkit_documents, public.usage_counters
    in share row exclusive mode;

  insert into public.usage_counters (owner_id, section, lifetime_created_count)
  select s.owner_id, s.section,
         case when p_baseline = 'capped'
              then least(pg_catalog.count(*), l.limit_value::bigint)
              else pg_catalog.count(*) end
  from (
    select owner_id, 'requests'::public.quota_section as section from public.requests
    union all select owner_id, 'offers' from public.offers
    union all select owner_id, 'owners' from public.owners
    union all select owner_id, 'offices' from public.offices
    union all select owner_id, 'brokers' from public.brokers
    union all select owner_id, 'watchmen' from public.watchmen
    union all select owner_id, 'quotations' from public.quotations
    union all
    select owner_id, document_type::public.quota_section
    from public.toolkit_documents
    where status in ('ready', 'pending_delete', 'deleted')
  ) as s
  join public.plan_limits as l on l.plan_code = 'free' and l.section = s.section
  group by s.owner_id, s.section, l.limit_value
  on conflict (owner_id, section) do update
    set lifetime_created_count = greatest(
      public.usage_counters.lifetime_created_count, excluded.lifetime_created_count);

  foreach v_table in array array['requests', 'offers', 'owners', 'offices', 'brokers', 'watchmen'] loop
    execute pg_catalog.format(
      'revoke insert, update, delete on public.%I from public, anon, authenticated', v_table);
    execute pg_catalog.format('grant update (deleted_at) on public.%I to authenticated', v_table);
    execute pg_catalog.format(
      'create policy %1$s on public.%2$I as restrictive for update to authenticated '
      'using (owner_id = (select auth.uid()) and deleted_at is null) '
      'with check (owner_id = (select auth.uid()) and deleted_at is not null)',
      v_table || '_direct_soft_delete_only', v_table);
    execute pg_catalog.format(
      'create trigger %1$s before insert or update on public.%2$I '
      'for each row execute function public.guard_core_entity_client_write()',
      v_table || '_guard_client_write', v_table);
  end loop;
  foreach v_table in array array['request_areas', 'offer_areas'] loop
    execute pg_catalog.format(
      'revoke insert, update, delete on public.%I from public, anon, authenticated', v_table);
    execute pg_catalog.format(
      'create trigger %1$s before insert or update or delete on public.%2$I '
      'for each row execute function public.guard_core_entity_client_write()',
      v_table || '_guard_client_write', v_table);
  end loop;

  create trigger toolkit_documents_quota_reserve
    before insert on public.toolkit_documents
    for each row execute function public.toolkit_document_quota_reserve();
  create trigger toolkit_documents_quota_commit
    before update on public.toolkit_documents
    for each row when (old.status = 'pending_upload' and new.status = 'ready')
    execute function public.toolkit_document_quota_commit();

  select pg_catalog.count(distinct u.owner_id) into v_over
  from public.usage_counters as u
  join public.plan_limits as l on l.plan_code = 'free' and l.section = u.section
  where u.lifetime_created_count > l.limit_value;

  update public.subscription_rollout
    set enforced = true, baseline = p_baseline, changed_at = pg_catalog.now();
  insert into public.subscription_rollout_log (action, baseline, accounts_over_limit)
    values ('cutover', p_baseline, v_over);
  return pg_catalog.jsonb_build_object(
    'outcome', 'enforced', 'baseline', p_baseline, 'accounts_over_limit', v_over);
end;
$function$;

-- Puts the direct writes back exactly as they were. Counters, edits, events and
-- provider records all stay, so a later cutover continues from the same history.
create function public.subscription_cutback(p_confirm text)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_table text;
  v_insert text;
  v_update text;
begin
  if current_user <> 'postgres' then
    raise exception 'Only the database owner can run the cutback';
  end if;
  if p_confirm is distinct from 'RESTORE DIRECT WRITES' then
    raise exception 'subscription_cutback needs the words RESTORE DIRECT WRITES';
  end if;
  perform 1 from public.subscription_rollout as r where r.enforced for update;
  if not found then
    return pg_catalog.jsonb_build_object('outcome', 'not_enforced');
  end if;

  drop trigger toolkit_documents_quota_reserve on public.toolkit_documents;
  drop trigger toolkit_documents_quota_commit on public.toolkit_documents;
  foreach v_table in array array['requests', 'offers', 'owners', 'offices', 'brokers', 'watchmen'] loop
    execute pg_catalog.format('drop trigger %I on public.%I', v_table || '_guard_client_write', v_table);
    execute pg_catalog.format('drop policy %I on public.%I', v_table || '_direct_soft_delete_only', v_table);
    select pg_catalog.string_agg(pg_catalog.format('%I', c), ', ') into v_insert
      from pg_catalog.unnest(array['id', 'owner_id'] || public.subscription_entity_columns(v_table)) as c;
    select pg_catalog.string_agg(pg_catalog.format('%I', c), ', ') into v_update
      from pg_catalog.unnest(public.subscription_entity_columns(v_table) || array['deleted_at']) as c;
    execute pg_catalog.format('grant insert (%s) on public.%I to authenticated', v_insert, v_table);
    execute pg_catalog.format('grant update (%s) on public.%I to authenticated', v_update, v_table);
  end loop;
  foreach v_table in array array['request_areas', 'offer_areas'] loop
    execute pg_catalog.format('drop trigger %I on public.%I', v_table || '_guard_client_write', v_table);
    execute pg_catalog.format('grant insert, update, delete on public.%I to authenticated', v_table);
  end loop;

  update public.subscription_rollout set enforced = false, changed_at = pg_catalog.now();
  insert into public.subscription_rollout_log (action) values ('cutback');
  return pg_catalog.jsonb_build_object('outcome', 'restored');
end;
$function$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------

do $privileges$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.subscription_accepts_sandbox()',
    'public.subscription_override_entitlement(uuid)',
    'public.subscription_test_mode_state(uuid)',
    'public.subscription_enforced()',
    'public.subscription_cutover(text, text)',
    'public.subscription_cutback(text)',
    'public.subscription_entitlement(uuid)',
    'public.subscription_access(uuid)',
    'public.subscription_lock(uuid)',
    'public.subscription_plan_label(jsonb)',
    'public.subscription_charge_create(uuid, public.quota_section, uuid)',
    'public.subscription_charge_edit(uuid, public.quota_section, uuid, uuid)',
    'public.subscription_grant_media(uuid, public.quota_section, uuid, uuid[], interval)',
    'public.subscription_entity_columns(text)',
    'public.subscription_require_columns(text, jsonb)',
    'public.subscription_pick(jsonb, text[])',
    'public.subscription_parse_areas(text, jsonb)',
    'public.subscription_stored_areas(text, uuid)',
    'public.subscription_replace_areas(text, uuid, text[])',
    'public.subscription_require_caller()',
    'public.subscription_quotation_content(uuid)',
    'public.subscription_state_for(uuid)',
    'public.toolkit_document_quota_reserve()',
    'public.toolkit_document_quota_commit()',
    'public.guard_core_entity_client_write()'
  ] loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role', v_signature);
  end loop;
end;
$privileges$;

revoke all on function public.create_core_entity(text, uuid, jsonb, jsonb, uuid[])
  from public, anon, service_role;
revoke all on function public.update_core_entity(text, uuid, uuid, jsonb, jsonb, uuid[])
  from public, anon, service_role;
revoke all on function public.get_subscription_state() from public, anon, service_role;
grant execute on function public.create_core_entity(text, uuid, jsonb, jsonb, uuid[]) to authenticated;
grant execute on function public.update_core_entity(text, uuid, uuid, jsonb, jsonb, uuid[]) to authenticated;
grant execute on function public.get_subscription_state() to authenticated;

revoke all on function public.subscription_authorize_media_change(uuid, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.apply_subscription_provider_event(
  text, text, text, timestamptz, uuid, text, text, text, text, boolean,
  timestamptz, timestamptz, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.subscription_authorize_media_change(uuid, text, uuid, uuid) to service_role;
grant execute on function public.apply_subscription_provider_event(
  text, text, text, timestamptz, uuid, text, text, text, text, boolean,
  timestamptz, timestamptz, timestamptz, text, text) to service_role;

comment on function public.create_core_entity(text, uuid, jsonb, jsonb, uuid[]) is
  'Atomic owner-only create of a core entity and its lifetime charge. Errors: PBQ01 creation limit, PBQ03 read-only, PBQ04 invalid or unavailable, PBQ05 id conflict, PBQ06 quota unavailable.';
comment on function public.update_core_entity(text, uuid, uuid, jsonb, jsonb, uuid[]) is
  'Atomic owner-only update of a core entity. A real content change charges one Free edit. Errors: PBQ02 edit limit, PBQ03 read-only, PBQ04 invalid or unavailable.';
