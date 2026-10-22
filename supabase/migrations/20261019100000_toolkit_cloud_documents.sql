-- Toolkit cloud documents (C1, SOURCE ONLY — not applied anywhere).
--
-- Decision: the documents created by Broker Wallet's four Toolkit tools (Scanner,
-- Combine PDFs, Images to PDF, Document Signature) are cloud-backed account
-- data. The phone's own folders are a cache and an offline working layer.
--
-- Model. ONE table, `public.toolkit_documents`, holds the metadata of every such
-- document. Two separate fields: `document_type` is the SOURCE TOOL, and
-- `content_type` is the BINARY FORMAT (application/pdf, image/jpeg, image/png).
-- Every tool produces PDFs; only the Scanner may also store JPEG / PNG scans, kept
-- as the original image bytes (nothing is converted). The bytes live in the
-- private Cloudflare R2 bucket the media Worker already owns, under the same
-- account prefix Delete Account sweeps:
--   profiles/<owner uid>/toolkit-documents/<document id>.<pdf|jpg|png>
-- The server builds the whole key; a CHECK constraint pins it to exactly that
-- shape with the extension taken from the content type, so a row can never point
-- outside its owner's prefix, at another account's object, at a gallery / plan
-- object, or carry an extension that disagrees with its format. No client name,
-- key or extension is ever used. No URL is stored anywhere; the Worker signs
-- short-lived transport URLs on demand.
--
-- Why not `media_objects`: that table is the gallery/plan/profile-image media
-- model (status enum, parent link tables, 10-item and plan rules, sweeps keyed
-- on those key patterns). A document needs a title, a type, a version for
-- rename conflicts, a delete tombstone and its own quotas. Account deletion does
-- not need a row in `media_objects`: it removes the union of that table and the
-- WHOLE account prefix (account_deletion.js removeAccountMedia), and these rows
-- cascade with the profile.
--
-- Everything that changes state is service-role only. The Worker verifies the
-- bearer token, the Single Active Device gate, the account-deletion quarantine
-- and the real bytes in R2, then calls these functions. `authenticated` may only
-- READ its own ready documents (column-restricted, no bucket or key); there is
-- no INSERT / UPDATE / DELETE grant, and `anon` has nothing.
--
-- Lifecycle:  pending_upload -> ready -> pending_delete -> deleted (tombstone)
--             pending_upload -> pending_delete -> deleted
--             pending_upload -> pending_discard -> (row removed, no tombstone)
--             pending_discard -> pending_delete -> deleted   (the user deletes it meanwhile)
--   * `id` is chosen by the device (the local document id, a UUID) and is the
--     idempotency key of authorize, confirm, rename and remove.
--   * `ready` is terminal for content: bytes never change for an id.
--   * A delete is two steps (mark, then remove the object, then finalize), so a
--     crash between them is repaired by retrying or by the sweep.
--   * The `deleted` tombstone keeps an id from being re-created by a device that
--     was offline when the document was deleted elsewhere. Abandoned uploads that
--     never became ready are hard-deleted instead (no tombstone), so a slow device
--     can still upload later. That cleanup is CLAIM-FIRST: the row is moved to
--     `pending_discard` under its row lock (after which it can never become ready
--     and no new upload can be authorized for it), only then is the object removed,
--     and only the holder of the claim may remove the row. Tombstones are scrubbed of the title when written and
--     purged after a retention period; purging advances the account's
--     `tombstone_floor` (table toolkit_document_account_state), after which a
--     document the device made before that time is not re-created without an
--     explicit acknowledgement. That is what keeps a purged tombstone from allowing
--     a deleted document to come back, while the tombstone history stays bounded.
--
-- Integrity. The row records three different things, never conflated: the
-- device-calculated SHA-256 (content_sha256, required, a claim until proven), the
-- facts the Worker observed on the stored object (size, content type, format
-- framing, ETag as an identity token only), and sha256_verified, true only when
-- the Worker hashed the stored object and the digest matched.
--
-- Limits. The numeric limits are anti-abuse / storage-safety limits, NOT
-- subscription quotas. The Worker passes its configured values to the
-- authorize function, which enforces them atomically (per-account advisory
-- lock) and refuses any value above the hard ceilings below.
--
-- search_path is empty: every relation, type and function is schema-qualified.
-- The migration runner supplies the transaction (no begin/commit here), so the
-- rollback-only validation can include this exact file.
--
-- Reversal: see the note at the end of this file.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table public.toolkit_documents (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null,
  title text not null,
  content_type text not null,
  size_bytes bigint not null,
  page_count integer,
  content_sha256 text not null,
  sha256_verified boolean not null default false,
  bucket text not null,
  object_key text not null,
  observed_etag text,
  status text not null default 'pending_upload',
  source_created_at timestamptz not null default pg_catalog.now(),
  upload_attempts integer not null default 0,
  last_authorized_at timestamptz,
  confirmed_at timestamptz,
  deleted_at timestamptz,
  -- Set only while an abandoned-upload cleanup owns the row (status pending_discard):
  -- the identity of that claim, which the final discard must present.
  discard_claimed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1,
  constraint toolkit_documents_type_known
    check (document_type in ('scanner', 'combine_pdfs', 'image_to_pdf', 'signature')),
  constraint toolkit_documents_title_clean
    check (
      pg_catalog.char_length(title) between 1 and 200
      and title = pg_catalog.btrim(title)
      -- no control characters and no bidi override / isolate controls
      and title !~ '[\u0001-\u001f\u007f\u202A-\u202E\u2066-\u2069]'
    ),
  constraint toolkit_documents_content_type_known
    check (content_type in ('application/pdf', 'image/jpeg', 'image/png')),
  -- Only the Scanner stores images; every other tool produces PDFs.
  constraint toolkit_documents_tool_content_type
    check (content_type = 'application/pdf' or document_type = 'scanner'),
  constraint toolkit_documents_size_range
    check (size_bytes between 1 and 262144000
           and (content_type = 'application/pdf' or size_bytes <= 67108864)),
  constraint toolkit_documents_pages_range
    check (page_count is null or page_count between 1 and 100000),
  constraint toolkit_documents_image_single_page
    check (content_type = 'application/pdf' or page_count is null or page_count = 1),
  constraint toolkit_documents_sha256_format check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint toolkit_documents_verified_when_ready
    check (not sha256_verified or status not in ('pending_upload', 'pending_discard')),
  constraint toolkit_documents_bucket_nonempty check (pg_catalog.btrim(bucket) <> ''),
  constraint toolkit_documents_object_key_exact
    check (object_key = 'profiles/' || owner_id::text || '/toolkit-documents/' || id::text || '.' ||
      case content_type
        when 'application/pdf' then 'pdf'
        when 'image/jpeg' then 'jpg'
        when 'image/png' then 'png'
      end),
  constraint toolkit_documents_status_known
    check (status in ('pending_upload', 'ready', 'pending_delete', 'pending_discard', 'deleted')),
  constraint toolkit_documents_attempts_nonnegative check (upload_attempts >= 0),
  constraint toolkit_documents_version_positive check (version >= 1),
  constraint toolkit_documents_ready_confirmed
    check (status <> 'ready' or confirmed_at is not null),
  constraint toolkit_documents_pending_unconfirmed
    check (status not in ('pending_upload', 'pending_discard') or confirmed_at is null),
  constraint toolkit_documents_deleting_has_time
    check ((status in ('pending_delete', 'deleted')) = (deleted_at is not null)),
  constraint toolkit_documents_discard_has_claim
    check ((status = 'pending_discard') = (discard_claimed_at is not null)),
  constraint toolkit_documents_bucket_key_unique unique (bucket, object_key)
);

