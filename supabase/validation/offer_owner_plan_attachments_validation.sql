-- SOURCE ONLY. Run separately when authorized, with psql as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/offer_owner_plan_attachments_validation.sql
-- This file includes the exact migration inside a transaction that always
-- rolls back. It never writes to R2 and never records migration history.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regprocedure('public.plan_attachment_rules(text)') is not null
     or to_regprocedure('public.guard_plan_media_pointer()') is not null
     or to_regprocedure('public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_offer_plan(uuid,uuid,text,uuid)') is not null
     or to_regprocedure('public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_owner_plan(uuid,uuid,text,uuid)') is not null
     or to_regprocedure('public.confirm_offer_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)') is null
     or to_regprocedure('public.confirm_owner_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)') is null
     or exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name in ('offers', 'owners')
         and column_name = 'plan_media_id')
     or (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname in ('offers', 'owners', 'media_objects')
         and c.relrowsecurity and pg_get_userbyid(c.relowner) = 'postgres') <> 3
     or exists (select 1 from auth.users where id in (
       '9b9b0000-0000-4000-8000-00000000000a'::uuid,
       '9b9b0000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from auth.users where email in (
       'plan-attachment-a@validation.invalid',
       'plan-attachment-b@validation.invalid'))
     or exists (select 1 from public.media_objects
       where bucket in ('plan-validation.invalid', 'plan-validation-other.invalid')) then
    raise exception 'Plan attachment validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20261012233000_offer_owner_plan_attachments.sql

create function pg_temp.assert_true(ok boolean, label text)
returns void language plpgsql as $assert$
begin
  if ok is distinct from true then
    raise exception 'Plan attachment validation failed: %', label;
  end if;
end;
$assert$;

