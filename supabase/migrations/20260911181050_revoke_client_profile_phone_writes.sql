-- The profile phone columns are a mirror of Supabase Auth identity, not
-- client-editable profile data.
--
-- `public.sync_auth_identity_to_profile()` (SECURITY DEFINER, owned by
-- postgres) copies `auth.users.phone` into `phone_number`, derives
-- `phone_e164`, and derives `is_phone_verified` from `phone_confirmed_at`.
-- While clients could also write `phone_number` / `phone_e164` directly, a
-- profile could show a number that Supabase Auth never confirmed, and a stale
-- client copy could overwrite a freshly confirmed one. Phone changes now go
-- through Supabase Auth's own verified phone-change flow only.
--
-- The baseline grants UPDATE column by column after revoking everything from
-- anon and authenticated, so revoking these two columns leaves exactly
-- `name` and `preferences` client-writable. SELECT is unchanged: the app reads
-- its own profile's phone. `is_phone_verified` was never client-writable.
--
-- Trusted writers are unaffected: the sync trigger runs as its owner
-- (postgres), and service_role keeps its privileges.

begin;

revoke update (phone_number, phone_e164) on public.profiles from authenticated;
revoke update (phone_number, phone_e164) on public.profiles from anon;

commit;
