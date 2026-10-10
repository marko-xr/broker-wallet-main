// Smart Map UX Phase 3: contextual filters by layer.
//
// The filter row follows the layer that is chosen: Layers, Location and Near Me
// are always there, and Rent / Sale, Property Type and Sort only where the kind
// of place has them. A control that is not shown is never on: choosing another
// layer puts the layer's own filters back to their defaults in the very same
// change, and Reset can never stay on for a filter the person cannot see.
// Where the map looks (the city, Near Me), the search, the loaded places and
// the backend are not touched by a change of layer. Plain Dart: the real
// mapper, filter state, controller and loader, and source guards.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_layer_controls.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bar = 'lib/src/views/Screens/home/map/map_filter_bar.dart';
const String _viewModel = 'lib/src/views/Screens/home/map/map_viewmodel.dart';
const String _filter = 'lib/src/services/map_filter.dart';
const String _controller = 'lib/src/services/map_filter_controller.dart';
const String _controls = 'lib/src/services/map_layer_controls.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

int _count(String text, String needle) =>
    needle.isEmpty ? 0 : text.split(needle).length - 1;

String _between(String text, String from, String to) {
  final start = text.indexOf(from);
  expect(start, greaterThanOrEqualTo(0), reason: from);
  final end = text.indexOf(to, start + from.length);
  expect(end, greaterThan(start), reason: to);
  return text.substring(start, end);
}

// ---- the places ---------------------------------------------------------

// The device is in Downtown Dubai.
const double _homeLat = 25.2048;
const double _homeLng = 55.2708;

