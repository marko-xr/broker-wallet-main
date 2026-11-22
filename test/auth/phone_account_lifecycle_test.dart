// Phone account lifecycle, Batch C2.
//
// D. Add Email for a phone-primary account, on a real SupabaseClient behind a
//    recording loopback HTTP layer: email accounts are refused, the policy and
//    format are checked before the network, only the address is requested
//    (with the app callback), and the chosen password is set only after the
//    server reports that address confirmed for the same account (C3). Every
//    failure is a fixed outcome without provider text.
// W. C1 review on the real screens under GoRouter: Home is reached only after
//    the account is signed in and authorized; a refused, slow or failing
//    sign-in stays on the code screen; the Login / Sign-up code requests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/edit_profile_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/phone_otp_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../responsive/responsive_harness.dart' show prepareResponsiveAssets;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _phone = '+971501234567';
const _storedPhone = '971501234567';
const _goodPassword = 'Strong9Pass';

// ---------------------------------------------------------------------------
// D. Repository harness
// ---------------------------------------------------------------------------

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _userJson({String email = '', String? newEmail}) => {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      if (email.isNotEmpty) 'email_confirmed_at': '2026-11-01T10:00:00Z',
      if (newEmail != null) 'new_email': newEmail,
      'phone': _storedPhone,
      'phone_confirmed_at': '2026-11-22T10:00:00Z',
      'app_metadata': {
        'provider': 'phone',
        'providers': ['phone'],
      },
      'user_metadata': <String, Object?>{},
      'created_at': '2026-11-22T09:59:00Z',
    };

Map<String, Object?> _sessionJson({Map<String, Object?>? user}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': _uid,
          'session_id': _s1,
          'exp': now + 3600,
          'iat': now,
          'role': 'authenticated',
          'aud': 'authenticated',
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-secret',
    'user': user ?? _userJson(),
  };
}

class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final Object? body;
}

_Reply _authError(int status, String code) => _Reply(
      status,
      {'code': status, 'error_code': code, 'msg': 'raw-server-text $code'},
    );

class _Net extends http.BaseClient {
  _Reply passwordReply = _Reply(200, _userJson());
  _Reply emailReply = _Reply(200, _userJson(newEmail: 'sara@example.test'));
  bool failPasswordTransport = false;
  bool failEmailTransport = false;

  /// The account as `GET /auth/v1/user` reports it.
  _Reply getUserReply = _Reply(200, _userJson());
  final List<http.Request> requests = [];

  Iterable<http.Request> get passwordUpdates => userUpdates.where((r) =>
      (jsonDecode(r.body) as Map<String, Object?>).containsKey('password'));

  Iterable<http.Request> get userUpdates => requests
      .where((r) => r.url.path.endsWith('/auth/v1/user') && r.method == 'PUT');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r);
    final path = r.url.path;
    _Reply reply;
    if (path.endsWith('/auth/v1/user') && r.method == 'PUT') {
      final body = jsonDecode(r.body) as Map<String, Object?>;
      if (body.containsKey('password')) {
        if (failPasswordTransport) {
          throw const SocketException('test transport: unreachable');
        }
        reply = passwordReply;
      } else {
        if (failEmailTransport) {
          throw const SocketException('test transport: unreachable');
        }
        reply = emailReply;
      }
    } else if (path.endsWith('/auth/v1/user') && r.method == 'GET') {
      reply = getUserReply;
    } else if (path.endsWith('/rpc/is_current_app_session') ||
        path.endsWith('/rpc/claim_current_app_session')) {
      reply = const _Reply(200, true);
    } else {
      reply = const _Reply(200, <String, Object?>{});
    }
    final text = reply.body == null ? '' : jsonEncode(reply.body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(text)),
      reply.status,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _NoSocket {
  Never call(String url, Map<String, String> headers) =>
      throw const SocketException('test transport: no WebSocket is opened');
}

