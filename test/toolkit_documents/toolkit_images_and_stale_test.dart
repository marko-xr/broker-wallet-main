// C1.1: Scanner JPEG / PNG documents, forged or truncated content, download
// integrity per format, the deletion-history ("stale") rule for old offline
// queues, and the isolation of ownerless legacy documents.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_file_probe.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_legacy_migration.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_library_reconciler.dart';

import 'toolkit_fakes.dart';

Uint8List bytesOf(ToolkitContentType type, [int extra = 64]) => switch (type) {
      ToolkitContentType.pdf => pdfBytes(extra),
      ToolkitContentType.jpeg => jpegBytes(extra),
      ToolkitContentType.png => pngBytes(extra),
    };

Uint8List headOf(Uint8List b) => b.sublist(0, b.length < 32 ? b.length : 32);
Uint8List tailOf(Uint8List b) =>
    b.sublist(b.length > 1024 ? b.length - 1024 : 0);

void main() {
  group('formats', () {
    test('three formats, one extension each, images only for the Scanner', () {
      expect(ToolkitContentType.values.map((t) => t.mime),
          ['application/pdf', 'image/jpeg', 'image/png']);
      expect(ToolkitContentType.values.map((t) => t.extension),
          ['pdf', 'jpg', 'png']);
      for (final tool in ToolkitDocumentType.values) {
        expect(ToolkitContentType.pdf.allowedFor(tool), isTrue);
        expect(ToolkitContentType.jpeg.allowedFor(tool),
            tool == ToolkitDocumentType.scanner);
        expect(ToolkitContentType.png.allowedFor(tool),
            tool == ToolkitDocumentType.scanner);
      }
      for (final bad in [
        'image/gif',
        'IMAGE/PNG',
        'image/jpeg; charset=x',
        '',
        null,
        7
      ]) {
        expect(ToolkitContentType.fromMime(bad), isNull, reason: '$bad');
      }
    });

    test('leading bytes identify the format; complete containers pass', () {
      for (final type in ToolkitContentType.values) {
        final bytes = bytesOf(type);
        expect(ToolkitContentType.detect(bytes), type);
        expect(type.hasValidFraming(headOf(bytes), tailOf(bytes), bytes.length),
            isTrue);
      }
      expect(ToolkitContentType.detect('GIF89a......'.codeUnits), isNull);
      expect(ToolkitContentType.detect(<int>[]), isNull);
    });

    test('a polyglot (one format\'s start with another\'s ending) is refused',
        () {
      final eof = '\n%%EOF\n'.codeUnits;
      bool framed(ToolkitContentType t, List<int> b) {
        final bytes = Uint8List.fromList(b);
        return t.hasValidFraming(headOf(bytes), tailOf(bytes), bytes.length);
      }

      expect(framed(ToolkitContentType.pdf, [...jpegBytes(), ...eof]), isFalse);
      expect(framed(ToolkitContentType.pdf, [...pngBytes(), ...eof]), isFalse);
      expect(framed(ToolkitContentType.jpeg, [...pngBytes(), 0xff, 0xd9]),
          isFalse);
      expect(framed(ToolkitContentType.jpeg, [...pdfBytes(), 0xff, 0xd9]),
          isFalse);
      expect(
          framed(ToolkitContentType.png, [
            ...jpegBytes(),
            0,
            0,
            0,
            0,
            0x49,
            0x45,
            0x4e,
            0x44,
            0xae,
            0x42,
            0x60,
            0x82
          ]),
          isFalse);
    });

    test('forged and truncated containers fail for every format pair', () {
      for (final declared in ToolkitContentType.values) {
        for (final actual in ToolkitContentType.values) {
          if (declared == actual) continue;
          final bytes = bytesOf(actual);
          expect(
              declared.hasValidFraming(
                  headOf(bytes), tailOf(bytes), bytes.length),
              isFalse,
              reason: '$actual as $declared');
        }
      }
      bool framed(ToolkitContentType t, Uint8List b) => t.hasValidFraming(
          b.sublist(0, b.length < 32 ? b.length : 32),
          b.sublist(b.length > 1024 ? b.length - 1024 : 0),
          b.length);
      expect(
          framed(ToolkitContentType.jpeg, jpegBytes().sublist(0, 60)), isFalse);
      expect(
          framed(ToolkitContentType.png, pngBytes().sublist(0, 70)), isFalse);
      expect(
          framed(ToolkitContentType.pdf, pdfBytes().sublist(0, 70)), isFalse);
      final zeroSize = pngBytes()..setRange(16, 20, [0, 0, 0, 0]);
      expect(framed(ToolkitContentType.png, zeroSize), isFalse);
    });

    test('the metadata contract keeps the tool and the format apart', () {
      Map<String, Object?> json({
        String tool = 'scanner',
        String type = 'image/png',
        Object? pages = 1,
        Object? size = 10,
      }) =>
          {
            'documentId': doc1,
            'documentType': tool,
            'contentType': type,
            'title': 'Scan',
            'sizeBytes': size,
            'pageCount': pages,
            'contentSha256': 'a' * 64,
            'sha256Verified': true,
            'sourceCreatedAt': '2026-10-19T08:00:00.000Z',
            'createdAt': '2026-10-19T08:00:01.000Z',
            'version': 2,
          };
      final scan = ToolkitDocumentMetadata.fromWorkerJson(json());
      expect((scan.type, scan.contentType, scan.sha256Verified),
          (ToolkitDocumentType.scanner, ToolkitContentType.png, true));
      for (final bad in [
        json(tool: 'signature'),
        json(tool: 'combine_pdfs', type: 'image/jpeg'),
        json(type: 'image/gif'),
        json(pages: 3),
        json(size: 65 * 1024 * 1024),
      ]) {
        expect(() => ToolkitDocumentMetadata.fromWorkerJson(bad),
            throwsFormatException,
            reason: '$bad');
      }
      expect(
          ToolkitDocumentMetadata.fromWorkerJson(
                  json(tool: 'signature', type: 'application/pdf', pages: 4))
              .type,
          ToolkitDocumentType.signature);
    });
  });

  group('Scanner images through the coordinator', () {
    late Harness h;
    setUp(() async => h = await Harness.create());
    tearDown(() => h.dispose());

    Future<ToolkitSyncEntry> addImage(String id, ToolkitContentType type,
        {Uint8List? bytes,
        ToolkitDocumentType tool = ToolkitDocumentType.scanner}) async {
      final data = bytes ?? bytesOf(type);
      await h.files.create('$id.${type.extension}', data);
      return h.coordinator
          .enqueue(entryFor(id, data, contentType: type, type: tool));
    }

    test('a JPEG and a PNG scan are saved to the cloud with their own format',
        () async {
      for (final (id, type) in [
        (doc1, ToolkitContentType.jpeg),
        (doc2, ToolkitContentType.png),
      ]) {
        final data = bytesOf(type);
        await addImage(id, type, bytes: data);
        expect(await h.coordinator.sync(id), ToolkitSyncOutcome.synced);
        expect(h.transport.lastAuthorizedContentType, type);
        expect(h.transport.lastUploadedContentType, type);
        final stored = h.transport.server[id]!;
        expect((stored.type, stored.contentType),
            (ToolkitDocumentType.scanner, type));
        expect(stored.bytes, data);
        expect(h.coordinator.entryFor(id)!.state,
            ToolkitDocumentSyncState.savedToCloud);
        expect(h.coordinator.entryFor(id)!.contentType, type);
        expect(h.coordinator.entryFor(id)!.contentSha256, sha(data));
      }
      // The format survives a restart, from the journal.
      final again = h.restarted();
      await again.load();
      expect(again.entryFor(doc1)!.contentType, ToolkitContentType.jpeg);
      expect(again.entryFor(doc2)!.contentType, ToolkitContentType.png);
      await again.dispose();
    });

    test('only the Scanner may queue an image', () async {
      for (final tool in [
        ToolkitDocumentType.combinePdfs,
        ToolkitDocumentType.imageToPdf,
        ToolkitDocumentType.signature,
      ]) {
        await expectLater(addImage(doc1, ToolkitContentType.jpeg, tool: tool),
            throwsArgumentError,
            reason: '$tool');
      }
      expect(h.coordinator.entries, isEmpty);
    });

    test('a file that is not what its type says is never uploaded', () async {
      final cases = <String, (ToolkitContentType, Uint8List)>{
        'a PDF stored as JPEG': (ToolkitContentType.jpeg, pdfBytes()),
        'a JPEG stored as PNG': (ToolkitContentType.png, jpegBytes()),
        'a PNG stored as PDF': (ToolkitContentType.pdf, pngBytes()),
        'a JPEG without its end marker': (
          ToolkitContentType.jpeg,
          jpegBytes().sublist(0, jpegBytes().length - 2)
        ),
        'a PNG without IEND': (
          ToolkitContentType.png,
          pngBytes().sublist(0, pngBytes().length - 12)
        ),
        'noise': (ToolkitContentType.jpeg, Uint8List(200)),
      };
      var n = 0;
      for (final entry in cases.entries) {
        final id = 'd0c1000${n++}-0000-4000-8000-00000000000$n';
        await addImage(id, entry.value.$1, bytes: entry.value.$2);
        expect(await h.coordinator.sync(id), ToolkitSyncOutcome.rejected,
            reason: entry.key);
        expect(h.coordinator.entryFor(id)!.lastFailure,
            ToolkitFailure.typeMismatch,
            reason: entry.key);
      }
      expect(h.transport.calls, isEmpty, reason: 'nothing left the phone');
    });

    test('images have their own, smaller, size limit', () async {
      await h.dispose();
      h = await Harness.create(maxImageBytes: 300, maxDocumentBytes: 5000);
      await addImage(doc1, ToolkitContentType.jpeg, bytes: jpegBytes(600));
      expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.rejected);
      expect(
          h.coordinator.entryFor(doc1)!.lastFailure, ToolkitFailure.tooLarge);
      await h.add(doc2, extra: 600);
      expect(await h.coordinator.sync(doc2), ToolkitSyncOutcome.synced,
          reason: 'a PDF of that size is within the PDF limit');
      expect(h.transport.calls.where((c) => c == 'authorize'), hasLength(1));
    });

    test('a cloud-only image is a download-on-open document', () {
      final items = ToolkitLibraryReconciler.reconcile(
        local: const [],
        journal: const [],
        remote: [
          ToolkitDocumentMetadata(
            documentId: doc1,
            type: ToolkitDocumentType.scanner,
            contentType: ToolkitContentType.jpeg,
            title: 'Page 1',
            sizeBytes: 500,
            contentSha256: 'a' * 64,
            sourceCreatedAt: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
            version: 2,
          ),
        ],
      );
      expect(items.single.state, ToolkitDocumentSyncState.downloadRequired);
    });
  });

  group('download integrity per format', () {
    late Directory dir;
    late FakeToolkitTransport transport;
    late File target;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('toolkit_img_dl_');
      transport = FakeToolkitTransport(accountA);
      target = File('${dir.path}/cache/$doc1.bin');
    });
    tearDown(() => dir.delete(recursive: true));

    FakeServerDoc cloud(ToolkitContentType type, Uint8List stored,
            {String? declaredSha}) =>
        FakeServerDoc(
          type: ToolkitDocumentType.scanner,
          contentType: type,
          title: 'Scan',
          size: stored.length,
          sha: declaredSha ?? sha(stored),
        )
          ..status = 'ready'
          ..bytes = stored;

    test('JPEG and PNG scans download, verify and are stored', () async {
      for (final type in [ToolkitContentType.jpeg, ToolkitContentType.png]) {
        final data = bytesOf(type);
        transport.server[doc1] = cloud(type, data);
        final path = File('${dir.path}/${type.extension}.bin');
        expect(
            await ToolkitDocumentDownloadService(transport: transport)
                .ensureLocalCopy(documentId: doc1, target: path),
            ToolkitDownloadResult.downloaded);
        expect(await path.readAsBytes(), data);
      }
    });

    test('corrupted, truncated and swapped-format downloads are discarded',
        () async {
      final service = ToolkitDocumentDownloadService(transport: transport);
      final good = jpegBytes();
      final corrupt = Uint8List.fromList(good)..[10] ^= 0xff;
      final truncated = pngBytes().sublist(0, pngBytes().length - 12);
      final swapped = pdfBytes();
      final cases = <String, (ToolkitContentType, Uint8List, Uint8List)>{
        // stored != what the hash was declared for
        'bit flip': (ToolkitContentType.jpeg, good, corrupt),
        // the declared hash IS of the damaged bytes: the container check refuses
        'truncated png': (ToolkitContentType.png, truncated, truncated),
        'a pdf under a jpeg record': (
          ToolkitContentType.jpeg,
          swapped,
          swapped
        ),
      };
      for (final entry in cases.entries) {
        final (type, declared, served) = entry.value;
        transport.server[doc1] = cloud(type, declared);
        transport.downloadOverride = served;
        final failure = await () async {
          try {
            await service.ensureLocalCopy(documentId: doc1, target: target);
          } on ToolkitDocumentException catch (e) {
            return e.failure;
          }
          return null;
        }();
        expect(failure, ToolkitFailure.integrityMismatch, reason: entry.key);
        expect(target.existsSync(), isFalse, reason: entry.key);
        expect(File('${target.path}.part').existsSync(), isFalse,
            reason: entry.key);
      }
    });

    test('the probe reads only the ends of a file', () async {
      final file = File('${dir.path}/probe.png')
        ..writeAsBytesSync(pngBytes(5000));
      expect(
          await ToolkitFileProbe.isCompleteContainer(
              file, ToolkitContentType.png),
          isTrue);
      expect(
          await ToolkitFileProbe.isCompleteContainer(
              file, ToolkitContentType.jpeg),
          isFalse);
      expect(
          await ToolkitFileProbe.isCompleteContainer(
              File('${dir.path}/missing.png'), ToolkitContentType.png),
          isFalse);
      expect(
          await ToolkitFileProbe.isCompleteContainer(
              File('${dir.path}/probe.png')..writeAsBytesSync(<int>[]),
              ToolkitContentType.png),
          isFalse);
    });
  });

  group('deletion history: stale offline queues', () {
    late Harness h;
    setUp(() async => h = await Harness.create());
    tearDown(() => h.dispose());

    test('an old queued document is not re-created after the tombstone is gone',
        () async {
      // entryFor makes documents at 2026-10-19 08:00 UTC; the account's floor is later.
      h.transport.staleFloor = DateTime.utc(2026, 10, 19, 9);
      await h.add(doc1);
      expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.rejected);
      final entry = h.coordinator.entryFor(doc1)!;
      expect(entry.state, ToolkitDocumentSyncState.syncRejected);
      expect(entry.lastFailure, ToolkitFailure.staleDocument);
      expect(h.transport.server, isEmpty, reason: 'nothing was created');
      expect(h.transport.callCount('uploadBytes'), 0);

      // It is never retried on its own...
      h.now = h.now.add(const Duration(days: 30));
      expect(await h.coordinator.syncDue(), isEmpty);
      expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.rejected);
      // ...and a plain retry asks again and is refused again.
      expect(await h.coordinator.retry(doc1), ToolkitSyncOutcome.rejected);
      expect(h.transport.lastAcknowledgeStale, isFalse);
    });

    test('only the user\'s explicit acknowledgement backs it up', () async {
      h.transport.staleFloor = DateTime.utc(2026, 10, 19, 9);
      await h.add(doc1);
      await h.coordinator.sync(doc1);
      expect(await h.coordinator.retry(doc1, acknowledgeStale: true),
          ToolkitSyncOutcome.synced);
      expect(h.transport.lastAcknowledgeStale, isTrue);
      expect(h.coordinator.entryFor(doc1)!.staleAcknowledged, isTrue);
      expect(h.transport.server[doc1]!.status, 'ready');
      final again = h.restarted();
      await again.load();
      expect(again.entryFor(doc1)!.staleAcknowledged, isTrue);
      await again.dispose();
    });

    test('a document made after the floor needs no acknowledgement', () async {
      h.transport.staleFloor = DateTime.utc(2026, 10, 19, 7);
      await h.add(doc1);
      expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.synced);
      expect(h.transport.lastAcknowledgeStale, isFalse);
    });

    test('an account being deleted stops the queue instead of retrying forever',
        () async {
      await h.add(doc1);
      h.transport.failNext('authorize', ToolkitFailure.deletionInProgress);
      expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.rejected);
      expect(h.coordinator.entryFor(doc1)!.lastFailure,
          ToolkitFailure.deletionInProgress);
      h.now = h.now.add(const Duration(days: 2));
      expect(await h.coordinator.syncDue(), isEmpty);
    });

    test(
        'a confirmed document that the cloud no longer lists is never uploaded again',
        () {
      // Restored from an old cache / long offline: the journal knows it reached the cloud.
      final confirmed = entryFor(doc1, pdfBytes()).copyWith(
          cloudConfirmedAt: DateTime.utc(2026, 1, 1), confirmedTitle: 'Lease');
      for (final remote in [
        ToolkitRemoteState.deleted,
        ToolkitRemoteState.unknown
      ]) {
        final items = ToolkitLibraryReconciler.reconcile(
          local: [
            ToolkitLocalDocument(documentId: doc1, sizeBytes: pdfBytes().length)
          ],
          journal: [confirmed],
          remote: const [],
          remoteStates: {doc1: remote},
        );
        expect(items.single.action,
            ToolkitReconcileAction.keepLocalDeletedRemotely,
            reason: '$remote');
      }
    });
  });

  group('ownerless legacy documents stay local and isolated', () {
    ToolkitLegacyCandidate cand(
      String id, {
      ToolkitDocumentType type = ToolkitDocumentType.scanner,
      String contentType = 'application/pdf',
      String? folder,
      String? owner = accountA,
      int size = 1000,
      String title = 'Lease',
    }) =>
        ToolkitLegacyCandidate(
          type: type,
          localId: id,
          accountFolderName:
              folder ?? ToolkitLegacyMigration.accountFolderName(accountA),
          indexOwnerId: owner,
          contentType: contentType,
          sizeBytes: size,
          title: title,
        );

    test(
        'Scanner JPEG and PNG scans of the account are eligible; other tools\' images are not',
        () {
      final plan = ToolkitLegacyMigration.plan(
        currentUserId: accountA,
        candidates: [
          cand(doc1, contentType: 'image/jpeg'),
          cand(doc2, contentType: 'image/png'),
          cand(doc3,
              type: ToolkitDocumentType.signature, contentType: 'image/png'),
          cand(doc4,
              type: ToolkitDocumentType.imageToPdf, contentType: 'image/jpeg'),
        ],
      );
      expect(plan.eligible.map((c) => c.localId), [doc1, doc2]);
      expect(plan.count(ToolkitLegacyDecision.unsupportedType), 2);
    });

    test('an image has the image size limit', () {
      final plan = ToolkitLegacyMigration.plan(
        currentUserId: accountA,
        candidates: [
          cand(doc1, contentType: 'image/png', size: 30 * 1024 * 1024),
          cand(doc2, contentType: 'application/pdf', size: 30 * 1024 * 1024),
        ],
      );
      expect(plan.eligible.map((c) => c.localId), [doc2]);
      expect(plan.skipped['scanner/$doc1'], ToolkitLegacyDecision.tooLarge);
    });

    test(
        'ownerless documents are skipped for every signed-in user, in every format',
        () {
      for (final user in [accountA, accountB]) {
        final plan = ToolkitLegacyMigration.plan(
          currentUserId: user,
          candidates: [
            for (final (i, type)
                in ['application/pdf', 'image/jpeg', 'image/png'].indexed)
              cand('d0c1000$i-0000-4000-8000-00000000000$i',
                  contentType: type,
                  owner: null,
                  folder: ToolkitLegacyMigration.accountFolderName(user)),
          ],
        );
        expect(plan.eligible, isEmpty, reason: user);
        expect(plan.count(ToolkitLegacyDecision.ownerless), 3, reason: user);
      }
    });

    test('a matching title or file name is never proof of ownership', () {
      final plan = ToolkitLegacyMigration.plan(
        currentUserId: accountA,
        candidates: [
          // Same title as the account's own document, but no owner on record.
          cand(doc1, owner: null, title: 'Lease'),
          // Same document id and title as A's, found in B's folder with B as owner.
          cand(doc2,
              owner: accountB,
              folder: ToolkitLegacyMigration.accountFolderName(accountB)),
          // The right folder but an index that names someone else.
          cand(doc3, owner: accountB),
          // A's own document.
          cand(doc4),
        ],
      );
      expect(plan.eligible.map((c) => c.localId), [doc4]);
      expect(plan.skipped['scanner/$doc1'], ToolkitLegacyDecision.ownerless);
      expect(plan.skipped['scanner/$doc2'], ToolkitLegacyDecision.otherAccount);
      expect(plan.skipped['scanner/$doc3'], ToolkitLegacyDecision.otherAccount);
    });

    test(
        'per-account documents stay eligible next to skipped ones, and a re-run adds nothing',
        () {
      final candidates = [
        cand(doc1),
        cand(doc2, contentType: 'image/jpeg'),
        cand(doc3, owner: null),
      ];
      final first = ToolkitLegacyMigration.plan(
          currentUserId: accountA, candidates: candidates);
      expect(first.eligible.map((c) => c.localId), [doc1, doc2]);
      final second = ToolkitLegacyMigration.plan(
          currentUserId: accountA,
          candidates: candidates,
          idsAlreadyInCloud: {doc1, doc2});
      expect(second.eligible, isEmpty);
      expect(second.count(ToolkitLegacyDecision.alreadyInCloud), 2);
      expect(second.count(ToolkitLegacyDecision.ownerless), 1);
    });
  });
}
