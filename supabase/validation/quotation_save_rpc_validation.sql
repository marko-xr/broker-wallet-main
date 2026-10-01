-- Run ONLY after owner review/approval, with psql as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/quotation_save_rpc_validation.sql
-- psql's \ir includes the exact migration file inside this transaction.
-- Do not paste this into the SQL Editor: \ir is a psql command.
-- Every test identity and every schema/data change is discarded by ROLLBACK.
-- No COMMIT appears in this file or in the included migration.

\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regprocedure('public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') is not null
     or not (select rolbypassrls from pg_roles where rolname = 'postgres')
     or (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in (
           'quotations', 'quotation_downpayments',
           'quotation_government_fees', 'quotation_administrative_fees')
           and pg_get_userbyid(c.relowner) = 'postgres'
           and c.relrowsecurity and not c.relforcerowsecurity) <> 4
     or not has_any_column_privilege('authenticated', 'public.quotations', 'INSERT')
     or not has_column_privilege('authenticated', 'public.quotations',
                                'property_title', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.quotations',
                                'deleted_at', 'UPDATE')
     or not has_table_privilege('authenticated', 'public.quotation_downpayments', 'INSERT')
     or not has_table_privilege('authenticated', 'public.quotation_government_fees', 'INSERT')
     or not has_table_privilege('authenticated', 'public.quotation_administrative_fees', 'INSERT')
     or exists (select 1 from pg_policy where polrelid = 'public.quotations'::regclass
       and polname = 'quotations_direct_soft_delete_only')
     or exists (select 1 from auth.users where id in (
       'a0a00000-0000-4000-8000-00000000000a'::uuid,
       'a0a00000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from auth.users where email in (
       'quotation-a@validation.invalid', 'quotation-b@validation.invalid'))
     or exists (select 1 from public.quotations where id in (
       'a0a00000-0000-4000-8000-0000000000a1'::uuid,
       'a0a00000-0000-4000-8000-0000000000a2'::uuid))
     or exists (select 1 from public.media_objects where id =
       'a0a00000-0000-4000-8000-0000000000a3'::uuid)
     or exists (select 1 from public.media_objects where bucket = 'validation'
       and object_key =
       'profiles/a0a00000-0000-4000-8000-00000000000a/quotations/a0a00000-0000-4000-8000-0000000000a1/logo.jpg')
     or exists (select 1 from pg_trigger where tgrelid = 'auth.users'::regclass
       and not tgisinternal and tgname not in (
         'on_auth_user_created', 'on_auth_user_identity_updated',
         'guard_pending_phone_change'))
     or exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass
       and not tgisinternal and tgname not in (
         'profiles_bump_sync_version', 'profiles_validate_direct_media')) then
    raise exception 'quotation validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20260930204217_quotation_save_rpc.sql

create function pg_temp.assert_true(p_ok boolean, p_case text)
returns void language plpgsql security invoker as $assert$
begin
  if p_ok is distinct from true then
    raise exception 'quotation validation failed: %', p_case;
  end if;
end;
$assert$;

create function pg_temp.expect_error(p_sql text, p_code text)
returns void language plpgsql security invoker as $expect$
declare
  v_code text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_code = returned_sqlstate;
    if v_code <> p_code then
      raise exception 'expected SQLSTATE %, got % for %', p_code, v_code, p_sql;
    end if;
    return;
  end;
  raise exception 'expected SQLSTATE %, call succeeded: %', p_code, p_sql;
end;
$expect$;

