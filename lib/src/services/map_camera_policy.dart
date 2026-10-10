import 'dart:math' as math;

import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_city_geography.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';

// Where each city is lives with the rest of the city geography; it is
// re-exported so the camera policy's callers keep reading it from here.
export 'package:broker_wallet/src/services/map_city_geography.dart'
    show MapCityCameras, MapCityFrame;

/// Why the camera might move. Every move has one of these causes, and the cause
/// decides what it shows; a state notification on its own is never a cause.
enum MapCameraCause {
  /// The map opens: the UAE's cities (the map's starting camera, not a move).
  initialOpen,

  /// The person chose a city.
  cityChanged,

  /// The person chose All UAE: an explicit "show me the country". The camera
  /// goes to the UAE overview, the frame the map opens on, whatever the filters
  /// let through and wherever the camera was.
  allUae,

  /// Nearby was just turned on.
  nearbyEnabled,

  /// Nearby is on and the person chose another radius.
  nearbyRadiusChanged,

  /// The person tapped "my location": the device's position only. It does not
  /// turn Nearby on.
  locateMe,

  /// Any other choice: category, property type, rent/sale, price, Nearby off,
  /// Clear.
  filterChanged,

  /// The places were read again. The person is looking at the map: it stays
  /// where it is.
  backgroundRefresh,
}

/// What a planned camera move is about.
enum MapCameraSubject {
  /// The places the filter lets through (and only those).
  matchingPlaces,

  /// The chosen city itself, because no place matches.
  city,

  /// The area within the chosen Nearby radius of the device.
  nearbyArea,

  /// The UAE overview: the frame the map opens on.
  uaeOverview,
}

/// A camera move the map should make: where to go, and what it is about.
final class MapCameraPlan {
  const MapCameraPlan({
    required this.cause,
    required this.subject,
    required this.target,
  });

  final MapCameraCause cause;
  final MapCameraSubject subject;
  final MapCameraTarget target;
}

/// The camera for Nearby: the whole circle of the chosen radius around the
/// device, so 5, 10 and 25 km each look different and the person's own position
/// stays in the middle. Every place Nearby lets through is inside it by
/// definition, so showing the circle shows the matching places and nothing
/// outside the radius.
abstract final class NearbyCamera {
  /// A little room beyond the radius, so the edge of the circle and the pins
  /// near it are not cut.
  static const double marginFactor = 1.12;

  static const double minZoom = 5;
  static const double maxZoom = 16;

  // The length of a degree of latitude, from the same Earth radius the
  // distance filter uses.
  static const double _kmPerDegreeOfLatitude =
      GeoDistance.earthRadiusMeters * math.pi / 180 / 1000;

  /// The camera that shows the circle of [nearby]'s radius around its position
  /// inside the free part of [viewport].
  static MapCameraTarget target(NearbyFilter nearby, MapViewport viewport) {
    final km = nearby.radiusKm * marginFactor;
    final latitudeSpan = km / _kmPerDegreeOfLatitude;
    final cosine = math.max(0.01, math.cos(nearby.latitude * math.pi / 180));
    final longitudeSpan = km / (_kmPerDegreeOfLatitude * cosine);
    return MapFraming.fitBox(
      south: nearby.latitude - latitudeSpan,
      north: nearby.latitude + latitudeSpan,
      west: nearby.longitude - longitudeSpan,
      east: nearby.longitude + longitudeSpan,
      viewport: viewport,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }
}

/// Decides what the camera does for a cause, from the one snapshot the markers
/// were drawn from and the filter the person chose in it. Never from a cache of
/// markers, and never from "all the records".
abstract final class MapCameraPlanner {
  /// The move for [cause], or null when the camera should stay where it is.
  static MapCameraPlan? plan({
    required MapCameraCause cause,
    required MapFilterSnapshot snapshot,
    required MapViewport viewport,
  }) {
    switch (cause) {
      case MapCameraCause.initialOpen:
      case MapCameraCause.locateMe:
      case MapCameraCause.backgroundRefresh:
        // The starting camera is the map's own; "my location" goes to the
        // device; a refresh never moves what the person is looking at.
        return null;

      case MapCameraCause.nearbyEnabled:
      case MapCameraCause.nearbyRadiusChanged:
        final nearby = snapshot.state.nearby;
        if (nearby == null) return _places(cause, snapshot, viewport);
        return MapCameraPlan(
          cause: cause,
          subject: MapCameraSubject.nearbyArea,
          target: NearbyCamera.target(nearby, viewport),
        );

      case MapCameraCause.allUae:
        // An explicit choice of the whole country: the opening frame, from the
        // same function and the same room. Never the places the filters let
        // through, and never the old camera because nothing is visible.
        return MapCameraPlan(
          cause: cause,
          subject: MapCameraSubject.uaeOverview,
          target: UaeMapFraming.fit(viewport),
        );

      case MapCameraCause.cityChanged:
        final city = snapshot.state.city;
        if (city == null) return _places(cause, snapshot, viewport);
        // Places match: show them, and only them. None match: show the city
        // itself, never somebody else's places.
        final shown = _places(cause, snapshot, viewport);
        if (shown != null) return shown;
        final frame = MapCityCameras.of(city);
        if (frame == null) return null;
        return MapCameraPlan(
          cause: cause,
          subject: MapCameraSubject.city,
          target: MapFraming.centered(
            frame.latitude,
            frame.longitude,
            frame.zoom,
            viewport,
          ),
        );

      case MapCameraCause.filterChanged:
        return _places(cause, snapshot, viewport);
    }
  }

