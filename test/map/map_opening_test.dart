// How the map opens smoothly. The Google map is a native view: made while its
// page is still sliding in, it stalls the slide, and its first frames (empty,
// dark, then tiles) flash on a calm page. So the page slides in first
// (AfterRouteTransition), the map is made when the page is in place, and a sheet
// of the page's own colour lies over it until the map exists and then fades away
// (MapRevealCover). Local widget tests of those two widgets, and source guards on
// how the screen uses them (the screen itself needs Google Maps); not how a
// device renders it.

import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/map/map_opening.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _under = Key('under');
const _coverColor = Color(0xFF123456);

/// Pushes [page] from a home page, the way the map screen is opened, and pumps
/// the first frame of the new page. With [transition] the page opens with a
/// transition of that length (and no visible animation of its own).
Future<void> _openRoute(
  WidgetTester tester,
  Widget page, {
  Duration? transition,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            transition == null
                ? MaterialPageRoute<void>(builder: (_) => page)
                : PageRouteBuilder<void>(
                    transitionDuration: transition,
                    pageBuilder: (_, __, ___) => page,
                  ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

/// A cover over something that can be tapped, as the map's cover is over the
/// map.
Future<void> _pumpCover(
  WidgetTester tester, {
  required bool revealed,
  Duration maxWait = const Duration(seconds: 4),
  VoidCallback? onUnderTap,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Center(
            child: GestureDetector(
              key: _under,
              behavior: HitTestBehavior.opaque,
              onTap: onUnderTap,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
          Positioned.fill(
            child: MapRevealCover(
              revealed: revealed,
              color: _coverColor,
              maxWait: maxWait,
            ),
          ),
        ],
      ),
    ),
  );
}

/// How see-through the cover is now (1 covers, 0 shows what is under it), or
/// null when the cover is no longer built.
double? _coverOpacity(WidgetTester tester) {
  final fade = find.descendant(
    of: find.byType(MapRevealCover),
    matching: find.byType(FadeTransition),
  );
  if (fade.evaluate().isEmpty) return null;
  return tester.widget<FadeTransition>(fade).opacity.value;
}

void main() {
  group('AfterRouteTransition', () {
    testWidgets('outside a route there is nothing to wait for', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AfterRouteTransition(
            placeholder: Text('placeholder'),
            child: Text('child'),
          ),
        ),
      );

      expect(find.text('child'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);
    });

    testWidgets('a first page, already in place, shows its child at once',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AfterRouteTransition(
            placeholder: Text('placeholder'),
            child: Text('child'),
          ),
        ),
      );

      expect(find.text('child'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);
    });

    testWidgets('the child waits for the page to slide in', (tester) async {
      await _openRoute(
        tester,
        const AfterRouteTransition(
          placeholder: Text('placeholder'),
          child: Text('child'),
        ),
      );

      // Sliding in: the heavy child is not made yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('placeholder'), findsOneWidget);
      expect(find.text('child'), findsNothing);

      // In place: it is.
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);
    });

    testWidgets(
        'the child appears after maxWait even if the page never '
        'finishes', (tester) async {
      await _openRoute(
        tester,
        const AfterRouteTransition(
          maxWait: Duration(milliseconds: 200),
          placeholder: Text('placeholder'),
          child: Text('child'),
        ),
        transition: const Duration(seconds: 10),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('placeholder'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('child'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);

      // Let the slow page finish, so no animation is left running.
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
    });
  });

  group('MapRevealCover', () {
    testWidgets('lies over the page until the map exists', (tester) async {
      await _pumpCover(tester, revealed: false);

      expect(_coverOpacity(tester), 1.0);
      await tester.pump(const Duration(seconds: 1));
      expect(_coverOpacity(tester), 1.0);
    });

    testWidgets('fades away, not at once, when the map exists', (tester) async {
      await _pumpCover(tester, revealed: false);
      expect(_coverOpacity(tester), 1.0);

      await _pumpCover(tester, revealed: true);
      // The same frame the map was reported: nothing has changed yet.
      expect(_coverOpacity(tester), 1.0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_coverOpacity(tester), allOf(greaterThan(0.0), lessThan(1.0)));

      await tester.pumpAndSettle();
      // Gone: nothing of it is left to draw over the map.
      expect(_coverOpacity(tester), isNull);
    });

    testWidgets('takes no touches, so the map and the controls work',
        (tester) async {
      var taps = 0;
      await _pumpCover(tester, revealed: false, onUnderTap: () => taps++);

      await tester.tap(find.byKey(_under));

      expect(taps, 1);
    });

    testWidgets('is never left over the map for good', (tester) async {
      await _pumpCover(
        tester,
        revealed: false,
        maxWait: const Duration(milliseconds: 500),
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(_coverOpacity(tester), 1.0);

      // maxWait passes: it starts to fade although the map never reported in.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_coverOpacity(tester), lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_coverOpacity(tester), isNull);
    });

    testWidgets('a map that is ready from the start has no cover',
        (tester) async {
      await _pumpCover(tester, revealed: true);

      expect(_coverOpacity(tester), isNull);
    });
  });

  group('the map screen', () {
    // The screen needs Google Maps, so how it uses the two widgets is checked
    // in its source.
    String screenSource() =>
        File('lib/src/views/Screens/home/map/map_view.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');

    test('makes the map only after the page has slid in', () {
      final screen = screenSource();
      expect(RegExp(r'\bAfterRouteTransition\(').allMatches(screen).length, 1);

      final start = screen.indexOf('AfterRouteTransition(');
      // The load-error page is not behind the wait; the map is.
      expect(start, greaterThan(screen.indexOf('vm.hasLoadError')));
      final wrapped = screen.substring(
        start,
        screen.indexOf('MapRevealCover(', start),
      );
      expect(wrapped.contains('LayoutBuilder('), isTrue);
      expect(wrapped.contains('GoogleMap('), isTrue);
    });

    test('lies a cover of the page\'s colour over the map, under the controls',
        () {
      final screen = screenSource();
      expect(RegExp(r'\bMapRevealCover\(').allMatches(screen).length, 1);

      final cover = screen.indexOf('MapRevealCover(');
      expect(cover, greaterThan(screen.indexOf('GoogleMap(')));
      expect(cover, lessThan(screen.indexOf('child: _FloatingSearchBar(')));
      expect(cover, lessThan(screen.indexOf('child: MapFilterBar(')));
      expect(
          screen.contains('revealed: _mapCreated || vm.hasLoadError,'), isTrue);
      expect(screen.contains('color: colors.surface,'), isTrue);
    });

    test('the cover goes when the map reports it exists', () {
      final screen = screenSource();
      expect(screen.contains('onMapCreated: (controller) =>'), isTrue);
      expect(screen.contains('_onMapCreated(controller, vm),'), isTrue);

      final handler = screen.substring(
        screen.indexOf('void _onMapCreated('),
        screen.indexOf('Future<void> _locateMe('),
      );
      // The view model still gets the controller, as before.
      expect(handler.contains('vm.onMapCreated(controller);'), isTrue);
      expect(handler.contains('setState(() => _mapCreated = true)'), isTrue);
    });

    test('the page itself has no wait of its own', () {
      final screen = screenSource();
      // The waiting lives in the two widgets, not in the screen.
      expect(screen.contains('Timer'), isFalse);
      expect(screen.contains('Future.delayed'), isFalse);
    });
  });
}
