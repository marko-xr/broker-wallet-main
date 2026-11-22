-- SOURCE ONLY. Reverses 20261122130000_phone_identity_model_x.sql. Run only
-- with the owner's approval, as postgres, from an LF copy of this file:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_identity_model_x_rollback.sql
--
-- What it restores, byte for byte from the earlier migrations:
--   * public.sync_auth_identity_to_profile() as in 20260822000400;
--   * public.before_user_created_phone_policy(jsonb) as in 20261122120000 (B1).
-- What it removes: the two Model X triggers on auth.users, the Model X
-- functions and the three Model X tables (sign-in methods, verification
-- records, identity change grants).
--
-- Data kept (C4): before anything is dropped, every account's sign-in method
-- and every email account's verified contact number are copied into
-- public.model_x_rollback_backup (RLS on, no client or service-role access,
-- rows removed with their account). The restored sync clears an email
-- account's contact number from public.profiles at its next Auth identity
-- update; re-applying 20261122130000 restores it from the backup when the
-- number is still free, and recognises phone accounts that added an email.
--
-- What it cannot undo:
--   * pending self-service phone changes cleared when Model X was applied
--     (abandoned by design; nothing to restore).
-- After a rollback the old self-service phone change (F-AP-1) is reachable
-- again whenever SMS delivery works: keep the Phone provider off.
--
-- If the migration was applied with `supabase db push`, its history entry is
-- corrected afterwards as a separate owner step:
--   supabase migration repair --status reverted 20261122130000
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.account_sign_in_methods') is null
     or to_regclass('public.phone_verifications') is null
     or to_regclass('public.phone_identity_change_grants') is null
     or to_regprocedure('public.guard_auth_phone_identity()') is null
     or to_regprocedure('public.before_user_created_phone_policy(jsonb)') is null then
    raise exception 'phone identity model x rollback preflight failed: objects not present';
  end if;
  if to_regclass('public.account_deletion_challenges') is not null then
    raise exception 'phone identity model x rollback preflight failed: roll back 20261122140000 first';
  end if;
end;
$preflight$;

create table if not exists public.model_x_rollback_backup (
  user_id uuid primary key references auth.users(id) on delete cascade,
  primary_method text not null
    constraint model_x_rollback_backup_method check (primary_method in ('email', 'phone')),
  contact_phone_e164 text
    constraint model_x_rollback_backup_uae check (contact_phone_e164 ~ '^[+]9715[0-9]{8}$'),
  saved_at timestamptz not null default now()
);
alter table public.model_x_rollback_backup enable row level security;
revoke all on public.model_x_rollback_backup from public, anon, authenticated, service_role;

insert into public.model_x_rollback_backup (user_id, primary_method, contact_phone_e164)
select m.user_id,
       m.primary_method,
       case when m.primary_method = 'email' and p.is_phone_verified
                 and p.phone_e164 ~ '^[+]9715[0-9]{8}$'
            then p.phone_e164 end
  from public.account_sign_in_methods m
  left join public.profiles p on p.id = m.user_id
on conflict (user_id) do update
  set primary_method = excluded.primary_method,
      contact_phone_e164 = excluded.contact_phone_e164,
      saved_at = now();

drop trigger guard_auth_phone_identity on auth.users;
drop trigger on_auth_user_sign_in_method on auth.users;

create or replace function public.sync_auth_identity_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set
    email = nullif(new.email, '')::extensions.citext,
    phone_number = nullif(new.phone, ''),
    phone_e164 = case
      when coalesce(new.phone, '') ~ '^\+[1-9][0-9]{6,14}$' then new.phone
      else null
    end,
    is_email_verified = new.email_confirmed_at is not null,
    is_phone_verified = new.phone_confirmed_at is not null
  where id = new.id
    and (
      email is distinct from nullif(new.email, '')::extensions.citext
      or phone_number is distinct from nullif(new.phone, '')
      or phone_e164 is distinct from case
        when coalesce(new.phone, '') ~ '^\+[1-9][0-9]{6,14}$' then new.phone
        else null
      end
      or is_email_verified is distinct from (new.email_confirmed_at is not null)
      or is_phone_verified is distinct from (new.phone_confirmed_at is not null)
    );

  return new;
end;
$$;

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

drop function public.phone_identity_change_grant(uuid, uuid, uuid);
drop function public.phone_identity_current_proven(uuid, uuid, uuid);
drop function public.contact_phone_confirm(uuid, uuid, uuid);
drop function public.phone_verification_attempt(uuid, uuid, uuid);
drop function public.phone_verification_fail(uuid, uuid);
drop function public.phone_verification_attach(uuid, uuid, text);
drop function public.phone_verification_start(uuid, uuid, text, text, integer);
drop function public.guard_auth_phone_identity();
drop function public.record_account_sign_in_method();
drop function public.phone_number_is_held(text, uuid);
drop function public.phone_digits(text);
drop function public.sign_in_method_for(text, text);
drop table public.phone_verifications;
drop table public.phone_identity_change_grants;
drop table public.account_sign_in_methods;

do $postflight$
begin
  if to_regclass('public.account_sign_in_methods') is not null
     or to_regclass('public.phone_verifications') is not null
     or to_regclass('public.phone_identity_change_grants') is not null
     or exists (select 1 from pg_trigger
                 where tgrelid = 'auth.users'::regclass
                   and tgname in ('guard_auth_phone_identity', 'on_auth_user_sign_in_method'))
     or exists (select 1 from pg_proc
                 where pronamespace = 'public'::regnamespace
                   and proname in ('phone_identity_change_grant', 'phone_identity_current_proven', 'contact_phone_confirm',
                     'phone_verification_attempt', 'phone_verification_fail', 'phone_verification_attach',
                     'phone_verification_start', 'guard_auth_phone_identity', 'record_account_sign_in_method',
                     'phone_number_is_held', 'phone_digits', 'sign_in_method_for'))
     or to_regprocedure('public.before_user_created_phone_policy(jsonb)') is null
     or to_regclass('public.model_x_rollback_backup') is null then
    raise exception 'phone identity model x rollback postflight failed';
  end if;
end;
$postflight$;

select 'phone_identity_model_x_rollback: DONE' as result;
commit;
