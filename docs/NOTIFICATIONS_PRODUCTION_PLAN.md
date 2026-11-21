# Notifications — production plan (final, 2026-11-20)

Source: the owner's audit
`BROKER_WALLET_NOTIFICATIONS_PRODUCTION_AUDIT_PLAN_2026-11-20.md`. Every
code-level finding in that audit was checked against this checkout and
confirmed. This file is that plan with the owner's decisions applied. Where the
two disagree, this file wins.

## Owner decisions (2026-11-20)

1. The **Status changes** (`statusReminders`) and **App updates**
   (`systemUpdates`) settings are removed.
2. These settings stay, with short descriptions:
   - Matches
   - Request reminders
   - Offer reminders
   - Plan alerts
   - Push
   - the master switch
3. The "push delivery is not configured yet" card is removed from the settings
   screen. Until N3, the Push switch only records the preference.
4. The **`system` notification category is dropped entirely**:
   - no maintenance, update or system notices
   - the first real event in N2 is an own-account request or offer reminder
   - the "App maintenance and updates" row of the audit's event catalogue is
     gone

## Architecture (unchanged from the audit)

- **Postgres `public.notifications`** is the source of truth. Push is only a
  transport and can be lost.
- **Events:** only a trusted backend (Edge Function plus Cron) creates them,
  with an idempotent event key. Flutter never inserts rows or chooses
  recipients.
- **Delivery:** a durable outbox with retries.
- **Push provider (owner decision, 2026-11-20):** Firebase Cloud Messaging
  HTTP v1, sent by a Supabase Edge Function. Android goes through FCM, iOS
  through APNs. No OneSignal.
- **Single Active Device:** checked when the device registers and again at
  send time. Each push targets one FCM token bound to the active app session.
- **Matching:** within the user's own account only. Never across accounts.

## Phases

| Phase | Scope | Gate |
|---|---|---|
| N0 | Choose the push provider. Define the reminder rule, retention and timezone. | Owner decision |
| N1 | Settings cleanup and inbox correctness. Client only: no SQL, no vendor. | Owner checks it on a device |
| N2 | Staging SQL: `event_key` dedupe, `(recipient_id, created_at desc, id desc)` index, delivery-jobs outbox, atomic session-gated preferences patch RPC. The create-event function rejects `system`, and the `system` enum value is retired with a reviewed migration. | Separate approval |
| N3 | Remote push: SDK, trusted registration endpoint, send-time session check. | Physical Android and iPhone |
| N4 | Business alerts: reminders first, then own-account matching. Plan alerts only after real entitlements exist. Media and Toolkit failures stay in-app. | Separate approval |
| N5 | Release acceptance: security, reliability, AR/EN, accessibility, privacy. | Release checklist |

## N1 — what changed (source, 2026-11-20)

- **Settings screen**
  - Two switches and the card are removed.
  - Five switches plus the master switch remain, each with a short Arabic and
    English description.
  - The view model uses one key list for initial values, load and save, so
    `planAlerts` now persists.
  - Saves run one after another and write through `updateUserPreferences`,
    which merges the change and never rewrites the whole profile.
  - A failed save puts the switch back. Without a loaded profile, nothing
    pretends to save.
- **Model and repository**
  - `system` is removed from the client enum.
  - Rows with an unknown category, a missing time or a missing id are skipped,
    not shown as reminders or as "now".
  - Paging uses a keyset on `(created_at, id)`.
  - The unread badge always comes from an exact server count. Realtime only
    signals that the count must be read again.
- **Inbox view model**
  - An account generation guard drops answers that belong to an earlier
    account.
  - Live rows and paged rows are merged with deduplication, so a live event no
    longer drops loaded pages.
  - The first page after the live feed includes every row tied at the boundary
    timestamp.
  - `hasMore` is tracked.
  - Offline, no feed is opened and no spinner is left on screen.
  - A failed refresh or failed paging is reported, with a retry.
  - A swipe-delete is optimistic and rolls back if the server refuses it.
  - Mark-read errors no longer escape as unhandled errors.
- **Inbox screen**
  - Offline and failure states each show a Retry button instead of "all caught
    up".
  - A retry footer appears when an older page fails.
  - Taps go only to a fixed allowlist, built from UUID-validated ids:
    - match → `/match-details`
    - reminder → Offer or Request details
    - plan → `/my-plan`
  - The stored `action_route`, `data['route']` and `storeUrl` are never
    followed.

