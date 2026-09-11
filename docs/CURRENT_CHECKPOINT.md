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

Committed after FLUTTER-P2 (their real-device status is not recorded in this
file; do not treat them as VERIFIED_RUNTIME from this list):

- `94e7315` unify auth profile state and R2 media updates
- `998e31e` session-first auth bootstrap and unified navigation
- `ca77d03` stabilize cached profile presentation
- `905702d` immediate and resilient profile saves
- `5534730` remove Facebook authentication

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

PROJECT ORDER

1. EMAIL CHANGE — next major checkpoint.
2. PASSWORD
3. DELETE ACCOUNT
4. GOOGLE / APPLE — deferred until later.

Facebook authentication remains removed.

NOW — start the EMAIL CHANGE checkpoint with a read-only inspection; implement
only after the plan is approved.

NEXT — after Email Change passes real-device verification, start PASSWORD.
