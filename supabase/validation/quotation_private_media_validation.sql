-- SOURCE ONLY. Run separately when authorized, with psql as postgres:
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/quotation_private_media_validation.sql
-- This file includes the exact migration inside a transaction that always
-- rolls back. It never writes to R2 and never records migration history.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regprocedure('public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_quotation_media(uuid,uuid,text,text,uuid)') is not null
     or (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname in ('quotations','quotation_media','media_objects')
         and c.relrowsecurity and pg_get_userbyid(c.relowner) = 'postgres') <> 3
     or exists (select 1 from auth.users where id in (
       '9a9a0000-0000-4000-8000-00000000000a'::uuid,
       '9a9a0000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from auth.users where email in (
       'quotation-media-a@validation.invalid',
       'quotation-media-b@validation.invalid'))
     or exists (select 1 from public.quotations where id in (
       '9a9a0000-0000-4000-8000-0000000000a1'::uuid,
       '9a9a0000-0000-4000-8000-0000000000a2'::uuid,
       '9a9a0000-0000-4000-8000-0000000000b1'::uuid))
     or exists (select 1 from public.media_objects
       where bucket = 'quotation-media-validation.invalid') then
    raise exception 'Quotation media validation preflight failed';
  end if;
end;
$preflight$;

\ir ../migrations/20261001220000_quotation_private_media_rpc.sql

create function pg_temp.assert_true(ok boolean, label text)
returns void language plpgsql as $assert$
begin
  if ok is distinct from true then
    raise exception 'Quotation media validation failed: %', label;
  end if;
end;
$assert$;

