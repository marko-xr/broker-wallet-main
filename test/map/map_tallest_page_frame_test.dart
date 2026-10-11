// The card that floats over the map when a pin is tapped sat in a hard-coded
// 135 high box, and on a phone whose lines were a little taller (Arabic text, a
// larger text size) Flutter painted "BOTTOM OVERFLOWED BY 2.0 PIXELS" across
// it. TallestPageFrame sizes the page view from the cards themselves instead.
// Local widget tests with Flutter's test font: they prove the frame's sizing and
// that cards laid out inside it never overflow; not how a device renders it.

import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/map/map_tallest_page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Key('frame');
const _pages = Key('pages');

/// A card whose height comes from its text, as the pin card's does: a title, an
/// address line and a row of buttons, with the card's padding around them.
class _TextCard extends StatelessWidget {
  const _TextCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Title', style: TextStyle(fontSize: 14)),
          Text('Address', style: TextStyle(fontSize: 11)),
          SizedBox(height: 36),
        ],
      ),
    );
  }
}

/// Puts the frame where the screen does: full width minus the side gap, inside
/// a Column that gives its children no height limit.
Future<void> _pump(
  WidgetTester tester, {
  required double minHeight,
  required List<Widget> measure,
  required List<Widget> pages,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TallestPageFrame(
                  key: _frame,
                  minHeight: minHeight,
                  measure: measure,
                  child: PageView(key: _pages, children: pages),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('how tall the frame is', () {
    testWidgets('as tall as the tallest card, and as wide as it is given',
        (tester) async {
      await _pump(
        tester,
        minHeight: 20,
        measure: const [
          SizedBox(height: 40),
          SizedBox(height: 90),
          SizedBox(height: 70),
        ],
        pages: const [SizedBox(), SizedBox(), SizedBox()],
      );

      expect(tester.getSize(find.byKey(_frame)), const Size(368, 90));
    });

    testWidgets('never shorter than the least height', (tester) async {
      await _pump(
        tester,
        minHeight: 135,
        measure: const [SizedBox(height: 40), SizedBox(height: 50)],
        pages: const [SizedBox(), SizedBox()],
      );

      expect(tester.getSize(find.byKey(_frame)).height, 135);
    });

    testWidgets('grows past the least height when a card needs more',
        (tester) async {
      await _pump(
        tester,
        minHeight: 135,
        measure: const [SizedBox(height: 137)],
        pages: const [SizedBox()],
      );

      // The case from the device: a card 2 px taller than the old fixed box.
      expect(tester.getSize(find.byKey(_frame)).height, 137);
    });

    testWidgets('the page view fills the whole frame', (tester) async {
      await _pump(
        tester,
        minHeight: 20,
        measure: const [SizedBox(height: 90)],
        pages: const [SizedBox()],
      );

      expect(
        tester.getRect(find.byKey(_pages)),
        tester.getRect(find.byKey(_frame)),
      );
    });

    testWidgets('swiping to another card does not resize the frame',
        (tester) async {
      await _pump(
        tester,
        minHeight: 20,
        // The cards differ, the frame is the tallest of them on every page.
        measure: const [SizedBox(height: 60), SizedBox(height: 90)],
        pages: [
          Container(color: Colors.red),
          Container(color: Colors.blue),
        ],
      );
      expect(tester.getSize(find.byKey(_frame)).height, 90);

      await tester.drag(find.byKey(_pages), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(_frame)).height, 90);
    });
  });

  group('text that needs more room', () {
    testWidgets('a card laid out in the frame never overflows', (tester) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        await _pump(
          tester,
          // Less than the card needs at any scale, so the frame must grow.
          minHeight: 40,
          measure: const [_TextCard()],
          pages: const [_TextCard()],
          textScale: scale,
        );

        // A page that did not fit its frame would have thrown an overflow.
        expect(tester.takeException(), isNull, reason: 'text scale $scale');
      }
    });

    testWidgets('larger text makes the frame taller', (tester) async {
      Future<double> heightAt(double scale) async {
        await _pump(
          tester,
          minHeight: 40,
          measure: const [_TextCard()],
          pages: const [_TextCard()],
          textScale: scale,
        );
        return tester.getSize(find.byKey(_frame)).height;
      }

      final normal = await heightAt(1);
      final large = await heightAt(2);

      expect(normal, greaterThan(40));
      expect(large, greaterThan(normal));
    });
  });

  group('the pin card carousel on the map screen', () {
    // The screen itself needs Google Maps, so its wiring is checked in source.
    String screenSource() =>
        File('lib/src/views/Screens/home/map/map_view.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');

    test('has no hard-coded height to overflow', () {
      final screen = screenSource();
      expect(screen.contains('height: 135'), isFalse);
      expect(RegExp(r'\bTallestPageFrame\(').allMatches(screen).length, 1);
      expect(screen.contains('minHeight: _cardMinHeight,'), isTrue);
    });

    test('is measured from a copy of every card, close button included', () {
      final screen = screenSource();
      expect(
        screen.contains(
          'for (final item in widget.cluster.items) _measureCard(item, colors),',
        ),
        isTrue,
      );
      expect(screen.contains('measure: measure,'), isTrue);

      final measureCard = screen.substring(
        screen.indexOf('Widget _measureCard('),
        screen.indexOf('Widget build(BuildContext context) {',
            screen.indexOf('Widget _measureCard(')),
      );
      // The copy is the real card class, so the two cannot disagree.
      expect(measureCard.contains('_LocationCarouselCard('), isTrue);
      expect(measureCard.contains('showCloseButton: true,'), isTrue);
      expect(measureCard.contains('measureOnly: true,'), isTrue);
    });

    test('a measuring copy loads and draws no photo and no icon', () {
      final screen = screenSource();
      expect(screen.contains('if (measureOnly)'), isTrue);
      expect(
        screen.contains(
          'const SizedBox.square(dimension: _CompactMediaPreview.size)',
        ),
        isTrue,
      );
      // The real preview, which asks for a photo, is built in one place only
      // (the constructor's own `const _CompactMediaPreview(` is not a build).
      expect(
        RegExp(r'(?<!const )_CompactMediaPreview\(').allMatches(screen).length,
        1,
      );
    });
  });
}
