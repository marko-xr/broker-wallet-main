import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';

/// Temporary notification repository used while authentication is on Supabase
/// but notifications have not yet been migrated from Firebase.
///
/// It deliberately performs no Firebase work. This prevents a Supabase-authenticated
/// user from being attached to a Firestore notification stream with no matching
/// Firebase Auth session during the staged backend migration.
class DeferredNotificationRepository implements NotificationRepository {
  @override
  Future<void> saveNotification(
    String userId,
    NotificationModel notification,
  ) async {}

  @override
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  }) async {
    return const <NotificationModel>[];
  }

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    return Stream<List<NotificationModel>>.value(
      const <NotificationModel>[],
    );
  }

  @override
  Stream<int> watchUnreadCount(String userId) => Stream<int>.value(0);

  @override
  Future<void> markAsRead(String userId, String notificationId) async {}

  @override
  Future<void> markAllAsRead(String userId) async {}

  @override
  Future<void> deleteNotification(String userId, String notificationId) async {}

  @override
  Future<void> upsertFcmToken(
    String userId,
    FcmTokenMetadata metadata,
  ) async {}

  @override
  Future<void> deleteFcmToken(String userId, String token) async {}
}
