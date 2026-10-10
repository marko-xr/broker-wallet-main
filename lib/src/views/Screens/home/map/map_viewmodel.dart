import 'dart:async';

import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media_source.dart';
import 'package:broker_wallet/src/Views/Widgets/custom_map_pin.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';
import 'package:broker_wallet/src/services/device_location_platform.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_camera_policy.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_location_source.dart';
import 'package:broker_wallet/src/services/map_nearby_locator.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Data models
class LocationInfo {
  final String id;

  /// What the record calls itself; empty when it says nothing. Show it through
  /// [MapViewViewModel.displayTitle], which words the empty case.
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

  /// Identifies the place among all the map's places: its kind and its id.
  String get key => '${type.name}:$id';
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
    return '$lat,$lng';
  }
}

/// What the map screen shows and does.
///
/// The places are the signed-in user's own Offers, Owners, Offices and Watchmen
/// that have a position, read through a [MapLocationSource] (Supabase for the
/// app). They are read when the screen opens — at once from the last read when
/// it is still good — and again whenever the user's own data changes, one read
/// at a time. A read that fails never empties a map that has places on it; only
/// a map with nothing to show reports the failure.
///
/// What the person narrows the map by (one category, Nearby, city, property
/// type, rent or sale, and a price ordering) is a [MapFilterState] held by a
/// [MapFilterController]: the places already loaded are filtered in memory, so
/// changing a filter never reads anything, and only redraws the markers.
///
/// The map opens on the UAE's cities, Abu Dhabi to Khor Fakkan ([initialCameraFor]),
/// and frames nothing by itself afterwards: new places and a refresh leave the
/// camera where the person put it. Only an explicit choice moves it, and each
/// kind of choice has its own meaning (see [MapCameraCause]): a city shows that
/// city's places, or the city itself when none match; Nearby shows the circle of
/// its radius around the device; any other filter shows the places it lets
/// through. The camera is planned from the same snapshot the markers are drawn
/// from, and only the newest choice may move it. Location is asked for only
/// after a tap on "my location" or Nearby.
class MapViewViewModel extends ChangeNotifier {
  MapViewViewModel({
    MapLocationSource? source,
    MapDataCacheService? cache,
    SearchCardMediaResolver? cardMedia,
    DeviceLocationPlatform? device,
  })  : _cache = cache ?? MapDataCacheService(),
        _device = device ?? const PluginDeviceLocationPlatform(),
        cardMedia = cardMedia ??
            SearchCardMediaResolver(source: DefaultSearchCardMediaSource()) {
    _loader = MapPlacesLoader(
      source: source ?? DefaultMapLocationSource(),
      cache: _cache,
      onPlaces: _onPlaces,
      onFailed: _failLoad,
    );
    unawaited(_loader.start());
  }

  final MapDataCacheService _cache;

  /// The phone's location features. Nothing here is used when the map opens
  /// except reading whether permission is already granted; the position and the
  /// system's permission prompt are only reached through [moveToCurrentLocation]
  /// and [enableNearby], which a tap starts.
  final DeviceLocationPlatform _device;

  /// Chooses the photo or video frame an Offer's or an Owner's card shows. The
  /// reads carry no media links, so a card asks for its own while it is shown;
  /// what was asked is forgotten whenever the places are read again.
  final SearchCardMediaResolver cardMedia;

  /// Reads the places, keeps them current, and drops what belongs to another
  /// account.
  late final MapPlacesLoader _loader;

  /// The places loaded, the filter over them, the places it lets through and
  /// the one whose card is open.
  final MapFilterController _filters = MapFilterController();

  // Add disposal tracking
  bool _disposed = false;
  bool get disposed => _disposed;

  /// Whether the places could not be read and there is nothing on the map to
  /// fall back to. The screen words it; the technical error is never shown.
  bool _hasLoadError = false;
  bool get hasLoadError => _hasLoadError;

  // Location permission tracking
  bool _hasLocationPermission = false;
  bool get hasLocationPermission => _hasLocationPermission;

