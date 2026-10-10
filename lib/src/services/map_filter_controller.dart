import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_property_type_options.dart';

/// What asking the device where it is came back with.
sealed class NearbyFix {
  const NearbyFix();
}

/// The device's position. Used to filter, then kept only in memory.
final class NearbyLocated extends NearbyFix {
  const NearbyLocated(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Location access was refused this time; the system may still ask again.
final class NearbyDenied extends NearbyFix {
  const NearbyDenied();
}

/// Location access is refused for good: the system will not ask again, and
/// neither does the app. Only the device's settings can change it.
final class NearbyPermanentlyDenied extends NearbyFix {
  const NearbyPermanentlyDenied();
}

/// Location services are switched off on the device.
final class NearbyServicesOff extends NearbyFix {
  const NearbyServicesOff();
}

/// No position could be had (a timeout, or the platform failed).
final class NearbyUnavailable extends NearbyFix {
  const NearbyUnavailable();
}

/// Where the device's position comes from. Asked only after the person taps
/// "my location" or turns Nearby on, never because the map opened.
abstract interface class NearbyLocator {
  Future<NearbyFix> locate();
}

/// The localization key of the short, non-blocking message that tells the
/// person why [fix] gave no position, or null when it gave one. The one
/// wording of these outcomes, for both "my location" and Nearby.
String? nearbyFixMessageKey(NearbyFix fix) => switch (fix) {
      NearbyLocated() => null,
      NearbyDenied() => 'locationPermissionDenied',
      NearbyPermanentlyDenied() => 'mapLocationBlocked',
      NearbyServicesOff() => 'locationServiceDisabledMessage',
      NearbyUnavailable() => 'mapNearbyUnavailable',
    };

/// One consistent picture of the map's filter at one moment: the choice, the
/// places it lets through, and the open card. The markers and the camera are
/// both drawn from ONE snapshot, never from live state read at different times,
/// so a slow draw can never mix an old filter's places with a new filter's
/// camera.
final class MapFilterSnapshot {
  const MapFilterSnapshot({
    required this.stateVersion,
    required this.recordsVersion,
    required this.state,
    required this.visible,
    required this.selectedKey,
  });

  /// Counts the person's filter choices. A refresh of the places does not
  /// change it, so "the filter the person chose" can be told from "the same
  /// filter over newer places".
  final int stateVersion;

  /// Counts the times the loaded places were replaced.
  final int recordsVersion;

  final MapFilterState state;

  /// The places [state] lets through, in order.
  final List<CachedLocationData> visible;

  /// The open card's place (one of [visible]), or null.
  final String? selectedKey;
}

/// The map's filter, over the places already loaded.
///
///     all places  ->  [state]  ->  [visible]  ->  markers and the open card
///
/// A change of filter recomputes [visible] from [all] in memory: nothing is
/// read from the backend. The selected place is kept only while it is visible,
/// so a card never outlives a filter (or a refresh) that removed its place.
class MapFilterController {
  List<CachedLocationData> _all = const <CachedLocationData>[];
  MapFilterState _state = MapFilterState.initial;
  List<CachedLocationData> _visible = const <CachedLocationData>[];
  String? _selectedKey;
  int _stateVersion = 0;
  int _recordsVersion = 0;

  /// Identifies the newest Nearby request: a position that arrives after the
  /// filter was cleared, turned off or asked for again is ignored.
  int _nearbyRequest = 0;

  /// The Nearby request whose position is being awaited, or null.
  int? _locatingRequest;

  /// Every loaded place, whatever the filter says.
  List<CachedLocationData> get all => _all;

  MapFilterState get state => _state;

  /// The places the filter lets through.
  List<CachedLocationData> get visible => _visible;

  /// The key ([CachedLocationData.key]) of the place whose card is open, or
  /// null. Always one of [visible].
  String? get selectedKey => _selectedKey;

  bool get filtersActive => _state.isActive;

  /// Whether Nearby was asked for and its position has not come back yet.
  bool get isLocatingNearby => _locatingRequest != null;

  /// The number of the newest Near Me request. [enableNearby] takes the next
  /// number before it first waits, and choosing a city, All UAE, Reset or
  /// turning Near Me off takes one too. A caller that remembers the number it
  /// was given can tell, when its answer comes, whether it is still the one
  /// wanted: it is the very protection that makes this controller ignore a late
  /// position, read, not a second one.
  int get nearbyRequest => _nearbyRequest;

  /// The filter as it is right now, in one piece.
  MapFilterSnapshot get snapshot => MapFilterSnapshot(
        stateVersion: _stateVersion,
        recordsVersion: _recordsVersion,
        state: _state,
        visible: _visible,
        selectedKey: _selectedKey,
      );

  /// Places were loaded, and the filter lets none of them through. This is not
  /// a failed load: the data is all there.
  bool get hasNoMatches => _all.isNotEmpty && _visible.isEmpty;

  Map<LocationFilter, int> get entityCounts =>
      MapFilterOptions.entityCounts(_all);

  /// Every city of the catalog the forms use, whatever is loaded.
  List<String> get cityOptions => MapFilterOptions.cities();

  List<String> get propertyTypeOptions =>
      MapPropertyTypeOptions.forLayer(_state.entityType);

  /// The loaded places changed (a read finished). The filter stays as it is.
  void setRecords(List<CachedLocationData> places) {
    _all = List<CachedLocationData>.unmodifiable(places);
    _recordsVersion++;
    _recompute();
  }

  // Each setter returns whether anything changed, so the caller redraws only
  // when it must.

  /// One layer, or all of them. Another layer clears incompatible filters in
  /// this one change; only a type valid for both Offers and Owners survives
  /// ([MapFilterState.withEntityType]); where the map looks, a position still
  /// being asked for, and the loaded places are not touched.
  bool setEntityType(LocationFilter type) =>
      _change(_state.withEntityType(type));

  /// A city replaces Near Me: a city and a circle around the device are two
  /// ways of saying where to look, never both. A Near Me position that is still
  /// on its way is not wanted any more either, and is dropped when it arrives.
  /// Null is every city and leaves Near Me as it is (the Location list uses
  /// [setAllUae]).
  bool setCity(String? city) {
    if (city != null) _dropNearbyRequest();
    return _change(_state.withCity(city));
  }

  /// All UAE: no city and Near Me off, the default place to look. It reads
  /// nothing and does not ask the device; a Near Me position still on its way is
  /// dropped.
  bool setAllUae() {
    _dropNearbyRequest();
    return _change(_state.withCity(null).withNearby(null));
  }

  bool setPropertyType(String? key) => _change(_state.withPropertyType(key));

  bool setTransaction(MapTransaction? transaction) =>
      _change(_state.withTransaction(transaction));

  bool setPriceRange(MapPriceRange? range) =>
      _change(_state.withPriceRange(range));

  /// Default load order, or priced Offers first and unpriced Offers last.
  bool setPriceMode(MapPriceMode mode) => _change(_state.withPriceMode(mode));

  /// Changes the radius of Nearby while it is on; does nothing while it is off.
  bool setNearbyRadius(int km) {
    final nearby = _state.nearby;
    if (nearby == null || nearby.radiusKm == km) return false;
    return _change(_state.withNearby(nearby.withRadius(km)));
  }

  bool disableNearby() {
    _dropNearbyRequest();
    return _change(_state.withNearby(null));
  }

  /// Back to the default: every kind, every city, every type, rent and sale,
  /// every price, Nearby off. The loaded places are not touched.
  bool clear() {
    _dropNearbyRequest();
    return _change(MapFilterState.initial);
  }

  /// Turns Nearby on at the device's position.
  ///
  /// The position is asked for here and only here. Unless it comes back
  /// ([NearbyLocated], and a usable one), Nearby stays off and everything stays
  /// visible, a chosen city included; the outcome is returned so the screen can
  /// say what happened. When it does come back, Near Me replaces the city (the
  /// two never hold together), in the one change that turns Near Me on.
  ///
  /// Everything already shown stays shown while the position is awaited: the
  /// filter changes once, when the position arrives. [isLocatingNearby] is true
  /// for exactly that wait, and false again however it ends (a position, a
  /// refusal, a failure, or the person clearing the filter meanwhile).
  Future<NearbyFix> enableNearby(
    NearbyLocator locator, {
    int radiusKm = NearbyFilter.defaultRadiusKm,
  }) async {
    final request = ++_nearbyRequest;
    _locatingRequest = request;
    NearbyFix fix;
    try {
      fix = await locator.locate();
    } catch (_) {
      fix = const NearbyUnavailable();
    }
    // The wait is over for this request (a newer one keeps its own).
    if (_locatingRequest == request) _locatingRequest = null;
    // Cleared, turned off or asked again meanwhile: this answer is not wanted.
    if (request != _nearbyRequest) return fix;

    if (fix is NearbyLocated) {
      if (!MapLocationMapper.isUsableCoordinate(fix.latitude, fix.longitude)) {
        return const NearbyUnavailable();
      }
      _change(
        _state.withNearby(
          NearbyFilter(
            latitude: fix.latitude,
            longitude: fix.longitude,
            radiusKm: radiusKm,
          ),
        ),
      );
    }
    return fix;
  }

  /// Opens the card of the place with [key], or closes it with null. A place
  /// that is not visible cannot be selected.
  void select(String? key) {
    if (key == null) {
      _selectedKey = null;
      return;
    }
    if (_visible.any((place) => place.key == key)) _selectedKey = key;
  }

  /// Forgets a Near Me request that is waiting for the device's position: the
  /// person chose something else meanwhile, so that position is not wanted.
  void _dropNearbyRequest() {
    _nearbyRequest++;
    _locatingRequest = null;
  }

  bool _change(MapFilterState next) {
    if (next == _state) return false;
    _state = next;
    _stateVersion++;
    _recompute();
    return true;
  }

  void _recompute() {
    _visible = List<CachedLocationData>.unmodifiable(
      MapFilterEngine.apply(_all, _state),
    );
    final selected = _selectedKey;
    if (selected != null && !_visible.any((place) => place.key == selected)) {
      _selectedKey = null;
    }
  }
}
