// M2-2 (tracker §7AZ): the encrypted Offers and Owners saved lists keep each
// record's trusted media identity, `listedMediaObjectIds`, inside the
// existing authenticated v2 payload — no new format, version, key or label.
//
// Stored as `"listedMediaObjectIds":[…]`: canonical lower-case UUIDs, in
// gallery order, each once. Anything else is written and read as `[]` for
// that record only; the record and the rest of the list are untouched. The
// field never holds a link, a path, a key or bytes, and the Offers
// `mediaObjectIds` (ids aligned with Worker signed links) is still never
// stored.
//
// "M2-1" below is a verbatim copy of the encoders/decoders before M2-2: the
// format and code of the builds already installed. Lists written with it are
// authentic v2 lists (same box, key and tag), so old → new and new → old are
// tested against the real earlier code, not a description of it.
//
// Real Hive in a temporary directory (never the app's boxes) and the
// secure-storage test store.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

String _media(int n) =>
    'cccccccc-cccc-4ccc-8ccc-${n.toString().padLeft(12, '0')}';

List<String> _ten() => [for (var i = 10; i >= 1; i--) _media(i)];

final _created = DateTime.utc(2026, 3, 4, 5, 6, 7);
final _updated = DateTime.utc(2026, 4, 5, 6, 7, 8);

// ---- M2-1 (before M2-2): verbatim copies -----------------------------------

Map<String, Object?> _m21EncodeOffer(OfferModel o) => {
      'id': o.id,
      'userId': o.userId,
      'offerType': o.offerType,
      'selectedCity': o.selectedCity,
      'selectedAreas': o.selectedAreas,
      'location': o.location,
      'phoneNumber': o.phoneNumber,
      'countryCode': o.countryCode,
      'minPrice': o.minPrice,
      'maxPrice': o.maxPrice,
      'squareFootage': o.squareFootage,
      'notes': o.notes,
      'propertyType': o.propertyType,
      'specificPropertyType': o.specificPropertyType,
      'rooms': o.rooms,
      'bathrooms': o.bathrooms,
      'pickUpLocation': o.pickUpLocation,
      'pickUpLatitude': o.pickUpLatitude,
      'pickUpLongitude': o.pickUpLongitude,
      'pickUpAddress': o.pickUpAddress,
      'uploadedFileName': o.uploadedFileName,
      'status': o.status.toFirestoreString(),
      'createdAt': o.createdAt.toUtc().toIso8601String(),
      'updatedAt': o.updatedAt.toUtc().toIso8601String(),
    };

OfferModel _m21DecodeOffer(Map<String, dynamic> m) => OfferModel(
      id: m['id'] as String?,
      userId: m['userId'] as String,
      offerType: m['offerType'] as String,
      selectedCity: m['selectedCity'] as String,
      selectedAreas: List<String>.from(m['selectedAreas'] as List),
      location: m['location'] as String,
      phoneNumber: m['phoneNumber'] as String,
      countryCode: m['countryCode'] as String,
      minPrice: m['minPrice'] as String,
      maxPrice: m['maxPrice'] as String,
      squareFootage: m['squareFootage'] as String,
      notes: m['notes'] as String,
      propertyType: m['propertyType'] as String?,
      specificPropertyType: m['specificPropertyType'] as String,
      rooms: m['rooms'] as int,
      bathrooms: m['bathrooms'] as int,
      pickUpLocation: m['pickUpLocation'] as String,
      pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
      pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
      pickUpAddress: m['pickUpAddress'] as String,
      uploadedFileName: m['uploadedFileName'] as String,
      mediaUrl: null,
      mediaUrls: const <String>[],
      status: PropertyStatus.fromString(m['status'] as String),
      createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
    );

Map<String, Object?> _m21EncodeOwner(OwnerModel o) => {
      'id': o.id,
      'userId': o.userId,
      'name': o.name,
      'phoneNumber': o.phoneNumber,
      'countryCode': o.countryCode,
      'typeOfProperties': o.typeOfProperties,
      'propertyLocation': o.propertyLocation,
      'notes': o.notes,
      'pickUpLocation': o.pickUpLocation,
      'pickUpLatitude': o.pickUpLatitude,
      'pickUpLongitude': o.pickUpLongitude,
      'pickUpAddress': o.pickUpAddress,
      'uploadedFileName': o.uploadedFileName,
      'createdAt': o.createdAt.toUtc().toIso8601String(),
      'updatedAt': o.updatedAt.toUtc().toIso8601String(),
    };

