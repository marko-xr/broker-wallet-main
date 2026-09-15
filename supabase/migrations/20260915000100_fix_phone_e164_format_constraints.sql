-- The `phone_e164_format` CHECK constraint on all seven tables that carry a
-- `phone_e164` column was defined in the baseline with an over-escaped
-- regex literal: `'^\\+[1-9][0-9]{6,14}$'`. Postgres string literals do not
-- treat backslash as an escape character (standard_conforming_strings is on
-- by default), so `\\` in that literal is two literal backslash characters,
-- not one. The regex Postgres actually evaluates is therefore
-- `^\\+[1-9][0-9]{6,14}$`: start of string, one-or-more literal backslashes,
-- then the digits — which requires the value to start with a backslash, not
-- a plus sign. No valid E.164 number (e.g. `+971501234567`) can ever satisfy
-- it, which blocks every insert/update that populates `phone_e164`.
--
-- The fix uses a bracket expression, `[+]`, to match a literal plus sign
-- with no backslash escaping involved at all, avoiding the ambiguity that
-- caused the original bug.
--
-- This migration only replaces these seven CHECK constraints. It does not
-- touch RLS, grants, triggers, columns, data, ownership, indexes, foreign
-- keys or any other CHECK constraint. Verified on hosted Supabase that all
-- seven tables currently have zero non-null `phone_e164` rows, so no backfill
-- or data migration is required.

begin;

alter table public.profiles drop constraint profiles_phone_e164_format;
alter table public.profiles
  add constraint profiles_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.requests drop constraint requests_phone_e164_format;
alter table public.requests
  add constraint requests_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.offers drop constraint offers_phone_e164_format;
alter table public.offers
  add constraint offers_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.owners drop constraint owners_phone_e164_format;
alter table public.owners
  add constraint owners_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.offices drop constraint offices_phone_e164_format;
alter table public.offices
  add constraint offices_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.brokers drop constraint brokers_phone_e164_format;
alter table public.brokers
  add constraint brokers_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

alter table public.watchmen drop constraint watchmen_phone_e164_format;
alter table public.watchmen
  add constraint watchmen_phone_e164_format
  check (phone_e164 is null or phone_e164 ~ '^[+][1-9][0-9]{6,14}$');

commit;
