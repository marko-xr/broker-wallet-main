-- Broker Wallet Stage 2 security hardening.
--
-- Supabase's database advisor flags SECURITY DEFINER functions that are
-- executable by authenticated users. The ownership helpers below do not need
-- definer privileges: the parent tables already have owner-scoped RLS policies,
-- and authenticated users have the SELECT privileges required for those checks.
-- Running the helpers as SECURITY INVOKER therefore preserves the intended
-- ownership semantics while removing an unnecessary privilege boundary.

begin;

alter function public.owns_request(uuid) security invoker;
alter function public.owns_offer(uuid) security invoker;
alter function public.owns_owner_record(uuid) security invoker;
alter function public.owns_office(uuid) security invoker;
alter function public.owns_broker(uuid) security invoker;
alter function public.owns_watchman(uuid) security invoker;
alter function public.owns_quotation(uuid) security invoker;

comment on function public.owns_request(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_offer(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_owner_record(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_office(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_broker(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_watchman(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';
comment on function public.owns_quotation(uuid) is
  'RLS ownership helper. SECURITY INVOKER is intentional; parent-table RLS remains authoritative.';

commit;
