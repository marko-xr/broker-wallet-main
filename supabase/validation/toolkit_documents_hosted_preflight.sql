-- Toolkit cloud documents: MINIMAL HOSTED PREFLIGHT (C2B). SOURCE ONLY - NOT EXECUTED ANYWHERE HOSTED.
--
-- A bounded, rollback-only check of the EXACT migration against the shared hosted database, safe to run
-- there because it needs no fixtures: it creates no user, no session, no profile and no document, calls no
-- session-claim function, calls the functions that can write only with identifiers that match no row (they
-- answer not_found / false and change nothing), makes no network call, and performs no nontransactional
-- operation (no sequence, notify, extension, vacuum). The complete 195-assertion suite
-- (supabase/validation/toolkit_documents_validation.sql and supabase/tests/toolkit_documents_test.sql)
-- needs fixtures and stays local / isolated.
--
-- What it proves on the hosted engine, inside one transaction that always rolls back:
--   0  preconditions: role, no Toolkit object, the 18 applied migrations, required existing objects
--   1  the migration changes NOTHING that exists (digest snapshot before == after, default privileges,
--      roles, extensions, event triggers, every existing table / function / policy / trigger included)
--   2  the objects it creates: 2 tables, 16 functions (signature, owner, security mode, fixed search
--      path, source digest that also proves the text arrived as LF, exact ACL), 22 constraints, 6 indexes,
--      3 triggers, 2 policies, RLS enabled and not forced, table and column privileges
--   3  as anon / authenticated / service_role: what each can and cannot do, without touching any row
--      (random identifiers only; read-only calls on the empty new tables)
-- Run as one request (the \set line becomes a comment and the \ir line becomes the migration's LF text; see
-- docs/toolbox/cloud-documents-rollout.md), then compare the hosted baseline snapshot again.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '2s';
set local statement_timeout = '20s';
set local idle_in_transaction_session_timeout = '30s';

-- 0. Preconditions (read only) ---------------------------------------------------------------------
do $preflight$
begin
  if current_user <> 'postgres' then
    raise exception 'Toolkit hosted preflight: must run as postgres';
  end if;
  if exists (select 1 from pg_class where relname ~* 'toolkit')
     or exists (select 1 from pg_proc where proname ~* 'toolkit')
     or exists (select 1 from pg_type where typname ~* 'toolkit')
     or exists (select 1 from pg_policy where polname ~* 'toolkit') then
    raise exception 'Toolkit hosted preflight: a Toolkit object already exists';
  end if;
  if (select count(*) from supabase_migrations.schema_migrations) <> 18
     or (select max(version) from supabase_migrations.schema_migrations) <> '20261012233000' then
    raise exception 'Toolkit hosted preflight: unexpected migration history';
  end if;
  if to_regprocedure('public.is_current_app_session()') is null
     or to_regprocedure('public.bump_sync_version()') is null
     or not exists (select 1 from pg_class c where c.oid = 'public.profiles'::regclass and c.relrowsecurity) then
    raise exception 'Toolkit hosted preflight: required existing objects are missing';
  end if;
end;
$preflight$;

