// A coarse UAE-level sanity check on coordinates, and what depends on it.
//
// One pure rule says whether a position could reasonably be inside the UAE (a
// generous rectangle, not a border, no city polygons). It guards two places and
// nothing else:
//
//  * the Map: a record whose pin could not be in the UAE is not a place, so it
//    has no marker and cannot move any camera or take part in Nearby. The record
//    itself is untouched;
//  * a pin picked on the map for a form (Offer, Owner, Office, Watchman): a
//    position outside the UAE is turned away and the form keeps what it had.
//
// It is NOT applied when a record is saved, so a legacy record with a bad pin
// stays editable. Plain Dart.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/data/picked_location_gate.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/data/uae_coordinate_sanity.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/core_entity_payload_builder.dart';
import 'package:broker_wallet/src/services/geo_distance.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_city_geography.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Independent reference centres of the nine cities (public coordinates), NOT
// read from the app.
const Map<String, List<double>> _cities = {
  'Dubai': [25.2048, 55.2708],
  'Abu Dhabi': [24.4539, 54.3773],
  'Sharjah': [25.3463, 55.4209],
  'Ajman': [25.4052, 55.5136],
  'Ras Al Khaimah': [25.7895, 55.9432],
  'Fujairah': [25.1288, 56.3265],
  'Umm Al Quwain': [25.5647, 55.5552],
  'Al Ain': [24.2075, 55.7447],
  'Khor Fakkan': [25.3395, 56.3563],
};

// Ordinary places in the west and south of Abu Dhabi's emirate, which the map's
// opening camera box leaves out on purpose.
const Map<String, List<double>> _west = {
  'Al Ghuwaifat': [24.09, 51.61],
  'Sila': [24.04, 51.74],
  'Dalma island': [24.50, 52.33],
  'Sir Bani Yas': [24.33, 52.60],
  'Jebel Dhanna': [24.19, 52.60],
  'Ruwais': [24.11, 52.73],
  'Das island': [25.15, 52.87],
  'Ghayathi': [23.84, 52.80],
  'Madinat Zayed': [23.66, 53.70],
  'Liwa': [23.13, 53.77],
};

// Ordinary places in the east and north.
const Map<String, List<double>> _east = {
  'Hatta': [24.80, 56.12],
  'Masafi': [25.30, 56.15],
  'Kalba': [25.07, 56.35],
  'Dibba Al-Fujairah': [25.59, 56.26],
  'Dibba Al-Hisn': [25.62, 56.27],
  'Rams': [25.88, 56.06],
};

// The UAE's own rough extremes (public geography), to show how much room the
// rectangle leaves beyond them.
const double _extremeSouth = 22.6;
const double _extremeNorth = 26.1;
const double _extremeWest = 51.6;
const double _extremeEast = 56.4;

// The hosted row that started this correction: Umm Al Quwain, longitude 34.09.
const double _badLat = 24.6263;
const double _badLng = 34.0921;

const MapViewport _phone = MapViewport(
  width: 360,
  height: 780,
  top: 156,
  bottom: 72,
  left: 16,
  right: 16,
);

final DateTime _now = DateTime(2026, 10, 10);

double _km(double lat1, double lng1, double lat2, double lng2) =>
    GeoDistance.meters(lat1, lng1, lat2, lng2) / 1000;

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

