Branch:
backend-implementation

Recovery work began on `recovery-profile-auth` from baseline:
cc0951e

Verified Supabase-mode device behavior:

- Signup: PASS
- Home: PASS
- Profile: PASS
- Cold restart while authenticated: PASS
- Manual logout: PASS
- Restart after logout remains unauthenticated: PASS
- Login again: PASS

Completed recovery fix:
Notification token cleanup is best-effort and can no longer prevent authoritative
Supabase logout.

Authoritative logout verification observed:

- Supabase logout completed
- Supabase session after logout absent
- AuthViewModel unauthenticated

Recovery Step 2 — PASS

Verified on hosted Supabase:

- public.notifications is in the supabase_realtime publication.
- migration 20260822000500_add_notifications_to_realtime.sql was applied.
- RealtimeSubscribeException for public.notifications is gone on real device.
- Supabase logout remains PASS.

Recovery Step 3 — PASS

Verified on real device:

- Plain `flutter run` now defaults Auth/Profile to Supabase: PASS.
- Signup appears in Supabase: PASS.
- Login/Home/Profile: PASS.
- Startup Firestore offers/owners/offices/watchmen permission errors are gone:
  PASS.
- Logout and restart behavior: PASS.

Recovery Step 4A — PASS

Verified on real device:

- Unconfigured push notification registration no longer throws an unhandled
  UnsupportedError into signup/verification/login/logout flows: PASS.
- Signup: PASS.
- Email verification link flow: PASS.
- Login: PASS.
- Home: PASS.
- Profile: PASS.
- Logout: PASS.
- Login again: PASS.

Previously observed Welcome-page flash before Home is no longer reproducible and
requires no work now.

Recovery Step 4B — Profile name persistence:

- Name-only Edit Profile save writes successfully to hosted
  `public.profiles`: PASS.
- Hosted Supabase row updated and sync version increased: PASS.
- Cold persistence is authoritative from Supabase: PASS.

Recovery Step 4C — Profile screen refresh:

- Root cause was stale ProfileViewModel display state.
- ProfileViewModel now reacts to refreshed AuthViewModel state.
- New profile name appears immediately on Profile after Save: PASS.
- Home/Search/Favorites continue showing the same new name: PASS.
- Cold restart shows the same persisted name: PASS.

Do not mark image/R2, phone, password, delete account or notifications backend
complete.

PROFILE NON-MEDIA CHECKPOINT — PASS

Verified by human on a real device:

- Name-only save persists correctly to hosted `public.profiles.name`.
- Profile screen reflects the new name immediately.
- `phone_number` before test: `NULL`.
- `phone_number` after name-only save: unchanged `NULL`.
- `phone_e164` before test: `NULL`.
- `phone_e164` after name-only save: unchanged `NULL`.
- No phone-field corruption is confirmed.
- No repository patch is justified.
- No code changes were needed for this verification.

R2 STEP 1 — SUPABASE PROFILE MEDIA CONFIRM RPC — PASS

Verified on hosted Supabase:

- `public.profiles.profile_media_id` exists.
- `public.media_objects` exists.
- `media_status` supports the required profile-media states.
- `confirm_profile_media_upload(...)` exists.
- The RPC is `SECURITY DEFINER`.
- `anon` cannot EXECUTE the RPC.
- `authenticated` cannot EXECUTE the RPC.
- `service_role` can EXECUTE the RPC.
- Migration `20260907000500` is applied remotely.
- Security lockdown migration `20260908000100` is applied remotely.
- Local and remote Supabase migration histories match.

Important security decision:

The Flutter client must never call `confirm_profile_media_upload` directly.
Only the trusted server-side Cloudflare Worker may invoke it using the
server-side Supabase secret/service credential.

R2 STEP 2 — CLOUDFLARE PROFILE IMAGE BACKEND PREVIEW — PASS

Verified preview behavior:

- `/authorize` without token: 401 PASS.
- `/authorize` with invalid token: 401 PASS.
- Valid token with mismatched `userId`: 403 PASS.
- Valid `/authorize`: PASS.
- Object key is scoped to the authenticated user: PASS.
- Signed PUT URL: PASS.

Valid image E2E:

- Private R2 signed PUT: PASS.
- Actual uploaded image size: 78596 bytes.
- `/confirm`: PASS.
- `media_objects.status` is `ready`.
- `public.profiles.profile_media_id` links the same media object.
- `/profile-image-url`: PASS.
- Signed GET: PASS.
- Downloaded bytes match the original.
- Downloaded SHA256 equals the original SHA256: PASS.

Security:

- R2 `r2.dev` public access is disabled.
- R2 custom public domains: none.
- MIME-mismatch upload is rejected by `/confirm` with 422.
- Rejected media row becomes `failed`.
- Rejected media is not linked to the profile.
- Good media remains `ready` and linked.

RPC:

- Profile-media-id ambiguity migration was fixed and applied.
- Confirm RPC remains `SECURITY DEFINER`.
- `anon` EXECUTE: false.
- `authenticated` EXECUTE: false.
- `service_role` EXECUTE: true.

PROFILE IMAGE BACKEND — PRODUCTION PASS

Cloudflare Worker:

- Worker: `r2-profile-upload`
- Production endpoint: https://media-api.brokerwallet.ae
- Production Version ID: `491a5e0f-6b51-4ca9-8d33-8164bcfec348`
- Production traffic: 100%

Preview backend verification PASS:

- `/authorize` auth/security checks: PASS.
- Private signed PUT: PASS.
- `/confirm`: PASS.
- `Supabase media_objects` status becomes `ready`.
- `public.profiles.profile_media_id` linked atomically.
- `/profile-image-url`: PASS.
- Signed GET: PASS.
- Downloaded image SHA256 matches original.
- R2 `r2.dev` public access disabled.
- No custom public R2 domain.
- MIME mismatch rejected with 422.
- Invalid media row marked `failed`.
- Invalid media never linked to profile.

Production smoke verification PASS:

- `/authorize` without token: 401.
- `/profile-image-url` with real Supabase token: PASS.
- Signed GET URL returned.
- Production signed GET downloads the correct 78596-byte image.
- SHA256 matches original image.
- Custom domain `media-api.brokerwallet.ae`: PASS.
- `brokerwallet.ae` and `www.brokerwallet.ae` remain working.

Supabase:

- `confirm_profile_media_upload` RPC ambiguity fix applied.
- RPC remains `SECURITY DEFINER`.
- `anon` EXECUTE: false.
- `authenticated` EXECUTE: false.
- `service_role` EXECUTE: true.

Do not repeat destructive backend security tests in production unless there is
a concrete reason.

FLUTTER-P1 — R2Config + R2ProfileUploadService — PASS

Verified:

- Production Worker default: https://media-api.brokerwallet.ae
- `R2_UPLOAD_WORKER_URL` dart-define override remains supported.
- Plain Flutter runtime requires no R2 Worker dart-define.
- `R2ProfileUploadService` supports:
  - authenticated `/authorize`
  - direct signed PUT
  - `/confirm`
  - `/profile-image-url` signed read
- User identity/token comes from the current Supabase session.
- No Supabase secret/service_role credential exists in Flutter.
- No R2 access/secret credential exists in Flutter.
- No signed URLs or auth tokens are logged.
- No Firebase fallback was added.
- Targeted analyze: PASS.
- `git diff --check`: PASS.
- Backend production was already verified PASS.
- Real-device integration is N/A for P1 because no UI/repository path is wired
  yet.

FLUTTER-P2 — SIGNED PROFILE IMAGE READ — PASS

Verified by human on a real device:

- Login: PASS.
- Home: PASS.
- Profile opens: PASS.
- Existing R2 profile image resolves through the production Worker: PASS.
- Cold restart: PASS.
- Profile image remains available after restart: PASS.
- Name/profile text unchanged: PASS.
- No Auth/Profile crash: PASS.
- Previous screen-switching image flicker is fixed.
- Welcome-page flash previously observed after login is no longer reproducible
  and requires no current work.

Minor non-blocking UX observation:

- On a full cold app start only, the profile image may visibly refresh once
  before stabilizing.
- This does not affect data, authentication, Supabase
  `profile_media_id`, or final image correctness.
- Do not open a new fix for this now.
- Re-check during final Profile UX polish after upload integration is complete.

AUTH / NAVIGATION / PROFILE STABILIZATION — PASS

Commits: `94e7315`, `998e31e`, `ca77d03`, `905702d`, `5534730`.
Real-device status as recorded by the project owner in the Broker Wallet
Master Context (2026-09-12):

- Supabase canonical Auth/Profile: PASS.
- Session-first auth bootstrap: PASS.
- General auth navigation owned by GoRouter: PASS.
- Authenticated cold starts 10/10: PASS.
- No Welcome flash: PASS.
- Login / logout / logged-out restart: PASS.
- Profile last-known-good cold-start presentation: PASS.
- Optimistic profile name save: PASS.
- Optimistic profile image save: PASS.
- Home/Profile/Search/Favorites parity: PASS.
- Flutter profile-image integration (FLUTTER-P3): PASS.
- Stable media-id/local-cache profile image presentation: PASS (supersedes the
  cold-start image refresh observation above).
- Facebook authentication removed: PASS.

PHONE/OTP CHECKPOINT — DEFERRED (EXTERNAL SMS CONFIGURATION)

PHONE/OTP BACKEND + APP IMPLEMENTATION = READY
HOSTED DB SECURITY = PASS
REAL UAE SMS DELIVERY = EXTERNAL CONFIG PENDING
FINAL PHONE RUNTIME PASS = DEFERRED UNTIL SMS PROVIDER + UAE SENDER SETUP

Flutter implementation (committed in `0148dbd`; CODE_PROVEN, not
VERIFIED_RUNTIME):

- Phone change uses Supabase Auth's own flow only: `updateUser(phone)`,
  `verifyOTP(type: phoneChange)`, `resend(type: phoneChange)`.
- `public.profiles` phone fields are a read-only mirror of Supabase Auth; the
  app never writes them.
- No custom OTP storage, no fake success, no account merging.

Hosted Supabase phone database security — PASS:

- Rollback-safe database validation
  (`supabase/validation/phone_security_validation.sql`) passed on hosted.
- `authenticated` cannot directly update `public.profiles.phone_number`.
- `authenticated` cannot directly update `public.profiles.phone_e164`.
- `authenticated` can still update allowed fields such as `name` and
  `preferences`.
- The `guard_pending_phone_change` trigger on `auth.users` is installed and
  enabled.
- Normal authenticated users cannot execute the guard or cleanup functions.
- No pending `phone_change` existed at hosted verification time.
- Both phone security migrations are applied in hosted migration history:
  - `20260911000100_revoke_client_profile_phone_writes.sql`
  - `20260911000200_guard_pending_phone_changes.sql`

Real SMS delivery — EXTERNAL CONFIG PENDING:

- Supabase phone verification requires a real SMS provider.
- The Twilio account is Trial; production messaging needs an upgrade/payment.
- Broker Wallet launches in the UAE; a UAE production sender / Sender ID is
  required, and the business/trade license needed for it does not exist yet.
- Decision: do not pay for or configure production SMS now just to unblock
  development (see `docs/DECISIONS.md`).

Revisit final real-device SMS acceptance only when all of these exist:

- business/trade license
- production SMS provider
- UAE sender registration/configuration

This external dependency does not block unrelated Broker Wallet work.

EMAIL CHANGE CHECKPOINT — REAL-DEVICE TEST FAILED, THEN FIXED

REAL-DEVICE TEST (2026-09-12): FAIL. This falsified the earlier
CODE_PROVEN / READY FOR DEVICE TEST status recorded below.

Status after the runtime fix:
CODE_PROVEN AFTER RUNTIME FIX — AWAITING REAL-DEVICE RETEST.
Not VERIFIED_RUNTIME.

Hosted Secure Email Change is CONFIRMED ENABLED and stays enabled.

Observed failure:

- Request succeeded and the pending state appeared.
- Confirmation emails arrived; the user opened a link.
- The app reopened on `brokerwallet://auth/callback` with no state change and
  no success, partial-success or error feedback.
- Flutter logged an unhandled
  `AuthException(message: Email link is invalid or has expired,
  statusCode: otp_expired, code: access_denied)` from
  `GoTrueClient.getSessionFromUrl` via `SupabaseAuth._handleDeeplink`.

Hosted state read after the failure (read-only, no token values):
exactly one pending email change with `email_change_confirm_status = 1` —
the current-address token cleared, the new-address token still present. One
half of Secure Email Change was accepted; the change never completed.

Root causes, all three proven from source:

1. Error callbacks became unhandled exceptions. `SupabaseAuth._handleDeeplink`
   does catch the `AuthException` and re-publishes it with
   `notifyException`, which surfaces it as an *error on the
   `onAuthStateChange` stream*. Four subscribers had no `onError`
   (`home_viewmodel.dart` x2, `notification_service.dart`,
   `favorites_service.dart`), so it escaped as an unhandled async error.
   `AuthViewModel` did have a handler, but it treated any stream error as a
   failed bootstrap and reset the session to unauthenticated — an expired link
   could therefore present as a logout.

2. The intermediate confirmation was silently dropped. With Secure Email
   Change, GoTrue answers the first of the two confirmations with
   `?message=Confirmation+link+accepted...` and no `code`. The SDK's default
   detection heuristic only recognizes `access_token`, `code`, `error`,
   `error_code` or `error_description`, so that link matched nothing, was never
   delivered anywhere, and the UI could not react.

3. Resend was addressed to the wrong mailbox. `resendEmailChange` passed the
   pending address. GoTrue's resend handler resolves the account with
   `FindUserByEmailAndAudience` over `users.email`, which still holds the
   confirmed address while a change is pending, and then sends to the stored
   `user.EmailChange` itself. The resend could never have worked.

Fix:

- Automatic URI detection stays ON. `detectSessionInUriPredicate` now narrows
  which links Supabase exchanges to those actually carrying `access_token` or
  `code`, so signup verification, magic link, recovery and OAuth are untouched
  while error-only and message-only links are no longer fed to
  `getSessionFromUrl`.
- One application-level `AuthCallbackCoordinator` owns a single subscription to
  `AppLinks()` — itself a singleton, so no second native listener — and
  publishes only the callbacks Supabase declined, classified as session /
  error / informational / unknown. It never creates, refreshes or invalidates a
  session. Supabase remains the only session authority, `AuthViewModel` remains
  the application identity owner, and GoRouter remains navigation authority.
- A callback is only a *trigger*: `EmailChangeViewModel` always re-reads the
  authoritative Supabase user and describes that result. Nothing is concluded
  from the link's own wording, which Supabase may change.
- Only `error` and `error_code` are carried out of a callback. The provider's
  `error_description`, and any token or hash in the link, are dropped at the
  classification boundary and never logged or rendered.
- `resendEmailChange` now sends the confirmed address.
- Every auth-stream subscriber has an `onError`, and an auth-stream error no
  longer demotes an established session — only an unresolved bootstrap may
  still resolve to unauthenticated.

Verified from GoTrue server source (`sendEmailChange`), which both
`UserUpdate` and `Resend` call:

- Secure Email Change regenerates `EmailChangeTokenCurrent` and
  `EmailChangeTokenNew` and resets `EmailChangeConfirmStatus` to 0.
- So a resend, and equally a fresh request for a different address, invalidates
  the earlier links and discards any approval already given. The UI says this.
- A fresh request therefore safely replaces a pending one, which is what makes
  "Use a different email" a real recovery action rather than a fake cancel.
- There is still no server-side cancellation API, so no cancel action is
  offered.

UX redesign:

- Edit Profile keeps the confirmed email as the primary identity row and, while
  pending, carries only a single compact "Email change pending / new address /
  View" line. The large status card was removed.
- The pending detail lives in a focused sheet: current -> new transition with
  Active / Awaiting approval badges, the two-inbox explanation, Check status
  (primary), Send fresh verification emails (secondary, with the cooldown in
  the button label rather than a countdown element), Use a different email, and
  Close, which is always present.
- Returning from the mail app refreshes state automatically, via the callback
  and via a throttled resume that only runs while something is pending.
- Feedback is chosen from authoritative state: completed, partially confirmed
  (only after an informational callback), still pending, or a localized link
  error. No raw provider text reaches the UI.

Local verification after the fix:

- Focused email-change suite: 15/15 PASS.
- New callback/runtime-failure suite: 20/20 PASS.
- Full Flutter suite: 238/238 PASS (was 218).
- `flutter analyze lib test`: zero errors, zero warnings; 112 existing
  informational deprecations in unrelated files.
- No migration, RLS change, Edge Function, email template, hosted setting or
  deployment was touched.

Still unverified — requires the real-device retest:

- Real confirmation emails for both mailboxes after a fresh request.
- The intermediate callback producing partial-confirmation feedback.
- The final callback completing the change and updating the confirmed email.
- An expired link producing the localized recovery state and no crash.
- `public.profiles.email` mirror and cold restart after a real confirmation.

Known unresolved risk: Supabase documents that some mail providers prefetch
links, which consumes `{{ .ConfirmationURL }}` and yields exactly this
"expired or invalid" error. The recovery path now handles that case, but if
fresh links keep failing immediately in controlled retesting, the cause is
prefetch, not this fix, and an OTP-based Email Change template becomes a
separate decision. No email template was changed here.

Historical record of the now-falsified status follows.

EMAIL CHANGE CHECKPOINT — CODE_PROVEN / READY FOR DEVICE TEST

Local implementation and verification completed on 2026-09-12. This is not
VERIFIED_RUNTIME until the hosted setting and real-device mailbox/callback flow
are exercised.

Implemented behavior:

- Existing authenticated Supabase users can start an email change from Edit
  Profile without a second password ceremony.
- `auth.users.email` remains canonical until Supabase confirms the change.
- Pending presentation comes only from Supabase `User.newEmail` and
  `emailChangeSentAt`; no durable client copy is created.
- Request and resend use the current Supabase session uid, the existing
  `brokerwallet://auth/callback`, and the pinned SDK's
  `resend(type: emailChange)` support.
- Auth identity and pending email share the repository's existing single
  Supabase auth-event pipeline. An authoritative `getUser()` refresh publishes
  completion to `AuthViewModel` without a second auth listener.
