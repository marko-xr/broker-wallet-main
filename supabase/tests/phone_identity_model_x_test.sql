-- Model X (20261122130000_phone_identity_model_x.sql): one sign-in identifier
-- per account, contact numbers for email accounts, Worker-mediated changes of
-- a phone account's sign-in number.
--
-- Run with `supabase test db` against the local stack. Writes to auth.users
-- run as postgres here, standing in for Supabase Auth's own writes and for the
-- Auth Admin API. The service_role functions are what the Worker calls.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(97);

-- Accounts
--   A, B, C, N: created by email (N: no email and no phone = anonymous)
--   P, Q:       created by phone (Supabase Auth stores numbers without '+')
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('a1111111-1111-4111-8111-111111111111', 'mx-a@example.test', '{}'::jsonb, now(), now()),
  ('b2222222-2222-4222-8222-222222222222', 'mx-b@example.test', '{}'::jsonb, now(), now()),
  ('c3333333-3333-4333-8333-333333333333', 'mx-c@example.test', '{}'::jsonb, now(), now());
insert into auth.users (id, raw_user_meta_data, created_at, updated_at, is_anonymous)
values ('f6666666-6666-4666-8666-666666666666', '{}'::jsonb, now(), now(), true);
insert into auth.users (id, phone, phone_confirmed_at, raw_user_meta_data, created_at, updated_at)
values
  ('d4444444-4444-4444-8444-444444444444', '971501111111', now(), '{}'::jsonb, now(), now()),
  ('e5555555-5555-4555-8555-555555555555', '971502222222', now(), '{}'::jsonb, now(), now());

-- Sessions; A's session is its current app session (Single Active Device).
insert into auth.sessions (id, user_id) values
  ('0a000000-0000-4000-8000-00000000000a', 'a1111111-1111-4111-8111-111111111111'),
  ('0b000000-0000-4000-8000-00000000000b', 'a1111111-1111-4111-8111-111111111111');
insert into public.user_active_sessions (user_id, active_session_id)
values ('a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a');

-- ---------------------------------------------------------------------------
-- Structure and grants
-- ---------------------------------------------------------------------------

select has_table('public', 'account_sign_in_methods', 'sign-in method table exists');
select has_table('public', 'phone_verifications', 'verification records table exists');
select has_table('public', 'phone_identity_change_grants', 'identity change grants table exists');
select has_trigger('auth', 'users', 'on_auth_user_sign_in_method', 'sign-in method is recorded on account creation');
select has_trigger('auth', 'users', 'guard_auth_phone_identity', 'auth.users carries the phone identity guard');

select ok(not exists (
  select 1 from (values
    ('public.phone_verification_start(uuid,uuid,text,text,integer)'),
    ('public.phone_verification_attach(uuid,uuid,text)'),
    ('public.phone_verification_fail(uuid,uuid)'),
    ('public.phone_verification_attempt(uuid,uuid,uuid)'),
    ('public.contact_phone_confirm(uuid,uuid,uuid)'),
    ('public.phone_identity_change_grant(uuid,uuid,uuid)'),
    ('public.phone_identity_current_proven(uuid,uuid,uuid)'),
    ('public.phone_number_is_held(text,uuid)'),
    ('public.guard_auth_phone_identity()'),
    ('public.record_account_sign_in_method()')) f(sig)
  cross join (values ('anon'), ('authenticated')) r(role)
  where has_function_privilege(r.role, f.sig, 'EXECUTE')),
  'clients cannot execute any Model X function');
select ok((select bool_and(has_function_privilege('service_role', f.sig, 'EXECUTE')) from (values
    ('public.phone_verification_start(uuid,uuid,text,text,integer)'),
    ('public.phone_verification_attach(uuid,uuid,text)'),
    ('public.phone_verification_fail(uuid,uuid)'),
    ('public.phone_verification_attempt(uuid,uuid,uuid)'),
    ('public.contact_phone_confirm(uuid,uuid,uuid)'),
    ('public.phone_identity_change_grant(uuid,uuid,uuid)'),
    ('public.phone_identity_current_proven(uuid,uuid,uuid)')) f(sig)),
  'the service role (Worker) can execute the verification functions');
