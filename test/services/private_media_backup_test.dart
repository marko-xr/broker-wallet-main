// M0.5 (tracker §7AZ, D-M1): the private media this device keeps and the
// indexes that describe it stay out of new backups where the platform allows.
//
// Verified locations (Android paths; iOS in brackets):
//  * Hive boxes `url_mapping` and `local_media` — `Hive.initFlutter()` with no
//    sub-folder, so getApplicationDocumentsDirectory: app_flutter/<name>.hive,
//    .lock, and .hivec while compacting [Documents].
//  * profile_media — OfflineMediaService.adoptLocalFileForMediaId's default
//    folder under the same Documents directory [Documents/profile_media].
//  * The image-cache index — flutter_cache_manager's CacheObjectProvider on
//    Android/iOS: getApplicationSupportDirectory()/libCachedImageData.db
//    (Android files/, backup domain "file") [Library/Application Support],
//    with sqflite's -journal (WAL off by default; -wal/-shm listed too).
//  * M1b: the private image cache's own index, bwPrivateMedia.db, in the same
//    folder (its bytes are in the temporary folder, never backed up).
// Nothing here is moved, cleared, encrypted or deleted.
import 'dart:io';

import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_backup_exclusions.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _Guard implements ScannerBackupGuard {
  final List<String> excluded = [];
  @override
  Future<bool> exclude(String path) async {
    excluded.add(path);
    return true;
  }
}

String _sep(List<String> parts) => parts.join(Platform.pathSeparator);

/// Every exclusion the rules held before M0.5 (domain, path).
const _earlier = [
  ('root', 'app_flutter/offer_media'),
  ('root', 'app_flutter/offer_media_uploads.hive'),
  ('root', 'app_flutter/offer_media_uploads.lock'),
  ('root', 'app_flutter/scanner'),
  ('file', 'mlkit_docscan_ui_client'),
  ('root', 'app_flutter/combine_pdfs'),
  ('root', 'app_flutter/image_to_pdf'),
  ('root', 'app_flutter/signature_pdfs'),
  ('root', 'app_flutter/offline_lists'),
  ('root', 'app_flutter/quotation_pdfs'),
  ('root', 'app_flutter/cached_favorites.hive'),
  ('root', 'app_flutter/cached_favorites.lock'),
];

/// What M0.5 adds (domain, path).
const _added = [
  ('root', 'app_flutter/profile_media'),
  ('root', 'app_flutter/url_mapping.hive'),
  ('root', 'app_flutter/url_mapping.hivec'),
  ('root', 'app_flutter/url_mapping.lock'),
  ('root', 'app_flutter/local_media.hive'),
  ('root', 'app_flutter/local_media.hivec'),
  ('root', 'app_flutter/local_media.lock'),
  ('file', 'libCachedImageData.db'),
  ('file', 'libCachedImageData.db-journal'),
  ('file', 'libCachedImageData.db-wal'),
  ('file', 'libCachedImageData.db-shm'),
];

/// What M1b adds (domain, path): the private image cache's index.
const _m1b = [
  ('file', 'bwPrivateMedia.db'),
  ('file', 'bwPrivateMedia.db-journal'),
  ('file', 'bwPrivateMedia.db-wal'),
  ('file', 'bwPrivateMedia.db-shm'),
];

List<String> _sections(String xml, String tag) => [
      for (final m
          in RegExp('<$tag>(.*?)</$tag>', dotAll: true).allMatches(xml))
        m.group(1)!
    ];

List<(String, String)> _excludes(String section) => [
      for (final m in RegExp(r'<exclude domain="([a-z]+)" path="([^"]+)" />')
          .allMatches(section))
        (m.group(1)!, m.group(2)!)
    ];