-- Account-scoped listing and counting (also serves the owner foreign key).
create index toolkit_documents_owner_idx
  on public.toolkit_documents (owner_id, created_at desc, id desc);
-- Abandoned-upload and half-finished-delete sweeps.
create index toolkit_documents_pending_upload_idx
  on public.toolkit_documents (last_authorized_at, id)
  where status in ('pending_upload', 'pending_discard');
create index toolkit_documents_deleting_idx
  on public.toolkit_documents (deleted_at, id) where status in ('pending_delete', 'deleted');

comment on table public.toolkit_documents is
  'Cloud-backed documents (PDF, and Scanner JPEG / PNG) of the four Toolkit tools. Metadata only: bytes live in private R2 under profiles/<uid>/toolkit-documents/<id>.<pdf|jpg|png>. Server-controlled: only the service-role functions below change it.';

create trigger toolkit_documents_bump_sync_version
  before update on public.toolkit_documents
  for each row execute function public.bump_sync_version();

-- ---------------------------------------------------------------------------
-- Rules and the one definition of the object key
-- ---------------------------------------------------------------------------

-- The one list of accepted binary formats: extension and hard size ceiling.
create function public.toolkit_document_rules(p_content_type text)
returns table(file_extension text, hard_max_bytes bigint)
language sql
immutable
set search_path = ''
as $function$
  select r.ext, r.cap
  from (values
    ('application/pdf'::text, 'pdf'::text, 262144000::bigint),
    ('image/jpeg'::text, 'jpg'::text, 67108864::bigint),
    ('image/png'::text, 'png'::text, 67108864::bigint)
  ) as r(content_type, ext, cap)
  where r.content_type = p_content_type;
$function$;

