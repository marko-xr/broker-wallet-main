import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-backed notification repository with offline caching support
class FirestoreNotificationRepository implements NotificationRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _notificationsRef(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications');
  }

  CollectionReference<Map<String, dynamic>> _tokenRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('fcmTokens');
  }

  @override
  Future<void> saveNotification(
    String userId,
    NotificationModel notification,
  ) async {
    await _notificationsRef(userId)
        .doc(notification.id)
        .set(notification.toFirestore(), SetOptions(merge: true));
  }

  @override
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _notificationsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfter([startAfter.createdAt]);
    }

    final snapshot =
        await query.get(const GetOptions(source: Source.serverAndCache));
    return snapshot.docs.map(NotificationModel.fromFirestore).toList();
  }

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    return _notificationsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) =>
            snapshot.docs.map(NotificationModel.fromFirestore).toList());
  }

  @override
  Stream<int> watchUnreadCount(String userId) {
    return _notificationsRef(userId)
        .where('isRead', isEqualTo: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs.length);
  }

  @override
  Future<void> markAsRead(String userId, String notificationId) async {
    await _notificationsRef(userId)
        .doc(notificationId)
        .update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _notificationsRef(userId)
        .where('isRead', isEqualTo: false)
        .limit(200)
        .get();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference,
          {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  @override
  Future<void> deleteNotification(String userId, String notificationId) async {
    await _notificationsRef(userId).doc(notificationId).delete();
  }

  @override
  Future<void> upsertFcmToken(String userId, FcmTokenMetadata metadata) async {
    await _tokenRef(userId)
        .doc(metadata.token)
        .set(metadata.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> deleteFcmToken(String userId, String token) async {
    await _tokenRef(userId).doc(token).delete();
  }
}
