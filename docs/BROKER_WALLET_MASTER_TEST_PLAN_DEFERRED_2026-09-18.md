# Broker Wallet — Master Test Plan & Release Acceptance Register

**Edition:** 1.0 · **Prepared:** 2026-09-18 · **Owner workflow:** development first, consolidated testing later.

> **Purpose:** A single portable, actionable inventory of the tests needed for Broker Wallet. Put this file in the repository at `docs/MASTER_TEST_PLAN.md` (or attach it to the project). This is a **plan and evidence register**, not permission to execute tests, modify the application, create accounts, run SQL, deploy, pay, or publish. The live repository and later owner-observed results supersede this snapshot.
>
> **Important:** Do **not** make the full test inventory a prerequisite for every normal feature. Continue approved development checkpoints. Perform *only change-specific verification* when its risk requires it. The full matrix becomes active in a separately approved pre-release testing phase. Release-critical failures cannot be waived merely to preserve development momentum.

## 1. Rules: keep development moving without hiding risk

- **DEVELOPMENT mode (now):** implement one owner-approved feature/checkpoint at a time; run the smallest static/unit check needed for changed code, plus a *narrow real-device/hosted check only when a change touches a critical boundary*. Record all unrun tests here; do not start the full matrix or extend RLS probes just because the harness exists. The owner decides when to start TEST PHASE.
- **Immediate focused gate:** changing authentication/session recovery, authorization/RLS, tenant ownership, account deletion, database migrations, privileged Workers, private media, or payment entitlements warrants a scoped negative/positive test before labeling *that changed feature* verified or deploying consequential changes. If not tested, mark **IMPLEMENTED / TEST PENDING**, do not invent PASS, and do not claim production readiness.
- **TEST PHASE (later):** inventory live implementation, decide release features and test devices/accounts, run the suites below in risk order, fix defects in focused checkpoints, rerun affected tests, and perform final store/hosted approval.
- **Cost control:** reuse one A/B session harness for all core entities *when test phase starts*; batch related read-only tests in one run, separate destructive cases. Avoid rerunning completed suites without a relevant code/backend change. Do not spend Claude time watching manual tests; owner runs them and shares sanitized PASS/FAIL only.
- **Scope integrity:** no `service_role` impersonation for client RLS, no production-user test data, no credential/token/PII in logs or chat, no assumption that a passed Office test proves another table, no mock/fake test promoted to real-device PASS.
- **Device protection:** prefer isolated emulator/disposable device for install/uninstall, sign-out, clear-cache, account-deletion, network cutting, and media races. Never uninstall/reset the primary Samsung or clear Hive without express owner approval and an assessed data-backup path.
- **Design invariants:** protect owner-modified UI, English/Arabic and RTL, light/dark, MVVM + Provider + Repository + GoRouter, canonical Supabase identity, private R2, and existing offline behavior. Do not remove visible but unfinished features without owner approval.
- **Environment/cost:** use the existing hosted Supabase Free project unless owner authorizes otherwise. No Docker, Local Supabase, paid dev branch, plan upgrade, parallel writer, backend write, release or account creation by implication.

## 2. Evidence, status, and how to update this register

**Permitted execution states:** `NOT RUN`, `DEFERRED_TEST_PHASE`, `TEST READY`, `BLOCKED`, `IN PROGRESS`, `PASS`, `FAIL`, `NOT APPLICABLE (with proof)`. **Evidence tags:** `VERIFIED_SOURCE`, `CODE_PROVEN`, `VERIFIED_HOSTED`, `VERIFIED_RUNTIME`, `VERIFIED_REAL_DEVICE`, `OWNER_REPORTED`, `UNKNOWN`. A test can be `PASS` only with its required evidence and date; "agent says PASS" alone is not evidence.

Every executed test should be recorded as: `Case ID | date | environment/build/commit | A/B or disposable dataset (non-sensitive label) | observed result | evidence tag | issue reference | owner sign-off`. Never store actual credentials, account IDs, Office UUIDs, JWTs, full logs, screenshots containing personal data, or private records in this file.

