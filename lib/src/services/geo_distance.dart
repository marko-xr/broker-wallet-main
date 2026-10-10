import 'dart:math' as math;

/// Distance on the Earth's surface.
abstract final class GeoDistance {
  /// The mean radius of the Earth, in metres (IUGG).
  static const double earthRadiusMeters = 6371008.8;

  /// The great-circle distance between two points, in metres (haversine).
  static double meters(double lat1, double lng1, double lat2, double lng2) {
    final phi1 = _radians(lat1);
    final phi2 = _radians(lat2);
    final deltaPhi = _radians(lat2 - lat1);
    final deltaLambda = _radians(lng2 - lng1);
    final a = math.pow(math.sin(deltaPhi / 2), 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.pow(math.sin(deltaLambda / 2), 2);
    // Rounding can push `a` a hair past 1 for opposite points.
    final clamped = math.min(1.0, math.max(0.0, a.toDouble()));
    return 2 * earthRadiusMeters * math.asin(math.sqrt(clamped));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
