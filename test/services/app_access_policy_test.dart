// OFF-2b-2: strict central read-only enforcement. The policy is dormant in
// production (nothing enters offline mode yet); these tests drive it directly.
// No real network: every offline request is refused before it reaches a
// transport, and online requests go to in-memory fakes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/supabase_notification_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/offer_media_session.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:broker_wallet/src/services/r2_profile_upload_service.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_gate.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
// Same URI casing as optimistic_favorites_service.dart ('../Views/...').
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../toolkit_documents/toolkit_fakes.dart';

final _supabase = Uri.parse('https://abcdefghijklmnop.supabase.co');

/// Answers 200 with [body] and records every request it actually received.
class _Inner extends http.BaseClient {
  _Inner([this.body = '[]']);
  final String body;
  final List<http.BaseRequest> received = [];
  Completer<void>? hold;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    received.add(request);
    final h = hold;
    if (h != null) await h.future;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

Uri _u(String path, [Map<String, String>? query]) =>
    _supabase.replace(path: path, queryParameters: query);

Future<Object?> _send(http.Client c, String method, Uri url) async {
  try {
    final r = await c.send(http.Request(method, url));
    await r.stream.drain<void>();
    return r.statusCode;
  } catch (e) {
    return e;
  }
}

class _Favorites extends FavoriteService {
  _Favorites() : super(currentUserId: () => 'u1', currentSessionId: () => 's1');
  int calls = 0;
  @override
  Future<void> addToFavorites(String itemId, String type) async => calls++;
  @override
  Future<void> removeFromFavorites(String itemId, String type) async => calls++;
}

/// The Realtime transport of every test client: it records the attempt and
/// throws at once, so no WebSocket is ever created (no DNS, no socket). A
/// throwing transport makes RealtimeClient.connect() take its general error
/// path, which schedules no reconnect timer.
class _NoSocket {
  final List<String> urls = [];
  Never call(String url, Map<String, String> headers) {
    urls.add(url);
    throw const SocketException('test transport: no WebSocket is opened');
  }
}

/// Test clients point at a closed loopback port, never at a real host; REST
/// goes to [inner] (a fake) and Realtime to [ws] (the throwing transport).
sb.SupabaseClient _client(http.Client inner, _NoSocket ws) => sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: AppAccessPolicy.guard(inner),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: sb.RealtimeClientOptions(transport: ws.call),
    );

/// Runs [body] where any real socket (HttpClient, WebSocket, raw Socket) is
/// refused and recorded: the proof that a test reaches no network at all.
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

