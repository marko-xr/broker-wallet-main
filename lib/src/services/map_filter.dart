import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/geo_distance.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_property_type_options.dart';

// The distance maths lives in its own plain file (the city geography needs it
// too); it is re-exported so everything that reads it from here keeps working.
export 'package:broker_wallet/src/services/geo_distance.dart';

/// The kinds of place the map shows, in the order its category selector lists
/// them. Exactly the kinds the map reads (Offers, Owners, Offices, Watchmen):
/// the selector offers these and "All", and nothing the map does not show.
abstract final class MapEntityTypes {
  static const List<LocationFilter> all = <LocationFilter>[
    LocationFilter.offers,
    LocationFilter.owners,
    LocationFilter.offices,
    LocationFilter.watchmen,
  ];
}

/// "Near me": places within [radiusKm] of where the device is.
///
/// The position lives only here, in the running app's memory, for as long as
/// the filter is on. It is never stored, sent anywhere or logged.
class NearbyFilter {
  const NearbyFilter({
    required this.latitude,
    required this.longitude,
    this.radiusKm = defaultRadiusKm,
  });

  /// The radii the selector offers, nearest first.
  static const List<int> radiusOptionsKm = <int>[5, 10, 25];

  static const int defaultRadiusKm = 10;

  final double latitude;
  final double longitude;
  final int radiusKm;

  NearbyFilter withRadius(int km) =>
      NearbyFilter(latitude: latitude, longitude: longitude, radiusKm: km);

  @override
  bool operator ==(Object other) =>
      other is NearbyFilter &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(latitude, longitude, radiusKm);
}

/// How the places are ordered by price. Not a filter on a backend field: a way
/// of ranking what is already loaded.
enum MapPriceMode {
  /// The map as it is: every place, no price involved.
  all,

  /// Places with a usable price first, lowest to highest; others last.
  lowest,

  /// Places with a usable price first, highest to lowest; others last.
  highest,
}

/// Inclusive bounds on an Offer's comparable price. Both may be absent only
/// when there is no range at all (represented by null in [MapFilterState]).
class MapPriceRange {
  const MapPriceRange._(this.min, this.max);

  final double? min;
  final double? max;

  static final RegExp _numeric = RegExp(r'^\d+(\.\d+)?$');

  /// A UI entry, or null for an empty/invalid entry. Arabic keyboards may
  /// enter Arabic-Indic digits and their decimal mark.
  static double? parseBound(String text) {
    final normalized = String.fromCharCodes(text.trim().runes.map((digit) {
      if (digit >= 0x0660 && digit <= 0x0669) return digit - 0x0660 + 0x30;
      if (digit >= 0x06F0 && digit <= 0x06F9) return digit - 0x06F0 + 0x30;
      if (digit == 0x066B) return 0x2E;
      return digit;
    }));
    if (!_numeric.hasMatch(normalized)) return null;
    final value = double.tryParse(normalized);
    return value != null && value.isFinite ? value : null;
  }

  /// Null clears the range. Invalid programmatic bounds cannot enter state.
  static MapPriceRange? fromBounds({double? min, double? max}) {
    if (min == null && max == null) return null;
    if ((min != null && (!min.isFinite || min < 0)) ||
        (max != null && (!max.isFinite || max < 0)) ||
        (min != null && max != null && min > max)) {
      throw ArgumentError('Invalid price range');
    }
    return MapPriceRange._(min, max);
  }

  @override
  bool operator ==(Object other) =>
      other is MapPriceRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Everything the person has chosen to narrow the map by. Immutable: a choice
/// makes a new state. The default state ([initial]) restricts nothing.
class MapFilterState {
  const MapFilterState({
    this.entityType = LocationFilter.all,
    this.nearby,
    this.city,
    this.propertyType,
    this.transaction,
    this.priceRange,
    this.priceMode = MapPriceMode.all,
  });

  static const MapFilterState initial = MapFilterState();

  /// [LocationFilter.all]: every kind.
  ///
  /// The layer owns [transaction], [propertyType], [priceRange] and
  /// [priceMode]. Choosing another layer clears incompatible choices.
  final LocationFilter entityType;

