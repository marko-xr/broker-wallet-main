-- Broker Wallet Stage 2 performance hardening.
--
-- 1) Supabase recommends wrapping auth.uid() in a scalar SELECT inside RLS
--    policies so PostgreSQL can evaluate it once per statement instead of once
--    per row. This migration preserves the exact policy semantics while
--    changing only that execution form.
-- 2) Adds covering indexes for every foreign key currently reported by the
--    Supabase performance advisor as unindexed.
-- 3) Keeps existing application/search indexes. Fresh databases naturally
--    report those as unused until real workloads exist, so they are not removed.

begin;

-- Optimize ownership helper internals while retaining SECURITY INVOKER.
create or replace function public.owns_request(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.requests r
    where r.id = row_id
      and r.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_offer(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.offers o
    where o.id = row_id
      and o.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_owner_record(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.owners o
    where o.id = row_id
      and o.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_office(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.offices o
    where o.id = row_id
      and o.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_broker(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.brokers b
    where b.id = row_id
      and b.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_watchman(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.watchmen w
    where w.id = row_id
      and w.owner_id = (select auth.uid())
  );
$$;

create or replace function public.owns_quotation(row_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists(
    select 1
    from public.quotations q
    where q.id = row_id
      and q.owner_id = (select auth.uid())
  );
$$;

-- Optimize direct auth.uid() usage in RLS policies.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists revenuecat_entitlements_select_own on public.revenuecat_entitlements;
create policy revenuecat_entitlements_select_own on public.revenuecat_entitlements for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists usage_counters_select_own on public.usage_counters;
create policy usage_counters_select_own on public.usage_counters for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists requests_select_own on public.requests;
create policy requests_select_own on public.requests for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists requests_insert_own on public.requests;
create policy requests_insert_own on public.requests for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists requests_update_own on public.requests;
create policy requests_update_own on public.requests for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists offers_select_own on public.offers;
create policy offers_select_own on public.offers for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists offers_insert_own on public.offers;
create policy offers_insert_own on public.offers for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists offers_update_own on public.offers;
create policy offers_update_own on public.offers for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists owners_select_own on public.owners;
create policy owners_select_own on public.owners for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists owners_insert_own on public.owners;
create policy owners_insert_own on public.owners for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists owners_update_own on public.owners;
create policy owners_update_own on public.owners for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists offices_select_own on public.offices;
create policy offices_select_own on public.offices for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists offices_insert_own on public.offices;
create policy offices_insert_own on public.offices for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists offices_update_own on public.offices;
create policy offices_update_own on public.offices for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists brokers_select_own on public.brokers;
create policy brokers_select_own on public.brokers for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists brokers_insert_own on public.brokers;
create policy brokers_insert_own on public.brokers for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists brokers_update_own on public.brokers;
create policy brokers_update_own on public.brokers for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists watchmen_select_own on public.watchmen;
create policy watchmen_select_own on public.watchmen for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists watchmen_insert_own on public.watchmen;
create policy watchmen_insert_own on public.watchmen for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists watchmen_update_own on public.watchmen;
create policy watchmen_update_own on public.watchmen for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists quotations_select_own on public.quotations;
create policy quotations_select_own on public.quotations for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists quotations_insert_own on public.quotations;
create policy quotations_insert_own on public.quotations for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists quotations_update_own on public.quotations;
create policy quotations_update_own on public.quotations for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists media_objects_select_own on public.media_objects;
create policy media_objects_select_own on public.media_objects for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists profile_media_select_own on public.profile_media;
create policy profile_media_select_own on public.profile_media for select to authenticated using (profile_id = (select auth.uid()));

drop policy if exists favorite_offers_select_own on public.favorite_offers;
create policy favorite_offers_select_own on public.favorite_offers for select to authenticated using (owner_id = (select auth.uid()) and public.owns_offer(target_id));

drop policy if exists favorite_offers_insert_own on public.favorite_offers;
create policy favorite_offers_insert_own on public.favorite_offers for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_offer(target_id));

drop policy if exists favorite_offers_delete_own on public.favorite_offers;
create policy favorite_offers_delete_own on public.favorite_offers for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_offer(target_id));

drop policy if exists favorite_requests_select_own on public.favorite_requests;
create policy favorite_requests_select_own on public.favorite_requests for select to authenticated using (owner_id = (select auth.uid()) and public.owns_request(target_id));

drop policy if exists favorite_requests_insert_own on public.favorite_requests;
create policy favorite_requests_insert_own on public.favorite_requests for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_request(target_id));

drop policy if exists favorite_requests_delete_own on public.favorite_requests;
create policy favorite_requests_delete_own on public.favorite_requests for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_request(target_id));

drop policy if exists favorite_owners_select_own on public.favorite_owners;
create policy favorite_owners_select_own on public.favorite_owners for select to authenticated using (owner_id = (select auth.uid()) and public.owns_owner_record(target_id));

drop policy if exists favorite_owners_insert_own on public.favorite_owners;
create policy favorite_owners_insert_own on public.favorite_owners for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_owner_record(target_id));

drop policy if exists favorite_owners_delete_own on public.favorite_owners;
create policy favorite_owners_delete_own on public.favorite_owners for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_owner_record(target_id));

