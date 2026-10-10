// The map's price ordering.
//
// Sort keeps every place, placing unpriced Offers last. Only an Offer has a price
// (its minimum, else its maximum, read from the text the forms store); an
// Owner, an Office or a Watchman has none and is never given one. A price that
// cannot be read is never taken for zero. It sorts what is already loaded: no
// backend is asked. Plain Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:broker_wallet/src/services/map_price.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

final DateTime _now = DateTime(2026, 10, 7);

OfferModel _offer(
  String id, {
  String min = '',
  String max = '',
  String city = 'Dubai',
  String type = 'rent',
}) =>
    OfferModel(
      id: id,
      userId: 'u1',
      offerType: type,
      selectedCity: city,
      selectedAreas: const <String>[],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: min,
      maxPrice: max,
      notes: '',
      specificPropertyType: 'Villa',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: 25.2,
      pickUpLongitude: 55.27,
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

/// A place with a ready price (as the mapper would have made it).
CachedLocationData _priced(
  String id,
  double? price, {
  LocationFilter type = LocationFilter.offers,
  String? city = 'Dubai',
  MapTransaction? transaction,
  double lat = 25.2048,
  double lng = 55.2708,
}) =>
    CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: lat,
      longitude: lng,
      type: type,
      city: city,
      transaction: transaction,
      price: price,
    );

List<String> _ids(Iterable<CachedLocationData> places) => [
      for (final place in places) place.id,
    ];

/// Offers at 900, 1000 and 25 (so text order and number order differ), an
/// Offer with no price, and one of each other kind.
List<CachedLocationData> _market() => [
      _priced('mid', 900, transaction: MapTransaction.rent),
      _priced('top', 1000, city: 'Abu Dhabi', transaction: MapTransaction.sale),
      _priced('cheap', 25, transaction: MapTransaction.rent),
      _priced('unpriced', null, transaction: MapTransaction.rent),
      _priced('owner', null, type: LocationFilter.owners),
      _priced('office', null, type: LocationFilter.offices),
      _priced('watchman', null, type: LocationFilter.watchmen, city: null),
    ];

MapFilterController _loaded([List<CachedLocationData>? places]) =>
    MapFilterController()..setRecords(places ?? _market());

class _Source implements MapLocationSource {
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
    return _market();
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
  group('reading a stored price', () {
    test('plain digits, thousands commas, whitespace and decimals', () {
      expect(MapPrice.parse('1500000'), 1500000.0);
      expect(MapPrice.parse('1,500,000'), 1500000.0);
      expect(MapPrice.parse('  1,500,000  '), 1500000.0);
      expect(MapPrice.parse('\t850\n'), 850.0);
      expect(MapPrice.parse('1500000.50'), 1500000.5);
      expect(MapPrice.parse('1,500,000.25'), 1500000.25);
      expect(MapPrice.parse('0.5'), 0.5);
      expect(MapPrice.parse('007'), 7.0);
      expect(MapPrice.parse('999999999999'), 999999999999.0);
    });

    test('empty, blank or missing is no price', () {
      for (final empty in [null, '', ' ', '\n', '   \t ']) {
        expect(MapPrice.parse(empty), isNull, reason: '"$empty"');
      }
    });

    test('malformed values are no price, and never zero', () {
      for (final bad in [
        'abc',
        'AED 500',
        '500 AED',
        '500k',
        '1.5M',
        'From 500',
        '500 - 900',
        '1,5',
        '1,50',
        '12,34,567',
        ',500',
        '500,',
        ',,,',
        '1.5.2',
        '.5',
        '5.',
        '1e6',
        '0x10',
        '١٢٣',
        'NaN',
        'Infinity',
        '-Infinity',
        '--5',
        '+500',
        '5 00',
      ]) {
        expect(MapPrice.parse(bad), isNull, reason: '"$bad"');
      }
    });

    test('zero and negative amounts are no price', () {
      for (final bad in ['0', '0.0', '0.00', '000', '-5', '-0.5', '-1,000']) {
        expect(MapPrice.parse(bad), isNull, reason: '"$bad"');
      }
    });

    test('a free-form display string is never parsed', () {
      // The map reads what the forms store, not what a card shows.
      for (final shown in [
        '1,000 - 2,000 AED',
        'From 1,000 AED',
        'Up to 2,000 AED',
        'AED 1,000',
      ]) {
        expect(MapPrice.parse(shown), isNull, reason: shown);
      }
    });
  });

