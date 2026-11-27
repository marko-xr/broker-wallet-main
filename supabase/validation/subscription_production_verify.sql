-- READ-ONLY. Proves a database cannot grant Plus through the test facility and
-- reports its rollout state. Run on production before and after the cutover:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_production_verify.sql
\set ON_ERROR_STOP on
begin transaction read only;

do $verify$
declare
  v_probe uuid := '00000000-0000-4000-8000-000000000000';
begin
  if to_regclass('public.deployment_environment') is not null
     or to_regclass('public.staging_test_allowlist') is not null
     or to_regclass('public.staging_test_entitlements') is not null
     or to_regclass('public.staging_test_audit') is not null
     or to_regprocedure('public.staging_test_control(uuid,text)') is not null
     or to_regprocedure('public.subscription_is_staging()') is not null then
    raise exception 'FAILED: the Staging test facility is installed on this database';
  end if;
  if public.subscription_accepts_sandbox() is distinct from false then
    raise exception 'FAILED: this database accepts sandbox purchases';
  end if;
  if public.subscription_override_entitlement(v_probe) is not null then
    raise exception 'FAILED: the entitlement override seam is not constant';
  end if;
  if (public.subscription_test_mode_state(v_probe) ->> 'available')::boolean is distinct from false then
    raise exception 'FAILED: the test control reports as available';
  end if;
  if exists (select 1 from public.subscription_provider_records where environment = 'sandbox') then
    raise warning 'Sandbox provider records exist here. They grant nothing, but they should not be on production.';
  end if;
  if has_function_privilege('anon', 'public.get_subscription_state()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.subscription_cutover(text,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.subscription_cutover(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.apply_subscription_provider_event(text,text,text,timestamptz,uuid,text,text,text,text,boolean,timestamptz,timestamptz,timestamptz,text,text)',
       'EXECUTE') then
    raise exception 'FAILED: a function is executable by a role that must not call it';
  end if;
  if has_function_privilege('authenticated', 'public.play_account_ref(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.play_apply_snapshot(text,text,uuid,uuid,text,text,text,text,text,text,timestamptz,text,text,boolean,timestamptz,timestamptz,timestamptz,text,boolean,text)',
       'EXECUTE')
     or has_function_privilege('authenticated', 'public.tap_card_update_create(uuid)', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.play_purchases', 'SELECT')
     or has_table_privilege('service_role', 'public.play_purchases', 'SELECT') then
    raise exception 'FAILED: a payment-channel object is reachable by a role that must not reach it';
  end if;
  if exists (select 1 from public.play_purchases where token_ciphertext not like 'v1.%') then
    raise exception 'FAILED: a stored purchase token is not encrypted';
  end if;
  raise notice 'PASSED: no test facility, no sandbox access, no client path to an entitlement';
end;
$verify$;

select enforced, baseline, changed_at from public.subscription_rollout;
select action, baseline, accounts_over_limit, at
from public.subscription_rollout_log order by id desc limit 5;

rollback;
