// City chips and Area chips are one chip, so they are one height.
//
// The Request, Offer and Owner forms all show the same three things: the city
// chips, then — once a city is chosen — the chosen-city pill and the city's area
// chips. This pins that every one of them, in every state and language, renders at
// exactly the same height: label line + the shared padding + the shared border.
// Only widths differ, with the label. It also pins that no label wraps (a long
// area name is ellipsized, never a second line) and that the 3-row collapse, the
// Show more toggle and the selection caps still work with that geometry.
//
// Request and Offer's own city/area section is a private widget of each screen, a
// thin composition of SelectableChip, ClearableChip and ExpandableAreaChips; here a
// stand-in composes exactly those, and source guards pin each screen's private
// widget to them. The Owner uses the real UaeCityAreaPicker.
//
// Local widget and source tests with the real ARB text. The test font gives every
// glyph the same width, so a long label is far wider than a real one: that is the
// point at narrow widths — it makes the no-wrap rule bite — but it means these
// prove the layout rules, not how a real device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/views/Widgets/expandable_area_chips.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';
import 'package:broker_wallet/src/views/Widgets/uae_city_area_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _pill = ValueKey<String>('city-pill');
const _toggle = ValueKey<String>('area-chips-toggle');

String _read(String path) => File(path).readAsStringSync();

/// The vertical room a chip adds around its label line: padding and border, both
/// sides.
double get _chipChrome =>
    2 * (AppControlSizes.chipVerticalPadding + AppControlSizes.chipBorderWidth);

/// Request and Offer's `_CityChips`, composed of the same shared components, with
/// the same three-area cap. The host owns the selection, as the view-model does.
class _RequestOfferCityArea extends StatefulWidget {
  const _RequestOfferCityArea();

  @override
  State<_RequestOfferCityArea> createState() => _RequestOfferCityAreaState();
}

class _RequestOfferCityAreaState extends State<_RequestOfferCityArea> {
  String city = '';
  final List<String> selected = <String>[];

  void selectCity(String value) => setState(() {
        city = value;
        selected.clear();
      });

  void toggleArea(String key) => setState(() {
        if (selected.contains(key)) {
          selected.remove(key);
        } else if (selected.length < 3) {
          selected.add(key);
        }
      });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    if (city.isEmpty) {
      return Wrap(
        spacing: AppControlSizes.chipSpacing,
        runSpacing: AppControlSizes.chipSpacing,
        children: [
          for (final c in UaeAreaCatalog.supportedCities)
            SelectableChip(
              key: ValueKey<String>('city-chip-$c'),
              label: localization.translate(UaeAreaCatalog.cityKey(c)),
              isSelected: false,
              onTap: () => selectCity(c),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClearableChip(
              key: _pill,
              clearKey: const ValueKey<String>('city-pill-clear'),
              label: localization.translate(UaeAreaCatalog.cityKey(city)),
              onClear: () => selectCity(''),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ExpandableAreaChips(
          city: city,
          selectedAreas: selected,
          onToggleArea: toggleArea,
          localization: localization,
        ),
      ],
    );
  }
}

/// The Owner's section: the real shared picker, one area at a time.
class _OwnerCityArea extends StatefulWidget {
  const _OwnerCityArea();

  @override
  State<_OwnerCityArea> createState() => _OwnerCityAreaState();
}

class _OwnerCityAreaState extends State<_OwnerCityArea> {
  String city = '';
  final List<String> selected = <String>[];

  @override
  Widget build(BuildContext context) {
    return UaeCityAreaPicker(
      cities: UaeAreaCatalog.supportedCities,
      selectedCity: city,
      onCityChanged: (value) => setState(() {
        city = value;
        selected.clear();
      }),
      selectedAreas: selected,
      onToggleArea: (key) => setState(() {
        selected
          ..clear()
          ..add(key);
      }),
      maxSelectedAreas: 1,
      localization: AppLocalizations.of(context),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget host,
  required Locale locale,
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: inner ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          // The forms' own side padding.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child:
              Align(alignment: AlignmentDirectional.centerStart, child: host),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cityChips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('city-chip-');
    });

Finder _areaChips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('area-chip-');
    });

Finder _areaChip(String key) => find.byKey(ValueKey<String>('area-chip-$key'));

/// A chip's label as laid out: the paragraph of its Text. (Not "the chip's only
/// RichText": the pill's x icon is a RichText too.)
RenderParagraph _paragraph(WidgetTester tester, Finder chip) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(of: chip, matching: find.byType(Text)),
        matching: find.byType(RichText),
      ),
    );

class _Reading {
  _Reading(this.what, this.chipHeight, this.labelHeight, this.ellipsized);

  final String what;
  final double chipHeight;
  final double labelHeight;
  final bool ellipsized;
}

