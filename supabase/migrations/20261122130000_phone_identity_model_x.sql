-- Model X: one sign-in identifier per account (owner decision, 2026-11-22).
--
--   * An account created by email signs in by email. Its phone number is a
--     verified CONTACT number only: it is never stored in auth.users.phone,
--     so Supabase Auth can never sign anyone in with it.
--   * An account created by phone signs in by phone (Supabase OTP).
--   * Supabase's self-service phone change (`PUT /user {phone}` ->
--     phone_change -> `POST /verify type=phone_change`) is never accepted for
--     any account: its confirmation is not bound to the account's session and
--     issues a session to whoever holds the code (GoTrue v2.198.0 verify.go).
--   * A phone-primary number change happens only through the Worker, which
--     re-verifies the account and both numbers and then writes the number with
--     the Auth Admin API; this table-level guard accepts that write only
--     against a single-use grant for exactly that number.
--   * A contact number is verified by the Worker for the signed-in,
--     Single-Active-Device-current session through an SMS provider's
--     verification API, and written to public.profiles by the service role.
--     A provider code never grants Auth access.
--   * One number belongs to at most one account, as a sign-in number or a
--     contact number (profiles_phone_e164_unique + explicit checks).
--
-- Sensitive: adds triggers on auth.users and replaces the auth -> profile
-- sync. Hosted application needs a separate owner approval, a rollback-only
-- validation first, and an isolated staging project for the GoTrue paths.
-- No BEGIN/COMMIT: applied by the reviewed single-transaction apply.

-- ---------------------------------------------------------------------------
-- 0. Preconditions: refuse to install over a state Model X does not allow,
--    instead of silently leaving a sign-in number on an email account.
-- ---------------------------------------------------------------------------

-- A re-apply after phone_identity_model_x_rollback.sql finds that script's
-- backup (public.model_x_rollback_backup): a phone account that had added an
-- email is then recognised as a phone account, not refused.
do $preconditions$
begin
  if to_regclass('public.model_x_rollback_backup') is null then
    if exists (
      select 1 from auth.users u
       where coalesce(u.email, '') <> '' and coalesce(u.phone, '') <> ''
    ) then
      raise exception 'model_x: an email account holds a sign-in phone number; resolve it before applying';
    end if;
  else
    if exists (
      select 1 from auth.users u
       where coalesce(u.email, '') <> '' and coalesce(u.phone, '') <> ''
         and not exists (select 1 from public.model_x_rollback_backup b
                          where b.user_id = u.id and b.primary_method = 'phone')
    ) then
      raise exception 'model_x: an email account holds a sign-in phone number; resolve it before applying';
    end if;
  end if;
end;
$preconditions$;

-- Any pending self-service phone change is abandoned: its code must never be
-- usable once this guard exists (the guard below refuses new ones).
update auth.users
   set phone_change = '',
       phone_change_token = '',
       phone_change_sent_at = null
 where coalesce(phone_change, '') <> '';

-- ---------------------------------------------------------------------------
-- 1. The sign-in method each account was created with (fixed at creation)
-- ---------------------------------------------------------------------------

create table public.account_sign_in_methods (
  user_id uuid primary key references auth.users(id) on delete cascade,
  primary_method text not null
    constraint account_sign_in_methods_method check (primary_method in ('email', 'phone')),
  created_at timestamptz not null default now()
);

alter table public.account_sign_in_methods enable row level security;
revoke all on public.account_sign_in_methods from public, anon, authenticated, service_role;
grant select on public.account_sign_in_methods to authenticated;
create policy account_sign_in_methods_select_own on public.account_sign_in_methods
  for select to authenticated using (user_id = (select auth.uid()));
create policy app_session_gate on public.account_sign_in_methods
  as restrictive for all to authenticated
  using ((select public.is_current_app_session()))
  with check ((select public.is_current_app_session()));

