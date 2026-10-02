// The shared expandable area chips used by Add Request and Add Offer: three
// visual rows until expanded, localized Show more / Show less, selection and
// the three-area cap untouched by expanding, per-city reset, Arabic/RTL, and
// saved selections that the collapsed rows (or the catalog) would otherwise
// hide.
//
// Local widget tests with the real ARB text. The test font gives every glyph the
// same width, so these prove the layout rules, not how a real device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Widgets/expandable_area_chips.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

const _toggle = ValueKey<String>('area-chips-toggle');

/// Stands in for the form's view-model: it owns the selection and applies the
/// same select / deselect / at-most-[maxSelected] rule as `selectArea` (a limit
/// of one replaces the choice, as the Owner's single location does).
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.city,
    this.initialSelected = const <String>[],
    this.maxSelected = 3,
  });

  final String city;
  final List<String> initialSelected;
  final int maxSelected;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final List<String> selected = List<String>.of(widget.initialSelected);
  final List<String> taps = <String>[];
  String? _city;

  String get city => _city ?? widget.city;

  void setCity(String city) => setState(() => _city = city);

  void toggle(String key) {
    taps.add(key);
    setState(() {
      if (selected.contains(key)) {
        selected.remove(key);
      } else if (widget.maxSelected == 1) {
        selected
          ..clear()
          ..add(key);
      } else if (selected.length < widget.maxSelected) {
        selected.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpandableAreaChips(
            city: city,
            selectedAreas: selected,
            onToggleArea: toggle,
            localization: AppLocalizations.of(context),
            maxSelectedAreas: widget.maxSelected,
          ),
        ],
      ),
    );
  }
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester, {
  String city = 'Dubai',
  List<String> selected = const <String>[],
  double width = 360,
  Locale locale = const Locale('en'),
  double textScale = 1,
  int maxSelected = 3,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final host = GlobalKey<_HostState>();
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
        body: _Host(
          key: host,
          city: city,
          initialSelected: selected,
          maxSelected: maxSelected,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

Finder _chips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('area-chip-');
    });

Finder _chip(String areaKey) =>
    find.byKey(ValueKey<String>('area-chip-$areaKey'));

/// How many visual rows the chips occupy: the number of distinct top edges.
int _rows(WidgetTester tester) {
  final finder = _chips();
  final tops = <int>{};
  for (var i = 0; i < finder.evaluate().length; i++) {
    tops.add((tester.getTopLeft(finder.at(i)).dy * 10).round());
  }
  return tops.length;
}