  // Map configuration
  MapType _mapType = MapType.hybrid;
  MapType get mapType => _mapType;

  GoogleMapController? _mapController;

  /// Decides, once, the camera the map opens on: the UAE where its cities are.
  final MapCameraDirector _camera = MapCameraDirector();

  /// Whether the opening camera has been decided. After that nothing frames the
  /// country again: not new places, not a refresh, not a filter, not Clear.
  bool get initialCameraApplied => _camera.initialApplied;

  /// The camera the map is created with: the UAE's cities, worked out from the
  /// map's own size ([viewport]). It is handed to the map as its starting
  /// camera, so there is nothing to move afterwards and no timer; and the first
  /// answer is kept, so a rebuild or a new size cannot change it.
  CameraPosition initialCameraFor(MapViewport viewport) {
    // The room the map really has, kept so a later camera move (a city, a
    // radius) is framed for the same screen.
    _viewport = viewport;
    final camera = _camera.initial(viewport);
    return CameraPosition(
      target: LatLng(camera.latitude, camera.longitude),
      zoom: camera.zoom,
    );
  }

  // Every loaded place, as the screen draws it, and by key
  List<LocationInfo> _allLocations = [];
  List<LocationInfo> get allLocations => _allLocations;
  Map<String, LocationInfo> _infoByKey = {};

  Set<Marker> _markers = {};
  Set<Marker> get filteredMarkers => _markers;

  /// How many places the published markers stand for (a marker can hold several
  /// places at one spot); null until the first draw has been published.
  int? _publishedPlaceCount;

  /// The number of results the screen shows: the places of the draw that is on
  /// the map now, so it is always the markers' own places. It is set only when
  /// a draw is published (never from the live filter, which is ahead of the
  /// markers while a draw is under way), and costs no count and no read of its
  /// own. Null when there is nothing to say yet, and when the places could not
  /// be loaded: a map that has not loaded does not say "0 results".
  int? get resultCount => _hasLoadError ? null : _publishedPlaceCount;

  LocationInfo? _selectedLocationInfo;
  LocationInfo? get selectedLocationInfo => _selectedLocationInfo;

  // Clustered location tracking
  ClusteredLocationInfo? _selectedCluster;
  ClusteredLocationInfo? get selectedCluster => _selectedCluster;

  // The clusters the markers on the map stand for, by coordinate key
  Map<String, ClusteredLocationInfo> _locationClusters = {};

  /// The room the map has (set when the screen lays it out).
  MapViewport? _viewport;

  /// Draws the markers for a filter snapshot, publishes them, and moves the
  /// camera for the person's newest choice, one latest-wins pass at a time. A
  /// draw that a newer one overtook publishes nothing and moves nothing.
  late final MapDrawPipeline<_Drawn> _pipeline = MapDrawPipeline<_Drawn>(
    draw: _drawMarkers,
    publish: _publishDrawn,
    moveCamera: _moveCamera,
    viewport: () => _viewport ?? MapViewport.referencePhone,
  );

  AppLocalizations? _localization;

  // ---- the filter ------------------------------------------------------------

  /// What the map is narrowed by now.
  MapFilterState get filterState => _filters.state;

  /// Whether anything narrows the map.
  bool get filtersActive => _filters.filtersActive;

  /// Places were loaded and the filter lets none through. Not a failed load.
  bool get hasNoFilterMatches => _filters.hasNoMatches;

  /// How many places of each kind are loaded.
  Map<LocationFilter, int> get entityCounts => _filters.entityCounts;

  int get totalLocationsCount => _allLocations.length;

  /// Every city of the catalog the forms use, in the catalog's order. Not taken
  /// from the loaded places: a city nobody has a place in can still be chosen.
  List<String> get cityOptions => _filters.cityOptions;

  /// The active layer's canonical form vocabulary, independent of loaded pins.
  List<String> get propertyTypeOptions => _filters.propertyTypeOptions;

  /// Whether the device's position is being awaited for Nearby (it was just
  /// turned on and has not answered yet). The chip shows it; the map and its
  /// places stay exactly as they are until the position arrives.
  bool get isLocatingNearby => _filters.isLocatingNearby;

