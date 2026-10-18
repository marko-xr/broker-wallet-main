import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:broker_wallet/src/services/quota_helper.dart';

/// Records that a signed document was saved. One call is one signed document
/// however many items it carries, and it is made only after the document was
/// stored, so a failed or cancelled save never uses an allowance.
abstract interface class SignatureUsageRecorder {
  Future<void> recordSignedDocument(String userId);
}

/// The Signature tool's boundary to the free-plan limit.
///
/// Today the limit lives in the legacy Firestore `users/{uid}` document (`plan`,
/// `lifetimeCreated.signature`). That document is NOT authoritative for a
/// Supabase-authenticated account and the client can write to it, so this gate
/// is a courtesy, not entitlement enforcement: an unreachable or missing
/// document lets the save through (the same fail-open the other tools have) and
/// nothing here may be presented as secure enforcement. When the
/// server-authoritative quota exists (the later checklist milestone), replace
/// this one class; the Signature tool calls nothing else.
abstract interface class SignatureUsageGate implements SignatureUsageRecorder {
  /// Whether [userId] may save another signed document; shows the plan-limit
  /// dialog and returns false when the limit is reached.
  Future<bool> allowNewSignedDocument(BuildContext context, String userId);
}

/// The legacy Firestore implementation, preserving the product's existing limit
/// under the same `signature` section the tool always used.
class LegacyFirestoreSignatureUsageGate implements SignatureUsageGate {
  const LegacyFirestoreSignatureUsageGate();

  static const String section = 'signature';

  @override
  Future<bool> allowNewSignedDocument(BuildContext context, String userId) {
    return QuotaHelper.checkAndWarnQuota(
      context: context,
      uid: userId,
      section: section,
      toolName: section,
    );
  }

  @override
  Future<void> recordSignedDocument(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort, as before: the signed document is already stored and must
      // not fail because the legacy counter could not be written.
    }
  }
}
