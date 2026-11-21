-- Notifications N2: user-scheduled Request/Offer follow-up reminders, exactly
-- once inbox creation, a durable push delivery queue and FCM device
-- registration bound to the account's single active app session.
--
-- Source only. Nothing here sends anything: the scheduler (pg_cron + pg_net)
-- and the `push-dispatch` Edge Function are deployed separately, after
-- approval (supabase/deploy/notifications_n2_schedule.sql).
--
-- Trust boundaries:
--   * Clients never write notifications, reminders, jobs or devices directly.
--     They call session-gated SECURITY DEFINER RPCs that check ownership.
--   * Firing, claiming and completing delivery are service_role only.
--   * A device receives a push only if, at claim time, its row is bound to the
--     account's currently active app session (Single Active Device).
--
-- No BEGIN/COMMIT here, like the other recent migrations: `supabase db push`
-- runs the file in one transaction, and the rollback-only validation
-- includes it with \ir inside its own transaction (a COMMIT in this file
-- would make the validation's fixtures permanent).

-- ---------------------------------------------------------------------------
-- 1. Inbox: idempotency key, stable paging order, `system` retired.
-- ---------------------------------------------------------------------------
alter table public.notifications add column event_key text;
alter table public.notifications
  add constraint notifications_event_key_shape
  check (event_key is null or event_key ~ '^[a-z_]{1,32}:[0-9a-f-]{36}:[0-9]{1,9}$');
create unique index notifications_recipient_event_key_uidx
  on public.notifications (recipient_id, event_key) where event_key is not null;

-- Keyset paging (created_at desc, id desc). The old (recipient_id,
-- created_at desc) index is a prefix of this one.
create index notifications_recipient_created_id_idx
  on public.notifications (recipient_id, created_at desc, id desc);
drop index if exists public.notifications_recipient_created_idx;

-- Owner decision 2026-11-20: no system notices. The enum value cannot be
-- dropped in place; the constraint keeps it unusable.
alter table public.notifications
  add constraint notifications_category_offered
  check (category <> 'system'::public.notification_category);

-- ---------------------------------------------------------------------------
-- 2. Push devices: bound to the app session that registered them.
-- ---------------------------------------------------------------------------
alter table public.push_devices add column session_id uuid;
alter table public.push_devices
  add constraint push_devices_locale_valid check (locale is null or locale in ('en', 'ar'));
alter table public.push_devices
  add constraint push_devices_platform_valid check (platform in ('android', 'ios'));
create index push_devices_owner_session_idx on public.push_devices (owner_id, session_id);
drop index if exists public.push_devices_owner_idx;
-- No client grant or policy: the table stays reachable only through the RPCs
-- below (it already has RLS and the restrictive app-session gate).

-- ---------------------------------------------------------------------------
-- 3. Follow-up reminders: one per Request or Offer, chosen by the user.
-- ---------------------------------------------------------------------------
create table public.follow_up_reminders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid references public.requests(id) on delete cascade,
  offer_id uuid references public.offers(id) on delete cascade,
  remind_at timestamptz not null,
  status text not null default 'scheduled',
  -- Bumped on every (re)schedule; part of the inbox event key, so each
  -- schedule produces at most one inbox row.
  generation integer not null default 1,
  notification_id uuid references public.notifications(id) on delete set null,
  fired_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint follow_up_reminders_one_target check (num_nonnulls(request_id, offer_id) = 1),
  constraint follow_up_reminders_status_valid check (status in ('scheduled', 'sent', 'cancelled')),
  constraint follow_up_reminders_generation_positive check (generation > 0),
  constraint follow_up_reminders_cancel_reason_valid
    check (cancel_reason is null or cancel_reason in ('user', 'record_deleted'))
);

create unique index follow_up_reminders_request_uidx
  on public.follow_up_reminders (request_id) where request_id is not null;
create unique index follow_up_reminders_offer_uidx
  on public.follow_up_reminders (offer_id) where offer_id is not null;
create index follow_up_reminders_due_idx
  on public.follow_up_reminders (remind_at) where status = 'scheduled';
create index follow_up_reminders_owner_idx on public.follow_up_reminders (owner_id);
create index follow_up_reminders_notification_idx
  on public.follow_up_reminders (notification_id) where notification_id is not null;

create trigger follow_up_reminders_updated_at before update on public.follow_up_reminders
  for each row execute function public.set_updated_at();

