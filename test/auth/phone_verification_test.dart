import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/phone_verification_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _phone = '+971501234567';

UserSubscription _subscription() =>
    UserSubscription(plan: 'test', isActive: false, features: const []);

UserModel _identity({
  String uid = _uid,
  String? phone,
  bool phoneVerified = false,
}) =>
    UserModel(
      uid: uid,
      name: 'Phone User',
      email: 'phone@example.test',
      phoneNumber: phone,
      createdAt: DateTime(2026, 9, 11),
      isEmailVerified: true,
      isPhoneVerified: phoneVerified,
      subscription: _subscription(),
      preferences: const {},
    );

// ---------------------------------------------------------------------------
// Repository harness: a real SupabaseClient on a recorded transport.
// ---------------------------------------------------------------------------

String _fakeJwt(String uid) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _userJson({
  String uid = _uid,
  String? phone,
  String? phoneConfirmedAt,
}) =>
    {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'phone@example.test',
      'email_confirmed_at': '2026-09-11T10:00:00Z',
      'phone': phone ?? '',
      if (phoneConfirmedAt != null) 'phone_confirmed_at': phoneConfirmedAt,
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    };

Map<String, dynamic> _sessionJson({String uid = _uid, Map<String, dynamic>? user}) =>
    {
      'access_token': _fakeJwt(uid),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': user ?? _userJson(uid: uid),
    };

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _authError(int status, String code) => _json(
      {'code': status, 'error_code': code, 'msg': 'raw-server-text $code'},
      status,
    );

class _Backend {
  _Backend(this.handler);

  final http.Response Function(http.Request request) handler;
  final List<http.Request> requests = [];

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() =>
      client.auth.setInitialSession(jsonEncode(_sessionJson()));

  Iterable<String> get paths => requests.map((r) => r.url.path);
}

class _NoProfiles implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SupabaseAuthRepository _repository(_Backend backend) =>
    SupabaseAuthRepository(userRepository: _NoProfiles(), client: backend.client);

// ---------------------------------------------------------------------------
// View model harness.
// ---------------------------------------------------------------------------

class _SessionAuthRepository implements AuthRepository {
  _SessionAuthRepository(this._current);

  final StreamController<UserModel?> _events =
      StreamController<UserModel?>.broadcast();
  UserModel? _current;

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
  Future<void> signOut() async => emit(null);

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements UserRepository {
  UserModel? profile;

  @override
  Future<UserModel?> getUserById(String uid) async =>
      profile?.uid == uid ? profile : null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllable stand-in for the Supabase phone-verification calls.
class _Gateway implements PhoneVerificationCapability {
  Completer<void>? sendGate;
  Completer<UserModel>? verifyGate;
  Object? sendError;
  Object? resendError;
  Object? verifyError;
  UserModel? confirmed;

  final List<String> sent = [];
  final List<String> resent = [];
  final List<String> verified = [];

  @override
  Future<void> requestPhoneVerification(String phoneE164) async {
    sent.add(phoneE164);
    if (sendGate != null) await sendGate!.future;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> resendPhoneVerification(String phoneE164) async {
    resent.add(phoneE164);
    if (resendError != null) throw resendError!;
  }

  @override
  Future<UserModel> confirmPhoneVerification({
    required String phoneE164,
    required String code,
  }) async {
    verified.add(code);
    if (verifyGate != null) return verifyGate!.future;
    if (verifyError != null) throw verifyError!;
    return confirmed ?? _identity(phone: phoneE164, phoneVerified: true);
  }
}

/// Captures the resend ticker so the countdown can be advanced by hand.
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
  _Flow._(this.auth, this.authVM, this.gateway, this.ticker, this.vm);

  final _SessionAuthRepository auth;
  final AuthViewModel authVM;
  final _Gateway gateway;
  final _Ticker ticker;
  final PhoneVerificationViewModel vm;

  static Future<_Flow> signedIn() async {
    final auth = _SessionAuthRepository(_identity());
    final authVM = AuthViewModel(authRepository: auth, userRepository: _Profiles());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(authVM.status, AuthStatus.authenticated);

    final gateway = _Gateway();
    final ticker = _Ticker();
    final vm = PhoneVerificationViewModel(
      authViewModel: authVM,
      gateway: gateway,
      resendCooldown: const Duration(seconds: 3),
      timerFactory: ticker.create,
    );
    return _Flow._(auth, authVM, gateway, ticker, vm);
  }

  Future<void> dispose() async {
    vm.dispose();
    authVM.dispose();
    await auth.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('UAE phone normalization', () {
    test('every common form normalizes to the same E.164 number', () {
      for (final input in const [
        '0501234567',
        '050 123 4567',
        '050-123-4567',
        '+971501234567',
        '+971 50 123 4567',
        '971501234567',
        '+9710501234567',
      ]) {
        expect(PhoneNumberNormalizer.normalizeUaeMobile(input), _phone,
            reason: input);
      }
    });

    test('non-mobile, foreign and malformed numbers are rejected', () {
      for (final input in const [
        '',
        'abc',
        '05012345',
        '050123456789',
        '0412345678',
        '+447700900123',
        '+97141234567',
      ]) {
        expect(
          () => PhoneNumberNormalizer.normalizeUaeMobile(input),
          throwsA(isA<PhoneValidationException>()),
          reason: input,
        );
      }
    });
  });

  group('Supabase phone change (repository)', () {
    test('requests a phone change on the signed-in account only', () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/user')) {
          return _json(_userJson(), 200);
        }
        return _json({}, 404);
      });
      await backend.signIn();

      await _repository(backend).requestPhoneVerification('0501234567');

      final request = backend.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, endsWith('/auth/v1/user'));
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(jsonDecode(request.body), containsPair('phone', _phone));
      // Never a sign-up or a phone sign-in: no second identity is possible.
      expect(backend.paths.where((p) => p.endsWith('/signup')), isEmpty);
      expect(backend.paths.where((p) => p.endsWith('/otp')), isEmpty);
    });

