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

NOW — superseded for the display/crash question specifically by the
correction below; unaffected otherwise.

NEXT — see the correction below's own NOW/NEXT.

---

## OFFER MEDIA — DETAILS CRASH + STALE-MEDIA DISPLAY CORRECTION (uncommitted)

A real-device (Samsung) report, investigated read-only in the prior
checkpoint, found: the previously-verified ready JPEG never appeared in
Offer Details; a newly created Offer's image (independently reconciled
hosted as `ready`, correctly associated, in the production bucket) also
never appeared; and a Flutter red-screen crash: `type 'Null' is not a
subtype of type 'OfferModel' in type cast`. This checkpoint corrects both a
strongly-supported crash defect and a source-proven display defect,
distinct root causes in two different files.

CRASH DEFECT (source-proven): the `/offers-details` `GoRoute` in
`lib/app.dart` did `state.extra as OfferModel` — a mandatory, non-nullable
cast. GoRouter's `extra` is a transient in-memory value that is not restored
across a killed-process restart or a route rebuilt without it, and this
route carries no `:id` to fall back on (unlike `/offers-details-by-id/:id`).
Grepping the full codebase for `as OfferModel` found this to be the *only*
non-nullable instance tied to `state.extra`; every sibling Add-screen route
already used the safe `as OfferModel?` form. The exact device stack trace
was never obtained, so this is reported as strongly supported, not
absolutely proven.

DISPLAY DEFECT (source-proven, independent of the crash): every normal
navigation to Offer Details (list, search, map, favorites, match-details —
seven call sites, all `context.push('/offers-details', extra: offer)`)
passes an `OfferModel` sourced from the bulk list fetch, which deliberately
never populates `mediaUrls` (to avoid an unbounded per-offer Worker
fan-out — a documented, unchanged tradeoff). `OffersDetailsView.initState`
only ever refreshed that data via `_refreshOfferData()` (which does call the
correct `OfferService.getOffer(id)`, itself unmodified and already
production-verified to return real signed media), and that refresh was
wired *only* to `FastMediaUploadService.onUploadCompleted` — a legacy
Firebase-only event stream the current Supabase/R2 upload path never
publishes. Under Supabase mode (the default), the refresh essentially never
fired on a normal open, so real, `ready`, correctly-associated media stayed
invisible.

CORRECTION — two files, two independent fixes, no shared logic changed:

- `lib/app.dart`: the `/offers-details` route's inline builder closure was
  extracted, unchanged in behavior except for the cast, into a new public
  top-level function `buildOffersDetailsRoute(context, state)` (public
  specifically so a test can call the real production logic rather than a
  reimplementation of it). `state.extra as OfferModel` became
  `state.extra as OfferModel?`; when `null`, it returns a small "Offer not
  found" fallback `Scaffold` (mirroring the existing equivalent fallback
  already used by `_OfferDetailsLoader` for the same concept) with a "Go
  Back" button that calls `context.go('/home')` — a single one-shot absolute
  navigation to an already-elsewhere-proven-safe destination, not a
  redirect, so there is no redirect-loop risk. No fake `OfferModel` is ever
  constructed. No other route, no auth `redirect:` guard, and no other
  builder changed.
- `lib/src/views/Screens/ViewDetails/offers_view_details.dart`:
  `initState()` gained exactly one added line, an unconditional call to the
  existing `_refreshOfferData()` (itself untouched — already correctly
  guarded by `if (_currentOffer.id == null) return;` and
  `if (updatedOffer != null && mounted)` before its `setState`, and already
  invalidates `_cachedMediaGallery`/`_cachedMapWidget` so the rebuilt screen
  picks up real media through the unmodified `OptimizedMediaGalleryWidget`,
  which itself already tolerates a `null` `pageController` by creating its
  own). The pre-existing Firebase-event listener was deliberately left in
  place, not removed, since removing it was not necessary or proven safe to
  do within this scope. No other line in this file changed: layout, theme,
  EN/AR, RTL, and every other behavior are untouched.

INCIDENTAL FINDING, NOT FIXED, OUT OF SCOPE: while constructing a test
fixture, `_buildCachedMiniMap` in `offers_view_details.dart` was found to
call `_currentOffer.pickUpLatitude!`/`pickUpLongitude!` (forced non-null)
with no presence guard anywhere in that file or its caller — a *separate,
pre-existing* crash risk for any Offer with no pickup location set,
unrelated to the two defects this checkpoint addresses. Reported for a
future, separately-approved checkpoint; not touched here.

TEST EVIDENCE AND ITS LIMITS: new `test/app/offers_details_route_test.dart`,
2/2 PASS, exercising the *actual* `buildOffersDetailsRoute` function (not a
reimplementation) through a minimal real `GoRouter`: navigating to
`/offers-details` with no `extra` no longer throws the null-cast exception
and shows the safe fallback instead of crashing; tapping "Go Back" reaches
`/home` with no exception and without looping back to the fallback. **The
valid-`OfferModel` branch (`OffersDetailsView` itself, and therefore the new
`_refreshOfferData()` call and every item D–J of the originally-requested
test plan) could not be exercised in a widget test within this checkpoint's
two-file approved scope.** Confirmed empirically, not assumed: pumping
`OffersDetailsView` throws `"You must initialize the supabase instance
before calling Supabase.instance"` from inside its own `initState` chain
(`OfferService`/`SupabaseCoreEntitiesService` and, separately,
`OptimisticFavoritesService`/`FavoriteService` each construct their real
Supabase-backed dependency internally with no injectable seam), and the
screen also builds a `GoogleMap` unconditionally, which needs platform-view
mocking unrelated to this fix. Making that path testable would require
adding dependency injection to `offer_service.dart` and/or
`optimistic_favorites_service.dart` — both outside the two approved files —
so this was reported rather than forced. Static source verification (traced
by hand, not test-executed) is the basis for confidence in the
`_refreshOfferData()` call's correctness instead.

Targeted `flutter analyze` on all three changed/added files: no issues.
`git diff --check`: clean. No existing test file references
`offers-details`, `OffersDetailsView`, or `buildOffersDetailsRoute`, so none
was directly affected by this change; the full suite was not rerun.

NOT PERFORMED: no real-device verification of either fix; no installed-build
provenance established; no Worker, Supabase, or R2 change; no cleanup of the
seven historical failed `media_objects` rows (still retained); no HEIC/HEIF
work; no new Offer creation or upload; no git add, commit, or push.

NOW — superseded by the localization addendum immediately below for the
fallback-string question specifically; unaffected otherwise.

NEXT — see the addendum's own NOW/NEXT.

### ADDENDUM — NULL-EXTRA FALLBACK LOCALIZATION (uncommitted)

