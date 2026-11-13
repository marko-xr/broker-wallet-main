import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/widgets/brand_splash/brand_splash_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _brand = 'محفظة الوسيط\nإدارة ممتلكاتك';

class _Startup extends ChangeNotifier {
  final routing = ValueNotifier(0);
  AuthStatus status = AuthStatus.unknown;
  bool unavailable = false;
  bool recovery = false;
  int retryCalls = 0;

  void update({bool refreshRouter = true}) {
    notifyListeners();
    if (refreshRouter) routing.value++;
  }

  @override
  void dispose() {
    routing.dispose();
    super.dispose();
  }
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Startup startup, {
  bool reduceMotion = false,
  String initialLocation = '/',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: startup.routing,
    redirect: (_, state) => resolveAuthRedirect(
      startup.status,
      state.uri.path,
      passwordRecoveryActive: startup.recovery,
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ListenableBuilder(
          listenable: startup,
          builder: (_, __) => Scaffold(
            body: Center(
              child: startup.unavailable
                  ? TextButton(
                      onPressed: () => startup.retryCalls++,
                      child: const Text('Retry'),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      for (final entry in {
        '/home': 'Private Home',
        '/welcome': 'Welcome',
        '/reset-password': 'Reset Password',
      }.entries)
        GoRoute(
          path: entry.key,
          builder: (_, __) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () {}, child: Text(entry.value)),
            ),
          ),
        ),
    ],
  );

  final updates = Listenable.merge([router.routerDelegate, startup]);
  await tester.pumpWidget(MaterialApp.router(
    routerConfig: router,
    builder: (context, app) => Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: BrandSplashRouteBuilder(
          listenable: updates,
          builder: (_, child) => BrandSplashGate(
            stage: startupSplashStage(
              router.routerDelegate.currentConfiguration,
              status: startup.status,
              sessionCheckUnavailable: startup.unavailable,
              passwordRecoveryActive: startup.recovery,
            ),
            title: 'محفظة الوسيط',
            tagline: 'إدارة ممتلكاتك',
            child: child!,
          ),
          child: app,
        ),
      ),
    ),
  ));
  addTearDown(router.dispose);
  addTearDown(startup.dispose);
  await tester.pump();
  return router;
}

void main() {
  for (final (status, path, destination) in [
    (AuthStatus.authenticated, '/home', 'Private Home'),
    (AuthStatus.unauthenticated, '/welcome', 'Welcome'),
  ]) {
    testWidgets('keeps $destination covered until the router settles',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final startup = _Startup();
        final router = await _mount(tester, startup, initialLocation: '/home');
        expect(router.routerDelegate.currentConfiguration.uri.path, '/');
        expect(find.text('Private Home'), findsNothing);
        expect(find.bySemanticsLabel(_brand), findsOneWidget);

        // Bootstrap is resolved, but the router has not applied its redirect.
        startup
          ..status = status
          ..update(refreshRouter: false);
        await tester.pump(const Duration(milliseconds: 1600));
        expect(router.routerDelegate.currentConfiguration.uri.path, '/');
        expect(find.bySemanticsLabel(_brand), findsOneWidget);
        expect(find.text(destination), findsNothing);

        startup.update();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(router.routerDelegate.currentConfiguration.uri.path, path);
        expect(find.text(destination, skipOffstage: false), findsOneWidget);
        expect(find.text(destination).hitTestable(), findsNothing);
        expect(find.bySemanticsLabel(destination), findsNothing);

        await tester.pumpAndSettle();
        expect(find.text(destination).hitTestable(), findsOneWidget);
        expect(find.bySemanticsLabel(_brand), findsNothing);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('Retry is actionable immediately and the intro never replays',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final startup = _Startup();
      await _mount(tester, startup);

      startup
        ..unavailable = true
        ..update();
      await tester.pump();
      expect(find.bySemanticsLabel(_brand), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(startup.retryCalls, 1);
      expect(find.text('Private Home'), findsNothing);

      startup
        ..status = AuthStatus.authenticated
        ..unavailable = false
        ..update();
      await tester.pumpAndSettle();
      expect(find.text('Private Home').hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel(_brand), findsNothing);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('reduced motion reveals a recovery link without the iris',
      (tester) async {
    final startup = _Startup()..recovery = true;
    await _mount(tester, startup, reduceMotion: true);
    await tester.pump();

    expect(find.text('Reset Password').hitTestable(), findsOneWidget);
    expect(find.text('Private Home'), findsNothing);
    expect(find.bySemanticsLabel(_brand), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
