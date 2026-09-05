import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:broker_wallet/src/services/clean_location_service.dart';
import 'package:broker_wallet/src/services/clean_permission_service.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';
import 'package:broker_wallet/src/Views/Widgets/custom_map_pin.dart';
import 'dart:async';

// Enums for filtering - now imported from location_colors.dart

// Data models
class LocationInfo {
  final String id;
  final String title;
  final String address;
  final LatLng coordinates;
  final LocationFilter type;
  final Color color;
  final IconData? icon;
  final String? iconAsset;
  final String? phoneNumber;
  final String? mediaUrl;
  final List<String> mediaUrls;
  final Map<String, dynamic> additionalData;

  LocationInfo({
    required this.id,
    required this.title,
    required this.address,
    required this.coordinates,
    required this.type,
    required this.color,
    this.icon,
    this.iconAsset,
    this.phoneNumber,
    this.mediaUrl,
    this.mediaUrls = const [],
    this.additionalData = const {},
  });
}

// Model for clustered locations (multiple items at same coordinates)
class ClusteredLocationInfo {
  final LatLng coordinates;
  final List<LocationInfo> items;
  int activeIndex;

  ClusteredLocationInfo({
    required this.coordinates,
    required this.items,
    this.activeIndex = 0,
  });

  LocationInfo get activeItem => items[activeIndex];

  bool get hasMultipleItems => items.length > 1;

  int get itemCount => items.length;

  // Helper to create a coordinate key for grouping
  static String coordinateKey(LatLng coords) {
    // Round to 3 decimal places (~111m precision) to group items in same building
    // This handles slight GPS variations from mobile devices
    final lat = (coords.latitude * 1000).round() / 1000;
    final lng = (coords.longitude * 1000).round() / 1000;
    final key = '$lat,$lng';
    // Debug log suppressed: Coordinate key for ${coords.latitude},${coords.longitude}: $key
    return key;
  }
}

class MapViewViewModel extends ChangeNotifier {
  // Add disposal tracking
  bool _disposed = false;
  bool get disposed => _disposed;

  // State management
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // Location permission tracking
  bool _hasLocationPermission = false;
  bool get hasLocationPermission => _hasLocationPermission;

  // Map configuration
  MapType _mapType = MapType.hybrid;
  MapType get mapType => _mapType;

  GoogleMapController? _mapController;

  // Default camera position (Dubai, UAE)
  final CameraPosition initialCameraPosition = const CameraPosition(
    target: LatLng(25.2048, 55.2708), // Dubai coordinates
    zoom: 11.0,
  );

  // Filter state - now supports multiple selections
  Set<LocationFilter> _selectedFilters = {LocationFilter.all};
  Set<LocationFilter> get selectedFilters => _selectedFilters;

  // Backward compatibility getter
  LocationFilter get selectedFilter => _selectedFilters.first;

  // Data storage
  List<LocationInfo> _allLocations = [];
  List<LocationInfo> get allLocations => _allLocations;

  Set<Marker> _markers = {};
  Set<Marker> get filteredMarkers => _markers;

  LocationInfo? _selectedLocationInfo;
  LocationInfo? get selectedLocationInfo => _selectedLocationInfo;

  // NEW: Clustered location tracking
  ClusteredLocationInfo? _selectedCluster;
  ClusteredLocationInfo? get selectedCluster => _selectedCluster;

  // Map to track which markers have clusters
  Map<String, ClusteredLocationInfo> _locationClusters = {};

  // Stream subscriptions for real-time updates
  StreamSubscription? _offersSubscription;
  StreamSubscription? _ownersSubscription;
  StreamSubscription? _officesSubscription;
  StreamSubscription? _watchmenSubscription;

  // Counts for filter chips
  int get totalLocationsCount => _allLocations.length;
  int get offersCount =>
      _allLocations.where((l) => l.type == LocationFilter.offers).length;
  int get ownersCount =>
      _allLocations.where((l) => l.type == LocationFilter.owners).length;
  int get officesCount =>
      _allLocations.where((l) => l.type == LocationFilter.offices).length;
  int get watchmenCount =>
      _allLocations.where((l) => l.type == LocationFilter.watchmen).length;

