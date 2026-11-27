-- Provider billing state: store reconciliation and Tap recurring billing for the
-- web channel. ADDITIVE, SOURCE ONLY until the owner approves a hosted apply.
--
-- Every function is service-role only and is called by the subscription-billing
-- Edge Function. Prices live here, never in a client. A charge activates Plus only
-- when it matches a server-created order in amount and currency.
--
-- Tap has no subscription scheduler for new integrations: the merchant triggers
-- each renewal. tap_claim_due_renewals() therefore claims each due period under a
-- unique key, so one period can never be charged twice by overlapping job runs.
-- Whether a renewal really runs is decided by TAP_RENEWALS_ENABLED in the function.

alter table public.subscription_provider_records
  add column last_reconciled_at timestamptz;

create table public.subscription_sync_state (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_sync_at timestamptz not null
);

-- Deleting the account removes the agreement, which is what stops any renewal.
create table public.tap_billing_agreements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  tap_customer_id text not null,
  tap_card_id text not null,
  tap_agreement_id text not null,
  billing_cycle text not null,
  auto_renew boolean not null default true,
  failed_attempts smallint not null default 0,
  next_attempt_at timestamptz,
  -- Display only. Tap holds the card; the full number and CVV never reach us.
  card_brand text,
  card_last_four text,
  card_exp_month smallint,
  card_exp_year smallint,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint tap_agreements_cycle_known check (billing_cycle in ('monthly', 'annual')),
  constraint tap_agreements_attempts_range check (failed_attempts between 0 and 3),
  constraint tap_agreements_card_brand_clean check (
    card_brand is null or card_brand ~ '^[A-Za-z0-9 _-]{1,32}$'),
  constraint tap_agreements_card_last_four check (
    card_last_four is null or card_last_four ~ '^[0-9]{4}$'),
  constraint tap_agreements_card_expiry check (
    (card_exp_month is null or card_exp_month between 1 and 12)
    and (card_exp_year is null or card_exp_year between 0 and 9999))
);

create table public.tap_billing_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  agreement_id uuid references public.tap_billing_agreements(id) on delete set null,
  kind text not null,
  billing_cycle text not null,
  amount numeric(10, 2) not null,
  currency text not null default 'AED',
  status text not null default 'created',
  tap_charge_id text unique,
  renewal_for timestamptz,
  attempt smallint not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint tap_orders_kind_known check (kind in ('initial', 'renewal')),
  constraint tap_orders_cycle_known check (billing_cycle in ('monthly', 'annual')),
  constraint tap_orders_currency check (currency = 'AED'),
  constraint tap_orders_amount check (
    (billing_cycle = 'monthly' and amount = 20.00)
    or (billing_cycle = 'annual' and amount = 180.00)),
  constraint tap_orders_status_known check (
    status in ('created', 'pending', 'captured', 'failed', 'refunded', 'needs_review')),
  constraint tap_orders_renewal_shape check ((kind = 'renewal') = (renewal_for is not null))
);
create unique index tap_orders_one_renewal_attempt_idx
  on public.tap_billing_orders (agreement_id, renewal_for, attempt) where kind = 'renewal';
create index tap_orders_user_idx on public.tap_billing_orders (user_id, created_at desc);

do $lockdown$
declare
  v_table text;
begin
  foreach v_table in array array[
    'subscription_sync_state', 'tap_billing_agreements', 'tap_billing_orders'
  ] loop
    execute pg_catalog.format('alter table public.%I enable row level security', v_table);
    execute pg_catalog.format(
      'revoke all on public.%I from public, anon, authenticated, service_role', v_table);
  end loop;
end;
$lockdown$;

-- ---------------------------------------------------------------------------
-- Store reconciliation
-- ---------------------------------------------------------------------------

