/// Quota Service - Server-Enforced Item Creation with Quota Management
///
/// This service provides a secure, server-backed mechanism for creating items
/// with automatic quota enforcement. All item creation goes through Cloud Functions
/// to prevent client-side bypass of quota limits.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

/// Result of adding an item with quota enforcement
class AddItemResult {
  const AddItemResult({
    required this.itemId,
    required this.section,
    required this.currentCount,
    required this.quotaLimit,
    required this.replayed,
  });

  /// The ID of the created item
  final String itemId;

  /// The section where item was created
  final String section;

  /// Current count of items in this section after creation
  final int? currentCount;

  /// Quota limit for this section (null for premium users)
  final int? quotaLimit;

  /// Whether this was a replayed idempotent request
  final bool replayed;

  /// Remaining quota slots
  int? get remainingQuota {
    if (quotaLimit == null || currentCount == null) return null;
    return (quotaLimit! - currentCount!).clamp(0, quotaLimit!);
  }
}

/// Service for managing quota-enforced item creation
class QuotaService {
  QuotaService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  /// Add an item with server-side quota enforcement
  ///
  /// This method calls the Cloud Function `addItemWithQuota` which:
  /// - Validates authentication
  /// - Checks quota limits (5 items for free plan)
  /// - Creates the item atomically
  /// - Updates user counts
  /// - Records audit logs
  /// - Supports idempotency via [idempotencyToken]
  ///
  /// Throws [QuotaExceededException] when quota is reached
  /// Throws [AuthRequiredException] if user is not authenticated
  /// Throws [BadRequestException] for invalid input
  /// Throws [MissingProfileException] if user profile is incomplete
  /// Throws [GenericServerException] for other server errors
  Future<AddItemResult> addItem({
    required String section,
    required Map<String, dynamic> payload,
    String? idempotencyToken,
  }) async {
    final callable = _functions.httpsCallable(
      'addItemWithQuota',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 15),
      ),
    );

    final token = idempotencyToken ?? _uuid.v4();

    try {
      final response = await callable.call({
        'section': section,
        'payload': payload,
        'idempotencyToken': token,
      });

      final data = Map<String, dynamic>.from(response.data as Map);
      return AddItemResult(
        itemId: data['itemId'] as String,
        section: data['section'] as String,
        currentCount: data['currentCount'] as int?,
        quotaLimit: data['quotaLimit'] as int?,
        replayed: data['replayed'] as bool? ?? false,
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapError(error);
    }
  }

  /// Get a real-time stream of quota counts for a user
  ///
  /// Returns a map of section names to current counts.
  /// Use this to display remaining quota in UI.
  Stream<Map<String, int>> countsStream(String uid) {
    return _firestore.doc('users/$uid').snapshots().map((doc) {
      if (!doc.exists) return <String, int>{};
      final counts = doc.data()?['counts'];
      if (counts is Map<String, dynamic>) {
        return counts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
      }
      return <String, int>{};
    });
  }

  /// Get current counts once (not real-time)
  Future<Map<String, int>> getCounts(String uid) async {
    final doc = await _firestore.doc('users/$uid').get();
    if (!doc.exists) return <String, int>{};
    final counts = doc.data()?['counts'];
    if (counts is Map<String, dynamic>) {
      return counts.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
    }
    return <String, int>{};
  }

  /// Get user's current plan
  Future<String> getUserPlan(String uid) async {
    final doc = await _firestore.doc('users/$uid').get();
    if (!doc.exists) return 'free';
    return doc.data()?['plan'] as String? ?? 'free';
  }

  /// Check if user can add more items to a section
  Future<bool> canAddItem(String uid, String section) async {
    final plan = await getUserPlan(uid);
    if (plan == 'premium') return true;

    final counts = await getCounts(uid);
    final currentCount = counts[section] ?? 0;
    return currentCount < 5;
  }

  /// Map Firebase Functions errors to typed exceptions
  Exception _mapError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'resource-exhausted':
        return QuotaExceededException(
          message: error.message ??
              'You have reached the Free plan limit. Upgrade to add more.',
          section: error.details?['section'] as String?,
          currentCount: error.details?['currentCount'] as int?,
          quotaLimit: error.details?['quotaLimit'] as int?,
        );
      case 'unauthenticated':
        return const AuthRequiredException('Please sign in to continue.');
      case 'invalid-argument':
        return BadRequestException(error.message ?? 'Invalid request.');
      case 'failed-precondition':
        return const MissingProfileException(
          'Your account configuration is incomplete. Please reload.',
        );
      default:
        return GenericServerException(
          error.message ?? 'Unexpected error. Please retry.',
        );
    }
  }
}

/// Exception thrown when quota limit is exceeded
class QuotaExceededException implements Exception {
  const QuotaExceededException({
    required this.message,
    this.section,
    this.currentCount,
    this.quotaLimit,
  });

  final String message;
  final String? section;
  final int? currentCount;
  final int? quotaLimit;

  @override
  String toString() => 'QuotaExceededException: $message';
}

/// Exception thrown when authentication is required
class AuthRequiredException implements Exception {
  const AuthRequiredException(this.message);
  final String message;

  @override
  String toString() => 'AuthRequiredException: $message';
}

/// Exception thrown for bad requests
class BadRequestException implements Exception {
  const BadRequestException(this.message);
  final String message;

  @override
  String toString() => 'BadRequestException: $message';
}

/// Exception thrown when user profile is missing
class MissingProfileException implements Exception {
  const MissingProfileException(this.message);
  final String message;

  @override
  String toString() => 'MissingProfileException: $message';
}

/// Generic server exception
class GenericServerException implements Exception {
  const GenericServerException(this.message);
  final String message;

  @override
  String toString() => 'GenericServerException: $message';
}
