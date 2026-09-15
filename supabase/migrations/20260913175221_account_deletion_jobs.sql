-- Server-owned record of an account deletion that outlives the account.
--
-- Deleting `auth.users` cascades through `public.profiles` and removes every
-- row that names the account, including `media_objects`. Two things must still
-- happen after that point, and neither can be authorized by the deleted
-- account's own session, which Supabase Auth no longer accepts:
--
--   1. Upload quarantine. While a deletion is in progress the media Worker must
--      not issue a signed R2 PUT URL for the account. The Worker checks this
--      table immediately before signing.
--   2. Deferred R2 finalization. A signed PUT URL issued before the quarantine
--      began stays valid for its TTL and can create an object after the account
--      is gone. The Worker's scheduled finalizer sweeps `profiles/<user_id>/`
--      in `bucket` once `cleanup_not_before` has passed, by which time no URL
--      for that prefix can still be valid.
--
-- The row is the only server-side authority for that cleanup: `user_id` comes
-- from a Supabase-verified session when the row is created, never from a
-- client afterwards, and the R2 location is derived from `bucket` and
-- `user_id`.
--
-- `user_id` deliberately has NO foreign key. A foreign key to `auth.users` or
-- `public.profiles` would either block the account deletion or cascade this row
-- away with it, which is exactly what the row exists to survive.
--
-- `bucket` scopes the job to the Worker that created it. A finalizer only acts
-- on jobs for its own bucket, so a staging Worker and the production Worker can
-- never finalize each other's jobs.
--
-- The row holds no email, name, phone, token, password, object key or URL. It
-- is deleted when finalization completes, and when a deletion is abandoned
-- before the account was deleted.
--
-- Access: service_role only (the media Worker's server secret). anon and
-- authenticated have no privileges and RLS is enabled with no policies, so the
-- table is invisible to every client session even if a grant were added by
-- mistake.
--
-- Lifecycle:
--   quarantined          uploads blocked; R2 cleanup running; auth user exists
--   auth_delete_pending  set immediately before the Supabase Auth admin delete
--   auth_deleted         auth user confirmed gone; awaiting finalization
--   cleanup_failed       a finalization attempt failed; retried by the finalizer
-- (completed or abandoned jobs are deleted, not kept in a terminal state)
--
-- `cleanup_not_before` has no default and is NULL until the finalizer stamps
-- it, on its own Cloudflare clock, the first time it reads the job as
-- `auth_deleted` / `cleanup_failed`: stamp time + 300 s maximum PUT URL lifetime
-- + 60 s bound between the Worker's quarantine check and signing + 120 s safety
-- margin. The database clock takes no part in that guarantee. The
-- `cleanup_not_before >= created_at` check is only a sanity guard against a
-- corrupt stamp.

begin;

create table public.account_deletion_jobs (
  user_id uuid primary key,
  bucket text not null,
  status text not null default 'quarantined',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  auth_deleted_at timestamptz,
  cleanup_not_before timestamptz,
  cleanup_attempts integer not null default 0,
  last_error_code text,
  constraint account_deletion_jobs_bucket_nonempty
    check (btrim(bucket) <> ''),
  constraint account_deletion_jobs_status_valid
    check (status in ('quarantined', 'auth_delete_pending', 'auth_deleted', 'cleanup_failed')),
  constraint account_deletion_jobs_auth_deleted_consistent
    check ((status in ('auth_deleted', 'cleanup_failed')) = (auth_deleted_at is not null)),
  constraint account_deletion_jobs_stamp_only_after_auth_delete
    check (cleanup_not_before is null or status in ('auth_deleted', 'cleanup_failed')),
  constraint account_deletion_jobs_stamp_sane
    check (cleanup_not_before is null or cleanup_not_before >= created_at),
  constraint account_deletion_jobs_attempts_nonnegative
    check (cleanup_attempts >= 0),
  constraint account_deletion_jobs_error_code_format
    check (last_error_code is null or last_error_code ~ '^[a-z_]{1,64}$')
);

create index account_deletion_jobs_finalizer_idx
  on public.account_deletion_jobs (bucket, status, cleanup_not_before);

create index account_deletion_jobs_reconcile_idx
  on public.account_deletion_jobs (bucket, status, updated_at);

create trigger account_deletion_jobs_updated_at
  before update on public.account_deletion_jobs
  for each row execute function public.set_updated_at();

alter table public.account_deletion_jobs enable row level security;

revoke all on table public.account_deletion_jobs from public;
revoke all on table public.account_deletion_jobs from anon;
revoke all on table public.account_deletion_jobs from authenticated;
grant select, insert, update, delete on table public.account_deletion_jobs to service_role;

commit;
