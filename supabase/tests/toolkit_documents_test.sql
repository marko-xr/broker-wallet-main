-- Toolkit cloud documents: the table, its row level security and its
-- service-role-only functions.
--
--   * no client role can write, call a function, read the bucket / object key,
--     read another account's row or any pending / deleted row;
--   * the object key is pinned to profiles/<owner>/toolkit-documents/<id>.pdf;
--   * authorize, confirm, rename, delete are idempotent, serialized per account
--     and refuse another account's id (cross-account probes read as "not found");
--   * a deleted id is never re-created, an abandoned upload leaves no tombstone and is
--     removed claim-first, so cleanup can never delete a ready document's object;
--   * the anti-abuse limits hold and the hard ceilings fail closed;
--   * a superseded session (Single Active Device) reads nothing.
--
-- Run with `supabase test db` against the local stack. Writes run as postgres
-- here, standing in for the Worker's service_role calls; the client-side checks
-- switch to the `authenticated` and `anon` roles.
begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(195);

insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values
  ('c1c10000-0000-4000-8000-00000000000a', 'toolkit-a@example.test', '{"name":"A"}'::jsonb, now(), now()),
  ('c1c10000-0000-4000-8000-00000000000b', 'toolkit-b@example.test', '{"name":"B"}'::jsonb, now(), now());
insert into auth.sessions (id, user_id, created_at, updated_at)
values
  ('c1c10000-0000-4000-8000-0000000000a1', 'c1c10000-0000-4000-8000-00000000000a', now(), now()),
  ('c1c10000-0000-4000-8000-0000000000a2', 'c1c10000-0000-4000-8000-00000000000a', now(), now()),
  ('c1c10000-0000-4000-8000-0000000000b1', 'c1c10000-0000-4000-8000-00000000000b', now(), now());

-- authorize with the default (production-like) limits; returns the outcome.
create function pg_temp.authz(
  p_user uuid, p_doc uuid, p_type text default 'scanner', p_size bigint default 1000,
  p_sha text default 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  p_bucket text default 'test-bucket',
  p_max_doc bigint default 52428800, p_max_account bigint default 1073741824,
  p_max_docs integer default 1000, p_max_pending integer default 5,
  p_max_hour integer default 120, p_max_attempts integer default 10,
  p_title text default 'Test document', p_source timestamptz default now(),
  p_ctype text default 'application/pdf', p_max_image bigint default 26214400,
  p_ack boolean default false
) returns text language sql as $$
  select a.outcome from public.authorize_toolkit_document_upload(
    p_user, p_doc, p_type, p_ctype, p_title, p_size,
    case when p_ctype = 'application/pdf' then 3 else 1 end, p_sha, p_source, p_bucket,
    p_max_doc, p_max_image, p_max_account, p_max_docs, p_max_pending, p_max_hour,
    p_max_attempts, p_ack) as a;
$$;
create function pg_temp.conf(
  p_user uuid, p_doc uuid, p_size bigint default 1000, p_bucket text default 'test-bucket',
  p_ctype text default 'application/pdf', p_verified boolean default false
) returns text language sql as $$
  select c.outcome from public.confirm_toolkit_document_upload(
    p_user, p_doc, p_bucket, p_size, p_ctype, '"etag-1"', p_verified) as c;
$$;
create function pg_temp.del(
  p_user uuid, p_doc uuid, p_expected text default null, p_bucket text default 'test-bucket'
) returns text language sql as $$
  select b.outcome from public.begin_toolkit_document_delete(p_user, p_doc, p_bucket, p_expected) as b;
$$;
create function pg_temp.fin(
  p_user uuid, p_doc uuid, p_age integer default 0, p_bucket text default 'test-bucket'
) returns text language sql as $$
  select f.outcome from public.finalize_toolkit_document_delete(p_user, p_doc, p_bucket, p_age) as f;
$$;
create function pg_temp.claim(
  p_user uuid, p_doc uuid, p_cutoff timestamptz, p_bucket text default 'test-bucket', p_lease integer default 900
) returns text language sql as $$
  select c.outcome from public.claim_abandoned_toolkit_document(p_user, p_doc, p_bucket, p_cutoff, p_lease) as c;
$$;
create function pg_temp.discard(
  p_user uuid, p_doc uuid, p_claimed timestamptz, p_bucket text default 'test-bucket'
) returns text language sql as $$
  select f.outcome from public.discard_abandoned_toolkit_document(p_user, p_doc, p_bucket, p_claimed) as f;
$$;
-- A document uploaded and confirmed (ready).
create function pg_temp.ready_doc(p_user uuid, p_doc uuid, p_type text default 'scanner', p_size bigint default 1000)
returns text language sql as $$
  select pg_temp.authz(p_user, p_doc, p_type, p_size) || '/' || pg_temp.conf(p_user, p_doc, p_size);
$$;

-- ---------------------------------------------------------------------------
-- Structure and privileges
-- ---------------------------------------------------------------------------

select ok((select relrowsecurity from pg_class where oid = 'public.toolkit_documents'::regclass),
  'row level security is enabled');
