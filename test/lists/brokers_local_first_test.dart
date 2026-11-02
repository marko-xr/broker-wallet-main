// Phase 2 / P2.4b: the Brokers list reads this account's encrypted saved copy
// first.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// BrokersListViewModel, BrokerService and BrokersLocalCache, the
// secure-storage test store, and a fake server stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_brokers_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The list JSON inside a stored authenticated (v2) list.
extension on String {
  String get payload => (json.decode(this) as Map)['p'] as String;
}

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

BrokerModel _broker(
  String id,
  String? account, {
  DateTime? createdAt,
  DateTime? updatedAt,
  bool undated = false,
}) =>
    BrokerModel(
      id: id,
      userId: account,
      name: 'Broker $id',
      countryCode: '+971',
      phoneNumber: '504445566',
      notes: 'notes $id',
      createdAt:
          undated ? null : (createdAt ?? DateTime.utc(2026, 9, 1, 2, 3, 4)),
      updatedAt:
          undated ? null : (updatedAt ?? DateTime.utc(2026, 10, 2, 3, 4, 5)),
    );

List<Object?> _fields(BrokerModel b) => [
      b.id,
      b.userId,
      b.name,
      b.countryCode,
      b.phoneNumber,
      b.notes,
      b.createdAt?.toUtc(),
      b.updatedAt?.toUtc(),
    ];

List<String?> _ids(List<BrokerModel> brokers) =>
    brokers.map((o) => o.id).toList();

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
class _Brokers extends BrokerService {
  _Brokers({required super.currentUserId, super.localCache});

  final List<StreamController<List<BrokerModel>>> reads = [];

  StreamController<List<BrokerModel>> get server => reads.single;

  @override
  Stream<List<BrokerModel>> getUserBrokers() {
    final read = StreamController<List<BrokerModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const cache = BrokersLocalCache();
  String? signedIn;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('brokers_local_first_test');
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
      '${BrokersLocalCache.boxNameForUid(uid)}.hive');

  Future<void> closeBox(String uid) async {
    final name = BrokersLocalCache.boxNameForUid(uid);
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  String storedList(String uid) =>
      Hive.box<String>(BrokersLocalCache.boxNameForUid(uid))
          .get('brokers_v2')!
          .payload;

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureBrokersCacheKeyStore.storageKeyFor(uid));

  BrokersListViewModel openBrokers(_Brokers service) {
    final vm = BrokersListViewModel(brokerService: service);
    addTearDown(vm.dispose);
    return vm;
  }

  _Brokers service() => _Brokers(currentUserId: () => signedIn);

  /// The saved copy is read from disk first; wait until the screen has gone
  /// on to ask the server.
  Future<void> untilServerRead(_Brokers brokers) async {
    for (var i = 0; i < 400 && brokers.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(brokers.reads, isNotEmpty, reason: 'the server is still asked');
    await pumpEventQueue();
  }

  group('offline reading', () {
    test('with the network down, the account\'s saved Brokers stay shown',
        () async {
      await cache.write(_alice, [_broker('f1', _alice), _broker('f2', _alice)]);
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      expect(_ids(vm.brokers), ['f1', 'f2'],
          reason: 'the saved copy shows before the server answers');

      brokers.server.addError(const SocketException('offline'));
      await brokers.server.close();
      await pumpEventQueue();

      expect(vm.hasLoadError, isFalse);
      expect(_ids(vm.brokers), ['f1', 'f2']);
      expect(_ids((await cache.read(_alice))!), ['f1', 'f2'],
          reason: 'a failed read never discards the saved copy');
    });

    test('with nothing saved, a network failure still shows the load error',
        () async {
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      expect(vm.isLoading, isTrue);

      brokers.server.addError(const SocketException('offline'));
      await brokers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
    });

    test(
        'the server list replaces the saved copy; an empty list is saved '
        'as empty', () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);

      brokers.server.add([_broker('f1', _alice), _broker('f3', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.brokers), ['f1', 'f3']);
      expect(_ids((await cache.read(_alice))!), ['f1', 'f3']);

      brokers.server.add(const []);
      await pumpEventQueue();
      expect(vm.brokers, isEmpty);
      expect(await cache.read(_alice), isEmpty,
          reason: 'the server answered "none": the saved copy is none too');
    });

    test('a failure after a list keeps that list and the saved copy', () async {
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      brokers.server.add([_broker('f1', _alice)]);
      await pumpEventQueue();

      brokers.server.addError(const SocketException('offline'));
      await pumpEventQueue();
      expect(_ids(vm.brokers), ['f1']);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });
  });

