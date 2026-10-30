import 'package:broker_wallet/src/views/Screens/home/Toolkit/toolkit_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);

  const scenarios = [
    ResponsiveCase(Size(280, 600)),
    ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.3),
    ResponsiveCase(Size(360, 640), dark: true, textScale: 1.6),
    ResponsiveCase(Size(393, 852), locale: Locale('ar')),
    ResponsiveCase(Size(430, 932), dark: true),
    ResponsiveCase(Size(640, 360), textScale: 2),
    ResponsiveCase(Size(600, 800), locale: Locale('ar'), dark: true),
    ResponsiveCase(Size(800, 600), textScale: 1.3),
    ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      textScale: 2,
      safeArea: EdgeInsets.only(top: 32, bottom: 24),
    ),
  ];

  for (final scenario in scenarios) {
    testWidgets('Toolkit route layout and reachable cards: $scenario',
        (tester) async {
      await pumpResponsive(tester, scenario, home: const ToolkitView());
      expect(find.byType(ToolkitView), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);

      // The last tool must remain reachable even on a short window.
      final label = AppLocalizations.translateFor(
          scenario.locale.languageCode, 'uaeLinks');
      final lastCard = find.text(label!);
      // Use the production card type via its semantic action; scrolling the
      // grid is part of the reachability check.
      await tester.scrollUntilVisible(lastCard, 120,
          scrollable: find.byType(Scrollable).last);
      expect(lastCard, findsOneWidget);
      await tester.ensureVisible(lastCard);
      await tester.pumpAndSettle();
      final cardCenter = tester.getCenter(lastCard);
      expect(cardCenter.dx, inInclusiveRange(0, scenario.size.width));
      expect(cardCenter.dy, inInclusiveRange(0, scenario.size.height));
      await tester.pumpAndSettle();
      expectNoLayoutException(tester, scenario);
    });
  }
}
