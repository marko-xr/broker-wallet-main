// P3.2: how many Home count requests are actually sent.
//
// The real HomeViewModel and CountCacheService, the real Supabase client and
// its real auth stream (gotrue's ReplaySubject, which hands every new
// listener all earlier auth events), and the real SupabaseHomeCountsService
// — with an HTTP stand-in that answers and counts every count request (one
// per table, seven per Home count read). Nothing reaches the network.
import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/supabase_home_counts_service.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _tables = 7;
// Real session_id claims are UUIDs (anything else reads as no session).
const _sA = 'a1a1a1a1-0000-4000-8000-000000000001';
const _sA2 = 'a2a2a2a2-0000-4000-8000-000000000002';
const _sB = 'b1b1b1b1-0000-4000-8000-000000000003';

class _Repo implements AuthRepository {
  String? uid;
  @override
  String? get currentUserId => uid;
  @override
  UserModel? get currentUser => null;
  @override
  Stream<UserModel?> get authStateChanges => const Stream<UserModel?>.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Supabase backend: counts every Home count request; each answers
/// [count] rows unless [fail] is set; [hold] keeps answers until released.
class _Backend {
  int requests = 0;
  int count = 3;
  bool fail = false;
  Completer<void>? hold;

  /// When set, the count answered for a request made under each session.
  Map<String, int>? countBySession;

  static String? _sessionOf(http.BaseRequest request) {
    final auth = request.headers['Authorization'] ?? '';
    return AppSessionCoordinator.sessionIdFromAccessToken(
        auth.startsWith('Bearer ') ? auth.substring(7) : auth);
  }

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      // gotrue's token refresh: a new access token, the same session.
      if (request.url.path.endsWith('/auth/v1/token')) {
        return http.Response(jsonEncode(_sessionMap(_uid!, _session!)), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final counting = request.method == 'GET' &&
          request.url.path.startsWith('/rest/v1/') &&
          (request.headers['Prefer'] ?? '').contains('count=exact');
      if (!counting) return http.Response('[]', 200, request: request);
      requests++;
      final answer = countBySession?[_sessionOf(request)] ?? count;
      final gate = hold;
      if (gate != null) await gate.future;
      if (fail) {
        return http.Response('{"message":"unavailable"}', 500,
            request: request);
      }
      return http.Response('[]', 200,
          headers: {
            'content-type': 'application/json',
            'content-range': '*/$answer',
          },
          request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  String? _uid;
  String? _session;
  int _issued = 0;

  Map<String, dynamic> _sessionMap(String uid, String sessionId) {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({
          'sub': uid,
          'exp': exp.millisecondsSinceEpoch ~/ 1000,
          'iat': ++_issued,
          'session_id': sessionId,
        })}.sig';
    return {
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh-$sessionId-$_issued',
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'email': '$uid@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    };
  }

  /// Signs [uid] in on session [sessionId] (a restored or new session).
  Future<void> session(String uid, String sessionId) {
    _uid = uid;
    _session = sessionId;
    return client.auth
        .setInitialSession(jsonEncode(_sessionMap(uid, sessionId)));
  }

  /// gotrue's token refresh, as hourly: a tokenRefreshed event, same
  /// session.
  Future<void> tokenRefreshed() => client.auth.refreshSession();

  String? get sessionId =>
      AppSessionCoordinator.sessionId(client.auth.currentSession);
}

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  await pumpEventQueue();
}

int _shown(HomeViewModel vm, String key) =>
    vm.items.firstWhere((item) => item.labelKey == key).count ?? -1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Backend backend;
  late _Repo repo;
  late CountCacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CountCacheService.forTesting();
    await cache.initialize();
    backend = _Backend();
    repo = _Repo();
  });

  HomeViewModel openHome() {
    final counts = SupabaseHomeCountsService(client: backend.client);
    final vm = HomeViewModel(
      authRepository: repo,
      countCache: cache,
      readCounts: (fallback) => counts.getCounts(fallback: fallback),
      authStateChanges: backend.client.auth.onAuthStateChange,
      confirmSession: (_) => Future<bool>.value(true),
      sessionOf: () => backend.sessionId,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  /// Requests sent by [action], once everything has settled.
  Future<int> measure(String label, Future<void> Function() action) async {
    final before = backend.requests;
    await action();
    await _settle();
    final sent = backend.requests - before;
    // ignore: avoid_print
    print('P3.2 MEASURED $label: $sent count requests '
        '(${sent / _tables} Home count reads)');
    return sent;
  }

  group('measured count requests', () {
    test('cold start with a restored session: one Home count read', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      late HomeViewModel vm;
      final sent = await measure(
          'cold start (1 replayed auth event)', () async => vm = openHome());
      expect(sent, _tables);
      expect(_shown(vm, 'offers'), 3);
    });

    test(
        'cold start after earlier auth events (replayed to the new listener): '
        'still one read', () async {
      await backend.session(_alice, _sA);
      await backend.tokenRefreshed();
      await backend.tokenRefreshed();
      repo.uid = _alice;
      final sent = await measure(
          'cold start (3 replayed auth events)', () async => openHome());
      expect(sent, _tables);
    });

    test(
        'Home opened again later (a new view model, every event replayed): '
        'one read for it', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final first = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: (fallback) =>
            SupabaseHomeCountsService(client: backend.client)
                .getCounts(fallback: fallback),
        authStateChanges: backend.client.auth.onAuthStateChange,
        confirmSession: (_) => Future<bool>.value(true),
        sessionOf: () => backend.sessionId,
      );
      await _settle();
      first.dispose();
      final sent = await measure('second Home view model', () async {
        openHome();
      });
      expect(sent, _tables);
    });

    test('a later token refresh still reads, as before', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      openHome();
      await _settle();
      final sent =
          await measure('token refresh', () async => backend.tokenRefreshed());
      expect(sent, _tables);
    });

