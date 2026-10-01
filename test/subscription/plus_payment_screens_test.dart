import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_payment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plus_test_support.dart';

const _hub = '/subscription-billing';
const _details = '/subscription-billing/payment-details';
const _dash = '/subscription-billing/payment-methods';
const _add = '$_dash/add';
const _manage = '$_dash/manage';
const _backup = '$_dash/backup';
const _billing = '$_dash/billing';
const _help = '$_dash/help';

const _google = PlusStore.googlePlay;
const _apple = PlusStore.appStore;

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextButton, label));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackArrowButton));
  await tester.pumpAndSettle();
}

/// The screen on top is titled [title]. Asserted on the app bar, because a
/// section label or a card can legitimately repeat the title's words further
/// down the same screen.
void _expectTitle(String title) {
  expect(
    find.descendant(of: find.byType(AppBar), matching: find.text(title)),
    findsOneWidget,
    reason: 'the screen on top is not titled "$title"',
  );
}

void _expectAll(Iterable<String> texts, {required bool present}) {
  for (final text in texts) {
    expect(
      find.text(text),
      present ? findsWidgets : findsNothing,
      reason: present ? 'missing: $text' : 'unexpected: $text',
    );
  }
}

void _expectAllAr(Iterable<String> texts) {
  for (final text in texts) {
    expect(find.text(text), findsWidgets, reason: 'missing (ar): $text');
  }
}

