import 'dart:async';

import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:flutter/foundation.dart';

class NotificationViewModel extends ChangeNotifier {
  /// [isOnline] is a test seam; the app always reads [AppAccessPolicy].
  NotificationViewModel({
    required NotificationRepository repository,
    bool Function()? isOnline,
  })  : _repository = repository,
        _isOnline = isOnline ?? (() => AppAccessPolicy.isOnline);

  /// Rows the live Realtime feed keeps (the newest ones).
  static const int liveFeedSize = 20;

  /// Rows fetched per page when the user pulls to refresh or scrolls on.
  static const int pageSize = 25;

  /// The greatest UUID. As a cursor id it makes "strictly after" include every
  /// row of the cursor's timestamp, for the first page read after the live
  /// feed, whose rows sharing a timestamp at its end were cut arbitrarily.
  static const String _maxUuid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

  final NotificationRepository _repository;
  final bool Function() _isOnline;

  StreamSubscription<List<NotificationModel>>? _notificationSubscription;
  StreamSubscription<int>? _unreadSubscription;

  /// Rows from the live feed (the newest page, replaced on every event).
  List<NotificationModel> _live = const [];

  /// Rows read page by page (refresh and load more), kept across live events.
  List<NotificationModel> _paged = const [];

  /// Rows the user deleted whose server deletion has not finished yet.
  final Set<String> _pendingDeletes = <String>{};

  /// The last row of the last page read, in the stable (created_at, id)
  /// order. Null until a page has been read.
  NotificationModel? _cursor;

  List<NotificationModel> _notifications = const [];
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _loadMoreFailed = false;
  bool _feedUnavailable = false;
  bool _isOffline = false;
  bool _disposed = false;
  String? _userId;

  /// Bumped whenever the account changes, the feed is reopened, or the view
  /// model is disposed. An answer that arrives for an older generation is
  /// dropped, so one account's rows can never land in another account's list.
  int _generation = 0;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _notifications.isEmpty && !_isLoading;

  /// Whether older notifications may still exist on the server.
  bool get hasMore => _hasMore;

  /// The last attempt to read older notifications failed. Scrolling no
  /// longer retries on its own; [retryLoadMore] or [refresh] does.
  bool get loadMoreFailed => _loadMoreFailed;

  /// True when the notification feed could not be read. It never changes
  /// anything about the account: no sign-out, no session change.
  bool get isFeedUnavailable => _feedUnavailable;

  /// True when the app is in offline read-only mode, so the feed was not
  /// opened. Nothing is fetched until the app is online again and the user
  /// refreshes.
  bool get isOffline => _isOffline;

  void attachUser(String? userId) {
    if (_userId == userId) {
      return;
    }

    _userId = userId;
    _resetFeed();
    _isLoading = true;
    _notify();

    if (userId == null) {
      _isLoading = false;
      _notify();
      return;
    }
    _openFeed(userId);
  }

  void _resetFeed() {
    _generation++;
    _cancelSubscriptions();
    _live = const [];
    _paged = const [];
    _pendingDeletes.clear();
    _cursor = null;
    _notifications = const [];
    _unreadCount = 0;
    _hasMore = true;
    _loadMoreFailed = false;
    _feedUnavailable = false;
    _isOffline = false;
    _isLoadingMore = false;
  }

  void _cancelSubscriptions() {
    _notificationSubscription?.cancel();
    _unreadSubscription?.cancel();
    _notificationSubscription = null;
    _unreadSubscription = null;
  }

  /// Opens the live feed and the unread count for [userId] in the current
  /// generation. Offline, nothing is opened and the offline state is shown.
  void _openFeed(String userId) {
    final generation = _generation;
    if (!_isOnline()) {
      _isOffline = true;
      _isLoading = false;
      _notify();
      return;
    }

    // Both subscriptions carry an `onError`. A Supabase Realtime channel that
    // is refused — `RealtimeSubscribeException`, a dropped socket, a filter the
    // server rejects — otherwise surfaces as an unhandled async error that
    // pauses the debugger repeatedly and can reach the user as a crash. A
    // notification feed failing is never a reason to change what the app shows
    // about the account, so the handlers settle the loading state and nothing
    // else: no sign-out, no auth mutation, and no logging of the payload.
    _notificationSubscription = _repository
        .watchLatestNotifications(userId, limit: liveFeedSize)
        .listen(
      (items) {
        if (!_isCurrent(userId, generation)) return;
        _live = items;
        _feedUnavailable = false;
        if (_cursor == null) _hasMore = items.length >= liveFeedSize;
        _isLoading = false;
        _rebuild();
        _notify();
      },
      onError: (Object error) => _handleFeedError(userId, generation, error),
    );

    _unreadSubscription = _repository.watchUnreadCount(userId).listen(
      (count) {
        if (!_isCurrent(userId, generation)) return;
        _unreadCount = count;
        _notify();
      },
      onError: (Object error) => _handleFeedError(userId, generation, error),
    );
  }

  bool _isCurrent(String userId, int generation) =>
      !_disposed && _userId == userId && _generation == generation;

  /// Records that the notification feed is unavailable for [userId].
  ///
  /// Deliberately narrow. It never touches authentication, never clears the
  /// session, and never rethrows. The error's message is not kept, because a
  /// provider error can carry a filter, a row or a token fragment.
  void _handleFeedError(String userId, int generation, Object error) {
    if (!_isCurrent(userId, generation)) return;
    _feedUnavailable = true;
    _isLoading = false;
    _notify();
  }

