// The map's filter and its camera, as one flow.
//
//     filter choice -> snapshot -> draw markers -> publish -> camera
//
// Two defects found on the Samsung drive this file:
//
//  * Nearby: choosing 5, 10 or 25 km must change what is shown AND where the
//    camera looks, from the position already held, with no new location request
//    and no backend read.
//  * City: choosing Abu Dhabi must show Abu Dhabi's places (or Abu Dhabi
//    itself when there are none) and must never frame a place from another
//    city.
//
// The camera is planned from the one snapshot the markers were drawn from and
// the filter chosen in it, and only the newest choice may move it. Plain Dart.

import 'dart:async';
import 'dart:math' as math;

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:flutter_test/flutter_test.dart';

// The phone: the room the screen's controls leave, as the map screen passes it.
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

/// A place [km] north of the device.
CachedLocationData _north(
  String id,
  double km, {
  String? city,
  LocationFilter type = LocationFilter.offers,
}) =>
    CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: _userLat + km / _kmPerDegree,
      longitude: _userLng,
      type: type,
      city: city,
    );

/// A place at an exact position.
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

List<String> _ids(Iterable<CachedLocationData> places) => [
      for (final place in places) place.id,
    ];

MapFilterController _loaded(List<CachedLocationData> places) =>
    MapFilterController()..setRecords(places);

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

bool _inFree(MapCameraTarget camera, double lat, double lng) {
  final at = UaeMapFraming.project(camera, _phone, lat, lng);
  const slack = 0.5;
  return at.x >= _phone.left - slack &&
      at.x <= _phone.width - _phone.right + slack &&
      at.y >= _phone.top - slack &&
      at.y <= _phone.height - _phone.bottom + slack;
}

MapCameraPlan? _plan(MapCameraCause cause, MapFilterSnapshot snapshot) =>
    MapCameraPlanner.plan(cause: cause, snapshot: snapshot, viewport: _phone);

// ---- Offers through the real mapper, for the city checks ------------------

final DateTime _now = DateTime(2026, 10, 10);