Future<void> _tapToggle(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_toggle));
  await tester.pump();
  await tester.tap(find.byKey(_toggle));
  await tester.pump();
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
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('collapsed: three visual rows, whatever the screen', () {
    for (final width in const [320.0, 360.0, 412.0, 800.0, 1200.0]) {
      testWidgets('exactly three rows at ${width.toInt()} px wide',
          (tester) async {
        await _pump(tester, width: width);
        final total = UaeAreaCatalog.areasFor('Dubai').length;

        expect(_rows(tester), 3);
        expect(_chips().evaluate().length, lessThan(total));
        expect(_chips().evaluate().length, greaterThanOrEqualTo(3));
        expect(find.text(en['showMore'] as String), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a wider screen shows more chips in the same three rows',
        (tester) async {
      await _pump(tester, width: 360);
      final narrow = _chips().evaluate().length;
      await _pump(tester, width: 1200);
      final wide = _chips().evaluate().length;

      expect(wide, greaterThan(narrow),
          reason: 'the cut-off follows the layout, not a fixed chip count');
      expect(_rows(tester), 3);
    });

    testWidgets('the most important area comes first', (tester) async {
      await _pump(tester, width: 360);
      final first = tester.getTopLeft(_chips().first);
      for (final key in UaeAreaCatalog.areasFor('Dubai').take(3)) {
        expect(_chip(key), findsOneWidget, reason: key);
      }
      expect(first.dy, lessThanOrEqualTo(tester.getTopLeft(_chips().last).dy));
      expect(
        _chips().evaluate().first.widget.key,
        ValueKey<String>('area-chip-${UaeAreaCatalog.areasFor('Dubai').first}'),
      );
    });

    testWidgets('large text still stays within three rows', (tester) async {
      await _pump(tester, width: 360, textScale: 2);
      expect(_rows(tester), lessThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no Show more when every area already fits', (tester) async {
      await _pump(tester, city: 'Khor Fakkan', width: 3000);
      final total = UaeAreaCatalog.areasFor('Khor Fakkan').length;

      expect(_chips(), findsNWidgets(total));
      expect(find.byKey(_toggle), findsNothing);
      expect(find.text(en['showMore'] as String), findsNothing);
      expect(find.text(en['showLess'] as String), findsNothing);
    });

    testWidgets('Khor Fakkan shows its own areas', (tester) async {
      await _pump(tester, city: 'Khor Fakkan', width: 360);
      expect(_chip('alMudaifi'), findsOneWidget);
      expect(find.text(en['alMudaifi'] as String), findsOneWidget);
    });

    testWidgets('an unknown city renders nothing', (tester) async {
      await _pump(tester, city: 'Atlantis');
      expect(_chips(), findsNothing);
      expect(find.byKey(_toggle), findsNothing);
    });
  });

  group('Show more / Show less', () {
    testWidgets('Show more reveals every area, Show less collapses again',
        (tester) async {
      await _pump(tester, width: 360);
      final total = UaeAreaCatalog.areasFor('Dubai').length;
      final collapsed = _chips().evaluate().length;

      await _tapToggle(tester);
      expect(_chips(), findsNWidgets(total));
      expect(find.text(en['showLess'] as String), findsOneWidget);
      expect(find.text(en['showMore'] as String), findsNothing);
      expect(_chip(UaeAreaCatalog.areasFor('Dubai').last), findsOneWidget);

      await _tapToggle(tester);
      expect(_chips(), findsNWidgets(collapsed));
      expect(find.text(en['showMore'] as String), findsOneWidget);
      expect(_rows(tester), 3);
    });

    testWidgets('expanding and collapsing never changes the selection',
        (tester) async {
      final host = await _pump(tester, width: 360);
      final dubai = UaeAreaCatalog.areasFor('Dubai');

      await tester.tap(_chip(dubai[0]));
      await tester.pump();
      await tester.tap(_chip(dubai[1]));
      await tester.pump();
      expect(host.currentState!.selected, [dubai[0], dubai[1]]);

      await _tapToggle(tester);
      expect(host.currentState!.selected, [dubai[0], dubai[1]]);
      await _tapToggle(tester);
      expect(host.currentState!.selected, [dubai[0], dubai[1]]);
      expect(host.currentState!.taps, [dubai[0], dubai[1]],
          reason: 'the toggle is not an area tap');
    });

    testWidgets('areas can be selected while expanded', (tester) async {
      final host = await _pump(tester, width: 360);
      final last = UaeAreaCatalog.areasFor('Dubai').last;

      await _tapToggle(tester);
      await tester.ensureVisible(_chip(last));
      await tester.pump();
      await tester.tap(_chip(last));
      await tester.pump();

      expect(host.currentState!.selected, [last]);
      expect(_chips(), findsNWidgets(UaeAreaCatalog.areasFor('Dubai').length),
          reason: 'selecting does not collapse the list');
    });

    testWidgets('switching city returns to the collapsed top areas',
        (tester) async {
      final host = await _pump(tester, width: 360);
      await _tapToggle(tester);
      expect(find.text(en['showLess'] as String), findsOneWidget);

      host.currentState!.setCity('Abu Dhabi');
      await tester.pump();

      final abuDhabi = UaeAreaCatalog.areasFor('Abu Dhabi');
      expect(find.text(en['showMore'] as String), findsOneWidget);
      expect(find.text(en['showLess'] as String), findsNothing);
      expect(_chips().evaluate().length, lessThan(abuDhabi.length));
      expect(_chip(abuDhabi.first), findsOneWidget);
      expect(_rows(tester), 3);
    });
  });

  group('at most three selected areas', () {
    testWidgets(
        'a fourth area cannot be selected, a selected one can be undone',
        (tester) async {
      final host = await _pump(tester, width: 1200);
      final dubai = UaeAreaCatalog.areasFor('Dubai');

      for (final key in dubai.take(3)) {
        await tester.tap(_chip(key));
        await tester.pump();
      }
      expect(host.currentState!.selected, dubai.take(3).toList());

      await tester.tap(_chip(dubai[3]));
      await tester.pump();
      expect(host.currentState!.selected, dubai.take(3).toList());
      expect(host.currentState!.taps, dubai.take(3).toList(),
          reason: 'the fourth chip is inert, so it never reports a tap');

      await tester.tap(_chip(dubai[1]));
      await tester.pump();
      expect(host.currentState!.selected, [dubai[0], dubai[2]]);

      await tester.tap(_chip(dubai[3]));
      await tester.pump();
      expect(host.currentState!.selected, [dubai[0], dubai[2], dubai[3]]);
    });
  });

  group('a limit of one (a single location, as the Owner has)', () {
    testWidgets('any area can be tapped to replace the choice, none is dimmed',
        (tester) async {
      final host = await _pump(tester, width: 1200, maxSelected: 1);
      final dubai = UaeAreaCatalog.areasFor('Dubai');

      await tester.tap(_chip(dubai[0]));
      await tester.pump();
      expect(host.currentState!.selected, [dubai[0]]);
      for (final key in dubai.take(8)) {
        expect(tester.widget<SelectableChip>(_chip(key)).isEnabled, isTrue,
            reason: key);
      }

      await tester.tap(_chip(dubai[2]));
      await tester.pump();
      expect(host.currentState!.selected, [dubai[2]]);
      expect(host.currentState!.taps, [dubai[0], dubai[2]]);

      await tester.tap(_chip(dubai[2]));
      await tester.pump();
      expect(host.currentState!.selected, isEmpty);
    });

    testWidgets(
        'with the default limit the other chips are dimmed once it is '
        'reached', (tester) async {
      final host = await _pump(tester, width: 1200);
      final dubai = UaeAreaCatalog.areasFor('Dubai');

      for (final key in dubai.take(3)) {
        await tester.tap(_chip(key));
        await tester.pump();
      }

      expect(host.currentState!.selected, hasLength(3));
      expect(tester.widget<SelectableChip>(_chip(dubai[3])).isEnabled, isFalse);
      expect(tester.widget<SelectableChip>(_chip(dubai[0])).isEnabled, isTrue);
    });
  });

  group('saved selections stay visible (edit mode)', () {
    testWidgets('an area far down the catalog is shown while collapsed',
        (tester) async {
      final dubai = UaeAreaCatalog.areasFor('Dubai');
      final far = dubai.last;
      expect(dubai.indexOf(far), greaterThan(40));

      final host = await _pump(tester, width: 360, selected: [far]);

      expect(_chip(far), findsOneWidget);
      expect(_rows(tester), lessThanOrEqualTo(3));
      expect(find.text(en['showMore'] as String), findsOneWidget);
      expect(host.currentState!.selected, [far]);
    });

    testWidgets('three saved areas deep in the list all stay visible',
        (tester) async {
      final dubai = UaeAreaCatalog.areasFor('Dubai');
      final saved = dubai.reversed.take(3).toList();

      await _pump(tester, width: 360, selected: saved);

      for (final key in saved) {
        expect(_chip(key), findsOneWidget, reason: key);
      }
      expect(_rows(tester), lessThanOrEqualTo(3));
    });

    testWidgets('a legacy key the catalog no longer offers still renders',
        (tester) async {
      // 'alShabiya' was offered for Umm Al Quwain by an older picker.
      expect(UaeAreaCatalog.isOffered('Umm Al Quwain', 'alShabiya'), isFalse);
      final host = await _pump(
        tester,
        city: 'Umm Al Quwain',
        width: 360,
        selected: const ['alShabiya'],
      );

      expect(_chip('alShabiya'), findsOneWidget);
      expect(find.text(en['alShabiya'] as String), findsOneWidget);
      expect(host.currentState!.selected, ['alShabiya']);

      await tester.tap(_chip('alShabiya'));
      await tester.pump();
      expect(host.currentState!.selected, isEmpty,
          reason: 'the user can still remove a legacy selection');
    });

    testWidgets('an unknown saved value is shown as stored, not dropped',
        (tester) async {
      await _pump(
        tester,
        city: 'Dubai',
        width: 360,
        selected: const ['Old Free Text Area'],
      );
      expect(find.text('Old Free Text Area'), findsOneWidget);
      expect(find.textContaining('not found'), findsNothing);
    });

    testWidgets('an old key keeps its saved name in Arabic', (tester) async {
      await _pump(
        tester,
        city: 'Dubai',
        width: 360,
        locale: const Locale('ar'),
        selected: const ['jumeirah'],
      );
      expect(find.text(ar['jumeirah'] as String), findsOneWidget);
    });
  });

  group('Arabic and RTL', () {
    testWidgets('three rows, no overflow, localized toggle at a narrow width',
        (tester) async {
      await _pump(
        tester,
        width: 320,
        locale: const Locale('ar'),
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(_rows(tester), 3);
      expect(find.text(ar['showMore'] as String), findsOneWidget);
      final first = UaeAreaCatalog.areasFor('Dubai').first;
      expect(find.text(ar[first] as String), findsOneWidget);
    });

    testWidgets('chips flow from the right edge', (tester) async {
      await _pump(tester, width: 360, locale: const Locale('ar'));
      final first = UaeAreaCatalog.areasFor('Dubai').first;
      expect(tester.getTopRight(_chip(first)).dx, greaterThan(330));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Show less is Arabic once expanded', (tester) async {
      await _pump(tester, width: 360, locale: const Locale('ar'));
      await _tapToggle(tester);
      expect(find.text(ar['showLess'] as String), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every Arabic catalog name renders in every city',
        (tester) async {
      for (final city in UaeAreaCatalog.supportedCities) {
        await _pump(tester, city: city, width: 320, locale: const Locale('ar'));
        expect(tester.takeException(), isNull, reason: city);
        expect(_rows(tester), lessThanOrEqualTo(3), reason: city);
      }
    });
  });

  group('planCollapsedAreaChips', () {
    List<int> plan(
      List<double> widths, {
      Set<int> selected = const <int>{},
      double maxWidth = 320,
      double spacing = 10,
      int maxRows = 3,
    }) =>
        planCollapsedAreaChips(
          count: widths.length,
          widthOf: (i) => widths[i],
          selected: selected,
          maxWidth: maxWidth,
          spacing: spacing,
          maxRows: maxRows,
        );

    int rowsOf(List<double> widths, List<int> shown,
        {double maxWidth = 320, double spacing = 10}) {
      var rows = 0;
      var used = 0.0;
      for (final i in shown) {
        final w = math.min(widths[i], maxWidth);
        if (rows == 0) {
          rows = 1;
          used = w;
        } else if (used + spacing + w <= maxWidth + 1e-10) {
          used += spacing + w;
        } else {
          rows++;
          used = w;
        }
      }
      return rows;
    }

    test('everything fits: nothing is hidden', () {
      final shown = plan(List<double>.filled(5, 100));
      expect(shown, [0, 1, 2, 3, 4]);
    });

    test('keeps the longest prefix that fits in three rows', () {
      // Three 100 px chips per 320 px row (100 + 10 + 100 + 10 + 100).
      final shown = plan(List<double>.filled(20, 100));
      expect(shown, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('a wider chip leaves fewer in the same rows', () {
      final widths = [250.0, 250, 250, 250, 250, 250];
      expect(plan(widths), [0, 1, 2]);
    });

    test('a chip wider than the row takes a row to itself', () {
      final widths = [500.0, 100, 100, 100, 100, 100, 100, 100];
      final shown = plan(widths);
      expect(rowsOf(widths, shown), 3);
      expect(shown.first, 0);
      expect(shown.length, lessThan(widths.length));
    });

    test('a selected area beyond the cut-off is kept, the prefix shrinks', () {
      final widths = List<double>.filled(20, 100);
      final shown = plan(widths, selected: {15});
      expect(shown, [0, 1, 2, 3, 4, 5, 6, 7, 15]);
      expect(rowsOf(widths, shown), 3);
    });

    test('a selected area inside the cut-off changes nothing', () {
      final widths = List<double>.filled(20, 100);
      expect(plan(widths, selected: {2}), plan(widths));
    });

    test('several selected areas are kept in catalog order', () {
      final widths = List<double>.filled(20, 100);
      final shown = plan(widths, selected: {19, 11, 14});
      expect(shown.sublist(shown.length - 3), [11, 14, 19]);
      expect(rowsOf(widths, shown), 3);
    });

    test('the rows never exceed the limit, whatever the widths', () {
      final random = math.Random(42);
      for (var run = 0; run < 400; run++) {
        final count = 1 + random.nextInt(60);
        final widths = <double>[
          for (var i = 0; i < count; i++) 40 + random.nextDouble() * 330,
        ];
        final maxWidth = 200 + random.nextDouble() * 400;
        final selectedCount = random.nextInt(4);
        final selected = <int>{
          for (var i = 0; i < selectedCount; i++) random.nextInt(count),
        };
        final rows = 1 + random.nextInt(4);
        final shown =
            plan(widths, selected: selected, maxWidth: maxWidth, maxRows: rows);

        // Every selected area is always shown, and nothing is shown twice.
        expect(shown.toSet().containsAll(selected), isTrue, reason: 'run $run');
        expect(shown.toSet().length, shown.length, reason: 'run $run');

        if (shown.length == count) {
          expect(shown, List<int>.generate(count, (i) => i),
              reason: 'run $run: all shown means all in order');
        } else {
          // Hidden chips exist. The shown ones must fit in the allowed rows,
          // unless the selected areas alone are already more than that.
          final selectedAlone = selected.toList()..sort();
          if (rowsOf(widths, selectedAlone, maxWidth: maxWidth) <= rows) {
            expect(rowsOf(widths, shown, maxWidth: maxWidth),
                lessThanOrEqualTo(rows),
                reason: 'run $run');
          }
        }
      }
    });
  });
}
