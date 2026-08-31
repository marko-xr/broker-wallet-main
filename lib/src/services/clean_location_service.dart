import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:broker_wallet/src/services/clean_permission_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Clean location service with proper permission handling
/// Replaces direct Geolocator usage with permission-aware methods
class CleanLocationService {
  static final CleanLocationService _instance =
      CleanLocationService._internal();
  factory CleanLocationService() => _instance;
  CleanLocationService._internal();

  final CleanPermissionService _permissionService = CleanPermissionService();

  // ============================================================================
  // 📍 LOCATION METHODS WITH PERMISSION HANDLING
  // ============================================================================

  /// Get current position with permission handling
  Future<Position?> getCurrentPosition(BuildContext context) async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServiceDisabledDialog(context);
        return null;
      }

      // Request location permission
      final permission =
          await _permissionService.requestLocationPermission(context);

      if (!permission.isGranted) {
        return null;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      _showLocationErrorSnackBar(
          context, 'Failed to get location: ${e.toString()}');
      return null;
    }
  }

  /// Get current position with custom accuracy
  Future<Position?> getCurrentPositionWithAccuracy(
    BuildContext context,
    LocationAccuracy accuracy,
  ) async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServiceDisabledDialog(context);
        return null;
      }

      // Request location permission
      final permission =
          await _permissionService.requestLocationPermission(context);

      if (!permission.isGranted) {
        return null;
      }

      // Get current position with custom accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: const Duration(seconds: 15),
      );

      return position;
    } catch (e) {
      _showLocationErrorSnackBar(
          context, 'Failed to get location: ${e.toString()}');
      return null;
    }
  }

  /// Check if we have location permission without requesting it
  Future<bool> hasLocationPermission() async {
    return await _permissionService.hasLocationPermission();
  }

  /// Check if location services are enabled on device
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Get distance between two positions
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Get bearing between two positions
  double bearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.bearingBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  // ============================================================================
  // 🎯 LOCATION STREAM WITH PERMISSION HANDLING
  // ============================================================================

  /// Get position stream with permission handling (for real-time location)
  Stream<Position>? getPositionStream(BuildContext context) {
    // Note: This should be called after ensuring permissions are granted
    // Use getCurrentPosition first to handle permissions
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Only update if user moves 10 meters
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  // ============================================================================
  // 🚨 ERROR HANDLING AND USER FEEDBACK
  // ============================================================================

  /// Show dialog when location services are disabled
  void _showLocationServiceDisabledDialog(BuildContext context) {
    final loc = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_off,
                  color: Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  loc.translate('locationServiceDisabled'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.translate('locationServiceDisabledMessage'),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.translate('enableLocationServiceInstruction'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                loc.translate('cancel'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Geolocator.openLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                loc.translate('openLocationSettings'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show snackbar for location errors
  void _showLocationErrorSnackBar(BuildContext context, String message) {
    // Use Fluttertoast for lightweight feedback so this function can be
    // called from contexts that may not have a Scaffold (e.g. services).
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  // ============================================================================
  // 🔧 UTILITY METHODS
  // ============================================================================

  /// Format distance for display
  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      final km = distanceInMeters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  /// Check if two positions are within a certain radius (in meters)
  bool isWithinRadius(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    double radiusInMeters,
  ) {
    final distance = distanceBetween(lat1, lon1, lat2, lon2);
    return distance <= radiusInMeters;
  }
}
