// The last list of an account's documents that the Worker returned, kept on the
// phone so a tool can show its document cards the moment its screen opens, before
// (or without) a round trip.
//
// It is a convenience copy of METADATA only (ids, titles, sizes, dates): never a
// file, a signed URL or a storage key. It is never an authority:
//  * the cards it shows are replaced by the next list the Worker returns, so a
//    document deleted elsewhere disappears at the next successful list;
//  * a document is opened only through an authorized download, which the server
//    refuses for a deleted document;
//  * an entry of another account, another tool or one that does not pass the
//    Worker's strict contract is dropped, never shown.
// A file that cannot be read is ignored: the next successful list writes a new
// one. It lives in the tool's account folder, which backup already excludes.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_diagnostics.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';

abstract interface class ToolkitRemoteCache {
  /// The documents of [type] the last successful list held; empty when there is
  /// none. Never throws.
  Future<List<ToolkitDocumentMetadata>> read(ToolkitDocumentType type);

  /// Replaces the copy for [type] with [documents]. Never throws.
  Future<void> write(
    ToolkitDocumentType type,
    List<ToolkitDocumentMetadata> documents,
  );
}

/// A cache in memory, for tests and for builds with no storage.
class InMemoryToolkitRemoteCache implements ToolkitRemoteCache {
  final Map<ToolkitDocumentType, List<ToolkitDocumentMetadata>> _byType =
      <ToolkitDocumentType, List<ToolkitDocumentMetadata>>{};

  @override
  Future<List<ToolkitDocumentMetadata>> read(ToolkitDocumentType type) async =>
      List<ToolkitDocumentMetadata>.of(
          _byType[type] ?? const <ToolkitDocumentMetadata>[]);

  @override
  Future<void> write(
    ToolkitDocumentType type,
    List<ToolkitDocumentMetadata> documents,
  ) async {
    _byType[type] = List<ToolkitDocumentMetadata>.of(documents);
  }
}

/// One JSON file per account and tool, written through a temporary file and
/// renamed over the old one, so a crash leaves the previous complete copy.
class FileToolkitRemoteCache implements ToolkitRemoteCache {
  FileToolkitRemoteCache({required this.directory, required this.accountId});

  final Directory directory;
  final String accountId;

  Future<void> _tail = Future<void>.value();

  File _file(ToolkitDocumentType type) {
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(accountId);
    final name = plain
        ? accountId
        : 'u_${utf8.encode(accountId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    return File(
        p.join(directory.path, 'toolkit_remote_${type.wireName}_$name.json'));
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<List<ToolkitDocumentMetadata>> read(ToolkitDocumentType type) =>
      _serial(() async {
        try {
          final file = _file(type);
          if (!await file.exists()) return <ToolkitDocumentMetadata>[];
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is! Map ||
              decoded['accountId'] != accountId ||
              decoded['type'] != type.wireName ||
              decoded['documents'] is! List) {
            return <ToolkitDocumentMetadata>[];
          }
          final documents = <ToolkitDocumentMetadata>[];
          for (final raw in decoded['documents'] as List) {
            try {
              final document = ToolkitDocumentMetadata.fromWorkerJson(raw);
              if (document.type == type) documents.add(document);
            } on FormatException {
              // One entry that no longer fits the contract is dropped alone.
            }
          }
          return documents;
        } catch (error) {
          ToolkitDiagnostics.report('cache-read-failed',
              type: type, error: error);
          return <ToolkitDocumentMetadata>[];
        }
      });

  @override
  Future<void> write(
    ToolkitDocumentType type,
    List<ToolkitDocumentMetadata> documents,
  ) =>
      _serial(() async {
        try {
          await directory.create(recursive: true);
          final file = _file(type);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(
            jsonEncode(<String, Object?>{
              'version': 1,
              'accountId': accountId,
              'type': type.wireName,
              'documents': documents.map((d) => d.toWorkerJson()).toList(),
            }),
            flush: true,
          );
          await temp.rename(file.path);
        } catch (error) {
          ToolkitDiagnostics.report('cache-write-failed',
              type: type, error: error);
        }
      });
}
