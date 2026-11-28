# Task 01: final handoff (2026-11-28, task 01G)

Documentation only. Nothing was deployed, applied, paid, rebuilt or re-tested in 01G. Status words follow
`docs/CURRENT_CHECKPOINT.md`; nothing below is HOSTED_VERIFIED, DEVICE_VERIFIED or PRODUCTION_READY unless it says so.

## 1. Baseline for task 02

| Item | Value |
|---|---|
| Branch to cut task 02 from | `chore/task01-final-handoff` (this commit), pushed to `origin` |
| Parent of this commit | `fix/android-build-readiness` `8feca38` (01F.1 record) |
| Code baseline | The tree of `integration/broker-wallet-consolidated` `2cf3602`. `8feca38` and this commit change documentation only |
| Code status | LOCAL_TESTED (section 5). Not PRODUCTION_READY |
| `main` | `c29115e` (2026-09-10), unchanged on `origin` and far behind. 01G did not update, merge into or open a PR to `main` |
| Hosted state | Unchanged by task 01 apart from the read-only checks and the production backup (section 2) |

Every branch listed in section 3 except the WIP snapshot `2118fea` is an ancestor of `8feca38`, so nothing on them is
missing from the baseline.

## 2. What task 01 did

| Step | Result | Record |
|---|---|---|
| 01 (2026-11-26) | Encrypted logical backup of the production database on the owner's external drive, verified by decryption, checksum and row counts | `docs/PRODUCTION_DATABASE_BACKUP_RUNBOOK.md` section 9 |
| 01B (2026-11-27) | Full restore-test plan (temporary hosted recovery project), **not approved, not run**. A full local repository snapshot was taken before the cleanup | Runbook section 10 |
| Repository cleanup (2026-11-27/28) | Five commits on top of `ceb488d`, section 4. The WIP of subscriptions, payments, web, store and backup work was saved as `backup/subscriptions-payments-web-wip` `2118fea` and split into six topic branches | `docs/CURRENT_CHECKPOINT.md` Git map |
| 01E (2026-11-28) | Documentation refresh: short checkpoint, 18,323-line history frozen in `docs/archive/`, `docs/README.md` map, AGENTS.md work rules | `46e931f` |
| 01F (2026-11-28) | `integration/broker-wallet-consolidated` `2cf3602`: the subscription/payment/web, store-compliance and backup-tooling branches merged into `46e931f`, plus the import-casing and S4 guard fixes | `docs/INTEGRATION_01F_2026-11-28.md` |
| 01F.1 (2026-11-28) | Android release APK built from an export of `2cf3602` (debug key), no source change | Same file, 01F.1 section; `8feca38` |
| 01G (2026-11-28) | Integrity check, this handoff, review of the external security files, push of this branch only | This file |

## 3. Branch map (read 2026-11-28)

On `origin` before 01G: `main`, `fix/import-path-casing` `6951b29`, `docs/project-context-refresh` `46e931f`, the
older feature branches, `backup/subscriptions-payments-web-wip` `2118fea`. Local only before 01G: the six topic
branches, `integration/broker-wallet-consolidated` and `fix/android-build-readiness`. Pushing
`chore/task01-final-handoff` uploads their commits as its history (14 commits, `950bb2b` … `8feca38`) but creates no
other branch on `origin`.

| Branch | Commit | Role |
|---|---|---|
| `chore/task01-final-handoff` | this commit | **Baseline for task 02** |
| `fix/android-build-readiness` | `8feca38` | 01F.1 record (docs only) |
| `integration/broker-wallet-consolidated` | `2cf3602` | 01F integration |
| `docs/project-context-refresh` | `46e931f` | 01E docs refresh; the main checkout is on it |
| `fix/import-path-casing` | `6951b29` | Cleanup tip, the base of 01E |
| `feature/subscriptions-payments-flutter` | `f7d2ffa` | Flutter subscription and payment client (includes `5a6c956`, `02ec76b`, `53c313b`) |
| `feature/payment-backend-tap-play` | `5a6c956` | Payment backend |
| `feature/subscriptions-backend-quotas` | `02ec76b` | Subscription backend and quotas |
| `feature/flutter-web-foundation` | `53c313b` | Flutter web foundation |
| `chore/store-compliance-targetsdk36` | `950bb2b` | `targetSdk` 36, iOS privacy manifest |
| `ops/production-backup-tooling` | `b8917a8` | `supabase/backup/` scripts and runbook |
| `backup/subscriptions-payments-web-wip` | `2118fea` | WIP snapshot, on `origin`. **Not merged and not for merge**; only `deno.lock` is unique to it (Deno runs with `--no-lock`) |
| `main` | `c29115e` | Old default branch |

Keep every branch. None is to be deleted as part of task 01.

## 4. Cleanup changes (in the baseline)