class _NoProfiles implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// PKCE verifier storage, as `Supabase.initialize` provides in the app: an
/// email change under PKCE stores a code verifier.
class _MemoryPkce implements sb.GotrueAsyncStorage {
  final Map<String, String> _items = {};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

class _MemoryStore implements OfflinePassStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class _Repo {
  _Repo._(this.net, this.repo, this.sub);
  final _Net net;
  final SupabaseAuthRepository repo;
  final StreamSubscription<UserModel?> sub;

  /// A repository whose restored session has passed the session check.
  static Future<_Repo> start({_Net? net, Map<String, Object?>? user}) async {
    final n = net ?? _Net();
    final client = sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: n,
      authOptions: sb.AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryPkce(),
      ),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: _NoSocket().call),
    );
    if (user != null) {
      await client.auth.setInitialSession(jsonEncode(_sessionJson(user: user)));
    }
    final repo =
        SupabaseAuthRepository(userRepository: _NoProfiles(), client: client);
    final sub = repo.authStateChanges.listen((_) {}, onError: (_) {});
    await pumpEventQueue(times: 40);
    n.requests.clear();
    return _Repo._(n, repo, sub);
  }

  Future<void> dispose() async {
    await sub.cancel();
    await repo.dispose();
  }
}

Future<AuthFailure> _failureOf(Future<Object?> Function() body) async {
  try {
    await body();
  } on AuthFailure catch (failure) {
    return failure;
  }
  fail('expected an AuthFailure');
}

// ---------------------------------------------------------------------------
// W. Screen harness
// ---------------------------------------------------------------------------

UserModel _phoneUser() => UserModel(
      uid: _uid,
      name: '',
      email: '',
      phoneNumber: _storedPhone,
      createdAt: DateTime(2026, 11, 22),
      isEmailVerified: false,
      isPhoneVerified: true,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: const []),
      preferences: const {},
    );

class _PhoneAuth implements AuthRepository, PhoneSignInCapability {
  final StreamController<UserModel?> _events =
      StreamController<UserModel?>.broadcast();
  UserModel? _current;

