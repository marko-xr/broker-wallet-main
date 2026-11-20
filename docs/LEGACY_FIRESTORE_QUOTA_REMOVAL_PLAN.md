# Legacy Firestore quotas — removal plan (proposal, 2026-11-20)

Status: **PLAN ONLY.** Nothing in this file is implemented. No SQL, hosted,
Firebase or device change was made. Each phase needs the owner's approval.

Owner architecture (2026-11-20):

- Supabase is the only backend for auth, data, quotas and reminders.
- The new Firebase project (NMO Digital) is used only for Android push (FCM).
- OneSignal manages push delivery to Android and iOS.
- The old Firebase project `broker-wallet-app` was for experiments. It is not
  used in production. It and its hosted files are not deleted.

## 1. What still uses Firebase (source review, 2026-11-20)

| Code | Firebase use |
|---|---|
| `lib/src/services/quota_helper.dart` `checkAndWarnQuota` | Reads Firestore `users/{uid}` (`plan`, `lifetimeCreated`). Free limit 3 is hard-coded. |
| `scanner_usage_gate.dart`, `combine_usage_gate.dart`, `image_pdf_usage_gate.dart`, `signature_usage_gate.dart` | Check through `QuotaHelper`, then write `counts` and `lifetimeCreated` with `FieldValue.increment` after the file is stored. |
| `lib/src/services/core_entity_quota_bridge.dart` | No Firebase. `canCreate` always returns true and `recordCreated` does nothing (Offers, Requests, Owners, Offices, Brokers, Watchmen, Quotations). |
| `pubspec.yaml` | `firebase_core`, `cloud_firestore` |
| `android/app/build.gradle` | `google-services` plugin, Firebase BoM, `firebase-firestore` |
| iOS | `FirebaseApp.configure()` in `AppDelegate.swift`, `GoogleService-Info.plist` (old project) |

No `firebase_auth`, `firebase_storage`, `cloud_functions` or
`firebase_messaging` remain.

## 2. The protection today is not real

Static reading shows that the Toolkit quota never blocks anything. This was
not checked at runtime.

1. Dart never calls `Firebase.initializeApp()`. `FirebaseFirestore.instance`
   is expected to throw `[core/no-app]`. `checkAndWarnQuota` catches every
   error and returns true.
2. `uid` is the Supabase user id. There is no Firebase Auth session, so Firestore
   rules that require auth would refuse the read. A missing document also
   returns true.
3. Offline, the check returns true by design (OFF-2b-2).
4. Core entities have no quota at all (`CoreEntityQuotaBridge`).

Removing the Firestore code therefore loses no working protection. Replacing it
with a **real** quota is new protection, not a migration of an existing one.

## 3. What Supabase already has

From `20260821000100_broker_wallet_baseline.sql`:

- `quota_section` enum covers all 11 sections: offers, requests, owners,
  offices, brokers, watchmen, quotations, scanner, signature, image_to_pdf,
  combine_pdfs.
- `plan_limits (plan_code, section, counter_basis, limit_value, reset_period)`.
  It has no seeded rows.
- `usage_counters (owner_id, section, current/lifetime/period counts)`.
- `revenuecat_entitlements` and `revenuecat_webhook_events`.
- Authenticated users have **SELECT only** on their own rows. There is no
  write grant and no quota RPC.

## 4. Target design

- **One authority.** Postgres decides. The client never writes a plan, a limit
  or a counter.
- **Plan.** It is derived on the server from active `revenuecat_entitlements`
  rows, and defaults to `free`. It is never taken from the profile or the
  client.
- **Core entities.** The limit is enforced in the same transaction that
  inserts the row (a `before insert` trigger or the existing create RPCs).
  The client cannot bypass it with a direct insert. The `lifetime_created`
  basis does not refund on delete.
- **Toolkit tools.** The work happens on the device, so the server can only
  authorize and count. Use an atomic
  `quota_reserve(section, request_id) → reservation` before the file is
  produced, then `quota_commit(reservation)` once it is stored. Expired,
  uncommitted reservations are released by a sweep. `request_id` makes retries
  idempotent. A modified client could skip local processing anyway, so this
  protects the business count, not the binary.
- **Session.** Every quota RPC checks `is_current_app_session` (Single Active
  Device).
- **Failure.** It is never fail-open. Server unreachable or refused → the action
  does not start, and the existing quota dialog or a retry message is shown.
  Offline behaviour is an owner decision (D-Q4).
- **UI.** The existing quota dialog, texts and screens stay. Only its data
  source changes.

## 5. Owner decisions needed (Q0)

- **D-Q1** Limits per plan and section (the current client hard-codes 3 for
  free).
- **D-Q2** Counter basis and reset period per section (lifetime, monthly, …).
- **D-Q3** The RevenueCat entitlement → `plan_code` mapping.
- **D-Q4** Offline Toolkit use: block, or allow a bounded offline allowance
  that is reconciled later. Today it is allowed without limit.
- **D-Q5** Existing Firestore counters are **not** migrated. The app is
  unreleased, and those counters are keyed by ids that never matched.

## 6. Phases

| Phase | Scope | Gate |
|---|---|---|
| Q0 | Decisions D-Q1..D-Q5 | Owner |
| Q1 | Migration: seed `plan_limits`; `quota_status`, `quota_reserve`, `quota_commit` RPCs; core-entity enforcement; pgTAP for limits, concurrency (two parallel reserves at limit-1), idempotent retry, cross-account isolation and the session gate. Run on local PGlite first, then rollback-only validation on hosted. | Separate approval before any hosted apply |
| Q2 | Dart: a Supabase quota repository behind `QuotaHelper` and `CoreEntityQuotaBridge`; the 4 Toolkit gates call reserve and commit; fail-closed; tests. The UI stays unchanged. | Owner runs tests and the device check |
| Q3 | Remove `cloud_firestore` from `lib/` and `pubspec.yaml`, `firebase-firestore` from Gradle, and the Firestore imports from tests. Keep `firebase_core`, the `google-services` plugin and `google-services.json` only if the chosen push SDK needs them (decided in notifications N3). | After Q2 is verified on a device |
| Q4 | iOS: `GoogleService-Info.plist` from the NMO Digital project together with the iOS Bundle ID change. Remove `FirebaseApp.configure()` if push on iOS needs no Firebase. | Separate iOS checkpoint |

## 7. Rules while this is pending

- Do not create a Firestore database or rules in the new NMO Digital Firebase
  project. Its only role is FCM.
- Do not convert any quota check to `return true` and do not remove the
  quota dialog.
- The old project `broker-wallet-app`, its `firebase.json`, `firestore.rules`,
  `storage.rules` and `functions/` stay untouched until the owner decides.