- Flutter never writes `public.profiles.email`; the existing server identity
  sync remains responsible for the mirror.
- There is no fake server cancellation. UI copy states that ignoring the
  request leaves the current confirmed email unchanged.
- Supabase failures are mapped to fixed domain outcomes and localized EN/AR;
  raw provider messages and exceptions do not reach this UI.
- The conditional no-email Add Email flow remains unchanged and separate. It
  still carries the previously audited Firebase-oriented/partial-update risk.
- The previously unreachable `SupabaseAuthRepository.updateEmail(newEmail,
  currentPassword)` override no longer performs its own password
  reauthentication ceremony. It now delegates to `requestEmailChange` so the
  backend-neutral legacy contract and the Supabase capability cannot diverge.
  `currentPassword` is accepted and ignored in Supabase mode. The Firebase and
  Mock implementations of that contract are unchanged.

Verification completed:

- Focused email-change suite: 15/15 PASS.
- Full Flutter suite: 218/218 PASS.
- Focused analyzer for changed Dart files: no issues.
- `flutter analyze lib test`: zero errors, zero warnings; 112 existing
  informational deprecations in unrelated files.
- No database migration, RLS change, Edge Function, hosted setting change, or
  deployment was made.

Hosted/device acceptance still required:

- Connected project `rbvcnvqpdqrhywcgxkne` (`broker-wallet`) is healthy, but
  the available project tools do not expose the hosted Secure Email Change
  toggle. Local `supabase/config.toml` has `double_confirm_changes = true`,
  which does not prove the hosted value.
- In Supabase Dashboard, confirm Secure Email Change and the redirect allowlist
  for `brokerwallet://auth/callback` without changing them during this check.
- On a real device, request a change between two controlled inboxes, approve
  the exact mailbox sequence required by the hosted toggle, verify callback
  routing and same-session uid, then verify Profile/Edit Profile and a cold
  restart show the new confirmed email.
- Also exercise resend/cooldown, duplicate submit, invalid/same/used email,
  logout while pending, and account-switch isolation.

PROJECT ORDER

1. EMAIL CHANGE — VERIFIED_RUNTIME (complete).
2. PASSWORD — VERIFIED_RUNTIME (complete, 2026-09-13).
3. DELETE ACCOUNT — production happy path and wrong-password path
   VERIFIED_RUNTIME + VERIFIED_HOSTED + VERIFIED_REAL_DEVICE (2026-09-14). The
   dedicated lost-response / cut-network scenario is NOT RUN / DEFERRED. See
   "DELETE ACCOUNT — PRODUCTION ACCEPTANCE" at the end of this file.
4. GOOGLE / APPLE — deferred until later.

Phone auth for sign-in/sign-up is not in this order: it is legacy-Firebase only
and its UI presence is a product-owner decision, not an open checkpoint.

Facebook authentication remains removed.

ACCOUNT / PROFILE CHECKPOINT — REAL-DEVICE ACCEPTANCE (2026-09-12)

The product owner completed real-device acceptance. Statuses below are their
observations, not inferences from tests.

EMAIL CHANGE — VERIFIED_RUNTIME

Verified by the product owner on a real device:

- Email Change works end to end.
- The Secure Email Change two-mailbox flow works.
- The confirmed email updates correctly.
- Email Change remains reachable from Edit Profile.

Secure Email Change remains ENABLED in hosted Supabase. The deep-link
predicate, the callback classification and the resend address correction are
therefore runtime verified, not just code proven.

EDIT PROFILE UI POLISH — VERIFIED_RUNTIME / ACCEPTED

Accepted by the product owner on a real device:

- The polished Edit Profile layout is accepted.
- English layout accepted.
- Arabic / RTL layout accepted.
- Name save still works.
- Profile image save still works.
- Email Change entry still works.
- Add Phone entry still works.
- No UI regression reported.

The change was presentation only: no business logic, repository boundary, save
behavior, image-upload path, phone flow or email-change state was modified.

- Compact identity header: 84px avatar with its camera affordance plus a
  "Change photo" action, name, and the confirmed email as secondary LTR text
  that ellipsizes instead of wrapping. The separate hint chip was removed.
- Quiet uppercase section labels group the form: Personal information, Email,
  Phone.
- Email and phone rows share one card treatment, padding and radius, so neither
  reads as more important than the other. The confirmed email stays primary and
  ellipsizes to one line; the change action is a compact secondary text button.
- A pending email change shows only the compact one-line indicator that opens
  the pending sheet. The old large status card was not reintroduced.
- Page padding is a consistent 20px; the 80px gap above Save is gone; the Save
  button radius matches the cards, and a one-line note states that Save covers
  name and photo while email and phone are confirmed separately.

PHONE LOGIN / SIGNUP UI RESTORATION — VERIFIED_UI

Verified by the product owner on a real device:

- The Login Phone tab is visible and selectable.
- The Sign-up Phone tab is visible and selectable.

This status covers the UI restoration only. It is explicitly NOT a statement
about phone authentication working.

The Phone tab had been hidden in commit `0148dbd` behind `phoneSignInAvailable`
/ `phoneSignUpAvailable` without product-owner authorization. The gates were
removed, the tabs render unconditionally again, and the Phone method is
selectable on both screens. No UI was redesigned.

PHONE LOGIN / SIGNUP AUTH FUNCTIONALITY —
NOT IMPLEMENTED / NOT RUNTIME PASS IN SUPABASE MODE

- Phone sign-in and phone registration are implemented on the legacy Firebase
  backend only. With Supabase as the auth authority — the default — neither can
  complete, and neither has been runtime verified.
- Attempting either shows a localized EN/AR message saying the method is not
  available yet and to use email. That message was previously a hard-coded
  English string and is now a localization key.
- Email is the initially selected method wherever phone auth cannot complete,
  so neither screen opens on a method that cannot finish. The Phone tab is
  still present and selectable. Flip `SignInViewModel.initialLoginMethod` /
  `SignUpViewModel.initialSignupMethod` to restore the historical Phone-first
  default.
- No phone authentication architecture was built, no second identity was
  created, and phone login is not wired to the signed-in phone-change flow.
- Restoring this UI does not re-open the phone auth checkpoint.

PHONE ADD / VERIFY IMPLEMENTATION — PRESERVED

The signed-in account Add Phone / phone-verification flow and its hosted
database hardening are unchanged and remain as recorded in the phone checkpoint
above: implementation CODE_PROVEN, hosted DB security PASS, and final real UAE
SMS acceptance still externally deferred pending a business/trade licence, a
production SMS provider and UAE sender registration.

Local verification at acceptance time: full suite 241/241 PASS;
`flutter analyze lib test` zero errors, zero warnings, 112 pre-existing
informational findings in unrelated files.

Open backlog, reported and deliberately not implemented:

- A confirmed phone number has no "change" entry point in Edit Profile.
- The restored phone login form keeps a pre-existing hard-coded 280px spacer.
- `tapToChangePhoto` is now an unused localization key.
- Both `.arb` files contain roughly 450 pre-existing duplicate keys; a
  JSON-based tool will silently drop the earlier copies.

NOW — nothing is pending on this checkpoint. Review the staged working tree and
commit the Account/Profile work when you are ready; the generated plugin
registrant files under `linux/flutter/`, `macos/Flutter/` and `windows/flutter/`
carry no content change and must stay out of that commit.

NEXT — start the PASSWORD checkpoint.

PASSWORD CHECKPOINT — SUPERSEDED BY THE REAL-DEVICE FAILURE RECORDED
AT THE END OF THIS FILE

Not VERIFIED_RUNTIME. Nothing below was observed on a real device or against
hosted Supabase; every statement is proven from source, the pinned SDK, or the
local test suite only.

SDK gate: Flutter 3.47.2 stable (Dart 3.13.2), matching the current stable
baseline. No upgrade was performed or needed. Package language version stays
3.5 (`environment.sdk: ^3.5.3`).

Pinned SDK capability, read from `gotrue-2.27.2` source rather than assumed:

- `resetPasswordForEmail(email, {redirectTo})` exists and, under the PKCE flow
  the app uses, stores a code verifier tagged `passwordRecovery`.
- `exchangeCodeForSession` reads that tag back and emits
  `AuthChangeEvent.passwordRecovery`; the implicit flow emits the same event
  for `type=recovery`. This event is the only moment a recovery session is
  distinguishable from an ordinary sign-in.
- `updateUser(UserAttributes(password:))` requires a session and emits
  `userUpdated`.
- `UserAttributes.currentPassword` exists and serialises to `current_password`,
  which GoTrue only honours when
  `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD` is enabled.
- `UserAttributes.nonce` and `GoTrueClient.reauthenticate()` exist, so
  Supabase's "Secure password change" nonce ceremony is *possible* in this SDK.
  It is deliberately NOT implemented — see the hosted settings section.
- `AuthWeakPasswordException` exists and is mapped.

Implemented:

- One canonical policy, `PasswordPolicy` (`lib/src/common/utils/password_policy.dart`):
  minimum 8 characters plus a lower-case letter, an upper-case letter and a
  digit — byte-for-byte the rules Sign-up already enforced, so no existing
  account can be locked out of Change Password by a rule its password never had
  to meet. A 72-byte maximum is added because GoTrue hashes with bcrypt, which
  silently ignores anything beyond that. Sign-up, Change Password and Reset
  Password all validate through this one class.
- `PasswordCapability` on `AuthRepository`, implemented by
  `SupabaseAuthRepository` only, alongside the existing
  `PhoneVerificationCapability` / `EmailChangeCapability` pattern.
  `sendPasswordResetEmail` from the legacy backend-neutral contract now
  delegates to it so the two cannot diverge.
- Change Password: a focused sheet opened from a new Password row in Edit
  Profile. `updateUser(password:)` on the live session; the owning account is
  captured before the call and re-checked after it, against the session rather
  than any caller-supplied id.
- Forgot Password: the Login screen's pre-existing "Forgot password?" action,
  which previously showed a "coming soon" toast, now opens a reset-request
  sheet. No Login layout changed.
- Reset Password: a guarded `/reset-password` route, reachable only while
  `PasswordRecoveryViewModel.holdsRoute` is true. The form itself is only built
  in the `active` phase, so it cannot render without a real recovery.
- Recovery deep link: no new AppLinks listener. A recovery callback is
  session-bearing, so the existing `detectSessionInUriPredicate` hands it to
  Supabase; `SupabaseAuthRepository` republishes
  `AuthChangeEvent.passwordRecovery` from its single existing
  `onAuthStateChange` subscription as a `PasswordRecoverySession`.
  `AuthCallbackCoordinator` keeps owning only the callbacks Supabase declined,
  and now also reports whether a callback arrived at the dedicated
  password-recovery address.
- Password recovery has its own callback address,
  `brokerwallet://auth/reset-password`
  (`SupabaseConfig.passwordRecoveryCallbackUri`). Everything else keeps
  `brokerwallet://auth/callback`.

Collision safety is structural, not heuristic:

- A recovery callback carries a session, so the coordinator never sees it and
  it can never be confused with the Email Change callbacks, which are exactly
  the ones Supabase declined.
- Signup verification and the final Email Change confirmation are
  session-bearing too, but GoTrue emits `signedIn`/`userUpdated` for them,
  never `passwordRecovery`.
- An Email Change error callback carries `type=email_change` and is left alone.

Expired recovery links — HARDENED, no heuristic. GoTrue does not guarantee a
`type` parameter on an error redirect, so an expired recovery link and an
expired Email Change link carry identical parameters. Sending recovery to its
own address makes them distinguishable by the link itself:
`isPasswordRecoveryCallback(uri)` compares scheme, host and path exactly
(case-insensitive scheme/host, trailing slash tolerated) and consults no
parameter, no provider-supplied `type` and no clock. `PasswordRecoveryViewModel`
claims an error callback only when that address matches, and
`EmailChangeViewModel` now ignores callbacks at that address, so neither flow
can capture the other's dead link.

The earlier one-hour `PasswordResetRequestMarker` heuristic and the
`AuthCallbackEvent.flowType` hint were both removed outright rather than left
as fallbacks: a weaker signal kept alongside a deterministic one can only
re-introduce the misclassification. `lib/src/services/password_reset_request_marker.dart`
is deleted, and nothing in the password flow stores local state or reads a
clock.

Proven from the pinned SDK, not assumed:

- `SupabaseAuth._isAuthCallbackDeeplink` uses the supplied
  `detectSessionInUriPredicate` and nothing else; neither it nor the SDK
  default inspects the URI's path or host — only query and fragment
  parameters.
- `GoTrueClient.getSessionFromUrl` likewise reads only parameters, never the
  path.
- The PKCE code verifier that tags the exchange as `passwordRecovery` is keyed
  by storage key, not by redirect URL, so changing `redirectTo` does not affect
  `AuthChangeEvent.passwordRecovery` emission.

Therefore the new path is exchanged exactly as the old one was.

Platform compatibility — no platform file changed:

- Android: the existing filter is
  `<data android:scheme="brokerwallet" android:host="auth" />` with **no**
  `android:path`/`pathPrefix`/`pathPattern`. Android ignores the path when no
  path attribute is present, so `/reset-password` already matches.
- iOS: `CFBundleURLSchemes` registers the scheme `brokerwallet`; the path plays
  no part in scheme matching and the full URL is delivered to the app.
- `flutter_deeplinking_enabled` is `false` on Android and
  `FlutterDeepLinkingEnabled` is `<false/>` on iOS, so platform deep links are
  never fed into Flutter navigation. The deep-link path `/reset-password` and
  the GoRouter route `/reset-password` are separate namespaces and cannot
  collide.

Hosted Supabase settings — REPORTED, NOT CHANGED. Nothing hosted was read,
written or deployed in this checkpoint. `supabase/config.toml` is the *local*
file and does not prove the hosted values; it currently reads
`minimum_password_length = 6`, `password_requirements = ""`,
`secure_password_change = false`. The owner must verify and decide in the
Dashboard:

- Minimum password length → raise to 8 to match the client policy. Safe: the
  client already refuses shorter passwords, and this does not affect sign-in
  for existing accounts.
- Leaked password protection → enable if the plan allows. Already compatible:
  GoTrue answers with `weak_password`, which maps to a localized message.
- **Redirect allowlist → add `brokerwallet://auth/reset-password` as a second
  exact entry, alongside the existing `brokerwallet://auth/callback`.** This is
  mandatory and blocking: GoTrue validates `redirect_to` against Site URL plus
  Additional Redirect URLs and silently falls back to the Site URL when the
  value is not listed, so without this entry every reset email would point away
  from the app. Add the exact URL; do not introduce a wildcard.
- Require current password → currently assumed OFF, and the app is built for
  OFF. The current-password field is shown and sent **only** when
  `--dart-define=REQUIRE_CURRENT_PASSWORD=true` matches the hosted setting.
  Enabling it hosted without that define would leave the server expecting a
  value the app does not send. Enable hosted first, then rebuild with the
  define, then device-test; also re-test the recovery flow, since a recovery
  session has no current password to supply.
- Secure password change (reauthentication/nonce) → keep OFF. The pinned SDK
  can do it, but the app does not implement the OTP-entry ceremony. If it is
  ever enabled, the server's `reauthentication_needed` is already mapped to a
  localized message rather than a crash, but the flow would not complete. Take
  it as its own checkpoint.

No database migration, RLS change, Edge Function, email template, hosted
setting or deployment was touched. None is required for password auth.

Protected UI audit:

- `login_view.dart`, `signup_view.dart`, `profile_view.dart`: zero changes.
- `edit_profile_view.dart`: 97 insertions, 0 deletions — one Password section
  between Phone and Save, reusing `_fieldCardDecoration`, `_FieldLeadingIcon`
  and `_SectionLabel` so it is visually identical in treatment to the existing
  "Add phone number" row. Section spacing follows the owner's existing rhythm
  (20 between sections, 28 before Save). Nothing else in that file changed.
- `login_viewmodel.dart` changed behaviour only: the existing "Forgot
  password?" action opens a sheet instead of showing a toast.
- `signup_viewmodel.dart` now validates through `PasswordPolicy`. Its error
  strings are its own pre-existing English strings, unchanged, so Sign-up
  presentation is untouched.

Local verification:

- Full Flutter suite: 320/320 PASS (was 241/241). 79 new tests across
  `test/auth/password_policy_test.dart`, `password_change_test.dart`,
  `password_recovery_test.dart` and `password_ui_test.dart`.
- `flutter analyze lib test`: 0 errors, 0 warnings, 112 pre-existing
  informational findings in unrelated files — unchanged from baseline.
- `git diff --check`: clean.
- Generated plugin registrants under `linux/flutter/`, `macos/Flutter/` and
  `windows/flutter/` show as modified with no content change. Reported, not
  touched, and must stay out of any commit.

Known trap for widget tests, learned here: `pumpEventQueue()` hangs inside
`testWidgets` because the test body runs in a fake-async zone. Drive streams
with `tester.pump()` after `pumpWidget`, not with `pumpEventQueue()`.

Unresolved risks, none of them blocking code completion:

- Recovery emails sent before this change point at
  `brokerwallet://auth/callback` and will no longer be claimed as recovery if
  they expire. Password has never shipped or been runtime-tested, so no such
  link exists outside development.
