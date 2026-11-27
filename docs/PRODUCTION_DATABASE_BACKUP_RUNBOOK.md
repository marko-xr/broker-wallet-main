# Production database backup and recovery

Status on 2026-11-26: **one encrypted logical backup exists** (record in section 9). It was decrypted with the
owner's saved passphrase and checked by counts against production. **A full restore into an isolated database has not
been performed yet**; that needs the owner's separate authorization.

Never restore anything over production while testing. Never put a dump in Git, a project upload, cloud storage that is
not encrypted and private, or a chat message.

## 1. The production project

| Item | Value |
|---|---|
| Project | `broker-wallet`, ref `rbvcnvqpdqrhywcgxkne`, region `ap-south-1`, organization `Nmo Digitil` |
| Evidence | `SupabaseConfig.productionProjectRef` and both Worker environments in `wrangler.toml` point at this ref |
| Staging | Shares this same project (there is no separate staging database) |
| Database | PostgreSQL 17.6, 24 MB |

## 2. Backup state (read on 2026-11-26)

`supabase backups list --project-ref rbvcnvqpdqrhywcgxkne` answered `backups: null`, `pitr_enabled: false`,
`walg_enabled: true`. There is no Supabase-managed recovery point to restore, and no point-in-time recovery.
Daily managed backups need a paid plan and PITR is a paid add-on; the plan tier is not readable from the CLI, so
confirm it in the dashboard (Organization settings > Billing). Managed backups also only cover the database.

## 3. Baseline to verify a backup against (aggregate counts, no personal data)

| Item | Production |
|---|---|
| Public tables / views / functions / RLS policies / triggers / types | 42 / 1 / 61 / 113 / 33 / 54 |
| Public tables without RLS | 0 |
| Migration history | 21 rows, `20260821000100` to `20261121090000` |
| Rows | public 515, auth 195 (5 users), storage 81, cron 16,811 (3 active jobs), net 360, realtime 97 |
| Extensions | citext, pg_cron, pg_net, pg_stat_statements, pg_trgm, pgcrypto, plpgsql, supabase_vault, uuid-ossp |
| Supabase Storage buckets | none |
| Vault secrets | 1 |
| Custom database roles | none |

Counts change with use: take them again (section 6 queries) right before each backup.

## 4. Creating the backup (Supabase CLI logical dump)

