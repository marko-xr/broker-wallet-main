// Smart Map UX Phase 2: one place to look.
//
// The map has ONE place to look: all of the UAE, a city, or Near Me within a
// radius. A city and Near Me exclude each other (choosing one replaces the
// other), All UAE puts both back, and none of it reads the backend, asks the
// device again for a radius change, or moves the camera in a new way. Location
// and Near Me are two chips of the row (for a while they were one control): the
// rule is the filter state's, not the chips'. Plain Dart: the real filter state
// and controller, the real camera planner, and source guards.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bar = 'lib/src/views/Screens/home/map/map_filter_bar.dart';
const String _viewModel = 'lib/src/views/Screens/home/map/map_viewmodel.dart';
const String _filter = 'lib/src/services/map_filter.dart';
const String _controller = 'lib/src/services/map_filter_controller.dart';

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

// The device is in Sharjah. A degree of latitude is about 111.2 km.
const double _userLat = 25.30;
const double _userLng = 55.40;
const double _kmPerDegree = 111.195;
const NearbyFix _atUser = NearbyLocated(_userLat, _userLng);

CachedLocationData _at(
  String id,
  double lat,
  double lng, {
  String? city,
  LocationFilter type = LocationFilter.offers,
}) =>
    CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: lat,
      longitude: lng,
      type: type,
      city: city,
    );

/// A place [km] north of the device.
CachedLocationData _north(String id, double km, {String? city}) =>
    _at(id, _userLat + km / _kmPerDegree, _userLng, city: city);

/// Five places: two close to the device (3 and 7 km), two a little further
/// (about 16 km: Dubai's and Ajman's centres), one far away (Abu Dhabi).
List<CachedLocationData> _places() => [
      _north('sh-near', 3, city: 'Sharjah'),
      _north('dx-near', 7, city: 'Dubai'),
      _at('dx-far', 25.2048, 55.2708, city: 'Dubai'),
      _at('ad-1', 24.4539, 54.3773, city: 'Abu Dhabi'),
      _at('aj-1', 25.4052, 55.5136, city: 'Ajman'),
    ];

List<String> _ids(Iterable<CachedLocationData> places) => [
      for (final place in places) place.id,
    ];

MapFilterController _loaded() => MapFilterController()..setRecords(_places());

const NearbyFilter _someNearby =
    NearbyFilter(latitude: _userLat, longitude: _userLng, radiusKm: 10);

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

/// A position that comes when the test says so.
class _PendingLocator implements NearbyLocator {
  final Completer<NearbyFix> _answer = Completer<NearbyFix>();
  int calls = 0;

  @override
  Future<NearbyFix> locate() {
    calls++;
    return _answer.future;
  }

  void answer(NearbyFix fix) => _answer.complete(fix);
}

class _Source implements MapLocationSource {
  _Source(this.places);

  final List<CachedLocationData> places;

  @override
  String? currentUserId = 'u1';

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get changes => _changes.stream;

  int loads = 0;

  @override
  Future<List<CachedLocationData>> load() async {
    loads++;
    return places;
  }
}

class _Cache implements MapPlacesCache {
  @override
  List<CachedLocationData>? valid;

  @override
  int generation = 0;

  @override
  void store(
    String userId,
    List<CachedLocationData> places, {
    required int generation,
  }) {
    if (generation == this.generation) valid = places;
  }
}

