import 'dart:async';

import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class QuietAuthRepository implements AuthRepository {
  @override
  Stream<UserModel?> get authStateChanges => const Stream<UserModel?>.empty();

  @override
  UserModel? get currentUser => null;

  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuietUserRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuietNotificationRepository implements NotificationRepository {
  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) =>
      const Stream<List<NotificationModel>>.empty();

  @override
  Stream<int> watchUnreadCount(String userId) => const Stream<int>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuietFavoriteService extends FavoriteService {
  @override
  Future<bool> isFavorite(String itemId, String type) async => false;

  @override
  Future<void> addToFavorites(String itemId, String type) async {}

  @override
  Future<void> removeFromFavorites(String itemId, String type) async {}
}

Widget withR2ScreenProviders(
  Widget child, {
  OptimisticFavoritesService? favorites,
}) {
  final auth = AuthViewModel(
    authRepository: QuietAuthRepository(),
    userRepository: QuietUserRepository(),
    autoInitialize: false,
  );
  final notifications = NotificationViewModel(
    repository: QuietNotificationRepository(),
  );
  final optimistic = favorites ??
      OptimisticFavoritesService(favoriteService: QuietFavoriteService());

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewModel>.value(value: auth),
      ChangeNotifierProvider<NotificationViewModel>.value(value: notifications),
      ChangeNotifierProvider<OptimisticFavoritesService>.value(
        value: optimistic,
      ),
    ],
    child: child,
  );
}
