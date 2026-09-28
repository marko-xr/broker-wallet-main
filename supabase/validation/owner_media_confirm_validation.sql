-- =============================================================================
-- Broker Wallet: Owner media confirm function validation
--
-- Run in the Supabase SQL Editor as the default `postgres` role, or with
-- `psql -f`. Needs no pgTAP and no extension. It checks the same behavior as
-- supabase/tests/owner_media_confirm_test.sql against the real hosted
-- database, before the migration is applied for real.
--
-- The Owner counterpart of offer_media_confirm_validation.sql, check for
-- check, plus the refusal of media keyed as Offer media.
--
-- What it does:
--   1. pre-checks everything the migration and this script depend on;
--   2. installs the migration from its exact file text (only its own
--      `begin;` / `commit;` lines are left out, so it runs inside this
--      transaction; the Flutter test suite fails if this copy drifts);
--   3. exercises the function with temporary test accounts, Owner records and
--      media rows;
--   4. undoes all of it, twice over:
--        - inside the run: the install and every test step are in a savepoint
--          that is always rolled back before the report is written. The post
--          checks prove this;
--        - at the end: `rollback;` discards what is left (the report itself).
--      There is no COMMIT anywhere in this file.
--
-- Reading the result: the grid shows one row per check. Row 0 is the verdict:
--   PASSED - every check passed, and everything was undone.
--   FAILED - see the FAIL rows. Nothing was kept either way.
--
-- Safety:
--   * No real account, Owner or media row is written. Test accounts use
--     reserved ids and `.invalid` emails; test media rows use two bucket names
--     no Worker uses. The script refuses to run if any test id already exists.
--   * Nothing touches R2. The function does not either: it only reads and
--     writes these tables.
--   * Creating the test accounts fires the project's own auth.users trigger
--     (on_auth_user_created), which creates their profiles; both are rolled
--     back with everything else.
--   * Concurrency — two confirms racing for an Owner's last place — cannot be
--     shown in one session. It rests on the row lock the function takes on the
--     Owner (SELECT ... FOR UPDATE) before it counts. Verify it on a local
--     stack with two psql sessions (procedure at the end of this file), never
--     against hosted data.
-- =============================================================================

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table owner_media_validation_results (
  seq integer primary key,
  result text not null,
  check_name text not null,
  detail text
) on commit drop;

do $validation$
declare
  -- Reserved test identities.
  user_a constant uuid := '0e0e0000-0000-4000-8000-00000000000a';
  user_b constant uuid := '0e0e0000-0000-4000-8000-00000000000b';
  test_users constant uuid[] := array[user_a, user_b];
  test_email_domain constant text := '@owner-media-validation.invalid';
  owner_a1 constant uuid := '0e0e0000-0000-4000-8000-0000000000a1';
  owner_a2 constant uuid := '0e0e0000-0000-4000-8000-0000000000a2';
  owner_a3 constant uuid := '0e0e0000-0000-4000-8000-0000000000a3';
  owner_a4 constant uuid := '0e0e0000-0000-4000-8000-0000000000a4';
  owner_b1 constant uuid := '0e0e0000-0000-4000-8000-0000000000b1';
  test_owners constant uuid[] := array[owner_a1, owner_a2, owner_a3, owner_a4, owner_b1];
  test_bucket constant text := 'owner-media-validation.invalid';
  other_bucket constant text := 'owner-media-validation-other.invalid';
  fn constant text := 'public.confirm_owner_media_upload(uuid,uuid,uuid,text,integer,bigint,text,bigint)';

  results jsonb := '[]'::jsonb;
  stage text := 'starting';
  completed boolean := false;
  affected integer;
  detail_text text;
  flag boolean;
  failures integer;
  passes integer;
  i integer;
  outcome_text text;
  ordinal_value integer;
  media_1 uuid;
  media_2 uuid;
  media_3 uuid;
  media_4 uuid;
  extra uuid;

  pre_function_count integer;
