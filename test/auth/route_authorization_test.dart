// AUTH-ROUTE-1 (tracker §7BF): protected-by-default GoRouter authorization.
//
// The route list is read from the app's REAL router (every declared GoRoute,
// shell branches and path parameters included), so a route added later is
// covered automatically: it is protected unless it is deliberately exempted
// both in lib/app.dart and in the reviewed list below.
// No network and no Supabase: fake repositories and stub pages only.

import 'dart:async';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/Sign-Up-Log-In/session_superseded_dialog_host.dart';
import 'package:broker_wallet/src/widgets/brand_splash/brand_splash_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserModel _user(String uid) => UserModel(
      uid: uid,
      name: 'Route User',
      email: 'route-$uid@example.test',
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

final _alice = _user('550e8400-e29b-41d4-a716-446655440000');
final _bob = _user('660e8400-e29b-41d4-a716-446655440000');

/// Identity events plus the displacement phases, as the real repository
/// publishes them.
class _Repo implements AuthRepository, AppSessionEvents {
  _Repo([this._current]);

  UserModel? _current;
  final _identities = StreamController<UserModel?>.broadcast(sync: true);
  final _phases =
      StreamController<AppSessionSupersededPhase>.broadcast(sync: true);
  final _unavailable = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _current;
    yield* _identities.stream;
  }

  @override
  UserModel? get currentUser => _current;

  @override
  String? get currentUserId => _current?.uid;

  @override
  Stream<AppSessionSupersededPhase> get sessionSupersededEvents =>
      _phases.stream;

  @override
  Stream<bool> get sessionCheckUnavailableEvents => _unavailable.stream;

  @override
  Future<void> retryAppSessionValidation() async {}

  /// A sign-out, an SDK-ended session or a completed account deletion: the
  /// identity simply becomes null.
  void emit(UserModel? user) {
    _current = user;
    _identities.add(user);
  }

  void beginDisplacement() =>
      _phases.add(AppSessionSupersededPhase.accessRevoked);

  void finishDisplacement() {
    _current = null;
    _identities.add(null);
    _phases.add(AppSessionSupersededPhase.localSignOutCompleted);
  }

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

/// Every route path the real router declares, nested and shell routes
/// included, as patterns (`/offers-details-by-id/:id`).
List<String> _declaredPaths(List<RouteBase> routes, [String parent = '']) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) {
      final full = route.path.startsWith('/')
          ? route.path
          : (parent == '/' ? '/${route.path}' : '$parent/${route.path}');
      paths
        ..add(full)
        ..addAll(_declaredPaths(route.routes, full));
    } else if (route is ShellRouteBase) {
      paths.addAll(_declaredPaths(route.routes, parent));
    }
  }
  return paths;
}

/// A navigable path for a pattern.
String _concrete(String pattern) =>
    pattern.replaceAllMapped(RegExp(r':(\w+)'), (m) => 'x-${m[1]}');

/// The only routes reviewed as reachable without an authorized session.
const _reviewedExempt = <String, RouteAccess>{
  '/': RouteAccess.bootstrap,
  '/welcome': RouteAccess.authEntry,
  '/sign-up': RouteAccess.authEntry,
  '/sign-in': RouteAccess.authEntry,
  '/email-verification': RouteAccess.verification,
  '/phone-otp': RouteAccess.verification,
  '/reset-password': RouteAccess.recovery,
};

/// The owner's list of sections that must require authorization.
const _mustBeProtected = [
  '/home', '/search', '/favorites', '/profile', // shell branches
  '/offers-list', '/requested-list', '/owners-list', '/offices-list',
  '/brokers-list', '/watchmen-list', '/quotation-list', '/map-view',
  '/toolkit-list', '/scanner', '/signature', '/imageToPdf', '/combine-pdfs',
  '/uae-links', '/analytics', '/notifications', '/notification-settings',
  '/match-details', '/add-requested', '/add-offers', '/add-owners',
  '/add-offices', '/add-watchmen', '/add-brokers', '/add-quotation',
  '/edit-profile', '/requested-details', '/requested-details-by-id/:id',
  '/offers-details', '/offers-details-by-id/:id', '/owners-details',
  '/offices-details', '/watchmen-details', '/brokers-details', '/language',
  '/security', '/subscription', '/my-plan', '/billing-payments',
  '/export-data', '/payment-selection/:plan', '/help-support',
  '/privacy-policy', '/terms-conditions', '/feedback', '/share-app',
  '/about', '/contact-us', '/info-placeholder',
];

