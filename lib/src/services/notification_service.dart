import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/firebase_options.dart';
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Background handler required by Firebase Messaging
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Centralized notification orchestration: permissions, tokens, foreground display
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AuthRepository _authRepository =
      RepositoryProvider.instance.authRepository;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final NotificationRepository _notificationRepository =
      RepositoryProvider.instance.notificationRepository;
  StreamSubscription<UserModel?>? _authSubscription;
  String? _lastAuthenticatedUserId;

  final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notificationTapStream =>
      _notificationTapController.stream;

  bool _initialized = false;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'broker_wallet_high_importance',
    'Important Alerts',
    description: 'High priority alerts for matches and reminders.',
    importance: Importance.max,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    tz.initializeTimeZones();
    _configureTimezone();

    await _configureLocalNotifications();
    await _requestPermission();
    await _syncInitialToken();

    _messaging.onTokenRefresh.listen(_handleTokenRefresh);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedRemoteMessage);
    _authSubscription ??= _authRepository.authStateChanges.listen((user) async {
      if (user != null) {
        _lastAuthenticatedUserId = user.uid;
        await _syncInitialToken();
      } else {
        final previousUserId = _lastAuthenticatedUserId;
        _lastAuthenticatedUserId = null;
        await _clearTokenForUser(previousUserId);
      }
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedRemoteMessage(initialMessage);
    }

    _initialized = true;
  }

  Future<void> _configureLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final initializationSettings = const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        _notificationTapController.add(response.payload != null
            ? {'route': response.payload}
            : <String, dynamic>{});
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  void _configureTimezone() {
    final locationName = DateTime.now().timeZoneName;
    try {
      tz.setLocalLocation(tz.getLocation(locationName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) {
        print('⚠️ Notification permission denied');
      }
    }
  }

  Future<void> _syncInitialToken() async {
    final token = await _messaging.getToken();
    final uid = _authRepository.currentUserId;
    if (token == null || uid == null) {
      return;
    }

    _lastAuthenticatedUserId = uid;

    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : 'unknown';
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();
    final deviceName = await _resolveDeviceName();

    await _notificationRepository.upsertFcmToken(
      uid,
      FcmTokenMetadata(
        token: token,
        platform: platform,
        updatedAt: DateTime.now(),
        deviceName: deviceName,
        locale: locale,
      ),
    );
  }

  void _handleTokenRefresh(String token) {
    final uid = _authRepository.currentUserId;
    if (uid == null) {
      return;
    }

    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : 'unknown';
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();

    _notificationRepository.upsertFcmToken(
      uid,
      FcmTokenMetadata(
        token: token,
        platform: platform,
        updatedAt: DateTime.now(),
        deviceName: null,
        locale: locale,
      ),
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final android = notification?.android;

    if (notification == null) {
      return;
    }

    final payloadRoute = message.data['route'] ?? '';

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Broker Wallet',
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: android?.smallIcon,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payloadRoute.isNotEmpty ? payloadRoute : null,
    );
  }

  void _handleOpenedRemoteMessage(RemoteMessage message) {
    _notificationTapController.add(message.data);
  }

  Future<void> clearToken() async {
    await _clearTokenForUser(
      _authRepository.currentUserId ?? _lastAuthenticatedUserId,
    );
  }

  Future<void> _clearTokenForUser(String? uid) async {
    final token = await _messaging.getToken();
    if (uid == null || token == null) {
      return;
    }
    await _notificationRepository.deleteFcmToken(uid, token);
  }

  Future<String?> _resolveDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return info.model;
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.utsname.machine;
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to resolve device name: $e');
      }
    }
    return null;
  }
}
