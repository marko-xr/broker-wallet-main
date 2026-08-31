// lib/src/data/models/feedback_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedbackStatus { unread, read, resolved }

class FeedbackModel {
  final String? id;
  final String userId;
  final String userName;
  final String userEmail;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final String appVersion;
  final String platform;
  final String? deviceInfo;
  final FeedbackStatus status;

  FeedbackModel({
    this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.appVersion,
    required this.platform,
    this.deviceInfo,
    this.status = FeedbackStatus.unread,
  });

  // Convert to Map for Firebase storage
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
      'appVersion': appVersion,
      'platform': platform,
      'deviceInfo': deviceInfo,
      'status': status.name,
    };
  }

  // Create from Firebase document
  factory FeedbackModel.fromMap(Map<String, dynamic> map, String documentId) {
    return FeedbackModel(
      id: documentId,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userEmail: map['userEmail'] ?? '',
      rating: map['rating'] ?? 0,
      comment: map['comment'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      appVersion: map['appVersion'] ?? '',
      platform: map['platform'] ?? '',
      deviceInfo: map['deviceInfo'],
      status: FeedbackStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => FeedbackStatus.unread,
      ),
    );
  }

  // Copy with different values
  FeedbackModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userEmail,
    int? rating,
    String? comment,
    DateTime? createdAt,
    String? appVersion,
    String? platform,
    String? deviceInfo,
    FeedbackStatus? status,
  }) {
    return FeedbackModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      appVersion: appVersion ?? this.appVersion,
      platform: platform ?? this.platform,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      status: status ?? this.status,
    );
  }
}
