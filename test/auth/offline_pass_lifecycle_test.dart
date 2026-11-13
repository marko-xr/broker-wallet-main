// OFF-2b-3: the authoritative offline pass lifecycle. A pass is issued only
// when the server answers a session CHECK with a current `true` (never for a
// sign-in claim, a refreshed token or a failure), for the exact session that
// was checked, and only while that session is still the current one. It is
// invalidated on sign-out, displacement, 401/403, password recovery, a new
// sign-in, a vanished session and the start of Delete Account.
// No real network: loopback-only clients behind fake HTTP and a throwing
// Realtime transport, under a socket tripwire. Nothing here enables offline
// Home or touches the router.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/account_deletion_state_store.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/viewmodels/delete_account_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _s2 = '22222222-2222-4222-8222-222222222222';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _sessionJson({String sid = _s1, int? iat}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': _uid,
          'session_id': sid,
          'exp': now + 3600,
          'iat': iat ?? now,
          'role': 'authenticated',
          'aud': 'authenticated',
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-secret',
    'user': {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'session@example.test',
      'email_confirmed_at': '2026-01-01T00:00:00Z',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}

sb.Session _session({String sid = _s1}) =>
    sb.Session.fromJson(_sessionJson(sid: sid))!;

/// One ordered record of what reached storage and the network.
final List<String> _log = [];

class _Store implements OfflinePassStore {
  String? value;
  Completer<void>? holdWrite;
  Completer<void>? holdDelete;
  bool failDelete = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    final hold = holdWrite;
    if (hold != null) await hold.future;
    _log.add('pass-write');
    value = v;
  }

  @override
  Future<void> delete() async {
    final hold = holdDelete;
    if (hold != null) await hold.future;
    if (failDelete) throw const FileSystemException('keystore failure');
    _log.add('pass-delete');
    value = null;
  }

  Map<String, Object?> get json => jsonDecode(value!) as Map<String, Object?>;
}

const _otherUid = '660e8400-e29b-41d4-a716-446655440000';

/// The revocation marker (correction A), in memory.
class _Marker implements OfflinePassRevocationMarker {
  int? value;
  bool failWrite = false;
  Completer<void>? holdWrite;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int revocation) async {
    final hold = holdWrite;
    if (hold != null) await hold.future;
    if (failWrite) throw const FileSystemException('fsync failed');
    value = revocation;
  }
}

class _Gateway implements AccountDeletionGateway {
  int calls = 0;

  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async =>
      calls++;
}

class _Owner implements AccountDeletionSession {
  @override
  String? get currentUserId => _uid;

  @override
  bool get isPasswordRecoveryActive => false;

  @override
  Future<void> completeAccountDeletion(String deletedUid) async {}

  @override
  Future<AccountDeletionConvergence> reconcileAccountDeletion(
          String uid) async =>
      AccountDeletionConvergence.sessionEnded;
}

