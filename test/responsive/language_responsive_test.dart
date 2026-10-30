import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/language_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final scenario in const [
    ResponsiveCase(Size(280, 600)),
    ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.3),
    ResponsiveCase(Size(360, 640), dark: true, textScale: 1.6),
    ResponsiveCase(Size(640, 360), locale: Locale('ar'), textScale: 2),
    ResponsiveCase(Size(800, 600)),
  ]) {
    testWidgets('Language settings actions: $scenario', (tester) async {
      final localeViewModel = LocaleViewModel();
      addTearDown(localeViewModel.dispose);
      await pumpResponsive(
        tester,
        scenario,
        home: ChangeNotifierProvider.value(
          value: localeViewModel,
          child: const LanguageView(),
        ),
      );
      final save = find.text(
          AppLocalizations.translateFor(scenario.locale.languageCode, 'save')!);
      expect(save, findsOneWidget);
      final center = tester.getCenter(save);
      expect(center.dx, inInclusiveRange(0, scenario.size.width));
      expect(center.dy, inInclusiveRange(0, scenario.size.height));
      expectNoLayoutException(tester, scenario);
    });
  }
}
