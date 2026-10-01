import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/services/subscription/plus_billing_gateway.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_add_payment_method_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_backup_payment_methods_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_billing_history_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_manage_billing_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_manage_payment_methods_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_payment_details_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_payment_help_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_change_period_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_legal_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_manage_subscription_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_payment_methods_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_paywall_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_purchase_progress_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_purchase_review_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_restore_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_subscription_help_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plus_usage_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_billing_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Test fixtures use a non-AED currency on purpose: the Plus UI must render
// whatever complete price string the billing source supplies and never
// assume a currency.
const SubscriptionPlanUiModel testMonthlyPlan = SubscriptionPlanUiModel(
  id: 'test.monthly',
  period: SubscriptionPeriod.monthly,
  localizedPrice: 'USD 4.99',
);

const SubscriptionPlanUiModel testAnnualPlan = SubscriptionPlanUiModel(
  id: 'test.annual',
  period: SubscriptionPeriod.annual,
  localizedPrice: 'USD 49.99',
  monthlyEquivalent: 'USD 4.17',
  savingsPercent: 17,
);

const SubscriptionOfferingUiModel testOffering = SubscriptionOfferingUiModel(
  plans: [testMonthlyPlan, testAnnualPlan],
  preselectedPeriod: SubscriptionPeriod.annual,
);

SubscriptionUiState testActive({
  bool preview = false,
  PlusStore store = PlusStore.googlePlay,
}) =>
    SubscriptionUiState(
      status: SubscriptionStatus.active,
      period: SubscriptionPeriod.annual,
      renewsOn: DateTime(2027, 1, 15),
      nextChargePrice: 'USD 49.99',
      billingPeriodPrice: 'USD 49.99',
      store: store,
      isPreview: preview,
    );

/// A state for [status] billed through [store], with realistic supplied dates
/// and prices (a non-AED currency, on purpose).
SubscriptionUiState testState(
  SubscriptionStatus status, {
  PlusStore store = PlusStore.googlePlay,
}) {
  switch (status) {
    case SubscriptionStatus.free:
      return const SubscriptionUiState.free();
    case SubscriptionStatus.active:
      return testActive(store: store);
    case SubscriptionStatus.trial:
      return SubscriptionUiState(
        status: status,
        period: SubscriptionPeriod.annual,
        trialEndsOn: DateTime(2027, 1, 8),
        renewsOn: DateTime(2027, 1, 8),
        nextChargePrice: 'USD 49.99',
        billingPeriodPrice: 'USD 49.99',
        store: store,
      );
    case SubscriptionStatus.cancelledActive:
      return SubscriptionUiState(
        status: status,
        period: SubscriptionPeriod.annual,
        expiresOn: DateTime(2027, 3, 1),
        billingPeriodPrice: 'USD 49.99',
        store: store,
      );
    case SubscriptionStatus.gracePeriod:
      return SubscriptionUiState(
        status: status,
        period: SubscriptionPeriod.monthly,
        expiresOn: DateTime(2027, 2, 5),
        nextChargePrice: 'USD 4.99',
        billingPeriodPrice: 'USD 4.99',
        store: store,
      );
    case SubscriptionStatus.billingIssue:
      return SubscriptionUiState(
        status: status,
        period: SubscriptionPeriod.monthly,
        nextChargePrice: 'USD 4.99',
        billingPeriodPrice: 'USD 4.99',
        store: store,
      );
    case SubscriptionStatus.expired:
      return SubscriptionUiState(
        status: status,
        period: SubscriptionPeriod.annual,
        expiresOn: DateTime(2026, 12, 1),
        store: store,
      );
  }
}

/// The view model under test and the fake billing source that drives it.
class PlusTestCtx {
  PlusTestCtx(this.vm, this.gateway);

  final PlusSubscriptionViewModel vm;
  final FakePlusGateway gateway;
}

PlusTestCtx plusCtx({FakePlusGateway? gateway}) {
  final g = gateway ?? FakePlusGateway();
  final vm = PlusSubscriptionViewModel(gateway: g);
  addTearDown(() async {
    vm.dispose();
    await g.dispose();
  });
  return PlusTestCtx(vm, g);
}