-- A media row as the Worker's authorize step leaves it: pending, keyed exactly
-- as the plan routes key it (or, for the refusal cases, keyed wrongly).
create function pg_temp.pending_plan(
  p_account uuid,
  p_segment text,
  p_parent uuid,
  p_ctype text,
  p_ext text,
  p_kind public.media_type,
  p_status public.media_status default 'pending_upload',
  p_bucket text default 'plan-validation.invalid',
  p_key_account uuid default null,
  p_size bigint default 100
) returns uuid language plpgsql as $helper$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.media_objects (
    id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
  values (
    v_id, p_account, p_bucket,
    'profiles/' || coalesce(p_key_account, p_account)::text || '/' || p_segment ||
      '/' || p_parent::text || '/' || v_id::text || '.' || p_ext,
    p_kind, p_ctype, p_size, p_status);
  return v_id;
end;
$helper$;

-- ===========================================================================
-- 1. Structure, privileges and what the migration must NOT change
-- ===========================================================================

select pg_temp.assert_true(
  not has_function_privilege('anon',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.remove_offer_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.remove_owner_plan(uuid,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.plan_attachment_rules(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.plan_attachment_rules(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.guard_plan_media_pointer()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.guard_plan_media_pointer()', 'EXECUTE'),
  'plan functions: no anon/authenticated EXECUTE, service_role EXECUTE on the RPCs');
select pg_temp.assert_true(
  not exists (select 1 from pg_proc p
    where p.proname in ('plan_attachment_rules', 'guard_plan_media_pointer',
      'confirm_offer_plan_upload', 'remove_offer_plan',
      'confirm_owner_plan_upload', 'remove_owner_plan')
      and p.pronamespace = 'public'::regnamespace
      and (p.proacl is null
        or exists (select 1 from aclexplode(p.proacl) as a where a.grantee = 0))),
  'no plan function grants EXECUTE to PUBLIC (an explicit ACL exists and has no PUBLIC entry)');
select pg_temp.assert_true(
  (select count(*) = 4 from pg_proc p
   where p.oid in (
     'public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)'::regprocedure,
     'public.remove_offer_plan(uuid,uuid,text,uuid)'::regprocedure,
     'public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)'::regprocedure,
     'public.remove_owner_plan(uuid,uuid,text,uuid)'::regprocedure)
     and p.prosecdef
     and pg_get_userbyid(p.proowner) = 'postgres'
     and pg_catalog.array_position(p.proconfig, 'search_path=""') is not null),
  'the four RPCs are postgres-owned definer functions with an empty search_path');
select pg_temp.assert_true(
  (select count(*) = 2 from pg_proc p
   where p.oid in (
     'public.plan_attachment_rules(text)'::regprocedure,
     'public.guard_plan_media_pointer()'::regprocedure)
     and not p.prosecdef
     and pg_catalog.array_position(p.proconfig, 'search_path=""') is not null),
  'the helper and the trigger function have an empty search_path');
select pg_temp.assert_true(
  not has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'INSERT')
  and not has_column_privilege('authenticated', 'public.owners', 'plan_media_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.owners', 'plan_media_id', 'INSERT')
  and not has_column_privilege('anon', 'public.offers', 'plan_media_id', 'SELECT')
  and not has_column_privilege('anon', 'public.owners', 'plan_media_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.offers', 'plan_media_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.owners', 'plan_media_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.offers', 'notes', 'UPDATE')
  and has_column_privilege('authenticated', 'public.owners', 'notes', 'UPDATE'),
  'clients can read but never write the plan pointers; ordinary columns are unchanged');
select pg_temp.assert_true(
  (select count(*) = 2 from pg_index i
     join pg_class c on c.oid = i.indexrelid
     where c.relname in ('offers_plan_media_id_key', 'owners_plan_media_id_key')
       and i.indisunique and i.indpred is not null)
  and (select count(*) = 2 from pg_constraint
     where conname in ('offers_plan_media_fk', 'owners_plan_media_fk')
       and contype = 'f' and confdeltype = 'n'),
  'one parent per media (partial unique indexes) and ON DELETE SET NULL foreign keys');
select pg_temp.assert_true(
  (select count(*) = 4 from pg_trigger
     where tgname in ('offers_plan_media_guard_insert', 'offers_plan_media_guard_update',
       'owners_plan_media_guard_insert', 'owners_plan_media_guard_update')
       and not tgisinternal),
  'the four pointer guard triggers exist');
select pg_temp.assert_true(
  (select count(*) = 2 from pg_trigger
     where tgname in ('offers_plan_media_guard_update', 'owners_plan_media_guard_update')
       and tgname > case tgrelid::regclass::text
         when 'offers' then 'offers_bump_sync_version'
         else 'owners_bump_sync_version' end),
  'the update guard runs after bump_sync_version (trigger name order)');
select pg_temp.assert_true(
  not exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name in ('offer_media', 'owner_media')
      and column_name = 'plan_media_id')
  and (select count(*) = 4 from information_schema.columns
    where table_schema = 'public' and table_name = 'offer_media')
  and (select count(*) = 4 from information_schema.columns
    where table_schema = 'public' and table_name = 'owner_media'),
  'the gallery link tables are untouched');
select pg_temp.assert_true(
  (select jsonb_agg(to_jsonb(r) order by r.file_extension)
     from public.plan_attachment_rules('image/jpeg') as r) =
  '[{"file_extension":"jpg","media_kind":"image","max_bytes":10485760}]'::jsonb
  and (select count(*) = 1 from public.plan_attachment_rules('image/png'))
  and (select count(*) = 1 from public.plan_attachment_rules('image/webp'))
  and (select count(*) = 1 from public.plan_attachment_rules('application/pdf'))
  and (select count(*) = 1 from public.plan_attachment_rules('application/msword'))
  and (select count(*) = 1 from public.plan_attachment_rules(
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'))
  and (select max_bytes = 26214400 from public.plan_attachment_rules('application/pdf'))
  and (select max_bytes = 26214400 from public.plan_attachment_rules('application/msword'))
  and not exists (select 1 from public.plan_attachment_rules('image/heic'))
  and not exists (select 1 from public.plan_attachment_rules('image/gif'))
  and not exists (select 1 from public.plan_attachment_rules('image/svg+xml'))
  and not exists (select 1 from public.plan_attachment_rules('application/zip'))
  and not exists (select 1 from public.plan_attachment_rules('application/x-msdownload'))
  and not exists (select 1 from public.plan_attachment_rules('application/octet-stream'))
  and not exists (select 1 from public.plan_attachment_rules('video/mp4'))
  and not exists (select 1 from public.plan_attachment_rules('')),
  'the accepted plan types and the 25 MiB document limit; nothing else');

-- ===========================================================================
-- 2. Data
-- ===========================================================================

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('9b9b0000-0000-4000-8000-00000000000a',
   'plan-attachment-a@validation.invalid', '{}'::jsonb, now(), now()),
  ('9b9b0000-0000-4000-8000-00000000000b',
   'plan-attachment-b@validation.invalid', '{}'::jsonb, now(), now());
select pg_temp.assert_true((select count(*) = 2 from public.profiles where id in (
  '9b9b0000-0000-4000-8000-00000000000a'::uuid,
  '9b9b0000-0000-4000-8000-00000000000b'::uuid)), 'test profiles created');

-- Old timestamps, so a plan change that wrongly bumps updated_at is visible.
insert into public.offers (id, owner_id, offer_type, created_at, updated_at, deleted_at)
values
  ('9b9b0000-0000-4000-8000-0000000000a1', '9b9b0000-0000-4000-8000-00000000000a',
   'rent', now() - interval '2 days', now() - interval '2 days', null),
  ('9b9b0000-0000-4000-8000-0000000000a2', '9b9b0000-0000-4000-8000-00000000000a',
   'rent', now() - interval '2 days', now() - interval '2 days', null),
  ('9b9b0000-0000-4000-8000-0000000000a3', '9b9b0000-0000-4000-8000-00000000000a',
   'rent', now() - interval '2 days', now() - interval '2 days', now()),
  ('9b9b0000-0000-4000-8000-0000000000b1', '9b9b0000-0000-4000-8000-00000000000b',
   'rent', now() - interval '2 days', now() - interval '2 days', null);
insert into public.owners (id, owner_id, name, created_at, updated_at, deleted_at)
values
  ('9b9b0000-0000-4000-8000-0000000000c1', '9b9b0000-0000-4000-8000-00000000000a',
   'Owner A1', now() - interval '2 days', now() - interval '2 days', null),
  ('9b9b0000-0000-4000-8000-0000000000c2', '9b9b0000-0000-4000-8000-00000000000a',
   'Owner A2', now() - interval '2 days', now() - interval '2 days', null),
  ('9b9b0000-0000-4000-8000-0000000000c3', '9b9b0000-0000-4000-8000-00000000000a',
   'Owner A3', now() - interval '2 days', now() - interval '2 days', now()),
  ('9b9b0000-0000-4000-8000-0000000000d1', '9b9b0000-0000-4000-8000-00000000000b',
   'Owner B1', now() - interval '2 days', now() - interval '2 days', null);

-- ===========================================================================
-- 3. Offer plan
-- ===========================================================================

do $offer$
declare
  ua constant uuid := '9b9b0000-0000-4000-8000-00000000000a';
  ub constant uuid := '9b9b0000-0000-4000-8000-00000000000b';
  oa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000a1';
  oa2 constant uuid := '9b9b0000-0000-4000-8000-0000000000a2';
  oa3 constant uuid := '9b9b0000-0000-4000-8000-0000000000a3';
  ob1 constant uuid := '9b9b0000-0000-4000-8000-0000000000b1';
  wa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000c1';
  bucket constant text := 'plan-validation.invalid';
  docx constant text :=
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  img1 uuid; img2 uuid; pdf1 uuid; doc1 uuid; docx1 uuid;
  stale1 uuid; foreign1 uuid; other_parent uuid; owner_key uuid; gallery_key uuid;
  profile_key uuid; wrong_kind uuid; failed1 uuid; other_bucket uuid; wrong_user_key uuid;
  deleted_parent uuid; too_big uuid; r record; refused boolean; message text;
  v_version bigint; v_updated timestamptz;
begin
  img1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image');
  img2 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/png', 'png', 'image');
  pdf1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'application/pdf', 'pdf', 'pdf');
  doc1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'application/msword', 'doc', 'unknown');
  docx1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, docx, 'docx', 'unknown');
  stale1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/webp', 'webp', 'image');
  other_parent := pg_temp.pending_plan(ua, 'offer-plans', oa2, 'image/jpeg', 'jpg', 'image');
  owner_key := pg_temp.pending_plan(ua, 'owner-plans', wa1, 'image/jpeg', 'jpg', 'image');
  gallery_key := pg_temp.pending_plan(ua, 'offers', oa1, 'image/jpeg', 'jpg', 'image');
  profile_key := gen_random_uuid();
  insert into public.media_objects (id, owner_id, bucket, object_key, media_type,
    content_type, size_bytes, status)
  values (profile_key, ua, bucket, 'profiles/' || ua::text || '/' || profile_key::text || '.jpg',
    'image', 'image/jpeg', 100, 'pending_upload');
  wrong_kind := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'application/pdf', 'pdf', 'image');
  failed1 := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image', 'failed');
  other_bucket := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image',
    'pending_upload', 'plan-validation-other.invalid');
  foreign1 := pg_temp.pending_plan(ub, 'offer-plans', ob1, 'image/jpeg', 'jpg', 'image');
  wrong_user_key := pg_temp.pending_plan(ub, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image',
    'pending_upload', bucket, ua);
  deleted_parent := pg_temp.pending_plan(ua, 'offer-plans', oa3, 'image/jpeg', 'jpg', 'image');
  too_big := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'application/pdf', 'pdf', 'pdf',
    'pending_upload', bucket, null, 26214401);

  -- 3.1 First attach: an image. The parent's own timestamps and version stay.
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, img1, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id is null,
    'offer: first plan attached');
  perform pg_temp.assert_true(
    (select plan_media_id = img1 from public.offers where id = oa1)
    and (select status = 'ready' from public.media_objects where id = img1),
    'offer: pointer and ready status agree');
  select version, updated_at into v_version, v_updated from public.offers where id = oa1;
  perform pg_temp.assert_true(v_version = 1 and v_updated < now() - interval '1 day',
    'offer: attaching a plan keeps the Offer''s version and updated_at');
  perform pg_temp.assert_true(
    not exists (select 1 from public.offer_media where offer_id = oa1)
    and not exists (select 1 from public.owner_media as om
      where om.owner_record_id in (select w.id from public.owners as w where w.owner_id in (ua, ub))),
    'offer: the plan is not a gallery item');

  -- 3.2 A retried confirm is idempotent.
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, img1, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'already_attached' and r.previous_media_id is null,
    'offer: a repeated confirm reports already_attached');

  -- 3.3 One plan per parent, replacement keeps the old one until the switch.
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, stale1, bucket, null, 100, 'image/webp');
  perform pg_temp.assert_true(r.outcome = 'stale_replacement',
    'offer: an upload that does not name the current plan is stale');
  perform pg_temp.assert_true(
    (select plan_media_id = img1 from public.offers where id = oa1)
    and (select status = 'ready' from public.media_objects where id = img1)
    and (select status = 'pending_upload' from public.media_objects where id = stale1),
    'offer: a refused replacement leaves the old plan and the candidate untouched');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, pdf1, bucket, img1, 4096, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = img1,
    'offer: replacement by a PDF switches the plan');
  perform pg_temp.assert_true(
    (select plan_media_id = pdf1 from public.offers where id = oa1)
    and (select status = 'ready' and size_bytes = 4096 from public.media_objects where id = pdf1)
    and (select status = 'pending_delete' and deleted_at is not null
         from public.media_objects where id = img1),
    'offer: the old plan is retired in the same step and the new one is ready');
  select version, updated_at into v_version, v_updated from public.offers where id = oa1;
  perform pg_temp.assert_true(v_version = 1 and v_updated < now() - interval '1 day',
    'offer: replacing a plan keeps the Offer''s version and updated_at');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, img1, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'invalid_status',
    'offer: a retired plan can never be attached again');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, doc1, bucket, pdf1, 3000, 'application/msword');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = pdf1,
    'offer: a DOC replaces the PDF');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, docx1, bucket, doc1, 26214400, docx);
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = doc1
    and (select plan_media_id = docx1 from public.offers where id = oa1),
    'offer: a DOCX of exactly 25 MiB is accepted');

  -- 3.4 Refusals leave everything as it was.
  refused := false;
  begin
    perform public.confirm_offer_plan_upload(
      ua, oa1, too_big, bucket, docx1, 26214401, 'application/pdf');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'offer: a document over 25 MiB is refused');
  refused := false;
  begin
    perform public.confirm_offer_plan_upload(ua, oa1, img2, bucket, docx1, 10485761, 'image/png');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'offer: an image over 10 MiB is refused');
  refused := false;
  begin
    perform public.confirm_offer_plan_upload(ua, oa1, img2, bucket, docx1, 0, 'image/png');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'offer: a zero-length object is refused');
  foreach message in array array['image/gif', 'image/svg+xml', 'application/zip',
    'application/x-msdownload', 'application/octet-stream', 'video/mp4', 'image/heic'] loop
    refused := false;
    begin
      perform public.confirm_offer_plan_upload(ua, oa1, img2, bucket, docx1, 100, message);
    exception when others then refused := true;
    end;
    perform pg_temp.assert_true(refused, 'offer: unsupported type refused: ' || message);
  end loop;
  refused := false;
  begin
    perform public.confirm_offer_plan_upload(ua, oa1, img2, '  ', docx1, 100, 'image/png');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'offer: a blank bucket is refused');

  select * into r from public.confirm_offer_plan_upload(
    ub, oa1, foreign1, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'offer_not_found',
    'offer: another account''s Offer is offer_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, foreign1, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: another account''s media is media_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, wrong_user_key, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: media owned by B but keyed under A is media_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, other_parent, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: media keyed for another Offer is media_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, owner_key, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: an Owner plan key can never bind to an Offer');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, gallery_key, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: a gallery key can never bind as a plan');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, profile_key, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: a profile image key can never bind as a plan');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, wrong_kind, bucket, docx1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: a media row whose kind disagrees with its type is media_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, other_bucket, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'offer: media of another bucket is media_not_found');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa1, failed1, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'invalid_status',
    'offer: a failed upload is invalid_status');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa3, deleted_parent, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'offer_not_found',
    'offer: a soft-deleted Offer cannot bind');
  select * into r from public.remove_offer_plan(ua, oa3, bucket, null);
  perform pg_temp.assert_true(r.outcome = 'offer_not_found',
    'offer: a soft-deleted Offer cannot remove');
  perform pg_temp.assert_true(
    (select plan_media_id = docx1 from public.offers where id = oa1)
    and (select plan_media_id is null from public.offers where id in (oa2, oa3, ob1) limit 1),
    'offer: every refusal left the plan exactly as it was');

  -- 3.5 Removal.
  select * into r from public.remove_offer_plan(ub, oa1, bucket, docx1);
  perform pg_temp.assert_true(r.outcome = 'offer_not_found',
    'offer: another account cannot remove');
  select * into r from public.remove_offer_plan(ua, oa1, bucket, img1);
  perform pg_temp.assert_true(r.outcome = 'stale_replacement'
    and (select plan_media_id = docx1 from public.offers where id = oa1),
    'offer: a stale removal changes nothing');
  select * into r from public.remove_offer_plan(ua, oa1, 'plan-validation-other.invalid', docx1);
  perform pg_temp.assert_true(r.outcome = 'invalid_state'
    and (select plan_media_id = docx1 from public.offers where id = oa1),
    'offer: a removal from another bucket is refused');
  select * into r from public.remove_offer_plan(ua, oa1, bucket, docx1);
  perform pg_temp.assert_true(r.outcome = 'removed' and r.previous_media_id = docx1
    and (select plan_media_id is null from public.offers where id = oa1)
    and (select status = 'pending_delete' from public.media_objects where id = docx1),
    'offer: removal clears the pointer and retires the object');
  select version, updated_at into v_version, v_updated from public.offers where id = oa1;
  perform pg_temp.assert_true(v_version = 1 and v_updated < now() - interval '1 day',
    'offer: removing a plan keeps the Offer''s version and updated_at');
  select * into r from public.remove_offer_plan(ua, oa1, bucket, docx1);
  perform pg_temp.assert_true(r.outcome = 'already_removed' and r.previous_media_id is null,
    'offer: a repeated removal is idempotent');

  -- 3.6 An ordinary edit of the Offer still bumps version and updated_at.
  update public.offers set notes = 'edited' where id = oa2;
  select version, updated_at into v_version, v_updated from public.offers where id = oa2;
  perform pg_temp.assert_true(v_version = 2 and v_updated > now() - interval '1 minute',
    'offer: an ordinary edit still bumps version and updated_at');
