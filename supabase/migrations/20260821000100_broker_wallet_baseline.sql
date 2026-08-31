-- Broker Wallet Stage 1 baseline schema
-- Target: Supabase/PostgreSQL 17
-- This migration intentionally does NOT migrate Firebase test data, configure R2,
-- configure RevenueCat webhooks, or change the Flutter application.

begin;

create extension if not exists citext with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.listing_transaction_type as enum ('rent', 'sell');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.property_status as enum (
    'available', 'active', 'sold', 'rented', 'canceled',
    'not_available', 'fulfilled', 'closed', 'expired'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.feedback_status as enum ('unread', 'read', 'resolved');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_category as enum ('match', 'reminder', 'plan', 'system');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.media_type as enum ('image', 'video', 'pdf', 'unknown');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.media_status as enum (
    'pending_upload', 'uploaded', 'ready', 'failed', 'pending_delete', 'deleted'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_method as enum ('cash', 'cheque', 'bank_transfer', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.welcome_message_mode as enum ('auto', 'custom', 'hidden');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.quota_section as enum (
    'offers', 'requests', 'owners', 'offices', 'brokers', 'watchmen',
    'quotations', 'scanner', 'signature', 'image_to_pdf', 'combine_pdfs'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.quota_counter_basis as enum ('current', 'lifetime_created', 'period');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.quota_reset_period as enum ('lifetime', 'daily', 'weekly', 'monthly', 'yearly');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Common trigger functions
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.bump_sync_version()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles / identity projection
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email extensions.citext,
  phone_number text,
  phone_e164 text,
  profile_media_id uuid,
  is_email_verified boolean not null default false,
  is_phone_verified boolean not null default false,
  preferences jsonb not null default '{}'::jsonb,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint profiles_preferences_object check (jsonb_typeof(preferences) = 'object'),
  constraint profiles_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$')
);

create unique index profiles_email_unique on public.profiles (email) where email is not null;
create unique index profiles_phone_e164_unique on public.profiles (phone_e164) where phone_e164 is not null;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  insert into public.profiles (
    id,
    name,
    email,
    phone_number,
    phone_e164,
    is_email_verified,
    is_phone_verified,
    created_at,
    updated_at
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    nullif(new.email, '')::extensions.citext,
    nullif(new.phone, ''),
    case when coalesce(new.phone, '') ~ '^\\+[1-9][0-9]{6,14}$' then new.phone else null end,
    new.email_confirmed_at is not null,
    new.phone_confirmed_at is not null,
    coalesce(new.created_at, now()),
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

create trigger profiles_bump_sync_version
  before update on public.profiles
  for each row execute function public.bump_sync_version();

-- ---------------------------------------------------------------------------
-- RevenueCat projection and quota bookkeeping
-- No production quota limits are seeded in Stage 1 because product limits and
-- RevenueCat product/entitlement mapping are product-owner decisions.
-- ---------------------------------------------------------------------------

create table public.revenuecat_entitlements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  entitlement_id text not null,
  product_id text,
  plan_code text,
  is_active boolean not null default false,
  purchased_at timestamptz,
  expires_at timestamptz,
  environment text not null default 'unknown',
  updated_at timestamptz not null default now(),
  primary key (user_id, entitlement_id),
  constraint revenuecat_entitlement_id_nonempty check (btrim(entitlement_id) <> ''),
  constraint revenuecat_plan_code_nonempty check (plan_code is null or btrim(plan_code) <> ''),
  constraint revenuecat_environment_valid check (environment in ('sandbox', 'production', 'unknown'))
);

create table public.plan_limits (
  plan_code text not null,
  section public.quota_section not null,
  counter_basis public.quota_counter_basis not null,
  limit_value integer,
  reset_period public.quota_reset_period not null default 'lifetime',
  updated_at timestamptz not null default now(),
  primary key (plan_code, section),
  constraint plan_limits_plan_code_nonempty check (btrim(plan_code) <> ''),
  constraint plan_limits_nonnegative check (limit_value is null or limit_value >= 0)
);

create table public.usage_counters (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  section public.quota_section not null,
  current_item_count bigint not null default 0,
  lifetime_created_count bigint not null default 0,
  period_item_count bigint not null default 0,
  period_started_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (owner_id, section),
  constraint usage_current_nonnegative check (current_item_count >= 0),
  constraint usage_lifetime_nonnegative check (lifetime_created_count >= 0),
  constraint usage_period_nonnegative check (period_item_count >= 0)
);

create table public.revenuecat_webhook_events (
  event_id text primary key,
  event_type text not null,
  app_user_id text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_status text not null default 'pending',
  payload jsonb not null,
  constraint revenuecat_event_id_nonempty check (btrim(event_id) <> ''),
  constraint revenuecat_event_type_nonempty check (btrim(event_type) <> ''),
  constraint revenuecat_processing_status_valid check (processing_status in ('pending', 'processed', 'failed', 'ignored')),
  constraint revenuecat_payload_object check (jsonb_typeof(payload) = 'object')
);

create trigger revenuecat_entitlements_updated_at
  before update on public.revenuecat_entitlements
  for each row execute function public.set_updated_at();
create trigger plan_limits_updated_at
  before update on public.plan_limits
  for each row execute function public.set_updated_at();
create trigger usage_counters_updated_at
  before update on public.usage_counters
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Core domain tables
-- ---------------------------------------------------------------------------

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  request_type public.listing_transaction_type not null,
  selected_city text not null default '',
  location_text text not null default '',
  phone_number text not null default '',
  country_code text not null default '+971',
  phone_e164 text,
  min_price numeric(14,2),
  max_price numeric(14,2),
  square_footage numeric(14,2),
  notes text not null default '',
  property_type text,
  specific_property_type text not null default '',
  rooms integer not null default 0,
  bathrooms integer not null default 0,
  status public.property_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint requests_min_price_nonnegative check (min_price is null or min_price >= 0),
  constraint requests_max_price_nonnegative check (max_price is null or max_price >= 0),
  constraint requests_price_range check (min_price is null or max_price is null or min_price <= max_price),
  constraint requests_square_footage_nonnegative check (square_footage is null or square_footage >= 0),
  constraint requests_rooms_nonnegative check (rooms >= 0),
  constraint requests_bathrooms_nonnegative check (bathrooms >= 0),
  constraint requests_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'),
  constraint requests_status_workflow check (status in ('active', 'fulfilled', 'closed', 'expired'))
);

create table public.request_areas (
  request_id uuid not null references public.requests(id) on delete cascade,
  ordinal integer not null default 0,
  area text not null,
  primary key (request_id, area),
  unique (request_id, ordinal),
  constraint request_areas_ordinal_nonnegative check (ordinal >= 0),
  constraint request_areas_nonempty check (btrim(area) <> '')
);

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  offer_type public.listing_transaction_type not null,
  selected_city text not null default '',
  location_text text not null default '',
  phone_number text not null default '',
  country_code text not null default '+971',
  phone_e164 text,
  min_price numeric(14,2),
  max_price numeric(14,2),
  square_footage numeric(14,2),
  notes text not null default '',
  property_type text,
  specific_property_type text not null default '',
  rooms integer not null default 0,
  bathrooms integer not null default 0,
  pickup_location_text text not null default '',
  pickup_latitude double precision,
  pickup_longitude double precision,
  pickup_address text not null default '',
  legacy_uploaded_file_name text,
  status public.property_status not null default 'available',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint offers_min_price_nonnegative check (min_price is null or min_price >= 0),
  constraint offers_max_price_nonnegative check (max_price is null or max_price >= 0),
  constraint offers_price_range check (min_price is null or max_price is null or min_price <= max_price),
  constraint offers_square_footage_nonnegative check (square_footage is null or square_footage >= 0),
  constraint offers_rooms_nonnegative check (rooms >= 0),
  constraint offers_bathrooms_nonnegative check (bathrooms >= 0),
  constraint offers_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'),
  constraint offers_latitude_range check (pickup_latitude is null or pickup_latitude between -90 and 90),
  constraint offers_longitude_range check (pickup_longitude is null or pickup_longitude between -180 and 180),
  constraint offers_coordinates_pair check ((pickup_latitude is null) = (pickup_longitude is null)),
  constraint offers_status_workflow check (status in ('available', 'sold', 'rented', 'canceled', 'not_available'))
);

create table public.offer_areas (
  offer_id uuid not null references public.offers(id) on delete cascade,
  ordinal integer not null default 0,
  area text not null,
  primary key (offer_id, area),
  unique (offer_id, ordinal),
  constraint offer_areas_ordinal_nonnegative check (ordinal >= 0),
  constraint offer_areas_nonempty check (btrim(area) <> '')
);

create table public.owners (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  phone_number text not null default '',
  country_code text not null default '+971',
  phone_e164 text,
  property_type_text text not null default '',
  property_location text not null default '',
  notes text not null default '',
  pickup_location_text text not null default '',
  pickup_latitude double precision,
  pickup_longitude double precision,
  pickup_address text not null default '',
  legacy_uploaded_file_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint owners_name_nonempty check (btrim(name) <> ''),
  constraint owners_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'),
  constraint owners_latitude_range check (pickup_latitude is null or pickup_latitude between -90 and 90),
  constraint owners_longitude_range check (pickup_longitude is null or pickup_longitude between -180 and 180),
  constraint owners_coordinates_pair check ((pickup_latitude is null) = (pickup_longitude is null))
);

create table public.offices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  office_name text not null,
  manager_name text not null default '',
  country_code text not null default '+971',
  phone_number text not null default '',
  phone_e164 text,
  office_location text not null default '',
  notes text not null default '',
  pickup_location_text text not null default '',
  pickup_latitude double precision,
  pickup_longitude double precision,
  pickup_address text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint offices_name_nonempty check (btrim(office_name) <> ''),
  constraint offices_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'),
  constraint offices_latitude_range check (pickup_latitude is null or pickup_latitude between -90 and 90),
  constraint offices_longitude_range check (pickup_longitude is null or pickup_longitude between -180 and 180),
  constraint offices_coordinates_pair check ((pickup_latitude is null) = (pickup_longitude is null))
);

