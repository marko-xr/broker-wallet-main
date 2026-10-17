# Plan attachment staging acceptance

An end-to-end check of the Offer and Owner land / plot **plan** routes on the
**staging** Worker (`r2-profile-upload-staging`, private bucket
`broker-wallet-media-staging`) against the hosted database that carries migration
`20261012233000_offer_owner_plan_attachments`. Run by the owner, in the owner's
own terminal, after that migration is applied and the Plan Worker candidate is
deployed to staging. It never targets production: the runner refuses any URL that
is not `https://r2-profile-upload-staging.<subdomain>.workers.dev`.

It is not part of `npm test` (Node's default test discovery does not match these
file names) and needs no `npm install`: Node built-ins only. The fixtures are built
in memory (`plan_attachment_fixtures.mjs`), plus the three photos in `fixtures/`.

## Run

From the repository root, in PowerShell 7:

```powershell
./cloudflare/workers/r2-profile-upload/staging-acceptance/run_plan_attachment_staging_acceptance.ps1
```

The launcher asks you to type `CLAIM` (see below), then takes the staging gate key
and both accounts' credentials from the same settings the Quotation launcher
reads (`BW_E2E_STAGING_KEY`, `BW_TEST_EMAIL` / `BW_TEST_PASSWORD` with
`BW_TEST_USER_ID`, `BW_TEST_B_EMAIL` / `BW_TEST_B_PASSWORD` with
`BW_TEST_B_USER_ID`), falling back to masked prompts, and clears its copies when
the run ends. The default staging URL is the one the Quotation launcher uses.

Exit codes: 0 all passed, 1 at least one failure, 2 configuration error.

## Single Active Device (session claim)

The database and the Worker refuse every session that is not the account's one
**active** Broker Wallet session, and a password sign-in creates a new, unclaimed
one. So the runner **claims** each session it signs in with, through the same RPC
the app uses (`app_session_claim.mjs`), and has the database confirm it before it
sends a request. **Claiming ends every other session of that account**: account A
is the designated test account, so a phone signed in as A is signed out. Use only
the designated and disposable test accounts, never a real user.

## What it checks

| Section | Checks |
| --- | --- |
| gate | all eight plan routes: no staging key or a wrong key 403; the key without a session or with an invalid token 401 (stops if a route is not deployed) |
| session-gate | on those eight routes: a claimed session is accepted (no write); a sign-in that never claimed is 403 `session_superseded` and displaces nothing; a session a newer one replaced is 403 `session_superseded` and cannot reclaim |
| offer-plan | empty read; authorize (one signed PUT for exactly `profiles/<uid>/offer-plans/<offer>/<media>.jpg`, no key in the answer); confirm before the bytes exist 409 `upload_incomplete`; confirm; repeated confirm; read with the exact bytes, a private link, no unsigned read; outside the gallery list and `offer_media`; the Offer's `version` and `updated_at` unchanged; a PDF replacement that cannot lose the JPEG (an unconfirmed upload, an XLSX and a PPTX renamed `.docx` refused 422 `media_type_mismatch`, a stale slot 409 `stale_replacement`); the valid replacement; the old object gone and its row retired; removal |
| owner-plan | the same for an Owner: DOC attached; an XLS and a PPT renamed `.doc` refused; DOCX replacing the DOC; removal; PNG replaced by WebP; removal |
| refuse | unsupported types, over-size images (10 MiB) and documents (25 MiB, refused at authorize with nothing uploaded), exactly-at-the-limit accepted, a PNG declared as a JPEG, missing `expectedMediaId` and record id, an unknown record, the cap of three waiting uploads |
| isolation | account B on A's Offer and Owner plans (read, authorize, confirm, remove: 404; A's media id 409 `media_id_conflict`; nothing readable through RLS); the other kind of record; another record of the same kind; a gallery file used as a plan (409 `media_mismatch`); no client can write a plan pointer or execute a plan function |
| regression | Offer and Owner gallery: authorize, PUT, confirm, list, signed read, link, removal, 410; one Quotation and one Profile route still answer |
| cleanup | every plan removed, every candidate withdrawn, every test Offer and Owner soft-deleted, and no media row this run made left outside a terminal state |

## What it creates and never does

- Creates new Offers and Owners whose names or notes start `staging-e2e <run id>`,
  and plan or gallery files only in the staging bucket. It never modifies or
  deletes a row it did not create, never confirms a profile image, and never
  deletes an account.
- Removes its plans and uploads through the Worker (the replaced or removed
  objects are deleted from the bucket by the Worker itself) and soft-deletes its
  test records, as the app does. The sweeps are off, so anything it could not
  remove is reported by id (`cleanup` section) instead of being swept.
- Prints and records PASS/FAIL, HTTP statuses, Worker codes and record and media
  ids only: never a key, password, token, email, account id, object key or any URL.
  The report goes to `reports/plan_attachment_<run id>.json` (gitignored).

## Fixtures

The photos are the synthetic images of the other runners. The PDF and the DOCX are
minimal and valid; the DOC is a compound file holding Word's own `WordDocument`
stream (the structure the Worker tells Word apart by), not a file saved by Word;
the XLSX, PPTX, XLS and PPT are Excel- and PowerPoint-shaped in the same two ways
(the package's main part type, the compound file's streams).

## Self-test (no network, no account)

```powershell
node cloudflare/workers/r2-profile-upload/staging-acceptance/plan_attachment_offline_selftest.mjs
```

It runs the real `worker.js` and this runner against an in-memory Supabase and R2
(the plan functions modelled from the migration), then injects faults (a client
that can write a pointer or call a plan function, leaking reads, a public bucket,
corrupted bytes, a bumped `version`, a plan stored as a gallery link, a missing
staging key, a gate that accepts a session that never claimed, and more) and
requires the runner to catch each one. `BW_E2E_OFFLINE_CHECK=1 node
plan_attachment_staging_acceptance.mjs` checks only the local helpers and fixtures.