Status: **CODE ONLY.** Tests and analysis were not run by the agent; the owner
runs them. No SQL, hosted, vendor or device change was made.

Known limits that remain until N2:

- Preferences use read-merge-write, not an atomic RPC.
- The live feed and the unread count still use two Realtime channels.
- The database still accepts `system` rows. The client hides them.

## N2 + N3 — follow-up reminders and FCM push (source, 2026-11-20)

Approved design (owner, 2026-11-20):

- Supabase stays the only authority for auth and business data. It runs
  Postgres, Cron, Edge Functions and Realtime.
- FCM HTTP v1 carries the push: Android today, iOS through APNs later.
- The user picks the follow-up date and time.

**Status: SOURCE ONLY.** No hosted change was made: no migration applied, no
function deployed, no secret, no cron job. The agent did not run the Flutter
tests or analyze.

### Read-only check of the connected services

| Item | Finding |
|---|---|
| Supabase project | `broker-wallet` (`rbvcnvqpdqrhywcgxkne`), ACTIVE_HEALTHY |
| Hosted migrations | Identical to the repo up to `20261019100000` |
| `notifications` / `push_devices` | 0 rows each, no `system` rows |
| Extensions | `pg_cron` and `pg_net` not installed; Vault installed, 0 secrets |
| Edge Functions | None |
| Android Firebase file | Project `broker-wallet` (285578142613), package `com.nmodigital.brokerwallet` |
| iOS | Old project `broker-wallet-app`, bundle `com.example.broker-wallet` |
| Firebase MCP | Failed to connect; the Firebase console was not read |

### Server (N2)

Everything below is in
`supabase/migrations/20261120130000_follow_up_reminders_and_push_delivery.sql`.

**New and changed tables**

- `follow_up_reminders`
  - One row per Request or Offer.
  - `generation` goes up on every reschedule.
  - Status is `scheduled`, `sent` or `cancelled`.
  - Clients can read only their own rows (RLS plus the app-session gate) and
    cannot write.
- `notifications`
  - New `event_key`, unique per recipient: `follow_up:<reminder>:<generation>`.
    Each schedule makes at most one inbox row.
  - New keyset index on `(created_at desc, id desc)`.
  - `system` is refused.
- `notification_delivery_jobs`
  - One job per inbox row, with lease, attempts, backoff and a cap of 5.
  - Stores fixed error codes only.
  - No client grant.
- `push_devices.session_id`: binds each token to the app session that
  registered it.

**Client RPCs.** All require the current app session and check that the
caller owns the record.

- `set_follow_up_reminder(type, id, remind_at)`
  - Creates or moves the reminder, between 1 minute and 366 days ahead.
  - A missing, deleted or other user's record all return the same answer.
- `cancel_follow_up_reminder(type, id)`
- `register_push_device(token, platform, locale)`
  - Binds the token to the caller's current session.
  - Deletes the account's other devices.
- `unregister_push_device(token)`

**Server functions (service_role only)**

- `fire_due_follow_up_reminders`
  - Locks rows with `SKIP LOCKED`.
  - Re-checks the owner and soft delete.
  - Writes the inbox row and its delivery job.
- `claim_push_delivery_jobs`. At send time it re-checks:
  - the inbox row still exists and is unread
  - the preferences
  - the device belongs to the account's **active** session of a live auth
    session (Single Active Device)
- `complete_push_delivery_job`
- `prune_push_delivery_jobs` (keeps 30 days)

**Preference policy.** The inbox row is always created, because the user asked
for it. Push needs all three switches on:

- `notificationsEnabled`
- `push`
- `requestReminders` or `offerReminders`

**Edge Function `supabase/functions/push-dispatch`**

- Sends with FCM HTTP v1, using an OAuth service-account JWT signed with RS256
  through WebCrypto. It has no npm or Deno imports.
- Accepts only calls that carry the scheduler secret.
- Handles FCM answers:

| FCM answer | Action |
|---|---|
| `UNREGISTERED`, `SENDER_ID_MISMATCH` or 400 | Delete the device |
| 429 or 5xx | Retry |
| 401 | Refresh the OAuth token once |

