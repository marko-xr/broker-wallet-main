import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:broker_wallet/src/services/quota_helper.dart';

/// Records that a combine was completed. One call is one combined PDF however
/// many files or pages went into it, and it is made only after the combined
/// file was stored, so a failed or cancelled combine never uses an allowance.
abstract interface class CombineUsageRecorder {
  Future<void> recordCombine(String userId);
}

/// The Combine tool's boundary to the free-plan limit.
///
/// Today the limit lives in the legacy Firestore `users/{uid}` document
/// (`plan`, `lifetimeCreated.combinePdfs`). That document is NOT authoritative
/// for a Supabase-authenticated account and the client can write to it, so this
/// gate is a courtesy, not entitlement enforcement: an unreachable or missing
/// document lets the combine through (the same fail-open the other tools have)
/// and nothing here may be presented as secure enforcement. When the
/// server-authoritative quota exists, replace this one class; the Combine tool
/// calls nothing else.
abstract interface class CombineUsageGate implements CombineUsageRecorder {
  /// Whether [userId] may start another combine; shows the plan-limit dialog and
  /// returns false when the limit is reached.
  Future<bool> allowNewCombine(BuildContext context, String userId);
}

/// The legacy Firestore implementation, preserving the product's existing limit.
class LegacyFirestoreCombineUsageGate implements CombineUsageGate {
  const LegacyFirestoreCombineUsageGate();

  static const String section = 'combinePdfs';

  @override
  Future<bool> allowNewCombine(BuildContext context, String userId) {
    return QuotaHelper.checkAndWarnQuota(
      context: context,
      uid: userId,
      section: section,
      toolName: section,
    );
  }

  @override
  Future<void> recordCombine(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort, as before: the combined PDF is already stored and must
      // not fail because the legacy counter could not be written.
    }
  }
}
