# Cloud Documents — enabling the production Worker (needs the owner's explicit approval)

Why this is needed: the live production Worker (`r2-profile-upload`, version `96783f3d`, 2026-10-13) contains **no Toolkit code** and has **no `TOOLKIT_*` variable**. A request to
`/toolkit-documents` answers a plain 404 there. The staging Worker (`r2-profile-upload-staging`, version `d5102f8c`, 2026-10-20) has the module with
`TOOLKIT_DOCUMENTS_ENABLED = "true"` and `TOOLKIT_DOCUMENT_SWEEP_MODE = "off"`. The Supabase migration is already applied to the shared project; the production bucket
(`broker-wallet-media`) already exists. So production needs a **new Worker version**, not just a variable.

Status 2026-10-21: the source edits (step 2 under Before) and the app default ON are DONE. The deploy below was RUN on 2026-10-21 after the owner's specific approval (record: docs/CURRENT_CHECKPOINT.md, C3.4); before that the auto-mode permission classifier had refused the first wrangler
command as "[Production Deploy]" until that specific approval arrived. Every step below is a write to live infrastructure.

## Before

1. The owner runs the Worker tests (`node --test`) and the Flutter analyzer/tests for the touched files, and has seen the staging device gate pass for at least Combine PDFs
   (`staging-acceptance/run_c3_combine_device_gate.ps1`), or accepts deploying without it.
2. Source edits (a small diff in `cloudflare/workers/r2-profile-upload/wrangler.toml`, production `[vars]`):
   - `TOOLKIT_DOCUMENTS_ENABLED = "true"`
   - `TOOLKIT_DOCUMENT_SWEEP_MODE = "off"` (the file currently says `"true"`, an invalid value the code treats as off; correct it so the intent is readable)
   Leave the staging block alone.
3. Prove the artifact is the one staging ran: a local `versions upload --dry-run` of the same tree and a comparison of the module with the staging version
   (see the same-artifact notes in the owner's Cloudflare memory; compare etags only for uploads made close together).
   Lesson from 2026-10-21: build the candidate with the same wrangler copy the staging upload used. The bundle's esbuild header comments name that copy (16 lines differed between wrangler 4.136.3 and
   4.151.3), which changes the etag although the code is identical. The strongest proof is the module bytes: `wrangler init --from-dash <script> --no-delegate-c3`, run in an empty folder, downloads the
   modules a Worker is serving with GET requests only, and their sha256 can be compared.

## Deploy (the owner's established guarded procedure)

1. `wrangler versions upload --env "" --strict --tag toolkit-<hash> --message "Toolkit cloud documents (staging d5102f8c)"`: ONE non-GET (`POST .../versions`); it prints the
   preview URL `https://<first 8 hex of the version id>-r2-profile-upload.<subdomain>.workers.dev`.
2. Credential-free probes of the preview URL: `GET /toolkit-documents` must answer **401** `Missing or malformed Authorization header` (not 404); `GET /profile-image-url` still 401;
   an unknown route 404. Read the version back (`versions view <id> --json`): bindings include `TOOLKIT_DOCUMENTS_ENABLED = "true"`, the four existing secrets are still `secret_text`.
3. `wrangler versions deploy <id>@100% --env "" --message "..." --yes`: ONE non-GET (`POST .../deployments`).
4. Read production back: deployment status, the live version, and that `/toolkit-documents` answers 401 and the existing routes are unchanged.

## Roll back

`wrangler versions deploy 96783f3d-6557-437f-addc-658a8f252d0f@100% --env "" --message "rollback toolkit" --yes` restores the previous version in one POST. The Toolkit rows and
objects written meanwhile stay (they are account data); the routes simply 404 again.

## After

- The app default is ON (done 2026-10-21: `TOOLKIT_CLOUD_DOCUMENTS` default `true`; `--dart-define=TOOLKIT_CLOUD_DOCUMENTS=false` stays as the kill switch for a build that
  must not use it).
- One real-phone check per tool: create a document, uninstall, reinstall, sign in: it is listed, opens, and matches. The status line on each screen says what is happening.
- Before a STORE release: update the Privacy Policy, Terms and the Google Play / App Store data disclosures (documents, titles, sizes, formats, digests, storage in Cloudflare R2 and
  Supabase, retention until deleted or account deletion, tombstone metadata up to 180 days).
