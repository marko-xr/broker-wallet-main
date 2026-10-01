-- One authenticated, atomic save for the non-media Quotation aggregate.
-- The caller supplies one stable UUID per logical create. A retry with the
-- identical persisted aggregate is replayed; a different payload conflicts.
-- Authenticated clients retain owner-scoped reads and direct soft delete only.
-- This SECURITY DEFINER function is the sole ordinary aggregate-write path.
-- It must be created by postgres, the existing table owner; RLS is bypassed
-- inside it, so every parent lookup/write explicitly checks auth.uid().
-- Apply the whole file in one migration transaction. It has no transaction
-- control so validation can include this exact file inside BEGIN ... ROLLBACK.
-- Never execute its statements one by one on a hosted database.

do $owner_check$
begin
  if current_user <> 'postgres'
     or not (select rolbypassrls from pg_catalog.pg_roles where rolname = 'postgres')
     or (select count(*) from pg_catalog.pg_class c
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in (
           'quotations', 'quotation_downpayments',
           'quotation_government_fees', 'quotation_administrative_fees')
           and pg_catalog.pg_get_userbyid(c.relowner) = 'postgres'
           and c.relrowsecurity and not c.relforcerowsecurity) <> 4 then
    raise exception 'save_quotation requires postgres-owned RLS quotation tables';
  end if;
end;
$owner_check$;