select pg_temp.assert_true(
  not has_function_privilege('anon',
    'public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.remove_quotation_media(uuid,uuid,text,text,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.remove_quotation_media(uuid,uuid,text,text,uuid)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.remove_quotation_media(uuid,uuid,text,text,uuid)', 'EXECUTE')
  and not has_column_privilege('authenticated', 'public.quotations',
    'office_logo_media_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.quotations',
    'pdf_media_id', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotation_media', 'INSERT'),
  'service-only RPCs and server-controlled IDs');
select pg_temp.assert_true(
  (select count(*) = 2 from pg_proc p
   where p.oid in (
     'public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)'::regprocedure,
     'public.remove_quotation_media(uuid,uuid,text,text,uuid)'::regprocedure)
     and p.prosecdef
     and pg_get_userbyid(p.proowner) = 'postgres'
     and pg_catalog.array_position(p.proconfig, 'search_path=""') is not null),
  'both functions are postgres-owned definer with empty search_path');

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('9a9a0000-0000-4000-8000-00000000000a',
   'quotation-media-a@validation.invalid', '{}'::jsonb, now(), now()),
  ('9a9a0000-0000-4000-8000-00000000000b',
   'quotation-media-b@validation.invalid', '{}'::jsonb, now(), now());
select pg_temp.assert_true((select count(*) = 2 from public.profiles where id in (
  '9a9a0000-0000-4000-8000-00000000000a'::uuid,
  '9a9a0000-0000-4000-8000-00000000000b'::uuid)), 'test profiles created');

insert into public.quotations (id, owner_id, property_title)
values
  ('9a9a0000-0000-4000-8000-0000000000a1',
   '9a9a0000-0000-4000-8000-00000000000a', 'Validation A1'),
  ('9a9a0000-0000-4000-8000-0000000000a2',
   '9a9a0000-0000-4000-8000-00000000000a', 'Validation A2'),
  ('9a9a0000-0000-4000-8000-0000000000b1',
   '9a9a0000-0000-4000-8000-00000000000b', 'Validation B1');

insert into public.media_objects (
  id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
values
  ('9a9a0000-0000-4000-8000-000000000101',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/office_logo/9a9a0000-0000-4000-8000-000000000101.jpg',
   'image', 'image/jpeg', 64, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000102',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/office_logo/9a9a0000-0000-4000-8000-000000000102.png',
   'image', 'image/png', 64, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000103',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/quotation_pdf/9a9a0000-0000-4000-8000-000000000103.pdf',
   'pdf', 'application/pdf', 100, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000104',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a2/office_logo/9a9a0000-0000-4000-8000-000000000104.jpg',
   'image', 'image/jpeg', 64, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000105',
   '9a9a0000-0000-4000-8000-00000000000b', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000b/quotations/9a9a0000-0000-4000-8000-0000000000b1/office_logo/9a9a0000-0000-4000-8000-000000000105.jpg',
   'image', 'image/jpeg', 64, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000106',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/quotation_pdf/9a9a0000-0000-4000-8000-000000000106.pdf',
   'image', 'application/pdf', 100, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000107',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/quotation_pdf/9a9a0000-0000-4000-8000-000000000107.pdf',
   'pdf', 'application/pdf', 100, 'failed'),
  ('9a9a0000-0000-4000-8000-000000000108',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/office_logo/9a9a0000-0000-4000-8000-000000000108.webp',
   'image', 'image/webp', 64, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-000000000109',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a1/quotation_pdf/9a9a0000-0000-4000-8000-000000000109.pdf',
   'pdf', 'application/pdf', 100, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-00000000010a',
   '9a9a0000-0000-4000-8000-00000000000a', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000a/quotations/9a9a0000-0000-4000-8000-0000000000a2/quotation_pdf/9a9a0000-0000-4000-8000-00000000010a.pdf',
   'pdf', 'application/pdf', 100, 'pending_upload'),
  ('9a9a0000-0000-4000-8000-00000000010b',
   '9a9a0000-0000-4000-8000-00000000000b', 'quotation-media-validation.invalid',
   'profiles/9a9a0000-0000-4000-8000-00000000000b/quotations/9a9a0000-0000-4000-8000-0000000000b1/quotation_pdf/9a9a0000-0000-4000-8000-00000000010b.pdf',
   'pdf', 'application/pdf', 100, 'pending_upload');

do $cases$
declare
  ua constant uuid := '9a9a0000-0000-4000-8000-00000000000a';
  ub constant uuid := '9a9a0000-0000-4000-8000-00000000000b';
  qa constant uuid := '9a9a0000-0000-4000-8000-0000000000a1';
  qa2 constant uuid := '9a9a0000-0000-4000-8000-0000000000a2';
  logo1 constant uuid := '9a9a0000-0000-4000-8000-000000000101';
  logo2 constant uuid := '9a9a0000-0000-4000-8000-000000000102';
  pdf1 constant uuid := '9a9a0000-0000-4000-8000-000000000103';
  otherquote constant uuid := '9a9a0000-0000-4000-8000-000000000104';
  foreignmedia constant uuid := '9a9a0000-0000-4000-8000-000000000105';
  wrongtype constant uuid := '9a9a0000-0000-4000-8000-000000000106';
  failedmedia constant uuid := '9a9a0000-0000-4000-8000-000000000107';
  webp1 constant uuid := '9a9a0000-0000-4000-8000-000000000108';
  pdf2 constant uuid := '9a9a0000-0000-4000-8000-000000000109';
  otherpdf constant uuid := '9a9a0000-0000-4000-8000-00000000010a';
  foreignpdf constant uuid := '9a9a0000-0000-4000-8000-00000000010b';
  bucket constant text := 'quotation-media-validation.invalid';
  r record;
  refused boolean;
begin
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo1, 'office_logo', bucket, null, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.resulting_version = 2,
    'logo attached and version bumped');
  perform pg_temp.assert_true((select office_logo_media_id = logo1 from public.quotations where id = qa)
    and (select status = 'ready' from public.media_objects where id = logo1)
    and exists(select 1 from public.quotation_media where quotation_id = qa
      and media_id = logo1 and role = 'logo' and ordinal = 0),
    'logo header, link and ready status agree');

  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo1, 'office_logo', bucket, null, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'already_attached' and r.resulting_version = 2,
    'repeated confirm is idempotent');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, pdf1, 'quotation_pdf', bucket, null, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.resulting_version = 3
    and (select pdf_media_id = pdf1 from public.quotations where id = qa)
    and exists(select 1 from public.quotation_media where quotation_id = qa
      and media_id = pdf1 and role = 'pdf'), 'PDF bound to separate slot');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, pdf1, 'quotation_pdf', bucket, null, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'already_attached' and r.resulting_version = 3,
    'repeated PDF confirm is idempotent');

  select * into r from public.confirm_quotation_media_upload(
    ub, qa, foreignmedia, 'office_logo', bucket, null, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'cross-user quote refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, foreignmedia, 'office_logo', bucket, logo1, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'foreign media refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, otherquote, 'office_logo', bucket, logo1, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'cross-parent key refused');
  select * into r from public.confirm_quotation_media_upload(
    ub, qa, foreignpdf, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'cross-user PDF quotation refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, foreignpdf, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'foreign PDF media refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, otherpdf, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'cross-parent PDF key refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, wrongtype, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'wrong media_type refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, failedmedia, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'invalid_status', 'failed upload refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo2, 'office_logo', bucket, null, 64, 'image/png');
  perform pg_temp.assert_true(r.outcome = 'stale_replacement', 'stale expected slot refused');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo2, 'office_logo', 'wrong-bucket.invalid', logo1, 64, 'image/png');
  perform pg_temp.assert_true(r.outcome = 'media_not_found', 'wrong bucket refused');
  refused := false;
  begin
    perform public.confirm_quotation_media_upload(
      ua, qa, logo2, 'quotation_pdf', bucket, logo1, 64, 'image/png');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'wrong role/MIME refused');
  refused := false;
  begin
    perform public.confirm_quotation_media_upload(
      ua, qa, logo2, 'office_logo', bucket, logo1, 0, 'image/png');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'invalid observed size refused');
  refused := false;
  begin
    perform public.confirm_quotation_media_upload(
      ua, qa, logo2, 'office_logo', bucket, logo1, 64, 'image/gif');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'unsupported logo MIME refused');
  refused := false;
  begin
    perform public.confirm_quotation_media_upload(
      ua, qa, pdf2, 'quotation_pdf', bucket, pdf1, 100, 'application/octet-stream');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'unsupported PDF MIME refused');
  refused := false;
  begin
    perform public.confirm_quotation_media_upload(
      ua, qa, pdf2, 'office_logo', bucket, pdf1, 100, 'application/pdf');
  exception when others then refused := true;
  end;
  perform pg_temp.assert_true(refused, 'PDF role interchange refused');
  perform pg_temp.assert_true(
    (select office_logo_media_id = logo1 and pdf_media_id = pdf1
       from public.quotations where id = qa)
    and (select status = 'pending_upload' from public.media_objects where id = logo2)
    and (select status = 'pending_upload' from public.media_objects where id = pdf2)
    and (select count(*) = 2 from public.quotation_media where quotation_id = qa),
    'failed bindings leave both slots and links intact');

  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo2, 'office_logo', bucket, logo1, 64, 'image/png');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = logo1
    and r.resulting_version = 4
    and (select status = 'pending_delete' from public.media_objects where id = logo1)
    and (select status = 'ready' from public.media_objects where id = logo2)
    and (select count(*) = 1 from public.quotation_media where quotation_id = qa and role = 'logo'),
    'replacement swaps slot and retires previous media atomically');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, logo1, 'office_logo', bucket, null, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'stale_replacement', 'old confirm cannot restore old logo');
  select * into r from public.remove_quotation_media(ua, qa, 'office_logo', bucket, logo1);
  perform pg_temp.assert_true(r.outcome = 'stale_replacement', 'stale removal refused');
  select * into r from public.remove_quotation_media(ua, qa, 'office_logo', bucket, logo2);
  perform pg_temp.assert_true(r.outcome = 'removed' and r.previous_media_id = logo2
    and r.resulting_version = 5
    and (select office_logo_media_id is null from public.quotations where id = qa)
    and (select status = 'pending_delete' from public.media_objects where id = logo2)
    and not exists(select 1 from public.quotation_media where quotation_id = qa and role = 'logo'),
    'removal clears header/link and retires bytes');
  select * into r from public.remove_quotation_media(ua, qa, 'office_logo', bucket, logo2);
  perform pg_temp.assert_true(r.outcome = 'already_removed' and r.resulting_version = 5,
    'removal retry is idempotent');

  select * into r from public.confirm_quotation_media_upload(
    ua, qa, webp1, 'office_logo', bucket, null, 64, 'image/webp');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.resulting_version = 6
    and (select office_logo_media_id = webp1 from public.quotations where id = qa)
    and (select status = 'ready' from public.media_objects where id = webp1)
    and exists(select 1 from public.quotation_media where quotation_id = qa
      and media_id = webp1 and role = 'logo' and ordinal = 0),
    'WebP logo binds to the correct slot');
  select * into r from public.remove_quotation_media(ua, qa, 'office_logo', bucket, webp1);
  perform pg_temp.assert_true(r.outcome = 'removed' and r.resulting_version = 7
    and (select office_logo_media_id is null from public.quotations where id = qa)
    and (select status = 'pending_delete' from public.media_objects where id = webp1),
    'WebP logo removal retires object');

  select * into r from public.confirm_quotation_media_upload(
    ua, qa, pdf2, 'quotation_pdf', bucket, null, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'stale_replacement' and r.resulting_version = 7
    and (select pdf_media_id = pdf1 from public.quotations where id = qa)
    and (select status = 'pending_upload' from public.media_objects where id = pdf2),
    'stale PDF replacement leaves existing PDF intact');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa, pdf2, 'quotation_pdf', bucket, pdf1, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'attached' and r.previous_media_id = pdf1
    and r.resulting_version = 8
    and (select pdf_media_id = pdf2 from public.quotations where id = qa)
    and (select status = 'pending_delete' from public.media_objects where id = pdf1)
    and (select status = 'ready' from public.media_objects where id = pdf2)
    and (select count(*) = 1 from public.quotation_media
      where quotation_id = qa and role = 'pdf' and media_id = pdf2),
    'PDF regeneration swaps slot and retires previous object');
  select * into r from public.remove_quotation_media(ua, qa, 'quotation_pdf', bucket, pdf1);
  perform pg_temp.assert_true(r.outcome = 'stale_replacement'
    and (select pdf_media_id = pdf2 from public.quotations where id = qa),
    'stale PDF removal leaves replacement intact');
  select * into r from public.remove_quotation_media(ua, qa, 'quotation_pdf', bucket, pdf2);
  perform pg_temp.assert_true(r.outcome = 'removed' and r.previous_media_id = pdf2
    and r.resulting_version = 9
    and (select pdf_media_id is null from public.quotations where id = qa)
    and (select status = 'pending_delete' from public.media_objects where id = pdf2)
    and not exists(select 1 from public.quotation_media where quotation_id = qa and role = 'pdf'),
    'PDF removal clears slot and link and retires object');
  select * into r from public.remove_quotation_media(ua, qa, 'quotation_pdf', bucket, pdf2);
  perform pg_temp.assert_true(r.outcome = 'already_removed' and r.resulting_version = 9,
    'PDF removal retry is idempotent');

  update public.quotations set deleted_at = now() where id = qa2;
  select * into r from public.confirm_quotation_media_upload(
    ua, qa2, otherquote, 'office_logo', bucket, null, 64, 'image/jpeg');
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'deleted quotation cannot bind');
  select * into r from public.remove_quotation_media(ua, qa2, 'office_logo', bucket, null);
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'deleted quotation cannot remove');
  select * into r from public.confirm_quotation_media_upload(
    ua, qa2, otherpdf, 'quotation_pdf', bucket, null, 100, 'application/pdf');
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'deleted quotation cannot bind PDF');
  select * into r from public.remove_quotation_media(ua, qa2, 'quotation_pdf', bucket, null);
  perform pg_temp.assert_true(r.outcome = 'quotation_not_found', 'deleted quotation cannot remove PDF');
end;
$cases$;

select 'QUOTATION_PRIVATE_MEDIA_ROLLBACK_SOURCE_PASS' as result;
rollback;

do $postflight$
begin
  if to_regprocedure('public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)') is not null
     or to_regprocedure('public.remove_quotation_media(uuid,uuid,text,text,uuid)') is not null
     or exists (select 1 from auth.users where id in (
       '9a9a0000-0000-4000-8000-00000000000a'::uuid,
       '9a9a0000-0000-4000-8000-00000000000b'::uuid))
     or exists (select 1 from public.quotations where id in (
       '9a9a0000-0000-4000-8000-0000000000a1'::uuid,
       '9a9a0000-0000-4000-8000-0000000000a2'::uuid,
       '9a9a0000-0000-4000-8000-0000000000b1'::uuid))
     or exists (select 1 from public.media_objects
       where bucket = 'quotation-media-validation.invalid') then
    raise exception 'Quotation media validation rollback left hosted residue';
  end if;
end;
$postflight$;
select 'QUOTATION_PRIVATE_MEDIA_ROLLBACK_RESTORED' as result;
