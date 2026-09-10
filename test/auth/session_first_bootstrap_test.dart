import 'dart:async';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';

UserSubscription _subscription() => UserSubscription(
      plan: 'test',
      isActive: false,
      features: const [],
    );

/// The identity a Supabase session yields on its own: uid, email and the
/// confirmed-at derived verification flags. No profile columns.
UserModel _sessionIdentity({
  String uid = _uid,
  bool emailVerified = true,
  bool phoneVerified = false,
}) =>
    UserModel(
      uid: uid,
      name: '',
      email: 'session@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: emailVerified,
      isPhoneVerified: phoneVerified,
      subscription: _subscription(),
      preferences: const {},
    );

/// A hydrated `public.profiles` row. Carries the canonical
/// `profile_media_id` and — after the Batch 1 change — never a signed URL.
UserModel _profileRow({
  String uid = _uid,
  String name = 'Profile Name',
  String? profileMediaId = 'media-1',
}) =>
    UserModel(
      uid: uid,
      name: name,
      email: 'profile@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      isPhoneVerified: false,
      profileImageUrl: null,
      profileMediaId: profileMediaId,
      subscription: _subscription(),
      preferences: const {},
    );

class _IdentityAuthRepository implements AuthRepository {
  _IdentityAuthRepository({UserModel? initialUser}) : _currentUser = initialUser;

  final StreamController<UserModel?> _controller =
      StreamController<UserModel?>.broadcast();
  UserModel? _currentUser;

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  void emit(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records how many authoritative profile reads and signed-URL resolutions
/// actually happen, and lets a test hold either of them open indefinitely.
class _RecordingUserRepository
    implements UserRepository, ProfileImageUrlResolver {
  _RecordingUserRepository({
    this.profile,
    this.neverCompletes = false,
    this.throwOnRead = false,
    this.signedUrl,
    this.throwOnResolve = false,
  });

  UserModel? profile;
  bool neverCompletes;
  bool throwOnRead;
  String? signedUrl;
  bool throwOnResolve;

  int getUserByIdCalls = 0;
  int resolveProfileImageUrlCalls = 0;

  @override
  Future<UserModel?> getUserById(String uid) {
    getUserByIdCalls++;
    if (neverCompletes) return Completer<UserModel?>().future;
    if (throwOnRead) return Future<UserModel?>.error(StateError('read failed'));
    return Future<UserModel?>.value(profile);
  }

  @override
  Future<String?> resolveProfileImageUrl(String profileMediaId) {
    resolveProfileImageUrlCalls++;
    if (throwOnResolve) {
      return Future<String?>.error(StateError('R2 unavailable'));
    }
    return Future<String?>.value(signedUrl);
  }

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<void> updateUser(UserModel user) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await sb.Supabase.initialize(
      url: 'https://unit-test.invalid',
      publishableKey: 'unit-test-publishable-key',
    );
  });