/// Paths no route declares (yet): a future feature, a nested path under a
/// protected one, near-misses of the exempt routes.
const _undeclared = [
  '/no-such-route',
  '/a-future-feature',
  '/home/nested',
  '/profile/edit',
  '/offers-list/extra',
  '/sign-in/extra',
  '/welcome-old',
  '/WELCOME',
  '/phone-otp/extra',
  '/email-verification-old',
  '/reset-password/extra',
];

late List<String> _declared;

Iterable<String> get _protectedPatterns =>
    _declared.where((p) => !_reviewedExempt.containsKey(p));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.preloadAllLanguages();
    final repo = _Repo();
    final auth =
        AuthViewModel(authRepository: repo, userRepository: _Profiles());
    final recovery =
        PasswordRecoveryViewModel(gateway: null, authRepository: null);
    final router = createAppRouterForTesting(auth, recovery);
    _declared = _declaredPaths(router.configuration.routes);
    router.dispose();
    recovery.dispose();
    auth.dispose();
    await repo.dispose();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A. every declared route is classified', () {
    test(
        'A1 the real router declares every section, shell and parameter '
        'routes included, once each', () {
      expect(_declared, containsAll(_mustBeProtected));
      expect(_declared, containsAll(_reviewedExempt.keys));
      expect(_declared.toSet(), hasLength(_declared.length));
    });

    test(
        'A2 everything outside the reviewed exemptions is protected; no '
        'route is public', () {
      for (final pattern in _declared) {
        expect(routeAccessFor(_concrete(pattern)),
            _reviewedExempt[pattern] ?? RouteAccess.protected,
            reason: pattern);
      }
    });

    test('A3 an undeclared, future or near-miss path is protected', () {
      for (final path in _undeclared) {
        expect(routeAccessFor(path), RouteAccess.protected, reason: path);
      }
      expect(routeAccessFor('/welcome/'), RouteAccess.authEntry);
      expect(routeAccessFor('/offers-list/'), RouteAccess.protected);
    });
  });

  group('B. redirect outcomes', () {
    Iterable<String> all() => [..._declared.map(_concrete), ..._undeclared];

    test('B1 unknown bootstrap holds every route at the root gate', () {
      for (final path in all()) {
        expect(resolveAuthRedirect(AuthStatus.unknown, path),
            path == '/' ? isNull : '/',
            reason: path);
      }
    });

    test('B2 signed out: every protected route goes to Welcome', () {
      for (final path in [
        ..._protectedPatterns.map(_concrete),
        ..._undeclared
      ]) {
        expect(
            resolveAuthRedirect(AuthStatus.unauthenticated, path), '/welcome',
            reason: path);
      }
      expect(resolveAuthRedirect(AuthStatus.unauthenticated, '/'), '/welcome');
      for (final path in ['/welcome', '/sign-in', '/sign-up']) {
        expect(resolveAuthRedirect(AuthStatus.unauthenticated, path), isNull);
      }
      expect(resolveAuthRedirect(AuthStatus.unauthenticated, '/reset-password'),
          '/sign-in');
    });

    test(
        'B3 signed in: every protected route is reachable; entry screens, '
        'the root and the reset screen go Home', () {
      for (final path in [
        ..._protectedPatterns.map(_concrete),
        ..._undeclared
      ]) {
        expect(resolveAuthRedirect(AuthStatus.authenticated, path), isNull,
            reason: path);
      }
      for (final path in [
        '/',
        '/welcome',
        '/sign-in',
        '/sign-up',
        '/reset-password'
      ]) {
        expect(resolveAuthRedirect(AuthStatus.authenticated, path), '/home',
            reason: path);
      }
    });

    test('B4 verification routes keep their own routing', () {
      for (final status in [
        AuthStatus.authenticated,
        AuthStatus.unauthenticated
      ]) {
        for (final path in ['/email-verification', '/phone-otp']) {
          expect(resolveAuthRedirect(status, path), isNull,
              reason: '$status $path');
        }
      }
    });

    test('B5 an unresolved password recovery wins over every route', () {
      for (final status in AuthStatus.values) {
        for (final path in all()) {
          expect(
              resolveAuthRedirect(status, path, passwordRecoveryActive: true),
              path == '/reset-password' ? isNull : '/reset-password',
              reason: '$status $path');
        }
      }
    });

    test('B6 no redirect loops, and Home is never reached without a session',
        () {
      for (final status in AuthStatus.values) {
        for (final recovery in [false, true]) {
          for (final start in all()) {
            var path = start;
            var hops = 0;
            String? next;
            while ((next = resolveAuthRedirect(status, path,
                    passwordRecoveryActive: recovery)) !=
                null) {
              path = next!;
              expect(++hops, lessThanOrEqualTo(2),
                  reason: '$status $recovery $start');
            }
            final signedIn = status == AuthStatus.authenticated && !recovery;
            if (!signedIn) {
              expect(routeAccessFor(path), isNot(RouteAccess.protected),
                  reason: '$status $recovery $start -> $path');
            }
          }
        }
      }
    });
  });

  group('C. through a live router', () {
    late _Repo repo;
    late AuthViewModel auth;
    late ValueNotifier<bool> recovery;
    late GoRouter router;

    Future<void> pumpRouter(WidgetTester tester, {UserModel? user}) async {
      repo = _Repo(user);
      auth = AuthViewModel(authRepository: repo, userRepository: _Profiles());
      recovery = ValueNotifier<bool>(false);
      Widget page(String pattern) => Scaffold(body: Text('PAGE $pattern'));
      router = GoRouter(
        initialLocation: '/',
        refreshListenable: Listenable.merge([auth, recovery]),
        redirect: (context, state) => resolveAuthRedirect(
          auth.status,
          state.uri.path,
          passwordRecoveryActive: recovery.value,
        ),
        routes: [
          for (final pattern in _declared)
            GoRoute(
              path: pattern,
              builder: (_, __) => pattern == '/welcome'
                  ? SessionSupersededDialogHost(
                      authViewModel: auth, child: page(pattern))
                  : page(pattern),
            ),
        ],
      );
      addTearDown(() async {
        router.dispose();
        auth.dispose();
        recovery.dispose();
        await repo.dispose();
      });
      await tester.pumpWidget(ChangeNotifierProvider<AuthViewModel>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder on(String pattern) => find.text('PAGE $pattern');

    testWidgets(
        'C1 signed out: direct navigation to any protected route '
        'lands on Welcome', (tester) async {
      await pumpRouter(tester);
      expect(on('/welcome'), findsOneWidget);
      for (final pattern in [..._protectedPatterns, '/no-such-route']) {
        router.go(_concrete(pattern));
        await tester.pumpAndSettle();
        expect(on('/welcome'), findsOneWidget, reason: pattern);
        expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome',
            reason: pattern);
      }
    });

    testWidgets('C2 signed in: every protected route opens directly',
        (tester) async {
      await pumpRouter(tester, user: _alice);
      expect(on('/home'), findsOneWidget);
      for (final pattern in _protectedPatterns) {
        router.go(_concrete(pattern));
        await tester.pumpAndSettle();
        expect(on(pattern), findsOneWidget, reason: pattern);
      }
    });

    testWidgets('C3 a session that ends while Offers is open lands on Welcome',
        (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/offers-list');
      await tester.pumpAndSettle();
      expect(on('/offers-list'), findsOneWidget);
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(on('/offers-list'), findsNothing);
    });

    testWidgets(
        'C4 a session that ends while Add Offers is open (over '
        'Offers) leaves nothing of the old stack', (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/offers-list');
      await tester.pumpAndSettle();
      router.push('/add-offers');
      await tester.pumpAndSettle();
      expect(on('/add-offers'), findsOneWidget);
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(on('/add-offers'), findsNothing);
      expect(on('/offers-list'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.matches, hasLength(1));
    });

    testWidgets(
        'C5 account switch: the next account starts at Home, never on '
        "the previous account's screen", (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/owners-list');
      await tester.pumpAndSettle();
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      repo.emit(_bob);
      await tester.pumpAndSettle();
      expect(on('/home'), findsOneWidget);
      expect(on('/owners-list'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.matches, hasLength(1));
    });

    testWidgets(
        'C6 displacement while Offers is open: access closes at once '
        'and the one-shot notice shows on Welcome', (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/offers-list');
      await tester.pumpAndSettle();
      repo.beginDisplacement();
      await tester.pumpAndSettle();
      expect(on('/offers-list'), findsNothing);
      expect(on('/'), findsOneWidget, reason: 'held at the bootstrap gate');
      repo.finishDisplacement();
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('C7 a password recovery wins over an open protected route',
        (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/edit-profile');
      await tester.pumpAndSettle();
      recovery.value = true;
      await tester.pumpAndSettle();
      expect(on('/reset-password'), findsOneWidget);
      expect(on('/edit-profile'), findsNothing);
    });

    testWidgets('C8 signed out: verification routes stay, Home is never shown',
        (tester) async {
      await pumpRouter(tester);
      for (final pattern in ['/email-verification', '/phone-otp']) {
        router.go(pattern);
        await tester.pumpAndSettle();
        expect(on(pattern), findsOneWidget, reason: pattern);
      }
      for (final path in ['/home', '/', '/security']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(on('/home'), findsNothing, reason: path);
        expect(on('/welcome'), findsOneWidget, reason: path);
      }
    });

    testWidgets(
        'C9 a session that ends on Security (where Delete Account '
        'starts) lands on Welcome', (tester) async {
      await pumpRouter(tester, user: _alice);
      router.push('/profile');
      await tester.pumpAndSettle();
      router.push('/security');
      await tester.pumpAndSettle();
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(on('/security'), findsNothing);
    });

    testWidgets(
        'C10 a session that ends on a route opened with go (Feedback, as '
        'profile_viewmodel does) lands on Welcome', (tester) async {
      await pumpRouter(tester, user: _alice);
      router.go('/feedback');
      await tester.pumpAndSettle();
      expect(on('/feedback'), findsOneWidget);
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(on('/feedback'), findsNothing);
    });

    testWidgets(
        'C11 a session that ends on a list opened with go lands on Welcome',
        (tester) async {
      await pumpRouter(tester, user: _alice);
      router.go('/offers-list');
      await tester.pumpAndSettle();
      repo.emit(null);
      await tester.pumpAndSettle();
      expect(on('/welcome'), findsOneWidget);
      expect(on('/offers-list'), findsNothing);
    });
  });

  group('D. startup Splash', () {
    test(
        'D1 the launch overlay keeps a protected route covered until the '
        'redirect lands', () {
      final router = GoRouter(routes: [
        for (final pattern in _declared)
          GoRoute(path: pattern, builder: (_, __) => const SizedBox()),
      ]);
      addTearDown(router.dispose);
      BrandSplashStage stage(String path, AuthStatus status) =>
          startupSplashStage(
            router.configuration.findMatch(Uri.parse(path)),
            status: status,
            sessionCheckUnavailable: false,
            passwordRecoveryActive: false,
          );
      for (final pattern in _protectedPatterns) {
        final path = _concrete(pattern);
        expect(
            stage(path, AuthStatus.unauthenticated), BrandSplashStage.waiting,
            reason: path);
        expect(stage(path, AuthStatus.unknown), BrandSplashStage.waiting,
            reason: path);
        expect(
            stage(path, AuthStatus.authenticated), BrandSplashStage.destination,
            reason: path);
      }
      expect(stage('/welcome', AuthStatus.unauthenticated),
          BrandSplashStage.destination);
    });
  });
}