  // Get current filtered count for display
  int get currentFilteredCount {
    if (_selectedFilters.contains(LocationFilter.all)) {
      return _allLocations.length;
    } else {
      return _allLocations
          .where((l) => _selectedFilters.contains(l.type))
          .length;
    }
  }

  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final AuthRepository _authRepository;
  final _cacheService = MapDataCacheService();

  MapViewViewModel({AuthRepository? authRepository})
      : _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository {
    _initializeMap();
  }

  // Safe notifyListeners that checks if disposed
  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // Initialize map and load data
  Future<void> _initializeMap() async {
    if (_disposed) return;

    // Don't set loading to true - let the map display immediately
    // _isLoading = true;
    // _safeNotifyListeners();

    try {
      // Load locations once from cache/Firestore for initial display
      // Note: We don't block map initialization on location permission
      // The map will load even if location permission is denied
      // User location features will simply be unavailable
      await loadLocations();

      // Set up real-time listeners for instant updates going forward
      _setupRealtimeListeners();
    } catch (e) {
      if (_disposed) return;

      _error = 'Failed to initialize map: ${e.toString()}';
      // Debug log suppressed: Map initialization error: $e
      _safeNotifyListeners();
    }
    // No need to set _isLoading = false since we never set it to true
  }

  // Request location permission using CleanPermissionService (with pre-permission dialog)
  // This should be called from the UI after map is loaded
  Future<void> requestLocationPermission(BuildContext context) async {
    if (_disposed) return;

    final cleanPermissionService = CleanPermissionService();
    final permissionStatus =
        await cleanPermissionService.requestLocationPermission(context);

    if (_disposed) return;

    _hasLocationPermission = permissionStatus.isGranted;
    _safeNotifyListeners();

    // Debug log suppressed: Location permission status: $_hasLocationPermission
  }