alter table public.follow_up_reminders enable row level security;
revoke all on public.follow_up_reminders from public, anon, authenticated;
grant select on public.follow_up_reminders to authenticated;
create policy follow_up_reminders_select_own on public.follow_up_reminders
  for select to authenticated using (owner_id = (select auth.uid()));
create policy app_session_gate on public.follow_up_reminders
  as restrictive for all to authenticated
  using ((select public.is_current_app_session()))
  with check ((select public.is_current_app_session()));

-- ---------------------------------------------------------------------------
-- 4. Push delivery queue: one job per inbox row. Server-only.
-- ---------------------------------------------------------------------------
create table public.notification_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique references public.notifications(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'queued',
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_until timestamptz,
  -- A fixed code, never a provider message, token or payload.
  last_error text,
  provider_message_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_delivery_jobs_status_valid
    check (status in ('queued', 'sending', 'sent', 'skipped', 'failed')),
  constraint notification_delivery_jobs_attempts_nonnegative check (attempts >= 0),
  constraint notification_delivery_jobs_error_code
    check (last_error is null or last_error ~ '^[a-z0-9_]{1,64}$')
);

create index notification_delivery_jobs_ready_idx
  on public.notification_delivery_jobs (next_attempt_at) where status in ('queued', 'sending');
create index notification_delivery_jobs_recipient_idx
  on public.notification_delivery_jobs (recipient_id);

create trigger notification_delivery_jobs_updated_at before update on public.notification_delivery_jobs
  for each row execute function public.set_updated_at();

alter table public.notification_delivery_jobs enable row level security;
revoke all on public.notification_delivery_jobs from public, anon, authenticated;
-- No policy and no grant: only the SECURITY DEFINER functions below touch it.

-- ---------------------------------------------------------------------------
-- 5. Preferences (profiles.preferences, written by Notification Settings).
--    Missing keys mean "on", as on the settings screen; only an explicit JSON
--    false turns a switch off (no cast can fail inside the dispatcher).
-- ---------------------------------------------------------------------------
create function public.notification_push_allowed(p_user uuid, p_preference text)
returns boolean language sql stable security definer set search_path = ''
as $function$
  select coalesce((
    select (p.preferences->'notificationsEnabled') is distinct from 'false'::jsonb
      and (p.preferences->'notifications'->'push') is distinct from 'false'::jsonb
      and (p.preferences->'notifications'->p_preference) is distinct from 'false'::jsonb
    from public.profiles p
    where p.id = p_user
  ), false);