create function public.save_quotation(
  p_quotation_id uuid,
  p_expected_version bigint,
  p_header jsonb,
  p_downpayments jsonb,
  p_government_fees jsonb,
  p_administrative_fees jsonb
)
returns table (
  quotation_id uuid,
  resulting_version bigint,
  outcome text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_header record;
  v_quote public.quotations%rowtype;
  v_item jsonb;
  v_key text;
  v_header_keys constant text[] := array[
    'property_title', 'property_type', 'parking', 'subtitle', 'display_date',
    'start_date_text', 'end_date_text', 'currency_code', 'professional_fee',
    'total_amount', 'number_of_installments', 'payment_type',
    'insurance_amount', 'insurance_returnable', 'office_name', 'custom_note',
    'welcome_message_mode', 'custom_welcome_message'
  ];
  v_downpayment_keys constant text[] := array['sequence_number', 'method', 'due_at', 'amount'];
  v_government_keys constant text[] := array[
    'percent_of_total_rent', 'municipality', 'electricity', 'sewerage', 'total'
  ];
  v_administrative_keys constant text[] := array['ordinal', 'title', 'amount'];
  v_seen integer[];
  v_position integer;
  v_stored jsonb;
  v_submitted jsonb;
  v_action text;
begin
  if v_user is null then
    raise exception using errcode = 'PQT01', message = 'unauthenticated';
  end if;

  if p_quotation_id is null or (p_expected_version is not null and p_expected_version < 1)
     or p_header is null or jsonb_typeof(p_header) <> 'object'
     or p_downpayments is null or jsonb_typeof(p_downpayments) <> 'array'
     or p_administrative_fees is null or jsonb_typeof(p_administrative_fees) <> 'array'
     or (p_government_fees is not null
         and jsonb_typeof(p_government_fees) not in ('object', 'null')) then
    raise exception using errcode = 'PQT05', message = 'invalid_payload';
  end if;

  -- The header is a complete replacement. Every nullable value is explicit
  -- JSON null; absent keys and server-owned/unknown keys are rejected.
  if not (p_header ?& v_header_keys)
     or exists (select 1 from jsonb_object_keys(p_header) as keys(key)
                where keys.key <> all(v_header_keys)) then
    raise exception using errcode = 'PQT05', message = 'invalid_payload';
  end if;
  foreach v_key in array v_header_keys loop
    if (v_key = any(array['property_title', 'currency_code', 'office_name', 'welcome_message_mode'])
        and jsonb_typeof(p_header -> v_key) <> 'string')
       or (v_key = any(array['property_type', 'subtitle', 'display_date', 'start_date_text',
                               'end_date_text', 'custom_note', 'custom_welcome_message', 'payment_type'])
           and jsonb_typeof(p_header -> v_key) not in ('string', 'null'))
       or (v_key = any(array['parking', 'insurance_returnable'])
           and jsonb_typeof(p_header -> v_key) not in ('boolean', 'null'))
       or (v_key = any(array['professional_fee', 'total_amount', 'number_of_installments',
                               'insurance_amount'])
           and jsonb_typeof(p_header -> v_key) not in ('number', 'null')) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
  end loop;
  if btrim(p_header ->> 'property_title') = ''
     or length(p_header ->> 'currency_code') <> 3
     or (p_header ->> 'currency_code') <> upper(p_header ->> 'currency_code')
     or (p_header ->> 'welcome_message_mode') not in ('auto', 'custom', 'hidden')
     or (p_header ->> 'payment_type') is not null
        and (p_header ->> 'payment_type') not in ('cash', 'cheque', 'bank_transfer', 'other')
     or (p_header ->> 'welcome_message_mode') = 'custom'
        and nullif(btrim(p_header ->> 'custom_welcome_message'), '') is null then
    raise exception using errcode = 'PQT05', message = 'invalid_payload';
  end if;
  if jsonb_typeof(p_header -> 'number_of_installments') = 'number'
     and (p_header ->> 'number_of_installments')::numeric <> trunc((p_header ->> 'number_of_installments')::numeric) then
    raise exception using errcode = 'PQT05', message = 'invalid_payload';
  end if;

  select * into v_header from jsonb_to_record(p_header) as h(
    property_title text, property_type text, parking boolean, subtitle text,
    display_date text, start_date_text text, end_date_text text,
    currency_code varchar(3), professional_fee numeric(14,2),
    total_amount numeric(14,2), number_of_installments integer,
    payment_type public.payment_method, insurance_amount numeric(14,2),
    insurance_returnable boolean, office_name text, custom_note text,
    welcome_message_mode public.welcome_message_mode, custom_welcome_message text
  );

  v_seen := array[]::integer[];
  for v_item in select value from jsonb_array_elements(p_downpayments) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    if not (v_item ?& v_downpayment_keys)
       or exists (select 1 from jsonb_object_keys(v_item) as keys(key)
                  where keys.key <> all(v_downpayment_keys))
       or jsonb_typeof(v_item -> 'sequence_number') <> 'number'
       or jsonb_typeof(v_item -> 'method') <> 'string'
       or jsonb_typeof(v_item -> 'due_at') not in ('string', 'null')
       or jsonb_typeof(v_item -> 'amount') <> 'number'
       or (v_item ->> 'method') not in ('cash', 'cheque', 'bank_transfer', 'other') then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    -- A timestamptz without an offset would depend on the database session's
    -- TimeZone. Require an explicit offset for deterministic persistence.
    if jsonb_typeof(v_item -> 'due_at') = 'string'
       and (v_item ->> 'due_at') !~
         '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    if (v_item ->> 'sequence_number')::numeric <> trunc((v_item ->> 'sequence_number')::numeric) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    v_position := (v_item ->> 'sequence_number')::integer;
    if v_position < 1 or v_position = any(v_seen) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    v_seen := array_append(v_seen, v_position);
  end loop;

  if jsonb_typeof(p_government_fees) = 'object' then
    if not (p_government_fees ?& v_government_keys)
       or exists (select 1 from jsonb_object_keys(p_government_fees) as keys(key)
                  where keys.key <> all(v_government_keys)) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    foreach v_key in array v_government_keys loop
      if jsonb_typeof(p_government_fees -> v_key) not in ('number', 'null') then
        raise exception using errcode = 'PQT05', message = 'invalid_payload';
      end if;
    end loop;
  end if;

  v_seen := array[]::integer[];
  for v_item in select value from jsonb_array_elements(p_administrative_fees) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    if not (v_item ?& v_administrative_keys)
       or exists (select 1 from jsonb_object_keys(v_item) as keys(key)
                  where keys.key <> all(v_administrative_keys))
       or jsonb_typeof(v_item -> 'ordinal') <> 'number'
       or jsonb_typeof(v_item -> 'title') <> 'string'
       or jsonb_typeof(v_item -> 'amount') <> 'number'
       or btrim(v_item ->> 'title') = '' then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    if (v_item ->> 'ordinal')::numeric <> trunc((v_item ->> 'ordinal')::numeric) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    v_position := (v_item ->> 'ordinal')::integer;
    if v_position < 0 or v_position = any(v_seen) then
      raise exception using errcode = 'PQT05', message = 'invalid_payload';
    end if;
    v_seen := array_append(v_seen, v_position);
  end loop;

  if p_expected_version is null then
    insert into public.quotations (
      id, owner_id, property_title, property_type, parking, subtitle,
      display_date, start_date_text, end_date_text, currency_code,
      professional_fee, total_amount, number_of_installments, payment_type,
      insurance_amount, insurance_returnable, office_name, custom_note,
      welcome_message_mode, custom_welcome_message
    ) values (
      p_quotation_id, v_user, v_header.property_title, v_header.property_type,
      v_header.parking, v_header.subtitle, v_header.display_date,
      v_header.start_date_text, v_header.end_date_text, v_header.currency_code,
      v_header.professional_fee, v_header.total_amount,
      v_header.number_of_installments, v_header.payment_type,
      v_header.insurance_amount, v_header.insurance_returnable,
      v_header.office_name, v_header.custom_note,
      v_header.welcome_message_mode, v_header.custom_welcome_message
    ) on conflict (id) do nothing returning * into v_quote;

    if not found then
      select q.* into v_quote from public.quotations q
      where q.id = p_quotation_id and q.owner_id = v_user for update;
      if not found then
        raise exception using errcode = 'PQT02', message = 'quotation_not_found';
      end if;
      if v_quote.deleted_at is not null then
        raise exception using errcode = 'PQT03', message = 'quotation_deleted';
      end if;
      if v_quote.version <> 1
         or (to_jsonb(v_quote) - array[
               'id','owner_id','office_logo_media_id','pdf_media_id',
               'created_at','updated_at','version','deleted_at'
             ]) <> to_jsonb(v_header) then
        raise exception using errcode = 'PQT06', message = 'quotation_id_conflict';
      end if;

      select coalesce(jsonb_agg(jsonb_build_object(
        'sequence_number', d.sequence_number, 'method', d.method,
        'due_at', d.due_at, 'amount', d.amount) order by d.sequence_number), '[]'::jsonb)
      into v_stored from public.quotation_downpayments d where d.quotation_id = p_quotation_id;
      select coalesce(jsonb_agg(jsonb_build_object(
        'sequence_number', d.sequence_number, 'method', d.method,
        'due_at', d.due_at, 'amount', d.amount) order by d.sequence_number), '[]'::jsonb)
      into v_submitted from jsonb_to_recordset(p_downpayments) as d(
        sequence_number integer, method public.payment_method,
        due_at timestamptz, amount numeric(14,2));
      if v_stored <> v_submitted then
        raise exception using errcode = 'PQT06', message = 'quotation_id_conflict';
      end if;

      select to_jsonb(g) - 'quotation_id' into v_stored
      from public.quotation_government_fees g where g.quotation_id = p_quotation_id;
      v_submitted := null;
      if jsonb_typeof(p_government_fees) = 'object' then
        select to_jsonb(g) into v_submitted from jsonb_to_record(p_government_fees) as g(
          percent_of_total_rent numeric(7,4), municipality numeric(14,2),
          electricity numeric(14,2), sewerage numeric(14,2), total numeric(14,2));
      end if;
      if v_stored is distinct from v_submitted then
        raise exception using errcode = 'PQT06', message = 'quotation_id_conflict';
      end if;

      select coalesce(jsonb_agg(jsonb_build_object(
        'ordinal', a.ordinal, 'title', a.title, 'amount', a.amount)
        order by a.ordinal), '[]'::jsonb)
      into v_stored from public.quotation_administrative_fees a where a.quotation_id = p_quotation_id;
      select coalesce(jsonb_agg(jsonb_build_object(
        'ordinal', a.ordinal, 'title', a.title, 'amount', a.amount)
        order by a.ordinal), '[]'::jsonb)
      into v_submitted from jsonb_to_recordset(p_administrative_fees) as a(
        ordinal integer, title text, amount numeric(14,2));
      if v_stored <> v_submitted then
        raise exception using errcode = 'PQT06', message = 'quotation_id_conflict';
      end if;

      return query select v_quote.id, v_quote.version, 'replayed'::text,
                          v_quote.created_at, v_quote.updated_at;
      return;
    end if;
    v_action := 'created';
  else
    -- FOR UPDATE serializes competing edits. Recheck after the lock is held.
    select q.* into v_quote from public.quotations q
    where q.id = p_quotation_id and q.owner_id = v_user for update;
    if not found then
      raise exception using errcode = 'PQT02', message = 'quotation_not_found';
    end if;
    if v_quote.deleted_at is not null then
      raise exception using errcode = 'PQT03', message = 'quotation_deleted';
    end if;
    if v_quote.version <> p_expected_version then
      raise exception using errcode = 'PQT04', message = 'version_conflict';
    end if;
    update public.quotations q set
      property_title = v_header.property_title,
      property_type = v_header.property_type,
      parking = v_header.parking,
      subtitle = v_header.subtitle,
      display_date = v_header.display_date,
      start_date_text = v_header.start_date_text,
      end_date_text = v_header.end_date_text,
      currency_code = v_header.currency_code,
      professional_fee = v_header.professional_fee,
      total_amount = v_header.total_amount,
      number_of_installments = v_header.number_of_installments,
      payment_type = v_header.payment_type,
      insurance_amount = v_header.insurance_amount,
      insurance_returnable = v_header.insurance_returnable,
      office_name = v_header.office_name,
      custom_note = v_header.custom_note,
      welcome_message_mode = v_header.welcome_message_mode,
      custom_welcome_message = v_header.custom_welcome_message
    where q.id = p_quotation_id and q.owner_id = v_user
      and q.version = p_expected_version and q.deleted_at is null
    returning * into v_quote;
    if not found then
      raise exception using errcode = 'PQT04', message = 'version_conflict';
    end if;
    v_action := 'updated';
  end if;

  -- DELETE + INSERT is safe here because every exception aborts this entire
  -- function call. The parent row lock serializes saves for this quotation.
  delete from public.quotation_downpayments d where d.quotation_id = p_quotation_id;
  insert into public.quotation_downpayments (quotation_id, sequence_number, method, due_at, amount)
  select p_quotation_id, d.sequence_number, d.method, d.due_at, d.amount
  from jsonb_to_recordset(p_downpayments) as d(
    sequence_number integer, method public.payment_method,
    due_at timestamptz, amount numeric(14,2)) order by d.sequence_number;

  delete from public.quotation_government_fees g where g.quotation_id = p_quotation_id;
  if jsonb_typeof(p_government_fees) = 'object' then
    insert into public.quotation_government_fees (
      quotation_id, percent_of_total_rent, municipality, electricity, sewerage, total)
    select p_quotation_id, g.percent_of_total_rent, g.municipality,
           g.electricity, g.sewerage, g.total
    from jsonb_to_record(p_government_fees) as g(
      percent_of_total_rent numeric(7,4), municipality numeric(14,2),
      electricity numeric(14,2), sewerage numeric(14,2), total numeric(14,2));
  end if;

  delete from public.quotation_administrative_fees a where a.quotation_id = p_quotation_id;
  insert into public.quotation_administrative_fees (quotation_id, ordinal, title, amount)
  select p_quotation_id, a.ordinal, a.title, a.amount
  from jsonb_to_recordset(p_administrative_fees) as a(
    ordinal integer, title text, amount numeric(14,2)) order by a.ordinal;

  return query select v_quote.id, v_quote.version, v_action,
                      v_quote.created_at, v_quote.updated_at;
exception when data_exception then
  -- Invalid JSON scalar casts (including malformed timestamptz or overflow)
  -- are payload errors. Rethrowing aborts the complete function call.
  raise exception using errcode = 'PQT05', message = 'invalid_payload';
end;
$function$;

revoke execute on function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  from public, anon;
grant execute on function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb)
  to authenticated;

