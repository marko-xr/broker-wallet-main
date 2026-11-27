-- Server-authoritative subscriptions and quotas.
--
--   * Free: 5 lifetime creations per section, deletion never restores one;
--   * Free: 3 content edits per item, no-ops, replays and failures cost nothing;
--   * no client role can write a core table, a counter or an entitlement;
--   * cancellation, billing trouble, expiry, refund and revocation stay separate;
--   * late, duplicate and foreign provider events cannot grant access;
--   * the production schema holds no test facility at all.
--
-- The checks run in the ENFORCED state: this transaction performs the cutover.
--
-- Run with `supabase test db` on a disposable local stack. Provider and Toolkit
-- calls run as postgres here, standing in for the service role of the trusted
-- backend; the client-side checks switch to the `authenticated` role.
-- Two truly concurrent connections cannot be expressed in one pgTAP transaction.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(114);

create function pg_temp.uid(p text) returns uuid language sql immutable as
$$ select md5('user:' || p)::uuid $$;
create function pg_temp.sid(p text) returns uuid language sql immutable as
$$ select md5('session:' || p)::uuid $$;
create function pg_temp.item(p_owner text, p_section text, p_n integer) returns uuid
language sql immutable as $$ select md5(p_owner || ':' || p_section || ':' || p_n)::uuid $$;
create function pg_temp.req(p text) returns uuid language sql immutable as
$$ select md5('request:' || p)::uuid $$;

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
select pg_temp.uid(u), 'quota-' || u || '@example.test', jsonb_build_object('name', u), now(), now()
from unnest(array['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) as u;
insert into auth.sessions (id, user_id, created_at, updated_at)
select pg_temp.sid(u), pg_temp.uid(u), now(), now()
from unnest(array['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) as u;
insert into public.user_active_sessions (user_id, active_session_id)
select pg_temp.uid(u), pg_temp.sid(u)
from unnest(array['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) as u;

-- Runs one statement as that account's active session. Returns its text value
-- or the SQLSTATE it failed with, so a refusal can be asserted exactly.
create function pg_temp.call(p_user text, p_sql text) returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.uid(p_user), 'role', 'authenticated',
    'session_id', pg_temp.sid(p_user))::text, true);
  begin
    set local role authenticated;
    execute p_sql into v;
    set local role none;
    return coalesce(v, 'null');
  exception when others then
    return sqlstate;
  end;
end $$;

-- A complete valid payload for a section, carrying p_note as the content.
create function pg_temp.body(p_section text, p_note text) returns jsonb language sql as $$
  select jsonb_object_agg(c.column_name, case
    when c.column_name = 'notes' then to_jsonb(p_note)
    when c.column_name = 'status' then
      case p_section when 'requests' then '"active"'::jsonb else '"available"'::jsonb end
    when c.data_type = 'text' and c.is_nullable = 'NO' and c.column_default is null then '"x"'::jsonb
    when c.data_type = 'text' and c.is_nullable = 'NO' then '""'::jsonb
    when c.data_type = 'integer' then '0'::jsonb
    when c.data_type = 'USER-DEFINED' then to_jsonb((
      select e.enumlabel::text from pg_enum as e join pg_type as t on t.oid = e.enumtypid
      where t.typname = c.udt_name order by e.enumsortorder limit 1))
    else 'null'::jsonb end)
  from information_schema.columns as c
  where c.table_schema = 'public' and c.table_name = p_section
    and c.column_name = any(public.subscription_entity_columns(p_section));
$$;

create function pg_temp.mk(p_user text, p_section text, p_n integer, p_note text default 'base')
returns text language sql as $$
  select pg_temp.call(p_user, format(
    $f$select public.create_core_entity(%L, %L::uuid, %L::jsonb) ->> 'outcome'$f$,
    p_section, pg_temp.item(p_user, p_section, p_n), pg_temp.body(p_section, p_note)));
$$;
create function pg_temp.ed(p_actor text, p_owner text, p_section text, p_n integer,
  p_note text, p_request text) returns text language sql as $$
  select pg_temp.call(p_actor, format(
    $f$select public.update_core_entity(%L, %L::uuid, %L::uuid, %L::jsonb) ->> 'outcome'$f$,
    p_section, pg_temp.item(p_owner, p_section, p_n), pg_temp.req(p_request),
    pg_temp.body(p_section, p_note)));
$$;
create function pg_temp.used(p_user text, p_section text) returns bigint language sql as $$
  select coalesce((select u.lifetime_created_count from public.usage_counters as u
    where u.owner_id = pg_temp.uid(p_user) and u.section = p_section::public.quota_section), 0);
$$;
create function pg_temp.edits(p_user text, p_section text, p_n integer) returns integer
language sql as $$
  select coalesce((select e.free_edits_used::integer from public.item_edit_usage as e
    where e.owner_id = pg_temp.uid(p_user) and e.section = p_section::public.quota_section
      and e.item_id = pg_temp.item(p_user, p_section, p_n)), 0);
$$;
create function pg_temp.state(p_user text, p_key text) returns text language sql as $$
  select public.subscription_state_for(pg_temp.uid(p_user)) ->> p_key;
$$;

-- The whole create and edit contract of one core section. Returns 'ok' or the
-- first broken rule.
create function pg_temp.core_flow(p_section text) returns text language plpgsql as $$
declare
  v text;
  n bigint;
  i integer;
begin
  for i in 1..5 loop
    v := pg_temp.mk('a', p_section, i);
    if v <> 'created' then return format('create %s: %s', i, v); end if;
  end loop;
  if pg_temp.used('a', p_section) <> 5 then return 'five creations were not counted'; end if;

  v := pg_temp.mk('a', p_section, 6);
  if v <> 'PBQ01' then return 'sixth: ' || v; end if;
  execute format('select count(*) from public.%I where id = $1', p_section) into n
    using pg_temp.item('a', p_section, 6);
  if n <> 0 or pg_temp.used('a', p_section) <> 5 then return 'refused create left a trace'; end if;

  v := pg_temp.mk('a', p_section, 1);
  if v <> 'replayed' or pg_temp.used('a', p_section) <> 5 then return 'replay: ' || v; end if;
  v := pg_temp.mk('a', p_section, 1, 'other content');
  if v <> 'PBQ05' then return 'same id, new content: ' || v; end if;

  v := pg_temp.call('a', format(
    'insert into public.%I (id, owner_id) values (gen_random_uuid(), auth.uid()) returning id::text', p_section));
  if v <> '42501' then return 'direct insert: ' || v; end if;
  v := pg_temp.call('a', format(
    $f$update public.%I set notes = 'bypass' where id = %L returning id::text$f$,
    p_section, pg_temp.item('a', p_section, 2)));
  if v <> '42501' then return 'direct update: ' || v; end if;
  v := pg_temp.call('a', format('delete from public.%I where id = %L returning id::text',
    p_section, pg_temp.item('a', p_section, 2)));
  if v <> '42501' then return 'direct delete: ' || v; end if;

  v := pg_temp.ed('b', 'a', p_section, 2, 'stolen', p_section || 'cross');
  if v <> 'PBQ04' then return 'cross-account edit: ' || v; end if;

  v := pg_temp.ed('a', 'a', p_section, 2, 'e1', p_section || 'r1');
  if v <> 'updated' or pg_temp.edits('a', p_section, 2) <> 1 then return 'edit 1: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 2, 'e1', p_section || 'r1');
  if v <> 'replayed' or pg_temp.edits('a', p_section, 2) <> 1 then return 'edit replay: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 2, 'e1', p_section || 'noop');
  if v <> 'unchanged' or pg_temp.edits('a', p_section, 2) <> 1 then return 'no-op: ' || v; end if;
  v := pg_temp.call('a', format(
    $f$select public.update_core_entity(%L, %L::uuid, %L::uuid, %L::jsonb)::text$f$,
    p_section, pg_temp.item('a', p_section, 2), pg_temp.req(p_section || 'bad'),
    pg_temp.body(p_section, 'e9') || '{"owner_id":"00000000-0000-4000-8000-000000000000"}'));
  if v <> 'PBQ04' or pg_temp.edits('a', p_section, 2) <> 1 then return 'bad payload: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 2, 'e2', p_section || 'r2');
  if v <> 'updated' then return 'edit 2: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 2, 'e3', p_section || 'r3');
  if v <> 'updated' or pg_temp.edits('a', p_section, 2) <> 3 then return 'edit 3: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 2, 'e4', p_section || 'r4');
  if v <> 'PBQ02' or pg_temp.edits('a', p_section, 2) <> 3 then return 'edit 4: ' || v; end if;
  execute format('select notes from public.%I where id = $1', p_section) into v
    using pg_temp.item('a', p_section, 2);
  if v <> 'e3' then return 'refused edit changed the row: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 3, 'other item', p_section || 'r5');
  if v <> 'updated' or pg_temp.edits('a', p_section, 3) <> 1 then return 'edits are per item: ' || v; end if;

  v := pg_temp.call('a', format(
    'update public.%I set deleted_at = now() where id = %L returning id::text',
    p_section, pg_temp.item('a', p_section, 1)));
  if v <> pg_temp.item('a', p_section, 1)::text then return 'soft delete: ' || v; end if;
  v := pg_temp.mk('a', p_section, 7);
  if v <> 'PBQ01' or pg_temp.used('a', p_section) <> 5 then return 'delete restored allowance: ' || v; end if;
  v := pg_temp.ed('a', 'a', p_section, 1, 'after delete', p_section || 'r6');
  if v <> 'PBQ04' then return 'edit after delete: ' || v; end if;
  return 'ok';
end $$;

create function pg_temp.authz(p_user text, p_type text, p_n integer) returns text
language plpgsql as $$
declare
  v text;
begin
  select a.outcome into v from public.authorize_toolkit_document_upload(
    pg_temp.uid(p_user), pg_temp.item(p_user, p_type, p_n), p_type, 'application/pdf', 'Doc',
    1000, 1, repeat('a', 64), now(), 'test-bucket', 52428800, 26214400, 1073741824,
    1000, 5, 120, 10, false) as a;
  return v;
exception when others then
  return sqlstate;
end $$;
create function pg_temp.conf(p_user text, p_type text, p_n integer) returns text
language plpgsql as $$
declare
  v text;
begin
  select c.outcome into v from public.confirm_toolkit_document_upload(
    pg_temp.uid(p_user), pg_temp.item(p_user, p_type, p_n), 'test-bucket', 1000,
    'application/pdf', '"etag"', false) as c;
  return v;
exception when others then
  return sqlstate;
end $$;

create function pg_temp.toolkit_flow(p_type text) returns text language plpgsql as $$
declare
  v text;
  i integer;
begin
  for i in 1..5 loop
    v := pg_temp.authz('e', p_type, i);
    if v <> 'created' then return format('authorize %s: %s', i, v); end if;
    if pg_temp.used('e', p_type) <> i - 1 then return 'authorize alone consumed allowance'; end if;
    v := pg_temp.conf('e', p_type, i);
    if v <> 'confirmed' then return format('confirm %s: %s', i, v); end if;
  end loop;
  if pg_temp.used('e', p_type) <> 5 then return 'five documents were not counted'; end if;
  v := pg_temp.conf('e', p_type, 1);
  if v <> 'already_confirmed' or pg_temp.used('e', p_type) <> 5 then return 'duplicate confirm: ' || v; end if;
  v := pg_temp.authz('e', p_type, 6);
  if v <> 'PBQ01' then return 'sixth document: ' || v; end if;
  v := (select b.outcome from public.begin_toolkit_document_delete(
    pg_temp.uid('e'), pg_temp.item('e', p_type, 1), 'test-bucket', null) as b);
  if pg_temp.used('e', p_type) <> 5 then return 'delete changed the count'; end if;
  v := pg_temp.authz('e', p_type, 6);
  if v <> 'PBQ01' then return 'deletion restored allowance: ' || v; end if;
  if not exists (select 1 from public.toolkit_documents as d
                 where d.id = pg_temp.item('e', p_type, 2) and d.status = 'ready') then
    return 'an existing document stopped being ready';
  end if;
  return 'ok';
end $$;

create function pg_temp.event(p_user text, p_sub text, p_id text, p_state text,
  p_event interval, p_paid interval, p_auto boolean default true,
  p_env text default 'production', p_provider text default 'google_play',
  p_grace interval default null) returns text language sql as $$
  select public.apply_subscription_provider_event(
    p_provider, p_id, 'TEST_EVENT', now() + p_event, pg_temp.uid(p_user), p_sub, 'plus_monthly',
    'monthly', p_state, p_auto, now() - interval '1 day', now() + p_paid,
    now() + p_grace, p_env, null);
$$;

-- ---------------------------------------------------------------------------
-- Structure and privileges
-- ---------------------------------------------------------------------------

select ok(not exists (
  select 1 from unnest(array[
    'subscription_provider_records', 'billing_events', 'item_edit_usage', 'usage_events',
    'item_media_grants', 'subscription_rollout', 'subscription_rollout_log']) as t(name)
  join pg_class as c on c.oid = ('public.' || t.name)::regclass
  where not c.relrowsecurity
), 'every new table has row level security');
select ok(not exists (
  select 1 from unnest(array[
    'subscription_provider_records', 'billing_events', 'item_edit_usage', 'usage_events',
    'item_media_grants', 'subscription_rollout', 'subscription_rollout_log']) as t(name)
  cross join unnest(array['anon', 'authenticated', 'service_role']) as r(role)
  cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
  where has_table_privilege(r.role, 'public.' || t.name, p.priv)
), 'no client or service role holds a direct privilege on the new tables');
select ok(not has_table_privilege('authenticated', 'public.usage_counters', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.usage_counters', 'INSERT')
  and not has_table_privilege('authenticated', 'public.revenuecat_entitlements', 'UPDATE'),
  'clients cannot write counters or entitlements');
select ok(has_function_privilege('authenticated', 'public.get_subscription_state()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.create_core_entity(text,uuid,jsonb,jsonb,uuid[])', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.update_core_entity(text,uuid,uuid,jsonb,jsonb,uuid[])', 'EXECUTE'),
  'clients can call exactly the three client functions');
select ok(not has_function_privilege('anon', 'public.get_subscription_state()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.create_core_entity(text,uuid,jsonb,jsonb,uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.update_core_entity(text,uuid,uuid,jsonb,jsonb,uuid[])', 'EXECUTE'),
  'anonymous callers can call none of them');
select ok(not has_function_privilege('authenticated',
    'public.apply_subscription_provider_event(text,text,text,timestamptz,uuid,text,text,text,text,boolean,timestamptz,timestamptz,timestamptz,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.subscription_authorize_media_change(uuid,text,uuid,uuid)', 'EXECUTE'),
  'clients cannot call the trusted-backend functions');
select ok(has_function_privilege('service_role',
    'public.apply_subscription_provider_event(text,text,text,timestamptz,uuid,text,text,text,text,boolean,timestamptz,timestamptz,timestamptz,text,text)', 'EXECUTE'),
  'the trusted backend can call them');
select ok(not exists (
  select 1 from unnest(array[
    'subscription_entitlement(uuid)', 'subscription_access(uuid)',
    'subscription_charge_create(uuid,public.quota_section,uuid)',
    'subscription_charge_edit(uuid,public.quota_section,uuid,uuid)',
    'subscription_state_for(uuid)', 'subscription_grant_media(uuid,public.quota_section,uuid,uuid[],interval)'
  ]) as f(sig)
  cross join unnest(array['anon', 'authenticated', 'service_role']) as r(role)
  where has_function_privilege(r.role, 'public.' || f.sig, 'EXECUTE')
), 'the internal decision functions are not callable by any API role');
select ok(not exists (
  select 1 from pg_proc as p
  where p.pronamespace = 'public'::regnamespace and p.prosecdef
    and (p.proname like 'subscription%'
         or p.proname in ('create_core_entity', 'update_core_entity', 'get_subscription_state',
                          'apply_subscription_provider_event', 'toolkit_document_quota_reserve',
                          'toolkit_document_quota_commit'))
    and not coalesce(p.proconfig, array[]::text[]) @> array['search_path=""']
), 'every SECURITY DEFINER function pins an empty search_path');
select ok(not exists (
  select 1 from pg_proc as p
  cross join unnest(array['anon', 'authenticated']) as r(role)
  where p.pronamespace = 'public'::regnamespace
    and (p.proname like 'subscription%'
         or p.proname in ('apply_subscription_provider_event', 'toolkit_document_quota_reserve',
                          'toolkit_document_quota_commit', 'guard_core_entity_client_write'))
    and has_function_privilege(r.role, p.oid, 'EXECUTE')
), 'no subscription helper is callable by a client role');
select is((select count(*)::integer from public.plan_limits
  where plan_code = 'free' and limit_value = 5), 11, 'Free limit is 5 in all 11 sections');

-- The production schema has no test facility.
select ok(to_regclass('public.deployment_environment') is null
  and to_regclass('public.staging_test_allowlist') is null
  and to_regclass('public.staging_test_entitlements') is null
  and to_regclass('public.staging_test_audit') is null
  and to_regprocedure('public.staging_test_control(uuid,text)') is null,
  'no Staging test object exists in the production schema');
select ok(public.subscription_accepts_sandbox() = false
  and public.subscription_override_entitlement(pg_temp.uid('a')) is null
  and (public.subscription_test_mode_state(pg_temp.uid('a')) ->> 'available')::boolean = false,
  'the three seams are constants that grant nothing');
select is(pg_temp.state('a', 'plan'), 'free', 'and the state reports Free');

-- Cutover.
select throws_like($$select public.subscription_cutover('actual', 'yes')$$,
  '%ENFORCE%', 'the cutover needs its confirmation word');
select throws_like($$select public.subscription_cutover('everything', 'ENFORCE')$$,
  '%baseline%', 'and a known baseline');
select ok(has_column_privilege('authenticated', 'public.brokers', 'notes', 'UPDATE'),
  'before cutover existing builds keep their direct writes');
select is(public.subscription_cutover('actual', 'ENFORCE') ->> 'outcome', 'enforced', 'cutover runs');
select is(public.subscription_cutover('actual', 'ENFORCE') ->> 'outcome', 'already_enforced',
  'and is idempotent');
select ok(not has_function_privilege('authenticated', 'public.subscription_cutover(text,text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.subscription_cutover(text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.subscription_cutback(text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.subscription_cutback(text)', 'EXECUTE'),
  'no API role can run the cutover or the cutback');
select ok(not exists (
  select 1 from unnest(array['requests', 'offers', 'owners', 'offices', 'brokers', 'watchmen']) as t(name)
  where has_table_privilege('authenticated', 'public.' || t.name, 'INSERT')
     or has_column_privilege('authenticated', 'public.' || t.name, 'notes', 'UPDATE')
     or has_table_privilege('authenticated', 'public.' || t.name, 'DELETE')
     or not has_column_privilege('authenticated', 'public.' || t.name, 'deleted_at', 'UPDATE')
), 'core tables accept only the soft delete directly');
select ok(not has_table_privilege('authenticated', 'public.request_areas', 'INSERT')
  and not has_table_privilege('authenticated', 'public.offer_areas', 'DELETE'),
  'area tables are not client-writable');

select is(pg_temp.state('a', 'plan'), 'free', 'a new verified account is Free');
select is(pg_temp.state('a', 'read_only'), 'false', 'a new account is not read-only');
select is(pg_temp.call('a', $$select public.get_subscription_state() ->> 'plan'$$), 'free',
  'a signed-in client reads its own state');

-- A superseded session gets nothing.
update public.user_active_sessions set active_session_id = pg_temp.sid('h')
  where user_id = pg_temp.uid('h');
insert into auth.sessions (id, user_id, created_at, updated_at)
  values (md5('session:h-old')::uuid, pg_temp.uid('h'), now(), now());
update public.user_active_sessions set active_session_id = md5('session:h-old')::uuid
  where user_id = pg_temp.uid('h');
select is(pg_temp.call('h', $$select public.get_subscription_state() ->> 'plan'$$), '42501',
  'a superseded session cannot read the state');
select is(pg_temp.mk('h', 'brokers', 1), '42501', 'a superseded session cannot create');
select is(pg_temp.used('h', 'brokers'), 0::bigint, 'and is not charged');

-- ---------------------------------------------------------------------------
-- A/B. Creation and per-item edits on the six core sections
-- ---------------------------------------------------------------------------

select is(pg_temp.core_flow('requests'), 'ok', 'requests: full create and edit contract');
select is(pg_temp.core_flow('offers'), 'ok', 'offers: full create and edit contract');
select is(pg_temp.core_flow('owners'), 'ok', 'owners: full create and edit contract');
select is(pg_temp.core_flow('offices'), 'ok', 'offices: full create and edit contract');
select is(pg_temp.core_flow('brokers'), 'ok', 'brokers: full create and edit contract');
select is(pg_temp.core_flow('watchmen'), 'ok', 'watchmen: full create and edit contract');
select is(pg_temp.state('a', 'read_only'), 'false',
  'five used in every section is not an over-limit account');
select is((select owner_id from public.brokers where id = pg_temp.item('a', 'brokers', 2)),
  pg_temp.uid('a'), 'the owner comes from auth, never from the payload');
select is(pg_temp.used('b', 'brokers'), 0::bigint, 'another account is unaffected');
select is(pg_temp.mk('b', 'brokers', 1), 'created', 'and keeps its own allowance');

-- An id another account owns can be neither read nor replayed.
select is(pg_temp.call('b', format(
    $f$select public.create_core_entity('brokers', %L::uuid, %L::jsonb) ->> 'outcome'$f$,
    pg_temp.item('a', 'brokers', 2), pg_temp.body('brokers', 'e3'))), 'PBQ04',
  'a create on another account''s id is refused');

-- Areas are content; status is not.
select is(pg_temp.call('a', format(
    $f$select public.update_core_entity('requests', %L::uuid, %L::uuid, %L::jsonb, '["Marina","JBR"]'::jsonb) ->> 'outcome'$f$,
    pg_temp.item('a', 'requests', 4), pg_temp.req('areas1'),
    pg_temp.body('requests', 'base'))), 'updated', 'changing areas is a content edit');
select is(pg_temp.edits('a', 'requests', 4), 1, 'and costs one edit');
select is((select array_agg(area order by ordinal) from public.request_areas
  where request_id = pg_temp.item('a', 'requests', 4)), array['Marina', 'JBR'],
  'parent and areas are written together');
select is(pg_temp.call('a', format(
    $f$select public.update_core_entity('requests', %L::uuid, %L::uuid, %L::jsonb, '["Marina","JBR"]'::jsonb) ->> 'outcome'$f$,
    pg_temp.item('a', 'requests', 4), pg_temp.req('areas2'),
    pg_temp.body('requests', 'base'))), 'unchanged', 'the same areas are a no-op');
select is(pg_temp.call('a', format(
    $f$select public.update_core_entity('requests', %L::uuid, %L::uuid, %L::jsonb, '["Marina","JBR"]'::jsonb) ->> 'outcome'$f$,
    pg_temp.item('a', 'requests', 4), pg_temp.req('status1'),
    pg_temp.body('requests', 'base') || '{"status":"closed"}'::jsonb)), 'status_updated',
  'a status-only change is not a content edit');
select is(pg_temp.edits('a', 'requests', 4), 1, 'and costs nothing');

-- A failed child write leaves no parent and no charge.
select is(pg_temp.call('b', format(
    $f$select public.create_core_entity('requests', %L::uuid, %L::jsonb, '[1]'::jsonb) ->> 'outcome'$f$,
    pg_temp.item('b', 'requests', 1), pg_temp.body('requests', 'x'))), 'PBQ04',
  'an invalid area list is refused');
select is(pg_temp.used('b', 'requests'), 0::bigint, 'a failed create consumes nothing');

-- One save with media is one edit, and retrying it is not another.
select is(pg_temp.mk('b', 'offers', 1), 'created', 'an Offer for the media checks');
select is(pg_temp.call('b', format(
    $f$select public.update_core_entity('offers', %L::uuid, %L::uuid, %L::jsonb, '[]'::jsonb, array[%L]::uuid[]) ->> 'outcome'$f$,
    pg_temp.item('b', 'offers', 1), pg_temp.req('media1'), pg_temp.body('offers', 'base'),
    md5('media-1')::uuid)), 'updated', 'a save that adds media is a content edit');
select is(pg_temp.edits('b', 'offers', 1), 1, 'and costs one edit');
select is(pg_temp.call('b', format(
    $f$select public.update_core_entity('offers', %L::uuid, %L::uuid, %L::jsonb, '[]'::jsonb, array[%L]::uuid[]) ->> 'outcome'$f$,
    pg_temp.item('b', 'offers', 1), pg_temp.req('media2'), pg_temp.body('offers', 'base'),
    md5('media-1')::uuid)), 'unchanged', 'retrying the same media save changes nothing');
select is(pg_temp.edits('b', 'offers', 1), 1, 'and costs nothing');
select is(public.subscription_authorize_media_change(pg_temp.uid('b'), 'offers',
    pg_temp.item('b', 'offers', 1), md5('media-1')::uuid), 'allowed',
  'the Worker may change the media that save paid for');
select is(public.subscription_authorize_media_change(pg_temp.uid('b'), 'offers',
    pg_temp.item('b', 'offers', 1), md5('media-2')::uuid), 'edit_required',
  'but no other media');

-- ---------------------------------------------------------------------------
-- E. Toolkit documents
-- ---------------------------------------------------------------------------

select is(pg_temp.toolkit_flow('scanner'), 'ok', 'scanner: full document contract');
select is(pg_temp.toolkit_flow('signature'), 'ok', 'signature: full document contract');
select is(pg_temp.toolkit_flow('image_to_pdf'), 'ok', 'image_to_pdf: full document contract');
select is(pg_temp.toolkit_flow('combine_pdfs'), 'ok', 'combine_pdfs: full document contract');

select ok(pg_temp.authz('f', 'scanner', 1) = 'created' and pg_temp.conf('f', 'scanner', 1) = 'confirmed'
  and pg_temp.authz('f', 'scanner', 2) = 'created' and pg_temp.conf('f', 'scanner', 2) = 'confirmed'
  and pg_temp.authz('f', 'scanner', 3) = 'created' and pg_temp.conf('f', 'scanner', 3) = 'confirmed'
  and pg_temp.authz('f', 'scanner', 4) = 'created' and pg_temp.conf('f', 'scanner', 4) = 'confirmed',
  'a fresh account stores four documents');
select is(pg_temp.authz('f', 'scanner', 5), 'created', 'the fifth upload is reserved');
select is(pg_temp.authz('f', 'scanner', 6), 'PBQ01', 'a fresh pending upload holds the last place');
select is(pg_temp.used('f', 'scanner'), 4::bigint, 'an unfinished upload consumes nothing');
update public.toolkit_documents set last_authorized_at = now() - interval '25 hours'
  where id = pg_temp.item('f', 'scanner', 5);
select is(pg_temp.authz('f', 'scanner', 6), 'created', 'an abandoned upload stops holding it');
select is(pg_temp.conf('f', 'scanner', 6), 'confirmed', 'the new document completes');
select is(pg_temp.conf('f', 'scanner', 5), 'PBQ01',
  'the old upload cannot finish past the limit');
select is(pg_temp.used('f', 'scanner'), 5::bigint, 'the count is exactly five');

-- ---------------------------------------------------------------------------
-- Quotations
-- ---------------------------------------------------------------------------

create function pg_temp.qh(p_title text) returns jsonb language sql as $$
  select jsonb_build_object('property_title', p_title, 'property_type', null, 'parking', null,
    'subtitle', null, 'display_date', null, 'start_date_text', null, 'end_date_text', null,
    'currency_code', 'AED', 'professional_fee', null, 'total_amount', 1000,
    'number_of_installments', null, 'payment_type', null, 'insurance_amount', null,
    'insurance_returnable', null, 'office_name', 'Office', 'custom_note', null,
    'welcome_message_mode', 'auto', 'custom_welcome_message', null);
$$;
create function pg_temp.qs(p_user text, p_n integer, p_version bigint, p_title text) returns text
language sql as $$
  select pg_temp.call(p_user, format(
    $f$select r.outcome from public.save_quotation(%L::uuid, %s, %L::jsonb, '[]'::jsonb, null, '[]'::jsonb) as r$f$,
    pg_temp.item(p_user, 'quotations', p_n), coalesce(p_version::text, 'null'), pg_temp.qh(p_title)));
$$;
create function pg_temp.qv(p_user text, p_n integer) returns bigint language sql as $$
  select version from public.quotations where id = pg_temp.item(p_user, 'quotations', p_n);
$$;

select ok(pg_temp.qs('g', 1, null, 'Q') = 'created' and pg_temp.qs('g', 2, null, 'Q') = 'created'
  and pg_temp.qs('g', 3, null, 'Q') = 'created' and pg_temp.qs('g', 4, null, 'Q') = 'created'
  and pg_temp.qs('g', 5, null, 'Q') = 'created', 'five Quotations are created');
select is(pg_temp.qs('g', 6, null, 'Q'), 'PBQ01', 'the sixth Quotation is refused');
select is((select count(*)::integer from public.quotations
  where id = pg_temp.item('g', 'quotations', 6)), 0, 'and leaves no row');
select is(pg_temp.qs('g', 1, null, 'Q'), 'replayed', 'a retried create is a replay');
select is(pg_temp.used('g', 'quotations'), 5::bigint, 'and is not counted again');
select is(pg_temp.qs('g', 1, pg_temp.qv('g', 1), 'Q'), 'updated', 'saving identical content succeeds');
select is(pg_temp.edits('g', 'quotations', 1), 0, 'but costs no edit');
select is(pg_temp.qs('g', 1, pg_temp.qv('g', 1), 'E1'), 'updated', 'first real edit');
select is(pg_temp.qs('g', 1, pg_temp.qv('g', 1), 'E2'), 'updated', 'second real edit');
select is(pg_temp.qs('g', 1, pg_temp.qv('g', 1), 'E3'), 'updated', 'third real edit');
select is(pg_temp.qs('g', 1, pg_temp.qv('g', 1), 'E4'), 'PBQ02', 'the fourth edit is refused');
select is((select property_title from public.quotations where id = pg_temp.item('g', 'quotations', 1)),
  'E3', 'and the whole aggregate stays as it was');

-- ---------------------------------------------------------------------------
-- C. Lifecycle from verified provider events
-- ---------------------------------------------------------------------------

select is(pg_temp.event('c', 'sub-c', 'c1', 'unknown', '0 s', '30 days'), 'processed',
  'an unknown provider state can be recorded');
select is(pg_temp.state('c', 'plan'), 'free', 'unknown is never Plus');
select is(pg_temp.event('c', 'sub-sandbox', 'c-sb', 'active', '0 s', '30 days', true, 'sandbox'),
  'processed', 'a sandbox purchase can be recorded');
select is(pg_temp.state('c', 'plan'), 'free', 'sandbox never grants Plus without a staging marker');
select is(pg_temp.event('c', 'sub-c', 'c2', 'active', '1 s', '30 days'), 'processed', 'purchase');
select is(pg_temp.state('c', 'status'), 'plus_renewing', 'Free to Plus');
select is(pg_temp.event('c', 'sub-c', 'c2', 'active', '1 s', '30 days'), 'duplicate',
  'a repeated event is a duplicate');
select is(pg_temp.mk('c', 'brokers', 1), 'created', 'Plus creates');
select ok(pg_temp.mk('c', 'brokers', 2) = 'created' and pg_temp.mk('c', 'brokers', 3) = 'created'
  and pg_temp.mk('c', 'brokers', 4) = 'created' and pg_temp.mk('c', 'brokers', 5) = 'created'
  and pg_temp.mk('c', 'brokers', 6) = 'created', 'Plus creates past five');
select ok(pg_temp.ed('c', 'c', 'brokers', 1, 'p1', 'cp1') = 'updated'
  and pg_temp.ed('c', 'c', 'brokers', 1, 'p2', 'cp2') = 'updated'
  and pg_temp.ed('c', 'c', 'brokers', 1, 'p3', 'cp3') = 'updated'
  and pg_temp.ed('c', 'c', 'brokers', 1, 'p4', 'cp4') = 'updated'
  and pg_temp.edits('c', 'brokers', 1) = 0, 'Plus edits are unlimited and use no Free edits');

select is(pg_temp.event('c', 'sub-c', 'c3', 'cancel_scheduled', '2 s', '30 days', false), 'processed',
  'cancellation');
select is(pg_temp.state('c', 'plan') || '/' || pg_temp.state('c', 'status'),
  'plus/plus_cancel_scheduled', 'canceled but paid: still Plus until the period ends');
select is(pg_temp.event('c', 'sub-c', 'c-old', 'active', '-1 hour', '60 days'), 'stale',
  'an older event arriving late is stale');
select is(pg_temp.state('c', 'status'), 'plus_cancel_scheduled', 'and changes nothing');
-- The paid-through date is deliberately still ahead: the state decides.
select is(pg_temp.event('c', 'sub-c', 'c4', 'expired', '3 s', '30 days', false), 'processed', 'expiry');
select is(pg_temp.state('c', 'status'), 'expired_over_limit',
  'six brokers after Plus: expired over limit');
select is(pg_temp.mk('c', 'owners', 1), 'PBQ03', 'over limit blocks creation in every section');
select is(pg_temp.ed('c', 'c', 'brokers', 2, 'blocked', 'cx1'), 'PBQ03', 'and blocks content edits');
select ok(pg_temp.call('c', format('select id::text from public.brokers where id = %L',
    pg_temp.item('c', 'brokers', 2))) = pg_temp.item('c', 'brokers', 2)::text,
  'existing records stay readable');
select is(pg_temp.call('c', format(
    'update public.brokers set deleted_at = now() where id = %L returning id::text',
    pg_temp.item('c', 'brokers', 6))), pg_temp.item('c', 'brokers', 6)::text, 'and deletable');
select is(pg_temp.state('c', 'status'), 'expired_over_limit', 'deletion does not lift the restriction');
select is(pg_temp.event('c', 'sub-c', 'c5', 'active', '4 s', '30 days'), 'processed', 'reactivation');
select is(pg_temp.ed('c', 'c', 'brokers', 2, 'back', 'cx2'), 'updated', 'reactivated Plus can edit again');
select is(pg_temp.event('c', 'sub-c', 'c6', 'refunded', '5 s', '30 days', false), 'processed', 'refund');
select is(pg_temp.state('c', 'plan'), 'free', 'a refund ends Plus even with a future paid-through');
select is(pg_temp.event('c', 'sub-c', 'c7', 'billing_issue', '6 s', '-1 s', true, 'production',
  'google_play', '2 days'), 'processed', 'billing issue with grace');
select is(pg_temp.state('c', 'status'), 'payment_issue', 'a billing issue in grace keeps Plus');
select is(pg_temp.event('c', 'sub-c', 'c8', 'revoked', '7 s', '30 days', false), 'processed', 'revocation');
select is(pg_temp.state('c', 'plan'), 'free', 'revocation ends Plus');

select is(pg_temp.event('b', 'sub-c', 'foreign', 'active', '8 s', '30 days'), 'ownership_conflict',
  'a purchase cannot be moved to another account');
select is(pg_temp.state('b', 'plan'), 'free', 'and grants that account nothing');
select is(public.apply_subscription_provider_event('tap', 'no-acct', 'TEST', now(),
    '00000000-0000-4000-8000-0000000000ff', 'sub-none', null, null, 'active', true,
    null, now() + interval '30 days', null, 'production', null), 'no_account',
  'an event for an unknown account creates nothing');
select is((select count(*)::integer from public.subscription_provider_records
  where provider_subscription_id = 'sub-none'), 0, 'not even a record');
select is(pg_temp.event('b', 'sub-b-tap', 'b-t', 'active', '0 s', '30 days', true, 'production', 'tap'),
  'processed', 'a second provider has its own record');
select is(pg_temp.event('b', 'sub-b-tap', 'b-g', 'expired', '1 s', '-1 s', false, 'production', 'google_play'),
  'processed', 'the same external id at another provider is a separate subscription');
select is(pg_temp.state('b', 'plan'), 'plus', 'so one provider cannot cancel another');

select * from finish();
rollback;
