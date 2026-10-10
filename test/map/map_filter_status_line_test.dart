// The map's status line: how many places the map shows, and Reset while a
// filter is on. Local widget tests with the real ARB text and Flutter's test
// font: they prove what is shown, where, and that Reset calls its callback; not
// how a device renders it. (The view model's side, that the count is the
// published draw's own, is pinned in map_ux_phase1_test.dart.)

import 'package:broker_wallet/src/Views/Screens/home/map/map_filter_status_line.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the line the way the screen does, inside the app's localization.
/// The ARB assets are preloaded outside testWidgets' fake-async zone below.
Future<void> _pump(
  WidgetTester tester, {
  required int? resultCount,
  required bool canReset,
  VoidCallback? onReset,
  Locale locale = const Locale('en'),
  double width = 412,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
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
            child: Builder(
              builder: (context) => MapFilterStatusLine(
                localization: AppLocalizations.of(context),
                resultCount: resultCount,
                canReset: canReset,
                onReset: onReset ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // App startup loads these assets before building MaterialApp. Doing the
    // same outside the widget test's fake-async zone lets the delegate mount
    // the home route on the first pump, including when it loads from cache.
    await AppLocalizations.preloadAllLanguages();
    expect(AppLocalizations.translateFor('en', 'mapReset'), 'Reset');
    expect(AppLocalizations.translateFor('ar', 'mapReset'), 'إعادة تعيين');
  });

  testWidgets('shows nothing when there is no count and no filter',
      (tester) async {
    await _pump(tester, resultCount: null, canReset: false);

    expect(find.byType(MapFilterStatusLine), findsOneWidget);
    expect(find.byKey(MapFilterStatusLine.resultCountKey), findsNothing);
    expect(find.byKey(MapFilterStatusLine.resetKey), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the count alone: no Reset while the filters are the default',
      (tester) async {
    await _pump(tester, resultCount: 12, canReset: false);

    expect(find.text('12 results'), findsOneWidget);
    expect(find.byKey(MapFilterStatusLine.resultCountKey), findsOneWidget);
    expect(find.byKey(MapFilterStatusLine.resetKey), findsNothing);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('English: 0 results, 1 result, 12 results', (tester) async {
    for (final entry in {
      0: '0 results',
      1: '1 result',
      2: '2 results',
      12: '12 results',
    }.entries) {
      await _pump(tester, resultCount: entry.key, canReset: false);
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
  });

  testWidgets('Arabic: the words agree with the number', (tester) async {
    for (final entry in {
      0: 'لا توجد نتائج',
      1: 'نتيجة واحدة',
      2: 'نتيجتان',
      3: '3 نتائج',
      11: '11 نتيجة',
    }.entries) {
      await _pump(
        tester,
        resultCount: entry.key,
        canReset: false,
        locale: const Locale('ar'),
      );
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
  });

  testWidgets('Reset shows with a filter on, and calls its callback once',
      (tester) async {
    var resets = 0;
    await _pump(
      tester,
      resultCount: 3,
      canReset: true,
      onReset: () => resets++,
    );

    expect(find.text('3 results'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.byKey(MapFilterStatusLine.resetKey), findsOneWidget);

    await tester.tap(find.byKey(MapFilterStatusLine.resetKey));
    await tester.pump();
    expect(resets, 1);
  });

  testWidgets('Reset can show before there is a count', (tester) async {
    await _pump(tester, resultCount: null, canReset: true);

    expect(find.byKey(MapFilterStatusLine.resultCountKey), findsNothing);
    expect(find.text('Reset'), findsOneWidget);
    // At the end of the line, where it always is.
    final reset = tester.getRect(find.byKey(MapFilterStatusLine.resetKey));
    expect(reset.right, closeTo(412 - 16, 0.5));
  });

  testWidgets('Reset is worded in Arabic too', (tester) async {
    await _pump(
      tester,
      resultCount: 5,
      canReset: true,
      locale: const Locale('ar'),
    );

    expect(find.text('إعادة تعيين'), findsOneWidget);
    expect(find.text('5 نتائج'), findsOneWidget);
  });

  testWidgets('the count is at the start and Reset at the end, either way',
      (tester) async {
    await _pump(tester, resultCount: 3, canReset: true);
    var count = tester.getRect(find.byKey(MapFilterStatusLine.resultCountKey));
    var reset = tester.getRect(find.byKey(MapFilterStatusLine.resetKey));
    expect(count.left, closeTo(16, 0.5), reason: 'English: count at the left');
    expect(reset.right, closeTo(412 - 16, 0.5),
        reason: 'English: Reset at the right');
    expect(count.right, lessThan(reset.left));

    await _pump(
      tester,
      resultCount: 3,
      canReset: true,
      locale: const Locale('ar'),
    );
    count = tester.getRect(find.byKey(MapFilterStatusLine.resultCountKey));
    reset = tester.getRect(find.byKey(MapFilterStatusLine.resetKey));
    expect(count.right, closeTo(412 - 16, 0.5),
        reason: 'Arabic: count at the right');
    expect(reset.left, closeTo(16, 0.5), reason: 'Arabic: Reset at the left');
    expect(reset.right, lessThan(count.left));
  });

  testWidgets('the count does not move when Reset appears or goes',
      (tester) async {
    await _pump(tester, resultCount: 7, canReset: false);
    final before =
        tester.getRect(find.byKey(MapFilterStatusLine.resultCountKey));

    await _pump(tester, resultCount: 7, canReset: true);
    final after =
        tester.getRect(find.byKey(MapFilterStatusLine.resultCountKey));

    expect(after.left, closeTo(before.left, 0.01));
    expect(after.width, closeTo(before.width, 0.01));
  });

  testWidgets('a narrow screen with large text does not overflow, either way',
      (tester) async {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      await _pump(
        tester,
        resultCount: 1234,
        canReset: true,
        width: 320,
        textScale: 2,
        locale: locale,
      );
      expect(tester.takeException(), isNull, reason: locale.languageCode);
      expect(find.byKey(MapFilterStatusLine.resultCountKey), findsOneWidget);
      expect(find.byKey(MapFilterStatusLine.resetKey), findsOneWidget);
    }
  });

  testWidgets('Reset is a button with its own name for a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, resultCount: 3, canReset: true);

    expect(find.bySemanticsLabel('Reset filters'), findsWidgets);
    handle.dispose();
  });
}