  group('the price an Offer is ranked by', () {
    test('its minimum, when that is a usable price', () {
      expect(MapPrice.comparable(minPrice: '500', maxPrice: '900'), 500.0);
      expect(MapPrice.comparable(minPrice: '1,000', maxPrice: '800'), 1000.0);
      expect(MapPrice.comparable(minPrice: '500'), 500.0);
      expect(MapPrice.comparable(minPrice: '500', maxPrice: ''), 500.0);
      expect(MapPrice.comparable(minPrice: '500', maxPrice: 'abc'), 500.0);
    });

    test('otherwise its maximum', () {
      expect(MapPrice.comparable(minPrice: '', maxPrice: '900'), 900.0);
      expect(MapPrice.comparable(maxPrice: '900'), 900.0);
      expect(MapPrice.comparable(minPrice: null, maxPrice: '9,000'), 9000.0);
      expect(MapPrice.comparable(minPrice: 'abc', maxPrice: '900'), 900.0);
      expect(MapPrice.comparable(minPrice: '0', maxPrice: '900'), 900.0);
      expect(MapPrice.comparable(minPrice: '  ', maxPrice: '900'), 900.0);
    });

    test('otherwise none, and never zero', () {
      expect(MapPrice.comparable(), isNull);
      expect(MapPrice.comparable(minPrice: '', maxPrice: ''), isNull);
      expect(MapPrice.comparable(minPrice: 'abc', maxPrice: 'xyz'), isNull);
      expect(MapPrice.comparable(minPrice: '0', maxPrice: '0'), isNull);
      expect(MapPrice.comparable(minPrice: '-1', maxPrice: 'NaN'), isNull);
      for (final bad in ['', ' ', 'abc', '0', '-3', '1,5', 'AED 5', 'NaN']) {
        final price = MapPrice.comparable(minPrice: bad, maxPrice: bad);
        expect(price, isNull, reason: '"$bad"');
        expect(price, isNot(0.0), reason: '"$bad"');
      }
    });
  });

  group('which places have a price', () {
    test('an Offer has the price its text gives', () {
      final places = MapLocationMapper.offers([
        _offer('both', min: '1,000', max: '2,000'),
        _offer('only-max', max: '3,000'),
        _offer('none'),
        _offer('bad', min: 'AED 5', max: '0'),
      ]);
      expect({
        for (final p in places) p.id: p.price
      }, {
        'both': 1000.0,
        'only-max': 3000.0,
        'none': null,
        'bad': null,
      });
    });

    test('an Offer still carries the text it stored, unchanged', () {
      final place = MapLocationMapper.offers([
        _offer('x', min: '1,000', max: '2,000'),
      ]).single;
      expect(place.additionalData['minPrice'], '1,000');
      expect(place.additionalData['maxPrice'], '2,000');
    });

    test('an Owner, an Office and a Watchman have no price, ever', () {
      final owner = OwnerModel(
        id: 'w',
        userId: 'u',
        name: 'Sara',
        phoneNumber: '',
        countryCode: '+971',
        typeOfProperties: 'Villa',
        propertyLocation: 'Dubai',
        notes: '1,000,000 AED',
        pickUpLocation: '',
        pickUpLatitude: 25.1,
        pickUpLongitude: 55.2,
        pickUpAddress: '',
        mediaUrls: const <String>[],
        createdAt: _now,
        updatedAt: _now,
      );
      final office = OfficeModel(
        id: 'f',
        officeName: 'Price Office 500000',
        managerName: 'Ali',
        countryCode: '+971',
        phoneNumber: '',
        officeLocation: 'Dubai',
        notes: '750,000',
        pickUpLocation: '',
        pickUpLatitude: 25.3,
        pickUpLongitude: 55.3,
        pickUpAddress: '',
      );
      final watchman = WatchmenModel(
        id: 'm',
        name: 'Omar',
        countryCode: '+971',
        phoneNumber: '',
        buildingName: 'Tower 900000',
        notes: '300,000',
        buildingLocation: 'Dubai',
        pickUpLocation: '',
        pickUpLatitude: 25.4,
        pickUpLongitude: 55.4,
        pickUpAddress: '',
      );
      final places = MapLocationMapper.all(
        owners: [owner],
        offices: [office],
        watchmen: [watchman],
      );
      expect(places, hasLength(3));
      for (final place in places) {
        expect(place.price, isNull, reason: place.type.name);
      }
    });
  });