**Risk:** `P0` = security/data-loss/billing/legal/release blocker; `P1` = core user flow; `P2` = secondary/visual/quality. **Modes:** `S` source/static; `U` unit/widget; `H` hosted authenticated or infrastructure; `D` device manual/integration; `P` profile/performance; `C` provider/store console. A risk mark means *release criticality*, not an instruction to run immediately.

### Evidence carried forward from owner and agent reports (do not inflate)

| Scope | Current recorded evidence, 2026-09-18 | Unverified / limitation |
|---|---|---|
| Six core entity CRUD | Owner-reported real-device CRUD + hosted readback in active workstream for Broker, Office, Watchman, Owner, Request and Offer, with child areas where applicable | Media on Owner/Offer intentionally untested; no implication for other modules or broad regression |
| Favorites | Prior completed milestone, owner-reported Samsung acceptance; do not reopen without regression evidence | Later feature changes may need a focused regression |
| Hosted core-entity RLS metadata | Agent-reported matching eight tables, 26 policies, grants and helpers on existing hosted project | Configuration evidence does not replace authenticated behavioral checks |
| Office cross-account SELECT | **PASS on Samsung SM-S928B, owner-supplied terminal output:** A positive control signaled; owner sign-out/sign-in occurred; existing harness completed `+1: All tests passed!`. Evidence `OWNER_REPORTED + VERIFIED_REAL_DEVICE/RUNTIME` for *this exact Office ID / SELECT path* | Only Office SELECT, one record; other entities, writes and child operations remain unverified; keep this result without rerunning by default |
| Delete Account | Owner-reported production normal path and wrong-password path device + hosted PASS | Lost-response/cut-network and other listed negative scenarios not run |
| Email Change / Password | Previous owner-reported device/runtime completion | Full localization/device matrix not assumed |
| Signed-in phone verification | Hosted guard reported verified; code implementation present | Real UAE SMS provider and final real SMS acceptance blocked externally |
| Phone login/sign-up | Phone tabs owner-verified as present/selectable | Supabase-mode phone authentication not implemented; do not call it PASS |
| Google/Apple / RevenueCat | Planned/deferred in 2026-09-16 master context | Provider setup, entitlements and live behavior not verified |
| Release policy research | September 16 planning context exists | Console state, live source, stores, legal and billing require fresh verification before release |

**Next development decision:** do not extend the Office harness in development mode. On current branch read `AGENTS.md`, `CLAUDE.md` if present, `docs/CURRENT_CHECKPOINT.md` and *current source*; choose the next incomplete product feature from present implementation evidence. One concrete candidate from the older September 14 snapshot is **Owner/Offer private-media integration**, previously excluded from Supabase core CRUD, but it is **not confirmed incomplete on the September 18 live branch**. Source-inspect only the relevant media boundaries first; if the path is already present, move to the next actual unfinished feature. Seek approval for the precise smallest implementation before infrastructure writes or risky changes. A read-only performance audit and publishing gap audit remain separate queued tracks, not automatic blockers.

## 3. Test-phase preparation and release gate

**Before full testing:** freeze the agreed release scope; identify supported Android/iOS versions and real devices; select one disposable owner-controlled A/B account pair and approved records; ensure backups and a rollback version; record hosted project/Worker configuration without values of secrets; identify a test mailbox, real SMS provider status, Apple/Google sandbox access and test purchase accounts only when needed. Prepare sanitized reporting and a defect tracker. Do not create these automatically.

**Release acceptance:** every in-scope `P0` must have adequate evidence and no unresolved blocker; every core `P1` must pass or have a documented owner decision and truthful product scope; ensure store, legal, privacy and payment gates are actually satisfied. `DEFERRED_TEST_PHASE` is acceptable *during development only*, not a release sign-off. Unimplemented/deferred capabilities remain accurately disclosed, and must not be advertised as working.

## 4. Complete test inventory

Each checkbox is **work remaining unless the evidence register above explicitly covers the narrowly described scenario**. The register is intentionally exhaustive: adapt applicability only against live source and approved release scope. Steps/expected outcomes are condensed so the list stays usable.

### A. Build, bootstrap, lifecycle, routing