begin
  -- State before the run, compared again after it.
  select count(*) into pre_function_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'confirm_owner_media_upload';

  -- ===========================================================================
  -- Everything that changes anything happens inside this block. Its exception
  -- clause makes it a savepoint, and it always ends by raising, so all of it
  -- is rolled back before the report below is written.
  -- ===========================================================================
  begin
    -- -------------------------------------------------------------------------
    -- 1. Pre-checks
    -- -------------------------------------------------------------------------
    stage := 'running pre-checks';

    results := results || jsonb_build_object(
      'ok', current_user = 'postgres',
      'check', 'pre: running as postgres, which will own the new function',
      'detail', 'current_user = ' || current_user);

    results := results || jsonb_build_object(
      'ok', pg_has_role(current_user, 'authenticated', 'MEMBER'),
      'check', 'pre: can act as the authenticated role to simulate a signed-in client');

    select count(*) into affected
    from information_schema.columns
    where table_schema = 'public'
      and (table_name, column_name) in (
        ('media_objects', 'status'), ('media_objects', 'bucket'), ('media_objects', 'object_key'),
        ('media_objects', 'owner_id'), ('media_objects', 'size_bytes'), ('media_objects', 'content_type'),
        ('media_objects', 'duration_ms'), ('owner_media', 'owner_record_id'), ('owner_media', 'media_id'),
        ('owner_media', 'role'), ('owner_media', 'ordinal'), ('owners', 'owner_id'), ('owners', 'deleted_at'));
    results := results || jsonb_build_object(
      'ok', affected = 13,
      'check', 'pre: media_objects, owner_media and owners have every column the function uses',
      'detail', affected || ' of 13 present');

    select count(*) into affected
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'media_status'
      and e.enumlabel in ('pending_upload', 'ready', 'failed', 'pending_delete', 'deleted');
    results := results || jsonb_build_object(
      'ok', affected = 5,
      'check', 'pre: media_status has pending_upload, ready, failed, pending_delete, deleted',
      'detail', affected || ' of 5 present');

    results := results || jsonb_build_object(
      'ok', exists (
        select 1 from pg_constraint c
        where c.conrelid = 'public.owner_media'::regclass and c.contype = 'u'
          and (select array_agg(a.attname::text order by a.attname)
               from pg_attribute a
               where a.attrelid = c.conrelid and a.attnum = any(c.conkey))
              = array['ordinal', 'owner_record_id', 'role']),
      'check', 'pre: owner_media still has unique (owner_record_id, role, ordinal)');

    results := results || jsonb_build_object(
      'ok', exists (
        select 1 from pg_trigger
        where tgrelid = 'public.owner_media'::regclass
          and tgname = 'owner_media_validate_owner'
          and not tgisinternal),
      'check', 'pre: the owner_media ownership trigger is present');

    select count(*) into affected from pg_roles where rolname in ('anon', 'authenticated', 'service_role');
    results := results || jsonb_build_object(
      'ok', affected = 3,
      'check', 'pre: roles anon, authenticated and service_role exist');

    select count(*) into affected from auth.users
    where id = any(test_users) or email like '%' || test_email_domain;
    select affected + count(*) into affected from public.profiles where id = any(test_users);
    select affected + count(*) into affected from public.owners where id = any(test_owners);
    select affected + count(*) into affected from public.media_objects where bucket in (test_bucket, other_bucket);
    results := results || jsonb_build_object(
      'ok', affected = 0,
      'check', 'pre: no test account, Owner or media row exists',
      'detail', affected || ' found');

    results := results || jsonb_build_object(
      'info', true,
      'check', 'info: confirm_owner_media_upload before the run',
      'detail', case when pre_function_count > 0 then 'already installed (re-validation)' else 'not installed yet' end);

    if exists (
      select 1 from jsonb_array_elements(results) as r
      where not (r ? 'info') and not coalesce((r ->> 'ok')::boolean, false)
    ) then
      raise exception 'a pre-check failed; nothing was installed';
    end if;

    -- -------------------------------------------------------------------------
    -- 2. Install the migration, exact file text
    -- -------------------------------------------------------------------------
    stage := 'installing 20260928100000_owner_media_confirm_rpc.sql';
    execute $migration_20260928100000$
