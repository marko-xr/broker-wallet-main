// The app's shared control sizes ([AppControlSizes]) and the reusable controls
// that read them: large actions share one height, compact inline actions another,
// every quick-pick chip is one size, nothing tappable falls under its floor, and
// no equivalent control keeps a private copy of a size the tokens own.
//
// "Same size" means same KIND of control: a chip, a text field, an icon button
// and a large action keep their own sizes, and these tests do not ask otherwise.
//
// Local widget and source tests with the real ARB text. The test font gives every
// glyph the same width, so they prove the sizing rules, not how a real device
// renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/views/Widgets/property_type_chips.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';
import 'package:broker_wallet/src/views/Widgets/uae_city_area_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const _pill = ValueKey<String>('city-pill');
const _pillClear = ValueKey<String>('city-pill-clear');
const _toggle = ValueKey<String>('area-chips-toggle');

Future<void> _pump(
  WidgetTester tester, {
  required WidgetBuilder body,
  Locale locale = const Locale('en'),
  double textScale = 1,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 3000);
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
          padding: const EdgeInsets.all(16),
          child: Builder(builder: body),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every kind of quick-pick chip the forms show, in one column: the bare chip in
/// each of its three looks, the Owner's property types, the city chips and, for
/// a chosen city, the pill and the area chips.
Widget _everyChip(BuildContext context, {String city = ''}) {
  final localization = AppLocalizations.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: AppControlSizes.chipSpacing,
        runSpacing: AppControlSizes.chipSpacing,
        children: [
          SelectableChip(label: 'Plain', isSelected: false, onTap: () {}),
          SelectableChip(label: 'Chosen', isSelected: true, onTap: () {}),
          SelectableChip(
            label: 'Dimmed',
            isSelected: false,
            isEnabled: false,
            onTap: () {},
          ),
        ],
      ),
      const SizedBox(height: 12),
      PropertyTypeChips(
        value: '',
        onSelected: (_) {},
        localization: localization,
      ),
      const SizedBox(height: 12),
      UaeCityAreaPicker(
        cities: UaeAreaCatalog.supportedCities,
        selectedCity: city,
        onCityChanged: (_) {},
        selectedAreas: const <String>[],
        onToggleArea: (_) {},
        localization: localization,
      ),
    ],
  );
}

/// The pill as the forms place it: in a Row, which lets it take its own width.
Widget _standalonePill(VoidCallback onClear) => Row(
      children: [
        ClearableChip(
          key: _pill,
          clearKey: _pillClear,
          label: 'Dubai',
          onClear: onClear,
        ),
      ],
    );

// Wide enough that no chip label wraps: the test font gives every glyph a full
// em, so on a phone-width screen a long area name would take two lines and these
// tests, which compare chip HEIGHTS, would be measuring the wrap.
const double _wide = 1200;

