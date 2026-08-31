import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to sync user quota counts with server-side data
/// This ensures quota limits cannot be bypassed by reinstalling the app
class QuotaSyncService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sync user's quota counts with actual Firestore data
  /// Should be called:
  /// - On user login
  /// - After app reinstall
  /// - When plan changes
  /// - Periodically to ensure accuracy
  Future<QuotaSyncResult> syncUserQuota() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to sync quota');
      }

      // 🔄 Syncing quota for user: ${user.uid} (log removed)

      // Call Cloud Function to sync counts
      final result = await _functions.httpsCallable('syncUserQuota').call();

      final data = result.data as Map<String, dynamic>;

      // ✅ Quota sync complete: ${data['message']} (log removed)
      // 📊 Updated counts: ${data['counts']} (log removed)

      return QuotaSyncResult.fromMap(data);
    } catch (e) {
      // ❌ Failed to sync quota: $e (log removed)
      throw Exception('Failed to sync quota: $e');
    }
  }

  /// Check if sync is needed (e.g., hasn't been done recently)
  /// This prevents unnecessary Cloud Function calls
  Future<bool> shouldSync() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // For now, always return true
      // You can add logic to check lastQuotaSync timestamp
      return true;
    } catch (e) {
      // Error checking sync status: $e (log removed)
      return true; // Err on the side of syncing
    }
  }
}

/// Result of quota sync operation
class QuotaSyncResult {
  final bool success;
  final Map<String, int> counts;
  final String plan;
  final dynamic limit; // Can be int or 'unlimited'
  final List<String> sectionsAtLimit;
  final String message;

  QuotaSyncResult({
    required this.success,
    required this.counts,
    required this.plan,
    required this.limit,
    required this.sectionsAtLimit,
    required this.message,
  });

  factory QuotaSyncResult.fromMap(Map<String, dynamic> map) {
    return QuotaSyncResult(
      success: map['success'] as bool,
      counts: Map<String, int>.from(map['counts'] as Map),
      plan: map['plan'] as String,
      limit: map['limit'],
      sectionsAtLimit: List<String>.from(map['sectionsAtLimit'] as List),
      message: map['message'] as String,
    );
  }

  bool isAtLimit(String section) {
    return sectionsAtLimit.contains(section);
  }

  int getCount(String section) {
    return counts[section] ?? 0;
  }
}
