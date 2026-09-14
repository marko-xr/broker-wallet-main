# Project state

Broker Wallet is in a staged Firebase → Supabase migration. This is not a full Supabase cutover; Firebase behavior remains for sections not yet migrated.

The existing-account Supabase Email Change flow is VERIFIED_RUNTIME. It failed
its first real-device test, was fixed, and the product owner has since confirmed
a successful end-to-end change — including the Secure Email Change two-mailbox
flow — on a real device. It derives pending state from Supabase Auth, keeps
`auth.users.email` canonical until confirmation, reuses the existing auth
callback, and relies on the server identity-sync trigger for
`public.profiles.email`.

The Edit Profile screen's UI polish is VERIFIED_RUNTIME / accepted by the
product owner on a real device in both English and Arabic, with name save,
profile image save, Email Change entry and Add Phone entry all confirmed
working and no reported regression.

Phone Login and Phone Sign-up UI is present and selectable on both screens at
the product owner's request, and that restoration is VERIFIED_UI. Phone
authentication itself is NOT implemented and NOT runtime verified in Supabase
mode: it is legacy-Firebase only, and the screens say so in EN/AR. The
signed-in Add Phone / verification flow is preserved, and real UAE SMS delivery
remains externally deferred.

Password is VERIFIED_RUNTIME. The product owner confirmed on a real device
Change Password, Forgot Password, the dedicated recovery callback, recovery
across warm, backgrounded, cold and process-death starts, reset followed by
sign-out to Sign In, cancel, reused-link safety, old-password rejection and
new-password sign-in. It first failed real-device acceptance with a
security/routing blocker — a recovery session was treated as an ordinary
authenticated session and could reach Home — which the recovery-session
quarantine below resolved.

The application now distinguishes a normal authenticated session from a
password-recovery session. Recovery ownership is resolved by the repository
before it publishes the session identity and is mirrored by `AuthViewModel` in
the same turn, so status and recovery are one atomic snapshot and GoRouter can
never see an authenticated session before it sees that the session is a
recovery. While a recovery is unresolved the only reachable route is
`/reset-password`, and both completing and cancelling a reset sign the recovery
session out and land on Sign In. A uid-bound local marker lets a recovery that
survived process death be recognised, because Supabase restores it as an
ordinary `initialSession`.

Change Password, Forgot Password and the recovery deep link are implemented
on Supabase Auth only, behind a single `PasswordCapability` on the repository
and a single canonical `PasswordPolicy`. Recovery context comes from
`AuthChangeEvent.passwordRecovery` republished by the existing auth pipeline,
so no second deep-link listener and no second session authority were added,
and `/reset-password` is reachable only while that recovery is unresolved.

Password recovery has its own deep-link address,
`brokerwallet://auth/reset-password`, while every other auth flow keeps
`brokerwallet://auth/callback`. That split is what makes an expired recovery
link distinguishable from an expired Email Change link, which GoTrue's error
redirect otherwise renders identical, so no timing heuristic takes part in
classifying a callback. It requires the new URL to be present in the hosted
redirect allowlist as an exact entry.

The current-password step is deliberately configuration-gated and off,
matching the hosted settings the owner verified: minimum length 8, no required
character classes, Secure password change OFF and Require current password
OFF. Leaked-password protection is unavailable on the current Free plan. No
agent changed any hosted setting.

Delete Account status:

- `account_deletion_jobs` migration: APPLIED + VERIFIED_HOSTED.
- Staging Worker (`r2-profile-upload-staging`): the access gate, R2
  authorize / PUT / confirm / signed GET, correct-password hard delete, and the
  deleted user's old-JWT retry returning 401 `session_expired` are
  VERIFIED_RUNTIME.
- Hosted: removal of the `auth.users`, profile and media rows, and the cron
  stamping `cleanup_not_before` then removing the deletion job, are
  VERIFIED_HOSTED.
- Production Worker `r2-profile-upload`: version
  `f5bdf3eb-400e-488f-930b-d3c5e78a0624` deployed at 100% traffic, with rollback
  target `491a5e0f-6b51-4ca9-8d33-8164bcfec348`. `media-api.brokerwallet.ae` is
  attached, the `*/5 * * * *` cron is deployed, and `STAGING_TEST_KEY` is not
  bound. No-JWT smoke returns 401 on `/authorize`, `/profile-image-url` and
  `/account/delete` (`session_expired`).
- Production normal Delete Account happy path and wrong-password path:
  VERIFIED_RUNTIME + VERIFIED_HOSTED + VERIFIED_REAL_DEVICE (2026-09-14, one
  disposable account).
  - Wrong password leaves the account, profile and image intact.
  - Correct password lands on Welcome with no Home and no stale
    profile/name/image, including after force-stop and cold restart.
  - The old credentials no longer sign in.
  - Hosted afterwards: no auth user, no profile, 0 `media_objects`, 0 deletion
    jobs, and the production finalizer completed.
- Dedicated lost-response / cut-network scenario: NOT RUN / DEFERRED. The
  lost-response marker and bootstrap quarantine are CODE_PROVEN only.
- Staging infrastructure is temporarily retained.

The existing Profile row opens a two-step confirmation (what is deleted, then
password plus an explicit acknowledgement). Deletion runs server-side in the
existing `r2-profile-upload` Worker: the account comes only from the verified
session token, the password is re-verified there, the account's R2 objects are
removed and proven gone, and only then is `auth.users` deleted so the database
cascade removes the profile and owned data. Flutter never holds a server
credential and never sends a user id. After success, `AuthViewModel` ends local
state for that account and clears an explicit inventory of user-scoped caches,
keeping language and theme.

Work that must happen after the account is gone is authorized by a
server-owned `account_deletion_jobs` row, never by the deleted account's token.
The row blocks new signed upload URLs while a deletion runs, and a scheduled
Worker finalizer sweeps the account's R2 prefix once every previously issued
URL has expired.

The application now also distinguishes a session whose account has a deletion
of unknown outcome. If a restored or newly signed-in session belongs to the
account named by the local pending-deletion marker, `AuthViewModel`
quarantines it in the same turn: it is never application-authenticated, GoRouter
holds the bootstrap route, and nothing account-scoped starts. It asks Supabase
Auth what happened, and always ends that session on the device, reporting a
deletion only when Supabase Auth says the account is gone. The job-table
migration is applied and hosted-verified, and the production Worker is deployed.
That lost-response path has not been exercised at runtime (NOT RUN / DEFERRED;
see `docs/CURRENT_CHECKPOINT.md`).

The Realtime `RealtimeSubscribeException` on `public.notifications` observed
during the first failed recovery test did not reproduce after the quarantine
fix, in recovery, after a normal login, or in Notifications. It is recorded as
exposed by the incorrect recovery-to-Home path, not as a backend schema defect.
