import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:broker_wallet/src/services/quota_helper.dart';

/// Records that a PDF was made from pictures. One call is one stored PDF however
/// many pictures went into it, and it is made only after the PDF was saved, so a
/// failed, cancelled or discarded conversion never uses an allowance.
abstract interface class ImagePdfUsageRecorder {
  Future<void> recordConversion(String userId);
}

/// The Images to PDF tool's boundary to the free-plan limit.
///
/// Today the limit lives in the legacy Firestore `users/{uid}` document
/// (`plan`, `lifetimeCreated.imageToPdf`). That document is NOT authoritative
/// for a Supabase-authenticated account and the client can write to it, so this
/// gate is a courtesy, not entitlement enforcement: an unreachable or missing
/// document lets the conversion through (the same fail-open the other tools
/// have) and nothing here may be presented as secure enforcement. When the
/// server-authoritative quota exists, replace this one class; the tool calls
/// nothing else.
abstract interface class ImagePdfUsageGate implements ImagePdfUsageRecorder {
  /// Whether [userId] may start another conversion; shows the plan-limit dialog
  /// and returns false when the limit is reached.
  Future<bool> allowNewConversion(BuildContext context, String userId);
}

/// The legacy Firestore implementation, preserving the product's existing limit.
class LegacyFirestoreImagePdfUsageGate implements ImagePdfUsageGate {
  const LegacyFirestoreImagePdfUsageGate();

  static const String section = 'imageToPdf';

  @override
  Future<bool> allowNewConversion(BuildContext context, String userId) {
    return QuotaHelper.checkAndWarnQuota(
      context: context,
      uid: userId,
      section: section,
      toolName: section,
    );
  }

  @override
  Future<void> recordConversion(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort, as before: the PDF is already stored and must not fail
      // because the legacy counter could not be written.
    }
  }
}