  /// The frame of the places the snapshot lets through, or null when there are
  /// none (the camera then stays: there is nothing of the person's to show).
  ///
  /// A place whose position is not one the map can show (for instance one that
  /// could not be in the UAE, see [MapLocationMapper.isMapLocation]) never
  /// frames the camera. The mapper already keeps such records off the map; this
  /// keeps the camera safe from a place that came any other way.
  static MapCameraPlan? _places(
    MapCameraCause cause,
    MapFilterSnapshot snapshot,
    MapViewport viewport,
  ) {
    final points = <MapGeoPoint>[
      for (final place in snapshot.visible)
        if (MapLocationMapper.isMapLocation(
          place.latitude,
          place.longitude,
        ))
          MapGeoPoint(place.latitude, place.longitude),
    ];
    if (points.isEmpty) return null;
    return MapCameraPlan(
      cause: cause,
      subject: MapCameraSubject.matchingPlaces,
      target: MapFraming.fitPoints(points, viewport: viewport),
    );
  }
}

/// A request for the camera to move, for the filter choice numbered
/// [stateVersion].
final class MapCameraIntent {
  const MapCameraIntent(this.cause, this.stateVersion);

  final MapCameraCause cause;
  final int stateVersion;
}

/// Draws the markers for a snapshot and returns what it drew, or null when it
/// stopped because a newer draw took over ([isCurrent] turned false).
typedef MapDraw<M> = Future<M?> Function(
  MapFilterSnapshot snapshot,
  bool Function() isCurrent,
);

/// Draws, publishes and frames the map, one latest-wins pass at a time.
///
///     filter choice -> snapshot -> draw markers (slow) -> publish -> camera
///
/// Three rules keep a slow older pass from touching the map after a newer one:
///
///  * only the NEWEST draw may publish; an older one that finishes late is
///    dropped before it publishes anything;
///  * the camera moves only for the person's NEWEST explicit choice, and only
///    against the snapshot that was just published for that same choice, in
///    the same synchronous step as the publish (there is no await between the
///    check and the move, and no fallback runs after one);
///  * the camera plan is made from that published snapshot and the filter in it
///    (a city, a radius), never from the markers on screen or from all records.
///
/// Places being read again go through [show] without a request, so they never
/// move the camera; if a choice was pending, it still moves once, over the
/// newest places.
class MapDrawPipeline<M> {
  MapDrawPipeline({
    required MapDraw<M> draw,
    required void Function(MapFilterSnapshot snapshot, M drawn) publish,
    required void Function(MapCameraPlan plan) moveCamera,
    required MapViewport Function() viewport,
  })  : _draw = draw,
        _publish = publish,
        _moveCamera = moveCamera,
        _viewport = viewport;

  final MapDraw<M> _draw;
  final void Function(MapFilterSnapshot snapshot, M drawn) _publish;
  final void Function(MapCameraPlan plan) _moveCamera;
  final MapViewport Function() _viewport;

  int _build = 0;
  int _epoch = 0;
  MapCameraIntent? _intent;

  /// Counts the times an explicit camera choice was made or cancelled. A slow
  /// action (the device's position arriving) remembers it at the start and
  /// moves the camera only if no newer choice was made since.
  int get cameraEpoch => _epoch;

  /// The person made a choice in [snapshot] that moves the camera: [cause] says
  /// how. It replaces any earlier request that has not moved yet.
  void requestCamera(MapCameraCause cause, MapFilterSnapshot snapshot) {
    _epoch++;
    _intent = MapCameraIntent(cause, snapshot.stateVersion);
  }

  /// Something else moved the camera on purpose (the device's position, a
  /// searched place): an older request that has not moved yet must not follow.
  void cancelCamera() {
    _epoch++;
    _intent = null;
  }

  /// Draws [snapshot]'s places and publishes them if this is still the newest
  /// draw, then moves the camera if a request for this same filter is waiting.
  /// Returns whether it published.
  Future<bool> show(MapFilterSnapshot snapshot) async {
    final build = ++_build;
    final drawn = await _draw(snapshot, () => build == _build);
    if (drawn == null || build != _build) return false;

    _publish(snapshot, drawn);
    _moveCameraFor(snapshot);
    return true;
  }

  void _moveCameraFor(MapFilterSnapshot published) {
    final intent = _intent;
    if (intent == null) return;
    if (intent.stateVersion != published.stateVersion) {
      // A request for an older choice can never move anything now; one for a
      // newer choice waits for the draw of that choice.
      if (intent.stateVersion < published.stateVersion) _intent = null;
      return;
    }
    _intent = null;
    final plan = MapCameraPlanner.plan(
      cause: intent.cause,
      snapshot: published,
      viewport: _viewport(),
    );
    if (plan != null) _moveCamera(plan);
  }
}
