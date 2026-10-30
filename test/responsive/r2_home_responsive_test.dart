import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'r2_test_fakes.dart';
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
    const ResponsiveCase(Size(393, 852)),
    const ResponsiveCase(Size(430, 932), locale: Locale('ar'), dark: true),
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
    testWidgets('Home dashboard and long localized content: $scenario',
        (tester) async {
      final vm = HomeViewModel(
        authRepository: QuietAuthRepository(),
        initializeStreams: false,
      );
      addTearDown(vm.dispose);

      await pumpResponsive(
        tester,
        scenario,
        home: withR2ScreenProviders(
          ChangeNotifierProvider<HomeViewModel>.value(
            value: vm,
            child: const HomeView(),
          ),
        ),
      );

      expect(find.byType(HomeView), findsOneWidget);
      expectNoLayoutException(tester, scenario);

      final mapLabel = AppLocalizations.translateFor(
        scenario.locale.languageCode,
        'map',
      )!;
      final map = find.text(mapLabel);
      await tester.scrollUntilVisible(
        map,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(map, findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });
  }
}
