import 'dart:async';

import 'package:broker_wallet/src/common/utils/coalesced_runner.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';

/// Where the map gets its places: the signed-in user's own Offers, Owners,
/// Offices and Watchmen that have a position.
abstract interface class MapLocationSource {
  /// The signed-in user's id, or null when nobody is signed in. Places read for
  /// one user are never shown to another.
  String? get currentUserId;

  /// Reads the places now. Throws when they cannot be read: the caller decides
  /// what the person is told, and a failed read is never "no places".
  Future<List<CachedLocationData>> load();

  /// Signals that the user's own records changed somewhere in the app, so what
  /// was read is out of date.
  Stream<void> get changes;
}

/// What the loader keeps the last read in, so the map opens with it at once.
abstract interface class MapPlacesCache {
  /// The last read, when it is still good: the same user, not old, and nothing
  /// changed since. Null otherwise.
  List<CachedLocationData>? get valid;

  /// Counts the times the user's data was reported changed.
  int get generation;

  /// Keeps [places] as [userId]'s, unless the data changed after the read that
  /// produced them started at [generation].
  void store(
    String userId,
    List<CachedLocationData> places, {
    required int generation,
  });
}

/// Gets the map its places and keeps them current.
///
///  * [start] shows the last read at once when it is still good; otherwise it
///    reads.
///  * Whenever the user's own data changes, the places are read again — one
///    read at a time, and one more after it if more changes came in meanwhile.
///  * What a read found is shown only if the same user is still signed in and
///    the screen is still there.
///  * A failed read is reported through [onFailed]; it never shows "no places",
///    and the caller decides what a map that already has places does with it.
class MapPlacesLoader {
  MapPlacesLoader({
    required MapLocationSource source,
    required MapPlacesCache cache,
    required this.onPlaces,
    required this.onFailed,
  })  : _source = source,
        _cache = cache {
    _runner = CoalescedRunner(_read);
  }

  final MapLocationSource _source;
  final MapPlacesCache _cache;

  /// Shows the places. [fresh] is true for what a read just found, false for
  /// what the cache already held.
  final Future<void> Function(
    List<CachedLocationData> places, {
    required bool fresh,
  }) onPlaces;

  /// A read could not be completed.
  final void Function() onFailed;

  late final CoalescedRunner _runner;
  StreamSubscription<void>? _changes;
  bool _disposed = false;

  /// Opens the map's data: the cache when it is good, else a read, and a read
  /// after every change from now on.
  Future<void> start() async {
    if (_disposed) return;

    // Listen before the first read starts: a change that lands while it is in
    // flight asks for one more read instead of being missed.
    _changes = _source.changes.listen((_) {
      if (!_disposed) unawaited(_runner.run());
    });

    final cached = _cache.valid;
    if (cached != null && _source.currentUserId != null) {
      await onPlaces(cached, fresh: false);
      return;
    }
    await _runner.run();
  }

  /// Reads the places again now (or after the read in progress).
  Future<void> refresh() => _runner.run();

  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    _changes = null;
  }

  Future<void> _read() async {
    if (_disposed) return;

    final userId = _source.currentUserId;
    if (userId == null || userId.isEmpty) {
      onFailed();
      return;
    }

    final generation = _cache.generation;
    final List<CachedLocationData> places;
    try {
      places = await _source.load();
    } catch (_) {
      if (!_disposed) onFailed();
      return;
    }
    // Nothing it read is shown if the screen is gone or another account is
    // signed in now.
    if (_disposed || _source.currentUserId != userId) return;

    _cache.store(userId, places, generation: generation);
    await onPlaces(places, fresh: true);
  }
}
