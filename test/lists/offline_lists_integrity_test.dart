// D-3: the offline lists' authentication tag (v2) and the S2 transition from
// the earlier untagged (v1) lists.
//
// Real Hive in a temporary documents directory and the secure-storage test
// store. Lists reach the cache through the real local-first stream, as a
// server list would.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
final _when = DateTime.utc(2026);

RequestModel _request(String id, [String owner = _alice]) => RequestModel(
      id: id,
      userId: owner,
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: '',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: 'note $id',
      specificPropertyType: '',
      rooms: 0,
      bathrooms: 0,
      createdAt: _when,
      updatedAt: _when,
    );

List<String?> _ids(List<RequestModel>? requests) =>
    requests?.map((r) => r.id).toList() ?? const ['<nothing>'];

class _Requests extends RequestService {
  _Requests({required super.currentUserId});
  final List<StreamController<List<RequestModel>>> reads = [];

  @override
  Stream<List<RequestModel>> getUserRequests() {
    final read = StreamController<List<RequestModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const cache = RequestsLocalCache();
  final aliceBoxName = RequestsLocalCache.boxNameForUid(_alice);
  String sep() => Platform.pathSeparator;
  File boxFile(String name) => File('${root.path}${sep()}'
      '${EncryptedAccountListCache.directoryName}${sep()}$name.hive');

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('offline_lists_integrity_test');
    Hive.init(root.path);
    EncryptedAccountListCache.debugStorageRoot = root.path;
  });

  tearDownAll(() async {
    await Hive.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final entity in root.listSync()) {
      for (var attempt = 0;; attempt++) {
        try {
          entity.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
  });

  Box<String> box(String name) => Hive.box<String>(name);

  Future<String?> secureKey(String storageKey) =>
      const FlutterSecureStorage().read(key: storageKey);

  /// A server list for Alice, through the Requests screen's local-first
  /// stream; waits until the save behind it has finished.
  Future<void> serverDelivers(List<RequestModel> list,
      {bool failInstead = false}) async {
    final requests = _Requests(currentUserId: () => _alice);
    final subscription =
        requests.watchUserRequestsLocalFirst().listen((_) {}, onError: (_) {});
    for (var i = 0; i < 400 && requests.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (failInstead) {
      requests.reads.single.addError(const SocketException('offline'));
    } else {
      requests.reads.single.add(list);
    }
    await pumpEventQueue();
    await cache.read(_alice);
    await subscription.cancel();
  }

  /// Alice's box as an earlier version left it: only the untagged v1 list.
  Future<void> earlierV1Box(List<RequestModel> list) async {
    await cache.write(_alice, list);
    final b = box(aliceBoxName);
    final payload = (json.decode(b.get('requests_v2')!) as Map)['p'] as String;
    await b.delete('requests_v2');
    await b.put('requests_v1', payload);
    await Hive.close();
  }

  Map<String, Object?> sealed(String boxName, String key) =>
      Map<String, Object?>.from(json.decode(box(boxName).get(key)!) as Map);

  String withTag(
      Map<String, Object?> envelope, List<int> Function(List<int>) f) {
    final tag = base64Url.decode(envelope['t']! as String);
    return json.encode({...envelope, 't': base64Url.encode(f(tag))});
  }

  // ---------------------------------------------------------------------
  group('the stored v2 list', () {
    test(
        'a server list is stored tagged under requests_v2, and no v1 list '
        'remains', () async {
      await serverDelivers([_request('s1')]);
      final b = box(aliceBoxName);
      expect(b.containsKey('requests_v1'), isFalse);
      final envelope = sealed(aliceBoxName, 'requests_v2');
      expect(envelope.keys.toSet(), {'v', 'p', 't'});
      expect(envelope['v'], 2);
      expect(base64Url.decode(envelope['t']! as String), hasLength(32));
      expect(_ids(await cache.read(_alice)), ['s1']);
    });

    test(
        'the tag is HMAC-SHA256 over the length-prefixed label, version, list, '
        'account and payload, under a key derived from the box key — never '
        'the box key itself', () async {
      await serverDelivers([_request('s1')]);
      final boxKey = base64.decode((await secureKey(
          SecureRequestsCacheKeyStore.storageKeyFor(_alice)))!);
      final envelope = sealed(aliceBoxName, 'requests_v2');
      final stored = base64Url.decode(envelope['t']! as String);

      List<int> part(List<int> bytes) => [
            ...(ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List(),
            ...bytes
          ];
      final covered = [
        ...part(utf8.encode('bw-offline-list')),
        ...part(utf8.encode('2')),
        ...part(utf8.encode('requests_v1')),
        ...part(utf8.encode(_alice)),
        ...part(utf8.encode(envelope['p']! as String)),
      ];
      final macKey = Hmac(sha256, boxKey)
          .convert(utf8.encode('broker_wallet/offline_lists/v2/mac'))
          .bytes;
      expect(stored, Hmac(sha256, macKey).convert(covered).bytes);
      expect(stored, isNot(Hmac(sha256, boxKey).convert(covered).bytes),
          reason: 'the box key is never the MAC key');
    });

    test('it reads back after every box is closed (a restart)', () async {
      await serverDelivers([_request('s1'), _request('s2')]);
      await Hive.close();
      expect(_ids(await cache.read(_alice)), ['s1', 's2']);
    });
  });

  group('anything not authentic reads as nothing', () {
    setUp(() async => serverDelivers([_request('a1')]));

    Future<void> expectNothing(String replacement, String why) async {
      await box(aliceBoxName).put('requests_v2', replacement);
      expect(await cache.read(_alice), isNull, reason: why);
    }

    test('a modified tag', () async {
      final envelope = sealed(aliceBoxName, 'requests_v2');
      await expectNothing(
          withTag(envelope, (t) => [...t]..[0] ^= 0x01), 'first tag byte');
      await expectNothing(
          withTag(envelope, (t) => [...t]..[31] ^= 0x80), 'last tag byte');
    });

    test('a modified payload, even a valid list of the same account', () async {
      final envelope = sealed(aliceBoxName, 'requests_v2');
      final forged = json.encode([
        {
          ...(json.decode(envelope['p']! as String) as List).single as Map,
          'id': 'forged'
        },
      ]);
      await expectNothing(
          json.encode({...envelope, 'p': forged}), 'payload changed');
    });

    test('malformed or incomplete v2 lists', () async {
      final envelope = sealed(aliceBoxName, 'requests_v2');
      final cases = <String, String>{
        'not JSON': '{not json',
        'a JSON list': '[]',
        'no tag': json.encode({'v': 2, 'p': envelope['p']}),
        'empty tag': json.encode({...envelope, 't': ''}),
        'tag not base64': json.encode({...envelope, 't': '!!!'}),
        'short tag': withTag(envelope, (t) => t.sublist(0, 16)),
        'long tag': withTag(envelope, (t) => [...t, 0]),
        'other version': json.encode({...envelope, 'v': 3}),
        'version as text': json.encode({...envelope, 'v': '2'}),
        'payload not text': json.encode({...envelope, 'p': 7}),
        'extra field': json.encode({...envelope, 'x': 1}),
      };
      for (final entry in cases.entries) {
        await expectNothing(entry.value, entry.key);
      }
    });

    test('a modified v2 list never falls back to an earlier v1 list', () async {
      final envelope = sealed(aliceBoxName, 'requests_v2');
      await box(aliceBoxName)
          .put('requests_v1', json.encode([_request('old').toJsonForTest()]));
      await expectNothing(
          withTag(envelope, (t) => [...t]..[5] ^= 0x10), 'tampered v2');
    });
  });

  group('a list bound to its account, its list and its key', () {
    test('a valid list of another account under the same key is rejected',
        () async {
      await serverDelivers([_request('a1')]);
      final aliceKey =
          await secureKey(SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      await const FlutterSecureStorage().write(
          key: SecureRequestsCacheKeyStore.storageKeyFor(_bob),
          value: aliceKey);
      await cache.write(_bob, [_request('b1', _bob)]);
      final bobBox = RequestsLocalCache.boxNameForUid(_bob);
      expect(_ids(await cache.read(_bob)), ['b1']);

      await box(bobBox)
          .put('requests_v2', box(aliceBoxName).get('requests_v2')!);
      expect(await cache.read(_bob), isNull,
          reason: 'same key, other account: the tag does not match');
    });

    test(
        'a valid list of another kind of list under the same key is '
        'rejected', () async {
      // An empty list decodes as any kind of list, so only the tag can
      // tell a Requests list from an Offers list here.
      await serverDelivers(const []);
      final key =
          await secureKey(SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      await const FlutterSecureStorage().write(
          key: SecureOffersCacheKeyStore.storageKeyFor(_alice), value: key);
      const offers = OffersLocalCache();
      await offers.write(_alice, []);
      final offersBox = OffersLocalCache.boxNameForUid(_alice);
      expect(await offers.read(_alice), isEmpty);

      await box(offersBox)
          .put('offers_v2', box(aliceBoxName).get('requests_v2')!);
      expect(await offers.read(_alice), isNull,
          reason: 'same key, same account, other list: no match');
    });

    test('a valid list made under an earlier key is rejected', () async {
      await serverDelivers([_request('a1')]);
      final earlier = box(aliceBoxName).get('requests_v2')!;
      await cache.forgetAccount(_alice); // box and key gone
      await serverDelivers([_request('a2')]); // a new key
      await box(aliceBoxName).put('requests_v2', earlier);
      expect(await cache.read(_alice), isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('S2: moving from v1 lists', () {
    test('an earlier v1 list stays readable, and reading it never tags it',
        () async {
      await earlierV1Box([_request('v1a'), _request('v1b')]);
      expect(_ids(await cache.read(_alice)), ['v1a', 'v1b']);
      expect(box(aliceBoxName).containsKey('requests_v2'), isFalse);
      await Hive.close();
      expect(_ids(await cache.read(_alice)), ['v1a', 'v1b']);
      expect(box(aliceBoxName).containsKey('requests_v2'), isFalse);
    });

    test('a failed server read keeps the v1 list readable and untagged',
        () async {
      await earlierV1Box([_request('v1a')]);
      await serverDelivers(const [], failInstead: true);
      expect(_ids(await cache.read(_alice)), ['v1a']);
      expect(box(aliceBoxName).containsKey('requests_v2'), isFalse);
    });

    test(
        'the first server list replaces v1 with v2 and v1 is removed, also '
        'after a restart', () async {
      await earlierV1Box([_request('v1a')]);
      await serverDelivers([_request('s1')]);
      expect(box(aliceBoxName).containsKey('requests_v1'), isFalse);
      expect(_ids(await cache.read(_alice)), ['s1']);
      await Hive.close();
      expect(_ids(await cache.read(_alice)), ['s1']);
      expect(box(aliceBoxName).containsKey('requests_v1'), isFalse);
    });

    test('an authoritative empty server list replaces v1 with an empty v2',
        () async {
      await earlierV1Box([_request('v1a')]);
      await serverDelivers(const []);
      expect(await cache.read(_alice), isEmpty);
      expect(box(aliceBoxName).containsKey('requests_v1'), isFalse);
    });

    test(
        'cut off after v2 was written but before v1 was removed: v2 is read, '
        'and the next server list removes v1', () async {
      await serverDelivers([_request('s1')]);
      await box(aliceBoxName)
          .put('requests_v1', json.encode([_request('v1a').toJsonForTest()]));
      await Hive.close();

      expect(_ids(await cache.read(_alice)), ['s1']);
      await serverDelivers([_request('s2')]);
      expect(box(aliceBoxName).containsKey('requests_v1'), isFalse);
      expect(_ids(await cache.read(_alice)), ['s2']);
    });
  });

  group('integrity failures and torn writes', () {
    test(
        'a list that fails its check is not reset by a write that did not '
        'come from a server list; a verified server list replaces it',
        () async {
      await serverDelivers([_request('a1')]);
      final envelope = sealed(aliceBoxName, 'requests_v2');
      final tampered = withTag(envelope, (t) => [...t]..[0] ^= 0x01);
      await box(aliceBoxName).put('requests_v2', tampered);

      await cache.write(_alice, [_request('x')]);
      expect(box(aliceBoxName).get('requests_v2'), tampered);
      expect(await cache.read(_alice), isNull);

      await serverDelivers([_request('s1')]);
      expect(_ids(await cache.read(_alice)), ['s1']);
    });

    test(
        'a write torn off at the end of the file is never read; the next '
        'verified server list recovers', () async {
      await serverDelivers([_request('a1')]);
      await Hive.close();
      final file = boxFile(aliceBoxName);
      final bytes = file.readAsBytesSync();
      // Half of a further frame: a length, then the write stops.
      file.writeAsBytesSync([...bytes, 200, 0, 0, 0, 1, 2, 3]);

      expect(await cache.read(_alice), isNull);
      await serverDelivers([_request('s1')]);
      await Hive.close();
      expect(_ids(await cache.read(_alice)), ['s1']);
    });
  });

  // ---------------------------------------------------------------------
  group('all six lists', () {
    test(
        'each stores a tagged v2 list that reads back, and each still reads '
        'its earlier v1 list', () async {
      final checks = <String, Future<void> Function()>{
        'requests': () => _roundTrip(
            const RequestsLocalCache(),
            'requests',
            RequestsLocalCache.boxNameForUid(_alice),
            [_request('r1')],
            (r) => r.id),
        'offers': () => _roundTrip(
            const OffersLocalCache(),
            'offers',
            OffersLocalCache.boxNameForUid(_alice),
            [
              OfferModel(
                id: 'o1',
                userId: _alice,
                offerType: 'sell',
                selectedCity: '',
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
                pickUpLocation: '',
                pickUpLatitude: null,
                pickUpLongitude: null,
                pickUpAddress: '',
                uploadedFileName: '',
                createdAt: _when,
                updatedAt: _when,
                mediaUrls: const [],
              ),
            ],
            (o) => o.id),
        'owners': () => _roundTrip(
            const OwnersLocalCache(),
            'owners',
            OwnersLocalCache.boxNameForUid(_alice),
            [
              OwnerModel(
                id: 'w1',
                userId: _alice,
                name: '',
                phoneNumber: '',
                countryCode: '+971',
                typeOfProperties: '',
                propertyLocation: '',
                notes: '',
                pickUpLocation: '',
                pickUpLatitude: null,
                pickUpLongitude: null,
                pickUpAddress: '',
                mediaUrls: const [],
                createdAt: _when,
                updatedAt: _when,
              ),
            ],
            (o) => o.id),
        'offices': () => _roundTrip(
            const OfficesLocalCache(),
            'offices',
            OfficesLocalCache.boxNameForUid(_alice),
            [
              OfficeModel(
                id: 'f1',
                userId: _alice,
                officeName: '',
                managerName: '',
                countryCode: '+971',
                phoneNumber: '',
                officeLocation: '',
                notes: '',
                pickUpLocation: '',
                pickUpAddress: '',
              ),
            ],
            (o) => o.id),
        'brokers': () => _roundTrip(
            const BrokersLocalCache(),
            'brokers',
            BrokersLocalCache.boxNameForUid(_alice),
            [
              BrokerModel(
                id: 'b1',
                userId: _alice,
                name: '',
                countryCode: '+971',
                phoneNumber: '',
                notes: '',
              ),
            ],
            (b) => b.id),
        'watchmen': () => _roundTrip(
            const WatchmenLocalCache(),
            'watchmen',
            WatchmenLocalCache.boxNameForUid(_alice),
            [
              WatchmenModel(
                id: 'm1',
                userId: _alice,
                name: '',
                countryCode: '+971',
                phoneNumber: '',
                buildingName: '',
                notes: '',
                buildingLocation: '',
                pickUpLocation: '',
                pickUpAddress: '',
              ),
            ],
            (w) => w.id),
      };
      for (final check in checks.entries) {
        await check.value();
      }
    });
  });
}

/// Writes [items], checks the stored v2 list and its read-back, then turns
/// the box into an earlier v1-only box and checks the read-back again.
Future<void> _roundTrip<T>(
  EncryptedAccountListCache<T> cache,
  String entity,
  String boxName,
  List<T> items,
  String? Function(T) idOf,
) async {
  final ids = items.map(idOf).toList();
  await cache.write(_alice, items);
  final b = Hive.box<String>(boxName);
  expect(b.containsKey('${entity}_v2'), isTrue, reason: entity);
  expect(b.containsKey('${entity}_v1'), isFalse, reason: entity);
  await Hive.close();
  expect((await cache.read(_alice))!.map(idOf).toList(), ids, reason: entity);

  final again = Hive.box<String>(boxName);
  final payload =
      (json.decode(again.get('${entity}_v2')!) as Map)['p'] as String;
  await again.delete('${entity}_v2');
  await again.put('${entity}_v1', payload);
  await Hive.close();
  expect((await cache.read(_alice))!.map(idOf).toList(), ids,
      reason: '$entity v1');
}

extension on RequestModel {
  /// The row shape the Requests cache stores, for planting a v1 list.
  Map<String, Object?> toJsonForTest() => {
        'id': id,
        'userId': userId,
        'requestType': requestType,
        'selectedCity': selectedCity,
        'selectedAreas': selectedAreas,
        'location': location,
        'phoneNumber': phoneNumber,
        'countryCode': countryCode,
        'minPrice': minPrice,
        'maxPrice': maxPrice,
        'squareFootage': squareFootage,
        'notes': notes,
        'propertyType': propertyType,
        'specificPropertyType': specificPropertyType,
        'rooms': rooms,
        'bathrooms': bathrooms,
        'status': status.toFirestoreString(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}
