// Smart Map UX Phase 1: control semantics and the top UI.
//
// The controls are named for what they are (Layers, Location, Near Me, Sort;
// Location and Near Me are two chips of their own), Reset appears only while
// the filters differ from the default, a result count says how many places the
// markers on the map stand for, and the search box is the same search with a
// new hint. None of it changes what the map filters, loads or frames: this
// file pins the new names and the new status line, and that they read nothing.
// (The Sort words are in map_price_test.dart.) Plain Dart: source and string
// guards, and the real filter controller and draw pipeline.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_result_count.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bar = 'lib/src/views/Screens/home/map/map_filter_bar.dart';
const String _view = 'lib/src/views/Screens/home/map/map_view.dart';
const String _viewModel = 'lib/src/views/Screens/home/map/map_viewmodel.dart';
const String _statusLine =
    'lib/src/views/Screens/home/map/map_filter_status_line.dart';
const String _resultCount = 'lib/src/services/map_result_count.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

int _count(String text, String needle) =>
    needle.isEmpty ? 0 : text.split(needle).length - 1;

String _between(String text, String from, String to) {
  final start = text.indexOf(from);
  expect(start, greaterThanOrEqualTo(0), reason: from);
  final end = text.indexOf(to, start + from.length);
  expect(end, greaterThan(start), reason: to);
  return text.substring(start, end);
}

// The room the map's controls leave, as the screen passes it.
const MapViewport _phone = MapViewport(
  width: 360,
  height: 780,
  top: 156,
  bottom: 72,
  left: 16,
  right: 16,
);

CachedLocationData _place(
  String id, {
  LocationFilter type = LocationFilter.offers,
  String? city = 'Dubai',
}) =>
    CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: 25.2048,
      longitude: 55.2708,
      type: type,
      city: city,
    );

/// A position that is always there, and counts how often it was asked.
class _CountingLocator implements NearbyLocator {
  _CountingLocator(this.fix);

  final NearbyFix fix;
  int calls = 0;

  @override
  Future<NearbyFix> locate() async {
    calls++;
    return fix;
  }
}

/// The words for [count] in [code], from the real ARB table.
String _words(String code, int count) {
  final table = _arb(code);
  return MapResultCount.text(
    count,
    languageCode: code,
    translate: (key) => table[key] as String,
  );
}

