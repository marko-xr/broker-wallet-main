import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plus_test_support.dart';

const _hub = '/subscription-billing';
const _manage = '/subscription-billing/manage';
const _changePeriod = '/subscription-billing/change-period';
const _paymentMethods = '/subscription-billing/payment-methods';

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Details, instructions and legal text that belong on the screens below the
/// hub, never on the hub itself.
List<String> _detailsThatBelongElsewhere() => [
      en('plusDetailRenewal'),
      en('plusDetailPrice'),
      en('plusDetailNextCharge'),
      en('plusManageStepAndroid1'),
      en('plusHistoryStepAndroid2'),
      en('plusSubscriptionInfoTitle'),
      en('plusDeleteAccountNoteTitle'),
      en('plusPaySafetyNote'),
    ];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => setUpPlusTestAssets(binding));
  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('hub: Subscription & Billing', () {
    // What each state must show and must not show. Texts are exact English
    // strings from the ARB file, so a wording change flows through.
    final expectations =
        <SubscriptionStatus, ({List<String> shown, List<String> hidden})>{
      SubscriptionStatus.free: (
        shown: [
          en('freePlan'),
          en('plusFreeHeroBody'),
          en('plusUpgradeToPlus'),
          en('plusRestorePurchases'),
          en('plusUsageTitle'),
          en('plusRowHelpTitle'),
          en('plusLegalTitle'),
        ],
        hidden: [
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
          en('plusRowHistory'),
          en('plusFixPayment'),
          en('plusIssueTitle'),
          en('plusViewPlans'),
          en('plusResubscribe'),
          en('plusRenewalOn'),
          en('plusStatusActive'),
        ],
      ),
      SubscriptionStatus.active: (
        shown: [
          en('plusBrandName'),
          en('plusStatusActive'),
          en('plusPeriodPriceLine', {
            'period': en('plusPeriodAnnual'),
            'price': 'USD 49.99 / year',
          }),
          en('plusHeroRenewsOn', {'date': 'January 15, 2027'}),
          en('plusBilledThrough', {'store': 'Google Play'}),
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
          en('plusManagedByGoogle'),
          en('plusRowHistory'),
          en('plusRestorePurchases'),
          en('plusUsageTitle'),
          en('plusRowHelpTitle'),
          en('plusLegalTitle'),
        ],
        hidden: [
          en('plusUpgradeToPlus'),
          en('plusViewPlans'),
          en('plusResubscribe'),
          en('plusFixPayment'),
          en('plusIssueTitle'),
          en('plusStatusExpired'),
        ],
      ),
      SubscriptionStatus.trial: (
        shown: [
          en('plusStatusTrial'),
          en('plusHeroTrialEnds', {'date': 'January 8, 2027'}),
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
          en('plusRowHistory'),
        ],
        hidden: [
          en('plusUpgradeToPlus'),
          en('plusViewPlans'),
          en('plusResubscribe'),
          en('plusIssueTitle'),
        ],
      ),
      SubscriptionStatus.cancelledActive: (
        shown: [
          en('plusStatusActive'),
          en('plusStatusCancelledActive'),
          en('plusHeroActiveUntil', {'date': 'March 1, 2027'}),
          en('plusResubscribe'),
          en('plusManageSubscription'),
          en('plusRowHistory'),
          en('plusRestorePurchases'),
        ],
        hidden: [
          en('plusStatusExpired'),
          // Renewal is off, so there is no payment method to fix.
          en('plusPaymentMethodsTitle'),
          en('plusFixPayment'),
          en('plusIssueTitle'),
          en('plusUpgradeToPlus'),
          en('plusViewPlans'),
        ],
      ),
      SubscriptionStatus.gracePeriod: (
        shown: [
          en('plusStatusGracePeriod'),
          en('plusIssueTitle'),
          en('plusIssueGraceBody', {
            'store': 'Google Play',
            'date': 'February 5, 2027',
          }),
          en('plusFixPayment'),
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
        ],
        hidden: [
          en('plusStatusExpired'),
          en('plusViewPlans'),
          en('plusUpgradeToPlus'),
          en('plusResubscribe'),
        ],
      ),
      SubscriptionStatus.billingIssue: (
        shown: [
          en('plusStatusBillingIssue'),
          en('plusIssueTitle'),
          en('plusIssueBody', {'store': 'Google Play'}),
          en('plusFixPayment'),
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
        ],
        hidden: [
          en('plusStatusExpired'),
          en('plusViewPlans'),
          en('plusUpgradeToPlus'),
          en('plusResubscribe'),
        ],
      ),
      SubscriptionStatus.expired: (
        shown: [
          en('plusStatusExpired'),
          en('plusHeroExpiredOn', {'date': 'December 1, 2026'}),
          en('plusViewPlans'),
          en('plusRowHistory'),
          en('plusRestorePurchases'),
        ],
        hidden: [
          en('plusManageSubscription'),
          en('plusPaymentMethodsTitle'),
          en('plusFixPayment'),
          en('plusResubscribe'),
          en('plusUpgradeToPlus'),
          en('plusRenewalOn'),
          en('plusBilledThrough', {'store': 'Google Play'}),
        ],
      ),
    };

    for (final entry in expectations.entries) {
      testWidgets('${entry.key.name} is presented correctly', (tester) async {
        await openPlusScreen(tester, _hub, status: entry.key);

        expect(find.text(en('plusBillingTitle')), findsOneWidget);
        for (final text in entry.value.shown) {
          expect(find.text(text), findsWidgets, reason: 'missing: $text');
        }
        for (final text in entry.value.hidden) {
          expect(find.text(text), findsNothing, reason: 'unexpected: $text');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key.name} stays a hub, not a wall of detail',
          (tester) async {
        await openPlusScreen(tester, _hub, status: entry.key);

        for (final text in _detailsThatBelongElsewhere()) {
          expect(find.text(text), findsNothing, reason: 'on the hub: $text');
        }
        // One summary and at most seven destinations, whatever the state.
        expect(find.byType(PlusPlanSummaryCard), findsOneWidget);
        expect(find.byType(PlusActionRow), findsAtLeastNWidgets(4));
        expect(
          tester.widgetList(find.byType(PlusActionRow)).length,
          lessThanOrEqualTo(7),
        );
      });
    }

    testWidgets('Free is an intentional plan, not missing data',
        (tester) async {
      await openPlusScreen(tester, _hub);

      expect(find.text(en('freePlan')), findsWidgets);
      expect(find.text(en('plusFreeHeroBody')), findsOneWidget);
      // One obvious primary action, with Restore as the quiet second one.
      expect(
        find.widgetWithText(ElevatedButton, en('plusUpgradeToPlus')),
        findsOneWidget,
      );
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('2027'), findsNothing);
    });

    testWidgets('an active subscriber sees the plan, status and store at once',
        (tester) async {
      await openPlusScreen(tester, _hub, status: SubscriptionStatus.active);

      final summary = find.byType(PlusPlanSummaryCard);
      for (final text in [
        en('plusBrandName'),
        en('plusStatusActive'),
        en('plusBilledThrough', {'store': 'Google Play'}),
        en('plusHeroRenewsOn', {'date': 'January 15, 2027'}),
      ]) {
        expect(
          find.descendant(of: summary, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('the App Store is named when it bills the subscription',
        (tester) async {
      await openPlusScreen(
        tester,
        _hub,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );

      expect(find.text(en('plusBilledThrough', {'store': 'App Store'})),
          findsOneWidget);
      expect(find.text(en('plusManagedByApple')), findsOneWidget);
      expect(find.text(en('plusManagedByGoogle')), findsNothing);
      expect(find.textContaining('Google Play'), findsNothing);
    });

    testWidgets('no price or date is invented when none is supplied',
        (tester) async {
      tallSurface(tester);
      final c = plusCtx();
      c.vm.applyEntitlement(
        const SubscriptionUiState(
          status: SubscriptionStatus.active,
          store: PlusStore.googlePlay,
        ),
      );
      await tester.pumpWidget(plusTestApp(c.vm, initialLocation: _hub));
      await tester.pumpAndSettle();

      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('2027'), findsNothing);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.text(en('plusBilledThrough', {'store': 'Google Play'})),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pending purchase is shown without unlocking anything',
        (tester) async {
      tallSurface(tester);
      final c = plusCtx();
      c.vm.debugShowPurchasePhase(PurchasePhase.pending);
      await tester.pumpWidget(plusTestApp(c.vm, initialLocation: _hub));
      await tester.pumpAndSettle();

      expect(find.text(en('plusPendingBannerTitle')), findsOneWidget);
      expect(find.text(en('freePlan')), findsWidgets);
      expect(c.vm.status, SubscriptionStatus.free);
    });

    testWidgets('the first screenful answers "what do I have?"',
        (tester) async {
      // Free: the upgrade is on the first screen of a small phone.
      await openPlusScreen(tester, _hub, small: true);
      expect(
        tester.getRect(find.text(en('plusUpgradeToPlus'))).bottom,
        lessThanOrEqualTo(568),
      );

      // Active: the status is on the first screen, and the first destination
      // starts on it.
      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _hub,
        status: SubscriptionStatus.active,
        small: true,
      );
      expect(
        tester.getRect(find.text(en('plusStatusActive'))).bottom,
        lessThanOrEqualTo(568),
      );
      expect(
        tester.getRect(find.text(en('plusManageSubscription'))).top,
        lessThan(540),
      );
    });

    testWidgets('a billing issue leads with the fix, calmly', (tester) async {
      await openPlusScreen(tester, _hub,
          status: SubscriptionStatus.billingIssue);

      expect(
        find.widgetWithText(ElevatedButton, en('plusFixPayment')),
        findsOneWidget,
      );
      expect(find.text(en('plusStatusExpired')), findsNothing);
      expect(find.text(en('plusViewPlans')), findsNothing);
      // The whole screen is not alarm-coloured: only one tinted notice.
      expect(find.text(en('plusIssueTitle')), findsOneWidget);
    });
  });

  group('hub: navigation', () {
    // Each destination and a text that exists only on it.
    final destinations = <String, ({String row, String landed})>{
      'Manage subscription': (
        row: en('plusManageSubscription'),
        landed: en('plusManageDetailsLabel'),
      ),
      'Payment methods': (
        row: en('plusPaymentMethodsTitle'),
        landed: en('plusPmIntroGoogle'),
      ),
      'Billing history & receipts': (
        row: en('plusRowHistory'),
        landed: en('plusHistoryHowTo'),
      ),
      'Restore purchases': (
        row: en('plusRestorePurchases'),
        landed: en('plusRestoreTitle'),
      ),
      'Plan usage': (
        row: en('plusUsageTitle'),
        landed: en('plusUsagePlusBody'),
      ),
      'Subscription help': (
        row: en('plusRowHelpTitle'),
        landed: en('plusHelpIntro'),
      ),
      'Legal': (
        row: en('plusLegalTitle'),
        landed: en('plusLegalDocuments'),
      ),
    };

    for (final entry in destinations.entries) {
      testWidgets('${entry.key} opens its own screen and back returns',
          (tester) async {
        await openPlusScreen(tester, _hub, status: SubscriptionStatus.active);

        await _tap(tester, entry.value.row);
        expect(find.text(entry.value.landed), findsOneWidget,
            reason: 'did not reach ${entry.key}');

        // The app-bar arrow returns to the hub, not to Profile.
        await tester.tap(find.byType(BackArrowButton));
        await tester.pumpAndSettle();
        expect(find.text(en('plusBillingTitle')), findsOneWidget);
        expect(find.text(entry.value.landed), findsNothing);
      });
    }

    testWidgets('Android system back also returns to the hub', (tester) async {
      await openPlusScreen(tester, _hub, status: SubscriptionStatus.active);

      await _tap(tester, en('plusManageSubscription'));
      expect(find.text(en('plusManageDetailsLabel')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(en('plusManageDetailsLabel')), findsNothing);
      expect(find.text(en('plusBrandName')), findsWidgets);
      expect(find.text(en('plusBillingTitle')), findsOneWidget);
    });

    testWidgets('a free user reaches the plans from the hub', (tester) async {
      final c = await openPlusScreen(tester, _hub);

      await _tap(tester, en('plusUpgradeToPlus'));

      expect(find.text(en('plusChoosePlanTitle')), findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.free);
    });

    testWidgets('an expired subscriber reaches the plans from the hub',
        (tester) async {
      await openPlusScreen(tester, _hub, status: SubscriptionStatus.expired);

      await _tap(tester, en('plusViewPlans'));

      expect(find.text(en('plusChoosePlanTitle')), findsOneWidget);
    });

    testWidgets('Restore stays non-authoritative from the hub', (tester) async {
      final c = await openPlusScreen(tester, _hub);

      await _tap(tester, en('plusRestorePurchases'));
      await tester.tap(
        find.widgetWithText(ElevatedButton, en('plusRestorePurchases')),
      );
      await tester.pump();
      c.gateway.restoreCompleter!
          .complete(const RestoreResult(RestorePhase.restored));
      await tester.pumpAndSettle();

      // "Restored" without an entitlement from the source unlocks nothing.
      expect(find.text(en('plusRestoreNothingTitle')), findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.free);
    });
  });

  group('legacy routes', () {
    testWidgets('the former My Plan path lands on Subscription & Billing',
        (tester) async {
      await openPlusScreen(tester, '/my-plan');
      expect(find.text(en('plusBillingTitle')), findsOneWidget);
    });

    testWidgets('the former subscription path lands on the paywall',
        (tester) async {
      await openPlusScreen(tester, '/subscription');
      expect(find.text(en('plusChoosePlanTitle')), findsOneWidget);
    });

    testWidgets('the former payment-selection path lands on the paywall',
        (tester) async {
      await openPlusScreen(tester, '/payment-selection/monthly');
      expect(find.text(en('plusChoosePlanTitle')), findsOneWidget);
      // None of the old payment-method choices came back with it.
      for (final word in ['PayPal', 'Apple Pay', 'Google Pay', 'Credit']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  group('manage subscription', () {
    final expectations =
        <SubscriptionStatus, ({List<String> shown, List<String> hidden})>{
      SubscriptionStatus.active: (
        shown: [
          en('plusDetailPlan'),
          en('plusBrandName'),
          en('plusDetailBilling'),
          en('plusPeriodAnnual'),
          en('plusDetailPrice'),
          'USD 49.99 / year',
          en('plusDetailRenewal'),
          en('plusRenewalOn'),
          en('plusDetailRenews'),
          'January 15, 2027',
          en('plusDetailNextCharge'),
          'USD 49.99',
          en('plusDetailStore'),
          'Google Play',
          en('plusChangePeriodRow'),
          en('plusManageInStore', {'store': 'Google Play'}),
          en('plusDeleteAccountNote', {'store': 'Google Play'}),
        ],
        hidden: [
          en('plusResubscribe'),
          en('plusFixPayment'),
          en('plusIssueTitle'),
          en('plusManageNoneTitle'),
        ],
      ),
      SubscriptionStatus.trial: (
        shown: [
          en('plusTrialNoticeTitle'),
          en('plusDetailTrialEnds'),
          'January 8, 2027',
          en('plusDetailAfterTrial'),
          en('plusChangePeriodRow'),
          en('plusManageInStore', {'store': 'Google Play'}),
        ],
        hidden: [en('plusResubscribe'), en('plusFixPayment')],
      ),
      SubscriptionStatus.cancelledActive: (
        shown: [
          en('plusCancelledActiveTitle'),
          en('plusCancelledActiveBody', {'date': 'March 1, 2027'}),
          en('plusRenewalOff'),
          en('plusDetailAccessUntil'),
          'March 1, 2027',
          en('plusResubscribe'),
          en('plusManageInStore', {'store': 'Google Play'}),
        ],
        hidden: [
          en('plusChangePeriodRow'),
          en('plusDetailNextCharge'),
          en('plusRenewalOn'),
          en('plusFixPayment'),
          en('plusStatusExpired'),
        ],
      ),
      SubscriptionStatus.gracePeriod: (
        shown: [
          en('plusIssueTitle'),
          en('plusIssueGraceBody', {
            'store': 'Google Play',
            'date': 'February 5, 2027',
          }),
          en('plusDetailGraceUntil'),
          en('plusFixPayment'),
          en('plusManageInStore', {'store': 'Google Play'}),
        ],
        hidden: [
          en('plusResubscribe'),
          en('plusChangePeriodRow'),
          en('plusStatusExpired'),
        ],
      ),
      SubscriptionStatus.billingIssue: (
        shown: [
          en('plusIssueTitle'),
          en('plusIssueBody', {'store': 'Google Play'}),
          en('plusFixPayment'),
          en('plusManageInStore', {'store': 'Google Play'}),
        ],
        hidden: [
          en('plusResubscribe'),
          en('plusChangePeriodRow'),
          en('plusStatusExpired'),
        ],
      ),
    };

    for (final entry in expectations.entries) {
      testWidgets('${entry.key.name} shows only what applies', (tester) async {
        await openPlusScreen(tester, _manage, status: entry.key);

        for (final text in entry.value.shown) {
          expect(find.text(text), findsWidgets, reason: 'missing: $text');
        }
        for (final text in entry.value.hidden) {
          expect(find.text(text), findsNothing, reason: 'unexpected: $text');
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final status in [
      SubscriptionStatus.free,
      SubscriptionStatus.expired
    ]) {
      testWidgets('${status.name} has no subscription to manage',
          (tester) async {
        await openPlusScreen(tester, _manage, status: status);

        expect(find.text(en('plusManageNoneTitle')), findsOneWidget);
        expect(find.text(en('plusViewPlans')), findsOneWidget);
        expect(find.text(en('plusChangePeriodRow')), findsNothing);
        expect(find.textContaining('Manage in'), findsNothing);
        expect(find.text(en('plusDetailRenewal')), findsNothing);
      });
    }

    testWidgets('Manage in store explains the hand-off and changes nothing',
        (tester) async {
      final c = await openPlusScreen(tester, _manage,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusManageInStore', {'store': 'Google Play'}));

      expect(find.text(en('plusManageTitle', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('plusManageStepAndroid1')), findsOneWidget);
      expect(find.text(en('plusDeleteAccountNoteTitle')), findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);

      await _tap(tester, en('notNow'));
      expect(find.text(en('plusManageTitle', {'store': 'Google Play'})),
          findsNothing);
      expect(c.vm.entitlement, same(before),
          reason: 'opening a hand-off never mutates the subscription');
    });

    testWidgets('Resubscribe is framed as turning renewal back on',
        (tester) async {
      final c = await openPlusScreen(tester, _manage,
          status: SubscriptionStatus.cancelledActive);

      await _tap(tester, en('plusResubscribe'));

      expect(find.text(en('plusResubscribeTitle', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('plusResubscribeHint')), findsOneWidget);
      expect(c.vm.status, SubscriptionStatus.cancelledActive);
    });

    testWidgets('a payment issue leads to Payment methods', (tester) async {
      await openPlusScreen(tester, _manage,
          status: SubscriptionStatus.billingIssue);

      await _tap(tester, en('plusFixPayment'));

      expect(find.text(en('plusPmIntroGoogle')), findsOneWidget);
      expect(find.text(en('plusIssueTitle')), findsOneWidget);
    });

    testWidgets('the App Store names itself in the hand-off', (tester) async {
      await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );

      await _tap(tester, en('plusManageInStore', {'store': 'App Store'}));

      expect(find.text(en('plusManageStepIos1')), findsOneWidget);
      expect(find.text(en('plusManageStepAndroid1')), findsNothing);
      expect(find.text(en('plusContinueToStore', {'store': 'App Store'})),
          findsOneWidget);
    });
  });

  group('change billing period', () {
    Future<void> goto(WidgetTester tester) async {
      await _tap(tester, en('plusChangePeriodRow'));
    }

    ElevatedButton continueButton(WidgetTester tester) => tester.widget(
          find.widgetWithText(ElevatedButton, en('plusContinue')),
        );

    testWidgets('is reached from Manage subscription', (tester) async {
      await openPlusScreen(tester, _manage, status: SubscriptionStatus.active);
      await goto(tester);

      expect(find.text(en('plusChangePeriodOptions')), findsOneWidget);
    });

    testWidgets('shows the current period and the options', (tester) async {
      await openPlusScreen(tester, _changePeriod,
          status: SubscriptionStatus.active);

      expect(
        find.text(
          en('plusChangePeriodCurrent', {'period': en('plusPeriodAnnual')}),
        ),
        findsOneWidget,
      );
      expect(find.text(en('plusPeriodMonthly')), findsOneWidget);
      expect(find.text(en('plusPeriodAnnual')), findsOneWidget);
      expect(find.text(en('plusChangePeriodCurrentBadge')), findsOneWidget);
      expect(
        find.text(en('plusChangePeriodIntro', {'store': 'Google Play'})),
        findsOneWidget,
      );
      expect(
        find.text(en('plusChangePeriodNote', {'store': 'Google Play'})),
        findsOneWidget,
      );
    });

    testWidgets(
        'Continue needs a different period, and the current one '
        'cannot be selected', (tester) async {
      await openPlusScreen(tester, _changePeriod,
          status: SubscriptionStatus.active);
      expect(continueButton(tester).onPressed, isNull);

      await _tap(tester, en('plusPeriodAnnual'));
      expect(continueButton(tester).onPressed, isNull,
          reason: 'the current period is not a change');

      await _tap(tester, en('plusPeriodMonthly'));
      expect(continueButton(tester).onPressed, isNotNull);
    });

    testWidgets('Continue hands over to the store without changing anything',
        (tester) async {
      final c = await openPlusScreen(tester, _changePeriod,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusPeriodMonthly'));
      await _tap(tester, en('plusContinue'));

      expect(find.text(en('plusChangePeriodTitle', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('plusManageStepAndroid1')), findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);

      await _tap(tester, en('notNow'));
      expect(c.vm.entitlement, same(before));
      expect(c.vm.entitlement.period, SubscriptionPeriod.annual);
    });

    testWidgets('prices are the store\'s own, and absent when not supplied',
        (tester) async {
      // With an offering the options carry the supplied amounts.
      await openPlusScreen(tester, _changePeriod,
          status: SubscriptionStatus.active);
      expect(find.text(en('plusBilledMonthly', {'price': 'USD 4.99'})),
          findsOneWidget);
      expect(find.text(en('plusBilledAnnually', {'price': 'USD 49.99'})),
          findsOneWidget);

      // Without one, nothing is invented: the store shows the price.
      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _changePeriod,
        status: SubscriptionStatus.active,
        gateway: FakePlusGateway(
          offering: const SubscriptionOfferingUiModel.unavailable(),
        ),
      );
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('AED'), findsNothing);
      expect(
        find.text(en('plusChangePeriodPriceInStore', {'store': 'Google Play'})),
        findsNWidgets(2),
      );
    });

    for (final status in [
      SubscriptionStatus.cancelledActive,
      SubscriptionStatus.gracePeriod,
      SubscriptionStatus.billingIssue,
      SubscriptionStatus.expired,
      SubscriptionStatus.free,
    ]) {
      testWidgets('is not offered while ${status.name}', (tester) async {
        await openPlusScreen(tester, _changePeriod, status: status);

        expect(
            find.text(en('plusChangePeriodUnavailableTitle')), findsOneWidget);
        expect(find.text(en('plusChangePeriodOptions')), findsNothing);
        expect(find.widgetWithText(ElevatedButton, en('plusContinue')),
            findsNothing);
      });
    }

    testWidgets('speaks about the App Store on iOS', (tester) async {
      await openPlusScreen(
        tester,
        _changePeriod,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );
      await _tap(tester, en('plusPeriodMonthly'));
      await _tap(tester, en('plusContinue'));

      expect(find.text(en('plusChangePeriodTitle', {'store': 'App Store'})),
          findsOneWidget);
      expect(find.text(en('plusManageStepIos1')), findsOneWidget);
    });
  });

  group('billing issue recovery', () {
    for (final status in [
      SubscriptionStatus.gracePeriod,
      SubscriptionStatus.billingIssue,
    ]) {
      testWidgets('${status.name}: hub -> Payment methods -> hand-off',
          (tester) async {
        final c = await openPlusScreen(tester, _hub, status: status);
        final before = c.vm.entitlement;

        // 1. The hub's warning offers the fix.
        await _tap(tester, en('plusFixPayment'));
        // 2. Payment methods opens on the same problem, with the same fix.
        expect(find.text(en('plusPmIntroGoogle')), findsOneWidget);
        expect(find.text(en('plusIssueTitle')), findsOneWidget);
        await _tap(tester, en('plusFixPayment'));
        // 3. The platform hand-off: steps, and Continue to the store.
        expect(find.text(en('plusPayUpdateTitle')), findsWidgets);
        expect(find.text(en('plusPayStepAndroidUpdate')), findsOneWidget);
        expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
            findsOneWidget);
        expect(find.text(en('plusPaySafetyNote')), findsWidgets);

        await _tap(tester, en('notNow'));
        // Nothing was changed, and the subscription is not shown as ended.
        expect(c.vm.entitlement, same(before));
        expect(find.text(en('plusStatusExpired')), findsNothing);
      });
    }

    testWidgets('on iOS the hand-off is guidance with no fake link',
        (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.billingIssue,
        store: PlusStore.appStore,
      );

      await _tap(tester, en('plusFixPayment'));

      expect(find.text(en('plusPayUpdateTitle')), findsWidgets);
      expect(find.text(en('plusPayIntroApple')), findsOneWidget);
      expect(find.text(en('plusPayStepIosPayment')), findsOneWidget);
      expect(find.text(en('plusPayStepIosAdd')), findsOneWidget);
      expect(find.textContaining('Continue to'), findsNothing);
      expect(find.text(en('done')), findsOneWidget);
    });

    testWidgets('a healthy subscription is not shown a payment warning',
        (tester) async {
      await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      expect(find.text(en('plusIssueTitle')), findsNothing);
      expect(find.text(en('plusFixPayment')), findsNothing);
    });
  });
}