-- The one definition of an object key; null for an unaccepted content type.
create function public.toolkit_document_object_key(
  p_owner_id uuid, p_document_id uuid, p_content_type text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select 'profiles/' || p_owner_id::text || '/toolkit-documents/' || p_document_id::text
    || '.' || r.file_extension
  from public.toolkit_document_rules(p_content_type) as r;
$function$;

-- ---------------------------------------------------------------------------
-- Guard: identity and content never change; status only moves forward
-- ---------------------------------------------------------------------------
--
--  1. A client role is refused outright (the grants already stop it; this keeps
--     the rule if a grant is ever widened by mistake).
--  2. On UPDATE, the identity (id, owner, type, bucket, key, content type, size,
--     hash, creation times) is frozen for EVERY role, so a server-side mistake
--     cannot reassign a document to another account or re-point its object.
--  3. Status may only follow the lifecycle above; `deleted` is terminal.

create function public.guard_toolkit_document()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'Toolkit documents are server-controlled'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending_upload' or new.version <> 1 then
      raise exception 'A Toolkit document starts as a pending upload';
    end if;
    return new;
  end if;

  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id
     or new.document_type is distinct from old.document_type
     or new.bucket is distinct from old.bucket
     or new.object_key is distinct from old.object_key
     or new.content_type is distinct from old.content_type
     or new.size_bytes is distinct from old.size_bytes
     or new.content_sha256 is distinct from old.content_sha256
     or new.source_created_at is distinct from old.source_created_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Toolkit document identity is immutable';
  end if;

  if new.status is distinct from old.status
     and not ((old.status = 'pending_upload'
               and new.status in ('ready', 'pending_delete', 'pending_discard'))
              or (old.status = 'ready' and new.status = 'pending_delete')
              or (old.status = 'pending_discard' and new.status = 'pending_delete')
              or (old.status = 'pending_delete' and new.status = 'deleted')) then
    raise exception 'Invalid Toolkit document status change: % to %', old.status, new.status;
  end if;

  -- The verification flag can only be set at the moment the document becomes
  -- ready, never afterwards and never cleared.
  if new.sha256_verified is distinct from old.sha256_verified
     and not (new.sha256_verified and old.status = 'pending_upload'
              and new.status = 'ready') then
    raise exception 'The verification flag is set only when a document becomes ready';
  end if;
  return new;
end;
$function$;

create trigger toolkit_documents_guard_insert
  before insert on public.toolkit_documents
  for each row execute function public.guard_toolkit_document();
-- Fires after `toolkit_documents_bump_sync_version` (name order), so it also
-- sees the bumped version; it never relaxes a check.
create trigger toolkit_documents_guard_update
  before update on public.toolkit_documents
  for each row execute function public.guard_toolkit_document();

-- ---------------------------------------------------------------------------
-- Row level security and privileges
-- ---------------------------------------------------------------------------

alter table public.toolkit_documents enable row level security;

revoke all on public.toolkit_documents from public, anon, authenticated, service_role;
-- Read only, own ready documents, and never the bucket, the key or the etag.
grant select (
  id, owner_id, document_type, title, content_type, size_bytes, page_count,
  content_sha256, sha256_verified, status, source_created_at, confirmed_at,
  created_at, updated_at, version
) on public.toolkit_documents to authenticated;

create policy toolkit_documents_select_own on public.toolkit_documents
  for select to authenticated
  using (owner_id = (select auth.uid()) and status = 'ready');

-- Same Single Active Device gate as every other app-data table.
create policy app_session_gate on public.toolkit_documents
  as restrictive for all to authenticated
  using ((select public.is_current_app_session()))
  with check ((select public.is_current_app_session()));

-- Per-account deletion history floor (see the header). Internal bookkeeping:
-- RLS is on, there is no policy and no grant for any role, so only the
-- SECURITY DEFINER functions below (owned by the migration role) read or write it.
create table public.toolkit_document_account_state (
  owner_id uuid primary key references public.profiles(id) on delete cascade,
  tombstone_floor timestamptz not null,
  updated_at timestamptz not null default pg_catalog.now()
);
alter table public.toolkit_document_account_state enable row level security;
revoke all on public.toolkit_document_account_state
  from public, anon, authenticated, service_role;
comment on table public.toolkit_document_account_state is
  'Latest deletion time of any purged Toolkit tombstone of the account. Internal; no client or service-role table access.';

-- ---------------------------------------------------------------------------
-- authorize: reserve (or resume) an upload, atomically within the limits
-- ---------------------------------------------------------------------------
--
-- Outcomes (returned, not raised, so the Worker can answer precisely):
--   created              a new pending row; the caller may PUT the bytes
--   resumed              the same pending upload again (a retry)
--   already_ready        the document is already cloud-backed (a retried save)
--   document_deleted     the id was deleted; never re-created
--   id_unavailable       the id belongs to another account (indistinguishable
--                        from the outside; see the Worker)
--   idempotency_mismatch the id was used for a different file
--   too_large            above p_max_document_bytes (PDF) or p_max_image_bytes
--   stale_document       no row for this id, and the device made the document
--                        before the account's tombstone floor: possibly a deleted
--                        document whose tombstone was purged. Re-created only with
--                        p_acknowledge_stale (an explicit user decision)
--   storage_limit        the account would exceed p_max_account_bytes
--   document_limit       the account would exceed p_max_account_documents
--   too_many_pending     p_max_pending uploads are already waiting
--   rate_limited         p_max_new_per_hour new documents in the last hour, or
--                        p_max_attempts authorizations of this one pending upload
-- Malformed input (a type, hash, title or limit the rules refuse) raises.

create function public.authorize_toolkit_document_upload(
  p_user_id uuid,
  p_document_id uuid,
  p_document_type text,
  p_content_type text,
  p_title text,
  p_size_bytes bigint,
  p_page_count integer,
  p_content_sha256 text,
  p_source_created_at timestamptz,
  p_bucket text,
  p_max_document_bytes bigint,
  p_max_image_bytes bigint,
  p_max_account_bytes bigint,
  p_max_account_documents integer,
  p_max_pending integer,
  p_max_new_per_hour integer,
  p_max_attempts integer,
  p_acknowledge_stale boolean
)
returns table(outcome text, status text, version bigint)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
  v_used_bytes bigint;
  v_used_documents bigint;
  v_pending bigint;
  v_recent bigint;
  v_source_created timestamptz;
  v_floor timestamptz;
  v_cap bigint;
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_size_bytes is null or p_size_bytes < 1
     or p_document_type is null
     or p_document_type not in ('scanner', 'combine_pdfs', 'image_to_pdf', 'signature')
     or p_content_type is null
     or not exists (select 1 from public.toolkit_document_rules(p_content_type))
     -- Only the Scanner stores images; every other tool produces PDFs.
     or (p_content_type <> 'application/pdf' and p_document_type <> 'scanner')
     or p_title is null
     -- The device-calculated digest is required; the server never invents one.
     or p_content_sha256 is null or p_content_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_created_at is null
     or p_acknowledge_stale is null
     or (p_page_count is not null and (p_page_count < 1 or p_page_count > 100000
         or (p_content_type <> 'application/pdf' and p_page_count <> 1))) then
    raise exception 'Invalid Toolkit document request';
  end if;
  -- Hard ceilings: a configuration above them fails closed.
  if p_max_document_bytes is null or p_max_document_bytes < 1 or p_max_document_bytes > 262144000
     or p_max_image_bytes is null or p_max_image_bytes < 1 or p_max_image_bytes > 67108864
     or p_max_account_bytes is null or p_max_account_bytes < 1 or p_max_account_bytes > 21474836480
     or p_max_account_documents is null or p_max_account_documents < 1 or p_max_account_documents > 5000
     or p_max_pending is null or p_max_pending < 1 or p_max_pending > 20
     or p_max_new_per_hour is null or p_max_new_per_hour < 1 or p_max_new_per_hour > 1000
     or p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 100 then
    raise exception 'Invalid Toolkit document limits';
  end if;
  v_cap := case when p_content_type = 'application/pdf'
    then p_max_document_bytes else p_max_image_bytes end;
  if p_size_bytes > v_cap then
    return query select 'too_large'::text, null::text, null::bigint;
    return;
  end if;

  -- Every authorize of one account serializes here, so the counts below cannot
  -- be raced by a second concurrent authorize of the same account.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('toolkit_documents:' || p_user_id::text, 0));

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id for update;
  if found then
    if v_row.owner_id <> p_user_id then
      return query select 'id_unavailable'::text, null::text, null::bigint;
      return;
    end if;
    if v_row.status in ('pending_delete', 'deleted') then
      return query select 'document_deleted'::text, v_row.status, v_row.version;
      return;
    end if;
    -- An abandoned-upload cleanup owns this row right now. Nothing may be uploaded
    -- for it until the cleanup has finished and removed it (the device retries).
    if v_row.status = 'pending_discard' then
      return query select 'cleanup_in_progress'::text, v_row.status, v_row.version;
      return;
    end if;
    if v_row.bucket <> p_bucket
       or v_row.document_type <> p_document_type
       or v_row.content_type <> p_content_type
       or v_row.size_bytes <> p_size_bytes
       or v_row.content_sha256 <> p_content_sha256 then
      return query select 'idempotency_mismatch'::text, v_row.status, v_row.version;
      return;
    end if;
    if v_row.status = 'ready' then
      return query select 'already_ready'::text, v_row.status, v_row.version;
      return;
    end if;
    if v_row.upload_attempts >= p_max_attempts then
      return query select 'rate_limited'::text, v_row.status, v_row.version;
      return;
    end if;
    update public.toolkit_documents as d
      set upload_attempts = d.upload_attempts + 1,
          last_authorized_at = pg_catalog.now()
      where d.id = p_document_id;
    return query select 'resumed'::text, 'pending_upload'::text, v_row.version + 1;
    return;
  end if;

  -- No row for this id. It is either new, or a document whose tombstone has been
  -- purged. The account's tombstone floor (the latest deletion time of any purged
  -- tombstone) tells them apart for an honest device: a document made on the
  -- device before that time may be one that was deleted and forgotten, so it is
  -- not re-created unless the user explicitly acknowledged (p_acknowledge_stale).
  select s.tombstone_floor into v_floor
    from public.toolkit_document_account_state as s where s.owner_id = p_user_id;
  if v_floor is not null and p_source_created_at <= v_floor and not p_acknowledge_stale then
    return query select 'stale_document'::text, null::text, null::bigint;
    return;
  end if;

  select pg_catalog.count(*) into v_recent from public.toolkit_documents as d
    where d.owner_id = p_user_id
      and d.created_at > pg_catalog.now() - interval '1 hour';
  if v_recent >= p_max_new_per_hour then
    return query select 'rate_limited'::text, null::text, null::bigint;
    return;
  end if;

  select pg_catalog.count(*) filter (where d.status = 'pending_upload'),
         pg_catalog.count(*),
         coalesce(pg_catalog.sum(d.size_bytes), 0)
    into v_pending, v_used_documents, v_used_bytes
    from public.toolkit_documents as d
    where d.owner_id = p_user_id and d.status in ('pending_upload', 'ready');
  if v_pending >= p_max_pending then
    return query select 'too_many_pending'::text, null::text, null::bigint;
    return;
  end if;
  if v_used_documents >= p_max_account_documents then
    return query select 'document_limit'::text, null::text, null::bigint;
    return;
  end if;
  if v_used_bytes + p_size_bytes > p_max_account_bytes then
    return query select 'storage_limit'::text, null::text, null::bigint;
    return;
  end if;

  -- A device clock may be wrong; a creation time more than a day ahead is not
  -- believed.
  v_source_created := case
    when p_source_created_at > pg_catalog.now() + interval '1 day'
    then pg_catalog.now() else p_source_created_at end;

  begin
    insert into public.toolkit_documents (
      id, owner_id, document_type, content_type, title, size_bytes, page_count,
      content_sha256, bucket, object_key, source_created_at,
      upload_attempts, last_authorized_at)
    values (
      p_document_id, p_user_id, p_document_type, p_content_type, p_title,
      p_size_bytes, p_page_count, p_content_sha256, p_bucket,
      public.toolkit_document_object_key(p_user_id, p_document_id, p_content_type),
      v_source_created, 1, pg_catalog.now());
  exception when unique_violation then
    -- Another account chose the same id in the same instant.
    return query select 'id_unavailable'::text, null::text, null::bigint;
    return;
  end;
  return query select 'created'::text, 'pending_upload'::text, 1::bigint;