| Commit | Change |
|---|---|
| `57d0c5e` | Stray debug logs, an empty `test.dart` and IDE `.iml` files removed |
| `27869bb` | Unused `next`, `react`, `react-dom` dropped from the root `package.json` |
| `8012e84` | Empty Dart files and duplicate `*-Share.svg` icons removed |
| `29cfa57` | Duplicate Noto `_Bold` font folders and a duplicate icon removed |
| `6951b29` | Dart import paths match the tracked file casing (`src/views/`) |
| `a2e182f` | The remaining subscription imports and two test paths lowercased (01F) |
| `1ca452d` | The S4 signature doc guard reads the archived checkpoint (01F) |

## 5. Verification reused from 01F and 01F.1 (not re-run in 01G)

All LOCAL_TESTED, on a `git archive` export of `2cf3602`, providers and hosted services faked:

| Check | Result |
|---|---|
| `flutter analyze --no-pub lib test integration_test` | 0 errors, 0 warnings, 82 infos |
| `flutter test` (full suite) | 8,489 pass, 13 skip; the one failure (S4 doc guard) fixed in `1ca452d`, guard and auth tests rerun 60/60 |
| Deno function tests | 67/67 |
| Worker `node --test` | 372/372 |
| SQL on a local PostgreSQL 17 | 14/14 files, 312 checks, 36/36 mutations caught |
| `flutter build web --release` | PASS |
| `flutter build apk --release` (01F.1) | PASS, **debug key**, `targetSdk` 36, Play Billing 9.1.0, 16 KB alignment OK |

Not covered: iOS build, real devices, any hosted step, provider sandboxes, a release-key or `BW_PUBLIC_RELEASE` build.

## 6. Repository integrity (01G, 2026-11-28)

- `git fsck --no-dangling`: exit 0, no output.
- Ancestry: every local branch except `backup/subscriptions-payments-web-wip` is an ancestor of `8feca38`.
- Stashes, all four kept: `stash@{0}` `f97e443` (ios-notifications-implementation), `stash@{1}` `d2aa563`
  (iOS-branch), `stash@{2}` `10cd41f` (update-some-issues, "UI rollback backup before restoring HEAD"), `stash@{3}`
  `d9853b1` (toolkit-cloud-documents-readiness).
- Working tree of the main checkout: only the generated `macos/Flutter/GeneratedPluginRegistrant.swift` is modified
  (two added lines). It is preserved, not committed.
- 01G built this commit with Git plumbing (temporary index, `commit-tree`, `update-ref`); the main checkout, its branch,
  its working tree and the stashes were not touched.
- Push safety scan of everything new to `origin`: no environment files, keystores, key properties, private keys,
  service-account files, backups, dumps, APKs, generated registrants, `graphify-out/`, `staging-acceptance/reports/`
  or `node_modules`. Two pattern hits, both already on `origin` in `46e931f`: the Android Maps client key in
  `AndroidManifest.xml` and a fixture password in `test/auth/real_email_verification_route_test.dart`.

## 7. External security files (outside the repository; contents never opened, printed or uploaded)

| File | Finding | Status |
|---|---|---|
| Plaintext note of the backup passphrase (32 bytes, in the owner's Downloads folder) | Unencrypted secret on an unencrypted disk | **Awaiting the owner**: delete only after the owner confirms the passphrase is saved in the password manager and approves the deletion |
| Unencrypted full repository snapshot from 01B (Claude session scratchpad under the user Temp folder, about 76 MB: Git bundle of all 31 refs and stashes, a mirror, the WIP working tree, patches, lists) | Verified redundant: every bundle and mirror commit exists in the repository, the four stashes are identical, the 148 working-tree files equal `2118fea` (on `origin`) plus the current registrant, the two ignored files equal the checkout | **Awaiting the owner's deletion approval** |
| `build/_01f1/` in the main checkout (about 2.3 GB, gitignored) and the 01F scratchpad export | `git archive` exports of tracked files plus build output and the debug APK; no ignored secrets | Kept; housekeeping only, not a secret risk |

The encrypted production backup on the owner's external drive is the only copy of production data and stays.

## 8. Remaining limitations (open, not part of task 01)

- No isolated restore of the production backup (runbook section 10 needs the owner's approval).
- Subscription and payment migrations, Edge Functions and Worker quota code are not applied or deployed; staging and
  production share one Supabase project.
- Android: release-key signing, App Bundle, `BW_PUBLIC_RELEASE` build, R8, App Links, Play Console product and testers,
  Gradle/AGP/Kotlin upgrades (each its own checkpoint), install on the Samsung.
- iOS: Xcode build of this tree, the `supabase/config.toml` hook decision, Apple no-IAP basis, Sign in with Apple,
  export compliance, Universal Links, APNs key.
- Payments: no Tap or Play sandbox run, no real payment.
- On the base, quotas are not enforced until the subscription backend is hosted.

## 9. Rules for task 02 and later

- Cut each task's branch from the baseline in section 1 unless the owner names another; one task per branch and chat.
- Keep `docs/CURRENT_CHECKPOINT.md` as the status page; long evidence goes to topic docs; never edit `docs/archive/`.
- Every hosted, store and payment step needs the owner's explicit approval of that exact step.
- Never commit the generated plugin registrants, `graphify-out/`, `build/` or any local report.
