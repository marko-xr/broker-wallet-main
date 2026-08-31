import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Enums for filtering (import from viewmodel)
enum LocationFilter { all, offers, owners, offices, watchmen }

/// Utility class for consistent location colors across the app
/// This ensures map markers and filter chips use the same colors
class LocationColors {
  // Private constructor to prevent instantiation
  LocationColors._();

  // Color constants for each location type
  static const Color offersColor = Color(0xFF4CAF50); // Green
  static const Color ownersColor = Color(0xFFFF9800); // Blue
  static const Color officesColor = Color(0xFF2196F3); // Orange
  static const Color watchmenColor = Color(0xFFD7C502); // Yellow
  static const Color allColor = Color(0xFFF44336); // Red

  /// Get the color for a specific location type
  static Color getColor(LocationFilter type) {
    switch (type) {
      case LocationFilter.offers:
        return offersColor;
      case LocationFilter.owners:
        return ownersColor;
      case LocationFilter.offices:
        return officesColor;
      case LocationFilter.watchmen:
        return watchmenColor;
      case LocationFilter.all:
        return allColor;
    }
  }

  /// Get the closest marker hue for Google Maps markers
  /// This ensures visual consistency between filter chips and map markers
  static double getMarkerHue(LocationFilter type) {
    switch (type) {
      case LocationFilter.offers:
        return BitmapDescriptor.hueGreen;
      case LocationFilter.owners:
        return BitmapDescriptor.hueOrange;
      case LocationFilter.offices:
        return BitmapDescriptor.hueBlue;
      case LocationFilter.watchmen:
        return BitmapDescriptor.hueYellow;
      case LocationFilter.all:
        return BitmapDescriptor.hueRed;
    }
  }

  /// Get a list of all available colors
  static List<Color> getAllColors() {
    return [
      offersColor,
      ownersColor,
      officesColor,
      watchmenColor,
      allColor,
    ];
  }

  /// Get a list of all location types
  static List<LocationFilter> getAllTypes() {
    return LocationFilter.values;
  }
}