**Use `supabase/backup/backup_production.sh`.** It runs the five dumps below as one stream straight into GnuPG
(AES-256 with MDC integrity, S2K SHA-512 at the maximum count), so no unencrypted copy is written anywhere, then asks
for the passphrase again from the password manager and verifies the file with `verify_backup.mjs` (counts only).
Before it, write `baseline.json` from `supabase/backup/baseline.sql` into the work folder. The destination approved by
the owner is `F:\BrokerWallet\ProductionBackups\` (external SSD, exFAT, not disk-encrypted: the file encryption is the
protection). The manual commands below explain what the script does; never run them to an unencrypted location.

The CLI normally runs `pg_dump` in Docker. This machine has no Docker, so the CLI prints its own dump script
(`--dry-run`) and Git Bash runs it with the installed PostgreSQL 17 client tools. The script carries the CLI's
temporary login role: no database password is typed, shown or stored. The one fix: Windows `pg_dump` needs the full
flag name `--quote-all-identifiers`.

Prerequisites: the owner's `supabase` CLI login; a scratch folder linked to the project
(`supabase init && supabase link --project-ref rbvcnvqpdqrhywcgxkne`, never inside the repo); an **approved encrypted
destination** outside the repo and outside any synced folder (for example a BitLocker drive), with a second offline
copy.

In Git Bash, from the linked scratch folder:

```bash
export PATH="/c/Program Files/PostgreSQL/17/bin:$PATH"
OUT="/x/approved-encrypted-location/broker-wallet-$(date -u +%Y%m%dT%H%MZ)"   # owner-approved path
mkdir -p "$OUT"
FIX='s/--quote-all-identifier\b/--quote-all-identifiers/'
supabase db dump --linked --role-only --dry-run | sed "$FIX" | bash > "$OUT/roles.sql"
supabase db dump --linked --dry-run | sed "$FIX" | bash > "$OUT/schema.sql"
supabase db dump --linked --data-only --use-copy --dry-run | sed "$FIX" | bash > "$OUT/data.sql"
supabase db dump --linked --schema supabase_migrations --dry-run | sed "$FIX" | bash > "$OUT/history_schema.sql"
supabase db dump --linked --data-only --use-copy --schema supabase_migrations --dry-run | sed "$FIX" | bash > "$OUT/history_data.sql"
(cd "$OUT" && sha256sum *.sql > SHA256SUMS && wc -c *.sql)
```

Every file except `roles.sql` (settings only: there are no custom roles) must be non-empty. **Never print the dry-run
script itself:** it contains the temporary login password.

What each file holds:

| File | Content | Sensitivity |
|---|---|---|
| `roles.sql` | Settings on Supabase's built-in roles | Low |
| `schema.sql` | Public schema: tables, functions, triggers, RLS policies, grants, types, realtime publication membership | Low |
| `data.sql` | All rows of `public`, `auth` (users, identities, password hashes, sessions, refresh tokens), `storage` metadata, `cron` jobs and run history, `net` | **Highest: personal data and auth secrets.** Encrypted storage only |
| `history_*.sql` | `supabase_migrations.schema_migrations`, which the data dump excludes | Contains the e-mail address that applied some migrations |

## 5. Not in the database dump: preserve separately

| Component | Where it lives | Action |
|---|---|---|
| Media, profile images, Toolkit documents | Cloudflare R2 (`media_objects` holds 117 rows that point at them) | Separate R2 backup task |
| Supabase Storage objects | None exist (no buckets) | Nothing to do today |
| Project triggers on `auth.users` (3): `on_auth_user_created` (creates the profile), `on_auth_user_identity_updated`, `guard_pending_phone_change` | `auth` schema, which the CLI schema dump excludes (found 2026-11-27) | Re-create them after a restore from migrations `20260821000100`, `20260822000400`, `20260911181112`, or from a structure-only dump of `auth`. Without them new sign-ups get no profile |
| Scheduled jobs (`cron.job`, 3 jobs) | Extension table: `pg_dump --data-only` never includes it | Identical to `supabase/deploy/notifications_n2_schedule.sql` (MD5 of every command and the schedules checked 2026-11-26 with `supabase/backup/cron_jobs.sql`): re-run that file after a restore. Cron run history and the pg_net queue are not kept |
| Vault secret `bw_push_dispatch_url` (the only one) | `vault` schema, excluded by the CLI | Keep its value in the password manager; re-create it as `notifications_n2_schedule.sql` describes before scheduling the jobs |
| Edge Function secrets, Worker secrets, API keys | Supabase and Cloudflare dashboards | Keep in the password manager. A new project gets new keys |
| Auth settings (providers, SMS, SMTP, redirect URLs) | Supabase dashboard | Record them; a new project starts empty |
| Legacy quota data | Firebase Firestore | Separate system, not covered |
| Edge Function code, migrations | This repository | Covered by Git |

## 6. Verifying a backup

1. `sha256sum -c SHA256SUMS` in the backup folder.
2. Restore into an **isolated** target, never production. A new temporary Supabase project is the faithful target: it
   already has `auth`, `storage`, the extensions and the `supabase_realtime` publication. In Git Bash:

```bash
psql --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql --file schema.sql \
  --command 'SET session_replication_role = replica' --file data.sql \
  --dbname "$ISOLATED_DB_URL"      # typed by the owner, never echoed
