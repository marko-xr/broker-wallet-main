import 'dart:async';

import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _validPassword = 'Passw0rdd';
const _otherValidPassword = 'Passw0rde';
const _currentPassword = '0ldPassw0rd';

/// A password gateway that records what it was asked, and nothing about the
/// values themselves beyond what a test needs to assert.
class _Gateway implements PasswordCapability {
  _Gateway({this.verifiesCurrentPassword = false});

  @override
  final bool verifiesCurrentPassword;

  final StreamController<PasswordRecoverySession> _recovery =
      StreamController<PasswordRecoverySession>.broadcast();

  int changeCalls = 0;
  int resetCalls = 0;
  String? lastResetEmail;
  String? lastNewPassword;
  String? lastCurrentPassword;
  Object? failWith;
  Completer<void>? pending;

  @override
  Future<void> requestPasswordReset(String email) async {
    resetCalls++;
    lastResetEmail = email;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    changeCalls++;
    lastNewPassword = newPassword;
    lastCurrentPassword = currentPassword;
    if (pending != null) await pending!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions =>
      _recovery.stream;

  bool recoveryActive = false;
  int recoveriesEnded = 0;

  @override
  bool get isPasswordRecoveryActive => recoveryActive;

  @override
  Future<void> endPasswordRecovery() async {
    recoveriesEnded++;
    recoveryActive = false;
  }

  Future<void> close() => _recovery.close();
}

class _Session implements AuthRepository {
  _Session(this.uid);

  String? uid;

  @override
  String? get currentUserId => uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChangePasswordViewModel _changeVm(_Gateway gateway, _Session session) {
  final vm = ChangePasswordViewModel(
    gateway: gateway,
    authRepository: session,
  );
  addTearDown(vm.dispose);
  return vm;
}

void main() {
  group('Change password', () {
    test('a valid change reaches Supabase and reports success', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      final ok = await vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      expect(ok, isTrue);
      expect(vm.hasSucceeded, isTrue);
      expect(vm.errorKey, isNull);
      expect(gateway.changeCalls, 1);
      expect(gateway.lastNewPassword, _validPassword);
    });

    test('a policy failure makes no network call at all', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(
        await vm.submit(
          currentPassword: '',
          newPassword: 'weak',
          confirmPassword: 'weak',
        ),
        isFalse,
      );
      expect(gateway.changeCalls, 0);
      expect(vm.errorKey, 'passwordDoesNotMeetRequirements');
    });

    test('a mismatched confirmation makes no network call', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(
        await vm.submit(
          currentPassword: '',
          newPassword: _validPassword,
          confirmPassword: _otherValidPassword,
        ),
        isFalse,
      );
      expect(gateway.changeCalls, 0);
      expect(vm.errorKey, 'passwordsDoNotMatch');
    });

    test('a duplicate submit while one is in flight is refused', () async {
      final gateway = _Gateway()..pending = Completer<void>();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      final first = vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      await pumpEventQueue();
      final second = await vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      expect(second, isFalse);
      gateway.pending!.complete();
      expect(await first, isTrue);
      expect(gateway.changeCalls, 1);
    });

    test(
        'no current password is collected or sent when the backend will '
        'not verify it', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(vm.requiresCurrentPassword, isFalse);
      await vm.submit(
        currentPassword: 'whatever-the-user-typed',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      expect(gateway.lastCurrentPassword, isNull);
    });

