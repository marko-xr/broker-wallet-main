import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// RLS-backed in-app notifications. Push delivery/device registration remains
/// a separate server integration and is deliberately not faked here.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _requireUser(String requestedUserId) {
    final current = _client.auth.currentUser?.id;
    if (current == null || current != requestedUserId) {
      throw StateError('An authenticated user session is required.');
    }
    return current;
  }

  @override
  Future<void> saveNotification(String userId, NotificationModel notification) {
    throw UnsupportedError('Notifications can only be created by the backend.');
  }

  @override
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  }) async {
    _requireUser(userId);
    var query =
        _client.from('notifications').select().eq('recipient_id', userId);
    if (startAfter != null) {
      query = query.lt(
          'created_at', startAfter.createdAt.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    _requireUser(userId);
    return _client
        .from('notifications')
        .stream(primaryKey: const ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(_fromRow).toList(growable: false));
  }

  @override
  Stream<int> watchUnreadCount(String userId) =>
      watchLatestNotifications(userId, limit: 500)
          .map((rows) => rows.where((row) => !row.isRead).length);

  @override
  Future<void> markAsRead(String userId, String notificationId) async {
    _requireUser(userId);
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('id', notificationId);
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    _requireUser(userId);
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('is_read', false);
  }

  @override
  Future<void> deleteNotification(String userId, String notificationId) async {
    _requireUser(userId);
    // The authoritative schema supports hard deletion, not deleted_at.
    await _client
        .from('notifications')
        .delete()
        .eq('recipient_id', userId)
        .eq('id', notificationId);
  }

  @override
  Future<void> upsertFcmToken(String userId, FcmTokenMetadata metadata) {
    throw UnsupportedError('Push device registration is not configured.');
  }

  @override
  Future<void> deleteFcmToken(String userId, String token) async {
    _requireUser(userId);
    await _client
        .from('push_devices')
        .delete()
        .eq('owner_id', userId)
        .eq('token_value', token);
  }

  NotificationModel _fromRow(Map<String, dynamic> row) => NotificationModel(
        id: row['id']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        body: row['body']?.toString() ?? '',
        category: NotificationCategoryParser.fromString(
          row['category']?.toString(),
        ),
        isRead: row['is_read'] as bool? ?? false,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now(),
        data: Map<String, dynamic>.from(
          row['data'] as Map? ?? const <String, dynamic>{},
        ),
        actionRoute: row['action_route']?.toString(),
        offerId: row['offer_id']?.toString(),
        requestId: row['request_id']?.toString(),
        matchScore: (row['match_score'] as num?)?.toDouble(),
        senderUserId: row['sender_user_id']?.toString(),
      );
}
