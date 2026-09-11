-- Phone verification security: the profile phone mirror is not client-
-- writable, the trusted sync still maintains it, and a pending Supabase Auth
-- phone change can never be held by two accounts at once.
--
-- Run with `supabase test db` against the local stack. Writes to auth.users
-- run as postgres here, standing in for Supabase Auth's own writes.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('a1111111-1111-4111-8111-111111111111', 'phone-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('b2222222-2222-4222-8222-222222222222', 'phone-b@example.test', '{"name":"B"}'::jsonb, now(), now()),
  ('c3333333-3333-4333-8333-333333333333', 'phone-c@example.test', '{"name":"C"}'::jsonb, now(), now()),
  ('d4444444-4444-4444-8444-444444444444', 'phone-d@example.test', '{"name":"D"}'::jsonb, now(), now());

-- ---------------------------------------------------------------------------
-- Grants: the phone mirror is read-only to clients.
-- ---------------------------------------------------------------------------

select ok(not has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'UPDATE'),
  'authenticated cannot update profiles.phone_number');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'phone_e164', 'UPDATE'),
  'authenticated cannot update profiles.phone_e164');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'is_phone_verified', 'UPDATE'),
  'authenticated still cannot update profiles.is_phone_verified');
select ok(has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE'),
  'authenticated can still update its profile name');
select ok(has_column_privilege('authenticated', 'public.profiles', 'preferences', 'UPDATE'),
  'authenticated can still update its preferences');
select ok(has_column_privilege('authenticated', 'public.profiles', 'phone_number', 'SELECT'),
  'authenticated can still read its profile phone');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated"}', true);

select throws_ok($$
  update public.profiles set phone_number = '+971500000000'
  where id = 'a1111111-1111-4111-8111-111111111111'
$$, '42501', null, 'a client cannot write its own profile phone_number');

select throws_ok($$
  update public.profiles set phone_e164 = '+971500000000'
  where id = 'a1111111-1111-4111-8111-111111111111'
$$, '42501', null, 'a client cannot write its own profile phone_e164');

select lives_ok($$
  update public.profiles set name = 'A renamed'
  where id = 'a1111111-1111-4111-8111-111111111111'
$$, 'a client can still update its own name');

reset role;

-- ---------------------------------------------------------------------------
-- The trusted sync still maintains the mirror from Supabase Auth.
-- ---------------------------------------------------------------------------

update auth.users
set phone = '971501234567', phone_confirmed_at = now(), updated_at = now()
where id = 'a1111111-1111-4111-8111-111111111111';

select is(
  (select phone_number from public.profiles where id = 'a1111111-1111-4111-8111-111111111111'),
  '971501234567',
  'confirmed auth phone syncs into the profile mirror'
);
select is(
  (select is_phone_verified from public.profiles where id = 'a1111111-1111-4111-8111-111111111111'),
  true,
  'phone confirmation syncs into is_phone_verified'
);

-- ---------------------------------------------------------------------------
-- Pending phone-change guard.
-- now() is fixed for the whole transaction, so every request below that must
-- reach the guard changes the number or the token, as a real Supabase Auth
-- (re)send does. An unchanged re-save deliberately bypasses the guard.
-- ---------------------------------------------------------------------------

select has_trigger('auth', 'users', 'guard_pending_phone_change',
  'auth.users carries the pending phone-change guard');
select ok(not has_function_privilege('authenticated', 'public.clear_stale_phone_changes()', 'EXECUTE'),
  'clients cannot run the stale phone-change sweep');
select ok(not has_function_privilege('authenticated', 'public.guard_pending_phone_change()', 'EXECUTE'),
  'clients cannot run the guard function');

select lives_ok($$
  update auth.users
  set phone_change = '971509999999', phone_change_sent_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'an account can start a phone change');

select throws_like($$
  update auth.users
  set phone_change = '971509999999', phone_change_sent_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, '%phone_change_unavailable%',
  'a second account cannot hold the same live pending number');

