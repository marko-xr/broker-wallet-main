import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/views/Screens/home/Toolkit/combine_pdfs_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../combine_pdf/combine_fixtures.dart';
import 'responsive_harness.dart';

class _OfflineGate implements CombineUsageGate {
  @override
  Future<bool> allowNewCombine(BuildContext context, String userId) async =>
      true;

  @override
  Future<void> recordCombine(String userId) async {}
}

void main() {
  setUpAll(prepareResponsiveAssets);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const scenarios = [
    ResponsiveCase(Size(280, 600)),
    ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.3),
    ResponsiveCase(Size(360, 640), dark: true, textScale: 1.6),
    ResponsiveCase(Size(430, 932)),
    ResponsiveCase(Size(640, 360), textScale: 2),
    ResponsiveCase(Size(600, 800), locale: Locale('ar'), dark: true),
    ResponsiveCase(Size(800, 600)),
    ResponsiveCase(
      Size(393, 852),
      locale: Locale('ar'),
      textScale: 1.3,
      safeArea: EdgeInsets.only(top: 28, bottom: 20),
      keyboard: 300,
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('Combine PDFs empty library: $scenario', (tester) async {
      final fixture = CombineHarness();
      addTearDown(fixture.dispose);
      await tester.runAsync(fixture.viewModel.start);
      await pumpResponsive(
        tester,
        scenario,
        home: CombinePdfsView(
          viewModel: fixture.viewModel,
          usageGate: _OfflineGate(),
        ),
      );
      expect(fixture.viewModel.isLoading, isFalse);
      final action = find.text(AppLocalizations.translateFor(
          scenario.locale.languageCode, 'createFirstPdf')!);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });
  }

  for (final scenario in const [
    ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6),
    ResponsiveCase(Size(393, 852)),
    ResponsiveCase(Size(640, 360), dark: true, textScale: 2),
  ]) {
    testWidgets('Combine PDFs populated library: $scenario', (tester) async {
      final fixture = CombineHarness();
      addTearDown(fixture.dispose);
      final documentName = scenario.locale.languageCode == 'ar'
          ? 'اتفاقية الإيجار التجاري للعقار في دبي'
          : 'Commercial tenancy agreement for Marina office';
      await tester.runAsync(() async {
        await fixture.viewModel.start();
        final first = await fixture.pdf('lease.pdf', 'L');
        final second = await fixture.pdf('plan.pdf', 'P');
        await fixture.add([first, second]);
        await fixture.combine(name: documentName);
      });
      await pumpResponsive(
        tester,
        scenario,
        home: CombinePdfsView(
          viewModel: fixture.viewModel,
          usageGate: _OfflineGate(),
        ),
      );
      final document = find.text(documentName);
      await tester.scrollUntilVisible(document, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(document);
      await tester.pumpAndSettle();
      expect(document, findsWidgets);
      expectNoLayoutException(tester, scenario);
    });
  }
}
