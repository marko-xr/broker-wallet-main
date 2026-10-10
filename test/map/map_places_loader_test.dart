// How the map gets its places and keeps them current: the last read when it is
// still good, a read otherwise, one more read after every change (never two at
// once), nothing shown for another account or a closed screen, and a failed
// read that never turns into "no places". Plain Dart, run against fakes.

import 'dart:async';

import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';
import 'package:flutter_test/flutter_test.dart';

CachedLocationData _place(String id) => CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: 25.2,
      longitude: 55.27,
      type: LocationFilter.offers,
    );

List<String> _ids(List<CachedLocationData>? places) => [
      for (final place in places ?? const <CachedLocationData>[]) place.id,
    ];

class _FakeSource implements MapLocationSource {
  @override
  String? currentUserId = 'u1';

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get changes => _changes.stream;

  bool get isListening => _changes.hasListener;

  void change() => _changes.add(null);

  /// What an immediate read returns.
  List<CachedLocationData> next = [_place('a')];

  /// A read that throws.
  Object? failWith;

  /// With [gated], each read waits until it is released.
  bool gated = false;
  final List<Completer<List<CachedLocationData>>> pending = [];

  int loads = 0;

  /// Runs inside a read, before it answers.
  void Function()? duringRead;

  @override
  Future<List<CachedLocationData>> load() async {
    loads++;
    duringRead?.call();
    final error = failWith;
    if (error != null) throw error;
    if (gated) {
      final gate = Completer<List<CachedLocationData>>();
      pending.add(gate);
      return gate.future;
    }
    return next;
  }

  void release(int index, List<CachedLocationData> places) =>
      pending[index].complete(places);
}

class _FakeCache implements MapPlacesCache {
  @override
  List<CachedLocationData>? valid;

  @override
  int generation = 0;

  final List<List<CachedLocationData>> stored = [];
  final List<String> storedFor = [];

  @override
  void store(
    String userId,
    List<CachedLocationData> places, {
    required int generation,
  }) {
    // The real cache's rule: a read that raced a change is not kept.
    if (generation != this.generation) return;
    stored.add(places);
    storedFor.add(userId);
    valid = places;
  }
}

/// A position that is always there.
class _FixedLocator implements NearbyLocator {
  _FixedLocator(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  Future<NearbyFix> locate() async => NearbyLocated(latitude, longitude);
}

class _Harness {
  _Harness() {
    loader = MapPlacesLoader(
      source: source,
      cache: cache,
      onPlaces: (places, {required fresh}) async {
        shown.add(_ids(places));
        freshness.add(fresh);
      },
      onFailed: () => failures++,
    );
  }

  final source = _FakeSource();
  final cache = _FakeCache();
  late final MapPlacesLoader loader;