-- The schema fingerprint compared before and after the migration (names containing "toolkit" excluded).
create function pg_temp.snapshot() returns table(item text, value text, digest text)
language sql as $snapshot$
  with
   t as (select c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, c.relacl, pg_get_userbyid(c.relowner) as owner
         from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r','p','v','m','S','i') and c.relname !~* 'toolkit'),
   f as (select p.oid, p.proname, p.proacl, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as owner
         from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname !~* 'toolkit')
  select 'migration_history', count(*)::text, md5(string_agg(version || ':' || name || ':' || coalesce(cardinality(statements), 0), ',' order by version))
    from supabase_migrations.schema_migrations
  union all select 'public_relations', count(*)::text, md5(string_agg(relname || ':' || relkind::text || ':' || relrowsecurity || ':' || relforcerowsecurity || ':' || owner || ':' || coalesce(relacl::text, ''), ',' order by relname)) from t
  union all select 'public_columns', count(*)::text, md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by table_name, ordinal_position))
    from information_schema.columns where table_schema = 'public' and table_name !~* 'toolkit'
  union all select 'column_privileges', count(*)::text, md5(coalesce(string_agg(c.relname || '.' || a.attname || ':' || a.attacl::text, ',' order by c.relname, a.attnum), ''))
    from pg_attribute a join pg_class c on c.oid = a.attrelid where c.relnamespace = 'public'::regnamespace and a.attacl is not null and c.relname !~* 'toolkit'
  union all select 'public_functions', count(*)::text, md5(string_agg(proname || ':' || md5(pg_get_functiondef(oid)) || ':' || coalesce(proacl::text, '') || ':' || prosecdef || ':' || coalesce(proconfig::text, '') || ':' || owner, ',' order by oid::regprocedure::text)) from f
  union all select 'public_triggers', count(*)::text, md5(string_agg(tgrelid::regclass::text || '.' || tgname || ':' || tgenabled::text || ':' || tgfoid::regproc::text, ',' order by tgrelid::regclass::text, tgname))
    from pg_trigger where not tgisinternal and (select relnamespace from pg_class where oid = tgrelid) = 'public'::regnamespace and tgname !~* 'toolkit'
  union all select 'public_indexes', count(*)::text, md5(string_agg(indexname || ':' || indexdef, ',' order by indexname)) from pg_indexes where schemaname = 'public' and tablename !~* 'toolkit'
  union all select 'public_constraints', count(*)::text, md5(string_agg(conrelid::regclass::text || '.' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname))
    from pg_constraint where connamespace = 'public'::regnamespace and conrelid::regclass::text !~* 'toolkit'
  union all select 'public_policies', count(*)::text, md5(string_agg(tablename || '.' || policyname || ':' || permissive || ':' || roles::text || ':' || cmd || ':' || coalesce(qual, '') || ':' || coalesce(with_check, ''), ',' order by tablename, policyname))
    from pg_policies where schemaname = 'public' and tablename !~* 'toolkit'
  union all select 'default_acls', count(*)::text, md5(string_agg(pg_get_userbyid(defaclrole) || ':' || defaclnamespace::regnamespace::text || ':' || defaclobjtype::text || ':' || defaclacl::text, ',' order by defaclrole, defaclnamespace, defaclobjtype)) from pg_default_acl
  union all select 'roles', count(*)::text, md5(string_agg(rolname || ':' || rolsuper || ':' || rolbypassrls || ':' || rolcanlogin, ',' order by rolname)) from pg_roles where rolname in ('postgres','anon','authenticated','service_role','authenticator','supabase_admin','supabase_auth_admin')
  union all select 'event_triggers', count(*)::text, md5(string_agg(evtname || ':' || evtenabled::text || ':' || evtfoid::regproc::text, ',' order by evtname)) from pg_event_trigger
  union all select 'extensions', count(*)::text, md5(string_agg(extname || ':' || extversion, ',' order by extname)) from pg_extension
  union all select 'realtime_publication', count(*)::text, md5(coalesce(string_agg(schemaname || '.' || tablename, ',' order by schemaname, tablename), '')) from pg_publication_tables where pubname = 'supabase_realtime'
  union all select 'schemas', count(*)::text, md5(string_agg(nspname, ',' order by nspname)) from pg_namespace where nspname !~ '^pg_(temp|toast)'
  union all select 'row_counts', (select count(*) from auth.users)::text || '/' || (select count(*) from public.profiles) || '/' || (select count(*) from public.media_objects)
      || '/' || (select count(*) from public.user_active_sessions) || '/' || (select count(*) from public.account_deletion_jobs), ''
$snapshot$;
create temp table toolkit_snapshot_before as select * from pg_temp.snapshot();

-- The exact migration under review ----------------------------------------------------------------
\ir ../migrations/20261019100000_toolkit_cloud_documents.sql

-- 1. Nothing that exists was changed --------------------------------------------------------------
create temp table toolkit_snapshot_after as select * from pg_temp.snapshot();
do $unchanged$
declare
  v_diff text;
