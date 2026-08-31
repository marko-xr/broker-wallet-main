import 'package:broker_wallet/src/data/models/notification_model.dart';

/// Repository responsible for persisting notification data and device tokens
abstract class NotificationRepository {
  /// Save or update a notification under the current user document
  Future<void> saveNotification(String userId, NotificationModel notification);

  /// Fetch notifications ordered by creation time desc
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  });

  /// Real-time stream for a lightweight subset (used for badge counts)
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  });

  /// Stream of unread count for quick badge updates
  Stream<int> watchUnreadCount(String userId);

  /// Mark a single notification as read
  Future<void> markAsRead(String userId, String notificationId);

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId);

  /// Delete a notification entry
  Future<void> deleteNotification(String userId, String notificationId);

  /// Persist a device token so Cloud Functions can target this device
  Future<void> upsertFcmToken(String userId, FcmTokenMetadata metadata);

  /// Remove a device token (called on logout)
  Future<void> deleteFcmToken(String userId, String token);
}