create temp table quotation_validation_payload (
  header jsonb not null,
  downpayments jsonb not null,
  government_fees jsonb,
  administrative_fees jsonb not null
) on commit drop;
insert into quotation_validation_payload values (
  '{"property_title":"Original","property_type":"apartment","parking":true,
    "subtitle":"Offer","display_date":"1 Oct 2026","start_date_text":"Oct 2026",
    "end_date_text":"Oct 2027","currency_code":"AED","professional_fee":100,
    "total_amount":1000,"number_of_installments":2,"payment_type":"cash",
    "insurance_amount":200,"insurance_returnable":true,"office_name":"Office",
    "custom_note":null,"welcome_message_mode":"auto","custom_welcome_message":null}'::jsonb,
  '[{"sequence_number":2,"method":"cheque","due_at":null,"amount":500},
    {"sequence_number":1,"method":"cash","due_at":"2026-10-01T10:00:00Z","amount":500}]'::jsonb,
  '{"percent_of_total_rent":5,"municipality":50,"electricity":20,
    "sewerage":10,"total":80}'::jsonb,
  '[{"ordinal":1,"title":"Processing","amount":20},
    {"ordinal":0,"title":"Registration","amount":30}]'::jsonb
);
grant select on quotation_validation_payload to authenticated, anon;

create function pg_temp.save_case(
  p_id uuid, p_version bigint,
  p_header jsonb default null,
  p_downpayments jsonb default null,
  p_government_fees jsonb default null,
  p_administrative_fees jsonb default null
)
returns table (quotation_id uuid, resulting_version bigint, outcome text,
               created_at timestamptz, updated_at timestamptz)
language sql security invoker set search_path = '' as $save$
  select s.* from pg_temp.quotation_validation_payload p
  cross join lateral public.save_quotation(
    p_id, p_version, coalesce(p_header, p.header),
    coalesce(p_downpayments, p.downpayments),
    coalesce(p_government_fees, p.government_fees),
    coalesce(p_administrative_fees, p.administrative_fees)) s;
$save$;

select pg_temp.assert_true(
  (select prosecdef and pg_get_userbyid(proowner) = 'postgres'
          and exists (
            select 1 from pg_catalog.pg_options_to_table(proconfig) cfg
            where cfg.option_name = 'search_path'
              and cfg.option_value in ('', pg_catalog.quote_ident('')))
   from pg_proc where oid =
    'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)'::regprocedure)
  and not exists (
    select 1 from pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) acl
    where p.oid =
      'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)'::regprocedure
      and acl.grantee = 0::oid and acl.privilege_type = 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE'),
  'postgres-owned definer, empty search_path and least-privilege grants');

