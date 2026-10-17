-- Offer / Owner land-plan and plot-plan attachment: the service-role-only
-- functions attach, replace and remove ONE plan per record, refuse anything not
-- owned, not live, not in the given bucket or outside the record's own plan key
-- (an Offer plan can never bind to an Owner, and the other way round), keep the
-- plan apart from the photo/video gallery and its 10-item limit, and leave the
-- record's own `version` and `updated_at` alone. The pointer columns are
-- server-controlled: clients can read them, never write them.
--
-- The rollback-only counterpart for the hosted database is
-- supabase/validation/offer_owner_plan_attachments_validation.sql.
--
-- Run with `supabase test db` against the local stack. Writes run as postgres
-- here, standing in for the Worker's service_role calls.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(53);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('9c9c0000-0000-4000-8000-00000000000a', 'plan-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('9c9c0000-0000-4000-8000-00000000000b', 'plan-b@example.test', '{"name":"B"}'::jsonb, now(), now());

insert into public.offers (id, owner_id, offer_type, created_at, updated_at, deleted_at)
values
  ('9c9c0000-0000-4000-8000-0000000000a1', '9c9c0000-0000-4000-8000-00000000000a', 'rent',
   now() - interval '2 days', now() - interval '2 days', null),
  ('9c9c0000-0000-4000-8000-0000000000a2', '9c9c0000-0000-4000-8000-00000000000a', 'rent',
   now() - interval '2 days', now() - interval '2 days', null),
  ('9c9c0000-0000-4000-8000-0000000000a3', '9c9c0000-0000-4000-8000-00000000000a', 'rent',
   now() - interval '2 days', now() - interval '2 days', now()),
  ('9c9c0000-0000-4000-8000-0000000000b1', '9c9c0000-0000-4000-8000-00000000000b', 'rent',
   now() - interval '2 days', now() - interval '2 days', null);
insert into public.owners (id, owner_id, name, created_at, updated_at, deleted_at)
values
  ('9c9c0000-0000-4000-8000-0000000000c1', '9c9c0000-0000-4000-8000-00000000000a', 'Owner A1',
   now() - interval '2 days', now() - interval '2 days', null),
  ('9c9c0000-0000-4000-8000-0000000000c2', '9c9c0000-0000-4000-8000-00000000000a', 'Owner A2',
   now() - interval '2 days', now() - interval '2 days', null);

-- A pending media row keyed the way the Worker keys plan uploads (or, for the
-- refusal cases, keyed another way).
create function pg_temp.pending(
  p_account uuid,
  p_segment text,
  p_parent uuid,
  p_ctype text default 'image/jpeg',
  p_ext text default 'jpg',
  p_kind public.media_type default 'image',
  p_status public.media_status default 'pending_upload',
  p_bucket text default 'test-bucket',
  p_size bigint default 100
) returns uuid
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
  values (v_id, p_account, p_bucket,
    'profiles/' || p_account || '/' || p_segment || '/' || p_parent || '/' || v_id || '.' || p_ext,
    p_kind, p_ctype, p_size, p_status);
  return v_id;
end;
$$;

-- outcome:previous (or '-') of the Offer / Owner confirm.
create function pg_temp.offer_confirm(
  p_user uuid, p_offer uuid, p_media uuid, p_expected uuid,
  p_ctype text default 'image/jpeg', p_bucket text default 'test-bucket', p_size bigint default 100
) returns text
language sql as $$
  select c.outcome || ':' || coalesce(c.previous_media_id::text, '-')
  from public.confirm_offer_plan_upload(p_user, p_offer, p_media, p_bucket, p_expected, p_size, p_ctype) as c;
$$;
create function pg_temp.owner_confirm(
  p_user uuid, p_owner uuid, p_media uuid, p_expected uuid,
  p_ctype text default 'image/jpeg', p_bucket text default 'test-bucket', p_size bigint default 100
) returns text
language sql as $$
  select c.outcome || ':' || coalesce(c.previous_media_id::text, '-')
  from public.confirm_owner_plan_upload(p_user, p_owner, p_media, p_bucket, p_expected, p_size, p_ctype) as c;
