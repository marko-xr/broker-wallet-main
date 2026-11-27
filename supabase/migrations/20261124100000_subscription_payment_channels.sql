-- Direct Google Play Billing, Tap saved-card changes and the customer billing view.
-- ADDITIVE, SOURCE ONLY until the owner approves a hosted apply.
--
-- Google Play: the app buys with a server-issued opaque account reference. A
-- purchase is bound to an account here, once, and is never moved to another one.
-- Purchase tokens are stored encrypted (AES-256-GCM, key held only by the Edge
-- Function) and looked up by SHA-256.
--
-- Nothing here is reachable by a client role except get_billing_overview(), which
-- returns the caller's own display data.

create table public.play_account_refs (
  -- CASCADE: after account deletion a late notification can no longer resolve it.
  user_id uuid primary key references public.profiles(id) on delete cascade,
  account_ref uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default pg_catalog.now()
);

create table public.play_purchases (
  token_sha256 text primary key,
  token_ciphertext text not null,
  -- SET NULL keeps a tombstone, so a token can never be re-bound after deletion.
  user_id uuid references public.profiles(id) on delete set null,
  product_id text not null,
  base_plan_id text,
  latest_order_id text,
  linked_token_sha256 text,
  acknowledged_at timestamptz,
  orphan_cancel_claimed_at timestamptz,
  orphan_canceled_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint play_purchases_token_hash check (token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint play_purchases_linked_hash check (
    linked_token_sha256 is null or linked_token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint play_purchases_sealed check (token_ciphertext like 'v1.%')
);
create index play_purchases_user_idx on public.play_purchases (user_id);

create table public.tap_card_updates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  agreement_id uuid not null references public.tap_billing_agreements(id) on delete cascade,
  tap_authorize_id text unique,
  status text not null default 'created',
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint tap_card_updates_status_known check (
    status in ('created', 'pending', 'applied', 'failed', 'needs_review'))
);
create index tap_card_updates_user_idx on public.tap_card_updates (user_id, created_at desc);

do $lockdown$
declare
  v_table text;
begin
  foreach v_table in array array['play_account_refs', 'play_purchases', 'tap_card_updates'] loop
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format(
      'revoke all on public.%I from public, anon, authenticated, service_role', v_table);
  end loop;
end;
$lockdown$;

-- ---------------------------------------------------------------------------
-- Google Play
-- ---------------------------------------------------------------------------

-- The opaque id the app passes to Play as obfuscatedAccountId.
create function public.play_account_ref(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ref uuid;
begin
  if p_user is null then
    raise exception using errcode = 'PBP01', message = 'invalid_account';
  end if;
  if not exists (select 1 from public.profiles as p where p.id = p_user) then
    return null;
  end if;
  insert into public.play_account_refs (user_id) values (p_user)
  on conflict (user_id) do nothing;
  select r.account_ref into v_ref from public.play_account_refs as r where r.user_id = p_user;
  return v_ref;
end;
$function$;

-- Binds a verified Play snapshot to its one account and applies it in a single
-- transaction. Ownership, in order:
--   1. an existing purchase keeps its owner;
--   2. a new purchase belongs to the account of its server-issued reference;
--   3. without one, to the owner of the purchase Google says it replaces.
-- A signed-in caller who is not that owner changes nothing.
-- Outcomes: processed, duplicate, stale, ignored, no_account, unlinked,
-- ownership_conflict. `acknowledge` is true only for a purchase that passed all of
-- this: an unacknowledged purchase is refunded by Google after three days.
create function public.play_apply_snapshot(
  p_token_sha256 text,
  p_token_ciphertext text,
  p_caller uuid,
  p_account_ref uuid,
  p_product_id text,
  p_base_plan_id text,
  p_order_id text,
  p_linked_sha256 text,
  p_event_id text,
  p_event_type text,
  p_event_at timestamptz,
  p_billing_cycle text,
  p_state text,
  p_auto_renew boolean,
  p_started_at timestamptz,
  p_paid_through_at timestamptz,
  p_grace_until timestamptz,
  p_environment text,
  p_ack_pending boolean,
  p_payload_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_purchase public.play_purchases%rowtype;
  v_exists boolean;
  v_ref_owner uuid;
  v_linked public.play_purchases%rowtype;
  v_has_linked boolean := false;
  v_owner uuid;
  v_outcome text;
  v_linked_record public.subscription_provider_records%rowtype;
begin
  if p_token_sha256 is null or p_token_sha256 !~ '^[0-9a-f]{64}$'
     or (p_linked_sha256 is not null and p_linked_sha256 !~ '^[0-9a-f]{64}$')
     or p_linked_sha256 = p_token_sha256
     or p_token_ciphertext is null or p_token_ciphertext not like 'v1.%'
     or nullif(pg_catalog.btrim(p_product_id), '') is null
     or nullif(pg_catalog.btrim(p_event_id), '') is null
     or p_ack_pending is null then
    raise exception using errcode = 'PBP01', message = 'invalid_play_snapshot';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'subscription_provider:google_play:' || p_token_sha256, 0));

  select pp.* into v_purchase from public.play_purchases as pp
    where pp.token_sha256 = p_token_sha256 for update;
  v_exists := found;
  if p_account_ref is not null then
    select r.user_id into v_ref_owner from public.play_account_refs as r
      where r.account_ref = p_account_ref;
  end if;
  if p_linked_sha256 is not null then
    select pp.* into v_linked from public.play_purchases as pp
      where pp.token_sha256 = p_linked_sha256 for update;
    v_has_linked := found;
  end if;

  if v_exists then
    v_owner := v_purchase.user_id;
    if v_owner is null then
      v_outcome := 'no_account';
    elsif v_ref_owner is not null and v_ref_owner <> v_owner then
      v_outcome := 'ownership_conflict';
    end if;
  else
    v_owner := coalesce(v_ref_owner, case when v_has_linked then v_linked.user_id end);
    if v_owner is null then
      v_outcome := 'unlinked';
    end if;
  end if;
  if v_outcome is null and p_caller is not null and p_caller <> v_owner then
    v_outcome := 'ownership_conflict';
  end if;
  if v_outcome is null and v_has_linked and v_linked.user_id is not null
     and v_linked.user_id <> v_owner then
    v_outcome := 'ownership_conflict';
  end if;

  if v_outcome is not null then
    insert into public.billing_events (
      provider, event_id, event_type, event_at, provider_subscription_id, outcome, payload_sha256)
    values ('google_play', p_event_id, p_event_type, p_event_at, p_token_sha256,
            case when v_outcome = 'unlinked' then 'ignored' else v_outcome end, p_payload_sha256)
    on conflict (provider, event_id) do nothing;
    return pg_catalog.jsonb_build_object('outcome', v_outcome, 'acknowledge', false);
  end if;

  if v_exists then
    update public.play_purchases as pp set
      token_ciphertext = p_token_ciphertext,
      product_id = p_product_id,
      base_plan_id = coalesce(p_base_plan_id, pp.base_plan_id),
      latest_order_id = coalesce(p_order_id, pp.latest_order_id),
      linked_token_sha256 = coalesce(p_linked_sha256, pp.linked_token_sha256),
      updated_at = pg_catalog.now()
    where pp.token_sha256 = p_token_sha256;
  else
    insert into public.play_purchases (
      token_sha256, token_ciphertext, user_id, product_id, base_plan_id,
      latest_order_id, linked_token_sha256)
    values (p_token_sha256, p_token_ciphertext, v_owner, p_product_id, p_base_plan_id,
            p_order_id, p_linked_sha256);
  end if;

  v_outcome := public.apply_subscription_provider_event(
    'google_play', p_event_id, p_event_type, p_event_at, v_owner, p_token_sha256,
    p_product_id, p_billing_cycle, p_state, p_auto_renew, p_started_at,
    p_paid_through_at, p_grace_until, p_environment, p_payload_sha256);

  -- Google: the replaced token must stop granting anything.
  if v_has_linked and v_linked.user_id = v_owner then
    select r.* into v_linked_record from public.subscription_provider_records as r
      where r.provider = 'google_play' and r.provider_subscription_id = p_linked_sha256;
    if found and v_linked_record.state <> 'revoked' then
      perform public.apply_subscription_provider_event(
        'google_play', 'linked:' || p_linked_sha256 || ':' || p_token_sha256,
        'LINKED_TOKEN_REPLACED', greatest(p_event_at, v_linked_record.last_event_at),
        v_owner, p_linked_sha256, null, null, 'revoked', false, null, null, null,
        v_linked_record.environment, null);
    end if;
  end if;

  return pg_catalog.jsonb_build_object(
    'outcome', v_outcome,
    'user_id', v_owner,
    'acknowledge',
      p_ack_pending
      and v_outcome in ('processed', 'duplicate', 'stale')
      and p_state in ('active', 'cancel_scheduled', 'billing_issue')
      and (p_environment = 'production' or public.subscription_accepts_sandbox()));
end;
$function$;

create function public.play_mark_acknowledged(p_token_sha256 text)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.play_purchases as pp
    set acknowledged_at = coalesce(pp.acknowledged_at, pg_catalog.now()),
        updated_at = pg_catalog.now()
    where pp.token_sha256 = p_token_sha256;
$function$;

create function public.play_user_purchases(p_user uuid)
returns table (token_sha256 text, token_ciphertext text)
language sql
stable
security definer
set search_path = ''
as $function$
  select pp.token_sha256, pp.token_ciphertext
  from public.play_purchases as pp
  join public.subscription_provider_records as r
    on r.provider = 'google_play' and r.provider_subscription_id = pp.token_sha256
  where pp.user_id = p_user and r.state not in ('revoked', 'refunded')
  order by pp.updated_at desc
  limit 10;
$function$;

create function public.play_purchase_ciphertexts(p_hashes text[])
returns table (token_sha256 text, token_ciphertext text)
language sql
stable
security definer
set search_path = ''
as $function$
  select pp.token_sha256, pp.token_ciphertext
  from public.play_purchases as pp
  where pp.token_sha256 = any (p_hashes);
$function$;

-- Subscriptions still renewing for an account that no longer exists. Google would
-- keep charging that person, so the job cancels renewal (access is already gone).
create function public.play_claim_orphans(p_limit integer)
returns table (token_sha256 text, token_ciphertext text, product_id text)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = 'PBP01', message = 'invalid_limit';
  end if;
  return query
  with due as (
    select pp.token_sha256
    from public.play_purchases as pp
    join public.subscription_provider_records as r
      on r.provider = 'google_play' and r.provider_subscription_id = pp.token_sha256
    where pp.user_id is null and pp.orphan_canceled_at is null
      and r.auto_renew and r.state in ('active', 'billing_issue')
      and (pp.orphan_cancel_claimed_at is null
           or pp.orphan_cancel_claimed_at < pg_catalog.now() - interval '6 hours')
    order by pp.updated_at
    limit p_limit
    for update of pp skip locked
  )
  update public.play_purchases as pp
    set orphan_cancel_claimed_at = pg_catalog.now()
  from due
  where pp.token_sha256 = due.token_sha256
  returning pp.token_sha256, pp.token_ciphertext, pp.product_id;
end;
$function$;

create function public.play_mark_orphan_canceled(p_token_sha256 text)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.play_purchases as pp
    set orphan_canceled_at = pg_catalog.now(), updated_at = pg_catalog.now()
    where pp.token_sha256 = p_token_sha256 and pp.user_id is null;
$function$;

-- ---------------------------------------------------------------------------
-- Tap: changing the saved card
-- ---------------------------------------------------------------------------

create function public.tap_card_update_create(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_agreement public.tap_billing_agreements%rowtype;
  v_update uuid;
begin
  if p_user is null then
    raise exception using errcode = 'PBP01', message = 'invalid_account';
  end if;
  perform public.subscription_lock(p_user);
  select a.* into v_agreement from public.tap_billing_agreements as a where a.user_id = p_user;
  if not found then
    return pg_catalog.jsonb_build_object('refused', 'no_agreement');
  end if;
  if not exists (
    select 1 from public.subscription_provider_records as r
    where r.provider = 'tap' and r.provider_subscription_id = public.tap_subscription_key(p_user)
      and r.state in ('active', 'cancel_scheduled', 'billing_issue')
  ) then
    return pg_catalog.jsonb_build_object('refused', 'not_active');
  end if;
  select u.id into v_update from public.tap_card_updates as u
    where u.user_id = p_user and u.status in ('created', 'pending')
      and u.created_at > pg_catalog.now() - interval '25 minutes'
    order by u.created_at desc limit 1;
  if v_update is null then
    insert into public.tap_card_updates (user_id, agreement_id)
    values (p_user, v_agreement.id)
    returning id into v_update;
  end if;
  return pg_catalog.jsonb_build_object(
    'update_id', v_update, 'tap_customer_id', v_agreement.tap_customer_id);
end;
$function$;

create function public.tap_card_update_attach(p_update uuid, p_authorize_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.tap_card_updates%rowtype;
begin
  if p_update is null or nullif(pg_catalog.btrim(p_authorize_id), '') is null then
    raise exception using errcode = 'PBP01', message = 'invalid_card_update';
  end if;
  select u.* into v_row from public.tap_card_updates as u where u.id = p_update for update;
  if not found then
    return 'unknown_update';
  end if;
  if v_row.tap_authorize_id is not null and v_row.tap_authorize_id <> p_authorize_id then
    return 'authorize_mismatch';
  end if;
  update public.tap_card_updates as u
    set tap_authorize_id = p_authorize_id,
        status = case when u.status = 'created' then 'pending' else u.status end,
        updated_at = pg_catalog.now()
    where u.id = p_update;
  return 'attached';
end;
$function$;

create function public.tap_card_update_owner(p_authorize_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.user_id from public.tap_card_updates as u where u.tap_authorize_id = p_authorize_id;
$function$;

-- A card replaces the saved one only after an AUTHORIZED result, for the same Tap
-- customer, with a new agreement. Clearing the failure count lets the next job run
-- retry a failed renewal on the new card.
create function public.tap_card_update_settle(
  p_update uuid,
  p_authorize_id text,
  p_status text,
  p_customer_id text,
  p_card_id text,
  p_agreement_id text,
  p_card jsonb default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.tap_card_updates%rowtype;
  v_agreement public.tap_billing_agreements%rowtype;
  v_card jsonb := public.tap_card_display(p_card);
begin
  if p_update is null or nullif(pg_catalog.btrim(p_authorize_id), '') is null or p_status is null then
    raise exception using errcode = 'PBP01', message = 'invalid_card_update';
  end if;
  select u.* into v_row from public.tap_card_updates as u where u.id = p_update for update;
  if not found then
    return 'unknown_update';
  end if;
  if v_row.tap_authorize_id is not null and v_row.tap_authorize_id <> p_authorize_id then
    return 'authorize_mismatch';
  end if;
  if v_row.status in ('applied', 'failed', 'needs_review') then
    return 'duplicate';
  end if;
  perform public.subscription_lock(v_row.user_id);
  select a.* into v_agreement from public.tap_billing_agreements as a
    where a.id = v_row.agreement_id for update;
  if not found then
    return 'unknown_update';
  end if;

  if p_status = 'AUTHORIZED' then
    if nullif(p_card_id, '') is null or nullif(p_agreement_id, '') is null
       or p_customer_id is distinct from v_agreement.tap_customer_id then
      update public.tap_card_updates as u
        set status = 'needs_review', tap_authorize_id = p_authorize_id, updated_at = pg_catalog.now()
        where u.id = p_update;
      return 'needs_review';
    end if;
    update public.tap_billing_agreements as a set
      tap_card_id = p_card_id,
      tap_agreement_id = p_agreement_id,
      card_brand = v_card ->> 'brand',
      card_last_four = v_card ->> 'last_four',
      card_exp_month = (v_card ->> 'exp_month')::smallint,
      card_exp_year = (v_card ->> 'exp_year')::smallint,
      failed_attempts = 0,
      next_attempt_at = null,
      updated_at = pg_catalog.now()
    where a.id = v_agreement.id;
    update public.tap_card_updates as u
      set status = 'applied', tap_authorize_id = p_authorize_id, updated_at = pg_catalog.now()
      where u.id = p_update;
    return 'applied';
  end if;

  if p_status in ('ABANDONED', 'CANCELLED', 'FAILED', 'DECLINED', 'RESTRICTED', 'VOID', 'TIMEDOUT') then
    update public.tap_card_updates as u
      set status = 'failed', tap_authorize_id = p_authorize_id, updated_at = pg_catalog.now()
      where u.id = p_update;
    return 'failed';
  end if;
  return 'pending';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Which payment choices may be presented
-- ---------------------------------------------------------------------------

-- One row, changed only by the owner as postgres. Turning the Android card choice
-- on requires a recorded basis (the Google Play program enrollment that allows it).
create table public.billing_channel_policy (
  singleton boolean primary key default true,
  android_card_choice boolean not null default false,
  android_card_choice_basis text,
  changed_at timestamptz not null default pg_catalog.now(),
  constraint billing_channel_policy_one_row check (singleton),
  constraint billing_channel_policy_basis check (
    not android_card_choice
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(android_card_choice_basis, ''))) >= 10)
);
insert into public.billing_channel_policy (singleton) values (true);

-- ---------------------------------------------------------------------------
-- UAE VAT: tax invoices and credit notes for payments Broker Wallet collects (Tap)
-- ---------------------------------------------------------------------------

-- The supplier details printed on every document. A card payment cannot start
-- until the TRN and address are set, so no sale happens without a valid invoice.
create table public.billing_tax_profile (
  singleton boolean primary key default true,
  legal_name text not null default 'NMO Digital LLC',
  trn text,
  address text,
  vat_rate_bp integer not null default 500,
  prices_include_vat boolean not null default true,
  updated_at timestamptz not null default pg_catalog.now(),
  constraint billing_tax_profile_one_row check (singleton),
  constraint billing_tax_profile_trn check (trn is null or trn ~ '^[0-9]{15}$'),
  constraint billing_tax_profile_rate check (vat_rate_bp between 0 and 10000),
  -- Only VAT-inclusive prices are supported: the customer pays the listed price.
  constraint billing_tax_profile_inclusive check (prices_include_vat)
);
insert into public.billing_tax_profile (singleton) values (true);

-- Gapless numbering per document kind and year: a row lock, not a sequence.
create table public.billing_document_counters (
  kind text not null,
  year integer not null,
  last_number integer not null default 0,
  primary key (kind, year)
);

create table public.billing_documents (
  id uuid primary key default gen_random_uuid(),
  document_number text not null unique,
  kind text not null,
  -- SET NULL: tax records outlive the account, which they do not identify.
  user_id uuid references public.profiles(id) on delete set null,
  tap_order_id uuid not null references public.tap_billing_orders(id) on delete restrict,
  related_document_id uuid references public.billing_documents(id) on delete restrict,
  issued_at timestamptz not null default pg_catalog.now(),
  billing_cycle text not null,
  currency text not null default 'AED',
  total_fils integer not null,
  vat_fils integer not null,
  net_fils integer not null,
  vat_rate_bp integer not null,
  supplier_legal_name text not null,
  supplier_trn text not null,
  supplier_address text not null,
  constraint billing_documents_kind_known check (kind in ('tax_invoice', 'tax_credit_note')),
  constraint billing_documents_currency check (currency = 'AED'),
  constraint billing_documents_amounts check (
    total_fils > 0 and vat_fils >= 0 and net_fils >= 0 and net_fils + vat_fils = total_fils),
  constraint billing_documents_credit_links check (
    (kind = 'tax_credit_note') = (related_document_id is not null)),
  constraint billing_documents_one_per_order unique (tap_order_id, kind)
);
create index billing_documents_user_idx on public.billing_documents (user_id, issued_at desc);

do $tax_lockdown$
declare
  v_table text;
begin
  foreach v_table in array array[
    'billing_channel_policy', 'billing_tax_profile', 'billing_document_counters', 'billing_documents'
  ] loop
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format(
      'revoke all on public.%I from public, anon, authenticated, service_role', v_table);
  end loop;
end;
$tax_lockdown$;

create function public.billing_tax_ready()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((
    select p.trn is not null
       and nullif(pg_catalog.btrim(p.legal_name), '') is not null
       and nullif(pg_catalog.btrim(p.address), '') is not null
    from public.billing_tax_profile as p), false);
$function$;

-- VAT contained in a VAT-inclusive total, rounded half up to the fils.
create function public.billing_vat_fils(p_total_fils integer, p_rate_bp integer)
returns integer
language sql
immutable
set search_path = ''
as $function$
  select ((p_total_fils::bigint * p_rate_bp * 2 + (10000 + p_rate_bp))
          / (2 * (10000 + p_rate_bp)))::integer;
$function$;

create function public.billing_next_number(p_kind text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_year integer := extract(year from pg_catalog.now() at time zone 'Asia/Dubai')::integer;
  v_number integer;
begin
  insert into public.billing_document_counters as c (kind, year, last_number)
  values (p_kind, v_year, 1)
  on conflict (kind, year) do update set last_number = c.last_number + 1
  returning c.last_number into v_number;
  return case p_kind when 'tax_invoice' then 'BW-INV-' else 'BW-CN-' end
    || v_year::text || '-' || pg_catalog.lpad(v_number::text, 6, '0');
end;
$function$;

-- A sale starts only when its invoice can be valid.
create function public.billing_require_tax_profile()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.kind = 'initial' and not public.billing_tax_ready() then
    raise exception using errcode = 'PBP02', message = 'tax_profile_incomplete';
  end if;
  return new;
end;
$function$;

create trigger tap_orders_require_tax_profile
  before insert on public.tap_billing_orders
  for each row execute function public.billing_require_tax_profile();

-- Issued in the same transaction as the settlement: a captured payment gets its
-- tax invoice, a full refund of it gets a credit note. A missing profile never
-- blocks recording a real payment; the operations report lists the gap.
create function public.billing_issue_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile public.billing_tax_profile%rowtype;
  v_total integer;
  v_vat integer;
  v_invoice public.billing_documents%rowtype;
begin
  select p.* into v_profile from public.billing_tax_profile as p;
  if not public.billing_tax_ready() then
    return null;
  end if;
  v_total := (new.amount * 100)::integer;
  v_vat := public.billing_vat_fils(v_total, v_profile.vat_rate_bp);

  if new.status = 'captured' and old.status is distinct from 'captured' then
    insert into public.billing_documents (
      document_number, kind, user_id, tap_order_id, billing_cycle, total_fils, vat_fils,
      net_fils, vat_rate_bp, supplier_legal_name, supplier_trn, supplier_address)
    select public.billing_next_number('tax_invoice'), 'tax_invoice', new.user_id, new.id,
           new.billing_cycle, v_total, v_vat, v_total - v_vat, v_profile.vat_rate_bp,
           v_profile.legal_name, v_profile.trn, v_profile.address
    where not exists (
      select 1 from public.billing_documents as d
      where d.tap_order_id = new.id and d.kind = 'tax_invoice');
  elsif new.status = 'refunded' and old.status = 'captured' then
    select d.* into v_invoice from public.billing_documents as d
      where d.tap_order_id = new.id and d.kind = 'tax_invoice';
    if found then
      insert into public.billing_documents (
        document_number, kind, user_id, tap_order_id, related_document_id, billing_cycle,
        total_fils, vat_fils, net_fils, vat_rate_bp, supplier_legal_name, supplier_trn,
        supplier_address)
      values (
        public.billing_next_number('tax_credit_note'), 'tax_credit_note', new.user_id, new.id,
        v_invoice.id, new.billing_cycle, v_invoice.total_fils, v_invoice.vat_fils,
        v_invoice.net_fils, v_invoice.vat_rate_bp, v_profile.legal_name, v_profile.trn,
        v_profile.address)
      on conflict (tap_order_id, kind) do nothing;
    end if;
  end if;
  return null;
end;
$function$;

create trigger tap_orders_issue_documents
  after update of status on public.tap_billing_orders
  for each row when (new.status is distinct from old.status)
  execute function public.billing_issue_documents();

-- ---------------------------------------------------------------------------
-- What the customer may see
-- ---------------------------------------------------------------------------

create function public.get_billing_channels()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform public.subscription_require_caller();
  return pg_catalog.jsonb_build_object(
    'android_card_choice',
    coalesce((select p.android_card_choice from public.billing_channel_policy as p), false));
end;
$function$;

-- The caller's own billing view. Display fields only: never a token, a provider
-- customer id, a card id or an agreement id.
create function public.get_billing_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := public.subscription_require_caller();
  v_sandbox boolean := public.subscription_accepts_sandbox();
  v_record public.subscription_provider_records%rowtype;
  v_agreement public.tap_billing_agreements%rowtype;
  v_has_agreement boolean;
  v_history jsonb;
begin
  select r.* into v_record from public.subscription_provider_records as r
    where r.user_id = v_user and r.state <> 'unknown'
      and (r.environment = 'production' or (v_sandbox and r.environment = 'sandbox'))
    order by (r.state not in ('revoked', 'refunded', 'expired')) desc,
             greatest(r.paid_through_at, r.grace_until) desc nulls last, r.id
    limit 1;

  select a.* into v_agreement from public.tap_billing_agreements as a where a.user_id = v_user;
  v_has_agreement := found;

  select coalesce(pg_catalog.jsonb_agg(t.entry order by t.at desc), '[]'::jsonb) into v_history
  from (
    select o.created_at as at, pg_catalog.jsonb_build_object(
      'id', o.id, 'kind', o.kind, 'cycle', o.billing_cycle, 'amount', o.amount,
      'currency', o.currency, 'status', o.status, 'at', o.created_at,
      'documents', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'kind', d.kind, 'number', d.document_number, 'issued_at', d.issued_at,
          'total_fils', d.total_fils, 'vat_fils', d.vat_fils, 'net_fils', d.net_fils,
          'vat_rate_bp', d.vat_rate_bp, 'supplier', d.supplier_legal_name,
          'trn', d.supplier_trn, 'address', d.supplier_address) order by d.issued_at)
        from public.billing_documents as d where d.tap_order_id = o.id), '[]'::jsonb)) as entry
    from public.tap_billing_orders as o
    where o.user_id = v_user and o.status in ('pending', 'captured', 'failed', 'refunded')
    order by o.created_at desc
    limit 50
  ) as t;

  return pg_catalog.jsonb_build_object(
    'provider', v_record.provider,
    'state', v_record.state,
    'cycle', v_record.billing_cycle,
    'auto_renew', coalesce(v_record.auto_renew, false),
    'paid_through', v_record.paid_through_at,
    'grace_until', v_record.grace_until,
    'product_id', case when v_record.provider = 'google_play' then v_record.product_id end,
    'payment_method', case when v_has_agreement and v_record.provider = 'tap' then
      pg_catalog.jsonb_build_object(
        'brand', v_agreement.card_brand, 'last_four', v_agreement.card_last_four,
        'exp_month', v_agreement.card_exp_month, 'exp_year', v_agreement.card_exp_year)
      end,
    'can_renew_on_file', v_has_agreement and v_record.provider = 'tap',
    'history', v_history);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------