- The text is generic and localized. It never contains a client, phone, price
  or place.
- The payload carries ids only.

**Scheduler** (`supabase/deploy/notifications_n2_schedule.sql`, not a
migration):

- Every minute, pg_cron turns due reminders into inbox rows using plain SQL.
- A second cron job calls `push-dispatch` every minute.
- A daily job prunes old delivery jobs.
- The URL and the secret are read from Vault.

### App (N3)

- `firebase_messaging: ^16.0.0` is added. It should resolve to 16.5.0 against
  the locked `firebase_core` 4.13.0.
- `PushMessagingService` with `FirebasePushPlatform`:
  - Android only (`iosPushReady = false`).
  - Starts before `runApp`, without waiting.
  - Registers the token only after the server confirms the app session.
  - Registers again after a new sign-in, a language change or a token
    refresh, with a bounded number of retries.
  - Notification messages only, so there is no Dart background isolate.
- **Foreground:** the unread count refreshes. No second banner is shown.
- **Tap from background or closed app:** opens the inbox, but only once the
  router is on a protected screen.
- **Android:**
  - Channel `follow_up_reminders`, named in Arabic or English.
  - A monochrome status-bar icon.
- **Permission** is asked only after the user sets a reminder. If refused, the
  inbox still works.
- **Follow-up section** on Request and Offer Details:
  - Set, Change and Cancel.
  - Date and time pickers.
  - Keeps the same height while loading, offline and on error.
  - Arabic and English.
- **Inbox:** follow-up rows are shown in the app language, and a tap opens the
  record through the validated route.

### Matching and plan notifications

- There is no verified matching engine and no authoritative entitlement
  events (RevenueCat is not live), so nothing produces match or plan
  notifications.
- Their switches stay as preferences only.

### Conflicts with the earlier Firebase removal

1. **Firestore quota code: solved in source on 2026-11-20.** All five legacy
   accesses now go through `legacyQuotaFirestore()`, which fails as before, so
   nothing reaches Firestore. The original notes follow.
   **Original finding:**
   - Before this change, Dart never called `Firebase.initializeApp()`. The
     four Toolkit usage gates and `QuotaHelper` failed on `[core/no-app]` and
     let everything through.
   - Starting Firebase for FCM wakes them up. They then read and write
     `users/{supabase-uid}` in the **new** project's Firestore.
   - Until those calls are removed (`LEGACY_FIRESTORE_QUOTA_REMOVAL_PLAN.md`),
     keep `broker-wallet` without a Firestore database, or with deny-all
     rules.
2. **FCM network traffic.** FCM's native networking (token, delivery) does not
   pass through `AppAccessPolicy`. Only the Supabase registration call is
   guarded.
3. **iOS** now starts the `broker-wallet` project natively (2026-11-21), the
   same project as Android. Delivery waits for the APNs key and an
   Apple-signed build (checklist below).

### Deploy runbook (each step needs the owner's approval)

1. The owner runs `flutter pub get`, the tests, and the Samsung check of the
   in-app parts.
2. On the hosted database, which is **production** (the only project, real
   accounts), run `supabase/validation/follow_up_reminders_validation.sql`.
   It includes the migration with `\ir` and always rolls back. Then apply the
   migration as its own approved step.
3. In Firebase `broker-wallet`, create a service-account key for FCM. Never
   commit it.
4. Set the secrets and deploy the function:
   - `supabase secrets set FCM_SERVICE_ACCOUNT_JSON=...`
   - `supabase secrets set PUSH_DISPATCH_SECRET=...`
   - `supabase functions deploy push-dispatch --no-verify-jwt`
5. Create the Vault secrets `bw_push_dispatch_url` and
   `bw_push_dispatch_secret`, then run
   `supabase/deploy/notifications_n2_schedule.sql`.
6. On the Samsung, set a reminder 3 minutes ahead and check:
   - The inbox row appears.
   - The push arrives in the foreground, in the background and when the app
     is closed.
   - A tap opens the inbox, and from there the record.
   - After signing in on another phone, the first phone gets nothing.
   - With Push OFF, the inbox row appears but no push.

### iOS / APNs checklist

**Done in code (2026-11-21, source only, uncommitted, not built):**