begin
  select string_agg(b.item, ', ') into v_diff
  from toolkit_snapshot_before b full join toolkit_snapshot_after a using (item)
  where b.value is distinct from a.value or b.digest is distinct from a.digest;
  if v_diff is not null then
    raise exception 'Toolkit hosted preflight: the migration changed existing objects: %', v_diff;
  end if;
  if (select count(*) from toolkit_snapshot_before) <> 16 then
    raise exception 'Toolkit hosted preflight: snapshot incomplete';
  end if;
end;
$unchanged$;

-- 2. The objects it creates ------------------------------------------------------------------------
create function pg_temp.assert_that(good boolean, label text) returns void language plpgsql as $assert$
begin
  if good is distinct from true then
    raise exception 'Toolkit hosted preflight failed: %', label;
  end if;
end;
$assert$;

do $objects$
declare
  v_expected_functions constant text[] := array['authorize_toolkit_document_upload(uuid,uuid,text,text,text,bigint,integer,text,timestamp with time zone,text,bigint,bigint,bigint,integer,integer,integer,integer,boolean)', 'begin_toolkit_document_delete(uuid,uuid,text,text)', 'claim_abandoned_toolkit_document(uuid,uuid,text,timestamp with time zone,integer)', 'confirm_toolkit_document_upload(uuid,uuid,text,bigint,text,text,boolean)', 'discard_abandoned_toolkit_document(uuid,uuid,text,timestamp with time zone)', 'finalize_toolkit_document_delete(uuid,uuid,text,integer)', 'get_toolkit_document(uuid,uuid)', 'guard_toolkit_document()', 'list_toolkit_document_cleanup(text,text,timestamp with time zone,integer)', 'list_toolkit_documents(uuid,text,integer,timestamp with time zone,uuid,text)', 'purge_toolkit_document_tombstone(uuid,uuid,timestamp with time zone)', 'rename_toolkit_document(uuid,uuid,text,bigint)', 'toolkit_document_object_key(uuid,uuid,text)', 'toolkit_document_rules(text)', 'toolkit_document_statuses(uuid,text,uuid[])', 'toolkit_document_usage(uuid)']::text[];
