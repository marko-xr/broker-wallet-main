// Phase 2 / P2.4c: the Watchmen list reads this account's encrypted saved copy
// first.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// WatchmenListViewModel, WatchmenService and WatchmenLocalCache, the
// secure-storage test store, and a fake server stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
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
import 'package:broker_wallet/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

WatchmenModel _watchman(
  String id,
  String? account, {
  double? latitude = 25.0657,
  double? longitude = 55.1713,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    WatchmenModel(
      id: id,
      userId: account,
      name: 'Watchman $id',
      countryCode: '+971',
      phoneNumber: '505556677',
      buildingName: 'Tower $id',
      notes: 'notes $id',
      buildingLocation: 'Dubai Marina',
      pickUpLocation: 'Security desk',
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: 'Marina Promenade 9',
      createdAt: createdAt ?? DateTime.utc(2026, 11, 1, 2, 3, 4),
      updatedAt: updatedAt ?? DateTime.utc(2026, 11, 2, 3, 4, 5),
    );

List<Object?> _fields(WatchmenModel w) => [
      w.id,
      w.userId,
      w.name,
      w.countryCode,
      w.phoneNumber,
      w.buildingName,
      w.notes,
      w.buildingLocation,
      w.pickUpLocation,
      w.pickUpLatitude,
      w.pickUpLongitude,
      w.pickUpAddress,
      w.createdAt?.toUtc(),
      w.updatedAt?.toUtc(),
    ];

List<String?> _ids(List<WatchmenModel> watchmen) =>
    watchmen.map((o) => o.id).toList();

class _UnavailableKeys implements AccountCacheKeyStore {
  @override
  Future<List<int>?> read(String uid) async =>
      throw PlatformException(code: 'keystore-unavailable');

  @override
  Future<void> write(String uid, List<int> key) async =>
      throw PlatformException(code: 'keystore-unavailable');

  @override
  Future<void> delete(String uid) async =>
      throw PlatformException(code: 'keystore-unavailable');
}

/// The server side: one stream per screen subscription, answered by the test.
class _Watchmen extends WatchmenService {
  _Watchmen({required super.currentUserId, super.localCache});

  final List<StreamController<List<WatchmenModel>>> reads = [];

  StreamController<List<WatchmenModel>> get server => reads.single;

  @override
  Stream<List<WatchmenModel>> getUserWatchmen() {
    final read = StreamController<List<WatchmenModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const cache = WatchmenLocalCache();
  String? signedIn;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('watchmen_local_first_test');
    Hive.init(tempDir.path);
    EncryptedAccountListCache.debugStorageRoot = tempDir.path;
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    signedIn = _alice;
  });

  tearDown(() async {
    final names = [
      for (final uid in [_alice, _bob]) ...[
        WatchmenLocalCache.boxNameForUid(uid),
        BrokersLocalCache.boxNameForUid(uid),
        OfficesLocalCache.boxNameForUid(uid),
        OwnersLocalCache.boxNameForUid(uid),
        OffersLocalCache.boxNameForUid(uid),
        RequestsLocalCache.boxNameForUid(uid),
      ],
    ];
    for (final name in names) {
      // A box that failed to open is closed by Hive without waiting; on
      // Windows its file stays locked for a moment.
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

  File boxFile(String uid) => File('${listsDir()}${Platform.pathSeparator}'
      '${WatchmenLocalCache.boxNameForUid(uid)}.hive');

  Future<void> closeBox(String uid) async {
    final name = WatchmenLocalCache.boxNameForUid(uid);
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  String storedList(String uid) =>
      Hive.box<String>(WatchmenLocalCache.boxNameForUid(uid))
          .get('watchmen_v1')!;

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureWatchmenCacheKeyStore.storageKeyFor(uid));

  WatchmenListViewModel openWatchmen(_Watchmen service) {
    final vm = WatchmenListViewModel(watchmenService: service);
    addTearDown(vm.dispose);
    return vm;
  }

  _Watchmen service() => _Watchmen(currentUserId: () => signedIn);

  /// The saved copy is read from disk first; wait until the screen has gone
  /// on to ask the server.
  Future<void> untilServerRead(_Watchmen watchmen) async {
    for (var i = 0; i < 400 && watchmen.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(watchmen.reads, isNotEmpty, reason: 'the server is still asked');
    await pumpEventQueue();
  }

  group('offline reading', () {
    test('with the network down, the account\'s saved Watchmen stay shown',
        () async {
      await cache
          .write(_alice, [_watchman('f1', _alice), _watchman('f2', _alice)]);
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      expect(_ids(vm.watchmen), ['f1', 'f2'],
          reason: 'the saved copy shows before the server answers');

      watchmen.server.addError(const SocketException('offline'));
      await watchmen.server.close();
      await pumpEventQueue();

      expect(vm.hasLoadError, isFalse);
      expect(_ids(vm.watchmen), ['f1', 'f2']);
      expect(_ids((await cache.read(_alice))!), ['f1', 'f2'],
          reason: 'a failed read never discards the saved copy');
    });

    test('with nothing saved, a network failure still shows the load error',
        () async {
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      expect(vm.isLoading, isTrue);

      watchmen.server.addError(const SocketException('offline'));
      await watchmen.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
    });

    test(
        'the server list replaces the saved copy; an empty list is saved '
        'as empty', () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);

      watchmen.server.add([_watchman('f1', _alice), _watchman('f3', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.watchmen), ['f1', 'f3']);
      expect(_ids((await cache.read(_alice))!), ['f1', 'f3']);

      watchmen.server.add(const []);
      await pumpEventQueue();
      expect(vm.watchmen, isEmpty);
      expect(await cache.read(_alice), isEmpty,
          reason: 'the server answered "none": the saved copy is none too');
    });

    test('a failure after a list keeps that list and the saved copy', () async {
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      watchmen.server.add([_watchman('f1', _alice)]);
      await pumpEventQueue();

      watchmen.server.addError(const SocketException('offline'));
      await pumpEventQueue();
      expect(_ids(vm.watchmen), ['f1']);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });
  });

  group('account isolation', () {
    test('one account never sees another account\'s saved Watchmen', () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      signedIn = _bob;
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      expect(vm.watchmen, isEmpty);

      watchmen.server.addError(const SocketException('offline'));
      await watchmen.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
      expect(vm.watchmen, isEmpty);
    });

    test('Watchmen of another account, or of no account, are never saved',
        () async {
      await cache.write(_alice, [
        _watchman('f1', _alice),
        _watchman('b1', _bob),
        _watchman('n1', null),
      ]);
      final stored = storedList(_alice);
      expect(stored.contains(_bob), isFalse);
      expect(stored.contains('b1'), isFalse);
      expect(stored.contains('n1'), isFalse);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });

    test('nothing is saved once the account has changed', () async {
      final watchmen = service();
      openWatchmen(watchmen);
      await untilServerRead(watchmen);

      signedIn = _bob;
      watchmen.server.add([_watchman('f9', _alice)]);
      await pumpEventQueue();

      expect(await cache.read(_alice), isNull);
      expect(await cache.read(_bob), isNull);
    });

    test('a saved copy is not shown if the account changed while reading it',
        () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      var calls = 0;
      final watchmen =
          _Watchmen(currentUserId: () => calls++ == 0 ? _alice : _bob);
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      expect(vm.watchmen, isEmpty);
    });

    test('with no signed-in account nothing is read or saved', () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      signedIn = null;
      final watchmen = service();
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      expect(vm.watchmen, isEmpty);

      watchmen.server.add([_watchman('f2', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.watchmen), ['f2']);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });

    test('closing the screen while the copy is read starts no server read',
        () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      final watchmen = service();
      final subscription =
          watchmen.watchUserWatchmenLocalFirst().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(watchmen.reads, isEmpty);
    });

    test('a read that ends after the screen is closed saves nothing', () async {
      final watchmen = service();
      final vm = WatchmenListViewModel(watchmenService: watchmen);
      await untilServerRead(watchmen);
      vm.dispose();
      watchmen.server.add([_watchman('f5', _alice)]);
      await pumpEventQueue();
      expect(await cache.read(_alice), isNull);
    });
  });

  group('the saved copy', () {
    test('keeps every list field exactly, across a restart', () async {
      final original = _watchman(
        'f1',
        _alice,
        latitude: null,
        longitude: -0.000444,
      ).copyWith(notes: 'ملاحظة\nسطر ثان', buildingName: 'برج المارينا');
      final undated = WatchmenModel(
        id: 'f2',
        userId: _alice,
        name: 'Undated',
        countryCode: '+971',
        phoneNumber: '',
        buildingName: '',
        notes: '',
        buildingLocation: '',
        pickUpLocation: '',
        pickUpAddress: '',
      );
      await cache.write(_alice, [original, undated]);
      await closeBox(_alice);
      final read = (await cache.read(_alice))!;
      expect(_fields(read.first), _fields(original));
      expect(_fields(read.last), _fields(undated));
      expect(read.last.createdAt, isNull);
      expect(read.last.pickUpLatitude, isNull);
      expect(storedList(_alice).contains('"createdAt":null'), isTrue,
          reason: 'a missing value is stored as missing, never a fallback');
    });

    test('a damaged entry counts as nothing saved', () async {
      await cache.write(_alice, [_watchman('f0', _alice)]);
      await Hive.box<String>(WatchmenLocalCache.boxNameForUid(_alice))
          .put('watchmen_v1', '{not json');
      expect(await cache.read(_alice), isNull);
    });
  });

  group('encryption and keys', () {
    test(
        'the copy is encrypted on disk and its key is only in secure '
        'storage', () async {
      await cache.write(_alice, [
        _watchman('f1', _alice).copyWith(
          name: 'Secret Watchman',
          phoneNumber: '509876543',
          notes: 'SECRET-WATCHMAN-NOTE',
        ),
      ]);
      await closeBox(_alice);

      final onDisk = latin1.decode(boxFile(_alice).readAsBytesSync());
      for (final secret in [
        'Secret Watchman',
        '509876543',
        'SECRET-WATCHMAN-NOTE',
        'Dubai Marina',
        _alice,
      ]) {
        expect(onDisk.contains(secret), isFalse, reason: '"$secret" in clear');
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(base64.decode((await secureKey(_alice))!), hasLength(32));
      expect((await cache.read(_alice))!.single.name, 'Secret Watchman');
    });

    test('Watchmen and the five other caches keep separate keys and boxes',
        () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      for (final other in [
        SecureBrokersCacheKeyStore.storageKeyFor(_alice),
        SecureOfficesCacheKeyStore.storageKeyFor(_alice),
        SecureOwnersCacheKeyStore.storageKeyFor(_alice),
        SecureOffersCacheKeyStore.storageKeyFor(_alice),
        SecureRequestsCacheKeyStore.storageKeyFor(_alice),
      ]) {
        expect(await const FlutterSecureStorage().read(key: other), isNull,
            reason: 'writing Watchmen creates only its own key');
      }
      expect(
        {
          WatchmenLocalCache.boxNameForUid(_alice),
          BrokersLocalCache.boxNameForUid(_alice),
          OfficesLocalCache.boxNameForUid(_alice),
          OwnersLocalCache.boxNameForUid(_alice),
          OffersLocalCache.boxNameForUid(_alice),
          RequestsLocalCache.boxNameForUid(_alice),
        },
        hasLength(6),
      );
      expect(
        {
          SecureWatchmenCacheKeyStore.storageKeyFor(_alice),
          SecureBrokersCacheKeyStore.storageKeyFor(_alice),
          SecureOfficesCacheKeyStore.storageKeyFor(_alice),
          SecureOwnersCacheKeyStore.storageKeyFor(_alice),
          SecureOffersCacheKeyStore.storageKeyFor(_alice),
          SecureRequestsCacheKeyStore.storageKeyFor(_alice),
        },
        hasLength(6),
      );
    });

    test('existing caches are untouched by a Watchmen write and read',
        () async {
      await const OwnersLocalCache().write(_alice, []);
      final ownersKey = await const FlutterSecureStorage()
          .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice));
      await cache.write(_alice, [_watchman('f1', _alice)]);
      await cache.read(_alice);
      expect(
        await const FlutterSecureStorage()
            .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice)),
        ownersKey,
      );
      expect(await const OwnersLocalCache().read(_alice), isEmpty);
    });

    test(
        'with key storage unavailable nothing is read or written, and '
        'nothing is stored unencrypted', () async {
      final broken = WatchmenLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_watchman('f1', _alice)]);
      expect(
          await Hive.boxExists(WatchmenLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await broken.read(_alice), isNull);

      final watchmen =
          _Watchmen(currentUserId: () => signedIn, localCache: broken);
      final vm = openWatchmen(watchmen);
      await untilServerRead(watchmen);
      watchmen.server.addError(const SocketException('offline'));
      await watchmen.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue, reason: 'as before the cache existed');
    });

    test(
        'a box whose key went missing is never read, overwritten or given a '
        'new key', () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage()
          .delete(key: SecureWatchmenCacheKeyStore.storageKeyFor(_alice));
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_watchman('f2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      await closeBox(_alice);
      final otherKey = base64.encode(List<int>.generate(32, (i) => 5 * i));
      await const FlutterSecureStorage().write(
        key: SecureWatchmenCacheKeyStore.storageKeyFor(_alice),
        value: otherKey,
      );
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_watchman('f2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });

    test('a corrupted box counts as nothing saved and is left unchanged',
        () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      await closeBox(_alice);
      final bytes = boxFile(_alice).readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] = bytes[i] ^ 0x5a;
      }
      boxFile(_alice).writeAsBytesSync(bytes);

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_watchman('f2', _alice)]);
      expect(boxFile(_alice).readAsBytesSync(), bytes);
    });
  });

  group('account deletion', () {
    test(
        'removes the deleted account\'s Watchmen box and key, and no one '
        'else\'s', () async {
      await cache.write(_alice, [_watchman('f1', _alice)]);
      await cache.write(_bob, [_watchman('b1', _bob)]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(
          await Hive.boxExists(WatchmenLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_alice), isNull);
      expect(await secureKey(_bob), isNotNull);
      expect(_ids((await cache.read(_bob))!), ['b1']);
    });
  });
}