/// A surface tall enough that a whole scrolling screen is built at once.
void tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A realistic narrow phone.
void smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps the real Plus screens at [route] with the subscription in [status],
/// billed through [store], and returns the context that drives them.
Future<PlusTestCtx> openPlusScreen(
  WidgetTester tester,
  String route, {
  SubscriptionStatus status = SubscriptionStatus.free,
  PlusStore store = PlusStore.googlePlay,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
  bool small = false,
  FakePlusGateway? gateway,
}) async {
  if (small) {
    smallPhone(tester);
  } else {
    tallSurface(tester);
  }
  final c = plusCtx(gateway: gateway);
  // Free has no subscription to pin a store, so the preview store decides the
  // wording; a current state carries its own store.
  c.vm.debugSetStore(store);
  if (status != SubscriptionStatus.free) {
    c.vm.applyEntitlement(testState(status, store: store));
  }
  await tester.pumpWidget(
    plusTestApp(
      c.vm,
      initialLocation: route,
      locale: locale,
      themeMode: themeMode,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

/// English wording of the store's display name, as the UI renders it.
String storeName(PlusStore store) =>
    store == PlusStore.appStore ? 'App Store' : 'Google Play';

/// Scrolls the screen's list until [target] exists and is on screen.
///
/// The Subscription & Billing screens are lazy lists: a row below the visible
/// area (plus a small cache) has not been built, so `find` matches nothing and
/// `ensureVisible` has no element to work with. At large text on a small phone
/// that is most rows. Scrolling the real scrollable builds the row, then brings
/// it fully into view.
Future<void> scrollToVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Brings [target] into view (inside an open sheet or a pinned bar) and checks
/// that it really is on the 320x568 screen, so an action that merely exists but
/// cannot be reached fails the test.
Future<void> expectReachable(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final rect = tester.getRect(target);
  expect(rect.top, greaterThanOrEqualTo(0), reason: 'clipped above the screen');
  expect(rect.bottom, lessThanOrEqualTo(568),
      reason: 'clipped below the screen');
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
}

/// Words that would mean Broker Wallet is collecting, storing or showing a
/// payment method of its own.
const paymentWords = [
  'Visa',
  'Mastercard',
  'CVV',
  'Card number',
  'Expiry',
  'Expiration',
  'Add card',
  'Saved card',
  'Default card',
  'Credit',
  'Debit',
  'PayPal',
  'Apple Pay',
  'Google Pay',
  'Stripe',
  'Telr',
  'MasterCard',
  'Cardholder',
  'Postal',
  'Bank account',
  'Subtotal',
  'VAT',
  'Discount',
  '••',
  '4242',
];

/// Asserts the screen on show collects, stores and displays no payment method:
/// no card word, no input field, no payment-provider choice, no card icon.
void expectNoPaymentForm(WidgetTester tester) {
  for (final word in paymentWords) {
    expect(find.textContaining(word), findsNothing, reason: word);
  }
  expect(find.byType(TextField), findsNothing);
  expect(find.byType(TextFormField), findsNothing);
  expect(
    find.byWidgetPredicate((w) => w is Radio || w is RadioListTile),
    findsNothing,
  );
  expect(find.byIcon(Icons.credit_card), findsNothing);
  expect(find.byIcon(Icons.payment), findsNothing);
  expect(tester.takeException(), isNull);
}

/// A billing source the test drives by hand.
class FakePlusGateway implements PlusBillingGateway {
  FakePlusGateway({
    this.offering = testOffering,
    this.billingAvailable = true,
  });

  SubscriptionOfferingUiModel offering;
  bool billingAvailable;
  Object? loadError;

  int loadCalls = 0;
  int purchaseCalls = 0;
  int restoreCalls = 0;

  StreamController<PurchaseUpdate>? purchaseController;
  Completer<RestoreResult>? restoreCompleter;
  SubscriptionPlanUiModel? lastPlan;

  @override
  bool get isBillingAvailable => billingAvailable;

  @override
  Future<SubscriptionOfferingUiModel> loadOffering() async {
    loadCalls++;
    final error = loadError;
    if (error != null) throw error;
    return offering;
  }

  @override
  Stream<PurchaseUpdate> purchase(SubscriptionPlanUiModel plan) {
    purchaseCalls++;
    lastPlan = plan;
    final controller = StreamController<PurchaseUpdate>();
    purchaseController = controller;
    return controller.stream;
  }

  @override
  Future<RestoreResult> restorePurchases() {
    restoreCalls++;
    final completer = Completer<RestoreResult>();
    restoreCompleter = completer;
    return completer.future;
  }

  /// Releases the purchase stream WITHOUT waiting for it.
  ///
  /// `StreamController.close()` returns a future that completes only after the
  /// listener has been cancelled, and that cancellation is a microtask in the
  /// zone the listener was created in. For a widget test that zone is
  /// `flutter_test`'s fake-async zone, whose microtasks are flushed only while
  /// the test body runs (`AutomatedTestWidgetsFlutterBinding.runTest`). A
  /// tear-down runs after the body, so awaiting that future there can never
  /// finish whenever the body ended with the stream still open — for example
  /// because an assertion failed first. The test would then sit "running"
  /// forever, and because the expanded reporter prints a failure only when its
  /// test completes, the assertion that failed would never be shown.
  Future<void> dispose() async {
    final controller = purchaseController;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }
}

/// Pumps fixed 100 ms frames until [finder] matches, then returns.
///
/// Use this instead of `pumpAndSettle` for any screen that can legitimately
/// keep an indeterminate animation running (the purchase progress spinners).
/// `pumpAndSettle` waits for the whole tree to stop requesting frames, which
/// such a screen never does; this waits for the one thing the test actually
/// needs, and fails with a readable message after a bounded number of frames.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(
    'Gave up after $maxFrames frames (${step * maxFrames}) waiting for: '
    '$finder',
  );
}

Map<String, dynamic> _readArb(String lang) => json.decode(
      File('lib/src/common/localization/app_$lang.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

// Top-level finals initialise on first use, so tests can build their
// expectation tables while `main()` is still registering them.
final Map<String, dynamic> enStrings = _readArb('en');
final Map<String, dynamic> arStrings = _readArb('ar');

/// Mirrors the harness the account-deletion UI tests use: the ARB files and
/// icons are served from disk, so the real localization delegate works.
Future<void> setUpPlusTestAssets(TestWidgetsFlutterBinding binding) async {
  binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      final file = File(key);
      if (!file.existsSync()) return null;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      return ByteData.view(bytes.buffer);
    },
  );
  await AppLocalizations.preloadAllLanguages();
}

/// English string for [key], with `{name}` placeholders filled from [args].
String en(String key, [Map<String, String> args = const {}]) =>
    _fill(enStrings[key] as String, args);

String ar(String key, [Map<String, String> args = const {}]) =>
    _fill(arStrings[key] as String, args);

String _fill(String text, Map<String, String> args) {
  var result = text;
  args.forEach((name, value) => result = result.replaceAll('{$name}', value));
  return result;
}

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

/// The real Plus screens behind a real GoRouter, with the view model supplied.
Widget plusTestApp(
  PlusSubscriptionViewModel vm, {
  String initialLocation = '/plus',
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/plus', builder: (_, __) => const PlusPaywallView()),
      GoRoute(
        path: '/plus/review',
        builder: (_, __) => const PlusPurchaseReviewView(),
      ),
      GoRoute(
        path: '/plus/purchase',
        builder: (_, __) => const PlusPurchaseProgressView(),
      ),
      GoRoute(
          path: '/plus/restore', builder: (_, __) => const PlusRestoreView()),
      GoRoute(
        path: '/subscription-billing',
        builder: (_, __) => const SubscriptionBillingView(),
      ),
      GoRoute(
        path: '/subscription-billing/manage',
        builder: (_, __) => const PlusManageSubscriptionView(),
      ),
      GoRoute(
        path: '/subscription-billing/change-period',
        builder: (_, __) => const PlusChangePeriodView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-details',
        builder: (_, __) => const PlusPaymentDetailsView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods',
        builder: (_, __) => const PlusPaymentMethodsView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods/add',
        builder: (_, __) => const PlusAddPaymentMethodView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods/manage',
        builder: (_, __) => const PlusManagePaymentMethodsView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods/backup',
        builder: (_, __) => const PlusBackupPaymentMethodsView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods/billing',
        builder: (_, __) => const PlusManageBillingView(),
      ),
      GoRoute(
        path: '/subscription-billing/payment-methods/help',
        builder: (_, __) => const PlusPaymentHelpView(),
      ),
      GoRoute(
        path: '/subscription-billing/history',
        builder: (_, __) => const PlusBillingHistoryView(),
      ),
      GoRoute(
        path: '/subscription-billing/help',
        builder: (_, __) => const PlusSubscriptionHelpView(),
      ),
      GoRoute(
        path: '/subscription-billing/legal',
        builder: (_, __) => const PlusLegalView(),
      ),
      GoRoute(
        path: '/subscription-billing/usage',
        // Replaces the legacy Firestore usage read, so no Firebase is needed.
        builder: (_, __) =>
            const PlusUsageView(usageSection: SizedBox.shrink()),
      ),
      // The former routes, redirected exactly as in the app router.
      GoRoute(
        path: '/my-plan',
        redirect: (_, __) => '/subscription-billing',
      ),
      GoRoute(path: '/subscription', redirect: (_, __) => '/plus'),
      GoRoute(
        path: '/payment-selection/:plan',
        redirect: (_, __) => '/plus',
      ),
      GoRoute(path: '/profile', builder: (_, __) => _stub('profile-stub')),
      GoRoute(path: '/help-support', builder: (_, __) => _stub('support-stub')),
      GoRoute(
          path: '/terms-conditions', builder: (_, __) => _stub('terms-stub')),
      GoRoute(
          path: '/privacy-policy', builder: (_, __) => _stub('privacy-stub')),
    ],
  );

  return ChangeNotifierProvider<PlusSubscriptionViewModel>.value(
    value: vm,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
