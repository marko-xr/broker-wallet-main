// Explicit manual repro, intentionally OUTSIDE the required green responsive
// suite and without an _test.dart discovery suffix. Run this file explicitly.
// OWNER_DECISION_REQUIRED: never change the protected card to satisfy this test.
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../responsive/responsive_harness.dart';
import '../responsive/r7a_test_fakes.dart';

void main() {
  setUpAll(prepareResponsiveAssets);
  for (final width in [280.0, 320.0]) {
    testWidgets('OWNER_DECISION_REQUIRED Scanner grid $width AR 2.0',
        (t) async {
      final report = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        report?.call(details);
      };
      addTearDown(() => FlutterError.onError = report);
      SharedPreferences.setMockInitialValues({'scanner_grid_view_mode': true});
      final vm = LocalScannerModel()..documents = scannerFixtures();
      addTearDown(() {
        expect(vm.unexpectedCalls, 0);
        vm.dispose();
      });
      await pumpResponsive(
          t,
          ResponsiveCase(Size(width, 600),
              locale: const Locale('ar'), textScale: 2),
          home: ScannerView(viewModel: vm));
      await t.scrollUntilVisible(
          find.byKey(const ValueKey<String>('fixture-0')), 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey<String>('fixture-0'));
      final bounds = t.getRect(card);
      for (final icon in [Icons.visibility, Icons.share, Icons.download]) {
        final rect =
            t.getRect(find.descendant(of: card, matching: find.byIcon(icon)));
        debugPrint(
            'grid width=$width card=$bounds icon=$icon rect=$rect contained=${bounds.contains(rect.topLeft) && bounds.contains(rect.bottomRight)}');
      }
      expectNoLayoutException(t, ResponsiveCase(Size(width, 600)));
    });
  }
}
