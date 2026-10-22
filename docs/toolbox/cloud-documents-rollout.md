# Toolkit cloud documents — design, security review and rollout (checkpoints C1 and C1.1)

**DEPLOYMENT STATE (C2D, 2026-10-20): the migration `20261019100000_toolkit_cloud_documents.sql` (LF SHA-256 `5b020380…0e71`) IS APPLIED
to the hosted Supabase project `rbvcnvqpdqrhywcgxkne` (shared by staging and production) and verified by a SELECT-only catalog
read-back (see `docs/CURRENT_CHECKPOINT.md`, C2D). The two tables are empty. NOT done: the Worker is not deployed with the Toolkit
routes, the flags are off (every route would answer 404), nothing in R2, no Flutter integration, no authenticated runtime test.**

Status of the source below: the design, review and plans in this document are as written for C1–C2C; sections that say "nothing
has been applied" describe the state before C2D.

Earlier status line (C1.1): the four tools still save only to their own local stores, no code outside
`lib/src/services/toolkit_documents/` imports the foundation, every Worker route answers 404, and the Flutter switch is off.

Product decision (owner, 2026-10-19): **Toolkit documents are cloud-backed account data; local storage is a cache and
an offline working layer.** A document made by Scanner, Combine PDFs, Images to PDF or Document Signature must be
recoverable after reinstalling Broker Wallet or on a new phone by signing in to the same Supabase account.
C1.1 decisions (owner, 2026-10-20): Scanner **JPEG and PNG** scans are backed up too, as the original bytes (no
conversion, no silent exclusion); **ownerless legacy** documents stay local and isolated, no recovery flow is authorized.

**What the owner must review before approving anything hosted** (the source is long, so these are the exact places):

