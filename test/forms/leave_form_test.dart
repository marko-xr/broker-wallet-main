// Leaving an Add form (save, cancel, discard) goes back to where it was opened
// from — a list, or Home's quick actions — never straight to Home.

import 'dart:io';

import 'package:broker_wallet/src/common/routes/leave_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('HOME'))),
        GoRoute(
            path: '/offices-list',
            builder: (_, __) => const Scaffold(body: Text('LIST'))),
        GoRoute(
            path: '/add-offices',
            builder: (_, __) => const Scaffold(body: Text('FORM'))),
      ],
    );

void main() {
  testWidgets('a form opened from a list returns to that list', (tester) async {
    final router = _router('/offices-list');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/add-offices');
    await tester.pumpAndSettle();
    expect(find.text('FORM'), findsOneWidget);

    leaveForm(router);
    await tester.pumpAndSettle();
    expect(find.text('LIST'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('a form opened from Home returns to Home', (tester) async {
    final router = _router('/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/add-offices');
    await tester.pumpAndSettle();

    leaveForm(router);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a discard dialog closes, then the form goes back',
      (tester) async {
    final router = _router('/offices-list');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/add-offices');
    await tester.pumpAndSettle();

    final form = tester.element(find.text('FORM'));
    showDialog<void>(
      context: form,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            onPressed: () {
              // As the Add view models do: the router first, then close.
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              leaveForm(router);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('LIST'), findsOneWidget);
  });

  testWidgets('a form opened by a link, with nothing underneath, goes Home',
      (tester) async {
    final router = _router('/add-offices');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    leaveForm(router);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  test('no Add form sends the user straight to Home any more', () {
    for (final path in [
      'lib/src/viewmodels/AddScreens/add_brokers_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_offices_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_watchmen_viewmodel.dart',
      'lib/src/views/Screens/home/quotation/add_quotation_viewmodel.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains("context.go('/home')"), isFalse, reason: path);
      expect(source, contains('leaveForm('), reason: path);
    }
  });
}
