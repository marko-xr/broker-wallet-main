// The camera the map opens on: the UAE where its cities are (Abu Dhabi to
// Khor Fakkan, Al Ain to Ras Al Khaimah), whatever records exist, wherever the
// person is, on any phone. It is worked out from the map's real
// size and handed to the map as its starting camera, so no timer waits for a
// layout and no marker load can override it; afterwards only the person moves
// the camera. Plain Dart: the framing is checked by projecting real places
// through it.

import 'dart:math' as math;

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where each catalog city is, for checking the frame (test data only: the app
/// has no such table and never reads one).
const Map<String, List<double>> _cityCentres = {
  'Dubai': [25.2048, 55.2708],
  'Abu Dhabi': [24.4539, 54.3773],
  'Sharjah': [25.3463, 55.4209],
  'Ajman': [25.4052, 55.5136],
  'Ras Al Khaimah': [25.7895, 55.9432],
  'Fujairah': [25.1288, 56.3265],
  'Umm Al Quwain': [25.5647, 55.5552],
  'Al Ain': [24.2075, 55.7447],
  'Khor Fakkan': [25.3395, 56.3563],
};

/// What the screen's controls cover, as the map screen passes it: the search bar
/// and the filter row below the status bar, the location button at the bottom,
/// a small gap at each side.
MapViewport _screen(double width, double height, {double statusBar = 24}) =>
    MapViewport(
      width: width,
      height: height,
      top: statusBar + 76 + 48 + 8,
      bottom: 16 + 40 + 16,
      left: 16,
      right: 16,
    );

final Map<String, MapViewport> _devices = {
  'small phone 320x568': _screen(320, 568),
  'phone 360x640': _screen(360, 640),
  'phone 360x780': _screen(360, 780),
  'phone 393x852': _screen(393, 852, statusBar: 48),
  'Samsung 412x915': _screen(412, 915, statusBar: 36),
  'large phone 430x932': _screen(430, 932, statusBar: 54),
  'tablet 800x1280': _screen(800, 1280),
  'landscape 844x390': _screen(844, 390, statusBar: 0),
};

const double _tolerance = 0.5; // pixels

void _expectInsideFreeArea(
  MapCameraTarget camera,
  MapViewport viewport,
  double lat,
  double lng,
  String reason,
) {
  final at = UaeMapFraming.project(camera, viewport, lat, lng);
  expect(at.x, greaterThanOrEqualTo(viewport.left - _tolerance),
      reason: reason);
  expect(
    at.x,
    lessThanOrEqualTo(viewport.width - viewport.right + _tolerance),
    reason: reason,
  );
  expect(at.y, greaterThanOrEqualTo(viewport.top - _tolerance), reason: reason);
  expect(
    at.y,
    lessThanOrEqualTo(viewport.height - viewport.bottom + _tolerance),
    reason: reason,
  );
}

void main() {
  group('the UAE bounds', () {
    test('the table of city centres is the catalog, nothing more or less', () {
      expect(
        _cityCentres.keys.toSet(),
        UaeAreaCatalog.supportedCities.toSet(),
        reason: 'a city added to the catalog must be checked here too',
      );
    });

    test('they are the cities\' own area, not the whole country\'s box', () {
      expect(UaeMapFraming.south, lessThan(UaeMapFraming.north));
      expect(UaeMapFraming.west, lessThan(UaeMapFraming.east));
      // Abu Dhabi to Khor Fakkan is a little under 2 degrees of longitude, and
      // Al Ain to Ras Al Khaimah a little over 1.5 of latitude.
      expect(UaeMapFraming.east - UaeMapFraming.west, inInclusiveRange(2, 3));
      expect(
        UaeMapFraming.north - UaeMapFraming.south,
        inInclusiveRange(1.5, 2.5),
      );
      // The whole country would start at the western border, 51.5 E: far west
      // of every city, which left half the screen empty.
      expect(UaeMapFraming.west, greaterThan(54));
    });

    test('there is room for a pin around the outermost cities', () {
      final lats = [for (final c in _cityCentres.values) c[0]];
      final lngs = [for (final c in _cityCentres.values) c[1]];
      const room = 0.08; // degrees: a pin and its edge
      expect(lngs.reduce(math.min) - UaeMapFraming.west, greaterThan(room));
      expect(UaeMapFraming.east - lngs.reduce(math.max), greaterThan(room));
      expect(lats.reduce(math.min) - UaeMapFraming.south, greaterThan(room));
      // More above the northmost city: a pin's body sits above its point.
      expect(UaeMapFraming.north - lats.reduce(math.max), greaterThan(0.15));
    });

    test('every city of the catalog lies inside them', () {
      for (final entry in _cityCentres.entries) {
        final lat = entry.value[0];
        final lng = entry.value[1];
        expect(lat, inInclusiveRange(UaeMapFraming.south, UaeMapFraming.north),
            reason: entry.key);
        expect(lng, inInclusiveRange(UaeMapFraming.west, UaeMapFraming.east),
            reason: entry.key);
      }
    });
  });

  group('the opening camera shows every city on every screen', () {
    for (final device in _devices.entries) {
      test('${device.key}: all nine cities are in the free part of the map',
          () {
        final viewport = device.value;
        final camera = UaeMapFraming.fit(viewport);
        for (final city in _cityCentres.entries) {
          _expectInsideFreeArea(
            camera,
            viewport,
            city.value[0],
            city.value[1],
            '${device.key}: ${city.key}',
          );
        }
      });

      test(
          '${device.key}: the whole country box fits, centred, as large as '
          'it can be', () {
        final viewport = device.value;
        final camera = UaeMapFraming.fit(viewport);

        for (final corner in [
          [UaeMapFraming.south, UaeMapFraming.west],
          [UaeMapFraming.south, UaeMapFraming.east],
          [UaeMapFraming.north, UaeMapFraming.west],
          [UaeMapFraming.north, UaeMapFraming.east],
        ]) {
          _expectInsideFreeArea(
            camera,
            viewport,
            corner[0],
            corner[1],
            '${device.key}: corner $corner',
          );
        }

        final sw = UaeMapFraming.project(
          camera,
          viewport,
          UaeMapFraming.south,
          UaeMapFraming.west,
        );
        final ne = UaeMapFraming.project(
          camera,
          viewport,
          UaeMapFraming.north,
          UaeMapFraming.east,
        );
        final boxWidth = ne.x - sw.x;
        final boxHeight = sw.y - ne.y;
        final freeWidth = viewport.freeWidth;
        final freeHeight = viewport.freeHeight;

        // Centred in the free part, not in the whole screen.
        expect(
          (sw.x + ne.x) / 2,
          closeTo(viewport.left + freeWidth / 2, _tolerance),
        );
        expect(
          (sw.y + ne.y) / 2,
          closeTo(viewport.top + freeHeight / 2, _tolerance),
        );
        // As large as the free part allows in the tighter direction: not a
        // far-away speck.
        final fill = math.max(boxWidth / freeWidth, boxHeight / freeHeight);
        expect(fill, closeTo(1, 0.01), reason: device.key);
      });

      test('${device.key}: a regional zoom, not the whole country or a street',
          () {
        final camera = UaeMapFraming.fit(device.value);
        expect(camera.zoom, inInclusiveRange(6.9, 9), reason: device.key);
      });
    }

    test('a portrait phone shows the cities about 7.7 zoom steps in', () {
      final camera = UaeMapFraming.fit(_devices['phone 360x640']!);
      expect(camera.zoom, inInclusiveRange(7.5, 7.9));
    });

    group('the cities fill the width of a portrait phone', () {
      // The owner found the map too wide: with the whole country's box the
      // cities were squeezed into the right 40% of the screen. They must now
      // spread from side to side, Abu Dhabi near the left edge and Khor Fakkan
      // and Fujairah near the right one.
      for (final device in _devices.entries) {
        final viewport = device.value;
        if (viewport.width >= viewport.height) continue;
        test('${device.key}: Abu Dhabi near the left, Fujairah near the right',
            () {
          final camera = UaeMapFraming.fit(viewport);
          double x(String city) =>
              UaeMapFraming.project(
                camera,
                viewport,
                _cityCentres[city]![0],
                _cityCentres[city]![1],
              ).x /
              viewport.width;

          final xs = [for (final city in _cityCentres.keys) x(city)];
          expect(
            xs.reduce(math.min),
            inInclusiveRange(0.02, 0.15),
            reason: '${device.key}: the westmost city (Abu Dhabi)',
          );
          expect(
            xs.reduce(math.max),
            inInclusiveRange(0.85, 0.98),
            reason: '${device.key}: the eastmost city (Khor Fakkan)',
          );
          expect(x('Abu Dhabi'), lessThan(0.15), reason: device.key);
          expect(x('Fujairah'), greaterThan(0.8), reason: device.key);
          // And not bunched on one side, as the whole-country frame had them.
          expect(
            xs.reduce(math.max) - xs.reduce(math.min),
            greaterThan(0.75),
            reason: '${device.key}: the cities span the screen',
          );
        });
      }
    });
  });

  group('it is not the old Dubai frame, nor anything the data decides', () {
    test('it is neither Dubai at zoom 11 nor any zoom close to a city', () {
      for (final device in _devices.entries) {
        final camera = UaeMapFraming.fit(device.value);
        expect(camera.zoom, lessThan(10), reason: device.key);
        expect(camera.zoom, isNot(11), reason: device.key);
      }
    });

    test('its centre is the middle of the cities\' area', () {
      final camera = UaeMapFraming.fit(_devices['phone 360x640']!);
      expect(
        camera.latitude,
        inInclusiveRange(UaeMapFraming.south, UaeMapFraming.north),
      );
      expect(
        camera.longitude,
        closeTo((UaeMapFraming.west + UaeMapFraming.east) / 2, 1e-6),
        reason: 'centred side to side',
      );
    });

    test('the same room gives the same camera every time', () {
      final viewport = _devices['phone 393x852']!;
      expect(UaeMapFraming.fit(viewport), UaeMapFraming.fit(viewport));
    });

    test(
        'the camera is a function of the room alone: the framing takes no '
        'places and no position', () {
      // `fit` takes only a viewport. This is the whole of its input, so no
      // record, city count or device position can change what it returns.
      final viewport = _devices['Samsung 412x915']!;
      final before = UaeMapFraming.fit(viewport);
      final controller = MapFilterController()
        ..setRecords([
          CachedLocationData(
            id: 'x',
            title: 'x',
            address: '',
            latitude: 25.2,
            longitude: 55.27,
            type: LocationFilter.offers,
            city: 'Dubai',
          ),
        ]);
      expect(controller.visible, hasLength(1));
      expect(UaeMapFraming.fit(viewport), before);
    });

    test('a room it cannot use frames the UAE for a common phone', () {
      final reference = UaeMapFraming.fit(MapViewport.referencePhone);
      for (final unusable in [
        const MapViewport(width: 0, height: 0),
        const MapViewport(width: double.nan, height: 640),
        const MapViewport(width: 360, height: double.infinity),
        const MapViewport(width: 360, height: 640, top: 700),
        const MapViewport(width: 360, height: 640, left: 200, right: 200),
        const MapViewport(width: 360, height: 640, top: -5),
      ]) {
        expect(unusable.isUsable, isFalse);
        expect(UaeMapFraming.fit(unusable), reference);
      }
    });

    test('the camera looks where it says it does', () {
      final viewport = _devices['phone 360x640']!;
      final camera = UaeMapFraming.fit(viewport);
      final centre = UaeMapFraming.project(
        camera,
        viewport,
        camera.latitude,
        camera.longitude,
      );
      expect(centre.x, closeTo(viewport.width / 2, 1e-6));
      expect(centre.y, closeTo(viewport.height / 2, 1e-6));
    });
  });

  group('the framing maths every camera move uses', () {
    final phone = _devices['phone 360x780']!;

    test('a box is framed exactly as the opening camera frames its own', () {
      expect(
        MapFraming.fitBox(
          south: UaeMapFraming.south,
          west: UaeMapFraming.west,
          north: UaeMapFraming.north,
          east: UaeMapFraming.east,
          viewport: phone,
          minZoom: UaeMapFraming.minZoom,
          maxZoom: UaeMapFraming.maxZoom,
        ),
        UaeMapFraming.fit(phone),
      );
    });

    test('points are all in view, with room for their pins', () {
      final random = math.Random(7);
      for (var round = 0; round < 25; round++) {
        final points = [
          for (var i = 0; i < 2 + random.nextInt(8); i++)
            MapGeoPoint(
              24.2 + random.nextDouble() * 1.6,
              54.3 + random.nextDouble() * 2.1,
            ),
        ];
        final camera = MapFraming.fitPoints(points, viewport: phone);
        for (final point in points) {
          final at = UaeMapFraming.project(
            camera,
            phone,
            point.latitude,
            point.longitude,
          );
          expect(at.x, inInclusiveRange(phone.left, phone.width - phone.right));
          expect(
              at.y, inInclusiveRange(phone.top, phone.height - phone.bottom));
        }
      }
    });

    test('one place, or several in one spot, get a street-level view', () {
      final one = MapFraming.fitPoints(
        const [MapGeoPoint(25.2, 55.27)],
        viewport: phone,
      );
      final same = MapFraming.fitPoints(
        const [MapGeoPoint(25.2, 55.27), MapGeoPoint(25.2, 55.27)],
        viewport: phone,
      );
      expect(one.zoom, 15);
      expect(same, one);
      // The limit is the caller's: raised, the same place may be framed closer,
      // up to the smallest box a place is given (about 0.008 degrees across).
      final closer = MapFraming.fitPoints(
        const [MapGeoPoint(25.2, 55.27)],
        viewport: phone,
        maxZoom: 17,
      );
      expect(closer.zoom, greaterThan(15));
      expect(closer.zoom, lessThanOrEqualTo(17));
      expect(
        MapFraming.fitPoints(
          const [MapGeoPoint(25.2, 55.27)],
          viewport: phone,
          maxZoom: 12,
        ).zoom,
        12,
        reason: 'and lowered, never closer than the caller allows',
      );
    });

    test('the zoom never goes below the limit, however far apart', () {
      final camera = MapFraming.fitPoints(
        const [MapGeoPoint(-40, -100), MapGeoPoint(60, 120)],
        viewport: phone,
      );
      expect(camera.zoom, 4);
    });

    test('a place is centred in the free part of the screen at the zoom asked',
        () {
      final camera = MapFraming.centered(24.4539, 54.3773, 10.5, phone);
      expect(camera.zoom, 10.5);
      final at = UaeMapFraming.project(camera, phone, 24.4539, 54.3773);
      expect(at.x, closeTo(phone.left + phone.freeWidth / 2, 0.5));
      expect(at.y, closeTo(phone.top + phone.freeHeight / 2, 0.5));
    });

    test('an unusable room frames for a common phone', () {
      const nowhere = MapViewport(width: 0, height: 0);
      expect(
        MapFraming.centered(25.2, 55.27, 11, nowhere),
        MapFraming.centered(25.2, 55.27, 11, MapViewport.referencePhone),
      );
      expect(
        MapFraming.fitPoints(
          const [MapGeoPoint(25.2, 55.27), MapGeoPoint(25.3, 55.4)],
          viewport: nowhere,
        ),
        MapFraming.fitPoints(
          const [MapGeoPoint(25.2, 55.27), MapGeoPoint(25.3, 55.4)],
          viewport: MapViewport.referencePhone,
        ),
      );
    });
  });

  group('the opening camera is decided once', () {
    test('before the map opens it is not applied; after, it is', () {
      final director = MapCameraDirector();
      expect(director.initialApplied, isFalse);
      director.initial(MapViewport.referencePhone);
      expect(director.initialApplied, isTrue);
    });

    test('rebuilds and new sizes keep the first camera', () {
      final director = MapCameraDirector();
      final first = director.initial(_devices['phone 360x640']!);
      for (final device in _devices.values) {
        expect(director.initial(device), first);
      }
      expect(first, UaeMapFraming.fit(_devices['phone 360x640']!));
    });

    test('records arriving, refreshing and being filtered do not re-frame it',
        () {
      final director = MapCameraDirector();
      final controller = MapFilterController();
      final first = director.initial(_devices['phone 360x640']!);

      CachedLocationData place(String id, String city) => CachedLocationData(
            id: id,
            title: id,
            address: '',
            latitude: 25.2,
            longitude: 55.27,
            type: LocationFilter.offers,
            city: city,
          );

      // The first records arrive (in one city only), then a refresh with others.
      controller.setRecords([place('a', 'Ajman')]);
      expect(director.initial(_devices['phone 360x640']!), first);
      controller.setRecords([place('a', 'Ajman'), place('b', 'Al Ain')]);
      expect(director.initial(_devices['phone 360x640']!), first);
      controller.setRecords(const <CachedLocationData>[]);
      expect(director.initial(_devices['phone 360x640']!), first);

      // A filter, then Clear, are not the opening camera either.
      controller.setCity('Ajman');
      expect(director.initial(_devices['phone 360x640']!), first);
      controller.clear();
      expect(director.initial(_devices['phone 360x640']!), first);
      expect(director.initialApplied, isTrue);
    });

    test('two screens each decide their own, once', () {
      final one = MapCameraDirector()..initial(_devices['phone 360x640']!);
      final other = MapCameraDirector();
      expect(other.initialApplied, isFalse);
      expect(one.initialApplied, isTrue);
    });
  });
}
