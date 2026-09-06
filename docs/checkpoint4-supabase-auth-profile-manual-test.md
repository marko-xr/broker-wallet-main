# Checkpoint 4: Supabase Auth and Profile Manual Test

This script validates only the Supabase email/password authentication and `public.profiles` vertical slice. It does not validate domain entities, quotas, media, or subscriptions.

## Local configuration

Run the app with local, non-committed Dart defines. Do not put real values in tracked files, screenshots, logs, or issue comments.

```powershell
flutter devices
$bwDeviceId = Read-Host 'Physical Android device ID from flutter devices'
flutter run -d "$bwDeviceId" `
  "--dart-define=SUPABASE_URL=<Broker-Wallet-project-URL>" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=<Broker-Wallet-publishable-key>" `
  --dart-define=USE_SUPABASE_AUTH=true
```

Use only the Supabase project URL and publishable key. Never use `SUPABASE_SECRET_KEY`, `service_role`, or a JWT secret in Flutter.

The mobile callback URI is:

```text
brokerwallet://auth/callback
```

The user has already configured **Authentication -> URL Configuration -> Additional Redirect URLs** with exactly `brokerwallet://auth/callback` and inspected the Confirm signup template. Treat those as user-reported assumptions; do not change hosted settings during this gate. Email confirmation must be enabled. Use URL and publishable key values from the same Broker Wallet project and a fresh testing email. Do not apply SQL, stage, commit, delete users, or start domain migration.

Android declares the `brokerwallet` scheme with host `auth` in `android/app/src/main/AndroidManifest.xml`. iOS declares the same `brokerwallet` scheme in `ios/Runner/Info.plist`. `supabase_flutter` 2.17.2 automatically observes mobile deep links and consumes auth callbacks through `getSessionFromUrl`; the app does not add a parallel listener or parse/store access or refresh tokens.

Android's MainActivity sets `flutter_deeplinking_enabled=false`; iOS sets `FlutterDeepLinkingEnabled=false`. Existing Google and Broker Wallet schemes remain registered. Both initial signup and signup-confirmation resend pass `SupabaseConfig.authCallbackUri` as `emailRedirectTo`. Fully rebuild with the defines above; hot reload does not update native settings or compile-time defines.

The real route is `EmailVerificationView -> AuthViewModel -> AuthRepository`. It observes auth-state updates and also polls every five seconds. Auth notifications, polling, manual checks, and already-verified resend results share one completion guard. The separately existing `EmailVerificationViewModel` is not the routed screen's controller.

## Test cases

### 1. Fresh signup

1. Start the app with the three Dart defines above.
2. Open Sign up.
3. Enter a new email, a valid password, and a display name.
4. Submit the form.
5. Confirm the app opens the email-verification route and does not enter the authenticated home route before confirmation.

### 2. Check `auth.users`

In the Supabase dashboard, open Authentication and locate the new test email. Confirm one `auth.users` row exists.

Do not copy or expose the password, access token, refresh token, or JWT.

### 3. Check `public.profiles`

Using **Table Editor -> public -> profiles**, locate the new user's row. Confirm one row exists and its name/email match the signup values. Before confirmation, `is_email_verified` should be false. Use no SQL for this gate.

### 4. Confirm identity equality

Compare the two UUID values:

```text
auth.users.id == public.profiles.id
```

They must be identical. There must be no Firebase UID or mapping row involved.

### 5. Open the confirmation email

Open the confirmation email on the same phone and app installation used for signup. Tap its link. Do not share the link, authorization code, or session objects. Use the most recent email if you explicitly tested resend.

### 6. Detect confirmation in the app

Tap the confirmation link. Confirm the OS opens Broker Wallet through `brokerwallet://auth/callback`. The Supabase SDK should consume the callback and restore the session. On the email-verification screen, wait for the automatic check or tap the manual verification action. Confirm the app detects the confirmed email without requiring Firebase Auth.

### 7. Profile loads

Confirm the app navigates to the home route and the authenticated profile name/email are loaded from `public.profiles`.

In the debug console, auth-state profile resolution emits exactly one source message per resolution:

- `Supabase profile source: database` means a non-null profile was read from the database (`PROFILE_DB_LOADED`).
- `Supabase profile source: auth metadata fallback` means the row was absent or its read failed (`AUTH_METADATA_FALLBACK`).

The fallback preserves auth-state delivery when the profile is temporarily unavailable; it is not a successful profile test. Require the database message for this test session, matching Dashboard UUID/name/email, and `public.profiles.is_email_verified=true` after confirmation. A visible Home screen alone does not pass. Default SDK callback message `handle deeplink uri` only proves processing began. Do not enable FINEST logging or log keys, passwords, tokens, full callback URLs, or session objects.

### 8. Close the app completely

Terminate the app process. Do not log out.

### 9. Restore the session

Start the app again with the same Dart defines. Confirm the Supabase session is restored from secure device storage and the app reaches the authenticated route without a new login.

### 10. Log out

Use the app's logout action.

### 11. Confirm unauthenticated routing and cache cleanup

Confirm the app returns to the welcome/unauthenticated route. Confirm reopening the app does not restore the previous profile after logout.

### 12. Log in again

Use the same email and password. Confirm login succeeds after email confirmation.

### 13. Confirm stable identity

Confirm the loaded profile has the same UUID as before and that it still equals `auth.users.id`. Do not expect a new profile row.

### 14. Edit an allowed profile field

Change only the display name through Edit Profile. Save without selecting an image or changing email/phone.

Confirm the name changed in `public.profiles` and survives reopening Profile. Confirm `id`, `email`, verification flags, and `deleted_at` remain unchanged. Server-maintained `version` and `updated_at` may legitimately advance.

## Expected result

Cases 1 through 14 pass for the auth/profile slice. Domain repositories and Firebase-backed features remain outside this checkpoint and are not expected to work as Supabase-native operations yet.

## Cleanup

Preserve the test account and report results. No account deletion, hosted mutations by the agent, SQL, staging, commits, or domain migration are authorized during this gate. Checkpoint 4 remains pending until the human completes the real device test.
