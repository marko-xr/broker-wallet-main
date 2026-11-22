-- Delete Account challenges for phone accounts
-- (20261122140000_phone_account_deletion.sql). Run with `supabase test db`.
-- Writes to auth.users run as postgres, standing in for Supabase Auth; the
-- functions are what the Worker calls with the service role.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(43);

-- E: email account. P, Q: phone accounts (Supabase stores numbers without '+').
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values ('e1111111-1111-4111-8111-111111111111', 'del-e@example.test', '{}'::jsonb, now(), now());
insert into auth.users (id, phone, phone_confirmed_at, raw_user_meta_data, created_at, updated_at)
values
  ('a2222222-2222-4222-8222-222222222222', '971501111201', now(), '{}'::jsonb, now(), now()),
  ('b3333333-3333-4333-8333-333333333333', '971501111202', now(), '{}'::jsonb, now(), now());
-- P later adds an email: it is still a phone account.
update auth.users set email = 'del-p@example.test', email_confirmed_at = now()
where id = 'a2222222-2222-4222-8222-222222222222';

-- ---------------------------------------------------------------------------
-- Structure and grants
-- ---------------------------------------------------------------------------

select has_table('public', 'account_deletion_challenges', 'challenge table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.account_deletion_challenges'::regclass),
  'row level security is on');
select ok(not exists (
  select 1 from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) p(priv)
  cross join (values ('anon'), ('authenticated'), ('service_role')) r(role)
  where has_table_privilege(r.role, 'public.account_deletion_challenges', p.priv)),
  'no role reads or writes challenges directly');
select ok(not exists (
  select 1 from (values
    ('public.account_deletion_challenge_issue(uuid,uuid)'),
    ('public.account_deletion_challenge_attempt(uuid,uuid)'),
    ('public.account_deletion_challenge_consume(uuid,uuid)')) f(sig)
  cross join (values ('anon'), ('authenticated')) r(role)
  where has_function_privilege(r.role, f.sig, 'EXECUTE')),
  'clients cannot execute the challenge functions');
select ok((select bool_and(has_function_privilege('service_role', f.sig, 'EXECUTE')) from (values
    ('public.account_deletion_challenge_issue(uuid,uuid)'),
    ('public.account_deletion_challenge_attempt(uuid,uuid)'),
    ('public.account_deletion_challenge_consume(uuid,uuid)')) f(sig)),
  'the service role (Worker) can execute them');
select ok((select bool_and(p.prosecdef) from pg_proc p
  where p.oid in ('public.account_deletion_challenge_issue(uuid,uuid)'::regprocedure,
                  'public.account_deletion_challenge_attempt(uuid,uuid)'::regprocedure,
                  'public.account_deletion_challenge_consume(uuid,uuid)'::regprocedure)),
  'the functions run as their owner');

-- ---------------------------------------------------------------------------
-- Who may ask
-- ---------------------------------------------------------------------------

select throws_like($$ select public.account_deletion_challenge_issue(
  'e1111111-1111-4111-8111-111111111111', '0e000000-0000-4000-8000-000000000001') $$,
  '%not_available_for_account%', 'an email account keeps the password path only');
select throws_like($$ select public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', null) $$,
  '%invalid_request%', 'a challenge is always bound to a session');
select throws_like($$ select public.account_deletion_challenge_issue(
  'f9999999-9999-4999-8999-999999999999', '0e000000-0000-4000-8000-000000000001') $$,
  '%not_available_for_account%', 'an unknown account gets nothing');

-- ---------------------------------------------------------------------------
-- Session binding, single use, replay
-- ---------------------------------------------------------------------------