List<_Reading> _measure(WidgetTester tester, Finder chips, String what) {
  final readings = <_Reading>[];
  for (var i = 0; i < chips.evaluate().length; i++) {
    final chip = chips.at(i);
    final paragraph = _paragraph(tester, chip);
    readings.add(_Reading(
      '$what #$i',
      tester.getSize(chip).height,
      paragraph.size.height,
      paragraph.didExceedMaxLines,
    ));
  }
  return readings;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Walks one form through everything it shows and returns what every chip
/// measured: the nine city chips; then, for the chosen city, the pill and the
/// collapsed area chips; then the expanded ones; then with areas chosen — which,
/// at the three-area cap, also dims the rest.
Future<List<_Reading>> _walk(
  WidgetTester tester, {
  required Widget host,
  required Locale locale,
  required double width,
  required double textScale,
  required int cap,
}) async {
  await _pump(
    tester,
    host: host,
    locale: locale,
    width: width,
    textScale: textScale,
  );
  final readings = <_Reading>[];

  // 1. The city chips.
  expect(_cityChips().evaluate().length, UaeAreaCatalog.supportedCities.length);
  readings.addAll(_measure(tester, _cityChips(), 'city chip'));

  // 2. A city is chosen: the pill and the collapsed area chips.
  await _tap(tester, find.byKey(const ValueKey<String>('city-chip-Dubai')));
  expect(find.byKey(_pill), findsOneWidget);
  readings.add(_Reading(
    'chosen-city pill',
    tester.getSize(find.byKey(_pill)).height,
    _paragraph(tester, find.byKey(_pill)).size.height,
    _paragraph(tester, find.byKey(_pill)).didExceedMaxLines,
  ));
  readings.addAll(_measure(tester, _areaChips(), 'area chip (collapsed)'));

  // 3. Show more: every area chip of the city, including the longest names.
  await _tap(tester, find.byKey(_toggle));
  expect(
      _areaChips().evaluate().length, UaeAreaCatalog.areasFor('Dubai').length);
  readings.addAll(_measure(tester, _areaChips(), 'area chip (expanded)'));

  // 4. Areas chosen: selected chips, and the dimmed rest at the cap.
  final areas = UaeAreaCatalog.areasFor('Dubai');
  for (var i = 0; i < cap; i++) {
    await _tap(tester, _areaChip(areas[i]));
  }
  final chosen = tester
      .widgetList<SelectableChip>(find.byType(SelectableChip))
      .where((chip) => chip.isSelected)
      .length;
  expect(chosen, cap, reason: 'the form took its $cap area(s)');
  readings.addAll(_measure(tester, _areaChips(), 'area chip (with a choice)'));
  readings.add(_Reading(
    'chosen-city pill (with a choice)',
    tester.getSize(find.byKey(_pill)).height,
    _paragraph(tester, find.byKey(_pill)).size.height,
    false,
  ));

  expect(tester.takeException(), isNull);
  return readings;
}

void _expectOneHeight(List<_Reading> readings, String where) {
  // The reference is the first city chip: a short name on one line.
  final reference = readings.first;
  for (final reading in readings) {
    expect(
      reading.chipHeight,
      closeTo(reference.chipHeight, 0.01),
      reason: '$where: ${reading.what} is ${reading.chipHeight} high, '
          'a city chip is ${reference.chipHeight}',
    );
    expect(
      reading.labelHeight,
      closeTo(reference.labelHeight, 0.01),
      reason:
          '$where: ${reading.what} laid its label out on more than one line '
          '(${reading.labelHeight} vs ${reference.labelHeight})',
    );
    expect(
      reading.chipHeight - reading.labelHeight,
      closeTo(_chipChrome, 0.01),
      reason: '$where: ${reading.what}: label + the shared padding and border',
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Serve the ARB files from disk so the tests assert on the real strings.
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

  // Request and Offer are the same composition with the same cap; they are
  // listed apart so each is reported on its own.
  final forms = <String, (Widget Function(), int)>{
    'Request': (() => const _RequestOfferCityArea(), 3),
    'Offer': (() => const _RequestOfferCityArea(), 3),
    'Owner': (() => const _OwnerCityArea(), 1),
  };

  // A narrow phone, a wide one, and a narrow one with large text — where the
  // longest names are far wider than the room.
  const settings = <(double, double)>[(320, 1.3), (360, 1.0), (412, 1.0)];

  for (final form in forms.entries) {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      for (final setting in settings) {
        final width = setting.$1;
        final scale = setting.$2;
        final where =
            '${form.key}, ${locale.languageCode}, ${width.toInt()}px, x$scale';

        testWidgets('city, pill and area chips are one height: $where',
            (tester) async {
          final readings = await _walk(
            tester,
            host: form.value.$1(),
            locale: locale,
            width: width,
            textScale: scale,
            cap: form.value.$2,
          );

          expect(readings.length, greaterThan(100),
              reason: 'the cities, the pill and every area of Dubai, '
                  'collapsed, expanded and with a choice');
          _expectOneHeight(readings, where);
        });
      }
    }
  }

  group('no label wraps; a name wider than the room is ellipsized', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets(
          '${locale.languageCode}: the longest names are cut, not wrapped',
          (tester) async {
        final readings = await _walk(
          tester,
          host: const _RequestOfferCityArea(),
          locale: locale,
          width: 320,
          textScale: 1.3,
          cap: 3,
        );

        // The test font makes a long name far wider than 320 px, so at least one
        // area chip really is cut — which proves the rule was exercised — and
        // every one of them is still a single line of the same height.
        final cut = readings.where((r) => r.ellipsized).toList();
        expect(cut, isNotEmpty,
            reason: 'the test must reach a name wider than the room');
        for (final reading in cut) {
          expect(reading.labelHeight, closeTo(readings.first.labelHeight, 0.01),
              reason: reading.what);
          expect(reading.chipHeight, closeTo(readings.first.chipHeight, 0.01),
              reason: reading.what);
        }
      });
    }

    testWidgets('a chip never takes more width than the row', (tester) async {
      await _walk(
        tester,
        host: const _RequestOfferCityArea(),
        locale: const Locale('en'),
        width: 320,
        textScale: 1.3,
        cap: 3,
      );

      const room = 320 - 32.0;
      final chips = _areaChips();
      for (var i = 0; i < chips.evaluate().length; i++) {
        expect(
            tester.getSize(chips.at(i)).width, lessThanOrEqualTo(room + 0.01),
            reason: 'chip $i');
      }
    });

    test('the chip label is one line and ellipsized', () {
      final source = _read('lib/src/views/Widgets/selectable_chip.dart');
      expect(source.contains('maxLines: SelectableChip.labelMaxLines'), isTrue);
      expect(SelectableChip.labelMaxLines, 1);
      expect(source.contains('TextOverflow.ellipsis'), isTrue);
      expect(source.contains('forceStrutHeight: true'), isTrue,
          reason: 'one line box whatever the glyphs\' fonts');
    });

    test('the row planner measures the same one-line label', () {
      final source = _read('lib/src/views/Widgets/expandable_area_chips.dart');
      expect(source.contains('maxLines: SelectableChip.labelMaxLines'), isTrue);
    });
  });

  group('width still follows the label', () {
    testWidgets('a longer name makes a wider chip of the same height',
        (tester) async {
      await _pump(
        tester,
        host: const _RequestOfferCityArea(),
        locale: const Locale('en'),
        width: 800,
        textScale: 1,
      );

      final short = find.byKey(const ValueKey<String>('city-chip-Ajman'));
      final long =
          find.byKey(const ValueKey<String>('city-chip-Umm Al Quwain'));
      expect(
          tester.getSize(long).width, greaterThan(tester.getSize(short).width));
      expect(tester.getSize(long).height, tester.getSize(short).height);
    });

    test('no chip is given a fixed width', () {
      final source = _read('lib/src/views/Widgets/selectable_chip.dart');
      // A width written as a number, or any box that would fix or bound one.
      expect(RegExp(r'width:\s*[0-9]').hasMatch(source), isFalse);
      expect(source.contains('ConstrainedBox'), isFalse);
      expect(source.contains('SizedBox'), isFalse);
      expect(source.contains('minWidth'), isFalse);
      expect(source.contains('maxWidth'), isFalse);
    });
  });

  group('the 3-row collapse and the selection rules are untouched', () {
    for (final width in const [320.0, 360.0, 412.0]) {
      testWidgets('three rows at ${width.toInt()} px', (tester) async {
        await _pump(
          tester,
          host: const _RequestOfferCityArea(),
          locale: const Locale('en'),
          width: width,
          textScale: 1,
        );
        await _tap(
            tester, find.byKey(const ValueKey<String>('city-chip-Dubai')));

        final tops = <int>{};
        final chips = _areaChips();
        for (var i = 0; i < chips.evaluate().length; i++) {
          tops.add((tester.getTopLeft(chips.at(i)).dy * 10).round());
        }
        expect(tops.length, 3);
        expect(find.byKey(_toggle), findsOneWidget);
      });
    }

    testWidgets(
        'Request/Offer take three areas and dim the rest; Owner takes one',
        (tester) async {
      await _pump(
        tester,
        host: const _RequestOfferCityArea(),
        locale: const Locale('en'),
        width: 412,
        textScale: 1,
      );
      await _tap(tester, find.byKey(const ValueKey<String>('city-chip-Dubai')));
      final areas = UaeAreaCatalog.areasFor('Dubai');
      for (var i = 0; i < 4; i++) {
        await _tap(tester, _areaChip(areas[i]));
      }
      final selected = tester
          .widgetList<SelectableChip>(_areaChips())
          .where((chip) => chip.isSelected)
          .length;
      expect(selected, 3);
      expect(
        tester
            .widgetList<SelectableChip>(_areaChips())
            .where((chip) => !chip.isSelected && !chip.isEnabled)
            .isNotEmpty,
        isTrue,
        reason: 'at the cap the others are dimmed',
      );

      await _pump(
        tester,
        host: const _OwnerCityArea(),
        locale: const Locale('en'),
        width: 412,
        textScale: 1,
      );
      await _tap(tester, find.byKey(const ValueKey<String>('city-chip-Dubai')));
      await _tap(tester, _areaChip(areas[0]));
      await _tap(tester, _areaChip(areas[1]));
      expect(
        tester
            .widgetList<SelectableChip>(_areaChips())
            .where((chip) => chip.isSelected)
            .length,
        1,
      );
      expect(
        tester
            .widgetList<SelectableChip>(_areaChips())
            .where((chip) => !chip.isEnabled),
        isEmpty,
        reason: 'a single choice replaces; nothing is dimmed',
      );
    });
  });

  group('Request and Offer render the shared chips, nothing of their own', () {
    for (final path in const [
      'lib/src/views/Screens/ViewAdd/add_requested_view.dart',
      'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
    ]) {
      final name = path.split('/').last;

      test(
          '$name: _CityChips is SelectableChip + ClearableChip + '
          'ExpandableAreaChips', () {
        final source = _read(path);
        final match = RegExp(
          r'class _CityChips extends StatelessWidget \{[\s\S]*?\r?\n\}\r?\n',
        ).firstMatch(source);
        expect(match, isNotNull, reason: name);
        final body = match!.group(0)!;

        expect(body.contains('SelectableChip('), isTrue, reason: name);
        expect(body.contains('ClearableChip('), isTrue, reason: name);
        expect(body.contains('ExpandableAreaChips('), isTrue, reason: name);
        expect(body.contains('spacing: AppControlSizes.chipSpacing'), isTrue,
            reason: name);

        // No private chip frame: nothing here paints a border, a fill, a
        // padding or a corner of its own.
        for (final forbidden in const [
          'Container(',
          'GestureDetector(',
          'BoxDecoration(',
          'BorderRadius',
          'Border.all',
          'EdgeInsets',
          'AppTextStyles',
        ]) {
          expect(body.contains(forbidden), isFalse,
              reason: '$name: _CityChips has its own $forbidden');
        }
      });
    }

    test('the Owner picker is the same three components', () {
      final source = _read('lib/src/views/Widgets/uae_city_area_picker.dart');
      expect(source.contains('SelectableChip('), isTrue);
      expect(source.contains('ClearableChip('), isTrue);
      expect(source.contains('ExpandableAreaChips('), isTrue);
      for (final forbidden in const [
        'Container(',
        'BoxDecoration(',
        'Border.all',
        'EdgeInsets',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: 'the picker has its own $forbidden');
      }
    });

    test('one frame: every chip draws its border through the same helper', () {
      final source = _read('lib/src/views/Widgets/selectable_chip.dart');
      expect(RegExp(r'_chipDecoration\(').allMatches(source).length,
          greaterThanOrEqualTo(3),
          reason: 'its definition and both chips');
      expect(RegExp(r'Border\.all\(').allMatches(source).length, 1,
          reason: 'the border is drawn in exactly one place');
    });
  });

  group('the selected-city pill matches the chips around it', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets('${locale.languageCode}: same height, same border',
          (tester) async {
        await _pump(
          tester,
          host: const _RequestOfferCityArea(),
          locale: locale,
          width: 360,
          textScale: 1,
        );
        final cityChipHeight = tester.getSize(_cityChips().first).height;
        await _tap(
            tester, find.byKey(const ValueKey<String>('city-chip-Dubai')));

        expect(tester.getSize(find.byKey(_pill)).height,
            closeTo(cityChipHeight, 0.01));
        final area = tester.getSize(_areaChips().first).height;
        expect(tester.getSize(find.byKey(_pill)).height, closeTo(area, 0.01));

        // The border is part of the pill, as of every chip.
        final box = tester.widget<Container>(find
            .descendant(of: find.byKey(_pill), matching: find.byType(Container))
            .first);
        final decoration = box.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        expect(border.top.width, AppControlSizes.chipBorderWidth);
        expect(border.bottom.width, AppControlSizes.chipBorderWidth);
        expect(border.left.width, AppControlSizes.chipBorderWidth);
        expect(border.right.width, AppControlSizes.chipBorderWidth);
      });
    }
  });
}
