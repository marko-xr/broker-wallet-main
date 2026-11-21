-- SOURCE ONLY. Rollback-only validation of
-- 20261120130000_follow_up_reminders_and_push_delivery.sql.
-- Run only with the owner's approval, as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/follow_up_reminders_validation.sql
--
-- This file includes the exact migration inside ONE transaction that always
-- ends in ROLLBACK (an error also aborts it), so:
--   * no table, function, row or migration-history entry persists;
--   * the new tables exist only inside this transaction and start empty, so
--     firing and claiming can only touch this script's own fixtures;
--   * nothing leaves the database: no Edge Function call, no pg_net, no
--     pg_cron, and Realtime publishes only committed changes;
--   * no token or account id is printed (results are checked in DO blocks).
-- The fixture accounts use the reserved `.invalid` domain and fixed ids that
-- the preflight requires to be unused.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or not pg_has_role('postgres', 'authenticated', 'member')
     or not pg_has_role('postgres', 'service_role', 'member')
     or to_regclass('public.follow_up_reminders') is not null
     or to_regclass('public.notification_delivery_jobs') is not null
     or to_regprocedure('public.set_follow_up_reminder(text, uuid, timestamptz)') is not null
     or to_regprocedure('public.claim_current_app_session()') is null
     or exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'push_devices'
                  and column_name = 'session_id')
     or exists (select 1 from public.notifications where category = 'system')
     or exists (select 1 from auth.users where id in (
       'f0110000-0000-4000-8000-00000000000a'::uuid,
       'f0110000-0000-4000-8000-00000000000b'::uuid)) then
    raise exception 'follow-up validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20261120130000_follow_up_reminders_and_push_delivery.sql

insert into auth.users(id, email, raw_user_meta_data, created_at, updated_at)
values
  ('f0110000-0000-4000-8000-00000000000a', 'follow-up-a@validation.invalid', '{"name":"A"}', now(), now()),
  ('f0110000-0000-4000-8000-00000000000b', 'follow-up-b@validation.invalid', '{"name":"B"}', now(), now());
insert into auth.sessions(id, user_id, created_at, updated_at)
values
  ('f0110000-0000-4000-8000-000000000001', 'f0110000-0000-4000-8000-00000000000a', now(), now()),
  ('f0110000-0000-4000-8000-000000000002', 'f0110000-0000-4000-8000-00000000000a', now(), now()),
  ('f0110000-0000-4000-8000-000000000004', 'f0110000-0000-4000-8000-00000000000b', now(), now());
insert into public.requests(id, owner_id, request_type)
values
  ('f0110000-0000-4000-8000-000000000010', 'f0110000-0000-4000-8000-00000000000a', 'rent'),
  ('f0110000-0000-4000-8000-000000000011', 'f0110000-0000-4000-8000-00000000000b', 'rent');

-- A on phone 1: claim, register a device.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0110000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims', '{"sub":"f0110000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"f0110000-0000-4000-8000-000000000001"}', true);
do $phone1$
begin
  perform public.claim_current_app_session();
  perform public.register_push_device('validation-token-phone-1', 'android', 'en');
end;
$phone1$;

-- A on phone 2: phone 1 is superseded.
select set_config('request.jwt.claims', '{"sub":"f0110000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"f0110000-0000-4000-8000-000000000002"}', true);
do $phone2$
declare
  v_id uuid;
  v_id2 uuid;
begin
  perform public.claim_current_app_session();
  select reminder_id into v_id from public.set_follow_up_reminder(
    'request', 'f0110000-0000-4000-8000-000000000010', now() + interval '10 minutes');
  select reminder_id into v_id2 from public.set_follow_up_reminder(
    'request', 'f0110000-0000-4000-8000-000000000010', now() + interval '20 minutes');
  if v_id is null or v_id is distinct from v_id2 then
    raise exception 'create/edit did not keep one reminder';
  end if;
  begin
    perform public.set_follow_up_reminder(
      'request', 'f0110000-0000-4000-8000-000000000011', now() + interval '10 minutes');
    raise exception 'scheduling on another account record succeeded';
  exception when no_data_found then null;
  end;
  begin
    perform public.set_follow_up_reminder(
      'request', 'f0110000-0000-4000-8000-000000000010', now() - interval '1 minute');
    raise exception 'a past time was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    insert into public.notifications(recipient_id, title, body, category)
    values ('f0110000-0000-4000-8000-00000000000a', 't', 'b', 'reminder');
    raise exception 'client inserted a notification';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.notification_delivery_jobs;
    raise exception 'client read delivery jobs';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.push_devices;
    raise exception 'client read push devices';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.fire_due_follow_up_reminders(10);
    raise exception 'client fired reminders';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.claim_push_delivery_jobs(10, 60);
    raise exception 'client claimed jobs';
  exception when insufficient_privilege then null;
  end;
  perform public.register_push_device('validation-token-phone-2-old', 'android', 'ar');
  perform public.register_push_device('validation-token-phone-2', 'android', 'ar');
end;
$phone2$;

-- The superseded phone can neither schedule, register nor read.
select set_config('request.jwt.claims', '{"sub":"f0110000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"f0110000-0000-4000-8000-000000000001"}', true);
do $superseded$
begin
  begin
    perform public.set_follow_up_reminder(
      'request', 'f0110000-0000-4000-8000-000000000010', now() + interval '10 minutes');
    raise exception 'superseded session scheduled';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.register_push_device('validation-token-phone-1', 'android', 'en');
    raise exception 'superseded session registered a device';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.follow_up_reminders) then
    raise exception 'superseded session read reminders';
  end if;
