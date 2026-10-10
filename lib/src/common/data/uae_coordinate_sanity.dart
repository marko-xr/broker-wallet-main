/// A coarse, country-level sanity check on a position: could it reasonably be
/// inside the UAE?
///
/// It answers only that. It does not say which emirate or city a position is in
/// (that is `MapCityGeography`'s own, separate and equally coarse job), it is not
/// a border, and it holds no polygon. It is one rectangle, deliberately generous:
/// at least half a degree (about 55 km) beyond the UAE's own extremes on every
/// side, which are roughly 22.6 to 26.1 degrees north and 51.6 to 56.4 degrees
/// east. So it admits a strip of the countries around the edge (Qatar, Bahrain,
/// northern Oman, a corner of Saudi Arabia) and turns away only what is plainly
/// elsewhere: Egypt, Riyadh, Muscat, Bandar Abbas, Mumbai, or a latitude and a
/// longitude the wrong way round.
///
/// It is not the map's opening camera box (`UaeMapFraming`): that one frames the
/// nine cities and leaves out the Western Region on purpose, while this one must
/// include every part of the country.
///
/// A position that fails is not rewritten, deleted or reported as an error
/// anywhere: the Map does not draw it, and a pickup location chosen on the map
/// is not accepted. Nothing stored changes.
///
/// Plain Dart: no widget, no backend, no logging.
abstract final class UaeCoordinateSanity {
  /// The rectangle's edges, in degrees.
  static const double south = 22.0;
  static const double north = 26.6;
  static const double west = 50.5;
  static const double east = 57.0;

  /// Whether [latitude], [longitude] could be in the UAE. A position that is not
  /// a number, or is not finite, never could.
  static bool couldBeInUae(double latitude, double longitude) =>
      latitude >= south &&
      latitude <= north &&
      longitude >= west &&
      longitude <= east;
}
