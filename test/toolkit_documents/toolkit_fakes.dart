// Test doubles for the Toolkit cloud document services: a scripted in-memory
// "server" behind the transport seam, and local files in a temporary folder.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

const String accountA = '11111111-1111-4111-8111-111111111111';
const String accountB = '22222222-2222-4222-8222-222222222222';
const String doc1 = 'd0c00001-0000-4000-8000-000000000001';
const String doc2 = 'd0c00002-0000-4000-8000-000000000002';
const String doc3 = 'd0c00003-0000-4000-8000-000000000003';
const String doc4 = 'd0c00004-0000-4000-8000-000000000004';

/// A JPEG-looking file body (start and end markers) of [extra] filler bytes.
Uint8List jpegBytes([int extra = 64]) => Uint8List.fromList(
    [0xff, 0xd8, 0xff, 0xe0, ...List<int>.filled(extra, 0x11), 0xff, 0xd9]);

/// A PNG-looking file body (signature, IHDR, IEND) of [extra] filler bytes.
Uint8List pngBytes([int extra = 64]) => Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 16, 0, 0, 0, 16, //
      8, 2, 0, 0, 0, 0, 0, 0, 0,
      ...List<int>.filled(extra + 30, 0x22),
      0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82, //
    ]);

/// A PDF-looking file body of [extra] filler bytes.
Uint8List pdfBytes([int extra = 64]) => Uint8List.fromList(
    '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n${'x' * extra}\n%%EOF\n'.codeUnits);

class FakeServerDoc {
  FakeServerDoc({
    required this.type,
    required this.title,
    required this.size,
    required this.sha,
    this.contentType = ToolkitContentType.pdf,
  });

  final ToolkitDocumentType type;
  final ToolkitContentType contentType;
  String title;
  final int size;
  final String sha;
  bool sha256Verified = false;
  String status = 'pending'; // pending | ready | deleted
  int version = 1;
  Uint8List? bytes;
  DateTime created = DateTime.utc(2026, 10, 19);
}

class FakeToolkitTransport implements ToolkitDocumentTransport {
  FakeToolkitTransport(this.accountId);

  @override
  final String accountId;

  final List<String> calls = <String>[];
  final Map<String, FakeServerDoc> server = <String, FakeServerDoc>{};
  final Map<String, List<Object>> _failures = <String, List<Object>>{};

  /// The server's deletion-history floor: a document with no record whose device
  /// creation time is at or before this is refused as stale unless acknowledged.
  DateTime? staleFloor;

  /// What the last authorize / upload carried, for assertions.
  ToolkitContentType? lastAuthorizedContentType;
  ToolkitContentType? lastUploadedContentType;
  Map<String, String> lastUploadHeaders = const {};
  bool? lastAcknowledgeStale;

  /// Pauses `uploadBytes` until completed (to test a delete during an upload).
  Completer<void>? uploadGate;

  /// Runs inside `uploadBytes`, after the gate.
  void Function()? duringUpload;

  /// Pauses `confirm` until completed (to test a delete during the confirmation).
  Completer<void>? confirmGate;

  /// `confirm` stores the confirmation on the server, then throws, as a lost
  /// response would.
  bool loseConfirmResponse = false;

  /// What `downloadToFile` writes instead of the stored bytes.
  Uint8List? downloadOverride;
  int downloadCalls = 0;
  int maxParallelUploads = 0;
  int _uploadsNow = 0;

  /// Makes the next call of [method] throw [failure].
  void failNext(String method, ToolkitFailure failure,
      {Duration? retryAfter, int times = 1}) {
    for (var i = 0; i < times; i++) {
      (_failures[method] ??= <Object>[]).add(
        ToolkitDocumentException(failure, retryAfter: retryAfter),
      );
    }
  }

  void _enter(String method) {
    calls.add(method);
    final queue = _failures[method];
    if (queue != null && queue.isNotEmpty) {
      throw queue.removeAt(0);
    }
  }

  int callCount(String method) => calls.where((c) => c == method).length;