select pg_temp.assert_true(
  not has_any_column_privilege('authenticated', 'public.quotations', 'INSERT')
  and has_table_privilege('authenticated', 'public.quotations', 'SELECT')
  and not has_table_privilege('authenticated', 'public.quotations', 'DELETE')
  and has_column_privilege('authenticated', 'public.quotations', 'deleted_at', 'UPDATE')
  and not exists (
    select 1 from pg_attribute a
    where a.attrelid = 'public.quotations'::regclass and a.attnum > 0
      and not a.attisdropped and a.attname <> 'deleted_at'
      and has_column_privilege('authenticated', 'public.quotations', a.attnum, 'UPDATE'))
  and not has_table_privilege('authenticated', 'public.quotation_downpayments', 'INSERT')
  and has_table_privilege('authenticated', 'public.quotation_downpayments', 'SELECT')
  and not has_table_privilege('authenticated', 'public.quotation_downpayments', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotation_downpayments', 'DELETE')
  and not has_table_privilege('authenticated', 'public.quotation_government_fees', 'INSERT')
  and has_table_privilege('authenticated', 'public.quotation_government_fees', 'SELECT')
  and not has_table_privilege('authenticated', 'public.quotation_government_fees', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotation_government_fees', 'DELETE')
  and not has_table_privilege('authenticated', 'public.quotation_administrative_fees', 'INSERT')
  and has_table_privilege('authenticated', 'public.quotation_administrative_fees', 'SELECT')
  and not has_table_privilege('authenticated', 'public.quotation_administrative_fees', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotation_administrative_fees', 'DELETE')
  and has_column_privilege('service_role', 'public.quotations',
                           'office_logo_media_id', 'UPDATE')
  and has_column_privilege('service_role', 'public.quotations',
                           'pdf_media_id', 'UPDATE')
  and has_table_privilege('service_role', 'public.quotation_downpayments', 'INSERT'),
  'direct aggregate writes revoked; read and deleted_at-only update retained');
select pg_temp.assert_true(
  (select polpermissive = false and polcmd = 'w'
          and pg_get_expr(polqual, polrelid) ~* 'deleted_at is null'
          and pg_get_expr(polwithcheck, polrelid) ~* 'deleted_at is not null'
   from pg_policy where polrelid = 'public.quotations'::regclass
     and polname = 'quotations_direct_soft_delete_only'),
  'restrictive soft-delete-only RLS policy installed');

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('a0a00000-0000-4000-8000-00000000000a', 'quotation-a@validation.invalid',
   '{"name":"Quotation A"}'::jsonb, now(), now()),
  ('a0a00000-0000-4000-8000-00000000000b', 'quotation-b@validation.invalid',
   '{"name":"Quotation B"}'::jsonb, now(), now());
select pg_temp.assert_true((select count(*) = 2 from public.profiles where id in (
  'a0a00000-0000-4000-8000-00000000000a'::uuid,
  'a0a00000-0000-4000-8000-00000000000b'::uuid)),
  'Auth trigger created both test profiles');

set local role anon;
do $anon_denied$
declare
  v_denied boolean := false;
begin
  begin
    perform 1 from public.save_quotation(
      'a0a00000-0000-4000-8000-0000000000a1', null, '{}'::jsonb,
      '[]'::jsonb, null, '[]'::jsonb);
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'anon executed save_quotation';
  end if;
end;
$anon_denied$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', null)$sql$, 'PQT01');
select set_config('request.jwt.claim.sub',
  'a0a00000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims',
  '{"sub":"a0a00000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select pg_temp.assert_true(auth.uid() =
  'a0a00000-0000-4000-8000-00000000000a'::uuid, 'A JWT maps to auth.uid');
select pg_temp.expect_error($sql$insert into public.quotations
  (id, owner_id, property_title) values
  ('a0a00000-0000-4000-8000-0000000000a2',
   'a0a00000-0000-4000-8000-00000000000a', 'direct')$sql$, '42501');

select pg_temp.assert_true((select outcome = 'created' and resulting_version = 1
  from pg_temp.save_case('a0a00000-0000-4000-8000-0000000000a1', null)),
  'A creates full quotation');
select pg_temp.expect_error($sql$update public.quotations set property_title = 'direct'
  where id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$update public.quotations set office_logo_media_id = null
  where id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$update public.quotations set pdf_media_id = null
  where id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$insert into public.quotation_downpayments
  (quotation_id, sequence_number, method, amount) values
  ('a0a00000-0000-4000-8000-0000000000a1', 3, 'cash', 1)$sql$, '42501');
select pg_temp.expect_error($sql$update public.quotation_downpayments set amount = 1
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$delete from public.quotation_downpayments
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$insert into public.quotation_government_fees
  (quotation_id, total) values
  ('a0a00000-0000-4000-8000-0000000000a1', 1)$sql$, '42501');
select pg_temp.expect_error($sql$update public.quotation_government_fees set total = 1
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$delete from public.quotation_government_fees
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$insert into public.quotation_administrative_fees
  (quotation_id, ordinal, title, amount) values
  ('a0a00000-0000-4000-8000-0000000000a1', 2, 'direct', 1)$sql$, '42501');
select pg_temp.expect_error($sql$update public.quotation_administrative_fees set amount = 1
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.expect_error($sql$delete from public.quotation_administrative_fees
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'$sql$, '42501');
select pg_temp.assert_true(
  (select owner_id = auth.uid() and office_logo_media_id is null and pdf_media_id is null
          and created_at > now() - interval '1 minute' and created_at <= now()
   from public.quotations where id = 'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 2 from public.quotation_downpayments where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 1 from public.quotation_government_fees where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and (select string_agg(title, ',' order by ordinal) = 'Registration,Processing'
       from public.quotation_administrative_fees where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and (select sum(amount) = 50 from public.quotation_administrative_fees where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and (select display_date = '1 Oct 2026' and start_date_text = 'Oct 2026'
              and end_date_text = 'Oct 2027'
       from public.quotations where id = 'a0a00000-0000-4000-8000-0000000000a1'),
  'header, owner, media defaults, ordered children persisted');
select pg_temp.assert_true((select outcome = 'replayed' and resulting_version = 1
  from pg_temp.save_case('a0a00000-0000-4000-8000-0000000000a1', null)),
  'identical create retry is idempotent');
select pg_temp.assert_true((select s.created_at = q.created_at
                              and s.updated_at = q.updated_at
                              and s.resulting_version = q.version
  from pg_temp.save_case('a0a00000-0000-4000-8000-0000000000a1', null) s
  join public.quotations q on q.id = s.quotation_id),
  'replay returns canonical stored version and timestamps');
select pg_temp.assert_true((select outcome = 'replayed' and resulting_version = 1
  from pg_temp.save_case('a0a00000-0000-4000-8000-0000000000a1', null,
    (select jsonb_set(header, '{professional_fee}', '100.0'::jsonb)
     from pg_temp.quotation_validation_payload),
    (select jsonb_set(downpayments, '{0,amount}', '500.0'::jsonb)
     from pg_temp.quotation_validation_payload))),
  'equivalent numeric JSON representations replay');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', null,
  (select jsonb_set(header, '{property_title}', '"Changed"')
   from pg_temp.quotation_validation_payload))$sql$, 'PQT06');

select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"owner_id":"a0a00000-0000-4000-8000-00000000000b"}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[{"sequence_number":1,"method":"cash","due_at":null,"amount":2,
     "quotation_id":"a0a00000-0000-4000-8000-0000000000a1"}]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[{"sequence_number":1,"method":"cash","due_at":null,"amount":-1}]'::jsonb)$sql$, '23514');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[{"sequence_number":1,"method":"cash","due_at":null,"amount":1},
    {"sequence_number":1,"method":"cheque","due_at":null,"amount":2}]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[{"sequence_number":1,"method":"cash","due_at":"not-a-date","amount":1}]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[{"sequence_number":1,"method":"cash","due_at":"2026-10-01T10:00:00","amount":1}]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[null]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null, null, null,
  '[{"ordinal":0,"title":"A","amount":1},
    {"ordinal":0,"title":"B","amount":2}]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null, null, null,
  '[1]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null, null,
  '[]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null, null,
  '{"percent_of_total_rent":101,"municipality":0,"electricity":0,
    "sewerage":0,"total":0}'::jsonb)$sql$, '23514');
select pg_temp.assert_true(not exists(select 1 from public.quotations where id =
  'a0a00000-0000-4000-8000-0000000000a2'), 'invalid child rolls back new header');

select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"office_logo_media_id":null}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"pdf_media_id":null}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"created_at":"2000-01-01"}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"updated_at":"2000-01-01"}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"version":99}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"deleted_at":null}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"payment_type":"invalid"}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"property_title":" "}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"total_amount":-1}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, '23514');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header - 'office_name' from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header || '{"parking":"yes"}'::jsonb
   from pg_temp.quotation_validation_payload))$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  '[]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '{}'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  null, null, '{}'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from public.save_quotation(
  'a0a00000-0000-4000-8000-0000000000a2', null, null,
  '[]'::jsonb, null, '[]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from public.save_quotation(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header from pg_temp.quotation_validation_payload), null, null,
  '[]'::jsonb)$sql$, 'PQT05');
