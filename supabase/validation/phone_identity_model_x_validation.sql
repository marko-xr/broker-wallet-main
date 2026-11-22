-- SOURCE ONLY. Rollback-only validation of 20261122130000_phone_identity_model_x.sql
-- (and of 20261122120000_phone_signup_policy.sql first, when B1 is not applied
-- yet). Run only with the owner's approval, as postgres, from an LF copy:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_identity_model_x_validation.sql
-- Everything runs in ONE transaction that always ends in ROLLBACK: nothing is
-- created or kept, no Auth setting or hook is touched, nothing is called over
-- the network. The synthetic accounts use example.invalid addresses and
-- fictional numbers in the UAE mobile shape (97150000xxxx), and exist only
-- inside this transaction.
--
-- Locks: creating triggers on auth.users takes a SHARE ROW EXCLUSIVE lock on
-- it until the ROLLBACK, so Supabase Auth writes (sign-ins, refreshes) wait
-- for the few hundred milliseconds this script runs. lock_timeout stops the
-- script instead of queueing behind a long Auth transaction.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.account_sign_in_methods') is not null
     or to_regclass('public.phone_verifications') is not null
     or to_regclass('public.phone_identity_change_grants') is not null
     or to_regprocedure('public.guard_auth_phone_identity()') is not null
     or to_regprocedure('public.sync_auth_identity_to_profile()') is null
     or to_regprocedure('public.is_current_app_session()') is null
     or (select count(*) from information_schema.columns
          where table_schema = 'auth' and table_name = 'users'
            and column_name in ('phone', 'phone_change', 'phone_change_token', 'phone_change_sent_at')) <> 4 then
    raise exception 'phone identity model x validation preflight failed';
  end if;
end;
$preflight$;

select to_regprocedure('public.before_user_created_phone_policy(jsonb)') is null as need_b1 \gset
\if :need_b1
\ir ../migrations/20261122120000_phone_signup_policy.sql
\endif
\ir ../migrations/20261122130000_phone_identity_model_x.sql

do $catalog$
declare
  v_role text;
  v_fn text;