select ok(not exists (
  select 1 from (values ('public.phone_verifications'), ('public.phone_identity_change_grants')) t(tbl)
  cross join (values ('anon'), ('authenticated'), ('service_role')) r(role)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) p(priv)
  where has_table_privilege(r.role, t.tbl, p.priv)),
  'no role reads or writes verification records or grants directly');
select ok(not exists (
  select 1 from (values ('INSERT'), ('UPDATE'), ('DELETE')) p(priv)
  cross join (values ('anon'), ('authenticated'), ('service_role')) r(role)
  where has_table_privilege(r.role, 'public.account_sign_in_methods', p.priv)),
  'no role can change a sign-in method');
select ok(has_table_privilege('authenticated', 'public.account_sign_in_methods', 'SELECT'),
  'a signed-in client may read its sign-in method');

-- ---------------------------------------------------------------------------
-- Sign-in method recorded at creation
-- ---------------------------------------------------------------------------

select is((select primary_method from public.account_sign_in_methods
  where user_id = 'a1111111-1111-4111-8111-111111111111'), 'email', 'email account is email-primary');
select is((select primary_method from public.account_sign_in_methods
  where user_id = 'd4444444-4444-4444-8444-444444444444'), 'phone', 'phone account is phone-primary');
select is((select primary_method from public.account_sign_in_methods
  where user_id = 'f6666666-6666-4666-8666-666666666666'), 'email',
  'an account with neither is treated as email-primary (never phone)');

-- A phone account that later adds an email stays phone-primary.
update auth.users set email = 'mx-p@example.test', email_confirmed_at = now()
where id = 'd4444444-4444-4444-8444-444444444444';
select is((select primary_method from public.account_sign_in_methods
  where user_id = 'd4444444-4444-4444-8444-444444444444'), 'phone',
  'adding an email does not change the sign-in method');

-- Clients: own row only, and only from the current app session.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"0a000000-0000-4000-8000-00000000000a"}', true);
select is((select count(*)::int from public.account_sign_in_methods), 1,
  'the current session reads exactly its own sign-in method');
select throws_ok($$ update public.account_sign_in_methods set primary_method = 'phone' $$,
  '42501', null, 'a client cannot change its sign-in method');
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"0b000000-0000-4000-8000-00000000000b"}', true);
select is((select count(*)::int from public.account_sign_in_methods), 0,
  'a superseded session reads nothing (Single Active Device gate)');
reset role;

-- ---------------------------------------------------------------------------
-- auth.users guard
-- ---------------------------------------------------------------------------

