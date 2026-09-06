import 'dart:async';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _supabaseStyleUuid = '550e8400-e29b-41d4-a716-446655440000';

UserModel _verifiedUser({String uid = _supabaseStyleUuid}) => UserModel(
      uid: uid,
      name: 'Logout User',
      email: 'logout@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'test',
        isActive: true,
        features: const [],
      ),
    );

class _LogoutStubAuthRepository implements AuthRepository {
  _LogoutStubAuthRepository({
    UserModel? initialUser,
    this.failSignOut = false,
  }) : _currentUser = initialUser;

  final StreamController<UserModel?> _controller =
      StreamController<UserModel?>.broadcast();
  bool failSignOut;
  UserModel? _currentUser;

  @override
  Stream<UserModel?> get authStateChanges => _controller.stream;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  void emit(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<void> signOut() async {
    if (failSignOut) {
      throw const AuthFailure(
        code: AuthFailureCode.network,
        message: 'Simulated sign out failure',
      );
    }

    _currentUser = null;
    _controller.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LogoutStubUserRepository implements UserRepository {
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _buildTestRouter(AuthViewModel authVM) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: authVM,
    redirect: (context, state) {
      if (authVM.isLoading) return null;

      final path = state.uri.path;
      final protected = path == '/home' || path == '/profile';
      if (!authVM.isAuthenticated && protected) {
        return '/welcome';
      }
      if (authVM.isAuthenticated && path == '/welcome') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME_SCREEN')),
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, __) => const Scaffold(body: Text('WELCOME_SCREEN')),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('authenticated user logout clears repository current user identity',
      () async {
    final repo = _LogoutStubAuthRepository(initialUser: _verifiedUser());

    expect(repo.currentUser, isNotNull);
    expect(repo.currentUserId, _supabaseStyleUuid);

    await repo.signOut();

    expect(repo.currentUser, isNull);
    expect(repo.currentUserId, isNull);
    await repo.dispose();
  });

  test('successful logout sets AuthViewModel to unauthenticated', () async {
    final repo = _LogoutStubAuthRepository(initialUser: _verifiedUser());
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );

    repo.emit(_verifiedUser());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await vm.signOut();

    expect(vm.currentUser, isNull);
    expect(vm.currentUserId, isNull);
    expect(vm.isAuthenticated, isFalse);

    vm.dispose();
    await repo.dispose();
  });

  testWidgets('successful logout re-evaluates route to unauthenticated screen',
      (tester) async {
    final repo = _LogoutStubAuthRepository(initialUser: _verifiedUser());
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );
    final router = _buildTestRouter(vm);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    repo.emit(_verifiedUser());
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN'), findsOneWidget);

    await vm.signOut();
    await tester.pumpAndSettle();

    expect(find.text('WELCOME_SCREEN'), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsNothing);

    await tester.pump(const Duration(seconds: 4));

    router.dispose();
    vm.dispose();
    await repo.dispose();
  });

  testWidgets('auth-state null after logout remains unauthenticated',
      (tester) async {
    final repo = _LogoutStubAuthRepository(initialUser: _verifiedUser());
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );
    final router = _buildTestRouter(vm);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    repo.emit(_verifiedUser());
    await tester.pumpAndSettle();
    await vm.signOut();
    await tester.pumpAndSettle();

    repo.emit(null);
    await tester.pumpAndSettle();

    expect(vm.isAuthenticated, isFalse);
    expect(find.text('WELCOME_SCREEN'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));

    router.dispose();
    vm.dispose();
    await repo.dispose();
  });

  test('stale OfflineAuthService cache cannot reauthenticate without session',
      () async {
    final offline = OfflineAuthService.instance;
    await offline.cacheUserModel(_verifiedUser(uid: 'stale-cached-user'));
    expect(await offline.isUserAuthenticated(), isTrue);

    final repo = _LogoutStubAuthRepository(initialUser: null);
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );

    repo.emit(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(vm.currentUser, isNull);
    expect(vm.currentUserId, isNull);
    expect(vm.isAuthenticated, isFalse);

    vm.dispose();
    await repo.dispose();
  });

  test('successful logout clears Supabase-style UUID identity', () async {
    final repo = _LogoutStubAuthRepository(initialUser: _verifiedUser());
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );

    repo.emit(_verifiedUser());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.currentUserId, _supabaseStyleUuid);

    await vm.signOut();

    expect(vm.currentUserId, isNull);
    expect(repo.currentUserId, isNull);

    vm.dispose();
    await repo.dispose();
  });

  test('cold-start restore with no session remains unauthenticated', () async {
    final offline = OfflineAuthService.instance;
    await offline.cacheUserModel(_verifiedUser(uid: 'cached-before-restart'));

    final repo = _LogoutStubAuthRepository(initialUser: null);
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );

    // Simulate startup auth stream resolving to no active SDK session.
    repo.emit(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(vm.currentUser, isNull);
    expect(vm.currentUserId, isNull);
    expect(vm.isAuthenticated, isFalse);

    vm.dispose();
    await repo.dispose();
  });

  testWidgets('signOut failure does not navigate to logged-out route',
      (tester) async {
    final repo = _LogoutStubAuthRepository(
      initialUser: _verifiedUser(),
      failSignOut: true,
    );
    final vm = AuthViewModel(
      authRepository: repo,
      userRepository: _LogoutStubUserRepository(),
      autoInitialize: true,
    );
    final router = _buildTestRouter(vm);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    repo.emit(_verifiedUser());
    await tester.pumpAndSettle();
    expect(find.text('HOME_SCREEN'), findsOneWidget);

    await expectLater(
      vm.signOut(),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.code,
          'code',
          AuthFailureCode.network,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(vm.isAuthenticated, isTrue);
    expect(find.text('HOME_SCREEN'), findsOneWidget);
    expect(find.text('WELCOME_SCREEN'), findsNothing);

    await tester.pump(const Duration(seconds: 4));

    router.dispose();
    vm.dispose();
    await repo.dispose();
  });
}