  /// Near Me: null means no distance restriction.
  ///
  /// Near Me and [city] are two ways of saying where the map looks, so they
  /// exclude each other: [withNearby] with a position clears the city, and
  /// [withCity] with a city clears Near Me. There is never a city AND a circle
  /// around the device.
  final NearbyFilter? nearby;

  /// A city of the UAE catalog; null: every city. Excludes [nearby] (see there).
  final String? city;

  /// A property-type key; null: every type.
  final String? propertyType;

  /// Null: rent and sale.
  final MapTransaction? transaction;

  /// An inclusive Offer price filter; null means no price restriction.
  final MapPriceRange? priceRange;

  /// [MapPriceMode.all]: no price ordering.
  final MapPriceMode priceMode;

  bool get nearbyEnabled => nearby != null;

  /// Whether anything narrows the map. Every part of it is one the person can
  /// see: a layer's own filters are cleared when the layer changes, so none of
  /// them is on while its control is not in the row.
  bool get isActive =>
      entityType != LocationFilter.all ||
      nearby != null ||
      city != null ||
      propertyType != null ||
      transaction != null ||
      priceRange != null ||
      priceMode != MapPriceMode.all;

  /// Another layer clears Offer-only choices in this one state change.
  /// Property Type survives Offers ↔ Owners only for a key in both canonical
  /// vocabularies. Where the map looks ([nearby] and [city]) stays as it is.
  /// Choosing the layer that is already chosen changes nothing.
  MapFilterState withEntityType(LocationFilter value) {
    if (value == entityType) return this;
    final keptType = propertyType != null &&
            MapPropertyTypeOptions.supports(value, propertyType!)
        ? propertyType
        : null;
    return MapFilterState(
      entityType: value,
      nearby: nearby,
      city: city,
      propertyType: keptType,
    );
  }

  /// Near Me on at [value] replaces any city; null turns Near Me off and leaves
  /// the city as it is.
  MapFilterState withNearby(NearbyFilter? value) => MapFilterState(
        entityType: entityType,
        nearby: value,
        city: value == null ? city : null,
        propertyType: propertyType,
        transaction: transaction,
        priceRange: priceRange,
        priceMode: priceMode,
      );

  /// A city replaces Near Me; null means every city and leaves Near Me as it is.
  MapFilterState withCity(String? value) => MapFilterState(
        entityType: entityType,
        nearby: value == null ? nearby : null,
        city: value,
        propertyType: propertyType,
        transaction: transaction,
        priceRange: priceRange,
        priceMode: priceMode,
      );

  MapFilterState withPropertyType(String? value) => MapFilterState(
        entityType: entityType,
        nearby: nearby,
        city: city,
        propertyType: value,
        transaction: transaction,
        priceRange: priceRange,
        priceMode: priceMode,
      );

  MapFilterState withTransaction(MapTransaction? value) => MapFilterState(
        entityType: entityType,
        nearby: nearby,
        city: city,
        propertyType: propertyType,
        transaction: value,
        priceRange: priceRange,
        priceMode: priceMode,
      );

  MapFilterState withPriceRange(MapPriceRange? value) => MapFilterState(
        entityType: entityType,
        nearby: nearby,
        city: city,
        propertyType: propertyType,
        transaction: transaction,
        priceRange: value,
        priceMode: priceMode,
      );

  MapFilterState withPriceMode(MapPriceMode value) => MapFilterState(
        entityType: entityType,
        nearby: nearby,
        city: city,
        propertyType: propertyType,
        transaction: transaction,
        priceRange: priceRange,
        priceMode: value,
      );

  @override
  bool operator ==(Object other) =>
      other is MapFilterState &&
      other.entityType == entityType &&
      other.nearby == nearby &&
      other.city == city &&
      other.propertyType == propertyType &&
      other.transaction == transaction &&
      other.priceRange == priceRange &&
      other.priceMode == priceMode;

