-- Quotation private media slots. The Worker verifies the bearer with Supabase
-- Auth and the bytes in private R2, then calls these service-role-only RPCs.
-- The existing quotation_media roles are logo/pdf; the public Worker role names
-- and R2 key segments are office_logo/quotation_pdf. The migration runner
-- supplies the transaction so validation can include this exact file inside
-- BEGIN ... ROLLBACK.

create function public.confirm_quotation_media_upload(
  p_user_id uuid,
  p_quotation_id uuid,
  p_media_id uuid,
  p_role text,
  p_bucket text,
  p_expected_media_id uuid,
  p_observed_size bigint,
  p_observed_content_type text
)
returns table(outcome text, previous_media_id uuid, resulting_version bigint)
language plpgsql security definer set search_path = ''
as $function$
declare
  v_quote public.quotations%rowtype;
  v_media public.media_objects%rowtype;
  v_current uuid;
  v_link_role text;
  v_extension text;
  v_media_type text;
  v_max_size bigint;
  v_key text;
begin
  if p_user_id is null or p_quotation_id is null or p_media_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_role is null or p_role not in ('office_logo', 'quotation_pdf') then
    raise exception 'Invalid quotation media request';
  end if;

  if p_role = 'office_logo' then
    v_link_role := 'logo';
    v_media_type := 'image';
    v_max_size := 10485760;
    v_extension := case p_observed_content_type
      when 'image/jpeg' then 'jpg'
      when 'image/png' then 'png'
      when 'image/webp' then 'webp'
      else null end;
  else
    v_link_role := 'pdf';
    v_media_type := 'pdf';
    v_max_size := 20971520;
    v_extension := case p_observed_content_type
      when 'application/pdf' then 'pdf' else null end;
  end if;
  if v_extension is null or p_observed_size is null
     or p_observed_size < 1 or p_observed_size > v_max_size then
    raise exception 'Invalid quotation media type or size';
  end if;
  v_key := 'profiles/' || p_user_id::text || '/quotations/' ||
    p_quotation_id::text || '/' || p_role || '/' || p_media_id::text ||
    '.' || v_extension;

  -- All slot changes, including removal and soft-delete, serialize here.
  select q.* into v_quote from public.quotations as q
    where q.id = p_quotation_id and q.owner_id = p_user_id for update;
  if not found or v_quote.deleted_at is not null then
    return query select 'quotation_not_found'::text, null::uuid, null::bigint;
    return;
  end if;
  v_current := case p_role when 'office_logo' then v_quote.office_logo_media_id
    else v_quote.pdf_media_id end;

  select mo.* into v_media from public.media_objects as mo
    where mo.id = p_media_id and mo.owner_id = p_user_id
      and mo.bucket = p_bucket for update;
  if not found or v_media.object_key is distinct from v_key
     or v_media.content_type is distinct from p_observed_content_type
     or v_media.media_type::text is distinct from v_media_type then
    return query select 'media_not_found'::text, null::uuid, v_quote.version;
    return;
  end if;

  if v_current = p_media_id and v_media.status = 'ready'
     and exists (select 1 from public.quotation_media as qm
       where qm.quotation_id = p_quotation_id and qm.media_id = p_media_id
         and qm.role = v_link_role and qm.ordinal = 0) then
    return query select 'already_attached'::text, null::uuid, v_quote.version;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid, v_quote.version;
    return;
  end if;
  if v_media.status <> 'pending_upload' then
    return query select 'invalid_status'::text, null::uuid, v_quote.version;
    return;
  end if;
  -- A media identity is single-use, even if a privileged caller previously
  -- attached it through another Quotation slot.
  if exists (select 1 from public.quotation_media as qm
       where qm.media_id = p_media_id)
     or exists (select 1 from public.quotations as q
       where q.office_logo_media_id = p_media_id or q.pdf_media_id = p_media_id) then
    return query select 'media_already_bound'::text, null::uuid, v_quote.version;
    return;
  end if;
  if v_current is not null and (
     exists (select 1 from public.quotation_media as qm
       where qm.media_id = v_current and
         (qm.quotation_id <> p_quotation_id or qm.role <> v_link_role))
     or exists (select 1 from public.quotations as q
       where q.id <> p_quotation_id and
         (q.office_logo_media_id = v_current or q.pdf_media_id = v_current))
     or (case p_role when 'office_logo' then v_quote.pdf_media_id
         else v_quote.office_logo_media_id end) = v_current) then
    return query select 'invalid_state'::text, null::uuid, v_quote.version;
    return;
  end if;
  if v_current is not null and not exists (
    select 1 from public.quotation_media as qm
    join public.media_objects as old on old.id = qm.media_id
    where qm.quotation_id = p_quotation_id and qm.media_id = v_current
      and qm.role = v_link_role and qm.ordinal = 0
      and old.owner_id = p_user_id and old.bucket = p_bucket
      and old.status = 'ready'
      and pg_catalog.starts_with(old.object_key,
        'profiles/' || p_user_id::text || '/quotations/' ||
        p_quotation_id::text || '/' || p_role || '/')) then
    return query select 'invalid_state'::text, null::uuid, v_quote.version;
    return;
  end if;

  delete from public.quotation_media as qm
    where qm.quotation_id = p_quotation_id and qm.role = v_link_role;
  insert into public.quotation_media (quotation_id, media_id, role, ordinal)
    values (p_quotation_id, p_media_id, v_link_role, 0);
  update public.media_objects as mo set status = 'ready',
    size_bytes = p_observed_size, content_type = p_observed_content_type
    where mo.id = p_media_id;
  if p_role = 'office_logo' then
    update public.quotations as q set office_logo_media_id = p_media_id
      where q.id = p_quotation_id returning q.version into v_quote.version;
  else
    update public.quotations as q set pdf_media_id = p_media_id
      where q.id = p_quotation_id returning q.version into v_quote.version;
  end if;
  if v_current is not null then
    update public.media_objects as mo set status = 'pending_delete',
      deleted_at = pg_catalog.now()
      where mo.id = v_current and mo.status = 'ready';
    if not found then raise exception 'Previous quotation media changed'; end if;
  end if;
  return query select 'attached'::text, v_current, v_quote.version;
