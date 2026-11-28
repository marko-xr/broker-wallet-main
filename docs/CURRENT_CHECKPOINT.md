# Current checkpoint

Updated 2026-11-28 (task 01G, task 01 final handoff; documentation only, nothing hosted). This page is the one source of truth for **current status**. Keep it
short: replace a status when it changes, and move long evidence into the topic document it belongs to.

The full history up to 2026-11-27 (18,323 lines, every dated section, evidence, version ids and rollback notes) is
frozen in `docs/archive/CURRENT_CHECKPOINT_HISTORY_TO_2026-11-27.md`; see `docs/archive/README.md` for its map. Any
reference written before 2026-11-28 to a section of `docs/CURRENT_CHECKPOINT.md` means that section of the archive.
Documentation map: `docs/README.md`.

## Status vocabulary

| Status | Meaning |
|---|---|
| CODE | The source exists on the named branch. Nothing run |
| LOCAL_TESTED | Tests or analysis ran locally (Flutter, Worker `node --test`, Deno, PostgreSQL/PGlite). Providers and hosted services were fakes |
| HOSTED_VERIFIED | Applied, deployed or read back on the hosted Supabase or Cloudflare. Staging and production share **one** Supabase project, so a hosted step is a production step |
| DEVICE_VERIFIED | The owner verified it on a real phone (earlier sections call this VERIFIED_RUNTIME / VERIFIED_REAL_DEVICE) |
| PRODUCTION_READY | Every gate passed for a public store release: hosted, device, store policy, legal. **No feature carries this status today**, because the app has no public release and the store gates below are open |

Never promote a status without the evidence named in this page or in a linked document.

## Git map (read 2026-11-28, no fetch)

- **Task 02A.1 (local, not pushed):** `feature/auth-google-signin`, cut from `chore/task01-final-handoff` `f01bcc9`:
  Google sign-in for Android (see Authentication below).
- **Baseline for task 02 (task 01G; not on origin per `git ls-remote`, 2026-11-28):** `chore/task01-final-handoff`, a documentation-only commit on
  `fix/android-build-readiness` `8feca38`; its code is the integration tree `2cf3602`. Handoff, integrity check and
  external security-file status: `docs/TASK_01_FINAL_HANDOFF.md`. Pushing it uploaded the commits of the branches
  below as its history; those branches themselves stay local.
- **Integration base:** `fix/import-path-casing` at `6951b29` (on origin). It contains every older branch: `main`,
  `backend-implementation`, `perf/phase-1-startup-baseline`, notifications, iOS, splash, phone auth (`ceb488d`) and the
  repo-cleanup chain (`57d0c5e` → `27869bb` → `8012e84` → `29cfa57` → `6951b29`). `main` (`c29115e`, 2026-09-10) is far
  behind.
- **Integration branch (task 01F, local, not pushed):** `integration/broker-wallet-consolidated`, cut from
  `docs/project-context-refresh` `46e931f`, merges `feature/subscriptions-payments-flutter` `f7d2ffa`,
  `chore/store-compliance-targetsdk36` `950bb2b` and `ops/production-backup-tooling` `b8917a8` (histories kept), plus
  two fixes (remaining import casing, S4 doc guard). LOCAL_TESTED; record, conflicts and WIP reconciliation in
  `docs/INTEGRATION_01F_2026-11-28.md`. The WIP `2118fea` was not merged.
- **Task 01F.1 branch (local, not pushed):** `fix/android-build-readiness`, cut from the integration tip `2cf3602`;
  documentation only (this record). The release APK was built from a `git archive` export of `2cf3602` with no source,
  dependency or hook change.
- **Not in the base `46e931f`** (cut from `ceb488d`, local only unless marked; all of them are in the integration
  branch, either directly or through `f7d2ffa`):

| Branch | Commit | Content |
|---|---|---|
| `backup/subscriptions-payments-web-wip` (on origin) | `2118fea` | WIP snapshot of all subscriptions, payments, web, store and backup work. Source of the six branches below. Not for merge |
| `chore/store-compliance-targetsdk36` | `950bb2b` | `targetSdk` 36, predictive back off, iOS `PrivacyInfo.xcprivacy` |
| `ops/production-backup-tooling` | `b8917a8` | `supabase/backup/` scripts and the backup runbook |
| `feature/flutter-web-foundation` | `53c313b` | Browser HTTP transport, web Maps loader, platform guards |
| `feature/subscriptions-backend-quotas` | `02ec76b` | Migration `20261123100000`, quota tests/rollback/preflight, Staging test mode, Worker quota |
| `feature/payment-backend-tap-play` | `5a6c956` (on `02ec76b`) | Payment migrations `20261123120000`, `20261124100000`, billing/webhook functions |
| `feature/subscriptions-payments-flutter` | `f7d2ffa` (merge `42bd6e5` of payments + web) | Flutter subscription, quota and payment client, Profile plan screens |

  Of the WIP's 147 changed files, only `deno.lock` and the WIP's checkpoint text exist nowhere else; that text is
  archived here byte-identical. The two runbooks are on this branch byte-identical to the WIP.
