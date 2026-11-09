// DA-MAP-1 (tracker §7AZ, D-DAM-1..3): Delete Account's media cleanup for
// one account, `OfflineMediaService.forgetOfferMedia(ownerId:)`.
//
//  * D-DAM-1: every `url_mapping` entry in that account's exact namespace
//    `mediaId::offer-media:<uid>:` is found — primary, `:poster` and M1d-2's
//    `::previous-copy` — even when no saved media catalogue names the item.
//  * D-DAM-2: for each item identified that way, the existing per-item
//    cleanup runs, which also removes its old-cache entry by its exact key.
//  * D-DAM-3: from the moment the cleanup starts, writes for that account
//    that were still in flight are refused, until a new application session
//    for the account begins (a deletion whose outcome was not known).
//
// Nothing outside that namespace is touched: other accounts, link-keyed and
// bare (profile) entries, the old catalogue-free `local_media` records.
import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The deleted account.
const _u = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

/// Another account on the same device.
const _v = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

/// An account id that differs from [_u] in its last character only.
const _near = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaab';

var _ids = 0;
String _media() =>
    'cccccccc-cccc-4ccc-8ccc-${(++_ids).toString().padLeft(12, '0')}';

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

void main() {
  late Directory documents;
  late Directory oldCacheDir;
  final offline = OfflineMediaService.instance;
  Box<dynamic> mappings() => Hive.box('url_mapping');
  Box<dynamic> catalogues() => Hive.box('local_media');

  /// The image cache used before M1c, by exact key.
  final oldCache = <String, File>{};
  final oldRemoved = <String>[];
  final privateRemoved = <String>[];
  final fetches = <String>[];
  Completer<void>? fetchGate;
  PrivateMediaScope? scope;

  File file(String name, [Directory? dir]) =>
      File('${(dir ?? oldCacheDir).path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [1, 2, 3]);

  /// An old-cache entry for [key] and a mapping naming it.
  Future<File> mapped(String key) async {
    final f = file('${key.hashCode.abs()}-${++_ids}.png');
    oldCache[key] = f;
    await offline.mapMediaIdToLocalFile(key, f.path);
    return f;
  }

  Map<dynamic, dynamic> snapshot(Box<dynamic> box) =>
      {for (final k in box.keys) k: box.get(k)};

  Map<dynamic, dynamic> entriesOf(Box<dynamic> box, String account) => {
        for (final k in box.keys)
          if (k is String && k.contains(account)) k: box.get(k),
      };

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('dam_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    await offline.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    oldCacheDir = Directory.systemTemp.createTempSync('dam_old_');
    if (!Hive.isBoxOpen('url_mapping')) await offline.initialize();
    await mappings().clear();
    await catalogues().clear();
    oldCache.clear();
    oldRemoved.clear();
    privateRemoved.clear();
    fetches.clear();
    fetchGate = null;
    scope = null; // Delete Account signs out before its cleaner runs
    OfflineMediaService.debugForgetDeletedAccounts();
    OfflineMediaService.sessionScope = () => scope;
    OfflineMediaService.removeCachedBytes = (key) async {
      oldRemoved.add(key);
      oldCache.remove(key)?.deleteSync();
    };
    OfflineMediaService.removePrivateBytes = (key) async {
      privateRemoved.add(key);
    };
    OfflineMediaService.fetchCachedBytes = (key, url) async {
      fetches.add('$key|$url');
      final gate = fetchGate;
      if (gate != null) await gate.future;
      if (url != null) oldCache[key] ??= file('dl-${++_ids}.png');
      return oldCache[key]?.path;
    };
  });

  tearDown(() {
    OfflineMediaService.debugForgetDeletedAccounts();
    OfflineMediaService.sessionScope = PrivateMediaCache.applicationScope;
    try {
      oldCacheDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ---------------------------------------------------------------------
  group('D-DAM-1/2: the deleted account\'s namespace is swept', () {
    test('a complete catalogue: removed as before', () async {
      final media = _media();
      final key = _key(_u, media);
      await offline.writeOfferMediaCatalog(
          ownerId: _u, offerId: _media(), mediaObjectIds: [media]);
      final old = await mapped(key);

      await offline.forgetOfferMedia(ownerId: _u);
      expect(offline.getLocalFilePathForMediaId(key), isNull);
      expect(oldRemoved, [key]);
      expect(old.existsSync(), isFalse, reason: 'its old-cache entry');
      expect(entriesOf(catalogues(), _u), isEmpty);
    });

    test('an item no catalogue names (known from a Worker answer only)',
        () async {
      final named = _media();
      final unnamed = _media();
      await offline.writeOfferMediaCatalog(
          ownerId: _u, offerId: _media(), mediaObjectIds: [named]);
      await mapped(_key(_u, named));
      final old = await mapped(_key(_u, unnamed)); // catalogue write was lost

      await offline.forgetOfferMedia(ownerId: _u);
      expect(entriesOf(mappings(), _u), isEmpty);
      expect(oldRemoved.toSet(), {_key(_u, named), _key(_u, unnamed)});
      expect(old.existsSync(), isFalse);
      expect(privateRemoved.toSet(), {_key(_u, named), _key(_u, unnamed)});
    });

    test('primary, poster and previous-copy entries, with no catalogue',
        () async {
      final media = _media();
      final key = _key(_u, media);
      final old = await mapped(key);
      final copy = file('private-${++_ids}.png');
      expect(
          await offline.replaceMediaIdMapping(key,
              expected: old.path, replacement: copy.path, previous: old.path),
          isTrue);
      final posterDir = Directory('${documents.path}${Platform.pathSeparator}'
          '${OfflineMediaService.offerMediaDirectoryName}')
        ..createSync(recursive: true);
      final poster = file('poster-${++_ids}.jpg', posterDir);
      await offline.mapMediaIdToLocalFile(
          offerMediaPosterKey(key), poster.path);
      expect(entriesOf(mappings(), _u), hasLength(3));

      await offline.forgetOfferMedia(ownerId: _u);
      expect(entriesOf(mappings(), _u), isEmpty);
      expect(oldRemoved, [key], reason: 'once, by the item\'s exact key');
      expect(poster.existsSync(), isFalse, reason: 'an adopted still frame');
      expect(copy.existsSync(), isTrue,
          reason: 'the private copy goes through forgetAccount, not by path');
    });

    test('a malformed entry in the namespace: only the entry goes', () async {
      final f1 = file('m1.png');
      final f2 = file('m2.png');
      final f3 = file('m3.png');
      await mappings().put('mediaId::offer-media:$_u:', f1.path);
      await mappings().put('mediaId::offer-media:$_u:a:b:c', f2.path);
      await mappings().put('mediaId::offer-media:$_u: spaced', f3.path);

      await offline.forgetOfferMedia(ownerId: _u);
      expect(entriesOf(mappings(), _u), isEmpty);
      expect(oldRemoved, isEmpty, reason: 'no item key could be proven');
      expect(privateRemoved, isEmpty);
      for (final f in [f1, f2, f3]) {
        expect(f.existsSync(), isTrue, reason: 'files are never taken by path');
      }
    });

    test('other accounts, near-identical ids and unscoped entries: untouched',
        () async {
      for (final account in [_v, _near]) {
        final media = _media();
        await offline.writeOfferMediaCatalog(
            ownerId: account, offerId: _media(), mediaObjectIds: [media]);
        await mapped(_key(account, media));
        await offline.mapMediaIdToLocalFile(
            offerMediaPosterKey(_key(account, media)), file('p.png').path);
      }
      // `u` followed by anything but the separator is another namespace.
      await mappings().put('mediaId::offer-media:${_u}0:m', file('x').path);
      await mappings()
          .put('mediaId::offer-media:${_u.toUpperCase()}:m', file('y').path);
      // Entries that name no account: a bare profile id, a link, a resized
      // copy's key, and an old `local_media` record.
      await offline.mapMediaIdToLocalFile('profile-photo-id', file('a').path);
      await offline.mapUrlToLocalFile(
          'https://firebasestorage.example/o/$_u.jpg', file('b').path);
      await offline.mapMediaIdToLocalFile(
          'resized_w100_h100_offer-media:$_u:m', file('c').path);
      await offline.storeLocalMediaData('doc-$_u', {'owner': _u});
      // The namespace appearing inside a key, not at its start.
      await mappings().put('legacy-mediaId::offer-media:$_u:m', file('d').path);
      final mappingsBefore = snapshot(mappings());
      final cataloguesBefore = snapshot(catalogues());
      await mapped(_key(_u, _media())); // the deleted account's own

      await offline.forgetOfferMedia(ownerId: _u);
      expect(snapshot(mappings()), mappingsBefore);
      expect(snapshot(catalogues()), cataloguesBefore);
      expect(oldRemoved.every((k) => k.startsWith('offer-media:$_u:')), isTrue);
    });

    test('an id that is not a canonical account id sweeps nothing more',
        () async {
      // Upper case, padded, with separators or empty: no namespace sweep.
      for (final owner in [_u.toUpperCase(), ' $_u', '::::', '', 'owner-x']) {
        await mappings().clear();
        await mapped(_key(_u, _media()));
        await offline.forgetOfferMedia(ownerId: owner);
        expect(entriesOf(mappings(), _u), hasLength(1), reason: owner);
      }
      // Even entries filed under such an id are not swept by namespace (only
      // a catalogue names them), and no writes for it are refused.
      for (final owner in ['owner-x', _u.toUpperCase()]) {
        final kept = 'offer-media:$owner:${_media()}';
        await mappings().put('mediaId::$kept', file('k').path);
        await offline.forgetOfferMedia(ownerId: owner);
        expect(offline.getLocalFilePathForMediaId(kept), isNotNull,
            reason: owner);
        final later = 'offer-media:$owner:${_media()}';
        await offline.mapMediaIdToLocalFile(later, file('l').path);
        expect(offline.getLocalFilePathForMediaId(later), isNotNull,
            reason: owner);
      }
    });

    test('repeating the cleanup is harmless and stays complete', () async {
      await mapped(_key(_u, _media()));
      await offline.forgetOfferMedia(ownerId: _u);
      final after = snapshot(mappings());
      await offline.forgetOfferMedia(ownerId: _u);
      await offline.forgetOfferMedia(ownerId: _u);
      expect(snapshot(mappings()), after);
      expect(entriesOf(mappings(), _u), isEmpty);
    });

    test('a failing old-cache removal is reported; mappings still go',
        () async {
      await mapped(_key(_u, _media()));
      OfflineMediaService.removeCachedBytes =
          (_) async => throw const FileSystemException('locked');
      final report = await offline.forgetOfferMedia(ownerId: _u);
      expect(report.failures, greaterThan(0));
      expect(entriesOf(mappings(), _u), isEmpty);
    });

    test('a Hive error is reported, never thrown, and a retry completes',
        () async {
      await mapped(_key(_u, _media()));
      await mappings().close();
      addTearDown(() async {
        if (!Hive.isBoxOpen('url_mapping')) await offline.initialize();
      });
      final report = await offline.forgetOfferMedia(ownerId: _u);
      expect(report.failures, greaterThan(0));
      await offline.initialize(); // reopened, as on the next start
      expect(entriesOf(mappings(), _u), hasLength(1), reason: 'left as it was');
      await offline.forgetOfferMedia(ownerId: _u);
      expect(entriesOf(mappings(), _u), isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  group('D-DAM-3: late writes cannot bring anything back', () {
    test('mapping, switch and catalogue writes are refused afterwards',
        () async {
      final media = _media();
      final key = _key(_u, media);
      await offline.forgetOfferMedia(ownerId: _u);

      await offline.mapMediaIdToLocalFile(key, file('late.png').path);
      expect(
          await offline.replaceMediaIdMapping(key,
              expected: 'x', replacement: file('c').path, previous: 'x'),
          isFalse);
      await offline.writeOfferMediaCatalog(
          ownerId: _u, offerId: _media(), mediaObjectIds: [media]);
      await offline.appendToOfferMediaCatalog(
          ownerId: _u, offerId: _media(), mediaObjectId: media);
      expect(entriesOf(mappings(), _u), isEmpty);
      expect(entriesOf(catalogues(), _u), isEmpty);
    });

    test('a card asking afterwards downloads nothing', () async {
      await offline.forgetOfferMedia(ownerId: _u);
      expect(
          await offline.ensureMediaIdCached(
              cacheKey: _key(_u, _media()), url: 'https://r2.example/x'),
          isNull);
      expect(fetches, isEmpty);
      expect(entriesOf(mappings(), _u), isEmpty);
    });

    test('a download in flight during the cleanup: no mapping, entry removed',
        () async {
      final key = _key(_u, _media());
      fetchGate = Completer<void>();
      final late =
          offline.ensureMediaIdCached(cacheKey: key, url: 'https://r2/x');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await offline.forgetOfferMedia(ownerId: _u);
      fetchGate!.complete(); // the download lands after the cleanup
      expect(await late, isNull);
      expect(entriesOf(mappings(), _u), isEmpty);
      expect(oldCache.containsKey(key), isFalse,
          reason: 'its old-cache entry is removed by exact key');
      expect(oldRemoved, contains(key));
    });

    test('a write landing while the sweep runs is refused', () async {
      final first = _key(_u, _media());
      final second = _key(_u, _media());
      await mapped(first);
      OfflineMediaService.removeCachedBytes = (key) async {
        oldRemoved.add(key);
        // Something still running for the account writes meanwhile.
        await offline.mapMediaIdToLocalFile(second, file('mid.png').path);
      };
      await offline.forgetOfferMedia(ownerId: _u);
      expect(entriesOf(mappings(), _u), isEmpty);
    });

    test('a late adoption copies nothing and maps nothing', () async {
      final key = _key(_u, _media());
      final picked = file('picked.jpg');
      final gate = Completer<void>();
      var calls = 0;
      OfflineMediaService.resolveDocumentsDirectory = () async {
        // The adoption's call waits, so it is under way during the cleanup;
        // the cleanup's own sweep of originals does not.
        if (++calls == 1) await gate.future;
        return documents;
      };
      addTearDown(() => OfflineMediaService.resolveDocumentsDirectory =
          () async => documents);
      final adoption = offline.adoptLocalFileForMediaId(key, picked.path,
          directoryName: OfflineMediaService.offerMediaDirectoryName);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await offline.forgetOfferMedia(ownerId: _u);
      gate.complete();
      await adoption;
      expect(entriesOf(mappings(), _u), isEmpty);
      final dir = Directory('${documents.path}${Platform.pathSeparator}'
          '${OfflineMediaService.offerMediaDirectoryName}');
      final left = dir.existsSync()
          ? dir.listSync().whereType<File>().where((f) => f.path.contains(_u))
          : const <File>[];
      expect(left, isEmpty, reason: 'its copy is removed, not left behind');
      expect(picked.existsSync(), isTrue, reason: 'the picked file is kept');

      // And one that starts after the cleanup does nothing at all.
      await offline.adoptLocalFileForMediaId(key, picked.path,
          directoryName: OfflineMediaService.offerMediaDirectoryName);
      expect(entriesOf(mappings(), _u), isEmpty);
    });

    test('another account keeps writing normally', () async {
      scope = const PrivateMediaScope(account: _v, session: 'v-1');
      await offline.forgetOfferMedia(ownerId: _u);
      final key = _key(_v, _media());
      await offline.mapMediaIdToLocalFile(key, file('v.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNotNull);
      expect(
          await offline.ensureMediaIdCached(
              cacheKey: _key(_v, _media()), url: 'https://r2/v'),
          isNotNull);
      // Another account being signed in is no new session for the deleted one.
      final deleted = _key(_u, _media());
      await offline.mapMediaIdToLocalFile(deleted, file('u.png').path);
      expect(offline.getLocalFilePathForMediaId(deleted), isNull);
    });

    test('the compare-and-set switch is refused too', () async {
      final key = _key(_u, _media());
      await offline.forgetOfferMedia(ownerId: _u);
      // A mapping that got there by some other way than this service.
      final stray = file('stray.png');
      await mappings().put('mediaId::$key', stray.path);
      expect(
          await offline.replaceMediaIdMapping(key,
              expected: stray.path,
              replacement: file('copy.png').path,
              previous: stray.path),
          isFalse);
      expect(offline.getLocalFilePathForMediaId(key), stray.path);
      expect(offline.previousCopyPathForMediaId(key), isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('a deletion whose outcome was not known', () {
    test('a new application session for the account lifts the guard', () async {
      await offline.forgetOfferMedia(ownerId: _u);
      final key = _key(_u, _media());
      await offline.mapMediaIdToLocalFile(key, file('a.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNull);

      scope = const PrivateMediaScope(account: _u, session: 'u-new');
      await offline.mapMediaIdToLocalFile(key, file('b.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNotNull);
    });

    test('the session current at cleanup time stays refused', () async {
      // The sign-out had not reached the media layer yet.
      scope = const PrivateMediaScope(account: _u, session: 'u-old');
      await offline.forgetOfferMedia(ownerId: _u);
      final key = _key(_u, _media());
      await offline.mapMediaIdToLocalFile(key, file('a.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNull,
          reason: 'the same account and session is not a new sign-in');

      scope = const PrivateMediaScope(account: _u, session: 'u-new');
      await offline.mapMediaIdToLocalFile(key, file('b.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNotNull);
    });

    test('a signed-out state never lifts it', () async {
      await offline.forgetOfferMedia(ownerId: _u);
      scope = const PrivateMediaScope(account: _v, session: 'v-1');
      scope = null;
      final key = _key(_u, _media());
      await offline.mapMediaIdToLocalFile(key, file('a.png').path);
      expect(offline.getLocalFilePathForMediaId(key), isNull);
    });
  });
}
