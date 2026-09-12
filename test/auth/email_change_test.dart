import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _oldEmail = 'old@example.test';
const _newEmail = 'new@example.test';

String _fakeJwt(String uid) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _userJson({
  String uid = _uid,
  String email = _oldEmail,
  String? newEmail,
  String? changeSentAt,
}) =>
    {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'email_confirmed_at': '2026-09-11T10:00:00Z',
      if (newEmail != null) 'new_email': newEmail,
      if (changeSentAt != null) 'email_change_sent_at': changeSentAt,
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    };

Map<String, dynamic> _sessionJson({Map<String, dynamic>? user}) => {
      'access_token': _fakeJwt(_uid),
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': user ?? _userJson(),
    };

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _authError(int status, String code) => _json(
      {'code': status, 'error_code': code, 'msg': 'secret-provider-text'},
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
    // Unit transport has no persistent auth-code-verifier store. Production
    // SupabaseFlutter remains on PKCE; implicit here isolates HTTP semantics.
    authOptions: const sb.AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: sb.AuthFlowType.implicit,
    ),
  );

  Future<void> signIn() => client.auth.setInitialSession(
        jsonEncode(_sessionJson()),
      );
}

class _NoProfiles implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SupabaseAuthRepository _repository(_Backend backend) => SupabaseAuthRepository(
    userRepository: _NoProfiles(), client: backend.client);

class _Gateway implements EmailChangeCapability {
  _Gateway(this._state);

  final StreamController<EmailChangeState?> _events =
      StreamController<EmailChangeState?>.broadcast();
  EmailChangeState? _state;
  Completer<void>? requestGate;
  Object? requestError;
  Object? resendError;
  int requests = 0;
  int resends = 0;
  bool applyRequestResult = true;

  EmailChangeState requestResult = const EmailChangeState(
    ownerUid: _uid,
    confirmedEmail: _oldEmail,
    pendingEmail: _newEmail,
  );

  @override
  EmailChangeState? get currentEmailChange => _state;

  @override
  Stream<EmailChangeState?> get emailChangeChanges => _events.stream;

  void emit(EmailChangeState? state) {
    _state = state;
    _events.add(state);
  }

  @override
  Future<EmailChangeState> requestEmailChange(String newEmail) async {
    requests++;
    if (requestGate != null) await requestGate!.future;
    if (requestError != null) throw requestError!;
    if (applyRequestResult) emit(requestResult);
    return requestResult;
  }

  @override
  Future<EmailChangeState> resendEmailChange() async {
    resends++;
    if (resendError != null) throw resendError!;
    return _state!;
  }

  @override
  Future<EmailChangeState?> refreshEmailChange() async => _state;

