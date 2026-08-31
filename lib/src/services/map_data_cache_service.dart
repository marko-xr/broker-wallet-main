import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';

/// Service to preload and cache map data for faster map loading
class MapDataCacheService {
  static final MapDataCacheService _instance = MapDataCacheService._internal();
  factory MapDataCacheService() => _instance;
  MapDataCacheService._internal();

  // Cache storage
  List<CachedLocationData>? _cachedLocations;
  DateTime? _lastCacheTime;
  String? _cachedUserId;

  // Track if cache was manually invalidated (data changed)
  bool _wasManuallyInvalidated = false;

  // Callback to notify when cache is invalidated
  void Function()? _onCacheInvalidated;

  // Cache validity duration (5 minutes)
  static const _cacheValidityDuration = Duration(minutes: 5);

  bool get hasValidCache {
    // If manually invalidated, cache is not valid even if it exists
    if (_wasManuallyInvalidated) return false;

    if (_cachedLocations == null || _lastCacheTime == null) return false;
    if (_cachedUserId != FirebaseAuth.instance.currentUser?.uid) return false;

    final now = DateTime.now();
    return now.difference(_lastCacheTime!) < _cacheValidityDuration;
  }

  List<CachedLocationData>? get cachedLocations {
    return hasValidCache ? _cachedLocations : null;
  }

  // Check if cache needs refresh (was invalidated)
  bool get needsRefresh => _wasManuallyInvalidated;

  /// Preload map data in the background
  Future<void> preloadMapData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // No user logged in - skipping preload (log removed)
        return;
      }

      // Starting background preload for user (log removed): ${currentUser.uid}

      final locations = <CachedLocationData>[];
      final firestore = FirebaseFirestore.instance;

      // Load all collections in parallel for speed
      final results = await Future.wait([
        firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('offers')
            .get(),
        firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('owners')
            .get(),
        firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('offices')
            .get(),
        firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('watchmen')
            .get(),
      ]);

      // Process offers
      for (final doc in results[0].docs) {
        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          locations.add(CachedLocationData(
            id: doc.id,
            title: data['specificPropertyType'] ?? 'Property Offer',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            latitude: lat,
            longitude: lng,
            type: LocationFilter.offers,
            phoneNumber: data['phoneNumber'],
            mediaUrl: data['mediaUrl'],
            mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
            additionalData: {
              'offerType': data['offerType'],
              'city': data['selectedCity'],
              'minPrice': data['minPrice'],
              'maxPrice': data['maxPrice'],
              'propertyType': data['specificPropertyType'],
            },
          ));
        }
      }

      // Process owners
      for (final doc in results[1].docs) {
        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          locations.add(CachedLocationData(
            id: doc.id,
            title: data['name'] ?? 'Property Owner',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            latitude: lat,
            longitude: lng,
            type: LocationFilter.owners,
            phoneNumber: data['phoneNumber'],
            mediaUrl: data['mediaUrl'],
            mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
            additionalData: {
              'typeOfProperties': data['typeOfProperties'],
              'propertyLocation': data['propertyLocation'],
            },
          ));
        }
      }

      // Process offices
      for (final doc in results[2].docs) {
        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          locations.add(CachedLocationData(
            id: doc.id,
            title: data['officeName'] ?? 'Real Estate Office',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            latitude: lat,
            longitude: lng,
            type: LocationFilter.offices,
            phoneNumber: data['phoneNumber'],
            additionalData: {
              'managerName': data['managerName'],
              'officeLocation': data['officeLocation'],
            },
          ));
        }
      }

      // Process watchmen
      for (final doc in results[3].docs) {
        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          locations.add(CachedLocationData(
            id: doc.id,
            title: data['name'] ?? 'Building Watchman',
            address: data['pickUpAddress'] ??
                data['pickUpLocation'] ??
                data['buildingLocation'] ??
                'No address',
            latitude: lat,
            longitude: lng,
            type: LocationFilter.watchmen,
            phoneNumber: data['phoneNumber'],
            additionalData: {
              'buildingName': data['buildingName'],
              'buildingLocation': data['buildingLocation'],
            },
          ));
        }
      }

      // Update cache
      _cachedLocations = locations;
      _lastCacheTime = DateTime.now();
      _cachedUserId = currentUser.uid;
      _wasManuallyInvalidated = false; // Reset flag after successful load

      // Preloaded ${locations.length} locations successfully (log removed)
      //   - Offers: ${locations.where((l) => l.type == LocationFilter.offers).length}
      //   - Owners: ${locations.where((l) => l.type == LocationFilter.owners).length}
      //   - Offices: ${locations.where((l) => l.type == LocationFilter.offices).length}
      //   - Watchmen: ${locations.where((l) => l.type == LocationFilter.watchmen).length}
    } catch (e) {
      // Error preloading map data (log removed): $e
      // Don't throw - let the map load data normally if preload fails
    }
  }

  /// Register a callback to be notified when cache is invalidated
  void setOnCacheInvalidatedCallback(void Function()? callback) {
    _onCacheInvalidated = callback;
  }

  /// Invalidate cache (call when data changes)
  void invalidateCache() {
    // Cache invalidated - data was modified (log removed)
    _cachedLocations = null;
    _lastCacheTime = null;
    _cachedUserId = null;
    _wasManuallyInvalidated = true; // Mark as needing refresh

    // Notify listener if registered (for when map is open)
    if (_onCacheInvalidated != null) {
      // Notifying listener of cache invalidation (log removed)
      _onCacheInvalidated!();
    }
  }

  /// Clear all cache
  void clearCache() {
    // Cache cleared (log removed)
    _cachedLocations = null;
    _lastCacheTime = null;
    _cachedUserId = null;
  }
}

/// Lightweight cached location data
class CachedLocationData {
  final String id;
  final String title;
  final String address;
  final double latitude;
  final double longitude;
  final LocationFilter type;
  final String? phoneNumber;
  final String? mediaUrl;
  final List<String> mediaUrls;
  final Map<String, dynamic> additionalData;

  CachedLocationData({
    required this.id,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.phoneNumber,
    this.mediaUrl,
    this.mediaUrls = const [],
    this.additionalData = const {},
  });

  LatLng get coordinates => LatLng(latitude, longitude);
}
