import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Covers removal of private Offer media from this device.
///
/// Keying a cache by the owner id proves one account cannot *display* another
/// account's photos. It says nothing about whether the bytes are still on the
/// device, which is a separate claim and the one these tests make: after an
/// account is deleted, or after media is removed server side, the image files
/// are actually gone — including the ones no catalogue names.
///
/// Everything here runs against a temporary directory through the service's
/// own test seams. No real device or production data is touched.
const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

const String _ownerA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const String _ownerB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

late Directory _root;
late Directory _docs;
late List<String> _forgotten;

Directory get _offerDir =>
    Directory('${_docs.path}/${OfflineMediaService.offerMediaDirectoryName}');

String _key(String owner, String mediaId) =>
    offerMediaCacheKey(ownerId: owner, mediaObjectId: mediaId)!;

/// The on-disk name an adopted original gets for [owner]/[mediaId].
String _originalName(String owner, String mediaId, {String ext = '.png'}) =>
    '${_key(owner, mediaId).replaceAll(':', '_')}$ext';

Future<File> _writeSource(String name) async {
  final file = File('${_root.path}/$name');
  await file.writeAsBytes(base64Decode(_onePixelPngBase64));
  return file;
}

/// Simulates an upload that was adopted: the picked file is copied into the
/// app-owned directory and mapped to its confirmed media identity.
Future<void> _adopt(String owner, String mediaId) async {
  final source = await _writeSource('picked-$owner-$mediaId.png');
  await OfflineMediaService.instance.adoptLocalFileForMediaId(
    _key(owner, mediaId),
    source.path,
    directoryName: OfflineMediaService.offerMediaDirectoryName,
  );
}

/// Simulates the Offer having been viewed, which is what writes a catalogue.
Future<void> _catalogue(String owner, String offerId, List<String> ids) =>
    OfflineMediaService.instance.writeOfferMediaCatalog(
      ownerId: owner,
      offerId: offerId,
      mediaObjectIds: ids,
    );