create table public.brokers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  country_code text not null default '+971',
  phone_number text not null default '',
  phone_e164 text,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint brokers_name_nonempty check (btrim(name) <> ''),
  constraint brokers_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$')
);

create table public.watchmen (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  country_code text not null default '+971',
  phone_number text not null default '',
  phone_e164 text,
  building_name text not null default '',
  notes text not null default '',
  building_location text not null default '',
  pickup_location_text text not null default '',
  pickup_latitude double precision,
  pickup_longitude double precision,
  pickup_address text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint watchmen_name_nonempty check (btrim(name) <> ''),
  constraint watchmen_phone_e164_format check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'),
  constraint watchmen_latitude_range check (pickup_latitude is null or pickup_latitude between -90 and 90),
  constraint watchmen_longitude_range check (pickup_longitude is null or pickup_longitude between -180 and 180),
  constraint watchmen_coordinates_pair check ((pickup_latitude is null) = (pickup_longitude is null))
);

create trigger requests_bump_sync_version before update on public.requests for each row execute function public.bump_sync_version();
create trigger offers_bump_sync_version before update on public.offers for each row execute function public.bump_sync_version();
create trigger owners_bump_sync_version before update on public.owners for each row execute function public.bump_sync_version();
create trigger offices_bump_sync_version before update on public.offices for each row execute function public.bump_sync_version();
create trigger brokers_bump_sync_version before update on public.brokers for each row execute function public.bump_sync_version();
create trigger watchmen_bump_sync_version before update on public.watchmen for each row execute function public.bump_sync_version();

