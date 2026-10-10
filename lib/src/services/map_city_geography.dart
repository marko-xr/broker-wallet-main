import 'package:broker_wallet/src/common/data/uae_city_matcher.dart';
import 'package:broker_wallet/src/services/geo_distance.dart';

/// Where the camera looks for a city, and how far in.
final class MapCityFrame {
  const MapCityFrame(this.latitude, this.longitude, this.zoom);

  final double latitude;
  final double longitude;
  final double zoom;
}

/// The one place each canonical city is, for the map's camera and for judging
/// whether a pin is in the city a record says. Keyed by the catalog's own city
/// names (a test pins the keys to `UaeAreaCatalog.supportedCities`), so there is
/// one list of cities in the app and this only says where each one is. Each is
/// the city's centre (the point a map shows for its name). Nothing is geocoded.
abstract final class MapCityCameras {
  static const Map<String, MapCityFrame> _frames = <String, MapCityFrame>{
    'Dubai': MapCityFrame(25.2048, 55.2708, 10.5),
    'Abu Dhabi': MapCityFrame(24.4539, 54.3773, 10.5),
    'Sharjah': MapCityFrame(25.3463, 55.4209, 11),
    'Ajman': MapCityFrame(25.4052, 55.5136, 12),
    'Ras Al Khaimah': MapCityFrame(25.7895, 55.9432, 10.5),
    'Fujairah': MapCityFrame(25.1288, 56.3265, 11),
    'Umm Al Quwain': MapCityFrame(25.5647, 55.5552, 11.5),
    'Al Ain': MapCityFrame(24.2075, 55.7447, 10.5),
    'Khor Fakkan': MapCityFrame(25.3395, 56.3563, 12),
  };

  /// The frame of the canonical city [name], or null for any other text.
  static MapCityFrame? of(String name) => _frames[name];

  /// The cities that have a frame.
  static Iterable<String> get cities => _frames.keys;
}

/// Whether a pin is where its record's city says.
///
/// A record's city (what it says) and its pin (where it is) are two separate
/// fields, and nothing in the form or the database ties them together: an Offer
/// can be saved as Abu Dhabi with its pin in Ajman. The app has no city borders
/// to check a pin against, so this judges only what is clear from the cities'
/// centres, and says nothing otherwise:
///
///   a pin conflicts with its city when it is NOT in that city's core and IS in
///   the core of another canonical city.
///
/// The core is the area within [coreKm] of a city's centre. A pin in its own
/// city's core is never in conflict, however near another city is (the border
/// of two cities is not judged: Sharjah's and Ajman's centres are only 11 km
/// apart, so their cores overlap). A pin far from every centre (a remote part
/// of Abu Dhabi's emirate, Hatta) is never in conflict: nothing says it is
/// somewhere else. Only a pin that is clearly in another listed city's core, and
/// outside its own city's, is a conflict.
///
/// A place in a city that lies inside the chosen city's emirate is not a
/// conflict either: a place in Al Ain may be listed as Abu Dhabi, and one in
/// Khor Fakkan as Sharjah (the nesting the city matcher already knows).
abstract final class MapCityGeography {
  /// The reach of a city's core, in kilometres from its centre.
  static const double coreKm = 15;

  /// The listed city whose core the pin is in while it is outside the core of
  /// [city], nearest first; null when the pin is in [city]'s own core, in no
  /// city's core, in the core of a city inside [city]'s emirate, or when [city]
  /// is not a listed city (nothing to judge).
  static String? otherCityAt(String city, double latitude, double longitude) {
    final own = MapCityCameras.of(city);
    if (own == null) return null;
    if (_km(own, latitude, longitude) <= coreKm) return null;

    String? nearest;
    var nearestKm = double.infinity;
    for (final name in MapCityCameras.cities) {
      if (name == city) continue;
      if (UaeCityMatcher.withinEmirateOf[name] == city) continue;
      final km = _km(MapCityCameras.of(name)!, latitude, longitude);
      if (km <= coreKm && km < nearestKm) {
        nearest = name;
        nearestKm = km;
      }
    }
    return nearest;
  }

  /// Whether the pin is clearly in a different listed city than [city].
  static bool conflicts(String? city, double latitude, double longitude) =>
      city != null && otherCityAt(city, latitude, longitude) != null;

  static double _km(MapCityFrame centre, double latitude, double longitude) =>
      GeoDistance.meters(
        centre.latitude,
        centre.longitude,
        latitude,
        longitude,
      ) /
      1000;
}
