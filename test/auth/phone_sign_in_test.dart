// Phone sign-in / sign-up (Supabase OTP), Batch C1.
//
// A. The repository on a real SupabaseClient behind a recorded HTTP layer:
//    the exact requests, the Single Active Device claim before any access,
//    and the error mapping. No real network: loopback URL, a recording
//    client, a throwing Realtime transport.
// B. The code screen's view model against a real AuthViewModel: success is
//    reported only once the account is authenticated, one verification at a
//    time, the sign-up name, resend and the countdown.
// C. Guards: the build default, logging, localization.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:broker_wallet/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '660e8400-e29b-41d4-a716-446655440000';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _phone = '+971501234567';
const _storedPhone = '971501234567'; // Supabase Auth stores it without '+'.

// ---------------------------------------------------------------------------
// A. Repository harness
// ---------------------------------------------------------------------------

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _phoneUserJson({
  String uid = _uid,
  String phone = _storedPhone,
  bool confirmed = true,
}) =>
    {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': '',
      'phone': phone,
      if (confirmed) 'phone_confirmed_at': '2026-11-22T10:00:00Z',
      'app_metadata': {
        'provider': 'phone',
        'providers': ['phone'],
      },
      'user_metadata': <String, Object?>{},
      'created_at': '2026-11-22T09:59:00Z',
    };