OfferModel _offer(
  String id, {
  required String city,
  required double lat,
  required double lng,
  String address = '',
}) =>
    OfferModel(
      id: id,
      userId: 'u1',
      offerType: 'rent',
      selectedCity: city,
      selectedAreas: const <String>[],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '100',
      maxPrice: '200',
      notes: '',
      specificPropertyType: 'Villa',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
      uploadedFileName: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

// ---- A source that counts its reads, for "no backend read" ----------------

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

// ---- The draw pipeline, with draws that finish when the test says ---------

class _Draw {
  _Draw(this.snapshot, this.isCurrent);

  final MapFilterSnapshot snapshot;
  final bool Function() isCurrent;
  final Completer<String?> done = Completer<String?>();
}

/// The map's filter, pipeline and a slow marker draw, wired the way the view
/// model wires them: a choice asks for a camera move for that snapshot, then
/// draws it.
class _Rig {
  _Rig(List<CachedLocationData> places) : controller = _loaded(places) {
    pipeline = MapDrawPipeline<String>(
      draw: (snapshot, isCurrent) {
        final draw = _Draw(snapshot, isCurrent);
        draws.add(draw);
        return draw.done.future;
      },
      publish: (snapshot, drawn) => published.add(snapshot),
      moveCamera: moves.add,
      viewport: () => _phone,
    );
  }

  final MapFilterController controller;
  late final MapDrawPipeline<String> pipeline;
  final List<_Draw> draws = [];
  final List<MapFilterSnapshot> published = [];
  final List<MapCameraPlan> moves = [];

  /// A filter choice just made (the setters return whether it changed).
  void chose(bool changed, MapCameraCause cause) {
    if (!changed) return;
    final snapshot = controller.snapshot;
    pipeline.requestCamera(cause, snapshot);
    unawaited(pipeline.show(snapshot));
  }

  /// The places were read again: drawn, with no request for the camera.
  void refreshed(List<CachedLocationData> places) {
    controller.setRecords(places);
    unawaited(pipeline.show(controller.snapshot));
  }

  /// A draw that notices a newer one took over and stops, as the view model's
  /// does.
  Future<void> finish(int index) async {
    final draw = draws[index];
    draw.done.complete(draw.isCurrent() ? 'drawn' : null);
    await pumpEventQueue();
  }

  /// A draw that never checks, and answers anyway: the pipeline must still
  /// refuse it.
  Future<void> finishBlind(int index) async {
    draws[index].done.complete('drawn');
    await pumpEventQueue();
  }
}

void main() {
  // The device and a spread of places: 3, 4.5, 7, 9, 12, 20, 24, 30 and 60 km.
  List<CachedLocationData> spread() => [
        for (final km in [3.0, 4.5, 7.0, 9.0, 12.0, 20.0, 24.0, 30.0, 60.0])
          _north('p$km', km),
      ];

  Future<MapFilterController> nearbyAt(int radiusKm) async {
    final controller = _loaded(spread());
    await controller.enableNearby(
      _CountingLocator(_atUser),
      radiusKm: radiusKm,
    );
    return controller;
  }

  group('Nearby: the radius changes what is shown', () {
    test('1. turning Nearby on, at 10 km, shows what is within 10 km',
        () async {
      final controller = _loaded(spread());
      final fix = await controller.enableNearby(_CountingLocator(_atUser));
      expect(fix, isA<NearbyLocated>());
      expect(controller.state.nearby!.radiusKm, 10);
      expect(
        _ids(controller.visible),
        ['p3.0', 'p4.5', 'p7.0', 'p9.0'],
      );
    });

    test('2. 10 -> 5 km recomputes the places', () async {
      final controller = await nearbyAt(10);
      expect(controller.setNearbyRadius(5), isTrue);
      expect(_ids(controller.visible), ['p3.0', 'p4.5']);
      expect(controller.state.nearby!.radiusKm, 5);
    });

    test('3. 5 -> 25 km recomputes the places', () async {
      final controller = await nearbyAt(5);
      expect(controller.setNearbyRadius(25), isTrue);
      expect(
        _ids(controller.visible),
        ['p3.0', 'p4.5', 'p7.0', 'p9.0', 'p12.0', 'p20.0', 'p24.0'],
      );
    });

    test('4. a radius change never asks the device again', () async {
      final locator = _CountingLocator(_atUser);
      final controller = _loaded(spread());
      await controller.enableNearby(locator);
      expect(locator.calls, 1);

      for (final km in [5, 25, 10, 5, 25, 5, 10]) {
        controller.setNearbyRadius(km);
      }
      expect(locator.calls, 1, reason: 'the position is the one already held');
      expect(controller.state.nearby!.latitude, _userLat);
      expect(controller.state.nearby!.longitude, _userLng);
    });

    test('5. a radius change costs no backend read', () async {
      final source = _Source(spread());
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
      await controller.enableNearby(_CountingLocator(_atUser));

      for (var round = 0; round < 10; round++) {
        controller
          ..setNearbyRadius(5)
          ..setNearbyRadius(25)
          ..setNearbyRadius(10);
      }
      expect(source.loads, 1, reason: 'not one read for any of that');
      loader.dispose();
    });

    test('6. what 5 km shows is within what 10 km shows, then 25 km', () async {
      final five = _ids((await nearbyAt(5)).visible).toSet();
      final ten = _ids((await nearbyAt(10)).visible).toSet();
      final twentyFive = _ids((await nearbyAt(25)).visible).toSet();
      expect(ten.containsAll(five), isTrue);
      expect(twentyFive.containsAll(ten), isTrue);
      expect(five.length, lessThan(ten.length));
      expect(ten.length, lessThan(twentyFive.length));
    });

    test('7. growing and shrinking the radius is monotonic, step by step',
        () async {
      final controller = await nearbyAt(5);
      var before = _ids(controller.visible).toSet();
      for (final km in [10, 25]) {
        controller.setNearbyRadius(km);
        final now = _ids(controller.visible).toSet();
        expect(now.containsAll(before), isTrue, reason: 'growing to $km');
        before = now;
      }
      for (final km in [10, 5]) {
        controller.setNearbyRadius(km);
        final now = _ids(controller.visible).toSet();
        expect(before.containsAll(now), isTrue, reason: 'shrinking to $km');
        before = now;
      }
    });

    test('the result is exactly the places within the radius, for any fixture',
        () async {
      // A deterministic scatter around the device, 0-45 km away.
      final random = math.Random(42);
      final places = [
        for (var i = 0; i < 1500; i++)
          _at(
            'r$i',
            _userLat + (random.nextDouble() - 0.5) * 0.8,
            _userLng + (random.nextDouble() - 0.5) * 0.8,
          ),
      ];
      final controller = _loaded(places);
      await controller.enableNearby(_CountingLocator(_atUser));
      Set<String> within(int km) => {
            for (final place in places)
              if (GeoDistance.meters(
                    _userLat,
                    _userLng,
                    place.latitude,
                    place.longitude,
                  ) <=
                  km * 1000.0)
                place.id,
          };
      for (final km in [5, 25, 10, 5, 10, 25]) {
        controller.setNearbyRadius(km);
        expect(
          _ids(controller.visible).toSet(),
          within(km),
          reason: '$km km',
        );
      }
      expect(within(5), isNotEmpty);
      expect(within(5).length, lessThan(within(25).length));
    });

    test('a place with no usable position is never near', () async {
      final controller = _loaded([
        _at('bad', 0, 0),
        _north('good', 2),
      ]);
      await controller.enableNearby(_CountingLocator(_atUser));
      expect(_ids(controller.visible), ['good']);
    });

    // A city is not one of those filters: it replaces Near Me (see
    // map_location_scope_test.dart). The others (the layer here) still combine.
    test('Near Me combines with the other (non-place) filters, with AND',
        () async {
      final controller = _loaded([
        _north('near-offer', 3),
        _north('near-owner', 4, type: LocationFilter.owners),
        _north('far-offer', 40),
      ]);
      await controller.enableNearby(_CountingLocator(_atUser));
      controller.setEntityType(LocationFilter.offers);
      expect(_ids(controller.visible), ['near-offer']);
      controller.setNearbyRadius(5);
      expect(_ids(controller.visible), ['near-offer']);
      controller.setNearbyRadius(25);
      expect(_ids(controller.visible), ['near-offer']);
    });
  });

  group('Nearby: the camera shows the radius', () {
    NearbyFilter at(int km) => NearbyFilter(
          latitude: _userLat,
          longitude: _userLng,
          radiusKm: km,
        );

    test('each radius has its own camera: 5 closer, 25 wider', () {
      final five = NearbyCamera.target(at(5), _phone);
      final ten = NearbyCamera.target(at(10), _phone);
      final twentyFive = NearbyCamera.target(at(25), _phone);
      expect(five.zoom, greaterThan(ten.zoom));
      expect(ten.zoom, greaterThan(twentyFive.zoom));
      // Doubling the radius is one zoom step; 2.5 times is about 1.32.
      expect(five.zoom - ten.zoom, closeTo(1.0, 0.01));
      expect(
          ten.zoom - twentyFive.zoom, closeTo(math.log(2.5) / math.ln2, 0.01));
    });

    test('the camera is a sensible zoom for each radius', () {
      expect(NearbyCamera.target(at(5), _phone).zoom, inInclusiveRange(11, 13));
      expect(
          NearbyCamera.target(at(10), _phone).zoom, inInclusiveRange(10, 12));
      expect(NearbyCamera.target(at(25), _phone).zoom, inInclusiveRange(9, 11));
    });

    test('the device is in the middle, and the whole circle is in view', () {
      for (final km in NearbyFilter.radiusOptionsKm) {
        final camera = NearbyCamera.target(at(km), _phone);
        final centre =
            UaeMapFraming.project(camera, _phone, _userLat, _userLng);
        expect(centre.x, closeTo(_phone.left + _phone.freeWidth / 2, 0.5));
        expect(centre.y, closeTo(_phone.top + _phone.freeHeight / 2, 0.5));
        // The four points of the circle, north, south, east and west.
        final dLat = km / _kmPerDegree;
        final dLng = km / (_kmPerDegree * math.cos(_userLat * math.pi / 180));
        for (final edge in [
          [_userLat + dLat, _userLng],
          [_userLat - dLat, _userLng],
          [_userLat, _userLng + dLng],
          [_userLat, _userLng - dLng],
        ]) {
          expect(_inFree(camera, edge[0], edge[1]), isTrue,
              reason: '$km km edge $edge');
        }
      }
    });

    test('every place Nearby lets through is in view', () async {
      for (final km in NearbyFilter.radiusOptionsKm) {
        final controller = await nearbyAt(km);
        final plan = _plan(
          MapCameraCause.nearbyRadiusChanged,
          controller.snapshot,
        )!;
        for (final place in controller.visible) {
          expect(_inFree(plan.target, place.latitude, place.longitude), isTrue,
              reason: '${place.id} at $km km');
        }
      }
    });

    test(
        '8. no place within the radius: the camera stays on the device, not '
        'on a place outside it', () async {
      final controller = _loaded([_north('far', 60), _north('farther', 90)]);
      await controller.enableNearby(_CountingLocator(_atUser));
      expect(controller.visible, isEmpty);
      expect(controller.hasNoMatches, isTrue, reason: 'the zero-result state');

      for (final km in NearbyFilter.radiusOptionsKm) {
        controller.setNearbyRadius(km);
        final plan = _plan(
          MapCameraCause.nearbyRadiusChanged,
          controller.snapshot,
        )!;
        expect(plan.subject, MapCameraSubject.nearbyArea);
        // It is the circle around the device, not the unrelated places.
        expect(plan.target, NearbyCamera.target(at(km), _phone));
        expect(_inFree(plan.target, _userLat, _userLng), isTrue);
        for (final place in controller.all) {
          expect(_inFree(plan.target, place.latitude, place.longitude), isFalse,
              reason: '${place.id} is outside $km km: not in the frame');
        }
      }
    });

    test('9. no place within the radius: the zoom still follows the radius',
        () async {
      // Nothing is near: 5, 10 and 25 km all show an empty circle, and each
      // empty circle is a different, deterministic zoom around the device.
      final controller = _loaded([_north('far', 80)]);
      await controller.enableNearby(_CountingLocator(_atUser));
      final zooms = <int, double>{};
      for (final km in NearbyFilter.radiusOptionsKm) {
        controller.setNearbyRadius(km);
        expect(controller.visible, isEmpty, reason: '$km km');
        final plan = _plan(
          MapCameraCause.nearbyRadiusChanged,
          controller.snapshot,
        )!;
        expect(plan.subject, MapCameraSubject.nearbyArea, reason: '$km km');
        zooms[km] = plan.target.zoom;
      }
      expect(zooms[5]!, greaterThan(zooms[10]!));
      expect(zooms[10]!, greaterThan(zooms[25]!));
      // The same zoom as with places around: the radius decides it, not them.
      for (final km in NearbyFilter.radiusOptionsKm) {
        expect(zooms[km], NearbyCamera.target(at(km), _phone).zoom);
      }
    });

    test(
        'the camera follows the radius chosen, even when the places do not '
        'change', () async {
      // Everything is within 3 km: 5, 10 and 25 km show the same places, and
      // the camera still moves with each radius.
      final controller =
          _loaded([_north('a', 1), _north('b', 2), _north('c', 3)]);
      await controller.enableNearby(_CountingLocator(_atUser));
      final targets = <int, MapCameraTarget>{};
      final shown = <int, Set<String>>{};
      for (final km in NearbyFilter.radiusOptionsKm) {
        controller.setNearbyRadius(km);
        shown[km] = _ids(controller.visible).toSet();
        targets[km] = _plan(
          MapCameraCause.nearbyRadiusChanged,
          controller.snapshot,
        )!
            .target;
      }
      expect(shown[5], shown[10]);
      expect(shown[10], shown[25]);
      expect(targets[5], isNot(targets[10]));
      expect(targets[10], isNot(targets[25]));
      expect(targets[5]!.zoom, greaterThan(targets[25]!.zoom));
    });

    test('turning Nearby on frames the radius it was turned on at', () async {
      final controller = _loaded(spread());
      await controller.enableNearby(_CountingLocator(_atUser));
      final plan = _plan(MapCameraCause.nearbyEnabled, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.nearbyArea);
      expect(plan.target, NearbyCamera.target(at(10), _phone));
    });

    test('the plan uses the radius in the snapshot, not an earlier one',
        () async {
      final controller = await nearbyAt(25);
      final early = controller.snapshot;
      controller.setNearbyRadius(5);
      final late = controller.snapshot;
      expect(
        _plan(MapCameraCause.nearbyRadiusChanged, early)!.target,
        NearbyCamera.target(at(25), _phone),
      );
      expect(
        _plan(MapCameraCause.nearbyRadiusChanged, late)!.target,
        NearbyCamera.target(at(5), _phone),
      );
    });
  });

  group('City: only that city\'s places', () {
    List<CachedLocationData> cities() => [
          _at('ad1', 24.45, 54.38, city: 'Abu Dhabi'),
          _at('ad2', 24.50, 54.40, city: 'Abu Dhabi'),
          _at('aj1', 25.41, 55.51, city: 'Ajman'),
          _at('aj2', 25.40, 55.52, city: 'Ajman'),
          _at('du1', 25.20, 55.27, city: 'Dubai'),
        ];

    test('10. Abu Dhabi shows the Abu Dhabi places and no others', () {
      final controller = _loaded(cities())..setCity('Abu Dhabi');
      expect(_ids(controller.visible), ['ad1', 'ad2']);
      for (final place in controller.visible) {
        expect(place.city, 'Abu Dhabi');
      }
    });

    test('11. an Ajman place cannot survive the Abu Dhabi filter', () {
      final controller = _loaded(cities())..setCity('Abu Dhabi');
      expect(
          _ids(controller.visible).any((id) => id.startsWith('aj')), isFalse);
      controller.setCity('Ajman');
      expect(_ids(controller.visible), ['aj1', 'aj2']);
      controller.setCity('Abu Dhabi');
      expect(controller.visible.any((place) => place.city == 'Ajman'), isFalse);
    });

    test('an Offer in Ajman, written either way, is never an Abu Dhabi place',
        () {
      final vocabulary = MapVocabulary(cityLabels: (city) => const <String>[]);
      final places = MapLocationMapper.offers(
        [
          _offer('structured', city: 'Ajman', lat: 25.41, lng: 55.51),
          _offer(
            'legacy-a',
            city: '',
            lat: 25.41,
            lng: 55.51,
            address: 'Ajman, Al Jurf',
          ),
          _offer(
            'legacy-b',
            city: '',
            lat: 25.41,
            lng: 55.51,
            address: 'Al Jurf, Ajman',
          ),
          _offer('abu-dhabi', city: 'Abu Dhabi', lat: 24.45, lng: 54.38),
        ],
        vocabulary: vocabulary,
      );
      final controller = _loaded(places)..setCity('Abu Dhabi');
      expect(_ids(controller.visible), ['abu-dhabi']);
      controller.setCity('Ajman');
      expect(
        _ids(controller.visible),
        ['structured', 'legacy-a', 'legacy-b'],
      );
    });

    test('12. Abu Dhabi with places: the camera frames only those places', () {
      final controller = _loaded(cities())..setCity('Abu Dhabi');
      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      expect(
        plan.target,
        MapFraming.fitPoints(
          const [MapGeoPoint(24.45, 54.38), MapGeoPoint(24.50, 54.40)],
          viewport: _phone,
        ),
      );
      for (final place in controller.visible) {
        expect(_inFree(plan.target, place.latitude, place.longitude), isTrue);
      }
      // Nothing from another city is in the frame, near or far.
      for (final place in controller.all.where((p) => p.city != 'Abu Dhabi')) {
        expect(_inFree(plan.target, place.latitude, place.longitude), isFalse,
            reason: '${place.id} is in ${place.city}');
      }
    });

    test('a city with one place frames that place, at street level', () {
      final controller = _loaded(cities())..setCity('Dubai');
      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      expect(plan.target.zoom, 15);
      expect(plan.target.latitude, closeTo(25.20, 0.05));
    });

    test('13. Abu Dhabi with no places: the camera goes to Abu Dhabi', () {
      final controller = _loaded([
        _at('aj1', 25.41, 55.51, city: 'Ajman'),
        _at('du1', 25.20, 55.27, city: 'Dubai'),
      ])
        ..setCity('Abu Dhabi');
      expect(controller.visible, isEmpty);
      expect(controller.hasNoMatches, isTrue,
          reason: 'the zero-result state, not a load failure');

      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
      final frame = MapCityCameras.of('Abu Dhabi')!;
      expect(plan.subject, MapCameraSubject.city);
      expect(plan.target.zoom, frame.zoom);
      expect(
          plan.target,
          MapFraming.centered(
            frame.latitude,
            frame.longitude,
            frame.zoom,
            _phone,
          ));
      // Abu Dhabi is in the middle of the free part of the screen.
      final centre = UaeMapFraming.project(
        plan.target,
        _phone,
        frame.latitude,
        frame.longitude,
      );
      expect(centre.x, closeTo(_phone.left + _phone.freeWidth / 2, 0.5));
      expect(centre.y, closeTo(_phone.top + _phone.freeHeight / 2, 0.5));
    });

    test('14. no places in the city: never the other cities\' places, nor all',
        () {
      final places = cities().where((p) => p.city != 'Abu Dhabi').toList();
      final controller = _loaded(places)..setCity('Abu Dhabi');
      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;

      expect(plan.subject, MapCameraSubject.city);
      final all = MapFraming.fitPoints(
        [for (final p in places) MapGeoPoint(p.latitude, p.longitude)],
        viewport: _phone,
      );
      expect(plan.target, isNot(all));
      for (final place in places) {
        expect(_inFree(plan.target, place.latitude, place.longitude), isFalse,
            reason: '${place.id} must not be what the camera shows');
      }
      // It is on Abu Dhabi, hundreds of kilometres from Ajman.
      expect(plan.target.longitude, closeTo(54.38, 0.2));
      expect(plan.target.latitude, closeTo(24.45, 0.3));
    });

    test('a city with no places and Nearby on still shows the city', () async {
      final controller = _loaded([_north('near', 3, city: 'Sharjah')]);
      await controller.enableNearby(_CountingLocator(_atUser));
      controller.setCity('Abu Dhabi');
      expect(controller.visible, isEmpty);
      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.city);
      expect(plan.target.longitude, closeTo(54.38, 0.2));
    });

    test('every city of the catalog can be shown with no places in it', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final frame = MapCityCameras.of(city)!;
        final controller = _loaded([_at('x', 0.5, 0.5, city: 'Nowhere')])
          ..setCity(city);
        final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
        expect(plan.subject, MapCameraSubject.city, reason: city);
        expect(plan.target.zoom, frame.zoom, reason: city);
        expect(_inFree(plan.target, frame.latitude, frame.longitude), isTrue,
            reason: city);
      }
    });

    test('back to every city frames the places there are', () {
      final controller = _loaded(cities())
        ..setCity('Abu Dhabi')
        ..setCity(null);
      final plan = _plan(MapCameraCause.cityChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      for (final place in controller.all) {
        expect(_inFree(plan.target, place.latitude, place.longitude), isTrue,
            reason: place.id);
      }
    });

    test('15. choosing cities costs no backend read', () async {
      final source = _Source(cities());
      final controller = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _Cache(),
        onPlaces: (places, {required fresh}) async =>
            controller.setRecords(places),
        onFailed: () {},
      );
      await loader.start();
      for (final city in [
        'Abu Dhabi',
        'Dubai',
        'Ajman',
        'Al Ain',
        null,
        'Abu Dhabi'
      ]) {
        controller.setCity(city);
      }
      expect(source.loads, 1);
      loader.dispose();
    });

    test('the canonical cities have one camera each, in the catalog', () {
      expect(
        MapCityCameras.cities.toSet(),
        UaeAreaCatalog.supportedCities.toSet(),
        reason: 'one list of cities: this only says where to look',
      );
      expect(MapCityCameras.cities, hasLength(9));
      expect(MapCityCameras.of('Atlantis'), isNull);
    });

    test('each city\'s camera is in its own place, inside the map\'s area', () {
      // Each city looks inside the area the map opens on, at a city-sized zoom.
      for (final city in MapCityCameras.cities) {
        final own = MapCityCameras.of(city)!;
        expect(own.latitude,
            inInclusiveRange(UaeMapFraming.south, UaeMapFraming.north),
            reason: city);
        expect(own.longitude,
            inInclusiveRange(UaeMapFraming.west, UaeMapFraming.east),
            reason: city);
        expect(own.zoom, inInclusiveRange(9, 13), reason: city);
      }
      final abuDhabi = MapCityCameras.of('Abu Dhabi')!;
      final ajman = MapCityCameras.of('Ajman')!;
      expect(
        GeoDistance.meters(abuDhabi.latitude, abuDhabi.longitude,
            ajman.latitude, ajman.longitude),
        greaterThan(100000),
        reason: 'Abu Dhabi and Ajman are far apart',
      );
    });
  });

  group('the camera plan for each cause', () {
    MapFilterSnapshot someSnapshot() => _loaded([
          _at('a', 25.20, 55.27, city: 'Dubai'),
          _at('b', 25.30, 55.40, city: 'Sharjah'),
        ]).snapshot;

    test('opening, "my location" and a refresh plan no camera move', () {
      final snapshot = someSnapshot();
      for (final cause in [
        MapCameraCause.initialOpen,
        MapCameraCause.locateMe,
        MapCameraCause.backgroundRefresh,
      ]) {
        expect(_plan(cause, snapshot), isNull, reason: cause.name);
      }
    });

    test('any other filter frames the places it lets through', () {
      final controller = _loaded([
        _at('a', 25.20, 55.27, type: LocationFilter.offers),
        _at('b', 25.30, 55.40, type: LocationFilter.owners),
      ])
        ..setEntityType(LocationFilter.owners);
      final plan = _plan(MapCameraCause.filterChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      expect(_inFree(plan.target, 25.30, 55.40), isTrue);
      expect(_inFree(plan.target, 25.20, 55.27), isFalse,
          reason: 'the Offer is not shown, so it is not framed');
    });

    test('a filter that lets nothing through leaves the camera where it is',
        () {
      final controller = _loaded([_at('a', 25.20, 55.27)])
        ..setEntityType(LocationFilter.watchmen);
      expect(controller.visible, isEmpty);
      expect(_plan(MapCameraCause.filterChanged, controller.snapshot), isNull);
    });

    test('Clear frames the places there are, never the country', () {
      final controller = _loaded([
        _at('a', 25.20, 55.27, city: 'Dubai'),
        _at('b', 24.45, 54.38, city: 'Abu Dhabi'),
      ])
        ..setCity('Dubai')
        ..clear();
      final plan = _plan(MapCameraCause.filterChanged, controller.snapshot)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      expect(plan.target, isNot(UaeMapFraming.fit(_phone)));
      for (final place in controller.all) {
        expect(_inFree(plan.target, place.latitude, place.longitude), isTrue);
      }
    });

    test('the causes are the owner\'s eight (All UAE is one)', () {
      expect(MapCameraCause.values.map((c) => c.name), [
        'initialOpen',
        'cityChanged',
        'allUae',
        'nearbyEnabled',
        'nearbyRadiusChanged',
        'locateMe',
        'filterChanged',
        'backgroundRefresh',
      ]);
    });
  });

  group('a slower older choice cannot move the map after a newer one', () {
    final dubai = _at('du', 25.20, 55.27, city: 'Dubai');
    final abuDhabi = _at('ad', 24.45, 54.38, city: 'Abu Dhabi');
    final ajman = _at('aj', 25.41, 55.51, city: 'Ajman');

    test('16. a slow older city cannot override a newer city', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      rig.chose(rig.controller.setCity('Dubai'), MapCameraCause.cityChanged);
      expect(rig.draws, hasLength(2));

      // The newer one finishes first; the older one finishes late.
      await rig.finish(1);
      await rig.finish(0);

      expect(rig.published, hasLength(1));
      expect(rig.published.single.state.city, 'Dubai');
      expect(rig.moves, hasLength(1));
      expect(rig.moves.single.subject, MapCameraSubject.matchingPlaces);
      expect(_inFree(rig.moves.single.target, 25.20, 55.27), isTrue);
      expect(_inFree(rig.moves.single.target, 24.45, 54.38), isFalse);
    });

    test('the older one finishing first changes nothing either', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      rig.chose(rig.controller.setCity('Dubai'), MapCameraCause.cityChanged);

      await rig.finish(0);
      expect(rig.published, isEmpty, reason: 'the older draw was overtaken');
      expect(rig.moves, isEmpty);
      await rig.finish(1);
      expect(rig.published.single.state.city, 'Dubai');
      expect(rig.moves, hasLength(1));
    });

    test('an older draw that never checks is still refused', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      rig.chose(rig.controller.setCity('Dubai'), MapCameraCause.cityChanged);
      await rig.finish(1);
      await rig.finishBlind(0);

      expect(rig.published.map((s) => s.state.city), ['Dubai']);
      expect(rig.moves, hasLength(1));
      expect(rig.moves.single.target.latitude, closeTo(25.20, 0.1));
    });

    test('17. a slow older radius cannot override a newer radius', () async {
      final rig = _Rig([
        _north('a', 3),
        _north('b', 8),
        _north('c', 20),
      ]);
      await rig.controller.enableNearby(_CountingLocator(_atUser));
      rig.chose(true, MapCameraCause.nearbyEnabled);
      await rig.finish(0);
      rig.moves.clear();
      rig.published.clear();

      rig.chose(rig.controller.setNearbyRadius(5),
          MapCameraCause.nearbyRadiusChanged);
      rig.chose(rig.controller.setNearbyRadius(25),
          MapCameraCause.nearbyRadiusChanged);
      await rig.finish(2);
      await rig.finishBlind(1);

      expect(rig.published, hasLength(1));
      expect(rig.published.single.state.nearby!.radiusKm, 25);
      expect(rig.moves, hasLength(1));
      expect(rig.moves.single.subject, MapCameraSubject.nearbyArea);
      expect(
        rig.moves.single.target,
        NearbyCamera.target(
          const NearbyFilter(
            latitude: _userLat,
            longitude: _userLng,
            radiusKm: 25,
          ),
          _phone,
        ),
      );
    });

    test('18. an old result cannot put a stale card back', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.controller.select('offers:aj');
      expect(rig.controller.selectedKey, 'offers:aj');
      // A draw for the filter as it was, with the Ajman card open, is slow.
      rig.chose(true, MapCameraCause.filterChanged);
      expect(rig.draws.single.snapshot.selectedKey, 'offers:aj');

      // The person chooses Abu Dhabi: the card closes at once.
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      expect(rig.controller.selectedKey, isNull);
      await rig.finish(1);
      await rig.finishBlind(0);

      expect(rig.published, hasLength(1));
      expect(rig.published.single.selectedKey, isNull);
      expect(
        rig.published.any((snapshot) => snapshot.selectedKey == 'offers:aj'),
        isFalse,
        reason: 'the old result never reached the map',
      );
    });

    test('19. places read again do not move an explicit city camera', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      await rig.finish(0);
      expect(rig.moves, hasLength(1), reason: 'the choice moved it once');

      // A refresh arrives: drawn, but the camera stays where the person left it.
      rig.refreshed(
          [dubai, abuDhabi, ajman, _at('ad2', 24.5, 54.4, city: 'Abu Dhabi')]);
      await rig.finish(1);
      rig.refreshed([dubai, abuDhabi]);
      await rig.finish(2);
      expect(rig.published, hasLength(3));
      expect(rig.moves, hasLength(1), reason: 'a refresh asked for no move');
    });

    test('19. places read again do not move an explicit Nearby camera',
        () async {
      final rig = _Rig([_north('a', 3), _north('b', 8)]);
      await rig.controller.enableNearby(_CountingLocator(_atUser));
      rig.chose(true, MapCameraCause.nearbyEnabled);
      await rig.finish(0);
      expect(rig.moves, hasLength(1));
      rig.refreshed([_north('a', 3), _north('b', 8), _north('c', 6)]);
      await rig.finish(1);
      expect(rig.moves, hasLength(1));
    });

    test('a refresh that overtakes a choice does not lose it', () async {
      final rig = _Rig([dubai, abuDhabi, ajman]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      // The places are read again while the choice is still being drawn.
      rig.refreshed(
          [dubai, abuDhabi, ajman, _at('ad2', 24.5, 54.4, city: 'Abu Dhabi')]);
      await rig.finish(1);
      await rig.finishBlind(0);

      expect(rig.published, hasLength(1));
      expect(rig.published.single.visible.map((p) => p.id), ['ad', 'ad2']);
      expect(rig.moves, hasLength(1), reason: 'the choice still moved, once');
      expect(rig.moves.single.cause, MapCameraCause.cityChanged);
      expect(rig.moves.single.subject, MapCameraSubject.matchingPlaces);
      // Over the newest places.
      expect(_inFree(rig.moves.single.target, 24.5, 54.4), isTrue);
    });

    test('Clear leaves no Nearby camera behind', () async {
      final rig = _Rig([_north('a', 3), _north('b', 8), dubai]);
      await rig.controller.enableNearby(_CountingLocator(_atUser));
      rig.chose(true, MapCameraCause.nearbyEnabled);
      await rig.finish(0);
      rig.moves.clear();

      rig.chose(rig.controller.setNearbyRadius(25),
          MapCameraCause.nearbyRadiusChanged);
      // Cleared before that draw finishes.
      rig.chose(rig.controller.clear(), MapCameraCause.filterChanged);
      await rig.finishBlind(1);
      await rig.finish(2);

      expect(rig.published.last.state, MapFilterState.initial);
      expect(rig.moves, hasLength(1));
      expect(rig.moves.single.subject, MapCameraSubject.matchingPlaces,
          reason: 'places, not the radius circle');
      expect(rig.controller.state.nearby, isNull);
    });

    test('a request for a choice that was overtaken can never move', () async {
      final rig = _Rig([dubai, abuDhabi]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      // A draw for a LATER state is published without a new request (a
      // refresh): the old request must be dropped, not applied to it.
      rig.controller.setCity('Dubai');
      unawaited(rig.pipeline.show(rig.controller.snapshot));
      await rig.finish(1);
      await rig.finishBlind(0);
      expect(rig.published.single.state.city, 'Dubai');
      expect(rig.moves, isEmpty);
    });

    test('"my location" does not override a choice made while it waited',
        () async {
      final rig = _Rig([dubai, abuDhabi]);
      final epoch = rig.pipeline.cameraEpoch;
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      expect(rig.pipeline.cameraEpoch, isNot(epoch),
          reason: 'the person chose again: the slow position must not move it');
    });

    test('a camera move of the person\'s own cancels a request that waits',
        () async {
      final rig = _Rig([dubai, abuDhabi]);
      rig.chose(
          rig.controller.setCity('Abu Dhabi'), MapCameraCause.cityChanged);
      final before = rig.pipeline.cameraEpoch;
      rig.pipeline.cancelCamera();
      expect(rig.pipeline.cameraEpoch, isNot(before));
      await rig.finish(0);
      expect(rig.published, hasLength(1), reason: 'the markers still draw');
      expect(rig.moves, isEmpty,
          reason: 'but no older request moves the camera');
    });

    test('the markers of a refresh are drawn though it asks for no camera',
        () async {
      final rig = _Rig([dubai]);
      rig.refreshed([dubai, abuDhabi]);
      await rig.finish(0);
      expect(rig.published, hasLength(1));
      expect(rig.moves, isEmpty);
    });
  });

  group('the open card follows the filter', () {
    List<CachedLocationData> mixed() => [
          _north('near', 3, city: 'Sharjah'),
          _north('far', 20, city: 'Sharjah'),
          _at('abu', 24.45, 54.38, city: 'Abu Dhabi'),
        ];

    test('20. a card closes when the city excludes its place', () {
      final controller = _loaded(mixed())..select('offers:far');
      controller.setCity('Abu Dhabi');
      expect(controller.selectedKey, isNull);
      expect(controller.snapshot.selectedKey, isNull);
    });

    test('20. a card closes when the radius excludes its place', () async {
      final controller = _loaded(mixed());
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 25);
      controller.select('offers:far');
      expect(controller.selectedKey, 'offers:far');
      controller.setNearbyRadius(5);
      expect(controller.selectedKey, isNull);
    });

    test('21. a card stays when the city still includes its place', () {
      final controller = _loaded(mixed())..select('offers:near');
      controller.setCity('Sharjah');
      expect(controller.selectedKey, 'offers:near');
    });

    test('21. a card stays when the radius still includes its place', () async {
      final controller = _loaded(mixed());
      await controller.enableNearby(_CountingLocator(_atUser), radiusKm: 25);
      controller.select('offers:near');
      controller.setNearbyRadius(5);
      expect(controller.selectedKey, 'offers:near');
      controller.setNearbyRadius(10);
      expect(controller.selectedKey, 'offers:near');
    });

    test('a card never outlives a city that excludes it, across changes', () {
      final controller = _loaded(mixed());
      controller.select('offers:abu');
      controller.setCity('Abu Dhabi');
      expect(controller.selectedKey, 'offers:abu');
      controller.setCity('Sharjah');
      expect(controller.selectedKey, isNull);
      controller.select('offers:near');
      controller.setCity('Abu Dhabi');
      expect(controller.selectedKey, isNull);
    });
  });

  group('Clear and the filter snapshot', () {
    test('22. Clear restores every default, and asks the device for nothing',
        () async {
      final locator = _CountingLocator(_atUser);
      final controller = _loaded([
        _north('a', 3, city: 'Sharjah'),
        _north('b', 20, city: 'Sharjah'),
      ]);
      await controller.enableNearby(locator);
      controller
        ..setEntityType(LocationFilter.offers)
        ..setCity('Sharjah')
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent)
        ..setPriceMode(MapPriceMode.lowest)
        ..setNearbyRadius(5);
      expect(controller.filtersActive, isTrue);

      expect(controller.clear(), isTrue);
      expect(controller.state, MapFilterState.initial);
      expect(controller.state.entityType, LocationFilter.all);
      expect(controller.state.city, isNull);
      expect(controller.state.propertyType, isNull);
      expect(controller.state.transaction, isNull);
      expect(controller.state.priceMode, MapPriceMode.all);
      expect(controller.state.nearby, isNull);
      expect(controller.visible, hasLength(2));
      expect(locator.calls, 1, reason: 'Clear does not ask for location');
    });

    test('a snapshot is one consistent picture, and is not changed later',
        () async {
      final controller = _loaded([_north('a', 3), _north('b', 20)]);
      final before = controller.snapshot;
      await controller.enableNearby(_CountingLocator(_atUser));
      controller.setNearbyRadius(5);
      expect(before.state, MapFilterState.initial);
      expect(before.visible, hasLength(2));
      final after = controller.snapshot;
      expect(after.visible, hasLength(1));
      expect(after.stateVersion, greaterThan(before.stateVersion));
    });

    test('the filter version counts choices, not refreshes', () {
      final controller = _loaded([_north('a', 3)]);
      final first = controller.snapshot;
      controller.setRecords([_north('a', 3), _north('b', 4)]);
      final refreshed = controller.snapshot;
      expect(refreshed.stateVersion, first.stateVersion);
      expect(refreshed.recordsVersion, greaterThan(first.recordsVersion));
      controller.setCity('Dubai');
      expect(controller.snapshot.stateVersion, greaterThan(first.stateVersion));
      // Choosing what is already chosen is no choice.
      final same = controller.snapshot.stateVersion;
      controller.setCity('Dubai');
      expect(controller.snapshot.stateVersion, same);
    });
  });
}
