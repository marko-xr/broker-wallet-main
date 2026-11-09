// P4.7b: a server list identical to the saved one is not written again; only
// its authenticated freshness record is. And the saved list is shown before
// its fingerprint is worked out.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// encrypted list caches, the secure-storage test store.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_fixtures.dart';

const _alice = 'u1';
const _bob = 'u2';

List<OwnerModel> _owners(int n,
        {String prefix = 'o', String account = _alice}) =>
    [
      for (var i = 0; i < n; i++)
        owner(
          id: '$prefix$i',
          name: 'Owner $i',
          phone: '50${i.toString().padLeft(7, '0')}',
          typeOfProperties: 'Villa, Apartment',
          propertyLocation: 'Palm Jumeirah Frond $i',
          notes: 'Prefers calls after 6pm; keys with watchman $i',
        ).copyWith(userId: account),
    ];

class _CountingOwners extends OwnersLocalCache {
  int fingerprints = 0;

  @override
  String fingerprintOf(List<OwnerModel> items) {
    fingerprints++;
    return super.fingerprintOf(items);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  File boxFile(String name) =>
      File('${listsDir()}${Platform.pathSeparator}${name.toLowerCase()}.hive');
  const owners = OwnersLocalCache();
  final ownersBox = OwnersLocalCache.boxNameForUid(_alice);
  Box<String> box(String name) => Hive.box<String>(name);
  final t1 = DateTime.utc(2026, 11, 6, 9);
  final t2 = DateTime.utc(2026, 11, 6, 9, 5);

  Future<void> closeAll() async {
    for (final uid in [_alice, _bob]) {
      for (final name in [
        RequestsLocalCache.boxNameForUid(uid),
        OffersLocalCache.boxNameForUid(uid),
        OwnersLocalCache.boxNameForUid(uid),
        OfficesLocalCache.boxNameForUid(uid),
        BrokersLocalCache.boxNameForUid(uid),
        WatchmenLocalCache.boxNameForUid(uid),
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
      }
    }
    EncryptedAccountListCache.debugForgetProcessState();
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('unchanged_save_test');
    Hive.init(tempDir.path);
    EncryptedAccountListCache.debugStorageRoot = tempDir.path;
  });

  tearDownAll(() async {
    await Hive.close();
    EncryptedAccountListCache.debugStorageRoot = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    EncryptedAccountListCache.debugForgetProcessState();
  });

  tearDown(() async {
    await closeAll();
    for (final uid in [_alice, _bob]) {
      for (final name in [
        RequestsLocalCache.boxNameForUid(uid),
        OffersLocalCache.boxNameForUid(uid),
        OwnersLocalCache.boxNameForUid(uid),
        OfficesLocalCache.boxNameForUid(uid),
        BrokersLocalCache.boxNameForUid(uid),
        WatchmenLocalCache.boxNameForUid(uid),
      ]) {
        for (var attempt = 0;; attempt++) {
          try {
            await Hive.deleteBoxFromDisk(name, path: listsDir());
            break;
          } on FileSystemException {
            if (attempt == 20) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
      }
    }
  });

  /// Bytes the box file grew by while [action] ran.
  Future<int> growthOf(String name, Future<void> Function() action) async {
    final before = boxFile(name).lengthSync();
    await action();
    return boxFile(name).lengthSync() - before;
  }

  String sealedPayload(String name, String key) =>
      (json.decode(box(name).get(key)!) as Map)['p'] as String;

  group('an unchanged server list', () {
    test('is not written again; only its freshness record is', () async {
      final list = _owners(200);
      await owners.write(_alice, list, serverReadAt: t1);
      final payloadBytes = sealedPayload(ownersBox, 'owners_v2').length;
      final sealedBefore = box(ownersBox).get('owners_v2');

      final growth = await growthOf(
          ownersBox, () => owners.write(_alice, list, serverReadAt: t2));

      expect(growth, lessThan(2048),
          reason: 'a ${payloadBytes}B list was not appended again');
      expect(box(ownersBox).get('owners_v2'), sealedBefore);
      final saved = await owners.readSaved(_alice);
      expect(saved!.info.serverReadAt, t2,
          reason: 'the server read is recorded even though nothing changed');
      expect(saved.info.authenticated, isTrue);
      expect([for (final o in saved.items) o.id], [for (final o in list) o.id]);
    });

    test('with no read time keeps the earlier one', () async {
      final list = _owners(5);
      await owners.write(_alice, list, serverReadAt: t1);
      await owners.write(_alice, list);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t1);
    });

    test('an authoritative empty list, saved again, stays a valid empty list',
        () async {
      await owners.write(_alice, _owners(3), serverReadAt: t1);
      await owners.write(_alice, const [], serverReadAt: t1);
      final growth = await growthOf(
          ownersBox, () => owners.write(_alice, const [], serverReadAt: t2));
      expect(growth, lessThan(2048));
      final saved = await owners.readSaved(_alice);
      expect(saved!.items, isEmpty);
      expect(saved.info.serverReadAt, t2);
    });

    test('after a restart, still recognised as unchanged', () async {
      final list = _owners(50);
      await owners.write(_alice, list, serverReadAt: t1);
      await closeAll();
      await owners.readSaved(_alice); // reopens the box
      final growth = await growthOf(
          ownersBox, () => owners.write(_alice, list, serverReadAt: t2));
      expect(growth, lessThan(2048));
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t2);
    });
  });

  group('a changed server list is written in full', () {
    Future<void> expectRewritten(
        List<OwnerModel> before, List<OwnerModel> after) async {
      await owners.write(_alice, before, serverReadAt: t1);
      final growth = await growthOf(
          ownersBox, () => owners.write(_alice, after, serverReadAt: t2));
      expect(growth, greaterThan(2048), reason: 'the new list was stored');
      final saved = await owners.readSaved(_alice);
      expect(
          [for (final o in saved!.items) o.id], [for (final o in after) o.id]);
      expect([for (final o in saved.items) o.name],
          [for (final o in after) o.name]);
      expect(saved.info.serverReadAt, t2);
    }

    test('one field of one record changed', () async {
      final list = _owners(100);
      final changed = [...list];
      changed[42] = changed[42].copyWith(notes: 'Now prefers WhatsApp');
      await expectRewritten(list, changed);
      final saved = await owners.readSaved(_alice);
      expect(saved!.items[42].notes, 'Now prefers WhatsApp');
    });

    test('the same records in another order', () async {
      final list = _owners(100);
      await expectRewritten(list, list.reversed.toList());
    });

    test('a record added, and a record removed', () async {
      final list = _owners(100);
      await expectRewritten(list, [...list, ..._owners(1, prefix: 'new')]);
      await expectRewritten(list, list.sublist(1));
    });

    test('a non-empty list replacing a saved empty one', () async {
      await expectRewritten(const [], _owners(80));
    });
  });

  group('integrity, recovery and migration are untouched', () {
    test('a saved list that fails its check is never "unchanged"', () async {
      final list = _owners(30);
      await owners.write(_alice, list, serverReadAt: t1);
      final sealed = Map<String, Object?>.from(
          json.decode(box(ownersBox).get('owners_v2')!) as Map);
      // Same payload, broken tag: equal content, not authentic.
      await box(ownersBox).put('owners_v2',
          json.encode({...sealed, 't': base64Url.encode(List.filled(32, 0))}));

      await owners.write(_alice, list, serverReadAt: t2);
      expect(await owners.readSaved(_alice), isNull,
          reason: 'without a verified server list nothing is written over it');

      await owners.write(_alice, list,
          serverReadAt: t2, mayRecover: () => true);
      final saved = await owners.readSaved(_alice);
      expect(saved!.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, t2);
    });

    test('a damaged freshness record is replaced by the next read', () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await box(ownersBox).put('owners_sync_v1', '{"v":1,"p":"{}","t":"AAAA"}');
      expect((await owners.readSaved(_alice))!.info.serverReadAt, isNull);

      await owners.write(_alice, list, serverReadAt: t2);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t2);
    });

    test('S2: an earlier v1 list is still moved to v2 and removed', () async {
      final list = _owners(20);
      await owners.write(_alice, list);
      final payload = sealedPayload(ownersBox, 'owners_v2');
      await box(ownersBox).delete('owners_v2');
      await box(ownersBox).put('owners_v1', payload);

      await owners.write(_alice, list, serverReadAt: t1);

      expect(box(ownersBox).containsKey('owners_v1'), isFalse);
      final saved = await owners.readSaved(_alice);
      expect(saved!.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, t1);
    });

    test('a v1 list left beside an unchanged v2 list is still removed',
        () async {
      final list = _owners(20);
      await owners.write(_alice, list, serverReadAt: t1);
      await box(ownersBox)
          .put('owners_v1', sealedPayload(ownersBox, 'owners_v2'));

      await owners.write(_alice, list, serverReadAt: t2);

      expect(box(ownersBox).containsKey('owners_v1'), isFalse);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t2);
    });

