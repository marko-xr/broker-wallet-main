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

The Realtime `RealtimeSubscribeException` on `public.notifications` observed
during the first failed recovery test did not reproduce after the quarantine
fix, in recovery, after a normal login, or in Notifications. It is recorded as
exposed by the incorrect recovery-to-Home path, not as a backend schema defect.
