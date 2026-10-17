import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_result.dart';

/// Copies the bytes behind an Android `content://` URI into a local file. The
/// only implementation that talks to the platform; tests substitute their own.
abstract interface class ContentUriReader {
  /// Throws when the URI cannot be opened or the copy fails.
  Future<void> copyContentUri(String uri, File destination);
}

/// A scanner output that is now a local file the Scanner may read.
class StagedScanFile {
  const StagedScanFile({
    required this.file,
    required this.isTemporaryCopy,
    required this.isScannerOutput,
  });

  final File file;

  /// The file is a copy this operation made from a `content://` URI.
  final bool isTemporaryCopy;

  /// The file is one the scanner wrote into its own output folder, which the
  /// Scanner may remove once it has stored (or dropped) the scan.
  final bool isScannerOutput;
}

/// The folders the stager works with, resolved once the platform can say where
/// they are.
class ScannerRoots {
  const ScannerRoots({
    required this.stagingDir,
    required this.trusted,
    this.denied = const <Directory>[],
    this.scannerOutputDirs = const <Directory>[],
    this.scannerOutputFlatDirs = const <Directory>[],
  });

  /// Where copies of `content://` URIs are made. Owned by the Scanner.
  final Directory stagingDir;

  /// Folders the scanner may have written its output to.
  final List<Directory> trusted;

  /// Folders inside a trusted one that are never read (the Scanner's own store).
  final List<Directory> denied;

  /// Folders created by the scanner for this app: every file inside, at any
  /// depth, is its disposable output.
  final List<Directory> scannerOutputDirs;

  /// Shared folders where the scanner drops date-named files directly (the
  /// iPhone scanner writes `yyyyMMdd-HHmmss[-n].png|pdf` into the app's
  /// Documents folder); only files of that name, directly inside, are disposable.
  final List<Directory> scannerOutputFlatDirs;
}

/// Turns what the scanner named into a local file, and only a file the Scanner
/// is entitled to read.
///
/// A `file://` URI or a plain path is accepted only when it resolves (links
/// followed) to a regular file inside one of the trusted folders and outside
/// every denied one, so a result can never point the Scanner at some other part
/// of the phone or at its own document store. A `content://` URI is never
/// turned into a path by cutting its prefix; it is copied through the platform
/// ([ContentUriReader]) into the staging folder.
class ScanSourceStager {
  ScanSourceStager({
    required Future<ScannerRoots> Function() roots,
    this.contentReader,
  }) : _roots = roots;

  final Future<ScannerRoots> Function() _roots;
  final ContentUriReader? contentReader;

  static final RegExp _scannerOutputName =
      RegExp(r'^\d{8}-\d{6}(-\d+)?\.(png|jpg|jpeg|pdf)$');

  /// Makes [source] a readable local file. [operationId] names the staging
  /// folder of this one scan.
  Future<StagedScanFile> stage(
    ScanSource source, {
    required String operationId,
    required int index,
  }) async {
    final roots = await _roots();
    if (source.kind == ScanSourceKind.content) {
      return _copyContent(roots, source, operationId, index);
    }
    final String resolved;
    try {
      final file = File(source.localPath);
      if (!p.isAbsolute(file.path)) {
        throw const ScannerException(
            ScannerFailure.untrustedSource, 'relative');
      }
      if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file) {
        // A link is followed below; a missing file or a folder is not a file.
        if (!await File(file.path).exists()) {
          throw const ScannerException(ScannerFailure.missingOutput);
        }
      }
      resolved = await file.resolveSymbolicLinks();
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.missingOutput);
    }
    if (await FileSystemEntity.type(resolved) != FileSystemEntityType.file) {
      throw const ScannerException(ScannerFailure.missingOutput);
    }
    if (!await _isInside(resolved, roots.trusted) ||
        await _isInside(resolved, roots.denied)) {
      throw const ScannerException(ScannerFailure.untrustedSource, 'outside');
    }
    return StagedScanFile(
      file: File(resolved),
      isTemporaryCopy: false,
      isScannerOutput: await _isInside(resolved, roots.scannerOutputDirs) ||
          await _isFlatScannerOutput(resolved, roots.scannerOutputFlatDirs),
    );
  }

  Future<StagedScanFile> _copyContent(ScannerRoots roots, ScanSource source,
      String operationId, int index) async {
    final reader = contentReader;
    if (reader == null) {
      throw const ScannerException(ScannerFailure.untrustedSource, 'content');
    }
    final folder = Directory(p.join(roots.stagingDir.path, operationId));
    final destination = File(p.join(folder.path, 'page_$index.tmp'));
    try {
      await folder.create(recursive: true);
      await reader.copyContentUri(source.uri, destination);
    } catch (error) {
      await _quietDelete(destination);
      if (error is FileSystemException && _isStorageFull(error)) {
        throw const ScannerException(ScannerFailure.storageFull);
      }
      throw const ScannerException(ScannerFailure.missingOutput, 'content');
    }
    return StagedScanFile(
      file: destination,
      isTemporaryCopy: true,
      isScannerOutput: false,
    );
  }

  /// Removes what this scan left behind: a copy made from a `content://` URI,
  /// and a file the scanner wrote into its own output folder. Nothing else is
  /// ever deleted, and failures are ignored.
  Future<void> release(StagedScanFile staged) async {
    if (staged.isTemporaryCopy || staged.isScannerOutput) {
      await _quietDelete(staged.file);
    }
  }

  /// Removes the (now empty) staging folder of one scan.
  Future<void> releaseOperation(String operationId) async {
    try {
      final roots = await _roots();
      final folder = Directory(p.join(roots.stagingDir.path, operationId));
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}
  }

  Future<bool> _isInside(String resolved, List<Directory> roots) async {
    for (final root in roots) {
      try {
        if (!await root.exists()) continue;
        final rootPath = await root.resolveSymbolicLinks();
        if (p.isWithin(rootPath, resolved)) return true;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }

  Future<bool> _isFlatScannerOutput(
      String resolved, List<Directory> roots) async {
    if (!_scannerOutputName.hasMatch(p.basename(resolved))) return false;
    for (final root in roots) {
      try {
        if (!await root.exists()) continue;
        if (p.equals(await root.resolveSymbolicLinks(), p.dirname(resolved))) {
          return true;
        }
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }

  Future<void> _quietDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static bool _isStorageFull(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 28 || code == 112;
  }
}