- [ ] `APP-01` [P0,S/D] Clean Android debug build on current toolchain; app launches without crash and points to expected Supabase project.
- [ ] `APP-02` [P0,S/D/C] Android release AAB: correct package ID, signing, target SDK, supported Billing dependency and 16 KB/native-library compatibility where applicable.
- [ ] `APP-03` [P0,S/D/C] iOS release archive/TestFlight: Bundle ID, signing, required current Xcode/iOS SDK, entitlements and privacy declarations.
- [ ] `APP-04` [P1,D] Fresh install, cold launch, warm launch, background/resume, force-stop/restart: correct screen and no spurious logout.
- [ ] `APP-05` [P0,D] Existing authenticated session cold-starts to authorized screen without Welcome flash or protected-content flash.
- [ ] `APP-06` [P0,D] Logged-out state and session expiry cannot reach protected routes via back button, deep link or cached navigation.
- [ ] `APP-07` [P0,D] Password-recovery and deletion-in-progress markers survive process death and quarantine protected routes correctly.
- [ ] `APP-08` [P1,D] Navigation across Home, Profile, Search, Favorites, lists, details, Toolkit, quotations and back/deep links retains correct state.
- [ ] `APP-09` [P1,D] Startup without connectivity, slow Supabase, timeout and retry show truthful recoverable state; no fake success.
- [ ] `APP-10` [P1,D] Upgrade from last supported build preserves user data, preferences and local artifacts; no accidental reinstall/data reset.

### B. Account creation, login, identity, sessions

- [ ] `AUTH-01` [P0,D/H] Email sign-up, validation, verification and redirect work according to active hosted Auth settings.
- [ ] `AUTH-02` [P0,D/H] Email/password sign-in, wrong password, nonexistent account and unverified-email outcomes are distinct and safe.
- [ ] `AUTH-03` [P0,D/H] Sign-out revokes local access, clears only designated user-scoped state, then cold restart remains logged out.
- [ ] `AUTH-04` [P0,D/H] A→B account switching never presents A's profile, favorites, searches, counts, media or cached records.
- [ ] `AUTH-05` [P0,D/H] Expired/revoked session and offline-to-online renewal fail closed without user-identity mixup.
- [ ] `AUTH-06` [P0,D/H] User identity is Supabase Auth; `auth.users.id` / profiles mapping stays canonical, with no second mapping.
- [ ] `AUTH-07` [P0,D/H] Email Change: two-mailbox Secure Email Change confirmation, pending state, cancel/expiry/replay, new email and profile synchronization.
- [ ] `AUTH-08` [P0,D/H] Change Password: valid/invalid password, current-policy enforcement, old password rejected and new password works.
- [ ] `AUTH-09` [P0,D/H] Forgot/Reset Password: deep link, expired/reused token, cancel, recovery quarantine, cold restart, route isolation.
- [ ] `AUTH-10` [P0,D/H] Sign-in callback, malformed link, wrong project and interrupted browser redirect do not authorize wrong account.
- [ ] `AUTH-11` [P1,D] User-visible login/signup Phone tabs remain present/selectable in EN/AR; capability truthfully reflects unfinished phone auth.
- [ ] `AUTH-12` [P0,D/H] When implemented: Google sign-in verifies provider configuration, linking, cancellation, replay and identity parity.
- [ ] `AUTH-13` [P0,D/H] When implemented: Apple sign-in verifies account linking, nonce, private relay and deletion obligations.
- [ ] `AUTH-14` [P0,D/H] When implemented: Phone login/signup handles real OTP, anti-abuse, resends, expiry and identity linking—never fake OTP.

### C. Profile, phone and user settings

- [ ] `PROF-01` [P1,D/H] Read own profile; identity parity in Home, Profile, Search and Favorites across cold start.
- [ ] `PROF-02` [P1,D/H] Edit name: validation, optimistic presentation, persisted read-back and failed-save rollback.
- [ ] `PROF-03` [P0,D/H] Profile avatar private R2 upload/replace/read, same-account access and no leaked long-lived signed URL.
- [ ] `PROF-04` [P0,D/H] Cross-account profile/media read and modification attempts are denied by actual server authorization.
- [ ] `PROF-05` [P0,D/H] Signed-in Add Phone: valid E.164, verification, number change, competing claims, retries and rate limiting.
- [ ] `PROF-06` [P0,D/H] Real UAE SMS delivery/sender compliance once provider configured; mark BLOCKED_EXTERNAL before then.
- [ ] `PROF-07` [P1,D] Theme/language/preferences and notification settings persist without leaking across accounts.
- [ ] `PROF-08` [P1,D] Feedback, About, Share App and support/terms/privacy links behave truthfully and open correct destinations.