OfferModel _offer(String id, String city, double lat, double lng) => OfferModel(
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
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OwnerModel _owner(String id, double lat, double lng) => OwnerModel(
      id: id,
      userId: 'u1',
      name: 'Sara',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OfficeModel _office(String id, double lat, double lng) => OfficeModel(
      id: id,
      officeName: 'Palm Office',
      managerName: 'Ali',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

WatchmenModel _watchman(String id, double lat, double lng) => WatchmenModel(
      id: id,
      name: 'Omar',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: 'Tower A',
      notes: '',
      buildingLocation: '',
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

// Offers shaped like the hosted ones that were read back: five Ajman Offers
// whose pins are in Ajman, three whose city says one place and whose pin is in
// another (Correction 4 keeps those off a city's camera), and the Umm Al Quwain
// one with longitude 34.09. Ids are made up.
List<OfferModel> _hostedShaped() => [
      _offer('city-pin-abu-dhabi', 'Abu Dhabi', 25.410, 55.519),
      _offer('ajman-1', 'Ajman', 25.374, 55.596),
      _offer('ajman-2', 'Ajman', 25.407, 55.510),
      _offer('ajman-3', 'Ajman', 25.404, 55.508),
      _offer('ajman-4', 'Ajman', 25.373, 55.596),
      _offer('ajman-5', 'Ajman', 25.374, 55.596),
      _offer('city-pin-fujairah', 'Fujairah', 25.407, 55.510),
      _offer('city-pin-sharjah', 'Sharjah', 25.2048, 55.2708),
      _offer('bad-umm-al-quwain', 'Umm Al Quwain', _badLat, _badLng),
    ];

List<OfferModel> _withoutBad(List<OfferModel> offers) => [
      for (final offer in offers)
        if (offer.id != 'bad-umm-al-quwain') offer,
    ];

MapFilterController _loaded(List<OfferModel> offers) =>
    MapFilterController()..setRecords(MapLocationMapper.offers(offers));

MapCameraPlan? _plan(MapCameraCause cause, MapFilterController controller) =>
    MapCameraPlanner.plan(
      cause: cause,
      snapshot: controller.snapshot,
      viewport: _phone,
    );

String _describe(MapCameraPlan? plan) => plan == null
    ? 'stays'
    : '${plan.subject.name} '
        '${plan.target.latitude.toStringAsFixed(4)}, '
        '${plan.target.longitude.toStringAsFixed(4)} '
        'z${plan.target.zoom.toStringAsFixed(2)}';

void _expectSamePlan(
  MapCameraPlan? actual,
  MapCameraPlan? wanted, {
  required String reason,
}) {
  expect(_describe(actual), _describe(wanted), reason: reason);
  expect(actual?.target, wanted?.target, reason: reason);
}

class _Locator implements NearbyLocator {
  const _Locator(this.fix);

  final NearbyFix fix;

  @override
  Future<NearbyFix> locate() async => fix;
}

// A form's pickup location, as the four forms keep it.
class _FakeForm {
  double? latitude;
  double? longitude;

  Future<void> select(double lat, double lng) async {
    await Future<void>.delayed(Duration.zero);
    latitude = lat;
    longitude = lng;
  }
}

Future<bool> _pick(
  _FakeForm form,
  double lat,
  double lng,
  List<String> messages,
) =>
    PickedLocationGate.admit(
      latitude: lat,
      longitude: lng,
      accept: () => form.select(lat, lng),
      reject: () => messages.add('outside the UAE'),
    );

void main() {
  group('the UAE sanity rule: could this position be inside the UAE?', () {
    test('1. every canonical city centre passes', () {
      for (final entry in _cities.entries) {
        expect(
          UaeCoordinateSanity.couldBeInUae(entry.value[0], entry.value[1]),
          isTrue,
          reason: entry.key,
        );
      }
      // The app's own camera table too, and the table covers every city the
      // forms offer.
      expect(
        MapCityCameras.cities.toSet(),
        UaeAreaCatalog.supportedCities.toSet(),
      );
      expect(_cities.keys.toSet(), UaeAreaCatalog.supportedCities.toSet());
      for (final city in MapCityCameras.cities) {
        final frame = MapCityCameras.of(city)!;
        expect(
          UaeCoordinateSanity.couldBeInUae(frame.latitude, frame.longitude),
          isTrue,
          reason: city,
        );
      }
    });

    test('2. ordinary places in the west and south of Abu Dhabi pass', () {
      for (final entry in _west.entries) {
        expect(
          UaeCoordinateSanity.couldBeInUae(entry.value[0], entry.value[1]),
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('3. ordinary places in the east and north pass', () {
      for (final entry in _east.entries) {
        expect(
          UaeCoordinateSanity.couldBeInUae(entry.value[0], entry.value[1]),
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('4. the hosted Umm Al Quwain coordinate (24.6263, 34.0921) fails', () {
      expect(UaeCoordinateSanity.couldBeInUae(_badLat, _badLng), isFalse);
      // It is a valid position on Earth: that is why nothing else caught it.
      expect(MapLocationMapper.isUsableCoordinate(_badLat, _badLng), isTrue);
    });

    test('5. a latitude outside the UAE region fails', () {
      for (final lat in [21.99, 26.61, 27.19, 30.04, 40.0, 89.99, 0.5, -25.0]) {
        expect(
          UaeCoordinateSanity.couldBeInUae(lat, 55.3),
          isFalse,
          reason: 'latitude $lat',
        );
      }
    });

    test('6. a longitude outside the UAE region fails', () {
      for (final lng in [34.0921, 46.68, 50.49, 57.01, 58.38, 72.88, -0.12]) {
        expect(
          UaeCoordinateSanity.couldBeInUae(25.2, lng),
          isFalse,
          reason: 'longitude $lng',
        );
      }
    });

    test('far-away cities, a swapped pair and impossible numbers all fail', () {
      const elsewhere = <String, List<double>>{
        'Cairo': [30.0444, 31.2357],
        'Riyadh': [24.7136, 46.6753],
        'Muscat': [23.5880, 58.3829],
        'Bandar Abbas': [27.1865, 56.2808],
        'Mumbai': [19.0760, 72.8777],
        'London': [51.5074, -0.1278],
        'Sydney': [-33.8688, 151.2093],
        'Null Island': [0.0, 0.0],
      };
      for (final entry in elsewhere.entries) {
        expect(
          UaeCoordinateSanity.couldBeInUae(entry.value[0], entry.value[1]),
          isFalse,
          reason: entry.key,
        );
      }
      // Latitude and longitude the wrong way round.
      expect(UaeCoordinateSanity.couldBeInUae(55.27, 25.2), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(double.nan, 55.3), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(25.2, double.nan), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(double.infinity, 55.3), isFalse);
      expect(
        UaeCoordinateSanity.couldBeInUae(25.2, double.negativeInfinity),
        isFalse,
      );
    });

    test('the rectangle\'s edges: just inside passes, just outside fails', () {
      const s = UaeCoordinateSanity.south;
      const n = UaeCoordinateSanity.north;
      const w = UaeCoordinateSanity.west;
      const e = UaeCoordinateSanity.east;
      expect(UaeCoordinateSanity.couldBeInUae(s, w), isTrue);
      expect(UaeCoordinateSanity.couldBeInUae(n, e), isTrue);
      expect(UaeCoordinateSanity.couldBeInUae(s + 0.001, w + 0.001), isTrue);
      expect(UaeCoordinateSanity.couldBeInUae(n - 0.001, e - 0.001), isTrue);
      expect(UaeCoordinateSanity.couldBeInUae(s - 0.001, 55.0), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(n + 0.001, 55.0), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(25.0, w - 0.001), isFalse);
      expect(UaeCoordinateSanity.couldBeInUae(25.0, e + 0.001), isFalse);
    });

    test('it is deliberately generous: half a degree beyond every extreme', () {
      const half = 0.5 - 1e-9;
      expect(_extremeSouth - UaeCoordinateSanity.south,
          greaterThanOrEqualTo(half));
      expect(UaeCoordinateSanity.north - _extremeNorth,
          greaterThanOrEqualTo(half));
      expect(
          _extremeWest - UaeCoordinateSanity.west, greaterThanOrEqualTo(half));
      expect(
          UaeCoordinateSanity.east - _extremeEast, greaterThanOrEqualTo(half));
    });

    test('it is not the opening camera box, which leaves out the west', () {
      // The camera box frames the nine cities. This rectangle has to hold the
      // whole country, so it is wider than the camera box on every side, and a
      // place in the Western Region is inside it but outside the camera box.
      expect(UaeCoordinateSanity.south, lessThan(UaeMapFraming.south));
      expect(UaeCoordinateSanity.north, greaterThan(UaeMapFraming.north));
      expect(UaeCoordinateSanity.west, lessThan(UaeMapFraming.west));
      expect(UaeCoordinateSanity.east, greaterThan(UaeMapFraming.east));
      final ruwais = _west['Ruwais']!;
      expect(ruwais[1], lessThan(UaeMapFraming.west));
      expect(UaeCoordinateSanity.couldBeInUae(ruwais[0], ruwais[1]), isTrue);
    });

    test('it is coarse on purpose: a rectangle, not a border or a city map',
        () {
      // A neighbour just across the edge can pass; it is a sanity check, not a
      // border.
      expect(UaeCoordinateSanity.couldBeInUae(25.2854, 51.5310), isTrue,
          reason: 'Doha is inside the rectangle');
      final text = _source('lib/src/common/data/uae_coordinate_sanity.dart');
      expect(text.contains('package:flutter'), isFalse);
      expect(RegExp(r"^import ", multiLine: true).hasMatch(text), isFalse,
          reason: 'it needs nothing: no city table, no geography');
      for (final city in _cities.keys) {
        expect(text.contains("'$city'"), isFalse, reason: city);
      }
      expect(RegExp(r'static const double ').allMatches(text).length, 4,
          reason: 'four edges and nothing else');
      expect(RegExp(r'\b(Future|async|await|Timer|Stream)\b').hasMatch(text),
          isFalse);
    });
  });

  group('a record outside the UAE on the Map', () {
    test('7. it is not a place, so it has no marker (every kind of record)',
        () {
      expect(
        MapLocationMapper.offers(
            [_offer('b', 'Umm Al Quwain', _badLat, _badLng)]),
        isEmpty,
      );
      expect(
          MapLocationMapper.owners([_owner('b', _badLat, _badLng)]), isEmpty);
      expect(
        MapLocationMapper.offices([_office('b', _badLat, _badLng)]),
        isEmpty,
      );
      expect(
        MapLocationMapper.watchmen([_watchman('b', _badLat, _badLng)]),
        isEmpty,
      );
      // A valid coordinate that is nowhere near the UAE, and a swapped pair.
      expect(MapLocationMapper.offers([_offer('b', 'Dubai', 0, 55)]), isEmpty);
      expect(
        MapLocationMapper.offers([_offer('b', 'Dubai', 55.27, 25.2)]),
        isEmpty,
      );
    });

    test('7. the rest of the read is untouched: the other records still load',
        () {
      final places = MapLocationMapper.all(
        offers: [
          _offer('o-ok', 'Dubai', 25.2, 55.27),
          _offer('o-bad', 'Umm Al Quwain', _badLat, _badLng),
        ],
        owners: [
          _owner('w-bad', _badLat, _badLng),
          _owner('w-ok', 25.1, 55.2),
        ],
        offices: [_office('f-ok', 25.3, 55.3), _office('f-bad', 40.0, 3.0)],
        watchmen: [
          _watchman('m-bad', 0.5, 55.0),
          _watchman('m-ok', 25.4, 55.4)
        ],
      );
      expect(
        [for (final p in places) p.id],
        ['o-ok', 'w-ok', 'f-ok', 'm-ok'],
        reason: 'order of the map\'s chips, bad ones skipped, nothing thrown',
      );
      final controller = MapFilterController()..setRecords(places);
      expect(controller.all, hasLength(4));
      expect(controller.visible, hasLength(4));
      expect(
        controller.entityCounts[LocationFilter.offers],
        1,
        reason: 'the count is of places the map can show',
      );
    });

    test('7. markers are drawn from the visible places and from nothing else',
        () {
      final vm = _squash(
        _source('lib/src/views/Screens/home/map/map_viewmodel.dart'),
      );
      expect(vm.contains('for (final place in snapshot.visible)'), isTrue);
      expect(vm.contains('_filters.all'), isFalse,
          reason: 'no marker is built from the unfiltered places');
      final source =
          _squash(_source('lib/src/services/map_location_source.dart'));
      expect(source.contains('MapLocationMapper.all('), isTrue,
          reason: 'every place comes through the mapper');
    });

    test('8. it cannot affect any city camera', () {
      final hosted = _hostedShaped();
      final withBad = _loaded(hosted);
      final without = _loaded(_withoutBad(hosted));
      for (final city in UaeAreaCatalog.supportedCities) {
        withBad.setCity(city);
        without.setCity(city);
        _expectSamePlan(
          _plan(MapCameraCause.cityChanged, withBad),
          _plan(MapCameraCause.cityChanged, without),
          reason: city,
        );
        expect(
          withBad.visible.map((p) => p.id).toList(),
          without.visible.map((p) => p.id).toList(),
          reason: city,
        );
      }
    });

    test('8. choosing Umm Al Quwain goes to Umm Al Quwain, not to Egypt', () {
      final controller = _loaded(_hostedShaped())..setCity('Umm Al Quwain');
      expect(controller.visible, isEmpty);
      expect(controller.hasNoMatches, isTrue,
          reason: 'the existing "no matches" banner, not an error');
      final plan = _plan(MapCameraCause.cityChanged, controller)!;
      expect(plan.subject, MapCameraSubject.city);
      final centre = _cities['Umm Al Quwain']!;
      expect(
        _km(plan.target.latitude, plan.target.longitude, centre[0], centre[1]),
        lessThan(MapCityGeography.coreKm),
      );
      expect(plan.target.longitude, greaterThan(54), reason: 'not 34.09');
    });

    test('9. it cannot affect category, price, rent/sale or Clear framing', () {
      final hosted = _hostedShaped();
      final withBad = _loaded(hosted);
      final without = _loaded(_withoutBad(hosted));

      void same(String choice, void Function(MapFilterController c) apply) {
        apply(withBad);
        apply(without);
        final a = _plan(MapCameraCause.filterChanged, withBad);
        final b = _plan(MapCameraCause.filterChanged, without);
        _expectSamePlan(a, b, reason: choice);
        expect(a, isNotNull, reason: '$choice frames the places');
        expect(a!.target.zoom, greaterThan(9),
            reason: '$choice: the UAE, not a continent');
      }

      same('all places', (c) {});
      same('category: Offers', (c) => c.setEntityType(LocationFilter.offers));
      same('price: lowest', (c) => c.setPriceMode(MapPriceMode.lowest));
      same('price: highest', (c) => c.setPriceMode(MapPriceMode.highest));
      same('rent', (c) => c.setTransaction(MapTransaction.rent));
      same('Clear', (c) {
        c.setEntityType(LocationFilter.owners);
        c.clear();
      });
    });

    test('9. a place that bypassed the mapper still cannot frame the camera',
        () {
      final good = MapLocationMapper.offers(_withoutBad(_hostedShaped()));
      const bypass = CachedLocationData(
        id: 'bypass',
        title: '',
        address: '',
        latitude: _badLat,
        longitude: _badLng,
        type: LocationFilter.offers,
        city: 'Umm Al Quwain',
      );
      final withBypass = MapFilterController()..setRecords([...good, bypass]);
      final without = MapFilterController()..setRecords(good);
      for (final cause in [
        MapCameraCause.filterChanged,
        MapCameraCause.cityChanged,
      ]) {
        _expectSamePlan(
          _plan(cause, withBypass),
          _plan(cause, without),
          reason: cause.name,
        );
      }
      // Only that place matches Umm Al Quwain: the camera goes to the city.
      withBypass.setCity('Umm Al Quwain');
      final plan = _plan(MapCameraCause.cityChanged, withBypass)!;
      expect(plan.subject, MapCameraSubject.city);
      expect(plan.target.longitude, greaterThan(54));
    });

    test(
        '10. it cannot affect Nearby, and a device abroad still has a position',
        () async {
      final hosted = _hostedShaped();
      final withBad = _loaded(hosted);
      final without = _loaded(_withoutBad(hosted));
      const ajman = _Locator(NearbyLocated(25.4052, 55.5136));
      for (final km in [5, 10, 25]) {
        await withBad.enableNearby(ajman, radiusKm: km);
        await without.enableNearby(ajman, radiusKm: km);
        expect(
          withBad.visible.map((p) => p.id).toList(),
          without.visible.map((p) => p.id).toList(),
          reason: '$km km',
        );
      }
      expect(withBad.visible.map((p) => p.id),
          isNot(contains('bad-umm-al-quwain')));

      // A phone at the bad pin itself (someone travelling): its position is
      // still a position, Nearby turns on, and there is simply nothing near it.
      expect(MapLocationMapper.isUsableCoordinate(_badLat, _badLng), isTrue);
      final abroad = _loaded(hosted);
      final fix = await abroad.enableNearby(
        const _Locator(NearbyLocated(_badLat, _badLng)),
        radiusKm: 25,
      );
      expect(fix, isA<NearbyLocated>());
      expect(abroad.state.nearbyEnabled, isTrue);
      expect(abroad.visible, isEmpty);
    });

    test('11. valid records are unchanged: still places, same city and flag',
        () {
      // Every valid pin is a place exactly when the older rule said so.
      for (var lat = 22.0; lat <= 26.6; lat += 0.2) {
        for (var lng = 50.5; lng <= 57.0; lng += 0.25) {
          expect(
            MapLocationMapper.isMapLocation(lat, lng),
            MapLocationMapper.isUsableCoordinate(lat, lng),
            reason: '$lat, $lng',
          );
        }
      }
      // The generic coordinate rule itself is not touched.
      expect(MapLocationMapper.isUsableCoordinate(25.2, 55.3), isTrue);
      expect(MapLocationMapper.isUsableCoordinate(0, 0), isFalse);
      expect(MapLocationMapper.isUsableCoordinate(91, 55), isFalse);
      expect(MapLocationMapper.isUsableCoordinate(25, -181), isFalse);
      expect(MapLocationMapper.isUsableCoordinate(null, 55), isFalse);
      expect(MapLocationMapper.isUsableCoordinate(25, double.nan), isFalse);

      // Every city, west and east: a place, at its pin, in its own city.
      final offers = [
        for (final entry in _cities.entries)
          _offer('c-${entry.key}', entry.key, entry.value[0], entry.value[1]),
        for (final entry in _west.entries)
          _offer('w-${entry.key}', 'Abu Dhabi', entry.value[0], entry.value[1]),
        for (final entry in _east.entries)
          _offer('e-${entry.key}', 'Fujairah', entry.value[0], entry.value[1]),
      ];
      final places = MapLocationMapper.offers(offers);
      expect(places, hasLength(offers.length));
      for (var i = 0; i < places.length; i++) {
        expect(places[i].id, offers[i].id);
        expect(places[i].latitude, offers[i].pickUpLatitude);
        expect(places[i].longitude, offers[i].pickUpLongitude);
        expect(places[i].city, offers[i].selectedCity);
      }
      for (final place in places.where((p) => p.id.startsWith('c-'))) {
        expect(place.cityConflict, isFalse, reason: place.id);
      }
      // The Correction 4 city/pin rule gives what it gave.
      final flags = {
        for (final p in MapLocationMapper.offers(_withoutBad(_hostedShaped())))
          p.id: p.cityConflict,
      };
      expect(flags, {
        'city-pin-abu-dhabi': true,
        'ajman-1': false,
        'ajman-2': false,
        'ajman-3': false,
        'ajman-4': false,
        'ajman-5': false,
        'city-pin-fujairah': true,
        'city-pin-sharjah': true,
      });
    });

    test('the city/pin rule and the generic coordinate rule are not touched',
        () {
      final geography = _source('lib/src/services/map_city_geography.dart');
      expect(geography.contains('UaeCoordinateSanity'), isFalse);
      expect(geography.contains('uae_coordinate_sanity'), isFalse);
      final mapper =
          _squash(_source('lib/src/services/map_location_data.dart'));
      expect(
        mapper.contains(
          'static bool isUsableCoordinate(double? lat, double? lng) { '
          'if (lat == null || lng == null) return false;',
        ),
        isTrue,
      );
      expect(
        mapper.contains(
          'isUsableCoordinate(lat, lng) && UaeCoordinateSanity.couldBeInUae(lat!, lng!)',
        ),
        isTrue,
      );
      // Four kinds of record, judged once each by the map's rule.
      expect(
        RegExp(r'if \(id == null \|\| !isMapLocation\(lat, lng\)\) continue;')
            .allMatches(mapper)
            .length,
        4,
      );
      expect(mapper.contains('!isUsableCoordinate(lat, lng)'), isFalse);
    });

    test('the device\'s own position is judged by the generic rule only', () {
      final vm = _squash(
        _source('lib/src/views/Screens/home/map/map_viewmodel.dart'),
      );
      expect(
        vm.contains(
          'if (!MapLocationMapper.isUsableCoordinate(fix.latitude, fix.longitude))',
        ),
        isTrue,
      );
      final controller = _squash(
        _source('lib/src/services/map_filter_controller.dart'),
      );
      expect(
        controller.contains(
          'if (!MapLocationMapper.isUsableCoordinate(fix.latitude, fix.longitude))',
        ),
        isTrue,
      );
      expect(vm.contains('UaeCoordinateSanity'), isFalse);
      expect(controller.contains('UaeCoordinateSanity'), isFalse);
      expect(
          _squash(_source('lib/src/services/map_filter.dart'))
              .contains('UaeCoordinateSanity'),
          isFalse);
    });

    test('the camera frames only places the map can show', () {
      final policy =
          _squash(_source('lib/src/services/map_camera_policy.dart'));
      expect(
        policy.contains(
            'if (MapLocationMapper.isMapLocation( place.latitude, place.longitude, ))'),
        isTrue,
      );
      expect(policy.contains('MapLocationMapper.isUsableCoordinate'), isFalse);
    });
  });

  group('a pin picked on the map, for any of the four forms', () {
    test('12. a position inside the UAE is accepted', () async {
      final all = <String, List<double>>{..._cities, ..._west, ..._east};
      for (final entry in all.entries) {
        final form = _FakeForm();
        final messages = <String>[];
        final accepted =
            await _pick(form, entry.value[0], entry.value[1], messages);
        expect(accepted, isTrue, reason: entry.key);
        expect(form.latitude, entry.value[0], reason: entry.key);
        expect(form.longitude, entry.value[1], reason: entry.key);
        expect(messages, isEmpty, reason: entry.key);
      }
    });

    test('13. a position outside the UAE is rejected, with one message',
        () async {
      for (final pos in <List<double>>[
        [_badLat, _badLng],
        [30.0444, 31.2357],
        [24.7136, 46.6753],
        [55.27, 25.2],
        [double.nan, 55.3],
      ]) {
        final form = _FakeForm();
        final messages = <String>[];
        final accepted = await _pick(form, pos[0], pos[1], messages);
        expect(accepted, isFalse, reason: '$pos');
        expect(form.latitude, isNull, reason: '$pos: nothing was taken');
        expect(form.longitude, isNull, reason: '$pos');
        expect(messages, ['outside the UAE'], reason: '$pos: one message');
      }
    });

    test('14. a rejection keeps the previous valid selection', () async {
      final form = _FakeForm();
      final messages = <String>[];
      expect(await _pick(form, 25.405, 55.514, messages), isTrue);
      expect([form.latitude, form.longitude], [25.405, 55.514]);

      expect(await _pick(form, _badLat, _badLng, messages), isFalse);
      expect([form.latitude, form.longitude], [25.405, 55.514],
          reason: 'the Ajman pin is still there');
      expect(await _pick(form, double.nan, 55.0, messages), isFalse);
      expect([form.latitude, form.longitude], [25.405, 55.514]);
      expect(messages, hasLength(2));

      // Choosing again works as before.
      expect(await _pick(form, 25.2048, 55.2708, messages), isTrue);
      expect([form.latitude, form.longitude], [25.2048, 55.2708]);
      expect(messages, hasLength(2));
    });

    test('the form is not even asked to take a rejected position', () async {
      var asked = 0;
      var told = 0;
      final accepted = await PickedLocationGate.admit(
        latitude: _badLat,
        longitude: _badLng,
        accept: () async {
          asked++;
        },
        reject: () => told++,
      );
      expect(accepted, isFalse);
      expect(asked, 0);
      expect(told, 1);
      final ok = await PickedLocationGate.admit(
        latitude: 25.2,
        longitude: 55.3,
        accept: () async {
          await Future<void>.delayed(Duration.zero);
          asked++;
        },
        reject: () => told++,
      );
      expect(ok, isTrue);
      expect(asked, 1, reason: 'admit waits for the form to take it');
      expect(told, 1);
    });

    test('the shared widget is the one boundary, used by all four forms', () {
      final widget =
          _source('lib/src/views/Widgets/pickup_location_widget.dart');
      final squashed = _squash(widget);
      expect(squashed.contains('PickedLocationGate.admit('), isTrue);
      expect(
          squashed.contains(
              'accept: () => vm.setSelectedLocation(selectedLocation, context),'),
          isTrue);
      expect(squashed.contains('reject: _showOutsideUae,'), isTrue);
      expect('vm.setSelectedLocation('.allMatches(widget).length, 1,
          reason: 'a picked position reaches a form only through the gate');
      final open =
          widget.substring(widget.indexOf('Future<void> _openMapPicker('));
      expect(
          open.indexOf(
              'if (selectedLocation == null || !context.mounted) return;'),
          lessThan(open.indexOf('PickedLocationGate.admit(')));

      for (final form in [
        'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
        'lib/src/views/Screens/ViewAdd/add_owners_view.dart',
        'lib/src/views/Screens/ViewAdd/add_offices_view.dart',
        'lib/src/views/Screens/ViewAdd/add_watchmen_view.dart',
      ]) {
        expect(_source(form).contains('PickUpInputWidget('), isTrue,
            reason: form);
      }
      // Nothing else opens the picker or hands a position to a form.
      final callers = <String>[];
      final setters = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        final path = entity.path.replaceAll('\\', '/');
        if (text.contains('MapPickerView(') &&
            !path.endsWith('widgets/map_picker_view.dart') &&
            !path.endsWith('Widgets/map_picker_view.dart')) {
          callers.add(path);
        }
        if (RegExp(r'\.setSelectedLocation\(').hasMatch(text))
          setters.add(path);
      }
      expect(callers, hasLength(1));
      expect(callers.single.endsWith('pickup_location_widget.dart'), isTrue);
      expect(setters, hasLength(1));
      expect(setters.single.endsWith('pickup_location_widget.dart'), isTrue);
    });

    test(
        'the message is a short toast, not a dialog, and the picker is not touched',
        () {
      final widget =
          _source('lib/src/views/Widgets/pickup_location_widget.dart');
      final toast = widget.substring(widget.indexOf('void _showOutsideUae()'));
      expect(toast.contains('Fluttertoast.showToast('), isTrue);
      expect(toast.contains("translate('pickupLocationOutsideUae')"), isTrue);
      expect(toast.contains('widget.localization'), isTrue,
          reason: 'no context is used after the picker returns');
      for (final blocking in [
        'showDialog(',
        'AlertDialog',
        'showModalBottomSheet(',
        'showGeneralDialog(',
      ]) {
        expect(widget.contains(blocking), isFalse, reason: blocking);
      }
      final picker = _source('lib/src/views/Widgets/map_picker_view.dart');
      expect(picker.contains('UaeCoordinateSanity'), isFalse);
      expect(picker.contains('PickedLocationGate'), isFalse);
    });

    test('15. the message exists in English and in Arabic', () {
      final en = (_arb('en')['pickupLocationOutsideUae'] as String?) ?? '';
      final ar = (_arb('ar')['pickupLocationOutsideUae'] as String?) ?? '';
      expect(en, 'Please choose a location inside the UAE.');
      expect(ar.trim(), isNotEmpty);
      expect(ar.contains('الإمارات'), isTrue);
      expect(RegExp(r'[a-zA-Z]').hasMatch(ar), isFalse,
          reason: 'the Arabic message has no English in it');
      for (final text in [en, ar]) {
        expect(text.contains('{'), isFalse, reason: 'no placeholders');
        expect(text.length, lessThan(80), reason: 'a short toast');
      }
    });
  });

  group('nothing hosted is touched, and a legacy record stays editable', () {
    test('16. the new and changed source never reads or writes the backend',
        () {
      final backend = RegExp(
        r'\.(insert|update|upsert|delete|rpc|from)\(|supabase|Supabase|'
        r'service_role|http|SharedPreferences|File\(|print\(|debugPrint\(',
      );
      for (final path in [
        'lib/src/common/data/uae_coordinate_sanity.dart',
        'lib/src/common/data/picked_location_gate.dart',
        'lib/src/services/map_location_data.dart',
        'lib/src/services/map_camera_policy.dart',
        'lib/src/views/Widgets/pickup_location_widget.dart',
      ]) {
        expect(backend.hasMatch(_source(path)), isFalse, reason: path);
      }
      // Pure files stay plain Dart.
      for (final path in [
        'lib/src/common/data/uae_coordinate_sanity.dart',
        'lib/src/common/data/picked_location_gate.dart',
      ]) {
        final text = _source(path);
        expect(text.contains('package:flutter'), isFalse, reason: path);
        expect(text.contains('google_maps_flutter'), isFalse, reason: path);
        expect(text.contains('geolocator'), isFalse, reason: path);
      }
    });

    test(
        'legacy: a record whose stored pin is outside the UAE can still be saved',
        () {
      final legacy = _offer('legacy', 'Umm Al Quwain', _badLat, _badLng);
      // The same payload an edit or a status change writes: it builds, and the
      // stored pin is carried over exactly.
      final payload = CoreEntityPayloadBuilder.forUpdate(
        CoreEntityPayloadBuilder.offer(legacy, id: 'legacy', ownerId: 'u1'),
      );
      expect(payload['pickup_latitude'], _badLat);
      expect(payload['pickup_longitude'], _badLng);
      expect(CoreEntityPayloadBuilder.coordinates(_badLat, _badLng),
          (_badLat, _badLng));
      // The persistence mapper keeps its own, unchanged, Earth-level rule.
      var refused = false;
      try {
        CoreEntityPayloadBuilder.coordinates(_badLat, 190);
      } on CoreEntityValidationException {
        refused = true;
      }
      expect(refused, isTrue, reason: 'longitude 190 is not on Earth');
    });

    test('legacy: neither the payload builder nor a service knows the UAE rule',
        () {
      for (final path in [
        'lib/src/services/core_entity_payload_builder.dart',
        'lib/src/services/supabase_core_entities_service.dart',
        'lib/src/services/ScreenServices/offer_service.dart',
        'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_offices_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_watchmen_viewmodel.dart',
      ]) {
        final text = _source(path);
        expect(text.contains('UaeCoordinateSanity'), isFalse, reason: path);
        expect(text.contains('PickedLocationGate'), isFalse, reason: path);
      }
    });
  });
}
