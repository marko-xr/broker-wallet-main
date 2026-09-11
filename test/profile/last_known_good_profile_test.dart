import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _snapshotKey = 'cached_profile_snapshot_v1';

const _signupName = 'Signup Era Name';
const _profileName = 'Current Profile Name';
const _snapshotName = 'Last Known Good Name';

UserSubscription _subscription() => UserSubscription(
      plan: 'test',
      isActive: false,
      features: const [],
    );

/// Session identity: uid, email, confirmed-at flags and the *signup* metadata
/// name, which `updateUserProfile` never rewrites.
UserModel _sessionIdentity({String uid = _uid}) => UserModel(
      uid: uid,
      name: _signupName,
      email: 'session@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      subscription: _subscription(),
      preferences: const {},
    );

UserModel _profileRow({
  String uid = _uid,
  String name = _profileName,
  String? profileMediaId = 'media-current',
}) =>
    UserModel(
      uid: uid,
      name: name,
      email: 'profile@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      profileImageUrl: null,
      profileMediaId: profileMediaId,
      subscription: _subscription(),
      preferences: const {},
    );

UserModel _snapshotUser({
  String uid = _uid,
  String name = _snapshotName,
  String? profileMediaId = 'media-snapshot',
  String? signedUrl,
}) =>
    UserModel(
      uid: uid,
      name: name,
      email: 'snapshot@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      profileImageUrl: signedUrl,
      profileMediaId: profileMediaId,
      subscription: _subscription(),
      preferences: const {},
    );

