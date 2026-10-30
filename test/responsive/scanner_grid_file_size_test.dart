import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r7a_test_fakes.dart';
import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);
  const cases = [
    ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2),
    ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 2),
    ResponsiveCase(Size(280, 600), textScale: 2),
    ResponsiveCase(Size(320, 568), textScale: 1.6),
    ResponsiveCase(Size(393, 852)),
  ];
  for (final c in cases) {
    testWidgets('Scanner Grid file size and existing actions $c', (t) async {
      SharedPreferences.setMockInitialValues({'scanner_grid_view_mode': true});
      final vm = LocalScannerModel()..documents = scannerFixtures();
      addTearDown(() {
        expect(vm.unexpectedCalls, 0);
        vm.dispose();
      });
      await pumpResponsive(t, c, home: ScannerView(viewModel: vm));
      final card = find.byKey(const ValueKey<String>('fixture-0'));
      await t.scrollUntilVisible(card, 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expectNoLayoutException(t, c);
      // Original two columns, horizontal insets/gap and scaled tile extent.
      expect(t.getSize(card).width, (c.size.width - 32) / 2);
      expect(t.getSize(card).height, 200 * c.textScale.clamp(1.0, 1.6));
      final size = find.descendant(of: card, matching: find.text('941.9 MB'));
      expect(size, findsOneWidget);
      await Scrollable.ensureVisible(t.element(size), alignment: .5);
      await t.pumpAndSettle();
      final viewport =
          find.ancestor(of: size, matching: find.byType(SingleChildScrollView));
      final textBounds = t.getRect(size);
      final visible = t.getRect(viewport).inflate(.1);
      expect(
          visible.contains(textBounds.topLeft) &&
              visible.contains(textBounds.bottomRight),
          isTrue,
          reason: 'The complete file size must be reachable without clipping');
      expect(t.renderObject<RenderParagraph>(size).didExceedMaxLines, isFalse);
      for (final data in [Icons.visibility, Icons.share, Icons.download]) {
        final icon = find.descendant(of: card, matching: find.byIcon(data));
        await Scrollable.ensureVisible(t.element(icon), alignment: .5);
        await t.pumpAndSettle();
        expect(icon.hitTestable(), findsOneWidget);
        InkWell? action;
        t.element(icon).visitAncestorElements((element) {
          if (element.widget is InkWell) {
            action = element.widget as InkWell;
            return false;
          }
          return true;
        });
        expect(action!.onTap, isNotNull); // Never invoke preview/share/export.
        expect(t.getSize(find.byWidget(action!)).height, 36);
        final button = t.getRect(find.byWidget(action!));
        final bounds = t.getRect(card).inflate(.1);
        expect(
            bounds.contains(button.topLeft) &&
                bounds.contains(button.bottomRight),
            isTrue);
      }
      final typeIcon = find.descendant(
          of: card, matching: find.byIcon(Icons.picture_as_pdf));
      await Scrollable.ensureVisible(t.element(typeIcon), alignment: .5);
      await t.pumpAndSettle();
      await t.longPress(typeIcon); // Only the local selection callback.
      await t.pumpAndSettle();
      expect(vm.isSelectionMode, isTrue);
      expect(vm.selectedCount, 1);
      final loc = AppLocalizations.of(t.element(find.byType(Scaffold)));
      await t.tap(find.byTooltip(loc.translate('cancelSelection')));
      await t.pumpAndSettle();
      expect(vm.isSelectionMode, isFalse);
      expect(vm.starts, 1);
      expectNoLayoutException(t, c);
    });
  }
}
