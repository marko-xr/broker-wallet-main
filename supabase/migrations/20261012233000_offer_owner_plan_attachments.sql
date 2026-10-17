-- Offer / Owner land-plan and plot-plan attachment (Arabic: مخطط الأرض /
-- مخطط القطعة). ONE optional, dedicated plan per Offer and per Owner record, an
-- image or a document (PDF, DOC, DOCX), kept apart from the Offer/Owner photo
-- and video gallery.
--
-- Model: a nullable pointer column on the parent (`offers.plan_media_id`,
-- `owners.plan_media_id`) to `public.media_objects`, the same shape as
-- `quotations.pdf_media_id`. It is deliberately NOT a row in `offer_media` or
-- `owner_media`: those link tables are the gallery, and everything that reads
-- them (the 10-item limit in confirm_offer_media_upload /
-- confirm_owner_media_upload, the Worker's list, capacity and sweep queries,
-- the app's card and Share media) counts every link whatever its `role`. A
-- plan stored there would consume gallery places and show up in the carousel.
--
-- Why a pointer column is the smallest correct schema:
--   * one plan per parent is the column itself (no second row can exist);
--   * the partial unique indexes below make one media identity back at most
--     one parent;
--   * `authenticated` holds only COLUMN-level INSERT/UPDATE grants on `offers`
--     and `owners` (see the baseline), so a new column is server-controlled
--     until someone grants it. This migration grants nothing to clients;
--   * existing rows stay valid (the column is null) and no media row, link or
--     object is rewritten.
--
-- Object keys. Plan objects live under their own key segment, still inside the
-- account prefix that Delete Account sweeps:
--   profiles/<uid>/offer-plans/<offerId>/<mediaId>.<ext>
--   profiles/<uid>/owner-plans/<ownerRecordId>/<mediaId>.<ext>
-- Neither matches the gallery's `profiles/*/offers/*` / `profiles/*/owners/*`
-- patterns, so no gallery query, count or sweep can see a plan object, and the
-- parent id and the kind of parent are part of the key the database checks.
--
-- Replacement is switch-then-retire in one transaction: the candidate is
-- uploaded and verified first; only the confirm function (compare-and-swap on
-- the expected current media id, parent row locked) points the parent at it and
-- marks the old object `pending_delete`. A failed or abandoned replacement
-- never touches the existing plan.
--
-- Everything here is service-role only. The Worker verifies the bearer, the
-- session gate and the real bytes in private R2, then calls these functions;
-- nothing is callable by `anon` or `authenticated`.
--
-- search_path is empty: every relation, type and function is schema-qualified.
-- The migration runner supplies the transaction (no begin/commit here), so the
-- rollback-only validation can include this exact file.
--
-- Reversal: see the note at the end of this file.

-- ---------------------------------------------------------------------------
-- Columns, foreign keys, uniqueness
-- ---------------------------------------------------------------------------

alter table public.offers add column plan_media_id uuid;
alter table public.owners add column plan_media_id uuid;

alter table public.offers
  add constraint offers_plan_media_fk
  foreign key (plan_media_id) references public.media_objects(id) on delete set null;
alter table public.owners
  add constraint owners_plan_media_fk
  foreign key (plan_media_id) references public.media_objects(id) on delete set null;

-- One media identity backs at most one parent. They also serve the foreign
-- keys' ON DELETE SET NULL lookups.
create unique index offers_plan_media_id_key
  on public.offers (plan_media_id) where plan_media_id is not null;
create unique index owners_plan_media_id_key
  on public.owners (plan_media_id) where plan_media_id is not null;

comment on column public.offers.plan_media_id is
  'The Offer''s dedicated land/plot plan (media_objects). Server-controlled: only the plan RPCs of the media Worker change it.';
comment on column public.owners.plan_media_id is
  'The Owner record''s dedicated land/plot plan (media_objects). Server-controlled: only the plan RPCs of the media Worker change it.';

-- ---------------------------------------------------------------------------
-- What a plan may be: one source of truth for the RPCs and the trigger
-- ---------------------------------------------------------------------------

create function public.plan_attachment_rules(p_content_type text)
returns table(file_extension text, media_kind public.media_type, max_bytes bigint)
language sql
immutable
set search_path = ''
as $function$
  select r.ext, r.kind::public.media_type, r.cap
  from (values
    ('image/jpeg'::text, 'jpg'::text, 'image'::text, 10485760::bigint),
    ('image/png'::text, 'png'::text, 'image'::text, 10485760::bigint),
    ('image/webp'::text, 'webp'::text, 'image'::text, 10485760::bigint),
    ('application/pdf'::text, 'pdf'::text, 'pdf'::text, 26214400::bigint),
    ('application/msword'::text, 'doc'::text, 'unknown'::text, 26214400::bigint),
    ('application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text,
     'docx'::text, 'unknown'::text, 26214400::bigint)
  ) as r(content_type, ext, kind, cap)
  where r.content_type = p_content_type;
$function$;

-- ---------------------------------------------------------------------------
-- The pointer is server-controlled and always points at the right object
-- ---------------------------------------------------------------------------
--
-- Two triggers per table, both inert unless the pointer is being written:
-- one for an INSERT that supplies a pointer, one for an UPDATE that changes it
-- (a foreign-key SET NULL is such an UPDATE). Ordinary client inserts and
-- updates never name the column, so they never reach this function.
--
--  1. A client role is refused outright. The column privileges already stop it;
--     this keeps the rule if a grant is ever widened by mistake.
--  2. A non-null pointer must name a READY media row of the same account whose
--     object key is exactly this kind of parent and this parent's id, with a
--     type and size the plan rules allow. An Offer plan cannot point at an
--     Owner plan, a gallery item, a profile image or another record's file.
--  3. A change that touches only the pointer leaves the parent's own
--     `updated_at` and `version` alone. The plan is an attachment, not an edit
--     of the record's fields: attaching one must not make a brand-new Offer look
--     "recently updated". The UPDATE trigger runs after bump_sync_version
--     (triggers fire in name order: `*_bump_sync_version` sorts before
--     `*_plan_media_guard_update`).

create function public.guard_plan_media_pointer()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_segment text;
  v_media public.media_objects%rowtype;
  v_rules record;
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'The plan attachment is server-controlled'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    if new.plan_media_id is not distinct from old.plan_media_id then
      return new;
    end if;
  end if;

  if new.plan_media_id is not null then
    v_segment := case tg_table_name
      when 'offers' then 'offer-plans'
      when 'owners' then 'owner-plans'
      else null end;
    if v_segment is null then
      raise exception 'Unsupported plan attachment table: %', tg_table_name;
    end if;

    select mo.* into v_media from public.media_objects as mo
      where mo.id = new.plan_media_id;
    if not found
       or v_media.owner_id is distinct from new.owner_id
       or v_media.status <> 'ready'
       or not pg_catalog.starts_with(
         v_media.object_key,
         'profiles/' || new.owner_id::text || '/' || v_segment || '/' ||
           new.id::text || '/') then
      raise exception 'Plan media must be a ready file of this record';
    end if;

    select r.* into v_rules
      from public.plan_attachment_rules(v_media.content_type) as r;
    if not found
       or v_media.media_type is distinct from v_rules.media_kind
       or v_media.size_bytes is null
       or v_media.size_bytes < 1
       or v_media.size_bytes > v_rules.max_bytes
       or v_media.object_key is distinct from
         'profiles/' || new.owner_id::text || '/' || v_segment || '/' ||
           new.id::text || '/' || v_media.id::text || '.' || v_rules.file_extension then
      raise exception 'Plan media type or size is not allowed';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if (pg_catalog.to_jsonb(new) - array['plan_media_id', 'updated_at', 'version'])
         = (pg_catalog.to_jsonb(old) - array['plan_media_id', 'updated_at', 'version']) then
      new.updated_at := old.updated_at;
      new.version := old.version;
    end if;
  end if;
  return new;
end;
$function$;

create trigger offers_plan_media_guard_insert
  before insert on public.offers
  for each row when (new.plan_media_id is not null)
  execute function public.guard_plan_media_pointer();
create trigger offers_plan_media_guard_update
  before update of plan_media_id on public.offers
  for each row when (new.plan_media_id is distinct from old.plan_media_id)
  execute function public.guard_plan_media_pointer();
create trigger owners_plan_media_guard_insert
  before insert on public.owners
  for each row when (new.plan_media_id is not null)
  execute function public.guard_plan_media_pointer();
create trigger owners_plan_media_guard_update
  before update of plan_media_id on public.owners
  for each row when (new.plan_media_id is distinct from old.plan_media_id)
  execute function public.guard_plan_media_pointer();

-- ---------------------------------------------------------------------------
-- Offer plan: confirm (attach or replace) and remove
-- ---------------------------------------------------------------------------
--
-- Outcomes are returned, not raised, so the Worker can answer precisely:
--   attached           the media is now the Offer's plan; previous_media_id is
--                      the plan it replaced (marked pending_delete), if any
--   already_attached   the media already is the plan (a retried confirm)
--   offer_not_found    no live Offer with that id owned by p_user_id
--   media_not_found    no pending media of p_user_id in p_bucket under exactly
--                      this Offer's plan key, with this MIME and kind
--   stale_replacement  the plan is not p_expected_media_id any more
--   invalid_status     the media row is not pending_upload
--   invalid_state      the current plan is not a coherent ready object of this
--                      Offer in this bucket; nothing is retired blindly
-- Malformed input (a type or size the plan rules refuse) raises.

create function public.confirm_offer_plan_upload(
  p_user_id uuid,
  p_offer_id uuid,
  p_media_id uuid,
  p_bucket text,
  p_expected_media_id uuid,
  p_observed_size bigint,
  p_observed_content_type text
)
returns table(outcome text, previous_media_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offer public.offers%rowtype;
  v_media public.media_objects%rowtype;
  v_rules record;
  v_prefix text;
  v_current uuid;
begin
  if p_user_id is null or p_offer_id is null or p_media_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null then
    raise exception 'Invalid plan attachment request';
  end if;

  select r.* into v_rules from public.plan_attachment_rules(p_observed_content_type) as r;
  if not found or p_observed_size is null
     or p_observed_size < 1 or p_observed_size > v_rules.max_bytes then
    raise exception 'Invalid plan attachment type or size';
  end if;
  v_prefix := 'profiles/' || p_user_id::text || '/offer-plans/' || p_offer_id::text || '/';

  -- Every change of this Offer's plan serializes here.
  select o.* into v_offer from public.offers as o
    where o.id = p_offer_id and o.owner_id = p_user_id for update;
  if not found or v_offer.deleted_at is not null then
    return query select 'offer_not_found'::text, null::uuid;
    return;
  end if;
  v_current := v_offer.plan_media_id;

  select mo.* into v_media from public.media_objects as mo
    where mo.id = p_media_id and mo.owner_id = p_user_id
      and mo.bucket = p_bucket for update;
  if not found
     or v_media.object_key is distinct from
       v_prefix || p_media_id::text || '.' || v_rules.file_extension
     or v_media.content_type is distinct from p_observed_content_type
     or v_media.media_type is distinct from v_rules.media_kind then
    return query select 'media_not_found'::text, null::uuid;
    return;
  end if;

  if v_current = p_media_id and v_media.status = 'ready' then
    return query select 'already_attached'::text, null::uuid;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid;
    return;
  end if;
  if v_media.status <> 'pending_upload' then
    return query select 'invalid_status'::text, null::uuid;
    return;
  end if;
  if v_current is not null and not exists (
    select 1 from public.media_objects as old
    where old.id = v_current and old.owner_id = p_user_id
      and old.bucket = p_bucket and old.status = 'ready'
      and pg_catalog.starts_with(old.object_key, v_prefix)) then
    return query select 'invalid_state'::text, null::uuid;
    return;
  end if;

  update public.media_objects as mo
    set status = 'ready', size_bytes = p_observed_size,
        content_type = p_observed_content_type
    where mo.id = p_media_id;
  update public.offers as o set plan_media_id = p_media_id where o.id = p_offer_id;
  if v_current is not null then
    update public.media_objects as mo
      set status = 'pending_delete', deleted_at = pg_catalog.now()
      where mo.id = v_current and mo.status = 'ready';
    if not found then raise exception 'Previous plan media changed'; end if;
  end if;
  return query select 'attached'::text, v_current;
end;
$function$;

-- Outcomes: removed, already_removed (no plan), offer_not_found,
-- stale_replacement, invalid_state.
create function public.remove_offer_plan(
  p_user_id uuid,
  p_offer_id uuid,
  p_bucket text,
  p_expected_media_id uuid
)
returns table(outcome text, previous_media_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offer public.offers%rowtype;
  v_current uuid;
begin
  if p_user_id is null or p_offer_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null then
    raise exception 'Invalid plan attachment removal';
  end if;

  select o.* into v_offer from public.offers as o
    where o.id = p_offer_id and o.owner_id = p_user_id for update;
  if not found or v_offer.deleted_at is not null then
    return query select 'offer_not_found'::text, null::uuid;
    return;
  end if;
  v_current := v_offer.plan_media_id;
  if v_current is null then
    return query select 'already_removed'::text, null::uuid;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid;
    return;
  end if;
  if not exists (
    select 1 from public.media_objects as mo
    where mo.id = v_current and mo.owner_id = p_user_id
      and mo.bucket = p_bucket and mo.status = 'ready'
      and pg_catalog.starts_with(mo.object_key,
        'profiles/' || p_user_id::text || '/offer-plans/' || p_offer_id::text || '/')) then
    return query select 'invalid_state'::text, null::uuid;
    return;
  end if;

  update public.offers as o set plan_media_id = null where o.id = p_offer_id;
  update public.media_objects as mo
    set status = 'pending_delete', deleted_at = pg_catalog.now()
    where mo.id = v_current and mo.status = 'ready';
  if not found then raise exception 'Plan media changed'; end if;
  return query select 'removed'::text, v_current;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Owner plan: the same two functions for an Owner record
-- ---------------------------------------------------------------------------
-- Outcomes as above with owner_not_found; the key segment is `owner-plans`.

create function public.confirm_owner_plan_upload(
  p_user_id uuid,
  p_owner_record_id uuid,
  p_media_id uuid,
  p_bucket text,
  p_expected_media_id uuid,
  p_observed_size bigint,
  p_observed_content_type text
)
returns table(outcome text, previous_media_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner public.owners%rowtype;
  v_media public.media_objects%rowtype;
  v_rules record;
  v_prefix text;
  v_current uuid;
begin
  if p_user_id is null or p_owner_record_id is null or p_media_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null then
    raise exception 'Invalid plan attachment request';
  end if;

  select r.* into v_rules from public.plan_attachment_rules(p_observed_content_type) as r;
  if not found or p_observed_size is null
     or p_observed_size < 1 or p_observed_size > v_rules.max_bytes then
    raise exception 'Invalid plan attachment type or size';
  end if;
  v_prefix := 'profiles/' || p_user_id::text || '/owner-plans/' || p_owner_record_id::text || '/';

  select o.* into v_owner from public.owners as o
    where o.id = p_owner_record_id and o.owner_id = p_user_id for update;
  if not found or v_owner.deleted_at is not null then
    return query select 'owner_not_found'::text, null::uuid;
    return;
  end if;
  v_current := v_owner.plan_media_id;

  select mo.* into v_media from public.media_objects as mo
    where mo.id = p_media_id and mo.owner_id = p_user_id
      and mo.bucket = p_bucket for update;
  if not found
     or v_media.object_key is distinct from
       v_prefix || p_media_id::text || '.' || v_rules.file_extension
     or v_media.content_type is distinct from p_observed_content_type
     or v_media.media_type is distinct from v_rules.media_kind then
    return query select 'media_not_found'::text, null::uuid;
    return;
  end if;

  if v_current = p_media_id and v_media.status = 'ready' then
    return query select 'already_attached'::text, null::uuid;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid;
    return;
  end if;
  if v_media.status <> 'pending_upload' then
    return query select 'invalid_status'::text, null::uuid;
    return;
  end if;
  if v_current is not null and not exists (
    select 1 from public.media_objects as old
    where old.id = v_current and old.owner_id = p_user_id
      and old.bucket = p_bucket and old.status = 'ready'
      and pg_catalog.starts_with(old.object_key, v_prefix)) then
    return query select 'invalid_state'::text, null::uuid;
    return;
  end if;

  update public.media_objects as mo
    set status = 'ready', size_bytes = p_observed_size,
        content_type = p_observed_content_type
    where mo.id = p_media_id;
  update public.owners as o set plan_media_id = p_media_id where o.id = p_owner_record_id;
  if v_current is not null then
    update public.media_objects as mo
      set status = 'pending_delete', deleted_at = pg_catalog.now()
      where mo.id = v_current and mo.status = 'ready';
    if not found then raise exception 'Previous plan media changed'; end if;
  end if;
  return query select 'attached'::text, v_current;
end;
$function$;

create function public.remove_owner_plan(
  p_user_id uuid,
  p_owner_record_id uuid,
  p_bucket text,
  p_expected_media_id uuid
)
returns table(outcome text, previous_media_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner public.owners%rowtype;
  v_current uuid;
begin
  if p_user_id is null or p_owner_record_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null then
    raise exception 'Invalid plan attachment removal';
  end if;

  select o.* into v_owner from public.owners as o
    where o.id = p_owner_record_id and o.owner_id = p_user_id for update;
  if not found or v_owner.deleted_at is not null then
    return query select 'owner_not_found'::text, null::uuid;
    return;
  end if;
  v_current := v_owner.plan_media_id;
  if v_current is null then
    return query select 'already_removed'::text, null::uuid;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid;
    return;
  end if;
  if not exists (
    select 1 from public.media_objects as mo
    where mo.id = v_current and mo.owner_id = p_user_id
      and mo.bucket = p_bucket and mo.status = 'ready'
      and pg_catalog.starts_with(mo.object_key,
        'profiles/' || p_user_id::text || '/owner-plans/' || p_owner_record_id::text || '/')) then
    return query select 'invalid_state'::text, null::uuid;
    return;
  end if;

  update public.owners as o set plan_media_id = null where o.id = p_owner_record_id;
  update public.media_objects as mo
    set status = 'pending_delete', deleted_at = pg_catalog.now()
    where mo.id = v_current and mo.status = 'ready';
  if not found then raise exception 'Plan media changed'; end if;
  return query select 'removed'::text, v_current;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Privileges: service role only
-- ---------------------------------------------------------------------------

revoke all on function public.plan_attachment_rules(text)
  from public, anon, authenticated;
grant execute on function public.plan_attachment_rules(text) to service_role;
revoke all on function public.guard_plan_media_pointer()
  from public, anon, authenticated;

revoke all on function public.confirm_offer_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.confirm_offer_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) to service_role;
revoke all on function public.remove_offer_plan(
  uuid, uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.remove_offer_plan(
  uuid, uuid, text, uuid) to service_role;
revoke all on function public.confirm_owner_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.confirm_owner_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) to service_role;
revoke all on function public.remove_owner_plan(
  uuid, uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.remove_owner_plan(
  uuid, uuid, text, uuid) to service_role;

comment on function public.plan_attachment_rules(text) is
  'Accepted plan attachment types: extension, media kind and maximum size. service_role only.';
comment on function public.guard_plan_media_pointer() is
  'Trigger: the plan pointer is server-controlled and must name a ready file of exactly this record; pointer-only changes keep updated_at and version.';
comment on function public.confirm_offer_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) is
  'Worker-only atomic Offer plan attach/replace; exact owner, key, MIME, kind, state and compare-and-swap slot checks.';
comment on function public.remove_offer_plan(uuid, uuid, text, uuid) is
  'Worker-only atomic Offer plan removal with compare-and-swap slot check.';
comment on function public.confirm_owner_plan_upload(
  uuid, uuid, uuid, text, uuid, bigint, text) is
  'Worker-only atomic Owner plan attach/replace; exact owner, key, MIME, kind, state and compare-and-swap slot checks.';
comment on function public.remove_owner_plan(uuid, uuid, text, uuid) is
  'Worker-only atomic Owner plan removal with compare-and-swap slot check.';

-- Reversal (not part of this migration). Only after every Worker version that
-- calls the plan functions has been rolled back; until then dropping them makes
-- every plan confirm and removal fail closed (nothing is attached or removed):
--
--   drop trigger if exists offers_plan_media_guard_insert on public.offers;
--   drop trigger if exists offers_plan_media_guard_update on public.offers;
--   drop trigger if exists owners_plan_media_guard_insert on public.owners;
--   drop trigger if exists owners_plan_media_guard_update on public.owners;
--   drop function if exists public.remove_owner_plan(uuid, uuid, text, uuid);
--   drop function if exists public.confirm_owner_plan_upload(
--     uuid, uuid, uuid, text, uuid, bigint, text);
--   drop function if exists public.remove_offer_plan(uuid, uuid, text, uuid);
--   drop function if exists public.confirm_offer_plan_upload(
--     uuid, uuid, uuid, text, uuid, bigint, text);
--   drop function if exists public.guard_plan_media_pointer();
--   drop function if exists public.plan_attachment_rules(text);
--   drop index if exists public.offers_plan_media_id_key;
--   drop index if exists public.owners_plan_media_id_key;
--   alter table public.offers drop column if exists plan_media_id;
--   alter table public.owners drop column if exists plan_media_id;
--
-- Dropping the columns removes the links, not the files: a plan object that was
-- attached stays in private R2 and in media_objects (status ready) until Delete
-- Account's prefix sweep or a manual cleanup removes it. Deploy order is this
-- migration first, then the Worker; rollback is the reverse.