create function public.sign_in_method_for(p_email text, p_phone text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when coalesce(p_email, '') <> '' then 'email'
    when coalesce(p_phone, '') <> '' then 'phone'
    else 'email'
  end
$function$;
revoke all on function public.sign_in_method_for(text, text) from public, anon, authenticated, service_role;

-- Existing accounts (all email accounts at the time of writing). After a
-- rollback, the method each account had is taken from the backup first.
do $backfill$
begin
  if to_regclass('public.model_x_rollback_backup') is not null then
    insert into public.account_sign_in_methods (user_id, primary_method)
    select b.user_id, b.primary_method
      from public.model_x_rollback_backup b
      join auth.users u on u.id = b.user_id
    on conflict (user_id) do nothing;
  end if;
end;
$backfill$;
insert into public.account_sign_in_methods (user_id, primary_method)
select u.id, public.sign_in_method_for(u.email, u.phone)
  from auth.users u
on conflict (user_id) do nothing;

create function public.record_account_sign_in_method()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.account_sign_in_methods (user_id, primary_method)
  values (new.id, public.sign_in_method_for(new.email, new.phone))
  on conflict (user_id) do nothing;
  return new;
end;
$function$;
revoke all on function public.record_account_sign_in_method() from public, anon, authenticated, service_role;

create trigger on_auth_user_sign_in_method
  after insert on auth.users
  for each row execute function public.record_account_sign_in_method();

-- ---------------------------------------------------------------------------
-- 2. Number ownership (one number, one account)
-- ---------------------------------------------------------------------------

create function public.phone_digits(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select ltrim(coalesce(p_phone, ''), '+')
$function$;
revoke all on function public.phone_digits(text) from public, anon, authenticated, service_role;

-- Whether a number already belongs to an account other than p_except:
-- as its sign-in number (auth.users.phone) or as its mirrored/contact number
-- (profiles.phone_e164).
create function public.phone_number_is_held(p_phone text, p_except uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
      -- Supabase Auth stores numbers without '+'; both spellings are checked
      -- so the unique index on auth.users.phone serves the lookup.
      select 1 from auth.users u
       where u.phone in (public.phone_digits(p_phone), '+' || public.phone_digits(p_phone))
         and public.phone_digits(p_phone) <> ''
         and u.id is distinct from p_except
    )
    or exists (
      select 1 from public.profiles p
       where p.phone_e164 = '+' || public.phone_digits(p_phone)
         and p.id is distinct from p_except
    )
$function$;
revoke all on function public.phone_number_is_held(text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.phone_number_is_held(text, uuid) to supabase_auth_admin, service_role;

-- ---------------------------------------------------------------------------
-- 3. Guard on auth.users: no phone for email accounts, no self-service
--    phone change, phone-primary number writes only against a grant
-- ---------------------------------------------------------------------------

create table public.phone_identity_change_grants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null,
  target_digits text not null
    constraint phone_identity_change_grants_uae check (target_digits ~ '^9715[0-9]{8}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.phone_identity_change_grants enable row level security;
revoke all on public.phone_identity_change_grants from public, anon, authenticated, service_role;

create function public.guard_auth_phone_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_new_phone text := public.phone_digits(new.phone);
  v_old_phone text := case when tg_op = 'UPDATE' then public.phone_digits(old.phone) else '' end;
  v_new_change text := coalesce(new.phone_change, '');
  v_old_change text := case when tg_op = 'UPDATE' then coalesce(old.phone_change, '') else '' end;
  v_method text;
begin
  if tg_op = 'INSERT' then
    -- An account holds a sign-in number only when it is created by phone.
    if v_new_phone <> '' and coalesce(new.email, '') <> '' then
      raise exception using errcode = 'P0001', message = 'phone_identity_not_allowed';
    end if;
    if v_new_change <> '' then
      raise exception using errcode = 'P0001', message = 'phone_change_not_allowed';
    end if;
    if v_new_phone <> '' then
      -- One number, one account: serialized with contact-number confirmation.
      perform pg_advisory_xact_lock(hashtextextended('bw.phone:' || v_new_phone, 0));
      if public.phone_number_is_held(v_new_phone, new.id) then
        raise exception using errcode = 'P0001', message = 'phone_unavailable';
      end if;
    end if;
    return new;
  end if;

  -- Self-service phone change is never accepted (its confirmation is not
  -- bound to the account's session): neither a new pending number nor a
  -- resend for an existing one. Clearing a pending change, and full-row
  -- re-saves that leave it untouched, pass.
  if v_new_change <> '' and (
       v_new_change is distinct from v_old_change
       or new.phone_change_token is distinct from old.phone_change_token
       or new.phone_change_sent_at is distinct from old.phone_change_sent_at) then
    raise exception using errcode = 'P0001', message = 'phone_change_not_allowed';
  end if;

  if v_new_phone is distinct from v_old_phone then
    select m.primary_method into v_method
      from public.account_sign_in_methods m
     where m.user_id = new.id;
    if coalesce(v_method, public.sign_in_method_for(old.email, old.phone)) <> 'phone' then
      raise exception using errcode = 'P0001', message = 'phone_identity_not_allowed';
    end if;
    if v_new_phone = '' then
      raise exception using errcode = 'P0001', message = 'phone_identity_required';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('bw.phone:' || v_new_phone, 0));
    if public.phone_number_is_held(v_new_phone, new.id) then
      raise exception using errcode = 'P0001', message = 'phone_unavailable';
    end if;
    update public.phone_identity_change_grants g
       set consumed_at = now()
     where g.user_id = new.id
       and g.target_digits = v_new_phone
       and g.consumed_at is null
       and g.expires_at > now();
    if not found then
      raise exception using errcode = 'P0001', message = 'phone_change_not_authorized';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_auth_phone_identity() from public, anon, authenticated, service_role;

create trigger guard_auth_phone_identity
  before insert or update of phone, phone_change, phone_change_token, phone_change_sent_at on auth.users
  for each row execute function public.guard_auth_phone_identity();

-- ---------------------------------------------------------------------------
-- 4. Auth -> profile sync: phone fields mirror Supabase Auth only for
--    phone-primary accounts (email accounts keep their contact number)
-- ---------------------------------------------------------------------------

create or replace function public.sync_auth_identity_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_phone_primary boolean := coalesce(
    (select m.primary_method = 'phone' from public.account_sign_in_methods m where m.user_id = new.id),
    public.sign_in_method_for(new.email, new.phone) = 'phone'
  );
  -- Same projection as before Model X for phone-primary accounts.
  v_e164 text := case when coalesce(new.phone, '') ~ '^\+[1-9][0-9]{6,14}$' then new.phone else null end;
begin
  update public.profiles
  set
    email = nullif(new.email, '')::extensions.citext,
    is_email_verified = new.email_confirmed_at is not null,
    phone_number = case when v_phone_primary then nullif(new.phone, '') else phone_number end,
    phone_e164 = case when v_phone_primary then v_e164 else phone_e164 end,
    is_phone_verified = case when v_phone_primary then new.phone_confirmed_at is not null else is_phone_verified end
  where id = new.id
    and (
      email is distinct from nullif(new.email, '')::extensions.citext
      or is_email_verified is distinct from (new.email_confirmed_at is not null)
      or (v_phone_primary and (
        phone_number is distinct from nullif(new.phone, '')
        or phone_e164 is distinct from v_e164
        or is_phone_verified is distinct from (new.phone_confirmed_at is not null)
      ))
    );
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Worker-only verification records and functions (service_role only)
-- ---------------------------------------------------------------------------

create table public.phone_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  purpose text not null
    constraint phone_verifications_purpose check (purpose in ('contact', 'identity_change')),
  phone_e164 text not null
    constraint phone_verifications_uae check (phone_e164 ~ '^[+]9715[0-9]{8}$'),
  provider_ref text,
  attempts integer not null default 0
    constraint phone_verifications_attempts check (attempts between 0 and 5),
  status text not null default 'pending'
    constraint phone_verifications_status check (
      status in ('pending', 'verified', 'failed', 'superseded')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  -- identity_change only: when the Worker proved possession of the account's
  -- current sign-in number (or its password) for this record and session.
  current_proven_at timestamptz
);
create index phone_verifications_user_idx on public.phone_verifications (user_id, created_at desc);
alter table public.phone_verifications enable row level security;
revoke all on public.phone_verifications from public, anon, authenticated, service_role;

create function public.phone_verification_start(
  p_user uuid,
  p_session uuid,
  p_purpose text,
  p_phone text,
  p_ttl_seconds integer default 600
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_digits text := public.phone_digits(p_phone);
  v_method text;
  v_id uuid;
begin
  if p_user is null or p_session is null or p_purpose not in ('contact', 'identity_change')
     or v_digits !~ '^9715[0-9]{8}$' or p_ttl_seconds not between 60 and 900 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select m.primary_method into v_method from public.account_sign_in_methods m where m.user_id = p_user;
  if v_method is null
     or (p_purpose = 'contact' and v_method <> 'email')
     or (p_purpose = 'identity_change' and v_method <> 'phone') then
    raise exception using errcode = 'P0001', message = 'not_available_for_account';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bw.phone:' || v_digits, 0));
  if public.phone_number_is_held(v_digits, p_user) then
    raise exception using errcode = 'P0001', message = 'phone_unavailable';
  end if;
  if exists (select 1 from auth.users u where u.id = p_user and public.phone_digits(u.phone) = v_digits)
     or exists (select 1 from public.profiles p where p.id = p_user and p.phone_e164 = '+' || v_digits
                and p.is_phone_verified) then
    raise exception using errcode = 'P0001', message = 'phone_already_verified';
  end if;
  -- Server-side ceilings on started verifications (per account and per
  -- number), independent of the client and of the provider's own limits.
  if (select count(*) from public.phone_verifications v
       where v.user_id = p_user and v.created_at > now() - interval '1 hour') >= 5
     or (select count(*) from public.phone_verifications v
          where v.phone_e164 = '+' || v_digits and v.created_at > now() - interval '1 hour') >= 5 then
    raise exception using errcode = 'P0001', message = 'too_many_requests';
  end if;
  update public.phone_verifications v
     set status = 'superseded', completed_at = now()
   where v.user_id = p_user and v.purpose = p_purpose and v.status = 'pending';
  insert into public.phone_verifications (user_id, session_id, purpose, phone_e164, expires_at)
  values (p_user, p_session, p_purpose, '+' || v_digits, now() + make_interval(secs => p_ttl_seconds))
  returning id into v_id;
  return v_id;
end;
$function$;

create function public.phone_verification_attach(p_id uuid, p_user uuid, p_provider_ref text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.phone_verifications v
     set provider_ref = p_provider_ref
   where v.id = p_id and v.user_id = p_user and v.status = 'pending' and v.provider_ref is null;
  return found;
end;
$function$;

create function public.phone_verification_fail(p_id uuid, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.phone_verifications v
     set status = 'failed', completed_at = now()
   where v.id = p_id and v.user_id = p_user and v.status = 'pending';
  return found;
end;
$function$;

-- Counts one code attempt for a verification of this user and this session
-- and returns what the Worker needs to ask the provider. Outcomes that change
-- the record (expiry, attempt cap) are returned, not raised, so the change is
-- kept: result is 'ok', 'already_verified', 'verification_expired' or
-- 'too_many_attempts'. Unknown records and other sessions raise.
create function public.phone_verification_attempt(p_id uuid, p_user uuid, p_session uuid)
returns table (result text, phone_e164 text, provider_ref text, purpose text, current_proven boolean)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v public.phone_verifications%rowtype;
begin
  select * into v from public.phone_verifications x where x.id = p_id for update;
  if not found or v.user_id is distinct from p_user then
    raise exception using errcode = 'P0001', message = 'verification_not_found';
  end if;
  if v.session_id is distinct from p_session then
    raise exception using errcode = 'P0001', message = 'session_mismatch';
  end if;
  -- A contact verification this session already completed: a retried
  -- confirmation after a lost response, answered without a new code.
  if v.status = 'verified' and v.purpose = 'contact' then
    return query select 'already_verified'::text, v.phone_e164, null::text, v.purpose, false;
    return;
  end if;
  if v.status <> 'pending' or v.provider_ref is null then
    raise exception using errcode = 'P0001', message = 'verification_not_found';
  end if;
  if v.expires_at <= now() then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return query select 'verification_expired'::text, null::text, null::text, v.purpose, false;
    return;
  end if;
  if v.attempts >= 5 then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return query select 'too_many_attempts'::text, null::text, null::text, v.purpose, false;
    return;
  end if;
  update public.phone_verifications x set attempts = x.attempts + 1 where x.id = p_id;
  return query select 'ok'::text, v.phone_e164, v.provider_ref, v.purpose, v.current_proven_at is not null;
end;
$function$;

-- After the provider approved the code: stores the contact number of an
-- email account. Returns 'verified' (also for a repeated call),
-- 'phone_unavailable' or 'verification_expired'.
create function public.contact_phone_confirm(p_id uuid, p_user uuid, p_session uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v public.phone_verifications%rowtype;
begin
  select * into v from public.phone_verifications x where x.id = p_id for update;
  if not found or v.user_id is distinct from p_user or v.purpose <> 'contact' then
    raise exception using errcode = 'P0001', message = 'verification_not_found';
  end if;
  if v.session_id is distinct from p_session then
    raise exception using errcode = 'P0001', message = 'session_mismatch';
  end if;
  if v.status = 'verified' then
    return 'verified';
  end if;
  if v.status <> 'pending' then
    return 'verification_expired';
  end if;
  if v.expires_at <= now() then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return 'verification_expired';
  end if;
  if not exists (select 1 from public.account_sign_in_methods m
                  where m.user_id = p_user and m.primary_method = 'email') then
    raise exception using errcode = 'P0001', message = 'not_available_for_account';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bw.phone:' || public.phone_digits(v.phone_e164), 0));
  if public.phone_number_is_held(v.phone_e164, p_user) then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return 'phone_unavailable';
  end if;
  update public.profiles p
     set phone_number = v.phone_e164,
         phone_e164 = v.phone_e164,
         is_phone_verified = true
   where p.id = p_user;
  if not found then
    raise exception using errcode = 'P0001', message = 'verification_not_found';
  end if;
  update public.phone_verifications x
     set status = 'verified', completed_at = now()
   where x.id = p_id;
  return 'verified';
end;
$function$;

-- Records that the Worker proved possession of the account's current sign-in
-- number (a Supabase sign-in code checked server-side, its session revoked)
-- or the account password, for this pending identity change and session.
-- Kept across code retries, so a mistyped new-number code does not spend the
-- current-number code again.
create function public.phone_identity_current_proven(p_id uuid, p_user uuid, p_session uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.phone_verifications v
     set current_proven_at = coalesce(v.current_proven_at, now())
   where v.id = p_id
     and v.user_id = p_user
     and v.session_id = p_session
     and v.purpose = 'identity_change'
     and v.status = 'pending'
     and v.expires_at > now();
  return found;
end;
$function$;

-- After the Worker re-verified a phone-primary account and the provider
-- approved the new number: a single-use grant, valid five minutes, that the
-- auth.users guard consumes when the Worker writes the number through the
-- Auth Admin API. Returns 'granted', 'phone_unavailable' or
-- 'verification_expired'.
create function public.phone_identity_change_grant(p_id uuid, p_user uuid, p_session uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v public.phone_verifications%rowtype;
begin
  select * into v from public.phone_verifications x where x.id = p_id for update;
  if not found or v.user_id is distinct from p_user or v.purpose <> 'identity_change' then
    raise exception using errcode = 'P0001', message = 'verification_not_found';
  end if;
  if v.session_id is distinct from p_session then
    raise exception using errcode = 'P0001', message = 'session_mismatch';
  end if;
  if v.status <> 'pending' then
    return 'verification_expired';
  end if;
  if v.expires_at <= now() then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return 'verification_expired';
  end if;
  if not exists (select 1 from public.account_sign_in_methods m
                  where m.user_id = p_user and m.primary_method = 'phone') then
    raise exception using errcode = 'P0001', message = 'not_available_for_account';
  end if;
  -- The current sign-in number (or password) must have been proven first.
  if v.current_proven_at is null then
    raise exception using errcode = 'P0001', message = 'current_number_not_proven';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bw.phone:' || public.phone_digits(v.phone_e164), 0));
  if public.phone_number_is_held(v.phone_e164, p_user) then
    update public.phone_verifications x set status = 'failed', completed_at = now() where x.id = p_id;
    return 'phone_unavailable';
  end if;
  insert into public.phone_identity_change_grants (user_id, session_id, target_digits, expires_at)
  values (p_user, p_session, public.phone_digits(v.phone_e164), now() + interval '5 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        target_digits = excluded.target_digits,
        expires_at = excluded.expires_at,
        consumed_at = null,
        created_at = now();
  update public.phone_verifications x
     set status = 'verified', completed_at = now()
   where x.id = p_id;
  return 'granted';
end;
$function$;

revoke all on function public.phone_verification_start(uuid, uuid, text, text, integer) from public, anon, authenticated, service_role;
revoke all on function public.phone_verification_attach(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.phone_verification_fail(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.phone_verification_attempt(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.contact_phone_confirm(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.phone_identity_change_grant(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.phone_identity_current_proven(uuid, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.phone_verification_start(uuid, uuid, text, text, integer) to service_role;
grant execute on function public.phone_verification_attach(uuid, uuid, text) to service_role;
grant execute on function public.phone_verification_fail(uuid, uuid) to service_role;
grant execute on function public.phone_verification_attempt(uuid, uuid, uuid) to service_role;
grant execute on function public.contact_phone_confirm(uuid, uuid, uuid) to service_role;
grant execute on function public.phone_identity_change_grant(uuid, uuid, uuid) to service_role;
grant execute on function public.phone_identity_current_proven(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 6. B1 phone sign-up policy: a number that already belongs to an account
--    (as a sign-in or contact number) cannot create another account
-- ---------------------------------------------------------------------------

create or replace function public.before_user_created_phone_policy(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_refused constant jsonb :=
    '{"error":{"http_code":403,"message":"phone_signup_not_allowed"}}'::jsonb;
  v_phone text := coalesce(event #>> '{user,phone}', '');
  v_e164 text;
  v_metadata jsonb;
  v_mode text;
begin
  -- Not a phone sign-up: never read a table, never refuse.
  if v_phone = '' then
    return '{}'::jsonb;
  end if;

  begin
    v_e164 := case when left(v_phone, 1) = '+' then v_phone else '+' || v_phone end;
    if v_e164 !~ '^[+]9715[0-9]{8}$' then
      return v_refused;
    end if;

    v_metadata := event #> '{user,user_metadata}';
    if v_metadata is not null
       and v_metadata <> 'null'::jsonb
       and v_metadata <> '{}'::jsonb then
      return v_refused;
    end if;

    -- One number, one account (Model X).
    if public.phone_number_is_held(v_e164, null) then
      return v_refused;
    end if;

    select p.mode into v_mode
      from public.phone_auth_policy p
     where p.singleton;

    if v_mode = 'open' then
      return '{}'::jsonb;
    end if;
    if v_mode = 'allowlist' and exists (
      select 1 from public.phone_auth_allowlist a where a.phone_e164 = v_e164
    ) then
      return '{}'::jsonb;
    end if;
    -- 'closed', a missing policy row or any other value.
    return v_refused;
  exception when others then
    return v_refused;
  end;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Re-apply after a rollback: restore the contact numbers the rollback kept,
--    where the number is still free. A number that now belongs to another
--    account stays in the backup (reported), and the backup is dropped only
--    when nothing is left in it.
-- ---------------------------------------------------------------------------

do $restore$
declare
  v_restored integer := 0;
  v_left integer;
  r record;
begin
  if to_regclass('public.model_x_rollback_backup') is null then
    return;
  end if;
  for r in
    select b.user_id, b.contact_phone_e164
      from public.model_x_rollback_backup b
      join public.account_sign_in_methods m on m.user_id = b.user_id and m.primary_method = 'email'
      join public.profiles p on p.id = b.user_id
     where b.contact_phone_e164 is not null
       and p.phone_e164 is null
     order by b.saved_at, b.user_id
  loop
    if not public.phone_number_is_held(r.contact_phone_e164, r.user_id) then
      update public.profiles
         set phone_number = r.contact_phone_e164,
             phone_e164 = r.contact_phone_e164,
             is_phone_verified = true
       where id = r.user_id;
      v_restored := v_restored + 1;
    end if;
  end loop;
  -- Rows whose data is now in place (or that hold no contact number) are done.
  delete from public.model_x_rollback_backup b
   using public.profiles p
   where p.id = b.user_id
     and (b.contact_phone_e164 is null or p.phone_e164 = b.contact_phone_e164);
  delete from public.model_x_rollback_backup b
   where not exists (select 1 from auth.users u where u.id = b.user_id);
  select count(*) into v_left from public.model_x_rollback_backup;
  if v_left = 0 then
    drop table public.model_x_rollback_backup;
  else
    raise notice 'model_x: % contact number(s) restored; % left in public.model_x_rollback_backup (number now held elsewhere)',
      v_restored, v_left;
  end if;
end;
$restore$;