begin
  if (select count(*) from pg_trigger
       where tgrelid = 'auth.users'::regclass
         and tgname in ('guard_auth_phone_identity', 'on_auth_user_sign_in_method')
         and tgenabled = 'O') <> 2 then
    raise exception 'the two Model X triggers on auth.users are not installed and enabled';
  end if;
  foreach v_fn in array array[
    'public.phone_verification_start(uuid,uuid,text,text,integer)',
    'public.phone_verification_attach(uuid,uuid,text)',
    'public.phone_verification_fail(uuid,uuid)',
    'public.phone_verification_attempt(uuid,uuid,uuid)',
    'public.contact_phone_confirm(uuid,uuid,uuid)',
    'public.phone_identity_change_grant(uuid,uuid,uuid)',
    'public.phone_identity_current_proven(uuid,uuid,uuid)'] loop
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute')
       or not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'execute grants on % are not service_role only', v_fn;
    end if;
  end loop;
  foreach v_fn in array array[
    'public.phone_number_is_held(text,uuid)', 'public.guard_auth_phone_identity()',
    'public.record_account_sign_in_method()', 'public.phone_digits(text)', 'public.sign_in_method_for(text,text)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'clients can execute %', v_fn;
    end if;
  end loop;
  foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(v_role, 'public.phone_verifications', 'select,insert,update,delete,truncate')
       or has_table_privilege(v_role, 'public.phone_identity_change_grants', 'select,insert,update,delete,truncate')
       or has_table_privilege(v_role, 'public.account_sign_in_methods', 'insert,update,delete,truncate') then
      raise exception '% can reach Model X records directly', v_role;
    end if;
  end loop;
  if not has_table_privilege('authenticated', 'public.account_sign_in_methods', 'select')
     or has_table_privilege('anon', 'public.account_sign_in_methods', 'select')
     or (select count(*) from pg_policies
          where schemaname = 'public' and tablename = 'account_sign_in_methods'
            and ((policyname = 'app_session_gate' and permissive = 'RESTRICTIVE')
              or (policyname = 'account_sign_in_methods_select_own' and cmd = 'SELECT'))) <> 2
     or not (select bool_and(relrowsecurity) from pg_class
              where oid in ('public.account_sign_in_methods'::regclass, 'public.phone_verifications'::regclass,
                            'public.phone_identity_change_grants'::regclass)) then
    raise exception 'RLS on the Model X tables is not as designed';
  end if;
  if (select count(*) from public.account_sign_in_methods) <> (select count(*) from auth.users)
     or exists (select 1 from auth.users u join public.account_sign_in_methods m on m.user_id = u.id
                 where m.primary_method <> public.sign_in_method_for(u.email, u.phone)) then
    raise exception 'the sign-in method backfill does not cover every account exactly';
  end if;
  if exists (select 1 from auth.users where coalesce(phone_change, '') <> '') then
    raise exception 'a pending self-service phone change survived';
  end if;
end;
$catalog$;

do $behaviour$
declare
  -- Synthetic accounts, visible only inside this transaction.
  v_email constant uuid := gen_random_uuid();
  v_other constant uuid := gen_random_uuid();
  v_phone constant uuid := gen_random_uuid();
  v_session constant uuid := gen_random_uuid();
  v_contact constant text := '+971500000091';
  v_old constant text := '971500000092';
  v_new constant text := '+971500000093';
  v_id uuid;
  v_result text;
  v_profile_phone_before text;
  r record;
begin
  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values (v_email, 'model-x-a@example.invalid', '{}'::jsonb, now(), now()),
         (v_other, 'model-x-b@example.invalid', '{}'::jsonb, now(), now());
  insert into auth.users (id, phone, phone_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (v_phone, v_old, now(), '{}'::jsonb, now(), now());
  if (select primary_method from public.account_sign_in_methods where user_id = v_email) <> 'email'
     or (select primary_method from public.account_sign_in_methods where user_id = v_phone) <> 'phone' then
    raise exception 'behaviour: sign-in methods are not recorded at creation';
  end if;

  begin
    update auth.users set phone = '971500000094' where id = v_email;
    raise exception 'behaviour: an email account received a sign-in number';
  exception when raise_exception then
    if sqlerrm <> 'phone_identity_not_allowed' then raise; end if;
  end;
  begin
    update auth.users set phone_change = '971500000094', phone_change_token = 't', phone_change_sent_at = now()
     where id = v_email;
    raise exception 'behaviour: a self-service phone change started';
  exception when raise_exception then
    if sqlerrm <> 'phone_change_not_allowed' then raise; end if;
  end;

  -- Contact number of the email account.
  v_id := public.phone_verification_start(v_email, v_session, 'contact', v_contact);
  if not public.phone_verification_attach(v_id, v_email, 'validation-ref') then
    raise exception 'behaviour: provider reference not stored';
  end if;
  select * into r from public.phone_verification_attempt(v_id, v_email, v_session);
  if r.result <> 'ok' or r.provider_ref <> 'validation-ref' then
    raise exception 'behaviour: attempt did not return the provider reference';
  end if;
  -- Separate statements: one expression would read the profile from the
  -- snapshot taken before the confirmation wrote it.
  v_result := public.contact_phone_confirm(v_id, v_email, v_session);
  if v_result <> 'verified'
     or (select phone_e164 from public.profiles where id = v_email) is distinct from v_contact
     or (select coalesce(phone, '') from auth.users where id = v_email) <> '' then
    raise exception 'behaviour: the contact number was not stored as a contact number only';
  end if;
  v_profile_phone_before := (select phone_e164 from public.profiles where id = v_email);
  update auth.users set email_confirmed_at = now() where id = v_email;
  if (select phone_e164 from public.profiles where id = v_email) is distinct from v_profile_phone_before then
    raise exception 'behaviour: the identity sync overwrote a contact number';
  end if;
  begin
    perform public.phone_verification_start(v_other, gen_random_uuid(), 'contact', v_contact);
    raise exception 'behaviour: a second account claimed a contact number';
  exception when raise_exception then
    if sqlerrm <> 'phone_unavailable' then raise; end if;
  end;
  if public.before_user_created_phone_policy(jsonb_build_object('user', jsonb_build_object('phone', ltrim(v_contact, '+'))))
       -> 'error' ->> 'message' is distinct from 'phone_signup_not_allowed' then
    raise exception 'behaviour: the sign-up hook accepted a contact number';
  end if;

  -- Sign-in number change of the phone account.
  begin
    update auth.users set phone = ltrim(v_new, '+') where id = v_phone;
    raise exception 'behaviour: a number change passed without a grant';
  exception when raise_exception then
    if sqlerrm <> 'phone_change_not_authorized' then raise; end if;
  end;
  v_id := public.phone_verification_start(v_phone, v_session, 'identity_change', v_new);
  if not public.phone_identity_current_proven(v_id, v_phone, v_session) then
    raise exception 'behaviour: current-number proof not recorded';
  end if;
  v_result := public.phone_identity_change_grant(v_id, v_phone, v_session);
  if v_result <> 'granted' then
    raise exception 'behaviour: no grant issued';
  end if;
  update auth.users set phone = ltrim(v_new, '+'), phone_confirmed_at = now() where id = v_phone;
  begin
    update auth.users set phone = v_old where id = v_phone;
    raise exception 'behaviour: a consumed grant was replayed';
  exception when raise_exception then
    if sqlerrm <> 'phone_change_not_authorized' then raise; end if;
  end;
end;
$behaviour$;

select 'phone_identity_model_x_validation: PASS' as result;
rollback;
