-- STAGING ONLY, owner step, after subscription_test_mode.sql:
--   psql -X -v ON_ERROR_STOP=1 -v staging_ref=<20-character staging project ref> \
--     -v test_user=<the test account's auth.users id> \
--     -f supabase/staging/activate_test_account.sql
-- The marker table refuses the production ref. Exactly one account is added.
\set ON_ERROR_STOP on
begin;

select set_config('bw.staging_ref', :'staging_ref', true),
       set_config('bw.test_user', :'test_user', true);

do $mark$
declare
  v_ref text := current_setting('bw.staging_ref');
  v_user uuid := current_setting('bw.test_user')::uuid;
begin
  if current_user <> 'postgres' then
    raise exception 'Run as postgres';
  end if;
  if exists (select 1 from public.subscription_provider_records where environment = 'production') then
    raise exception 'This database holds production subscriptions: it is not a Staging project';
  end if;
  if not exists (select 1 from public.profiles where id = v_user) then
    raise exception 'The test account does not exist on this project';
  end if;

  insert into public.deployment_environment (environment, project_ref)
    values ('staging', v_ref)
    on conflict (singleton) do update set project_ref = excluded.project_ref;
  insert into public.staging_test_allowlist (user_id, note)
    values (v_user, 'subscription test mode')
    on conflict (user_id) do nothing;
end;
$mark$;

commit;
