-- SOURCE ONLY. Removes 20261123100000_subscription_entitlements_quotas.sql. Run
-- only with the owner's approval, as postgres, from an LF copy of this file:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_entitlements_quotas_rollback.sql
--
-- For an incident after cutover, use public.subscription_cutback() instead: it
-- restores the direct writes and keeps every counter and provider record.
--
-- This script refuses to run while enforcement is on, while the Staging facility
-- is installed, or once real history exists: subscriptions, billing events,
-- charged usage or per-item edits cannot be rebuilt after being dropped.
-- Lifetime counters in public.usage_counters are deliberately left as they are.
--
-- If the migration was applied with `supabase db push`, its history entry is
-- corrected afterwards as a separate owner step:
--   supabase migration repair --status reverted 20261123100000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.usage_events') is null
     or to_regprocedure('public.create_core_entity(text,uuid,jsonb,jsonb,uuid[])') is null then
    raise exception 'subscription rollback preflight failed: objects not present';
  end if;
  if (select enforced from public.subscription_rollout) then
    raise exception 'subscription rollback preflight failed: run subscription_cutback first';
  end if;
  if to_regclass('public.tap_billing_orders') is not null then
    raise exception 'subscription rollback preflight failed: roll back 20261123120000 first';
  end if;
  if to_regclass('public.deployment_environment') is not null then
    raise exception 'subscription rollback preflight failed: remove the Staging test facility first';
  end if;
  if exists (select 1 from public.subscription_provider_records)
     or exists (select 1 from public.billing_events)
     or exists (select 1 from public.usage_events)
     or exists (select 1 from public.item_edit_usage)
     or exists (select 1 from public.subscription_rollout_log) then
    raise exception 'subscription rollback preflight failed: real history exists and would be lost';
  end if;
end;
$preflight$;

-- The Quotation save, exactly as it was.
create or replace function public.save_quotation(
  p_quotation_id uuid, p_expected_version bigint, p_header jsonb,
  p_downpayments jsonb, p_government_fees jsonb, p_administrative_fees jsonb
)
returns table (
  quotation_id uuid, resulting_version bigint, outcome text,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql security definer set search_path = ''
as $function$
begin
  if not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  return query select * from public.save_quotation_session_internal(
    p_quotation_id, p_expected_version, p_header, p_downpayments,
    p_government_fees, p_administrative_fees
  );
end;
$function$;

drop function public.subscription_cutback(text);
drop function public.subscription_cutover(text, text);
drop function public.apply_subscription_provider_event(
  text, text, text, timestamptz, uuid, text, text, text, text, boolean,
  timestamptz, timestamptz, timestamptz, text, text);
drop function public.subscription_authorize_media_change(uuid, text, uuid, uuid);
drop function public.get_subscription_state();
drop function public.subscription_state_for(uuid);
drop function public.toolkit_document_quota_commit();
drop function public.toolkit_document_quota_reserve();
drop function public.subscription_quotation_content(uuid);
drop function public.update_core_entity(text, uuid, uuid, jsonb, jsonb, uuid[]);
drop function public.create_core_entity(text, uuid, jsonb, jsonb, uuid[]);
drop function public.subscription_require_caller();
drop function public.subscription_replace_areas(text, uuid, text[]);
drop function public.subscription_stored_areas(text, uuid);
drop function public.subscription_parse_areas(text, jsonb);
drop function public.subscription_pick(jsonb, text[]);
drop function public.subscription_require_columns(text, jsonb);
drop function public.subscription_entity_columns(text);
drop function public.subscription_grant_media(uuid, public.quota_section, uuid, uuid[], interval);
drop function public.subscription_charge_edit(uuid, public.quota_section, uuid, uuid);
drop function public.subscription_charge_create(uuid, public.quota_section, uuid);
drop function public.subscription_plan_label(jsonb);
drop function public.subscription_lock(uuid);
drop function public.subscription_access(uuid);
drop function public.subscription_entitlement(uuid);
drop function public.subscription_enforced();
drop function public.subscription_test_mode_state(uuid);
drop function public.subscription_override_entitlement(uuid);
drop function public.subscription_accepts_sandbox();
drop function public.guard_core_entity_client_write();

drop table public.subscription_rollout_log;
drop table public.subscription_rollout;
drop table public.item_media_grants;
drop table public.usage_events;
drop table public.item_edit_usage;
drop table public.billing_events;
drop table public.subscription_provider_records;

delete from public.plan_limits where plan_code = 'free';

do $postflight$
begin
  if to_regclass('public.usage_events') is not null
     or to_regprocedure('public.create_core_entity(text,uuid,jsonb,jsonb,uuid[])') is not null
     or exists (select 1 from public.plan_limits)
     or not has_table_privilege('authenticated', 'public.request_areas', 'INSERT')
     or not has_column_privilege('authenticated', 'public.requests', 'notes', 'UPDATE') then
    raise exception 'subscription rollback postflight failed';
  end if;
end;
$postflight$;

commit;
