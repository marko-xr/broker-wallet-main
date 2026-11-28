# Broker Wallet documentation map

One topic, one source of truth. When two documents disagree, the one named here for that topic wins; fix the other.

## Read first

| File | Owns |
|---|---|
| `AGENTS.md` | Rules for every agent: architecture, safety, Git, approvals, reporting |
| `CLAUDE.md` | Claude-specific pointers and known tool traps |
| `docs/CURRENT_CHECKPOINT.md` | **Current status** of every feature, the Git map, NOW / NEXT |

## Durable references

| File | Owns |
|---|---|
| `docs/PROJECT_STATE.md` | How the verified behaviour works (auth, recovery, deletion, media) and its verification history |
| `docs/DECISIONS.md` | Durable decisions, including security decisions; superseded ones stay, marked with what replaced them |
| `docs/PHONE_ACCOUNT_SECURITY_DESIGN.md` | Phone account design (Model X) |
| `docs/GOOGLE_SIGN_IN_ANDROID.md` | Google sign-in on Android: design, SDK choice, owner setup, device acceptance, gaps |
| `docs/GOOGLE_SIGN_IN_IOS.md` | Google sign-in on iOS: native client ID / URL scheme setup, nonce constraint, owner actions |
| `docs/NOTIFICATIONS_PRODUCTION_PLAN.md` | Notifications design, hosted runbook, iOS/APNs checklist |
| `docs/SUBSCRIPTION_PRODUCTION_RUNBOOK.md` | Subscriptions and payments release procedure, configuration, rollback, store gates, web audit. Its code is on the integration branch, not on `46e931f`: see the Git map in the checkpoint |
| `docs/PRODUCTION_DATABASE_BACKUP_RUNBOOK.md` | Production database backup, its record and the restore-test plan. The `supabase/backup/` scripts it uses are on `ops/production-backup-tooling` and the integration branch |
| `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` | Performance and offline-first work, measurements, deferred device tests |
| `docs/BROKER_WALLET_MASTER_TEST_PLAN_DEFERRED_2026-09-18.md` | Deferred device test scenarios (`MEDIA-*` and others) |
| `docs/OFFER_MEDIA_DEVICE_ISSUES.md` | Offer media device issues |
| `docs/INTEGRATION_01F_2026-11-28.md` | Task 01F integration: commits, conflict resolutions, WIP reconciliation, local verification |
| `docs/TASK_01_FINAL_HANDOFF.md` | Task 01 closeout: baseline for task 02, branch map, integrity check, external security-file status |
| `docs/LEGACY_FIRESTORE_QUOTA_REMOVAL_PLAN.md` | Remaining legacy Firestore quota code and its removal |
| `docs/toolbox/` | Toolkit cloud documents rollout and production enablement, UAE links verification |
| `docs/backend-migration-plan.md`, `docs/backend-schema-decisions.md` | Original Firebase → Supabase migration plan and schema decisions (historical; the migration is complete except FCM and the legacy quota gates) |
| `docs/checkpoint4-supabase-auth-profile-manual-test.md`, `docs/stage3-core-crud-*.md` | Early stage test notes (historical) |
| `supabase/README.md` | Supabase CLI usage |

## History

`docs/archive/` holds frozen documents. `docs/archive/README.md` explains each file and how to verify it against Git.

## How to update

- A status change: edit `docs/CURRENT_CHECKPOINT.md` (replace the row; do not append a diary).
- Evidence, commands and long results: the topic document above, as a dated section.
- A new durable decision: `docs/DECISIONS.md`, dated. A replaced decision is marked "Superseded (date)", never deleted.
- Never edit `docs/archive/`.