  group('account isolation', () {
    test('one account never sees another account\'s saved Brokers', () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      signedIn = _bob;
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      expect(vm.brokers, isEmpty);

      brokers.server.addError(const SocketException('offline'));
      await brokers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
      expect(vm.brokers, isEmpty);
    });

    test('Brokers of another account, or of no account, are never saved',
        () async {
      await cache.write(_alice, [
        _broker('f1', _alice),
        _broker('b1', _bob),
        _broker('n1', null),
      ]);
      final stored = storedList(_alice);
      expect(stored.contains(_bob), isFalse);
      expect(stored.contains('b1'), isFalse);
      expect(stored.contains('n1'), isFalse);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });

    test('nothing is saved once the account has changed', () async {
      final brokers = service();
      openBrokers(brokers);
      await untilServerRead(brokers);

      signedIn = _bob;
      brokers.server.add([_broker('f9', _alice)]);
      await pumpEventQueue();

      expect(await cache.read(_alice), isNull);
      expect(await cache.read(_bob), isNull);
    });

    test('a saved copy is not shown if the account changed while reading it',
        () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      var calls = 0;
      final brokers =
          _Brokers(currentUserId: () => calls++ == 0 ? _alice : _bob);
      final vm = openBrokers(brokers);
      // The list was opened for an account that has gone: it shows nothing
      // and asks the server nothing for it.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(brokers.reads, isEmpty);
      expect(vm.brokers, isEmpty);
    });

    test('with no signed-in account nothing is read or saved', () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      signedIn = null;
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      expect(vm.brokers, isEmpty);

      brokers.server.add([_broker('f2', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.brokers), ['f2']);
      expect(_ids((await cache.read(_alice))!), ['f1']);
    });