do $privileges$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.play_account_ref(uuid)',
    'public.play_apply_snapshot(text, text, uuid, uuid, text, text, text, text, text, text, timestamptz, text, text, boolean, timestamptz, timestamptz, timestamptz, text, boolean, text)',
    'public.play_mark_acknowledged(text)',
    'public.play_user_purchases(uuid)',
    'public.play_purchase_ciphertexts(text[])',
    'public.play_claim_orphans(integer)',
    'public.play_mark_orphan_canceled(text)',
    'public.tap_card_update_create(uuid)',
    'public.tap_card_update_attach(uuid, text)',
    'public.tap_card_update_owner(text)',
    'public.tap_card_update_settle(uuid, text, text, text, text, text, jsonb)'
  ] loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated', v_signature);
    execute pg_catalog.format('grant execute on function %s to service_role', v_signature);
  end loop;
end;
$privileges$;

revoke all on function public.get_billing_overview() from public, anon, service_role;
grant execute on function public.get_billing_overview() to authenticated;
revoke all on function public.get_billing_channels() from public, anon, service_role;
grant execute on function public.get_billing_channels() to authenticated;

do $tax_privileges$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.billing_tax_ready()',
    'public.billing_vat_fils(integer, integer)',
    'public.billing_next_number(text)',
    'public.billing_require_tax_profile()',
    'public.billing_issue_documents()'
  ] loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role', v_signature);
  end loop;
end;
$tax_privileges$;