select pg_temp.expect_error($sql$select * from public.save_quotation(
  'a0a00000-0000-4000-8000-0000000000a2', null,
  (select header from pg_temp.quotation_validation_payload), '[]'::jsonb,
  null, null)$sql$, 'PQT05');

select pg_temp.assert_true((select resulting_version = 1 from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', null)),
  'second owned quotation can be created after failed attempts');
select pg_temp.assert_true((select resulting_version = 2 from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a2', 1, null, null,
  '{"percent_of_total_rent":5,"municipality":50,"electricity":20,
    "sewerage":10,"total":90}'::jsonb)),
  'government fee values can be updated');
select pg_temp.assert_true((select total = 90 from public.quotation_government_fees
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a2'),
  'government update replaced its prior total');
select pg_temp.assert_true((select resulting_version = 3 from public.save_quotation(
  'a0a00000-0000-4000-8000-0000000000a2', 2,
  (select header from pg_temp.quotation_validation_payload),
  (select downpayments from pg_temp.quotation_validation_payload),
  null,
  (select administrative_fees from pg_temp.quotation_validation_payload))),
  'SQL null removes government fee row');
select pg_temp.assert_true(not exists(select 1 from public.quotation_government_fees
  where quotation_id = 'a0a00000-0000-4000-8000-0000000000a2'),
  'removed government row does not remain stale');

-- Seed one server-owned media reference to prove ordinary aggregate updates
-- leave a non-null ID untouched. This row and update are rolled back.
reset role;
insert into public.media_objects (id, owner_id, bucket, object_key, media_type, status)
values ('a0a00000-0000-4000-8000-0000000000a3',
        'a0a00000-0000-4000-8000-00000000000a', 'validation',
        'profiles/a0a00000-0000-4000-8000-00000000000a/quotations/a0a00000-0000-4000-8000-0000000000a1/logo.jpg',
        'image', 'ready');
update public.quotations set office_logo_media_id =
  'a0a00000-0000-4000-8000-0000000000a3'
where id = 'a0a00000-0000-4000-8000-0000000000a1';
-- The server-owned media update advances version to 2 via the existing trigger.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'a0a00000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims',
  '{"sub":"a0a00000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', null)$sql$, 'PQT06');
