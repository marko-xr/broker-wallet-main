-- Billing state on the production schema: server-side prices, single settlement,
-- renewal claims, cancellation and refunds. Tap itself is not involved here.
-- Calls run as postgres, standing in for the billing function's service role.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(31);

-- A test supplier profile: card sales need one (20261124100000).
update public.billing_tax_profile
  set trn = '100000000000003', address = 'Test address, Dubai, UAE';

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('b1110000-0000-4000-8000-00000000000a', 'bill-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('b1110000-0000-4000-8000-00000000000b', 'bill-b@example.test', '{"name":"B"}'::jsonb, now(), now());

create function pg_temp.a() returns uuid language sql immutable as $$ select 'b1110000-0000-4000-8000-00000000000a'::uuid $$;
create function pg_temp.b() returns uuid language sql immutable as $$ select 'b1110000-0000-4000-8000-00000000000b'::uuid $$;
create function pg_temp.settle(p_order uuid, p_charge text, p_status text, p_amount numeric default 20)
returns text language sql as $$
  select public.tap_settle_charge(p_order, p_charge, p_status, p_amount, 'AED', true,
    'cus_1', 'card_1', 'agr_1');
$$;
create function pg_temp.status(p_user uuid) returns text language sql as $$
  select public.subscription_state_for(p_user) ->> 'status';
$$;

select ok(not exists (
  select 1 from unnest(array['subscription_sync_state', 'tap_billing_agreements', 'tap_billing_orders']) as t(name)
  cross join unnest(array['anon', 'authenticated', 'service_role']) as r(role)
  cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
  where has_table_privilege(r.role, 'public.' || t.name, p.priv)
), 'no API role reads or writes the billing tables directly');
select ok(not exists (
  select 1 from pg_proc as p
  cross join unnest(array['anon', 'authenticated']) as r(role)
  where p.pronamespace = 'public'::regnamespace and p.proname like 'tap_%'
    and has_function_privilege(r.role, p.oid, 'EXECUTE')
), 'no client role can call a Tap function');
select ok(has_function_privilege('service_role',
  'public.tap_settle_charge(uuid,text,text,numeric,text,boolean,text,text,text,jsonb)', 'EXECUTE'),
  'the billing function can settle');
select throws_ok($$insert into public.tap_billing_orders (user_id, kind, billing_cycle, amount)
    values ('b1110000-0000-4000-8000-00000000000a', 'initial', 'monthly', 1)$$,
  '23514', null, 'an order cannot carry another price');

create temporary table o1 as
  select (public.tap_create_order(pg_temp.a(), 'monthly') ->> 'order_id')::uuid as id;
select is((public.tap_create_order(pg_temp.a(), 'monthly') ->> 'order_id')::uuid,
  (select id from o1), 'a repeated checkout reuses the open order');
select is((select amount from public.tap_billing_orders where id = (select id from o1)),
  20.00::numeric, 'monthly is AED 20.00');
select is(public.tap_price('annual'), 180.00::numeric, 'annual is AED 180.00, charged once a year');
select is(public.tap_attach_charge((select id from o1), 'chg_1'), 'attached', 'the charge attaches');
select is(public.tap_attach_charge((select id from o1), 'chg_other'), 'charge_mismatch',
  'and cannot be swapped');
select is(pg_temp.settle((select id from o1), 'chg_other', 'CAPTURED'), 'charge_mismatch',
  'another charge cannot settle this order');
select is(pg_temp.settle((select id from o1), 'chg_1', 'CAPTURED', 1), 'amount_mismatch',
  'a wrong amount does not settle it');
select is(pg_temp.status(pg_temp.a()), 'free', 'and grants nothing');

create temporary table o2 as
  select (public.tap_create_order(pg_temp.b(), 'monthly') ->> 'order_id')::uuid as id;
select is(pg_temp.settle((select id from o2), 'chg_2', 'INITIATED'), 'pending', 'an open charge is pending');
select is(pg_temp.status(pg_temp.b()), 'free', 'and grants nothing');
select is(pg_temp.settle((select id from o2), 'chg_2', 'CAPTURED'), 'captured', 'a capture settles');
select is(pg_temp.status(pg_temp.b()), 'plus_renewing', 'and activates Plus');
select is(pg_temp.settle((select id from o2), 'chg_2', 'CAPTURED'), 'duplicate', 'settling twice is a duplicate');
select is((select count(*)::integer from public.billing_events where event_id = 'charge:chg_2'), 1,
  'and records one event');
select is(public.tap_create_order(pg_temp.b(), 'annual') ->> 'refused', 'already_plus',
  'Plus cannot be bought twice');

select is(public.tap_set_auto_renew(pg_temp.b(), false), 'renewal_off', 'renewal can be turned off');
select is(pg_temp.status(pg_temp.b()), 'plus_cancel_scheduled', 'Plus stays to the paid date');
update public.subscription_provider_records set paid_through_at = now() + interval '1 hour'
  where user_id = pg_temp.b();
select is((select count(*)::integer from public.tap_claim_due_renewals(10)), 0,
  'a canceled subscription is never renewed, even when its period is about to end');
-- A second wall: auto-renew off stops a renewal whatever the record's state says.
update public.subscription_provider_records set state = 'active' where user_id = pg_temp.b();
select is((select count(*)::integer from public.tap_claim_due_renewals(10)), 0,
  'auto-renew off alone also stops a renewal');
update public.subscription_provider_records set state = 'cancel_scheduled' where user_id = pg_temp.b();

select is(public.tap_set_auto_renew(pg_temp.b(), true), 'renewal_on', 'renewal can be turned back on');
select is((select count(*)::integer from public.tap_claim_due_renewals(10)), 1, 'a due period is claimed');
select is((select count(*)::integer from public.tap_claim_due_renewals(10)), 0, 'and not claimed again');

select is(public.tap_record_refund('re_1', 'chg_2', 'REFUNDED', 20), 'refunded', 'a full refund is recorded');

-- The annual plan is one AED 180.00 charge a year, never monthly installments.
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values ('b1110000-0000-4000-8000-00000000000c', 'bill-c@example.test', '{"name":"C"}'::jsonb, now(), now());
create temporary table o3 as
  select (public.tap_create_order('b1110000-0000-4000-8000-00000000000c', 'annual') ->> 'order_id')::uuid as id;
select is((select amount from public.tap_billing_orders where id = (select id from o3)),
  180.00::numeric, 'an annual order is one AED 180.00 charge');
select throws_ok($$insert into public.tap_billing_orders (user_id, kind, billing_cycle, amount)
    values ('b1110000-0000-4000-8000-00000000000c', 'initial', 'annual', 15.00)$$,
  '23514', null, 'an annual order cannot be a monthly installment');
select is(pg_temp.settle((select id from o3), 'chg_3', 'CAPTURED', 180.00), 'captured',
  'the full annual amount settles it');
select is((select paid_through_at from public.subscription_provider_records
           where user_id = 'b1110000-0000-4000-8000-00000000000c'),
  now() + interval '1 year', 'and pays for one whole year');

select * from finish();
rollback;
