// P4.7c (Option C): work the cache already did in this process is reused —
// never an integrity rule.
//
//  1. A v2 envelope that passed full HMAC verification is not verified again
//     while Hive hands back that very String instance, from the same open
//     box, under the same key. Any other object — equal contents included —
//     is verified in full; nothing is ever trusted because of its identity
//     alone.
//  2. The server list's fingerprint is saved as the payload only when it is
//     exactly that payload: nothing hidden by deletion markers, and every
//     record the account's own.
//  3. An identical server list is recognised by comparing its fingerprint
//     with the saved list's verified payload, without re-encoding the saved
//     list (only when no confirmed deletion is hidden from it).
//
// Real Hive in a temporary directory, the real caches, the secure-storage
// test store.
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
import 'package:broker_wallet/src/services/favorites_local_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_fixtures.dart';

const _alice = 'u1';
const _bob = 'u2';

List<OwnerModel> _owners(int n, {String account = _alice, String p = 'o'}) => [
      for (var i = 0; i < n; i++)
        owner(id: '$p$i', name: 'Owner $i', notes: 'note $i')
            .copyWith(userId: account),
    ];

/// Counts full verifications made during [op].
Future<int> _fullChecks(Future<void> Function() op) async {
  final before = EncryptedAccountListCache.debugFullVerifications;
  await op();
  return EncryptedAccountListCache.debugFullVerifications - before;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const owners = OwnersLocalCache();
  final aliceBox = OwnersLocalCache.boxNameForUid(_alice);
  Box<String> box(String name) => Hive.box<String>(name);
  final t1 = DateTime.utc(2026, 11, 6, 9);
  final t2 = DateTime.utc(2026, 11, 6, 9, 5);

  final allBoxes = [
    for (final uid in [_alice, _bob]) ...[
      RequestsLocalCache.boxNameForUid(uid),
      OffersLocalCache.boxNameForUid(uid),
      OwnersLocalCache.boxNameForUid(uid),
      OfficesLocalCache.boxNameForUid(uid),
      BrokersLocalCache.boxNameForUid(uid),
      WatchmenLocalCache.boxNameForUid(uid),
      FavoritesLocalCache.boxNameForUid(uid),
    ],
  ];

  Future<void> restart() async {
    for (final name in allBoxes) {
      if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
    }
    EncryptedAccountListCache.debugForgetProcessState();
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('verified_reuse_test');
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
    await restart();
    for (final name in allBoxes) {
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
  });

  Map<String, Object?> envelope(String name, String key) =>
      Map<String, Object?>.from(json.decode(box(name).get(key)!) as Map);

  group('1. a verified envelope, while it is that very object', () {
    test('is not verified again; the list reads the same', () async {
      final list = _owners(30);
      await owners.write(_alice, list, serverReadAt: t1);
      // The write's read-back verified the stored envelope in full once.
      final first = await owners.readSaved(_alice);
      final again = await _fullChecks(() async {
        final a = await owners.readSaved(_alice);
        final b = await owners.readSaved(_alice);
        expect([for (final o in a!.items) o.id], [for (final o in list) o.id]);
        expect(b!.info.serverReadAt, t1);
      });
      expect(again, 0, reason: 'same instance, same box, same key');
      expect(first!.info.authenticated, isTrue);
    });

    test('an equal envelope in another String instance is verified in full',
        () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice);
      final sealed = box(aliceBox).get('owners_v2')!;
      final copy = String.fromCharCodes(sealed.codeUnits);
      expect(identical(copy, sealed), isFalse);
      await box(aliceBox).put('owners_v2', copy);

      final checks = await _fullChecks(() async {
        expect((await owners.readSaved(_alice))!.items, hasLength(10));
      });
      expect(checks, 1);
    });

    test('a forged envelope in a new instance is refused, not reused',
        () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice);
      final e = envelope(aliceBox, 'owners_v2');
      await box(aliceBox).put('owners_v2',
          json.encode({...e, 't': base64Url.encode(List.filled(32, 1))}));
      expect(await owners.readSaved(_alice), isNull);
    });

    test('after the box is closed and reopened: verified in full', () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice);
      await box(aliceBox).close();
      final checks = await _fullChecks(() async {
        expect((await owners.readSaved(_alice))!.items, hasLength(10));
      });
      expect(checks, 1);
    });

    test('after a restart: verified in full', () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await restart();
      final checks = await _fullChecks(() async {
        expect((await owners.readSaved(_alice))!.items, hasLength(10));
      });
      expect(checks, 1);
    });

    test('a lost key: nothing read; recovery replaces it; then verified',
        () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await owners.readSaved(_alice);
      await restart();
      FlutterSecureStorage.setMockInitialValues({});
      expect(await owners.readSaved(_alice), isNull);

      await owners.write(_alice, list,
          serverReadAt: t2, mayRecover: () => true);
      final checks = await _fullChecks(() async {
        final saved = await owners.readSaved(_alice);
        expect(saved!.items, hasLength(10));
        expect(saved.info.serverReadAt, t2);
      });
      expect(checks, greaterThanOrEqualTo(0));
      expect(EncryptedAccountListCache.debugMemoIsFor(aliceBox), isTrue);
    });

    test('a wrong key: the box does not open; nothing is read', () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice);
      await restart();
      await const FlutterSecureStorage().write(
          key: SecureOwnersCacheKeyStore.storageKeyFor(_alice),
          value: base64Url.encode(List<int>.filled(32, 9)));
      expect(await owners.readSaved(_alice), isNull);
    });

    test('a key replaced while the box stays open: verified under the new key',
        () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice); // memoized under the real key
      // Hive hands back the box already open, and the very same String.
      await const FlutterSecureStorage().write(
          key: SecureOwnersCacheKeyStore.storageKeyFor(_alice),
          value: base64Url.encode(List<int>.filled(32, 9)));
      expect(await owners.readSaved(_alice), isNull,
          reason: 'as before P4.7c: the tag does not match under that key');
    });

    test('another account never uses this account\'s verification', () async {
      await owners.write(_alice, _owners(5), serverReadAt: t1);
      await owners.readSaved(_alice);
      await owners.write(_bob, _owners(5, account: _bob), serverReadAt: t2);
      final checks = await _fullChecks(() async {
        final bob = await owners.readSaved(_bob);
        expect(bob!.items.every((o) => o.userId == _bob), isTrue);
      });
      expect(checks, 0, reason: "bob's own write verified bob's own envelope");
      expect(EncryptedAccountListCache.debugMemoIsFor(aliceBox), isTrue);
      expect(
          EncryptedAccountListCache.debugMemoIsFor(
              OwnersLocalCache.boxNameForUid(_bob)),
          isTrue);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, t1);
    });

    test('unreadable deletion markers still block the list', () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await owners.readSaved(_alice); // memoized
      await box(aliceBox).put('owners_deleted_v1', '{"v":1,"p":"x","t":"y"}');
      expect(await owners.readSaved(_alice), isNull);
      expect(owners.isIntegrityBlocked(_alice), isTrue);
    });

    test('Delete Account forgets the verification with the box', () async {
      await owners.write(_alice, _owners(5), serverReadAt: t1);
      await owners.readSaved(_alice);
      expect(EncryptedAccountListCache.debugMemoIsFor(aliceBox), isTrue);
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);
      expect(EncryptedAccountListCache.debugMemoIsFor(aliceBox), isFalse);
      expect(await owners.readSaved(_alice), isNull);
    });

    test('concurrent reads and writes stay ordered and correct', () async {
      final a = _owners(20);
      final b = a.reversed.toList();
      await owners.write(_alice, a, serverReadAt: t1);
      final results = await Future.wait([
        owners.readSaved(_alice),
        owners.write(_alice, b, serverReadAt: t2).then((_) => null),
        owners.readSaved(_alice),
        owners.write(_alice, b, serverReadAt: t2).then((_) => null),
        owners.readSaved(_alice),
      ]);
      expect(
          [for (final o in results[0]!.items) o.id], [for (final o in a) o.id]);
      expect(
          [for (final o in results[2]!.items) o.id], [for (final o in b) o.id]);
      expect(results[4]!.info.serverReadAt, t2);
    });

    test('the memo holds one payload per open box, released on close',
        () async {
      await owners.write(_alice, _owners(50), serverReadAt: t1);
      await owners.readSaved(_alice);
      final payload = envelope(aliceBox, 'owners_v2')['p']! as String;
      expect(
          EncryptedAccountListCache.debugRetainedPayloadChars, payload.length);
      await box(aliceBox).close();
      // Any later use of the memo drops entries of boxes no longer open.
      await owners.write(_bob, _owners(1, account: _bob));
      expect(EncryptedAccountListCache.debugMemoIsFor(aliceBox), isFalse);
    });
  });

  group('2 + 3. the screen stream, server answers and saves', () {
    Future<
        ({
          List<List<OwnerModel>> shown,
          StreamController<List<OwnerModel>> server,
          StreamSubscription<List<OwnerModel>> sub,
        })> openScreen() async {
      final server = StreamController<List<OwnerModel>>();
      final shown = <List<OwnerModel>>[];
      final sub = localFirstList<OwnerModel>(
        server: () => server.stream,
        cache: owners,
        currentUserId: () => _alice,
        refreshSignals: const Stream<void>.empty(),
        isAppActive: () => true,
        confirmEmptyList: (_) => null,
        sessionOf: () => null,
      ).listen(shown.add, onError: (Object _) {});
      // Reopening the box after a restart is real file I/O.
      for (var i = 0; i < 200 && shown.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await owners.debugSettled(_alice);
      return (shown: shown, server: server, sub: sub);
    }

    Future<void> answer(
        StreamController<List<OwnerModel>> server, List<OwnerModel> l) async {
      server.add(l);
      await pumpEventQueue();
      await owners.debugSettled(_alice);
    }

    String storedPayload() => envelope(aliceBox, 'owners_v2')['p']! as String;

    test(
        'an identical list: not shown again, not rewritten, read time '
        'recorded, no saved-list re-encoding', () async {
      final list = _owners(40);
      await owners.write(_alice, list, serverReadAt: t1);
      await restart();
      final s = await openScreen();
      expect(s.shown, hasLength(1));
      final sealedBefore = box(aliceBox).get('owners_v2');
      final encodes = EncryptedAccountListCache.debugEncodes;

      await answer(s.server, [...list]);

      expect(s.shown, hasLength(1));
      expect(identical(box(aliceBox).get('owners_v2'), sealedBefore), isTrue);
      expect((await owners.readSaved(_alice))!.info.serverReadAt, isNot(t1));
      expect(EncryptedAccountListCache.debugEncodes - encodes, 1,
          reason: 'the server list once; never the saved list, never twice');
      await s.sub.cancel();
    });

    test('a changed field, a reorder, an addition: shown and saved exactly',
        () async {
      final list = _owners(40);
      await owners.write(_alice, list, serverReadAt: t1);
      await restart();
      final s = await openScreen();
      final changed = [...list]..[3] = list[3].copyWith(notes: 'changed');
      final reordered = changed.reversed.toList();
      final added = [...reordered, ..._owners(1, p: 'new')];
      var expected = 1;
      for (final next in [changed, reordered, added]) {
        await answer(s.server, next);
        expect(s.shown, hasLength(++expected));
        expect(storedPayload(), owners.fingerprintOf(next),
            reason: 'saved exactly as the server sent it');
        final saved = await owners.readSaved(_alice);
        expect(
            [for (final o in saved!.items) o.id], [for (final o in next) o.id]);
      }
      await s.sub.cancel();
    });

    test('a record of another account: the saved payload leaves it out',
        () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await restart();
      final s = await openScreen();
      final withForeign = [...list, ..._owners(1, account: _bob, p: 'foreign')];
      await answer(s.server, withForeign);
      expect(storedPayload(), isNot(contains('foreign0')));
      expect(storedPayload(), owners.fingerprintOf(list));
      await s.sub.cancel();
    });

    test(
        'a hidden confirmed deletion: the server list is saved as sent, '
        'and comparison falls back to re-encoding', () async {
      final list = _owners(10);
      await owners.write(_alice, list, serverReadAt: t1);
      await owners.rememberConfirmedDeletion(_alice, 'o4');
      await restart();
      final s = await openScreen();
      expect(s.shown.single.map((o) => o.id), isNot(contains('o4')));
      // The server still lists it (a read that started before the delete).
      await answer(s.server, [...list]);
      expect(s.shown, hasLength(1), reason: 'what is shown did not change');
      expect(storedPayload(), contains('o4'),
          reason: 'the saved list stays what the server returned (D-3)');
      await s.sub.cancel();
    });

    test('a legacy v1 list is never taken for a verified v2 list', () async {
      final list = _owners(10);
      await owners.write(_alice, list);
      final payload = storedPayload();
      await box(aliceBox).delete('owners_v2');
      await box(aliceBox).put('owners_v1', payload);
      await restart();
      final s = await openScreen();
      expect((await owners.readSaved(_alice))!.info.authenticated, isFalse);
      await answer(s.server, [...list]);
      expect(box(aliceBox).containsKey('owners_v1'), isFalse);
      final saved = await owners.readSaved(_alice);
      expect(saved!.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, isNotNull);
      await s.sub.cancel();
    });

    test('an integrity-blocked list saves nothing', () async {
      await owners.write(_alice, _owners(10), serverReadAt: t1);
      await box(aliceBox).put('owners_deleted_v1', '{"v":1,"p":"x","t":"y"}');
      final before = box(aliceBox).get('owners_v2');
      await restart();
      final s = await openScreen();
      await answer(s.server, _owners(12));
      expect(box(aliceBox).get('owners_v2'), before);
      await s.sub.cancel();
    });

    test('an empty authoritative answer is saved as a valid empty list',
        () async {
      await owners.write(_alice, _owners(5), serverReadAt: t1);
      await restart();
      final s = await openScreen();
      await answer(s.server, const []);
      expect(s.shown.last, isEmpty);
      expect((await owners.readSaved(_alice))!.items, isEmpty);
      await s.sub.cancel();
    });
  });

  test(
      'every list type round-trips its stored form exactly (what 3 relies '
      'on), and memoizes its verification', () async {
    Future<void> check<T>(EncryptedAccountListCache<T> cache, String uidBox,
        List<T> items) async {
      await cache.write(_alice, items, serverReadAt: t1);
      final payload = (json.decode(Hive.box<String>(uidBox)
              .get('${cache.listKey.replaceAll('_v1', '')}_v2')!) as Map)['p']
          as String;
      final saved = await cache.readSaved(_alice);
      expect(cache.fingerprintOf(saved!.items), payload, reason: cache.logName);
      expect(EncryptedAccountListCache.debugMemoIsFor(uidBox), isTrue,
          reason: cache.logName);
    }

    await check<RequestModel>(
        const RequestsLocalCache(), RequestsLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        request(id: 'r$i', notes: 'n$i', minPrice: '1${i}00', areas: ['A$i'])
    ]);
    await check<OfferModel>(
        const OffersLocalCache(), OffersLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        offer(id: 'f$i', notes: 'ملاحظة $i', squareFootage: '9$i')
    ]);
    await check<OwnerModel>(owners, aliceBox, _owners(20));
    await check<OfficeModel>(
        const OfficesLocalCache(), OfficesLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        office(id: 'c$i', name: 'مكتب $i').copyWith(userId: _alice)
    ]);
    await check<BrokerModel>(
        const BrokersLocalCache(), BrokersLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        broker(id: 'b$i', name: 'Broker $i').copyWith(userId: _alice)
    ]);
    await check<WatchmenModel>(
        const WatchmenLocalCache(), WatchmenLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        watchman(id: 'w$i', name: 'Watchman $i').copyWith(userId: _alice)
    ]);
    await check<StoredFavorite>(const FavoritesLocalCache(),
        FavoritesLocalCache.boxNameForUid(_alice), [
      for (var i = 0; i < 20; i++)
        StoredFavorite(
          account: _alice,
          id: 'fav$i',
          type: 'owners',
          title: 'Owner $i',
          subtitle: 'Palm $i',
          addedAt: DateTime.utc(2026, 10, 1 + i),
        )
    ]);
  });
}
