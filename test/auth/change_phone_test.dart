// Change Phone for phone accounts (C4, Model X): the Worker proves the current
// number (a Supabase code) and the new number (the verification provider) for
// the current app session, then changes the sign-in number itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/contact_phone_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/change_phone_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/change_phone_codes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _session1 = '6f1f6c1e-0000-4000-8000-000000000001';
const _session2 = '6f1f6c1e-0000-4000-8000-000000000002';
const _current = '+971501111111';
const _new = '+971507777777';
const _worker = 'https://worker.test';

UserModel _identity({String uid = _uid, String? phone = _current}) => UserModel(
      uid: uid,
      name: 'Pat',
      email: '',
      phoneNumber: phone,
      createdAt: DateTime(2026, 11, 22),
      isEmailVerified: false,
      isPhoneVerified: true,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: const []),
      preferences: const {},
    );

// ---------------------------------------------------------------------------
// A. Worker gateway
// ---------------------------------------------------------------------------

WorkerContactPhoneGateway _gateway(
  List<http.Request> sent,
  http.Response Function(http.Request) answer,
) =>
    WorkerContactPhoneGateway(
      workerUrl: _worker,
      httpClient: MockClient((request) async {
        sent.add(request);
        return answer(request);
      }),
    );

http.Response _reply(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

// ---------------------------------------------------------------------------
// B. Repository harness (real SupabaseClient, SAD-authorized session)
// ---------------------------------------------------------------------------

String _b64(Map<String, Object?> v) =>
    base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');

Map<String, Object?> _sessionJson({
  String sessionId = _session1,
  String phone = '971501111111',
  String email = '',
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': _uid,
          'session_id': sessionId,
          'exp': now + 3600,
          'iat': now,
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
      'email': email,
      'phone': phone,
      if (phone.isNotEmpty) 'phone_confirmed_at': '2026-11-01T10:00:00Z',
      'app_metadata': {'provider': phone.isNotEmpty ? 'phone' : 'email'},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-11-01T09:59:00Z',
    },
  };
}

class _Net extends http.BaseClient {
  bool sessionCurrent = true;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r);
    final path = r.url.path;
    final Object body = path.endsWith('/rpc/is_current_app_session') ||
            path.endsWith('/rpc/claim_current_app_session')
        ? sessionCurrent
        : <String, Object?>{};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _NoSocket {
  Never call(String url, Map<String, String> headers) =>
      throw const SocketException('test transport: no WebSocket is opened');
}

class _RepoProfiles implements UserRepository {
  UserModel? profile;
  @override
  Future<UserModel?> getUserById(String uid) async => profile;
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChangeGateway implements PhoneNumberChangeGateway {
  final List<(String, String)> starts = [];
  final List<(String, String, String, String?)> confirms = [];
  Object? startError;
  Object? confirmError;
  String confirmedPhone = _new;
  int _next = 0;

  @override
  Future<String> startSignInNumberChange({
    required String accessToken,
    required String newPhoneE164,
  }) async {
    if (startError != null) throw startError!;
    starts.add((accessToken, newPhoneE164));
    return 'verification-${++_next}';
  }

  @override
  Future<String> confirmSignInNumberChange({
    required String accessToken,
    required String verificationId,
    required String newCode,
    String? currentCode,
  }) async {
    confirms.add((accessToken, verificationId, newCode, currentCode));
    if (confirmError != null) throw confirmError!;
    return confirmedPhone;
  }
}

class _Repo {
  _Repo._(
      this.net, this.client, this.repo, this.gateway, this.profiles, this.sub);
  final _Net net;
  final sb.SupabaseClient client;
  final SupabaseAuthRepository repo;
  final _ChangeGateway gateway;
  final _RepoProfiles profiles;
  final StreamSubscription<UserModel?> sub;

