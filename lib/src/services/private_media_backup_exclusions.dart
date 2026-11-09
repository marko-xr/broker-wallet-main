// M0.5 (tracker §7AZ, D-M1): keeps this device's private media and the
// indexes that describe it out of new backups where the platform allows.
//
// Android does this declaratively: backup_rules.xml and
// data_extraction_rules.xml list each path below. iPhone needs each item
// marked (`isExcludedFromBackup`, through the existing
// PlatformScannerBackupGuard channel in AppDelegate.swift), which
// [excludeExisting] does at startup for whatever exists then; a media folder
// made later is marked when it is made (OfflineMediaService).
//
// Nothing is moved, cleared, encrypted or deleted: the exclusion keeps a new
// backup from taking a copy, and does nothing to backups already made.

import 'dart:io';

import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PrivateMediaBackupExclusions {
  PrivateMediaBackupExclusions({
    Future<Directory> Function()? documents,
    Future<Directory> Function()? support,
    ScannerBackupGuard? backup,
  })  : _documents = documents ?? getApplicationDocumentsDirectory,
        _support = support ?? getApplicationSupportDirectory,
        _backup = backup ?? PlatformScannerBackupGuard();

  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _support;
  final ScannerBackupGuard _backup;

  /// In the documents folder (`Hive.initFlutter()`, no sub-folder): the media
  /// identity map and the media catalogue, with the lock and the compaction
  /// file Hive keeps beside each box.
  static const List<String> documentFiles = [
    'url_mapping.hive',
    'url_mapping.hivec',
    'url_mapping.lock',
    'local_media.hive',
    'local_media.hivec',
    'local_media.lock',
  ];

  /// In the documents folder: profile originals and adopted Offer/Owner
  /// originals and video frames (Android already excludes offer_media).
  static const List<String> documentFolders = ['profile_media', 'offer_media'];

  /// In the application-support folder: the image cache's index (it records
  /// each entry's key and the link it was fetched from), the private image
  /// cache's index (M1b: keys only), and SQLite's files beside each.
  static final List<String> cacheIndexFiles = [
    for (final store in [DefaultCacheManager.key, PrivateMediaCache.storeKey])
      for (final suffix in ['', '-journal', '-wal', '-shm']) '$store.db$suffix',
  ];

  /// Marks every listed item that exists now; returns the paths it asked
  /// about. Best effort: never throws, and never creates, changes or
  /// deletes anything.
  Future<List<String>> excludeExisting() async {
    final asked = <String>[];
    Future<void> mark(String path, {required bool folder}) async {
      try {
        final exists =
            folder ? await Directory(path).exists() : await File(path).exists();
        if (!exists) return;
        asked.add(path);
        await _backup.exclude(path);
      } catch (_) {}
    }

    try {
      final documents = (await _documents()).path;
      for (final name in documentFiles) {
        await mark(p.join(documents, name), folder: false);
      }
      for (final name in documentFolders) {
        await mark(p.join(documents, name), folder: true);
      }
    } catch (_) {}
    try {
      final support = (await _support()).path;
      for (final name in cacheIndexFiles) {
        await mark(p.join(support, name), folder: false);
      }
    } catch (_) {}
    return asked;
  }
}
