// P2.5a: where the six offline lists live (D-1a) and how an unreadable one is
// recovered (D-2).
//
// Real Hive in a temporary documents directory, the secure-storage test
// store, and the real backup rule files of the Android app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
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
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

RequestModel _request(String id, [String owner = _alice]) => RequestModel(
      id: id,
      userId: owner,
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: 'Tower 1',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '1',
      maxPrice: '2',
      notes: 'note $id',
      specificPropertyType: 'apartment',
      rooms: 1,
      bathrooms: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

List<String?> _ids(List<RequestModel>? requests) =>
    requests?.map((r) => r.id).toList() ?? const ['<null>'];

/// A key store that answers from secure storage, but can be told to fail or
/// to give a scripted sequence of answers.
class _ScriptedKeys implements AccountCacheKeyStore {
  final _real = const SecureRequestsCacheKeyStore();
  final List<Object?> readScript = []; // null, List<int>, or an Exception
  bool failWrites = false;

  @override
  Future<List<int>?> read(String uid) async {
    if (readScript.isNotEmpty) {
      final next = readScript.removeAt(0);
      if (next is Exception) throw next;
      return next as List<int>?;
    }
    return _real.read(uid);
  }

  @override
  Future<void> write(String uid, List<int> key) async {
    if (failWrites) throw PlatformException(code: 'keystore-write');
    return _real.write(uid, key);
  }

  @override
  Future<void> delete(String uid) => _real.delete(uid);
}

/// A server that answers each subscription when the test says so.
class _Requests extends RequestService {
  _Requests({required super.currentUserId, super.localCache});
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
  final name = RequestsLocalCache.boxNameForUid(_alice);
  String sep() => Platform.pathSeparator;
  String lists() =>
      '${root.path}${sep()}${EncryptedAccountListCache.directoryName}';
  File inLists(String file) => File('${lists()}${sep()}$file');
  File inRoot(String file) => File('${root.path}${sep()}$file');
  File spare(String file) => File(
      '${lists()}${sep()}${EncryptedAccountListCache.recoveryDirectoryName}'
      '${sep()}$file');
  File aliceBox() => inLists('$name.hive');

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('offline_lists_storage_test');
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
    // Hive closes a box whose open failed without waiting (and then deletes
    // its lock file); let that finish before the files go.
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

  Future<String?> key(String uid) => const FlutterSecureStorage()
      .read(key: SecureRequestsCacheKeyStore.storageKeyFor(uid));

  Future<void> closeAll() => Hive.close();

  /// A box exactly as the earlier version left it: same name, same key, same
  /// format, directly in the documents directory.
  Future<List<int>> earlierBox(String uid, List<RequestModel> requests) async {
    await cache.write(uid, requests);
    await closeAll();
    final boxName = RequestsLocalCache.boxNameForUid(uid);
    final moved = inLists('$boxName.hive');
    final bytes = moved.readAsBytesSync();
    moved.renameSync(inRoot('$boxName.hive').path);
    return bytes;
  }

  /// Opens the Requests screen's list, delivers [server] once and waits for
  /// the save (or recovery) that follows to finish.
  Future<void> serverDelivers(
    List<RequestModel> server, {
    String? Function()? signedIn,
    RequestsLocalCache localCache = cache,
    bool failInstead = false,
  }) async {
    final requests = _Requests(
        currentUserId: signedIn ?? () => _alice, localCache: localCache);
    final subscription =
        requests.watchUserRequestsLocalFirst().listen((_) {}, onError: (_) {});
    for (var i = 0; i < 400 && requests.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (failInstead) {
      requests.reads.single.addError(const SocketException('offline'));
    } else {
      requests.reads.single.add(server);
    }
    await pumpEventQueue();
    // The save runs behind the list; a read waits its turn in the same queue.
    await localCache.read(_alice);
    await subscription.cancel();
  }

  // ---------------------------------------------------------------------
  group('D-1a: the lists directory', () {
    test('a new box is created in offline_lists, not the documents root',
        () async {
      await cache.write(_alice, [_request('a1')]);
      expect(aliceBox().existsSync(), isTrue);
      expect(inRoot('$name.hive').existsSync(), isFalse);
    });

    test('every one of the six caches keeps its box in offline_lists',
        () async {
      final when = DateTime.utc(2026);
      await const RequestsLocalCache().write(_alice, [_request('a1')]);
      await const OffersLocalCache().write(_alice, [
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
          createdAt: when,
          updatedAt: when,
          mediaUrls: const [],
        ),
      ]);
      await const OwnersLocalCache().write(_alice, [
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
          createdAt: when,
          updatedAt: when,
        ),
      ]);
      await const OfficesLocalCache().write(_alice, [
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
      ]);
      await const BrokersLocalCache().write(_alice, [
        BrokerModel(
          id: 'b1',
          userId: _alice,
          name: '',
          countryCode: '+971',
          phoneNumber: '',
          notes: '',
        ),
      ]);
      await const WatchmenLocalCache().write(_alice, [
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
      ]);
      for (final box in [
        RequestsLocalCache.boxNameForUid(_alice),
        OffersLocalCache.boxNameForUid(_alice),
        OwnersLocalCache.boxNameForUid(_alice),
        OfficesLocalCache.boxNameForUid(_alice),
        BrokersLocalCache.boxNameForUid(_alice),
        WatchmenLocalCache.boxNameForUid(_alice),
      ]) {
        expect(inLists('$box.hive').existsSync(), isTrue, reason: box);
        expect(inRoot('$box.hive').existsSync(), isFalse, reason: box);
      }
    });
  });

  group('D-1a: moving a box an earlier version kept in the root', () {
    test(
        'moves it untouched — same key, same bytes — and it survives a '
        'restart', () async {
      final bytes = await earlierBox(_alice, [_request('a1'), _request('a2')]);
      final keyBefore = await key(_alice);

      expect(_ids(await cache.read(_alice)), ['a1', 'a2']);
      expect(inRoot('$name.hive').existsSync(), isFalse);
      expect(aliceBox().readAsBytesSync(), bytes,
          reason: 'moved, not rewritten');
      expect(await key(_alice), keyBefore, reason: 'the same key');

      await closeAll();
      expect(_ids(await cache.read(_alice)), ['a1', 'a2']);
    });

    test('a move cut off after copying resumes, and the half copy goes',
        () async {
      final bytes = await earlierBox(_alice, [_request('a1')]);
      Directory(lists()).createSync(recursive: true);
      inLists('$name.hive.moving').writeAsBytesSync(bytes.sublist(0, 10));

      expect(_ids(await cache.read(_alice)), ['a1']);
      expect(inLists('$name.hive.moving').existsSync(), isFalse);
      expect(inRoot('$name.hive').existsSync(), isFalse);
      expect(aliceBox().readAsBytesSync(), bytes);
    });

    test('a move cut off before the earlier file was removed is finished',
        () async {
      final bytes = await earlierBox(_alice, [_request('a1')]);
      Directory(lists()).createSync(recursive: true);
      aliceBox().writeAsBytesSync(bytes); // copied, earlier not yet removed

      expect(_ids(await cache.read(_alice)), ['a1']);
      expect(inRoot('$name.hive').existsSync(), isFalse);
    });

    test(
        'when both copies exist and differ, the moved one is used and the '
        'earlier one is left alone', () async {
      final earlier = await earlierBox(_alice, [_request('old')]);
      await cache.write(_alice, [_request('new')]); // moves, then writes
      await closeAll();
      inRoot('$name.hive').writeAsBytesSync(earlier);

      expect(_ids(await cache.read(_alice)), ['new']);
      expect(inRoot('$name.hive').readAsBytesSync(), earlier);
    });

    test('an open box is never moved', () async {
      await earlierBox(_alice, [_request('a1')]);
      final keyBytes = base64.decode((await key(_alice))!);
      await Hive.openBox<String>(name,
          encryptionCipher: HiveAesCipher(keyBytes));

      await cache.read(_alice);
      expect(inRoot('$name.hive').existsSync(), isTrue);
      expect(aliceBox().existsSync(), isFalse);

      await closeAll();
      expect(_ids(await cache.read(_alice)), ['a1']);
      expect(inRoot('$name.hive').existsSync(), isFalse);
    });
  });

  group('D-1a: Android backup and device-transfer rules', () {
    final excluded =
        '<exclude domain="root" path="app_flutter/${EncryptedAccountListCache.directoryName}" />';
    const unchanged = [
      'app_flutter/offer_media"',
      'app_flutter/offer_media_uploads.hive"',
      'app_flutter/offer_media_uploads.lock"',
      'app_flutter/scanner"',
      'app_flutter/combine_pdfs"',
      'app_flutter/image_to_pdf"',
      'app_flutter/signature_pdfs"',
      'path="mlkit_docscan_ui_client"',
    ];
    String rules(String file) =>
        File('android/app/src/main/res/xml/$file').readAsStringSync();
    String section(String xml, String tag) {
      final start = xml.indexOf('<$tag>');
      final end = xml.indexOf('</$tag>');
      expect(start, isNonNegative, reason: tag);
      expect(end, greaterThan(start), reason: tag);
      return xml.substring(start, end);
    }

    test('Android 11 and below (full-backup-content) excludes the directory',
        () {
      final body = section(rules('backup_rules.xml'), 'full-backup-content');
      expect(excluded.allMatches(body), hasLength(1));
      for (final kept in unchanged) {
        expect(body.contains(kept), isTrue, reason: kept);
      }
    });

    test('Android 12+ cloud backup and device transfer both exclude it', () {
      final xml = rules('data_extraction_rules.xml');
      for (final tag in ['cloud-backup', 'device-transfer']) {
        final body = section(xml, tag);
        expect(excluded.allMatches(body), hasLength(1), reason: tag);
        for (final kept in unchanged) {
          expect(body.contains(kept), isTrue, reason: '$tag $kept');
        }
      }
    });

    test('the manifest still points at both rule files', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android:fullBackupContent="@xml/backup_rules"'),
          isTrue);
      expect(
          manifest.contains(
              'android:dataExtractionRules="@xml/data_extraction_rules"'),
          isTrue);
    });

    test('the excluded path is the directory the boxes are really written to',
        () async {
      // On Android `root` is the app's data directory and the documents
      // directory is `<data>/app_flutter`; here the documents directory is
      // this test's root, so the box must sit under <root>/offline_lists.
      await cache.write(_alice, [_request('a1')]);
      expect(aliceBox().parent.path, lists());
      expect(
          aliceBox()
              .parent
              .path
              .endsWith('${sep()}${EncryptedAccountListCache.directoryName}'),
          isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('D-2: recovery after a verified server list', () {
    test(
        'a key lost while the box is still open is recovered on the FIRST '
        'server list, and reads back after closing and a restart', () async {
      await cache.write(_alice, [_request('old')]);
      expect(Hive.isBoxOpen(name), isTrue, reason: 'the box stays open');
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));

      await serverDelivers([_request('s1'), _request('s2')]); // once

      expect(await key(_alice), isNotNull, reason: 'a new key, first time');
      expect(_ids(await cache.read(_alice)), ['s1', 's2']);
      expect(spare('$name.hive').existsSync(), isFalse);
      expect(spare('$name.hive.unreadable').existsSync(), isFalse);

      await Hive.box<String>(name).close();
      expect(_ids(await cache.read(_alice)), ['s1', 's2']);
      await closeAll(); // a restart
      expect(_ids(await cache.read(_alice)), ['s1', 's2']);
    });

    test(
        'a failed recovery of a box that was open leaves its encrypted '
        'file as it was and the other account untouched', () async {
      await cache.write(_bob, [_request('b1', _bob)]);
      await cache.write(_alice, [_request('old')]);
      expect(Hive.isBoxOpen(name), isTrue);
      final before = aliceBox().readAsBytesSync();
      final bobKey = await key(_bob);
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));

      final keys = _ScriptedKeys()..failWrites = true;
      await serverDelivers([_request('s1')],
          localCache: RequestsLocalCache(keyStore: keys));

      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
      expect(spare('$name.hive.unreadable').existsSync(), isFalse);
      expect(await key(_bob), bobKey);
      expect(_ids(await cache.read(_bob)), ['b1']);
    });

    test('a box whose key went missing is recovered with the server list',
        () async {
      await cache.write(_alice, [_request('old')]);
      await closeAll();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));

      await serverDelivers([_request('s1'), _request('s2')]);

      expect(await key(_alice), isNotNull, reason: 'a new key');
      await closeAll();
      expect(_ids(await cache.read(_alice)), ['s1', 's2']);
      expect(spare('$name.hive.unreadable').existsSync(), isFalse);
      expect(spare('$name.hive').existsSync(), isFalse);
    });

    test('a box under another key is recovered with the server list', () async {
      await cache.write(_alice, [_request('old')]);
      await closeAll();
      final other = base64.encode(List<int>.generate(32, (i) => i * 7));
      await const FlutterSecureStorage().write(
          key: SecureRequestsCacheKeyStore.storageKeyFor(_alice), value: other);

      await serverDelivers([_request('s1')]);

      expect(await key(_alice), isNot(other));
      await closeAll();
      expect(_ids(await cache.read(_alice)), ['s1']);
    });

    test('a damaged box is recovered with the server list', () async {
      await cache.write(_alice, [_request('old')]);
      await closeAll();
      final bytes = aliceBox().readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] ^= 0x5a;
      }
      aliceBox().writeAsBytesSync(bytes);

      await serverDelivers([_request('s1')]);

      await closeAll();
      expect(_ids(await cache.read(_alice)), ['s1']);
    });

    test('an authoritative empty server list recovers to an empty list',
        () async {
      await cache.write(_alice, [_request('old')]);
      await closeAll();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));

      await serverDelivers(const []);

      await closeAll();
      expect(await cache.read(_alice), isEmpty);
    });

    test('recovery touches only that account and that list', () async {
      await cache.write(_alice, [_request('old')]);
      await cache.write(_bob, [_request('b1', _bob)]);
      await const OwnersLocalCache().write(_alice, []);
      await closeAll();
      final bobBytes = inLists('${RequestsLocalCache.boxNameForUid(_bob)}.hive')
          .readAsBytesSync();
      final bobKey = await key(_bob);
      final ownersKey = await const FlutterSecureStorage()
          .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice));
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));

      await serverDelivers([_request('s1')]);

      expect(
          inLists('${RequestsLocalCache.boxNameForUid(_bob)}.hive')
              .readAsBytesSync(),
          bobBytes);
      expect(await key(_bob), bobKey);
      expect(
          await const FlutterSecureStorage()
              .read(key: SecureOwnersCacheKeyStore.storageKeyFor(_alice)),
          ownersKey);
      expect(_ids(await cache.read(_bob)), ['b1']);
    });
  });

  group('D-2: no recovery without a verified server list', () {
    Future<List<int>> keylessBox() async {
      await cache.write(_alice, [_request('old')]);
      await closeAll();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      return aliceBox().readAsBytesSync();
    }

    test('offline: a failed server read recovers nothing', () async {
      final before = await keylessBox();
      await serverDelivers(const [], failInstead: true);
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
    });

    test('a read never recovers', () async {
      final before = await keylessBox();
      expect(await cache.read(_alice), isNull);
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
    });

    test('a write that did not come from a server list recovers nothing',
        () async {
      final before = await keylessBox();
      await cache.write(_alice, [_request('x')]);
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
    });

    test('not after the signed-in account changed', () async {
      final before = await keylessBox();
      var calls = 0;
      // Signed in when the list is opened and delivered; changed when the
      // recovery asks.
      await serverDelivers([_request('s1')],
          signedIn: () => calls++ < 2 ? _alice : _bob);
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
    });

    test(
        'not on a transient key-store failure, at the write or at the '
        'second check; recovery still happens once storage answers', () async {
      final before = await keylessBox();
      // Key-store answers in order: the screen's read of the saved copy, the
      // write's key read, then the recovery's second check.
      for (final script in <List<Object?>>[
        [null, PlatformException(code: 'keystore-busy')],
        [null, null, PlatformException(code: 'keystore-busy')],
      ]) {
        final keys = _ScriptedKeys()..readScript.addAll(script);
        await serverDelivers([_request('s1')],
            localCache: RequestsLocalCache(keyStore: keys));
        expect(aliceBox().readAsBytesSync(), before, reason: '$script');
        expect(await key(_alice), isNull, reason: '$script');
      }

      await serverDelivers([_request('s1')]);
      await closeAll();
      expect(_ids(await cache.read(_alice)), ['s1']);
    });

    test('not when the unreadable state does not hold on the second check',
        () async {
      final before = await keylessBox();
      final keys = _ScriptedKeys();
      // The screen's read and the write see no key; the recovery's second
      // check sees a key that appeared meanwhile.
      keys.readScript
        ..add(null)
        ..add(null)
        ..add(List<int>.filled(32, 1));
      await serverDelivers([_request('s1')],
          localCache: RequestsLocalCache(keyStore: keys));
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
    });

    test('a recovery that cannot store the new key leaves the box as it was',
        () async {
      final before = await keylessBox();
      final keys = _ScriptedKeys()..failWrites = true;
      await serverDelivers([_request('s1')],
          localCache: RequestsLocalCache(keyStore: keys));
      expect(aliceBox().readAsBytesSync(), before);
      expect(await key(_alice), isNull);
      expect(spare('$name.hive.unreadable').existsSync(), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  group('account deletion and unrelated data', () {
    test(
        'Delete Account removes the moved box, an earlier-location box, '
        'recovery leftovers and the key — for that account only', () async {
      await cache.write(_alice, [_request('a1')]);
      await cache.write(_bob, [_request('b1', _bob)]);
      await closeAll();
      inRoot('$name.hive').writeAsBytesSync([1, 2, 3]);
      spare('$name.hive.unreadable').parent.createSync(recursive: true);
      spare('$name.hive.unreadable').writeAsBytesSync([4, 5, 6]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(aliceBox().existsSync(), isFalse);
      expect(inRoot('$name.hive').existsSync(), isFalse);
      expect(spare('$name.hive.unreadable').existsSync(), isFalse);
      expect(await key(_alice), isNull);
      expect(_ids(await cache.read(_bob)), ['b1']);
    });

    test('moving, recovering and deleting never touch unrelated files',
        () async {
      final unrelated = <File>[
        inRoot('offer_media_uploads.hive'),
        inRoot('cached_favorites_$_alice.hive'),
        File('${root.path}${sep()}offer_media${sep()}photo.jpg'),
        File('${root.path}${sep()}signature_pdfs${sep()}$_alice${sep()}a.pdf'),
        File('${root.path}${sep()}image_to_pdf${sep()}draft.pdf'),
      ];
      for (final file in unrelated) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('keep ${file.path}');
      }

      await earlierBox(_alice, [_request('a1')]);
      await cache.read(_alice); // move
      await closeAll();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      await serverDelivers([_request('s1')]); // recover
      await const RequestsLocalCache().forgetAccount(_alice); // delete

      for (final file in unrelated) {
        expect(file.readAsStringSync(), 'keep ${file.path}', reason: file.path);
      }
    });
  });
}
