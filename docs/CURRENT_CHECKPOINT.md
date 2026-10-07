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

## OFFER MEDIA — PRODUCTION LIFECYCLE, PHASE 2 (implemented locally; uncommitted after the baseline)

OWNER AUTHORIZATION: "APPROVED — PROCEED TO PHASE 2", with: (1) Option B, one
service-role-only atomic `confirm_offer_media_upload` function — migration,
reversal notes and validation prepared for independent review, NOT applied;
(2) the Offer saves without waiting for media, a persistent per-item queue
uploads visibly, and nothing is shown as uploaded before it is ready;
(3) Offer-only UI: upload state overlays, Retry, Remove, local video poster,
tap-to-play, expired-link recovery, all 10 items reachable — no redesign, no
Owner change; (4) 7-day retention for soft-deleted Offers' media, sweeps
shipped `off`; (5) HEIC converted to JPEG on the device; (6) one baseline
commit, no push. No Supabase, Cloudflare or production change was made.

### Baseline commit

`ed78c45` — "feat(offer-media): baseline private offer media, video support
and details loading", **not pushed**: the earlier Offer-media work of this
branch (34 tracked + 17 new files). Excluded: `lib/main.dart` and the seven
generated plugin files (line-ending-only, no content change). Before it, a stale
0-byte `.git/index.lock` dated 2026-09-19, with no git process running, was
removed; `git add` had been silently staging nothing. Everything below is on
top of that commit and uncommitted.

### What the lifecycle is now

- **Identity**: each picked file gets a UUID v4 `mediaObjectId` on the device,
  once, at selection. It is the same id in the upload queue, the Worker,
  `media_objects`, the R2 key and the local cache. Every Worker step is
  idempotent on it, so any retry — after a lost answer, a failure or a restart
  — resumes the same object and can never create a second one.
- **Save**: the Offer row is saved first and never rolled back for a media
  problem; removals run next (each reported as it went); new items are handed
  to the queue. The form never waits for an upload. An item that could not be
  queued, or a removal that failed, stays in the open form and Save retries
  exactly that; a created Offer is never created twice.
