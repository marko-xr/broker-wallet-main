import 'dart:async';

import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:flutter/foundation.dart';

class NotificationViewModel extends ChangeNotifier {
  NotificationViewModel({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  StreamSubscription<List<NotificationModel>>? _notificationSubscription;
  StreamSubscription<int>? _unreadSubscription;

  List<NotificationModel> _notifications = const [];
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _userId;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _notifications.isEmpty && !_isLoading;

  void attachUser(String? userId) {
    if (_userId == userId) {
      return;
    }

    _userId = userId;
    _notificationSubscription?.cancel();
    _unreadSubscription?.cancel();
    _notifications = const [];
    _unreadCount = 0;
    _isLoading = true;
    notifyListeners();

    if (userId == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _notificationSubscription =
        _repository.watchLatestNotifications(userId).listen((items) {
      _notifications = items;
      _isLoading = false;
      notifyListeners();
    });

    _unreadSubscription = _repository.watchUnreadCount(userId).listen((count) {
      _unreadCount = count;
      notifyListeners();
    });
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || _userId == null || _notifications.isEmpty) {
      return;
    }
    _isLoadingMore = true;
    notifyListeners();
    try {
      final more = await _repository.fetchNotifications(
        _userId!,
        startAfter: _notifications.last,
      );
      if (more.isNotEmpty) {
        _notifications = [..._notifications, ...more];
        notifyListeners();
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_userId == null) {
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final items = await _repository.fetchNotifications(_userId!);
      _notifications = items;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String notificationId) async {
    if (_userId == null) return;
    await _repository.markAsRead(_userId!, notificationId);
  }

  Future<void> markAllAsRead() async {
    if (_userId == null) return;
    await _repository.markAllAsRead(_userId!);
  }

  Future<void> deleteNotification(String notificationId) async {
    if (_userId == null) return;
    await _repository.deleteNotification(_userId!, notificationId);
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _unreadSubscription?.cancel();
    super.dispose();
  }
}