set local role service_role;
select is(public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'issued', 'a phone account that added an email can ask for a code');
reset role;
select is(public.account_deletion_challenge_attempt(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000002'),
  'challenge_required', 'another session of the account cannot use the challenge');
select is(public.account_deletion_challenge_attempt(
  'b3333333-3333-4333-8333-333333333333', '0a000000-0000-4000-8000-000000000001'),
  'challenge_required', 'another account cannot use it');
select is((select attempts from public.account_deletion_challenges
  where user_id = 'a2222222-2222-4222-8222-222222222222'), 0,
  'refused attempts from elsewhere are not counted against the owner');
select is(public.account_deletion_challenge_attempt(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'ok', 'the session that asked may try a code');
select ok(not public.account_deletion_challenge_consume(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000002'),
  'another session cannot use the proof');
set local role service_role;
select ok(public.account_deletion_challenge_consume(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'the proof is used once');
reset role;
select ok(not public.account_deletion_challenge_consume(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'a second use (replay) is refused');
select is(public.account_deletion_challenge_attempt(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'challenge_required', 'a used challenge accepts no more codes');

-- A new request from a newer session replaces the older one.
select is(public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'issued', 'a second code in the hour');
select is(public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000003'),
  'issued', 'a third code, from a newer session');
select is(public.account_deletion_challenge_attempt(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'challenge_required', 'the older session lost its challenge');
select ok(not public.account_deletion_challenge_consume(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000001'),
  'and cannot use it');
select is(public.account_deletion_challenge_attempt(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000003'),
  'ok', 'the newer session can');

-- ---------------------------------------------------------------------------
-- Rate limit
-- ---------------------------------------------------------------------------

select throws_like($$ select public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000003') $$,
  '%too_many_requests%', 'no more than three codes an hour');
update public.account_deletion_challenges
   set window_started_at = now() - interval '61 minutes'
 where user_id = 'a2222222-2222-4222-8222-222222222222';
select is(public.account_deletion_challenge_issue(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000003'),
  'issued', 'a new hour allows a new code');
select is((select issued_in_window from public.account_deletion_challenges
  where user_id = 'a2222222-2222-4222-8222-222222222222'), 1, 'the count restarts with the hour');

-- ---------------------------------------------------------------------------
-- Attempt cap and expiry
-- ---------------------------------------------------------------------------

select is(public.account_deletion_challenge_issue(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'), 'issued', 'Q asks');
-- The lateral call refers to g so it runs once per row.
select is((select string_agg(public.account_deletion_challenge_attempt(
    'b3333333-3333-4333-8333-333333333333',
    case when g > 0 then '0b000000-0000-4000-8000-000000000001'::uuid end), ',' order by g)
  from generate_series(1, 5) g),
  'ok,ok,ok,ok,ok', 'five attempts are allowed');
select is(public.account_deletion_challenge_attempt(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'too_many_attempts', 'the sixth is refused');
select is(public.account_deletion_challenge_attempt(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'challenge_expired', 'and the challenge is closed');
select ok(not public.account_deletion_challenge_consume(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'a closed challenge gives no proof');

select is(public.account_deletion_challenge_issue(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'issued', 'a fresh code reopens it');
select is((select attempts from public.account_deletion_challenges
  where user_id = 'b3333333-3333-4333-8333-333333333333'), 0, 'with a fresh attempt count');
update public.account_deletion_challenges set expires_at = now() - interval '1 second'
 where user_id = 'b3333333-3333-4333-8333-333333333333';
select is(public.account_deletion_challenge_attempt(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'challenge_expired', 'an expired challenge accepts no code');
select ok(not public.account_deletion_challenge_consume(
  'b3333333-3333-4333-8333-333333333333', '0b000000-0000-4000-8000-000000000001'),
  'and gives no proof');

-- ---------------------------------------------------------------------------
-- Clients
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a2222222-2222-4222-8222-222222222222","role":"authenticated","session_id":"0a000000-0000-4000-8000-000000000003"}', true);
select throws_ok($$ select * from public.account_deletion_challenges $$, '42501', null,
  'the account itself cannot read its challenge');
select throws_ok($$ select public.account_deletion_challenge_consume(
  'a2222222-2222-4222-8222-222222222222', '0a000000-0000-4000-8000-000000000003') $$, '42501', null,
  'the account itself cannot mark a proof');
select throws_ok($$ update public.account_deletion_challenges set attempts = 0 $$, '42501', null,
  'the account itself cannot reset attempts');
reset role;

-- ---------------------------------------------------------------------------
-- Account deletion removes the challenge
-- ---------------------------------------------------------------------------

select is((select count(*)::int from public.account_deletion_challenges), 2, 'two challenges stored');
select ok((select bool_and(c.session_id is not null) from public.account_deletion_challenges c),
  'every challenge names its session');
select ok(not exists (
  select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'account_deletion_challenges'
     and column_name ~ '(phone|code|token)'),
  'no number, code or token is stored');
delete from auth.users where id = 'b3333333-3333-4333-8333-333333333333';
select is((select count(*)::int from public.account_deletion_challenges
  where user_id = 'b3333333-3333-4333-8333-333333333333'), 0, 'deleting the account removes its challenge');
select is((select count(*)::int from public.account_deletion_challenges), 1, 'others are untouched');

select * from finish();
rollback;
