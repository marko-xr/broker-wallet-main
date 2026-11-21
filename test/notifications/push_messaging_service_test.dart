// Notifications N3 client: FCM token registration and push taps, with a fake
// platform. No Firebase, no Supabase, no device.
import 'dart:async';

import 'package:broker_wallet/src/services/push/push_messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform implements PushPlatform {
  bool available = true;
  PushPermission current = PushPermission.granted;
  PushPermission answer = PushPermission.granted;
  String? deviceToken = 'token-1';
  bool launched = false;
  int prompts = 0;
  final List<String> channels = [];
  final refresh = StreamController<String>.broadcast(sync: true);
  final foreground = StreamController<void>.broadcast(sync: true);
  final opened = StreamController<void>.broadcast(sync: true);

  @override
  Future<bool> initialize() async => available;
  @override
  Future<void> updateChannel(String languageCode) async =>
      channels.add(languageCode);
  @override
  Future<PushPermission> permission() async => current;
  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return current = answer;
  }

  @override
  Future<String?> token() async => deviceToken;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<void> get foregroundMessages => foreground.stream;
  @override
  Stream<void> get openedMessages => opened.stream;
  @override
  Future<bool> launchedFromMessage() async => launched;
  @override
  String get platformName => 'android';
}

class _Registrar implements PushRegistrar {
  final List<String> calls = [];
  int failuresLeft = 0;

  @override
  Future<void> register(
      String token, String platform, String languageCode) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('session_superseded');
    }
    calls.add('$token|$platform|$languageCode');
  }
}

Future<(PushMessagingService, _Platform, _Registrar)> _started({
  bool online = true,
  void Function(_Platform)? setUp,
}) async {
  final platform = _Platform();
  setUp?.call(platform);
  final registrar = _Registrar();
  final service = PushMessagingService(
    platform: platform,
    registrar: registrar,
    isOnline: () => online,
    retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
  );
  addTearDown(service.dispose);
  await service.start();
  return (service, platform, registrar);
}

Future<void> _settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await pumpEventQueue();
}

void main() {
  test('a device without push stays inactive and never registers', () async {
    final (service, _, registrar) =
        await _started(setUp: (p) => p.available = false);
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(service.isActive, isFalse);
    expect(registrar.calls, isEmpty);
    expect(await service.requestPermissionAndRegister(), PushPermission.denied);
  });

  test('a signed-in account registers once with the app language', () async {
    final (service, platform, registrar) = await _started();
    service.attach(userId: 'a', languageCode: 'ar');
    await _settle();
    service.attach(userId: 'a', languageCode: 'ar');
    await _settle();
    expect(registrar.calls, ['token-1|android|ar']);
    expect(platform.channels.last, 'ar');
  });

  test('nothing is registered signed out, offline or without permission',
      () async {
    final (signedOut, _, signedOutCalls) = await _started();
    signedOut.attach(userId: null, languageCode: 'en');
    await _settle();
    expect(signedOutCalls.calls, isEmpty);

    final (offline, _, offlineCalls) = await _started(online: false);
    offline.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(offlineCalls.calls, isEmpty);

    final (denied, _, deniedCalls) =
        await _started(setUp: (p) => p.current = PushPermission.denied);
    denied.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(deniedCalls.calls, isEmpty);
  });

  test('a new sign-in binds the token again, even for the same account',
      () async {
    final (service, _, registrar) = await _started();
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    service.attach(userId: null, languageCode: 'en');
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    service.attach(userId: 'b', languageCode: 'en');
    await _settle();
    expect(registrar.calls, hasLength(3));
  });

  test('language change and token refresh register again', () async {
    final (service, platform, registrar) = await _started();
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    service.attach(userId: 'a', languageCode: 'ar');
    await _settle();
    platform.deviceToken = 'token-2';
    platform.refresh.add('token-2');
    await _settle();
    expect(registrar.calls,
        ['token-1|android|en', 'token-1|android|ar', 'token-2|android|ar']);
  });

  test('a refused registration is retried a bounded number of times', () async {
    final (service, _, registrar) = await _started();
    registrar.failuresLeft = 2;
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(registrar.calls, ['token-1|android|en']);

    registrar.failuresLeft = 10;
    service.attach(userId: 'b', languageCode: 'en');
    await _settle();
    expect(registrar.failuresLeft, 7, reason: 'one try plus two retries');
  });

  test('permission is asked when not granted, then registers', () async {
    final (service, platform, registrar) =
        await _started(setUp: (p) => p.current = PushPermission.notDetermined);
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(registrar.calls, isEmpty);
    expect(
        await service.requestPermissionAndRegister(), PushPermission.granted);
    await _settle();
    expect(platform.prompts, 1);
    expect(registrar.calls, ['token-1|android|en']);

    expect(
        await service.requestPermissionAndRegister(), PushPermission.granted);
    expect(platform.prompts, 1, reason: 'never asks once granted');
  });

  test('Android: "denied" before any prompt still asks the system', () async {
    // firebase_messaging on Android reports only granted or denied; a fresh
    // install that was never asked reads as denied.
    final (service, platform, registrar) =
        await _started(setUp: (p) => p.current = PushPermission.denied);
    service.attach(userId: 'a', languageCode: 'en');
    await _settle();
    expect(registrar.calls, isEmpty, reason: 'nothing before the user asks');
    expect(
        await service.requestPermissionAndRegister(), PushPermission.granted);
    await _settle();
    expect(platform.prompts, 1);
    expect(registrar.calls, ['token-1|android|en']);
  });

  test('a refusal is reported and nothing is registered', () async {
    final (service, platform, registrar) = await _started(setUp: (p) {
      p.current = PushPermission.denied;
      p.answer = PushPermission.denied;
    });
    service.attach(userId: 'a', languageCode: 'en');
    expect(await service.requestPermissionAndRegister(), PushPermission.denied);
    await _settle();
    expect(platform.prompts, 1);
    expect(registrar.calls, isEmpty);
  });

  test('a tap waits for sign-in, then opens the inbox once', () async {
    final (service, platform, _) =
        await _started(setUp: (p) => p.launched = true);
    var opened = 0;
    service.openInbox = () => opened++;
    expect(service.hasPendingOpen, isTrue);
    service.attach(userId: null, languageCode: 'en');
    expect(opened, 0, reason: 'not before sign-in');
    service.attach(userId: 'a', languageCode: 'en');
    expect(opened, 1);
    service.attach(userId: 'a', languageCode: 'ar');
    expect(opened, 1);

    platform.opened.add(null);
    expect(opened, 2, reason: 'a background tap while signed in opens now');
  });

  test('a foreground push only refreshes the count', () async {
    final (service, platform, _) = await _started();
    var refreshed = 0;
    service.onForegroundMessage = () => refreshed++;
    platform.foreground.add(null);
    expect(refreshed, 1);
  });
}
