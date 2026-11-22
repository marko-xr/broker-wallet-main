-- Delete Account for accounts that sign in by phone (C4, Model X).
--
-- An email account keeps the existing password confirmation unchanged. A phone
-- account proves possession of its sign-in number: the Worker asks Supabase
-- Auth to send a sign-in code to the number taken from the verified account
-- (never from the request), checks the code server-side, revokes the session
-- that check creates, and only then starts the existing deletion lifecycle.
-- A phone account that added an email and set a password may use the password
-- path instead (the Worker's existing check).
--
-- This table binds that code to the account AND to the app session that asked
-- for it, caps the attempts, and makes the proof single-use, so a code cannot
-- be replayed and a superseded or stolen older session cannot use a code that
-- the current session requested. It holds no number and no code.
--
-- Depends on 20261122130000_phone_identity_model_x.sql (sign-in methods).
-- Service-role functions only. No BEGIN/COMMIT: applied by the reviewed
-- single-transaction apply. Hosted application needs a separate approval.

create table public.account_deletion_challenges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null,
  attempts integer not null default 0
    constraint account_deletion_challenges_attempts check (attempts between 0 and 5),
  issued_in_window integer not null default 0
    constraint account_deletion_challenges_issued check (issued_in_window between 0 and 3),
  window_started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.account_deletion_challenges enable row level security;
revoke all on public.account_deletion_challenges from public, anon, authenticated, service_role;

-- Before the Worker asks Supabase Auth for a code: records a challenge for
-- this account and session (a new one replaces the previous one, which can no
-- longer be used). At most three per account per hour.
create function public.account_deletion_challenge_issue(p_user uuid, p_session uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v public.account_deletion_challenges%rowtype;
begin
  if p_user is null or p_session is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if not exists (select 1 from public.account_sign_in_methods m
                  where m.user_id = p_user and m.primary_method = 'phone') then
    raise exception using errcode = 'P0001', message = 'not_available_for_account';
  end if;

  -- One row per account; concurrent requests serialize on it.
  insert into public.account_deletion_challenges
    (user_id, session_id, attempts, issued_in_window, window_started_at, expires_at, consumed_at)
  values (p_user, p_session, 0, 0, now(), now(), now())
  on conflict (user_id) do nothing;
  select * into v from public.account_deletion_challenges c where c.user_id = p_user for update;

  if v.window_started_at <= now() - interval '1 hour' then
    v.issued_in_window := 0;
    v.window_started_at := now();
  end if;
  if v.issued_in_window >= 3 then
    raise exception using errcode = 'P0001', message = 'too_many_requests';
  end if;

  update public.account_deletion_challenges c
     set session_id = p_session,
         attempts = 0,
         issued_in_window = v.issued_in_window + 1,
         window_started_at = v.window_started_at,
         expires_at = now() + interval '10 minutes',
         consumed_at = null,
         updated_at = now()
   where c.user_id = p_user;
  return 'issued';
end;
$function$;

-- Before the Worker checks a code: counts one attempt for this account's
-- challenge from this session. Outcomes are returned, not raised, so a closed
-- challenge stays closed: 'ok', 'challenge_required' (none, used, or from
-- another session), 'challenge_expired' or 'too_many_attempts'.
create function public.account_deletion_challenge_attempt(p_user uuid, p_session uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v public.account_deletion_challenges%rowtype;
begin
  select * into v from public.account_deletion_challenges c where c.user_id = p_user for update;
  if not found or v.consumed_at is not null or v.session_id is distinct from p_session then
    return 'challenge_required';
  end if;
  if v.expires_at <= now() then
    return 'challenge_expired';
  end if;
  if v.attempts >= 5 then
    update public.account_deletion_challenges c
       set expires_at = now(), updated_at = now()
     where c.user_id = p_user;
    return 'too_many_attempts';
  end if;
  update public.account_deletion_challenges c
     set attempts = c.attempts + 1, updated_at = now()
   where c.user_id = p_user;
  return 'ok';
end;
$function$;

-- After Supabase Auth accepted the code and its session was revoked: uses the
-- challenge up. True exactly once per issued challenge.
create function public.account_deletion_challenge_consume(p_user uuid, p_session uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.account_deletion_challenges c
     set consumed_at = now(), updated_at = now()
   where c.user_id = p_user
     and c.session_id = p_session
     and c.consumed_at is null
     and c.expires_at > now();
  return found;
end;
$function$;

revoke all on function public.account_deletion_challenge_issue(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.account_deletion_challenge_attempt(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.account_deletion_challenge_consume(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.account_deletion_challenge_issue(uuid, uuid) to service_role;
grant execute on function public.account_deletion_challenge_attempt(uuid, uuid) to service_role;
grant execute on function public.account_deletion_challenge_consume(uuid, uuid) to service_role;