- **Stashes (keep):** `stash@{0}` ios-notifications-implementation, `stash@{1}` iOS-branch, `stash@{2}` update-some-issues
  "UI rollback backup before restoring HEAD", `stash@{3}` toolkit-cloud-documents-readiness.
- **Working tree:** `macos/Flutter/GeneratedPluginRegistrant.swift` shows as modified (generated; never commit it).

## Feature status

### Authentication

| Area | Code | Local | Hosted | Device | Notes |
|---|---|---|---|---|---|
| Email sign-up, login, logout, session restore | Base | Yes | Yes | Yes (2026-08/09) | Supabase Auth only; Firebase Auth code removed |
| Password change, forgot, recovery link | Base | Yes | Yes | Yes | `docs/PROJECT_STATE.md` |
| Email Change (incl. Secure Email Change) | Base | Yes | Yes | Yes | |
| Delete Account, email accounts | Base | Yes | Yes | Yes (production, 2026-09-14) | Lost-response path NOT RUN |
| Single Active Device | Base | Yes | Yes (Worker parity 2026-10-12) | Runtime-verified on staging | Authenticated production A-B test not run |
| Phone accounts, Model X (B1–C4) | Base (`5d15ddb`, `ceb488d`) | Yes (PGlite, Worker 359/359, Flutter 2,453) | **No** | **No** | `PHONE_AUTH_ENABLED` defaults to false. Migrations `20261122120000`, `130000`, `140000` NOT applied; no hook enabled; Worker phone routes NOT deployed. `docs/PHONE_ACCOUNT_SECURITY_DESIGN.md` |
| Google sign-in / sign-up, Android (task 02A.1) | `feature/auth-google-signin` | Yes (26 Google tests; 204 with related auth files, 2026-11-28) | **No**: provider, client IDs and SHA-1 not configured | No | CODE_READY / EXTERNAL_CONFIG_REQUIRED. Off unless built with `GOOGLE_WEB_CLIENT_ID`; iOS and web report "not available". Google-only accounts cannot use Delete Account yet (Worker refuses, fail-closed). `docs/GOOGLE_SIGN_IN_ANDROID.md` |
| Apple sign-in | None | – | – | – | Task 02B |

Phone accounts need a separate Supabase staging project and a real SMS/verify provider (business licence and UAE sender
registration) before any hosted step. No OTP tests on the shared project.

### Notifications

| Area | Code | Local | Hosted | Device | Notes |
|---|---|---|---|---|---|
| Inbox, follow-up reminders, Android FCM push | Base | Yes | Yes: migrations `20261120130000` and `20261121090000` applied 2026-11-21; `push-dispatch` (nonce) deployed; scheduler active since 2026-11-21 | Yes (Samsung, groups 1–7) | Open: 5c second account, 5d second device, 6(b) Arabic visuals, production retry path |
| iOS push (APNs) | Base (`831e7c9`) | Owner: 90 tests, Xcode build on the Mac | APNs key not uploaded | No | Blocked on the Apple Developer membership. `docs/NOTIFICATIONS_PRODUCTION_PLAN.md` |

### Subscriptions and quotas

| Area | Code | Local | Hosted | Device |
|---|---|---|---|---|
| Server entitlements, quotas, cutover/cutback | `feature/subscriptions-backend-quotas` | Yes (real PostgreSQL 17, emulated pgTAP, mutation and race checks) | **No**: no subscription object exists on production | No |
| Flutter plan screens and quota client | `feature/subscriptions-payments-flutter`, integration branch | Yes (integration branch full suite 8,489 pass / 13 skip, 2026-11-28, on a case-sensitive export; WIP 8,490 / 13 on 2026-11-26) | – | No |

On the base branch quotas are **not** enforced: core entities always allow creation, and the four Toolkit usage gates
plus `quota_helper` still call legacy Firestore without a Firebase session. That is a known production gap, closed only
by the subscription work. Release procedure: `docs/SUBSCRIPTION_PRODUCTION_RUNBOOK.md`.

### Payments

