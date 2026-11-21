import 'package:cloud_firestore/cloud_firestore.dart';

/// The legacy Firestore quota document (`users/{uid}`: `plan`, `counts`,
/// `lifetimeCreated`) is not connected in this app.
///
/// Firebase is initialized for one purpose only: Firebase Cloud Messaging
/// (push, project `broker-wallet`). Before that, Dart never initialized
/// Firebase, so `FirebaseFirestore.instance` failed with `[core/no-app]` and
/// the legacy Toolkit usage gates and [QuotaHelper] took their existing
/// fail-open paths. Initializing Firebase for FCM must not silently connect
/// them to the new project's Firestore: they would read and write counters in
/// a store that is not authoritative for a Supabase account, and could start
/// showing the free-plan dialog from data nobody owns.
///
/// So every legacy quota access goes through this function, which fails the
/// same way the app failed before. Nothing about the quota changes: no limit
/// is added or removed, no subscription authority moves, and the gates keep
/// their code for the day a server-authoritative quota replaces this store
/// (docs/LEGACY_FIRESTORE_QUOTA_REMOVAL_PLAN.md).
FirebaseFirestore legacyQuotaFirestore() =>
    throw const LegacyQuotaStoreDisconnected();

/// Thrown instead of returning a Firestore instance; the legacy callers
/// already catch every error.
class LegacyQuotaStoreDisconnected implements Exception {
  const LegacyQuotaStoreDisconnected();

  @override
  String toString() =>
      'LegacyQuotaStoreDisconnected: Firebase is used for push only';
}
