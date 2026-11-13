// OFF-1: how a restored session is verified at startup.
//
// Every test runs the real SupabaseAuthRepository, AppSessionCoordinator,
// AuthViewModel, AuthWrapper and auth redirect on a real SupabaseClient whose
// HTTP transport is controlled here. Time is the test binding's fake clock:
// the 5 s and 30 s deadlines are pumped, never slept.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_state_store.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/auth_wrapper.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/session_superseded_dialog_host.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _s2 = '22222222-2222-4222-8222-222222222222';
const _s3 = '33333333-3333-4333-8333-333333333333';

const _enMessage =
    'Could not verify this sign-in. Check your connection and try again.';
const _arMessage =
    'تعذّر التحقق من تسجيل الدخول. تحقّق من اتصالك وحاول مرة أخرى.';
const _snapshotKey = 'cached_profile_snapshot_v1';
const _snapshot = '{"uid":"$_uid","name":"Saved"}';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _sessionJson({
  String uid = _uid,
  String sid = _s1,
  bool expired = false,
  String refresh = 'refresh-1',
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final exp = expired ? now - 7200 : now + 3600;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': uid,
          'session_id': sid,
          'exp': exp,
          'iat': now,
          'role': 'authenticated',
          'aud': 'authenticated',
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp,
    'refresh_token': refresh,
    'user': {
      'id': uid,
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

String? _sidOf(http.BaseRequest r) {
  final bearer = r.headers['Authorization'] ?? r.headers['authorization'];
  if (bearer == null) return null;
  final parts = bearer.replaceFirst('Bearer ', '').split('.');
  if (parts.length != 3) return null;
  final body =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
  return body is Map ? body['session_id'] as String? : null;
}

http.StreamedResponse _reply(http.BaseRequest r, Object? body,
        [int status = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(
          body == null ? '' : (body is _Raw ? body.text : jsonEncode(body)))),
      status,
      request: r,
      headers: {'content-type': 'application/json'},
    );

class _Raw {
  const _Raw(this.text);
  final String text;
}

typedef _Answer = FutureOr<http.StreamedResponse> Function(http.BaseRequest);

/// The whole network, recorded. A request whose answer never comes is left
/// pending; one that carries an abort trigger is ended by it.
class _Net extends http.BaseClient {
  _Answer check = (r) => _reply(r, true);
  _Answer claim = (r) => _reply(r, true);
  _Answer token =
      (r) => throw http.ClientException('Failed host lookup', r.url);
  _Answer other = (r) => _reply(r, const <Object>[]);

  final List<String> requests = [];
  final List<String> aborted = [];

  int count(String fragment) =>
      requests.where((p) => p.contains(fragment)).length;
  int get checks => count('/rpc/is_current_app_session');

  void offline() =>
      check = (r) => throw http.ClientException('Failed host lookup', r.url);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    requests.add(path);
    final pick = path.endsWith('/rpc/is_current_app_session')
        ? check
        : path.endsWith('/rpc/claim_current_app_session')
            ? claim
            : path.endsWith('/token')
                ? token
                : other;
    final out = Completer<http.StreamedResponse>();
    if (request is http.Abortable) {
      final trigger = request.abortTrigger;
      trigger?.whenComplete(() {
        if (out.isCompleted) return;
        aborted.add(path);
        out.completeError(http.RequestAbortedException(request.url));
      });
    }
    Future<http.StreamedResponse>.sync(() => pick(request)).then(
      (value) {
        if (!out.isCompleted) out.complete(value);
      },
      onError: (Object e, StackTrace s) {
        if (!out.isCompleted) out.completeError(e, s);
      },
    );
    return out.future;
  }
}

/// An answer the test releases later.
class _Gate {
  final Completer<Object?> _c = Completer<Object?>();
  _Answer get answer => (r) async => _reply(r, await _c.future);
  void open(Object? body) => _c.complete(body);
  void fail(Object error) => _c.completeError(error);
}

class _Profiles implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _App {
  _App(this.net);

  final _Net net;
  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: net,
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  late final SupabaseAuthRepository repository;
  late final AuthViewModel auth;
  late final GoRouter router;

  Future<void> start(
    WidgetTester tester, {
    Map<String, Object?>? session,
    Locale locale = const Locale('en'),
  }) async {
    if (session != null) {
      await client.auth.setInitialSession(jsonEncode(session));
    }
    _freshOfflinePass();
    repository =
        SupabaseAuthRepository(userRepository: _Profiles(), client: client);
    auth =
        AuthViewModel(authRepository: repository, userRepository: _Profiles());
    router = GoRouter(
      initialLocation: '/',
      refreshListenable: auth,
      redirect: (context, state) => resolveAuthRedirect(
        auth.status,
        state.uri.path,
        passwordRecoveryActive: auth.isPasswordRecoveryActive,
      ),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const AuthWrapper()),
        GoRoute(
          path: '/welcome',
          builder: (_, __) => SessionSupersededDialogHost(
            authViewModel: auth,
            child: const Scaffold(body: Text('WELCOME')),
          ),
        ),
        GoRoute(
          path: '/sign-in',
          builder: (_, __) => const Scaffold(body: Text('SIGN IN')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (_, __) => const Scaffold(body: Text('RESET')),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          locale: locale,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets microtasks, stream events and frames run without moving time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> wait(WidgetTester tester, Duration d) async {
    var left = d;
    const step = Duration(milliseconds: 500);
    while (left > Duration.zero) {
      final s = left < step ? left : step;
      await tester.pump(s);
      left -= s;
    }
    await settle(tester);
  }

  bool get sessionKept => client.auth.currentSession != null;

  /// Only the explicit sign-in test may send a claim. A restored session,
  /// its Retry, a hint or a resume only ever check.
  bool allowClaim = false;

  Future<void> dispose(WidgetTester tester) async {
    if (!allowClaim) {
      expect(net.count('/rpc/claim_current_app_session'), 0,
          reason: 'a restored session never claims');
    }
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    auth.dispose();
    // Both need real asynchrony, which the fake clock never provides: the
    // repository's stream teardown, and the client's JSON isolate (the client
    // is therefore left, as other auth tests leave it).
    await tester.runAsync(() async {
      await repository
          .dispose()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
      // A confirmed check starts the existing Realtime watch of the active
      // session row; its channel and push timers are ended here.
      await client
          .removeAllChannels()
          .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    });
    await tester.pump(const Duration(seconds: 11));
  }
}

Finder get _retryButton => find.widgetWithText(ElevatedButton, 'Retry');
bool _buttonEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(_retryButton).onPressed != null;
Finder get _indicator => find.byType(CircularProgressIndicator);

void _expectRetry(WidgetTester tester, {required bool waiting}) {
  expect(find.text(_enMessage), findsOneWidget, reason: 'Retry is shown');
  expect(find.text('HOME'), findsNothing);
  expect(find.text('WELCOME'), findsNothing);
  if (waiting) {
    expect(_indicator, findsOneWidget, reason: 'one indicator while waiting');
    expect(find.byIcon(Icons.wifi_off), findsNothing);
    expect(_buttonEnabled(tester), isFalse,
        reason: 'the button can only join the running check');
  } else {
    expect(_indicator, findsNothing);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(_buttonEnabled(tester), isTrue);
  }
}

/// OFF-2b-3: a fresh offline pass lifecycle, built inside the running test.
/// The lease chains its work through futures, and a future keeps the zone it
/// was born in: one made in setUp (real zone) or in an earlier test's
/// fake-async zone would never run inside this test's fake-async zone.
void _freshOfflinePass() => OfflinePassLifecycle.debugShared =
    OfflinePassLifecycle(OfflineSessionLease(store: SecureOfflinePassStore()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.preloadAllLanguages();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({_snapshotKey: _snapshot});
    // OFF-2b-3: the offline pass store lives in flutter_secure_storage.
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => OfflinePassLifecycle.debugShared = null);

  Future<bool> snapshotKept() async =>
      (await SharedPreferences.getInstance()).getString(_snapshotKey) ==
      _snapshot;

  group('classification of the first check', () {
    testWidgets(
        '1. a valid session with no network shows Retry, keeps the '
        'session and signs nothing out', (tester) async {
      final app = _App(_Net()..offline());
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.auth.status, AuthStatus.unknown);
      expect(app.sessionKept, isTrue);
      expect(app.net.count('/logout'), 0);
      expect(app.net.count('/token'), 0);
      expect(await snapshotKept(), isTrue);
      await app.dispose(tester);
    });

    testWidgets('2. a raw DNS/socket failure is the same temporary state',
        (tester) async {
      final net = _Net()
        ..check = (r) => throw const SocketException('Failed host lookup');
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.sessionKept, isTrue);
      await app.dispose(tester);
    });

    testWidgets('3. a TLS failure (Wi-Fi portal) is temporary', (tester) async {
      final net = _Net()
        ..check = (r) => throw const HandshakeException('portal certificate');
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.sessionKept, isTrue);
      await app.dispose(tester);
    });

    testWidgets('4. an RPC 5xx is temporary', (tester) async {
      final net = _Net()
        ..check = (r) => _reply(r, {'message': 'unavailable'}, 503);
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.sessionKept, isTrue);
      expect(app.net.checks, 1, reason: 'a POST is not retried by the client');
      await app.dispose(tester);
    });

    testWidgets(
        '5. an RPC 401 is not a refusal, keeps the session and makes '
        'no refresh of its own', (tester) async {
      final net = _Net()
        ..check = (r) =>
            _reply(r, {'code': 'PGRST301', 'message': 'JWT expired'}, 401);
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.sessionKept, isTrue);
      expect(app.net.count('/token'), 0, reason: 'the SDK owns refreshing');
      expect(find.byType(AlertDialog), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('6. a valid true opens Home with one check and no refresh',
        (tester) async {
      final app = _App(_Net());
      await app.start(tester, session: _sessionJson());
      expect(find.text('HOME'), findsOneWidget);
      expect(app.net.checks, 1);
      expect(app.net.count('/token'), 0);
      await app.dispose(tester);
    });

    testWidgets(
        '7. a valid false is a refusal: the existing displacement '
        'flow signs the session out', (tester) async {
      final net = _Net()..check = (r) => _reply(r, false);
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(app.sessionKept, isFalse);
      await app.dispose(tester);
    });

    for (final entry in <String, Object?>{
      '204 with no body': const _Raw(''),
      'JSON null': null,
      'the string "false"': 'false',
      'the number 0': 0,
      'the number 1': 1,
      'an object': const <String, Object?>{},
      'a list': const <Object?>[],
      'a non-JSON 200 page': const _Raw('<html>portal</html>'),
    }.entries) {
      testWidgets(
          '8. ${entry.key} is not a refusal: no sign-out, no data '
          'touched', (tester) async {
        final net = _Net()
          ..check = (r) => entry.key.startsWith('204')
              ? _reply(r, const _Raw(''), 204)
              : _reply(r, entry.value);
        final app = _App(net);
        await app.start(tester, session: _sessionJson());
        _expectRetry(tester, waiting: false);
        expect(app.sessionKept, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        expect(await snapshotKept(), isTrue);
        await app.dispose(tester);
      });
    }

    testWidgets(
        '9. an expired token with no network shows Retry, not Welcome, '
        'and keeps the session', (tester) async {
      final app = _App(_Net());
      await app.start(tester, session: _sessionJson(expired: true));
      // The SDK's own refresh backoff runs out well before this.
      await app.wait(tester, const Duration(seconds: 45));
      _expectRetry(tester, waiting: false);
      expect(app.sessionKept, isTrue);
      expect(app.net.count('/token'), greaterThan(0));
      expect(app.net.checks, 0, reason: 'no check without a usable token');
      await app.dispose(tester);
    });

    testWidgets(
        '10. a rejected refresh credential follows the SDK sign-out '
        'and leaves no temporary-error flag', (tester) async {
      final net = _Net()
        ..token = (r) => _reply(
            r,
            {
              'code': 400,
              'error_code': 'refresh_token_not_found',
              'msg': 'Invalid Refresh Token: Refresh Token Not Found',
            },
            400);
      final app = _App(net);
      await app.start(tester, session: _sessionJson(expired: true));
      await app.wait(tester, const Duration(seconds: 1));
      expect(find.text('WELCOME'), findsOneWidget);
      expect(app.sessionKept, isFalse);
      expect(app.auth.isSessionCheckUnavailable, isFalse);
      await app.dispose(tester);
    });
  });

  group('auth stream errors', () {
    Future<_App> pending(WidgetTester tester, _Gate gate) async {
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      expect(find.text('HOME'), findsNothing);
      return app;
    }

    testWidgets(
        '11. a retryable SDK error while the session is stored does '
        'not look like a sign-out', (tester) async {
      final gate = _Gate();
      final app = await pending(tester, gate);
      // ignore: invalid_use_of_internal_member
      app.client.auth.notifyException(
          sb.AuthRetryableFetchException(message: 'Failed host lookup'));
      await app.settle(tester);
      expect(find.text('WELCOME'), findsNothing);
      expect(app.auth.status, AuthStatus.unknown);
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets(
        '12. any other auth error keeps today\'s behaviour (the rule '
        'is narrow)', (tester) async {
      final gate = _Gate();
      final app = await pending(tester, gate);
      // ignore: invalid_use_of_internal_member
      app.client.auth.notifyException(const sb.AuthApiException('link expired',
          statusCode: '403', code: 'otp_expired'));
      await app.settle(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      gate.open(false);
      await app.settle(tester);
      await app.dispose(tester);
    });

    testWidgets('13. an unexpected non-auth error keeps today\'s behaviour',
        (tester) async {
      final gate = _Gate();
      final app = await pending(tester, gate);
      // ignore: invalid_use_of_internal_member
      app.client.auth.notifyException(StateError('unexpected'));
      await app.settle(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      gate.open(false);
      await app.settle(tester);
      await app.dispose(tester);
    });

    testWidgets(
        '14. an explicit sign-out during the check is never ignored '
        'and its late answer changes nothing', (tester) async {
      final gate = _Gate();
      final app = await pending(tester, gate);
      await app.client.auth.signOut(scope: sb.SignOutScope.local);
      await app.settle(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      gate.fail(http.ClientException('Failed host lookup'));
      await app.settle(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(app.auth.isSessionCheckUnavailable, isFalse,
          reason: 'no temporary-error flag for a session that is gone');
      await app.dispose(tester);
    });
  });

  group('deadlines', () {
    testWidgets(
        '15. at 5 s the existing Retry shows while the same check '
        'keeps running', (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      await app.wait(tester, const Duration(seconds: 4));
      expect(find.text(_enMessage), findsNothing, reason: 'splash before 5 s');
      await app.wait(tester, const Duration(seconds: 1));
      _expectRetry(tester, waiting: true);
      expect(app.net.checks, 1);
      expect(app.sessionKept, isTrue);
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget,
          reason: 'a late, current true still opens Home');
      await app.dispose(tester);
    });

    testWidgets(
        '16. at 30 s the check ends, only its RPC is aborted, and a '
        'later answer is ignored', (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      await app.wait(tester, const Duration(seconds: 30));
      _expectRetry(tester, waiting: false);
      expect(app.net.aborted, ['/rest/v1/rpc/is_current_app_session']);
      expect(app.sessionKept, isTrue);
      expect(await snapshotKept(), isTrue);
      await app.dispose(tester);
    });

    testWidgets(
        '17. a late false before 30 s still refuses, even with Retry '
        'showing', (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      await app.wait(tester, const Duration(seconds: 6));
      expect(find.text(_enMessage), findsOneWidget);
      gate.open(false);
      await app.settle(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets(
        '18. a hung token refresh still ends the check at 30 s; '
        'Retry waits on the SDK\'s one refresh, not a second', (tester) async {
      final refresh = Completer<void>();
      final net = _Net()
        ..token = (r) async {
          await refresh.future;
          return _reply(
              r,
              {
                'code': 400,
                'error_code': 'refresh_token_not_found',
                'msg': 'Invalid Refresh Token',
              },
              400);
        };
      final app = _App(net);
      await app.start(tester, session: _sessionJson(expired: true));
      await app.wait(tester, const Duration(seconds: 30));
      _expectRetry(tester, waiting: false);
      expect(net.checks, 0);
      expect(net.aborted, isEmpty, reason: 'the refresh is never aborted');
      await tester.tap(_retryButton);
      await app.settle(tester);
      _expectRetry(tester, waiting: true);
      await app.wait(tester, const Duration(seconds: 30));
      _expectRetry(tester, waiting: false);
      expect(net.count('/token'), 1, reason: 'the SDK refresh is shared');
      refresh.complete();
      await app.settle(tester);
      await app.dispose(tester);
    });
  });

  group('Retry, hints and lifecycle', () {
    testWidgets(
        '19. Retry tapped many times while a check runs makes no '
        'second request', (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      await app.wait(tester, const Duration(seconds: 5));
      for (var i = 0; i < 5; i++) {
        await tester.tap(_retryButton, warnIfMissed: false);
        unawaited(app.auth.retryAppSessionValidation());
        await app.settle(tester);
      }
      expect(app.net.checks, 1);
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('20. Retry after a failure starts one new check',
        (tester) async {
      final app = _App(_Net()..offline());
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      app.net.check = (r) => _reply(r, true);
      await tester.tap(_retryButton);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(app.net.checks, 2);
      await app.dispose(tester);
    });

    testWidgets('21. the network coming back triggers one debounced check',
        (tester) async {
      final connectivity =
          StreamController<List<ConnectivityResult>>.broadcast();
      ListRefreshSignals.instance.useConnectivity(() => connectivity.stream);
      final app = _App(_Net()..offline());
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      connectivity.add([ConnectivityResult.none]);
      await app.settle(tester);
      app.net.check = (r) => _reply(r, true);
      connectivity.add([ConnectivityResult.wifi]);
      connectivity.add([ConnectivityResult.mobile]);
      await app.wait(tester, const Duration(seconds: 2));
      expect(find.text('HOME'), findsOneWidget);
      expect(app.net.checks, 2, reason: 'one hint, one check');
      await app.dispose(tester);
      unawaited(connectivity.close());
    });

    testWidgets('22. background and resume join the running check',
        (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await app.settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await app.settle(tester);
      expect(app.net.checks, 1);
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets(
        '23. an SDK token refresh with the same session joins the '
        'running check', (tester) async {
      final gate = _Gate();
      final net = _Net()
        ..check = gate.answer
        ..token = (r) => _reply(r, _sessionJson(refresh: 'refresh-2'));
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      await app.client.auth.refreshSession();
      await app.settle(tester);
      expect(net.checks, 1, reason: 'same session_id: not a new check');
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets(
        '24. after a 401 the SDK\'s own refresh re-verifies and opens '
        'Home', (tester) async {
      final net = _Net()
        ..check = ((r) =>
            _reply(r, {'code': 'PGRST301', 'message': 'JWT expired'}, 401))
        ..token = ((r) => _reply(r, _sessionJson(refresh: 'refresh-2')));
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      net.check = (r) => _reply(r, true);
      await app.client.auth.refreshSession();
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(net.count('/token'), 1, reason: 'only the SDK refresh');
      await app.dispose(tester);
    });
  });

  group('session and account binding', () {
    testWidgets(
        '25. a new session for the same account invalidates the old '
        'check', (tester) async {
      final first = _Gate();
      final second = _Gate();
      final net = _Net()
        ..check = (r) => _sidOf(r) == _s1 ? first.answer(r) : second.answer(r);
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      await app.client.auth
          .setInitialSession(jsonEncode(_sessionJson(sid: _s3)));
      await app.settle(tester);
      first.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsNothing,
          reason: 'the old session\'s answer cannot authorize the new one');
      second.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets(
        '26. an account switch: the old account\'s late failure '
        'raises nothing', (tester) async {
      final first = _Gate();
      final second = _Gate();
      final net = _Net()
        ..check = (r) => _sidOf(r) == _s1 ? first.answer(r) : second.answer(r);
      final app = _App(net);
      await app.start(tester, session: _sessionJson());
      await app.client.auth.setInitialSession(
          jsonEncode(_sessionJson(uid: _otherUid, sid: _s2)));
      await app.settle(tester);
      first.fail(http.ClientException('Failed host lookup'));
      await app.settle(tester);
      expect(app.auth.isSessionCheckUnavailable, isFalse);
      second.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(app.auth.currentUserId, _otherUid);
      await app.dispose(tester);
    });

    testWidgets('27. after 30 s an old check\'s true cannot open Home',
        (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester, session: _sessionJson());
      await app.wait(tester, const Duration(seconds: 31));
      gate.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsNothing);
      _expectRetry(tester, waiting: false);
      await app.dispose(tester);
    });

    testWidgets('28. a pending account deletion is not entered offline',
        (tester) async {
      await AccountDeletionStateStore.remember(_uid);
      addTearDown(() => AccountDeletionStateStore.forgetIfOwnedBy(_uid));
      final app = _App(_Net()..offline());
      await app.start(tester, session: _sessionJson());
      _expectRetry(tester, waiting: false);
      expect(app.auth.isAccountDeletionReconciling, isFalse);
      expect(app.sessionKept, isTrue);
      await app.dispose(tester);
    });

    testWidgets('29. a password recovery makes no check and Retry is inert',
        (tester) async {
      await PasswordRecoveryStateStore.remember(_uid);
      addTearDown(PasswordRecoveryStateStore.forget);
      final app = _App(_Net());
      await app.start(tester, session: _sessionJson());
      expect(find.text('RESET'), findsOneWidget);
      await app.auth.retryAppSessionValidation();
      await app.settle(tester);
      expect(app.net.checks, 0);
      await app.dispose(tester);
    });

    testWidgets('30. the sign-in claim has no deadline and is never aborted',
        (tester) async {
      final claim = _Gate();
      final net = _Net()
        ..claim = claim.answer
        ..token = (r) => _reply(r, _sessionJson(sid: _s2));
      final app = _App(net)..allowClaim = true;
      await app.start(tester);
      expect(find.text('WELCOME'), findsOneWidget);
      unawaited(app.client.auth
          .signInWithPassword(email: 'session@example.test', password: 'x'));
      await app.wait(tester, const Duration(seconds: 31));
      expect(net.aborted, isEmpty);
      expect(net.count('/rpc/claim_current_app_session'), greaterThan(0));
      claim.open(true);
      await app.settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('the Retry screen', () {
    testWidgets(
        '31. one centered indicator while waiting, none in the '
        'button, label kept; Arabic and RTL', (tester) async {
      final gate = _Gate();
      final app = _App(_Net()..check = gate.answer);
      await app.start(tester,
          session: _sessionJson(), locale: const Locale('ar'));
      await app.wait(tester, const Duration(seconds: 5));
      expect(find.text(_arMessage), findsOneWidget);
      expect(_indicator, findsOneWidget);
      final button = find.widgetWithText(ElevatedButton, 'إعادة المحاولة');
      expect(button, findsOneWidget, reason: 'the label stays');
      expect(find.descendant(of: button, matching: _indicator), findsNothing);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(Directionality.of(tester.element(find.text(_arMessage))),
          TextDirection.rtl);
      gate.fail(http.ClientException('Failed host lookup'));
      await app.settle(tester);
      expect(_indicator, findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
      await app.dispose(tester);
    });
  });
}
