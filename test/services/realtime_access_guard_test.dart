// OFF-2b-2 Realtime correction: the WebSocket transport guard, the event gate
// for business streams, and the teardown on entering offline read-only.
// No real network: every client points at a closed loopback port, Realtime
// goes through a fake transport behind the production guard, and each test
// runs under a socket tripwire that refuses and records any real connection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/repositories/supabase_notification_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:broker_wallet/src/services/r2_profile_upload_service.dart';
import 'package:broker_wallet/src/services/realtime_access_guard.dart';
// Same URI casing as the app's own imports of this file.
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Answers 200 `[]` and records every request it actually received.
class _Inner extends http.BaseClient {
  final List<http.BaseRequest> received = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    received.add(request);
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// The fake WebSocket transport: records the attempt and throws, so no socket
/// is ever created.
class _NoSocket {
  final List<String> urls = [];
  Never call(String url, Map<String, String> headers) {
    urls.add(url);
    throw const SocketException('test transport: no WebSocket is opened');
  }
}

/// A client whose Realtime goes through the PRODUCTION guard in front of the
/// fake transport, and whose REST goes through the production HTTP guard in
/// front of a fake client.
sb.SupabaseClient _client(_Inner inner, _NoSocket ws) => sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: AppAccessPolicy.guard(inner),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: guardRealtimeTransport(ws.call)),
    );

Future<T> _noNetwork<T>(List<String> attempts, Future<T> Function() body) =>
    IOOverrides.runZoned(
      body,
      socketConnect: (host, port,
          {sourceAddress, int sourcePort = 0, Duration? timeout}) {
        attempts.add('connect $host:$port');
        throw SocketException('test: no network ($host:$port)');
      },
      socketStartConnect: (host, port, {sourceAddress, int sourcePort = 0}) {
        attempts.add('startConnect $host:$port');
        throw SocketException('test: no network ($host:$port)');
      },
    );

const _hard = Timeout(Duration(seconds: 20));

/// Runs [body] offline-safe: tripwire on, and asserts no socket was tried.
Future<void> _bounded(Future<void> Function() body) async {
  final attempts = <String>[];
  await _noNetwork(attempts, body);
  expect(attempts, isEmpty, reason: 'no real socket may be attempted');
}