    test('each Home tab return or pull still reads once', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = openHome();
      await _settle();
      final sent = await measure('one refreshCounts', vm.refreshCounts);
      expect(sent, _tables);
    });

    test('many triggers during one read: one more read after it, not one each',
        () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = openHome();
      await _settle();
      final sent =
          await measure('3 mutations + 2 refreshes during a read', () async {
        backend.hold = Completer<void>();
        CoreEntityMutationNotifier.notify();
        await pumpEventQueue();
        CoreEntityMutationNotifier.notify();
        CoreEntityMutationNotifier.notify();
        unawaited(vm.refreshCounts());
        unawaited(vm.refreshCounts());
        await pumpEventQueue();
        backend.hold!.complete();
        backend.hold = null;
      });
      expect(sent, 2 * _tables, reason: 'the read in flight, then one more');
    });

    test(
        'a change during a read is never lost: the read after it shows the '
        'new counts', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = openHome();
      await _settle();
      backend.hold = Completer<void>();
      CoreEntityMutationNotifier.notify(); // read 1 starts, sees 3
      await pumpEventQueue();
      backend.count = 4; // a record added while read 1 is in flight
      CoreEntityMutationNotifier.notify();
      backend.hold!.complete();
      backend.hold = null;
      await _settle();
      expect(_shown(vm, 'offers'), 4);
    });

    test('a single change after reads have settled still reads once', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      openHome();
      await _settle();
      final sent = await measure(
          'one mutation', () async => CoreEntityMutationNotifier.notify());
      expect(sent, _tables);
    });
  });

  group('accounts, sessions, failures and disposal', () {
    test('another account or a new session of the same account always reads',
        () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      openHome();
      await _settle();
      final relogin = await measure('same account, new session', () async {
        await backend.session(_alice, _sA2);
      });
      expect(relogin, _tables);
      final other = await measure('another account', () async {
        repo.uid = _bob;
        await backend.session(_bob, _sB);
      });
      expect(other, _tables);
    });

    test(
        'a read in flight for the old session does not cover the new one, '
        'and its late answer is dropped', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = openHome();
      await _settle();
      final start = backend.requests;
      backend
        ..countBySession = {_sA: 5, _sA2: 8}
        ..hold = Completer<void>();
      CoreEntityMutationNotifier.notify(); // a read under sA, held
      await pumpEventQueue();
      await backend.session(_alice, _sA2); // a new session: its own read
      await _settle();
      backend.hold!.complete(); // both answer now; sA's is late
      backend.hold = null;
      await _settle();
      expect(backend.requests - start, 2 * _tables,
          reason: 'the sA read and a separate sA2 read');
      expect(_shown(vm, 'offers'), 8, reason: 'sA2\'s answer, not sA\'s 5');
      expect((await cache.getAllCachedCounts(_alice))['offers'], 8);
    });

    test(
        'after a failed read the next trigger reads again; failed tables keep '
        'what is shown', () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = openHome();
      await _settle();
      backend.fail = true;
      final failed =
          await measure('failing read', () async => backend.tokenRefreshed());
      expect(failed, _tables);
      expect(_shown(vm, 'offers'), 3);
      backend
        ..fail = false
        ..count = 5;
      final retried =
          await measure('retry', () async => backend.tokenRefreshed());
      expect(retried, _tables);
      expect(_shown(vm, 'offers'), 5);
    });

    test('a disposed Home reads nothing more, even with a read pending',
        () async {
      await backend.session(_alice, _sA);
      repo.uid = _alice;
      final vm = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: (fallback) =>
            SupabaseHomeCountsService(client: backend.client)
                .getCounts(fallback: fallback),
        authStateChanges: backend.client.auth.onAuthStateChange,
        confirmSession: (_) => Future<bool>.value(true),
        sessionOf: () => backend.sessionId,
      );
      await _settle();
      backend.hold = Completer<void>();
      CoreEntityMutationNotifier.notify();
      await pumpEventQueue();
      CoreEntityMutationNotifier.notify(); // would ask for one more read
      vm.dispose();
      final before = backend.requests;
      backend.hold!.complete();
      backend.hold = null;
      await _settle();
      CoreEntityMutationNotifier.notify();
      await backend.tokenRefreshed();
      await _settle();
      expect(backend.requests, before);
    });
  });
}
