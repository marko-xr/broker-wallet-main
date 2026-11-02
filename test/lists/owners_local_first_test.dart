// Phase 2 / P2.3: the Owners list reads this account's encrypted saved copy
// first.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// OwnersListViewModel, OwnerService and OwnersLocalCache, the secure-storage
// test store, and a fake server stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

OwnerModel _owner(
  String id,
  String account, {
  double? latitude = 25.2048,
  double? longitude = 55.2708,
  String? uploadedFileName,
  String? mediaUrl,
  List<String> mediaUrls = const [],
}) =>
    OwnerModel(
      id: id,
      userId: account,
      name: 'Owner $id',
      phoneNumber: '502223344',
      countryCode: '+971',
      typeOfProperties: 'Villa, Apartment',
      propertyLocation: 'Palm Jumeirah',
      notes: 'notes $id',
      pickUpLocation: 'Gate 3',
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: 'Frond K',
      uploadedFileName: uploadedFileName,
      mediaUrl: mediaUrl,
      mediaUrls: mediaUrls,
      createdAt: DateTime.utc(2026, 5, 6, 7, 8, 9),
      updatedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
    );

List<Object?> _fields(OwnerModel o) => [
      o.id,
      o.userId,
      o.name,
      o.phoneNumber,
      o.countryCode,
      o.typeOfProperties,
      o.propertyLocation,
      o.notes,
      o.pickUpLocation,
      o.pickUpLatitude,
      o.pickUpLongitude,
      o.pickUpAddress,
      o.uploadedFileName,
      o.createdAt.toUtc(),
      o.updatedAt.toUtc(),
    ];

List<String?> _ids(List<OwnerModel> owners) => owners.map((o) => o.id).toList();

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
class _Owners extends OwnerService {
  _Owners({required super.currentUserId, super.localCache});

  final List<StreamController<List<OwnerModel>>> reads = [];

  StreamController<List<OwnerModel>> get server => reads.single;

  @override
  Stream<List<OwnerModel>> getUserOwners() {
    final read = StreamController<List<OwnerModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const cache = OwnersLocalCache();
  String? signedIn;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('owners_local_first_test');
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
      '${OwnersLocalCache.boxNameForUid(uid)}.hive');

  Future<void> closeBox(String uid) async {
    final name = OwnersLocalCache.boxNameForUid(uid);
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  String storedList(String uid) =>
      Hive.box<String>(OwnersLocalCache.boxNameForUid(uid)).get('owners_v1')!;

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureOwnersCacheKeyStore.storageKeyFor(uid));

  OwnersListViewModel openOwners(_Owners service) {
    final vm = OwnersListViewModel(ownerService: service);
    addTearDown(vm.dispose);
    return vm;
  }

  _Owners service() => _Owners(currentUserId: () => signedIn);

  /// The saved copy is read from disk first; wait until the screen has gone
  /// on to ask the server.
  Future<void> untilServerRead(_Owners owners) async {
    for (var i = 0; i < 400 && owners.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(owners.reads, isNotEmpty, reason: 'the server is still asked');
    await pumpEventQueue();
  }

  group('offline reading', () {
    test('with the network down, the account\'s saved Owners stay shown',
        () async {
      await cache.write(_alice, [_owner('w1', _alice), _owner('w2', _alice)]);
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);
      expect(_ids(vm.owners), ['w1', 'w2'],
          reason: 'the saved copy shows before the server answers');

      owners.server.addError(const SocketException('offline'));
      await owners.server.close();
      await pumpEventQueue();

      expect(vm.hasLoadError, isFalse);
      expect(_ids(vm.owners), ['w1', 'w2']);
      expect(_ids((await cache.read(_alice))!), ['w1', 'w2'],
          reason: 'a failed read never discards the saved copy');
    });

    test('with nothing saved, a network failure still shows the load error',
        () async {
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);
      expect(vm.isLoading, isTrue);

      owners.server.addError(const SocketException('offline'));
      await owners.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
    });

    test(
        'the server list replaces the saved copy; an empty list is saved '
        'as empty', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);

      owners.server.add([_owner('w1', _alice), _owner('w3', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.owners), ['w1', 'w3']);
      expect(_ids((await cache.read(_alice))!), ['w1', 'w3']);

      owners.server.add(const []);
      await pumpEventQueue();
      expect(vm.owners, isEmpty);
      expect(await cache.read(_alice), isEmpty,
          reason: 'the server answered "none": the saved copy is none too');
    });