String _lib(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(AppAccessPolicy.debugReset);
  tearDown(AppAccessPolicy.debugReset);

  group('T. the Realtime transport guard', () {
    test('T1 online it delegates to the transport; offline it refuses first',
        timeout: _hard, () async {
      await _bounded(() async {
        final ws = _NoSocket();
        final guarded = guardRealtimeTransport(ws.call);
        expect(() => guarded('ws://127.0.0.1:9/realtime/v1/websocket', {}),
            throwsA(isA<SocketException>()),
            reason: 'reached the transport');
        expect(ws.urls, hasLength(1));
        AppAccessPolicy.enterOfflineReadOnly();
        expect(() => guarded('ws://127.0.0.1:9/realtime/v1/websocket', {}),
            throwsA(isA<OfflineReadOnlyBlockedException>()));
        expect(ws.urls, hasLength(1), reason: 'the transport was not called');
      });
    });

    test(
        'T2 the default delegated online is the SDK\'s own transport, and '
        'reading it opens nothing',
        timeout: _hard, () async {
      await _bounded(() async {
        expect(
            identical(sdkDefaultRealtimeTransport(),
                sb.RealtimeClient('ws://127.0.0.1:9').transport),
            isTrue);
      });
    });

    test(
        'T3 online a channel connects through the transport; offline neither '
        'a new channel nor the app-resume reconnect reaches it',
        timeout: _hard, () async {
      await _bounded(() async {
        final ws = _NoSocket();
        final client = _client(_Inner(), ws);
        client.channel('online').subscribe();
        await pumpEventQueue();
        expect(ws.urls, isNotEmpty, reason: 'online Realtime still connects');
        final before = ws.urls.length;
        await client.realtime.disconnect();
        AppAccessPolicy.enterOfflineReadOnly();
        client.channel('offline').subscribe();
        // Exactly what supabase_flutter's app-resume handler calls (supabase.dart
        // 2.17.2, _processLifecycle): the reconnect path under test.
        // ignore: invalid_use_of_internal_member
        await client.realtime.connect();
        await pumpEventQueue();
        expect(ws.urls, hasLength(before), reason: 'no connect while offline');
        await client.removeAllChannels().timeout(const Duration(seconds: 5));
        await client.dispose().timeout(const Duration(seconds: 5));
      });
    });

    test(
        'T4 HTTP and Realtime guards are independent: offline, a raw '
        '.stream() reaches neither the REST client nor the transport',
        timeout: _hard, () async {
      await _bounded(() async {
        final inner = _Inner();
        final ws = _NoSocket();
        final client = _client(inner, ws);
        AppAccessPolicy.enterOfflineReadOnly();
        final sub = client
            .from('offers')
            .stream(primaryKey: const ['id']).listen((_) {}, onError: (_) {});
        await pumpEventQueue();
        expect(inner.received, isEmpty);
        expect(ws.urls, isEmpty);
        await sub.cancel();
        await client.removeAllChannels().timeout(const Duration(seconds: 5));
        await client.dispose().timeout(const Duration(seconds: 5));
      });
    });
  });

  group('G. the event gate for business streams', () {
    test('G1 offline at listen time: the source is never opened', () async {
      var opened = 0;
      AppAccessPolicy.enterOfflineReadOnly();
      final events = <Object?>[];
      final sub = AppAccessPolicy.onlineOnly(() {
        opened++;
        return Stream.value(1);
      }).listen(events.add,
          onError: events.add, onDone: () => events.add('done'));
      await pumpEventQueue();
      expect(opened, 0);
      expect(events, isEmpty);
      await sub.cancel();
    });

    test(
        'G2 created online, listened offline: still never opened (no late '
        'subscription)', () async {
      var opened = 0;
      final stream = AppAccessPolicy.onlineOnly(() {
        opened++;
        return Stream.value(1);
      });
      AppAccessPolicy.enterOfflineReadOnly();
      final sub = stream.listen((_) {});
      await pumpEventQueue();
      expect(opened, 0);
      await sub.cancel();
    });

    test(
        'G3 an event already queued when the switch happens is not delivered; '
        'the source is cancelled; nothing after it gets through', () async {
      final source = StreamController<int>();
      var cancelled = false;
      source.onCancel = () => cancelled = true;
      final events = <Object?>[];
      final sub = AppAccessPolicy.onlineOnly(() => source.stream).listen(
          events.add,
          onError: events.add,
          onDone: () => events.add('done'));
      source.add(1);
      await pumpEventQueue();
      expect(events, [1], reason: 'online events flow as before');
      source.add(2); // queued, not yet delivered
      AppAccessPolicy.enterOfflineReadOnly();
      await pumpEventQueue();
      expect(events, [1], reason: 'the queued event is dropped');
      expect(cancelled, isTrue, reason: 'the subscription is torn down');
      if (!source.isClosed) {
        source.addError(StateError('late error'));
        await source.close();
      }
      await pumpEventQueue();
      expect(events, [1], reason: 'no late error or end either');
      await sub.cancel();
    });

    test(
        'G4 returning online does not resubscribe: that needs an '
        'authoritative revalidation and a new listen (OFF-2b-5)', () async {
      var opened = 0;
      final key = AppAccessPolicy.claimCoordinatorKey();
      final sub = AppAccessPolicy.onlineOnly(() {
        opened++;
        return StreamController<int>().stream;
      }).listen((_) {});
      await pumpEventQueue();
      expect(opened, 1);
      AppAccessPolicy.enterOfflineReadOnly();
      AppAccessPolicy.enterOnline(key);
      await pumpEventQueue();
      expect(opened, 1);
      await sub.cancel();
    });

    test(
        'G6 an event pushed synchronously DURING the switch (by an earlier '
        'listener) is not delivered', () async {
      final source = StreamController<int>.broadcast(sync: true);
      // Registered before the stream is listened to, so it runs first.
      AppAccessPolicy.addListener((mode) {
        if (mode == AppAccessMode.offlineReadOnly) source.add(2);
      });
      final events = <Object?>[];
      final sub = AppAccessPolicy.onlineOnly(() => source.stream)
          .listen(events.add, onError: events.add);
      source.add(1);
      await pumpEventQueue();
      expect(events, [1]);
      AppAccessPolicy.enterOfflineReadOnly();
      await pumpEventQueue();
      expect(events, [1], reason: 'offline from the instant of the switch');
      await sub.cancel();
      await source.close();
    });

    test(
        'G7 a subscription from before an offline period never delivers, even '
        'if the app is online again by then', () async {
      final key = AppAccessPolicy.claimCoordinatorKey();
      final source = StreamController<int>.broadcast(sync: true);
      // Runs first on the switch: returns online and pushes on the OLD
      // subscription before it can be cancelled.
      AppAccessPolicy.addListener((mode) {
        if (mode == AppAccessMode.offlineReadOnly) {
          AppAccessPolicy.enterOnline(key);
          source.add(99);
        }
      });
      final events = <Object?>[];
      final sub = AppAccessPolicy.onlineOnly(() => source.stream)
          .listen(events.add, onError: events.add);
      AppAccessPolicy.enterOfflineReadOnly();
      await pumpEventQueue();
      expect(AppAccessPolicy.isOnline, isTrue);
      expect(events, isEmpty, reason: 'stale subscription, new epoch');
      await sub.cancel();
      await source.close();
    });

    test('G5 cancelling removes its policy listener (no leak)', () async {
      final heard = <AppAccessMode>[];
      final sub =
          AppAccessPolicy.onlineOnly(() => StreamController<int>().stream)
              .listen((_) {});
      await sub.cancel();
      AppAccessPolicy.addListener(heard.add);
      AppAccessPolicy.enterOfflineReadOnly();
      expect(heard, [AppAccessMode.offlineReadOnly]);
    });
  });

  group('P. the four Realtime paths', () {
    test(
        'P1 profile and notifications: created online, listened offline — no '
        'channel, no REST, no transport, no event',
        timeout: _hard, () async {
      await _bounded(() async {
        final inner = _Inner();
        final ws = _NoSocket();
        final client = _client(inner, ws);
        final users = SupabaseUserRepository(
            client: client,
            profileImageService: R2ProfileUploadService(
                httpClient: inner, supabaseClient: client));
        final notes = SupabaseNotificationRepository(client: client);
        // Created online, listened offline (the late-subscription case).
        final profile = users.getUserStream('u1');
        AppAccessPolicy.enterOfflineReadOnly();
        // Online, this one requires a signed-in user at creation (unchanged
        // contract; no session exists here), so it is created offline; its
        // listen-time gate is the same onlineOnly (P3, G2).
        final notifications = notes.watchLatestNotifications('u1');
        final events = <Object?>[];
        final s1 = profile.listen(events.add, onError: events.add);
        final s2 = notifications.listen(events.add, onError: events.add);
        await pumpEventQueue();
        expect(events, isEmpty);
        expect(client.getChannels(), isEmpty);
        expect(inner.received, isEmpty);
        expect(ws.urls, isEmpty);
        await s1.cancel();
        await s2.cancel();
        await client.dispose().timeout(const Duration(seconds: 5));
      });
    });

    test(
        'P2 Favorites ids: created online, listened offline — the Supabase '
        'client is never touched',
        timeout: _hard, () async {
      await _bounded(() async {
        final favorites = FavoriteService(
            currentUserId: () => 'u1', currentSessionId: () => 's1');
        final stream = favorites.getFavoriteIdsByType('offer');
        AppAccessPolicy.enterOfflineReadOnly();
        final events = <Object?>[];
        // Supabase.instance is not initialized here: any open would throw.
        final sub = stream.listen(events.add, onError: events.add);
        await pumpEventQueue();
        expect(events, isEmpty);
        await sub.cancel();
      });
    });

    test('P3 all three business streams go through the event gate', () {
      expect(_lib('lib/src/repositories/supabase_user_repository.dart'),
          contains('AppAccessPolicy.onlineOnly('));
      expect(_lib('lib/src/repositories/supabase_notification_repository.dart'),
          contains('AppAccessPolicy.onlineOnly('));
      expect(
          _lib('lib/src/views/Screens/home/favorites/favorites_service.dart'),
          contains('AppAccessPolicy.onlineOnly('));
    });

    test(
        'P4 the session coordinator keeps its own watch ungated: its only '
        'effect is displacing the session (tightening), never relaxing', () {
      final src = _lib('lib/src/services/app_session_coordinator.dart')
          .replaceAll('\r\n', '\n');
      final start = src.indexOf('void _watchOwnRow(');
      final end = src.indexOf('\n  }\n', start);
      final body = src.substring(start, end);
      expect(body, isNot(contains('onlineOnly')));
      expect(body, contains('supersede()'));
    });
  });

  group('D. teardown on entering offline read-only', () {
    test(
        'D1 disconnect first, then remove channels; status completes only '
        'when both did', () async {
      final calls = <String>[];
      final teardown = RealtimeOfflineTeardown(
        disconnect: () async => calls.add('disconnect'),
        removeAllChannels: () async => calls.add('remove'),
      )..attach();
      expect(teardown.status, RealtimeTeardownStatus.notStarted);
      AppAccessPolicy.enterOfflineReadOnly();
      expect(teardown.status, RealtimeTeardownStatus.inProgress,
          reason: 'started synchronously with the switch');
      await teardown.done;
      expect(calls, ['disconnect', 'remove']);
      expect(teardown.status, RealtimeTeardownStatus.completed);
      teardown.detach();
    });

    test('D2 a failed or hung teardown is reported failed, never completed',
        () async {
      final failing = RealtimeOfflineTeardown(
        disconnect: () async => throw StateError('close failed'),
        removeAllChannels: () async {},
      )..attach();
      AppAccessPolicy.enterOfflineReadOnly();
      await failing.done;
      expect(failing.status, RealtimeTeardownStatus.failed);
      failing.detach();

      AppAccessPolicy.debugReset();
      final hung = RealtimeOfflineTeardown(
        disconnect: () => Completer<void>().future,
        removeAllChannels: () async {},
        timeout: const Duration(milliseconds: 50),
      )..attach();
      AppAccessPolicy.enterOfflineReadOnly();
      await hung.done;
      expect(hung.status, RealtimeTeardownStatus.failed);
      hung.detach();
    });

    test(
        'D3 with a real client: open channels are removed, nothing connects, '
        'and an app resume cannot reconnect',
        timeout: _hard, () async {
      await _bounded(() async {
        final ws = _NoSocket();
        final client = _client(_Inner(), ws);
        final teardown = RealtimeOfflineTeardown.forClient(client)..attach();
        client.channel('a').subscribe();
        client.channel('b').subscribe();
        await pumpEventQueue();
        expect(client.getChannels(), hasLength(2));
        final before = ws.urls.length;
        AppAccessPolicy.enterOfflineReadOnly();
        await teardown.done.timeout(const Duration(seconds: 5));
        expect(teardown.status, RealtimeTeardownStatus.completed);
        expect(client.getChannels(), isEmpty);
        // The app-resume reconnect (see T3).
        // ignore: invalid_use_of_internal_member
        await client.realtime.connect();
        expect(ws.urls, hasLength(before));
        teardown.detach();
        await client.dispose().timeout(const Duration(seconds: 5));
      });
    });

    test('D4 the bootstrap installs the transport guard and the teardown', () {
      final boot = _lib('lib/src/services/supabase_bootstrap_service.dart');
      expect(
          boot,
          contains('transport: guardRealtimeTransport('
              'sdkDefaultRealtimeTransport())'));
      expect(
          boot.replaceAll(RegExp(r'\s+'), ''),
          contains('RealtimeOfflineTeardown.forClient('
              'Supabase.instance.client)..attach();'),
          reason: 'installed AND attached to the policy');
    });
  });
}
