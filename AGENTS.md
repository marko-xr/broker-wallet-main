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