select has_index('public', 'toolkit_documents', 'toolkit_documents_owner_idx', 'account listing index');
select has_index('public', 'toolkit_documents', 'toolkit_documents_pending_upload_idx', 'abandoned upload index');
select has_index('public', 'toolkit_documents', 'toolkit_documents_deleting_idx', 'delete sweep index');
select has_trigger('public', 'toolkit_documents', 'toolkit_documents_bump_sync_version', 'version bump trigger');
select has_trigger('public', 'toolkit_documents', 'toolkit_documents_guard_insert', 'insert guard trigger');
select has_trigger('public', 'toolkit_documents', 'toolkit_documents_guard_update', 'update guard trigger');
select ok(to_regprocedure('public.authorize_toolkit_document_upload(uuid,uuid,text,text,text,bigint,integer,text,timestamptz,text,bigint,bigint,bigint,integer,integer,integer,integer,boolean)') is not null
  and to_regprocedure('public.confirm_toolkit_document_upload(uuid,uuid,text,bigint,text,text,boolean)') is not null
  and to_regprocedure('public.toolkit_document_object_key(uuid,uuid,text)') is not null
  and to_regclass('public.toolkit_document_account_state') is not null
  and to_regprocedure('public.rename_toolkit_document(uuid,uuid,text,bigint)') is not null
  and to_regprocedure('public.begin_toolkit_document_delete(uuid,uuid,text,text)') is not null
  and to_regprocedure('public.finalize_toolkit_document_delete(uuid,uuid,text,integer)') is not null
  and to_regprocedure('public.discard_abandoned_toolkit_document(uuid,uuid,text,timestamptz)') is not null
  and to_regprocedure('public.claim_abandoned_toolkit_document(uuid,uuid,text,timestamptz,integer)') is not null
  and to_regprocedure('public.list_toolkit_documents(uuid,text,integer,timestamptz,uuid,text)') is not null
  and to_regprocedure('public.get_toolkit_document(uuid,uuid)') is not null
  and to_regprocedure('public.toolkit_document_statuses(uuid,text,uuid[])') is not null
  and to_regprocedure('public.toolkit_document_usage(uuid)') is not null
  and to_regprocedure('public.list_toolkit_document_cleanup(text,text,timestamptz,integer)') is not null
  and to_regprocedure('public.purge_toolkit_document_tombstone(uuid,uuid,timestamptz)') is not null,
  'all Toolkit document functions exist');

select ok(not has_table_privilege('anon', 'public.toolkit_documents', 'select,insert,update,delete,truncate,references,trigger'),
  'anon has no table privilege');
select ok(not has_table_privilege('authenticated', 'public.toolkit_documents', 'insert,update,delete,truncate,references,trigger'),
  'authenticated holds no write privilege on the table');
select ok(not has_table_privilege('service_role', 'public.toolkit_documents', 'select,insert,update,delete,truncate'),
  'service_role reaches the table only through the functions');
select ok(has_column_privilege('authenticated', 'public.toolkit_documents', 'title', 'select')
  and has_column_privilege('authenticated', 'public.toolkit_documents', 'size_bytes', 'select'),
  'authenticated can read the safe columns');
select ok(not has_column_privilege('authenticated', 'public.toolkit_documents', 'object_key', 'select')
  and not has_column_privilege('authenticated', 'public.toolkit_documents', 'bucket', 'select')
  and not has_column_privilege('authenticated', 'public.toolkit_documents', 'observed_etag', 'select')
  and not has_column_privilege('authenticated', 'public.toolkit_documents', 'upload_attempts', 'select')
  and not has_column_privilege('authenticated', 'public.toolkit_documents', 'last_authorized_at', 'select'),
  'authenticated cannot read the bucket, the object key or server bookkeeping');
select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute')
                   and not has_function_privilege('authenticated', p.oid, 'execute')
                   and has_function_privilege('service_role', p.oid, 'execute'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('authorize_toolkit_document_upload', 'confirm_toolkit_document_upload',
       'rename_toolkit_document', 'begin_toolkit_document_delete', 'finalize_toolkit_document_delete',
       'discard_abandoned_toolkit_document', 'claim_abandoned_toolkit_document',
       'list_toolkit_documents', 'get_toolkit_document', 'toolkit_document_statuses',
       'toolkit_document_usage', 'list_toolkit_document_cleanup', 'purge_toolkit_document_tombstone',
       'toolkit_document_rules', 'toolkit_document_object_key')),
  'every Toolkit function is service_role only');
select ok(not has_function_privilege('authenticated', 'public.guard_toolkit_document()', 'execute')
  and not has_function_privilege('anon', 'public.guard_toolkit_document()', 'execute'),
  'the guard trigger function is not callable by clients');
select is((select string_agg(r.file_extension, ',' order by r.file_extension)
  from (select (public.toolkit_document_rules(t)).file_extension
        from unnest(array['application/pdf', 'image/jpeg', 'image/png']) as t) as r),
  'jpg,pdf,png', 'PDF, JPEG and PNG are the accepted formats');
select is((select count(*)::int from public.toolkit_document_rules('image/gif')), 0, 'a GIF is not accepted');
select is((select count(*)::int from public.toolkit_document_rules('application/pdf; charset=x')), 0,
  'a content type with parameters is not accepted');
