-- Offer media confirm: the service-role-only function attaches an upload and
-- marks it ready in one step, enforces the per-Offer limit per bucket, puts a
-- new item at the end, is idempotent, and refuses anything not owned, not
-- live, not in the given bucket or outside the Offer's object-key prefix.
--
-- Run with `supabase test db` against the local stack. Writes run as postgres
-- here, standing in for the Worker's service_role calls.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(26);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('0ffe0000-0000-4000-8000-00000000000a', 'offer-media-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('0ffe0000-0000-4000-8000-00000000000b', 'offer-media-b@example.test', '{"name":"B"}'::jsonb, now(), now());

insert into public.offers (id, owner_id, offer_type, deleted_at)
values
  ('0ffe0000-0000-4000-8000-0000000000a1', '0ffe0000-0000-4000-8000-00000000000a', 'rent', null),
  ('0ffe0000-0000-4000-8000-0000000000a2', '0ffe0000-0000-4000-8000-00000000000a', 'sell', null),
  ('0ffe0000-0000-4000-8000-0000000000a3', '0ffe0000-0000-4000-8000-00000000000a', 'rent', null),
  ('0ffe0000-0000-4000-8000-0000000000a4', '0ffe0000-0000-4000-8000-00000000000a', 'rent', now()),
  ('0ffe0000-0000-4000-8000-0000000000b1', '0ffe0000-0000-4000-8000-00000000000b', 'rent', null);

-- A pending upload row, keyed the way the Worker keys Offer media.
create function pg_temp.pending(
  p_owner uuid,
  p_offer uuid,
  p_bucket text default 'test-bucket',
  p_key_owner uuid default null,
  p_status public.media_status default 'pending_upload'
) returns uuid
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
  values (
    v_id, p_owner, p_bucket,
    'profiles/' || coalesce(p_key_owner, p_owner) || '/offers/' || p_offer || '/' || v_id || '.jpg',
    'image', 'image/jpeg', 64, p_status);
  return v_id;
end;
$$;

create function pg_temp.confirm(
  p_user uuid, p_offer uuid, p_media uuid,
  p_bucket text default 'test-bucket', p_duration bigint default null
) returns text
language sql as $$
  select c.outcome || ':' || coalesce(c.media_ordinal::text, '-')
  from public.confirm_offer_media_upload(p_user, p_offer, p_media, p_bucket, 10, 64, 'image/jpeg', p_duration) as c;
$$;

-- ---------------------------------------------------------------------------
-- The function and who may execute it
-- ---------------------------------------------------------------------------

select has_function('public', 'confirm_offer_media_upload',
  array['uuid', 'uuid', 'uuid', 'text', 'integer', 'bigint', 'text', 'bigint'],
  'confirm_offer_media_upload exists with the Worker''s signature');
select ok((select prosecdef from pg_proc
           where oid = 'public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)'::regprocedure),
  'it is SECURITY DEFINER');
select ok((select array_to_string(proconfig, ',') like 'search_path=%' from pg_proc
           where oid = 'public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)'::regprocedure),
  'it runs with a fixed search_path');
select ok(not has_function_privilege('anon',
  'public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)', 'EXECUTE'),
  'anon cannot execute it');
select ok(not has_function_privilege('authenticated',
  'public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)', 'EXECUTE'),
  'authenticated cannot execute it');
select ok(has_function_privilege('service_role',
  'public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)', 'EXECUTE'),
  'service_role can execute it');

-- ---------------------------------------------------------------------------
-- Attach, retry, append order
-- ---------------------------------------------------------------------------

create temp table m (name text primary key, id uuid not null);
insert into m values
  ('one', pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1')),
  ('two', pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1')),
  ('three', pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1')),
  ('four', pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1'));

select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'one')),
  'attached:0', 'the first item is attached at position 0');
select is((select status::text from public.media_objects where id = (select id from m where name = 'one')),
  'ready', 'and marked ready in the same call');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'one')),
  'already_attached:0', 'a retried confirm reports already_attached');
select is((select count(*)::int from public.offer_media where media_id = (select id from m where name = 'one')),
  1, 'and adds no second link');

select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'two')),
  'attached:1', 'the second item goes to position 1');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'three')),
  'attached:2', 'the third to position 2');

-- What the Worker's removal does: pending_delete, then unlink.
update public.media_objects set status = 'pending_delete', deleted_at = now()
where id = (select id from m where name = 'two');
delete from public.offer_media where media_id = (select id from m where name = 'two');

select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'four'), 'test-bucket', 30000),
  'attached:3', 'after a removal the next item goes to the end, not into the gap');
select is((select duration_ms from public.media_objects where id = (select id from m where name = 'four')),
  30000::bigint, 'a video''s measured duration is recorded');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          (select id from m where name = 'two')),
  'invalid_status:-', 'a removed item cannot be attached again');

-- ---------------------------------------------------------------------------
-- The limit
-- ---------------------------------------------------------------------------

create temp table filled (n int primary key, outcome text);
insert into filled
select n, pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a2',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a2'))
from generate_series(1, 11) as n;

select is((select count(*)::int from filled where outcome like 'attached:%'), 10, 'ten items are attached');
select is((select outcome from filled where n = 11), 'limit_reached:-', 'the 11th is refused with limit_reached');
select is((select count(*)::int from public.offer_media where offer_id = '0ffe0000-0000-4000-8000-0000000000a2'),
  10, 'the Offer holds exactly 10 links');

-- ---------------------------------------------------------------------------
-- Bucket isolation
-- ---------------------------------------------------------------------------

create temp table other_bucket as
select pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a3',
                       pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a3', 'other-bucket'),
                       'other-bucket') as outcome
from generate_series(1, 9);

create temp table this_bucket (n int primary key, outcome text);
insert into this_bucket
select n, pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a3',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a3'))
from generate_series(1, 11) as n;

select is((select outcome from this_bucket where n = 10), 'attached:18',
  'another bucket''s 9 items do not count against this bucket''s 10, and positions never collide');
select is((select outcome from this_bucket where n = 11), 'limit_reached:-',
  'this bucket''s 11th item is refused');

-- ---------------------------------------------------------------------------
-- Refusals
-- ---------------------------------------------------------------------------

select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000b1',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000b1')),
  'offer_not_found:-', 'another account''s Offer is offer_not_found');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a4',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a4')),
  'offer_not_found:-', 'a soft-deleted Offer is offer_not_found');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a2',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1')),
  'media_not_found:-', 'media keyed under a different Offer is media_not_found');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000b', '0ffe0000-0000-4000-8000-0000000000a1',
                                          'test-bucket', '0ffe0000-0000-4000-8000-00000000000a')),
  'media_not_found:-', 'another account''s media is media_not_found');
select is(pg_temp.confirm('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                          pg_temp.pending('0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
                                          'test-bucket', null, 'failed')),
  'invalid_status:-', 'a failed upload is invalid_status');

set local role authenticated;
select throws_ok(
  $$select * from public.confirm_offer_media_upload(
      '0ffe0000-0000-4000-8000-00000000000a', '0ffe0000-0000-4000-8000-0000000000a1',
      gen_random_uuid(), 'test-bucket', 10, 64, 'image/jpeg', null)$$,
  '42501', null, 'a signed-in client cannot call it');
reset role;

select * from finish();
rollback;