    test('a malformed number is rejected before any network call', () async {
      final backend = _Backend((_) => _json({}, 500));
      await backend.signIn();

      await expectLater(
        _repository(backend).requestPhoneVerification('0412345678'),
        throwsA(isA<AuthFailure>().having(
            (f) => f.code, 'code', AuthFailureCode.invalidPhoneNumber)),
      );
      expect(backend.requests, isEmpty);
    });

    test('with no session nothing is sent', () async {
      final backend = _Backend((_) => _json({}, 500));

      await expectLater(
        _repository(backend).requestPhoneVerification(_phone),
        throwsA(isA<AuthFailure>()
            .having((f) => f.code, 'code', AuthFailureCode.sessionExpired)),
      );
      expect(backend.requests, isEmpty);
    });

    test('confirmation keeps the same account and reads it from Supabase',
        () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/verify')) {
          // Supabase Auth may report the phone without its leading "+".
          return _json(
            _sessionJson(
              user: _userJson(
                phone: '971501234567',
                phoneConfirmedAt: '2026-09-11T10:05:00Z',
              ),
            ),
            200,
          );
        }
        return _json({}, 404);
      });
      await backend.signIn();

      final user = await _repository(backend)
          .confirmPhoneVerification(phoneE164: _phone, code: '123456');

      expect(user.uid, _uid, reason: 'same canonical account');
      expect(user.isPhoneVerified, isTrue);

      final verify = backend.requests.single;
      final body = jsonDecode(verify.body) as Map<String, dynamic>;
      expect(body['type'], 'phone_change');
      expect(body['phone'], _phone);
      expect(body['token'], '123456');
    });

    test('an accepted code without confirmation is not treated as verified',
        () async {
      // A secure two-step change accepts the first code but confirms nothing.
      final backend = _Backend((_) =>
          _json({'user': _userJson(phone: '')}, 200));
      await backend.signIn();

      await expectLater(
        _repository(backend)
            .confirmPhoneVerification(phoneE164: _phone, code: '123456'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('confirmation of a different number is not accepted', () async {
      final backend = _Backend((_) => _json(
            _sessionJson(
              user: _userJson(
                phone: '971559999999',
                phoneConfirmedAt: '2026-09-11T10:05:00Z',
              ),
            ),
            200,
          ));
      await backend.signIn();

      await expectLater(
        _repository(backend)
            .confirmPhoneVerification(phoneE164: _phone, code: '123456'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('resend asks for a new phone-change code for the same number',
        () async {
      final backend = _Backend((_) => _json({}, 200));
      await backend.signIn();

      await _repository(backend).resendPhoneVerification(_phone);

      final request = backend.requests.single;
      expect(request.url.path, endsWith('/auth/v1/resend'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['type'], 'phone_change');
      expect(body['phone'], _phone);
    });

    Future<AuthFailure> failureFor(http.Response response,
        Future<void> Function(SupabaseAuthRepository) action) async {
      final backend = _Backend((_) => response);
      await backend.signIn();
      try {
        await action(_repository(backend));
      } on AuthFailure catch (failure) {
        return failure;
      }
      fail('expected an AuthFailure');
    }

    test('server failures map to typed outcomes with no raw text', () async {
      final cases = <String, (http.Response, AuthFailureCode)>{
        'wrong code': (_authError(403, 'otp_expired'),
            AuthFailureCode.otpInvalidOrExpired),
        'rate limited': (_authError(429, 'over_sms_send_rate_limit'),
            AuthFailureCode.tooManyRequests),
        'SMS provider': (_authError(500, 'sms_send_failed'),
            AuthFailureCode.smsUnavailable),
        'provider off': (_authError(400, 'phone_provider_disabled'),
            AuthFailureCode.smsUnavailable),
        'number taken': (_authError(422, 'phone_exists'),
            AuthFailureCode.phoneAlreadyInUse),
        'session gone': (_authError(403, 'session_not_found'),
            AuthFailureCode.sessionExpired),
        // gotrue drops the code on any 5xx; an unrecognized server error is a
        // generic failure, not a connectivity problem.
        'server error': (_authError(502, 'unexpected_failure'),
            AuthFailureCode.unknown),
      };

      for (final entry in cases.entries) {
        final (response, expected) = entry.value;
        final failure = await failureFor(
          response,
          (repo) => repo.confirmPhoneVerification(
              phoneE164: _phone, code: '123456'),
        );
        expect(failure.code, expected, reason: entry.key);
        expect(failure.message, isNot(contains('raw-server-text')),
            reason: entry.key);
        expect(failure.originalException, isNull, reason: entry.key);
      }
    });
  });

  test('a dropped connection is reported as a network failure', () async {
    final backend = _Backend((_) => throw http.ClientException('offline'));
    await backend.signIn();

    await expectLater(
      _repository(backend).requestPhoneVerification(_phone),
      throwsA(isA<AuthFailure>()
          .having((f) => f.code, 'code', AuthFailureCode.network)),
    );
  });

  group('Verification flow (view model)', () {
    test('a malformed number is rejected before any network call', () async {
      final f = await _Flow.signedIn();

      expect(await f.vm.sendCode('0412345678'), isFalse);

      expect(f.gateway.sent, isEmpty);
      expect(f.vm.errorKey, 'invalidUAEPhoneNumber');
      expect(f.vm.phase, PhoneVerificationPhase.idle);
      await f.dispose();
    });

    test('sends the canonical number exactly once under repeated taps',
        () async {
      final f = await _Flow.signedIn();
      f.gateway.sendGate = Completer<void>();

      final first = f.vm.sendCode('050 123 4567');
      final second = f.vm.sendCode('0501234567');
      expect(f.vm.isBusy, isTrue);

      f.gateway.sendGate!.complete();
      expect(await first, isTrue);
      expect(await second, isFalse);

      expect(f.gateway.sent, [_phone]);
      expect(f.vm.phase, PhoneVerificationPhase.awaitingCode);
      await f.dispose();
    });

    test('the resend countdown gates resend, then allows it', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      expect(f.vm.resendSecondsRemaining, 3);
      expect(f.vm.canResend, isFalse);
      expect(await f.vm.resendCode(), isFalse);
      expect(f.gateway.resent, isEmpty);

      f.ticker.tick(3);
      expect(f.vm.resendSecondsRemaining, 0);
      expect(f.vm.canResend, isTrue);

      expect(await f.vm.resendCode(), isTrue);
      expect(f.gateway.resent, [_phone]);
      expect(f.vm.resendSecondsRemaining, 3, reason: 'countdown restarts');
      await f.dispose();
    });

    test('the resend cooldown never decides whether a code is still valid',
        () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      // During the cooldown the sent code can be submitted.
      expect(f.vm.canResend, isFalse);
      f.gateway.verifyError = const AuthFailure(
          code: AuthFailureCode.otpInvalidOrExpired, message: 'bad');
      await f.vm.verifyCode('111111');
      expect(f.gateway.verified, ['111111'],
          reason: 'the cooldown does not gate verification');

      // The cooldown ending only re-enables Resend. It does not expire the
      // code locally: submitting it still asks Supabase, the sole authority
      // on validity.
      f.gateway.verifyError = null;
      f.ticker.tick(3);
      expect(f.vm.canResend, isTrue);
      expect(f.vm.phase, PhoneVerificationPhase.awaitingCode);

      expect(await f.vm.verifyCode('123456'), isTrue);
      expect(f.gateway.verified, ['111111', '123456']);
      await f.dispose();
    });

    test('a rate-limited resend restarts the countdown honestly', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');
      f.ticker.tick(3);
      f.gateway.resendError = const AuthFailure(
          code: AuthFailureCode.tooManyRequests, message: 'limited');

      expect(await f.vm.resendCode(), isFalse);

      expect(f.vm.errorKey, 'authTooManyRequests');
      expect(f.vm.canResend, isFalse);
      await f.dispose();
    });

    test('a failed send leaves a clean, retryable state', () async {
      final f = await _Flow.signedIn();
      f.gateway.sendError = const AuthFailure(
          code: AuthFailureCode.network, message: 'offline');

      expect(await f.vm.sendCode('0501234567'), isFalse);
      expect(f.vm.phase, PhoneVerificationPhase.idle);
      expect(f.vm.errorKey, 'authNetworkFailed');

      f.gateway.sendError = null;
      expect(await f.vm.sendCode('0501234567'), isTrue);
      expect(f.gateway.sent, hasLength(2));
      await f.dispose();
    });

    test('a wrong or expired code keeps the user on the code step', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');
      f.gateway.verifyError = const AuthFailure(
          code: AuthFailureCode.otpInvalidOrExpired, message: 'bad');

      expect(await f.vm.verifyCode('111111'), isFalse);

      expect(f.vm.phase, PhoneVerificationPhase.awaitingCode);
      expect(f.vm.errorKey, 'phoneCodeInvalidOrExpired');

      f.gateway.verifyError = null;
      expect(await f.vm.verifyCode('123456'), isTrue, reason: 'can retry');
      await f.dispose();
    });

    test('an incomplete code is rejected without a network call', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      expect(await f.vm.verifyCode('12a4'), isFalse);

      expect(f.gateway.verified, isEmpty);
      expect(f.vm.errorKey, 'otpInvalid');
      await f.dispose();
    });

    test('a second verify while one is in flight is ignored', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');
      f.gateway.verifyGate = Completer<UserModel>();

      final first = f.vm.verifyCode('123456');
      final second = f.vm.verifyCode('123456');
      expect(await second, isFalse);

      f.gateway.verifyGate!
          .complete(_identity(phone: _phone, phoneVerified: true));
      expect(await first, isTrue);
      expect(f.gateway.verified, ['123456']);
      await f.dispose();
    });

    test('success never sets a verified flag on the client', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      expect(await f.vm.verifyCode('123456'), isTrue);
      expect(f.vm.phase, PhoneVerificationPhase.verified);

      // Nothing on the client asserted it. The canonical user changes only
      // when Supabase reports the confirmed phone through the auth stream.
      expect(f.authVM.currentUser?.isPhoneVerified, isFalse);

      f.auth.emit(_identity(phone: '971501234567', phoneVerified: true));
      await settle();
      expect(f.authVM.currentUser?.isPhoneVerified, isTrue);
      expect(f.authVM.currentUser?.uid, _uid, reason: 'same account');
      await f.dispose();
    });

    test('signing out abandons the pending verification', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      await f.authVM.signOut();
      await settle();

      expect(f.vm.phase, PhoneVerificationPhase.idle);
      expect(f.vm.phoneE164, isNull);
      expect(f.vm.errorKey, 'authSessionExpired');
      expect(await f.vm.verifyCode('123456'), isFalse);
      expect(f.gateway.verified, isEmpty);
      await f.dispose();
    });

    test('an account switch cannot apply the previous verification', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');

      f.auth.emit(_identity(uid: _otherUid));
      await settle();

      expect(f.vm.phase, PhoneVerificationPhase.idle);
      expect(await f.vm.verifyCode('123456'), isFalse);
      expect(f.gateway.verified, isEmpty);
      await f.dispose();
    });

    test('a result arriving after the account changed is discarded', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');
      f.gateway.verifyGate = Completer<UserModel>();

      final pending = f.vm.verifyCode('123456');
      f.auth.emit(_identity(uid: _otherUid));
      await settle();
      f.gateway.verifyGate!
          .complete(_identity(phone: _phone, phoneVerified: true));

      expect(await pending, isFalse);
      expect(f.vm.phase, isNot(PhoneVerificationPhase.verified));
      await f.dispose();
    });

    test('a confirmation for another account is refused', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCode('0501234567');
      f.gateway.confirmed =
          _identity(uid: _otherUid, phone: _phone, phoneVerified: true);

      expect(await f.vm.verifyCode('123456'), isFalse);
      expect(f.vm.phase, isNot(PhoneVerificationPhase.verified));
      await f.dispose();
    });

    test('raw failures surface only as localizable keys', () async {
      final f = await _Flow.signedIn();
      f.gateway.sendError = StateError('SocketException token=abc123');

      await f.vm.sendCode('0501234567');

      // An unexplained refusal to start is a neutral "not right now": the
      // server-side pending-number guard surfaces exactly this way, and must
      // not be disclosed or invite repeated retries.
      expect(f.vm.errorKey, 'phoneVerificationUnavailableNow');
      expect(PhoneVerificationViewModel.surfacedErrorKeys,
          contains(f.vm.errorKey));
      await f.dispose();
    });
  });

  group('Verified status authority', () {
    test('markPhoneVerified cannot assert verification or fabricate a session',
        () async {
      final auth = _SessionAuthRepository(null);
      final authVM =
          AuthViewModel(authRepository: auth, userRepository: _Profiles());
      await settle();
      expect(authVM.status, AuthStatus.unauthenticated);

      await authVM.markPhoneVerified(phoneNumber: _phone);

      expect(authVM.status, AuthStatus.unauthenticated,
          reason: 'no session means not signed in, whatever a code said');
      expect(authVM.currentUser, isNull);

      auth.emit(_identity());
      await settle();
      await authVM.markPhoneVerified(phoneNumber: _phone);
      expect(authVM.currentUser?.isPhoneVerified, isFalse);

      authVM.dispose();
      await auth.close();
    });
  });

  group('Localization and scope guards', () {
    Map<String, dynamic> arb(String language) => json.decode(
          File('lib/src/common/localization/app_$language.arb')
              .readAsStringSync(),
        ) as Map<String, dynamic>;

    test('every surfaced message exists in English and Arabic', () {
      final en = arb('en');
      final ar = arb('ar');
      final keys = {
        ...PhoneVerificationViewModel.surfacedErrorKeys,
        'verifyPhoneNumber',
        'otpSentTo',
        'enterOTP',
        'resendCode',
        'resending',
        'resendCodeIn',
        'otpResent',
        'otpSent',
        'phoneVerifiedSuccessfully',
        'verify',
        'cancel',
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
      }
      expect(en['otpSentTo'], contains('{phone}'));
      expect(ar['otpSentTo'], contains('{phone}'));
      expect(en['resendCodeIn'], contains('{seconds}'));
      expect(ar['resendCodeIn'], contains('{seconds}'));
    });

    test('the new phone flow logs nothing and uses no Firebase auth', () {
      for (final path in const [
        'lib/src/viewmodels/phone_verification_viewmodel.dart',
        'lib/src/views/Widgets/phone_otp_dialog.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('print(')), reason: path);
        expect(source, isNot(contains('debugPrint')), reason: path);
        expect(source, isNot(contains('firebase_auth')), reason: path);
      }
    });

    test('no Apple, Google or Facebook provider work was introduced', () {
      expect(File('pubspec.yaml').readAsStringSync(),
          isNot(contains('sign_in_with_apple')));
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('signInWithApple')), reason: file.path);
        expect(source, isNot(contains('OAuthProvider.apple')),
            reason: file.path);
        expect(source, isNot(contains('OAuthProvider.google')),
            reason: file.path);
      }
    });
  });
}