select is(public.toolkit_document_object_key('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', 'application/pdf'),
  'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000d1.pdf',
  'the object key shape is exact and inside the account prefix');
select is(public.toolkit_document_object_key('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', 'image/jpeg'),
  'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000d1.jpg',
  'a JPEG key ends in .jpg');
select is(public.toolkit_document_object_key('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', 'text/html'), null, 'an unaccepted type has no key');
select ok(not has_table_privilege('authenticated', 'public.toolkit_document_account_state', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.toolkit_document_account_state', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.toolkit_document_account_state', 'select,insert,update,delete')
  and (select relrowsecurity from pg_class where oid = 'public.toolkit_document_account_state'::regclass),
  'the tombstone-floor table is internal: RLS on, no role has access');
select ok(has_column_privilege('authenticated', 'public.toolkit_documents', 'content_type', 'select')
  and has_column_privilege('authenticated', 'public.toolkit_documents', 'sha256_verified', 'select')
  and not has_column_privilege('authenticated', 'public.toolkit_documents', 'sha256_verified', 'update'),
  'a client may read the format and the verification flag, never write it');

-- ---------------------------------------------------------------------------
-- authorize
-- ---------------------------------------------------------------------------

select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'created', 'a first authorize creates the pending row');
select is((select object_key from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000d1.pdf',
  'the stored key is exactly the account-prefixed key');
select is((select status || ':' || version || ':' || upload_attempts from public.toolkit_documents
  where id = 'c1c10000-0000-4000-8000-0000000000d1'), 'pending_upload:1:1',
  'pending, version 1, one attempt');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'resumed', 'the same authorize again is a retry');
select is((select upload_attempts from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  2, 'the retry is counted');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', p_size => 2000),
  'idempotency_mismatch', 'the same id with another size is refused');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', p_type => 'signature'),
  'idempotency_mismatch', 'the same id for another tool is refused');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', p_sha => repeat('b', 64)),
  'idempotency_mismatch', 'the same id with another hash is refused');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', p_ctype => 'image/png'),
  'idempotency_mismatch', 'the same id as another format is refused');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d1'),
  'id_unavailable', 'another account cannot take or probe an existing id');
select is((select owner_id from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'c1c10000-0000-4000-8000-00000000000a'::uuid, 'the owner never changed');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_size => 4096, p_max_doc => 2048),
  'too_large', 'a file above the per-document limit is refused');
select is((select count(*)::int from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d2'),
  0, 'a refused authorize leaves no row');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_size => 1500, p_max_account => 2000),
  'storage_limit', 'the account byte limit counts what is already stored');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_max_docs => 1),
  'document_limit', 'the document count limit holds');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_max_pending => 1),
  'too_many_pending', 'only a few uploads may wait');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_max_hour => 1),
  'rate_limited', 'new documents are rate limited per hour');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', p_max_attempts => 2),
  'rate_limited', 'one pending upload cannot be re-authorized without end');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_type => 'notes')$$,
  'P0001', 'Invalid Toolkit document request', 'an unknown tool is refused');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_sha => 'XYZ')$$,
  'P0001', 'Invalid Toolkit document request', 'a malformed hash is refused');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_sha => null)$$,
  'P0001', 'Invalid Toolkit document request', 'the device digest is required');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_source => null)$$,
  'P0001', 'Invalid Toolkit document request', 'the device creation time is required');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_ctype => 'image/gif')$$,
  'P0001', 'Invalid Toolkit document request', 'an unaccepted format is refused');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_ctype => 'application/pdf; x=1')$$,
  'P0001', 'Invalid Toolkit document request', 'a format with parameters is refused');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', 'signature', p_ctype => 'image/jpeg')$$,
  'P0001', 'Invalid Toolkit document request', 'only the Scanner may store an image');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', 'combine_pdfs', p_ctype => 'image/png')$$,
  'P0001', 'Invalid Toolkit document request', 'a PDF tool cannot store a PNG');
select throws_ok(
  $$select * from public.authorize_toolkit_document_upload(
      'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', 'scanner', 'image/jpeg', 'T',
      10, 4, repeat('a', 64), now(), 'test-bucket', 1000, 1000, 100000, 10, 2, 10, 5, false)$$,
  'P0001', 'Invalid Toolkit document request', 'an image is one page');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_max_image => 99999999)$$,
  'P0001', 'Invalid Toolkit document limits', 'an image limit above its ceiling fails closed');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e1', 'scanner',
    p_size => 3000, p_ctype => 'image/jpeg'), 'created', 'the Scanner stores a JPEG scan');
select is((select content_type || ':' || document_type || ':' || object_key from public.toolkit_documents
    where id = 'c1c10000-0000-4000-8000-0000000000e1'),
  'image/jpeg:scanner:profiles/c1c10000-0000-4000-8000-00000000000b/toolkit-documents/c1c10000-0000-4000-8000-0000000000e1.jpg',
  'the format and the source tool are separate fields and the key ends .jpg');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e2', 'scanner',
    p_size => 3000, p_ctype => 'image/png'), 'created', 'the Scanner stores a PNG scan');