  group('All prices', () {
    test('is the default, and restricts nothing', () {
      expect(MapFilterState.initial.priceMode, MapPriceMode.all);
      expect(MapFilterState.initial.isActive, isFalse);
      expect(MapFilterState.initial.withPriceMode(MapPriceMode.all).isActive,
          isFalse);
    });

    test('keeps every place, in load order, priced or not', () {
      final controller = _loaded();
      controller.setPriceMode(MapPriceMode.lowest);
      controller.setPriceMode(MapPriceMode.all);
      expect(
        _ids(controller.visible),
        ['mid', 'top', 'cheap', 'unpriced', 'owner', 'office', 'watchman'],
      );
      expect(controller.filtersActive, isFalse);
    });

    test('changes nothing in any other filter\'s result', () {
      final places = _market();
      final states = [
        MapFilterState.initial,
        MapFilterState.initial.withEntityType(LocationFilter.offers),
        MapFilterState.initial.withCity('Dubai'),
        MapFilterState.initial.withTransaction(MapTransaction.rent),
        MapFilterState.initial
            .withCity('Dubai')
            .withTransaction(MapTransaction.rent),
        MapFilterState.initial.withNearby(
          const NearbyFilter(latitude: 25.2048, longitude: 55.2708),
        ),
      ];
      for (final state in states) {
        expect(
          _ids(MapFilterEngine.apply(places, state)),
          _ids(MapFilterEngine.apply(
            places,
            state.withPriceMode(MapPriceMode.all),
          )),
        );
      }
    });
  });