  static Future<_Repo> start({
    String phone = '971501111111',
    String email = '',
    bool current = true,
  }) async {
    final net = _Net()..sessionCurrent = current;
    final client = sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: net,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: _NoSocket().call),
    );
    await client.auth.setInitialSession(
        jsonEncode(_sessionJson(phone: phone, email: email)));
    final gateway = _ChangeGateway();
    final profiles = _RepoProfiles();
    final repo = SupabaseAuthRepository(
      userRepository: profiles,
      client: client,
      phoneNumberChanges: gateway,
    );
    final sub = repo.authStateChanges.listen((_) {}, onError: (_) {});
    await pumpEventQueue(times: 40);
    net.requests.clear();
    return _Repo._(net, client, repo, gateway, profiles, sub);
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
// C. View model harness
// ---------------------------------------------------------------------------

class _PhoneAuth
    implements AuthRepository, SignInPhoneSource, PhoneNumberChangeCapability {
  _PhoneAuth(this._current);

  final StreamController<UserModel?> _events =
      StreamController<UserModel?>.broadcast();
  UserModel? _current;
  String? signInPhone = '+971501111111';

  Completer<void>? confirmGate;
  Object? requestError;
  Object? confirmError;
  bool proven = false;
  final List<String> requests = [];
  final List<(String, String, String?)> confirms = [];

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _current;
    yield* _events.stream;
  }

  @override
  UserModel? get currentUser => _current;

  @override
  String? get currentUserId => _current?.uid;

  @override
  String? get currentSignInPhoneE164 => _current == null ? null : signInPhone;

  @override
  bool get currentNumberProven => proven;

  @override
  Future<void> requestPhoneNumberChange(String newPhoneE164) async {
    requests.add(newPhoneE164);
    if (requestError != null) throw requestError!;
  }

  @override
  Future<UserModel> confirmPhoneNumberChange({
    required String newPhoneE164,
    required String newCode,
    String? currentCode,
  }) async {
    confirms.add((newPhoneE164, newCode, currentCode));
    if (confirmGate != null) await confirmGate!.future;
    final error = confirmError;
    if (error != null) {
      if (error is NewNumberCodeRejected) proven = true;
      throw error;
    }
    return _identity(phone: newPhoneE164);
  }

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
  @override
  Future<UserModel?> getUserById(String uid) async => null;
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
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
  final ChangePhoneViewModel vm;

  static Future<_Flow> signedIn({String? signInPhone = _current}) async {
    final auth = _PhoneAuth(_identity())..signInPhone = signInPhone;
    final authVM =
        AuthViewModel(authRepository: auth, userRepository: _Profiles());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(authVM.status, AuthStatus.authenticated);
    final ticker = _Ticker();
    final vm = ChangePhoneViewModel(
      authViewModel: authVM,
      resendCooldown: const Duration(seconds: 3),
      timerFactory: ticker.create,
    );
    return _Flow._(auth, authVM, ticker, vm);
  }

