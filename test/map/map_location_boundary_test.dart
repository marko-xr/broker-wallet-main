// How the map gets the device's position, for "my location" and for Nearby.
//
// One boundary serves both. It asks the operating system for permission only
// when a tap reaches it and the system can still be asked; it never asks again
// for a permission refused for good; it shows nothing of its own; and every way
// it can fail is a result the screen words, never an exception, a platform
// message or a coordinate. Plain Dart, run against a fake phone that records
// everything it is asked.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/map_nearby_locator.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone that does what it is told and writes down every question.
class _FakePhone implements DeviceLocationPlatform {
  _FakePhone({
    this.services = true,
    this.permissionNow = DevicePermission.granted,
    this.answerToPrompt = DevicePermission.granted,
    this.point = const DevicePoint(25.2048, 55.2708),
  });

  bool services;
  DevicePermission permissionNow;

  /// What the system's prompt ends up with, when it is shown.
  DevicePermission answerToPrompt;
  DevicePoint point;

  /// Makes the position fail (a timeout, say).
  Object? positionFails;

  /// While set, the new fix does not come until the test completes it.
  Completer<DevicePoint>? positionGate;

  /// While set, the system's prompt is not answered until the test completes it.
  Completer<DevicePermission>? promptGate;

  /// What the system already holds (a position it took earlier), or nothing.
  DevicePoint? held;

  /// Makes asking for the held position fail.
  Object? heldFails;

  /// Makes reading the permission fail.
  Object? permissionFails;

  final List<String> calls = [];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<bool> servicesEnabled() async {
    calls.add('services');
    return services;
  }

  @override
  Future<DevicePermission> permission() async {
    calls.add('permission');
    final error = permissionFails;
    if (error != null) throw error;
    return permissionNow;
  }

  @override
  Future<DevicePermission> requestPermission() async {
    calls.add('prompt');
    final gate = promptGate;
    if (gate != null) {
      permissionNow = await gate.future;
      return permissionNow;
    }
    permissionNow = answerToPrompt;
    return permissionNow;
  }

  @override
  Future<DevicePoint?> lastKnownPosition() async {
    calls.add('lastKnown');
    final error = heldFails;
    if (error != null) throw error;
    return held;
  }

  @override
  Future<DevicePoint> position({required bool precise}) async {
    calls.add(precise ? 'position:fine' : 'position:rough');
    final error = positionFails;
    if (error != null) throw error;
    final gate = positionGate;
    if (gate != null) return gate.future;
    return point;
  }
}

