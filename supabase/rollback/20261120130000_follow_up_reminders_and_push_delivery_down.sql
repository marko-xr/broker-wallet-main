-- RECOVERY ONLY. Undoes 20261120130000_follow_up_reminders_and_push_delivery
-- and restores the exact previous schema. Run only with the owner's approval,
-- as postgres, in one transaction.
--
-- What it removes (data created after the apply is lost with its objects):
--   * every follow-up reminder and every push delivery job (both tables);
--   * the 9 functions the migration added;
--   * notifications.event_key and push_devices.session_id with their
--     constraints and indexes.
-- Inbox rows already created stay in public.notifications (without their
-- event key). Device rows stay in public.push_devices (without session).
-- What it restores: the two indexes the migration replaced, with the exact
-- definitions read from production on 2026-11-21, and the migration-history
-- entry is removed so the migration can be applied again later.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $preflight$
begin
  if current_user <> 'postgres'
     or to_regclass('public.follow_up_reminders') is null
     or to_regclass('public.notification_delivery_jobs') is null then
    raise exception 'N2 recovery preflight failed: the migration is not applied';
  end if;
end;
$preflight$;

drop function if exists public.prune_push_delivery_jobs();
drop function if exists public.complete_push_delivery_job(uuid, text, text, text, uuid, integer);
drop function if exists public.claim_push_delivery_jobs(integer, integer);
drop function if exists public.fire_due_follow_up_reminders(integer);
drop function if exists public.unregister_push_device(text);
drop function if exists public.register_push_device(text, text, text);
drop function if exists public.cancel_follow_up_reminder(text, uuid);
drop function if exists public.set_follow_up_reminder(text, uuid, timestamptz);
drop function if exists public.notification_push_allowed(uuid, text);

drop table if exists public.notification_delivery_jobs;
drop table if exists public.follow_up_reminders;

drop index if exists public.push_devices_owner_session_idx;
alter table public.push_devices drop constraint if exists push_devices_platform_valid;
alter table public.push_devices drop constraint if exists push_devices_locale_valid;
alter table public.push_devices drop column if exists session_id;
create index if not exists push_devices_owner_idx on public.push_devices using btree (owner_id);

alter table public.notifications drop constraint if exists notifications_category_offered;
drop index if exists public.notifications_recipient_created_id_idx;
drop index if exists public.notifications_recipient_event_key_uidx;
alter table public.notifications drop constraint if exists notifications_event_key_shape;
alter table public.notifications drop column if exists event_key;
create index if not exists notifications_recipient_created_idx
  on public.notifications using btree (recipient_id, created_at desc);

delete from supabase_migrations.schema_migrations where version = '20261120130000';

commit;