### D. Six core entities — run D-01…D-11 separately for each entity

**Entities:** `BRO` Broker, `OFF` Office, `WAT` Watchman, `OWN` Owner, `REQ` Request, `OFR` Offer. Record results as `BRO-D01`, `OFF-D01`, etc. **The earlier CRUD evidence covers selected scenarios only; do not auto-check all boxes.**

- [ ] `*-D01` [P1,D/H] List loads only current account's active records and correct counts, ordering, refresh and empty state.
- [ ] `*-D02` [P1,D/H] Create minimum valid record; exactly one saved row with authenticated server ownership.
- [ ] `*-D03` [P1,D/H] Create maximal valid record with phone/location/status/type/value fields relevant to that entity.
- [ ] `*-D04` [P1,D/H] Required/blank, invalid numeric, price range, partial lat/lng, invalid enum, duplicate/blank area rejected before partial writes.
- [ ] `*-D05` [P1,D/H] Detail read immediately after create and after app restart matches hosted data.
- [ ] `*-D06` [P1,D/H] Edit allowed fields and reopen; no unexpected owner/id mutation, lost fields or duplicate record.
- [ ] `*-D07` [P1,D/H] Save failures/timeouts do not show false success; retry remains idempotent where required.
- [ ] `*-D08` [P1,D/H] Soft-delete hides record in app/list/search/counts without hard-deleting relational data.
- [ ] `*-D09` [P0,H] Authenticated A owns record and reads it; authenticated B's direct SELECT by A's ID returns zero, without client owner filter.
- [ ] `*-D10` [P0,H] Disposable data only: B cannot INSERT for A, UPDATE/soft-delete A's row, or change `owner_id`/id; no unauthorized data mutation.
- [ ] `*-D11` [P1,D/H] Home totals, list refresh, Search/Favorites and related references reconcile after scoped create/edit/soft-delete.

**Explicit current evidence:** `OFF-D09` has a narrow owner-reported successful one-record SELECT proof on Samsung, dated 2026-09-18; record this in evidence register, not as a pass of all `*-D09` or `OFF-D10`. The rest of the entity cross-account suite is **DEFERRED_TEST_PHASE** until owner starts full testing. Mutating negative tests require separate disposable-data approval.

### E. Request/Offer child areas and entity relationships

- [ ] `AREA-01` [P1,D/H] Request child areas create/edit/remove; blank/duplicate/invalid area rejected and parent remains consistent.
- [ ] `AREA-02` [P1,D/H] Offer child areas create/edit/remove; prevent orphan/duplicate rows and parent rollback surprises.
- [ ] `AREA-03` [P0,H] Direct authenticated A/B SELECT of `request_areas` under foreign parent; B sees zero.
- [ ] `AREA-04` [P0,H] Direct authenticated A/B SELECT of `offer_areas` under foreign parent; B sees zero.
- [ ] `AREA-05` [P0,H] On disposable rows, B cannot create/update/delete children belonging to A; helper functions honor parent ownership.
- [ ] `AREA-06` [P1,D/H] Parent soft-delete and relevant mutations have intended effect on child read, counts and search.
- [ ] `REL-01` [P0,H] Foreign-key and check constraints reject dangling relationships and invalid values without partial parent/child corruption.
- [ ] `REL-02` [P0,H] All cross-account entity references and attachment links reject mismatched owners.

### F. Private media — profile, Owner, Offer, quotation, attachments

