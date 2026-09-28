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

begin;

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

commit;

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
