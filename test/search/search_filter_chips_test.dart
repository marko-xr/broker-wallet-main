// The Search filter chips: they float on the page (nothing is drawn behind the
// row), every chip is the same compact height, selected or not, and each one has
// a full touch target around it so being compact does not make it hard to press.
//
// Local widget tests with the real ARB text and Flutter's test font; they prove
// the sizing rules, not how a device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Read straight from the ARB files when first used. Not assigned in setUpAll:
// the groups below choose their strings while the tests are being REGISTERED,
// which is before any setUpAll has run.
final Map<String, dynamic> en = json.decode(
  File('lib/src/common/localization/app_en.arb').readAsStringSync(),
) as Map<String, dynamic>;

final Map<String, dynamic> ar = json.decode(
  File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
) as Map<String, dynamic>;

const _keys = [
  'all',
  'requested',
  'offers',
  'owners',
  'offices',
  'brokers',
  'watchmen',
];

List<FilterModel> _filters({int selected = 0}) => [
      for (var i = 0; i < _keys.length; i++)
        FilterModel(
            label: _keys[i], labelKey: _keys[i], selected: i == selected),
    ];

Future<void> _pump(
  WidgetTester tester, {
  List<FilterModel>? filters,
  void Function(int)? onToggle,
  Locale locale = const Locale('en'),
  double width = 360,
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
            child: FilterChips(
              filters: filters ?? _filters(),
              onToggle: onToggle ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The visible chips, in order.
Finder _chips() => find.descendant(
      of: find.byType(FilterChips),
      matching: find.byType(AnimatedContainer),
    );

Finder _chipOf(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

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

  group('the sizes', () {
    test('compact, but not smaller than the suggested range', () {
      expect(AppControlSizes.compactChipHeight, 36);
      expect(AppControlSizes.compactChipHeight, inInclusiveRange(36, 40));
      expect(AppControlSizes.compactChipHeight,
          lessThan(AppControlSizes.standardButtonHeight));
      expect(FilterChips.rowHeight, AppControlSizes.minTouchTarget);
    });
  });

  for (final entry in {
    'English': const Locale('en'),
    'Arabic (RTL)': const Locale('ar'),
  }.entries) {
    final locale = entry.value;
    final table = locale.languageCode == 'ar' ? ar : en;

    group('every chip is one compact height: ${entry.key}', () {
      testWidgets('at the default text size', (tester) async {
        await _pump(tester, locale: locale);
        expect(_chips(), findsNWidgets(_keys.length));
        for (var i = 0; i < _keys.length; i++) {
          expect(tester.getSize(_chips().at(i)).height,
              AppControlSizes.compactChipHeight,
              reason: _keys[i]);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('selected or not, with or without the check mark',
          (tester) async {
        for (var selected = 0; selected < _keys.length; selected++) {
          await _pump(tester,
              locale: locale, filters: _filters(selected: selected));
          final heights = <double>{
            for (var i = 0; i < _keys.length; i++)
              tester.getSize(_chips().at(i)).height,
          };
          expect(heights, {AppControlSizes.compactChipHeight},
              reason: 'chip $selected selected');
          expect(find.byIcon(Icons.check_rounded), findsOneWidget,
              reason: 'only the selected chip has the check');
        }
      });

      testWidgets('the labels are the localized ones', (tester) async {
        await _pump(tester, locale: locale);
        for (final key in _keys) {
          expect(find.text(table[key] as String), findsOneWidget, reason: key);
        }
      });

      testWidgets('with large text the chips grow together', (tester) async {
        await _pump(tester, locale: locale, textScale: 1.5);
        final heights = <double>{
          for (var i = 0; i < _keys.length; i++)
            tester.getSize(_chips().at(i)).height,
        };
        expect(heights, hasLength(1), reason: 'all one height');
        expect(heights.single,
            greaterThanOrEqualTo(AppControlSizes.compactChipHeight));
        expect(tester.takeException(), isNull);
      });

      testWidgets('light and dark', (tester) async {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
          await _pump(tester, locale: locale, theme: theme);
          expect(tester.getSize(_chips().first).height,
              AppControlSizes.compactChipHeight);
          expect(tester.takeException(), isNull);
        }
      });
    });
  }

  group('nothing is drawn behind the chips', () {
    testWidgets('the only decorated boxes are the chips themselves',
        (tester) async {
      await _pump(tester);
      final boxes = find.descendant(
        of: find.byType(FilterChips),
        matching: find.byType(DecoratedBox),
      );
      expect(boxes, findsWidgets);
      for (var i = 0; i < boxes.evaluate().length; i++) {
        expect(
          find.ancestor(
              of: boxes.at(i), matching: find.byType(AnimatedContainer)),
          findsOneWidget,
          reason: 'decorated box $i is inside a chip',
        );
      }
    });

    testWidgets('no chip is wider than its label needs, and none spans the row',
        (tester) async {
      await _pump(tester);
      final rowWidth = tester.getSize(find.byType(FilterChips)).width;
      for (var i = 0; i < _keys.length; i++) {
        expect(tester.getSize(_chips().at(i)).width, lessThan(rowWidth * 0.6),
            reason: _keys[i]);
      }
    });

    testWidgets('the row paints no background of its own', (tester) async {
      await _pump(tester);
      // Material wrappers are transparent: there is no panel colour behind the
      // chips for the page to be hidden by.
      for (final material in tester.widgetList<Material>(find.descendant(
        of: find.byType(FilterChips),
        matching: find.byType(Material),
      ))) {
        expect(material.color, Colors.transparent);
        expect(material.elevation, 0);
      }
    });

    test('the screen draws no panel behind the filter row', () {
      final source = File(
        'lib/src/views/Screens/home/search/search_view.dart',
      ).readAsStringSync();
      expect(source.contains('BoxShadow'), isFalse);
      expect(source.contains('BoxDecoration'), isTrue,
          reason: 'only the result-count chip, below');
      final bar = source.substring(
        source.indexOf('SliverAppBar('),
        source.indexOf('// Content area'),
      );
      expect(bar.contains('BoxDecoration'), isFalse);
      expect(bar.contains('Container('), isFalse);
      expect(bar.contains('boxShadow'), isFalse);
      expect(bar.contains('scrolledUnderElevation: 0'), isTrue);
      expect(bar.contains('elevation: 0'), isTrue);
      expect(bar.contains('surfaceTintColor: Colors.transparent'), isTrue);
      expect(bar.contains('shadowColor: Colors.transparent'), isTrue);
      expect(bar.contains('toolbarHeight: FilterChips.rowHeightOf(context)'),
          isTrue);
      expect(bar.contains('pinned: true'), isTrue);
    });
  });

  group('the touch target', () {
    testWidgets('each chip has a full 48 to be pressed in', (tester) async {
      await _pump(tester);
      final targets = find.descendant(
        of: find.byType(FilterChips),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == AppControlSizes.minTouchTarget,
        ),
      );
      expect(targets, findsNWidgets(_keys.length));
      for (var i = 0; i < _keys.length; i++) {
        expect(tester.getSize(targets.at(i)).height,
            AppControlSizes.minTouchTarget);
      }
    });

    testWidgets('a press in the area around a chip toggles it, once',
        (tester) async {
      final toggled = <int>[];
      await _pump(tester, onToggle: toggled.add);
      // The second chip: fully on screen at 360 px without scrolling, which a
      // press at its coordinates needs (the fourth is off to the right).
      final chip = _chipOf(en['requested'] as String);
      final centre = tester.getCenter(chip);
      expect(centre.dx, inInclusiveRange(0, 360),
          reason: 'the chip is on screen');
      expect(tester.getSize(chip).height, AppControlSizes.compactChipHeight);

      // On the chip itself: one toggle, not two.
      await tester.tapAt(centre);
      expect(toggled, [1]);

      // Above and below it, inside the 48 but outside the 36.
      await tester.tapAt(centre.translate(0, -21));
      await tester.tapAt(centre.translate(0, 21));
      expect(toggled, [1, 1, 1]);
    });

    testWidgets('a press beyond the target does not', (tester) async {
      final toggled = <int>[];
      await _pump(tester, onToggle: toggled.add);
      final centre = tester.getCenter(_chipOf(en['requested'] as String));
      expect(centre.dx, inInclusiveRange(0, 360),
          reason: 'the chip is on screen');

      // Prove the press WOULD land if it were inside the target...
      await tester.tapAt(centre.translate(0, -21));
      expect(toggled, [1], reason: 'inside the 48 it toggles');

      // ...and that 30 above or below, outside it, does not.
      toggled.clear();
      await tester.tapAt(centre.translate(0, -30));
      await tester.tapAt(centre.translate(0, 30));
      expect(toggled, isEmpty);
    });

    testWidgets('a chip reports its own index', (tester) async {
      final toggled = <int>[];
      await _pump(tester, onToggle: toggled.add);
      for (final key in ['all', 'offers', 'watchmen']) {
        await tester.ensureVisible(_chipOf(en[key] as String));
        await tester.tap(find.text(en[key] as String));
      }
      expect(toggled, [0, 2, 6]);
    });

    testWidgets('with a very large font the target grows with the chips',
        (tester) async {
      await _pump(tester, textScale: 2.0);
      expect(tester.takeException(), isNull, reason: 'no overflow');

      final context = tester.element(find.byType(FilterChips));
      final rowHeight = FilterChips.rowHeightOf(context);
      final chipFormula = FilterChips.chipHeightOf(context);

      for (var i = 0; i < _keys.length; i++) {
        final chipFinder = _chips().at(i);
        final chip = tester.getSize(chipFinder).height;
        // The chip's target: the SizedBox nearest above it. Found by structure,
        // not by guessing its height.
        final target = tester
            .getSize(find
                .ancestor(of: chipFinder, matching: find.byType(SizedBox))
                .first)
            .height;
        final numbers = 'chip $chip, target $target, row $rowHeight, '
            'formula chip $chipFormula';

        // It grew with the text: a target stuck at 48 fails all of these.
        expect(chip, greaterThan(AppControlSizes.compactChipHeight),
            reason: '${_keys[i]}: the chip grew. $numbers');
        expect(target, greaterThan(AppControlSizes.minTouchTarget),
            reason: '${_keys[i]}: the target grew past 48. $numbers');

        // The chip always fits inside its target, with room around it.
        expect(target, greaterThanOrEqualTo(chip + 6),
            reason: '${_keys[i]}: room above and below the chip. $numbers');
        expect(target, lessThanOrEqualTo(chip + 10),
            reason:
                '${_keys[i]}: about 8 of room, not a different size. $numbers');

        // And it is the size the row itself reports (the toolbar uses it).
        expect(target, closeTo(rowHeight, 0.01),
            reason: '${_keys[i]}: the target is rowHeightOf. $numbers');
      }

      // The shared formula tracks the real chips. The engine lays text out with
      // its own rounding of the line, so this allows a pixel or two rather than
      // demanding the formula's fractions to the hundredth.
      expect(tester.getSize(_chips().first).height, closeTo(chipFormula, 2.0),
          reason: 'the formula and the laid-out chip agree to within rounding');
    });

    testWidgets('the row height is the touch target at normal text',
        (tester) async {
      late double normal;
      late double large;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            normal = FilterChips.rowHeightOf(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Builder(builder: (context) {
              large = FilterChips.rowHeightOf(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(normal, AppControlSizes.minTouchTarget);
      expect(large, greaterThan(normal));
    });
  });

  group('selected and unselected', () {
    testWidgets('only the colours and the check differ', (tester) async {
      await _pump(tester, filters: _filters(selected: 1));
      final selectedChip = tester.getSize(_chipOf(en['requested'] as String));
      final otherChip = tester.getSize(_chipOf(en['owners'] as String));
      expect(selectedChip.height, otherChip.height);

      final decoration = tester
          .widget<AnimatedContainer>(_chipOf(en['requested'] as String))
          .decoration! as BoxDecoration;
      final other = tester
          .widget<AnimatedContainer>(_chipOf(en['owners'] as String))
          .decoration! as BoxDecoration;
      expect(decoration.color, isNot(other.color));
      expect(decoration.borderRadius, other.borderRadius,
          reason: 'the same shape');
    });

    testWidgets('the radius is the shared pill', (tester) async {
      await _pump(tester);
      final decoration = tester
          .widget<AnimatedContainer>(_chips().first)
          .decoration! as BoxDecoration;
      expect(decoration.borderRadius,
          BorderRadius.circular(AppControlSizes.chipRadius));
    });
  });

  group('narrow and RTL layouts', () {
    testWidgets('at 320 px the row scrolls instead of overflowing',
        (tester) async {
      await _pump(tester, width: 320);
      expect(tester.takeException(), isNull);
      final last = _chipOf(en['watchmen'] as String);
      await tester.dragUntilVisible(
        last,
        find.byType(SingleChildScrollView),
        const Offset(-120, 0),
      );
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in Arabic the first chip is at the right edge',
        (tester) async {
      await _pump(tester, locale: const Locale('ar'), width: 320);
      final first = tester.getCenter(_chipOf(ar['all'] as String)).dx;
      final second = tester.getCenter(_chipOf(ar['requested'] as String)).dx;
      expect(first, greaterThan(second),
          reason: 'the order follows the language');
      expect(first, greaterThan(160));
    });

    testWidgets('in English the first chip is at the left edge',
        (tester) async {
      await _pump(tester, width: 320);
      final first = tester.getCenter(_chipOf(en['all'] as String)).dx;
      final second = tester.getCenter(_chipOf(en['requested'] as String)).dx;
      expect(first, lessThan(second));
      expect(first, lessThan(160));
    });

    testWidgets('the gap between chips mirrors', (tester) async {
      await _pump(tester);
      final a = tester.getTopRight(_chipOf(en['all'] as String)).dx;
      final b = tester.getTopLeft(_chipOf(en['requested'] as String)).dx;
      expect(b - a, closeTo(AppControlSizes.chipSpacing, 0.01));

      await _pump(tester, locale: const Locale('ar'));
      final right = tester.getTopLeft(_chipOf(ar['all'] as String)).dx;
      final left = tester.getTopRight(_chipOf(ar['requested'] as String)).dx;
      expect(right - left, closeTo(AppControlSizes.chipSpacing, 0.01));
    });
  });
}
