import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_recorder.dart';

/// The Scanner's boundary to the free-plan limit.
///
/// Today the limit lives in the legacy Firestore `users/{uid}` document
/// (`plan`, `lifetimeCreated.scanner`, free limit 3). That document is NOT
/// authoritative for a Supabase-authenticated account and the client can write
/// to it, so this gate is a courtesy, not entitlement enforcement: an
/// unreachable or missing document lets the scan through (the same fail-open
/// the other tools have), and nothing here may be presented as secure
/// enforcement. When the server-authoritative quota exists, replace this one
/// class; the Scanner calls nothing else.
abstract interface class ScannerUsageGate implements ScannerUsageRecorder {
  /// Whether [userId] may start another scan; shows the plan-limit dialog and
  /// returns false when the limit is reached.
  Future<bool> allowNewScan(BuildContext context, String userId);
}

/// The legacy Firestore implementation, preserving the product's existing limit.
class LegacyFirestoreScannerUsageGate implements ScannerUsageGate {
  const LegacyFirestoreScannerUsageGate();

  static const String section = 'scanner';

  @override
  Future<bool> allowNewScan(BuildContext context, String userId) {
    return QuotaHelper.checkAndWarnQuota(
      context: context,
      uid: userId,
      section: section,
      toolName: section,
    );
  }

  @override
  Future<void> recordScan(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort, as before: the scan is already stored and must not fail
      // because the legacy counter could not be written.
    }
  }
}
