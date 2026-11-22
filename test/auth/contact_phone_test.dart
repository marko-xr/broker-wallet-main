// Model X contact numbers (C3): an email account's phone number is verified
// by the Worker as a CONTACT number. Supabase Auth's phone change is never
// used, so the number can never sign anyone in.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/contact_phone_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _session1 = '6f1f6c1e-0000-4000-8000-000000000001';
const _session2 = '6f1f6c1e-0000-4000-8000-000000000002';
const _phone = '+971501234567';
const _worker = 'https://worker.test';

String _b64(Map<String, Object?> v) =>
    base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');

Map<String, Object?> _userJson() => {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'sara@example.test',
      'email_confirmed_at': '2026-11-01T10:00:00Z',
      'phone': '',
      'app_metadata': {
        'provider': 'email',
        'providers': ['email'],
      },
      'user_metadata': <String, Object?>{},
      'created_at': '2026-11-01T09:59:00Z',
    };

Map<String, Object?> _sessionJson({String sessionId = _session1}) {
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
    'user': _userJson(),
  };
}

/// Supabase transport: the session check answers [sessionCurrent]; every
/// other request is recorded and answered with an empty object.
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

class _Profiles implements UserRepository {
  UserModel? profile;
  @override
  Future<UserModel?> getUserById(String uid) async => profile;
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements ContactPhoneGateway {
  final List<(String, String)> starts = [];
  final List<(String, String, String)> confirms = [];
  Object? startError;
  Object? confirmError;
  String confirmedPhone = _phone;
  int _next = 0;

  @override
  Future<String> startContactPhone({
    required String accessToken,
    required String phoneE164,
  }) async {
    if (startError != null) throw startError!;
    starts.add((accessToken, phoneE164));
    return 'verification-${++_next}';
  }

  @override
  Future<String> confirmContactPhone({
    required String accessToken,
    required String verificationId,
    required String code,
  }) async {
    confirms.add((accessToken, verificationId, code));
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
  final _Gateway gateway;
  final _Profiles profiles;
  final StreamSubscription<UserModel?> sub;

  /// A repository whose restored session has passed (or failed) the session
  /// check, as after app start.
  static Future<_Repo> start(
      {bool signedIn = true, bool current = true}) async {
    final net = _Net()..sessionCurrent = current;
    final client = sb.SupabaseClient(
      'http://127.0.0.1:9',
      'publishable-test-key',
      httpClient: net,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions:
          sb.RealtimeClientOptions(transport: _NoSocket().call),
    );
    if (signedIn) {
      await client.auth.setInitialSession(jsonEncode(_sessionJson()));
    }
    final gateway = _Gateway();
    final profiles = _Profiles();
    final repo = SupabaseAuthRepository(
      userRepository: profiles,
      client: client,
      contactPhones: gateway,
    );
    final sub = repo.authStateChanges.listen((_) {}, onError: (_) {});
    await pumpEventQueue(times: 40);
    net.requests.clear();
    return _Repo._(net, client, repo, gateway, profiles, sub);
  }

  /// Supabase Auth was never asked to put a number on the account.
  void expectNoAuthPhoneWrite() {
    for (final r in net.requests) {
      final path = r.url.path;
      expect(path, isNot(endsWith('/auth/v1/verify')), reason: path);
      expect(path, isNot(endsWith('/auth/v1/resend')), reason: path);
      expect(path, isNot(endsWith('/auth/v1/otp')), reason: path);
      if (path.endsWith('/auth/v1/user') && r.method == 'PUT') {
        expect(jsonDecode(r.body), isNot(contains('phone')), reason: path);
      }
    }
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

UserModel _profile({String? phone, bool verified = false}) => UserModel(
      uid: _uid,
      name: 'Sara',
      email: 'sara@example.test',
      phoneNumber: phone,
      createdAt: DateTime(2026, 11, 1),
      isEmailVerified: true,
      isPhoneVerified: verified,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: const []),
      preferences: const {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('Worker gateway', () {
    late List<http.Request> sent;

    WorkerContactPhoneGateway gatewayAnswering(
      http.Response Function(http.Request) answer, {
      String workerUrl = _worker,
    }) {
      sent = [];
      return WorkerContactPhoneGateway(
        workerUrl: workerUrl,
        httpClient: MockClient((request) async {
          sent.add(request);
          return answer(request);
        }),
      );
    }

    http.Response reply(Object body, int status) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );

    test('start sends only the bearer token and the number', () async {
      final gateway = gatewayAnswering((_) =>
          reply({'verificationId': 'v-1', 'expiresInSeconds': 600}, 200));
      final id = await gateway.startContactPhone(
          accessToken: 'access-token', phoneE164: _phone);

      expect(id, 'v-1');
      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$_worker/account/contact-phone/start');
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {'phone': _phone});
    });

    test('confirm returns the number only when the server reports it verified',
        () async {
      final ok = gatewayAnswering(
          (_) => reply({'status': 'verified', 'phone': _phone}, 200));
      expect(
        await ok.confirmContactPhone(
            accessToken: 't', verificationId: 'v-1', code: '654321'),
        _phone,
      );
      expect(jsonDecode(sent.single.body),
          {'verificationId': 'v-1', 'code': '654321'});
      expect(sent.single.url.path, '/account/contact-phone/confirm');

      final unexpected = gatewayAnswering((_) => reply({'phone': _phone}, 200));
      final failure = await _failureOf(() => unexpected.confirmContactPhone(
          accessToken: 't', verificationId: 'v-1', code: '654321'));
      expect(failure.code, AuthFailureCode.unknown);
    });

    test('every Worker refusal maps to a typed failure with no server text',
        () async {
      final cases = <String, (int, AuthFailureCode)>{
        'session_expired': (401, AuthFailureCode.sessionExpired),
        'session_superseded': (403, AuthFailureCode.sessionExpired),
        'session_mismatch': (403, AuthFailureCode.sessionExpired),
        'recovery_session': (403, AuthFailureCode.operationNotAllowed),
        'invalid_phone': (400, AuthFailureCode.invalidPhoneNumber),
        'invalid_code': (422, AuthFailureCode.otpInvalidOrExpired),
        'verification_expired': (410, AuthFailureCode.otpInvalidOrExpired),
        'verification_not_found': (404, AuthFailureCode.otpInvalidOrExpired),
        'rate_limited': (429, AuthFailureCode.tooManyRequests),
        'too_many_attempts': (429, AuthFailureCode.tooManyRequests),
        'phone_unavailable': (409, AuthFailureCode.phoneAlreadyInUse),
        'phone_already_verified': (409, AuthFailureCode.operationNotAllowed),
        'not_available_for_account': (409, AuthFailureCode.operationNotAllowed),
        'verification_unavailable': (503, AuthFailureCode.smsUnavailable),
        'service_unavailable': (503, AuthFailureCode.unknown),
        'unknown': (500, AuthFailureCode.unknown),
      };
      for (final entry in cases.entries) {
        final (status, expected) = entry.value;
        final gateway = gatewayAnswering((_) =>
            reply({'error': entry.key, 'detail': 'raw-server-text'}, status));
        final failure = await _failureOf(() =>
            gateway.startContactPhone(accessToken: 't', phoneE164: _phone));
        expect(failure.code, expected, reason: entry.key);
        expect(failure.message, isNot(contains('raw-server-text')));
        expect(failure.originalException, isNull, reason: entry.key);
      }
      final bare401 = gatewayAnswering((_) => http.Response('nope', 401));
      expect(
        (await _failureOf(() =>
                bare401.startContactPhone(accessToken: 't', phoneE164: _phone)))
            .code,
        AuthFailureCode.sessionExpired,
      );
    });

    test('a dropped connection is a network failure', () async {
      final gateway =
          gatewayAnswering((_) => throw http.ClientException('offline'));
      final failure = await _failureOf(
          () => gateway.startContactPhone(accessToken: 't', phoneE164: _phone));
      expect(failure.code, AuthFailureCode.network);
    });

    test('without a Worker address nothing is sent', () async {
      final gateway = gatewayAnswering((_) => reply({}, 200), workerUrl: '');
      final failure = await _failureOf(
          () => gateway.startContactPhone(accessToken: 't', phoneE164: _phone));
      expect(failure.code, AuthFailureCode.smsUnavailable);
      expect(sent, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('Repository (SupabaseAuthRepository)', () {
    test(
        'Add Phone goes to the Worker with the session token and never to '
        'Supabase Auth', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification('0501234567');

      final (token, phone) = r.gateway.starts.single;
      expect(phone, _phone, reason: 'canonical E.164');
      expect(token, r.client.auth.currentSession!.accessToken);
      r.expectNoAuthPhoneWrite();
      await r.dispose();
    });

    test('a malformed number is refused before any call', () async {
      final r = await _Repo.start();
      final failure =
          await _failureOf(() => r.repo.requestPhoneVerification('0412345678'));
      expect(failure.code, AuthFailureCode.invalidPhoneNumber);
      expect(r.gateway.starts, isEmpty);
      await r.dispose();
    });

    test('with no session nothing is sent', () async {
      final r = await _Repo.start(signedIn: false);
      final failure =
          await _failureOf(() => r.repo.requestPhoneVerification(_phone));
      expect(failure.code, AuthFailureCode.sessionExpired);
      expect(r.gateway.starts, isEmpty);
      await r.dispose();
    });

    test(
        'a session that is not the current app session sends nothing '
        '(Single Active Device)', () async {
      final r = await _Repo.start(current: false);
      final failure =
          await _failureOf(() => r.repo.requestPhoneVerification(_phone));
      expect(failure.code, AuthFailureCode.sessionExpired);
      expect(r.gateway.starts, isEmpty);
      await r.dispose();
    });

    test(
        'confirmation uses the verification this account started and '
        'returns the same account with the contact number verified', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      r.profiles.profile = _profile(phone: _phone, verified: true);

      final user = await r.repo
          .confirmPhoneVerification(phoneE164: _phone, code: '654321');

      final (token, id, code) = r.gateway.confirms.single;
      expect(token, r.client.auth.currentSession!.accessToken);
      expect(id, 'verification-1');
      expect(code, '654321');
      expect(user.uid, _uid);
      expect(user.phoneNumber, _phone);
      expect(user.isPhoneVerified, isTrue);
      expect(user.email, 'sara@example.test',
          reason: 'still the email account; nothing else changed');
      r.expectNoAuthPhoneWrite();
      await r.dispose();
    });

    test('a lagging profile read still reports what the server confirmed',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      r.profiles.profile = _profile();
      final user = await r.repo
          .confirmPhoneVerification(phoneE164: _phone, code: '654321');
      expect(user.phoneNumber, _phone);
      expect(user.isPhoneVerified, isTrue);
      await r.dispose();
    });

    test('a code without a pending verification is refused locally', () async {
      final r = await _Repo.start();
      final failure = await _failureOf(() =>
          r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321'));
      expect(failure.code, AuthFailureCode.otpInvalidOrExpired);
      expect(r.gateway.confirms, isEmpty);
      await r.dispose();
    });

    test('a code for a different number than the pending one is refused',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      final failure = await _failureOf(() => r.repo.confirmPhoneVerification(
          phoneE164: '+971559999999', code: '654321'));
      expect(failure.code, AuthFailureCode.otpInvalidOrExpired);
      expect(r.gateway.confirms, isEmpty);
      await r.dispose();
    });

    test('the server confirming another number is not accepted', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      r.gateway.confirmedPhone = '+971559999999';
      final failure = await _failureOf(() =>
          r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321'));
      expect(failure.code, AuthFailureCode.unknown);
      await r.dispose();
    });

    test('resend starts a new verification and the new one is confirmed',
        () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      await r.repo.resendPhoneVerification(_phone);
      expect(r.gateway.starts, hasLength(2));
      await r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321');
      expect(r.gateway.confirms.single.$2, 'verification-2');
      await r.dispose();
    });

    test('a verification is used once', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      await r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321');
      final failure = await _failureOf(() =>
          r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321'));
      expect(failure.code, AuthFailureCode.otpInvalidOrExpired);
      expect(r.gateway.confirms, hasLength(1));
      await r.dispose();
    });

    test('Worker refusals reach the caller as typed failures', () async {
      final r = await _Repo.start();
      r.gateway.startError = const AuthFailure(
        code: AuthFailureCode.phoneAlreadyInUse,
        message: 'The phone number belongs to another account.',
      );
      final failure =
          await _failureOf(() => r.repo.requestPhoneVerification(_phone));
      expect(failure.code, AuthFailureCode.phoneAlreadyInUse);
      await r.dispose();
    });

    test('a wrong code keeps the verification for another try', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      r.gateway.confirmError = const AuthFailure(
        code: AuthFailureCode.otpInvalidOrExpired,
        message: 'The verification code is invalid or has expired.',
      );
      final failure = await _failureOf(() =>
          r.repo.confirmPhoneVerification(phoneE164: _phone, code: '000000'));
      expect(failure.code, AuthFailureCode.otpInvalidOrExpired);
      r.gateway.confirmError = null;
      await r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321');
      expect(r.gateway.confirms.map((c) => c.$2).toSet(), {'verification-1'});
      await r.dispose();
    });

    test(
        'after an account or session switch the old verification is not '
        'used', () async {
      final r = await _Repo.start();
      await r.repo.requestPhoneVerification(_phone);
      await r.client.auth
          .setInitialSession(jsonEncode(_sessionJson(sessionId: _session2)));
      await pumpEventQueue(times: 40);

      final failure = await _failureOf(() =>
          r.repo.confirmPhoneVerification(phoneE164: _phone, code: '654321'));
      expect(
        failure.code,
        anyOf(AuthFailureCode.otpInvalidOrExpired,
            AuthFailureCode.sessionExpired),
      );
      expect(r.gateway.confirms, isEmpty);
      await r.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('Guards', () {
    test('the app never uses Supabase phone change for Add Phone', () {
      final source = File('lib/src/repositories/supabase_auth_repository.dart')
          .readAsStringSync();
      expect(source, isNot(contains('OtpType.phoneChange')));
      expect(source, isNot(contains('UserAttributes(phone')));
    });

    test('the contact-number gateway logs nothing', () {
      final source = File('lib/src/services/contact_phone_service.dart')
          .readAsStringSync();
      expect(source, isNot(contains('print(')));
      expect(source, isNot(contains('debugPrint')));
      expect(source, isNot(contains('log(')));
    });

    test('the Add Phone text says the number cannot be used to sign in', () {
      Map<String, Object?> arb(String language) => jsonDecode(
            File('lib/src/common/localization/app_$language.arb')
                .readAsStringSync(),
          ) as Map<String, Object?>;
      final en = arb('en')['phoneAdditionInfo'] as String;
      final ar = arb('ar')['phoneAdditionInfo'] as String;
      expect(en, contains("can't be used to sign in"));
      expect(en, isNot(contains('login options')));
      expect(ar, contains('لا يمكن استخدامه لتسجيل الدخول'));
      expect(ar, isNot(contains('خيارات تسجيل الدخول')));
    });
  });
}