end;
$superseded$;

-- B sees nothing of A.
select set_config('request.jwt.claim.sub', 'f0110000-0000-4000-8000-00000000000b', true);
select set_config('request.jwt.claims', '{"sub":"f0110000-0000-4000-8000-00000000000b","role":"authenticated","session_id":"f0110000-0000-4000-8000-000000000004"}', true);
do $other$
begin
  perform public.claim_current_app_session();
  if exists (select 1 from public.follow_up_reminders)
     or exists (select 1 from public.notifications
                where recipient_id = 'f0110000-0000-4000-8000-00000000000a') then
    raise exception 'another account read A rows';
  end if;
end;
$other$;

-- Device state, as postgres: exactly one row for A, on phone 2's session.
reset role;
do $devices$
begin
  if (select count(*) from public.push_devices
      where owner_id = 'f0110000-0000-4000-8000-00000000000a') <> 1
     or not exists (select 1 from public.push_devices
                    where owner_id = 'f0110000-0000-4000-8000-00000000000a'
                      and token_value = 'validation-token-phone-2'
                      and session_id = 'f0110000-0000-4000-8000-000000000002') then
    raise exception 'A does not have exactly one device on the active session';
  end if;
end;
$devices$;

update public.follow_up_reminders set remind_at = now() - interval '1 second'
where request_id = 'f0110000-0000-4000-8000-000000000010';

-- Only function calls run as service_role (they are its whole interface);
-- their results stay in transaction-local settings and are never printed.
set local role service_role;
do $server$
begin
  perform set_config('bw_validation.fire1', public.fire_due_follow_up_reminders(100)::text, true);
  perform set_config('bw_validation.fire2', public.fire_due_follow_up_reminders(100)::text, true);
  perform set_config('bw_validation.claims', coalesce((
    select string_agg(c.job_id::text || '=' || c.token, ',')
    from public.claim_push_delivery_jobs(500, 60) c), ''), true);
end;
$server$;
reset role;

do $results$
declare
  v_claims text[] := string_to_array(nullif(current_setting('bw_validation.claims'), ''), ',');
  v_for_a text[];
begin
  if current_setting('bw_validation.fire1')::integer <> 1
     or current_setting('bw_validation.fire2')::integer <> 0 then
    raise exception 'fire was not exactly once';
  end if;
  if (select count(*) from public.notifications
      where request_id = 'f0110000-0000-4000-8000-000000000010') <> 1 then
    raise exception 'not exactly one inbox row';
  end if;
  if coalesce(array_length(v_claims, 1), 0) <> 1 then
    raise exception 'claim did not return exactly the fixture job';
  end if;
  select array_agg(split_part(c, '=', 2)) into v_for_a
  from unnest(v_claims) c
  join public.notification_delivery_jobs j on j.id = split_part(c, '=', 1)::uuid
  where j.recipient_id = 'f0110000-0000-4000-8000-00000000000a';
  if v_for_a is distinct from array['validation-token-phone-2'] then
    raise exception 'claim did not target only the active phone';
  end if;
  begin
    insert into public.notifications(recipient_id, title, body, category, event_key)
    select recipient_id, 't', 'b', 'reminder', event_key from public.notifications
    where request_id = 'f0110000-0000-4000-8000-000000000010';
    raise exception 'a second inbox row with the same event key was accepted';
  exception when unique_violation then null;
  end;
end;
$results$;

-- Single Active Device at send time: A signs in on a third phone that has
-- registered no token. A new reminder for A must reach no device at all, not
-- even phone 2, whose token row is still present.
insert into auth.sessions(id, user_id, created_at, updated_at)
values ('f0110000-0000-4000-8000-000000000003', 'f0110000-0000-4000-8000-00000000000a', now(), now());
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0110000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims', '{"sub":"f0110000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"f0110000-0000-4000-8000-000000000003"}', true);
do $phone3$
begin
  perform public.claim_current_app_session();
  perform public.set_follow_up_reminder(
    'request', 'f0110000-0000-4000-8000-000000000010', now() + interval '10 minutes');
end;
$phone3$;
reset role;
update public.follow_up_reminders set remind_at = now() - interval '1 second'
where request_id = 'f0110000-0000-4000-8000-000000000010';
set local role service_role;
do $server2$
begin
  perform public.fire_due_follow_up_reminders(100);
  perform set_config('bw_validation.claims2', coalesce((
    select count(*)::text from public.claim_push_delivery_jobs(500, 60)), '0'), true);
end;
$server2$;
reset role;
do $superseded_device$
begin
  if current_setting('bw_validation.claims2') <> '0'
     or not exists (
       select 1 from public.notification_delivery_jobs j
       join public.notifications n on n.id = j.notification_id
       where n.request_id = 'f0110000-0000-4000-8000-000000000010'
         and j.status = 'skipped' and j.last_error = 'no_active_device') then
    raise exception 'a push was claimed for a superseded device';
  end if;
end;
$superseded_device$;

select 'follow_up_reminders_validation: PASS' as result;
rollback;
