# Durable decisions

- Migration is staged.
- Supabase is the canonical identity/profile authority in Supabase mode.
- Production media target is private Cloudflare R2.
- Do not weaken security.
- Require a real-device gate after every checkpoint.
- Use a one-small-change workflow.
- Facebook authentication is removed. Google and Apple sign-in are deferred.
- Phone verification stays on Supabase Auth's own phone-change flow. Real SMS
  provider setup is deferred until the business/trade license and UAE sender
  registration exist; paying for production SMS just to unblock development is
  not justified. Until then:
  - keep the existing Phone implementation and its database security as they
    are; do not remove or redesign them;
  - no fake SMS credentials, no custom OTP system, no weakening of Supabase
    Phone security;
  - no test OTP bypass unless chosen later as a separate development-only
    checkpoint;
  - unrelated work is not blocked on this external dependency.
- Only the stale `phone_change` cleanup is Supabase's documented mitigation for
  phone-change ambiguity. The write-time single-holder guard trigger is this
  project's own hardening on Supabase Auth's internal columns: re-run
  `supabase/validation/phone_security_validation.sql` after Supabase Auth
  upgrades.
- Existing-account Email Change uses Supabase Auth's native authenticated
  `updateUser(email)` flow. Do not add a current-password reauthentication step
  unless a future Supabase-supported configuration explicitly requires it.
- During Email Change, `auth.users.email` remains canonical and
  `User.newEmail` is pending presentation only. Never persist a competing
  client-side pending email or write `public.profiles.email` from Flutter.
- Supabase exposes resend for `email_change` but no supported server-side
  cancellation API in the pinned client. The app may close the form, but must
  not label that as cancelling a pending server request.
- Supabase auth deep links stay on automatic URI detection. The app narrows
  `detectSessionInUriPredicate` to links actually carrying `access_token` or
  `code` instead of disabling detection, so Supabase remains the only thing
  that exchanges a session while error-only and message-only callbacks are
  handled in the app. Never disable `detectSessionInUri` globally — signup
  email verification depends on Supabase exchanging its own link.
- An error delivered on Supabase's `onAuthStateChange` stream is not evidence
  that the session ended. Supabase republishes failed refreshes and every
  `AuthException` its deep-link observer catches onto that stream, so every
  subscriber must supply `onError`, and no subscriber may treat a stream error
  as a sign-out. An authoritative sign-out always arrives as a null identity.
- An auth callback is a trigger, never a source of truth. Under Secure Email
  Change the first confirmation returns only an informational `message` whose
  wording Supabase may change, so outcomes are always read back from the
  authoritative Supabase user rather than parsed out of the link.
- Under Secure Email Change, resending — and equally requesting a different
  address — calls GoTrue's `sendEmailChange`, which regenerates both
  confirmation tokens and resets `email_change_confirm_status` to 0. Older
  links stop working and any approval already given must be repeated; UI copy
  must say so. This is also why "Use a different email" is a legitimate
  recovery action while a fake "Cancel email change" is not.
- Broker Wallet has exactly one password policy, `PasswordPolicy`: minimum 8
  characters with a lower-case letter, an upper-case letter and a digit, and a
  72-byte maximum because GoTrue hashes with bcrypt, which ignores anything
  past 72 bytes. Sign-up, Change Password and Reset Password all validate
  through it. The rules were chosen to equal what Sign-up already enforced, so
  no existing account can be refused a password change by a rule its password
  never had to satisfy. Never add a competing validator.
- The current password is collected and sent only when the backend actually
  verifies it, which the app learns from
  `SupabaseConfig.requireCurrentPasswordOnChange` mirroring the hosted
  `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD`. Never verify a
  current password client-side with a second `signInWithPassword`: it would
  mutate the very session the change is about and would prove nothing the
  server was not already able to answer. Enabling the hosted setting therefore
  requires a matching `--dart-define=REQUIRE_CURRENT_PASSWORD=true` build.
- Supabase "Secure password change" (the `reauthenticate()` + `nonce`
  ceremony) stays OFF. The pinned `gotrue` exposes it, but the app does not
  implement the OTP-entry step, so enabling it hosted would break password
  changes. Adopting it is its own checkpoint.
- Password recovery has its own deep-link address,
  `brokerwallet://auth/reset-password`
  (`SupabaseConfig.passwordRecoveryCallbackUri`). Every other auth flow keeps
  `brokerwallet://auth/callback`. This is what makes a *failed* recovery link
  identifiable: GoTrue does not exchange it, gives its error redirect no
  guaranteed `type`, and therefore produces a callback otherwise identical to
  an expired Email Change link. Ownership is decided by exact scheme, host and
  path — no parameter, no provider-supplied `type`, no clock. Never route two
  auth flows through one address again where the failure callbacks would be
  ambiguous, and never re-introduce a time-window heuristic as a fallback: a
  weaker signal kept beside a deterministic one only restores the ambiguity.
  Adding an address obliges adding it to the hosted redirect allowlist as an
  exact entry.
- Password recovery context comes only from `AuthChangeEvent.passwordRecovery`,
  republished by `SupabaseAuthRepository` from its existing single
  `onAuthStateChange` subscription. This is what separates a recovery session
  from an ordinary sign-in, since Supabase makes them otherwise identical.
  Never add a second deep-link listener for recovery: the recovery callback is
  session-bearing, so Supabase exchanges it and `AuthCallbackCoordinator`
  correctly never sees it.
- `/reset-password` is reachable only while `PasswordRecoveryViewModel`
  holds the route, and the form is built only in the `active` phase. Recovery
  outranks every other rule in `resolveAuthRedirect` because a recovery link
  produces a genuine session that would otherwise route straight to `/home`.
- Changing a flow's `redirectTo` is safe with respect to the pinned SDK:
  `SupabaseAuth._isAuthCallbackDeeplink` consults only the supplied
  `detectSessionInUriPredicate`, and neither it nor `getSessionFromUrl`
  inspects the URI path or host — only query and fragment parameters. The PKCE
  code verifier that tags an exchange as `passwordRecovery` is keyed by storage
  key, not by redirect URL. Both were read from `supabase_flutter` 2.17.2 and
  `gotrue` 2.27.2 source.
- A new deep-link path needs no platform change while it keeps the existing
  scheme and host. The Android filter declares `scheme` and `host` with no
  `path`/`pathPrefix`/`pathPattern`, and Android then ignores the path; iOS
  matches on the registered scheme alone. `flutter_deeplinking_enabled` is
  false on Android and `FlutterDeepLinkingEnabled` is false on iOS, so a
  platform deep link never reaches Flutter navigation and a deep-link path can
  safely share a name with a GoRouter route.
- Password reset is treated as an account-discovery surface. Its success
  message is identical for a registered and an unregistered address, and every
  failure that could distinguish the two collapses into one generic outcome.
  Never add a pre-flight "does this account exist" lookup to that flow.
- SECURITY INVARIANT: a Supabase password-recovery session must never grant
  normal application access. It is authenticated at the transport level and is
  deliberately not application-authenticated: while one is live the only
  reachable screen is `/reset-password`, and Home, Profile, Edit Profile,
  Search, Favorites and every other route redirect to it. This is a regression
  invariant, covered by `test/auth/password_recovery_quarantine_test.dart`, and
  it must not be weakened to make any future feature route more simply.
