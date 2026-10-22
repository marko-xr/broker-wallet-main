# Toolkit Cloud Documents — real-R2 staging acceptance (C3B.5A)

An owner-run end-to-end check of the Toolkit document routes on the **staging** Worker
(`r2-profile-upload-staging`, private bucket `broker-wallet-media-staging`) against the hosted Supabase project,
using the real R2 presigned PUT / GET. It never targets production: the runner refuses any Worker URL that is not
`https://r2-profile-upload-staging.<subdomain>.workers.dev`, refuses any signed URL that is not the staging bucket's
and the signed-in account's Toolkit prefix, and only ever sends the publishable key (never a secret key).

Needs **two different DISPOSABLE Supabase test accounts** (not the account on your phone: claiming a session ends the
account's other sessions) and the staging gate key. Node built-ins only; no `npm install`.

## Run (PowerShell, from this folder)

```powershell
.\run_toolkit_staging_acceptance.ps1 -Phases A          # start here: one PDF, then Scanner JPEG and PNG
.\run_toolkit_staging_acceptance.ps1 -Phases B          # write-once (replay of a signed PUT)
.\run_toolkit_staging_acceptance.ps1 -Phases ABCDE      # everything
```

Settings (process or User environment, else masked prompts): `BW_E2E_STAGING_KEY`, `BW_TOOLKIT_A_EMAIL`,
`BW_TOOLKIT_A_PASSWORD`, `BW_TOOLKIT_B_EMAIL`, `BW_TOOLKIT_B_PASSWORD`; optional `BW_TOOLKIT_A_UID` / `BW_TOOLKIT_B_UID`
(the run stops if the signed-in account is not that one). The launcher asks you to type `CLAIM` (Single Active Device);
the runner then asks for a second confirmation, `CREATE TEST DOCUMENTS`, before it creates any document or PUTs any byte.

## Phases

| Phase | What it does | Stops on |
|---|---|---|
| A | PDF first (authorize, PUT with `If-None-Match: *`, confirm, list, signed GET, byte length and SHA-256), then Scanner JPEG and PNG in their original formats; a wrong digest claim shows whether `sha256Verified` is Worker verification or only the device's claim | any failure |
| B | replay of the same signed PUT with different bytes (with and without the signed header), before and after the confirm; the object must keep its SHA-256 | an accepted overwrite = SECURITY BLOCKER (exit 3) |
| C | account B cannot list / download / rename / remove / re-authorize A's document; direct PostgREST stays RLS-constrained (no key or bucket columns, no writes, no functions); at the END of the run a superseded session of A is refused by the Worker and PostgREST and cannot reclaim | any failure |
| D | rename with expected version, stale version, idempotent confirm, remove, tombstone state, repeated remove, no resurrection, incomplete and wrong-size uploads, retry, lost-PUT-answer retry | any failure |
| E | no write: no HTTP route can trigger a cleanup; every confirmed document of the run is still intact; lists what this run cannot prove | — |

Order of execution: A, B, C (isolation), D, C (sessions), E, then cleanup.

## What it creates and removes

Only new synthetic documents titled `staging-e2e-toolkit-<run>-…` (about 8 for account A, 1 for B) in the staging bucket, owned by
the two test accounts. The runner requests removal for each created document and checks that no ready copy appears in account lists, but does not independently inspect R2 inventory. `cleanupPending` is reported as pending finalization, not proof the object is gone. The Worker writes the tombstone after the ~6 minute signed-URL window; with the sweep OFF it may stay in the hidden "deleting" state until a later repeated remove.
It does not intentionally touch any existing document, real account, sweep, Worker variable or other object. Before starting, verify both test accounts are owned by you. If a cleanup check fails, inspect the test-only leftovers before continuing.

## Report

`reports\toolkit_staging_<run>.json` (gitignored): PASS/FAIL per check, HTTP statuses, fixed codes. No password, token, signed
URL, e-mail, account id, document id or object key. Exit code: 0 all passed, 1 a failure, 3 security blocker, 2 refused to start.

The PDF fixture now has a valid cross-reference table and `startxref`; the PNG fixture includes a correct CRC for its inserted `tEXt` chunk, so normal document/image readers can open them.

## Not proven by this runner

The claim-first abandoned-upload cleanup on real objects (stale-only claims, the lease takeover, a delete during a claim, the 503
answers) needs the sweep in `dry_run` then `on` in a separately authorized window. Authenticated device behavior and Delete Account
with real objects are also out of scope.

## Offline self-test

`node toolkit_offline_selftest.mjs` runs the whole runner against the real Worker code with in-memory doubles (no network): all
phases, stop conditions, the overwrite blocker, the write confirmation, project / account guards, URL guards and output safety.
