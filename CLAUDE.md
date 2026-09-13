# Claude instructions

Read `AGENTS.md` and `docs/CURRENT_CHECKPOINT.md` first. Read `docs/PROJECT_STATE.md` and `docs/DECISIONS.md` only when relevant.

Known trap: Flutter commands rewrite the generated plugin registrant files under `linux/flutter/`, `macos/Flutter/` and `windows/flutter/`, so they show as modified in `git status` even when `git diff` shows no content change. Never include them in a feature commit and never edit them by hand; report them rather than restoring them unless the owner asks.

Known trap: do not run a bare `dart format` on `lib/` or on already-tracked
files. The package language version is 3.5, so the formatter uses the old short
style, but three files still carry pre-existing deviations from it —
`lib/src/viewmodels/Signup-Login/auth_viewmodel.dart`,
`lib/src/views/Screens/home/Profile/edit_profile_view.dart` and
`lib/src/repositories/firebase_auth_repository.dart`. Formatting them injects
unrelated churn into a feature diff. Format only genuinely new files, and
verify with `dart format --output=none --set-exit-if-changed` first.

Known trap: `core.autocrlf` is `true` and there is no `.gitattributes`, so the
working tree is CRLF while the index is LF. Newly written blocks often land as
LF inside an otherwise-CRLF file. Git normalizes this on staging, so it never
reaches a commit and `git diff --check` stays clean — but `dart format` and
plain `diff` will report those lines as changed. Treat a format/diff hit whose
content is byte-identical as a line-ending artifact, not a defect.

Known trap: `pumpEventQueue()` hangs inside `testWidgets`. The test body runs
in a fake-async zone, so the event queue only advances when the tester pumps.
In a widget test, pump the widget first and then drive streams with
`await tester.pump()` / `pumpAndSettle()`; keep `pumpEventQueue()` for plain
`test()` bodies, where it works normally.

Known trap: an `AuthException` from Supabase's deep-link observer does not
reach you as a thrown exception. `SupabaseAuth._handleDeeplink` catches it and
calls `notifyException`, which re-publishes it as an *error on the
`onAuthStateChange` stream*. Any `.listen(...)` on that stream — or on anything
forwarding it, such as `AuthRepository.authStateChanges` — without an `onError`
turns it into an unhandled async error far from its cause. Always pass
`onError`, and never treat an auth-stream error as a sign-out: a real sign-out
arrives as a null identity event.