$$;

-- ---------------------------------------------------------------------------
-- The functions, the trigger, the indexes and who may use them
-- ---------------------------------------------------------------------------

select has_function('public', 'confirm_offer_plan_upload',
  array['uuid', 'uuid', 'uuid', 'text', 'uuid', 'bigint', 'text'],
  'confirm_offer_plan_upload exists with the Worker''s signature');
select has_function('public', 'remove_offer_plan', array['uuid', 'uuid', 'text', 'uuid'],
  'remove_offer_plan exists');
select has_function('public', 'confirm_owner_plan_upload',
  array['uuid', 'uuid', 'uuid', 'text', 'uuid', 'bigint', 'text'],
  'confirm_owner_plan_upload exists with the Worker''s signature');
select has_function('public', 'remove_owner_plan', array['uuid', 'uuid', 'text', 'uuid'],
  'remove_owner_plan exists');
select is((select count(*)::int from pg_proc p
           where p.oid in (
             'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)'::regprocedure,
             'public.remove_offer_plan(uuid,uuid,text,uuid)'::regprocedure,
             'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)'::regprocedure,
             'public.remove_owner_plan(uuid,uuid,text,uuid)'::regprocedure)
             and p.prosecdef
             and array_to_string(p.proconfig, ',') like 'search_path=%'),
  4, 'all four are SECURITY DEFINER with a fixed search_path');
select ok(not has_function_privilege('anon',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE'),
  'anon cannot execute any of them');
select ok(not has_function_privilege('authenticated',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE'),
  'authenticated cannot execute any of them');
select ok(has_function_privilege('service_role',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE'),
  'service_role can execute all of them');
select ok(not has_function_privilege('authenticated', 'public.plan_attachment_rules(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.guard_plan_media_pointer()', 'EXECUTE'),
  'the helper and the trigger function are not executable by clients');
select ok(not has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'INSERT')
  and not has_column_privilege('authenticated', 'public.owners', 'plan_media_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.owners', 'plan_media_id', 'INSERT'),
  'clients cannot write either plan pointer');
select ok(has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.offers', 'notes', 'UPDATE'),
  'clients can still read the pointer and edit the Offer''s own fields');
select has_index('public', 'offers', 'offers_plan_media_id_key', 'one Offer per media: partial unique index');
select has_index('public', 'owners', 'owners_plan_media_id_key', 'one Owner per media: partial unique index');
select has_trigger('public', 'offers', 'offers_plan_media_guard_update', 'the Offer pointer guard exists');
select has_trigger('public', 'owners', 'owners_plan_media_guard_update', 'the Owner pointer guard exists');

-- ---------------------------------------------------------------------------
-- Offer: attach, retry, replace, retire
-- ---------------------------------------------------------------------------

create temp table m (name text primary key, id uuid not null);
insert into m values
  ('img', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1')),
  ('pdf', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1',
                          'application/pdf', 'pdf', 'pdf')),
  ('doc', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1',
                          'application/msword', 'doc', 'unknown')),
  ('stale', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1'));

select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'img'), null),
  'attached:-', 'the first plan is attached');
select is((select plan_media_id from public.offers where id = '9c9c0000-0000-4000-8000-0000000000a1'),
  (select id from m where name = 'img'), 'the Offer points at it');
select is((select status::text from public.media_objects where id = (select id from m where name = 'img')),
  'ready', 'and it is marked ready in the same call');
select is((select version from public.offers where id = '9c9c0000-0000-4000-8000-0000000000a1'),
  1::bigint, 'attaching a plan does not bump the Offer''s version');
select ok((select updated_at < now() - interval '1 day' from public.offers where id = '9c9c0000-0000-4000-8000-0000000000a1'),
  'nor its updated_at');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'img'), null),
  'already_attached:-', 'a retried confirm reports already_attached');
select is((select count(*)::int from public.offer_media where offer_id = '9c9c0000-0000-4000-8000-0000000000a1'),
  0, 'the plan is not a gallery item');

select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'stale'), null),
  'stale_replacement:-', 'an upload that does not name the current plan is stale');
