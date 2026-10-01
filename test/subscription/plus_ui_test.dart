import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/upgrade_to_plus_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plus_test_support.dart';

// The shared harness lives in plus_test_support.dart; these keep this file's
// call sites short.
PlusTestCtx _ctx({FakePlusGateway? gateway}) => plusCtx(gateway: gateway);

void _tallSurface(WidgetTester tester) => tallSurface(tester);

void _smallPhone(WidgetTester tester) => smallPhone(tester);

/// Finder key for the button the sheet tests use to open a sheet. A key, not
/// the button's label, so the finder survives any change to its text.
const Key _sheetTrigger = Key('plus-sheet-test-trigger');

/// A plain app around [home] with the real theme and localization.
Widget _sheetApp(Widget home, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => setUpPlusTestAssets(binding));
  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('paywall', () {
    testWidgets('shows both billing periods with complete store prices',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusPeriodMonthly')), findsOneWidget);
      expect(find.text(en('plusPeriodAnnual')), findsOneWidget);
      expect(find.text('USD 49.99 / year'), findsOneWidget);
      expect(find.text('USD 4.99 / month'), findsOneWidget);
      expect(
        find.text(en('plusMonthlyEquivalent', {'price': 'USD 4.17'})),
        findsOneWidget,
      );
      expect(
        find.text(en('plusSavePercent', {'percent': '17'})),
        findsOneWidget,
      );
      expect(find.text(en('plusContinue')), findsOneWidget);
      // The currency is whatever the source supplied, never assumed.
      expect(find.textContaining('AED'), findsNothing);
    });

    testWidgets('the full annual charge stays visible next to the equivalent',
        (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(plusTestApp(_ctx().vm));
      await tester.pumpAndSettle();

      expect(
        find.text(en('plusBilledAnnually', {'price': 'USD 49.99'})),
        findsWidgets,
      );
    });

    testWidgets('selecting a period updates the selected plan', (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      expect(c.vm.selectedPlan, testAnnualPlan);

      await tester.tap(find.text(en('plusPeriodMonthly')));
      await tester.pumpAndSettle();
      expect(c.vm.selectedPlan, testMonthlyPlan);
    });

    testWidgets('works with a single plan', (tester) async {
      _tallSurface(tester);
      final c = _ctx(
        gateway: FakePlusGateway(
          offering: const SubscriptionOfferingUiModel(plans: [testAnnualPlan]),
        ),
      );
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusPeriodAnnual')), findsOneWidget);
      expect(find.text(en('plusPeriodMonthly')), findsNothing);
      expect(find.text(en('plusContinue')), findsOneWidget);
    });

    testWidgets('shows the Free versus Plus comparison without table layout',
        (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(plusTestApp(_ctx().vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusCompareTitle')), findsOneWidget);
      expect(find.text(en('plusBenefitRecordsTitle')), findsOneWidget);
      expect(find.text(en('plusBenefitToolkitTitle')), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('does not advertise features the app does not have',
        (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(plusTestApp(_ctx().vm));
      await tester.pumpAndSettle();

      for (final word in [
        'Priority support',
        'analytics',
        'Export',
        'Quotation'
      ]) {
        expect(find.textContaining(word, findRichText: true), findsNothing,
            reason: word);
      }
    });

    testWidgets('offers no payment-method choice', (tester) async {
      _tallSurface(tester);
      await tester.pumpWidget(plusTestApp(_ctx().vm));
      await tester.pumpAndSettle();

      for (final word in [
        'PayPal',
        'Apple Pay',
        'Google Pay',
        'Credit',
        'CVV'
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('without a billing source it explains and offers no purchase',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx(
        gateway: FakePlusGateway(
          offering: const SubscriptionOfferingUiModel.unavailable(),
          billingAvailable: false,
        ),
      );
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusPlansUnavailableTitle')), findsOneWidget);
      expect(find.text(en('plusContinue')), findsNothing);
    });

    testWidgets('someone already on Plus is pointed to My Plan',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      c.vm.applyEntitlement(testActive());
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusAlreadyPlusTitle')), findsOneWidget);
      expect(find.text(en('plusContinue')), findsNothing);
      expect(find.text(en('plusPeriodAnnual')), findsNothing);
    });

    testWidgets('an expired subscriber is told, and offered to resubscribe',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      c.vm.applyEntitlement(testState(SubscriptionStatus.expired));
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusExpiredTitle')), findsOneWidget);
      expect(find.text(en('plusResubscribe')), findsOneWidget);
    });

    testWidgets('a pending purchase is shown without unlocking anything',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      c.vm.debugShowPurchasePhase(PurchasePhase.pending);
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(find.text(en('plusPendingBannerTitle')), findsOneWidget);
      expect(find.text(en('plusAlreadyPlusTitle')), findsNothing);
      expect(c.vm.status, SubscriptionStatus.free);
    });

    testWidgets(
        'a store trial is described as a trial with its follow-on price',
        (tester) async {
      _tallSurface(tester);
      const trialAnnual = SubscriptionPlanUiModel(
        id: 'test.annual.trial',
        period: SubscriptionPeriod.annual,
        localizedPrice: 'USD 49.99',
        freeTrialDays: 7,
      );
      final c = _ctx(
        gateway: FakePlusGateway(
          offering: const SubscriptionOfferingUiModel(plans: [trialAnnual]),
        ),
      );
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      expect(
        find.text(en('plusTrialThenAnnually', {
          'days': '7',
          'price': 'USD 49.99',
        })),
        findsWidgets,
      );
      expect(find.text(en('plusStartTrial')), findsOneWidget);
    });
  });

  group('purchase review', () {
    testWidgets('states what will be charged and hands over to the store',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      expect(find.text(en('plusReviewTitle')), findsOneWidget);
      // The full amount of one billing period, once, and how often it renews.
      expect(find.text(en('plusReviewCharged')), findsOneWidget);
      expect(find.text('USD 49.99'), findsOneWidget);
      expect(find.text(en('plusRenewsAnnually')), findsOneWidget);
      expect(find.text(en('plusReviewStepNoCard')), findsOneWidget);
      // One primary action; the purchase has not started.
      expect(find.text(en('plusContinue')), findsOneWidget);
      expect(c.gateway.purchaseCalls, 0);
      expect(find.textContaining('AED'), findsNothing);
      for (final word in ['PayPal', 'Apple Pay', 'Google Pay', 'CVV']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('does not turn into another settings dashboard',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      // The old "what happens next" checklist is gone: the secure checkout
      // step says it once, in its own place.
      expect(find.text(en('plusPaymentDetailsTitle')), findsNothing);
      expect(find.text(en('plusManageSubscription')), findsNothing);
      expect(find.text(en('plusRowHistory')), findsNothing);
    });

    testWidgets('Continue opens secure checkout, and Not now backs out',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      expect(find.text(en('plusCheckoutTitle')), findsOneWidget);
      expect(find.text(en('plusCheckoutBody', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('plusCheckoutNoteGoogle')), findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);
      // Nothing has started, and nothing is asked for here.
      expect(c.gateway.purchaseCalls, 0);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(en('notNow')));
      await tester.pumpAndSettle();

      expect(find.text(en('plusCheckoutTitle')), findsNothing);
      expect(find.text(en('plusReviewTitle')), findsOneWidget);
      expect(c.gateway.purchaseCalls, 0, reason: 'Not now starts nothing');
    });

    testWidgets('secure checkout speaks about Apple on the App Store',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      c.vm.debugSetStore(PlusStore.appStore);
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      expect(find.text(en('plusCheckoutBody', {'store': 'App Store'})),
          findsOneWidget);
      expect(find.text(en('plusCheckoutNoteApple')), findsOneWidget);
      expect(find.text(en('plusCheckoutNoteGoogle')), findsNothing);
      expect(find.text(en('plusContinueToStore', {'store': 'App Store'})),
          findsOneWidget);
    });

    testWidgets('secure checkout says it is a preview while previewing',
        (tester) async {
      _tallSurface(tester);
      final c = _ctx(
        gateway: FakePlusGateway(
          offering: const SubscriptionOfferingUiModel(
            plans: [testMonthlyPlan, testAnnualPlan],
            preselectedPeriod: SubscriptionPeriod.annual,
            isPreview: true,
          ),
        ),
      );
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      // The review already carries the banner; the checkout sheet adds its own.
      expect(find.text(en('plusPreviewNotice')), findsWidgets);
      expect(find.text(en('plusCheckoutTitle')), findsOneWidget);
    });

    testWidgets('links the legal pages', (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en('termsConditions')));
      await tester.pumpAndSettle();
      expect(find.text('terms-stub'), findsOneWidget);
    });
  });

  group('purchase journey', () {
    testWidgets('review to success lands on My Plan with Plus active',
        // Test name kept: the destination is now titled Subscription & Billing.
        (tester) async {
      _tallSurface(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      // Paywall -> review -> secure checkout -> the purchase.
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('plusContinue')));
      await tester.pumpAndSettle();
      expect(c.gateway.purchaseCalls, 0, reason: 'checkout comes first');
      await tester.tap(
        find.text(en('plusContinueToStore', {'store': 'Google Play'})),
      );

      // From here on the progress screen is on show and its spinners animate
      // for as long as the purchase runs, so `pumpAndSettle` (which waits for
      // the tree to stop asking for frames) must not be used. Each wait below
      // is for one specific widget, in bounded 100 ms frames.
      final progressTitle = find.text(en('plusProgressTitle'));
      await pumpUntilFound(tester, progressTitle);

      // In progress: the screen shows the steps and cannot start a second one.
      expect(progressTitle, findsOneWidget);
      expect(c.gateway.purchaseCalls, 1, reason: 'one purchase was started');
      expect(c.vm.status, SubscriptionStatus.free,
          reason: 'nothing is unlocked while the purchase is running');

      final controller = c.gateway.purchaseController!;
      controller.add(const PurchaseUpdate(PurchasePhase.waitingForStore));
      final waitingForStore = find.text(
        en('plusStepWaitingStore', {'store': 'Google Play'}),
      );
      await pumpUntilFound(tester, waitingForStore);
      expect(waitingForStore, findsOneWidget);
      // Still Free, and no success shown prematurely.
      expect(find.text(en('plusSuccessTitle')), findsNothing);
      expect(c.vm.status, SubscriptionStatus.free);

      controller.add(PurchaseUpdate(
        PurchasePhase.success,
        entitlement: testActive(),
      ));
      // Not awaited: the test body runs in a fake-async zone, so only
      // pumping advances the stream.
      unawaited(controller.close());
      final successTitle = find.text(en('plusSuccessTitle'));
      await pumpUntilFound(tester, successTitle);
      // Let the one-shot success pop-in finish.
      await tester.pump(const Duration(milliseconds: 600));

      expect(successTitle, findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.active);

      // Continue goes to Profile and then opens Subscription & Billing from a
      // post-frame callback, so wait for that screen itself rather than for an
      // idle tree.
      await tester.tap(find.text(en('plusContinue')));
      final billingTitle = find.text(en('plusBillingTitle'));
      await pumpUntilFound(tester, billingTitle);
      await tester.pump(const Duration(milliseconds: 600));

      expect(billingTitle, findsOneWidget);
      expect(find.text(en('plusStatusActive')), findsWidgets);
      // Plus is shown as active, billed through the store that sold it.
      expect(
        find.text(en('plusBilledThrough', {'store': 'Google Play'})),
        findsWidgets,
      );
    });

    final results =
        <PurchasePhase, ({List<String> shown, List<String> hidden})>{
      PurchasePhase.success: (
        shown: [en('plusSuccessTitle'), en('plusContinue')],
        hidden: [en('plusTryAgain')],
      ),
      PurchasePhase.pending: (
        shown: [
          en('plusPendingTitle'),
          en('plusPendingPointLeave'),
          en('plusPendingPointUpdate'),
          en('done'),
        ],
        hidden: [en('plusSuccessTitle'), en('plusTryAgain')],
      ),
      PurchasePhase.cancelled: (
        shown: [
          en('plusCancelledTitle'),
          en('plusBackToPlans'),
          en('plusTryAgain'),
        ],
        hidden: [en('plusSuccessTitle'), en('plusContactSupport')],
      ),
      PurchasePhase.storeProblem: (
        shown: [en('plusStoreProblemTitle'), en('plusTryAgain')],
        hidden: [en('plusSuccessTitle'), en('plusContactSupport')],
      ),
      PurchasePhase.networkProblem: (
        shown: [en('plusNetworkTitle'), en('plusTryAgain')],
        hidden: [en('plusSuccessTitle'), en('plusContactSupport')],
      ),
      PurchasePhase.verificationFailed: (
        shown: [
          en('plusVerificationTitle'),
          en('plusTryAgain'),
          en('plusContactSupport'),
        ],
        hidden: [en('plusSuccessTitle')],
      ),
      PurchasePhase.unknownFailure: (
        shown: [
          en('plusUnknownTitle'),
          en('plusTryAgain'),
          en('plusContactSupport'),
        ],
        hidden: [en('plusSuccessTitle')],
      ),
    };

    for (final entry in results.entries) {
      testWidgets('${entry.key.name} has its own result screen',
          (tester) async {
        final c = _ctx();
        c.vm.debugShowPurchasePhase(entry.key);
        await tester
            .pumpWidget(plusTestApp(c.vm, initialLocation: '/plus/purchase'));
        await tester.pump(const Duration(milliseconds: 600));

        for (final text in entry.value.shown) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        for (final text in entry.value.hidden) {
          expect(find.text(text), findsNothing, reason: text);
        }
        // Raw errors are never shown.
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);
      });
    }

    testWidgets('every progress step is shown while a purchase runs',
        (tester) async {
      final c = _ctx();
      c.vm.debugShowPurchasePhase(PurchasePhase.verifying);
      await tester
          .pumpWidget(plusTestApp(c.vm, initialLocation: '/plus/purchase'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(en('plusStepInitiating')), findsOneWidget);
      expect(
        find.text(en('plusStepWaitingStore', {'store': 'Google Play'})),
        findsOneWidget,
      );
      expect(find.text(en('plusStepVerifying')), findsOneWidget);
      expect(find.text(en('plusStepFinalizing')), findsOneWidget);
      // No result actions while a purchase is running.
      expect(find.text(en('plusTryAgain')), findsNothing);
      expect(find.text(en('plusContinue')), findsNothing);
    });
  });

  group('restore', () {
    testWidgets('explains itself, then reports nothing to restore',
        (tester) async {
      final c = _ctx();
      await tester
          .pumpWidget(plusTestApp(c.vm, initialLocation: '/plus/restore'));
      await tester.pumpAndSettle();

      expect(find.text(en('plusRestoreTitle')), findsOneWidget);
      expect(find.text(en('plusRestoreNoChargeTitle')), findsOneWidget);

      await tester.tap(
        find.widgetWithText(ElevatedButton, en('plusRestorePurchases')),
      );
      await tester.pump();
      expect(find.text(en('plusRestoring', {'store': 'Google Play'})),
          findsOneWidget);

      c.gateway.restoreCompleter!
          .complete(const RestoreResult(RestorePhase.nothingFound));
      await tester.pumpAndSettle();

      expect(find.text(en('plusRestoreNothingTitle')), findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.free);
    });

    testWidgets('a restored subscription is applied from the source only',
        (tester) async {
      final c = _ctx();
      await tester
          .pumpWidget(plusTestApp(c.vm, initialLocation: '/plus/restore'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(ElevatedButton, en('plusRestorePurchases')),
      );
      await tester.pump();
      c.gateway.restoreCompleter!.complete(
        RestoreResult(RestorePhase.restored, entitlement: testActive()),
      );
      await tester.pumpAndSettle();

      expect(find.text(en('plusRestoreSuccessTitle')), findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.active);
    });

    final results = <RestorePhase, List<String>>{
      RestorePhase.nothingFound: [en('plusRestoreNothingTitle')],
      RestorePhase.conflict: [
        en('plusRestoreConflictTitle'),
        en('plusContactSupport'),
      ],
      RestorePhase.failed: [en('plusRestoreFailedTitle'), en('plusTryAgain')],
      RestorePhase.unavailable: [en('plusRestoreUnavailableTitle')],
      RestorePhase.restored: [en('plusRestoreSuccessTitle')],
    };
    for (final entry in results.entries) {
      testWidgets('${entry.key.name} has its own screen', (tester) async {
        final c = _ctx();
        c.vm.debugShowRestorePhase(entry.key);
        await tester.pumpWidget(
          plusTestApp(c.vm, initialLocation: '/plus/restore'),
        );
        await tester.pumpAndSettle();

        for (final text in entry.value) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
      });
    }
  });

  group('profile tile summary', () {
    Future<String> subtitle(
      WidgetTester tester,
      SubscriptionUiState state, {
      Locale locale = const Locale('en'),
    }) async {
      var result = '';
      await tester.pumpWidget(_sheetApp(
        Builder(builder: (context) {
          result = plusProfileTileSubtitle(
            context,
            AppLocalizations.of(context),
            state,
          );
          return const SizedBox.shrink();
        }),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('Free invites an upgrade', (tester) async {
      expect(
        await subtitle(tester, const SubscriptionUiState.free()),
        '${en('freePlan')} • ${en('plusUpgradeToPlus')}',
      );
    });

    testWidgets('Active shows status and billing period', (tester) async {
      expect(
        await subtitle(tester, testActive()),
        '${en('plusPlanShort')} • ${en('plusStatusActive')} • '
        '${en('plusPeriodAnnual')}',
      );
    });

    testWidgets('Trial shows when it ends', (tester) async {
      final text = await subtitle(tester, testState(SubscriptionStatus.trial));
      expect(
        text,
        '${en('plusPlanShort')} • ${en('plusStatusTrial')} • '
        '${en('plusTileEnds', {'date': 'Jan 8, 2027'})}',
      );
    });

    testWidgets('Cancelled-active says Plus is active until the date',
        (tester) async {
      final text = await subtitle(
        tester,
        testState(SubscriptionStatus.cancelledActive),
      );
      expect(
        text,
        '${en('plusPlanShort')} • '
        '${en('plusTileActiveUntil', {'date': 'Mar 1, 2027'})}',
      );
      expect(text, isNot(contains(en('plusStatusExpired'))));
    });

    testWidgets('Grace and billing issue both say there is a payment issue',
        (tester) async {
      for (final status in [
        SubscriptionStatus.gracePeriod,
        SubscriptionStatus.billingIssue,
      ]) {
        expect(
          await subtitle(tester, testState(status)),
          '${en('plusPlanShort')} • ${en('plusStatusBillingIssue')}',
        );
      }
    });

    testWidgets('Expired says so', (tester) async {
      expect(
        await subtitle(tester, testState(SubscriptionStatus.expired)),
        '${en('plusPlanShort')} • ${en('plusStatusExpired')}',
      );
    });

    testWidgets('every state is summarised in Arabic with no missing key',
        (tester) async {
      for (final status in SubscriptionStatus.values) {
        final text = await subtitle(
          tester,
          testState(status),
          locale: const Locale('ar'),
        );
        expect(text, isNotEmpty, reason: status.name);
        expect(text, isNot(contains('not found')), reason: status.name);
        expect(text, contains('•'), reason: status.name);
      }
    });
  });

  group('language, theme and size', () {
    // Every Subscription & Billing screen in the states that stress it most.
    // The hub and the payment screens are listed for every status.
    final screens = <String, ({String route, SubscriptionStatus status})>{
      'paywall': (route: '/plus', status: SubscriptionStatus.free),
      for (final status in SubscriptionStatus.values) ...{
        'billing (${status.name})': (
          route: '/subscription-billing',
          status: status,
        ),
        'payment methods (${status.name})': (
          route: '/subscription-billing/payment-methods',
          status: status,
        ),
      },
      // The payment-methods family: each dedicated screen for Free, a healthy
      // subscriber and a payment issue.
      for (final status in [
        SubscriptionStatus.free,
        SubscriptionStatus.active,
        SubscriptionStatus.billingIssue,
      ]) ...{
        'payment details (${status.name})': (
          route: '/subscription-billing/payment-details',
          status: status,
        ),
        'add payment method (${status.name})': (
          route: '/subscription-billing/payment-methods/add',
          status: status,
        ),
        'manage payment methods (${status.name})': (
          route: '/subscription-billing/payment-methods/manage',
          status: status,
        ),
        'backup payment methods (${status.name})': (
          route: '/subscription-billing/payment-methods/backup',
          status: status,
        ),
        'manage billing (${status.name})': (
          route: '/subscription-billing/payment-methods/billing',
          status: status,
        ),
        'payment method help (${status.name})': (
          route: '/subscription-billing/payment-methods/help',
          status: status,
        ),
      },
      for (final status in [
        SubscriptionStatus.active,
        SubscriptionStatus.trial,
        SubscriptionStatus.cancelledActive,
        SubscriptionStatus.gracePeriod,
        SubscriptionStatus.billingIssue,
      ])
        'manage (${status.name})': (
          route: '/subscription-billing/manage',
          status: status,
        ),
      'manage (expired, no subscription)': (
        route: '/subscription-billing/manage',
        status: SubscriptionStatus.expired,
      ),
      'change period (active)': (
        route: '/subscription-billing/change-period',
        status: SubscriptionStatus.active,
      ),
      'change period (unavailable)': (
        route: '/subscription-billing/change-period',
        status: SubscriptionStatus.cancelledActive,
      ),
      'history (active)': (
        route: '/subscription-billing/history',
        status: SubscriptionStatus.active,
      ),
      'history (free)': (
        route: '/subscription-billing/history',
        status: SubscriptionStatus.free,
      ),
      'help': (
        route: '/subscription-billing/help',
        status: SubscriptionStatus.free,
      ),
      'legal': (
        route: '/subscription-billing/legal',
        status: SubscriptionStatus.free,
      ),
      'usage': (
        route: '/subscription-billing/usage',
        status: SubscriptionStatus.active,
      ),
      'restore': (route: '/plus/restore', status: SubscriptionStatus.free),
    };

    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders in Arabic right-to-left',
          (tester) async {
        _tallSurface(tester);
        final c = _ctx();
        c.vm.applyEntitlement(testState(entry.value.status));
        await tester.pumpWidget(
          plusTestApp(c.vm,
              initialLocation: entry.value.route, locale: const Locale('ar')),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold).first);
        expect(Directionality.of(context), TextDirection.rtl);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('not found'), findsNothing,
            reason: 'a key is missing in Arabic');
      });

      testWidgets('${entry.key} renders in dark mode', (tester) async {
        _tallSurface(tester);
        final c = _ctx();
        c.vm.applyEntitlement(testState(entry.value.status));
        await tester.pumpWidget(
          plusTestApp(c.vm,
              initialLocation: entry.value.route, themeMode: ThemeMode.dark),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('not found'), findsNothing);
      });

      testWidgets('${entry.key} fits a small phone with large text',
          (tester) async {
        _smallPhone(tester);
        final c = _ctx();
        c.vm.applyEntitlement(testState(entry.value.status));
        await tester.pumpWidget(
          plusTestApp(c.vm, initialLocation: entry.value.route, textScale: 1.6),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key} fits a small phone in Arabic', (tester) async {
        _smallPhone(tester);
        final c = _ctx();
        c.vm.applyEntitlement(testState(entry.value.status));
        await tester.pumpWidget(
          plusTestApp(
            c.vm,
            initialLocation: entry.value.route,
            locale: const Locale('ar'),
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the pinned purchase action is reachable on a small phone',
        (tester) async {
      _smallPhone(tester);
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm, textScale: 1.3));
      await tester.pumpAndSettle();

      final button = find.text(en('plusContinue'));
      expect(button, findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.bottom, lessThanOrEqualTo(568));
      expect(rect.top, greaterThanOrEqualTo(0));
    });

    testWidgets('result screens keep their actions on screen at large text',
        (tester) async {
      _smallPhone(tester);
      final c = _ctx();
      c.vm.debugShowPurchasePhase(PurchasePhase.verificationFailed);
      await tester.pumpWidget(
        plusTestApp(c.vm, initialLocation: '/plus/purchase', textScale: 1.6),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.text(en('plusTryAgain')));
      expect(rect.bottom, lessThanOrEqualTo(568));
    });
  });

  group('reusable upgrade sheet', () {
    Future<bool?> openSheet(WidgetTester tester, String tapLabel) async {
      bool? result;
      await tester.pumpWidget(_sheetApp(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: _sheetTrigger,
              onPressed: () async {
                result = await UpgradeToPlusSheet.show(
                  context,
                  title: 'Feature title',
                  message: 'A concise explanation.',
                );
              },
              child: const Text('Show sheet'),
            ),
          ),
        ),
      )));
      // The app's localization delegate loads asynchronously, and until it has
      // `Localizations` builds nothing, so the host button does not exist yet.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_sheetTrigger));
      await tester.pumpAndSettle();

      expect(find.text('Feature title'), findsOneWidget);
      expect(find.text('A concise explanation.'), findsOneWidget);
      expect(find.text(en('plusHighlightRecords')), findsOneWidget);
      expect(find.text(en('plusUpgradeToPlus')), findsOneWidget);
      expect(find.text(en('notNow')), findsOneWidget);

      await tester.tap(find.text(tapLabel));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('Upgrade to Plus resolves true', (tester) async {
      expect(await openSheet(tester, en('plusUpgradeToPlus')), isTrue);
    });

    testWidgets('Not Now resolves false', (tester) async {
      expect(await openSheet(tester, en('notNow')), isFalse);
    });
  });

  group('debug preview chooser', () {
    testWidgets('can put the screens into any plan state', (tester) async {
      final c = _ctx();
      await tester.pumpWidget(plusTestApp(c.vm));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Plus preview (debug only)'), findsOneWidget);

      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();

      expect(c.vm.status, SubscriptionStatus.active);
      expect(c.vm.entitlement.isPreview, isTrue);
    });
  });
}