- Recovery ownership is resolved by the repository *before* it publishes the
  session identity, and `AuthViewModel` re-reads it in the same turn it applies
  that identity, so `status` and `isPasswordRecoveryActive` are always one
  atomic snapshot carried by a single `notifyListeners()`. The real-device
  failure was exactly this ordering: identity was published first, the router
  refreshed on a notification that said "authenticated" and nothing yet said
  "recovery", and Home appeared. Never answer "is this session a recovery" on a
  second stream, and never paper over the window with `Future.delayed` or a
  timer — the guarantee has to be structural.
- `resolveAuthRedirect` evaluates the recovery gate ahead of the bootstrap gate.
  Recovery is known before bootstrap resolves, because it is restored from the
  persisted marker, so deferring it behind `status == unknown` reopens the same
  hole.
- A recovery session is never kept. Both completing a reset and cancelling one
  sign it out and clear the marker, and the router then lands on `/sign-in` —
  never Home and never Welcome. The user proves the new password by signing in
  with it. Keeping the session alive after a reset would be the same defect as
  routing to Home during one.
- `PasswordRecoveryStateStore` persists exactly one value, the recovery owner's
  uid, because `GoTrueClient.recoverSession` restores a session with
  `AuthChangeEvent.initialSession` and `Session` carries no recovery marker, so
  a recovery that survives process death is otherwise indistinguishable from a
  normal session. It holds no token, password, address or timestamp, is never
  used to classify a callback, and is ignored when the live session's uid does
  not match. Stale-state analysis: it is cleared on a completed reset, a
  cancellation, a sign-out and any ordinary sign-in, so the worst reachable
  state is a marker for the account that is already signed in, which presents
  as the reset screen and is cleared by the cancel action on it — one extra tap,
  never a lockout, and never silent application access. Do not extend this store
  with anything else.
- Every Supabase Realtime subscription needs an `onError`, for the same reason
  the auth stream does: a refused channel delivers `RealtimeSubscribeException`
  onto the stream, and without a handler it becomes an unhandled async error
  that pauses the debugger repeatedly and can reach a user as a crash. A
  notification-feed failure must settle its own loading state and nothing else —
  it is never a reason to change authentication state, and its provider message
  must not be logged or rendered.
- Account deletion is server-owned and runs in the existing
  `r2-profile-upload` Worker (`POST /account/delete`), not in a Supabase Edge
  Function. It must delete the account's R2 objects before `auth.users`, because
  the cascade removes the `media_objects` rows that record them, and the Worker
  is the only existing boundary that already holds both the R2 binding and the
  Supabase server secret. Never give Supabase an R2 credential or Flutter any
  credential to make deletion work elsewhere. This is this project's design, not
  a Supabase-prescribed pattern.
- The account to delete comes only from the bearer token as verified by
  `GET /auth/v1/user`. A client-supplied user id is never used; one that differs
  from the verified account is refused. Media is inventoried only by
  `media_objects.owner_id = verified uid` and the `profiles/<uid>/` prefix, and a
  row outside that bucket or prefix stops deletion before anything is removed —
  unknown media is never guessed at and never orphaned silently.
- Deletion is confirmed by re-verifying the account password server-side,
  inside the Worker, against the verified account's own email. It is never done
  with a client-side `signInWithPassword` on the app's Supabase client: the
  pinned `gotrue` saves that session and emits `signedIn`, which would replace
  the live session and clear password-recovery state. `reauthenticate()` only
  sends a nonce that GoTrue consumes in a password update, so it proves nothing
  for deletion. Accounts without an email identity are refused
  (`reauthentication_unsupported`) until their provider has its own
  confirmation.
- A password-recovery session can never delete an account: the route
  quarantine keeps the flow unreachable, the view model refuses it, and the
  Worker refuses a token whose `amr` includes `recovery`.
- Once `auth.users` is deleted, the deleted account's token authorizes
  nothing. The Worker never decodes a rejected token to choose an account, and
  a retry after deletion gets `session_expired` with no cleanup. Every action
  after the auth delete is authorized by a server-owned
  `public.account_deletion_jobs` row, created from the Supabase-verified id
  before the account is deleted, with no foreign key so it survives the
  cascade, readable and writable only by `service_role`. The R2 prefix comes
  from that row. (An earlier design recovered lost responses by trusting the
  `sub` of a token Supabase Auth had rejected; it was withdrawn for exactly this
  reason.)
- Order is fixed: authority -> password -> claim job (`quarantined`) -> R2
  inventory and deletion, proven by an empty prefix listing -> job to
  `auth_delete_pending` by compare-and-set -> auth admin delete, with any
  ambiguous result settled by reading the user back -> job to `auth_deleted`:
  this bucket's existing job is advanced by compare-and-set, an absent job is
  recreated with a conflict-ignoring insert, and another bucket's job is never
  merge-overwritten. Every failure before the auth delete cancels the job, so an
  account that was not deleted is never left unable to upload.
- Upload quarantine is structural: `/authorize` reads the clock (t0), refuses if
  a job exists (failing closed if the table cannot be read), signs, and refuses
  a URL dated more than 60 s after t0. The maximum signed PUT lifetime is
  therefore 300 s TTL + 60 s = 360 s after t0.