-- Owner media: attach an uploaded file to its Owner record and mark it ready
-- as ONE atomic, idempotent step, with the per-Owner limit and the item's
-- position decided under a lock on the Owner row.
--
-- The Owner counterpart of confirm_offer_media_upload
-- (20260926092220_offer_media_confirm_rpc.sql), line for line: only the
-- parent table (public.owners), the link table (public.owner_media), the key
-- segment ('owners') and the not-found outcome ('owner_not_found') differ.
-- Owner decision (2026-09-28): Owner media follows the Offer media rules, so
-- the observed-size ceiling is the same 100 MiB and the Worker passes the same
-- limit of 10 items.
--
-- Called only by the r2-profile-upload Worker (service_role) after it has
-- verified the uploaded bytes in private R2: size, real type from the leading
-- bytes, and video duration. Clients cannot execute it: EXECUTE is revoked
-- from public, anon and authenticated, as for confirm_offer_media_upload.
--
-- Why a function: through PostgREST, "count the Owner's items, insert the
-- link, mark the media ready" is several requests. Two concurrent confirms
-- could both count nine items, and a failure between the insert and the
-- update left an item attached but not ready. Here the Owner row is locked
-- first (SELECT ... FOR UPDATE), so every attach to one Owner is serialized;
-- the limit, the position and `ready` are then decided and written in one
-- transaction. The position is the Owner's highest position + 1, so a new
-- item always goes to the end, never into a gap a removal left.
--
-- Outcomes are returned, not raised, so the Worker can clean up precisely:
--   attached          linked at media_ordinal and marked ready
--   already_attached  already linked (a retried confirm); a still-pending
--                     row is marked ready; nothing is duplicated
--   limit_reached     the Owner already has p_max_items ready items in
--                     p_bucket; nothing changed
--   owner_not_found   no live Owner record with that id owned by p_user_id
--   media_not_found   no media row with that id owned by p_user_id in
--                     p_bucket under this Owner's object-key prefix
--   invalid_status    the media row is not pending_upload (failed,
--                     removed, ...); nothing changed
--
-- Only ready media in p_bucket is counted. Staging and production share this
-- database, each with its own bucket; counting per bucket keeps one
-- environment's test media from filling the other's Owner. Positions are
-- taken over all of the Owner's links, so they never collide.
--
-- The object-key prefix check is what keeps an Offer's media out of an Owner
-- (and one Owner's out of another's): media authorized for an Offer lives
-- under profiles/<uid>/offers/<offerId>/ and is refused here as
-- media_not_found.
--
-- No table, column, constraint, index, RLS policy or trigger changes.
-- public.owner_media, its unique (owner_record_id, role, ordinal) constraint,
-- its owner_media_validate_owner trigger (validate_media_attachment_ownership)
-- and its owner_media_select_own policy already exist (baseline migration)
-- and still apply to the insert.
--
-- search_path is empty: every relation and type below is schema-qualified,
-- so nothing can be resolved through a caller-controlled path.
--
-- Reversal: see the note at the end of this file.


