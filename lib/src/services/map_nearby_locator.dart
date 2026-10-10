import 'package:broker_wallet/src/services/map_filter_controller.dart';

/// Whether the app may use the device's location.
enum DevicePermission {
  granted,

  /// Not allowed yet, or refused once: the system may still ask.
  denied,

  /// Refused for good (or restricted): the system will not ask again, so the
  /// app does not either.
  permanentlyDenied,
}

/// A position, in plain numbers. Never stored, sent or logged.
///
/// A position the system already held carries when it was taken and how
/// accurate it is, so a caller can tell a fresh one from a stale one.
final class DevicePoint {
  const DevicePoint(
    this.latitude,
    this.longitude, {
    this.takenAt,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// When the system took this position, when it says.
  final DateTime? takenAt;

  /// How far off it may be, in metres, when the system says.
  final double? accuracyMeters;
}

/// What the map needs from the phone's location features. The real one
/// ([PluginDeviceLocationPlatform]) talks to the system; a test passes its own.
///
/// None of it shows a screen of the app's own. The only prompt there is is the
/// operating system's, from [requestPermission].
abstract interface class DeviceLocationPlatform {
  /// Whether the device's location services are switched on.
  Future<bool> servicesEnabled();

  /// The permission as it stands. Never asks.
  Future<DevicePermission> permission();

  /// Asks, with the operating system's own permission prompt.
  Future<DevicePermission> requestPermission();

  /// The position the system already holds, or null when it holds none. It
  /// takes no new fix: it answers at once, with when the position was taken and
  /// how accurate it is.
  Future<DevicePoint?> lastKnownPosition();

  /// Where the device is now: waits for a new fix. [precise] asks for a fine
  /// one (the camera zooms to the street); otherwise a rough one is enough.
  /// Throws when there is no position (a timeout, or the platform failed).
  Future<DevicePoint> position({required bool precise});
}

/// Where the device is, for the map's "my location" button and its Nearby
/// filter. The one place that decides how the map gets a position:
///
///     services on?  ->  permission known?  ->  ask the system only if it can
///                   ->  a recent position the system holds (Nearby only)
///                   ->  otherwise a new fix
///
/// It is built, and [locate] called, only after a tap on one of those two
/// controls; opening the map never asks for location. Nothing here shows a
/// dialog or a message: it has no screen to show one on. Everything that can go
/// wrong becomes a [NearbyFix] the screen words in the person's language, never
/// an exception and never a platform message. A permission that is refused for
/// good is reported, not asked for again.
///
/// A new fix takes seconds (the system waits for one). Nearby only needs a rough
/// position, so when the system already holds a position that is recent and
/// accurate enough ([maxRecentAge], [maxRecentAccuracyMeters]: an error far
/// below the smallest radius, 5 km), that one is used at once. Anything older,
/// less accurate, or with no time or accuracy to judge it by is never used: a
/// new fix is waited for instead. "My location" is precise and never takes this
/// shortcut.
///
/// Taps that arrive while a request is running share it: one permission prompt
/// and one new fix, however many times it is tapped.
class DeviceNearbyLocator implements NearbyLocator {
  DeviceNearbyLocator(
    this._device, {
    this.precise = false,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// The oldest position the system held that Nearby will use.
  static const Duration maxRecentAge = Duration(seconds: 60);

  /// The least accurate position the system held that Nearby will use: a tenth
  /// of the smallest radius.
  static const double maxRecentAccuracyMeters = 500;

  final DeviceLocationPlatform _device;

  /// A fine position instead of a rough one.
  final bool precise;

  final DateTime Function() _now;

  Future<NearbyFix>? _running;

  @override
  Future<NearbyFix> locate() => _running ??= _locate().whenComplete(() {
        _running = null;
      });

  Future<NearbyFix> _locate() async {
    try {
      if (!await _device.servicesEnabled()) return const NearbyServicesOff();

      var permission = await _device.permission();
      if (permission == DevicePermission.permanentlyDenied) {
        return const NearbyPermanentlyDenied();
      }
      if (permission != DevicePermission.granted) {
        permission = await _device.requestPermission();
        if (permission == DevicePermission.permanentlyDenied) {
          return const NearbyPermanentlyDenied();
        }
        if (permission != DevicePermission.granted) {
          return const NearbyDenied();
        }
      }

      if (!precise) {
        final recent = await _recentPosition();
        if (recent != null) {
          return NearbyLocated(recent.latitude, recent.longitude);
        }
      }

      final point = await _device.position(precise: precise);
      return NearbyLocated(point.latitude, point.longitude);
    } catch (_) {
      return const NearbyUnavailable();
    }
  }

  /// The position the system holds, if it is recent and accurate enough to use
  /// for Nearby; otherwise null.
  Future<DevicePoint?> _recentPosition() async {
    try {
      final held = await _device.lastKnownPosition();
      if (held == null) return null;
      final takenAt = held.takenAt;
      final accuracy = held.accuracyMeters;
      // Nothing to judge it by: not used.
      if (takenAt == null || accuracy == null) return null;
      if (accuracy.isNaN ||
          accuracy <= 0 ||
          accuracy > maxRecentAccuracyMeters) {
        return null;
      }
      final age = _now().difference(takenAt);
      // A time in the future is a wrong clock, not a fresh position.
      if (age.isNegative || age > maxRecentAge) return null;
      return held;
    } catch (_) {
      return null;
    }
  }
}