end;
$function$;

-- ---------------------------------------------------------------------------
-- confirm: the Worker has proven the bytes; make the document ready
-- ---------------------------------------------------------------------------
-- What "ready" means is decided by the Worker before this is called, and the
-- facts are passed in, never assumed: the object exists, its byte length equals
-- the authorized size, its stored content type equals the declared one, its
-- leading and trailing bytes have the declared format's framing. The ETag is kept
-- only as an object-identity token (it is NOT a digest). p_sha256_verified says
-- whether the Worker itself hashed the stored object and found it equal to the
-- device-declared digest; when false the digest is only a device claim that the
-- app verifies on download.
-- Outcomes: confirmed, already_confirmed, not_found, document_deleted,
-- cleanup_in_progress (an abandoned-upload cleanup owns the row; retry later),
-- size_mismatch (the object is not the size that was authorized),
-- type_mismatch (the stored content type is not the declared one).

create function public.confirm_toolkit_document_upload(
  p_user_id uuid,
  p_document_id uuid,
  p_bucket text,
  p_observed_size bigint,
  p_observed_content_type text,
  p_observed_etag text,
  p_sha256_verified boolean
)
returns table(outcome text, version bigint)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_observed_size is null
     or p_observed_content_type is null
     or p_sha256_verified is null then
    raise exception 'Invalid Toolkit document confirmation';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id and d.bucket = p_bucket
    for update;
  if not found then
    return query select 'not_found'::text, null::bigint;
    return;
  end if;
  if v_row.status in ('pending_delete', 'deleted') then
    return query select 'document_deleted'::text, v_row.version;
    return;
  end if;
  -- A claimed upload can never become ready: that is what makes it safe for the
  -- cleanup to remove its object.
  if v_row.status = 'pending_discard' then
    return query select 'cleanup_in_progress'::text, v_row.version;
    return;
  end if;
  if v_row.status = 'ready' then
    return query select 'already_confirmed'::text, v_row.version;
    return;
  end if;
  if v_row.size_bytes <> p_observed_size then
    return query select 'size_mismatch'::text, v_row.version;
    return;
  end if;
  if v_row.content_type <> p_observed_content_type then
    return query select 'type_mismatch'::text, v_row.version;
    return;
  end if;

  update public.toolkit_documents as d
    set status = 'ready', confirmed_at = pg_catalog.now(),
        sha256_verified = p_sha256_verified,
        observed_etag = nullif(pg_catalog.left(p_observed_etag, 128), '')
    where d.id = p_document_id;
  return query select 'confirmed'::text, v_row.version + 1;
