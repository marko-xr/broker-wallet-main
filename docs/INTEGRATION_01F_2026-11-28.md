# Task 01F: consolidated integration (2026-11-28)

Local only. Nothing was pushed, deployed, applied or paid. Status words follow `docs/CURRENT_CHECKPOINT.md`: everything
below is **LOCAL_TESTED** at most.

## Branch

`integration/broker-wallet-consolidated`, cut from `docs/project-context-refresh` at `46e931f`. Built with Git
plumbing (`merge-tree --write-tree`, a temporary index, `commit-tree`, `update-ref`): the main checkout, its working
tree, its branch and the four stashes were never touched. The source branches keep their histories.

| Commit | What |
|---|---|
| `a3f96b3` | Merge `feature/subscriptions-payments-flutter` `f7d2ffa` (subscription backend `02ec76b`, payment backend `5a6c956`, web foundation `53c313b`, Flutter client) |
| `a2e182f` | Lowercase the 6 remaining `src/Views/` imports in `SubscriptionPlan/` and the 3 `File('lib/src/Views/...')` paths in 2 auth tests |
| `8e37a90` | Merge `chore/store-compliance-targetsdk36` `950bb2b` |
| `1875d91` | Merge `ops/production-backup-tooling` `b8917a8` |
| `1ca452d` | `signature_source_guards_test` reads CHECKPOINT S4 from the archive (01E moved it there; the guard failed on `46e931f` too) |
| tip | This record and the checkpoint/README updates |

The WIP `2118fea` was not merged.

## Conflicts

Only the first merge conflicted, in four files: `lib/app.dart` and the Profile `subscription_view.dart`,
`billing_payments_view.dart`, `my_plan_view.dart`. Every hunk was an import block: the base had lowercased
`src/Views/` (`6951b29`) while the branch edited the same lines. Resolution: the branch's import set in the base's
casing. Each resolved file equals the branch file with `src/Views/` → `src/views/`, and nothing else. The other twelve
files both sides changed merged cleanly and also equal the branch plus the base's casing (and, for `pubspec.yaml`, the
base's de-duplicated Noto font paths).

## Reconciliation

- Every file each source branch changed is in the result, identical or differing only by casing / the font path:
  `f7d2ffa` 135 files (118 identical, 17 casing), `950bb2b` 4 identical, `b8917a8` 5 identical.
- Against the WIP `2118fea`: 286 paths differ, all intentional. 160 changed and 102 deleted by the base cleanup
  (`57d0c5e`…`6951b29`, 01E) where the WIP left them alone; 3 added by 01E (`docs/README.md`, `docs/archive/*`);
  16 WIP files differ only by the lowercase casing; `pubspec.yaml` only by the font paths; the 2 auth tests only by
  the path casing; `docs/CURRENT_CHECKPOINT.md` is the 01E page (the WIP text is the archive blob `fde0278`);
  `deno.lock` is excluded (no tool needs it: Deno runs with `--no-lock`).
- Nothing deleted by the cleanup came back: no `_Bold` font folders, logs, `.iml`, empty Dart files or `*-Share.svg`.
- `supabase/` and `cloudflare/` equal `f7d2ffa` plus the 4 `supabase/backup/` files; both runbooks and `docs/archive/`
  equal `46e931f`.
- Case-sensitive audit of every own-package import/export/part URI and string path (4,676 URIs): 0 mismatches
  (`46e931f` had 3 path-casing hits, the merged tree 9 before the fix commit).
- Six asset strings in `lib/` (`*_active.svg`, `icons/placeholder.png`, `images/listdots.png`) name files that do not
  exist; already so on `ceb488d`, not caused by this integration.

## Verification (on a `git archive` export in a case-sensitive directory)

