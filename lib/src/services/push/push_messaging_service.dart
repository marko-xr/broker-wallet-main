import 'dart:async';

import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PushPermission { granted, denied, notDetermined }

/// The device side of push: Firebase Messaging on a real phone, a fake in
/// tests. Nothing here talks to Supabase.
abstract class PushPlatform {
  /// Prepares the platform (Firebase, Android channel). False when push
  /// cannot work on this device; the service then stays inactive.
  Future<bool> initialize();

  /// Creates or renames the Android channel in the app's language.
  Future<void> updateChannel(String languageCode);

  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();
  Future<String?> token();
  Stream<String> get tokenRefresh;

  /// A push arrived while the app was in the foreground.
  Stream<void> get foregroundMessages;

  /// The user tapped a push while the app was in the background.
  Stream<void> get openedMessages;

  /// True once if the app was started by tapping a push.
  Future<bool> launchedFromMessage();

  String get platformName;
}

/// Sends this device's token to the server. The server binds it to the
/// caller's CURRENT app session and drops the account's other devices.
abstract class PushRegistrar {
  Future<void> register(String token, String platform, String languageCode);
}

class SupabasePushRegistrar implements PushRegistrar {
  SupabasePushRegistrar({SupabaseClient? client}) : _injected = client;
  final SupabaseClient? _injected;

  @override
  Future<void> register(
      String token, String platform, String languageCode) async {
    final client = _injected ?? Supabase.instance.client;
    await client.rpc('register_push_device', params: {
      'p_token': token,
      'p_platform': platform,
      'p_locale': languageCode == 'ar' ? 'ar' : 'en',
    });
  }
}

/// Keeps the server's record of this phone's FCM token in step with the
/// signed-in account, and turns push taps into "open the inbox" once the user
/// is signed in.
///
/// Security model: registering is only a hint. The server re-checks the
/// account's single active app session and the notification preferences when
/// it sends, so a stale registration (a sign-out that never reached the
/// server, a displaced phone) can never receive a new private notification.
/// A push payload carries ids only and never grants access: the inbox is read
/// again under RLS after sign-in.
class PushMessagingService {
  PushMessagingService({
    required PushPlatform platform,
    required PushRegistrar registrar,
    bool Function()? isOnline,
    List<Duration> retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 15),
      Duration(seconds: 60),
    ],
  })  : _platform = platform,
        _registrar = registrar,
        _isOnline = isOnline ?? (() => AppAccessPolicy.isOnline),
        _retryDelays = retryDelays;

  /// The app's one instance, set at startup on a platform where push is
  /// supported; null otherwise (and in tests that do not set it).
  static PushMessagingService? current;

  final PushPlatform _platform;
  final PushRegistrar _registrar;
  final bool Function() _isOnline;
  final List<Duration> _retryDelays;

  /// Opens the inbox. Set by the app once the router exists.
  void Function()? openInbox;

  /// Called when a push arrives in the foreground (the inbox refreshes its
  /// count; no second, local banner is shown).
  void Function()? onForegroundMessage;

  bool _started = false;
  bool _active = false;
  String? _userId;
  String _languageCode = 'en';
  String? _registeredKey;
  bool _pendingOpen = false;
  int _generation = 0;
  Timer? _retry;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  bool get isActive => _active;
  @visibleForTesting
  bool get hasPendingOpen => _pendingOpen;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _active = await _platform.initialize();
    } catch (_) {
      _active = false;
    }
    if (!_active) return;
    _subscriptions
      ..add(_platform.tokenRefresh
          .listen((_) => _sync(force: true), onError: (Object _) {}))
      ..add(_platform.foregroundMessages
          .listen((_) => onForegroundMessage?.call(), onError: (Object _) {}))
      ..add(_platform.openedMessages
          .listen((_) => _requestOpen(), onError: (Object _) {}));
    try {
      if (await _platform.launchedFromMessage()) _requestOpen();
    } catch (_) {}
    unawaited(_platform.updateChannel(_languageCode).catchError((Object _) {}));
    _sync();
  }

  /// Called whenever the signed-in account or the app language changes.
  /// [userId] is null while signed out or during a password recovery.
  void attach({required String? userId, required String languageCode}) {
    final languageChanged = languageCode != _languageCode;
    final userChanged = userId != _userId;
    // A new sign-in is a new app session: the token must be bound again even
    // when the account is the same as before.
    if (userChanged) _registeredKey = null;
    _userId = userId;
    _languageCode = languageCode;
    if (!_active) return;
    if (languageChanged) {
      unawaited(
          _platform.updateChannel(languageCode).catchError((Object _) {}));
    }
    if (userChanged || languageChanged) _sync();
    if (userId != null && _pendingOpen) _openNow();
  }

  /// Asks for the notification permission at a moment the user understands
  /// (after setting a reminder), then registers.
  ///
  /// Android never reports "not decided": firebase_messaging answers only
  /// granted or denied, and denied also means "never asked". So the system is
  /// asked whenever the permission is not granted. The system itself decides
  /// whether to show its prompt (Android stops after the user refuses for
  /// good, iOS after the first answer), so this cannot nag.
  Future<PushPermission> requestPermissionAndRegister() async {
    if (!_active) return PushPermission.denied;
    PushPermission result;
    try {
      result = await _platform.permission();
      if (result != PushPermission.granted) {
        result = await _platform.requestPermission();
      }
    } catch (_) {
      return PushPermission.denied;
    }
    if (result == PushPermission.granted) _sync(force: true);
    return result;
  }

  void _requestOpen() {
    _pendingOpen = true;
    if (_userId != null) _openNow();
  }

  void _openNow() {
    final open = openInbox;
    if (open == null) return;
    _pendingOpen = false;
    open();
  }

  void _sync({bool force = false}) {
    _retry?.cancel();
    final generation = ++_generation;
    unawaited(_attempt(generation, 0, force));
  }

  Future<void> _attempt(int generation, int retry, bool force) async {
    final userId = _userId;
    if (!_active || userId == null || !_isOnline()) return;
    try {
      if (await _platform.permission() != PushPermission.granted) return;
      final token = await _platform.token();
      if (generation != _generation || token == null || token.isEmpty) return;
      final key = '$userId|$_languageCode|$token';
      if (!force && key == _registeredKey) return;
      await _registrar.register(token, _platform.platformName, _languageCode);
      if (generation != _generation) return;
      _registeredKey = key;
    } catch (_) {
      // Usually the app session is not confirmed yet, or the network is
      // down. Try again a few times; the next sign-in, language change or
      // token refresh tries again too.
      if (generation != _generation || retry >= _retryDelays.length) return;
      _retry = Timer(_retryDelays[retry],
          () => unawaited(_attempt(generation, retry + 1, force)));
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
