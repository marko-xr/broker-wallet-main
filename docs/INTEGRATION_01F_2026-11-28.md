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
| `flutter build apk --release` | **Not run**: blocked by the owner's store-compliance hook (see below). No override was used |

The hook scans the session's main checkout, which was still on `docs/project-context-refresh` (no `targetSdk` 36, no
privacy manifest) and holds gitignored files (`staging-acceptance/reports/`, `graphify-out/`): 6 critical findings.
A standalone scan of the integration export shows 1 critical, `supabase/config.toml:101` (the local Supabase CLI
Studio `api_url = "http://127.0.0.1"`, not compiled into any app build). An Android build of the integration branch
needs the owner: run it from a checkout of this branch, or decide how the hook should treat those files.

Not covered: iOS build, real devices, any hosted step, provider sandboxes, the Android compile of
`in_app_purchase_android`.