psql --variable ON_ERROR_STOP=1 --file history_schema.sql --file history_data.sql --dbname "$ISOLATED_DB_URL"
```

   A file made by `backup_production.sh` is one stream in that order, with the replica setting already before the
   data, so it restores in one go without any decrypted copy on disk:
   `gpg --decrypt <file> | psql --single-transaction --variable ON_ERROR_STOP=1 --dbname "$ISOLATED_DB_URL"`.
   Then re-create the Vault secret and run `supabase/deploy/notifications_n2_schedule.sql` (section 5).
3. Run the counts of section 3 on the restored copy and compare. Delete the temporary project afterwards.

A plain local PostgreSQL can check the schema only. Rehearsal on 2026-11-26: PostgreSQL 17.12 on loopback with
stand-ins for the Supabase roles, `extensions`, `auth.users` and `auth.uid()`. It produced 9 errors, all expected
outside Supabase (6 platform extensions not installed locally, 3 `supabase_realtime` publication additions), and
42 / 1 / 61 / 113 / 33 / 54 objects, 0 tables without RLS and 21 migration rows: identical to production. The
rehearsal files were deleted after the comparison.

## 7. Recovering in a real incident

1. Stop writes: put the Worker into maintenance and pause the cron jobs if they would act on bad data.
2. Create a new Supabase project in the same region; restore as in section 6 step 2; re-create the Vault secret,
   Edge Function secrets and auth settings from section 5.
3. Verify against the counts taken with the backup.
4. Point the app builds and both Worker environments at the new project (`SUPABASE_URL`, keys, Worker secrets), or,
   only by explicit owner decision, restore into the existing project. Data written after the dump is lost: the
   recovery point is the dump time.

## 8. Before any hosted migration

Take a fresh backup with section 4, verify it with section 6, and record its time and SHA-256 sums (not its contents)
in `docs/CURRENT_CHECKPOINT.md`. Until a paid plan provides daily backups, repeat this before every hosted change.

## 9. Backup record

| Field | 2026-11-26 backup |
|---|---|
| Folder | `F:\BrokerWallet\ProductionBackups\20261126T194340Z\` (external SSD "Marko SSD") |
| File | `broker-wallet-production-20261126T194340Z.sql.gpg`, 142,461 bytes, plus `SHA256SUMS` and `MANIFEST.txt` |
| SHA-256 (encrypted file) | `54143577e959e02eed766e4b232777a2da683c91bd6674c5b8ae35e8ac44a9f9` (`sha256sum -c` read back from the SSD: OK) |
| SHA-256 (decrypted stream) | `d0fdb50093752ed3076bad30eb7b662610c706c6560d0b48935945bb4fb7ecf7`, equal at encryption and after decryption |
| Encryption | GnuPG 2.4.5 symmetric: AES-256, MDC, S2K iterated+salted SHA-512, count 65011712 |
| Passphrase | Chosen and typed by the owner, kept in the owner's password manager with an offline copy; never on the SSD, in Git, in a log or seen by the agent |
| Decryption check | Passed with the passphrase pasted from the password manager; GnuPG integrity check passed |
| Content check | Schema 42 tables (RLS on all), 113 policies, 61 functions, 33 triggers, 1 view; rows public 515, auth 110, storage 0; every table equal to production at 19:42 UTC; 21 migration rows; parts in order |
| Not in the file | `cron`/`net` extension tables (jobs reproducible from the repo, see section 5), Vault secret, R2 objects, external secrets and settings, Firestore |
| Isolated restore | **Not performed** (needs the owner's authorization of a target) |

The verifier's first run reported FAIL only because its baseline listed the four `cron`/`net` extension tables, which
`pg_dump --data-only` never includes; `baseline.sql` now leaves them out, and the same counts re-evaluated give PASS.

## 10. Full restore test (Task 01B): plan awaiting the owner's approval

**Done without customer data (2026-11-27):** a throwaway PostgreSQL 17.12 on loopback, with production's exact
`auth`/`storage` structure, received a live structure-only stream (roles, schema, migration history). Errors: only
the 4 unavailable extensions (`pg_cron`, `pg_net`, `supabase_vault`, `pgcrypto`; nothing restored uses `pgcrypto`).
Result: 42 public tables, 21 migration rows, the 3 `auth.users` triggers, and the 3 functions the cron jobs call. The
throwaway cluster was then deleted. **The real data has not been restored anywhere.**

**Chosen target: a temporary hosted Supabase project.** Not created; it needs the owner's separate approval.

| Topic | Plan |
|---|---|
| Cost | Plan tier of `Nmo Digitil` is not readable from the CLI (no managed backups suggests Free). Free allows 2 active projects across all the owner's organizations; `INTLAQ HUB` and `broker-wallet` are active (`Emaratik Commerce` is paused and does not count), so a third needs either the Pro plan ($25/month; the extra Micro project then costs $0.01344 per started hour, about $0.03 for a 2-hour test) or pausing another project. Prices from supabase.com, read 2026-11-27 |
| Project | `bw-recovery-test-<date>`, region `ap-south-1`, Micro compute, database password generated in the password manager and deleted after |
| Isolation | Data API disabled; Auth: sign-ups off, email and phone providers off (no login, no e-mail, no SMS); no SMTP, no auth hooks; network restrictions to the owner's current IP; SSL enforced, connection with `sslmode=verify-full` and the project's CA certificate; no Edge Functions deployed; no Vault secret, push, payment or service-role secret copied; nothing in the app or Workers points at it |
| No external side effects | The restore stream is filtered so `pg_cron` and `pg_net` are never created; `cron.job` is not in the backup and `notifications_n2_schedule.sql` is not run; no public trigger or function calls `net.*`; data loads with `session_replication_role = replica`, so no trigger fires |
| No plaintext at rest | The owner runs the restore in the Terminal panel and types the backup passphrase and the recovery database password (never echoed): `gpg --decrypt` streams through `psql` over TLS to the session pooler (IPv4). Decrypted data exists only in memory and in the project's AES-256-encrypted storage. Errors are written in terse mode with quoted values masked |
| Order | Pre-check the empty project's `auth` structure against production's (structure only); restore the stream; re-create the 3 `auth.users` triggers; count-only checks |
| Verification | Per-table rows against `baseline.json`; auth counts; RLS on all 42 tables, 113 policies, 61 functions, 33 + 3 triggers, 1 view; 21 migrations; foreign-key orphan counts; per-table content hashes (MD5 only) compared with production read-only, explaining any table changed since the backup; every psql error classified |
| Removal | The owner deletes the project (Settings > General > Delete project): Supabase states that all data and backups are permanently removed and billing stops. Then delete the CA certificate and the recovery password, confirm with `supabase projects list`, and downgrade the plan if it was raised only for this test |
| Time | About 30 to 60 minutes including setup; the restore itself takes under a minute (24 MB database) |
