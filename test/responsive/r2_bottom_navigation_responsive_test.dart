import 'package:broker_wallet/src/views/Widgets/bottom_nav_bar.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);

  final cases = <ResponsiveCase>[
    const ResponsiveCase(Size(280, 600)),
    const ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      textScale: 1.6,
    ),
    const ResponsiveCase(Size(360, 640), dark: true, textScale: 2),
    const ResponsiveCase(
      Size(430, 932),
      locale: Locale('ar'),
      dark: true,
      safeArea: EdgeInsets.only(bottom: 34),
    ),
    const ResponsiveCase(
      Size(640, 360),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
      safeArea: EdgeInsets.only(top: 20, bottom: 20),
    ),
    const ResponsiveCase(Size(800, 1280), textScale: 2),
  ];

  for (final scenario in cases) {
    testWidgets('custom bottom navigation: $scenario', (tester) async {
      final selected = <int>[];
      await pumpResponsive(
        tester,
        scenario,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: BottomNavBar(
            selectedIndex: 0,
            onSelect: selected.add,
          ),
        ),
      );

      expect(find.byType(BottomNavBar), findsOneWidget);
      expectNoLayoutException(tester, scenario);

      final searchLabel = AppLocalizations.translateFor(
        scenario.locale.languageCode,
        'search',
      )!;
      final search = find.text(searchLabel);
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.pump();
      expect(selected, [1]);
      expectNoLayoutException(tester, scenario);
    });
  }
}
