-- Run only against a disposable database after applying the matching source
-- migration there. psql -X -v ON_ERROR_STOP=1 -f this-file.sql
-- Every synthetic row is discarded by the final ROLLBACK. Do not run hosted.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regprocedure('public.claim_current_app_session()') is null
     or exists (select 1 from auth.users where id in (
       'a5a50000-0000-4000-8000-00000000000a'::uuid,
       'a5a50000-0000-4000-8000-00000000000b'::uuid)) then
    raise exception 'single-active-session validation preflight failed';
  end if;
end;
$preflight$;

insert into auth.users(id, email, raw_user_meta_data, created_at, updated_at)
values
  ('a5a50000-0000-4000-8000-00000000000a', 'session-a@validation.invalid', '{"name":"A"}', now(), now()),
  ('a5a50000-0000-4000-8000-00000000000b', 'session-b@validation.invalid', '{"name":"B"}', now(), now());
insert into auth.sessions(id, user_id, created_at, updated_at)
values
  ('a5a50000-0000-4000-8000-000000000001', 'a5a50000-0000-4000-8000-00000000000a', now(), now()),
  ('a5a50000-0000-4000-8000-000000000002', 'a5a50000-0000-4000-8000-00000000000a', now(), now()),
  ('a5a50000-0000-4000-8000-000000000003', 'a5a50000-0000-4000-8000-00000000000a', now(), now()),
  ('a5a50000-0000-4000-8000-000000000004', 'a5a50000-0000-4000-8000-00000000000b', now(), now());

set local role anon;
do $anon$
begin
  begin
    perform public.claim_current_app_session();
    raise exception 'anon claim unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$anon$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5a50000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims', '{"sub":"a5a50000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"a5a50000-0000-4000-8000-000000000001"}', true);
do $first$
begin
  if not public.claim_current_app_session() or not public.claim_current_app_session()
     or not public.is_current_app_session() then
    raise exception 'first or idempotent claim failed';
  end if;
  insert into public.requests(id, owner_id, request_type, status, min_price, max_price)
  values ('a5a50000-0000-4000-8000-000000000010',
          'a5a50000-0000-4000-8000-00000000000a', 'rent', 'active', 1000, 2000);
end;
$first$;

select set_config('request.jwt.claims', '{"sub":"a5a50000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"a5a50000-0000-4000-8000-000000000002"}', true);
do $second$
begin
  if not public.claim_current_app_session() or not public.is_current_app_session()
     or (select count(*) from public.requests where owner_id = auth.uid()) <> 1 then
    raise exception 'second session did not take over or lost owner data';
  end if;
end;
$second$;

select set_config('request.jwt.claims', '{"sub":"a5a50000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"a5a50000-0000-4000-8000-000000000001"}', true);
do $old$
begin
  if public.is_current_app_session()
     or public.release_current_app_session()
     or (select count(*) from public.requests where owner_id = auth.uid()) <> 0 then
    raise exception 'old session retained data or release authority';
  end if;
  begin
    perform public.claim_current_app_session();
    raise exception 'old session reclaimed';
  exception when insufficient_privilege then
    if sqlerrm <> 'session_superseded' then raise; end if;
  end;
  begin
    update public.user_active_sessions set active_session_id =
      'a5a50000-0000-4000-8000-000000000001' where user_id = auth.uid();
    raise exception 'client direct update succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$old$;

select set_config('request.jwt.claims', '{"sub":"a5a50000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"a5a50000-0000-4000-8000-000000000003"}', true);
do $third$
begin
  if not public.claim_current_app_session() or not public.is_current_app_session() then
    raise exception 'third session failed to take over';
  end if;
end;
$third$;

select set_config('request.jwt.claim.sub', 'a5a50000-0000-4000-8000-00000000000b', true);
select set_config('request.jwt.claims', '{"sub":"a5a50000-0000-4000-8000-00000000000b","role":"authenticated","session_id":"a5a50000-0000-4000-8000-000000000004"}', true);
do $other$
begin
  if (select count(*) from public.user_active_sessions) <> 0 then
    raise exception 'user B read user A active state';
  end if;
end;
$other$;

reset role;
do $catalog$
begin
  if (select count(*) from public.app_session_claims where user_id =
       'a5a50000-0000-4000-8000-00000000000a') <> 3
     or (select active_session_id from public.user_active_sessions where user_id =
       'a5a50000-0000-4000-8000-00000000000a') <>
       'a5a50000-0000-4000-8000-000000000003'::uuid
     or not exists (select 1 from pg_publication_tables where pubname =
       'supabase_realtime' and schemaname = 'public' and tablename = 'user_active_sessions') then
    raise exception 'claim history, latest winner or publication wrong';
  end if;
end;
$catalog$;
delete from auth.users where id = 'a5a50000-0000-4000-8000-00000000000a';
do $cascade$
begin
  if exists (select 1 from public.user_active_sessions where user_id =
       'a5a50000-0000-4000-8000-00000000000a')
     or exists (select 1 from public.app_session_claims where user_id =
       'a5a50000-0000-4000-8000-00000000000a') then
    raise exception 'account deletion did not clean session control state';
  end if;
end;
$cascade$;
rollback;
