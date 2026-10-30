import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'r5d_entity_cases.dart';
import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);
  for (final c in entityMatrix) {
    for (final kind in ['offer', 'request', 'both']) {
      testWidgets('Related $kind painted bounds and scrolling $c',
          (tester) async {
        final window = noKeyboard(c);
        await pumpResponsive(tester, window,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AutoScrollingRelatedItemsCarousel(
              offers: kind == 'request' ? [] : [relatedOffer()],
              requests: kind == 'offer' ? [] : [relatedRequest()],
            ))),
            settle: false);
        await tester.pump();
        await tester.pump();
        final inner = find.descendant(
            of: find.byType(AutoScrollingRelatedItemsCarousel),
            matching: find.byType(SingleChildScrollView));
        expect(inner, findsWidgets);
        await tester.ensureVisible(inner.first);
        await tester.pump();
        final rect = tester.getRect(inner.first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(window.size.width));
        await tester.drag(inner.first, const Offset(0, -400));
        await tester.pump();
        expectNoLayoutException(tester, window);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
