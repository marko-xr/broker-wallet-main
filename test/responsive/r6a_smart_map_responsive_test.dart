import 'dart:async';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_filter_bar.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_filter_status_line.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'r6a_map_fakes.dart';
import 'responsive_harness.dart';

const _sizes = [
  Size(280, 600),
  Size(320, 568),
  Size(360, 640),
  Size(393, 852),
  Size(430, 932),
  Size(640, 360),
  Size(600, 800),
  Size(800, 1280),
];

ClusteredLocationInfo _cluster(int count) => ClusteredLocationInfo(
      coordinates: const LatLng(25.2, 55.3),
      items: List.generate(
          count,
          (i) => LocationInfo(
                id: 'fixture-$i',
                title:
                    'اسم عقار طويل جداً Long property title repeated for layout $i',
                address: 'Dubai Marina, Dubai عنوان طويل لاختبار البطاقة',
                coordinates: const LatLng(25.2, 55.3),
                type: LocationFilter.values[1 + i % 4],
                color:
                    LocationColors.getColor(LocationFilter.values[1 + i % 4]),
                icon: Icons.place,
                phoneNumber: '0500000000',
              )),
    );

Future<LayoutMapModel> _open(WidgetTester tester, ResponsiveCase c,
    {int cards = 0, bool fail = false}) async {
  final source = LayoutMapSource()..fail = fail;
  final device = LayoutMapDevice();
  final vm = LayoutMapModel(source, device,
      cluster: cards == 0 ? null : _cluster(cards));
  await pumpResponsive(tester, c,
      home: MapViewScreen(
        viewModel: vm,
        mapSurface: const SizedBox.expand(key: Key('local-map-surface')),
      ));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expectNoLayoutException(tester, c);
  expect(source.reads, 1);
  expect(device.checks, 1);
  expect(device.unexpectedAccesses, 0);
  addTearDown(() => expect(device.unexpectedAccesses, 0));
  return vm;
}

AppLocalizations _loc(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MapFilterBar)));

