import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/auth_wrapper.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/session_superseded_dialog_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserModel _signedInUser() => UserModel(
      uid: '550e8400-e29b-41d4-a716-446655440000',
      name: 'Session User',
      email: 'session@example.test',
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

class _SessionRepository implements AuthRepository, AppSessionEvents {
  _SessionRepository({UserModel? initialUser, this.publishInitialIdentity = true})
      : _currentUser = initialUser;

  final bool publishInitialIdentity;
  UserModel? _currentUser;
  int localSignOutStarts = 0;
  final _identities = StreamController<UserModel?>.broadcast(sync: true);
  final _phases =
      StreamController<AppSessionSupersededPhase>.broadcast(sync: true);
  final _unavailable = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<UserModel?> get authStateChanges async* {
    if (publishInitialIdentity) yield _currentUser;
    yield* _identities.stream;
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  @override
  Stream<AppSessionSupersededPhase> get sessionSupersededEvents =>
      _phases.stream;

  @override
  Stream<bool> get sessionCheckUnavailableEvents => _unavailable.stream;

  @override
  Future<void> retryAppSessionValidation() async {}

  void beginSupersededLocalSignOut() {
    _phases.add(AppSessionSupersededPhase.accessRevoked);
    localSignOutStarts++;
  }

  void repeatSupersededDetection() {
    _phases.add(AppSessionSupersededPhase.accessRevoked);
  }

  void finishSupersededLocalSignOut() {
    _currentUser = null;
    _identities.add(null);
    _phases.add(AppSessionSupersededPhase.localSignOutCompleted);
  }

  void ordinarySignOut() {
    _currentUser = null;
    _identities.add(null);
  }

  void validationUnavailable() => _unavailable.add(true);

  Future<void> dispose() async {
    await _identities.close();
    await _phases.close();
    await _unavailable.close();
  }

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

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  AuthViewModel auth, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) =>
        resolveAuthRedirect(auth.status, state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (_, __) => const AuthWrapper()),
      GoRoute(
        path: '/welcome',
        builder: (_, __) => SessionSupersededDialogHost(
          authViewModel: auth,
          child: const Scaffold(body: Text('WELCOME')),
        ),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (_, __) => const Scaffold(body: Text('SIGN IN')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewModel>.value(
      value: auth,
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.preloadAllLanguages();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('production path closes access before explicit local sign-out and '
      'signals completion afterward', () {
    final source = File('lib/src/repositories/supabase_auth_repository.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> _endSupersededSession()');
    final end = source.indexOf('void _clearPasswordRecovery()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final path = source.substring(start, end);
    final closed = path.indexOf('AppSessionSupersededPhase.accessRevoked');
    final signOut = path.indexOf('signOut(scope: SignOutScope.local)');
    final completed =
        path.indexOf('AppSessionSupersededPhase.localSignOutCompleted');
    expect(closed, greaterThanOrEqualTo(0));
    expect(signOut, greaterThan(closed));
    expect(completed, greaterThan(signOut));
    expect(source, contains('broadcast(sync: true)'));
  });

  testWidgets('displacement signs out before the one-shot dialog and OK '
      'leaves Welcome unauthenticated', (tester) async {
    final repository = _SessionRepository(initialUser: _signedInUser());
    final auth = AuthViewModel(
      authRepository: repository,
      userRepository: _Profiles(),
    );
    final router = await _pumpApp(tester, auth);
    addTearDown(() async {
      router.dispose();
      auth.dispose();
      await repository.dispose();
    });
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);

    repository.beginSupersededLocalSignOut();
    repository.repeatSupersededDetection();
    expect(repository.localSignOutStarts, 1);
    expect(auth.status, AuthStatus.unknown);
    expect(auth.hasSessionSupersededNotice, isFalse);
    await tester.pump();
    expect(find.text('HOME'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    repository.finishSupersededLocalSignOut();
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.unauthenticated);
    expect(repository.currentUserId, isNull);
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text("You've been signed out"), findsOneWidget);
    expect(
      find.text('Your account was signed in on another device. '
          'For your security, this device has been signed out.'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    repository.repeatSupersededDetection();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('WELCOME'), findsOneWidget);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(repository.currentUserId, isNull);

    router.go('/sign-in');
    await tester.pumpAndSettle();
    router.go('/welcome');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    repository.repeatSupersededDetection();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Arabic dialog keeps the requested copy and RTL', (tester) async {
    final repository = _SessionRepository(initialUser: _signedInUser());
    final auth = AuthViewModel(
      authRepository: repository,
      userRepository: _Profiles(),
    );
    final router = await _pumpApp(
      tester,
      auth,
      locale: const Locale('ar'),
      themeMode: ThemeMode.dark,
    );
    addTearDown(() async {
      router.dispose();
      auth.dispose();
      await repository.dispose();
    });
    await tester.pumpAndSettle();
    repository.beginSupersededLocalSignOut();
    repository.finishSupersededLocalSignOut();
    await tester.pumpAndSettle();
    expect(find.text('تم تسجيل خروجك'), findsOneWidget);
    expect(
      find.text('تم تسجيل الدخول إلى حسابك من جهاز آخر. '
          'لحماية حسابك، تم تسجيل خروج هذا الجهاز.'),
      findsOneWidget,
    );
    expect(find.text('حسنًا'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('تم تسجيل خروجك'))),
      TextDirection.rtl,
    );
    expect(
      Theme.of(tester.element(find.text('تم تسجيل خروجك'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('validation unavailable keeps Retry and has no dialog',
      (tester) async {
    final repository = _SessionRepository(publishInitialIdentity: false);
    final auth = AuthViewModel(
      authRepository: repository,
      userRepository: _Profiles(),
    );
    final router = await _pumpApp(tester, auth);
    addTearDown(() async {
      router.dispose();
      auth.dispose();
      await repository.dispose();
    });
    repository.validationUnavailable();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.status, AuthStatus.unknown);
  });

  testWidgets('ordinary logout has no displacement dialog', (tester) async {
    final repository = _SessionRepository(initialUser: _signedInUser());
    final auth = AuthViewModel(
      authRepository: repository,
      userRepository: _Profiles(),
    );
    final router = await _pumpApp(tester, auth);
    addTearDown(() async {
      router.dispose();
      auth.dispose();
      await repository.dispose();
    });
    await tester.pumpAndSettle();
    repository.ordinarySignOut();
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('normal unauthenticated startup has no dialog',
      (tester) async {
    final repository = _SessionRepository();
    final auth = AuthViewModel(
      authRepository: repository,
      userRepository: _Profiles(),
    );
    final router = await _pumpApp(tester, auth);
    addTearDown(() async {
      router.dispose();
      auth.dispose();
      await repository.dispose();
    });
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
