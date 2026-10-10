// The map's smart filter, over the places already loaded: one category, Nearby,
// city, property type and rent/sale, all optional, all combined with AND, none
// of them reading from the backend. Plain Dart.

import 'dart:async';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_property_type_options.dart';
import 'package:broker_wallet/src/common/data/offer_property_types.dart';
import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

// The device is in Downtown Dubai. A degree of latitude is about 111.2 km, so
// these offsets are about 3.3, 5.0, 22.2 and 33.4 km away.
const double _homeLat = 25.2048;
const double _homeLng = 55.2708;

CachedLocationData _place(
  String id,
  LocationFilter type, {
  String? city,
  String? property,
  MapTransaction? transaction,
  double lat = _homeLat,
  double lng = _homeLng,
}) =>
    CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: lat,
      longitude: lng,
      type: type,
      city: city,
      propertyType: property,
      transaction: transaction,
    );

List<String> _ids(Iterable<CachedLocationData> places) => [
      for (final place in places) place.id,
    ];

/// A small, mixed set: two Offers (rent a villa in Dubai, sale of an apartment
/// in Abu Dhabi), an Owner with a villa in Dubai, an Office and a Watchman.
List<CachedLocationData> _sample() => [
      _place(
        'rent-villa',
        LocationFilter.offers,
        city: 'Dubai',
        property: 'villa',
        transaction: MapTransaction.rent,
      ),
      _place(
        'sale-apartment',
        LocationFilter.offers,
        city: 'Abu Dhabi',
        property: 'apartment',
        transaction: MapTransaction.sale,
      ),
      _place(
        'owner-villa',
        LocationFilter.owners,
        city: 'Dubai',
        property: 'villa',
      ),
      _place('office', LocationFilter.offices, city: 'Dubai'),
      _place('watchman', LocationFilter.watchmen),
    ];

class _FakeLocator implements NearbyLocator {
  _FakeLocator(this.fix);

  NearbyFix fix;
  Object? throwing;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<NearbyFix> locate() async {
    calls++;
    final waiting = gate;
    if (waiting != null) await waiting.future;
    final error = throwing;
    if (error != null) throw error;
    return fix;
  }
}

MapFilterController _loaded([List<CachedLocationData>? places]) =>
    MapFilterController()..setRecords(places ?? _sample());