  /// Merges the live rows and the paged rows: one entry per id (the live copy
  /// wins, it is the freshest), minus rows being deleted, newest first in the
  /// stable (created_at, id) order.
  void _rebuild() {
    final byId = <String, NotificationModel>{};
    for (final item in _paged) {
      byId[item.id] = item;
    }
    for (final item in _live) {
      byId[item.id] = item;
    }
    _pendingDeletes.forEach(byId.remove);
    final merged = byId.values.toList()..sort(_newestFirst);
    _notifications = List<NotificationModel>.unmodifiable(merged);
  }

  static int _newestFirst(NotificationModel a, NotificationModel b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore ||
        _loadMoreFailed ||
        !_hasMore ||
        _userId == null ||
        _notifications.isEmpty) {
      return;
    }
    final userId = _userId!;
    if (!_isOnline()) {
      _isOffline = true;
      _notify();
      return;
    }
    final generation = _generation;
    final cursor = _cursor ?? _notifications.last.copyWith(id: _maxUuid);
    _isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.fetchNotifications(
        userId,
        limit: pageSize,
        startAfter: cursor,
      );
      if (!_isCurrent(userId, generation)) return;
      _paged = [..._paged, ...page];
      if (page.isNotEmpty) _cursor = page.last;
      _hasMore = page.length >= pageSize;
      _rebuild();
    } catch (_) {
      if (!_isCurrent(userId, generation)) return;
      _loadMoreFailed = true;
    } finally {
      if (_isCurrent(userId, generation)) {
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  /// Tries to read older notifications again after a failed attempt.
  Future<void> retryLoadMore() {
    _loadMoreFailed = false;
    return loadMore();
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) {
      return;
    }
    if (!_isOnline()) {
      _isOffline = true;
      _isLoading = false;
      _notify();
      return;
    }
    if (_isOffline || _feedUnavailable) {
      // The app is online again, or the feed failed earlier: a refresh the
      // user asked for opens a new live feed in a new generation.
      _generation++;
      _cancelSubscriptions();
      _isOffline = false;
      _feedUnavailable = false;
      _openFeed(userId);
    }
    final generation = _generation;
    _isLoading = true;
    _notify();
    try {
      final page = await _repository.fetchNotifications(
        userId,
        limit: pageSize,
      );
      if (!_isCurrent(userId, generation)) return;
      _paged = page;
      _cursor = page.isEmpty ? null : page.last;
      _hasMore = page.length >= pageSize;
      _loadMoreFailed = false;
      _feedUnavailable = false;
      _rebuild();
      unawaited(_recount(userId, generation));
    } catch (_) {
      if (!_isCurrent(userId, generation)) return;
      _feedUnavailable = true;
    } finally {
      if (_isCurrent(userId, generation)) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// Marks one notification read. A failure changes nothing on screen.
  Future<void> markAsRead(String notificationId) async {
    final userId = _userId;
    if (userId == null) return;
    final generation = _generation;
    try {
      await _repository.markAsRead(userId, notificationId);
    } catch (_) {
      return;
    }
    if (!_isCurrent(userId, generation)) return;
    _markLocallyRead((item) => item.id == notificationId);
    unawaited(_recount(userId, generation));
  }

  /// Marks every notification read. A failure changes nothing on screen.
  Future<void> markAllAsRead() async {
    final userId = _userId;
    if (userId == null) return;
    final generation = _generation;
    try {
      await _repository.markAllAsRead(userId);
    } catch (_) {
      return;
    }
    if (!_isCurrent(userId, generation)) return;
    _markLocallyRead((_) => true);
    unawaited(_recount(userId, generation));
  }

  void _markLocallyRead(bool Function(NotificationModel item) test) {
    NotificationModel read(NotificationModel item) =>
        !item.isRead && test(item) ? item.copyWith(isRead: true) : item;
    _live = _live.map(read).toList(growable: false);
    _paged = _paged.map(read).toList(growable: false);
    _rebuild();
    _notify();
  }

  /// Removes the row at once and puts it back in its place if the server
  /// does not confirm the deletion.
  Future<void> deleteNotification(String notificationId) async {
    final userId = _userId;
    if (userId == null) return;
    final generation = _generation;
    _pendingDeletes.add(notificationId);
    _rebuild();
    _notify();
    try {
      await _repository.deleteNotification(userId, notificationId);
    } catch (_) {
      if (!_isCurrent(userId, generation)) return;
      _pendingDeletes.remove(notificationId);
      _rebuild();
      _notify();
      return;
    }
    if (!_isCurrent(userId, generation)) return;
    _live = _live.where((item) => item.id != notificationId).toList();
    _paged = _paged.where((item) => item.id != notificationId).toList();
    _pendingDeletes.remove(notificationId);
    _rebuild();
    _notify();
    unawaited(_recount(userId, generation));
  }

  /// Re-reads the exact unread count, e.g. when a push arrives while the app
  /// is open (Realtime normally does this already).
  Future<void> refreshUnreadCount() async {
    final userId = _userId;
    if (userId == null || !_isOnline()) return;
    await _recount(userId, _generation);
  }

  /// Reads the exact unread count from the server. Realtime does not report
  /// every deletion, so the count is read again after the user's own changes.
  Future<void> _recount(String userId, int generation) async {
    try {
      final count = await _repository.countUnread(userId);
      if (!_isCurrent(userId, generation)) return;
      _unreadCount = count;
      _notify();
    } catch (_) {
      // The live count stays as it is; a later event or refresh reads it again.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelSubscriptions();
    super.dispose();
  }
}