- [ ] `MEDIA-01` [P0,S/H] Actual feature architecture: private bucket(s), Workers, authenticated authorization, metadata identities and separate staging/production resources.
- [ ] `MEDIA-02` [P0,D/H] Owner image upload and persistence after restart, including multiple files, large/invalid file and retry when implemented.
- [ ] `MEDIA-03` [P0,D/H] Offer image upload and persistence after restart, including gallery, replace/reorder/delete when implemented.
- [ ] `MEDIA-04` [P1,D/H] Media selection cancellation, permission refusal, compression/thumbnail and upload progress recover cleanly.
- [ ] `MEDIA-05` [P0,H] B cannot authorize, read, confirm, replace or attach A's private media; signed URLs expire; Flutter never holds R2 secrets.
- [ ] `MEDIA-06` [P0,H] Worker rejects missing/expired JWT, wrong owner/media ID, malformed content, oversized file and mismatched bucket.
- [ ] `MEDIA-07` [P0,H] Media DB attachment trigger and metadata references reject foreign-parent ownership, including privileged trigger review.
- [ ] `MEDIA-08` [P1,D] Low memory, app background, slow/offline upload and process kill do not leak, duplicate or corrupt queued media.
- [ ] `MEDIA-09` [P0,H] Account deletion sweeps media objects, late signed PUTs and finalizer safely within approved lifecycle.
- [ ] `MEDIA-10` [P1,D] Cache shows correct user's images after A→B, sign-out, expiry and cold restart; no stale signed URL persistence.
- [ ] `MEDIA-11` [P0,H] Quotations and other private attachments (if implemented) enforce corresponding ownership and retention.

### G. Search, Favorites, matching, counts, map and analytics

- [ ] `SEARCH-01` [P1,D/H] Search across actual supported entities with exact/partial/Arabic queries, filters, sort, pagination and empty state.
- [ ] `SEARCH-02` [P0,D/H] Search never returns other accounts' private records or leaked cached results after account switch.
- [ ] `SEARCH-03` [P1,D] Rapid typing, filter changes, cancellation and offline/reconnect avoid stale/duplicated results.
- [ ] `FAV-01` [P1,D/H] Add/remove favorite in list/detail/search; reopen persists and UI stays synchronized.
- [ ] `FAV-02` [P0,D/H] A/B favorite account isolation including cached items and cold restart.
- [ ] `FAV-03` [P1,D/H] Deleted/unavailable targets, optimistic-save failure, duplicates and empty states handled accurately.
- [ ] `COUNT-01` [P1,D/H] Home and related totals agree with actual active/soft-deleted records and cache invalidation.
- [ ] `MAP-01` [P1,D/H] Map markers/filters/permissions/zero or partial coordinates reflect correct authorized records.
- [ ] `MAP-02` [P0,D/H] Map/cached marker and location data never reveal other accounts' records.
- [ ] `ANALYT-01` [P1,D/H] Analytics aggregates, dates, charts and zero state match authorized underlying records.
- [ ] `ANALYT-02` [P0,D/H] Analytics metrics and matching/related-item suggestions do not use another account's private data.

### H. Quotations, sharing, PDF and Toolkit

- [ ] `QUOT-01` [P1,D/H] Create/view/edit quotation, line items, totals, rounding, discount/tax/fees and permitted manual overrides per owner decision.
- [ ] `QUOT-02` [P0,H] Quotations/lines and linked source records enforce ownership and prevent cross-account data references.
- [ ] `QUOT-03` [P1,D] Generated quotation PDF matches calculations, branding, EN/AR, RTL, file name and sharing permission.
- [ ] `QUOT-04` [P1,D] Failed save/generation/share, missing source, offline and large quotation do not corrupt or falsely mark saved.
- [ ] `TOOL-01` [P1,D] Scan to PDF: camera permission, multi-page, orientation, cancel, save and reopen.
- [ ] `TOOL-02` [P1,D] Images-to-PDF: selection, ordering, compression/quality, invalid input and output integrity.
- [ ] `TOOL-03` [P1,D] Combine PDFs: ordering, encrypted/corrupt input, large files, cancel and valid output.
- [ ] `TOOL-04` [P1,D] Signature/sign document: precision, cancel/retry, resulting PDF and stored copies.
- [ ] `TOOL-05` [P0,D] Toolkit device-local PDFs survive account deletion as explicitly decided; unrelated private caches do not.
- [ ] `TOOL-06` [P1,D] File picker, storage permissions, share sheet, PDF viewer and external UAE links work on supported Android/iOS.

### I. Offline, persistence, cache and synchronization

