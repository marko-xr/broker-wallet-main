-- SELECT-ONLY. Run before applying 20261123100000_subscription_entitlements_quotas.sql.
-- Reports how many accounts the migration would make read-only, per section, using
-- the same baseline it applies. It prints counts only: no ids, names or content.
--   psql -X -v ON_ERROR_STOP=1 -f supabase/validation/subscription_quota_preflight.sql
\set ON_ERROR_STOP on
begin transaction read only;

with created as (
  select owner_id, 'requests'::public.quota_section as section from public.requests
  union all select owner_id, 'offers' from public.offers
  union all select owner_id, 'owners' from public.owners
  union all select owner_id, 'offices' from public.offices
  union all select owner_id, 'brokers' from public.brokers
  union all select owner_id, 'watchmen' from public.watchmen
  union all select owner_id, 'quotations' from public.quotations
  union all
  select owner_id, document_type::public.quota_section
  from public.toolkit_documents
  where status in ('ready', 'pending_delete', 'deleted')
),
per_account as (
  select owner_id, section, count(*) as total from created group by owner_id, section
)
select section,
       count(*) as accounts_with_rows,
       count(*) filter (where total > 5) as accounts_over_five,
       max(total) as highest_count
from per_account
group by section
order by section;

with created as (
  select owner_id, 'requests' as section from public.requests
  union all select owner_id, 'offers' from public.offers
  union all select owner_id, 'owners' from public.owners
  union all select owner_id, 'offices' from public.offices
  union all select owner_id, 'brokers' from public.brokers
  union all select owner_id, 'watchmen' from public.watchmen
  union all select owner_id, 'quotations' from public.quotations
  union all
  select owner_id, document_type
  from public.toolkit_documents
  where status in ('ready', 'pending_delete', 'deleted')
),
over_limit as (
  select owner_id from created group by owner_id, section having count(*) > 5
)
select (select count(distinct owner_id) from over_limit) as accounts_that_become_read_only,
       (select count(*) from public.profiles) as accounts_total;

rollback;
