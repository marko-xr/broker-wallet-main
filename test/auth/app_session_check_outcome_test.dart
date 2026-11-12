// OFF-1: the typed session-check contract, the coordinator's attempt rules,
// and source guards on what may change and what may not.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _sid = '11111111-1111-4111-8111-111111111111';
const _sid2 = '22222222-2222-4222-8222-222222222222';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _session({String sid = _sid}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': _uid, 'session_id': sid, 'exp': now + 3600})}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-1',
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
  });
}

/// Answers the session RPC with [body] (a raw string is sent as is), or
/// leaves it pending until aborted when [body] is [_hang].
class _Rpc extends http.BaseClient {
  Object? body = true;

  /// When set, the answer waits for it.
  Completer<void>? hold;
  int calls = 0;
  int aborts = 0;
  int otherRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!request.url.path.endsWith('/rpc/is_current_app_session')) {
      otherRequests++;
      return Future.value(http.StreamedResponse(
          Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'}));
    }
    calls++;
    final out = Completer<http.StreamedResponse>();
    if (request is http.Abortable) {
      request.abortTrigger?.whenComplete(() {
        if (out.isCompleted) return;
        aborts++;
        out.completeError(http.RequestAbortedException(request.url));
      });
    }
    final b = body;
    if (!identical(b, _hang)) {
      void reply() {
        if (out.isCompleted) return;
        out.complete(http.StreamedResponse(
            Stream.value(utf8.encode(b is String ? b : jsonEncode(b))), 200,
            request: request, headers: {'content-type': 'application/json'}));
      }

      final h = hold;
      h == null ? reply() : h.future.then((_) => reply());
    }
    return out.future;
  }
}

const Object _hang = Object();

class _Clock implements Stopwatch {
  Duration now = Duration.zero;
  @override
  Duration get elapsed => now;
  @override
  void start() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('answers: only a real Boolean decides', () {
    test('true confirms, false refuses', () {
      expect(
          classifySessionCheckAnswer(true), AppSessionCheckOutcome.confirmed);
      expect(classifySessionCheckAnswer(false), AppSessionCheckOutcome.refused);
    });

    for (final answer in <Object?>[
      null,
      'true',
      'false',
      0,
      1,
      const <String, Object?>{},
      const <Object?>[],
      const [false],
    ]) {
      test('${jsonEncode(answer)} is inconclusive, never a refusal', () {
        expect(classifySessionCheckAnswer(answer),
            AppSessionCheckOutcome.inconclusive);
      });
    }
  });

  group('errors are classified by type, never by text', () {
    final cases = <String, (Object, AppSessionCheckOutcome)>{
      'SDK retryable, no response': (
        sb.AuthRetryableFetchException(message: 'Failed host lookup'),
        AppSessionCheckOutcome.offline
      ),
      'SDK retryable, /token 503': (
        sb.AuthRetryableFetchException(message: 'x', statusCode: '503'),
        AppSessionCheckOutcome.serverUnavailable
      ),
      'SDK credential rejection': (
        const sb.AuthApiException('Invalid Refresh Token',
            statusCode: '400', code: 'refresh_token_not_found'),
        AppSessionCheckOutcome.credentialsRejected
      ),
      'socket': (
        const SocketException('Failed host lookup'),
        AppSessionCheckOutcome.offline
      ),
      'http client': (
        http.ClientException('Failed host lookup'),
        AppSessionCheckOutcome.offline
      ),
      'TLS': (
        const HandshakeException('portal certificate'),
        AppSessionCheckOutcome.offline
      ),
      'HTTP protocol': (
        const HttpException('Connection closed'),
        AppSessionCheckOutcome.offline
      ),
      'timeout': (TimeoutException('slow'), AppSessionCheckOutcome.timedOut),
      'aborted': (
        http.RequestAbortedException(),
        AppSessionCheckOutcome.timedOut
      ),
      'PGRST301': (
        const sb.PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        AppSessionCheckOutcome.credentialsRejected
      ),
      'PGRST302': (
        const sb.PostgrestException(message: 'x', code: 'PGRST302'),
        AppSessionCheckOutcome.credentialsRejected
      ),
      'PGRST303': (
        const sb.PostgrestException(message: 'x', code: 'PGRST303'),
        AppSessionCheckOutcome.credentialsRejected
      ),
      'RPC 503': (
        const sb.PostgrestException(message: 'unavailable', code: '503'),
        AppSessionCheckOutcome.serverUnavailable
      ),
      'RPC 500': (
        const sb.PostgrestException(message: 'x', code: '500'),
        AppSessionCheckOutcome.serverUnavailable
      ),
      'non-JSON 200': (
        const sb.PostgrestException(message: '<html>', code: '200'),
        AppSessionCheckOutcome.inconclusive
      ),
      'gateway 401 without a PostgREST code': (
        const sb.PostgrestException(message: 'Invalid API key', code: '401'),
        AppSessionCheckOutcome.inconclusive
      ),
      'session_superseded text from the read RPC': (
        const sb.PostgrestException(
            message: 'session_superseded', code: '42501'),
        AppSessionCheckOutcome.inconclusive
      ),
      'anything else': (
        StateError('unexpected'),
        AppSessionCheckOutcome.inconclusive
      ),
      'an already typed failure': (
        const AppSessionCheckException(AppSessionCheckOutcome.timedOut),
        AppSessionCheckOutcome.timedOut
      ),
    };
    cases.forEach((name, c) {
      test(name, () => expect(classifySessionCheckError(c.$1), c.$2));
    });

    test('a typed failure never reads as a displacement', () {
      for (final outcome in AppSessionCheckOutcome.values) {
        expect(AppSessionCheckException(outcome).toString(),
            isNot(contains('session_superseded')));
      }
    });
  });

