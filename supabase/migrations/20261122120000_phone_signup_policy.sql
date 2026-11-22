-- Phone Auth B1: server-side policy for creating accounts by phone.
--
-- What it is: a Supabase Auth "Before User Created" Postgres hook function and
-- the two tables it reads. Supabase Auth calls the hook before it inserts a new
-- auth.users row (and before any SMS is sent for a new phone sign-up). The hook
-- only answers; it never writes.
--
-- Policy for accounts created with a phone number:
--   * only UAE mobile numbers, +9715XXXXXXXX (Supabase Auth may store the
--     number without the leading '+', so both spellings are accepted);
--   * no user metadata at creation (a name chosen by whoever first requested a
--     code must never reach the real owner's profile);
--   * mode 'closed' (default) refuses every phone sign-up, 'allowlist' accepts
--     only listed numbers, 'open' accepts every UAE mobile number.
-- Every refusal returns the same fixed error, so the response reveals nothing
-- about the mode or the allowlist. Any unexpected error refuses a phone sign-up.
--
-- Sign-ups without a phone (email, OAuth, anonymous) return '{}' before any
-- table is read, so nothing in this file can affect them.
--
-- THIS CHECKPOINT DOES NOT ENABLE THE HOOK. It takes effect only when the
-- function is selected in Supabase Dashboard -> Authentication -> Hooks, which
-- is a separate, owner-approved step. The mode is changed by the owner with SQL
-- as postgres (the table owner); clients have no access at all.
--
-- Following Supabase's guidance for Postgres hooks, the function is SECURITY
-- INVOKER and supabase_auth_admin gets explicit, read-only access (it has no
-- BYPASSRLS, hence the SELECT policies).
--
-- Additive only: no existing table, function, trigger, policy or grant is
-- changed. No BEGIN/COMMIT: applied by the reviewed single-transaction apply
-- and included by the rollback-only validation.

create table public.phone_auth_policy (
  singleton boolean primary key default true
    constraint phone_auth_policy_singleton check (singleton),
  mode text not null default 'closed'
    constraint phone_auth_policy_mode check (mode in ('closed', 'allowlist', 'open')),
  updated_at timestamptz not null default now()
);

insert into public.phone_auth_policy (singleton, mode) values (true, 'closed');

alter table public.phone_auth_policy enable row level security;
revoke all on public.phone_auth_policy from public, anon, authenticated, service_role;
grant select on public.phone_auth_policy to supabase_auth_admin;
create policy phone_auth_policy_auth_admin_read on public.phone_auth_policy
  for select to supabase_auth_admin using (true);

create table public.phone_auth_allowlist (
  phone_e164 text primary key
    constraint phone_auth_allowlist_uae_mobile check (phone_e164 ~ '^[+]9715[0-9]{8}$'),
  created_at timestamptz not null default now()
);

alter table public.phone_auth_allowlist enable row level security;
revoke all on public.phone_auth_allowlist from public, anon, authenticated, service_role;
grant select on public.phone_auth_allowlist to supabase_auth_admin;
create policy phone_auth_allowlist_auth_admin_read on public.phone_auth_allowlist
  for select to supabase_auth_admin using (true);

create function public.before_user_created_phone_policy(event jsonb)
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

revoke all on function public.before_user_created_phone_policy(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.before_user_created_phone_policy(jsonb)
  to supabase_auth_admin;