OwnerModel _m21DecodeOwner(Map<String, dynamic> m) => OwnerModel(
      id: m['id'] as String?,
      userId: m['userId'] as String,
      name: m['name'] as String,
      phoneNumber: m['phoneNumber'] as String,
      countryCode: m['countryCode'] as String,
      typeOfProperties: m['typeOfProperties'] as String,
      propertyLocation: m['propertyLocation'] as String,
      notes: m['notes'] as String,
      pickUpLocation: m['pickUpLocation'] as String,
      pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
      pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
      pickUpAddress: m['pickUpAddress'] as String,
      uploadedFileName: m['uploadedFileName'] as String?,
      mediaUrl: null,
      mediaUrls: const <String>[],
      createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
    );

// ---- Offers and Owners behind one test matrix ------------------------------

/// One saved list kind, with its real cache and the M2-1 code for it.
class _Kind<T> {
  _Kind({
    required this.name,
    required this.cache,
    required this.boxPrefix,
    required this.listKey,
    required this.keyStore,
    required this.make,
    required this.idsOf,
    required this.fieldsOf,
    required this.m21Encode,
    required this.m21Decode,
    required this.ownerOf,
    required this.idOf,
  });

  final String name;
  final EncryptedAccountListCache<T> cache;
  final String boxPrefix;
  final String listKey;
  final AccountCacheKeyStore keyStore;
  final T Function(String id, String owner, List<String> ids) make;
  final List<String> Function(T) idsOf;
  final List<Object?> Function(T) fieldsOf;
  final Map<String, Object?> Function(T) m21Encode;
  final T Function(Map<String, dynamic>) m21Decode;
  final String Function(T) ownerOf;
  final String? Function(T) idOf;

  String get v2Key => '${listKey.substring(0, listKey.length - 3)}_v2';

  /// The same box, key and list name with other record code: what an earlier
  /// (or a deliberately wrong) build would read and write.
  EncryptedAccountListCache<T> other({
    Map<String, Object?> Function(T)? encode,
    T Function(Map<String, dynamic>)? decode,
  }) =>
      EncryptedAccountListCache<T>(
        boxPrefix: boxPrefix,
        listKey: listKey,
        logName: 'TestCache',
        keyStore: keyStore,
        encode: encode ?? m21Encode,
        decode: decode ?? m21Decode,
        ownerOf: ownerOf,
        idOf: idOf,
      );

  /// The decrypted stored payload (the box is open with its key).
  String storedPayload(String uid) =>
      (json.decode(Hive.box<String>('$boxPrefix$uid').get(v2Key)!) as Map)['p']
          as String;

  List<Map<String, dynamic>> storedRows(String uid) => [
        for (final r in json.decode(storedPayload(uid)) as List)
          Map<String, dynamic>.from(r as Map)
      ];
}

OfferModel _offer(String id, String owner, List<String> ids) => OfferModel(
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
      notes: 'ملاحظة $id',
      propertyType: 'residential',
      specificPropertyType: 'apartment',
      rooms: 3,
      bathrooms: 2,
      pickUpLocation: 'Lobby',
      pickUpLatitude: 25.0772,
      pickUpLongitude: 55.1393,
      pickUpAddress: 'Marina Walk 1',
      uploadedFileName: '',
      status: PropertyStatus.sold,
      createdAt: _created,
      updatedAt: _updated,
      mediaUrls: const [],
      listedMediaObjectIds: ids,
    );

OwnerModel _owner(String id, String owner, List<String> ids) => OwnerModel(
      id: id,
      userId: owner,
      name: 'Owner $id',
      phoneNumber: '501234567',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: 'Dubai Hills',
      notes: 'ملاحظة $id',
      pickUpLocation: 'Gate',
      pickUpLatitude: null,
      pickUpLongitude: -0.000123456789,
      pickUpAddress: 'Hills 1',
      uploadedFileName: 'deed.pdf',
      mediaUrls: const [],
      createdAt: _created,
      updatedAt: _updated,
      listedMediaObjectIds: ids,
    );

