import 'package:broker_wallet/src/constants/location_filter.dart';

/// The controls of the map's filter row.
enum MapFilterControl {
  /// Which layer of the map is shown: Offers, Owners, Offices or Watchmen.
  layers,

  /// Where the map looks: all of the UAE, or one of its cities.
  location,

  /// Near Me: the places within 5, 10 or 25 km of the device.
  nearMe,

  /// Rent / Sale.
  transaction,

  /// Property Type.
  propertyType,

  /// Inclusive Offer price range.
  price,

  /// Sort: the order the places come in (today, by price).
  sort,
}

/// Which controls the filter row has for the layer that is chosen.
///
/// The row is contextual: a control that does not apply to a layer is not
/// there. Every layer has Layers, Location and Near Me, since which layer to
/// show and where to look (a city, or around the device) are asked of any map.
/// The other four belong to a kind of place, and the map's own
/// data decides who has what (see `MapLocationMapper`):
///
///  * Rent / Sale: only an Offer has a transaction.
///  * Price: only an Offer has a comparable price to filter by.
///  * Sort: only an Offer has a price to order by.
///  * Property Type: an Offer has one and so does an Owner (its type of
///    properties). An Office and a Watchman have none.
///
/// All Layers has none of the four. With every kind on the map, a choice such
/// as Rent would quietly take whole kinds off it (only an Offer can be rented),
/// so those choices are made inside the layer they belong to.
///
/// A control that is not shown must never be on: `MapFilterState.withEntityType`
/// clears incompatible choices whenever the layer changes, so a choice
/// never outlives the row that offered it, and Reset can never stay on for a
/// filter the person cannot see. Where the map looks (Location and Near Me) is
/// not a layer's business and is never touched by a change of layer.
abstract final class MapLayerControls {
  static const Set<MapFilterControl> _everyLayer = <MapFilterControl>{
    MapFilterControl.layers,
    MapFilterControl.location,
    MapFilterControl.nearMe,
  };

  /// The controls the row has for [layer].
  static Set<MapFilterControl> of(LocationFilter layer) => switch (layer) {
        LocationFilter.all => _everyLayer,
        LocationFilter.offers => const <MapFilterControl>{
            MapFilterControl.layers,
            MapFilterControl.location,
            MapFilterControl.nearMe,
            MapFilterControl.transaction,
            MapFilterControl.propertyType,
            MapFilterControl.price,
            MapFilterControl.sort,
          },
        LocationFilter.owners => const <MapFilterControl>{
            MapFilterControl.layers,
            MapFilterControl.location,
            MapFilterControl.nearMe,
            MapFilterControl.propertyType,
          },
        LocationFilter.offices => _everyLayer,
        LocationFilter.watchmen => _everyLayer,
      };

  /// Whether the row has [control] for [layer].
  static bool shows(LocationFilter layer, MapFilterControl control) =>
      of(layer).contains(control);
}
