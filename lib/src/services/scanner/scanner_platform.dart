import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';

/// The native channel shared with the Toolkit's other tools
/// (`FileSaverPlugin.kt`). Its older `saveFileToDownloads` method is unchanged
/// for them; the Scanner uses the two file-based methods below, which stream
/// from a file instead of passing a whole document through the channel.
const MethodChannel scannerFileChannel = MethodChannel('file_saver');

/// Reads Android `content://` URIs through the platform's content resolver.
class PlatformContentUriReader implements ContentUriReader {
  PlatformContentUriReader([MethodChannel? channel])
      : _channel = channel ?? scannerFileChannel;

  final MethodChannel _channel;

  @override
  Future<void> copyContentUri(String uri, File destination) async {
    final result = await _channel.invokeMethod<Object?>(
      'copyContentUriToFile',
      <String, Object?>{'uri': uri, 'destinationPath': destination.path},
    );
    if (result is! Map || result['success'] != true) {
      throw const FileSystemException('content copy failed');
    }
  }
}

/// Where an exported copy went.
enum ScannerExportDestination {
  /// The phone's public Downloads folder (Android).
  downloads,

  /// A folder the user chose in the Files app (iPhone).
  files,
}

class ScannerExportResult {
  const ScannerExportResult.saved(this.destination, this.savedName)
      : cancelled = false;
  const ScannerExportResult.cancelled()
      : destination = null,
        savedName = null,
        cancelled = true;

  final ScannerExportDestination? destination;

  /// The name the copy was actually saved under (the phone may have changed it
  /// to avoid replacing a file that was already there).
  final String? savedName;
  final bool cancelled;
}

/// Copies a stored document to a place the user can reach.
abstract interface class ScannerExporter {
  /// Exports [file], the stored file of [document]. Throws a [ScannerException]
  /// (`permissionDenied`, `storageFull`, `exportFailed`).
  Future<ScannerExportResult> export(ScannerDocument document, File file);
}

/// Android: MediaStore Downloads (no storage permission on Android 10 and
/// later, and never All Files Access); the old public-folder route with the
/// legacy storage permission only on Android 9 and below. iPhone: the system
/// Files "save" sheet, so the user picks the destination. Nothing is reported
/// as saved unless the platform said so.
class PlatformScannerExporter implements ScannerExporter {
  PlatformScannerExporter({
    required this.isAndroid,
    required this.androidSdk,
    required this.requestLegacyStoragePermission,
    required this.saveToFiles,
    MethodChannel? channel,
  }) : _channel = channel ?? scannerFileChannel;

  final bool isAndroid;
  final Future<int> Function() androidSdk;

  /// Asks for the storage permission that only Android 9 and below need.
  final Future<bool> Function() requestLegacyStoragePermission;

  /// Shows the Files save sheet; returns the saved location or null when the
  /// user closed it.
  final Future<String?> Function(String fileName, Uint8List bytes) saveToFiles;
  final MethodChannel _channel;

  @override
  Future<ScannerExportResult> export(
      ScannerDocument document, File file) async {
    if (isAndroid) return _exportAndroid(document, file);
    return _exportFiles(document, file);
  }

  Future<ScannerExportResult> _exportAndroid(
      ScannerDocument document, File file) async {
    final sdk = await androidSdk();
    if (sdk <= 28 && !await requestLegacyStoragePermission()) {
      throw const ScannerException(ScannerFailure.permissionDenied);
    }
    try {
      final result = await _channel.invokeMethod<Object?>(
        'exportFileToDownloads',
        <String, Object?>{
          'sourcePath': file.path,
          'fileName': document.exportFileName,
          'mimeType': document.mimeType,
        },
      );
      if (result is Map &&
          result['success'] == true &&
          result['displayName'] is String) {
        return ScannerExportResult.saved(ScannerExportDestination.downloads,
            result['displayName'] as String);
      }
      throw const ScannerException(ScannerFailure.exportFailed, 'reply');
    } on PlatformException catch (error) {
      if (error.code == 'STORAGE_FULL') {
        throw const ScannerException(ScannerFailure.storageFull);
      }
      if (error.code == 'PERMISSION_DENIED') {
        throw const ScannerException(ScannerFailure.permissionDenied);
      }
      throw ScannerException(ScannerFailure.exportFailed, error.code);
    }
  }

  Future<ScannerExportResult> _exportFiles(
      ScannerDocument document, File file) async {
    try {
      final saved =
          await saveToFiles(document.exportFileName, await file.readAsBytes());
      if (saved == null) return const ScannerExportResult.cancelled();
      return ScannerExportResult.saved(
          ScannerExportDestination.files, p.basename(saved));
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.exportFailed, 'read');
    } on PlatformException catch (error) {
      throw ScannerException(ScannerFailure.exportFailed, error.code);
    }
  }
}