void main() {
  group('Android backup rules', () {
    void expectRules(String section, String where) {
      final rules = _excludes(section);
      for (final rule in [..._earlier, ..._added, ..._m1b]) {
        expect(rules, contains(rule), reason: '$where: $rule');
      }
      expect(rules, hasLength(_earlier.length + _added.length + _m1b.length),
          reason: '$where: nothing else added or broadened');
    }

    test('Auto Backup (Android ≤ 11) leaves the private media out', () {
      final xml = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      final full = _sections(xml, 'full-backup-content');
      expect(full, hasLength(1));
      expectRules(full.single, 'full-backup-content');
    });

    test('cloud backup and device transfer (Android 12+) leave it out', () {
      final xml = File('android/app/src/main/res/xml/data_extraction_rules.xml')
          .readAsStringSync();
      for (final tag in ['cloud-backup', 'device-transfer']) {
        final sections = _sections(xml, tag);
        expect(sections, hasLength(1), reason: tag);
        expectRules(sections.single, tag);
      }
    });

    test('nothing broad: no whole Documents, files or cache folder', () {
      for (final name in ['backup_rules.xml', 'data_extraction_rules.xml']) {
        final xml =
            File('android/app/src/main/res/xml/$name').readAsStringSync();
        for (final (domain, path) in _excludes(xml)) {
          expect(path, isNot(anyOf('app_flutter', '.', '')),
              reason: '$name $domain');
        }
        expect(xml, isNot(contains('<include')), reason: name);
      }
    });
  });

  group('the excluded names are the ones the code uses', () {
    test('the image-cache indexes: DefaultCacheManager\'s and the private one',
        () {
      expect(DefaultCacheManager.key, 'libCachedImageData');
      expect(PrivateMediaCache.storeKey, 'bwPrivateMedia');
      expect(PrivateMediaBackupExclusions.cacheIndexFiles, [
        'libCachedImageData.db',
        'libCachedImageData.db-journal',
        'libCachedImageData.db-wal',
        'libCachedImageData.db-shm',
        'bwPrivateMedia.db',
        'bwPrivateMedia.db-journal',
        'bwPrivateMedia.db-wal',
        'bwPrivateMedia.db-shm',
      ]);
    });

    test('Hive opens its boxes in Documents, with no sub-folder', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('await Hive.initFlutter();'));
      expect(main, contains("await Hive.openBox('local_media');"));
      final media = File('lib/src/services/offline_media_service.dart')
          .readAsStringSync();
      expect(media, contains("_localMediaBoxName = 'local_media'"));
      expect(media, contains("_urlMappingBoxName = 'url_mapping'"));
      expect(media, contains("String directoryName = 'profile_media',"));
      expect(PrivateMediaBackupExclusions.documentFiles, [
        'url_mapping.hive',
        'url_mapping.hivec',
        'url_mapping.lock',
        'local_media.hive',
        'local_media.hivec',
        'local_media.lock',
      ]);
      expect(PrivateMediaBackupExclusions.documentFolders,
          ['profile_media', 'offer_media']);
    });

    test('startup marks them on iPhone once the media boxes are open', () {
      final main = File('lib/main.dart').readAsStringSync();
      final opened =
          main.indexOf('await OfflineMediaService.instance.initialize();');
      final marked =
          main.indexOf('PrivateMediaBackupExclusions().excludeExisting()');
      expect(opened, isNonNegative);
      expect(marked, greaterThan(opened));
    });
  });

  // -----------------------------------------------------------------------
  group('on iPhone each existing item is marked, and nothing is touched', () {
    late Directory documents;
    late Directory support;

    setUp(() {
      documents = Directory.systemTemp.createTempSync('m05_docs_');
      support = Directory.systemTemp.createTempSync('m05_support_');
    });
    tearDown(() {
      documents.deleteSync(recursive: true);
      support.deleteSync(recursive: true);
    });

    test('existing files and folders only; bytes and times unchanged',
        () async {
      final present = [
        File(_sep([documents.path, 'url_mapping.hive']))..writeAsBytesSync([1]),
        File(_sep([documents.path, 'local_media.lock']))..writeAsBytesSync([2]),
        File(_sep([support.path, 'libCachedImageData.db']))
          ..writeAsBytesSync([3, 4]),
        File(_sep([support.path, 'bwPrivateMedia.db']))..writeAsBytesSync([6]),
      ];
      final profile = Directory(_sep([documents.path, 'profile_media']))
        ..createSync();
      final photo = File(_sep([profile.path, 'p.jpg']))..writeAsBytesSync([9]);
      final before = {
        for (final f in [...present, photo])
          f.path: (f.readAsBytesSync(), f.lastModifiedSync())
      };
      final guard = _Guard();

      final marked = await PrivateMediaBackupExclusions(
        documents: () async => documents,
        support: () async => support,
        backup: guard,
      ).excludeExisting();

      expect(guard.excluded.toSet(), {
        _sep([documents.path, 'url_mapping.hive']),
        _sep([documents.path, 'local_media.lock']),
        _sep([documents.path, 'profile_media']),
        _sep([support.path, 'libCachedImageData.db']),
        _sep([support.path, 'bwPrivateMedia.db']),
      });
      expect(marked, guard.excluded);
      for (final entry in before.entries) {
        final f = File(entry.key);
        expect(f.readAsBytesSync(), entry.value.$1, reason: entry.key);
        expect(f.lastModifiedSync(), entry.value.$2, reason: entry.key);
      }
      expect(documents.listSync().length, 3, reason: 'nothing created');
      expect(support.listSync().length, 2, reason: 'nothing created');
    });

    test('a guard that fails, or a missing directory, never throws', () async {
      final failing = _FailingGuard();
      File(_sep([documents.path, 'url_mapping.hive'])).writeAsBytesSync([1]);
      await PrivateMediaBackupExclusions(
        documents: () async => documents,
        support: () async => throw const FileSystemException('none'),
        backup: failing,
      ).excludeExisting();
      expect(failing.calls, 1);
    });
  });

  // -----------------------------------------------------------------------
  group('a folder made for adopted media is marked when it is made', () {
    late Directory documents;
    late _Guard guard;
    late Future<Directory> Function() previousDocuments;
    late ScannerBackupGuard previousGuard;

    setUp(() async {
      documents = Directory.systemTemp.createTempSync('m05_adopt_');
      Hive.init(documents.path);
      previousDocuments = OfflineMediaService.resolveDocumentsDirectory;
      previousGuard = OfflineMediaService.backupGuard;
      OfflineMediaService.resolveDocumentsDirectory = () async => documents;
      guard = _Guard();
      OfflineMediaService.backupGuard = guard;
      await OfflineMediaService.instance.initialize();
    });
    tearDown(() async {
      OfflineMediaService.resolveDocumentsDirectory = previousDocuments;
      OfflineMediaService.backupGuard = previousGuard;
      await Hive.close();
      documents.deleteSync(recursive: true);
    });

    for (final folder in ['profile_media', 'offer_media']) {
      test('$folder: copied and mapped exactly as before, then marked',
          () async {
        final source = File(_sep([documents.path, 'picked.jpg']))
          ..writeAsBytesSync([7, 7, 7]);
        await OfflineMediaService.instance.adoptLocalFileForMediaId(
          'media-1',
          source.path,
          directoryName: folder,
        );
        // The service joins with '/', as it always has.
        final copy = File('${documents.path}/$folder/media-1.jpg');
        expect(copy.readAsBytesSync(), [7, 7, 7]);
        expect(source.existsSync(), isTrue, reason: 'never moved');
        expect(
            OfflineMediaService.instance.getLocalFilePathForMediaId('media-1'),
            copy.path);
        expect(guard.excluded, ['${documents.path}/$folder']);
      });
    }
  });
}

class _FailingGuard implements ScannerBackupGuard {
  int calls = 0;
  @override
  Future<bool> exclude(String path) async {
    calls++;
    return false;
  }
}
