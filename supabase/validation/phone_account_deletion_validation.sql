-- SOURCE ONLY. Rollback-only validation of 20261122140000_phone_account_deletion.sql,
-- including 20261122120000 (B1) and 20261122130000 (Model X) first when they
-- are not applied yet. Run only with the owner's approval, as postgres, from
-- an LF copy:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/phone_account_deletion_validation.sql
-- ONE transaction that always ends in ROLLBACK. The synthetic accounts use
-- example.invalid addresses and fictional numbers (97150000xxxx) and exist only
-- inside this transaction. Nothing is called over the network.
-- Locks: as phone_identity_model_x_validation.sql when Model X is included
-- (auth.users trigger creation); otherwise only the new table.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.account_deletion_challenges') is not null
     or to_regprocedure('public.account_deletion_challenge_issue(uuid,uuid)') is not null
     or to_regprocedure('public.is_current_app_session()') is null then
    raise exception 'phone account deletion validation preflight failed';
  end if;
end;
$preflight$;

select to_regprocedure('public.before_user_created_phone_policy(jsonb)') is null as need_b1, to_regclass('public.account_sign_in_methods') is null as need_model_x \gset
\if :need_b1
\ir ../migrations/20261122120000_phone_signup_policy.sql
\endif
\if :need_model_x
\ir ../migrations/20261122130000_phone_identity_model_x.sql
\endif
\ir ../migrations/20261122140000_phone_account_deletion.sql

do $catalog$
declare
  v_role text;
  v_fn text;
begin
  foreach v_fn in array array[
    'public.account_deletion_challenge_issue(uuid,uuid)',
    'public.account_deletion_challenge_attempt(uuid,uuid)',
    'public.account_deletion_challenge_consume(uuid,uuid)'] loop
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute')
       or not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'execute grants on % are not service_role only', v_fn;
    end if;
  end loop;
  foreach v_role in array array['anon', 'authenticated', 'service_role'] loop
    if has_table_privilege(v_role, 'public.account_deletion_challenges', 'select,insert,update,delete,truncate') then
      raise exception '% can reach deletion challenges directly', v_role;
    end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid = 'public.account_deletion_challenges'::regclass) then
    raise exception 'RLS is off on account_deletion_challenges';
  end if;
end;
$catalog$;

do $behaviour$
declare
  v_email constant uuid := gen_random_uuid();
  v_phone constant uuid := gen_random_uuid();
  v_s1 constant uuid := gen_random_uuid();
  v_s2 constant uuid := gen_random_uuid();
  v_result text;
  v_used boolean;
begin
  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values (v_email, 'deletion-x@example.invalid', '{}'::jsonb, now(), now());
  insert into auth.users (id, phone, phone_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (v_phone, '971500000095', now(), '{}'::jsonb, now(), now());

  begin
    perform public.account_deletion_challenge_issue(v_email, v_s1);
    raise exception 'behaviour: an email account got a phone challenge';
  exception when raise_exception then
    if sqlerrm <> 'not_available_for_account' then raise; end if;
  end;

  v_result := public.account_deletion_challenge_issue(v_phone, v_s1);
  if v_result <> 'issued' then raise exception 'behaviour: no challenge issued'; end if;
  v_result := public.account_deletion_challenge_attempt(v_phone, v_s2);
  if v_result <> 'challenge_required' then raise exception 'behaviour: another session used the challenge'; end if;
  v_result := public.account_deletion_challenge_attempt(v_phone, v_s1);
  if v_result <> 'ok' then raise exception 'behaviour: the owning session could not try a code'; end if;
  v_used := public.account_deletion_challenge_consume(v_phone, v_s1);
  if not v_used then raise exception 'behaviour: the proof could not be used'; end if;
  v_used := public.account_deletion_challenge_consume(v_phone, v_s1);
  if v_used then raise exception 'behaviour: the proof was used twice'; end if;
end;
$behaviour$;

select 'phone_account_deletion_validation: PASS' as result;
rollback;