/// Seeds the store exactly as `cacheProfileSnapshot` writes it.
void seedSnapshot(UserModel user, {bool keepSignedUrl = false}) {
  final map = Map<String, dynamic>.from(user.toMap());
  if (!keepSignedUrl) map.remove('profileImageUrl');
  SharedPreferences.setMockInitialValues({_snapshotKey: json.encode(map)});
}

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

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubUserRepository implements UserRepository, ProfileImageUrlResolver {
  _StubUserRepository({
    this.profile,
    this.neverCompletes = false,
    this.throwOnRead = false,
  });

  UserModel? profile;
  bool neverCompletes;
  bool throwOnRead;

  /// Signed-URL resolution is exercised by the session-first suite; here it
  /// stays unresolved so the tests observe the cached identity alone.
  String? signedUrl;

  @override
  Future<UserModel?> getUserById(String uid) {
    if (neverCompletes) return Completer<UserModel?>().future;
    if (throwOnRead) return Future<UserModel?>.error(StateError('offline'));
    return Future<UserModel?>.value(profile);
  }

  @override
  Future<String?> resolveProfileImageUrl(String profileMediaId) async =>
      signedUrl;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<void> updateUser(UserModel user) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cold-start last-known-good profile', () {
    test('same-uid snapshot is applied before hydration resolves', () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.status, AuthStatus.authenticated);
      expect(vm.profileHydration, ProfileHydrationStatus.resolving);
      expect(vm.displayName, _snapshotName);
      expect(vm.currentUser?.name, _snapshotName);

      vm.dispose();
      await authRepository.dispose();
    });

    test('profileMediaId survives the restore', () async {
      seedSnapshot(_snapshotUser(profileMediaId: 'media-snapshot'));
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.currentUser?.profileMediaId, 'media-snapshot');
      expect(vm.profileImage.mediaId, 'media-snapshot');
      expect(vm.profileImage.hasStableIdentity, isTrue);

      vm.dispose();
      await authRepository.dispose();
    });

    test('a snapshot belonging to another uid is rejected', () async {
      seedSnapshot(_snapshotUser(uid: _otherUid));
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.displayName, isNot(_snapshotName));
      expect(vm.currentUser?.name, isNot(_snapshotName));
      expect(vm.currentUser?.profileMediaId, isNull);
      expect(vm.status, AuthStatus.authenticated);

      vm.dispose();
      await authRepository.dispose();
    });

    test('a snapshot never overwrites an already hydrated profile', () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(profile: _profileRow());
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.profileHydration, ProfileHydrationStatus.resolved);
      expect(vm.currentUser?.name, _profileName);
      expect(vm.currentUser?.profileMediaId, 'media-current');
      expect(vm.displayName, _profileName);

      vm.dispose();
      await authRepository.dispose();
    });

    test('hydration failure preserves the cached presentation', () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(throwOnRead: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.status, AuthStatus.authenticated);
      expect(vm.profileHydration, ProfileHydrationStatus.failed);
      expect(vm.displayName, _snapshotName);
      expect(vm.currentUser?.profileMediaId, 'media-snapshot');

      vm.dispose();
      await authRepository.dispose();
    });

    test('the signup metadata name never wins over cached profile data',
        () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      final observed = <String>[];
      vm.addListener(() => observed.add(vm.displayName));

      await settle();

      expect(observed, isNot(contains(_signupName)));
      expect(vm.displayName, _snapshotName);

      vm.dispose();
      await authRepository.dispose();
    });

    test('signup metadata is still the fallback when nothing is cached',
        () async {
      SharedPreferences.setMockInitialValues({});
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.displayName, _signupName);

      vm.dispose();
      await authRepository.dispose();
    });

    test('a stored signed URL is never restored as presentation state',
        () async {
      // Defensive: an older payload that still carries a signed URL.
      seedSnapshot(
        _snapshotUser(signedUrl: 'https://media-api.example.test/expired'),
        keepSignedUrl: true,
      );
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(neverCompletes: true);
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();

      expect(vm.currentUser?.profileImageUrl, isNull);
      expect(vm.profileImage.signedUrl, isNull);
      expect(vm.profileImage.mediaId, 'media-snapshot');

      vm.dispose();
      await authRepository.dispose();
    });
  });

  group('Account isolation', () {
    test('switching account exposes no previous user name or media id',
        () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(profile: _profileRow());
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();
      expect(vm.currentUser?.name, _profileName);

      userRepository.profile = null;
      userRepository.neverCompletes = true;
      authRepository.emit(_sessionIdentity(uid: _otherUid));
      await settle();

      expect(vm.currentUser?.uid, _otherUid);
      expect(vm.currentUser?.name, isNot(_profileName));
      expect(vm.currentUser?.name, isNot(_snapshotName));
      expect(vm.currentUser?.profileMediaId, isNull);
      expect(vm.profileImage.mediaId, isNull);

      vm.dispose();
      await authRepository.dispose();
    });

    test('sign-out clears the cached name and image identity', () async {
      seedSnapshot(_snapshotUser());
      final authRepository =
          _IdentityAuthRepository(initialUser: _sessionIdentity());
      final userRepository = _StubUserRepository(profile: _profileRow());
      final vm = AuthViewModel(
        authRepository: authRepository,
        userRepository: userRepository,
      );

      await settle();
      expect(vm.currentUser, isNotNull);

      await vm.signOut();
      await settle();

      expect(vm.status, AuthStatus.unauthenticated);
      expect(vm.currentUser, isNull);
      expect(vm.displayName, isEmpty);
      expect(vm.profileImage, ProfileImageSource.empty);

      vm.dispose();
      await authRepository.dispose();
    });
  });

  group('Stable profile image cache identity', () {
    testWidgets('a rotating signed URL resolves to the same cache key',
        (tester) async {
      const mediaId = 'media-stable';

      Future<String?> cacheKeyFor(String signedUrl) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OfflineMediaService.instance.buildOfflineAwareImage(
              imageUrl: signedUrl,
              cacheKey: mediaId,
              width: 48,
              height: 48,
            ),
          ),
        );
        final image =
            tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
        return image.cacheKey;
      }

      final first = await cacheKeyFor(
        'https://media-api.example.test/img?X-Amz-Signature=aaa&X-Amz-Date=1',
      );
      final second = await cacheKeyFor(
        'https://media-api.example.test/img?X-Amz-Signature=zzz&X-Amz-Date=2',
      );

      expect(first, mediaId);
      expect(second, mediaId);
      expect(first, second);
    });

    testWidgets('omitting the cache key preserves URL-keyed behavior',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMediaService.instance.buildOfflineAwareImage(
            imageUrl: 'https://cdn.example.test/property.jpg',
            width: 48,
            height: 48,
          ),
        ),
      );

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.cacheKey, isNull);
      expect(image.imageUrl, 'https://cdn.example.test/property.jpg');
    });

    testWidgets('a stable identity with no URL yet renders the placeholder',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMediaService.instance.buildOfflineAwareImage(
            imageUrl: '',
            cacheKey: 'media-no-url',
            width: 48,
            height: 48,
            placeholder: const SizedBox(key: ValueKey('placeholder')),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}