end;
$function$;

-- ---------------------------------------------------------------------------
-- rename: compare-and-swap on the version
-- ---------------------------------------------------------------------------
-- Outcomes: renamed (also when the title is already the requested one),
-- stale_version (title and version returned are the current ones),
-- not_found, document_deleted. A pending upload may be renamed.

create function public.rename_toolkit_document(
  p_user_id uuid,
  p_document_id uuid,
  p_title text,
  p_expected_version bigint
)
returns table(outcome text, title text, version bigint)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
begin
  if p_user_id is null or p_document_id is null or p_title is null
     or p_expected_version is null or p_expected_version < 1 then
    raise exception 'Invalid Toolkit document rename';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id for update;
  if not found then
    return query select 'not_found'::text, null::text, null::bigint;
    return;
  end if;
  if v_row.status in ('pending_delete', 'deleted') then
    return query select 'document_deleted'::text, null::text, v_row.version;
    return;
  end if;
  if v_row.status = 'pending_discard' then
    return query select 'cleanup_in_progress'::text, null::text, v_row.version;
    return;
  end if;
  if v_row.title = p_title then
    return query select 'renamed'::text, v_row.title, v_row.version;
    return;
  end if;
  if v_row.version <> p_expected_version then
    return query select 'stale_version'::text, v_row.title, v_row.version;
    return;
  end if;

  update public.toolkit_documents as d set title = p_title where d.id = p_document_id;
  return query select 'renamed'::text, p_title, v_row.version + 1;
end;
$function$;

-- ---------------------------------------------------------------------------
-- delete: mark, (the Worker removes the object), finalize
-- ---------------------------------------------------------------------------
-- begin outcomes: marked, already_pending, already_deleted, not_found,
-- status_changed (p_expected_status was given and no longer holds). A row is
-- also returned with its key and the last time an upload was authorized, so the
-- Worker can confirm the key and wait out a still-valid signed PUT.

