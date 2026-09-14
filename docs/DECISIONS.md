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