-- ---------------------------------------------------------------------------
-- Quotations
-- ---------------------------------------------------------------------------

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  property_title text not null,
  property_type text,
  parking boolean,
  subtitle text,
  display_date text,
  start_date_text text,
  end_date_text text,
  currency_code varchar(3) not null default 'AED',
  professional_fee numeric(14,2),
  total_amount numeric(14,2),
  number_of_installments integer,
  payment_type public.payment_method,
  insurance_amount numeric(14,2),
  insurance_returnable boolean,
  office_name text not null default '',
  office_logo_media_id uuid,
  custom_note text,
  welcome_message_mode public.welcome_message_mode not null default 'auto',
  custom_welcome_message text,
  pdf_media_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version >= 1),
  deleted_at timestamptz,
  constraint quotations_title_nonempty check (btrim(property_title) <> ''),
  constraint quotations_currency_uppercase check (currency_code = upper(currency_code)),
  constraint quotations_professional_fee_nonnegative check (professional_fee is null or professional_fee >= 0),
  constraint quotations_total_amount_nonnegative check (total_amount is null or total_amount >= 0),
  constraint quotations_installments_positive check (number_of_installments is null or number_of_installments > 0),
  constraint quotations_insurance_nonnegative check (insurance_amount is null or insurance_amount >= 0),
  constraint quotations_custom_welcome_mode check (
    welcome_message_mode <> 'custom' or nullif(btrim(custom_welcome_message), '') is not null
  )
);

create table public.quotation_downpayments (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  method public.payment_method not null,
  sequence_number integer not null,
  due_at timestamptz,
  amount numeric(14,2) not null,
  unique (quotation_id, sequence_number),
  constraint quotation_downpayments_sequence_positive check (sequence_number > 0),
  constraint quotation_downpayments_amount_nonnegative check (amount >= 0)
);

create table public.quotation_government_fees (
  quotation_id uuid primary key references public.quotations(id) on delete cascade,
  percent_of_total_rent numeric(7,4),
  municipality numeric(14,2),
  electricity numeric(14,2),
  sewerage numeric(14,2),
  total numeric(14,2),
  constraint quotation_gov_percent_range check (percent_of_total_rent is null or percent_of_total_rent between 0 and 100),
  constraint quotation_gov_municipality_nonnegative check (municipality is null or municipality >= 0),
  constraint quotation_gov_electricity_nonnegative check (electricity is null or electricity >= 0),
  constraint quotation_gov_sewerage_nonnegative check (sewerage is null or sewerage >= 0),
  constraint quotation_gov_total_nonnegative check (total is null or total >= 0)
);

create table public.quotation_administrative_fees (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  ordinal integer not null default 0,
  title text not null,
  amount numeric(14,2) not null,
  unique (quotation_id, ordinal),
  constraint quotation_admin_ordinal_nonnegative check (ordinal >= 0),
  constraint quotation_admin_title_nonempty check (btrim(title) <> ''),
  constraint quotation_admin_amount_nonnegative check (amount >= 0)
);

create trigger quotations_bump_sync_version before update on public.quotations for each row execute function public.bump_sync_version();

-- ---------------------------------------------------------------------------
-- Media metadata for future private Cloudflare R2 storage
-- ---------------------------------------------------------------------------

create table public.media_objects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  bucket text not null,
  object_key text not null,
  media_type public.media_type not null default 'unknown',
  format text,
  content_type text,
  size_bytes bigint,
  width integer,
  height integer,
  duration_ms bigint,
  thumbnail_media_id uuid references public.media_objects(id) on delete set null,
  original_file_name text,
  status public.media_status not null default 'pending_upload',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (bucket, object_key),
  constraint media_bucket_nonempty check (btrim(bucket) <> ''),
  constraint media_object_key_nonempty check (btrim(object_key) <> ''),
  constraint media_size_nonnegative check (size_bytes is null or size_bytes >= 0),
  constraint media_width_positive check (width is null or width > 0),
  constraint media_height_positive check (height is null or height > 0),
  constraint media_duration_nonnegative check (duration_ms is null or duration_ms >= 0)
);

alter table public.profiles
  add constraint profiles_profile_media_fk
  foreign key (profile_media_id) references public.media_objects(id) on delete set null;

alter table public.quotations
  add constraint quotations_office_logo_media_fk
  foreign key (office_logo_media_id) references public.media_objects(id) on delete set null,
  add constraint quotations_pdf_media_fk
  foreign key (pdf_media_id) references public.media_objects(id) on delete set null;

create table public.offer_media (
  offer_id uuid not null references public.offers(id) on delete cascade,
  media_id uuid not null references public.media_objects(id) on delete cascade,
  role text not null default 'gallery',
  ordinal integer not null default 0,
  primary key (offer_id, media_id),
  unique (offer_id, role, ordinal),
  constraint offer_media_role_nonempty check (btrim(role) <> ''),
  constraint offer_media_ordinal_nonnegative check (ordinal >= 0)
);

create table public.owner_media (
  owner_record_id uuid not null references public.owners(id) on delete cascade,
  media_id uuid not null references public.media_objects(id) on delete cascade,
  role text not null default 'gallery',
  ordinal integer not null default 0,
  primary key (owner_record_id, media_id),
  unique (owner_record_id, role, ordinal),
  constraint owner_media_role_nonempty check (btrim(role) <> ''),
  constraint owner_media_ordinal_nonnegative check (ordinal >= 0)
);

create table public.quotation_media (
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  media_id uuid not null references public.media_objects(id) on delete cascade,
  role text not null,
  ordinal integer not null default 0,
  primary key (quotation_id, media_id),
  unique (quotation_id, role, ordinal),
  constraint quotation_media_role_valid check (role in ('logo', 'pdf', 'attachment', 'thumbnail')),
  constraint quotation_media_ordinal_nonnegative check (ordinal >= 0)
);

create table public.profile_media (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  media_id uuid not null references public.media_objects(id) on delete cascade,
  role text not null default 'avatar',
  ordinal integer not null default 0,
  primary key (profile_id, media_id),
  unique (profile_id, role, ordinal),
  constraint profile_media_role_valid check (role in ('avatar', 'thumbnail')),
  constraint profile_media_ordinal_nonnegative check (ordinal >= 0)
);

create or replace function public.validate_media_attachment_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_owner uuid;
  media_owner uuid;