void main() {
  group('a city and Near Me exclude each other', () {
    test('in the state: choosing one replaces the other', () {
      final dubai = MapFilterState.initial.withCity('Dubai');
      final nearMe = dubai.withNearby(_someNearby);
      expect(nearMe.city, isNull, reason: 'Near Me replaced Dubai');
      expect(nearMe.nearby, _someNearby);

      final ajman = nearMe.withCity('Ajman');
      expect(ajman.nearby, isNull, reason: 'Ajman replaced Near Me');
      expect(ajman.city, 'Ajman');
    });

    test('turning one off leaves the other as it is; the rest never moves', () {
      final base = MapFilterState.initial
          .withEntityType(LocationFilter.offers)
          .withPropertyType('villa')
          .withTransaction(MapTransaction.rent)
          .withPriceMode(MapPriceMode.lowest);

      final city = base.withCity('Dubai');
      expect(city.withNearby(null).city, 'Dubai', reason: 'Near Me off');
      final nearMe = base.withNearby(_someNearby);
      expect(nearMe.withCity(null).nearby, _someNearby, reason: 'no city');

      for (final state in [
        city,
        nearMe,
        city.withNearby(_someNearby),
        nearMe.withCity('Ajman'),
      ]) {
        expect(state.entityType, LocationFilter.offers);
        expect(state.propertyType, 'villa');
        expect(state.transaction, MapTransaction.rent);
        expect(state.priceMode, MapPriceMode.lowest);
      }
    });

    test('Dubai, then Near Me 10 km, then Ajman, then All UAE', () async {
      final locator = _CountingLocator(_atUser);
      final controller = _loaded()..setCity('Dubai');
      expect(_ids(controller.visible), ['dx-near', 'dx-far']);

      // Near Me replaces the city, in the one change that turns it on.
      final fix = await controller.enableNearby(locator, radiusKm: 10);
      expect(fix, isA<NearbyLocated>());
      expect(controller.state.city, isNull);
      expect(controller.state.nearby!.radiusKm, 10);
      expect(_ids(controller.visible), ['sh-near', 'dx-near']);
      expect(locator.calls, 1);

      // A city replaces Near Me, and the device is not asked.
      expect(controller.setCity('Ajman'), isTrue);
      expect(controller.state.nearby, isNull);
      expect(controller.state.city, 'Ajman');
      expect(_ids(controller.visible), ['aj-1']);
      expect(locator.calls, 1);

      // All UAE puts the default back.
      expect(controller.setAllUae(), isTrue);
      expect(controller.state, MapFilterState.initial);
      expect(controller.visible, hasLength(5));
      expect(locator.calls, 1);
      expect(controller.setAllUae(), isFalse, reason: 'it is already there');
    });

    test('Near Me starts at the radius chosen; a new radius asks nothing',
        () async {
      final locator = _CountingLocator(_atUser);
      final controller = _loaded();
      await controller.enableNearby(locator, radiusKm: 25);
      expect(controller.state.nearby!.radiusKm, 25);
      expect(
        _ids(controller.visible),
        ['sh-near', 'dx-near', 'dx-far', 'aj-1'],
      );

      expect(controller.setNearbyRadius(10), isTrue);
      expect(_ids(controller.visible), ['sh-near', 'dx-near']);
      expect(controller.setNearbyRadius(5), isTrue);
      expect(_ids(controller.visible), ['sh-near']);
      expect(controller.setNearbyRadius(5), isFalse, reason: 'same radius');
      expect(controller.state.nearby!.latitude, _userLat);
      expect(locator.calls, 1, reason: 'the position held is reused');
    });

    test('Near Me with no position leaves the city alone', () async {
      for (final fix in <NearbyFix>[
        const NearbyDenied(),
        const NearbyPermanentlyDenied(),
        const NearbyServicesOff(),
        const NearbyUnavailable(),
      ]) {
        final controller = _loaded()..setCity('Dubai');
        await controller.enableNearby(_CountingLocator(fix), radiusKm: 5);
        expect(controller.state.city, 'Dubai', reason: '$fix');
        expect(controller.state.nearby, isNull, reason: '$fix');
        expect(controller.isLocatingNearby, isFalse, reason: '$fix');
        expect(_ids(controller.visible), ['dx-near', 'dx-far'], reason: '$fix');
      }
    });

    test('a city chosen while Near Me waits is not undone by the late position',
        () async {
      final controller = _loaded()..setCity('Dubai');
      final locator = _PendingLocator();

      final pending = controller.enableNearby(locator, radiusKm: 10);
      expect(controller.isLocatingNearby, isTrue);
      expect(controller.state.city, 'Dubai',
          reason: 'nothing changes while the position is awaited');

      controller.setCity('Ajman');
      expect(controller.isLocatingNearby, isFalse);

      locator.answer(_atUser);
      await pending;
      expect(controller.state.city, 'Ajman');
      expect(controller.state.nearby, isNull);
      expect(_ids(controller.visible), ['aj-1']);
    });

    test('All UAE chosen while Near Me waits drops the late position too',
        () async {
      final controller = _loaded()..setCity('Dubai');
      final locator = _PendingLocator();

      final pending = controller.enableNearby(locator, radiusKm: 10);
      expect(controller.setAllUae(), isTrue);
      expect(controller.isLocatingNearby, isFalse);

      locator.answer(_atUser);
      await pending;
      expect(controller.state, MapFilterState.initial);
      expect(controller.visible, hasLength(5));
    });

    test('All UAE restores the place only: the other filters stay', () async {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setCity('Dubai');
      controller.setAllUae();
      expect(controller.state.city, isNull);
      expect(controller.state.entityType, LocationFilter.offers);
      expect(controller.filtersActive, isTrue, reason: 'Reset is still there');

      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 10);
      controller.setAllUae();
      expect(controller.state.nearby, isNull);
      expect(controller.state.entityType, LocationFilter.offers);

      // Reset is the one that puts everything back.
      expect(controller.clear(), isTrue);
      expect(controller.state, MapFilterState.initial);
    });

    test('Near Me still combines with the layer, rent / sale, type and sort',
        () async {
      final controller = MapFilterController()
        ..setRecords([
          _north('offer', 3),
          _at('owner', _userLat + 4 / _kmPerDegree, _userLng,
              type: LocationFilter.owners),
        ]);
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 10);
      expect(controller.visible, hasLength(2));
      controller.setEntityType(LocationFilter.owners);
      expect(_ids(controller.visible), ['owner']);
      expect(controller.state.nearby, isNotNull);
    });

    test('switching the place costs no backend read and no location request',
        () async {
      final source = _Source(_places());
      final controller = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _Cache(),
        onPlaces: (places, {required fresh}) async =>
            controller.setRecords(places),
        onFailed: () {},
      );
      await loader.start();
      expect(source.loads, 1);

      final locator = _CountingLocator(_atUser);
      await controller.enableNearby(locator, radiusKm: 10);
      for (var i = 0; i < 10; i++) {
        controller
          ..setCity('Dubai')
          ..setAllUae()
          ..setCity('Ajman')
          ..setAllUae();
      }
      expect(source.loads, 1, reason: 'not one read for any of that');
      expect(locator.calls, 1,
          reason: 'a city and All UAE ask the device nothing');
      loader.dispose();
    });
  });

  group('the camera follows the place chosen', () {
    MapCameraPlan plan(MapCameraCause cause, MapFilterController controller) =>
        MapCameraPlanner.plan(
          cause: cause,
          snapshot: controller.snapshot,
          viewport: _phone,
        )!;

    test('Near Me shows the circle, a city its places, All UAE the overview',
        () async {
      final controller = _loaded();
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 10);
      final circle = plan(MapCameraCause.nearbyEnabled, controller);
      expect(circle.subject, MapCameraSubject.nearbyArea);
      final expected = NearbyCamera.target(controller.state.nearby!, _phone);
      expect(circle.target.latitude, closeTo(expected.latitude, 1e-9));
      expect(circle.target.zoom, closeTo(expected.zoom, 1e-9));

      // Near Me -> Abu Dhabi: the city, never the old circle.
      controller.setCity('Abu Dhabi');
      final city = plan(MapCameraCause.cityChanged, controller);
      expect(city.subject, MapCameraSubject.matchingPlaces);
      expect(city.target.latitude, closeTo(24.45, 0.3));
      expect(city.target.longitude, closeTo(54.38, 0.3));

      // Abu Dhabi -> All UAE: the UAE overview, the frame the map opens on.
      controller.setAllUae();
      final all = plan(MapCameraCause.allUae, controller);
      expect(all.subject, MapCameraSubject.uaeOverview);
      expect(all.target.zoom, lessThan(city.target.zoom));
    });

    test('All UAE restores the opening frame, from wherever the camera was',
        () {
      final controller = _loaded()..setCity('Abu Dhabi');
      controller.setAllUae();
      final overview = plan(MapCameraCause.allUae, controller);
      expect(overview.subject, MapCameraSubject.uaeOverview);
      // The very frame the map opened on: the same function, the same room.
      expect(overview.target, UaeMapFraming.fit(_phone));
      expect(overview.target, MapCameraDirector().initial(_phone));
      // And not what the filters let through.
      final places = plan(MapCameraCause.filterChanged, controller);
      expect(overview.target, isNot(places.target));
    });

    test('All UAE does not stay on the old city because nothing is visible',
        () {
      // Ajman has a place; the layer chosen after it has none.
      final controller = _loaded()
        ..setCity('Ajman')
        ..setEntityType(LocationFilter.watchmen);
      expect(controller.visible, isEmpty);
      // Any other choice with nothing visible leaves the camera where it is.
      expect(
        MapCameraPlanner.plan(
          cause: MapCameraCause.filterChanged,
          snapshot: controller.snapshot,
          viewport: _phone,
        ),
        isNull,
      );

      controller.setAllUae();
      expect(controller.visible, isEmpty, reason: 'the other filter stays');
      final overview = plan(MapCameraCause.allUae, controller);
      expect(overview.subject, MapCameraSubject.uaeOverview);
      expect(overview.target, UaeMapFraming.fit(_phone));
    });

    test('from Near Me, and from All UAE itself, it is the overview too',
        () async {
      final controller = _loaded();
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 5);
      controller.setAllUae();
      expect(
        plan(MapCameraCause.allUae, controller).target,
        UaeMapFraming.fit(_phone),
      );
      // Already on All UAE: the filter does not change, and the choice still
      // asks for the overview (the person may have moved away).
      expect(controller.setAllUae(), isFalse);
      expect(
        plan(MapCameraCause.allUae, controller).subject,
        MapCameraSubject.uaeOverview,
      );
    });

    test('the opening camera is the one source of that frame', () {
      final director = _squash(_read('lib/src/services/map_camera.dart'));
      expect(director.contains('_initial ??= UaeMapFraming.fit(viewport);'),
          isTrue);
      // The frame's own numbers are the opening camera's and are unchanged; the
      // planner uses the same function once, for All UAE, and holds no copy.
      for (final constant in [
        'static const double south = 24.08;',
        'static const double north = 25.95;',
        'static const double west = 54.28;',
        'static const double east = 56.46;',
        'static const double minZoom = 4;',
        'static const double maxZoom = 9;',
      ]) {
        expect(_count(director, constant), 1, reason: constant);
      }
      final planner = _squash(_read('lib/src/services/map_camera_policy.dart'));
      expect(_count(planner, 'UaeMapFraming.fit('), 1);
      for (final number in ['24.08', '25.95', '54.28', '56.46']) {
        expect(planner.contains(number), isFalse, reason: number);
      }
    });

    test('each choice names its camera cause', () {
      final model = _squash(_read(_viewModel));
      for (final pair in {
        'setCity': 'cityChanged',
        'setAllUae': 'allUae',
        'setNearbyRadius': 'nearbyRadiusChanged',
      }.entries) {
        final start = model.indexOf('void ${pair.key}(');
        expect(start, greaterThanOrEqualTo(0), reason: pair.key);
        final end = model.indexOf(');', start);
        expect(
          model.substring(start, end).contains('MapCameraCause.${pair.value}'),
          isTrue,
          reason: '${pair.key} -> ${pair.value}',
        );
      }
      expect(
        model.contains(
          '_afterFilterChange( fix is NearbyLocated && _filters.state.nearbyEnabled, MapCameraCause.nearbyEnabled, );',
        ),
        isTrue,
      );
      // The planner is not touched: it still reads only the field of its cause.
      final planner = _squash(_read('lib/src/services/map_camera_policy.dart'));
      expect(planner.contains('final city = snapshot.state.city;'), isTrue);
      expect(planner.contains('final nearby = snapshot.state.nearby;'), isTrue);
    });
  });

  group('the rule is in the one place every change goes through', () {
    test('the state clears the other field; the controller drops a late fix',
        () {
      final state = _squash(_read(_filter));
      expect(state.contains('city: value == null ? city : null,'), isTrue);
      expect(state.contains('nearby: value == null ? nearby : null,'), isTrue);

      final controller = _squash(_read(_controller));
      expect(
        controller.contains(
          'bool setCity(String? city) { if (city != null) _dropNearbyRequest(); return _change(_state.withCity(city)); }',
        ),
        isTrue,
      );
      expect(
        controller.contains(
          'bool setAllUae() { _dropNearbyRequest(); return _change(_state.withCity(null).withNearby(null)); }',
        ),
        isTrue,
      );
      // Near Me is applied in one change, so a city and Near Me are never both
      // in a state, not even for one frame.
      expect(
        controller.contains(
          'void _dropNearbyRequest() { _nearbyRequest++; _locatingRequest = null; }',
        ),
        isTrue,
      );
      expect(_count(controller, '_dropNearbyRequest();'), 4);
    });

    test('All UAE reads nothing, in the view model\'s filter section', () {
      final text = _read(_viewModel);
      final start = text.indexOf('// ---- filter changes');
      final end = text.indexOf('// UI methods');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final changes = text.substring(start, end);
      expect(changes.contains('void setAllUae()'), isTrue);
      for (final read in ['_loader', '_cache', 'refresh', 'retry', 'load(']) {
        expect(changes.contains(read), isFalse, reason: read);
      }
      expect(
        _squash(text).contains(
          'void setAllUae() { final waiting = _filters.isLocatingNearby; _afterFilterChange( _filters.setAllUae(), MapCameraCause.allUae, force: true, ); _stopWaiting(waiting); }',
        ),
        isTrue,
      );
    });
  });

  group('the Location and Near Me chips in the row', () {
    test('two chips: Location says the city, Near Me says its own state', () {
      final bar = _squash(_read(_bar));
      // Location: its own name or the city; on for a city only.
      expect(
        bar.contains(
          "_MapFilterChip( label: state.city == null ? loc.translate('mapFilterLocation') : _cityLabel(state.city!), icon: Icons.location_on_rounded, color: colors.primary, active: state.city != null, dropdown: true, onTap: () => _chooseLocation(context), ),",
        ),
        isTrue,
      );
      // Near Me: its own name, or "Near Me · 10 km"; the spinner while the
      // device is being asked.
      expect(
        bar.contains(
          "_MapFilterChip( label: nearby == null ? loc.translate('mapFilterNearby') : loc .translate('mapNearbyActive') .replaceAll('{km}', _number(nearby.radiusKm)), icon: Icons.near_me_rounded, color: colors.primary, active: nearby != null, loading: vm.isLocatingNearby, onTap: () => _tapNearby(context), ),",
        ),
        isTrue,
      );
      // Two chips, two handlers; nothing of the one merged control is left.
      expect(_count(bar, 'onTap: () => _chooseLocation(context),'), 1);
      expect(_count(bar, 'onTap: () => _tapNearby(context),'), 1);
      for (final gone in [
        '_locationLabel',
        '_chooseNearMe',
        '_LocationChoice.nearMe',
        '_SheetOption.header',
        '_SheetOption.divider',
        'indented',
        'enabled:',
      ]) {
        expect(bar.contains(gone), isFalse, reason: gone);
      }
    });

    test('a choice in either chip goes to the same setters as before', () {
      final bar = _squash(_read(_bar));
      // Location: a city, or All UAE (which puts the default back).
      expect(
        bar.contains(
          'final picked = choice?.value; if (picked == null) return; final pickedCity = picked.city; if (pickedCity != null) { vm.setCity(pickedCity); } else { vm.setAllUae(); }',
        ),
        isTrue,
      );
      // Near Me off: the device is asked (the default radius) and a failure is
      // worded, never raw; a chosen city stays then.
      expect(
        bar.contains(
          'if (vm.isLocatingNearby) return; final nearby = vm.filterState.nearby; if (nearby == null) { final fix = await vm.enableNearby();',
        ),
        isTrue,
      );
      expect(
        bar.contains(
          'final key = fix == null ? null : nearbyFixMessageKey(fix); if (key != null) onMessage(localization.translate(key)); return; }',
        ),
        isTrue,
      );
      // Near Me on: a radius changes only the radius, the way out turns it off.
      expect(
        bar.contains(
          'if (choice == null) return; if (choice.value == turnOff) { vm.disableNearby(); } else if (choice.value != null) { vm.setNearbyRadius(choice.value!); }',
        ),
        isTrue,
      );
    });

    test('while the device is asked, Near Me waits and Location stays free',
        () {
      final bar = _squash(_read(_bar));
      // The Near Me chip shows the spinner and cannot be tapped (its handler
      // also returns at once); it is the only chip that does.
      expect(_count(bar, 'loading: vm.isLocatingNearby,'), 1);
      expect(bar.contains('onTap: loading ? null : onTap,'), isTrue);
      expect(_count(bar, 'if (vm.isLocatingNearby) return;'), 1);
      // The Location chip and its list never look at the wait, so a city or All
      // UAE can be chosen meanwhile: the view model supersedes the request and
      // ends the wait (the guards below).
      final location = _between(
        _read(_bar),
        'Future<void> _chooseLocation(',
        'Future<void> _choosePropertyType(',
      );
      expect(location.contains('isLocatingNearby'), isFalse);
      expect(location.contains('loading'), isFalse);
      expect(location.contains('enabled'), isFalse);
    });

    test('Location lists All UAE and the cities; Near Me lists 5, 10, 25 km',
        () {
      expect(NearbyFilter.radiusOptionsKm, [5, 10, 25]);
      expect(NearbyFilter.defaultRadiusKm, 10);

      final bar = _squash(_read(_bar));
      // Near Me's list: the radii (the one chosen is checked), then the way out.
      expect(
        bar.contains(
          "title: localization.translate('mapNearbyRadius'), selected: nearby.radiusKm, options: [ for (final km in NearbyFilter.radiusOptionsKm) _SheetOption(value: km, label: _km(km)), _SheetOption( value: turnOff, label: localization.translate('mapNearbyTurnOff'), icon: Icons.close_rounded, ), ],",
        ),
        isTrue,
      );

      // Location's list: All UAE first, then the cities. No radius in it, and
      // with Near Me on no row is the chosen one (the map is on neither).
      final location = _squash(_between(
        _read(_bar),
        'Future<void> _chooseLocation(',
        'Future<void> _choosePropertyType(',
      ));
      expect(location.contains('radiusOptionsKm'), isFalse);
      expect(location.contains('_km('), isFalse);
      var from = 0;
      for (final step in [
        "label: localization.translate('mapAllUae'),",
        'for (final city in vm.cityOptions)',
      ]) {
        final at = location.indexOf(step, from);
        expect(at, greaterThanOrEqualTo(0), reason: step);
        from = at + step.length;
      }
      expect(
        location.contains(
          'final _LocationChoice? current = chosenCity != null ? _LocationChoice.city(chosenCity) : chosen.nearby != null ? null : const _LocationChoice.allUae();',
        ),
        isTrue,
      );
    });
  });

  group('choosing a place while the device is being asked', () {
    test('a city, All UAE, Reset and turning Near Me off each take a number',
        () async {
      final controller = _loaded();
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 10);
      var seen = controller.nearbyRequest;
      for (final choose in <void Function()>[
        () => controller.setCity('Dubai'),
        () => controller.setAllUae(),
        () => controller.clear(),
        () => controller.disableNearby(),
      ]) {
        choose();
        expect(controller.nearbyRequest, greaterThan(seen));
        seen = controller.nearbyRequest;
      }
    });

    test('a request takes its number before it waits; other choices do not',
        () async {
      final controller = _loaded();
      final locator = _PendingLocator();
      final before = controller.nearbyRequest;

      final pending = controller.enableNearby(locator, radiusKm: 10);
      final mine = controller.nearbyRequest;
      expect(mine, before + 1, reason: 'taken before the first wait');

      // Not new requests: every city, and every other filter.
      controller
        ..setCity(null)
        ..setEntityType(LocationFilter.offers)
        ..setPriceMode(MapPriceMode.lowest);
      expect(controller.nearbyRequest, mine);

      controller.setCity('Ajman');
      expect(controller.nearbyRequest, isNot(mine));

      locator.answer(_atUser);
      await pending;
      expect(controller.nearbyRequest, isNot(mine));
      expect(controller.state.nearby, isNull);
    });

    test('a late failure after a newer choice is recognised as not wanted',
        () async {
      final controller = _loaded()..setCity('Dubai');
      final locator = _PendingLocator();
      final pending = controller.enableNearby(locator, radiusKm: 5);
      final mine = controller.nearbyRequest;

      controller.setAllUae();
      locator.answer(const NearbyDenied());
      final fix = await pending;

      expect(fix, isA<NearbyDenied>(), reason: 'the controller reports it');
      expect(controller.nearbyRequest, isNot(mine),
          reason: 'a caller comparing numbers sees that it is stale');
      expect(controller.state, MapFilterState.initial);
    });

    test('Near Me, a city, Near Me again: one answer serves the newest only',
        () async {
      final controller = _loaded();
      final locator = _PendingLocator();

      final first = controller.enableNearby(locator, radiusKm: 10);
      final firstNumber = controller.nearbyRequest;
      controller.setCity('Ajman');
      final second = controller.enableNearby(locator, radiusKm: 25);
      final secondNumber = controller.nearbyRequest;
      expect(secondNumber, greaterThan(firstNumber));

      locator.answer(_atUser);
      await first;
      await second;

      // The first answer is not wanted; the second is applied, once.
      expect(firstNumber, isNot(controller.nearbyRequest));
      expect(secondNumber, controller.nearbyRequest);
      expect(controller.state.city, isNull);
      expect(controller.state.nearby!.radiusKm, 25);
      expect(controller.isLocatingNearby, isFalse);
    });

    test('the chip ends its wait at once, and says nothing of a late answer',
        () {
      final model = _squash(_read(_viewModel));
      for (final pinned in [
        'final pending = _filters.enableNearby(_nearbyLocator, radiusKm: radiusKm); _safeNotifyListeners(); final request = _filters.nearbyRequest; final fix = await pending;',
        'if (request != _filters.nearbyRequest) { _safeNotifyListeners(); return null; }',
        'void _stopWaiting(bool waiting) { if (waiting && !_filters.isLocatingNearby) _safeNotifyListeners(); }',
        'void setCity(String? city) { final waiting = _filters.isLocatingNearby; _afterFilterChange(_filters.setCity(city), MapCameraCause.cityChanged); _stopWaiting(waiting); }',
      ]) {
        expect(model.contains(pinned), isTrue, reason: pinned);
      }
      // The permission fact is kept for any answer; the check that the answer
      // is still wanted comes before anything is applied.
      var from = model.indexOf('Future<NearbyFix?> enableNearby({');
      expect(from, greaterThanOrEqualTo(0));
      for (final step in [
        'if (fix is NearbyLocated) _hasLocationPermission = true;',
        'if (request != _filters.nearbyRequest) {',
        '_afterFilterChange( fix is NearbyLocated && _filters.state.nearbyEnabled, MapCameraCause.nearbyEnabled, );',
      ]) {
        final at = model.indexOf(step, from);
        expect(at, greaterThanOrEqualTo(0), reason: step);
        from = at + step.length;
      }
      // The guard that stops a second request while one waits is still there,
      // and the number is only ever read outside the controller.
      expect(
        model.contains(
          'if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;',
        ),
        isTrue,
      );
      expect(
        _squash(_read(_controller))
            .contains('int get nearbyRequest => _nearbyRequest;'),
        isTrue,
      );
      expect(model.contains('nearbyRequest ='), isFalse);
    });
  });

  group('the words', () {
    test('All UAE, and the search hint that now says only what it does', () {
      expect(_arb('en')['mapAllUae'], 'All UAE');
      expect(_arb('ar')['mapAllUae'], 'كل الإمارات');
      expect(_arb('en')['mapSearchHint'], 'Search location...');
      expect(_arb('ar')['mapSearchHint'], 'ابحث عن موقع...');
      // The hint is a Map key; the place picker's own is untouched.
      expect(_arb('en')['searchLocation'], 'Search for a location...');
      expect(
        _read('lib/src/views/Screens/home/map/map_view.dart')
            .contains("hintText: localization.translate('mapSearchHint'),"),
        isTrue,
      );
    });

    test('everything the two location chips say exists in both languages', () {
      for (final code in ['en', 'ar']) {
        final table = _arb(code);
        for (final key in [
          'mapFilterLocation',
          'mapAllUae',
          'mapFilterNearby',
          'mapNearbyActive',
          'mapNearbyRadius',
          'mapNearbyTurnOff',
          'mapKmValue',
          'mapNearbyUnavailable',
        ]) {
          expect((table[key] as String?)?.trim(), isNotEmpty,
              reason: '$code $key');
        }
        expect((table['mapNearbyActive'] as String).contains('{km}'), isTrue);
        expect((table['mapKmValue'] as String).contains('{km}'), isTrue);
      }
    });
  });
}