  group('Offer price range', () {
    test('blank bounds clear the filter; numeric input rejects negatives', () {
      expect(MapPriceRange.fromBounds(), isNull);
      expect(MapPriceRange.parseBound('500000'), 500000);
      expect(MapPriceRange.parseBound('٥٠٠٠٠٠'), 500000);
      expect(MapPriceRange.parseBound('۵۰۰۰۰۰'), 500000);
      expect(MapPriceRange.parseBound('-1'), isNull);
      expect(MapPriceRange.parseBound('AED 500'), isNull);
      expect(MapPriceRange.parseBound('NaN'), isNull);
      expect(() => MapPriceRange.fromBounds(min: -1), throwsArgumentError);
      expect(() => MapPriceRange.fromBounds(min: 2, max: 1),
          throwsArgumentError);
    });

    test('minimum, maximum, both and inclusive boundaries', () {
      final controller = _loaded([
        _priced('below', 499999),
        _priced('min', 500000),
        _priced('between', 750000),
        _priced('max', 1000000),
        _priced('above', 1000001),
        _priced('unpriced', null),
      ])..setEntityType(LocationFilter.offers);
      controller.setPriceRange(MapPriceRange.fromBounds(min: 500000));
      expect(_ids(controller.visible), ['min', 'between', 'max', 'above']);
      controller.setPriceRange(MapPriceRange.fromBounds(max: 1000000));
      expect(_ids(controller.visible), ['below', 'min', 'between', 'max']);
      controller.setPriceRange(
          MapPriceRange.fromBounds(min: 500000, max: 1000000));
      expect(_ids(controller.visible), ['min', 'between', 'max']);
      controller.setPriceRange(null);
      expect(_ids(controller.visible),
          ['below', 'min', 'between', 'max', 'above', 'unpriced']);
    });

    test('Sort keeps unpriced Offers unless a range is active', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible), ['cheap', 'mid', 'top', 'unpriced']);
      controller.setPriceRange(MapPriceRange.fromBounds(min: 900));
      expect(_ids(controller.visible), ['mid', 'top']);
      controller.setPriceRange(null);
      expect(_ids(controller.visible), ['cheap', 'mid', 'top', 'unpriced']);
    });
  });

  group('Lowest price and Highest price', () {
    test('lowest: priced first, then unpriced in load order', () {
      final controller = _loaded()..setPriceMode(MapPriceMode.lowest);
      // 25 < 900 < 1000 as numbers; as text "1000" < "25" < "900".
      expect(_ids(controller.visible),
          ['cheap', 'mid', 'top', 'unpriced', 'owner', 'office', 'watchman']);
      expect(
        [for (final place in controller.visible) place.price],
        [25.0, 900.0, 1000.0, null, null, null, null],
      );
    });

    test('highest: priced first, then unpriced in load order', () {
      final controller = _loaded()..setPriceMode(MapPriceMode.highest);
      expect(_ids(controller.visible),
          ['top', 'mid', 'cheap', 'unpriced', 'owner', 'office', 'watchman']);
      expect(
        [for (final place in controller.visible) place.price],
        [1000.0, 900.0, 25.0, null, null, null, null],
      );
    });

    test('the order is numeric even for decimals and large amounts', () {
      final controller = _loaded([
        _priced('a', 9.5),
        _priced('b', 10),
        _priced('c', 1500000.25),
        _priced('d', 1500000),
        _priced('e', 100),
      ])
        ..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible), ['a', 'b', 'e', 'd', 'c']);
      controller.setPriceMode(MapPriceMode.highest);
      expect(_ids(controller.visible), ['c', 'd', 'e', 'b', 'a']);
    });

    test('places with the same price keep the order they were loaded in', () {
      final tied = [
        _priced('first', 500),
        _priced('second', 500),
        _priced('cheaper', 100),
        _priced('third', 500),
      ];
      final controller = _loaded(tied)..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible), ['cheaper', 'first', 'second', 'third']);
      controller.setPriceMode(MapPriceMode.highest);
      expect(_ids(controller.visible), ['first', 'second', 'third', 'cheaper']);
    });

    test('switching between the three is repeatable', () {
      final controller = _loaded();
      for (var round = 0; round < 3; round++) {
        controller.setPriceMode(MapPriceMode.lowest);
        expect(_ids(controller.visible),
            ['cheap', 'mid', 'top', 'unpriced', 'owner', 'office', 'watchman']);
        controller.setPriceMode(MapPriceMode.highest);
        expect(_ids(controller.visible),
            ['top', 'mid', 'cheap', 'unpriced', 'owner', 'office', 'watchman']);
        controller.setPriceMode(MapPriceMode.all);
        expect(controller.visible, hasLength(7));
      }
    });

    test('the loaded places themselves are not reordered', () {
      final controller = _loaded()..setPriceMode(MapPriceMode.highest);
      expect(
        _ids(controller.all),
        ['mid', 'top', 'cheap', 'unpriced', 'owner', 'office', 'watchman'],
      );
    });
  });

  group('a place with no price sorts last', () {
    test('it stays visible after priced places', () {
      for (final mode in [MapPriceMode.lowest, MapPriceMode.highest]) {
        final controller = _loaded()..setPriceMode(mode);
        for (final id in ['unpriced', 'owner', 'office', 'watchman']) {
          expect(
            _ids(controller.visible).contains(id),
            isTrue,
            reason: '$id has no price ($mode)',
          );
        }
      }
    });

    test('zero, negative and not-a-number prices are not prices either', () {
      final controller = _loaded([
        _priced('real', 300),
        _priced('zero', 0),
        _priced('negative', -50),
        _priced('nan', double.nan),
        _priced('infinite', double.infinity),
        _priced('none', null),
      ]);
      for (final mode in [MapPriceMode.lowest, MapPriceMode.highest]) {
        controller.setPriceMode(mode);
        expect(_ids(controller.visible),
            ['real', 'zero', 'negative', 'nan', 'infinite', 'none'],
            reason: '$mode');
      }
    });

    test('a record whose stored price is malformed does not rank as free', () {
      final places = MapLocationMapper.offers([
        _offer('free-looking', min: '0', max: ''),
        _offer('garbled', min: 'AED five', max: 'cheap'),
        _offer('empty'),
        _offer('real', min: '1,200'),
      ]);
      final controller = _loaded(places)..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible),
          ['real', 'free-looking', 'garbled', 'empty']);
    });
  });

  group('price with the other filters', () {
    test('a forced sort on non-Offers never hides them', () {
      for (final type in [
        LocationFilter.owners,
        LocationFilter.offices,
        LocationFilter.watchmen,
      ]) {
        for (final mode in [MapPriceMode.lowest, MapPriceMode.highest]) {
          final controller = _loaded()
            ..setEntityType(type)
            ..setPriceMode(mode);
          expect(controller.visible, hasLength(1), reason: '${type.name} $mode');
          expect(
            controller.hasNoMatches,
            isFalse,
            reason: 'sort never filters',
          );
          expect(controller.all, hasLength(7));
        }
      }
    });

    test('Offers with a price ordering: unpriced Offers remain last', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setPriceMode(MapPriceMode.highest);
      expect(_ids(controller.visible), ['top', 'mid', 'cheap', 'unpriced']);
    });

    test('a forced sort on All Layers leaves every layer visible',
        () {
      final controller = _loaded()..setPriceMode(MapPriceMode.lowest);
      expect(controller.state.entityType, LocationFilter.all);
      expect(_ids(controller.visible),
          ['cheap', 'mid', 'top', 'unpriced', 'owner', 'office', 'watchman']);
    });

    test('it combines with city, rent or sale, and Nearby (AND)', () {
      final controller = _loaded()
        ..setCity('Dubai')
        ..setTransaction(MapTransaction.rent)
        ..setPriceMode(MapPriceMode.highest);
      expect(_ids(controller.visible), ['mid', 'cheap', 'unpriced']);

      controller.setTransaction(MapTransaction.sale);
      expect(controller.visible, isEmpty, reason: 'the sale is in Abu Dhabi');
      expect(controller.hasNoMatches, isTrue);

      controller
        ..setCity(null)
        ..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible), ['top']);
    });

    test('Nearby narrows the ordered places by distance', () async {
      final places = [
        _priced('near-dear', 900, lat: 25.2048, lng: 55.2708),
        _priced('near-cheap', 100, lat: 25.21, lng: 55.27),
        _priced('far', 50, lat: 24.4539, lng: 54.3773),
      ];
      final controller = _loaded(places)..setPriceMode(MapPriceMode.lowest);
      await controller.enableNearby(_FixedLocator(25.2048, 55.2708));
      expect(_ids(controller.visible), ['near-cheap', 'near-dear']);
    });

    test('a place with no price remains after another filter', () {
      final controller = _loaded()
        ..setPriceMode(MapPriceMode.lowest)
        ..setCity('Dubai')
        ..setEntityType(LocationFilter.all)
        ..setTransaction(null);
      expect(_ids(controller.visible),
          ['cheap', 'mid', 'unpriced', 'owner', 'office']);
    });
  });

  group('Clear', () {
    test('puts the price back to All prices, with everything else', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setCity('Dubai')
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent)
        ..setPriceMode(MapPriceMode.highest);
      expect(controller.state.priceMode, MapPriceMode.highest);
      expect(controller.filtersActive, isTrue);

      expect(controller.clear(), isTrue);

      expect(controller.state, MapFilterState.initial);
      expect(controller.state.priceMode, MapPriceMode.all);
      expect(controller.state.entityType, LocationFilter.all);
      expect(controller.state.nearby, isNull);
      expect(controller.state.city, isNull);
      expect(controller.state.propertyType, isNull);
      expect(controller.state.transaction, isNull);
      expect(controller.filtersActive, isFalse);
      expect(controller.visible, hasLength(7));
    });

    test('the price alone makes Clear appear, and clears it', () {
      final controller = _loaded()..setPriceMode(MapPriceMode.lowest);
      expect(controller.filtersActive, isTrue);
      controller.clear();
      expect(controller.state.priceMode, MapPriceMode.all);
      expect(controller.filtersActive, isFalse);
    });

    test('clearing again changes nothing', () {
      final controller = _loaded()..setPriceMode(MapPriceMode.lowest);
      expect(controller.clear(), isTrue);
      expect(controller.clear(), isFalse);
    });
  });

  group('the price is part of the one filter state', () {
    test('choosing the same price changes nothing; another does', () {
      final controller = _loaded();
      expect(controller.setPriceMode(MapPriceMode.all), isFalse);
      expect(controller.setPriceMode(MapPriceMode.lowest), isTrue);
      expect(controller.setPriceMode(MapPriceMode.lowest), isFalse);
      expect(controller.setPriceMode(MapPriceMode.highest), isTrue);
    });

    test('every other choice keeps the price', () {
      // Sort is the Offers row's own filter, so the price is chosen under
      // Offers (another layer clears it: see map_ux_phase3_test.dart). Choosing
      // the same layer again is no change, and then nothing else touches it.
      var state = MapFilterState.initial
          .withEntityType(LocationFilter.offers)
          .withPriceMode(MapPriceMode.highest);
      state = state.withEntityType(LocationFilter.offers);
      state = state.withCity('Dubai');
      state = state.withPropertyType('villa');
      state = state.withTransaction(MapTransaction.sale);
      state = state.withNearby(
        const NearbyFilter(latitude: 25.2, longitude: 55.27),
      );
      expect(state.priceMode, MapPriceMode.highest);
      state = state.withNearby(null).withCity(null);
      expect(state.priceMode, MapPriceMode.highest);
    });

    test('states with different prices are different, and hash apart', () {
      const a = MapFilterState();
      final b = a.withPriceMode(MapPriceMode.lowest);
      final c = a.withPriceMode(MapPriceMode.highest);
      expect(a == b, isFalse);
      expect(b == c, isFalse);
      expect(b == a.withPriceMode(MapPriceMode.lowest), isTrue);
      expect(b.hashCode, a.withPriceMode(MapPriceMode.lowest).hashCode);
      expect({a, b, c}, hasLength(3));
    });

    test('the three choices are all, lowest, highest, in that order', () {
      expect(MapPriceMode.values, [
        MapPriceMode.all,
        MapPriceMode.lowest,
        MapPriceMode.highest,
      ]);
    });
  });

  group('it costs no backend read', () {
    test('choosing, switching and clearing the price reads nothing', () async {
      final source = _Source();
      final filters = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _Cache(),
        onPlaces: (places, {required fresh}) async =>
            filters.setRecords(places),
        onFailed: () {},
      );
      await loader.start();
      expect(source.loads, 1);

      for (var i = 0; i < 20; i++) {
        filters
          ..setEntityType(LocationFilter.offers)
          ..setPriceRange(MapPriceRange.fromBounds(min: 500))
          ..setPriceMode(MapPriceMode.lowest)
          ..setPriceMode(MapPriceMode.highest)
          ..setPriceMode(MapPriceMode.all)
          ..setPriceMode(MapPriceMode.lowest)
          ..setCity('Dubai')
          ..clear();
      }
      expect(filters.visible, hasLength(7));
      expect(source.loads, 1, reason: 'not one read for any of that');
      loader.dispose();
    });

    test('a refresh keeps the chosen price and re-ranks the new places',
        () async {
      final controller = _loaded()..setPriceMode(MapPriceMode.lowest);
      controller.setRecords([
        _priced('new-cheap', 10),
        _priced('new-dear', 5000),
        _priced('no-price', null),
      ]);
      expect(controller.state.priceMode, MapPriceMode.lowest);
      expect(_ids(controller.visible), ['new-cheap', 'new-dear', 'no-price']);
    });
  });

  group('the words (the control is called Sort)', () {
    test('English: Sort, Default, Price: Low to High, Price: High to Low', () {
      final table = _arb('en');
      expect(table['mapFilterSort'], 'Sort');
      expect(table['mapSortDefault'], 'Default');
      expect(table['mapSortPriceLowToHigh'], 'Price: Low to High');
      expect(table['mapSortPriceHighToLow'], 'Price: High to Low');
    });

    test('Arabic: الترتيب, الافتراضي, and the two price orders', () {
      final table = _arb('ar');
      expect(table['mapFilterSort'], 'الترتيب');
      expect(table['mapSortDefault'], 'الافتراضي');
      expect(table['mapSortPriceLowToHigh'], 'السعر: من الأقل إلى الأعلى');
      expect(table['mapSortPriceHighToLow'], 'السعر: من الأعلى إلى الأقل');
    });

    test('the four are different words, in both languages', () {
      for (final code in ['en', 'ar']) {
        final table = _arb(code);
        final words = {
          table['mapFilterSort'],
          table['mapSortDefault'],
          table['mapSortPriceLowToHigh'],
          table['mapSortPriceHighToLow'],
        };
        expect(words, hasLength(4), reason: code);
        for (final word in words) {
          expect((word as String).trim(), isNotEmpty, reason: code);
        }
      }
    });

    test('the retired price-sort names stay gone from both languages', () {
      for (final code in ['en', 'ar']) {
        final table = _arb(code);
        for (final old in [
          'mapAllPrices',
          'mapLowestPrice',
          'mapHighestPrice',
        ]) {
          expect(table.containsKey(old), isFalse, reason: '$code $old');
        }
      }
    });
  });
}

/// A position that is always there.
class _FixedLocator implements NearbyLocator {
  _FixedLocator(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  Future<NearbyFix> locate() async => NearbyLocated(latitude, longitude);
}