create or replace function public.confirm_owner_media_upload(
  p_user_id uuid,
  p_owner_record_id uuid,
  p_media_id uuid,
  p_bucket text,
  p_max_items integer,
  p_observed_size bigint,
  p_observed_content_type text,
  p_duration_ms bigint default null
)
returns table(
  outcome text,
  media_ordinal integer
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status public.media_status;
  v_object_key text;
  v_ordinal integer;
  v_ready_count integer;
begin
  if p_user_id is null
     or p_owner_record_id is null
     or p_media_id is null
     or p_bucket is null
     or btrim(p_bucket) = ''
     or p_max_items is null
     or p_max_items < 1 then
    raise exception 'p_user_id, p_owner_record_id, p_media_id, p_bucket and a positive p_max_items are required';
  end if;

  if p_observed_size is null
     or p_observed_size <= 0
     or p_observed_size > 104857600 then
    raise exception 'Observed object size out of allowed range';
  end if;

  -- Serializes every attach to this Owner: the limit and the position below
  -- are decided while this lock is held.
  perform 1
  from public.owners as ow
  where ow.id = p_owner_record_id
    and ow.owner_id = p_user_id
    and ow.deleted_at is null
  for update;

  if not found then
    return query select 'owner_not_found'::text, null::integer;
    return;
  end if;

  select mo.status, mo.object_key
    into v_status, v_object_key
  from public.media_objects as mo
  where mo.id = p_media_id
    and mo.owner_id = p_user_id
    and mo.bucket = p_bucket
  for update;

  if not found
     or not starts_with(
       v_object_key,
       'profiles/' || p_user_id::text || '/owners/' || p_owner_record_id::text || '/'
     ) then
    return query select 'media_not_found'::text, null::integer;
    return;
  end if;

  select owm.ordinal
    into v_ordinal
  from public.owner_media as owm
  where owm.owner_record_id = p_owner_record_id
    and owm.media_id = p_media_id;

  if found then
    -- A retried confirm: finish what is left and duplicate nothing.
    update public.media_objects as mo
    set
      status = 'ready',
      size_bytes = p_observed_size,
      content_type = p_observed_content_type,
      duration_ms = p_duration_ms
    where mo.id = p_media_id
      and mo.status = 'pending_upload';

    return query select 'already_attached'::text, v_ordinal;
    return;
  end if;

  if v_status <> 'pending_upload' then
    return query select 'invalid_status'::text, null::integer;
    return;
  end if;

  select count(*)
    into v_ready_count
  from public.owner_media as owm
  join public.media_objects as mo on mo.id = owm.media_id
  where owm.owner_record_id = p_owner_record_id
    and mo.bucket = p_bucket
    and mo.status = 'ready';

  if v_ready_count >= p_max_items then
    return query select 'limit_reached'::text, null::integer;
    return;
  end if;

  select coalesce(max(owm.ordinal), -1) + 1
    into v_ordinal
  from public.owner_media as owm
  where owm.owner_record_id = p_owner_record_id
    and owm.role = 'gallery';

  insert into public.owner_media (owner_record_id, media_id, role, ordinal)
  values (p_owner_record_id, p_media_id, 'gallery', v_ordinal);

  update public.media_objects as mo
  set
    status = 'ready',
    size_bytes = p_observed_size,
    content_type = p_observed_content_type,
    duration_ms = p_duration_ms
  where mo.id = p_media_id;

  return query select 'attached'::text, v_ordinal;
end;
$function$;

revoke all on function public.confirm_owner_media_upload(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  bigint,
  text,
  bigint
) from public;

revoke all on function public.confirm_owner_media_upload(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  bigint,
  text,
  bigint
) from anon;

revoke all on function public.confirm_owner_media_upload(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  bigint,
  text,
  bigint
) from authenticated;

grant execute on function public.confirm_owner_media_upload(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  bigint,
  text,
  bigint
) to service_role;

comment on function public.confirm_owner_media_upload(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  bigint,
  text,
  bigint
) is 'Owner media: atomic, idempotent attach + ready with the per-Owner limit and append position. service_role only (r2-profile-upload Worker).';


-- Reversal (not part of this migration). Only after every Worker version that
-- calls this function has been rolled back — until then, dropping it makes
-- every Owner media confirm fail closed (nothing can be attached):
--
--   drop function if exists public.confirm_owner_media_upload(
--     uuid, uuid, uuid, text, integer, bigint, text, bigint
--   );
--
-- Dropping it deletes no data: media already attached stays attached and
-- listed. Deploy order is the reverse: this migration first, then the Worker.
$migration_20260928100000$;
    results := results || jsonb_build_object(
      'ok', true,
      'check', 'install: 20260928100000_owner_media_confirm_rpc.sql');

    -- -------------------------------------------------------------------------
    -- 3. The installed function and who may execute it
    -- -------------------------------------------------------------------------
    stage := 'checking the installed function and its grants';

    select p.prosecdef into flag from pg_proc p where p.oid = fn::regprocedure;
    results := results || jsonb_build_object(
      'ok', flag,
      'check', 'function: SECURITY DEFINER');

    select array_to_string(p.proconfig, ',') into detail_text from pg_proc p where p.oid = fn::regprocedure;
    results := results || jsonb_build_object(
      'ok', coalesce(detail_text like 'search_path=%', false),
      'check', 'function: runs with a fixed search_path',
      'detail', detail_text);

    select pg_get_userbyid(p.proowner) into detail_text from pg_proc p where p.oid = fn::regprocedure;
    results := results || jsonb_build_object(
      'ok', detail_text = 'postgres',
      'check', 'function: owned by postgres',
      'detail', detail_text);

    results := results || jsonb_build_object(
      'ok', not has_function_privilege('anon', fn, 'EXECUTE')
        and not has_function_privilege('authenticated', fn, 'EXECUTE')
        and has_function_privilege('service_role', fn, 'EXECUTE'),
      'check', 'grants: service_role may execute; anon and authenticated may not');

    select not exists (
      select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
      where p.oid = fn::regprocedure and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
    ) into flag;
    results := results || jsonb_build_object(
      'ok', flag,
      'check', 'grants: PUBLIC may not execute');

    -- -------------------------------------------------------------------------
    -- 4. Fixtures
    -- -------------------------------------------------------------------------
    stage := 'creating test accounts, Owner records and media rows';

    insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
    values
      (user_a, 'a' || test_email_domain, '{"name":"Owner Media Validation A"}'::jsonb, now(), now()),
      (user_b, 'b' || test_email_domain, '{"name":"Owner Media Validation B"}'::jsonb, now(), now());

    insert into public.owners (id, owner_id, name, deleted_at)
    values
      (owner_a1, user_a, 'Owner Media Validation A1', null),
      (owner_a2, user_a, 'Owner Media Validation A2', null),
      (owner_a3, user_a, 'Owner Media Validation A3', null),
      (owner_a4, user_a, 'Owner Media Validation A4', now()),
      (owner_b1, user_b, 'Owner Media Validation B1', null);

    -- -------------------------------------------------------------------------
    -- 5. Attach, retry, append order
    -- -------------------------------------------------------------------------
    stage := 'attaching, retrying and ordering';

    media_1 := gen_random_uuid();
    media_2 := gen_random_uuid();
    media_3 := gen_random_uuid();
    media_4 := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    select m, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a1 || '/' || m || '.jpg',
           'image', 'image/jpeg', 64, 'pending_upload'
    from unnest(array[media_1, media_2, media_3, media_4]) as m;

    select c.outcome, c.media_ordinal into outcome_text, ordinal_value
    from public.confirm_owner_media_upload(user_a, owner_a1, media_1, test_bucket, 10, 12345, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'attached' and ordinal_value = 0,
      'check', 'attach: the first item is attached at position 0',
      'detail', format('%s / %s', outcome_text, ordinal_value));

    select count(*) into affected from public.media_objects
    where id = media_1 and status = 'ready' and size_bytes = 12345 and content_type = 'image/jpeg' and duration_ms is null;
    select affected + count(*) into affected from public.owner_media where media_id = media_1 and owner_record_id = owner_a1;
    results := results || jsonb_build_object(
      'ok', affected = 2,
      'check', 'attach: the item is ready with the observed size and linked exactly once');

    select c.outcome, c.media_ordinal into outcome_text, ordinal_value
    from public.confirm_owner_media_upload(user_a, owner_a1, media_1, test_bucket, 10, 12345, 'image/jpeg', null) as c;
    select count(*) into affected from public.owner_media where media_id = media_1;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'already_attached' and ordinal_value = 0 and affected = 1,
      'check', 'idempotent: a retried confirm reports already_attached and adds no link',
      'detail', format('%s / %s, %s link(s)', outcome_text, ordinal_value, affected));

    perform public.confirm_owner_media_upload(user_a, owner_a1, media_2, test_bucket, 10, 64, 'image/jpeg', null);
    perform public.confirm_owner_media_upload(user_a, owner_a1, media_3, test_bucket, 10, 64, 'image/jpeg', null);
    -- What the Worker's removal does to media_2: pending_delete, then unlink.
    update public.media_objects set status = 'pending_delete', deleted_at = now() where id = media_2;
    delete from public.owner_media where media_id = media_2;
    select c.outcome, c.media_ordinal into outcome_text, ordinal_value
    from public.confirm_owner_media_upload(user_a, owner_a1, media_4, test_bucket, 10, 64, 'video/mp4', 30000) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'attached' and ordinal_value = 3,
      'check', 'order: after a removal the next item goes to the end (position 3), not into the gap',
      'detail', format('%s / %s', outcome_text, ordinal_value));

    select count(*) into affected from public.media_objects where id = media_4 and duration_ms = 30000;
    results := results || jsonb_build_object(
      'ok', affected = 1,
      'check', 'attach: a video''s measured duration is recorded');

    -- -------------------------------------------------------------------------
    -- 6. The limit
    -- -------------------------------------------------------------------------
    stage := 'filling an Owner to its limit';

    for i in 1..11 loop
      extra := gen_random_uuid();
      insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
      values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a2 || '/' || extra || '.jpg',
              'image', 'image/jpeg', 64, 'pending_upload');
      select c.outcome, c.media_ordinal into outcome_text, ordinal_value
      from public.confirm_owner_media_upload(user_a, owner_a2, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    end loop;
    select count(*) into affected from public.owner_media where owner_record_id = owner_a2;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'limit_reached' and ordinal_value is null and affected = 10,
      'check', 'limit: the 11th item is refused with limit_reached; the Owner holds exactly 10',
      'detail', format('last outcome %s, %s link(s)', outcome_text, affected));

    select count(*) into affected from public.media_objects where id = extra and status = 'pending_upload';
    select affected + count(*) into affected from public.owner_media where media_id = extra;
    results := results || jsonb_build_object(
      'ok', affected = 1,
      'check', 'limit: the refused item is left pending and unlinked (the Worker then marks it failed)');

    -- -------------------------------------------------------------------------
    -- 7. Bucket isolation: the other environment's media is not counted
    -- -------------------------------------------------------------------------
    stage := 'checking bucket isolation';

    for i in 1..9 loop
      extra := gen_random_uuid();
      insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
      values (extra, user_a, other_bucket, 'profiles/' || user_a || '/owners/' || owner_a3 || '/' || extra || '.jpg',
              'image', 'image/jpeg', 64, 'pending_upload');
      perform public.confirm_owner_media_upload(user_a, owner_a3, extra, other_bucket, 10, 64, 'image/jpeg', null);
    end loop;
    for i in 1..10 loop
      extra := gen_random_uuid();
      insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
      values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a3 || '/' || extra || '.jpg',
              'image', 'image/jpeg', 64, 'pending_upload');
      select c.outcome, c.media_ordinal into outcome_text, ordinal_value
      from public.confirm_owner_media_upload(user_a, owner_a3, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    end loop;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'attached' and ordinal_value = 18,
      'check', 'buckets: 9 items in the other bucket do not count against this bucket''s 10; positions never collide',
      'detail', format('10th item in this bucket: %s / %s', outcome_text, ordinal_value));

    -- -------------------------------------------------------------------------
    -- 8. Refusals
    -- -------------------------------------------------------------------------
    stage := 'checking refusals';

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_b1 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_b1, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'owner_not_found',
      'check', 'refuse: another account''s Owner is owner_not_found',
      'detail', outcome_text);

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a4 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a4, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'owner_not_found',
      'check', 'refuse: a soft-deleted Owner is owner_not_found',
      'detail', outcome_text);

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a1 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a2, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'media_not_found',
      'check', 'refuse: media keyed under a different Owner is media_not_found',
      'detail', outcome_text);

    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a1, extra, other_bucket, 10, 64, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'media_not_found',
      'check', 'refuse: media in another bucket is media_not_found',
      'detail', outcome_text);

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_a, test_bucket, 'profiles/' || user_a || '/offers/' || owner_a1 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a1, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    select count(*) into affected from public.owner_media where media_id = extra;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'media_not_found' and affected = 0,
      'check', 'refuse: media keyed as Offer media is media_not_found and is not linked',
      'detail', outcome_text);

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_b, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a1 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'pending_upload');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a1, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'media_not_found',
      'check', 'refuse: another account''s media is media_not_found',
      'detail', outcome_text);

    extra := gen_random_uuid();
    insert into public.media_objects (id, owner_id, bucket, object_key, media_type, content_type, size_bytes, status)
    values (extra, user_a, test_bucket, 'profiles/' || user_a || '/owners/' || owner_a1 || '/' || extra || '.jpg',
            'image', 'image/jpeg', 64, 'failed');
    select c.outcome into outcome_text
    from public.confirm_owner_media_upload(user_a, owner_a1, extra, test_bucket, 10, 64, 'image/jpeg', null) as c;
    select count(*) into affected from public.owner_media where media_id = extra;
    results := results || jsonb_build_object(
      'ok', outcome_text = 'invalid_status' and affected = 0,
      'check', 'refuse: a failed upload is invalid_status and is not linked',
      'detail', outcome_text);

    begin
      perform public.confirm_owner_media_upload(user_a, owner_a1, media_1, test_bucket, 0, 64, 'image/jpeg', null);
      flag := false;
    exception when others then
      flag := true;
    end;
    results := results || jsonb_build_object(
      'ok', flag,
      'check', 'refuse: a non-positive limit is an error');

    begin
      perform public.confirm_owner_media_upload(user_a, owner_a1, media_1, test_bucket, 10, 0, 'image/jpeg', null);
      flag := false;
    exception when others then
      flag := true;
    end;
    results := results || jsonb_build_object(
      'ok', flag,
      'check', 'refuse: an empty or oversized observed size is an error');

    begin
      execute 'set local role authenticated';
      perform public.confirm_owner_media_upload(user_a, owner_a1, media_1, test_bucket, 10, 64, 'image/jpeg', null);
      flag := false;
    exception when insufficient_privilege then
      flag := true;
    end;
    results := results || jsonb_build_object(
      'ok', flag and current_user = 'postgres',
      'check', 'grants: a signed-in client (authenticated) is refused with permission denied');

    -- Undo everything in this block, including the installed migration.
    completed := true;
    raise exception using errcode = 'P0001', message = 'owner_media_validation_rollback';
  exception when others then
    if not completed then
      results := results || jsonb_build_object(
        'ok', false,
        'check', 'validation stopped while ' || stage,
        'detail', sqlstate || ': ' || sqlerrm);
    end if;
  end;

  -- ===========================================================================
  -- 9. Post-checks: the rollback above really undid everything
  -- ===========================================================================
  select count(*) into affected
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'confirm_owner_media_upload';
  results := results || jsonb_build_object(
    'ok', affected = pre_function_count,
    'check', 'post: the function is back to its state before the run',
    'detail', format('%s before, %s after', pre_function_count, affected));

  select count(*) into affected from auth.users
  where id = any(test_users) or email like '%' || test_email_domain;
  select affected + count(*) into affected from public.profiles where id = any(test_users);
  select affected + count(*) into affected from public.owners where owner_id = any(test_users);
  select affected + count(*) into affected from public.media_objects where bucket in (test_bucket, other_bucket);
  results := results || jsonb_build_object(
    'ok', affected = 0,
    'check', 'post: no test account, profile, Owner or media row remains',
    'detail', affected || ' remaining');

  -- ===========================================================================
  -- Report
  -- ===========================================================================
  insert into pg_temp.owner_media_validation_results (seq, result, check_name, detail)
  select ord,
         case
           when e ? 'info' then 'INFO'
           when coalesce((e ->> 'ok')::boolean, false) then 'PASS'
           else 'FAIL'
         end,
         e ->> 'check',
         e ->> 'detail'
  from jsonb_array_elements(results) with ordinality as entry(e, ord);

  select count(*) filter (where result = 'FAIL'), count(*) filter (where result = 'PASS')
  into failures, passes
  from pg_temp.owner_media_validation_results;

  insert into pg_temp.owner_media_validation_results (seq, result, check_name, detail)
  values (
    0,
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end,
    format('OWNER MEDIA CONFIRM VALIDATION %s: %s passed, %s failed',
           case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures),
    case
      when not completed then 'The run stopped early; see the last FAIL row. Nothing was kept.'
      else 'All changes were rolled back inside the run (see post rows); the final ROLLBACK discards this report.'
    end);

  raise notice 'OWNER MEDIA CONFIRM VALIDATION %: % passed, % failed',
    case when failures = 0 and completed then 'PASSED' else 'FAILED' end, passes, failures;
end;
$validation$;

select seq as "#", result, check_name, detail
from pg_temp.owner_media_validation_results
order by seq;

rollback;

-- =============================================================================
-- Concurrency (local stack only — never hosted data)
--
-- With the migration applied to a local `supabase start` database, fill a test
-- Owner to 9 ready items, create two pending media rows for it, then in two
-- psql sessions:
--   session 1: begin; select * from public.confirm_owner_media_upload(<A>, <owner>, <m1>, <bucket>, 10, 64, 'image/jpeg', null);
--   session 2: begin; select * from public.confirm_owner_media_upload(<A>, <owner>, <m2>, <bucket>, 10, 64, 'image/jpeg', null);
--              -- blocks on the Owner row lock
--   session 1: commit;
--   session 2: -- now returns limit_reached
--   session 2: rollback;
-- Expected: exactly one `attached`, one `limit_reached`, 10 links.
-- =============================================================================