end;
$offer$;

-- ===========================================================================
-- 4. Owner plan (the same contract, for an Owner record)
-- ===========================================================================

do $owner$
declare
  ua constant uuid := '9b9b0000-0000-4000-8000-00000000000a';
  ub constant uuid := '9b9b0000-0000-4000-8000-00000000000b';
  oa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000a1';
  wa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000c1';
  wa2 constant uuid := '9b9b0000-0000-4000-8000-0000000000c2';
  wa3 constant uuid := '9b9b0000-0000-4000-8000-0000000000c3';
  wb1 constant uuid := '9b9b0000-0000-4000-8000-0000000000d1';
  bucket constant text := 'plan-validation.invalid';
  docx constant text :=
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  docx1 uuid; img1 uuid; pdf1 uuid; offer_key uuid; gallery_key uuid; other_parent uuid;
  foreign1 uuid; deleted_parent uuid; r record; refused boolean;
  v_version bigint; v_updated timestamptz;
begin
  docx1 := pg_temp.pending_plan(ua, 'owner-plans', wa1, docx, 'docx', 'unknown');
  img1 := pg_temp.pending_plan(ua, 'owner-plans', wa1, 'image/jpeg', 'jpg', 'image');
  pdf1 := pg_temp.pending_plan(ua, 'owner-plans', wa1, 'application/pdf', 'pdf', 'pdf');
  offer_key := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image');
  gallery_key := pg_temp.pending_plan(ua, 'owners', wa1, 'image/jpeg', 'jpg', 'image');
  other_parent := pg_temp.pending_plan(ua, 'owner-plans', wa2, 'image/jpeg', 'jpg', 'image');
  foreign1 := pg_temp.pending_plan(ub, 'owner-plans', wb1, 'image/jpeg', 'jpg', 'image');
  deleted_parent := pg_temp.pending_plan(ua, 'owner-plans', wa3, 'image/jpeg', 'jpg', 'image');

  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, docx1, bucket, null, 5000, docx);
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id is null
    and (select plan_media_id = docx1 from public.owners where id = wa1),
    'owner: a DOCX plan is attached');
  select version, updated_at into v_version, v_updated from public.owners where id = wa1;
  perform pg_temp.assert_true(v_version = 1 and v_updated < now() - interval '1 day',
    'owner: attaching a plan keeps the Owner''s version and updated_at');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, docx1, bucket, null, 5000, docx);
  perform pg_temp.assert_true(r.outcome = 'already_attached', 'owner: idempotent confirm');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, img1, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'stale_replacement'
    and (select plan_media_id = docx1 from public.owners where id = wa1),
    'owner: a stale replacement is refused and keeps the plan');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, img1, bucket, docx1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = docx1
    and (select status = 'pending_delete' from public.media_objects where id = docx1)
    and (select plan_media_id = img1 from public.owners where id = wa1),
    'owner: replacement switches and retires the old plan');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, pdf1, bucket, img1, 26214400, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = img1,
    'owner: a PDF of exactly 25 MiB is accepted');
  refused := false;
  begin
    perform public.confirm_owner_plan_upload(ua, wa1, pdf1, bucket, pdf1, 26214401, 'application/pdf');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'owner: a document over 25 MiB is refused');
  refused := false;
  begin
    perform public.confirm_owner_plan_upload(ua, wa1, pdf1, bucket, pdf1, 100, 'application/zip');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'owner: an archive is refused');

  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, offer_key, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'owner: an Offer plan key can never bind to an Owner');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, gallery_key, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'owner: a gallery key can never bind as a plan');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, other_parent, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'owner: media keyed for another Owner is media_not_found');
  select * into r from public.confirm_owner_plan_upload(
    ub, wa1, foreign1, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'owner_not_found',
    'owner: another account''s Owner is owner_not_found');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa1, foreign1, bucket, pdf1, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found',
    'owner: another account''s media is media_not_found');
  select * into r from public.confirm_owner_plan_upload(
    ua, wa3, deleted_parent, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'owner_not_found',
    'owner: a soft-deleted Owner cannot bind');
  select * into r from public.confirm_offer_plan_upload(
    ua, wa1, other_parent, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'offer_not_found',
    'owner: an Owner id on the Offer function is offer_not_found');

  select * into r from public.remove_owner_plan(ua, wa1, bucket, img1);
  perform pg_temp.assert_true(r.outcome = 'stale_replacement'
    and (select plan_media_id = pdf1 from public.owners where id = wa1),
    'owner: a stale removal changes nothing');
  select * into r from public.remove_owner_plan(ub, wa1, bucket, pdf1);
  perform pg_temp.assert_true(r.outcome = 'owner_not_found', 'owner: another account cannot remove');
  select * into r from public.remove_owner_plan(ua, wa1, bucket, pdf1);
  perform pg_temp.assert_true(r.outcome = 'removed' and r.previous_media_id = pdf1
    and (select plan_media_id is null from public.owners where id = wa1)
    and (select status = 'pending_delete' from public.media_objects where id = pdf1),
    'owner: removal clears the pointer and retires the object');
  select * into r from public.remove_owner_plan(ua, wa1, bucket, pdf1);
  perform pg_temp.assert_true(r.outcome = 'already_removed', 'owner: removal is idempotent');
  select * into r from public.remove_owner_plan(ua, wa3, bucket, null);
  perform pg_temp.assert_true(r.outcome = 'owner_not_found', 'owner: a deleted Owner cannot remove');
  select version, updated_at into v_version, v_updated from public.owners where id = wa1;
  perform pg_temp.assert_true(v_version = 1 and v_updated < now() - interval '1 day',
    'owner: plan changes never touched the Owner''s version or updated_at');