select pg_temp.assert_true((select outcome = 'updated' and resulting_version = 3
  from pg_temp.save_case('a0a00000-0000-4000-8000-0000000000a1', 2,
    (select jsonb_set(jsonb_set(header, '{property_title}', '"Updated"'),
                      '{subtitle}', 'null'::jsonb)
     from pg_temp.quotation_validation_payload),
    '[{"sequence_number":1,"method":"bank_transfer","due_at":null,"amount":1000}]'::jsonb,
    'null'::jsonb,
    '[{"ordinal":0,"title":"Only","amount":7}]'::jsonb)),
  'update advances version exactly once');
select pg_temp.assert_true(
  (select property_title = 'Updated' and subtitle is null and version = 3
          and office_logo_media_id = 'a0a00000-0000-4000-8000-0000000000a3'
   from public.quotations where id = 'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 1 and min(method::text) = 'bank_transfer'
       from public.quotation_downpayments where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and not exists (select 1 from public.quotation_government_fees where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 1 and min(title) = 'Only'
       from public.quotation_administrative_fees where quotation_id =
       'a0a00000-0000-4000-8000-0000000000a1'),
  'old children removed, order preserved, media ID retained');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 2)$sql$, 'PQT04');

select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 3,
  (select jsonb_set(header, '{property_title}', '"Should roll back"')
   from pg_temp.quotation_validation_payload),
  '[]'::jsonb, 'null'::jsonb,
  '[{"ordinal":0,"title":"Bad","amount":-1}]'::jsonb)$sql$, '23514');
select pg_temp.assert_true(
  (select property_title = 'Updated' and version = 3 from public.quotations where id =
    'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 1 from public.quotation_downpayments where quotation_id =
    'a0a00000-0000-4000-8000-0000000000a1')
  and (select count(*) = 1 from public.quotation_administrative_fees where quotation_id =
    'a0a00000-0000-4000-8000-0000000000a1'),
  'failed later child restores header and every prior child set');

select pg_temp.assert_true((select resulting_version = 4 from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 3,
  (select jsonb_set(header, '{property_title}', '"Updated again"')
   from pg_temp.quotation_validation_payload),
  '[]'::jsonb,
  '{"percent_of_total_rent":2,"municipality":1,"electricity":null,"sewerage":null,"total":1}'::jsonb,
  '[]'::jsonb)), 'government row can be reinserted');
