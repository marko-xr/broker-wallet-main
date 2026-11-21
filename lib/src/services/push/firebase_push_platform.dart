import 'package:broker_wallet/src/services/push/push_messaging_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must match `android.notification.channel_id` in the push-dispatch Edge
/// Function and the default channel in AndroidManifest.xml.
const String followUpChannelId = 'follow_up_reminders';

/// iOS stays off until the iOS app has the NMO Digital
/// `GoogleService-Info.plist`, the Push Notifications capability and an APNs
/// key in Firebase (docs/NOTIFICATIONS_PRODUCTION_PLAN.md, iOS checklist).
const bool iosPushReady = false;

bool get pushSupportedOnThisPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        (iosPushReady && defaultTargetPlatform == TargetPlatform.iOS));

/// Firebase Cloud Messaging (Android FCM, later iOS through APNs).
///
/// Only notification messages are sent, so Android itself shows them while
/// the app is in the background or not running; no Dart background handler
/// (and no background isolate) is needed.
class FirebasePushPlatform implements PushPlatform {
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  String get platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<bool> initialize() async {
    if (!pushSupportedOnThisPlatform) return false;
    if (Firebase.apps.isEmpty) {
      // Android reads android/app/google-services.json (project
      // broker-wallet, package com.nmodigital.brokerwallet).
      await Firebase.initializeApp();
    }
    return true;
  }

  @override
  Future<void> updateChannel(String languageCode) async {
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    final arabic = languageCode == 'ar';
    await android.createNotificationChannel(AndroidNotificationChannel(
      followUpChannelId,
      arabic ? 'تذكيرات المتابعة' : 'Follow-up reminders',
      description: arabic
          ? 'تذكيرات متابعة الطلبات والعروض التي تحددها.'
          : 'Reminders you set to follow up on requests and offers.',
      importance: Importance.high,
    ));
  }

  @override
  Future<PushPermission> permission() async =>
      _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async =>
      _map((await _messaging.requestPermission()).authorizationStatus);

  PushPermission _map(AuthorizationStatus status) => switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<void> get foregroundMessages =>
      FirebaseMessaging.onMessage.where(_isOurs);

  @override
  Stream<void> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.where(_isOurs);

  @override
  Future<bool> launchedFromMessage() async {
    final message = await _messaging.getInitialMessage();
    return message != null && _isOurs(message);
  }

  static bool _isOurs(RemoteMessage message) =>
      message.data['kind'] == 'follow_up';
}