- **Queue** (`OfferMediaUploadQueue`, Hive box `offer_media_uploads`): one
  upload at a time, oldest first; a durable copy of each file in the
  backup-excluded `offer_media` directory under the owner's file-name prefix
  (moved from the picker's temporary copy, copied otherwise); automatic retries
  at 2 s / 10 s / 30 s / 2 min / 10 min, then Retry; a transfer whose bytes
  already reached R2 is only confirmed again, never re-sent. States:
  queued / uploading (with progress) / ready / retryable failure / permanent
  failure. An 11th item waits (`blocked`) instead of being lost, and goes on
  when a removal frees a place. Uploads run only for the application-
  authenticated account (`OfferMediaSession`, fed by `AuthViewModel`): never
  under password recovery or the deletion quarantine, never another account's
  task. Account deletion purges that account's tasks before its files are swept.
- **Confirm (Option B)**: the Worker verifies size, real type and video duration
  from the bytes in R2, then makes one call to `confirm_offer_media_upload`,
  which locks the Offer row, counts only `ready` items in the same bucket,
  appends at max+1 and marks the item ready in one transaction. This
  **supersedes** the "limit without a migration" mechanism described above
  (first free slot in `[0, 10)` retried on a unique-violation 409).
- **Remove**: `/offer-media/remove` — a pending or failed row is deleted; a
  ready one goes `pending_delete` → unlinked → R2 object deleted → `deleted`
  tombstone. Idempotent; a failed R2 delete is completed by the sweep.
- **Sweeps** (`OFFER_MEDIA_SWEEP_MODE` = `off` | `dry_run` | `on`; missing or
  unknown means `off`; shipped `off` in production and staging vars): abandoned
  pending uploads over 24 h, media of Offers soft-deleted over 7 days,
  unfinished `pending_delete`, failed rows over 7 days. Bucket-scoped, limited
  to `profiles/*/offers/*` keys, 10 per run (dry run lists up to 100).
- **Display**: Details and full screen show queued items from their local copy
  with their state; images decode at screen width; a private video shows its
  still frame (made on the device) and its length and loads nothing until
  tapped; its player is named by the stable cache key, not the rotating signed
  link; an expired link is signed again once, automatically, then the viewer
  gets a localized message and Retry. Signed links are held in memory only
  (`OfferMediaUrlCache`, dropped 60 s before expiry and on account change) and
  are never persisted. Full screen never preloads a private video.
- **HEIC**: converted to JPEG on the device with the existing
  `flutter_image_compress`; the Worker no longer accepts new HEIC uploads (it
  still reads older HEIC rows) and validates the real bytes as before.

### Proposed Supabase change — FOR REVIEW, NOT APPLIED

- `supabase/migrations/20260925120000_offer_media_confirm_rpc.sql`:
  `create or replace function public.confirm_offer_media_upload(...)`,
  `SECURITY DEFINER`, `search_path = ''`, EXECUTE revoked from public, anon and
  authenticated, granted to service_role. No table, column, RLS, index or
  trigger change.
- `supabase/tests/offer_media_confirm_test.sql`: pgTAP, plan(26).
- `supabase/validation/offer_media_confirm_validation.sql`: one transaction
  that installs the exact migration text, asserts behaviour on reserved test
  ids and ends in `ROLLBACK`; includes a two-session concurrency procedure.
- **Neither has been executed** (no Docker, `psql` or Postgres on this
  machine). A static test keeps the migration, the validation script, the pgTAP
  plan and the Worker's call in agreement; that is not execution.
- Reversal: drop the function only after every Worker version that calls it
  has been rolled back; dropping it deletes no data.

### Verification — CODE_PROVEN (local only)

- Worker `npm test`: **103/103 PASS** (55 account-deletion, 38 offer-media,
  10 staging-gate).
- Flutter full suite: **693 PASS, 5 FAIL**. All five fail at `HEAD` too: they
  read migration files renamed by `0d7fb17` ("reconcile Supabase migration
  timestamps", 2026-09-15) —
  `test/account/delete_account_test.dart` (1) and
  `test/auth/phone_security_hardening_test.dart` (4). Unrelated; not changed.
- 109 new or rewritten Flutter tests: upload queue 29, save orchestration 10,
  Add/Edit form 15, rendering 11, migration/Worker contract 10, URL cache and
  session 7, transport +10, video/HEIF +8, selection +8, deletion purge +1.
- A defect found by those tests and fixed: a video link with no playable
  extension failed inside the player's `initState`, so the tile's recovery ran
  during its parent's build (`!_dirty` assertion); the failure callback is now
  delivered after the build.
- A regression found and fixed: a failed `Hive.openBox` leaves an unhandled
  error inside Hive; the queue now opens its box with an explicit path (the
  same documents directory `Hive.initFlutter()` uses), so a missing directory
  provider is an ordinary, handled error. That fixed 42 auth/account tests
  that never initialize Hive. A 43rd, a deletion UI test whose fake-async zone
  never completes real I/O, now injects the new purge step exactly as it
  already injected the cleaner's other media steps.
- `flutter analyze lib test`: 0 errors, 0 warnings; 113 infos, none in a file
  changed by this checkpoint.
- `dart format`: the ten new Dart files are formatted. No tracked file was
  formatted; four tracked files had formatter deviations in lines written here,
  corrected by hand. Deviations already present at `HEAD` were left as they were.
- `git diff --check`: clean. Generated plugin files and `lib/main.dart`: no
  content change (line endings only), not edited.
- Scope: no Owner file changed. Shared widgets (`media_upload_widget`,
  `unified_media_preview_grid`, the gallery, full screen, the video resource
  manager) change only for Offer media or behind defaults that keep the Owner
  path identical; an Owner-grid test and the existing Owner pipeline tests pass.

### NOT VERIFIED — do not treat as production-ready

- The migration is not applied; the Worker is not deployed anywhere; no device
  or emulator run of any Phase 2 behaviour.
- MOV, 3GP and HEVC playback compatibility is not claimed: the container is
  checked, the codec is not. Requires real-device acceptance.
- Background execution: the queue persists and resumes on app resume and
  restart, but does not upload while the OS has the app suspended.
- The 300-second signed PUT versus a 100 MB upload on a slow link is still
  unmeasured; a stalled transfer is retried from the queue with the same id.
- HEIC conversion and video still frames use platform plugins and are not
  device-verified.

### Deployment order (mandatory)

1. Independent review, then the validation script on hosted Supabase (ends in
   ROLLBACK), then the owner applies the migration.
2. Owner deploys the Worker to `r2-profile-upload-staging`; staging acceptance.
3. Production Worker, as its own approved step.
4. Only then an app build with the queue. Against the current production
   Worker the new app refuses to continue an upload whose id the server chose
   (by design), so every item would wait in Retry. Older app builds keep
   working against the new Worker: the id is optional there and role/ordinal
   are ignored.

The Worker must never be deployed before the migration: without the function,
every Offer media confirm fails with 502 and items stay pending (retryable).

NOW — independent review of the migration and validation SQL; then the owner
runs `supabase/validation/offer_media_confirm_validation.sql` in the hosted SQL
Editor and confirms it ends in ROLLBACK with every check passing.

NEXT — owner applies the migration, deploys the Worker to staging, and
authorizes the staging acceptance (image, video, 11th item, retry/idempotency,
remove, cross-account denial); then the production Worker; then the Samsung
device acceptance of the app.

## OFFER MEDIA — STAGING ACCEPTANCE (VERIFIED_HOSTED, 2026-09-26)

**Deployment.** The owner deployed the recorded candidate to the staging
Worker `r2-profile-upload-staging` with wrangler 4.136.3 (`worker.js` sha256
`94b3ca4a…`, 109.32 KiB bundle, the same size as the local dry-run). Checked
first-hand afterwards: version `ab42e479-7ff2-445e-8e7e-08b945c9b4a6`
(tag `op2-94b3ca4a`) serves 100% of staging; fetch and scheduled handlers;
bucket `broker-wallet-media-staging`; `OFFER_MEDIA_SWEEP_MODE = "off"`; the four
expected secret names. Gate: preflight 204, no key 403, wrong key 403.
Rollback target: `d6e8fdb4-da48-43e4-b4cc-803fe8f204db`. Production was not
touched (still `bacad8d6-b7e2-434b-88e4-965c91c82874`). Scheduled run on the
new version, observed with `wrangler tail`: `*/5` at 10:15:26 UTC — Ok, no
error and no `[offer-media-sweep]` output (the sweep only logs in `dry_run` or
`on`), so the account-deletion finalizer runs and cleanup stays off.

**End-to-end run `20260926T100726Z`** — the owner ran the prepared runner
(session scratchpad, `staging_e2e/`) with two new disposable accounts; it
records statuses, codes and ids only. **69 PASS, 1 FAIL**, against hosted
Supabase and private staging R2:

- JPEG, PNG and WebP photos and a real 7.44 MiB MP4: authorize → private PUT
  → confirm → listed with the right type → signed download byte-identical.
  The video's duration was measured by the Worker (74,651 ms) and stored; a
  ranged read answers 206 with the right bytes.
- Retry and idempotency: authorizing one id twice leaves one row; confirm
  before the bytes arrive answers 409 `upload_incomplete` and leaves the row
  pending; a repeated confirm returns the same position with one link and one
  row; an attached id answers `ready`; the id reused for another Offer or
  another size is refused (409 `idempotency_mismatch`).
- Refusals: PNG bytes declared as JPEG → 422 `media_type_mismatch`, row
  failed, id stays refused, never listed; photo over 10 MB, video over 100 MB
  and a new HEIC upload refused before any row exists.
- The ten-item limit: nine photos and one video at positions 0–9; the
  eleventh refused (409 `offer_media_limit_reached`, no row); after one
  removal the same eleventh id is attached at position 10, never in the gap.
- Removal: tombstoned `deleted`, unlinked, its R2 bytes gone (404 on the
  earlier signed link), repeat removal harmless, an unconfirmed upload
  withdrawn with its row deleted and unattachable afterwards.
- Cross-account: account B gets 404 listing, authorizing, confirming or
  removing on A's Offer, 409 `media_id_conflict` reusing A's id, no rows
  through RLS, and 403 `42501` calling the database function; A's media is
  untouched.
- Database, first-hand: `confirm_offer_media_upload` exists and does the
  attaching (positions, limit, append) through the Worker, and a signed-in
  client calling it directly is refused 403 `42501`. The owner reports the
  hosted migration as version `20260926092220`; the repository file still
  carries `20260925120000` until that version is confirmed first-hand.

The one FAIL was a defect in the runner, not in the Worker: it re-authorized a
removed PNG id as a JPEG, which the Worker correctly refused as
`idempotency_mismatch` (409) before reaching the removed-state answer; confirm
on the same id answered 410 `media_removed`. The runner now removes its own
PNG and checks both answers.

Not run, by decision: the profile-image mutation and account-deletion
regressions (their code is unchanged; 55 account-deletion and the profile
Worker tests pass locally) and a video over 3:01 (covered by Worker unit
tests only).

Test data created and kept (staging bucket only, disposable accounts): Offers
`431b1f9d-bb0d-4efb-9182-d882e2511a4d` and `58a5a3b9-90a0-40d9-92b2-693ef6c28ac7`
(account A), `d3a6ba3e-7b6f-4769-8e6d-209fa97959f7` (account B), and 19 media
objects listed in the run report. Two earlier attempts stopped at sign-in
(`invalid_credentials`) and created nothing. No existing row was modified or
deleted.

**Clean rerun `20260926T101644Z`: 72 PASS, 0 FAIL** with the corrected runner,
the same candidate and staging version. It adds: a removed id answers 410
`media_removed` on both authorize and confirm, and 409 `idempotency_mismatch`
when reused for a different file. Created and kept: Offers
`d557e504-d87e-4a79-87c8-769460313c73`, `0276037d-997f-4aca-813a-08641ac3487b`
(account A) and `4a56e6b5-ce2d-4c92-b111-aa2f08da5234` (account B), and 20
media objects in the staging bucket.

**STAGING ACCEPTANCE: PASS.** Production candidate: the same source
(`worker.js` `94b3ca4a…`; production bundle byte-identical to the staging
one), bucket `broker-wallet-media`, `OFFER_MEDIA_SWEEP_MODE = "off"`, rollback
target `bacad8d6-b7e2-434b-88e4-965c91c82874`.

NOW — the owner deploys this candidate to production (the agent's session
may not deploy) and keeps the rollback command at hand.

NEXT — verify the live production version and settings, then the Samsung
device acceptance; Offer media is not complete until it passes.

## OFFER MEDIA — SAMSUNG DEVICE FAILURE, TASK A (2026-09-26)

### Status

| Item | Status |
| --- | --- |
| Backend staging E2E (`r2-profile-upload-staging`, `ab42e479…`) | 72/72 PASS — VERIFIED_HOSTED |
| Supabase `confirm_offer_media_upload` | APPLIED + VERIFIED_HOSTED (owner's rollback validation 33/0; SECURITY DEFINER, owner postgres, empty search_path, anon/authenticated denied, service_role allowed) |
| Production Worker `r2-profile-upload` | Deployed by the owner: `ecaf125d-a0e3-4c26-add6-5f2c684c2516`, bucket `broker-wallet-media`, `OFFER_MEDIA_SWEEP_MODE=off`, rollback `bacad8d6-b7e2-434b-88e4-965c91c82874` (owner-reported; not re-read by the agent) |
| Real-device Offer media (Samsung) | FAILED / OPEN |
| Task A — P0 device failure | ACTIVE: root causes proven, fixes CODE_PROVEN, device acceptance NOT run |
| Task B — P1 picker/permission UX | QUEUED, separate, not started (see `docs/OFFER_MEDIA_DEVICE_ISSUES.md`) |
| Task C — private Offer documents | DEFERRED unless separately approved |

Not run and not claimed: the over-3-minute video refusal on staging (Worker unit
tests only) and the live profile-image / account-deletion regressions.

**Migration tracking reconciled.** Read first-hand (`supabase migration list
--linked`, read-only; the CLI initialised its temporary login role to connect):
remote `20260926092220` had no local file and local `20260925120000` no remote
row. The local file was renamed to
`supabase/migrations/20260926092220_offer_media_confirm_rpc.sql`, byte-identical
(sha256 `3aad4199…c6e8e1`), so `db push` can never re-apply it. Nothing was
applied. Not compared first-hand: the hosted
`supabase_migrations.schema_migrations.statements` text against this file. The
rollback-only validation script is left byte-identical to the executed version
(its stage labels still name the old file name).

### Owner's observation

Five images + five videos on a new Offer: some tiles blurry, some showing an
upload percentage for minutes, videos very slow, some showing "upload stopped,
tap Retry", playback showing "this video can't be played right now", some still
unplayable after ~10 minutes.

### Evidence collected (read-only, before any change)

Device: Samsung SM-S928B, Android 16 (SDK 36), installed Debug build of the
current working tree (built 14:33:02, no `lib/` file newer). Wi-Fi 5 GHz,
validated, continuously connected since 09:26 (no network change during the
test). The phone was locked, so no UI was driven; logcat for the test window
had already rotated out (buffer starts 14:52:31).

- **Upload queue history** — Hive keeps every state write as an appended
  frame; the box was copied to the session scratchpad and decoded (ids
  shortened, no paths or names printed). Offer `…969770`, saved 14:40:25. The
  five photos and one video completed 14:40:33–14:41:02. The other four
  videos (4.3–8.3 MiB, 42–56 s, MP4) **failed at the authorize step, before
  any byte was sent, in about 20 ms each** — at 14:41:05, 14:41:07, 14:41:17 and
  14:41:47 — each counted as an automatic retry (`interrupted`). A real request
  needs at least one Worker→Supabase round trip, so these failed on the device.
- **Completion times** (mtime of each adopted still frame): the four waiting
  videos completed at 14:48:58, 14:49:02, 14:49:06 and 14:49:09 — **about 4 s
  each for authorize + PUT + confirm**. Throughput was never the problem.
- **Android network policy** (`dumpsys netpolicy`): the app's uid is
  `blocked=APP_BACKGROUND, effective=APP_BACKGROUND` whenever it is not in
  front. Android 15 behaviour change (official): an app that makes a network
  request outside a valid process lifecycle receives an `UnknownHostException`
  or other socket `IOException`.
- File characteristics: all selected files were within policy (photos
  80–555 KB after the picker's resize; videos far below 100 MB / 3 min), so no
  policy refusal was misreported.

### Root causes

1. **CONFIRMED (device + code): the queue kept making network requests while
   the app was in the background.** Android blocks the app's network there, so
   every attempt failed instantly and spent one of the five automatic retries
   (2 s / 10 s / 30 s / 2 min / 10 min); after that an item waited for a manual
   Retry forever — returning to the app ran only items already due, never a
   `needsRetry` one. Once Android froze the app, no timer fired at all, so the
   four videos sat idle from 14:41:47 until the app returned at about 14:48:54.
   A transfer running when the user left was cut off the same way.
2. **CONFIRMED (code): the UI presented a pending automatic retry as a
   failure** — `retryWait` drew "The upload was interrupted. Tap Retry" — and
   drew authorize and confirm as "Uploading N%" (100 % while the server was
   still confirming); after a restart a step persisted as in progress showed
   "Uploading 0%" while nothing ran.
3. **CONFIRMED (device + code): the "blurry images" were video still frames**
   made at 480 px wide, JPEG q75 (the device files are 31–43 KB), drawn
   full-width (~1080 px) in Details and full screen, before and after ready.
4. **CONFIRMED (code): a video still uploading could not be played** — its
   local copy was not passed to the tile (`playable: false`).
5. **CONFIRMED (code): a failed link refresh re-used the link that had just
   failed.** `refreshSignedUrl` returned the item's old URL when the
   re-resolution itself failed, so the retry could only fail again and end in
   "can't be played right now"; each player open also tried the same source
   three times (30/40/50 s timeouts) before any recovery.
6. **UNKNOWN: the exact player error for the owner's failed ready-video
   playback.** The native ExoPlayer error was in the rotated logcat. Codec is
   not a suspect on this phone (it has a hardware HEVC decoder), and the staging
   E2E proved signed GET + 206 range reads. The acceptance session captures it.

### Fixes (local, uncommitted)

- `offer_media_upload_queue.dart`: lifecycle-aware. Nothing starts in the
  background (`hidden`/`paused`/`detached`; `inactive` changes nothing); a
  transport failure in the background, or within 5 s of returning, returns the
  item to waiting without spending a retry (the server answering is never
  treated so); on return and at every start/sign-in, `retryWait` items run at
  once and `needsRetry` items that failed only on the connection are queued
  again (refusals, a full Offer and a missing file are not). New phases:
  `confirming`, `retrying`; an in-progress step nothing is running shows as
  queued. Pending video refs carry their local copy. A completed video's copy
  is retired (it may be playing) and swept at the next queue open; the account
  deletion sweep also removes it by owner prefix.
- `r2_offer_media_upload_service.dart`: fixed-category `cause` on every failure
  (dns, reset, timeout, stalled, no-response, `put-http:<status>`,
  `http:<status>`, bytes sent) — never a URL or provider text.
- NEW `offer_media_diagnostics.dart`: `[offer-media]` log lines per item (last
  six characters of the id; sizes, timings, kbps, states, categories); debug
  and profile builds only.
- `offer_media_selection.dart`: still frames at 1280 px, q85.
- `offer_media_upload_status.dart`: honest labels (waiting / uploading N% /
  finishing / retrying automatically / failed); Retry also on "retrying"
  (skips the wait). Large views draw a strip along the bottom so the preview
  and a pending video's play button stay visible; grid tiles keep the overlay.
- `media_gallery_widget.dart`, `full_screen_media_viewer.dart`: a pending
  video plays from its local copy (never the network); one widget shape for an
  item before and after ready, so local playback continues when the upload
  finishes; private video players open once per source, then the tile signs a
  new link once; poster decoded at screen width.
- `video_player_resource_manager.dart`: `maxAttempts`; a private video's last
  failure kept as a category.
- `offer_details_load_coordinator.dart`: `refreshSignedUrl` returns a link only
  from a resolution that just succeeded.
- `add_offers_viewmodel.dart`: Retry allowed on "retrying" too.
- EN/AR: `offerMediaFinishing`, `offerMediaRetrying`.

Unchanged: the Worker, the database, R2, signed-URL lifetimes (PUT 300 s, GET
900 s), transport timeouts, the ten-item / 10 MB / 100 MB / 3 min limits, the
Owner media path. No multipart: at the measured ~4 s per video there is no
evidence for it. Signed PUT expiry during a slow 100 MB upload remains
unmeasured; a refusal would now be logged as `put-http:403` and retried with a
fresh URL. Existing Offers keep their old 480 px still frames; only new picks
get the sharper ones.

### Verification — CODE_PROVEN

- Targeted: `flutter test test/offers/ test/services/` — 243 PASS (10 new:
  background start, cut-off transfer, grace after return, resume after
  exhausted retries, refused item not resumed, retrying phase, pending video
  local copy, frozen step shown waiting, local playback in the tile, honest
  labels; the video lifecycle test now proves retirement and the sweep).
- Full suite: 703 PASS, 5 FAIL — the same five pre-existing failures (stale
  migration paths from `0d7fb17`), unrelated.
- `flutter analyze` on every changed Dart file: no issues.

### Samsung acceptance — NOT RUN

The feature is not complete until this passes on the device.

NOW — install the updated Debug build on the Samsung (data kept) and run one
session with `adb logcat` capturing `[offer-media]` lines and ExoPlayer errors
(query strings redacted): a fresh Offer with five compliant photos and five
compliant videos; save; watch per-item progress; play a pending video; leave
the app mid-upload and return; reopen Details; confirm all ten reach ready and
every video plays; interrupt with airplane mode and Retry; kill and restart
the app with items pending; replay a ready video after 15 minutes (link
refresh); remove an item; sign in as a second account and confirm it sees
nothing.

NEXT — on a pass, record VERIFIED_REAL_DEVICE here and ask for commit approval;
then start Task B as its own checkpoint.

### Update — ready-video playback: root cause CONFIRMED and fixed

Owner's Samsung session 16:37–16:39 (recorded with the app-scoped logcat):
the ten new items uploaded (hosted database, owner-inspected: all five videos
`ready`, `video/mp4`, linked once), but every ready video failed to play.

Evidence: each tap logged `play` then `play-failed` **6–24 ms later**, and the
resource manager's per-attempt `player-init-failed` line never appeared. No
ExoPlayer instance was created for any tap (no `ExoPlayerImpl: Init` after
16:39) — the video was refused before a player existed or a byte was
requested. The same session proves local playback: the selection probe opened
all five picked files with `VideoPlayerController.file` (Media3 1.9.2; four on
`c2.qti.avc.decoder`, one on `c2.qti.hevc.decoder`), with no player error.

Root cause: `video_player_resource_manager.dart`, `_extensionOf`, used by
`isVideoFormatSupported`, which `OptimizedVideoPlayerWidget._initializeVideo`
calls before `getController`. It read the extension from `_redact(url)`, the
log-safe form that re-appends `?<signature-hidden>`; a signed R2 link
`…/<id>.mp4?X-Amz-…` therefore yielded extension `mp4?<signature-hidden>`,
"unsupported format", thrown in `initState`. A fresh link has the same shape,
so the one automatic refresh failed identically. Local paths (no query) pass,
which is why only network playback failed. Introduced by the URL-redaction
change in baseline `ed78c45` (the previous version stripped the query itself).
The same defect refused any video URL with a query string, including Firebase
token URLs used by Owner media.

Fix: `_extensionOf` cuts the query and fragment from the URL itself. The
format-check refusal and the player's failures now log a stage, error type,
platform error code and a fixed category (`format-refused`, `http:<status>`,
`source`, `codec`, `format`, `timeout` …), never the link.

Regression test: `test/services/video_player_resource_manager_test.dart`
(6 cases; the signed-R2, container and Firebase-token cases FAILED on the
unfixed code and pass now). Offer/service suites: 249 PASS.

No hosted change is required: the Worker signs a correct path-style URL ending
in the object's `.mp4` key, and the staging E2E already proved signed GET 200,
206 ranges, content type and byte identity for the same Worker source.

Remaining: one device reproduction of ready-video network playback on the
fixed build — no local copy of `…ed0dd9` exists any more (swept at restart as
designed), so it also covers the "no local bytes" case.

**VERIFIED_REAL_DEVICE (owner, Samsung, 2026-09-26, build installed 17:15):**
all five ready videos of the new Offer play from Offer Details over the
network (private signed R2 GET); the owner's logs show real network playback
and successful ExoPlayer initialization. The signed-URL extension defect is
closed. The owner then reported two video UX defects (seeking; black poster
for saved videos) and a diagnostics finding — see the next section.

### Video UX — seeking and posters (2026-09-26, CODE_PROVEN, device check pending)

**Seeking — root cause CONFIRMED.** The owner's test videos are portrait
(stills 1280×2276, 9:16; a phone recording's normal shape). A portrait video
fills the height of its page, so Chewie's seek bar sits along the bottom edge,
where the app draws its own overlays on top of the player:
- Offer Details header (280 dp): the gallery's page dots are a `Positioned`
  row 20 dp from the bottom, lying across the seek bar; each dot's decoration
  is hit-testable, so a tap there never reached the bar.
- Full screen: the thumbnail strip (≈140 dp, a horizontally scrolling list)
  covers the bottom of the screen, where a portrait video's seek bar is; its
  list took the drag. Hidden viewer controls were only faded (`Opacity`), so
  they kept taking touches while invisible.
Chewie's own seek bar was not at fault: in the widget tests below, dragging
it seeks correctly when nothing is drawn over it, including in Arabic (RTL:
the bar is drawn and read left to right in both languages, consistently).

Fix: `media_gallery_widget.dart` — the page dots and the counter (indicators
only) are wrapped in `IgnorePointer`, no visual change; "View All" stays
interactive. `full_screen_media_viewer.dart` — hidden top/bottom controls
ignore touches; a private video page is laid out between the measured top bar
and thumbnail strip, so its seek bar and buttons are never underneath them.

**Black posters — root cause CONFIRMED.** A video's still frame was made only
on the device that picked it (and kept locally under its stable media id); the
server stores only the video. At 17:19:26 the app was uninstalled and
reinstalled (package `firstInstallTime` moved from 14:33:27 to 17:19:26 — a
`flutter install`/IDE run, not `adb install -r`), wiping app data; every file
under `offer_media` from before 17:19 was gone. After that, every saved video
had no frame on this device — the same state as a second device.

Fix, client-only, no hosted change: NEW `offer_video_poster_service.dart`
makes the missing frame on demand from the ready video through its private
signed link (`video_thumbnail` → Android `MediaMetadataRetriever`, which reads
only the byte ranges it needs — the index and the first frame — not the whole
video), one at a time, a video requested twice read once, only for the
signed-in account's own media; it keeps the frame under
`offerMediaPosterKey(cacheKey)` (stable, account-scoped id; removed by the
account-deletion prefix sweep and by catalogue reconciliation), deletes the
temporary file, never stores or logs the link, and does not retry a failure
for two minutes. NEW `offer_video_poster.dart` draws the known frame, the kept
one, or a loading surface (the existing `MediaLoadingPlaceholder`) while one
is made, then the frame; used by the Details video tile, the full-screen
thumbnail strip and the Edit-form grid. A durable server-side poster (a
second private R2 object linked through the existing
`media_objects.thumbnail_media_id`) would avoid any per-device read but needs
a Worker change and deployment — not required for the reported defect, not
done, owner decision if ever wanted.

**Diagnostics finding — fixed.** The resource manager's debug lines printed
the redacted link, which still spelled out `profiles/<account>/offers/<offer>/`,
and cache keys, which carry the account id, plus raw player error text. They
now print only a masked name (`network …ed0dd9`: kind and the last six
characters of the media id) and fixed categories or error types; the same for
the three shared debug prints that included a URL or raw error.

Tests: NEW `test/offers/offer_video_playback_test.dart` (4: drag seeks in the
gallery; portrait tap-seek under the page dots and portrait drag-seek under
the full-screen strip — both FAILED before the fix; RTL drag) using a fake
platform player; NEW `test/offers/offer_video_poster_test.dart` (8: made once
and kept under the account-scoped id, reused after a restart without reading
the video, one read for two requests, another account's video never read or
answered, no link no read, failure not retried at once, loading surface then
frame and reopened frame at once, placeholder). Offer/service suites 261 PASS;
`flutter analyze lib test`: 0 errors, 0 warnings.

NOW — one focused Samsung check on the existing Offer: seek by tap and drag in
Details and in full screen; close and reopen; posters of the saved videos.

NEXT — record the result; then Task B (picker and permissions) as its own
checkpoint.

**VERIFIED_REAL_DEVICE (owner, Samsung SM-S928B, 2026-09-26):**
- all five existing videos play;
- video seeking works;
- saved-video thumbnails appear after reopening;
- the signed-R2 video playback defect is resolved.
Interruption and reliability scenarios the owner did not personally verify
are recorded as pending cases `MEDIA-12`…`MEDIA-20` in
`docs/BROKER_WALLET_MASTER_TEST_PLAN_DEFERRED_2026-09-18.md`, not as passed.

## OFFER MEDIA — TASK B: PICKER AND PERMISSION UX (2026-09-26, CODE_PROVEN, device acceptance pending)

OWNER AUTHORIZATION: redesign ONLY the Offer media attachment selection UI
(compact Camera / Gallery / Documents sheet); other screens protected; no
Owner Media change; no hosted change expected.

### Root causes (source-proven)

1. **One video per visit.** The Offer "+" used the shared
   `CleanMediaService.showMediaSelectionDialog`: five rows (camera, video
   camera, gallery, video gallery, documents); "video gallery" called
   `pickVideo` (single). The installed `image_picker` 1.2.3 already provides
   `pickMultipleMedia(limit:)` and `pickMultiVideo`.
2. **Double permission prompt.** Every gallery row first called
   `CleanPermissionService.requestStoragePermissions`, which shows the
   app-made dialog `mediaAccessNeeded` ("الحاجة لإذن الوسائط") and then
   requests `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` — Android's "select photos /
   allow all / don't allow" screen — although picking needs no library
   permission at all. `image_picker_android` 0.8.13+19 defaults
   `useAndroidPhotoPicker = false` (it launched `ACTION_GET_CONTENT`).
3. **Camera.** An app-made pre-dialog before the system camera prompt, and a
   microphone request for video (not declared in the manifest, so always
   refused, with a misleading "recorded without audio" warning — the camera
   app records sound itself).

### Implementation (Offer only)

- NEW `lib/src/services/offer_media_picker.dart` (`OfferMediaPicker`):
  Gallery = `pickMultipleMedia(limit: remaining)`, photos and videos in one
  native selection, images at the existing 1920 px / q85; on Android the
  system **Photo Picker** is switched on for that call only (the flag is
  restored, so Owner/profile/Toolkit pickers are unchanged) — no app dialog,
  no media-library permission request. Camera = `pickImage`/`pickVideo`
  (3 min cap) through the system camera; `image_picker_android` asks the
  camera permission itself with the system dialog (required because the app
  declares CAMERA); `camera_access_denied` is mapped to denied / permanently
  denied (status read only, no request). `retrieveLostData` recovery.
- NEW `lib/src/views/Widgets/offer_media_source_sheet.dart`: bottom sheet with
  drag handle, title, "You can add N more", three tiles — **Camera** (then
  Photo / Video inside the sheet, with Back), **Gallery**, **Documents** shown
  as "Not available for offers yet" (disabled; secure Offer documents remain
  Task C). Theme colours and text styles only (brand primary tint), light
  and dark, EN/AR, RTL, 48+ dp targets, semantics labels.
- `add_offers_viewmodel.dart`: `selectMedia` uses the sheet and the picker;
  NEW `addPickedOfferMedia` skips files already in the form (same name and
  size as a picked or queued item), then the unchanged
  `screenOfferMediaSelection` (10-item limit, size caps, real type, duration,
  HEIC→JPEG, lasting `mediaObjectId`); drafts go to the unchanged upload queue
  on Save (durable copy there). Cancel changes nothing; camera refusal shows
  the existing localized message, permanently denied offers Open Settings;
  lost picks are recovered when the form opens. The hard-coded English
  "Added N file(s)" toast is replaced by a localized one.
- EN/AR strings for the sheet, results and picker failure.
- `ios/Runner/Info.plist`: camera, photo library and microphone purpose
  strings now describe the real use (profile and Offer photos/videos).
- Unchanged: `CleanMediaService`, `CleanPermissionService` (Owner, profile,
  Toolkit, map keep their flows), manifest permissions (READ_MEDIA_*,
  MANAGE_EXTERNAL_STORAGE and others are used by other features — recorded
  for the release audit, not removed here), queue, Worker, database.

### Verification — CODE_PROVEN

- NEW `test/offers/offer_media_picker_test.dart`: 21 PASS — one mixed
  selection with the remaining limit and no permission call; Photo Picker on
  for that call only; full Offer opens nothing; camera photo and 3-min video
  with no app permission call; camera denied / permanently denied; lost-data
  recovery; five videos in one selection; mixed kinds; capacity re-checked
  whatever the picker returned; duplicate skipped and invalid file refused;
  distinct lasting ids for the queue; sheet dismiss / picker cancel change
  nothing; Gallery flow with no dialog and one localized confirmation;
  camera flows; permanently denied offers Settings; the sheet's three
  actions, camera sub-choice and Back, Documents disabled (semantics), Arabic
  RTL order, dark theme and a 320 dp phone with no overflow.
- Full suite: 742 PASS, 5 FAIL (the same five pre-existing stale migration
  path failures). `flutter analyze lib test`: 0 errors, 0 warnings.
- Not device-verified: Photo Picker behaviour on the Samsung, camera prompts,
  lost-data recovery.

NOW — install the Debug build with `adb install -r` (keeps data) and run the
Task B acceptance: + once → Gallery → five videos in one selection → five
previews; mixed photos/videos in one selection; save and reopen; no
double-permission dialog; Camera photo and video.

NEXT — record the result; then reconcile the final Offer media checkpoint.

### Task B device result and final corrections (2026-09-27)

**VERIFIED_REAL_DEVICE (owner, Samsung):** the combined Gallery picker selects
five videos and five images in one operation. Kept as is.

**P0 — "A VideoPlayerController was used after being disposed" — root cause
CONFIRMED.** `VideoPlayerResourceManager` shared controllers by video but did
not know who used them: to open a video beyond its two-player limit it
disposed the oldest paused controller, and a newer link of a video disposed
the older controller — even when a mounted player still showed it. Offer
Details keeps its paused player mounted under full screen, so playing a third
video in full screen disposed the controller Details still held; its next
play/seek raised the error (Flutter's `ChangeNotifier` assertion). Proven
directly: with the old manager, opening three videos and then playing the
first threw exactly that error (probe run, 2026-09-27). The device stack
trace itself was not available to the agent (the debugger console, not
logcat); the failing operation is identified by reproduction, not by the
owner's trace.

Fix — `video_player_resource_manager.dart`: each player entry counts its
holders; `getController` hands out a held controller, `release` gives it back
(new API); a controller is disposed only when nothing holds it (making room
takes idle players only, least recently used; at most one idle player is
kept; an idle player of an outdated link is dropped); a disposed controller
is removed before disposal and never handed out again; two requests for the
same video while it starts share one platform player. `media_gallery_widget
.dart` (`OptimizedVideoPlayerWidget`, the only acquirer): disposes its Chewie
controls, then releases its controller in `dispose`; releases a controller
that arrives after the widget was closed; releases before a Retry. Widgets
never dispose controllers.

**Camera — owner-approved correction.** The Camera → second Photo/Video sheet
is removed. Tap + → Camera now opens the Offer media camera directly, with its
own Photo / Video switch. Android's system capture intents return either a
photo or a video, never "whichever the user picked", so this needs an in-app
camera: **owner approved adding flutter.dev's official `camera` 0.12.1**
(adds only `camera`, `camera_android_camerax` 0.7.5, `camera_avfoundation`,
`camera_platform_interface`, `camera_web`; no existing package changed; no
SDK change). NEW `lib/src/views/Widgets/offer_media_camera.dart`: back camera,
Photo / Video switch (locked while recording), shutter, switch camera,
recording timer with automatic stop at the 3-minute limit, 1080p video at
4 Mbit/s + 128 kbit/s audio (≈ 93 MB for 3 minutes, under the 100 MB limit),
photos at 1080p; camera and microphone asked once by the system dialog when
the camera starts (plugin-requested; no app-made dialog); a refused
microphone records silently with a note; a refused camera shows a localized
message with Open Settings and Retry; the camera is released in the
background and a recording in progress is finished and kept. The result is
screened and queued exactly like a Gallery pick. The sheet's Camera tile
closes the sheet and opens this screen; Gallery is unchanged.
`AndroidManifest.xml`: the CameraX plugin merges CAMERA and RECORD_AUDIO; its
WRITE_EXTERNAL_STORAGE `maxSdkVersion=28` conflicted with the app's 29, so the
app's declaration gains `tools:replace="android:maxSdkVersion"` (the app's
value is kept; nothing else changed). The picker service keeps only Gallery
and lost-data recovery (its image_picker camera path was removed).

Tests: NEW `test/offers/offer_video_lifecycle_test.dart` (11: held player
never evicted — the device crash; idle player makes room and a disposed
controller is never returned; one video shared and disposed after its last
holder; newer link leaves the shown player; concurrent start opens one
player; double/unknown release harmless; full screen over Details with three
videos then back, Details player still usable; repeated switching in Details
with the live count bounded; full screen opened/closed repeatedly; leaving
while a player starts releases it; every platform player freed). NEW
`test/offers/offer_media_camera_test.dart` (8, fake platform camera: opens on
the back camera with the switch and returns a photo; video start/stop with
timer and switch locked; automatic stop at the limit; switch lens releases
the first; refused camera → Settings/Retry; refused microphone → silent
video; close returns nothing; Arabic/RTL). `offer_media_picker_test.dart`
updated (Camera opens straight away; closing the camera changes nothing;
Camera closes the sheet with no second sheet). Full suite: 759 PASS, 5 FAIL
(the same pre-existing stale migration paths). `flutter analyze lib test`:
0 errors, 0 warnings. The generated plugin registrants show as modified with
no content change (line endings); not edited, not for commit.

Test-harness note: `VideoPlayerController.dispose()` completes only when real
time passes; widget tests that make the manager dispose a player therefore
interleave a real-time moment between frames.

Device note: the app was not installed on the phone at 20:57 on 2026-09-27
(`run-as` reported the package unknown); the build was installed fresh, then
updated with `adb install -r` (first-install time kept). The owner signs in
again; the Offer's media is on the server.

NOW — Samsung acceptance: open the Offer with five images and five videos,
play and switch videos repeatedly, open/close full screen, pause, seek,
reopen — no disposed-controller error; + → Camera opens the camera directly
with Photo / Video inside it; take a photo and record a video; Gallery still
selects several items without permission dialogs.

NEXT — record the result; then the final Offer media checkpoint
reconciliation.

### Source review — recorded-video size and player lifecycle (2026-09-27)

Working model from 2026-09-27: the owner builds, installs, runs and tests the
app. Agents do not run Flutter build/run/test/analyze, APK, adb or emulator
operations unless the owner authorizes that single operation. The test and
analyzer results above are the previous session's reports; not re-run.

Status: SOURCE REVIEWED / PENDING_OWNER_DEVICE_ACCEPTANCE. No behaviour
changed in this review.

- Recorded-video size — enforced. CameraX's `stopVideoRecording` returns
  only after the Finalize event, for a manual and an automatic stop alike
  (both go through `_stopRecording` → `_finish`). The file then takes the
  Gallery path: `selectMedia` → `addPickedOfferMedia` →
  `screenOfferMediaSelection` → `OfferMediaPolicy.check`, which reads the
  file's real length and refuses more than 100 MiB (`offerMediaVideoTooLarge`,
  English and Arabic), then more than 3:01 (`offerMediaVideoTooLong`). The
  "≈ 93 MB" above is the encoder's target, not a guarantee; the camera
  screen's comments now say so (comment-only change).
- Player lifecycle — no defect found. Held controllers are never evicted or
  replaced; a disposed entry is removed before disposal and is never returned
  (including an entry disposed while a request was joining it); concurrent
  requests share one open; a widget closed mid-open releases what arrives;
  a newer signed link is a new keyed player and the old one is disposed once
  idle; Chewie is disposed before the release and never disposes the
  controller; at most one idle player remains.
- Backlog only (not the Offer path, pre-existing since `ddb20a6`): the legacy
  `mediaUrls` full-screen viewer disposes its own controllers in `dispose` and
  then pauses them in a post-frame callback, which can raise the same
  "used after being disposed" assertion in debug builds for non-Offer videos.

NOW — owner's Samsung acceptance (unchanged; see NOW above).

NEXT — record the result; then the final Offer media checkpoint
reconciliation.

### Camera reverted to the system camera (2026-09-27)

**Owner device result (Samsung):** the in-app camera crashed right after the
permission grant — `PlatformException(IllegalStateException,
releaseFlutterSurfaceTexture() cannot be called if the flutterSurfaceProducer
for the camera preview has not yet been initialized.)` from
`camera_android_camerax` (`PreviewProxyApi.releaseSurfaceProvider`).
**Owner decision:** no in-app camera, not to be fixed; Broker Wallet uses the
phone's own camera app, as before. The approval of the `camera` package is
withdrawn.

Removed: `lib/src/views/Widgets/offer_media_camera.dart`,
`test/offers/offer_media_camera_test.dart`, the `camera` dependency
(`pubspec.yaml`) and its five lock entries (`camera`,
`camera_android_camerax`, `camera_avfoundation`, `camera_platform_interface`,
`camera_web`; nothing else imported them), and the manifest's
`xmlns:tools` / `tools:replace` added only for that plugin.
`pubspec.yaml`, `pubspec.lock` and `AndroidManifest.xml` now equal `HEAD`
again, so CAMERA (declared by the app for the scanner) and the app's
storage permissions are unchanged, and the plugin's RECORD_AUDIO is gone
from the merged manifest.

Restored (the pre-camera code, from the previous session's record):
`OfferMediaPicker.capturePhoto` = `pickImage(source: ImageSource.camera)`
at 1920 px / q85, `recordVideo` = `pickVideo(source: ImageSource.camera,
maxDuration: 3 min)`; `image_picker_android` asks for CAMERA with the system
dialog (no app-made dialog, no microphone request); `camera_access_denied`
→ the existing localized toast, or, when refused for good, a snackbar with
Open Settings (status read only). `selectMedia` → `addPickedOfferMedia` →
`screenOfferMediaSelection`, the same path as Gallery: real size, type from
bytes, duration, HEIC→JPEG, 10-item limit, lasting id, upload queue on Save,
`retrieveLostData` recovery; cancel changes nothing.

Sheet (owner-specified): three sections in one row — **Camera** with two
small direct actions, **Take photo** and **Record video** (each closes the
sheet and opens the system camera at once; no second sheet or popup),
**Gallery** (unchanged combined Photo Picker selection), **Documents**
(still unavailable for Offers). Theme colours only, EN/AR, RTL, 48 dp
actions, one shared tile height. Strings: + `offerMediaCameraRecordVideo`;
`offerMediaCameraTakePhoto` kept; nine strings used only by the custom
camera or the old Photo/Video sub-step removed.

Tests (source only, NOT run — owner runs them): `offer_media_picker_test.dart`
— system-camera photo and 3-minute video with no app permission call;
refused / refused-for-good; photo then video added; leaving the camera
changes nothing; an invalid camera file refused with its message; refused for
good shows Open Settings; sheet has Take photo / Record video, each direct,
with button semantics; Arabic label present in the RTL/dark/320 dp case.
`dart format --output=none` on the three new/rewritten files: clean. No
build, test, analyzer, adb or device operation was run.

Status: SOURCE ONLY / PENDING_OWNER_DEVICE_ACCEPTANCE. The video player
lifecycle fix is still pending the owner's device confirmation (not reported
in this round). Gallery combined selection remains VERIFIED_REAL_DEVICE and
its code is unchanged.

NOW — owner: `flutter pub get`, build, install and check + → Take photo,
+ → Record video, refusing the camera once, cancelling, and Gallery.

NEXT — record the result; then the final Offer media checkpoint
reconciliation.

## OFFER PRIVATE MEDIA — OWNER ACCEPTANCE AND COMMIT CANDIDATE (2026-09-27)

**VERIFIED_REAL_DEVICE (owner, physical Samsung, 2026-09-27).** The owner
accepted Offer Media's core implementation after manual acceptance of:

- image and video selection;
- one combined Gallery selection of several videos and images;
- photo and video capture through the phone's own Samsung camera app
  (`image_picker`), with no custom CameraX screen;
- no redundant Gallery permission popup;
- saving and reopening Offers with media;
- private video playback, video seeking and persisted video thumbnails;
- switching between videos with no disposed-controller exception;
- the Offer media interface in its accepted state.

This closes the "pending" device checks of the Task B, player-lifecycle and
camera-revert sections above. Nothing else is promoted: `MEDIA-12`…`MEDIA-26`
in the deferred master test plan stay NOT RUN.

| Item | Status |
| --- | --- |
| Offer media core (Tasks A and B) | ACCEPTED — VERIFIED_REAL_DEVICE (the items above) |
| Supabase `confirm_offer_media_upload` | APPLIED + VERIFIED_HOSTED. Repository file `supabase/migrations/20260926092220_offer_media_confirm_rpc.sql` carries the hosted version; sha256 `3aad4199…c6e8e1`, unchanged since the tracking reconciliation |
| Production Worker `r2-profile-upload` | `ecaf125d-a0e3-4c26-add6-5f2c684c2516` (owner-reported), `OFFER_MEDIA_SWEEP_MODE=off`, rollback `bacad8d6-b7e2-434b-88e4-965c91c82874`. Working-tree `worker.js` sha256 = `94b3ca4a…`, the recorded deployed source |
| Staging Worker `r2-profile-upload-staging` | `ab42e479-…`, 72/72 PASS (VERIFIED_HOSTED); its test Offers and 20 staging objects are retained |
| Flutter tests | Not run by the agent after the camera revert. The last full-suite report (759 PASS / 5 FAIL) predates the revert and included the since-removed camera tests |
| Task C — private Offer documents | DEFERRED |
| Owner Media | ACTIVE since 2026-09-28 (see the next section) |

**Known failing tests (not fixed here; never report them as passing).** Five
tests read migration files by the names `0d7fb17` changed:
`test/account/delete_account_test.dart` (1: `20260913000100_…`, now
`20260913175221_…`) and `test/auth/phone_security_hardening_test.dart`
(4: `20260911000100_…` and `20260911000200_…`, now `20260911181050_…` and
`20260911181112_…`). Checked on 2026-09-27: the old paths are still in both
files.

**Backlog, outside the accepted Offer path.** The legacy `mediaUrls`
full-screen viewer (non-Offer media) disposes its own controllers and then
pauses them a frame later, which can raise "used after being disposed" in
debug builds (since `ddb20a6`; `MEDIA-26`). The Offer-media sweeps stay `off`
until an owner-approved dry run (`MEDIA-25`). iOS has not been exercised
(`MEDIA-24`).

**Committed and pushed.** The owner approved the 62-file candidate (38
modified, 24 new) and it was committed as `06cd3964bc726be00ebcfc6f6cdc2d5451125dca`
"feat(offer-media): complete private offer media lifecycle, picker and
playback" on `feature/offer-private-media`; the owner pushed it. Checked
2026-09-28 from the Git refs: the local branch and
`origin/feature/offer-private-media` both point at `06cd396`. Excluded from
it, and still excluded: generated plugin registrant files whose only
difference is line endings. (The baseline `ed78c45`, recorded in the
Phase 2 section as "not pushed", is also on origin now.)

Offer Media is closed; its deferred scenarios stay in the master test plan.
Owner Media is the active checkpoint (next section).

## OWNER PRIVATE MEDIA — ACTIVE CHECKPOINT (2026-09-28)

**Owner decision (2026-09-28):** Owner media follows the Offer media rules —
photos and videos only; at most 10 per Owner record; photos ≤ 10 MiB after
HEIC → JPEG; videos ≤ 100 MiB and ≤ 3:00; Documents shown but unavailable; a
soft-deleted Owner's media kept 7 days, its cleanup sweeps off until the owner
approves them. The same attachment UX as Offers: system camera (Take photo /
Record video), one combined Gallery selection, no app-made permission dialog.

**State found (source, 2026-09-28).**

- Database: `public.owner_media` (owner_record_id → owners, media_id →
  media_objects, role, ordinal, unique (owner_record_id, role, ordinal)) with
  RLS select-own (`owns_owner_record`), the `owner_media_validate_owner`
  ownership trigger and an index already exist (baseline migrations). No
  confirm function existed for Owners.
- Worker: Offer routes only; no Owner routes.
- Flutter: in Supabase mode, Owner media upload was switched off
  (`saveOwnerWithMediaFast` threw when files were attached); the Owner form
  used the legacy `CleanMediaService` dialog; Owner Details showed only legacy
  Firebase `mediaUrls` (always empty in Supabase mode); Edit never uploaded.

**Backend change (source written, NOT applied, NOT deployed).**

- `supabase/migrations/20260928100000_owner_media_confirm_rpc.sql`:
  `public.confirm_owner_media_upload(...)`, the line-for-line Owner
  counterpart of `confirm_offer_media_upload` (lock on the Owner row, per-bucket
  limit, append ordinal, idempotent, key prefix `profiles/<uid>/owners/<id>/`,
  outcome `owner_not_found`, 100 MiB ceiling, `SECURITY DEFINER`, empty
  search_path, service_role only). No table, RLS, index or trigger change.
  With `supabase/tests/owner_media_confirm_test.sql` (pgTAP, 27) and
  `supabase/validation/owner_media_confirm_validation.sql` (rollback-only,
  installs the exact migration text, ends in `ROLLBACK`). Not executed against
  any database yet. The hosted version number is whatever the owner's apply
  records; reconcile the file name to it afterwards, as for Offers.
- `cloudflare/workers/r2-profile-upload/worker.js`: the Offer media handlers
  are now generalized over a `MEDIA_PARENTS` descriptor (Offer, Owner) and
  serve `POST /owner-media/authorize`, `POST /owner-media/confirm`,
  `GET /owner-media?ownerRecordId=`, `POST /owner-media/remove`; Owner sweeps
  (`runOwnerMediaSweeps`) behind their own `OWNER_MEDIA_SWEEP_MODE` (added
  `"off"` to both `wrangler.toml` environments). Offer requests, responses,
  error codes and sweep reports are unchanged. The working-tree `worker.js` is
  therefore no longer the deployed production source (`94b3ca4a…`).
- Worker tests: new `test/owner_media.test.mjs` (13). **`npm test` run
  locally by the agent (Node, no deployment): 116 PASS, 0 FAIL** — the 103
  existing (Offer media, account deletion, staging gate) plus the 13 Owner.

**Flutter (source written, not built or run).**

- Shared, not copied: `MediaParent` (Offer/Owner routes, id field, limit,
  record-named messages); `R2OfferMediaUploadService(parent:)`; ONE upload
  queue whose tasks record their parent (an Owner task persists `parent`, an
  Offer task is stored exactly as before; per-parent transport, listing,
  blocking, forgetting and completion events; one box, one directory, one
  retired-copy sweep, one account purge); `SupabaseCoreEntitiesService`
  `cachedOwnerMedia` / `resolveOwnerMedia` (the Offer logic, extracted and
  shared); the device catalogue keyed by record id; the sheet (Documents hint
  per record), picker, screening, gallery, video tile, posters, full screen.
- `OwnerService`: `saveOwnerWithMedia` (row first, removals through the Owner
  routes, cancellations, new items queued as Owner media), media API
  (`PrivateMediaStore`), Owner delete forgets its queued items and local
  copies.
- NEW `PrivateMediaForm` (the Offer form's media behaviour for any record) used
  by `AddOwnersViewModel` in Supabase mode: sheet, system camera, combined
  Gallery, screening, remove/retry, lost-data recovery, limit re-check at Save,
  honest per-item outcomes; Edit loads the Owner's media and returns the saved
  Owner (with its id) to Details. The legacy Firebase Owner flow is unchanged.
- NEW `PrivateMediaGalleryLoader` for Owner Details: cached → queued →
  server list, signed-link refresh for video, revoked access cleared; the
  header shows the private gallery when there is media, the compact header
  otherwise (unchanged for Owners without media), a retry state on failure.
- 7 EN/AR strings (`ownerMedia…`, `ownerSaved…`, `ownerUpdated…`).
- Offer contract test updated to read the Worker's Offer descriptor (the
  refactor moved the text it checked); NEW `test/owners/owner_media_test.dart`
  and `test/owners/owner_media_confirm_contract_test.dart`. Flutter tests NOT
  run (owner-run).

**Security.** Ownership stays server-side: every Owner route verifies the
signed-in account owns the live Owner record; media keys name the parent, so
an Offer's media (or another Owner's) is refused on the Owner routes and vice
versa (`media_mismatch` / `idempotency_mismatch`, Worker-tested); the
database function refuses media outside the Owner's key prefix; account B
gets 404 and nothing is revealed; no signed URL is stored; no credential in
Flutter; no RLS change. Account deletion already sweeps `profiles/<uid>/`
(Owner keys included) and the queue purge covers Owner tasks.

**Deploy order (all owner actions):** validation script (SQL Editor,
rollback-only) → apply the migration → staging Worker deploy + Owner E2E →
production Worker deploy → Samsung acceptance.

**Backend handoff review (2026-09-28, source only; no hosted access, no
test run).** Reviewed files (sha256 of the bytes on disk, all LF):
migration `20260928100000_owner_media_confirm_rpc.sql` `059e31c7ab5ff929…6c4fbb`,
validation `867405230facbdc4…c73e7444`, pgTAP `df21b80bed368e37…5a5df8f84`;
`worker.js` (CRLF throughout) `241d367b220e91a5…fb8ea374`. The validation's
embedded install is byte-identical to the migration with only its `begin;` /
`commit;` lines removed; the script has one `begin;`, no `commit`, ends in
`rollback;`, and contains no non-transactional statement. The only effect a
ROLLBACK cannot undo would come from a database event trigger fired by its
DDL that advances a sequence (pg_graphql's schema-version counter, if
installed: a cache counter, no data); PostgREST's `pg_notify` and any
pg_net webhook are delivered only on commit, so they are discarded. The
hosted triggers and event triggers were not read (no hosted access); the
owner can list them read-only first. No blocker found; no source change.
Open, NOT accepted:

- The Worker's inline abandoned-upload cleanup
  (`bestEffortCleanupAbandonedPending`, already deployed for profile and Offer
  authorize) is account-scoped but parent-agnostic: an Owner authorize can
  remove the same account's `pending_upload` rows older than 24 h under any
  key (Offer, Owner, profile), and an Offer authorize an Owner's. Never
  another account's, never ready/failed/recent rows; the app re-authorizes
  under the same id.
- Android lost picker data: `retrieveLostData` carries no origin, and both
  the Offer form and the Owner form adopt it on open, so a photo or video
  recovered after Android killed the app lands as a draft in whichever
  Offer/Owner form (any record, and possibly another signed-in account on the
  same device) opens first; it is attached only if that form is saved.

The Worker suite was run once (116/116) before the owner's instruction not to
run Worker tests without authorization; it has not been run since.

**Owner's hosted read-only inspection (reported by the owner, 2026-09-28):**
the required `owners` / `owner_media` / `media_objects` columns, the Owner
media uniqueness constraint, the enabled `owner_media_validate_owner`
trigger, the Owner/media SELECT policies and `confirm_offer_media_upload` are
present; `confirm_owner_media_upload` is NOT installed and `20260928100000`
is NOT in the hosted migration history; relevant table/event triggers
inspected; nothing modified. (Owner-reported; not re-read by the agent.)

**Pre-deploy corrections F1 and F2 (owner-approved, 2026-09-28): SOURCE
WRITTEN, NOT RUN — no build, test, analyzer, Worker test, migration or
deployment.** The reviewed SQL is unchanged (same three hashes as above).

- F1 — abandoned-upload cleanup per entity. `worker.js`:
  `bestEffortCleanupAbandonedPending(userId, env, scope)` now selects only
  the entity's own keys, in the query itself, and re-checks each row's exact
  key before deleting: `profileCleanupScope` (`/authorize`: the account's
  `profiles/<uid>/<id>.<ext>` keys, `like` plus `not.like …/*/*`) and
  `parentCleanupScope` (Offer/Owner authorize: `profiles/<uid>/<segment>/<recordId>/`).
  Same 24 h cutoff, 10-row batch, account and bucket filters; sweeps and
  account deletion untouched; both sweep modes still `off`. New
  `worker.js` sha256 `3b16d8e6aa893833…0b54f92af` (CRLF; LF-normalized
  `2344b330fb72cc33…570b1977a`). Regression source: 4 new tests in
  `test/owner_media.test.mjs`; the Offer and Owner test fakes learned
  `not.` filters.
- F2 — lost picker result goes back to its own form only. NEW
  `lib/src/services/media_pick_recovery.dart` (`MediaPickOrigin`,
  `MediaPickRecovery`); `OfferMediaPicker` records the form's origin before
  each Gallery/camera launch and clears it on return, and recovers only via
  `take(origin)`; the Offer form and the shared Owner form pass their origin
  (account, Offer/Owner, record id or per-form session); `main.dart` routes
  Android's result once at start-up (`MediaPickRecovery.reconcileAtStartup()`,
  Android only, non-blocking). Picker, camera, combined Gallery, screening
  and the upload queue are otherwise unchanged. A pick lost while adding a
  NEW Offer/Owner is no longer recovered (its form does not survive the
  restart). Regression source: NEW `test/offers/media_pick_recovery_test.dart`;
  `test/offers/offer_media_picker_test.dart` updated to the origin API plus a
  cross-form test.
- Device/hosted verification pending: `MEDIA-33` (F1, staging) and `MEDIA-34`
  (F2, Samsung) in the master test plan.

NOW — superseded by the staging preparation section below (the owner ran the
checks, the validation and the migration).

NEXT — see that section's own NOW/NEXT.

## OWNER PRIVATE MEDIA — HOSTED MIGRATION RECONCILED, STAGING PREPARED (2026-09-28)

This completes the preparation an earlier agent session could not finish: its
shell tools were blocked by a Claude Code permission-classifier failure (a
session problem, not a repository, Git, Supabase or Cloudflare one). Nothing
was deployed, applied, committed or pushed here, and no Flutter, Worker-test,
adb or hosted-SQL command was run by the agent.

**Owner-run results (owner-reported; not re-run by the agent).**

- Worker suite (`npm test`, including the F1 regressions): 120/120 PASS.
- Targeted Flutter suite: 60/60 PASS.
- `flutter analyze`: no errors or warnings; 113 informational findings.
- Hosted rollback-only `supabase/validation/owner_media_confirm_validation.sql`:
  34/34 PASS; its temporary results table does not exist afterwards.
- The migration was applied through Supabase's migration interface and read
  back independently. Registered version:
  `20260928131828_owner_media_confirm_rpc`. `confirm_owner_media_upload`
  exists, `SECURITY DEFINER`, owner `postgres`, empty `search_path`; EXECUTE
  denied to PUBLIC, `anon` and `authenticated`, allowed to `service_role`;
  `confirm_offer_media_upload` preserved. **APPLIED + VERIFIED_HOSTED
  (owner-verified). Do not apply it again.**

**Repository reconciled to the hosted version.**

- `supabase/migrations/20260928100000_owner_media_confirm_rpc.sql` renamed to
  `supabase/migrations/20260928131828_owner_media_confirm_rpc.sql` (an
  untracked file, so a plain rename). SHA-256 before and after:
  `059e31c7ab5ff9296aca7d8cd76eb8c17fbb6a5e66175b6b3da5b4f42d6c4fbb` (8,258
  bytes, LF): the reviewed bytes, unchanged.
- `test/owners/owner_media_confirm_contract_test.dart` reads the new path (one
  line).
- `supabase/validation/owner_media_confirm_validation.sql` is kept byte for
  byte as it was run (`867405230facbdc4…c73e7444`); its stage labels still
  name `20260928100000`, the file name when it passed.
  `supabase/tests/owner_media_confirm_test.sql` is unchanged
  (`df21b80bed368e37…5a5df8f84`).

**Worker candidate (unchanged since F1).** `worker.js` sha256
`3b16d8e6aa893833ea65626eb6ec843fa2f18670ed1bd085cd5572f0b54f92af` (CRLF;
LF-normalized `2344b330fb72cc331bb9627856e4a2f1d164a5c32c36d6f24ddcddf570b1977a`);
`wrangler.toml` sha256
`3de84126b7ccdd1b8fb7d2bbd60f48bfd8e229fea18690a48b3a46216659b0e0` (CRLF;
LF-normalized `1d5aedd9dad48b8fd759a527a9b9d09a06c688d3bdd2f7bab1cd94bb897320e1`).
Both environments set `OFFER_MEDIA_SWEEP_MODE = "off"` and
`OWNER_MEDIA_SWEEP_MODE = "off"` (a missing or unknown value is also off in
`worker.js`). Buckets: production `broker-wallet-media`, staging
`broker-wallet-media-staging`.

**Cloudflare, read first-hand (wrangler 4.136.3, read-only, 2026-09-28).**

- Staging `r2-profile-upload-staging` serves
  `ab42e479-7ff2-445e-8e7e-08b945c9b4a6` (tag `op2-94b3ca4a`, the Offer
  Phase 2 candidate) at 100%: fetch and scheduled handlers, compatibility
  date 2024-11-01 with `nodejs_compat`; `MEDIA_BUCKET` →
  `broker-wallet-media-staging`, `R2_BUCKET_NAME`
  `broker-wallet-media-staging`, `OFFER_MEDIA_SWEEP_MODE` `"off"`,
  `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `R2_S3_ENDPOINT`,
  `ALLOWED_ORIGIN`; secret names `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
  `STAGING_TEST_KEY`, `SUPABASE_SECRET_KEY` (values never read). The live
  version predates the Owner routes and has no `OWNER_MEDIA_SWEEP_MODE`
  binding. The version before it is `d6e8fdb4-da48-43e4-b4cc-803fe8f204db`.
- **Rollback target for the Owner staging deploy:
  `ab42e479-7ff2-445e-8e7e-08b945c9b4a6`.**
- Staging gate, probed without credentials: preflight 204; `GET /owner-media`
  without a key 403, with a wrong key 403; `POST /owner-media/authorize`
  without a key 403.
- Bucket `broker-wallet-media-staging`: r2.dev public access disabled, no
  custom domains, no CORS rules; 39 objects, 40.4 MB (the retained Offer test
  data).
- Production `r2-profile-upload` serves
  `ecaf125d-a0e3-4c26-add6-5f2c684c2516` at 100%: untouched.

**Staging acceptance runner (new, in the repository; not run).**
`cloudflare/workers/r2-profile-upload/staging-acceptance/`:
`owner_media_staging_acceptance.mjs` (Node built-ins only; outside
`npm test`'s discovery), the launcher `run_owner_media_staging_acceptance.ps1`
(masked input, clears its environment afterwards), `README.md`, the three
synthetic fixtures from the Offer staging run, and a `.gitignore` for
`reports/`. It covers the gate, Owner authorize, private PUT, confirm,
listing, signed GET, video range reads, removal, idempotency and retry, the
ten-item limit, cross-account and cross-parent isolation, a focused Offer
regression, a non-destructive profile regression (it never confirms a
profile image) and F1 in two phases: `-Mode Full` seeds abandoned uploads on
two Owners, one Offer, the profile image and account B's Owner;
`-Mode F1Verify`, at least 24 h 10 min later, proves each authorize withdraws
only its own entity's (`MEDIA-33`). Fresh disposable accounts and records
only; it logs statuses, codes and ids, never credentials, account ids, object
keys or URLs. Only `node --check` and a PowerShell parse were run on it.

**Owner commands (not run by the agent).** From
`cloudflare/workers/r2-profile-upload`:

1. `(Get-FileHash worker.js -Algorithm SHA256).Hash` → `3B16D8E6…0B54F92AF`.
2. Dry run: `npx wrangler@4.136.3 deploy --env staging --dry-run`.
3. Deploy: `npx wrangler@4.136.3 deploy --env staging --tag om1-3b16d8e6
   --message "Owner media staging candidate (worker.js sha256 3b16d8e6)"`.
4. Verify: `npx wrangler@4.136.3 deployments status --env staging`, then
   `npx wrangler@4.136.3 versions view <new version id> --env staging` (both
   sweep variables `"off"`, the four secret names, the staging bucket).
5. Rollback if needed: `npx wrangler@4.136.3 rollback
   ab42e479-7ff2-445e-8e7e-08b945c9b4a6 --env staging --message "Roll back
   Owner media staging candidate"`.

| Item | Status |
| --- | --- |
| `confirm_owner_media_upload` | APPLIED + VERIFIED_HOSTED (owner), version `20260928131828`; repository file renamed to match |
| Worker candidate `3b16d8e6…` | CODE_PROVEN (owner-run suite 120/120); NOT DEPLOYED |
| Staging Worker | `ab42e479-…` (Offer candidate), verified first-hand |
| Production Worker | `ecaf125d-…`, untouched |
| Owner staging acceptance | runner prepared; NOT RUN |
| F1 (`MEDIA-33`) | NOT RUN (runner phase 1 + phase 2 prepared) |
| Flutter Owner media | owner-run tests/analyzer reported clean; NOT DEVICE-VERIFIED (`MEDIA-27`…`MEDIA-32`, `MEDIA-34`) |

NOW — superseded by the deployment section below (staging and production
deployed, staging acceptance passed).

NEXT — see that section's own NOW/NEXT.

## OWNER PRIVATE MEDIA — DEPLOYED, STAGING ACCEPTED, LOCAL COMMIT (2026-09-28)

**Owner-reported (not re-read by the agent; no Cloudflare or Supabase access
in this step).**

- Staging Worker `r2-profile-upload-staging`:
  `ac033060-5cbf-4b9c-8932-592bd88ab6ef` (previously `ab42e479-…`).
- Production Worker `r2-profile-upload`:
  `6387e2c0-db49-43eb-a0e0-edaca76e3e5e`. Rollback target
  `ecaf125d-a0e3-4c26-add6-5f2c684c2516`, the version production served
  before this deployment (read first-hand in the preparation section above).
- Both deployed from the `worker.js` candidate sha256
  `3b16d8e6aa893833ea65626eb6ec843fa2f18670ed1bd085cd5572f0b54f92af`.
- Production smoke tests: PASS (the individual checks were not supplied).
- `OFFER_MEDIA_SWEEP_MODE` and `OWNER_MEDIA_SWEEP_MODE`: off in both
  environments, as `wrangler.toml` ships them.
- Worker suite 120/120 and targeted Flutter suite 60/60, as recorded above.

**Staging acceptance — PASS (`VERIFIED_HOSTED`; owner-run, report read by
the agent).** Runner `staging-acceptance/`, `-Mode Full`, run
`20260928T144750Z` (14:47:50–14:51:20 UTC), two fresh disposable accounts:
**126 PASS, 0 FAIL** — gate 5, setup 9, database 2, owner-authorize 5,
owner-image 12, owner-video 6, owner-retry 12, owner-refuse 9, owner-limit 7,
owner-remove 11, offer 8, cross-parent 15, cross-account 11, profile 7,
f1-seed 7. Not run: the over-3:01 video refusal (no long video supplied;
covered by Worker unit tests only). Account A had no profile photo and none
was set. Test data created and kept (staging bucket; hosted rows of the two
disposable accounts only): account A's Owners
`7f813dfe-3e45-497a-82d8-d7bf16ad97db` (A1),
`8ab620b8-556d-43f7-b1d1-363c885a8d27` (A2),
`e3b9262a-69a5-4fb6-a40f-d65642f438cb` (A3-limit),
`15570b6f-9f0a-4302-ad6a-f938f0072f3a` (F1-owner-one) and
`ec063fa1-2e54-4e5f-9041-dbce39dc7e59` (F1-owner-two), account B's Owner
`efe28a5c-4df7-428c-b6b0-7a3107ee291e` (B1), account A's Offers
`2c8961ee-8665-4de1-99cf-7692b465be9a` (A-offer) and
`115a728b-1623-4a83-b710-b7191c734e4f` (F1-offer), and 28 media objects (listed
in the local, gitignored report). Nothing was cleaned up.

**F1 (`MEDIA-33`) — PENDING.** Phase 1 seeded five abandoned uploads (two
Owners, one Offer, the profile image and account B's Owner) at 14:51:20 UTC
and showed a fresh authorize leaves recent ones alone. Phase 2
(`-Mode F1Verify`, run `20260928T145634Z`, 14:56 UTC) passed its
preconditions (same two accounts, all five still pending) and stopped as too
early, changing nothing. It is due after **2026-09-29 15:01:20 UTC**, with
the same two accounts and `reports/f1_state_20260928T144750Z.json`.

**Not verified on a device.** No Owner media Samsung acceptance has been
reported: `MEDIA-29`…`MEDIA-32` and F2's lost-picker scenario (`MEDIA-34`)
stay NOT RUN.

**Local commit.** Branch `feature/owner-private-media`, created from
`06cd396` with the working tree kept; one commit
`feat(owner-media): implement private owner media lifecycle`, not pushed.
Excluded: the generated plugin registrant files under `linux/`, `macos/` and
`windows/` (line endings only, no content change) and the runner's
`reports/` (gitignored).

| Item | Status |
| --- | --- |
| `confirm_owner_media_upload` | APPLIED + VERIFIED_HOSTED, version `20260928131828` |
| Staging Worker | `ac033060-…` (owner-reported); Owner acceptance 126/126, VERIFIED_HOSTED |
| Production Worker | `6387e2c0-…` (owner-reported); smoke PASS (owner-reported); rollback `ecaf125d-…` |
| Media sweeps | off, Offer and Owner, both environments |
| F1 (`MEDIA-33`) | PENDING — phase 2 after 2026-09-29 15:01:20 UTC |
| Samsung (`MEDIA-29`…`MEDIA-32`), F2 (`MEDIA-34`) | NOT RUN |
| Git | one local commit on `feature/owner-private-media`; not pushed |

NOW — the owner reviews the local commit on `feature/owner-private-media` and
decides whether to push it.

NEXT — after 2026-09-29 15:01:20 UTC, run `-Mode F1Verify` with the same two
accounts and record the result here; then the Owner media Samsung acceptance
(`MEDIA-29`…`MEDIA-32`, `MEDIA-34`).

## UI PERFORMANCE — HOME TAB, ENTITY LISTS, DELETE FLASH (2026-09-28, VERIFIED_REAL_DEVICE)

Branch `perf/navigation-list-transitions`, created from `8e43c6f` with the
working tree kept. Separate from, and not touching, the
pending Owner media checkpoints (F1 phase 2, `MEDIA-29`…`MEDIA-34`): no
Worker, Supabase, R2, media, RevenueCat or Delete Account change.

### Root causes

1. **Home tab slow to appear.** `MainScaffold._onItemTapped` set the shell's
   fade to 0, switched branch, then `await`ed `HomeViewModel.refreshCounts()`
   — seven Supabase count queries — before starting the fade-in. Home stayed
   invisible for the whole round trip. Only the bottom-bar Home tap had the
   `await`; system Back to Home and returning from a pushed screen (Home
   stays mounted under it) have no blocking work.
2. **The six list screens appear late.** Each visit builds a fresh view
   model whose body shows its shimmer until Supabase returns the first list.
   The shimmer was `surface` at 40–80 % alpha drawn on a `surface` page, so it
   was invisible: the page stayed blank until the data arrived, whether the
   list was empty or not.
3. **White flash after a delete (all six).** After a successful delete the
   view model called `refreshX()`, which *re-created* the stream. The
   `StreamBuilder` resubscribed, reported `ConnectionState.waiting` and the
   view drew that invisible shimmer in place of the list until a fresh read
   returned. The delete had already triggered a re-read of the old stream
   (`CoreEntityMutationNotifier`), which the re-creation cancelled. Offers
   and Requests did the same after a status change.
4. **Found with it.** `_refreshedStream` ended on its first failed re-read,
   which the per-delete re-creation used to mask. Requests swallowed load
   errors (`handleError`), so a failed first load showed "no requests".

### Changes

- `lib/src/viewmodels/ListScreens/entity_list_state.dart` (new): shared list
  lifecycle — one subscription, last list kept, loading only before the first
  list, item-level delete with restore on failure and a double-submit guard.
- The six `list_*_viewmodel.dart`: use it; optional service parameter; no
  stream re-creation after delete or status change; toasts unchanged.
- The six `*_list_view.dart`: body drawn from that state instead of a
  `StreamBuilder`; each tile wrapped in the new
  `lib/src/views/Widgets/entity_delete_progress.dart`; shimmer tinted with
  `onSurface` so it is visible. `OwnersListView` gained a test-only
  `createViewModel` seam.
- `lib/src/views/Screens/home/quotation/list_quotation_view.dart`: same
  invisible shimmer on first load (Issue 4, same root cause); tint fixed only.
- `lib/src/common/routes/app_routes.dart`: the Home tab fades in at once;
  the count refresh runs without being awaited.
- `lib/src/services/supabase_core_entities_service.dart`: a failed re-read
  is delivered as an error event and the stream keeps listening.
- Debug builds log `[EntityList] <list>: first list after N ms`, delete
  timings, and `[Home] counts refreshed after N ms` (fixed categories only).

### Regression coverage

`test/lists/entity_list_state_test.dart`,
`test/lists/entity_list_view_models_test.dart` (all six view models),
`test/lists/core_entity_refresh_stream_test.dart`,
`test/lists/owners_list_view_test.dart`.

| Item | Status |
| --- | --- |
| Root causes 1–4 | CODE_PROVEN + VERIFIED_REAL_DEVICE |
| Targeted tests | 43/43 PASS (owner-run) |
| Flutter analyzer | ACCEPTED (owner-run) |
| Samsung acceptance | PASS (owner-verified) |
| Git | one focused local commit authorized on `perf/navigation-list-transitions`; no push, deploy or merge |

### Update — owner test run and refresh-stream correction (2026-09-28)

Owner-reported: `flutter test test/lists` 40 passed, 1 failed
(`core_entity_refresh_stream_test.dart`, "a failed re-read is reported and
the next mutation reads again": 5 s `TimeoutException`, then the 30 s test
timeout). Targeted analyzer: 0 errors, 0 warnings, 1 INFO — deprecated
`onPopInvoked` in `MainScaffold` (`app_routes.dart`), present in `8e43c6f`
and outside this change; left as is.

Root cause, in production code: the `async*` `_refreshedStream` subscribed to
`CoreEntityMutationNotifier` only when it reached `await for`, a microtask
after the first list had been delivered, so a mutation during the first read
or in that window was dropped (the test's notify, made from the delivery
microtask, hit it: the 5 s timeout). An `async*` body waiting in `await for`
also cannot be cancelled until the next mutation arrives, so the teardown
`cancel()` never completed (the 30 s timeout) — and in the app every closed
list screen stayed subscribed and made one more Supabase read on the next
mutation. `_refreshedStream` is now a `StreamController`: it subscribes to
mutations before the first read, runs reads one at a time (mutations during
a read cause one more), keeps the error semantics above, and stops listening
immediately on cancel. Same queries, same RLS path. Two tests added (a
mutation during the first read; cancel stops at once); the failing test's
assertions are unchanged. Status: CODE_PROVEN, NOT RUN.

### Final owner verification and commit approval (2026-09-28)

Owner-reported final verification after the refresh-stream correction:

- 43/43 targeted Flutter regression tests: PASS.
- Flutter analyzer: accepted. The pre-existing deprecated `onPopInvoked`
  INFO remains outside this checkpoint.
- Samsung physical-device acceptance: PASS.
- Home navigation and the Requests, Offers, Owners, Offices, Brokers and
  Watchmen list screens behave smoothly.
- The full-list white flash during deletion is resolved on the device.

This is VERIFIED_REAL_DEVICE. The owner authorized one focused local commit
with message `perf: improve navigation and entity list transitions`. No push,
deployment or merge is authorized by this checkpoint.

NOW — the owner reviews the completed local performance commit on
`perf/navigation-list-transitions`.

NEXT — if satisfied, the owner safely pushes that branch; then return to F1
phase 2 and the separate Owner media Samsung acceptance.

## QUOTATION SOURCE IMPLEMENTATION — BLOCKED AT BACKEND BOUNDARY (2026-10-01)

Branch `quotation-updated` was created directly from `main-last` at
`6413faaa9e15e548b58b2871e1b513c35cf8ff18`. The seven generated plugin
registrant files already showed line-ending-only drift; their normalized Git
diff was empty and they were left untouched. No Quotation source was changed.

Current source routes only to the Quotation list and add form. The form uses
`AuthRepository.currentUserId` (Supabase Auth by default), while
`QuotationService` reads/writes `users/{uid}/quotations` in Firestore and its
logo/PDF paths use Firebase Storage. The checked-in `firestore.rules` permits
quotation reads only with matching Firebase Auth and denies direct quotation
writes; it requires a quota Cloud Function for creation. No Supabase-to-Firebase
sign-in bridge exists in the default auth flow. The hosted Firestore rules were
not read, so their deployed state remains unknown. An existing Supabase
`public.quotations` schema does not mean this feature uses it; the owner
explicitly excluded a backend migration from this checkpoint.

The source review also found no edit route or edit initialization, disabled
form validation, no synchronous save guard before the quota await, and PDF
generation failures that are caught without user feedback. These are known
source issues, not completed fixes. A source-only patch cannot honestly make
create → save → reopen production-ready under the current authorized backend
scope. Status: VERIFIED_SOURCE for the cited call paths; implementation
BLOCKED; Flutter tests/analyzer/build and real-device verification NOT RUN by
owner instruction. No hosted change, migration, commit, or push was made.

NOW — the owner decides whether to authorize a separate Quotation backend
contract checkpoint using the existing Supabase schema and an approved media
path. Keep the Quotation entry points visible; report their real runtime
capability during device testing.

NEXT — after that contract is authorized and implemented, return to this
Quotation source implementation, then have the owner run real-device create,
save, reopen, edit, logo and PDF acceptance before marking it complete.

## QUOTATION SUPABASE BACKEND CONTRACT — READ-ONLY VERIFICATION (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the active hosted `broker-wallet` Supabase project was inspected with read-only
catalog queries. Migration history includes the baseline `20260821000100` and
RLS optimization `20260821000300`. **VERIFIED_HOSTED (schema metadata):**
`quotations`, all three quotation child tables, `quotation_media`, and
`media_objects` exist. All have RLS enabled. Authenticated users have SELECT
on their own rows, column-scoped INSERT/UPDATE on quotation headers, and
owner-bound CRUD on the three child tables. Header hard DELETE and client media
writes are not granted. `owner_id` points to `profiles.id`, which points to
`auth.users.id`; the header policies check `owner_id = auth.uid()`, and child
policies use `owns_quotation(quotation_id)`. These policy/grant conclusions are
catalog-verified, not a cross-account runtime test.

The hosted catalog has no Quotation aggregate save/update RPC. A Flutter
sequence of independent header and child writes is not atomic, so a reviewed
transactional RPC is required before production aggregate persistence. The
existing form/model also store an editable `administrativeFees.total`, while
the normalized hosted administrative-fees rows have no total column. The owner
decided on 2026-10-01 that this total must always equal the sum of fee rows;
a manual override is not authoritative and needs no database column. The later
Flutter implementation must align that field's behavior without redesigning
the screen. Header `date`/`startDate`/`endDate` remain display text as the
schema decision specifies. `paymentType` and row `method` remain separate
pending a later semantics decision.

**VERIFIED_SOURCE:** `quotations.office_logo_media_id` and `pdf_media_id` are
stable UUID references with owner-validation triggers; `quotation_media` has
`logo`/`pdf` roles. The current private-media Worker and shared Flutter queue
support Profile/Offer/Owner, not Quotation. The Worker has no Quotation routes
or PDF upload policy. The direct media IDs and link rows are not synchronized
by a database constraint. Quotation media needs a narrow extension of the
existing private R2 lifecycle and a service-role-only confirm path; no signed
URL should become canonical state. Account deletion inventories an account's
`media_objects` and R2 prefix, so any future Quotation key must remain under
`profiles/<uid>/`.

Status: backend contract investigation only. No mutating SQL or hosted mutation,
Worker deployment, Flutter change, test, analyzer, build, real-device check,
commit, or push. The generated plugin registrant drift remains untouched.

NOW — prepare one narrow Supabase migration/RPC checkpoint for atomic
Quotation aggregate saves, including rollback-only database validation; do
not apply it to hosted Supabase without separate authorization.

NEXT — after that checkpoint succeeds, address the separate Quotation
private-media backend extension before Flutter Quotation migration.

## QUOTATION ATOMIC SAVE RPC — SOURCE ONLY (2026-10-01)

On `quotation-updated` at base HEAD `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
`supabase/migrations/20260930204217_quotation_save_rpc.sql` adds
`public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)`. This is one
`SECURITY INVOKER` PostgreSQL function with an empty search path, existing RLS
and column grants, `auth.uid()` ownership, and EXECUTE only for `authenticated`
(PUBLIC/anon revoked). It writes the 18 non-media header fields and replaces
the three child sets in one function call. No table, policy, trigger, media
column, or unrelated feature is changed. The migration filename uses the
current UTC timestamp after the latest repository migration; the Supabase CLI
is not installed here, so `supabase migration new` was unavailable.

Input contract: client supplies a stable Quotation UUID, a nullable expected
version (NULL=create; non-NULL=update), a complete header JSON object, required
downpayment and administrative-fee arrays (empty arrays remove all), and an
optional government-fee object (SQL/JSON null removes it). Every header key is
required, with explicit JSON null for optional scalar values. Each child object
requires its full documented keys. Unknown keys, including `owner_id`,
`created_at`, `deleted_at`, `version`, `office_logo_media_id`, `pdf_media_id`,
and child `quotation_id`, are rejected. `payment_type` and each downpayment
`method` remain independent. A non-null downpayment `due_at` must be an ISO
timestamp with an explicit timezone offset. Display dates remain text.
Administrative total is the sum of child amounts and is not stored. The return row is
`(quotation_id uuid, resulting_version bigint, outcome text, created_at
timestamptz, updated_at timestamptz)`; outcome is `created`, `replayed`, or
`updated`.

Create retries with the same UUID return `replayed` only while the live stored
version-one header and all child values exactly match. A different owner sees
the ownership-safe not-found result; a changed same-owner row produces UUID
conflict. Updates lock the owned row, reject tombstones/stale expected versions,
and use the existing header trigger for exactly one version increment. The
function raises machine-readable SQLSTATEs: `PQT01` unauthenticated, `PQT02`
not found/foreign, `PQT03` deleted, `PQT04` version conflict, `PQT05` invalid
payload, `PQT06` UUID conflict; existing CHECK failures retain `23514`.
Statement failure rolls back the header and every child mutation.

`supabase/validation/quotation_save_rpc_validation.sql` is a psql-only,
transaction-wrapped script that includes the exact migration via `\ir` and ends
in `ROLLBACK`. It stages reserved test identities, checks grants/auth/ownership,
create/retry and mismatch, full child persistence and replacement, optional
government fees, invalid values, media-field protection, stale/deleted saves,
version advancement, and rollback after early or late child failure. Its source
checks the row lock and version predicate; simultaneous committed-session
contention cannot be conclusively exercised while all hosted writes remain
rollback-only. The current direct child-table CRUD grants also mean writes
that bypass this RPC do not advance the header version; the later client adapter
must use this RPC for aggregate writes. The validation script was written but
**NOT RUN**. The migration was **NOT APPLIED**; this RPC is
**IMPLEMENTED_SOURCE, NOT VERIFIED_HOSTED**.
No Flutter tests/analyzer/build/device commands, hosted SQL, commit, or push
were run. The prior generated registrant line-ending drift remains untouched.

NOW — owner reviews the exact migration and rollback-only validation source
before authorizing any hosted execution.

NEXT — only after owner approval, run that exact validation against hosted
Supabase in a transaction ending in ROLLBACK; evaluate its result before any
migration application or Quotation media checkpoint.

## QUOTATION SAVE RPC FINAL SOURCE/SECURITY CORRECTION (2026-10-01)

The prior `SECURITY INVOKER` proposal did not enforce its aggregate-write
boundary. Read-only hosted catalog inspection reconfirmed authenticated
column-level INSERT/UPDATE on `quotations` and direct CRUD on all three
Quotation child tables. Such writes could bypass the RPC, leave partial child
state, and change child rows without advancing `quotations.version`.

The still-unapplied
`supabase/migrations/20260930204217_quotation_save_rpc.sql` now uses a
`postgres`-owned `SECURITY DEFINER` function with empty `search_path`, explicit
`auth.uid()` ownership on every parent lookup/write, and no dynamic SQL. A
migration guard refuses installation by another role. Function EXECUTE remains
revoked from PUBLIC/anon and granted only to authenticated. The same migration
revokes the existing authenticated header INSERT/aggregate UPDATE column grants
and child INSERT/UPDATE/DELETE grants. Owner-scoped SELECT remains. Direct
`UPDATE (deleted_at)` remains for the established soft-delete path, with a
restrictive UPDATE policy allowing a live owned row to become tombstoned once
and preventing direct resurrection. RLS is not weakened. Trusted service-role
media writes remain separate; this RPC still neither writes nor accepts media
IDs. The existing `bump_sync_version` trigger was checked against hosted source:
it sets `updated_at=now()` and `version=old.version+1` on a header UPDATE; child
replacement does not fire it.

`supabase/validation/quotation_save_rpc_validation.sql` now checks definer
ownership/search path, exact grants and policy, denied direct aggregate DML,
retained owner soft delete, blocked resurrection, malformed JSON, equivalent
numeric replay, explicit-null header clearing, government-fee update/removal,
and post-ROLLBACK absence of the staged function/data/policy/grant changes.
It still includes the exact migration inside BEGIN/ROLLBACK. Sequential stale
version behavior and the lock/predicate are covered; true two-session
contention remains REQUIRES SEPARATE RUNTIME CONCURRENCY TEST.

Status: **SOURCE_CORRECTION_REQUIRED_AND_COMPLETED**. Source reasoning supports
the corrected authority and transaction model, but migration and validation
SQL remain **NOT EXECUTED**, **NOT APPLIED**, and **NOT VERIFIED_HOSTED**. No
Flutter/media changes, commit, or push. The generated registrant drift remains
untouched. Production application must use a transactional migration runner;
the rollback-only psql validation is the next approved database exercise.

NOW — owner reviews the corrected migration and validation files before
authorizing the exact hosted rollback-only validation.

NEXT — only after owner authorization, run the validation ending in ROLLBACK,
inspect every check and the post-rollback confirmation, then decide whether
the migration can be applied in a separate checkpoint.

## QUOTATION RPC HOSTED ROLLBACK VALIDATION — BLOCKED (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the existing hosted Broker Wallet project `rbvcnvqpdqrhywcgxkne` matched the
reviewed Quotation table ownership, RLS, grants, policies and version trigger.
Migration `20260930204217` and the exact `save_quotation` function were absent.
The local SQL hashes before execution were migration
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`
and validation
`44DA30C0C89DB3A8551463627675906A344B3D1482D552B0F50F2516FEA87549`.

One hosted rollback-validation call was attempted through the SQL connector.
Its local psql-directive expansion was malformed because JavaScript interpreted
`$'` in the migration's timestamp regular expression as replacement syntax;
the connector returned SQLSTATE `42601` (missing `THEN`). The script did not
return its rollback confirmation, so no validation assertion is claimed as
passed. A fresh read-only hosted snapshot matched preflight exactly: the
function and migration remained absent, baseline grants/policies and public
object digest were unchanged, and staged user, quotation, child and media row
counts were zero. No persistent hosted change was found.

The connector expansion was corrected locally without changing either SQL
file, but both untracked Quotation SQL files disappeared from this workspace
before the retry's final hash check. That check stopped the retry before any
second hosted validation call. Their disappearance was not caused by a Git
command in this checkpoint; unrelated Plus and generated registrant changes
were left untouched. Status: **BLOCKED / NOT VERIFIED_HOSTED_ROLLBACK**. The
migration was not applied; no Flutter/media work, deployment, commit or push
occurred in this checkpoint.

NOW — restore the exact two reviewed Quotation SQL files at the hashes above
and inspect the working tree; do not execute a substitute script.

NEXT — after source integrity is restored and the owner renews authorization,
run the exact rollback-only validation and compare fresh hosted preflight and
post-rollback snapshots before considering any separate migration application.

## QUOTATION SQL SOURCE RESTORED AFTER BRANCH-SWITCH LOSS (2026-10-01)

On `quotation-updated` at base HEAD `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the two reviewed Quotation SQL files and the Quotation checkpoint sections that
had vanished from the working tree were restored from Git history, not
rewritten. All four local branches (`quotation-updated`,
`upgrade-plus-plan-and-payment`, `backend-implementation`, `main-last`) and their
remotes pointed at this same commit, so none of the 2026-10-01 work had ever
been committed; it survived only in two GitHub Desktop stash entries created
while switching branches. The SQL files and the first four Quotation sections
came from `stash@{1}` (taken on `quotation-updated` at 2026-10-01 11:04:42
+0400); the "HOSTED ROLLBACK VALIDATION — BLOCKED" section came from
`stash@{0}`, where it had been carried to the Plus branch. The agent logs show
no git or file command that deleted these files; the stash taken at the branch
switch is the only place they remained.

Restored and hash-verified byte for byte against the values recorded in the
BLOCKED section above: migration
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047` and
validation `44DA30C0C89DB3A8551463627675906A344B3D1482D552B0F50F2516FEA87549`.
The Plus/Subscription changes that had been carried into the quotation stash
were deliberately NOT restored here; they belong to
`upgrade-plus-plan-and-payment`. Both stash commits are pinned under
`refs/backup/` so a stash discard cannot lose them.

Status: SOURCE RESTORED (CODE_PROVEN source integrity only). The migration is
still NOT EXECUTED, NOT APPLIED and NOT VERIFIED_HOSTED; no hosted call, Flutter
change, test, commit or push was made by this restoration.

NOW — the owner secures these restored files (commit them on `quotation-updated`
or otherwise protect them) before switching branches again.

NEXT — the owner renews authorization, then the exact rollback-only validation
runs as described in the BLOCKED section above.

## QUOTATION RPC HOSTED ROLLBACK VALIDATION — SIGNATURE ASSERTION FAILURE (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
both restored SQL files matched their reviewed SHA-256 hashes:
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`
(migration) and
`44DA30C0C89DB3A8551463627675906A344B3D1482D552B0F50F2516FEA87549`
(validation). Fresh read-only hosted preflight matched the reviewed baseline on
project `rbvcnvqpdqrhywcgxkne`; migration and RPC were absent.

Because no `psql` client was available, a temporary connector input was made
by byte-copying the exact migration file at the validation file's `\ir` line
and omitting only the two psql-only directive lines. The embedded migration
bytes were compared individually, the assembled file's length/hash were
checked, and the connector received that prepared file unchanged. The
temporary local file was removed after the attempt.

Hosted validation stopped with SQLSTATE `42883` at validation line 132:
`'public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb)'::regprocedure` names
only five arguments, while the migration defines six (uuid, bigint and four
jsonb). This is a validation-script defect. No completed assertion count or
explicit `ROLLBACK` verdict was returned. A fresh read-only hosted snapshot
matched preflight exactly: function/migration absent; grants, policies,
constraints and public-object digest unchanged; validation users, quotations,
all three child-table row sets and media rows absent. No persistent hosted
change was found. The migration was not applied.

Status: **BLOCKED / NOT VERIFIED_HOSTED_ROLLBACK**. Both reviewed SQL files
remain byte-identical and unmodified because correcting the validation file
would invalidate its reviewed hash. No Flutter/media work, deployment, commit
or push occurred in this checkpoint; generated registrant drift was untouched.

NOW — perform a new narrow source review of the validation signature assertion
and any other exact-signature references, correct and re-hash the validation
file, leaving the migration unchanged.

NEXT — after that new source is reviewed and explicitly authorized, rerun the
rollback-only hosted validation with fresh preflight and post-rollback read-back;
only a clean pass can make migration application eligible for a separate
owner authorization.

## QUOTATION RPC VALIDATION SIGNATURE FIX — HOSTED ASSERTION BLOCKER (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the validation file's one five-argument `regprocedure` reference was corrected
to the exact six-argument `save_quotation` signature. Reversing only that edit
in memory reproduced the prior SHA-256, proving the change was one string.
The new validation SHA-256 is
`02D4F00D75890DD8BEEE26A4CB7D6BB8F1C451507DD881ADC05F36EF8CE99B76`;
the migration SHA-256 remains
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.

Fresh read-only hosted preflight on `rbvcnvqpdqrhywcgxkne` found the migration
and RPC absent, the four quotation tables/postgres owners and baseline
grants/RLS/trigger intact, 30 relevant constraints present, and no validation
test residue. The corrected validation was submitted once using a raw-byte
temporary transport: the migration's exact 19,211 bytes were embedded and
compared, and the temporary file was removed afterwards. The script stopped
at its first security assertion with SQLSTATE `P0001` and message
`quotation validation failed: postgres-owned definer, empty search_path and
least-privilege grants`. No successful assertion count or explicit `ROLLBACK`
verdict was returned.

Read-only catalog diagnosis found that PostgreSQL stores `SET search_path = ''`
as `proconfig = {search_path=""}` on existing functions. The validation tests
`proconfig @> array['search_path=']`, which is false for those empty-path
functions; this is a validation-predicate defect. No correction or rerun was
made after the failed assertion. A fresh hosted snapshot matched preflight
exactly: function and migration absent; grants, policies, constraints and
public-object digest unchanged; validation users, quotations, all child-table
row sets and media rows absent. No persistent hosted change was found.

Status: **BLOCKED / NOT VERIFIED_HOSTED_ROLLBACK**. The migration remains NOT
APPLIED. True two-session contention remains REQUIRES LATER TEST. No
Flutter/media work, deployment, commit or push was performed; unrelated
generated registrant drift was untouched.

NOW — conduct a separate narrow source review of the empty-search-path
assertion, correct that validation-only predicate, and record a new hash.

NEXT — only after renewed owner authorization, rerun the rollback-only hosted
validation with fresh preflight and post-rollback read-back; a clean pass is
required before any separate migration-application authorization.

## QUOTATION VALIDATION SEARCH_PATH SOURCE CORRECTION (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the first RPC security assertion's `proconfig @> array['search_path=']`
predicate was corrected. PostgreSQL had recorded an explicitly empty function
search path as `search_path=""`, so the old literal array element could not
match. The validation now parses `proconfig` into option name/value pairs with
`pg_catalog.pg_options_to_table`, requires `option_name = 'search_path'`, and
requires the option value to be either the empty string or PostgreSQL's own
`pg_catalog.quote_ident('')` representation of the empty path. The same
assertion still requires postgres ownership, `SECURITY DEFINER`, PUBLIC and
anon EXECUTE denial, and authenticated EXECUTE allowance.

The old validation SHA-256 was
`02D4F00D75890DD8BEEE26A4CB7D6BB8F1C451507DD881ADC05F36EF8CE99B76`;
the new SHA-256 is
`05B1D68FE9D3024A32D555D515C02B7DE1C6B94986984CDDC08CD85495168287`.
Reversing exactly this predicate edit in memory reproduced the old hash. The
reviewed migration remained untouched at
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.
Other catalog/deparsed-source assertions were inspected; no other proven
representation defect was changed. `git diff --check` passed. No hosted SQL or
rollback validation ran in this source-only checkpoint; the migration remains
NOT APPLIED and hosted rollback remains NOT VERIFIED. True two-session
concurrency still requires a later test.

NOW — the corrected validation source is ready for separate owner-authorized
hosted rollback-only validation, beginning with a fresh preflight and exact
migration-byte transport check.

NEXT — after a clean rollback verdict and post-rollback read-back, seek a
separate owner authorization before applying the migration; do not apply it
under this source-only checkpoint.

## QUOTATION SAVE RPC HOSTED ROLLBACK VALIDATED (2026-10-01)

On `quotation-updated` at `6413faaa9e15e548b58b2871e1b513c35cf8ff18`,
the owner authorized a hosted rollback-only validation against project
`rbvcnvqpdqrhywcgxkne`. The reviewed migration remained byte-identical at
SHA-256 `ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.
The starting validation SHA-256 was
`05B1D68FE9D3024A32D555D515C02B7DE1C6B94986984CDDC08CD85495168287`.
Fresh read-only preflight found the RPC and migration absent, the four
postgres-owned RLS quotation tables, expected grants/policies/triggers and
30 relevant constraints present, and no validation residue.

The first run stopped at the first security assertion with SQLSTATE `42704`:
`has_function_privilege('PUBLIC', ...)` attempts to resolve the PUBLIC
pseudo-role as a real role. A fresh read-only hosted snapshot, constraints
read-back and migration list matched preflight exactly, including zero test
rows and unchanged public-object digest. Under the owner's explicit
validation-script-only correction authorization, the PUBLIC EXECUTE check was
changed to inspect function ACL entries with `aclexplode`, using `acldefault`
for a null ACL and requiring no `grantee = 0` EXECUTE row. The anon and
authenticated checks remained unchanged. The final validation SHA-256 is
`FF72C060F77F359BC64D5A9CC73D5647AC607400B1517DC975BF64AB81A64BE5`.

After a second fresh preflight matched the baseline, the exact migration
bytes were inserted into the validation transaction using byte-safe in-memory
transport. The successful hosted run returned
`QUOTATION SAVE RPC ROLLBACK CONFIRMED`. All 76 explicit
`assert_true`/`expect_error` calls (26 and 50 respectively), plus the
procedural guards, completed without failure in that final run. A fresh
read-only post-run snapshot, constraints read-back, project identity and
migration list all matched preflight exactly: `save_quotation` absent,
migration history unchanged, grants/policies/constraints/digest unchanged,
and test user, quotation, child and media rows all zero.

Status: **VERIFIED_HOSTED_ROLLBACK = YES; MIGRATION_APPLIED = NO**. This
validates the exact migration under the rollback-only hosted exercise; it does
not prove a committed two-session contention test or real-device behavior.
No migration apply, deployment, Flutter/media change, commit or push occurred.

NOW — request a separate owner-authorized apply plus hosted read-back of the
exact reviewed migration.

NEXT — after that apply and read-back succeed, perform the required real-device
Quotation verification and a later two-session concurrency test.

## QUOTATION SAVE RPC MIGRATION APPLY — HASH GATE BLOCKED (2026-10-02)

The owner authorized one hosted apply of
`20260930204217_quotation_save_rpc.sql` followed by read-only hosted
verification. Before the attempted apply, the source on `quotation-updated` at
`6413faaa9e15e548b58b2871e1b513c35cf8ff18` had the authoritative
SHA-256 `ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.
A fresh hosted preflight matched the rollback-validated baseline exactly, and
the linked Supabase CLI `db push --dry-run --skip-vault` listed only this
migration. The first actual apply command was **not executed**: automatic
approval review returned a usage-limit error before process creation.

On the owner's continuation, the checkout had changed to commit
`7ea6c251b7e875a379489e76d83069356e4b8841` with a clean working tree.
The tracked migration's working-tree bytes are now CRLF and hash to
`E08C59636EB9C52E376F8757D856FBAFAF88EF36737F8E9687EB7C928BD2D362`.
An in-memory LF normalization reproduces the authoritative hash exactly; no
migration source content difference was found. Nevertheless, the owner's
literal migration-hash gate requires the file itself to hash to the
authoritative value, so application stopped. A fresh hosted migration-list
read still did not contain version `20260930204217`. A separate read-only
snapshot request was rejected by automatic review because its query argument
was absent; it was not retried or used as evidence. No hosted apply, migration
history registration, Flutter/media work or new commit/push occurred here.

Status: **BLOCKED — MIGRATION NOT APPLIED; VERIFIED_HOSTED_ROLLBACK remains YES**.

NOW — restore the migration working-tree file to its authoritative LF bytes
under explicit owner direction, then verify its SHA-256 and rerun fresh hosted
preflight and a one-file CLI dry run.

NEXT — only after those gates pass, run the owner-authorized single linked
migration apply and complete the hosted read-back; the two-session concurrency
test remains a separate later checkpoint.

## QUOTATION SAVE RPC HOSTED APPLICATION VERIFIED (2026-10-02)

The owner authorized reconciliation and LF-only restoration before a single
hosted migration apply. Branch `quotation-updated` was at
`7ea6c251b7e875a379489e76d83069356e4b8841`, a direct descendant of
`6413faaa9e15e548b58b2871e1b513c35cf8ff18`. That commit added the
already-reviewed migration, rollback validation source and checkpoint docs;
its migration blob had the exact reviewed LF SHA-256
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.
It did not change Plus/subscription or Flutter source. The working-tree
`20260930204217_quotation_save_rpc.sql` had only 380 CRLF pairs in place of
LF, giving raw SHA-256
`E08C59636EB9C52E376F8757D856FBAFAF88EF36737F8E9687EB7C928BD2D362`.
Replacing those CRLF pairs with LF and no other bytes restored the reviewed
SHA-256. No SQL content or validation SQL changed.

The earlier exact-source hosted rollback validation remains **76 PASS, 0 FAIL,
ROLLBACK reached, hosted state restored exactly**. Fresh preflight against the
healthy project `rbvcnvqpdqrhywcgxkne` found migration `20260930204217` and
`public.save_quotation` absent, all four postgres-owned quotation tables under
RLS, the two unchanged quotation triggers, 15 existing policies, 30 relevant
constraints, expected baseline grants, and zero validation residue. The linked
Supabase CLI dry run listed only `20260930204217_quotation_save_rpc.sql`, with
no seeds or roles. The final local SHA-256 and project ref were rechecked;
the CLI then applied exactly that one migration and registered version
`20260930204217` through normal migration history.

**VERIFIED_HOSTED:** Direct read-back found the migration registered exactly
once and `public.save_quotation(uuid,bigint,jsonb,jsonb,jsonb,jsonb)` present,
owned by `postgres`, `SECURITY DEFINER`, PL/pgSQL, with explicit empty
`search_path`. Its return columns are `quotation_id uuid`,
`resulting_version bigint`, `outcome text`, and `created_at`/`updated_at`
`timestamptz`. EXECUTE is denied to PUBLIC and anon and allowed to
authenticated. Authenticated direct quotation INSERT and DELETE are denied;
the sole UPDATE-able column is `deleted_at`, restricted by the new owned,
live-row soft-delete policy. Direct child INSERT/UPDATE/DELETE are denied on
downpayments, government fees and administrative fees; SELECT remains.
All four tables retain RLS and postgres ownership. The 15 existing policies
remain, including the `auth.uid()` ownership policies, with only the intended
restrictive soft-delete policy added. `owner_id`, `created_at`, `version`,
`office_logo_media_id` and `pdf_media_id` are not directly UPDATE-able.
The before/after public-schema digest for columns, constraints, foreign keys,
indexes, triggers and existing policies matched exactly; unrelated table ACL
digest matched too. Validation residue remained zero. No unrelated schema
changes were observed and no quotation test data was created.

Status: **QUOTATION ATOMIC CRUD BACKEND HOSTED COMPLETE** for this migration
and catalog read-back. True two-session concurrency and real-device behavior
remain unverified. Quotation media and Flutter Quotation implementation are
not started. No Cloudflare/R2 deployment, new commit or push was performed
in this checkpoint.

NOW — close this hosted migration application checkpoint with the verified
catalog evidence above; do not infer real-device verification.

NEXT — run the separate narrow true two-session concurrency verification
checkpoint when authorized; then continue the remaining Quotation product
work under its own checkpoints.

## QUOTATION TWO-SESSION CONCURRENCY — IDENTITY GATE BLOCKED (2026-10-02)

The owner authorized one hosted two-session contention test, conditioned on
using an existing clearly dedicated Broker Wallet test account. Read-only
preflight confirmed project `rbvcnvqpdqrhywcgxkne` is healthy, migration
`20260930204217` is registered exactly once, the six-argument
`public.save_quotation` RPC exists and is postgres-owned, and the existing
`quotations_bump_sync_version` trigger is present.

The hosted Auth inventory contained seven accounts, all with `gmail.com`
addresses. No account carried an explicit test/QA/validation/sandbox/demo
marker in its email or inspected metadata, and no profile matched such a
marker. Consequently, no existing account could safely be classified as
dedicated test-only. The owner's STOP gate was reached before selecting a
quotation UUID, establishing authenticated sessions or writing any hosted
data. No test Quotation, child row, media object or user/profile change was
made; no concurrency result or cleanup claim is inferred.

Status: **TRUE_TWO_SESSION_CONCURRENCY = BLOCKED / NOT VERIFIED_HOSTED**.
The earlier atomic CRUD migration and catalog read-back remain VERIFIED_HOSTED;
real-device behavior, Flutter Quotation and Quotation media remain unverified
or not started. No migration, RPC, grant, RLS or other source change was made.

NOW — identify an existing clearly dedicated test account and a safe way to
establish two independent authenticated sessions for it, without exposing
credentials or tokens.

NEXT — after that identity/session gate passes, rerun hosted preflight and
perform the single owner-authorized same-version contention test, aggregate
read-back, exact test-row cleanup and post-test security/schema read-back.

## QUOTATION TWO-SESSION CONCURRENCY — LOCAL AUTH ENV BLOCKED (2026-10-02)

The owner identified existing user
`317d7619-01da-4420-8c7f-fe7c3fc2d6e7` as the dedicated test-only account
for the previously authorized hosted concurrency test. This resolves the
test-identity ambiguity above. A presence-only check of the local process
environment found both `BW_TEST_EMAIL` and `BW_TEST_PASSWORD` absent. No
values were printed or searched for elsewhere. Under the owner's explicit
STOP condition, no authentication, new hosted preflight, test Quotation,
concurrent call, cleanup operation or hosted write was attempted.

Status: **TRUE_TWO_SESSION_CONCURRENCY = BLOCKED / NOT VERIFIED_HOSTED**.
The prior migration application and catalog read-back remain VERIFIED_HOSTED;
no new runtime concurrency evidence exists. No source, migration, grants,
RLS, policies, user/profile, existing Quotation, media or Flutter code changed.

NOW — make `BW_TEST_EMAIL` and `BW_TEST_PASSWORD` available to the Codex local
process environment without placing their values in chat.

NEXT — after both variables are present and the email matches the designated
account, rerun preflight and the authorized two-session test with exact test
data cleanup and post-test read-back.

## QUOTATION TRUE TWO-SESSION CONCURRENCY VERIFIED HOSTED (2026-10-02)

The owner confirmed the existing dedicated test-only identity and supplied
`BW_TEST_EMAIL`, `BW_TEST_PASSWORD` and `BW_TEST_USER_ID` through the local
Windows user environment. The values were never printed or written to a file.
Presence and exact designated-identity comparisons passed locally; hosted
`auth.users` and `public.profiles` matched the designated identity before any
test write. Two separate password sign-ins produced distinct authenticated
Auth session IDs and access tokens; each session was verified with the hosted
Auth user endpoint. Both sessions were closed after the test.

Fresh preflight found migration `20260930204217` registered exactly once, the
six-argument `public.save_quotation` RPC and version trigger present, and no
existing row or child with temporary UUID
`d09066c9-ff4d-44ae-abcb-2c9d17cc5c48`. Session A created one non-media
test aggregate through `save_quotation`; hosted read-back confirmed owner,
header and one row in each child table, with initial version **V = 1**.

The two independent authenticated sessions each submitted a distinct complete
aggregate to that UUID with `expected_version = 1`. Their RPC request intervals
started 1 ms apart and overlapped for 484 ms (A: 21:40:43.623–44.108 UTC;
B: 21:40:43.624–44.141 UTC). **A succeeded** with `outcome = updated` and
`resulting_version = 2`; **B failed** with SQLSTATE `PQT04`. Hosted read-back
showed final version **2 = V + 1**, never 3. The header, one downpayment,
government-fee row and administrative-fee row all matched A's payload; no B
field or child value, mixed aggregate or partial replacement was present.
The request-window overlap is direct client evidence; a separate server-side
lock-wait sample was not obtained, so no claim of a measured wait duration is
made.

An admin cleanup transaction checked the exact test UUID, owner, version,
test-only title, null media IDs and one row per child, then removed exactly
those three child rows and the temporary quotation. Read-only verification
found zero remaining rows under that UUID and the existing Auth user/profile
still present. Whole-table quotation and child row counts returned to their
pretest values; the test profile digest was unchanged. Before/after hosted
digests for the RPC definition/config/ACL, table and column grants, RLS,
policies and version trigger matched. Migration history remained 15 total
entries with `20260930204217` registered once. No unrelated data or schema
change was observed.

Status: **QUOTATION DATABASE BACKEND = COMPLETE + VERIFIED_HOSTED** and
**TRUE_TWO_SESSION_CONCURRENCY = VERIFIED_HOSTED** for the two independent,
overlapping authenticated client RPC calls and persisted aggregate outcome.
This is database-level evidence only; Flutter Quotation, private Quotation
media and real-device behavior remain unverified or not started. No migration,
RPC, grant, RLS, policy, media, Flutter, Cloudflare/R2, commit or push change
occurred in this checkpoint.

NOW — close the Quotation database backend checkpoint with the hosted
concurrency evidence and confirmed zero test-data residue.

NEXT — begin the separate Quotation private media backend contract and
implementation checkpoint for the office logo and generated PDF when
authorized; do not start it under this concurrency checkpoint.

## QUOTATION PRIVATE MEDIA BACKEND SOURCE (2026-10-02)

The Quotation atomic CRUD database backend remains **COMPLETE +
VERIFIED_HOSTED**, including true two-session concurrency. This checkpoint
adds source for private office-logo images and generated Quotation PDFs only;
the media backend is **SOURCE ONLY / NOT HOSTED VERIFIED**. No Quotation
Flutter, media UI, Worker deployment, hosted SQL validation or write, migration
application, commit or push occurred.

Hosted read-only schema inspection confirmed that `media_objects`,
`quotation_media`, `quotations.office_logo_media_id` and `pdf_media_id` already
exist under RLS. Both header media IDs remain server-controlled and absent
from the six-argument `save_quotation` payload. The existing
`quotation_media` role check uses `logo`/`pdf`; the new Worker API and R2 paths
name the roles `office_logo`/`quotation_pdf`. Private keys are
`profiles/<uid>/quotations/<quotationId>/<role>/<mediaId>.<ext>`, keeping them
under the established account-deletion prefix and separate from Offer/Owner
media. No new table, public URL, identity system, grant or RLS policy was
added.

New migration source:
`supabase/migrations/20261001220000_quotation_private_media_rpc.sql` adds
service-role-only `confirm_quotation_media_upload` and
`remove_quotation_media`. Each locks the live owned Quotation, checks its
current media slot against `expectedMediaId`, and writes the Quotation pointer,
`quotation_media` link and `media_objects` state atomically. Confirm additionally
checks the exact owner/bucket/role/key/MIME/type/size and pending state; a
successful replacement marks the prior object `pending_delete`. A stale
confirm cannot replace the winner. These media slot changes advance the
existing Quotation version trigger exactly once; `save_quotation` source and
its non-media CRUD semantics are unchanged. The migration contains no
transaction control so its exact bytes can be included by the rollback-only
validation source, `supabase/validation/quotation_private_media_validation.sql`.
That SQL validation has **NOT** run against hosted Supabase.

`cloudflare/workers/r2-profile-upload/worker.js` now has four Quotation routes:
authorize, confirm, signed GET and remove. They reuse Supabase Auth bearer
verification, the private R2 binding, signing, account-deletion quarantine and
the existing media state model. Logo uploads accept JPEG/PNG/WebP up to 10 MiB;
PDF uploads accept `application/pdf` up to 20 MiB. Confirm checks stored R2
size, content type and leading bytes before the RPC. Removal and replacement
attempt immediate R2 cleanup and retain a `pending_delete` tombstone for
retry on failure. Pending-upload cancellation and aged-upload cleanup use a
status compare-and-set before deleting bytes. Soft-deleted Quotations cannot
authorize, confirm, list or remove; the separate seven-day Quotation cleanup
sweep can clear their media pointers, remove links and retire private bytes.
`QUOTATION_MEDIA_SWEEP_MODE` is absent and therefore **off** in every current
environment. No global sweep was enabled or configuration changed.

Targeted Worker behavior source is
`cloudflare/workers/r2-profile-upload/test/quotation_media.test.mjs`.
The local Node suite passed **128/128** after the final targeted additions.
These tests use in-memory Supabase/R2 fakes and establish no
hosted or real-device result. The rollback-only SQL source includes grant,
cross-user, cross-parent, role/MIME, stale replacement, idempotency, removal
and deleted-Quotation cases; it remains unexecuted. The reviewed
`save_quotation` migration retained raw SHA-256
`ED1EF8D1E5C26A94775E3983F92C4845335291299C6DA27DDF3B3EE9D6856047`.

NOW — obtain separate owner authorization to run the exact rollback-only
Quotation private-media SQL validation against hosted Supabase. The migration
and Worker remain unapplied and undeployed.

NEXT — after hosted rollback validation passes and a separate deployment
checkpoint is authorized, apply the migration, then stage and verify the
Worker routes with the private staging R2 bucket before any production
deployment. Flutter Quotation integration remains a later checkpoint.

## QUOTATION PRIVATE MEDIA HOSTED ROLLBACK VALIDATION (2026-10-02)

Target `rbvcnvqpdqrhywcgxkne` (`broker-wallet`) passed a fresh read-only
preflight: migration `20261001220000` was absent, both new media RPCs were
absent, the three existing media/Quotation tables and media-ID columns,
foreign keys, indexes, RLS and client write restrictions matched the source
assumptions, and validation IDs/bucket had no residue. The hosted
`save_quotation` definition digest was `0a7e5e6e9e774d3dd9af0cd807f38c32`.

The exact migration source
`supabase/migrations/20261001220000_quotation_private_media_rpc.sql` had
SHA-256 `8C5BE0CFC961498B0DBC29CB258D720955B0613CAFB3EF09BE24215E49C74005`
before and after validation. The validation source
`supabase/validation/quotation_private_media_validation.sql` initially had
SHA-256 `456C1641AC72E7A6E0F5D28B98F7152FE867BB8DC2134CE19051FC314BFD7A67`.
Only that validation file changed: WebP, PDF regeneration/isolation/removal and
failed-binding consistency cases were added, then its empty `search_path`
assertion was corrected from `search_path=` to PostgreSQL's stored
`search_path=""` representation. Its final SHA-256 is
`0986207DE6A476CF6DAA718617894A8011728FCB5D35F1EF7A8344266A3603D0`.
Byte-safe assembly replaced only the psql `\ir` include and `\set` directive;
the embedded migration slice rehashed to the unchanged migration SHA-256.

The first hosted attempt failed on that validation-only `search_path`
assertion (SQLSTATE `P0001`) before reaching explicit `ROLLBACK`. An immediate
hosted read-back found the migration, new RPCs, validation rows and bucket
absent, with the saved RPC and existing media digest unchanged. The corrected
run executed **40/40 assertions**, **0 failures**, and returned
`QUOTATION_PRIVATE_MEDIA_ROLLBACK_RESTORED` after its explicit `ROLLBACK`.
The final read-back exactly matched the captured preflight for migration
history, RPC absence, `save_quotation` definition/config/ACL, three table and
media-column grants, RLS state, six policy definitions, 28 constraints, 14
indexes, Quotation media IDs/links, all 156 existing media-object rows, and
zero validation users/profiles/Quotations/media rows. No unrelated media or
unexpected scoped schema object persisted. The migration is **NOT APPLIED**;
the Worker is **NOT DEPLOYED**; Flutter Quotation is **NOT STARTED**; real-device
behavior is **NOT VERIFIED**. No commit or push occurred.

NOW — the exact private-media migration source is ready for a separate
owner-authorized hosted application checkpoint.

NEXT — after that separate application and hosted read-back succeed, stage
the Worker routes with the private staging R2 bucket before any production
deployment; do not apply or deploy under this rollback checkpoint.

## QUOTATION PRIVATE MEDIA HOSTED MIGRATION APPLICATION (2026-10-02)

On `quotation-updated` at `7ea6c251b7e875a379489e76d83069356e4b8841`,
the owner authorized application of only
`supabase/migrations/20261001220000_quotation_private_media_rpc.sql`. Its raw
SHA-256 matched the rollback-validated source exactly:
`8C5BE0CFC961498B0DBC29CB258D720955B0613CAFB3EF09BE24215E49C74005`.
The prior hosted rollback validation remains **40/40 PASS, 0 FAIL, explicit
ROLLBACK and exact baseline restoration**; it was not rerun here.

Fresh preflight against the linked healthy project `rbvcnvqpdqrhywcgxkne`
found 15 registered migrations, version `20261001220000` absent, both new RPCs
absent, and no relevant schema, grant, RLS, constraint, index, data or
`save_quotation` drift from the validated baseline. The linked Supabase CLI
`db push --linked --dry-run` listed only the authorized file. After a final
local hash and linked-project-ref check, `db push --linked --yes` applied that
one file and completed successfully. The CLI warned that its optional local
pg-delta catalog cache could not access Docker; hosted read-back below is the
authoritative application result.

Direct hosted read-back found **16 migrations total**, with
`20261001220000_quotation_private_media_rpc` registered **exactly once**.
`public.confirm_quotation_media_upload(uuid,uuid,uuid,text,text,uuid,bigint,text)`
and `public.remove_quotation_media(uuid,uuid,text,text,uuid)` are present,
owned by `postgres`, PL/pgSQL `SECURITY DEFINER`, with explicit empty
`search_path`. Their stored bodies MD5-match the respective bodies extracted
from the exact migration source (`79026d8501670a554afd8bd451853954` and
`ba0318cf0e7a603152e04b86b2227420`). Both have EXECUTE for
`service_role` only; PUBLIC, anon and authenticated have none. The stored
contract includes the owned-row lock, exact media role/key checks,
compare-and-swap expected slot, and `pending_delete` transition already
exercised in the 40/40 rollback validation.

Authenticated direct UPDATE remains denied for
`quotations.office_logo_media_id` and `quotations.pdf_media_id`, and direct
`quotation_media` INSERT remains denied. The six-argument `save_quotation`
definition/config/ACL digest is unchanged
(`0a7e5e6e9e774d3dd9af0cd807f38c32`); its migration remains registered
once and its payload still has no media-ID write path. The three relevant
tables retain RLS, owners and ACLs; six policies, 28 constraints and 14
indexes retain their preflight digests. Existing `media_objects` data retains
156 rows and the exact preflight digest; Quotations and `quotation_media`
remain empty. Captured Offer/Owner/Profile-related ACL digest also matches.
No unintended hosted schema or data change was observed. Source, Worker,
Cloudflare/R2 settings, sweep modes and Flutter were not changed; no commit or
push occurred.

Status: **QUOTATION PRIVATE MEDIA DATABASE = COMPLETE + VERIFIED_HOSTED** for
the exact applied SQL migration and catalog read-back. Worker deployment is
**NOT DEPLOYED**, Flutter Quotation is **NOT STARTED**, and real-device behavior
is **NOT VERIFIED**.

NOW — close this single hosted database application checkpoint with migration
history, exact function bodies, privileges and unchanged baseline verified.

NEXT — under a separate owner-authorized checkpoint, deploy the already-tested
Quotation-capable Worker source to the private staging Worker and run staging
E2E against the private staging R2 bucket; do not start that deployment here.

## QUOTATION PRIVATE MEDIA STAGING — GATE KEY BLOCKED (2026-10-02)

Continuation of the staging Worker E2E checkpoint on `quotation-updated` at
`7ea6c251b7e875a379489e76d83069356e4b8841`, working tree preserved (no reset,
restore, clean, stash, commit or push). The Worker was **not deployed** and no
hosted or R2 write occurred; the checkpoint stopped at the credential gate.

**Source.** `worker.js` working-tree SHA-256
`a07e7bc5c0aee421d5fc50d1c642cbf14027700302f82eba6ab17107a9ba42aa`;
`test/quotation_media.test.mjs`
`227a3fea28191b9ec7bee2298e5da98997cc6074e38430e705ccd9d137a0cf26`. The Node
suite was re-run against this exact source: **128/128 PASS**, so it still
corresponds to the previously tested source. Still CODE_PROVEN only.

**Live staging preflight (read-only, VERIFIED first-hand).** Cloudflare login
valid for account `cb2f5eeef339651f8c7d94dd04866726` (the R2 endpoint's
account). Staging `r2-profile-upload-staging` serves 100% of version
`ac033060-5cbf-4b9c-8932-592bd88ab6ef` (tag `om1-3b16d8e6`, 2026-09-28) — the
rollback target. Its `MEDIA_BUCKET` and `R2_BUCKET_NAME` are
`broker-wallet-media-staging`; `OFFER_MEDIA_SWEEP_MODE` and
`OWNER_MEDIA_SWEEP_MODE` are `"off"`; `QUOTATION_MEDIA_SWEEP_MODE` is not bound
(off). Secret names present: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`STAGING_TEST_KEY`, `SUPABASE_SECRET_KEY` (values unreadable and not read).
Production `r2-profile-upload` serves 100% of `6387e2c0-db49-43eb-a0e0-edaca76e3e5e`,
binds `broker-wallet-media`, holds three secrets and **no** `STAGING_TEST_KEY`.
Staging and production share only the hosted Supabase project, as designed.
Production Worker, traffic and bucket were not touched.

**Blockers (credential gate).**

1. The staging gate key is not available to the agent process. Every staging
   HTTP request needs `X-Broker-Wallet-Staging-Key` equal to the Worker secret
   `STAGING_TEST_KEY`; secrets cannot be read back, earlier runs had the owner
   type it into the masked launcher prompt, and no environment variable at
   Process, User or Machine scope holds it.
2. Cross-user negatives (foreign owner, foreign Quotation, foreign media id)
   need a second authenticated test identity. Only the designated account
   `317d7619-01da-4420-8c7f-fe7c3fc2d6e7` is configured (`BW_TEST_EMAIL`,
   `BW_TEST_PASSWORD`, `BW_TEST_USER_ID` present; the id matches). Accounts are
   not created by the agent.

Status: **WORKER STAGING = NOT DEPLOYED; STAGING OFFICE LOGO / PDF E2E = NOT RUN;
OFFER / OWNER REGRESSION = NOT RUN**. Quotation private-media database remains
COMPLETE + VERIFIED_HOSTED; Production Worker, Flutter and real device are
unchanged / not started.

NOW — owner supplies the staging gate key to the local environment (a User
environment variable such as `BW_E2E_STAGING_KEY`, never in chat) and a second
dedicated test identity (`BW_TEST_B_EMAIL`, `BW_TEST_B_PASSWORD`,
`BW_TEST_B_USER_ID`), or instead authorizes a staging-only rotation of
`STAGING_TEST_KEY` to a value held only in the agent process.

NEXT — deploy the candidate to staging only (`--env staging`, rollback target
`ac033060-…`) and run the staging E2E, security negatives, Offer/Owner
regression, read-back and scoped cleanup in the same session.

## QUOTATION PRIVATE MEDIA STAGING — CANDIDATE DEPLOYED, E2E RUNNER READY (2026-10-02)

The owner authorized (A) rotating only the staging gate secret and (B) a
temporary second Auth account. **A is done; B was not performed by the agent**:
creating an account on the hosted identity provider is an action the agent must
leave to the owner even when authorized, so the authenticated E2E (which signs
in with account passwords) is handed to an owner-run runner, the pattern this
repo already uses for Owner media.

**Staging gate key rotated (value omitted).** A new random 256-bit
`STAGING_TEST_KEY` was set on `r2-profile-upload-staging` only, and stored as
the User-scope variable `BW_E2E_STAGING_KEY` on the owner's machine. It was
never printed, logged or committed. No other secret was touched; production
still holds only its three secrets and no `STAGING_TEST_KEY`.

**Staging candidate deployed (staging only, `--env staging`).** Version trail:
`ac033060-5cbf-4b9c-8932-592bd88ab6ef` (Owner media, old gate key) →
`fc93b776-92df-42f0-8888-ceed16bb1df2` (same code, new gate key) →
**`f875b2f7-9131-49c9-8bd2-9a35c5f4f1a2`** (tag `qm1-a07e7bc5`, `worker.js`
SHA-256 `a07e7bc5c0aee421d5fc50d1c642cbf14027700302f82eba6ab17107a9ba42aa`),
now 100%. Bindings: `MEDIA_BUCKET`/`R2_BUCKET_NAME` =
`broker-wallet-media-staging`; Offer/Owner sweeps `"off"`;
`QUOTATION_MEDIA_SWEEP_MODE` unbound (off); four staging secret names present.
Rollback: `fc93b776-…` (previous code, current gate key). Rolling back to
`ac033060-…` would restore the old, unrecoverable gate key. Production is
unchanged: `6387e2c0-db49-43eb-a0e0-edaca76e3e5e` at 100%, bucket
`broker-wallet-media`, no production traffic, secret or R2 change.

**Verified at runtime without any account credential** (HTTP probes of the
deployed staging Worker): no gate key and a wrong key → 403; the new key with no
session → 401, and with an invalid bearer → 401, on Quotation authorize,
confirm, remove and list; Offer, Owner and profile authorize still 401 under the
same conditions; an unknown route 404. The new key therefore works, the old one
is dead, and the Quotation routes are live behind the auth wall.

**Hosted baseline captured read-only (before any test data)** for the post-run
comparison: 16 migrations (`20260930204217` and `20261001220000` once each),
`save_quotation` definition digest prefix `0a7e5e6e`, the three Quotation
functions postgres-owned SECURITY DEFINER, 0 Quotations, 0 `quotation_media`,
156 `media_objects`, 7 auth users, designated account A present with 0
Quotations/media. 8 Offers and 6 Owners named `staging-e2e…` already exist from
the earlier Owner-media staging run and are not part of this checkpoint; cleanup
must use only this run's ids, never a name pattern.

**Runner prepared, not yet run against staging.**
`staging-acceptance/quotation_media_staging_acceptance.mjs`, its launcher
`run_quotation_media_staging_acceptance.ps1` and `QUOTATION_MEDIA_README.md`
cover the gate, office-logo (JPEG/PNG/WebP, refusals, replacement, stale,
removal), PDF (refusals, regeneration, stale, removal), wrong role, cross-parent,
deleted Quotation, direct-write denial, cross-user (A vs temporary B), and an
Offer/Owner/profile regression. Its offline self-test
(`quotation_media_offline_selftest.mjs`) runs the real `worker.js` and the runner
against in-memory fakes: **204 PASS, 0 FAIL**, and seven injected faults behave
as designed (five detected, two correctly held by the Worker's own guards). That
is CODE_PROVEN only. `npm test` is unchanged at 128/128. Untracked and
uncommitted.

Status: **WORKER STAGING = DEPLOYED (candidate `f875b2f7-…`), runtime-probed
without credentials; STAGING OFFICE LOGO / PDF E2E, CROSS-USER SECURITY and
OFFER / OWNER REGRESSION = NOT RUN**. Temporary account B: NOT CREATED.
Production, Flutter and real device: unchanged / not started. No commit or push.

NOW — the owner creates temporary account B in the Supabase dashboard
(Authentication → Users → Add user, Auto Confirm) and runs the launcher in their
own terminal.

NEXT — the agent reads the run's report and does the hosted and R2 read-back and
the narrow cleanup of exactly the report's ids; the owner then deletes account
B; only then can staging be classified VERIFIED_RUNTIME.

## QUOTATION PRIVATE MEDIA STAGING — VERIFIED_RUNTIME (2026-10-02)

**Acceptance run (owner-run, report read by the agent).** Runner
`quotation_media_staging_acceptance.mjs`, run `20261002T100914Z`
(10:09:14–10:11:56 UTC) against staging candidate `f875b2f7-…`:
**203 PASS, 0 FAIL** — gate 6, unauthenticated 3, invalid-auth 2, setup 10,
logo-refuse 9, logo 36, pdf 28, role-parent 9, deleted 8, direct-write 11,
cross-user 25, regression 40, removal 16. The offline self-test counts 204; the
difference is the optional "B matches the expected id" check, skipped when
`BW_TEST_B_USER_ID` is unset. Designated account A
(`317d7619-01da-4420-8c7f-fe7c3fc2d6e7`) matched; temporary TEST USER B was
`4778c51e-8fb3-428c-a040-fcfd527e0e4c`. Observed designed behaviour: a replaced
or removed object is tombstoned `deleted` immediately (no lingering
`pending_delete`); a stale remove while a newer media holds the slot is 409, and
removing an already-empty slot is idempotent. Not exercised against the real
bucket: the 10 MiB and 20 MiB limits were refused at declaration, no object that
size was uploaded.

**Post-run hosted read-back (before cleanup).** Versus the pre-run baseline,
migration history (16, both Quotation migrations once), all five media and
Quotation function definitions/owners/config/ACLs (`save_quotation` included),
RLS, policies, table and column grants, the 156-row media digest and designated
account A were identical. The only deltas were this run's footprint: +17
`media_objects` (16 `deleted`, 1 never-uploaded `pending_upload` on the
soft-deleted Quotation), +4 Quotations (every media slot null, no
`quotation_media`, no child rows), +1 Offer, +1 Owner, and B's auth user and
profile. Nothing outside the report's ledger existed.

**Staging R2.** `broker-wallet-media-staging` holds 55 objects, equal to the
database's 55 pre-existing `ready` staging rows (none from this run), so the run
left no bytes and no object outside the expected prefixes. All 17 of this run's
exact keys are absent (probe validated by a positive control on an unrelated
object). Private at bucket level: no custom domain, r2.dev access disabled.

**Cleanup (only the report's ids; no sweep).** One atomic guarded transaction
checked every id's owner, bucket, run window, run name and zero link rows, then
deleted exactly 17 `media_objects`, 4 Quotations, 1 Offer and 1 Owner, each
count asserted. The 8 Offers and 6 Owners named `staging-e2e…` from the earlier
Owner-media run were not touched. After cleanup the full baseline is identical
to pre-run except `auth_users` and `profiles` each +1 (TEST USER B): this run's
Quotations, `quotation_media`, `media_objects` and Offer/Owner rows are 0, A is
unchanged and the seven pre-existing profiles' digest is unchanged. B holds no
media, Quotation, Offer or Owner; across all 35 foreign keys to `profiles` and
`auth.users` B has rows only in `auth.identities`, `auth.sessions` and
`public.profiles`, all cascade-on-delete from `auth.users`. B was NOT deleted
by the agent.

**Production unchanged.** Worker `r2-profile-upload` still serves 100% of
`6387e2c0-db49-43eb-a0e0-edaca76e3e5e` (created 2026-09-28), three secrets and no
`STAGING_TEST_KEY`, bound to `broker-wallet-media`; no deploy, traffic, secret or
binding change. Staging remains on `f875b2f7-…` (no redeploy). No pre-run count
was captured for the production bucket (now 79 objects); its untouched state
rests on there being no write path: the runner refuses non-staging hosts, the
staging Worker binds only the staging bucket, every R2 command here named the
staging bucket, and the database has no row from this run in the production
bucket.

Status: **QUOTATION PRIVATE MEDIA STAGING = VERIFIED_RUNTIME** (hosted staging
Worker, private staging R2, hosted Supabase). Quotation CRUD, true concurrency
and the media database remain VERIFIED_HOSTED. Production Worker, Flutter
Quotation and real-device behaviour are NOT verified / NOT started. No commit or
push; the runner files are untracked.

NOW — the owner deletes TEST USER B in Supabase Authentication (safe: no
dependent data).

NEXT — separate owner-authorized checkpoint: Production Worker promotion
(rollback target `6387e2c0-…`) plus Production smoke verification.

## QUOTATION PRIVATE MEDIA PRODUCTION PROMOTION — PROMOTED, CREDENTIAL-FREE SMOKE PASS, AUTHENTICATED SMOKE PENDING (2026-10-02)

**Preflight (read-only, before any change).** TEST USER B
(`4778c51e-8fb3-428c-a040-fcfd527e0e4c`): auth user, identities, sessions and
profile all absent; 7 auth users; account A present. Branch `quotation-updated`
at `7ea6c251…`, working tree preserved. `worker.js` SHA-256 is exactly
`a07e7bc5c0aee421d5fc50d1c642cbf14027700302f82eba6ab17107a9ba42aa`, the source
of the 128/128 suite and the 203/203 staging acceptance (staging `f875b2f7-…`
was deployed from it). Production `r2-profile-upload` served 100% of
`6387e2c0-db49-43eb-a0e0-edaca76e3e5e` (the rollback target), bucket
`broker-wallet-media`, three secrets, no `STAGING_TEST_KEY`, Offer/Owner sweeps
`"off"`, `QUOTATION_MEDIA_SWEEP_MODE` unbound (off). Baseline: R2 production
bucket 79 objects (436 MB), staging bucket 55 at that reading; hosted
`media_objects` 156 (production bucket 85 rows: 77 ready, 7 failed, 1 deleted;
staging bucket 71 rows); 0 Quotations / `quotation_media`; 16 migrations (digest
`ff7c305c…`); the five media/Quotation functions' definition digests unchanged;
RLS, policy, grant, `offer_media`/`owner_media` and profile-media digests
captured. Both buckets: no custom domain, r2.dev access disabled.

**Candidate and promotion.** `wrangler versions upload --env ""` created
**`5eff52cb-5390-4a6a-9ea1-3a81dcedb12a`** (tag `qm1-a07e7bc5`, same 136.90 KiB
bundle as the staging candidate) without deploying. Its effective configuration
was verified before promotion: `MEDIA_BUCKET`/`R2_BUCKET_NAME` =
`broker-wallet-media`, Offer/Owner sweeps `"off"`, the three inherited secrets
and no gate secret; its preview URL answered 401 on the Quotation, Offer and
Owner routes and 404 on an unknown one. `wrangler versions deploy
5eff52cb-…@100% --env ""` then promoted exactly that version at 2026-10-02
10:30:56Z. Production now serves 100% of `5eff52cb-…`; the staging Worker is
unchanged (`f875b2f7-…`). The cron trigger was not touched by the version
deployment (not independently re-read). Rollback target remains
`6387e2c0-db49-43eb-a0e0-edaca76e3e5e`.

**Credential-free Production smoke — PASS** (`media-api.brokerwallet.ae`): all
four Quotation routes 401 without a session; an invalid bearer 401; an unknown
route 404; Offer, Owner and profile authorize/list/lookup 401 as before;
Production has no staging gate (a junk gate header gets the ordinary 401).

**Open observation.** The staging bucket's reported object count moved from 55
(two earlier readings) to 57 and stayed 57 for five minutes, while the database
for both buckets is byte-identical to the pre-promotion baseline (no row created
or updated), the staging Worker is unchanged, all 24 non-`ready` rows in both
buckets have no bytes, and all 17 keys of the earlier staging run are absent. It
is consistent with R2's storage metric delivering a delayed mid-run snapshot (55
+ the logo and PDF that were bound together) but is not proven; to be
re-measured at the end of this checkpoint.

Status: **PRODUCTION WORKER = PROMOTED (`5eff52cb-…`); credential-free smoke
PASS; authenticated Production logo/PDF smoke and Offer/Owner/Profile regression
= NOT RUN; PRODUCTION BACKEND NOT YET VERIFIED_RUNTIME.** Flutter and real device
unchanged / not started. No commit or push.

NOW — the owner runs `run_quotation_media_production_smoke.ps1` (designated
account A only; one temporary Quotation, Offer and Owner; no staging gate).

NEXT — the agent reads its report, does the hosted and Production-R2 read-back,
cleans up exactly the report's ids, compares with the pre-promotion baseline and
rolls back to `6387e2c0-…` if anything fails.

## QUOTATION PRIVATE MEDIA PRODUCTION BACKEND — VERIFIED_RUNTIME (2026-10-02)

**Production authenticated smoke (owner-run, report read by the agent).**
Runner `quotation_media_production_smoke.mjs`, run `20261002T105934Z`
(10:59:34–11:00:07 UTC) against `media-api.brokerwallet.ae` on version
`5eff52cb-…` as the designated account A only: **60 PASS, 0 FAIL** —
credential-free 10, setup 3, office logo 15, PDF 15, regression 17. One temporary
Quotation created through `save_quotation`; one logo and one PDF each went
authorize → signed PUT → confirm → hosted read-back → signed GET (exact bytes) →
remove → read-back, in bucket `broker-wallet-media` under
`profiles/<A>/quotations/<Q>/office_logo|quotation_pdf/<id>.<ext>`; the bare
object URL was refused; signed URLs were pinned to the production bucket and
exact key. Offer and Owner: authenticated list/unknown-id/authorize still
correct under their own prefixes and a never-uploaded authorization withdrawn;
Quotation, Offer and Owner ids do not cross routes; profile lookup 200 and a
foreign `userId` 403. Not re-run in Production (VERIFIED_RUNTIME in staging):
replacement, races, MIME matrix, cross-user.

**Post-run hosted read-back (before cleanup).** The Quotation was at version 5
(create, logo confirm/remove, PDF confirm/remove), both media slots null, no
`quotation_media` rows, no child rows. Of the four ledger media ids only the logo
and PDF still had rows, both tombstoned `deleted` in the production bucket (the
two never-uploaded Offer/Owner authorizations had already been withdrawn and had
no rows). Nothing outside the ledger was created or updated. Versus the
pre-promotion baseline, migration history, all five media/Quotation functions
(definition, owner, config, ACL), RLS, policies, table and column grants, the
Offer/Owner/Profile media digests, designated account A and the entire staging
bucket state were identical; the only deltas were the ledger's rows (+2
`deleted` media, +1 Quotation, +1 Offer, +1 Owner).

**Production R2.** All four keys of this smoke (logo, PDF, and the two
never-uploaded Offer/Owner keys) are absent from `broker-wallet-media`; the
objects were written to the production bucket only (pinned by the runner's URL
checks and the rows' bucket). Both buckets remain private: no custom domain,
r2.dev access disabled.

**Cleanup (only the report's ids; no sweep).** One atomic guarded transaction
asserted owner A, the production bucket, the run window, the run name, the
two withdrawn rows' absence and zero link rows, then deleted exactly 2
`media_objects`, 1 Quotation, 1 Offer and 1 Owner, each count asserted. After
cleanup all 24 captured baseline items (counts, 156-row media digest,
production- and staging-bucket digests, function definitions and ACLs, RLS,
policies, grants, migration history, profile and link digests, A's rows) are
identical to the pre-promotion baseline; this smoke's Quotations,
`quotation_media`, `media_objects`, Offer and Owner rows are 0. TEST USER A is
present and untouched (profile media null, own rows unchanged).

**Bucket-count observation resolved.** The staging bucket's reported count read
57 at 10:31–10:38 UTC and was back at 55 by 11:02 UTC with no database or Worker
change: R2's storage metric delivers a delayed snapshot (57 = 55 + the logo and
PDF bound together mid-run), not stray objects. Production reads 79 (baseline 79,
three readings 5–7 minutes after the smoke); because the metric lags ~20 minutes,
a transient +1 could still appear there and is not evidence of residue — the
key-level probes above are the authoritative proof. The 79 objects versus 77
`ready` rows (2 more bytes than rows) is pre-existing and unchanged from before
promotion.

**Workers.** Production `r2-profile-upload` still serves 100% of
`5eff52cb-5390-4a6a-9ea1-3a81dcedb12a` (bucket `broker-wallet-media`, three
secrets, no gate secret, Offer/Owner sweeps `"off"`, Quotation sweep unbound).
Staging still serves `f875b2f7-9131-49c9-8bd2-9a35c5f4f1a2`. Rollback was not
required; the rollback target remains `6387e2c0-db49-43eb-a0e0-edaca76e3e5e`.
The cron trigger was not changed by the version deployment (not independently
re-read).

Status: **QUOTATION PRIVATE MEDIA PRODUCTION BACKEND = VERIFIED_RUNTIME.**
Quotation CRUD, true concurrency and the media database VERIFIED_HOSTED; staging
Worker VERIFIED_RUNTIME. Flutter Quotation and real-device behaviour are NOT
started / NOT verified. No commit or push; the runner and smoke files are
untracked.

NOW — Production backend for Quotation private media is closed; no further backend
action is pending.

NEXT — begin Flutter Quotation integration in a separate implementation
checkpoint (not started automatically).

## QUOTATION FLUTTER SUPABASE + PRIVATE MEDIA INTEGRATION — SOURCE COMPLETE, NOT RUN (2026-10-02)

**Source implemented; no Flutter command was run by the agent.** The Flutter
Quotation feature now persists through the hosted `save_quotation` aggregate and
keeps its office logo and generated PDF in private R2 through the verified
Worker routes. Tests: **NOT RUN BY AI**. Analyzer: **NOT RUN BY AI**. Real
device: **NOT VERIFIED**. Backend, Worker, SQL and the acceptance runners are
unchanged (`worker.js` still `a07e7bc5…42aa`, media migration still
`8C5BE0CF…4005`).

**Before.** Quotation CRUD wrote `users/{uid}/quotations` in Firestore (hard
`delete()`), the logo went through Hive + Firebase Storage and the PDF to
`quotations/{uid}/{id}.pdf` in Firebase Storage, saved with Firestore
`createdAt` and a `pdfUrl` string, and the quota counter was a direct Firestore
write.

**Files changed (lib).** `quotation/quotation_model.dart` (Firebase types and
`pdfUrl` removed; `version`, `officeLogoMediaId`, `pdfMediaId`, `hasPdf`);
`quotation/services/quotation_service.dart` (Firestore/Hive/Firebase Storage
implementation replaced by the facade over the new services);
`quotation/services/pdf_generation_service.dart` (Firebase Storage upload and the
`local://` branch removed; rendering unchanged); `quotation/add_quotation_viewmodel.dart`
(create + edit, ordered save, media sync, conflict handling);
`quotation/add_quotation_view.dart` (optional id, existing loading style,
Save/Update label); `quotation/list_quotations_viewmodel.dart`;
`quotation/list_quotation_view.dart` (PDF open/share via the private path,
`hasPdf`, card tap); `lib/app.dart` (`/add-quotation?mode=edit&id=` as Owner
does); `lib/src/common/localization/app_en.arb` + `app_ar.arb` (15 keys, valid
JSON, CRLF kept). **New:** `quotation/services/quotation_supabase_mapper.dart`,
`supabase_quotation_service.dart`, `r2_quotation_media_service.dart`,
`quotation_media_workflow.dart`, `quotation_pdf_cache.dart`.

**Supabase aggregate.** Create: the client chooses a UUID v4 and calls
`save_quotation` with a null `expected_version` (an identical retry replays, so a
lost answer can never make two Quotations). Update: the version loaded on reopen
is sent as `expected_version`; `resulting_version` and every media confirm/remove
version are adopted, and the state is re-read after the media phase. `PQT04` is a
fixed "changed on another device" message and nothing is overwritten; `PQT01–06`
and `42501` map to fixed localized messages, never provider text. All 18 header
keys are always sent; media ids, owner, version and timestamps never are; there
is no direct write to any child table. Downpayment sequence is the list order;
due dates are the calendar date at UTC midnight with an explicit offset (the same
date on every device); `bankTransfer`↔`bank_transfer`, `cheques`→`cheque`; an
empty government section is not stored; untouched empty administrative rows are
skipped. Reads: one embedded select for reopen, header columns only for the list.
Delete is the soft `deleted_at` update of a live row (no hard delete), which also
removes this device's cached PDF; every mutation signals Home/list refresh.

**Private media.** Logo (JPEG/PNG/WebP ≤ 10 MiB, checked by real bytes at pick
time) and PDF (`application/pdf` ≤ 20 MiB): authorize → signed PUT (no Supabase
token sent to storage) → trusted confirm, each against `expectedMediaId`. The
bound logo/PDF changes only when confirm succeeds, so a failed replacement leaves
the previous one in place; a retry reuses the same logo upload identity, and a
stale authorize is resolved by an idempotent confirm; a PDF whose slot moved is
re-read and retried once. Save order: aggregate, then logo, then PDF; a media
failure leaves the saved Quotation intact, stays on the form with a localized
message, and the next Save is an update. The PDF is regenerated on every save (a
new media object; the server retires the old one) and drawn from the local logo
file or a short-lived signed URL used immediately. Opening/sharing a PDF uses a
local copy named by its media id, otherwise one download through a fresh signed
link; nothing signed is stored or logged.

**Legacy removed from the active path.** No `cloud_firestore`, `firebase_storage`,
Hive, `FirebaseAuth` or quota-Firestore reference remains in the Quotation
feature (quota now goes through `CoreEntityQuotaBridge`, a no-op in Supabase
mode). Firebase mode (`USE_SUPABASE_AUTH=false`) no longer has a Quotation
backend: the list is empty and saving fails. **Not migrated, by design:**
`analytics_service.dart` still reads Firestore `quotations` (so Analytics will not
see Supabase Quotations); `media_type_service.uploadQuotationLogo` and
`media_upload_service_compat.uploadQuotationLogo` are now dead shared helpers.

**UI.** No visual redesign. The only behaviour added is wiring the list card's
existing empty `onTap` to open the Quotation in the existing form (the edit
entry point); revert that one line to remove it. New text exists in English and
Arabic. A blank total is stored as `0` and shows blank on reopen; the
administrative-fees total is not a hosted column, so a reopened Quotation shows
the sum of its fees.

**Test source added (not run).** `test/quotation/`:
`quotation_supabase_mapper_test.dart` (payload contract, enums, dates, round
trip), `supabase_quotation_service_test.dart` (RPC/read/soft-delete requests,
PQT mapping), `r2_quotation_media_service_test.dart` (Worker bodies, no token to
storage, code mapping, no URL in errors), `quotation_media_workflow_test.dart`
(order, failed PUT never confirms or removes, stale/lost-confirm, PDF retry),
`quotation_service_test.dart` (notify, soft delete + cache purge, cache keyed by
media id, publish/download), `add_quotation_viewmodel_test.dart` (create, update
with `expected_version`, conflict, logo select/replace/remove/failure/retry, PDF
failure, busy), `quotation_legacy_removal_test.dart` (no Firebase, no direct
writes, no secrets, localization). The guard checks were replayed in Node against
the real sources and passed; Dart syntax was parsed with `dart format
--output=none`; neither is a substitute for the owner's runs.

**Owner commands.**
1. `flutter test test/quotation test/auth/canonical_identity_test.dart`
2. `flutter analyze lib/src/views/Screens/home/quotation lib/app.dart test/quotation`
   (then a full `flutter analyze` if wanted)
3. Only after 1 and 2 pass: `flutter run` (Supabase mode is the default; the
   Worker defaults to the verified production address).

**Device acceptance.** Create with title/office/total/dates/fees and a logo →
Save → card shows a PDF badge; View PDF opens (first open downloads once, the
second is instant) and Share works → tap the card (reopen): every field, the
schedule, fees and logo name match → change a field and Update → "Quotation
updated" and the list refreshes → reopen shows the change → replace the logo,
Update, reopen → clear the logo, Update → try a HEIC/PDF/GIF as logo (rejected
with a message) → delete by swipe (the card goes, Home count drops) → cold
restart (list, reopen and PDF still work) → switch to Arabic (RTL, Arabic
messages) → dark mode → optional: change the same Quotation on a second device
and save from the stale one (must show the "changed on another device" message).

Status: **FLUTTER QUOTATION INTEGRATION = SOURCE COMPLETE; tests/analyzer not
run; device NOT VERIFIED.** Quotation soft-deleted media is not retired from R2
until a separate sweep checkpoint enables `QUOTATION_MEDIA_SWEEP_MODE` (off).
No commit or push.

**Test-harness fix (owner run 1: 136 pass, 18 fail).** All 18 failures were in
`test/quotation/supabase_quotation_service_test.dart` and all surfaced as
`QuotationException(unknown)`. One shared harness defect: the `MockClient`
answered with `http.Response` objects that carried no `request`; `MockClient`
copies `response.request`, and postgrest's response parser dereferences it
unconditionally (success and error paths), so a null-check `TypeError` — not a
`PostgrestException` — reached the service, which correctly maps an unrecognised
error to `unknown`. Production service code was correct and is unchanged. The
test `_Backend.client` now re-binds every answer to its request (the same
pattern as `test/favorites/favorites_create_upsert_test.dart`), and the list
test accepts postgrest's default `created_at.desc.nullslast`. Not re-run by the
AI.

NOW — the owner reruns ONLY `flutter test test/quotation/supabase_quotation_service_test.dart`.

NEXT — if that passes, run the three commands above in order (1 first); no
analyzer or device testing until the full targeted suite passes; then real-device
acceptance of the checklist and record the result here.

## QUOTATION FLUTTER SUPABASE + PRIVATE MEDIA — OWNER-VERIFIED, MILESTONE COMMIT (2026-10-02)

Recorded from the owner's own runs; the AI did not run Flutter tests, the analyzer
or a device. This section supersedes the "tests/analyzer not run; device NOT
VERIFIED" status line of the section above; that section is left as written.

**Owner evidence.**
- `flutter test test/quotation/supabase_quotation_service_test.dart` — 22 / 22 PASS
  (after the test-harness fix recorded above; production service code unchanged).
- `flutter test test/quotation test/auth/canonical_identity_test.dart` — 154 / 154 PASS.
- `flutter analyze lib/src/views/Screens/home/quotation lib/app.dart test/quotation`
  — 0 errors, 0 warnings, 3 info-only `Color.red/green/blue` deprecation notices
  (accepted for this milestone; no unrelated cleanup made).
- Real device (Samsung): the Quotation create / save / reopen / edit / media / PDF
  flow was tested by the owner and reported PASS.

**Status.**
- Quotation CRUD backend: COMPLETE + VERIFIED_HOSTED (true concurrency VERIFIED_HOSTED).
- Quotation private-media database: COMPLETE + VERIFIED_HOSTED.
- Quotation private-media Worker: Staging VERIFIED_RUNTIME (203 / 203); Production
  VERIFIED_RUNTIME (60 / 60).
- Flutter Quotation: **OWNER-VERIFIED_REAL_DEVICE for the tested flow.**
- Still off / out of scope: `QUOTATION_MEDIA_SWEEP_MODE` (soft-deleted media is
  not yet retired from R2; a separate sweep checkpoint).

Committed as one milestone commit on `quotation-updated`: `feat(quotation): migrate
CRUD and private media to Supabase R2`. Generated plugin-registrant drift, runtime
reports and unrelated work were not staged. Not pushed.

NOW — the Quotation milestone is committed locally.

NEXT — pushing requires separate owner authorization.

## UAE AREA CATALOG + EXPANDABLE AREA CHIPS — SOURCE COMPLETE, NOT RUN (2026-10-02)

Scope: the "Choose City" area section of Add Request and Add Offer only. No
backend, Quotation, Worker, R2, subscription or Request/Offer persistence change.

**Backend check.** `request_areas.area` / `offer_areas.area` are `text not null`
with only a non-empty check (primary key `(request_id, area)`); there is no enum,
allow-list or length rule, so new area keys need no migration.

**One shared catalog.** `lib/src/common/data/uae_area_catalog.dart`
(`UaeAreaCatalog`) holds an ORDERED list of area keys for each of the nine
supported cities (Dubai 91, Abu Dhabi 39, Sharjah 45, Ajman 28, Ras Al Khaimah
24, Fujairah 20, Umm Al Quwain 18, Al Ain 31, Khor Fakkan 15; before: 10 each,
and none for Khor Fakkan). The order is a product priority — current demand,
market prominence, active inventory, recognisability, then newer and peripheral
areas — not alphabetical and not an official ranking. Buildings, towers, project
phases and numbered sub-districts are not areas. English and Arabic names live
in the ARBs (+235 keys each, `showMore`, `showLess`). Names were cross-checked
against Property Finder and Bayut area guides and, for Khor Fakkan, the
Sharjah Ruler's published suburb division.

**Stored values are unchanged.** An area is stored by its key. Every key an
older picker offered kept its exact key; new areas got new keys. Keys no longer
offered (`qalaatAlFujairah`, `alMuroorUAQ`, `alHadarah`, `alShabiya`) stay in
`UaeAreaCatalog.legacyOnlyAreas`, localized, so an old record still renders. No
hosted row was rewritten. Two existing English labels were aligned to current
spelling (`murbah` Mirbah, `zakhir` Zakher) and the missing English `mussafah`
was added (it previously fell back to Arabic text in English).

**One shared component.** `lib/src/views/Widgets/expandable_area_chips.dart`
(`ExpandableAreaChips`) replaces both forms' private `_getResidentialAreas`
switch and chip loop. Collapsed it shows only the first three VISUAL rows,
planned from the available width, text scale and language (`TextPainter`
measurement that mirrors `Wrap`; never a fixed chip count), with a localized
"Show more" / "Show less". A selected area the collapsed rows would hide (a
saved area far down the list, or a legacy/unknown key) stays visible at the end
of the last row. Expanding never changes the selection; a new city starts
collapsed; the three-area cap is unchanged. Chip look is unchanged.

**Related fix.** `request_share_options_dialog.dart` mapped area keys through a
lossy switch and fell back to the raw camelCase key; it now translates the
stored key directly when its mapping finds nothing. (The two details screens
already pass unknown keys through.)

**Tests (source only).** `test/areas/uae_area_catalog_test.dart`,
`test/areas/expandable_area_chips_test.dart`. A plain-Node replay of the catalog
assertions and of the row-planning algorithm (including a 20,000-case fuzz) passed;
Dart syntax was parsed with `dart format --output=none`. None of that is a
substitute for the owner's runs.

Status: **AREA CATALOG / EXPANDABLE UI = SOURCE COMPLETE; tests/analyzer not run;
device NOT VERIFIED.** No commit or push.

NOW — the owner runs `flutter test test/areas`.

NEXT — only if that passes, the scoped analyzer: `flutter analyze
lib/src/common/data lib/src/views/Widgets/expandable_area_chips.dart
lib/src/views/Screens/ViewAdd lib/src/views/Screens/ViewDetails/widgets/request_share_options_dialog.dart
test/areas`; then check Add Request and Add Offer on a device in English and
Arabic, light and dark, at a narrow and a wide phone.

## OWNER PROPERTY TYPE CHIPS + SHARED UAE LOCATION — SOURCE COMPLETE, NOT RUN (2026-10-02)

Scope: the Add/Edit Owner screen only, on top of the uncommitted Request/Offer
UAE area-catalog work above. No backend, migration, RLS, Worker, R2, Owner media,
Quotation, Request/Offer persistence or subscription change.

**What an Owner stores (unchanged).** `typeOfProperties` and `propertyLocation` are
two plain strings (`owners.property_type_text`, `owners.property_location`, both
`text not null default ''`; no CHECK, enum or length rule in any migration).
There is NO city or area column, so nothing here is a new persistence contract.

**Property type chips.** `PropertyTypeChips` shows 19 quick picks (Villa, Apartment,
Townhouse, Studio, Penthouse, Duplex, Whole Building, Residential Plot, Commercial
Plot, Land, Farm, Office, Shop / Retail, Warehouse, Show Room, Labor Camp, Hotel,
Hotel Apartment, Other) above the EXISTING free-text field, which stays and still
accepts any wording. A tap puts the name, in the language in use, into that field;
the field is the only stored value. A chip shows selected only while the text says
it (case/space-insensitive, English or Arabic, plus the project's older spellings);
custom text selects nothing and a saved value is never rewritten. The names reuse
existing ARB keys (`villa`, `apartment`, `showRoom`, `laborCamp`, …); five new keys
were added (`residentialPlot`, `commercialPlot`, `shopRetail`, `hotel`,
`hotelApartment`). The existing wording was kept where it differs from the brief:
`laborCamp` = "Labor Camp" / "مخيم عمال", `showRoom` = "Show Room", `penthouse` =
"بنت هاوس"; the brief's spellings are recognised when matching saved text.

**Property location on the shared catalog.** The Owner form uses the same
`UaeAreaCatalog` (nine cities, ordered areas) and the same `ExpandableAreaChips`
as Request and Offer, through the new `UaeCityAreaPicker` (city chips, selected-city
pill, then the three-row expandable areas). An Owner has ONE location, so the
picker runs with `maxSelectedAreas: 1`: tapping another area replaces the choice
and no chip is dimmed (Request and Offer keep their three). A choice is written
into the existing location text as `Area, City` (or `City`), in the language in use,
optionally followed by `, the owner's own words`; `OwnerLocationCodec` reads it
back in either language, so edit mode restores the city and area (a deep area or a
dropped legacy area still shows). Anything else is the owner's own text: shown
exactly, never normalized, no chip selected. Typing never creates a choice and
clears one once the text stops saying it; changing the city clears the area and
collapses the list. Choosing a city/area over custom text replaces that text
(like the property-type chips); clearing the city keeps what the owner wrote after
the choice. The existing "Property Location" text field stays below the picker.

**Shared pieces.** `SelectableChip` is now the one chip look (area chips use it);
`ExpandableAreaChips` gained the single-selection behaviour; `UaeAreaCatalog` gained
`cityKey` and `isAreaOf`; `AppLocalizations.translateFor(language, key)` reads a
name in a given language from the preloaded cache (no fallback). Request and Offer
screens are unchanged and still use `ExpandableAreaChips` with three areas; their
private city-chip rows remain (backlog: move them onto `UaeCityAreaPicker`).

**Tests (source only).** `test/owners/owner_property_type_test.dart`,
`test/owners/owner_location_test.dart`, plus a single-selection group in
`test/areas/expandable_area_chips_test.dart`. A plain-Node replay of the codec, the
Owner view-model's chip state machine, the property-type matching (5,937 checks) and
the source guards passed against the real catalog and ARB files; Dart syntax was
parsed with `dart format --output=none`. None of that is a substitute for the
owner's runs.

Status: **OWNER PROPERTY TYPE CHIPS / SHARED UAE LOCATION = SOURCE COMPLETE; Flutter
tests NOT RUN; analyzer NOT RUN; device NOT VERIFIED.** More UI changes are still
being grouped, so no run has been requested. No commit or push.

NOW — nothing to run yet; finish the remaining grouped UI changes.

NEXT — one targeted pass after they are done: `flutter test test/areas
test/owners/owner_property_type_test.dart test/owners/owner_location_test.dart`,
then the scoped analyzer over the changed folders, then the device check of Add
Request, Add Offer and Add/Edit Owner (English and Arabic, light and dark, narrow
and wide phone).

## FLOATING SAVE / CANCEL FORM ACTIONS — SOURCE COMPLETE, NOT RUN (2026-10-02)

Scope: the bottom Save / Cancel area of the seven form screens that use
`SaveCancelButtons` — Add/Edit Request, Offer, Owner, Broker, Office, Watchman and
Quotation. UI layout only: no save logic, view-model, backend, media or auth change.

**Root cause.** `SaveCancelButtons` itself never had a background. Each of the seven
screens wrapped it, identically (copy-pasted), in a bottom `Positioned` +
`Container(color: colorScheme.surface, boxShadow: top shadow)` — the full-width dock —
and reserved room for it with a hard-coded `100` of bottom scroll padding.

**Shared fix.** The dock is gone from all seven screens: `SaveCancelButtons` now sits
directly in the `Positioned` and owns the floating presentation once:
- transparent: the page colour shows around the buttons; same 16 margins, same pill
  buttons, colours, labels, loading/disabled/Update behaviour;
- `SafeArea(top: false, left: false, right: false)`: the bottom system inset is still
  cleared (the app already applies the same bottom-only SafeArea in `app.dart`, so no
  inset is double-counted);
- opaque buttons so scrolled content never shows through: Cancel is filled with the
  page colour, Save's "nothing to save yet" tint is blended onto it (identical look on
  the page, light and dark);
- `SaveCancelButtons.clearanceOf(context)` = bottom inset + the actions' real height +
  a 16 gap, replacing the hard-coded 100. It follows the text scale and the theme's
  button line height, so the last field can always scroll fully above the buttons.

**Keyboard (unchanged).** The actions are still left out while the keyboard is open and
the scroll view still pads `keyboardHeight + 20`; the six screens with
`resizeToAvoidBottomInset: false` keep it. Observed, NOT changed: Quotation lacks
`resizeToAvoidBottomInset: false`, so with the keyboard open its body is resized and
also padded by the keyboard height (extra blank scroll room) — pre-existing, backlog.

Not in scope and untouched: the Request/Offer/Owner area, city and property-type work
above, Edit Profile (its `bottom: 0` is an avatar badge) and every other screen.

**Tests (source only).** `test/forms/save_cancel_buttons_test.dart`: render, Update,
Arabic/RTL order, size and margins, no full-width painter behind the buttons, touches
pass through the margins and the gap, opaque buttons in light and dark, SafeArea,
the last field scrolled above the actions at four text scales and two insets, loading
and disabled behaviour, and source guards that all seven screens use the shared
component with no panel. A plain-Node replay of the guards and the clearance
arithmetic passed (106 checks); Dart syntax was parsed with `dart format
--output=none`. None of that is a substitute for the owner's runs.

Status: **FLOATING SAVE / CANCEL ACTIONS = SOURCE COMPLETE; Flutter tests NOT RUN;
analyzer NOT RUN; device NOT VERIFIED.** More UI changes may still be grouped. No
commit or push.

NOW — nothing to run yet; finish any remaining grouped UI changes.

NEXT — one combined pass: `flutter test test/areas test/owners test/forms`, the scoped
analyzer over the changed folders, then a Samsung acceptance of Add/Edit Request, Offer,
Owner, Broker, Office, Watchman and Quotation (English and Arabic, light and dark): the
buttons float with the page visible around them, clear the navigation area, the last
field scrolls fully above them, and the keyboard hides them as before.

## APP UI SIZE CONSISTENCY + COMPACT FORM ACTIONS — SOURCE COMPLETE, NOT RUN (2026-10-02)

Scope: size consistency of the app's existing reusable controls, with Save / Cancel
made more compact. Not a redesign: no colour, font, radius, field order or layout
change. No backend, migration, RLS, Worker, R2, auth, subscription, persistence or
business-logic change.

**Canonical form action height: 48 dp (was 56).** The old buttons were an 18 dp
vertical padding around a ~20 dp label. `SaveCancelButtons` now sizes both buttons
with one shared value, so Save and Cancel are exactly the same height and level in
every state (Save, Update, saving, "nothing to save yet", Arabic, light, dark).
Horizontal padding was already 0 and still is; pill radius, colours, labels,
margins (16), the gap between the buttons (18), RTL order and loading/disabled
behaviour are unchanged. The two tints (30% / 50% of the primary colour) are now
`withAlpha(77)` / `withAlpha(128)` — byte-identical to the old
`Color.fromARGB((0.3 * 255).round(), …)`, which removes the deprecated
`.red/.green/.blue` reads in this one component (the only one edited that had them).
A button grows past 48 only when the text scale is so large that the label line plus
8 above and below would not fit (about 1.6x and up), so a label is never clipped;
labels are one line with an ellipsis.

**Clearance.** `SaveCancelButtons.heightOf` = 2 x 16 margin + `buttonHeightOf` (48 at
normal scale), so `clearanceOf` (bottom inset + that + 16) is built from the actual
shared action height, not the old 56-high buttons. `SafeArea(top: false, left: false,
right: false)` and the floating presentation (no full-width panel) are untouched.

**Shared size system.** One small file, `lib/src/constants/app_control_sizes.dart`
(`AppControlSizes`), beside `app_colors.dart` and `app_typography.dart`. Only sizes a
whole KIND of control shares: `standardButtonHeight` 48 (large actions),
`formActionHeight` (= standard), `compactButtonHeight` 40 (compact inline actions),
`minTouchTarget` 48, and the chip metrics (`chipHorizontalPadding` 18,
`chipVerticalPadding` 9, `chipBorderWidth` 1.3, `chipRadius` 32, `chipSpacing` 10).
Chips, fields, icon buttons and large actions are deliberately NOT forced to one
height.

**Controls normalized.**
- Save / Cancel (the seven forms: Request, Offer, Owner, Broker, Office, Watchman,
  Quotation) — 48, via `AppControlSizes.formActionHeight`.
- Large full-width actions in shared widgets that already hard-coded 48
  (`feedback_success_bottom_sheet`, `logout_confirmation_bottom_sheet`,
  `email_addition_dialog`) now read `standardButtonHeight`. No visual change.
- Chips: `SelectableChip` reads the chip tokens (values unchanged). The Request and
  Offer forms had private copies of the unselected city chip and of the selected-city
  pill (the same 18 / 9 / 1.3 / 32 numbers); they now use `SelectableChip` and the new
  `ClearableChip`, which the Owner's `UaeCityAreaPicker` also uses. One chip look, one
  size. `chipSpacing` is the one gap the Wraps and the row planner share.
- The selected-city pill's clear (x): its tap area was the bare 18 px icon; it is now
  the icon plus the pill's own padding (44 x 38), with no visual change to the pill.
- The area chips' "Show more / Show less" toggle (a compact inline action) has at
  least `compactButtonHeight` (40) to tap, up from about 34; the label stays where it
  was, with the room below it a little larger.

**3-row collapse preserved.** `ExpandableAreaChips` plans rows from chip WIDTHS, the
text scale and the language, never from chip height, and no chip width changed
(padding, border and spacing are the same numbers), so the collapsed state is still
three rendered rows. Request and Offer still use `ExpandableAreaChips` with
`selectedAreas: vm.selectedAreas` / `onToggleArea: vm.selectArea` and the three-area
cap; the Owner still has one area, property-type chips and the free-text fields.

**Audited and intentionally left alone.**
- Single-line text fields, the phone field, the pick-up location field and the
  Quotation dropdown/date fields are already one size (52 dp, radius 10) across the
  seven forms; Notes (min 84) is multi-line. Not changed.
- Specialised controls: the Rent/Sell segmented tabs (50), the Quotation logo-attach
  row (54), the rooms/baths number pills, media galleries/cards, maps, avatars.
- Default Material buttons with no explicit size (the account sheets' `FilledButton`s,
  etc.) are 40 dp visible with a 48 tap target. A theme-wide button size would change
  ~80 files, so it is not done here.
- Delete/confirm dialogs in the six lists and six detail screens (12 dp vertical
  padding, about 47 dp, radius 12) and the share dialogs are consistent with each
  other and about 48; they are copy-pasted per screen, not shared.
- Map picker actions (44, commented "reduced height") and the phone dialog (40, 11 pt
  label, radius 10) are deliberately compact.

**Backlog, not implemented (outside the named screens or a layout change).**
- `language_view.dart` Save is a 50 dp full-width action (`Size(0, 50)`); the standard
  is 48. `match_details_view.dart` already uses 48 as a literal. Both are single
  screens the task did not name.
- The error-banner dismiss (x) in Add Broker / Office / Watchman is an `IconButton`
  with `constraints: BoxConstraints()` and zero padding, so its tap target is the 18 px
  icon. Enlarging it would make the banner taller; the owner should decide.
- Request/Offer still have their own `_CityChips` wrappers (kept: existing source
  guards rely on them); they could move onto `UaeCityAreaPicker`.
- `AppTextStyles.fontFamily` is `Inter` while the theme font is `Montserrat`, and
  neither is a bundled font family in `pubspec.yaml` (only Noto Sans / Naskh are). Not
  investigated; the fixed 48 dp buttons centre their label, so it cannot clip either way.

**Tests (source only).** `test/forms/save_cancel_buttons_test.dart` (48 instead of 56;
equal heights in Save / Update / saving / disabled, English / Arabic, light / dark,
text scales 0.85 to 2.0; labels inside their buttons; exact `heightOf` and
`clearanceOf`; no old padding or deprecated colour reads) and the new
`test/forms/control_sizes_test.dart` (the tokens; every chip kind one height; the
pill and the clear tap area; the toggle's compact height; shared widgets read the
token; no private copy of the chip padding). `test/areas` and `test/owners` needed no
change. Dart syntax of every touched file was parsed with `dart format
--output=none`, and each edited tracked file matches the in-package formatter except
formatting differences that were already there.

Status: **APP UI SIZE CONSISTENCY = SOURCE COMPLETE; Flutter tests NOT RUN; analyzer
NOT RUN; device NOT VERIFIED.** Floating Save / Cancel, the Request/Offer UAE area
catalog and Owner property-type / location work are preserved. No commit or push.

NOW — nothing to run yet if more grouped UI changes are coming.

NEXT — one owner-controlled pass once the grouped UI work is finished: `flutter test
test/areas test/owners test/forms`, then the scoped analyzer over `lib/src/constants
lib/src/common/data lib/src/views/Widgets lib/src/views/Screens/ViewAdd test/areas
test/owners test/forms`, then Samsung acceptance (English and Arabic, light and dark,
narrow and wide phone, a large font size): Save / Cancel visibly more compact, the same
height on all seven forms, the last field clearing them, the city pill's x easy to hit,
and the three-row areas with Show more / Show less unchanged. Only then commit.

## CITY / AREA CHIP HEIGHT CONSISTENCY — SOURCE COMPLETE, NOT RUN (2026-10-02)

Scope: the city chips, the selected-city pill and the area chips of Add Request, Add
Offer and Add/Edit Owner. Follow-up to the size-consistency section above, after the
owner saw area chips look taller than city chips on a device. It supersedes that
section's detail about the pill (which was left without a border and 38 high).
No backend, persistence or business-logic change; colours, radii, ordering,
localization, the three-row collapse, Show more / Show less and the selection caps
are unchanged.

**Traced render paths.** All six are the same chip class. Request and Offer: unselected
city chips = `SelectableChip`; selected city = `ClearableChip`; areas = `ExpandableAreaChips`
-> `SelectableChip`. Owner: `UaeCityAreaPicker` -> the same three. Same Wrap spacing, same
inherited text style (Material 3 body, 1.43 line height, identical in English and
Arabic), same padding and border tokens. So the shared tokens were NOT enough to make
the rendered geometry identical; two things in the shared file differed or could vary.

**Root cause.**
1. The selected-city pill drew no border. Every `SelectableChip` has a 1.3 border (in
   all three states), so the pill was 2.6 dp shorter than the area chips directly under
   it: about 38.0 against 40.6. This is the mismatch the owner saw once a city is chosen.
2. A chip label was allowed to wrap. The catalog has names of up to 31 characters
   ("Jumeirah Village Triangle (JVT)", "Tourist Club Area (Al Zahiyah)"); wider than the
   row on a narrow phone or at a large font, such a name wrapped to a second line and
   that one chip was about 20 dp taller than its neighbours. City names are short and
   never wrapped.
Also removed as a hazard: a line holding glyphs from two fonts (three Arabic names end
in a Latin digit, e.g. "داماك هيلز 2") can get a slightly taller line box than a one-font line.

**Fix (once, in `lib/src/views/Widgets/selectable_chip.dart`).**
- One frame for every chip, `_chipDecoration`: fill, pill corners and the 1.3 border in
  every state. `SelectableChip` and `ClearableChip` both use it; the border is drawn in
  exactly one place.
- `ClearableChip` is now a selected chip with a x: same border, same padding, same label.
  Its height is the label cell's height (an `IntrinsicHeight` row), so the x can never
  make it taller. It is 2.6 dp wider than before (the border); its x tap area is 44 wide
  by the chip's inner height, no longer 38.
- One label for both chips, `_ChipLabel`: one line (`labelMaxLines` = 1), ellipsized
  rather than wrapped, with every line forced to the line box of the style it inherits
  (`StrutStyle.fromTextStyle(..., forceStrutHeight: true)`, scaled with the text scale).
  For Latin at normal scale the line box is the one it already had (14 x 1.43).
- `ExpandableAreaChips` measures the same one-line, ellipsized label. A label wider than
  the room could only ever take the whole row, so the three-row plan is unchanged.
- Request and Offer city chips now carry the same `city-chip-<city>` keys the Owner's
  have.
- No fixed or minimum widths anywhere: a chip is still as wide as its label.

Old vs new, at normal scale: city chip 40.6, area chip 40.6 (unless its name wrapped:
about 60.6), pill 38.0. Now every one is label line + 18 padding + 2.6 border = 40.6;
the label line scales with the text scale and is the same for all of them.

**Property-type chips.** The Owner's quick-pick property types use `SelectableChip`, so
they inherit the one-line label and the same line box; their padding, border, colours and
spacing are unchanged. Request and Offer's own property-type rows are Material
`ChoiceChip`s, a different chip, and are untouched.

**Tests (source only).** New `test/forms/city_area_chip_height_test.dart`: for Request,
Offer and Owner, English and Arabic, at 320 px with large text, 360 and 412, walks the
form (city chips; the pill; collapsed areas; expanded areas, which include the longest
names; areas chosen, which also dims the rest at the Request/Offer cap) and asserts every
chip is the same height, every label is one line, and height = label + the shared padding
+ border. Further: a long name is ellipsized and still the same height; a chip never takes
more than the row; width still follows the label; three rows, the three-area cap and the
Owner's single area still hold; the pill matches a chip; source guards pin Request's and
Offer's `_CityChips` and the Owner picker to the shared components with no frame of their
own. `test/forms/control_sizes_test.dart` pill expectations were updated (same height as a
chip; 44 x inner height tap area; +2.6 width). Request and Offer's section is a private
widget, so the tests compose the same components in a stand-in and guard the screens by
source; they do not pump the real screens.

Status: **CITY / AREA CHIP HEIGHT = SOURCE COMPLETE; Flutter tests NOT RUN; analyzer
NOT RUN; device NOT VERIFIED.** The cause was derived from source, not observed on the
device. No commit or push.

NOW — nothing to run yet if more grouped UI changes are coming.

NEXT — the one owner pass already listed above (`flutter test test/areas test/owners
test/forms`, the scoped analyzer, then Samsung acceptance). On the device, check in
Request, Offer and Owner that the chosen-city pill, the area chips and the city chips are
visually one height in English and Arabic, with a long name such as Jumeirah Village
Triangle (JVT) and with a large font. If a difference remains, send a screenshot.

## SEARCH PRODUCTION READINESS — SOURCE COMPLETE, NOT RUN (2026-10-03)

Branch `search-production-readiness`, created locally from `6afd4d3` (the committed UI
checkpoint "refine property forms and shared controls"). Not pushed. Scope: the Search
screen only. No backend, migration, RLS, Worker, R2, subscription or unrelated-screen change.

**How Search works (traced, not assumed).** Search is local. It loads the signed-in user's
OWN records once (Supabase: the six core-entity services, `owner_id`-scoped with RLS;
legacy Firestore: the user's own collections), keeps them in memory and answers every query
from that copy. The only filter is the record type (All, Requested, Offers, Owners, Offices,
Brokers, Watchmen); there are no city, area, price or range filters, so none were added.
There is no pagination: the user's own records are loaded once, which is bounded by one
person's data. If a single user ever holds many thousands of records the answer is a backend
search/pagination change, which is out of scope and was not made.

**Hint jank — root cause.** The rotating hint was an `AnimatedSwitcher`, whose default
layout is a CENTRED `Stack`. While one hint is replaced by another both are on screen; the
Stack is as wide as the longer one, so the shorter hint sat in the middle of that width for
the 350 ms fade (a slide toward the centre — the right in English, the left in Arabic) and
snapped back to the start when the old hint left and the Stack shrank. Also: the screen
passed a NEW list every rebuild, which reset the rotation each time; the timer kept firing
while the tab was hidden (tickers are paused by `TickerMode`, timers are not), so swaps piled
up and replayed together on return; the hint was an overlay at a hand-set `start: 50` while
the field's own hint starts at 48. The Flutter SDK's own `InputDecorator` uses a start-aligned
layout for exactly this reason. Verified in SDK source: the decorator lays a hint WIDGET out
with a tight width equal to the input's, so a default centred switcher placed there would be
centred from the very first frame.
**Fix.** The rotating hint is now the field's own `InputDecoration.hint` (so its origin is
the static hint's, focused or not); `AnimatedSearchHints` lays every hint out with
`AlignmentDirectional.centerStart` (never moves sideways, LTR or RTL); the rotation is not
restarted by a rebuild that changes no words (`listEquals`); nothing is swapped while the tab
is hidden. The hint is styled like the field's own hint (theme input style, field style,
hint style) so size and line box match. A decoration takes `hint` OR `hintText`, never both
(SDK assert), so screen readers get the static hint through a `Semantics` label. No animation
was added to hide the bug; the existing fade and rise are unchanged.
Also in the field: the controller listener fired on every cursor move, restarting the search;
it now reports only a change of TEXT. Clearing reports once and keeps focus. The keyboard Search
action searches at once. Typing ASCII in an Arabic UI used to flip the WHOLE bar to LTR (the
search icon jumped sides); now only the typed text takes that direction.

**Filter UI.** The pinned bar was a full-width `SliverAppBar` with a page-colour container and
a drop shadow (plus the Material 3 scroll-under tint): that was the "panel". It is now flat:
no shadow, no tint, the page's own colour, still pinned. Chips: visible height
`AppControlSizes.compactChipHeight` = 36 (shared token). The old chip was padding 10+10 around
a natural 14 sp line plus a border, roughly 39 (font-dependent; not measured on a device).
Every chip is one height, selected or not, with or without the check, English or Arabic; a
fixed line box (1.2) makes that independent of the font. Each chip has a 48 dp touch target
around it (a transparent area that answers to a tap, with the chip's own ripple nearer), and
the row, and the chips, grow with a larger system font. Pill radius, colours, spacing token and
RTL order are the app's existing ones. Reset: tapping the chosen chip goes back to All; All is a
no-op when already chosen; when a filter hides every result the empty state offers "Clear Filter".

**Search logic — defects found and fixed.**
- No latest-query-wins guard and no `dispose` guard: each search is now stamped with a
  generation and a superseded one is dropped; searches that need the records share ONE load;
  a failed load is not remembered; nothing notifies after dispose.
- A failed load was swallowed and shown as "No results", or shown as a raw
  `Search failed: <exception>` string. Failures now become a kind (network, session, generic)
  that the screen words from existing localized strings; records already loaded keep serving.
  "Not asked yet", "loading", "error" and "no results" are four distinct states.
- Deleted or edited records stayed searchable for 5 minutes. The records are now marked stale
  by the existing `CoreEntityMutationNotifier`, reloaded on the next search, and refreshed when
  the Search tab is shown again; they are also reloaded when older than 5 minutes, and never
  reused for a different signed-in user.
- Matching: no multi-word AND, no trimming, no ranking (requests always first), Arabic-Indic
  digits and tatweel not handled, areas matched by raw key (Arabic area names never matched),
  Al Ain and Khor Fakkan missing from a private seven-city map, a 17-scan precomputed index
  rebuilt every cache load, exceptions used as control flow inside a state-mutating getter that
  ran per result. Replaced by `SearchText` (comparison-only folding), `SearchRanking` and
  `SearchEngine`: every word must match somewhere; names are searchable in BOTH languages from
  the app's own strings and the shared UAE area catalog; phone numbers match as stored, local
  and international; numbers match from their start only, by their whole part ("1,200.5" is
  1200); exact beats prefix beats word-prefix beats contains, weighted name > place > note,
  a phrase bonus, stable tie-break (type, title, id); records deduped by type + id (different
  types never merged; a record without an id kept with its own key).
- Arabic folding is deliberately light: diacritics and tatweel dropped, Alef variants to Alef,
  Alef Maqsura to Yeh, Teh Marbuta to Heh, Arabic-Indic digits to digits, direction marks
  dropped. Hamza on Waw/Yeh is NOT folded (so مؤمن does not match مومن). Stored values are never
  rewritten.
- Highlighting marked only the whole query as typed and used `RichText`, which ignores the
  system text size. It now marks what the search matched (each word, folded, phone numbers across
  formatting) through `Text.rich`.
- Result cards: the fixed 3:4 shape cut the third field off on a 320 px phone even at normal
  text, and at larger fonts; each card now gets at least the height its three one-line fields
  need. Cards keep their state when results reorder (`findChildIndexCallback`); the keyboard is
  put away before opening a result; dragging results dismisses it.

**Left unchanged on purpose.** Per-card favorite status reads (an app-wide pattern against an
ordering-guarded service), the cards' keep-alive and badge timers, the card visuals, navigation
routes, colours, and the 300 ms debounce (already present and within range).

**Tests (source only).** `test/search/`: `search_fixtures.dart`; `search_text_test.dart` and
`search_ranking_test.dart` (pure Dart); `search_engine_test.dart` (matching, bilingual names,
phones, numbers, ranking, filter, dedupe, stable order); `search_viewmodel_test.dart` (debounce,
latest-query-wins, shared load, freshness, user change, errors, filters, dispose);
`search_bar_test.dart` (hint position at every moment of a swap, English and Arabic, focus, clear,
typing, submit, hidden tab, rebuilds); `search_filter_chips_test.dart` (height, tap target, panel,
RTL, narrow, large text); `search_results_ui_test.dart` (highlighting and text scale, card height,
states, error safety, navigation, data scope). The two pure-Dart suites were EXECUTED with the plain
`dart` VM through a small stand-in for `expect` (32 and 20 cases, 0 failures) — that exercises the
real `SearchText` and `SearchRanking` code but is NOT `flutter test`. A Node replay of the source
guards (130 assertions) matched the real files. Nothing else was executed.

Status: **SEARCH = SOURCE COMPLETE; Flutter tests NOT RUN; analyzer NOT RUN; device NOT
VERIFIED.** Search work is uncommitted on the branch. No push.

NOW — `flutter test test/search`.

NEXT — only if that passes, the scoped analyzer: `flutter analyze lib/src/common/utils
lib/src/views/Screens/home/search lib/src/utils/text_highlighter.dart lib/src/constants test/search`;
then a Samsung check of Search in English and Arabic, light and dark: the hint never slides, the filter
chips float with the page showing around them, results never cut off a field at a large font, and a
deleted record disappears after returning to the tab.

### Search — owner verification and final polish (2026-10-03)

This addendum supersedes the "tests NOT RUN / analyzer NOT RUN / device NOT VERIFIED" lines
of the Search section above, which described the state when that work was first written.

**Verification by the owner.**
- `flutter test test/search`: all pass (282 of 282 before the final polish; PASS again after it,
  with its new tests).
- Scoped analyzer over the Search sources, `lib/src/common/utils`, `text_highlighter.dart`,
  `lib/src/constants` and `test/search`: no issues. Its first run had six findings (three
  deprecated-API uses, one unnecessary import, two unused symbols); all were corrected without
  changing behaviour.
- Samsung acceptance of Search: PASS (hint stability, filters, results, general use), then a
  quick check of the final polish below in English and Arabic, light and dark: PASS.

**Corrections made while getting there (all test-side except where noted).**
- Chip test read `en`/`ar` while tests were still being registered, before `setUpAll` ran.
- A hint test compared the Text BOX width (272, the whole input slot the field hands a hint)
  with the static hint's glyph width (247.5); it now measures where the glyphs start and end,
  and a counter-example test proves the same measurements fail for a centred switcher.
- Two touch-target tests tapped a chip that was off-screen at 360 px, and one finder also matched
  the check mark's own 16 x 16 box; the large-font test asserted a formula to the hundredth
  where the engine lays text out with its own rounding. Each now asserts the property that matters.
- Production, deprecations only: `cacheExtent` -> `scrollCacheExtent: ScrollCacheExtent.pixels(1400)`
  (the SDK's own mapping) and `TickerMode.of` -> `TickerMode.valuesOf(context).enabled` (the same
  effective value and the same dependency, so the same behaviour).

**Final Search-bar polish.**
- Height 56 -> 48: vertical padding 16 -> 12 around the one 24 dp line. 48 is Flutter's own minimum
  interactive size, so a text field is never laid out shorter; a larger system font still makes
  it taller.
- Focused border 2 -> 1.3, in the theme's primary colour (the chips' own thin line). A border is
  painted inside the field's bounds and never enters the layout, so focused and unfocused are the
  same box. Idle border, radius, icon size, hint and text fonts are unchanged.
- New shared tokens in `AppControlSizes`: `searchFieldHeight`, `searchFieldVerticalPadding`,
  `focusedFieldBorderWidth`.

Status: **SEARCH = VERIFIED BY THE OWNER (tests, analyzer, Samsung); committed locally on
`search-production-readiness`; not pushed.**

## SHARE PRODUCTION READINESS — SOURCE COMPLETE, NOT RUN (2026-10-03)

Branch `share-production-readiness`, created locally from `2e89025` (the committed and pushed Search
milestone, not reopened). **Not committed. Not pushed.** The seven generated Flutter plugin registrant files
show as modified in `git status`; they are Flutter drift, are not part of this work, and were left alone.

**Scope.** Every active Share path in the app, brought to one production path. Backend, Supabase, RLS, the
Worker, R2, migrations, `pubspec.yaml` and every package version are untouched.

### Inventory (found in source, not assumed)

| Surface | Trigger | What it did before | Now |
|---|---|---|---|
| Request details | AppBar share icon | Options dialog, text only; Request-only copy of the dialog; sent the SIGNED-IN ACCOUNT'S phone, not the Request's own; `saleRequest` missing in Arabic | Shared dialog, text; the Request's own phone |
| Offer details | AppBar share icon | Options dialog; first photo only, downloaded through the signed URL by plain `http.get`; any failure silently fell back to text only; account phone; `"** dubai not found"` could reach the message; map option enabled with no coordinates | Shared dialog; photos and videos as files; own phone; no fallback |
| Owner details | AppBar share icon | A toast reading "Share functionality: Check out this property owner: <name>" — nothing was shared | Shared dialog; text, location, map, phone, notes, private photos and videos |
| Broker details | AppBar share icon | Same toast placeholder | Shared dialog; name, phone, notes |
| Watchman details | AppBar share icon | Same toast placeholder | Shared dialog; name, building, place, map, phone, notes |
| Office details | AppBar share icon | Same toast placeholder | Shared dialog; office, manager, place, map, phone, notes |
| Quotation list card | "Share" button | PDF through the private cache file, so the receiver saw `quotation_<quotation id>_<media id>.pdf`; English text and subject hard-coded; no busy guard | Shared dialog; summary + PDF as `Broker-Wallet-Quotation-<title>.pdf` |
| PDF viewer | AppBar share icon | If a download failed it shared the LINK as text; failures showed `$e` in a toast; no busy guard | One named file; link never shared; short localized failure |
| Toolkit: combine, image-to-PDF, scanner, signed documents (single, bulk and the signature screen's multi-select) | per-document button, selection mode | Direct plugin calls; signature multi-select opened one share sheet PER file; scanner's bulk failure said "failed to delete"; two screens showed `** failedToShareDocuments not found` | One launcher; one sheet for a selection; real messages |
| Share App | Share button, targets | Main button had no busy guard and no error handling; "shared" toast shown even when the sheet was closed | One launcher; a closed sheet reports nothing |
| Search cards, Favorites cards, list cards | — | No Share control | Unchanged: none added |

### Architecture (`lib/src/services/share/`, `lib/src/views/Widgets/share_options_dialog.dart`)

- **UI — `ShareOptionsDialog`**: ONE dialog for every record. A row per part the record really has, a line
  saying what is in it, Select All (tri-state), photo/video chips, Share (off while nothing is chosen, "Preparing
  files…" while fetching, never pressable twice), Cancel, an inline reason + Retry on failure.
- **State — `ShareFlowController`**: the choices, one share at a time, the status, the failure.
- **Composer — `ShareSource`** (`PropertyShareSource` for Offer and Request, `OwnerShareSource`,
  `BrokerShareSource`, `WatchmanShareSource`, `OfficeShareSource`, `QuotationShareSource`): which parts exist, what
  starts chosen, how each part is written. Built from the record as the screen already holds it, so the message
  needs no network. `ShareTextBuilder` + `ShareFormat` write it.
- **Preparation — `SharePreparer`, `ShareMediaFetcher`**: local file → still-valid link → fresh link, streamed to
  disk; one folder per share; professional names; the extension the bytes prove.
- **Platform — `ShareLauncher` (+ `SharePlusSink`, `ShareLive`)**: the only code that touches `share_plus`; one
  sheet open at a time app-wide; an empty request is never opened; the iPad anchor is always passed.
- Duplicated logic removed: the two near-identical 700-line dialogs (and their private copies of the property-type
  and city maps); the Request dialog's area map (areas now come from `UaeAreaCatalog`); every direct
  `SharePlus.instance.share` call (15) outside `share_plus_sink.dart`.

### What is shared, and the defaults chosen (decisions to confirm)

- **Request / Offer** (the broker's own listings): everything the record has starts chosen, as before. **Contact is
  now the record's OWN phone number** (the one its detail screen shows and dials), no longer the signed-in account's.
  An Offer's photos start chosen, its videos do not.
- **Owner / Broker / Watchman / Office** (address-book records): name and place start chosen. An **Owner's** phone,
  and the private **notes** of all four, start UNchosen; Broker, Watchman and Office phones start chosen (their
  purpose is to be passed on). One tap changes any of them.
- **Quotation**: summary and PDF start chosen; the money lines start unchosen (the PDF carries them).
- A part with no data is **not shown** (it used to be a greyed "No data available" row). Media, a map and a PDF
  appear only when the record really has them.
- Rooms and bathrooms are shown only for villa, apartment and studio — the same rule the detail screens use.
- Prices: `AED 1,000,000 - 1,500,000` (English) / `1,000,000 - 1,500,000 درهم` (Arabic), a quotation in its own
  currency. Phones: the detail screens' format. Map: the detail screens' valid-coordinate rule and the same public
  link. No dates are written.
- In Arabic every label comes from the ARB file; phone numbers, links and amounts are wrapped in Unicode LTR
  isolates so their digit groups are not reversed; the person's own words are never translated; a stored Owner
  location written in either language is shown in the message's language.

### Private media and documents

- A private photo or video is addressed by its media id, never by a link: bytes already on the phone are used
  as they are; otherwise one download through a link that is still valid; otherwise ONE fresh link from the
  record's own authorized path (`OfferDetailsLoadCoordinator` / `PrivateMediaGalleryLoader.refreshSignedUrl`).
  The receiving app gets the **file**. A signed link, a media id, an object key or a bucket is never written into a
  message, a file name or a log (guarded by tests over the source).
- A video is shared as the original video file, never its poster or a link. Ceiling: 50 MB per photo and 150 MB per
  video (the app's own upload limits are 10 and 100 MB); downloads time out when stalled.
- A file keeps the extension its bytes prove (`jpg`, `png`, `webp`, `mp4`, `mov`, `3gp`, `pdf`); bytes that are not an
  accepted type are refused, not renamed. Names are `Offer-<Place>-01.jpg`, `Owner-Property-01.jpg`,
  `Broker-Wallet-Quotation-<title>.pdf`, built from letters and digits only. A place is in a file name only when the
  location is among the chosen parts; an Owner's name or place never is.
- Files are prepared in `<temporary directory>/broker_wallet_share/<millis>-<n>/`, one folder per share. A folder is
  removed at once only when nobody received it (the sheet was closed, the share was called off, preparation failed);
  otherwise folders older than 6 hours are swept before the next share. No storage permission is used or added.

### Failure behaviour

- Any file that cannot be had stops the whole share before the sheet opens — nothing is ever sent incomplete. The
  dialog stays open with the choices intact and ONE short localized sentence: connection (Retry), a file that is gone
  (the item is marked "Unavailable" and left out of the choice; sharing again is the person's decision to go on
  without it), session expired, or generic. No exception, URL, key or provider text is ever shown.
- Closing the share sheet is not an error: no message, the dialog stays as it was. Choosing an app closes it.
- Text-only shares need no network. Cached photos share offline. An uncached private file offline gives the
  connection message, never a spinner that does not end (30 s connect / idle timeouts).

### Files changed

New: `lib/src/services/share/` (`share_labels`, `share_models`, `share_format`, `share_text`, `share_source`,
`share_sources`, `share_preparer`, `share_media_fetcher`, `share_launcher`, `share_plus_sink`,
`share_flow_controller`, `share_live`), `lib/src/views/Widgets/share_options_dialog.dart`, `test/share/` (10 files).
Deleted: `ViewDetails/widgets/share_options_dialog.dart`, `ViewDetails/widgets/request_share_options_dialog.dart`.
Edited: the six `*_view_details.dart` screens (share handler + tooltip on the Share icon), `list_quotation_view.dart`,
`list_quotations_viewmodel.dart` (`resolvePdfForShare`), `pdf_viewer_screen.dart`, `combine_pdfs_view.dart`,
`image_to_pdf_view.dart`, `scanner_view.dart`, `signed_documents_storage.dart`, `signature_view.dart`,
`share_app_view.dart`, `app_en.arb`, `app_ar.arb` (+15 keys English, +16 Arabic including the missing `saleRequest`).

### Verification

- `git diff --check` clean; new files formatted (`dart format` check, 0 changes); ARB files valid JSON, CRLF kept; no
  secret, no backend file, no `pubspec.yaml` change.
- The pure-Dart Share logic was EXECUTED with the plain `dart` VM against small stand-ins for `flutter_test`,
  `package:flutter` and `cloud_firestore` (it reads the real ARB files and the real UAE catalog): format 35, sources
  62, preparer 24 (real temp files), fetcher 25 (fake network), controller 43, source guards 35, launcher 5 — all
  passed. That is **not** `flutter test`. The dialog widget tests, the `share_plus` sink tests and the quotation view-model
  mapping test were NOT executed (they need Flutter).

Status: **SHARE = SOURCE COMPLETE; Flutter tests NOT RUN; analyzer NOT RUN; device NOT VERIFIED.**

### Known limitations / backlog (not changed)

- Toolkit's own share icons are the filled `Icons.share`; the detail screens' are `Icons.share_outlined`. Both are
  consistent among themselves; harmonizing is a UI decision for the owner. The detail icons' hit area is 36 dp, like
  the Back and Delete icons beside them. The Toolkit cards' Preview and Download icons have no label.
- A receiving app may ignore the message when files are attached (Android and iOS apps decide); the ARB key
  `shareCompatibilityNote` exists but is not shown.
- An old record's HEIC photo (the app converts to JPEG now) is not an accepted type and is refused as unavailable.
- Pre-existing duplicate ARB keys `shareSelected`, `shareError`, `sharePdf` (both languages) were not touched.
- An Offer or Owner on the legacy Firebase backend shares its stored links' files as images (type from the bytes).

NOW — `flutter test test/share`.

NEXT — only if that passes, the scoped analyzer: `flutter analyze lib/src/services/share
lib/src/views/Widgets/share_options_dialog.dart lib/src/views/Screens/ViewDetails lib/src/views/Screens/home/quotation
lib/src/views/Screens/home/Toolkit lib/src/views/Screens/home/Profile/share_app_view.dart test/share`; then a device
pass (Android, and an iPad or iPhone if available), English and Arabic, light and dark: share text from each of the six
detail screens; an Offer and an Owner with several photos and a video (airplane mode with cached photos, then with an
uncached one); a quotation PDF (name, opens in the receiver); close the share sheet; double-tap Share; deselect everything.

### Share — owner's first test run and the correction (2026-10-03)

First `flutter test test/share` run: **244 passed, 35 failed**. All 35 were in `share_options_dialog_test.dart` and
had one cause, in the test harness only: the app's localization delegates load asynchronously, so `MaterialApp` draws
nothing until they finish, and `openDialog` tapped its own "open" button (and the last test its "icon" button) before it
existed ("Found 0 widgets with key <'open'>"). Fixed with a `pumpAndSettle` after `pumpWidget` in both places. No
production code changed. Every other suite in the run passed, including the `share_plus` sink tests and the quotation
view-model mapping test. The 35 dialog tests were therefore not yet exercised and need the owner's re-run.

NOW — `flutter test test/share`.

### Share — Options dialog responsive layout fix (2026-10-03)

Second `flutter test test/share` run: **272 passed, 7 failed**, all in `share_options_dialog_test.dart`: a
`RenderFlex` overflow (40 px with a media error, 68 px with an unavailable PDF, 60 px in the four large-font looks). Real
defect in `share_options_dialog.dart`: the dialog was a `Column` with a hard 600 dp ceiling in which only the option list
scrolled; the heading, Select All, the hint, the failure block and the buttons were fixed, so a failure block or a large font
pushed the fixed parts past the ceiling and the buttons off the dialog.

Fix (layout only; no controller, composer, preparer or share logic touched): heading fixed on top; one scrolling region
holding Select All, the option rows, the photo/video chips, the hint and the failure; the Cancel/Share row fixed at the
bottom. The hard 600 dp height is gone — `Dialog` already bounds its child to the screen less the system insets. A failure
is brought into view once, as it appears, and its Retry now sits under the sentence instead of squeezing it. Tests added for
a short screen at a 1.6 font (rows scroll, heading and buttons do not; Share and Retry reachable with no scrolling), the
unavailable PDF, and the buttons' order in English and Arabic; the four large-font looks now also press Cancel unscrolled.

Status: Flutter tests NOT RUN since this change; analyzer NOT RUN; device NOT VERIFIED.

NOW — `flutter test test/share/share_options_dialog_test.dart`. NEXT — `flutter test test/share`.

### Share — Options dialog: the height budget (2026-10-03, supersedes the layout note above)

The first scrolling fix still overflowed by 35 px in five tests. Cause, measured rather than guessed: at a 1.6 font in
Flutter's test font (every glyph one em wide) the title and subtitle wrap in a 132 px column to about 450 px. That fixed
heading + two 20 px gaps + the 48 px button row = 539 px against the 504 px the content box has (screen 600 − 2 × 24 dialog
inset − 2 × 24 padding), so the rows were given 0 px, the scroll region had nothing to scroll in, and the column itself
still overflowed. Scrolling the rows could not help because the heading was unbounded.

Fix (layout only): one bounded column inside a `LayoutBuilder` that reads the real available height. Budget = buttons
(48) + two gaps (40) + rows (at least 30% of the height) + heading (the rest, scrolling inside its own space only if a very
large font or a narrow dialog needs more). The rows scroll in their own region; Cancel/Share stay fixed under it.
Real-device fonts never reach the heading's cap at normal settings. The tests address the two scroll regions by key
(`share-header-scroll`, `share-body-scroll`) and now also check that heading, rows and buttons are stacked without overlap.

Status: Flutter tests NOT RUN since this change; analyzer NOT RUN; device NOT VERIFIED.

NOW — `flutter test test/share/share_options_dialog_test.dart`. NEXT — only if all of it passes: `flutter test test/share`.

### Share — owner results and analyzer cleanup (2026-10-03)

`flutter test test/share`: **287 of 287 PASS** (owner-reported). Scoped analyzer: 30 findings = 17 warnings + 13 infos.

- The 17 warnings were all Share-introduced: literal bidi control characters (U+2066 / U+2069) in `share_format.dart`,
  `share_format_test.dart` and `share_sources_test.dart`. They are now written as `⁦` / `⁩` escapes (and the
  invisible U+200E likewise); the runtime strings are identical, so Arabic phone numbers, links and amounts keep their
  left-to-right isolation.
- Of the 13 infos, ONE was Share-introduced: the `offer_media_cache_identity.dart` import added to
  `owners_view_details.dart` (`media_gallery_widget.dart` already re-exports `OfferMediaRef`); removed.
- The other 12 are PRE-EXISTING at `2e89025` and untouched: `add_quotation_view.dart` `Color.red/green/blue` (3),
  Toolkit `onReorder` in `combine_pdfs_view.dart` and `image_to_pdf_view.dart` (2), `scanner_view.dart` `Radio.groupValue` /
  `onChanged` on three radios (6), `toolkit_view.dart` `Color.value` (1). Left as they are on purpose.

Status: Share = tests PASS (287/287, owner); analyzer re-run pending; device NOT VERIFIED.

NOW — `flutter test test/share`, then the scoped analyzer.

### Share — Arabic Offer message polish (2026-10-03)

The Arabic Offer message now uses the requested title, natural localized property type,
clean rent/sale wording, nonduplicated area label, singular/plural UAE area label, and
Offer-specific footer. User-entered text and existing bidi isolates are unchanged.
English and other entity messages, share logic, media, and security are unchanged.
This polish has had source/diff review only; Flutter tests and analyzer were not run
per owner instruction. Samsung/WhatsApp runtime verification is pending.

NOW — share an Arabic Offer on Samsung to WhatsApp and check the received text,
including number direction, singular and multiple areas, and unchanged notes.

NEXT — after that succeeds, record the device result and resume the broader Share
verification from the previous checkpoint.

### Share media selection — source checkpoint (2026-10-03)

Branch `share-media-selection-readiness` starts at `c9e25d4d8379d1040f3a0dca26a9a05da2970b55`.
The prior Share flow is committed; this checkpoint is uncommitted and unpushed.
Source tracing found no one-file truncation in the existing preparer or
`SharePlusSink`; the Samsung one-file symptom remains to be retested. The
visible gap was numbered media chips and no current-item Share handoff from
the full-screen viewer.

- Offer and Owner Share Options now open a separate visual media picker from the
  Media row. A lazy two/three-column grid uses the gallery's local/cache image
  path at thumbnail decode size; videos use only a poster already on the device
  or a video icon. The Share Options dialog shows a selected count and compact
  preview. The picker drafts changes until Done; Cancel keeps the earlier set.
- Current private media is selected by `mediaObjectId`, with a stable hashed
  path fallback for legacy records without IDs. Selection, deduplication and
  final file ordering do not depend on gallery index or signed URL query.
  Detail Share retains its photo-first default. The Offer/Owner full-screen
  viewer now opens the same Share Options flow with its current item selected;
  the picker can add more.
- The controller prepares only the confirmed keys, in source order, and reports
  completed-file progress. The existing sequential fetch path checks local
  bytes/cache first, then an authorized private download only for selected
  uncached items. The original files go as one XFile list in one platform call.
  A failed selected file still blocks the entire share; unavailable items are
  deselected and cannot be reselected; existing cancellation and temp cleanup
  remain in use. No backend or security changes were made.
- Targeted test source was updated for picker selection, Cancel/Done, detail
  and viewer defaults, thumbnails/posters/placeholders, short Arabic layout,
  stable keys, progress, and selected multi-file behavior. Flutter tests NOT
  RUN; analyzer NOT RUN; device NOT VERIFIED. Source parsing and diff review
  only, including ARB JSON validation and `git diff --check`. Generated Flutter
  registrant drift remains unrelated and untouched.

NOW — `flutter test test/share`.

NEXT — only if that passes, run `flutter analyze lib/src/services/share lib/src/views/Widgets/share_options_dialog.dart lib/src/views/Widgets/share_media_picker.dart lib/src/views/Screens/ViewDetails/offers_view_details.dart lib/src/views/Screens/ViewDetails/owners_view_details.dart lib/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart lib/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart test/share`, then verify on Samsung with several photos and a video.

### Share media selection — owner test correction (2026-10-03)

The owner ran `flutter test test/share` and reported 291 PASS, 2 FAIL. No Flutter
command was run during this correction. The status test expected one listener
notification per status, but preparation now also notifies for its file count;
the test checks collapsed status transitions and monotonic 0/3 through 3/3
progress while preserving production notifications. The short Arabic picker
test now scrolls the keyed Share Options body until Media is hittable, checks
that the body can scroll and fixed actions are reachable, and exercises picker
Cancel and Done. No production layout change was needed from source review.

Normal visual picker tests now use the project's decodable JPEG asset rather
than magic-prefix-only bytes. One explicit broken-poster test keeps image-load
fallback coverage. Multi-file tests explicitly assert one native request with
all selected files, source order, stable-ID deduplication, and that an
unselected remote image is never fetched. This correction changed test source
only; generated registrant drift remains untouched. `git diff --check` PASS;
Flutter tests NOT RUN here, analyzer NOT RUN, device NOT VERIFIED.

NOW — `flutter test test/share`.

NEXT — after the owner reports a passing full Share suite, run the scoped
analyzer for the media Share source and tests, then verify on Samsung.

### Share media picker — final widget test hardening (2026-10-03)

The owner's next `flutter test test/share` run again reported about 293 PASS and
2 FAIL: the short Arabic test still could not hit Media, and the broken-poster
test could not find its exact icon. Flutter's `scrollUntilVisible` skips its
drag loop for an eagerly built row and then aligns its leading edge; that did
not establish a tappable center in the short viewport. The actual Share
Options body is the keyed `share-body-scroll`
`SingleChildScrollView`, inside the fixed heading/footer column. A shared
test helper now centers every tapped option in that body's own Scrollable,
checks its viewport/target rectangles and footer clearance, then taps it.
Picker tiles use the same geometry check with the keyed lazy grid scroll view.
The short Arabic test checks pre-scroll geometry and the fixed actions remain
reachable; the helper checks the Media center inside the body after scrolling.

The picker now gives its existing photo/video placeholders and video indicator
stable keys; no visual layout or multi-file logic changed. Tests assert those
keys and selected semantics instead of icon internals. A deliberately missing
video poster exercises the immediate fallback deterministically; normal
thumbnail tests still use a validated decodable project JPEG. The viewer swipe
uses its measured page width. Every option-row tap and picker-tile tap in the
Share Options widget test now goes through the same scoped helper. Source-only
parse/diff review and `git diff --check` PASS; Flutter tests NOT RUN here,
analyzer NOT RUN, device NOT VERIFIED. Unrelated generated registrant drift
remains untouched; no commit or push.

NOW — `flutter test test/share`.

NEXT — after the owner reports a passing full Share suite, run the scoped
analyzer for the media Share source and tests, then verify on Samsung.

### Share multi-media message and video previews — source checkpoint (2026-10-03)

> Superseded for two or more files by the next section (2026-10-04): the
> clipboard lifecycle and the dialog note below describe the earlier contract,
> where the message also travelled with several files. The video-preview
> paragraphs stand unchanged.


Two real-device defects from the Samsung run, both source-only here: some
videos in Select Media had no recognizable frame, and the multi-file message
lifecycle was described inconsistently. This section replaces the earlier
"multi-media message" note, which described a SnackBar that has been removed.

**Video preview root cause.** The gallery's video tile, the full-screen viewer's
thumbnail strip and the form media grid all draw a video through
`OfferVideoPoster`. It resolves the record's own frame (`posterPath`), then the
frame this device keeps under the video's stable identity
(`offerMediaPosterKey(cacheKey)`), then — for a ready video with neither — makes
one on demand through `OfferVideoPosterService.ensure` (the existing
`video_thumbnail` dependency, Android `MediaMetadataRetriever`, which reads only
the index and first frame of the signed link, never the whole video; verified in
`video_thumbnail 0.5.6`'s `VideoThumbnailPlugin.java`) and keeps it. The server
stores no poster, so a frame exists on a device only after some tile of that
video was drawn there (the gallery is a lazy `PageView`; a video the person never
swiped to, or any video after a reinstall, has none). `ShareMediaPreview` stopped
after step two on purpose ("never fetch a video for a preview") and skipped the
on-demand step, and being a stateless widget it also never noticed a frame made
a moment later. Result: exactly those videos fell to the placeholder, plus a
second generic play badge on top of it. Not a model problem: `ShareMediaItem`
keeps the whole `OfferMediaRef`, including `posterPath`, `cacheKey` and the link.

**Video preview fix.** `ShareMediaPreview` (the one widget behind both the
picker's tiles and the compact summary in Share Options) now draws a video with
`OfferVideoPoster`, the gallery's own widget, so the two cannot disagree and a
frame made by either is found by the other:

1. the frame the record carries; 2. the frame this device keeps; 3. one frame
made once, from the original when this device already holds it (no network),
else from the link the record already holds, then kept; 4. one plain video
placeholder. No link is refreshed for a preview and no video is downloaded: the
picker holds no `refreshLink` and no fetcher, and frames are made lazily, one at
a time, only for tiles that are built. The play badge is now drawn only over a
real frame (new optional `OfferVideoPoster.frameOverlay`, built through
`Image.frameBuilder` so an undecodable frame shows the placeholder alone); the
placeholder carries a single video icon.

**Legacy and data-shape limits (stated, not hidden).** A video gets no frame
when: it has no stable identity (`cacheKey == null`: an old record or a Firebase
Owner that only has a stored link, `mediaObjectId == ''`), because a frame is
kept under, and owned through, the account-scoped media id; it has no link and no
kept frame (the Offer media resolution did not run or its link expired) because
previews do not refresh links; the platform cannot read its first frame; or a
recent attempt failed (retried after two minutes). These show the placeholder,
which is a fallback and not equivalent to a thumbnail. Observed, not changed:
Offer refs built by `_refsFromOffer()` carry no `isVideo`, and `ShareMediaItem`
classifies by `isVideo` only while the gallery also classifies by URL extension.
No dependency was added or needed.

**Clipboard lifecycle (corrected contract, implemented and tested).**
- Preparation fails, or the share is called off before it is handed over:
  clipboard untouched, sheet not opened.
- A sheet is already open (the app-wide launcher): `busy`, clipboard untouched.
  This check now runs before the copy.
- Two or more photos or videos prepared, with a message: the message is copied
  once, then the native share is called once with all files and the same text.
  From the copy on the share is committed: nothing can call it off between the
  copy and the native call, so the clipboard is never written for a share that
  is then cancelled.
- The sheet closed unused after it opened is not an error and the copy stays; a
  sheet that cannot be opened leaves the copy where it is. The earlier clipboard
  is never read, restored or cleared.
- One photo or video, or no message: no copy, unchanged behavior. A clipboard
  that fails or throws never holds the share back; the text still goes to the
  platform.

**Notice.** The previous 8-second SnackBar was removed (it would sit under the
native sheet on Android and, on Android 14+, is raised only after the app was
already in the background). The Share Options dialog now shows a short note
under the Media row, before Share is pressed, only while a share really would
copy: "Details are copied when you share several photos or videos. If the app
doesn't attach the text, paste it in the chat." (key `shareDetailsCopyNote`,
Arabic included). It follows the selection, stays after a closed sheet, and
disappears if the clipboard ever refuses. No confirmation step. It is present
tense because it is read before the copy happens.

Tests (source only, NOT RUN): new `test/share/share_media_preview_test.dart`
(carried frame, kept frame, frame made once from the link, from the original,
picker and compact summary sharing one read, failure, missing frame file, no
identity, no link); controller tests for every lifecycle rule above; dialog tests
for the note (shown before sharing, Arabic, absent for one photo, follows the
choice, stays after a closed sheet, withdrawn after a failed copy) and for the
tile contract (frame + badge, placeholder alone); source guards for the shared
widget, no refresh/download in the picker, the badge, one copy moment in order,
and no SnackBar. `dart format --output=none --set-exit-if-changed` passes for the
new and rewritten files and every touched file apart from deviations that were
already in two test files; `git diff --check` PASS. Flutter tests NOT RUN,
analyzer NOT RUN, device NOT VERIFIED. No backend, Supabase, RLS, Worker or
upload change. Generated registrant drift untouched; no commit or push.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`.

NEXT — after it passes, the scoped analyzer from the previous checkpoint with
`share_clipboard.dart` and `offer_video_poster.dart` added, then on the Samsung
phone: open Select Media on an Offer with several videos you never opened in the
gallery (frames should appear one at a time and match the gallery afterwards);
note any video that stays a placeholder (legacy/no link); share three photos to
WhatsApp and confirm the note was visible before pressing Share and that pasting
the details works if the caption is empty.

### Share media batch architecture — Samsung / WhatsApp evidence and correction (2026-10-04)

> Superseded by the next section (2026-10-04, native Android transport): the
> product owner rejected the photo/video split and the files-only rule. Nothing
> below the evidence list describes the current behavior; only the evidence and
> the `share_plus 11.1.0` inspection still stand.


Owner verification before this change: `flutter test test/share` = 333 PASS;
scoped analyzer clean before the latest runtime-specific source work; the media
picker accepted visually on the device; the video-poster work implemented and its
tests passing. None of that is reopened here.

**Real Samsung / WhatsApp results (owner device evidence, authoritative).**
- One image + the Offer details: PASS (WhatsApp receives the image and the full
  text).
- One video + the Offer details: PASS (the video and the full text).
- Several images (5 tried): every image arrives, but WhatsApp attaches the same
  Offer text to every image, so each image carries a repeated caption.
- More than one media item that includes video (several videos, an image and a
  video, images and videos): the batch is not reliably delivered. Observed:
  media does not arrive, sometimes only the text arrives.

**Source inspection of the locked `share_plus 11.1.0` (pub cache, Android).**
- Dart (`MethodChannelShare._toPlatformMap`): one `paths` list and one
  `mimeTypes` list, in the order of the `XFile`s; each type is
  `XFile.mimeType ?? lookupMimeType(path)`. `cross_file`'s `XFile` returns the
  explicit type it was given and never infers one, so the types the preparer
  proved from the bytes are what the plugin sees. A files-only request is valid.
- Android (`Share.kt`): no file is `ACTION_SEND` `text/plain` with `EXTRA_TEXT`.
  Each file is copied into `cacheDir/share_plus/<file.name>` and addressed by a
  `FileProvider` content URI (a name collision overwrites, ours never collide;
  the folder is emptied at the start of every share). One file is `ACTION_SEND`
  with that file's type; two or more are `ACTION_SEND_MULTIPLE` with
  `EXTRA_STREAM` as the URI list and `type = reduceMimeTypes(...)`: the exact
  type when all are identical, `family/*` when only the family is shared (for
  example `video/mp4` + `video/quicktime` → `video/*`), `*/*` as soon as the
  families differ. `EXTRA_TEXT`, subject and title are added to the single and
  to the multiple intent alike, when not blank. `FLAG_GRANT_READ_URI_PERMISSION`
  is set on the inner intent; the plugin also grants read and write on every URI
  to the packages that resolve the chooser intent (the system chooser), and the
  framework moves the grant and the `ClipData` it builds from `EXTRA_STREAM` to
  the app the person picks. Everything is wrapped in one `Intent.createChooser`
  started once.
- Conclusion: for a single-family batch the plugin emits the correct, ordinary
  Android payload, so it is retained. A mixed photo/video batch is expressed by
  the plugin as `*/*`, which is exactly what real WhatsApp does not take
  reliably. The plugin cannot make a receiver use `EXTRA_TEXT` the way Broker
  Wallet wants.

**What was ours and what is the receiver's.**
- Ours: we sent the composed message as `EXTRA_TEXT` with every multi-file
  request (the cause of the per-image caption: the receiver chose to attach it to
  each image), and we launched a photo/video mix as one generic `*/*` request.
  Preparation itself held up under inspection: every selected video is fetched
  through the authorized path, written with the extension its own bytes prove,
  typed from those bytes, uniquely named and passed as one explicitly typed
  `XFile`; all-or-nothing preparation, existence and size are checked before the
  sheet opens. No text-only request replaces an attachment request.
- The receiver's (not an app bug, and not something the app can change): whether
  WhatsApp shows, repeats or drops a message that comes with several files, and
  whether it accepts a `*/*` batch. The multi-video failure observed with the
  message attached cannot be traced to our files from source; the corrected
  payload removes everything optional from it. If a video-only batch with no
  message still fails on the device, the next suspects are the plugin's
  synchronous per-file copy of large videos on the platform thread and WhatsApp's
  own limits; only then would a narrow native adapter be justified. None is
  written: it is not proven necessary.

**The contract (one place: `SharePayload.plan`, fed by `MediaSharePlan`).**
- 0 files: the message alone. 1 file: the file with its message, clipboard
  untouched (image and video, as accepted).
- 2+ files of one family: the files ONLY in the native request (no text, no
  subject), types explicit and proven; the whole message copied to the clipboard
  once, immediately before the sheet opens; one native call; the gallery's order.
- A choice that mixes photos and videos is never launched as one batch. Share
  asks once ("For reliable sharing, photos and videos are shared separately."):
  Share photos (n) / Share videos (n) / Back. Only the chosen batch is fetched,
  prepared and shared; the other is neither downloaded nor touched. After a batch
  is handed over the dialog stays open, the shared items leave the selection, a
  note says what is still chosen ("Photos shared. Videos still selected: 1. Tap
  Share to send them."), and the next Share sends it directly, with no second
  sheet opened by itself. A closed sheet leaves the selection as it was. The
  picker still lets photos and videos be chosen together; Share Options shows
  the real breakdown ("Photos: 3 · Videos: 2").
- After preparation the files' own proven types are checked again: a batch that
  turns out to mix families (a record that misdescribed one of them) is never
  launched; it fails safely with the generic message and nothing is copied.
- Clipboard moment unchanged: preparation done and nothing left to cancel it,
  no sheet already open, copy, then the single native call; a closed sheet or a
  sheet that cannot open leaves the copy, the earlier clipboard is never
  restored. Decision the owner may reverse: if the clipboard refuses (or the
  engine has none) the details travel with the files after all, because nothing
  else would carry them; this is the only way text reaches a multi-file request.
- The dialog note is read before Share is pressed and says what will happen: "The
  details are copied when you share several photos or videos. After sending the
  media, paste them into the chat." It appears only when some batch holds several
  files and a copy is possible.
- Policy versus transport: the rule above applies on Android, where one intent
  carries the files and the receiver decides. On iOS and the other platforms
  (`ShareTransport.systemSheet`, chosen once in `ShareLive.engine()`) the share is
  exactly as before: every file and the message in one system sheet, no question,
  no copy. The widgets hold no MIME, platform or payload logic.
- Offer and Owner use the one media path, so both get it; text stays
  entity-specific. The quotation PDF is one file with its message and is
  untouched. Nothing private is exposed: files are fetched through the existing
  authorized path into the app's temporary folder, links are never written
  anywhere, and the clipboard holds only the accepted human-readable message.
  No backend, Supabase, RLS, Worker or upload change.

Files: new `share_media_plan.dart`, `share_payload.dart`,
`views/Widgets/share_batch_choice.dart`; changed `share_flow_controller.dart`,
`share_models.dart` (file family), `share_live.dart` (transport),
`share_options_dialog.dart`, both ARBs (`shareDetailsCopyNote` reworded; new
`shareBatchExplain`, `shareBatchPhotos`, `shareBatchVideos`, `shareBreakdown`,
`shareBatchRemainingVideos`, `shareBatchRemainingPhotos`).

Test source (not run): new `share_media_plan_test.dart` (classification and the
payload rule); `share_flow_controller_test.dart` (0 media, 1 image, 1 video, 3
images, 3 videos with type/extension/bytes/order, mixed question without side
effects, photos batch, video batch, the next Share, failure, repeated tap,
clipboard lifecycle, system sheet, misdescribed file); `share_options_dialog_test.dart`
(breakdown, question, Back, Arabic, double tap, photos batch, video batch, notes);
`share_launcher_test.dart` (the plugin receives files only, one call, typed);
`share_source_guards_test.dart` (one place for the request, decision order, pinned
`share_plus`, no widget policy, strings in both languages).

Verification: `dart format --output=none --set-exit-if-changed` passes for every
new file and every touched file apart from deviations already in two test files;
ARB JSON parses; `git diff --check` PASS. Flutter tests NOT RUN, analyzer NOT
RUN, device NOT VERIFIED. Generated registrant drift untouched; no commit, no
push.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`.

NEXT — if it passes, the scoped analyzer (add `share_media_plan.dart`,
`share_payload.dart`, `share_clipboard.dart`, `share_batch_choice.dart`,
`offer_video_poster.dart`), then on the Samsung phone with WhatsApp: 1 image and
1 video (unchanged); 3 images (arrive as one batch with no repeated caption, then
paste the details once); 3 videos (one batch of three); photos + videos (the
question, photos first, then Share again for the videos, no second sheet by
itself). Report any batch that still does not arrive; that evidence decides
whether a narrow native adapter is needed.

### Share native Android multi-media transport — correction (2026-10-04)

> Superseded by "Share final reliable media flow" below (2026-10-04): the
> single native batch for photos and videos together, the family-wildcard and
> message-extra experiments, and the message travelling with several files no
> longer describe the behavior. Only the evidence stands.

Owner verification before this change: `flutter test test/share
test/offers/offer_video_poster_test.dart` = 392 PASS; scoped analyzer no issues;
video previews working. Not reopened.

**Latest real Samsung / WhatsApp observations (owner device evidence).**
- One image + the Offer text: works. One video + the Offer text: works.
- A scalar `EXTRA_TEXT` with several images (the original `share_plus` payload):
  every image arrives, but WhatsApp repeated the same Offer text on every image.
- Generic mixed photo/video batches (`*/*` through `share_plus`): unreliable.
- Several images as files only (the previous correction, text omitted by design):
  the images arrive but no Offer text arrives automatically.
- The split-media compatibility dialog ("photos and videos are shared
  separately", Share photos / Share videos / Back): rejected by the product owner.
  The media picker is the only place the person chooses which media goes.

**What was removed.** The photo/video choice (`share_batch_choice.dart`, its
dialog flow, `ShareFlowResult.chooseBatch`/`batchShared`, the remaining-batch
note, the deselect-after-sharing rule), the media-plan classification
(`share_media_plan.dart` and its test), the Android/iOS `ShareTransport` split,
the "several files carry no message" rule and its clipboard-refusal exception,
the mixed-family refusal, and the strings `shareBatchExplain`, `shareBatchPhotos`,
`shareBatchVideos`, `shareBatchRemainingVideos`, `shareBatchRemainingPhotos`. The
two earlier 2026-10-04 and 2026-10-03 notes about those rules are superseded.

**The contract (one place: `SharePayload.plan`).**
- No file: the message alone, system share. One file: the file with its message,
  system share (`share_plus`), clipboard untouched. Both exactly as accepted.
- Two or more photos and videos (a media batch), in any mix: ONE request carrying
  EVERY chosen file in the order chosen, with the message supplied to the
  platform, and the same message copied to the clipboard once, immediately before
  the sheet opens, as a secondary fallback that never replaces sending the text.
  One Share press, one share sheet, nothing asked in between. The media family
  never changes which files go; it only decides the declared MIME type.
- Preparation failure, a share called off, or a sheet already open: nothing is
  copied and nothing is launched. A closed sheet leaves the copy; the earlier
  clipboard is never restored. Share Options still shows the count, thumbnails and
  an informational "Photos: n · Videos: n" line when both kinds are chosen, and a
  note, read before Share is pressed, that the details are copied for several
  media.

**Platform boundary (Android only; the decision is in `ShareLive` alone).**
`ShareLive.launcher` wraps the system share in `AndroidMediaBatchSink` on Android;
elsewhere it is the system share as before (iOS unchanged). The sink hands only a
request marked `mediaBatch` with two or more files to the native adapter over the
MethodChannel `com.example.broker_wallet/multi_media_share`, method
`shareMultipleMedia`, arguments `paths` (local files, in order), `mimeTypes` (the
type each file's bytes proved) and `text`. Anything else, including the Toolkit's
own files, takes the system share. A started chooser reports nothing back, so the
outcome is "unknown", which the flow treats as done. A native refusal or a
missing adapter is a `ShareFailure`, never a silent fall back to the old path.

**Native side (`MultiMediaSharePlugin.kt`, registered in `MainActivity` the way
`FileSaverPlugin` is; no second engine).** It receives local prepared files only,
never a link, id or key, and decides nothing about what is shared.
- URIs: each path must lie inside `cacheDir/broker_wallet_share` (the folder the
  share staging already uses, one subfolder per share) and be a readable file; it
  is turned into a `content://` URI by `BrokerWalletShareFileProvider`, a
  `FileProvider` subclass of its own with authority
  `${applicationId}.brokerwallet.shareprovider`, not exported, `grantUriPermissions`,
  whose paths file exposes that one cache folder and nothing else. No copy is made
  (so a large video is not duplicated), names stay unique with their real
  extensions, no `file://` is ever used, and the existing broad provider is left
  alone. The staging sweep still removes old folders.
- Intent: `ACTION_SEND_MULTIPLE`; `EXTRA_STREAM` is the `ArrayList<Uri>` of every
  file in the given order; `FLAG_GRANT_READ_URI_PERMISSION`; one `ClipData` with
  one item per file, in order, and a `ClipDescription` listing the distinct real
  types; started once through `Intent.createChooser`, which (Android 34 source,
  `Intent.createChooser`) copies the target's `ClipData` and permission flags onto
  the chooser so the receiving app is granted every URI.
- Type (`MultiMediaShareFormat.commonMimeType`): all identical → that exact type;
  different image formats only → `image/*`; different video formats only →
  `video/*`; photos mixed with videos (or anything not shaped like type/subtype)
  → `*/*`. Types are never changed to suit a receiver.
- Message: `EXTRA_TEXT` as an `ArrayList<CharSequence>` aligned with the
  attachments (`MultiMediaShareFormat.buildCaptionList`): the whole message first,
  an empty caption for every other file; never also a scalar under that key. This
  is the aligned form Android's own `Intent.migrateExtraStreamToClipData` reads
  (it requires the list to be as long as `EXTRA_STREAM`, and builds one
  `ClipData` item per attachment holding that attachment's text and URI), so each
  clip item here carries its caption as that code would. The one gradle change is
  the explicit `androidx.core:core:1.13.1` line the `FileProvider` subclass needs,
  already in the build through `share_plus`; no third-party dependency, no
  Gradle test dependency. Kotlin unit tests were not added for that reason; the
  two helpers are pure Kotlin and pinned by source guards.
- Errors reach Dart as fixed words only: no path, name or message.

**What is not guaranteed.** What WhatsApp (or any receiver) does with the
per-attachment text list, with `*/*`, and with several videos is the receiver's
choice and has NOT been verified: it may show the message once, repeat it, ignore
it, or not read the list form at all. The clipboard copy is the fallback for that.
Receiver behavior needs Samsung / WhatsApp verification; nothing here claims it.

**Security.** Private media stays: authenticated app retrieval, local prepared
file in the cache, `content://` URI with a temporary read grant, the share sheet.
No signed URL, R2 key, media id, service-role data or Worker endpoint is passed to
native code or into a message; the clipboard holds only the accepted
human-readable message. No backend, Supabase, RLS, Worker or upload change.

Test source (not run): `share_payload_test.dart` (0 / 1 / 2+, mixed order, no
family rule, documents), `share_android_sink_test.dart` (routing, exact channel
arguments, order, MIME list, text, local paths only, native refusal, missing
adapter, one sheet), `share_flow_controller_test.dart` (0 media, 1 image, 1 video,
3 images, 3 videos, interleaved photos and videos in one request in the order
chosen, failure, repeated tap, clipboard lifecycle), `share_options_dialog_test.dart`
(no question, one request for a mixed choice, breakdown, wait, notes),
`share_launcher_test.dart` (the plugin boundary for a batch), and
`share_source_guards_test.dart` (the request is built in one place, no widget
policy, the retired architecture is gone, Kotlin/manifest/paths/Dart constants
agree, `ACTION_SEND_MULTIPLE` + `ClipData` + list `EXTRA_TEXT` + read grant, no
scalar text, no `file://`, one narrow provider path). Format, ARB JSON and
`git diff --check` pass; Flutter tests, analyzer and the Android build were NOT
RUN; device NOT VERIFIED. No commit, no push.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`.

NEXT — if it passes, the scoped analyzer (add `share_android_sink.dart`,
`share_payload.dart`, `share_clipboard.dart`, `offer_video_poster.dart`); then a
full Android rebuild and install (Kotlin, manifest, a new XML resource and a
Gradle line changed, so a hot restart is not enough); then on the Samsung with
WhatsApp: 1 image and 1 video (unchanged); 3 images; 3 videos; 2 photos + 2
videos (one chooser, all four, in order); and note for each whether the Offer
text arrived, once or repeated, and whether pasting the copied details works.
That evidence decides the next step; no further transport change before it.

### Share native transport — double-tap test correction (2026-10-04)

Owner run of `flutter test test/share test/offers/offer_video_poster_test.dart`
after the native Android routing: 390 PASS, 1 FAIL — "a double tap on Share
opens one share sheet" (`realUntil` timed out waiting for a request to reach the
sink).

Root cause: a test-harness defect, not a production bug and not the routing. The
test chose the video (two photos and a video, a batch of three) but never served
the video's download, so `FakeNet` answered 200 with an empty body, the fetcher
rejected it as unavailable (`received == 0`), preparation failed, and nothing was
ever handed to the sink to be waited for. The fake sink was already the sink the
controller launches through, nothing was routed elsewhere, no wait depended on a
retired counter, and the controller's busy lock was correct throughout: it is
taken inside `share()` before its first await, so a second tap cannot enter the
pipeline.

Correction (tests only): the test now serves the video, holds its download open
with a gate and keeps the share sheet open with the fake sink's existing `hold`,
so every phase is observable without a clock. It checks the lock after two taps
with no frame between them, again while preparation is held at the download, and
again while the sheet is open: one download, no copy before the hand-over, one
copy, one request to the Android multi-media transport and none to the system
share, then the share completes. `FakeShareSink` gained `nativeRequests` and
`systemRequests`, derived from the production routing predicate
(`AndroidMediaBatchSink.takes`) over the one `requests` list. The related tests
(controller repeated tap, a new held-batch variant, the dialog's mixed share, the
wait test, the two-photo note test, and the single-file and message-only double
taps) assert the 0 / 1 / 2+ routing. No production file changed.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`. NEXT is
unchanged: scoped analyzer, full Android rebuild, then Samsung / WhatsApp.

### Share native transport — WhatsApp all-types finding and correction (2026-10-04)

> Superseded by "Share final reliable media flow" below (2026-10-04): the
> single native batch for photos and videos together, the family-wildcard and
> message-extra experiments, and the message travelling with several files no
> longer describe the behavior. Only the evidence stands.

Owner device result with the native Android transport: photos and videos chosen
together, Share, the chooser lists the apps with the media shown; choosing
WhatsApp answers "can't send empty message".

Root cause: the batch was declared as the all-types wildcard. WhatsApp reads an
`ACTION_SEND_MULTIPLE` declared as all types as a TEXT-ONLY share and ignores
every file in it. That matches every mixed-media observation on this device: with
a scalar message WhatsApp sent the message alone ("sometimes only text arrives");
with no scalar message (the per-attachment text list) there was nothing to send
and WhatsApp reported an empty message. An independent report describes the same
behavior in another plugin ("sharing several images with text to WhatsApp only
sends the text (intent type forced to all types)": WhatsApp treats it as a
text-only share and drops the images; a `ClipData` over all the URIs was not
enough, the MIME type was the deciding factor). The all-types declaration for a
photo/video mix was the written spec, so this was a wrong assumption of ours, not
a random receiver fault.

Correction (Kotlin and its guards only; the Dart flow, routing, picker and
clipboard are unchanged):
- Declared type (`MultiMediaShareFormat.commonMimeType`): identical types give
  that exact type; several formats of one family give its wildcard; photos mixed
  with videos give the wildcard of the family most of the files belong to (a tie
  goes to the family seen first), never the all-types wildcard. The all-types
  type remains only for an empty or malformed type list. The files themselves are
  not relabelled: each keeps its own extension and proven type, the provider
  answers each URI with its own type, and the `ClipDescription` lists every
  distinct real type. Only the batch-level wildcard is chosen so that WhatsApp
  reads the files. Whether WhatsApp then takes the videos of a mixed batch
  declared as the image family (or the images of one declared as the video family)
  is NOT verified.
- Message: the ordinary `EXTRA_TEXT` string, once. The per-attachment list with
  empty captions is removed (`buildCaptionList`, `putCharSequenceArrayListExtra`,
  the text in the clip items): it was never confirmed to be read by any receiver,
  and the one form WhatsApp is known to read beside a batch is the string. The
  clip items hold only their URI again.
- Known and accepted trade-off, to be judged on the device: WhatsApp shows the
  message string as the caption of every item of a batch (observed earlier with
  images). The clipboard copy (once, before the sheet) stays as the fallback and
  as the way to paste the details a single time. If a once-only caption matters
  more than delivery, the per-attachment list can be tried again later as its own
  experiment, with the type fixed.
- Guards now pin: the string message and no list, URI-only clip items, the family
  wildcard rule, and that the all-types type is returned only for no types or a
  malformed type.

Not changed: the media picker, posters, the 0 / 1 / 2+ rule, the MethodChannel,
the FileProvider, the clipboard behavior, the share text, backend. Flutter tests
NOT RUN, analyzer NOT RUN, Android build NOT RUN, device NOT VERIFIED.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`, then a
full Android rebuild and install (Kotlin changed; a hot restart is not enough).

NEXT — on the Samsung with WhatsApp: 2 photos + 2 videos (the failing case), 3
images, 3 videos, 1 image, 1 video. For each: do all the files arrive, does the
message arrive and on how many items, and does pasting the copied details work.
That is the evidence for any further change.

### Share final reliable media flow — one choice, homogeneous batches (2026-10-04)

Owner verification before this change: `flutter test test/share
test/offers/offer_video_poster_test.dart` passing before the transport
experiments; scoped analyzer clean; video previews accepted. Not reopened.

**Real Samsung / WhatsApp evidence (owner device, authoritative).**
- One image + the Offer text: PASS. One video + the Offer text: PASS.
- Several images with the message as a scalar text: all arrive, WhatsApp repeats
  the same text on every image.
- Several images with no platform text: they arrive, no automatic caption.
- Photos mixed with videos declared as all types: WhatsApp does not deliver the
  media reliably (it reads such a share as text only and drops the files; an
  independent report of another plugin describes the same).
- The per-attachment list form of the text extra: WhatsApp answered "can't send
  empty message".
- The majority-family workaround (a mix declared as the family most files belong
  to): REJECTED by the product owner, because it misrepresents the payload. It,
  the list extra, and the family-choice dialog are removed.

**Contract.** The person chooses once, in the media picker. That choice (the
master selection) is kept as chosen, by the stable identity of each item, and is
never changed by sharing.
- No media: the message alone, system share. One image or one video: the file
  with its message, system share, clipboard untouched. Both exactly as accepted.
- Several photos only, or several videos only: ONE homogeneous batch of exactly
  those files in the order chosen, declared as the type its files proved (the
  common type, or the wildcard of their one family), with NO message in the
  request. The complete details are copied to the clipboard ONCE before the sheet
  opens, and the dialog says so beforehand. Receiver captions are not relied on:
  a scalar message is repeated on every image by WhatsApp, and without one no
  caption arrives, so the deterministic behavior is the clipboard.
- Photos and videos chosen together: derived internally into the photos and the
  videos (each in its relative order), shared photos first, then videos, in two
  steps, with no question and no second media selection. Nothing mixed is ever
  handed to a receiver in one batch and nothing is relabelled. The dialog shows
  one informational line beforehand ("Photos and videos will be shared in two
  steps to ensure all selected media are sent."). Share launches the photo step;
  the dialog stays open and says "Photos shared. Videos are ready to share.";
  the same button, now Continue, launches the video step when the person is back.
  There is no timer and no second sheet while the first receiving app may be
  open. A family of one file goes with its message like any single file; the
  details are copied once, at the first step, only if some family has several
  files, and never again for the second step.
- Failure: a step that cannot be prepared or opened launches nothing and copies
  nothing; steps already handed over are never sent again; the retry (Retry or
  Continue) sends only the remaining step. A closed sheet leaves the choice and
  the progress as they were (a closed first sheet starts the share over). Changing
  the media choice starts over.
- Double tap: the controller takes its busy lock before its first await, so one
  preparation, one copy and one external share per step, and one more for the
  continuation, however fast the taps.
- State: the owner's idle / preparing / ready-to-share-images / images launched /
  waiting for return / ready-to-share-videos / videos launched / complete are:
  `ShareFlowStatus` idle, preparing, sharing; the set of completed families
  (`MediaFamily`), never the selection; `hasPendingStep` / `pendingFamily`
  (ready to share videos, shown by the open dialog); and the share ending in
  `ShareFlowResult.shared`. Each step prepares only its own files, so the videos
  are not downloaded for the photo step and a video failure after the photos left
  is the "second step failed" case, retried alone.
- Platform: the rule above is applied where files are handed over in batches
  (Android, `ShareDelivery.familyBatches`); on iOS and the rest
  (`ShareDelivery.wholeSelection`, chosen in `ShareLive` alone) the whole choice
  and its message stay in one system share as before, until verified separately.

**Transport.** A homogeneous batch of two or more goes through the small native
Android adapter kept from before (MethodChannel
`com.example.broker_wallet/multi_media_share`): files only, as content URIs from
the narrow FileProvider over the share staging folder, one `ACTION_SEND_MULTIPLE`
with every URI also in the `ClipData`, a read grant, the proven type or the
wildcard of one family, and no message. A mix reaching it is refused. It is kept
(rather than `share_plus`) because it copies nothing again and does not clear
earlier files: `share_plus 11.1.0` empties its cache folder at the start of every
share, which would delete the first step's files while a receiving app may still
be reading them. One file and no file still use `share_plus`.

**Removed.** The majority-family type, the list text extra and its caption
helper, the all-types fallback in the native adapter, the message parameter of the
channel, the clipboard-refusal text fallback, the `ShareTransport` split, the
family-choice dialog and its states and strings, and the plan classes. A guard
now fails if majority logic, timers sequencing a share, or a relabelled mix
returns.

**Security.** Private media stays: authenticated retrieval, local prepared file in
the cache, content URI with a temporary read grant, the share sheet. No signed
URL, key, media id or Worker endpoint reaches native code, a message or the
clipboard, which holds only the accepted human-readable details. No backend,
Supabase, RLS, Worker or upload change.

**Known limits, stated plainly.**
- The native adapter has not yet run a homogeneous batch on the device (it ran
  only with a mix); whether WhatsApp takes a files-only batch of photos or of
  videos through it is NOT verified. Images-only files-only through
  `share_plus` did arrive.
- Two steps need two taps; the second is the person's, never automatic.
- If the clipboard ever refuses (not seen on Android) the batch has no details
  anywhere and the dialog stops promising a copy.
- Owner media, which uses the same shared media path, gets the same behavior;
  quotation PDF sharing and the Offer text are untouched.

Tests (source only, not run): `share_media_batches_test.dart` (master selection,
derived batches, fixed order, no majority), `share_payload_test.dart` (0 / 1 /
a family / a mix refused / whole selection), `share_android_sink_test.dart`
(routing, exact channel arguments, no message), `share_flow_controller_test.dart`
(single image and video, three photos, three videos, the mixed master selection
step by step, no timer, retry of the second step only, failures before and after
the first launch, change of choice, double taps, whole selection, clipboard once),
`share_options_dialog_test.dart` (the two-step note, the open dialog and
Continue, a failed second step, a double tap held at a download, Cancel, offline,
a file that is gone, the notes), and `share_source_guards_test.dart` (no majority
logic, no timer, no relabelled mix, no widget policy, master selection by stable
identity, clipboard private, Kotlin pinned). Format, ARB JSON and
`git diff --check` pass. Flutter tests, analyzer and the Android build were NOT
RUN; device NOT VERIFIED. No commit, no push.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`, then a
full Android rebuild and install (Kotlin and the manifest changed).

NEXT — on the Samsung with WhatsApp: 1 image, 1 video (unchanged); 3 images and 3
videos (does the batch arrive, paste the details once); photos + videos: Share,
confirm the photos arrive and the dialog stays with "Photos shared. Videos are
ready to share.", press Continue, confirm the videos arrive. Report any batch that
does not arrive; that evidence decides the next step.

### Share final reliable media flow — source-guard realignment (2026-10-04)

Owner run of `flutter test test/share test/offers/offer_video_poster_test.dart`:
417 passed, 3 failed, all three in `test/share/share_source_guards_test.dart`. Each
was judged against the final architecture; none was a production defect, and no
production code changed.

| Failure | Verdict | Cause | Realignment |
|---|---|---|---|
| Family-comparison count | Guard wrong | The regex had been corrupted by an edit script (a backspace character where `\b` was meant), so it counted zero matches. | The homogeneous-batch invariant is now asserted where it is enforced: the one code line that reads a file's family is the check refusing a mix, placed after the non-batch cases and before the only way to a media batch; a refused mix carries no message; `isLaunchable` excludes it; the flow ends the step as a failure before the busy check, the copy and the launch; in Kotlin `commonMimeType` requires one family and the intent is built (so a mix refused) before the sheet starts. The native defensive check already existed. |
| `Handler(` in Kotlin | Guard too broad | It matched `setMethodCallHandler(` and `MethodChannel.MethodCallHandler`, which wait for nothing. | The guard refuses real timing APIs only (`Future.delayed`, `Timer(`/`Timer.periodic`, `CountDownTimer`, `postDelayed`, `postAtTime`, `sendMessageDelayed`, `scheduleAtFixedRate`, `Thread.sleep`, `sleep(`, `delay(`), with a self-check that these are caught and that plain handlers are not. |
| Localization keys | Guard stale | A hand-kept key list expected `share` as a literal, which now appears only as one branch of a conditional. | The keys are now read from the source: every quoted key inside each `translate(` call (balanced parentheses, so either branch of a conditional counts), the note keys, and the keys held in values, read from `ShareSection`, `ShareFailureKind.messageKey`, `titleKey` and `sectionTitleKey`. Each must exist, non-empty, in both ARBs with matching placeholders. A guard lists the only four value-held arguments, so a new one cannot reach the screen unchecked. |

Also: the keys added for Share must each be named by code that shows them (no
dead strings), and no source may declare a batch as all types. Obsolete
assumptions were dropped (the expectations on `shareMediaPhotoN` and
`shareMediaVideoN`). Retired-architecture guards (no majority type, no choice
dialog, no `ShareTransport`/plan classes, no timer, no relabelled mix) stay as
"must not return" checks.

Dead strings removed: `shareMediaPhotoN` and `shareMediaVideoN` from both ARBs.
The earlier dialog was their only user and nothing references them. No string was
added. Other unreferenced `share*` keys in the ARBs predate this work and were not
touched.

Verification (source only): `dart format` clean on the guard file, Dart parse, ARB
JSON valid, `git diff --check` clean, and the rewritten guards were emulated
against the real sources and ARBs with the same logic. Flutter tests, analyzer
and builds were NOT RUN by the agent. No commit, no push.

NOW — `flutter test test/share test/offers/offer_video_poster_test.dart`.

### Share UI / loading polish — one loading indicator, notes at the reading edge (2026-10-04)

Small polish on the accepted final media flow. The Share architecture, the
picker, the master selection, the batching, the clipboard contract, the native
Android transport, FileProvider, MIME policy, the Offer text, the posters, the
backend and the quotation share are untouched.

**Notes alignment (Arabic and English).**
- Root cause: each Media row is a `Column` with the default centered cross axis.
  A note narrower than the row shrank to its words and sat centered ("Photos
  shared. Videos are ready to share."), while the long details note filled the row
  and so began at the reading edge. Nothing in the text itself was centered.
- Fix, in `_buildNote` only: each note is a full-width `SizedBox` with
  `TextAlign.start`. The one `Directionality` then decides the edge: left in
  English, right in Arabic. No `TextAlign.right/left/center` anywhere in the dialog.
- Arabic details note, now exactly: `عند مشاركة عدة صور أو مقاطع فيديو، يتم نسخ التفاصيل. الصقها في المحادثة مرة واحدة بعد إرسال الوسائط.`
  English (already natural, unchanged): "When you share several photos or videos,
  the details are copied. Paste them into the chat once, after the media." The
  status line and the accepted Offer message text are unchanged.

**Loading: what happens between the tap and the sheet (traced, not assumed).**
tap → one busy lock (before the first await) → status `preparing` → staging folder
lookup and stale sweep → per file: held-on-phone lookup (path, then the cache by
stable key) else one download → type proven from the file's own header → copy
(cache hit) or move (download) into the share's folder → payload planned → status
`sharing` → clipboard once → one native call → status `idle`.
- Duplicate work found: NO. No file is looked up, downloaded, typed, copied or
  staged twice, inside a step or across the two steps; Continue prepares only the
  pending family and never touches the first folder. The only repeated check is
  `exists`/`length` in the fetcher and again in the preparer, kept on purpose as
  validation (microseconds). A cache hit is copied once because the FileProvider
  serves only the share folder, which is not changed here.
- What made the first loading feel poor was the presentation, not hidden work:
  (1) the button showed a spinner AND "Preparing files…", (2) a separate
  "x of y files prepared" line appeared under the media and moved the rows below
  it, rebuilding the whole dialog for each file, (3) the moment the sheet was
  launching or open the button switched again to a spinner with "Sharing…" (for
  `share_plus` that lasts as long as the sheet is open, behind it), and (4) the
  spinner was white on the button's grey disabled colour.
  Videos are not held on the phone, so a Continue for them is a real download,
  which is why the second wait is the one that is understandable.

**Correction.** One presentation for every state, driven only by
`ShareFlowController.status` (the one source of truth):
- The label is always Share (or Continue). The one loading indicator takes the
  place of the icon, the same 18 px box, and only while the status is
  `preparing`. Nothing changes width or colour: while busy the button keeps its
  primary colour but cannot be pressed. A screen reader is told "Preparing
  files…" through the spinner's semantics.
- Removed: the "Preparing files…"/"Sharing…" labels, the count line, its string
  `sharePreparingCount` (both ARBs), and the per-file notifications
  (`preparedFiles`, `filesToPrepare`, the controller's `onProgress`). The dialog is
  told once per phase: preparing, sharing, idle. A share with nothing to prepare
  (a message alone) goes from `preparing` to `sharing` in the same turn, so no frame
  ever draws a spinner for it. Nothing is timed: no `Future.delayed`, no `Timer`,
  no minimum loading time.
- Lifecycle: nothing is added. The native batch call returns as soon as the
  chooser starts, and `share_plus` returns when the chooser closes (before the
  app resumes), so the button is back to Share/Continue, enabled, whenever the
  person returns; no spinner is left behind.

| State | Button |
|---|---|
| Idle, first | Share, enabled |
| Preparing a step | Share (Continue for a later step), locked, one spinner for the icon |
| Sheet launching / open | same label, locked, no spinner |
| First mixed step done | Continue, enabled, "Photos shared. Videos are ready to share." |
| Preparing the rest | Continue, locked, one spinner |
| Failure | back to Share/Continue, enabled, the reason and Retry |

**Not changed, stated plainly.** Downloads are still one after another (kept: an
all-or-nothing, cancellable, ordered preparation). A cache hit is still copied
once into the share's folder. Nothing is downloaded ahead of the tap. Whether a
batch is quicker on the phone is for the owner's device to say.

Tests (source): dialog — one spinner for each preparation of a mixed share, none
while the sheet is open or after, same button size throughout, a double tap sends
once, no spinner after a failure or a closed sheet, the locked button keeps its
colour, and in English and Arabic the status line and the details note begin at
the same edge (checked on the laid-out text, with a status line shorter than its
row); controller — what is held on the phone is looked up once and never
downloaded, Continue looks up only the pending family and leaves the first folder
as it was, a download is moved (no partial or second copy), one notification per
phase, a message alone never reaches a visible `preparing`; guards — one
`CircularProgressIndicator`, gated on `isPreparing`, no `'sharing'` state, no
progress plumbing, `TextAlign.start` and full width for notes, the exact Arabic
string, and the timing guard over the dialog and the share folder.

Verification: formatter clean on every touched file, ARB JSON valid, `git diff
--check` clean. The share logic and the source guards were executed in the plain
Dart VM with stand-ins for Flutter (controller 85, preparer 25, payload 14,
sources 63, guards 64 passed); that is not `flutter test`. The dialog widget tests
were NOT run. Flutter tests, analyzer and the Android build were NOT RUN; device
NOT VERIFIED. No commit, no push.

NOW — `flutter test test/share`.

## HOME FILTER CHIPS — SUPABASE READINESS + COMPACT CHIPS — SOURCE COMPLETE, NOT RUN (2026-10-04)

Branch `share-media-selection-readiness` at `0a6f7e3` (the Share checkpoint is committed there; the seven generated
plugin registrant files are Flutter drift and were left alone). **Not committed. Not pushed.** Scope: the Home filter
chips and the filtered list only. No backend, schema, RLS, Worker, Auth, navigation, Search, Favorites, Share, Home
grid or Home header change.

### The blocker, verified in current source

- `HomeViewModel.toggleFilter` returned at once when `SupabaseConfig.useSupabaseAuth` was true ("Home-domain data is
  still backed by Firebase"), so in the default (Supabase) build a chip tap did nothing. The comment was migration-era:
  all six entity services already send their reads to `SupabaseCoreEntitiesService` in Supabase mode.
- Removing that line alone would not have been enough. The old path listened to the six service streams independently,
  from empty lists, and cleared the loading flag on the FIRST stream to answer: a filter showed a part of the answer and
  then changed as the other streams arrived. The listeners had no `onError`, so a failed first read of a Supabase stream
  was an unhandled async error and, if every read failed, a spinner that never ended. Six live subscriptions were opened
  per tap.
- Also found: sign-out left the chip selected; a Broker/Office/Watchman with no creation time was given
  `DateTime.now()` and so counted as newly added; two unused getters (`isRecentlyAdded`, `isThisWeek`) defined "recent"
  with other boundaries than the filter; prices went through `double.tryParse`, so "1,500,000" was no price and a
  negative end could still rank; a pull to refresh dropped the chosen filter; `FilteredItemsView` had no failure state
  and threw `UnimplementedError` for a Quotation.

### Architecture now (`lib/src/viewmodels/home_filter_*.dart`)

- Tap → `HomeViewModel.toggleFilter` → `HomeFilterController.toggle` (chip chosen at once, one loading state, no backend
  or mode switch) → `SnapshotHomeFilterDataSource.load(types)` → `HomeFilterRules.apply` (pure) → `items` →
  `FilteredItemsView`.
- The data source is handed the view model's own `getUserRequests / Offers / Brokers / Owners / Offices / Watchmen`, so
  the services choose the backend and, in Supabase mode, read as the signed-in user with RLS as the boundary. It takes
  the FIRST answer of each stream (one snapshot, nothing stays subscribed, no polling) and waits for all of them
  (`Future.wait(eagerError: true)`): the answer is whole or it is a failure. Recently Added and This Week read the six
  kinds; Less Price reads only Offers and Requests. Quotations are never read, the rules drop one if handed in, and the
  list has no unsupported-tile crash.
- Rules. Recently Added = created in the last 12 hours, This Week = the last 7 x 24 hours: elapsed time before "now",
  not calendar days or weeks, strictly after the window start (exactly on it is out), compared as instants (UTC or local
  makes no difference, no UAE offset). A record with no creation time of its own (`UnifiedItemModel.hasCreatedAt`
  false) is never recent. Both list by kind in Home's order (Requested, Offers, Brokers, Owners, Offices, Watchmen),
  newest first inside a kind, then id. Less Price = the 6 lowest average prices of Offers and Requests (average of min
  and max, or the one given; a finite number above zero; thousands separators read like the write path), cheapest
  first, ties newest first, then kind, then id. Same input, same list, in any input order.
- Async. Every read carries a generation; choosing another chip, clearing, refreshing, a data change, sign-out or
  dispose makes an earlier read stale and a late one changes nothing. A read that never answers ends after 30 s as a
  connection problem. A failure shows one localized sentence from strings the app already has (`authNetworkFailed`,
  `userSessionExpired`, `errorOccurred`, Search's classifier) and Try Again; never a spinner without end, an empty list,
  a raw error or a Firebase fallback.
- Pull to refresh (`HomeView`) calls `refreshCounts(keepFilter: true)`: the chosen filter stays chosen and is read again
  with the counts, what is on screen stays until the new answer arrives, a failed refresh is shown. The filtered list is
  always scrollable so a short list can be pulled. Other callers (`app_routes`: tapping Home again, switching tabs) keep
  the old default and drop the filter, as before. Leaving the Home tab still clears it.
- A create, edit or delete of the user's own records (the existing `CoreEntityMutationNotifier` subscription the view
  model already holds) re-reads a chosen filter quietly; if that read fails the answer on screen is kept. No new
  subscription, no timer.
- The canonical counts and their cache are never touched by a filter. Single choice is unchanged: one chip at a time,
  tapping the chosen chip clears it.
- Legacy Firebase build (`USE_SUPABASE_AUTH=false`): the same services answer, so a filter is now one snapshot per tap or
  refresh instead of a live combiner. The old combiner is gone.

### Chip visual contract

(Superseded on 2026-10-05, see "Update 2026-10-05" at the end of this section: Home now draws its own chips, with the
same sizes, so that choosing a chip does not make the row jump.)

Home reuses Search's accepted chip row (`FilterChips`, through `HomeFilterChips` with the same API), so Home cannot drift
from it: visible height `AppControlSizes.compactChipHeight` 36, padding 16 x 8, border 1, 14 sp label on a 1.2 line
box, check 16 with a 6 gap, pill (`chipRadius`), a 48 dp touch target around each chip, `chipSpacing` 10 between chips
as `EdgeInsetsDirectional` (mirrors in Arabic, the row starts at the reading edge), theme colours (light and dark).
The owner's suggested numbers (12 x 7, 13 sp, 14 check, 8 gap) were not used: the accepted Search contract outranks them,
and its 36 dp height is inside the suggested 34-36 range. The old Home chip: padding 16 x 10, a 14 sp label with the
font's own line box (about 38 dp for Latin by derivation, taller in Arabic; not measured), radius 20,
`EdgeInsets.only(right: 12)` (not direction-aware), deprecated `.red/.green/.blue`. Favorites' chips still have that old
style and were not touched. Consequence for the owner to judge: the row now reserves the 48 dp touch target like Search,
and the two 24 dp spacers in `home_view.dart` were left as they are, so in English the chip block is about 10 dp taller
than before by derivation (Arabic: not measured); dropping both spacers to 18 would restore the old visible gaps.

### Files

Edited: `lib/src/viewmodels/home_viewmodel.dart` (the combiner and the Supabase early return are gone; the controller is
wired in), `lib/src/views/Widgets/home_filter_chips.dart`, `lib/src/views/Widgets/filtered_items_view.dart` (failure
state, no `UnimplementedError`, always-scrollable list), `lib/src/views/Screens/home_view.dart` (pull keeps the filter),
`lib/src/data/models/unified_item_model.dart` (`hasCreatedAt`, price parsing, the two dead getters removed).
New: `home_filter_rules.dart`, `home_filter_controller.dart`, `home_filter_data_source.dart`, `home_filter_errors.dart`
(`lib/src/viewmodels/`) and `test/home/` (six files). No ARB change: every string already existed in both languages.

### Verification

`test/home` holds 149 cases: rules 36, model 11, snapshot source 9, controller 45, chips widgets 23, failure sorting and
words 6, source guards 19. The 120 that need no Flutter (rules, model, source, controller, guards) were EXECUTED by the
agent under the plain Dart VM against the real production sources, with small stand-ins for `flutter_test`,
`package:flutter/foundation.dart` and `cloud_firestore` and the real `matcher` package. That is **not** `flutter test`.
Eight deliberate regressions (no generation guard, a quiet failure replacing the list, clear not invalidating reads, an
inclusive window start, an unknown time counted as recent, Less Price admitting unpriced kinds, reads one after another,
a Broker reported as having a time) were each caught by those tests; the files were restored byte for byte. The 29 cases
that need Flutter (chips widgets 23, failure sorting and words 6) were reviewed against the real `FilterChips` and
NOT run. `dart format` clean on every new file and unchanged on the edited ones (`filtered_items_view.dart` keeps its one
pre-existing deviation), ARB files valid and untouched, `git diff --check` clean. Flutter tests, analyzer and device:
**NOT RUN**. Status: **HOME FILTERS = SOURCE COMPLETE; owner test and device acceptance pending.**

### Not changed, found on the way (backlog)

- Less Price still ranks Offers and Requests together, so rent amounts and sale prices share one list and the six lowest
  will mostly be rent. Kept as the accepted behaviour; scoping it by rent/sell is a product decision.
- "This Week" means the last 7 days, not the calendar week; Recently Added is 12 hours. Kept.
- The Requests list's Sale card filters on `'sale'` while requests are stored as `'sell'` (`requests_list_view.dart`,
  `list_requests_viewmodel.dart`, `core_entity_payload_builder.dart`): it appears to match nothing. Not touched, not
  checked on a device.
- `SupabaseCoreEntitiesService._date` falls back to `DateTime.now()` for a missing or unparseable timestamp. All six
  tables have `created_at`/`updated_at` `NOT NULL`, so it should be unreachable; the shared mapping was left alone.
- Each `getUser...()` call of five entity services builds a new `SupabaseCoreEntitiesService`; harmless, pre-existing.

NOW — `flutter test test/home`.

NEXT — only if that passes, the scoped analyzer: `flutter analyze lib/src/viewmodels lib/src/views/Widgets/home_filter_chips.dart lib/src/views/Widgets/filtered_items_view.dart lib/src/views/Screens/home_view.dart lib/src/data/models/unified_item_model.dart test/home`;
then a device pass (English and Arabic, light and dark): tap each chip with the app signed in on Supabase (the chip is
chosen at once, one spinner, then the whole list or "No Filtered Items"); switch chips quickly; tap the chosen chip to
clear and see the normal counts; pull to refresh with a filter chosen (it stays); open a filtered record, delete it,
come back (it is gone); airplane mode, tap a chip (connection message and Try Again); log out and in (no chip chosen);
compare the Home chips with Search's (same height, spacing, mirrored in Arabic).

### Update 2026-10-05 — chips that no longer jump, and two UI-only chips (supersedes "Chip visual contract" above)

The owner reported that the filter chips do not look smooth: tapping to choose or clear one makes the others look
affected. Source only; not seen on a device. Branch, scope and the "not committed, not pushed" state are unchanged.

**What the chip row did in the frame a chip was tapped (read from the code and the SDK, not observed).** Search's
`FilterChips`, which Home reused, adds the check mark and its 6 dp gap to the chip's `Row` in a single frame, so a chosen
chip is 22 dp wider at once and every chip after it jumps sideways; it also changes the label from weight 500 to 600,
which on a device with static fonts changes the label's width (and, with an animating weight, can do it frame after
frame). Moving the choice from one chip to another does both, so the chips between them jump in opposite directions. A
wrapper such as `AnimatedSize` does not cure the second part: it follows a child whose size changes on consecutive
frames exactly, which is a jump again. With five chips the row scrolls, so a change of its width also moves its scroll
extent.

**Fix (Home only; Search's file is untouched).** `HomeFilterChips` now draws its own chips instead of forwarding to
`FilterChips`, with the same numbers (36 dp height, 48 dp touch target, padding 16 x 8, border 1, 14 sp label, pill,
10 dp directional gap, same shadows) read from `AppControlSizes` and Search's public sizes, and two differences:
- The room for the check mark is `checkRoom` (22 dp) times how far a 200 ms `easeInOut` animation has got
  (`TweenAnimationBuilder` + `Align(widthFactor)` + `ClipRect` + fade), so a chip's width, and with it where its
  neighbours are, glides in both directions. It starts from where the chip is when it is tapped again mid-flight, so
  reversing does not jump. Settled and not chosen, the check is not in the tree and takes no room.
- The label keeps weight 500 in both states, so its width never changes. (Search's selected label is 600; on a device
  Home's chosen chip is therefore a few dp narrower than Search's.) The colours, shadow and label colour animate with the
  same duration and curve; the label and check use the theme's `onPrimary` (white in both themes), the shadow
  `ColorScheme.shadow`.
- Moving the choice from chip A to chip B: A gives up exactly what B takes at every frame, so the chips outside the two
  never move at all; only those between them glide.

**Two new chips, UI only (owner request): Highest Price, Recently Updated** (appended after This Week; the row now has five
and scrolls on a phone). `HomeFilterKind` gained `highestPrice` and `recentlyUpdated` with `isImplemented: false`. Choosing
one selects the chip and shows a localized "Coming soon / This filter will be available soon." state in the list area; it
reads nothing, shows no spinner, no error and no "No Filtered Items" (which would claim a filter ran). Tapping it again
clears it; switching to another chip works as before and a read still in flight for the previous chip is dropped. A pull,
a data change and Retry do nothing for it. The rules refuse to answer for such a chip (`UnsupportedError`), so nothing can
mistake it for an empty result. Four ARB keys were added to both languages: `highestPrice` ("Highest Price" / "أعلى سعر"),
`recentlyUpdated` ("Recently Updated" / "محدّث حديثاً"), `homeFilterComingSoonTitle` and `homeFilterComingSoonDesc`. The
Arabic wording is the agent's and should be read by the owner. Building either filter later means: set `isImplemented`
true, give it a case in `HomeFilterRules.typesFor` and `apply`, and add tests; Recently Updated would use `updated_at`
(set by the `bump_sync_version` trigger on all six tables, no backend change), Highest Price the same price fields as Less
Price.

**Tests.** `test/home` now holds 181 cases. The 135 that need no Flutter (rules 40, model 11, snapshot source 9, controller
54, source guards 21) were executed by the agent under a plain Dart VM with the stand-ins described above, and twelve
deliberate regressions (the earlier eight plus: a chip with no filter reading anyway, such a chip not staling an earlier
read, a pull reading it, the rules answering with an empty list for it) were each caught. The 46 that need Flutter (chips
widgets 40, failure sorting and words 6) were NOT run (the chips file's pure source assertions were checked against the real
file by a script): the chip tests prove, with frames pumped 60 ms apart, that nothing
moves in the frame a chip is chosen, that the chips after it advance by exactly the growth of its check room, that a
chosen-to-chosen move leaves the chips outside the two untouched at every frame, and that a tap half way reverses from
where it is, in English and Arabic. `dart format`: new files formatted, `home_filter_chips.dart` clean, ARB files valid
JSON with CRLF kept, `git diff --check` clean.

**Not done, for the owner to decide.** Search's chips have the same jump; Home's row could be shared with Search
(one-line change there) once the owner has seen it on a device. A chip that is partly off-screen is not scrolled into view
when tapped. The area below the chips still swaps (grid, spinner, list) without a fade.

NOW — `flutter test test/home`.

NEXT — only if that passes, the scoped analyzer (as above), then the device
pass: tap each of the five chips in English and Arabic and watch that the chips beside the one you tap glide rather than
jump, including moving the choice between chips and tapping twice quickly; scroll the row and choose Highest Price and
Recently Updated (the "Coming soon" state, then clear it).

## FAVORITES SCREEN — APP UI PATTERN (UI ONLY) — SOURCE COMPLETE, NOT RUN (2026-10-05)

Owner request: update the Favorites screen to match the app's pattern — the filter chips and their size, the screen itself,
the top bar, everything Search has — "ui updates nothing else". Source only; not seen on a device. The work is on the local
branch `home-filter-supabase-readiness` (HEAD `ffe3679`), uncommitted and not pushed.

### What Favorites had, against Search (read from the code)

- A gradient hero card (28 dp radius, 22 dp padding) with a 56 dp rounded-square avatar, the greeting, a title, the refresh
  hint and two info chips, where Search and Home have a plain row: a round 48 dp avatar, the greeting with one line under it,
  the bell.
- A gradient page and, behind the chips, a rounded 24 dp panel with a shadow; Search's chips float on the page's own colour.
- Its own chips: 20 dp radius and 10 dp vertical padding (roughly 40 dp tall against Search's 36), a 12 dp gap fixed to the
  physical right (it did not mirror in Arabic), no 48 dp touch target, a check mark that took its room in one frame.
- A grid of 18 dp by 16 dp gaps at a fixed 0.8 shape (Search: 12 dp gaps, 3 : 4, never shorter than the card's text needs).
  The card is laid out like Search's result card (three one-line fields in a fixed band), so a fixed shape is likely to clip
  the third field on a narrow phone or at a large font (derived from the layout, not seen).
- The view model's raw error text on screen when loading failed, and no way to clear a filter that hides everything.

### What it is now (`lib/src/views/Screens/home/favorites/`)

- **Header** — Search's: the round 48 dp avatar (opens Edit Profile), the greeting that cross-fades when the name changes,
  "overview" under it, the bell. It listens to the profile itself, so a profile update does not rebuild the list.
- **Filters** — a pinned, flat bar on the page's own colour (no panel, no shadow, no tint), Search's `SliverAppBar` recipe,
  tall enough for the chips at large fonts (`FilterChips.rowHeightOf`). `FavoriteFilterChips` draws nothing of its own any
  more: it forwards to Home's `HomeFilterChips` (Search's sizes and colours, 36 dp chips in a 48 dp touch target, spacing
  that mirrors in Arabic, and the glide when a chip is chosen or cleared), so the three screens cannot drift apart.
- **Status** — what the hero card's chips said is kept, as pills in the style of Search's result count: how many are saved,
  how many the chosen filter shows and, while there is something to sync, syncing or synced. The pills wrap onto a second
  line instead of overflowing (`FavoritesStatusRow`, public so it can be tested). The refresh hint moved from the top card to
  the foot of the list, with 56 dp below it (as the loading text has) so the docked add button, which rises about 28 dp into
  the page, does not cover it.
- **Grid** — two columns, 12 dp gaps, padding 16 / 8 / 16 / 20 and a card 3 : 4, never shorter than
  `SearchResultCard.minHeightForText` (Search's own formula). The loading skeleton uses the same grid.
- **States** — loading: the skeleton and the two lines as before; no favorites: as before; a filter that hides everything:
  the same empty state plus Search's "Clear Filter" button, which calls the existing `toggleFilter`; a failure with nothing
  cached: Search's error screen (error icon, the localized title, a "Retry loading" button), and the technical error is no longer shown.
- **Scroll** — `SafeArea`, pull to refresh in the primary colour, bouncing always-scrollable physics and a 1200 px cache as
  before (now through `scrollCacheExtent`, as Search does). The grid's behaviour (image prefetching, one key per favorite, no
  keep-alive per card) is unchanged.

Nothing but the UI changed: `FavoritesViewModel`, `FavoriteCard`, routing and every ARB string are as they were (all the keys
already existed in both languages, `clearFilter` among them).

### Files

Edited: `favorites_view.dart` (layout and states), `favorites_filter_chips.dart` (now a forwarder). New:
`test/favorites/favorites_screen_ui_test.dart` (22 cases).

### Verification

The 22 cases are 12 source guards and 10 widget tests. The widget tests (the chips are Home's chips with the same rectangles
in English and Arabic; the row is as tall as Search's at normal and at double text size; a tap reports the chip's own index;
the status row in English and Arabic, syncing and synced, in Search's pill style in light and dark, and wrapping at 320 dp
with 1.6 times text) need Flutter and were NOT run. The 12 source guards were EXECUTED by the agent under a plain Dart VM
against the real sources (the stand-ins described above; **not** `flutter test`): the grid's columns, gaps, padding and
minimum height against Search's own constants, the header and the flat pinned bar against Search's, no raw error, Clear
Filter, every screen string present in both ARB files, the foot of the list clearing the docked add button, and the chips
being the shared ones. Twenty deliberate regressions (grid gap or padding drifting from Search, the text minimum height
dropped, a fixed shape again, the skeleton and cards no longer sharing one grid, a 56 dp avatar, the gradient back, a
shadow under the bar, the bar unpinned or tinted, pull to refresh gone, the raw error shown, Clear Filter gone, a screen
string or a translation missing, the chips drawing their own box or no longer forwarding to Home, the cards' grid
keep-alive changed, the refresh hint no longer clearing the add button) were each caught; they ran on scratch copies, so
no production file was touched. One regression got past the first version of a guard (the keep-alive flag also appears in the
skeleton); the guard was narrowed to the cards' class and the check re-run. `dart format`: the new test and the chips file
clean, `favorites_view.dart` formatted, `git diff --check` clean. Flutter tests, analyzer and device: **NOT RUN**. Status:
**FAVORITES UI = SOURCE COMPLETE; owner test and device acceptance pending.**

### Not changed, found on the way (backlog)

- Home draws its page on `colorScheme.surface` (`#F6F6F8` light, `#22292F` dark) where Search, Profile and now Favorites use
  the scaffold colour (`#FAFAFA`, `#141918`). Home's unselected chips (also filled with `surface`) therefore blend into
  their page more than Search's do. The Home tab was not part of this task and was left alone; changing it is one line.
- The avatar, greeting and bell header now exists as three near-copies (Home, Search, Favorites). One shared widget would
  remove the drift risk; not done, because it touches the two screens this task did not name.
- Search's own chips still jump when one is chosen (see the Home update above); Favorites and Home no longer do.
- `CurrentUserAvatar.borderRadius` has no caller left (Favorites' rounded square was its only user). Left in place.
- Favorites' view model still holds raw, English error strings. They are no longer shown, so nothing user-visible is wrong,
  but a localized message would belong in the view model, not the view.
- A `FavoriteCard` whose layout changes without `SearchResultCard` changing with it would make the shared minimum height
  wrong; there is no test that renders both cards and compares them.

NOW — `flutter test test/favorites/favorites_screen_ui_test.dart`.

NEXT — only if that passes, the scoped analyzer: `flutter analyze lib/src/views/Screens/home/favorites test/favorites/favorites_screen_ui_test.dart`;
then a device pass, English and Arabic, light and dark, with Search open beside it: the header (avatar, greeting, bell) in
the same place and size; the chips the same height and gap, pinned under the header while the cards scroll beneath, and
gliding when one is chosen or cleared; the two status pills (and the sync pill) wrapping, not overflowing, on a narrow
phone and with a large system font; every card's three fields fully visible; the five states: loading, no favorites, a
filter that hides everything (and Clear Filter), a failure with nothing cached (airplane mode on a fresh install, then
"Retry loading"), and the list with a pull to refresh.

### Favorites UI — owner's test runs and the corrections (2026-10-05)

Run 1: the file failed to compile ("Member not found: 'rtl'" at `TextDirection.rtl`). Cause: the test imported
`package:intl/intl.dart` whole, and `intl` has a `TextDirection` class of its own (with `LTR` / `RTL`) that hid
Flutter's. Fix: `import 'package:intl/intl.dart' show NumberFormat;`. The production files compiled in that run (the
compiler type-checks the whole import graph), so only the test was wrong. The mistake was the agent's: `dart format`
and the plain-Dart replay of the source guards do not resolve names, so neither could have caught it.

Run 2: 20 of 22 cases passed (the 12 source guards and 8 of the 10 widget tests). The two that failed, "says how many are
saved and how many are shown" in English and in Arabic, failed on their last line only: they compared where the two
pills' labels sit, but in the test font (every letter a full em wide, plus the theme's letter spacing for Latin text)
the two pills need about 426 dp, so at the 412 dp test width the `Wrap` put them on two lines and both labels started at
the same edge (the same left edge in English, the same right edge in Arabic). The screen was right: the pills are meant to
wrap rather than overflow, and in a real font they are far narrower (an estimate, not measured). The test's width was
wrong. Fix: that test now runs on a 700 dp surface, first asserts that the two labels share a line, then asserts the
reading order (left to right in English, right to left in Arabic). The pill widths were recomputed from the ARB strings
and the test font's metrics and reproduce the owner's failure output to a tenth of a dp (English first pill 215.7 dp,
Arabic 246.0 dp); at 700 dp the two fit with more than 240 dp to spare. Only the test changed.

NOW — `flutter test test/favorites/favorites_screen_ui_test.dart` again. NEXT is unchanged (the scoped analyzer, then the
device pass listed above).

### Single active Broker Wallet session — source readiness (2026-10-05)

Branch `single-active-device-readiness`, based on `9040cc7142ff53aa2f409114330384da153f2160`.
Source is **UNVERIFIED**. No commit or push. Migration
`20261005175500_single_active_app_session.sql` is **NOT APPLIED**. Worker source
is changed but **NOT DEPLOYED**. Flutter tests, analyzer, build, Worker tests,
database validation, and device testing were **NOT RUN** by the agent under the
owner execution policy. This is not a production PASS or a runtime checkpoint.

The migration gives each `auth.users.id` one `user_active_sessions` row and a
permanent, user-cascading `app_session_claims` record for each Supabase
`session_id`. A fresh JWT session can claim once; a currently active claimant
can retry idempotently; a displaced claimant cannot reclaim. Claims lock the
canonical `auth.users` row, so concurrent new claims serialize and the last
successful new claim wins. The check and claim verify `auth.sessions` membership.
No user/session ID, token, password, or service credential is accepted from
Flutter as authority. Both session tables are RLS-enabled. The active row has
an ownership-only SELECT policy for Realtime detection; neither table grants
client DML. User deletion cascades both tables.

A restrictive authenticated session policy is added to each currently
client-accessible public app-data table (profiles, subscription/quota reads,
core entities and child/area rows, quotation rows, private-media metadata and
links, favorites, feedback, notifications, app versions, and the other listed
tables in the migration). Existing permissive business policies remain.
`save_quotation`, the sole client-callable SECURITY DEFINER business RPC,
is wrapped in the same gate; media-confirm RPCs remain service-role only.
`account_deletion_jobs`, webhook/audit server tables, the internal claim ledger,
and the active-state observation row are explicit exceptions. The Worker checks
the caller's JWT through `is_current_app_session` after Auth verification on
every media route and on account deletion, returning fixed
`session_superseded` on rejection. Server-owned cron/finalizer work is unchanged.

Flutter waits for claim after normal sign-in, or validation of a restored
session, before publishing app identity to the router. Recovery remains
quarantined and never claims. A user-scoped Realtime row stream detects a
replacement; app resume validates with a five-second
throttle. A fresh sign-in claim takes precedence over an in-flight check of
the same session, so the check cannot reject the new claimant. Both converge
on one explicit `SignOutScope.local` path and a localized English/Arabic
message. Worker/RPC error reports are correlated with the request's token so
a late error from a previous account cannot log out a new one. Normal logout
releases only the current active row, then signs out locally. Existing
account-scoped cache/listener cleanup remains in the AuthViewModel's null
identity path; Toolkit PDFs are untouched.
If an offline cold start cannot check a cached session, bootstrap stays
closed to Home and shows a localized Retry action without discarding that
session. Resume retries automatically. The Worker returns a separate
`session_check_unavailable` failure for a database outage; it does not call
that outage a displacement.

The built-in Supabase single-session setting is Pro+ and is not used. Pinned
`gotrue 2.27.2` supports `SignOutScope.others`, but the source intentionally
does not invoke it: a newer login can claim between the database claim and
that Auth API call, allowing an already-displaced caller to revoke the true
winner's refresh token. Database, RPC, and Worker gates are the immediate
authority. An old access JWT can still reach the raw Auth API until `exp`;
`supabase/config.toml` records a **local** 3600-second JWT expiry and no hosted
Auth setting was changed. A shorter owner-controlled expiry, if chosen, must
respect Supabase's guidance not to go below five minutes. An entirely offline
old device cannot receive displacement until reconnect/resume; its online
backend access is denied already. Existing development sessions without an
active row must sign in once after rollout. Premium access in the future must
require both entitlement and this active-session gate.

Source validation added:
`supabase/validation/single_active_app_session_validation.sql` (rollback-only
on a disposable migrated database),
`cloudflare/workers/r2-profile-upload/test/active_session.test.mjs` and the
updated Worker fakes, and `test/auth/single_active_session_source_test.dart`.
The owner ran the original three Flutter source tests on 2026-10-05 and they
passed (`00:11 +3: All tests passed!`). That test did not import
`AuthViewModel`, so it could not compile the integration site where the editor
reported `sessionCheckUnavailableEvents` against `AuthRepository`. The
optional `AppSessionEvents` reference is now explicitly typed, and the test
imports `AuthViewModel` as a compile smoke check. This revised source has not
been rerun; Worker tests, database validation, analyzer, build, and device
testing remain unrun. The SQL script covers ownership, direct DML,
first/idempotent/replacement claims, blocked reclaim/release, RLS, publication,
and deletion cascade; a separate concurrent multi-connection database run and
real-device A→B→C exercise are still required.

NOW — owner reruns `flutter test test/auth/single_active_session_source_test.dart`.

NEXT — only after that passes, owner runs a scoped analyzer, then Worker tests,
then the disposable-database rollback validation (including concurrent
claims). Hosted migration and Worker deployment require separate explicit owner
action; only afterward run the A→B→C, recovery, logout, offline/reconnect,
private-media, and account-deletion device acceptance. Do not mark this
VERIFIED_RUNTIME before that pass.

### Single active device — hosted rollout and logout dialog (2026-10-06)

Owner-reported hosted state supersedes the earlier source-readiness paragraph:
`20261005175500_single_active_app_session.sql` was applied and registered.
Hosted read-back confirmed both session tables, all session RPCs, the gated
quotation wrapper and internal function, 32 restrictive policies, Realtime
publication membership, RLS, grants, and cascading auth-user foreign keys.
The owner observed a cached session lose app access and sign out on a device.
The Worker deployment and the full A→B→C/device acceptance remain unverified
here; no production-wide PASS is claimed.

The transient displacement toast was too fast to read. Source now holds a
one-shot notice in the app-lifetime `AuthViewModel`. A synchronous displacement
phase closes protected app state and routes to the splash gate before explicit
`SignOutScope.local`; a completion phase then allows the unauthenticated
Welcome route to render a barrier/back-protected, single-action Material
dialog in English or Arabic. No dialog is produced by validation unavailable,
ordinary logout, normal cold start, or another auth-stream failure. A genuine
displacement in a sign-in flow is owned by this dialog; an unrelated expired
session keeps its separate localized sign-in error. No database, Worker, or
hosted setting changed for this UX checkpoint. Source/widget tests were added
but not run by the agent under the owner's Flutter execution policy. This UX
remains **SOURCE READY / DEVICE UNVERIFIED**.

NOW — owner runs `flutter test test/auth/session_superseded_dialog_test.dart`
and reports the output.

NEXT — if that passes, owner runs a scoped analyzer for the changed Dart files,
then checks displacement on two real devices in English/Arabic and light/dark:
protected UI closes before local sign-out, Welcome appears, exactly one dialog
stays until OK, and the old device remains signed out. Also verify Retry,
ordinary logout, and a normal cold start show no displacement dialog.

BOTTOM NAV BAR UPDATE — SOURCE READY / RUNTIME VERIFICATION PENDING

Scope:

- The main four-tab shell now uses the proven INTLAQ Hub liquid-notch geometry
  and stable tab presentation while preserving Broker Wallet's own colors,
  PNG navigation icons, localized labels, GoRouter branch order, and center
  action behavior.
- The shell uses `extendBody: true` so the notch remains physically transparent.
- The main center FAB is aligned to the liquid notch with the same 64 px / +8 px
  geometry used by the reference implementation, while retaining Broker
  Wallet's existing green FAB styling and action bottom sheet.
- The former per-tab fade reset and nav-item scale/text animations were removed;
  branch state and Home refresh/filter behavior are unchanged.
- No backend, auth, Supabase, Worker, route destination, package, or unrelated UI
  change is part of this checkpoint.

Verification status:

- Source inspection: completed.
- Flutter tests: NOT RUN (owner-only execution policy).
- Flutter analyze: NOT RUN (owner-only execution policy).
- Real-device Light/Dark + English/Arabic/RTL verification: PENDING OWNER.

QUOTATION PDF / OFFICE LOGO POLISH — SOURCE PREPARED, NOT RUNTIME VERIFIED

Source changes prepared for owner verification:

- Downpayment PDF table headers and row values are centered in every column.
- Office Logo now shows an image preview instead of only the file name.
- A localized, opt-in "Remove logo background" control appears under the
  Office Logo picker for a newly selected image.
- Background removal runs locally on-device, keeps the picked source image
  untouched, produces a temporary transparent PNG, trims transparent margin,
  and uses the processed PNG for upload/PDF only when the option is enabled.
- Existing bound private logos use a short-lived signed URL only for preview;
  no signed URL is persisted.
- No Supabase schema/RLS/Worker/media architecture change was made.

Verification status:

- Flutter tests: NOT RUN (owner-only execution policy).
- Analyzer: NOT RUN (owner-only execution policy).
- Build/device: NOT RUN.
- Hosted backend changes: NONE.
- Commit/push: NO.

## QUOTATION SAVE PERFORMANCE — SOURCE PREPARED, NOT RUNTIME VERIFIED (2026-10-06)

The existing quotation PDF/logo polish above remains uncommitted and protected.
This checkpoint changes only the quotation editor/save path, its English/Arabic
progress strings, PDF font loading and targeted quotation tests. No backend,
Worker, migration, package, auth or other screen was changed.

Before: Save checked identity/quota, then `performSave` built the aggregate and
awaited `save_quotation`; logo upload/remove ran next; PDF source lookup,
generation and private upload/confirmation followed; a media-state read ran on
every successful database save before reporting success or incomplete media.
Newly selected logo background removal was already performed on toggle, but
turning it off deleted the result and turning it back on recomputed it.

After: Save locks immediately, keeps the button spinner, and shows a localized
blocking overlay only after 1.25 seconds. The form and back navigation remain
blocked during Save. The RPC still runs first with the same identity, id and
expected version. One PDF preparation starts after the database result and may
overlap logo transfer; PDF publication still waits for logo sync and its own
private confirmation before success. A final media-state read is now reserved
for media failure or a confirmation without a resulting version. A processed
logo remains cached for the same selected source across toggle off/on and is
reused for preview, upload and PDF; changing the selected media bytes clears
the pending upload identity. An unchanged bound logo reuses its still-valid
preview link for PDF rendering; expired links are fetched again. The original
source file is untouched.

The PDF service now loads its four font assets once per process, sharing the
in-flight load and retrying after a load error. Previously `_loadFonts` ran on
every generation despite writing to `late final` font fields, so subsequent
generations could fail on reassignment. Debug-only logs time quota preflight,
local preparation, database save, logo sync, PDF generation/publication,
conditional refresh and total; they contain no tokens, URLs or quotation data.

Targeted tests were added to `test/quotation/add_quotation_viewmodel_test.dart`
for duplicate taps before quota completes, fast and slow feedback, overlay
cleanup on conflict, processed-logo reuse, unchanged-logo upload avoidance,
signed-link reuse/expiry, one PDF generation, logo/PDF ordering and no redundant
success refresh. Existing version-conflict and media retry tests remain.
Flutter tests/analyzer/build and real-device timings are **NOT RUN** under the
owner's execution policy. Source
is **CODE PREPARED**, not `VERIFIED_RUNTIME`.

NOW — owner runs `flutter test test/quotation/add_quotation_viewmodel_test.dart`
and the scoped quotation analyzer, then reports failures and debug timing lines.
NEXT — after those pass, owner verifies create/edit, processed and unchanged
logos, PDF availability, failure retry, English/Arabic/RTL and Light/Dark on a
real device before marking this checkpoint runtime verified.

### Quotation save performance — two widget test fixture corrections (2026-10-06)

The owner ran `flutter test test/quotation/add_quotation_viewmodel_test.dart`:
33 passed, 2 failed. The editor spinner assertion found no descendant, and the
processed-logo test dereferenced a null test `BuildContext` before background
removal began. Source inspection confirms the shared Save button still renders
its `CircularProgressIndicator` when `isLoading`, the quotation editor passes
the view model loading state to it, and the processed-logo cache is retained
across toggle off/on for the selected source. The localized widget fixtures had
not preloaded their asynchronous ARB assets before pumping the app; the logo
fixture also relied on a nullable context assigned by a `Builder` that had not
built. The test file now serves and preloads the real ARBs, asserts the Save
button exists and locks while retaining the spinner assertion, and obtains the
logo context from a mounted keyed widget. The logo test still asserts one
background removal call through toggle off/on and Save, and verifies that Save
uploads the prepared file. Production source and
the 1.25-second overlay timer were not changed in this correction.

Status: TEST FIXES PREPARED; owner Flutter tests/analyzer and real-device
verification NOT RUN after these corrections. No commit, push, backend or
migration action.

NOW — owner reruns `flutter test test/quotation/add_quotation_viewmodel_test.dart`
and reports the exact result.
NEXT — after the targeted suite passes, owner runs the scoped analyzer and then
verifies create/edit, background-removal reuse, overlay timing and PDF/media
availability on a real device.

## QUOTATION SAVE — PERFORMANCE CORRECTION — SOURCE PREPARED, NOT RUNTIME VERIFIED (2026-10-06)

This supersedes the loading UX and the save ordering described in the two
"Quotation save performance" sections above. Branch `bottom-nav-bar-update`,
uncommitted. No backend, Worker, migration, package, auth or other-screen change.

Owner's Samsung result for the previous checkpoint (not accepted): Save felt
slower, a blocking centre overlay changed its text between "Uploading logo..."
and "Preparing quotation...", and the Save button showed its own spinner at the
same time. One save looked like several slow operations.

Source-backed causes:

- Two progress indicators at once: `SaveCancelButtons` spun while `isLoading`,
  and `_QuotationSaveOverlay` (shown after 1.25 s) spun as well.
- The PDF was prepared only after `save_quotation` answered, although the PDF
  reads nothing the server assigns (only form fields and the client-chosen id).
- Each save fired `CoreEntityMutationNotifier.notify()` up to three times
  (aggregate, logo confirm, PDF confirm). Every signal makes Home re-run its
  seven count queries and every open list, the quotation list and Search
  re-read, competing with the uploads.
- A picked logo was uploaded and embedded at camera resolution (up to the 10 MB
  limit); a background-removed logo was kept at up to 2048 px, which the `pdf`
  package decodes and re-deflates on the UI isolate.
- The PDF service decoded the whole localized ARB JSON on every generation.

Changes:

- Loading UX: `QuotationSaveProgress { idle, saving, longSaving }` replaces the
  stage enum. Tap locks Save at once and the button spins. After 2 seconds
  (`AddQuotationViewModel.defaultLongSaveThreshold`) one centred indicator
  replaces the button spinner (`SaveCancelButtons.showProgress` is false; Save
  stays disabled with its label). A save that ends sooner never shows it and
  it closes the moment the save ends. Text: "Saving quotation..." /
  "جارٍ حفظ عرض السعر...". The ARB keys `quotationUploadingLogo` and
  `quotationPreparing` were removed. No stage text is user-facing.
- Order: validate (`QuotationSupabaseMapper.validate`, so an invalid form starts
  no work) -> PDF preparation and `save_quotation` start together -> logo sync
  -> PDF publication -> a media-state read only if a confirmation lacked its
  version. A failed save discards the prepared PDF (its file is deleted; the
  next save waits for that renderer so it cannot delete its own file) and
  publishes nothing. Media confirms stay serialized and compare-and-swap.
- `QuotationService.batchMutations` makes one save send one refresh signal.
- Logo: `LogoOptimizationService` shrinks a picked logo to at most 768 px on
  its long edge when it is picked (never during Save); the picked file is never
  modified; a JPEG stays a JPEG, other formats become PNG with alpha; EXIF is
  not carried over. Save waits only for a copy still being made. Background
  removal still runs only on the toggle, now at the same 768 px size (it was
  2048 px). An unchanged bound logo does no upload, no confirm and, while its
  preview link is valid, no new signed-link request.
- PDF: fonts stay cached; localized strings are now cached per language; one
  PDF per save. Generation still runs on the UI isolate (unchanged).
  Publication still blocks completion: View and Share need `hasPdf`, and there is
  no durable retry for Quotation media, so a background publish could be lost.

Plain-Dart scratch measurement of the real optimizer (synthetic images, desktop
VM, not `flutter test`, not a device): 4000x3000 JPEG 4489 KB -> 768x576 92 KB
(3.7% of the pixels), the PDF embedding it 4490 KB -> 93 KB; a 3000x2000
transparent PNG 33 KB -> 768x512 8.7 KB with alpha intact; the 2048 px
transparent-style PNG a PDF had to decode (39 KB, 456 ms to build) -> 768 px
(8 KB, 31 ms). `test/quotation/logo_optimization_service_test.dart` ran under
a plain-Dart stand-in: 5/5 passed.

Tests changed (source only, NOT RUN): `add_quotation_viewmodel_test.dart`,
`quotation_service_test.dart`, `save_cancel_buttons_test.dart`, new
`logo_optimization_service_test.dart`. Flutter tests, analyzer, build and
real-device timing: NOT RUN (owner-only execution policy). Commit/push: NO.

NOW - owner runs `flutter test test/quotation/add_quotation_viewmodel_test.dart
test/quotation/quotation_service_test.dart test/quotation/logo_optimization_service_test.dart
test/forms/save_cancel_buttons_test.dart` and the scoped analyzer, and reports
exact failures.
NEXT - on a real device, with a 12 MP camera photo as the logo and with the
background toggle on and off: confirm one spinner at a time, no stage text,
the 2 s centre indicator only on a slow connection, English/Arabic/RTL and
Light/Dark, PDF opens with the logo, and read the debug lines
`Quotation save timing: ... +Nms..+Nms` (PDF preparation overlaps database save).

### Quotation save — concurrent PDF cleanup race (2026-10-06)

Owner run: `add_quotation_viewmodel_test.dart` 42 passed / 4 failed (version
conflict, deleted quotation, failure-message matrix, unexpected error), each with
`PathAccessException` deleting `quotation_vm_test_*`; the other suites passed
(logo optimizer 5/5, quotation service 17/17, save buttons 80/80).

Cause: a TEST-FIXTURE defect, not a production one. When `save_quotation` fails,
`_performSave` returns at once by design (the user hears about the failure
without waiting for the renderer) while the PDF rendered beside the RPC is still
writing `quotation_<id>.pdf`; the view-model already tracks that render
(`_pdfDiscard`) and deletes its file when it finishes, and the next save waits
for it. `_env` registered `dir.delete(recursive: true)` and `vm.dispose` as
independent teardowns that did not wait for it, so Windows refused to delete a
directory holding an open handle.

Source tightening (no change to the success path; the PDF still overlaps the
RPC): `_saveAndPublish` now owns the prepared PDF with a single `finally` that
discards it on every exit except the hand-over to `_publishPdf` (so an
unexpected error between the RPC and the publish cannot orphan it);
`_performSave` does not start a save that waited for a discarded renderer after
the view-model was disposed; temporary-file removals on dispose, cleared logo
and reload are now a tracked chain; `backgroundWorkSettled()` (visible for
testing) completes when a discarded render, a logo copy in progress and those
removals are finished; `PdfGenerationService` deletes a half-written PDF when
the write fails.

Tests (source only, NOT RUN): `_env` has one teardown that waits on
`backgroundWorkSettled()` before disposing and deleting the directory (a
renderer parked on a test's own gate has touched no file and is not waited for);
the four business tests are unchanged. New cases: no generated PDF remains
after a failed save once its renderer finishes; a retry with changed data
publishes only its own PDF; a save waiting for a discarded renderer does not
start after dispose. Earlier sleep-based waits for logo copies were replaced by
`backgroundWorkSettled()` / `pumpEventQueue()`.

NOW - owner reruns `flutter test test/quotation/add_quotation_viewmodel_test.dart`
and reports the exact result.
NEXT - then the scoped analyzer and the real-device pass listed in the section above.

### List screens — shimmer loading removed (2026-10-06)

Owner request: remove the loading shimmer from the list screens. The Offers,
Requests, Owners, Offices, Brokers, Watchmen and Quotation lists each carried
their own `_ShimmerContainer` skeleton; all seven now show the shared
`ListLoadingIndicator` (one centered `CircularProgressIndicator`) until the
first list arrives. A refresh or a delete still never takes the list off screen.
The duplicated shimmer widgets and builders were deleted. Not changed: the
Favorites skeleton, the Home analytics card placeholder and the media
placeholder in the detail screens (not list screens). Source only; the owners
list test now expects the indicator. Flutter tests/analyzer/device: NOT RUN.

Follow-up: the indicator itself flashed on a fast first read, so
`ListLoadingIndicator` now waits 400 ms (`defaultDelay`) before showing and then
fades in over 250 ms; a list that arrives sooner shows no indicator at all. The
debug line `[EntityList] <list>: first list after N ms` shows the real first-read
time if the delay needs tuning.

NOW - owner runs `flutter test test/lists/owners_list_view_test.dart` and checks
the first-load state of each list screen on the device.

### Favorites — shimmer removed, cached items paint at once (2026-10-06)

Owner request: remove the Favorites loading shimmer and show the items
immediately. The skeleton (`FavoriteCardSkeleton`) and its builder are deleted.
Cause of the slow open: every Favorites screen builds its own `FavoriteService`,
and the on-disk cache box was only readable on the instance that had opened it,
so `getCachedFavoritesSync()` returned nothing at build time and each visit did
a full network load behind the skeleton.

Changes: `FavoriteService.getCachedFavoritesSync()` adopts the signed-in
account's already-open box (the name is built from the live canonical uid, so
it can only reach that account's own box); the view-model re-reads the cache
once its box opens while the first load is still running (never after that load
has answered, so an empty answer is not overwritten by old items); the loading
text (`favoritesLoadingPrimary/Secondary`, unchanged) is shown through
`DelayedReveal`, i.e. only if the first load takes over 400 ms.
`ListLoadingIndicator` now uses the same `DelayedReveal`.

Known behaviour: the cache is only as fresh as the last Favorites visit; a
favorite added or removed on another screen shows on the next open after the
background refresh (about a second), as the original design intended. The
`shimmer` package is no longer imported by app code (still in `pubspec.yaml`).
Tests (source only, NOT RUN): two view-model cases and one service case added.

NOW - owner runs `flutter test test/favorites` and opens Favorites on a device
(second open in a session, and after a restart) to confirm the items appear in
the first frame.

### Favorites — Offer and Owner photos / video frames on the cards (2026-10-07)

Owner report: Favorites cards for Offers and Owners did not show their images
even when the record has media. Rule requested: show the first photo; if the
first file is a video use the first photo after it; if there are only videos,
show the first video's still frame.

Causes (source-read): the Supabase Owner read always returns an empty
`mediaUrls`, so an Owner favorite never had a picture; an Offer read returns the
signed links of ALL its media in server order with no kind, so `mediaUrls.first`
was a video link whenever a video came first, and the card cannot draw a video as
an image; the card keyed its image cache by the signed link, which changes on
every read, so each visit re-downloaded the photo and a stored link was
useless after it expired.

Change: `FavoriteCardMedia` (new) picks the card's media from a record's media
refs (first photo, else first video) and is addressed by the stable,
account-scoped `offerMediaCacheKey`; the link is memory-only. Offers derive it
from the media ids and kinds their read just remembered (no extra request);
Owners resolve their private media (one request per Owner, all Owners at once),
falling back to what the device holds. The card draws a photo through
`OfflineMediaService.buildOfflineAwareImage` with the stable key (local bytes
first, cached by identity, bytes kept on the device for the next open) and a
video through the shared `OfferVideoPoster` with a play mark. The cached
favorite stores only the identity and kind (`entityData`; no Hive schema
change), so a reopened screen can draw the photo or kept frame before any link
exists. Records with plain URLs (Firebase backend) are unchanged.
`FavoritesViewModel` takes an optional `ownerService` for tests.

Not changed: Search result cards use the same `mediaUrls.first` rule and show
no private photos either; reported, not touched (not requested).

Tests (source only): `favorite_card_media_test.dart` (11 cases, also run under
the plain-Dart stand-in: 11/11), Owner/Offer card-media cases in the view-model
tests, and the stored-identity round trip in the isolation tests. Flutter tests,
analyzer, device: NOT RUN.

NOW - owner runs `flutter test test/favorites` and opens Favorites with an Offer
whose first file is a video, an Offer and an Owner with only videos, and an Owner
with photos, checking the card image in each.

### Home filters — Highest Price and Recently Updated implemented (2026-10-07)

Owner request: the two Home chips that were UI only ("Coming soon") now work.

Definitions (pure, in `HomeFilterRules`, like the other three):

- **Highest Price**: the 6 highest-priced Offers and Requests by average price
  (the same price rule as Less Price), highest first; equal prices go newest
  first, then by kind, then by id. Reads only Requests and Offers.
- **Recently Updated**: records last changed in the last 12 hours (the same
  "recent" as Recently Added, `recentlyUpdatedWindow`) AND changed after they
  were created (`updatedAt` strictly later than `createdAt`). The database
  stamps both with one instant on creation, so a new record that was never
  edited is not "updated". Grouped by kind in Home's order, most recently
  changed first inside a kind, then by id. Reads the same six kinds as Recently
  Added; Quotations are never read.
- A record whose own change time is unknown never counts as updated:
  `UnifiedItemModel.hasUpdatedAt` (new, like `hasCreatedAt`) is false for a
  Broker, Office or Watchman with no `updatedAt`, whose stand-in is "now".
- The Home list shows a record's last-change date under Recently Updated (so an
  old record listed there explains itself) and its creation date under every
  other filter.

Data check (read from the migrations): all six tables stamp `updated_at` on
every row UPDATE (trigger `bump_sync_version`); no media or other RPC updates
those rows, so only edits bump it. The app writes an edit with one UPDATE.

The "Coming soon" state (controller phase, view state, two strings) is kept but
unreachable: no chip uses it now. `HomeFilterController` takes a test-only
`isBuilt` so the state stays covered for a future chip. Removing it is the
owner's call.

Tests (source only; the pure ones were also run under a plain-Dart stand-in, not
`flutter test`): `home_filter_rules_test` (66), `home_unified_item_model_test`
(17), `home_filter_controller_test` (60) — 143/143 there; nine deliberate
regressions of the rules and the model were each caught. `home_filter_wiring_test`
gained a guard for the date and needs Flutter. Flutter tests, analyzer, device:
NOT RUN.

NOW - owner runs `flutter test test/home` and tries the five chips on Home
(Highest Price; Recently Updated after editing a record, and after only creating
one).

### Home filters — instant chips, delayed loader, new Arabic labels (2026-10-07)

Owner report: tapping a Home filter chip flashed a very fast loading state.
Cause: every tap re-read the records from the backend and replaced the list
area with a spinner and text at once.

Change: a filter is a calculation over the signed-in user's own records, so
`HomeFilterController` now reads the records once and keeps them, by kind. A
chip whose kinds are all held answers at once, with no loading state; only the
kinds not held are read (the first chip of a session, or the kinds a later chip
adds). What is held is dropped on a change to the user's records
(`onDataChanged`, which Home already signals), on a pull to refresh, after
5 minutes (`recordsValidFor`, as Search), when the clock goes back, when it
belongs to another account than the signed-in one (`currentUserId`, passed by
`HomeViewModel`), and on `reset()` (sign-out). A plain `clear()` (tapping the
chosen chip, leaving Home) keeps it. The answer is always worked out at the
moment of the tap, so a time window uses the current clock. A failed read keeps
nothing new; what earlier chips read stays held.

When a read is still needed, the loading state (`FilteredItemsView`) appears
only after 400 ms and fades in (`DelayedReveal`, as the list screens), so a read
that returns quickly shows nothing.

Arabic wording (owner's choice): Recently Added is "مضاف مؤخرًا" and Recently
Updated is "مُحدَّث مؤخرًا". The `recentlyAdded` key is also the Favorites
chip's label, so Favorites shows the same wording. (The Arabic file declared
`recentlyAdded` twice; both entries now say the same.)

Tests (source only; the pure ones also run under a plain-Dart stand-in, not
`flutter test`): `home_filter_controller_test` 77, `home_filter_rules_test` 66,
`home_unified_item_model_test` 17 — 160/160 there; ten deliberate regressions
of the new holding logic were each caught. `home_filter_wiring_test` gained
guards for the sign-out reset, the account tie and the delayed loader and needs
Flutter. Flutter tests, analyzer, device: NOT RUN.

NOW - owner runs `flutter test test/home test/favorites` and, on the device,
taps the five chips in turn (the second and later should answer at once), edits
a record and returns to Home, and signs out and in as another account.

### One header for Home, Search and Favorites (2026-10-07)

Owner report: the three tabs did not look like one app. Each had its own copy of
the avatar + name + bell header, so the subtitle colour and size, the gap under
the name and the wording had drifted; Search "welcomed" the user like Home, and
Favorites said "saved picks" instead of favorites.

Change: one widget, `UserScreenHeader` (`lib/src/views/Widgets/
user_screen_header.dart`), draws the header for all three. It owns the avatar
(48, opens edit-profile), the greeting + name (`headlineSmall`, animated on a
name change, one line), a 2 px gap, the subtitle (`bodyMedium` in the theme's
`onSurface` at 60%, one line) and the bell. The screen passes only its subtitle.
Home's old subtitle was a fixed grey at 16; it now matches the other two. The
private copies in Search and Favorites and Home's `_buildHeader` are gone, along
with the imports only they used.

Subtitles, each proper for its screen: Home keeps `welcomeMessage` (welcome);
Search uses the new `searchHeaderSubtitle` — "Search all your items" /
"ابحث في كل عناصرك"; Favorites `favoritesOverviewTitle` is now "Your favorites" /
"عناصرك المفضلة" (was "Your saved picks" / "عناصرك المحفوظة").

Found, not changed: `app_ar.arb` declares `welcomeMessage` twice. The later
one wins ("مرحباً بك في محفظة الوسيط"); the shadowed first one ("عما تبحث
اليوم؟", "what are you looking for today?") reads like a search prompt and is a
candidate for Search if the owner prefers it. Removing the duplicate is the
owner's call.

Tests (source and string guards; run under the plain-Dart stand-in, not
`flutter test`): new `test/home/screen_header_unity_test.dart` 13/13 — each
screen uses the one widget and carries no header of its own, the sizes/gap/
colour/overflow are set once in the widget, the three subtitles exist and differ
in both languages, Favorites says favorites, Search does not welcome. Sixteen
deliberate regressions (gap, size, opacity, hard-coded colour or font size, a
wrapping subtitle, a private header or avatar or bell coming back, a wrong
subtitle key, the old wording returning) were each caught.
`favorites_screen_ui_test` was updated to read the shared widget.

Owner's `flutter test test/home test/favorites`: 333 passed, 2 failed, both in
`favorites_screen_ui_test` and neither about the header — stale grid guards,
identical on `HEAD`. The grid's bottom padding became 96 in `36f1347`
(bottom nav bar) and the Favorites skeleton was removed in `cd56303`, but the
guards still expected 20 and three grid uses. Fixed: Favorites' grid padding
must equal Search's (both read from source, no number baked in), and the cards
are the only user of the grid (2 delegate uses, 1 `SliverLayoutBuilder`, no
skeleton or shimmer). Checked against the real sources by script with six
deliberate regressions, all caught; the re-run is the owner's. Analyzer,
device: NOT RUN.

NOW - owner re-runs `flutter test test/home test/favorites` and, on the device,
looks at Home, Search and Favorites in both languages and both themes: the name,
gap and subtitle should be identical on all three, and a long name should end
in "..." on one line.

### Favorites: no counts, no sync pill (2026-10-07)

Owner question: are "Total saved", "Visible now" and the "Synced" pill needed
on Favorites? Decision (owner delegated it): no, removed.

Why: with no filter chosen the two counts are the same number twice; with a
filter chosen the grid and its empty state already show what is shown. "Synced"
says nothing in the normal case and the background refresh needs no badge: the
cached list is shown at once, a pull to refresh has its own indicator, and a
failed load has its error state. Search keeps its result count because it
answers a question the user asked; Favorites has no such question. Home and
Search never had these pills.

Change: `FavoritesStatusRow`, its three pills and the number formatter are gone
from `favorites_view.dart`, so the cards now follow the filter chips directly
(the chips' bar and the grid's own 8 dp top padding give the spacing). The four
strings (`favoritesTotalCountLabel`, `favoritesVisibleCountLabel`,
`favoritesSyncedChip`, `favoritesSyncingChip`) are removed from both ARB files.
Kept: the header, the chips, the grid, the loading/error/empty states and the
"Pull down anytime to refresh and sync." line at the foot of the list (not part
of this request; also removable if the owner wants a cleaner foot). No view-model
change.

Tests: the status-row widget tests are removed with the widget, along with the
`_pump` options only they used; a new source guard asserts the row, its
formatter and the four strings stay gone and that the cards follow the chips
directly. The guard and the trimmed key list were evaluated against the real
sources with eight deliberate regressions, all caught; the Flutter run is the
owner's. Flutter tests, analyzer, device: NOT RUN.

NOW - owner runs `flutter test test/favorites test/home` and looks at Favorites
on the device (EN and AR, light and dark): the chips should sit under the header
and the cards start right under them, with no gap or pill in between.