  final List<List<String>> shown = [];
  final List<bool> freshness = [];
  int failures = 0;
}

void main() {
  group('opening the map', () {
    test('a good last read opens it at once, with no read', () async {
      final h = _Harness();
      h.cache.valid = [_place('cached')];
      await h.loader.start();
      expect(h.shown, [
        ['cached'],
      ]);
      expect(h.freshness, [false]);
      expect(h.source.loads, 0);
      expect(
        h.source.isListening,
        isTrue,
        reason: 'later changes still refresh it',
      );
    });

    test(
      'with nothing good in the cache, it reads once and keeps the answer',
      () async {
        final h = _Harness();
        h.source.next = [_place('a'), _place('b')];
        await h.loader.start();
        expect(h.source.loads, 1);
        expect(h.shown, [
          ['a', 'b'],
        ]);
        expect(h.freshness, [true]);
        expect(_ids(h.cache.valid), ['a', 'b']);
        expect(h.cache.storedFor, ['u1']);
        expect(h.failures, 0);
      },
    );

    test('a cached read is not used when nobody is signed in', () async {
      final h = _Harness();
      h.cache.valid = [_place('cached')];
      h.source.currentUserId = null;
      await h.loader.start();
      expect(h.shown, isEmpty);
      expect(h.source.loads, 0);
      expect(h.failures, 1, reason: 'no session is a failure, not "no places"');
    });

    test('a person with no places gets an empty map, not an error', () async {
      final h = _Harness();
      h.source.next = const <CachedLocationData>[];
      await h.loader.start();
      expect(h.shown, [<String>[]]);
      expect(h.failures, 0);
    });
  });

  group('a read that fails', () {
    test('is reported, shows nothing and keeps nothing', () async {
      final h = _Harness();
      h.source.failWith = StateError('offline');
      await h.loader.start();
      expect(h.failures, 1);
      expect(h.shown, isEmpty);
      expect(h.cache.stored, isEmpty);
    });

    test('is retried by the next change, and then recovers', () async {
      final h = _Harness();
      h.source.failWith = StateError('offline');
      await h.loader.start();
      h.source.failWith = null;
      h.source.next = [_place('back')];
      h.source.change();
      await pumpEventQueue();
      expect(h.shown, [
        ['back'],
      ]);
      expect(h.failures, 1);
    });

    test(
      'a failing refresh is reported but never retracts what was shown',
      () async {
        final h = _Harness();
        await h.loader.start();
        h.source.failWith = StateError('timeout');
        await h.loader.refresh();
        expect(h.failures, 1);
        expect(
            h.shown,
            [
              ['a'],
            ],
            reason: 'the earlier places were not replaced by an empty answer');
      },
    );
  });

  group('keeping it current', () {
    test('a change reads the places again', () async {
      final h = _Harness();
      await h.loader.start();
      h.source.next = [_place('a'), _place('new')];
      h.source.change();
      await pumpEventQueue();
      expect(h.source.loads, 2);
      expect(h.shown.last, ['a', 'new']);
    });

    test(
      'a burst of changes during a read costs exactly one more read',
      () async {
        final h = _Harness();
        h.source.gated = true;
        final started = h.loader.start();
        await pumpEventQueue();
        expect(h.source.loads, 1);

        for (var i = 0; i < 5; i++) {
          h.source.change();
        }
        await pumpEventQueue();
        expect(h.source.loads, 1, reason: 'never two reads at once');

        h.source.release(0, [_place('old')]);
        await pumpEventQueue();
        expect(h.source.loads, 2, reason: 'one more, for the latest state');
        h.source.release(1, [_place('latest')]);
        await started;
        expect(h.shown.last, ['latest']);
        expect(h.source.loads, 2);
      },
    );

    test(
      'a change that lands during the very first read is not missed',
      () async {
        final h = _Harness();
        h.source.gated = true;
        final started = h.loader.start();
        await pumpEventQueue();
        h.source.change();
        h.source.release(0, [_place('before')]);
        await pumpEventQueue();
        expect(h.source.loads, 2);
        h.source.release(1, [_place('after')]);
        await started;
        expect(h.shown.last, ['after']);
      },
    );

    test('refresh reads now', () async {
      final h = _Harness();
      await h.loader.start();
      h.source.next = [_place('z')];
      await h.loader.refresh();
      expect(h.shown.last, ['z']);
    });
  });

  group('only for the right person and screen', () {
    test(
      'an answer for the first account is dropped when another signs in',
      () async {
        final h = _Harness();
        h.source.gated = true;
        final started = h.loader.start();
        await pumpEventQueue();
        h.source.currentUserId = 'u2';
        h.source.release(0, [_place('u1-place')]);
        await started;
        expect(h.shown, isEmpty);
        expect(h.cache.stored, isEmpty);
        expect(h.failures, 0, reason: 'not an error: just not theirs');
      },
    );

    test('nothing is shown or kept after the screen is closed', () async {
      final h = _Harness();
      h.source.gated = true;
      final started = h.loader.start();
      await pumpEventQueue();
      h.loader.dispose();
      h.source.release(0, [_place('late')]);
      await started;
      expect(h.shown, isEmpty);
      expect(h.cache.stored, isEmpty);
    });

    test(
      'a closed screen stops listening, and later changes do nothing',
      () async {
        final h = _Harness();
        await h.loader.start();
        expect(h.source.isListening, isTrue);
        h.loader.dispose();
        await pumpEventQueue();
        expect(h.source.isListening, isFalse);
        h.source.change();
        await pumpEventQueue();
        expect(h.source.loads, 1);
      },
    );

    test('a failure after the screen closed is not reported', () async {
      final h = _Harness();
      h.source.gated = true;
      final started = h.loader.start();
      await pumpEventQueue();
      h.loader.dispose();
      h.source.pending[0].completeError(StateError('late failure'));
      await started;
      expect(h.failures, 0);
    });
  });

  group('a change that races a read', () {
    test('the answer is shown but not kept for the next visit', () async {
      final h = _Harness();
      // The user's data changes while the read is in flight: the cache's count
      // moves on, so what this read found may already be out of date.
      h.source.duringRead = () => h.cache.generation++;
      await h.loader.start();
      expect(h.shown, [
        ['a'],
      ]);
      expect(
        h.cache.stored,
        isEmpty,
        reason: 'the count at the START of the read is what counts',
      );
    });
  });

  group('the filter works on what is loaded and never reads again', () {
    CachedLocationData placed(
      String id,
      LocationFilter type, {
      String? city,
      String? property,
      MapTransaction? transaction,
      double lat = 25.2,
    }) =>
        CachedLocationData(
          id: id,
          title: id,
          address: '',
          latitude: lat,
          longitude: 55.27,
          type: type,
          city: city,
          propertyType: property,
          transaction: transaction,
        );

    final data = [
      placed(
        'rent-villa',
        LocationFilter.offers,
        city: 'Dubai',
        property: 'villa',
        transaction: MapTransaction.rent,
      ),
      placed(
        'sale-flat',
        LocationFilter.offers,
        city: 'Abu Dhabi',
        property: 'apartment',
        transaction: MapTransaction.sale,
        lat: 24.5,
      ),
      placed('office', LocationFilter.offices, city: 'Dubai'),
    ];

    /// The map's wiring: what the loader finds goes to the filter.
    ({_FakeSource source, MapFilterController filters, MapPlacesLoader loader})
        wired() {
      final source = _FakeSource()..next = data;
      final filters = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _FakeCache(),
        onPlaces: (places, {required fresh}) async =>
            filters.setRecords(places),
        onFailed: () {},
      );
      return (source: source, filters: filters, loader: loader);
    }

    test('choosing, combining, clearing and Nearby cost no read', () async {
      final w = wired();
      await w.loader.start();
      expect(w.source.loads, 1);
      expect(w.filters.visible, hasLength(3));

      w.filters
        ..setEntityType(LocationFilter.offers)
        ..setCity('Dubai')
        ..setPropertyType('villa')
        ..setTransaction(MapTransaction.rent)
        ..select('offers:rent-villa');
      expect(_ids(w.filters.visible), ['rent-villa']);

      await w.filters.enableNearby(_FixedLocator(25.2, 55.27));
      expect(w.filters.state.nearbyEnabled, isTrue);
      w.filters
        ..setNearbyRadius(25)
        ..disableNearby()
        ..clear();
      expect(w.filters.visible, hasLength(3));

      expect(w.source.loads, 1, reason: 'not one read for any of that');
    });

    test(
      'a change in the user\'s data reads once more and keeps the filter',
      () async {
        final w = wired();
        await w.loader.start();
        w.filters.setCity('Dubai');
        expect(_ids(w.filters.visible), ['rent-villa', 'office']);

        w.source.next = [
          ...data,
          placed('new', LocationFilter.owners, city: 'Dubai'),
        ];
        w.source.change();
        await pumpEventQueue();

        expect(w.source.loads, 2);
        expect(w.filters.state.city, 'Dubai', reason: 'the choice is kept');
        expect(_ids(w.filters.visible), ['rent-villa', 'office', 'new']);
      },
    );

    test('a filter that matches nothing is not a failed load', () async {
      var failures = 0;
      final source = _FakeSource()..next = data;
      final filters = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _FakeCache(),
        onPlaces: (places, {required fresh}) async =>
            filters.setRecords(places),
        onFailed: () => failures++,
      );
      await loader.start();
      filters
        ..setEntityType(LocationFilter.watchmen)
        ..setCity('Ajman');
      expect(filters.visible, isEmpty);
      expect(filters.hasNoMatches, isTrue);
      expect(failures, 0, reason: 'the read succeeded: nothing failed');
      expect(filters.all, hasLength(3), reason: 'the data is all still there');
    });

    test('a failed load with nothing loaded is not "no matches"', () async {
      var failures = 0;
      final source = _FakeSource()..failWith = StateError('offline');
      final filters = MapFilterController();
      final loader = MapPlacesLoader(
        source: source,
        cache: _FakeCache(),
        onPlaces: (places, {required fresh}) async =>
            filters.setRecords(places),
        onFailed: () => failures++,
      );
      await loader.start();
      filters.setCity('Dubai');
      expect(failures, 1);
      expect(
        filters.hasNoMatches,
        isFalse,
        reason: 'it is a load failure, and the screen shows Retry for it',
      );
    });

    test(
      'a failed refresh keeps the filtered places that were loaded',
      () async {
        var failures = 0;
        final source = _FakeSource()..next = data;
        final filters = MapFilterController();
        final loader = MapPlacesLoader(
          source: source,
          cache: _FakeCache(),
          onPlaces: (places, {required fresh}) async =>
              filters.setRecords(places),
          onFailed: () => failures++,
        );
        await loader.start();
        filters.setCity('Dubai');
        source.failWith = StateError('timeout');
        await loader.refresh();
        expect(failures, 1);
        expect(_ids(filters.visible), ['rent-villa', 'office']);
      },
    );
  });
}
