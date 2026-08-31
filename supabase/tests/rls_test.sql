-- Runtime RLS and integrity checks for Broker Wallet Stage 1.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(19);

-- Test identities. The auth.users trigger must create matching public.profiles rows.
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111', 'user-a@example.test', '{"name":"User A"}'::jsonb, now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'user-b@example.test', '{"name":"User B"}'::jsonb, now(), now());

select is((select count(*)::integer from public.profiles where id in (
  '11111111-1111-4111-8111-111111111111'::uuid,
  '22222222-2222-4222-8222-222222222222'::uuid
)), 2, 'auth trigger creates profiles');

-- Auth confirmation updates must remain authoritative for profile verification state.
update auth.users
set email_confirmed_at = now(), updated_at = now()
where id = '11111111-1111-4111-8111-111111111111'::uuid;

select is(
  (select is_email_verified from public.profiles
   where id = '11111111-1111-4111-8111-111111111111'::uuid),
  true,
  'email confirmation syncs to profile verification state'
);

-- Create one B-owned request as B.
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}', true);

select lives_ok($$
  insert into public.requests (id, owner_id, request_type, status, min_price, max_price)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'rent', 'active', 1000, 2000)
$$, 'user B can insert own request');

-- Switch JWT identity to A while remaining in authenticated role.
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);

select lives_ok($$
  insert into public.requests (id, owner_id, request_type, status, min_price, max_price)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'sell', 'active', 500000, 700000)
$$, 'user A can insert own request');

select is(
  (select count(*)::integer from public.requests where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'user A cannot read user B request'
);

select throws_like($$
  insert into public.requests (id, owner_id, request_type, status)
  values ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'rent', 'active')
$$, '%row-level security%', 'user A cannot create a request for user B');

select lives_ok($$
  update public.requests set notes='updated by owner' where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
$$, 'user A can update own request');

select is(
  (select version from public.requests where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  2::bigint,
  'owner update increments sync version'
);

select throws_like($$
  delete from public.requests where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
$$, '%permission denied%', 'hard delete of synced owner entity is denied');

select throws_like($$
  insert into public.requests (id, owner_id, request_type, status, min_price, max_price)
  values ('44444444-4444-4444-8444-444444444444', '11111111-1111-4111-8111-111111111111', 'rent', 'active', 5000, 1000)
$$, '%requests_price_range%', 'invalid price range is rejected by database constraint');

select throws_like($$
  insert into public.request_areas (request_id, ordinal, area)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0, 'Dubai Marina')
$$, '%row-level security%', 'user A cannot modify user B request areas');

select throws_like($$
  insert into public.favorite_requests (owner_id, target_id)
  values ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
$$, '%row-level security%', 'user A cannot favorite a user B private target');

select lives_ok($$
  insert into public.favorite_requests (owner_id, target_id)
  values ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
$$, 'user A can favorite own request');

select lives_ok($$
  insert into public.feedback (owner_id, rating, comment, app_version, platform)
  values ('11111111-1111-4111-8111-111111111111', 5, 'Local test feedback', '0.0.0-test', 'test')
$$, 'user A can submit feedback');

select is(
  (select user_name_snapshot from public.feedback where owner_id='11111111-1111-4111-8111-111111111111' limit 1),
  'User A',
  'feedback identity snapshot is server-derived'
);

select throws_like($$
  insert into public.media_objects (owner_id, bucket, object_key)
  values ('11111111-1111-4111-8111-111111111111', 'private', 'x')
$$, '%permission denied%', 'client cannot create media metadata directly');

select throws_like($$
  insert into public.revenuecat_entitlements (user_id, entitlement_id)
  values ('11111111-1111-4111-8111-111111111111', 'pro')
$$, '%permission denied%', 'client cannot grant itself RevenueCat entitlement');

select throws_like($$
  update public.usage_counters set lifetime_created_count=999
  where owner_id='11111111-1111-4111-8111-111111111111'
$$, '%permission denied%', 'client cannot manipulate authoritative usage counters');

reset role;

-- Confirm B row was not altered while A was authenticated.
select is(
  (select notes from public.requests where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '',
  'other-user row remains unchanged'
);

select * from finish();
rollback;