begin
  select owner_id into media_owner from public.media_objects where id = new.media_id;

  if tg_table_name = 'offer_media' then
    select owner_id into parent_owner from public.offers where id = new.offer_id;
  elsif tg_table_name = 'owner_media' then
    select owner_id into parent_owner from public.owners where id = new.owner_record_id;
  elsif tg_table_name = 'quotation_media' then
    select owner_id into parent_owner from public.quotations where id = new.quotation_id;
  elsif tg_table_name = 'profile_media' then
    parent_owner := new.profile_id;
  else
    raise exception 'Unsupported media attachment table: %', tg_table_name;
  end if;

  if parent_owner is null or media_owner is null or parent_owner <> media_owner then
    raise exception 'Media owner must match attached entity owner';
  end if;

  return new;
end;
$$;

create trigger offer_media_validate_owner before insert or update on public.offer_media for each row execute function public.validate_media_attachment_ownership();
create trigger owner_media_validate_owner before insert or update on public.owner_media for each row execute function public.validate_media_attachment_ownership();
create trigger quotation_media_validate_owner before insert or update on public.quotation_media for each row execute function public.validate_media_attachment_ownership();
create trigger profile_media_validate_owner before insert or update on public.profile_media for each row execute function public.validate_media_attachment_ownership();

create or replace function public.validate_direct_media_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  expected_owner uuid;
begin
  if tg_table_name = 'profiles' then
    expected_owner := new.id;
    if new.profile_media_id is not null and not exists (
      select 1 from public.media_objects m where m.id = new.profile_media_id and m.owner_id = expected_owner
    ) then
      raise exception 'Profile media must belong to the profile owner';
    end if;
  elsif tg_table_name = 'quotations' then
    expected_owner := new.owner_id;
    if new.office_logo_media_id is not null and not exists (
      select 1 from public.media_objects m where m.id = new.office_logo_media_id and m.owner_id = expected_owner
    ) then
      raise exception 'Quotation logo media must belong to the quotation owner';
    end if;
    if new.pdf_media_id is not null and not exists (
      select 1 from public.media_objects m where m.id = new.pdf_media_id and m.owner_id = expected_owner
    ) then
      raise exception 'Quotation PDF media must belong to the quotation owner';
    end if;
  elsif tg_table_name = 'media_objects' then
    expected_owner := new.owner_id;
    if new.thumbnail_media_id is not null and not exists (
      select 1 from public.media_objects m where m.id = new.thumbnail_media_id and m.owner_id = expected_owner
    ) then
      raise exception 'Thumbnail media must belong to the same owner';
    end if;
  else
    raise exception 'Unsupported direct media owner validation table: %', tg_table_name;
  end if;

  return new;
end;
$$;

create trigger profiles_validate_direct_media before insert or update of profile_media_id on public.profiles for each row execute function public.validate_direct_media_ownership();
create trigger quotations_validate_direct_media before insert or update of office_logo_media_id, pdf_media_id on public.quotations for each row execute function public.validate_direct_media_ownership();
create trigger media_objects_validate_thumbnail before insert or update of thumbnail_media_id on public.media_objects for each row execute function public.validate_direct_media_ownership();
create trigger media_objects_updated_at before update on public.media_objects for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Favorites (six concrete tables for real FK integrity)
-- ---------------------------------------------------------------------------

