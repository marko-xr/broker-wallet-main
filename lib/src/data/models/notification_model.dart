import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Supported in-app notification categories
/// Used for quick filtering and client-side routing decisions
enum NotificationCategory {
  /// When an offer matches a user's request criteria
  match,

  /// Reminder for active requests or available offers
  reminder,

  /// Plan alerts - quota limits, subscription expiring, upgrade prompts
  plan,

  /// System updates - new app version available
  system,
}

extension NotificationCategoryParser on NotificationCategory {
  String get firestoreValue {
    switch (this) {
      case NotificationCategory.match:
        return 'match';
      case NotificationCategory.reminder:
        return 'reminder';
      case NotificationCategory.plan:
        return 'plan';
      case NotificationCategory.system:
        return 'system';
    }
  }

  static NotificationCategory fromString(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'match':
        return NotificationCategory.match;
      case 'reminder':
        return NotificationCategory.reminder;
      case 'plan':
      case 'quota': // Legacy support
        return NotificationCategory.plan;
      case 'system':
        return NotificationCategory.system;
      default:
        return NotificationCategory
            .reminder; // Default to reminder instead of general
    }
  }
}

/// Model representing a single in-app notification entry
@immutable
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final NotificationCategory category;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  final String? actionRoute;
  final String? offerId;
  final String? requestId;
  final double? matchScore;
  final String? senderUserId;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.isRead,
    required this.createdAt,
    required this.data,
    this.actionRoute,
    this.offerId,
    this.requestId,
    this.matchScore,
    this.senderUserId,
  });

  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    NotificationCategory? category,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? data,
    String? actionRoute,
    String? offerId,
    String? requestId,
    double? matchScore,
    String? senderUserId,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
      actionRoute: actionRoute ?? this.actionRoute,
      offerId: offerId ?? this.offerId,
      requestId: requestId ?? this.requestId,
      matchScore: matchScore ?? this.matchScore,
      senderUserId: senderUserId ?? this.senderUserId,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      'category': category.firestoreValue,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'data': data,
      'actionRoute': actionRoute,
      'offerId': offerId,
      'requestId': requestId,
      'matchScore': matchScore,
      'senderUserId': senderUserId,
    };
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return NotificationModel(
      id: doc.id,
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      category: NotificationCategoryParser.fromString(
        data['category']?.toString(),
      ),
      isRead: data['isRead'] as bool? ?? false,
      createdAt: _parseTimestamp(data['createdAt']) ?? DateTime.now(),
      data: Map<String, dynamic>.from(data['data'] as Map? ?? {}),
      actionRoute: data['actionRoute']?.toString(),
      offerId: data['offerId']?.toString(),
      requestId: data['requestId']?.toString(),
      matchScore: (data['matchScore'] as num?)?.toDouble(),
      senderUserId: data['senderUserId']?.toString(),
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is Map<String, dynamic>) {
      final seconds = raw['seconds'] ?? raw['_seconds'];
      final nanoseconds = raw['nanoseconds'] ?? raw['_nanoseconds'] ?? 0;
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + ((nanoseconds is int ? nanoseconds : 0) ~/ 1000000),
        );
      }
    }
    return DateTime.tryParse(raw.toString());
  }
}

/// Metadata describing the device token currently registered for push
class FcmTokenMetadata {
  final String token;
  final String platform;
  final DateTime updatedAt;
  final String? deviceName;
  final String? locale;

  const FcmTokenMetadata({
    required this.token,
    required this.platform,
    required this.updatedAt,
    this.deviceName,
    this.locale,
  });

  Map<String, dynamic> toMap() {
    return {
      'platform': platform,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'deviceName': deviceName,
      'locale': locale,
    };
  }
}