CachedLocationData _place(String id) => CachedLocationData(
      id: id,
      title: id,
      address: '',
      latitude: 25.2048,
      longitude: 55.2708,
      type: LocationFilter.offers,
      city: 'Dubai',
    );

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  group('opening the map asks the phone nothing', () {
    test('building the boundary neither asks permission nor gets a position',
        () {
      final phone = _FakePhone(permissionNow: DevicePermission.denied);
      // Both ways the map builds it: for Nearby (rough) and for "my location".
      DeviceNearbyLocator(phone);
      DeviceNearbyLocator(phone, precise: true);
      expect(phone.calls, isEmpty);
    });

    test('reading the permission, as the map does on opening, never prompts',
        () async {
      final phone = _FakePhone(permissionNow: DevicePermission.denied);
      expect(await phone.permission(), DevicePermission.denied);
      expect(phone.calls, ['permission']);
      expect(phone.count('prompt'), 0);
      expect(phone.count('position:fine') + phone.count('position:rough'), 0);
    });
  });

  group('"my location" (a fine position)', () {
    test('permission already given: no prompt, then the position', () async {
      final phone = _FakePhone();
      final fix = await DeviceNearbyLocator(phone, precise: true).locate();
      expect(phone.calls, ['services', 'permission', 'position:fine']);
      expect(fix, isA<NearbyLocated>());
      final located = fix as NearbyLocated;
      expect(located.latitude, 25.2048);
      expect(located.longitude, 55.2708);
    });

    test('the system is asked only after the tap, and only when it can be',
        () async {
      final phone = _FakePhone(permissionNow: DevicePermission.denied);
      final locator = DeviceNearbyLocator(phone, precise: true);
      expect(phone.calls, isEmpty, reason: 'nothing before the tap');

      final fix = await locator.locate();
      expect(phone.calls, [
        'services',
        'permission',
        'prompt',
        'position:fine',
      ]);
      expect(fix, isA<NearbyLocated>());
    });

    test('refused at the prompt: no position, and a result to word', () async {
      final phone = _FakePhone(
        permissionNow: DevicePermission.denied,
        answerToPrompt: DevicePermission.denied,
      );
      final fix = await DeviceNearbyLocator(phone, precise: true).locate();
      expect(fix, isA<NearbyDenied>());
      expect(phone.count('position:fine'), 0);
      expect(phone.calls.last, 'prompt');
    });
  });

  group('Nearby (a rough position)', () {
    test('asks the system only after the tap, then takes a rough position',
        () async {
      final phone = _FakePhone(permissionNow: DevicePermission.denied);
      final locator = DeviceNearbyLocator(phone);
      expect(phone.calls, isEmpty);

      final fix = await locator.locate();
      // The system holds no position: a new, rough fix is waited for.
      expect(phone.calls, [
        'services',
        'permission',
        'prompt',
        'lastKnown',
        'position:rough',
      ]);
      expect(fix, isA<NearbyLocated>());
    });

    test(
        'it is the same flow as "my location": only the accuracy differs, '
        'and Nearby also looks at the position the system holds', () async {
      final rough = _FakePhone(permissionNow: DevicePermission.denied);
      final fine = _FakePhone(permissionNow: DevicePermission.denied);
      await DeviceNearbyLocator(rough).locate();
      await DeviceNearbyLocator(fine, precise: true).locate();
      expect(
        [
          for (final call in rough.calls)
            if (call != 'lastKnown') call.split(':').first,
        ],
        [for (final call in fine.calls) call.split(':').first],
      );
      expect(rough.count('lastKnown'), 1);
      expect(fine.count('lastKnown'), 0,
          reason: '"my location" is precise: it never takes a held position');
    });

    test('refused: Nearby stays off and every loaded place stays visible',
        () async {
      final phone = _FakePhone(
        permissionNow: DevicePermission.denied,
        answerToPrompt: DevicePermission.denied,
      );
      final filters = MapFilterController()
        ..setRecords([_place('a'), _place('b'), _place('c')]);

      final fix = await filters.enableNearby(DeviceNearbyLocator(phone));

      expect(fix, isA<NearbyDenied>());
      expect(filters.state.nearby, isNull, reason: 'Nearby stays OFF');
      expect(filters.state.nearbyEnabled, isFalse);
      expect(filters.filtersActive, isFalse);
      expect(filters.visible, hasLength(3), reason: 'the markers stay');
      expect(filters.hasNoMatches, isFalse, reason: 'not a "no matches" state');
    });

    test('refused for good: the same, and no prompt was shown', () async {
      final phone =
          _FakePhone(permissionNow: DevicePermission.permanentlyDenied);
      final filters = MapFilterController()..setRecords([_place('a')]);

      final fix = await filters.enableNearby(DeviceNearbyLocator(phone));

      expect(fix, isA<NearbyPermanentlyDenied>());
      expect(filters.state.nearby, isNull);
      expect(filters.visible, hasLength(1));
      expect(phone.count('prompt'), 0);
    });

    test(
        'allowed: Nearby turns on, at the radius, with the position kept only '
        'in the filter', () async {
      final phone = _FakePhone(point: const DevicePoint(25.21, 55.27));
      final filters = MapFilterController()..setRecords([_place('a')]);

      final fix = await filters.enableNearby(
        DeviceNearbyLocator(phone),
        radiusKm: 5,
      );

      expect(fix, isA<NearbyLocated>());
      expect(filters.state.nearby, isNotNull);
      expect(filters.state.nearby!.radiusKm, 5);
      expect(filters.state.nearby!.latitude, 25.21);
    });
  });

  group('a permission refused for good is never asked for again', () {
    test('it is reported, and the system is not asked', () async {
      final phone =
          _FakePhone(permissionNow: DevicePermission.permanentlyDenied);
      final fix = await DeviceNearbyLocator(phone, precise: true).locate();
      expect(fix, isA<NearbyPermanentlyDenied>());
      expect(phone.calls, ['services', 'permission']);
    });

    test('tapping again and again never prompts', () async {
      final phone =
          _FakePhone(permissionNow: DevicePermission.permanentlyDenied);
      final nearby = DeviceNearbyLocator(phone);
      final mine = DeviceNearbyLocator(phone, precise: true);
      for (var tap = 0; tap < 5; tap++) {
        expect(await nearby.locate(), isA<NearbyPermanentlyDenied>());
        expect(await mine.locate(), isA<NearbyPermanentlyDenied>());
      }
      expect(phone.count('prompt'), 0);
      expect(phone.count('position:fine') + phone.count('position:rough'), 0);
    });

    test('a prompt that comes back "for good" is reported the same way',
        () async {
      final phone = _FakePhone(
        permissionNow: DevicePermission.denied,
        answerToPrompt: DevicePermission.permanentlyDenied,
      );
      final locator = DeviceNearbyLocator(phone);
      expect(await locator.locate(), isA<NearbyPermanentlyDenied>());
      expect(phone.count('prompt'), 1);
      // The next tap does not prompt again.
      expect(await locator.locate(), isA<NearbyPermanentlyDenied>());
      expect(phone.count('prompt'), 1);
    });
  });

  group('every other failure is a result, not an exception', () {
    test('location services off: said so, nothing else is asked', () async {
      final phone = _FakePhone(
        services: false,
        permissionNow: DevicePermission.denied,
      );
      final fix = await DeviceNearbyLocator(phone, precise: true).locate();
      expect(fix, isA<NearbyServicesOff>());
      expect(phone.calls, ['services'],
          reason: 'no prompt and no position while services are off');
    });

    test('no position in time: unavailable, and nothing escapes', () async {
      final phone = _FakePhone()..positionFails = StateError('timeout');
      final fix = await DeviceNearbyLocator(phone).locate();
      expect(fix, isA<NearbyUnavailable>());
    });

    test('the permission cannot be read: unavailable', () async {
      final phone = _FakePhone()..permissionFails = StateError('platform');
      final fix = await DeviceNearbyLocator(phone, precise: true).locate();
      expect(fix, isA<NearbyUnavailable>());
      expect(phone.count('prompt'), 0);
    });

    test('a failed attempt leaves Nearby off and the places visible', () async {
      final phone = _FakePhone()..positionFails = StateError('x');
      final filters = MapFilterController()..setRecords([_place('a')]);
      final fix = await filters.enableNearby(DeviceNearbyLocator(phone));
      expect(fix, isA<NearbyUnavailable>());
      expect(filters.state.nearby, isNull);
      expect(filters.visible, hasLength(1));
    });
  });

  group('what the person is told', () {
    test('each outcome has one short message, a key of the app\'s own', () {
      expect(nearbyFixMessageKey(const NearbyLocated(25.2, 55.27)), isNull);
      expect(
        nearbyFixMessageKey(const NearbyDenied()),
        'locationPermissionDenied',
      );
      expect(
        nearbyFixMessageKey(const NearbyPermanentlyDenied()),
        'mapLocationBlocked',
      );
      expect(
        nearbyFixMessageKey(const NearbyServicesOff()),
        'locationServiceDisabledMessage',
      );
      expect(
        nearbyFixMessageKey(const NearbyUnavailable()),
        'mapNearbyUnavailable',
      );
    });

    test('the four messages are different, so the person can tell why', () {
      final keys = {
        nearbyFixMessageKey(const NearbyDenied()),
        nearbyFixMessageKey(const NearbyPermanentlyDenied()),
        nearbyFixMessageKey(const NearbyServicesOff()),
        nearbyFixMessageKey(const NearbyUnavailable()),
      };
      expect(keys, hasLength(4));
    });

    for (final code in ['en', 'ar']) {
      test('$code: every message exists, is short, and holds no coordinate',
          () {
        final table = _arb(code);
        for (final key in [
          'locationPermissionDenied',
          'mapLocationBlocked',
          'locationServiceDisabledMessage',
          'mapNearbyUnavailable',
        ]) {
          final text = (table[key] as String?)?.trim() ?? '';
          expect(text, isNotEmpty, reason: '$code $key');
          expect(text.length, lessThan(160), reason: '$code $key is concise');
          expect(
            RegExp(r'[0-9٠-٩]').hasMatch(text),
            isFalse,
            reason: '$code $key must hold no number, let alone a coordinate',
          );
          expect(text.contains('{'), isFalse, reason: '$code $key');
        }
      });
    }

    test('the message is chosen by the kind of result alone, never its numbers',
        () {
      // The same message key for any position (there is none), and no fix of
      // any coordinates reaches the words.
      expect(nearbyFixMessageKey(const NearbyLocated(0, 0)), isNull);
      expect(
          nearbyFixMessageKey(const NearbyLocated(25.2048, 55.2708)), isNull);
    });
  });

  group('nothing of the position is kept', () {
    test('the boundary hands the position back and holds no copy', () async {
      final phone = _FakePhone(point: const DevicePoint(24.4539, 54.3773));
      final locator = DeviceNearbyLocator(phone, precise: true);
      final first = await locator.locate() as NearbyLocated;
      phone.point = const DevicePoint(25.0, 55.0);
      final second = await locator.locate() as NearbyLocated;
      expect(first.latitude, 24.4539);
      expect(second.latitude, 25.0, reason: 'each tap asks the device afresh');
    });

    test('turning Nearby off forgets the position', () async {
      final filters = MapFilterController()..setRecords([_place('a')]);
      await filters.enableNearby(DeviceNearbyLocator(_FakePhone()));
      expect(filters.state.nearby, isNotNull);
      filters.disableNearby();
      expect(filters.state.nearby, isNull);
      expect(filters.state, MapFilterState.initial);
    });
  });

  group('Nearby: the first position is quick and deterministic', () {
    final now = DateTime(2026, 10, 10, 12);

    // A position the system took `age` ago, to within `accuracy` metres.
    DevicePoint held({
      Duration age = const Duration(seconds: 20),
      double? accuracy = 80,
      bool timed = true,
      double lat = 25.31,
      double lng = 55.41,
    }) =>
        DevicePoint(
          lat,
          lng,
          takenAt: timed ? now.subtract(age) : null,
          accuracyMeters: accuracy,
        );

    DeviceNearbyLocator rough(_FakePhone phone) =>
        DeviceNearbyLocator(phone, clock: () => now);

    // What a new fix would say (not the held one).
    const fresh = DevicePoint(25.0, 55.0);

    test(
        '15. nothing held: the path is exactly services, permission, the held '
        'position, then a new rough fix', () async {
      final phone = _FakePhone(point: fresh);
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(phone.calls, [
        'services',
        'permission',
        'lastKnown',
        'position:rough',
      ]);
      expect(fix.latitude, 25.0);
    });

    test(
        'a recent, accurate position the system holds is used at once, with '
        'no new fix', () async {
      final phone = _FakePhone(point: fresh)..held = held();
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(phone.calls, ['services', 'permission', 'lastKnown']);
      expect(fix.latitude, 25.31);
      expect(fix.longitude, 55.41);
    });

    test('it is still used at the limits: a minute old, 500 m', () async {
      final phone = _FakePhone(point: fresh)
        ..held = held(age: DeviceNearbyLocator.maxRecentAge, accuracy: 500);
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(fix.latitude, 25.31);
      expect(phone.count('position:rough'), 0);
    });

    test('the limits are a minute and a tenth of the smallest radius', () {
      expect(DeviceNearbyLocator.maxRecentAge, const Duration(minutes: 1));
      expect(DeviceNearbyLocator.maxRecentAccuracyMeters, 500);
      expect(
        DeviceNearbyLocator.maxRecentAccuracyMeters * 10,
        NearbyFilter.radiusOptionsKm.first * 1000.0,
        reason: 'an error of a tenth of 5 km cannot make 5 km unreliable',
      );
    });

    test('older than that: never used, a new fix is waited for', () async {
      final phone = _FakePhone(point: fresh)
        ..held = held(
          age: DeviceNearbyLocator.maxRecentAge + const Duration(seconds: 1),
        );
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(phone.count('position:rough'), 1);
      expect(fix.latitude, 25.0, reason: 'the new fix, not the old position');
    });

    test('less accurate than that: never used', () async {
      final phone = _FakePhone(point: fresh)..held = held(accuracy: 501);
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(phone.count('position:rough'), 1);
      expect(fix.latitude, 25.0);
    });

    test('with no accuracy, a zero or a nonsense one: never used', () async {
      for (final accuracy in [null, 0.0, -1.0, double.nan]) {
        final phone = _FakePhone(point: fresh)..held = held(accuracy: accuracy);
        final fix = await rough(phone).locate() as NearbyLocated;
        expect(fix.latitude, 25.0, reason: 'accuracy $accuracy');
        expect(phone.count('position:rough'), 1, reason: 'accuracy $accuracy');
      }
    });

    test('with no time to judge it by: never used', () async {
      final phone = _FakePhone(point: fresh)..held = held(timed: false);
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(fix.latitude, 25.0);
      expect(phone.count('position:rough'), 1);
    });

    test('taken in the future (a wrong clock): never used', () async {
      final phone = _FakePhone(point: fresh)
        ..held = DevicePoint(
          25.31,
          55.41,
          takenAt: now.add(const Duration(minutes: 5)),
          accuracyMeters: 50,
        );
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(fix.latitude, 25.0);
    });

    test('the held position cannot be read: a new fix is waited for', () async {
      final phone = _FakePhone(point: fresh)
        ..held = held()
        ..heldFails = StateError('platform');
      final fix = await rough(phone).locate() as NearbyLocated;
      expect(fix.latitude, 25.0);
      expect(phone.count('position:rough'), 1);
    });

    test('"my location" is precise: it never takes a position that was held',
        () async {
      final phone = _FakePhone(point: fresh)..held = held();
      final fix = await DeviceNearbyLocator(
        phone,
        precise: true,
        clock: () => now,
      ).locate() as NearbyLocated;
      expect(phone.calls, ['services', 'permission', 'position:fine']);
      expect(fix.latitude, 25.0);
    });

    test('services off, or no permission: the held position is not looked at',
        () async {
      final off = _FakePhone(services: false)..held = held();
      expect(await rough(off).locate(), isA<NearbyServicesOff>());
      expect(off.count('lastKnown'), 0);

      final refused = _FakePhone(
        permissionNow: DevicePermission.denied,
        answerToPrompt: DevicePermission.denied,
      )..held = held();
      expect(await rough(refused).locate(), isA<NearbyDenied>());
      expect(refused.count('lastKnown'), 0);

      final blocked = _FakePhone(
        permissionNow: DevicePermission.permanentlyDenied,
      )..held = held();
      expect(await rough(blocked).locate(), isA<NearbyPermanentlyDenied>());
      expect(blocked.count('lastKnown'), 0);
    });
  });

  group('Nearby: a position once held is reused', () {
    final now = DateTime(2026, 10, 10, 12);
    CachedLocationData placeAt(String id, double lat, double lng) =>
        CachedLocationData(
          id: id,
          title: id,
          address: '',
          latitude: lat,
          longitude: lng,
          type: LocationFilter.offers,
        );

    final places = [
      placeAt('near', 25.32, 55.41),
      placeAt('mid', 25.38, 55.41),
      placeAt('far', 25.5, 55.41),
    ];

    test('16/17. 5, 10 and 25 km never ask the phone anything again', () async {
      final phone = _FakePhone(point: const DevicePoint(25.31, 55.41));
      final filters = MapFilterController()..setRecords(places);
      await filters.enableNearby(
        DeviceNearbyLocator(phone, clock: () => now),
      );
      final afterEnable = List<String>.of(phone.calls);
      expect(phone.count('position:rough'), 1);

      for (final km in [5, 25, 10, 5, 25, 10]) {
        filters.setNearbyRadius(km);
      }
      expect(phone.calls, afterEnable,
          reason: 'not one more question to the phone');
      expect(phone.count('position:rough') + phone.count('position:fine'), 1);
    });

    test('16. turning Nearby on again soon uses the position the system holds',
        () async {
      final phone = _FakePhone(point: const DevicePoint(25.31, 55.41));
      final filters = MapFilterController()..setRecords(places);
      final locator = DeviceNearbyLocator(phone, clock: () => now);
      await filters.enableNearby(locator);
      expect(phone.count('position:rough'), 1);

      filters.disableNearby();
      // The system now holds the position it just took.
      phone.held = DevicePoint(
        25.31,
        55.41,
        takenAt: now.subtract(const Duration(seconds: 5)),
        accuracyMeters: 40,
      );
      await filters.enableNearby(locator);
      expect(phone.count('position:rough'), 1,
          reason: 'no second wait for a new fix');
      expect(filters.state.nearby!.latitude, 25.31);
    });
  });

  group('Nearby: while the first position is awaited', () {
    final now = DateTime(2026, 10, 10, 12);
    CachedLocationData placeAt(String id, double lat, double lng) =>
        CachedLocationData(
          id: id,
          title: id,
          address: '',
          latitude: lat,
          longitude: lng,
          type: LocationFilter.offers,
        );

    final places = [
      placeAt('near', 25.32, 55.41),
      placeAt('far', 25.5, 55.41),
    ];

    MapFilterController loaded() => MapFilterController()..setRecords(places);

    test('18. every place stays visible, and nothing changes, until it comes',
        () async {
      final phone = _FakePhone()..positionGate = Completer<DevicePoint>();
      final filters = loaded();
      final before = filters.snapshot;

      final pending = filters.enableNearby(
        DeviceNearbyLocator(phone, clock: () => now),
      );
      await pumpEventQueue();

      expect(filters.isLocatingNearby, isTrue);
      expect(filters.visible.map((p) => p.id), ['near', 'far']);
      expect(filters.state, MapFilterState.initial);
      expect(filters.snapshot.stateVersion, before.stateVersion);

      phone.positionGate!.complete(const DevicePoint(25.31, 55.41));
      await pending;

      // Applied once: one choice, one new snapshot.
      expect(filters.visible.map((p) => p.id), ['near']);
      expect(filters.snapshot.stateVersion, before.stateVersion + 1);
    });

    test('19. the wait ends when the position arrives', () async {
      final phone = _FakePhone(point: const DevicePoint(25.31, 55.41));
      final filters = loaded();
      final pending = filters.enableNearby(
        DeviceNearbyLocator(phone, clock: () => now),
      );
      expect(filters.isLocatingNearby, isTrue,
          reason: 'the chip shows it from the tap');
      await pending;
      expect(filters.isLocatingNearby, isFalse);
      expect(filters.state.nearbyEnabled, isTrue);
    });

    test('20. the wait ends when it is refused, blocked, off or fails',
        () async {
      final cases = <String, _FakePhone>{
        'denied': _FakePhone(
          permissionNow: DevicePermission.denied,
          answerToPrompt: DevicePermission.denied,
        ),
        'blocked for good': _FakePhone(
          permissionNow: DevicePermission.permanentlyDenied,
        ),
        'services off': _FakePhone(services: false),
        'no position': _FakePhone()..positionFails = StateError('timeout'),
        'permission unreadable': _FakePhone()
          ..permissionFails = StateError('platform'),
      };
      for (final entry in cases.entries) {
        final filters = loaded();
        final pending = filters.enableNearby(
          DeviceNearbyLocator(entry.value, clock: () => now),
        );
        expect(filters.isLocatingNearby, isTrue, reason: entry.key);
        final fix = await pending;
        expect(fix, isNot(isA<NearbyLocated>()), reason: entry.key);
        expect(filters.isLocatingNearby, isFalse, reason: entry.key);
        expect(filters.state.nearbyEnabled, isFalse, reason: entry.key);
        expect(filters.visible, hasLength(2), reason: '${entry.key}: all stay');
      }
    });

    test('20. the wait ends at once when the filter is cleared meanwhile',
        () async {
      final phone = _FakePhone()..positionGate = Completer<DevicePoint>();
      final filters = loaded();
      final pending = filters.enableNearby(
        DeviceNearbyLocator(phone, clock: () => now),
      );
      await pumpEventQueue();
      expect(filters.isLocatingNearby, isTrue);

      filters.clear();
      expect(filters.isLocatingNearby, isFalse);

      phone.positionGate!.complete(const DevicePoint(25.31, 55.41));
      await pending;
      expect(filters.isLocatingNearby, isFalse);
      expect(filters.state.nearbyEnabled, isFalse,
          reason: 'a position nobody wants any more is not applied');
    });

    test('20. the wait ends when Nearby is turned off meanwhile', () async {
      final phone = _FakePhone()..positionGate = Completer<DevicePoint>();
      final filters = loaded();
      final pending = filters.enableNearby(
        DeviceNearbyLocator(phone, clock: () => now),
      );
      await pumpEventQueue();
      filters.disableNearby();
      expect(filters.isLocatingNearby, isFalse);
      phone.positionGate!.complete(const DevicePoint(25.31, 55.41));
      await pending;
      expect(filters.state.nearbyEnabled, isFalse);
    });
  });

  group('Nearby: repeated taps are one request', () {
    final now = DateTime(2026, 10, 10, 12);

    test('21. taps while the system\'s prompt is open show it once', () async {
      final phone = _FakePhone(permissionNow: DevicePermission.denied)
        ..promptGate = Completer<DevicePermission>();
      final locator = DeviceNearbyLocator(phone, clock: () => now);

      final taps = [for (var i = 0; i < 4; i++) locator.locate()];
      await pumpEventQueue();
      expect(phone.count('prompt'), 1, reason: 'one prompt for four taps');

      phone.promptGate!.complete(DevicePermission.granted);
      final fixes = await Future.wait(taps);
      expect(phone.count('prompt'), 1);
      expect(phone.count('position:rough'), 1);
      expect(fixes.every((fix) => fix is NearbyLocated), isTrue);
    });

    test('21. taps while the new fix is awaited ask for one fix', () async {
      final phone = _FakePhone()..positionGate = Completer<DevicePoint>();
      final locator = DeviceNearbyLocator(phone, clock: () => now);

      final taps = [for (var i = 0; i < 5; i++) locator.locate()];
      await pumpEventQueue();
      phone.positionGate!.complete(const DevicePoint(25.31, 55.41));
      final fixes = await Future.wait(taps);

      expect(phone.count('position:rough'), 1, reason: 'one fix for five taps');
      expect(phone.count('services'), 1);
      expect(phone.count('permission'), 1);
      for (final fix in fixes) {
        expect((fix as NearbyLocated).latitude, 25.31);
      }
    });

    test('21. the filter asked three times at once still asks the phone once',
        () async {
      final phone = _FakePhone()..positionGate = Completer<DevicePoint>();
      final locator = DeviceNearbyLocator(phone, clock: () => now);
      final filters = MapFilterController()..setRecords([_place('a')]);

      final asked = [
        for (var i = 0; i < 3; i++) filters.enableNearby(locator),
      ];
      await pumpEventQueue();
      phone.positionGate!.complete(const DevicePoint(25.2048, 55.2708));
      await Future.wait(asked);

      expect(phone.count('position:rough'), 1);
      expect(filters.state.nearbyEnabled, isTrue);
      expect(filters.isLocatingNearby, isFalse);
    });

    test('a request that has finished does not block the next one', () async {
      final phone = _FakePhone();
      final locator = DeviceNearbyLocator(phone, clock: () => now);
      await locator.locate();
      await locator.locate();
      expect(phone.count('position:rough'), 2,
          reason: 'each separate tap is its own request');
    });

    test('a failure does not leave the locator stuck', () async {
      final phone = _FakePhone()..positionFails = StateError('timeout');
      final locator = DeviceNearbyLocator(phone, clock: () => now);
      expect(await locator.locate(), isA<NearbyUnavailable>());
      phone.positionFails = null;
      expect(await locator.locate(), isA<NearbyLocated>());
    });
  });
}
