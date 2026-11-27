-- READ-ONLY operations report for the subscription system. Prints counts and
-- provider references only: no names, emails, phone numbers or card data.
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_ops_report.sql
\set ON_ERROR_STOP on
begin transaction read only;

-- Rollout state.
select enforced, baseline, changed_at from public.subscription_rollout;

-- Subscriptions by provider, environment and state.
select provider, environment, state, count(*) as subscriptions
from public.subscription_provider_records
group by 1, 2, 3 order by 1, 2, 3;

-- ALERT: payments that need a person (wrong amount, or an account deleted first).
select id, kind, billing_cycle, amount, tap_charge_id, updated_at
from public.tap_billing_orders where status = 'needs_review' order by updated_at desc limit 50;

-- ALERT: Tap charges open for over an hour (webhook missing?).
select id, kind, tap_charge_id, created_at
from public.tap_billing_orders
where status in ('created', 'pending') and created_at < now() - interval '1 hour'
order by created_at limit 50;

-- ALERT: captured card payments without a tax invoice (tax profile incomplete?).
select o.id, o.kind, o.updated_at
from public.tap_billing_orders as o
where o.status in ('captured', 'refunded')
  and not exists (select 1 from public.billing_documents as d
                  where d.tap_order_id = o.id and d.kind = 'tax_invoice')
order by o.updated_at desc limit 50;

-- ALERT: card changes that need a person.
select id, status, tap_authorize_id, updated_at
from public.tap_card_updates where status = 'needs_review' order by updated_at desc limit 50;

-- ALERT: Play purchases not acknowledged after 48 hours. Google refunds at 3 days.
select p.token_sha256, p.product_id, p.created_at, r.state
from public.play_purchases as p
join public.subscription_provider_records as r
  on r.provider = 'google_play' and r.provider_subscription_id = p.token_sha256
where p.acknowledged_at is null and p.user_id is not null
  and r.state in ('active', 'cancel_scheduled', 'billing_issue')
  and p.created_at < now() - interval '48 hours'
order by p.created_at limit 50;

-- ALERT: Play renewal still on for a deleted account.
select p.token_sha256, p.orphan_cancel_claimed_at, r.state
from public.play_purchases as p
join public.subscription_provider_records as r
  on r.provider = 'google_play' and r.provider_subscription_id = p.token_sha256
where p.user_id is null and p.orphan_canceled_at is null and r.auto_renew
order by p.updated_at limit 50;

-- ALERT: active store subscriptions past their date with no newer event.
select provider, provider_subscription_id, state, paid_through_at, last_event_at, last_reconciled_at
from public.subscription_provider_records
where state in ('active', 'cancel_scheduled') and paid_through_at < now() - interval '6 hours'
order by paid_through_at limit 50;

-- ALERT: events that could not be attached in the last 7 days.
select provider, outcome, count(*) as events
from public.billing_events
where received_at > now() - interval '7 days'
  and outcome in ('ownership_conflict', 'no_account', 'processing')
group by 1, 2 order by 1, 2;

-- Webhook traffic over the last 24 hours.
select provider, outcome, count(*) as events
from public.billing_events
where received_at > now() - interval '24 hours'
group by 1, 2 order by 1, 2;

-- Accounts over the Free limits without Plus (read-only).
select count(distinct u.owner_id) as accounts_over_free_limits
from public.usage_counters as u
join public.plan_limits as l on l.plan_code = 'free' and l.section = u.section
where u.lifetime_created_count > l.limit_value;

rollback;
