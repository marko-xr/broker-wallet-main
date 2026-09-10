import 'dart:async';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';

UserModel _verifiedSession() => UserModel(
      uid: _uid,
      name: 'Nav User',
      email: 'nav@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'test',
        isActive: false,
        features: const [],
      ),
      preferences: const {},
    );

class _NavAuthRepository implements AuthRepository {
  _NavAuthRepository({UserModel? initialUser}) : _currentUser = initialUser;

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

class _NavUserRepository implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Exercises the real redirect through a router, counting how many distinct
/// destinations the app actually lands on.
GoRouter _routerUnderTest(AuthViewModel authVM, List<String> visited) {
  Widget screen(String label) => Builder(builder: (_) {
        visited.add(label);
        return Scaffold(body: Text(label));
      });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authVM,
    redirect: (context, state) =>
        resolveAuthRedirect(authVM.status, state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (_, __) => screen('SPLASH')),
      GoRoute(path: '/welcome', builder: (_, __) => screen('WELCOME')),
      GoRoute(path: '/sign-in', builder: (_, __) => screen('SIGN_IN')),
      GoRoute(path: '/sign-up', builder: (_, __) => screen('SIGN_UP')),
      GoRoute(path: '/home', builder: (_, __) => screen('HOME')),
      GoRoute(
        path: '/email-verification',
        builder: (_, __) => screen('EMAIL_VERIFICATION'),
      ),
      GoRoute(path: '/phone-otp', builder: (_, __) => screen('PHONE_OTP')),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveAuthRedirect is the single authority', () {
    test('unknown bootstrap holds the root gate and pulls everything to it',
        () {
      expect(resolveAuthRedirect(AuthStatus.unknown, '/'), isNull);
      expect(resolveAuthRedirect(AuthStatus.unknown, '/home'), '/');
      expect(resolveAuthRedirect(AuthStatus.unknown, '/welcome'), '/');
      expect(resolveAuthRedirect(AuthStatus.unknown, '/sign-in'), '/');
    });

    test('authenticated leaves the root gate for Home', () {
      expect(resolveAuthRedirect(AuthStatus.authenticated, '/'), '/home');
    });

    test('unauthenticated leaves the root gate for Welcome', () {
      expect(resolveAuthRedirect(AuthStatus.unauthenticated, '/'), '/welcome');
    });

    test('unauthenticated cannot reach a protected route', () {
      for (final path in const [
        '/home',
        '/search',
        '/favorites',
        '/profile',
        '/profile/edit',
      ]) {
        expect(
          resolveAuthRedirect(AuthStatus.unauthenticated, path),
          '/welcome',
          reason: path,
        );
      }
    });

    test('authenticated is carried off every auth screen', () {
      for (final path in const ['/welcome', '/sign-in', '/sign-up']) {
        expect(
          resolveAuthRedirect(AuthStatus.authenticated, path),
          '/home',
          reason: path,
        );
      }
    });

    test('authenticated stays put on a protected route', () {
      expect(resolveAuthRedirect(AuthStatus.authenticated, '/home'), isNull);
      expect(
          resolveAuthRedirect(AuthStatus.authenticated, '/profile'), isNull);
    });

    test('email-verification and phone-otp keep their own routing', () {
      for (final status in AuthStatus.values) {
        if (status == AuthStatus.unknown) continue;
        expect(
          resolveAuthRedirect(status, '/email-verification'),
          isNull,
          reason: '$status',
        );
        expect(
          resolveAuthRedirect(status, '/phone-otp'),
          isNull,
          reason: '$status',
        );
      }
    });
  });

  group('Route outcomes through a live router', () {
    testWidgets('a verified session lands on Home without passing Welcome',
        (tester) async {
      final authRepository = _NavAuthRepository(initialUser: _verifiedSession());
      final authVM = AuthViewModel(
        authRepository: authRepository,
        userRepository: _NavUserRepository(),
      );
      final visited = <String>[];
      final router = _routerUnderTest(authVM, visited);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVM,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(visited, isNot(contains('WELCOME')));

      authVM.dispose();
      await authRepository.dispose();
    });

    testWidgets('no session lands on Welcome and never renders Home',
        (tester) async {
      final authRepository = _NavAuthRepository();
      final authVM = AuthViewModel(
        authRepository: authRepository,
        userRepository: _NavUserRepository(),
      );
      final visited = <String>[];
      final router = _routerUnderTest(authVM, visited);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVM,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WELCOME'), findsOneWidget);
      expect(visited, isNot(contains('HOME')));

      authVM.dispose();
      await authRepository.dispose();
    });

    testWidgets(
        'sign-in success produces exactly one navigation outcome and never '
        'reveals Welcome', (tester) async {
      final authRepository = _NavAuthRepository();
      final authVM = AuthViewModel(
        authRepository: authRepository,
        userRepository: _NavUserRepository(),
      );
      final visited = <String>[];
      final router = _routerUnderTest(authVM, visited);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVM,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('WELCOME'), findsOneWidget);

      // Welcome now uses replacement-style routing, so Sign-In does not sit on
      // top of Welcome and Welcome cannot be revealed beneath it.
      router.go('/sign-in');
      await tester.pumpAndSettle();
      expect(find.text('SIGN_IN'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.matches.length, 1);

      visited.clear();

      // The session resolves. Only the router acts on it.
      authRepository.emit(_verifiedSession());
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(visited, <String>['HOME']);

      authVM.dispose();
      await authRepository.dispose();
    });

    testWidgets('sign-up success does not race the router', (tester) async {
      final authRepository = _NavAuthRepository();
      final authVM = AuthViewModel(
        authRepository: authRepository,
        userRepository: _NavUserRepository(),
      );
      final visited = <String>[];
      final router = _routerUnderTest(authVM, visited);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVM,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/sign-up');
      await tester.pumpAndSettle();
      visited.clear();

      authRepository.emit(_verifiedSession());
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(visited, <String>['HOME']);

      authVM.dispose();
      await authRepository.dispose();
    });

    testWidgets('sign-out returns to Welcome exactly once', (tester) async {
      final authRepository = _NavAuthRepository(initialUser: _verifiedSession());
      final authVM = AuthViewModel(
        authRepository: authRepository,
        userRepository: _NavUserRepository(),
      );
      final visited = <String>[];
      final router = _routerUnderTest(authVM, visited);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVM,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      visited.clear();
      authRepository.emit(null);
      await tester.pumpAndSettle();

      expect(find.text('WELCOME'), findsOneWidget);
      expect(visited, <String>['WELCOME']);

      authVM.dispose();
      await authRepository.dispose();
    });
  });
}