begin
  -- Functions: exactly these, owned by postgres, fixed empty search path, exact ACL, exact source.
  perform pg_temp.assert_that((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ 'toolkit') = v_expected_functions,
    'the set of Toolkit functions');
  perform pg_temp.assert_that((select count(*) from (values
    ('authorize_toolkit_document_upload(uuid,uuid,text,text,text,bigint,integer,text,timestamp with time zone,text,bigint,bigint,bigint,integer,integer,integer,integer,boolean)', true, '8e6467a4b3eb142be8d3640fd4f3ef4b', '{postgres=X/postgres,service_role=X/postgres}'),
    ('begin_toolkit_document_delete(uuid,uuid,text,text)', true, '41cefb73723648ae55483a32a4dde943', '{postgres=X/postgres,service_role=X/postgres}'),
    ('claim_abandoned_toolkit_document(uuid,uuid,text,timestamp with time zone,integer)', true, '8ae7be28bc927914bc06e06bb9b9bb63', '{postgres=X/postgres,service_role=X/postgres}'),
    ('confirm_toolkit_document_upload(uuid,uuid,text,bigint,text,text,boolean)', true, '067bbe353c011cf286f84e9ddc11408e', '{postgres=X/postgres,service_role=X/postgres}'),
    ('discard_abandoned_toolkit_document(uuid,uuid,text,timestamp with time zone)', true, '64c500ca46021a8765eeeeac8b2f092e', '{postgres=X/postgres,service_role=X/postgres}'),
    ('finalize_toolkit_document_delete(uuid,uuid,text,integer)', true, 'f5e45cc49639124b5dec25ab83821547', '{postgres=X/postgres,service_role=X/postgres}'),
    ('get_toolkit_document(uuid,uuid)', true, '55f562ef25631ea60c1c63a4b2a4a271', '{postgres=X/postgres,service_role=X/postgres}'),
    ('guard_toolkit_document()', false, '522f99bbe1a351c0913d89cc62fb44b1', '{postgres=X/postgres,service_role=X/postgres}'),
    ('list_toolkit_document_cleanup(text,text,timestamp with time zone,integer)', true, 'a2f0642c501f460e764a32ab5bcd4ce6', '{postgres=X/postgres,service_role=X/postgres}'),
    ('list_toolkit_documents(uuid,text,integer,timestamp with time zone,uuid,text)', true, '38ca159b847010a3259e9cfbc490f1b9', '{postgres=X/postgres,service_role=X/postgres}'),
    ('purge_toolkit_document_tombstone(uuid,uuid,timestamp with time zone)', true, '16782644bfb248a3106a37d14c9b081c', '{postgres=X/postgres,service_role=X/postgres}'),
    ('rename_toolkit_document(uuid,uuid,text,bigint)', true, 'c80107f6c930428dc2250b2af4827c5a', '{postgres=X/postgres,service_role=X/postgres}'),
    ('toolkit_document_object_key(uuid,uuid,text)', false, '60dd70e1bb4430f849aa743404f38228', '{postgres=X/postgres,service_role=X/postgres}'),
    ('toolkit_document_rules(text)', false, '1ed368627d0438beac8f0f76a5c94ee6', '{postgres=X/postgres,service_role=X/postgres}'),
    ('toolkit_document_statuses(uuid,text,uuid[])', true, '5ac1798338e80358f34fb6fe971e5a0b', '{postgres=X/postgres,service_role=X/postgres}'),
    ('toolkit_document_usage(uuid)', true, 'd36791be82b1aaf286613f8f89cc8d75', '{postgres=X/postgres,service_role=X/postgres}')
    ) as e(sig, definer, src, acl)
    join pg_proc p on p.oid = e.sig::regprocedure
    where pg_get_userbyid(p.proowner) = 'postgres'
      and p.prosecdef = e.definer
      and md5(p.prosrc) = e.src
      and p.proacl::text = e.acl
      and p.proconfig = array['search_path=""']) = 16,
    'owner, security mode, source digest, ACL and search_path of each Toolkit function');
  perform pg_temp.assert_that(not exists (
      select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as a
      where p.pronamespace = 'public'::regnamespace and p.proname ~ 'toolkit'
        and (a.grantee = 0 or a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid))),
    'no Toolkit function is executable by PUBLIC, anon or authenticated');
  perform pg_temp.assert_that((select count(*) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname ~ 'toolkit'
        and has_function_privilege('service_role', p.oid, 'execute')) = 16,
    'service_role can execute the Toolkit functions');

  -- Tables: owner, RLS on and not forced, no table privilege for any client or service role.
  perform pg_temp.assert_that((select count(*) from pg_class c
      where c.oid in ('public.toolkit_documents'::regclass, 'public.toolkit_document_account_state'::regclass)
        and pg_get_userbyid(c.relowner) = 'postgres' and c.relrowsecurity and not c.relforcerowsecurity
        and c.relacl::text = '{postgres=arwdDxtm/postgres}') = 2,
    'tables: owner, row level security, table ACL');
  perform pg_temp.assert_that((select d from (select md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attnum)) as d
      from pg_attribute a where a.attrelid = 'public.toolkit_documents'::regclass and a.attnum > 0 and not a.attisdropped) x) = '5715ea5e3e2e88dd535ebe4ffbdc2669',
    'toolkit_documents columns');
  perform pg_temp.assert_that((select d from (select md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attnum)) as d
      from pg_attribute a where a.attrelid = 'public.toolkit_document_account_state'::regclass and a.attnum > 0 and not a.attisdropped) x) = '0ac13d3129f1296bc301bf4c88f5c467',
    'toolkit_document_account_state columns');
  perform pg_temp.assert_that(not exists (select 1 from unnest(array['public.toolkit_documents', 'public.toolkit_document_account_state']) as t(rel),
      unnest(array['anon', 'authenticated', 'service_role']) as r(role)
      where has_table_privilege(r.role, t.rel, 'select,insert,update,delete,truncate,references,trigger')),
    'no table privilege for anon, authenticated or service_role');
  perform pg_temp.assert_that((select array_agg(a.attname::text order by a.attnum) from pg_attribute a
      where a.attrelid = 'public.toolkit_documents'::regclass and a.attnum > 0 and not a.attisdropped
        and has_column_privilege('authenticated', 'public.toolkit_documents', a.attname, 'select')) = array['id', 'owner_id', 'document_type', 'title', 'content_type', 'size_bytes', 'page_count', 'content_sha256', 'sha256_verified', 'status', 'source_created_at', 'confirmed_at', 'created_at', 'updated_at', 'version']::text[],
    'the columns authenticated can read (no bucket, key, etag, attempts, last-authorized or deleted time)');
  perform pg_temp.assert_that(not exists (select 1 from pg_attribute a
      where a.attrelid = 'public.toolkit_documents'::regclass and a.attnum > 0 and not a.attisdropped
        and (has_column_privilege('authenticated', 'public.toolkit_documents', a.attname, 'insert,update')
             or has_column_privilege('anon', 'public.toolkit_documents', a.attname, 'select,insert,update')
             or has_column_privilege('service_role', 'public.toolkit_documents', a.attname, 'select,insert,update'))),
    'no write column privilege for authenticated; no column privilege at all for anon or service_role');

  -- Constraints, indexes, triggers, policies.
  perform pg_temp.assert_that((select array_agg(conname::text order by conname) from pg_constraint
      where conrelid in ('public.toolkit_documents'::regclass, 'public.toolkit_document_account_state'::regclass)) = array['toolkit_document_account_state_owner_id_fkey', 'toolkit_document_account_state_pkey', 'toolkit_documents_attempts_nonnegative', 'toolkit_documents_bucket_key_unique', 'toolkit_documents_bucket_nonempty', 'toolkit_documents_content_type_known', 'toolkit_documents_deleting_has_time', 'toolkit_documents_discard_has_claim', 'toolkit_documents_image_single_page', 'toolkit_documents_object_key_exact', 'toolkit_documents_owner_id_fkey', 'toolkit_documents_pages_range', 'toolkit_documents_pending_unconfirmed', 'toolkit_documents_pkey', 'toolkit_documents_ready_confirmed', 'toolkit_documents_sha256_format', 'toolkit_documents_size_range', 'toolkit_documents_status_known', 'toolkit_documents_title_clean', 'toolkit_documents_tool_content_type', 'toolkit_documents_type_known', 'toolkit_documents_verified_when_ready', 'toolkit_documents_version_positive']::text[],
    'constraints (22)');
  perform pg_temp.assert_that((select array_agg(indexname::text order by indexname) from pg_indexes
      where schemaname = 'public' and tablename ~ 'toolkit') = array['toolkit_document_account_state_pkey', 'toolkit_documents_bucket_key_unique', 'toolkit_documents_deleting_idx', 'toolkit_documents_owner_idx', 'toolkit_documents_pending_upload_idx', 'toolkit_documents_pkey']::text[],
    'indexes (6)');
  perform pg_temp.assert_that((select array_agg(tgname::text order by tgname) from pg_trigger
      where tgrelid = 'public.toolkit_documents'::regclass and not tgisinternal) = array['toolkit_documents_bump_sync_version', 'toolkit_documents_guard_insert', 'toolkit_documents_guard_update']::text[],
    'triggers (3)');
  perform pg_temp.assert_that((select array_agg(policyname::text || ':' || permissive || ':' || roles::text || ':' || cmd order by policyname)
      from pg_policies where schemaname = 'public' and tablename ~ 'toolkit') = array['app_session_gate:RESTRICTIVE:{authenticated}:ALL', 'toolkit_documents_select_own:PERMISSIVE:{authenticated}:SELECT']::text[],
    'policies: own ready rows (permissive select) and the restrictive session gate; none on the state table');
  perform pg_temp.assert_that(pg_get_expr((select polqual from pg_policy where polname = 'app_session_gate' and polrelid = 'public.toolkit_documents'::regclass), 'public.toolkit_documents'::regclass)
      like '%is_current_app_session%'
    and pg_get_expr((select polqual from pg_policy where polname = 'toolkit_documents_select_own' and polrelid = 'public.toolkit_documents'::regclass), 'public.toolkit_documents'::regclass)
      like '%auth.uid%ready%', 'policy expressions');