select throws_like($$
  insert into auth.users (id, email, phone, created_at, updated_at)
  values ('99999999-0000-4000-8000-000000000001', 'both@example.test', '971507000001', now(), now())
$$, '%phone_identity_not_allowed%', 'an account cannot be created with both an email and a sign-in number');
select throws_like($$
  insert into auth.users (id, email, phone_change, created_at, updated_at)
  values ('99999999-0000-4000-8000-000000000002', 'pend@example.test', '971507000002', now(), now())
$$, '%phone_change_not_allowed%', 'an account cannot be created with a pending phone change');
select throws_like($$
  update auth.users set phone = '971507000003' where id = 'a1111111-1111-4111-8111-111111111111'
$$, '%phone_identity_not_allowed%', 'an email account never receives a sign-in number');
select throws_like($$
  update auth.users set phone_change = '971507000004', phone_change_token = 't', phone_change_sent_at = now()
  where id = 'a1111111-1111-4111-8111-111111111111'
$$, '%phone_change_not_allowed%', 'an email account cannot start a self-service phone change');
select throws_like($$
  update auth.users set phone_change = '971507000005', phone_change_token = 't', phone_change_sent_at = now()
  where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_allowed%', 'a phone account cannot start a self-service phone change');

-- A pending change left from before Model X (seeded with the guard off) can
-- be cleared but never re-sent.
alter table auth.users disable trigger guard_auth_phone_identity;
update auth.users set phone_change = '971507000006', phone_change_token = 'old', phone_change_sent_at = now()
where id = 'b2222222-2222-4222-8222-222222222222';
alter table auth.users enable trigger guard_auth_phone_identity;
select throws_like($$
  update auth.users set phone_change_token = 'new', phone_change_sent_at = now() + interval '1 second'
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, '%phone_change_not_allowed%', 'a legacy pending change cannot be re-sent');
select lives_ok($$
  update auth.users set phone_change = '', phone_change_token = '', phone_change_sent_at = null
  where id = 'b2222222-2222-4222-8222-222222222222'
$$, 'a legacy pending change can be cleared');

select throws_like($$
  update auth.users set phone = '971507000007' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_authorized%', 'a phone account number change without a grant is refused');
select throws_like($$
  update auth.users set phone = null where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_identity_required%', 'a phone account cannot lose its sign-in number');
select lives_ok($$
  update auth.users set phone = phone, phone_change = phone_change, updated_at = now()
  where id in ('a1111111-1111-4111-8111-111111111111', 'e5555555-5555-4555-8555-555555555555')
$$, 'a full-row re-save that changes no number passes');

-- ---------------------------------------------------------------------------
-- Contact number of an email account (the Worker flow)
-- ---------------------------------------------------------------------------

create temporary table mx (k text primary key, id uuid) on commit drop;
grant all on mx to service_role;

set local role service_role;
insert into mx values ('a1', public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'contact', '+971503333333'));
reset role;
select ok((select id from mx where k = 'a1') is not null, 'the service role starts a contact verification');

select throws_like($$ select public.phone_verification_start(
  'd4444444-4444-4444-8444-444444444444', '0c000000-0000-4000-8000-00000000000c', 'contact', '+971503333334') $$,
  '%not_available_for_account%', 'a phone account has no contact-number flow');
select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'identity_change', '+971503333334') $$,
  '%not_available_for_account%', 'an email account has no sign-in-number change');
select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'contact', '+447700900123') $$,
  '%invalid_request%', 'only UAE mobile numbers are accepted');
select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'contact', '+971503333334', 5) $$,
  '%invalid_request%', 'an out-of-range lifetime is refused');
select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', null, 'contact', '+971503333334') $$,
  '%invalid_request%', 'a verification must be bound to a session');
select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'contact', '971501111111') $$,
  '%phone_unavailable%', 'a number that signs in to another account cannot become a contact number');

select ok(public.phone_verification_attach((select id from mx where k = 'a1'),
  'a1111111-1111-4111-8111-111111111111', 'provider-ref-a1'), 'the provider reference is stored once');
select ok(not public.phone_verification_attach((select id from mx where k = 'a1'),
  'a1111111-1111-4111-8111-111111111111', 'provider-ref-other'), 'the provider reference cannot be replaced');
select ok(not public.phone_verification_attach((select id from mx where k = 'a1'),
  'b2222222-2222-4222-8222-222222222222', 'provider-ref-b'), 'another account cannot attach to the record');

select throws_like($$ select * from public.phone_verification_attempt(
  (select id from mx where k = 'a1'), 'a1111111-1111-4111-8111-111111111111', '0b000000-0000-4000-8000-00000000000b') $$,
  '%session_mismatch%', 'a different session of the same account cannot use the record');
select throws_like($$ select * from public.phone_verification_attempt(
  (select id from mx where k = 'a1'), 'b2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-00000000000a') $$,
  '%verification_not_found%', 'another account cannot use the record');
select is((select result || '|' || provider_ref || '|' || phone_e164 from public.phone_verification_attempt(
  (select id from mx where k = 'a1'), 'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a')),
  'ok|provider-ref-a1|+971503333333', 'an attempt returns the number and provider reference for the Worker');
select is((select attempts from public.phone_verifications where id = (select id from mx where k = 'a1')), 1,
  'the attempt was counted before the provider is asked');

select throws_like($$ select public.contact_phone_confirm(
  (select id from mx where k = 'a1'), 'a1111111-1111-4111-8111-111111111111', '0b000000-0000-4000-8000-00000000000b') $$,
  '%session_mismatch%', 'confirmation is bound to the session that started it');
