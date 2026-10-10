import 'dart:math' as math;

/// Where a map camera looks and how far in. [zoom] is Google Maps' own: at 0 the
/// whole world is 256 logical pixels wide, and every step doubles it.
final class MapCameraTarget {
  const MapCameraTarget({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  final double latitude;
  final double longitude;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is MapCameraTarget &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(latitude, longitude, zoom);
}

/// The room the map has, in logical pixels, and how much of its edges the
/// screen's own controls cover (the search bar and filter row at the top, the
/// location button at the bottom). The framing fits into what is left.
final class MapViewport {
  const MapViewport({
    required this.width,
    required this.height,
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
  });

  /// A common portrait phone, used when the real size is not known yet.
  static const MapViewport referencePhone =
      MapViewport(width: 360, height: 640);

  final double width;
  final double height;
  final double top;
  final double bottom;
  final double left;
  final double right;

  double get freeWidth => width - left - right;
  double get freeHeight => height - top - bottom;

  /// Whether there is real room to fit into.
  bool get isUsable =>
      width.isFinite &&
      height.isFinite &&
      top.isFinite &&
      bottom.isFinite &&
      left.isFinite &&
      right.isFinite &&
      top >= 0 &&
      bottom >= 0 &&
      left >= 0 &&
      right >= 0 &&
      freeWidth > 0 &&
      freeHeight > 0;
}

/// A point on the screen, in logical pixels from the map's top-left corner.
final class MapScreenPoint {
  const MapScreenPoint(this.x, this.y);

  final double x;
  final double y;
}

/// The camera the map opens on: the UAE where its cities are.
///
/// A fixed regional frame, from Abu Dhabi in the west to Khor Fakkan and Fujairah
/// in the east, and from Al Ain in the south to Ras Al Khaimah in the north. The
/// whole country's box would waste the left half of the screen on sea and desert
/// (the cities are all east of 54 E), so this one fits the cities' own area. It
/// does not depend on which records exist, on where the person is, or on how many
/// cities have data, so the map always opens in the same place. It is worked out
/// from the map's real size, so it is right on any phone, and it is handed to the
/// map as its starting camera: there is nothing to move afterwards, no timer to
/// wait on, and nothing a later data load could override.
abstract final class UaeMapFraming {
  /// The box the frame fits. Every city of the app's catalog lies inside it with
  /// room for its pin: Abu Dhabi is the westmost (54.38 E) and Khor Fakkan the
  /// eastmost (56.36 E); Al Ain the southmost (24.21 N) and Ras Al Khaimah the
  /// northmost (25.79 N), with more room above, where a pin's body sits.
  static const double south = 24.08;
  static const double north = 25.95;
  static const double west = 54.28;
  static const double east = 56.46;

  /// How far in or out a regional frame may go, whatever the screen.
  static const double minZoom = 4;
  static const double maxZoom = 9;

  /// The camera that shows the whole box inside the free part of [viewport],
  /// centred there. On a portrait phone the width is what limits it: the cities
  /// fill the screen from side to side.
  static MapCameraTarget fit(MapViewport viewport) => MapFraming.fitBox(
        south: south,
        west: west,
        north: north,
        east: east,
        viewport: viewport,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

  /// Where [latitude], [longitude] is on a map of [viewport]'s size looking
  /// through [camera]. Used to check that a frame really shows what it should.
  static MapScreenPoint project(
    MapCameraTarget camera,
    MapViewport viewport,
    double latitude,
    double longitude,
  ) =>
      MapFraming.project(camera, viewport, latitude, longitude);
}

/// A place on the Earth, in plain numbers.
final class MapGeoPoint {
  const MapGeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Where a camera must look to show what the map is meant to show: a box, some
/// points, or one place at a chosen zoom. Pure maths on the Web Mercator map
/// Google Maps draws, from the map's real size, so every frame is exact on any
/// screen and needs no layout, no timer and no native bounds call that can fail.
///
/// Each answer is a camera position to go to, not a list of steps: nothing runs
/// after it that could land late.
abstract final class MapFraming {
  /// Google Maps' world width, in logical pixels, at zoom 0.
  static const double _worldAtZoomZero = 256;

  /// The camera that shows the whole box inside the free part of [viewport],
  /// centred there, as far in as the box allows between [minZoom] and [maxZoom].
  static MapCameraTarget fitBox({
    required double south,
    required double west,
    required double north,
    required double east,
    required MapViewport viewport,
    double minZoom = 2,
    double maxZoom = 18,
  }) {
    final room = viewport.isUsable ? viewport : MapViewport.referencePhone;

    // How big the box is at zoom 0, and so how far in the free part allows.
    final boxWidth = (east - west) / 360 * _worldAtZoomZero;
    final boxHeight = (_v(south) - _v(north)) * _worldAtZoomZero;
    final zoom = math
        .min(
          _log2(room.freeWidth / boxWidth),
          _log2(room.freeHeight / boxHeight),
        )
        .clamp(minZoom, maxZoom)
        .toDouble();

    // The box's middle, moved so it lands in the middle of the free part (the
    // controls cover the edges, so the free part is not the screen's middle).
    return _cameraAt(
      (_u(west) + _u(east)) / 2,
      (_v(north) + _v(south)) / 2,
      zoom,
      room,
    );
  }

  /// The camera that shows all of [points], with [margin] of their span around
  /// them (so a pin at the edge is not cut) and never closer than [maxZoom] (a
  /// single place, or several in one building, gets a street-level view, not a
  /// pixel). [points] must not be empty.
  static MapCameraTarget fitPoints(
    Iterable<MapGeoPoint> points, {
    required MapViewport viewport,
    double margin = 0.12,
    double minHalfSpan = 0.004,
    double minZoom = 4,
    double maxZoom = 15,
  }) {
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    final halfLat = math.max((maxLat - minLat) / 2, minHalfSpan);
    final halfLng = math.max((maxLng - minLng) / 2, minHalfSpan);
    final centreLat = (minLat + maxLat) / 2;
    final centreLng = (minLng + maxLng) / 2;
    return fitBox(
      south: centreLat - halfLat * (1 + margin),
      north: centreLat + halfLat * (1 + margin),
      west: centreLng - halfLng * (1 + margin),
      east: centreLng + halfLng * (1 + margin),
      viewport: viewport,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  /// The camera that puts [latitude], [longitude] in the middle of the free
  /// part of [viewport] at [zoom].
  static MapCameraTarget centered(
    double latitude,
    double longitude,
    double zoom,
    MapViewport viewport,
  ) {
    final room = viewport.isUsable ? viewport : MapViewport.referencePhone;
    return _cameraAt(_u(longitude), _v(latitude), zoom, room);
  }

  /// Where [latitude], [longitude] is on a map of [viewport]'s size looking
  /// through [camera].
  static MapScreenPoint project(
    MapCameraTarget camera,
    MapViewport viewport,
    double latitude,
    double longitude,
  ) {
    final world = _worldAtZoomZero * math.pow(2, camera.zoom);
    return MapScreenPoint(
      viewport.width / 2 + (_u(longitude) - _u(camera.longitude)) * world,
      viewport.height / 2 + (_v(latitude) - _v(camera.latitude)) * world,
    );
  }

  // The camera whose view puts the world point (u, v) (0..1 across the world)
  // in the middle of the free part of [room], at [zoom].
  static MapCameraTarget _cameraAt(
    double u,
    double v,
    double zoom,
    MapViewport room,
  ) {
    final world = _worldAtZoomZero * math.pow(2, zoom);
    final shiftX = (room.left - room.right) / 2;
    final shiftY = (room.top - room.bottom) / 2;
    return MapCameraTarget(
      latitude: _latitudeOf((v * world - shiftY) / world),
      longitude: ((u * world - shiftX) / world) * 360 - 180,
      zoom: zoom,
    );
  }

  // Web Mercator, as 0..1 across the world (v grows southwards).
  static double _u(double longitude) => (longitude + 180) / 360;

  static double _v(double latitude) {
    final sine = math.sin(latitude * math.pi / 180);
    return 0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi);
  }

  static double _latitudeOf(double v) =>
      math.atan(_sinh(math.pi * (1 - 2 * v))) * 180 / math.pi;

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  static double _log2(double x) => math.log(x) / math.ln2;
}

/// Decides the camera the map opens on, once.
///
/// The first answer is kept and every later one is that same answer, so a
/// rebuild, a change of size, or any data arriving can never frame the UAE
/// again; only the person (or an explicit choice of theirs) moves the camera
/// after that.
final class MapCameraDirector {
  MapCameraTarget? _initial;

  /// Whether the opening camera has been decided (the one-time guard).
  bool get initialApplied => _initial != null;

  MapCameraTarget initial(MapViewport viewport) =>
      _initial ??= UaeMapFraming.fit(viewport);
}
