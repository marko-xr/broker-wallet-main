// A record's city and its pin are two separate fields, and nothing in the form
// or the database ties them together. This file pins what the Map does about it
// (and proves the other two suspects innocent):
//
//  * each canonical city has its own, unique, correct camera, and the matcher
//    never turns one city into another;
//  * a record whose city says one place while its pin is clearly in another is
//    not shown as a place of that city, and can never drag a city's camera to
//    its pin; it still shows with every city, and nothing is changed or hidden
//    in the data;
//  * choosing a city with no valid place goes to that city, for every city;
//  * a new Offer cannot be saved with its city and its pin in different cities.
//
// Plain Dart.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/data/uae_city_matcher.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_city_geography.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

// Independent reference centres of the nine cities (public coordinates), NOT
// read from the app: the app's table is checked against these.
const Map<String, List<double>> _reference = {
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

const MapViewport _phone = MapViewport(
  width: 360,
  height: 780,
  top: 156,
  bottom: 72,
  left: 16,
  right: 16,
);

// An Ajman pin, where the owner's test records are.
const double _ajmanLat = 25.405;
const double _ajmanLng = 55.514;

double _km(double lat1, double lng1, double lat2, double lng2) =>
    GeoDistance.meters(lat1, lng1, lat2, lng2) / 1000;

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Iterable<String> _labels(String city) {
  final key = UaeAreaCatalog.cityKey(city);
  return [
    for (final code in const ['en', 'ar'])
      if (_arb(code)[key] is String) _arb(code)[key] as String,
  ];
}

final UaeCityMatcher _matcher = UaeCityMatcher(labelsOf: _labels);
final MapVocabulary _vocabulary = MapVocabulary(cityLabels: _labels);
final DateTime _now = DateTime(2026, 10, 10);

OfferModel _offer(String id, String city, double lat, double lng,
        {String address = ''}) =>
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

WatchmenModel _watchman(
        String id, String buildingLocation, double lat, double lng) =>
    WatchmenModel(
      id: id,
      name: 'Omar',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: 'Tower A',
      notes: '',
      buildingLocation: buildingLocation,
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

OwnerModel _owner(String id, String propertyLocation, double lat, double lng) =>
    OwnerModel(
      id: id,
      userId: 'u1',
      name: 'Sara',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: propertyLocation,
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OfficeModel _office(String id, String officeLocation, double lat, double lng) =>
    OfficeModel(
      id: id,
      officeName: 'Palm Office',
      managerName: 'Ali',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: officeLocation,
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

MapCameraPlan? _cityPlan(MapFilterController controller) =>
    MapCameraPlanner.plan(
      cause: MapCameraCause.cityChanged,
      snapshot: controller.snapshot,
      viewport: _phone,
    );

/// The owner's data, as the hypothesis reads: three records, one per failing
/// city, every pin in Ajman.
List<CachedLocationData> _ownersThreeRecords() => [
      ...MapLocationMapper.offers([
        _offer('offer-abu-dhabi', 'Abu Dhabi', _ajmanLat, _ajmanLng),
        _offer('offer-dubai', 'Dubai', _ajmanLat + 0.001, _ajmanLng - 0.002),
      ], vocabulary: _vocabulary),
      ...MapLocationMapper.watchmen([
        _watchman(
            'watchman-fujairah', 'Fujairah', _ajmanLat - 0.001, _ajmanLng),
      ], vocabulary: _vocabulary),
    ];

void main() {
  group('each canonical city has its own camera, and only its own', () {
    for (final city in const [
      'Abu Dhabi',
      'Dubai',
      'Fujairah',
      'Ajman',
      'Sharjah'
    ]) {
      test('1-4. $city: its camera is its place, and no other city\'s', () {
        final frame = MapCityCameras.of(city)!;
        final ref = _reference[city]!;
        expect(
            _km(frame.latitude, frame.longitude, ref[0], ref[1]), lessThan(0.5),
            reason: '$city is where $city is');
        for (final other in _reference.entries.where((e) => e.key != city)) {
          expect(
            _km(frame.latitude, frame.longitude, other.value[0],
                other.value[1]),
            greaterThan(10),
            reason: '$city\'s camera must not be near ${other.key}',
          );
        }
        expect(frame.zoom, inInclusiveRange(9, 13));
      });
    }

    test('5. every supported city has exactly one entry, unique and in the UAE',
        () {
      expect(MapCityCameras.cities.toList()..sort(),
          UaeAreaCatalog.supportedCities.toList()..sort());
      expect(MapCityCameras.cities.toSet(), hasLength(9),
          reason: 'no duplicate');
      final seen = <String>{};
      for (final city in UaeAreaCatalog.supportedCities) {
        final frame = MapCityCameras.of(city)!;
        // Not swapped: the UAE is about 22-27 N and 51-57 E.
        expect(frame.latitude, inInclusiveRange(22, 27),
            reason: '$city latitude');
        expect(frame.longitude, inInclusiveRange(51, 57),
            reason: '$city longitude');
        expect(seen.add('${frame.latitude},${frame.longitude}'), isTrue,
            reason: '$city copies another city\'s coordinates');
      }
      // No two are closer than the real distance between neighbouring cities.
      final cities = UaeAreaCatalog.supportedCities.toList();
      for (var i = 0; i < cities.length; i++) {
        for (var j = i + 1; j < cities.length; j++) {
          final a = MapCityCameras.of(cities[i])!;
          final b = MapCityCameras.of(cities[j])!;
          expect(_km(a.latitude, a.longitude, b.latitude, b.longitude),
              greaterThan(10),
              reason: '${cities[i]} and ${cities[j]} are different places');
        }
      }
    });

    test('every camera entry equals the independent reference table', () {
      expect(_reference.keys.toSet(), UaeAreaCatalog.supportedCities.toSet());
      for (final entry in _reference.entries) {
        final frame = MapCityCameras.of(entry.key)!;
        expect(frame.latitude, closeTo(entry.value[0], 0.005),
            reason: entry.key);
        expect(frame.longitude, closeTo(entry.value[1], 0.005),
            reason: entry.key);
      }
    });

    test('a camera is found by the canonical name only: no alias, no fallback',
        () {
      for (final alias in [
        'abu dhabi',
        'ABU DHABI',
        'AbuDhabi',
        'abuDhabi',
        'Abu-Dhabi',
        'Dubai ',
        ' Dubai',
        'dubai',
        'Fujairah ',
        'fujairah',
        'Ajman,',
        '',
        'UAE',
      ]) {
        expect(MapCityCameras.of(alias), isNull, reason: '"$alias"');
      }
    });

    test('a city\'s own camera centre is where choosing it with no place goes',
        () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final controller = MapFilterController()
          ..setRecords([
            CachedLocationData(
              id: 'x',
              title: 'x',
              address: '',
              latitude: 1,
              longitude: 1,
              type: LocationFilter.offers,
              city: 'Nowhere',
            ),
          ])
          ..setCity(city);
        final plan = _cityPlan(controller)!;
        final ref = _reference[city]!;
        expect(plan.subject, MapCameraSubject.city, reason: city);
        // Within the insets' shift of the city's own centre (a few km).
        expect(_km(plan.target.latitude, plan.target.longitude, ref[0], ref[1]),
            lessThan(8),
            reason: city);
        for (final other in _reference.entries.where((e) => e.key != city)) {
          expect(
            _km(plan.target.latitude, plan.target.longitude, other.value[0],
                other.value[1]),
            greaterThan(
              _km(plan.target.latitude, plan.target.longitude, ref[0], ref[1]),
            ),
            reason: '$city: the camera is nearer $city than ${other.key}',
          );
        }
      }
    });
  });

  group('the matcher never turns one city into another', () {
    test('every spelling of a city is that city, and no other', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final spellings = <String>{
          city,
          city.toUpperCase(),
          city.toLowerCase(),
          UaeAreaCatalog.cityKey(city),
          city.replaceAll(' ', ''),
          city.replaceAll(' ', '-'),
          ..._labels(city),
        };
        for (final spelling in spellings) {
          expect(_matcher.canonical(spelling), city, reason: '"$spelling"');
          expect(_matcher.cityIn(spelling), city,
              reason: '"$spelling" in text');
        }
      }
    });

    test('7-10. Abu Dhabi, Dubai and Fujairah are never Ajman, nor Ajman them',
        () {
      for (final name in [
        'Abu Dhabi',
        'AbuDhabi',
        'Abu-Dhabi',
        'Dubai',
        'Fujairah'
      ]) {
        expect(_matcher.canonical(name), isNot('Ajman'), reason: name);
        expect(_matcher.cityIn(name), isNot('Ajman'), reason: name);
        expect(_matcher.cityIn('Al Jurf, $name'), isNot('Ajman'), reason: name);
      }
      for (final name in ['Ajman', 'ajman', 'عجمان']) {
        for (final other in ['Abu Dhabi', 'Dubai', 'Fujairah']) {
          expect(_matcher.canonical(name), isNot(other), reason: name);
          expect(_matcher.cityIn('Al Jurf, $name'), isNot(other), reason: name);
        }
      }
    });

    test('no pair of cities is confused, by name or by text', () {
      final cities = UaeAreaCatalog.supportedCities.toList();
      for (final a in cities) {
        for (final b in cities.where((b) => b != a)) {
          expect(_matcher.canonical(a), isNot(b), reason: '$a read as $b');
          // A text that names only a is never b.
          expect(_matcher.cityIn('Villa 5, $a, United Arab Emirates'), a,
              reason: '$a');
          expect(_matcher.cityIn('Villa 5, $a'), isNot(b),
              reason: '$a read as $b');
        }
      }
    });

    test('no partial or substring match, no fallback to anything', () {
      for (final text in [
        'Abu',
        'Dub',
        'Fuj',
        'Ajm',
        'Dubailand',
        'Dubaian Tower',
        'Abudhabian',
        'Fujairahs',
        'Ajmanian',
        'Ain',
        'Sharj',
        'Somewhere nice',
        '',
        ' , ',
        'United Arab Emirates',
      ]) {
        expect(_matcher.cityIn(text), isNull, reason: '"$text"');
        expect(_matcher.canonical(text), isNull, reason: '"$text"');
      }
    });

    test(
        'a record with no usable city has no city: not the first one, not the '
        'last one', () {
      final places = MapLocationMapper.offers([
        _offer('a', 'Atlantis', _ajmanLat, _ajmanLng),
        _offer('b', '', _ajmanLat, _ajmanLng),
        _offer('c', 'Ajman', _ajmanLat, _ajmanLng),
      ], vocabulary: _vocabulary);
      expect(places.map((p) => p.city), [null, null, 'Ajman']);
    });
  });

  group('choosing a city never goes to a place that is not in it', () {
    test(
        '6-8. Abu Dhabi, Dubai and Fujairah with only Ajman pins: that city, '
        'not Ajman', () {
      for (final city in ['Abu Dhabi', 'Dubai', 'Fujairah']) {
        final controller = MapFilterController()
          ..setRecords(_ownersThreeRecords())
          ..setCity(city);
        final plan = _cityPlan(controller)!;
        final ref = _reference[city]!;

        expect(controller.visible, isEmpty, reason: '$city has no valid place');
        expect(controller.hasNoMatches, isTrue,
            reason: '$city: the ordinary "no matches", not a failure');
        expect(plan.subject, MapCameraSubject.city, reason: city);
        final toCity =
            _km(plan.target.latitude, plan.target.longitude, ref[0], ref[1]);
        final toAjman = _km(
          plan.target.latitude,
          plan.target.longitude,
          _ajmanLat,
          _ajmanLng,
        );
        expect(toCity, lessThan(8), reason: city);
        expect(toCity, lessThan(toAjman), reason: '$city is not Ajman');
        expect(plan.target.zoom, lessThan(13),
            reason: 'not a street-level jump');
        // The Ajman pin is not what the camera shows.
        final at = UaeMapFraming.project(
          plan.target,
          _phone,
          _ajmanLat,
          _ajmanLng,
        );
        final inFrame = at.x >= _phone.left &&
            at.x <= _phone.width - _phone.right &&
            at.y >= _phone.top &&
            at.y <= _phone.height - _phone.bottom;
        expect(inFrame, isFalse, reason: '$city: the Ajman pin is not in view');
      }
    });

    test('9. a city with no valid place goes to that city, for every city', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final controller = MapFilterController()
          ..setRecords(
            MapLocationMapper.offers([
              // Every other city's record, pinned in Ajman.
              for (final other
                  in UaeAreaCatalog.supportedCities.where((c) => c != city))
                _offer('o-$other', other, _ajmanLat, _ajmanLng),
            ], vocabulary: _vocabulary),
          )
          ..setCity(city);
        final plan = _cityPlan(controller)!;
        expect(plan.subject, MapCameraSubject.city, reason: city);
        final ref = _reference[city]!;
        expect(_km(plan.target.latitude, plan.target.longitude, ref[0], ref[1]),
            lessThan(8),
            reason: city);
      }
    });

    test('11. a place the camera went to before cannot pull the next city', () {
      final controller = MapFilterController()
        ..setRecords([
          ...MapLocationMapper.offers([
            _offer('ajman-real', 'Ajman', _ajmanLat, _ajmanLng),
          ], vocabulary: _vocabulary),
          ..._ownersThreeRecords(),
        ]);

      controller.setCity('Ajman');
      final first = _cityPlan(controller)!;
      expect(first.subject, MapCameraSubject.matchingPlaces);
      expect(
          _km(first.target.latitude, first.target.longitude, _ajmanLat,
              _ajmanLng),
          lessThan(1));

      // The next city has no valid place: the Ajman place, which was just
      // framed, is nowhere in what the camera now shows.
      controller.setCity('Abu Dhabi');
      final second = _cityPlan(controller)!;
      expect(second.subject, MapCameraSubject.city);
      expect(
          _km(second.target.latitude, second.target.longitude, _ajmanLat,
              _ajmanLng),
          greaterThan(100));
    });

    test('a real place of the city is framed; a stray one is not', () {
      final controller = MapFilterController()
        ..setRecords([
          ...MapLocationMapper.offers([
            _offer('real', 'Abu Dhabi', 24.4539, 54.3773),
            _offer('stray', 'Abu Dhabi', _ajmanLat, _ajmanLng),
          ], vocabulary: _vocabulary),
        ])
        ..setCity('Abu Dhabi');
      expect(controller.visible.map((p) => p.id), ['real']);
      final plan = _cityPlan(controller)!;
      expect(plan.subject, MapCameraSubject.matchingPlaces);
      expect(_km(plan.target.latitude, plan.target.longitude, 24.4539, 54.3773),
          lessThan(1));
    });
  });

  group('a city that disagrees with its pin is not shown as that city', () {
    test(
        '12. each of the owner\'s three records is flagged, and shown with '
        'every city only', () {
      final places = _ownersThreeRecords();
      expect(places, hasLength(3));
      for (final place in places) {
        expect(place.cityConflict, isTrue, reason: place.id);
      }
      // Their city is what they say, unchanged: nothing was rewritten.
      expect(places.map((p) => p.city), ['Abu Dhabi', 'Dubai', 'Fujairah']);

      final controller = MapFilterController()..setRecords(places);
      expect(controller.visible, hasLength(3), reason: 'all cities: all shown');
      for (final city in UaeAreaCatalog.supportedCities) {
        controller.setCity(city);
        expect(controller.visible, isEmpty, reason: city);
      }
      controller.setCity(null);
      expect(controller.visible, hasLength(3));
    });

    test('12. the record is not attributed to the city its pin is in either',
        () {
      final controller = MapFilterController()
        ..setRecords(_ownersThreeRecords())
        ..setCity('Ajman');
      expect(controller.visible, isEmpty,
          reason: 'its city says Dubai: it is not an Ajman record');
    });

    test('12. Clear brings them back with every other place', () {
      final controller = MapFilterController()
        ..setRecords(_ownersThreeRecords())
        ..setCity('Dubai');
      expect(controller.visible, isEmpty);
      controller.clear();
      expect(controller.visible, hasLength(3));
    });

    test('13. a record whose pin is where its city says is shown normally', () {
      final places = MapLocationMapper.offers([
        for (final city in UaeAreaCatalog.supportedCities)
          _offer('ok-$city', city, _reference[city]![0], _reference[city]![1]),
      ], vocabulary: _vocabulary);
      for (final place in places) {
        expect(place.cityConflict, isFalse, reason: place.id);
      }
      final controller = MapFilterController()..setRecords(places);
      for (final city in UaeAreaCatalog.supportedCities) {
        controller.setCity(city);
        expect(controller.visible.map((p) => p.id), ['ok-$city'], reason: city);
        final plan = _cityPlan(controller)!;
        expect(plan.subject, MapCameraSubject.matchingPlaces, reason: city);
      }
    });

    test(
        '13. a record with a city and a pin in a nearby or remote place is '
        'shown normally', () {
      final places = MapLocationMapper.offers([
        _offer('mirdif', 'Dubai', 25.2194, 55.4167),
        _offer('marina', 'Dubai', 25.0805, 55.1403),
        _offer('jebel-ali', 'Dubai', 25.0, 55.06),
        _offer('hatta', 'Dubai', 24.80, 56.12),
        _offer('yas', 'Abu Dhabi', 24.49, 54.60),
        _offer('ruwais', 'Abu Dhabi', 24.11, 52.73),
        _offer('al-ain-as-abu-dhabi', 'Abu Dhabi', 24.2075, 55.7447),
        _offer('khor-fakkan-as-sharjah', 'Sharjah', 25.3395, 56.3563),
        _offer('dibba', 'Fujairah', 25.59, 56.26),
      ], vocabulary: _vocabulary);
      for (final place in places) {
        expect(place.cityConflict, isFalse, reason: place.id);
      }
    });

    test(
        'a record with no city, or a city the app does not list, is not '
        'judged', () {
      final places = MapLocationMapper.offers([
        _offer('none', '', _ajmanLat, _ajmanLng),
        _offer('other', 'Atlantis', _ajmanLat, _ajmanLng),
      ], vocabulary: _vocabulary);
      for (final place in places) {
        expect(place.cityConflict, isFalse, reason: place.id);
      }
    });

    test('an Owner and an Office are judged by their pin like an Offer is', () {
      final places = [
        ...MapLocationMapper.owners([
          _owner('owner-clash', 'Dubai', _ajmanLat, _ajmanLng),
          _owner('owner-ok', 'Ajman', _ajmanLat, _ajmanLng),
        ], vocabulary: _vocabulary),
        ...MapLocationMapper.offices([
          _office('office-clash', 'Abu Dhabi', _ajmanLat, _ajmanLng),
          _office('office-ok', 'Ajman', _ajmanLat, _ajmanLng),
        ], vocabulary: _vocabulary),
      ];
      expect(places.map((p) => p.id),
          ['owner-clash', 'owner-ok', 'office-clash', 'office-ok']);
      expect(
          places.map((p) => p.city), ['Dubai', 'Ajman', 'Abu Dhabi', 'Ajman']);
      expect(places.map((p) => p.cityConflict), [true, false, true, false]);
    });

    test('14. showing them safely changes nothing in the data', () {
      final offer = _offer('o', 'Dubai', _ajmanLat, _ajmanLng);
      final watchman = _watchman('w', 'Fujairah', _ajmanLat, _ajmanLng);
      MapLocationMapper.offers([offer], vocabulary: _vocabulary);
      MapLocationMapper.watchmen([watchman], vocabulary: _vocabulary);
      expect(offer.selectedCity, 'Dubai');
      expect(offer.pickUpLatitude, _ajmanLat);
      expect(offer.pickUpLongitude, _ajmanLng);
      expect(watchman.buildingLocation, 'Fujairah');
    });

    test('14. the Map writes nothing to the backend, to display this safely',
        () {
      final mapFiles = [
        'lib/src/services/map_location_source.dart',
        'lib/src/services/map_places_loader.dart',
        'lib/src/services/map_data_cache_service.dart',
        'lib/src/services/map_filter.dart',
        'lib/src/services/map_filter_controller.dart',
        'lib/src/services/map_location_data.dart',
        'lib/src/services/map_city_geography.dart',
        'lib/src/services/map_camera_policy.dart',
        'lib/src/views/Screens/home/map/map_viewmodel.dart',
        'lib/src/views/Screens/home/map/map_view.dart',
      ];
      final writes = RegExp(
        r'\.(insert|update|upsert|delete)\(|\.rpc\(|service_role|saveOffer|updateOffer|deleteOffer',
      );
      for (final path in mapFiles) {
        expect(writes.hasMatch(_source(path)), isFalse, reason: path);
      }
    });
  });

  group(
      'the rule: a pin is in conflict only when it is clearly in another city',
      () {
    // [city, latitude, longitude, conflict?, where]
    final cases = <List<Object>>[
      // The owner's case: pins in Ajman.
      ['Abu Dhabi', 25.4052, 55.5136, true, 'Ajman centre'],
      ['Dubai', 25.4052, 55.5136, true, 'Ajman centre'],
      ['Fujairah', 25.4052, 55.5136, true, 'Ajman centre'],
      ['Ras Al Khaimah', 25.4052, 55.5136, true, 'Ajman centre'],
      // Dubai's own neighbourhoods, including the ones nearest Sharjah.
      ['Dubai', 25.2194, 55.4167, false, 'Mirdif'],
      ['Dubai', 25.2845, 55.3772, false, 'Al Qusais'],
      ['Dubai', 25.2933, 55.3678, false, 'Al Nahda (Dubai)'],
      ['Dubai', 25.0805, 55.1403, false, 'Dubai Marina'],
      ['Dubai', 25.0, 55.06, false, 'Jebel Ali'],
      ['Dubai', 24.80, 56.12, false, 'Hatta'],
      // Clearly Sharjah, labelled Dubai.
      ['Dubai', 25.3463, 55.4209, true, 'Sharjah centre'],
      ['Dubai', 25.29, 55.47, true, 'Muwaileh, Sharjah'],
      // Neighbours whose centres are 11 km apart overlap: not judged.
      ['Sharjah', 25.4052, 55.5136, false, 'Ajman centre, as Sharjah'],
      ['Ajman', 25.3463, 55.4209, false, 'Sharjah centre, as Ajman'],
      // Remote parts of a big emirate are never in conflict.
      ['Abu Dhabi', 24.49, 54.60, false, 'Yas Island'],
      ['Abu Dhabi', 24.11, 52.73, false, 'Ruwais'],
      // A city inside the emirate may be listed as the emirate.
      ['Abu Dhabi', 24.2075, 55.7447, false, 'Al Ain, as Abu Dhabi'],
      ['Sharjah', 25.3395, 56.3563, false, 'Khor Fakkan, as Sharjah'],
      // ...but not the other way round, and not across emirates.
      ['Al Ain', 24.4539, 54.3773, true, 'Abu Dhabi centre, as Al Ain'],
      ['Khor Fakkan', 25.3463, 55.4209, true, 'Sharjah centre, as Khor Fakkan'],
      ['Fujairah', 25.3395, 56.3563, true, 'Khor Fakkan centre, as Fujairah'],
      ['Fujairah', 25.59, 56.26, false, 'Dibba'],
      ['Umm Al Quwain', 25.4052, 55.5136, true, 'Ajman centre, as UAQ'],
      ['Ras Al Khaimah', 25.5647, 55.5552, true, 'UAQ centre, as RAK'],
    ];

    for (final c in cases) {
      test(
          '${c[0]} with a pin at ${c[4]}: '
          '${c[3] == true ? 'conflict' : 'no conflict'}', () {
        final city = c[0] as String;
        final lat = c[1] as double;
        final lng = c[2] as double;
        expect(MapCityGeography.conflicts(city, lat, lng), c[3], reason: '$c');
        expect(MapCityGeography.otherCityAt(city, lat, lng) != null, c[3]);
      });
    }

    test('the other city is named, and is the nearest one holding the pin', () {
      expect(MapCityGeography.otherCityAt('Dubai', 25.4052, 55.5136), 'Ajman');
      expect(MapCityGeography.otherCityAt('Abu Dhabi', 25.3463, 55.4209),
          'Sharjah');
      expect(MapCityGeography.otherCityAt('Fujairah', 25.3395, 56.3563),
          'Khor Fakkan');
    });

    test('a city the app does not list, or no city, is never judged', () {
      expect(MapCityGeography.conflicts(null, 25.4, 55.5), isFalse);
      expect(MapCityGeography.conflicts('Atlantis', 25.4, 55.5), isFalse);
      expect(MapCityGeography.otherCityAt('', 25.4, 55.5), isNull);
    });

    test('a pin in its own city\'s core is never in conflict, at its centre',
        () {
      for (final entry in _reference.entries) {
        expect(
          MapCityGeography.conflicts(entry.key, entry.value[0], entry.value[1]),
          isFalse,
          reason: entry.key,
        );
      }
    });

    test(
        'a pin in another city\'s centre is in conflict with every city '
        'that is not near it or its emirate', () {
      for (final pin in _reference.entries) {
        for (final city in _reference.keys.where((c) => c != pin.key)) {
          final own = MapCityCameras.of(city)!;
          final far =
              _km(own.latitude, own.longitude, pin.value[0], pin.value[1]) >
                  MapCityGeography.coreKm;
          final nested = UaeCityMatcher.withinEmirateOf[pin.key] == city;
          expect(
            MapCityGeography.conflicts(city, pin.value[0], pin.value[1]),
            far && !nested,
            reason: '${pin.key} pin, labelled $city',
          );
        }
      }
    });

    test('the core is smaller than the distance between non-adjacent cities',
        () {
      // Sharjah and Ajman are 11 km apart (their cores overlap, which is not
      // judged); the next closest pair is further than a core's width.
      final a = MapCityCameras.of('Sharjah')!;
      final b = MapCityCameras.of('Ajman')!;
      expect(_km(a.latitude, a.longitude, b.latitude, b.longitude),
          lessThan(MapCityGeography.coreKm));
      expect(MapCityGeography.coreKm, 15);
    });
  });

  group('a new Offer cannot be saved with its city and pin in different cities',
      () {
    const vm = 'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart';

    test(
        'the Offer form judges the pin with the Map\'s own rule, before saving',
        () {
      final text = _source(vm);
      expect(
          text.contains(
              "import 'package:broker_wallet/src/services/map_city_geography.dart';"),
          isTrue);
      expect(
          text.contains('MapCityGeography.otherCityAt(selectedCity, lat, lng)'),
          isTrue);
      final save = text.substring(
        text.indexOf('Future<void> save(BuildContext context)'),
        text.indexOf('/// Handle edit mode with proper media merging'),
      );
      final validate = save.indexOf('_validateData()');
      final check = save.indexOf('_cityOfConflictingPin()');
      final upload = save.indexOf('_saveWithUploadQueue');
      final add = save.indexOf('_handleAddMode');
      final edit = save.indexOf('_handleEditMode');
      expect(validate, greaterThanOrEqualTo(0));
      expect(check, greaterThan(validate));
      // The check comes before anything is uploaded or saved, on every path.
      for (final later in [upload, add, edit]) {
        expect(later, greaterThan(check));
      }
      // It ends the save: it returns, in the person's language, not throws.
      final block = save.substring(check, upload);
      expect(block.contains('return;'), isTrue);
      expect(block.contains("translate('offerCityPinMismatch')"), isTrue);
      expect(block.contains('_showToast(_error!, Colors.red);'), isTrue);
    });

    test('it judges only a chosen city with a chosen pin', () {
      final text = _source(vm);
      expect(
        text.contains(
          'if (selectedCity.isEmpty || lat == null || lng == null) return null;',
        ),
        isTrue,
        reason: 'no city, or no pin: nothing to compare',
      );
    });

    test('the message names both cities, in English and in Arabic', () {
      for (final code in ['en', 'ar']) {
        final text = (_arb(code)['offerCityPinMismatch'] as String?) ?? '';
        expect(text.trim(), isNotEmpty, reason: code);
        expect(text.contains('{city}'), isTrue, reason: code);
        expect(text.contains('{pinCity}'), isTrue, reason: code);
        expect(text.length, lessThan(200), reason: '$code is concise');
      }
    });
  });
}