/// The vertical room a chip adds around its label: padding and border, both
/// sides.
double get _chipChrome =>
    2 * (AppControlSizes.chipVerticalPadding + AppControlSizes.chipBorderWidth);

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

  group('the shared size tokens', () {
    test('large actions have one height, and the form actions are those', () {
      expect(AppControlSizes.standardButtonHeight, 48);
      expect(AppControlSizes.formActionHeight,
          AppControlSizes.standardButtonHeight);
    });

    test('a compact inline action is shorter than a large one, not tiny', () {
      expect(AppControlSizes.compactButtonHeight, 40);
      expect(AppControlSizes.compactButtonHeight,
          lessThan(AppControlSizes.standardButtonHeight));
    });

    test('the touch-target floor is 48 and no large action is under it', () {
      expect(AppControlSizes.minTouchTarget, 48);
      expect(AppControlSizes.standardButtonHeight,
          greaterThanOrEqualTo(AppControlSizes.minTouchTarget));
      expect(AppControlSizes.formActionHeight,
          greaterThanOrEqualTo(AppControlSizes.minTouchTarget));
    });

    test('the chip metrics are the values the chips always had', () {
      expect(AppControlSizes.chipHorizontalPadding, 18);
      expect(AppControlSizes.chipVerticalPadding, 9);
      expect(AppControlSizes.chipBorderWidth, 1.3);
      expect(AppControlSizes.chipRadius, 32);
      expect(AppControlSizes.chipSpacing, 10);
    });

    test('the chip widget reads the tokens', () {
      expect(SelectableChip.horizontalPadding,
          AppControlSizes.chipHorizontalPadding);
      expect(
          SelectableChip.verticalPadding, AppControlSizes.chipVerticalPadding);
      expect(SelectableChip.borderWidth, AppControlSizes.chipBorderWidth);
      // The row planner measures a chip's width from these.
      expect(
        SelectableChip.horizontalInset,
        2 *
            (AppControlSizes.chipHorizontalPadding +
                AppControlSizes.chipBorderWidth),
      );
    });
  });

  group('every quick-pick chip is one size', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      for (final city in const ['', 'Dubai']) {
        final tag = '${locale.languageCode}, '
            '${city.isEmpty ? 'city chips' : 'area chips'}';

        testWidgets('same height, padding and border: $tag', (tester) async {
          await _pump(
            tester,
            locale: locale,
            width: _wide,
            body: (context) => _everyChip(context, city: city),
          );

          final chips = find.byType(SelectableChip);
          expect(chips.evaluate().length, greaterThan(20),
              reason:
                  'the bare chips, the property types and the cities/areas');

          final heights = <double>[];
          for (var i = 0; i < chips.evaluate().length; i++) {
            final chip = chips.at(i);
            final text = find.descendant(
              of: chip,
              matching: find.byType(Text),
            );
            final height = tester.getSize(chip).height;
            heights.add(height);

            expect(
              height - tester.getSize(text).height,
              closeTo(_chipChrome, 0.01),
              reason: 'chip $i: label plus the shared padding and border',
            );
          }
          for (final height in heights) {
            expect(height, closeTo(heights.first, 0.01),
                reason: 'all the chips of one language are one height');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('selected, unselected and dimmed chips do not differ in size',
        (tester) async {
      await _pump(tester, width: _wide, body: (context) => _everyChip(context));

      final plain =
          tester.getSize(find.widgetWithText(SelectableChip, 'Plain'));
      final chosen =
          tester.getSize(find.widgetWithText(SelectableChip, 'Chosen'));
      final dimmed =
          tester.getSize(find.widgetWithText(SelectableChip, 'Dimmed'));

      expect(chosen.height, plain.height);
      expect(dimmed.height, plain.height);
    });

    testWidgets('the chosen-city pill is exactly as tall as a chip',
        (tester) async {
      await _pump(tester,
          body: (context) => _everyChip(context, city: 'Dubai'));

      final pill = find.byKey(_pill);
      final pillText = find.descendant(of: pill, matching: find.byType(Text));
      final chip = tester.getSize(find.byType(SelectableChip).first);

      expect(tester.getSize(pill).height, closeTo(chip.height, 0.01),
          reason: 'it has the same border and padding as every chip');
      expect(
        tester.getSize(pill).height - tester.getSize(pillText).height,
        closeTo(_chipChrome, 0.01),
        reason: 'label line + the shared padding and border, like any chip',
      );
    });

    test('the chip spacing the planner uses is the one the Wraps use', () {
      expect(
        _read('lib/src/views/Widgets/expandable_area_chips.dart').contains(
            'const double _chipSpacing = AppControlSizes.chipSpacing;'),
        isTrue,
      );
      // The widgets that are made of quick-pick chips read the one gap.
      for (final path in const [
        'lib/src/views/Widgets/property_type_chips.dart',
        'lib/src/views/Widgets/uae_city_area_picker.dart',
      ]) {
        final source = _read(path);
        expect(source.contains('spacing: AppControlSizes.chipSpacing'), isTrue,
            reason: path);
        expect(RegExp(r'spacing: 10,').hasMatch(source), isFalse,
            reason: '$path keeps its own chip gap');
      }
      // Request and Offer: their city chips read it too. (Their property-type
      // rows are Material ChoiceChips, a different chip, and keep their own
      // Wrap spacing.)
      for (final path in const [
        'lib/src/views/Screens/ViewAdd/add_requested_view.dart',
        'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
      ]) {
        final source = _read(path);
        expect(
          RegExp(r'spacing: AppControlSizes\.chipSpacing,\s*runSpacing: '
                  r'AppControlSizes\.chipSpacing,')
              .hasMatch(source),
          isTrue,
          reason: '$path: the city chips use the shared gap',
        );
      }
    });
  });

  group('the pill\'s clear button is easy to hit', () {
    testWidgets('its tap area is the icon plus the pill padding, not 18 px',
        (tester) async {
      await _pump(tester,
          body: (context) => _everyChip(context, city: 'Dubai'));

      final area = tester.getSize(find.byKey(_pillClear));
      final pill = tester.getSize(find.byKey(_pill));
      expect(area.width, closeTo(44, 0.01),
          reason: '8 to the label, the 18 px icon, 18 to the pill edge');
      expect(
        area.height,
        closeTo(pill.height - 2 * AppControlSizes.chipBorderWidth, 0.01),
        reason: 'the pill\'s full inner height, inside its border',
      );
      expect(area.width, greaterThan(ClearableChip.clearIconSize * 2));
      expect(area.height, greaterThan(ClearableChip.clearIconSize * 2));
    });

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets(
          '${locale.languageCode}: a tap beside the icon, in the padding, clears',
          (tester) async {
        var cleared = 0;
        await _pump(
          tester,
          locale: locale,
          body: (context) => _standalonePill(() => cleared++),
        );

        final centre = tester.getCenter(find.byKey(_pillClear));
        // The icon is 18 px wide: these are well outside it, inside the area.
        await tester.tapAt(centre + const Offset(14, 0));
        await tester.tapAt(centre + const Offset(-10, 0));
        await tester.tapAt(centre + const Offset(0, 15));
        expect(cleared, 3);
      });
    }

    testWidgets('the label is not part of the clear button', (tester) async {
      var cleared = 0;
      await _pump(
        tester,
        body: (context) => _standalonePill(() => cleared++),
      );

      await tester.tap(find.text('Dubai'));
      expect(cleared, 0);
    });

    testWidgets('the pill is its label, the x area and the chip border',
        (tester) async {
      await _pump(
        tester,
        body: (context) => _standalonePill(() {}),
      );

      final text = tester.getSize(find.text('Dubai')).width;
      // 18 + label + 8 + 18 (icon) + 18 as the private pills laid out, plus the
      // 1.3 border on each side that every chip has.
      expect(
        tester.getSize(find.byKey(_pill)).width,
        closeTo(text + 62 + 2 * AppControlSizes.chipBorderWidth, 0.01),
      );
    });
  });

  group('the compact inline action', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets(
          '${locale.languageCode}: the "Show more" toggle has the compact height',
          (tester) async {
        await _pump(
          tester,
          locale: locale,
          width: _wide,
          body: (context) => _everyChip(context, city: 'Dubai'),
        );

        final toggle = tester.getSize(find.byKey(_toggle));
        expect(toggle.height,
            greaterThanOrEqualTo(AppControlSizes.compactButtonHeight));
        expect(toggle.height, lessThan(AppControlSizes.standardButtonHeight),
            reason: 'a compact action is not a large one');
      });
    }

    testWidgets('it still answers to a tap and toggles', (tester) async {
      await _pump(tester,
          width: _wide, body: (context) => _everyChip(context, city: 'Dubai'));

      final before = find.byType(SelectableChip).evaluate().length;
      await tester.tap(find.byKey(_toggle));
      await tester.pump();

      expect(
          find.byType(SelectableChip).evaluate().length, greaterThan(before));
    });

    test('the toggle reads the shared compact height', () {
      final source = _read('lib/src/views/Widgets/expandable_area_chips.dart');
      expect(source.contains('AppControlSizes.compactButtonHeight'), isTrue);
      expect(source.contains('fromLTRB(2, 10, 8, 4)'), isFalse,
          reason: 'the old 10-above-4-below padding made it about 34 high');
    });
  });

  group('large actions read one token, not their own 48', () {
    const sharedWidgets = [
      'lib/src/views/Widgets/feedback_success_bottom_sheet.dart',
      'lib/src/views/Widgets/logout_confirmation_bottom_sheet.dart',
      'lib/src/views/Widgets/email_addition_dialog.dart',
    ];

    for (final path in sharedWidgets) {
      final name = path.split('/').last;

      test('$name: the full-width action is the standard height', () {
        final source = _read(path);
        expect(source.contains('app_control_sizes.dart'), isTrue);
        expect(source.contains('AppControlSizes.standardButtonHeight'), isTrue);
        expect(RegExp(r'height: 48\b').hasMatch(source), isFalse,
            reason: '$name still hard-codes the standard height');
      });
    }

    test('Save / Cancel, sheets and dialogs are all the one height', () {
      expect(AppControlSizes.formActionHeight, 48);
      expect(AppControlSizes.standardButtonHeight, 48);
    });
  });

  group('no equivalent control keeps a private copy of a chip size', () {
    test('only the chip component spells the chip padding', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) {
            final source = f.readAsStringSync();
            return RegExp(r'horizontal: 18,\s*vertical: 9').hasMatch(source) ||
                RegExp(r'vertical: 9,\s*horizontal: 18').hasMatch(source);
          })
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      expect(offenders, isEmpty);
    });

    test('Request and Offer city chips and pills are the shared components',
        () {
      for (final path in const [
        'lib/src/views/Screens/ViewAdd/add_requested_view.dart',
        'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
      ]) {
        final source = _read(path);
        expect(source.contains('selectable_chip.dart'), isTrue, reason: path);
        expect(source.contains('SelectableChip('), isTrue, reason: path);
        expect(source.contains('ClearableChip('), isTrue, reason: path);
        expect(source.contains('BorderRadius.circular(32)'), isFalse,
            reason: '$path keeps its own pill corners');
        // The area catalog and its three-row component are untouched.
        expect(source.contains('ExpandableAreaChips('), isTrue, reason: path);
        expect(source.contains('selectedAreas: vm.selectedAreas'), isTrue,
            reason: path);
        expect(source.contains('onToggleArea: vm.selectArea'), isTrue,
            reason: path);
      }
    });

    test('the Owner picker uses the shared pill', () {
      final source = _read('lib/src/views/Widgets/uae_city_area_picker.dart');
      expect(source.contains('ClearableChip('), isTrue);
      expect(source.contains('BorderRadius.circular(32)'), isFalse);
    });
  });
}