  Future<void> close() => _events.close();
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
      final active = timer;
      if (active == null || !active.isActive) return;
      onTick!(active);
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

EmailChangeState _state({
  String uid = _uid,
  String confirmed = _oldEmail,
  String? pending,
  DateTime? requestedAt,
}) =>
    EmailChangeState(
      ownerUid: uid,
      confirmedEmail: confirmed,
      pendingEmail: pending,
      requestedAt: requestedAt,
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Supabase email change repository', () {
    test('targets only the live account and retains the confirmed email',
        () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/user')) {
          return _json(
            _userJson(
              newEmail: _newEmail,
              changeSentAt: '2026-09-12T10:00:00Z',
            ),
            200,
          );
        }
        return _json({}, 404);
      });
      await backend.signIn();
      final repository = _repository(backend);

      final state = await repository.requestEmailChange(' NEW@example.test ');

      expect(state.ownerUid, _uid);
      expect(state.confirmedEmail, _oldEmail);
      expect(state.pendingEmail, _newEmail);
      final request = backend.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, endsWith('/auth/v1/user'));
      expect(request.url.queryParameters['redirect_to'], isNotEmpty);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['email'], _newEmail);
      expect(body, isNot(contains('password')));
      expect(body, isNot(contains('user_id')));
      expect(
        backend.requests.where((r) => r.url.path.contains('/rest/v1/profiles')),
        isEmpty,
        reason: 'public.profiles is synchronized server-side only',
      );
      await repository.dispose();
    });

    test('resend addresses the confirmed mailbox, not the pending one',
        () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/user')) {
          return _json(_userJson(newEmail: _newEmail), 200);
        }
        if (request.url.path.endsWith('/auth/v1/resend')) {
          return _json({}, 200);
        }
        return _json({}, 404);
      });
      await backend.signIn();
      final repository = _repository(backend);
      await repository.requestEmailChange(_newEmail);

      final state = await repository.resendEmailChange();

      expect(state.confirmedEmail, _oldEmail);
      expect(state.pendingEmail, _newEmail);
      final request = backend.requests.last;
      expect(request.url.path, endsWith('/auth/v1/resend'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['type'], 'email_change');
      // GoTrue resolves the account with FindUserByEmailAndAudience over
      // users.email, which still holds the confirmed address while a change is
      // pending. Sending the pending address matches no account at all.
      expect(body['email'], _oldEmail);
      expect(body['email'], isNot(_newEmail));
      expect(request.url.queryParameters['redirect_to'], isNotEmpty);
      await repository.dispose();
    });

    test('legacy Supabase contract cannot revive password reauthentication',
        () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/user')) {
          return _json(_userJson(newEmail: _newEmail), 200);
        }
        return _json({}, 404);
      });
      await backend.signIn();
      final repository = _repository(backend);

      await repository.updateEmail(
        newEmail: _newEmail,
        currentPassword: 'must-not-leave-the-client',
      );

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.url.path, endsWith('/auth/v1/user'));
      expect(backend.requests.single.body,
          isNot(contains('must-not-leave-the-client')));
      await repository.dispose();
    });

    test('authoritative refresh publishes the confirmed replacement', () async {
      final backend = _Backend((request) {
        if (request.url.path.endsWith('/auth/v1/user')) {
          return _json(_userJson(email: _newEmail), 200);
        }
        return _json({}, 404);
      });
      await backend.signIn();
      final repository = _repository(backend);
      final confirmed = repository.authStateChanges.firstWhere(
        (user) => user?.email == _newEmail,
      );

      final state = await repository.refreshEmailChange();

      expect(state?.confirmedEmail, _newEmail);
      expect(state?.pendingEmail, isNull);
      expect((await confirmed)?.uid, _uid);
      expect(repository.currentUser?.email, _newEmail);
      expect(repository.currentEmailChange?.confirmedEmail, _newEmail);
      expect(
        backend.requests.where((r) => r.url.path.contains('/rest/v1/profiles')),
        isEmpty,
      );
      await repository.dispose();
    });

    test('typed failures never retain provider text or exceptions', () {
      final cases = <String, AuthFailureCode>{
        'email_address_invalid': AuthFailureCode.invalidEmail,
        'email_exists': AuthFailureCode.emailAlreadyInUse,
        'over_email_send_rate_limit': AuthFailureCode.tooManyRequests,
        'session_not_found': AuthFailureCode.sessionExpired,
        'email_address_not_authorized': AuthFailureCode.providerUnavailable,
        'otp_expired': AuthFailureCode.otpInvalidOrExpired,
      };

      for (final entry in cases.entries) {
        final failure = AuthFailure.fromSupabaseEmailChange(
          sb.AuthException(
            'secret-provider-text',
            code: entry.key,
            statusCode: entry.key.contains('rate') ? '429' : '400',
          ),
        );
        expect(failure.code, entry.value, reason: entry.key);
        expect(failure.message, isNot(contains('secret-provider-text')));
        expect(failure.originalException, isNull);
      }
    });

    test('a server error is sanitized by the real repository boundary',
        () async {
      final backend = _Backend((_) => _authError(422, 'email_exists'));
      await backend.signIn();

      await expectLater(
        _repository(backend).requestEmailChange(_newEmail),
        throwsA(
          isA<AuthFailure>()
              .having((f) => f.code, 'code', AuthFailureCode.emailAlreadyInUse)
              .having((f) => f.message, 'message',
                  isNot(contains('secret-provider-text')))
              .having((f) => f.originalException, 'raw exception', isNull),
        ),
      );
    });
  });

  group('Email change presentation state', () {
    test('validates locally and blocks same-address requests', () async {
      final gateway = _Gateway(_state());
      final vm = EmailChangeViewModel(gateway: gateway);
      await _settle();

      expect(await vm.requestEmailChange('not-an-email'), isFalse);
      expect(vm.errorKey, 'emailChangeInvalidEmail');
      expect(await vm.requestEmailChange(' OLD@example.test '), isFalse);
      expect(vm.errorKey, 'emailSameAsCurrent');
      expect(gateway.requests, 0);

      vm.dispose();
      await gateway.close();
    });

    test('repeated taps produce one request and preserve pending state',
        () async {
      final gateway = _Gateway(_state())..requestGate = Completer<void>();
      final ticker = _Ticker();
      final vm = EmailChangeViewModel(
        gateway: gateway,
        resendCooldown: const Duration(seconds: 3),
        timerFactory: ticker.create,
      );
      await _settle();

      final first = vm.requestEmailChange(_newEmail);
      final second = vm.requestEmailChange(_newEmail);
      expect(await second, isFalse);
      gateway.requestGate!.complete();
      expect(await first, isTrue);
      expect(gateway.requests, 1);
      expect(vm.confirmedEmail, _oldEmail);
      expect(vm.pendingEmail, _newEmail);
      expect(vm.noticeKey, 'emailChangeRequestSent');
      expect(vm.resendSecondsRemaining, 3);

      vm.dispose();
      await gateway.close();
    });

    test('pending state restores on reopen and resend obeys cooldown',
        () async {
      final gateway = _Gateway(_state(pending: _newEmail));
      final ticker = _Ticker();
      final vm = EmailChangeViewModel(
        gateway: gateway,
        resendCooldown: const Duration(seconds: 2),
        timerFactory: ticker.create,
      );
      await _settle();

      expect(vm.isPending, isTrue, reason: 'restored from backend user state');
      expect(vm.confirmedEmail, _oldEmail);
      expect(await vm.resendEmailChange(), isTrue);
      expect(gateway.resends, 1);
      expect(vm.resendSecondsRemaining, 2);
      expect(await vm.resendEmailChange(), isFalse);
      ticker.tick(2);
      expect(await vm.resendEmailChange(), isTrue);
      expect(gateway.resends, 2);

      vm.dispose();
      await gateway.close();
    });

    test('logout removes pending state without leaking it to another account',
        () async {
      final gateway = _Gateway(_state(pending: _newEmail));
      final vm = EmailChangeViewModel(gateway: gateway);
      await _settle();

      gateway.emit(null);
      await _settle();
      expect(vm.state, isNull);
      expect(vm.pendingEmail, isNull);

      gateway.emit(_state(uid: _otherUid, confirmed: 'other@example.test'));
      await _settle();
      expect(vm.confirmedEmail, 'other@example.test');
      expect(vm.pendingEmail, isNull);

      vm.dispose();
      await gateway.close();
    });

    test('a late result from the previous account is discarded', () async {
      final gateway = _Gateway(_state())
        ..requestGate = Completer<void>()
        ..applyRequestResult = false;
      final vm = EmailChangeViewModel(gateway: gateway);
      await _settle();

      final pending = vm.requestEmailChange(_newEmail);
      gateway.emit(_state(uid: _otherUid, confirmed: 'other@example.test'));
      gateway.requestGate!.complete();

      expect(await pending, isFalse);
      expect(vm.errorKey, 'emailChangeAccountChanged');
      expect(vm.confirmedEmail, 'other@example.test');
      expect(vm.pendingEmail, isNull);

      vm.dispose();
      await gateway.close();
    });

    test('unknown errors surface only a fixed localization key', () async {
      final gateway = _Gateway(_state())
        ..requestError = StateError('token=secret raw failure');
      final vm = EmailChangeViewModel(gateway: gateway);
      await _settle();

      expect(await vm.requestEmailChange(_newEmail), isFalse);
      expect(vm.errorKey, 'emailChangeFailed');

      vm.dispose();
      await gateway.close();
    });
  });

  group('Auth owner and scope guards', () {
    test('AuthViewModel exposes email change only for capable repositories',
        () {
      final capable = _CapableAuthRepository();
      final vm = AuthViewModel(
        authRepository: capable,
        userRepository: _NoProfiles(),
        autoInitialize: false,
      );
      expect(vm.emailChange, same(capable));
      vm.dispose();
      capable.close();
    });

    Map<String, dynamic> arb(String language) => jsonDecode(
          File('lib/src/common/localization/app_$language.arb')
              .readAsStringSync(),
        ) as Map<String, dynamic>;

    test('every email-change UI string exists in English and Arabic', () {
      final en = arb('en');
      final ar = arb('ar');
      const keys = {
        'emailChangeSubmit',
        'emailChangeMailboxGuidance',
        'emailChangeCanonicalGuidance',
        'emailChangePendingTitle',
        'emailChangeBothInboxes',
        'emailChangeCheckStatus',
        'emailChangeActiveBadge',
        'emailChangeAwaitingBadge',
        'emailChangeResendReplacesLinks',
        'emailChangeUseDifferent',
        'emailChangePartiallyConfirmed',
        'emailChangeStillPending',
        'view',
        'resendEmailChange',
        'resendEmailChangeIn',
        'emailChangeInvalidEmail',
        'emailChangeAlreadyInUse',
        'emailChangeRateLimited',
        'emailChangeNetworkError',
        'emailChangeLinkExpired',
        'emailChangeSessionExpired',
        'emailChangeAccountChanged',
        'emailChangeNoPending',
        'emailChangeUnavailable',
        'emailChangeFailed',
        'emailChangeRequestSent',
        'emailChangeCompleted',
        'emailChangeResent',
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
      }
      expect(en['resendEmailChangeIn'], contains('{seconds}'));
      expect(ar['resendEmailChangeIn'], contains('{seconds}'));
    });

    test('the new flow has no cancel API, Firebase import, logs, or raw errors',
        () {
      final capability =
          File('lib/src/repositories/auth_repository.dart').readAsStringSync();
      final viewModel = File('lib/src/viewmodels/email_change_viewmodel.dart')
          .readAsStringSync();
      final sheet = File('lib/src/Views/Widgets/email_change_sheet.dart')
          .readAsStringSync();
      final pendingSheet =
          File('lib/src/Views/Widgets/email_change_pending_sheet.dart')
              .readAsStringSync();
      expect(capability, isNot(contains('cancelEmailChange')));
      for (final source in [viewModel, sheet, pendingSheet]) {
        expect(source, isNot(contains('firebase_auth')));
        expect(source, isNot(contains('print(')));
        expect(source, isNot(contains('debugPrint')));
        expect(source, isNot(contains('toString()')));
      }
    });
  });
}

class _CapableAuthRepository implements AuthRepository, EmailChangeCapability {
  final StreamController<UserModel?> _auth =
      StreamController<UserModel?>.broadcast();

  @override
  EmailChangeState? get currentEmailChange => _state();

  @override
  Stream<EmailChangeState?> get emailChangeChanges => const Stream.empty();

  @override
  UserModel? get currentUser => null;

  @override
  String? get currentUserId => null;

  @override
  Stream<UserModel?> get authStateChanges => _auth.stream;

  @override
  Future<EmailChangeState> requestEmailChange(String newEmail) async =>
      _state();

  @override
  Future<EmailChangeState> resendEmailChange() async => _state();

  @override
  Future<EmailChangeState?> refreshEmailChange() async => _state();

  void close() => _auth.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