  Future<void> dispose() async {
    vm.dispose();
    authVM.dispose();
    await auth.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('A. Worker gateway', () {
    test(
        'start sends the new number with the session token, never the '
        'current number or a user id', () async {
      final sent = <http.Request>[];
      final gateway =
          _gateway(sent, (_) => _reply({'verificationId': 'v-1'}, 200));
      expect(
        await gateway.startSignInNumberChange(
            accessToken: 'live-token', newPhoneE164: _new),
        'v-1',
      );
      final request = sent.single;
      expect(request.url.toString(), '$_worker/account/phone-identity/start');
      expect(request.headers['Authorization'], 'Bearer live-token');
      expect(
          jsonDecode(request.body), {'newPhone': _new, 'currentProof': 'sms'});
    });

    test(
        'confirm sends both codes, or only the new one once the current is '
        'proven', () async {
      final sent = <http.Request>[];
      final gateway = _gateway(
          sent, (_) => _reply({'status': 'changed', 'phone': _new}, 200));
      expect(
        await gateway.confirmSignInNumberChange(
            accessToken: 't',
            verificationId: 'v-1',
            newCode: '654321',
            currentCode: '123456'),
        _new,
      );
      expect(jsonDecode(sent.last.body), {
        'verificationId': 'v-1',
        'newCode': '654321',
        'currentCode': '123456'
      });
      await gateway.confirmSignInNumberChange(
          accessToken: 't', verificationId: 'v-1', newCode: '654321');
      expect(jsonDecode(sent.last.body),
          {'verificationId': 'v-1', 'newCode': '654321'});
    });

    test(
        'a rejected new-number code is told apart from a rejected current '
        'one', () async {
      final sent = <http.Request>[];
      var answer = _reply({'error': 'invalid_code'}, 422);
      final gateway = _gateway(sent, (_) => answer);
      final rejectedNew = await _failureOf(() =>
          gateway.confirmSignInNumberChange(
              accessToken: 't',
              verificationId: 'v',
              newCode: '1',
              currentCode: '2'));
      expect(rejectedNew, isA<NewNumberCodeRejected>());
      expect(rejectedNew.code, AuthFailureCode.otpInvalidOrExpired);

      answer = _reply({'error': 'current_proof_failed'}, 403);
      final rejectedCurrent = await _failureOf(() =>
          gateway.confirmSignInNumberChange(
              accessToken: 't',
              verificationId: 'v',
              newCode: '1',
              currentCode: '2'));
      expect(rejectedCurrent, isNot(isA<NewNumberCodeRejected>()));
      expect(rejectedCurrent.code, AuthFailureCode.invalidCurrentPassword);

      // On the contact route invalid_code stays an ordinary failure.
      answer = _reply({'error': 'invalid_code'}, 422);
      final contact = await _failureOf(() => gateway.confirmContactPhone(
          accessToken: 't', verificationId: 'v', code: '1'));
      expect(contact, isNot(isA<NewNumberCodeRejected>()));
    });

    test('number-change refusals map to fixed outcomes', () async {
      final cases = <String, (int, AuthFailureCode)>{
        'reauthentication_unsupported': (
          409,
          AuthFailureCode.operationNotAllowed
        ),
        'not_available_for_account': (409, AuthFailureCode.operationNotAllowed),
        'account_mismatch': (403, AuthFailureCode.accountChanged),
        'phone_unavailable': (409, AuthFailureCode.phoneAlreadyInUse),
        'session_superseded': (403, AuthFailureCode.sessionExpired),
        'phone_change_failed': (502, AuthFailureCode.unknown),
        'verification_unavailable': (503, AuthFailureCode.smsUnavailable),
      };
      for (final entry in cases.entries) {
        final (status, code) = entry.value;
        final gateway =
            _gateway([], (_) => _reply({'error': entry.key}, status));
        final failure = await _failureOf(() => gateway.startSignInNumberChange(
            accessToken: 't', newPhoneE164: _new));
        expect(failure.code, code, reason: entry.key);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('B. Repository', () {
    test('the sign-in number comes from Supabase Auth: phone accounts only',
        () async {
      final phone = await _Repo.start();
      expect(phone.repo.currentSignInPhoneE164, _current);
      await phone.dispose();
      final email = await _Repo.start(phone: '', email: 'sara@example.test');
      expect(email.repo.currentSignInPhoneE164, isNull,
          reason: 'an email account never signs in by phone');
      await email.dispose();
    });

    test('a change is started for the session account with its token',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange('0507777777');
      final (token, phone) = r.gateway.starts.single;
      expect(phone, _new);
      expect(token, r.client.auth.currentSession!.accessToken);
      // Supabase Auth is never asked to change the phone directly.
      for (final request in r.net.requests) {
        expect(request.url.path, isNot(endsWith('/auth/v1/user')));
        expect(request.url.path, isNot(endsWith('/auth/v1/verify')));
      }
      await r.dispose();
    });

    test(
        'an email account, the same number, a bad number or a superseded '
        'session send nothing', () async {
      final email = await _Repo.start(phone: '', email: 'sara@example.test');
      expect(
          (await _failureOf(() => email.repo.requestPhoneNumberChange(_new)))
              .code,
          AuthFailureCode.operationNotAllowed);
      expect(email.gateway.starts, isEmpty);
      await email.dispose();

      final r = await _Repo.start();
      expect(
          (await _failureOf(() => r.repo.requestPhoneNumberChange(_current)))
              .code,
          AuthFailureCode.operationNotAllowed);
      expect(
          (await _failureOf(
                  () => r.repo.requestPhoneNumberChange('0412345678')))
              .code,
          AuthFailureCode.invalidPhoneNumber);
      expect(r.gateway.starts, isEmpty);
      await r.dispose();

      final superseded = await _Repo.start(current: false);
      expect(
          (await _failureOf(
                  () => superseded.repo.requestPhoneNumberChange(_new)))
              .code,
          AuthFailureCode.sessionExpired);
      expect(superseded.gateway.starts, isEmpty);
      await superseded.dispose();
    });

    test(
        'confirm uses the pending verification and returns the same account '
        'with the new number', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange(_new);
      final user = await r.repo.confirmPhoneNumberChange(
          newPhoneE164: _new, newCode: '654321', currentCode: '123456');
      final (_, id, newCode, currentCode) = r.gateway.confirms.single;
      expect(id, 'verification-1');
      expect(newCode, '654321');
      expect(currentCode, '123456');
      expect(user.uid, _uid);
      expect(user.phoneNumber, _new);
      expect(r.repo.currentSignInPhoneE164, _new,
          reason: 'the new number is used before the next token refresh');
      expect(r.net.requests.where((q) => q.url.path.endsWith('/auth/v1/token')),
          isEmpty,
          reason: 'no forced refresh (a refused refresh signs the user out)');
      await r.dispose();
    });

    test('without a pending change, or for another number, nothing is sent',
        () async {
      final r = await _Repo.start();
      expect(
          (await _failureOf(() => r.repo.confirmPhoneNumberChange(
                  newPhoneE164: _new,
                  newCode: '654321',
                  currentCode: '123456')))
              .code,
          AuthFailureCode.otpInvalidOrExpired);
      await r.repo.requestPhoneNumberChange(_new);
      expect(
          (await _failureOf(() => r.repo.confirmPhoneNumberChange(
                  newPhoneE164: '+971508888888',
                  newCode: '654321',
                  currentCode: '123456')))
              .code,
          AuthFailureCode.otpInvalidOrExpired);
      expect(r.gateway.confirms, isEmpty);
      await r.dispose();
    });

    test('a mistyped new code keeps the proven current number for the retry',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange(_new);
      r.gateway.confirmError = const NewNumberCodeRejected();
      await _failureOf(() => r.repo.confirmPhoneNumberChange(
          newPhoneE164: _new, newCode: '000000', currentCode: '123456'));
      expect(r.repo.currentNumberProven, isTrue);
      r.gateway.confirmError = null;
      await r.repo.confirmPhoneNumberChange(
          newPhoneE164: _new, newCode: '654321', currentCode: '123456');
      expect(r.gateway.confirms.last.$4, isNull,
          reason: 'the current-number code is not sent again');
      await r.dispose();
    });

    test('a rejected current code is not marked proven', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange(_new);
      r.gateway.confirmError = const AuthFailure(
          code: AuthFailureCode.invalidCurrentPassword, message: 'x');
      await _failureOf(() => r.repo.confirmPhoneNumberChange(
          newPhoneE164: _new, newCode: '654321', currentCode: '000000'));
      expect(r.repo.currentNumberProven, isFalse);
      await r.dispose();
    });

    test('the server confirming another number is not accepted', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange(_new);
      r.gateway.confirmedPhone = '+971509999999';
      expect(
          (await _failureOf(() => r.repo.confirmPhoneNumberChange(
                  newPhoneE164: _new,
                  newCode: '654321',
                  currentCode: '123456')))
              .code,
          AuthFailureCode.unknown);
      await r.dispose();
    });

    test('after a session switch the old change is not used', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneNumberChange(_new);
      await r.client.auth
          .setInitialSession(jsonEncode(_sessionJson(sessionId: _session2)));
      await pumpEventQueue(times: 40);
      final failure = await _failureOf(() => r.repo.confirmPhoneNumberChange(
          newPhoneE164: _new, newCode: '654321', currentCode: '123456'));
      expect(
          failure.code,
          anyOf(AuthFailureCode.otpInvalidOrExpired,
              AuthFailureCode.sessionExpired));
      expect(r.gateway.confirms, isEmpty);
      await r.dispose();
    });

    test('a network failure during start leaves nothing pending', () async {
      final r = await _Repo.start();
      r.gateway.startError =
          const AuthFailure(code: AuthFailureCode.network, message: 'x');
      await _failureOf(() => r.repo.requestPhoneNumberChange(_new));
      r.gateway.startError = null;
      expect(
          (await _failureOf(() => r.repo.confirmPhoneNumberChange(
                  newPhoneE164: _new,
                  newCode: '654321',
                  currentCode: '123456')))
              .code,
          AuthFailureCode.otpInvalidOrExpired);
      await r.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('C. View model', () {
    test('only a phone account can change its sign-in number here', () async {
      final phone = await _Flow.signedIn();
      expect(phone.vm.isAvailable, isTrue);
      await phone.dispose();
      final email = await _Flow.signedIn(signInPhone: null);
      expect(email.vm.isAvailable, isFalse);
      expect(await email.vm.sendCodes(_new), isFalse);
      expect(email.vm.errorKey, 'phoneVerificationUnavailableNow');
      expect(email.auth.requests, isEmpty);
      await email.dispose();
    });

    test('the same or a malformed number is refused locally', () async {
      final f = await _Flow.signedIn();
      expect(await f.vm.sendCodes('0501111111'), isFalse);
      expect(f.vm.errorKey, 'changePhoneSameNumber');
      expect(await f.vm.sendCodes('0412345678'), isFalse);
      expect(f.vm.errorKey, 'invalidUAEPhoneNumber');
      expect(f.auth.requests, isEmpty);
      await f.dispose();
    });

    test(
        'both codes are needed, then only the new one once the current '
        'number is proven', () async {
      final f = await _Flow.signedIn();
      expect(await f.vm.sendCodes('0507777777'), isTrue);
      expect(f.vm.phase, ChangePhonePhase.awaitingCodes);
      expect(f.vm.currentPhoneE164, _current);
      expect(f.vm.newPhoneE164, _new);

      expect(await f.vm.verify(currentCode: '', newCode: '654321'), isFalse);
      expect(f.vm.errorKey, 'otpInvalid');
      expect(f.auth.confirms, isEmpty);

      f.auth.confirmError = const NewNumberCodeRejected();
      expect(
          await f.vm.verify(currentCode: '123456', newCode: '000000'), isFalse);
      expect(f.vm.errorKey, 'phoneCodeInvalidOrExpired');
      expect(f.vm.currentNumberProven, isTrue);

      f.auth.confirmError = null;
      expect(await f.vm.verify(currentCode: '', newCode: '654321'), isTrue);
      expect(f.auth.confirms.last, (_new, '654321', null));
      expect(f.vm.phase, ChangePhonePhase.changed);
      await f.dispose();
    });

    test('a rejected current code has its own message', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCodes(_new);
      f.auth.confirmError = const AuthFailure(
          code: AuthFailureCode.invalidCurrentPassword, message: 'x');
      expect(
          await f.vm.verify(currentCode: '000000', newCode: '654321'), isFalse);
      expect(f.vm.errorKey, 'changePhoneCurrentCodeInvalid');
      expect(f.vm.phase, ChangePhonePhase.awaitingCodes);
      await f.dispose();
    });

    test('signing out abandons the change; a late result is discarded',
        () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCodes(_new);
      f.auth.confirmGate = Completer<void>();
      final pending = f.vm.verify(currentCode: '123456', newCode: '654321');
      await settle();
      f.auth.emit(null);
      await settle();
      f.auth.confirmGate!.complete();
      expect(await pending, isFalse);
      expect(f.vm.phase, ChangePhonePhase.idle);
      await f.dispose();
    });

    test('an account switch cannot apply the previous change', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCodes(_new);
      f.auth.emit(_identity(uid: _otherUid));
      await settle();
      expect(f.vm.phase, ChangePhonePhase.idle);
      expect(
          await f.vm.verify(currentCode: '123456', newCode: '654321'), isFalse);
      expect(f.auth.confirms, isEmpty);
      await f.dispose();
    });

    test('resend waits for the countdown and a rate limit restarts it',
        () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCodes(_new);
      expect(f.vm.canResend, isFalse);
      f.ticker.tick(3);
      expect(f.vm.canResend, isTrue);
      f.auth.requestError = const AuthFailure(
          code: AuthFailureCode.tooManyRequests, message: 'x');
      expect(await f.vm.resendCodes(), isFalse);
      expect(f.vm.errorKey, 'authTooManyRequests');
      expect(f.vm.resendSecondsRemaining, 3);
      f.ticker.tick(3);
      f.auth.requestError = null;
      expect(await f.vm.resendCodes(), isTrue);
      expect(f.auth.requests, [_new, _new, _new]);
      await f.dispose();
    });

    test('a second verify while one is running is ignored', () async {
      final f = await _Flow.signedIn();
      await f.vm.sendCodes(_new);
      f.auth.confirmGate = Completer<void>();
      final first = f.vm.verify(currentCode: '123456', newCode: '654321');
      await settle();
      expect(
          await f.vm.verify(currentCode: '123456', newCode: '654321'), isFalse);
      f.auth.confirmGate!.complete();
      expect(await first, isTrue);
      expect(f.auth.confirms, hasLength(1));
      await f.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('D. Screens and texts', () {
    late Map<String, dynamic> en;
    late Map<String, dynamic> ar;

    setUpAll(() async {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          final file = File(key);
          if (!file.existsSync()) return null;
          final bytes = Uint8List.fromList(file.readAsBytesSync());
          return ByteData.view(bytes.buffer);
        },
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'),
        (call) async => true,
      );
      await AppLocalizations.preloadAllLanguages();
      en = json.decode(
              File('lib/src/common/localization/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      ar = json.decode(
              File('lib/src/common/localization/app_ar.arb').readAsStringSync())
          as Map<String, dynamic>;
    });

    Widget dialogApp(ChangePhoneViewModel vm,
            {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          theme: AppTheme.lightTheme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: ChangeNotifierProvider<ChangePhoneViewModel>.value(
              value: vm,
              child: const ChangePhoneCodesDialog(),
            ),
          ),
        );

    testWidgets('the code dialog asks for both codes, then only the new one',
        (tester) async {
      final auth = _PhoneAuth(_identity());
      final authVM =
          AuthViewModel(authRepository: auth, userRepository: _Profiles());
      await tester.pump();
      final vm = ChangePhoneViewModel(
        authViewModel: authVM,
        resendCooldown: Duration.zero,
      );
      addTearDown(() {
        vm.dispose();
        authVM.dispose();
      });
      await tester.runAsync(() => vm.sendCodes(_new));
      await tester.pumpWidget(dialogApp(vm));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.textContaining('+971501111111'), findsOneWidget);
      expect(find.textContaining('+971507777777'), findsOneWidget);
      ElevatedButton verifyButton() =>
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(verifyButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pump();
      expect(verifyButton().onPressed, isNull,
          reason: 'the new code is missing');
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.pump();
      expect(verifyButton().onPressed, isNotNull);

      auth.confirmError = const NewNumberCodeRejected();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the proven current number is not asked again');
      expect(
          find.text(en['phoneCodeInvalidOrExpired'] as String), findsOneWidget);
    });

    testWidgets('Arabic renders the code dialog without overflow',
        (tester) async {
      final auth = _PhoneAuth(_identity());
      final authVM =
          AuthViewModel(authRepository: auth, userRepository: _Profiles());
      await tester.pump();
      final vm = ChangePhoneViewModel(
          authViewModel: authVM, resendCooldown: Duration.zero);
      addTearDown(() {
        vm.dispose();
        authVM.dispose();
      });
      await tester.runAsync(() => vm.sendCodes(_new));
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(dialogApp(vm, locale: const Locale('ar')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(ar['changePhoneNumber'] as String), findsOneWidget);
    });

    test('every Change Phone text exists in English and Arabic', () {
      for (final key in {
        ...ChangePhoneViewModel.surfacedErrorKeys,
        'changePhoneNumber',
        'changePhoneInfo',
        'changePhoneCurrentCode',
        'changePhoneNewCode',
        'phoneChangedSuccessfully',
        'change',
      }) {
        expect(en[key], isA<String>(), reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
      }
      expect(en['changePhoneCurrentCode'], contains('{phone}'));
      expect(ar['changePhoneNewCode'], contains('{phone}'));
    });

    test(
        'Edit Profile offers Change only to phone accounts; Add Phone keeps '
        'its own texts', () {
      final view =
          File('lib/src/views/Screens/home/Profile/edit_profile_view.dart')
              .readAsStringSync();
      expect(
          view,
          contains(
              'authVM.signInPhoneE164 != null && authVM.phoneNumberChange != null'));
      expect(view, contains("titleKey: 'changePhoneNumber'"));
      expect(view, contains('Icons.lock_outline'),
          reason: 'an email account\'s contact number stays read-only');
      final dialog = File('lib/src/views/Widgets/phone_addition_dialog.dart')
          .readAsStringSync();
      expect(dialog, contains("this.titleKey = 'addPhoneNumber'"));
      expect(dialog, contains("this.infoKey = 'phoneAdditionInfo'"));
    });
  });
}
