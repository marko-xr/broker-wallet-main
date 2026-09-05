import 'package:cloud_functions/cloud_functions.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';

/// Service to sync user quota counts with server-side data
/// This ensures quota limits cannot be bypassed by reinstalling the app
class QuotaSyncService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Sync user's quota counts with actual Firestore data
  /// Should be called:
  /// - On user login
  /// - After app reinstall
  /// - When plan changes
  /// - Periodically to ensure accuracy
  Future<QuotaSyncResult> syncUserQuota() async {
    try {
      final currentUserId =
          RepositoryProvider.instance.authRepository.currentUserId;
      if (currentUserId == null) {
        throw Exception('User must be logged in to sync quota');
      }

      // Call Cloud Function to sync counts
      final result = await _functions.httpsCallable('syncUserQuota').call();

      final data = result.data as Map<String, dynamic>;

      return QuotaSyncResult.fromMap(data);
    } catch (e) {
      throw Exception('Failed to sync quota: $e');
    }
  }

  /// Check if sync is needed (e.g., hasn't been done recently)
  /// This prevents unnecessary Cloud Function calls
  Future<bool> shouldSync() async {
    try {
      final currentUserId =
          RepositoryProvider.instance.authRepository.currentUserId;
      if (currentUserId == null) return false;

      // For now, always return true
      // You can add logic to check lastQuotaSync timestamp
      return true;
    } catch (e) {
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