Map<String, Object?> _sessionJson({
  String uid = _uid,
  String sid = _s1,
  Map<String, Object?>? user,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': uid,
          'session_id': sid,
          'exp': now + 3600,
          'iat': now,
          'role': 'authenticated',
          'aud': 'authenticated',
          'amr': [
            {'method': 'otp', 'timestamp': now},
          ],
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-secret',
    'user': user ?? _phoneUserJson(uid: uid),
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

/// Records every request; each endpoint answers what the test sets.
class _Net extends http.BaseClient {
  _Reply otp = const _Reply(200, <String, Object?>{});
  _Reply verify = _Reply(200, _sessionJson());
  _Reply claim = const _Reply(200, true);
  Object? throwOn; // a path suffix that fails at transport level
  final List<http.Request> requests = [];

  Iterable<String> get paths => requests.map((r) => r.url.path);

  Map<String, Object?> bodyOf(String suffix) => jsonDecode(
        requests.lastWhere((r) => r.url.path.endsWith(suffix)).body,
      ) as Map<String, Object?>;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r);
    final path = r.url.path;
    if (throwOn is String && path.endsWith(throwOn as String)) {
      throw const SocketException('test transport: unreachable');
    }
    _Reply reply;
    if (path.endsWith('/auth/v1/otp')) {
      reply = otp;
    } else if (path.endsWith('/auth/v1/verify')) {
      reply = verify;
    } else if (path.endsWith('/rpc/claim_current_app_session')) {
      reply = claim;
    } else if (path.endsWith('/rpc/is_current_app_session')) {
      reply = const _Reply(200, true);
    } else if (path.endsWith('/rest/v1/profiles') && r.method == 'PATCH') {
      final written = jsonDecode(r.body) as Map<String, Object?>;
      reply = _Reply(200, {'name': written['name']});
    } else if (path.endsWith('/auth/v1/logout')) {
      reply = const _Reply(204, null);
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

sb.SupabaseClient _client(_Net net) => sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: net,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: _NoSocket().call),
    );

UserSubscription _subscription() =>
    UserSubscription(plan: 'test', isActive: false, features: const []);

UserModel _profile({String uid = _uid, String name = '', String? phone}) =>
    UserModel(
      uid: uid,
      name: name,
      email: '',
      phoneNumber: phone ?? _storedPhone,
      createdAt: DateTime(2026, 11, 22),
      isEmailVerified: false,
      isPhoneVerified: true,
      subscription: _subscription(),
      preferences: const {},
    );

class _Profiles implements UserRepository {
  UserModel? profile;
  int reads = 0;

  @override
  Future<UserModel?> getUserById(String uid) async {
    reads++;
    return profile?.uid == uid ? profile : null;
  }

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  _Repo._(this.net, this.client, this.profiles, this.repo, this.identities,
      this.sub);

  final _Net net;
  final sb.SupabaseClient client;
  final _Profiles profiles;
  final SupabaseAuthRepository repo;
  final List<UserModel?> identities;
  final StreamSubscription<UserModel?> sub;

  static Future<_Repo> start({_Net? net, bool signedIn = false}) async {
    final n = net ?? _Net();
    final client = _client(n);
    if (signedIn) {
      await client.auth.setInitialSession(jsonEncode(_sessionJson()));
    }
    final profiles = _Profiles();
    final repo =
        SupabaseAuthRepository(userRepository: profiles, client: client);
    final identities = <UserModel?>[];
    final sub = repo.authStateChanges.listen(identities.add, onError: (_) {});
    await pumpEventQueue(times: 40);
    return _Repo._(n, client, profiles, repo, identities, sub);
  }

  Iterable<UserModel> get published => identities.whereType<UserModel>();

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
// B. View model harness
// ---------------------------------------------------------------------------

/// An auth repository that can phone-sign-in. Publishing the identity stands
/// for the real repository's "the claim succeeded".
class _PhoneAuth implements AuthRepository, PhoneSignInCapability {
  final StreamController<UserModel?> _events =
      StreamController<UserModel?>.broadcast();
  UserModel? _current;

  bool publishOnVerify = true;
  bool accountExisted = false;
  Object? requestError;
  Object? verifyError;
  Completer<void>? verifyGate;
  int nameFailuresLeft = 0;

  final List<(String, bool)> requests = [];
  int verifyCalls = 0;
  final List<String> names = [];

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
    final user = _profile(name: accountExisted ? 'Existing' : '');
    if (publishOnVerify) emit(user);
    return PhoneSignInResult(user: user, accountExisted: accountExisted);
  }

  @override
  Future<UserModel> completePhoneSignUpName({
    required String expectedUid,
    required String name,
  }) async {
    names.add(name);
    if (nameFailuresLeft > 0) {
      nameFailuresLeft--;
      throw const AuthFailure(
          code: AuthFailureCode.unknown, message: 'not saved');
    }
    return _profile(uid: expectedUid, name: name);
  }

  @override
  Future<void> signOut() async => emit(null);

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ticker {
  void Function(Timer)? onTick;
  _FakeTimer? timer;

  Timer create(Duration period, void Function(Timer) tick) {
    onTick = tick;
    return timer = _FakeTimer();
  }

  void tick([int times = 1]) {
    for (var i = 0; i < times; i++) {
      final t = timer;
      if (t == null || !t.isActive) return;
      onTick!(t);
    }
  }
}

class _FakeTimer implements Timer {
  bool _active = true;
  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

class _Flow {
  _Flow._(this.auth, this.authVM, this.ticker, this.vm);

  final _PhoneAuth auth;
  final AuthViewModel authVM;
  final _Ticker ticker;
  final PhoneOtpViewModel vm;

  static Future<_Flow> start({
    bool isSignup = false,
    String? name,
    bool enabled = true,
    DateTime? codeSentAt,
    DateTime? now,
  }) async {
    final auth = _PhoneAuth();
    final authVM =
        AuthViewModel(authRepository: auth, userRepository: _Profiles());
    await settle();
    expect(authVM.status, AuthStatus.unauthenticated);
    final ticker = _Ticker();
    final vm = PhoneOtpViewModel(
      authViewModel: authVM,
      enabled: enabled,
      resendCooldown: const Duration(seconds: 3),
      accessTimeout: const Duration(milliseconds: 200),
      timerFactory: ticker.create,
      clock: now == null ? null : () => now,
    )..initialize(PhoneOtpArgs(
        phoneNumber: _phone,
        isSignup: isSignup,
        displayName: name,
        codeSentAt: codeSentAt,
      ));
    return _Flow._(auth, authVM, ticker, vm);
  }

  Future<void> dispose() async {
    vm.dispose();
    authVM.dispose();
    await auth.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

String _read(String path) => File(path).readAsStringSync();

Map<String, dynamic> _arb(String language) => json.decode(
      _read('lib/src/common/localization/app_$language.arb'),
    ) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PasswordRecoveryStateStore.forget();
    OfflinePassLifecycle.debugShared =
        OfflinePassLifecycle(OfflineSessionLease(store: _MemoryStore()));
  });
  tearDown(() => OfflinePassLifecycle.debugShared = null);

  group('A. Requesting a code', () {
    test('A1 sign-in asks Supabase for a code without creating an account',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneSignInCode(
          phoneE164: '0501234567', createAccount: false);

      final body = r.net.bodyOf('/auth/v1/otp');
      expect(body['phone'], _phone);
      expect(body['create_user'], isFalse);
      expect(body['channel'], 'sms');
      expect(body['data'], isEmpty,
          reason: 'no metadata: the server refuses phone sign-ups with any');
      expect(r.net.paths.where((p) => p.endsWith('/resend')), isEmpty);
      expect(r.published, isEmpty, reason: 'a sent code is not a sign-in');
      await r.dispose();
    });

    test('A2 sign-up may create the account; resend is the same request',
        () async {
      final r = await _Repo.start();
      await r.repo
          .requestPhoneSignInCode(phoneE164: _phone, createAccount: true);
      await r.repo
          .requestPhoneSignInCode(phoneE164: _phone, createAccount: true);

      expect(
          r.net.paths.where((p) => p.endsWith('/auth/v1/otp')), hasLength(2));
      expect(r.net.bodyOf('/auth/v1/otp')['create_user'], isTrue);
      expect(r.net.bodyOf('/auth/v1/otp')['data'], isEmpty);
      await r.dispose();
    });

    test('A3 a malformed number never reaches the network', () async {
      final r = await _Repo.start();
      final failure = await _failureOf(() => r.repo.requestPhoneSignInCode(
          phoneE164: '+447700900123', createAccount: true));
      expect(failure.code, AuthFailureCode.invalidPhoneNumber);
      expect(r.net.paths.where((p) => p.endsWith('/otp')), isEmpty);
      await r.dispose();
    });

    test('A4 every server refusal maps to a fixed outcome without its text',
        () async {
      final cases = <_Reply, AuthFailureCode>{
        _authError(422, 'otp_disabled'): AuthFailureCode.phoneNotRegistered,
        _authError(429, 'over_sms_send_rate_limit'):
            AuthFailureCode.tooManyRequests,
        _authError(400, 'phone_provider_disabled'):
            AuthFailureCode.smsUnavailable,
        _authError(422, 'signup_disabled'): AuthFailureCode.phoneAuthNotAllowed,
        _authError(400, 'captcha_failed'): AuthFailureCode.captchaFailed,
        const _Reply(403, {'code': 403, 'msg': 'phone_signup_not_allowed'}):
            AuthFailureCode.phoneAuthNotAllowed,
        const _Reply(500, {'code': 500, 'error_code': 'sms_send_failed'}):
            AuthFailureCode.smsUnavailable,
      };
      for (final entry in cases.entries) {
        final net = _Net()..otp = entry.key;
        final r = await _Repo.start(net: net);
        final failure = await _failureOf(() => r.repo
            .requestPhoneSignInCode(phoneE164: _phone, createAccount: true));
        expect(failure.code, entry.value, reason: '${entry.key.body}');
        expect(failure.message, isNot(contains('raw-server-text')));
        expect(failure.originalException, isNull);
        await r.dispose();
      }
    });

    test('A5 no connection is reported as a network failure', () async {
      final net = _Net()..throwOn = '/auth/v1/otp';
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() => r.repo
          .requestPhoneSignInCode(phoneE164: _phone, createAccount: false));
      expect(failure.code, AuthFailureCode.network);
      await r.dispose();
    });
  });

  group('A. Verifying a code', () {
    test('A6 a malformed code never reaches the network', () async {
      final r = await _Repo.start();
      for (final code in ['12345', '1234567', '12a456', '']) {
        final failure = await _failureOf(
            () => r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: code));
        expect(failure.code, AuthFailureCode.otpInvalidOrExpired, reason: code);
      }
      expect(r.net.paths.where((p) => p.endsWith('/verify')), isEmpty);
      await r.dispose();
    });

    test('A7 a verified code is claimed before the identity is published',
        () async {
      final r = await _Repo.start();
      final result =
          await r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456');
      await pumpEventQueue(times: 40);

      final verify = r.net.bodyOf('/auth/v1/verify');
      expect(verify['type'], 'sms');
      expect(verify['phone'], _phone);
      expect(verify['token'], '123456');

      final paths = r.net.paths.toList();
      final claimAt =
          paths.indexWhere((p) => p.endsWith('/rpc/claim_current_app_session'));
      expect(
          claimAt, greaterThan(paths.indexWhere((p) => p.endsWith('/verify'))));
      expect(result.user.uid, _uid);
      expect(result.accountExisted, isFalse);
      expect(r.published.map((u) => u.uid), contains(_uid));
      expect(r.client.auth.currentSession, isNotNull);
      await r.dispose();
    });

    test('A8 a refused claim ends the session and publishes nobody', () async {
      final net = _Net()
        ..claim = const _Reply(500, {'code': '500', 'message': 'boom'});
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() =>
          r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456'));
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.appSessionUnavailable);
      expect(r.published, isEmpty, reason: 'no access without the claim');
      expect(r.client.auth.currentSession, isNull);
      await r.dispose();
    });

    test('A9 a superseded claim is reported as an expired session', () async {
      final net = _Net()
        ..claim = const _Reply(
            403, {'code': '42501', 'message': 'session_superseded'});
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() =>
          r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456'));
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.sessionExpired);
      expect(r.published, isEmpty);
      await r.dispose();
    });

    test('A10 a session for another number is never kept', () async {
      final net = _Net()
        ..verify = _Reply(
            200, _sessionJson(user: _phoneUserJson(phone: '971559999999')));
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() =>
          r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456'));
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.unknown);
      expect(r.client.auth.currentSession, isNull);
      await r.dispose();
    });

    test('A11 a wrong or expired code is one outcome', () async {
      final net = _Net()..verify = _authError(403, 'otp_expired');
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() =>
          r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456'));
      expect(failure.code, AuthFailureCode.otpInvalidOrExpired);
      expect(r.published, isEmpty);
      await r.dispose();
    });

    test('A12 an account with a profile name existed before', () async {
      final r = await _Repo.start();
      r.profiles.profile = _profile(name: 'Existing Broker');
      final result =
          await r.repo.verifyPhoneSignInCode(phoneE164: _phone, code: '123456');
      expect(result.accountExisted, isTrue);
      expect(result.user.name, 'Existing Broker');
      await r.dispose();
    });
  });

  group('A. Sign-up name', () {
    test('A13 the name is written only to a profile without one', () async {
      final r = await _Repo.start(signedIn: true);
      r.profiles.profile = _profile(name: '');
      await r.repo
          .completePhoneSignUpName(expectedUid: _uid, name: '  Sara Ali ');
      final write = r.net.requests
          .lastWhere((q) => q.url.path.endsWith('/rest/v1/profiles'));
      expect(write.method, 'PATCH');
      expect(jsonDecode(write.body), {'name': 'Sara Ali'});
      expect(write.url.queryParameters['id'], 'eq.$_uid');
      await r.dispose();
    });

    test('A14 an existing name is never replaced', () async {
      final r = await _Repo.start(signedIn: true);
      r.profiles.profile = _profile(name: 'Existing Broker');
      final kept =
          await r.repo.completePhoneSignUpName(expectedUid: _uid, name: 'X');
      expect(kept.name, 'Existing Broker');
      expect(
          r.net.paths.where((p) => p.endsWith('/rest/v1/profiles')), isEmpty);
      await r.dispose();
    });

    test('A15 a different signed-in account is refused without a write',
        () async {
      final r = await _Repo.start(signedIn: true);
      final failure = await _failureOf(() =>
          r.repo.completePhoneSignUpName(expectedUid: _otherUid, name: 'X'));
      expect(failure.code, AuthFailureCode.sessionExpired);
      expect(
          r.net.paths.where((p) => p.endsWith('/rest/v1/profiles')), isEmpty);
      await r.dispose();
    });
  });

  group('B. Code screen', () {
    test('B1 with the build switch off nothing is sent or verified', () async {
      final f = await _Flow.start(enabled: false);
      expect(f.vm.isAvailable, isFalse);
      final outcome = await f.vm.verifyCode('123456');
      expect(outcome, PhoneOtpOutcome.none);
      expect(f.vm.errorKey, 'phoneSignInUnavailable');
      expect(await f.vm.resendCode(), isFalse);
      expect(f.auth.verifyCalls, 0);
      expect(f.auth.requests, isEmpty);
      await f.dispose();
    });

    test('B2 a malformed code is refused locally', () async {
      final f = await _Flow.start();
      expect(await f.vm.verifyCode('12345'), PhoneOtpOutcome.none);
      expect(f.vm.errorKey, 'otpInvalid');
      expect(f.auth.verifyCalls, 0);
      await f.dispose();
    });

    test('B3 success only once the app authenticated that same account',
        () async {
      final f = await _Flow.start();
      final outcome = await f.vm.verifyCode('123456');
      expect(outcome, PhoneOtpOutcome.signedIn);
      expect(f.authVM.status, AuthStatus.authenticated);
      expect(f.authVM.currentUserId, _uid);
      expect(f.vm.errorKey, isNull);
      await f.dispose();
    });

    test('B4 a verify that never becomes access is not success', () async {
      final f = await _Flow.start();
      f.auth.publishOnVerify = false;
      final outcome = await f.vm.verifyCode('123456');
      expect(outcome, PhoneOtpOutcome.none);
      expect(f.vm.errorKey, 'appSessionCheckFailed');
      expect(f.authVM.status, isNot(AuthStatus.authenticated));
      await f.dispose();
    });

    test('B5 a refused session check stays on the screen', () async {
      final f = await _Flow.start();
      f.auth.verifyError = const AuthFailure(
          code: AuthFailureCode.appSessionUnavailable, message: 'x');
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.none);
      expect(f.vm.errorKey, 'appSessionCheckFailed');
      expect(f.vm.isVerifying, isFalse);
      await f.dispose();
    });

    test('B6 a second submit while one is in flight is ignored', () async {
      final f = await _Flow.start();
      f.auth.verifyGate = Completer<void>();
      final first = f.vm.verifyCode('123456');
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.none);
      expect(await f.vm.resendCode(), isFalse);
      f.auth.verifyGate!.complete();
      expect(await first, PhoneOtpOutcome.signedIn);
      expect(f.auth.verifyCalls, 1);
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.none,
          reason: 'a completed sign-in is not repeated');
      expect(f.auth.verifyCalls, 1);
      await f.dispose();
    });

    test('B7 sign-up saves the name of a new account', () async {
      final f = await _Flow.start(isSignup: true, name: ' Sara Ali ');
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.signedIn);
      expect(f.auth.names, ['Sara Ali']);
      await f.dispose();
    });

    test('B8 sign-up on an existing account keeps it and says so', () async {
      final f = await _Flow.start(isSignup: true, name: 'Someone Else');
      f.auth.accountExisted = true;
      expect(await f.vm.verifyCode('123456'),
          PhoneOtpOutcome.signedInToExistingAccount);
      expect(f.auth.names, isEmpty);
      await f.dispose();
    });

    test('B9 a failed name save is retried without a second verification',
        () async {
      final f = await _Flow.start(isSignup: true, name: 'Sara');
      f.auth.nameFailuresLeft = 1;
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.none);
      expect(f.vm.errorKey, 'profileSaveFailed');
      expect(f.vm.canResend, isFalse);
      expect(await f.vm.verifyCode(''), PhoneOtpOutcome.signedIn);
      expect(f.auth.verifyCalls, 1);
      expect(f.auth.names, ['Sara', 'Sara']);
      await f.dispose();
    });

    test('B10 login never sends a name', () async {
      final f = await _Flow.start(name: 'ignored');
      expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.signedIn);
      expect(f.auth.names, isEmpty);
      await f.dispose();
    });

    test('B11 server refusals become fixed message keys', () async {
      final cases = <AuthFailureCode, String>{
        AuthFailureCode.otpInvalidOrExpired: 'phoneCodeInvalidOrExpired',
        AuthFailureCode.tooManyRequests: 'authTooManyRequests',
        AuthFailureCode.network: 'authNetworkFailed',
        AuthFailureCode.sessionExpired: 'authSessionExpired',
        AuthFailureCode.phoneAuthNotAllowed: 'phoneSignInUnavailable',
      };
      for (final entry in cases.entries) {
        final f = await _Flow.start();
        f.auth.verifyError = AuthFailure(code: entry.key, message: 'raw');
        expect(await f.vm.verifyCode('123456'), PhoneOtpOutcome.none);
        expect(f.vm.errorKey, entry.value, reason: '${entry.key}');
        await f.dispose();
      }
      expect(
        PhoneOtpViewModel.errorKeyFor(
            const AuthFailure(
                code: AuthFailureCode.phoneAuthNotAllowed, message: 'x'),
            isSignup: true),
        'phoneSignUpUnavailable',
      );
      expect(
        PhoneOtpViewModel.errorKeyFor(
            const AuthFailure(
                code: AuthFailureCode.phoneNotRegistered, message: 'x'),
            isSignup: false),
        'phoneNotRegistered',
      );
    });

    test('B12 resend waits for the countdown and re-requests the code',
        () async {
      final f = await _Flow.start(isSignup: true, name: 'Sara');
      expect(f.vm.secondsRemaining, 3);
      expect(await f.vm.resendCode(), isFalse);
      f.ticker.tick(3);
      expect(f.vm.secondsRemaining, 0);
      expect(await f.vm.resendCode(), isTrue);
      expect(f.auth.requests, [(_phone, true)]);
      expect(f.vm.secondsRemaining, 3, reason: 'a new countdown');
      await f.dispose();
    });

    test('B13 a rate-limited resend waits another full interval', () async {
      final f = await _Flow.start();
      f.ticker.tick(3);
      f.auth.requestError = const AuthFailure(
          code: AuthFailureCode.tooManyRequests, message: 'x');
      expect(await f.vm.resendCode(), isFalse);
      expect(f.vm.errorKey, 'authTooManyRequests');
      expect(f.vm.secondsRemaining, 3);
      expect(f.auth.requests, [(_phone, false)]);
      await f.dispose();
    });

    test('B14 the countdown starts from when the code was requested', () async {
      final now = DateTime(2026, 11, 22, 12);
      final f = await _Flow.start(
        codeSentAt: now.subtract(const Duration(seconds: 2)),
        now: now,
      );
      expect(f.vm.secondsRemaining, 1);
      await f.dispose();
    });
  });

  group('C. Guards', () {
    test('C1 the build default keeps phone authentication off', () {
      expect(SupabaseConfig.phoneAuthEnabled, isFalse);
      expect(SignInViewModel.phoneSignInSupported, isFalse);
      expect(SignUpViewModel.phoneSignUpSupported, isFalse);
      expect(SignInViewModel.initialLoginMethod, LoginMethod.email);
      expect(SignUpViewModel.initialSignupMethod, SignupMethod.email);
    });

    test('C2 the repository sign-in path is the Supabase-native one', () {
      final source =
          _read('lib/src/repositories/supabase_auth_repository.dart');
      final start = source.indexOf('// Phone sign-in / sign-up (Supabase OTP)');
      final end = source.indexOf('/// Supabase Auth may store phones');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final section = source.substring(start, end);
      expect(section, contains('signInWithOtp('));
      expect(section, contains('type: OtpType.sms'));
      expect(section, contains('_authorizeAndPublish(session, claim: true)'));
      expect(section, isNot(contains('data:')),
          reason: 'no metadata is sent with a code request');
      expect(section, isNot(contains('resend(')),
          reason: 'resend type sms sends nothing for a confirmed number');
      expect(section, isNot(contains('debugPrint')));
      expect(section, isNot(contains('print(')));
    });

    test('C3 the phone flow logs nothing', () {
      for (final path in const [
        'lib/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart',
        'lib/src/views/Screens/Sign-Up-Log-In/phone_otp_view.dart',
        'lib/src/data/models/phone_otp_args.dart',
      ]) {
        final source = _read(path);
        expect(source, isNot(contains('print(')), reason: path);
        expect(source, isNot(contains('debugPrint')), reason: path);
        expect(source, isNot(contains('firebase_auth')), reason: path);
      }
    });

    test('C4 every message the flow can show exists in English and Arabic', () {
      final en = _arb('en');
      final ar = _arb('ar');
      for (final key in PhoneOtpViewModel.surfacedKeys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
      }
    });

    test('C5 the code screen carries no Firebase verification id', () {
      final args = _read('lib/src/data/models/phone_otp_args.dart');
      expect(args, isNot(contains('verificationId')));
      expect(args, isNot(contains('resendToken')));
    });
  });
}