bool _originalExists(String owner, String mediaId) =>
    File('${_offerDir.path}/${_originalName(owner, mediaId)}').existsSync();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _root = await Directory.systemTemp.createTemp('offer_media_security');
    _docs = Directory('${_root.path}/documents')..createSync(recursive: true);
    Hive.init('${_root.path}/hive');
    OfflineMediaService.resolveDocumentsDirectory = () async => _docs;
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    await OfflineMediaService.instance.initialize();
  });

  setUp(() async {
    _forgotten = <String>[];
    OfflineMediaService.removeCachedBytes = (key) async {
      _forgotten.add(key);
    };
    OfflineMediaService.resolveDocumentsDirectory = () async => _docs;
    // A clean slate per test, using the service's own unscoped wipe. The
    // record is cleared afterwards so the wipe's own removals are not
    // mistaken for the behaviour under test.
    await OfflineMediaService.instance.forgetOfferMedia();
    _forgotten.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _root.delete(recursive: true);
    } catch (_) {
      // A temp directory left behind is harmless.
    }
  });

  group('S-1 account deletion removes private originals', () {
    test('A. an uploaded image that was viewed is removed entirely', () async {
      await _adopt(_ownerA, 'media-a');
      await _catalogue(_ownerA, 'offer-1', const ['media-a']);
      expect(_originalExists(_ownerA, 'media-a'), isTrue);

      final report =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(_originalExists(_ownerA, 'media-a'), isFalse);
      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerA, offerId: 'offer-1'),
        isEmpty,
      );
      expect(
        OfflineMediaService.instance
            .getLocalFilePathForMediaId(_key(_ownerA, 'media-a')),
        isNull,
      );
      expect(_forgotten, contains(_key(_ownerA, 'media-a')));
      expect(report.isComplete, isTrue);
    });

    test('B. an uploaded image never viewed is still removed', () async {
      // No catalogue is ever written, because the Offer was never opened.
      await _adopt(_ownerA, 'media-never-viewed');
      expect(_originalExists(_ownerA, 'media-never-viewed'), isTrue);

      final report =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(_originalExists(_ownerA, 'media-never-viewed'), isFalse,
          reason: 'a catalogue is not a complete inventory of originals');
      expect(report.originalsRemoved, 1);
      expect(report.isComplete, isTrue);
    });

    test('C. an orphan with no mapping and no catalogue is removed', () async {
      // A file left by a previous run: correct name, nothing referencing it.
      await _offerDir.create(recursive: true);
      final orphan = File('${_offerDir.path}/'
          '${_originalName(_ownerA, 'media-orphan')}');
      await orphan.writeAsBytes(base64Decode(_onePixelPngBase64));

      final report =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(orphan.existsSync(), isFalse);
      expect(report.isComplete, isTrue);
    });

    test('D. another account originals are never touched', () async {
      await _adopt(_ownerA, 'media-a');
      await _adopt(_ownerB, 'media-b');
      await _catalogue(_ownerA, 'offer-1', const ['media-a']);
      await _catalogue(_ownerB, 'offer-2', const ['media-b']);

      await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(_originalExists(_ownerA, 'media-a'), isFalse);
      expect(_originalExists(_ownerB, 'media-b'), isTrue,
          reason: 'cleanup is scoped by the owner id in the file name');
      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerB, offerId: 'offer-2'),
        ['media-b'],
      );
      expect(_forgotten, isNot(contains(_key(_ownerB, 'media-b'))));
    });

    test('a directory that matches the prefix is never deleted', () async {
      await _offerDir.create(recursive: true);
      final decoy = Directory(
        '${_offerDir.path}/${_originalName(_ownerA, 'looks-like-a-file')}',
      );
      await decoy.create();

      await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(decoy.existsSync(), isTrue,
          reason: 'only regular files are removed, never directories or links');
    });

    test('an unusable owner id sweeps nothing rather than everything',
        () async {
      await _adopt(_ownerA, 'media-a');

      final report =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: '::::');

      expect(_originalExists(_ownerA, 'media-a'), isTrue);
      expect(report.isComplete, isFalse,
          reason: 'a sweep that could not run must not report success');
    });

    test('E. repeating cleanup is idempotent and stays complete', () async {
      await _adopt(_ownerA, 'media-a');
      await _catalogue(_ownerA, 'offer-1', const ['media-a']);

      final first =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);
      final second =
          await OfflineMediaService.instance.forgetOfferMedia(ownerId: _ownerA);

      expect(first.isComplete, isTrue);
      expect(second.isComplete, isTrue);
      expect(second.originalsRemoved, 0);
      expect(second.catalogueEntriesRemoved, 0);
    });

    group('F. partial failure is reported, never hidden', () {
      test('a cache entry that will not delete fails the report', () async {
        await _adopt(_ownerA, 'media-a');
        await _catalogue(_ownerA, 'offer-1', const ['media-a']);
        OfflineMediaService.removeCachedBytes =
            (_) async => throw const FileSystemException('locked');

        final report = await OfflineMediaService.instance
            .forgetOfferMedia(ownerId: _ownerA);

        expect(report.failures, greaterThan(0));
        expect(report.isComplete, isFalse);
        // The rest still happened: one failure does not abort cleanup.
        expect(_originalExists(_ownerA, 'media-a'), isFalse);
      });

      test('a directory that cannot be read fails the report', () async {
        await _adopt(_ownerA, 'media-a');
        OfflineMediaService.resolveDocumentsDirectory =
            () async => throw const FileSystemException('unavailable');

        final report = await OfflineMediaService.instance
            .forgetOfferMedia(ownerId: _ownerA);

        expect(report.sweepCompleted, isFalse);
        expect(report.isComplete, isFalse,
            reason: 'orphans may remain, so success cannot be claimed');
      });
    });
  });

  group('S-3 media removed server side is removed locally', () {
    test('an id dropped from an authoritative response is cleaned up',
        () async {
      await _adopt(_ownerA, 'media-keep');
      await _adopt(_ownerA, 'media-drop');
      await _catalogue(_ownerA, 'offer-1', const ['media-keep', 'media-drop']);

      final report =
          await OfflineMediaService.instance.reconcileOfferMediaCatalog(
        ownerId: _ownerA,
        offerId: 'offer-1',
        mediaObjectIds: const ['media-keep'],
      );

      expect(_originalExists(_ownerA, 'media-drop'), isFalse);
      expect(_originalExists(_ownerA, 'media-keep'), isTrue);
      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerA, offerId: 'offer-1'),
        ['media-keep'],
      );
      expect(_forgotten, contains(_key(_ownerA, 'media-drop')));
      expect(_forgotten, isNot(contains(_key(_ownerA, 'media-keep'))));
      expect(report.originalsRemoved, 1);
    });

    test('display order is preserved when nothing was dropped', () async {
      await _catalogue(_ownerA, 'offer-1', const ['one', 'two', 'three']);

      await OfflineMediaService.instance.reconcileOfferMediaCatalog(
        ownerId: _ownerA,
        offerId: 'offer-1',
        mediaObjectIds: const ['one', 'two', 'three'],
      );

      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerA, offerId: 'offer-1'),
        ['one', 'two', 'three'],
      );
      expect(_forgotten, isEmpty);
    });

    test('an empty authoritative response removes everything for that Offer',
        () async {
      await _adopt(_ownerA, 'media-a');
      await _catalogue(_ownerA, 'offer-1', const ['media-a']);

      await OfflineMediaService.instance.reconcileOfferMediaCatalog(
        ownerId: _ownerA,
        offerId: 'offer-1',
        mediaObjectIds: const <String>[],
      );

      expect(_originalExists(_ownerA, 'media-a'), isFalse);
      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerA, offerId: 'offer-1'),
        isEmpty,
      );
    });

    test('one Offer reconciling never disturbs another Offer', () async {
      await _adopt(_ownerA, 'media-other');
      await _catalogue(_ownerA, 'offer-other', const ['media-other']);
      await _catalogue(_ownerA, 'offer-1', const ['media-x']);

      await OfflineMediaService.instance.reconcileOfferMediaCatalog(
        ownerId: _ownerA,
        offerId: 'offer-1',
        mediaObjectIds: const <String>[],
      );

      expect(_originalExists(_ownerA, 'media-other'), isTrue);
      expect(
        OfflineMediaService.instance
            .readOfferMediaCatalog(ownerId: _ownerA, offerId: 'offer-other'),
        ['media-other'],
      );
    });
  });

  group('removal reaches in-memory presentation state', () {
    test('a registered listener is told which identity was forgotten',
        () async {
      final seen = <String>[];
      void listener(String key) => seen.add(key);
      OfflineMediaService.addCacheKeyForgetListener(listener);
      addTearDown(
        () => OfflineMediaService.removeCacheKeyForgetListener(listener),
      );

      await OfflineMediaService.instance.forgetOfferMediaItems(
        ownerId: _ownerA,
        mediaObjectIds: const ['media-a'],
      );

      expect(seen, [_key(_ownerA, 'media-a')]);
    });

    test('a listener that throws never stops cleanup', () async {
      void bad(String key) => throw StateError('presentation cache failed');
      OfflineMediaService.addCacheKeyForgetListener(bad);
      addTearDown(() => OfflineMediaService.removeCacheKeyForgetListener(bad));

      await _adopt(_ownerA, 'media-a');
      final report = await OfflineMediaService.instance.forgetOfferMediaItems(
        ownerId: _ownerA,
        mediaObjectIds: const ['media-a'],
      );

      expect(_originalExists(_ownerA, 'media-a'), isFalse);
      expect(report.failures, 0);
    });

    test('forgetting items for an unknown account does nothing', () async {
      await _adopt(_ownerB, 'media-b');

      final report = await OfflineMediaService.instance.forgetOfferMediaItems(
        ownerId: '',
        mediaObjectIds: const ['media-b'],
      );

      expect(_originalExists(_ownerB, 'media-b'), isTrue);
      expect(report.originalsRemoved, 0);
    });
  });
}
