// Phase 2 / P2.2: the Offers list reads this account's encrypted saved copy
// first.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// OffersListViewModel, OfferService and OffersLocalCache, the secure-storage
// test store, and a fake server stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
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

OfferModel _offer(
  String id,
  String owner, {
  PropertyStatus status = PropertyStatus.available,
  double? latitude = 25.0772,
  double? longitude = 55.1393,
  String? mediaUrl,
  List<String> mediaUrls = const [],
  List<String> mediaObjectIds = const [],
}) =>
    OfferModel(
      id: id,
      userId: owner,
      offerType: 'sell',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina', 'JBR'],
      location: 'Tower 2',
      phoneNumber: '501234567',
      countryCode: '+971',
      minPrice: '1500000',
      maxPrice: '1700000',
      squareFootage: '1200',
      notes: 'notes $id',
      propertyType: 'residential',
      specificPropertyType: 'apartment',
      rooms: 3,
      bathrooms: 2,
      pickUpLocation: 'Lobby',
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: 'Marina Walk 1',
      uploadedFileName: '',
      mediaUrl: mediaUrl,
      status: status,
      createdAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
      updatedAt: DateTime.utc(2026, 4, 5, 6, 7, 8),
      mediaUrls: mediaUrls,
      mediaObjectIds: mediaObjectIds,
    );

List<Object?> _fields(OfferModel o) => [
      o.id,
      o.userId,
      o.offerType,
      o.selectedCity,
      o.selectedAreas,
      o.location,
      o.phoneNumber,
      o.countryCode,
      o.minPrice,
      o.maxPrice,
      o.squareFootage,
      o.notes,
      o.propertyType,
      o.specificPropertyType,
      o.rooms,
      o.bathrooms,
      o.pickUpLocation,
      o.pickUpLatitude,
      o.pickUpLongitude,
      o.pickUpAddress,
      o.uploadedFileName,
      o.status,
      o.createdAt.toUtc(),
      o.updatedAt.toUtc(),
    ];

List<String?> _ids(List<OfferModel> offers) => offers.map((o) => o.id).toList();

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
class _Offers extends OfferService {
  _Offers({required super.currentUserId, super.localCache});

  final List<StreamController<List<OfferModel>>> reads = [];

  StreamController<List<OfferModel>> get server => reads.single;

  @override
  Stream<List<OfferModel>> getUserOffers() {
    final read = StreamController<List<OfferModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const cache = OffersLocalCache();
  String? signedIn;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('offers_local_first_test');
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
      '${OffersLocalCache.boxNameForUid(uid)}.hive');

  Future<void> closeBox(String uid) async {
    final name = OffersLocalCache.boxNameForUid(uid);
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureOffersCacheKeyStore.storageKeyFor(uid));

  OffersListViewModel openOffers(_Offers service) {
    final vm = OffersListViewModel(offerService: service);
    addTearDown(vm.dispose);
    return vm;
  }

  _Offers service() => _Offers(currentUserId: () => signedIn);

  /// The saved copy is read from disk first; wait until the screen has gone
  /// on to ask the server.
  Future<void> untilServerRead(_Offers offers) async {
    for (var i = 0; i < 400 && offers.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(offers.reads, isNotEmpty, reason: 'the server is still asked');
    await pumpEventQueue();
  }

  group('offline reading', () {
    test('with the network down, the account\'s saved Offers stay shown',
        () async {
      await cache.write(_alice, [_offer('o1', _alice), _offer('o2', _alice)]);
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);
      expect(_ids(vm.offers), ['o1', 'o2'],
          reason: 'the saved copy shows before the server answers');

      offers.server.addError(const SocketException('offline'));
      await offers.server.close();
      await pumpEventQueue();

      expect(vm.hasLoadError, isFalse);
      expect(_ids(vm.offers), ['o1', 'o2']);
      expect(_ids((await cache.read(_alice))!), ['o1', 'o2'],
          reason: 'a failed read never discards the saved copy');
    });

    test('with nothing saved, a network failure still shows the load error',
        () async {
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);
      expect(vm.isLoading, isTrue);

      offers.server.addError(const SocketException('offline'));
      await offers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
    });

    test(
        'the server list replaces the saved copy; an empty list is saved '
        'as empty', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);

      offers.server.add([_offer('o1', _alice), _offer('o3', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.offers), ['o1', 'o3']);
      expect(_ids((await cache.read(_alice))!), ['o1', 'o3']);

      offers.server.add(const []);
      await pumpEventQueue();
      expect(vm.offers, isEmpty);
      expect(await cache.read(_alice), isEmpty,
          reason: 'the server answered "none": the saved copy is none too');
    });