-- At most one provider lookup per account per p_min_seconds.
create function public.subscription_sync_claim(p_user uuid, p_min_seconds integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claimed uuid;
begin
  if p_user is null or p_min_seconds is null or p_min_seconds < 1 then
    raise exception using errcode = 'PBP01', message = 'invalid_sync_claim';
  end if;
  insert into public.subscription_sync_state as s (user_id, last_sync_at)
  values (p_user, pg_catalog.now())
  on conflict (user_id) do update set last_sync_at = excluded.last_sync_at
    where s.last_sync_at <= pg_catalog.now() - pg_catalog.make_interval(secs => p_min_seconds)
  returning s.user_id into v_claimed;
  return v_claimed is not null;
end;
$function$;

-- Records whose webhook may have been missed. SKIP LOCKED plus the claim stamp
-- keeps overlapping job runs from working on the same record.
create function public.subscription_claim_reconcile_batch(p_limit integer)
returns table (
  user_id uuid, provider text, provider_subscription_id text, product_id text,
  state text, auto_renew boolean, paid_through_at timestamptz, grace_until timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception using errcode = 'PBP01', message = 'invalid_limit';
  end if;
  return query
  with due as (
    select r.id
    from public.subscription_provider_records as r
    where r.user_id is not null
      and r.provider in ('google_play', 'app_store')
      and r.state in ('active', 'cancel_scheduled', 'billing_issue', 'paused')
      and (r.paid_through_at is null
           or r.paid_through_at < pg_catalog.now() + interval '2 hours'
           or r.last_event_at < pg_catalog.now() - interval '24 hours')
      and (r.last_reconciled_at is null
           or r.last_reconciled_at < pg_catalog.now() - interval '1 hour')
    order by r.last_reconciled_at nulls first, r.id
    limit p_limit
    for update of r skip locked
  )
  update public.subscription_provider_records as r
    set last_reconciled_at = pg_catalog.now()
  from due
  where r.id = due.id
  returning r.user_id, r.provider, r.provider_subscription_id, r.product_id,
            r.state, r.auto_renew, r.paid_through_at, r.grace_until;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Tap: orders and settlement
-- ---------------------------------------------------------------------------

create function public.tap_price(p_cycle text)
returns numeric
language sql
immutable
set search_path = ''
as $function$
  select case p_cycle when 'monthly' then 20.00::numeric when 'annual' then 180.00::numeric end;
$function$;

create function public.tap_subscription_key(p_user uuid)
returns text
language sql
immutable
set search_path = ''
as $function$
  select 'tap:' || p_user::text;
$function$;

-- One open order per account and cycle, so a double tap reuses the same order and
-- therefore the same Tap idempotency key.
create function public.tap_create_order(p_user uuid, p_cycle text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_price numeric := public.tap_price(p_cycle);
  v_order public.tap_billing_orders%rowtype;
  v_access jsonb;
  v_customer text;
begin
  if p_user is null or v_price is null then
    raise exception using errcode = 'PBP01', message = 'invalid_order';
  end if;
  if not exists (select 1 from public.profiles as p where p.id = p_user) then
    return pg_catalog.jsonb_build_object('refused', 'no_account');
  end if;
  perform public.subscription_lock(p_user);
  v_access := public.subscription_access(p_user);
  if (v_access ->> 'is_plus')::boolean then
    return pg_catalog.jsonb_build_object('refused', 'already_plus');
  end if;

  select a.tap_customer_id into v_customer
    from public.tap_billing_agreements as a where a.user_id = p_user;
  select o.* into v_order from public.tap_billing_orders as o
    where o.user_id = p_user and o.kind = 'initial' and o.billing_cycle = p_cycle
      and o.status in ('created', 'pending')
      and o.created_at > pg_catalog.now() - interval '25 minutes'
    order by o.created_at desc limit 1;
  if not found then
    insert into public.tap_billing_orders (user_id, kind, billing_cycle, amount)
    values (p_user, 'initial', p_cycle, v_price)
    returning * into v_order;
  end if;
  return pg_catalog.jsonb_build_object(
    'order_id', v_order.id, 'amount', v_order.amount, 'currency', v_order.currency,
    'tap_customer_id', v_customer,
    -- Tap needs a phone number to save a card. Email accounts may keep it on the profile.
    'customer_phone', (select p.phone_e164 from public.profiles as p where p.id = p_user));
end;
$function$;

create function public.tap_attach_charge(p_order uuid, p_charge_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.tap_billing_orders%rowtype;
begin
  if p_order is null or nullif(pg_catalog.btrim(p_charge_id), '') is null then
    raise exception using errcode = 'PBP01', message = 'invalid_charge';
  end if;
  select o.* into v_order from public.tap_billing_orders as o where o.id = p_order for update;
  if not found then
    return 'unknown_order';
  end if;
  if v_order.tap_charge_id is not null and v_order.tap_charge_id <> p_charge_id then
    return 'charge_mismatch';
  end if;
  update public.tap_billing_orders as o
    set tap_charge_id = p_charge_id,
        status = case when o.status = 'created' then 'pending' else o.status end,
        updated_at = pg_catalog.now()
    where o.id = p_order;
  return 'attached';
end;
$function$;

-- Keeps only well-formed display fields, so an unexpected provider value can never
-- abort the settlement of a real payment.
create function public.tap_card_display(p_card jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'brand', case when p_card ->> 'brand' ~ '^[A-Za-z0-9 _-]{1,32}$' then p_card ->> 'brand' end,
    'last_four', case when p_card ->> 'last_four' ~ '^[0-9]{4}$' then p_card ->> 'last_four' end,
    'exp_month', case when p_card ->> 'exp_month' ~ '^(0?[1-9]|1[0-2])$'
                      then (p_card ->> 'exp_month')::smallint end,
    'exp_year', case when p_card ->> 'exp_year' ~ '^[0-9]{2,4}$'
                     then (p_card ->> 'exp_year')::smallint end);
$function$;

-- The only path from a Tap charge to Plus. The caller has verified the webhook
-- hash and re-read the charge from Tap. Returns: captured, duplicate, failed,
-- pending, unknown_order, charge_mismatch, amount_mismatch, no_account.
create function public.tap_settle_charge(
  p_order uuid,
  p_charge_id text,
  p_status text,
  p_amount numeric,
  p_currency text,
  p_live boolean,
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
  v_order public.tap_billing_orders%rowtype;
  v_agreement public.tap_billing_agreements%rowtype;
  v_key text;
  v_current timestamptz;
  v_paid timestamptz;
  v_environment text;
  v_period interval;
  v_renews boolean;
  v_grace timestamptz;
  v_card jsonb := public.tap_card_display(p_card);
begin
  if p_order is null or nullif(pg_catalog.btrim(p_charge_id), '') is null
     or p_status is null or p_live is null then
    raise exception using errcode = 'PBP01', message = 'invalid_charge';
  end if;
  select o.* into v_order from public.tap_billing_orders as o where o.id = p_order for update;
  if not found then
    return 'unknown_order';
  end if;
  if v_order.tap_charge_id is not null and v_order.tap_charge_id <> p_charge_id then
    return 'charge_mismatch';
  end if;
  if v_order.status in ('captured', 'refunded') then
    return 'duplicate';
  end if;
  -- A replayed decline must not count as another failed attempt.
  if v_order.status = 'failed' and p_status <> 'CAPTURED' then
    return 'duplicate';
  end if;
  if p_status = 'CAPTURED' and (p_amount is distinct from v_order.amount
                                or p_currency is distinct from v_order.currency) then
    update public.tap_billing_orders as o
      set status = 'needs_review', tap_charge_id = p_charge_id, updated_at = pg_catalog.now()
      where o.id = p_order;
    return 'amount_mismatch';
  end if;
  if v_order.user_id is null then
    -- The account was deleted. Nothing is re-created; the payment needs a refund.
    update public.tap_billing_orders as o
      set status = case when p_status = 'CAPTURED' then 'needs_review' else o.status end,
          tap_charge_id = p_charge_id, updated_at = pg_catalog.now()
      where o.id = p_order;
    return 'no_account';
  end if;

  perform public.subscription_lock(v_order.user_id);
  v_key := public.tap_subscription_key(v_order.user_id);
  v_environment := case when p_live then 'production' else 'sandbox' end;
  select r.paid_through_at into v_current from public.subscription_provider_records as r
    where r.provider = 'tap' and r.provider_subscription_id = v_key;

  if p_status = 'CAPTURED' then
    v_period := case v_order.billing_cycle when 'annual' then interval '1 year' else interval '1 month' end;
    v_paid := greatest(coalesce(v_current, pg_catalog.now()), pg_catalog.now()) + v_period;

    -- Only a customer-present payment may set the saved card. A renewal keeps the
    -- agreement it was charged on and only clears its failure count.
    if v_order.kind = 'initial' and nullif(p_customer_id, '') is not null
       and nullif(p_card_id, '') is not null and nullif(p_agreement_id, '') is not null then
      insert into public.tap_billing_agreements as a (
        user_id, tap_customer_id, tap_card_id, tap_agreement_id, billing_cycle,
        card_brand, card_last_four, card_exp_month, card_exp_year)
      values (v_order.user_id, p_customer_id, p_card_id, p_agreement_id, v_order.billing_cycle,
              v_card ->> 'brand', v_card ->> 'last_four',
              (v_card ->> 'exp_month')::smallint, (v_card ->> 'exp_year')::smallint)
      on conflict (user_id) do update set
        tap_customer_id = excluded.tap_customer_id,
        tap_card_id = excluded.tap_card_id,
        tap_agreement_id = excluded.tap_agreement_id,
        billing_cycle = excluded.billing_cycle,
        card_brand = excluded.card_brand,
        card_last_four = excluded.card_last_four,
        card_exp_month = excluded.card_exp_month,
        card_exp_year = excluded.card_exp_year,
        -- A new customer payment turns renewal back on.
        auto_renew = true,
        failed_attempts = 0,
        next_attempt_at = null,
        updated_at = pg_catalog.now();
    else
      update public.tap_billing_agreements as a
        set failed_attempts = 0, next_attempt_at = null, updated_at = pg_catalog.now()
        where a.user_id = v_order.user_id;
    end if;
    select a.* into v_agreement from public.tap_billing_agreements as a
      where a.user_id = v_order.user_id;
    v_renews := found and v_agreement.auto_renew;

    perform public.apply_subscription_provider_event(
      'tap', 'charge:' || p_charge_id, 'CHARGE_CAPTURED', pg_catalog.now(), v_order.user_id,
      v_key, 'plus_' || v_order.billing_cycle, v_order.billing_cycle,
      case when v_renews then 'active' else 'cancel_scheduled' end, v_renews,
      pg_catalog.now(), v_paid, null, v_environment, null);
    update public.tap_billing_orders as o
      set status = 'captured', tap_charge_id = p_charge_id,
          agreement_id = coalesce(v_agreement.id, o.agreement_id),
          updated_at = pg_catalog.now()
      where o.id = p_order;
    return 'captured';
  end if;

  if p_status in ('ABANDONED', 'CANCELLED', 'FAILED', 'DECLINED', 'RESTRICTED', 'VOID', 'TIMEDOUT') then
    update public.tap_billing_orders as o
      set status = 'failed', tap_charge_id = p_charge_id, updated_at = pg_catalog.now()
      where o.id = p_order;
    if v_order.kind = 'renewal' and v_order.agreement_id is not null then
      update public.tap_billing_agreements as a
        set failed_attempts = least(a.failed_attempts + 1, 3),
            next_attempt_at = pg_catalog.now() + interval '1 day',
            auto_renew = a.failed_attempts + 1 < 3 and a.auto_renew,
            updated_at = pg_catalog.now()
        where a.id = v_order.agreement_id
        returning a.* into v_agreement;
      v_grace := v_order.renewal_for + interval '3 days';
      perform public.apply_subscription_provider_event(
        'tap', 'charge:' || p_charge_id, 'RENEWAL_FAILED', pg_catalog.now(), v_order.user_id,
        v_key, 'plus_' || v_order.billing_cycle, v_order.billing_cycle,
        case when v_agreement.auto_renew then 'billing_issue' else 'expired' end,
        v_agreement.auto_renew, null, v_current, v_grace, v_environment, null);
    end if;
    return 'failed';
  end if;
  return 'pending';
end;
$function$;

-- ---------------------------------------------------------------------------
-- Tap: renewals, cancellation, refunds
-- ---------------------------------------------------------------------------

-- Claims due periods. Each period has at most one open attempt:
--   no attempt yet        -> attempt 1
--   last attempt failed   -> the next attempt
--   created, no charge id -> the same order again, so Tap's 24-hour idempotency key
--                            turns a lost response into the original charge
--   created for 23 hours  -> needs_review: the key is about to expire, so a person
--                            decides instead of risking a second charge
--   pending or captured   -> never charged again here
create function public.tap_claim_due_renewals(p_limit integer)
returns table (
  order_id uuid, user_id uuid, amount numeric, currency text,
  tap_customer_id text, tap_card_id text, tap_agreement_id text
)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_row record;
  v_order uuid;
  v_price numeric;
  v_last public.tap_billing_orders%rowtype;
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = 'PBP01', message = 'invalid_limit';
  end if;
  for v_row in
    select a.id as agreement_id, a.user_id as owner, a.billing_cycle, a.failed_attempts,
           a.tap_customer_id as customer, a.tap_card_id as card, a.tap_agreement_id as agreement,
           r.paid_through_at as period
    from public.tap_billing_agreements as a
    join public.subscription_provider_records as r
      on r.provider = 'tap' and r.provider_subscription_id = public.tap_subscription_key(a.user_id)
    where a.auto_renew
      and r.state in ('active', 'billing_issue')
      and r.paid_through_at <= pg_catalog.now() + interval '24 hours'
      and (a.next_attempt_at is null or a.next_attempt_at <= pg_catalog.now())
    order by r.paid_through_at
    limit p_limit
    for update of a skip locked
  loop
    v_order := null;
    v_price := public.tap_price(v_row.billing_cycle);
    select o.* into v_last from public.tap_billing_orders as o
      where o.agreement_id = v_row.agreement_id and o.kind = 'renewal'
        and o.renewal_for = v_row.period
      order by o.attempt desc limit 1;
    if not found or v_last.status = 'failed' then
      insert into public.tap_billing_orders (
        user_id, agreement_id, kind, billing_cycle, amount, renewal_for, attempt)
      values (v_row.owner, v_row.agreement_id, 'renewal', v_row.billing_cycle, v_price,
              v_row.period, case when v_last.id is null then 1 else v_last.attempt + 1 end)
      on conflict (agreement_id, renewal_for, attempt) where kind = 'renewal' do nothing
      returning id into v_order;
    elsif v_last.status = 'created' and v_last.tap_charge_id is null then
      if v_last.created_at > pg_catalog.now() - interval '23 hours' then
        v_order := v_last.id;
        v_price := v_last.amount;
      else
        update public.tap_billing_orders as o
          set status = 'needs_review', updated_at = pg_catalog.now()
          where o.id = v_last.id;
      end if;
    end if;
    -- A declined charge sets its own one-day delay in tap_settle_charge.
    update public.tap_billing_agreements as a
      set next_attempt_at = pg_catalog.now() + interval '1 hour', updated_at = pg_catalog.now()
      where a.id = v_row.agreement_id;
    if v_order is not null then
      order_id := v_order;
      user_id := v_row.owner;
      amount := v_price;
      currency := 'AED';
      tap_customer_id := v_row.customer;
      tap_card_id := v_row.card;
      tap_agreement_id := v_row.agreement;
      return next;
    end if;
  end loop;
end;
$function$;

-- Open charges whose webhook may have been missed. The claim stamp keeps
-- overlapping job runs from re-reading the same charge.
create function public.tap_claim_stale_charges(p_limit integer)
returns table (order_id uuid, tap_charge_id text)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception using errcode = 'PBP01', message = 'invalid_limit';
  end if;
  return query
  with due as (
    select o.id
    from public.tap_billing_orders as o
    where o.status = 'pending' and o.tap_charge_id is not null
      and o.updated_at < pg_catalog.now() - interval '10 minutes'
      and o.created_at > pg_catalog.now() - interval '14 days'
    order by o.updated_at
    limit p_limit
    for update of o skip locked
  )
  update public.tap_billing_orders as o
    set updated_at = pg_catalog.now()
  from due
  where o.id = due.id
  returning o.id, o.tap_charge_id;
end;
$function$;

-- Which account a charge belongs to, for a signed-in return from checkout.
create function public.tap_charge_owner(p_charge_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select o.user_id from public.tap_billing_orders as o where o.tap_charge_id = p_charge_id;
$function$;

-- Renewal off keeps Plus to the paid date; renewal on again is only possible
-- while that period is still running.
create function public.tap_set_auto_renew(p_user uuid, p_on boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_agreement public.tap_billing_agreements%rowtype;
  v_record public.subscription_provider_records%rowtype;
begin
  if p_user is null or p_on is null then
    raise exception using errcode = 'PBP01', message = 'invalid_request';
  end if;
  perform public.subscription_lock(p_user);
  select a.* into v_agreement from public.tap_billing_agreements as a
    where a.user_id = p_user for update;
  if not found then
    return 'no_agreement';
  end if;
  select r.* into v_record from public.subscription_provider_records as r
    where r.provider = 'tap' and r.provider_subscription_id = public.tap_subscription_key(p_user);
  if not found or v_record.state not in ('active', 'cancel_scheduled', 'billing_issue')
     or v_record.paid_through_at <= pg_catalog.now() then
    return 'not_active';
  end if;
  if v_agreement.auto_renew = p_on then
    return 'unchanged';
  end if;
  update public.tap_billing_agreements as a
    set auto_renew = p_on, failed_attempts = 0, next_attempt_at = null,
        updated_at = pg_catalog.now()
    where a.id = v_agreement.id;
  perform public.apply_subscription_provider_event(
    'tap', 'auto-renew:' || gen_random_uuid()::text,
    case when p_on then 'RENEWAL_ON' else 'RENEWAL_OFF' end, pg_catalog.now(), p_user,
    v_record.provider_subscription_id, v_record.product_id, v_record.billing_cycle,
    case when p_on then 'active' else 'cancel_scheduled' end, p_on,
    null, v_record.paid_through_at, null, v_record.environment, null);
  return case when p_on then 'renewal_on' else 'renewal_off' end;
end;
$function$;

-- A full refund of the newest paid period ends Plus. An older period's refund, or
-- a partial refund, is recorded and leaves the running period alone.
create function public.tap_record_refund(
  p_refund_id text, p_charge_id text, p_status text, p_amount numeric
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.tap_billing_orders%rowtype;
  v_record public.subscription_provider_records%rowtype;
begin
  if nullif(pg_catalog.btrim(p_refund_id), '') is null
     or nullif(pg_catalog.btrim(p_charge_id), '') is null or p_status is null then
    raise exception using errcode = 'PBP01', message = 'invalid_refund';
  end if;
  select o.* into v_order from public.tap_billing_orders as o
    where o.tap_charge_id = p_charge_id for update;
  if not found then
    return 'unknown_charge';
  end if;
  if p_status <> 'REFUNDED' then
    return 'pending';
  end if;
  if v_order.status = 'refunded' then
    return 'duplicate';
  end if;
  if p_amount is null or p_amount < v_order.amount then
    return 'partial_recorded';
  end if;
  update public.tap_billing_orders as o
    set status = 'refunded', updated_at = pg_catalog.now() where o.id = v_order.id;
  if v_order.user_id is null then
    return 'refunded';
  end if;
  perform public.subscription_lock(v_order.user_id);
  if exists (
    select 1 from public.tap_billing_orders as newer
    where newer.user_id = v_order.user_id and newer.status = 'captured'
      and newer.created_at > v_order.created_at
  ) then
    return 'older_period_refunded';
  end if;
  update public.tap_billing_agreements as a
    set auto_renew = false, updated_at = pg_catalog.now()
    where a.user_id = v_order.user_id;
  select r.* into v_record from public.subscription_provider_records as r
    where r.provider = 'tap'
      and r.provider_subscription_id = public.tap_subscription_key(v_order.user_id);
  if found then
    perform public.apply_subscription_provider_event(
      'tap', 'refund:' || p_refund_id, 'REFUNDED', pg_catalog.now(), v_order.user_id,
      v_record.provider_subscription_id, v_record.product_id, v_record.billing_cycle,
      'refunded', false, null, v_record.paid_through_at, null, v_record.environment, null);
  end if;
  return 'refunded';
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
    'public.tap_price(text)',
    'public.tap_subscription_key(uuid)',
    'public.tap_card_display(jsonb)'
  ] loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role', v_signature);
  end loop;
  foreach v_signature in array array[
    'public.subscription_sync_claim(uuid, integer)',
    'public.subscription_claim_reconcile_batch(integer)',
    'public.tap_create_order(uuid, text)',
    'public.tap_attach_charge(uuid, text)',
    'public.tap_settle_charge(uuid, text, text, numeric, text, boolean, text, text, text, jsonb)',
    'public.tap_claim_due_renewals(integer)',
    'public.tap_claim_stale_charges(integer)',
    'public.tap_charge_owner(text)',
    'public.tap_set_auto_renew(uuid, boolean)',
    'public.tap_record_refund(text, text, text, numeric)'
  ] loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated', v_signature);
    execute pg_catalog.format('grant execute on function %s to service_role', v_signature);
  end loop;
end;
$privileges$;