- Cross-device recovery. Under PKCE the code verifier lives in this device's
  Supabase storage, so a reset requested on the phone and opened on a laptop
  (or after the app's storage is cleared) cannot be exchanged. Supabase
  republishes that as an auth-stream error, which the app correctly refuses to
  treat as a sign-out, but the user sees nothing happen. Same-device is the
  supported path.
- Wrong-current-password mapping is unexercised. `invalid_credentials` is the
  semantically correct GoTrue code for a credential mismatch, but it cannot be
  confirmed until the hosted setting is enabled. It is inert in the shipped
  configuration, which never sends a current password.
- Whether a password change invalidates the account's other sessions is a
  server-side behaviour that the pinned client SDK does not expose. Not
  asserted either way; confirm in the Dashboard/docs if it matters.
- Mail-provider link prefetch remains the known hazard it was for Email Change.

Backlog observed and deliberately not implemented:

- Sign-up's password validation messages are still hard-coded English while
  Change and Reset are localized. Fixing that changes Sign-up's user-visible
  behaviour in Arabic and needs the owner's authorization.
- The Profile screen's "Security" tile is still an info placeholder. It was
  left exactly as the owner arranged it.

NOW — in the Supabase Dashboard, add `brokerwallet://auth/reset-password` to
Authentication → URL Configuration → Redirect URLs as an exact entry, keeping
`brokerwallet://auth/callback`. That one addition is blocking: without it reset
emails will not return to the app. While there, read and report the three
password settings (minimum password length, leaked password protection, require
current password / secure password change) without changing them. Then run the
real-device matrix below, starting at step 10 (Login → Forgot password?).

NEXT — once the device matrix passes, record PASSWORD as VERIFIED_RUNTIME and
start the DELETE ACCOUNT checkpoint.

PASSWORD REAL-DEVICE TEST MATRIX

Change Password (signed in, Edit Profile → Password):

1. Valid change succeeds and shows the confirmation toast.
2. A password failing the checklist is refused with no network call.
3. Mismatched confirmation is refused.
4. Double-tapping Update produces exactly one change.
5. Sign out, sign in with the new password: PASS.
6. The old password is rejected.
7. Cold restart: still signed in, account uid unchanged.
8. EN and AR, light and dark.
9. Current-password field: only if the hosted setting is enabled and the build
   carries `--dart-define=REQUIRE_CURRENT_PASSWORD=true`; then also test a
   wrong current password.

Forgot / Reset:

10. Login → Forgot password? → a registered address: the generic confirmation
    appears.
11. An unregistered address: the identical confirmation appears.
12. The reset email arrives.
13. Tapping the link opens the app (app already running, and app cold-started).
14. The Reset Password screen appears — not Home, not signup verification, not
    the Email Change sheet. Confirm the link in the email points at
    `brokerwallet://auth/reset-password`.
15. A valid new password completes and shows the confirmation.
16. Continue leaves the screen and lands on Home.
17. Sign out, sign in with the new password: PASS; old password rejected.
18. Tapping the same link again shows the expired-link screen, not a second
    reset.
19. An expired link (wait out the link lifetime) shows the expired-link screen
    with "Send a new link" and "Back to sign in", and no crash.
20. "Send a new link" delivers a working email.
21. Repeat 13–16 in Arabic/RTL and in dark mode.
22. Account uid is unchanged throughout.

Regression checks during the same session:

23. Email Change still works end to end and its callback is not captured by the
    recovery screen.
24. Signup email verification still completes normally.
25. The Login and Sign-up Phone tabs are still visible and selectable.
26. Edit Profile name save, photo save, Email Change entry and Add Phone entry
    are unchanged.

PASSWORD REAL-DEVICE ACCEPTANCE (2026-09-12): FAIL — SECURITY/ROUTING BLOCKER

This falsifies the CODE_PROVEN / READY-FOR-DEVICE status recorded above. Real
device evidence overrides the local suite, which passed while both defects were
present.

Hosted setup confirmed by the product owner:

- `brokerwallet://auth/reset-password` added to Supabase Redirect URLs: PASS.
- Minimum password length: 8. Password requirements: none selected.
- Secure password change: OFF. Require current password: OFF.

Observed PASS:

- Change Password weak-password validation, mismatch validation, and the actual
  password change.
- Reset email received; the reset link opens the app.

Observed FAIL 1 — a recovery session was treated as an ordinary session:

The app could reach Home before the user entered or submitted a new password.
A Supabase password-recovery session is a fully valid session, so every routing
rule accepted it as a normal login.

Observed FAIL 2 — during recovery the device threw
`RealtimeSubscribeException` for `public.notifications` filtered on
`recipient_id` ("invalid column for filter recipient_id"), repeatedly pausing
the debugger before the reset screen became usable.

Not yet performed: old-password rejection and new-password login verification.

ROOT CAUSE 1 — publication order, proven from source

`SupabaseAuthRepository._handleAuthState` published the session identity first
and only then announced the recovery, and `_startIdentityPipeline` published the
restored identity before subscribing to auth events at all. Identity reaches
`AuthViewModel` through `_replayLatestThen`, so it arrived a microtask *before*
the recovery announcement reached `PasswordRecoveryViewModel`. In that window
`AuthViewModel.status` was `authenticated` while nothing yet said the session
was a recovery, GoRouter refreshed on that notification, and
`resolveAuthRedirect` sent the user to Home. Home then built, which is what
started the notification feed.

A second, independent path existed in `resolveAuthRedirect` itself: the
bootstrap gate (`status == unknown`) was evaluated *before* the recovery gate
and returned `/`, and `/` resolves to `/home` for an authenticated session.

Both are ordering defects, not timing defects, and neither is fixed by waiting.

ROOT CAUSE 2 — cold start after process death

`GoTrueClient.recoverSession` restores a session and emits
`AuthChangeEvent.initialSession`; only the live exchange emits
`AuthChangeEvent.passwordRecovery`. `gotrue` 2.27.2 uses a `ReplaySubject` for
`onAuthStateChange`, so a late subscriber within one process still receives the
recovery event — but nothing survives process death, and `Session` carries no
recovery marker. A recovery session restored on a fresh launch was therefore
indistinguishable from a normal one.

FIX — recovery quarantine

- `PasswordCapability` gained `isPasswordRecoveryActive` (synchronous) and
  `endPasswordRecovery()`. The repository resolves recovery ownership *before*
  publishing the identity for that session, and binds it to the account uid.
- `AuthViewModel` re-reads that flag in the same turn it applies the session
  identity, so `status` and `isPasswordRecoveryActive` are one atomic snapshot
  published by one `notifyListeners()`. The cross-stream race is structurally
  impossible, not merely unlikely. No timer and no `Future.delayed` is involved.
- `resolveAuthRedirect` evaluates the recovery gate FIRST, ahead of the
  bootstrap gate. While a recovery is unresolved, every path resolves to
  `/reset-password`.
- The router takes the live-session answer from `AuthViewModel`, and keeps
  `PasswordRecoveryViewModel.holdsRoute` only for the session-less dead-link
  state, where there is nothing that could be mistaken for a login.
- `PasswordRecoveryStateStore` persists one value — the recovery owner's uid —
  so a session restored after process death is still recognised. It stores no
  token, no password, no address and no timestamp, is never used to classify a
  callback, and is ignored whenever the live session's uid does not match.
  Stale-state analysis is in `docs/DECISIONS.md`; the worst reachable state is
  one extra cancel, never a lockout and never silent app access.
- Successful reset: the password is updated, the recovery session is signed out,
  the marker is cleared, and GoRouter resolves to `/sign-in` with a localized
  "Password updated. Sign in with your new password." The user proves the new
  password by using it. Home is never reached with a recovery session.
- Cancel: the same sign-out and clear, from a "Back to sign in" text button now
  present on the reset form. It mirrors the button the dead-link state already
  had; no other UI changed.

ROOT CAUSE — Realtime exception

Two distinct things, deliberately kept apart.

1. Why it happened *during recovery*: `NotificationViewModel` is created lazily
   by `NotificationIcon`, which lives on Home. It was reached only because the
   recovery session routed to Home. With the quarantine in place Home is not
   built during recovery, and `main.dart` additionally passes a null uid to
   `attachUser` while `isPasswordRecoveryActive`, so the channel is not opened
   even if some other surface were to read that provider.

2. Why it crashed the app: both `.listen(...)` calls in `NotificationViewModel`
   had no `onError`. `SupabaseNotificationRepository.watchLatestNotifications`
   builds a Realtime stream, and a refused channel delivers
   `RealtimeSubscribeException` onto it, which without a handler becomes an
   unhandled async error — the repeated debugger pauses. Both subscriptions now
   carry `onError`, which records `isFeedUnavailable`, settles the loading
   state, touches no authentication state, and logs nothing from the payload.

The hosted database is NOT implicated and was not changed. The owner verified
read-only that `public.notifications.recipient_id` exists as `uuid`, that the
table is in the `supabase_realtime` publication with `recipient_id` in its
column list, and that an RLS SELECT policy `recipient_id = auth.uid()` exists.
No migration was created and no schema, publication or policy was altered.

STILL UNPROVEN: whether the same Realtime filter is refused in an *ordinary*
authenticated session. It could not be reproduced here, because the only
reproduction on record happened inside the recovery path that is now closed.
The containment above means a refusal can no longer crash the app, but if the
feed is still unavailable after the retest, that is a separate Notifications
checkpoint and not part of Password. Capture it with the notifications screen
open on a normal login and report whether `isFeedUnavailable` is true.

Local verification after the fix:

- Full Flutter suite: 347/347 PASS (was 328).
- New suite `test/auth/password_recovery_quarantine_test.dart`: 12/12, including
  a test that samples the router destination on *every* notification during a
  recovery and fails if any of them resolves to Home.
- `flutter analyze lib test`: 0 errors, 0 warnings, 112 pre-existing
  informational findings.
- `git diff --check`: clean. No platform file, no hosted change, no migration.

PASSWORD STATUS: CODE_PROVEN AFTER RECOVERY-QUARANTINE FIX —
AWAITING REAL-DEVICE RETEST. NOT VERIFIED_RUNTIME.

RETEST MATRIX — PASSWORD RECOVERY QUARANTINE

Run these before anything else; they are the failures being retested.

R1. Forgot password from Login, open the emailed link with the app running.
    The Reset Password screen appears. Home must never appear, not even for a
    frame, and the bottom navigation must not be reachable.
R2. Same, with the app backgrounded rather than foreground.
R3. Same, from a cold start (force-stop the app first).
R4. While the reset screen is showing, background the app, force-stop it, and
    reopen from the launcher. The app must return to the reset screen, not to
    Home.
R5. During recovery, confirm no `RealtimeSubscribeException` appears and the
    debugger does not pause.
R6. Set a valid new password. Expect: the success message, then the Sign In
    screen. Home must not appear.
R7. Sign in with the new password: PASS. Sign in with the old password:
    rejected.
R8. Repeat R1 and tap "Back to sign in" instead. Expect Sign In, and confirm
    the app is genuinely signed out (reopening lands on Welcome/Sign In, not
    Home).
R9. After R8, sign in normally and confirm the app behaves as an ordinary
    session: Home, Profile, notifications all reachable, no reset screen.
R10. Expired link: request a reset, wait out the link lifetime, then tap it.
     Expect the localized expired-link screen with "Send a new link" and "Back
     to sign in", and no crash.
R11. EN and AR, light and dark, for R1 and R6.
R12. Account uid unchanged throughout.

Regression in the same session:

R13. Email Change still completes end to end and its callback is not captured
     by the reset screen.
R14. Signup email verification still completes normally.
R15. Login and Sign-up Phone tabs still visible and selectable.
R16. Edit Profile name save, photo save, Email Change entry, Add Phone entry
     and the Password row all behave as before.
R17. On a normal login, open Notifications and report whether the list loads or
     shows empty, so the separate Realtime question can be settled.

PASSWORD — VERIFIED_RUNTIME (2026-09-13)

The product owner completed the full real-device retest after the
recovery-session quarantine fix. This supersedes the CODE_PROVEN / AWAITING
RETEST status above. Statuses below are the owner's device observations, not
inferences from tests.

Recovery quarantine:

- App already open: PASS.
- App backgrounded: PASS.
- Cold start from the email link: PASS.
- Force-stop while Reset Password is open, then reopen from the launcher: PASS.
- Home appeared before reset completion: NO.
- `RealtimeSubscribeException` during recovery: NO.

Reset completion:

- Password reset succeeds: PASS.
- After reset the app lands on Sign In, not Home: PASS.
- Old password rejected: PASS.
- New password accepted: PASS.
- Normal cold restart after signing in with the new password: PASS.

Cancel and invalid links:

- Cancel recovery lands on Sign In: PASS.
- Reused recovery link handled safely: PASS.
- Raw `AuthException` or crash: NO.

Normal session and Notifications:

- `RealtimeSubscribeException` after a normal login: NO.
- Notifications usable: PASS.

No other runtime issue was reported.

VERIFIED_RUNTIME scope — all of the following are now runtime verified:

- Authenticated Change Password: weak-password validation, mismatch
  validation, the actual password change, old-password rejection and
  new-password authentication.
- Forgot Password request and recovery email delivery.
- The dedicated `brokerwallet://auth/reset-password` callback.
- Recovery-session quarantine: no application access during recovery, across
  warm, backgrounded and cold starts, including recovery that survives process
  death through `PasswordRecoveryStateStore`.
- Successful reset followed by sign-out to Sign In.
- Cancel recovery.
- Reused and invalid recovery-link safety, with no raw `AuthException`.
- No `RealtimeSubscribeException` during recovery.
- Normal authenticated Notifications regression.

Hosted Supabase password settings, as observed by the owner and unchanged:

- Minimum password length: 8.
- Password requirements: none selected.
- Secure password change: OFF.
- Require current password: OFF.
- Leaked-password protection: unavailable on the current Free plan, and
  therefore disabled.
- Redirect URLs include `brokerwallet://auth/reset-password` as an exact entry
  alongside `brokerwallet://auth/callback`.

The client password policy (8 characters with lower-case, upper-case and digit)
is stricter than the hosted "none selected" requirement, so the client remains
the effective enforcement of character classes. The shipped configuration never
collects or sends a current password, consistent with Require current password
being OFF. No hosted setting was changed by any agent.

Realtime `recipient_id` exception — classification:

The earlier `RealtimeSubscribeException` ("invalid column for filter
recipient_id") on `public.notifications` did not reproduce during corrected
password recovery, after a normal login, or while using Notifications. It is
recorded as a runtime failure caused or exposed by the incorrect
recovery-to-Home path, and not reproducible since the quarantine correction.
No backend schema defect is claimed: the owner had already verified read-only
that `recipient_id` exists as `uuid`, is in the `supabase_realtime`
publication column list, and is covered by the `recipient_id = auth.uid()`
SELECT policy. The "STILL UNPROVEN" note in the failure record above is
resolved by this result. No Notifications checkpoint is opened for it. The
`onError` containment added to `NotificationViewModel` remains in place as
defence in depth.

Leftover observations carried forward, not blocking and not scheduled:

- Cross-device recovery cannot complete under PKCE, because the code verifier
  lives on the device that requested the reset. Same-device recovery is the
  supported and verified path.
- The wrong-current-password mapping (`invalid_credentials`) remains
  unexercised and inert while Require current password is OFF.
- Sign-up password validation messages remain hard-coded English, a
  pre-existing gap that needs product-owner authorization to change.
- The Profile screen's "Security" tile remains an information placeholder.

NOW — review and commit the Password checkpoint working tree when ready. Keep
the generated plugin registrant files under `linux/flutter/`, `macos/Flutter/`
and `windows/flutter/` out of that commit; they carry no content change.

NEXT — start the DELETE ACCOUNT checkpoint.

DELETE ACCOUNT CHECKPOINT — CODE_PROVEN (2026-09-13)

SUPERSEDED IN PART by "DELETE ACCOUNT — CROSS-SYSTEM COMPLETION REVIEW" at the
end of this file. The failure model item 3 (`already_deleted`), the residual
signed-PUT risk, "MIGRATION REQUIRED: NO", product decisions 1, 2, 4, 5 and 6,
and the NOW/NEXT below no longer apply.

Branch `delete-account-production`, baseline `50cf0a9`, clean tree at start.
Not VERIFIED_HOSTED and not VERIFIED_RUNTIME. Nothing was deployed, applied,
committed or run against hosted Supabase or Cloudflare. No real account was
deleted.

Starting state found:

- The Profile screen already had the owner's Delete Account row (destructive
  style, `deleteAccount` / `deleteAccountHint`), which opened a "will be
  available before release" dialog.
- `SupabaseAuthRepository.deleteAccount()` and
  `SupabaseUserRepository.deleteUser()` throw "server-owned" failures. They are
  left unchanged and are not the deletion path.
- Firebase `deleteAccount` in `firebase_auth_repository.dart` and
  `auth_service.dart` is LEGACY and untouched.
- No `supabase/functions/` directory and no delete endpoint existed in the live
  repository. The older `delete-account` Edge Function snapshot is not present
  and was not reintroduced.
- `media_objects.object_key` is always `profiles/<uid>/<media id>.<ext>`,
  enforced by the Worker. Replaced-avatar and abandoned-pending cleanup already
  existed; account-level cleanup did not.

Repository schema matches the supplied hosted cascade facts:
`profiles.id -> auth.users ON DELETE CASCADE`; every owner table cascades from
`profiles`; `audit_logs.actor_id`, `audit_logs.target_user_id` and
`notifications.sender_user_id` are `ON DELETE SET NULL`. No cascade migration
was created.

Implemented:

- Trusted server: `POST /account/delete` in the existing `r2-profile-upload`
  Worker (`cloudflare/workers/r2-profile-upload/account_deletion.js`, routed
  from `worker.js` and held open with `ctx.waitUntil`). The Worker already owns
  the `MEDIA_BUCKET` binding and `SUPABASE_SECRET_KEY`, so no R2 credential was
  given to Supabase and no credential of any kind to Flutter. No new Worker
  secret or binding is needed.
- Order: verify bearer token with `GET /auth/v1/user` -> refuse a body user id
  that differs from the verified one -> refuse a token whose `amr` contains
  `recovery` -> re-verify the password server-side with a password grant for
  the verified account's own email, check the returned user id, revoke that
  verification session -> inventory `media_objects` by the verified
  `owner_id` plus an R2 listing of `profiles/<uid>/` -> refuse (and delete
  nothing) if any row is in another bucket or outside that prefix -> delete the
  union, re-list and prove the prefix empty -> mark the rows `deleted` ->
  `DELETE /auth/v1/admin/users/<uid>` with `should_soft_delete: false` (404
  counts as done) -> sweep the prefix once more.
- Errors are fixed codes only: `session_expired`, `already_deleted`,
  `account_mismatch`, `recovery_session`, `invalid_request`,
  `reauthentication_failed`, `reauthentication_unsupported`, `rate_limited`,
  `media_cleanup_failed`, `server_delete_failed`, `service_unavailable`,
  `unknown`. Logs carry the code only — no token, password, email, uid, object
  key or error object.
- Flutter: `WorkerAccountDeletionGateway` sends the live session token and the
  password, never a user id. `DeleteAccountViewModel` captures the account when
  the flow opens and refuses on any change, recovery session, missing
  acknowledgement or empty password before any request, and ignores repeated
  submits. `AuthViewModel.completeAccountDeletion(uid)` ends local state only for
  that uid, never signs out a different account, and cannot be left
  authenticated by a sign-out that fails to reach the server.
  `DeletedAccountLocalDataCleaner` clears the inventory in its class comment.
- UI: the existing Delete Account row now opens a two-step sheet — what is
  deleted, "cannot be undone", subscription-not-refunded note -> password,
  explicit acknowledgement checkbox, "Delete account permanently". While
  deleting, the sheet cannot be dismissed (PopScope, drag disabled) and every
  control is disabled. On success GoRouter's existing redirect takes the Profile
  tab to `/welcome` and a localized toast confirms. 27 new EN/AR keys.

Cross-system failure model (Postgres/Auth and R2 are not one transaction):

1. R2 cleanup fails -> `media_cleanup_failed`; auth user and metadata untouched;
   retry is safe.
2. R2 succeeds, auth delete fails -> `server_delete_failed`; account still
   exists with no media and rows marked `deleted`; retry is safe.
3. Auth delete succeeds, response lost -> the app shows the network message; a
   retry with the same still-valid token gets `already_deleted` (Supabase Auth
   `user_not_found`), sweeps the prefix and completes locally.
4. Retry after partial deletion -> every step is idempotent (R2 deletes of
   missing keys succeed; the admin delete treats 404 as done).
5. Client disconnects -> `ctx.waitUntil` keeps the request running to the end.
6. Two concurrent executions -> both converge; the second's admin delete gets
   404.

MIGRATION REQUIRED: NO. None of the six failure points needs durable state: the
metadata stays until the auth delete succeeds, and the prefix listing finds
objects without metadata. Residual risk, not closed without new infrastructure:
a signed PUT URL issued by `/authorize` in the seconds before the auth delete is
valid for 300 s and could land an object after the final sweep. It needs a
concurrent avatar upload from another device during deletion, is limited to one
image under a deleted uid's prefix, and is removed by any later retry. Closing it
completely needs a scheduled prefix sweep for deleted uids — an ops decision,
not a migration.

Local verification:

- Worker: `node --test` in `cloudflare/workers/r2-profile-upload` — 24/24.
  Mutation-checked: removing the uid-mismatch check, removing the recovery
  check, or deleting auth before media each fails the suite.
- Flutter: `test/account/delete_account_test.dart` 26/26 and
  `test/account/delete_account_ui_test.dart` 9/9.
- Full Flutter suite: 382/382 PASS (was 347).
- `flutter analyze lib test`: 0 errors, 0 warnings, 112 pre-existing
  informational findings (unchanged).
- `git diff --check`: clean. Generated plugin registrants drift with no content
  change, excluded.
- Protected UI: only `profile_view.dart` changed (Delete Account `onTap`, and
  the now-unused dialog removed). Edit Profile, Login, Signup, Home, Email
  Change, Password and Phone files have zero diff.

Hosted assumptions that are AWAITING HOSTED VALIDATION (source-reasoned, not
observed):

- The API gateway accepts `SUPABASE_SECRET_KEY` for
  `DELETE /auth/v1/admin/users/{id}` when it is sent as both `apikey` and
  `Authorization: Bearer`, as `supabase-js` does. The Worker's existing
  PostgREST calls prove the key works for `/rest/v1` only.
- `GET /auth/v1/user` with a still-valid token for a deleted user returns
  `error_code: user_not_found` rather than `session_not_found`. If it does not,
  failure point 3 shows the session-ended message instead of completing; nothing
  unsafe happens.
- A PKCE recovery session carries `amr` method `recovery`. The app-side
  quarantine and the password re-check are the primary guards; this server check
  is defence in depth.
- The password grant from Cloudflare egress IPs is subject to GoTrue's per-IP
  sign-in rate limit, which is shared across users of the Worker.
- The cascade itself: run
  `supabase/validation/account_deletion_cascade_validation.sql` (rollback only,
  no install, no COMMIT). It checks every foreign key onto `auth.users` /
  `public.profiles`, deletes a synthetic account as `supabase_auth_admin` when
  permitted, asserts every owned row is gone, that another account is untouched,
  and that notification sender / audit references become NULL, and reports audit
  and webhook row counts without contents. It could not be run here: no Docker
  and no `psql`.

Product / legal decisions required (not made by this checkpoint):

1. Deletion semantics. Evidence points to immediate permanent deletion: the
   owner-approved row subtitle is "Permanently remove your account", the schema
   cascades from `auth.users`, and `deleted_at` is the generic sync tombstone
   column on every mutable table. No grace period exists anywhere. The
   implementation is immediate hard delete; confirm, or choose a scheduled
   deletion before deploy.
2. `audit_logs` retention. No code writes `audit_logs` today and `details` is
   free-form `jsonb`. Before any writer is added, decide what `details` may hold
   and how long rows live; a SET NULL foreign key does not remove an email, name
   or object key stored in `details`. Do not invent UAE retention rules.
3. Other accounts' notifications. `sender_user_id` becomes NULL, but a title or
   body that names the deleted sender is not rewritten. No server writer exists
   yet; decide before one does.
4. `revenuecat_webhook_events.app_user_id` / `payload` have no foreign key and
   survive deletion. Decide retention when RevenueCat goes live. Deleting an
   account is not a refund or a store cancellation, and the UI says so.
5. Toolkit documents (scanned, signed, combined, converted PDFs) are
   device-local and are kept, like on logout. Decide whether deletion should
   remove them.
6. Accounts without an email identity (future Google, Apple, phone) get
   `reauthentication_unsupported`. Each provider needs its own confirmation at
   `verifyAccountPassword` before it ships.

Backlog observed, not implemented:

- `deleteAccountUnavailable` is now an unused localization key.
- Ordinary logout does not clear `cached_favorites`, cached counts or avatar
  caches; only account deletion does.
- Supabase Storage is not cleaned (0 objects today). If Storage is adopted, add
  owner-scoped cleanup to the Worker before the auth delete.

DELETE ACCOUNT REAL-DEVICE / HOSTED TEST MATRIX

Use two disposable test accounts (A and B) on a real device.

D1. Profile -> Delete Account opens the review step; Cancel and a barrier tap
    close it; nothing is deleted.
D2. Continue -> the button stays disabled until a password is typed and the box
    is ticked.
D3. Wrong password -> localized "incorrect" message, field cleared; A still signs
    in; A's avatar still loads.
D4. Correct password -> the sheet cannot be dismissed while deleting; the app
    lands on Welcome, never Home; the "deleted" toast appears.
D5. Hosted checks after D4 (read-only): no `auth.users`, `public.profiles`,
    `media_objects` or owned rows for A; R2 prefix `profiles/<A>/` is empty; B is
    untouched; `audit_logs` / `notifications.sender_user_id` references to A are
    NULL.
D6. Sign in as A with the old password -> rejected. Cold restart -> still logged
    out.
D7. Language and theme are unchanged after D4.
D8. Airplane mode at the moment of tapping delete -> network message; reconnect
    and retry -> completes (or "already deleted" path) and lands on Welcome.
D9. A with an avatar and several replaced avatars -> every object under the
    prefix is gone after D4.
D10. Arabic/RTL and dark mode for D1-D4.
D11. Worker 404 before deployment -> "not available right now, nothing was
     deleted".
D12. Regression: Email Change, Change/Forgot Password with recovery quarantine,
     Phone tabs and Add Phone entry, Edit Profile save, normal login/logout all
     behave as before.

NOW — in the Supabase SQL Editor, run
`supabase/validation/account_deletion_cascade_validation.sql` as `postgres` and
report row 0 plus any FAIL and every INFO row. It installs nothing and ends in
ROLLBACK. At the same time, answer product decision 1 (immediate permanent
deletion, yes or no).

NEXT — if the script PASSES and decision 1 is yes: run `npm test` in
`cloudflare/workers/r2-profile-upload`, deploy that Worker to a preview version
only, and exercise `/account/delete` with disposable accounts (wrong password,
recovery-session token, success, retry after success) before promoting it. Then
run the real-device matrix above.

DELETE ACCOUNT — CROSS-SYSTEM COMPLETION REVIEW (2026-09-13)

SUPERSEDED IN PART by "DELETE ACCOUNT — FINAL LOCAL HARDENING" below: the
database-set `cleanup_not_before` (creation + 10 min) and its 240 s
Cloudflare/Postgres clock assumption, the "Home may flash" known gap, the
"exists / no answer -> change nothing" convergence rule, the preview-Worker cron
plan, and this section's NOW/NEXT no longer apply.

Status: CODE_PROVEN after architecture correction. Not VERIFIED_HOSTED, not
VERIFIED_RUNTIME. Nothing deployed, applied, committed or run against hosted
systems. No hosted user was deleted.

Product owner decisions recorded (see `docs/DECISIONS.md`):

- Immediate permanent hard delete: APPROVED. No grace period, no soft-delete
  account lifecycle.
- Toolkit PDFs on the device are preserved.
- RevenueCat retention deferred until RevenueCat is live.
- Retained audit/security history must not contain direct personal identifiers.
- Google / Apple / phone reauthentication for deletion is future provider work.

Why the previous design was not safe:

1. Retry after auth deletion. The `already_deleted` path decoded the `sub` of a
   token that Supabase Auth had just rejected and swept that prefix. Its safety
   rested on an unverified assumption about GoTrue's check order, not on
   validation the Worker performed. A deleted account's token proves nothing
   and must authorize nothing.
2. Signed PUT race. A PUT URL issued before deletion is valid for 300 s. An
   object written with it after the auth delete had no server-owned owner:
   cleaning it depended on a client retry that might never come, authorized by
   item 1.
3. `/authorize` had no quarantine, so new URLs could be issued during the
   deletion itself.

Approaches evaluated:

- A. Synchronous flow, no durable state: rejected; it cannot remove objects
  written after the request ends and has no authority left once the user is
  gone.
- B. Durable server-owned deletion job created before the auth delete: needed.
  It is the only record that survives the cascade.
- C. Cleanup authority that survives auth deletion without client identity:
  needed, provided by a Worker cron over B's rows with the server secret.
- D. Block uploads and wait for PUT TTL before deleting auth: blocking needs B's
  durable state, and a request cannot wait 5+ minutes, so it reduces to B + C.
  B + C waits after the auth delete instead, which is equally final.
- E. Route uploads through the Worker instead of presigned PUTs, or revoke URLs
  by rotating R2 keys: rejected; the first redesigns the runtime-verified
  profile upload path, the second breaks every user's in-flight uploads.
  Cloudflare KV was rejected for the quarantine flag because its eventual
  consistency would break the ordering proof below.

MIGRATION REQUIRED: YES —
`supabase/migrations/20260913000100_account_deletion_jobs.sql`
(prepared, NOT applied).

- Table `public.account_deletion_jobs`: `user_id uuid primary key` (no foreign
  key), `status`, `created_at`, `updated_at`, `auth_deleted_at`,
  `cleanup_not_before` (database default creation + 10 min),
  `cleanup_attempts`, `last_error_code`. No email, name, phone, token, key or
  URL.
- States: `quarantined` -> `auth_delete_pending` -> `auth_deleted`
  (-> `cleanup_failed` <-> retried). Completed or abandoned jobs are DELETED.
  CHECK constraints reject unknown states and `auth_deleted`/`cleanup_failed`
  without `auth_deleted_at`.
- Access: RLS enabled with no policies; all privileges revoked from `public`,
  `anon` and `authenticated`; `service_role` only (the Worker's server secret).
  `updated_at` trigger reuses `public.set_updated_at()`.
- Retention: a row exists only while a deletion is in flight or awaiting
  finalization; nothing is kept about a completed deletion.

Upload quarantine (`worker.js` `/authorize`): read the clock (t0) -> refuse
with 409 if any job exists for the verified uid (fail closed if the table cannot
be read) -> sign -> refuse a URL whose `X-Amz-Date` is later than t0 + 60 s.
Every issued URL expires by t0 + 360 s. A job the check could have missed was
committed after the check, so its `created_at` is at least t0 less clock
difference, and its `cleanup_not_before` is at least t0 + 600 s. Holds while the
Cloudflare/Postgres clock difference plus the claim transaction stay under
240 s.

Post-auth-deletion cleanup authority: the Worker cron (`*/5 * * * *`,
`runDeletionFinalizer`) reads job rows with the server secret only:

1. `auth_deleted` / `cleanup_failed` past `cleanup_not_before` -> sweep
   `profiles/<user_id>/`, prove it empty, delete the job; on failure
   `cleanup_failed` with `cleanup_attempts + 1`, retried next run.
2. `auth_delete_pending` older than 15 min -> read the user back with the admin
   API: gone -> `auth_deleted`; still present and older than 60 min -> cancel.
3. `quarantined` older than 60 min -> gone -> `auth_deleted`; present -> cancel.

All transitions are compare-and-set on the current status. A retry cannot
affect another account because the prefix is derived only from the job's
`user_id`, which only a Supabase-verified request can create.

POST /account/delete order (`account_deletion.js`): verify token -> refuse
mismatched body id / recovery session -> re-verify password -> claim job ->
inventory and delete media, prove prefix empty (failure cancels job) -> CAS to
`auth_delete_pending` -> admin delete (ambiguous result settled by reading the
user; "exists" cancels job with `server_delete_failed`; unresolvable returns
`deletion_pending` and leaves the job for the finalizer) -> upsert
`auth_deleted` (recreates the job if the finalizer had abandoned it during a
stalled delete) -> best-effort immediate sweep. A retry after deletion returns
`session_expired` and does nothing else.

Client convergence after a lost response:

- `AccountDeletionStateStore` writes the account id immediately before the
  request, and clears it only on a proven outcome.
- On any open outcome (network, unknown, `deletion_pending`,
  `deletion_in_progress`, `session_expired`) the flow asks Supabase Auth via
  `SupabaseAuthRepository.probeCurrentAccount()` (`getUser()`, which in the
  pinned `gotrue` neither refreshes nor removes the session). `user_not_found`
  -> complete as deleted; other 401/403/404 -> end local state without claiming
  a deletion; exists / no answer -> error shown, marker kept.
- On every later session start for that account, `AuthViewModel` repeats the
  check while the marker matches the live uid. A cold start after a lost
  success therefore ends logged out without any new deletion request.
- Independent guarantee from pinned `gotrue` source (`_doRefresh`): a
  non-retryable refresh failure removes the session and emits `signedOut`, and
  a deleted account's refresh token can no longer refresh, so the device is
  logged out within the access-token lifetime even with no marker.
- Known presentation gap: on that cold start, the app may show Home briefly
  before the probe answers. The deleted account's still-valid JWT can create
  nothing in the meantime: every table `authenticated` can insert into
  references `public.profiles` directly or through a parent row, and those rows
  are gone. `/authorize` rejects the token. Hiding that moment would need a routing gate, which is out of scope.

Validation SQL safety review
(`supabase/validation/account_deletion_cascade_validation.sql`, not run):

- The first statement is `begin;` and the last is `rollback;`. There is no
  `commit` or `end transaction` anywhere, and exactly one `rollback`. A Flutter
  test enforces all three.
- All writes happen inside a nested block that always ends by raising
  `account_deletion_validation_rollback`, so they are rolled back before the
  report is written. If the run fails anywhere, the same handler records the
  failure and the outer transaction still cannot commit.
- Only two synthetic accounts are created, with reserved constant ids
  (`de1e7e00-...`) and `@account-deletion-validation.invalid` emails. A
  pre-check refuses to run if any of them already exists. The only `delete`
  statement is `delete from auth.users where id = user_a`, and no `update` of
  any `auth.` table exists. Tests enforce both.
- Child-row ids are reserved constants or `gen_random_uuid()` generated inside
  the transaction.
- Real rows are only counted: audit log count and JSON key names, webhook event
  count, notifications with a sender, Storage object count. No content is
  printed.
- It installs the job migration from its exact file text (a test fails on
  drift) unless the table already exists. It then checks RLS on / no policies /
  no anon-authenticated privilege, no foreign key, the PK, both CHECK
  constraints, that `authenticated` gets 42501 reading it, and that A's job row
  survives A's auth deletion. Post-checks confirm the table and every test row
  are back to their pre-run state.

Local verification:

- Worker: 31/31 (`npm test`). Mutation-checked: removing the quarantine check,
  the `cleanup_not_before` filter, the job claim, the compare-and-set before the
  admin delete, the signing-date bound, or the one-hour abandonment age each
  fails the suite.
- Flutter account suites: 48/48. Full suite: 395/395 PASS (was 382).
- `flutter analyze lib test`: 0 errors, 0 warnings, 112 pre-existing infos.
- `git diff --check`: clean. Generated plugin registrants drift with no content
  change, excluded.
- Protected UI: no change in this review. `profile_view.dart` is unchanged since
  the first Delete Account pass. Edit Profile, Login, Signup, Home, Email
  Change, Password and Phone have zero diff.

Still AWAITING HOSTED VALIDATION: secret-key acceptance on the Auth admin
DELETE/GET endpoints; `amr: recovery` on recovery tokens; `user_not_found` as
the `getUser()` code for a deleted account (if it differs, the device converges
through the "session ended" branch or the refresh failure instead); PostgREST
`resolution=ignore-duplicates` returning an empty array on conflict; the
Cloudflare cron trigger running; the clock-difference assumption.

Deploy order (owner-run, not done here): apply the migration BEFORE deploying a
Worker version that reads the table. `/authorize` fails closed, so the reverse
order would stop profile photo uploads.

NOW — in the Supabase SQL Editor, run
`supabase/validation/account_deletion_cascade_validation.sql` as `postgres`.
Report row 0, every FAIL and every INFO row. It installs the job table
migration inside the transaction and ends in ROLLBACK. If it PASSES, apply
`20260913000100_account_deletion_jobs.sql` yourself and confirm in the table
editor that `account_deletion_jobs` has RLS on, no policies, and no
anon/authenticated grants.

NEXT — preview Worker verification (preview version only, disposable accounts):

1. `npm test` in `cloudflare/workers/r2-profile-upload`; deploy a preview
   version with the cron trigger.
2. `/authorize` for an ordinary account still returns a signed PUT URL (no
   regression).
3. `/account/delete` with a wrong password -> `reauthentication_failed`; no job
   row.
4. Account A with an avatar: obtain a signed PUT URL, then `/account/delete`
   -> 200; job row `auth_deleted`; `auth.users`, `profiles`, `media_objects`
   for A gone; `/authorize` with A's old token -> refused.
5. Upload with the pre-deletion PUT URL within its 300 s -> object appears
   under `profiles/<A>/`.
6. Repeat `/account/delete` with A's old token -> `session_expired`; the object
   is still there; nothing else changed.
7. After `cleanup_not_before`, wait for a cron run (or trigger it from the
   dashboard) -> prefix empty, job row gone.
8. Account B untouched throughout.
9. Recovery-session token -> `recovery_session`.
10. Then the real-device matrix D1–D12 above, plus: kill the network right after
    tapping delete; reopen the app -> logged out, not signed in as the deleted
    account.

DELETE ACCOUNT — FINAL LOCAL HARDENING (2026-09-13)

Status: CODE_PROVEN. Not VERIFIED_HOSTED, not VERIFIED_RUNTIME. Nothing
deployed, no migration applied, nothing committed, no account deleted, nothing
changed in Cloudflare or Supabase.

1. Lost-response quarantine (closes the "Home may flash" gap)

Root cause: `_handleSessionIdentity` applied a restored session, recomputed
`authenticated` and notified GoRouter in the same turn. The pending-deletion
check ran afterwards as an async task. For one or more notifications the router
could therefore resolve `/home`, and hydration, the profile subscription and the
notification feed could start.

Fix, the same structure as the password-recovery quarantine:

- `AccountDeletionStateStore` is now primed at startup in
  `SupabaseBootstrapService` (next to `PasswordRecoveryStateStore.prime()`) and
  read synchronously.
- In `_handleSessionIdentity`, before anything is applied or published: a newly
  applied identity (not the already-authenticated same user) whose uid equals
  the marker enters `_enterAccountDeletionQuarantine`. `status = unknown`,
  `currentUser = null`, recovery false, hydration token bumped, profile
  subscription cancelled, then one notification. GoRouter's existing bootstrap
  gate holds `/`. `_recomputeStatus`, `_applyProfile` and
  `_refreshPasswordRecovery` refuse to lift it. `main.dart`'s notification proxy
  receives a null uid. No router or `main.dart` change was needed.
- `reconcileAccountDeletion(uid)` always ends the session for `uid` on the
  device (`completeAccountDeletion`). `getUser()` decides only the result:
  `user_not_found` -> `deleted`; exists, rejected, unanswered or thrown ->
  `sessionEnded`. It never touches a different signed-in account (checked
  before and after the probe). Concurrent calls share one run.
- `completeAccountDeletion` now resets application state synchronously BEFORE
  awaiting sign-out, so a different account that signs in during the sign-out is
  never overwritten. It re-reads the live uid before clearing single-slot
  caches, and clears the marker only when no session for the account remains.
- In-app flow: an open outcome now also ends the session. A new localized toast,
  `deleteAccountUnconfirmedToast` (EN/AR), says "we couldn't confirm the
  deletion, so you've been signed out; sign in again to check".
- The only bound in the path is a 15 s timeout on the single `getUser()` read.
  There is no `Future.delayed` or `Timer` in the quarantine, and a test enforces
  that.

Cold start with marker X and restored session X: `/` (bootstrap) -> `getUser()`
-> sign-out, caches cleared -> `/welcome`. Home is never built.
Ambiguous or offline: the same path, ending logged out. The marker is cleared
once the session is gone; a later sign-in as X is an ordinary session, proven to
exist by that sign-in.
Account switch: a marker for A never quarantines B; a late reconciliation for A
never signs out B.

2. Signed PUT / clock safety

- Maximum signed PUT lifetime: 300 s (`SIGNED_PUT_TTL_SECONDS`, now the single
  source for `worker.js`) + 60 s signing bound = 360 s after the quarantine
  check.
- Finalizer safety margin: 120 s (`FINALIZER_SAFETY_MARGIN_MS`). Window 480 s.
- `cleanup_not_before` is no longer defaulted by Postgres. The cron stamps it on
  its Cloudflare clock, read after it lists the job as `auth_deleted`
  (compare-and-set on `cleanup_not_before is null`), and sweeps on a later run
  at or after the stamp. The stamp follows the job's commit, which follows any
  check it could have missed, so the Postgres clock takes no part. Remaining
  assumption: Cloudflare's own clocks (signing isolate, R2 validation, cron
  isolate) agree within 120 s. Cloudflare publishes no bound, so it is stated
  here, and the margin can be raised with a one-line change.
- A job is deleted only after its prefix has been proven empty at or after the
  stamp. Sweeps are idempotent. A stamp is never read before the listing (a test
  enforces this).
- Jobs now carry `bucket`, and a finalizer acts only on its own bucket's jobs.

3. Supabase secret key semantics

The Auth admin calls no longer send `Authorization: Bearer <secret>`. The
`sb_secret_...` key is sent only as `apikey`, on every server call. The test
fake fails any request that places a secret key outside `apikey`, sends an
Authorization header with a secret key, or pairs a user JWT with anything but
the publishable key. Hosted acceptance of apikey-only admin DELETE/GET is
verified on staging first.

4. Migration final review (NOT applied)

`20260913000100_account_deletion_jobs.sql`:

- No foreign key.
- RLS enabled, no policies.
- `revoke all` from `public`, `anon` and `authenticated`; `service_role` only.
- Columns: `user_id` (PK), `bucket` (NOT NULL, non-blank), `status` (4 values),
  `created_at`, `updated_at` (trigger), `auth_deleted_at`,
  `cleanup_not_before` (nullable, no default), `cleanup_attempts`,
  `last_error_code`. No PII beyond the uid, no secret, no default payload.
- Constraints: status set; `auth_deleted_at` present exactly for
  `auth_deleted`/`cleanup_failed`; stamp only after auth delete; stamp not
  before `created_at` (sanity); attempts ≥ 0; error-code format.
- Indexes: `(bucket, status, cleanup_not_before)` for finalization,
  `(bucket, status, updated_at)` for reconciliation.
- Compare-and-set friendly: every transition filters on the current `status`
  or `cleanup_not_before is null`.

5. Validation script (NOT run; still rollback-only, embedded migration regenerated
from the file)

Expected output: a single result grid with columns `#`, `result`, `check_name`,
`detail`, ordered by `#`, plus a NOTICE line.

- Row 0: `PASSED` or `FAILED`, `ACCOUNT DELETION CASCADE VALIDATION PASSED: N
  passed, 0 failed`, detail "All changes were rolled back inside the run…".
  N is 31 when the table did not exist before the run, and 32 when it did (one
  extra post-check).
- `PASS` / `FAIL` rows, in order: pre (postgres, reserved ids unused) -> schema
  (FKs cascade or set null; only the three SET NULL columns; profiles cascade;
  no DELETE trigger on auth.users) -> install -> jobs shape (RLS/no policies,
  no anon/authenticated privilege, service_role CRUD, no FK) -> setup -> jobs
  behaviour (quarantined with null stamp, bucket required, early stamp rejected,
  PK, unknown status, auth_deleted needs timestamp, authenticated read denied
  42501) -> delete -> cascade -> job survives -> job to auth_deleted -> stamp
  applies -> isolation -> anonymize ×2 -> idempotent -> post checks.
- `INFO` rows (not pass/fail): delete role, audit_logs count and detail keys,
  webhook event count, notifications with a sender, Storage object count,
  job-table state before the run, synthetic identity/session created or
  skipped.
- Interpretation: accept only row 0 = `PASSED` with 0 failed. Any `FAIL` row, or
  a row "validation stopped while …", means do not apply the migration. Report
  every INFO row regardless. Nothing persists either way.

6. Cron / preview correction and staging plan

Correction: a preview version (`wrangler versions upload`) does not receive Cron
Triggers; triggers deploy separately. The previous NEXT plan assumed otherwise
and is withdrawn. Nothing was changed in Cloudflare.

- A — HTTP tests against a preview URL: fine for `/authorize` and
  `/account/delete`, never for cron.
- B — local `scheduled()`: already covered by the Node suite (34 tests).
  `wrangler dev --env staging --test-scheduled` can exercise the handler
  locally, but it simulates R2 and needs secrets on the machine, so it adds
  little over the Node suite and is optional.
- C — separate staging Worker: REQUIRED for hosted cron.
- D — production code and trigger only after C passes.

Staging Worker, local config prepared in `wrangler.toml` `[env.staging]`:

- Name: `r2-profile-upload-staging`, deployed only with `--env staging`.
- Reachable only at its workers.dev URL. No route, no custom domain, preview
  URLs off.
- Bucket: a new, separate `broker-wallet-media-staging`. The Worker code is
  prefix- and bucket-scoped, so sharing the production bucket would be
  technically safe for disposable accounts, but a separate bucket gives
  isolation that does not depend on the code under test.
- Vars: as production except `R2_BUCKET_NAME = broker-wallet-media-staging`.
- Secrets, set with `wrangler secret put … --env staging`, values never in the
  repo:
  - `SUPABASE_SECRET_KEY`: a NEW, separately named Supabase secret key, revoked
    after the test.
  - `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`: a NEW R2 API token scoped to
    the staging bucket only.
- The production app never calls it. `R2Config` defaults to
  `https://media-api.brokerwallet.ae`; staging is reached only with curl or a
  local debug build run with `--dart-define=R2_UPLOAD_WORKER_URL=<staging URL>`.
  Never ship such a build.
- Shared Supabase: staging uses the hosted project and the same job table. Its
  jobs are tagged with the staging bucket, so the production finalizer ignores
  them and the staging finalizer ignores production jobs.
- Cleanup after the test:
  1. `wrangler delete --env staging` (removes the Worker, its cron and its
     secrets).
  2. Confirm `account_deletion_jobs` has no row with
     `bucket = 'broker-wallet-media-staging'`.
  3. Empty and delete the `broker-wallet-media-staging` bucket.
  4. Revoke the staging Supabase secret key and the staging R2 token.
  5. Confirm no disposable test users remain.

Production trigger deployment (after staging passes):

1. The migration is already applied (from NOW).
2. From the production config, `wrangler deploy` (no `--env`) — the code and the
   `*/5 * * * *` trigger go out together. Do not use
   `versions upload` / `versions deploy` without also running
   `wrangler triggers deploy`, or the finalizer will not run.
3. Confirm in the dashboard that the production Worker lists the cron trigger
   and that `/authorize` still issues URLs for a normal account.
4. Smoke-test one disposable-account deletion end to end, including one cron
   finalization.

Local verification:

- `npm test`: 34/34. New mutations caught: stamp read before listing, bucket
  filter removed, secret sent as Bearer, finalizing without a stamp, zero margin.
- Flutter account suites: 54/54, including the new
  `test/account/account_deletion_quarantine_test.dart` (12 tests covering the
  eleven required race cases, plus a no-timer source guard and a GoRouter
  widget test in which Home is never built). Removing the quarantine check fails
  9 of them.
- Full Flutter suite: 401/401 PASS.
- `flutter analyze lib test`: 0 errors, 0 warnings, 112 pre-existing infos.
- `git diff --check`: clean. Generated plugin registrants drift with no content
  change, excluded.
- Protected UI: unchanged since the first Delete Account pass (`profile_view.dart`
  Delete Account `onTap` only). `app.dart`, `main.dart`, Edit Profile, Login,
  Signup, Home, Email Change, Password and Phone have zero diff. The only UI
  addition is one toast string in the existing delete flow.

READY FOR HOSTED VALIDATION: YES (the rollback-only script only).

NOW — do not perform it here. In the Supabase SQL Editor, as `postgres`, run
`supabase/validation/account_deletion_cascade_validation.sql` and report row 0,
every FAIL row and every INFO row. Apply nothing, whatever the result.

NEXT — only if row 0 is PASSED with 0 failed:

1. Apply `20260913000100_account_deletion_jobs.sql` (owner action). Confirm RLS
   on, no policies, and no anon/authenticated grants.
2. Create `broker-wallet-media-staging`, a bucket-scoped R2 token and a
   separately named Supabase secret key.
3. From `cloudflare/workers/r2-profile-upload`: `npm test`, then
   `wrangler deploy --env staging`, then
   `wrangler secret put SUPABASE_SECRET_KEY --env staging` (and the two R2
   secrets).
4. Against the staging workers.dev URL with disposable accounts:
   - `/authorize` signs a URL;
   - wrong password -> `reauthentication_failed`, no job;
   - recovery token -> `recovery_session`;
   - account A: take a PUT URL, delete -> 200, job `auth_deleted` with bucket
     staging and a null stamp; `/authorize` refused for A;
   - upload with the old URL within 300 s;
   - retry delete with A's old token -> `session_expired`, object still there.
5. Wait for a cron run -> stamp set to about now + 480 s. Wait for the next run
   at or after the stamp -> prefix empty, job gone. Account B untouched. This
   confirms the cron trigger, apikey-only Auth admin DELETE/GET, PostgREST
   `ignore-duplicates` / `is.null` behaviour and R2 expiry enforcement on
   hosted.
6. Staging cleanup as listed above.
7. Production trigger deployment as listed above.
8. Real-device matrix D1–D12, plus cold-start convergence: delete with the
   network cut after the tap, reopen -> never Home, lands logged out.

DELETE ACCOUNT — STAGING ISOLATION FINAL FIX (2026-09-13)

Hosted state reported by the product owner (not performed by an agent):

- `supabase/validation/account_deletion_cascade_validation.sql` ran on hosted:
  PASSED, 31 passed, 0 failed.
- Migration `20260913000100_account_deletion_jobs.sql` is APPLIED and
  VERIFIED_HOSTED.

This supersedes steps 1 and 3 of the "FINAL LOCAL HARDENING" NEXT list above.
At the time of this step nothing was deployed, no Cloudflare resource was
created, no Supabase hosted state was changed, no migration was added, and
nothing was committed. The Worker's hosted status at that time is superseded by
"DELETE ACCOUNT — CURRENT CHECKPOINT" below.

1. Cross-bucket job ownership (fixed)

Root cause: only the finalizer filtered on `bucket`. On the interactive path,
`claimDeletionJob` reused any `quarantined` row (its `loadJob` did not even read
`bucket`), `compareAndSetJob` and `cancelJob` filtered on `user_id` + `status`
only, and `recordAuthDeleted` merge-upserted by `user_id` and could rewrite
another bucket's row. Staging and production share one Supabase job table, so a
staging request could have reused, advanced, cancelled or overwritten a
production job, and the reverse.

Fix (`account_deletion.js`, no schema change):

- `loadJob` reads `user_id, bucket, status` in any bucket.
- `claimDeletionJob` conflict: other bucket -> `deletion_in_progress` (409),
  before any media inventory, R2 delete or auth call; same bucket +
  `quarantined` -> safe retry; anything else -> 409.
- `compareAndSetJob`, `cancelJob` and the finalizer stamp all add
  `bucket=eq.<R2_BUCKET_NAME>`.
- `recordAuthDeleted`: compare-and-set this bucket's `auth_delete_pending` /
  `quarantined` job to `auth_deleted`. Otherwise re-read: this bucket's job
  already `auth_deleted` / `cleanup_failed` -> done; another bucket's job -> log
  a fixed line, return failure, leave it untouched; no job -> insert with
  `resolution=ignore-duplicates` (never merge), re-read on conflict. The
  post-auth-delete recovery (recreating a job the finalizer abandoned) is kept
  without any cross-bucket takeover.
- `assertUploadsAllowed` still blocks when a job exists in ANY bucket.
- The finalizer stays bucket-scoped.

Residual, not solvable without a schema change and not reachable in the intended
use: if a staging job and a production deletion ever target the same uid at the
same time, the second is refused. If a foreign-bucket job appears between a
production auth delete and its job record, production cannot record its own
finalization, and a late upload to the production prefix is not swept. Staging
must therefore use disposable accounts that never exist in production use.

2. Staging access gate (added)

`staging_gate.js`, called first in `worker.js` `fetch` (only a CORS `OPTIONS`
reply comes before it):

- When `STAGING_TEST_KEY` is bound, a missing or wrong
  `X-Broker-Wallet-Staging-Key` gets a fixed 403 `{"error":"Forbidden"}` before
  any Supabase, R2 or account logic. A bound empty key denies everything.
- The comparison is SHA-256 of both values with a no-early-exit XOR over the
  digests. The key is never logged or returned.
- When the secret is not bound (production), the gate returns immediately and
  behaviour is unchanged.
- Cron (`scheduled`) is not gated.
- `/account/delete` still requires the user JWT and password behind it.

`wrangler.toml`: `[env.staging.secrets] required` = `SUPABASE_SECRET_KEY`,
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `STAGING_TEST_KEY`. Production
required secrets are unchanged and do not mention the key. Staging keeps
`r2-profile-upload-staging`, `broker-wallet-media-staging`,
`workers_dev = true`, no route, no custom domain.

3. First-time staging bootstrap (corrected; prepared, not run)

The earlier "deploy, then `wrangler secret put`" order is withdrawn: required
secrets are validated before `wrangler deploy`, and `wrangler secret put`
deploys a version immediately. New local files: `staging-bootstrap/placeholder.js`
(404 for everything; no bindings, env, imports or network),
`staging-bootstrap/wrangler.toml` (name `r2-profile-upload-staging`,
`workers_dev = false`, no triggers, bindings, vars or route) and
`staging-bootstrap/README.md` with the exact sequence:

1. `npm test`.
2. `wrangler deploy --config staging-bootstrap/wrangler.toml` (placeholder).
3. Create the staging Supabase secret key, the staging-bucket-scoped R2 token
   and a random `STAGING_TEST_KEY`.
4. `wrangler secret put <NAME> --name r2-profile-upload-staging` for each of the
   four, entered interactively; `wrangler secret list` shows exactly those four.
5. `wrangler r2 bucket create broker-wallet-media-staging`.
6. `wrangler deploy --env staging` (replaces the placeholder and keeps the
   secrets).
7. Confirm a missing key and a wrong key both return 403 before anything else.

Version-dependent alternatives (a secrets file on deploy or upload,
`wrangler versions secret put`) are documented as "confirm in the installed
Wrangler's `--help` first" and are not relied on.

Local verification:

- `npm test`: 55/55. `account_deletion.test.mjs` has 44 tests, including 10
  cross-bucket tests: production↔staging claim refusal with no R2 or auth call,
  compare-and-set and cancel refusal, no overwrite in `recordAuthDeleted`,
  absent-row recreation, reconciled-row acceptance, any-bucket upload block,
  same-bucket quarantined retry, and per-bucket finalizers over one shared
  table. `staging_gate.test.mjs` has 11 tests: missing, wrong, empty, near-miss
  and correct keys, production no-op, gate-before-routes and cron-not-gated
  source order, staging-only required secret, and placeholder inertness.
- Mutations caught: claim ignoring bucket, compare-and-set without bucket,
  cancel without bucket, `recordAuthDeleted` taking over another bucket.
- `flutter test`: 401/401 PASS. `flutter analyze lib test`: 0 errors, 0
  warnings, 112 pre-existing infos. `git diff --check`: clean.
- Protected UI: no Flutter file changed in this step. `profile_view.dart` still
  differs only by the Delete Account `onTap`; Edit Profile, Login, Signup, Home,
  Email Change, Password and Phone have zero diff. Generated plugin registrants
  are excluded.

(The staging bootstrap was subsequently completed by the product owner; the
READY / NOW / NEXT that stood here are superseded by the section below.)

DELETE ACCOUNT — CURRENT CHECKPOINT (2026-09-14)

SUPERSEDED by "DELETE ACCOUNT — PRODUCTION ACCEPTANCE" below. The production
preflight and deployment in this section's NOW / NEXT have been completed, and
the "production NOT DEPLOYED" and "real-device NOT RUN" statements no longer
apply. The staging evidence recorded here still stands.

Status: hosted staging Delete Account E2E is VERIFIED_RUNTIME + VERIFIED_HOSTED.
The production Worker is NOT DEPLOYED with this implementation. Real-device
acceptance D1–D12 has NOT RUN. Do not read anything below as a production PASS.

Evidence, as reported by the product owner:

- Local: Worker tests 55/55 PASS; Flutter tests 401/401 PASS;
  `flutter analyze`: 0 errors, 0 warnings, 112 pre-existing infos.
- `account_deletion_jobs` migration: APPLIED + VERIFIED_HOSTED (rollback-only
  validation PASSED, 31 passed, 0 failed).
- Staging Worker `r2-profile-upload-staging`:
  - staging access gate: VERIFIED_RUNTIME;
  - R2 authorize / PUT / confirm / signed GET: VERIFIED_RUNTIME;
  - correct-password hard delete: VERIFIED_RUNTIME;
  - removal of the `auth.users`, profile and media rows: VERIFIED_HOSTED;
  - the deleted user's old JWT on retry -> 401 `session_expired`:
    VERIFIED_RUNTIME;
  - cron stamped `cleanup_not_before` and later removed the deletion job:
    VERIFIED_HOSTED.
- Hosted `account_deletion_jobs` now: staging 0, production 0, total 0.

Not verified and not claimed:

- Anything on the production Worker (`r2-profile-upload`,
  `media-api.brokerwallet.ae`): the Delete Account code, the upload quarantine
  on `/authorize` and the production cron trigger are NOT DEPLOYED.
- Real-device Delete Account acceptance (D1–D12, plus the cut-network cold-start
  convergence): NOT RUN.
- Staging checks not in the evidence above (wrong password, recovery-session
  token, the signed-PUT late-upload race) are not recorded as verified.

Staging infrastructure (the Worker, the `broker-wallet-media-staging` bucket, and
its staging-only secrets) is intentionally RETAINED until production real-device
acceptance succeeds. It is cleaned up separately afterwards, per
`staging-bootstrap/README.md`.

Constraint for device testing: the app does not send
`X-Broker-Wallet-Staging-Key`, so a device build pointed at the staging Worker
would get 403 on every Worker call. That would be reported as an unconfirmed
outcome and sign the user out. Real-device acceptance must therefore run against
the production Worker once it is deployed. Never put the staging key in the app,
and never ship a build that points at staging.

NOW — production Worker deployment preflight (read-only; deploy nothing):

1. Confirm the production Worker's current deployed version and its existing
   secrets (`SUPABASE_SECRET_KEY`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`)
   without printing values, and that the production config does not bind
   `STAGING_TEST_KEY`.
2. Confirm the top-level (production) `wrangler.toml` resolves to name
   `r2-profile-upload`, bucket `broker-wallet-media` and the `*/5 * * * *`
   trigger, with no staging values. Also confirm the custom domain
   `media-api.brokerwallet.ae`, which is configured in the dashboard rather than
   in `wrangler.toml`, stays attached to the production Worker.
3. Confirm hosted `account_deletion_jobs` is still empty and the migration is
   still present.
4. Run `npm test` in `cloudflare/workers/r2-profile-upload`.
5. Record a rollback target (the current production version id) before any
   deploy.

NEXT — only after the preflight passes: deploy the production Worker code and
its cron trigger together (`wrangler deploy`, no `--env`). Then confirm
`/authorize` still signs URLs for an ordinary account and the dashboard lists the
trigger. Then run the real-device matrix D1–D12 plus cut-network cold-start
convergence against production. Staging cleanup follows only after that
acceptance succeeds.

DELETE ACCOUNT — PRODUCTION ACCEPTANCE (2026-09-14)

Status:

- Production normal Delete Account happy path: VERIFIED_RUNTIME +
  VERIFIED_HOSTED + VERIFIED_REAL_DEVICE.
- Production wrong-password path: VERIFIED_RUNTIME + VERIFIED_HOSTED +
  VERIFIED_REAL_DEVICE.
- Dedicated lost-response / cut-network deletion scenario: NOT RUN / DEFERRED.
  The product owner explicitly chose to stop further disposable-account testing.
  The lost-response marker and bootstrap quarantine remain CODE_PROVEN only
  (local tests); they are not runtime-, hosted- or real-device-verified.

All facts below were observed by the product owner. No agent deployed, applied
or changed hosted state.

Production Worker (`r2-profile-upload`):

- Version `f5bdf3eb-400e-488f-930b-d3c5e78a0624`, serving 100% of production
  traffic.
- Rollback target: previous version `491a5e0f-6b51-4ca9-8d33-8164bcfec348`.
- `media-api.brokerwallet.ae` is attached.
- Cron trigger `*/5 * * * *` is deployed and visible.
- `STAGING_TEST_KEY` is not bound in production.
- No-JWT smoke:
  - `/authorize` -> 401: PASS;
  - `/profile-image-url` -> 401: PASS;
  - `/account/delete` -> 401 `session_expired`: PASS.

Real-device Delete Account, disposable account uid
`1f5ce143-1bca-46d7-8d76-53743493176c`:

- Real-device login: PASS.
- Production profile-image upload: PASS.
- Wrong-password Delete Account: PASS.
  - The user stayed signed in, the profile stayed accessible and the profile
    image remained.
  - The localized incorrect-password message was shown (reported as "Incorrect
    password").
  - Hosted state was unchanged: auth user exists, profile exists,
    `media_objects` = 1, deletion jobs = 0.
- Correct-password Delete Account: PASS.
  - Final screen Welcome; Home did not appear.
  - The old profile, name and image did not remain visible.
  - The app remained responsive.
- Force-stop and cold restart after deletion: PASS.
  - Welcome only, no Home flash.
  - No deleted profile, name or image.
  - The app remained responsive.
- Signing in with the deleted account's previous credentials fails, as
  expected.

Hosted post-delete, final verified state:

- auth user: absent.
- profile: absent.
- `media_objects`: 0.
- `account_deletion_jobs`: 0.
- The production cron / finalizer completed successfully.

Not verified and not claimed:

- The lost-response / cut-network scenario (delete with the network cut after
  the tap, reopen): NOT RUN / DEFERRED.
- The matrix items not listed above (D1–D12 items beyond login, upload, wrong
  password, correct password, cold restart and old-credential sign-in — for
  example Arabic/RTL and dark-mode runs, the Worker-404 message, and the full
  Email Change / Password / Phone regression pass) are not recorded as run in
  this acceptance.
- In production, the recovery-session refusal and the signed-PUT late-upload
  race were not exercised.

Staging infrastructure (`r2-profile-upload-staging`,
`broker-wallet-media-staging`, staging-only secrets) remains temporarily
retained. It is not part of this commit's cleanup, and it is removed separately
per `staging-bootstrap/README.md` when the owner decides.

NOW — review and commit the Delete Account change set when ready. Exclude the
generated plugin registrant files under `linux/flutter/`, `macos/Flutter/` and
`windows/flutter/`; they carry no content change.

NEXT — owner decisions, in any order: run the deferred lost-response /
cut-network scenario with a disposable account if and when chosen; decommission
the staging Worker, bucket and secrets per `staging-bootstrap/README.md`. Google
/ Apple remain deferred in the project order.

PROFILE COMPLETION 1 — VERIFIED_REAL_DEVICE (2026-09-14)

Implemented only the authorized Profile/Settings scope:

- Added Help & Support, Security Center, Privacy Policy and Terms & Conditions
  destinations, with new standalone GoRouter routes.
- Help & Support links only to real existing destinations; Contact Us remains
  the existing honest placeholder.
- Security Center reads the current `AuthViewModel`/`UserModel` presentation
  state and reuses `/edit-profile` plus the verified
  `showDeleteAccountFlow(context)` flow. It introduces no Auth or Supabase
  implementation.
- Privacy Policy and Terms & Conditions are localized pre-release legal shells;
  no legal/contact content was invented.
- Removed the fake `user@example.com` fallback, localized logout progress and
  failure text, and corrected SettingsTile's RTL chevron and switch-label
  directional padding.

Static evidence:

- Focused `test/profile/profile_completion_one_ui_test.dart`: PASS (5/5).
- Updated `test/account/delete_account_test.dart` only after owner approval:
  it continues to protect the Profile row order and the existing verified
  Delete Account action, and now also asserts the four authorized Profile
  routes instead of the retired placeholder navigation.
- Directly affected Delete Account source-contract test: PASS (33/33).
- `flutter test`: PASS (406/406).
- `flutter analyze`: 0 errors, 0 warnings and 112 pre-existing infos.
- `git diff --check`: PASS.

Physical-device acceptance reported by the owner: PASS.

- English Light: PASS.
- English Dark: PASS.
- Arabic RTL: PASS, including layout, directional chevrons and no clipped text.
- Profile, Help & Support, Security, Privacy Policy and Terms & Conditions:
  PASS.
- Navigation and back behavior: PASS.
- Security opens the existing Delete Account sheet unchanged: PASS.
- No fake `user@example.com` presentation, crash, or unexpected protected-UI
  regression: PASS.

Status: VERIFIED_REAL_DEVICE. The static gates above remain passing at their
recorded evidence level.

NOW — retain this verified Profile Completion 1 state; no source/test change is
required for this documentation sync.

NEXT — begin only the owner-approved next checkpoint, keeping this acceptance
evidence intact.

FAVORITES COLD-LOAD DEDUPLICATION = CODE_PROVEN

- Cold/no-cache duplicate initialization was source-confirmed.
- Empty-cache construction now starts one authoritative Favorites load.
- Warm-cache path still performs one background authoritative refresh.
- Manual refresh and optimistic mutation paths remain unchanged.
- Targeted Favorites tests pass.
- Full Flutter suite passes.
- Analyzer has 0 errors / 0 warnings.
- Profile RTL test contained contradictory assertions and was corrected
  TEST-ONLY; production SettingsTile/UI was not changed.
- No runtime performance gain is claimed yet.
- Physical-device/Profile-mode Favorites acceptance remains pending.

Status: CODE_PROVEN. Not VERIFIED_RUNTIME or VERIFIED_REAL_DEVICE.

CORE ENTITY DATA READINESS — VERIFIED_REAL_DEVICE + VERIFIED_HOSTED (2026-09-15/16)

The product owner tested all six entities on a physical Android device.
Hosted Supabase read-back was performed separately. Statuses below are the
owner's observations, not inferences from tests.

Broker:

- Create, Read/List, Edit, Soft Delete: VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.

Office:

- Create, Read/List, Edit, Soft Delete: VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.
- Create/Edit with phone: VERIFIED_REAL_DEVICE + VERIFIED_HOSTED, retested
  after the phone_e164 hotfix below.

Watchman:

- Create with phone, Read/List, Edit with phone, Soft Delete:
  VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.

Owner:

- Create with phone, Read/List, Edit with phone, Soft Delete:
  VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.
- No-media path only. Owner media remains deferred.

Request:

- Create with phone, Read/List, Edit with phone, Soft Delete:
  VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.
- Request areas were saved and updated successfully; hosted `request_areas`
  read-back confirmed child records and ordinal ordering.

Offer:

- Create with phone, Read/List, Edit with phone, Soft Delete:
  VERIFIED_REAL_DEVICE + VERIFIED_HOSTED.
- Offer areas were saved and updated successfully; hosted `offer_areas`
  read-back confirmed child records and ordinal ordering.
- No-media path only. Offer media remains deferred.

These are scoped CRUD/read-back verifications for the six listed entities on
one physical device and one hosted project. They are not a statement of
complete public-release readiness, and they do not include cross-account
authorization negative tests or exhaustive failure-recovery testing — no such
evidence exists yet.

PHONE E.164 CONSTRAINT HOTFIX — APPLIED + VERIFIED_HOSTED

The malformed `phone_e164_format` CHECK constraints on `profiles`,
`requests`, `offers`, `owners`, `offices`, `brokers` and `watchmen` (over-
escaped regex, previously rejecting every valid E.164 number — see the
migration's own header comment for the full root-cause explanation) were
corrected by
`supabase/migrations/20260915000100_fix_phone_e164_format_constraints.sql`,
using `^[+][1-9][0-9]{6,14}$`.

- Hosted status: APPLIED + VERIFIED_HOSTED.
- RLS and column grants were checked after the migration; unchanged.
- Office phone Create/Edit was subsequently verified on the real device and
  against the hosted database (see Office above).
- No phone normalization, Auth, RLS or Flutter code was modified for this
  hotfix.

MIGRATION-HISTORY RECONCILIATION — commit `0d7fb17`

Three local migration filenames were renamed to match the timestamps already
applied on hosted Supabase, with no content change (confirmed: three 100%
identical renames, 0 insertions/0 deletions):

- `20260911181050_revoke_client_profile_phone_writes.sql`
- `20260911181112_guard_pending_phone_changes.sql`
- `20260913175221_account_deletion_jobs.sql`

The owner confirmed the post-rename Supabase dry-run reported "Remote
database is up to date." No old migration was rerun and no remote history
was repaired.

REMAINING LIMITATIONS — explicitly deferred or unverified

- Owner media and Offer media.
- Subscription and quota enforcement.
- Phone Login/Signup backend authentication (legacy-Firebase only; see the
  PHONE LOGIN / SIGNUP sections above).
- Final UAE SMS acceptance.
- Other existing release/security checkpoints not listed above.

NOW — nothing is pending on CORE ENTITY DATA READINESS; this documentation
sync is the closing action.

NEXT — FAVORITES COLD-LOAD DEDUPLICATION — REAL-DEVICE VERIFICATION.

The Favorites deduplication change (`2372896 perf: deduplicate favorites cold
load`) is CODE_PROVEN: targeted tests passed, but real-device performance
verification was deferred because real entity data was not ready. That
dependency is now resolved for the six tested basic CRUD flows above — it is
not, by itself, proof that Favorites persistence or migration works, since
Favorites has not yet been runtime-verified at all.

Before any Favorites testing or further optimization, the next checkpoint
must first verify, on a real device:

- The currently reachable Favorites route.
- The current backend used by Favorites.
- Which entity types Favorites actually supports.
- How an actual favorite is created and persisted.
- Cold empty-cache behavior.
- Warm-cache behavior.
- Refresh after an optimistic favorite mutation.

Do not assume core CRUD verification automatically proves Favorites
persistence or migration. Do not claim measurable performance improvement
without before/after evidence. No new optimization should be performed
before this runtime verification is complete.

FAVORITES CREATE PERMISSION FIX — VERIFIED_REAL_DEVICE (2026-09-16)

Real-device Favorites verification found that adding a Favorite failed with
`PostgrestException(message: permission denied for table favorite_brokers,
code: 42501, ...)`. Root cause, confirmed from the installed `postgrest`
client source: the existing `FavoriteService.addToFavorites` used a bare
`.upsert({...})`, which defaults to `Prefer: resolution=merge-duplicates` —
PostgREST executes that as `INSERT ... ON CONFLICT DO UPDATE`, which Postgres
requires UPDATE privilege for at plan time even when no row actually
conflicts. Hosted `authenticated` has SELECT/INSERT(owner_id,
target_id)/DELETE on all six `favorite_*` tables but no UPDATE anywhere — a
deliberate, consistent contract across all six tables, not an oversight.

Fix: the same call now passes `ignoreDuplicates: true`, which PostgREST
executes as `INSERT ... ON CONFLICT DO NOTHING` — needs only INSERT privilege,
matches the existing grants exactly, and is naturally idempotent on a
double-tap or a concurrent retry (no error, no duplicate row, `added_at`
untouched on an already-existing row). No database migration, GRANT, or RLS
change was made or is required. `removeFromFavorites` and `isFavorite` were
unaffected (never used upsert).

Static evidence: a client-level regression test constructs a real
`SupabaseClient` against a recording mock transport (the same harness
pattern as `test/auth/phone_verification_test.dart`) and asserts the
outgoing request is `POST` with `Prefer: resolution=ignore-duplicates`, that
the body never carries `added_at`, and that a repeated call completes without
throwing.

Real-device verification (owner, 2026-09-16): Add Broker Favorite, correct
heart state, correct item in the Favorites list, correct Broker details,
persistence after navigation, persistence after force-stop and restart,
Remove Favorite, absence after refresh, previous 42501 error gone, no crash.
Independent hosted read-back confirmed one `favorite_brokers` row existed
after addition and zero rows existed after removal, with the underlying
Broker record untouched.

Status: VERIFIED_REAL_DEVICE for the tested Broker Favorite create/persist/
remove flow. Not a statement about the other five Favorite entity types, and
not a statement about Favorites cold-load performance, which remained a
separate, still-open question at this point.

FAVORITES ACCOUNT ISOLATION — VERIFIED_REAL_DEVICE (2026-09-16/17)

Investigating the permission fix surfaced a separate, pre-existing defect:
the local Favorites cache was a single Hive box (`cached_favorites`), shared
across every account that ever signed in on a device, with no owner field in
its `CachedFavoriteItem` schema and no clearing on ordinary sign-out — a
code-proven cross-account exposure path. A companion, smaller finding:
`OptimisticFavoritesService` (the in-memory optimistic favorite-flag map) is
a singleton created once at the app root and was never told about account
transitions either; its own `clearState()` method had zero call sites.

Rejected design: an intermediate design kept the single shared box and added
a durably persisted "owner uid" marker (mirroring `PasswordRecoveryStateStore`
/`AccountDeletionStateStore`), read-gating cache trust on a marker match. A
dedicated crash-safety review rejected this before implementation: Hive and
`shared_preferences` are two independent storage backends with independently
non-atomic durability, so a hard process kill could let one account's Hive
write durably commit while the marker store still named the previous
account — a genuine cross-account read on the next launch, provable by
direct trace, not merely theoretical. This design was never implemented and
is not the current architecture.

Implemented architecture: **account-scoped Hive boxes**. Each canonical
Supabase uid gets its own box, `cached_favorites_<uid>`
(`FavoriteService.boxNameForUid`). There is no shared mutable file and
nothing that can fall out of sync with anything else — an account's cache
"ownership" is the box's name, which only that account's own uid can ever
produce or open. `DeletedAccountLocalDataCleaner` now deletes the deleted
account's own box precisely, unconditionally (safe unconditionally, since
box names are disjoint — an improvement on the old code, which only cleared
the shared box when the deleted account happened to be the one signed in).

The pre-existing, unscoped `cached_favorites` box is deliberately **retained
on disk, never opened, read, migrated, or deleted** by the new code. Its rows
cannot be attributed to any account from the legacy schema, so there is
nothing safe to migrate; deleting it was implemented once, found to destroy
real, already-cached data with no isolation benefit (isolation comes
entirely from never referencing that name again), and was reverted before
any device test. Preserving it does not restore the old instant warm-cache
experience: the first Favorites open under the new per-uid box name always
cold-loads once, for every account, including one that had cached data under
the old scheme.

Additional protections, layered on top of box naming:

- An in-memory, monotonic account-generation counter
  (`FavoriteService.currentAccountGeneration`), bumped synchronously by
  `AuthViewModel._handleSessionIdentity` at both of its existing
  cache-ownership points (a null identity, and a different uid arriving
  directly) — the single canonical point every identity transition is
  recognized, not only explicit sign-out, so it also covers a server-side
  session invalidation.
- `cacheFavorites` and `OptimisticFavoritesService.updateLoadedFavorites`
  both require (not merely accept) an `expectedGeneration` argument, so a
  fetch or optimistic-sync that started under one account cannot write its
  result after a later account is current — closes a real gap found during
  review, where `updateLoadedFavorites` had no such guard at all while
  `toggleFavorite`/`initializeFavoriteStatus` already did.
- `initializeCache()` re-checks both the live canonical uid and the
  generation immediately after its `Hive.openBox` await, before assigning
  the active cache reference — proven against the actual race (a transition
  while the box is still opening) by a test that starts the call, forces the
  transition mid-flight, then awaits it; the opened box is left untouched
  (never closed) since Hive tracks it globally by name.
- `OptimisticFavoritesService` gained `syncAccountGeneration()`, wired into
  `main.dart` by converting its Provider registration to a
  `ChangeNotifierProxyProvider<AuthViewModel, OptimisticFavoritesService>` —
  the same `??=`-preserves-the-same-instance shape already in production for
  `NotificationViewModel` — so `clearState()` (previously unreachable) now
  actually runs on a real identity transition, without losing any existing
  listener subscription.

STATIC TEST EVIDENCE

- Favorites tests: 20/20 PASS (permission-fix client-level tests, the
  pre-existing cold-load dedup suite unmodified in behavior, and the new
  account-isolation suite: box-naming isolation, simulated-restart
  cross-account read safety, same-account restart, the generation guard, and
  the `initializeCache` race).
- Targeted `flutter analyze` on every changed file: PASS, no issues.
- `git diff --check`: PASS, only the known generated-plugin-registrant
  line-ending drift, no real whitespace errors.
- Full `test/auth/`: 284/288 PASS. Full `test/account/`: 49/50 PASS. **Not**
  claiming either full suite passes.

PRE-EXISTING TEST FAILURES (five, unrelated, not fixed here)

All traced to commit `0d7fb17` (`chore: reconcile Supabase migration
timestamps`), which renamed three migration files with zero content change.
Four tests in `test/auth/phone_security_hardening_test.dart` and one in
`test/account/delete_account_test.dart` read migration files from disk by a
hardcoded pre-rename path (`File(path).readAsStringSync()`); all five predate
`0d7fb17` in their own last-modified commit and are untouched by any Favorites
work. Not migrations or tests to fix in this checkpoint.

SAMSUNG DEVICE VERIFICATION (owner-reported, 2026-09-17)

Test 3 — Single account, all reported PASS: app starts on the correct
account; initial Favorites state correct; Add Broker Favorite; correct Broker
details; persistence after navigation; persistence after force-stop and
restart; Remove Favorite and refresh; no 42501 error; no crash; no Provider
error.

Test 4 — Cross-account isolation, all reported PASS, full sequence: Account A
signs in and adds a self-owned test Broker to Favorites; Account A signs out
normally (no app-data clear); Account B signs in and opens Favorites
immediately; Account B does not display Account A's Favorites, including no
observed temporary/flash appearance; the app is closed and restarted while
on Account B; Account B's Favorites state remains correct; Account B signs
out; Account A signs in again; Account A sees only its own Favorites.

Status: **VERIFIED_REAL_DEVICE — OWNER-REPORTED** for this tested
single-account and cross-account UI behavior. Account B's own ability to
independently create and persist a favorite of its own was not part of the
tested sequence above and is not claimed.

HOSTED EVIDENCE AND LIMITS: The permission-fix flow (Broker add/remove) has a
hosted Supabase read-back from 2026-09-16, before the account-isolation
device tests. **No new hosted read-back was performed after Test 4** — the
cross-account result above is UI-observed only, not cross-checked against
`favorite_*` row ownership in the hosted database.

UNVERIFIED SCENARIOS — explicitly not claimed:

- No process-crash or disk-corruption scenario was exercised on the physical
  device; the `initializeCache` race is proven only by an automated test
  against a temp-directory Hive instance, not on-device.
- Interrupted writes (kill mid-write) were not exercised on a physical
  device.
- Not every `ChangeNotifierProxyProvider` scheduling edge case or optimistic-
  state race has dedicated automated coverage — `syncAccountGeneration`'s
  Provider wiring is verified by source inspection and by analogy to the
  already-working `NotificationViewModel` pattern, not by a widget test.
- Favorites functionality for the other five entity types (Requests, Offers,
  Owners, Offices, Watchmen) was not exercised on this device — only Broker.
- No performance measurement was taken in Profile mode; no cold-load speed
  claim is made.
- Full `test/auth/` and `test/account/` suites are not claimed to pass (see
  pre-existing failures above).
- Broker Wallet is not claimed production-ready by any of this work.

NOW — nothing is pending on FAVORITES ACCOUNT ISOLATION; this documentation
sync is the closing action. No commit or push was performed as part of any
step in this checkpoint.

NEXT — FAVORITES REMAINING ENTITY TYPES — READ-ONLY READINESS REVIEW.

Only Broker has been verified end to end (create-permission fix, persistence,
removal, and cross-account isolation) on a real device. Requests, Offers,
Owners, Offices and Watchmen share the same `FavoriteService`/
`OptimisticFavoritesService` code paths and the same hosted RLS shape
(ownership-scoped `favorite_*` tables), so the fixes above almost certainly
apply to all six uniformly — but this has not been exercised for the other
five, and must not be assumed. The next checkpoint should be read-only:
inspect the five remaining entity types' favorite/unfavorite UI entry points,
confirm nothing about them differs from Broker in a way that would evade the
fixes in this checkpoint, and identify the smallest additional real-device
verification step needed — without modifying production code or touching
hosted data.

---

## FAVORITES FINAL ACCEPTANCE — DOCUMENTATION CLOSURE

Closes two implementation checkpoints that ran after FAVORITES ACCOUNT
ISOLATION above and were not previously documented (both were
implementation-only tasks with no doc-update authorization at the time), plus
the owner's final Samsung device acceptance that followed both.

STALE-HEART REGRESSION (checkpoint: FAVORITES STALE HEART SCOPED
IMPLEMENTATION)

Root cause: an asynchronous ordering race in `OptimisticFavoritesService`
between a user mutation (`toggleFavorite`, Add/Remove) and a status read
(`initializeFavoriteStatus`/`updateLoadedFavorites`). A read dispatched before
a removal but resolving after it could publish stale pre-removal server truth
over the removal's own correct result, making a successfully removed item
show a selected heart again. An initial design proposal (a single shared
per-key version bumped by both reads and mutations) was rejected before
implementation: it would have let a later-starting read wrongly supersede an
already in-flight mutation's own successful result. The implemented fix uses
two independent per-key counters — `_mutationVersion` (bumped only by
`toggleFavorite`) and `_readVersion` (bumped only by a read) — so a read can
never invalidate a mutation, in either direction, while two overlapping reads
for the same key still agree on which is newest. Files changed:
`lib/src/services/optimistic_favorites_service.dart` only. New tests:
`test/favorites/optimistic_favorites_service_ordering_test.dart` (9 tests,
`Completer`-gated controllable fakes against the real production ordering
logic).

STALE-LIST FLICKER REGRESSION (checkpoint: FAVORITES STALE LIST
RECONCILIATION FIX)

A second, distinct regression found after the heart fix: the Favorites
*list* (not the heart icon) could still show a removed item reappear, or a
newly added item briefly disappear, because `FavoritesViewModel`'s three
bulk-fetch paths (`_refreshImmediately`, `_loadFreshFavoritesImmediately`,
`_loadFreshFavorites`) all assigned `_allFavorites = <fetched result>`
unconditionally once any fetch resolved — gated only by account generation,
never by which fetch was more recent or what had mutated since it started.
Fix: a new `_reconcileFetchedFavorites` helper reconciles a fetch's result
against the current list using the existing
`OptimisticFavoritesService.snapshotMutationVersions()` API (no changes to
that service were needed). For each key in the union of the fetched and
current lists, a key whose mutation was pending at fetch-start, is pending
now, or whose mutation version has changed since the snapshot defers to the
*current* list; every other key defers to the fetch. This protects both
stale presence (a fetch that still lists a just-removed item) and stale
absence (a fetch that predates a just-added item) symmetrically, without
fabricating any item data. All three fetch paths, including each one's
empty-favorites branch, now thread the same reconciled result through list
assignment, filtered/display state, the optimistic-service sync call, and
the cache write. File changed: only
`lib/src/views/Screens/home/favorites/favorites_viewmodel.dart` (the single
pre-authorized production file for that checkpoint). New tests:
`test/favorites/favorites_list_reconciliation_test.dart` — 10 deterministic
tests covering stale-remove and stale-add protection, pending-mutation
protection, consecutive removals with an unrelated item updating normally,
out-of-order overlapping fetches, failed-mutation behavior, empty-state
stability, account-transition safety, and same-id-different-type
independence. Pre-fix failure evidence: rather than resetting the git working
tree, the four reconciliation edits were temporarily reverted in place (via
the same edit tooling, with the exact original content snapshotted first),
the new test file was rerun, and the exact original content was then
restored and diff-verified byte-for-byte. **7 of the 10 new tests failed
against the pre-fix code**, reproducing the exact remove-reappear/disappear
symptom; the other 3 (empty-state, account-transition, same-id-different-type)
passed either way since those particular paths did not strictly require
reconciliation.

The Favorites-card removal path performing two separate DELETE calls
(identified during an earlier review) remains **unmodified, known technical
debt** — not addressed in either of these two checkpoints, and not implied
to be fixed by the owner's acceptance below. It is not to be actioned without
a separately scoped checkpoint or an explicit reliability/performance
justification.

STATIC TEST EVIDENCE (both checkpoints combined)

- `flutter test test/favorites/`: **39/39 PASS** (10 account-isolation + 3
  create-upsert + 10 list-reconciliation + 9 ordering + 7 initial-load).
- Targeted `flutter analyze` on every changed file: PASS, no issues.
- `git diff --check`: PASS — only the known generated-plugin-registrant and
  edited-file line-ending drift (LF-will-become-CRLF warnings), no real
  whitespace or conflict-marker errors.
- Not claiming a full application test suite PASS; the five pre-existing,
  unrelated migration-filename test failures documented in the FAVORITES
  ACCOUNT ISOLATION closure above remain outside Favorites scope and were not
  re-investigated here.

SAMSUNG DEVICE VERIFICATION — FINAL ACCEPTANCE (owner-reported)

The owner completed a further Samsung device test ("Samsung Test 7") after
the stale-list reconciliation fix and reported: Favorites addition works;
removal works correctly; removed items no longer reappear temporarily;
multiple-item removal works; the current removal experience is acceptable;
no new issue was reported during this final acceptance pass. The owner's own
words: "Now everything is good ... I test and everything is working well."

Status: **VERIFIED_REAL_DEVICE — OWNER-REPORTED** for the stale-heart
regression and the stale-list flicker/reappear regression, on the tested
scenarios (single- and multi-item Favorites add/remove). This is an
owner-reported observation, not a new automated log, timing measurement, or
independently captured device trace.

HOSTED EVIDENCE AND LIMITS: unchanged from the FAVORITES ACCOUNT ISOLATION
closure above — the most recent hosted Supabase read-back predates the
stale-heart and stale-list fixes. **No new hosted read-back was performed**
after either of these two UI/state-layer fixes; both are UI-observed
device evidence only.

KNOWN NON-BLOCKING TECHNICAL DEBT AND OUTSTANDING RISKS — explicitly not
claimed resolved by this closure:

- The Favorites-card double-DELETE path (above) — unmodified.
- Office, Owner and Request screens still lack the independently identified
  on-mount `initializeFavoriteStatus` calls that Broker (and, per source,
  presumably Offer/Watchmen) already have — unless current source now proves
  otherwise, this has not been re-checked in either of these two checkpoints
  and those three screens were **not modified**.
- No process-crash or interrupted-write scenario was exercised on the
  physical device for either fix.
- Full `test/auth/` and `test/account/` suites were not newly rerun in either
  checkpoint.
- Favorites functionality for entity types other than Broker was not part of
  the owner's reported Samsung Test 7 sequence above.
- Application-wide production readiness is not claimed.

NOW — nothing is pending on FAVORITES FINAL ACCEPTANCE; this documentation
sync is the closing action. No file was staged, committed, or pushed as part
of this checkpoint or the two implementation checkpoints it closes out.

NEXT — FAVORITES SCOPED COMMIT PREPARATION — READ-ONLY REVIEW. Prepare an
exact file-level staging and commit plan for owner approval, isolating the
Favorites-related changes from unrelated documentation edits and from
generated-plugin registrant drift. No staging or committing happens until
that review is explicitly approved.

(Editorial note: the Favorites commit above was subsequently approved,
staged, and committed as `3fb9634`; a full cross-account RLS metadata review
and an Office SELECT integration-test harness followed as separate
checkpoints, documented in this file's own commit history rather than
retroactively inserted here.)

---

## OFFER PRIVATE MEDIA — SOURCE IMPLEMENTATION (uncommitted)

Implements Offer-only private media upload, persistence, secure retrieval and
display, extending the existing, already-production-verified profile-image
Supabase + private Cloudflare R2 architecture. Owner media is explicitly out
of scope. **Not deployed. Not hosted-verified. Not device-verified.**

WORKER PRODUCTION COMPATIBILITY: confirmed before any change — the
repository's `cloudflare/workers/r2-profile-upload/worker.js` already
contains the full production route set (`/authorize`, `/confirm`,
`/profile-image-url`, `/account/delete`, and the scheduled deletion
finalizer), matching what is actually deployed. All additions below are
strictly additive to that file; no existing route, handler, or the
account-deletion/cron logic in `account_deletion.js`/`staging_gate.js` was
modified.

WHAT WAS IMPLEMENTED:

- Three new Worker routes on the same production Worker: `POST
  /offer-media/authorize`, `POST /offer-media/confirm`, `GET /offer-media`.
  Each independently verifies the Supabase access token and, server-side,
  that the authenticated user owns the target Offer (`owns` check via a
  service-role `offers` query, not a client-supplied id) before touching
  anything.
- Offer media objects are stored at
  `profiles/<uid>/offers/<offerId>/<mediaId>.<ext>` — deliberately nested
  under the *existing* profile-image account prefix rather than a new
  top-level one. `account_deletion.js`'s `removeAccountMedia` inventories
  every `media_objects` row for a deleted account and throws
  `media_cleanup_failed` for any row whose key falls outside that single
  per-account prefix; a separate `offers/...` prefix would have broken
  account deletion for any user who ever attached offer media. Nesting keeps
  offer media inside the existing account-deletion sweep with **no change**
  to `account_deletion.js`.
- Confirm links the upload into `offer_media` (idempotent insert, `Prefer:
  resolution=ignore-duplicates`, mirroring the existing Favorites insert
  pattern) *before* marking the media object `ready` — deliberately, so a
  failed link leaves the row `pending_upload`, where the existing
  `bestEffortDeleteInvalidObjectAndMarkFailed` cleanup path (shared with the
  profile-image code, unmodified) still correctly matches and fails closed
  instead of leaving an orphaned `ready`-but-unlinked object. A retry after
  a client-visible failure is safe: the link insert is idempotent and the
  mark-ready step re-applies against the still-`pending_upload` row.
- `GET /offer-media` returns fresh, short-lived signed R2 GET URLs
  (15-minute TTL, same as profile images) for the offer's confirmed media —
  never a permanently public URL, never a persisted signed URL.
- New `lib/src/services/r2_offer_media_upload_service.dart`, mirroring
  `R2ProfileUploadService`'s shape (bounded timeouts, sanitized exceptions,
  no token/response logging).
- `lib/src/services/ScreenServices/offer_service.dart`:
  `saveOfferWithMediaFast` no longer throws `StateError` for Supabase mode.
  It now saves the Offer row first (create or update, decided by an existing
  read rather than a new parameter, since the call site could not be
  changed — see below), then uploads attached files one at a time. The Offer
  row's own success is never rolled back for a media failure; failed
  file(s) are collected and surfaced as a thrown `StateError` naming the
  offer as saved and listing which photo(s) failed, so the existing
  unmodified error toast in `add_offers_viewmodel.dart` shows a true,
  specific failure instead of a false blanket success. New uploads append
  after whatever media the offer already has (ordinal continuity across
  edit sessions).
- `lib/src/services/supabase_core_entities_service.dart`: `getOffer(id)`
  (single-offer reads — detail/edit screens, Favorites cards, search
  results) now populates real signed `mediaUrls`/`mediaUrl`, tolerating a
  Worker failure by falling back to the empty list rather than breaking the
  read. The bulk `_fetchOffers()` list/grid fetch is **deliberately left
  unchanged** (still empty media) to avoid an unbounded per-offer Worker
  fan-out for a whole list at once — a named, deliberate limitation, not an
  oversight.

A LATENT BUG THIS EXPOSED AND FIXED: before this checkpoint,
`saveOfferWithMediaFast` under Supabase mode was unreachable whenever any
file was attached (it always threw first), so its plain-INSERT call to
`saveOffer` for an *already-existing* offer id (the edit-with-new-media
case) had never actually been exercised — it would have violated the
primary key. `_saveOfferWithMediaSupabase` now checks whether the offer
already exists and calls `updateOffer` instead of `saveOffer` in that case.

DATABASE MIGRATION REQUIRED: **NO.** `owner_media`/`offer_media`,
`media_objects`, their RLS policies, grants, and the
`validate_media_attachment_ownership` ownership trigger already existed
(confirmed in the CORE ENTITY CROSS-ACCOUNT RLS OWNERSHIP review) and are
unmodified.

STATIC CHECKS: `dart format` (new file formatted; the one pre-existing
over-length line in `offer_service.dart` left untouched, matching this
repo's documented pre-existing-deviation policy); targeted `flutter
analyze` on all three Dart files — no issues; `node --check worker.js` —
syntax OK; the existing `cloudflare/workers/r2-profile-upload` test suite
(`node --test`, 55 tests covering `account_deletion.js`/`staging_gate.js`,
none of which this checkpoint touched) — 55/55 still pass; `git diff
--check` — clean (only the pre-existing generated-plugin line-ending
drift).

WHAT REMAINS UNVERIFIED: no real upload was performed; no staging or
production Worker deployment occurred; no hosted Supabase mutation ran; no
device or emulator was used. A successful static analysis/syntax check is
**CODE_PROVEN**, not production verification. Offer media is **not**
production-ready.

EXACT NEXT CHECKPOINT — OFFER PRIVATE MEDIA STAGING ACCEPTANCE: deploy the
three new routes to the existing `r2-profile-upload-staging` Worker only
(never production directly), then exercise authorize → PUT → confirm → list
end to end against a disposable test Offer, verifying: a same-account round
trip displays the uploaded image; a cross-account attempt to authorize,
confirm, or list against another account's Offer is refused; an account
deletion for a user with attached offer media still completes and leaves
its `profiles/<uid>/` prefix empty. Only after that passes should production
deployment be considered, as its own separately approved step.

---

## OFFER PRIVATE MEDIA — STAGING API ACCEPTANCE (owner-executed)

Deployed to the existing staging Worker (`r2-profile-upload-staging`, version
`5934a60d-bf74-42fe-b3ef-c92fac5dfb15`, bucket `broker-wallet-media-staging`)
and exercised end to end by the owner from a local, owner-run PowerShell
procedure (never executed by an agent) using an explicitly approved,
disposable Account A / Account B pair and a disposable test Offer.

**Status: VERIFIED_HOSTED (API level), owner-executed.** All steps reported
PASS: the staging gate correctly rejects a request with no key; a request
with a valid key but no authentication is still rejected; Account A
authorizes an upload for its own Offer; the real selected JPEG uploads
directly to private staging R2 via the presigned URL; the upload confirms
successfully; Account A's authorized list returns it; the returned signed
GET URL retrieves the image; the downloaded bytes' SHA-256 matches the
original file exactly; Account B is denied with 404 on authorize, confirm,
and list against Account A's Offer and media. Production Worker
(`f5bdf3eb-400e-488f-930b-d3c5e78a0624`) was not touched and remains on its
prior version throughout.

**Exact test-artifact database read-back: PENDING.** The owner-executed run
created exactly one `media_objects` row (bucket
`broker-wallet-media-staging`), one `offer_media` association, and one R2
object in that bucket. A row-level reconciliation (offer ownership, media
bucket/status/owner match, exactly one association) was designed and is
ready to run the moment the owner supplies the specific `offerId` and
`mediaObjectId` from their local run — not yet supplied, so this specific
reconciliation is not yet closed, distinct from the API-level PASS above.

**Flutter real-device acceptance: NOT VERIFIED.** The staging run exercised
the Worker's HTTP contract directly; no Flutter code, on any device or
simulator, has executed the Offer Media upload/display path yet.

**Production deployment: NOT PERFORMED.** Production remains on
`f5bdf3eb-400e-488f-930b-d3c5e78a0624`, unchanged.

**Staging test artifacts: retained, cleanup not authorized.** The one
`media_objects` row, one `offer_media` association, and one R2 object created
by the acceptance run remain in the shared Supabase database (staging and
production share one project) and the staging bucket. No SQL delete, no R2
delete, and no account operation has been performed. Retention is not
characterized as indefinitely safe by default — it is an open decision for
the owner, to be resolved by either accepting it as a standing regression
fixture or approving a dedicated, dependency-ordered cleanup checkpoint
(delete the `offer_media` row, then the `media_objects` row, then the R2
object, each followed by a read-back).

**Do not mark Offer Media production-ready.** Only the Worker-side contract
is now real-world proven; the Flutter client path and production deployment
remain unverified and unperformed respectively.

NOW — nothing further is pending on Worker-side staging verification.

NEXT — reconcile the exact test artifacts once the owner supplies the
`offerId`/`mediaObjectId`, then prepare a separately approved production
deployment (its own checkpoint, gated on that reconciliation and, at the
owner's discretion, on a Flutter real-device pass first).

---

## OFFER MEDIA — PARTIAL-UPLOAD ERROR MESSAGE CORRECTION (uncommitted)

Owner-approved hosted reconciliation (separate from this correction, not
repeated here) subsequently found real Samsung device evidence: one `ready`
production media object/association for a newly created test Offer, and seven
`failed` `media_objects` rows (six on an edited test Offer, one on the created
test Offer) — all rejected during the Worker's `/offer-media/confirm` step,
never linked into `offer_media`. The exact per-object Worker rejection reason
is not persisted anywhere and could not be recovered; the image-format/
signature root cause behind those seven failures **remains unresolved** and is
explicitly out of scope for this checkpoint.

PROVEN DEFECT (source-confirmed, now corrected): `OfferService.
_saveOfferWithMediaSupabase` (`lib/src/services/ScreenServices/
offer_service.dart`) always saves/updates the Offer row first and only then
uploads attached media; a media-upload failure throws a specific `StateError`
naming the offer as saved and listing the failed file(s). The generic mapper
in `lib/src/common/utils/core_entity_error_message.dart` had no case for that
message, so it fell through to the same generic "Unable to update/save the
offer" text used for a total Offer-persistence failure — falsely implying the
Offer itself was not saved.

CORRECTION: `CoreEntityErrorMessage.save` gained one additional `StateError`
branch, matched only on the distinctive, grep-confirmed-unique substring
`'photo(s) failed to upload'` (present nowhere else in the codebase), placed
before the existing `'session'` StateError branch. It returns a fixed,
non-localized string — consistent with every other branch already in this
class, none of which are localized — stating that the entity was saved but
one or more photos could not be uploaded, without echoing the original
message, any file name, or any path. No other branch, no `offer_service.dart`
logic, and no unrelated CRUD module's error mapping were touched.

STATIC TEST EVIDENCE: new `test/common/core_entity_error_message_test.dart`,
8/8 PASS — the known partial-upload StateError maps correctly; the raw failed
file name is not leaked into the mapped message; the pre-existing session,
permission (Postgrest `42501`), and timeout mappings are unchanged; an
unrelated `StateError` (`removeMediaUrls`'s R2-migration-pending message) and
an ordinary total-failure `StateError` both still fall through to the
original generic message. Targeted `flutter analyze` on both changed/added
files: no issues. `git status`/`git diff --check`: only this one production
file and the one new test file changed, plus the known unrelated generated-
plugin-registrant drift; clean, no line-ending errors.

NOT PERFORMED: no Flutter real-device verification of this specific message
change; no Worker/Cloudflare change; no Supabase migration or mutation; no
cleanup of the seven failed `media_objects` rows (still present, still
awaiting an owner decision); no image-format/signature fix; no git add,
commit, or push.

NOW — superseded by the localization completion below.

NEXT — see the localization addendum's own NOW/NEXT.

### ADDENDUM — EN/AR LOCALIZATION OF THE PARTIAL-FAILURE MESSAGE (uncommitted)

A same-day follow-up review found that the correction above, while accurate,
returned a hard-coded English-only string with no path to Arabic — the
project's own `AGENTS.md` rule ("Do not hard-code production UI strings when
localization exists") was not actually satisfied, only reproduced against
existing technical debt in the same call path (the neighboring success/
validation toasts in this same viewmodel are equally hard-coded English and
remain untouched, out of scope). This addendum closes only the localization
gap for the one message this checkpoint introduced.

CORRECTION:
- One new key, `offerSavedMediaPartialFailure`, added to both
  `lib/src/common/localization/app_en.arb` and
  `lib/src/common/localization/app_ar.arb` (the project's manually-loaded
  JSON/ARB localization system — no code generation step exists or was
  needed). English: "The offer was saved, but one or more photos could not be
  uploaded. Edit the offer to retry." Arabic: "تم حفظ العرض، لكن تعذّر رفع صورة
  واحدة أو أكثر. يمكنك تعديل العرض لإعادة المحاولة."
- `CoreEntityErrorMessage.save` gained one new optional named parameter,
  `String Function(String key)? translate`, defaulting to `null`. It is
  consulted only inside the existing partial-upload branch; every other
  branch and every other existing caller (`add_watchmen_viewmodel.dart`,
  `add_requested_viewmodel.dart`, `add_owners_viewmodel.dart`,
  `add_offices_viewmodel.dart`, `add_brokers_viewmodel.dart` — none of which
  were modified) is unaffected, since an optional named parameter is
  backward-compatible and none of them pass it. When `translate` is `null`
  the exact previous English string is still returned, unchanged.
- `add_offers_viewmodel.dart`'s single `CoreEntityErrorMessage.save` call site
  now passes `context.mounted ? AppLocalizations.of(context).translate :
  null` — obtained only while the context is still valid, falling back to the
  existing English text otherwise. No other line in this file changed: Offer
  save ordering, persistence, media upload, navigation, and success handling
  are untouched, as is every other hard-coded string in the file.

STATIC TEST EVIDENCE: `test/common/core_entity_error_message_test.dart`
extended to 13/13 PASS, adding: the English-translator case, the
Arabic-translator case, the no-translator English-fallback case, and a case
proving a filesystem path / R2-object-key-shaped / signed-URL-query-shaped
fragment embedded in the underlying exception still cannot reach the
user-facing message; plus a new small group that reads both `.arb` files
directly from disk and asserts the new key exists, is valid JSON, and its
Arabic value differs from the English one. Targeted `flutter analyze` on all
four changed Dart files: no issues. `git diff --check`: clean. `git status`:
only the four approved production files plus the test file and this doc
changed, plus the known unrelated generated-plugin-registrant drift.

NOT PERFORMED: no Flutter real-device verification of either the message
text or its Arabic rendering; no Worker/Cloudflare change; no Supabase
mutation; no cleanup of the seven failed `media_objects` rows (still
retained); no image-format/signature fix (root cause remains unresolved); no
git add, commit, or push; no unrelated localization technical debt addressed.

NOW — superseded by the byte-signature correction below for the image-format
question specifically; the localization correction above is unaffected and
remains its own pending item.

NEXT — see the byte-signature correction's own NOW/NEXT.

---

## OFFER MEDIA — CLIENT-SIDE BYTE-SIGNATURE MIME DETECTION (uncommitted)

A follow-up, read-only diagnosis (commit `18eeb6a8...` was the baseline, and
was independently confirmed pushed via `git ls-remote` against the live
remote, not just owner-reported) traced the historical seven failed
production `media_objects` records to a proven source-level defect, distinct
from the message-mapping issue above: `R2OfferMediaUploadService` determined
the upload's Content-Type from the file name's extension only, never from
the file's actual bytes, while the Worker's `/offer-media/confirm` step
independently verifies the real byte signature and rejects any mismatch.
`image_picker`'s `imageQuality`/`maxWidth`/`maxHeight` options (already in use
for every camera/gallery pick) are documented to re-encode the file, which
can change its actual bytes while the temp file's extension is unrelated —
a plausible but **not independently proven** explanation for the seven
historical failures, since the Worker never persisted a rejection reason and
the original Samsung test files are not available on this machine (a
bounded, read-only search of local `Downloads`/`Pictures`/`Desktop` for files
matching the seven records' exact byte sizes found nothing).

CORRECTION (JPEG, PNG, WebP only — HEIC deliberately deferred, see below):
- New file `lib/src/services/image_signature_detector.dart`: a small,
  dependency-free, pure function that inspects a file's real leading bytes
  for the JPEG (`FF D8 FF`), PNG (8-byte signature), and WebP
  (`RIFF....WEBP`) container signatures — the same three physical formats
  the Worker's own `detectImageMimeFromBytes` already checks, written
  independently rather than transliterated from the Worker's JavaScript.
  Returns `null` for anything else or for too few bytes; never decodes the
  image data past the signature and never reads a file name.
- `lib/src/services/r2_offer_media_upload_service.dart`:
  `_contentTypeForFileName(path)` (extension-only) replaced by
  `_resolveContentType(path, bytes)`, called with the same `bytes` already
  read once by `uploadOfferMediaFile` — no second file read. It uses the
  detector's answer as the authoritative Content-Type sent to both
  `/offer-media/authorize` and the signed PUT's `Content-Type` header, so
  they can no longer disagree with the file's real bytes or with each other.
  Object-key generation is unaffected: verified from `worker.js` that
  `offerObjectKey`'s extension is derived entirely from the `contentType`
  field the client sends, never from the original file name, so a more
  accurate detected type produces a correctly-matching object key
  automatically, with no separate consistency fix needed.
- **HEIC is an explicit, deliberate exception, not an oversight.** The new
  byte detector does not recognize HEIC signatures (out of scope for this
  checkpoint, and HEIC/HEIF conversion was explicitly excluded). Extending it
  would have silently changed behavior for a format whose *display* — not
  just upload — is separately unproven (`CachedNetworkImage`'s underlying
  Skia decoders have no built-in HEIC support on Android). To avoid
  regressing currently-accepted HEIC uploads, `_resolveContentType` falls
  back to the exact previous extension-trusted classification for `.heic`
  files only, byte-for-byte unchanged from before this checkpoint. This is
  flagged as a deliberately deferred decision, not a silent gap: a dedicated
  HEIC/HEIF checkpoint (covering both upload and guaranteed display) needs
  its own explicit owner approval.
- Every other Offer Media behavior — the 10 MiB limit
  (`R2OfferMediaUploadService.maxImageBytes`, unchanged), authorization,
  ownership checks, Create/Edit persistence ordering, the partial-failure
  message correction above, EN/AR localization, image picker settings, and
  no re-encoding of JPEG/PNG/WebP bytes — is untouched.

STATIC TEST EVIDENCE: two new files, 17/17 PASS.
`test/services/image_signature_detector_test.dart` (8 tests) proves correct
detection against **real, decodable** JPEG/PNG/WebP bytes generated at test
time with the already-present `package:image` (no new dependency), plus
null-safe rejection of unknown/empty/too-short/RIFF-but-not-WebP input.
`test/services/r2_offer_media_upload_service_test.dart` (9 tests), using a
real `SupabaseClient` with a locally-set session (the same
`setInitialSession` seam already used by
`test/auth/phone_verification_test.dart` — no new dependency, no mocking
library) and an injected `http.MockClient` (the constructor's pre-existing
`httpClient` parameter), proves: a `.jpg`-named file with real PNG bytes is
sent as `image/png` and vice versa for `.webp`/JPEG; unrecognized bytes are
rejected before any HTTP request is made at all; the rejection message is
the fixed string `'Unsupported offer image type.'`, containing neither the
file's real path nor its byte content; the detected MIME is identical on
both the authorize call and the PUT's `Content-Type` header; the original
byte length is unchanged through both; the 10 MiB constant is unchanged; a
`.heic` file is still declared `image/heic` regardless of its actual bytes,
proving the no-regression guarantee; and a full authorize → PUT → confirm
round trip still succeeds for a genuinely valid JPEG. Targeted `flutter
analyze` on all four changed/added Dart files: no issues. `git diff --check`:
clean (only the known unrelated generated-plugin-registrant line-ending
drift).

NOT PERFORMED: no Worker change (the Worker's own byte-signature check is
unmodified and unweakened — this correction makes the client agree with it,
not the other way around); no Cloudflare deployment or logging change; no
Supabase mutation; no cleanup of the seven failed `media_objects` rows (still
retained, cause still not independently proven); no HEIC/HEIF conversion or
whitelist expansion; no image picker/compression change; no real-device
upload, Samsung or otherwise; no git add, commit, or push.

NOW — nothing further is pending on this byte-signature correction itself;
it remains uncommitted, alongside the still-uncommitted localization
correction above, pending owner review of both.

NEXT — owner decision on HEIC/HEIF (convert to JPEG for guaranteed display,
or verify decode/display compatibility before deciding), then real-device
acceptance covering ordinary phone photos in both Create and Edit before any
claim of production readiness for Offer Media images.