    test('a failure after a list keeps that list and the saved copy', () async {
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);
      offers.server.add([_offer('o1', _alice)]);
      await pumpEventQueue();

      offers.server.addError(const SocketException('offline'));
      await pumpEventQueue();
      expect(_ids(vm.offers), ['o1']);
      expect(_ids((await cache.read(_alice))!), ['o1']);
    });
  });

  group('account isolation', () {
    test('one account never sees another account\'s saved Offers', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      signedIn = _bob;
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);
      expect(vm.offers, isEmpty);

      offers.server.addError(const SocketException('offline'));
      await offers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
      expect(vm.offers, isEmpty);
    });

    test('Offers owned by another account are never saved', () async {
      await cache.write(_alice, [_offer('o1', _alice), _offer('b1', _bob)]);
      // The stored list itself (decrypted; the box is open with its key),
      // not only what a read lets through.
      final stored = Hive.box<String>(OffersLocalCache.boxNameForUid(_alice))
          .get('offers_v2')!
          .payload;
      expect(stored.contains(_bob), isFalse);
      expect(stored.contains('b1'), isFalse);
      expect(_ids((await cache.read(_alice))!), ['o1']);
    });

    test('nothing is saved once the account has changed', () async {
      final offers = service();
      openOffers(offers);
      await untilServerRead(offers);

      signedIn = _bob;
      offers.server.add([_offer('o9', _alice)]);
      await pumpEventQueue();

      expect(await cache.read(_alice), isNull);
      expect(await cache.read(_bob), isNull);
    });

    test('a saved copy is not shown if the account changed while reading it',
        () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      var calls = 0;
      final offers = _Offers(currentUserId: () => calls++ == 0 ? _alice : _bob);
      final vm = openOffers(offers);
      await untilServerRead(offers);
      expect(vm.offers, isEmpty);
    });

    test('with no signed-in account nothing is read or saved', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      signedIn = null;
      final offers = service();
      final vm = openOffers(offers);
      await untilServerRead(offers);
      expect(vm.offers, isEmpty);

      offers.server.add([_offer('o2', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.offers), ['o2']);
      expect(_ids((await cache.read(_alice))!), ['o1']);
    });

    test('closing the screen while the copy is read starts no server read',
        () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      final offers = service();
      final subscription = offers.watchUserOffersLocalFirst().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(offers.reads, isEmpty);
    });
  });

  group('the saved copy', () {
    test('keeps every list field exactly', () async {
      final original = _offer(
        'o1',
        _alice,
        status: PropertyStatus.sold,
        latitude: null,
        longitude: -0.000123456789,
      ).copyWith(notes: 'ملاحظة\nسطر ثان', selectedAreas: ['الخليج التجاري']);
      await cache.write(_alice, [original]);
      await closeBox(_alice);
      final read = (await cache.read(_alice))!.single;
      expect(_fields(read), _fields(original));
    });

    test('never holds media: no signed URL, no media id', () async {
      const signed =
          'https://media.example.test/o1.jpg?X-Amz-Signature=deadbeef';
      await cache.write(_alice, [
        _offer('o1', _alice,
            mediaUrl: signed,
            mediaUrls: const [signed],
            mediaObjectIds: const ['media-object-1']),
      ]);
      // The box is open with its key: this is the stored list, decrypted.
      final stored = Hive.box<String>(OffersLocalCache.boxNameForUid(_alice))
          .get('offers_v2')!
          .payload;
      for (final part in [
        'X-Amz-Signature',
        'media.example.test',
        'mediaUrl',
        'media-object-1',
        'mediaObjectIds'
      ]) {
        expect(stored.contains(part), isFalse, reason: '"$part" stored');
      }
      final read = (await cache.read(_alice))!.single;
      expect(read.mediaUrl, isNull);
      expect(read.mediaUrls, isEmpty);
      expect(read.mediaObjectIds, isEmpty);
    });

    test('a damaged entry counts as nothing saved', () async {
      await cache.write(_alice, [_offer('o0', _alice)]);
      await Hive.box<String>(OffersLocalCache.boxNameForUid(_alice))
          .put('offers_v2', '{not json');
      expect(await cache.read(_alice), isNull);
    });
  });

  group('encryption and keys', () {
    test(
        'the copy is encrypted on disk, its key only in secure storage, and '
        'it survives a restart', () async {
      await cache.write(_alice, [
        _offer('o1', _alice).copyWith(
          phoneNumber: '509876543',
          notes: 'SECRET-OFFER-NOTE',
          pickUpAddress: 'Hidden Villa 7',
        ),
      ]);
      await closeBox(_alice);

      final onDisk = latin1.decode(boxFile(_alice).readAsBytesSync());
      for (final secret in [
        '509876543',
        'SECRET-OFFER-NOTE',
        'Hidden Villa 7',
        'Marina',
        _alice,
      ]) {
        expect(onDisk.contains(secret), isFalse, reason: '"$secret" in clear');
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(base64.decode((await secureKey(_alice))!), hasLength(32));

      final read = (await cache.read(_alice))!.single;
      expect(read.notes, 'SECRET-OFFER-NOTE');
    });

    test('Offers and Requests keep separate keys and boxes', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      await const RequestsLocalCache().write(_alice, [
        RequestModel(
          id: 'r1',
          userId: _alice,
          requestType: 'rent',
          selectedCity: 'Dubai',
          selectedAreas: const [],
          location: '',
          phoneNumber: '',
          countryCode: '+971',
          minPrice: '',
          maxPrice: '',
          notes: '',
          specificPropertyType: '',
          rooms: 0,
          bathrooms: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]);
      final requestsKey = await const FlutterSecureStorage()
          .read(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      expect(requestsKey, isNotNull);
      expect(await secureKey(_alice), isNot(requestsKey));
      expect(OffersLocalCache.boxNameForUid(_alice),
          isNot(RequestsLocalCache.boxNameForUid(_alice)));
    });

    test(
        'with key storage unavailable nothing is read or written, and '
        'nothing is stored unencrypted', () async {
      final broken = OffersLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_offer('o1', _alice)]);
      expect(
          await Hive.boxExists(OffersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await broken.read(_alice), isNull);

      final offers = _Offers(currentUserId: () => signedIn, localCache: broken);
      final vm = openOffers(offers);
      await untilServerRead(offers);
      offers.server.addError(const SocketException('offline'));
      await offers.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue, reason: 'as before the cache existed');
    });

    test(
        'a box whose key went missing is never read, overwritten or given a '
        'new key', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage()
          .delete(key: SecureOffersCacheKeyStore.storageKeyFor(_alice));
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_offer('o2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      await closeBox(_alice);
      final otherKey = base64.encode(List<int>.generate(32, (i) => 7 * i));
      await const FlutterSecureStorage().write(
        key: SecureOffersCacheKeyStore.storageKeyFor(_alice),
        value: otherKey,
      );
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_offer('o2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });

    test('a corrupted box counts as nothing saved and is left unchanged',
        () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      await closeBox(_alice);
      final bytes = boxFile(_alice).readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] = bytes[i] ^ 0x5a;
      }
      boxFile(_alice).writeAsBytesSync(bytes);

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_offer('o2', _alice)]);
      expect(boxFile(_alice).readAsBytesSync(), bytes);
    });

    test('two first saves at once create one key and stay readable', () async {
      await Future.wait([
        cache.write(_alice, [_offer('o1', _alice)]),
        cache.write(_alice, [_offer('o2', _alice)]),
      ]);
      await closeBox(_alice);
      expect(_ids((await cache.read(_alice))!), ['o2']);
    });
  });

  group('account deletion', () {
    test(
        'removes the deleted account\'s Offers box and key, and no one '
        'else\'s', () async {
      await cache.write(_alice, [_offer('o1', _alice)]);
      await cache.write(_bob, [_offer('b1', _bob)]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(
          await Hive.boxExists(OffersLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_alice), isNull);
      expect(await secureKey(_bob), isNotNull);
      expect(_ids((await cache.read(_bob))!), ['b1']);
    });
  });
}
