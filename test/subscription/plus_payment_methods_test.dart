import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plus_test_support.dart';

const _hub = '/subscription-billing';
const _paymentMethods = '/subscription-billing/payment-methods';
const _history = '/subscription-billing/history';
const _help = '/subscription-billing/help';
const _legal = '/subscription-billing/legal';
const _usage = '/subscription-billing/usage';

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Words that would mean Broker Wallet is collecting, storing or showing a
/// payment method of its own.
const _paymentWords = [
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
  '••',
  '4242',
];

void _expectNoPaymentForm(WidgetTester tester) {
  for (final word in _paymentWords) {
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => setUpPlusTestAssets(binding));
  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('payment methods: Google Play', () {
    testWidgets('lays out the Google Play structure', (tester) async {
      await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      for (final text in [
        en('plusPaymentMethodsTitle'),
        en('plusStoreGooglePlay'),
        en('plusPmIntroGoogle'),
        en('plusPmSectionPaymentMethods'),
        en('plusPayManageTitle'),
        en('plusManagedByGoogle'),
        en('plusPayAddTitle'),
        en('plusPmAddSubtitleGoogle'),
        en('plusPayBackupTitle'),
        en('plusPmBackupSubtitleGoogle'),
        en('plusPmSectionSubscription'),
        en('plusPmManageSubscription', {'store': 'Google Play'}),
        en('plusPmSubscriptionSubtitle', {'store': 'Google Play'}),
        en('plusPmHelp'),
        en('plusPmHelpSubtitle'),
        en('plusPaySafetyNote'),
      ]) {
        expect(find.text(text), findsWidgets, reason: 'missing: $text');
      }
      for (final text in [
        en('plusPmProviderApple'),
        en('plusPmIntroApple'),
        en('plusPayChangeTitle'),
        en('plusManagedByApple'),
        en('plusPmSectionPaymentShipping'),
        en('plusPmManageSubscription', {'store': 'App Store'}),
      ]) {
        expect(find.text(text), findsNothing, reason: 'unexpected: $text');
      }
    });

    testWidgets('a free user sees payment methods but no subscription row',
        (tester) async {
      await openPlusScreen(tester, _paymentMethods);

      expect(find.text(en('plusPayManageTitle')), findsOneWidget);
      expect(find.text(en('plusPmSectionSubscription')), findsNothing);
      expect(
          find.text(en('plusPmManageSubscription', {'store': 'Google Play'})),
          findsNothing);
      expect(find.text(en('plusIssueTitle')), findsNothing);
    });

    testWidgets('Add payment method explains the hand-off and has no fake link',
        (tester) async {
      final c = await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusPayAddTitle'));

      // The row and the sheet share the title.
      expect(find.text(en('plusPayAddTitle')), findsNWidgets(2));
      expect(find.text(en('plusPayIntroGoogle')), findsOneWidget);
      for (final key in [
        'plusManageStepAndroid1',
        'plusPayStepAndroidMethods',
        'plusPayStepAndroidAdd',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      // No documented link exists for account-level payment methods, so the
      // sheet gives the steps and a plain Done, never a button that pretends.
      expect(find.textContaining('Continue to'), findsNothing);
      expect(find.text(en('done')), findsOneWidget);
      expect(find.text(en('plusPaySafetyNote')), findsWidgets);
      _expectNoPaymentForm(tester);

      await _tap(tester, en('done'));
      expect(find.text(en('plusPayIntroGoogle')), findsNothing);
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('Manage payment methods gives the Google Play steps',
        (tester) async {
      await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      await _tap(tester, en('plusPayManageTitle'));

      expect(find.text(en('plusPayManageTitle')), findsNWidgets(2));
      for (final key in [
        'plusManageStepAndroid1',
        'plusPayStepAndroidMethods',
        'plusPayStepAndroidManage',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('Backup payment methods is hedged to what Google Play offers',
        (tester) async {
      await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      await _tap(tester, en('plusPayBackupTitle'));

      expect(find.text(en('plusPayBackupTitle')), findsNWidgets(2));
      expect(find.text(en('plusPayStepAndroidBackup')), findsOneWidget);
      expect(find.text(en('plusManageStepAndroid2')), findsOneWidget);
    });

    testWidgets('Manage Google Play subscription opens the store hand-off',
        (tester) async {
      final c = await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(
        tester,
        en('plusPmManageSubscription', {'store': 'Google Play'}),
      );

      expect(find.text(en('plusManageTitle', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('Payment method help opens subscription help', (tester) async {
      await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      await _tap(tester, en('plusPmHelp'));

      expect(find.text(en('plusHelpIntro')), findsOneWidget);
    });
  });

  group('payment methods: App Store', () {
    testWidgets('lays out the Apple Account structure', (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );

      for (final text in [
        en('plusPaymentMethodsTitle'),
        en('plusPmProviderApple'),
        en('plusPmIntroApple'),
        en('plusPmSectionPaymentShipping'),
        en('plusPayChangeTitle'),
        en('plusManagedByApple'),
        en('plusPmSectionSubscription'),
        en('plusPmManageSubscription', {'store': 'App Store'}),
        en('plusPmSubscriptionSubtitle', {'store': 'App Store'}),
        en('plusPmHelp'),
        en('plusPaySafetyNote'),
      ]) {
        expect(find.text(text), findsWidgets, reason: 'missing: $text');
      }
      for (final text in [
        en('plusStoreGooglePlay'),
        en('plusPmIntroGoogle'),
        en('plusPayAddTitle'),
        en('plusPayManageTitle'),
        en('plusPayBackupTitle'),
        en('plusPmAddSubtitleGoogle'),
        en('plusPmBackupSubtitleGoogle'),
        en('plusManagedByGoogle'),
      ]) {
        expect(find.text(text), findsNothing, reason: 'unexpected: $text');
      }
      expect(find.textContaining('Google'), findsNothing);
    });

    testWidgets('Add or change payment method is Apple guidance, not a form',
        (tester) async {
      final c = await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );
      final before = c.vm.entitlement;

      await _tap(tester, en('plusPayChangeTitle'));

      expect(find.text(en('plusPayChangeTitle')), findsNWidgets(2));
      expect(find.text(en('plusPayIntroApple')), findsOneWidget);
      for (final key in [
        'plusManageStepIos1',
        'plusPayStepIosPayment',
        'plusPayStepIosAdd',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      expect(find.textContaining('Continue to'), findsNothing);
      expect(find.text(en('done')), findsOneWidget);
      _expectNoPaymentForm(tester);

      await _tap(tester, en('done'));
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('Manage App Store subscription opens the store hand-off',
        (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );

      await _tap(
        tester,
        en('plusPmManageSubscription', {'store': 'App Store'}),
      );

      expect(find.text(en('plusManageTitle', {'store': 'App Store'})),
          findsOneWidget);
      expect(find.text(en('plusManageStepIos1')), findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'App Store'})),
          findsOneWidget);
    });

    testWidgets('the free App Store view still reads as Apple', (tester) async {
      await openPlusScreen(tester, _paymentMethods, store: PlusStore.appStore);

      expect(find.text(en('plusPmProviderApple')), findsOneWidget);
      expect(find.text(en('plusPmIntroApple')), findsOneWidget);
      expect(find.text(en('plusPmSectionSubscription')), findsNothing);
    });
  });

  group('payment safety', () {
    for (final store in [PlusStore.googlePlay, PlusStore.appStore]) {
      for (final status in SubscriptionStatus.values) {
        testWidgets(
            '${storeName(store)} / ${status.name}: no card, expiry, saved '
            'card or provider choice', (tester) async {
          await openPlusScreen(tester, _paymentMethods,
              status: status, store: store);

          _expectNoPaymentForm(tester);
          expect(find.text(en('plusPaySafetyNote')), findsOneWidget);
        });
      }
    }

    testWidgets('every hand-off sheet is explanation only', (tester) async {
      final c = await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.billingIssue,
      );
      final before = c.vm.entitlement;

      for (final row in [
        en('plusPayManageTitle'),
        en('plusPayAddTitle'),
        en('plusPayBackupTitle'),
        en('plusPmManageSubscription', {'store': 'Google Play'}),
        en('plusFixPayment'),
      ]) {
        await _tap(tester, row);
        _expectNoPaymentForm(tester);
        // Every sheet can be dismissed: Not now when it can continue, Done
        // when it is guidance only.
        final notNow = find.text(en('notNow'));
        await _tap(
          tester,
          notNow.evaluate().isNotEmpty ? en('notNow') : en('done'),
        );
      }

      expect(c.vm.entitlement, same(before));
      expect(c.vm.status, SubscriptionStatus.billingIssue);
    });

    testWidgets('no fake entitlement or backend call comes from the hand-offs',
        (tester) async {
      final c = await openPlusScreen(tester, _paymentMethods,
          status: SubscriptionStatus.active);

      await _tap(tester, en('plusPayAddTitle'));
      await _tap(tester, en('done'));

      expect(c.gateway.purchaseCalls, 0);
      expect(c.gateway.restoreCalls, 0);
      expect(c.gateway.loadCalls, lessThanOrEqualTo(1));
    });
  });

  group('billing history & receipts', () {
    testWidgets('Google Play: guidance and an honest empty state',
        (tester) async {
      await openPlusScreen(tester, _history, status: SubscriptionStatus.active);

      for (final text in [
        en('plusRowHistory'),
        en('plusManagedByGoogle'),
        en('plusHistoryIntroGoogle'),
        en('plusHistoryHowTo'),
        en('plusManageStepAndroid1'),
        en('plusHistoryStepAndroid2'),
        en('plusHistoryNothingListed'),
        en('plusHistoryHelp'),
      ]) {
        expect(find.text(text), findsOneWidget, reason: 'missing: $text');
      }
      expect(find.text(en('plusHistoryIntroApple')), findsNothing);
    });

    testWidgets('App Store: guidance and an honest empty state',
        (tester) async {
      await openPlusScreen(
        tester,
        _history,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
      );

      for (final text in [
        en('plusManagedByApple'),
        en('plusHistoryIntroApple'),
        en('plusManageStepIos1'),
        en('plusHistoryStepIos2'),
        en('plusHistoryNothingListed'),
      ]) {
        expect(find.text(text), findsOneWidget, reason: 'missing: $text');
      }
      expect(find.text(en('plusHistoryIntroGoogle')), findsNothing);
      expect(find.text(en('plusHistoryStepAndroid2')), findsNothing);
    });

    for (final status in [
      SubscriptionStatus.free,
      SubscriptionStatus.active,
      SubscriptionStatus.expired,
    ]) {
      testWidgets('${status.name}: no invented transaction, invoice or amount',
          (tester) async {
        await openPlusScreen(tester, _history, status: status);

        for (final word in [
          'USD',
          'AED',
          '2027',
          '2026',
          'Receipt #',
          'Invoice',
          'Order',
          'Transaction',
          '••',
        ]) {
          expect(find.textContaining(word), findsNothing, reason: word);
        }
        // Instructions only: nothing here pretends to open a store page.
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a question about a charge leads to subscription help',
        (tester) async {
      await openPlusScreen(tester, _history, status: SubscriptionStatus.active);

      await _tap(tester, en('plusHistoryHelp'));

      expect(find.text(en('plusHelpIntro')), findsOneWidget);
    });
  });

  group('subscription help', () {
    testWidgets('lists the topics and the way to reach support',
        (tester) async {
      await openPlusScreen(tester, _help);

      for (final text in [
        en('plusRowHelpTitle'),
        en('plusHelpIntro'),
        en('plusHelpBilling'),
        en('plusHelpBillingSubtitle'),
        en('plusHelpPayment'),
        en('plusHelpPaymentSubtitle'),
        en('plusHelpRestore'),
        en('plusHelpRestoreSubtitle'),
        en('plusManageSubscription'),
        en('plusHelpManageSubtitle'),
        en('plusContactSupport'),
        en('plusHelpSupportSubtitle'),
      ]) {
        expect(find.text(text), findsOneWidget, reason: 'missing: $text');
      }
    });

    final topics = <String, ({String row, String landed})>{
      'Billing problem': (
        row: en('plusHelpBilling'),
        landed: en('plusHistoryHowTo'),
      ),
      'Payment method problem': (
        row: en('plusHelpPayment'),
        landed: en('plusPmIntroGoogle'),
      ),
      'Restore purchases problem': (
        row: en('plusHelpRestore'),
        landed: en('plusRestoreTitle'),
      ),
      'Manage subscription': (
        row: en('plusManageSubscription'),
        landed: en('plusManageDetailsLabel'),
      ),
      'Contact support': (
        row: en('plusContactSupport'),
        landed: 'support-stub',
      ),
    };
    for (final entry in topics.entries) {
      testWidgets('${entry.key} goes straight to the screen that helps',
          (tester) async {
        await openPlusScreen(tester, _help, status: SubscriptionStatus.active);

        await _tap(tester, entry.value.row);

        expect(find.text(entry.value.landed), findsOneWidget,
            reason: entry.key);
      });
    }

    testWidgets('invents no phone number, email address or chat',
        (tester) async {
      await openPlusScreen(tester, _help);

      for (final word in ['@', '+971', 'Chat', 'Ticket', 'Call us']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  group('legal', () {
    testWidgets(
        'shows the subscription information and the existing legal '
        'screens', (tester) async {
      await openPlusScreen(tester, _legal);

      expect(find.text(en('plusLegalTitle')), findsOneWidget);
      expect(find.text(en('plusSubscriptionInfoTitle')), findsOneWidget);
      expect(
        find.text(en('plusSubscriptionInfoBody', {'store': 'Google Play'})),
        findsOneWidget,
      );
      expect(find.text(en('termsConditions')), findsOneWidget);
      expect(find.text(en('privacyPolicy')), findsOneWidget);
    });

    testWidgets('the disclosure names the App Store on iOS', (tester) async {
      await openPlusScreen(tester, _legal, store: PlusStore.appStore);

      expect(
        find.text(en('plusSubscriptionInfoBody', {'store': 'App Store'})),
        findsOneWidget,
      );
    });

    testWidgets('Terms and Privacy open the existing legal pages',
        (tester) async {
      await openPlusScreen(tester, _legal);

      await _tap(tester, en('termsConditions'));
      expect(find.text('terms-stub'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tap(tester, en('privacyPolicy'));
      expect(find.text('privacy-stub'), findsOneWidget);
    });
  });

  group('plan usage', () {
    testWidgets('Free explains the limits', (tester) async {
      await openPlusScreen(tester, _usage);

      expect(find.text(en('plusUsageTitle')), findsOneWidget);
      expect(find.text(en('plusUsageFreeBody')), findsOneWidget);
      expect(find.text(en('plusUsagePlusBody')), findsNothing);
    });

    testWidgets('Plus says there are no free-plan limits', (tester) async {
      await openPlusScreen(tester, _usage, status: SubscriptionStatus.active);

      expect(find.text(en('plusUsagePlusBody')), findsOneWidget);
      expect(find.text(en('plusUsageFreeBody')), findsNothing);
    });
  });

  group('management links', () {
    test(
        'subscription actions use the store page unless the source supplies '
        'one', () {
      final supplied = Uri.parse('https://example.test/manage');
      for (final action in [
        PlusManageAction.manage,
        PlusManageAction.changePeriod,
        PlusManageAction.resubscribe,
      ]) {
        expect(plusManagementUri(PlusStore.googlePlay, action)?.host,
            'play.google.com');
        expect(plusManagementUri(PlusStore.appStore, action)?.host,
            'apps.apple.com');
        expect(plusManagementUri(PlusStore.unknown, action), isNull);
        expect(
          plusManagementUri(PlusStore.googlePlay, action, supplied: supplied),
          supplied,
        );
      }
    });

    test('adding, managing and backing up payment methods is guidance only',
        () {
      // There is no documented link to a store account's payment methods, so
      // none is assumed, even when the source supplies a management link.
      final supplied = Uri.parse('https://example.test/manage');
      for (final action in [
        PlusManageAction.addPaymentMethod,
        PlusManageAction.managePaymentMethods,
        PlusManageAction.backupPaymentMethods,
      ]) {
        for (final store in PlusStore.values) {
          expect(plusManagementUri(store, action), isNull,
              reason: '${store.name} / ${action.name}');
          expect(plusManagementUri(store, action, supplied: supplied), isNull,
              reason: '${store.name} / ${action.name} (supplied)');
        }
      }
    });

    test('fixing a payment method opens only the Google Play subscription', () {
      final supplied = Uri.parse('https://example.test/manage');
      const action = PlusManageAction.updatePaymentMethod;

      expect(plusManagementUri(PlusStore.googlePlay, action)?.host,
          'play.google.com');
      expect(
          plusManagementUri(PlusStore.googlePlay, action, supplied: supplied),
          supplied);
      // Apple keeps payment methods in Settings, which no link reaches.
      expect(plusManagementUri(PlusStore.appStore, action), isNull);
      expect(plusManagementUri(PlusStore.appStore, action, supplied: supplied),
          isNull);
      expect(plusManagementUri(PlusStore.unknown, action), isNull);
    });

    test('payment-method actions are recognised as such', () {
      for (final action in PlusManageAction.values) {
        expect(
          action.isPaymentMethodAction,
          const {
            PlusManageAction.addPaymentMethod,
            PlusManageAction.managePaymentMethods,
            PlusManageAction.backupPaymentMethods,
            PlusManageAction.updatePaymentMethod,
          }.contains(action),
          reason: action.name,
        );
      }
    });
  });

  group('English, Arabic and direction', () {
    const routes = [
      _hub,
      '/subscription-billing/manage',
      '/subscription-billing/change-period',
      _paymentMethods,
      _history,
      _help,
      _legal,
      _usage,
    ];

    for (final route in routes) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
            '$route (${locale.languageCode}): no raw placeholder or '
            'missing key', (tester) async {
          await openPlusScreen(
            tester,
            route,
            status: SubscriptionStatus.active,
            store: PlusStore.appStore,
            locale: locale,
          );

          expect(find.textContaining('{'), findsNothing);
          expect(find.textContaining('not found'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('chevrons point away from the start in both directions',
        (tester) async {
      await openPlusScreen(tester, _hub, status: SubscriptionStatus.active);
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _hub,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('Arabic payment methods are fully translated per platform',
        (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      final context = tester.element(find.byType(Scaffold).first);
      expect(Directionality.of(context), TextDirection.rtl);
      for (final text in [
        ar('plusPaymentMethodsTitle'),
        ar('plusPmIntroGoogle'),
        ar('plusPayManageTitle'),
        ar('plusPayAddTitle'),
        ar('plusPayBackupTitle'),
        ar('plusPmManageSubscription', {'store': 'Google Play'}),
        ar('plusPaySafetyNote'),
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.active,
        store: PlusStore.appStore,
        locale: const Locale('ar'),
      );
      for (final text in [
        ar('plusPmProviderApple'),
        ar('plusPmIntroApple'),
        ar('plusPmSectionPaymentShipping'),
        ar('plusPayChangeTitle'),
        ar('plusManagedByApple'),
        ar('plusPmManageSubscription', {'store': 'App Store'}),
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
    });

    testWidgets('Arabic hand-off sheet renders right-to-left', (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.billingIssue,
        locale: const Locale('ar'),
      );

      await _tap(tester, ar('plusFixPayment'));

      expect(find.text(ar('plusPayStepAndroidUpdate')), findsOneWidget);
      expect(find.text(ar('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.textContaining('{'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('small phone and large text', () {
    testWidgets('hand-off sheets stay usable at 1.6x text', (tester) async {
      await openPlusScreen(
        tester,
        _paymentMethods,
        status: SubscriptionStatus.billingIssue,
        small: true,
        textScale: 1.6,
      );

      await tester.ensureVisible(find.text(en('plusPayAddTitle')));
      await _tap(tester, en('plusPayAddTitle'));

      expect(tester.takeException(), isNull);
      expect(find.text(en('plusPayIntroGoogle')), findsOneWidget);
    });

    testWidgets('secure checkout stays usable at 1.6x text', (tester) async {
      // Paywall -> review -> secure checkout: the review needs the plans the
      // paywall loads, so the journey starts there.
      await openPlusScreen(tester, '/plus', small: true, textScale: 1.6);
      await _tap(tester, en('plusContinue'));
      await _tap(tester, en('plusContinue'));

      expect(tester.takeException(), isNull);
      expect(find.text(en('plusCheckoutTitle')), findsOneWidget);
    });
  });
}