/// No row, card or button that looks tappable does nothing.
void _expectNoDeadEnds(WidgetTester tester) {
  for (final row in tester.widgetList<PlusActionRow>(
    find.byType(PlusActionRow),
  )) {
    expect(row.onTap, isNotNull, reason: 'row "${row.title}" does nothing');
  }
  for (final card in tester.widgetList<PlusActionCard>(
    find.byType(PlusActionCard),
  )) {
    expect(card.onTap, isNotNull, reason: 'card "${card.title}" does nothing');
  }
  for (final button in tester.widgetList<ElevatedButton>(
    find.byType(ElevatedButton),
  )) {
    expect(button.onPressed, isNotNull, reason: 'a primary button is dead');
  }
  for (final button in tester.widgetList<OutlinedButton>(
    find.byType(OutlinedButton),
  )) {
    expect(button.onPressed, isNotNull, reason: 'an outlined button is dead');
  }
  for (final button in tester.widgetList<TextButton>(
    find.byType(TextButton),
  )) {
    expect(button.onPressed, isNotNull, reason: 'a text button is dead');
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => setUpPlusTestAssets(binding));
  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  // ---------------------------------------------------------------------------
  group('payment details', () {
    testWidgets(
        'Google Play: what, how it is billed, who manages it, the action',
        (tester) async {
      await openPlusScreen(tester, _details, status: SubscriptionStatus.active);

      _expectTitle(en('plusPaymentDetailsTitle'));
      _expectAll([
        // The payment summary: only supplied values.
        en('plusPdSectionSummary'),
        en('plusBrandName'),
        en('plusStatusActive'),
        en('plusDetailBilling'),
        en('plusPeriodAnnual'),
        en('plusDetailPrice'),
        'USD 49.99 / year',
        en('plusDetailRenews'),
        'January 15, 2027',
        en('plusDetailStore'),
        // The payment method: the provider card with a Change action.
        en('plusPmTitle'),
        en('plusStoreGooglePlay'),
        en('plusPdMethodCaption'),
        en('plusPdManagedGoogle'),
        en('plusPdChange'),
        // One obvious bottom action.
        en('plusPdManageMethod'),
      ], present: true);
      _expectAll([
        en('plusPmProviderApple'),
        en('plusPdManagedApple'),
        en('plusFixPayment'),
        en('plusPdIssueTitle'),
      ], present: false);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('invents no subtotal, tax, discount, total or card',
        (tester) async {
      await openPlusScreen(tester, _details, status: SubscriptionStatus.active);

      for (final word in [
        'Subtotal',
        'VAT',
        'Tax',
        'Discount',
        'Total',
        'AED',
        '••',
        '08/26',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      // The only amount on the screen is the one the source supplied.
      expect(find.textContaining('USD'), findsNWidgets(1));
    });

    testWidgets('Change and the bottom action both open Payment method',
        (tester) async {
      await openPlusScreen(tester, _details, status: SubscriptionStatus.active);

      await _tap(tester, en('plusPdChange'));
      _expectTitle(en('plusPmTitle'));
      expect(find.text(en('plusPmSelectedCaption')), findsOneWidget);
      await _back(tester);
      _expectTitle(en('plusPaymentDetailsTitle'));

      await _tap(tester, en('plusPdManageMethod'));
      _expectTitle(en('plusPmTitle'));
      await _back(tester);
      _expectTitle(en('plusPaymentDetailsTitle'));
    });

    testWidgets('a trial shows when it ends', (tester) async {
      await openPlusScreen(tester, _details, status: SubscriptionStatus.trial);

      _expectAll([
        en('plusStatusTrial'),
        en('plusDetailTrialEnds'),
        'January 8, 2027',
      ], present: true);
    });

    testWidgets('a cancelled subscription is active, with renewal off',
        (tester) async {
      await openPlusScreen(tester, _details,
          status: SubscriptionStatus.cancelledActive);

      _expectAll([
        en('plusStatusActive'),
        en('plusStatusCancelledActive'),
        en('plusDetailAccessUntil'),
        'March 1, 2027',
      ], present: true);
      _expectAll([en('plusStatusExpired'), en('plusDetailRenews')],
          present: false);
    });

    testWidgets('Free shows a plain Free card, not subscriber billing',
        (tester) async {
      await openPlusScreen(tester, _details);

      _expectAll([
        en('freePlan'),
        en('plusFreeHeroBody'),
        en('plusStoreGooglePlay'),
        en('plusPdChange'),
        en('plusPdManageMethod'),
      ], present: true);
      _expectAll([
        en('plusDetailPrice'),
        en('plusDetailBilling'),
        en('plusDetailRenews'),
        en('plusDetailStore'),
        en('plusFixPayment'),
      ], present: false);
      expect(find.textContaining('USD'), findsNothing);
    });

    testWidgets('an ended plan shows only when it ended', (tester) async {
      await openPlusScreen(tester, _details,
          status: SubscriptionStatus.expired);

      _expectAll([
        en('plusStatusExpired'),
        en('plusDetailExpiredOn'),
        'December 1, 2026',
      ], present: true);
      _expectAll([
        en('plusDetailPrice'),
        en('plusDetailBilling'),
        en('plusDetailStore'),
      ], present: false);
    });

    for (final status in [
      SubscriptionStatus.billingIssue,
      SubscriptionStatus.gracePeriod,
    ]) {
      testWidgets('${status.name}: the payment-method card is the highlight',
          (tester) async {
        final c = await openPlusScreen(tester, _details, status: status);
        final before = c.vm.entitlement;

        _expectAll([
          en('plusPdIssueTitle'),
          status == SubscriptionStatus.billingIssue
              ? en('plusIssueBody', {'store': 'Google Play'})
              : en('plusIssueGraceBody', {
                  'store': 'Google Play',
                  'date': 'February 5, 2027',
                }),
          en('plusFixPayment'),
          // The pinned action becomes billing, not a second "fix".
          en('plusPmManageBilling'),
        ], present: true);
        // The card carries the fix instead of Change; one action, not two.
        _expectAll([en('plusPdChange'), en('plusPdManageMethod')],
            present: false);
        expect(find.text(en('plusStatusExpired')), findsNothing);

        // The fix goes to Payment method, and nothing was changed.
        await _tap(tester, en('plusFixPayment'));
        _expectTitle(en('plusPmTitle'));
        expect(c.vm.entitlement, same(before));
        await _back(tester);

        await _tap(tester, en('plusPmManageBilling'));
        _expectTitle(en('plusPmManageBilling'));
      });
    }

    testWidgets('App Store wording and icon on iOS', (tester) async {
      await openPlusScreen(
        tester,
        _details,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      _expectAll([
        en('plusPmProviderApple'),
        en('plusPdManagedApple'),
        en('plusDetailStore'),
        'App Store',
      ], present: true);
      _expectAll([en('plusPdManagedGoogle'), en('plusStoreGooglePlay')],
          present: false);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('payment method', () {
    testWidgets('Google Play: one selected provider, one prominent action',
        (tester) async {
      await openPlusScreen(tester, _dash, status: SubscriptionStatus.active);

      _expectTitle(en('plusPmTitle'));
      _expectAll([
        en('plusStoreGooglePlay'),
        en('plusPmSelectedCaption'),
        en('plusPdManagedGoogle'),
        en('plusPayManageTitle'),
        en('plusPmManageSubtitleGoogle'),
        en('plusPayAddTitle'),
        en('plusPmAddSubtitleGoogle'),
        en('plusPmManageBillingFull'),
        en('plusPmSubscriptionSubtitle', {'store': 'Google Play'}),
        en('plusPmHelp'),
        en('plusPaySafetyNote'),
      ], present: true);
      _expectAll([
        en('plusPmProviderApple'),
        en('plusPmManageSubtitleApple'),
        en('plusPmManageSubscription', {'store': 'App Store'}),
        // Backup lives on Manage payment methods, not here.
        en('plusPayBackupTitle'),
      ], present: false);

      // The selected state: exactly one provider, marked with a check.
      expect(find.byType(PlusProviderCard), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        tester.widget<PlusProviderCard>(find.byType(PlusProviderCard)).selected,
        isTrue,
      );

      // Strong hierarchy, not eight equal rows: three action cards of which
      // exactly one (Manage payment methods) is prominent, plus one quiet help.
      final cards = tester
          .widgetList<PlusActionCard>(find.byType(PlusActionCard))
          .toList();
      expect(cards.length, 3);
      expect(cards.where((c) => c.prominent).length, 1);
      expect(
          cards.firstWhere((c) => c.prominent).title, en('plusPayManageTitle'));
      expect(find.byType(PlusActionRow), findsOneWidget);

      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('a free user sees the payment actions only', (tester) async {
      await openPlusScreen(tester, _dash);

      _expectAll([
        en('plusPmSelectedCaption'),
        en('plusPayManageTitle'),
        en('plusPayAddTitle'),
        en('plusPmHelp'),
      ], present: true);
      _expectAll([
        en('plusPmManageBillingFull'),
        en('plusPmSubscriptionSubtitle', {'store': 'Google Play'}),
        en('plusIssueTitle'),
      ], present: false);
      expect(find.byType(PlusActionCard), findsNWidgets(2));
    });

    testWidgets('a payment issue leads with a calm notice', (tester) async {
      await openPlusScreen(tester, _dash,
          status: SubscriptionStatus.billingIssue);

      expect(find.text(en('plusIssueTitle')), findsOneWidget);
      expect(find.text(en('plusIssueBody', {'store': 'Google Play'})),
          findsOneWidget);
      // The way to fix it is the prominent action.
      expect(find.text(en('plusPayManageTitle')), findsOneWidget);
      expect(find.text(en('plusStatusExpired')), findsNothing);
    });

    testWidgets('App Store: the Apple Account, no backup, Apple wording',
        (tester) async {
      await openPlusScreen(
        tester,
        _dash,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      _expectAll([
        en('plusPmProviderApple'),
        en('plusPdManagedApple'),
        en('plusPmSelectedCaption'),
        en('plusPayManageTitle'),
        en('plusPmManageSubtitleApple'),
        en('plusPayAddTitle'),
        en('plusPmAddSubtitleApple'),
        en('plusPmManageSubscription', {'store': 'App Store'}),
        en('plusPmHelp'),
      ], present: true);
      _expectAll([
        en('plusStoreGooglePlay'),
        en('plusPmManageSubtitleGoogle'),
        en('plusPmAddSubtitleGoogle'),
        en('plusPmManageBillingFull'),
        en('plusPayBackupTitle'),
        en('plusPmBackupSubtitleGoogle'),
      ], present: false);
      expect(find.textContaining('Google'), findsNothing);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });

    final destinations = <String, ({String card, String landed})>{
      'Manage payment methods': (
        card: en('plusPayManageTitle'),
        landed: en('plusMmLabelManage'),
      ),
      'Add payment method': (
        card: en('plusPayAddTitle'),
        landed: en('plusAddLineBilledGoogle'),
      ),
      'Manage subscription billing': (
        card: en('plusPmManageBillingFull'),
        landed: en('plusBrandName'),
      ),
      'Payment method help': (
        card: en('plusPmHelp'),
        landed: en('plusPmHelpIntro'),
      ),
    };
    for (final entry in destinations.entries) {
      testWidgets('${entry.key} opens its own screen and back returns',
          (tester) async {
        await openPlusScreen(tester, _dash, status: SubscriptionStatus.active);

        await _tap(tester, entry.value.card);
        expect(find.text(entry.value.landed), findsWidgets,
            reason: 'did not reach ${entry.key}');
        expect(find.byType(BottomSheet), findsNothing);

        await _back(tester);
        _expectTitle(en('plusPmTitle'));
        expect(find.text(en('plusPmSelectedCaption')), findsOneWidget);
      });
    }

    testWidgets('on iOS Manage App Store subscription opens billing',
        (tester) async {
      await openPlusScreen(
        tester,
        _dash,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      await _tap(
          tester, en('plusPmManageSubscription', {'store': 'App Store'}));

      _expectTitle(en('plusPmManageBilling'));
    });
  });

  // ---------------------------------------------------------------------------
  group('manage payment methods', () {
    testWidgets('Google Play: the provider, then clear action cards',
        (tester) async {
      await openPlusScreen(tester, _manage, status: SubscriptionStatus.active);

      _expectTitle(en('plusPayManageTitle'));
      _expectAll([
        en('plusStoreGooglePlay'),
        en('plusManageMethodsIntroGoogle'),
        en('plusPdManagedGoogle'),
        // CHANGE / MANAGE
        en('plusMmLabelManage'),
        en('plusPmManageSubtitleGoogle'),
        en('plusPmOpenInStore', {'store': 'Google Play'}),
        // ADD
        en('plusMmLabelAdd'),
        en('plusPmAddSubtitleGoogle'),
        // BACKUP
        en('plusMmLabelBackup'),
        en('plusPayBackupTitle'),
        en('plusPmBackupSubtitleGoogle'),
        en('plusMmBackupButton'),
        en('plusPmHelp'),
        en('plusPaySafetyNote'),
      ], present: true);
      _expectAll([
        en('plusManageMethodsIntroApple'),
        en('plusMmShippingButton'),
        en('plusFixPayment'),
        en('plusIssueTitle'),
      ], present: false);
      // Three task cards, each with the button that does it.
      expect(find.byType(PlusTaskCard), findsNWidgets(3));
      expect(find.byType(BottomSheet), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('Manage in Google Play is the final hand-off step',
        (tester) async {
      final c = await openPlusScreen(tester, _manage,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusPmOpenInStore', {'store': 'Google Play'}));

      expect(find.byType(BottomSheet), findsOneWidget);
      for (final key in [
        'plusManageStepAndroid1',
        'plusPayStepAndroidMethods',
        'plusPayStepAndroidManage',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      expect(find.text(en('done')), findsOneWidget);
      expectNoPaymentForm(tester);

      await _tap(tester, en('done'));
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('the Add card opens the Add screen, the Backup card its own',
        (tester) async {
      await openPlusScreen(tester, _manage, status: SubscriptionStatus.active);

      await tester.tap(
        find.widgetWithText(OutlinedButton, en('plusPayAddTitle')),
      );
      await tester.pumpAndSettle();
      expect(find.text(en('plusAddLineBilledGoogle')), findsOneWidget);
      await _back(tester);

      await _tap(tester, en('plusMmBackupButton'));
      expect(find.text(en('plusBackupIntro')), findsWidgets);
      await _back(tester);

      await _tap(tester, en('plusPmHelp'));
      expect(find.text(en('plusPmHelpIntro')), findsOneWidget);
    });

    testWidgets('a payment issue leads with the fix', (tester) async {
      final c = await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.billingIssue,
      );
      final before = c.vm.entitlement;

      expect(find.text(en('plusIssueTitle')), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, en('plusFixPayment')),
        findsOneWidget,
      );

      await _tap(tester, en('plusFixPayment'));

      // The one place a documented link exists: the Google Play subscription.
      expect(find.text(en('plusPayStepAndroidUpdate')), findsOneWidget);
      expect(find.text(en('plusContinueToStore', {'store': 'Google Play'})),
          findsOneWidget);
      expect(find.text(en('notNow')), findsOneWidget);
      expectNoPaymentForm(tester);

      await _tap(tester, en('notNow'));
      expect(c.vm.entitlement, same(before));
      expect(find.text(en('plusStatusExpired')), findsNothing);
    });

    testWidgets('a healthy subscription is shown no payment warning',
        (tester) async {
      await openPlusScreen(tester, _manage, status: SubscriptionStatus.active);

      expect(find.text(en('plusIssueTitle')), findsNothing);
      expect(find.text(en('plusFixPayment')), findsNothing);
    });

    testWidgets('App Store: Payment & Shipping, no backup card',
        (tester) async {
      await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      _expectAll([
        en('plusPmProviderApple'),
        en('plusManageMethodsIntroApple'),
        en('plusMmLabelManage'),
        en('plusPmSectionPaymentShipping'),
        en('plusPmManageSubtitleApple'),
        en('plusMmShippingButton'),
        en('plusMmLabelAdd'),
        en('plusPmAddSubtitleApple'),
        en('plusPmHelp'),
      ], present: true);
      _expectAll([
        en('plusMmLabelBackup'),
        en('plusPayBackupTitle'),
        en('plusMmBackupButton'),
        en('plusStoreGooglePlay'),
        en('plusPmOpenInStore', {'store': 'Google Play'}),
      ], present: false);
      expect(find.byType(PlusTaskCard), findsNWidgets(2));
      expect(find.textContaining('Google'), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('Payment & Shipping steps are Apple\'s, as a final step',
        (tester) async {
      final c = await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.active,
        store: _apple,
      );
      final before = c.vm.entitlement;

      await _tap(tester, en('plusMmShippingButton'));

      expect(find.byType(BottomSheet), findsOneWidget);
      for (final key in [
        'plusManageStepIos1',
        'plusPayStepIosPayment',
        'plusPayStepIosAdd',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      expect(find.textContaining('Continue to'), findsNothing);
      await _tap(tester, en('done'));
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('an App Store payment issue gives guidance, not a fake link',
        (tester) async {
      await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.billingIssue,
        store: _apple,
      );

      await _tap(tester, en('plusFixPayment'));

      expect(find.text(en('plusPayIntroApple')), findsOneWidget);
      expect(find.text(en('plusPayStepIosPayment')), findsOneWidget);
      expect(find.textContaining('Continue to'), findsNothing);
      expect(find.text(en('done')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('add payment method', () {
    testWidgets('Google Play: a checkout-style screen, not a card form',
        (tester) async {
      await openPlusScreen(tester, _add, status: SubscriptionStatus.active);

      expect(find.text(en('plusPayAddTitle')), findsOneWidget);
      _expectAll([
        en('plusStoreGooglePlay'),
        en('plusAddLineBilledGoogle'),
        en('plusAddLineSecureGoogle'),
        en('plusAddLineNoCard'),
        en('plusContinueToStore', {'store': 'Google Play'}),
        en('plusAddHowTo'),
      ], present: true);
      _expectAll([
        en('plusContinueToApple'),
        en('plusAddHelpApple'),
        en('plusAddLineBilledApple'),
        en('plusAddLineSecureApple'),
      ], present: false);
      // A large provider visual, three short lines, one primary action.
      expect(find.byType(PlusProviderHero), findsOneWidget);
      expect(find.byType(PlusIconLine), findsNWidgets(3));
      expect(
        find.widgetWithText(
          ElevatedButton,
          en('plusContinueToStore', {'store': 'Google Play'}),
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('has no card, CVV, expiry, cardholder or postal-code field',
        (tester) async {
      await openPlusScreen(tester, _add, status: SubscriptionStatus.active);

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      for (final word in [
        'Card number',
        'CVV',
        'Expiry',
        'Cardholder',
        'Postal'
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('Continue is an honest hand-off step, not a fake navigation',
        (tester) async {
      final c =
          await openPlusScreen(tester, _add, status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusContinueToStore', {'store': 'Google Play'}));

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(en('plusPayAddTitle')), findsNWidgets(2));
      for (final key in [
        'plusPayIntroGoogle',
        'plusManageStepAndroid1',
        'plusPayStepAndroidMethods',
        'plusPayStepAndroidAdd',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      expect(find.text(en('done')), findsOneWidget);
      // Only the screen's own button says "Continue to": the sheet has none,
      // because no verified link exists and none is pretended.
      expect(find.textContaining('Continue to'), findsOneWidget);
      expectNoPaymentForm(tester);

      await _tap(tester, en('done'));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(en('plusAddLineBilledGoogle')), findsOneWidget);
      expect(c.vm.entitlement, same(before));
      expect(c.gateway.purchaseCalls, 0);
      expect(c.gateway.restoreCalls, 0);
    });

    testWidgets('How to add a payment method opens payment method help',
        (tester) async {
      await openPlusScreen(tester, _add, status: SubscriptionStatus.active);

      await _tap(tester, en('plusAddHowTo'));

      expect(find.text(en('plusPmHelpIntro')), findsOneWidget);
    });

    testWidgets('Android system back returns to Payment method',
        (tester) async {
      await openPlusScreen(tester, _dash, status: SubscriptionStatus.active);
      await _tap(tester, en('plusPayAddTitle'));
      expect(find.text(en('plusAddLineBilledGoogle')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(en('plusAddLineBilledGoogle')), findsNothing);
      _expectTitle(en('plusPmTitle'));
    });

    testWidgets('works for a free user', (tester) async {
      await openPlusScreen(tester, _add);

      expect(find.text(en('plusAddLineBilledGoogle')), findsOneWidget);
      expect(
          find.text(en('plusPmManageSubscription', {'store': 'Google Play'})),
          findsNothing);
    });

    testWidgets('App Store: speaks about the Apple Account', (tester) async {
      await openPlusScreen(
        tester,
        _add,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      expect(find.text(en('plusPayAddTitle')), findsOneWidget);
      _expectAll([
        en('plusPmProviderApple'),
        en('plusAddLineBilledApple'),
        en('plusAddLineSecureApple'),
        en('plusAddLineNoCard'),
        en('plusContinueToApple'),
        en('plusAddHelpApple'),
        en('plusPmManageSubscription', {'store': 'App Store'}),
      ], present: true);
      _expectAll([
        en('plusContinueToStore', {'store': 'Google Play'}),
        en('plusAddHowTo'),
        en('plusAddLineBilledGoogle'),
      ], present: false);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('Continue to Apple gives Apple\'s steps and invents no link',
        (tester) async {
      final c = await openPlusScreen(
        tester,
        _add,
        status: SubscriptionStatus.active,
        store: _apple,
      );
      final before = c.vm.entitlement;

      await _tap(tester, en('plusContinueToApple'));

      expect(find.byType(BottomSheet), findsOneWidget);
      for (final key in [
        'plusPayIntroApple',
        'plusManageStepIos1',
        'plusPayStepIosPayment',
        'plusPayStepIosAdd',
      ]) {
        expect(find.text(en(key)), findsOneWidget, reason: key);
      }
      expect(find.textContaining('Continue to'), findsOneWidget);
      await _tap(tester, en('done'));
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('the App Store secondary actions lead to help and billing',
        (tester) async {
      await openPlusScreen(
        tester,
        _add,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      await _tap(tester, en('plusAddHelpApple'));
      expect(find.text(en('plusPmHelpIntro')), findsOneWidget);
      await _back(tester);

      await _tap(
          tester, en('plusPmManageSubscription', {'store': 'App Store'}));
      _expectTitle(en('plusPmManageBilling'));
    });

    testWidgets('a free App Store user is not offered the subscription',
        (tester) async {
      await openPlusScreen(tester, _add, store: _apple);

      expect(find.text(en('plusContinueToApple')), findsOneWidget);
      expect(find.text(en('plusPmManageSubscription', {'store': 'App Store'})),
          findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('backup payment methods', () {
    testWidgets('Google Play: what it is, why it helps, who decides',
        (tester) async {
      await openPlusScreen(tester, _backup, status: SubscriptionStatus.active);

      _expectTitle(en('plusPayBackupTitle'));
      _expectAll([
        en('plusStoreGooglePlay'),
        en('plusBackupIntro'),
        en('plusPdManagedGoogle'),
        en('plusBackupPointWhat'),
        en('plusBackupPointWhy'),
        en('plusBackupPointEligibility'),
        en('plusBackupManage'),
        en('plusPmHelp'),
        en('plusPaySafetyNote'),
      ], present: true);
      _expectAll([
        en('plusBackupUnavailableTitle'),
        en('plusBackupUnavailableBody'),
      ], present: false);
      expect(find.byType(BottomSheet), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('Manage backup payment methods is the final hand-off step',
        (tester) async {
      final c = await openPlusScreen(tester, _backup,
          status: SubscriptionStatus.active);
      final before = c.vm.entitlement;

      await _tap(tester, en('plusBackupManage'));

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(en('plusPayBackupTitle')), findsNWidgets(2));
      expect(find.text(en('plusPayStepAndroidBackup')), findsOneWidget);
      expect(find.text(en('plusManageStepAndroid2')), findsOneWidget);
      expect(find.text(en('done')), findsOneWidget);

      await _tap(tester, en('done'));
      expect(c.vm.entitlement, same(before));
    });

    testWidgets('help opens payment method help', (tester) async {
      await openPlusScreen(tester, _backup, status: SubscriptionStatus.active);

      await _tap(tester, en('plusPmHelp'));

      expect(find.text(en('plusPmHelpIntro')), findsOneWidget);
    });

    testWidgets('the App Store has no backup action anywhere', (tester) async {
      // Not on Payment method or Manage payment methods...
      await openPlusScreen(tester, _dash, store: _apple);
      expect(find.text(en('plusPayBackupTitle')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(tester, _manage, store: _apple);
      expect(find.text(en('plusPayBackupTitle')), findsNothing);
      expect(find.text(en('plusMmBackupButton')), findsNothing);

      // ...and not in help...
      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(tester, _help, store: _apple);
      expect(find.text(en('plusPayBackupTitle')), findsNothing);
      expect(find.text(en('plusPmAnswerBackup')), findsNothing);

      // ...and a direct visit says so and leads back, with no Google wording.
      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(tester, _backup, store: _apple);
      expect(find.text(en('plusBackupUnavailableTitle')), findsOneWidget);
      expect(find.text(en('plusBackupUnavailableBody')), findsOneWidget);
      _expectAll([
        en('plusBackupManage'),
        en('plusBackupIntro'),
        en('plusBackupPointWhat'),
        en('plusBackupPointWhy'),
      ], present: false);
      _expectNoDeadEnds(tester);

      await _tap(tester, en('plusBackToPaymentMethods'));
      _expectTitle(en('plusPmTitle'));
      expect(find.text(en('plusPmProviderApple')), findsOneWidget);
      expect(find.text(en('plusPayBackupTitle')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('manage billing', () {
    testWidgets('Google Play: a billing dashboard with one store action',
        (tester) async {
      await openPlusScreen(tester, _billing, status: SubscriptionStatus.active);

      _expectTitle(en('plusPmManageBilling'));
      _expectAll([
        en('plusBrandName'),
        en('plusStatusActive'),
        en('plusPeriodPriceLine', {
          'period': en('plusPeriodAnnual'),
          'price': 'USD 49.99 / year',
        }),
        en('plusHeroRenewsOn', {'date': 'January 15, 2027'}),
        en('plusBilledThrough', {'store': 'Google Play'}),
        // Only the actions that matter.
        en('plusManageSubscription'),
        en('plusPmTitle'),
        en('plusRowHistory'),
        en('plusRestorePurchases'),
        // The one store action, pinned.
        en('plusPmOpenInStore', {'store': 'Google Play'}),
      ], present: true);
      _expectAll([
        en('plusManageNoneTitle'),
        en('plusViewPlans'),
        // The old details table is gone: this is a dashboard.
        en('plusDetailPrice'),
        en('plusDetailRenewal'),
      ], present: false);
      expect(find.byType(PlusPlanSummaryCard), findsOneWidget);
      expect(find.byType(PlusActionRow), findsNWidgets(4));
      expect(find.byType(BottomSheet), findsNothing);
      expectNoPaymentForm(tester);
      _expectNoDeadEnds(tester);
    });

    testWidgets('App Store: names Apple and its store action', (tester) async {
      await openPlusScreen(
        tester,
        _billing,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      _expectAll([
        en('plusBilledThrough', {'store': 'App Store'}),
        en('plusPmOpenInStore', {'store': 'App Store'}),
      ], present: true);
      expect(find.textContaining('Google'), findsNothing);
    });

    testWidgets('the store action is a hand-off that changes nothing',
        (tester) async {
      for (final store in [_google, _apple]) {
        final c = await openPlusScreen(
          tester,
          _billing,
          status: SubscriptionStatus.active,
          store: store,
        );
        final before = c.vm.entitlement;

        await _tap(
            tester, en('plusPmOpenInStore', {'store': storeName(store)}));

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text(en('plusContinueToStore', {'store': storeName(store)})),
          findsOneWidget,
        );
        await _tap(tester, en('notNow'));
        expect(c.vm.entitlement, same(before));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    final links = <String, ({String row, String landed})>{
      'Manage subscription': (
        row: en('plusManageSubscription'),
        landed: en('plusManageDetailsLabel'),
      ),
      'Payment method': (
        row: en('plusPmTitle'),
        landed: en('plusPmSelectedCaption'),
      ),
      'Billing history & receipts': (
        row: en('plusRowHistory'),
        landed: en('plusHistoryHowTo'),
      ),
      'Restore purchases': (
        row: en('plusRestorePurchases'),
        landed: en('plusRestoreTitle'),
      ),
    };
    for (final entry in links.entries) {
      testWidgets('${entry.key} opens its own screen and back returns',
          (tester) async {
        await openPlusScreen(tester, _billing,
            status: SubscriptionStatus.active);

        await _tap(tester, entry.value.row);
        expect(find.text(entry.value.landed), findsOneWidget);

        await _back(tester);
        _expectTitle(en('plusPmManageBilling'));
      });
    }

    testWidgets('a cancelled subscription shows renewal off and the end date',
        (tester) async {
      await openPlusScreen(tester, _billing,
          status: SubscriptionStatus.cancelledActive);

      _expectAll([
        en('plusStatusActive'),
        en('plusStatusCancelledActive'),
        en('plusHeroActiveUntil', {'date': 'March 1, 2027'}),
      ], present: true);
      _expectAll([en('plusDetailNextCharge'), en('plusStatusExpired')],
          present: false);
    });

    testWidgets('a trial shows when it ends', (tester) async {
      await openPlusScreen(tester, _billing, status: SubscriptionStatus.trial);

      _expectAll([
        en('plusStatusTrial'),
        en('plusHeroTrialEnds', {'date': 'January 8, 2027'}),
      ], present: true);
    });

    for (final status in [
      SubscriptionStatus.gracePeriod,
      SubscriptionStatus.billingIssue,
    ]) {
      testWidgets('${status.name} shows the calm payment notice',
          (tester) async {
        await openPlusScreen(tester, _billing, status: status);

        expect(find.text(en('plusIssueTitle')), findsOneWidget);
        expect(find.text(en('plusStatusExpired')), findsNothing);
      });
    }

    testWidgets('Free sees no renewal, charge or store action', (tester) async {
      await openPlusScreen(tester, _billing);

      _expectAll([
        en('plusManageNoneTitle'),
        en('plusViewPlans'),
        en('plusPmTitle'),
        en('plusRestorePurchases'),
      ], present: true);
      _expectAll([
        en('plusManageSubscription'),
        en('plusRowHistory'),
        en('plusBilledThrough', {'store': 'Google Play'}),
        en('plusPmOpenInStore', {'store': 'Google Play'}),
      ], present: false);
      _expectNoDeadEnds(tester);
    });

    testWidgets('an expired plan offers receipts and Restore, not renewal',
        (tester) async {
      await openPlusScreen(tester, _billing,
          status: SubscriptionStatus.expired);

      _expectAll([
        en('plusManageNoneTitle'),
        en('plusRowHistory'),
        en('plusRestorePurchases'),
      ], present: true);
      _expectAll([
        en('plusPmOpenInStore', {'store': 'Google Play'}),
        en('plusManageSubscription'),
      ], present: false);
    });
  });

  // ---------------------------------------------------------------------------
  group('payment method help', () {
    // Topic title -> (answer, the action in the answer, where it leads).
    final googleTopics = <String, ({String answer, String action, String to})>{
      en('plusPayAddTitle'): (
        answer: en('plusPmAnswerAddGoogle'),
        action: en('plusPayAddTitle'),
        to: en('plusAddLineBilledGoogle'),
      ),
      en('plusPmHelpChange'): (
        answer: en('plusPmAnswerChangeGoogle'),
        action: en('plusPayManageTitle'),
        to: en('plusManageMethodsIntroGoogle'),
      ),
      en('plusPmHelpDeclined'): (
        answer: en('plusPmAnswerDeclined', {'store': 'Google Play'}),
        action: en('plusPayUpdateTitle'),
        to: en('plusManageMethodsIntroGoogle'),
      ),
      en('plusPmHelpBillingIssue'): (
        answer: en('plusPmAnswerBillingIssue', {'store': 'Google Play'}),
        action: en('plusPmManageBilling'),
        to: en('plusBrandName'),
      ),
      en('plusPayBackupTitle'): (
        answer: en('plusPmAnswerBackup'),
        action: en('plusPayBackupTitle'),
        to: en('plusBackupIntro'),
      ),
      en('plusManageSubscription'): (
        answer: en('plusPmAnswerManage', {'store': 'Google Play'}),
        action: en('plusManageSubscription'),
        to: en('plusManageDetailsLabel'),
      ),
    };

    testWidgets('Google Play: topics are collapsed until chosen',
        (tester) async {
      await openPlusScreen(tester, _help, status: SubscriptionStatus.active);

      expect(find.text(en('plusPmHelp')), findsOneWidget);
      _expectAll([
        en('plusPmHelpIntro'),
        ...googleTopics.keys,
        en('plusContactSupport'),
        en('plusHelpSupportSubtitle'),
      ], present: true);
      // Progressive disclosure: no answer is on show yet.
      for (final topic in googleTopics.values) {
        expect(find.text(topic.answer), findsNothing);
      }
      _expectNoDeadEnds(tester);
    });

    for (final entry in googleTopics.entries) {
      testWidgets('Google Play: "${entry.key}" answers and leads somewhere',
          (tester) async {
        await openPlusScreen(tester, _help, status: SubscriptionStatus.active);

        await _tap(tester, entry.key);
        expect(find.text(entry.value.answer), findsOneWidget);

        await _tapButton(tester, entry.value.action);
        expect(find.text(entry.value.to), findsWidgets,
            reason: 'the action for "${entry.key}" went nowhere useful');
      });
    }

    testWidgets('App Store: Apple wording and no backup topic', (tester) async {
      await openPlusScreen(
        tester,
        _help,
        status: SubscriptionStatus.active,
        store: _apple,
      );

      _expectAll([
        en('plusPayAddTitle'),
        en('plusPmHelpChange'),
        en('plusPmHelpDeclined'),
        en('plusPmHelpBillingIssue'),
        en('plusManageSubscription'),
      ], present: true);
      expect(find.text(en('plusPayBackupTitle')), findsNothing);

      await _tap(tester, en('plusPayAddTitle'));
      expect(find.text(en('plusPmAnswerAddApple')), findsOneWidget);
      expect(find.text(en('plusPmAnswerAddGoogle')), findsNothing);
      await _tapButton(tester, en('plusPayAddTitle'));
      expect(find.text(en('plusAddLineBilledApple')), findsOneWidget);
    });

    testWidgets('Contact support opens the existing Help & Support',
        (tester) async {
      await openPlusScreen(tester, _help);

      await _tap(tester, en('plusContactSupport'));

      expect(find.text('support-stub'), findsOneWidget);
    });

    testWidgets('invents no phone number, email address or chat',
        (tester) async {
      await openPlusScreen(tester, _help, status: SubscriptionStatus.active);
      // Open every topic so every answer is on screen.
      for (final title in googleTopics.keys) {
        await _tap(tester, title);
      }

      for (final word in ['@', '+971', 'Chat', 'Ticket', 'Call us']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expectNoPaymentForm(tester);
    });

    testWidgets('works for a free user', (tester) async {
      await openPlusScreen(tester, _help);

      expect(find.text(en('plusPmHelpIntro')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('billing issue recovery, end to end', () {
    for (final store in [_google, _apple]) {
      for (final status in [
        SubscriptionStatus.gracePeriod,
        SubscriptionStatus.billingIssue,
      ]) {
        testWidgets(
            '${storeName(store)} / ${status.name}: hub -> Payment details -> '
            'Payment method -> Manage -> hand-off', (tester) async {
          final c =
              await openPlusScreen(tester, _hub, status: status, store: store);
          final before = c.vm.entitlement;

          // 1. Subscription & Billing: the payment issue and its fix.
          expect(find.text(en('plusIssueTitle')), findsOneWidget);
          await _tap(tester, en('plusFixPayment'));

          // 2. Payment details: the payment-method card is the highlight.
          _expectTitle(en('plusPaymentDetailsTitle'));
          expect(find.text(en('plusPdIssueTitle')), findsWidgets);
          await _tap(tester, en('plusFixPayment'));

          // 3. Payment method: the same problem, and the way to manage it.
          _expectTitle(en('plusPmTitle'));
          expect(find.text(en('plusIssueTitle')), findsOneWidget);
          await _tap(tester, en('plusPayManageTitle'));

          // 4. Manage payment methods, with the fix as its primary action.
          _expectTitle(en('plusPayManageTitle'));
          expect(find.text(en('plusIssueTitle')), findsOneWidget);
          await _tap(tester, en('plusFixPayment'));

          // 5. The platform hand-off, store-specific.
          expect(find.byType(BottomSheet), findsOneWidget);
          if (store == _google) {
            expect(find.text(en('plusPayStepAndroidUpdate')), findsOneWidget);
            expect(
              find.text(en('plusContinueToStore', {'store': 'Google Play'})),
              findsOneWidget,
            );
            await _tap(tester, en('notNow'));
          } else {
            expect(find.text(en('plusPayStepIosPayment')), findsOneWidget);
            expect(find.textContaining('Continue to'), findsNothing);
            await _tap(tester, en('done'));
          }

          // Nothing was changed, and the plan is never shown as ended.
          expect(c.vm.entitlement, same(before));
          expect(find.text(en('plusStatusExpired')), findsNothing);

          // Back out the same way: Manage -> Payment method -> Payment details
          // -> the hub.
          await _back(tester);
          _expectTitle(en('plusPmTitle'));
          await _back(tester);
          _expectTitle(en('plusPaymentDetailsTitle'));
          await _back(tester);
          _expectTitle(en('plusBillingTitle'));
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  group('Android runtime: Google Play only', () {
    final routes = [_details, _dash, _manage, _add, _backup, _billing, _help];

    for (final route in routes) {
      for (final status in [
        SubscriptionStatus.free,
        SubscriptionStatus.active
      ]) {
        testWidgets(
            '${route.replaceFirst(_hub, '')} / ${status.name}: no App Store, '
            'Apple or provider selector', (tester) async {
          tallSurface(tester);
          // No preview store: this is what an Android device runs. The
          // platform decides, and the platform is Android.
          final c = plusCtx();
          if (status != SubscriptionStatus.free) {
            c.vm.applyEntitlement(testState(status));
          }
          await tester.pumpWidget(plusTestApp(c.vm, initialLocation: route));
          await tester.pumpAndSettle();

          expect(c.vm.effectiveStore, PlusStore.googlePlay);
          for (final word in ['App Store', 'Apple', 'iOS', 'iPhone']) {
            expect(find.textContaining(word), findsNothing, reason: word);
          }
          // No way to choose a provider: no radio, chip, dropdown or tab bar.
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Radio ||
                  w is RadioListTile ||
                  w is ChoiceChip ||
                  w is FilterChip ||
                  w is DropdownButton ||
                  w is TabBar,
            ),
            findsNothing,
          );
          expectNoPaymentForm(tester);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  group('no card, no credential, no dead end', () {
    final routes = [_details, _dash, _add, _manage, _backup, _billing, _help];
    for (final route in routes) {
      for (final store in [_google, _apple]) {
        for (final status in [
          SubscriptionStatus.free,
          SubscriptionStatus.active,
          SubscriptionStatus.billingIssue,
        ]) {
          testWidgets(
              '${route.replaceFirst(_hub, '')} / ${storeName(store)} / '
              '${status.name}', (tester) async {
            await openPlusScreen(tester, route, status: status, store: store);

            expectNoPaymentForm(tester);
            _expectNoDeadEnds(tester);
            // A screen of its own, never a sheet standing in for one.
            expect(find.byType(BottomSheet), findsNothing);
          });
        }
      }
    }
  });

  // ---------------------------------------------------------------------------
  group('English, Arabic and direction', () {
    final routes = [_details, _dash, _add, _manage, _backup, _billing, _help];
    for (final route in routes) {
      for (final store in [_google, _apple]) {
        testWidgets(
            '${route.replaceFirst(_hub, '')} / ${storeName(store)}: Arabic is '
            'right-to-left with no raw placeholder or missing key',
            (tester) async {
          await openPlusScreen(
            tester,
            route,
            status: SubscriptionStatus.active,
            store: store,
            locale: const Locale('ar'),
          );

          final context = tester.element(find.byType(Scaffold).first);
          expect(Directionality.of(context), TextDirection.rtl);
          expect(find.textContaining('{'), findsNothing);
          expect(find.textContaining('not found'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('Arabic Payment details and Payment method use Arabic wording',
        (tester) async {
      await openPlusScreen(
        tester,
        _details,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusPaymentDetailsTitle'),
        ar('plusPdSectionSummary'),
        ar('plusPmTitle'),
        ar('plusPdMethodCaption'),
        ar('plusPdManagedGoogle'),
        ar('plusPdChange'),
        ar('plusPdManageMethod'),
        ar('plusDetailStore'),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _dash,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusPmTitle'),
        ar('plusPmSelectedCaption'),
        ar('plusPayManageTitle'),
        ar('plusPmManageSubtitleGoogle'),
        ar('plusPayAddTitle'),
        ar('plusPmManageBillingFull'),
        ar('plusPmHelp'),
      ]);
    });

    testWidgets('Arabic Add and Manage use the Arabic wording', (tester) async {
      await openPlusScreen(
        tester,
        _add,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusPayAddTitle'),
        ar('plusAddLineBilledGoogle'),
        ar('plusAddLineSecureGoogle'),
        ar('plusAddLineNoCard'),
        ar('plusContinueToStore', {'store': 'Google Play'}),
        ar('plusAddHowTo'),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusMmLabelManage'),
        ar('plusMmLabelAdd'),
        ar('plusMmLabelBackup'),
        ar('plusMmBackupButton'),
        ar('plusManageMethodsIntroGoogle'),
      ]);
    });

    testWidgets('Arabic App Store screens use Apple\'s wording',
        (tester) async {
      await openPlusScreen(
        tester,
        _add,
        status: SubscriptionStatus.active,
        store: _apple,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusPmProviderApple'),
        ar('plusAddLineBilledApple'),
        ar('plusContinueToApple'),
        ar('plusAddHelpApple'),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _manage,
        status: SubscriptionStatus.active,
        store: _apple,
        locale: const Locale('ar'),
      );
      _expectAllAr([
        ar('plusManageMethodsIntroApple'),
        ar('plusPmSectionPaymentShipping'),
        ar('plusMmShippingButton'),
      ]);
    });

    testWidgets('action cards point away from the start in both directions',
        (tester) async {
      await openPlusScreen(tester, _dash, status: SubscriptionStatus.active);
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await openPlusScreen(
        tester,
        _dash,
        status: SubscriptionStatus.active,
        locale: const Locale('ar'),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('the Arabic hand-off step renders right-to-left',
        (tester) async {
      await openPlusScreen(
        tester,
        _manage,
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

  // ---------------------------------------------------------------------------
  group('small phone and large text', () {
    // The English test keeps its original name; the Arabic one adds a suffix.
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final isArabic = locale.languageCode == 'ar';
      String t(String key, [Map<String, String> args = const {}]) =>
          isArabic ? ar(key, args) : en(key, args);
      final suffix = isArabic ? ' in Arabic' : '';

      testWidgets('hand-off sheets stay usable at 1.6x text$suffix',
          (tester) async {
        await openPlusScreen(
          tester,
          _manage,
          status: SubscriptionStatus.billingIssue,
          small: true,
          textScale: 1.6,
          locale: locale,
        );

        // 1. The fix for a payment issue: the sheet can continue to the store,
        //    so it has a primary and a secondary action. Both must be
        //    readable and reachable, not just present.
        await scrollToVisible(tester, find.text(t('plusFixPayment')));
        await _tap(tester, t('plusFixPayment'));
        expect(tester.takeException(), isNull);
        expect(find.text(t('plusPayStepAndroidUpdate')), findsOneWidget);
        await expectReachable(
          tester,
          find.text(t('plusContinueToStore', {'store': 'Google Play'})),
        );
        await expectReachable(tester, find.text(t('notNow')));
        await _tap(tester, t('notNow'));
        expect(find.text(t('plusPayStepAndroidUpdate')), findsNothing);

        // 2. Add payment method: a card far below the first screen opens the
        //    dedicated screen, whose one large action stays reachable.
        final addButton = find.widgetWithText(
          OutlinedButton,
          t('plusPayAddTitle'),
        );
        await scrollToVisible(tester, addButton);
        await tester.tap(addButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cta =
            find.text(t('plusContinueToStore', {'store': 'Google Play'}));
        await expectReachable(tester, cta);

        // 3. Its hand-off step: the explanation can be read, and Done reached.
        await _tap(tester, t('plusContinueToStore', {'store': 'Google Play'}));
        expect(tester.takeException(), isNull);
        expect(find.text(t('plusPayIntroGoogle')), findsOneWidget);
        await expectReachable(tester, find.text(t('done')));
        await _tap(tester, t('done'));
        expect(find.text(t('plusPayIntroGoogle')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Payment details actions stay reachable at 1.6x text$suffix',
          (tester) async {
        await openPlusScreen(
          tester,
          _details,
          status: SubscriptionStatus.active,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        // The pinned action is always on screen; Change, which drops below the
        // provider name at large text, is reachable by scrolling.
        await expectReachable(tester, find.text(t('plusPdManageMethod')));
        await scrollToVisible(tester, find.text(t('plusPdChange')));
        await expectReachable(tester, find.text(t('plusPdChange')));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await openPlusScreen(
          tester,
          _details,
          status: SubscriptionStatus.billingIssue,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        // With a payment issue the fix is on the highlighted card, and the
        // pinned action is billing.
        await expectReachable(tester, find.text(t('plusPmManageBilling')));
        await scrollToVisible(tester, find.text(t('plusFixPayment')));
        await expectReachable(tester, find.text(t('plusFixPayment')));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'Add, Backup and Billing actions stay reachable at 1.6x text$suffix',
          (tester) async {
        await openPlusScreen(
          tester,
          _add,
          status: SubscriptionStatus.active,
          store: _apple,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        await expectReachable(tester, find.text(t('plusContinueToApple')));
        await expectReachable(tester, find.text(t('plusAddHelpApple')));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await openPlusScreen(
          tester,
          _backup,
          status: SubscriptionStatus.active,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        await expectReachable(tester, find.text(t('plusBackupManage')));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await openPlusScreen(
          tester,
          _billing,
          status: SubscriptionStatus.active,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        await expectReachable(
          tester,
          find.text(t('plusPmOpenInStore', {'store': 'Google Play'})),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Payment method actions stay reachable at 1.6x text$suffix',
          (tester) async {
        await openPlusScreen(
          tester,
          _dash,
          status: SubscriptionStatus.active,
          small: true,
          textScale: 1.6,
          locale: locale,
        );
        await scrollToVisible(tester, find.text(t('plusPayManageTitle')));
        await expectReachable(tester, find.text(t('plusPayManageTitle')));
        await scrollToVisible(tester, find.text(t('plusPmManageBillingFull')));
        await expectReachable(tester, find.text(t('plusPmManageBillingFull')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