set local role service_role;
select is(public.contact_phone_confirm((select id from mx where k = 'a1'),
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a'),
  'verified', 'the service role confirms the contact number');
reset role;
select is((select phone_e164 || '|' || phone_number || '|' || is_phone_verified::text from public.profiles
  where id = 'a1111111-1111-4111-8111-111111111111'),
  '+971503333333|+971503333333|true', 'the profile shows the verified contact number');
select is((select coalesce(phone, '') from auth.users where id = 'a1111111-1111-4111-8111-111111111111'), '',
  'the contact number is never a sign-in number');
select is(public.contact_phone_confirm((select id from mx where k = 'a1'),
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a'),
  'verified', 'a repeated confirmation is idempotent');
select is((select result from public.phone_verification_attempt(
  (select id from mx where k = 'a1'), 'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a')),
  'already_verified', 'a retried request after a lost response needs no new code');

-- Auth writes for the email account never overwrite its contact number.
update auth.users set email_confirmed_at = now(), updated_at = now()
where id = 'a1111111-1111-4111-8111-111111111111';
select is((select phone_e164 from public.profiles where id = 'a1111111-1111-4111-8111-111111111111'),
  '+971503333333', 'the identity sync leaves an email account''s contact number alone');

select throws_like($$ select public.phone_verification_start(
  'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a', 'contact', '+971503333333') $$,
  '%phone_already_verified%', 'the same number is not verified twice');
select throws_like($$ select public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971503333333') $$,
  '%phone_unavailable%', 'a contact number of one account cannot be claimed by another');
select throws_like($$
  insert into auth.users (id, phone, created_at, updated_at)
  values ('99999999-0000-4000-8000-000000000003', '971503333333', now(), now())
$$, '%phone_unavailable%', 'a contact number cannot create a phone account');

update public.phone_auth_policy set mode = 'open';
select is(public.before_user_created_phone_policy('{"user":{"phone":"971503333333"}}'::jsonb)
  -> 'error' ->> 'message', 'phone_signup_not_allowed', 'the sign-up hook refuses a contact number even when open');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971501111111"}}'::jsonb)
  -> 'error' ->> 'message', 'phone_signup_not_allowed', 'the sign-up hook refuses a number that already signs in');
select is(public.before_user_created_phone_policy('{"user":{"phone":"971509000000"}}'::jsonb), '{}'::jsonb,
  'the sign-up hook still allows a free UAE number when open');
update public.phone_auth_policy set mode = 'closed';

-- Supersede, attempt cap, expiry, closing (B starts five in total below).
insert into mx values ('b1', public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971504444444'));
insert into mx values ('b2', public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971504444445'));
select is((select status from public.phone_verifications where id = (select id from mx where k = 'b1')), 'superseded',
  'a new verification supersedes the pending one');
select is(public.contact_phone_confirm((select id from mx where k = 'b1'),
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d'),
  'verification_expired', 'a superseded verification cannot be confirmed');
select ok(not public.phone_verification_fail((select id from mx where k = 'b1'), 'b2222222-2222-4222-8222-222222222222'),
  'a closed record is not closed twice');
select throws_like($$ select * from public.phone_verification_attempt(
  (select id from mx where k = 'b2'), 'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d') $$,
  '%verification_not_found%', 'no attempt before the provider reference is stored');
select ok(public.phone_verification_attach((select id from mx where k = 'b2'),
  'b2222222-2222-4222-8222-222222222222', 'provider-ref-b2'), 'reference stored');
-- The lateral call refers to g so it runs once per row, not once in total.
select is((select string_agg(a.result, ',' order by g) from generate_series(1, 5) g
  cross join lateral public.phone_verification_attempt((select id from mx where k = 'b2' and g > 0),
    'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d') a),
  'ok,ok,ok,ok,ok', 'five attempts are allowed');
select is((select attempts from public.phone_verifications where id = (select id from mx where k = 'b2')), 5,
  'all five attempts were counted');
select is((select result from public.phone_verification_attempt(
  (select id from mx where k = 'b2'), 'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d')),
  'too_many_attempts', 'the sixth attempt is refused');
select is((select status from public.phone_verifications where id = (select id from mx where k = 'b2')), 'failed',
  'the attempt cap closes the record');
select is(public.contact_phone_confirm((select id from mx where k = 'b2'),
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d'),
  'verification_expired', 'a closed record cannot be confirmed');

insert into mx values ('b3', public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971504444446'));
select ok(public.phone_verification_attach((select id from mx where k = 'b3'),
  'b2222222-2222-4222-8222-222222222222', 'provider-ref-b3'), 'reference stored');
update public.phone_verifications set expires_at = now() - interval '1 second' where id = (select id from mx where k = 'b3');
select is((select result from public.phone_verification_attempt(
  (select id from mx where k = 'b3'), 'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d')),
  'verification_expired', 'an expired record accepts no code');
select is((select status from public.phone_verifications where id = (select id from mx where k = 'b3')), 'failed',
  'expiry closes the record');

-- Server-side ceiling: C starts five in the hour, the sixth is refused.
insert into mx select 'c' || g, public.phone_verification_start(
  'c3333333-3333-4333-8333-333333333333', '0e000000-0000-4000-8000-00000000000e', 'contact', '+97150555555' || g)
  from generate_series(1, 5) g;
select throws_like($$ select public.phone_verification_start(
  'c3333333-3333-4333-8333-333333333333', '0e000000-0000-4000-8000-00000000000e', 'contact', '+971505555559') $$,
  '%too_many_requests%', 'an account cannot start more than five verifications an hour');
select ok(public.phone_verification_fail((select id from mx where k = 'c5'), 'c3333333-3333-4333-8333-333333333333'),
  'the Worker can close a pending record (provider failure)');

-- Two accounts verify the same free number: the first confirmation wins.
insert into mx values ('race-b', public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971506000000'));
insert into mx values ('race-n', public.phone_verification_start(
  'f6666666-6666-4666-8666-666666666666', '0f000000-0000-4000-8000-00000000000f', 'contact', '+971506000000'));
select is(public.contact_phone_confirm((select id from mx where k = 'race-n'),
  'f6666666-6666-4666-8666-666666666666', '0f000000-0000-4000-8000-00000000000f'),
  'verified', 'the first confirmation takes the number');
select is(public.contact_phone_confirm((select id from mx where k = 'race-b'),
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d'),
  'phone_unavailable', 'the second account cannot take the same number');
select is((select status from public.phone_verifications where id = (select id from mx where k = 'race-b')), 'failed',
  'the losing record is closed');

-- ---------------------------------------------------------------------------
-- Changing a phone account's sign-in number (Worker + Auth Admin API)
-- ---------------------------------------------------------------------------

insert into mx values ('q1', public.phone_verification_start(
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001', 'identity_change', '+971507777777'));
select throws_like($$ select public.phone_identity_change_grant(
  (select id from mx where k = 'q1'), 'e5555555-5555-4555-8555-555555555555', '02000000-0000-4000-8000-000000000002') $$,
  '%session_mismatch%', 'another session cannot turn the verification into a grant');
select throws_like($$ select public.contact_phone_confirm(
  (select id from mx where k = 'q1'), 'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001') $$,
  '%verification_not_found%', 'a sign-in-number verification cannot become a contact number');
select throws_like($$ select public.phone_identity_change_grant(
  (select id from mx where k = 'q1'), 'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001') $$,
  '%current_number_not_proven%', 'no grant before the current sign-in number is proven');
select ok(not public.phone_identity_current_proven((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', '02000000-0000-4000-8000-000000000002'),
  'another session cannot record the current-number proof');
insert into mx values ('n2', public.phone_verification_start(
  'f6666666-6666-4666-8666-666666666666', '0f000000-0000-4000-8000-00000000000f', 'contact', '+971506100000'));
select ok(not public.phone_identity_current_proven((select id from mx where k = 'n2'),
  'f6666666-6666-4666-8666-666666666666', '0f000000-0000-4000-8000-00000000000f'),
  'a pending contact verification takes no current-number proof');
set local role service_role;
select ok(public.phone_identity_current_proven((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'),
  'the service role records the current-number proof');
reset role;
select ok(public.phone_verification_attach((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', 'provider-ref-q1'), 'reference stored');
select is((select result || '|' || current_proven::text from public.phone_verification_attempt((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001')),
  'ok|true', 'a retried attempt knows the current number is already proven');
set local role service_role;
select is(public.phone_identity_change_grant((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'),
  'granted', 'the service role issues a single-use grant');
reset role;
select throws_like($$
  update auth.users set phone = '971507777778' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_authorized%', 'the grant covers only its own target number');
select lives_ok($$
  update auth.users set phone = '971507777777', phone_confirmed_at = now()
  where id = 'e5555555-5555-4555-8555-555555555555'
$$, 'the Admin API write for the granted number succeeds');
select is((select phone_number from public.profiles where id = 'e5555555-5555-4555-8555-555555555555'),
  '971507777777', 'the new sign-in number reaches the profile mirror');
select ok((select consumed_at is not null from public.phone_identity_change_grants
  where user_id = 'e5555555-5555-4555-8555-555555555555'), 'the grant was consumed');
select throws_like($$
  update auth.users set phone = '971502222222' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_authorized%', 'the grant does not cover a return to the old number');
-- Move the number away with the guard off, then try the granted number again.
alter table auth.users disable trigger guard_auth_phone_identity;
update auth.users set phone = '971502222223' where id = 'e5555555-5555-4555-8555-555555555555';
alter table auth.users enable trigger guard_auth_phone_identity;
select throws_like($$
  update auth.users set phone = '971507777777' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_authorized%', 'a consumed grant cannot be replayed for its own number');
select throws_like($$ select public.phone_identity_change_grant(
  (select id from mx where k = 'a1'), 'a1111111-1111-4111-8111-111111111111', '0a000000-0000-4000-8000-00000000000a') $$,
  '%verification_not_found%', 'a contact verification cannot become a grant');
select is(public.phone_identity_change_grant((select id from mx where k = 'q1'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'),
  'verification_expired', 'a used verification cannot issue a second grant');

-- A number taken as a contact number between the grant and the write.
insert into mx values ('q2', public.phone_verification_start(
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001', 'identity_change', '+971508888888'));
select ok(public.phone_identity_current_proven((select id from mx where k = 'q2'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'), 'current number proven');
select is(public.phone_identity_change_grant((select id from mx where k = 'q2'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'),
  'granted', 'second grant issued');
insert into mx values ('b-late', public.phone_verification_start(
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d', 'contact', '+971508888888'));
select is(public.contact_phone_confirm((select id from mx where k = 'b-late'),
  'b2222222-2222-4222-8222-222222222222', '0d000000-0000-4000-8000-00000000000d'),
  'verified', 'another account took the number as its contact number');
select throws_like($$
  update auth.users set phone = '971508888888' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_unavailable%', 'the write is refused when the number was taken after the grant');

-- An expired grant.
insert into mx values ('q3', public.phone_verification_start(
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001', 'identity_change', '+971509999991'));
select ok(public.phone_identity_current_proven((select id from mx where k = 'q3'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'), 'current number proven');
select is(public.phone_identity_change_grant((select id from mx where k = 'q3'),
  'e5555555-5555-4555-8555-555555555555', '01000000-0000-4000-8000-000000000001'),
  'granted', 'third grant issued');
update public.phone_identity_change_grants set expires_at = now() - interval '1 second'
where user_id = 'e5555555-5555-4555-8555-555555555555';
select throws_like($$
  update auth.users set phone = '971509999991' where id = 'e5555555-5555-4555-8555-555555555555'
$$, '%phone_change_not_authorized%', 'an expired grant is refused');

-- ---------------------------------------------------------------------------
-- Account deletion removes everything Model X stored for the account
-- ---------------------------------------------------------------------------

delete from auth.users where id = 'e5555555-5555-4555-8555-555555555555';
select is((select count(*)::int from public.phone_verifications where user_id = 'e5555555-5555-4555-8555-555555555555')
  + (select count(*)::int from public.phone_identity_change_grants where user_id = 'e5555555-5555-4555-8555-555555555555')
  + (select count(*)::int from public.account_sign_in_methods where user_id = 'e5555555-5555-4555-8555-555555555555'),
  0, 'deleting the account removes its records, grants and sign-in method');

select * from finish();
rollback;