  bool _locatingMe = false;

  // The one boundary that gets the device's position: "my location" and Nearby
  // both go through it. Nearby needs a rough fix; the camera that zooms to the
  // street needs a fine one. Nothing else in the map asks the device anything.
  late final NearbyLocator _nearbyLocator = DeviceNearbyLocator(_device);
  late final NearbyLocator _myLocationLocator =
      DeviceNearbyLocator(_device, precise: true);

  // Safe notifyListeners that checks if disposed
  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The words the map speaks in (marker text, empty titles). Set by the screen
  /// on every build; it never rebuilds anything by itself.
  void updateLocalization(AppLocalizations localization) {
    _localization = localization;
  }

  /// What a place is called on the screen: its own name (an Offer's property
  /// type in the app's language), or — when it has none — the kind of place it
  /// is. Never an English placeholder.
  String displayTitle(LocationInfo item) {
    final stored = item.title.trim();
    final loc = _localization;
    if (stored.isNotEmpty) {
      if (item.type == LocationFilter.offers && loc != null) {
        return ShareFormat.propertyType(
              stored,
              ShareLabels(
                languageCode: loc.locale.languageCode,
                lookup: AppLocalizations.translateFor,
              ),
            ) ??
            stored;
      }
      return stored;
    }
    if (loc == null) return '';
    switch (item.type) {
      case LocationFilter.offers:
        return loc.translate('offer');
      case LocationFilter.owners:
        return loc.translate('propertyOwner');
      case LocationFilter.offices:
        return loc.translate('office');
      case LocationFilter.watchmen:
        return loc.translate('watchman');
      case LocationFilter.all:
        return '';
    }
  }

  /// Shows the places the loader has: the last read, or what a read just found.
  Future<void> _onPlaces(
    List<CachedLocationData> places, {
    required bool fresh,
  }) async {
    if (_disposed) return;
    if (fresh) {
      // New records: forget which photos were asked for, and the failure.
      cardMedia.invalidate();
      _hasLoadError = false;
    }
    await _show(places);
  }

  /// Places already on the map keep serving; only a map with nothing to show
  /// reports that it could not read them.
  void _failLoad() {
    if (_allLocations.isEmpty) {
      _hasLoadError = true;
      _safeNotifyListeners();
    }
  }

  Future<void> _show(List<CachedLocationData> records) async {
    if (_disposed) return;

    // The filter stays as the person set it; a card whose place is gone closes.
    _filters.setRecords(records);
    _infoByKey = {
      for (final record in records) record.key: _toLocationInfo(record),
    };
    _allLocations = _infoByKey.values.toList();

    // Places appearing or being read again never ask the camera to move: the
    // map opened on the UAE's cities, and from then on only the person (an
    // explicit choice) moves it.
    await _pipeline.show(_filters.snapshot);
  }

  LocationInfo _toLocationInfo(CachedLocationData record) {
    return LocationInfo(
      id: record.id,
      title: record.title,
      address: record.address,
      coordinates: record.coordinates,
      type: record.type,
      color: LocationColors.getColor(record.type),
      iconAsset: _getIconAssetForType(record.type),
      phoneNumber: record.phoneNumber,
      mediaUrl: record.mediaUrl,
      mediaUrls: record.mediaUrls,
      additionalData: record.additionalData,
    );
  }

  /// Tries again after a failure.
  Future<void> retry() async {
    if (_disposed) return;
    _hasLoadError = false;
    _safeNotifyListeners();
    await _loader.refresh();
  }

