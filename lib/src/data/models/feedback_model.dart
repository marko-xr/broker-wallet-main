// lib/src/data/models/feedback_model.dart

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
