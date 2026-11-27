-- Google Play ownership and the Tap additions on the production schema. Calls run
-- as postgres, standing in for the billing function's service role.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(37);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('c2220000-0000-4000-8000-00000000000a', 'play-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('c2220000-0000-4000-8000-00000000000b', 'play-b@example.test', '{"name":"B"}'::jsonb, now(), now());

create function pg_temp.a() returns uuid language sql immutable as $$ select 'c2220000-0000-4000-8000-00000000000a'::uuid $$;
create function pg_temp.b() returns uuid language sql immutable as $$ select 'c2220000-0000-4000-8000-00000000000b'::uuid $$;
create function pg_temp.h(p text) returns text language sql immutable as $$ select repeat(p, 64) $$;
create function pg_temp.apply(
  p_hash text, p_caller uuid, p_ref uuid, p_event text,
  p_linked text default null, p_env text default 'production', p_ack boolean default true,
  p_state text default 'active'
) returns jsonb language sql as $$
  select public.play_apply_snapshot(
    p_hash, 'v1.sealed', p_caller, p_ref, 'plus', 'monthly', 'GPA.1', p_linked, p_event, 'TEST',
    now(), 'monthly', p_state, true, now(), now() + interval '30 days', null, p_env, p_ack);
$$;
create function pg_temp.status(p_user uuid) returns text language sql as $$
  select public.subscription_state_for(p_user) ->> 'status';
$$;

select ok(not exists (
  select 1 from unnest(array['play_account_refs', 'play_purchases', 'tap_card_updates']) as t(name)
  cross join unnest(array['anon', 'authenticated', 'service_role']) as r(role)
  cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
  where has_table_privilege(r.role, 'public.' || t.name, p.priv)
), 'no API role reads or writes the channel tables directly');
select ok(not exists (
  select 1 from pg_proc as p
  cross join unnest(array['anon', 'authenticated']) as r(role)
  where p.pronamespace = 'public'::regnamespace
    and (p.proname like 'play_%' or p.proname like 'tap_card_%')
    and has_function_privilege(r.role, p.oid, 'EXECUTE')
), 'no client role can call a Play or card-change function');
select ok(has_function_privilege('authenticated', 'public.get_billing_overview()', 'EXECUTE'),
  'a signed-in client may read its own billing view');
select ok(not has_function_privilege('anon', 'public.get_billing_overview()', 'EXECUTE'),
  'an anonymous caller may not');

create temporary table refs as
  select public.play_account_ref(pg_temp.a()) as a, public.play_account_ref(pg_temp.b()) as b;
select is(public.play_account_ref(pg_temp.a()), (select a from refs), 'the reference is stable');
select isnt((select a from refs), pg_temp.a(), 'and is not the account id');

select is(pg_temp.apply(pg_temp.h('1'), pg_temp.a(), (select a from refs), 'e1') ->> 'outcome',
  'processed', 'a purchase binds to the account of its reference');
select is(pg_temp.status(pg_temp.a()), 'plus_renewing', 'and activates Plus');
select is((pg_temp.apply(pg_temp.h('2'), pg_temp.a(), (select a from refs), 'e2') ->> 'acknowledge')::boolean,
  true, 'an accepted purchase may be acknowledged');

select is(pg_temp.apply(pg_temp.h('1'), pg_temp.b(), (select b from refs), 'e3') ->> 'outcome',
  'ownership_conflict', 'another account cannot take it');
select is(pg_temp.status(pg_temp.b()), 'free', 'and stays Free');
select is((select user_id from public.play_purchases where token_sha256 = pg_temp.h('1')),
  pg_temp.a(), 'ownership did not move');

select is(pg_temp.apply(pg_temp.h('3'), pg_temp.b(), (select a from refs), 'e4') ->> 'outcome',
  'ownership_conflict', 'another account''s reference cannot be redeemed');
select is((pg_temp.apply(pg_temp.h('3'), pg_temp.b(), (select a from refs), 'e5') ->> 'acknowledge')::boolean,
  false, 'and a refused purchase is never acknowledged');
select is(pg_temp.apply(pg_temp.h('4'), pg_temp.b(), null, 'e6') ->> 'outcome',
  'unlinked', 'a purchase with no reference links to no caller');