- Bundle ID `com.nmodigital.brokerwallet` (Runner Debug/Release/Profile) and
  `com.nmodigital.brokerwallet.RunnerTests`. No `com.example.broker-wallet` is
  left in the Xcode project.
- The owner registered the iOS app in Firebase `broker-wallet`. Its
  `GoogleService-Info.plist` is installed in `ios/Runner/`:
  - PROJECT_ID `broker-wallet` and GCM_SENDER_ID `285578142613` (the same as
    Android), BUNDLE_ID as above, IS_GCM_ENABLED true.
  - It is now **referenced in the Xcode project and its Resources phase**.
    Before, the old plist sat in the folder unreferenced, so it was never
    bundled.
  - The old plist (`broker-wallet-app`) is backed up at
    `%USERPROFILE%\BrokerWallet-Backups\2026-11-21-ios-firebase\`.
- `ios/Runner/Runner.entitlements` with `aps-environment = development`, set
  as `CODE_SIGN_ENTITLEMENTS` for all three Runner configurations.
  - With automatic signing, App Store / TestFlight exports are re-signed
    with `production`.
- `Info.plist`: `FirebaseAppDelegateProxyEnabled` is now **true**; it was
  false. The Firebase Flutter docs say method swizzling "is required" on
  Apple platforms.
  - `UIBackgroundModes` already had `fetch` and `remote-notification`.
  - FCM auto-init stays at its default (on), because firebase_messaging
    registers for APNs at launch only while auto-init is on. The token still
    reaches our server only after sign-in and permission, as on Android.
- `AppDelegate.swift`: unchanged. It already calls `FirebaseApp.configure()`
  once.
  - firebase_messaging 16.5.0 itself forwards the APNs token, sets the
    notification-centre delegate, and calls `registerForRemoteNotifications`
    (read in the plugin source).
  - Dart `Firebase.initializeApp()` attaches to the native default app;
    firebase_core 4.13.0 reads `[FIRApp allApps]`, so there is no second
    configure.
- Dart:
  - `iosPushReady = true`.
  - `FirebasePushPlatform.token()` waits for the APNs token on iOS (0.5 s,
    1 s, 2 s), as FCM requires. With none, it throws `ApnsTokenUnavailable`,
    and the push service's existing retries, the token-refresh listener and
    the next sign-in try again. Nothing is registered without a token.
  - Permission (asked when a reminder is set), the foreground count refresh,
    opening the inbox from a tap (`onMessageOpenedApp` / `getInitialMessage`)
    and the server-side Arabic/English text are shared with Android.
  - The server already sends `apns-priority: 10` and `sound: default`.
- Tests: `test/notifications/ios_push_config_test.dart` reads the real project
  files and unit-tests the APNs wait.

**BLOCKED_EXTERNAL (owner: Apple Developer membership, D-U-N-S pending):**

1. Apple Developer (paid organization membership):
   - App ID `com.nmodigital.brokerwallet` with **Push Notifications**.
   - An **APNs Authentication Key (.p8)**, with its **Key ID** and the **Team
     ID**.
2. Firebase `broker-wallet` → Project settings → Cloud Messaging → iOS app →
   upload the .p8 with its Key ID and Team ID.
3. On a Mac with Xcode, in `ios/Runner.xcworkspace` → Runner → Signing &
   Capabilities:
   - choose the team (this sets `DEVELOPMENT_TEAM`)
   - check that **Push Notifications** and **Background Modes → Remote
     notifications** show as enabled (both are already in the files)
   - `pod install` runs on the first build
4. A free personal team cannot sign the Push Notifications entitlement, so a
   real-device build fails until the membership exists. Simulator builds do
   not need it, but the Simulator is not proof of APNs delivery.
5. Google Maps: if the iOS Maps API key is restricted by bundle ID, add
   `com.nmodigital.brokerwallet` in Google Cloud.
6. Test on a real iPhone: permission prompt, push in the foreground,
   background and closed states, a tap opening the inbox, Arabic and English
   text, sign-out / other-device silence, and Android unchanged.

**Backlog (not changed):**

- `firebase.json`'s `flutter` section still names `broker-wallet-app`. No
  `lib/firebase_options.dart` exists, and nothing reads that section at
  build or run time.
- `Info.plist` keeps a Google Sign-In URL scheme for client
  `460721646511-…`; `google_sign_in` is not used in `lib/`.
