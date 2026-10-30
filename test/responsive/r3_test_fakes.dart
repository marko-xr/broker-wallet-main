import 'dart:async';

import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'r2_test_fakes.dart';

Widget withR3ScreenProviders(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewModel>(
        create: (_) => AuthViewModel(
          authRepository: QuietAuthRepository(),
          userRepository: QuietUserRepository(),
          autoInitialize: false,
        ),
      ),
      ChangeNotifierProvider<ThemeViewModel>(
        create: (_) => ThemeViewModel(),
      ),
      ChangeNotifierProvider<LocaleViewModel>(
        create: (_) => LocaleViewModel(),
      ),
    ],
    child: child,
  );
}

class ControlledNotificationRepository implements NotificationRepository {
  final StreamController<List<NotificationModel>> _notifications =
      StreamController<List<NotificationModel>>.broadcast(sync: true);
  final StreamController<int> _unread =
      StreamController<int>.broadcast(sync: true);

  List<NotificationModel> fetched = const [];

  void emit(List<NotificationModel> value) => _notifications.add(value);

  void emitUnread(int value) => _unread.add(value);

  void emitError(Object error) => _notifications.addError(error);

  Future<void> close() async {
    await _notifications.close();
    await _unread.close();
  }

  @override
  Future<void> deleteFcmToken(String userId, String token) async {}

  @override
  Future<void> deleteNotification(
    String userId,
    String notificationId,
  ) async {}

  @override
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  }) async =>
      fetched;

  @override
  Future<void> markAllAsRead(String userId) async {}

  @override
  Future<void> markAsRead(String userId, String notificationId) async {}

  @override
  Future<void> saveNotification(
    String userId,
    NotificationModel notification,
  ) async {}

  @override
  Future<void> upsertFcmToken(
    String userId,
    FcmTokenMetadata metadata,
  ) async {}

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) =>
      _notifications.stream;

  @override
  Stream<int> watchUnreadCount(String userId) => _unread.stream;
}