    test('D-2: a lost key is recovered only from a verified server list',
        () async {
      final list = _owners(15);
      await owners.write(_alice, list, serverReadAt: t1);
      await closeAll();
      FlutterSecureStorage.setMockInitialValues({});

      await owners.write(_alice, list, serverReadAt: t2);
      expect(await owners.readSaved(_alice), isNull);

      await owners.write(_alice, list,
          serverReadAt: t2, mayRecover: () => true);
      final saved = await owners.readSaved(_alice);
      expect(saved!.items, hasLength(15));
      expect(saved.info.serverReadAt, t2);
    });

    test('unreadable deletion markers block the list; nothing is saved',
        () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await box(ownersBox).put('owners_deleted_v1', '{"v":1,"p":"x","t":"y"}');
      final before = box(ownersBox).get('owners_sync_v1');

      await owners.write(_alice, list, serverReadAt: t2);

      expect(owners.isIntegrityBlocked(_alice), isTrue);
      expect(box(ownersBox).get('owners_sync_v1'), before);
    });

    test('a list holding a record confirmed deleted this run is not saved',
        () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await owners.rememberConfirmedDeletion(_alice, 'o3');

      await owners.write(_alice, list, serverReadAt: t2);

      final saved = await owners.readSaved(_alice);
      expect([for (final o in saved!.items) o.id], isNot(contains('o3')));
      expect(saved.info.serverReadAt, t1, reason: 'the stale list was refused');
    });
  });

  group('accounts, deletion and concurrency', () {
    test('another account\'s identical-looking list is its own', () async {
      await owners.write(_alice, _owners(5), serverReadAt: t1);
      await owners.write(_bob, _owners(5, account: _bob), serverReadAt: t2);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t1);
      expect((await owners.readSaved(_bob))!.info.serverReadAt, t2);
      expect(
          (await owners.readSaved(_bob))!.items.every((o) => o.userId == _bob),
          isTrue);
    });

    test('Delete Account still removes the box and its key', () async {
      final list = _owners(5);
      await owners.write(_alice, list, serverReadAt: t1);
      await owners.write(_alice, list, serverReadAt: t2);
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);
      expect(await Hive.boxExists(ownersBox, path: listsDir()), isFalse);
      expect(
          await const FlutterSecureStorage()
              .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice)),
          isNull);
    });

    test('concurrent saves keep their order: the last one wins', () async {
      final a = _owners(30);
      final b = [...a.reversed];
      await owners.write(_alice, a, serverReadAt: t1);
      await Future.wait([
        owners.write(_alice, a, serverReadAt: t1), // unchanged
        owners.write(_alice, b, serverReadAt: t2), // changed
        owners.write(_alice, b,
            serverReadAt: t2.add(const Duration(minutes: 1))),
      ]);
      final saved = await owners.readSaved(_alice);
      expect([for (final o in saved!.items) o.id], [for (final o in b) o.id]);
      expect(saved.info.serverReadAt, t2.add(const Duration(minutes: 1)));
    });
  });

  group('the screen stream', () {
    test(
        'the saved list is shown before its fingerprint is worked out; an '
        'identical server list is still not shown twice', () async {
      final cache = _CountingOwners();
      final list = _owners(40);
      await cache.write(_alice, list, serverReadAt: t1);
      final server = StreamController<List<OwnerModel>>();
      final shown = <List<OwnerModel>>[];
      var fingerprintsAtFirstList = -1;
      final sub = localFirstList<OwnerModel>(
        server: () => server.stream,
        cache: cache,
        currentUserId: () => _alice,
        refreshSignals: const Stream<void>.empty(),
        isAppActive: () => true,
        confirmEmptyList: (_) => null,
        sessionOf: () => null,
      ).listen((items) {
        if (shown.isEmpty) fingerprintsAtFirstList = cache.fingerprints;
        shown.add(items);
      });
      await pumpEventQueue();
      expect(shown, hasLength(1));
      expect(fingerprintsAtFirstList, 0,
          reason: 'no re-encoding before the first list is on screen');

      server.add([...list]); // identical
      await pumpEventQueue();
      expect(shown, hasLength(1), reason: 'not shown again');

      final changed = [...list]..[0] = list[0].copyWith(name: 'Renamed');
      server.add(changed);
      await pumpEventQueue();
      expect(shown, hasLength(2));
      expect(shown.last.first.name, 'Renamed');
      await sub.cancel();
      await server.close();
    });
  });

  test('all six lists: unchanged saves write only freshness', () async {
    Future<void> check<T>(EncryptedAccountListCache<T> cache, String name,
        String base, List<T> items) async {
      await cache.write(_alice, items, serverReadAt: t1);
      final growth = await growthOf(
          name, () => cache.write(_alice, items, serverReadAt: t2));
      expect(growth, lessThan(2048), reason: base);
      expect((await cache.readSaved(_alice))!.info.serverReadAt, t2,
          reason: base);
    }

    await check<RequestModel>(
        const RequestsLocalCache(),
        RequestsLocalCache.boxNameForUid(_alice),
        'requests',
        [for (var i = 0; i < 50; i++) request(id: 'r$i', notes: 'n$i')]);
    await check<OfferModel>(
        const OffersLocalCache(),
        OffersLocalCache.boxNameForUid(_alice),
        'offers',
        [for (var i = 0; i < 50; i++) offer(id: 'f$i', notes: 'n$i')]);
    await check<OwnerModel>(owners, ownersBox, 'owners', _owners(50));
    await check<OfficeModel>(const OfficesLocalCache(),
        OfficesLocalCache.boxNameForUid(_alice), 'offices', [
      for (var i = 0; i < 50; i++)
        office(id: 'c$i', name: 'Office $i').copyWith(userId: _alice)
    ]);
    await check<BrokerModel>(const BrokersLocalCache(),
        BrokersLocalCache.boxNameForUid(_alice), 'brokers', [
      for (var i = 0; i < 50; i++)
        broker(id: 'b$i', name: 'Broker $i').copyWith(userId: _alice)
    ]);
    await check<WatchmenModel>(const WatchmenLocalCache(),
        WatchmenLocalCache.boxNameForUid(_alice), 'watchmen', [
      for (var i = 0; i < 50; i++)
        watchman(id: 'w$i', name: 'Watchman $i').copyWith(userId: _alice)
    ]);
  });

  group('cost (MEASURED on the test VM, not a phone)', () {
    for (final n in [0, 100, 1000, 5000, 20000]) {
      test('Owners n=$n', () async {
        final list = _owners(n);
        final changedSave = Stopwatch()..start();
        await owners.write(_alice, list, serverReadAt: t1);
        changedSave.stop();
        final unchangedGrowth = await growthOf(ownersBox, () async {});
        final unchangedSave = Stopwatch()..start();
        final grew = await growthOf(
            ownersBox, () => owners.write(_alice, list, serverReadAt: t2));
        unchangedSave.stop();

        await closeAll();
        final cache = _CountingOwners();
        final server = StreamController<List<OwnerModel>>();
        final open = Stopwatch()..start();
        int? firstList;
        final sub = localFirstList<OwnerModel>(
          server: () => server.stream,
          cache: cache,
          currentUserId: () => _alice,
          refreshSignals: const Stream<void>.empty(),
          isAppActive: () => true,
          confirmEmptyList: (_) => null,
          sessionOf: () => null,
        ).listen((_) => firstList ??= open.elapsedMilliseconds);
        for (var i = 0; i < 1000 && firstList == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final fingerprintsBeforeServer = cache.fingerprints;
        final fp = Stopwatch()..start();
        cache.fingerprintOf(list);
        fp.stop();
        await sub.cancel();
        await server.close();

        expect(unchangedGrowth, 0);
        debugPrint('[UnchangedSave] owners n=$n changedSave='
            '${changedSave.elapsedMilliseconds}ms unchangedSave='
            '${unchangedSave.elapsedMilliseconds}ms unchangedFileGrowth=${grew}B '
            'firstList=${firstList}ms fingerprintsBeforeServer='
            '$fingerprintsBeforeServer fingerprint=${fp.elapsedMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}
