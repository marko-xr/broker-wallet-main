# Claude instructions

Read `AGENTS.md` and `docs/CURRENT_CHECKPOINT.md` first. Read `docs/PROJECT_STATE.md` and `docs/DECISIONS.md` only when relevant.

Known trap: Flutter commands rewrite the generated plugin registrant files under `linux/flutter/`, `macos/Flutter/` and `windows/flutter/`, so they show as modified in `git status` even when `git diff` shows no content change. Never include them in a feature commit and never edit them by hand; report them rather than restoring them unless the owner asks.