select pg_temp.assert_true((select total = 1 from public.quotation_government_fees where
  quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'),
  'government total remains explicit');
select pg_temp.assert_true((select resulting_version = 5 from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 4,
  (select jsonb_set(header, '{property_title}', '"Final"')
   from pg_temp.quotation_validation_payload),
  '[]'::jsonb, 'null'::jsonb, '[]'::jsonb)),
  'government row can be removed');
select pg_temp.assert_true(not exists(select 1 from public.quotation_government_fees where
  quotation_id = 'a0a00000-0000-4000-8000-0000000000a1'),
  'government removal persisted');

select set_config('request.jwt.claim.sub',
  'a0a00000-0000-4000-8000-00000000000b', true);
select set_config('request.jwt.claims',
  '{"sub":"a0a00000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 5)$sql$, 'PQT02');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', null)$sql$, 'PQT02');
update public.quotations set deleted_at = now()
where id = 'a0a00000-0000-4000-8000-0000000000a1';

select set_config('request.jwt.claim.sub',
  'a0a00000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims',
  '{"sub":"a0a00000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select pg_temp.assert_true((select version = 5 and deleted_at is null
  from public.quotations where id = 'a0a00000-0000-4000-8000-0000000000a1'),
  'foreign owner cannot directly soft delete quotation');
update public.quotations set deleted_at = now()
where id = 'a0a00000-0000-4000-8000-0000000000a1';
select pg_temp.assert_true((select version = 6 and deleted_at is not null
  from public.quotations where id = 'a0a00000-0000-4000-8000-0000000000a1'),
  'owner direct soft delete remains usable and advances version');
do $no_resurrection$
begin
  begin
    update public.quotations set deleted_at = null
    where id = 'a0a00000-0000-4000-8000-0000000000a1';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.quotations where id =
      'a0a00000-0000-4000-8000-0000000000a1' and deleted_at is null) then
    raise exception 'direct tombstone resurrection was allowed';
  end if;
end;
$no_resurrection$;
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', 6)$sql$, 'PQT03');
select pg_temp.expect_error($sql$select * from pg_temp.save_case(
  'a0a00000-0000-4000-8000-0000000000a1', null)$sql$, 'PQT03');
reset role;

-- FOR UPDATE plus the guarded q.version predicate makes simultaneous stale
-- updates serialize; the sequential stale call above checks the losing result.
-- A two-session commit/contend exercise is intentionally omitted because it
-- cannot be fully demonstrated while keeping every hosted write rollback-only.
select pg_temp.assert_true(
  position('for update' in lower(pg_get_functiondef(
    'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)'::regprocedure))) > 0
  and position('q.version = p_expected_version' in lower(pg_get_functiondef(
    'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)'::regprocedure))) > 0,
  'source contains locked, guarded optimistic update');

select 'QUOTATION SAVE RPC EXERCISES PASSED; STARTING ROLLBACK' as status;
rollback;

do $post_rollback$
begin
  if to_regprocedure('public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') is not null
     or exists (select 1 from auth.users where id in (
       'a0a00000-0000-4000-8000-00000000000a'::uuid,
       'a0a00000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from public.quotations where id in (
       'a0a00000-0000-4000-8000-0000000000a1'::uuid,
       'a0a00000-0000-4000-8000-0000000000a2'::uuid))
     or exists (select 1 from public.media_objects where id =
       'a0a00000-0000-4000-8000-0000000000a3'::uuid)
     or exists (select 1 from pg_policy where polrelid = 'public.quotations'::regclass
       and polname = 'quotations_direct_soft_delete_only')
     or not has_any_column_privilege('authenticated', 'public.quotations', 'INSERT')
     or not has_table_privilege('authenticated', 'public.quotation_downpayments', 'INSERT') then
    raise exception 'quotation validation left persistent changes after ROLLBACK';
  end if;
end;
$post_rollback$;
select 'QUOTATION SAVE RPC ROLLBACK CONFIRMED' as verdict;