- [ ] `OFF-01` [P1,D] Offline launch with retained valid session shows only permitted cached data and clear freshness state.
- [ ] `OFF-02` [P0,D/H] A→B switching while offline/online never exposes A's Hive/SharedPreferences/favorites/media cache to B.
- [ ] `OFF-03` [P1,D/H] Pending operations/queued media retry after reconnect without duplicates or data loss where offline writes exist.
- [ ] `OFF-04` [P1,D] Airplane mode mid-read/save/upload and after app kill recovers without indefinite spinner or false success.
- [ ] `OFF-05` [P0,D] Logout/delete clears only user-scoped caches, preserves supported local PDFs, preferences and safe shared assets.
- [ ] `OFF-06` [P1,D] App upgrade/schema evolution opens existing Hive boxes without crashing or silently dropping data.
- [ ] `OFF-07` [P1,D/H] Concurrent edits/conflicting offline changes follow documented conflict policy; no accidental last-writer surprise.

### J. Notifications, push and external integrations

- [ ] `NOTIF-01` [P0,D/H] When backend is ready, push-token registration, refresh, logout cleanup and authorization tied to correct account/device.
- [ ] `NOTIF-02` [P0,H] Server cannot send another account's private event/payload to wrong user; old-device tokens are invalidated.
- [ ] `NOTIF-03` [P1,D] Foreground/background/terminated notification, tap routing, Android channels and iOS permissions work.
- [ ] `NOTIF-04` [P1,D] Notification settings, denied permission, duplicate event and stale/missing target are handled correctly.
- [ ] `NOTIF-05` [P1,D/H] Match results and notification details resolve only authorized content.
- [ ] `EXT-01` [P1,D] Links to email, dialer, WhatsApp, maps, sharing and external resources handle missing apps/permission gracefully.
- [ ] `EXT-02` [P0,S/H] Provider outages, secrets, API quotas, webhook signatures and privileged credentials use fail-closed boundaries.

### K. Subscription, entitlements, pricing and quotas (when implemented)

- [ ] `PAY-01` [P0,C] Owner-approved StoreKit/Play/RevenueCat product IDs, offerings, subscription territories, app-user mapping and cross-platform identity.
- [ ] `PAY-02` [P0,D/H] Genuine store sandbox purchase grants server-authoritative entitlement only after verified completion.
- [ ] `PAY-03` [P0,D/H] Pending, cancelled, declined, unverified, refunded and revoked purchases do not unlock prematurely.
- [ ] `PAY-04` [P0,D/H] Renew, expire, grace, billing retry/hold and cancel retain/remove access according to actual provider state.
- [ ] `PAY-05` [P0,D/H] Restore/reinstall and Android→iOS same identity reconcile; cross-account restore cannot transfer without approved policy.
- [ ] `PAY-06` [P0,H] Signed webhook auth, duplicate/out-of-order delivery, retry/idempotence and reconciliation after network loss.
- [ ] `PAY-07` [P0,H] Quotas and plan limits enforced on trusted backend; client modifications, concurrent requests and stale cache cannot bypass.
- [ ] `PAY-08` [P0,D/C] Paywall shows actual localized store currency, full yearly charge, renewal/trial terms, privacy/terms, restore/manage/cancel links.
- [ ] `PAY-09` [P0,D/H] Delete Account with active subscription explains separate store cancellation; account deletion lifecycle remains approved immediate-delete behavior.
- [ ] `PAY-10` [P0,C] Play/Apple billing SDK and agreements, provider dashboard permissions, price/territory tax rules and real test-account approvals.

### L. Delete Account and data lifecycle

