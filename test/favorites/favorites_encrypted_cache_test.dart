// FU-FAV-CACHE-ENCRYPT: the saved Favorites copy is encrypted per account.
//
// Real FavoriteService, real Hive in a temporary directory (never the app's
// boxes), the real encrypted list cache and the secure-storage test store.
//
// Rules under test (owner-approved D1–D3):
//  * the encrypted copy is made only from a complete server answer, and is
//    read back and checked before the account's old plaintext copy goes;
//  * until then the old plaintext copy is shown read-only and is never
//    signed into the encrypted copy;
//  * once an encrypted copy exists, a damaged copy or a lost key never falls
//    back to plaintext;
//  * nothing stored is a link (no `imageUrl`), only stable media identity.
import 'dart:io';

import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/favorites_local_cache.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/views/Screens/home/favorites/favorite_card_media.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

FavoriteItem _item(
  String id, {
  String type = 'owners',
  String? imageUrl,
  FavoriteCardMedia? media,
  int day = 1,
}) =>
    FavoriteItem(
      id: id,
      type: type,
      title: 'Customer name $id',
      subtitle: 'Palm Jumeirah $id',
      imageUrl: imageUrl,
      media: media,
      addedAt: DateTime.utc(2026, 10, day, 8, 30),
    );

List<String> _ids(List<FavoriteItem> items) =>
    [for (final i in items) '${i.type}/${i.id}'];

/// Writes nothing: as a Keystore that cannot keep a new key.
class _ForgetfulKeys implements AccountCacheKeyStore {
  const _ForgetfulKeys();

  @override
  Future<List<int>?> read(String uid) async => null;

  @override
  Future<void> write(String uid, List<int> key) async {}

  @override
  Future<void> delete(String uid) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  File encryptedFile(String uid) =>
      File('${listsDir()}${Platform.pathSeparator}'
          '${FavoritesLocalCache.boxNameForUid(uid).toLowerCase()}.hive');
  const cache = FavoritesLocalCache();

  FavoriteService serviceFor(String? uid, {FavoritesLocalCache? local}) =>
      FavoriteService(localCache: local ?? cache)
        ..debugActiveUserIdOverride = uid;

  Future<void> seedPlaintext(String uid, List<FavoriteItem> items) async {
    final box = await Hive.openBox<CachedFavoriteItem>(
        FavoriteService.boxNameForUid(uid));
    await box.clear();
    await box.addAll([
      for (final i in items)
        CachedFavoriteItem(
          id: i.id,
          type: i.type,
          title: i.title,
          subtitle: i.subtitle,
          imageUrl: i.imageUrl,
          thumbnailUrl: i.imageUrl,
          addedAt: i.addedAt,
          cachedAt: DateTime.utc(2026, 10, 30),
          entityData: i.media?.toStored(),
        ),
    ]);
    await box.close();
  }

  Future<bool> plaintextExists(String uid) =>
      Hive.boxExists(FavoriteService.boxNameForUid(uid));

  /// As a process restart: nothing in memory, every box closed.
  Future<void> restart() async {
    FavoriteService.debugForgetSnapshots();
    EncryptedAccountListCache.debugForgetProcessState();
    for (final uid in [_alice, _bob]) {
      final encrypted = FavoritesLocalCache.boxNameForUid(uid);
      if (Hive.isBoxOpen(encrypted)) await Hive.box<String>(encrypted).close();
      final plaintext = FavoriteService.boxNameForUid(uid);
      if (Hive.isBoxOpen(plaintext)) {
        await Hive.box<CachedFavoriteItem>(plaintext).close();
      }
    }
  }

  Future<List<FavoriteItem>> openAs(String uid) async {
    final service = serviceFor(uid);
    await service.initializeCache(uidOverride: uid);
    return service.getCachedFavoritesSync();
  }