end;
$function$;

create function public.remove_quotation_media(
  p_user_id uuid,
  p_quotation_id uuid,
  p_role text,
  p_bucket text,
  p_expected_media_id uuid
)
returns table(outcome text, previous_media_id uuid, resulting_version bigint)
language plpgsql security definer set search_path = ''
as $function$
declare
  v_quote public.quotations%rowtype;
  v_current uuid;
  v_link_role text;
begin
  if p_user_id is null or p_quotation_id is null
     or nullif(pg_catalog.btrim(p_bucket), '') is null
     or p_role is null or p_role not in ('office_logo', 'quotation_pdf') then
    raise exception 'Invalid quotation media removal';
  end if;
  v_link_role := case p_role when 'office_logo' then 'logo' else 'pdf' end;
  select q.* into v_quote from public.quotations as q
    where q.id = p_quotation_id and q.owner_id = p_user_id for update;
  if not found or v_quote.deleted_at is not null then
    return query select 'quotation_not_found'::text, null::uuid, null::bigint;
    return;
  end if;
  v_current := case p_role when 'office_logo' then v_quote.office_logo_media_id
    else v_quote.pdf_media_id end;
  if v_current is null then
    return query select 'already_removed'::text, null::uuid, v_quote.version;
    return;
  end if;
  if v_current is distinct from p_expected_media_id then
    return query select 'stale_replacement'::text, null::uuid, v_quote.version;
    return;
  end if;
  if exists (select 1 from public.quotation_media as qm
       where qm.media_id = v_current and
         (qm.quotation_id <> p_quotation_id or qm.role <> v_link_role))
     or exists (select 1 from public.quotations as q
       where q.id <> p_quotation_id and
         (q.office_logo_media_id = v_current or q.pdf_media_id = v_current))
     or (case p_role when 'office_logo' then v_quote.pdf_media_id
         else v_quote.office_logo_media_id end) = v_current then
    return query select 'invalid_state'::text, null::uuid, v_quote.version;
    return;
  end if;
  if not exists (select 1 from public.quotation_media as qm
    join public.media_objects as mo on mo.id = qm.media_id
    where qm.quotation_id = p_quotation_id and qm.media_id = v_current
      and qm.role = v_link_role and qm.ordinal = 0
      and mo.owner_id = p_user_id and mo.bucket = p_bucket
      and mo.status = 'ready'
      and pg_catalog.starts_with(mo.object_key,
        'profiles/' || p_user_id::text || '/quotations/' ||
        p_quotation_id::text || '/' || p_role || '/')) then
    return query select 'invalid_state'::text, null::uuid, v_quote.version;
    return;
  end if;
  if p_role = 'office_logo' then
    update public.quotations as q set office_logo_media_id = null
      where q.id = p_quotation_id returning q.version into v_quote.version;
  else
    update public.quotations as q set pdf_media_id = null
      where q.id = p_quotation_id returning q.version into v_quote.version;
  end if;
  delete from public.quotation_media as qm
    where qm.quotation_id = p_quotation_id and qm.media_id = v_current;
  update public.media_objects as mo set status = 'pending_delete',
    deleted_at = pg_catalog.now()
    where mo.id = v_current and mo.status = 'ready';
  if not found then raise exception 'Quotation media changed'; end if;
  return query select 'removed'::text, v_current, v_quote.version;
end;
$function$;

revoke all on function public.confirm_quotation_media_upload(
  uuid, uuid, uuid, text, text, uuid, bigint, text)
  from public, anon, authenticated;
grant execute on function public.confirm_quotation_media_upload(
  uuid, uuid, uuid, text, text, uuid, bigint, text) to service_role;
revoke all on function public.remove_quotation_media(
  uuid, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.remove_quotation_media(
  uuid, uuid, text, text, uuid) to service_role;

comment on function public.confirm_quotation_media_upload(
  uuid, uuid, uuid, text, text, uuid, bigint, text) is
  'Worker-only atomic Quotation logo/PDF bind; exact owner, role, key, MIME, state and compare-and-swap slot checks.';
comment on function public.remove_quotation_media(
  uuid, uuid, text, text, uuid) is
  'Worker-only atomic Quotation logo/PDF removal with compare-and-swap slot check.';
