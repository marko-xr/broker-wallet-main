# Google sign-in and sign-up (iOS)

Task 02A.2, 2026-11-28, branch `feature/auth-google-ios` (cut from `integration/broker-wallet-development` `2621654`).
Status: **LOCAL_TESTED** on Windows only (Dart tests and source guards). **Not built for iOS, not run on an iPhone,
nothing hosted changed.** The Android flow (`docs/GOOGLE_SIGN_IN_ANDROID.md`) is unchanged and reused.

## What changed

- Same flow as Android: `GoogleSignInFlow` → `AuthViewModel.signInWithGoogle` →
  `SupabaseAuthRepository.signInWithGoogle` → `signInWithIdToken` → the same `claim: true` Single Active Device
  authorization before any identity is published. No view, view model, repository or database change.
- `PluginGoogleIdTokenSource` now knows the platform. Android: unchanged (`serverClientId` = Web client ID, on when
  `GOOGLE_WEB_CLIENT_ID` is set). iOS: on only with `--dart-define=GOOGLE_SIGN_IN_IOS=true`, and the plugin is created
  **without** a client ID.
- The iOS client ID is set once, in `ios/Flutter/GoogleSignIn.xcconfig` (`GOOGLE_IOS_CLIENT_ID_PREFIX`, the client ID
  without `.apps.googleusercontent.com`; empty in Git). `Info.plist` builds both `GIDClientID` and the Google URL
  scheme `com.googleusercontent.apps.<prefix>` from it, so the client the SDK uses always has its scheme. This matters:
  with `google_sign_in_ios` 5.9.0 a missing scheme raises an exception that the plugin re-raises, which ends the app.
  An empty prefix with the flag on should give Google's "invalid client" page rather than a crash, because the client
  ID and the scheme are still derived from the same value (expected from the SDK's scheme rule; not run).
- `Info.plist` had a hard-coded Google URL scheme of an unrelated Google Cloud project (`460721646511-…`); it is
  replaced. `Debug.xcconfig` and `Release.xcconfig` include the new file (Profile uses Release).
- `GoogleService-Info.plist` (project `broker-wallet`, bundle `com.nmodigital.brokerwallet`) has no `CLIENT_ID`. If a
  newer copy with `CLIENT_ID` is ever added, the plugin prefers it, so it must be the same iOS client as the prefix.

## Locked SDK facts (`google_sign_in` 6.3.0, `google_sign_in_ios` 5.9.0, GoogleSignIn iOS SDK ~> 8.0)

- No app-supplied nonce: nonce support starts in `google_sign_in_ios` 6.1.0 (GoogleSignIn 9), which needs the
  `google_sign_in` 7.x line, blocked on Android by AGP 8.11.1 (see the Android document). The iOS SDK puts its own
  nonce in the ID token, so Supabase must have **"Skip nonce check"** on for iOS sign-in, as the Supabase Google guide
  says for iOS.
- Supabase's Google provider must list the **Web client ID first, then the iOS client ID** in "Client IDs".
- Error codes map as on Android: cancel → `sign_in_canceled` (no message), no network → `network_error`, anything else
  → `sign_in_failed`.

## Owner actions (no secret in Git or chat)

1. **Google Cloud**, project `broker-wallet` → Google Auth Platform → Clients → Create client → **iOS**: name
   `Broker Wallet iOS`, bundle ID `com.nmodigital.brokerwallet` (App Store ID and Team ID can wait). Copy the client
   ID; it is public. Check first that no iOS client for this bundle exists.
2. **Repository** (a separate small commit): set `GOOGLE_IOS_CLIENT_ID_PREFIX = <client id without
   .apps.googleusercontent.com>` in `ios/Flutter/GoogleSignIn.xcconfig`.
3. **Supabase**, Authentication → Providers → Google (a hosted change on the shared staging/production project; needs
   the owner's explicit approval): Client IDs = `<web client id>,<ios client id>`; turn **Skip nonce check** on.
   Effect: Supabase stops comparing the token's nonce for every Google sign-in. Android tokens carry no nonce today, so
   Android loses nothing; iOS tokens are still checked for signature, issuer, audience and expiry.
4. **Test users**: while the OAuth app is in Testing, the Google account used on the iPhone must be a listed test user.
5. **Mac**: Xcode with a signing team for the iPhone (a free Apple ID can sign a debug build for a personal device);
   then from the repository root `flutter build ios --debug --dart-define=GOOGLE_SIGN_IN_IOS=true` (or `flutter run -d
   <iPhone> --dart-define=GOOGLE_SIGN_IN_IOS=true`). CocoaPods or Swift Package Manager resolves GoogleSignIn ~> 8.0.

## Device acceptance (owner, iPhone): NOT TESTED

Same cases as Android: new user from Login and from Sign-up, returning login, cancel, network failure, logout,
restart, Arabic/English, second device (Single Active Device), email/password regression. Then the read-only Supabase
integrity check (one user, profile and Google identity per Google account; no duplicates or linking).

## Release blockers on iOS

- Google-only accounts cannot delete themselves (Android document, Known gaps).
- App Store guideline 4.8: an app that offers Google sign-in must also offer Sign in with Apple or an equivalent
  (task 02B).
- "Skip nonce check" stays a documented compromise until the SDK upgrade that allows an app nonce.

## Evidence (2026-11-28, Windows, agent-run)

- `test/auth/google_sign_in_test.dart` 29/29 (B2 platform gates, B8 plugin arguments per platform, B9 iOS flow, D5
  `Info.plist` / xcconfig guard); with `auth_boundary_invariants` and `auth_repository_contract` 41/41.
- `flutter analyze` on the changed Dart files: no issues. `Info.plist` parses as XML.
- Not run: iOS build, CocoaPods/SPM resolution, iPhone, hosted.
