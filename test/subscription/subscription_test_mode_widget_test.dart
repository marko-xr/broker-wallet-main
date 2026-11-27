import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/subscription_test_mode_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Run three ways: as is (control hidden), with SUBSCRIPTION_BACKEND=true and
// BW_DEPLOYMENT_ENV=staging on the default production URL (still hidden), and
// with a non-production SUPABASE_URL added (drawn).

SubscriptionServerState _state({
  String plan = 'free',
  String status = 'free',
  bool available = true,
  String? scenario,
}) =>
    SubscriptionServerState.fromJson({
      'plan': plan,
      'status': status,
      'read_only': false,
      'is_test': scenario != null,
      'cycle': null,
      'provider': null,
      'started_at': null,
      'paid_through': null,
      'next_charge_at': null,
      'usage': {
        for (final s in [
          'requests',
          'offers',
          'owners',
          'offices',
          'brokers',
          'watchmen',
          'quotations',
          'scanner',
          'signature',
          'image_to_pdf',
          'combine_pdfs',
        ])
          s: 0,
      },
      'items': const <Object?>[],
      'test_mode': {
        'available': available,
        'scenario': scenario,
        'expires_at': null,
      },
    });

class _Backend implements SubscriptionBackend {
  _Backend(this.state);

  SubscriptionServerState state;
  final actions = <String>[];
  Object? refuse;

  @override
  Future<SubscriptionServerState> fetchState() async => state;

  @override
  Future<StoreSyncResult> syncWithStore() async => StoreSyncResult.synced;

  @override
  Future<SubscriptionServerState> testControl(String action) async {
    actions.add(action);
    final refusal = refuse;
    if (refusal != null) throw refusal;
    state = action == 'plus_on'
        ? _state(plan: 'plus', status: 'plus_renewing', scenario: 'plus')
        : _state();
    return state;
  }
}

Future<SubscriptionStateController> _pump(
  WidgetTester tester,
  _Backend backend,
) async {
  final controller = SubscriptionStateController(backend: () => backend);
  addTearDown(controller.dispose);
  await tester.runAsync(() async {
    controller.attachUser('a');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<SubscriptionStateController>.value(
      value: controller,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('en'), Locale('ar')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(child: SubscriptionTestModeSection()),
        ),
      ),
    ),
  );
  // The strings load from the asset bundle, which needs real time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  final drawable = SubscriptionTestModeSection.buildAllows;

  testWidgets('a build that is not debug + backend + Staging draws nothing',
      (tester) async {
    await _pump(tester, _Backend(_state()));
    expect(find.byType(Switch), findsNothing);
    expect(find.text('TEST / STAGING'), findsNothing);
  }, skip: drawable);

  test('the default production URL never allows the control', () {
    if (SupabaseConfig.url.contains(SupabaseConfig.productionProjectRef)) {
      expect(SubscriptionTestModeSection.buildAllows, isFalse);
    }
  });

  group('on a Staging debug build', skip: !drawable, () {
    testWidgets('an account the server did not allowlist sees nothing',
        (tester) async {
      await _pump(tester, _Backend(_state(available: false)));
      expect(find.byType(Switch), findsNothing);
      expect(find.text('TEST / STAGING'), findsNothing);
    });

    testWidgets('the badge shows and the switch starts from the server',
        (tester) async {
      await _pump(tester, _Backend(_state()));
      expect(find.text('TEST / STAGING'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('reopening on an active override shows it ON', (tester) async {
      await _pump(
        tester,
        _Backend(
          _state(plan: 'plus', status: 'plus_renewing', scenario: 'plus'),
        ),
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('turning it on follows the server answer', (tester) async {
      final backend = _Backend(_state());
      await _pump(tester, backend);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await tester.pumpAndSettle();
      expect(backend.actions, ['plus_on']);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('a refusal leaves it OFF and tells the user', (tester) async {
      final backend = _Backend(_state())
        ..refuse = const SubscriptionTestControlRefused('not_allowlisted');
      await _pump(tester, backend);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.text(
            'The server refused this change, so the plan stays as it was.'),
        findsOneWidget,
      );
    });

    testWidgets('resetting usage asks first', (tester) async {
      final backend = _Backend(_state());
      await _pump(tester, backend);
      await tester.tap(find.text('Advanced test states'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reset test usage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset test usage'));
      await tester.pumpAndSettle();
      expect(backend.actions, isEmpty);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(backend.actions, isEmpty);

      await tester.tap(find.text('Reset test usage'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Reset'));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await tester.pumpAndSettle();
      expect(backend.actions, ['reset_usage']);
    });
  });
}
