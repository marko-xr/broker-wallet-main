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
  target `491a5e0f-6b51-4ca9-8d33-8164bcfec348` (the version Delete Account was
  accepted on; production now runs the Offer media version below). `media-api.brokerwallet.ae` is
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

Offer private media is accepted by the product owner (VERIFIED_REAL_DEVICE,
Samsung, 2026-09-27): selecting images and videos, one combined Gallery
selection through the Android Photo Picker with no media-library permission
prompt, photo and video capture through the phone's own camera app
(`image_picker`; no in-app camera), saving and reopening Offers with media,
private playback, seeking, persisted thumbnails, and switching between videos
without the disposed-controller error. Each item gets a `mediaObjectId` on the
device, used unchanged by the persistent upload queue, the Worker,
`media_objects`, the R2 key and the local cache. An Offer saves without waiting
for its media; files reach the private `broker-wallet-media` bucket through
short-lived signed URLs, and the service-role-only `confirm_offer_media_upload`
function attaches them (migration `20260926092220`, APPLIED + VERIFIED_HOSTED).
Signed links are held in memory only. Limits: 10 items per Offer, images
10 MiB, videos 100 MiB and 3 minutes, checked on the device and again by the
Worker. The production Worker (`6387e2c0-db49-43eb-a0e0-edaca76e3e5e` since
the Owner media deployment of 2026-09-28, owner-reported; it served Offer
media as `ecaf125d-a0e3-4c26-add6-5f2c684c2516` before that) runs with the
Offer-media sweeps `off`. Interruption, account switching, permission refusal,
process death, iOS and sweep scenarios are NOT RUN (`MEDIA-12`…`MEDIA-26` in
the deferred master test plan). Private Offer documents (Task C) are deferred.

Owner private media is the active checkpoint (2026-09-28): the Offer media
lifecycle for Owner records, under the same rules (owner decision). Source is
written for all three layers — the `confirm_owner_media_upload` migration with
its pgTAP and rollback-only validation, the Worker's Owner routes with
per-entity abandoned-upload cleanup (F1), and the Flutter Owner form, details
gallery, shared upload queue and per-form lost-picker recovery (F2). The owner
reports the Worker suite at 120/120 and the targeted Flutter suite at 60/60,
and `flutter analyze` with no errors or warnings. The migration is APPLIED +
VERIFIED_HOSTED as version `20260928131828` (owner-applied and read back; the
repository file carries that version). The Worker with the Owner routes is
deployed (owner-reported): staging `ac033060-5cbf-4b9c-8932-592bd88ab6ef`,
where the repository's acceptance runner
(`cloudflare/workers/r2-profile-upload/staging-acceptance/`) passed 126/126,
and production `6387e2c0-db49-43eb-a0e0-edaca76e3e5e` (rollback
`ecaf125d-a0e3-4c26-add6-5f2c684c2516`), whose smoke tests passed; every media
sweep stays `off`. Still open: the second, day-later phase of the F1 staging
check, and all Owner media device acceptance, including F2's lost-picker
scenario (see `docs/CURRENT_CHECKPOINT.md`). The milestone is committed
locally on `feature/owner-private-media`.

The Realtime `RealtimeSubscribeException` on `public.notifications` observed
during the first failed recovery test did not reproduce after the quarantine
fix, in recovery, after a normal login, or in Notifications. It is recorded as
exposed by the incorrect recovery-to-Home path, not as a backend schema defect.

A UI performance checkpoint is VERIFIED_REAL_DEVICE (2026-09-28, branch
`perf/navigation-list-transitions`): the Home tab no longer waits for its
count refresh before fading in, and the six entity lists share one list
lifecycle (`EntityListState`) so a delete, a status change or a refresh no
longer blanks the screen, with a visible loading placeholder and item-level
delete progress. Owner-run verification: 43/43 targeted regression tests
PASS, Flutter analyzer accepted, and Samsung physical-device acceptance PASS.
No push, deployment or merge occurred; see `docs/CURRENT_CHECKPOINT.md`.

The Broker Wallet Plus subscription UI is SOURCE IMPLEMENTED on
`upgrade-plus-plan-and-payment` (2026-10-01): paywall, purchase review, purchase
progress and results, restore, and a "Subscription & Billing" hub that Profile
opens (rebuilt 2026-10-01 after the owner rejected the first layout on a device)
with its own Manage subscription, Change billing period, Payment methods,
Billing history & receipts, Subscription help, Legal and Plan usage screens,
localised in English and Arabic. It is presentation only: RevenueCat, Play
Billing and StoreKit are NOT INTEGRATED, no real purchase has been made, release
builds say plans are not available yet, and Broker Wallet holds no card details
(the store bills and manages payment; the Payment methods screens only explain
and hand off). The owner reports the subscription tests 142/142 PASS before the
Subscription & Billing work; the rebuilt screens' tests are written but not yet
run, and nothing is verified on a device. See `docs/CURRENT_CHECKPOINT.md` and
`docs/DECISIONS.md`.