  group('the coordinator', () {
    late _Rpc rpc;
    late sb.SupabaseClient client;
    late AppSessionCoordinator coordinator;
    late int superseded;
    late int resumes;
    late _Clock clock;
    Future<bool>? resumed;

    setUp(() async {
      rpc = _Rpc();
      superseded = 0;
      resumes = 0;
      clock = _Clock();
      client = sb.SupabaseClient(
        'https://unit-test.supabase.co',
        'unit-test-publishable-key',
        httpClient: rpc,
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.setInitialSession(_session());
      coordinator = AppSessionCoordinator(
        client,
        onSuperseded: () => superseded++,
        onResumeWhileUnverified: () {
          resumes++;
          resumed =
              coordinator.authorize(client.auth.currentSession!, claim: false);
        },
        stopwatch: () => clock,
      );
    });

    tearDown(() => coordinator.dispose());

    sb.Session session() => client.auth.currentSession!;

    Future<void> authorizeFirst() async {
      rpc.body = true;
      expect(await coordinator.authorize(session(), claim: false), isTrue);
      expect(coordinator.isAuthorized(session()), isTrue);
    }

    test('validateNow: true stays authorized', () async {
      await authorizeFirst();
      expect(await coordinator.validateNow(), isTrue);
      expect(superseded, 0);
    });

    test('validateNow: a real false supersedes', () async {
      await authorizeFirst();
      rpc.body = false;
      expect(await coordinator.validateNow(), isFalse);
      expect(superseded, 1);
    });

    for (final answer in <Object?>[null, '"false"', 0, '{}', '']) {
      test(
          'validateNow: ${jsonEncode(answer)} is inconclusive and supersedes '
          'nothing', () async {
        await authorizeFirst();
        rpc.body = answer;
        await expectLater(
          coordinator.validateNow(),
          throwsA(isA<AppSessionCheckException>().having((e) => e.outcome,
              'outcome', AppSessionCheckOutcome.inconclusive)),
        );
        expect(superseded, 0);
        expect(coordinator.isAuthorized(session()), isTrue);
      });
    }

    test(
        'the first check: a non-Boolean answer is a typed failure, not a '
        'refusal', () async {
      rpc.body = null;
      await expectLater(
        coordinator.authorize(session(), claim: false),
        throwsA(isA<AppSessionCheckException>().having(
            (e) => e.outcome, 'outcome', AppSessionCheckOutcome.inconclusive)),
      );
      expect(superseded, 0);
      expect(coordinator.isAuthorized(session()), isFalse);
    });

    test(
        'a check older than the hard deadline at resume is ended and a fresh '
        'one is asked for, even if its timer has not fired', () async {
      rpc.body = _hang;
      final first = coordinator.authorize(session(), claim: false);
      final failure = expectLater(
        first,
        throwsA(isA<AppSessionCheckException>().having(
            (e) => e.outcome, 'outcome', AppSessionCheckOutcome.timedOut)),
      );
      await pumpEventQueue();
      clock.now = const Duration(seconds: 31);
      rpc.body = true;
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await failure;
      expect(rpc.aborts, 1);
      expect(resumes, 1);
      expect(await resumed, isTrue,
          reason: 'the retry at resume is a fresh check, not the ended one');
      expect(rpc.calls, 2);
    });

    test('a younger check is joined at resume, not ended', () async {
      rpc.body = _hang;
      final first = coordinator.authorize(session(), claim: false);
      unawaited(first.then((_) {}, onError: (Object _) {}));
      await pumpEventQueue();
      clock.now = const Duration(seconds: 10);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(identical(coordinator.authorize(session(), claim: false), first),
          isTrue);
      expect(rpc.calls, 1);
      expect(rpc.aborts, 0);
      coordinator.clear();
      expect(await first, isFalse, reason: 'a cleared check is stale');
      expect(rpc.aborts, 1);
    });

    test("a new session ends the old session's check and aborts its request",
        () async {
      rpc.body = _hang;
      final first = coordinator.authorize(session(), claim: false);
      await pumpEventQueue();
      await client.auth.setInitialSession(_session(sid: _sid2));
      rpc.body = true;
      expect(await coordinator.authorize(session(), claim: false), isTrue);
      expect(await first, isFalse, reason: 'the old check is stale');
      expect(rpc.aborts, 1);
      expect(superseded, 0);
    });

    test(
        'a true that arrives after the session changed authorizes nothing '
        '(the check after the answer, with nobody ending the old check)',
        () async {
      rpc.hold = Completer<void>();
      rpc.body = true;
      final first = coordinator.authorize(session(), claim: false);
      await pumpEventQueue();
      await client.auth.setInitialSession(_session(sid: _sid2));
      rpc.hold!.complete();
      expect(await first, isFalse);
      expect(coordinator.isAuthorized(session()), isFalse);
      expect(superseded, 0);
    });

    test(
        'a cleared session ends its check as stale: no authorization, no '
        'refusal, its request aborted', () async {
      rpc.body = _hang;
      final first = coordinator.authorize(session(), claim: false);
      await pumpEventQueue();
      coordinator.clear();
      expect(await first, isFalse);
      expect(coordinator.isAuthorized(session()), isFalse);
      expect(superseded, 0);
      expect(rpc.aborts, 1);
    });
  });

  group('source guards', () {
    String read(String path) => File(path).readAsStringSync();
    final coordinator = read('lib/src/services/app_session_coordinator.dart');
    final repository =
        read('lib/src/repositories/supabase_auth_repository.dart');
    final viewModel =
        read('lib/src/viewmodels/Signup-Login/auth_viewmodel.dart');

    test('the sign-in claim keeps its own unchanged path', () {
      expect(
          coordinator,
          contains(
              "claim ? 'claim_current_app_session' : 'is_current_app_session'"));
      expect(RegExp(r'abortSignal\(').allMatches(coordinator).length, 1,
          reason: 'only the read check can be aborted');
    });

    test('the application never refreshes a token itself', () {
      for (final source in [coordinator, repository]) {
        expect(source, isNot(contains('refreshSession(')));
      }
    });

    test('only the retryable SDK error is filtered, and only with a session',
        () {
      final source = repository.replaceAll('\r\n', '\n');
      expect(
          RegExp(r'error is AuthRetryableFetchException &&\s+'
                  r'_client\.auth\.currentSession != null\)')
              .allMatches(source)
              .length,
          1);
      expect(source, isNot(contains('error is AuthException &&')));
      expect(
          viewModel.replaceAll('\r\n', '\n'),
          contains('  void _handleAuthStreamError(Object error) {\n'
              '    if (_status == AuthStatus.unknown) {\n'
              '      _resolveBootstrapAsUnauthenticated();\n'
              '    }\n'
              '  }'));
    });
  });
}