/// The whole network: every request is logged; the session check answers
/// [check] (true, false, a 401 body, or a held gate).
class _Net extends http.BaseClient {
  Object? check = true;
  int checkStatus = 200;
  Completer<void>? holdCheck;
  Completer<void>? holdRelease;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    _log.add(path);
    Object? body = const <Object>[];
    var status = 200;
    if (path.endsWith('/rpc/is_current_app_session')) {
      final hold = holdCheck;
      if (hold != null) await hold.future;
      body = check;
      status = checkStatus;
    } else if (path.endsWith('/rpc/claim_current_app_session')) {
      body = true;
    } else if (path.endsWith('/rpc/release_current_app_session')) {
      final hold = holdRelease;
      if (hold != null) await hold.future;
      body = null;
    } else if (path.contains('/auth/v1/')) {
      body = <String, Object?>{};
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(body == null ? '' : jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

class _NoSocket {
  Never call(String url, Map<String, String> headers) =>
      throw const SocketException('test transport: no WebSocket is opened');
}

sb.SupabaseClient _client(_Net net) => sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: net,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: _NoSocket().call),
    );

class _Profiles implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

Future<void> _bounded(Future<void> Function() body) async {
  final attempts = <String>[];
  await _noNetwork(attempts, body);
  expect(attempts, isEmpty, reason: 'no real socket may be attempted');
}

/// A pass for [_uid]/[sid], written the way the lifecycle writes one.
Future<void> _seedPass(_Store store, {String sid = _s1}) async {
  final lifecycle = OfflinePassLifecycle(OfflineSessionLease(store: store));
  final s = _session(sid: sid);
  expect(await lifecycle.confirmed(s, currentSession: () => s), isTrue);
  _log.clear();
}

/// A repository whose pipeline has started on a restored session.
Future<
    (
      SupabaseAuthRepository,
      sb.SupabaseClient,
      StreamSubscription<UserModel?>
    )> _startRepository(_Net net, {String sid = _s1}) async {
  final client = _client(net);
  await client.auth.setInitialSession(jsonEncode(_sessionJson(sid: sid)));
  final repo =
      SupabaseAuthRepository(userRepository: _Profiles(), client: client);
  final sub = repo.authStateChanges.listen((_) {}, onError: (_) {});
  await pumpEventQueue(times: 40);
  return (repo, client, sub);
}

Future<void> _emit(sb.SupabaseClient client, sb.AuthChangeEvent event,
    {sb.Session? session}) async {
  // GoTrue's own emitter (internal to the SDK), so each auth event is exact.
  // ignore: invalid_use_of_internal_member
  client.auth.notifyAllSubscribers(event, session: session);
  await pumpEventQueue(times: 40);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Static recovery state must not leak from one test into the next.
    await PasswordRecoveryStateStore.forget();
    _log.clear();
    store = _Store();
    OfflinePassLifecycle.debugShared =
        OfflinePassLifecycle(OfflineSessionLease(store: store));
  });
  tearDown(() => OfflinePassLifecycle.debugShared = null);

  group('L. the lifecycle itself', () {
    test('L1 a confirmation for the current session issues a bound pass',
        () async {
      final s = _session();
      expect(
          await OfflinePassLifecycle.shared
              .confirmed(s, currentSession: () => s),
          isTrue);
      expect(store.json['uid'], _uid);
      expect(store.json['sid'], _s1);
    });

    test(
        'L2 a late confirmation for a session that is no longer current '
        'issues nothing', () async {
      expect(
          await OfflinePassLifecycle.shared
              .confirmed(_session(), currentSession: () => _session(sid: _s2)),
          isFalse);
      expect(
          await OfflinePassLifecycle.shared
              .confirmed(_session(), currentSession: () => null),
          isFalse);
      expect(store.value, isNull);
      expect(_log, isNot(contains('pass-write')),
          reason: 'not even written and then removed');
    });

    test(
        'L3b a session that changes while the pass is being written leaves '
        'no pass', () async {
      final s = _session();
      sb.Session? current = s;
      store.holdWrite = Completer<void>();
      final issuing = OfflinePassLifecycle.shared
          .confirmed(s, currentSession: () => current);
      await pumpEventQueue();
      current = _session(sid: _s2);
      store.holdWrite!.complete();
      expect(await issuing, isFalse);
      expect(store.value, isNull);
    });

    test(
        'L3 an invalidation that arrives while the pass is being written '
        'wins', () async {
      final s = _session();
      store.holdWrite = Completer<void>();
      final issuing =
          OfflinePassLifecycle.shared.confirmed(s, currentSession: () => s);
      await pumpEventQueue();
      final invalidating = OfflinePassLifecycle.shared
          .invalidate(OfflinePassInvalidation.signOut);
      store.holdWrite!.complete();
      expect(await issuing, isFalse);
      await invalidating;
      expect(store.value, isNull);
    });

    test('L4 after an invalidation only a new confirmation issues again',
        () async {
      final s = _session();
      await OfflinePassLifecycle.shared.confirmed(s, currentSession: () => s);
      await OfflinePassLifecycle.shared
          .invalidate(OfflinePassInvalidation.credentialsRejected);
      expect(store.value, isNull);
      expect(OfflinePassLifecycle.shared.lastInvalidation,
          OfflinePassInvalidation.credentialsRejected);
      expect(
          await OfflinePassLifecycle.shared
              .confirmed(s, currentSession: () => s),
          isTrue);
    });

    test(
        'L5 one process-wide instance; the platform lease carries the '
        'Android journal; nothing else in lib/ builds a lease', () {
      OfflinePassLifecycle.debugShared = null;
      expect(
          identical(OfflinePassLifecycle.shared, OfflinePassLifecycle.shared),
          isTrue);
      final src = File('lib/src/services/offline_pass_lifecycle.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), '');
      expect(
          src,
          contains('chargeJournal:platformChargeJournal('
              'isAndroid:Platform.isAndroid)'));
      final builders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        final code = f.readAsStringSync();
        if (RegExp(r'\bOfflineSessionLease\(').hasMatch(code) &&
            !path.endsWith('offline_pass_lifecycle.dart') &&
            !path.endsWith('offline_session_lease.dart')) {
          builders.add(path);
        }
        if (RegExp(r'\bOfflinePassLifecycle\(').hasMatch(code) &&
            !path.endsWith('offline_pass_lifecycle.dart')) {
          builders.add(path);
        }
      }
      expect(builders, isEmpty);
      expect(
          File('lib/src/repositories/supabase_auth_repository.dart')
              .readAsStringSync(),
          contains('OfflinePassLifecycle.shared'));
    });
  });

  group('C. the coordinator reports only authoritative confirmations', () {
    test('C1 a confirmed restored-session check reports that exact session',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net();
        final client = _client(net);
        await client.auth.setInitialSession(jsonEncode(_sessionJson()));
        final confirmed = <sb.Session>[];
        final c = AppSessionCoordinator(client,
            onSuperseded: () {}, onConfirmed: (s, _) => confirmed.add(s));
        final checked = client.auth.currentSession!;
        expect(await c.authorize(checked, claim: false), isTrue);
        expect(confirmed, hasLength(1));
        expect(identical(confirmed.single, checked), isTrue);
        await c.dispose();
        await client.dispose();
      });
    });

    test('C2 refused, 401 and a sign-in claim report nothing', timeout: _hard,
        () async {
      await _bounded(() async {
        for (final kind in ['refused', '401', 'claim']) {
          final net = _Net();
          if (kind == 'refused') net.check = false;
          if (kind == '401') {
            net.check = {'code': 'PGRST301', 'message': 'JWT expired'};
            net.checkStatus = 401;
          }
          final client = _client(net);
          await client.auth.setInitialSession(jsonEncode(_sessionJson()));
          final confirmed = <sb.Session>[];
          final c = AppSessionCoordinator(client,
              onSuperseded: () {}, onConfirmed: (s, _) => confirmed.add(s));
          try {
            await c.authorize(client.auth.currentSession!,
                claim: kind == 'claim');
          } catch (_) {}
          expect(confirmed, isEmpty, reason: kind);
          await c.dispose();
          await client.dispose();
        }
      });
    });

    test('C3 validateNow reports a confirmation, never a refusal',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net();
        final client = _client(net);
        await client.auth.setInitialSession(jsonEncode(_sessionJson()));
        final confirmed = <sb.Session>[];
        final c = AppSessionCoordinator(client,
            onSuperseded: () {}, onConfirmed: (s, _) => confirmed.add(s));
        await c.authorize(client.auth.currentSession!, claim: false);
        confirmed.clear();
        expect(await c.validateNow(), isTrue);
        expect(confirmed, hasLength(1));
        net.check = false;
        expect(await c.validateNow(), isFalse);
        expect(confirmed, hasLength(1));
        await c.dispose();
        await client.dispose();
      });
    });
  });

  group('R. the repository drives the pass through the session lifecycle', () {
    test('R1 a confirmed restored session issues the pass', timeout: _hard,
        () async {
      await _bounded(() async {
        final (repo, client, sub) = await _startRepository(_Net());
        expect(store.value, isNotNull);
        expect(store.json['sid'], _s1);
        await sub.cancel();
        await client.dispose();
      });
    });

    test('R2 a 401 on the session check deletes an existing pass',
        timeout: _hard, () async {
      await _bounded(() async {
        await _seedPass(store);
        final net = _Net()
          ..check = {'code': 'PGRST301', 'message': 'JWT expired'}
          ..checkStatus = 401;
        final (repo, client, sub) = await _startRepository(net);
        expect(store.value, isNull);
        expect(OfflinePassLifecycle.shared.lastInvalidation,
            OfflinePassInvalidation.credentialsRejected);
        await sub.cancel();
        await client.dispose();
      });
    });

    test('R3 a displaced session loses its pass before the local sign-out',
        timeout: _hard, () async {
      await _bounded(() async {
        await _seedPass(store);
        final net = _Net()..check = false;
        final (repo, client, sub) = await _startRepository(net);
        expect(store.value, isNull);
        final delete = _log.indexOf('pass-delete');
        final logout = _log.indexWhere((p) => p.contains('/auth/v1/logout'));
        expect(delete, isNonNegative);
        if (logout >= 0) expect(delete, lessThan(logout));
        await sub.cancel();
        await client.dispose();
      });
    });

    test('R4 sign-out deletes the pass before releasing the session',
        timeout: _hard, () async {
      await _bounded(() async {
        final (repo, client, sub) = await _startRepository(_Net());
        expect(store.value, isNotNull);
        _log.clear();
        try {
          await repo.signOut();
        } catch (_) {}
        expect(store.value, isNull);
        final delete = _log.indexOf('pass-delete');
        final release = _log
            .indexWhere((p) => p.contains('/rpc/release_current_app_session'));
        expect(delete, 0, reason: 'first, before any request: $_log');
        expect(release, greaterThan(delete));
        await sub.cancel();
        await client.dispose();
      });
    });

    test('R4b sign-out sends nothing until the pass deletion has finished',
        timeout: _hard, () async {
      await _bounded(() async {
        final (repo, client, sub) = await _startRepository(_Net());
        expect(store.value, isNotNull);
        _log.clear();
        store.holdDelete = Completer<void>();
        final signingOut = repo.signOut().then<void>((_) {}, onError: (_) {});
        await pumpEventQueue(times: 40);
        expect(_log, isEmpty, reason: 'no request while the pass still exists');
        store.holdDelete!.complete();
        await signingOut;
        expect(_log.first, 'pass-delete');
        expect(store.value, isNull);
        await sub.cancel();
        await client.dispose();
      });
    });

    test(
        'R5 a password recovery, a vanished session and a new sign-in each '
        'delete the pass; the sign-in claim does not issue one',
        timeout: _hard, () async {
      await _bounded(() async {
        for (final event in [
          sb.AuthChangeEvent.passwordRecovery,
          sb.AuthChangeEvent.signedOut,
          sb.AuthChangeEvent.signedIn,
        ]) {
          _log.clear();
          // A fresh process each time: a recovery latch lasts a process.
          OfflinePassLifecycle.debugShared =
              OfflinePassLifecycle(OfflineSessionLease(store: store));
          final (repo, client, sub) = await _startRepository(_Net());
          expect(store.value, isNotNull, reason: event.name);
          await _emit(client, event,
              session: event == sb.AuthChangeEvent.signedOut
                  ? null
                  : client.auth.currentSession);
          expect(store.value, isNull, reason: event.name);
          await sub.cancel();
          await client.dispose();
          await PasswordRecoveryStateStore.forget();
        }
      });
    });

    test(
        'R6 a refreshed token verified online renews the pass (validateNow); '
        'the refresh alone never would',
        timeout: _hard, () async {
      await _bounded(() async {
        final (repo, client, sub) = await _startRepository(_Net());
        expect(store.value, isNotNull);
        store.value = null; // as if spent
        await _emit(client, sb.AuthChangeEvent.tokenRefreshed,
            session: client.auth.currentSession);
        expect(store.value, isNotNull, reason: 'renewed by a server check');
        await sub.cancel();
        await client.dispose();
      });
    });

    test('R7 an answer that arrives after sign-out issues nothing',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net()..holdCheck = Completer<void>();
        final (repo, client, sub) = await _startRepository(net);
        await client.auth.signOut(scope: sb.SignOutScope.local);
        await pumpEventQueue(times: 40);
        net.holdCheck!.complete();
        await pumpEventQueue(times: 40);
        expect(store.value, isNull);
        await sub.cancel();
        await client.dispose();
      });
    });
  });

  group('D. Delete Account', () {
    test('D1 the pass is gone before the deletion marker is even written',
        () async {
      await _seedPass(store);
      store.holdDelete = Completer<void>();
      final marking = const AccountDeletionMarkers().remember(_uid);
      await pumpEventQueue();
      expect(AccountDeletionStateStore.ownerUid, isNull,
          reason: 'the marker waits for the pass deletion');
      store.holdDelete!.complete();
      await marking;
      expect(store.value, isNull);
      expect(AccountDeletionStateStore.ownerUid, _uid);
      await AccountDeletionStateStore.forgetIfOwnedBy(_uid);
    });

    test('D2 the deleted-account cleaner removes the pass too', () async {
      await _seedPass(store);
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
        forgetQuotationPdfs: (_) async => 0,
        forgetPrivateMedia: (_) async => 0,
      ).clear(deletedUid: _uid, wasSignedInAccount: true);
      expect(store.value, isNull);
      expect(OfflinePassLifecycle.shared.lastInvalidation,
          OfflinePassInvalidation.accountDeletion);
    });
  });

  group('H. hardening (corrections A–E)', () {
    OfflinePassLifecycle withMarker(_Marker marker) =>
        OfflinePassLifecycle.debugShared = OfflinePassLifecycle(
            OfflineSessionLease(store: store, revocationMarker: marker),
            deleteBound: const Duration(milliseconds: 20));

    test(
        'H1 a pass delete that never completes no longer freezes sign-out: '
        'the revocation is durable first, then the session is ended',
        timeout: _hard, () async {
      await _bounded(() async {
        final marker = _Marker();
        withMarker(marker);
        final (repo, client, sub) = await _startRepository(_Net());
        expect(store.value, isNotNull);
        store.holdDelete = Completer<void>();
        await repo.signOut();
        expect(marker.value, greaterThanOrEqualTo(1));
        expect(client.auth.currentSession, isNull);
        expect(_log.any((p) => p.contains('/rpc/release_current_app_session')),
            isTrue);
        store.holdDelete!.complete();
        await pumpEventQueue(times: 40);
        await sub.cancel();
        await client.dispose();
      });
    });

    test(
        'H2 sign-out sends nothing and keeps the session until the '
        'revocation is durable (a kill before it leaves nothing half-done)',
        timeout: _hard, () async {
      await _bounded(() async {
        final marker = _Marker();
        withMarker(marker);
        final (repo, client, sub) = await _startRepository(_Net());
        _log.clear();
        marker.holdWrite = Completer<void>();
        final signingOut = repo.signOut().then<void>((_) {}, onError: (_) {});
        await pumpEventQueue(times: 40);
        expect(client.auth.currentSession, isNotNull);
        expect(_log.where((p) => p.startsWith('/')), isEmpty,
            reason: 'no release, no logout: $_log');
        marker.holdWrite!.complete();
        await signingOut;
        expect(client.auth.currentSession, isNull);
        await sub.cancel();
        await client.dispose();
      });
    });

    test(
        'H3 when neither the marker nor the delete succeeds, the session is '
        'still ended locally but sign-out reports failure',
        timeout: _hard, () async {
      await _bounded(() async {
        final marker = _Marker();
        final life = withMarker(marker);
        final (repo, client, sub) = await _startRepository(_Net());
        marker.failWrite = true;
        store.failDelete = true;
        await expectLater(repo.signOut(), throwsA(isA<AuthFailure>()));
        expect(client.auth.currentSession, isNull);
        expect(life.lastRevocation?.safe, isFalse);
        await sub.cancel();
        await client.dispose();
      });
    });

    test(
        'H4 a check that started before sign-out and answers true during it '
        'cannot re-issue the pass',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net();
        final (repo, client, sub) = await _startRepository(net);
        expect(store.value, isNotNull);
        net.holdCheck = Completer<void>();
        net.holdRelease = Completer<void>();
        await _emit(client, sb.AuthChangeEvent.tokenRefreshed,
            session: client.auth.currentSession);
        _log.clear();
        final signingOut = repo.signOut().then<void>((_) {}, onError: (_) {});
        await pumpEventQueue(times: 40);
        expect(store.value, isNull);
        net.holdCheck!.complete(); // the old validateNow now answers true
        await pumpEventQueue(times: 40);
        expect(store.value, isNull);
        expect(_log, isNot(contains('pass-write')));
        net.holdRelease!.complete();
        await signingOut;
        await sub.cancel();
        await client.dispose();
      });
    });

    test('H5 a 401/403 inside validateNow deletes the pass; a 5xx does not',
        timeout: _hard, () async {
      await _bounded(() async {
        for (final (status, body, deleted) in [
          (401, {'code': 'PGRST301', 'message': 'JWT expired'}, true),
          (403, {'code': 'PGRST303', 'message': 'JWT claims invalid'}, true),
          (403, {'code': '42501', 'message': 'permission denied'}, false),
          (503, {'message': 'unavailable'}, false),
        ]) {
          _log.clear();
          store.value = null;
          OfflinePassLifecycle.debugShared =
              OfflinePassLifecycle(OfflineSessionLease(store: store));
          final net = _Net();
          final (repo, client, sub) = await _startRepository(net);
          expect(store.value, isNotNull, reason: '$status');
          net
            ..check = body
            ..checkStatus = status;
          await _emit(client, sb.AuthChangeEvent.tokenRefreshed,
              session: client.auth.currentSession);
          expect(store.value == null, deleted, reason: '$status');
          expect(
              OfflinePassLifecycle.shared.lastInvalidation ==
                  OfflinePassInvalidation.credentialsRejected,
              deleted,
              reason: '$status');
          await sub.cancel();
          await client.dispose();
        }
      });
    });

    test(
        'H6 validateNow still throws on a rejection (OFF-1 unchanged) and '
        'reports only 401/403',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net();
        final client = _client(net);
        await client.auth.setInitialSession(jsonEncode(_sessionJson()));
        var rejected = 0;
        final c = AppSessionCoordinator(client,
            onSuperseded: () {}, onCredentialsRejected: () async => rejected++);
        expect(await c.authorize(client.auth.currentSession!, claim: false),
            isTrue);
        net
          ..check = {'code': 'PGRST301', 'message': 'JWT expired'}
          ..checkStatus = 401;
        await expectLater(c.validateNow(), throwsA(anything));
        expect(rejected, 1);
        net
          ..check = {'message': 'unavailable'}
          ..checkStatus = 503;
        await expectLater(c.validateNow(), throwsA(anything));
        expect(rejected, 1);
        await c.dispose();
        await client.dispose();
      });
    });

    test(
        "H7 a late deleted-account cleanup never removes another account's "
        'pass', () async {
      await _seedPass(store);
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
        forgetQuotationPdfs: (_) async => 0,
        forgetPrivateMedia: (_) async => 0,
      ).clear(deletedUid: _otherUid, wasSignedInAccount: false);
      expect(store.value, isNotNull);
      expect(OfflinePassLifecycle.shared.lastInvalidation, isNull);
    });

    test(
        'H8 Delete Account does not start when offline access cannot be '
        'revoked safely', () async {
      final marker = _Marker()..failWrite = true;
      OfflinePassLifecycle.debugShared = OfflinePassLifecycle(
          OfflineSessionLease(store: store, revocationMarker: marker));
      store.failDelete = true;
      final gateway = _Gateway();
      final vm = DeleteAccountViewModel(gateway: gateway, session: _Owner());
      vm.continueToConfirmation();
      vm.setAcknowledged(true);
      expect(await vm.submit(password: 'pw'), isFalse);
      expect(gateway.calls, 0, reason: 'no server request');
      expect(AccountDeletionStateStore.ownerUid, isNull);
      expect(vm.step, DeleteAccountStep.confirm);
      expect(vm.errorKey, isNotNull);
      vm.dispose();
    });

    test(
        'H10 the epoch alone refuses a confirmation that outlived an '
        'invalidation (restore check and validateNow)',
        timeout: _hard, () async {
      await _bounded(() async {
        // The restore check, held while a (non-latching) 401 invalidates.
        final net = _Net()..holdCheck = Completer<void>();
        final (repo, client, sub) = await _startRepository(net);
        await OfflinePassLifecycle.shared
            .invalidate(OfflinePassInvalidation.credentialsRejected);
        net.holdCheck!.complete();
        net.holdCheck = null;
        await pumpEventQueue(times: 40);
        expect(store.value, isNull, reason: 'restore check');
        // validateNow, held the same way.
        net.holdCheck = Completer<void>();
        await _emit(client, sb.AuthChangeEvent.tokenRefreshed,
            session: client.auth.currentSession);
        await OfflinePassLifecycle.shared
            .invalidate(OfflinePassInvalidation.credentialsRejected);
        net.holdCheck!.complete();
        await pumpEventQueue(times: 40);
        expect(store.value, isNull, reason: 'validateNow');
        await sub.cancel();
        await client.dispose();
      });
    });

    test('H11 the latch alone refuses a check that STARTED during sign-out',
        timeout: _hard, () async {
      await _bounded(() async {
        final net = _Net();
        final (repo, client, sub) = await _startRepository(net);
        net.holdRelease = Completer<void>();
        final signingOut = repo.signOut().then<void>((_) {}, onError: (_) {});
        await pumpEventQueue(times: 40);
        expect(store.value, isNull);
        // A new check (new epoch) while the release is still running.
        await _emit(client, sb.AuthChangeEvent.tokenRefreshed,
            session: client.auth.currentSession);
        expect(store.value, isNull);
        net.holdRelease!.complete();
        await signingOut;
        await sub.cancel();
        await client.dispose();
      });
    });

    test('H12 a password recovery latches its own session', timeout: _hard,
        () async {
      await _bounded(() async {
        final (repo, client, sub) = await _startRepository(_Net());
        final s = client.auth.currentSession!;
        await _emit(client, sb.AuthChangeEvent.passwordRecovery, session: s);
        expect(
            await OfflinePassLifecycle.shared
                .confirmed(s, currentSession: () => s),
            isFalse);
        await sub.cancel();
        await client.dispose();
      });
    });

    test('H9 Delete Account start latches the account being deleted', () async {
      await const AccountDeletionMarkers().remember(_uid);
      final s = _session();
      expect(
          await OfflinePassLifecycle.shared
              .confirmed(s, currentSession: () => s),
          isFalse);
      await AccountDeletionStateStore.forgetIfOwnedBy(_uid);
    });
  });

  test(
      'Z. still dormant: nothing in lib/ admits a cold start offline or '
      'enters offline mode', () {
    final users = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final code = f.readAsStringSync();
      final path = f.path.replaceAll(r'\', '/');
      if (code.contains('admitColdStart(') &&
          !path.endsWith('offline_session_lease.dart')) {
        users.add('$path admitColdStart');
      }
      if (code.contains('enterOfflineReadOnly(') &&
          !path.endsWith('app_access_policy.dart')) {
        users.add('$path enterOfflineReadOnly');
      }
    }
    expect(users, isEmpty);
  });
}
