// M2-2 (tracker §7AZ) measurement only: what saving `listedMediaObjectIds`
// in the encrypted Offers/Owners lists costs, on the desktop test VM.
//
// For 500 / 1,000 / 5,000 / 20,000 records with 0, 3 and 10 media ids each,
// against the same records saved by the M2-1 code (no field):
//   - payload bytes (the authenticated plaintext JSON) and the encrypted box
//     file size after one save;
//   - encode (the list's stored form, as `fingerprintOf`), save (encode +
//     tag + encrypted Hive write + read-back check) and cold read (decrypt +
//     tag check + JSON and record decode) in milliseconds, best of 3.
// Every step runs on the calling (main) isolate, as in the app. No network:
// M2-2 adds no request. Desktop numbers only — not Samsung, not iOS.
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _uid(int n) =>
    '${n.toString().padLeft(8, '0')}-1111-4111-8111-111111111111';

String _media(int n) =>
    'cccccccc-cccc-4ccc-8ccc-${n.toString().padLeft(12, '0')}';

String _record(int n) =>
    '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _at = DateTime.utc(2026, 3, 4, 5, 6, 7);

OfferModel _offer(String uid, int n, int ids) => OfferModel(
      id: _record(n),
      userId: uid,
      offerType: 'sell',
      selectedCity: 'Dubai',
      selectedAreas: const ['Dubai Marina', 'JBR'],
      location: 'Tower $n',
      phoneNumber: '50${n.toString().padLeft(7, '0')}',
      countryCode: '+971',
      minPrice: '1500000',
      maxPrice: '1700000',
      squareFootage: '1200',
      notes: 'Notes for record $n',
      propertyType: 'residential',
      specificPropertyType: 'apartment',
      rooms: 3,
      bathrooms: 2,
      pickUpLocation: 'Lobby',
      pickUpLatitude: 25.0772,
      pickUpLongitude: 55.1393,
      pickUpAddress: 'Marina Walk 1',
      uploadedFileName: '',
      status: PropertyStatus.available,
      createdAt: _at,
      updatedAt: _at,
      mediaUrls: const [],
      listedMediaObjectIds: [for (var i = 0; i < ids; i++) _media(n * 16 + i)],
    );

OwnerModel _owner(String uid, int n, int ids) => OwnerModel(
      id: _record(n),
      userId: uid,
      name: 'Owner $n',
      phoneNumber: '50${n.toString().padLeft(7, '0')}',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: 'Dubai Hills',
      notes: 'Notes for record $n',
      pickUpLocation: 'Gate',
      pickUpLatitude: 25.1,
      pickUpLongitude: 55.2,
      pickUpAddress: 'Hills 1',
      mediaUrls: const [],
      createdAt: _at,
      updatedAt: _at,
      listedMediaObjectIds: [for (var i = 0; i < ids; i++) _media(n * 16 + i)],
    );

/// The M2-1 record form (no media field): the baseline.
Map<String, Object?> _m21Offer(OfferModel o) {
  final m = Map<String, Object?>.from(
      (json.decode(const OffersLocalCache().fingerprintOf([o])) as List).single
          as Map);
  return m..remove('listedMediaObjectIds');
}