end;
$objects$;

-- 3. What each role can do, without touching a row (random identifiers; the new tables are empty) ----
do $anon$
declare
  r record;
begin
  execute 'set local role anon';
  begin
    perform count(*) from public.toolkit_documents;
    raise exception 'Toolkit hosted preflight failed: anon read the table';
  exception when insufficient_privilege then null;
  end;
  for r in select p.proname, p.pronargs from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname ~ 'toolkit' and p.prorettype <> 'trigger'::regtype loop
    begin
      execute format('select * from public.%I(%s)', r.proname, (select string_agg('null', ', ') from generate_series(1, r.pronargs)));
      raise exception 'Toolkit hosted preflight failed: anon executed %', r.proname;
    exception when insufficient_privilege then null;
    end;
  end loop;
  execute 'reset role';
end;
$anon$;

do $authenticated$
declare
  r record;
  v_rows bigint;
begin
  -- A random identity that exists nowhere: the session gate and the own-rows policy read nothing.
  perform set_config('request.jwt.claims',
    '{"sub":"c2b00000-0000-4000-8000-0000000000a1","role":"authenticated","session_id":"c2b00000-0000-4000-8000-0000000000a2"}', true);
  execute 'set local role authenticated';
  select count(*) into v_rows from public.toolkit_documents;
  if v_rows <> 0 then
    raise exception 'Toolkit hosted preflight failed: authenticated read % rows', v_rows;
  end if;
  begin perform object_key from public.toolkit_documents;
    raise exception 'Toolkit hosted preflight failed: authenticated read the object key';
  exception when insufficient_privilege then null; end;
  begin perform bucket from public.toolkit_documents;
    raise exception 'Toolkit hosted preflight failed: authenticated read the bucket';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.toolkit_document_account_state;
    raise exception 'Toolkit hosted preflight failed: authenticated read the tombstone floor';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
      values ('c2b00000-0000-4000-8000-0000000000b1', 'c2b00000-0000-4000-8000-0000000000a1', 'scanner', 'application/pdf',
              repeat('a', 64), 'T', 1, 'preflight.invalid', 'x');
    raise exception 'Toolkit hosted preflight failed: authenticated inserted a row';
  exception when insufficient_privilege then null; end;
  begin update public.toolkit_documents set title = 'x';
    raise exception 'Toolkit hosted preflight failed: authenticated updated a row';
  exception when insufficient_privilege then null; end;
  begin delete from public.toolkit_documents;
    raise exception 'Toolkit hosted preflight failed: authenticated deleted a row';
  exception when insufficient_privilege then null; end;
  for r in select p.proname, p.pronargs from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname ~ 'toolkit' and p.prorettype <> 'trigger'::regtype loop
    begin
      execute format('select * from public.%I(%s)', r.proname, (select string_agg('null', ', ') from generate_series(1, r.pronargs)));
      raise exception 'Toolkit hosted preflight failed: authenticated executed %', r.proname;
    exception when insufficient_privilege then null;
    end;
  end loop;
  execute 'reset role';