create function public.begin_toolkit_document_delete(
  p_user_id uuid,
  p_document_id uuid,
  p_bucket text,
  p_expected_status text
)
returns table(outcome text, object_key text, last_authorized_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or (p_expected_status is not null
         and p_expected_status not in ('pending_upload', 'ready', 'pending_delete')) then
    raise exception 'Invalid Toolkit document removal';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id and d.bucket = p_bucket
    for update;
  if not found then
    return query select 'not_found'::text, null::text, null::timestamptz;
    return;
  end if;
  if v_row.status = 'deleted' then
    return query select 'already_deleted'::text, v_row.object_key, v_row.last_authorized_at;
    return;
  end if;
  if p_expected_status is not null and v_row.status <> p_expected_status then
    return query select 'status_changed'::text, v_row.object_key, v_row.last_authorized_at;
    return;
  end if;
  if v_row.status = 'pending_delete' then
    return query select 'already_pending'::text, v_row.object_key, v_row.last_authorized_at;
    return;
  end if;

  update public.toolkit_documents as d
    set status = 'pending_delete', deleted_at = pg_catalog.now(), discard_claimed_at = null
    where d.id = p_document_id;
  return query select 'marked'::text, v_row.object_key, v_row.last_authorized_at;
end;
$function$;

-- finalize outcomes: deleted (the `deleted` tombstone, at most 500 per account),
-- too_soon (an upload was
-- authorized within p_min_upload_age_seconds, so its signed PUT may still be
-- live: the object is removed again later), not_pending, already_deleted,
-- not_found.

create function public.finalize_toolkit_document_delete(
  p_user_id uuid,
  p_document_id uuid,
  p_bucket text,
  p_min_upload_age_seconds integer
)
returns table(outcome text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_min_upload_age_seconds is null or p_min_upload_age_seconds < 0 then
    raise exception 'Invalid Toolkit document finalization';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id and d.bucket = p_bucket
    for update;
  if not found then
    return query select 'not_found'::text;
    return;
  end if;
  if v_row.status = 'deleted' then
    return query select 'already_deleted'::text;
    return;
  end if;
  if v_row.status <> 'pending_delete' then
    return query select 'not_pending'::text;
    return;
  end if;
  if v_row.last_authorized_at is not null
     and v_row.last_authorized_at + pg_catalog.make_interval(secs => p_min_upload_age_seconds)
         > pg_catalog.now() then
    return query select 'too_soon'::text;
    return;
  end if;

  -- The tombstone keeps the id and the facts needed to refuse a re-creation, not
  -- the user's title.
  update public.toolkit_documents as d
    set status = 'deleted', title = 'Deleted document'
    where d.id = p_document_id;

  -- Bounded history: an account keeps at most 500 tombstones. Older ones are
  -- purged at once and the account's tombstone floor advances to the latest of
  -- them, so a purged tombstone never allows its document to come back (see
  -- authorize), while an account that churns documents cannot grow the table
  -- without limit. An ordinary account never reaches 500 deletions.
  with doomed as (
    select d.id, d.deleted_at from public.toolkit_documents as d
      where d.owner_id = p_user_id and d.status = 'deleted'
      order by d.deleted_at desc, d.id desc
      offset 500
  ), gone as (
    delete from public.toolkit_documents as d
      using doomed
      where d.id = doomed.id
      returning doomed.deleted_at
  )
  insert into public.toolkit_document_account_state as s (owner_id, tombstone_floor)
    select p_user_id, pg_catalog.max(gone.deleted_at) from gone
    having pg_catalog.count(*) > 0
  on conflict (owner_id) do update
    set tombstone_floor = greatest(s.tombstone_floor, excluded.tombstone_floor),
        updated_at = pg_catalog.now();
  return query select 'deleted'::text;
end;
$function$;

-- Abandoned-upload cleanup is CLAIM-FIRST. An upload that was authorized but never
-- became ready, and has not been touched since p_cutoff, is removed WITHOUT a
-- tombstone (nobody deleted it, so a slow device may still upload the same
-- document later) in three steps that are safe against every concurrent
-- authorize, confirm, delete and second sweep:
--   1. claim_abandoned_toolkit_document moves the row pending_upload ->
--      pending_discard under its row lock and returns the claim identity. From
--      then on confirm and authorize refuse the row (cleanup_in_progress), so it
--      can NEVER become ready, and any signed PUT it ever had expired long before
--      the cutoff. A row that was re-authorized or confirmed first is simply not
--      claimable (not_abandoned), so a ready document's object is never touched.
--   2. The Worker removes the object. A failed removal leaves the row claimed;
--      once the lease has passed the cleanup claims it again (a new identity) and
--      retries, so nothing is lost and nothing is orphaned.
--   3. discard_abandoned_toolkit_document removes the row only for the exact claim
--      identity it was given (not_claimed otherwise, e.g. the user deleted the
--      document meanwhile: that moves it to pending_delete with a tombstone).
-- Claim outcomes: claimed (object_key and claimed_at returned), claim_held (another
-- cleanup holds an unexpired lease), not_abandoned, not_found.
create function public.claim_abandoned_toolkit_document(
  p_user_id uuid,
  p_document_id uuid,
  p_bucket text,
  p_cutoff timestamptz,
  p_lease_seconds integer
)
returns table(outcome text, object_key text, claimed_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null or p_cutoff is null
     or p_lease_seconds is null or p_lease_seconds < 60 or p_lease_seconds > 3600 then
    raise exception 'Invalid Toolkit document claim';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id and d.bucket = p_bucket
    for update;
  if not found then
    return query select 'not_found'::text, null::text, null::timestamptz;
    return;
  end if;

  if v_row.status = 'pending_discard' then
    if v_row.discard_claimed_at > v_now - pg_catalog.make_interval(secs => p_lease_seconds) then
      return query select 'claim_held'::text, null::text, null::timestamptz;
      return;
    end if;
    -- The earlier cleanup never finished (its object removal failed or its worker
    -- stopped): take over under a new identity so its late discard cannot win.
  elsif v_row.status <> 'pending_upload'
        or v_row.last_authorized_at is null or v_row.last_authorized_at > p_cutoff then
    return query select 'not_abandoned'::text, null::text, null::timestamptz;
    return;
  end if;

  update public.toolkit_documents as d
    set status = 'pending_discard', discard_claimed_at = v_now
    where d.id = p_document_id;
  return query select 'claimed'::text, v_row.object_key, v_now;
end;
$function$;

-- Step 3. Outcomes: discarded, not_claimed (the row is not in this claim any more),
-- not_found.
create function public.discard_abandoned_toolkit_document(
  p_user_id uuid,
  p_document_id uuid,
  p_bucket text,
  p_claimed_at timestamptz
)
returns table(outcome text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.toolkit_documents%rowtype;
begin
  if p_user_id is null or p_document_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null or p_claimed_at is null then
    raise exception 'Invalid Toolkit document discard';
  end if;

  select d.* into v_row from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id and d.bucket = p_bucket
    for update;
  if not found then
    return query select 'not_found'::text;
    return;
  end if;
  if v_row.status <> 'pending_discard'
     or v_row.discard_claimed_at is distinct from p_claimed_at then
    return query select 'not_claimed'::text;
    return;
  end if;

  delete from public.toolkit_documents as d where d.id = p_document_id;
  return query select 'discarded'::text;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Reads for the Worker (always scoped by the verified account id)
-- ---------------------------------------------------------------------------

-- Ready documents of one bucket, newest first, after an optional keyset cursor.
-- Staging and production share this database and differ only in their bucket,
-- so every read the Worker serves is scoped to its own.
create function public.list_toolkit_documents(
  p_user_id uuid,
  p_bucket text,
  p_limit integer,
  p_before_created_at timestamptz,
  p_before_id uuid,
  p_document_type text
)
returns table(
  id uuid, document_type text, content_type text, title text, size_bytes bigint,
  page_count integer, content_sha256 text, sha256_verified boolean,
  source_created_at timestamptz, created_at timestamptz,
  confirmed_at timestamptz, version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_user_id is null or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_limit is null or p_limit < 1 or p_limit > 101
     or (p_document_type is not null
         and p_document_type not in ('scanner', 'combine_pdfs', 'image_to_pdf', 'signature'))
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Invalid Toolkit document listing';
  end if;
  return query
    select d.id, d.document_type, d.content_type, d.title, d.size_bytes, d.page_count,
           d.content_sha256, d.sha256_verified, d.source_created_at, d.created_at,
           d.confirmed_at, d.version
    from public.toolkit_documents as d
    where d.owner_id = p_user_id
      and d.bucket = p_bucket
      and d.status = 'ready'
      and (p_document_type is null or d.document_type = p_document_type)
      and (p_before_created_at is null
           or (d.created_at, d.id) < (p_before_created_at, p_before_id))
    order by d.created_at desc, d.id desc
    limit p_limit;
end;
$function$;

-- One document of the account, with what the Worker needs to verify it.
create function public.get_toolkit_document(p_user_id uuid, p_document_id uuid)
returns table(
  id uuid, owner_id uuid, document_type text, title text, content_type text,
  size_bytes bigint, page_count integer, content_sha256 text, sha256_verified boolean,
  bucket text, object_key text, observed_etag text, status text, version bigint,
  last_authorized_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select d.id, d.owner_id, d.document_type, d.title, d.content_type,
         d.size_bytes, d.page_count, d.content_sha256, d.sha256_verified, d.bucket,
         d.object_key, d.observed_etag, d.status, d.version, d.last_authorized_at
  from public.toolkit_documents as d
  where d.id = p_document_id and d.owner_id = p_user_id;
$function$;

-- The state of up to 100 of the account's documents of one bucket by id. Ids
-- that do not exist, belong to another account or live in another bucket are
-- simply absent from the result.
create function public.toolkit_document_statuses(p_user_id uuid, p_bucket text, p_ids uuid[])
returns table(id uuid, status text, version bigint)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_user_id is null or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_ids is null or pg_catalog.cardinality(p_ids) > 100 then
    raise exception 'Invalid Toolkit document status request';
  end if;
  return query
    select d.id, d.status, d.version
    from public.toolkit_documents as d
    where d.owner_id = p_user_id and d.bucket = p_bucket and d.id = any (p_ids);
end;
$function$;

-- What the account holds, for the library header and the Worker's own logs.
create function public.toolkit_document_usage(p_user_id uuid)
returns table(ready_count bigint, ready_bytes bigint, pending_count bigint, pending_bytes bigint)
language sql
stable
security definer
set search_path = ''
as $function$
  select pg_catalog.count(*) filter (where d.status = 'ready'),
         coalesce(pg_catalog.sum(d.size_bytes) filter (where d.status = 'ready'), 0)::bigint,
         pg_catalog.count(*) filter (where d.status = 'pending_upload'),
         coalesce(pg_catalog.sum(d.size_bytes) filter (where d.status = 'pending_upload'), 0)::bigint
  from public.toolkit_documents as d
  where d.owner_id = p_user_id and d.status in ('pending_upload', 'ready');
$function$;

-- ---------------------------------------------------------------------------
-- Scheduled cleanup candidates (service role only; the Worker acts on them)
-- ---------------------------------------------------------------------------
--   abandoned_pending  pending_upload not (re)authorized since p_cutoff (to be claimed)
--   stuck_discard      pending_discard claimed at or before p_cutoff (a cleanup that
--                      never finished; to be claimed again)
--   pending_delete     marked for removal at or before p_cutoff
--   old_tombstones     `deleted` tombstones older than p_cutoff
create function public.list_toolkit_document_cleanup(
  p_kind text,
  p_bucket text,
  p_cutoff timestamptz,
  p_limit integer
)
returns table(id uuid, owner_id uuid, bucket text, object_key text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_kind is null or p_kind not in ('abandoned_pending', 'stuck_discard', 'pending_delete', 'old_tombstones')
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_cutoff is null or p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'Invalid Toolkit document cleanup request';
  end if;
  return query
    select d.id, d.owner_id, d.bucket, d.object_key, d.status
    from public.toolkit_documents as d
    where d.bucket = p_bucket and case p_kind
      when 'abandoned_pending' then
        d.status = 'pending_upload' and d.last_authorized_at <= p_cutoff
      when 'stuck_discard' then
        d.status = 'pending_discard' and d.discard_claimed_at <= p_cutoff
      when 'pending_delete' then
        d.status = 'pending_delete' and d.deleted_at <= p_cutoff
      else
        d.status = 'deleted' and d.deleted_at <= p_cutoff
      end
    order by d.created_at, d.id
    limit p_limit;
end;
$function$;

-- Purging a tombstone also advances the account's tombstone floor to that
-- tombstone's deletion time (never backwards), in the same transaction, so the
-- fact that "something was deleted by then" outlives the row.
create function public.purge_toolkit_document_tombstone(
  p_user_id uuid,
  p_document_id uuid,
  p_cutoff timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_deleted timestamptz;
begin
  if p_user_id is null or p_document_id is null or p_cutoff is null then
    raise exception 'Invalid Toolkit tombstone purge';
  end if;
  delete from public.toolkit_documents as d
    where d.id = p_document_id and d.owner_id = p_user_id
      and d.status = 'deleted' and d.deleted_at <= p_cutoff
    returning d.deleted_at into v_deleted;
  if v_deleted is null then
    return false;
  end if;
  insert into public.toolkit_document_account_state as s (owner_id, tombstone_floor)
    values (p_user_id, v_deleted)
    on conflict (owner_id) do update
      set tombstone_floor = greatest(s.tombstone_floor, excluded.tombstone_floor),
          updated_at = pg_catalog.now();
  return true;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Privileges: service role only (the guard trigger function is not callable)
-- ---------------------------------------------------------------------------

revoke all on function public.toolkit_document_rules(text) from public, anon, authenticated;
revoke all on function public.toolkit_document_object_key(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.guard_toolkit_document() from public, anon, authenticated;
revoke all on function public.authorize_toolkit_document_upload(
  uuid, uuid, text, text, text, bigint, integer, text, timestamptz, text,
  bigint, bigint, bigint, integer, integer, integer, integer, boolean)
  from public, anon, authenticated;
revoke all on function public.confirm_toolkit_document_upload(
  uuid, uuid, text, bigint, text, text, boolean) from public, anon, authenticated;
revoke all on function public.rename_toolkit_document(
  uuid, uuid, text, bigint) from public, anon, authenticated;
revoke all on function public.begin_toolkit_document_delete(
  uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.finalize_toolkit_document_delete(
  uuid, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.claim_abandoned_toolkit_document(
  uuid, uuid, text, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.discard_abandoned_toolkit_document(
  uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.list_toolkit_documents(
  uuid, text, integer, timestamptz, uuid, text) from public, anon, authenticated;
revoke all on function public.get_toolkit_document(uuid, uuid) from public, anon, authenticated;
revoke all on function public.toolkit_document_statuses(uuid, text, uuid[]) from public, anon, authenticated;
revoke all on function public.toolkit_document_usage(uuid) from public, anon, authenticated;
revoke all on function public.list_toolkit_document_cleanup(
  text, text, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.purge_toolkit_document_tombstone(
  uuid, uuid, timestamptz) from public, anon, authenticated;

grant execute on function public.toolkit_document_rules(text) to service_role;
grant execute on function public.toolkit_document_object_key(uuid, uuid, text) to service_role;
grant execute on function public.authorize_toolkit_document_upload(
  uuid, uuid, text, text, text, bigint, integer, text, timestamptz, text,
  bigint, bigint, bigint, integer, integer, integer, integer, boolean)
  to service_role;
grant execute on function public.confirm_toolkit_document_upload(
  uuid, uuid, text, bigint, text, text, boolean) to service_role;
grant execute on function public.rename_toolkit_document(
  uuid, uuid, text, bigint) to service_role;
grant execute on function public.begin_toolkit_document_delete(
  uuid, uuid, text, text) to service_role;
grant execute on function public.finalize_toolkit_document_delete(
  uuid, uuid, text, integer) to service_role;
grant execute on function public.claim_abandoned_toolkit_document(
  uuid, uuid, text, timestamptz, integer) to service_role;
grant execute on function public.discard_abandoned_toolkit_document(
  uuid, uuid, text, timestamptz) to service_role;
grant execute on function public.list_toolkit_documents(
  uuid, text, integer, timestamptz, uuid, text) to service_role;
grant execute on function public.get_toolkit_document(uuid, uuid) to service_role;
grant execute on function public.toolkit_document_statuses(uuid, text, uuid[]) to service_role;
grant execute on function public.toolkit_document_usage(uuid) to service_role;
grant execute on function public.list_toolkit_document_cleanup(
  text, text, timestamptz, integer) to service_role;
grant execute on function public.purge_toolkit_document_tombstone(
  uuid, uuid, timestamptz) to service_role;

comment on function public.authorize_toolkit_document_upload(
  uuid, uuid, text, text, text, bigint, integer, text, timestamptz, text,
  bigint, bigint, bigint, integer, integer, integer, integer, boolean) is
  'Worker-only: reserve or resume a Toolkit document upload (PDF, or Scanner JPEG / PNG) within the configured anti-abuse limits (hard ceilings enforced here).';
comment on function public.confirm_toolkit_document_upload(uuid, uuid, text, bigint, text, text, boolean) is
  'Worker-only: mark a Toolkit upload ready after the Worker verified the stored object. Idempotent.';
comment on function public.purge_toolkit_document_tombstone(uuid, uuid, timestamptz) is
  'Worker-only: purge an old tombstone and advance the account tombstone floor.';
comment on function public.rename_toolkit_document(uuid, uuid, text, bigint) is
  'Worker-only: rename with a compare-and-swap on the version.';
comment on function public.begin_toolkit_document_delete(uuid, uuid, text, text) is
  'Worker-only: first step of a delete (mark pending_delete). Idempotent.';
comment on function public.finalize_toolkit_document_delete(uuid, uuid, text, integer) is
  'Worker-only: last step of a delete, after the R2 object is gone. Writes the deleted tombstone.';
comment on function public.claim_abandoned_toolkit_document(uuid, uuid, text, timestamptz, integer) is
  'Worker-only: first step of the abandoned-upload cleanup. Moves an idle pending upload to pending_discard under its row lock (it can then never become ready) and returns the claim identity.';
comment on function public.discard_abandoned_toolkit_document(uuid, uuid, text, timestamptz) is
  'Worker-only: last step of the abandoned-upload cleanup. Removes the row, without a tombstone, only for the exact claim identity returned by the claim, after the object is gone.';

-- Reversal (not part of this migration). Only after every Worker version that
-- calls these functions has been rolled back; until then dropping them makes
-- every Toolkit document route fail closed. Dropping the table removes the
-- metadata, NOT the files: objects under profiles/<uid>/toolkit-documents/ stay
-- in R2 until Delete Account's prefix sweep or a manual cleanup removes them, so
-- list and archive them first if the data matters.
--
--   drop function if exists public.purge_toolkit_document_tombstone(uuid, uuid, timestamptz);
--   drop function if exists public.list_toolkit_document_cleanup(text, text, timestamptz, integer);
--   drop function if exists public.toolkit_document_usage(uuid);
--   drop function if exists public.toolkit_document_statuses(uuid, text, uuid[]);
--   drop function if exists public.get_toolkit_document(uuid, uuid);
--   drop function if exists public.list_toolkit_documents(uuid, text, integer, timestamptz, uuid, text);
--   drop function if exists public.discard_abandoned_toolkit_document(uuid, uuid, text, timestamptz);
--   drop function if exists public.claim_abandoned_toolkit_document(uuid, uuid, text, timestamptz, integer);
--   drop function if exists public.finalize_toolkit_document_delete(uuid, uuid, text, integer);
--   drop function if exists public.begin_toolkit_document_delete(uuid, uuid, text, text);
--   drop function if exists public.rename_toolkit_document(uuid, uuid, text, bigint);
--   drop function if exists public.confirm_toolkit_document_upload(uuid, uuid, text, bigint, text, text, boolean);
--   drop function if exists public.authorize_toolkit_document_upload(
--     uuid, uuid, text, text, text, bigint, integer, text, timestamptz, text,
--     bigint, bigint, bigint, integer, integer, integer, integer, boolean);
--   drop table if exists public.toolkit_document_account_state;
--   drop table if exists public.toolkit_documents;
--   drop function if exists public.guard_toolkit_document();
--   drop function if exists public.toolkit_document_object_key(uuid, uuid, text);
--   drop function if exists public.toolkit_document_rules(text);
