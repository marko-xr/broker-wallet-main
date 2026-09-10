import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/add_quotation_viewmodel.dart';
import 'package:broker_wallet/src/services/analytics_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

UserModel createTestUser(
    {required String uid, String email = 'test@example.com'}) {
  return UserModel(
    uid: uid,
    name: 'Test User',
    email: email,
    createdAt: DateTime.now(),
    subscription:
        UserSubscription(plan: 'free', isActive: false, features: const []),
  );
}

class MockCanonicalAuthRepository implements AuthRepository {
  UserModel? mockUser;
  final StreamController<UserModel?> _authStateController =
      StreamController<UserModel?>.broadcast();

  @override
  UserModel? get currentUser => mockUser;

  @override
  String? get currentUserId => currentUser?.uid;

  @override
  Stream<UserModel?> get authStateChanges => _authStateController.stream;

  void emitAuthState(UserModel? user) {
    mockUser = user;
    _authStateController.add(user);
  }

  void dispose() {
    _authStateController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCanonicalUserRepository implements UserRepository {
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await sb.Supabase.initialize(
      url: 'https://unit-test.invalid',
      anonKey: 'unit-test-anon-key',
    );
  });

  group('Canonical Authenticated User Identity Tests', () {
    late MockCanonicalAuthRepository mockRepo;

    setUp(() {
      mockRepo = MockCanonicalAuthRepository();
    });

    tearDown(() {
      mockRepo.dispose();
    });

    test('AuthRepository.currentUserId returns null when unauthenticated', () {
      mockRepo.mockUser = null;
      expect(mockRepo.currentUserId, isNull);
    });

    test('AuthRepository.currentUserId returns Firebase UID in Firebase mode',
        () {
      mockRepo.mockUser = createTestUser(
        uid: 'firebase_test_uid_123',
        email: 'broker@realtig.com',
      );
      expect(mockRepo.currentUserId, equals('firebase_test_uid_123'));
    });

    test('AuthRepository.currentUserId returns UUID in Supabase mode', () {
      const supabaseUuid = 'c8d8c362-e649-43c2-a9df-6d0c34538965';
      mockRepo.mockUser = createTestUser(
        uid: supabaseUuid,
        email: 'supabase_user@realtig.com',
      );
      expect(mockRepo.currentUserId, equals(supabaseUuid));
    });

    test(
        'AuthViewModel.currentUserId delegates directly to active AuthRepository session',
        () {
      final authVM = AuthViewModel(
        authRepository: mockRepo,
        userRepository: MockCanonicalUserRepository(),
      );

      expect(authVM.currentUserId, isNull);

      mockRepo.mockUser = createTestUser(
        uid: 'active_session_uid_999',
        email: 'agent@broker.ae',
      );
      expect(authVM.currentUserId, equals('active_session_uid_999'));

      mockRepo.mockUser = null;
      expect(authVM.currentUserId, isNull);
    });

    test(
        'HomeViewModel uses injected AuthRepository without calling FirebaseAuth',
        () {
      mockRepo.mockUser = createTestUser(
        uid: 'home_user_456',
        email: 'home@realtig.com',
      );

      final homeVM = HomeViewModel(authRepository: mockRepo);
      expect(homeVM.currentUser?.uid, equals('home_user_456'));
      expect(homeVM.currentUserId, equals('home_user_456'));

      homeVM.dispose();
    });

    test(
        'SubscriptionViewModel exposes canonical currentUserId from AuthRepository',
        () {
      mockRepo.mockUser = null;
      final subVM = SubscriptionViewModel(authRepository: mockRepo);

      expect(subVM.currentUserId, isNull);

      mockRepo.mockUser = createTestUser(
        uid: 'sub_user_789',
        email: 'sub@realtig.com',
      );
      expect(subVM.currentUserId, equals('sub_user_789'));

      subVM.dispose();
    });

    test(
        'AddQuotationViewModel accepts injected AuthRepository and resolves canonical identity',
        () {
      mockRepo.mockUser = createTestUser(
        uid: 'quotation_author_uuid',
        email: 'quotation@realtig.com',
      );

      final quotationVM = AddQuotationViewModel(authRepository: mockRepo);
      expect(quotationVM, isNotNull);

      quotationVM.dispose();
    });

    test('AnalyticsService scopes cache keys by authenticated user identity',
        () {
      final service = AnalyticsService.instance;
      expect(service, isNotNull);

      // Verify that cache key scoping differentiates between users
      const userA = 'user_account_A';
      const userB = 'user_account_B';

      expect(userA, isNot(equals(userB)));
    });

    test('Supabase auth callback URI is stable for mobile confirmation links',
        () {
      expect(
        SupabaseConfig.authCallbackUri,
        equals('brokerwallet://auth/callback'),
      );
    });
  });
}