  /// Reads the places again (a manual refresh).
  Future<void> refreshLocations() async {
    if (_disposed) return;
    _cache.invalidateCache();
    await _loader.refresh();
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

  /// Draws the markers for the places [snapshot] lets through, grouping places
  /// at the same spot into one marker. Returns null when it stopped because a
  /// newer draw took over ([isCurrent] turned false): then nothing is published.
  Future<_Drawn?> _drawMarkers(
    MapFilterSnapshot snapshot,
    bool Function() isCurrent,
  ) async {
    if (_disposed) return null;

    // Group the places of the snapshot by coordinates
    final groups = <String, List<LocationInfo>>{};
    for (final place in snapshot.visible) {
      final info = _infoByKey[place.key];
      if (info == null) continue;
      final key = ClusteredLocationInfo.coordinateKey(info.coordinates);
      groups.putIfAbsent(key, () => []).add(info);
    }

    // The places the markers will stand for, counted from the very groups they
    // are made from.
    var placeCount = 0;
    for (final group in groups.values) {
      placeCount += group.length;
    }

    // The place the person is looking at keeps being the one shown.
    final selectedKey = snapshot.selectedKey;

    final clusters = <String, ClusteredLocationInfo>{};
    final markers = <Marker>{};
    for (final entry in groups.entries) {
      final cluster = ClusteredLocationInfo(
        coordinates: entry.value.first.coordinates,
        items: entry.value,
      );
      if (selectedKey != null) {
        final at = cluster.items.indexWhere((item) => item.key == selectedKey);
        if (at >= 0) cluster.activeIndex = at;
      }
      clusters[entry.key] = cluster;
      await _createClusterMarker(cluster, markers);
      // Pins take a moment to draw; a newer draw (a filter change, a refresh)
      // that started meanwhile owns the map now.
      if (_disposed || !isCurrent()) return null;
    }
    return _Drawn(clusters, markers, placeCount);
  }

  /// Puts what the newest draw made on the map, and the open card with it, and
  /// the number of places the markers stand for: the three change together, in
  /// one step, so the count is always the markers' own.
  void _publishDrawn(MapFilterSnapshot snapshot, _Drawn drawn) {
    if (_disposed) return;
    _locationClusters = drawn.clusters;
    _markers = drawn.markers;
    _publishedPlaceCount = drawn.placeCount;
    _syncSelection();
    _safeNotifyListeners();
  }

  /// Points the open card at the rebuilt group its place is in, or closes it
  /// when the place is not on the map (deleted, or filtered out).
  void _syncSelection() {
    final key = _filters.selectedKey;
    if (key != null) {
      for (final cluster in _locationClusters.values) {
        final at = cluster.items.indexWhere((item) => item.key == key);
        if (at < 0) continue;
        final markerShowsAnother = cluster.activeIndex != at;
        cluster.activeIndex = at;
        _selectedCluster = cluster;
        _selectedLocationInfo = cluster.activeItem;
        if (markerShowsAnother) unawaited(updateClusterMarker(cluster));
        return;
      }
      _filters.select(null);
    }
    _selectedCluster = null;
    _selectedLocationInfo = null;
  }

  String _markerTitle(ClusteredLocationInfo cluster) {
    if (cluster.hasMultipleItems) {
      final loc = _localization;
      if (loc == null) return '';
      return loc
          .translate('mapItemsAtLocation')
          .replaceAll('{count}', '${cluster.itemCount}');
    }
    return displayTitle(cluster.activeItem);
  }

  // Create marker for a cluster
  Future<void> _createClusterMarker(
    ClusteredLocationInfo cluster,
    Set<Marker> markerSet,
  ) async {
    if (_disposed) return;

    final activeItem = cluster.activeItem;
    final key = ClusteredLocationInfo.coordinateKey(cluster.coordinates);

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

      markerSet.add(
        Marker(
          markerId: MarkerId(key), // Use coordinate key as marker ID
          position: cluster.coordinates,
          onTap: () => _onClusterTap(cluster),
          icon: customPin,
          infoWindow: InfoWindow(
            title: _markerTitle(cluster),
            snippet: activeItem.address,
          ),
        ),
      );
    } catch (e) {
      if (_disposed) return;

      // Fallback to default marker
      markerSet.add(
        Marker(
          markerId: MarkerId(key),
          position: cluster.coordinates,
          onTap: () => _onClusterTap(cluster),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            LocationColors.getMarkerHue(activeItem.type),
          ),
          infoWindow: InfoWindow(
            title: _markerTitle(cluster),
            snippet: activeItem.address,
          ),
        ),
      );
    }
  }

  // Update marker for a specific cluster (used when carousel changes)
  Future<void> updateClusterMarker(ClusteredLocationInfo cluster) async {
    if (_disposed) return;

    final key = ClusteredLocationInfo.coordinateKey(cluster.coordinates);
    final activeItem = cluster.activeItem;

    try {
      // Create new custom pin for the active item
      final customPin = await MapPinHelper.createCategoryPin(
        type: activeItem.type,
        color: activeItem.color,
        size: cluster.hasMultipleItems ? 82.0 : 72.0,
      );

      // The group was rebuilt (or removed) while the pin was drawn: its marker
      // is not this one any more.
      if (_disposed || !identical(_locationClusters[key], cluster)) return;

      _markers = {
        for (final marker in _markers)
          if (marker.markerId.value != key) marker,
        Marker(
          markerId: MarkerId(key),
          position: cluster.coordinates,
          onTap: () => _onClusterTap(cluster),
          icon: customPin,
          infoWindow: InfoWindow(
            title: _markerTitle(cluster),
            snippet: activeItem.address,
          ),
        ),
      };
      _safeNotifyListeners();
    } catch (e) {
      // The marker keeps the icon it had.
    }
  }

  // Handle cluster tap
  void _onClusterTap(ClusteredLocationInfo cluster) {
    if (_disposed) return;

    _filters.select(cluster.activeItem.key);
    _selectedCluster = cluster;
    _selectedLocationInfo = cluster.activeItem;
    _safeNotifyListeners();
  }

  // Update active item in cluster (called from carousel swipe)
  void updateClusterActiveIndex(int index) async {
    final cluster = _selectedCluster;
    if (_disposed || cluster == null) return;

    if (index < 0 || index >= cluster.itemCount) return;

    cluster.activeIndex = index;
    _filters.select(cluster.activeItem.key);
    _selectedLocationInfo = cluster.activeItem;

    // Update the marker icon to match the new active item
    await updateClusterMarker(cluster);
  }

  // Map event handlers
  void onMapCreated(GoogleMapController controller) {
    if (_disposed) return;

    // The map was created on the camera initialCameraFor gave it (the cities):
    // nothing is framed here, whatever markers already exist.
    _mapController = controller;
  }

  void onMapTap(LatLng position) {
    if (_disposed) return;
    clearSelectedLocation();
  }

  // ---- filter changes --------------------------------------------------------

  /// One layer, or all of them. Another layer also puts Rent / Sale, Property
  /// Type and Sort back to their defaults, in the same change as the layer; the
  /// place, Near Me and search are untouched, and nothing is read or asked.
  void setEntityType(LocationFilter type) => _afterFilterChange(
        _filters.setEntityType(type),
        MapCameraCause.filterChanged,
      );

  /// One city of the catalog, or null for every city. A city replaces Near Me
  /// (the two never hold together). The camera goes to that city's places, or to
  /// the city itself when none match.
  void setCity(String? city) {
    final waiting = _filters.isLocatingNearby;
    _afterFilterChange(_filters.setCity(city), MapCameraCause.cityChanged);
    _stopWaiting(waiting);
  }

  /// All UAE: no city and Near Me off, the default place to look. An explicit
  /// choice of the whole country, so the camera goes to the UAE overview, the
  /// frame the map opens on, whatever the filters let through, and even when
  /// the map was already on All UAE (the person may have moved away). Nothing
  /// is read and the device is not asked; a Near Me request still waiting is
  /// dropped.
  void setAllUae() {
    final waiting = _filters.isLocatingNearby;
    _afterFilterChange(
      _filters.setAllUae(),
      MapCameraCause.allUae,
      force: true,
    );
    _stopWaiting(waiting);
  }

  /// A place chosen while Near Me still waits for the device ends the wait at
  /// once, even when the choice changes nothing else (All UAE chosen on the
  /// default map, say): the chip must not go on showing the spinner for an
  /// answer that is no longer wanted.
  void _stopWaiting(bool waiting) {
    if (waiting && !_filters.isLocatingNearby) _safeNotifyListeners();
  }

  /// One property-type key, or null for every type.
  void setPropertyType(String? key) => _afterFilterChange(
        _filters.setPropertyType(key),
        MapCameraCause.filterChanged,
      );

  /// Rent, sale, or null for both.
  void setTransaction(MapTransaction? transaction) => _afterFilterChange(
        _filters.setTransaction(transaction),
        MapCameraCause.filterChanged,
      );

  /// Inclusive price bounds for Offers, or null to show every price.
  void setPriceRange(MapPriceRange? range) => _afterFilterChange(
        _filters.setPriceRange(range),
        MapCameraCause.filterChanged,
      );

  /// Default load order, or usable prices cheapest/dearest first with offers
  /// that have no usable price last.
  void setPriceMode(MapPriceMode mode) => _afterFilterChange(
        _filters.setPriceMode(mode),
        MapCameraCause.filterChanged,
      );

  /// The radius of Nearby, while it is on. The device's position is the one
  /// already held: nothing is asked of the device and nothing is read. The
  /// camera shows the new radius around it.
  void setNearbyRadius(int km) => _afterFilterChange(
        _filters.setNearbyRadius(km),
        MapCameraCause.nearbyRadiusChanged,
      );

  void disableNearby() => _afterFilterChange(
        _filters.disableNearby(),
        MapCameraCause.filterChanged,
      );

  /// Everything back to the default: all kinds, Nearby off, every city, type,
  /// transaction and price. Nothing is read: the places are already loaded.
  void clearFilters() => _afterFilterChange(
        _filters.clear(),
        MapCameraCause.filterChanged,
      );

  /// Turns Near Me on within [radiusKm] of the device's position, asking for
  /// location only now (the person chose Near Me), through the same boundary "my
  /// location" uses. A chosen city is replaced only when a position comes back.
  /// Returns what came back, so the screen can say so when Near Me could not be
  /// turned on (it then stays off, the city stays, and every place stays
  /// visible). Null when a request is already in progress, so a second tap
  /// starts nothing, and when the person chose something else while the device
  /// was being asked: that answer is not theirs any more, and says nothing.
  Future<NearbyFix?> enableNearby({
    int radiusKm = NearbyFilter.defaultRadiusKm,
  }) async {
    if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;

    // The wait starts here: the chip enters its loading state at once, and
    // nothing on the map changes until the position comes back. The request
    // takes its number before it first waits; that number tells, when the
    // answer comes, whether it is still the one wanted.
    final pending = _filters.enableNearby(_nearbyLocator, radiusKm: radiusKm);
    _safeNotifyListeners();
    final request = _filters.nearbyRequest;
    final fix = await pending;
    if (_disposed) return fix;

    if (fix is NearbyLocated) _hasLocationPermission = true;
    // A city, All UAE, Reset or Near Me again was chosen meanwhile: this answer
    // changes nothing and is not announced (an old failure must never be told
    // over a newer choice). The wait is over for it.
    if (request != _filters.nearbyRequest) {
      _safeNotifyListeners();
      return null;
    }
    // Only a position that was applied changes what is shown.
    _afterFilterChange(
      fix is NearbyLocated && _filters.state.nearbyEnabled,
      MapCameraCause.nearbyEnabled,
    );
    // The wait is over, whichever way it ended: the chip is usable again.
    _safeNotifyListeners();
    return fix;
  }

  /// A filter choice was made: draw it, and ask the camera to show it. The
  /// request and the draw are for the same snapshot, so the camera is planned
  /// from what was just drawn and only if no newer choice has been made.
  /// [force] asks for the camera (and a redraw) even when the filter itself did
  /// not change: a choice that is its own request to see something, All UAE.
  void _afterFilterChange(
    bool changed,
    MapCameraCause cause, {
    bool force = false,
  }) {
    if (_disposed || (!changed && !force)) return;

    // A card whose place the filter just removed closes at once, not after the
    // markers have been redrawn.
    if (_filters.selectedKey == null && _selectedCluster != null) {
      _selectedCluster = null;
      _selectedLocationInfo = null;
    }
    _safeNotifyListeners();

    final snapshot = _filters.snapshot;
    _pipeline.requestCamera(cause, snapshot);
    unawaited(_pipeline.show(snapshot));
  }

  // UI methods
  void toggleMapType() {
    if (_disposed) return;

    _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    _safeNotifyListeners();
  }

  void clearSelectedLocation() {
    if (_disposed) return;

    _filters.select(null);
    _selectedLocationInfo = null;
    _selectedCluster = null;
    _safeNotifyListeners();
  }

  /// The "my location" button: moves the camera to where the device is. The
  /// person tapped it, so this is where location may be asked for (through the
  /// system's own prompt, with no dialog of the app's before it).
  ///
  /// It only moves the camera. It does not turn Nearby on or touch any filter.
  /// Returns what came back, so the screen can say why the camera did not move;
  /// null when another location request is already in progress.
  Future<NearbyFix?> moveToCurrentLocation() async {
    if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;

    _locatingMe = true;
    // The position takes a moment. If the person chooses a city or a radius
    // meanwhile, that newer choice owns the camera and this one does not move it.
    final epoch = _pipeline.cameraEpoch;
    final fix = await _myLocationLocator.locate();
    _locatingMe = false;
    if (_disposed || fix is! NearbyLocated) return fix;
    if (!MapLocationMapper.isUsableCoordinate(fix.latitude, fix.longitude)) {
      return const NearbyUnavailable();
    }

    // Allowed now: the map may draw the device's own dot.
    _hasLocationPermission = true;
    _safeNotifyListeners();

    if (epoch == _pipeline.cameraEpoch) {
      // The device's position only: this move is its own cause, and an older
      // request that has not moved yet must not follow it.
      _pipeline.cancelCamera();
      _animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(fix.latitude, fix.longitude), 18.0),
      );
    }
    return fix;
  }

  /// Whether location access is already granted (used to show the device's own
  /// position on the map). It only reads the permission as it stands: it never
  /// asks and never gets a position, so the map opening never prompts for
  /// location.
  Future<void> checkLocationPermission() async {
    if (_disposed) return;

    try {
      _hasLocationPermission =
          await _device.permission() == DevicePermission.granted;
    } catch (e) {
      _hasLocationPermission = false;
    }
    _safeNotifyListeners();
  }

  // Move camera to specific location with zoom
  Future<void> animateToLocation(LatLng location) async {
    if (_disposed || _mapController == null) return;

    // A searched place is the person's newest choice: no older request that has
    // not moved yet may follow it.
    _pipeline.cancelCamera();
    _animateCamera(CameraUpdate.newLatLngZoom(location, 15.0));
  }

  /// Makes the camera move the pipeline planned. The plan is a camera position,
  /// worked out from the snapshot just published for the person's newest choice:
  /// one move, with nothing that runs after it.
  void _moveCamera(MapCameraPlan plan) {
    final target = plan.target;
    _animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(target.latitude, target.longitude),
          zoom: target.zoom,
        ),
      ),
    );
  }

  /// Starts one camera animation. It is not awaited and nothing follows it: a
  /// failure (the map was closed) leaves the camera where it is.
  void _animateCamera(CameraUpdate update) {
    final controller = _mapController;
    if (_disposed || controller == null) return;
    unawaited(
      controller.animateCamera(update).then<void>((_) {}, onError: (_) {}),
    );
  }

  @override
  void dispose() {
    _disposed = true;

    _loader.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}

/// What one draw of the markers made: the groups of places and their pins, and
/// how many places those groups hold.
final class _Drawn {
  const _Drawn(this.clusters, this.markers, this.placeCount);

  final Map<String, ClusteredLocationInfo> clusters;
  final Set<Marker> markers;
  final int placeCount;
}