Future<void> _chip(WidgetTester tester, String key) async {
  final target = find.descendant(
      of: find.byType(MapFilterBar),
      matching: find.text(_loc(tester).translate(key)));
  final scrollable = find.descendant(
      of: find.byType(MapFilterBar), matching: find.byType(Scrollable));
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(prepareResponsiveAssets);
  testWidgets(
      'map loading never announces zero before the local read completes',
      (tester) async {
    final source = LayoutMapSource()
      ..pending = Completer<List<CachedLocationData>>();
    final device = LayoutMapDevice();
    final vm = LayoutMapModel(source, device);
    const c = ResponsiveCase(Size(320, 568), textScale: 1.6);
    await pumpResponsive(tester, c,
        home:
            MapViewScreen(viewModel: vm, mapSurface: const SizedBox.expand()));
    expect(vm.resultCount, isNull);
    expect(find.byKey(MapFilterStatusLine.resultCountKey), findsNothing);
    source.pending!.complete([]);
    await tester.pumpAndSettle();
    expect(vm.resultCount, 0);
    expect(find.byKey(MapFilterStatusLine.resultCountKey), findsOneWidget);
    expect(device.unexpectedAccesses, 0);
  });
  for (var i = 0; i < _sizes.length; i++) {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final c = ResponsiveCase(_sizes[i],
          locale: locale,
          dark: i.isOdd,
          textScale: const [2.0, 1.6, 1.3, 1.0][i % 4],
          safeArea: const EdgeInsets.only(top: 24, bottom: 16));
      testWidgets('map shell and scaled filter text $c', (tester) async {
        final vm = await _open(tester, c);
        expect(vm.resultCount, 0);
        if (c.textScale == 1) {
          expect(tester.getRect(find.byType(MapFilterBar)).top,
              c.safeArea.top + 76);
          expect(tester.getSize(find.byType(MapFilterBar)).height, 48);
        }
        expect(find.byKey(const Key('local-map-surface')), findsOneWidget);
        final bar = tester.getRect(find.byType(MapFilterBar));
        final field = tester.getRect(find.byType(TextField));
        expect(field.bottom, lessThanOrEqualTo(bar.top),
            reason: 'search/filter separation');
        for (final e in find
            .descendant(
                of: find.byType(MapFilterBar), matching: find.byType(RichText))
            .evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final painter = TextPainter(
              text: p.text,
              textDirection: p.textDirection,
              textScaler: p.textScaler)
            ..layout();
          expect(p.size.height, greaterThanOrEqualTo(painter.height - .1),
              reason: 'scaled filter label must not clip');
          painter.dispose();
        }
        expect(tester.getRect(find.byType(MapFilterStatusLine)).top,
            greaterThanOrEqualTo(bar.bottom));
      });
      for (final count in [1, 4]) {
        testWidgets('map selected $count cards $c', (tester) async {
          final vm = await _open(tester, c, cards: count);
          expect(find.byType(PageView), findsOneWidget);
          final pager = tester.getRect(find.byType(PageView));
          expect(
              pager.top,
              greaterThanOrEqualTo(
                  tester.getRect(find.byType(MapFilterStatusLine)).bottom),
              reason: 'selected card must not cover map filters');
          for (var page = 1; page < count; page++) {
            final width = tester.getSize(find.byType(PageView)).width;
            await tester.drag(
                find.byType(PageView),
                Offset(
                    (locale.languageCode == 'ar' ? 1 : -1) * width * .85, 0));
            await tester.pumpAndSettle();
            expect(vm.cluster!.activeIndex, page);
            expectNoLayoutException(tester, c);
          }
          expectNoLayoutException(tester, c);
          // Check the middle and bottom of the real selected-card scroller;
          // contact actions are inspected, never launched by a layout test.
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -80));
          await tester.pumpAndSettle();
          expectNoLayoutException(tester, c);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -600));
          await tester.pumpAndSettle();
          final contact = find
              .descendant(
                  of: find.byType(PageView),
                  matching: find.text(_loc(tester).translate('whatsapp')))
              .hitTestable();
          expect(contact, findsOneWidget);
          final action =
              find.ancestor(of: contact, matching: find.byType(InkWell)).first;
          expect(tester.widget<InkWell>(action).onTap, isNotNull);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, 600));
          await tester.pumpAndSettle();
          final close = find.byIcon(Icons.close_rounded).hitTestable().first;
          await tester.ensureVisible(close);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(vm.cluster, isNull);
        });
      }
      testWidgets('map sheets and local filters $c', (tester) async {
        final vm = await _open(tester, c);
        final loc = _loc(tester);
        await _chip(tester, 'mapFilterLayers');
        expectNoLayoutException(tester, c);
        await tester
            .tap(find.widgetWithText(ListTile, loc.translate('offers')));
        await tester.pumpAndSettle();
        expect(vm.filterState.entityType, LocationFilter.offers);
        for (final key in [
          'mapFilterLocation',
          'propertyType',
          'mapFilterTransaction',
          'mapFilterSort'
        ]) {
          await _chip(tester, key);
          expectNoLayoutException(tester, c);
          Navigator.of(tester.element(find.byType(ListTile).first)).pop();
          await tester.pumpAndSettle();
        }
        await _chip(tester, 'mapFilterPrice');
        expectNoLayoutException(tester, c);
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(1), '900');
        await tester.enterText(fields.at(2), '100');
        final apply =
            find.widgetWithText(FilledButton, loc.translate('mapPriceApply'));
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(find.text(loc.translate('mapPriceOrder')), findsOneWidget);
        expectNoLayoutException(tester, c);
        expect(vm.source.reads, 1,
            reason: 'presentation changes must not reload data');
      });
      testWidgets('map failed local read $c', (tester) async {
        final vm = await _open(tester, c, fail: true);
        expect(vm.hasLoadError, isTrue);
        expect(
            find.text(_loc(tester).translate('mapLoadFailed')), findsOneWidget);
      });
    }
  }
  for (var i = 0; i < _sizes.length; i++) {
    final c = ResponsiveCase(_sizes[i],
        locale: Locale(i.isEven ? 'ar' : 'en'),
        textScale: 2,
        dark: i.isOdd,
        keyboard: _sizes[i].height < 400 ? 120 : 220,
        safeArea: const EdgeInsets.only(top: 24, bottom: 16));
    testWidgets('map price keyboard reaches apply and keeps bounds $c',
        (tester) async {
      final vm = await _open(tester, c);
      vm.setEntityType(LocationFilter.offers);
      await tester.pumpAndSettle();
      final loc = _loc(tester);
      await _chip(tester, 'mapFilterPrice');
      expectNoLayoutException(tester, c);
      await tester.enterText(find.byType(TextField).at(1), '100');
      await tester.enterText(find.byType(TextField).at(2), '900');
      final apply =
          find.widgetWithText(FilledButton, loc.translate('mapPriceApply'));
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      expect(tester.getRect(apply).bottom,
          lessThanOrEqualTo(c.size.height - c.keyboard));
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(vm.filterState.priceRange!.min, 100);
      expect(vm.filterState.priceRange!.max, 900);
      expect(vm.source.reads, 1);
      expectNoLayoutException(tester, c);
    });
  }
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets(
        'map nearby radius presentation without a location request $locale',
        (tester) async {
      final c =
          ResponsiveCase(const Size(280, 600), locale: locale, textScale: 2);
      final vm = await _open(tester, c);
      vm.showNearbyPresentation();
      await tester.pumpAndSettle();
      final loc = _loc(tester);
      final label = loc.translate('mapNearbyActive').replaceAll('{km}', '10');
      final target = find.descendant(
          of: find.byType(MapFilterBar), matching: find.text(label));
      final scrollable = find.descendant(
          of: find.byType(MapFilterBar), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(4));
      expectNoLayoutException(tester, c);
      expect(vm.device.unexpectedAccesses, 0);
      expect(vm.source.reads, 1);
    });
    testWidgets('map live resize retains search and filters $locale',
        (tester) async {
      final c = ResponsiveCase(const Size(393, 852), locale: locale);
      final vm = await _open(tester, c);
      vm.setCity('Dubai');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dubai Marina');
      final focus = tester.widget<TextField>(find.byType(TextField));
      final controller = focus.controller;
      final focusNode =
          tester.widget<EditableText>(find.byType(EditableText)).focusNode;
      expect(focusNode.hasFocus, isTrue);
      for (final size in [const Size(640, 360), const Size(280, 600)]) {
        final resized = ResponsiveCase(size, locale: locale, textScale: 2);
        await pumpResponsive(tester, resized,
            home: MapViewScreen(
                viewModel: vm,
                mapSurface:
                    const SizedBox.expand(key: Key('local-map-surface'))));
        expect(tester.widget<TextField>(find.byType(TextField)).controller,
            same(controller));
        expect(controller!.text, 'Dubai Marina');
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode,
            same(focusNode));
        expect(focusNode.hasFocus, isTrue);
        expect(vm.filterState.city, 'Dubai');
        expect(vm.source.reads, 1);
        expect(vm.device.checks, 1);
      }
      await tester.tap(find.byKey(MapFilterStatusLine.resetKey));
      await tester.pumpAndSettle();
      expect(vm.filtersActive, isFalse);
      expect(vm.source.reads, 1);
    });
    for (final count in [null, 123456789]) {
      testWidgets('map long/unknown status and reset $locale $count',
          (tester) async {
        var resets = 0;
        final c =
            ResponsiveCase(const Size(280, 600), locale: locale, textScale: 2);
        await pumpResponsive(tester, c,
            home: Scaffold(
                body: Builder(
                    builder: (context) => MapFilterStatusLine(
                        localization: AppLocalizations.of(context),
                        resultCount: count,
                        canReset: true,
                        onReset: () => resets++))));
        expect(find.byKey(MapFilterStatusLine.resultCountKey),
            count == null ? findsNothing : findsOneWidget);
        await tester.tap(find.byKey(MapFilterStatusLine.resetKey));
        expect(resets, 1);
        expectNoLayoutException(tester, c);
      });
    }
  }
}
