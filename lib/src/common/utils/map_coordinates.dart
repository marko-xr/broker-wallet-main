/// Geographic validity for Details previews and external map navigation.
class MapCoordinates {
  MapCoordinates._();

  static bool isValid(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    // Preserve the app's existing rejection of an unset Null Island location.
    return latitude != 0 || longitude != 0;
  }
}
