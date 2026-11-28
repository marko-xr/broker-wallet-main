# Google sign-in and sign-up (Android)

Task 02A.1, 2026-11-28, branch `feature/auth-google-signin` (cut from `chore/task01-final-handoff` `f01bcc9`).
Status: **LOCAL_TESTED** (CODE_READY / EXTERNAL_CONFIG_REQUIRED). Nothing hosted was read or changed; no device run.

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
  Supabase's documented behaviour, not this project's design, and it has **not** been observed on the hosted project.
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
   reports "Google sign-in isn't available right now".

Read-only check of the hosted provider state (public endpoint, publishable key from `supabase_config.dart`):
`GET https://rbvcnvqpdqrhywcgxkne.supabase.co/auth/v1/settings` → `external.google`. Not run in this task.

## Device acceptance (owner)

Debug build with the define, on the Samsung (`adb install -r` only, see the install-safety note): new Google account
→ Home and a profile with the Google name; same account again → same user, no duplicate; an existing confirmed email
account with the same Gmail → same user, name kept; picker closed → no message; airplane mode → network message;
logout → Login, next sign-in shows the picker; Arabic/RTL and dark mode of both buttons; a second device signing in
displaces the first (Single Active Device).

## Known gaps

- **Delete Account for a Google-only account is refused** (Worker `verifyAccountPassword` →
  `reauthentication_unsupported`, fail-closed; app message `deleteAccountErrorUnsupported`). A Google account that is
  linked to an email/password account can still delete with its password. A Google re-authentication for deletion is
  a security design for the owner; Google Play and Apple both require in-app account deletion.
- Change Password / Change Email for a Google-only account were not reviewed (task 02D).
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
- Not run: full suite, any build, device, hosted.