select is((select count(*)::integer from public.play_purchases where token_sha256 = pg_temp.h('4')),
  0, 'and is not stored');

select is((pg_temp.apply(pg_temp.h('5'), pg_temp.b(), (select b from refs), 'e7', null, 'sandbox') ->> 'acknowledge')::boolean,
  false, 'a test purchase is not acknowledged on production');
select is(pg_temp.status(pg_temp.b()), 'free', 'and grants nothing');

select is(pg_temp.apply(pg_temp.h('6'), pg_temp.a(), (select a from refs), 'e8', pg_temp.h('1')) ->> 'outcome',
  'processed', 'a replacement by the same account is accepted');
select is((select state from public.subscription_provider_records where provider_subscription_id = pg_temp.h('1')),
  'revoked', 'and the replaced token stops granting');
select is(pg_temp.apply(pg_temp.h('7'), pg_temp.b(), (select b from refs), 'e9', pg_temp.h('6')) ->> 'outcome',
  'ownership_conflict', 'a purchase linked to another account''s token is refused');

-- Payment choices are the owner's server-side decision.
select ok(not (select android_card_choice from public.billing_channel_policy),
  'the Android card choice starts off');
select throws_ok($$update public.billing_channel_policy set android_card_choice = true$$,
  '23514', null, 'and cannot be turned on without a recorded basis');
select ok(not has_table_privilege('authenticated', 'public.billing_channel_policy', 'UPDATE'),
  'no client can change it');

-- VAT documents.
select is(public.billing_vat_fils(2000, 500), 95, 'VAT inside AED 20.00 is AED 0.95');
select is(public.billing_vat_fils((public.tap_price('annual') * 100)::integer, 500), 857,
  'VAT inside the server annual price is AED 8.57');
select is(public.billing_vat_fils(18000, 500), 857, 'VAT inside AED 180.00 is AED 8.57');
update public.billing_tax_profile set trn = null, address = null;
select throws_ok($$select public.tap_create_order('c2220000-0000-4000-8000-00000000000b', 'monthly')$$,
  'PBP02', 'tax_profile_incomplete', 'no card sale starts without a complete tax profile');
update public.billing_tax_profile set trn = '100000000000003', address = 'Test address, Dubai, UAE';
create temporary table vat_order as
  select (public.tap_create_order(pg_temp.b(), 'monthly') ->> 'order_id')::uuid as id;
select is(public.tap_settle_charge((select id from vat_order), 'chg_vat', 'CAPTURED', 20, 'AED', true,
  'cus_v', 'card_v', 'agr_v'), 'captured', 'a captured card payment settles');
select is((select string_agg(concat_ws(',', kind, total_fils, vat_fils, net_fils), ';')
    from public.billing_documents where tap_order_id = (select id from vat_order)),
  'tax_invoice,2000,95,1905', 'and gets one tax invoice with its VAT');
select ok((select document_number from public.billing_documents where tap_order_id = (select id from vat_order))
  ~ '^BW-INV-[0-9]{4}-000001$', 'numbered from one');
select is(public.tap_settle_charge((select id from vat_order), 'chg_vat', 'CAPTURED', 20, 'AED', true,
  'cus_v', 'card_v', 'agr_v'), 'duplicate', 'a replayed capture');
select is(public.tap_record_refund('re_vat', 'chg_vat', 'REFUNDED', 20), 'refunded', 'then a full refund');
select is((select count(*)::integer from public.billing_documents where tap_order_id = (select id from vat_order)),
  2, 'issues exactly one credit note and no second invoice');

delete from auth.users where id = pg_temp.a();
select is(pg_temp.apply(pg_temp.h('6'), null, null, 'e10') ->> 'outcome',
  'no_account', 'a late event for a deleted account recreates nothing');
select is((select count(*)::integer from public.profiles where id = pg_temp.a()), 0, 'no profile returned');
select is(pg_temp.apply(pg_temp.h('6'), pg_temp.b(), (select b from refs), 'e11') ->> 'outcome',
  'no_account', 'and its purchase cannot be claimed by another account');

select * from finish();
rollback;
