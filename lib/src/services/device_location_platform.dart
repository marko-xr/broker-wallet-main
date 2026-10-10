import 'package:broker_wallet/src/services/map_nearby_locator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// The phone's location features, for the map: the system's permission and the
/// device's position, and nothing else. It has no screen: the only prompt it
/// can cause is the operating system's own permission sheet, and only
/// [requestPermission] causes it.
class PluginDeviceLocationPlatform implements DeviceLocationPlatform {
  const PluginDeviceLocationPlatform();

  @override
  Future<bool> servicesEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<DevicePermission> permission() async =>
      _read(await Permission.locationWhenInUse.status);

  @override
  Future<DevicePermission> requestPermission() async =>
      _read(await Permission.locationWhenInUse.request());

  @override
  Future<DevicePoint?> lastKnownPosition() async {
    // The system's cached position: no new fix, so it answers at once (or with
    // nothing).
    final held = await Geolocator.getLastKnownPosition();
    if (held == null) return null;
    return DevicePoint(
      held.latitude,
      held.longitude,
      takenAt: held.timestamp,
      accuracyMeters: held.accuracy,
    );
  }

  @override
  Future<DevicePoint> position({required bool precise}) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        // A rough fix is quicker and kinder to the battery, and enough for a
        // radius of 5 km or more; the camera that zooms to the street wants a
        // fine one.
        accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ),
    );
    return DevicePoint(position.latitude, position.longitude);
  }

  static DevicePermission _read(PermissionStatus status) {
    if (status.isGranted) return DevicePermission.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return DevicePermission.permanentlyDenied;
    }
    return DevicePermission.denied;
  }
}
