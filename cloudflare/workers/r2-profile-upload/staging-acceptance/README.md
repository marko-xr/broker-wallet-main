# Owner media staging acceptance

An end-to-end check of the Owner private media routes on the **staging**
Worker (`r2-profile-upload-staging`, private bucket
`broker-wallet-media-staging`) against hosted Supabase. Run by the owner, in
the owner's own terminal, after the Owner media candidate is deployed to
staging. It never targets production: the runner refuses any URL that is not
`https://r2-profile-upload-staging.<subdomain>.workers.dev`.

It is not part of `npm test` (Node's default test discovery does not match
these file names) and needs no `npm install`: Node built-ins only.

## What it checks

`-Mode Full`:

| Section | Checks |
| --- | --- |
| gate | no key / wrong key: 403; key without a session or with an invalid token: 401; stops if the Owner routes are not deployed |
| database | a signed-in client cannot execute `confirm_owner_media_upload` or `confirm_offer_media_upload` |
| owner-authorize | missing id 400, unknown Owner 404 `owner_not_found`, an Offer id as an Owner 404, no row for a refusal |
| owner-image | JPEG, PNG, WebP: authorize → private PUT → confirm → listed in order → signed GET byte-identical; row ready; linked once in `owner_media` |
| owner-video | video authorize/PUT/confirm; server-measured duration; ranged reads (first 64 KiB, last 4 KiB) answer 206 with the right bytes; full GET byte-identical |
| owner-retry | repeated authorize, early confirm (409 `upload_incomplete`), repeated confirm, ready re-authorize, id reused for another Owner or size (409 `idempotency_mismatch`), withdrawal |
| owner-refuse | PNG declared as JPEG (422, `failed`, stays refused), photo > 10 MiB, video > 100 MiB, HEIC, PDF; optional video > 3:01 |
| owner-limit | ten items (nine photos, one video) at positions 0–9; the eleventh refused (409 `owner_media_limit_reached`, no row); after one removal it is appended at position 10 |
| owner-remove | ready item tombstoned `deleted`, unlinked, bytes gone, repeat harmless, 410 `media_removed` afterwards; an uploaded-but-unconfirmed item withdrawn |
| offer | focused Offer regression: upload, repeated confirm, listing, signed GET, removal, 410, unknown Offer 404 |
| cross-parent | one account: an Offer's media on the Owner routes, an Owner's on the Offer routes, one Owner's on another Owner's — authorize 409 `idempotency_mismatch`, confirm/remove 409 `media_mismatch`, never listed; wrong-kind ids 404 |
| cross-account | account B: 404 on A's Owner (list, authorize, confirm, remove), 409 `media_id_conflict` on A's id, nothing readable through RLS, the database function refused; A's media untouched |
| profile | non-destructive: lookup, 401 without session, video refused, foreign `userId` 403, one authorize that is **never uploaded or confirmed**; the profile photo is compared before and after, never replaced |
| f1-seed | phase 1 of the F1 check (below) |

`-Mode F1Verify` (phase 2 of F1): at least 24 h 10 min after the Full run, with
the same two accounts. It first confirms every seeded abandoned upload is still
pending and old enough (otherwise it changes nothing and exits 3), then
authorizes on one entity at a time — A's first Owner, A's Offer, A's profile
image, A's second Owner — and checks each authorize withdraws only its own
entity's abandoned upload and leaves every other one (including account B's)
alone. Finally B withdraws its own seeded upload.

## What it creates and never does

- Uses two **fresh, disposable** accounts. Creates new Owner and Offer records
  whose names or notes start `staging-e2e <run id>`, and media only in the
  staging bucket. It never modifies or deletes a row it did not create.
- Never confirms a profile image, so no profile photo is replaced. It does
  leave one or two never-uploaded `pending_upload` profile rows on account A.
- Leaves its test records and media in place (the sweeps are off); nothing is
  cleaned up automatically.
- Prints and records PASS/FAIL, HTTP statuses, Worker codes and record/media
  ids only — never a key, password, token, email, account id, object key or
  any URL. Reports and the F1 state file go to `reports/`, which is gitignored.

## Run

From the repository root, in PowerShell 7:

```powershell
./cloudflare/workers/r2-profile-upload/staging-acceptance/run_owner_media_staging_acceptance.ps1 -WorkerUrl <staging workers.dev URL> -VideoPath <MP4 or MOV, ≤ 3:00, ≤ 100 MB>
```

Optional: `-LongVideoPath <video longer than 3:01>`.

Phase 2, a day later (the Full run prints the earliest time):

```powershell
./cloudflare/workers/r2-profile-upload/staging-acceptance/run_owner_media_staging_acceptance.ps1 -WorkerUrl <staging workers.dev URL> -Mode F1Verify -F1StatePath ./cloudflare/workers/r2-profile-upload/staging-acceptance/reports/f1_state_<run id>.json
```

The launcher asks for the staging gate key and both passwords with masked
input and clears them when the run ends.

Exit codes: 0 all passed, 1 at least one failure, 2 configuration error,
3 (F1Verify only) too early — nothing was changed.

`BW_E2E_OFFLINE_CHECK=1 node owner_media_staging_acceptance.mjs` checks the
local helpers and fixtures without any network access.

`fixtures/` holds three synthetic images (a 640×480 JPEG and PNG and a 1×1
WebP) made for these runs; the same files were used by the Offer media staging
acceptance of 2026-09-26.
