import 'dart:async';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

export 'package:broker_wallet/src/services/map_location_data.dart'
    show CachedLocationData;

/// A place's position as the map draws it.
extension CachedLocationCoordinates on CachedLocationData {
  LatLng get coordinates => LatLng(latitude, longitude);
}

/// Keeps the map's places between visits, so the map opens with them at once.
///
/// What is kept belongs to one user and is trusted for [_cacheValidityDuration]
/// unless the user's own data changed since: every core-entity change anywhere
/// in the app (Supabase) invalidates it, and so does a call to
/// [invalidateCache] (the legacy services).
class MapDataCacheService implements MapPlacesCache {
  static final MapDataCacheService _instance = MapDataCacheService._internal();
  factory MapDataCacheService() => _instance;
  MapDataCacheService._internal() {
    // A save, an edit or a delete of an Offer, Owner, Office or Watchman:
    // the Supabase save paths do not call [invalidateCache] themselves.
    _mutations = CoreEntityMutationNotifier.changes.listen(
      (_) => invalidateCache(),
    );
  }

  // The process-wide singleton listens for the whole life of the app.
  // ignore: unused_field
  late final StreamSubscription<void> _mutations;

  // Cache storage
  List<CachedLocationData>? _cachedLocations;
  DateTime? _lastCacheTime;
  String? _cachedUserId;

  // Track if cache was manually invalidated (data changed)
  bool _wasManuallyInvalidated = false;

  /// Counts the times the data was reported changed. A read remembers the count
  /// it started at and is kept only if the count is still the same when it
  /// finishes: a read that raced a change must not be trusted.
  int _generation = 0;

  @override
  int get generation => _generation;

  // Callback to notify when cache is invalidated
  void Function()? _onCacheInvalidated;

  // Cache validity duration (5 minutes)
  static const _cacheValidityDuration = Duration(minutes: 5);

  bool get hasValidCache {
    // If manually invalidated, cache is not valid even if it exists
    if (_wasManuallyInvalidated) return false;

    if (_cachedLocations == null || _lastCacheTime == null) return false;
    if (_cachedUserId !=
        RepositoryProvider.instance.authRepository.currentUserId) {
      return false;
    }

    final now = DateTime.now();
    return now.difference(_lastCacheTime!) < _cacheValidityDuration;
  }

  List<CachedLocationData>? get cachedLocations {
    return hasValidCache ? _cachedLocations : null;
  }

  @override
  List<CachedLocationData>? get valid => cachedLocations;

  // Check if cache needs refresh (was invalidated)
  bool get needsRefresh => _wasManuallyInvalidated;

  /// Keeps [places] as [userId]'s, unless the data changed after the read that
  /// produced them started at [generation].
  @override
  void store(
    String userId,
    List<CachedLocationData> places, {
    required int generation,
  }) {
    if (generation != _generation) return;
    _cachedLocations = List<CachedLocationData>.unmodifiable(places);
    _lastCacheTime = DateTime.now();
    _cachedUserId = userId;
    _wasManuallyInvalidated = false; // Reset flag after a successful load
  }

  /// Kept for the callers that ask for a preload at startup and at sign-in:
  /// there is nothing to preload. The map reads its places from Supabase when it
  /// opens, and keeps them here for the next visit.
  Future<void> preloadMapData() async {}

  /// Register a callback to be notified when cache is invalidated
  void setOnCacheInvalidatedCallback(void Function()? callback) {
    _onCacheInvalidated = callback;
  }

  /// Invalidate cache (call when data changes)
  void invalidateCache() {
    _generation++;
    _cachedLocations = null;
    _lastCacheTime = null;
    _cachedUserId = null;
    _wasManuallyInvalidated = true; // Mark as needing refresh

    // Notify listener if registered (for when map is open)
    _onCacheInvalidated?.call();
  }

  /// Clear all cache
  void clearCache() {
    _generation++;
    _cachedLocations = null;
    _lastCacheTime = null;
    _cachedUserId = null;
  }
}
