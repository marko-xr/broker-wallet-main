import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class StubAuthRepository implements AuthRepository {
  final StreamController<UserModel?> authStateController =
      StreamController<UserModel?>.broadcast();
  UserModel? currentRepoUser;
  AuthFailure? failureToThrow;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Stream<UserModel?> get authStateChanges => authStateController.stream;

  @override
  UserModel? get currentUser => currentRepoUser;

  @override
  Future<UserModel?> reloadUser() async => currentRepoUser;

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (failureToThrow != null) throw failureToThrow!;
    return currentRepoUser!;
  }

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    if (failureToThrow != null) throw failureToThrow!;
    return currentRepoUser!;
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    if (failureToThrow != null) throw failureToThrow!;
  }

  @override
  Future<void> signOut() async {
    authStateController.add(null);
  }
}

class StubUserRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<UserModel?> getUserById(String uid) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Boundary Invariant 1: AuthFailure Propagation', () {
    late StubAuthRepository stubAuthRepo;
    late StubUserRepository stubUserRepo;
    late AuthViewModel authViewModel;

    setUp(() {
      stubAuthRepo = StubAuthRepository();
      stubUserRepo = StubUserRepository();
      authViewModel = AuthViewModel(
        authRepository: stubAuthRepo,
        userRepository: stubUserRepo,
        autoInitialize: false,
      );
    });

    test('AuthFailure.emailNotConfirmed is NOT converted to unknown in signIn',
        () async {
      stubAuthRepo.failureToThrow = const AuthFailure(
        code: AuthFailureCode.emailNotConfirmed,
        message: 'Please verify your email address.',
      );

      expect(
        () => authViewModel.signInWithEmail('test@broker.com', 'pass123'),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.emailNotConfirmed,
        )),
      );
    });

    test('AuthFailure.emailAlreadyInUse is NOT converted to unknown in signUp',
        () async {
      stubAuthRepo.failureToThrow = const AuthFailure(
        code: AuthFailureCode.emailAlreadyInUse,
        message: 'Email already registered.',
      );

      expect(
        () => authViewModel.signUpWithEmail(
          'exists@broker.com',
          'password',
          'Agent',
        ),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.emailAlreadyInUse,
        )),
      );
    });

    test('AuthFailure is preserved in sendEmailVerification', () async {
      stubAuthRepo.failureToThrow = const AuthFailure(
        code: AuthFailureCode.tooManyRequests,
        message: 'Rate limited.',
      );

      expect(
        () => authViewModel.sendEmailVerification(),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.tooManyRequests,
        )),
      );
    });
  });

  group('Auth Boundary Invariant 2 & 3: Cache Authority & State Invalidation', () {
    late StubAuthRepository stubAuthRepo;
    late StubUserRepository stubUserRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      stubAuthRepo = StubAuthRepository();
      stubUserRepo = StubUserRepository();
    });

    test('Sign out clears OfflineAuthService cache', () async {
      final offlineService = OfflineAuthService.instance;
      final testUser = UserModel(
        uid: 'user-abc',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime.now(),
        isEmailVerified: true,
        subscription: UserSubscription(
          plan: 'free',
          isActive: true,
          features: [],
        ),
      );

      await offlineService.cacheUserModel(testUser);
      expect(await offlineService.isUserAuthenticated(), isTrue);

      final authVM = AuthViewModel(
        authRepository: stubAuthRepo,
        userRepository: stubUserRepo,
        autoInitialize: false,
      );

      await authVM.signOut();

      expect(await offlineService.isUserAuthenticated(), isFalse);
      expect(await offlineService.getCachedUserModel(), isNull);
      expect(authVM.currentUser, isNull);
      expect(authVM.isAuthenticated, isFalse);
    });

    test('Null auth state change invalidates cache and sets isAuthenticated to false',
        () async {
      final offlineService = OfflineAuthService.instance;
      final verifiedUser = UserModel(
        uid: 'verified-1',
        name: 'Agent',
        email: 'agent@broker.com',
        createdAt: DateTime.now(),
        isEmailVerified: true,
        subscription: UserSubscription(
          plan: 'free',
          isActive: true,
          features: [],
        ),
      );

      await offlineService.cacheUserModel(verifiedUser);
      expect(await offlineService.isUserAuthenticated(), isTrue);

      final authVM = AuthViewModel(
        authRepository: stubAuthRepo,
        userRepository: stubUserRepo,
        autoInitialize: true,
      );

      // Emit null auth event
      stubAuthRepo.authStateController.add(null);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(authVM.currentUser, isNull);
      expect(authVM.isAuthenticated, isFalse);
      expect(await offlineService.isUserAuthenticated(), isFalse);
      expect(await offlineService.getCachedUserModel(), isNull);
    });

    test('Stale cache cannot cause isAuthenticated to be true when currentUser is null',
        () async {
      final offlineService = OfflineAuthService.instance;
      // Stale cache left in SharedPreferences
      await offlineService.cacheUserModel(UserModel(
        uid: 'stale-user',
        name: 'Stale',
        email: 'stale@broker.com',
        createdAt: DateTime.now(),
        isEmailVerified: true,
        subscription: UserSubscription(
          plan: 'free',
          isActive: true,
          features: [],
        ),
      ));

      final authVM = AuthViewModel(
        authRepository: stubAuthRepo,
        userRepository: stubUserRepo,
        autoInitialize: false,
      );

      expect(authVM.currentUser, isNull);
      // Invariant: Session state is strictly authoritative
      expect(authVM.isAuthenticated, isFalse);
    });
  });

  group('Auth Boundary Invariant 5: Supabase Unsupported Providers Fail Safely', () {
    late SupabaseAuthRepository supabaseRepo;

    setUp(() {
      supabaseRepo = SupabaseAuthRepository(
        userRepository: StubUserRepository(),
        client: sb.SupabaseClient('https://dummy.supabase.co', 'dummyKey'),
      );
    });

    test('signInWithGoogle throws AuthFailure.providerUnavailable (not UnsupportedError)',
        () async {
      expect(
        () => supabaseRepo.signInWithGoogle(),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.providerUnavailable,
        )),
      );
    });

    test('verifyPhoneNumber throws AuthFailure.providerUnavailable',
        () async {
      expect(
        () => supabaseRepo.verifyPhoneNumber(
          verificationId: 'fake-id',
          otpCode: '123456',
        ),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.providerUnavailable,
        )),
      );
    });

    test('sendPhoneVerificationOTP calls onError with AuthFailure message and throws AuthFailure',
        () async {
      String? caughtError;
      expect(
        () => supabaseRepo.sendPhoneVerificationOTP(
          phoneNumber: '+971500000000',
          onCodeSent: (_) {},
          onError: (err) => caughtError = err,
        ),
        throwsA(isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          AuthFailureCode.providerUnavailable,
        )),
      );
      expect(caughtError, contains('not supported'));
    });
  });
}
