import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/cancellation_info_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/how_limits_work_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/manage_subscription_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plan_compare_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/restore_purchases_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_flow_state_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_plan_sheet.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_preview_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_routes.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/usage_details_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/billing_payments_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/my_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

late Map<String, dynamic> _en;
late Map<String, dynamic> _ar;

String _t(String key, [String lang = 'en']) =>
    (lang == 'ar' ? _ar : _en)[key] as String;

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  SubscriptionPresentation presentation =
      const SubscriptionPresentation.unavailable(),
  String lang = 'en',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(420, 4200),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SubscriptionScope(
      presentation: presentation,
      child: MaterialApp(
        key: ValueKey('$lang-$mode-$size-$textScale-${screen.runtimeType}'),
        locale: Locale(lang),
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: _delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  // Not pumpAndSettle: the restore "checking" state has an endless spinner.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

FilledButton _filled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );

extension on SubscriptionPresentation {
  /// The same state with no store attached, as a web-only account would be.
  SubscriptionPresentation copyWithoutProvider() => SubscriptionPresentation(
        status: status,
        cycle: cycle,
        usage: usage,
        isSample: isSample,
      );
}

/// Taps the Plus card's call to action on the plans screen.
Future<void> _openPlanSheet(
  WidgetTester tester, {
  String cycleKey = 'subCycleAnnual',
  String lang = 'en',
}) async {
  final label = (lang == 'ar' ? _ar : _en)['subContinueWithPlan'] as String;
  await tester.tap(
    find.text(label.replaceAll('{cycle}', _t(cycleKey, lang))),
  );
  await tester.pumpAndSettle();
}

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(of: find.text(text), matching: find.byType(AnimatedOpacity))
          .first,
    )
    .opacity;

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

/// Words that must never appear in the iPhone subscription experience.
final _iosForbidden = RegExp(
  r'tap payments|stripe|google play|\bwebsite\b|\bweb\b|https?:|www\.|'
  r'checkout|\bcard\b|payment method|\bpay\b|'
  r'بطاقة|موقع|سترايب|طريقة الدفع|صفحة الدفع',
  caseSensitive: false,
);