| Area | Code | Local | Hosted / sandbox | Device |
|---|---|---|---|---|
| Tap Payments (web cards), UAE VAT invoices | `feature/payment-backend-tap-play` + Flutter branch | Yes, fake Tap only | **No**: no Tap test key, no sandbox run | – |
| Google Play Billing (direct, `in_app_purchase_android` 0.5.5) | Same | Yes, fake Play only | **No**: no Play Console product | No. LOCAL_TESTED only: compiled and packaged in the 01F.1 release APK (Billing Library 9.1.0, `BILLING` permission, `ProxyBillingActivity`); no purchase ever run |

Final prices (owner, 2026-11-26): AED 20.00 monthly, AED 180.00 yearly, VAT included. RevenueCat, Stripe and Ziina are not
used. No real payment has been made.

### Flutter Web

| Code | Local | Hosted |
|---|---|---|
| `feature/flutter-web-foundation` (also merged into the Flutter subscription branch and the integration branch) | Boots, signs in, keeps its page on refresh and completes the billing journey in a local browser with fakes; release web build compiled 2026-11-24, and again from the integration branch 2026-11-28 | `app.brokerwallet.ae` serves an older build (1.0.0+1); its Cloudflare project was not inspected |

Not web-ready: Scanner and Signature crash on open, Images to PDF and Combine PDFs are expected to, Maps need
`GOOGLE_MAPS_WEB_API_KEY`, media upload, Quotation PDF, sharing and web realtime are unverified. The Toolkit web design
waits for the owner. The base branch lacks the web startup fixes (the WIP recorded a white screen at startup before
them).

### Production infrastructure

- **Supabase** project `rbvcnvqpdqrhywcgxkne`, the only project (staging = production), Free plan, no managed backup,
  PITR off. Migration history ends at `20261121090000` (read-only check, 2026-11-26). 5 accounts; several already exceed
  the planned Free limits.
- **Backup:** encrypted logical backup `20261126T194340Z` on the owner's drive `F:\BrokerWallet\ProductionBackups\`,
  verified by decryption, checksum and row counts. **No isolated full restore yet** (Task 01B: needs the owner's
  approval of a temporary recovery project). After any restore re-create the three `auth.users` triggers. Not in any
  dump: R2 media, Vault secret, function/Worker secrets, auth settings, Firestore. `docs/PRODUCTION_DATABASE_BACKUP_RUNBOOK.md`.
- **Cloudflare Worker** `r2-profile-upload`: last recorded production deployment `64a9589b` (2026-10-21, Toolkit cloud
  documents), rollback `96783f3d`; not re-read since. Staging Worker `r2-profile-upload-staging`. No phone or subscription
  Worker code is deployed.
- **Android:** application id `com.nmodigital.brokerwallet`. Base branch is `targetSdk` 35; Play requires 36
  (fixed on `chore/store-compliance-targetsdk36` and the integration branch). **Release APK of `2cf3602`: build PASS,
  LOCAL_TESTED** (01F.1, 2026-11-28): `targetSdk`/`compileSdk` 36, **debug-key signed** (no release keystore used; not
  uploadable), 16 KB alignment OK, store-compliance hook 0 critical. Not installed on any device; no release-key,
  public-release (`BW_PUBLIC_RELEASE`) or App Bundle build. Evidence and remaining findings: the 01F record.
- **Store gates open:** Apple has no identified basis for the no-IAP iPhone model (UAE); Google Play UAE billing choice
  for Tap; Sign in with Apple; export-compliance answer; R8; App Links; store privacy answers; release signing. The
  store-compliance hook scans the main checkout unless the command starts with a `cd` into a folder inside it; an
  iOS build of the integration tree is still blocked by its Apple-only `supabase/config.toml` finding (owner decision).

## Other areas (details in the archive and topic docs)

Offer, Owner and Quotation private media, land/plot plan attachments, Search, Share, Favorites, Home filters, Toolkit
tools S1–S5 and cloud documents (production Worker since 2026-10-21; real-phone check owed), responsive hardening
R1–R8A, offline-first performance work (`docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`) and the launch screen.

## NOW / NEXT

**NOW:** task 01 is handed off (`docs/TASK_01_FINAL_HANDOFF.md`). The baseline `chore/task01-final-handoff` is
LOCAL_TESTED, including a debug-signed Android release APK; it is **not** PRODUCTION_READY. Two external files (a
plaintext passphrase note and the unencrypted 01B repository snapshot) await the owner's confirmation and deletion
approval.
**Task 02A.1 (2026-11-28):** Google sign-in for Android is LOCAL_TESTED on `feature/auth-google-signin`; it needs the
owner's Google Cloud clients, the Supabase Google provider (a hosted step) and a device check before it is more.
**NEXT:** the owner's Google setup and device check (`docs/GOOGLE_SIGN_IN_ANDROID.md`), then task 02B (Apple) from the
approved integration tip. Whether and when `main` is updated is the owner's decision; every hosted, store and payment
step stays behind its own approval.