select lives_ok($$
  update auth.users
  set phone_change = '971509999999', phone_change_token = 'b-resent-token', phone_change_sent_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'the same account can request its code again');

-- B abandons the attempt: it outlives the grace period.
update auth.users
set phone_change_sent_at = now() - interval '1 hour'
where id = 'b2222222-2222-4222-8222-222222222222';

select lives_ok($$
  update auth.users
  set phone_change = '971509999999', phone_change_sent_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, 'a stale attempt no longer blocks another account');

select is(
  (select phone_change from auth.users where id = 'b2222222-2222-4222-8222-222222222222'),
  '',
  'the abandoned attempt was cleared, leaving one pending account'
);

select throws_like($$
  update auth.users
  set phone_change = '971501234567', phone_change_sent_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, '%phone_change_unavailable%',
  'a number confirmed on another account cannot become pending');

-- ---------------------------------------------------------------------------
-- The documented periodic cleanup.
-- ---------------------------------------------------------------------------

update auth.users
set phone_change = '971507777777', phone_change_sent_at = now() - interval '2 hours'
where id = 'd4444444-4444-4444-8444-444444444444';

select ok(public.clear_stale_phone_changes() >= 1,
  'the sweep clears stale pending changes');
select is(
  (select phone_change from auth.users where id = 'd4444444-4444-4444-8444-444444444444'),
  '',
  'the stale pending change is gone'
);
select is(
  (select phone_change from auth.users where id = 'c3333333-3333-4333-8333-333333333333'),
  '971509999999',
  'a live pending change survives the sweep'
);
select is(
  (select phone from auth.users where id = 'a1111111-1111-4111-8111-111111111111'),
  '971501234567',
  'the sweep never touches a confirmed phone'
);

-- ---------------------------------------------------------------------------
-- Unrelated Auth writes are never refused.
-- ---------------------------------------------------------------------------

-- C still holds pending 971509999999. An administrative write makes that
-- number D's confirmed phone (the guard does not watch `phone`), so a guard
-- evaluated for C would now refuse.
update auth.users
set phone = '971509999999', phone_confirmed_at = now()
where id = 'd4444444-4444-4444-8444-444444444444';

select lives_ok($$
  update auth.users set updated_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, 'an update that does not touch phone_change is unaffected');

select lives_ok($$
  update auth.users
  set phone_change = phone_change,
      phone_change_token = phone_change_token,
      phone_change_sent_at = phone_change_sent_at,
      raw_app_meta_data = raw_app_meta_data,
      updated_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, 'a full-row re-save with an unchanged pending change is never refused');

select throws_like($$
  update auth.users
  set phone_change = phone_change, phone_change_token = 'c-resent-token', phone_change_sent_at = now()
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, '%phone_change_unavailable%',
  'resending a code for a number now confirmed elsewhere is refused');

select lives_ok($$
  update auth.users
  set phone_change = '', phone_change_token = '', phone_change_sent_at = null
  where id = 'c3333333-3333-4333-8333-333333333333'
$$, 'clearing a pending change neither recurses nor fails');

-- ---------------------------------------------------------------------------
-- A normal Supabase Auth phone change still completes end to end.
-- ---------------------------------------------------------------------------

select lives_ok($$
  update auth.users
  set phone_change = '971506666666',
      phone_change_token = 'hashed-token',
      phone_change_sent_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'a fresh phone change can be requested');

select lives_ok($$
  update auth.users
  set phone = phone_change,
      phone_change = '',
      phone_change_token = '',
      phone_confirmed_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'confirming the change (as Supabase Auth does) succeeds');

select is(
  (select phone_number from public.profiles where id = 'b2222222-2222-4222-8222-222222222222'),
  '971506666666',
  'the confirmed number reaches the profile mirror'
);
select is(
  (select is_phone_verified from public.profiles where id = 'b2222222-2222-4222-8222-222222222222'),
  true,
  'the profile reports the phone as verified'
);

select * from finish();
rollback;