  @override
  Future<ToolkitUploadAuthorization> authorize({
    required String documentId,
    required ToolkitDocumentType type,
    required ToolkitContentType contentType,
    required String title,
    required int contentLength,
    required String contentSha256,
    required DateTime sourceCreatedAt,
    int? pageCount,
    bool acknowledgeStale = false,
  }) async {
    _enter('authorize');
    lastAuthorizedContentType = contentType;
    lastAcknowledgeStale = acknowledgeStale;
    final known = server[documentId];
    if (known == null &&
        staleFloor != null &&
        !sourceCreatedAt.isAfter(staleFloor!) &&
        !acknowledgeStale) {
      throw const ToolkitDocumentException(ToolkitFailure.staleDocument);
    }
    if (known != null) {
      if (known.status == 'deleted') {
        throw const ToolkitDocumentException(ToolkitFailure.documentDeleted);
      }
      if (known.size != contentLength ||
          known.type != type ||
          known.contentType != contentType ||
          known.sha != contentSha256) {
        throw const ToolkitDocumentException(ToolkitFailure.idConflict);
      }
      if (known.status == 'ready') {
        return ToolkitUploadAuthorization.alreadyConfirmed(
            documentId: documentId);
      }
    } else {
      server[documentId] = FakeServerDoc(
          type: type,
          contentType: contentType,
          title: title,
          size: contentLength,
          sha: contentSha256);
    }
    return ToolkitUploadAuthorization.pending(
      documentId: documentId,
      presignedUrl: 'https://signed.example.test/put/$documentId?sig=secret',
      uploadHeaders: const {'If-None-Match': '*'},
    );
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required ToolkitContentType contentType,
    Map<String, String> headers = const {},
  }) async {
    _enter('uploadBytes');
    lastUploadedContentType = contentType;
    lastUploadHeaders = headers;
    _uploadsNow += 1;
    if (_uploadsNow > maxParallelUploads) maxParallelUploads = _uploadsNow;
    try {
      final gate = uploadGate;
      if (gate != null) await gate.future;
      duringUpload?.call();
      final id = presignedUrl.split('/put/').last.split('?').first;
      // Write-once, as the real service reports it: an existing object is kept.
      if (headers.containsKey('If-None-Match') && server[id]!.bytes != null) {
        return;
      }
      server[id]!.bytes = await file.readAsBytes();
    } finally {
      _uploadsNow -= 1;
    }
  }

  @override
  Future<ToolkitConfirmation> confirm({required String documentId}) async {
    _enter('confirm');
    final gate = confirmGate;
    if (gate != null) await gate.future;
    final doc = server[documentId];
    if (doc == null) {
      throw const ToolkitDocumentException(ToolkitFailure.documentNotFound);
    }
    if (doc.status == 'deleted') {
      throw const ToolkitDocumentException(ToolkitFailure.documentDeleted);
    }
    if (doc.status == 'ready') {
      return ToolkitConfirmation(version: doc.version, alreadyConfirmed: true);
    }
    if (doc.bytes == null) {
      throw const ToolkitDocumentException(ToolkitFailure.uploadIncomplete);
    }
    doc.status = 'ready';
    doc.version += 1;
    if (loseConfirmResponse) {
      loseConfirmResponse = false;
      throw const ToolkitDocumentException(ToolkitFailure.interrupted);
    }
    return ToolkitConfirmation(version: doc.version);
  }

  @override
  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit = ToolkitDocumentLimits.listPageSize,
    ToolkitDocumentType? type,
  }) async {
    _enter('listPage');
    final ids = server.entries
        .where((e) =>
            e.value.status == 'ready' && (type == null || e.value.type == type))
        .map((e) => e.key)
        .toList()
      ..sort();
    final start = cursor == null ? 0 : int.parse(cursor);
    final page = ids.skip(start).take(limit).toList();
    final next = start + limit < ids.length ? '${start + limit}' : null;
    return ToolkitDocumentPage(
      documents: [for (final id in page) metadataOf(id)],
      nextCursor: next,
    );
  }

  ToolkitDocumentMetadata metadataOf(String id) {
    final doc = server[id]!;
    return ToolkitDocumentMetadata(
      documentId: id,
      type: doc.type,
      contentType: doc.contentType,
      title: doc.title,
      sizeBytes: doc.size,
      contentSha256: doc.sha,
      sha256Verified: doc.sha256Verified,
      sourceCreatedAt: doc.created,
      createdAt: doc.created,
      version: doc.version,
    );
  }

  @override
  Future<ToolkitRemoteStatuses> statuses(List<String> documentIds) async {
    _enter('statuses');
    return ToolkitRemoteStatuses({
      for (final id in documentIds)
        id: switch (server[id]?.status) {
          'ready' => ToolkitRemoteState.ready,
          'pending' => ToolkitRemoteState.pending,
          'deleted' => ToolkitRemoteState.deleted,
          _ => ToolkitRemoteState.unknown,
        },
    });
  }

  @override
  Future<ToolkitDownloadTicket> downloadTicket(String documentId) async {
    _enter('downloadTicket');
    final doc = server[documentId];
    if (doc == null) {
      throw const ToolkitDocumentException(ToolkitFailure.documentNotFound);
    }
    if (doc.status == 'deleted') {
      throw const ToolkitDocumentException(ToolkitFailure.documentDeleted);
    }
    return ToolkitDownloadTicket(
      documentId: documentId,
      type: doc.type,
      contentType: doc.contentType,
      title: doc.title,
      sizeBytes: doc.size,
      version: doc.version,
      contentSha256: doc.sha,
      sha256Verified: doc.sha256Verified,
      url: 'https://signed.example.test/get/$documentId?sig=secret',
      expiresAt: DateTime.utc(2026, 10, 19, 12),
    );
  }

  @override
  Future<void> downloadToFile({
    required String url,
    required File target,
    required int maxBytes,
  }) async {
    _enter('downloadToFile');
    downloadCalls += 1;
    final id = url.split('/get/').last.split('?').first;
    final bytes = downloadOverride ?? server[id]!.bytes!;
    if (bytes.length > maxBytes) {
      throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
    }
    await target.writeAsBytes(bytes);
  }

  @override
  Future<ToolkitRenameResult> rename({
    required String documentId,
    required String title,
    required int expectedVersion,
  }) async {
    _enter('rename');
    final doc = server[documentId];
    if (doc == null) {
      throw const ToolkitDocumentException(ToolkitFailure.documentNotFound);
    }
    if (doc.status == 'deleted') {
      throw const ToolkitDocumentException(ToolkitFailure.documentDeleted);
    }
    if (doc.title == title) {
      return ToolkitRenameResult(title: doc.title, version: doc.version);
    }
    if (doc.version != expectedVersion) {
      throw ToolkitDocumentException(
        ToolkitFailure.staleVersion,
        currentTitle: doc.title,
        currentVersion: doc.version,
      );
    }
    doc.title = title;
    doc.version += 1;
    return ToolkitRenameResult(title: doc.title, version: doc.version);
  }

  @override
  Future<ToolkitRemoveResult> remove({required String documentId}) async {
    _enter('remove');
    final doc = server[documentId];
    if (doc == null || doc.status == 'deleted') {
      return const ToolkitRemoveResult(alreadyRemoved: true);
    }
    doc.status = 'deleted';
    doc.bytes = null;
    return const ToolkitRemoveResult();
  }
}