- `cleanup_not_before` is never set by the request path or defaulted from the
  database clock. The cron finalizer stamps it, on its own Cloudflare clock
  read after it has listed the job as `auth_deleted`, as stamp + 360 s + a
  120 s safety margin (`CLEANUP_WINDOW_MS` = 480 s), and sweeps only at or
  after that time. The stamp follows the job's commit, which follows every
  quarantine check that could have missed it, so no Postgres clock takes part.
  The only clock assumption left is agreement within 120 s among Cloudflare
  clocks (the signing isolate, R2's validation and the cron isolate). Never
  shorten the margin, lengthen the PUT TTL, remove the signing bound, or read
  the stamp before the listing without redoing this argument.
- Each job records its `bucket`. JOB OWNERSHIP INVARIANT: a job may be mutated
  (claimed, reused, advanced, stamped, cancelled, finalized or recreated) only by
  the Worker whose `R2_BUCKET_NAME` equals the job's `bucket`. Every
  compare-and-set and delete filters on it. A job owned by another bucket blocks
  the request with `deletion_in_progress` before any R2 or auth action, and is
  never overwritten: `recordAuthDeleted` advances by compare-and-set and
  recreates an absent row only with an insert that ignores conflicts, never a
  merge upsert. Reading is deliberately not bucket-scoped: `/authorize` refuses
  uploads while a job exists for the account in ANY bucket. `user_id` stays the
  one-account primary key.
- A staging Worker that reaches real Supabase data is protected by explicit
  access control, never by an unpublished URL. When `STAGING_TEST_KEY` is bound
  (staging only), every HTTP request except a CORS preflight must present it in
  `X-Broker-Wallet-Staging-Key` before any Supabase, R2 or account logic runs.
  Otherwise the fixed response is 403, and a bound-but-empty key denies
  everything. The comparison is SHA-256 digests without an early exit. The key
  is never logged or returned, and it adds to, never replaces, the user's JWT and
  password. Production never binds it, so production behaviour is unchanged.
- A new Worker whose config lists required secrets is bootstrapped by claiming
  its name with a do-nothing placeholder (`staging-bootstrap/`), storing the
  secrets on it, creating its bucket, and only then deploying the real code.
  Never deploy real code first and add secrets afterwards: Wrangler refuses to
  deploy without them, and each `wrangler secret put` deploys a version
  immediately.
- The finalizer is a Worker cron trigger that uses the server secret and job
  rows only. Jobs are deleted when finalized or cancelled; nothing is retained
  about a completed deletion. An `auth_delete_pending` or `quarantined` job is
  cancelled only when Supabase Auth reports the account still exists and the
  job is over an hour old. The migration must be applied before the Worker
  version that reads the table is deployed, because `/authorize` fails closed.
- The Supabase secret key (`sb_secret_...`) is sent only in the `apikey`
  header, on server-to-Supabase calls, including the Auth admin API. It is never
  sent as `Authorization: Bearer`. A user JWT travels only as
  `Authorization: Bearer`, paired with the publishable key.
- SECURITY INVARIANT (same discipline as password recovery): a session whose
  account has a deletion of unknown outcome is never application-
  authenticated. `AccountDeletionStateStore` is primed at startup and holds the
  account id written immediately before the request. When a newly applied
  session identity matches it, `AuthViewModel` quarantines the session in the
  same turn, before notifying: `status` stays `unknown`, `currentUser` is null,
  and no hydration, profile subscription, snapshot or notification feed starts,
  so GoRouter holds `/`. Reconciliation then ALWAYS ends that session on the
  device. Supabase Auth's `getUser()` answer decides only the wording:
  `user_not_found` is a deletion; exists, rejected or unanswered is "signed
  out, sign in again to check". Ambiguity is never success, and a still-
  existing account signs in again as an ordinary session. The marker is
  cleared once no session for that account remains on the device. A session
  that is already application-authenticated (its own in-app deletion flow) is
  not re-quarantined. No timer or delay holds the quarantine; the only bound is
  a 15 s timeout on the single `getUser()` network read. Independently, the
  pinned `gotrue` removes the session and emits `signedOut` when a refresh fails
  with a non-retryable error, which a deleted account's refresh token always
  does.
- Hosted verification of Worker triggers runs on a separate staging Worker
  (`r2-profile-upload-staging`, its own bucket and revocable keys, no route),
  never by attaching an unverified cron to the production Worker. A preview
  version (`wrangler versions upload`) does not receive Cron Triggers.
  Production gets the code and its trigger together, and only after staging
  passes.
- Deletion is immediate and permanent (`should_soft_delete: false`). APPROVED
  by the product owner, 2026-09-13: no grace period and no soft-delete account
  lifecycle. The existing `deleted_at` columns are sync tombstones, not an
  account lifecycle.
- Product owner decisions, 2026-09-13: device-local Toolkit PDFs are preserved
  on account deletion; RevenueCat data retention is deferred until RevenueCat is
  live; retained audit/security history must not contain direct personal
  identifiers (email, phone, name) — a SET NULL foreign key is not enough if the
  payload names the person; Google, Apple and phone reauthentication for
  deletion is future provider-specific work. No UAE retention requirement has
  been specified and none may be assumed.
- After the server reports deletion, `AuthViewModel.completeAccountDeletion`
  ends local state for that uid only. It never signs out a different account
  that is signed in by then, and it is not left authenticated by a sign-out that
  cannot reach the server. Local cleanup is an explicit inventory
  (`DeletedAccountLocalDataCleaner`); language and theme are device preferences
  and are kept. Never replace it with a wipe of all app storage.
- Deleting an account is not a subscription cancellation or refund, and the UI
  says so. Any future RevenueCat integration must not infer one from a deletion.
- Offer media identity is a UUID v4 `mediaObjectId` generated on the device when
  the file is picked. It is the same id in the upload queue, the Worker,
  `media_objects`, the R2 object key and the local cache, and every Worker step
  (authorize, confirm, remove) is idempotent on it. Retrying the same logical
  media must never create a second object; a Worker that answers with an id of
  its own is refused rather than followed.
- Offer media is attached by one service-role-only database function,
  `confirm_offer_media_upload` (APPROVED by the product owner as Option B): it
  locks the Offer row, counts only `ready` items in the same bucket (staging
  and production share one database), appends at max+1 and marks the item
  ready in one transaction. The Worker remains the authority for ownership,
  real type, size, duration and the ten-item limit; Flutter checks are only
  for the user's benefit. Deploy order: migration, then Worker, then the app.
- Saving an Offer never waits for its media. New items go to a persistent,
  one-at-a-time upload queue (`offer_media_uploads`) that survives restarts,
  runs only for the application-authenticated account, and shows each item as
  queued, uploading, ready, retryable or refused. Nothing is presented as
  uploaded before the server has accepted it.
- Signed Offer-media links are transport: held in memory only, dropped a
  minute before expiry and on any account change, never persisted, never used
  as a cache key, never logged. A private Offer video loads only when tapped,
  and an expired link is re-signed once automatically.
- HEIC/HEIF Offer photos are converted to JPEG on the device with the existing
  image compression package; no display path depends on platform HEIF
  decoding, and the Worker no longer accepts new HEIC uploads.
- Media of a soft-deleted Offer is retained for 7 days, then removed by the
  Worker's Offer-media sweep. The sweeps ship with `OFFER_MEDIA_SWEEP_MODE =
  "off"`; enabling `dry_run` or `on` in any environment is a separate owner
  decision. Transcoding and Cloudflare Stream are out of scope for Offer media
  until separately approved.
- Offer media uploads run only while the app is in the foreground. Android 15+
  gives an app outside a valid process lifecycle no network (device-verified
  on the Samsung test phone: the app's uid is blocked `APP_BACKGROUND` whenever
  it is not in front). The queue therefore starts nothing in the background, a
  transfer cut off by leaving the app returns to waiting without spending an
  automatic retry, and on the app's return (and at every start or sign-in) any
  item that failed only for a transient reason is resumed automatically.
  Background uploads (WorkManager or a foreground service) are not promised
  and would be a separate, owner-approved checkpoint.
- An Offer media item waiting for an automatic retry is shown as "retrying",
  not as a failure asking for Retry; "tap Retry" appears only once automatic
  retries are exhausted. Upload progress is drawn beside the preview (a strip
  along the bottom on the large views), never instead of it.
- A video still uploading plays from the device's own copy. After its upload
  that copy is retired rather than deleted (it may be playing) and is removed
  the next time the queue opens; it is never adopted as a cached copy of the
  server video (local video caching remains deferred).
- A ready Offer video with no still frame on this device (another device, or
  after a reinstall) gets one made on demand from the video through its
  private signed link and kept under its stable, account-scoped media id; the
  link is never stored or logged. A server-stored poster (a second private R2
  object via `media_objects.thumbnail_media_id`) is a possible later
  improvement that needs a Worker deployment and is not approved.
- Debug diagnostics for media name items only by a masked media id and log
  fixed categories or error types: never a URL (even redacted), an object key,
  an account id, a local path or raw provider/player error text.
- Offer media is picked through its own compact sheet (Camera — Take photo /
  Record video, Gallery, Documents). Gallery is one native selection of
  photos and videos together, capped at the places left, through the
  Android system Photo Picker: it needs no media-library permission, so no
  app-made explanation dialog and no READ_MEDIA_* request is shown for it. Camera
  permission is requested once by the system dialog at use. Documents stay
  unavailable for Offers until a secure Offer-document backend is approved
  (Task C). Profile and Toolkit pickers keep their existing flows; Owner
  media uses this sheet (below).
- Video players are owned by holders: a widget that receives a controller from
  VideoPlayerResourceManager holds it until it calls release; the manager
  disposes a controller only when no widget holds it (idle players make room,
  a held one never does) and never hands out a disposed controller. Widgets
  never dispose controllers themselves.
- Offer media capture uses the phone's own camera app through `image_picker`
  (`pickImage` / `pickVideo` with `ImageSource.camera`), offered as two direct
  actions, Take photo and Record video, because a system capture returns one
  kind of media. No in-app camera and no other camera package: an in-app
  camera on flutter.dev's `camera` package was approved and built on
  2026-09-27, crashed on the Samsung after the permission grant, and the
  owner withdrew that approval the same day. Camera output is screened by
  its real size, type and length like any Gallery pick. Profile and Toolkit
  keep their existing capture flows; Owner media uses this one (below).
- Owner media follows the Offer media rules (owner decision, 2026-09-28):
  photos and videos only; at most 10 per Owner record; photos ≤ 10 MiB after
  HEIC → JPEG; videos ≤ 100 MiB and ≤ 3 minutes; Documents unavailable until
  a secure document workflow is approved; a soft-deleted Owner's media kept 7
  days, its cleanup sweeps (`OWNER_MEDIA_SWEEP_MODE`) off until the owner
  approves them. The attachment UX is the Offer's: system camera (Take photo /
  Record video), one combined Gallery selection, no app-made permission
  dialog.
- Owner media reuses the Offer media lifecycle rather than a second system:
  one Media Worker lifecycle parameterized by the parent record
  (`MEDIA_PARENTS`: its own routes `/owner-media…`, table `owners`, link table
  `owner_media`, key segment `profiles/<uid>/owners/<id>/` and service-role
  confirm function `confirm_owner_media_upload`), and one Flutter upload queue
  whose tasks name their parent (one box, one directory, one sweep, one
  account purge). Parents never reach each other's media: every Worker check
  and the database function compare the object key with the parent's own.
- The Worker's abandoned-upload cleanup at authorize (pending_upload older
  than 24 h) is scoped to one media entity, never the whole account (owner
  decision F1, 2026-09-28): the profile-image authorize withdraws only the
  account's own profile-image keys (`profiles/<uid>/<id>.<ext>`, nothing
  nested), an Offer or Owner authorize only that record's own keys
  (`profiles/<uid>/<segment>/<recordId>/`). The key filter is in the query
  (another entity's older rows cannot fill the 10-row batch) and every row is
  re-checked against the entity's exact key before deletion. Same 24 h
  policy, same batch, account and bucket filters; eligibility only narrowed.
- A photo or video Android hands back after it stopped the app mid-pick
  (`retrieveLostData`) goes back only to the form it was picked on (owner
  decision F2, 2026-09-28), routed by a persisted origin, never by timing
  (`MediaPickRecovery`): before an Offer/Owner picker opens, the form's origin
  — account, Offer/Owner, record id, or a per-form session id while the
  record has none — is saved, and cleared when the picker returns; once per
  process, at start-up before any picker can open, Android's result is kept
  under the origin that was pending, or not adopted when none was (another
  picker in the app) or when it was a not-yet-saved record's form (that form
  did not survive the restart); a form takes only a result whose origin is
  exactly its own, once. Consequence accepted with it: a pick lost while
  adding a new Offer/Owner is not recovered.
- A migration file in `supabase/migrations/` carries the version the hosted
  migration history registered when the owner applied it, so local and hosted
  histories match: the file is renamed afterwards with its SQL byte-identical
  (SHA-256 compared before and after), as for `20260926092220` (Offer) and
  `20260928131828` (Owner). The rollback-only validation script that passed
  against the hosted database is kept exactly as it was run, even where its
  labels still name the earlier file (owner instruction, 2026-09-28).
- Owner media's staging acceptance is a repository runner
  (`cloudflare/workers/r2-profile-upload/staging-acceptance/`), run only by
  the owner and only against the staging Worker, with fresh disposable
  accounts and records. It records statuses, Worker codes and ids only —
  never credentials, account ids, object keys or URLs — and its reports stay
  local (gitignored). F1 needs abandoned uploads older than 24 h, so it runs
  in two phases a day apart (`-Mode Full` seeds, `-Mode F1Verify` checks).
- The six entity list screens (Requests, Offers, Owners, Offices, Brokers,
  Watchmen) share one list lifecycle, `EntityListState` (perf checkpoint,
  2026-09-28): the view model subscribes to its service stream once for the
  screen's lifetime and keeps the last list it received. The loading
  placeholder shows only before the first list, the empty state only for a
  list that is genuinely empty, and a refresh, a failed refresh or a delete
  never takes the list off the screen. A delete marks only its own item
  (dimmed, not interactive, progress indicator), removes it once the server
  accepts, restores it on failure, and a second delete of the same item runs
  nothing. A list is never refreshed by re-creating its stream: Supabase
  re-reads on `CoreEntityMutationNotifier` and Firestore snapshots update by
  themselves. Lists are deliberately not cached across visits: a retained
  list would be account-scoped data that sign-out and Delete Account's cache
  inventory would have to clear, which is a separate owner decision.

- Single active Broker Wallet session source decision (2026-10-05, unverified):
  `auth.users.id` stays the only identity; a one-row active pointer plus a
  once-per-Supabase-`session_id` claim ledger selects the account's sole app
  session. Restrictive RLS, the client-callable quotation RPC wrapper, and a
  shared Worker gate refuse displaced JWTs. The active row remains readable
  by its owner for Realtime observation. Flutter validates restored sessions
  before publishing app identity, and signs displaced sessions out with
  explicit local scope. The built-in paid Auth setting and hardware binding
  are not used. `SignOutScope.others` is supported by the pinned SDK but is
  not invoked after a claim because another new claimant may win between the
  claim and the Auth API call. Premium authorization must require both paid
  entitlement and an active Broker Wallet session. Source and migration are
  not deployed or runtime verified; see `docs/CURRENT_CHECKPOINT.md`.

- Offer / Owner land / plot plan (decided 2026-10-13; checkpoint #7 closed
  2026-10-17: migration applied and verified, staging and production Worker
  deployed, Samsung accepted; see `docs/CURRENT_CHECKPOINT.md`): one optional plan per Offer
  and per Owner record, kept apart from the photo and video gallery. Model: a
  server-controlled pointer column `plan_media_id` on `offers` and `owners`
  (the shape of `quotations.pdf_media_id`), never a row in `offer_media` /
  `owner_media`, because the 10-item limit, the Worker's list, capacity and
  sweep queries and the app's card all count every link whatever its role.
  Its object key has its own segment (`profiles/<uid>/offer-plans/<offerId>/
  <mediaId>.<ext>`, `.../owner-plans/...`): inside the account prefix Delete
  Account sweeps, outside the gallery's key patterns. A plan is addressed only
  by its media id; no URL or storage key is stored or shown. Types: JPEG, PNG
  and WebP up to 10 MiB (the gallery's image contract; HEIC is converted on the
  device) and PDF, DOC, DOCX up to 25 MiB; no SVG, archive, executable or CAD.
  DOC and DOCX use the existing `media_type` value `unknown` (a new enum value
  would break rollback-only validation) and are told apart by content type.
  Their first bytes show only a container, which Excel and PowerPoint share, so
  the Worker proves a DOC or DOCX is Word's own before it attaches one
  (`proveWordDocument`: a few ranged reads of the stored object, no
  dependency): a DOCX's root relationship must name exactly one main part that
  is in the archive and `[Content_Types].xml` must give it the WordprocessingML
  main content type, by its own Override or else the Default for its extension
  (a workbook, a presentation, a macro-enabled document and a template name
  another); a DOC's root directory must hold the `WordDocument` stream and none
  of `Workbook`, `Book` or `PowerPoint Document`. Anything
  malformed, hostile or oversized fails closed, and a storage error is retried,
  never taken for a verdict. It shows which application's document the file
  claims to be, not that it is a well-formed document: a hand-forged Word
  package or stream still passes. The app's file-name check is UX only and the
  Worker stays authoritative. Replacement is switch-then-retire in one
  transaction with compare-and-swap on the expected media id: the old plan
  stays attached until the new file is confirmed, and a failed or abandoned
  upload never touches it. A change that touches only the pointer keeps the
  record's `updated_at` and `version` (a plan is an attachment, not an edit of
  the record's fields, and must not reorder Home's Recently Updated). The
  plan is sent only after
  its record is saved; a plan failure never undoes that save and the same
  upload id is retried. Its cleanup sweeps follow the parent's own
  `OFFER_MEDIA_SWEEP_MODE` / `OWNER_MEDIA_SWEEP_MODE` (`off` in every
  environment), so no new configuration exists. Its pickers pass no recovery
  origin, so a pick Android hands back after stopping the app is never adopted
  into a gallery. A PDF opens in Broker Wallet's PDF viewer and an image in its
  image viewer; there is no in-app Word renderer, so DOC and DOCX are opened by
  another app on the phone from an app-verified local file (or shared), and the
  card says so. The document Scanner is not offered: the app's scanner is a
  private flow of the Toolkit screen (the plugin's dynamic result shapes, its
  own quota and its own list), not a reusable service, and wrapping the plugin
  would be a second scanner integration. Removing a plan unbinds and retires
  only the plan, never the Offer or Owner. Every plan route sits behind the
  Single Active Device gate and is scoped by owner, record kind and parent id, so
  an Offer plan, an Owner plan and the gallery can never reach one another or
  another account's files. See `docs/CURRENT_CHECKPOINT.md`.
- Document Scanner production readiness (decided 2026-10-17, branch
  `scanner-production-readiness`, source only; device acceptance pending):
  - The scan engine stays `flutter_doc_scanner`, now `^0.0.21` (the lockfile
    already recorded 0.0.21 while `pubspec.yaml` said `^0.0.16`, which for a
    0.0.x version means exactly 0.0.16). Android uses Google's ML Kit Document
    Scanner (Google Play services); iPhone uses VisionKit. Crop, rotate, retake,
    delete-a-page and filters happen in that native screen; the app adds no
    competing editor.
  - Scans are stored per signed-in account in
    `<app documents>/scanner/<account>/` (`files/<id>.<ext>` plus
    `index.json`), never in the old device-wide `scanned_documents`
    SharedPreferences list. The old list carried no owner, so it is **not
    migrated, not shown and not deleted**: its entries and files stay on the
    phone and the Scanner shows a one-line count. Attributing them to an account
    is an owner decision (it can only be a guess).
  - A save is journaled (pending → file written and verified → ready) and a
    delete is journaled (deleting → removed), so an interrupted operation is
    finished or undone on the next load and a deleted document cannot reappear.
    A damaged index is set aside, never deleted, and rebuilt from the valid
    files. Titles are metadata; stored file names are internal ids only.
  - One scan is one usage unit however many pages it has, counted once after the
    whole scan was stored. The free-plan check runs before the scanner opens. It
    still reads the legacy Firestore document and is fail-open and not
    authoritative for a Supabase account; replacing
    `scanner_usage_gate.dart` is the whole server-authoritative-quota change.
  - Android All Files Access (`MANAGE_EXTERNAL_STORAGE`) is removed: the
    Scanner was its only consumer. Scans go to app storage; export to Downloads
    uses MediaStore (`IS_PENDING`) on Android 10+ and the legacy storage
    permission only on Android 9 and below. The `file_saver` channel keeps
    `saveFileToDownloads` unchanged for Combine PDFs, Images to PDF and
    Signature and adds file-based methods for the Scanner.
  - The Scanner shows only options that change what happens: output type, page
    limit and a label-only mode. Quality choices are shown disabled (neither
    platform scanner accepts a quality), and there is no AI, enhance, crop,
    background-removal, OCR or batch claim. Arabic or any OCR is not offered.
  - The iOS deployment target is 15.0 (it was 12.0). The Scanner plugin needs
    13.0 and the app's pinned Firebase plugins need 15.0, so 15.0 is the lowest
    value the project can build at; it matches Flutter's current template. iOS
    compile and iPhone runtime are not run.
  - A scan whose Android result the plugin lost (its Activity detached while the
    scanner was open and the engine survived) ends in a "scan interrupted, nothing
    saved, Retry" state instead of waiting forever. A small native listener
    (`ScanLifecycleGuard.kt`) reports the detach only while a scan is watched; the
    engine races the plugin against it. No timer is used, a slow or backgrounded scan is
    never ended, and the plugin is not forked. The result itself is still lost.
  - Scanner documents are excluded from Android cloud backup and device transfer
    (`app_flutter/scanner`, `mlkit_docscan_ui_client`) and from iPhone backup
    (`isExcludedFromBackup` on `Documents/scanner` and on scanner outputs). Scans are
    therefore not restored onto a new phone; export or share keeps a copy. Old ownerless
    scans in the `app_flutter` root remain backup-eligible until the owner decides.
  - Not claimed: encryption at rest (scans are plain files in the app's private
    storage), real-device behaviour, or secure entitlement enforcement. See
    `docs/CURRENT_CHECKPOINT.md`.
- Combine PDFs production readiness (decided 2026-10-18, branch
  `combine-pdfs-production-readiness`, source only; device acceptance pending):
  - Pages are copied with Syncfusion's `createTemplate()` onto pages that keep the
    source's own size, orientation and rotation (the old route forced A4). This carries
    text, fonts and geometry. It does not carry links, bookmarks or annotation objects.
  - Form fields and annotations are flattened by flatten, save and reload of an in-memory
    copy (a template of an in-memory flattened page lacks the values), and the user is told
    on the file's card. Links and bookmarks are dropped and disclosed. The combine is never
    described as lossless.
  - Signed PDFs and encrypted PDFs (with a password, or owner-only protection that opens
    without one) are **refused**, never opened with a supplied password and never copied:
    a combined copy cannot carry a signature, and copying pages would strip the owner's
    protection. No password is requested or stored.
  - A combine is all or nothing: no page or file is skipped; the output is read back (page
    count, per-page size/rotation, per-page text against its source page) before it is
    stored, and read back again after it is copied into the store. Failure or cancel stores
    and counts nothing. PDF work runs on a worker isolate that Cancel stops.
  - Combined PDFs are stored per signed-in account in
    `<app documents>/combine_pdfs/<account>/` with the Scanner's journaled store design
    (not shared code: a PDF-only store of the same shape). The old device-wide
    `combined_pdf_documents` list and its files are not migrated, shown or deleted; the
    screen shows a count. Attributing them is an owner decision.
  - Export reuses the Scanner's file-based route (`exportFileToDownloads`, Files save
    sheet); Share uses `ShareLive` with title-named copies. The system picker needs no
    permission, so none is requested. `saveFileToDownloads` stays for Images to PDF and
    Signature.
  - One combined PDF is one usage unit, recorded once after it was stored, through
    `combine_usage_gate.dart` (legacy Firestore, fail-open, not authoritative; replacing
    that class is the whole server-authoritative-quota change).
  - `app_flutter/combine_pdfs` is excluded from Android cloud backup and device transfer
    and from iPhone backup; combined PDFs are not restored onto a new phone and are not
    encrypted at rest.
  - No page thumbnails: none were added because that needs a renderer dependency.
- Images to PDF production readiness (decided 2026-10-18, branch
  `images-to-pdfs-production-readiness`, source only; device acceptance pending):
  - The picture pipeline is pure Dart (`package:image`) on worker isolates, the PDF is built,
    read back and encrypted with Syncfusion (already in use). Nothing is resized or recompressed
    at pick time (the old `imageQuality: 85, maxWidth: 1920` is gone). Every picture is opened
    completely when it is added, so a damaged one is found then; none is ever skipped or
    replaced by a fallback.
  - **Quality** means print resolution at the placed size (96/150/200/300 dpi), never above the
    picture's own pixels. **Compression None never recompresses with loss**: an upright baseline
    JPEG keeps its data byte for byte (metadata removed), anything that must change is stored
    losslessly (large). Low/Medium/High/Maximum are JPEG 92/85/75/60; PNG sources stay lossless
    at None and Low. The UI states the tradeoff for small print, stamps and plans.
  - EXIF orientation is applied exactly once (the JPEG decoder applies it; the raw bytes are only
    read to decide whether a file may be kept). Transparency is flattened to white. All metadata
    (EXIF/GPS/XMP/ICC/comments/thumbnails/trailing data) is removed on every path. HEIC/HEIF is
    converted to JPEG by the phone's own decoder at selection; where unavailable it is refused
    by name.
  - Layouts never crop or distort. Margins are millimetres. Tile Multiple is a real 2/4/6 grid,
    reading order left to right then top to bottom. One timestamp is captured per PDF and
    printed as `yyyy-MM-dd HH:mm`; page numbers are `n / total` of the PDF's pages (the cover is
    page 1 and unnumbered). Text on a PDF is Latin (standard font) or Arabic (bundled Noto Naskh
    Arabic); other scripts are refused. A cover page exists only when asked for.
  - **Draft first**: the PDF is made once as a verified draft; Preview opens that file; Save stores
    that file; any change to the pictures, order or settings discards it. One stored PDF is one
    usage unit, recorded once after it was stored, through `image_pdf_usage_gate.dart` (legacy
    Firestore, fail-open, not authoritative; replacing that class is the whole
    server-authoritative-quota change).
  - **Password protection** is AES-256 (revision 6) on the finished PDF, proven both ways before it
    is accepted. The ASCII password lives in memory only (never stored, logged or part of the
    settings) and has no recovery. Combine PDFs refuses protected PDFs (S2); the UI says so. No
    other algorithm is offered; RC4 and AES-128 are not used.
  - Converted PDFs are stored per signed-in account in `<app documents>/image_to_pdf/<account>/`
    with the Scanner's journaled store design (a PDF-only store of the same shape, with drafts and
    private picture copies). The old device-wide `converted_pdf_documents` list and its files are
    not migrated, shown or deleted; the screen shows a count. Attributing them is an owner decision.
  - Export reuses the Scanner's file-based route; Share uses `ShareLive` with title-named copies.
    `saveFileToDownloads` is now used only by Signature. The system pickers need no permission,
    so none is requested; the camera is the phone's own app via `image_picker`.
  - `app_flutter/image_to_pdf` is excluded from Android cloud backup and device transfer and from
    iPhone backup; converted PDFs are not restored onto a new phone and are not encrypted at rest.
  - Limits (memory, not policy): 100 pictures, 100 MB per file, 50.5 MP per picture, 300 MB of
    picture data per PDF.
  - A pick lost when Android kills the app is recovered through the existing shared
    `MediaPickRecovery` (one result slot, read at start-up), extended with a `ToolPickOrigin`
    (account + tool): recorded before the picker opens, cleared when it returns, taken once by the same
    account only, in pick order, and never by an Offer/Owner form (nor the reverse). Recovery adds
    pictures through the ordinary add; it never converts, saves or counts. The gallery uses the system
    Photo Picker explicitly. No broad picker redesign was needed.
- Document Signature production readiness (decided 2026-10-18, branch
  `document-signature-production-readiness`, source only; owner verification pending):
  - The tool places **visible** marks (drawn signature, initials, date, text). It is not a
    certificate-based digital signature and never claims signer identity, UAE accreditation, legal
    certification or non-repudiation; the preview says so. No certificate, UAE PASS or trust
    infrastructure is part of this tool.
  - **Geometry is one model.** A placement is a rectangle in the visible page's own points. The visible
    page is the CropBox clipped to the MediaBox (the MediaBox when there is no usable CropBox) turned by
    `/Rotate`, all read from the page's own dictionary (inherited from the page tree), never from
    Syncfusion's `PdfPage.size`. Pages whose boxes cannot give a page, or whose size PDFium and the file
    disagree on by more than a point, are refused rather than guessed.
  - **The editor draws the page as a bitmap and the items in the same box inside the same
    zoom-and-pan transform**, converting fingers with the box's own `globalToLocal`. It replaces
    `flutter_pdfview` for Signature (its overlay could not track the page); the shared PDF viewer is
    untouched. PDFium comes through `pdfrx`, already a dependency.
  - **The export writes in user space, not in the library's drawing space.** The engine reads back the
    translation Syncfusion sets up for a loaded page, cancels it, and draws an axis-aligned image at the
    geometry's user rectangle; for a rotated page it turns the image's pixels instead of using a rotation
    matrix. Stamps are transparent PNGs (drawn ink at 3x, text at 4x), so a placed item keeps its
    proportions and the preview and the file show the same picture. Text, dates and initials are therefore
    images, not selectable text.
  - **The original is never rewritten.** Syncfusion's incremental save keeps the original bytes and appends
    the changes, so links, forms, annotations and unrelated pages are untouched; flattening and page
    templates (which lose them) are not used, and the form of the document being saved is never read. The
    copy is verified (pages, boxes, rotation, form-field and annotation counts, no encryption or signature)
    before it is accepted. A PDF that already carries a digital signature (signature field or `/ByteRange`)
    is **refused**, and a protected PDF is **refused**; neither is ever opened with a bypass.
  - **Draft first.** Save writes a verified draft in the account's `work/` folder and opens the preview of
    that file; the preview's Save stores those bytes (compared byte for byte); any change to the items
    discards the draft. One stored document is one usage unit, recorded once after it was stored, through
    `signature_usage_gate.dart` (legacy Firestore, section `signature`, fail-open, not authoritative;
    replacing that class is the whole server-authoritative-quota change).
  - Signed documents are stored per signed-in account in `<app documents>/signature_pdfs/<account>/` with the
    Scanner's journaled store design. The old device-wide `signed_documents_list` preference and the
    `signed_documents/` files carry no owner: they are not migrated, shown, moved or deleted; the screen
    counts them. Attributing them, and whether they should leave backup, is an owner decision.
  - Export reuses the Scanner's file-based route; Share uses `ShareLive` with title-named copies. The
    system picker needs no permission, so none is requested. No Toolkit tool uses `saveFileToDownloads`
    any more (the native method stays for contract).
  - `app_flutter/signature_pdfs` is excluded from Android cloud backup and device transfer and from iPhone
    backup; signed documents are not restored onto a new phone and are not encrypted at rest.
  - The reusable signature is **session-only**; a persisted one would need encrypted, account-isolated
    storage with a deletion path, which was not built. Signature images are never written to disk except
    inside the saved PDF.
  - Items are placed by gesture on a recognizer that wins on the first touch (one finger moves, two
    resize, corner handles resize), so zoom and pan around them do not compete; the page itself zooms and
    pans. Limits (memory, not policy): 50 MB, 1000 pages, 100 items, 4 MB and 4096 px per stamp.

- UAE Useful Links production readiness (decided 2026-10-19, branch `uae-useful-links-production-readiness`):
  - **One curated catalogue, bilingual content in Dart.** `UAELinksData.entries` holds each service once, with
    emirate set, task tags, type, URL, authority, Arabic/English text, last-verified date, status and evidence.
    Directory content is reviewed together with its evidence, so it is not split across ARB files; screen chrome
    stays in ARB (`ulx*`). No remote CMS, database or backend.
  - **Publishing rule.** Only `verifiedOfficial` and `officialManualCheckRequired` entries are shown; a
    `.gov.ae` domain or an HTTP 200 alone never earns VERIFIED. Entries whose destination could not be confirmed
    say so on the card. No commercial portals, classifieds, shorteners or referral links; a private payment
    platform (Noqodi) is labelled as a payment platform and is not classed as government.
  - **Safe opening.** Addresses open only through `UaeLinkLauncher` after `UaeLinkUrlPolicy` (HTTPS, official
    domain on whole labels, no userinfo/odd port/IP/punycode), in the external browser. No WebView, proxy,
    scraping, credential entry, or identifiers appended to a URL; opening a site is never reported as a completed
    service.
  - **Broken-link report is copy/share only.** The text is built from fixed fields and shared by the user
    through the system sheet; no silent sending, no invented support address.
  - **Emirate assignment follows the operating authority** (Tasdeeq is Ajman). UAE-wide means federal only; the
    UAE-wide group stays visible under any emirate filter.
  - The verification register is `docs/toolbox/uae-links-verification.md`; the catalogue test enforces ids,
    domains, coverage, language completeness and metadata.
- Toolkit cloud documents (decided 2026-10-19, branch `toolkit-cloud-documents-readiness`; checkpoint C1 is source only):
  - **Toolkit documents are cloud-backed account data; local storage is a cache and an offline working layer.**
    The PDFs of Scanner, Combine PDFs, Images to PDF and Document Signature must survive reinstalling the app and
    moving to a new phone, by signing in to the same Supabase account. Local-only storage is no longer the final
    persistence model. Deal Pack Builder, Inspection Reports, Floor Plan Markup and the UAE Transaction Assistant
    are future work and not part of this.
  - **One shared foundation, no parallel identity.** One table `public.toolkit_documents` (the tool is the
    `document_type` column), bytes in the existing private R2 bucket under
    `profiles/<account>/toolkit-documents/<id>.pdf`, the existing `r2-profile-upload` Worker, the existing Supabase
    Auth identity, Single Active Device gate and Delete Account sweep. It deliberately does not reuse
    `media_objects`: that is the gallery / plan model. The object key is derived on the server, pinned by a CHECK
    constraint and never returned to the client; the id is the local document's UUID and is the idempotency key of
    every operation.
  - **Server-controlled state.** `authenticated` may only read its own ready rows through a column list without the
    bucket or key; every change goes through service-role-only `SECURITY DEFINER` functions (authorize / confirm /
    rename / begin-delete / finalize-delete / discard-abandoned), with a guard trigger that freezes identity for every
    role. Every Worker read is scoped by bucket because staging and production share one Supabase project.
  - **Honest states.** "Saved to cloud" is set only after the server confirmed the stored bytes; a document that is
    only on the phone says so and is described as not protected against device loss. A document deleted elsewhere is
    tombstoned (180 days) and never uploaded again; an abandoned upload that never became ready is removed without a
    tombstone so a slow device can still upload it. The coordinator never deletes a local file.
  - **Conflicts.** Bytes of an id never change: no "newer copy" exists. A same-id file with different bytes is a
    conflict that overwrites neither side; renames are compare-and-swap on the version, retried once.
  - **Limits are anti-abuse, not entitlements.** Per-PDF, per-account bytes and count, pending uploads, uploads per hour
    and attempts per upload are configurable Worker variables with hard ceilings enforced by the database; paid-plan
    quotas (RevenueCat) stay separate future work.
  - **Not end-to-end encrypted; the local cache is not encrypted.** The Privacy Policy, Terms and the store data
    disclosures must be updated before cloud document storage is enabled; existing legal decisions stand until then.
  - **Inactive until reviewed.** Every route answers 404 unless `TOOLKIT_DOCUMENTS_ENABLED` is exactly `"true"` (ships
    `"false"`), the sweep ships `off`, the Flutter foundation is imported by nothing and `TOOLKIT_CLOUD_DOCUMENTS` is a
    compile-time switch that is off. The four tools keep their local stores until the migration of existing documents
    is separately implemented and verified.
  - **C3 (2026-10-21): Combine PDFs is the one tool wired to the cloud, in a DEBUG build only.** `ToolkitCloudDocumentsFeature.isActive` is
    `TOOLKIT_CLOUD_DOCUMENTS=true` AND `kDebugMode` (profile and release builds are always local). Toolkit documents have their own Worker address
    (`TOOLKIT_WORKER_URL`) and staging gate key (`TOOLKIT_STAGING_KEY`), both honored in a debug build only and never applied to the shared
    `R2_UPLOAD_WORKER_URL` (Profile, Offer media, plans, account deletion). The key is never sent to the shared host or to signed storage URLs. The
    other three tools stay local (superseded by C3.2 below). A release build cannot reach the cloud until a later checkpoint changes that on purpose, after the Samsung
    result and the legal text. The tool's local store remains authoritative for names and files; the cloud copy never deletes a local file before the
    server confirmed the delete.
  - **C3.2 (2026-10-21): all four tools use the account copy, through one object each tool's view model owns (`ToolkitCloudSync`).** The phone's store stays the
    working copy and works offline; documents on the phone are recorded on the journal and uploaded (also ones made before the cloud was on); what the account holds
    and the phone lacks is downloaded, hash-verified and stored by the tool's own store (`restoreFromCloud`, same id), so the tool's list shows it like any other
    (Combine PDFs lists it first and downloads on open). A delete reaches the account first and the phone's file goes only after the server confirmed it. One library
    is shared per account and tool, so a screen closing never stops work in flight. The user is told the truth on every screen (one status line, including WHY the
    account cannot be reached). Details the account does not keep (scan type, image grouping, picture count, signature counts) are unknown after a restore.
    The app default stays OFF until the owner approves turning it on AND approves deploying the Worker to production (the live production Worker has no Toolkit code):
    see `docs/toolbox/cloud-documents-production-enable.md`.
  - **C3.3 (2026-10-21): the account copy is ON by default, in every build; the production Worker is next.** The owner approved it in chat ("do whatever it needs to make sure the doc is
    showing just like the other data ... all accounts are for testing, the app is not launched yet"). `ToolkitCloudDocumentsFeature.enabled` defaults to `true` and `isActive = enabled`;
    `--dart-define=TOOLKIT_CLOUD_DOCUMENTS=false` is the kill switch. The staging address and gate key stay debug-only, so a release build only ever talks to the shared production address.
    This supersedes the debug-only and default-off statements of C3 and C3.2. The production Worker must serve the routes first (`TOOLKIT_DOCUMENTS_ENABLED = "true"`, sweep `off`, set in the
    production `wrangler.toml`; the deployment waits for the owner's specific approval, see `docs/toolbox/cloud-documents-production-enable.md`); until then a normal build says
    "not available on this server yet" and keeps documents on the phone. The privacy policy, terms and store disclosures must be updated before a STORE release.
  - **C3.4 (2026-10-21): the production Worker serves Toolkit cloud documents.** Deployed on the owner's specific approval (version `64a9589b-718b-4419-8594-cb6fef01c021`, rollback `96783f3d`). The module is
    byte-identical to the one the accepted staging Worker serves (`worker.js` sha256 `f45173f3…fd4e`), the only code delta against the previous production Worker is the Toolkit module, and the only new
    variables are `TOOLKIT_DOCUMENTS_ENABLED = "true"` and `TOOLKIT_DOCUMENT_SWEEP_MODE = "off"`. Identity is proven by downloading the served module read-only and comparing bytes (the etags also matched once the
    candidate was built with the same wrangler copy as the staging upload). Real-phone verification remains the owner's; store disclosures remain open.
  - **Open owner decisions.** Historical ownerless legacy files (attribute, discard or keep local); Scanner image scans
    (JPEG / PNG are not PDFs: convert, allow image types, or keep local); the limits and cost proposal; the exact
    hosted SQL, grants, routes and rollback.
  - Design, contracts, rollout and rollback: `docs/toolbox/cloud-documents-rollout.md`.
- Toolkit cloud documents, C1.1 corrections (decided 2026-10-20; supersedes the C1 "open owner decisions" and the PDF-only wording above; still source only):
  - **Scanner JPEG and PNG are backed up as-is, beside PDF; no conversion and no silent exclusion.** `document_type` is the
    source tool and `content_type` the binary format, two separate frozen fields. Only the Scanner may store images
    (one page each); the other tools store PDF. The server builds the whole key from the verified content type
    (`.pdf` / `.jpg` / `.png`), never from a client name, MIME label or key; unsupported formats are refused before a row exists.
  - **Ownerless legacy documents stay local and isolated.** Never deleted, never auto-uploaded, never assigned to the
    signed-in account, never visible to another account, and a file name or title is never ownership. No recovery
    operation is authorized; a future one needs its own design and approval. Per-account documents remain eligible for
    the later explicit migration, which never moves, rewrites or deletes originals.
  - **Integrity is described at its real level.** The device SHA-256 is a claim; the Worker verifies existence, byte
    length, stored content type, declared-format signature and a complete container (not decoding); the R2 ETag is an
    object-identity token, never a digest; `sha256_verified` is true only when the optional Worker digest ran
    (`TOOLKIT_DOC_VERIFY_SHA256`, off until Cloudflare CPU is measured on staging); the app always verifies size, SHA-256
    and container on download. The product must not claim end-to-end cryptographic verification.
  - **Authorization model.** All Toolkit functions are `SECURITY DEFINER`, `search_path = ''`, revoked from
    `public, anon, authenticated` and granted to `service_role` only; clients read their own ready rows through a column
    list without bucket or key; `service_role` has no table privilege; identity (owner, tool, format, key, size, digest) is
    frozen for every role; `FORCE ROW LEVEL SECURITY` is deliberately not used (owner role has BYPASSRLS; RLS already
    applies to client roles). The explicit revoke/grant is required because hosted default privileges grant new functions
    to client roles.
  - **Tombstones are bounded and cannot be silently resurrected.** Deletion keeps a title-scrubbed tombstone for 180 days,
    at most 500 per account; every purge advances a per-account `tombstone_floor`; a new document id older than the floor
    is refused as `stale_document` unless the user explicitly acknowledges; documents that already reached the cloud are
    never re-uploaded (client ledger + reconciler). Abandoned never-ready uploads are removed object-first without a
    tombstone.
  - **Limits stay anti-abuse and non-final.** Recommended starting profile: PDF 50 MiB, image 25 MiB, account 1 GiB, 1,000
    documents, 5 pending, 120 new per hour, 10 attempts; hard ceilings 250 MiB / 64 MiB / 20 GiB / 5,000 / 20 / 1,000 / 100.
    The owner decides the numbers; they are Worker variables, not RevenueCat entitlements. The Free database size, not R2
    cost, is the first ceiling.
  - **Nothing hosted without a separate approval of the exact, frozen migration.** Staging and production share one
    Supabase project; the ordered sequence, stop conditions and rollback are in `docs/toolbox/cloud-documents-rollout.md`.
- Toolkit cloud documents, C2A preflight (2026-10-20; source unchanged, nothing hosted):
  - **The candidate is frozen by hash.** The migration's canonical (LF) SHA-256 is
    `88ceb6c2f8f6b62b9bbec73e6932f3843b333a13c114425b7ef7eaad20d5ad4d`; any edit to it restarts the review. The Worker
    modules and entrypoint are hashed in `docs/toolbox/cloud-documents-rollout.md` section P.
  - **Order of hosted work stays gated.** Read-only baseline (done) → separately approved rollback-only validation →
    separately approved apply of the one migration → read-back → staging Worker with the flag off, then on → acceptance →
    production only after legal updates and a further approval. Each step stops on any mismatch and none runs automatically.
  - **Integrity wording.** While `TOOLKIT_DOC_VERIFY_SHA256` is unset, `sha256_verified` is false for every document; the
    stored digest is the device's claim and no screen, document or policy may call documents server-verified. Enabling the
    Worker digest is a later decision after a staging CPU measurement.
  - **Capacity statements must be labelled.** The Supabase Free 500 MB is the database allowance and is separate from R2
    storage; the measured Toolkit row cost is about 770 bytes (table + indexes; two runs: 765 and 774). Capacity figures are estimates until measured on
    the hosted project; the earlier "database first at about 100 accounts" claim is withdrawn. Business quotas stay
    undecided and separate from these anti-abuse limits.
  - **Shared database consequence is accepted and must be repeated in every approval:** staging and production share one
    Supabase project, so an applied migration exists in production immediately (empty and inert while the Worker flag is
    off), and staging test data lives in the same table and counts toward the same per-account limits.
- Toolkit cloud documents, C2B corrections (2026-10-20; source only; supersedes the C1 / C1.1 abandoned-upload and PUT wording):
  - **Abandoned-upload cleanup is claim-first.** A row is claimed (`pending_upload → pending_discard`, a compare-and-set under its
    row lock) before its object is removed, and is discarded only for the exact claim identity. A status read before a delete is
    never the safety mechanism, because the status can change before the delete lands. A failed removal stays claimed and is
    retried after a lease; a user delete overrides a claim and keeps its tombstone. The sweep stays off by default.
  - **A signed Toolkit PUT is write-once.** It is signed with `If-None-Match: *`, the Worker returns the header, the app sends it
    and treats a 412 as "an object exists" so the confirm judges that object. This is designed from R2's documented atomic
    conditional PutObject and is NOT considered proven until a staging replay test shows a real presigned URL being refused;
    nothing may claim replay protection before that. The fallback, if R2 ignores the header, is a per-authorization staging key
    promoted by a server-side copy (not built).
  - **The signature does not cover Content-Type.** The stored type is whatever the client sent; the confirm's stored-type check
    remains the control and must not be removed.
  - **The hosted database is only ever given fixture-free, bounded checks.** Anything that needs users, sessions, profiles or
    document churn runs locally or in an isolated database. The hosted rollback-only candidate is
    `supabase/validation/toolkit_documents_hosted_preflight.sql`; the complete suite is not to be run on the shared project.
  - **A changed migration invalidates every earlier hash and review.** The C2A migration and request hashes are superseded.