drop policy if exists favorite_offices_select_own on public.favorite_offices;
create policy favorite_offices_select_own on public.favorite_offices for select to authenticated using (owner_id = (select auth.uid()) and public.owns_office(target_id));

drop policy if exists favorite_offices_insert_own on public.favorite_offices;
create policy favorite_offices_insert_own on public.favorite_offices for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_office(target_id));

drop policy if exists favorite_offices_delete_own on public.favorite_offices;
create policy favorite_offices_delete_own on public.favorite_offices for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_office(target_id));

drop policy if exists favorite_brokers_select_own on public.favorite_brokers;
create policy favorite_brokers_select_own on public.favorite_brokers for select to authenticated using (owner_id = (select auth.uid()) and public.owns_broker(target_id));

drop policy if exists favorite_brokers_insert_own on public.favorite_brokers;
create policy favorite_brokers_insert_own on public.favorite_brokers for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_broker(target_id));

drop policy if exists favorite_brokers_delete_own on public.favorite_brokers;
create policy favorite_brokers_delete_own on public.favorite_brokers for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_broker(target_id));

drop policy if exists favorite_watchmen_select_own on public.favorite_watchmen;
create policy favorite_watchmen_select_own on public.favorite_watchmen for select to authenticated using (owner_id = (select auth.uid()) and public.owns_watchman(target_id));

drop policy if exists favorite_watchmen_insert_own on public.favorite_watchmen;
create policy favorite_watchmen_insert_own on public.favorite_watchmen for insert to authenticated with check (owner_id = (select auth.uid()) and public.owns_watchman(target_id));

drop policy if exists favorite_watchmen_delete_own on public.favorite_watchmen;
create policy favorite_watchmen_delete_own on public.favorite_watchmen for delete to authenticated using (owner_id = (select auth.uid()) and public.owns_watchman(target_id));

drop policy if exists feedback_select_own on public.feedback;
create policy feedback_select_own on public.feedback for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists feedback_insert_own on public.feedback;
create policy feedback_insert_own on public.feedback for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications for select to authenticated using (recipient_id = (select auth.uid()));

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications for delete to authenticated using (recipient_id = (select auth.uid()));

-- Cover foreign keys identified by the Supabase database advisor.
create index if not exists audit_logs_actor_idx on public.audit_logs (actor_id);
create index if not exists feedback_owner_idx on public.feedback (owner_id);
create index if not exists notifications_sender_user_idx on public.notifications (sender_user_id);
create index if not exists offer_media_media_idx on public.offer_media (media_id);
create index if not exists owner_media_media_idx on public.owner_media (media_id);
create index if not exists profile_media_media_idx on public.profile_media (media_id);
create index if not exists profiles_profile_media_idx on public.profiles (profile_media_id);
create index if not exists quotation_media_media_idx on public.quotation_media (media_id);
create index if not exists quotations_office_logo_media_idx on public.quotations (office_logo_media_id);
create index if not exists quotations_pdf_media_idx on public.quotations (pdf_media_id);

commit;