select is((select plan_media_id from public.offers where id = '9c9c0000-0000-4000-8000-0000000000a1'),
  (select id from m where name = 'img'), 'and leaves the current plan in place');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'pdf'), (select id from m where name = 'img'),
                                'application/pdf'),
  'attached:' || (select id from m where name = 'img'), 'a replacement reports the plan it retired');
select is((select status::text from public.media_objects where id = (select id from m where name = 'img')),
  'pending_delete', 'the old plan is marked pending_delete in the same step');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'img'), (select id from m where name = 'pdf')),
  'invalid_status:-', 'a retired plan can never be attached again');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                (select id from m where name = 'doc'), (select id from m where name = 'pdf'),
                                'application/msword', 'test-bucket', 26214400),
  'attached:' || (select id from m where name = 'pdf'), 'a DOC of exactly 25 MiB replaces the PDF');

-- ---------------------------------------------------------------------------
-- Offer: refusals
-- ---------------------------------------------------------------------------

select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000b', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000b', 'offer-plans',
                                                '9c9c0000-0000-4000-8000-0000000000b1'), null),
  'offer_not_found:-', 'another account''s Offer is offer_not_found');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a3',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans',
                                                '9c9c0000-0000-4000-8000-0000000000a3'), null),
  'offer_not_found:-', 'a soft-deleted Offer is offer_not_found');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans',
                                                '9c9c0000-0000-4000-8000-0000000000a2'),
                                (select id from m where name = 'doc')),
  'media_not_found:-', 'media keyed for another Offer is media_not_found');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'owner-plans',
                                                '9c9c0000-0000-4000-8000-0000000000c1'),
                                (select id from m where name = 'doc')),
  'media_not_found:-', 'an Owner plan key can never bind to an Offer');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offers',
                                                '9c9c0000-0000-4000-8000-0000000000a1'),
                                (select id from m where name = 'doc')),
  'media_not_found:-', 'a gallery key can never bind as a plan');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans',
                                                '9c9c0000-0000-4000-8000-0000000000a1', 'image/jpeg', 'jpg', 'image',
                                                'pending_upload', 'other-bucket'),
                                (select id from m where name = 'doc')),
  'media_not_found:-', 'media of another bucket is media_not_found');
select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
                                pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans',
                                                '9c9c0000-0000-4000-8000-0000000000a1', 'image/jpeg', 'jpg', 'image',
                                                'failed'),
                                (select id from m where name = 'doc')),
  'invalid_status:-', 'a failed upload is invalid_status');
select throws_ok(
  $$select * from public.confirm_offer_plan_upload(
      '9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
      gen_random_uuid(), 'test-bucket', null, 100, 'application/zip')$$,
  'P0001', null, 'an archive type is refused');
select throws_ok(
  $$select * from public.confirm_offer_plan_upload(
      '9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
      gen_random_uuid(), 'test-bucket', null, 26214401, 'application/pdf')$$,
  'P0001', null, 'a document over 25 MiB is refused');

-- ---------------------------------------------------------------------------
-- Offer: removal
-- ---------------------------------------------------------------------------

select is((select outcome from public.remove_offer_plan('9c9c0000-0000-4000-8000-00000000000a',
    '9c9c0000-0000-4000-8000-0000000000a1', 'test-bucket', (select id from m where name = 'img'))),
  'stale_replacement', 'a stale removal changes nothing');
select is((select outcome from public.remove_offer_plan('9c9c0000-0000-4000-8000-00000000000b',
    '9c9c0000-0000-4000-8000-0000000000a1', 'test-bucket', (select id from m where name = 'doc'))),
  'offer_not_found', 'another account cannot remove');
select is((select outcome from public.remove_offer_plan('9c9c0000-0000-4000-8000-00000000000a',
    '9c9c0000-0000-4000-8000-0000000000a1', 'test-bucket', (select id from m where name = 'doc'))),
  'removed', 'removal clears the pointer');