  // Load all locations from Firestore
  Future<void> loadLocations({bool forceRefresh = false}) async {
    if (_disposed) return;

    try {
      // Don't show loading indicator - load silently in background
      // _isLoading = true;
      _error = null;
      // _safeNotifyListeners();

      final currentUserId = _authRepository.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Debug log suppressed: LOADING LOCATIONS FOR USER: ${currentUser.uid}

      // Check if cache needs refresh (was invalidated due to data changes)
      if (_cacheService.needsRefresh && !forceRefresh) {
        // Debug log suppressed: CACHE NEEDS REFRESH - FORCING RELOAD
        forceRefresh = true;
      }

      // Try to use cached data first for instant loading (unless force refresh)
      final cachedData = !forceRefresh ? _cacheService.cachedLocations : null;
      if (cachedData != null && cachedData.isNotEmpty) {
        // Debug log suppressed: USING CACHED DATA: ${cachedData.length} locations
        _allLocations.clear();

        // Convert cached data to LocationInfo
        for (final cached in cachedData) {
          if (_disposed) return;

          _allLocations.add(
            LocationInfo(
              id: cached.id,
              title: cached.title,
              address: cached.address,
              coordinates: cached.coordinates,
              type: cached.type,
              color: LocationColors.getColor(cached.type),
              iconAsset: _getIconAssetForType(cached.type),
              phoneNumber: cached.phoneNumber,
              mediaUrl: cached.mediaUrl,
              mediaUrls: cached.mediaUrls,
              additionalData: cached.additionalData,
            ),
          );
        }

        // Debug log suppressed: LOADED FROM CACHE: ${_allLocations.length} locations

        // Apply current filter
        _applyFilter();

        // Move camera to show all markers
        if (!_disposed) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!_disposed) {
              _moveCameraToShowAllMarkers();
            }
          });
        }

        return; // Exit early - we have the data
      }

      // No cache available - load from Firestore
      // Debug log suppressed: NO CACHE - LOADING FROM FIRESTORE
      _allLocations.clear();

      // Load offers
      await _loadOffers(currentUserId);
      if (_disposed) return;

      // Load owners
      await _loadOwners(currentUserId);
      if (_disposed) return;

      // Load offices
      await _loadOffices(currentUserId);
      if (_disposed) return;

      // Load watchmen
      await _loadWatchmen(currentUserId);
      if (_disposed) return;

      // Debug log suppressed: TOTAL LOCATIONS LOADED: ${_allLocations.length}
      // Debug log suppressed: Offers: ${_allLocations.where((l) => l.type == LocationFilter.offers).length}
      // Debug log suppressed: Owners: ${_allLocations.where((l) => l.type == LocationFilter.owners).length}
      // Debug log suppressed: Offices: ${_allLocations.where((l) => l.type == LocationFilter.offices).length}
      // Debug log suppressed: Watchmen: ${_allLocations.where((l) => l.type == LocationFilter.watchmen).length}

      // Rebuild cache in background with fresh data
      if (forceRefresh) {
        _cacheService.preloadMapData().catchError((e) {
          // Debug log suppressed: Background cache rebuild failed: $e
        });
      }

      // Apply current filter
      _applyFilter();

      // Move camera to show all markers after a short delay
      if (!_disposed) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_disposed) {
            _moveCameraToShowAllMarkers();
          }
        });
      }
    } catch (e) {
      if (!_disposed) {
        _error = e.toString();
        // Debug log suppressed: Error loading locations: $e
        _safeNotifyListeners();
      }
    }
    // No need to set _isLoading = false since we never set it to true
  }

  // Public method to refresh data (call this after adding/updating/deleting items)
  // Note: With real-time listeners, this is only needed for manual refresh
  Future<void> refreshLocations() async {
    if (_disposed) return;
    // Debug log suppressed: MANUAL REFRESH (Real-time listeners are active)

    // Invalidate cache
    _cacheService.invalidateCache();

    // Real-time listeners will automatically update the data
    // This method is kept for backward compatibility
  }

  // Set up real-time listeners for instant updates
  void _setupRealtimeListeners() {
    final currentUserId = _authRepository.currentUserId;
    if (currentUserId == null || _disposed) return;

    // Debug log suppressed: SETTING UP REAL-TIME LISTENERS

    // Listen to offers collection
    _offersSubscription = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('offers')
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      _handleOffersUpdate(snapshot);
    });

    // Listen to owners collection
    _ownersSubscription = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('owners')
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      _handleOwnersUpdate(snapshot);
    });

    // Listen to offices collection
    _officesSubscription = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('offices')
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      _handleOfficesUpdate(snapshot);
    });

    // Listen to watchmen collection
    _watchmenSubscription = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('watchmen')
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      _handleWatchmenUpdate(snapshot);
    });
  }

  // Handle offers collection updates
  void _handleOffersUpdate(QuerySnapshot snapshot) {
    if (_disposed) return;

    // Remove old offers
    _allLocations.removeWhere((loc) => loc.type == LocationFilter.offers);

    // Add updated offers
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = data['pickUpLatitude'] as double?;
      final lng = data['pickUpLongitude'] as double?;

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        _allLocations.add(
          LocationInfo(
            id: doc.id,
            title: data['specificPropertyType'] ?? 'Property Offer',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            coordinates: LatLng(lat, lng),
            type: LocationFilter.offers,
            color: LocationColors.getColor(LocationFilter.offers),
            iconAsset: 'assets/icons/offers-svg.svg',
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
          ),
        );
      }
    }

    _applyFilter();
    // Debug log suppressed: Offers updated: ${_allLocations.where((l) => l.type == LocationFilter.offers).length}
  }

  // Handle owners collection updates
  void _handleOwnersUpdate(QuerySnapshot snapshot) {
    if (_disposed) return;

    // Remove old owners
    _allLocations.removeWhere((loc) => loc.type == LocationFilter.owners);

    // Add updated owners
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = data['pickUpLatitude'] as double?;
      final lng = data['pickUpLongitude'] as double?;

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        _allLocations.add(
          LocationInfo(
            id: doc.id,
            title: data['name'] ?? 'Property Owner',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            coordinates: LatLng(lat, lng),
            type: LocationFilter.owners,
            color: LocationColors.getColor(LocationFilter.owners),
            iconAsset: 'assets/icons/owners-svg.svg',
            phoneNumber: data['phoneNumber'],
            mediaUrl: data['mediaUrl'],
            mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
            additionalData: {
              'typeOfProperties': data['typeOfProperties'],
              'propertyLocation': data['propertyLocation'],
            },
          ),
        );
      }
    }

    _applyFilter();
    // Debug log suppressed: Owners updated: ${_allLocations.where((l) => l.type == LocationFilter.owners).length}
  }

  // Handle offices collection updates
  void _handleOfficesUpdate(QuerySnapshot snapshot) {
    if (_disposed) return;

    // Remove old offices
    _allLocations.removeWhere((loc) => loc.type == LocationFilter.offices);

    // Add updated offices
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = data['pickUpLatitude'] as double?;
      final lng = data['pickUpLongitude'] as double?;

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        _allLocations.add(
          LocationInfo(
            id: doc.id,
            title: data['officeName'] ?? 'Real Estate Office',
            address:
                data['pickUpAddress'] ?? data['pickUpLocation'] ?? 'No address',
            coordinates: LatLng(lat, lng),
            type: LocationFilter.offices,
            color: LocationColors.getColor(LocationFilter.offices),
            iconAsset: 'assets/icons/offices-svg.svg',
            phoneNumber: data['phoneNumber'],
            additionalData: {
              'managerName': data['managerName'],
              'officeLocation': data['officeLocation'],
            },
          ),
        );
      }
    }

    _applyFilter();
    // Debug log suppressed: Offices updated: ${_allLocations.where((l) => l.type == LocationFilter.offices).length}
  }

  // Handle watchmen collection updates
  void _handleWatchmenUpdate(QuerySnapshot snapshot) {
    if (_disposed) return;

    // Remove old watchmen
    _allLocations.removeWhere((loc) => loc.type == LocationFilter.watchmen);

    // Add updated watchmen
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = data['pickUpLatitude'] as double?;
      final lng = data['pickUpLongitude'] as double?;

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        _allLocations.add(
          LocationInfo(
            id: doc.id,
            title: data['name'] ?? 'Building Watchman',
            address: data['pickUpAddress'] ??
                data['pickUpLocation'] ??
                data['buildingLocation'] ??
                'No address',
            coordinates: LatLng(lat, lng),
            type: LocationFilter.watchmen,
            color: LocationColors.getColor(LocationFilter.watchmen),
            iconAsset: 'assets/icons/watchman-svg.svg',
            phoneNumber: data['phoneNumber'],
            additionalData: {
              'buildingName': data['buildingName'],
              'buildingLocation': data['buildingLocation'],
            },
          ),
        );
      }
    }

    _applyFilter();
    // Debug log suppressed: Watchmen updated: ${_allLocations.where((l) => l.type == LocationFilter.watchmen).length}
  }

  // Helper method to get icon asset for type
  String _getIconAssetForType(LocationFilter type) {
    switch (type) {
      case LocationFilter.offers:
        return 'assets/icons/offers-svg.svg';
      case LocationFilter.owners:
        return 'assets/icons/owners-svg.svg';
      case LocationFilter.offices:
        return 'assets/icons/offices-svg.svg';
      case LocationFilter.watchmen:
        return 'assets/icons/watchman-svg.svg';
      case LocationFilter.all:
        return 'assets/icons/offers-svg.svg'; // Default
    }
  }

  // Load offers from Firestore
  Future<void> _loadOffers(String userId) async {
    if (_disposed) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('offers')
          .get();

      if (_disposed) return;

      for (final doc in snapshot.docs) {
        if (_disposed) return;

        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          _allLocations.add(
            LocationInfo(
              id: doc.id,
              title: data['specificPropertyType'] ?? 'Property Offer',
              address: data['pickUpAddress'] ??
                  data['pickUpLocation'] ??
                  'No address',
              coordinates: LatLng(lat, lng),
              type: LocationFilter.offers,
              color: LocationColors.getColor(LocationFilter.offers),
              iconAsset: 'assets/icons/offers-svg.svg',
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
            ),
          );
        }
      }
      // Debug log suppressed: Loaded ${_allLocations.where((l) => l.type == LocationFilter.offers).length} offers
    } catch (e) {
      // Debug log suppressed: Error loading offers: $e
    }
  }

  // Load owners from Firestore
  Future<void> _loadOwners(String userId) async {
    if (_disposed) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('owners')
          .get();

      if (_disposed) return;

      for (final doc in snapshot.docs) {
        if (_disposed) return;

        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          _allLocations.add(
            LocationInfo(
              id: doc.id,
              title: data['name'] ?? 'Property Owner',
              address: data['pickUpAddress'] ??
                  data['pickUpLocation'] ??
                  'No address',
              coordinates: LatLng(lat, lng),
              type: LocationFilter.owners,
              color: LocationColors.getColor(LocationFilter.owners),
              iconAsset: 'assets/icons/owners-svg.svg',
              phoneNumber: data['phoneNumber'],
              mediaUrl: data['mediaUrl'],
              mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
              additionalData: {
                'typeOfProperties': data['typeOfProperties'],
                'propertyLocation': data['propertyLocation'],
              },
            ),
          );
        }
      }
      // Debug log suppressed: Loaded ${_allLocations.where((l) => l.type == LocationFilter.owners).length} owners
    } catch (e) {
      // Debug log suppressed: Error loading owners: $e
    }
  }

  // Load offices from Firestore
  Future<void> _loadOffices(String userId) async {
    if (_disposed) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('offices')
          .get();

      if (_disposed) return;

      for (final doc in snapshot.docs) {
        if (_disposed) return;

        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          _allLocations.add(
            LocationInfo(
              id: doc.id,
              title: data['officeName'] ?? 'Real Estate Office',
              address: data['pickUpAddress'] ??
                  data['pickUpLocation'] ??
                  'No address',
              coordinates: LatLng(lat, lng),
              type: LocationFilter.offices,
              color: LocationColors.getColor(LocationFilter.offices),
              iconAsset: 'assets/icons/offices-svg.svg',
              phoneNumber: data['phoneNumber'],
              additionalData: {
                'managerName': data['managerName'],
                'officeLocation': data['officeLocation'],
              },
            ),
          );
        }
      }
      // Debug log suppressed: Loaded ${_allLocations.where((l) => l.type == LocationFilter.offices).length} offices
    } catch (e) {
      // Debug log suppressed: Error loading offices: $e
    }
  }

  // Load watchmen from Firestore
  Future<void> _loadWatchmen(String userId) async {
    if (_disposed) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('watchmen')
          .get();

      if (_disposed) return;

      for (final doc in snapshot.docs) {
        if (_disposed) return;

        final data = doc.data();
        final lat = data['pickUpLatitude'] as double?;
        final lng = data['pickUpLongitude'] as double?;

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          _allLocations.add(
            LocationInfo(
              id: doc.id,
              title: data['name'] ?? 'Building Watchman',
              address: data['pickUpAddress'] ??
                  data['pickUpLocation'] ??
                  data['buildingLocation'] ??
                  'No address',
              coordinates: LatLng(lat, lng),
              type: LocationFilter.watchmen,
              color: LocationColors.getColor(LocationFilter.watchmen),
              iconAsset: 'assets/icons/watchman-svg.svg',
              phoneNumber: data['phoneNumber'],
              additionalData: {
                'buildingName': data['buildingName'],
                'buildingLocation': data['buildingLocation'],
              },
            ),
          );
        }
      }
      // Debug log suppressed: Loaded ${_allLocations.where((l) => l.type == LocationFilter.watchmen).length} watchmen
    } catch (e) {
      // Debug log suppressed: Error loading watchmen: $e
    }
  }

  // Apply filter and update markers
  void _applyFilter() {
    if (_disposed) return;

    List<LocationInfo> filteredLocations;

    if (_selectedFilters.contains(LocationFilter.all)) {
      filteredLocations = _allLocations;
    } else {
      filteredLocations = _allLocations
          .where((location) => _selectedFilters.contains(location.type))
          .toList();
    }

    _updateMarkersWithClustering(filteredLocations);
  }

  // Update markers with clustering support
  Future<void> _updateMarkersWithClustering(
      List<LocationInfo> locations) async {
    if (_disposed) return;

    // Debug log suppressed: Creating markers with clustering for ${locations.length} locations

    // Group locations by coordinates
    final Map<String, List<LocationInfo>> coordinateGroups = {};

    for (final location in locations) {
      final key = ClusteredLocationInfo.coordinateKey(location.coordinates);
      coordinateGroups.putIfAbsent(key, () => []).add(location);
      // Debug log suppressed: Adding ${location.type} "${location.title}" to group $key
    }

    // Debug log suppressed: Found ${coordinateGroups.length} unique coordinate groups

    // Log groups with multiple items
    for (final entry in coordinateGroups.entries) {
      if (entry.value.length > 1) {
        // Debug log suppressed: CLUSTER at ${entry.key}: ${entry.value.length} items
        // Debug log suppressed: (individual item details suppressed)
      }
    }

    // Create clusters
    _locationClusters.clear();
    final Set<Marker> newMarkers = {};

    for (final entry in coordinateGroups.entries) {
      if (_disposed) return;

      final items = entry.value;
      final cluster = ClusteredLocationInfo(
        coordinates: items.first.coordinates,
        items: items,
      );

      _locationClusters[entry.key] = cluster;

      // Create marker using the first item's type (will update dynamically)
      await _createClusterMarker(cluster, newMarkers);
    }

    if (!_disposed) {
      _markers = newMarkers;
      _safeNotifyListeners();
      // Debug log suppressed: Created ${newMarkers.length} markers (${_locationClusters.values.where((c) => c.hasMultipleItems).length} are clusters)
    }
  }

  // Create marker for a cluster
  Future<void> _createClusterMarker(
      ClusteredLocationInfo cluster, Set<Marker> markerSet) async {
    if (_disposed) return;

    final activeItem = cluster.activeItem;
    final key = ClusteredLocationInfo.coordinateKey(cluster.coordinates);

    if (cluster.hasMultipleItems) {
      // Debug log suppressed: Creating CLUSTER marker for $key (${cluster.itemCount} items)
    }

    try {
      BitmapDescriptor customPin;

      if (cluster.hasMultipleItems) {
        // Create special cluster pin showing all item types
        final itemTypes = cluster.items.map((item) => item.type).toList();
        customPin = await MapPinHelper.createClusterPin(
          types: itemTypes,
          size: 92.0,
        );
      } else {
        // Single item - use regular category pin
        customPin = await MapPinHelper.createCategoryPin(
          type: activeItem.type,
          color: activeItem.color,
          size: 72.0,
        );
      }

      if (_disposed) return;

      final marker = Marker(
        markerId: MarkerId(key), // Use coordinate key as marker ID
        position: cluster.coordinates,
        onTap: () => _onClusterTap(cluster),
        icon: customPin,
        infoWindow: InfoWindow(
          title: cluster.hasMultipleItems
              ? '${cluster.itemCount} items at this location'
              : activeItem.title,
          snippet: activeItem.address,
        ),
      );

      markerSet.add(marker);
    } catch (e) {
      // Debug log suppressed: Error creating cluster marker: $e
      if (_disposed) return;

      // Fallback to default marker
      final marker = Marker(
        markerId: MarkerId(key),
        position: cluster.coordinates,
        onTap: () => _onClusterTap(cluster),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            LocationColors.getMarkerHue(activeItem.type)),
        infoWindow: InfoWindow(
          title: cluster.hasMultipleItems
              ? '${cluster.itemCount} items here'
              : activeItem.title,
          snippet: activeItem.address,
        ),
      );
      markerSet.add(marker);
    }
  }

  // Update marker for a specific cluster (used when carousel changes)
  Future<void> updateClusterMarker(ClusteredLocationInfo cluster) async {
    if (_disposed) return;

    // Debug log suppressed: Updating marker for cluster at ${cluster.coordinates}

    final key = ClusteredLocationInfo.coordinateKey(cluster.coordinates);
    final activeItem = cluster.activeItem;

    try {
      // Create new custom pin for the active item
      final customPin = await MapPinHelper.createCategoryPin(
        type: activeItem.type,
        color: activeItem.color,
        size: cluster.hasMultipleItems ? 82.0 : 72.0,
      );

      if (_disposed) return;

      // Remove old marker
      _markers.removeWhere((m) => m.markerId.value == key);

      // Add updated marker
      final marker = Marker(
        markerId: MarkerId(key),
        position: cluster.coordinates,
        onTap: () => _onClusterTap(cluster),
        icon: customPin,
        infoWindow: InfoWindow(
          title: cluster.hasMultipleItems
              ? '${cluster.itemCount} items at this location'
              : activeItem.title,
          snippet: activeItem.address,
        ),
      );

      _markers.add(marker);
      _safeNotifyListeners();
      // Debug log suppressed: Marker updated to ${activeItem.type} (${activeItem.title})
    } catch (e) {
      // Debug log suppressed: Error updating cluster marker: $e
    }
  }

  // Handle cluster tap
  void _onClusterTap(ClusteredLocationInfo cluster) {
    if (_disposed) return;

    // Debug log suppressed: Cluster tapped: ${cluster.itemCount} items at ${cluster.coordinates}

    _selectedCluster = cluster;
    _selectedLocationInfo = cluster.activeItem;
    _safeNotifyListeners();
  }

  // Update active item in cluster (called from carousel swipe)
  void updateClusterActiveIndex(int index) async {
    if (_disposed || _selectedCluster == null) return;

    if (index < 0 || index >= _selectedCluster!.itemCount) return;

    // Debug log suppressed: Carousel swiped to index $index

    _selectedCluster!.activeIndex = index;
    _selectedLocationInfo = _selectedCluster!.activeItem;

    // Update the marker icon to match the new active item
    await updateClusterMarker(_selectedCluster!);
  }

  // Map event handlers
  void onMapCreated(GoogleMapController controller) {
    if (_disposed) return;

    _mapController = controller;
    // Debug log suppressed: Map controller created, markers: ${_markers.length}
    // Move camera to show all markers if we have any
    if (_markers.isNotEmpty && !_disposed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_disposed) {
          _moveCameraToShowAllMarkers();
        }
      });
    }
  }

  void onMapTap(LatLng position) {
    if (_disposed) return;
    clearSelectedLocation();
  }

  // Filter methods
  void setFilter(LocationFilter filter) {
    if (_disposed) return;

    if (filter == LocationFilter.all) {
      // If "All" is selected, clear other selections and select only "All"
      _selectedFilters = {LocationFilter.all};
    } else {
      // Remove "All" if it was selected
      _selectedFilters.remove(LocationFilter.all);

      // Toggle the selected filter
      if (_selectedFilters.contains(filter)) {
        _selectedFilters.remove(filter);
      } else {
        _selectedFilters.add(filter);
      }

      // If no filters are selected, default to "All"
      if (_selectedFilters.isEmpty) {
        _selectedFilters = {LocationFilter.all};
      }
    }

    _applyFilter();
    // Move camera to show filtered markers
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_disposed) {
        _moveCameraToShowAllMarkers();
      }
    });
  }

  // Check if a filter is selected
  bool isFilterSelected(LocationFilter filter) {
    return _selectedFilters.contains(filter);
  }

  // UI methods
  void toggleMapType() {
    if (_disposed) return;

    _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    _safeNotifyListeners();
  }

  void clearSelectedLocation() {
    if (_disposed) return;

    _selectedLocationInfo = null;
    _selectedCluster = null;
    _safeNotifyListeners();
  }

  // Move to current user location with zoom
  Future<void> moveToCurrentLocation(BuildContext context) async {
    if (_disposed) return;

    try {
      final cleanLocationService = CleanLocationService();
      final position = await cleanLocationService.getCurrentPosition(context);

      if (position == null || _disposed) return;

      // Update permission status since user granted it
      _hasLocationPermission = true;
      _safeNotifyListeners();

      final currentLocation = LatLng(position.latitude, position.longitude);

      // Animate camera to current location with zoom
      if (_mapController != null && !_disposed) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(currentLocation, 18.0),
        );
        // Debug log suppressed: Moved to current location: $currentLocation
      }
    } catch (e) {
      // Debug log suppressed: Error getting current location: $e
    }
  }

  // Check location permission status (used to enable/disable myLocationEnabled)
  Future<void> checkLocationPermission() async {
    if (_disposed) return;

    final cleanLocationService = CleanLocationService();
    _hasLocationPermission = await cleanLocationService.hasLocationPermission();
    _safeNotifyListeners();
  }

  // Move camera to specific location with zoom
  Future<void> animateToLocation(LatLng location) async {
    if (_disposed || _mapController == null) return;

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(location, 15.0),
      );
      // Debug log suppressed: Moved to location: $location
    } catch (e) {
      // Debug log suppressed: Error moving to location: $e
    }
  }

  // Move camera to show all markers
  Future<void> _moveCameraToShowAllMarkers() async {
    if (_disposed || _mapController == null || _markers.isEmpty) {
      // Debug log suppressed: Cannot move camera: disposed=$_disposed, controller=${_mapController != null}, markers=${_markers.length}
      return;
    }

    // Debug log suppressed: Moving camera to show ${_markers.length} markers

    if (_markers.length == 1) {
      // If only one marker, center on it
      final marker = _markers.first;
      // Debug log suppressed: Centering on single marker at: ${marker.position}
      if (!_disposed) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(marker.position, 15.0),
        );
      }
      return;
    }

    // Calculate bounds for all markers
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final marker in _markers) {
      if (_disposed) return;

      minLat =
          marker.position.latitude < minLat ? marker.position.latitude : minLat;
      maxLat =
          marker.position.latitude > maxLat ? marker.position.latitude : maxLat;
      minLng = marker.position.longitude < minLng
          ? marker.position.longitude
          : minLng;
      maxLng = marker.position.longitude > maxLng
          ? marker.position.longitude
          : maxLng;
    }

    // Add padding
    const padding = 0.01;
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );

    // Debug log suppressed: Camera bounds: SW(${bounds.southwest}), NE(${bounds.northeast})

    try {
      if (!_disposed) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100.0),
        );
        // Debug log suppressed: Camera movement completed
      }
    } catch (e) {
      // Debug log suppressed: Error moving camera: $e
      if (!_disposed) {
        // Fallback to center point
        final centerLat = (minLat + maxLat) / 2;
        final centerLng = (minLng + maxLng) / 2;
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(centerLat, centerLng), 12.0),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;

    // Cancel all real-time listeners
    _offersSubscription?.cancel();
    _ownersSubscription?.cancel();
    _officesSubscription?.cancel();
    _watchmenSubscription?.cancel();

    _mapController?.dispose();
    super.dispose();
  }
}