- [ ] `DEL-01` [P0,D/H] Wrong password: refuse deletion, preserve account, profile/media and signed-in state; generic safe error.
- [ ] `DEL-02` [P0,D/H] Correct password: immediate authorized hard deletion, Welcome only, no old session/profile/media after restart.
- [ ] `DEL-03` [P0,H] Auth/profile/owned-row cascade and media_objects/deletion-job read-back converge; cron finalizer completes.
- [ ] `DEL-04` [P0,H] Old token after deletion cannot authorize read, upload, or mutation.
- [ ] `DEL-05` [P0,D/H] Lost response/network cut mid-delete: marker quarantine and eventual convergence; use disposable account only.
- [ ] `DEL-06` [P0,H] Late signed upload, cron retry, Worker restart and staging-vs-production ownership cannot reintroduce deleted media.
- [ ] `DEL-07` [P0,D] Double tap, incorrect password then correct, recovery session and expired auth refuse unsafe transitions.
- [ ] `DEL-08` [P0,D/H] Web deletion-request resource, identity verification, privacy/deletion disclosures and store billing-cancel explanation meet actual release requirements.
- [ ] `DEL-09` [P0,D] Device-local Toolkit PDFs remain, user-scoped application caches do not; A→B contains no residual personal data.

### M. Database RLS, migrations, Cloudflare and operational security

- [ ] `SEC-01` [P0,H] Actual hosted schema/constraints/indexes/FKs, migration history, RLS and grants match effective source on all release tables.
- [ ] `SEC-02` [P0,H] A/B authenticated SELECT negative tests for every private table and child; positive own-record controls, no client-side ownership filter.
- [ ] `SEC-03` [P0,H] Disposable-data negative INSERT/UPDATE/DELETE/ownership-transfer for exposed permissions; parent hard DELETE denied, intended soft-delete works.
- [ ] `SEC-04` [P0,H] SECURITY DEFINER routines, triggers, views, RPC EXECUTE grants, search_path and dynamic SQL reviewed for bypasses.
- [ ] `SEC-05` [P0,S/H] Flutter cannot access service-role/server keys; no secrets in repo, build artifacts, logs, crash dumps or sample commands.
- [ ] `SEC-06` [P0,H] Cloudflare Worker JWT validation, CORS/origin where relevant, bucket separation, signed URL TTL, nonce/idempotency and safe error responses.
- [ ] `SEC-07` [P0,H] Rate limits, abuse protection, failed-login/OTP resilience and privilege escalation tested where supported.
- [ ] `SEC-08` [P0,H] Database migration reviewed, previewed and authorized; reversible/rollback plan with non-destructive verification before hosted apply.
- [ ] `SEC-09` [P0,H] Backups/restore exercised on approved disposable environment; RPO/RTO and recovery procedure documented.
- [ ] `SEC-10` [P0,H] API/network error logs redact secrets, IDs and PII while preserving actionable error codes/trace identifiers.
- [ ] `SEC-11` [P0,S/H] Dependency audit, software supply chain, permissions and mobile/API threat model reviewed before release.

### N. Localization, UI, accessibility and compatibility

- [ ] `UI-01` [P1,D] Every in-scope screen and validation/error path works in English and Arabic; no hard-coded untranslated strings.
- [ ] `UI-02` [P1,D] RTL layout: navigation, forms, numbers, currency, dates, phone, mixed Arabic/English, maps, PDFs and sharing.
- [ ] `UI-03` [P1,D] Light/dark themes preserve manual design, readable contrast and stable components/typography.
- [ ] `UI-04` [P1,D] Small/large device, landscape where supported, text scaling, keyboard, safe area and display cutout.
- [ ] `UI-05` [P1,D] Accessibility labels, semantics, touch target size, focus order, screen-reader narration and reduced motion.
- [ ] `UI-06` [P1,D] Loading/empty/error/success UI never leaks old account data, obscures essential consent or produces false success.
- [ ] `UI-07` [P1,D] Form validation and numeric/locale formatting stable in both locales, including paste and keyboard submission.
- [ ] `UI-08` [P2,D] Navigation/animations/transitions/screenshots match owner-approved visual baseline; no unexpected redesign.

### O. Performance, reliability and resource use