A pre-build review found the null-extra fallback added above used two
hard-coded English strings, `'Offer not found'` and `'Go Back'`, despite
`AGENTS.md`'s existing-localization rule — and, unlike earlier cases in this
project, this was not a gap requiring a new key: both `offerNotFound` and
`goBack` already existed as fully translated EN/AR keys in
`app_en.arb`/`app_ar.arb`, each already in live use elsewhere (`goBack` in
`pdf_viewer_screen.dart`; `offerNotFound`, for the identical "an Offer could
not be resolved" concept, in `match_details_view.dart`). No ARB change was
needed or made.

CORRECTION: `lib/app.dart`'s `buildOffersDetailsRoute` now reads
`AppLocalizations.of(context).translate('offerNotFound')` and
`translate('goBack')` in place of the two literals. No other line changed.

TEST EVIDENCE: `test/app/offers_details_route_test.dart` extended to 3/3
PASS, now wrapping the test `MaterialApp.router` with the same
`localizationsDelegates`/`supportedLocales` the real app uses, and asserting
against the real, decoded ARB text — not the source key names — in both
locales: with `Locale('en')` the fallback shows "Offer not found"/"Go Back";
with `Locale('ar')` it shows "العرض غير موجود"/"رجوع" and the English text is
absent. This proves the strings are genuinely resolved per-locale through
the real localization pipeline, not merely present as literals. Targeted
`flutter analyze` on both changed files: no issues. `git diff --check`:
clean.

NOW — superseded for the reopen-performance question specifically by the
correction below; unaffected otherwise.

NEXT — see the correction below's own NOW/NEXT.

### ADDENDUM — DEVICE ACCEPTANCE AND REOPEN-PERFORMANCE CORRECTION (uncommitted)

Owner-executed Debug device acceptance (Debug build, matched to the
already-installed app's Android Debug signing certificate — the restored
Release keystore's certificate does not match the installed app and was
correctly not used) confirmed on Samsung: both previously-blocked Offer
images (the existing ready JPEG and the newly-created Offer's JPEG) now
display, and remain visible after leaving and reopening. The owner then
observed a new, distinct issue: every open, and every reopen of the same
Offer, shows a visible ~1-2 second delay before the image appears.

ROOT CAUSE (source-proven): `_refreshOfferData()` (added by the prior
checkpoint) calls `OfferService.getOffer(id)` on every `initState`, which
calls the Worker's `/offer-media` list route
(`R2OfferMediaUploadService.getOfferMedia`), which mints a **brand-new**
signed GET URL for the same underlying R2 object on every single call (by
design — signed URLs must be short-lived). The gallery widget
(`media_gallery_widget.dart`) renders each image via
`OfflineMediaService.buildOfflineAwareImage(imageUrl: mediaItem.url, ...)`
without passing that method's own `cacheKey` parameter, so — as that
method's own doc comment states — it falls back to `CachedNetworkImage`'s
default URL-keyed cache. Since the URL string is different on every open
(same bytes, different signature), every open is a guaranteed cache miss
and a full re-download, even seconds after the previous identical view.

THE PROVEN, COMPLETE FIX IS OUT OF THIS CHECKPOINT'S APPROVED SCOPE.
`OfflineMediaService.buildOfflineAwareImage`'s `cacheKey` parameter already
exists and is already used successfully for exactly this problem by Profile
Media (keyed on the stable `profile_media_id`), per its own doc comment.
Wiring the equivalent for Offer Media requires: `media_gallery_widget.dart`
to pass a stable per-item `cacheKey` (not approved here); and, further back,
a stable id per media item threaded from `SupabaseCoreEntitiesService`
(`_fetchOfferMediaDisplayUrls` currently discards `R2OfferMediaItem
.mediaObjectId` and keeps only `.url`) through `OfferModel.mediaUrls`
(currently `List<String>`, URLs only) to that widget — touching
`offer_service.dart`/`supabase_core_entities_service.dart` and possibly
`offers_model.dart`, none of which are in this checkpoint's approved file
list. **This is reported, not implemented, per instructions to stop and
report rather than expand scope.**

INTERIM CORRECTION IMPLEMENTED (within the one approved file only):
`lib/src/views/Screens/ViewDetails/offers_view_details.dart` gained a
process-lifetime, in-memory-only cache (`_recentOfferCache`, a
`static final Map<String, _RecentOfferSnapshot>`) of each Offer's last
successfully fetched, fully-resolved state, with a 60-second TTL —
deliberately far shorter than the signed GET's own server-side TTL, so a
cache hit here can never serve a URL past its real expiry. `initState` now
checks this cache before deciding whether to call `_refreshOfferData()` at
all: a hit within the last 60 seconds reuses the exact same previously
resolved `OfferModel` (same media URL strings), so
`CachedNetworkImage`'s existing URL-keyed cache correctly hits and no
network round trip or re-download happens; a miss (first open, or a reopen
after 60+ seconds) behaves exactly as before. This is a narrower, fully
in-scope mitigation for the specific "leave and immediately reopen" pattern
the owner tested — not the general architectural fix above.

Safety preserved: nothing is written to disk or Supabase (process-memory
only, cleared on app restart); no signed URL is ever reused past its own
real validity (60s cache vs. minutes-long server TTL); cross-account safety
needs no extra clearing logic, since a cache entry is only ever looked up
by the exact Offer id a screen was opened with, and RLS already prevents a
different account from ever fetching an id that isn't theirs. A media
change made via Edit's own pop-with-fresh-data path bypasses this cache
entirely (unaffected); a change made through some other path within the
same 60-second window as a very recent view could show cached-but-was-
correct-at-fetch-time data for up to 60 seconds — a bounded, disclosed
tradeoff, not indefinite staleness.

TEST EVIDENCE AND ITS LIMITS: targeted `flutter analyze` on the changed
file: no issues. `git diff --check`: clean. **No new automated test was
added for this specific logic** — `_recentOfferCache`/
`_applyRecentOfferCacheIfFresh` are private to this file, and the same
testability blocker already disclosed in the prior checkpoint (pumping
`OffersDetailsView` requires an initialized `Supabase.instance` and
`OptimisticFavoritesService`'s real `FavoriteService`, neither injectable
within this file alone, plus an unconditionally-built `GoogleMap`) applies
identically here. Verification is by manual code review
(CODE_PROVEN only) plus the real-device Debug acceptance below
(functional, not Release-performance, evidence).

DEVICE ACCEPTANCE: a Debug build from this exact source tree (HEAD
`005b819...` plus all four uncommitted corrections) was built and installed
as an update on Samsung `R5CY10YYLSM`, pre-verified matching package id,
matching signing certificate, matching versionCode, and confirmed via
`firstInstallTime` staying unchanged post-install that existing app data
was preserved (not a fresh install). Awaiting the owner's timed
before/after observation of the specific reopen-delay scenario on this
build; not yet recorded as PASS.

NOW — nothing further pending on this correction itself; it remains
uncommitted alongside the other three corrections, pending owner device
observation of the reopen-delay improvement specifically.

NEXT — owner confirmation of perceived (and where possible timed)
before/after reopen delay for both Offers on the installed Debug build; if
still too slow after this interim fix, the properly-scoped stable-
`cacheKey` fix above (three additional files) becomes its own separately
approved checkpoint. Debug-mode timing does not establish Release-build
performance.

---

## OFFER DETAILS "OFFER NOT FOUND" ON STARTUP — INVESTIGATION, ROOT CAUSE UNPROVEN, NO FIX APPLIED

A new owner-reported symptom, distinct from the crash the null-extra
fallback was built for: "normal application startup" sometimes lands
directly on that same localized "Offer not found" fallback rather than a
crash. This checkpoint traced the complete startup/navigation path and
**could not establish a proven root cause** — per this project's own
protocol, no speculative fix was implemented.

MECHANISMS TRACED AND RULED OUT, EACH WITH SPECIFIC EVIDENCE:

1. **`resolveAuthRedirect` targeting `/offers-details`** — read its full
   body (`lib/app.dart`). No branch can ever return `/offers-details`; the
   only redirect targets are `/`, `/welcome`, `/home`, `/sign-in`, and the
   password-recovery route. `initialLocation` is always `/`. A normal cold
   start therefore cannot land on `/offers-details` through this function
   at all.
2. **Flutter/Android state restoration** — `grep`'d the full `app.dart`:
   no `restorationScopeId` is set on `MaterialApp.router` or `GoRouter`, so
   Flutter's own navigator-restoration feature is inactive.
   `android/app/.../MainActivity.kt` does not override
   `shouldRestoreAndroidState()` (default `false`), and this project's own
   prior, already-verified finding (Password checkpoint) established
   `flutter_deeplinking_enabled` is `false` on Android — platform deep
   links, and by extension any OS-level "restore this URI" mechanism, are
   not fed into Flutter navigation here.
3. **Push/local notification taps** — traced
   `NotificationService._handleOpenedRemoteMessage` and the local-
   notification response handler: both only `add()` to
   `notificationTapStream`. Grepped the entire `lib/` tree for any listener
   of that stream: **there is none** — tapping a notification (terminated-
   app launch via `getInitialMessage`, or background-tap via
   `onMessageOpenedApp`) currently triggers no navigation at all under
   Supabase mode. This rules notifications out as this defect's cause (and
   is itself a separate, pre-existing gap — reported, not fixed, out of
   this checkpoint's scope).
4. **`refreshListenable`-triggered `redirect()` re-evaluation losing
   `extra` while already viewing Offer Details** — the most plausible
   remaining hypothesis (`AuthViewModel`/`PasswordRecoveryViewModel` firing
   `notifyListeners()`, e.g. on an app-resume session re-check, while the
   user sits on `/offers-details`) — **tested empirically with real
   go_router code**, `test/app/redirect_refresh_preserves_extra_test.dart`,
   using the exact same wiring shape as `_createRouter`
   (`refreshListenable` + `redirect: (...) => null` for an unaffected
   route). Result: the route's builder is invoked again (proving the
   rebuild genuinely happens), but **`state.extra` is preserved correctly
   across it, both times**. This mechanism is empirically ruled out.

Every call site that pushes `/offers-details` (list, search, map,
favorites, match-details — seven sites, rechecked) passes a non-null
`extra` at the call itself. The one existing ID-based route,
`/offers-details-by-id/:id` via `_OfferDetailsLoader`, is unaffected by any
of this and remains the safe, already-correct pattern for identity-only
navigation.

**ROOT CAUSE: UNKNOWN.** No implementation was made. `lib/main.dart`,
`lib/app.dart`, and `offers_view_details.dart` are unchanged from the
previous checkpoint (verified: this checkpoint's `git diff` touches no
production file).

MISSING EVIDENCE NEEDED TO PROCEED: the owner's exact sequence immediately
before the fallback appeared — specifically whether it followed (a)
tapping the Samsung launcher icon after a genuine force-stop/kill, (b)
tapping the app's card in the Android Recents/multitasking switcher after
the OS silently killed it in the background (Samsung's background-app
management is known to be aggressive), or (c) some other action. If
reproducible, the exact minimal capture needed is a narrowly filtered
`adb logcat` (filtered to this app's own tag/PID only, no broad device log)
taken at the moment the fallback appears, which would show whether the
Dart process actually restarted (a fresh `main()` log line) or merely
resumed.

TEST EVIDENCE: new `test/app/redirect_refresh_preserves_extra_test.dart`,
1/1 PASS (proves one specific hypothesis safe, not a fix). Existing
`test/app/offers_details_route_test.dart`, still 3/3 PASS, rerun for
confidence after the new file was added alongside it. Targeted `flutter
analyze` on the new test file: no issues. `git diff --check`: clean. No
production file in the diff.

NOT PERFORMED: no source fix (none proven necessary or safe); no build; no
install; no device test for this specific symptom; no git add, commit, or
push.

NOW — this investigation is complete for what source and empirical
go_router evidence can establish; the actual trigger remains unproven.

NEXT — superseded by the real-device follow-up below.

### ADDENDUM — REAL-DEVICE REPRODUCTION ATTEMPTS + TEMPORARY DIAGNOSTIC BUILD (uncommitted)

Performed three genuine, physical-equivalent reproduction attempts on the
connected Samsung `R5CY10YYLSM` via `adb` (not source reasoning), each
verified by device screenshot and a real process-id change:

1. **Force-stop, then launcher-icon tap** (`am force-stop` +
   `monkey -c android.intent.category.LAUNCHER`): lands correctly on Home.
   Screenshot evidence captured.
2. **Background (Home key) + `am kill`** (kills the background process
   while preserving its Recents task/snapshot — the closest safe adb
   equivalent to Samsung's own aggressive background memory reclaim), then
   resuming via tapping the app's card in the Recents/multitasking
   switcher: a genuinely new process (`pidof` confirmed a different PID)
   is created, and it **also** lands correctly on Home — not on the
   "Offer not found" fallback, and not a repeat of the previously-viewed
   Offer either (a separate, milder UX gap: the user's last-viewed screen
   is not restored, but nothing incorrect or unsafe is shown).
3. **Background + `am kill`, then resume via the launcher icon instead of
   Recents** (task still present): same result — Home, new PID confirmed.

**None of the three reproduced the reported fallback.** This is new
evidence beyond the prior source-only investigation, and it further rules
out the most obvious "kill the process while viewing Offer Details" shapes
of the problem, in addition to the previously-established source and
automated-test evidence (`resolveAuthRedirect` cannot target
`/offers-details`; no Flutter/Android restoration is configured; no
listener consumes `notificationTapStream`; `redirect()` re-evaluation
empirically preserves `extra`).

**ROOT CAUSE REMAINS UNKNOWN.** Given the owner's explicit request for
real evidence rather than another inconclusive report, a temporary,
narrowly-scoped, DEBUG-ONLY diagnostic was added (per this checkpoint's own
explicit authorization) rather than stopping again with no path forward:

- `lib/main.dart`: one `debugPrint` at the very start of
  `initializeAppServices()`, gated by `kDebugMode`, logging only a fixed
  marker and a timestamp — proves whether a fresh Dart isolate/process
  actually started.
- `lib/app.dart`: one `debugPrint` at the top of `resolveAuthRedirect`,
  gated by `kDebugMode`, logging only the route path template, the
  `AuthStatus` category, and the recovery-active flag — never an id, token,
  or full query string. This directly answers whether this function is
  ever invoked with `currentPath == '/offers-details'` at all, and what
  auth state it saw when it was.
- `lib/app.dart`: one `debugPrint` at the top of `buildOffersDetailsRoute`,
  gated by `kDebugMode`, logging only whether `extra` was present and the
  bare path template — never the Offer's own data.

All three are marked `TEMPORARY DIAGNOSTIC — remove before finalizing this
checkpoint` in source and must be removed once the real trigger is
captured.

BUILD: a new Debug APK was built from this exact source tree. Verified
before requesting installation: certificate `SHA-256:
6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` and
package/version (`com.example.broker_wallet`, versionCode 1) both match the
currently-installed app exactly — an update-compatible build, not
installed yet.

TEST EVIDENCE: `test/app/` re-run in full after adding the instrumentation,
4/4 PASS (the diagnostic prints themselves are visible in the test output,
confirming they fire correctly and add no behavioral change). Targeted
`flutter analyze` on `lib/main.dart` and `lib/app.dart`: no issues (two
missing `package:flutter/foundation.dart` imports were the only fix
needed). `git diff --check`: clean.

NOT PERFORMED: installation (awaiting explicit owner approval, per this
checkpoint's own instructions); removal of the diagnostic prints (deferred
until they have actually captured the real trigger); any change to auth,
recovery, deletion, or Offer media logic; git add, commit, or push.

NOW — a verified, update-compatible diagnostic Debug build is ready but not
installed.

NEXT — owner approval to install this diagnostic build, then ordinary daily
use (or a deliberate attempt to reproduce the original sequence the owner
remembers) until the fallback reappears, at which point `adb logcat`
filtered to this app's process should be captured immediately — the three
`[NAV_DIAG]` lines will show whether `main()` actually restarted and
exactly what `resolveAuthRedirect` saw. Once captured, the diagnostic
prints are removed as part of implementing the now-evidence-based fix.

### ADDENDUM — INDEPENDENT ROUTE-CONTRACT REVIEW: SCOPE BLOCKER

An independent review at the same branch/HEAD (`feature/offer-private-media`,
`005b819d33a7c5da6eff709b580cf6171db8cd15`) confirmed a demonstrable defect
separate from the still-unknown Samsung trigger: `/offers-details` has no
stable Offer identity and therefore cannot distinguish "the route has no
required argument" from "an identified Offer does not exist or is
inaccessible." Its null-`extra` branch currently presents the latter error
for the former condition. The existing `/offers-details-by-id/:id` route is
the correct identity-bearing shape, and `SupabaseCoreEntitiesService.getOffer`
already scopes the read to the canonical authenticated owner id before
returning data, so no RLS or backend change is needed.

The complete safe correction was **not implemented**, because it requires one
minimal change in a production file this checkpoint explicitly marked
read-only: `lib/src/views/Screens/ViewDetails/offers_view_details.dart`.
`_OfferDetailsLoader` already calls `OfferService.getOffer(id)` before it
constructs `OffersDetailsView`; the view's current `initState()` then calls
`_refreshOfferData()`, which invokes the same authoritative read again. Moving
all seven in-app entry points to the ID route without an "already resolved"
handoff would therefore introduce/retain an unnecessary duplicate details
fetch, renew the signed media URL twice, and violate this checkpoint's own
acceptance requirement. There is no seam in `lib/app.dart` that can suppress
the second call safely without fabricating an `OfferModel` or duplicating the
details UI.

MINIMAL ADDITIONAL SCOPE REQUIRED: authorize only a constructor flag (or
equivalent narrowly-scoped signal) in
`lib/src/views/Screens/ViewDetails/offers_view_details.dart` allowing the
ID-loader's already-authoritative result to skip the view's initial refresh.
Ordinary list/search/map/favorites navigation may still pass its existing
lightweight model as `extra` alongside the stable ID and perform exactly one
authoritative refresh; an ID-only restoration/deep link performs exactly one
loader fetch and passes the result as already resolved. No service,
repository, Supabase, RLS, media-cache, UI-layout, localization, Android, or
dependency change is required.

After that approval, the scoped implementation is: make both Offer Details
routes protected by the existing auth/recovery/deletion authority; convert the
legacy no-ID route into a compatibility redirect that uses a non-empty ID from
a valid `OfferModel` or returns to the root bootstrap gate when identity is
absent; make `/offers-details-by-id/:id` canonical; ignore a mismatched
`extra` rather than displaying the wrong Offer; update only the seven Offer
navigation calls to use the encoded stable ID; localize the existing ID
loader's not-found state with the already-present keys; remove all temporary
`NAV_DIAG` instrumentation; and add focused route/loader tests including a
single-fetch assertion.

ORIGINAL RUNTIME TRIGGER: **UNKNOWN** — unchanged. No new device reproduction,
build, install, Supabase mutation, source implementation, staging, commit, or
push was performed in this review. Temporary diagnostics remain in place
because production finalization did not occur.

NOW — request explicit approval for the one-file scope expansion above.

NEXT — after approval, implement and run only the scoped route regression
tests, directly affected auth/recovery/deletion tests, focused analysis, and
`git diff --check`; then inspect the complete exact diff before any build or
installation decision.

### ADDENDUM — ID-BASED OFFER DETAILS ROUTE CONTRACT IMPLEMENTED (uncommitted)

Owner approval was received for the one-file scope expansion identified
above. The proven route-contract defect is now corrected locally; the exact
intermittent Samsung event that originally exposed it remains **UNKNOWN**.

ROUTE CONTRACT: `/offers-details-by-id/:id` is now canonical and both Offer
Details paths are protected by the existing single auth redirect authority.
The former `/offers-details` path is retained only as a compatibility
redirect: a valid `OfferModel` is used solely to recover its non-empty ID and
redirect to the canonical path; missing/wrong/malformed route data returns to
the root bootstrap gate, where the existing authenticated, signed-out,
password-recovery, and account-deletion states choose the destination. It no
longer renders "Offer not found" merely because route identity is absent.

All seven in-app entry points now put the encoded Offer ID in the location:
`compact_offer_card.dart`, `filtered_tiles.dart`, `offers_list_view.dart`,
`map_view.dart`, `search_view.dart`, `favorites_card.dart`, and
`match_details_view.dart`. List/search/favorites/match call sites may still
carry their existing model as an optional render optimization, but the
canonical builder accepts it only when its ID exactly equals the path ID and
never treats it as fully resolved. Missing or mismatched extras use the ID
loader, so losing transient `extra` no longer loses Offer identity and a wrong
Offer cannot be displayed. The map no longer performs a details fetch before
navigating; the canonical loader owns that one fetch.

SINGLE-FETCH CONTRACT: `OfferDetailsLoader` still uses the existing
`OfferService.getOffer(id)` authorized service path and rejects an empty ID,
errors/null results, and even a mismatched returned model safely. Its trusted
result is passed to `OffersDetailsView(initialOfferIsResolved: true)`, which
skips only the redundant initial refresh. Ordinary list models keep the
default `false` and still perform the authoritative details/media refresh (or
reuse the existing fresh 60-second snapshot). Loader-resolved data is placed
into that same existing 60-second in-memory cache; the TTL, signed-URL policy,
gallery, later upload-completion refresh listener, and explicit refresh method
are unchanged. The loader's not-found UI now uses the already-existing EN/AR
localization keys.

AUTH/SECURITY: no competing guard was added. Unknown bootstrap still returns
to `/`; signed-out protected navigation still returns to `/welcome`;
authenticated root still resolves directly to `/home`; password recovery is
still evaluated first; account-deletion quarantine continues to hold
`AuthStatus.unknown`. The underlying Supabase read remains owner-scoped and no
RLS, database, Worker, R2, media-service, or auth implementation changed.

TEMPORARY DIAGNOSTICS: all `[NAV_DIAG]` code and its temporary imports were
removed from `lib/main.dart` and `lib/app.dart`. `lib/main.dart` therefore has
no remaining diff from HEAD.

TEST EVIDENCE:

- `flutter test test/app/offers_details_route_test.dart
  test/app/redirect_refresh_preserves_extra_test.dart`: **14/14 PASS**.
  Covers missing legacy identity versus confirmed not-found, legacy-ID
  compatibility without loops, valid loader result and exactly one loader
  call, empty/malformed ID without a service call, null/inaccessible/error
  results, mismatched-result refusal, resolved-versus-list initial-refresh
  decisions, path-ID/extra matching, startup/auth/recovery routing, and all
  seven call-site source contracts.
- `flutter test test/auth/navigation_authority_test.dart
  test/auth/password_recovery_test.dart`: **52/52 PASS**, including the live
  router no-Welcome-flash and recovery-quarantine contracts. Per scope, no
  destructive account-deletion test was run.
- Focused `flutter analyze` on `app.dart`, `main.dart`, Offer Details, and the
  two app tests: **PASS — no issues**. The broader check including every
  changed call-site file reported only four pre-existing deprecation infos at
  untouched lines in Map/Search; no new error or warning was introduced.
- `git diff --check`: **PASS**; only known CRLF notices.

BUILD: one Debug APK was built successfully from branch
`feature/offer-private-media`, HEAD
`005b819d33a7c5da6eff709b580cf6171db8cd15`, plus the preserved uncommitted
working tree. Verified package `com.example.broker_wallet`, versionCode `1`,
versionName `1.0.0`; its signing certificate matches the currently installed
Samsung app and its versionCode is update-compatible. APK SHA-256:
`12E61D994116349B0186EC29405020409E739B27E130CA75ADEF57758D64BD88`.
The APK was **not installed**.

STATUS: **LOCAL IMPLEMENTATION PASS / CODE_PROVEN**. This is not
VERIFIED_REAL_DEVICE. Existing JPEG/media display is preserved by source and
regression evidence only until the owner completes Samsung acceptance.

NOW — request explicit owner approval to update-install the verified Debug APK
on Samsung `R5CY10YYLSM` without uninstalling or clearing app data.

NEXT — after installation approval, the owner performs the defined startup,
Recents, Offer A/B image, reopen, and return-to-Details acceptance sequence;
record VERIFIED_REAL_DEVICE only after the owner reports the result.

### ADDENDUM — CORRECTED DEBUG APK INSTALLED; DEVICE ACCEPTANCE PENDING

Owner approval was received to update-install the corrected Debug APK on
Samsung `R5CY10YYLSM`. Pre-install checks passed: the APK hash still matched
the build recorded above, no approved production source file was newer than
the APK, package id was `com.example.broker_wallet`, built and installed
versionCode were both `1`, and the signing certificate matched the installed
application. Installation used `adb install -r` only — no uninstall, clear,
downgrade, signing change, or data operation.

Post-install read-back confirmed the device's installed base APK is byte-for-
byte the verified build (SHA-256
`12E61D994116349B0186EC29405020409E739B27E130CA75ADEF57758D64BD88`) and its
signing certificate still matches. `firstInstallTime` remained unchanged while
`lastUpdateTime` advanced, proving an in-place, data-preserving update rather
than a fresh installation.

STATUS: **INSTALLED_VERIFIED**. Real-device behavior is deliberately still
**PENDING** until the owner reports the defined startup, Offer A/B image,
reopen, background/return, and second force-stop/launch observations.

NOW — owner performs the six manual Samsung acceptance steps supplied in the
installation handoff.

NEXT — record VERIFIED_REAL_DEVICE only if the owner's actual observations
confirm every required result; otherwise capture the exact failing step
without beginning image-cache work.

---

## OFFER MEDIA — STABLE CACHE-IDENTITY CORRECTION (uncommitted)

Corrects the reopen-delay root cause this checkpoint's own prior addendum
("DEVICE ACCEPTANCE AND REOPEN-PERFORMANCE CORRECTION") proved but explicitly
left out of scope: every Offer Details open — including after an app
restart — re-downloaded the same image bytes, because
`_buildOptimizedImageViewer` never passed `OfflineMediaService
.buildOfflineAwareImage`'s existing `cacheKey` parameter, so the widget fell
back to `CachedNetworkImage`'s default URL-keyed cache. The Worker mints a
brand-new signed GET URL for the same R2 object on every `/offer-media` call
(by design — signed URLs must stay short-lived), so the URL string never
repeats and every open was a guaranteed cache miss, independent of the
existing 60-second `_recentOfferCache` in `offers_view_details.dart`, which
only ever mitigated a fetch *within* its own 60-second window and cannot
survive process death.

ROOT CAUSE: PROVEN from source, traced end to end: `OffersDetailsView
._refreshOfferData()` → `OfferService.getOffer(id)` →
`SupabaseCoreEntitiesService.getOffer(id)` → `_fetchOfferMediaDisplayUrls(id)`
→ `R2OfferMediaUploadService.getOfferMedia(offerId)`. The Worker/service layer
already returns `R2OfferMediaItem.mediaObjectId` — the durable
`media_objects.id` behind the URL — but `_fetchOfferMediaDisplayUrls` kept
only `.url`, discarding the one stable identity that could have keyed the
image cache. This is the exact mechanism, already production-verified for
profile images (`CurrentUserAvatar` passing `cacheKey: image.mediaId`, keyed
on `profile_media_id`), that this checkpoint's prior addendum identified as
the correct, complete fix and explicitly deferred as out of its approved
scope.

STABLE MEDIA IDENTITY: `mediaObjectId` (`media_objects.id`), already returned
by the Worker's `/offer-media` route — no new database column, no schema
change. Offer media upload is append-only today (no client path replaces or
deletes an existing item), so a `mediaObjectId`'s bytes never change once
confirmed, matching the same immutability assumption already accepted for
`profile_media_id` (a replacement there also always mints a new id). This is
an explicit, disclosed assumption tied to today's upload contract, not a new
guarantee invented for this fix; if a replace/delete capability for Offer
media is ever added, cache-identity behavior needs re-review at that point.

CORRECTION — four files, no new dependency, no backend/schema/Worker/RLS
change, no dependency injection added, no unrelated Offer CRUD touched:

- `lib/src/services/supabase_core_entities_service.dart`:
  `_fetchOfferMediaDisplayUrls` (private) is replaced by
  `_fetchOfferMediaDisplayItems`, which returns the full
  `List<R2OfferMediaItem>` instead of discarding everything but `.url`.
  `getOffer(id)` now derives both `mediaUrls` and a new, index-aligned
  `mediaObjectIds` list from the same response and passes both into
  `OfferModel.copyWith`. The bulk list fetch (`_fetchOffers()`) is untouched
  and still returns no media at all, per its existing documented tradeoff.
- `lib/src/data/models/ScreensModel/offers_model.dart`: `OfferModel` gains one
  new field, `mediaObjectIds` (`List<String>`, defaults to `const <String>[]`),
  threaded through the constructor and `copyWith`. `mediaUrls`'s type and
  every other field are unchanged; the legacy Firestore `toFirestore`/
  `fromFirestore` mapping is untouched and never populates the new field, so
  the Firebase-backend path (stable, non-rotating Storage URLs) keeps its
  existing URL-keyed cache behavior exactly as before — no regression, no new
  capability claimed for it.
- `lib/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart`:
  `OptimizedMediaGalleryWidget` gains an optional `mediaIds` parameter
  (index-aligned with `mediaUrls`); `MediaItem` gains an optional
  `mediaObjectId`. `_synchronizeMediaItems` pairs the two lists by index only
  when their lengths match exactly — a length mismatch (or an empty-string id
  at a given index) is treated as "no id" for that item rather than risking a
  misaligned pairing that could attribute one item's cached bytes to another.
  `_buildOptimizedImageViewer` now passes `cacheKey: mediaItem.mediaObjectId`
  into the existing, unmodified `buildOfflineAwareImage`. This widget is also
  used by `owners_view_details.dart` (Owner Media, explicitly out of scope)
  and `video_system_integration.dart`; the new parameter is optional and
  defaults to `null`, so neither call site's behavior changes.
- `lib/src/views/Screens/ViewDetails/offers_view_details.dart`: one line —
  `_buildCachedMediaGallery()` now passes
  `mediaIds: _currentOffer.mediaObjectIds` into `OptimizedMediaGalleryWidget`.
  The existing 60-second `_recentOfferCache` is unchanged.

TEMPORARY 60-SECOND CACHE: **RETAINED**, deliberately not removed. It solves a
different bottleneck than this fix — a very-recent reopen still avoids a
repeated Offer-metadata read and signed-URL mint through the Worker/Supabase,
which the cache-key fix does not address. It is a static in-memory field and
is always cleared on process death, so it alone could never have satisfied
"no unnecessary re-download after restart" — only the disk-level `cacheKey`
fix does that. The two are complementary: after this fix, even a genuine
60-second-cache miss (first open, or any reopen after a restart) still avoids
re-downloading the image bytes, because `CachedNetworkImage`/
`flutter_cache_manager`'s on-disk store is looked up by `mediaObjectId`,
independent of whatever newly-signed URL string comes back that time.

ACCOUNT ISOLATION / AUTHORIZATION: unchanged from, and structurally identical
to, the already-accepted profile-image model. `mediaObjectId` is a random
UUID never disclosed to a session that has not already passed the Worker's
server-side ownership check and Supabase's `owner_id` RLS on `getOffer(id)`;
there is no path by which an unauthorized session could ever learn or guess
the id needed to address a cache entry for someone else's Offer media, so a
persistent disk cache keyed by that id carries no new cross-account exposure.
As with profile images, ordinary sign-out/account-switch does not proactively
clear this disk cache (only `DeletedAccountLocalDataCleaner`, on account
deletion, does) — a pre-existing, already-accepted characteristic of
`OfflineMediaService`, not something newly introduced here; it is safe for
the same structural reason (the id is never guessable and never leaked).

SIGNED URL SAFETY: unaffected. The Worker still mints a fresh, short-lived
signed GET URL on every `/offer-media` call with no change to its TTL or
signing logic; this fix only changes which cache key the client attaches to
whatever URL comes back, and never persists or reuses a URL past its own
validity.

TEST EVIDENCE: new `test/offers/offer_media_cache_identity_test.dart`, 9/9
PASS — `OfferModel.mediaObjectIds` defaulting/`copyWith` pass-through (3
tests), and `OptimizedMediaGalleryWidget` cache-key wiring (6 tests): a
same-index id becomes the rendered `CachedNetworkImage.cacheKey`; a re-signed
URL for the same id keeps the same key; distinct ids never collide; a
`mediaIds` length mismatch falls back to no key rather than misaligning an id
to the wrong URL; an empty-string id at an index is treated as no id; omitting
`mediaIds` entirely preserves the previous URL-keyed behavior. Regression
run: `test/app/` (4/4) and `test/services/r2_offer_media_upload_service_test
.dart` (9/9) still pass alongside the new file — 32/32 combined, 0 failures.
Targeted `flutter analyze` on all four changed files plus the new test file:
no issues. `git diff --check`: clean (only the known pre-existing CRLF
notices on files already carrying prior uncommitted changes; none of the four
files this correction touches produced a new notice).

NOT PERFORMED: no automated test for `OffersDetailsView` itself (same
pre-existing testability blocker already disclosed earlier in this
checkpoint: pumping it needs an initialized `Supabase.instance`, a real
`OptimisticFavoritesService`/`FavoriteService`, and an unconditionally-built
`GoogleMap`, none of which are injectable within this correction's four-file
scope); no real device/emulator verification of actual disk-cache-hit
behavior (this session had no `adb`/connected-device access — see below); no
Worker, Supabase, or R2 change; no git add, commit, or push.

BUILD: `flutter build apk --debug` completed successfully (exit code 0,
~139s) from this exact corrected source tree, producing
`build/app/outputs/flutter-apk/app-debug.apk`. Only pre-existing Gradle/AGP/
Kotlin "support will soon be dropped" advisory warnings were emitted — no
error, and no SDK/dependency change was made or is implied by them, per this
project's no-upgrade instruction.

APK SIGNATURE / PACKAGE / VERSION: this session has no `adb` and no connected
device, but package id, version, and signing certificate could still be read
directly from the built artifact using the local Android SDK's `aapt` and
`apksigner` (no device needed for this part):

- File SHA-256:
  `52ced62981ab916029b31959658fe68ce2cfaf30ed96534450b0cc9b7deab44b`
- Package: `com.example.broker_wallet`; versionCode `1`; versionName `1.0.0`
  — identical to every value this file has recorded for the currently-
  installed app in every prior checkpoint.
- Signing certificate SHA-256:
  `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` —
  byte-for-byte identical to the certificate this file already recorded
  (ADDENDUM — REAL-DEVICE REPRODUCTION ATTEMPTS; ADDENDUM — CORRECTED DEBUG
  APK INSTALLED) as matching the installed Samsung app. This is the standard
  local Debug keystore, so an unchanged keystore on this machine reproduces
  the same certificate on every debug build.

**What this does and does not prove:** this confirms the built APK's own
package/version/signature are self-consistent with this file's historical
record of the installed app's identity. It is **not** a live read-back of the
device's currently-installed certificate/versionCode/`firstInstallTime` the
way every prior successful install in this file performed via `adb` —
without device access, this session cannot confirm nothing has changed on the
device side since the last recorded install. Treat this as strong supporting
evidence, not a substitute for the live device-side check every prior
checkpoint performed before installing.

NOW — the source-side correction (implementation, targeted tests, analyze,
diff) and the Debug APK build are both complete. Awaiting the owner's
explicit approval to install.

NEXT — before installing: the owner (or an `adb`-capable environment)
performs the live device-side provenance read-back (installed package id,
signing certificate, versionCode, `firstInstallTime`) exactly as in the prior
successful install addendum, confirming it still matches this build. Only
after that should the owner perform TEST A–F from the Samsung Acceptance
section of this checkpoint's original instructions, specifically checking
whether reopening Offer A/B — including after a full force-stop/relaunch —
now avoids a visible redownload, and report the result before this correction
is marked VERIFIED_REAL_DEVICE.

## ADDENDUM — OFFER DETAILS RESPONSIVENESS AND CACHE SAFETY (2026-09-20)

OWNER OBSERVATION AT ENTRY: Offer A and its image, Offer B and its image, and
Recents had passed on Samsung. A second cold start failed, and the owner also
reported an intermittent white screen with a loading circle before Offer
Details. The original Android entry event that selected/restored that route
was not reproduced and remains UNKNOWN. Nothing in this correction claims a
new navigation root cause or a return of the old `Offer not found` failure.

ACTUAL FAILURE CLASSIFICATION FROM CURRENT SOURCE: the white full-screen state
was `_OfferDetailsLoader` in `lib/app.dart`. Its single Future called
`OfferService.getOffer`, which performed the authoritative Offer-row read and
then waited for `/offer-media` signed-URL resolution. Consequently, signed-URL
latency blocked the entire details screen even though metadata was already
available. Image download/decode occurred after that Future, so it was a
separate later delay. The first unnecessary blocking operation was the media
signing request inside the route loader. The reported second-cold-start event
cannot be classified more narrowly without a successful device reproduction;
the observable spinner is classified as presentation/request latency, not as
proven navigation failure.

CORRECTION:

- `OfferService` and `SupabaseCoreEntitiesService` now expose a strict two-stage
  read: `getOfferMetadata` reads the authorized Offer row, and
  `resolveOfferMedia` resolves only private media after that row is usable.
  Both stages reject an account change while their asynchronous request is in
  flight. Existing non-details callers retain the previous best-effort
  `getOffer` contract.
- `OfferDetailsLoader` waits only for authoritative metadata. Its required
  security boundary now uses a localized, themed loading skeleton instead of
  an unexplained white spinner. It never fabricates or substitutes an Offer.
- `OffersDetailsView` renders trusted metadata immediately and resolves media
  independently. An ID-loader result is not fetched a second time; an Offer
  passed from a list is authoritatively refreshed before private details are
  adopted. Media errors are localized and explicitly retryable.
- `OfferDetailsLoadCoordinator` owns the two-stage state, uses a generation
  token to reject late results after rapid Offer switches, and rejects all
  callbacks after disposal. Retry is explicit and bounded; there is no request
  loop or permanent loading state.
- The former static 60-second `_recentOfferCache` is REMOVED. It reused signed
  URL strings, was process-local, did not prevent image-byte misses after
  process death, and was not an acceptable account/freshness boundary. This
  supersedes the prior addendum that retained it.
- Offer media disk identity is now
  `offer-media:<authenticated-owner-id>:<media_objects.id>`. The stable id and
  signed URL are still derived atomically from the same Worker response. Both
  gallery display and prefetch use this same key, so a rotated signed transport
  URL can reuse valid bytes without becoming canonical identity. A retry
  replaces the in-memory provider with the fresh signed URL, preventing reuse
  of a failed/expired transport URL.
- Missing owner/media identity disables the stable key. A different account
  necessarily receives a different key; no cached image is requested until an
  authorized media response supplies its URL and id. An empty media response
  clears old URLs and ids, and replacement gets a new media-object id under the
  current append-only upload contract. Ordinary sign-out does not proactively
  erase the third-party disk cache, but another account cannot address/reuse
  the old entry through this UI path; physical retention remains governed by
  the existing cache-manager eviction policy. Any future in-place media-object
  mutation would require this identity assumption to be re-reviewed.

CHANGED IMPLEMENTATION FILES FOR THIS CORRECTION:

- `lib/app.dart`
- `lib/src/data/models/ScreensModel/offers_model.dart`
- `lib/src/services/ScreenServices/offer_service.dart`
- `lib/src/services/supabase_core_entities_service.dart`
- `lib/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart` (new)
- `lib/src/views/Screens/ViewDetails/offers_view_details.dart`
- `lib/src/views/Screens/ViewDetails/widgets/media_cache_manager.dart`
- `lib/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart`
- `test/app/offers_details_route_test.dart`
- `test/offers/offer_details_load_coordinator_test.dart` (new)
- `test/offers/offer_media_cache_identity_test.dart`

LOCAL VERIFICATION:

- Targeted combined run: 97/97 PASS. This comprises 45 route, details-loading,
  cache-identity, and existing R2 media service tests plus 52 auth/navigation/
  password-recovery tests. Coverage includes startup authority, valid/invalid
  Offer ids, missing legacy arguments, trusted loader behavior, no redundant
  metadata fetch, list-model refresh, pending media, success/failure/retry,
  rapid switching, disposal, account cache-key separation, signed-URL retry,
  and recovery/session boundaries.
- Focused `flutter analyze` on 12 changed production/test items: no issues.
- `git diff --check`: PASS; output contains only the repository's existing
  LF-to-CRLF working-copy notices.
- The seven pre-existing generated-plugin drift files were not edited. SHA-256
  values recorded before and after the build are identical.
- No runtime timing was measured. Debug functional observations must not be
  represented as final Release performance measurements.

DEBUG APK: exactly one build was run after the local PASS:
`build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`6d33399d2bcd7a2b86c0804ad6dbece7b4c108cc315ffc88770e33567329568a`.
Artifact identity is package `com.example.broker_wallet`, versionCode `1`,
versionName `1.0.0`, signing-certificate SHA-256
`6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61`.
Privacy-safe inspection of the built `kernel_blob.bin` confirms the canonical
ID route, split metadata/media symbols, account-scoped media-key prefix, and
stale-result guard are present; `NAV_DIAG` is absent.

DEVICE / INSTALL STATUS: `adb devices -l` returned an empty device list on
2026-09-20. Therefore the live installed package, certificate, versionCode,
and data-preserving update compatibility cannot be re-read now. No install,
uninstall, clear-data, downgrade, or signing change was performed. Historical
records match this APK identity, but they are not a substitute for the required
live pre-install check. DEVICE ACCEPTANCE remains PENDING and READY FOR SAMSUNG
is NO until device `R5CY10YYLSM` is connected and authorized.

NOW — connect and authorize Samsung `R5CY10YYLSM`; rerun the live package,
certificate, and version compatibility checks only.

NEXT — if and only if those checks pass, request the owner's explicit approval
for a data-preserving update-install, then run the single concise device
acceptance session. Do not mark DEVICE PASS until the owner reports the actual
results.

## ADDENDUM — OFFER MEDIA: LOCAL-FIRST LOAD, REMOVING THE NETWORK FROM THE FIRST FRAME (uncommitted)

OWNER OBSERVATION AT ENTRY: "the image keeps taking a moment to load every time
I open the details screen; this is not the expected behaviour." This is
reported against the tree that already contains the stable-cache-identity
correction and the two-stage loader recorded in the two addenda above.

WHY THE PREVIOUS CORRECTIONS COULD NOT HAVE FIXED IT. Both prior corrections
are sound and are retained. Neither could remove the delay the owner sees,
because the delay is not a byte re-download — it is the wait before any byte
can be asked for at all. Proven from source, end to end:

- `CachedNetworkImage` requires an `imageUrl` before it will consult its disk
  cache. A `cacheKey` changes *which* entry it looks up; it does not let it
  look anything up without a URL.
- The only source of an Offer media URL is the Worker's `GET /offer-media`
  (`cloudflare/workers/r2-profile-upload/worker.js`), which mints a fresh
  `GET_URL_TTL_SECONDS = 900` signed URL per object on every call and answers
  `Cache-Control: no-store`. That call itself performs a Supabase
  `/auth/v1/user` token verification, an ownership check and an `offer_media`
  select before it signs.
- `OfferDetailsLoadCoordinator.load()` awaited `getOfferMetadata` and only then
  started media resolution.

So every open — cold, warm, or immediately after the previous one — paid two
serialised network round trips before the first pixel, no matter how complete
the disk cache was. That is exactly the symptom reported.

The same defect was already solved for profile images and is production
verified: `OfflineMediaService.warmMediaIdMapping` /
`getLocalFilePathForMediaId` let `CurrentUserAvatar` paint `Image.file` on the
first frame with no URL and no network. Offer media never adopted that half of
the pattern — it took the cache key and left the durable identity in memory
only, where a process restart erased it.

ROOT CAUSES, all proven from source:

1. The image could not paint before two serialised network round trips
   (metadata, then signed-URL minting).
2. Media resolution was serialised behind the metadata refresh although it
   needs only the Offer id and the owning account, never the Offer row.
3. There was no durable client-side index of an Offer's media identity, so a
   cold open had no cache key to look anything up with.
4. Nothing ever recorded where an Offer media item's bytes landed, so the
   synchronous local-file branch of `buildOfflineAwareImage` could never hit
   for Offer media even when the bytes were present.
5. Upload side: `uploadOfferMediaFile` returns the confirmed `mediaObjectId`
   while the exact bytes sit in a local file, and nothing adopted them — a
   photo was downloaded back immediately after being uploaded.
6. `FullScreenMediaViewer` built its images with a bare `NetworkImage`, which
   has no cache of any kind, so every full-screen open re-downloaded an image
   the gallery behind it had just finished downloading.
7. The gallery's prefetch used `CachedNetworkImageProvider(maxWidth: 800,
   maxHeight: 600)`, which stores a second, resized copy under
   `resized_w800_h600_<key>` and decodes it at a size nothing on screen uses,
   while the display path reads `<key>`.

CORRECTION.

- NEW `lib/src/services/offer_media_cache_identity.dart`: `offerMediaCacheKey`
  (moved out of the gallery widget so upload, read and display agree on one
  key), plus `OfferMediaRef` (durable id + optional signed URL + optional local
  file), `OfferMediaResolution` and `applyOfferMedia`.
- `OfflineMediaService`: an account-scoped Offer-media catalogue in the
  existing, already-initialised `local_media` Hive box under
  `offerMediaCatalog::<ownerId>::<offerId>`, read synchronously; plus
  `ensureMediaIdCached` (fetch-or-hit under the stable key, then record the
  path) and `forgetOfferMedia`. `adoptLocalFileForMediaId` gained a
  `directoryName` parameter so Offer originals land in `offer_media`, not in
  `profile_media`.
- `SupabaseCoreEntitiesService`: `resolveOfferMedia({offerId, ownerId})` is now
  the primitive and returns an `OfferMediaResolution`; `cachedOfferMedia` reads
  the catalogue synchronously for the live session; `currentOwnerId` is
  exposed. `getOffer` composes the primitive through `resolveOfferMediaFor`, so
  list/Favorites/search/edit callers keep their previous contract exactly.
- `OfferService`: exposes `cachedOfferMedia` and the new `resolveOfferMedia`,
  and adopts each uploaded file's bytes under its confirmed media id.
  `resolveOfferMedia` returns null on the Firebase backend, which has no
  separate media stage — the caller then keeps what metadata supplied rather
  than treating "no media stage" as "no media".
- `OfferDetailsLoadCoordinator`: seeds from locally held media synchronously in
  its constructor, then runs the metadata refresh and media resolution
  **concurrently**, merging media into the fresh row. A fresh metadata row
  never blanks media already on screen. The authoritative row remains the
  authority on ownership: media started against a stale caller-supplied owner
  is discarded and re-requested.
- `OptimizedMediaGalleryWidget` / `FullScreenMediaViewer`: a descriptor API
  (`mediaRefs`) beside the existing URL-list API, which other call sites keep
  using unchanged. Full-screen now prefers held bytes, then the shared cache
  under the stable key, and only then the network. The gallery warms visible
  and nearby items through `ensureMediaIdCached` instead of the resized
  URL-keyed prefetch.
- `DeletedAccountLocalDataCleaner` also forgets the deleted account's Offer
  media catalogue, cached bytes and adopted originals.

Deliberate: the catalogue records identity only, never bytes. Pulling a whole
gallery the viewer may never scroll to would spend their data to fill a cache,
so bytes are fetched for what the gallery actually shows.

RESULTING BEHAVIOUR. First ever view of an Offer's photo is unchanged — the
bytes genuinely are not on the device. Every subsequent open, including after a
force-stop, paints from disk on the first frame with no network on the critical
path, while the authoritative refresh runs behind it.

ACCOUNT ISOLATION: unchanged in kind from the already-accepted profile-image
model. Every key and every catalogue entry carries the authenticated owner id,
so a different account necessarily gets a different key and cannot address or
read back this account's entries. Covered by a test.

SIGNED URL SAFETY: unaffected. The Worker's TTL and signing logic are
untouched; no signed URL is ever persisted or treated as identity.

IMMUTABILITY ASSUMPTION (unchanged, restated): Offer media upload is
append-only today, so a `media_objects.id` never changes bytes. If a
replace-in-place capability is ever added, this identity assumption must be
re-reviewed.

TESTING SEAMS: `OfflineMediaService.removeCachedBytes` and `.fetchCachedBytes`
are `@visibleForTesting` overrides. Constructing `DefaultCacheManager` reaches
path_provider, which does not exist under `flutter test`, and it raises an
asynchronous platform error no caller can catch. Both shared-cache calls are
additionally bounded by a 5-second timeout, so a stalled cache can never stall
an account deletion or leave a warm-up future pending forever.

TEST EVIDENCE (CODE_PROVEN, not VERIFIED_RUNTIME):

- `test/offers/offer_details_load_coordinator_test.dart` rewritten for the new
  contract: 15/15 PASS, including a test that media resolution starts *before*
  metadata returns, local-first renderability before any load, an authoritative
  empty response clearing cached media, a metadata refresh not blanking media
  on screen, and stale-owner rejection/re-request.
- NEW `test/offers/offer_media_local_first_test.dart`: 12/12 PASS against a
  real Hive store — catalogue ordering, cross-account isolation, clearing,
  per-account forgetting, and gallery rendering that produces a `FileImage` and
  *no* `CachedNetworkImage` at all when the bytes are held.
- `test/offers/offer_media_cache_identity_test.dart` (pre-existing): 14/14
  still PASS, proving the URL-list API and its callers are unchanged.
- `test/app/` 4/4 and `test/app/offers_details_route_test.dart` route contract:
  PASS. `test/account/` and `test/services/`: 122 PASS / 1 pre-existing
  failure.
- Full suite: 493 PASS / 22 FAIL. All 22 failures are pre-existing and
  unrelated — see UNRELATED PRE-EXISTING FAILURES below. The same 22 fail
  without this correction.
- `flutter analyze lib test`: zero errors, zero warnings.
- `dart format --output=none --set-exit-if-changed` on the files authored here:
  clean. No tracked, previously formatted file was reformatted.
- `git diff --check`: clean apart from the repository's existing LF-to-CRLF
  working-copy notices.
- The seven generated plugin-registrant files show no content change
  (`git diff --numstat` returns nothing for them) and were not edited.

UNRELATED PRE-EXISTING FAILURES (not introduced here, not fixed here):

- 5 failures in `test/account/delete_account_test.dart` and
  `test/auth/phone_security_hardening_test.dart` read migration files by their
  old fixed names (`20260911000100_…`, `20260911000200_…`,
  `20260913000100_…`). Commit `0d7fb17 chore: reconcile Supabase migration
  timestamps` renamed them to `20260911181050_…`, `20260911181112_…` and
  `20260913175221_…`. The tests need their paths updated; no production code
  is involved.
- 17 failures across `test/favorites/` come from `FakeOfferService extends
  OfferService`, whose field initializer eagerly constructs
  `R2OfferMediaUploadService()` and therefore `Supabase.instance`, which those
  tests never initialise. That field exists identically at `HEAD`.

BACKLOG OBSERVATIONS (reported, deliberately not changed here):

- `lib/src/views/Screens/ViewDetails/widgets/media_cache_manager.dart` keeps an
  unbounded static `Map<String, ImageProvider> _imageCache` that is never
  evicted except on explicit `dispose()`.
- The same file's `getOptimizedImage` still stores a resized duplicate for
  URL-keyed callers; only the private-media path now avoids it.
- Files under `lib/src/views/...` are imported through two different path
  spellings (`src/Views/...` and `src/views/...`). Dart treats those as two
  libraries, so a type declared in one is not assignable to the same type
  reached through the other. This bit during this work and is why the gallery's
  public boundary is typed on the service-layer `OfferMediaRef`. Normalising
  the spellings is a separate, repo-wide change.
- `DeletedAccountLocalDataCleaner._step` has no timeout; a collaborator that
  never completes would stall account deletion. The Offer-media path added here
  is bounded, but the pre-existing steps are not.

NOT PERFORMED: no Worker, Supabase, R2, RLS, migration or schema change; no
`git add`, commit or push; no real-device or emulator verification (no `adb`
device available in this session); no APK build in this session.

NOW — the owner installs the current source on Samsung `R5CY10YYLSM` and, on
an Offer that already has at least one photo, performs: (A) open Offer Details
and note the time to first image; (B) go back and reopen the same Offer — the
photo must appear immediately, with no spinner and no fade-in; (C) force-stop
the app, relaunch, and open that same Offer — the photo must again appear
immediately; (D) open the full-screen viewer and confirm it does not
re-download; (E) add a photo through Edit and immediately view the Offer — the
new photo must appear without a download; (F) confirm a genuinely new Offer's
first photo still loads correctly.

NEXT — if and only if B, C and E show an immediate image, this correction is
marked VERIFIED_REAL_DEVICE and the two stale-migration-path test files are
fixed as their own small checkpoint. If any of them still shows a delay, report
which step and whether a spinner or a blank frame appeared, so the remaining
wait can be attributed to metadata, to media signing, or to decode.

## ADDENDUM — OFFER MEDIA: ONE LOADING SURFACE INSTEAD OF TWO SPINNERS (uncommitted)

OWNER OBSERVATION: after the local-first correction above, reopening and cold
starting an Offer now show the photo immediately ("it does not load and that is
good"). The remaining complaint is the *first* open of an Offer whose photo
this device has never held: it showed two loading circles, and the owner asked
for one at most, or a better treatment.

CAUSE, proven from source. Loading an Offer photo is one operation to the user
but two stages underneath, and each drew its own indicator in the same 280px
header, one after the other:

- `offers_view_details.dart` `_buildMediaLoadingHeader` — a 28px
  `CircularProgressIndicator` plus a "Loading" caption, while metadata and the
  signed URL resolved.
- `media_gallery_widget.dart` `_buildOptimizedImageViewer` — a different, 24px
  `CircularProgressIndicator` inside the gallery, while the bytes behind that
  URL downloaded.

They are mutually exclusive at any instant, so this was a *sequence*: spinner
one, then a swap, then spinner two. Two other candidates were checked and ruled
out. `OptimizedFavoriteButton` declares `isLoading` but never renders anything
for it. `_OfferDetailsMetadataLoading` in `lib/app.dart` is not on this path:
all seven in-app entry points push `/offers-details-by-id/:id` with the Offer
as `extra`, `buildOfferDetailsByIdRoute` renders `OffersDetailsView` directly
when the extra matches the path id, and `test/app/
redirect_refresh_preserves_extra_test.dart` shows a router refresh does not
drop `extra`.

CORRECTION — one continuous surface, no spinner:

- NEW `lib/src/views/Screens/ViewDetails/widgets/media_loading_placeholder.dart`
  (`MediaLoadingPlaceholder`): a shimmering media block drawn only from
  `ColorScheme` tokens — base `surfaceContainerHighest`, highlight blended from
  `surface` — with a low-emphasis `image_outlined` mark. It carries the
  localized `loading` label as a `Semantics` live region, so assistive
  technology still hears a loading state even though nothing spins. It honours
  `MediaQuery.disableAnimations` by rendering a still surface.
- The sweep phase comes from one `static Stopwatch` shared by every instance,
  not from a per-instance `AnimationController`. The header's surface and the
  gallery's surface are two separate mounts, and the gallery replaces the
  header at exactly the moment media resolves; a per-instance controller would
  restart the sweep right at the hand-over this widget exists to hide. The
  controller now only schedules frames.
- `OptimizedMediaGalleryWidget` gained an optional `imagePlaceholder`. Offer
  Details passes `MediaLoadingPlaceholder`, so both stages draw the identical
  surface and the hand-over is invisible. Callers that pass nothing — Owner
  media and `video_system_integration.dart` — keep the previous spinner
  unchanged, which keeps this change inside the authorized screen.
- `_buildMediaLoadingHeader` is now that same placeholder. The 28px spinner and
  the visible "Loading" caption in the Offer Details media header are gone.
  This is a deliberate, owner-requested UI change to that one header, made
  under the explicit instruction "at least it should be only one, not 2 … and
  if there is better approach apply it for better UX".

A warm cache never shows the placeholder at all: `buildOfflineAwareImage`
renders `Image.file` directly from held bytes, with no placeholder stage.

TEST EVIDENCE (CODE_PROVEN, not VERIFIED_RUNTIME):

- NEW `test/offers/offer_media_loading_ui_test.dart`: 5/5 PASS — the
  placeholder renders no `CircularProgressIndicator`, still exposes a
  `Loading` semantics label, falls back to a still surface under reduced
  motion; the gallery renders the caller's surface and no spinner for an image
  whose bytes have not arrived; and a caller that supplies nothing still gets
  the previous spinner (no regression for Owner media).
- `test/offers/` and `test/app/`: 60/60 PASS.
- Full suite: 498 PASS / 22 FAIL, the same 22 pre-existing unrelated failures
  recorded in the previous addendum.
- `flutter analyze lib test`: zero errors, zero warnings. Format clean on every
  file authored here. `git diff --check` clean apart from the repository's
  existing LF-to-CRLF notices.

KNOWN LIMITATION: `OffersDetailsView` still cannot be pumped in a widget test
(it needs an initialised `Supabase.instance`, a real
`OptimisticFavoritesService`/`FavoriteService`, and an unconditionally built
`GoogleMap`). The two stages are therefore verified as units; that exactly one
surface appears across the hand-over is a real-device check.

NOTE ON `MediaLoadingPlaceholder` IN TESTS: it animates forever by design, so
`pumpAndSettle` will never settle while it is on screen. Use `pump(duration)`.

REMAINING SPINNER, not changed: `_OfferDetailsMetadataLoading` in
`lib/app.dart` still shows a spinner inside its skeleton's image block. It
appears only on the ID-only route — a deep link, or any entry that arrives
without the Offer model — never when opening from a list. Unifying it with
`MediaLoadingPlaceholder` is a one-line change plus one test update, held back
because it is off the reported path and the current design is deliberate and
test-covered.

BRANCH STATE AT THIS POINT: `feature/offer-private-media`, 23 commits ahead of
`main`, level with `origin/feature/offer-private-media`. No temporary
diagnostic remains in `lib/` (`TEMPORARY DIAGNOSTIC`, `NAV_DIAG` and
`BOOT_DIAG` all absent). `lib/main.dart` and the seven generated
plugin-registrant files appear modified in `git status` but have zero content
change — the documented `core.autocrlf` artifact — and must be kept out of any
commit. No `service_role`, `sb_secret`, `OPENAI_API_KEY`, private key or signed
URL appears anywhere in the diff.

## ADDENDUM — OFFER MEDIA REVIEW AUDIT (docs only; no code changed)

Five review points were raised against the two addenda above. Each was checked
against code, package sources and measurement. No production or test code was
changed by this audit. The findings below that are defects are NOT fixed yet.

### 1. Private-media security — partly proven, partly overstated

PROVEN (automated test, `offer_media_local_first_test.dart`): a second account
cannot *display* the first account's cached Offer photos through this app.
Every cache key and every catalogue key carries the authenticated owner id
(`offer-media:<ownerId>:<mediaObjectId>`,
`offerMediaCatalog::<ownerId>::<offerId>`), so account B computes a different
key, misses, and must fetch its own copy; the ids are random UUIDs never
disclosed to a session that has not already passed the Worker's server-side
ownership check and Supabase RLS.

NOT PROVEN, and the review is right that the owner id in the key does not
establish it: that no private bytes REMAIN ON THE DEVICE. They do. "Not
addressable through the UI" and "not present on disk" are different claims and
the earlier addenda did not separate them clearly enough.

Where the bytes actually live, verified from `flutter_cache_manager` 3.4.2:

- Downloaded photos: `IOFileSystem` uses `getTemporaryDirectory()` — the
  Android cache directory. Default policy `stalePeriod` 30 days,
  `maxNrOfCacheObjects` 200. The OS may purge it, and Android Auto Backup
  excludes it.
- Adopted upload originals: `getApplicationDocumentsDirectory()/offer_media/`,
  named `offer-media_<ownerId>_<mediaObjectId><ext>`. Not OS-purgeable.
- Hive (`local_media`, `url_mapping`) also lives in the documents directory and
  holds only UUIDs and file paths — no URLs, no tokens.

FINDINGS:

- **S-1 (high) — account deletion leaves orphaned originals.**
  `DeletedAccountLocalDataCleaner` calls `forgetOfferMedia(ownerId: deletedUid)`
  and `forgetOfferMedia` derives its work list *only* from catalogue entries.
  The `offer_media` directory is deleted only on the unscoped
  (`ownerId == null`) path, which account deletion never takes. Any adopted
  original whose id is not in a surviving catalogue — a photo uploaded and
  never viewed, a catalogue write that failed, a photo since removed server
  side — stays on disk after the account is deleted. The file name already
  begins with `offer-media_<ownerId>_`, so a prefix scan of that directory
  would close this precisely and stay account-scoped.
- **S-2 (medium) — Android Auto Backup.** `android/app/src/main/
  AndroidManifest.xml` sets no `android:allowBackup`, no `fullBackupContent`
  and no `dataExtractionRules`, so it defaults to backup-enabled, and
  `app_flutter/` (adopted originals + the Hive catalogue) is included. Cached
  downloads are not, being in the cache directory. This is pre-existing and
  app-wide, but this work is what first put private Offer photos into that
  directory. Excluding `offer_media` and the Hive boxes, or disabling backup,
  is a product/security decision.
- **S-3 (medium) — removal leaves bytes behind.** When an authoritative
  `/offer-media` response no longer lists an id, the catalogue is replaced and
  that photo stops being displayable, but its cache entry, its `mediaId::`
  Hive mapping and its adopted original are never pruned. No client path can
  remove Offer media today (`OfferService.removeMediaUrls` throws in Supabase
  mode), so this is latent — it becomes live the moment a delete capability is
  added.
- **S-4 (medium) — a revoked grant is indistinguishable from a bad network.**
  `R2OfferMediaUploadService._ensureSuccess` throws an untyped
  `R2UploadException` carrying only a message, so 401/403 cannot be told from
  502/timeout. On any media failure the coordinator keeps the previously
  rendered items, so a photo whose access was revoked server-side keeps showing
  from the local copy until a *successful* response says otherwise —
  indefinitely while offline. A deleted or no-longer-owned Offer is handled
  correctly and never shows its photo: `getOfferMetadata` returns null,
  `detailsUnavailable` is set, and Offer Details renders "Offer not found"
  instead of the media header.
- **S-5 (accepted, pre-existing) — ordinary sign-out clears nothing.** Only
  account deletion cleans up. After an account switch the previous account's
  photos remain on the device, unreachable through the UI but present. This
  matches the already-accepted profile-image behaviour.

### 2. Change size — measured and attributed

Of the 21 files with real content changes, **10 were already modified in the
working tree before this work began and were not touched by it**: `lib/app.dart`,
`offers_model.dart`, `media_cache_manager.dart`, `offers_list_view.dart`,
`favorites_card.dart`, `map_view.dart`, `match_details_view.dart`,
`search_view.dart`, `filtered_tiles.dart`, `compact_offer_card.dart`. Their
diffs contain only the earlier ID-route and cache-key work. `lib/app.dart` was
checked for every identifier introduced here and contains none.

The remaining 11: four pre-existing files extended (`offer_service.dart`,
`supabase_core_entities_service.dart`, `offers_view_details.dart`,
`media_gallery_widget.dart`), three that newly entered the changeset
(`offline_media_service.dart`, `deleted_account_local_data_cleaner.dart`,
`full_screen_media_viewer.dart`), three account test files given an injected
no-op collaborator, and this document.

Of the 9 untracked paths, 4 are new here
(`offer_media_cache_identity.dart`, `media_loading_placeholder.dart`,
`offer_media_loading_ui_test.dart`, `offer_media_local_first_test.dart`), 2
were rewritten (`offer_details_load_coordinator.dart` and its test), 1 received
a two-line test stub, and 2 are untouched.

SHARED-WIDGET IMPACT, verified: `FullScreenMediaViewer` has exactly one call
site, inside `media_gallery_widget.dart`. Owner Details reaches it through
`OptimizedMediaGalleryWidget(mediaUrls: ...)`, so its items carry no cache key,
`_warmStableIdentity` returns false for them and the previous prefetch path is
unchanged, and no `imagePlaceholder` is supplied so the previous spinner is
unchanged. The single behaviour change for Owner media is that full-screen
images now use `CachedNetworkImageProvider` instead of an uncached
`NetworkImage`. Owner `mediaUrls` come from Firestore (Firebase Storage
download URLs, which change when the object is replaced), so this is a
straightforward win with no staleness path; the cost is disk usage bounded by
the cache manager's 200-object / 30-day policy. It is independent of the
loading-delay fix and can be reverted on its own if the owner prefers a
narrower diff.

### 3. The 22 failing tests — independently proven pre-existing

Method: `git worktree add --detach` at `HEAD` (`005b819`), which contains no
uncommitted work at all, `flutter pub get`, full `flutter test`. The owner's
working tree was never touched; the worktree was removed afterwards and
`git worktree list` shows only the main tree.

- Baseline at `HEAD`: **438 passed, 22 failed**.
- Working tree with everything applied: **498 passed, 22 failed**.
- The two failing-test name lists were captured and compared: **byte-identical**.
  `comm` reports no test failing only in the working tree, and none failing
  only at baseline.

Same distribution in both: 1 in `delete_account_test.dart`, 4 in
`phone_security_hardening_test.dart`, 10 in
`favorites_list_reconciliation_test.dart`, 7 in
`favorites_viewmodel_initial_load_test.dart`. Causes, unchanged from the
earlier addendum: five tests read migration files by names that commit
`0d7fb17` renamed, and seventeen construct `OfferService`, whose field
initializer eagerly builds `R2OfferMediaUploadService()` and therefore
`Supabase.instance`, without initialising Supabase. Neither cause is touched by
this work. They remain out of scope and unfixed.

### 4. "The image appears immediately" — claim corrected

The review is right; the earlier wording was too strong and is withdrawn. A
passing `FileImage` test proves the widget resolves to local bytes, not that a
photo paints on the first frame after every restart.

What is actually established: **when an authorized local copy is present, no
network round trip is on the critical path.** That is the property the work was
for, and it is what the tests cover.

What is not guaranteed, with the mechanism for each:

- Decode still costs time. `Image.file` is asynchronous and, after a process
  restart, Flutter's in-memory `ImageCache` is empty, so the file must be read
  and decoded before anything is painted.
- **F-5 (low, real gap):** that branch of `buildOfflineAwareImage` passes no
  `frameBuilder`, so during those decode frames the media area renders *empty*
  rather than continuing to show the loading surface. A `frameBuilder` holding
  the placeholder until the first frame would close it.
- The copy can disappear. Cached downloads live in the OS cache directory under
  a 30-day / 200-object policy and can be purged by Android under storage
  pressure. When the mapped file no longer exists, `existsSync()` fails and the
  code correctly falls back to the network path — correct, but not instant.

### 5. Shimmer clock and reduce motion — measured

Measured with a temporary probe that was run and then deleted; the tree is
unchanged.

- Reduce motion **does** work as described: with
  `MediaQueryData(disableAnimations: true)` the gradient branch is absent
  (`DecoratedBox` count inside the placeholder = 0) and the still branch is
  present (`ColoredBox` = 1). With animations enabled the gradient is present
  (= 1).
- **F-6 (low, real defect):** with animations disabled the controller is still
  started in `initState`, so `SchedulerBinding.transientCallbackCount` is 1 —
  the ticker keeps requesting frames for an animation nothing is showing. It
  should not be started, or should be stopped, when animations are disabled.
- **F-7 (low, test quality):** the committed reduce-motion test asserts
  `find.byType(ColoredBox), findsWidgets`, which also matches framework
  widgets and would pass even if the branch did not work. The probe above is
  what actually proved it. The test should assert the gradient is absent
  *inside* the placeholder, as the probe did.
- Shared `static Stopwatch`: no odd cross-gallery synchronisation in the
  current app. The only places two instances coexist are the Offer Details
  header/gallery hand-over, where being in phase is the point, and adjacent
  `PageView` pages, of which one is visible. It never stops and never
  overflows (64-bit int). The caveat worth recording is that if this widget is
  ever reused for a *list* of skeletons, perfectly synchronised sweeps look
  mechanical and a per-item stagger would be preferable.

### Proposed corrections, not implemented

Ordered by severity: **S-1** prefix-scan `offer_media/` during scoped
forgetting; **S-4** type the Worker exception with its status code and purge
the local copy plus catalogue entry on an authoritative 401/403; **S-3** prune
cache entries, Hive mappings and originals for ids dropped from a catalogue
replacement; **S-2** decide backup exclusion for `offer_media` and the Hive
boxes; **F-5** add a `frameBuilder`; **F-6** do not run the ticker under
reduce motion; **F-7** strengthen the reduce-motion assertion.

NOW — the owner decides which of S-1 to F-7 to authorize, and whether to keep
or revert the Owner-media full-screen caching change.

NEXT — implement only the approved items as one scoped correction, re-run the
targeted suites and the HEAD-baseline comparison, then return to the device
acceptance in the previous addendum.

## ADDENDUM — OFFER PRIVATE MEDIA SECURITY & QUALITY CORRECTION (uncommitted)

One bounded correction covering the seven findings from the preceding audit,
security first. No Supabase, Worker, R2 or migration change. Nothing staged,
committed or pushed. Nothing installed.

### S-1 — orphaned originals on account deletion: CORRECTED

`forgetOfferMedia` no longer derives its work only from catalogues. It now also
sweeps the app-owned `offer_media` directory by file-name ownership prefix
(`offer-media_<ownerId>_`, the sanitized cache key `adoptLocalFileForMediaId`
already writes), so originals no catalogue names — an upload adopted before the
Offer was ever viewed, a failed catalogue write, media dropped by a later
response — are removed too.

Scoping and safety: an owner id that is missing or sanitizes to nothing
disables the sweep instead of matching every file; only regular files are
considered, so a `Link` is never followed and a directory is never deleted;
only direct children of that one directory are visited; a mapped path outside
the app-owned directory is left alone, because `adoptLocalFileForMediaId` falls
back to the picked file when its copy fails.

`forgetOfferMedia` and `forgetOfferMediaItems` now return an
`OfferMediaCleanupReport`. `DeletedAccountLocalDataCleaner.clear` returns it and
starts it as *not complete*, so a step that `_step` swallows can never read back
as a clean success while private originals remain.

### S-4 — authorization vs transport: CORRECTED

`R2OfferMediaHttpException` carries the Worker's status. The Worker's
`assertOwnsOffer` answers **404** for "no such Offer for this account" and it
reaches that only after its ownership query succeeded and returned no row — an
upstream failure answers 502 — so 404 (and 403) is the trustworthy revocation
signal. 401 is a rejected token, a session problem, and deletes nothing. 5xx,
timeouts and offline delete nothing.

An expired signed R2 URL cannot be misread as revocation: that 403 is raised by
R2 while the image itself is fetched, on the cache manager's path, and never on
this Worker API call. Covered by a test.

On a proven revocation the service removes this device's copy for that account
and Offer only, and the coordinator clears the items, sets `mediaAccessRevoked`,
renders a localized unavailable state (EN + AR) and offers no retry. On anything
transient, whatever is on screen stays and a retry is offered.

OFFLINE POLICY — UNCHANGED, AND NO DECISION IS REQUIRED. The established
contract is that previously authorized media stays displayable offline; that is
what `OfflineMediaService` exists for. Offline resolves to `transient`, which
changes nothing. The app cannot learn about a revocation while fully offline and
this work does not claim otherwise.

### S-3 — removal cleanup: CORRECTED to the available signal

`reconcileOfferMediaCatalog` replaces the remembered set and removes the bytes,
identity mapping, adopted original and in-memory copy of every id the new set no
longer contains. The only removal signal this architecture has is an
authoritative `/offer-media` response, and that is what drives it. No client
delete path was added.

REMAINING INTEGRATION DEPENDENCY: removal is noticed the next time the app
resolves that Offer's media. There is no push signal, so between a server-side
removal and the next resolution the local copy remains.

### S-2 — Android backup: NARROWLY EXCLUDED

`android:fullBackupContent="@xml/backup_rules"` (API ≤ 30) and
`android:dataExtractionRules="@xml/data_extraction_rules"` (API 31+, both
`cloud-backup` and `device-transfer`) now exclude
`domain="root" path="app_flutter/offer_media"`. Only exclusions are declared, so
every other backup behaviour is unchanged and backup is not disabled app-wide.
`app_flutter` is what path_provider returns for
`getApplicationDocumentsDirectory()` on Android; minSdk is 24, so both files
apply. Downloaded photos are not listed because they live in the cache
directory, which Auto Backup already excludes.

VERIFIED ON THE BUILT ARTIFACT, not from source: `flutter build apk --debug`
succeeded; the merged manifest carries both attributes; `res/xml/backup_rules
.xml` and `res/xml/data_extraction_rules.xml` are present in the APK; and
`aapt2 dump xmltree` of the compiled `data_extraction_rules.xml` shows the exact
exclusion under both sections.

Backups already taken are NOT retroactively deleted; this only stops future
ones.

### Account isolation

`MediaCacheManager` registers as a forget listener, so removing bytes from disk
also evicts the retained provider and the decoded image. On the canonical
account-transition points in `AuthViewModel._handleSessionIdentity` — a null
identity, and a different uid arriving directly — private Offer providers are
released, mirroring the existing `FavoriteService.invalidateForAccountChange`
call. Both display isolation and file-level isolation are tested.

UNCHANGED BY DESIGN: ordinary sign-out still does not delete files. That is the
established lifecycle, already accepted for profile media; changing it is a
product decision, not part of this correction.

### F-5, F-6, F-7

F-5: the local-file branch of `buildOfflineAwareImage` now has a `frameBuilder`
holding the caller's loading surface until the first decoded frame, so the media
area no longer goes blank while a held file is read and decoded. This does not
promise first-frame rendering; it only stops the gap being empty.

F-6: the sweep controller is started and stopped from `didChangeDependencies`
according to `MediaQuery.disableAnimations`, so no frames are requested for an
animation nobody sees, and a change to the setting is honoured while the widget
is alive.

F-7: the weak assertion is replaced. Tests now assert the gradient branch is
absent *inside* the placeholder under reduce motion, that the still surface is
present, that `transientCallbackCount` is 0, that normal motion still runs the
sweep, and that switching the setting mid-life takes effect.

### Owner viewer — unrelated change removed

`_imageProviderFor` returns a plain `NetworkImage` when an item has no stable
cache key, which is every Owner Media and video-integration item, restoring the
previous behaviour exactly. Private Offer media keeps local bytes → identity-
keyed cache → network. Both sides are covered by regression tests.

### Files changed

Production: `offer_media_cache_identity.dart`, `r2_offer_media_upload_service
.dart`, `offline_media_service.dart`, `supabase_core_entities_service.dart`,
`deleted_account_local_data_cleaner.dart`, `offer_details_load_coordinator
.dart`, `offers_view_details.dart`, `media_cache_manager.dart`,
`media_loading_placeholder.dart`, `full_screen_media_viewer.dart`,
`auth_viewmodel.dart` (three lines), `app_en.arb`, `app_ar.arb`.
Android: `AndroidManifest.xml`, new `res/xml/backup_rules.xml`, new
`res/xml/data_extraction_rules.xml`.
Tests: new `offer_media_security_cleanup_test.dart`, new
`offer_media_authorization_test.dart`, rewritten `offer_media_loading_ui_test
.dart`, and the three `test/account/` files updated for the new cleanup
contract plus three honest-reporting tests.

The seven generated plugin-registrant files were not edited. No signing file was
read or changed.

### Verification

- Targeted: `test/offers/` + `test/app/` + `test/account/` + `test/services/` —
  **165 PASS / 1 FAIL**, the failure being the documented stale migration path.
- `test/auth/` + `test/profile/` were also run because `auth_viewmodel.dart` was
  touched — **324 PASS / 4 FAIL**, all four the documented stale migration
  paths. No regression from the account-transition hook.
- New coverage: 16 cleanup tests (A–F including two accounts, repeat runs and
  partial failure), 12 authorization tests, 12 presentation/Owner tests.
- `flutter analyze lib test`: zero errors, zero warnings.
- `dart format --set-exit-if-changed` on every file in this change set: clean,
  except `auth_viewmodel.dart`, which CLAUDE.md records as carrying pre-existing
  deviations and must not be formatted. Formatting `supabase_core_entities
  _service.dart` and `media_cache_manager.dart` was verified byte-identical
  apart from line endings.
- `git diff --check`: clean apart from the repository's existing LF-to-CRLF
  notices.
- The full suite was NOT rerun; the previously proven identical 22-test baseline
  stands (HEAD 438 PASS / 22 FAIL, working tree 498 PASS / 22 FAIL, identical
  failing names).

### Unresolved security risks

1. Offline revocation is impossible without a signal. Disclosed, not promised.
2. Ordinary sign-out leaves files on the device; only in-memory state is
   released. Established lifecycle, owner decision to change.
3. The Hive catalogue (`local_media`, `url_mapping`) holds UUIDs and file paths
   — no image bytes — and is still eligible for backup. Excluding those shared
   boxes would also change profile-media restore behaviour by one avatar
   re-download, so it was left for an owner decision rather than taken
   unilaterally.
4. Backups already taken are not retroactively removed.
5. A downloaded cache entry whose id no catalogue names is not swept by name;
   only adopted originals are. Those bytes sit in the OS cache directory, are
   bounded by the cache manager's 200-object / 30-day policy, and are excluded
   from backup.
6. S-3 acts only at the next media resolution; there is no push signal.

### Build

`build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`544bd9f2a828009f42fd782cfc5b8603c88bdcd91bcdeabadd005222f9f04deb`, package
`com.example.broker_wallet`, versionCode `1`, versionName `1.0.0`, minSdk 24,
signing certificate SHA-256
`6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` — the same
certificate this file already records for the installed Samsung app.

NOT INSTALLED. Device acceptance PENDING owner approval. Any account-switch or
deletion scenario needs an explicitly approved safe test account; the owner's
own account must never be deleted.

NOW — owner approves the data-preserving update install on Samsung
`R5CY10YYLSM` after the live package/certificate/version read-back.

NEXT — run the device acceptance: startup and Offer navigation, Offer A and B
images, first open and immediate reopen, force-stop and restart, the loading
surface while decoding, and reduce-motion where testable.

---

## OFFER MEDIA — VIDEO UPLOAD AND THE 10-ITEM LIMIT (uncommitted)

OWNER AUTHORIZATION: videos must upload and save; max **10 media per Offer in
total** (existing images + existing videos + newly selected); max video size
**100 MB**; max video duration **3 minutes**; automatic compression/transcoding,
video thumbnails, and resumable/background uploading are **deferred to separate
checkpoints**. Production deployment is not authorized here. Nothing was
committed or pushed.

SCOPE NOTE: the owner directed this work to start while the previous
Startup-Navigation / Offer-image-cache checkpoint was still pending its real
device acceptance. That checkpoint's uncommitted work is untouched and is still
pending; this section's changes sit on top of it in the same working tree.

### Proven root cause (read-only phase, no guessing)

A video was refused in three independent places, none of them a defect in the
existing code — video was simply never part of the Offer media contract:

1. `R2OfferMediaUploadService._resolveContentType` recognized only JPEG/PNG/
   WebP byte signatures plus `.heic` by extension, so an MP4/MOV threw
   `Unsupported offer image type` **before any network call**. The Offer itself
   still saved, which is why the user saw the partial-upload message.
2. `worker.js` accepted only the four image content types on
   `/offer-media/authorize`, capped every upload at 10 MiB, hard-coded
   `media_type: 'image'`, and its `/offer-media/confirm` byte-signature check
   (`detectImageMimeFromBytes`) would have rejected video bytes anyway.
3. No limit on the number of Offer media existed anywhere, client or server.

`public.media_objects` already supported `media_type = 'video'`, `duration_ms`
and `thumbnail_media_id`, so **NO DATABASE MIGRATION WAS REQUIRED** and none was
written. RLS, grants, the ownership trigger and the account-deletion sweep are
unchanged.

### The 10-item limit is atomic without a migration

`offer_media` already carries `unique (offer_id, role, ordinal)`. The Worker now
ignores the client's role/ordinal entirely and, at confirm time, links every
Offer item as role `gallery` into the first free ordinal slot in `[0, 10)`. Two
concurrent confirms therefore cannot both take the last slot: the loser gets
PostgREST 409 (unique violation), tries the next free slot, and when none is
left the upload is rejected (`offer_media_limit_reached`) and cleaned up by the
existing `rejectInvalidUpload` path. `on_conflict=offer_id,media_id` with
`resolution=ignore-duplicates` keeps a retried confirm idempotent without
masking a slot collision. `/offer-media/authorize` additionally refuses early
when linked items plus this account's still-pending uploads for that Offer (only
those younger than the 24-hour abandoned-upload cutoff) already reach 10 — a
courtesy refusal, not the guarantee.

### Worker changes (`cloudflare/workers/r2-profile-upload/worker.js`)

- `OFFER_MEDIA_TYPES`: the four image types (10 MiB) plus `video/mp4`,
  `video/quicktime`, `video/3gpp` (100 MB). Profile images keep their own
  separate `isAllowedContentType` allowlist — image-only, unchanged.
- `detectOfferMediaMimeFromBytes`: ISO base-media `ftyp` brand detection for
  video, with HEIF/AVIF image brands explicitly excluded, falling back to the
  existing image detector. Container only — **the codec inside is not proven**.
- `media_type` is now recorded correctly (`image`/`video`); size limits, the
  confirm-time byte check and the object-key extension are all per type.
- `GET /offer-media` returns `mediaType` and `contentType` per item.
- `WorkerError` carries an optional stable `code`, returned in the JSON body,
  which the client maps to a localized message. Free-text provider messages are
  never shown to users.
- Object keys stay under `profiles/<uid>/offers/<offerId>/`, so
  `account_deletion.js` is untouched and still sweeps Offer videos.

### App changes

- NEW `lib/src/services/offer_media_policy.dart`: the shared limits (10 items,
  10 MB image, 100 MB video, 3 minutes), `VideoSignatureDetector` (the client
  mirror of the Worker's brand detection), a `check()` that reads only the first
  64 bytes of a file, and the `OfferMediaRejection` reasons, each bound to one
  ARB key.
- NEW `lib/src/services/offer_media_selection.dart`: screens picked files
  against every rule before they enter the form, including `VideoDurationProbe`
  (a `video_player` probe; a video the platform player cannot open is refused
  rather than uploaded blindly).
- `r2_offer_media_upload_service.dart`: the file is **never read into memory
  whole**. The PUT body is the file's own lazy read stream with an exact
  Content-Length, so a 100 MB video costs the same memory as a photo. A watchdog
  aborts on no progress for 45 s while sending, or 60 s with no response after
  the last byte — never merely because an upload is large. A typed
  `OfferMediaRejectedException` replaces the old free-text message.
- `offer_service.dart`: videos are deliberately **not** adopted into the local
  originals directory (a second copy of up to 100 MB to save one download is a
  bad trade); images keep the existing local-first behaviour. Partial failures
  now throw `OfferMediaPartialUploadException`, carrying counts and, when every
  failure shared one reason, that reason — never a file name or path.
- `add_offers_viewmodel.dart`: `currentMediaCount`/`remainingMediaSlots`, a
  refusal before the picker opens when the Offer is full, screening of every
  pick, and a re-check at save time.
- `clean_media_service.dart`: a picked video is no longer `readAsBytes()`-ed
  into memory (nothing consumed those bytes; it risked an out-of-memory crash
  and a long freeze before the upload even started). Camera recording accepts a
  `maxDuration`; the Offer screen passes 3 minutes, other callers keep 5.
- Display: `OfferMediaRef.isVideo` carries the **server's** media type into
  `MediaItem` instead of guessing from a signed URL. `getMediaTypeFromUrl` now
  parses the path only (`mediaExtensionOf`), so a signing query can no longer be
  mistaken for an extension. The image-cache warm path is unchanged and still
  skips videos, so a video is never pulled into the image cache.
- `video_player_resource_manager.dart`: every log that printed a media URL now
  prints it redacted — a signed GET URL is a short-lived credential.
- EN/AR: `offerMediaLimitReached`, `offerMediaLimitTrimmed`,
  `offerMediaUnsupportedType`, `offerMediaImageTooLarge`,
  `offerMediaVideoTooLarge`, `offerMediaVideoTooLong`,
  `offerMediaUploadInterrupted`, `offerMediaSomeFilesRejected`; the existing
  partial-failure string now says "photos or videos".

### Verification — CODE_PROVEN only

- Worker: `npm test` — **71/71 PASS** (55 pre-existing account-deletion/staging
  tests unchanged, 16 offer-media tests, 13 of them new): video round trip and
  listing, Samsung `mp42` and iPhone QuickTime, per-kind size limits, refusal of
  unsupported containers, five byte/type mismatch cases (including HEIC bytes
  declared as video), server-chosen slots ignoring a client ordinal, the 11th
  item refused, in-flight uploads counted, an abandoned upload ageing out,
  **two concurrent confirms for one free slot (one 200, one 409, exactly ten
  links, the loser marked failed and its object deleted)**, an idempotent retry,
  and profile `/authorize` still refusing a video.
- Flutter: `test/offers/ test/services/ test/common/` — **140 PASS, 0 FAIL**,
  including 16 new upload tests (streamed bytes identical to the file, progress
  monotonic, a stall aborted) and 10 new selection/display tests.
- `test/account/ test/app/` — 1 FAIL, the **documented pre-existing** stale
  migration path `20260913000100_account_deletion_jobs.sql`; unrelated.
- `flutter analyze lib test`: zero errors, zero warnings (114 pre-existing
  infos, all `deprecated_member_use` in untouched files).
- `dart format`: the four new files are formatted; no tracked file was
  reformatted, per this repository's documented policy.

### NOT VERIFIED / DEFERRED — do not treat as production-ready

- **No real video has been uploaded.** No device, no emulator, no staging or
  production deployment. The Worker changes are not deployed anywhere yet.
- The Worker must be deployed to **staging first**; production deployment is a
  separate, explicitly approved step. Staging and production share one Supabase
  project, so a staging run writes real rows.
- **Codec compatibility is not proven**: an HEVC/H.265 video from a Samsung
  camera may fail to play on older Android devices. The container is verified;
  the codec is not. This is what the deferred transcoding checkpoint solves.
- **Backgrounding stops an upload.** Dart's HTTP client is killed when the OS
  suspends the app; the Offer is still saved and the failed video is reported
  for retry from Edit. Resumable/background upload is deferred.
- Deferred by owner decision: compression/transcoding, video thumbnails (a video
  shows a tile with a play icon), resumable/background uploading, and local
  caching of video bytes.
- Backlog observed, not changed: the Add Offer picker still offers a "Documents"
  option whose PDF/DOC picks cannot be uploaded as Offer media and are refused
  as an unsupported type.


### AMENDMENT — the 3-minute limit is now enforced by the trusted backend

The preflight established that the duration rule existed only in Flutter, which
is a courtesy check, not a rule: any modified client could have uploaded a
longer video within the 100 MB cap. The owner asked for production-grade
behaviour, so `worker.js` now measures it server-side at confirm time.

- `readVideoDurationMs` walks the uploaded object's top-level ISO base-media
  box headers with small ranged reads until it finds `moov`, then parses
  `mvhd` (version 0 and version 1) for timescale and duration. It handles the
  layout phone cameras actually write, with `moov` **after** the media data,
  and it never downloads the media data: a test asserts the whole measurement
  of a 40 MB file reads under 4 KB.
- Over the limit → the upload is refused 422 `video_too_long`, marked `failed`,
  its R2 object deleted and never attached to the Offer. A file whose duration
  cannot be read **fails closed** (422, treated as an unsupported file) rather
  than being accepted on trust.
- The measured duration is persisted in the existing `media_objects.duration_ms`
  column. No migration: the column already existed. Images are untouched and
  never carry a duration.
- Tolerance: 1 second above three minutes, because an encoder can measure a
  clip the camera reports as 3:00 a few tens of milliseconds over. Bounded at
  24 box hops and a 512-byte `moov` window, so a malformed file cannot make the
  Worker loop or read unbounded data.
- Client side: `video_too_long` now maps to the existing localized
  "3 minutes or shorter" message, and 422 was added to the statuses whose
  stable `code` the client reads.

Verification: Worker `npm test` **78/78 PASS** (7 new duration tests: exactly
three minutes accepted and recorded, an over-long clip refused and cleaned up,
the rounding tolerance honoured on both sides, `moov`-last and 64-bit `mvhd`
parsed, no readable duration failing closed, the read staying under 4 KB on a
40 MB file, and an image never duration-checked). Flutter targeted suites
**141 PASS** (one new test: the server's refusal surfacing as the localized
too-long message). `flutter analyze lib test`: zero errors, zero warnings.

Still deferred and still unclaimed: codec compatibility, resumable uploads,
background uploads, compression/transcoding and video thumbnails. The signed
PUT URL's 300-second lifetime versus a 100 MB upload on a slow link remains the
open question for staging to answer.

NOW — the app's configured Worker URL is the production one, so a device test of
video needs either this Worker version deployed to `r2-profile-upload-staging`
with a debug build pointed at it, or an explicitly approved production Worker
deployment as its own step. Owner decides which.

NEXT — device acceptance for video: record and pick a video, confirm it uploads,
saves and plays; try an 11th item; try a video over 100 MB and one over 3
minutes; confirm existing photo upload and display are unchanged; confirm the
English and Arabic messages.

### STAGING ACCEPTANCE — PHASE 1, ONE REAL VIDEO: PASS (VERIFIED_HOSTED)

Owner deployed the local Worker candidate to the staging Worker
(`r2-profile-upload-staging`): new version
`d6e8fdb4-da48-43e4-b4cc-803fe8f204db`, rollback target
`5934a60d-bf74-42fe-b3ef-c92fac5dfb15`. Production remains untouched.

Executed by the agent from the local terminal, non-interactively. The staging
gate key and the disposable account's password were captured by the owner with
masked input into a DPAPI-encrypted file readable only by that Windows account,
used in memory only, never printed, and the file was deleted at the end of the
run (deletion verified). No key, token, presigned PUT URL or signed GET URL was
printed or stored.

**Gate, on the new version:** a request with no key → 403; a request with a
wrong key → 403. (The wrong-key case had not been exercised before.)

**Test input, verified locally before anything was sent:** a real MP4,
major brand `isom`, 7,796,364 bytes (7.44 MiB), duration **74.65 s**, with
`moov` **first** — the complementary layout to the `moov`-last case the unit
tests cover.

**Result: 14 PASS / 0 FAIL**, each from an actual HTTP status or actual bytes:
sign-in; the Offer `2af5fa05-…` proven to belong to the disposable account
(`4b0b5727-…`) by the Worker's own 200/404 ownership answer; authorize
returning `mediaType: video`; the object key confined to
`profiles/<account>/offers/<offer>/<id>.mp4`; the signed PUT of the real file
to private R2 (HTTP 200, 1.6 s); **confirm accepting the video, which means the
server-side byte-signature and the new server-side duration check both passed
against a real camera file**; the list returning it as `mediaType=video`,
`contentType=video/mp4`; exactly one association, and the Offer's item count
rising 0 → 1 (no duplicate); a fresh signed retrieval URL; and the downloaded
bytes matching the original in both length and SHA-256
(`E557F43843D34F62…`).

Because `/offer-media` lists only `status='ready'` rows, the item being listed
is itself the proof that the media object reached `ready`.

**Test data created and retained** (nothing deleted, cleanup not authorized):
one `media_objects` row `522a53d1-a946-41db-8e1d-4fd4f78566ba`, one
`offer_media` association on Offer `2af5fa05-1f61-457f-95ad-54b6e13978a7`, and
one object in `broker-wallet-media-staging`.

**A defect in the earlier draft acceptance script was found and corrected
before running** (the script only, not the implementation): in PowerShell 7,
`Invoke-WebRequest -OutFile` returns nothing without `-PassThru`, so the
download check compared `$null` to 200 and would have reported a false FAIL on
a successful download. The runner also now compares the Offer's item count
before and after, so a duplicate association would be caught rather than
assumed away.

**NOT YET TESTED ON STAGING** (each needs its own owner approval, and some need
inputs that do not exist yet): the 10-item limit end to end (fills the Offer);
the server-side 3-minute refusal (needs a clip longer than three minutes, and
creates a `failed` row); cross-account denial (needs a second disposable
account); Profile Media regression through the staging Worker (replaces that
account's avatar); and the 100 MB upload on a slow link, which is the open
question about the 300-second signed-PUT lifetime — this run moved 7.44 MiB in
1.6 s and therefore says nothing about it.

**Flutter real-device acceptance remains NOT VERIFIED**: the app points at the
production Worker and never sends the staging key, so the device path cannot be
exercised against staging.

NOW — owner decides which of the remaining staging tests to authorize, and
whether to approve the production Worker deployment as its own checkpoint.

NEXT — after production deployment, the real-device acceptance on Samsung:
record and pick a video, confirm upload, save and playback, the 11th item
refusal, an over-long and an over-size clip, and that photos are unchanged.
