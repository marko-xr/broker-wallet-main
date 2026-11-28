# Google sign-in and sign-up (Android)

Task 02A.1, 2026-11-28, branch `feature/auth-google-signin` (cut from `chore/task01-final-handoff` `f01bcc9`; code
commit `cadd04f`, on origin).
Status (Android, debug build): **LOCAL_TESTED, HOSTED_VERIFIED, DEVICE_VERIFIED** (owner, Samsung, 2026-11-28).
**Not PRODUCTION_READY**: Google-only accounts cannot delete themselves (mandatory release blocker, see Known gaps).

## What it does

- The existing Google button on Login and on Sign-up (unchanged layout) runs one flow:
  `SignInViewModel.signInWithGoogle` / `SignUpViewModel.signUpWithGoogle` → `GoogleSignInFlow` →
  `AuthViewModel.signInWithGoogle` → `SupabaseAuthRepository.signInWithGoogle`.
- `PluginGoogleIdTokenSource` (`lib/src/services/google_id_token_source.dart`) shows Google's account picker
  (`google_sign_in` 6.3.0, `serverClientId` = the Web client ID) and returns the ID token and access token. The
  plugin's own signed-in state is cleared before (if left over) and after every attempt, so the picker always appears
  and another Google account can be chosen. Nothing is stored or logged.
- The repository sends the tokens once to Supabase Auth (`signInWithIdToken`, provider `google`, no nonce: the Android
  token carries none). Supabase verifies the token and finds or creates the user. The session then goes through the
  same `claim: true` Single Active Device authorization as email and phone sign-in; the identity is published only
  after the claim succeeds, and a refused or superseded claim ends the local session.
- Login and Sign-up are the same sign-in. A new Google account gets an account; an existing one is signed in. There is
  no separate "Google sign-up" that could create a second account.
- Session restore, token refresh and logout are the existing provider-independent Supabase paths; Google keeps no state.

## Identity and account safety

- The same Google account always maps to the same Supabase user (identity = provider + Google `sub`).
- `auth.users.id = public.profiles.id` is unchanged. A new account's profile is created by the existing
  `on_auth_user_created` trigger with the Google `full_name`; `sync_auth_identity_to_profile` then sets
  `is_email_verified`. An existing profile name is never overwritten (the profile wins over Google metadata).
- The app never matches, links or merges accounts. Joining an existing account with the same email is Supabase Auth's
  automatic linking: only an email the provider reports as verified links, and for an account whose email was never
  confirmed GoTrue first removes that account's unconfirmed credentials (pre-account-takeover protection). This is
  Supabase's documented behaviour, not this project's design, and it has **not** been observed on the hosted project:
  the device test deliberately used Gmail addresses that no Broker Wallet account had (all five earlier accounts are
  Gmail addresses, so signing in with one of them would link Google to that real account).
- The phone sign-up hook (`20261122120000`) returns early for sign-ups without a phone, and Model X records a Google
  account as `email` primary. Neither is applied on the hosted project.
- Failures carry fixed messages only (`AuthFailure.fromSupabaseGoogleSignIn`): no server text, token or account detail
  reaches a screen. Closing the picker is `AuthFailureCode.cancelled` and shows nothing.

## Why `google_sign_in` 6.x

`google_sign_in` 7.x uses Android Credential Manager, but `google_sign_in_android` 7.0.4+ needs the Android Gradle
plugin 8.12.1; the app is on 8.11.1, the same blocker that pins `connectivity_plus` 6.1.5. 6.3.0 was already locked
and compiled into the 01F.1 release APK, so this task changes no dependency. 6.x uses Google's legacy Sign-In for
Android API, which Google has deprecated (removal date not announced in the current English guide). Upgrading AGP and
moving to 7.x is its own checkpoint before a public release; only `PluginGoogleIdTokenSource` would change. Guard:
`test/auth/google_sign_in_test.dart` D4.

## Platforms

- **Android:** implemented.
- **iOS:** reports "not available" (no picker opens). Needs an iOS OAuth client, `GIDClientID` and the reversed client
  ID URL scheme in `Info.plist`, and Supabase "Skip nonce check" (the iOS SDK adds a nonce). Not in this task.