| Check | Result |
|---|---|
| `flutter pub get --offline` | `pubspec.lock` unchanged |
| `flutter analyze --no-pub lib test integration_test` | 0 errors, 0 warnings, 82 infos (77 `deprecated_member_use`, 5 `unnecessary_import`; none in a file this task touched) |
| `flutter test` (full suite) | 8,489 pass, 13 skip, 1 fail = the S4 doc guard, then fixed; the guard plus both case-fixed auth tests rerun: 60/60 |
| Deno, all 5 function test files | 67/67 (`--cached-only --no-lock --no-config`; push-dispatch with loopback-only net and scoped env as its header says; `fcm.test.ts` with read access to the tracked `android/app/google-services.json` only) |
| Worker `node --test` | 372/372 |
| SQL on a throwaway native PostgreSQL 17.12 (loopback) | 14/14 SQL test files (pgTAP emulated), 312 logic/E2E/channel/race checks, 36/36 mutations caught |
| `flutter build web --release` | Built (only wasm dry-run lint notices) |
| `flutter build apk --release` | Not run in 01F (hook, below). **PASS in task 01F.1**, debug-key signed: see the 01F.1 section |

In 01F the hook scanned the session's main checkout, which was still on `docs/project-context-refresh` (no `targetSdk`
36, no privacy manifest) and holds gitignored files (`staging-acceptance/reports/`, `graphify-out/`): 6 critical
findings. A standalone scan of the integration export shows 1 critical, `supabase/config.toml:101` (the local Supabase
CLI Studio `api_url = "http://127.0.0.1"`, not compiled into any app build).

Not covered in 01F: iOS build, real devices, any hosted step, provider sandboxes. The Android compile of
`in_app_purchase_android` is covered by 01F.1.

## Task 01F.1: Android release build (2026-11-28)

Every status below is **LOCAL_TESTED**. Nothing here is HOSTED_VERIFIED, DEVICE_VERIFIED or PRODUCTION_READY.

**Branch.** `fix/android-build-readiness`, cut from `2cf3602` with `git branch` (no checkout). The build needed no
source, dependency, Gradle or hook change; the only commit on the branch is this documentation.

**Why the hook scanned the old checkout.** `~/.claude/hooks/app-store-compliance-guard.sh` takes its folder from
`CLAUDE_PROJECT_DIR` (the main checkout). The only way it narrows that folder is one leading `cd <dir> &&` whose real
path lies **inside** the project root; 01F built in a folder outside it, so the hook ignored it. 01F.1 exported
`2cf3602` with `git archive` into the gitignored `build/_01f1/src` inside the main checkout and ran
`cd "<that folder>" && flutter build apk --release`. That is the hook's own documented scoping: no
`APP_STORE_GUARD_OK`, no skip flag, no change to the hook. The export folder is not case-sensitive (`fsutil
setCaseSensitiveInfo` is denied inside the repository); the 01F case-sensitive audit (0 mismatches) still covers casing.

**The six 01F criticals (main checkout, `46e931f`), reproduced with the hook in standalone mode:**

| Finding | Cause | On `2cf3602` |
|---|---|---|
| `GOOGLE-TARGET-API` (35) | Real on `46e931f` | Fixed: 36 |
| `FLUTTER-PRIVACY-MANIFEST-MISSING` | Real on `46e931f` (iOS) | Fixed: `ios/Runner/PrivacyInfo.xcprivacy` |
| `APPLE-PRIVACY-MANIFEST-MISSING` | Real on `46e931f` (iOS) | Fixed: same file |
| `GOOGLE-PERM-ALL-FILES` | False positive: the permission name sat in an XML comment; no such permission is declared | Comment reworded (`950bb2b`); the APK declares no all-files permission |
| `GOOGLE-PLAY-BILLING` | Gitignored local file `graphify-out/graph.json` | Not raised (Play Billing plugin present) |
| `APPLE-2.1-STAGING-BACKEND` | Gitignored local file `staging-acceptance/reports/.../supabase/config.toml` | Raised by the tracked `supabase/config.toml:101`, Apple-only (below) |

**Compliance scan of the exact integrated source.**

- Hook mode with the build command (Android only, Apple checks suppressed): **0 critical**, 7 high, 3 medium; the
  build was allowed.
- Standalone, all platforms: 1 critical, 11 high, 7 medium.
- Remaining critical: `APPLE-2.1-STAGING-BACKEND` at `supabase/config.toml:101`. This is the local Supabase CLI
  configuration, which no app build compiles. It would block an **iOS** build or submit of this tree until the owner
  decides how to treat it.
