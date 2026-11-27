-- SOURCE ONLY. Removes 20261124100000_subscription_payment_channels.sql. Run only with
-- the owner's approval, as postgres, from an LF copy of this file, BEFORE the rollback
-- of 20261123120000:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_payment_channels_rollback.sql
--
-- To stop billing in an incident, do not use this: turn the provider flags off. This
-- script refuses once any Google Play purchase or Tap card change exists, because
-- payment records must never be dropped.
--
-- If applied with `supabase db push`, correct its history entry afterwards:
--   supabase migration repair --status reverted 20261124100000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres' or to_regclass('public.play_purchases') is null then
    raise exception 'payment channels rollback preflight failed: objects not present';
  end if;
  if exists (select 1 from public.play_purchases)
     or exists (select 1 from public.tap_card_updates)
     or exists (select 1 from public.billing_documents) then
    raise exception 'payment channels rollback preflight failed: payment records exist';
  end if;
end;
$preflight$;

drop trigger tap_orders_issue_documents on public.tap_billing_orders;
drop trigger tap_orders_require_tax_profile on public.tap_billing_orders;
drop function public.get_billing_channels();
drop function public.get_billing_overview();
drop function public.billing_issue_documents();
drop function public.billing_require_tax_profile();
drop function public.billing_next_number(text);
drop function public.billing_vat_fils(integer, integer);
drop function public.billing_tax_ready();
drop table public.billing_documents;
drop table public.billing_document_counters;
drop table public.billing_tax_profile;
drop table public.billing_channel_policy;
drop function public.tap_card_update_settle(uuid, text, text, text, text, text, jsonb);
drop function public.tap_card_update_owner(text);
drop function public.tap_card_update_attach(uuid, text);
drop function public.tap_card_update_create(uuid);
drop function public.play_mark_orphan_canceled(text);
drop function public.play_claim_orphans(integer);
drop function public.play_purchase_ciphertexts(text[]);
drop function public.play_user_purchases(uuid);
drop function public.play_mark_acknowledged(text);
drop function public.play_apply_snapshot(text, text, uuid, uuid, text, text, text, text, text, text, timestamptz, text, text, boolean, timestamptz, timestamptz, timestamptz, text, boolean, text);
drop function public.play_account_ref(uuid);
drop table public.tap_card_updates;
drop table public.play_purchases;
drop table public.play_account_refs;

commit;