| Subject | File | Read |
|---|---|---|
| The one migration (SQL, RLS, grants, functions) | `supabase/migrations/20261019100000_toolkit_cloud_documents.sql` | all; the header comment, the table, "Row level security and privileges", `authorize_…`, `purge_…`, "Privileges" |
| Worker contract and checks | `cloudflare/workers/r2-profile-upload/toolkit_documents.js` | `authorize`, `confirm`, `download`, `remove`, `runToolkitDocumentSweeps`, `toolkitLimits` |
| Formats and framing | `cloudflare/workers/r2-profile-upload/toolkit_content.js` | all (about 130 lines) |
| Flags and variables | `cloudflare/workers/r2-profile-upload/wrangler.toml` | the `TOOLKIT_*` block (production and staging) |
| Wiring | `cloudflare/workers/r2-profile-upload/worker.js` | `toolkitDocumentDeps`, `sha256HexOfStoredObject`, `signToolkitDocumentPut`, the route and `scheduled` hooks |
| The hosted rollback-only validation | `supabase/validation/toolkit_documents_validation.sql` | preflight, postflight (the body is the pgTAP file's assertions) |
| Client rules | `lib/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart`, `toolkit_library_reconciler.dart`, `toolkit_legacy_migration.dart` | the class comments |

---

## A. Migration and object inventory

`supabase/migrations/20261019100000_toolkit_cloud_documents.sql` — one file, no `begin`/`commit` (the runner supplies
the transaction), reversal SQL at its end.

**Tables**
- `public.toolkit_documents` — metadata of every document. Columns: `id` (device-chosen UUID, immutable), `owner_id`
  (→ `profiles`, `on delete cascade`), `document_type` (`scanner` | `combine_pdfs` | `image_to_pdf` | `signature`;
  the **source tool**), `content_type` (`application/pdf` | `image/jpeg` | `image/png`; the **binary format**, a
  separate field), `title`, `size_bytes`, `page_count`, `content_sha256` (**not null**, device-calculated),
  `sha256_verified`, `bucket`, `object_key`, `observed_etag`, `status`, `source_created_at`, `upload_attempts`,
  `last_authorized_at`, `confirmed_at`, `deleted_at`, `discard_claimed_at` (C2B), `created_at`, `updated_at`, `version`.
- `public.toolkit_document_account_state` — per-account `tombstone_floor` (internal bookkeeping, no role has access).

**Constraints on `toolkit_documents`** (the database refuses what the Worker should never send):
format in the three accepted MIME types; **images only from the Scanner**; size 1 B – 250 MiB for PDF and ≤ 64 MiB for
an image; an image is one page; digest is 64 lower-case hex; `object_key` = `profiles/<owner>/toolkit-documents/<id>.`
+ (`pdf` | `jpg` | `png` by `content_type`); `unique (bucket, object_key)`; title 1–200 characters, trimmed, no control or
bidi-override characters; status and timestamp coherence; `sha256_verified` only when not pending.

**Indexes:** `toolkit_documents_owner_idx (owner_id, created_at desc, id desc)`, `toolkit_documents_pending_upload_idx`,
`toolkit_documents_deleting_idx`. **Triggers:** `toolkit_documents_bump_sync_version` (existing function),
`toolkit_documents_guard_insert`, `toolkit_documents_guard_update` (`guard_toolkit_document()`).

**Functions** (all `SECURITY DEFINER`, `set search_path = ''`, except the two immutable helpers): `toolkit_document_rules`,
`toolkit_document_object_key(uuid, uuid, text)`, `guard_toolkit_document`, `authorize_toolkit_document_upload`,
`confirm_toolkit_document_upload`, `rename_toolkit_document`, `begin_toolkit_document_delete`,
`finalize_toolkit_document_delete`, `claim_abandoned_toolkit_document` (C2B), `discard_abandoned_toolkit_document`, `list_toolkit_documents`,
`get_toolkit_document`, `toolkit_document_statuses`, `toolkit_document_usage`, `list_toolkit_document_cleanup`,
`purge_toolkit_document_tombstone`.

**Policies:** `toolkit_documents_select_own` (select, `authenticated`), `app_session_gate` (restrictive, all).

## B. Grants, RLS, ownership — and why it holds

**Verified read-only on the hosted project (2026-10-20, SELECTs only):**
- Function and table owner is `postgres` (not a superuser, **`BYPASSRLS` = true**); `anon` and `authenticated` are
  `NOLOGIN` and `BYPASSRLS = false`; `service_role` is `BYPASSRLS`, `NOLOGIN`.
- Default privileges for objects created by `postgres` in `public` grant **tables** `arwdDxtm` and **functions** `X` to
  `anon`, `authenticated` and `service_role` **explicitly**; the current default function ACL has **no PUBLIC entry**
  (C2A re-read it; C1.1's "plus PUBLIC" was wrong, although two older trigger functions, `bump_sync_version` and
  `set_updated_at`, do carry PUBLIC execute from when they were created). So every new function is executable by
  `anon` and `authenticated` until it is revoked, which is why the migration revokes from `public, anon, authenticated`
  on every function (PUBLIC included, as a precaution) and why a read-back must check it.
- The existing server-only function `confirm_offer_plan_upload` has ACL `{postgres=X/postgres,service_role=X/postgres}`,
  `prosecdef`, `search_path=""`: the migration produces exactly that shape. No table has `FORCE ROW LEVEL SECURITY`.
- The only `SECURITY DEFINER` functions in `public` that clients can execute today are `claim_current_app_session`,
  `is_current_app_session`, `release_current_app_session` and `save_quotation`; none is new here.

**How this design uses it**
1. **Definer context.** A `SECURITY DEFINER` function runs as its owner (`postgres`), which bypasses RLS and holds the
   table privileges. RLS therefore does **not** protect these functions; the protection is (a) who can `EXECUTE` them and
   (b) the checks inside them. Every function takes the verified account id as `p_user_id` and filters on it
   (`owner_id = p_user_id`), and `EXECUTE` is granted to `service_role` only. A client token cannot call them
   (`permission denied for function …`, tested as `authenticated` and `anon`).
2. **The Worker always calls with the secret key and no user token** (`supabaseServiceFetch` sends only `apikey`). Supabase
   documents that a secret/service key bypasses RLS only when no user access token is attached; a request carrying one runs
   under that user's policies.
3. **`service_role` has no table privilege at all.** Postgres checks table grants before RLS, so a missing grant is a hard
   error even for `service_role` (Supabase documents this); the Worker never touches the table, only the functions, which is
   what the migration enforces by revoking `service_role` from both tables.
4. **`authenticated` can only `SELECT`** a column list (no `bucket`, `object_key`, `observed_etag`, `upload_attempts`,
   `last_authorized_at`), rows where `owner_id = auth.uid()` **and** `status = 'ready'`, and only with a current Single Active
   Device session (restrictive `app_session_gate`). It has no INSERT / UPDATE / DELETE grant. `anon` has nothing.
5. **Not `FORCE ROW LEVEL SECURITY`, on purpose.** The table owner has `BYPASSRLS` on the hosted project, so forcing adds no
   protection against it, and the client roles are not owners so RLS already applies to them. Forcing would only risk
   breaking the definer functions on any database whose owner lacks `BYPASSRLS` (and no existing table forces it).
6. **Owner cannot be reassigned.** `guard_toolkit_document()` freezes `id`, `owner_id`, `document_type`, `content_type`,
   `bucket`, `object_key`, `size_bytes`, `content_sha256`, `source_created_at` and `created_at` for **every** role (so a
   server-side mistake cannot move a document), allows only forward status changes (`deleted` is terminal), and lets
   `sha256_verified` change only at the moment a document becomes ready. It also refuses any client role outright.
7. **Idempotent mutation rights.** authorize / confirm / rename / delete are keyed on the device-chosen id; a second caller
   (another account) gets the same answer as an unknown id, `id_unavailable`, `not_found`, or a silent "already removed".
8. **Key and bucket secrecy.** The column grant above, the Worker never returns a key, and a signed URL is minted only by the
   Worker and never stored.
9. **Fixed search path.** Every function sets `search_path = ''` and schema-qualifies every object, as the Supabase function
   guidance recommends for `SECURITY DEFINER`.
10. **Default-grant independence.** The migration explicitly revokes and grants, so it does not depend on Supabase's default
   Data API grants, which Supabase has announced it is tightening for new tables (changelog 45329).

Sources: [Database functions](https://supabase.com/docs/guides/database/functions),
[Securing your API](https://supabase.com/docs/guides/api/securing-your-api),
[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Breaking change: tables not exposed to the Data API automatically](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).

Tested (emulated, see L): every function not executable by `anon` / `authenticated`; direct INSERT / UPDATE / DELETE /
column reads refused as `authenticated`; `anon` refused; a superseded session reads nothing; cross-account probes;
identity frozen; forged extensions refused by the table; 28 deliberate SQL mutations make the file fail.

## C. Worker routes, authorization and flags

All routes: `Authorization: Bearer <Supabase access token>`; the Worker verifies it with Supabase Auth, then the Single
Active Device gate (`is_current_app_session` with that token), and only then runs. The account is the verified token's
account, never a body or query field. Unauthenticated → 401, replaced session → 403 `session_superseded`, gate unavailable
→ 503. **Every route answers the same 404 as an unknown path unless `TOOLKIT_DOCUMENTS_ENABLED` is exactly `"true"`**
(`"false"` in `wrangler.toml`, production and staging); the sweep needs `TOOLKIT_DOCUMENT_SWEEP_MODE` (`off`).

| Route | Body → answer |
|---|---|
| `POST /toolkit-documents/authorize` | `{documentId, documentType, contentType, title, contentLength, contentSha256, sourceCreatedAt, pageCount?, acknowledgeStale?}` → `{status:"pending", presignedUrl, expiresInSeconds:300}` or `{status:"ready", alreadyConfirmed:true}` |
| `POST /toolkit-documents/confirm` | `{documentId}` → `{documentId, version, sha256Verified}` (+ `alreadyConfirmed`) |
| `GET /toolkit-documents?limit&cursor&documentType` | → `{documents[], nextCursor, usage?, limits?}`; each document has `documentType`, `contentType`, `contentSha256`, `sha256Verified` |
| `POST /toolkit-documents/status` | `{documentIds[≤50]}` → `{documents:[{documentId,state,version}], unknownIds[]}` |
| `GET /toolkit-documents/download?documentId` | → metadata incl. `contentType`, `contentSha256`, `sha256Verified` and a 900 s signed `url` |
| `POST /toolkit-documents/rename` | `{documentId, title, expectedVersion}` → `{title, version}` or 409 `stale_version` |
| `POST /toolkit-documents/remove` | `{documentId}` → `{removed:true, alreadyRemoved?, cleanupPending?}` |

Codes: `unsupported_media_type`, `unsupported_document_type`, `document_too_large` (413), `invalid_request`,
`invalid_title`, `document_deleted` (410), `document_not_found`, `document_id_unavailable`, `idempotency_mismatch`,
`document_mismatch`, `stale_document` (409), `storage_limit_reached`, `document_limit_reached`,
`too_many_pending_uploads` (429), `rate_limited` (429 + `Retry-After`), `upload_incomplete`, `upload_rejected`,
`media_type_mismatch`, `integrity_mismatch` (422), `stale_version`, `object_missing`, `object_changed`,
`document_not_ready`, `deletion_in_progress`, `session_superseded`, `session_check_unavailable`.

Variables (all optional): `TOOLKIT_DOC_MAX_BYTES` (PDF), `TOOLKIT_DOC_MAX_IMAGE_BYTES`, `TOOLKIT_DOC_MAX_ACCOUNT_BYTES`,
`TOOLKIT_DOC_MAX_ACCOUNT_DOCUMENTS`, `TOOLKIT_DOC_MAX_PENDING`, `TOOLKIT_DOC_MAX_NEW_PER_HOUR`,
`TOOLKIT_DOC_MAX_ATTEMPTS`, and `TOOLKIT_DOC_VERIFY_SHA256` (`"true"` = hash on confirm; unset = off).

## D. Formats and the integrity contract

**Formats.** PDF, JPEG, PNG; the extension is derived from the verified content type, never from a client file name, MIME
label or key. The Worker refuses: an unknown or parameterised MIME (`image/jpeg; charset=…`, upper case), an image from a
PDF tool, an image page count other than 1, and a size above the per-format limit — all before any row exists. Nothing is
converted or guessed.

**What "ready" requires (minimum server-side checks, all in the Worker, then recorded by `confirm_toolkit_document_upload`):**

| # | Fact | Established by | Recorded as | Trust |
|---|---|---|---|---|
| 1 | The object exists | R2 `head` | (precondition) | server-verified |
| 2 | Byte length equals the authorized length | R2 `head.size` | `size_bytes` (frozen) | server-verified |
| 3 | Stored content type equals the declared one, exactly | R2 `head.httpMetadata.contentType` (C2B: the signature does NOT cover Content-Type; this check is what protects it) | `content_type` (frozen) | server-verified |
| 4 | The leading bytes identify the declared format | ranged read of 32 bytes | (precondition) | server-verified |
| 5 | The file is a complete container: PDF `%PDF-1.x`/`2.x` … `%%EOF` in the last KiB; JPEG `FF D8 FF` … `FF D9` (≤ 16 padding zeros); PNG signature, 13-byte `IHDR` with sane size, exact `IEND` | ranged reads of the first and last bytes | (precondition) | server-verified **container**, not decoding |
| 6 | Object identity | R2 ETag | `observed_etag` | **identity token only, never a digest** |
| 7 | SHA-256 of the stored bytes equals the device's | Worker, `crypto.DigestStream` over the R2 body, only when `TOOLKIT_DOC_VERIFY_SHA256 = "true"` | `sha256_verified = true` | **server-verified cryptographic digest** (otherwise false) |
| 0 | SHA-256 of the local file | the app, before upload (required by authorize) | `content_sha256` | **client-calculated claim** |

A failed check 2–7 deletes the stored object and leaves the document pending (the device can upload again); check 1 answers
`upload_incomplete`. A polyglot (one format's start with another's ending) fails check 4/5. Not checked: that the image or
pages decode, that nothing malicious is embedded, and — when the flag is off — that the bytes equal the device's digest.

**Download.** The Worker re-reads the object's head: size and ETag must still be the verified object's (a signed PUT can
outlive a confirmation by minutes), else `object_changed`. The **app always verifies**: size, the SHA-256 recorded at upload,
and the format's container check, into a `.part` file that becomes the library file only if all pass; a mismatch is deleted
and reported. So corruption in storage or transit is detected even when `sha256Verified` is false.

**What is and is not claimed.** `sha256Verified = false` means "device-declared only", not "wrong". A device can declare the
digest of other bytes, which only harms its own account. This is **not end-to-end cryptographic verification** and not
tamper-proofing against anyone with R2 write access: nothing here is signed or encrypted by the user.

**Server-side SHA-256 feasibility.** Streaming an R2 object through `crypto.DigestStream` is native and needs no buffering.
Measured on this machine with the real `workerd` (1.20260921.1, `nodejs_compat`, compatibility date 2024-11-01): 1 MiB and
50 MiB produced digests identical to Node's `crypto`, 50 MiB in about 0.4 s wall time. That is **not** a measurement of
Cloudflare's billed CPU time or of R2 read latency; the Free Workers plan allows 10 ms CPU, so verification needs a plan
with a larger limit (not known here). **Recommended design for review:** keep the flag off in code; turn it on in **staging**
first with 25–50 MiB test files and read the Worker's CPU time in the logs; enable it in production only if CPU and latency
are comfortably inside the limit, otherwise keep client-side verification (items 0 and download) as the integrity story.

## E. Object key and account-prefix compatibility

`profiles/<verified account id>/toolkit-documents/<document id>.<pdf|jpg|png>`. Built by the Worker from the verified account
id, the document UUID and the verified content type; compared with the key stored on the row (and pinned by the table CHECK)
before anything is read, signed or deleted; never returned to the client. It is inside `profiles/<uid>/`, which Delete
Account lists and removes (`account_deletion.js` `removeAccountMedia` deletes the union of the account's `media_objects`
rows and its **whole prefix**, then proves the prefix empty). No change to `account_deletion.js`. Tests: keys inside the
account prefix and never another's; traversal, wrong extension, upper case, wrong segment and foreign-account keys are
rejected; a real `removeAccountMedia` run removes PDFs, JPEGs and PNGs of the account and nobody else's.

## F. Lifecycle

**States** (app): `savedToCloud`, `savedLocallyPendingSync` (**not** protected against device loss — the UI must say so),
`syncInProgress`, `syncFailedRetryable`, `syncRejected`, `downloadRequired`, `downloadFailed`, `deletePending`,
`remoteDeleted`. `savedToCloud` is set only after the server's confirmation. Server states: `pending_upload → ready →
pending_delete → deleted` (and `pending_upload → pending_delete → deleted`).

**Upload.** The app hashes the local file and checks its container, then authorize (reserves a row; idempotent on the id;
refused while the account is being deleted; limits enforced under a per-account lock) → PUT to a 5-minute signed URL →
confirm. Every step is retryable: offline before the PUT, loss after the PUT, a lost confirm response (the next authorize
answers "already ready"), force-stop (the journal resumes), token expiry, rate limit (`Retry-After`), replaced session
(paused until sign-in), account switch (nothing is sent), rename or delete during the upload.

**Deletion and tombstones — the nine scenarios**

| Scenario | Outcome |
|---|---|
| Remote delete during an upload | The delete marks `pending_delete`; confirm answers 410; a late PUT is removed after the signed URL's lifetime; the id is tombstoned. On the device the delete flag wins between steps. |
| Repeated delete | Idempotent (`alreadyRemoved`). |
| Deleted document restored from an old cache | The journal says it reached the cloud, so it is never uploaded; the reconciler shows `remoteDeleted` and keeps the local copy for the user. |
| App restored from an old backup | These folders are excluded from backup; if a copy comes back some other way, a document without a journal entry goes to authorize: within retention the tombstone answers 410; after retention the **tombstone floor** answers 409 `stale_document` — it is not re-created without the user's explicit acknowledgement. |
| Long-offline client | Documents created before the account's floor need the same acknowledgement; later ones do not; a document that reached the cloud before is never re-uploaded. |
| Same account on a new phone | The cloud library lists everything; documents are `downloadRequired` and verified when opened. The old phone's never-synced documents stay on the old phone. |
| Session replaced (Single Active Device) | `session_superseded` pauses the queue until the user signs in again; the Worker and the RLS gate both refuse. |
| Delete Account while uploads are pending | authorize answers 409 `deletion_in_progress`; the app stops (not retried). The in-flight signed PUT (≤ 5 min) is covered by the deletion's own window and prefix sweep. The app must also clear the journal and cache on account deletion (C2: `deleted_account_local_data_cleaner`). |
| R2 objects left by an interrupted operation | Abandoned uploads (idle 24 h): claimed first (C2B: `pending_upload → pending_discard`, so the row can never become ready), then the object is removed, then the row for that exact claim (no tombstone); half-finished deletes: finished by the sweep after the URL lifetime; the whole prefix is the backstop at account deletion. An object with no row cannot arise from these flows. |

**Tombstone retention and the floor (replaces "180 days and hope").** Deleting writes a tombstone (title scrubbed to
"Deleted document"). Tombstones older than 180 days are purged; **purging advances the account's `tombstone_floor`** to the
deletion time (never backwards). A new document id with no row whose device creation time is ≤ the floor is refused as
`stale_document` unless `acknowledgeStale` is sent (only after the user explicitly agrees). So an expired tombstone cannot
silently resurrect a deleted document. History is **bounded**: at most **500 tombstones per account** (older ones are purged
immediately and advance the floor the same way), roughly 0.5–1 MiB worst case per account; hourly creation limits still
apply to churn. The honest cost is that an account that has purged history will ask the user once for old, never-backed-up
documents. This relies on the device clock for `sourceCreatedAt`; a wrong clock can only make an honest device ask or skip
asking about its own documents.

## G. Recommended initial operational limits (NOT final — the owner decides)

These are **anti-abuse and storage-safety limits, not subscription entitlements**; no RevenueCat or plan enforcement is
introduced. They are Worker variables with hard ceilings enforced again by the database.

| Limit | Recommended default | Hard ceiling | Why |
|---|---|---|---|
| PDF | 50 MiB | 250 MiB | Typical contracts, scans and signed PDFs are 1–20 MB; 50 MiB covers almost all. Larger local PDFs stay local and say so (`syncRejected`). |
| Scanner image (JPEG / PNG) | 25 MiB | 64 MiB | A 300-dpi A4 PNG is about 5–25 MB; a JPEG 1–8 MB. Images are one document per page, so counts grow faster than bytes. |
| Per account | 1 GiB | 20 GiB | About 100 large PDFs or 1,000+ image pages; bounded cost per account. |
| Documents per account | 1,000 | 5,000 | Image scans are one document per page. |
| Pending uploads | 5 | 20 | Bounds reservations and abandoned uploads. |
| New documents per hour | 120 | 1,000 | A 100-page scan session is legitimate; it is a burst limit, not a quota. |
| Authorizations per pending upload | 10 | 100 | Stops endless retries of one upload. |
| Tombstones kept per account | 500 | — | Bounds history (section F). |

Compared with C1's proposal (100 MiB / 2 GiB / 500 / image-agnostic) this halves the per-file and per-account bytes, adds a
separate image cap and doubles the document count. Trade-offs: a lower PDF cap rejects some large combined PDFs (they remain
local); a higher document count costs database rows.

**Cost (assumptions to verify on the providers' pricing pages; not checked live).** R2 Standard ≈ USD 0.015 per GB-month,
free allowance 10 GB-month, 1 M writes, 10 M reads, no egress fee. At the per-account cap: 20 pilot accounts ≈ 20 GiB ≈
USD 0.15/month; 200 accounts full ≈ 200 GiB ≈ USD 2.85/month; 1,000 full accounts ≈ USD 14.85/month. Operations are far
inside the free allowance (an upload is 1 write and 3 small reads; a download 2 reads; deletes are free). Database: the hosted
database is **16 MB** today. **C2A corrected C1.1's estimate**: the earlier "≈ 3 kB per row, so the database is the first
ceiling at about 100 full accounts" was an unmeasured extrapolation from a 90-row table and is withdrawn. Measured on
the local PostgreSQL storage format with 10,000 synthetic rows and the real indexes: **about 770 bytes per document** (765 and 774 in two runs; heap
432 + indexes 338), so a full 1,000-document account is under 1 MB and 100 full accounts are about 77 MB (about 155 MB with
a 2× churn allowance) of the Free plan's 500 MB **database** allowance (which is unrelated to R2 file storage). These remain
estimates, not a verified capacity limit; R2's free 10 GB is reached first. See section T. No plan change, no paid
branch, no unlimited uploads are proposed.

## H. Existing account-scoped documents (migration policy)

`ToolkitLegacyMigration.plan` (pure) selects what may be queued; the migration itself is C2 and not built. Originals are
**never moved, rewritten or deleted**; the cloud copy is verified (server confirmation, size, digest, container) first and
removing the local copy is the user's own act. A document is eligible only if its tool folder is the **current** account's
(`<root>/<account>/`, using the stores' exact folder-name rule) **and** that folder's `index.json` records the same owner,
it has a UUID id (which becomes the cloud id), it is a PDF (any tool) or a JPEG/PNG from the Scanner, and it is within the
size limit. Re-runs find the same ids (`alreadyInCloud`) and cannot duplicate. Anything else is reported with a reason, not
hidden: `unsupportedType`, `tooLarge`, `invalidId`, `fileMissing`, `ownerless`, `otherAccount`. Progress ("Backing up 3 of
12 documents"), a per-document retry, and the "not yet protected against device loss" message are C2 UI.

## I. Ownerless legacy documents (owner decision, preserved)

Ownerless legacy Toolkit documents (a folder or index that records no owner, for example the old device-wide signed
documents) are **kept locally and isolated**: never deleted, never auto-uploaded, never assigned to whoever signs in, never
shown in another user's library, and a matching file name or title is never treated as proof of ownership. The planner
returns `ownerless` for them whatever account is signed in and in every format, and `otherAccount` for a folder or index
that names someone else. **No recovery operation is authorized.** A future, explicit, user-authorized recovery flow would
need its own design and approval.

## J. Hosted validation and staging sequence (each step needs the owner's separate approval)

0. The owner approves this exact migration file, the Worker contract, the key shape, the limits and this plan. Any later
   change to the SQL restarts the review.
1. Baseline: read-only snapshot of the hosted schema and privileges (the digest recipe) — nothing written.
2. Run `supabase/validation/toolkit_documents_validation.sql` as one rollback-only request (the `\set` line a comment, the
   `\ir` line the migration's LF text). It must end with `…_ROLLBACK_SOURCE_PASS` and `…_ROLLBACK_RESTORED`. **Any failure
   → STOP** (classify as "validation script assumption / blocked before apply"), no apply, no edit without approval.
3. Apply the one migration from a scratch project holding the already-applied migrations plus this exact file
   (`db push --linked`). Staging and production share the Supabase project, so the empty tables exist in production at once.
4. Read-back (SELECT only): columns, constraints, indexes, policies, `pg_proc` bodies/ACLs/owners (`proacl` must be exactly
   `{postgres=X/postgres,service_role=X/postgres}`), table ACLs (`toolkit_documents`: `authenticated` column `r` only;
   `toolkit_document_account_state`: none), and every other object unchanged.
5. Deploy the Worker to **staging only**, flag `"false"`: every `/toolkit-documents*` route must answer 404.
6. Set the staging flag `"true"` and the sweep to `dry_run`; optionally `TOOLKIT_DOC_VERIFY_SHA256 = "true"` for the CPU
   measurement with a 25–50 MiB file.
7. Staging acceptance runner (to be written in C2): two accounts; PDF, JPEG, PNG upload → confirm → list → download →
   rename → remove; forged MIME / extension / polyglot; cross-account probes; limits; replaced session; tombstone purge and
   `stale_document`; Delete Account with PDF, JPEG and PNG objects present (all removed).
8. Owner device acceptance on a build with `--dart-define=TOOLKIT_CLOUD_DOCUMENTS=true` (section M).
9. Privacy Policy, Terms and store data disclosures updated (owner-approved wording) **before** production.
10. Production Worker with the flag `"false"`, then `"true"`; sweep `dry_run` → inspect counts → `on`.

## K. Rollback and stop conditions

**Stop** (do nothing further, report) on: any validation failure; a migration that differs from the approved file; a
read-back with a function executable by `anon` or `authenticated`, a table privilege for `service_role`, or an unexpected
change to another object; staging bound to production; Worker routes answering anything but 404 while the flag is `"false"`;
any cross-account read in staging; a Delete Account that leaves Toolkit objects; Worker CPU near its limit with digest
verification on.

**Rollback:** set `TOOLKIT_DOCUMENTS_ENABLED` to `"false"` (routes 404) and ship the app with the build flag off — documents
are still on the phones because the local stores are untouched until the migration is verified; roll the Worker back to the
previous version; the tables and functions are inert without the routes. The reversal SQL is at the end of the migration;
**export first**, because dropping the tables does not remove R2 objects (they stay until Delete Account's prefix sweep or a
manual cleanup).

## L. Evidence levels and results

Levels: **CODE_PROVEN** = source plus a local run; **EMULATED** = a local PostgreSQL engine (PGlite 17.5) with Supabase
stand-ins and an emulated pgTAP — not Supabase, not real pgTAP; **VERIFIED_HOSTED** = observed on the hosted project. Only
the read-only inspections below are hosted; nothing else is.

| Evidence | Result |
|---|---|
| Hosted read-only (SELECT): migration history = repository (18), no Toolkit objects, roles/default ACLs/function owners/forced-RLS, DB size 16 MB | VERIFIED_HOSTED (read-only) |
| pgTAP file `supabase/tests/toolkit_documents_test.sql` on the full migration chain | EMULATED: 165/165 assertions; 28/28 deliberate SQL mutations make it fail |
| Rollback-only validation script (same assertions, pg_temp helpers, preflight/postflight) | EMULATED: `_SOURCE_PASS` and `_RESTORED`, 275 statements; mutated runs fail |
| Worker module against the real migration SQL through a thin RPC adapter | EMULATED: 38/38 end-to-end checks (formats, forged content, digest verification, floor, sweeps) |
| Worker tests `toolkit_documents.test.mjs` (61) + `toolkit_content.test.mjs` (7) | CODE_PROVEN: 68/68; 38/38 deliberate Worker mutations fail them |
| Existing Worker regression (account deletion, session, claim, staging gate, offer/owner media, plan attachments, quotation media) | CODE_PROVEN: 206/206 (run because `worker.js` changed) |
| `crypto.DigestStream` in a real local `workerd` | CODE_PROVEN: 1 MiB and 50 MiB digests equal Node's; about 0.4 s for 50 MiB; not Cloudflare CPU billing |
| Flutter scoped analyzer (foundation and its tests) | CLEAN |
| Flutter `test/toolkit_documents` | CODE_PROVEN: 158/158; 20/20 (C1) + 12/12 (C1.1) deliberate mutations fail them |
| `git diff --check`, `dart format --set-exit-if-changed` on the new Dart files, scan for hidden bidi characters | clean |
| Real Supabase / PostgREST / pgTAP, real R2, a signed PUT from a phone, Cloudflare CPU, any device, any UI | **NOT VERIFIED** |

Not run: the full Flutter suite, any build, any hosted write, any Worker deploy.

## M. Samsung and cross-device acceptance criteria

On a Samsung phone, Arabic and English, RTL, dark mode, large text, with a staging build: (1) one document from each of the
four tools, plus a Scanner JPEG and a PNG scan; "not backed up yet" until the confirmation, "saved to cloud" only after it;
(2) airplane mode: saved locally, shown as pending, uploaded on reconnect, no duplicate; (3) force-stop during an upload,
reopen: it resumes; (4) uninstall, reinstall, sign in: the library lists all documents as cloud-only, opening downloads and
verifies, share and export use the local file; a corrupted download (simulated) leaves no file; (5) a second phone with the
same account: signing in there supersedes the first, the library matches, a rename appears, a delete on one removes it on the
other and it never returns; (6) another account on the same phone sees none of them; (7) fill the free space: the download
fails cleanly; (8) a file above its limit and the account limit show their own messages; (9) Delete Account removes the
documents (confirmed in the staging bucket); (10) nothing in logcat names a title, URL or key.

## N. Flutter integration points (C2, not done)

Per tool the adapter is small: `ToolkitLocalFiles.resolve(entry)` via the store's `fileOf(document)`; after a verified save,
`coordinator.enqueue(ToolkitSyncEntry(contentType: …))`; the library merges `repository.listAll()`, the journal and the local
documents with `ToolkitLibraryReconciler`; opening a cloud-only document goes through `ToolkitDocumentDownloadService`;
rename and delete go to the store and the coordinator (the local file is removed only after `ToolkitSyncOutcome.deleted`);
hashing should run off the UI isolate (the coordinator takes a hasher); the download cache and the journal must live in
folders excluded from Android backup / device transfer and iPhone backup and be cleared on Delete Account. A `staleDocument`
rejection needs a dialog and `retry(id, acknowledgeStale: true)`.

## O. Ownership, privacy and legal (not changed here)

Not end-to-end encrypted; the local cache is not encrypted. Provider-side encryption at rest and TLS in transit are
Cloudflare's and Supabase's (wording to be confirmed against their documentation). The Privacy Policy, Terms and the Google
Play / Apple data disclosures must be updated before enabling (documents, titles, sizes, formats, digests, storage in
Cloudflare R2 and Supabase, retention until deleted or account deletion, tombstone metadata up to 180 days). Existing legal
decisions stand until the owner approves new wording.


---

# C2A — Final hosted preflight and exact migration approval (2026-10-20)

Status: **READY FOR OWNER SQL APPROVAL.** This checkpoint ran **SELECT-only** statements on the hosted project and local
(emulated) checks. It executed no rollback-only transaction, applied nothing, deployed nothing, wrote nothing to R2 and
changed no tracked source: the migration, Worker and Flutter files are byte-identical to C1.1. The C1.1 tests were NOT
re-run (C1.1 results above are historical). Two documentation statements from C1.1 were found wrong and are corrected
in place (sections B and G): the default-privilege wording and the database-capacity estimate.

## P. The immutable candidate (hashes)

`git` stores LF and the working tree is CRLF, so each file has two hashes. **The LF hash is the canonical one**: it is
what `supabase db push` sends and what the hosted validation text embeds. The CRLF hash is what `sha256sum` prints for
the file in this checkout.

| File | SHA-256 (LF, canonical) | SHA-256 (working tree, CRLF) |
|---|---|---|
| `supabase/migrations/20261019100000_toolkit_cloud_documents.sql` (1,079 lines) | `88ceb6c2f8f6b62b9bbec73e6932f3843b333a13c114425b7ef7eaad20d5ad4d` | `87227b3199c492e58e9581f14cfa297c62142a92d47187495b0327c1e1ff62f3` |
| `cloudflare/workers/r2-profile-upload/toolkit_documents.js` | `e98e828eb9b8a5a40408dea2afeb3f8cb6af45a0ce354f1f8eb8b73745862599` | `867da9081af9d42596fc8cf6b93c7e113db2f5048f54c5963c91c610e4053f59` |
| `cloudflare/workers/r2-profile-upload/toolkit_content.js` | `26a8ebceff8f2ac5f386c38e522c2fc7b6396cbeb4629fcc9905cb9f9eb93cce` | `e87e7a577bb1459e95ca7b4932b91617e67454b50372b600263c50117b46bd1b` |
| `cloudflare/workers/r2-profile-upload/worker.js` (entrypoint; additive diff only) | `a57c2e4d1a56d06af47258ed1416b589ca813e96499fca525e54a1f5fe506576` | `ee209edfb9e4bdcb27983419a73b85f1b18ff43aa1c8f2bc72d95edbe8d431c7` |
| `cloudflare/workers/r2-profile-upload/wrangler.toml` (flags) | `19854f3450e04c5481ff0f8fa157b318d4738fab0b477cb5c703ae2912af8aff` | `129fbb4c478fb2647f208668578f568066cc6227bed0dbea8f8437e79e3fc013` |
| `supabase/tests/toolkit_documents_test.sql` | `98496b72967fd98bc0be0f493483a71b8d868fbf621a9eecadd45ba684b419b7` | `f2a025b3d35ebbebd134dcb8069d565295deda3c44ba740c2a89eb403896d0ef` |
| `supabase/validation/toolkit_documents_validation.sql` | `80621c33fbdb6f8ee3a920b1675c5f3c20db49b572964d662025c95314ff78a1` | `767e68b93e70ef5e520ad2c32b6fafcfcf214343f5e52ef9f812953ec47bb213` |
| Derived: the single hosted validation request (`hosted_toolkit_validation_request.sql`, 105,007 bytes) | `c66e4504ec39573a76f314ec6e50fbd1a183926b90d6266bea3190668d648006` | n/a (generated, LF) |

Branch `toolkit-cloud-documents-readiness`, HEAD `08c8e24e13da6762a6fa2cd48928165451791cf1`; nothing committed. Any change
to the migration restarts the review and changes these hashes.

**DDL inventory (what the migration creates; it modifies nothing that exists).** Two tables (`toolkit_documents`,
`toolkit_document_account_state`); six indexes (two primary-key indexes, the unique `(bucket, object_key)` index, and
`toolkit_documents_owner_idx`, `toolkit_documents_pending_upload_idx`, `toolkit_documents_deleting_idx`); 22 named
constraints on the two tables (check, primary key, unique, and two foreign keys to `profiles`);
three triggers (`toolkit_documents_bump_sync_version`, `toolkit_documents_guard_insert`, `toolkit_documents_guard_update`);
two policies (`toolkit_documents_select_own`, restrictive `app_session_gate`) with RLS enabled on both tables; 15 functions;
table comments and function comments; `REVOKE` on both tables and all 15 functions; one column-level `GRANT SELECT` to
`authenticated`; `GRANT EXECUTE` to `service_role` on 14 functions. **It contains no `ALTER DEFAULT PRIVILEGES`, no
`CREATE`/`ALTER EXTENSION`, no schema, role, publication or event-trigger statement, and no statement that alters, drops or
updates any existing table, function, policy, trigger, index, constraint, row or the account-deletion tables.** It only
*references* three existing objects: `public.profiles` (foreign key, `on delete cascade`), `public.is_current_app_session()`
(inside the restrictive policy) and `public.bump_sync_version()` (the existing version trigger function). It does not touch
`media_objects`, `account_deletion_jobs`, the Delete Account Worker module (`account_deletion.js` has an empty git diff) or
any Worker route that exists today (`worker.js` changes are additions only: the import, the route hook, the scheduled hook
and three helpers). The migration file has no `begin`/`commit` and no DML.

## Q. Hosted baseline (read-only, 2026-10-20)

Project reference `rbvcnvqpdqrhywcgxkne` (name `broker-wallet`, the only linked project). The Supabase CLI's ephemeral
login role is the only hosted side effect. Nothing below reads a customer record: only schema metadata and row counts.

| Check | Hosted result | Expected / verdict |
|---|---|---|
| Migration history | 18 applied versions, `20260821000100` … `20261012233000`, names equal the repository's 18 files one for one; latest hosted version `20261012233000` < candidate `20261019100000` | matches; candidate is next |
| Toolkit objects | 0 relations / functions / types / policies / triggers / constraints / schemas / roles with `toolkit` or `tombstone` in the name, in any schema | none exist: no name conflict |
| Engine | PostgreSQL 17.6; database `postgres`; session role `postgres` (not superuser, `BYPASSRLS`, CREATEROLE/CREATEDB); size 16 MB; 7 extensions (citext, pg_stat_statements, pg_trgm, pgcrypto, plpgsql, supabase_vault, uuid-ossp); `pg_graphql`/`pg_net`/`pg_cron` **not** installed | as assumed |
| Roles | `anon`, `authenticated`: NOLOGIN, no BYPASSRLS; `service_role`: NOLOGIN, BYPASSRLS; `postgres` is a member of `anon`, `authenticated`, `service_role` with the SET option (the validation's `set local role` works) and **not** a member of `supabase_auth_admin` (the validation's account-deletion step then deletes as `postgres`, which holds DELETE on `auth.users`) | OK |
| Default privileges (`postgres`, `public`) | functions: `postgres, anon, authenticated, service_role` = EXECUTE, **no PUBLIC entry**; tables: `arwdDxtm` to all four; sequences likewise | confirms every new function is client-executable until revoked; **corrects C1.1's "plus PUBLIC" wording** |
| Ownership convention | all 34 existing `public` functions and all 37 tables owned by `postgres`; 21 of the functions are `SECURITY DEFINER`, and every server-only one has `search_path=""` and ACL `{postgres=X,service_role=X}` | the 15 new functions follow the same shape |
| Pre-existing PUBLIC execute | only `bump_sync_version()` and `set_updated_at()` (trigger functions from the baseline migration) carry `=X` | untouched by this migration |
| RLS | RLS enabled on all 37 public tables, none forced; every table except `user_active_sessions` has the restrictive `app_session_gate` policy plus per-operation own-row permissive policies; client table grants are SELECT-only on media-like tables (`media_objects`: `authenticated=r`) | the new table follows the same pattern |
| Table privileges (public, all tables) | `anon` 0 grants; `authenticated` 45; `service_role` 266 | existing tables give `service_role` full table access; the new tables deliberately do not |
| Foreign keys | owner/recipient columns reference `profiles(id)` `on delete cascade` (media_objects, offers, owners, …); `profiles.id` references `auth.users(id)` `on delete cascade` | the new table behaves the same: its rows disappear with the account |
| Account deletion | `account_deletion_jobs` (user_id, bucket, status, timestamps, attempts, last_error_code; no FK to profiles), Worker removes the union of `media_objects` rows and the whole `profiles/<uid>/` prefix, then proves it empty | unchanged by this migration |
| Event triggers | 6, all Supabase-managed (graphql placeholder, extension grants, `pgrst_ddl_watch`, `pgrst_drop_watch`); none rewrites or re-grants new tables | no hidden DDL side effect except the PostgREST schema reload |
| `auth.users` triggers | `guard_pending_phone_change`, `on_auth_user_created`, `on_auth_user_identity_updated`; no delete trigger | the validation's fixtures are safe |
| Counts (not records) | auth.users 2, profiles 2, media_objects 90, user_active_sessions 2, account_deletion_jobs 0 | the validation preflight needs none of them |
| Session limits | `statement_timeout` 120 s, `lock_timeout` 0 (the script sets 3 s), `max_connections` 60 | fine |

**Baseline digests (`hosted_baseline_snapshot.sql`, two identical runs).** The same SELECT is run again right after the
rollback-only validation (all values must be equal) and after the apply (equal except the Toolkit objects and one
migration-history row).

```
column_privileges 115 ee40d435073e8999a0b2e41f1fa7b7f9   default_acls 24 dae83c135fc0603023c5369d7fe43d81
event_triggers 6 e8256cecd87190e75b98bf66fb461263        extensions 7 7e67b32061ba72ba0f00175391c56424
migration_history 18 ff8411b7d7ebfb7e5ca8e92905bc3c61    public_columns 330 95daf8ee82d63b592b59b056b48f60a1
public_constraints 215 82cf74b1253aae3474c5f542257a24e5  public_functions 34 041ea5837eda11e3658ac8a56e8a7b40
public_indexes 119 094e8f980bfe2934b1908102db4dec65     public_policies 109 5e36de4b1e40ffe9ae189360c0efbc72
public_relations 157 c8a3de85d19d0c6940989760c0efcc1b    public_triggers 28 40afd81ae646b99da05a4495df34d1e8
realtime_publication 2 127a3fffa3274fb2040ceb3c612e9563  roles 7 f0c0cc0a907b53b876c83cba866fc499
schemas 12 8eab80b49723f568366cffc90e92a60b              toolkit_named_objects 0
row counts users/profiles/media/active_sessions/deletion_jobs = 2/2/90/2/0
```

No baseline assumption was false. One thing differs from what a reader might assume: the two accounts and 90 media rows
are real, so every assertion must stay fixture-scoped (the Toolkit validation only asserts on its own new tables and
fixture ids, and was replayed as assembled; see section T).

## R. Function privilege matrix (derived from the engine, not from comments)

Method: the exact migration was applied to the local PostgreSQL 17.5 engine (PGlite) after the 18 prior migrations, with
the default privileges made **hosted-faithful** (no PUBLIC execute on new functions), then `pg_proc`, `proacl`,
`has_function_privilege`, `aclexplode`, `has_table_privilege`, `has_column_privilege`, `pg_policies` and `pg_trigger`
were queried, and every function was **called** as `anon` and as `authenticated` with NULL arguments (privilege is
checked before arguments). Source property = true of the exact SQL on that engine. Hosted ACLs of the new objects exist
only after an apply and are listed under "after apply" below.

| Function | Mode / owner / path | Explicit ACL (`proacl`) | EXECUTE: PUBLIC / anon / authenticated / service_role | Live call as anon / authenticated | Relies on | Account identity | Exposes |
|---|---|---|---|---|---|---|---|
| `authorize_toolkit_document_upload` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw), account_state (r) | argument p_user_id (Worker-verified); every row read or written is filtered by it; a row of another owner answers `id_unavailable` | returns outcome, status, version only |
| `begin_toolkit_document_delete` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw) | argument p_user_id; owner-filtered | returns the document's own key to the Worker |
| `confirm_toolkit_document_upload` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw) | argument p_user_id; owner-filtered update | returns outcome, version only |
| `discard_abandoned_toolkit_document` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw) | argument p_user_id; owner-filtered | returns outcome only |
| `finalize_toolkit_document_delete` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw), account_state (rw) | argument p_user_id; owner-filtered | returns outcome only |
| `get_toolkit_document` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (r) | argument p_user_id; owner-filtered | own key and etag to the Worker (never forwarded to the client) |
| `guard_toolkit_document` | INVOKER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | n/a (trigger fn; no EXECUTE) / n/a (trigger fn; no EXECUTE) | none (reads NEW / OLD) | no | no |
| `list_toolkit_document_cleanup` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (r) | **no account argument: scans every account of one bucket, by design** | owner ids and object keys, to the Worker's sweep only |
| `list_toolkit_documents` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (r) | argument p_user_id; owner-filtered | metadata of the caller's own documents; no key, bucket or etag |
| `purge_toolkit_document_tombstone` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw), account_state (rw) | argument p_user_id; owner-filtered | returns boolean |
| `rename_toolkit_document` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (rw) | argument p_user_id; owner-filtered | returns outcome, title, version |
| `toolkit_document_object_key` | INVOKER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | none (calls rules) | argument (the Worker passes the verified id) | returns a key to the Worker only |
| `toolkit_document_rules` | INVOKER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | none | no | no |
| `toolkit_document_statuses` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (r) | argument p_user_id; owner-filtered | id, status, version only |
| `toolkit_document_usage` | DEFINER / `postgres` / `search_path=''` | `{postgres=X,service_role=X}` | no / no / no / yes | denied (42501) / denied (42501) | documents (r) | argument p_user_id | four numbers |

Reading the matrix:
- All 15 functions: owner `postgres`, `search_path=''` (verified in `proconfig`), no PUBLIC, `anon` or `authenticated`
  EXECUTE; 12 are `SECURITY DEFINER`; the two pure helpers (`toolkit_document_rules`, `toolkit_document_object_key`) and the trigger function are invoker. All 14 callable functions
  answered `42501 permission denied` to `anon` and to `authenticated`.
- `guard_toolkit_document()` also shows `service_role` EXECUTE: it comes from the default privileges (the migration
  revokes only `public, anon, authenticated` from it, like the existing `guard_plan_media_pointer`). It is a trigger
  function: calling it directly fails with `42804` (a trigger function cannot be used in FROM), so the extra grant is
  inert.
- **Static schema-qualification scan.** The bodies reference only `public.` and `pg_catalog.` objects (plus
  `auth.uid()` in the policy); no unqualified relation, and `search_path=''` would make any such reference fail at run
  time. The relations used by each function are listed in the "Relies on" column.
- **Table privileges.** `toolkit_documents`: owner `postgres` only; `anon`, `authenticated`, `service_role` hold no table
  privilege at all (checked for select/insert/update/delete/truncate/references/trigger). `authenticated` has a **column**
  SELECT on 15 of 21 columns; hidden: `bucket`, `object_key`, `observed_etag`, `upload_attempts`, `last_authorized_at`
  and `deleted_at`. No column is writable by `authenticated`. `toolkit_document_account_state`: no grant to anyone.
- **Policies.** `toolkit_documents_select_own` (permissive, SELECT, `authenticated`): `owner_id = (select auth.uid())
  and status = 'ready'`; `app_session_gate` (restrictive, ALL, `authenticated`): `(select is_current_app_session())` for
  USING and WITH CHECK. Both tables have RLS enabled, none forced (see section B).
- **Triggers.** version bump (existing function), insert guard, update guard. The guard freezes identity for every role.

**What clients can reach through the public Data API.** Tables: only `toolkit_documents`, only own `ready` rows, only
those 15 columns, only while the session is the current one (a superseded session reads nothing). Functions: none. The
Single Active Device gate cannot be bypassed because there is no write path and no function path; reads without a
current session return zero rows. A client can read its own title, size, format, digest and counts without the Worker;
it cannot read a bucket, a key or a signed URL, and cannot obtain bytes without the Worker.

**The one trust boundary.** The Worker's service key can call any function with any `p_user_id` (as it can for every
existing `confirm_*` function). The Worker takes the account only from the verified bearer token, and the source guard
test fails if a body, query or header identity is ever used. `list_toolkit_document_cleanup` is the only function without
an account argument: it enumerates one bucket across accounts for the sweep, returns keys only to the Worker, and the sweep
ships `off`.

**Account deletion remains authorized and complete (source + earlier tests).** Keys are under `profiles/<uid>/toolkit-documents/`;
the existing `removeAccountMedia` deletes the union of `media_objects` rows and the whole prefix and proves it empty
(C1.1's Worker tests ran it with PDF, JPEG and PNG keys of the account and another account's keys untouched), the profile
delete cascades the rows (pgTAP and validation delete a fixture account), and a pending upload is refused while deletion
is in progress (`deletion_in_progress`). Only an apply and a staging run can prove it on the real services.

**Provable only after the apply (hosted read-back, SELECT only).**
1. `pg_proc.proacl` of each of the 15 functions equals `{postgres=X/postgres,service_role=X/postgres}` and the three
   `has_function_privilege` checks (anon/authenticated false) hold on the hosted objects.
2. `relacl` and `attacl`: `toolkit_documents` has no table ACL entry for client roles and the column ACL for `authenticated`
   is `r` on those 15 columns only.
3. `relrowsecurity` true, `relforcerowsecurity` false, the two policies as listed, the three triggers.
4. All baseline digests of section Q equal, excluding Toolkit objects and the one history row.
5. PostgREST (schema cache after `pgrst_ddl_watch`) exposes the table to `authenticated` and no RPC to `anon` / `authenticated`.

## S. Contract consistency (SQL ⇄ Worker ⇄ Flutter)

Checked by reading the three sources against each other and with a scripted comparison (formats, tools, statuses,
ceilings, outcome and refusal vocabularies):

| Contract | SQL | Worker | Flutter | Result |
|---|---|---|---|---|
| Formats | CHECK + `toolkit_document_rules`: PDF, JPEG, PNG, extension `pdf`/`jpg`/`png`, ceilings 250/64/64 MiB | `TOOLKIT_CONTENT_TYPES`, same three, ceilings 250 MiB / 64 MiB | `ToolkitContentType`, exactly the same three (source guard) | consistent |
| Tools (`document_type`) | `scanner, combine_pdfs, image_to_pdf, signature` | same four | same four (`signature` stored in the `signature_pdfs` folder) | consistent |
| Image rule | CHECK: image only from `scanner`, one page | `contentTypeAllowedForTool` before any RPC | `ToolkitContentType.allowedFor(tool)` | consistent |
| Key | CHECK pins `profiles/<owner>/toolkit-documents/<id>.<ext by content type>`; `toolkit_document_object_key` | `toolkitObjectKey(userId, documentId, contentType)`; compared with the row before any read/sign/delete; never returned | no key field exists (guard test) | consistent |
| Stable UUIDs | `id` is the idempotency key, immutable | `requireUuid` | local document UUID, legacy ids that are not UUIDs are refused (`invalidId`) | consistent |
| Lifecycle | `pending_upload → ready → pending_delete → deleted`; forward-only guard | authorize / confirm / remove / sweeps | `savedLocallyPendingSync … savedToCloud … deletePending … remoteDeleted`; `savedToCloud` only after server confirmation | consistent |
| Limits | authorize enforces the numbers it is given and refuses any above the hard ceilings; the limits themselves are Worker variables | defaults 50 MiB / 25 MiB / 1 GiB / 1,000 / 5 / 120 / 10, ceilings enforced again | none (server decides) | consistent; usage is counted per account across buckets |
| Outcomes | 28 distinct outcome strings (scripted scan) | each mapped to a status + code (`AUTHORIZE_REFUSALS`, switches); `too_soon`, `not_pending`, `status_changed`, `not_abandoned` take the non-success branch, i.e. fail closed (retry later / not removed) | `ToolkitFailure` maps every refusal code listed in section C (`staleDocument`, `sessionSuperseded`, rate limit, …); an unknown code falls back by HTTP status | consistent |
| Checksum | `content_sha256 not null`, 64 hex, immutable; `sha256_verified` set only when a document becomes ready | `sha256Verified` returned; hashing **only if** `TOOLKIT_DOC_VERIFY_SHA256 = "true"` (shipped unset) | hashes before upload and verifies after download | see statement below |
| Stale / tombstones | `tombstone_floor`, `stale_document`, 500 cap, purge advances floor | 409 `stale_document`; `acknowledgeStale` | journal ledger; `retry(id, acknowledgeStale: true)`; reconciler never re-uploads a confirmed id | consistent |
| Session / account | RLS gate for reads | token + `is_current_app_session` on every route (401 / 403 `session_superseded` / 503) | pauses on `sessionSuperseded`; nothing is sent for another account | consistent |

**Checksum statement.** With the shipped configuration the Worker does **not** hash stored objects. `sha256_verified` is
therefore `false` for every document, the stored digest is the device's claim, and the only independent integrity checks
are the Worker's size / stored-type / format-signature / container checks at confirm and the app's own size + SHA-256 +
container check on download. Independent Worker SHA-256 verification exists in source and was run in a local `workerd`,
but it is **not active** until the staging CPU measurement and a deliberate owner decision. Nothing in the app or the
documents may describe documents as "verified by the server".

**What is source-only, what needs staging, what is not built.**
- *Source-only today (proven by local tests only):* everything in the migration, Worker and Flutter foundation.
- *Needs staging runtime tests:* a real signed PUT to R2 binding the `Content-Type`; R2 `head` content type and ranged
  reads; PostgREST RPC result shapes for the 10 `returns table` functions; the Worker's service-key calls; subrequest and
  CPU use (limits differ by Cloudflare plan: Free is 10 ms CPU and 50 subrequests per request, Paid 30 s default; **the
  plan of the existing Worker has not been verified here**); the 5-minute cron; digest verification CPU; CORS; Delete
  Account with real objects; cross-account and superseded-session refusals through the real Auth service.
- *Not implemented in Flutter (C2):* every per-tool adapter (Scanner, Combine PDFs, Images to PDF, Signature keep their
  own local stores), the library UI and its states, downloads into the cache, local-file migration (and the user-visible
  progress), the stale-document dialog, off-isolate hashing wiring, Android/iPhone backup exclusion of the cache and
  journal, clearing them on Delete Account, localisation, and the staging acceptance runner. The Privacy Policy, Terms and
  store disclosures are unchanged.

## T. Cost and limit sanity check (measured where possible)

**Different resources, different limits (do not mix them up).**
- **R2** holds the PDF/JPEG/PNG bytes. Standard storage USD 0.015 per GB-month, first 10 GB-month free, Class A (writes)
  USD 4.50 per million with 1 million free, Class B (reads) USD 0.36 per million with 10 million free, no egress fee
  ([Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing)). The per-account 1 GiB cap bounds R2, not the database.
- **Supabase PostgreSQL** holds only the metadata rows and their indexes. The Free plan's **500 MB** is the *database*
  size per project (the same page lists 1 GB of Supabase *file storage*, which this design does not use); Free projects
  pause after a week of inactivity ([Supabase pricing](https://supabase.com/pricing)). A 500 MB database allowance is
  **not** a 500 MB file allowance.
- **Workers** meter requests and CPU (Free: 100,000 requests/day, 10 ms CPU per request, 50 outbound subrequests; Paid:
  default 30 s CPU, higher subrequest caps; [Workers limits](https://developers.cloudflare.com/workers/platform/limits)).
  Upload bytes go straight from the phone to R2 through the signed URL and **do not pass through the Worker**; the
  Worker's work per document is a handful of small requests, plus an optional CPU-heavy hash.
- **Future commercial quotas** (RevenueCat entitlements) are a separate product layer. The limits here are Worker
  variables with database-enforced ceilings and can be tightened or loosened without a migration. Nothing here is
  unlimited and nothing paid is activated.

**Measured row size (replaces C1.1's assumption).** 10,000 synthetic ready rows (100 accounts × 100; 28-character titles,
64-hex digest, 125-character key, real indexes) on the local PostgreSQL 17.5 storage format, after `VACUUM`:
heap 432 B + indexes 329–338 B = **765–774 B per document** (the index part varies with the random UUIDs) (the `(bucket, object_key)` unique index is the largest, 212 B/row;
average tuple 424 B). Tombstones are smaller (title scrubbed). The synthetic size excludes WAL, TOAST (none used), update
bloat and Supabase's own tables.

**How the earlier "database is the first limit at about 100 accounts" claim was derived, and its status.** It multiplied
an *assumed* 2–3 KB per row (taken from the 90-row `media_objects` table, 296 kB with indexes, a number dominated by empty
pages and wider rows) by 1,000 documents by 100 accounts. That was an estimate with no measurement of the new table and
is **withdrawn**. With the measured ~770 B/row (the 774 B run is used below):

| Scenario | Rows | Estimated Toolkit database size |
|---|---|---|
| one full account (1,000 documents) | 1,000 | ≈ 0.8 MB (≈ 1.6 MB with a 2× churn/bloat allowance) |
| 100 full accounts | 100,000 | ≈ 77 MB (≈ 155 MB with the allowance) = 15–31% of 500 MB |
| 100 typical accounts (50 documents) | 5,000 | ≈ 4 MB |
| accounts that would fill the free 500 MB alone (484 MB free after today's 16 MB) | | ≈ 625 full accounts (≈ 310 with the allowance) |

These are **estimates, not verified capacity**: real density after months of churn, autovacuum behaviour and Supabase's
database-size accounting are not measured. Monitor `pg_total_relation_size('public.toolkit_documents')` and
`pg_database_size` on staging and review at 100 MB of Toolkit data. The database is *not* the first thing to run out: R2's
free 10 GB is (≈ 10 accounts at the 1 GiB cap, many more at typical use), at roughly USD 0.015 per extra GB-month.

**Recommendation (unchanged, still not final):** PDF 50 MiB, image 25 MiB, account 1 GiB, 1,000 documents, 5 pending, 120
new per hour, 10 attempts. Because the measured metadata cost is low, the 1,000-document cap is a **bytes-and-abuse**
choice rather than a database necessity; the owner can raise the count (image scans are one document per page) at almost
no cost, or lower the bytes cap for lower R2 spend. No change to the migration is needed for any of these (they are Worker
variables below the database ceilings). The per-operation Worker cost is negligible next to the free request allowance.

## U. Hosted rollback-only validation — exact procedure (NOT executed)

Pre-conditions: the owner approves the candidate hashes in section P, in a separate message. Run from an isolated
scratch directory linked to the project (never inside the repository), SELECT/transaction only.

1. **Baseline.** Run `hosted_baseline_snapshot.sql`; every row must equal section Q's digests (except `row_counts`, which
   may legitimately change if the app is in use; compare it as a note). A difference in any schema digest, the history,
   or `toolkit_named_objects <> 0` is a **STOP**.
2. **Build the request.** Assemble `hosted_toolkit_validation_request.sql` from the repository validation script and the
   migration's LF text with exactly two edits (the `\set ON_ERROR_STOP on` line becomes a comment; the `\ir` line becomes
   the migration text). Verify: migration LF SHA-256 equals `88ceb6c2…ad4d`; the request SHA-256 equals
   `c66e4504…8006`; undoing the two edits reproduces the repository script byte for byte; 275 top-level statements, one
   `begin`, one `rollback`, no `commit`, `notify`, `truncate`, `copy`, extension, role, schema, publication, event-trigger
   or default-privilege statement (all checked).
3. **Run** `supabase db query --linked --output-format json -f hosted_toolkit_validation_request.sql` as one request.
   Inside it: the preflight (`current_user = 'postgres'`, no Toolkit object, required existing functions present, fixture
   ids/emails absent) → `begin` → `set local lock_timeout '3s'` and `statement_timeout '120s'` → the migration → the
   165 assertions (privileges, constraints, forged keys/extensions, tool/format rules, digest required, lifecycle, floor,
   stale/ack, churn cap, **RLS as `authenticated` for the owner, a second account and a superseded session, `anon`
   denial, function EXECUTE for client roles checked over every Toolkit function, direct write attempts denied,
   account-deletion cascade**) → the token
   `TOOLKIT_DOCUMENTS_ROLLBACK_SOURCE_PASS` → `rollback` → the postflight (`to_regclass`/`to_regprocedure` null, fixture
   users and sessions gone) → `TOOLKIT_DOCUMENTS_ROLLBACK_RESTORED`.
4. **Pass shape.** HTTP success whose last result set is the `_RESTORED` row. **Any error is HTTP 400** with the SQL
   message and the failing assertion label (the whole request has rolled back).
5. **Read back immediately** (separate SELECT requests): `hosted_baseline_snapshot.sql` again (every digest equal to
   step 1, `toolkit_named_objects` 0), `select count(*) from supabase_migrations.schema_migrations` = 18 with the same
   history digest, and no `toolkit` object by name.
6. **Stop on any mismatch** at any step. Do not edit the script or the migration to make it pass; classify a failed
   assertion as "validation script assumption / blocked before migration apply" or as a candidate defect, report the layer,
   and wait. A correction of the validation script needs the owner's explicit authorization; a correction of the migration
   restarts section P.

**Statements considered unsafe or unsuitable, and why the run is still acceptable.**
- Fixture inserts into `auth.users` / `auth.sessions` (and the resulting `profiles` rows through `on_auth_user_created`)
  are real DML on production tables inside the transaction. They use `@validation.invalid` addresses and `c1c10000-…`
  ids, are checked absent first and gone after, fire no email (Auth sends mail from GoTrue, not the database) and have no
  delete trigger or `pg_net`. A rollback undoes them; the only residue is the engine-level one listed below.
- `alter table … disable trigger` is applied to the *new* table inside the transaction only.
- `set local role …` and `request.jwt.claim*` settings are transaction-local.
- Assertions are limited to Toolkit tables, fixture ids and `profiles.relrowsecurity`; none asserts on production row
  contents or counts (the hosted lesson from the plan-attachment run).
- **Not suitable for SQL validation, and not attempted:** anything touching R2, the Worker, signed URLs, real JWTs, or
  PostgREST behaviour.
- **Side effects a rollback does not undo:** transaction ids and WAL are consumed, catalog dead tuples are left for
  autovacuum, `pg_stat` counters move, and the temporary `pg_temp` helpers vanish with the session. `create table … references
  public.profiles` takes a `SHARE ROW EXCLUSIVE` lock on `profiles` until the rollback (roughly 4 s in the earlier run), so
  profile *writes* by the app wait while profile *reads* do not; `lock_timeout = 3 s` makes the script fail rather than
  queue behind a long writer. Prefer a moment when the owner's phone is idle. The `pgrst_ddl_watch` notification is
  discarded with the rollback.

Local confirmation only: the assembled request was executed once on the local engine with hosted-faithful default
privileges: `…_SOURCE_PASS`, `…_RESTORED`, 275 statements, no Toolkit relation, function or fixture user afterwards
(EMULATED, not hosted; `supabase_auth_admin` membership differs from hosted, which is why the cascade step is also covered
by the hosted-role facts in section Q).

## V. Staging sequence (each step needs its own approval; nothing here has run)

Staging and production **share one Supabase project**, differing only in the Worker, its R2 bucket (`…-staging` vs
production) and secrets. So: an applied migration exists in the production database the moment it is applied. The tables
are empty and inert (no production code calls the functions; the shipped flag is off), and the Worker scopes every
read by bucket. Staging test documents live in the same table as, and count toward the same per-account limits as,
production documents of the same account; use dedicated test accounts and the staging bucket, and clean them up.

1. Owner approves the exact migration hashes, then separately approves the rollback-only run (section U).
2. Rollback-only run; owner reviews the result.
3. Separately authorized apply: a scratch project holding the 18 applied migrations (HEAD blobs, LF) plus the candidate
   (LF, SHA-gated, exact file name), `supabase db push --linked`; the history must list exactly one pending migration.
4. Read-back (section R, "provable only after apply") and baseline-digest comparison.
5. Upload the Worker candidate to **staging only** with `TOOLKIT_DOCUMENTS_ENABLED = "false"` and the sweep `off`
   (dry-run twice, then deploy with a tag; read production before and after to prove it did not change).
6. Route-off verification: every `/toolkit-documents*` path answers the same 404 as an unknown path (the staging gate may
   answer 403 first for credential-free requests).
7. Controlled enablement on staging only (`"true"`, sweep `dry_run`), with the staging secret handled by the owner.
8. Owner-run acceptance with two test accounts: positive path for PDF, JPEG and PNG (authorize → PUT → confirm → list →
   download → rename → remove), negative path (forged MIME/extension/polyglot, truncated file, oversize, wrong format for
   a tool), cross-account probes (status/download/rename/remove of the other account's id), a superseded session, limits
   and `Retry-After`, retry after a lost confirm, tombstone and `stale_document`, Delete Account with PDF/JPEG/PNG
   objects present (prefix empty afterwards), abandoned-upload sweep in `dry_run` then `on`.
9. Optional digest CPU measurement: `TOOLKIT_DOC_VERIFY_SHA256 = "true"` on staging with 25–50 MiB files; read the
   Worker's CPU time; decide separately whether to keep it.
10. Explicit cleanup of every staging test object and row (the test accounts' Delete Account is the cleanest), then a
    read-back that the staging bucket prefix and the Toolkit tables are empty of test data.
11. Production Worker upload (flag `"false"`), then enablement, only after the Privacy Policy, Terms and store
    disclosures are updated and the owner separately authorizes it.

## W. Risks and inconsistencies found in C2A

No critical flaw was found in the candidate; it was not changed. Documentation corrections made: the default-privilege
wording (section B) and the database-capacity estimate (section G). Open, non-critical items for the owner:
1. The existing Worker's Cloudflare plan is not verified (it decides CPU/subrequest limits and whether digest
   verification is viable at all); digest verification stays off regardless.
2. Account limits are counted across buckets (staging and production share the table); test accounts must not be
   real users.
3. `service_role` has no table privilege on the new tables, unlike the existing tables; this is deliberate and only
   functions are used, but a future dashboard/support query as `service_role` on these tables would need an explicit
   decision.
4. The validation takes a brief `SHARE ROW EXCLUSIVE` lock on `profiles` (section U).
5. Local-engine evidence cannot replace the hosted read-back; the hosted ACLs of the new objects are unverified until
   an apply.

---

# C2B — Independent review corrections (2026-10-20)

Status: **READY FOR INDEPENDENT REVIEW.** Source only. Nothing hosted was read or written in this checkpoint, nothing was applied,
deployed or enabled, no R2 object was touched. An independent review of the C2A package returned
`CORRECTIONS_REQUIRED_BEFORE_HOSTED_VALIDATION` with three narrow findings; each is corrected below. The architecture is
unchanged (Flutter → Supabase → trusted Worker → private R2; one table; PDF / JPEG / PNG; four tool identities;
account-prefixed keys; active-session enforcement; ownerless legacy isolation; cloud-save confirmation semantics).

**What this supersedes.** The C2A candidate hashes (section P) and the hosted validation request of section U (275 statements,
fixtures in the Auth tables, a 502-document stress test) are **superseded and must not be used**. The migration is still
unapplied, so it was corrected in place; its new hash is in section Z. Statements elsewhere in this document that conflict with
this section (function counts, "object deleted first, then the row", "the signed PUT binds the Content-Type header") are
corrected by it.

## X. Correction A — the abandoned-upload cleanup race

**Root cause.** The sweep read the stale pending rows, then removed each object, then asked the database to discard the row.
Between the read and the removal the device can authorize again, upload and confirm. The sweep then removed the verified
object, and the SQL discard correctly refused to delete the now-ready metadata: a READY document without its R2 object. The
same order was unsafe against a second sweep and against a concurrent delete. Re-checking the status before deleting would only
narrow the window (the status can still change between the check and the delete), so the fix is structural.

**Design: claim first.** The row itself is moved out of the set of rows that can ever become ready, under its row lock, before
any object is touched.

```
pending_upload ──claim──▶ pending_discard ──(object removed)──discard──▶ row removed (no tombstone)
      │                        │  ▲
      │                        │  └── lease expired and the earlier cleanup never finished: claimed again, NEW identity
      │                        └────── the user deletes meanwhile ──▶ pending_delete ──▶ deleted (tombstone)
      └──────────── confirm ──▶ ready   (impossible once claimed)
```

- `claim_abandoned_toolkit_document` (new, service-role only) is a compare-and-set: it succeeds only for a row that is still
  `pending_upload` and not re-authorized since the cutoff, or a `pending_discard` row whose lease expired. It returns the row's
  own key and the **claim identity** (`discard_claimed_at`, the statement clock, distinct per claim). A row that was confirmed
  or re-authorized first answers `not_abandoned` and **nothing is deleted**.
- While claimed, `authorize`, `confirm` and `rename` answer `cleanup_in_progress` (Worker: 503 `document_cleanup_in_progress`,
  `Retry-After: 60`, which the app already treats as a retryable wait) and the guard trigger refuses `pending_discard → ready`.
  So the object the cleanup removes belongs to a document that **cannot become ready**, and no new signed URL can be minted for
  it (any URL it ever had expired at least 23 hours before the cutoff).
- `discard_abandoned_toolkit_document` now takes the claim identity: it removes the row only for that exact claim (`not_claimed`
  otherwise, for example when the user deleted the document, which moves it to `pending_delete` and clears the claim).
- A failed object removal leaves the row claimed. After the 15-minute lease a later cleanup claims it again under a new identity
  and retries (listing kind `stuck_discard`), so a failure never orphans anything and never loses the last copy.
- Concurrent cleanups: the second one finds the row claimed (`claim_held`), gone (`not_found`) or not listed at all.
- `confirm` on a claimed row is refused before any object is read or removed. A rejected confirm removes the rejected object
  only if it is still the object that was examined (same ETag); see the residual below.

SQL changes: new status `pending_discard` and column `discard_claimed_at` (CHECK: set exactly when claimed; excluded from the
authenticated column grant), CHECKs updated, guard transitions (`pending_upload → pending_discard`, `pending_discard →
pending_delete`), `begin_toolkit_document_delete` clears the claim, `list_toolkit_document_cleanup` gains `stuck_discard`, one
new function (16 in all, 13 `SECURITY DEFINER`), same revoke / grant pattern. Worker changes: `discardAbandonedUpload`
(claim → verify the returned key → deadline check → remove → discard for that identity), `deleteIfUnchanged`, the 503 mapping,
`pending_discard` reported to clients as `pending`. The sweep stays **off by default** (`TOOLKIT_DOCUMENT_SWEEP_MODE = "off"`).

**Honest residual assumptions.**
1. *Time.* After a claim the Worker removes the object within 60 s (`DISCARD_DELETE_DEADLINE_MS`) or does nothing; a lease lasts
   15 minutes. A stale cleanup could only delete a newer upload if one Worker invocation stalled for more than the lease
   between claiming and deleting AND the document were then discarded, re-authorized and re-uploaded in the meantime. The
   deadline check makes that a stall-and-resume of over 14 minutes inside a single request; it is stated, not eliminated
   (R2 has no conditional delete).
2. *Confirm-time deletion.* A confirm that rejects an object removes it so the device can upload again. `deleteIfUnchanged`
   narrows the window in which that removal could hit a newer valid object (same ETag required) but R2 offers no atomic
   conditional delete, so it narrows rather than closes it. A document that is still pending recovers by uploading again; the
   remaining harmful interleaving needs a complete delete, re-upload and confirm inside one rejected confirm. Not closed in C2B.

## Y. Correction B — replay of a presigned PUT

**Root cause.** The Toolkit PUT used the common `createPresignedR2Url`. A presigned URL is valid for its whole lifetime
(300 s) and can be used repeatedly (R2's documentation says so). After a confirm, the same URL could overwrite the verified
object; the download then (correctly) reported `object_changed`, leaving a READY document that could not be opened.

**What was measured offline (no network), with the Worker's own signer and `aws4fetch`.** The current signature covered only
`host` (`X-Amz-SignedHeaders=host`). `Content-Type` is among the headers `aws4fetch` does **not** sign, so the earlier
statement in this document that "the signed PUT binds the Content-Type header" was wrong: the stored type is whatever the
client sent, and the Worker's confirm check (stored type must equal the declared one) is what protects it, as it did before.
A header such as `if-none-match` **is** signed by default (`X-Amz-SignedHeaders=host;if-none-match`).

**What Cloudflare documents.** The S3 compatibility page marks `If-None-Match` as supported on PutObject and says conditional
headers are evaluated atomically against the committed bucket state, naming `412 PreconditionFailed` for the losing writer of a
concurrent `If-None-Match: *` write ([S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/)). The presigned-URL
page documents signing `Content-Type` and says nothing about conditional headers on a presigned PUT
([Presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)). **Whether R2 enforces `If-None-Match` on a
presigned PUT is therefore not documented and cannot be proven here** (no R2 access is allowed in this checkpoint).

**Design (smallest change).**
- The Toolkit signer adds `if-none-match: *` to the signed headers (`TOOLKIT_PUT_SIGNED_HEADERS`; other routes' signers are
  untouched). A PUT that omits the header fails the signature (fail closed); a PUT that carries it is write-once.
- `authorize` returns `uploadHeaders: { "If-None-Match": "*" }`; the app sends exactly those (and accepts nothing else, so a
  Worker response cannot make the device send arbitrary headers).
- The app treats a `412` on that PUT as "an object already exists" and goes on to confirm; the **confirm judges the object**
  (size, stored type, format framing and, when enabled, the digest). It never retries a 412 as an overwrite.

**Retry behavior (all modeled and tested, see Section Z):**

| Situation | Result |
|---|---|
| Replay of the URL after the confirm | 412; the verified object, its ETag and the download are unchanged |
| Replay before the confirm | 412; the confirm verifies the first bytes |
| Lost confirm response | next authorize answers "already in the cloud", no new URL, no upload; a repeated confirm is idempotent |
| Lost PUT response | the retried PUT gets 412, the confirm accepts that same object |
| Existing object of the wrong size or type / not that file type | the confirm rejects it (422) and removes it; the next PUT succeeds |
| Existing object that cannot be removed | the document never becomes ready (each confirm 422, each PUT 412); it recovers once removal works |
| A rejected confirm while a newer valid object landed | the newer object is not removed |

**What is NOT proven, and what happens if R2 does not honor it.** The R2 side is a *model of the documented behavior*
(`FakeBucket.putViaSignedUrl`), so the tests prove the Worker, the signer and the app behave correctly *given* that behavior.
Staging must show, with a real signed URL, that a second PUT returns 412 and leaves the object unchanged, before the feature
is enabled (Section Z, "needs real R2"). If R2 ignores the header, protection falls back to the existing, unchanged detection
(`object_changed` at download) and the smallest correct alternative applies: upload to a per-authorization staging key under
the same account prefix and promote it with a server-side S3 `CopyObject` on confirm, so a replayed URL can only ever write the
staging key. That is not built (it would be a larger change and the Worker is disabled); it is recorded so the decision is
ready if the staging proof fails. Nothing here claims protection beyond the tested contract.

## W. Correction C — a minimal, bounded hosted rollback-only test

**Finding.** The C2A hosted request (275 statements) inserted into `auth.users` and `auth.sessions`, claimed sessions, ran a
502-document create/delete stress test and held its locks for the whole run. Those belong in a local or isolated database.

**Split.** Of the 195 assertions of `supabase/tests/toolkit_documents_test.sql`: *Structure and privileges* (23) is
catalogue-only; every other section (authorize 46, confirm 9, rename 6, delete / tombstone / cleanup 52, guard 12, reads /
pagination / cleanup 30, RLS as a signed-in client 16, account-deletion cascade 1) needs fixtures (profile and Auth rows,
session claims, document churn) and therefore **stays local / isolated**. The complete suite is unchanged in strength
(165 → 195 assertions); `supabase/validation/toolkit_documents_validation.sql` (its generated, rollback-only form) now carries
a header saying it must not be run on the shared hosted project.

**The new hosted candidate:** `supabase/validation/toolkit_documents_hosted_preflight.sql` — 90 statements, one `BEGIN`, one
`ROLLBACK`, no `COMMIT`. It includes the exact migration (same two-edit transformation as before) and:

| Block | Proves |
|---|---|
| 0 preconditions | role `postgres`; no Toolkit-named object anywhere; exactly 18 applied migrations with latest `20261012233000`; `profiles`, `is_current_app_session()`, `bump_sync_version()` present |
| 1 nothing existing changed | a 16-item digest snapshot (relations, columns, column privileges, **all existing functions with bodies and ACLs**, triggers, indexes, constraints, policies, **default privileges**, roles, extensions, event triggers, publications, schemas, row counts) taken before and after the migration must be identical |
| 2 what it creates | the exact set of 16 functions by signature; owner `postgres`; security mode; fixed empty search path; `md5(prosrc)` equal to the source (which also proves the text arrived as LF); exact ACL `{postgres=X/postgres,service_role=X/postgres}`; no PUBLIC / anon / authenticated EXECUTE (via `aclexplode`); both tables' owner, RLS enabled and not forced, table ACL; column fingerprints; no table privilege for anon / authenticated / service_role; the 15 readable columns; no write column privilege; 23 constraint names, 6 index names, 3 triggers, 2 policies with their roles and commands |
| 3 role behavior without rows | as `anon`: the table and all 15 callable functions are denied; as `authenticated` (a random identity that exists nowhere): zero rows, no object key / bucket / floor, no insert / update / delete, all 15 functions denied; as `service_role`: no direct table access, pure helpers correct, read-only calls for a random identity return empty or `not_found`, `authorize` refuses a null account before any lock or row |
| after | `TOOLKIT_DOCUMENTS_HOSTED_PREFLIGHT_SOURCE_PASS`, `ROLLBACK`, a postflight that no Toolkit object remains, then `..._RESTORED` |

It creates **no user, session, profile or document**, calls **no session-claim function**, calls the functions that can write
only with identifiers that match no row (they answer `not_found` / false and change nothing), makes no network call, and uses
nothing nontransactional (no sequence, `NOTIFY`, extension, `VACUUM`). Bounds:
`lock_timeout 2 s`, `statement_timeout 20 s`, `idle_in_transaction_session_timeout 30 s`; any error aborts the transaction (HTTP
400 from the CLI). Because the failing request cannot run its own postflight, the hosted baseline snapshot is read again in
separate SELECT requests afterwards (all digests equal; `toolkit_named_objects` 0; 18 migrations).

**Locks, honestly.** `CREATE TABLE ... REFERENCES public.profiles` takes `SHARE ROW EXCLUSIVE` on `profiles` until the rollback,
so writes to profiles wait while reads do not. The minimal script holds that for well under the earlier several seconds because
it has no stress test or fixtures; the apply holds it for milliseconds. `lock_timeout 2 s` makes it fail rather than queue.
Run it when the owner's phone is idle. The residue that any rolled-back transaction leaves (transaction id, WAL, catalog dead
tuples) remains.

**What it deliberately does not prove** (needs fixtures, so local only): the lifecycle behavior, limits, tombstone floor,
guard transitions, RLS for a real signed-in owner and a second account, the superseded-session behavior and the account-deletion
cascade. They are proven on the local engine (EMULATED) and later in staging with test accounts.

## V. Evidence for the three corrections

| Evidence | Result | Level |
|---|---|---|
| pgTAP file, full migration chain | 195 / 195 (165 before; +30 for claim / lease / takeover / user-delete / ready-safety / constraints / listings) | EMULATED (PGlite 17.5, emulated pgTAP) |
| Deliberate SQL mutations of the new logic | 20 / 20 make the pgTAP file fail | EMULATED |
| Complete rollback-only validation (local only) | `_SOURCE_PASS`, `_RESTORED`, 318 statements | EMULATED |
| **Minimal hosted preflight**, assembled request, hosted-faithful default privileges | `_SOURCE_PASS`, `_RESTORED`, 90 statements, nothing left behind | EMULATED (not hosted) |
| Deliberate defects in what the preflight embeds (extra grant, PUBLIC execute, altered existing function, changed default privileges, index on an existing table, RLS disabled elsewhere, removed policy, wider column grant, forced RLS, service_role table grant, changed function body, lost search path, stray function, CRLF text) | 14 / 14 make it fail | EMULATED |
| Worker, new file `toolkit_c2b.test.mjs` (races, cleanup, signed headers, replay, retries) | 25 / 25 | MOCK (database model + R2 model, see below) |
| Deliberate Worker defects (delete-before-claim, claim ignored, wrong identity, no deadline, no retry of stuck claims, dry run claims, key unchecked, unmapped refusals, missing headers, unsigned header, always-delete, fail-open R2 model, ...) | 21 / 21 make it fail | MOCK |
| Worker, all test files (`node --test`, because `worker.js` changed): account deletion, active session, claim, staging gate, Offer, Owner, Plan, Quotation, Toolkit | 300 / 300 (25 of them the new file) | MOCK |
| Worker module on the REAL migration SQL (thin RPC adapter), incl. the exact race, failed removal + lease takeover, user delete during a claim, ready document untouched | 49 / 49 (38 before + 11) | EMULATED SQL, mock R2 |
| Flutter `test/toolkit_documents` (signed header, 412, invalid headers, 503 wait, coordinator flow) | 168 / 168 (158 + 10); 6 / 6 deliberate Dart defects fail it; scoped analyzer clean; `dart format` clean | MOCK transport |
| `git diff --check`; hidden bidirectional-character scan | clean | — |

**Security and ownership after the correction (engine-derived, regenerated: `evidence/privilege_matrix.md` in the review
package).** 16 functions, all owned by `postgres` with `search_path=''`, 13 `SECURITY DEFINER`; every one has the exact ACL
`{postgres=X/postgres,service_role=X/postgres}` (no PUBLIC, anon or authenticated EXECUTE); each of the 15 callable ones answered
`42501` to `anon` and to `authenticated`; neither table grants any privilege to `anon`, `authenticated` or `service_role`;
`authenticated` reads 15 of the 22 columns (the new `discard_claimed_at`, like the key, bucket, ETag, attempts, last-authorized
and deleted time, is hidden); RLS enabled and not forced; policies, triggers (3) and indexes (6) unchanged; 23 constraints (one
new). The new function takes the verified account as an argument and filters every row by it and by the bucket; another
account's id answers `not_found`; the only function without an account argument is still `list_toolkit_document_cleanup`.
Ownership cannot be reassigned (the guard still freezes the identity columns), the account-deletion Worker module is untouched,
and the Single Active Device gate applies to the Worker routes and to client reads exactly as before.

**Mock versus real, exactly.** The database in the Worker tests is a model of the SQL outcome for outcome; the integration run
and the pgTAP file exercise the real SQL on a local PostgreSQL engine (not Supabase). R2 is a model of its *documented*
conditional PutObject behavior and of SigV4 signed-header enforcement; the Worker signs with the real `aws4fetch`, so the
`X-Amz-SignedHeaders` assertions are real. No test touched Supabase, PostgREST, R2, Cloudflare or a device.

**Needs real R2 / staging proof before enabling:** (1) a second PUT with the same presigned URL returns 412 and leaves the
object and ETag unchanged; (2) a PUT without the header is refused by the signature; (3) R2 stores the `Content-Type` the client
sent and returns it from `head`; (4) ranged reads and `head` behave as the confirm assumes; (5) the lost-response retry
(412 then confirm) on a real object; (6) the claim-first sweep in `dry_run` then `on` against real objects and a real database;
(7) the 503 `Retry-After` handling in the app against the real Worker; (8) Delete Account with PDF / JPEG / PNG objects and a
pending, claimed or abandoned upload present; (9) Worker CPU for the optional digest; (10) the hosted ACL / RLS read-back after
an apply.

## Z. The new candidate (hashes)

Canonical hashes are of the LF text (what git stores and `supabase db push` sends); the working tree is CRLF. **Any change to
the migration, the Worker or the preflight restarts the review.** HEAD is still `08c8e24`; nothing is committed.

| File | SHA-256 (LF, canonical) | SHA-256 (working tree, CRLF) |
|---|---|---|
| `supabase/migrations/20261019100000_toolkit_cloud_documents.sql` (1,185 lines) | `5b020380feb2f8b7f77b5cc33d417d4d97d213585fe071b36a610a4f9fcc0e71` | `7590f7d16c682e7a526a087b607e117868a21ac865d20e1a0781b5fdf47f28d7` |
| `cloudflare/workers/r2-profile-upload/toolkit_documents.js` | `3b171e7d9ceeb1b21327da8d0ccc5d782826bef6413febc65e8b2772e20d77e1` | `baa6c0e74b1740e862a2d0d25ecfbafc51823a4f8ed889bce9a15f10e335b0f3` |
| `cloudflare/workers/r2-profile-upload/toolkit_content.js` (unchanged) | `26a8ebceff8f2ac5f386c38e522c2fc7b6396cbeb4629fcc9905cb9f9eb93cce` | `e87e7a577bb1459e95ca7b4932b91617e67454b50372b600263c50117b46bd1b` |
| `cloudflare/workers/r2-profile-upload/worker.js` (entrypoint) | `0a0474648cf7c18610c036283da9d7c11dee74696f1626d69de0457c0396b441` | `1354d669d405458f1c5586c5abfae4609804db1f09e38581ccf100a49429be1f` |
| `cloudflare/workers/r2-profile-upload/wrangler.toml` (unchanged; flags off) | `19854f3450e04c5481ff0f8fa157b318d4738fab0b477cb5c703ae2912af8aff` | `129fbb4c478fb2647f208668578f568066cc6227bed0dbea8f8437e79e3fc013` |
| `supabase/tests/toolkit_documents_test.sql` | `d9f21e04942d0de3db952388da7871b626b0356eaaafce9ca6d5d54806adab6b` | `40c2476389681103ed0bd29151c9b46d121f81181ddaba6484007e244fe81d9f` |
| `supabase/validation/toolkit_documents_validation.sql` (complete suite, local only) | `f8316731491a474e008c2b154f5d46a03d54d9b443f27263d0638ae5bf7e4efd` | `9a7c41fe21fa29d5207d1771ed91a044152c8765a351fdd71ad71816e3dd825c` |
| `supabase/validation/toolkit_documents_hosted_preflight.sql` (**the hosted candidate**, 336 lines) | `0c9746e2d93efaa83735837b2d0241edbf53acedfe27134d408473a05558d952` | `4b205abc50d2d3999fc702e9fac9806f7574789b947cc357f4597321019f37b8` |
| Derived single request `hosted_toolkit_preflight_request.sql` (83,644 bytes, 90 statements) | `34f7e632a84e91ffc678399a5fcbec87267b8c4fcbb32ea13a6f494acd93dc1f` | n/a (generated, LF) |

The previous (C2A) migration hash `88ceb6c2…ad4d` and request hash `c66e4504…8006` are **no longer the reviewed candidate**.
The migration is unapplied, so no applied migration was mutated. `account_deletion.js` still has an empty diff; the migration
still creates only Toolkit objects and still modifies nothing that exists (proved, on the engine, by block 1 of the preflight and
its mutation checks).

**Remaining blockers before any hosted step:** independent review of this package; the owner's separate approval of the exact
migration and of the minimal preflight run; the real-R2 proofs above (the replay proof gates *enabling*, not the database
validation); the Cloudflare plan of the existing Worker is still unverified; Privacy Policy, Terms and store disclosures before
production. No hosted write, rollback run, apply, deployment, flag change or R2 change has been made or is authorized.
