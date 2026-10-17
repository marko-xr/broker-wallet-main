import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/scanner/scan_models.dart';

/// Prepares the files of a Scanner share. A stored document is named by an
/// internal id, which must never reach another app, so a share carries copies
/// named by the document's title in a folder of their own inside the app's
/// temporary directory.
///
/// The copies are not deleted the moment the share sheet opens: Android reports
/// nothing back for a chooser, and the app that receives the file may still be
/// reading it. They are swept when a later Scanner session starts
/// ([sweepStale]).
class ScannerSharePreparer {
  ScannerSharePreparer({required Future<Directory> Function() tempRoot})
      : _tempRoot = tempRoot;

  final Future<Directory> Function() _tempRoot;

  Future<Directory> _root() async =>
      Directory(p.join((await _tempRoot()).path, 'scanner_share'));

  /// Copies each of [files] to a title-named file and returns the new paths in
  /// the same order. [files] pairs a document with its stored file.
  Future<List<String>> prepare(
      List<({ScannerDocument document, File file})> files) async {
    final folder = Directory(p.join((await _root()).path, const Uuid().v4()));
    await folder.create(recursive: true);
    final used = <String>{};
    final paths = <String>[];
    try {
      for (final item in files) {
        var name = item.document.exportFileName;
        var counter = 2;
        while (!used.add(name.toLowerCase())) {
          name = '${item.document.name} ($counter).${item.document.extension}';
          counter++;
        }
        final target = File(p.join(folder.path, name));
        await item.file.copy(target.path);
        paths.add(target.path);
      }
    } catch (_) {
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
    return paths;
  }

  /// Removes share folders older than [olderThan]. Folders made just now are
  /// kept, since a receiving app may still be reading them.
  Future<void> sweepStale({
    Duration olderThan = const Duration(hours: 1),
    DateTime? now,
  }) async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final cutoff = (now ?? DateTime.now()).subtract(olderThan);
      await for (final item in root.list(followLinks: false)) {
        if (item is! Directory) continue;
        final stat = await item.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await item.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