$function$;
revoke all on function public.notification_push_allowed(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Client RPCs (authenticated, current app session only).
-- ---------------------------------------------------------------------------
create function public.set_follow_up_reminder(
  p_target_type text, p_target_id uuid, p_remind_at timestamptz
)
returns table (reminder_id uuid, remind_at timestamptz, status text)
language plpgsql security definer set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_owner uuid;
  v_deleted timestamptz;
  v_id uuid;
begin
  if v_user is null or not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  if p_target_type is null or p_target_type not in ('request', 'offer') or p_target_id is null then
    raise exception using errcode = '22023', message = 'invalid_target';
  end if;
  if p_remind_at is null or p_remind_at < now() + interval '1 minute' then
    raise exception using errcode = '22023', message = 'remind_at_in_past';
  end if;
  if p_remind_at > now() + interval '366 days' then
    raise exception using errcode = '22023', message = 'remind_at_too_far';
  end if;

  if p_target_type = 'request' then
    select r.owner_id, r.deleted_at into v_owner, v_deleted
    from public.requests r where r.id = p_target_id for share;
  else
    select o.owner_id, o.deleted_at into v_owner, v_deleted
    from public.offers o where o.id = p_target_id for share;
  end if;
  -- One answer for "missing", "deleted" and "someone else's": no oracle.
  if v_owner is distinct from v_user or v_deleted is not null then
    raise exception using errcode = 'P0002', message = 'target_not_found';
  end if;

  if not exists (
    select 1 from public.follow_up_reminders f
    where (p_target_type = 'request' and f.request_id = p_target_id)
       or (p_target_type = 'offer' and f.offer_id = p_target_id)
  ) and (
    select count(*) from public.follow_up_reminders f
    where f.owner_id = v_user and f.status = 'scheduled'
  ) >= 1000 then
    raise exception using errcode = '54000', message = 'too_many_reminders';
  end if;

  if p_target_type = 'request' then
    insert into public.follow_up_reminders as f (owner_id, request_id, remind_at)
    values (v_user, p_target_id, p_remind_at)
    on conflict (request_id) where request_id is not null do update
      set remind_at = excluded.remind_at,
          status = 'scheduled',
          generation = f.generation + 1,
          notification_id = null,
          fired_at = null,
          cancelled_at = null,
          cancel_reason = null
      where f.owner_id = v_user
    returning f.id into v_id;
  else
    insert into public.follow_up_reminders as f (owner_id, offer_id, remind_at)
    values (v_user, p_target_id, p_remind_at)
    on conflict (offer_id) where offer_id is not null do update
      set remind_at = excluded.remind_at,
          status = 'scheduled',
          generation = f.generation + 1,
          notification_id = null,
          fired_at = null,
          cancelled_at = null,
          cancel_reason = null
      where f.owner_id = v_user
    returning f.id into v_id;
  end if;
  if v_id is null then
    raise exception using errcode = 'P0002', message = 'target_not_found';
  end if;

  return query
    select f.id, f.remind_at, f.status from public.follow_up_reminders f where f.id = v_id;
end;
$function$;
revoke all on function public.set_follow_up_reminder(text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.set_follow_up_reminder(text, uuid, timestamptz) to authenticated;

create function public.cancel_follow_up_reminder(p_target_type text, p_target_id uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  if p_target_type is null or p_target_type not in ('request', 'offer') or p_target_id is null then
    raise exception using errcode = '22023', message = 'invalid_target';
  end if;
  update public.follow_up_reminders f
     set status = 'cancelled', cancelled_at = now(), cancel_reason = 'user'
   where f.owner_id = v_user
     and f.status = 'scheduled'
     and ((p_target_type = 'request' and f.request_id = p_target_id)
       or (p_target_type = 'offer' and f.offer_id = p_target_id));
  return found;
end;
$function$;
revoke all on function public.cancel_follow_up_reminder(text, uuid) from public, anon, authenticated;
grant execute on function public.cancel_follow_up_reminder(text, uuid) to authenticated;

-- Registers this install's FCM token for the caller's CURRENT app session and
-- removes every other device row of the account (one active device).
create function public.register_push_device(p_token text, p_platform text, p_locale text)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_session uuid;
  v_hash text;
begin
  if v_user is null or not public.is_current_app_session() then
    raise exception using errcode = '42501', message = 'session_superseded';
  end if;
  v_session := (auth.jwt()->>'session_id')::uuid;
  if p_token is null or length(btrim(p_token)) = 0 or length(p_token) > 4096
     or p_token ~ '\s' then
    raise exception using errcode = '22023', message = 'invalid_token';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios') then
    raise exception using errcode = '22023', message = 'invalid_platform';
  end if;
  v_hash := encode(sha256(convert_to(p_token, 'UTF8')), 'hex');

  insert into public.push_devices as d
    (owner_id, provider, token_value, token_hash, platform, locale, session_id, last_seen_at)
  values
    (v_user, 'fcm', p_token, v_hash, p_platform,
     case when p_locale in ('en', 'ar') then p_locale else 'en' end, v_session, now())
  on conflict (provider, token_hash) do update
    set owner_id = excluded.owner_id,
        token_value = excluded.token_value,
        platform = excluded.platform,
        locale = excluded.locale,
        session_id = excluded.session_id,
        last_seen_at = now();

  -- One device row per account: the account's other sessions (older phones)
  -- and any other token this session registered before (a refreshed token).
  delete from public.push_devices d
   where d.owner_id = v_user
     and (d.session_id is distinct from v_session
          or d.provider <> 'fcm'
          or d.token_hash <> v_hash);
  return true;
end;
$function$;
revoke all on function public.register_push_device(text, text, text) from public, anon, authenticated;
grant execute on function public.register_push_device(text, text, text) to authenticated;

-- Best-effort cleanup on sign-out or when the user turns push off. Not
-- session-gated: a superseded install may still remove its own token. The
-- send-time session check, not this call, is what stops delivery.
create function public.unregister_push_device(p_token text)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or p_token is null then
    return false;
  end if;
  delete from public.push_devices d
   where d.owner_id = v_user
     and d.provider = 'fcm'
     and d.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  return found;
end;
$function$;
revoke all on function public.unregister_push_device(text) from public, anon, authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Server functions (service_role only: pg_cron and push-dispatch).
-- ---------------------------------------------------------------------------

-- Turns due reminders into inbox rows. Exactly once per (reminder,
-- generation): the row lock + status change and the unique event key.
create function public.fire_due_follow_up_reminders(p_limit integer default 200)
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v record;
  v_owner uuid;
  v_deleted timestamptz;
  v_target text;
  v_key text;
  v_notification uuid;
  v_count integer := 0;
begin
  for v in
    select f.id, f.owner_id, f.request_id, f.offer_id, f.generation
    from public.follow_up_reminders f
    where f.status = 'scheduled' and f.remind_at <= now()
    order by f.remind_at
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
    for update skip locked
  loop
    v_owner := null;
    v_deleted := null;
    if v.request_id is not null then
      v_target := 'request';
      select r.owner_id, r.deleted_at into v_owner, v_deleted
      from public.requests r where r.id = v.request_id;
    else
      v_target := 'offer';
      select o.owner_id, o.deleted_at into v_owner, v_deleted
      from public.offers o where o.id = v.offer_id;
    end if;

    if v_owner is distinct from v.owner_id or v_deleted is not null then
      update public.follow_up_reminders
         set status = 'cancelled', cancelled_at = now(), cancel_reason = 'record_deleted'
       where id = v.id;
      continue;
    end if;

    v_key := 'follow_up:' || v.id::text || ':' || v.generation::text;
    v_notification := null;
    insert into public.notifications
      (recipient_id, title, body, category, data, request_id, offer_id, event_key)
    values (
      v.owner_id,
      'Follow-up reminder',
      case v_target when 'request' then 'A request is due for follow-up.'
                    else 'An offer is due for follow-up.' end,
      'reminder',
      jsonb_build_object('kind', 'follow_up', 'target', v_target),
      v.request_id,
      v.offer_id,
      v_key
    )
    on conflict (recipient_id, event_key) where event_key is not null do nothing
    returning id into v_notification;

    if v_notification is null then
      select n.id into v_notification from public.notifications n
       where n.recipient_id = v.owner_id and n.event_key = v_key;
    end if;

    if v_notification is not null then
      insert into public.notification_delivery_jobs (notification_id, recipient_id)
      values (v_notification, v.owner_id)
      on conflict (notification_id) do nothing;
    end if;

    update public.follow_up_reminders
       set status = 'sent', fired_at = now(), notification_id = v_notification
     where id = v.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;
revoke all on function public.fire_due_follow_up_reminders(integer) from public, anon, authenticated;
grant execute on function public.fire_due_follow_up_reminders(integer) to service_role;

-- Leases ready jobs and returns, for each one still deliverable, the token of
-- the account's CURRENT active device. Everything is re-checked here, at send
-- time: the inbox row still exists and is unread, preferences allow push, and
-- the device row belongs to the active app session of a live auth session.
create function public.claim_push_delivery_jobs(
  p_limit integer default 50, p_lease_seconds integer default 60
)
returns table (
  job_id uuid, notification_id uuid, device_id uuid, token text,
  locale text, target text, attempt integer
)
language plpgsql security definer set search_path = ''
as $function$
#variable_conflict use_column
declare
  v record;
  v_target text;
  v_preference text;
  v_device record;
  v_lease integer := greatest(15, least(coalesce(p_lease_seconds, 60), 600));
begin
  for v in
    select j.id, j.notification_id, j.recipient_id, j.attempts,
           n.is_read, n.data->>'target' as target, n.category,
           n.request_id, n.offer_id
    from public.notification_delivery_jobs j
    left join public.notifications n on n.id = j.notification_id
    where j.next_attempt_at <= now()
      and (j.status = 'queued' or (j.status = 'sending' and j.lease_until < now()))
    order by j.next_attempt_at
    limit greatest(1, least(coalesce(p_limit, 50), 500))
    for update of j skip locked
  loop
    if v.category is null then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'notification_gone', lease_until = null
       where id = v.id;
      continue;
    end if;
    if v.is_read then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'already_read', lease_until = null
       where id = v.id;
      continue;
    end if;
    -- The record was deleted (hard delete nulls the link) or soft-deleted
    -- after the reminder fired: no push about it.
    if (v.request_id is null and v.offer_id is null)
       or exists (select 1 from public.requests r
                  where r.id = v.request_id and r.deleted_at is not null)
       or exists (select 1 from public.offers o
                  where o.id = v.offer_id and o.deleted_at is not null) then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'record_deleted', lease_until = null
       where id = v.id;
      continue;
    end if;

    v_target := case when v.target in ('request', 'offer') then v.target else null end;
    v_preference := case v_target when 'request' then 'requestReminders'
                                  when 'offer' then 'offerReminders'
                                  else null end;
    if v_preference is null then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'unsupported_kind', lease_until = null
       where id = v.id;
      continue;
    end if;
    if not public.notification_push_allowed(v.recipient_id, v_preference) then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'push_disabled', lease_until = null
       where id = v.id;
      continue;
    end if;

    select d.id, d.token_value, d.locale into v_device
    from public.push_devices d
    join public.user_active_sessions s
      on s.user_id = d.owner_id and s.active_session_id = d.session_id
    join auth.sessions a
      on a.id = s.active_session_id and a.user_id = s.user_id
    where d.owner_id = v.recipient_id and d.provider = 'fcm'
    order by d.last_seen_at desc
    limit 1;
    if not found then
      update public.notification_delivery_jobs
         set status = 'skipped', last_error = 'no_active_device', lease_until = null
       where id = v.id;
      continue;
    end if;

    update public.notification_delivery_jobs
       set status = 'sending', attempts = attempts + 1,
           lease_until = now() + make_interval(secs => v_lease)
     where id = v.id;

    job_id := v.id;
    notification_id := v.notification_id;
    device_id := v_device.id;
    token := v_device.token_value;
    locale := coalesce(v_device.locale, 'en');
    target := v_target;
    attempt := v.attempts + 1;
    return next;
  end loop;
end;
$function$;
revoke all on function public.claim_push_delivery_jobs(integer, integer) from public, anon, authenticated;
grant execute on function public.claim_push_delivery_jobs(integer, integer) to service_role;

-- Records the provider's answer for a leased job.
--   sent           -> done
--   retry          -> queued again with backoff, failed after 5 attempts
--   invalid_token  -> device row removed, job skipped
--   failed         -> permanent failure
create function public.complete_push_delivery_job(
  p_job_id uuid, p_outcome text, p_error text default null,
  p_provider_message_id text default null, p_device_id uuid default null,
  p_retry_after_seconds integer default null
)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_attempts integer;
  v_error text := case when p_error ~ '^[a-z0-9_]{1,64}$' then p_error else null end;
  v_delay integer;
begin
  select j.attempts into v_attempts
  from public.notification_delivery_jobs j
  where j.id = p_job_id and j.status = 'sending'
  for update;
  if not found then
    return false;
  end if;

  if p_outcome = 'sent' then
    update public.notification_delivery_jobs
       set status = 'sent', lease_until = null, last_error = null,
           provider_message_id = left(p_provider_message_id, 200)
     where id = p_job_id;
  elsif p_outcome = 'retry' then
    if v_attempts >= 5 then
      update public.notification_delivery_jobs
         set status = 'failed', lease_until = null,
             last_error = coalesce(v_error, 'retries_exhausted')
       where id = p_job_id;
    else
      -- least()/greatest() ignore NULL, so the provider hint is tested first.
      v_delay := case
        when p_retry_after_seconds is not null
          then greatest(1, least(p_retry_after_seconds, 3600))
        else least(3600, 30 * (2 ^ greatest(v_attempts - 1, 0))::integer)
      end;
      update public.notification_delivery_jobs
         set status = 'queued', lease_until = null,
             next_attempt_at = now() + make_interval(secs => v_delay),
             last_error = coalesce(v_error, 'transient')
       where id = p_job_id;
    end if;
  elsif p_outcome = 'invalid_token' then
    if p_device_id is not null then
      delete from public.push_devices where id = p_device_id;
    end if;
    update public.notification_delivery_jobs
       set status = 'skipped', lease_until = null,
           last_error = coalesce(v_error, 'device_unregistered')
     where id = p_job_id;
  elsif p_outcome = 'failed' then
    update public.notification_delivery_jobs
       set status = 'failed', lease_until = null,
           last_error = coalesce(v_error, 'provider_rejected')
     where id = p_job_id;
  else
    raise exception using errcode = '22023', message = 'invalid_outcome';
  end if;
  return true;
end;
$function$;
revoke all on function public.complete_push_delivery_job(uuid, text, text, text, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.complete_push_delivery_job(uuid, text, text, text, uuid, integer)
  to service_role;

-- Retention: finished jobs are kept 30 days for diagnostics, then removed.
create function public.prune_push_delivery_jobs()
returns integer
language sql security definer set search_path = ''
as $function$
  with gone as (
    delete from public.notification_delivery_jobs
     where status in ('sent', 'skipped', 'failed')
       and updated_at < now() - interval '30 days'
    returning 1
  )
  select count(*)::integer from gone;
$function$;
revoke all on function public.prune_push_delivery_jobs() from public, anon, authenticated;
grant execute on function public.prune_push_delivery_jobs() to service_role;
