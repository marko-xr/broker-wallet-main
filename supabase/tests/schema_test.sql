-- Static schema/security contract checks for Broker Wallet Stage 1.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(27);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'requests', 'requests table exists');
select has_table('public', 'offers', 'offers table exists');
select has_table('public', 'owners', 'owners table exists');
select has_table('public', 'offices', 'offices table exists');
select has_table('public', 'brokers', 'brokers table exists');
select has_table('public', 'watchmen', 'watchmen table exists');
select has_table('public', 'quotations', 'quotations table exists');
select has_table('public', 'media_objects', 'media_objects table exists');
select has_table('public', 'revenuecat_entitlements', 'RevenueCat projection exists');
select has_table('public', 'usage_counters', 'usage counters exist');
select has_table('public', 'app_versions', 'app versions table exists');

select ok(
  not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name in ('properties', 'user_favorites')
  ),
  'legacy generic properties/user_favorites are excluded'
);

select is(
  (select count(*)::integer
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname in (
       'profiles','revenuecat_entitlements','plan_limits','usage_counters','revenuecat_webhook_events',
       'requests','request_areas','offers','offer_areas','owners','offices','brokers','watchmen',
       'quotations','quotation_downpayments','quotation_government_fees','quotation_administrative_fees',
       'media_objects','offer_media','owner_media','quotation_media','profile_media',
       'favorite_offers','favorite_requests','favorite_owners','favorite_offices','favorite_brokers','favorite_watchmen',
       'feedback','notifications','push_devices','app_versions','idempotency_keys','audit_logs'
     )
     and c.relrowsecurity),
  34,
  'RLS is enabled on every Stage 1 application table'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='requests' and column_name='min_price'
      and data_type='numeric' and numeric_precision=14 and numeric_scale=2
  ),
  'request prices use numeric(14,2)'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='offers' and column_name='pickup_latitude'
      and data_type='double precision'
  ),
  'offer coordinates use double precision'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='requests' and column_name='version'
      and data_type='bigint'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='requests' and column_name='deleted_at'
      and data_type='timestamp with time zone'
  ),
  'sync version and tombstone fields exist'
);

select ok(
  has_table_privilege('authenticated', 'public.requests', 'SELECT')
  and not has_table_privilege('authenticated', 'public.requests', 'DELETE'),
  'owned entities are readable but hard delete is not granted'
);

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'is_email_verified', 'UPDATE'),
  'profile editable and server-owned columns are separated'
);

select ok(
  has_table_privilege('authenticated', 'public.media_objects', 'SELECT')
  and not has_table_privilege('authenticated', 'public.media_objects', 'INSERT')
  and not has_table_privilege('authenticated', 'public.media_objects', 'UPDATE'),
  'media metadata is client read-only'
);

select ok(
  has_table_privilege('authenticated', 'public.revenuecat_entitlements', 'SELECT')
  and not has_table_privilege('authenticated', 'public.revenuecat_entitlements', 'INSERT')
  and not has_table_privilege('authenticated', 'public.revenuecat_entitlements', 'UPDATE'),
  'RevenueCat entitlement projection is server-write-only'
);

select ok(
  not has_table_privilege('authenticated', 'public.revenuecat_webhook_events', 'SELECT')
  and not has_table_privilege('authenticated', 'public.revenuecat_webhook_events', 'INSERT'),
  'RevenueCat webhook evidence is hidden from ordinary clients'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='favorite_offers' and policyname='favorite_offers_insert_own'
  ),
  'favorite offers have owner/target insert policy'
);

select is(
  (select count(*)::integer
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'owns_request','owns_offer','owns_owner_record','owns_office',
       'owns_broker','owns_watchman','owns_quotation'
     )
     and p.prosecdef = false),
  7,
  'RLS ownership helpers run as SECURITY INVOKER'
);

select ok(
  exists (
    select 1 from pg_views
    where schemaname='public' and viewname='favorites_unified'
  ),
  'unified favorites read view exists'
);

select ok(
  (select count(*) from public.plan_limits) = 0,
  'production quota limits are intentionally not seeded'
);


select is(
  (select count(*)::integer
   from pg_indexes
   where schemaname = 'public'
     and indexname in (
       'audit_logs_actor_idx',
       'feedback_owner_idx',
       'notifications_sender_user_idx',
       'offer_media_media_idx',
       'owner_media_media_idx',
       'profile_media_media_idx',
       'profiles_profile_media_idx',
       'quotation_media_media_idx',
       'quotations_office_logo_media_idx',
       'quotations_pdf_media_idx'
     )),
  10,
  'all advisor-reported foreign keys have covering indexes'
);

select * from finish();
rollback;