    test('closing the screen while the copy is read starts no server read',
        () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      final brokers = service();
      final subscription = brokers.watchUserBrokersLocalFirst().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(brokers.reads, isEmpty);
    });

    test('a read that ends after the screen is closed saves nothing', () async {
      final brokers = service();
      final vm = BrokersListViewModel(brokerService: brokers);
      await untilServerRead(brokers);
      vm.dispose();
      brokers.server.add([_broker('f5', _alice)]);
      await pumpEventQueue();
      expect(await cache.read(_alice), isNull);
    });
  });

  group('the saved copy', () {
    test('keeps every list field exactly, across a restart', () async {
      final original = _broker('f1', _alice)
          .copyWith(notes: 'ملاحظة\nسطر ثان', name: 'وسيط عقاري');
      final undated = _broker('f2', _alice, undated: true);
      await cache.write(_alice, [original, undated]);
      await closeBox(_alice);
      final read = (await cache.read(_alice))!;
      expect(_fields(read.first), _fields(original));
      expect(_fields(read.last), _fields(undated));
      expect(read.last.createdAt, isNull);
    });

    test(
        'a missing server date stays missing in the copy; the screen\'s '
        'stand-in date is display only', () async {
      final brokers = service();
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      brokers.server.add([_broker('f1', _alice, undated: true)]);
      await pumpEventQueue();

      expect(vm.brokers.single.createdAt, isNotNull,
          reason: 'the list shows a stand-in date as before');
      final saved = (await cache.read(_alice))!.single;
      expect(saved.createdAt, isNull, reason: 'never saved as data');
      expect(storedList(_alice).contains('"createdAt":null'), isTrue);
    });

    test('a damaged entry counts as nothing saved', () async {
      await cache.write(_alice, [_broker('f0', _alice)]);
      await Hive.box<String>(BrokersLocalCache.boxNameForUid(_alice))
          .put('brokers_v2', '{not json');
      expect(await cache.read(_alice), isNull);
    });
  });

  group('encryption and keys', () {
    test(
        'the copy is encrypted on disk and its key is only in secure '
        'storage', () async {
      await cache.write(_alice, [
        _broker('f1', _alice).copyWith(
          name: 'Secret Broker',
          phoneNumber: '509876543',
          notes: 'SECRET-BROKER-NOTE',
        ),
      ]);
      await closeBox(_alice);

      final onDisk = latin1.decode(boxFile(_alice).readAsBytesSync());
      for (final secret in [
        'Secret Broker',
        '509876543',
        'SECRET-BROKER-NOTE',
        _alice,
      ]) {
        expect(onDisk.contains(secret), isFalse, reason: '"$secret" in clear');
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(base64.decode((await secureKey(_alice))!), hasLength(32));
      expect((await cache.read(_alice))!.single.name, 'Secret Broker');
    });

    test(
        'Brokers, Offices, Owners, Offers and Requests keep separate keys and boxes',
        () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      for (final other in [
        SecureOfficesCacheKeyStore.storageKeyFor(_alice),
        SecureOwnersCacheKeyStore.storageKeyFor(_alice),
        SecureOffersCacheKeyStore.storageKeyFor(_alice),
        SecureRequestsCacheKeyStore.storageKeyFor(_alice),
      ]) {
        expect(await const FlutterSecureStorage().read(key: other), isNull,
            reason: 'writing Brokers creates only its own key');
      }
      expect(
        {
          BrokersLocalCache.boxNameForUid(_alice),
          OfficesLocalCache.boxNameForUid(_alice),
          OwnersLocalCache.boxNameForUid(_alice),
          OffersLocalCache.boxNameForUid(_alice),
          RequestsLocalCache.boxNameForUid(_alice),
        },
        hasLength(5),
      );
      expect(
        {
          SecureBrokersCacheKeyStore.storageKeyFor(_alice),
          SecureOfficesCacheKeyStore.storageKeyFor(_alice),
          SecureOwnersCacheKeyStore.storageKeyFor(_alice),
          SecureOffersCacheKeyStore.storageKeyFor(_alice),
          SecureRequestsCacheKeyStore.storageKeyFor(_alice),
        },
        hasLength(5),
      );
    });

    test('existing caches are untouched by a Brokers write and read', () async {
      await const OwnersLocalCache().write(_alice, []);
      final ownersKey = await const FlutterSecureStorage()
          .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice));
      await cache.write(_alice, [_broker('f1', _alice)]);
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
      final broken = BrokersLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_broker('f1', _alice)]);
      expect(
          await Hive.boxExists(BrokersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await broken.read(_alice), isNull);

      final brokers =
          _Brokers(currentUserId: () => signedIn, localCache: broken);
      final vm = openBrokers(brokers);
      await untilServerRead(brokers);
      brokers.server.addError(const SocketException('offline'));
      await brokers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue, reason: 'as before the cache existed');
    });

    test(
        'a box whose key went missing is never read, overwritten or given a '
        'new key', () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage()
          .delete(key: SecureBrokersCacheKeyStore.storageKeyFor(_alice));
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_broker('f2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      await closeBox(_alice);
      final otherKey = base64.encode(List<int>.generate(32, (i) => 5 * i));
      await const FlutterSecureStorage().write(
        key: SecureBrokersCacheKeyStore.storageKeyFor(_alice),
        value: otherKey,
      );
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_broker('f2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });

    test('a corrupted box counts as nothing saved and is left unchanged',
        () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      await closeBox(_alice);
      final bytes = boxFile(_alice).readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] = bytes[i] ^ 0x5a;
      }
      boxFile(_alice).writeAsBytesSync(bytes);

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_broker('f2', _alice)]);
      expect(boxFile(_alice).readAsBytesSync(), bytes);
    });
  });

  group('account deletion', () {
    test(
        'removes the deleted account\'s Brokers box and key, and no one '
        'else\'s', () async {
      await cache.write(_alice, [_broker('f1', _alice)]);
      await cache.write(_bob, [_broker('b1', _bob)]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(
          await Hive.boxExists(BrokersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_alice), isNull);
      expect(await secureKey(_bob), isNotNull);
      expect(_ids((await cache.read(_bob))!), ['b1']);
    });
  });
}