String _lib(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(AppAccessPolicy.debugReset);
  tearDown(AppAccessPolicy.debugReset);

  group('P. the policy and the guarded client', () {
    test('P1 online by default: requests pass unchanged', () async {
      expect(AppAccessPolicy.mode, AppAccessMode.online);
      expect(AppAccessPolicy.isOnline, isTrue);
      final inner = _Inner();
      final c = AppAccessPolicy.guard(inner);
      final req = http.Request('PATCH', _u('/rest/v1/offers'));
      final r = await c.send(req);
      expect(r.statusCode, 200);
      expect(identical(inner.received.single, req), isTrue,
          reason: 'the very same request object reaches the transport');
    });

    test(
        'P2 offline: EVERY request is refused before the transport — reads '
        'included, any host, any method', () async {
      AppAccessPolicy.configureSupabaseOrigin(_supabase);
      AppAccessPolicy.enterOfflineReadOnly();
      final inner = _Inner();
      final c = AppAccessPolicy.guard(inner);
      final urls = [
        _u('/rest/v1/offers', {'select': '*'}),
        _u('/rest/v1/favorites'),
        _u('/rest/v1/rpc/is_current_app_session'),
        _u('/rest/v1/rpc/claim_current_app_session'),
        _u('/rest/v1/rpc/release_current_app_session'),
        _u('/rest/v1/rpc/save_quotation'),
        _u('/auth/v1/token', {'grant_type': 'refresh_token'}),
        _u('/auth/v1/user'),
        _u('/auth/v1/logout'),
        _u('/storage/v1/object/x'),
        _u('/functions/v1/x'),
        Uri.parse('https://media-api.brokerwallet.ae/offer-media/url'),
        Uri.parse('https://bucket.r2.cloudflarestorage.com/a.jpg?X-Amz=1'),
        Uri.parse('https://example.com/file.pdf'),
      ];
      for (final url in urls) {
        for (final m in ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE']) {
          final e = await _send(c, m, url);
          expect(e, isA<OfflineReadOnlyBlockedException>(), reason: '$m $url');
          expect(e, isA<http.ClientException>(), reason: 'network-class');
        }
      }
      expect(inner.received, isEmpty);
    });

    test('P3 only the coordinator key returns the app to online', () {
      AppAccessPolicy.enterOfflineReadOnly();
      final key = AppAccessPolicy.claimCoordinatorKey();
      expect(AppAccessPolicy.claimCoordinatorKey, throwsStateError,
          reason: 'issued once');
      expect(() => AppAccessPolicy.enterOnline(_forgedKey()), throwsStateError);
      expect(AppAccessPolicy.isOnline, isFalse);
      AppAccessPolicy.enterOnline(key);
      expect(AppAccessPolicy.isOnline, isTrue);
    });

    test(
        'P4 the coordinator capability allows exactly its one endpoint, on '
        'the configured origin, inside its own zone only', () async {
      AppAccessPolicy.configureSupabaseOrigin(_supabase);
      final key = AppAccessPolicy.claimCoordinatorKey();
      AppAccessPolicy.enterOfflineReadOnly();
      final inner = _Inner();
      final c = AppAccessPolicy.guard(inner);
      Future<Object?> within(
              CoordinatorNetworkCapability cap, String m, Uri url) =>
          AppAccessPolicy.runWithCapability(key, cap, () => _send(c, m, url));
      const check = CoordinatorNetworkCapability.sessionCheck;
      const refresh = CoordinatorNetworkCapability.tokenRefresh;
      const release = CoordinatorNetworkCapability.sessionRelease;
      final isCurrent = _u('/rest/v1/rpc/is_current_app_session');
      // Allowed: the exact endpoint of each capability.
      expect(await within(check, 'POST', isCurrent), 200);
      expect(
          await within(refresh, 'POST',
              _u('/auth/v1/token', {'grant_type': 'refresh_token'})),
          200);
      expect(
          await within(
              release, 'POST', _u('/rest/v1/rpc/release_current_app_session')),
          200);
      expect(
          await within(
              release, 'POST', _u('/auth/v1/logout', {'scope': 'local'})),
          200);
      expect(inner.received, hasLength(4));
      // Refused: everything else, even inside the zone.
      final refused = <(CoordinatorNetworkCapability, String, Uri)>[
        (check, 'GET', isCurrent),
        (check, 'POST', _u('/rest/v1/rpc/claim_current_app_session')),
        (check, 'POST', _u('/rest/v1/rpc/is_current_app_session/')),
        (check, 'POST', _u('/rest/v1/rpc/IS_CURRENT_APP_SESSION')),
        (check, 'POST', _u('/rest/v1/rpc/is_current_app_session', {'x': '1'})),
        (check, 'POST', _u('/rest/v1/offers')),
        (check, 'POST', _u('/auth/v1/token', {'grant_type': 'refresh_token'})),
        (
          check,
          'POST',
          Uri.parse('https://evil.example/rest/v1/rpc/is_current_app_session')
        ),
        (check, 'POST', isCurrent.replace(scheme: 'http')),
        (check, 'POST', isCurrent.replace(port: 8443)),
        (refresh, 'POST', _u('/auth/v1/token', {'grant_type': 'password'})),
        (
          refresh,
          'POST',
          _u('/auth/v1/token', {'grant_type': 'refresh_token', 'x': '1'})
        ),
        (refresh, 'PUT', _u('/auth/v1/user')),
        (refresh, 'POST', isCurrent),
        (release, 'POST', _u('/rest/v1/rpc/claim_current_app_session')),
        (release, 'DELETE', _u('/auth/v1/logout')),
        (release, 'POST', _u('/auth/v1/logout', {'scope': 'global'})),
      ];
      for (final (cap, m, url) in refused) {
        expect(
            await within(cap, m, url), isA<OfflineReadOnlyBlockedException>(),
            reason: '${cap.name} $m $url');
      }
      // Outside the zone the same endpoint is refused.
      expect(await _send(c, 'POST', isCurrent),
          isA<OfflineReadOnlyBlockedException>());
      expect(inner.received, hasLength(4));
      // A forged key opens nothing: refused before the body ever runs.
      var ran = false;
      expect(
          () =>
              AppAccessPolicy.runWithCapability(_forgedKey(), check, () async {
                ran = true;
                return 1;
              }),
          throwsStateError);
      expect(ran, isFalse);
      expect(inner.received, hasLength(4));
    });

    test('P5 with no configured origin even the capability opens nothing',
        () async {
      final key = AppAccessPolicy.claimCoordinatorKey();
      AppAccessPolicy.enterOfflineReadOnly();
      final inner = _Inner();
      final c = AppAccessPolicy.guard(inner);
      expect(
          await AppAccessPolicy.runWithCapability(
              key,
              CoordinatorNetworkCapability.sessionCheck,
              () =>
                  _send(c, 'POST', _u('/rest/v1/rpc/is_current_app_session'))),
          isA<OfflineReadOnlyBlockedException>());
      expect(inner.received, isEmpty);
    });

    test(
        'P6 a response that arrives after the switch to offline is discarded '
        '(no stale result is applied)', () async {
      final inner = _Inner()..hold = Completer<void>();
      final c = AppAccessPolicy.guard(inner);
      final pending = _send(c, 'GET', _u('/rest/v1/offers'));
      await pumpEventQueue();
      AppAccessPolicy.enterOfflineReadOnly();
      inner.hold!.complete();
      expect(await pending, isA<OfflineReadOnlyBlockedException>());
    });

    test('P7 listeners hear each change once; offline entry is idempotent', () {
      final heard = <AppAccessMode>[];
      void listener(AppAccessMode m) => heard.add(m);
      AppAccessPolicy.addListener(listener);
      final key = AppAccessPolicy.claimCoordinatorKey();
      final e0 = AppAccessPolicy.epoch;
      AppAccessPolicy.enterOfflineReadOnly();
      AppAccessPolicy.enterOfflineReadOnly();
      AppAccessPolicy.enterOnline(key);
      AppAccessPolicy.removeListener(listener);
      AppAccessPolicy.enterOfflineReadOnly();
      expect(heard, [AppAccessMode.offlineReadOnly, AppAccessMode.online]);
      expect(AppAccessPolicy.epoch, e0 + 3);
    });

    test('P8 a listener that throws cannot stop the switch or the others', () {
      final heard = <AppAccessMode>[];
      AppAccessPolicy.addListener((_) => throw StateError('bad listener'));
      AppAccessPolicy.addListener(heard.add);
      AppAccessPolicy.enterOfflineReadOnly();
      expect(AppAccessPolicy.isOnline, isFalse);
      expect(heard, [AppAccessMode.offlineReadOnly]);
    });

    test('P9 guard() never wraps twice; ensureOnline is typed', () {
      final g = AppAccessPolicy.guard(_Inner());
      expect(identical(AppAccessPolicy.guard(g), g), isTrue);
      AppAccessPolicy.ensureOnline('x');
      AppAccessPolicy.enterOfflineReadOnly();
      expect(
          () => AppAccessPolicy.ensureOnline('favorite'),
          throwsA(isA<OfflineReadOnlyBlockedException>()
              .having((e) => e.operation, 'operation', 'favorite')));
    });

    test(
        'P10 inside the runWithClient zone, http.Client(), top-level http.get '
        "and flutter_cache_manager's HttpFileService are all guarded",
        timeout: _hard, () async {
      AppAccessPolicy.enterOfflineReadOnly();
      final attempts = <String>[];
      await _noNetwork(
          attempts,
          () => http.runWithClient(() async {
                expect(http.Client(), isA<PolicyGuardedClient>());
                expect(AppAccessPolicy.shared, isA<PolicyGuardedClient>());
                await expectLater(
                    http.get(Uri.parse('https://example.com/a.pdf')),
                    throwsA(isA<OfflineReadOnlyBlockedException>()));
                await expectLater(
                    HttpFileService().get('https://example.com/a.jpg'),
                    throwsA(isA<OfflineReadOnlyBlockedException>()));
              }, AppAccessPolicy.newZoneClient));
      expect(attempts, isEmpty, reason: 'refused before any socket');
    });

    test(
        'P11 the typed denial is distinct from a network failure, a token '
        'rejection and a Worker answer, and OFF-1 keeps it network-class', () {
      final blocked = OfflineReadOnlyBlockedException('x');
      expect(blocked, isNot(isA<SocketException>()));
      expect(blocked, isNot(isA<sb.AuthException>()));
      expect(blocked, isNot(isA<sb.PostgrestException>()));
      expect(classifySessionCheckError(blocked), AppSessionCheckOutcome.offline,
          reason: 'proves nothing about the server: never a refusal');
    });
  });

  group('S. every network path goes through the guard', () {
    test(
        'S1 no raw client or top-level http call anywhere in lib/ outside the '
        'policy', () {
      final offenders = <String>[];
      // Whitespace (line breaks included) may sit anywhere in a call: the
      // formatter splits `await AppAccessPolicy.shared` / `.get(` over lines.
      final raw = RegExp(r'\bhttp\s*\.\s*Client\s*\(\s*\)|'
          r'\bhttp\s*\.\s*Client\s*\.\s*new\b|\bIOClient\s*\(|'
          r'\bHttpClient\s*\(\s*\)|\bhttp\s*\.\s*(get|post|put|patch|delete|'
          r'head|read|readBytes)\s*\(');
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        if (path.endsWith('lib/src/services/app_access_policy.dart')) continue;
        // Comments out, lines joined: a call split over lines is one call.
        final code = f
            .readAsLinesSync()
            .map((l) => l.trimLeft().startsWith('//') ? '' : l)
            .join(' ');
        for (final m in raw.allMatches(code)) {
          final before =
              code.substring(m.start < 48 ? 0 : m.start - 48, m.start);
          if (before.contains('AppAccessPolicy.guard(')) continue;
          offenders.add('$path: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty);
    });

    test('S2 each of the seven HTTP-owning services guards its client', () {
      const files = [
        'lib/src/services/account_deletion_service.dart',
        'lib/src/services/plan_attachment/r2_plan_attachment_service.dart',
        'lib/src/services/r2_offer_media_upload_service.dart',
        'lib/src/services/r2_profile_upload_service.dart',
        'lib/src/services/toolkit_documents/r2_toolkit_document_service.dart',
        'lib/src/views/Screens/home/quotation/services/r2_quotation_media_service.dart',
        'lib/src/views/Screens/home/quotation/services/quotation_service.dart',
      ];
      for (final f in files) {
        expect(_lib(f),
            contains('AppAccessPolicy.guard(httpClient ?? http.Client())'),
            reason: f);
      }
    });

    test(
        'S3 Supabase uses the guarded client, knows its origin, and drops '
        'Realtime channels on offline entry; main() runs in the guard zone',
        () {
      final boot = _lib('lib/src/services/supabase_bootstrap_service.dart');
      expect(
          boot, contains('httpClient: AppAccessPolicy.guard(http.Client())'));
      expect(
          boot,
          contains(
              'AppAccessPolicy.configureSupabaseOrigin(Uri.parse(SupabaseConfig.url))'));
      expect(boot, contains('RealtimeOfflineTeardown.forClient('));
      final main = _lib('lib/main.dart');
      expect(main,
          contains('http.runWithClient(_main, AppAccessPolicy.newZoneClient)'));
      final share = _lib('lib/src/services/share/share_media_fetcher.dart');
      expect(share, contains('AppAccessPolicy.guard('));
      final cache = _lib('lib/src/services/private_media_cache.dart');
      expect(
          cache,
          contains(
              'HttpFileService(httpClient: AppAccessPolicy.guard(http.Client()))'));
    });

    test('S4 worker isolates and legacy upload services have no network code',
        () {
      const files = [
        'lib/src/services/combine_pdf/combine_executor.dart',
        'lib/src/services/image_to_pdf/image_pdf_executor.dart',
        'lib/src/services/signature/signature_executor.dart',
        'lib/src/services/toolkit/bounded_isolate.dart',
        'lib/src/services/fast_media_upload_service.dart',
        'lib/src/services/fast_profile_upload_service.dart',
      ];
      final network = RegExp(r"package:(http|supabase_flutter|supabase|"
          r"cloud_firestore|firebase_storage|dio)/|dart:io.*HttpClient|"
          r"\bHttpClient\b|WebSocket");
      for (final f in files) {
        expect(network.hasMatch(_lib(f)), isFalse, reason: f);
      }
    });

    test(
        'S5 an end-to-end Worker client: Delete Account offline never leaves '
        'the phone and fails as a network failure', () async {
      final inner = _Inner('{}');
      final gateway = WorkerAccountDeletionGateway(
        httpClient: inner,
        readCredentials: () => const AccountDeletionCredentials(
            userId: 'u1', accessToken: 'token'),
      );
      AppAccessPolicy.enterOfflineReadOnly();
      await expectLater(
          gateway.deleteAccount(expectedUid: 'u1', password: 'pw'),
          throwsA(isA<AccountDeletionFailure>().having(
              (f) => f.code, 'code', AccountDeletionFailureCode.network)));
      expect(inner.received, isEmpty);
    });

    test(
        'S6 Supabase reads, writes and RPCs through a guarded SupabaseClient '
        'never leave the phone offline',
        timeout: _hard, () async {
      final attempts = <String>[];
      final ws = _NoSocket();
      await _noNetwork(attempts, () async {
        final inner = _Inner();
        final client = _client(inner, ws);
        AppAccessPolicy.enterOfflineReadOnly();
        Future<Object?> run(Future<Object?> Function() f) async {
          try {
            return await f();
          } catch (e) {
            return e;
          }
        }

        for (final op in <Future<Object?> Function()>[
          () => client.from('offers').select(),
          () => client.from('favorites').insert({'a': 1}),
          () => client.from('profiles').update({'a': 1}).eq('id', 'u1'),
          () => client.from('favorites').delete().eq('id', 'x'),
          () => client.rpc('save_quotation', params: {}),
          () => client.rpc('claim_current_app_session'),
        ]) {
          expect(await run(op), isNot(isA<List>()));
        }
        expect(inner.received, isEmpty);
        await client.dispose();
      });
      expect(attempts, isEmpty, reason: 'no real socket was attempted');
      expect(ws.urls, isEmpty);
    });
  });

  group('R. Realtime subscriptions', () {
    test(
        'R1 offline, the profile and notification streams open no channel and '
        'emit nothing (never a false null user or empty list)',
        timeout: _hard, () async {
      final attempts = <String>[];
      final ws = _NoSocket();
      await _noNetwork(attempts, () async {
        final inner = _Inner();
        final client = _client(inner, ws);
        final users = SupabaseUserRepository(
            client: client,
            profileImageService: R2ProfileUploadService(
                httpClient: inner, supabaseClient: client));
        final notes = SupabaseNotificationRepository(client: client);
        AppAccessPolicy.enterOfflineReadOnly();
        final events = <Object?>[];
        final s1 = users.getUserStream('u1').listen(events.add,
            onError: events.add, onDone: () => events.add('done'));
        final s2 = notes.watchLatestNotifications('u1').listen(events.add,
            onError: events.add, onDone: () => events.add('done'));
        await pumpEventQueue();
        expect(events, isEmpty);
        expect(client.getChannels(), isEmpty);
        expect(inner.received, isEmpty);
        await s1.cancel();
        await s2.cancel();
        await client.dispose();
      });
      expect(attempts, isEmpty, reason: 'no real socket was attempted');
      expect(ws.urls, isEmpty, reason: 'Realtime was never even asked');
    });

    test(
        'R2 online, the profile stream still opens its channel as before — '
        'through the injected transport, never a real WebSocket',
        timeout: _hard, () async {
      final attempts = <String>[];
      final ws = _NoSocket();
      await _noNetwork(attempts, () async {
        final inner = _Inner();
        final client = _client(inner, ws);
        final users = SupabaseUserRepository(
            client: client,
            profileImageService: R2ProfileUploadService(
                httpClient: inner, supabaseClient: client));
        final Stream<UserModel?> s = users.getUserStream('u1');
        final sub = s.listen((_) {}, onError: (_) {});
        await pumpEventQueue();
        expect(client.getChannels(), isNotEmpty);
        await sub.cancel();
        await client
            .removeAllChannels()
            .timeout(const Duration(seconds: 5), onTimeout: () => const []);
        await client.dispose().timeout(const Duration(seconds: 5));
      });
      expect(attempts, isEmpty, reason: 'no real socket was attempted');
      expect(ws.urls, isNotEmpty, reason: 'the channel did try to connect');
      expect(ws.urls.every((u) => u.startsWith('ws://127.0.0.1:9/')), isTrue,
          reason: '${ws.urls}');
    });
  });

  group('B. background work', () {
    test(
        'B1 Offer media uploads pause in offline mode and resume only when '
        'the coordinator returns online', () {
      OfferMediaSession.reset();
      final key = AppAccessPolicy.claimCoordinatorKey();
      OfferMediaSession.onAuthState(uid: 'u1', active: true);
      expect(OfferMediaSession.queueOwner, 'u1');
      AppAccessPolicy.enterOfflineReadOnly();
      expect(OfferMediaSession.queueOwner, isNull, reason: 'paused at once');
      expect(OfferMediaSession.applicationAccount, 'u1',
          reason: 'held private media stays bound to the account');
      OfferMediaSession.onAuthState(uid: 'u1', active: true);
      expect(OfferMediaSession.queueOwner, isNull,
          reason: 'a new auth event cannot restart it offline');
      AppAccessPolicy.enterOnline(key);
      expect(OfferMediaSession.queueOwner, 'u1');
      OfferMediaSession.reset();
    });

    test(
        'B2 Favorites offline: a toggle is refused before any optimistic '
        'change, nothing is queued, nothing is replayed', () async {
      final fav = _Favorites();
      final svc = OptimisticFavoritesService(favoriteService: fav);
      AppAccessPolicy.enterOfflineReadOnly();
      await expectLater(svc.toggleFavorite('o1', 'offer'),
          throwsA(isA<OfflineReadOnlyBlockedException>()));
      expect(svc.isFavorite('o1', 'offer'), isFalse);
      svc.setOnlineStatus(false);
      svc.setOnlineStatus(true); // connectivity back, still not verified
      await svc.syncOfflineQueue();
      await pumpEventQueue();
      expect(fav.calls, 0);
    });

    test('B3 Favorites online still writes immediately', () async {
      final fav = _Favorites();
      final svc = OptimisticFavoritesService(favoriteService: fav);
      expect(await svc.toggleFavorite('o1', 'offer'), isTrue);
      expect(fav.calls, 1);
    });

    test(
        'B2b a change the existing connectivity queue already holds is neither '
        'replayed offline read-only nor dropped', () async {
      final fav = _Favorites();
      final svc = OptimisticFavoritesService(favoriteService: fav);
      final key = AppAccessPolicy.claimCoordinatorKey();
      svc.setOnlineStatus(false); // connectivity lost while the app is online
      expect(await svc.toggleFavorite('o1', 'offer'), isTrue); // queued
      expect(fav.calls, 0);
      AppAccessPolicy.enterOfflineReadOnly();
      svc.setOnlineStatus(true); // connectivity back, not verified
      await svc.syncOfflineQueue();
      await pumpEventQueue();
      expect(fav.calls, 0, reason: 'never replayed offline read-only');
      AppAccessPolicy.enterOnline(key); // authoritative revalidation (OFF-2b-5)
      await svc.syncOfflineQueue();
      await pumpEventQueue();
      expect(fav.calls, 1, reason: 'kept, not dropped');
    });

    test(
        'B4 Toolkit cloud sync offline: due uploads are not attempted and stay '
        'in the journal; online they run', () async {
      final h = await Harness.create();
      final library = DefaultToolkitCloudLibrary(
        accountId: accountA,
        transport: h.transport,
        journal: h.journal,
        files: h.files,
        currentAccountId: () => h.signedIn,
        clock: () => h.now,
      );
      final bytes = pdfBytes();
      await h.files.create('doc1.pdf', bytes);
      AppAccessPolicy.enterOfflineReadOnly();
      await library.queue(entryFor(
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', bytes,
          localRef: 'doc1.pdf'));
      await library.syncDue();
      await library.idle();
      expect(h.transport.calls, isEmpty);
      expect(library.entries, hasLength(1), reason: 'kept, not dropped');
      final key = AppAccessPolicy.claimCoordinatorKey();
      AppAccessPolicy.enterOnline(key);
      await library.syncDue();
      await library.idle();
      expect(h.transport.calls, isNotEmpty);
      await library.dispose();
      await h.dispose();
    });

    test(
        'B5 legacy Firestore usage counters: the policy is checked before '
        'Firestore is touched, so no write can be queued offline', () async {
      // The counters swallow every error ("best effort"), so behaviour alone
      // cannot show the write was skipped: the order is pinned in the source.
      const gates = {
        'lib/src/services/scanner/scanner_usage_gate.dart': 'recordScan',
        'lib/src/services/combine_pdf/combine_usage_gate.dart': 'recordCombine',
        'lib/src/services/image_to_pdf/image_pdf_usage_gate.dart':
            'recordConversion',
        'lib/src/services/signature/signature_usage_gate.dart':
            'recordSignedDocument',
      };
      for (final MapEntry(key: file, value: method) in gates.entries) {
        final src = _lib(file);
        final start =
            src.indexOf('Future<void> $method(String userId) async {');
        expect(start, isNonNegative, reason: file);
        final guard =
            src.indexOf('if (!AppAccessPolicy.isOnline) return;', start);
        final firestore = src.indexOf('FirebaseFirestore.instance', start);
        expect(guard, isNonNegative, reason: file);
        expect(guard, lessThan(firestore), reason: file);
      }
      AppAccessPolicy.enterOfflineReadOnly();
      await const LegacyFirestoreScannerUsageGate().recordScan('u1');
      await const LegacyFirestoreCombineUsageGate().recordCombine('u1');
      await const LegacyFirestoreImagePdfUsageGate().recordConversion('u1');
      await const LegacyFirestoreSignatureUsageGate()
          .recordSignedDocument('u1');
    });

    testWidgets(
        'B6 the local tools still open offline: the quota check answers '
        'without Firestore', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      AppAccessPolicy.enterOfflineReadOnly();
      final allowed = await QuotaHelper.checkAndWarnQuota(
          context: context, uid: 'u1', section: 'scanner', toolName: 'scanner');
      expect(allowed, isTrue);
      expect(_lib('lib/src/services/quota_helper.dart'),
          contains('if (!AppAccessPolicy.isOnline) return true;'));
    });
  });

  group('D. dormant', () {
    test('D1 nothing in lib/ enters offline mode or uses the coordinator key',
        () {
      final users = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        if (path.endsWith('lib/src/services/app_access_policy.dart')) continue;
        final s = f.readAsStringSync();
        for (final call in [
          'enterOfflineReadOnly(',
          'enterOnline(',
          'claimCoordinatorKey(',
          'runWithCapability(',
        ]) {
          if (s.contains(call)) users.add('$path $call');
        }
      }
      expect(users, isEmpty);
    });
  });
}

/// A key that was never issued by the policy.
CoordinatorKey _forgedKey() => debugForgeCoordinatorKey();