List<Object?> _offerFields(OfferModel o) => [
      o.id, o.userId, o.offerType, o.selectedCity, o.selectedAreas, //
      o.location, o.phoneNumber, o.countryCode, o.minPrice, o.maxPrice,
      o.squareFootage, o.notes, o.propertyType, o.specificPropertyType,
      o.rooms, o.bathrooms, o.pickUpLocation, o.pickUpLatitude,
      o.pickUpLongitude, o.pickUpAddress, o.uploadedFileName, o.status,
      o.createdAt.toUtc(), o.updatedAt.toUtc(),
    ];

List<Object?> _ownerFields(OwnerModel o) => [
      o.id, o.userId, o.name, o.phoneNumber, o.countryCode, //
      o.typeOfProperties, o.propertyLocation, o.notes, o.pickUpLocation,
      o.pickUpLatitude, o.pickUpLongitude, o.pickUpAddress,
      o.uploadedFileName, o.createdAt.toUtc(), o.updatedAt.toUtc(),
    ];

final _offers = _Kind<OfferModel>(
  name: 'Offers',
  cache: const OffersLocalCache(),
  boxPrefix: 'cached_offers_',
  listKey: 'offers_v1',
  keyStore: const SecureOffersCacheKeyStore(),
  make: _offer,
  idsOf: (o) => o.listedMediaObjectIds,
  fieldsOf: _offerFields,
  m21Encode: _m21EncodeOffer,
  m21Decode: _m21DecodeOffer,
  ownerOf: (o) => o.userId,
  idOf: (o) => o.id,
);

final _owners = _Kind<OwnerModel>(
  name: 'Owners',
  cache: const OwnersLocalCache(),
  boxPrefix: 'cached_owners_',
  listKey: 'owners_v1',
  keyStore: const SecureOwnersCacheKeyStore(),
  make: _owner,
  idsOf: (o) => o.listedMediaObjectIds,
  fieldsOf: _ownerFields,
  m21Encode: _m21EncodeOwner,
  m21Decode: _m21DecodeOwner,
  ownerOf: (o) => o.userId,
  idOf: (o) => o.id,
);

// ---- Local-first services with a fake server --------------------------------

class _OfferServer extends OfferService {
  _OfferServer({required super.currentUserId});
  final List<StreamController<List<OfferModel>>> reads = [];
  @override
  Stream<List<OfferModel>> getUserOffers() {
    final read = StreamController<List<OfferModel>>();
    reads.add(read);
    return read.stream;
  }
}