select is((select object_key from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000e2'),
  'profiles/c1c10000-0000-4000-8000-00000000000b/toolkit-documents/c1c10000-0000-4000-8000-0000000000e2.png',
  'a PNG key ends .png');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e3', 'scanner',
    p_size => 30000000, p_ctype => 'image/png'), 'too_large', 'an image has its own, smaller, size limit');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e3', 'scanner',
    p_size => 30000000), 'created', 'a PDF of that size is still within the PDF limit');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e1', 3000,
    'test-bucket', 'image/png'), 'type_mismatch', 'a stored type that is not the declared one is not confirmed');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e1', 3000,
    'test-bucket', 'image/jpeg', true), 'confirmed', 'the declared type confirms');
select is((select sha256_verified from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000e1'),
  true, 'the verification flag records that the Worker hashed the object');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e2', 3000,
    'test-bucket', 'image/png', false), 'confirmed', 'a confirmation without a Worker-side digest is allowed');
select is((select sha256_verified from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000e2'),
  false, 'and is recorded as only device-declared');
select throws_ok(
  $$update public.toolkit_documents set sha256_verified = true where id = 'c1c10000-0000-4000-8000-0000000000e2'$$,
  'P0001', 'The verification flag is set only when a document becomes ready',
  'the verification flag cannot be raised after the fact');
select throws_ok(
  $$update public.toolkit_documents set sha256_verified = false where id = 'c1c10000-0000-4000-8000-0000000000e1'$$,
  'P0001', 'The verification flag is set only when a document becomes ready',
  'nor cleared');
select throws_ok(
  $$update public.toolkit_documents set content_type = 'image/png' where id = 'c1c10000-0000-4000-8000-0000000000e1'$$,
  'P0001', 'Toolkit document identity is immutable', 'the format is frozen');
select throws_ok(
  $$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_max_doc => 999999999999)$$,
  'P0001', 'Invalid Toolkit document limits', 'a limit above the hard ceiling fails closed');
select throws_ok(
  format($$select pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d2', p_title => %L)$$,
    'Evil ' || chr(8238) || 'fdp.exe'),
  '23514', null, 'a bidi override in a title is refused by the table');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3',
    p_source => now() + interval '30 days'),
  'created', 'a document with a far-future device clock is still accepted');
select ok((select source_created_at <= now() + interval '1 minute' from public.toolkit_documents
  where id = 'c1c10000-0000-4000-8000-0000000000d3'), 'a far-future creation time is not believed');

-- ---------------------------------------------------------------------------
-- confirm
-- ---------------------------------------------------------------------------

select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 999),
  'size_mismatch', 'an object of another size is not confirmed');
select is((select status from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'pending_upload', 'it stays pending');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d1'),
  'not_found', 'another account cannot confirm it');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 1000, 'other-bucket'),
  'not_found', 'a different bucket is not the document');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'confirmed', 'the right size confirms');
select is((select status || ':' || (confirmed_at is not null) || ':' || observed_etag
  from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'ready:true:"etag-1"', 'ready with its confirmation time and etag');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'already_confirmed', 'a retried confirm is idempotent');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'already_ready', 'a retried save of a ready document uploads nothing');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000ff'),
  'not_found', 'an unknown id is not found');

-- ---------------------------------------------------------------------------
-- rename
-- ---------------------------------------------------------------------------

select is((select r.outcome || ':' || r.title || ':' || r.version from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 'Renamed', 3) as r),
  'renamed:Renamed:4', 'a rename at the current version succeeds and bumps it');
select is((select r.outcome || ':' || r.title || ':' || r.version from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 'Other', 3) as r),
  'stale_version:Renamed:4', 'a stale rename is refused and shows the current title');
select is((select r.outcome || ':' || r.version from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 'Renamed', 1) as r),
  'renamed:4', 'renaming to the title it already has is a no-op, whatever the version');
select is((select r.outcome from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d1', 'Mine now', 4) as r),
  'not_found', 'another account cannot rename it');
select is((select r.outcome from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'Pending renamed', 1) as r),
  'renamed', 'a pending upload can be renamed');
select throws_ok(
  $$select * from public.rename_toolkit_document('c1c10000-0000-4000-8000-00000000000a',
      'c1c10000-0000-4000-8000-0000000000d1', '  padded  ', 4)$$,
  '23514', null, 'a title with surrounding spaces is refused');

-- ---------------------------------------------------------------------------
-- delete: mark, finalize, tombstone
-- ---------------------------------------------------------------------------

select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d1'),
  'not_found', 'another account cannot delete it');
select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 'pending_upload'),
  'status_changed', 'a guarded delete does not act on a document that moved on');
select is((select status from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'ready', 'it is untouched');
select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'marked', 'a ready document is marked for deletion');
select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'already_pending', 'a retried delete is idempotent');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'document_deleted', 'a document being deleted cannot be re-authorized');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'document_deleted', 'nor confirmed');
select is((select r.outcome from public.rename_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 'Back', 3) as r),
  'document_deleted', 'nor renamed');