- **Web:** reports "not available". The web plugin does not return an ID token from the app's own button.

## Owner setup (no secret goes into Git or a chat)

Done by the owner on 2026-11-28 in Google Cloud project `broker-wallet` (number 285578142613) and the Supabase
project: Web client, Android client for the debug SHA-1 below, Google provider enabled. The OAuth app is in
**Testing** (only listed test users can sign in). Clients for the release/upload key and the Play App Signing key do
not exist yet.

1. **Google Cloud** (the project that will own sign-in): OAuth consent screen (app name, support email, privacy policy
   URL, scopes `openid`, `email`, `profile`).
2. **Web application** OAuth client. Its client ID is the `serverClientId`; its client secret is needed only for a
   browser OAuth flow, which this Android implementation does not use.
3. **Android** OAuth client(s) with package `com.nmodigital.brokerwallet`, one per signing certificate SHA-1:
   - debug key on this computer: `23:EE:CE:98:0F:47:3D:D1:72:A4:D1:E0:D7:ED:F6:3E:78:A4:EF:31`
     (`%USERPROFILE%\.android\debug.keystore`, the key the 01F.1 APK was signed with);
   - the release/upload key, once created (none exists yet);
   - the Play App Signing key from Play Console, for store installs.
   A missing SHA-1 shows as `sign_in_failed` with `ApiException: 10` (DEVELOPER_ERROR) in the debug log.
4. **Supabase Dashboard** → Authentication → Sign In / Providers → Google: enable, and put the **Web** client ID first
   in "Client IDs". Leave "Skip nonce check" off for Android. This is a hosted auth change on the shared
   staging/production project: it needs the owner's explicit approval of that step.
5. **Build:** `--dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>.apps.googleusercontent.com`. Without it the button
   reports "Google sign-in isn't available right now" (Arabic: «تسجيل الدخول بحساب Google غير متاح حاليًا»).

Read-only check of the hosted provider state (public endpoint, publishable key from `supabase_config.dart`):
`GET https://rbvcnvqpdqrhywcgxkne.supabase.co/auth/v1/settings` → `external.google`. Read on 2026-11-28 after the
owner's setup: `google: true`, `email: true`, `phone: false`, `disable_signup: false`.

## Test build and install (2026-11-28)

- A debug APK only signs in with Google when built with the define, for example
  `flutter build apk --debug --target-platform android-arm64 --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>`.
  The first APK on the phone (built in the main checkout at 19:04 +04) had the Google code but no client ID (0 matches
  in its `kernel_blob.bin`), so it showed the "not available" message by design; a build with the define fixed it.
- Install with `adb -s <serial> install -r --user 0 <apk>` only; never `flutter run` / `flutter install`, which can
  uninstall the app and wipe its data. The Samsung is reachable over wireless ADB as
  `adb-R5CY10YYLSM-kfXa7O._adb-tls-connect._tcp` (users: 0 owner, 95 Dual App, 150 Secure Folder).
- The store-compliance hook blocks `flutter build apk` in the main checkout on git-ignored staging reports. Building a
  `git archive` export inside `build/` scopes the scan to the committed tree; the build command must stand alone (an
  extra `flutter pub get`, `2>&1` or similar segment keeps the Apple-only rules on and blocks it).

## Device acceptance (owner, Samsung SM-S928B, Android 17, 2026-11-28)

Results are the owner's own runs, reported to the agent; the agent did not operate the phone.