  Future<void> saveFromServer(String uid, List<FavoriteItem> items) =>
      serviceFor(uid).cacheFavorites(
        items,
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('favorites_encrypted_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(CachedFavoriteItemAdapter().typeId)) {
      Hive.registerAdapter(CachedFavoriteItemAdapter());
    }
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
  });

  tearDown(() async {
    await restart();
    for (final uid in [_alice, _bob]) {
      for (var attempt = 0;; attempt++) {
        try {
          await Hive.deleteBoxFromDisk(FavoritesLocalCache.boxNameForUid(uid),
              path: listsDir());
          await Hive.deleteBoxFromDisk(FavoriteService.boxNameForUid(uid));
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
  });

  group('the encrypted copy', () {
    test('a server answer is saved encrypted and survives a restart', () async {
      final key = offerMediaCacheKey(ownerId: _alice, mediaObjectId: 'm1')!;
      await saveFromServer(_alice, [
        _item('o2', day: 2),
        _item('f1',
            type: 'offers',
            media: FavoriteCardMedia(
                cacheKey: key, isVideo: true, signedUrl: 'https://x/?sig=1')),
      ]);

      expect(encryptedFile(_alice).existsSync(), isTrue);
      final bytes = encryptedFile(_alice).readAsBytesSync();
      expect(String.fromCharCodes(bytes), isNot(contains('Customer name')),
          reason: 'names are not readable on disk');
      expect(await plaintextExists(_alice), isFalse,
          reason: 'no plaintext copy is made');
      final secure = await const FlutterSecureStorage()
          .read(key: 'favorites_cache_key_v1_$_alice');
      expect(secure, isNotNull, reason: 'the key lives in secure storage');

      await restart();
      final restored = await openAs(_alice);

      expect(_ids(restored), ['owners/o2', 'offers/f1']);
      expect(restored.first.title, 'Customer name o2');
      expect(restored.first.subtitle, 'Palm Jumeirah o2');
      expect(restored.first.addedAt, DateTime.utc(2026, 10, 2, 8, 30));
      expect(restored.last.media!.cacheKey, key);
      expect(restored.last.media!.isVideo, isTrue);
      expect(restored.last.media!.signedUrl, isNull);
      expect(restored.every((i) => i.originalData == null), isTrue);
    });

    test('no link is ever stored: imageUrl is left out', () async {
      await saveFromServer(_alice, [
        _item('f1',
            type: 'offers',
            imageUrl: 'https://r2.example/o.jpg?X-Amz-Signature=abc'),
      ]);
      expect(
        FavoritesLocalCache.encodeRecord(StoredFavorite(
          account: _alice,
          id: 'f1',
          type: 'offers',
          title: 't',
          subtitle: 's',
          addedAt: DateTime.utc(2026),
        )).keys,
        unorderedEquals(
            ['account', 'id', 'type', 'title', 'subtitle', 'addedAt', 'media']),
      );

      await restart();
      expect((await openAs(_alice)).single.imageUrl, isNull);
    });

    test('a confirmed empty answer is saved as an empty list', () async {
      await saveFromServer(_alice, [_item('o1')]);
      await saveFromServer(_alice, const []);
      await restart();

      expect(await openAs(_alice), isEmpty);
      expect((await cache.readSaved(_alice))!.items, isEmpty,
          reason: 'saved empty, not missing');
    });

    test('a warm process shows the copy at once on a new screen', () async {
      await saveFromServer(_alice, [_item('o1')]);

      // A new screen builds a new service and reads before any await.
      expect(_ids(serviceFor(_alice).getCachedFavoritesSync()), ['owners/o1']);
      expect(serviceFor(_bob).getCachedFavoritesSync(), isEmpty);
    });

    test('a stale write (account changed since the read began) is dropped',
        () async {
      final before = FavoriteService.currentAccountGeneration;
      await FavoriteService.invalidateForAccountChange();
      await serviceFor(_alice)
          .cacheFavorites([_item('o1')], expectedGeneration: before);

      expect(encryptedFile(_alice).existsSync(), isFalse);
    });
  });

  group('accounts', () {
    test('another account never sees it, even after a restart', () async {
      await saveFromServer(_alice, [_item('a1')]);
      await saveFromServer(_bob, [_item('b1')]);
      await restart();

      expect(_ids(await openAs(_bob)), ['owners/b1']);
      expect(_ids(await openAs(_alice)), ['owners/a1']);
    });

    test('sign-out shows nothing; signing in again shows it again', () async {
      await saveFromServer(_alice, [_item('a1')]);
      await FavoriteService.invalidateForAccountChange();

      expect(serviceFor(null).getCachedFavoritesSync(), isEmpty);
      expect(serviceFor(_alice).getCachedFavoritesSync(), isEmpty,
          reason: 'memory is cleared at every account change');
      expect(_ids(await openAs(_alice)), ['owners/a1'],
          reason: 'the encrypted copy stays on the device, as the lists do');
    });

    test('Delete Account removes the encrypted copy, its key and plaintext',
        () async {
      await saveFromServer(_alice, [_item('a1')]);
      await seedPlaintext(_alice, [_item('old')]);
      await saveFromServer(_bob, [_item('b1')]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(encryptedFile(_alice).existsSync(), isFalse);
      expect(await plaintextExists(_alice), isFalse);
      expect(
          await const FlutterSecureStorage()
              .read(key: 'favorites_cache_key_v1_$_alice'),
          isNull);
      expect(serviceFor(_alice).getCachedFavoritesSync(), isEmpty);
      await restart();
      expect(_ids(await openAs(_bob)), ['owners/b1']);
    });
  });

  group('migration from the old plaintext copy (D1-A)', () {
    test('before any server answer the old copy is shown, read-only', () async {
      await seedPlaintext(_alice, [_item('old1', day: 3), _item('old2')]);

      final shown = await openAs(_alice);

      expect(_ids(shown), ['owners/old1', 'owners/old2']);
      expect(encryptedFile(_alice).existsSync(), isFalse,
          reason: 'reading never creates the encrypted copy');
      expect(await plaintextExists(_alice), isTrue);
    });

    test('old items are never signed into the encrypted copy', () async {
      await seedPlaintext(_alice, [_item('old1'), _item('old2')]);
      final service = serviceFor(_alice);
      await service.initializeCache(uidOverride: _alice);
      final shown = service.getCachedFavoritesSync();

      // A local removal while only the old copy exists creates nothing.
      await service.cacheFavoritesAfterRemoval(
        [shown.first],
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );
      expect(encryptedFile(_alice).existsSync(), isFalse);
      expect(await plaintextExists(_alice), isTrue);

      // A server answer that still carries an old on-screen item (one being
      // toggled when the answer arrived) saves only the server's items.
      await service.cacheFavorites(
        [shown.first, _item('fresh')],
        expectedGeneration: FavoriteService.currentAccountGeneration,
      );
      await restart();
      expect(_ids(await openAs(_alice)), ['owners/fresh']);
    });

    test('the first server answer replaces it; the old file is removed',
        () async {
      await seedPlaintext(_alice, [_item('old1')]);
      await openAs(_alice);

      await saveFromServer(_alice, [_item('fresh')]);

      expect(await plaintextExists(_alice), isFalse);
      await restart();
      expect(_ids(await openAs(_alice)), ['owners/fresh']);
    });

    test('an empty server answer migrates too', () async {
      await seedPlaintext(_alice, [_item('old1')]);
      await saveFromServer(_alice, const []);

      expect(await plaintextExists(_alice), isFalse);
      await restart();
      expect(await openAs(_alice), isEmpty);
    });

    test('a write that cannot be confirmed keeps the old copy', () async {
      await seedPlaintext(_alice, [_item('old1')]);
      final keyless = FavoriteService(
          localCache: const FavoritesLocalCache(keyStore: _ForgetfulKeys()))
        ..debugActiveUserIdOverride = _alice;

      await keyless.cacheFavorites([_item('fresh')],
          expectedGeneration: FavoriteService.currentAccountGeneration);

      expect(await plaintextExists(_alice), isTrue,
          reason: 'nothing is deleted before a checked encrypted copy');
      await restart();
      expect(_ids(await openAs(_alice)), ['owners/old1']);
    });

    test('a write the cache refused is not taken as confirmed', () async {
      await saveFromServer(_alice, [_item('kept')]);
      await seedPlaintext(_alice, [_item('leftover')]);
      // The cache refuses any list still holding a record whose deletion was
      // confirmed this run, and keeps the list it has.
      await cache.rememberConfirmedDeletion(_alice, 'owners:gone');

      await saveFromServer(_alice, [_item('gone'), _item('kept')]);

      expect(await plaintextExists(_alice), isTrue,
          reason: 'the copy read back is not the one written');
      expect(
          _ids(serviceFor(_alice).getCachedFavoritesSync()), ['owners/kept']);
    });

    test('an old file left by an interrupted clean-up goes at the next open',
        () async {
      await saveFromServer(_alice, [_item('fresh')]);
      await seedPlaintext(_alice, [_item('leftover')]);
      await restart();

      expect(_ids(await openAs(_alice)), ['owners/fresh'],
          reason: 'the encrypted copy wins');
      expect(await plaintextExists(_alice), isFalse);
    });

    test('another account\'s old file is left alone', () async {
      await seedPlaintext(_bob, [_item('b-old')]);
      await saveFromServer(_alice, [_item('a1')]);

      expect(await plaintextExists(_bob), isTrue);
    });
  });

  group('once an encrypted copy exists, never plaintext again', () {
    test('a lost key shows nothing, and the next server answer recovers',
        () async {
      await saveFromServer(_alice, [_item('fresh')]);
      await seedPlaintext(_alice, [_item('leftover')]);
      await restart();
      FlutterSecureStorage.setMockInitialValues({}); // the key is gone

      expect(await openAs(_alice), isEmpty);
      expect(await plaintextExists(_alice), isTrue,
          reason: 'not shown, and not deleted either');

      await saveFromServer(_alice, [_item('recovered')]);
      await restart();
      expect(_ids(await openAs(_alice)), ['owners/recovered']);
      expect(await plaintextExists(_alice), isFalse);
    });

    test('a recovery cut off between its renames does not fall back', () async {
      await saveFromServer(_alice, [_item('fresh')]);
      await seedPlaintext(_alice, [_item('leftover')]);
      await restart();
      // As `_recover` leaves it when killed after setting the unreadable box
      // aside and before moving the rebuilt one in: no box in the lists
      // directory, only files in its recovery directory.
      final spare = Directory('${listsDir()}${Platform.pathSeparator}'
          '${EncryptedAccountListCache.recoveryDirectoryName}')
        ..createSync(recursive: true);
      final name = encryptedFile(_alice).uri.pathSegments.last;
      encryptedFile(_alice)
          .renameSync('${spare.path}${Platform.pathSeparator}$name.unreadable');

      expect(await cache.hasSavedBox(_alice), isTrue);
      expect(await openAs(_alice), isEmpty);
      expect(await plaintextExists(_alice), isTrue);

      File('${spare.path}${Platform.pathSeparator}$name.unreadable')
          .deleteSync();
    });

    test('a damaged box shows nothing and does not fall back', () async {
      await saveFromServer(_alice, [_item('fresh')]);
      await seedPlaintext(_alice, [_item('leftover')]);
      await restart();
      encryptedFile(_alice)
          .writeAsBytesSync(List<int>.generate(512, (i) => (i * 37) % 256));

      expect(await openAs(_alice), isEmpty);
      expect(await plaintextExists(_alice), isTrue);
    });
  });

  group('backup (D3)', () {
    String rules(String name) =>
        File('android/app/src/main/res/xml/$name').readAsStringSync();
    const hive =
        '<exclude domain="root" path="app_flutter/cached_favorites.hive" />';
    const lock =
        '<exclude domain="root" path="app_flutter/cached_favorites.lock" />';

    test('the old shared box is excluded by its exact files, everywhere', () {
      final full = rules('backup_rules.xml');
      final android12 = rules('data_extraction_rules.xml');
      expect(hive.allMatches(full), hasLength(1));
      expect(lock.allMatches(full), hasLength(1));
      expect(hive.allMatches(android12), hasLength(2),
          reason: 'cloud backup and device transfer');
      expect(lock.allMatches(android12), hasLength(2));
      for (final xml in [full, android12]) {
        expect(xml, isNot(contains('path="app_flutter" ')));
        expect(xml, isNot(contains('path="app_flutter/" ')));
      }
    });

    test('the encrypted copy lives in the excluded lists directory', () async {
      await saveFromServer(_alice, [_item('a1')]);
      expect(encryptedFile(_alice).parent.path, listsDir());
    });
  });

  group('cost of the first read (MEASURED on this test VM, not a phone)', () {
    for (final count in [0, 100, 1000, 5000]) {
      test('$count favorites: encrypted vs old plaintext read', () async {
        final items = [for (var i = 0; i < count; i++) _item('i$i')];
        await saveFromServer(_alice, items);
        await seedPlaintext(_bob, items);
        await restart();

        final encrypted = Stopwatch()..start();
        final a = await openAs(_alice);
        encrypted.stop();
        final plaintext = Stopwatch()..start();
        final b = await openAs(_bob);
        plaintext.stop();

        expect(a, hasLength(count));
        expect(b, hasLength(count));
        debugPrint('[FavoritesCacheCost] $count favorites: encrypted '
            '${encrypted.elapsedMilliseconds} ms, plaintext '
            '${plaintext.elapsedMilliseconds} ms');
      });
    }
  });
}
