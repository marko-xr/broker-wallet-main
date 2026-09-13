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
3. DELETE ACCOUNT — next.
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
