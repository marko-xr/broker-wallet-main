-- Keep the public profile identity projection aligned with Supabase Auth.
-- The baseline creation trigger handles INSERTs; this migration handles later
-- email/phone confirmation and identity updates, and repairs existing drift.

begin;

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

revoke all on function public.sync_auth_identity_to_profile() from public;
revoke all on function public.sync_auth_identity_to_profile() from anon;
revoke all on function public.sync_auth_identity_to_profile() from authenticated;

drop trigger if exists on_auth_user_identity_updated on auth.users;
create trigger on_auth_user_identity_updated
  after update of email, phone, email_confirmed_at, phone_confirmed_at on auth.users
  for each row execute function public.sync_auth_identity_to_profile();

-- Repair profiles that were confirmed or otherwise changed before this trigger existed.
update public.profiles p
set
  email = nullif(u.email, '')::extensions.citext,
  phone_number = nullif(u.phone, ''),
  phone_e164 = case
    when coalesce(u.phone, '') ~ '^\+[1-9][0-9]{6,14}$' then u.phone
    else null
  end,
  is_email_verified = u.email_confirmed_at is not null,
  is_phone_verified = u.phone_confirmed_at is not null
from auth.users u
where p.id = u.id
  and (
    p.email is distinct from nullif(u.email, '')::extensions.citext
    or p.phone_number is distinct from nullif(u.phone, '')
    or p.phone_e164 is distinct from case
      when coalesce(u.phone, '') ~ '^\+[1-9][0-9]{6,14}$' then u.phone
      else null
    end
    or p.is_email_verified is distinct from (u.email_confirmed_at is not null)
    or p.is_phone_verified is distinct from (u.phone_confirmed_at is not null)
  );

commit;
