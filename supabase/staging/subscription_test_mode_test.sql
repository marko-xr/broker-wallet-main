-- The Staging test facility. Run on a disposable database after
-- supabase/staging/subscription_test_mode.sql. Never part of `supabase test db`.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

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

select is(public.subscription_cutover('actual', 'ENFORCE') ->> 'outcome', 'enforced', 'enforced state');
select public.apply_subscription_provider_event('google_play', 'sb1', 'TEST', now(), pg_temp.uid('c'), 'sub-sb',
  'plus_monthly', 'monthly', 'active', true, now(), now() + interval '30 days', null, 'sandbox', null);


select throws_ok($$select public.staging_test_control(md5('user:d')::uuid, 'plus_on')$$,
  'PBT01', 'not_staging', 'test control is refused without a staging marker');
select throws_ok($$insert into public.deployment_environment (environment, project_ref)
    values ('staging', 'rbvcnvqpdqrhywcgxkne')$$,
  '23514', null, 'the production project can never be marked staging');
select throws_ok($$insert into public.deployment_environment (environment, project_ref)
    values ('production', 'abcdefghijklmnopqrst')$$,
  '23514', null, 'only a staging row can exist');

insert into public.deployment_environment (environment, project_ref)
  values ('staging', 'abcdefghijklmnopqrst');

select is(public.staging_test_control(pg_temp.uid('b'), 'plus_on') ->> 'code', 'not_allowlisted',
  'an ordinary account is refused on staging');
select is((select count(*)::integer from public.staging_test_entitlements
  where user_id = pg_temp.uid('b')), 0, 'and receives nothing');
select is((select outcome from public.staging_test_audit where user_id = pg_temp.uid('b')),
  'rejected_not_allowlisted', 'the refusal is audited');

insert into public.staging_test_allowlist (user_id, note) values (pg_temp.uid('d'), 'quota test');
select is(pg_temp.call('d', $$select (public.get_subscription_state() -> 'test_mode' ->> 'available')$$),
  'true', 'the allowlisted account sees the control');
select is(pg_temp.call('b', $$select (public.get_subscription_state() -> 'test_mode' ->> 'available')$$),
  'false', 'an ordinary account does not');
select is(pg_temp.call('d', format($f$select public.staging_test_control(%L::uuid, 'plus_on')::text$f$,
  pg_temp.uid('d'))), '42501', 'the client cannot call the control directly');

-- The owner's required flow.
select ok(pg_temp.mk('d', 'offers', 1) = 'created' and pg_temp.mk('d', 'offers', 2) = 'created'
  and pg_temp.mk('d', 'offers', 3) = 'created' and pg_temp.mk('d', 'offers', 4) = 'created'
  and pg_temp.mk('d', 'offers', 5) = 'created', 'OFF: five are created');
select is(pg_temp.mk('d', 'offers', 6), 'PBQ01', 'OFF: the sixth is rejected');
select is(public.staging_test_control(pg_temp.uid('d'), 'plus_on') #>> '{state,plan}', 'plus', 'ON');
select is(pg_temp.state('d', 'is_test'), 'true', 'the state is marked as a test');
select ok(pg_temp.mk('d', 'offers', 6) = 'created' and pg_temp.mk('d', 'offers', 7) = 'created'
  and pg_temp.mk('d', 'offers', 8) = 'created', 'ON: six, seven and eight are created');
select is(public.staging_test_control(pg_temp.uid('d'), 'plus_off') #>> '{state,status}',
  'expired_over_limit', 'OFF: over the limit, so read-only');
select is(pg_temp.mk('d', 'offers', 9), 'PBQ03', 'OFF: further creation is rejected');
select is(pg_temp.used('d', 'offers'), 8::bigint, 'switching never erased the history');
select is(public.staging_test_control(pg_temp.uid('d'), 'plus_on') #>> '{state,plan}', 'plus', 'ON again');
select is(pg_temp.mk('d', 'offers', 9), 'created', 'ON: creation is allowed again');

select is(public.staging_test_control(pg_temp.uid('d'), 'auto_renew_off') #>> '{state,status}',
  'plus_cancel_scheduled', 'advanced: canceled but active');
select is(public.staging_test_control(pg_temp.uid('d'), 'expired') #>> '{state,status}',
  'expired_over_limit', 'advanced: expired');
select is(public.staging_test_control(pg_temp.uid('d'), 'plus_on') #>> '{state,plan}', 'plus', 'back on');
select is((select count(*)::integer from public.subscription_provider_records
  where user_id = pg_temp.uid('d')), 0, 'test mode never creates a provider record');
select ok((select count(*) from public.staging_test_audit
  where user_id = pg_temp.uid('d') and outcome = 'applied') >= 6, 'every change is audited');
select throws_ok($$update public.staging_test_entitlements set expires_at = now() + interval '30 days'
    where user_id = md5('user:d')::uuid$$, '23514', null, 'an override cannot outlive its bound');
update public.staging_test_entitlements set started_at = now() - interval '4 days',
    expires_at = now() - interval '1 second' where user_id = pg_temp.uid('d');
select is(pg_temp.state('d', 'plan'), 'free', 'an expired override is no longer Plus');
update public.staging_test_entitlements set started_at = now(), expires_at = now() + interval '1 hour'
  where user_id = pg_temp.uid('d');
select is(pg_temp.state('d', 'plan'), 'plus', 'a live override is Plus on staging');
delete from public.deployment_environment;
select is(pg_temp.state('d', 'plan'), 'free', 'the same row grants nothing without the staging marker');
select is(pg_temp.call('d', $$select (public.get_subscription_state() -> 'test_mode' ->> 'available')$$),
  'false', 'and the control disappears');


select is(pg_temp.state('c', 'plan'), 'free', 'without the marker a sandbox purchase grants nothing');
insert into public.deployment_environment (environment, project_ref)
  values ('staging', 'abcdefghijklmnopqrst');
select is(pg_temp.state('c', 'plan'), 'plus', 'on Staging a sandbox purchase counts');

select * from finish();
rollback;