create table public.favorite_offers (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.offers(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create table public.favorite_requests (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.requests(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create table public.favorite_owners (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.owners(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create table public.favorite_offices (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.offices(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create table public.favorite_brokers (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.brokers(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create table public.favorite_watchmen (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.watchmen(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_id, target_id)
);

create or replace view public.favorites_unified
with (security_invoker = true)
as
  select owner_id, 'offer'::text as entity_type, target_id as entity_id, added_at from public.favorite_offers
  union all
  select owner_id, 'request', target_id, added_at from public.favorite_requests
  union all
  select owner_id, 'owner', target_id, added_at from public.favorite_owners
  union all
  select owner_id, 'office', target_id, added_at from public.favorite_offices
  union all
  select owner_id, 'broker', target_id, added_at from public.favorite_brokers
  union all
  select owner_id, 'watchman', target_id, added_at from public.favorite_watchmen;

-- ---------------------------------------------------------------------------
-- Feedback, notifications and push registrations
-- ---------------------------------------------------------------------------

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  user_name_snapshot text not null default '',
  user_email_snapshot extensions.citext,
  rating integer not null,
  comment text not null default '',
  app_version text not null default '',
  platform text not null default '',
  device_info text,
  status public.feedback_status not null default 'unread',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feedback_rating_range check (rating between 1 and 5)
);

create or replace function public.prepare_feedback_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select p.name, p.email
    into new.user_name_snapshot, new.user_email_snapshot
  from public.profiles p
  where p.id = new.owner_id;

  new.status := 'unread';
  return new;
end;
$$;

create trigger feedback_prepare_insert before insert on public.feedback for each row execute function public.prepare_feedback_insert();
create trigger feedback_updated_at before update on public.feedback for each row execute function public.set_updated_at();

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  category public.notification_category not null,
  is_read boolean not null default false,
  read_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  action_route text,
  offer_id uuid references public.offers(id) on delete set null,
  request_id uuid references public.requests(id) on delete set null,
  match_score numeric(7,4),
  sender_user_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint notifications_title_nonempty check (btrim(title) <> ''),
  constraint notifications_body_nonempty check (btrim(body) <> ''),
  constraint notifications_data_object check (jsonb_typeof(data) = 'object'),
  constraint notifications_match_score_nonnegative check (match_score is null or match_score >= 0)
);

create or replace function public.normalize_notification_read_state()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.is_read then
    if old.is_read is distinct from true then
      new.read_at := now();
    elsif new.read_at is null then
      new.read_at := coalesce(old.read_at, now());
    end if;
  else
    new.read_at := null;
  end if;
  return new;
end;
$$;

create trigger notifications_normalize_read_state
  before update of is_read on public.notifications
  for each row execute function public.normalize_notification_read_state();

create table public.push_devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null default 'fcm',
  token_value text not null,
  token_hash text not null,
  platform text not null,
  device_name text,
  locale text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, token_hash),
  constraint push_devices_provider_valid check (provider in ('fcm', 'apns', 'other')),
  constraint push_devices_token_nonempty check (btrim(token_value) <> ''),
  constraint push_devices_hash_nonempty check (btrim(token_hash) <> ''),
  constraint push_devices_platform_nonempty check (btrim(platform) <> '')
);

create trigger push_devices_updated_at before update on public.push_devices for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Operational/configuration tables
-- ---------------------------------------------------------------------------

create table public.app_versions (
  platform text primary key,
  latest_version text not null,
  minimum_version text,
  update_url text,
  release_notes text,
  updated_at timestamptz not null default now(),
  constraint app_versions_platform_valid check (platform in ('android', 'ios')),
  constraint app_versions_latest_nonempty check (btrim(latest_version) <> '')
);

create table public.idempotency_keys (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  key text not null,
  operation text not null,
  response jsonb,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (owner_id, key),
  constraint idempotency_key_nonempty check (btrim(key) <> ''),
  constraint idempotency_operation_nonempty check (btrim(operation) <> '')
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint audit_action_nonempty check (btrim(action) <> ''),
  constraint audit_details_object check (jsonb_typeof(details) = 'object')
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index requests_owner_created_idx on public.requests (owner_id, created_at desc);
create index requests_owner_updated_idx on public.requests (owner_id, updated_at desc);
create index requests_owner_status_created_idx on public.requests (owner_id, status, created_at desc);
create index requests_owner_type_created_idx on public.requests (owner_id, request_type, created_at desc);
create index requests_owner_city_idx on public.requests (owner_id, selected_city);
create index requests_owner_phone_idx on public.requests (owner_id, phone_e164) where phone_e164 is not null;
create index requests_price_idx on public.requests (owner_id, min_price, max_price);
create index request_areas_area_idx on public.request_areas (area, request_id);

create index offers_owner_created_idx on public.offers (owner_id, created_at desc);
create index offers_owner_updated_idx on public.offers (owner_id, updated_at desc);
create index offers_owner_status_created_idx on public.offers (owner_id, status, created_at desc);
create index offers_owner_type_created_idx on public.offers (owner_id, offer_type, created_at desc);
create index offers_owner_city_idx on public.offers (owner_id, selected_city);
create index offers_owner_phone_idx on public.offers (owner_id, phone_e164) where phone_e164 is not null;
create index offers_price_idx on public.offers (owner_id, min_price, max_price);
create index offer_areas_area_idx on public.offer_areas (area, offer_id);

create index owners_owner_created_idx on public.owners (owner_id, created_at desc);
create index owners_owner_updated_idx on public.owners (owner_id, updated_at desc);
create index owners_name_idx on public.owners (owner_id, lower(name));
create index owners_phone_idx on public.owners (owner_id, phone_e164) where phone_e164 is not null;

create index offices_owner_created_idx on public.offices (owner_id, created_at desc);
create index offices_owner_updated_idx on public.offices (owner_id, updated_at desc);
create index offices_name_idx on public.offices (owner_id, lower(office_name));
create index offices_phone_idx on public.offices (owner_id, phone_e164) where phone_e164 is not null;

create index brokers_owner_created_idx on public.brokers (owner_id, created_at desc);
create index brokers_owner_updated_idx on public.brokers (owner_id, updated_at desc);
create index brokers_name_idx on public.brokers (owner_id, lower(name));
create index brokers_phone_idx on public.brokers (owner_id, phone_e164) where phone_e164 is not null;

create index watchmen_owner_created_idx on public.watchmen (owner_id, created_at desc);
create index watchmen_owner_updated_idx on public.watchmen (owner_id, updated_at desc);
create index watchmen_name_idx on public.watchmen (owner_id, lower(name));
create index watchmen_phone_idx on public.watchmen (owner_id, phone_e164) where phone_e164 is not null;

create index quotations_owner_created_idx on public.quotations (owner_id, created_at desc);
create index quotations_owner_updated_idx on public.quotations (owner_id, updated_at desc);
create index quotations_title_trgm_idx on public.quotations using gin (property_title extensions.gin_trgm_ops);

create index favorite_offers_target_idx on public.favorite_offers (target_id);
create index favorite_requests_target_idx on public.favorite_requests (target_id);
create index favorite_owners_target_idx on public.favorite_owners (target_id);
create index favorite_offices_target_idx on public.favorite_offices (target_id);
create index favorite_brokers_target_idx on public.favorite_brokers (target_id);
create index favorite_watchmen_target_idx on public.favorite_watchmen (target_id);

create index media_owner_created_idx on public.media_objects (owner_id, created_at desc);
create index media_status_idx on public.media_objects (status, updated_at);
create index media_thumbnail_idx on public.media_objects (thumbnail_media_id) where thumbnail_media_id is not null;

create index feedback_status_created_idx on public.feedback (status, created_at desc);
create index notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc);
create index notifications_unread_idx on public.notifications (recipient_id, created_at desc) where is_read = false;
create index notifications_offer_idx on public.notifications (offer_id) where offer_id is not null;
create index notifications_request_idx on public.notifications (request_id) where request_id is not null;
create index push_devices_owner_idx on public.push_devices (owner_id);

create index revenuecat_entitlements_active_idx on public.revenuecat_entitlements (user_id, is_active, expires_at);
create index revenuecat_entitlements_expiry_idx on public.revenuecat_entitlements (expires_at) where is_active = true;
create index revenuecat_webhook_status_idx on public.revenuecat_webhook_events (processing_status, received_at);
create index idempotency_expires_idx on public.idempotency_keys (expires_at) where expires_at is not null;
create index audit_logs_target_created_idx on public.audit_logs (target_user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS helper functions
-- ---------------------------------------------------------------------------

create or replace function public.owns_request(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.requests r where r.id = row_id and r.owner_id = auth.uid());
$$;

create or replace function public.owns_offer(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.offers o where o.id = row_id and o.owner_id = auth.uid());
$$;

create or replace function public.owns_owner_record(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.owners o where o.id = row_id and o.owner_id = auth.uid());
$$;

create or replace function public.owns_office(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.offices o where o.id = row_id and o.owner_id = auth.uid());
$$;

create or replace function public.owns_broker(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.brokers b where b.id = row_id and b.owner_id = auth.uid());
$$;

create or replace function public.owns_watchman(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.watchmen w where w.id = row_id and w.owner_id = auth.uid());
$$;

create or replace function public.owns_quotation(row_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.quotations q where q.id = row_id and q.owner_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS on every application table
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.revenuecat_entitlements enable row level security;
alter table public.plan_limits enable row level security;
alter table public.usage_counters enable row level security;
alter table public.revenuecat_webhook_events enable row level security;
alter table public.requests enable row level security;
alter table public.request_areas enable row level security;
alter table public.offers enable row level security;
alter table public.offer_areas enable row level security;
alter table public.owners enable row level security;
alter table public.offices enable row level security;
alter table public.brokers enable row level security;
alter table public.watchmen enable row level security;
alter table public.quotations enable row level security;
alter table public.quotation_downpayments enable row level security;
alter table public.quotation_government_fees enable row level security;
alter table public.quotation_administrative_fees enable row level security;
alter table public.media_objects enable row level security;
alter table public.offer_media enable row level security;
alter table public.owner_media enable row level security;
alter table public.quotation_media enable row level security;
alter table public.profile_media enable row level security;
alter table public.favorite_offers enable row level security;
alter table public.favorite_requests enable row level security;
alter table public.favorite_owners enable row level security;
alter table public.favorite_offices enable row level security;
alter table public.favorite_brokers enable row level security;
alter table public.favorite_watchmen enable row level security;
alter table public.feedback enable row level security;
alter table public.notifications enable row level security;
alter table public.push_devices enable row level security;
alter table public.app_versions enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.audit_logs enable row level security;

-- Profiles: authenticated users can read their row and update only granted editable columns.
create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Server-owned subscription/quota projections.
create policy revenuecat_entitlements_select_own on public.revenuecat_entitlements for select to authenticated using (user_id = auth.uid());
create policy plan_limits_select_authenticated on public.plan_limits for select to authenticated using (true);
create policy usage_counters_select_own on public.usage_counters for select to authenticated using (owner_id = auth.uid());

-- Core owner tables: hard delete intentionally has no client policy/grant.
create policy requests_select_own on public.requests for select to authenticated using (owner_id = auth.uid());
create policy requests_insert_own on public.requests for insert to authenticated with check (owner_id = auth.uid());
create policy requests_update_own on public.requests for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy request_areas_select_own on public.request_areas for select to authenticated using (public.owns_request(request_id));
create policy request_areas_insert_own on public.request_areas for insert to authenticated with check (public.owns_request(request_id));
create policy request_areas_update_own on public.request_areas for update to authenticated using (public.owns_request(request_id)) with check (public.owns_request(request_id));
create policy request_areas_delete_own on public.request_areas for delete to authenticated using (public.owns_request(request_id));

create policy offers_select_own on public.offers for select to authenticated using (owner_id = auth.uid());
create policy offers_insert_own on public.offers for insert to authenticated with check (owner_id = auth.uid());
create policy offers_update_own on public.offers for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy offer_areas_select_own on public.offer_areas for select to authenticated using (public.owns_offer(offer_id));
create policy offer_areas_insert_own on public.offer_areas for insert to authenticated with check (public.owns_offer(offer_id));
create policy offer_areas_update_own on public.offer_areas for update to authenticated using (public.owns_offer(offer_id)) with check (public.owns_offer(offer_id));
create policy offer_areas_delete_own on public.offer_areas for delete to authenticated using (public.owns_offer(offer_id));

create policy owners_select_own on public.owners for select to authenticated using (owner_id = auth.uid());
create policy owners_insert_own on public.owners for insert to authenticated with check (owner_id = auth.uid());
create policy owners_update_own on public.owners for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy offices_select_own on public.offices for select to authenticated using (owner_id = auth.uid());
create policy offices_insert_own on public.offices for insert to authenticated with check (owner_id = auth.uid());
create policy offices_update_own on public.offices for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy brokers_select_own on public.brokers for select to authenticated using (owner_id = auth.uid());
create policy brokers_insert_own on public.brokers for insert to authenticated with check (owner_id = auth.uid());
create policy brokers_update_own on public.brokers for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy watchmen_select_own on public.watchmen for select to authenticated using (owner_id = auth.uid());
create policy watchmen_insert_own on public.watchmen for insert to authenticated with check (owner_id = auth.uid());
create policy watchmen_update_own on public.watchmen for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Quotations and owned children.
create policy quotations_select_own on public.quotations for select to authenticated using (owner_id = auth.uid());
create policy quotations_insert_own on public.quotations for insert to authenticated with check (owner_id = auth.uid());
create policy quotations_update_own on public.quotations for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy quotation_downpayments_select_own on public.quotation_downpayments for select to authenticated using (public.owns_quotation(quotation_id));
create policy quotation_downpayments_insert_own on public.quotation_downpayments for insert to authenticated with check (public.owns_quotation(quotation_id));
create policy quotation_downpayments_update_own on public.quotation_downpayments for update to authenticated using (public.owns_quotation(quotation_id)) with check (public.owns_quotation(quotation_id));
create policy quotation_downpayments_delete_own on public.quotation_downpayments for delete to authenticated using (public.owns_quotation(quotation_id));

create policy quotation_government_fees_select_own on public.quotation_government_fees for select to authenticated using (public.owns_quotation(quotation_id));
create policy quotation_government_fees_insert_own on public.quotation_government_fees for insert to authenticated with check (public.owns_quotation(quotation_id));
create policy quotation_government_fees_update_own on public.quotation_government_fees for update to authenticated using (public.owns_quotation(quotation_id)) with check (public.owns_quotation(quotation_id));
create policy quotation_government_fees_delete_own on public.quotation_government_fees for delete to authenticated using (public.owns_quotation(quotation_id));

create policy quotation_administrative_fees_select_own on public.quotation_administrative_fees for select to authenticated using (public.owns_quotation(quotation_id));
create policy quotation_administrative_fees_insert_own on public.quotation_administrative_fees for insert to authenticated with check (public.owns_quotation(quotation_id));
create policy quotation_administrative_fees_update_own on public.quotation_administrative_fees for update to authenticated using (public.owns_quotation(quotation_id)) with check (public.owns_quotation(quotation_id));
create policy quotation_administrative_fees_delete_own on public.quotation_administrative_fees for delete to authenticated using (public.owns_quotation(quotation_id));

-- Media: clients can only read their metadata/attachments. Writes are server-only.
create policy media_objects_select_own on public.media_objects for select to authenticated using (owner_id = auth.uid());
create policy offer_media_select_own on public.offer_media for select to authenticated using (public.owns_offer(offer_id));
create policy owner_media_select_own on public.owner_media for select to authenticated using (public.owns_owner_record(owner_record_id));
create policy quotation_media_select_own on public.quotation_media for select to authenticated using (public.owns_quotation(quotation_id));
create policy profile_media_select_own on public.profile_media for select to authenticated using (profile_id = auth.uid());

-- Favorites: only same-owner targets are allowed.
create policy favorite_offers_select_own on public.favorite_offers for select to authenticated using (owner_id = auth.uid() and public.owns_offer(target_id));
create policy favorite_offers_insert_own on public.favorite_offers for insert to authenticated with check (owner_id = auth.uid() and public.owns_offer(target_id));
create policy favorite_offers_delete_own on public.favorite_offers for delete to authenticated using (owner_id = auth.uid() and public.owns_offer(target_id));

create policy favorite_requests_select_own on public.favorite_requests for select to authenticated using (owner_id = auth.uid() and public.owns_request(target_id));
create policy favorite_requests_insert_own on public.favorite_requests for insert to authenticated with check (owner_id = auth.uid() and public.owns_request(target_id));
create policy favorite_requests_delete_own on public.favorite_requests for delete to authenticated using (owner_id = auth.uid() and public.owns_request(target_id));

create policy favorite_owners_select_own on public.favorite_owners for select to authenticated using (owner_id = auth.uid() and public.owns_owner_record(target_id));
create policy favorite_owners_insert_own on public.favorite_owners for insert to authenticated with check (owner_id = auth.uid() and public.owns_owner_record(target_id));
create policy favorite_owners_delete_own on public.favorite_owners for delete to authenticated using (owner_id = auth.uid() and public.owns_owner_record(target_id));

create policy favorite_offices_select_own on public.favorite_offices for select to authenticated using (owner_id = auth.uid() and public.owns_office(target_id));
create policy favorite_offices_insert_own on public.favorite_offices for insert to authenticated with check (owner_id = auth.uid() and public.owns_office(target_id));
create policy favorite_offices_delete_own on public.favorite_offices for delete to authenticated using (owner_id = auth.uid() and public.owns_office(target_id));

create policy favorite_brokers_select_own on public.favorite_brokers for select to authenticated using (owner_id = auth.uid() and public.owns_broker(target_id));
create policy favorite_brokers_insert_own on public.favorite_brokers for insert to authenticated with check (owner_id = auth.uid() and public.owns_broker(target_id));
create policy favorite_brokers_delete_own on public.favorite_brokers for delete to authenticated using (owner_id = auth.uid() and public.owns_broker(target_id));

create policy favorite_watchmen_select_own on public.favorite_watchmen for select to authenticated using (owner_id = auth.uid() and public.owns_watchman(target_id));
create policy favorite_watchmen_insert_own on public.favorite_watchmen for insert to authenticated with check (owner_id = auth.uid() and public.owns_watchman(target_id));
create policy favorite_watchmen_delete_own on public.favorite_watchmen for delete to authenticated using (owner_id = auth.uid() and public.owns_watchman(target_id));

-- Feedback: client creates and reads own rows; server controls status processing.
create policy feedback_select_own on public.feedback for select to authenticated using (owner_id = auth.uid());
create policy feedback_insert_own on public.feedback for insert to authenticated with check (owner_id = auth.uid());

-- Notifications: backend creates; recipient reads, marks read, and may delete.
create policy notifications_select_own on public.notifications for select to authenticated using (recipient_id = auth.uid());
create policy notifications_update_own on public.notifications for update to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
create policy notifications_delete_own on public.notifications for delete to authenticated using (recipient_id = auth.uid());

-- App version rows are safe authenticated reference data.
create policy app_versions_select_authenticated on public.app_versions for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Grants: RLS is only half of the boundary. Column-level grants stop clients
-- from modifying server-owned fields such as verification flags, versions,
-- subscription state, media metadata, feedback status, and notification body.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Read-own/profile-edit permissions.
grant select on public.profiles to authenticated;
grant update (name, phone_number, phone_e164, preferences) on public.profiles to authenticated;

-- Server-owned reference/projection reads.
grant select on public.revenuecat_entitlements to authenticated;
grant select on public.plan_limits to authenticated;
grant select on public.usage_counters to authenticated;

-- Core owner rows. Deliberately no DELETE grant: clients soft-delete via deleted_at.
grant select on public.requests, public.offers, public.owners, public.offices, public.brokers, public.watchmen, public.quotations to authenticated;
grant insert (
  id, owner_id, request_type, selected_city, location_text, phone_number, country_code, phone_e164,
  min_price, max_price, square_footage, notes, property_type, specific_property_type, rooms, bathrooms, status
) on public.requests to authenticated;
grant insert (
  id, owner_id, offer_type, selected_city, location_text, phone_number, country_code, phone_e164,
  min_price, max_price, square_footage, notes, property_type, specific_property_type, rooms, bathrooms,
  pickup_location_text, pickup_latitude, pickup_longitude, pickup_address, legacy_uploaded_file_name, status
) on public.offers to authenticated;
grant insert (
  id, owner_id, name, phone_number, country_code, phone_e164, property_type_text, property_location, notes,
  pickup_location_text, pickup_latitude, pickup_longitude, pickup_address, legacy_uploaded_file_name
) on public.owners to authenticated;
grant insert (
  id, owner_id, office_name, manager_name, country_code, phone_number, phone_e164, office_location, notes,
  pickup_location_text, pickup_latitude, pickup_longitude, pickup_address
) on public.offices to authenticated;
grant insert (id, owner_id, name, country_code, phone_number, phone_e164, notes) on public.brokers to authenticated;
grant insert (
  id, owner_id, name, country_code, phone_number, phone_e164, building_name, notes, building_location,
  pickup_location_text, pickup_latitude, pickup_longitude, pickup_address
) on public.watchmen to authenticated;
grant insert (
  id, owner_id, property_title, property_type, parking, subtitle, display_date, start_date_text, end_date_text,
  currency_code, professional_fee, total_amount, number_of_installments, payment_type, insurance_amount,
  insurance_returnable, office_name, custom_note, welcome_message_mode, custom_welcome_message
) on public.quotations to authenticated;
grant update (
  request_type, selected_city, location_text, phone_number, country_code, phone_e164,
  min_price, max_price, square_footage, notes, property_type, specific_property_type,
  rooms, bathrooms, status, deleted_at
) on public.requests to authenticated;
grant update (
  offer_type, selected_city, location_text, phone_number, country_code, phone_e164,
  min_price, max_price, square_footage, notes, property_type, specific_property_type,
  rooms, bathrooms, pickup_location_text, pickup_latitude, pickup_longitude,
  pickup_address, legacy_uploaded_file_name, status, deleted_at
) on public.offers to authenticated;
grant update (
  name, phone_number, country_code, phone_e164, property_type_text, property_location,
  notes, pickup_location_text, pickup_latitude, pickup_longitude, pickup_address,
  legacy_uploaded_file_name, deleted_at
) on public.owners to authenticated;
grant update (
  office_name, manager_name, country_code, phone_number, phone_e164, office_location,
  notes, pickup_location_text, pickup_latitude, pickup_longitude, pickup_address, deleted_at
) on public.offices to authenticated;
grant update (name, country_code, phone_number, phone_e164, notes, deleted_at) on public.brokers to authenticated;
grant update (
  name, country_code, phone_number, phone_e164, building_name, notes, building_location,
  pickup_location_text, pickup_latitude, pickup_longitude, pickup_address, deleted_at
) on public.watchmen to authenticated;
grant update (
  property_title, property_type, parking, subtitle, display_date, start_date_text,
  end_date_text, currency_code, professional_fee, total_amount, number_of_installments,
  payment_type, insurance_amount, insurance_returnable, office_name, custom_note,
  welcome_message_mode, custom_welcome_message, deleted_at
) on public.quotations to authenticated;

-- Aggregate children are editable directly by their owner through parent-bound RLS.
grant select, insert, update, delete on public.request_areas, public.offer_areas to authenticated;
grant select, insert, update, delete on public.quotation_downpayments, public.quotation_government_fees, public.quotation_administrative_fees to authenticated;

-- Media is read-only to clients; protected backend owns lifecycle writes.
grant select on public.media_objects, public.offer_media, public.owner_media, public.quotation_media, public.profile_media to authenticated;

-- Favorites are immutable links: insert/delete/select only. added_at is server-generated.
grant select, delete on public.favorite_offers, public.favorite_requests, public.favorite_owners, public.favorite_offices, public.favorite_brokers, public.favorite_watchmen to authenticated;
grant insert (owner_id, target_id) on public.favorite_offers to authenticated;
grant insert (owner_id, target_id) on public.favorite_requests to authenticated;
grant insert (owner_id, target_id) on public.favorite_owners to authenticated;
grant insert (owner_id, target_id) on public.favorite_offices to authenticated;
grant insert (owner_id, target_id) on public.favorite_brokers to authenticated;
grant insert (owner_id, target_id) on public.favorite_watchmen to authenticated;
grant select on public.favorites_unified to authenticated;

-- Feedback snapshot/status are server-derived. Client supplies only safe fields plus owner/id.
grant select on public.feedback to authenticated;
grant insert (id, owner_id, rating, comment, app_version, platform, device_info) on public.feedback to authenticated;

-- Notifications: client can only change read state.
grant select, delete on public.notifications to authenticated;
grant update (is_read) on public.notifications to authenticated;

-- App version reference data.
grant select on public.app_versions to authenticated;

-- Service role is trusted backend authority for all Stage 1 public objects.
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Authenticated clients need helper execution for parent-bound RLS policies.
grant execute on function public.owns_request(uuid) to authenticated;
grant execute on function public.owns_offer(uuid) to authenticated;
grant execute on function public.owns_owner_record(uuid) to authenticated;
grant execute on function public.owns_office(uuid) to authenticated;
grant execute on function public.owns_broker(uuid) to authenticated;
grant execute on function public.owns_watchman(uuid) to authenticated;
grant execute on function public.owns_quotation(uuid) to authenticated;

revoke execute on function public.owns_request(uuid) from public, anon;
revoke execute on function public.owns_offer(uuid) from public, anon;
revoke execute on function public.owns_owner_record(uuid) from public, anon;
revoke execute on function public.owns_office(uuid) from public, anon;
revoke execute on function public.owns_broker(uuid) from public, anon;
revoke execute on function public.owns_watchman(uuid) from public, anon;
revoke execute on function public.owns_quotation(uuid) from public, anon;

-- Do not expose trigger/internal functions to ordinary users.
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
revoke execute on function public.validate_media_attachment_ownership() from public, anon, authenticated;
revoke execute on function public.validate_direct_media_ownership() from public, anon, authenticated;
revoke execute on function public.prepare_feedback_insert() from public, anon, authenticated;
revoke execute on function public.normalize_notification_read_state() from public, anon, authenticated;

commit;