Map<String, Object?> _m21Owner(OwnerModel o) {
  final m = Map<String, Object?>.from(
      (json.decode(const OwnersLocalCache().fingerprintOf([o])) as List).single
          as Map);
  return m..remove('listedMediaObjectIds');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('m2_2_measure_');
    Hive.init(tempDir.path);
    EncryptedAccountListCache.debugStorageRoot = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('payload size and encode/save/read time (desktop VM)', () async {
    final lines = <String>[];
    var account = 0;

    Future<Map<String, num>> measure<T>(
      EncryptedAccountListCache<T> cache,
      String boxPrefix,
      List<T> Function(String uid) build, {
      bool readBack = true,
    }) async {
      final best = <String, int>{};
      late int payloadBytes;
      late int fileBytes;
      for (var round = 0; round < 3; round++) {
        final uid = _uid(++account);
        final items = build(uid);
        final encode = Stopwatch()..start();
        final payload = cache.fingerprintOf(items);
        encode.stop();
        payloadBytes = utf8.encode(payload).length;
        final save = Stopwatch()..start();
        await cache.write(uid, items);
        save.stop();
        final name = '$boxPrefix$uid';
        if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
        fileBytes = File('${tempDir.path}${Platform.pathSeparator}'
                '${EncryptedAccountListCache.directoryName}'
                '${Platform.pathSeparator}${name.toLowerCase()}.hive')
            .lengthSync();
        EncryptedAccountListCache.debugForgetProcessState();
        final read = Stopwatch()..start();
        if (readBack) {
          final back = await cache.read(uid);
          expect(back, hasLength(items.length));
        }
        read.stop();
        for (final (k, v) in [
          ('encode', encode.elapsedMilliseconds),
          ('save', save.elapsedMilliseconds),
          ('read', read.elapsedMilliseconds),
        ]) {
          best[k] = best[k] == null || v < best[k]! ? v : best[k]!;
        }
        await Hive.deleteBoxFromDisk(name,
            path: '${tempDir.path}${Platform.pathSeparator}'
                '${EncryptedAccountListCache.directoryName}');
      }
      return {...best, 'payload': payloadBytes, 'file': fileBytes};
    }

    for (final kind in ['offers', 'owners']) {
      for (final count in [500, 1000, 5000, 20000]) {
        final Map<String, num> base;
        if (kind == 'offers') {
          base = await measure<OfferModel>(
            EncryptedAccountListCache<OfferModel>(
              boxPrefix: 'cached_offers_',
              listKey: 'offers_v1',
              logName: 'M21',
              keyStore: const SecureOffersCacheKeyStore(),
              encode: _m21Offer,
              decode: (m) => throw UnimplementedError(),
              ownerOf: (o) => o.userId,
              idOf: (o) => o.id,
            ),
            'cached_offers_',
            (uid) => [for (var n = 1; n <= count; n++) _offer(uid, n, 0)],
            readBack: false,
          );
        } else {
          base = await measure<OwnerModel>(
            EncryptedAccountListCache<OwnerModel>(
              boxPrefix: 'cached_owners_',
              listKey: 'owners_v1',
              logName: 'M21',
              keyStore: const SecureOwnersCacheKeyStore(),
              encode: _m21Owner,
              decode: (m) => throw UnimplementedError(),
              ownerOf: (o) => o.userId,
              idOf: (o) => o.id,
            ),
            'cached_owners_',
            (uid) => [for (var n = 1; n <= count; n++) _owner(uid, n, 0)],
            readBack: false,
          );
        }
        lines.add('$kind n=$count M2-1 baseline: payload=${base['payload']} '
            'file=${base['file']} encodeMs=${base['encode']} '
            'saveMs=${base['save']}');
        for (final ids in [0, 3, 10]) {
          final r = kind == 'offers'
              ? await measure<OfferModel>(
                  const OffersLocalCache(),
                  'cached_offers_',
                  (uid) =>
                      [for (var n = 1; n <= count; n++) _offer(uid, n, ids)])
              : await measure<OwnerModel>(
                  const OwnersLocalCache(),
                  'cached_owners_',
                  (uid) =>
                      [for (var n = 1; n <= count; n++) _owner(uid, n, ids)]);
          final growth = (base['payload'] ?? 0) == 0
              ? 'n/a'
              : '${r['payload']! - base['payload']!}B '
                  '(${((r['payload']! - base['payload']!) / count).toStringAsFixed(0)}B/record, '
                  '+${((r['payload']! / base['payload']! - 1) * 100).toStringAsFixed(1)}%)';
          lines.add('$kind n=$count ids=$ids: payload=${r['payload']} '
              'file=${r['file']} growthVsM21=$growth '
              'encodeMs=${r['encode']} saveMs=${r['save']} readMs=${r['read']}');
        }
      }
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
