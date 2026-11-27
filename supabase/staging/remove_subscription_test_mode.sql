-- STAGING ONLY. Removes the whole test facility and restores the three constant
-- seams of the production schema. Records, usage and provider records stay.
--   psql -X -v ON_ERROR_STOP=1 -f supabase/staging/remove_subscription_test_mode.sql
begin;

create or replace function public.subscription_accepts_sandbox()
returns boolean language sql stable security invoker set search_path = ''
as $function$
  select false;
$function$;

create or replace function public.subscription_override_entitlement(p_user uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$
  select null::jsonb;
$function$;

create or replace function public.subscription_test_mode_state(p_user uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$
  select '{"available": false, "scenario": null, "expires_at": null}'::jsonb;
$function$;

drop function public.staging_test_control(uuid, text);
drop function public.subscription_is_staging();
drop table public.staging_test_audit;
drop table public.staging_test_entitlements;
drop table public.staging_test_allowlist;
drop table public.deployment_environment;

commit;