select ok((select plan_media_id is null from public.offers where id = '9c9c0000-0000-4000-8000-0000000000a1')
  and (select status = 'pending_delete' from public.media_objects where id = (select id from m where name = 'doc')),
  'and retires the object');
select is((select outcome from public.remove_offer_plan('9c9c0000-0000-4000-8000-00000000000a',
    '9c9c0000-0000-4000-8000-0000000000a1', 'test-bucket', (select id from m where name = 'doc'))),
  'already_removed', 'a repeated removal is idempotent');

-- ---------------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------------

create temp table n (name text primary key, id uuid not null);
insert into n values
  ('docx', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'owner-plans', '9c9c0000-0000-4000-8000-0000000000c1',
     'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx', 'unknown')),
  ('png', pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'owner-plans', '9c9c0000-0000-4000-8000-0000000000c1',
     'image/png', 'png', 'image'));

select is(pg_temp.owner_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000c1',
    (select id from n where name = 'docx'), null,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  'attached:-', 'an Owner''s DOCX plan is attached');
select is(pg_temp.owner_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000c1',
    (select id from n where name = 'png'), (select id from n where name = 'docx'), 'image/png'),
  'attached:' || (select id from n where name = 'docx'), 'replacing it by an image retires the document');
select is(pg_temp.owner_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000c1',
    pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1'),
    (select id from n where name = 'png')),
  'media_not_found:-', 'an Offer plan key can never bind to an Owner');
select is((select outcome from public.remove_owner_plan('9c9c0000-0000-4000-8000-00000000000a',
    '9c9c0000-0000-4000-8000-0000000000c1', 'test-bucket', (select id from n where name = 'png'))),
  'removed', 'an Owner''s plan is removed');
select is((select version from public.owners where id = '9c9c0000-0000-4000-8000-0000000000c1'),
  1::bigint, 'plan changes never bumped the Owner''s version');

-- ---------------------------------------------------------------------------
-- The gallery limit is not touched by a plan
-- ---------------------------------------------------------------------------

select is(pg_temp.offer_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a2',
    pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a2'),
    null), 'attached:-', 'an Offer with a plan');
create temp table filled (n int primary key, outcome text);
-- One scalar call per row (the same shape offer_media_confirm_test.sql uses), so
-- every confirm sees the previous one's attachment.
create function pg_temp.gallery_confirm(p_user uuid, p_offer uuid, p_media uuid) returns text
language sql as $$
  select c.outcome
  from public.confirm_offer_media_upload(p_user, p_offer, p_media, 'test-bucket', 10, 64, 'image/jpeg', null) as c;
$$;
insert into filled
select n, pg_temp.gallery_confirm('9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a2',
    pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offers', '9c9c0000-0000-4000-8000-0000000000a2'))
from generate_series(1, 11) as n;
select is((select count(*)::int from filled where outcome = 'attached'), 10,
  'ten gallery items still attach next to the plan');
select is((select outcome from filled where n = 11), 'limit_reached', 'the 11th is refused: the plan took no place');

-- ---------------------------------------------------------------------------
-- Direct writes of the pointer
-- ---------------------------------------------------------------------------

select throws_ok(
  format($$update public.offers set plan_media_id = %L where id = '9c9c0000-0000-4000-8000-0000000000a1'$$,
    pg_temp.pending('9c9c0000-0000-4000-8000-00000000000a', 'offer-plans', '9c9c0000-0000-4000-8000-0000000000a1')),
  'P0001', null, 'a pointer to a media row that is not ready is refused');

set local role authenticated;
select throws_ok(
  $$update public.offers set plan_media_id = null where id = '9c9c0000-0000-4000-8000-0000000000a2'$$,
  '42501', null, 'a signed-in client cannot write the pointer');
reset role;

set local role authenticated;
select throws_ok(
  $$select * from public.confirm_offer_plan_upload(
      '9c9c0000-0000-4000-8000-00000000000a', '9c9c0000-0000-4000-8000-0000000000a1',
      gen_random_uuid(), 'test-bucket', null, 64, 'image/jpeg')$$,
  '42501', null, 'a signed-in client cannot call the confirm function');
reset role;

select * from finish();
rollback;