  bool publishOnVerify = true;
  Object? requestError;
  Object? verifyError;
  Completer<void>? verifyGate;
  final List<(String, bool)> requests = [];
  int verifyCalls = 0;

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _current;
    yield* _events.stream;
  }

  @override
  UserModel? get currentUser => _current;
  @override
  String? get currentUserId => _current?.uid;

  void emit(UserModel? user) {
    _current = user;
    _events.add(user);
  }

  @override
  Future<void> requestPhoneSignInCode({
    required String phoneE164,
    required bool createAccount,
  }) async {
    requests.add((phoneE164, createAccount));
    if (requestError != null) throw requestError!;
  }

  @override
  Future<PhoneSignInResult> verifyPhoneSignInCode({
    required String phoneE164,
    required String code,
  }) async {
    verifyCalls++;
    if (verifyGate != null) await verifyGate!.future;
    if (verifyError != null) throw verifyError!;
    final user = _phoneUser();
    if (publishOnVerify) emit(user);
    return PhoneSignInResult(user: user, accountExisted: false);
  }

  @override
  Future<UserModel> completePhoneSignUpName({
    required String expectedUid,
    required String name,
  }) async =>
      _phoneUser();

  @override
  Future<void> signOut() async => emit(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _arb(String language) => json.decode(
      File('lib/src/common/localization/app_$language.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

final Map<String, dynamic> _en = _arb('en');

Widget _app(GoRouter router, AuthViewModel auth) =>
    ChangeNotifierProvider<AuthViewModel>.value(
      value: auth,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );

GoRouter _otpRouter() => GoRouter(
      initialLocation: '/phone-otp',
      routes: [
        GoRoute(
          path: '/phone-otp',
          builder: (_, __) => const PhoneOtpView(
            args: PhoneOtpArgs(phoneNumber: _phone, isSignup: false),
            phoneAuthEnabled: true,
          ),
        ),
        GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
      ],
    );

Future<void> _enterCode(WidgetTester tester, _PhoneAuth auth) async {
  await tester.enterText(
    find.descendant(
        of: find.byType(Pinput), matching: find.byType(EditableText)),
    '123456',
  );
  await tester.pump();
  if (auth.verifyCalls == 0) {
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }
}

/// A page whose button runs [action] with a context that has the router and
/// both providers, the way the real Login and Sign-up screens call them.
GoRouter _formRouter(Future<void> Function(BuildContext) action) => GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(
          path: '/form',
          builder: (_, __) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => action(context),
                child: const Text('SEND'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/phone-otp',
          builder: (_, state) {
            final args = state.extra! as PhoneOtpArgs;
            return Text('OTP ${args.phoneNumber} ${args.isSignup} '
                '${args.displayName ?? '-'}');
          },
        ),
      ],
    );

Future<AuthViewModel> _authVM(WidgetTester tester, _PhoneAuth auth) async {
  final vm = AuthViewModel(authRepository: auth, userRepository: _NoProfiles());
  addTearDown(vm.dispose);
  await tester.pump();
  return vm;
}

/// Lets streams, microtasks and one navigation settle without waiting for
/// the code screen's one-second countdown to finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Removes the tree so the code screen's countdown timer is cancelled.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(prepareResponsiveAssets);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PasswordRecoveryStateStore.forget();
    OfflinePassLifecycle.debugShared =
        OfflinePassLifecycle(OfflineSessionLease(store: _MemoryStore()));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true);
  });
  tearDown(() => OfflinePassLifecycle.debugShared = null);

  group('D. Add Email for a phone account', () {
    test('D1 an email account is refused; it keeps using Email Change',
        () async {
      final r =
          await _Repo.start(user: _userJson(email: 'broker@example.test'));
      final failure = await _failureOf(() => r.repo.addEmailToAccount(
          email: 'new@example.test', password: _goodPassword));
      expect(failure.code, AuthFailureCode.operationNotAllowed);
      expect(r.net.userUpdates, isEmpty);
      await r.dispose();
    });

    test(
        'D2 only the address is requested, with the app callback; no '
        'password before confirmation', () async {
      final r = await _Repo.start(user: _userJson());
      await r.repo.addEmailToAccount(
          email: '  Sara@Example.TEST ', password: _goodPassword);

      final update = r.net.userUpdates.single;
      final emailBody = jsonDecode(update.body) as Map<String, Object?>;
      expect(emailBody['email'], 'sara@example.test');
      expect(emailBody.containsKey('password'), isFalse);
      expect(emailBody['code_challenge_method'], 's256',
          reason: 'the app uses PKCE, as for Email Change');
      expect(update.url.queryParameters['redirect_to'],
          SupabaseConfig.authCallbackUri);
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test('D3 a password outside the policy never reaches the network',
        () async {
      final r = await _Repo.start(user: _userJson());
      for (final weak in ['short1A', 'alllowercase1', 'NoDigitsHere']) {
        final failure = await _failureOf(() => r.repo
            .addEmailToAccount(email: 'sara@example.test', password: weak));
        expect(failure.code, AuthFailureCode.weakPassword, reason: weak);
      }
      expect(r.net.userUpdates, isEmpty);
      await r.dispose();
    });

    test('D4 a malformed address never reaches the network', () async {
      final r = await _Repo.start(user: _userJson());
      final failure = await _failureOf(() => r.repo
          .addEmailToAccount(email: 'not-an-email', password: _goodPassword));
      expect(failure.code, AuthFailureCode.invalidEmail);
      expect(r.net.userUpdates, isEmpty);
      await r.dispose();
    });

    test('D5 a failed address request sets no password, now or later',
        () async {
      final net = _Net()..failEmailTransport = true;
      final r = await _Repo.start(net: net, user: _userJson());
      final failure = await _failureOf(() => r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword));
      expect(failure.code, AuthFailureCode.network);
      expect(addEmailErrorKey(failure), 'emailChangeNetworkError');
      // Even if the account later shows an email, nothing was held to set.
      r.net.getUserReply = _Reply(200, _userJson(email: 'sara@example.test'));
      expect(
          await r.repo.completeAddEmail(), AddEmailCompletion.passwordNotSet);
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test('D6 an address that belongs to another account is a fixed outcome',
        () async {
      final net = _Net()..emailReply = _authError(422, 'email_exists');
      final r = await _Repo.start(net: net, user: _userJson());
      final failure = await _failureOf(() => r.repo.addEmailToAccount(
          email: 'taken@example.test', password: _goodPassword));
      expect(failure.code, AuthFailureCode.emailAlreadyInUse);
      expect(failure.message, isNot(contains('raw-server-text')));
      expect(addEmailErrorKey(failure), 'emailChangeAlreadyInUse');
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test('D7 without a session nothing is sent', () async {
      final r = await _Repo.start();
      final failure = await _failureOf(() => r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword));
      expect(failure.code, AuthFailureCode.sessionExpired);
      expect((await _failureOf(() => r.repo.completeAddEmail())).code,
          AuthFailureCode.sessionExpired);
      expect(r.net.userUpdates, isEmpty);
      await r.dispose();
    });

    test('D8 before the address is confirmed no password is set', () async {
      final r = await _Repo.start(user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      // Pending change only: the server still reports no confirmed email.
      r.net.getUserReply =
          _Reply(200, _userJson(newEmail: 'sara@example.test'));
      expect(await r.repo.completeAddEmail(), AddEmailCompletion.notConfirmed);
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test('D10 once confirmed, the chosen password is set exactly once',
        () async {
      final r = await _Repo.start(user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      r.net.getUserReply = _Reply(200, _userJson(email: 'sara@example.test'));
      expect(await r.repo.completeAddEmail(), AddEmailCompletion.completed);
      expect(jsonDecode(r.net.passwordUpdates.single.body),
          {'password': _goodPassword});
      expect(
        r.net.requests.indexWhere(
            (q) => q.url.path.endsWith('/auth/v1/user') && q.method == 'GET'),
        lessThan(r.net.requests.indexOf(r.net.passwordUpdates.single)),
        reason: 'the server is asked before the password is sent',
      );
      await r.dispose();
    });

    test('D11 a different confirmed address does not receive the password',
        () async {
      final r = await _Repo.start(user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      r.net.getUserReply = _Reply(200, _userJson(email: 'other@example.test'));
      expect(await r.repo.completeAddEmail(), AddEmailCompletion.notConfirmed);
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test(
        'D12 a password the server refuses for good leaves the email and '
        'points to Forgot password', () async {
      for (final code in [
        'weak_password',
        'reauthentication_needed',
      ]) {
        final net = _Net()..passwordReply = _authError(422, code);
        final r = await _Repo.start(net: net, user: _userJson());
        await r.repo.addEmailToAccount(
            email: 'sara@example.test', password: _goodPassword);
        r.net.getUserReply = _Reply(200, _userJson(email: 'sara@example.test'));
        expect(
            await r.repo.completeAddEmail(), AddEmailCompletion.passwordNotSet,
            reason: code);
        // Nothing is held any more.
        expect(
            await r.repo.completeAddEmail(), AddEmailCompletion.passwordNotSet,
            reason: code);
        expect(r.net.passwordUpdates, hasLength(1), reason: code);
        await r.dispose();
      }
      expect(_en['emailAddedSetPasswordWithReset'], isA<String>());
      expect(_arb('ar')['emailAddedSetPasswordWithReset'], isA<String>());
    });

    test('D13 a dropped connection while setting the password can be retried',
        () async {
      final net = _Net()..failPasswordTransport = true;
      final r = await _Repo.start(net: net, user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      r.net.getUserReply = _Reply(200, _userJson(email: 'sara@example.test'));
      final failure = await _failureOf(() => r.repo.completeAddEmail());
      expect(failure.code, AuthFailureCode.network);
      r.net.failPasswordTransport = false;
      expect(await r.repo.completeAddEmail(), AddEmailCompletion.completed);
      expect(r.net.passwordUpdates, hasLength(2));
      await r.dispose();
    });

    test('D14 the same password already set counts as completed', () async {
      final net = _Net()..passwordReply = _authError(422, 'same_password');
      final r = await _Repo.start(net: net, user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      r.net.getUserReply = _Reply(200, _userJson(email: 'sara@example.test'));
      expect(await r.repo.completeAddEmail(), AddEmailCompletion.completed);
      await r.dispose();
    });

    test('D15 another account on the server never receives the password',
        () async {
      final r = await _Repo.start(user: _userJson());
      await r.repo.addEmailToAccount(
          email: 'sara@example.test', password: _goodPassword);
      r.net.getUserReply = _Reply(200, {
        ..._userJson(email: 'sara@example.test'),
        'id': '99999999-9999-4999-8999-999999999999',
      });
      final failure = await _failureOf(() => r.repo.completeAddEmail());
      expect(failure.code, AuthFailureCode.accountChanged);
      expect(r.net.passwordUpdates, isEmpty);
      await r.dispose();
    });

    test('D16 the screens call the confirmation step and show the reset hint',
        () {
      final dialog =
          File('lib/src/views/Widgets/email_verification_dialog.dart')
              .readAsStringSync();
      expect(dialog, contains('completeAddEmail()'));
      final view =
          File('lib/src/views/Screens/home/Profile/edit_profile_view.dart')
              .readAsStringSync();
      expect(view, contains("translate('emailAddedSetPasswordWithReset')"));
      expect(view, contains('AddEmailCompletion.passwordNotSet'));
    });

    test('D9 every Add Email message is localized, never raw text', () {
      final ar = _arb('ar');
      final keys = <String>{
        for (final code in AuthFailureCode.values)
          addEmailErrorKey(AuthFailure(code: code, message: 'x')),
        addEmailErrorKey(Exception('raw')),
        'emailChangeNetworkError',
      };
      for (final key in keys) {
        expect(_en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
      }
      expect(
        addEmailErrorKey(const AuthFailure(
            code: AuthFailureCode.weakPassword, message: 'x')),
        'passwordChangeWeak',
      );
      final view =
          File('lib/src/views/Screens/home/Profile/edit_profile_view.dart')
              .readAsStringSync();
      expect(view, isNot(contains(r"Failed to send verification email: ${e")));
      expect(view, contains('addEmailErrorKey(e)'));
      final dialog =
          File('lib/src/views/Widgets/email_verification_dialog.dart')
              .readAsStringSync();
      expect(dialog, isNot(contains('Verification check failed:')));
    });
  });

  group('W. C1 review: Home only after an authorized sign-in', () {
    testWidgets('W1 a verified and authorized sign-in opens Home',
        (tester) async {
      final auth = _PhoneAuth();
      final vm = await _authVM(tester, auth);
      await tester.pumpWidget(_app(_otpRouter(), vm));
      await tester.pump();
      await _enterCode(tester, auth);
      await _settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(vm.status, AuthStatus.authenticated);
      expect(auth.verifyCalls, 1);
      await _unmount(tester);
    });

    testWidgets('W2 a refused session check stays on the code screen',
        (tester) async {
      final auth = _PhoneAuth()
        ..verifyError = const AuthFailure(
            code: AuthFailureCode.appSessionUnavailable, message: 'x');
      final vm = await _authVM(tester, auth);
      await tester.pumpWidget(_app(_otpRouter(), vm));
      await tester.pump();
      await _enterCode(tester, auth);
      await _settle(tester);
      expect(find.text('HOME'), findsNothing);
      expect(find.byType(PhoneOtpView), findsOneWidget);
      expect(find.text(_en['appSessionCheckFailed'] as String), findsOneWidget);
      expect(vm.status, isNot(AuthStatus.authenticated));
      await _unmount(tester);
    });

    testWidgets('W3 a sign-in that never becomes access never opens Home',
        (tester) async {
      final auth = _PhoneAuth()..publishOnVerify = false;
      final vm = await _authVM(tester, auth);
      await tester.pumpWidget(_app(_otpRouter(), vm));
      await tester.pump();
      await _enterCode(tester, auth);
      await tester.pump(const Duration(seconds: 16));
      await _settle(tester);
      expect(find.text('HOME'), findsNothing);
      expect(find.text(_en['appSessionCheckFailed'] as String), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('W4 Home waits for the sign-in that is still in flight',
        (tester) async {
      final auth = _PhoneAuth()..verifyGate = Completer<void>();
      final vm = await _authVM(tester, auth);
      await tester.pumpWidget(_app(_otpRouter(), vm));
      await tester.pump();
      await _enterCode(tester, auth);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('HOME'), findsNothing);
      auth.verifyGate!.complete();
      await _settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(auth.verifyCalls, 1, reason: 'one verification at a time');
      await _unmount(tester);
    });

    testWidgets('W5 Login asks for a code without creating an account',
        (tester) async {
      final auth = _PhoneAuth();
      final vm = await _authVM(tester, auth);
      final login = SignInViewModel(phoneAuthEnabled: true)
        ..setPhone('0501234567');
      addTearDown(login.dispose);
      await tester.pumpWidget(_app(_formRouter(login.sendOTP), vm));
      await tester.pump();
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(auth.requests, [(_phone, false)]);
      expect(find.text('OTP $_phone false -'), findsOneWidget);
      expect(vm.status, isNot(AuthStatus.authenticated),
          reason: 'a sent code is not a sign-in');
      await _unmount(tester);
    });

    testWidgets('W6 Login with a malformed number sends nothing',
        (tester) async {
      final auth = _PhoneAuth();
      final vm = await _authVM(tester, auth);
      final login = SignInViewModel(phoneAuthEnabled: true)..setPhone('12345');
      addTearDown(login.dispose);
      await tester.pumpWidget(_app(_formRouter(login.sendOTP), vm));
      await tester.pump();
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(auth.requests, isEmpty);
      expect(login.phoneError, _en['invalidUAEPhoneNumber']);
      expect(find.text('SEND'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('W7 Login with an unknown number stays on the form',
        (tester) async {
      final auth = _PhoneAuth()
        ..requestError = const AuthFailure(
            code: AuthFailureCode.phoneNotRegistered, message: 'x');
      final vm = await _authVM(tester, auth);
      final login = SignInViewModel(phoneAuthEnabled: true)
        ..setPhone('0501234567');
      addTearDown(login.dispose);
      await tester.pumpWidget(_app(_formRouter(login.sendOTP), vm));
      await tester.pump();
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(login.phoneError, _en['phoneNotRegistered']);
      expect(find.text('SEND'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('W8 Sign-up needs a name, then may create the account',
        (tester) async {
      final auth = _PhoneAuth();
      final vm = await _authVM(tester, auth);
      final signup = SignUpViewModel(phoneAuthEnabled: true)
        ..setPhone('0501234567');
      addTearDown(signup.dispose);
      await tester.pumpWidget(_app(_formRouter(signup.signUpWithPhone), vm));
      await tester.pump();
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(auth.requests, isEmpty);
      expect(signup.nameError, _en['nameRequired']);

      signup.setName(' Sara Ali ');
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(auth.requests, [(_phone, true)]);
      expect(find.text('OTP $_phone true Sara Ali'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('W9 with the build switch off the forms send nothing',
        (tester) async {
      final auth = _PhoneAuth();
      final vm = await _authVM(tester, auth);
      final login = SignInViewModel()..setPhone('0501234567');
      addTearDown(login.dispose);
      await tester.pumpWidget(_app(_formRouter(login.sendOTP), vm));
      await tester.pump();
      await tester.tap(find.text('SEND'));
      await _settle(tester);
      expect(auth.requests, isEmpty);
      expect(login.phoneError, _en['phoneSignInUnavailable']);
      await _unmount(tester);
    });
  });
}
