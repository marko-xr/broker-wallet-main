/// Count Reconciliation Service
///
/// This service ensures quota counts always match reality by:
/// - Calling reconcileUserCounts Cloud Function on login
/// - Providing manual reconciliation for admins
/// - Detecting and fixing count discrepancies

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

/// Result of count reconciliation
class ReconciliationResult {
  const ReconciliationResult({
    required this.success,
    required this.counts,
    required this.plan,
    required this.discrepanciesFound,
    required this.discrepancies,
    required this.message,
  });

  final bool success;
  final Map<String, int> counts;
  final String plan;
  final int discrepanciesFound;
  final List<CountDiscrepancy> discrepancies;
  final String message;

  factory ReconciliationResult.fromMap(Map<String, dynamic> map) {
    final countsData = map['counts'] as Map<String, dynamic>?;
    final counts = <String, int>{};
    if (countsData != null) {
      countsData.forEach((key, value) {
        counts[key] = (value as num).toInt();
      });
    }

    final discrepanciesData = map['discrepancies'] as List?;
    final discrepancies = <CountDiscrepancy>[];
    if (discrepanciesData != null) {
      for (final item in discrepanciesData) {
        if (item is Map<String, dynamic>) {
          discrepancies.add(CountDiscrepancy.fromMap(item));
        }
      }
    }

    return ReconciliationResult(
      success: map['success'] as bool? ?? false,
      counts: counts,
      plan: map['plan'] as String? ?? 'free',
      discrepanciesFound: map['discrepanciesFound'] as int? ?? 0,
      discrepancies: discrepancies,
      message: map['message'] as String? ?? '',
    );
  }
}

/// Individual count discrepancy
class CountDiscrepancy {
  const CountDiscrepancy({
    required this.section,
    required this.oldCount,
    required this.realCount,
    required this.difference,
  });

  final String section;
  final int oldCount;
  final int realCount;
  final int difference;

  factory CountDiscrepancy.fromMap(Map<String, dynamic> map) {
    return CountDiscrepancy(
      section: map['section'] as String,
      oldCount: (map['oldCount'] as num).toInt(),
      realCount: (map['realCount'] as num).toInt(),
      difference: (map['difference'] as num).toInt(),
    );
  }

  @override
  String toString() =>
      '$section: $oldCount → $realCount (${difference > 0 ? '+' : ''}$difference)';
}

/// Service for reconciling quota counts
class CountReconciliationService {
  CountReconciliationService({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Reconcile counts for the authenticated user
  ///
  /// This should be called:
  /// - On first login after app reinstall
  /// - After subscription plan changes
  /// - When counts seem incorrect
  ///
  /// Returns reconciliation result with fixed counts
  Future<ReconciliationResult> reconcileUserCounts({String? uid}) async {
    final callable = _functions.httpsCallable(
      'reconcileUserCounts',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 60),
      ),
    );

    try {
      final response = await callable.call(uid != null ? {'uid': uid} : null);
      final data = Map<String, dynamic>.from(response.data as Map);
      return ReconciliationResult.fromMap(data);
    } on FirebaseFunctionsException catch (error) {
      throw _mapError(error);
    }
  }

  /// Check if reconciliation is needed
  ///
  /// Returns true if:
  /// - User has never reconciled
  /// - Last reconciliation was > 1 hour ago
  /// - User just upgraded/downgraded
  Future<bool> needsReconciliation({
    required DateTime? lastReconciliation,
    required DateTime? lastPlanChange,
  }) async {
    // Always reconcile if never done
    if (lastReconciliation == null) return true;

    // Reconcile if > 1 hour since last reconciliation
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    if (lastReconciliation.isBefore(oneHourAgo)) return true;

    // Reconcile if plan changed after last reconciliation
    if (lastPlanChange != null && lastPlanChange.isAfter(lastReconciliation)) {
      return true;
    }

    return false;
  }

  /// Map Firebase Functions errors to typed exceptions
  Exception _mapError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return const ReconciliationAuthException(
          'Please sign in to reconcile counts.',
        );
      case 'permission-denied':
        return const ReconciliationPermissionException(
          'You can only reconcile your own counts.',
        );
      case 'not-found':
        return const ReconciliationNotFoundException(
          'User profile not found.',
        );
      default:
        return ReconciliationException(
          error.message ?? 'Failed to reconcile counts.',
        );
    }
  }
}

/// Exception thrown during reconciliation
class ReconciliationException implements Exception {
  const ReconciliationException(this.message);
  final String message;

  @override
  String toString() => 'ReconciliationException: $message';
}

/// Exception for authentication errors
class ReconciliationAuthException implements Exception {
  const ReconciliationAuthException(this.message);
  final String message;

  @override
  String toString() => 'ReconciliationAuthException: $message';
}

/// Exception for permission errors
class ReconciliationPermissionException implements Exception {
  const ReconciliationPermissionException(this.message);
  final String message;

  @override
  String toString() => 'ReconciliationPermissionException: $message';
}

/// Exception when user not found
class ReconciliationNotFoundException implements Exception {
  const ReconciliationNotFoundException(this.message);
  final String message;

  @override
  String toString() => 'ReconciliationNotFoundException: $message';
}