void main() {
  group('the controls are named for what they are', () {
    test('English: Layers, Location, Near Me, Reset and the search hint', () {
      final table = _arb('en');
      expect(table['mapFilterLayers'], 'Layers');
      expect(table['mapFilterLocation'], 'Location');
      expect(table['mapFilterNearby'], 'Near Me');
      expect(table['mapNearbyActive'], 'Near Me · {km} km');
      expect(table['mapNearbyRadius'], 'Near Me radius');
      expect(table['mapNearbyTurnOff'], 'Turn off Near Me');
      expect(table['mapAllUae'], 'All UAE');
      expect(table['mapFilterSort'], 'Sort');
      expect(table['mapReset'], 'Reset');
      expect(table['mapResetFilters'], 'Reset filters');
      expect(table['mapSearchHint'], 'Search location...');
    });

    test('Arabic: map layers, location, near me, sort, reset, the hint', () {
      final table = _arb('ar');
      expect(table['mapFilterLayers'], 'طبقات الخريطة');
      expect(table['mapFilterLocation'], 'الموقع');
      expect(table['mapFilterNearby'], 'بالقرب مني');
      expect(table['mapNearbyActive'], 'بالقرب مني · {km} كم');
      expect(table['mapNearbyRadius'], 'نطاق البحث');
      expect(table['mapNearbyTurnOff'], 'إيقاف «بالقرب مني»');
      expect(table['mapAllUae'], 'كل الإمارات');
      expect(table['mapFilterSort'], 'الترتيب');
      expect(table['mapReset'], 'إعادة تعيين');
      expect(table['mapResetFilters'], 'إعادة تعيين عوامل التصفية');
      expect(table['mapSearchHint'], 'ابحث عن موقع...');
    });

    test('no two controls share a name, in either language', () {
      for (final code in ['en', 'ar']) {
        final table = _arb(code);
        final names = {
          table['mapFilterLayers'],
          table['mapFilterLocation'],
          table['mapFilterNearby'],
          table['mapFilterTransaction'],
          table['propertyType'],
          table['mapFilterSort'],
        };
        expect(names, hasLength(6), reason: code);
      }
    });

    test('the replaced names are gone from the language files and the code',
        () {
      // (`mapNearbyRadius` and `mapNearbyTurnOff` are not here: Near Me is a
      // chip of its own again, with its radius list and its way to turn off.)
      for (final code in ['en', 'ar']) {
        final table = _arb(code);
        for (final old in [
          'mapFilterCategory',
          'mapClearFilters',
          'mapAllCities',
        ]) {
          expect(table.containsKey(old), isFalse, reason: '$code $old');
        }
      }
      for (final path in [_bar, _view, _viewModel, _statusLine]) {
        final text = _read(path);
        for (final old in [
          'mapFilterCategory',
          'mapClearFilters',
          'mapAllPrices',
          'mapLowestPrice',
          'mapHighestPrice',
          'mapAllCities',
        ]) {
          expect(text.contains(old), isFalse, reason: '$path $old');
        }
      }
      final bar = _read(_bar);
      for (final old in [
        "translate('city')",
        "translate('selectCity')",
        "translate('clear')",
      ]) {
        expect(bar.contains(old), isFalse, reason: old);
      }
    });

    test('Price filters Offers by range while Sort only orders them', () {
      final bar = _squash(_read(_bar));
      expect(bar.contains('if (has(MapFilterControl.price))'), isTrue);
      expect(bar.contains('active: state.priceRange != null,'), isTrue);
      expect(bar.contains('onTap: () => _choosePrice(context),'), isTrue);
      expect(bar.contains('viewModel.setPriceRange(choice.value);'), isTrue);
      expect(bar.contains('active: state.priceMode != MapPriceMode.all,'),
          isTrue);
      expect(bar.contains('onTap: () => _chooseSort(context),'), isTrue);
      expect(bar.contains('vm.setPriceMode(choice.value ?? MapPriceMode.all)'),
          isTrue);

      final engine = _squash(_read('lib/src/services/map_filter.dart'));
      expect(
        engine.contains('if (range != null) { if (!_hasPrice(place)) return false;'),
        isTrue,
      );
      expect(
        engine.contains('if ((range.min != null && price < range.min!) ||'),
        isTrue,
      );
      expect(
        engine.contains(
          'case MapPriceMode.lowest: return _byPrice(kept, highestFirst: false);',
        ),
        isTrue,
      );
      expect(
        engine.contains(
          'case MapPriceMode.highest: return _byPrice(kept, highestFirst: true);',
        ),
        isTrue,
      );
    });

    test('each control uses its own name for its chip and its list', () {
      final bar = _squash(_read(_bar));
      for (final used in [
        "loc.translate('mapFilterLayers')",
        "title: localization.translate('mapFilterLayers'),",
        "loc.translate('mapFilterLocation')",
        "title: localization.translate('mapFilterLocation'),",
        "label: localization.translate('mapAllUae'),",
        "loc.translate('mapFilterNearby')",
        "title: localization.translate('mapNearbyRadius'),",
        "label: localization.translate('mapNearbyTurnOff'),",
        "loc.translate('mapFilterSort')",
        "title: localization.translate('mapFilterSort'),",
      ]) {
        expect(bar.contains(used), isTrue, reason: used);
      }
    });

    test('the filter wiring is the one it was: each choice calls its setter',
        () {
      final bar = _squash(_read(_bar));
      for (final call in [
        'vm.setEntityType(choice.value ?? LocationFilter.all)',
        'vm.setCity(pickedCity)',
        'vm.setAllUae()',
        'vm.setPropertyType(choice.value)',
        'vm.setTransaction(choice.value)',
        'vm.setPriceMode(choice.value ?? MapPriceMode.all)',
        'vm.enableNearby()',
        'vm.disableNearby()',
        'vm.setNearbyRadius(choice.value!)',
      ]) {
        expect(_count(bar, call), 1, reason: call);
      }
      // Location and Near Me are two chips, each with its own handler: 5, 10
      // and 25 km, and one chip for the city.
      expect(_count(bar, 'onTap: () => _chooseLocation(context),'), 1);
      expect(_count(bar, 'onTap: () => _tapNearby(context),'), 1);
      expect(bar.contains('loading: vm.isLocatingNearby,'), isTrue);
    });
  });

  group('search is the same search, with a new hint', () {
    test('the hint is the map\'s own; the shared one is untouched', () {
      final view = _read(_view);
      expect(
        view.contains("hintText: localization.translate('mapSearchHint'),"),
        isTrue,
      );
      expect(view.contains("translate('searchLocation')"), isFalse);
      // The place picker (not part of this phase) keeps its own hint.
      expect(
        _read('lib/src/views/Widgets/map_picker_view.dart').contains(
          "hintText: localization.translate('searchLocation'),",
        ),
        isTrue,
      );
      expect(_arb('en')['searchLocation'], 'Search for a location...');
      expect(_arb('ar')['searchLocation'], 'ابحث عن موقع...');
    });

    test('typing, submitting and clearing do what they did', () {
      final view = _read(_view);
      final box = _squash(_between(
        view,
        'class _FloatingSearchBar extends StatelessWidget {',
        '// Floating Location Carousel',
      ));
      for (final pinned in [
        'controller: controller,',
        'hintStyle: AppTextStyles.hintText,',
        'prefixIcon: Icon(Icons.search, color: colors.primary),',
        "controller.clear(); FocusScope.of(context).unfocus(); onSearchChanged('');",
        'style: AppTextStyles.bodyText,',
        'onSubmitted: onSearchSubmitted,',
        'onChanged: onSearchChanged,',
      ]) {
        expect(box.contains(pinned), isTrue, reason: pinned);
      }
    });

    test('a search still looks up a location and moves the camera there', () {
      final view = _read(_view);
      final search = _squash(_between(
        view,
        'Future<void> _searchLocation(String query, MapViewViewModel vm) async {',
        'static void _showToast(',
      ));
      for (final pinned in [
        'if (query.trim().isEmpty) return;',
        'List<Location> locations = await locationFromAddress(query);',
        'vm.animateToLocation(searchedLocation);',
        'FocusScope.of(context).unfocus();',
        "_showToast(loc.translate('mapLocationFound'), Colors.green);",
        "_showToast(loc.translate('mapLocationNotFound'), Colors.red);",
      ]) {
        expect(search.contains(pinned), isTrue, reason: pinned);
      }
    });

    test('the search stays the first control, above the filter row', () {
      final screen = _squash(_read(_view));
      expect(
        screen.contains(
          'left: 72, // Space for back button (16 + 40 + 16) right: 72, // Space for map toggle button (16 + 40 + 16) child: _FloatingSearchBar(',
        ),
        isTrue,
      );
      final search = screen.indexOf('child: _FloatingSearchBar(');
      final filters = screen.indexOf('child: MapFilterBar(');
      expect(search, greaterThanOrEqualTo(0));
      expect(filters, greaterThan(search));
    });
  });

  group('Reset', () {
    test('the filters are "active" exactly when they differ from the default',
        () {
      var checked = 0;
      for (final entity in LocationFilter.values) {
        for (final nearby in <NearbyFilter?>[
          null,
          const NearbyFilter(latitude: 25.2, longitude: 55.27),
        ]) {
          for (final city in <String?>[null, 'Dubai']) {
            for (final type in <String?>[null, 'villa']) {
              for (final transaction in <MapTransaction?>[
                null,
                ...MapTransaction.values,
              ]) {
                for (final price in MapPriceMode.values) {
                  final state = MapFilterState(
                    entityType: entity,
                    nearby: nearby,
                    city: city,
                    propertyType: type,
                    transaction: transaction,
                    priceMode: price,
                  );
                  expect(
                    state.isActive,
                    state != MapFilterState.initial,
                    reason: '$entity $nearby $city $type $transaction $price',
                  );
                  checked++;
                }
              }
            }
          }
        }
      }
      expect(checked, greaterThan(100));
      expect(MapFilterState.initial.isActive, isFalse);
    });

    test(
        'hidden at the default, shown with any filter, hidden again when the '
        'last one is undone', () {
      final controller = MapFilterController()
        ..setRecords([_place('a'), _place('b', type: LocationFilter.owners)]);
      expect(controller.filtersActive, isFalse, reason: 'default: no Reset');

      controller.setCity('Dubai');
      expect(controller.filtersActive, isTrue);
      controller.setEntityType(LocationFilter.offers);
      expect(controller.filtersActive, isTrue);
      controller.setCity(null);
      expect(controller.filtersActive, isTrue, reason: 'one is still on');
      controller.setEntityType(LocationFilter.all);
      expect(controller.filtersActive, isFalse, reason: 'back to the default');
    });

    test('Reset is the one Clear: the default again, and nothing is asked',
        () async {
      final controller = MapFilterController()
        ..setRecords([_place('a'), _place('b', type: LocationFilter.owners)]);
      final locator = _CountingLocator(const NearbyLocated(25.2, 55.27));
      await controller.enableNearby(locator);
      controller
        ..setCity('Dubai')
        ..setEntityType(LocationFilter.offers)
        ..setPriceMode(MapPriceMode.lowest);
      expect(controller.filtersActive, isTrue);

      expect(controller.clear(), isTrue);

      expect(controller.state, MapFilterState.initial);
      expect(controller.filtersActive, isFalse);
      expect(controller.visible, hasLength(2), reason: 'nothing is read again');
      expect(locator.calls, 1, reason: 'Reset asks the device for nothing');
    });

    test('Reset is shown only while a filter is on, outside the scrolling row',
        () {
      final line = _squash(_read(_statusLine));
      expect(
        line.contains(
          'if (count == null && !canReset) return const SizedBox.shrink();',
        ),
        isTrue,
      );
      expect(
        line.contains(
          'if (canReset) Flexible(child: _resetButton(context)) else const SizedBox.shrink(),',
        ),
        isTrue,
      );
      final screen = _squash(_read(_view));
      expect(screen.contains('canReset: vm.filtersActive,'), isTrue);
      expect(screen.contains('onReset: vm.clearFilters,'), isTrue);
      // The "no matches" banner's action is the very same call.
      expect(screen.contains('onClear: vm.clearFilters,'), isTrue);
      expect(_count(screen, 'MapFilterStatusLine('), 1);
      expect(
        screen.indexOf('child: MapFilterBar('),
        lessThan(screen.indexOf('MapFilterStatusLine(')),
      );
      expect(
        _squash(_read(_viewModel))
            .contains('bool get filtersActive => _filters.filtersActive;'),
        isTrue,
      );
    });
  });

  group('the result count', () {
    test('English has none, one and many', () {
      expect(MapResultCount.keyFor(0, 'en'), MapResultCount.none);
      expect(MapResultCount.keyFor(-3, 'en'), MapResultCount.none);
      expect(MapResultCount.keyFor(1, 'en'), MapResultCount.one);
      for (final count in [2, 3, 10, 11, 12, 99, 100, 101, 1000]) {
        expect(MapResultCount.keyFor(count, 'en'), MapResultCount.other,
            reason: '$count');
      }
    });

    test('Arabic has none, one, two, a few (3 to 10) and the rest', () {
      expect(MapResultCount.keyFor(0, 'ar'), MapResultCount.none);
      expect(MapResultCount.keyFor(1, 'ar'), MapResultCount.one);
      expect(MapResultCount.keyFor(2, 'ar'), MapResultCount.two);
      for (final count in [3, 4, 9, 10, 103, 110, 203, 1003]) {
        expect(MapResultCount.keyFor(count, 'ar'), MapResultCount.few,
            reason: '$count');
      }
      for (final count in [11, 12, 99, 100, 101, 102, 111, 200, 202, 1000]) {
        expect(MapResultCount.keyFor(count, 'ar'), MapResultCount.other,
            reason: '$count');
      }
    });

    test('English reads 0 results, 1 result, 12 results', () {
      expect(_words('en', 0), '0 results');
      // A count is never negative; if one ever came, it reads as none.
      expect(_words('en', -3), '0 results');
      expect(_words('ar', -3), 'لا توجد نتائج');
      expect(_words('en', 1), '1 result');
      expect(_words('en', 2), '2 results');
      expect(_words('en', 12), '12 results');
      expect(_words('en', 1234), '1,234 results');
    });

    test('Arabic agrees with the number, written as the rest of the map does',
        () {
      // The digits are the ones `intl` writes for Arabic, the same formatter
      // the Near Me radius and the list counts use.
      expect(_words('ar', 0), 'لا توجد نتائج');
      expect(_words('ar', 1), 'نتيجة واحدة');
      expect(_words('ar', 2), 'نتيجتان');
      expect(_words('ar', 3), '3 نتائج');
      expect(_words('ar', 10), '10 نتائج');
      expect(_words('ar', 11), '11 نتيجة');
      expect(_words('ar', 12), '12 نتيجة');
      expect(_words('ar', 100), '100 نتيجة');
      expect(_words('ar', 103), '103 نتائج');
    });

    test(
        'every form exists in both languages, with its number where it has one',
        () {
      final en = _arb('en');
      final ar = _arb('ar');
      expect(MapResultCount.keys, hasLength(5));
      for (final key in MapResultCount.keys) {
        expect((en[key] as String?)?.trim(), isNotEmpty, reason: 'en $key');
        expect((ar[key] as String?)?.trim(), isNotEmpty, reason: 'ar $key');
        expect((en[key] as String).contains('{count}'), isTrue, reason: key);
      }
      for (final key in [MapResultCount.few, MapResultCount.other]) {
        expect((ar[key] as String).contains('{count}'), isTrue, reason: key);
      }
      for (final key in [
        MapResultCount.none,
        MapResultCount.one,
        MapResultCount.two,
      ]) {
        expect((ar[key] as String).contains('{count}'), isFalse, reason: key);
      }
      expect(ar[MapResultCount.few] == ar[MapResultCount.other], isFalse);
    });

    test(
        'the count is the published draw\'s own, taken from the markers\' groups',
        () {
      final model = _squash(_read(_viewModel));
      for (final pinned in [
        'const _Drawn(this.clusters, this.markers, this.placeCount);',
        'for (final group in groups.values) { placeCount += group.length; }',
        'return _Drawn(clusters, markers, placeCount);',
        '_publishedPlaceCount = drawn.placeCount;',
        'int? get resultCount => _hasLoadError ? null : _publishedPlaceCount;',
      ]) {
        expect(model.contains(pinned), isTrue, reason: pinned);
      }
      // One writer, and it is the publish.
      expect(_count(model, '_publishedPlaceCount ='), 1);
      // The screen shows that number, never the live filter's or the total.
      final screen = _squash(_read(_view));
      expect(screen.contains('resultCount: vm.resultCount,'), isTrue);
      expect(screen.contains('totalLocationsCount'), isFalse);
      // The draw counts from its own groups and never from live filter state.
      final draw = _between(
        _read(_viewModel),
        'Future<_Drawn?> _drawMarkers(',
        'void _publishDrawn(',
      );
      expect(draw.contains('_filters'), isFalse);
    });

    test('a count is published with its markers, never ahead of them',
        () async {
      final controller = MapFilterController()
        ..setRecords([
          _place('a'),
          _place('b'),
          _place('c'),
          _place('o1', type: LocationFilter.owners),
          _place('o2', type: LocationFilter.owners),
        ]);
      final draws = <Completer<int?>>[];
      final snapshots = <MapFilterSnapshot>[];
      int? shown;
      final pipeline = MapDrawPipeline<int>(
        draw: (snapshot, isCurrent) {
          final done = Completer<int?>();
          draws.add(done);
          snapshots.add(snapshot);
          return done.future;
        },
        publish: (snapshot, count) => shown = count,
        moveCamera: (_) {},
        viewport: () => _phone,
      );

      // A draw ends with the number of places of the snapshot it drew.
      Future<void> finish(int index) async {
        draws[index].complete(snapshots[index].visible.length);
        await pumpEventQueue();
      }

      unawaited(pipeline.show(controller.snapshot));
      await finish(0);
      expect(shown, 5);

      // The person narrows the map to Offers: the live filter is ahead of the
      // markers while the draw is under way, and the count stays with them.
      controller.setEntityType(LocationFilter.offers);
      unawaited(pipeline.show(controller.snapshot));
      expect(controller.visible, hasLength(3));
      expect(shown, 5, reason: 'the markers have not changed yet');
      await finish(1);
      expect(shown, 3);

      // A slow draw that a newer one overtook never publishes its count.
      controller.setEntityType(LocationFilter.owners);
      unawaited(pipeline.show(controller.snapshot));
      controller.clear();
      unawaited(pipeline.show(controller.snapshot));
      await finish(3);
      expect(shown, 5);
      await finish(2);
      expect(shown, 5, reason: 'an overtaken draw publishes nothing');
    });

    test('the new files read nothing: plain imports, no async, no backend', () {
      const allowed = [
        'package:flutter/material.dart',
        'package:intl/intl.dart',
        'package:broker_wallet/src/common/localization/localization_delegate.dart',
        'package:broker_wallet/src/services/map_result_count.dart',
      ];
      for (final path in [_statusLine, _resultCount]) {
        final text = _read(path);
        final imports = RegExp(r"^import '([^']+)'", multiLine: true)
            .allMatches(text)
            .map((match) => match.group(1)!)
            .toList();
        expect(imports, isNotEmpty, reason: path);
        for (final import in imports) {
          expect(allowed.contains(import), isTrue, reason: '$path: $import');
        }
        for (final word in [
          'await ',
          'async',
          'Future',
          'Stream',
          'Timer',
          'upabase',
          'http',
          'geolocator',
          'showDialog',
        ]) {
          expect(text.contains(word), isFalse, reason: '$path: $word');
        }
      }
    });
  });
}