Future<void> _pumpRouter(
  WidgetTester tester, {
  required SubscriptionPresentation presentation,
  String initial = '/subscription',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 4200);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push(initial),
            child: const Text('open'),
          ),
        ),
      ),
      GoRoute(
        path: '/my-plan',
        builder: (context, state) => const MyPlanView(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionView(),
      ),
      GoRoute(
        path: '/billing-payments',
        builder: (context, state) => const BillingPaymentsView(),
      ),
      ...subscriptionProfileRoutes(),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    SubscriptionScope(
      presentation: presentation,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: _delegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.preloadAllLanguages();
    _en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    _ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('approved commercial rules', () {
    test('prices, saving and allowances match the owner decision', () {
      expect(SubscriptionPolicy.monthlyPrice.amount, '20.00');
      expect(SubscriptionPolicy.annualPrice.amount, '180.00');
      expect(SubscriptionPolicy.annualMonthlyEquivalent.amount, '15.00');
      expect(SubscriptionPolicy.annualSavingPercent, 25);
      expect(SubscriptionPolicy.freeCreationsPerCategory, 5);
      expect(SubscriptionPolicy.freeEditsPerItem, 3);
      expect(UsageCategory.values, hasLength(11));

      // Exact integer fils: no rounding hides a wrong figure.
      final fullYear = SubscriptionPolicy.monthlyPrice.fils * 12;
      final annual = SubscriptionPolicy.annualPrice.fils;
      expect((fullYear - annual) * 100,
          SubscriptionPolicy.annualSavingPercent * fullYear);
      expect(annual % 12, 0);
      expect(annual ~/ 12, SubscriptionPolicy.annualMonthlyEquivalent.fils);
    });

    test('a store-provided label replaces the reference amount', () {
      const price = PlanPrice(2000, storeLabel: 'AED 21.00');
      expect(price.storeLabel, 'AED 21.00');
      expect(price.amount, '20.00');
    });

    test('no obsolete commercial wording exists in either language', () {
      final obsolete = RegExp(
        r'19\.99|199\.20|16\.60|17%|free slot|saved items|make space|'
        r'editing (is|are) (always )?unlimited|'
        r'editing and sharing are never',
        caseSensitive: false,
      );
      for (final map in [_en, _ar]) {
        for (final entry in map.entries) {
          if (!entry.key.startsWith('sub') ||
              !RegExp(r'^sub[A-Z]').hasMatch(entry.key)) {
            continue;
          }
          expect(obsolete.hasMatch(entry.value as String), isFalse,
              reason: entry.key);
        }
      }
    });

    test('every module key exists in both languages with equal placeholders',
        () {
      final keys = <String>{};
      final dir = Directory('lib/src/views/Screens/home/Profile');
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        keys.addAll(RegExp(r"'(sub[A-Z]\w*)'")
            .allMatches(file.readAsStringSync())
            .map((m) => m.group(1)!));
      }
      expect(keys, isNotEmpty);
      List<String> holders(String s) =>
          RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toList()
            ..sort();
      for (final key in keys) {
        expect(_en[key], isA<String>(), reason: 'en $key');
        expect(_ar[key], isA<String>(), reason: 'ar $key');
        expect(holders(_ar[key] as String), holders(_en[key] as String),
            reason: key);
      }
    });
  });

  group('honest default', () {
    testWidgets('unknown status is neither Free nor Plus', (tester) async {
      await _pump(tester, const MyPlanView());
      expect(find.text(_t('planStatusUnavailable')), findsOneWidget);
      expect(find.text(_t('subPillActive')), findsNothing);
      expect(find.text(_t('subCurrentPlan')), findsNothing);
      expect(find.text(_t('subUsageNotAvailable')), findsNWidgets(11));
      expect(find.textContaining('AED'), findsNothing);
    });

    test('unavailable presentation grants nothing', () {
      const p = SubscriptionPresentation.unavailable();
      expect(p.hasVerifiedPlus, isFalse);
      expect(p.isUnconfirmed, isTrue);
      expect(p.isSample, isFalse);
      expect(p.nextPaymentDate, isNull);
      for (final category in UsageCategory.values) {
        expect(p.usage.createdFor(category), isNull);
      }
    });

    test('samples are referenced only by the debug preview', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('SubscriptionSamples'))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      expect(hits, hasLength(1));
      expect(hits.single, endsWith('subscription_preview_view.dart'));
    });
  });

  group('plans and comparison', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('monthly and annual labels in $lang', (tester) async {
        await _pump(tester, const SubscriptionView(), lang: lang);
        expect(find.textContaining('180.00'), findsOneWidget);
        expect(find.textContaining('20.00'), findsOneWidget);
        expect(find.textContaining('15.00'), findsOneWidget);
        expect(find.textContaining('25%'), findsOneWidget);
        expect(find.textContaining('19.99'), findsNothing);
        expect(find.textContaining('199.20'), findsNothing);
        expect(find.textContaining('16.60'), findsNothing);
        expect(find.textContaining('17%'), findsNothing);
      });

      testWidgets('comparison names all 11 categories in $lang',
          (tester) async {
        await _pump(tester, const PlanCompareView(), lang: lang);
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n');
        for (final key in [
          'subCatOwners',
          'subCatOffers',
          'subCatRequests',
          'subCatWatchmen',
          'subCatOffices',
          'subCatBrokers',
          'subCatQuotations',
          'subCatScanner',
          'subCatSignature',
          'subCatImagesToPdf',
          'subCatCombinePdfs',
        ]) {
          expect(text, contains(_t(key, lang)), reason: key);
        }
        expect(text, contains(_t('subThreePerItem', lang)));
      });
    }

    testWidgets('selecting a cycle keeps the option size', (tester) async {
      await _pump(tester, const SubscriptionView());
      final monthly = find.textContaining('20.00');
      final inkBefore = tester.getSize(
        find.ancestor(of: monthly, matching: find.byType(InkWell)).first,
      );
      await tester.tap(monthly);
      await tester.pump();
      final inkAfter = tester.getSize(
        find.ancestor(of: monthly, matching: find.byType(InkWell)).first,
      );
      expect(inkAfter, inkBefore);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });
  });

  group('limit explanations', () {
    testWidgets('five lifetime creations and no deletion reset',
        (tester) async {
      await _pump(tester, const HowLimitsWorkView());
      expect(find.text(_t('subLimitsCreationBody')), findsOneWidget);
      expect(find.text(_t('subLimitsDeleteBody')), findsOneWidget);
      expect(find.text(_t('subLimitsDeleteExample')), findsOneWidget);
      expect(_t('subLimitsDeleteExample'), contains('5 of 5'));
    });

    testWidgets('three edits per item, counted per record', (tester) async {
      await _pump(tester, const HowLimitsWorkView());
      expect(find.text(_t('subLimitsEditsBody')), findsOneWidget);
      expect(find.text(_t('subLimitsEditsNotCounted')), findsOneWidget);
      expect(find.text(_t('subLimitsEditsNoChange')), findsOneWidget);
      expect(_t('subLimitsEditsExample'), contains('2 of 3 edits used'));
      expect(_t('subLimitsEditsExample'), contains('no free edits remaining'));
    });

    testWidgets('usage shows per-item edit states', (tester) async {
      await _pump(
        tester,
        const UsageDetailsView(),
        presentation: SubscriptionSamples.free,
      );
      expect(find.textContaining('2 of 3 edits used'), findsOneWidget);
      expect(find.textContaining(_t('subNoFreeEdits')), findsOneWidget);
      expect(find.text('5 of 5'), findsNWidgets(3));
    });

    testWidgets('usage never fabricates counts when unavailable',
        (tester) async {
      await _pump(tester, const UsageDetailsView());
      expect(find.text(_t('subUsageUnavailable')), findsOneWidget);
      expect(find.text(_t('subEditsUnavailable')), findsOneWidget);
      expect(find.textContaining(' of 5'), findsNothing);
    });

    testWidgets('usage loading and empty states', (tester) async {
      await _pump(
        tester,
        const UsageDetailsView(),
        presentation: SubscriptionSamples.freeLoading,
      );
      expect(find.text(_t('subUsageLoading')), findsOneWidget);
      await _pump(
        tester,
        const UsageDetailsView(),
        presentation: SubscriptionSamples.freeEmpty,
      );
      expect(find.text(_t('subUsageEmpty')), findsOneWidget);
      expect(find.text('0 of 5'), findsNWidgets(11));
    });
  });

  group('plan states', () {
    testWidgets('Free shows the allowances and all categories', (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.free,
      );
      expect(find.text(_t('subPlanFree')), findsOneWidget);
      expect(find.text(_t('subAllowanceCreations')), findsOneWidget);
      expect(find.text(_t('subAllowanceEdits')), findsOneWidget);
      expect(find.textContaining(' of 5'), findsNWidgets(11));
    });

    testWidgets('active Plus shows verified details', (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.renewing,
      );
      expect(find.text('Plus · Annual'), findsOneWidget);
      expect(find.text(_t('subAutoRenewOn')), findsOneWidget);
      expect(find.text('1 Jan 2028'), findsOneWidget);
      expect(find.textContaining('180.00'), findsOneWidget);
      expect(find.text(_t('subProviderGooglePlay')), findsOneWidget);
    });

    testWidgets('canceled Plus stays active with no next charge',
        (tester) async {
      final p = SubscriptionSamples.cancelScheduled;
      expect(p.hasVerifiedPlus, isTrue);
      expect(p.nextPaymentDate, isNull);
      await _pump(tester, const MyPlanView(), presentation: p);
      expect(
        find.text('Plus remains active until 1 Feb 2027. Auto-renewal is off.'),
        findsOneWidget,
      );
      expect(find.text(_t('subPillAutoRenewOff')), findsOneWidget);
      expect(find.text(_t('subNoNextCharge')), findsOneWidget);
      expect(find.text(_t('subPlanFree')), findsNothing);
    });

    testWidgets('a next charge is hidden unless auto-renewal is on', (_) async {
      final p = SubscriptionPresentation(
        status: SubscriptionStatus.plusCancelScheduled,
        nextChargeAt: DateTime(2027, 2, 1),
      );
      expect(p.nextPaymentDate, isNull);
    });

    testWidgets('expired over limit is read-only and keeps records',
        (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.expiredOverLimit,
      );
      expect(
        find.text(
          'Your Plus subscription has ended. Your records are safe and '
          'available to view and share. Adding new records and editing '
          'existing content are paused until Plus is reactivated.',
        ),
        findsOneWidget,
      );
      expect(find.text(_t('subReadOnlyCreationPaused')), findsOneWidget);
      expect(find.text(_t('subReadOnlyEditingPaused')), findsOneWidget);
      expect(find.text('50 of 5'), findsOneWidget);
      // Reactivate only leads to the plans; the notice says nothing can be
      // bought yet, and the payment sheet's own action stays disabled.
      expect(_filled(tester, _t('subReactivatePlus')).onPressed, isNotNull);
      expect(find.text(_t('subPurchasesNotConnected')), findsOneWidget);
    });

    testWidgets('return to Free is a separate state', (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.expiredWithinFree,
      );
      expect(find.text(_t('subBackOnFreeTitle')), findsOneWidget);
      expect(find.text(_t('subRemainingAllowances')), findsOneWidget);
      expect(find.text(_t('subExpiredMessage')), findsNothing);
    });

    testWidgets('Manage covers every state', (tester) async {
      final expected = {
        SubscriptionSamples.renewing: 'subAutoRenewOnTitle',
        SubscriptionSamples.expiredOverLimit: 'subManageExpiredTitle',
        SubscriptionSamples.paymentIssue: 'subPaymentIssueTitle',
        SubscriptionSamples.activationPending: 'subActivationPendingTitle',
        SubscriptionSamples.unknown: 'subManageUnknownTitle',
      };
      for (final entry in expected.entries) {
        await _pump(
          tester,
          const ManageSubscriptionView(),
          presentation: entry.key,
        );
        expect(find.text(_t(entry.value)), findsOneWidget, reason: entry.value);
      }
      await _pump(
        tester,
        const ManageSubscriptionView(),
        presentation: SubscriptionSamples.cancelScheduled,
      );
      expect(find.textContaining('Auto-renewal is off'), findsOneWidget);
    });

    testWidgets('cancellation avoids refund promises', (tester) async {
      await _pump(tester, const CancellationInfoView());
      expect(find.text(_t('subCancelNoRefund')), findsOneWidget);
      expect(find.text(_t('subCancelDeleteApp')), findsOneWidget);
      expect(find.text(_t('subCancelRefundRules')), findsOneWidget);
      final all = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();
      expect(all, isNot(contains('non-refundable')));
      expect(all, isNot(contains('you will be refunded')));
    });

    testWidgets('billing never invents payment history', (tester) async {
      await _pump(tester, const BillingPaymentsView());
      expect(find.text(_t('billingUnavailable')), findsOneWidget);
      expect(find.text(_t('purchaseHistoryUnavailable')), findsOneWidget);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.text(_t('subNextCharge')), findsNothing);
    });
  });

  group('review fixes', () {
    for (final sample in [
      SubscriptionSamples.paymentIssue,
      SubscriptionSamples.activationPending,
    ]) {
      testWidgets('${sample.status.name} is never offered a second purchase',
          (tester) async {
        await _pump(tester, const SubscriptionView(), presentation: sample);
        expect(find.text(_t('subSubscribeToPlus')), findsNothing);
        expect(find.textContaining('180.00'), findsNothing);
        expect(find.text(_t('subManageSubscription')), findsOneWidget);
        expect(find.text(_t('subPillActive')), findsNothing);
      });
    }

    testWidgets('return to Free words the allowances as remaining',
        (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.expiredWithinFree,
      );
      expect(find.text('2 of 5 left'), findsOneWidget); // Owners: 3 used.
      expect(find.text('0 of 5 left'), findsNWidgets(3));
      expect(find.text('5 of 5 left'), findsNWidgets(2));
    });

    testWidgets('Toolkit rules cover deletion and document edits',
        (tester) async {
      await _pump(tester, const HowLimitsWorkView());
      expect(find.text(_t('subLimitsToolkitBlocked')), findsOneWidget);
      expect(find.text(_t('subLimitsToolkitKeep')), findsOneWidget);
      expect(find.text(_t('subLimitsToolkitDelete')), findsOneWidget);
      expect(find.text(_t('subLimitsToolkitEdits')), findsOneWidget);
    });

    test('the Profile summary never upgrades an unknown status', () async {
      final loc = AppLocalizations(const Locale('en'));
      await loc.load();
      const unknown = SubscriptionPresentation.unavailable();
      expect(loc.planLine(unknown), _t('planStatusUnavailable'));
      expect(loc.billingLine(unknown), _t('subBillingNotConnected'));
      expect(
        loc.planLine(SubscriptionSamples.cancelScheduled),
        'Plus · Active until 1 Feb 2027',
      );
      expect(
        loc.planLine(SubscriptionSamples.renewing),
        'Plus · Annual · Renews 1 Jan 2028',
      );
    });

    testWidgets('comparison stacks instead of splitting words on large text',
        (tester) async {
      await _pump(
        tester,
        const PlanCompareView(),
        size: const Size(320, 4200),
        textScale: 2,
      );
      expect(find.text(_t('subFeature')), findsNothing);
      expect(find.text(_t('subPlanFree')), findsNWidgets(9));
      expect(find.text(_t('subPlanPlus')), findsNWidgets(9));

      await _pump(tester, const PlanCompareView());
      expect(find.text(_t('subFeature')), findsOneWidget);
      expect(find.text(_t('subPlanFree')), findsOneWidget);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('stacked detail rows start at the text edge in $lang',
          (tester) async {
        await _pump(
          tester,
          const MyPlanView(),
          presentation: SubscriptionSamples.renewing,
          lang: lang,
          size: const Size(320, 6000),
          textScale: 2,
        );
        final label = tester.getRect(find.text(_t('subBillingCycle', lang)));
        final card = tester.getRect(
          find
              .ancestor(
                of: find.text(_t('subBillingCycle', lang)),
                matching: find.byType(SubCard),
              )
              .first,
        );
        const inset = 16 + 1.5;
        if (lang == 'ar') {
          expect(label.right, moreOrLessEquals(card.right - inset, epsilon: 1));
        } else {
          expect(label.left, moreOrLessEquals(card.left + inset, epsilon: 1));
        }
      });
    }

    test('every sample is labelled as a sample', () {
      for (final (_, sample) in SubscriptionSamples.plans) {
        expect(sample.isSample, isTrue);
      }
    });
  });

  group('no fake payment results', () {
    testWidgets('production plan selection cannot continue to payment',
        (tester) async {
      await _pump(tester, const SubscriptionView());
      expect(find.text(_t('subPurchasesNotConnected')), findsOneWidget);
      await _openPlanSheet(tester);
      expect(_filled(tester, _t('subContinueGoogle')).onPressed, isNull);
      expect(find.text(_t('subPayNotConnected')), findsOneWidget);
    });

    testWidgets('manage and cancellation cannot act', (tester) async {
      await _pump(
        tester,
        const ManageSubscriptionView(),
        presentation: SubscriptionSamples.renewing,
      );
      expect(
        _filled(tester, 'Manage in ${_t('subProviderGooglePlay')}').onPressed,
        isNull,
      );
      await _pump(tester, const CancellationInfoView());
      expect(
        _filled(tester, 'Continue to ${_t('subYourAppStore')}').onPressed,
        isNull,
      );
    });

    testWidgets('restore defaults to unavailable and cannot run',
        (tester) async {
      await _pump(tester, const RestorePurchasesView());
      expect(find.text(_t('subRestoreUnavailableTitle')), findsOneWidget);
      expect(_filled(tester, _t('tryAgain')).onPressed, isNull);
    });

    testWidgets('restored state cannot render outside a sample',
        (tester) async {
      await _pump(
        tester,
        const RestorePurchasesView(state: RestorePurchaseState.restored),
      );
      expect(find.text(_t('subRestoreDoneTitle')), findsNothing);
      expect(find.text(_t('subRestoreUnavailableTitle')), findsOneWidget);
    });

    testWidgets('activation success cannot render outside a sample',
        (tester) async {
      await _pump(
        tester,
        const SubscriptionFlowStateView(
          state: SubscriptionFlowState.activationSuccess,
        ),
      );
      expect(find.text(_t('subFlowSuccessTitle')), findsNothing);
      expect(find.text(_t('subFlowVerifyTitle')), findsOneWidget);
    });

    testWidgets('samples always carry the visible banner', (tester) async {
      await _pump(
        tester,
        const SubscriptionFlowStateView(
          state: SubscriptionFlowState.activationSuccess,
        ),
        presentation: SubscriptionSamples.renewing,
      );
      expect(find.text(_t('subFlowSuccessTitle')), findsOneWidget);
      expect(find.text(_t('subSampleBanner')), findsOneWidget);
    });

    test('the module adds no payment package or external checkout', () {
      final dir = Directory(
        'lib/src/views/Screens/home/Profile/SubscriptionPlan',
      );
      final banned = RegExp(
        r'in_app_purchase|purchases_flutter|RevenueCat|stripe|url_launcher|'
        r'launchUrl|https?://',
        caseSensitive: false,
      );
      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('subscription_viewmodel.dart')) continue;
        expect(banned.hasMatch(file.readAsStringSync()), isFalse,
            reason: file.path);
      }
    });
  });

  group('platform payment policy', () {
    const production = SubscriptionPresentation.unavailable();
    const verified = SubscriptionPresentation(
      status: SubscriptionStatus.free,
      tapCardEligibilityVerified: true,
    );

    test('production Android offers Google Play only', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          production,
          debugBuild: false,
        ),
        [PaymentOption.googlePlay],
      );
    });

    test('a sample cannot unlock Card outside a debug build', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          SubscriptionSamples.free,
          debugBuild: false,
        ),
        [PaymentOption.googlePlay],
      );
      expect(
        SubscriptionPlatformPolicy.canPreviewCheckout(
          SubscriptionSamples.free,
          debugBuild: false,
        ),
        isFalse,
      );
    });

    test('debug preview shows both Android options', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          SubscriptionSamples.free,
          debugBuild: true,
        ),
        [PaymentOption.googlePlay, PaymentOption.tapCard],
      );
    });

    test('only a future verified decision enables Card in production', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          verified,
          debugBuild: false,
        ),
        [PaymentOption.googlePlay, PaymentOption.tapCard],
      );
      expect(production.tapCardEligibilityVerified, isFalse);
    });

    test('only the server channel policy can turn card eligibility on', () {
      // The server-state mapping forwards its parameter, and the controller
      // fills that parameter from the server's channel answer and nothing else.
      final setters = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path
              .replaceAll(r'\', '/')
              .endsWith('subscription/subscription_server_state.dart'))
          .where((f) => RegExp(r'tapCardEligibilityVerified:\s*(true|[a-z])')
              .hasMatch(f.readAsStringSync()));
      expect(setters, isEmpty);
      expect(
        File('lib/src/viewmodels/subscription_state_controller.dart')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), ''),
        contains('tapCardEligibilityVerified:_channels.androidCardChoice'),
      );
    });

    test('iPhone never receives a payment option', () {
      for (final p in [production, verified, SubscriptionSamples.free]) {
        for (final debugBuild in [true, false]) {
          expect(
            SubscriptionPlatformPolicy.paymentOptions(
              SubscriptionPlatform.ios,
              p,
              debugBuild: debugBuild,
            ),
            isEmpty,
          );
        }
      }
    });

    test('each provider keeps its own management path', () {
      ManagementPath path(SubscriptionPlatform pf, BillingProvider? pr) =>
          SubscriptionPlatformPolicy.managementPath(pf, pr);
      const android = SubscriptionPlatform.android;
      const ios = SubscriptionPlatform.ios;
      expect(
          path(android, BillingProvider.googlePlay), ManagementPath.thisStore);
      expect(path(ios, BillingProvider.appStore), ManagementPath.thisStore);
      expect(
          path(android, BillingProvider.appStore), ManagementPath.otherStore);
      expect(path(ios, BillingProvider.googlePlay), ManagementPath.otherStore);
      expect(path(android, BillingProvider.tap), ManagementPath.tapBilling);
      expect(path(ios, BillingProvider.tap), ManagementPath.notOnThisDevice);
      expect(path(android, null), ManagementPath.none);
    });
  });

  group('Android payment sheet', () {
    testWidgets('production shows Google Play only, and cannot continue',
        (tester) async {
      await _pump(tester, const SubscriptionView());
      await _openPlanSheet(tester);
      expect(find.byType(PaymentMethodSheet), findsOneWidget);
      expect(find.text(_t('subPayCardTitle')), findsNothing);
      expect(find.textContaining('Tap Payments'), findsNothing);
      expect(_filled(tester, _t('subContinueGoogle')).onPressed, isNull);
    });

    for (final (cycleKey, price) in const [
      ('subCycleAnnual', 'AED 180.00 / year'),
      ('subCycleMonthly', 'AED 20.00 / month'),
    ]) {
      testWidgets('$cycleKey carries the correct price into the sheet',
          (tester) async {
        await _pump(
          tester,
          const SubscriptionView(),
          presentation: SubscriptionSamples.free,
        );
        if (cycleKey == 'subCycleMonthly') {
          await tester.tap(find.text(_t('subCycleMonthly')));
          await tester.pumpAndSettle();
        }
        await _openPlanSheet(tester, cycleKey: cycleKey);
        expect(
          find.descendant(
            of: find.byType(PaymentMethodSheet),
            matching: find.text(price),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('switching method updates description and CTA, not size',
        (tester) async {
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionSamples.free,
      );
      await _openPlanSheet(tester);
      final before = tester.getSize(find.byType(PaymentMethodSheet));
      expect(find.text(_t('subContinueGoogle')), findsOneWidget);
      expect(_opacityOf(tester, _t('subPayGoogleBody')), 1);
      expect(_opacityOf(tester, _t('subPayCardBody')), 0);

      await tester.tap(find.text(_t('subPayCardTitle')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(find.byType(PaymentMethodSheet)), before);
      await tester.pumpAndSettle();

      expect(find.text(_t('subContinueCard')), findsOneWidget);
      expect(find.text(_t('subContinueGoogle')), findsNothing);
      expect(_opacityOf(tester, _t('subPayCardBody')), 1);
      expect(_opacityOf(tester, _t('subPayGoogleBody')), 0);
      expect(tester.getSize(find.byType(PaymentMethodSheet)), before);

      await tester.tap(find.text(_t('subProviderGooglePlay')).first);
      await tester.pumpAndSettle();
      expect(find.text(_t('subContinueGoogle')), findsOneWidget);
    });

    testWidgets('card copy promises no raw card handling', (tester) async {
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionSamples.free,
      );
      await _openPlanSheet(tester);
      expect(find.byType(TextField), findsNothing);
      expect(_t('subPayCardSecure'), contains('never collects or stores'));
      expect(_t('subPayCardBody'), contains('Tap Payments'));
    });

    testWidgets('renewal and cancellation stay honest', (tester) async {
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionSamples.free,
      );
      await _openPlanSheet(tester);
      expect(
        find.text('Renews automatically every year at AED 180.00 until you '
            'cancel.'),
        findsNWidgets(2),
      );
      expect(_t('subPayCancelGoogle'), contains("doesn't automatically"));
      expect(_t('subPayCancelGoogle'), contains('Google Play'));
      expect(_t('subPayCancelCard'), isNot(contains('Google Play')));
    });

    for (final (name, dismiss)
        in <(String, Future<void> Function(WidgetTester))>[
      (
        'close button',
        (t) => t.tap(find.byTooltip(_t('subClose'))),
      ),
      (
        'back to plans',
        (t) => t.tap(find.text(_t('subBackToPlans'))),
      ),
      ('barrier', (t) => t.tapAt(const Offset(10, 10))),
      ('system back', (t) => t.binding.handlePopRoute()),
    ]) {
      testWidgets('$name dismisses the sheet and stays on plans',
          (tester) async {
        await _pump(
          tester,
          const SubscriptionView(),
          presentation: SubscriptionSamples.free,
        );
        await _openPlanSheet(tester);
        await dismiss(tester);
        await tester.pumpAndSettle();
        expect(find.byType(PaymentMethodSheet), findsNothing);
        expect(find.byType(SubscriptionView), findsOneWidget);
      });
    }

    testWidgets('sample review shows the choice and cannot charge',
        (tester) async {
      await _pumpRouter(tester, presentation: SubscriptionSamples.free);
      await _openPlanSheet(tester);
      await tester.tap(find.text(_t('subPayCardTitle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_t('subContinueCard')));
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionFlowStateView), findsOneWidget);
      expect(find.text(_t('subPayCardTap')), findsOneWidget);
      expect(find.text('AED 180.00'), findsOneWidget);
      expect(find.text(_t('subReviewDateAfterConfirm')), findsOneWidget);
      expect(find.text(_t('subReviewNoCharge')), findsOneWidget);
      expect(find.text(_t('subSampleBanner')), findsOneWidget);
      expect(find.text(_t('termsConditions')), findsOneWidget);
      expect(find.text(_t('privacyPolicy')), findsOneWidget);
      expect(
        _filled(tester, 'Subscribe · AED 180.00 / year').onPressed,
        isNull,
      );
      expect(find.text(_t('subFlowSuccessTitle')), findsNothing);
    });

    for (final state in [
      PaymentSheetState.loading,
      PaymentSheetState.providerUnavailable,
    ]) {
      testWidgets('${state.name} sheet cannot continue', (tester) async {
        await _pump(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PaymentMethodSheet(
                cycle: PlusBillingCycle.annual,
                options: const [
                  PaymentOption.googlePlay,
                  PaymentOption.tapCard,
                ],
                canContinue: true,
                sheetState: state,
              ),
            ),
          ),
        );
        expect(_filled(tester, _t('subContinueGoogle')).onPressed, isNull);
        expect(
          find.text(
            state == PaymentSheetState.loading
                ? _t('subPayLoading')
                : _t('subPayProviderUnavailableTitle'),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('tiles expose selection and tap to screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionSamples.free,
      );
      await _openPlanSheet(tester);
      final label = '${_t('subPayCardTitle')}, ${_t('subProviderTap')}';
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
          isButton: true,
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isChecked: true),
      );
      expect(find.text(_t('subContinueCard')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('tiles mirror in RTL', (tester) async {
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionSamples.free,
        lang: 'ar',
      );
      await _openPlanSheet(tester, lang: 'ar');
      final play = tester.getCenter(find.text('Google Play').first);
      final card = tester.getCenter(find.text(_t('subPayCardTitle', 'ar')));
      expect(play.dx, greaterThan(card.dx));
    });

    testWidgets('tiles stack on narrow large-text layouts', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PaymentMethodSheet(
              cycle: PlusBillingCycle.annual,
              options: [PaymentOption.googlePlay, PaymentOption.tapCard],
              canContinue: false,
            ),
          ),
        ),
        size: const Size(320, 2400),
        textScale: 2,
      );
      final play = tester.getBottomLeft(find.text('Google Play').first);
      final card = tester.getTopLeft(find.text(_t('subPayCardTitle')));
      expect(card.dy, greaterThan(play.dy));
    });
  });

  group('iPhone experience', () {
    final iphone = TargetPlatformVariant.only(TargetPlatform.iOS);

    for (final lang in ['en', 'ar']) {
      testWidgets('plans show no payment path in $lang', (tester) async {
        await _pump(
          tester,
          const SubscriptionView(),
          presentation: SubscriptionSamples.free,
          lang: lang,
        );
        expect(find.text(_t('subViewPlanDetails', lang)), findsOneWidget);
        expect(find.text(_t('restorePurchases', lang)), findsNothing);
        expect(find.text(_t('subRenewalDisclosure', lang)), findsNothing);
        expect(_iosForbidden.hasMatch(_allText(tester)), isFalse,
            reason: _iosForbidden.firstMatch(_allText(tester))?.group(0));
      }, variant: iphone);

      testWidgets('the plan sheet is informational in $lang', (tester) async {
        await _pump(
          tester,
          const SubscriptionView(),
          presentation: SubscriptionSamples.free,
          lang: lang,
        );
        await tester.tap(find.text(_t('subViewPlanDetails', lang)));
        await tester.pumpAndSettle();
        expect(find.byType(PlanInfoSheet), findsOneWidget);
        expect(find.byType(PaymentMethodSheet), findsNothing);
        final sheet = tester
            .widgetList<Text>(find.descendant(
              of: find.byType(PlanInfoSheet),
              matching: find.byType(Text),
            ))
            .map((t) => t.data ?? '')
            .join('\n');
        expect(_iosForbidden.hasMatch(sheet), isFalse,
            reason: _iosForbidden.firstMatch(sheet)?.group(0));
        await tester.tap(find.text(_t('subGotIt', lang)));
        await tester.pumpAndSettle();
        expect(find.byType(PlanInfoSheet), findsNothing);
        expect(find.byType(SubscriptionView), findsOneWidget);
      }, variant: iphone);
    }

    testWidgets('even a verified decision shows no payment choice',
        (tester) async {
      await _pump(
        tester,
        const SubscriptionView(),
        presentation: SubscriptionPresentation(
          status: SubscriptionStatus.free,
          tapCardEligibilityVerified: true,
        ),
      );
      await tester.tap(find.text(_t('subViewPlanDetails')));
      await tester.pumpAndSettle();
      expect(find.byType(PlanInfoSheet), findsOneWidget);
      expect(find.byType(PaymentMethodSheet), findsNothing);
    }, variant: iphone);

    testWidgets('a Tap subscription is shown without naming Tap',
        (tester) async {
      for (final screen in const <Widget>[
        MyPlanView(),
        ManageSubscriptionView(),
        BillingPaymentsView(),
      ]) {
        await _pump(
          tester,
          screen,
          presentation: SubscriptionSamples.tapManaged,
        );
        expect(_iosForbidden.hasMatch(_allText(tester)), isFalse,
            reason: '$screen: '
                '${_iosForbidden.firstMatch(_allText(tester))?.group(0)}');
      }
      await _pump(
        tester,
        const ManageSubscriptionView(),
        presentation: SubscriptionSamples.tapManaged,
      );
      expect(find.text(_t('subManagedNotHere')), findsOneWidget);
    }, variant: iphone);

    testWidgets('no reachable iPhone screen shows a payment path',
        (tester) async {
      const tapIssue = SubscriptionPresentation(
        status: SubscriptionStatus.paymentIssue,
        provider: BillingProvider.tap,
        cycle: PlusBillingCycle.monthly,
        isSample: true,
      );
      final states = <SubscriptionPresentation>[
        const SubscriptionPresentation.unavailable(),
        SubscriptionSamples.free,
        SubscriptionSamples.freeEmpty,
        SubscriptionSamples.expiredOverLimit.copyWithoutProvider(),
        SubscriptionSamples.expiredWithinFree.copyWithoutProvider(),
        SubscriptionSamples.offline,
        SubscriptionSamples.tapManaged,
        tapIssue,
      ];
      const screens = <Widget>[
        MyPlanView(),
        SubscriptionView(),
        PlanCompareView(),
        HowLimitsWorkView(),
        UsageDetailsView(),
        ManageSubscriptionView(),
        BillingPaymentsView(),
      ];
      for (final lang in ['en', 'ar']) {
        for (final state in states) {
          for (final screen in screens) {
            await _pump(tester, screen, presentation: state, lang: lang);
            final text = _allText(tester);
            expect(_iosForbidden.hasMatch(text), isFalse,
                reason: '${state.status.name} $screen $lang: '
                    '${_iosForbidden.firstMatch(text)?.group(0)}');
          }
        }
      }
    }, variant: iphone);

    testWidgets('expired Plus offers plans, not a payment action',
        (tester) async {
      await _pump(
        tester,
        const MyPlanView(),
        presentation: SubscriptionSamples.expiredOverLimit,
      );
      expect(find.text(_t('subReactivatePlus')), findsNothing);
      expect(find.text(_t('subViewPlusPlans')), findsOneWidget);
      expect(find.text(_t('subPurchasesNotConnected')), findsNothing);
      expect(find.text(_t('subExpiredMessage')), findsOneWidget);
    }, variant: iphone);

    testWidgets('billing hides receipts, payment method and restore',
        (tester) async {
      await _pump(tester, const BillingPaymentsView());
      expect(find.text(_t('billingUnavailable')), findsOneWidget);
      expect(find.text(_t('subBillingNoPurchaseHere')), findsOneWidget);
      expect(find.text(_t('paymentMethod')), findsNothing);
      expect(find.text(_t('subReceipts')), findsNothing);
      expect(find.text(_t('restorePurchases')), findsNothing);
    }, variant: iphone);
  });

  group('provider ownership on Android', () {
    testWidgets('Tap billing is not offered a Google Play action',
        (tester) async {
      await _pump(
        tester,
        const ManageSubscriptionView(),
        presentation: SubscriptionSamples.tapManaged,
      );
      expect(find.text(_t('subManagedByTap')), findsOneWidget);
      expect(
          find.text('Manage in ${_t('subProviderGooglePlay')}'), findsNothing);
    });

    testWidgets('an App Store subscription keeps its store path',
        (tester) async {
      await _pump(
        tester,
        const ManageSubscriptionView(),
        presentation: SubscriptionSamples.renewingAppStore,
      );
      expect(
        find.text(
          _t('subManagedInOtherStore').replaceAll('{store}', 'App Store'),
        ),
        findsOneWidget,
      );
      expect(find.text('Manage in App Store'), findsNothing);
    });
  });

  group('debug preview isolation', () {
    test('the module has no way to write real state', () {
      final dir = Directory(
        'lib/src/views/Screens/home/Profile/SubscriptionPlan',
      );
      final banned = RegExp(
        r'SharedPreferences|Hive\.|Supabase|FirebaseFirestore|\.rpc\(|'
        r'\.from\(|fromEnvironment|repositories/|url_launcher|launchUrl',
      );
      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('subscription_viewmodel.dart')) continue;
        expect(banned.hasMatch(file.readAsStringSync()), isFalse,
            reason: file.path);
      }
    });

    test('preview overrides are guarded by kDebugMode', () {
      const base = 'lib/src/views/Screens/home/Profile/SubscriptionPlan/';
      expect(
        File('${base}subscription_scope.dart').readAsStringSync(),
        contains('kDebugMode && debugPreview != null'),
      );
      expect(
        File('${base}subscription_platform_policy.dart').readAsStringSync(),
        contains('kDebugMode && debugOverride != null'),
      );
      expect(
        File('lib/src/views/Screens/home/Profile/my_plan_view.dart')
            .readAsStringSync(),
        contains('kDebugMode && !p.isSample'),
      );
    });

    testWidgets('leaving a previewed sheet clears every override',
        (tester) async {
      await _pumpRouter(
        tester,
        presentation: const SubscriptionPresentation.unavailable(),
        initial: SubscriptionRoutes.preview,
      );
      await tester.tap(find.text('Annual, Card selected'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodSheet), findsOneWidget);
      expect(SubscriptionScope.debugPreview, isNotNull);
      expect(
        SubscriptionPlatformPolicy.debugOverride,
        SubscriptionPlatform.android,
      );
      expect(find.text(_t('subContinueCard')), findsOneWidget);

      await tester.tap(find.byTooltip(_t('subClose')));
      await tester.pumpAndSettle();
      expect(SubscriptionScope.debugPreview, isNull);
      expect(SubscriptionPlatformPolicy.debugOverride, isNull);
    });

    testWidgets('the iPhone preview shows the information sheet',
        (tester) async {
      await _pumpRouter(
        tester,
        presentation: const SubscriptionPresentation.unavailable(),
        initial: SubscriptionRoutes.preview,
      );
      await tester.tap(find.text('Plan information, Monthly'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanInfoSheet), findsOneWidget);
      expect(find.byType(PaymentMethodSheet), findsNothing);
      await tester.tap(find.text(_t('subGotIt')));
      await tester.pumpAndSettle();
      expect(SubscriptionPlatformPolicy.debugOverride, isNull);
    });

    testWidgets('the production-gate preview has no Card and no continue',
        (tester) async {
      await _pumpRouter(
        tester,
        presentation: const SubscriptionPresentation.unavailable(),
        initial: SubscriptionRoutes.preview,
      );
      await tester.tap(find.text('Production gate: Google Play only'));
      await tester.pumpAndSettle();
      expect(find.text(_t('subPayCardTitle')), findsNothing);
      expect(_filled(tester, _t('subContinueGoogle')).onPressed, isNull);
      await tester.tap(find.byTooltip(_t('subClose')));
      await tester.pumpAndSettle();
    });
  });

  group('navigation', () {
    testWidgets('My Plan reaches each destination and returns', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 4200);
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/my-plan'),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/my-plan',
            builder: (context, state) => const MyPlanView(),
          ),
          GoRoute(
            path: '/subscription',
            builder: (context, state) => const SubscriptionView(),
          ),
          GoRoute(
            path: '/billing-payments',
            builder: (context, state) => const BillingPaymentsView(),
          ),
          ...subscriptionProfileRoutes(),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: _delegates,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final destinations = <String, Type>{
        _t('subscriptions'): SubscriptionView,
        _t('subUsageTitle'): UsageDetailsView,
        _t('subHowLimitsTitle'): HowLimitsWorkView,
        _t('subManageSubscription'): ManageSubscriptionView,
        _t('billingPayments'): BillingPaymentsView,
      };
      for (final entry in destinations.entries) {
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new).last);
        await tester.pumpAndSettle();
        expect(find.byType(MyPlanView), findsOneWidget, reason: entry.key);
      }
    });

    test('preview routes exist only in debug builds', () {
      final source = File(
        'lib/src/views/Screens/home/Profile/SubscriptionPlan/'
        'subscription_routes.dart',
      ).readAsStringSync();
      final guard = source.indexOf('if (kDebugMode)');
      expect(guard, greaterThan(0));
      expect(source.indexOf('SubscriptionRoutes.preview'), greaterThan(guard));
      expect(
          source.indexOf('SubscriptionRoutes.flowState'), greaterThan(guard));
    });
  });

  group('layout', () {
    final samples = <SubscriptionPresentation>[
      const SubscriptionPresentation.unavailable(),
      ...SubscriptionSamples.plans.map((e) => e.$2),
    ];
    final screens = <Widget>[
      const MyPlanView(),
      const SubscriptionView(),
      const PlanCompareView(),
      const HowLimitsWorkView(),
      const UsageDetailsView(),
      const ManageSubscriptionView(),
      const CancellationInfoView(),
      const BillingPaymentsView(),
      for (final s in RestorePurchaseState.values)
        RestorePurchasesView(state: s),
      for (final s in SubscriptionFlowState.values)
        SubscriptionFlowStateView(state: s),
    ];

    for (final lang in ['en', 'ar']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('no overflow at 320 px, $lang, ${mode.name}',
            (tester) async {
          for (final sample in samples) {
            for (final screen in screens) {
              await _pump(
                tester,
                screen,
                presentation: sample,
                lang: lang,
                mode: mode,
                size: const Size(320, 9000),
                textScale: 2,
              );
              expect(tester.takeException(), isNull);
            }
          }
        });
      }

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('sheets fit a small phone, $lang, ${mode.name}',
            (tester) async {
          final sheets = <Widget>[
            for (final cycle in PlusBillingCycle.values) ...[
              PlanInfoSheet(cycle: cycle),
              for (final state in PaymentSheetState.values)
                for (final options in const [
                  [PaymentOption.googlePlay],
                  [PaymentOption.googlePlay, PaymentOption.tapCard],
                ])
                  PaymentMethodSheet(
                    cycle: cycle,
                    options: options,
                    canContinue: false,
                    sheetState: state,
                  ),
            ],
          ];
          for (final textScale in [1.0, 1.3, 2.0]) {
            for (final size in const [Size(320, 568), Size(360, 740)]) {
              for (final sheet in sheets) {
                await _pump(
                  tester,
                  Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: Material(child: sheet),
                    ),
                  ),
                  lang: lang,
                  mode: mode,
                  size: size,
                  textScale: textScale,
                );
                expect(tester.takeException(), isNull);
              }
            }
          }
        });
      }

      testWidgets('direction follows the language: $lang', (tester) async {
        await _pump(tester, const MyPlanView(), lang: lang);
        expect(
          Directionality.of(tester.element(find.byType(ListView))),
          lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  });
}
