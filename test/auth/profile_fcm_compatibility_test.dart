import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/firestore_notification_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/notification_service.dart';
import 'package:broker_wallet/src/viewmodels/edit_profile_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = '550e8400-e29b-41d4-a716-446655440000';

UserModel _userWithName(String name) => UserModel(
      uid: _uuid,
      name: name,
      email: 'marko@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      subscription: UserSubscription(
        plan: 'test',
        isActive: true,
        features: const [],
      ),
    );

class _InMemoryUserRepository implements UserRepository {
  _InMemoryUserRepository(this._storedUser);

  UserModel _storedUser;

  @override
  Future<UserModel?> getUserById(String uid) async =>
      _storedUser.uid == uid ? _storedUser : null;

  @override
  Future<void> updateUser(UserModel user) async {
    _storedUser = user;
  }

  @override
  Stream<UserModel?> getUserStream(String uid) => Stream.value(_storedUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SupabaseStyleAuthRepositorySpy implements AuthRepository {
  _SupabaseStyleAuthRepositorySpy(this.profileRepository, this._currentUser);

  final _InMemoryUserRepository profileRepository;
  UserModel? _currentUser;
  int updateProfileCalls = 0;
  bool throwOnUpdate = false;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  @override
  Stream<UserModel?> get authStateChanges => Stream.value(_currentUser);

  @override
  Future<UserModel?> reloadUser() async {
    if (_currentUser == null) return null;
    return profileRepository.getUserById(_currentUser!.uid);
  }

  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    updateProfileCalls += 1;
    if (throwOnUpdate) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Profile update failed',
      );
    }

    final current = _currentUser;
    if (current == null) {
      throw const AuthFailure(
        code: AuthFailureCode.operationNotAllowed,
        message: 'No authenticated user',
      );
    }

    final updated = current.copyWith(
      name: name,
      phoneNumber: phoneNumber,
      profileImageUrl: profileImageUrl,
    );
    await profileRepository.updateUser(updated);
    _currentUser = await profileRepository.getUserById(current.uid);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthRepositoryForNotification implements AuthRepository {
  _AuthRepositoryForNotification(this._uid);

  final String? _uid;

  @override
  String? get currentUserId => _uid;

  @override
  UserModel? get currentUser =>
      _uid == null ? null : _userWithName('Auth User');

  @override
  Stream<UserModel?> get authStateChanges => Stream.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FirestoreNotificationRepositorySpy
    extends FirestoreNotificationRepository {
  int deleteCalls = 0;
  String? lastUserId;
  String? lastToken;

  @override
  Future<void> deleteFcmToken(String userId, String token) async {
    deleteCalls += 1;
    lastUserId = userId;
    lastToken = token;
  }
}

class _MemoryNotificationRepository implements NotificationRepository {
  int deleteCalls = 0;
  String? lastUserId;
  String? lastToken;

  @override
  Future<void> deleteFcmToken(String userId, String token) async {
    deleteCalls += 1;
    lastUserId = userId;
    lastToken = token;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Profile persistence in Supabase mode', () {
    test('Supabase-mode profile-name update invokes profile repository path',
        () async {
      final profileRepo = _InMemoryUserRepository(_userWithName('Mohammed'));
      final authRepo = _SupabaseStyleAuthRepositorySpy(
        profileRepo,
        _userWithName('Mohammed'),
      );

      final vm = EditProfileViewModel(
        themeVM: ThemeViewModel(),
        localeVM: LocaleViewModel(),
        name: 'Mohammed',
        email: 'marko@example.test',
        phone: '',
        userRepository: profileRepo,
        authRepository: authRepo,
      );

      vm.name = 'Marko';
      await vm.saveChanges();

      expect(authRepo.updateProfileCalls, 1);
      expect((await profileRepo.getUserById(_uuid))?.name, 'Marko');
    });

    test('successful profile name update survives repository refresh',
        () async {
      final profileRepo = _InMemoryUserRepository(_userWithName('Mohammed'));
      final authRepo = _SupabaseStyleAuthRepositorySpy(
        profileRepo,
        _userWithName('Mohammed'),
      );

      final vm = EditProfileViewModel(
        themeVM: ThemeViewModel(),
        localeVM: LocaleViewModel(),
        name: 'Mohammed',
        email: 'marko@example.test',
        phone: '',
        userRepository: profileRepo,
        authRepository: authRepo,
      );

      vm.name = 'Marko';
      await vm.saveChanges();

      final refreshed = await authRepo.reloadUser();
      expect(refreshed, isNotNull);
      expect(refreshed!.name, 'Marko');
    });

    test('failed profile DB update does not falsely report success', () async {
      final profileRepo = _InMemoryUserRepository(_userWithName('Mohammed'));
      final authRepo = _SupabaseStyleAuthRepositorySpy(
        profileRepo,
        _userWithName('Mohammed'),
      )..throwOnUpdate = true;

      final vm = EditProfileViewModel(
        themeVM: ThemeViewModel(),
        localeVM: LocaleViewModel(),
        name: 'Mohammed',
        email: 'marko@example.test',
        phone: '',
        userRepository: profileRepo,
        authRepository: authRepo,
      );

      vm.name = 'Marko';

      await expectLater(
        vm.saveChanges(),
        throwsA(isA<AuthFailure>()),
      );

      expect((await profileRepo.getUserById(_uuid))?.name, 'Mohammed');
    });
  });

  group('FCM logout compatibility by auth mode', () {
    test('Firebase mode still attempts Firestore token cleanup', () async {
      final repo = _FirestoreNotificationRepositorySpy();
      final service = NotificationService.forTesting(
        authRepository: _AuthRepositoryForNotification(_uuid),
        notificationRepository: repo,
        tokenProvider: () async => 'fcm-token',
        isSupabaseAuthModeOverride: false,
      );

      await service.clearToken();

      expect(repo.deleteCalls, 1);
      expect(repo.lastUserId, _uuid);
      expect(repo.lastToken, 'fcm-token');
    });

    test(
        'Supabase mode does not attempt Firebase-auth-protected Firestore token deletion',
        () async {
      final repo = _FirestoreNotificationRepositorySpy();
      final service = NotificationService.forTesting(
        authRepository: _AuthRepositoryForNotification(_uuid),
        notificationRepository: repo,
        tokenProvider: () async => 'fcm-token',
        isSupabaseAuthModeOverride: true,
      );

      await service.clearToken();

      expect(repo.deleteCalls, 0);
    });

    test(
        'Supabase logout token-clear path completes when legacy remote is unavailable',
        () async {
      final repo = _FirestoreNotificationRepositorySpy();
      final service = NotificationService.forTesting(
        authRepository: _AuthRepositoryForNotification(_uuid),
        notificationRepository: repo,
        tokenProvider: () async => null,
        isSupabaseAuthModeOverride: true,
      );

      await service.clearToken();

      expect(repo.deleteCalls, 0);
    });

    test('Non-Firestore repository still performs deletion in Supabase mode',
        () async {
      final repo = _MemoryNotificationRepository();
      final service = NotificationService.forTesting(
        authRepository: _AuthRepositoryForNotification(_uuid),
        notificationRepository: repo,
        tokenProvider: () async => 'fcm-token',
        isSupabaseAuthModeOverride: true,
      );

      await service.clearToken();

      expect(repo.deleteCalls, 1);
      expect(repo.lastUserId, _uuid);
      expect(repo.lastToken, 'fcm-token');
    });
  });
}
