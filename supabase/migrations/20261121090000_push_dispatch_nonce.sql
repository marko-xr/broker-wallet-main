-- Notifications N3: single-use nonce for the scheduler -> push-dispatch call.
--
-- Why: Supabase's pg_net keeps every queued request, headers included, in
-- net.http_request_queue, which the platform lets PUBLIC (anon, authenticated)
-- read and change, and which postgres cannot revoke (supabase_admin is the
-- grantor; proven with a rollback-only probe on 2026-11-21). A long-lived
-- secret must therefore never be sent through pg_net.
--
-- Instead, each scheduled call carries a fresh random nonce:
--   * issue_push_dispatch_nonce()  postgres only (the pg_cron job): makes a
--     256-bit random value, stores ONLY its sha256 with a 2-minute expiry,
--     returns the value for the request header.
--   * consume_push_dispatch_nonce(text)  service_role only (push-dispatch):
--     deletes the matching unexpired hash and returns true exactly once.
-- A leaked nonce allows at most one dispatch run, and a run only delivers
-- reminders that are already due to their own owners' active devices.
--
-- No BEGIN/COMMIT: applied by the reviewed single-transaction apply file and
-- included by the rollback-only validation.

create table public.push_dispatch_nonces (
  nonce_hash text primary key,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint push_dispatch_nonces_hash_shape check (nonce_hash ~ '^[0-9a-f]{64}$')
);
create index push_dispatch_nonces_expires_idx on public.push_dispatch_nonces (expires_at);

alter table public.push_dispatch_nonces enable row level security;
revoke all on public.push_dispatch_nonces from public, anon, authenticated, service_role;
-- No policy and no grant: only the two SECURITY DEFINER functions below.

create function public.issue_push_dispatch_nonce()
returns text
language plpgsql volatile security definer set search_path = ''
as $function$
declare
  v_nonce text;
begin
  -- 2 x gen_random_uuid() = 244 bits from the server's strong random source.
  v_nonce := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  delete from public.push_dispatch_nonces where expires_at < now();
  if (select count(*) from public.push_dispatch_nonces) >= 100 then
    raise exception using errcode = '54000', message = 'too_many_open_nonces';
  end if;
  insert into public.push_dispatch_nonces (nonce_hash, expires_at)
  values (encode(sha256(convert_to(v_nonce, 'UTF8')), 'hex'), now() + interval '2 minutes');
  return v_nonce;
end;
$function$;
revoke all on function public.issue_push_dispatch_nonce() from public, anon, authenticated, service_role;

create function public.consume_push_dispatch_nonce(p_nonce text)
returns boolean
language plpgsql volatile security definer set search_path = ''
as $function$
begin
  if p_nonce is null or p_nonce !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  delete from public.push_dispatch_nonces n
   where n.nonce_hash = encode(sha256(convert_to(p_nonce, 'UTF8')), 'hex')
     and n.expires_at >= now();
  return found;
end;
$function$;
revoke all on function public.consume_push_dispatch_nonce(text) from public, anon, authenticated;
grant execute on function public.consume_push_dispatch_nonce(text) to service_role;