  @override
  int get hashCode => Object.hash(
        entityType,
        nearby,
        city,
        propertyType,
        transaction,
        priceRange,
        priceMode,
      );
}

/// Which places a [MapFilterState] lets through, and in what order.
///
/// Every active restriction must hold (AND). A restriction that is not set
/// restricts nothing; one that is set excludes every place that cannot satisfy
/// it, including a place that simply has no such field. Sorting never excludes
/// a place; unpriced Offers appear after priced Offers.
///
/// A city is a place's city AND its pin: a place whose city says Abu Dhabi but
/// whose pin is clearly in Ajman ([CachedLocationData.cityConflict]) is not an
/// Abu Dhabi place, and is not shown as one. It still shows with every city.
abstract final class MapFilterEngine {
  static bool matches(CachedLocationData place, MapFilterState state) {
    if (state.entityType != LocationFilter.all &&
        place.type != state.entityType) {
      return false;
    }
    if (state.city != null &&
        (place.city != state.city || place.cityConflict)) {
      return false;
    }
    if (state.propertyType != null &&
        place.propertyType != state.propertyType) {
      return false;
    }
    if (state.transaction != null && place.transaction != state.transaction) {
      return false;
    }
    final range = state.priceRange;
    if (range != null) {
      if (!_hasPrice(place)) return false;
      final price = place.price!;
      if ((range.min != null && price < range.min!) ||
          (range.max != null && price > range.max!)) return false;
    }
    final nearby = state.nearby;
    if (nearby != null && !_within(place, nearby)) return false;
    return true;
  }

  /// The places [state] lets through. Price ordering keeps unpriced places
  /// last; equal prices and unpriced places keep their load order.
  static List<CachedLocationData> apply(
    Iterable<CachedLocationData> places,
    MapFilterState state,
  ) {
    if (!state.isActive) return List<CachedLocationData>.of(places);
    final kept = [
      for (final place in places)
        if (matches(place, state)) place,
    ];
    switch (state.priceMode) {
      case MapPriceMode.all:
        return kept;
      case MapPriceMode.lowest:
        return _byPrice(kept, highestFirst: false);
      case MapPriceMode.highest:
        return _byPrice(kept, highestFirst: true);
    }
  }

  /// A price that can rank a place: a real amount above zero. (The mapper only
  /// ever produces one, and this keeps the rule here too.)
  static bool _hasPrice(CachedLocationData place) {
    final price = place.price;
    return price != null && price.isFinite && price > 0;
  }

  /// Sorted by price, then unpriced, with load order for equal/unpriced places.
  static List<CachedLocationData> _byPrice(
    List<CachedLocationData> places, {
    required bool highestFirst,
  }) {
    final indexes = <int>[for (var i = 0; i < places.length; i++) i];
    indexes.sort((a, b) {
      final aHasPrice = _hasPrice(places[a]);
      final bHasPrice = _hasPrice(places[b]);
      if (aHasPrice != bHasPrice) return aHasPrice ? -1 : 1;
      if (!aHasPrice) return a.compareTo(b);
      final byPrice = highestFirst
          ? places[b].price!.compareTo(places[a].price!)
          : places[a].price!.compareTo(places[b].price!);
      return byPrice != 0 ? byPrice : a.compareTo(b);
    });
    return [for (final index in indexes) places[index]];
  }

  /// A place without a usable position cannot be near anything.
  static bool _within(CachedLocationData place, NearbyFilter nearby) {
    if (!MapLocationMapper.isUsableCoordinate(
      place.latitude,
      place.longitude,
    )) {
      return false;
    }
    final meters = GeoDistance.meters(
      nearby.latitude,
      nearby.longitude,
      place.latitude,
      place.longitude,
    );
    return meters <= nearby.radiusKm * 1000.0;
  }
}

/// What the map's selectors offer.
abstract final class MapFilterOptions {
  /// Every city of the catalog the Request, Offer and Owner forms use, in the
  /// catalog's order. It does not depend on which places are loaded: a city
  /// nobody has a place in is still a choice (and filters to "no matches").
  static List<String> cities() => UaeAreaCatalog.supportedCities;

  /// How many loaded places there are of each kind the selector lists.
  static Map<LocationFilter, int> entityCounts(
    Iterable<CachedLocationData> places,
  ) {
    final counts = <LocationFilter, int>{
      for (final type in MapEntityTypes.all) type: 0,
    };
    for (final place in places) {
      final current = counts[place.type];
      if (current != null) counts[place.type] = current + 1;
    }
    return counts;
  }
}