select is(pg_temp.fin('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 900),
  'too_soon', 'the tombstone waits while a signed upload could still be live');
select is(pg_temp.fin('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 0),
  'deleted', 'finalize writes the tombstone');
select is((select title from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d1'),
  'Deleted document', 'the tombstone no longer carries the user''s title');
select is(pg_temp.fin('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', 0),
  'already_deleted', 'a retried finalize is idempotent');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'document_deleted', 'a deleted id is never resurrected');
select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'already_deleted', 'deleting a tombstone is idempotent');
select is(pg_temp.fin('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 0),
  'not_pending', 'only a document marked for deletion can be finalized');
-- An abandoned upload is removed CLAIM-FIRST and leaves no tombstone: the id stays usable.
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', now() - interval '1 day'),
  'not_abandoned', 'a recently authorized upload cannot be claimed');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1', now() + interval '1 day'),
  'not_abandoned', 'a deleted document is not an abandoned upload');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d3', now() + interval '1 day'),
  'not_found', 'another account cannot claim it');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', now() + interval '1 day', 'other-bucket'),
  'not_found', 'nor can another bucket''s Worker');
select throws_ok(
  $$select * from public.claim_abandoned_toolkit_document('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'test-bucket', now(), 30)$$,
  'P0001', 'Invalid Toolkit document claim', 'a lease shorter than a minute is refused');
create temp table claim_d3 as
  select * from public.claim_abandoned_toolkit_document('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'test-bucket', now() + interval '1 day', 900);
select is((select outcome from claim_d3), 'claimed', 'an idle upload is claimed');
select is((select object_key from claim_d3), 'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000d3.pdf', 'the claim returns the key to remove');
select is((select status from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d3'), 'pending_discard',
  'the row is now pending_discard');
select is((select discard_claimed_at from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d3'),
  (select claimed_at from claim_d3), 'the claim identity is recorded on the row');
select is(pg_temp.conf('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3'), 'cleanup_in_progress', 'a claimed upload can never be confirmed');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3'), 'cleanup_in_progress', 'nor authorized again');
select is((select r.outcome from public.rename_toolkit_document('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'Renamed', 1) as r),
  'cleanup_in_progress', 'nor renamed');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', now() + interval '1 day'), 'claim_held',
  'a second cleanup is held off while the lease is valid');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', now() - interval '1 hour'), 'not_claimed',
  'a discard with another claim identity does nothing');
select is((select count(*)::int from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d3'), 1, 'the row is still there');
select throws_ok(
  $$update public.toolkit_documents set status = 'ready', confirmed_at = now() where id = 'c1c10000-0000-4000-8000-0000000000d3'$$,
  'P0001', null, 'a claimed upload cannot be made ready, even by the server');
-- The cleanup that held the claim never finished: after the lease another one takes over.
update public.toolkit_documents set discard_claimed_at = now() - interval '1 hour' where id = 'c1c10000-0000-4000-8000-0000000000d3';
create temp table claim_d3b as
  select * from public.claim_abandoned_toolkit_document('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'test-bucket', now() + interval '1 day', 900);
select is((select outcome from claim_d3b), 'claimed', 'an unfinished cleanup is taken over after its lease');
select isnt((select claimed_at from claim_d3b), (select claimed_at from claim_d3), 'under a new claim identity');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', (select claimed_at from claim_d3)), 'not_claimed',
  'the earlier cleanup can no longer discard the row');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000d3', (select claimed_at from claim_d3b)), 'not_found',
  'another account cannot discard it');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', (select claimed_at from claim_d3b), 'other-bucket'), 'not_found',
  'nor can another bucket''s Worker');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', (select claimed_at from claim_d3b)), 'discarded',
  'the current claim removes the row, without a tombstone');
select is((select count(*)::int from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d3'),
  0, 'no row remains');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3'),
  'created', 'a slow device can still upload that document later');

-- The user deletes a document while its abandoned-upload cleanup holds the claim.
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c1'), 'created', 'a second pending upload exists');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c1', now() + interval '1 day'), 'claimed', 'and its cleanup claims it');
create temp table claim_c1 as
  select discard_claimed_at as claimed_at from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000c1';
select is(pg_temp.del('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c1'), 'marked', 'a user delete overrides the claim');
select is((select status || '/' || (discard_claimed_at is null)::text from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000c1'),
  'pending_delete/true', 'the row is pending_delete and the claim is gone');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c1', (select claimed_at from claim_c1)), 'not_claimed',
  'the cleanup that held the claim cannot remove the document that is being deleted');

-- A ready document can be neither claimed nor discarded: its object is never at risk.
select is(pg_temp.ready_doc('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c2'), 'created/confirmed', 'a ready document exists');
select is(pg_temp.claim('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c2', now() + interval '1 day'), 'not_abandoned',
  'a ready document is never claimed, whatever the cutoff');
select is(pg_temp.discard('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000c2', now()), 'not_claimed', 'nor discarded');
select is((select status from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000c2'), 'ready', 'it stays ready');

-- Constraints and listings.
select throws_ok(
  $$update public.toolkit_documents set status = 'pending_discard' where id = 'c1c10000-0000-4000-8000-0000000000d3'$$,
  '23514', null, 'a claimed status needs its claim identity');
create temp table claim_d3c as
  select * from public.claim_abandoned_toolkit_document('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3', 'test-bucket', now() + interval '1 day', 900);
update public.toolkit_documents set discard_claimed_at = now() - interval '1 hour' where id = 'c1c10000-0000-4000-8000-0000000000d3';
select is((select count(*)::int from public.list_toolkit_document_cleanup('stuck_discard', 'test-bucket', now() - interval '15 minutes', 10)
    where id = 'c1c10000-0000-4000-8000-0000000000d3'), 1, 'a claim older than the lease is listed as stuck');
select is((select count(*)::int from public.list_toolkit_document_cleanup('abandoned_pending', 'test-bucket', now() + interval '1 day', 10)
    where id = 'c1c10000-0000-4000-8000-0000000000d3'), 0, 'a claimed row is not listed as a new abandoned upload');
-- Back to the state the later sections expect: no extra rows, d3 a fresh pending upload.
delete from public.toolkit_documents where id in ('c1c10000-0000-4000-8000-0000000000c1', 'c1c10000-0000-4000-8000-0000000000c2', 'c1c10000-0000-4000-8000-0000000000d3');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d3'), 'created', 'the id is usable again after cleanup');

-- ---------------------------------------------------------------------------
-- The guard: identity is frozen, status only moves forward
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update public.toolkit_documents set owner_id = 'c1c10000-0000-4000-8000-00000000000b'
    where id = 'c1c10000-0000-4000-8000-0000000000d3'$$,
  'P0001', 'Toolkit document identity is immutable', 'a document cannot be reassigned to another account');
select throws_ok(
  $$update public.toolkit_documents set object_key = 'profiles/x/toolkit-documents/y.pdf'
    where id = 'c1c10000-0000-4000-8000-0000000000d3'$$,
  'P0001', 'Toolkit document identity is immutable', 'a document cannot be re-pointed at another object');
select throws_ok(
  $$update public.toolkit_documents set status = 'deleted'
    where id = 'c1c10000-0000-4000-8000-0000000000d3'$$,
  'P0001', null, 'a pending upload cannot jump to deleted');
select throws_ok(
  $$update public.toolkit_documents set status = 'ready'
    where id = 'c1c10000-0000-4000-8000-0000000000d1'$$,
  'P0001', null, 'a deleted document cannot come back');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key, status, confirmed_at)
    values ('c1c10000-0000-4000-8000-0000000000f5', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000f5.pdf', 'ready', now())$$,
  'P0001', null, 'a row cannot be created already ready');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000f6', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000b/toolkit-documents/c1c10000-0000-4000-8000-0000000000f6.pdf')$$,
  '23514', null, 'a key inside another account''s prefix is refused');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000f7', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/offers/c1c10000-0000-4000-8000-0000000000f7.pdf')$$,
  '23514', null, 'a key outside the Toolkit segment is refused');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000f8', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'image/jpeg', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000f8.pdf')$$,
  '23514', null, 'a JPEG with a .pdf key (a forged extension) is refused');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000f9', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000f9.png')$$,
  '23514', null, 'a PDF with a .png key is refused');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000fa', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'image/gif', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000fa.gif')$$,
  '23514', null, 'an unaccepted format is refused by the table');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000fb', 'c1c10000-0000-4000-8000-00000000000a', 'signature', 'image/png', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000fb.png')$$,
  '23514', null, 'the table also refuses an image from a PDF tool');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000fc', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000fc.pdf')$$,
  '23502', null, 'the device digest cannot be omitted');

