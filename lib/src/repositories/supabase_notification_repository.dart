import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:flutter/foundation.dart';
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

  /// One page, newest first, in the stable order (created_at, id). With
  /// [startAfter] it returns only rows strictly after that one in this order,
  /// so rows sharing a timestamp are neither skipped nor repeated.
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
      query = query.or(notificationKeysetFilter(startAfter));
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return parseNotificationRows(rows);
  }

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    // OFF-2b-2: decided when listened to — offline, no Realtime subscription
    // is opened and no event is applied from the switch on.
    if (AppAccessPolicy.isOnline) _requireUser(userId);
    return AppAccessPolicy.onlineOnly(() => _client
        .from('notifications')
        .stream(primaryKey: const ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map(parseNotificationRows));
  }

  /// Every change Realtime reports for the account is only a signal: the
  /// number itself always comes from an exact server count, never from the
  /// rows that happen to be loaded.
  @override
  Stream<int> watchUnreadCount(String userId) {
    if (AppAccessPolicy.isOnline) _requireUser(userId);
    return AppAccessPolicy.onlineOnly(() => _client
        .from('notifications')
        .stream(primaryKey: const ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(20)
        .asyncMap((_) => countUnread(userId)));
  }

  @override
  Future<int> countUnread(String userId) async {
    _requireUser(userId);
    return _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('recipient_id', userId)
        .eq('is_read', false);
  }

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
}

/// The PostgREST `or` filter for "strictly after [after]" in the order
/// (created_at desc, id desc).
@visibleForTesting
String notificationKeysetFilter(NotificationModel after) {
  final at = after.createdAt.toUtc().toIso8601String();
  return 'created_at.lt.$at,and(created_at.eq.$at,id.lt.${after.id})';
}

/// The rows the app can show. A row without an id, with a category the app
/// does not offer, or without a readable creation time is left out rather
/// than shown as something it is not (no invented category, no "now").
@visibleForTesting
List<NotificationModel> parseNotificationRows(
  List<Map<String, dynamic>> rows,
) {
  final result = <NotificationModel>[];
  for (final row in rows) {
    final parsed = parseNotificationRow(row);
    if (parsed != null) result.add(parsed);
  }
  return List<NotificationModel>.unmodifiable(result);
}

@visibleForTesting
NotificationModel? parseNotificationRow(Map<String, dynamic> row) {
  final id = row['id']?.toString() ?? '';
  final category =
      NotificationCategoryParser.fromString(row['category']?.toString());
  final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
  if (id.isEmpty || category == null || createdAt == null) return null;
  return NotificationModel(
    id: id,
    title: row['title']?.toString() ?? '',
    body: row['body']?.toString() ?? '',
    category: category,
    isRead: row['is_read'] as bool? ?? false,
    createdAt: createdAt,
    data: row['data'] is Map
        ? Map<String, dynamic>.from(row['data'] as Map)
        : const <String, dynamic>{},
    actionRoute: row['action_route']?.toString(),
    offerId: row['offer_id']?.toString(),
    requestId: row['request_id']?.toString(),
    matchScore: (row['match_score'] as num?)?.toDouble(),
    senderUserId: row['sender_user_id']?.toString(),
  );
}
