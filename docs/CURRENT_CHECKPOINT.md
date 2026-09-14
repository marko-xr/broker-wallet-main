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
