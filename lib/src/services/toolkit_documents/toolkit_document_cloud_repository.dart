// The account's cloud document library: listing, state lookups, rename and
// delete. Uploads belong to the upload coordinator and downloads to the download
// service; this is the read side and the user's own changes.
//
// Reads come only from the Worker (never straight from the database), so the
// Single Active Device gate, the bucket scoping and the field allowlist apply.
// A document of another account cannot appear: the Worker lists only the
// verified account's documents and the transport is bound to one account.

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

abstract interface class ToolkitDocumentCloudRepository {
  String get accountId;

  /// One page, newest first. [cursor] is the previous page's `nextCursor`.
  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit,
    ToolkitDocumentType? type,
  });

  /// Every ready document, page after page. Stops with a failure rather than
  /// loop if the server repeats a cursor.
  Future<ToolkitDocumentListing> listAll({
    ToolkitDocumentType? type,
    int maxPages,
  });

  /// What the server knows about each of [documentIds], in batches.
  Future<Map<String, ToolkitRemoteState>> statuses(
      Iterable<String> documentIds);

  /// Renames; a stale version is retried once against the version the server
  /// reports (see the coordinator's rename policy).
  Future<ToolkitRenameResult> rename({
    required ToolkitDocumentMetadata document,
    required String title,
  });

  /// Deletes the document and its stored file. Idempotent.
  Future<ToolkitRemoveResult> remove(String documentId);
}

class ToolkitDocumentListing {
  const ToolkitDocumentListing({required this.documents, this.usage});

  final List<ToolkitDocumentMetadata> documents;
  final ToolkitDocumentUsage? usage;
}

class RemoteToolkitDocumentCloudRepository
    implements ToolkitDocumentCloudRepository {
  RemoteToolkitDocumentCloudRepository(this._transport);

  final ToolkitDocumentTransport _transport;

  @override
  String get accountId => _transport.accountId;

  @override
  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit = ToolkitDocumentLimits.listPageSize,
    ToolkitDocumentType? type,
  }) =>
      _transport.listPage(cursor: cursor, limit: limit, type: type);

  @override
  Future<ToolkitDocumentListing> listAll({
    ToolkitDocumentType? type,
    int maxPages = 100,
  }) async {
    final byId = <String, ToolkitDocumentMetadata>{};
    final seenCursors = <String>{};
    ToolkitDocumentUsage? usage;
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final result = await _transport.listPage(cursor: cursor, type: type);
      usage ??= result.usage;
      for (final document in result.documents) {
        // A repeated id is the same document: keep the newest version.
        final known = byId[document.documentId];
        if (known == null || document.version >= known.version) {
          byId[document.documentId] = document;
        }
      }
      final next = result.nextCursor;
      if (next == null) {
        return ToolkitDocumentListing(
          documents: byId.values.toList(),
          usage: usage,
        );
      }
      if (!seenCursors.add(next)) {
        throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
      }
      cursor = next;
    }
    // Too many pages to trust: report it instead of presenting a partial library
    // as the whole one.
    throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
  }

  @override
  Future<Map<String, ToolkitRemoteState>> statuses(
    Iterable<String> documentIds,
  ) async {
    final ids = documentIds.toSet().toList()..sort();
    final answered = <String, ToolkitRemoteState>{};
    for (var i = 0;
        i < ids.length;
        i += ToolkitDocumentLimits.statusBatchSize) {
      final batch =
          ids.skip(i).take(ToolkitDocumentLimits.statusBatchSize).toList();
      answered.addAll((await _transport.statuses(batch)).byId);
    }
    return answered;
  }

  @override
  Future<ToolkitRenameResult> rename({
    required ToolkitDocumentMetadata document,
    required String title,
  }) async {
    final problem = ToolkitDocumentTitles.problemWith(title);
    if (problem != null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidRequest);
    }
    try {
      return await _transport.rename(
        documentId: document.documentId,
        title: title,
        expectedVersion: document.version,
      );
    } on ToolkitDocumentException catch (error) {
      final current = error.currentVersion;
      if (error.failure != ToolkitFailure.staleVersion || current == null) {
        rethrow;
      }
      return _transport.rename(
        documentId: document.documentId,
        title: title,
        expectedVersion: current,
      );
    }
  }

  @override
  Future<ToolkitRemoveResult> remove(String documentId) =>
      _transport.remove(documentId: documentId);
}
