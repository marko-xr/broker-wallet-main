-- SOURCE ONLY. Removes 20261123120000_subscription_billing.sql. Run only with the
-- owner's approval, as postgres, from an LF copy of this file, BEFORE the rollback
-- of 20261123100000:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_billing_rollback.sql
--
-- To stop billing in an incident, do not use this: turn off TAP_RENEWALS_ENABLED and
-- TAP_BILLING_ENABLED instead. This script refuses once any Tap order or agreement
-- exists, because payment records must never be dropped.
--
-- If applied with `supabase db push`, correct its history entry afterwards:
--   supabase migration repair --status reverted 20261123120000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres' or to_regclass('public.tap_billing_orders') is null then
    raise exception 'billing rollback preflight failed: objects not present';
  end if;
  if to_regclass('public.play_purchases') is not null then
    raise exception 'billing rollback preflight failed: roll back 20261124100000 first';
  end if;
  if exists (select 1 from public.tap_billing_orders)
     or exists (select 1 from public.tap_billing_agreements) then
    raise exception 'billing rollback preflight failed: payment records exist';
  end if;
end;
$preflight$;

drop function public.tap_record_refund(text, text, text, numeric);
drop function public.tap_set_auto_renew(uuid, boolean);
drop function public.tap_charge_owner(text);
drop function public.tap_claim_stale_charges(integer);
drop function public.tap_claim_due_renewals(integer);
drop function public.tap_settle_charge(uuid, text, text, numeric, text, boolean, text, text, text, jsonb);
drop function public.tap_card_display(jsonb);
drop function public.tap_attach_charge(uuid, text);
drop function public.tap_create_order(uuid, text);
drop function public.tap_subscription_key(uuid);
drop function public.tap_price(text);
drop function public.subscription_claim_reconcile_batch(integer);
drop function public.subscription_sync_claim(uuid, integer);
drop table public.tap_billing_orders;
drop table public.tap_billing_agreements;
drop table public.subscription_sync_state;
alter table public.subscription_provider_records drop column last_reconciled_at;

commit;