  group('Session-first auth bootstrap', () {
    test(
        'verified cached session resolves AuthStatus.authenticated before the '
        'profile read completes', () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(neverCompletes: true);
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(Duration.zero);

      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.profileHydration, ProfileHydrationStatus.resolving);
      expect(userRepository.getUserByIdCalls, 1);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test('no session resolves AuthStatus.unauthenticated', () async {
      final authRepository = _IdentityAuthRepository();
      final userRepository = _RecordingUserRepository();
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(Duration.zero);

      expect(viewModel.status, AuthStatus.unauthenticated);
      expect(viewModel.currentUser, isNull);
      expect(userRepository.getUserByIdCalls, 0);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test(
        'a session that exists but is not verified stays unauthenticated',
        () async {
      final authRepository = _IdentityAuthRepository(
        initialUser: _sessionIdentity(emailVerified: false),
      );
      final userRepository = _RecordingUserRepository();
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(Duration.zero);

      expect(viewModel.status, AuthStatus.unauthenticated);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test(
        'a profile read that never completes never demotes the session',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(neverCompletes: true);
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      final observed = <AuthStatus>[];
      viewModel.addListener(() => observed.add(viewModel.status));

      // Comfortably longer than the deleted three-second safety timer.
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(viewModel.status, AuthStatus.authenticated);
      expect(observed, isNot(contains(AuthStatus.unauthenticated)));
      expect(viewModel.profileHydration, ProfileHydrationStatus.resolving);

      viewModel.dispose();
      await authRepository.dispose();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a failing profile read reports hydration failure, not sign-out',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(throwOnRead: true);
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.profileHydration, ProfileHydrationStatus.failed);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test(
        'bootstrap never passes through unauthenticated on its way to '
        'authenticated', () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(profile: _profileRow());
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      final transitions = <AuthStatus>[AuthStatus.unknown];
      viewModel.addListener(() {
        if (transitions.last != viewModel.status) {
          transitions.add(viewModel.status);
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(transitions, <AuthStatus>[
        AuthStatus.unknown,
        AuthStatus.authenticated,
      ]);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test('status is final before listeners are notified', () async {
      final authRepository = _IdentityAuthRepository();
      final userRepository = _RecordingUserRepository();
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      final statusesSeenByListener = <AuthStatus>[];
      viewModel.addListener(() => statusesSeenByListener.add(viewModel.status));

      await Future<void>.delayed(Duration.zero);

      // The old bootstrap flag was assigned after notifyListeners(), so a
      // synchronous reader still observed `unknown` and nothing notified again.
      expect(statusesSeenByListener, isNotEmpty);
      expect(statusesSeenByListener, isNot(contains(AuthStatus.unknown)));

      viewModel.dispose();
      await authRepository.dispose();
    });
  });

  group('Profile hydration and signed image resolution', () {
    test('hydration applies the profile row and resolves the signed URL',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(
        profile: _profileRow(),
        signedUrl: 'https://media-api.example.test/signed',
      );
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.profileHydration, ProfileHydrationStatus.resolved);
      expect(viewModel.currentUser?.name, 'Profile Name');
      expect(viewModel.currentUser?.profileMediaId, 'media-1');
      expect(
        viewModel.currentUser?.profileImageUrl,
        'https://media-api.example.test/signed',
      );

      viewModel.dispose();
      await authRepository.dispose();
    });

    test('a failing signed-URL resolution leaves authentication untouched',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(
        profile: _profileRow(),
        throwOnResolve: true,
      );
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.profileHydration, ProfileHydrationStatus.resolved);
      expect(viewModel.currentUser?.name, 'Profile Name');
      expect(viewModel.currentUser?.profileImageUrl, isNull);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test(
        'a session-identity refresh does not blank the hydrated name or image',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(
        profile: _profileRow(),
        signedUrl: 'https://media-api.example.test/signed',
      );
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(viewModel.currentUser?.name, 'Profile Name');

      // Supabase emits tokenRefreshed with session identity only.
      authRepository.emit(_sessionIdentity());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.currentUser?.name, 'Profile Name');
      expect(
        viewModel.currentUser?.profileImageUrl,
        'https://media-api.example.test/signed',
      );
      expect(viewModel.status, AuthStatus.authenticated);
      // No re-hydration for an unchanged, already resolved session.
      expect(userRepository.getUserByIdCalls, 1);

      viewModel.dispose();
      await authRepository.dispose();
    });

    test('a different user re-hydrates and does not inherit prior state',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(
        profile: _profileRow(),
        signedUrl: 'https://media-api.example.test/signed',
      );
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(viewModel.currentUser?.profileImageUrl, isNotNull);

      userRepository.profile =
          _profileRow(uid: _otherUid, name: 'Second User', profileMediaId: null);
      authRepository.emit(_sessionIdentity(uid: _otherUid));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(viewModel.currentUser?.uid, _otherUid);
      expect(viewModel.currentUser?.name, 'Second User');
      expect(viewModel.currentUser?.profileImageUrl, isNull);
      expect(userRepository.getUserByIdCalls, 2);

      viewModel.dispose();
      await authRepository.dispose();
    });
  });

  group('Auth stream fan-out', () {
    test('one hydration runs regardless of how many components observe auth',
        () async {
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _RecordingUserRepository(profile: _profileRow());

      // AuthViewModel is the single canonical owner of profile hydration.
      final viewModel = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      // Other components observe identity only, exactly as
      // NotificationService, HomeViewModel and FavoriteService do.
      final observers = <StreamSubscription<UserModel?>>[
        authRepository.authStateChanges.listen((_) {}),
        authRepository.authStateChanges.listen((_) {}),
        authRepository.authStateChanges.listen((_) {}),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(userRepository.getUserByIdCalls, 1);
      expect(userRepository.resolveProfileImageUrlCalls, 1);

      for (final subscription in observers) {
        await subscription.cancel();
      }
      viewModel.dispose();
      await authRepository.dispose();
    });

    test(
        'SupabaseAuthRepository emits session identity with no profile read, '
        'and replays the latest value to a late subscriber', () async {
      final userRepository = _RecordingUserRepository();
      final repository =
          SupabaseAuthRepository(userRepository: userRepository);

      final first = await repository.authStateChanges.first;
      expect(first, isNull, reason: 'no session is restored in this test');

      // A subscriber attaching after the pipeline started still receives the
      // current state; a plain broadcast stream would replay nothing.
      final late = await repository.authStateChanges.first
          .timeout(const Duration(seconds: 2));
      expect(late, isNull);

      // The auth stream performs no authoritative profile read at all.
      expect(userRepository.getUserByIdCalls, 0);
      expect(userRepository.resolveProfileImageUrlCalls, 0);

      await repository.dispose();
    });
  });
}
