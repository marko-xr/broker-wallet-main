# Broker Wallet agent rules

- Existing architecture: MVVM + Provider + Repository + GoRouter.
- Preserve existing Broker Wallet UI and screen layouts.
- Reuse existing ThemeData, AppColors, typography, spacing and components.
- Never introduce arbitrary hard-coded colors/fonts.
- Preserve Arabic + English localization and RTL.
- Do not hard-code production UI strings when localization exists.
- Supabase Auth is target auth authority in Supabase mode.
- `AuthRepository.currentUserId` is canonical identity.
- `auth.users.id = public.profiles.id`.
- `public.profiles` is canonical profile data.
- Never create `public.users` or Firebase/Supabase UID mappings.
- Never weaken RLS/security/authentication to make a feature pass.
- No fake success, swallowed authoritative failures, placeholders or demo behavior.
- Preserve Firebase behavior only for sections not yet migrated.
- One checkpoint/problem at a time.
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
  architecture, decision, blocker or verification status changed.
- Database/security migrations are never production-safe from source review or
  Flutter/Dart tests alone. Exercise them against a real or disposable database
  (pgTAP locally, or a rollback-only validation script) before any hosted PASS.
- Every handoff states NOW (the exact action to perform now) and NEXT (the exact
  action after that succeeds).
- Do not mark CODE_PROVEN work as VERIFIED_RUNTIME.

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