end;
$authenticated$;

do $service$
declare
  v_user constant uuid := 'c2b00000-0000-4000-8000-0000000000c1';
  v_doc constant uuid := 'c2b00000-0000-4000-8000-0000000000c2';
begin
  execute 'set local role service_role';
  -- The service role reaches the data only through the functions, never the tables.
  begin perform 1 from public.toolkit_documents;
    raise exception 'Toolkit hosted preflight failed: service_role read the table directly';
  exception when insufficient_privilege then null; end;
  -- Pure helpers.
  perform pg_temp.assert_that(public.toolkit_document_object_key(v_user, v_doc, 'application/pdf')
      = 'profiles/' || v_user::text || '/toolkit-documents/' || v_doc::text || '.pdf', 'pdf key');
  perform pg_temp.assert_that(public.toolkit_document_object_key(v_user, v_doc, 'image/jpeg') like '%.jpg'
    and public.toolkit_document_object_key(v_user, v_doc, 'image/png') like '%.png'
    and public.toolkit_document_object_key(v_user, v_doc, 'image/gif') is null, 'image keys');
  -- Read-only calls for an identity that owns nothing: empty answers, no row created or changed.
  perform pg_temp.assert_that((select count(*) from public.list_toolkit_documents(v_user, 'preflight.invalid', 10, null, null, null)) = 0, 'list');
  perform pg_temp.assert_that((select count(*) from public.get_toolkit_document(v_user, v_doc)) = 0, 'get');
  perform pg_temp.assert_that((select count(*) from public.toolkit_document_statuses(v_user, 'preflight.invalid', array[v_doc])) = 0, 'statuses');
  perform pg_temp.assert_that((select ready_count + pending_count from public.toolkit_document_usage(v_user)) = 0, 'usage');
  perform pg_temp.assert_that((select count(*) from public.list_toolkit_document_cleanup('abandoned_pending', 'preflight.invalid', now(), 10)) = 0
    and (select count(*) from public.list_toolkit_document_cleanup('stuck_discard', 'preflight.invalid', now(), 10)) = 0
    and (select count(*) from public.list_toolkit_document_cleanup('pending_delete', 'preflight.invalid', now(), 10)) = 0
    and (select count(*) from public.list_toolkit_document_cleanup('old_tombstones', 'preflight.invalid', now(), 10)) = 0, 'cleanup listings');
  perform pg_temp.assert_that((select outcome from public.claim_abandoned_toolkit_document(v_user, v_doc, 'preflight.invalid', now(), 900)) = 'not_found', 'claim of nothing');
  perform pg_temp.assert_that((select outcome from public.discard_abandoned_toolkit_document(v_user, v_doc, 'preflight.invalid', now())) = 'not_found', 'discard of nothing');
  perform pg_temp.assert_that((select outcome from public.begin_toolkit_document_delete(v_user, v_doc, 'preflight.invalid', null)) = 'not_found', 'delete of nothing');
  perform pg_temp.assert_that((select outcome from public.finalize_toolkit_document_delete(v_user, v_doc, 'preflight.invalid', 0)) = 'not_found', 'finalize of nothing');
  perform pg_temp.assert_that((select outcome from public.rename_toolkit_document(v_user, v_doc, 'T', 1)) = 'not_found', 'rename of nothing');
  perform pg_temp.assert_that((select outcome from public.confirm_toolkit_document_upload(v_user, v_doc, 'preflight.invalid', 1, 'application/pdf', null, false)) = 'not_found', 'confirm of nothing');
  perform pg_temp.assert_that(public.purge_toolkit_document_tombstone(v_user, v_doc, now()) = false, 'purge of nothing');
  -- Invalid input is refused before any lock or row (authorize is never given a real identity here).
  begin
    perform public.authorize_toolkit_document_upload(null, v_doc, 'scanner', 'application/pdf', 'T', 1, 1, repeat('a', 64), now(),
      'preflight.invalid', 1000, 1000, 100000, 10, 2, 10, 5, false);
    raise exception 'Toolkit hosted preflight failed: authorize accepted a null account';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'Invalid Toolkit document%' then raise; end if;
  end;
  execute 'reset role';
  perform pg_temp.assert_that((select count(*) from public.toolkit_documents) = 0
    and (select count(*) from public.toolkit_document_account_state) = 0, 'the new tables are still empty');
end;
$service$;

select 'TOOLKIT_DOCUMENTS_HOSTED_PREFLIGHT_SOURCE_PASS' as result;
rollback;

do $postflight$
begin
  if exists (select 1 from pg_class where relname ~* 'toolkit')
     or exists (select 1 from pg_proc where proname ~* 'toolkit')
     or exists (select 1 from pg_policy where polname ~* 'toolkit')
     or (select count(*) from supabase_migrations.schema_migrations) <> 18 then
    raise exception 'Toolkit hosted preflight: the rollback left hosted residue';
  end if;
end;
$postflight$;
select 'TOOLKIT_DOCUMENTS_HOSTED_PREFLIGHT_RESTORED' as result;