/// Resolves entries to files created in a temporary folder.
class TempLocalFiles implements ToolkitLocalFiles {
  TempLocalFiles(this.directory);

  final Directory directory;
  final Set<String> resolved = <String>{};

  File fileFor(String ref) => File('${directory.path}/$ref');

  Future<File> create(String ref, List<int> bytes) async {
    final file = fileFor(ref);
    await file.writeAsBytes(bytes);
    return file;
  }

  @override
  Future<File?> resolve(ToolkitSyncEntry entry) async {
    resolved.add(entry.localRef);
    final file = fileFor(entry.localRef);
    return await file.exists() ? file : null;
  }
}

ToolkitSyncEntry entryFor(
  String id,
  List<int> bytes, {
  String account = accountA,
  String title = 'Lease',
  ToolkitDocumentType type = ToolkitDocumentType.scanner,
  ToolkitContentType contentType = ToolkitContentType.pdf,
  String? localRef,
  String? sha,
}) =>
    ToolkitSyncEntry(
      documentId: id,
      accountId: account,
      type: type,
      contentType: contentType,
      title: title,
      sizeBytes: bytes.length,
      localRef: localRef ?? '$id.${contentType.extension}',
      sourceCreatedAt: DateTime.utc(2026, 10, 19, 8),
      pageCount: 1,
      contentSha256: sha,
    );

String sha(List<int> bytes) => ToolkitSha256.hexOfBytes(bytes);

class Harness {
  Harness._(this.dir, this.transport, this.journal, this.files);

  final Directory dir;
  final FakeToolkitTransport transport;
  final InMemoryToolkitSyncJournal journal;
  final TempLocalFiles files;
  String? signedIn = accountA;
  DateTime now = DateTime.utc(2026, 10, 19, 9);
  late ToolkitDocumentUploadCoordinator coordinator;

  static Future<Harness> create({
    int maxAutoAttempts = 8,
    int maxDocumentBytes = ToolkitDocumentLimits.defaultDocumentBytes,
    int maxImageBytes = ToolkitDocumentLimits.defaultImageBytes,
  }) async {
    final dir = await Directory.systemTemp.createTemp('toolkit_sync_test_');
    final harness = Harness._(
      dir,
      FakeToolkitTransport(accountA),
      InMemoryToolkitSyncJournal(),
      TempLocalFiles(dir),
    );
    harness.coordinator = ToolkitDocumentUploadCoordinator(
      accountId: accountA,
      transport: harness.transport,
      journal: harness.journal,
      files: harness.files,
      currentAccountId: () => harness.signedIn,
      clock: () => harness.now,
      maxAutoAttempts: maxAutoAttempts,
      maxDocumentBytes: maxDocumentBytes,
      maxImageBytes: maxImageBytes,
    );
    return harness;
  }

  /// A coordinator that reads the same journal, as after an app restart.
  ToolkitDocumentUploadCoordinator restarted() =>
      ToolkitDocumentUploadCoordinator(
        accountId: accountA,
        transport: transport,
        journal: journal,
        files: files,
        currentAccountId: () => signedIn,
        clock: () => now,
      );

  Future<ToolkitSyncEntry> add(String id,
      {int extra = 64, String title = 'Lease'}) async {
    final bytes = pdfBytes(extra);
    await files.create('$id.pdf', bytes);
    return coordinator.enqueue(entryFor(id, bytes, title: title));
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await dir.delete(recursive: true);
  }
}
