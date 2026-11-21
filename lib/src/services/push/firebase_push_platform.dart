import 'package:broker_wallet/src/services/push/push_messaging_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must match `android.notification.channel_id` in the push-dispatch Edge
/// Function and the default channel in AndroidManifest.xml.
const String followUpChannelId = 'follow_up_reminders';

/// iOS is wired: the app (bundle `com.nmodigital.brokerwallet`) carries the
/// `broker-wallet` `GoogleService-Info.plist`, the `aps-environment`
/// entitlement and Firebase method swizzling. Until the APNs key is uploaded
/// to Firebase and the app is signed with a team that has the Push
/// Notifications capability, iOS simply gets no APNs token: [FirebasePushPlatform.token]
/// then fails quietly, nothing is registered and nothing else changes
/// (docs/NOTIFICATIONS_PRODUCTION_PLAN.md, iOS checklist).
const bool iosPushReady = true;

/// How long [FirebasePushPlatform.token] waits on iOS for the APNs token
/// (FCM refuses to give a token before it), in total.
const List<Duration> apnsTokenWaits = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
];

/// Thrown when iOS has no APNs token yet. The push service retries later
/// (and again on the next sign-in, language change or token refresh).
class ApnsTokenUnavailable implements Exception {
  const ApnsTokenUnavailable();
  @override
  String toString() => 'ApnsTokenUnavailable';
}

/// Waits for the APNs token: reads it now, then after each of [waits]. FCM's
/// documentation requires it before any FCM call on Apple platforms.
@visibleForTesting
Future<String> waitForApnsToken(
  Future<String?> Function() read, {
  List<Duration> waits = apnsTokenWaits,
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async {
  for (var i = 0; i <= waits.length; i++) {
    final token = await read();
    if (token != null && token.isNotEmpty) return token;
    if (i < waits.length) await sleep(waits[i]);
  }
  throw const ApnsTokenUnavailable();
}

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
      // Android reads android/app/google-services.json, iOS
      // ios/Runner/GoogleService-Info.plist (both project broker-wallet,
      // com.nmodigital.brokerwallet). On iOS the default app is already
      // configured natively in AppDelegate.swift; this call attaches to it
      // and does not configure Firebase a second time.
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

  /// On iOS the APNs token must exist before FCM gives its own token; without
  /// it [ApnsTokenUnavailable] is thrown and the push service retries later.
  @override
  Future<String?> token() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await waitForApnsToken(_messaging.getAPNSToken);
    }
    return _messaging.getToken();
  }

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