- Remaining high and medium findings, not triaged in 01F.1 (file named by the hook):
  - Android/both: R8 off (`minifyEnabled false`); custom-scheme deep links without App Links
    (`AndroidManifest.xml:41`); placeholder text (`uae_link_url_policy.dart:6`); hard-cancel wording
    (`combine_executor.dart:18`); donation link and tracking scripts (`functions/package-lock.json`, not part of the
    APK); web `localStorage` (`supabase_bootstrap_service.dart:50`); future-functionality wording
    (`login_viewmodel.dart:309`); Restore Credentials (`auth_repository.dart:293`); the Play 12-tester rule.
  - iOS only: social login without Sign in with Apple, Universal Links, `ITSAppUsesNonExemptEncryption`, weak
    account-deletion wording, social-media declaration, VoiceOver, haptics, the 2026 age-rating questionnaire.

**Build.** Flutter 3.47.2, Gradle 8.14.5, AGP 8.11.1, Kotlin 2.3.10, `flutter pub get --offline` first
(`pubspec.lock` unchanged before and after). `flutter build apk --release` with no `--dart-define`: exit 0, about
19 minutes. Flutter warns that support for this Gradle, AGP and Kotlin will soon end (asks for at least 9.1.0,
9.0.1 and 2.3.20).

**APK** `build/app/outputs/flutter-apk/app-release.apk` in the export: 146,185,841 bytes, SHA-256
`65138ef2b1b50b98adf0aff135fd59b81e4679044f6b2c740244f9c57cc410e9`.

| Check | Result |
|---|---|
| Package, version | `com.nmodigital.brokerwallet`, `1.0.0` (versionCode 1), minSdk 24 |
| `targetSdk` / `compileSdk` | 36 / 36 |
| Signing | APK Signature Scheme v2, `CN=Android Debug`, certificate SHA-256 `6dcf85…9ef39f61`. **Debug key: never upload to a store** |
| Play Billing | `com.android.vending.BILLING`, `billingclient.version` 9.1.0, `ProxyBillingActivity`/`V2`, `BillingClient` and the `inapppurchase` plugin classes in dex |
| Permissions | No all-files permission; storage permissions capped (`WRITE` ≤ 29, `READ` ≤ 32) |
| Predictive back | `enableOnBackInvokedCallback=false` |
| 16 KB pages | `zipalign -c -P 16` passed; every arm64-v8a and x86_64 library has a LOAD alignment of 0x4000 or more |
| ABIs | arm64-v8a, x86_64 **and armeabi-v7a**, although Gradle `abiFilters` names only the two 64-bit ABIs |

The build had no `--dart-define`, so `BW_PUBLIC_RELEASE` and `SUBSCRIPTION_BACKEND` were off: this is a local
verification build, not the public-release configuration.

**Other local results (from 01F, not re-run in 01F.1):** analyzer 0 errors / 0 warnings / 82 infos; full Flutter suite
8,489 pass / 13 skip (plus the fixed S4 guard and auth tests 60/60); Deno 67/67; Worker 372/372; SQL 14/14 files,
312 checks, 36/36 mutants; `flutter build web --release` PASS.

**Open before any store release (not PRODUCTION_READY):**

- Android:
  - release-key signing and an App Bundle build;
  - a `BW_PUBLIC_RELEASE` build;
  - R8 and App Links;
  - installing on the Samsung (only `adb install -r --user 0`);
  - a Play Console product, license testers and a real purchase test;
  - the Google Play UAE billing choice for Tap;
  - the Gradle, AGP and Kotlin upgrades (each its own checkpoint).
- iOS:
  - the `supabase/config.toml` hook decision;
  - an Xcode build of this tree;
  - the Apple no-IAP model basis (UAE);
  - Sign in with Apple;
  - the export-compliance answer;
  - Universal Links;
  - the APNs key, which needs the Apple Developer membership.
- Payments: no Tap test key or sandbox run, no Play sandbox run, no real payment.
- Hosted: subscription and payment migrations (`20261123100000`, `20261123120000`, `20261124100000`), Edge Functions
  and Worker quota code are not applied or deployed. Staging and production share one Supabase project, and no isolated
  restore of the backup has been done yet.