| # | Case | Result |
|---|---|---|
| G1 | New Google account → Home, profile with the Google name | OWNER-VERIFIED PASS |
| G9 | Google from the Sign-up screen (same flow, no second account) | OWNER-VERIFIED PASS |
| L1 | Logout → Login screen, stays signed out after reopening | OWNER-VERIFIED PASS |
| L2 | Returning login with the same Google account → picker → same user | OWNER-VERIFIED PASS |
| L3 | Cancel the account picker → no message, button works | OWNER-VERIFIED PASS |
| L4 | Network failure (airplane mode) → network message, button recovers | OWNER-VERIFIED PASS |
| L5 | App closed from recents and reopened → Home without signing in | OWNER-VERIFIED PASS |
| L6 | Arabic and English: button, messages, RTL/LTR | OWNER-VERIFIED PASS |
| G8 | Same Google account on a second device → first device signed out (Single Active Device) | OWNER-VERIFIED PASS (device attribution is not visible in the database) |
| E1–E4 | Email/password regression with the designated test account: login, wrong-password message, logout and login, restart keeps the session | OWNER-VERIFIED PASS |

Not tested: linking Google to an existing email account (avoided on purpose, see above); dark mode; Delete Account
with a Google-only account (refused by design, see Known gaps); Change Password / Change Email for a Google-only
account; a release-signed or Play-installed build; iOS and web.

Hosted integrity, read-only SQL (aggregates, booleans and 6-character id tails only), 2026-11-28:

| Check | 12:15 UTC (before) | 15:54 UTC (after) |
|---|---|---|
| `auth.users` / `public.profiles` | 5 / 5 | 7 / 7 |
| Users without profile / profiles without user | 0 / 0 | 0 / 0 |
| Duplicate emails / duplicate identities | 0 / 0 | 0 / 0 |
| Email identities / Google identities | 5 / 0 | 5 / 2 |
| Users with both Google and email identities (linking) | 0 | 0 |
| Profile email or verified flag differing from Auth | 0 | 0 |
| Users with more than one active-session row | 0 | 0 |

The two Google test accounts (`…4f3f5c`, created 15:36:02 UTC, 4 sign-in claims; `…939145`, created 15:36:43 UTC,
1 claim) each have one Google identity, one profile whose name is the Google name, a matching verified email, no
phone, and at 15:54 UTC no live session and no active-session row (signed out). They are production rows and cannot
be removed from the app (Known gaps); removing them is a separate, owner-approved admin step. Email sign-ins of one
email account at 15:56:59 and 15:57:41 UTC created session claims as expected.

## Known gaps

- **Mandatory release blocker, unresolved: Delete Account for a Google-only account is refused** (Worker
  `verifyAccountPassword` → `reauthentication_unsupported`, fail-closed; app message `deleteAccountErrorUnsupported`).
  A Google account that is linked to an email/password account can still delete with its password. Google Play and
  Apple both require in-app account deletion, so Google sign-in cannot ship until a Google re-authentication for
  deletion is designed, approved by the owner, implemented and device-verified.
- The OAuth app is in Testing; only the debug SHA-1 has an Android client. Release/upload and Play App Signing
  clients and publishing the OAuth app belong to the release task.
- Two Google test accounts now exist in production (above).
- Change Password / Change Email for a Google-only account were not reviewed (task 02D).
- On Sign-up the email submit button also shows its spinner while Google runs (it reads `authVM.isLoading`); left
  as it was.
- `google_sign_in` 6.x legacy API (above). iOS and web not implemented.

## Evidence (2026-11-28, Windows, Flutter 3.47.2 / Dart 3.13.2, agent-run)

- `test/auth/google_sign_in_test.dart`: 26/26 (repository on a real `SupabaseClient` with a recorded HTTP layer, the
  plugin adapter with a fake plugin, the screen flow on a real `AuthViewModel`, guards).
- Related auth files (`auth_boundary_invariants`, `auth_failure_mapping`, `auth_repository_contract`, `phone_sign_in`,
  `password_policy`, `phone_account_lifecycle`, `facebook_auth_removed`, `logout_contract`,
  `responsive/r4_auth_responsive`): together with the new file 204/204.
- Mutation check: skipping the device claim (A5, A6), not clearing the plugin state (B3–B7) and dropping the
  double-tap guard (C4) each failed tests.
- `flutter analyze` on the changed and new files: no issues. `git diff --check` clean. New files `dart format` clean.
- Hosted and device evidence: the sections above (owner-run device cases; agent-run read-only hosted checks).
- Not run: full suite, a release build, iOS, web.