- [ ] `PERF-01` [P1,P] Record Profile-mode baseline on physical device: cold start, authenticated usable screen and first entity list.
- [ ] `PERF-02` [P1,P] Home↔Search/Favorites/Profile/navigation latency with no excessive duplicate requests.
- [ ] `PERF-03` [P1,P] Long list scroll, lazy rendering, rebuild scope, frame/UI/raster times and memory under representative data.
- [ ] `PERF-04` [P1,P] Large image/media gallery decode/cache dimensions, media upload and low-memory recovery.
- [ ] `PERF-05` [P1,P] Map, search/filter, analytics and PDF create/combine avoid main-isolate stalls under realistic load.
- [ ] `PERF-06` [P1,P] Repeat cold starts, navigation cycles, A/B switching and background/resume; no leaks or excessive persistent cache.
- [ ] `PERF-07` [P1,P] Slow/unstable network and backend retry behavior: bounded waits, batching/pagination and no unauthorized cache shortcuts.
- [ ] `PERF-08` [P1,P] Any optimization has before/after metrics and security/session/offline regression; no generic rewrite without evidence.

### P. Store release, business, policy and rollout

- [ ] `REL-01` [P0,C] Actual UAE business licence/app distribution eligibility and applicable TDRA/tax/VAT handling assessed with qualified parties as needed.
- [ ] `REL-02` [P0,C] Correct owner/developer account type, contracts, bank/tax agreements, D-U-N-S if applicable; no invented approval.
- [ ] `REL-03` [P0,C] Final Android package/iOS Bundle IDs, ownership, signing and secure credentials custody verified in consoles.
- [ ] `REL-04` [P0,C] Actual current Google/Apple SDK, target API, native page size, subscription and testing policies verified before submission.
- [ ] `REL-05` [P0,C] Privacy policy/support URLs, in-app and external deletion route, Data safety/App Privacy, permissions, encryption and age rating truthful.
- [ ] `REL-06` [P0,C] EN/AR listing content, screenshots, icons, review account, reviewer instructions and accurate available-feature descriptions.
- [ ] `REL-07` [P0,C] App country availability and individual subscription product territories/prices deliberately selected and verified.
- [ ] `REL-08` [P0,C] Store-specific closed test / TestFlight, product review, first IAP submission and owner-approved release sequencing.
- [ ] `REL-09` [P0,H/C] Production rollout checklist: exact versions/config, backups, Worker cron/domain, smoke tests, observability and rollback.
- [ ] `REL-10` [P0,C] Owner reviews known limitations, customer support response, incident escalation, retention and release go/no-go evidence.

## 5. How to run the consolidated test phase efficiently (when owner approves)

1. **Inventory only:** reconcile every scenario against the *then-current* branch, actual screens/backend, official policy and feature scope. Mark proven N/A with reason; don't create fake requirements for intentionally unsupported features.
2. **Prepare isolated test fixtures:** existing authorized disposable accounts/records, device strategy, rollback and redaction. Get separate permission for destructive tests and any hosted data changes.
3. **Fast foundation:** build, startup, account identity, one positive CRUD per core entity, offline/locale smoke. Record defects once, fix in narrow checkpoints.
4. **Batch read-only security:** reuse the established account-switching direct-query harness, cover each table and child in one A/B run only after its inputs are verified. Never assume Office PASS generalizes.
5. **Separate mutation/destructive security:** disposable records, explicit owner go-ahead, one bounded negative test at a time; document data read-back.
6. **Media/notifications/payments:** run only when implemented/provider-ready, with sandbox credentials kept outside code/chat and authoritative backend read-back.
7. **Quality and release:** device compatibility, EN/AR/RTL, profile performance, offline/cold restart, store consoles, compliance, backups and staged rollout.
8. **Exit report:** list tested build/commit, P0/P1 outcomes, blocked/deferred items, unresolved defects, explicit owner release decision. A passing suite does not authorize a store submission automatically.

## 6. Lightweight development checkpoint log (fill only when meaningful)

| Date | Feature/change | Changed paths | Small targeted check actually run | Deferred tests entered here | Owner-approved next implementation |
|---|---|---|---|---|---|
| 2026-09-18 | Office direct A/B SELECT | Test-only harness; exact current diff to verify in live repository | Owner terminal: A control signaled; app signed out/in B; `All tests passed!` | Seven other core/child-table SELECT checks, all mutation negatives | Select next actual unfinished product feature from live checkpoint |

**Change log:** v1.0 created from project master context dated 2026-09-16, historical September 14 repository inventory, latest owner/agent-reported core-entity/RLS and Office runtime progress through September 18. Historical code inventories are *planning input only*, not a claim that today's active branch contains or implements every feature listed.
