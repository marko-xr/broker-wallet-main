-- READ-ONLY. Counts the production objects and rows a backup must contain:
-- counts only, no row values. Run from a scratch folder linked to the project:
--   supabase db query --linked --output-format json -f baseline.sql
-- `cron` and `net` are left out: their tables belong to extensions, whose data
-- `pg_dump --data-only` never includes (cron jobs are checked with cron_jobs.sql).
select json_build_object(
  'tables', (select json_object_agg(t.table_schema || '.' || t.table_name,
      (xpath('/row/c/text()', query_to_xml(
        format('select count(*) as c from %I.%I', t.table_schema, t.table_name), false, true, '')))[1]::text::bigint)
    from information_schema.tables as t
    where t.table_type = 'BASE TABLE'
      and t.table_schema in ('public', 'auth', 'storage')
      and (t.table_schema || '.' || t.table_name) not in ('auth.schema_migrations', 'storage.migrations')),
  'schema', json_build_object(
    'tables', (select count(*) from pg_tables where schemaname = 'public'),
    'rls', (select count(*) from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relrowsecurity),
    'policies', (select count(*) from pg_policies where schemaname = 'public'),
    'functions', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace),
    'triggers', (select count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
                 where c.relnamespace = 'public'::regnamespace and not tg.tgisinternal),
    'views', (select count(*) from pg_views where schemaname = 'public')),
  'migrations', (select count(*) from supabase_migrations.schema_migrations),
  'volatile', json_build_array('auth.sessions', 'auth.refresh_tokens', 'auth.flow_state',
    'auth.mfa_amr_claims', 'auth.audit_log_entries', 'auth.one_time_tokens',
    'public.app_session_claims', 'public.user_active_sessions', 'public.notification_delivery_jobs'),
  'taken_at', now()
) as baseline;
