import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Gets the Google Maps SDK ready before the person opens the map.
///
/// The first time a map is shown in a run of the app, the Android SDK loads
/// itself on the phone's main thread, and that blocks it for a moment (the
/// plugin's own README says so). Flutter's frames are paced by that same thread,
/// so whatever is on screen then (the page sliding in) stalls and then jumps:
/// that is the flicker on opening the map. The plugin offers `warmup()` to do
/// that work at a moment of the app's choosing, and this is that moment: a few
/// seconds after the app is up, in the background, where nothing is animating
/// that the person is waiting on.
///
/// Android only (nothing else has this cost). It changes nothing the map shows
/// and reads nothing: if it cannot run, the map still works, as before, and
/// does that work when it first opens.
abstract final class MapSdkWarmup {
  /// How long after the app is up the warm-up waits, so it does not compete with
  /// the first screens being built.
  static const Duration defaultDelay = Duration(seconds: 3);

  static Future<void>? _started;

  /// Starts the warm-up, once. A second call returns the first one's result.
  /// Never throws; callers do not wait for it.
  ///
  /// [warmup] and [isAndroid] are for tests; the app gives neither.
  static Future<void> start({
    Duration after = defaultDelay,
    Future<void> Function()? warmup,
    bool? isAndroid,
  }) {
    return _started ??= _run(after, warmup ?? _warmUpAndroid, isAndroid);
  }

  /// Forgets that the warm-up ran, so a test can start it again.
  @visibleForTesting
  static void debugReset() => _started = null;

  static Future<void> _run(
    Duration after,
    Future<void> Function() warmup,
    bool? isAndroid,
  ) async {
    try {
      final android = isAndroid ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
      if (!android) return;
      await Future<void>.delayed(after);
      await warmup();
    } catch (_) {
      // Not worth telling anyone: the map opens either way.
    }
  }

  static Future<void> _warmUpAndroid() async {
    final platform = GoogleMapsFlutterPlatform.instance;
    if (platform is GoogleMapsFlutterAndroid) await platform.warmup();
  }
}
