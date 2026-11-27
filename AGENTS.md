# Broker Wallet agent rules

- Existing architecture: MVVM + Provider + Repository + GoRouter.
- Preserve existing Broker Wallet UI and screen layouts.
- Reuse existing ThemeData, AppColors, typography, spacing and components.
- Never introduce arbitrary hard-coded colors/fonts.
- Preserve Arabic + English localization and RTL.
- Do not hard-code production UI strings when localization exists.
- Supabase Auth is the only auth authority (Firebase Auth code is removed).
- `AuthRepository.currentUserId` is canonical identity.
- `auth.users.id = public.profiles.id`.
- `public.profiles` is canonical profile data.
- Never create `public.users` or Firebase/Supabase UID mappings.
- Never weaken RLS/security/authentication to make a feature pass.
- No fake success, swallowed authoritative failures, placeholders or demo behavior.
- Firebase remains only for FCM push transport (`firebase_core`,
  `firebase_messaging`) and the legacy Firestore quota gates
  (`docs/LEGACY_FIRESTORE_QUOTA_REMOVAL_PLAN.md`). Add no new Firebase use.
- One checkpoint/problem at a time (see "Work rules" below).
- Do not modify unrelated features.
- Do not remove, hide, redesign or alter existing user-facing UI or features
  unless the product owner explicitly authorized that UI change. A feature whose
  backend is unfinished, deferred or legacy is still the owner's to keep:
  report the real runtime capability instead of hiding the entry point.
- A scoped UI task authorizes only the screens it names. Report anything else
  worth changing as backlog; do not implement it.
- Do not commit unless explicitly requested.
- Do not deploy/apply migrations unless explicitly requested.
- Static/unit tests do not prove production behavior.
- A checkpoint is completed only after real-device verification.
- Before coding, read `AGENTS.md`, `CLAUDE.md` when present, and
  `docs/CURRENT_CHECKPOINT.md`.
- Before finishing a task, update the relevant durable docs when a checkpoint,
  architecture, decision, blocker or verification status changed, following
  `docs/README.md`: replace the status in `docs/CURRENT_CHECKPOINT.md` (keep it
  short), put long evidence in the topic document, and never edit `docs/archive/`.
- Database/security migrations are never production-safe from source review or
  Flutter/Dart tests alone. Exercise them against a real or disposable database
  (pgTAP locally, or a rollback-only validation script) before any hosted PASS.
- Every handoff states NOW (the exact action to perform now) and NEXT (the exact
  action after that succeeds).
- Do not mark CODE_PROVEN work as VERIFIED_RUNTIME.

## Work rules (owner, 2026-11-28)

- **One task per branch and per AI chat.** Each task gets its own branch, cut
  from the base the owner names. Do not mix tasks in one branch or one chat. Stop
  after the task's report and wait for the next instruction.
- **Reports in Arabic.** Every explanation, report and question to the owner is
  in Arabic. Code, identifiers, commit messages and repository documents stay in
  English.
- **Preserve Git work.** Never `reset`, `clean`, `restore`/`checkout` over
  existing changes, drop or pop a stash, delete a branch, `rebase`, `merge`,
  `push`, force-push or amend a commit that may be on origin, unless the owner
  asks for that exact action in the current task. Stage explicit paths only
  (never `git add .` or `-A`). Never commit the generated plugin registrants. No
  Git worktrees unless the owner asks. Preserve unfinished work as a Git branch
  and commit, not as an archive file. The owner pushes and pulls with GitHub
  Desktop at any time: check the branch and HEAD at the start of every task.
- **No unauthorized hosted changes.** Staging and production share one Supabase
  project, so every hosted write is a production write. Applying a migration,
  any SQL write, auth/config changes, Edge Functions, secrets, Workers, R2, cron,
  store consoles and payment providers each need the owner's explicit approval of
  that exact step. Read-only checks run only when the task allows them.
- **Report status honestly.** Use the status vocabulary in
  `docs/CURRENT_CHECKPOINT.md` (CODE, LOCAL_TESTED, HOSTED_VERIFIED,
  DEVICE_VERIFIED, PRODUCTION_READY) and name the evidence. Never call anything
  production-ready without it.

## Graphify (supporting tool only)

A local Graphify graph of `lib/` exists in `graphify-out/` (generated,
git-excluded through `.git/info/exclude`, never committed). It was validated on
2026-10-27 and is a navigation aid, never evidence.

- Trust, after a spot-check against the source line: class, mixin, `extends`,
  `implements` and `with` relations, `Provider.of` lookups, route/`Navigator`
  references, and which members a file defines. Cloudflare Worker `.js` modules
  also extract well.
- Do not trust for dependencies, call flow, communities or architecture:
  own-package and relative `import` edges point at dead string nodes, not at
  file nodes (no import graph); only 2 `calls` edges exist; community, bridge
  and "god node" results follow from that. Use `grep` on `import` lines and read
  the source.
- 27 files show a file node labelled `_` (a `Foo._()` constructor collides with
  the file node id); the edges are intact, only the label is wrong.
- Supabase `.sql` yields nothing (`tree_sitter_sql` is not installed, and it
  would model identifiers only, not RLS, grants or RPC behaviour). Read
  migrations and run the pgTAP/validation scripts instead.
- Files with no symbols are fully commented out or empty, not extractor
  failures; `favorites_item_model.g.dart` is the one unexplained miss.
- Do not rebuild the graph for routine work; refresh only after a meaningful
  structural change. Install no parsers and scan no further directories without
  a real task. Cross-check any graph answer with the source, `flutter analyze`,
  tests and these docs before it influences code.