-- ---------------------------------------------------------------------------
-- Reads, pagination, cleanup
-- ---------------------------------------------------------------------------

select is(pg_temp.ready_doc('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000f1', 'combine_pdfs', 3000), 'created/confirmed', 'ready doc f1');
select is(pg_temp.ready_doc('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000f2', 'signature', 4000), 'created/confirmed', 'ready doc f2');
select is(pg_temp.ready_doc('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000f9', 'scanner', 5000), 'created/confirmed', 'ready doc of B');
-- Test setup only: the guard freezes created_at for every role.
alter table public.toolkit_documents disable trigger toolkit_documents_guard_update;
update public.toolkit_documents set created_at = now() - interval '2 hours'
  where id = 'c1c10000-0000-4000-8000-0000000000f1';
update public.toolkit_documents set created_at = now() - interval '1 hour'
  where id = 'c1c10000-0000-4000-8000-0000000000f2';
alter table public.toolkit_documents enable trigger toolkit_documents_guard_update;
select is((select string_agg(l.id::text, ',' order by l.created_at desc, l.id desc)
  from public.list_toolkit_documents('c1c10000-0000-4000-8000-00000000000a', 'test-bucket', 10, null, null, null) as l),
  'c1c10000-0000-4000-8000-0000000000f2,c1c10000-0000-4000-8000-0000000000f1',
  'the list is the account''s ready documents, newest first (no pending, no deleted, none of B''s)');