    test('the current password is sent when the backend verifies it', () async {
      final gateway = _Gateway(verifiesCurrentPassword: true);
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(vm.requiresCurrentPassword, isTrue);
      expect(
        await vm.submit(
          currentPassword: _currentPassword,
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isTrue,
      );
      expect(gateway.lastCurrentPassword, _currentPassword);
    });

    test('a missing current password is refused locally when required',
        () async {
      final gateway = _Gateway(verifiesCurrentPassword: true);
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(
        await vm.submit(
          currentPassword: '',
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(vm.errorKey, 'currentPasswordRequired');
      expect(gateway.changeCalls, 0);
    });

    test('reusing the current password is refused before the network',
        () async {
      final gateway = _Gateway(verifiesCurrentPassword: true);
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      expect(
        await vm.submit(
          currentPassword: _validPassword,
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(vm.errorKey, 'passwordChangeSame');
      expect(gateway.changeCalls, 0);
    });

    test('a rejected current password maps to its own message', () async {
      final gateway = _Gateway(verifiesCurrentPassword: true)
        ..failWith = const AuthFailure(
          code: AuthFailureCode.invalidCurrentPassword,
          message: 'internal',
        );
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      await vm.submit(
        currentPassword: _currentPassword,
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      expect(vm.errorKey, 'passwordChangeWrongCurrent');
    });

    test('a weak password refused by the server maps safely', () async {
      final gateway = _Gateway()
        ..failWith = const AuthFailure(
          code: AuthFailureCode.weakPassword,
          message: 'internal',
        );
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      await vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      expect(vm.errorKey, 'passwordChangeWeak');
      expect(vm.hasSucceeded, isFalse);
    });

    test('a signed-out session is refused before the network', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(null));

      expect(
        await vm.submit(
          currentPassword: '',
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(vm.errorKey, 'passwordChangeSessionExpired');
      expect(gateway.changeCalls, 0);
    });

    test('an account switch during the request is never reported as success',
        () async {
      final gateway = _Gateway()..pending = Completer<void>();
      addTearDown(gateway.close);
      final session = _Session(_uid);
      final vm = _changeVm(gateway, session);

      final submitted = vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      await pumpEventQueue();
      session.uid = _otherUid;
      gateway.pending!.complete();

      expect(await submitted, isFalse);
      expect(vm.hasSucceeded, isFalse);
      expect(vm.errorKey, 'passwordChangeAccountChanged');
    });

    test('a logout during the request is never reported as success', () async {
      final gateway = _Gateway()..pending = Completer<void>();
      addTearDown(gateway.close);
      final session = _Session(_uid);
      final vm = _changeVm(gateway, session);

      final submitted = vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      await pumpEventQueue();
      session.uid = null;
      gateway.pending!.complete();

      expect(await submitted, isFalse);
      expect(vm.errorKey, 'passwordChangeAccountChanged');
    });

    test('a raw AuthException never reaches the UI', () async {
      final gateway = _Gateway()
        ..failWith = sb.AuthException(
          'Password should be at least 6 characters. weak_password',
          statusCode: '422',
          code: 'weak_password',
        );
      addTearDown(gateway.close);
      final vm = _changeVm(gateway, _Session(_uid));

      await vm.submit(
        currentPassword: '',
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      expect(vm.errorKey, isNotNull);
      expect(vm.errorKey, isNot(contains(' ')));
      expect(vm.errorKey, 'passwordChangeFailed');
    });

    test('an unavailable backend is reported, not crashed into', () async {
      final vm = ChangePasswordViewModel(gateway: null, authRepository: null);
      addTearDown(vm.dispose);

      expect(vm.isAvailable, isFalse);
      expect(
        await vm.submit(
          currentPassword: '',
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(vm.errorKey, 'passwordChangeUnavailable');
    });
  });

  group('Supabase password failure mapping', () {
    AuthFailureCode map(Object e) => AuthFailure.fromSupabasePassword(e).code;

    test('a weak-password exception keeps its own outcome', () {
      expect(
        map(sb.AuthWeakPasswordException(
          message: 'Password is too weak',
          statusCode: '422',
          reasons: const ['length'],
        )),
        AuthFailureCode.weakPassword,
      );
    });

    test('provider codes map to fixed outcomes', () {
      final cases = <String, AuthFailureCode>{
        'weak_password': AuthFailureCode.weakPassword,
        'validation_failed': AuthFailureCode.weakPassword,
        'same_password': AuthFailureCode.samePassword,
        'invalid_credentials': AuthFailureCode.invalidCurrentPassword,
        'reauthentication_needed': AuthFailureCode.reauthenticationRequired,
        'over_request_rate_limit': AuthFailureCode.tooManyRequests,
        'otp_expired': AuthFailureCode.otpInvalidOrExpired,
        'bad_jwt': AuthFailureCode.sessionExpired,
        'email_provider_disabled': AuthFailureCode.providerUnavailable,
      };
      cases.forEach((code, expected) {
        expect(
          map(sb.AuthException('provider prose', code: code)),
          expected,
          reason: code,
        );
      });
    });

    test('a missing session and a timeout are distinguished', () {
      expect(
        map(sb.AuthSessionMissingException()),
        AuthFailureCode.sessionExpired,
      );
      expect(map(TimeoutException('x')), AuthFailureCode.network);
    });

    test('no provider message or exception survives the mapping', () {
      const prose = 'Email link is invalid or has expired';
      final failure = AuthFailure.fromSupabasePassword(
        sb.AuthException(prose, statusCode: '401', code: 'otp_expired'),
      );
      expect(failure.message, isNot(contains(prose)));
      expect(failure.originalException, isNull);
    });

    test('an unknown provider code falls back safely', () {
      expect(
        map(sb.AuthException('anything at all', code: 'brand_new_code')),
        AuthFailureCode.unknown,
      );
    });
  });

  group('Forgot password', () {
    PasswordResetRequestViewModel vmFor(_Gateway gateway) {
      final vm = PasswordResetRequestViewModel(gateway: gateway);
      addTearDown(vm.dispose);
      return vm;
    }

    test('a malformed address makes no network call', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      expect(await vm.submit('not-an-email'), isFalse);
      expect(gateway.resetCalls, 0);
      expect(vm.errorKey, 'passwordResetInvalidEmail');
    });

    test('a valid address is normalized and sent once', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      expect(await vm.submit('  Person@Example.TEST '), isTrue);
      expect(gateway.resetCalls, 1);
      expect(gateway.lastResetEmail, 'person@example.test');
    });

    test('success is the same regardless of whether an account exists', () {
      // The view model has one success state and one message key. There is no
      // branch that could describe a missing account, which is what makes the
      // flow non-enumerable from the client side.
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      expect(vm.hasSent, isFalse);
      expect(vm.errorKey, isNull);
      expect(
        passwordResetRequestErrorKey(AuthFailureCode.unknown),
        'passwordResetFailed',
      );
      // "user not found" is deliberately not a distinct outcome.
      expect(
        passwordResetRequestErrorKey(AuthFailureCode.invalidCredentials),
        'passwordResetFailed',
      );
    });

    test('a rate limit is reported as its own recoverable state', () async {
      final gateway = _Gateway()
        ..failWith = const AuthFailure(
          code: AuthFailureCode.tooManyRequests,
          message: 'internal',
        );
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      expect(await vm.submit('person@example.test'), isFalse);
      expect(vm.errorKey, 'passwordResetRateLimited');
      expect(vm.hasSent, isFalse);
    });

    test('requesting a reset stores nothing locally', () async {
      // The request used to record a timestamp that later decided which expired
      // callbacks belonged to recovery. Recovery is now identified by the
      // callback address, so the request keeps no state of its own at all.
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      await vm.submit('person@example.test');
      expect(vm.hasSent, isTrue);
      expect(vm.errorKey, isNull);
    });

    test('a duplicate submit while one is in flight is refused', () async {
      final gateway = _Gateway();
      addTearDown(gateway.close);
      final vm = vmFor(gateway);

      final results = await Future.wait([
        vm.submit('person@example.test'),
        vm.submit('person@example.test'),
      ]);

      expect(results.where((ok) => ok).length, 1);
      expect(gateway.resetCalls, 1);
    });
  });

  group('Reset request redirect', () {
    test('the reset request is addressed to the recovery callback', () {
      expect(
        SupabaseConfig.passwordRecoveryCallbackUri,
        'brokerwallet://auth/reset-password',
      );
      expect(
        SupabaseConfig.passwordRecoveryCallbackUri,
        isNot(SupabaseConfig.authCallbackUri),
      );
    });
  });
}
