# Broker Wallet — C3B.7 exact-nine Toolkit cleanup, PREPARED ONLY

**Status: OFFLINE_PREPARED, no hosted deletion authorized, no mutation executed.**

This package is intentionally narrow. It is not a new cleanup architecture; it calls the already-deployed authenticated `POST /toolkit-documents/remove` route and no other mutation route except the existing Single Active Device session-claim RPC (required only if a later `-Apply` is approved). No SQL writes, `wrangler` deployments, Cloudflare API tokens, R2 credentials, or service-role keys are used.

## What was established before creating this package

- A–E hosted acceptance: 135 PASS / 0 FAIL.
- Toolkit sweep `dry_run`: `abandoned=0 pendingDeletes=9 tombstones=0 failures=0`.
- Last owner deployment: **Staging Worker** `d5102f8c-a358-446f-b878-7153b762c238` with Toolkit enabled and Toolkit/Offer/Owner sweeps `off`.
- Shared Supabase project: `rbvcnvqpdqrhywcgxkne`; private Staging bucket `broker-wallet-media-staging`.
- Nine synthetic `pending_delete` rows were counted by read-only Supabase SQL: A 4, B 1, C 2, DE 2. A more recent read-only SELECT is mandatory before any real deletion.

## Files

- `toolkit_cleanup_exact9.mjs` — defaults to offline `--check`; contains guarded, future `--apply` logic.
- `run_toolkit_cleanup.ps1` — owner-side wrapper. **Without `-Apply`, no HTTP requests, sign-in or session claim.**
- `toolkit_cleanup_selftest.mjs` — isolated Node tests with mock in-memory UUIDs, no HTTP.
- `C3B7_MANIFEST_READ_ONLY.sql` — read-only SQL for the existing hosted Supabase SQL Editor. Produces one result containing the JSON manifest and the global Staging-bucket counts.

## Install, without changing existing source

Place **the three `.mjs` / `.ps1` scripts** in the EXISTING:

`cloudflare/workers/r2-profile-upload/staging-acceptance/`

No existing file should be overwritten. Keep the SQL and README outside Git or in a review folder. This is not an instruction to commit anything.

This script dynamically imports **the existing** `app_session_claim.mjs` only in future `--apply` mode. The already-successful A–E runner uses the same helper. Do not copy an alternative helper.

## Offline-only selftest (approved for preparation/review)

From inside `staging-acceptance`:

```powershell
node --check .\toolkit_cleanup_exact9.mjs
node --test .\toolkit_cleanup_selftest.mjs
```

`run_toolkit_cleanup.ps1` defaults to checking an exact nine-row manifest **offline**. It refuses execution if the manifest has not yet been gathered.

## Getting the manifest — separate READ-ONLY step, no deletion

Open the existing Supabase project SQL Editor and run only `C3B7_MANIFEST_READ_ONLY.sql`.

**Required single result row:** `all_bucket_rows=9`, `all_bucket_pending_delete=9`, `all_bucket_synthetic=9`, `matched_count=9`, `pending_delete_count=9`. If any mismatch, STOP. Never run SQL UPDATE/DELETE or copy an object key from the database.

Copy the **JSON text** in the `manifest_json` result cell verbatim into this file on your local Windows PC (outside the Git repository):

`%LOCALAPPDATA%\BrokerWallet\C3B7\toolkit_cleanup_exact9_manifest.json`

The JSON intentionally includes only nine disposable test document UUIDs, their test account UUIDs, titles and timestamps; do not put it in Git/chat. There is no password, object key, token or signed URL. Create the directory if needed. Then run:

```powershell
.\run_toolkit_cleanup.ps1
```

Expected: `PASS: immutable nine-document scope validated locally...` and `NO NETWORK...`.

## Future real cleanup: NOT APPROVED BY THIS PACKAGE

**Do NOT run `-Apply` yet.** Real execution requires owner confirmation **after** the saved nine-row manifest has been reviewed against the live database and the Staging Worker flags have been rechecked. Both disposable mailboxes must genuinely belong to the operator. `-Apply` will:

1. Require typed confirmation `DELETE EXACT NINE TEST DOCUMENTS`.
2. Prompt for CURRENT Staging gate key and both disposable account passwords, hidden locally; it never reads stale staging keys from the environment.
3. Verify correct Staging gate (`401` without JWT) **before** claiming sessions.
4. Sign in A/B, check they are exactly the two owner IDs in the immutable manifest, then **claim** the Single Active Device sessions (displaces other sessions on those disposable accounts).
5. Call only `POST /toolkit-documents/remove` for exactly the eight allowlisted A document IDs and one B document ID. Stop on any unexpected status/`cleanupPending`/`alreadyRemoved`; no retries or fallback sweeps.
6. Report counts only; no email, document ID, object key, signed URL, password, JWT or staging gate key in terminal output.

**Evidence limit:** successful removal without `cleanupPending` confirms the Worker reports `bestEffortDelete()` and database tombstone finalization. This is not independent proof of an empty R2 object prefix. Separately authorized read-back of nine database `deleted` statuses, and if required an independently scoped R2 existence check, remain necessary. The client-side Worker `status` route merges `pending_delete` and `deleted`, so it is **not** valid proof of final tombstone.

Never activate the general Cron sweep (`TOOLKIT_DOCUMENT_SWEEP_MODE="on"`) to perform this exact-nine cleanup. The `dry_run` of that sweep was already completed and does not need repeating.

## STOP immediately when

- A/B mailbox ownership is uncertain, manifest is missing/malformed, wrong IDs/titles/buckets/ages, count !=9, extra Toolkit rows, unreviewed Worker version, any error, or non-test data appear.
- The Staging gate does not return `401` without JWT, or the account UID differs from the manifest.
- The Worker returns `cleanupPending` or `alreadyRemoved`, or a delete is ambiguous.
- You are asked to change a production/staging secret, Worker flag, database schema, RLS, or perform a cleanup sweep. Those are different checkpoints.
