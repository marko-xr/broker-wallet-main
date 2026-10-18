import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

/// One PDF the user picked: a private copy the picker made, and the name the
/// file had.
class PickedPdf {
  const PickedPdf({required this.path, required this.name});

  final String path;
  final String name;
}

/// Lets the user choose PDFs. The system picker needs no storage permission
/// (it hands the app only the files the user chose), so none is requested.
abstract interface class CombinePdfPicker {
  /// The chosen PDFs, or null when the picker was closed without a choice.
  Future<List<PickedPdf>?> pick();

  /// Removes the picker's private copies of files it handed out. Best effort.
  Future<void> clearPickedCopies();
}

class SystemCombinePdfPicker implements CombinePdfPicker {
  const SystemCombinePdfPicker();

  @override
  Future<List<PickedPdf>?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = <PickedPdf>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) {
        // Not a local file (a cloud-only document the system could not copy):
        // reported as a missing file rather than dropped.
        picked.add(PickedPdf(path: '', name: file.name));
      } else {
        picked.add(PickedPdf(path: path, name: file.name));
      }
    }
    return picked;
  }

  @override
  Future<void> clearPickedCopies() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
  }
}

/// Where an exported copy of a combined PDF goes.
abstract interface class CombinePdfExporter {
  /// Exports [file] under [fileName]. Throws a [CombinePdfException]
  /// (`permissionDenied`, `storageFull`, `exportFailed`).
  Future<ScannerExportResult> export(String fileName, File file);
}

/// Reuses the Scanner's route: MediaStore Downloads (no storage permission on
/// Android 10 and later, never All Files Access), the Files save sheet on
/// iPhone. Nothing is reported as saved unless the platform said so.
class PlatformCombinePdfExporter implements CombinePdfExporter {
  const PlatformCombinePdfExporter(this._exporter);

  final PlatformScannerExporter _exporter;

  @override
  Future<ScannerExportResult> export(String fileName, File file) async {
    try {
      return await _exporter.exportFile(
          file: file, fileName: fileName, mimeType: 'application/pdf');
    } on ScannerException catch (error) {
      switch (error.kind) {
        case ScannerFailure.permissionDenied:
          throw const CombinePdfException(CombinePdfFailure.permissionDenied);
        case ScannerFailure.storageFull:
          throw const CombinePdfException(CombinePdfFailure.storageFull);
        default:
          throw CombinePdfException(CombinePdfFailure.exportFailed,
              detail: error.detail);
      }
    }
  }
}

/// Prepares the files of a share. A stored document is named by an internal id,
/// which must never reach another app, so a share carries copies named by the
/// document's title in a folder of their own inside the app's temporary
/// directory. They are not deleted the moment the share sheet opens (the
/// receiving app may still be reading them); [sweepStale] removes old ones.
class CombineSharePreparer {
  CombineSharePreparer({required Future<Directory> Function() tempRoot})
      : _tempRoot = tempRoot;

  final Future<Directory> Function() _tempRoot;

  Future<Directory> _root() async =>
      Directory(p.join((await _tempRoot()).path, 'combine_share'));

  /// Copies each of [files] to a title-named file and returns the new paths in
  /// the same order.
  Future<List<String>> prepare(
      List<({CombinedPdf document, File file})> files) async {
    final folder = Directory(p.join((await _root()).path, const Uuid().v4()));
    await folder.create(recursive: true);
    final used = <String>{};
    final paths = <String>[];
    try {
      for (final item in files) {
        var name = item.document.exportFileName;
        var counter = 2;
        while (!used.add(name.toLowerCase())) {
          name = '${item.document.name} ($counter).pdf';
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