select is((select count(*)::int from public.list_toolkit_documents(
    'c1c10000-0000-4000-8000-00000000000a', 'test-bucket', 1, now() - interval '90 minutes', 'ffffffff-ffff-4fff-8fff-ffffffffffff', null)),
  1, 'the keyset cursor continues after the previous page');
select is((select l.id from public.list_toolkit_documents(
    'c1c10000-0000-4000-8000-00000000000a', 'test-bucket', 10, null, null, 'combine_pdfs') as l),
  'c1c10000-0000-4000-8000-0000000000f1'::uuid, 'the list can be filtered by tool');
select is((select count(*)::int from public.list_toolkit_documents(
    'c1c10000-0000-4000-8000-00000000000a', 'other-bucket', 10, null, null, null)),
  0, 'a Worker bound to another bucket lists nothing of this bucket (staging and production share the database)');
select is((select count(*)::int from public.toolkit_document_statuses('c1c10000-0000-4000-8000-00000000000a',
    'other-bucket', array['c1c10000-0000-4000-8000-0000000000f1']::uuid[])),
  0, 'nor reads its statuses');
select is((select count(*)::int from public.list_toolkit_document_cleanup('old_tombstones', 'other-bucket', now() + interval '1 day', 10)),
  0, 'nor sweeps its rows');
select is((select count(*)::int from public.get_toolkit_document(
    'c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000f1')),
  0, 'another account cannot read a document by id');
select is((select count(*)::int from public.toolkit_document_statuses('c1c10000-0000-4000-8000-00000000000a', 'test-bucket',
    array['c1c10000-0000-4000-8000-0000000000f1', 'c1c10000-0000-4000-8000-0000000000f9',
          'c1c10000-0000-4000-8000-0000000000ee']::uuid[])),
  1, 'status lookups answer only for the account''s own ids');
select is((select u.ready_count || ':' || u.ready_bytes from public.toolkit_document_usage('c1c10000-0000-4000-8000-00000000000a') as u),
  '2:7000', 'usage counts the account''s ready documents and bytes');
update public.toolkit_documents set last_authorized_at = now() - interval '2 days'
  where id = 'c1c10000-0000-4000-8000-0000000000d3';
select is((select count(*)::int from public.list_toolkit_document_cleanup('abandoned_pending', 'test-bucket', now() - interval '1 day', 10)),
  1, 'an upload not touched for a day is a cleanup candidate');
select is((select count(*)::int from public.list_toolkit_document_cleanup('old_tombstones', 'test-bucket', now() + interval '1 day', 10)),
  1, 'tombstones are listed once old enough');
select ok(not public.purge_toolkit_document_tombstone('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', now() - interval '1 day'),
  'a recent tombstone is kept');
select ok(public.purge_toolkit_document_tombstone('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', now() + interval '1 day'),
  'an old tombstone is purged');

-- A purged tombstone must not let the deleted document come back: the account's
-- tombstone floor now stands at the deletion time of d1 (this transaction's now()).
select is((select count(*)::int from public.toolkit_document_account_state
    where owner_id = 'c1c10000-0000-4000-8000-00000000000a'), 1, 'purging recorded a tombstone floor');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d1'),
  'stale_document', 'the purged document cannot be re-created by a device that made it earlier');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d8',
    p_source => now() - interval '2 days'), 'stale_document', 'nor can any older queued document');
select is((select count(*)::int from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000d8'),
  0, 'a refusal creates nothing');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d8',
    p_source => now() - interval '2 days', p_ack => true), 'created',
  'an explicit user acknowledgement allows an old, never-synced document');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000a', 'c1c10000-0000-4000-8000-0000000000d9',
    p_source => now() + interval '5 minutes'), 'created', 'a document made after the floor is unaffected');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000da',
    p_source => now() - interval '2 days'), 'created', 'another account has no floor');
select ok(public.purge_toolkit_document_tombstone('c1c10000-0000-4000-8000-00000000000a',
    'c1c10000-0000-4000-8000-0000000000d1', now()) is false, 'purging nothing changes nothing');
select is((select count(*)::int from public.toolkit_document_account_state
    where owner_id = 'c1c10000-0000-4000-8000-00000000000a'
      and tombstone_floor <= now()), 1, 'the floor is the deletion time, never in the future');

-- An account that churns documents cannot grow the table without limit: it keeps
-- at most 500 tombstones, and the early purge advances its floor so none of the
-- purged documents can come back.
insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
values ('c1c10000-0000-4000-8000-00000000000c', 'toolkit-c@example.test', '{"name":"C"}'::jsonb, now(), now());
create function pg_temp.churn(p_user uuid, p_count integer) returns integer language plpgsql as $$
declare
  v_id uuid;
begin
  for i in 1..p_count loop
    v_id := ('c1c1ccc0-0000-4000-8000-' || lpad(to_hex(i), 12, '0'))::uuid;
    perform pg_temp.authz(p_user, v_id, p_max_hour => 1000);
    perform pg_temp.del(p_user, v_id);
    perform pg_temp.fin(p_user, v_id, 0);
  end loop;
  return p_count;
end;
$$;
select is(pg_temp.churn('c1c10000-0000-4000-8000-00000000000c', 502), 502,
  'an account creates and deletes 502 documents');
