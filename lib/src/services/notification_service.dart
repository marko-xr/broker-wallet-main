import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/firebase_options.dart';
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/repositories/firestore_notification_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
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
  NotificationService._internal({
    FirebaseMessaging? messaging,
    AuthRepository? authRepository,
    NotificationRepository? notificationRepository,
    FlutterLocalNotificationsPlugin? localNotifications,
    Future<String?> Function()? tokenProvider,
    bool? isSupabaseAuthModeOverride,
  })  : _messaging = messaging,
        _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _notificationRepository = notificationRepository ??
            RepositoryProvider.instance.notificationRepository,
        _tokenProvider = tokenProvider,
        _isSupabaseAuthModeOverride = isSupabaseAuthModeOverride;

  static final NotificationService instance =
      NotificationService._internal(messaging: FirebaseMessaging.instance);

  @visibleForTesting
  factory NotificationService.forTesting({
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
    Future<String?> Function()? tokenProvider,
    bool? isSupabaseAuthModeOverride,
  }) {
    return NotificationService._internal(
      authRepository: authRepository,
      notificationRepository: notificationRepository,
      tokenProvider: tokenProvider,
      isSupabaseAuthModeOverride: isSupabaseAuthModeOverride,
    );
  }

  final FirebaseMessaging? _messaging;
  final AuthRepository _authRepository;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final NotificationRepository _notificationRepository;
  final Future<String?> Function()? _tokenProvider;
  final bool? _isSupabaseAuthModeOverride;
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

    final messaging = _messaging;
    if (messaging == null) {
      throw StateError('NotificationService requires FirebaseMessaging.');
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    tz.initializeTimeZones();
    _configureTimezone();

    await _configureLocalNotifications();
    await _requestPermission();
    await _syncInitialToken();

    messaging.onTokenRefresh.listen(_handleTokenRefresh);
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

    final initialMessage = await messaging.getInitialMessage();
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
    final messaging = _messaging;
    if (messaging == null) {
      return;
    }

    final settings = await messaging.requestPermission(
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
    final messaging = _messaging;
    if (messaging == null) {
      return;
    }

    final token = await messaging.getToken();
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
    if (_isSupabaseAuthMode &&
        _notificationRepository is FirestoreNotificationRepository) {
      if (kDebugMode) {
        print(
            '⚠️ Skipping legacy Firestore FCM delete in Supabase auth mode (unsupported backend/session combination).');
      }
      return;
    }

    await _clearTokenForUser(
      _authRepository.currentUserId ?? _lastAuthenticatedUserId,
    );
  }

  Future<void> _clearTokenForUser(String? uid) async {
    final token = await _resolveToken();
    if (uid == null || token == null) {
      return;
    }
    await _notificationRepository.deleteFcmToken(uid, token);
  }

  Future<String?> _resolveToken() async {
    if (_tokenProvider != null) {
      return _tokenProvider();
    }
    final messaging = _messaging;
    if (messaging == null) {
      return null;
    }
    return messaging.getToken();
  }

  bool get _isSupabaseAuthMode =>
      _isSupabaseAuthModeOverride ?? SupabaseConfig.useSupabaseAuth;

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