class _OwnerServer extends OwnerService {
  _OwnerServer({required super.currentUserId});
  final List<StreamController<List<OwnerModel>>> reads = [];
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

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('m2_2_saved_ids_');
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
    EncryptedAccountListCache.debugForgetProcessState();
  });

  tearDown(() async {
    for (final prefix in ['cached_offers_', 'cached_owners_']) {
      for (final uid in [_alice, _bob]) {
        for (var attempt = 0;; attempt++) {
          try {
            await Hive.deleteBoxFromDisk('$prefix$uid', path: listsDir());
            break;
          } on FileSystemException {
            if (attempt == 20) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
      }
    }
  });

  Future<void> closeBox(String name) async {
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  void matrix<T>(_Kind<T> k) {
    group(k.name, () {
      final cache = k.cache;

      for (final (label, ids) in [
        ('zero', <String>[]),
        ('one', [_media(1)]),
        ('ten, in gallery order (not sorted)', _ten()),
      ]) {
        test('$label media ids: saved and read back exactly, in order',
            () async {
          final item = k.make('r1', _alice, ids);
          await cache.write(_alice, [item]);
          expect(k.storedRows(_alice).single['listedMediaObjectIds'], ids,
              reason: 'always written, [] included');
          await closeBox('${k.boxPrefix}$_alice');
          final read = (await cache.read(_alice))!.single;
          expect(k.idsOf(read), ids);
          expect(k.fieldsOf(read), k.fieldsOf(item),
              reason: 'every existing field kept');
        });
      }

      test('each record keeps its own ids; record order is unchanged',
          () async {
        final items = [
          k.make('r1', _alice, [_media(3), _media(1)]),
          k.make('r2', _alice, const []),
          k.make('r3', _alice, [_media(9)]),
        ];
        await cache.write(_alice, items);
        final read = (await cache.read(_alice))!;
        expect([for (final r in read) k.idOf(r)], ['r1', 'r2', 'r3']);
        expect([
          for (final r in read) k.idsOf(r)
        ], [
          [_media(3), _media(1)],
          <String>[],
          [_media(9)],
        ]);
      });

      test('an M2-1 list (no field) reads with every record and [] ids',
          () async {
        final items = [
          k.make('r1', _alice, [_media(1)]),
          k.make('r2', _alice, [_media(2)]),
        ];
        await k.other().write(_alice, items);
        expect(k.storedPayload(_alice), isNot(contains('listedMediaObjectIds')),
            reason: 'written by the M2-1 code');
        final read = (await cache.read(_alice))!;
        expect([for (final r in read) k.idOf(r)], ['r1', 'r2']);
        for (final r in read) {
          expect(k.idsOf(r), isEmpty);
        }
        expect(k.fieldsOf(read.first), k.fieldsOf(items.first));
      });

      test('the M2-1 decoder reads an M2-2 list unchanged', () async {
        final items = [
          k.make('r1', _alice, _ten()),
          k.make('r2', _alice, const []),
        ];
        await cache.write(_alice, items);
        await closeBox('${k.boxPrefix}$_alice');
        final old = (await k.other().read(_alice))!;
        expect([for (final r in old) k.idOf(r)], ['r1', 'r2'],
            reason: 'an older build keeps working after a rollback');
        expect(k.fieldsOf(old.first), k.fieldsOf(items.first));
        expect(k.idsOf(old.first), isEmpty,
            reason: 'the older build has no such field');
      });

      test('a malformed field reads as [] for that record only', () async {
        final bad = <String, Object?>{
          'b1': 'not-a-list',
          'b2': {'0': _media(1)},
          'b3': 42,
          'b4': null,
          'b5': [_media(1), 7],
          'b6': [_media(1).toUpperCase()],
          'b7': ['{${_media(1)}}'],
          'b8': ['https://r2.example.test/${_media(1)}.jpg?X-Amz-Signature=s'],
          'b9': [_media(1), _media(2), _media(1)],
          'b10': ['cccccccc-cccc-4ccc-8ccc-00000000001'],
          'b11': [''],
        };
        final rogue = k.other(
          encode: (item) => {
            ...k.m21Encode(item),
            'listedMediaObjectIds':
                bad[k.idOf(item)] ?? [for (final i in k.idsOf(item)) i],
          },
        );
        final items = [
          k.make('ok1', _alice, [_media(5), _media(4)]),
          for (final id in bad.keys) k.make(id, _alice, const []),
          k.make('ok2', _alice, [_media(6)]),
        ];
        await rogue.write(_alice, items);
        final read = (await cache.read(_alice))!;
        expect(read, hasLength(items.length),
            reason: 'no record is dropped for its media field');
        final byId = {for (final r in read) k.idOf(r): r};
        expect(k.idsOf(byId['ok1'] as T), [_media(5), _media(4)]);
        expect(k.idsOf(byId['ok2'] as T), [_media(6)]);
        for (final id in bad.keys) {
          expect(k.idsOf(byId[id] as T), isEmpty, reason: id);
          expect(k.fieldsOf(byId[id] as T),
              k.fieldsOf(k.make(id, _alice, const [])),
              reason: '$id: the record itself is intact');
        }
      });

      test('ids that are not canonical UUIDs are never written', () async {
        const signed =
            'https://r2.example.test/a/b.jpg?X-Amz-Signature=deadbeef';
        final items = [
          k.make('u1', _alice, const [signed]),
          k.make('u2', _alice, [_media(1).toUpperCase()]),
          k.make('u3', _alice, [_media(1), _media(1)]),
          k.make('u4', _alice, [_media(2), '/data/user/0/x/file.jpg']),
          k.make('u5', _alice, [_media(3)]),
        ];
        await cache.write(_alice, items);
        final stored = k.storedPayload(_alice);
        for (final part in [
          'X-Amz-Signature',
          'r2.example.test',
          'https',
          '/data/user',
          _media(1).toUpperCase(),
        ]) {
          expect(stored.contains(part), isFalse, reason: '"$part" stored');
        }
        final rows = {
          for (final r in k.storedRows(_alice))
            r['id']: r['listedMediaObjectIds']
        };
        expect(rows['u1'], isEmpty);
        expect(rows['u2'], isEmpty);
        expect(rows['u3'], isEmpty,
            reason: 'a repeated id: the field is wrong');
        expect(rows['u4'], isEmpty, reason: 'all or nothing, order kept');
        expect(rows['u5'], [_media(3)]);
      });

      test('another account\'s records and ids are never saved or read',
          () async {
        await cache.write(_alice, [
          k.make('a1', _alice, [_media(1)]),
          k.make('b1', _bob, [_media(2)]),
        ]);
        final stored = k.storedPayload(_alice);
        expect(stored.contains(_bob), isFalse);
        expect(stored.contains(_media(2)), isFalse);
        expect(await cache.read(_bob), isNull);
        expect(k.idsOf((await cache.read(_alice))!.single), [_media(1)]);
      });

      test('a list changed only in its ids is saved again', () async {
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)])
        ]);
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(2)])
        ]);
        expect(k.idsOf((await cache.read(_alice))!.single), [_media(2)]);
      });

      test('an edited media id fails the integrity check: nothing is read',
          () async {
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)])
        ]);
        final box = Hive.box<String>('${k.boxPrefix}$_alice');
        final envelope =
            Map<String, dynamic>.from(json.decode(box.get(k.v2Key)!) as Map);
        envelope['p'] =
            (envelope['p'] as String).replaceFirst(_media(1), _media(7));
        await box.put(k.v2Key, json.encode(envelope));
        EncryptedAccountListCache.debugForgetProcessState();
        expect(await cache.read(_alice), isNull);
        // And a save without a server read does not replace it.
        await cache.write(_alice, [
          k.make('r9', _alice, [_media(9)])
        ]);
        expect(await cache.read(_alice), isNull);
      });

      test('a lost key: nothing is read; only a server read recovers, ids kept',
          () async {
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)])
        ]);
        await closeBox('${k.boxPrefix}$_alice');
        await k.keyStore.delete(_alice);
        EncryptedAccountListCache.debugForgetProcessState();
        expect(await cache.read(_alice), isNull);
        await cache.write(_alice, [
          k.make('r2', _alice, [_media(2)])
        ]);
        expect(await cache.read(_alice), isNull,
            reason: 'no recovery without a server read');
        await cache.write(
            _alice,
            [
              k.make('r3', _alice, [_media(3)])
            ],
            mayRecover: () => true);
        final read = (await cache.read(_alice))!.single;
        expect(k.idOf(read), 'r3');
        expect(k.idsOf(read), [_media(3)]);
      });

      test('a confirmed deletion hides the record and blocks a stale save',
          () async {
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)]),
          k.make('r2', _alice, [_media(2)]),
        ]);
        await cache.rememberConfirmedDeletion(_alice, 'r1');
        final read = (await cache.read(_alice))!;
        expect([for (final r in read) k.idOf(r)], ['r2']);
        expect(k.idsOf(read.single), [_media(2)]);
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)]),
          k.make('r2', _alice, [_media(8)]),
        ]);
        expect(k.idsOf((await cache.read(_alice))!.single), [_media(2)],
            reason: 'a list still holding the deleted record is not saved');
      });

      test('a confirmed empty list is saved as empty, not as nothing',
          () async {
        await cache.write(_alice, [
          k.make('r1', _alice, [_media(1)])
        ]);
        await cache.write(_alice, const []);
        expect(await cache.read(_alice), isEmpty);
      });
    });
  }

  matrix(_offers);
  matrix(_owners);

  test('Offers: the Worker-aligned media fields are still never stored',
      () async {
    const signed = 'https://media.example.test/o1.jpg?X-Amz-Signature=deadbeef';
    final offer = _offer('o1', _alice, [_media(1)]).copyWith(
      mediaUrl: signed,
      mediaUrls: const [signed],
      mediaObjectIds: const ['media-object-1'],
    );
    await _offers.cache.write(_alice, [offer]);
    final stored = _offers.storedPayload(_alice);
    for (final part in [
      'X-Amz-Signature',
      'media.example.test',
      '"mediaUrl"',
      '"mediaUrls"',
      '"mediaObjectIds"',
      'media-object-1',
    ]) {
      expect(stored.contains(part), isFalse, reason: '"$part" stored');
    }
    final read = (await _offers.cache.read(_alice))!.single;
    expect(read.mediaUrl, isNull);
    expect(read.mediaUrls, isEmpty);
    expect(read.mediaObjectIds, isEmpty,
        reason: 'ids aligned with signed links are not the listed ids');
    expect(read.listedMediaObjectIds, [_media(1)]);
  });

  group('server reads (local-first)', () {
    Future<void> settle() async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    test('a complete server list is saved with its ids; a failure keeps them',
        () async {
      String? signedIn = _alice;
      final offers = _OfferServer(currentUserId: () => signedIn);
      final sub =
          offers.watchUserOffersLocalFirst().listen((_) {}, onError: (_) {});
      addTearDown(sub.cancel);
      await settle();
      offers.reads.single.add([
        _offer('o1', _alice, [_media(1), _media(2)])
      ]);
      await settle();
      await _offers.cache.debugSettled(_alice);
      expect((await _offers.cache.read(_alice))!.single.listedMediaObjectIds,
          [_media(1), _media(2)]);
      offers.reads.single.addError(const SocketException('offline'));
      await settle();
      expect((await _offers.cache.read(_alice))!.single.listedMediaObjectIds,
          [_media(1), _media(2)],
          reason: 'a failed read never changes the saved copy');
    });

    test('the saved ids are shown first, before the server answers', () async {
      await _owners.cache.write(_alice, [
        _owner('w1', _alice, [_media(4)])
      ]);
      final owners = _OwnerServer(currentUserId: () => _alice);
      final shown = <List<OwnerModel>>[];
      final sub =
          owners.watchUserOwnersLocalFirst().listen(shown.add, onError: (_) {});
      addTearDown(sub.cancel);
      await settle();
      expect(shown.first.single.listedMediaObjectIds, [_media(4)]);
    });

    test('nothing is saved once the account changed before the answer',
        () async {
      String? signedIn = _alice;
      final owners = _OwnerServer(currentUserId: () => signedIn);
      final sub =
          owners.watchUserOwnersLocalFirst().listen((_) {}, onError: (_) {});
      addTearDown(sub.cancel);
      await settle();
      signedIn = _bob;
      owners.reads.single.add([
        _owner('w1', _alice, [_media(1)])
      ]);
      await settle();
      expect(await _owners.cache.read(_alice), isNull);
      expect(await _owners.cache.read(_bob), isNull);
    });
  });

  test('Delete Account removes both boxes and keys with their ids', () async {
    await _offers.cache.write(_alice, [
      _offer('o1', _alice, [_media(1)])
    ]);
    await _owners.cache.write(_alice, [
      _owner('w1', _alice, [_media(2)])
    ]);
    await _offers.cache.write(_bob, [
      _offer('b1', _bob, [_media(3)])
    ]);
    await DeletedAccountLocalDataCleaner(
      forgetProfileMedia: ({mediaIds}) async {},
      forgetOfferMedia: ({ownerId}) async =>
          const OfferMediaCleanupReport.empty(),
      purgeOfferMediaUploads: (_) async => 0,
    ).clear(deletedUid: _alice, wasSignedInAccount: false);
    for (final prefix in ['cached_offers_', 'cached_owners_']) {
      expect(await Hive.boxExists('$prefix$_alice', path: listsDir()), isFalse,
          reason: prefix);
    }
    expect(await _offers.keyStore.read(_alice), isNull);
    expect(await _owners.keyStore.read(_alice), isNull);
    expect((await _offers.cache.read(_bob))!.single.listedMediaObjectIds,
        [_media(3)]);
  });
}