end;
$owner$;

-- ===========================================================================
-- 5. The plan does not touch the gallery limit
-- ===========================================================================

do $gallery$
declare
  ua constant uuid := '9b9b0000-0000-4000-8000-00000000000a';
  oa2 constant uuid := '9b9b0000-0000-4000-8000-0000000000a2';
  bucket constant text := 'plan-validation.invalid';
  plan uuid; g uuid; r record; n integer;
begin
  plan := pg_temp.pending_plan(ua, 'offer-plans', oa2, 'application/pdf', 'pdf', 'pdf');
  select * into r from public.confirm_offer_plan_upload(
    ua, oa2, plan, bucket, null, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'attached', 'gallery: a plan is attached to the Offer');
  for n in 1..10 loop
    g := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type,
      content_type, size_bytes, status)
    values (g, ua, bucket,
      'profiles/' || ua::text || '/offers/' || oa2::text || '/' || g::text || '.jpg',
      'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into r
      from public.confirm_offer_media_upload(ua, oa2, g, bucket, 10, 64, 'image/jpeg', null) as c;
    perform pg_temp.assert_true(r.outcome = 'attached', 'gallery: item ' || n || ' attaches');
  end loop;
  g := gen_random_uuid();
  insert into public.media_objects (id, owner_id, bucket, object_key, media_type,
    content_type, size_bytes, status)
  values (g, ua, bucket,
    'profiles/' || ua::text || '/offers/' || oa2::text || '/' || g::text || '.jpg',
    'image', 'image/jpeg', 64, 'pending_upload');
  select c.outcome into r
    from public.confirm_offer_media_upload(ua, oa2, g, bucket, 10, 64, 'image/jpeg', null) as c;
  perform pg_temp.assert_true(r.outcome = 'limit_reached',
    'gallery: the 11th gallery item is refused');
  perform pg_temp.assert_true(
    (select count(*) = 10 from public.offer_media where offer_id = oa2)
    and (select plan_media_id = plan from public.offers where id = oa2),
    'gallery: ten gallery items and the plan coexist; the plan took no gallery place');
end;
$gallery$;

-- ===========================================================================
-- 6. Direct writes of the pointer
-- ===========================================================================

do $direct$
declare
  ua constant uuid := '9b9b0000-0000-4000-8000-00000000000a';
  ub constant uuid := '9b9b0000-0000-4000-8000-00000000000b';
  oa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000a1';
  oa4 constant uuid := '9b9b0000-0000-4000-8000-0000000000a4';
  ob1 constant uuid := '9b9b0000-0000-4000-8000-0000000000b1';
  wa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000c1';
  bucket constant text := 'plan-validation.invalid';
  m uuid; refused boolean; message text; state text; v_version bigint;
  v_updated timestamptz; had boolean;
begin
  -- A fresh Offer with no plan, for the refusal cases.
  insert into public.offers (id, owner_id, offer_type, created_at, updated_at)
  values (oa4, ua, 'rent', now() - interval '2 days', now() - interval '2 days');

  -- A READY, correctly keyed file is accepted even when written directly, and
  -- the write leaves the Offer's version and updated_at alone.
  m := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/png', 'png', 'image', 'ready');
  update public.offers set plan_media_id = m where id = oa1;
  select version, updated_at into v_version, v_updated from public.offers where id = oa1;
  perform pg_temp.assert_true(
    (select plan_media_id = m from public.offers where id = oa1)
    and v_version = 1 and v_updated < now() - interval '1 day',
    'direct: a ready, exact-key pointer is accepted and keeps version/updated_at');

  -- Refusals, each leaving the pointer unchanged.
  foreach state in array array['pending', 'foreign', 'owner-key', 'other-offer', 'kind',
    'big', 'nosize', 'gallery', 'cross-account'] loop
    m := case state
      when 'pending' then pg_temp.pending_plan(ua, 'offer-plans', oa4, 'image/png', 'png', 'image')
      when 'foreign' then pg_temp.pending_plan(ub, 'offer-plans', ob1, 'image/png', 'png', 'image', 'ready')
      when 'owner-key' then pg_temp.pending_plan(ua, 'owner-plans', wa1, 'image/png', 'png', 'image', 'ready')
      when 'other-offer' then pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/png', 'png', 'image', 'ready')
      when 'kind' then pg_temp.pending_plan(ua, 'offer-plans', oa4, 'application/pdf', 'pdf', 'image', 'ready')
      when 'big' then pg_temp.pending_plan(ua, 'offer-plans', oa4, 'image/png', 'png', 'image', 'ready', bucket, null, 10485761)
      when 'nosize' then pg_temp.pending_plan(ua, 'offer-plans', oa4, 'image/png', 'png', 'image', 'ready', bucket, null, 0)
      when 'gallery' then pg_temp.pending_plan(ua, 'offers', oa4, 'image/png', 'png', 'image', 'ready')
      else pg_temp.pending_plan(ub, 'offer-plans', oa4, 'image/png', 'png', 'image', 'ready', bucket, ua)
    end;
    refused := false;
    begin
      update public.offers set plan_media_id = m where id = oa4;
    exception when others then refused := true;
    end;
    perform pg_temp.assert_true(refused
      and (select plan_media_id is null from public.offers where id = oa4),
      'direct: refused pointer (' || state || ')');
  end loop;
  -- 'other-offer' targets oa4 with a key of oa1: refused above. A key for the
  -- right Offer that is already the pointer of another Offer cannot be shared.
  refused := false;
  begin
    update public.offers set plan_media_id = (select plan_media_id from public.offers where id = oa1)
      where id = oa4;
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'direct: one media cannot back two Offers');

  -- An insert that names a pointer is validated too.
  refused := false;
  begin
    insert into public.offers (id, owner_id, offer_type, plan_media_id)
    values (gen_random_uuid(), ua, 'rent',
      pg_temp.pending_plan(ua, 'offer-plans', oa4, 'image/png', 'png', 'image', 'ready'));
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'direct: an insert cannot start with a foreign pointer');

  -- A signed-in client is refused by column privilege...
  refused := false;
  begin
    execute 'set local role authenticated';
    update public.offers set plan_media_id = null where id = oa1;
  exception when insufficient_privilege then refused := true;
  end;
  perform pg_temp.assert_true(refused and current_user = 'postgres',
    'client: authenticated cannot update the pointer (column privilege)');
  refused := false;
  begin
    execute 'set local role authenticated';
    insert into public.owners (id, owner_id, name, plan_media_id)
    values (gen_random_uuid(), ua, 'x', null);
  exception when insufficient_privilege then refused := true;
  end;
  perform pg_temp.assert_true(refused and current_user = 'postgres',
    'client: authenticated cannot insert a pointer (column privilege)');
  refused := false;
  begin
    execute 'set local role anon';
    perform plan_media_id from public.offers limit 1;
  exception when insufficient_privilege then refused := true;
  end;
  perform pg_temp.assert_true(refused and current_user = 'postgres',
    'client: anon cannot read the pointer');

  -- ...and, if a grant were ever widened by mistake, by the trigger itself.
  had := false;
  execute 'alter table public.offers disable row level security';
  execute 'grant update (plan_media_id) on public.offers to authenticated';
  begin
    execute 'set local role authenticated';
    update public.offers set plan_media_id = null where id = oa1;
  exception when insufficient_privilege then
    get stacked diagnostics message = message_text;
    had := message like '%server-controlled%';
  end;
  execute 'reset role';
  execute 'revoke update (plan_media_id) on public.offers from authenticated';
  execute 'alter table public.offers enable row level security';
  perform pg_temp.assert_true(had and current_user = 'postgres'
    and (select plan_media_id is not null from public.offers where id = oa1),
    'client: the trigger refuses a client even with a widened grant');

  -- The service role (the Worker's direct clearing of a soft-deleted parent)
  -- may clear the pointer.
  execute 'set local role service_role';
  update public.offers set plan_media_id = null where id = oa1;
  execute 'reset role';
  select version, updated_at into v_version, v_updated from public.offers where id = oa1;
  perform pg_temp.assert_true(
    (select plan_media_id is null from public.offers where id = oa1)
    and v_version = 1 and v_updated < now() - interval '1 day',
    'service: service_role can clear the pointer, keeping version/updated_at');
end;
$direct$;

-- ===========================================================================
-- 7. Deleting the file or the account
-- ===========================================================================

do $delete$
declare
  ua constant uuid := '9b9b0000-0000-4000-8000-00000000000a';
  oa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000a1';
  wa1 constant uuid := '9b9b0000-0000-4000-8000-0000000000c1';
  bucket constant text := 'plan-validation.invalid';
  m uuid; r record; v_version bigint;
begin
  m := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'image/jpeg', 'jpg', 'image');
  select * into r from public.confirm_offer_plan_upload(ua, oa1, m, bucket, null, 100, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'attached', 'delete: plan attached');
  delete from public.media_objects where id = m;
  select version into v_version from public.offers where id = oa1;
  perform pg_temp.assert_true(
    (select plan_media_id is null from public.offers where id = oa1) and v_version = 1,
    'delete: removing the media row clears the pointer (ON DELETE SET NULL)');

  m := pg_temp.pending_plan(ua, 'offer-plans', oa1, 'application/pdf', 'pdf', 'pdf');
  perform public.confirm_offer_plan_upload(ua, oa1, m, bucket, null, 100, 'application/pdf');
  m := pg_temp.pending_plan(ua, 'owner-plans', wa1, 'image/png', 'png', 'image');
  perform public.confirm_owner_plan_upload(ua, wa1, m, bucket, null, 100, 'image/png');
  perform pg_temp.assert_true(
    (select count(*) = 1 from public.offers where id = oa1 and plan_media_id is not null)
    and (select count(*) = 1 from public.owners where id = wa1 and plan_media_id is not null),
    'delete: plans exist before the account is deleted');

  -- Account deletion: the Auth user goes, everything cascades. Deleted the way
  -- Supabase Auth's admin delete does it (see account_deletion_cascade_validation).
  if pg_has_role(current_user, 'supabase_auth_admin', 'MEMBER') then
    execute 'set local role supabase_auth_admin';
  end if;
  delete from auth.users where id = ua;
  execute 'set local role none';
  perform pg_temp.assert_true(
    not exists (select 1 from public.offers where owner_id = ua)
    and not exists (select 1 from public.owners where owner_id = ua)
    and not exists (select 1 from public.media_objects where owner_id = ua)
    and not exists (select 1 from public.profiles where id = ua),
    'delete: deleting the account removes its Offers, Owners, plans and media rows');
  perform pg_temp.assert_true(
    exists (select 1 from public.offers where owner_id = '9b9b0000-0000-4000-8000-00000000000b'),
    'delete: another account is untouched');
