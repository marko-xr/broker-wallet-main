-- Phone verification security: the profile phone mirror is not client-
-- writable, the trusted sync still maintains it for accounts that sign in by
-- phone, and Supabase Auth's self-service phone change can no longer start
-- (Model X, 20261122130000_phone_identity_model_x.sql — its confirmation is
-- not bound to the account's session). The pending-change guard and its sweep
-- from 20260911181112 stay installed; with no pending change ever accepted
-- they have nothing left to arbitrate.
--
-- Run with `supabase test db` against the local stack. Writes to auth.users
-- run as postgres here, standing in for Supabase Auth's own writes.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('a1111111-1111-4111-8111-111111111111', 'phone-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('b2222222-2222-4222-8222-222222222222', 'phone-b@example.test', '{"name":"B"}'::jsonb, now(), now());

-- An account created by phone, as Supabase Auth stores it (no '+').
insert into auth.users (id, phone, raw_user_meta_data, created_at, updated_at)
values ('d4444444-4444-4444-8444-444444444444', '971501234567', '{}'::jsonb, now(), now());

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

reset role;

-- ---------------------------------------------------------------------------
-- The trusted sync maintains the mirror for an account that signs in by phone.
-- ---------------------------------------------------------------------------

select is(
  (select phone_number from public.profiles where id = 'd4444444-4444-4444-8444-444444444444'),
  '971501234567',
  'the sign-in number of a phone account reaches the profile mirror'
);

update auth.users set phone_confirmed_at = now()
where id = 'd4444444-4444-4444-8444-444444444444';

select is(
  (select is_phone_verified from public.profiles where id = 'd4444444-4444-4444-8444-444444444444'),
  true,
  'phone confirmation syncs into is_phone_verified'
);

-- ---------------------------------------------------------------------------
-- Self-service phone change never starts, for any account.
-- ---------------------------------------------------------------------------

select has_trigger('auth', 'users', 'guard_auth_phone_identity',
  'auth.users carries the Model X phone identity guard');
select has_trigger('auth', 'users', 'guard_pending_phone_change',
  'auth.users still carries the pending phone-change guard');
select ok(not has_function_privilege('authenticated', 'public.clear_stale_phone_changes()', 'EXECUTE'),
  'clients cannot run the stale phone-change sweep');
select ok(not has_function_privilege('authenticated', 'public.guard_pending_phone_change()', 'EXECUTE'),
  'clients cannot run the pending-change guard function');
select ok(not has_function_privilege('authenticated', 'public.guard_auth_phone_identity()', 'EXECUTE'),
  'clients cannot run the phone identity guard function');

select throws_like($$
  update auth.users
  set phone_change = '971509999999', phone_change_token = 'token', phone_change_sent_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, '%phone_change_not_allowed%',
  'an email account cannot start a phone change');

select throws_like($$
  update auth.users
  set phone_change = '971509999999', phone_change_token = 'token', phone_change_sent_at = now()
  where id = 'd4444444-4444-4444-8444-444444444444'
$$, '%phone_change_not_allowed%',
  'a phone account cannot start a self-service phone change either');

select throws_like($$
  update auth.users set phone = '971509999999', phone_confirmed_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, '%phone_identity_not_allowed%',
  'an email account never receives a sign-in number');

select is(
  (select coalesce(phone, '') || '|' || coalesce(phone_change, '') from auth.users
    where id = 'b2222222-2222-4222-8222-222222222222'),
  '|',
  'the refused writes left the email account without any number'
);

-- ---------------------------------------------------------------------------
-- Unrelated Auth writes are never refused.
-- ---------------------------------------------------------------------------

select lives_ok($$
  update auth.users set updated_at = now()
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'an update that does not touch the phone columns is unaffected');

select lives_ok($$
  update auth.users
  set phone = phone,
      phone_change = phone_change,
      phone_change_token = phone_change_token,
      phone_change_sent_at = phone_change_sent_at,
      raw_app_meta_data = raw_app_meta_data,
      updated_at = now()
  where id in ('b2222222-2222-4222-8222-222222222222', 'd4444444-4444-4444-8444-444444444444')
$$, 'a full-row re-save that changes no phone column is never refused');

select lives_ok($$
  update auth.users
  set phone_change = '', phone_change_token = '', phone_change_sent_at = null
  where id = 'a1111111-1111-4111-8111-111111111111'
$$, 'clearing a pending change neither recurses nor fails');

-- ---------------------------------------------------------------------------
-- The documented periodic cleanup still runs and never touches a sign-in number.
-- ---------------------------------------------------------------------------

select is(public.clear_stale_phone_changes(), 0,
  'the sweep finds nothing to clear');
select is(
  (select phone from auth.users where id = 'd4444444-4444-4444-8444-444444444444'),
  '971501234567',
  'the sweep never touches a confirmed phone'
);

select * from finish();
rollback;