select is((select count(*)::int from public.toolkit_documents
    where owner_id = 'c1c10000-0000-4000-8000-00000000000c' and status = 'deleted'),
  500, 'it keeps at most 500 tombstones');
select is((select count(*)::int from public.toolkit_document_account_state
    where owner_id = 'c1c10000-0000-4000-8000-00000000000c'), 1,
  'the early purge advanced its tombstone floor');
select is((select count(*)::int from public.toolkit_documents
    where owner_id = 'c1c10000-0000-4000-8000-00000000000a' and status = 'deleted'), 0,
  'another account''s history is untouched (its own tombstone was purged earlier, by retention)');
select is(pg_temp.authz('c1c10000-0000-4000-8000-00000000000c', 'c1c1ccc0-0000-4000-8000-000000000001',
    p_source => now() - interval '1 day'), 'stale_document',
  'a document whose tombstone was purged early still cannot come back');

-- ---------------------------------------------------------------------------
-- Row level security as a signed-in client
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1c10000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims',
  '{"sub":"c1c10000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"c1c10000-0000-4000-8000-0000000000a1"}', true);
select ok(public.claim_current_app_session(), 'A claims the active session');
select is((select count(*)::int from public.toolkit_documents), 2,
  'A reads exactly their own ready documents');
select is((select count(*)::int from public.toolkit_documents where owner_id = 'c1c10000-0000-4000-8000-00000000000b'),
  0, 'A cannot read B''s document');
select is((select count(*)::int from public.toolkit_documents where status <> 'ready'),
  0, 'A reads no pending or deleted row');
select throws_ok($$select object_key from public.toolkit_documents$$,
  '42501', null, 'A cannot read the object key');
select throws_ok($$select bucket from public.toolkit_documents$$,
  '42501', null, 'A cannot read the bucket');
select throws_ok($$select * from public.toolkit_document_account_state$$,
  '42501', null, 'A cannot read the tombstone floor');
select is((select string_agg(content_type, ',' order by id) from public.toolkit_documents),
  'application/pdf,application/pdf', 'A reads the format of their documents');
select throws_ok(
  $$insert into public.toolkit_documents (id, owner_id, document_type, content_type, content_sha256, title, size_bytes, bucket, object_key)
    values ('c1c10000-0000-4000-8000-0000000000fd', 'c1c10000-0000-4000-8000-00000000000a', 'scanner', 'application/pdf', repeat('a', 64), 'T', 10, 'test-bucket',
    'profiles/c1c10000-0000-4000-8000-00000000000a/toolkit-documents/c1c10000-0000-4000-8000-0000000000fd.pdf')$$,
  '42501', null, 'A cannot create a row directly');
select throws_ok(
  $$update public.toolkit_documents set title = 'x' where id = 'c1c10000-0000-4000-8000-0000000000f1'$$,
  '42501', null, 'A cannot rename directly');
select throws_ok(
  $$update public.toolkit_documents set owner_id = 'c1c10000-0000-4000-8000-00000000000b'
    where id = 'c1c10000-0000-4000-8000-0000000000f1'$$,
  '42501', null, 'A cannot reassign a document');
select throws_ok(
  $$delete from public.toolkit_documents where id = 'c1c10000-0000-4000-8000-0000000000f1'$$,
  '42501', null, 'A cannot delete directly');
select throws_ok(
  $$select * from public.authorize_toolkit_document_upload(
      'c1c10000-0000-4000-8000-00000000000b', 'c1c10000-0000-4000-8000-0000000000e6', 'scanner', 'application/pdf', 'T',
      10, 1, repeat('a', 64), now(), 'test-bucket', 1000, 1000, 100000, 10, 2, 10, 5, false)$$,
  '42501', 'permission denied for function authorize_toolkit_document_upload',
  'A cannot call the authorize function');
select throws_ok(
  $$select * from public.list_toolkit_documents('c1c10000-0000-4000-8000-00000000000a', 'test-bucket', 10, null, null, null)$$,
  '42501', 'permission denied for function list_toolkit_documents',
  'A cannot call the Worker''s list function');
-- B has a ready document but no claimed session: the Single Active Device gate
-- reads nothing, and A's other (unclaimed) session does too.
select set_config('request.jwt.claims',
  '{"sub":"c1c10000-0000-4000-8000-00000000000a","role":"authenticated","session_id":"c1c10000-0000-4000-8000-0000000000a2"}', true);
select is((select count(*)::int from public.toolkit_documents), 0,
  'a superseded session reads nothing');
reset role;
set local role anon;
select throws_ok($$select count(*) from public.toolkit_documents$$,
  '42501', null, 'anon cannot read the table');
reset role;

-- ---------------------------------------------------------------------------
-- Account deletion removes the rows with the account
-- ---------------------------------------------------------------------------

delete from auth.users where id = 'c1c10000-0000-4000-8000-00000000000b';
select is((select count(*)::int from public.toolkit_documents where owner_id = 'c1c10000-0000-4000-8000-00000000000b'),
  0, 'deleting the account deletes its document rows (R2 is swept by the Worker first)');

select * from finish();
rollback;