void main() {
  group('the default shows everything', () {
    test('no filter set: every loaded place, in order', () {
      final controller = _loaded();
      expect(controller.state, MapFilterState.initial);
      expect(controller.filtersActive, isFalse);
      expect(_ids(controller.visible), _ids(_sample()));
    });

    test('the default state restricts nothing', () {
      const state = MapFilterState.initial;
      expect(state.entityType, LocationFilter.all);
      expect(state.nearbyEnabled, isFalse);
      expect(state.city, isNull);
      expect(state.propertyType, isNull);
      expect(state.transaction, isNull);
      expect(state.isActive, isFalse);
    });
  });

  group('the category selector', () {
    test('lists exactly the kinds the map shows, and no others', () {
      expect(MapEntityTypes.all, [
        LocationFilter.offers,
        LocationFilter.owners,
        LocationFilter.offices,
        LocationFilter.watchmen,
      ]);
      // The map's kinds plus "All" are every value of the enum: a kind added to
      // the map must be added to the selector, and this fails until it is.
      expect([
        LocationFilter.all,
        ...MapEntityTypes.all,
      ], LocationFilter.values);
    });

    test('choosing a kind shows only that kind', () {
      final controller = _loaded();
      for (final type in MapEntityTypes.all) {
        controller.setEntityType(type);
        expect(controller.visible.every((place) => place.type == type), isTrue);
        expect(controller.visible, isNotEmpty);
      }
      controller.setEntityType(LocationFilter.offers);
      expect(_ids(controller.visible), ['rent-villa', 'sale-apartment']);
    });

    test('choosing All again restores every kind', () {
      final controller = _loaded()..setEntityType(LocationFilter.owners);
      controller.setEntityType(LocationFilter.all);
      expect(controller.visible, hasLength(5));
    });

    test('counts per kind come from the loaded places', () {
      final counts = _loaded().entityCounts;
      expect(counts, {
        LocationFilter.offers: 2,
        LocationFilter.owners: 1,
        LocationFilter.offices: 1,
        LocationFilter.watchmen: 1,
      });
    });
  });

  group('city', () {
    test('shows only places in that city', () {
      final controller = _loaded()..setCity('Dubai');
      expect(_ids(controller.visible), ['rent-villa', 'owner-villa', 'office']);
    });

    test('a place with no known city does not pass a city filter', () {
      final controller = _loaded()..setCity('Dubai');
      expect(
        controller.visible.any((place) => place.id == 'watchman'),
        isFalse,
      );
    });

    test('options are every city of the catalog, in the catalog order', () {
      // Places in only three of the nine cities are loaded.
      final controller = _loaded([
        _place('a', LocationFilter.offers, city: 'Sharjah'),
        _place('b', LocationFilter.offers, city: 'Dubai'),
        _place('c', LocationFilter.owners, city: 'Abu Dhabi'),
        _place('d', LocationFilter.offices, city: 'Dubai'),
        _place('e', LocationFilter.watchmen),
      ]);
      expect(controller.cityOptions, UaeAreaCatalog.supportedCities);
      expect(MapFilterOptions.cities(), UaeAreaCatalog.supportedCities);
      expect(controller.cityOptions, hasLength(9));
      expect(controller.cityOptions.toSet(), hasLength(9));
    });

    test('the options do not depend on which places are loaded', () {
      final none = _loaded(const <CachedLocationData>[]);
      final one = _loaded([_place('a', LocationFilter.offers, city: 'Ajman')]);
      final several = _loaded();
      final unloaded = MapFilterController();
      for (final controller in [none, one, several, unloaded]) {
        expect(controller.cityOptions, UaeAreaCatalog.supportedCities);
      }
    });

    test('a refresh that brings other cities does not change the options', () {
      final controller = _loaded();
      final before = List<String>.of(controller.cityOptions);
      controller.setRecords([
        _place('x', LocationFilter.offers, city: 'Fujairah'),
      ]);
      expect(controller.cityOptions, before);
      controller.setRecords(const <CachedLocationData>[]);
      expect(controller.cityOptions, before);
    });

    test('the options are the catalog\'s cities, not a list of the map\'s own',
        () {
      expect(
        identical(MapFilterOptions.cities(), UaeAreaCatalog.supportedCities),
        isTrue,
        reason: 'one source: the forms\' catalog',
      );
    });

    test('a city with no places can be chosen, and shows no places', () {
      final controller = _loaded();
      expect(
        controller.cityOptions.contains('Al Ain'),
        isTrue,
        reason: 'nobody has a place in Al Ain, yet it is a choice',
      );
      expect(controller.setCity('Al Ain'), isTrue);
      expect(controller.state.city, 'Al Ain');
      expect(controller.visible, isEmpty);
    });

    test('every city of the catalog can be chosen, with or without places', () {
      final controller = _loaded();
      for (final city in controller.cityOptions) {
        expect(controller.setCity(city), isTrue, reason: city);
        expect(controller.state.city, city);
        expect(
          _ids(controller.visible),
          [
            for (final place in _sample())
              if (place.city == city) place.id,
          ],
          reason: city,
        );
        controller.setCity(null);
      }
    });

    test('a city with no places is "no matches", not a failed load', () {
      final controller = _loaded()..setCity('Khor Fakkan');
      expect(controller.visible, isEmpty);
      expect(controller.all, hasLength(5), reason: 'the data is all there');
      expect(controller.hasNoMatches, isTrue);
      controller.clear();
      expect(controller.hasNoMatches, isFalse);
      expect(controller.visible, hasLength(5));
    });
  });

  group('property type', () {
    test('shows only places of that type', () {
      final controller = _loaded()..setPropertyType('villa');
      expect(_ids(controller.visible), ['rent-villa', 'owner-villa']);
    });

    test('a place with no property type does not pass an active filter', () {
      final controller = _loaded()..setPropertyType('villa');
      for (final id in ['office', 'watchman']) {
        expect(
          controller.visible.any((place) => place.id == id),
          isFalse,
          reason: '$id has no property type',
        );
      }
      // An Owner or Offer of ANOTHER type does not pass either.
      expect(
        controller.visible.any((place) => place.id == 'sale-apartment'),
        isFalse,
      );
    });

    test('options use each layer\'s canonical vocabulary', () {
      final controller = _loaded()..setEntityType(LocationFilter.offers);
      expect(controller.propertyTypeOptions, OfferPropertyTypes.keys);
      expect(MapPropertyTypeOptions.forLayer(LocationFilter.offers),
          isNot(contains('residentialPlot')));
      controller.setEntityType(LocationFilter.owners);
      expect(controller.propertyTypeOptions,
          [for (final option in OwnerPropertyTypes.options) option.key]);
      expect(controller.propertyTypeOptions, isNot(contains('compound')));
      expect(MapPropertyTypeOptions.forLayer(LocationFilter.all), isEmpty);
    });
  });

  group('rent and sale', () {
    test('shows only that transaction', () {
      final controller = _loaded()..setTransaction(MapTransaction.rent);
      expect(_ids(controller.visible), ['rent-villa']);
      controller.setTransaction(MapTransaction.sale);
      expect(_ids(controller.visible), ['sale-apartment']);
    });

    test('a place with no transaction does not pass an active filter', () {
      final controller = _loaded()..setTransaction(MapTransaction.rent);
      for (final id in ['owner-villa', 'office', 'watchman']) {
        expect(
          controller.visible.any((place) => place.id == id),
          isFalse,
          reason: '$id has no rent or sale',
        );
      }
    });

    test('only the canonical stored values are a transaction', () {
      expect(MapTransaction.fromStored('rent'), MapTransaction.rent);
      expect(MapTransaction.fromStored(' Rent '), MapTransaction.rent);
      expect(MapTransaction.fromStored('sell'), MapTransaction.sale);
      expect(MapTransaction.fromStored('sale'), MapTransaction.sale);
      // Free text is never read for a transaction.
      expect(MapTransaction.fromStored('for rent'), isNull);
      expect(MapTransaction.fromStored('rent or sell'), isNull);
      expect(MapTransaction.fromStored('lease'), isNull);
      expect(MapTransaction.fromStored(''), isNull);
      expect(MapTransaction.fromStored(null), isNull);
    });
  });

  group('filters combine with AND', () {
    test('kind + city + type + transaction: only what matches all four', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setCity('Dubai')
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent);
      expect(_ids(controller.visible), ['rent-villa']);
    });

    test('dropping one condition widens the result, and only by that one', () {
      final controller = _loaded()
        ..setCity('Dubai')
        ..setPropertyType('villa');
      expect(_ids(controller.visible), ['rent-villa', 'owner-villa']);
      controller.setEntityType(LocationFilter.owners);
      expect(_ids(controller.visible), ['owner-villa']);
    });

    test('conditions that cannot all hold show nothing', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setCity('Abu Dhabi')
        ..setTransaction(MapTransaction.rent);
      expect(controller.visible, isEmpty);
    });

    test('an Office or Owner never passes merely for lacking the fields', () {
      final controller = _loaded()
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent);
      expect(_ids(controller.visible), ['rent-villa']);
    });
  });

  group('clearing', () {
    test('one call restores every place and the default state', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setCity('Dubai')
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent);
      expect(controller.filtersActive, isTrue);
      expect(controller.visible, hasLength(1));

      expect(controller.clear(), isTrue);
      expect(controller.state, MapFilterState.initial);
      expect(controller.filtersActive, isFalse);
      expect(_ids(controller.visible), _ids(_sample()));
    });

    test('clearing the default changes nothing', () {
      expect(_loaded().clear(), isFalse);
    });

    test('a setter reports whether anything changed', () {
      final controller = _loaded();
      expect(controller.setCity('Dubai'), isTrue);
      expect(controller.setCity('Dubai'), isFalse);
      expect(controller.setCity(null), isTrue);
    });
  });

  group('distance', () {
    test('the haversine distance is right', () {
      // A degree of latitude on a sphere of the mean Earth radius.
      expect(GeoDistance.meters(0, 0, 1, 0), closeTo(111195, 60));
      expect(GeoDistance.meters(0, 0, 0, 1), closeTo(111195, 60));
      // London to Paris is about 343.5 km.
      expect(
        GeoDistance.meters(51.5074, -0.1278, 48.8566, 2.3522),
        closeTo(343550, 1500),
      );
      // Dubai to Abu Dhabi is about 120-130 km as the crow flies.
      final dubaiAbuDhabi = GeoDistance.meters(
        25.2048,
        55.2708,
        24.4539,
        54.3773,
      );
      expect(dubaiAbuDhabi, inInclusiveRange(120000, 135000));
    });

    test('the distance to oneself is zero, and it is symmetric', () {
      expect(GeoDistance.meters(25.2, 55.3, 25.2, 55.3), 0);
      final there = GeoDistance.meters(25.2, 55.3, 24.4, 54.4);
      final back = GeoDistance.meters(24.4, 54.4, 25.2, 55.3);
      expect(there, closeTo(back, 1e-6));
    });

    test('opposite points are half the Earth\'s circumference apart', () {
      expect(
        GeoDistance.meters(0, 0, 0, 180),
        closeTo(3.141592653589793 * GeoDistance.earthRadiusMeters, 5),
      );
    });
  });

  group('nearby', () {
    List<CachedLocationData> ring() => [
          _place('near', LocationFilter.offers, lat: _homeLat + 0.03), // 3.3 km
          _place('edge', LocationFilter.offers, lat: _homeLat + 0.045), // 5.0
          _place('mid', LocationFilter.owners, lat: _homeLat + 0.2), // 22.2 km
          _place('far', LocationFilter.offices, lat: _homeLat + 0.3), // 33.4 km
        ];

    NearbyFilter at(int km) =>
        NearbyFilter(latitude: _homeLat, longitude: _homeLng, radiusKm: km);

    test('the radii on offer, and the default', () {
      expect(NearbyFilter.radiusOptionsKm, [5, 10, 25]);
      expect(NearbyFilter.defaultRadiusKm, 10);
    });

    test('includes what is inside the radius and excludes what is outside', () {
      final places = ring();
      List<String> within(int km) => _ids(
            MapFilterEngine.apply(
              places,
              const MapFilterState().withNearby(at(km)),
            ),
          );
      expect(within(5), ['near']);
      expect(within(10), ['near', 'edge']);
      expect(within(25), ['near', 'edge', 'mid']);
    });

    test(
      'enabling turns it on at the device\'s position, default 10 km',
      () async {
        final controller = _loaded(ring());
        final locator = _FakeLocator(const NearbyLocated(_homeLat, _homeLng));
        final fix = await controller.enableNearby(locator);
        expect(fix, isA<NearbyLocated>());
        expect(controller.state.nearbyEnabled, isTrue);
        expect(controller.state.nearby!.radiusKm, 10);
        expect(_ids(controller.visible), ['near', 'edge']);
      },
    );

    test(
      'changing the radius re-filters without asking for the position again',
      () async {
        final controller = _loaded(ring());
        final locator = _FakeLocator(const NearbyLocated(_homeLat, _homeLng));
        await controller.enableNearby(locator);
        expect(controller.setNearbyRadius(25), isTrue);
        expect(_ids(controller.visible), ['near', 'edge', 'mid']);
        expect(controller.setNearbyRadius(5), isTrue);
        expect(_ids(controller.visible), ['near']);
        expect(locator.calls, 1);
      },
    );

    test('the radius cannot be changed while Nearby is off', () {
      final controller = _loaded(ring());
      expect(controller.setNearbyRadius(25), isFalse);
      expect(controller.state.nearbyEnabled, isFalse);
    });

    test('it combines with the other filters', () async {
      final controller = _loaded(ring());
      await controller.enableNearby(
        _FakeLocator(const NearbyLocated(_homeLat, _homeLng)),
        radiusKm: 25,
      );
      controller.setEntityType(LocationFilter.owners);
      expect(_ids(controller.visible), ['mid']);
      controller.setEntityType(LocationFilter.offices);
      expect(controller.visible, isEmpty, reason: 'the Office is 33 km away');
    });

    test('a place without a usable position is excluded', () {
      final places = [
        _place('ok', LocationFilter.offers),
        _place('nan', LocationFilter.offers, lat: double.nan),
        _place('unset', LocationFilter.offers, lat: 0, lng: 0),
        _place('out', LocationFilter.offers, lat: 95),
      ];
      final visible = MapFilterEngine.apply(
        places,
        const MapFilterState().withNearby(at(25)),
      );
      expect(_ids(visible), ['ok']);
    });

    test(
        'a position outside the Earth is never near, whatever the arithmetic '
        'says', () {
      // Next to the pole the haversine of an impossible latitude (90.001) comes
      // out about a kilometre from a polar device: the check on the place's own
      // position, not the distance, is what keeps it out.
      final places = [
        _place('real', LocationFilter.offers, lat: 89.99, lng: 0),
        _place('beyond', LocationFilter.offers, lat: 90.001, lng: 0),
      ];
      final nearby = NearbyFilter(latitude: 89.99, longitude: 10, radiusKm: 25);
      expect(GeoDistance.meters(89.99, 10, 90.001, 0), lessThan(25000),
          reason: 'the numbers alone would call it near');
      final visible = MapFilterEngine.apply(
        places,
        const MapFilterState().withNearby(nearby),
      );
      expect(_ids(visible), ['real']);
    });

    test('turning it off restores what the other filters allow', () async {
      final controller = _loaded(ring());
      await controller.enableNearby(
        _FakeLocator(const NearbyLocated(_homeLat, _homeLng)),
      );
      expect(controller.visible, hasLength(2));
      expect(controller.disableNearby(), isTrue);
      expect(controller.visible, hasLength(4));
      expect(controller.state.nearbyEnabled, isFalse);
    });

    test('clearing turns it off', () async {
      final controller = _loaded(ring());
      await controller.enableNearby(
        _FakeLocator(const NearbyLocated(_homeLat, _homeLng)),
      );
      controller.clear();
      expect(controller.state.nearbyEnabled, isFalse);
      expect(controller.visible, hasLength(4));
    });
  });

  group('nearby when the position cannot be had', () {
    for (final entry in <String, NearbyFix>{
      'permission denied': const NearbyDenied(),
      'location services off': const NearbyServicesOff(),
      'no position available': const NearbyUnavailable(),
    }.entries) {
      test(
        '${entry.key}: Nearby stays off and every place stays visible',
        () async {
          final controller = _loaded();
          final fix = await controller.enableNearby(_FakeLocator(entry.value));
          expect(
            fix.runtimeType,
            entry.value.runtimeType,
            reason: 'the screen is told what happened',
          );
          expect(controller.state.nearbyEnabled, isFalse);
          expect(controller.filtersActive, isFalse);
          expect(_ids(controller.visible), _ids(_sample()));
        },
      );
    }

    test(
      'a platform failure is an unavailable position, not an exception',
      () async {
        final controller = _loaded();
        final locator = _FakeLocator(const NearbyDenied())
          ..throwing = StateError('platform exploded');
        final fix = await controller.enableNearby(locator);
        expect(fix, isA<NearbyUnavailable>());
        expect(controller.state.nearbyEnabled, isFalse);
        expect(controller.visible, hasLength(5));
      },
    );

    test('an impossible position is not used', () async {
      final controller = _loaded();
      for (final bad in [
        const NearbyLocated(double.nan, 55),
        const NearbyLocated(0, 0),
        const NearbyLocated(120, 55),
      ]) {
        final fix = await controller.enableNearby(_FakeLocator(bad));
        expect(fix, isA<NearbyUnavailable>());
        expect(controller.state.nearbyEnabled, isFalse);
      }
      expect(controller.visible, hasLength(5));
    });

    test('a failed attempt leaves earlier filters as they were', () async {
      final controller = _loaded()..setCity('Dubai');
      await controller.enableNearby(_FakeLocator(const NearbyDenied()));
      expect(controller.state.city, 'Dubai');
      expect(controller.visible, hasLength(3));
    });

    test(
      'an answer that arrives after the filter was cleared is ignored',
      () async {
        final controller = _loaded();
        final locator = _FakeLocator(const NearbyLocated(_homeLat, _homeLng))
          ..gate = Completer<void>();
        final pending = controller.enableNearby(locator);
        await pumpEventQueue();
        controller.clear(); // the person changed their mind
        locator.gate!.complete();
        await pending;
        expect(controller.state.nearbyEnabled, isFalse);
      },
    );

    test('asking twice: the latest answer wins', () async {
      final controller = _loaded();
      final first = _FakeLocator(const NearbyLocated(_homeLat, _homeLng))
        ..gate = Completer<void>();
      final second = _FakeLocator(const NearbyLocated(25.0, 55.0));
      final firstDone = controller.enableNearby(first, radiusKm: 5);
      await pumpEventQueue();
      await controller.enableNearby(second, radiusKm: 25);
      first.gate!.complete();
      await firstDone;
      expect(controller.state.nearby!.latitude, 25.0);
      expect(controller.state.nearby!.radiusKm, 25);
    });
  });

  group('the open card follows the filter', () {
    test('a place that stops matching closes the card', () {
      final controller = _loaded();
      controller.select('offers:rent-villa');
      expect(controller.selectedKey, 'offers:rent-villa');
      controller.setCity('Abu Dhabi');
      expect(controller.selectedKey, isNull);
    });

    test('a place that still matches keeps its card open', () {
      final controller = _loaded();
      controller.select('offers:rent-villa');
      controller.setCity('Dubai');
      controller.setPropertyType('villa');
      controller.setTransaction(MapTransaction.rent);
      expect(controller.selectedKey, 'offers:rent-villa');
    });

    test('clearing the filter does not reopen a closed card', () {
      final controller = _loaded();
      controller.select('offers:rent-villa');
      controller.setCity('Abu Dhabi');
      controller.clear();
      expect(controller.selectedKey, isNull);
    });

    test('a place that is not visible cannot be opened', () {
      final controller = _loaded()..setCity('Abu Dhabi');
      controller.select('offers:rent-villa');
      expect(controller.selectedKey, isNull);
      controller.select('offers:sale-apartment');
      expect(controller.selectedKey, 'offers:sale-apartment');
    });

    test('a refresh that removes the place closes its card', () {
      final controller = _loaded();
      controller.select('owners:owner-villa');
      controller.setRecords(
        _sample().where((place) => place.id != 'owner-villa').toList(),
      );
      expect(controller.selectedKey, isNull);
    });

    test('a refresh that keeps the place keeps its card, filter and all', () {
      final controller = _loaded()..setCity('Dubai');
      controller.select('offers:rent-villa');
      controller.setRecords([
        ..._sample(),
        _place('new', LocationFilter.offers),
      ]);
      expect(controller.selectedKey, 'offers:rent-villa');
      expect(controller.state.city, 'Dubai');
    });

    test('closing the card with null', () {
      final controller = _loaded();
      controller.select('offers:rent-villa');
      controller.select(null);
      expect(controller.selectedKey, isNull);
    });

    test('two kinds with the same id are two different places', () {
      final controller = _loaded([
        _place('same', LocationFilter.offers),
        _place('same', LocationFilter.owners),
      ]);
      controller.select('owners:same');
      controller.setEntityType(LocationFilter.offers);
      expect(controller.selectedKey, isNull);
    });
  });

  group('no matches is not a failure', () {
    test('data loaded and the filter shows none: "no matches"', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offices)
        ..setCity('Abu Dhabi');
      expect(controller.all, hasLength(5));
      expect(controller.visible, isEmpty);
      expect(controller.hasNoMatches, isTrue);
    });

    test('the loaded places are all still there, ready to be cleared', () {
      final controller = _loaded()..setCity('Ajman');
      expect(controller.hasNoMatches, isTrue);
      expect(controller.all, hasLength(5));
      controller.clear();
      expect(controller.hasNoMatches, isFalse);
      expect(controller.visible, hasLength(5));
    });

    test('nothing loaded at all is not "no matches"', () {
      final controller = MapFilterController();
      expect(controller.hasNoMatches, isFalse);
      controller.setCity('Dubai');
      expect(
        controller.hasNoMatches,
        isFalse,
        reason: 'there is nothing the filter removed',
      );
    });

    test(
      'a person with no places and no filter has no "no matches" either',
      () {
        expect(_loaded(const <CachedLocationData>[]).hasNoMatches, isFalse);
      },
    );
  });
}