CachedLocationData _place(
  String id,
  LocationFilter type, {
  String? city,
  String? property,
  MapTransaction? transaction,
  double? price,
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
      price: price,
    );

/// Three Offers (two of them in Dubai), two Owners, an Office and a Watchman.
List<CachedLocationData> _places() => [
      _place(
        'rent-villa',
        LocationFilter.offers,
        city: 'Dubai',
        property: 'villa',
        transaction: MapTransaction.rent,
        price: 900,
      ),
      _place(
        'sale-flat',
        LocationFilter.offers,
        city: 'Abu Dhabi',
        property: 'apartment',
        transaction: MapTransaction.sale,
        price: 1200,
        lat: 24.4539,
        lng: 54.3773,
      ),
      _place(
        'rent-flat',
        LocationFilter.offers,
        city: 'Dubai',
        property: 'apartment',
        transaction: MapTransaction.rent,
        price: 400,
      ),
      _place(
        'owner-villa',
        LocationFilter.owners,
        city: 'Dubai',
        property: 'villa',
      ),
      _place(
        'owner-flat',
        LocationFilter.owners,
        city: 'Abu Dhabi',
        property: 'apartment',
        lat: 24.46,
        lng: 54.37,
      ),
      _place('office', LocationFilter.offices, city: 'Dubai'),
      _place('watchman', LocationFilter.watchmen, city: 'Dubai'),
    ];

List<String> _ids(Iterable<CachedLocationData> places) => [
      for (final place in places) place.id,
    ];

MapFilterController _loaded() => MapFilterController()..setRecords(_places());

/// "Offers + Sale + Apartment + Price Low to High", the owner's own example.
MapFilterController _offersFiltered() => _loaded()
  ..setEntityType(LocationFilter.offers)
  ..setTransaction(MapTransaction.sale)
  ..setPropertyType('apartment')
  ..setPriceRange(MapPriceRange.fromBounds(min: 1000))
  ..setPriceMode(MapPriceMode.lowest);

// ---- the device ----------------------------------------------------------

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

const NearbyFix _atHome = NearbyLocated(_homeLat, _homeLng);

// ---- the backend ---------------------------------------------------------

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
    return _places();
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

// ---- one record of each kind, through the real mapper ----------------------

final DateTime _now = DateTime(2026, 10, 10);

// The app's own sources, standing in for the ARB-backed ones: the Offer forms'
// keys, and the Owner form's own suggestions.
final MapVocabulary _vocabulary = MapVocabulary(
  offerPropertyKey: (stored) => MapPropertyTypes.canonicalKey(
    stored,
    const ['apartment', 'villa'],
  ),
  ownerPropertyKey: (stored) =>
      OwnerPropertyTypes.match(stored, labelsOfKey: (key) => [key])?.key,
);

/// A fully filled record of each kind, as the Map's own source maps it.
List<CachedLocationData> _onePerKind() => [
      ...MapLocationMapper.offers([
        OfferModel(
          id: 'o1',
          userId: 'u1',
          offerType: 'rent',
          selectedCity: 'Dubai',
          selectedAreas: const <String>[],
          location: '',
          phoneNumber: '+971501234567',
          countryCode: '+971',
          minPrice: '1,000',
          maxPrice: '2,000',
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
        ),
      ], vocabulary: _vocabulary),
      ...MapLocationMapper.owners([
        OwnerModel(
          id: 'w1',
          userId: 'u1',
          name: 'Sara',
          phoneNumber: '0501112222',
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
        ),
      ], vocabulary: _vocabulary),
      ...MapLocationMapper.offices([
        OfficeModel(
          id: 'f1',
          officeName: 'Palm Office',
          managerName: 'Ali',
          countryCode: '+971',
          phoneNumber: '',
          officeLocation: 'Dubai',
          notes: '750,000',
          pickUpLocation: '',
          pickUpLatitude: 25.3,
          pickUpLongitude: 55.3,
          pickUpAddress: '',
        ),
      ], vocabulary: _vocabulary),
      ...MapLocationMapper.watchmen([
        WatchmenModel(
          id: 'm1',
          name: 'Omar',
          countryCode: '+971',
          phoneNumber: '',
          buildingName: 'Tower A',
          notes: '300,000',
          buildingLocation: 'Dubai',
          pickUpLocation: '',
          pickUpLatitude: 25.4,
          pickUpLongitude: 55.4,
          pickUpAddress: '',
        ),
      ], vocabulary: _vocabulary),
    ];

/// Whether a place has the thing [control] filters by.
bool _carries(CachedLocationData place, MapFilterControl control) =>
    switch (control) {
      MapFilterControl.layers ||
      MapFilterControl.location ||
      MapFilterControl.nearMe =>
        true,
      MapFilterControl.transaction => place.transaction != null,
      MapFilterControl.propertyType => place.propertyType != null,
      MapFilterControl.price => place.price != null,
      MapFilterControl.sort => place.price != null,
    };

/// The kinds whose mapped places carry what [control] filters by.
Set<LocationFilter> _kindsCarrying(MapFilterControl control) => {
      for (final place in _onePerKind())
        if (_carries(place, control)) place.type,
    };

// ---- "is this control on?" -------------------------------------------------

/// Whether [control] is at its default in [state]. Exhaustive on purpose: a
/// control added to the row must say here what "off" is.
bool _isDefault(MapFilterState state, MapFilterControl control) =>
    switch (control) {
      MapFilterControl.layers => state.entityType == LocationFilter.all,
      MapFilterControl.location => state.city == null,
      MapFilterControl.nearMe => state.nearby == null,
      MapFilterControl.transaction => state.transaction == null,
      MapFilterControl.propertyType => state.propertyType == null,
      MapFilterControl.price => state.priceRange == null,
      MapFilterControl.sort => state.priceMode == MapPriceMode.all,
    };

/// What is wrong with [controller] right now, as plain sentences (empty: all
/// well). The same checks run after every step of the walk, and are shown here
/// to fail on a state that breaks them.
List<String> _problems(MapFilterController controller) {
  final state = controller.state;
  final problems = <String>[];

  // 1. A control that is not shown is not on.
  for (final control in MapFilterControl.values) {
    if (!MapLayerControls.shows(state.entityType, control) &&
        !_isDefault(state, control)) {
      problems.add('${control.name} is on, but ${state.entityType.name} has '
          'no such control');
    }
  }

  // 2. Reset is shown exactly when a control that IS shown is not at its
  //    default: never for a filter the person cannot see.
  final somethingShown = MapFilterControl.values.any(
    (control) =>
        MapLayerControls.shows(state.entityType, control) &&
        !_isDefault(state, control),
  );
  if (controller.filtersActive != somethingShown) {
    problems.add('Reset is ${controller.filtersActive ? 'on' : 'off'} but a '
        'shown control is ${somethingShown ? 'on' : 'off'}');
  }

  // 3. Reset is still the state's own rule: on exactly when it differs from
  //    the default.
  if (controller.filtersActive != (state != MapFilterState.initial)) {
    problems.add('Reset is not "differs from the default"');
  }

  // 4. The places are the state's own, in one piece: the snapshot never holds a
  //    new layer with an old filter's places.
  final snapshot = controller.snapshot;
  if (snapshot.state != state) problems.add('the snapshot is another state');
  final wanted = _ids(MapFilterEngine.apply(controller.all, state));
  if (_ids(snapshot.visible).join(',') != wanted.join(',') ||
      _ids(controller.visible).join(',') != wanted.join(',')) {
    problems.add('the places are not the state\'s own');
  }
  return problems;
}

// ---- what the person can do in the row -----------------------------------------

/// One choice in the row, with the control it is made in. Layers, Location and
/// Near Me are in every row; the others are offered only while the layer has
/// them.
class _Step {
  const _Step(this.name, this.control, this.apply);

  final String name;
  final MapFilterControl? control;
  final void Function(MapFilterController controller) apply;

  bool offeredAt(LocationFilter layer) =>
      control == null || MapLayerControls.shows(layer, control!);

  @override
  String toString() => name;
}

final List<_Step> _steps = [
  for (final layer in LocationFilter.values)
    _Step('layer ${layer.name}', MapFilterControl.layers,
        (c) => c.setEntityType(layer)),
  _Step('city Dubai', MapFilterControl.location, (c) => c.setCity('Dubai')),
  _Step('city Ajman', MapFilterControl.location, (c) => c.setCity('Ajman')),
  _Step('All UAE', MapFilterControl.location, (c) => c.setAllUae()),
  _Step('rent', MapFilterControl.transaction,
      (c) => c.setTransaction(MapTransaction.rent)),
  _Step('sale', MapFilterControl.transaction,
      (c) => c.setTransaction(MapTransaction.sale)),
  _Step('any transaction', MapFilterControl.transaction,
      (c) => c.setTransaction(null)),
  _Step('villa', MapFilterControl.propertyType,
      (c) => c.setPropertyType('villa')),
  _Step('apartment', MapFilterControl.propertyType,
      (c) => c.setPropertyType('apartment')),
  _Step('any type', MapFilterControl.propertyType,
      (c) => c.setPropertyType(null)),
  _Step('price from 1000', MapFilterControl.price,
      (c) => c.setPriceRange(MapPriceRange.fromBounds(min: 1000))),
  _Step('any price', MapFilterControl.price,
      (c) => c.setPriceRange(null)),
  _Step('price low to high', MapFilterControl.sort,
      (c) => c.setPriceMode(MapPriceMode.lowest)),
  _Step('price high to low', MapFilterControl.sort,
      (c) => c.setPriceMode(MapPriceMode.highest)),
  _Step('price default', MapFilterControl.sort,
      (c) => c.setPriceMode(MapPriceMode.all)),
  _Step('Reset', null, (c) => c.clear()),
];

void main() {
  group('the contract: who really has Rent / Sale, Property Type and Sort', () {
    test('Rent / Sale is the Offer\'s alone', () {
      expect(
        _kindsCarrying(MapFilterControl.transaction),
        {LocationFilter.offers},
      );
    });

    test('Sort (by price) is the Offer\'s alone', () {
      expect(_kindsCarrying(MapFilterControl.sort), {LocationFilter.offers});
    });

    test(
        'Property Type is the Offer\'s AND the Owner\'s, not an Office\'s or '
        'a Watchman\'s', () {
      // Found while verifying the contract: it is not Offer-only. An Owner's
      // type of properties is matched against the Owner form's own suggestions
      // and filterable already; the row keeps it for Owners.
      expect(
        _kindsCarrying(MapFilterControl.propertyType),
        {LocationFilter.offers, LocationFilter.owners},
      );
    });

    test('the app\'s own wiring is what gives each kind what it carries', () {
      // The vocabulary the Map reads with names the Offer forms' types AND the
      // Owner form's suggestions...
      final source =
          _squash(_read('lib/src/services/map_location_source.dart'));
      for (final pinned in [
        'offerPropertyKey: (stored) => MapPropertyTypes.canonicalKey(stored, ShareFormat.propertySubTypeKeys),',
        'ownerPropertyKey: (stored) => OwnerPropertyTypes.match(stored, labelsOfKey: namesOfKey)?.key,',
      ]) {
        expect(source.contains(pinned), isTrue, reason: pinned);
      }
      // ...and the mapper reads a Property Type for Offers and Owners, and a
      // transaction and a price for Offers, and for no other kind.
      final mapper = _squash(_read('lib/src/services/map_location_data.dart'));
      for (final pinned in [
        'propertyType: _propertyKey( vocabulary.offerPropertyKey, offer.specificPropertyType, ),',
        'propertyType: _propertyKey( vocabulary.ownerPropertyKey, owner.typeOfProperties, ),',
      ]) {
        expect(_count(mapper, pinned), 1, reason: pinned);
      }
      expect(_count(mapper, 'propertyType: _propertyKey('), 2);
      expect(_count(mapper, 'transaction: MapTransaction.fromStored('), 1);
      expect(_count(mapper, 'price: MapPrice.comparable('), 1);
    });

    test('an Office and a Watchman have none of the three', () {
      final kinds = _onePerKind();
      expect(kinds.map((place) => place.type), [
        LocationFilter.offers,
        LocationFilter.owners,
        LocationFilter.offices,
        LocationFilter.watchmen,
      ]);
      for (final place in kinds.skip(2)) {
        expect(place.transaction, isNull, reason: place.type.name);
        expect(place.propertyType, isNull, reason: place.type.name);
        expect(place.price, isNull, reason: place.type.name);
      }
    });

    test('each kind\'s row has exactly the controls its places carry', () {
      for (final place in _onePerKind()) {
        for (final control in MapFilterControl.values) {
          expect(
            MapLayerControls.shows(place.type, control),
            _carries(place, control),
            reason: '${place.type.name} ${control.name}',
          );
        }
      }
    });
  });

  group('the row for each layer', () {
    const layers = MapFilterControl.layers;
    const location = MapFilterControl.location;
    const nearMe = MapFilterControl.nearMe;
    const transaction = MapFilterControl.transaction;
    const propertyType = MapFilterControl.propertyType;
    const price = MapFilterControl.price;
    const sort = MapFilterControl.sort;

    test('there are seven controls, with Price separate from Sort', () {
      expect(MapFilterControl.values, [
        layers,
        location,
        nearMe,
        transaction,
        propertyType,
        price,
        sort,
      ]);
    });

    test('All Layers: Layers, Location and Near Me only', () {
      expect(MapLayerControls.of(LocationFilter.all),
          unorderedEquals([layers, location, nearMe]));
    });

    test('Offers: Layers, Location, Near Me, Rent / Sale, Property Type, Price, Sort',
        () {
      expect(
        MapLayerControls.of(LocationFilter.offers),
        unorderedEquals(
          [layers, location, nearMe, transaction, propertyType, price, sort],
        ),
      );
    });

    test('Owners: Layers, Location, Near Me and Property Type (it has one)',
        () {
      expect(
        MapLayerControls.of(LocationFilter.owners),
        unorderedEquals([layers, location, nearMe, propertyType]),
      );
    });

    test('Offices and Watchmen: Layers, Location and Near Me only', () {
      for (final layer in [LocationFilter.offices, LocationFilter.watchmen]) {
        expect(
          MapLayerControls.of(layer),
          unorderedEquals([layers, location, nearMe]),
          reason: layer.name,
        );
      }
    });

    test('Layers, Location, Near Me are in every row; the table is complete',
        () {
      for (final layer in LocationFilter.values) {
        expect(MapLayerControls.shows(layer, layers), isTrue);
        expect(MapLayerControls.shows(layer, location), isTrue);
        expect(MapLayerControls.shows(layer, nearMe), isTrue);
        for (final control in MapFilterControl.values) {
          expect(
            MapLayerControls.shows(layer, control),
            MapLayerControls.of(layer).contains(control),
          );
        }
      }
    });

    test('only Offers have Rent / Sale, Price and Sort',
        () {
      for (final layer in LocationFilter.values) {
        final offers = layer == LocationFilter.offers;
        expect(MapLayerControls.shows(layer, transaction), offers,
            reason: layer.name);
        expect(MapLayerControls.shows(layer, sort), offers, reason: layer.name);
        expect(MapLayerControls.shows(layer, price), offers, reason: layer.name);
      }
    });

    test('Property Type is in the Offers and Owners rows only', () {
      for (final layer in LocationFilter.values) {
        expect(
          MapLayerControls.shows(layer, propertyType),
          layer == LocationFilter.offers || layer == LocationFilter.owners,
          reason: layer.name,
        );
      }
    });
  });

  group('another layer puts the layer\'s own filters back, in one change', () {
    test('Offers + Sale + Apartment + Price Low to High is what is set up', () {
      final controller = _offersFiltered();
      expect(controller.state.transaction, MapTransaction.sale);
      expect(controller.state.propertyType, 'apartment');
      expect(controller.state.priceMode, MapPriceMode.lowest);
      expect(_ids(controller.visible), ['sale-flat']);
    });

    test('...then other layers: Offer-only choices reset, shared type survives',
        () {
      final shown = {
        LocationFilter.watchmen: ['watchman'],
        LocationFilter.offices: ['office'],
        LocationFilter.owners: ['owner-flat'],
        // Every place, in load order: a price order kept would leave only the
        // priced Offers.
        LocationFilter.all: [
          'rent-villa',
          'sale-flat',
          'rent-flat',
          'owner-villa',
          'owner-flat',
          'office',
          'watchman',
        ],
      };
      for (final entry in shown.entries) {
        final controller = _offersFiltered();
        final before = controller.snapshot;

        expect(controller.setEntityType(entry.key), isTrue,
            reason: entry.key.name);

        final state = controller.state;
        expect(state.entityType, entry.key, reason: entry.key.name);
        expect(state.transaction, isNull, reason: entry.key.name);
        expect(state.propertyType,
            entry.key == LocationFilter.owners ? 'apartment' : null,
            reason: entry.key.name);
        expect(state.priceRange, isNull, reason: entry.key.name);
        expect(state.priceMode, MapPriceMode.all, reason: entry.key.name);
        expect(_ids(controller.visible), entry.value, reason: entry.key.name);
        // One change: one new version, and the snapshot is the new state with
        // its own places, never the new layer over the old filters.
        final after = controller.snapshot;
        expect(after.stateVersion, before.stateVersion + 1,
            reason: entry.key.name);
        expect(after.state, state, reason: entry.key.name);
        expect(_ids(after.visible), entry.value, reason: entry.key.name);
        expect(_problems(controller), isEmpty, reason: entry.key.name);
      }
    });

    test('the same state transition, on its own', () {
      final offers = MapFilterState.initial
          .withEntityType(LocationFilter.offers)
          .withTransaction(MapTransaction.sale)
          .withPropertyType('apartment')
          .withPriceRange(MapPriceRange.fromBounds(min: 1000))
          .withPriceMode(MapPriceMode.lowest);
      for (final layer in [
        LocationFilter.all,
        LocationFilter.owners,
        LocationFilter.offices,
        LocationFilter.watchmen,
      ]) {
        final next = offers.withEntityType(layer);
        expect(next,
            MapFilterState(
                entityType: layer,
                propertyType: layer == LocationFilter.owners ? 'apartment' : null),
            reason: layer.name);
        expect(next.isActive, layer != LocationFilter.all, reason: layer.name);
      }
    });

    test('a shared Owner type follows to Offers, and clears elsewhere',
        () {
      for (final layer in [
        LocationFilter.offers,
        LocationFilter.offices,
        LocationFilter.watchmen,
        LocationFilter.all,
      ]) {
        final controller = _loaded()
          ..setEntityType(LocationFilter.owners)
          ..setPropertyType('apartment');
        expect(_ids(controller.visible), ['owner-flat']);
        controller.setEntityType(layer);
        expect(controller.state.propertyType,
            layer == LocationFilter.offers ? 'apartment' : null,
            reason: layer.name);
        expect(_problems(controller), isEmpty, reason: layer.name);
      }
    });

    test('a shared Offer type follows to Owners', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setPropertyType('apartment');
      expect(_ids(controller.visible), ['sale-flat', 'rent-flat']);
      controller.setEntityType(LocationFilter.owners);
      expect(controller.state.propertyType, 'apartment');
      expect(_ids(controller.visible), ['owner-flat']);
    });

    test('a type exclusive to one layer clears in the same transition', () {
      final offers = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setPropertyType('compound');
      final before = offers.snapshot.stateVersion;
      offers.setEntityType(LocationFilter.owners);
      expect(offers.state.propertyType, isNull);
      expect(offers.snapshot.stateVersion, before + 1);

      final owners = _loaded()
        ..setEntityType(LocationFilter.owners)
        ..setPropertyType('residentialPlot');
      owners.setEntityType(LocationFilter.offers);
      expect(owners.state.propertyType, isNull);
    });

    test('coming back to Offers starts with the Offer filters at default', () {
      final controller = _offersFiltered();
      controller.setEntityType(LocationFilter.watchmen);
      controller.setEntityType(LocationFilter.offers);
      expect(controller.state.transaction, isNull);
      expect(controller.state.propertyType, isNull);
      expect(controller.state.priceRange, isNull);
      expect(controller.state.priceMode, MapPriceMode.all);
      expect(
          _ids(controller.visible), ['rent-villa', 'sale-flat', 'rent-flat']);
      // Nothing was remembered behind the row's back, either.
      expect(
        controller.state,
        const MapFilterState(entityType: LocationFilter.offers),
      );
    });

    test('a change from Offers to Offers is no change, and keeps the filters',
        () {
      final controller = _offersFiltered();
      final version = controller.snapshot.stateVersion;
      expect(controller.setEntityType(LocationFilter.offers), isFalse);
      expect(controller.snapshot.stateVersion, version);
      expect(controller.state.transaction, MapTransaction.sale);
      expect(controller.state.propertyType, 'apartment');
      expect(controller.state.priceRange, MapPriceRange.fromBounds(min: 1000));
      expect(controller.state.priceMode, MapPriceMode.lowest);
      expect(_ids(controller.visible), ['sale-flat']);
    });

    test('every layer change clears them, even into a layer that has them', () {
      // A state the screen cannot make (a price chosen with every layer shown)
      // is not carried into Offers either: the filters belong to the row that
      // offered them.
      final state = MapFilterState.initial
          .withPriceMode(MapPriceMode.highest)
          .withEntityType(LocationFilter.offers);
      expect(state.priceMode, MapPriceMode.all);
      expect(
        MapFilterState.initial
            .withTransaction(MapTransaction.rent)
            .withEntityType(LocationFilter.owners)
            .transaction,
        isNull,
      );
    });

    test('Reset: Offers + Sale, then All Layers, leaves nothing to reset', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..setTransaction(MapTransaction.sale);
      expect(controller.filtersActive, isTrue);

      controller.setEntityType(LocationFilter.all);

      // The hidden Sale did not keep Reset on: the map is the default map.
      expect(controller.filtersActive, isFalse);
      expect(controller.state, MapFilterState.initial);
      expect(controller.visible, hasLength(7));
    });

    test('Reset: a layer is a visible reason for it, and it clears the layer',
        () {
      final controller = _offersFiltered();
      controller.setEntityType(LocationFilter.watchmen);
      // The Layers chip says Watchmen: that is what Reset is on for.
      expect(controller.filtersActive, isTrue);
      expect(
        controller.state,
        const MapFilterState(entityType: LocationFilter.watchmen),
      );
      expect(controller.clear(), isTrue);
      expect(controller.state, MapFilterState.initial);
      expect(controller.filtersActive, isFalse);
      expect(controller.visible, hasLength(7));
    });
  });

  group('Location, the device, search and the backend are not touched', () {
    test('the city stays through every layer change', () {
      final controller = _loaded()
        ..setCity('Dubai')
        ..setEntityType(LocationFilter.offers)
        ..setTransaction(MapTransaction.rent)
        ..setPropertyType('villa');
      expect(_ids(controller.visible), ['rent-villa']);

      for (final layer in [
        LocationFilter.owners,
        LocationFilter.offices,
        LocationFilter.watchmen,
        LocationFilter.all,
        LocationFilter.offers,
      ]) {
        controller.setEntityType(layer);
        expect(controller.state.city, 'Dubai', reason: layer.name);
        expect(controller.state.nearby, isNull, reason: layer.name);
      }
      controller.setEntityType(LocationFilter.owners);
      // Dubai's Owner only: the Abu Dhabi Owner stays out, the Villa is gone.
      expect(_ids(controller.visible), ['owner-villa']);
    });

    test('Near Me stays, and the device is asked nothing', () async {
      final locator = _CountingLocator(_atHome);
      final controller = _loaded();
      await controller.enableNearby(locator, radiusKm: 10);
      final nearby = controller.state.nearby;
      expect(nearby, isNotNull);
      final request = controller.nearbyRequest;

      controller
        ..setEntityType(LocationFilter.offers)
        ..setTransaction(MapTransaction.rent)
        ..setPriceMode(MapPriceMode.lowest);
      expect(_ids(controller.visible), ['rent-flat', 'rent-villa']);

      for (final layer in [
        LocationFilter.owners,
        LocationFilter.all,
        LocationFilter.offices,
        LocationFilter.watchmen,
        LocationFilter.offers,
      ]) {
        controller.setEntityType(layer);
        expect(controller.state.nearby, nearby, reason: layer.name);
        expect(controller.state.city, isNull, reason: layer.name);
        expect(controller.nearbyRequest, request, reason: layer.name);
      }
      expect(locator.calls, 1, reason: 'a layer asks the device nothing');
      controller.setEntityType(LocationFilter.owners);
      expect(_ids(controller.visible), ['owner-villa']);
    });

    test('a Near Me request still waiting is neither cancelled nor changed',
        () async {
      final locator = _PendingLocator();
      final controller = _loaded();
      final pending = controller.enableNearby(locator, radiusKm: 10);
      final request = controller.nearbyRequest;
      expect(controller.isLocatingNearby, isTrue);

      controller
        ..setEntityType(LocationFilter.offers)
        ..setTransaction(MapTransaction.rent)
        ..setEntityType(LocationFilter.owners)
        ..setEntityType(LocationFilter.all);
      expect(controller.isLocatingNearby, isTrue,
          reason: 'the wait is not the layer\'s business');
      expect(controller.nearbyRequest, request);
      expect(locator.calls, 1);

      locator.answer(_atHome);
      await pending;
      // The position that was asked for is applied, on the layer chosen since.
      expect(controller.state.nearby, isNotNull);
      expect(controller.state.entityType, LocationFilter.all);
      expect(controller.isLocatingNearby, isFalse);
    });

    test('a layer change reads nothing: not one more load', () async {
      final source = _Source();
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

      for (var i = 0; i < 10; i++) {
        controller
          ..setEntityType(LocationFilter.offers)
          ..setTransaction(MapTransaction.sale)
          ..setPropertyType('apartment')
          ..setPriceMode(MapPriceMode.lowest)
          ..setEntityType(LocationFilter.owners)
          ..setEntityType(LocationFilter.all)
          ..clear();
      }
      expect(source.loads, 1, reason: 'not one read for any of that');
      loader.dispose();
    });

    test('the loaded places are the same list, whatever the layer', () {
      final controller = _offersFiltered();
      final all = controller.all;
      controller.setEntityType(LocationFilter.watchmen);
      controller.setEntityType(LocationFilter.offers);
      expect(identical(controller.all, all), isTrue);
      expect(controller.all, hasLength(7));
    });

    test('the open card is kept while its place is still shown', () {
      final controller = _loaded()
        ..setEntityType(LocationFilter.offers)
        ..select('offers:rent-villa');
      expect(controller.selectedKey, 'offers:rent-villa');
      // Offers + Rent is still on rent-villa: the card stays.
      controller.setTransaction(MapTransaction.rent);
      expect(controller.selectedKey, 'offers:rent-villa');
      // Another layer takes the place off the map, and the card with it.
      controller.setEntityType(LocationFilter.owners);
      expect(controller.selectedKey, isNull);
    });
  });

  group('a control that is not shown is never on', () {
    // Every sequence of up to `depth` choices the row offers, from the default,
    // on the real controller: after each one, the checks hold.
    const int depth = 5;

    test('the checker does see a filter that is on with no control for it', () {
      // The row can't make this state; it is forced here to show the checks can
      // fail, so a pass above means something.
      final forced = _loaded()..setTransaction(MapTransaction.rent);
      expect(forced.state.entityType, LocationFilter.all);
      expect(_problems(forced), isNotEmpty);
      expect(_problems(forced).first, contains('transaction is on'));

      final stale = _loaded()
        ..setEntityType(LocationFilter.owners)
        ..setPriceMode(MapPriceMode.lowest);
      expect(_problems(stale).join(' '), contains('sort is on'));
      expect(_problems(_loaded()), isEmpty);
      expect(_problems(_offersFiltered()), isEmpty);
    });

    test('every reachable state of the row is consistent (depth $depth)', () {
      var visited = 0;
      final seenOn = <MapFilterControl>{};
      final seenLayers = <LocationFilter>{};
      var leftOffersWithAFilterOn = 0;
      final failures = <String>[];

      void visit(List<_Step> path, MapFilterState? before) {
        final controller = _loaded();
        for (final step in path) {
          step.apply(controller);
        }
        visited++;

        final problems = _problems(controller);
        if (problems.isNotEmpty) {
          failures.add('after ${path.join(' > ')}: ${problems.join('; ')}');
        }

        final state = controller.state;
        seenLayers.add(state.entityType);
        for (final control in MapFilterControl.values) {
          if (!_isDefault(state, control)) seenOn.add(control);
        }
        // Coverage of the case the owner named: an Offer filter was on, and the
        // layer has just left Offers for another.
        if (before != null &&
            before.entityType == LocationFilter.offers &&
            state.entityType != LocationFilter.offers &&
            (before.transaction != null ||
                before.propertyType != null ||
                before.priceRange != null ||
                before.priceMode != MapPriceMode.all)) {
          leftOffersWithAFilterOn++;
        }

        if (path.length == depth) return;
        for (final next in _steps) {
          if (next.offeredAt(state.entityType)) {
            visit([...path, next], state);
          }
        }
      }

      visit(const <_Step>[], null);

      // Every failing path is listed (and the first few are enough to read).
      expect(failures.take(5).toList(), isEmpty);
      expect(failures, isEmpty);
      expect(visited, greaterThan(10000));
      // The walk reached every layer, and each of the controls on. (Near Me
      // needs the device, so this walk never turns it on: the next one starts
      // with it on.)
      expect(seenLayers, unorderedEquals(LocationFilter.values));
      expect(
        seenOn,
        unorderedEquals(
          MapFilterControl.values.where(
            (control) => control != MapFilterControl.nearMe,
          ),
        ),
      );
      // ...and left Offers with a filter on many times over.
      expect(leftOffersWithAFilterOn, greaterThan(100));
    });

    test('with Near Me on to begin with, the same holds (depth 4)', () async {
      // The same walk from a map that already has Near Me on: a city or All UAE
      // in it turns Near Me off, a layer never does, and Reset is on for Near Me
      // (a control that is always in the row) whichever layer is chosen.
      const nearDepth = 4;
      var visited = 0;
      var nearMeKeptThroughALayerChange = 0;
      final seenOn = <MapFilterControl>{};
      final failures = <String>[];

      Future<void> visit(List<_Step> path, MapFilterState? before) async {
        final controller = _loaded();
        await controller.enableNearby(_CountingLocator(_atHome), radiusKm: 10);
        for (final step in path) {
          step.apply(controller);
        }
        visited++;

        final problems = _problems(controller);
        if (problems.isNotEmpty) {
          failures.add('after ${path.join(' > ')}: ${problems.join('; ')}');
        }

        final state = controller.state;
        for (final control in MapFilterControl.values) {
          if (!_isDefault(state, control)) seenOn.add(control);
        }
        // Choosing a layer with Near Me on leaves it exactly as it was (Reset
        // and a city are not layer choices: they may turn it off).
        if (before != null &&
            before.nearby != null &&
            path.last.control == MapFilterControl.layers &&
            state.entityType != before.entityType) {
          expect(state.nearby, before.nearby, reason: path.join(' > '));
          nearMeKeptThroughALayerChange++;
        }

        if (path.length == nearDepth) return;
        for (final next in _steps) {
          if (next.offeredAt(state.entityType)) {
            await visit([...path, next], state);
          }
        }
      }

      await visit(const <_Step>[], null);

      expect(failures.take(5).toList(), isEmpty);
      expect(failures, isEmpty);
      expect(visited, greaterThan(5000));
      expect(seenOn, contains(MapFilterControl.nearMe));
      expect(seenOn, contains(MapFilterControl.location));
      expect(nearMeKeptThroughALayerChange, greaterThan(500));
    });
  });

  group('source guards: the bar, the table and the wiring', () {
    test('the table is plain Dart that imports only the layer enum', () {
      final text = _read(_controls);
      final imports = RegExp(r"^import '([^']+)'", multiLine: true)
          .allMatches(text)
          .map((match) => match.group(1)!)
          .toList();
      expect(imports, [
        'package:broker_wallet/src/constants/location_filter.dart',
      ]);
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
        'flutter',
      ]) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });

    test('the table says, layer by layer, what the row has', () {
      final text = _squash(_read(_controls));
      for (final pinned in [
        'LocationFilter.all => _everyLayer,',
        'LocationFilter.offers => const <MapFilterControl>{ MapFilterControl.layers, MapFilterControl.location, MapFilterControl.nearMe, MapFilterControl.transaction, MapFilterControl.propertyType, MapFilterControl.price, MapFilterControl.sort, },',
        'LocationFilter.owners => const <MapFilterControl>{ MapFilterControl.layers, MapFilterControl.location, MapFilterControl.nearMe, MapFilterControl.propertyType, },',
        'LocationFilter.offices => _everyLayer,',
        'LocationFilter.watchmen => _everyLayer,',
        'static const Set<MapFilterControl> _everyLayer = <MapFilterControl>{ MapFilterControl.layers, MapFilterControl.location, MapFilterControl.nearMe, };',
      ]) {
        expect(text.contains(pinned), isTrue, reason: pinned);
      }
    });

    test(
        'the row: Layers, Location and Near Me always, the rest by the '
        'table', () {
      final bar = _squash(_read(_bar));
      expect(
        bar.contains(
          'bool has(MapFilterControl control) => MapLayerControls.shows(entity, control);',
        ),
        isTrue,
      );
      // Four conditional chips, one per layer-owned control, in the row's
      // order, each the chip it was.
      var from = 0;
      for (final step in [
        'onTap: () => _chooseEntity(context),',
        'onTap: () => _chooseLocation(context),',
        'onTap: () => _tapNearby(context),',
        'if (has(MapFilterControl.transaction)) ...[ const SizedBox(width: 8), _MapFilterChip( label: state.transaction == null',
        'onTap: () => _chooseTransaction(context), ), ],',
        'if (has(MapFilterControl.propertyType)) ...[ const SizedBox(width: 8), _MapFilterChip( label: state.propertyType == null',
        'onTap: () => _choosePropertyType(context), ), ],',
        'if (has(MapFilterControl.price)) ...[ const SizedBox(width: 8), _MapFilterChip( label: _priceLabel(state.priceRange)',
        'onTap: () => _choosePrice(context), ), ],',
        'if (has(MapFilterControl.sort)) ...[ const SizedBox(width: 8), _MapFilterChip( label: state.priceMode == MapPriceMode.all',
        'onTap: () => _chooseSort(context), ), ], ], ), );',
      ]) {
        final at = bar.indexOf(step, from);
        expect(at, greaterThanOrEqualTo(0), reason: step);
        from = at + step.length;
      }
      expect(_count(bar, 'if (has('), 4);
      // Layers, Location and Near Me are not behind a condition.
      expect(bar.contains('has(MapFilterControl.layers'), isFalse);
      expect(bar.contains('has(MapFilterControl.location'), isFalse);
      expect(bar.contains('has(MapFilterControl.nearMe'), isFalse);
      // Five chips open an option list; Near Me and Price have their own UI.
      expect(_count(bar, 'dropdown: true,'), 5);
    });

    test('the bar never decides by a layer\'s name: the table does', () {
      final build = _between(
        _read(_bar),
        'Widget build(BuildContext context) {',
        '// ---- words',
      );
      for (final kind in ['offers', 'owners', 'offices', 'watchmen']) {
        expect(build.contains('LocationFilter.$kind'), isFalse, reason: kind);
      }
      expect(build.contains('MapLayerControls.shows(entity, control)'), isTrue);
    });

    test('choosing a layer in the bar does only that', () {
      final text = _read(_bar);
      final choose = _between(
        text,
        'Future<void> _chooseEntity(BuildContext context) async {',
        '/// The Location list:',
      );
      expect(
        _count(choose, 'vm.setEntityType(choice.value ?? LocationFilter.all)'),
        1,
      );
      for (final other in [
        'setCity',
        'setAllUae',
        'enableNearby',
        'setNearbyRadius',
        'disableNearby',
        'moveToCurrentLocation',
        'clearFilters',
        'setTransaction',
        'setPropertyType',
        'setPriceRange',
        'setPriceMode',
        'animateToLocation',
        'onMessage',
        'locationFromAddress',
        'geocoding',
        'http',
      ]) {
        expect(choose.contains(other), isFalse, reason: other);
      }
    });

    test('the reset is one state transition: the layer, with Location kept',
        () {
      final state = _squash(_read(_filter));
      expect(
        state.contains(
          'MapFilterState withEntityType(LocationFilter value) { if (value == entityType) return this; final keptType = propertyType != null && MapPropertyTypeOptions.supports(value, propertyType!) ? propertyType : null; return MapFilterState( entityType: value, nearby: nearby, city: city, propertyType: keptType, ); }',
        ),
        isTrue,
      );
      // The controller makes it ONE change, and does nothing else with it.
      final controller = _squash(_read(_controller));
      expect(
        controller.contains(
          'bool setEntityType(LocationFilter type) => _change(_state.withEntityType(type));',
        ),
        isTrue,
      );
      // The view model: the same camera cause as before, no read, no device.
      final model = _squash(_read(_viewModel));
      expect(
        model.contains(
          'void setEntityType(LocationFilter type) => _afterFilterChange( _filters.setEntityType(type), MapCameraCause.filterChanged, );',
        ),
        isTrue,
      );
    });

    test('Reset is still the one it was: the state\'s own "not the default"',
        () {
      final state = _squash(_read(_filter));
      expect(
        state.contains(
          'bool get isActive => entityType != LocationFilter.all || nearby != null || city != null || propertyType != null || transaction != null || priceRange != null || priceMode != MapPriceMode.all;',
        ),
        isTrue,
      );
      expect(
        _squash(_read(_controller))
            .contains('bool get filtersActive => _state.isActive;'),
        isTrue,
      );
      expect(
        _squash(_read(_viewModel))
            .contains('bool get filtersActive => _filters.filtersActive;'),
        isTrue,
      );
    });
  });
}
