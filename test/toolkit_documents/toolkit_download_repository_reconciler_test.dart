// Download verification, the cloud library repository, and the pure
// reconciliation policy.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_cloud_repository.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_library_reconciler.dart';

import 'toolkit_fakes.dart';

Future<ToolkitFailure?> failureOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on ToolkitDocumentException catch (error) {
    return error.failure;
  }
  return null;
}

void main() {
  group('download service', () {
    late Directory dir;
    late FakeToolkitTransport transport;
    late Uint8List bytes;
    late File target;

    FakeServerDoc ready({String? hash, Uint8List? stored}) => FakeServerDoc(
          type: ToolkitDocumentType.scanner,
          title: 'Scan',
          size: bytes.length,
          sha: hash ?? sha(bytes),
        )
          ..status = 'ready'
          ..bytes = stored ?? bytes;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('toolkit_dl_');
      transport = FakeToolkitTransport(accountA);
      bytes = pdfBytes(500);
      target = File('${dir.path}/cache/$doc1.pdf');
      transport.server[doc1] = ready();
    });
    tearDown(() => dir.delete(recursive: true));

    test('downloads, verifies and stores a document that is only in the cloud',
        () async {
      final service = ToolkitDocumentDownloadService(transport: transport);
      expect(await service.ensureLocalCopy(documentId: doc1, target: target),
          ToolkitDownloadResult.downloaded);
      expect(await target.readAsBytes(), bytes);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('an intact local copy is reused with no network at all', () async {
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      final known = transport.metadataOf(doc1);
      final service = ToolkitDocumentDownloadService(transport: transport);
      expect(
          await service.ensureLocalCopy(
              documentId: doc1, target: target, known: known),
          ToolkitDownloadResult.alreadyLocal);
      expect(transport.calls, isEmpty);
    });

    test('a different local file is a conflict and is never overwritten',
        () async {
      await target.parent.create(recursive: true);
      final other = pdfBytes(499);
      await target.writeAsBytes(other);
      final service = ToolkitDocumentDownloadService(transport: transport);
      expect(
          await service.ensureLocalCopy(
              documentId: doc1,
              target: target,
              known: transport.metadataOf(doc1)),
          ToolkitDownloadResult.conflict);
      expect(await target.readAsBytes(), other);
      expect(transport.downloadCalls, 0);
      expect(transport.calls, isEmpty,
          reason: 'known metadata decides it without any network use');

      // Same size, different bytes: caught by the hash.
      final sameSize = List<int>.of(bytes)..[20] = 0x41;
      await target.writeAsBytes(sameSize);
      expect(
          await service.ensureLocalCopy(
              documentId: doc1,
              target: target,
              known: transport.metadataOf(doc1)),
          ToolkitDownloadResult.conflict);
      expect(await target.readAsBytes(), sameSize);
      expect(transport.calls, isEmpty);

      // Without listed metadata the server is asked what the file must be.
      expect(await service.ensureLocalCopy(documentId: doc1, target: target),
          ToolkitDownloadResult.conflict);
      expect(await target.readAsBytes(), sameSize);
    });

    test('truncated, corrupted and non-PDF downloads are discarded', () async {
      final cases = <String, Uint8List>{
        'truncated': Uint8List.sublistView(bytes, 0, bytes.length - 10),
        'corrupted (same size)':
            Uint8List.fromList(List<int>.of(bytes)..[30] ^= 0xff),
        'an error page':
            Uint8List.fromList(('<html>' + 'x' * (bytes.length - 6)).codeUnits),
      };
      final service = ToolkitDocumentDownloadService(transport: transport);
      for (final entry in cases.entries) {
        transport.downloadOverride = entry.value;
        expect(
            await failureOf(() =>
                service.ensureLocalCopy(documentId: doc1, target: target)),
            isIn([ToolkitFailure.integrityMismatch]),
            reason: entry.key);
        expect(target.existsSync(), isFalse, reason: entry.key);
        expect(File('${target.path}.part').existsSync(), isFalse,
            reason: entry.key);
      }
    });

    test(
        'bytes whose hash matches but that are not a complete file of their type are refused',
        () async {
      // The device declared the hash of an error page: the hash alone proves
      // nothing about the format, the container check does.
      final page =
          Uint8List.fromList(('<html>' + 'x' * (bytes.length - 6)).codeUnits);
      transport.server[doc1] = FakeServerDoc(
          type: ToolkitDocumentType.scanner,
          title: 'S',
          size: bytes.length,
          sha: sha(page))
        ..status = 'ready'
        ..bytes = bytes;
      transport.downloadOverride = page;
      final service = ToolkitDocumentDownloadService(transport: transport);
      expect(
          await failureOf(
              () => service.ensureLocalCopy(documentId: doc1, target: target)),
          ToolkitFailure.integrityMismatch);
      expect(target.existsSync(), isFalse);
    });

    test(
        'a record whose digest is only device-declared still downloads and verifies',
        () async {
      transport.server[doc1] = FakeServerDoc(
          type: ToolkitDocumentType.scanner,
          title: 'S',
          size: bytes.length,
          sha: sha(bytes))
        ..status = 'ready'
        ..bytes = bytes;
      final service = ToolkitDocumentDownloadService(transport: transport);
      expect(await service.ensureLocalCopy(documentId: doc1, target: target),
          ToolkitDownloadResult.downloaded);
    });

    test('too little free space is detected before downloading', () async {
      final service = ToolkitDocumentDownloadService(
        transport: transport,
        freeSpace: (_) async => bytes.length + 100,
        spaceMargin: 1000,
      );
      expect(
          await failureOf(
              () => service.ensureLocalCopy(documentId: doc1, target: target)),
          ToolkitFailure.insufficientStorage);
      expect(transport.downloadCalls, 0);

      final enough = ToolkitDocumentDownloadService(
          transport: transport,
          freeSpace: (_) async => bytes.length + 5000,
          spaceMargin: 1000);
      expect(await enough.ensureLocalCopy(documentId: doc1, target: target),
          ToolkitDownloadResult.downloaded);

      final unknown = ToolkitDocumentDownloadService(
          transport: transport, freeSpace: (_) async => null);
      await target.delete();
      expect(await unknown.ensureLocalCopy(documentId: doc1, target: target),
          ToolkitDownloadResult.downloaded,
          reason: 'an unknown amount does not block');
    });

    test('a full disk during the download leaves nothing behind', () async {
      final service = ToolkitDocumentDownloadService(transport: transport);
      transport.failNext('downloadToFile', ToolkitFailure.insufficientStorage);
      expect(
          await failureOf(
              () => service.ensureLocalCopy(documentId: doc1, target: target)),
          ToolkitFailure.insufficientStorage);
      expect(target.existsSync(), isFalse);
    });

    test('a deleted, unknown or mismatched document cannot be downloaded',
        () async {
      final service = ToolkitDocumentDownloadService(transport: transport);
      transport.server[doc1]!.status = 'deleted';
      expect(
          await failureOf(
              () => service.ensureLocalCopy(documentId: doc1, target: target)),
          ToolkitFailure.documentDeleted);
      expect(
          await failureOf(
              () => service.ensureLocalCopy(documentId: doc2, target: target)),
          ToolkitFailure.documentNotFound);
      expect(
          await failureOf(() =>
              service.ensureLocalCopy(documentId: 'not-an-id', target: target)),
          ToolkitFailure.invalidRequest);
    });

    test('stale partial files are removed', () async {
      await target.parent.create(recursive: true);
      File('${target.parent.path}/a.pdf.part').writeAsStringSync('x');
      File('${target.parent.path}/keep.pdf').writeAsStringSync('x');
      expect(
          await ToolkitDocumentDownloadService.removeStalePartFiles(
              target.parent),
          1);
      expect(File('${target.parent.path}/keep.pdf').existsSync(), isTrue);
    });
  });

  group('repository', () {
    late FakeToolkitTransport transport;
    late RemoteToolkitDocumentCloudRepository repository;

    setUp(() {
      transport = FakeToolkitTransport(accountA);
      repository = RemoteToolkitDocumentCloudRepository(transport);
    });

    void seed(int count) {
      for (var i = 0; i < count; i++) {
        final id =
            'd0c${i.toString().padLeft(5, '0')}-0000-4000-8000-000000000000';
        transport.server[id] = FakeServerDoc(
            type: i.isEven
                ? ToolkitDocumentType.scanner
                : ToolkitDocumentType.signature,
            title: 'Doc $i',
            size: 10 + i,
            sha: sha([i]))
          ..status = 'ready';
      }
    }

    test('listAll follows every page and returns each document once', () async {
      seed(120);
      final listing = await repository.listAll();
      expect(listing.documents, hasLength(120));
      expect(
          listing.documents.map((d) => d.documentId).toSet(), hasLength(120));
      expect(transport.callCount('listPage'), 3);
      expect(
          (await repository.listAll(type: ToolkitDocumentType.signature))
              .documents,
          hasLength(60));
    });

    test(
        'a repeated cursor or too many pages is a failure, not a partial library',
        () async {
      seed(120);
      final looping = _LoopingTransport(transport);
      expect(
          await failureOf(
              () => RemoteToolkitDocumentCloudRepository(looping).listAll()),
          ToolkitFailure.invalidResponse);
      expect(looping.pages, 2, reason: 'stopped at the repeated cursor');
      expect(await failureOf(() => repository.listAll(maxPages: 2)),
          ToolkitFailure.invalidResponse);
    });

    test('statuses are asked in batches of 50 and merged', () async {
      seed(120);
      final ids = transport.server.keys.toList();
      final answered = await repository.statuses([...ids, ...ids, doc1]);
      expect(answered, hasLength(121));
      expect(answered[doc1], ToolkitRemoteState.unknown);
      expect(transport.callCount('statuses'), 3);
    });

    test('rename retries once on a stale version and reports the result',
        () async {
      seed(1);
      final id = transport.server.keys.single;
      final seen = transport.metadataOf(id);
      transport.server[id]!
        ..title = 'Changed elsewhere'
        ..version += 3;
      final result = await repository.rename(document: seen, title: 'Mine');
      expect(result.title, 'Mine');
      expect(transport.callCount('rename'), 2);
      expect(
          await failureOf(
              () => repository.rename(document: seen, title: ' bad')),
          ToolkitFailure.invalidRequest);
      transport.failNext('rename', ToolkitFailure.unavailable);
      expect(
          await failureOf(() => repository.rename(
              document: transport.metadataOf(id), title: 'x')),
          ToolkitFailure.unavailable,
          reason: 'other failures are not retried here');
    });

    test('remove is idempotent', () async {
      seed(1);
      final id = transport.server.keys.single;
      expect((await repository.remove(id)).alreadyRemoved, isFalse);
      expect((await repository.remove(id)).alreadyRemoved, isTrue);
      expect(repository.accountId, accountA);
    });
  });

  group('reconciliation policy', () {
    ToolkitDocumentMetadata cloud(String id, int size, {String? hash}) =>
        ToolkitDocumentMetadata(
          documentId: id,
          type: ToolkitDocumentType.scanner,
          contentType: ToolkitContentType.pdf,
          title: 'T',
          sizeBytes: size,
          contentSha256: hash ?? 'c' * 64,
          sourceCreatedAt: DateTime.utc(2026),
          createdAt: DateTime.utc(2026),
          version: 2,
        );

    ToolkitSyncEntry journaled(String id, {bool confirmed = false}) {
      final entry = entryFor(id, pdfBytes());
      return confirmed
          ? entry.copyWith(
              cloudConfirmedAt: DateTime.utc(2026), confirmedTitle: 'Lease')
          : entry;
    }

    Map<String, ToolkitReconcileItem> run({
      List<ToolkitLocalDocument> local = const [],
      List<ToolkitSyncEntry> journal = const [],
      List<ToolkitDocumentMetadata> remote = const [],
      Map<String, ToolkitRemoteState> states = const {},
    }) =>
        {
          for (final item in ToolkitLibraryReconciler.reconcile(
              local: local,
              journal: journal,
              remote: remote,
              remoteStates: states))
            item.documentId: item,
        };

    test('a new phone: cloud documents are downloaded on open', () {
      final items = run(remote: [cloud(doc1, 100), cloud(doc2, 200)]);
      expect(items.values.map((i) => i.state).toSet(),
          {ToolkitDocumentSyncState.downloadRequired});
      expect(items.values.map((i) => i.action).toSet(),
          {ToolkitReconcileAction.downloadOnOpen});
    });

    test(
        'same bytes in both places are in sync, even if the journal lost track',
        () {
      final items = run(
        local: [const ToolkitLocalDocument(documentId: doc1, sizeBytes: 100)],
        journal: [journaled(doc1)],
        remote: [cloud(doc1, 100)],
      );
      expect(items[doc1]!.state, ToolkitDocumentSyncState.savedToCloud);
      expect(items[doc1]!.action, ToolkitReconcileAction.none);
    });

    test('same id but different bytes is a conflict that touches neither side',
        () {
      final bySize = run(
        local: [const ToolkitLocalDocument(documentId: doc1, sizeBytes: 99)],
        remote: [cloud(doc1, 100)],
      );
      expect(bySize[doc1]!.action, ToolkitReconcileAction.conflict);
      final byHash = run(
        local: [
          ToolkitLocalDocument(
              documentId: doc1, sizeBytes: 100, contentSha256: 'a' * 64)
        ],
        remote: [cloud(doc1, 100, hash: 'b' * 64)],
      );
      expect(byHash[doc1]!.action, ToolkitReconcileAction.conflict);
    });

    test('a local file that never reached the cloud is uploaded', () {
      final items = run(local: [
        const ToolkitLocalDocument(documentId: doc1, sizeBytes: 100)
      ]);
      expect(items[doc1]!.action, ToolkitReconcileAction.upload);
      expect(
          items[doc1]!.state, ToolkitDocumentSyncState.savedLocallyPendingSync);
    });

    test('a document deleted elsewhere is never uploaded again', () {
      for (final confirmed in [false, true]) {
        final items = run(
          local: [const ToolkitLocalDocument(documentId: doc1, sizeBytes: 100)],
          journal: [journaled(doc1, confirmed: confirmed)],
          states: {doc1: ToolkitRemoteState.deleted},
        );
        expect(items[doc1]!.state, ToolkitDocumentSyncState.remoteDeleted,
            reason: 'confirmed=$confirmed');
        expect(items[doc1]!.action,
            ToolkitReconcileAction.keepLocalDeletedRemotely);
      }
    });

    test(
        'a document that was confirmed once and is now unknown is not resurrected',
        () {
      final items = run(
        local: [const ToolkitLocalDocument(documentId: doc1, sizeBytes: 100)],
        journal: [journaled(doc1, confirmed: true)],
        states: {doc1: ToolkitRemoteState.unknown},
      );
      expect(
          items[doc1]!.action, ToolkitReconcileAction.keepLocalDeletedRemotely);
    });

    test(
        'a listed document whose file is gone: download if the cloud has it, else lost',
        () {
      final cloudHas = run(
        local: [
          const ToolkitLocalDocument(
              documentId: doc1, sizeBytes: 100, fileMissing: true)
        ],
        remote: [cloud(doc1, 100)],
      );
      expect(cloudHas[doc1]!.state, ToolkitDocumentSyncState.downloadRequired);
      final lost = run(local: [
        const ToolkitLocalDocument(
            documentId: doc2, sizeBytes: 100, fileMissing: true)
      ]);
      expect(lost[doc2]!.action, ToolkitReconcileAction.lost);
    });

    test('a stale local cache never causes an upload over the cloud', () {
      // The cloud has the document; the local one has other bytes. Nothing uploads.
      final items = run(
        local: [const ToolkitLocalDocument(documentId: doc1, sizeBytes: 50)],
        journal: [journaled(doc1)],
        remote: [cloud(doc1, 100)],
      );
      expect(items[doc1]!.action, isNot(ToolkitReconcileAction.upload));
    });
  });
}

/// Answers the same cursor forever.
class _LoopingTransport implements ToolkitDocumentTransport {
  _LoopingTransport(this._inner);

  final FakeToolkitTransport _inner;
  int pages = 0;

  @override
  String get accountId => _inner.accountId;

  @override
  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit = 50,
    ToolkitDocumentType? type,
  }) async {
    pages += 1;
    final page = await _inner.listPage(cursor: '0', limit: 10, type: type);
    return ToolkitDocumentPage(documents: page.documents, nextCursor: 'same');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
