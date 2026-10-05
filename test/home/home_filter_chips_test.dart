// The Home filter chips: Search's compact chips — one height, a full touch
// target, spacing that follows the reading direction, labels from the ARB files,
// colours from the theme — with a selection that never makes the row jump. The
// room for a chosen chip's check mark opens and closes with the animation, so the
// chips beside it glide; they do not jump. Local widget tests with the real ARB
// text and Flutter's test font; they prove the sizing and motion rules, not how
// a device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_rules.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart';
import 'package:broker_wallet/src/views/Widgets/home_filter_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// How many chips the Home screen shows.
final int _count = HomeFilterKind.values.length;

/// The chips the Home screen shows, in order, with [selected] chosen (or none).
List<FilterModel> _filters({int? selected}) => [
      for (var i = 0; i < _count; i++)
        FilterModel(
          label: HomeFilterKind.values[i].label,
          labelKey: HomeFilterKind.values[i].labelKey,
          selected: i == selected,
        ),
    ];

/// The label a person reads on chip [index] in [languageCode], straight from
/// the ARB file the app loads.
String _label(String languageCode, int index) => AppLocalizations.translateFor(
    languageCode, HomeFilterKind.values[index].labelKey)!;

/// Builds the screen around the row. With [settle] false it stops after the one
/// frame in which the new state is built, so the animation it starts can be
/// looked at as it runs; the first call in a test must settle (the localization
/// delegates load asynchronously and nothing is drawn until they finish).
Future<void> _pump(
  WidgetTester tester, {
  Widget Function(List<FilterModel> filters, void Function(int) onToggle)?
      build,
  List<FilterModel>? filters,
  void Function(int)? onToggle,
  Locale locale = const Locale('en'),
  double width = 412,
  double textScale = 1,
  ThemeData? theme,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final shown = filters ?? _filters();
  final onTap = onToggle ?? (int _) {};
  final Widget chips = build != null
      ? build(shown, onTap)
      : HomeFilterChips(filters: shown, onToggle: onTap);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: chips,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// The chips of the row under test, in order.
Finder _chips({Type of = HomeFilterChips}) => find.descendant(
      of: find.byType(of),
      matching: find.byType(AnimatedContainer),
    );

List<Rect> _rects(WidgetTester tester, {Type of = HomeFilterChips}) => [
      for (var i = 0; i < _count; i++) tester.getRect(_chips(of: of).at(i)),
    ];

void _expectSameRect(Rect actual, Rect expected, String reason,
    {double tolerance = 0.01}) {
  expect(actual.left, closeTo(expected.left, tolerance),
      reason: '$reason: left');
  expect(actual.right, closeTo(expected.right, tolerance),
      reason: '$reason: right');
  expect(actual.top, closeTo(expected.top, tolerance), reason: '$reason: top');
  expect(actual.bottom, closeTo(expected.bottom, tolerance),
      reason: '$reason: bottom');
}

void _expectSameRects(List<Rect> actual, List<Rect> expected, String reason) {
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < expected.length; i++) {
    _expectSameRect(actual[i], expected[i], '$reason, chip $i');
  }
}

/// How far a chip has moved, from [before] to [after], toward the end of the row
/// in the reading direction: to the right in English, to the left in Arabic.
double _advance(Rect before, Rect after, {required bool rtl}) =>
    rtl ? before.right - after.right : after.left - before.left;

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const room = HomeFilterChips.checkRoom;

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  group('the Home chips have the Search chips\' sizes', () {
    for (final entry in {
      'English': const Locale('en'),
      'Arabic (RTL)': const Locale('ar'),
    }.entries) {
      testWidgets(
          'with nothing chosen: the same sizes and places, ${entry.key}',
          (tester) async {
        await _pump(tester, locale: entry.value);
        final home = _rects(tester);

        await _pump(
          tester,
          locale: entry.value,
          build: (filters, onToggle) =>
              FilterChips(filters: filters, onToggle: onToggle),
        );
        final search = _rects(tester, of: FilterChips);

        _expectSameRects(home, search, 'Home against Search');
      });

      testWidgets(
          'with a chip chosen: the same, up to the width of that chip, '
          '${entry.key}', (tester) async {
        final rtl = entry.value.languageCode == 'ar';
        for (var chosen = 0; chosen < _count; chosen++) {
          await _pump(tester,
              locale: entry.value, filters: _filters(selected: chosen));
          final home = _rects(tester);

          await _pump(
            tester,
            locale: entry.value,
            filters: _filters(selected: chosen),
            build: (filters, onToggle) =>
                FilterChips(filters: filters, onToggle: onToggle),
          );
          final search = _rects(tester, of: FilterChips);

          for (var i = 0; i < _count; i++) {
            // Same height and same row, whatever the chip.
            expect(home[i].top, closeTo(search[i].top, 0.01),
                reason: 'chosen $chosen, chip $i top');
            expect(home[i].bottom, closeTo(search[i].bottom, 0.01),
                reason: 'chosen $chosen, chip $i bottom');
          }
          // Up to the chosen chip the rows are the same chips in the same
          // places; the chosen chip starts at the same edge. Its label is not
          // bold here, so on a device it can only be narrower, never wider.
          for (var i = 0; i < chosen; i++) {
            _expectSameRect(home[i], search[i], 'chosen $chosen, chip $i');
          }
          final homeStart = rtl ? home[chosen].right : home[chosen].left;
          final searchStart = rtl ? search[chosen].right : search[chosen].left;
          expect(homeStart, closeTo(searchStart, 0.01));
          expect(home[chosen].width,
              lessThanOrEqualTo(search[chosen].width + 0.01));
        }
      });
    }

    test(
        'Home\'s chips take their sizes from Search\'s and add only the motion',
        () {
      final source = _source('lib/src/views/Widgets/home_filter_chips.dart');
      for (final shared in [
        'FilterChips.rowHeightOf(context)',
        'FilterChips.labelFontSize',
        'FilterChips.labelLineHeight',
        'AppControlSizes.compactChipHeight',
        'AppControlSizes.chipRadius',
        'AppControlSizes.chipSpacing',
      ]) {
        expect(source.contains(shared), isTrue, reason: shared);
      }
      // Spacing that follows the reading direction, never a fixed side.
      expect(source.contains('EdgeInsetsDirectional.only('), isTrue);
      expect(source.contains('EdgeInsets.only(right'), isFalse);
      expect(source.contains('EdgeInsets.only(left'), isFalse);
      expect(source.contains('Alignment.centerRight'), isFalse);
      expect(source.contains('Alignment.centerLeft'), isFalse);
      // Colours from the theme; nothing hard-coded and nothing deprecated.
      for (final own in [
        'Colors.white',
        'Colors.black',
        'Color.fromARGB',
        '.red',
        '.green',
        '.blue',
      ]) {
        expect(source.contains(own), isFalse, reason: 'no `$own`');
      }
    });

    test('the shared sizes are the compact ones', () {
      expect(AppControlSizes.compactChipHeight, 36);
      expect(AppControlSizes.compactChipHeight,
          lessThan(AppControlSizes.standardButtonHeight));
      expect(AppControlSizes.chipSpacing, 10);
      expect(FilterChips.rowHeight, AppControlSizes.minTouchTarget);
      // The room for the check mark is the check and the gap before it, which is
      // what Search's chip adds, all at once, when it is chosen.
      expect(room, 22);
    });
  });

  group('the size, as the Search chips have it', () {
    testWidgets('five chips, each exactly the compact height', (tester) async {
      await _pump(tester);
      expect(_chips(), findsNWidgets(5));
      for (var i = 0; i < _count; i++) {
        expect(tester.getSize(_chips().at(i)).height,
            AppControlSizes.compactChipHeight,
            reason: 'chip $i');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same height whichever chip is chosen, or none',
        (tester) async {
      for (final selected in [null, 0, 1, 2, 3, 4]) {
        await _pump(tester, filters: _filters(selected: selected));
        final heights = <double>{
          for (var i = 0; i < _count; i++)
            tester.getSize(_chips().at(i)).height,
        };
        expect(heights, {AppControlSizes.compactChipHeight},
            reason: 'chosen: $selected');
      }
    });

    testWidgets('only the chosen chip has the check mark', (tester) async {
      await _pump(tester);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      for (var i = 0; i < _count; i++) {
        await _pump(tester, filters: _filters(selected: i));
        expect(find.byIcon(Icons.check_rounded), findsOneWidget,
            reason: 'chip $i chosen');
        expect(
          find.descendant(
              of: _chips().at(i), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget,
          reason: 'chip $i chosen: the check is on that chip',
        );
      }
    });

    testWidgets('each chip has a full touch target to be pressed in',
        (tester) async {
      await _pump(tester);
      final targets = find.descendant(
        of: find.byType(HomeFilterChips),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == AppControlSizes.minTouchTarget,
        ),
      );
      expect(targets, findsNWidgets(_count));
      expect(tester.getSize(find.byType(HomeFilterChips)).height,
          AppControlSizes.minTouchTarget);
    });

    testWidgets('with large text the chips grow together and nothing overflows',
        (tester) async {
      await _pump(tester, textScale: 1.5);
      final heights = <double>{
        for (var i = 0; i < _count; i++) tester.getSize(_chips().at(i)).height,
      };
      expect(heights, hasLength(1));
      expect(heights.single,
          greaterThanOrEqualTo(AppControlSizes.compactChipHeight));
      expect(tester.takeException(), isNull);
    });
  });

  for (final entry in {
    'English': const Locale('en'),
    'Arabic (RTL)': const Locale('ar'),
  }.entries) {
    final locale = entry.value;
    final rtl = locale.languageCode == 'ar';

    group('the reading direction: ${entry.key}', () {
      testWidgets('the labels are the localized ones', (tester) async {
        await _pump(tester, locale: locale);
        for (var i = 0; i < _count; i++) {
          expect(find.text(_label(locale.languageCode, i)), findsOneWidget,
              reason: HomeFilterKind.values[i].labelKey);
        }
      });

      testWidgets('the chips start at the reading edge, in order',
          (tester) async {
        await _pump(tester, locale: locale);
        final rects = _rects(tester);
        for (var i = 0; i < _count - 1; i++) {
          if (rtl) {
            expect(rects[i].right, greaterThan(rects[i + 1].right),
                reason: 'chip $i is to the right of chip ${i + 1}');
          } else {
            expect(rects[i].left, lessThan(rects[i + 1].left),
                reason: 'chip $i is to the left of chip ${i + 1}');
          }
        }
        if (rtl) {
          // 412 wide, 16 of page padding and the row's own 4 at the start.
          expect(rects[0].right, closeTo(412 - 16 - 4, 0.01));
        } else {
          expect(rects[0].left, closeTo(16 + 4, 0.01));
        }
      });

      testWidgets('the space between chips is the shared one, both ways round',
          (tester) async {
        await _pump(tester, locale: locale);
        final rects = _rects(tester);
        for (var i = 0; i < _count - 1; i++) {
          final gap = rtl
              ? rects[i].left - rects[i + 1].right
              : rects[i + 1].left - rects[i].right;
          expect(gap, closeTo(AppControlSizes.chipSpacing, 0.01),
              reason: 'between chip $i and ${i + 1}');
        }
      });

      testWidgets('a tap reports the chip\'s own index', (tester) async {
        final toggled = <int>[];
        await _pump(tester, locale: locale, onToggle: toggled.add);
        for (final i in [4, 0, 3, 1, 2]) {
          await tester.ensureVisible(find.text(_label(locale.languageCode, i)));
          await tester.tap(find.text(_label(locale.languageCode, i)));
        }
        expect(toggled, [4, 0, 3, 1, 2]);
      });

      testWidgets('a press just above or below a chip still toggles it, once',
          (tester) async {
        final toggled = <int>[];
        await _pump(tester, locale: locale, onToggle: toggled.add);
        final centre = tester.getCenter(_chips().at(1));
        await tester.tapAt(centre);
        expect(toggled, [1]);
        // Inside the 48 but outside the 36.
        await tester.tapAt(centre.translate(0, -21));
        await tester.tapAt(centre.translate(0, 21));
        expect(toggled, [1, 1, 1]);
      });
    });

    group('choosing a chip never makes the row jump: ${entry.key}', () {
      testWidgets('nothing moves in the frame a chip is chosen',
          (tester) async {
        await _pump(tester, locale: locale);
        final before = _rects(tester);

        await _pump(tester,
            locale: locale, filters: _filters(selected: 1), settle: false);
        _expectSameRects(_rects(tester), before, 'the frame it is chosen');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the chips after it glide to make room for its check mark',
          (tester) async {
        await _pump(tester, locale: locale);
        final before = _rects(tester);

        await _pump(tester,
            locale: locale, filters: _filters(selected: 1), settle: false);
        await tester.pump(const Duration(milliseconds: 60));
        final early = _rects(tester);
        await tester.pump(const Duration(milliseconds: 60));
        final later = _rects(tester);
        await tester.pumpAndSettle();
        final after = _rects(tester);

        // The chosen chip grows a little at a time, not all at once.
        expect(early[1].width, greaterThan(before[1].width + 0.5));
        expect(later[1].width, greaterThan(early[1].width));
        expect(later[1].width, lessThan(after[1].width));
        expect(after[1].width, closeTo(before[1].width + room, 0.01));

        // The chips after it are carried along by exactly as much, at every
        // moment, and end up exactly one check mark's room further on.
        for (var i = 2; i < _count; i++) {
          expect(_advance(before[i], early[i], rtl: rtl),
              closeTo(early[1].width - before[1].width, 0.01),
              reason: 'chip $i, early');
          expect(_advance(before[i], later[i], rtl: rtl),
              closeTo(later[1].width - before[1].width, 0.01),
              reason: 'chip $i, later');
          expect(_advance(before[i], after[i], rtl: rtl), closeTo(room, 0.01),
              reason: 'chip $i, settled');
        }
        // The chip before it never moves.
        for (final frame in [early, later, after]) {
          _expectSameRect(frame[0], before[0], 'the chip before it');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('clearing it glides back the same way', (tester) async {
        await _pump(tester, locale: locale);
        final none = _rects(tester);
        await _pump(tester, locale: locale, filters: _filters(selected: 1));
        final chosen = _rects(tester);

        await _pump(tester, locale: locale, filters: _filters(), settle: false);
        _expectSameRects(_rects(tester), chosen, 'the frame it is cleared');

        await tester.pump(const Duration(milliseconds: 60));
        final early = _rects(tester);
        await tester.pump(const Duration(milliseconds: 60));
        final later = _rects(tester);
        expect(early[1].width, lessThan(chosen[1].width - 0.5));
        expect(later[1].width, lessThan(early[1].width));
        expect(later[1].width, greaterThan(none[1].width));

        await tester.pumpAndSettle();
        _expectSameRects(_rects(tester), none, 'settled');
        expect(find.byIcon(Icons.check_rounded), findsNothing);
      });

      testWidgets('moving the choice leaves the chips outside the two alone',
          (tester) async {
        await _pump(tester, locale: locale);
        final none = _rects(tester);
        await _pump(tester, locale: locale, filters: _filters(selected: 0));
        final fromFirst = _rects(tester);

        await _pump(tester,
            locale: locale, filters: _filters(selected: 2), settle: false);
        _expectSameRects(_rects(tester), fromFirst, 'the frame it moves');

        final frames = <List<Rect>>[];
        for (var step = 0; step < 2; step++) {
          await tester.pump(const Duration(milliseconds: 60));
          frames.add(_rects(tester));
        }
        await tester.pumpAndSettle();
        frames.add(_rects(tester));

        for (final frame in frames) {
          // One chip gives up exactly what the other takes, so the chips after
          // both do not move at all, at any moment.
          for (var i = 3; i < _count; i++) {
            _expectSameRect(frame[i], fromFirst[i], 'chip $i, outside the two');
          }
          // The first keeps its place and the second starts where the one in
          // between now ends.
          expect(_advance(fromFirst[0], frame[0], rtl: rtl), closeTo(0, 0.01));
          expect(_advance(fromFirst[2], frame[2], rtl: rtl),
              closeTo(_advance(fromFirst[1], frame[1], rtl: rtl), 0.01));
        }
        // The one in between is carried back by what the first gives up.
        expect(frames[0][0].width, lessThan(fromFirst[0].width));
        expect(_advance(fromFirst[1], frames[0][1], rtl: rtl), lessThan(0));
        // Settled: the first is back to its plain size, the second has the room.
        final settled = frames.last;
        expect(settled[0].width, closeTo(none[0].width, 0.01));
        expect(settled[2].width, closeTo(none[2].width + room, 0.01));
        expect(
            _advance(fromFirst[1], settled[1], rtl: rtl), closeTo(-room, 0.01));
      });

      testWidgets('a tap that comes half way reverses from where it is',
          (tester) async {
        await _pump(tester, locale: locale);
        final none = _rects(tester);

        await _pump(tester,
            locale: locale, filters: _filters(selected: 1), settle: false);
        await tester.pump(const Duration(milliseconds: 60));
        final halfWay = _rects(tester);
        expect(halfWay[1].width, greaterThan(none[1].width + 0.5));
        expect(halfWay[1].width, lessThan(none[1].width + room));

        await _pump(tester, locale: locale, filters: _filters(), settle: false);
        _expectSameRects(_rects(tester), halfWay, 'the frame it is reversed');

        await tester.pumpAndSettle();
        _expectSameRects(_rects(tester), none, 'settled again');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the label keeps one weight, chosen or not', (tester) async {
        await _pump(tester, locale: locale, filters: _filters(selected: 1));
        for (var i = 0; i < _count; i++) {
          final style = tester
              .widget<AnimatedDefaultTextStyle>(find.descendant(
                of: _chips().at(i),
                matching: find.byType(AnimatedDefaultTextStyle),
              ))
              .style;
          expect(style.fontWeight, FontWeight.w500, reason: 'chip $i');
        }
      });
    });
  }

  group('light and dark', () {
    for (final mode in ['light', 'dark']) {
      testWidgets('the colours come from the $mode theme', (tester) async {
        final theme =
            mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        await _pump(tester, theme: theme, filters: _filters(selected: 0));

        BoxDecoration decorationOf(int i) =>
            tester.widget<AnimatedContainer>(_chips().at(i)).decoration!
                as BoxDecoration;
        Color labelColorOf(int i) => tester
            .widget<AnimatedDefaultTextStyle>(find.descendant(
              of: _chips().at(i),
              matching: find.byType(AnimatedDefaultTextStyle),
            ))
            .style
            .color!;

        expect(decorationOf(0).color, theme.colorScheme.primary,
            reason: 'the chosen chip');
        expect(decorationOf(1).color, theme.colorScheme.surface,
            reason: 'a chip that is not chosen');
        expect(labelColorOf(0), theme.colorScheme.onPrimary);
        expect(labelColorOf(1), theme.colorScheme.onSurface);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
          theme.colorScheme.onPrimary,
          reason: 'the check mark',
        );
        expect(tester.getSize(_chips().first).height,
            AppControlSizes.compactChipHeight);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the Home screen', () {
    test('hands the chips the view model\'s filters and its toggle', () {
      final source = _source('lib/src/views/Screens/home_view.dart');
      expect(source.contains('HomeFilterChips('), isTrue);
      expect(source.contains('filters: vm.filters'), isTrue);
      expect(source.contains('onToggle: vm.toggleFilter'), isTrue);
    });
  });

  group('how the motion is built', () {
    final source = _source('lib/src/views/Widgets/home_filter_chips.dart');

    test('the room for the check mark is animated, not added in one frame', () {
      expect(source.contains('TweenAnimationBuilder<double>'), isTrue);
      expect(source.contains('widthFactor: progress'), isTrue);
      // The old way: the check and its gap added to the row the moment the chip
      // is chosen, which is the jump.
      expect(source.contains('if (selected) ...['), isFalse);
      expect(source.contains('if (isSelected) ...['), isFalse);
    });

    test('colours and room move over the same time and curve', () {
      expect(source.contains('static const Duration transition'), isTrue);
      expect(source.contains('static const Curve curve'), isTrue);
      // The chip's own animation, the label's and the check mark's.
      expect(
          RegExp(r'duration: HomeFilterChips\.transition')
              .allMatches(source)
              .length,
          3);
      expect(RegExp(r'curve: HomeFilterChips\.curve').allMatches(source).length,
          3);
    });

    test('the label has one weight in both states', () {
      expect(source.contains('FontWeight.w500'), isTrue);
      expect(source.contains('FontWeight.w600'), isFalse);
      expect(source.contains('FontWeight.bold'), isFalse);
    });

    test('a chip keeps its own animation however the row changes', () {
      expect(source.contains('key: ValueKey<String>('), isTrue);
    });
  });
}
