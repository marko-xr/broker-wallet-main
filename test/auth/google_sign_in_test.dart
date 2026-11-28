// Google sign-in / sign-up on Android (task 02A.1).
//
// A. The repository on a real SupabaseClient behind a recorded HTTP layer and
//    a fake Google token source: the exact ID-token request, the Single
//    Active Device claim before any access, cancel, and the error mapping.
//    No real network: loopback URL, a recording client, a throwing Realtime
//    transport.
// B. The google_sign_in adapter against a fake plugin: configuration gate,
//    cancel, the plugin state cleared after every attempt, error codes.
// C. The shared screen flow against a real AuthViewModel, and the Login view
//    model's one-sign-in-at-a-time guard.
// D. Guards: messages in both languages, no leftover "coming soon", no token
//    in logs, the plugin major version pinned with the reason.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/google_id_token_source.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/google_sign_in_flow.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _email = 'owner@example.com';

// ---------------------------------------------------------------------------
// A. Repository harness
// ---------------------------------------------------------------------------

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _googleUserJson({bool confirmed = true}) => {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': _email,
      if (confirmed) 'email_confirmed_at': '2026-11-28T10:00:00Z',
      'phone': '',
      'app_metadata': {
        'provider': 'google',
        'providers': ['google'],
      },
      'user_metadata': {
        'full_name': 'Google Name',
        'name': 'Google Name',
        'email': _email,
        'email_verified': true,
        'iss': 'https://accounts.google.com',
      },
      'created_at': '2026-11-28T09:59:00Z',
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
          'amr': [
            {'method': 'oauth', 'timestamp': now},
          ],
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-secret',
    'user': user ?? _googleUserJson(),
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
  _Reply token = _Reply(200, _sessionJson());
  _Reply claim = const _Reply(200, true);
  bool tokenUnreachable = false;
  final List<http.Request> requests = [];

  Iterable<String> get paths => requests.map((r) => r.url.path);

  Iterable<http.Request> get tokenRequests =>
      requests.where((r) => r.url.path.endsWith('/auth/v1/token'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r);
    final path = r.url.path;
    _Reply reply;
    if (path.endsWith('/auth/v1/token')) {
      if (tokenUnreachable) {
        throw const SocketException('test transport: unreachable');
      }
      reply = token;
    } else if (path.endsWith('/rpc/claim_current_app_session')) {
      reply = claim;
    } else if (path.endsWith('/rpc/is_current_app_session')) {
      reply = const _Reply(200, true);
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

UserModel _profile({String name = 'Profile Name', bool verified = true}) =>
    UserModel(
      uid: _uid,
      name: name,
      email: _email,
      createdAt: DateTime(2026, 11, 28),
      isEmailVerified: verified,
      isPhoneVerified: false,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: const []),
      preferences: const {},
    );

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

class _MemoryStore implements OfflinePassStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// A Google token source that answers what the test sets.
class _FakeTokens implements GoogleIdTokenSource {
  bool configured = true;
  GoogleIdTokens? tokens = const GoogleIdTokens(
    idToken: 'google-id-token',
    accessToken: 'google-access-token',
  );
  Object? error;
  int calls = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<GoogleIdTokens?> obtain() async {
    calls++;
    if (error != null) throw error!;
    return tokens;
  }
}

class _Repo {
  _Repo._(this.net, this.client, this.profiles, this.google, this.repo,
      this.identities, this.sub);

  final _Net net;
  final sb.SupabaseClient client;
  final _Profiles profiles;
  final _FakeTokens google;
  final SupabaseAuthRepository repo;
  final List<UserModel?> identities;
  final StreamSubscription<UserModel?> sub;

  static Future<_Repo> start({_Net? net, _FakeTokens? google}) async {
    final n = net ?? _Net();
    final g = google ?? _FakeTokens();
    final client = _client(n);
    final profiles = _Profiles();
    final repo = SupabaseAuthRepository(
      userRepository: profiles,
      client: client,
      googleIdTokens: g,
    );
    final identities = <UserModel?>[];
    final sub = repo.authStateChanges.listen(identities.add, onError: (_) {});
    await pumpEventQueue(times: 40);
    return _Repo._(n, client, profiles, g, repo, identities, sub);
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
// B. Plugin fakes
// ---------------------------------------------------------------------------

class _FakeAuthentication implements GoogleSignInAuthentication {
  _FakeAuthentication(this.idToken, this.accessToken);

  @override
  final String? idToken;
  @override
  final String? accessToken;
  @override
  String? get serverAuthCode => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccount implements GoogleSignInAccount {
  _FakeAccount({this.idToken = 'plugin-id-token', this.error});

  final String? idToken;
  final String accessToken = 'plugin-access-token';
  final Object? error;

  @override
  Future<GoogleSignInAuthentication> get authentication async {
    if (error != null) throw error!;
    return _FakeAuthentication(idToken, accessToken);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlugin implements GoogleSignIn {
  GoogleSignInAccount? current;
  GoogleSignInAccount? next;
  Object? signInError;
  final List<String> calls = [];

  @override
  GoogleSignInAccount? get currentUser => current;

  @override
  Future<GoogleSignInAccount?> signIn() async {
    calls.add('signIn');
    if (signInError != null) throw signInError!;
    current = next;
    return next;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    calls.add('signOut');
    current = null;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PluginGoogleIdTokenSource _adapter(_FakePlugin plugin) =>
    PluginGoogleIdTokenSource(
      webClientId: 'web-client.apps.googleusercontent.com',
      platform: TargetPlatform.android,
      googleSignIn: plugin,
    );

Future<GoogleTokenFailure> _tokenFailureOf(
    Future<Object?> Function() body) async {
  try {
    await body();
  } on GoogleTokenException catch (e) {
    return e.reason;
  }
  fail('expected a GoogleTokenException');
}

// ---------------------------------------------------------------------------
// C. View model harness
// ---------------------------------------------------------------------------

/// An auth repository that can sign in with Google. Publishing the identity
/// stands for the real repository's "the claim succeeded".
class _GoogleAuth implements AuthRepository {
  final StreamController<UserModel?> _events =
      StreamController<UserModel?>.broadcast();
  UserModel? _current;

  UserModel user = _profile();
  Object? error;
  Completer<void>? gate;
  int calls = 0;

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
  Future<UserModel> signInWithGoogle() async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    _current = user;
    _events.add(user);
    return user;
  }

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  group('A. Repository', () {
    test('A1 an unconfigured build never opens Google or the network',
        () async {
      final google = _FakeTokens()..configured = false;
      final r = await _Repo.start(google: google);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());

      expect(failure.code, AuthFailureCode.providerUnavailable);
      expect(google.calls, 0);
      expect(r.net.tokenRequests, isEmpty);
      await r.dispose();
    });

    test('A2 closing the account picker is a cancel, not a sign-in', () async {
      final google = _FakeTokens()..tokens = null;
      final r = await _Repo.start(google: google);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.cancelled);
      expect(r.net.tokenRequests, isEmpty);
      expect(r.published, isEmpty);
      expect(r.client.auth.currentSession, isNull);
      await r.dispose();
    });

    test('A3 the ID token goes to Supabase and is claimed before any access',
        () async {
      final r = await _Repo.start();
      r.profiles.profile = _profile(name: 'Profile Name');
      final user = await r.repo.signInWithGoogle();
      await pumpEventQueue(times: 40);

      final request = r.net.tokenRequests.single;
      expect(request.url.queryParameters['grant_type'], 'id_token');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['provider'], 'google');
      expect(body['id_token'], 'google-id-token');
      expect(body['access_token'], 'google-access-token');
      expect(body['nonce'], isNull,
          reason: 'the Android token carries no nonce, so none is sent');

      final paths = r.net.paths.toList();
      final tokenAt = paths.indexWhere((p) => p.endsWith('/auth/v1/token'));
      final claimAt =
          paths.indexWhere((p) => p.endsWith('/rpc/claim_current_app_session'));
      expect(claimAt, greaterThan(tokenAt));

      expect(user.uid, _uid);
      expect(user.name, 'Profile Name',
          reason: 'the canonical profile wins over Google metadata');
      expect(r.published.map((u) => u.uid), contains(_uid));
      expect(r.client.auth.currentSession, isNotNull);
      await r.dispose();
    });

    test('A4 before the profile row is readable the auth user is returned',
        () async {
      final r = await _Repo.start();
      final user = await r.repo.signInWithGoogle();

      expect(user.uid, _uid);
      expect(user.email, _email);
      expect(user.name, 'Google Name');
      expect(user.isEmailVerified, isTrue);
      await r.dispose();
    });

    test('A5 a refused claim ends the session and publishes nobody', () async {
      final net = _Net()
        ..claim = const _Reply(500, {'code': '500', 'message': 'boom'});
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.appSessionUnavailable);
      expect(r.published, isEmpty, reason: 'no access without the claim');
      expect(r.client.auth.currentSession, isNull);
      await r.dispose();
    });

    test('A6 a superseded claim is reported as an expired session', () async {
      final net = _Net()
        ..claim = const _Reply(
            403, {'code': '42501', 'message': 'session_superseded'});
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.sessionExpired);
      expect(r.published, isEmpty);
      await r.dispose();
    });

    test('A7 every Supabase refusal maps to a fixed outcome without its text',
        () async {
      final cases = <_Reply, AuthFailureCode>{
        _authError(400, 'provider_disabled'):
            AuthFailureCode.providerUnavailable,
        _authError(422, 'signup_disabled'): AuthFailureCode.operationNotAllowed,
        _authError(400, 'user_banned'): AuthFailureCode.userDisabled,
        _authError(429, 'over_request_rate_limit'):
            AuthFailureCode.tooManyRequests,
        _authError(400, 'captcha_failed'): AuthFailureCode.captchaFailed,
        // A token Supabase cannot accept (audience, expiry, nonce): no code.
        const _Reply(400, {
          'error': 'invalid request',
          'error_description': 'raw-server-text Bad ID token',
        }): AuthFailureCode.unknown,
        const _Reply(500, {
          'code': 500,
          'msg': 'raw-server-text Database error saving new user',
        }): AuthFailureCode.unknown,
      };
      for (final entry in cases.entries) {
        final net = _Net()..token = entry.key;
        final r = await _Repo.start(net: net);
        final failure = await _failureOf(() => r.repo.signInWithGoogle());
        await pumpEventQueue(times: 40);

        expect(failure.code, entry.value, reason: '${entry.key.body}');
        expect(failure.message, isNot(contains('raw-server-text')));
        expect(failure.originalException, isNull);
        expect(r.published, isEmpty);
        expect(r.client.auth.currentSession, isNull);
        await r.dispose();
      }
    });

    test('A8 no connection to Supabase is a network failure', () async {
      final net = _Net()..tokenUnreachable = true;
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());
      expect(failure.code, AuthFailureCode.network);
      await r.dispose();
    });

    test('A9 an answer without a session is never a sign-in', () async {
      final net = _Net()..token = _Reply(200, {'user': _googleUserJson()});
      final r = await _Repo.start(net: net);
      final failure = await _failureOf(() => r.repo.signInWithGoogle());
      await pumpEventQueue(times: 40);

      expect(failure.code, AuthFailureCode.unknown);
      expect(r.published, isEmpty);
      expect(r.net.paths.where((p) => p.endsWith('claim_current_app_session')),
          isEmpty);
      await r.dispose();
    });

    test('A10 a Google failure maps to its outcome and reaches no server',
        () async {
      final cases = <GoogleTokenFailure, AuthFailureCode>{
        GoogleTokenFailure.network: AuthFailureCode.network,
        GoogleTokenFailure.failed: AuthFailureCode.unknown,
        GoogleTokenFailure.notConfigured: AuthFailureCode.providerUnavailable,
      };
      for (final entry in cases.entries) {
        final google = _FakeTokens()..error = GoogleTokenException(entry.key);
        final r = await _Repo.start(google: google);
        final failure = await _failureOf(() => r.repo.signInWithGoogle());
        expect(failure.code, entry.value, reason: entry.key.name);
        expect(r.net.tokenRequests, isEmpty);
        await r.dispose();
      }
    });

    test('A11 the default Google source stays off without a client ID',
        () async {
      // No GOOGLE_WEB_CLIENT_ID in a test build: the real adapter is created
      // and refuses before touching the plugin.
      final repo = SupabaseAuthRepository(
        userRepository: _Profiles(),
        client: _client(_Net()),
      );
      final failure = await _failureOf(() => repo.signInWithGoogle());
      expect(failure.code, AuthFailureCode.providerUnavailable);
      await repo.dispose();
    });
  });

  group('B. google_sign_in adapter', () {
    test('B1 no client ID or no supported platform means not configured',
        () async {
      final plugin = _FakePlugin();
      final noId = PluginGoogleIdTokenSource(
          webClientId: '  ',
          platform: TargetPlatform.android,
          googleSignIn: plugin);
      final noPlatform = PluginGoogleIdTokenSource(
          webClientId: 'id',
          iosEnabled: true,
          platform: TargetPlatform.windows,
          googleSignIn: plugin);
      expect(noId.isConfigured, isFalse);
      expect(noPlatform.isConfigured, isFalse);
      expect(
          await _tokenFailureOf(noId.obtain), GoogleTokenFailure.notConfigured);
      expect(plugin.calls, isEmpty);
    });

    test('B2 Android needs the Web client ID; iOS needs its build flag', () {
      expect(PluginGoogleIdTokenSource(webClientId: 'id').isConfigured, isTrue,
          reason: 'flutter_test defaults to Android');
      expect(
          PluginGoogleIdTokenSource(webClientId: '', iosEnabled: true)
              .isConfigured,
          isFalse,
          reason: 'the iOS flag never turns Android on');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(
            PluginGoogleIdTokenSource(webClientId: 'id').isConfigured, isFalse,
            reason: 'iOS stays off by default, even with the Web client ID');
        expect(
            PluginGoogleIdTokenSource(webClientId: '', iosEnabled: true)
                .isConfigured,
            isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('B8 the plugin: Android names the Web client, iOS names none', () {
      final android = PluginGoogleIdTokenSource.createPlugin(
          TargetPlatform.android, 'web.apps.googleusercontent.com');
      expect(android.serverClientId, 'web.apps.googleusercontent.com');
      expect(android.clientId, isNull);

      // iOS takes GIDClientID and its URL scheme from Info.plist, so Dart
      // never names a client whose scheme could be missing.
      final ios = PluginGoogleIdTokenSource.createPlugin(
          TargetPlatform.iOS, 'web.apps.googleusercontent.com');
      expect(ios.clientId, isNull);
      expect(ios.serverClientId, isNull);
    });

    test('B9 an iOS sign-in uses the same flow and clears the plugin',
        () async {
      final plugin = _FakePlugin()..next = _FakeAccount();
      final ios = PluginGoogleIdTokenSource(
        webClientId: '',
        iosEnabled: true,
        platform: TargetPlatform.iOS,
        googleSignIn: plugin,
      );
      final tokens = await ios.obtain();
      expect(tokens!.idToken, 'plugin-id-token');
      expect(plugin.calls, ['signIn', 'signOut']);

      final cancelled = _FakePlugin()
        ..signInError = PlatformException(code: 'sign_in_canceled');
      final iosCancel = PluginGoogleIdTokenSource(
        iosEnabled: true,
        platform: TargetPlatform.iOS,
        googleSignIn: cancelled,
      );
      expect(await iosCancel.obtain(), isNull);
    });

    test('B3 a picked account gives its tokens; the plugin state is cleared',
        () async {
      final plugin = _FakePlugin()..next = _FakeAccount();
      final tokens = await _adapter(plugin).obtain();

      expect(tokens!.idToken, 'plugin-id-token');
      expect(tokens.accessToken, 'plugin-access-token');
      expect(plugin.calls, ['signIn', 'signOut']);
      expect(plugin.current, isNull);
    });

    test('B4 an account left signed in is cleared so the user always picks',
        () async {
      final plugin = _FakePlugin()
        ..current = _FakeAccount(idToken: 'stale')
        ..next = _FakeAccount();
      final tokens = await _adapter(plugin).obtain();

      expect(tokens!.idToken, 'plugin-id-token');
      expect(plugin.calls, ['signOut', 'signIn', 'signOut']);
    });

    test('B5 closing the picker returns null, by result or by error code',
        () async {
      final closed = _FakePlugin();
      expect(await _adapter(closed).obtain(), isNull);
      expect(closed.calls, ['signIn', 'signOut']);

      final cancelled = _FakePlugin()
        ..signInError = PlatformException(code: 'sign_in_canceled');
      expect(await _adapter(cancelled).obtain(), isNull);
    });

    test('B6 plugin errors map to network or failed', () async {
      final network = _FakePlugin()
        ..signInError = PlatformException(code: 'network_error');
      expect(await _tokenFailureOf(_adapter(network).obtain),
          GoogleTokenFailure.network);
      expect(network.calls.last, 'signOut');

      final developerError = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      );
      final misconfigured = _FakePlugin()..signInError = developerError;
      expect(await _tokenFailureOf(_adapter(misconfigured).obtain),
          GoogleTokenFailure.failed);
      expect(PluginGoogleIdTokenSource.androidStatusOf(developerError), 10);

      final other = _FakePlugin()..signInError = StateError('boom');
      expect(await _tokenFailureOf(_adapter(other).obtain),
          GoogleTokenFailure.failed);
    });

    test('B7 no ID token, or a token step that fails, is a failure', () async {
      final noToken = _FakePlugin()..next = _FakeAccount(idToken: null);
      expect(await _tokenFailureOf(_adapter(noToken).obtain),
          GoogleTokenFailure.failed);
      expect(noToken.calls.last, 'signOut');

      final tokenStep = _FakePlugin()
        ..next = _FakeAccount(
            error: PlatformException(code: 'failed_to_recover_auth'));
      expect(await _tokenFailureOf(_adapter(tokenStep).obtain),
          GoogleTokenFailure.failed);
      expect(tokenStep.calls.last, 'signOut');
    });
  });

  group('C. Screen flow', () {
    Future<(AuthViewModel, _GoogleAuth)> start() async {
      final auth = _GoogleAuth();
      final authVM =
          AuthViewModel(authRepository: auth, userRepository: _Profiles());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return (authVM, auth);
    }

    test('C1 a verified account goes Home and the operation ends', () async {
      final (authVM, auth) = await start();
      final result = await GoogleSignInFlow.run(authVM);

      expect(result.outcome, GoogleSignInOutcome.home);
      expect(auth.calls, 1);
      expect(authVM.isLoading, isFalse);
      authVM.dispose();
      await auth.close();
    });

    test('C2 an unconfirmed email goes to email verification', () async {
      final (authVM, auth) = await start();
      auth.user = _profile(verified: false);
      final result = await GoogleSignInFlow.run(authVM);

      expect(result.outcome, GoogleSignInOutcome.emailVerification);
      expect(result.email, _email);
      authVM.dispose();
      await auth.close();
    });

    test('C3 a cancel says nothing; failures name a localized message',
        () async {
      final (authVM, auth) = await start();
      final cases = <AuthFailureCode, String?>{
        AuthFailureCode.cancelled: null,
        AuthFailureCode.providerUnavailable: 'googleSignInUnavailable',
        AuthFailureCode.network: 'googleSignInNetworkError',
        AuthFailureCode.tooManyRequests: 'authTooManyRequests',
        AuthFailureCode.appSessionUnavailable: 'appSessionCheckFailed',
        AuthFailureCode.sessionExpired: 'authSessionExpired',
        AuthFailureCode.userDisabled: 'googleSignInFailed',
        AuthFailureCode.unknown: 'googleSignInFailed',
      };
      for (final entry in cases.entries) {
        auth.error = AuthFailure(code: entry.key, message: 'raw');
        final result = await GoogleSignInFlow.run(authVM);
        expect(
          result.outcome,
          entry.value == null
              ? GoogleSignInOutcome.silent
              : GoogleSignInOutcome.failed,
          reason: entry.key.name,
        );
        expect(result.errorKey, entry.value, reason: entry.key.name);
        expect(authVM.isLoading, isFalse);
      }
      authVM.dispose();
      await auth.close();
    });

    testWidgets('C4 one sign-in at a time on the Login screen', (tester) async {
      final auth = _GoogleAuth()
        ..gate = Completer<void>()
        ..error =
            const AuthFailure(code: AuthFailureCode.cancelled, message: 'x');
      final authVM = AuthViewModel(
        authRepository: auth,
        userRepository: _Profiles(),
        autoInitialize: false,
      );
      final vm = SignInViewModel(phoneAuthEnabled: false);
      late BuildContext context;
      await tester.pumpWidget(ChangeNotifierProvider<AuthViewModel>.value(
        value: authVM,
        child: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));

      final first = vm.signInWithGoogle(context);
      await tester.pump();
      expect(vm.isGoogleSignInInProgress, isTrue);

      // A second tap, not awaited: without the guard it would wait on the
      // same gate, so the count below is what proves it was refused.
      final second = vm.signInWithGoogle(context);
      await vm.signIn(context); // the email button
      await tester.pump();
      expect(auth.calls, 1);
      expect(vm.emailError, isNull,
          reason: 'the email sign-in did not start while Google runs');

      auth.gate!.complete();
      await first;
      await second;
      await tester.pump();
      expect(vm.isGoogleSignInInProgress, isFalse);
      expect(vm.isLoading, isFalse);

      vm.dispose();
      authVM.dispose();
      await auth.close();
    });
  });

  group('D. Guards', () {
    test('D1 every Google message exists in English and Arabic', () {
      final en = _arb('en');
      final ar = _arb('ar');
      final keys = <String>{
        for (final code in AuthFailureCode.values)
          GoogleSignInFlow.errorKeyFor(code),
        'googleSignInFailed',
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
        expect(ar[key], isNot(en[key]), reason: 'ar: $key must be translated');
      }
    });

    test('D2 the buttons no longer say "coming soon"', () {
      for (final path in [
        'lib/src/viewmodels/Signup-Login/login_viewmodel.dart',
        'lib/src/viewmodels/Signup-Login/signup_viewmodel.dart',
      ]) {
        final source = _read(path);
        expect(source, isNot(contains('coming soon')), reason: path);
        expect(source, contains('GoogleSignInFlow.run('), reason: path);
      }
    });

    test('D3 no token, account or raw plugin text is ever logged', () {
      final source = _read('lib/src/services/google_id_token_source.dart');
      final logs = RegExp(r'(debugPrint|print)\(([^;]*);', dotAll: true)
          .allMatches(source)
          .map((m) => m.group(2)!)
          .toList();
      expect(logs, isNotEmpty);
      for (final log in logs) {
        for (final secret in [
          'idToken',
          'accessToken',
          'authentication',
          'account',
          'email',
          'error.message',
        ]) {
          expect(log, isNot(contains(secret)), reason: log);
        }
      }
      final repository =
          _read('lib/src/repositories/supabase_auth_repository.dart');
      expect(repository, isNot(contains(r'$tokens')));
      expect(repository, isNot(contains('tokens.idToken}')));
    });

    test('D4 google_sign_in stays on 6.x until the AGP upgrade', () {
      // 7.x (Credential Manager) needs the Android Gradle plugin 8.12.1; the
      // app is on 8.11.1, the same blocker that pins connectivity_plus.
      final pubspec = _read('pubspec.yaml');
      expect(RegExp(r'\n  google_sign_in: \^6\.').hasMatch(pubspec), isTrue);
      expect(_read('android/settings.gradle'),
          contains('"com.android.application" version "8.11.1"'));
    });

    test('D5 iOS client ID and URL scheme come from one xcconfig value', () {
      final plist = _read('ios/Runner/Info.plist').replaceAll('\r\n', '\n');
      expect(
          plist,
          contains('<key>GIDClientID</key>\n    <string>'
              r'$(GOOGLE_IOS_CLIENT_ID_PREFIX).apps.googleusercontent.com'
              '</string>'));
      final schemes =
          RegExp(r'<string>(com\.googleusercontent\.apps\.[^<]*)</string>')
              .allMatches(plist)
              .map((m) => m.group(1))
              .toList();
      expect(schemes,
          [r'com.googleusercontent.apps.$(GOOGLE_IOS_CLIENT_ID_PREFIX)'],
          reason:
              'one Google scheme, never a hard-coded client of any project');
      expect(plist, isNot(contains('GIDServerClientID')));

      final xcconfig = _read('ios/Flutter/GoogleSignIn.xcconfig');
      expect(
          RegExp(r'^GOOGLE_IOS_CLIENT_ID_PREFIX =', multiLine: true)
              .hasMatch(xcconfig),
          isTrue);
      for (final config in ['Debug', 'Release']) {
        expect(_read('ios/Flutter/$config.xcconfig'),
            contains('#include "GoogleSignIn.xcconfig"'),
            reason: '$config (Profile uses Release)');
      }
    });
  });
}
