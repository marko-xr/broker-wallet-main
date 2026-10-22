// Brings a cloud document back onto this phone as a VERIFIED local file.
//
// Opening a document that is only in the cloud (a new phone, a reinstall)
// downloads it here first; sharing and exporting then use that prepared local
// file, never a signed URL.
//
// What it guarantees:
//  * The bytes go to `<target>.part` and become `<target>` only after the size,
//    the PDF header and (when the device declared one) the SHA-256 match what the
//    server recorded. A partial, truncated or corrupted download is deleted; a
//    damaged file is never left where a library could open it.
//  * An existing file is NEVER overwritten. Bytes of one id cannot change, so a
//    local file that does not match the cloud record is a conflict the caller
//    must resolve (it can download to another target to compare); an intact one
//    is reused without any network.
//  * Not enough free space is detected before the download starts, and a full
//    disk during it is reported as such, with the partial file removed.
//  * A signed URL is used once and never stored or logged.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_file_probe.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

/// Free bytes where [directory] lives, or null when it cannot be told. The
/// platform wiring supplies it; the default knows nothing.
typedef ToolkitFreeSpaceProbe = Future<int?> Function(Directory directory);

enum ToolkitDownloadResult {
  /// An intact local copy was already there; nothing was fetched.
  alreadyLocal,

  /// Downloaded, verified and stored.
  downloaded,

  /// A file is there but is not the cloud document (wrong size or hash). It was
  /// left exactly as it is.
  conflict,
}

class ToolkitDocumentDownloadService {
  ToolkitDocumentDownloadService({
    required ToolkitDocumentTransport transport,
    ToolkitFreeSpaceProbe? freeSpace,
    ToolkitFileHasher? hasher,
    this.spaceMargin = 8 * 1024 * 1024,
  })  : _transport = transport,
        _freeSpace = freeSpace,
        _hasher = hasher ?? ToolkitSha256.hexOfFile;

  final ToolkitDocumentTransport _transport;
  final ToolkitFreeSpaceProbe? _freeSpace;
  final ToolkitFileHasher _hasher;

  /// Free space required beyond the file itself.
  final int spaceMargin;

  /// Makes sure [target] holds the document [documentId]; see the class notes.
  ///
  /// [known] is what the library last listed for it (size, hash), used to
  /// recognize an intact copy without asking the server.
  Future<ToolkitDownloadResult> ensureLocalCopy({
    required String documentId,
    required File target,
    ToolkitDocumentMetadata? known,
  }) async {
    if (!ToolkitDocumentIds.isCanonical(documentId)) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidRequest);
    }
    if (await target.exists()) {
      if (known != null &&
          await _matches(target, known.sizeBytes, known.contentSha256)) {
        return ToolkitDownloadResult.alreadyLocal;
      }
      if (known != null) return ToolkitDownloadResult.conflict;
      // Nothing to compare with: ask the server what the file must be.
      final ticket = await _transport.downloadTicket(documentId);
      return await _matches(target, ticket.sizeBytes, ticket.contentSha256)
          ? ToolkitDownloadResult.alreadyLocal
          : ToolkitDownloadResult.conflict;
    }
    await _download(documentId, target);
    return ToolkitDownloadResult.downloaded;
  }

  Future<void> _download(String documentId, File target) async {
    final ticket = await _transport.downloadTicket(documentId);
    if (ticket.documentId != documentId) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    if (ticket.sizeBytes > ToolkitDocumentLimits.hardDocumentBytes) {
      // Above anything the server accepts: not a document of this app.
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    await _requireSpace(target.parent, ticket.sizeBytes);

    final part = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }

    try {
      await _transport.downloadToFile(
        url: ticket.url,
        target: part,
        maxBytes: ticket.sizeBytes,
      );
      if (!await _matches(part, ticket.sizeBytes, ticket.contentSha256)) {
        throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
      }
      if (!await ToolkitFileProbe.isCompleteContainer(
          part, ticket.contentType)) {
        throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
      }
      if (await target.exists()) {
        // Something appeared while downloading: never replace it.
        throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
      }
      await part.rename(target.path);
    } on ToolkitDocumentException {
      await _quietDelete(part);
      rethrow;
    } on FileSystemException catch (error) {
      await _quietDelete(part);
      throw ToolkitDocumentException(
        _isDiskFull(error)
            ? ToolkitFailure.insufficientStorage
            : ToolkitFailure.fileUnavailable,
      );
    }
  }

  Future<void> _requireSpace(Directory directory, int bytes) async {
    final probe = _freeSpace;
    if (probe == null) return;
    final free = await probe(directory);
    if (free != null && free < bytes + spaceMargin) {
      throw const ToolkitDocumentException(ToolkitFailure.insufficientStorage);
    }
  }

  Future<bool> _matches(File file, int size, String sha256) async {
    try {
      if (await file.length() != size) return false;
      return await _hasher(file) == sha256;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _quietDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static bool _isDiskFull(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 28 || code == 112;
  }

  /// Removes `.part` files an interrupted download left in [directory].
  @visibleForTesting
  static Future<int> removeStalePartFiles(Directory directory) async {
    var removed = 0;
    if (!await directory.exists()) return removed;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.pdf.part')) {
        await entity.delete();
        removed += 1;
      }
    }
    return removed;
  }
}