end;
$delete$;

select 'OFFER_OWNER_PLAN_ATTACHMENTS_ROLLBACK_SOURCE_PASS' as result;
rollback;

do $postflight$
begin
  if to_regprocedure('public.plan_attachment_rules(text)') is not null
     or to_regprocedure('public.guard_plan_media_pointer()') is not null
     or to_regprocedure('public.confirm_offer_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_offer_plan(uuid,uuid,text,uuid)') is not null
     or to_regprocedure('public.confirm_owner_plan_upload(uuid,uuid,uuid,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_owner_plan(uuid,uuid,text,uuid)') is not null
     or exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name in ('offers', 'owners')
         and column_name = 'plan_media_id')
     or exists (select 1 from auth.users where id in (
       '9b9b0000-0000-4000-8000-00000000000a'::uuid,
       '9b9b0000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from public.offers where id in (
       '9b9b0000-0000-4000-8000-0000000000a1'::uuid,
       '9b9b0000-0000-4000-8000-0000000000b1'::uuid))
     or exists (select 1 from public.media_objects
       where bucket in ('plan-validation.invalid', 'plan-validation-other.invalid')) then
    raise exception 'Plan attachment validation rollback left hosted residue';
  end if;
end;
$postflight$;
select 'OFFER_OWNER_PLAN_ATTACHMENTS_ROLLBACK_RESTORED' as result;