comment on function public.save_quotation(uuid, bigint, jsonb, jsonb, jsonb, jsonb) is
  'Atomic owner-only non-media Quotation create/update. Null expected_version creates or replays an identical version-1 aggregate; nonnull expected_version performs one locked optimistic update. Errors PQT01 unauthenticated, PQT02 not found/foreign, PQT03 deleted, PQT04 stale version, PQT05 invalid payload, PQT06 UUID conflict.';

-- A table-level REVOKE also removes corresponding column-level privileges in
-- PostgreSQL. This clears the header's baseline column INSERT/UPDATE grants;
-- only deleted_at is granted back. Reads and service_role grants remain.
revoke insert, update, delete on public.quotations from public, anon, authenticated;
grant update (deleted_at) on public.quotations to authenticated;

revoke insert, update, delete on
  public.quotation_downpayments,
  public.quotation_government_fees,
  public.quotation_administrative_fees
from public, anon, authenticated;

-- The established direct deleted_at update remains usable only to tombstone
-- a live owned row. This restrictive policy composes with quotations_update_own
-- and prevents a client from clearing a tombstone through that column grant.
create policy quotations_direct_soft_delete_only
on public.quotations as restrictive for update to authenticated
using (owner_id = auth.uid() and deleted_at is null)
with check (owner_id = auth.uid() and deleted_at is not null);