    test('a failure after a list keeps that list and the saved copy', () async {
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);
      owners.server.add([_owner('w1', _alice)]);
      await pumpEventQueue();

      owners.server.addError(const SocketException('offline'));
      await pumpEventQueue();
      expect(_ids(vm.owners), ['w1']);
      expect(_ids((await cache.read(_alice))!), ['w1']);
    });
  });

  group('account isolation', () {
    test('one account never sees another account\'s saved Owners', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      signedIn = _bob;
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);
      expect(vm.owners, isEmpty);

      owners.server.addError(const SocketException('offline'));
      await owners.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
      expect(vm.owners, isEmpty);
    });

    test('Owners belonging to another account are never saved', () async {
      await cache.write(_alice, [_owner('w1', _alice), _owner('b1', _bob)]);
      final stored = storedList(_alice);
      expect(stored.contains(_bob), isFalse);
      expect(stored.contains('b1'), isFalse);
      expect(_ids((await cache.read(_alice))!), ['w1']);
    });

    test('the cache belongs to the account, not to an Owner record id',
        () async {
      // An Owner record whose own id happens to equal Bob's account id is
      // still Alice's record and goes only to Alice's box.
      await cache.write(_alice, [_owner(_bob, _alice)]);
      expect(_ids((await cache.read(_alice))!), [_bob]);
      expect(
          await Hive.boxExists(OwnersLocalCache.boxNameForUid(_bob),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_bob), isNull);
    });

    test('nothing is saved once the account has changed', () async {
      final owners = service();
      openOwners(owners);
      await untilServerRead(owners);

      signedIn = _bob;
      owners.server.add([_owner('w9', _alice)]);
      await pumpEventQueue();

      expect(await cache.read(_alice), isNull);
      expect(await cache.read(_bob), isNull);
    });

    test('a saved copy is not shown if the account changed while reading it',
        () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      var calls = 0;
      final owners = _Owners(currentUserId: () => calls++ == 0 ? _alice : _bob);
      final vm = openOwners(owners);
      await untilServerRead(owners);
      expect(vm.owners, isEmpty);
    });

    test('with no signed-in account nothing is read or saved', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      signedIn = null;
      final owners = service();
      final vm = openOwners(owners);
      await untilServerRead(owners);
      expect(vm.owners, isEmpty);

      owners.server.add([_owner('w2', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.owners), ['w2']);
      expect(_ids((await cache.read(_alice))!), ['w1']);
    });

    test('closing the screen while the copy is read starts no server read',
        () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      final owners = service();
      final subscription = owners.watchUserOwnersLocalFirst().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(owners.reads, isEmpty);
    });

    test('a read that ends after the screen is closed saves nothing', () async {
      final owners = service();
      final vm = OwnersListViewModel(ownerService: owners);
      await untilServerRead(owners);
      vm.dispose();
      owners.server.add([_owner('w5', _alice)]);
      await pumpEventQueue();
      expect(await cache.read(_alice), isNull);
    });
  });

  group('the saved copy', () {
    test('keeps every list field exactly, across a restart', () async {
      final original = _owner(
        'w1',
        _alice,
        latitude: null,
        longitude: -0.000987654321,
        uploadedFileName: 'legacy-plan.pdf',
      ).copyWith(
        notes: 'ملاحظة\nسطر ثان',
        propertyLocation: 'نخلة جميرا',
      );
      await cache.write(_alice, [original, _owner('w2', _alice)]);
      await closeBox(_alice);
      final read = await cache.read(_alice);
      expect(_fields(read!.first), _fields(original));
      expect(read.last.uploadedFileName, isNull);
    });

    test('never holds media or transport links', () async {
      const signed =
          'https://media.example.test/w1.jpg?X-Amz-Signature=deadbeef';
      await cache.write(_alice, [
        _owner('w1', _alice, mediaUrl: signed, mediaUrls: const [signed]),
      ]);
      final stored = storedList(_alice);
      for (final part in [
        'X-Amz-Signature',
        'media.example.test',
        'mediaUrl',
        'https://',
        'token',
      ]) {
        expect(stored.contains(part), isFalse, reason: '"$part" stored');
      }
      final read = (await cache.read(_alice))!.single;
      expect(read.mediaUrl, isNull);
      expect(read.mediaUrls, isEmpty);
    });

    test('a damaged entry counts as nothing saved', () async {
      await cache.write(_alice, [_owner('w0', _alice)]);
      await Hive.box<String>(OwnersLocalCache.boxNameForUid(_alice))
          .put('owners_v1', '{not json');
      expect(await cache.read(_alice), isNull);
    });
  });

  group('encryption and keys', () {
    test(
        'the copy is encrypted on disk and its key is only in secure '
        'storage', () async {
      await cache.write(_alice, [
        _owner('w1', _alice).copyWith(
          name: 'Secret Landlord',
          phoneNumber: '509876543',
          notes: 'SECRET-OWNER-NOTE',
        ),
      ]);
      await closeBox(_alice);

      final onDisk = latin1.decode(boxFile(_alice).readAsBytesSync());
      for (final secret in [
        'Secret Landlord',
        '509876543',
        'SECRET-OWNER-NOTE',
        'Palm Jumeirah',
        _alice,
      ]) {
        expect(onDisk.contains(secret), isFalse, reason: '"$secret" in clear');
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(base64.decode((await secureKey(_alice))!), hasLength(32));
      expect((await cache.read(_alice))!.single.name, 'Secret Landlord');
    });

    test('Owners, Offers and Requests keep separate keys and boxes', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      final offersKey = await const FlutterSecureStorage()
          .read(key: SecureOffersCacheKeyStore.storageKeyFor(_alice));
      final requestsKey = await const FlutterSecureStorage()
          .read(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      expect(offersKey, isNull, reason: 'writing Owners creates only its key');
      expect(requestsKey, isNull);
      expect(
        {
          OwnersLocalCache.boxNameForUid(_alice),
          OffersLocalCache.boxNameForUid(_alice),
          RequestsLocalCache.boxNameForUid(_alice),
        },
        hasLength(3),
      );
      expect(
        {
          SecureOwnersCacheKeyStore.storageKeyFor(_alice),
          SecureOffersCacheKeyStore.storageKeyFor(_alice),
          SecureRequestsCacheKeyStore.storageKeyFor(_alice),
        },
        hasLength(3),
      );
    });

    test(
        'with key storage unavailable nothing is read or written, and '
        'nothing is stored unencrypted', () async {
      final broken = OwnersLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_owner('w1', _alice)]);
      expect(
          await Hive.boxExists(OwnersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await broken.read(_alice), isNull);

      final owners = _Owners(currentUserId: () => signedIn, localCache: broken);
      final vm = openOwners(owners);
      await untilServerRead(owners);
      owners.server.addError(const SocketException('offline'));
      await owners.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue, reason: 'as before the cache existed');
    });

    test(
        'a box whose key went missing is never read, overwritten or given a '
        'new key', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage()
          .delete(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice));
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_owner('w2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      await closeBox(_alice);
      final otherKey = base64.encode(List<int>.generate(32, (i) => 3 * i));
      await const FlutterSecureStorage().write(
        key: SecureOwnersCacheKeyStore.storageKeyFor(_alice),
        value: otherKey,
      );
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_owner('w2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });

    test('a corrupted box counts as nothing saved and is left unchanged',
        () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      await closeBox(_alice);
      final bytes = boxFile(_alice).readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] = bytes[i] ^ 0x5a;
      }
      boxFile(_alice).writeAsBytesSync(bytes);

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_owner('w2', _alice)]);
      expect(boxFile(_alice).readAsBytesSync(), bytes);
    });
  });

  group('account deletion', () {
    test(
        'removes the deleted account\'s Owners box and key, and no one '
        'else\'s', () async {
      await cache.write(_alice, [_owner('w1', _alice)]);
      await cache.write(_bob, [_owner('b1', _bob)]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(
          await Hive.boxExists(OwnersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_alice), isNull);
      expect(await secureKey(_bob), isNotNull);
      expect(_ids((await cache.read(_bob))!), ['b1']);
    });
  });
}
