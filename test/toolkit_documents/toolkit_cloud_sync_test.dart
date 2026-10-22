// The object a Toolkit tool owns to keep its documents in the user's account:
// what it uploads, what it brings back after a reinstall, how a delete and a
// rename reach the account, and what it tells the user (including WHY the account
// could not be reached). The server is the in-memory fake behind the transport
// seam; the library, the journal logic and the coordinator are the real ones.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

import 'toolkit_fakes.dart';

/// One tool's phone side (a list of documents and their files) wired to the
/// account copy.
class Rig {
  Rig(this.transport) {
    dir = Directory.systemTemp.createTempSync('toolkit_sync_rig_');
    library = DefaultToolkitCloudLibrary(
      accountId: accountA,
      transport: transport,
      journal: InMemoryToolkitSyncJournal(),
      files: TempLocalFiles(dir),
      currentAccountId: () => accountA,
      clock: () => now,
    );
    sync = ToolkitCloudSync(
      type: ToolkitDocumentType.scanner,
      library: library,
      localDocuments: () => List<ToolkitCloudLocalDocument>.of(local),
      restoreOne: _restoreOne,
      removeLocal: (id) async {
        removedLocally.add(id);
        local.removeWhere((d) => d.documentId == id);
      },
      onChanged: () => changes++,
    );
  }

  final FakeToolkitTransport transport;
  late final Directory dir;
  late final DefaultToolkitCloudLibrary library;
  late final ToolkitCloudSync sync;

  DateTime now = DateTime.utc(2026, 10, 22, 9);
  final List<ToolkitCloudLocalDocument> local = <ToolkitCloudLocalDocument>[];
  final List<String> removedLocally = <String>[];
  final List<String> restored = <String>[];
  int changes = 0;

  /// A document the tool saved on the phone.
  Future<List<int>> saveOnPhone(String id, {String title = 'Lease'}) async {
    final bytes = pdfBytes();
    await File('${dir.path}/$id').writeAsBytes(bytes);
    local.add(ToolkitCloudLocalDocument(
      documentId: id,
      title: title,
      sizeBytes: bytes.length,
      sourceCreatedAt: DateTime.utc(2026, 10, 19, 8),
      pageCount: 1,
    ));
    return bytes;
  }

  /// A document the account holds (uploaded from another phone).
  List<int> holdInAccount(String id, {String title = 'From another phone'}) {
    final bytes = pdfBytes(128);
    transport.server[id] = FakeServerDoc(
      type: ToolkitDocumentType.scanner,
      title: title,
      size: bytes.length,
      sha: sha(bytes),
    )
      ..status = 'ready'
      ..bytes = Uint8List.fromList(bytes);
    return bytes;
  }

  /// What a tool's store does: take the downloaded file and list it.
  Future<bool> _restoreOne(
    ToolkitDocumentMetadata document,
    ToolkitCloudLibrary lib,
  ) async {
    final target = File('${dir.path}/restore_${document.documentId}');
    final result = await lib.download(document: document, target: target);
    if (result == ToolkitDownloadResult.conflict) return false;
    await target.copy('${dir.path}/${document.documentId}');
    await target.delete();
    local.add(ToolkitCloudLocalDocument(
      documentId: document.documentId,
      title: document.title,
      sizeBytes: document.sizeBytes,
      sourceCreatedAt: document.sourceCreatedAt,
      pageCount: document.pageCount,
    ));
    restored.add(document.documentId);
    return true;
  }

  Future<void> run() async {
    sync.requestSync();
    await sync.settle();
  }

  Future<void> dispose() async {
    await sync.settle();
    sync.dispose();
    await library.shutdown();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void main() {
  final rigs = <Rig>[];
  Rig newRig([FakeToolkitTransport? transport]) {
    final rig = Rig(transport ?? FakeToolkitTransport(accountA));
    rigs.add(rig);
    return rig;
  }

  tearDown(() async {
    for (final rig in rigs) {
      await rig.dispose();
    }
    rigs.clear();
  });

  group('backing up', () {
    test('uploads a document the phone holds and the account lacks', () async {
      final rig = newRig();
      final bytes = await rig.saveOnPhone(doc1);
      await rig.run();
      final stored = rig.transport.server[doc1]!;
      expect(stored.status, 'ready');
      expect(stored.type, ToolkitDocumentType.scanner);
      expect(stored.title, 'Lease');
      expect(stored.sha, sha(bytes));
      final summary = rig.sync.summary();
      expect(summary.saved, 1);
      expect(summary.waiting, 0);
      expect(summary.notice, ToolkitCloudNotice.allSaved);
    });

    test('a document saved offline is recorded at once and uploaded later',
        () async {
      final rig = newRig();
      await rig.saveOnPhone(doc1);
      rig.transport
        ..failNext('listPage', ToolkitFailure.unavailable)
        ..failNext('authorize', ToolkitFailure.unavailable);
      await rig.run();
      // Not in the account, but on the journal: nothing is lost if the app closes.
      expect(rig.transport.server.containsKey(doc1), isFalse);
      expect(rig.library.entryFor(doc1), isNotNull);
      final offline = rig.sync.summary();
      expect(offline.unreachable, isTrue);
      expect(offline.notice, ToolkitCloudNotice.offline);

      // The connection returns and the retry time has passed.
      rig.now = rig.now.add(const Duration(hours: 2));
      await rig.library.syncDue();
      await rig.run();
      expect(rig.transport.server[doc1]!.status, 'ready');
      expect(rig.sync.summary().notice, ToolkitCloudNotice.allSaved);
    });

    test('says why when the server refuses (a gate, or Toolkit routes off)',
        () async {
      for (final failure in <ToolkitFailure>[
        ToolkitFailure.forbidden,
        ToolkitFailure.routeUnavailable,
      ]) {
        final rig = newRig();
        await rig.saveOnPhone(doc1);
        rig.transport
          ..failNext('listPage', failure)
          ..failNext('authorize', failure);
        await rig.run();
        final summary = rig.sync.summary();
        expect(summary.unreachable, isTrue, reason: '$failure');
        expect(summary.failure, failure);
        expect(summary.notice, ToolkitCloudNotice.serverNotReady,
            reason: '$failure');
      }
    });
  });

  group('restoring after a reinstall', () {
    test('brings back what the account holds and the phone lacks', () async {
      final rig = newRig();
      final bytes = rig.holdInAccount(doc1, title: 'Passport');
      expect(rig.local, isEmpty);

      await rig.run();

      expect(rig.restored, [doc1]);
      expect(rig.local.single.title, 'Passport');
      expect(File('${rig.dir.path}/$doc1').readAsBytesSync(), bytes);
      expect(rig.sync.isRestoring, isFalse);
      // The restored document is then recorded and confirmed as already held.
      expect(rig.sync.summary().saved, 1);
      expect(rig.transport.callCount('downloadToFile'), 1);
    });

    test('a document is restored once, however often the account is asked',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      await rig.run();
      await rig.run();
      expect(rig.restored, [doc1]);
      expect(rig.transport.callCount('downloadToFile'), 1);
    });

    test('brings the newest document back first', () async {
      final rig = newRig();
      rig.holdInAccount(doc1, title: 'Old');
      rig.holdInAccount(doc2, title: 'New');
      rig.transport.server[doc1]!.created = DateTime.utc(2026, 10, 1);
      rig.transport.server[doc2]!.created = DateTime.utc(2026, 10, 15);
      await rig.run();
      expect(rig.restored, [doc2, doc1]);
    });

    test('a document that was deleted on another phone is not brought back',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      rig.transport.server[doc1]!.status = 'deleted';
      await rig.run();
      expect(rig.restored, isEmpty);
      expect(rig.local, isEmpty);
    });

    test('an unreachable account is reported, and nothing is invented',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      rig.transport.failNext('listPage', ToolkitFailure.unavailable);
      await rig.run();
      expect(rig.restored, isEmpty);
      expect(rig.sync.summary().notice, ToolkitCloudNotice.offline);
      // The next pass, with the account reachable again, restores it.
      await rig.run();
      expect(rig.restored, [doc1]);
      expect(rig.sync.summary().unreachable, isFalse);
    });
  });

  group('delete and rename', () {
    test('a delete reaches the account first, then the phone may remove it',
        () async {
      final rig = newRig();
      await rig.saveOnPhone(doc1);
      await rig.run();
      expect(rig.transport.server[doc1]!.status, 'ready');

      final split = await rig.sync.deleteFirst(<String>[doc1]);
      expect(split.deleteLocally, [doc1]);
      expect(split.pending, isEmpty);
      expect(split.failed, isEmpty);
      expect(rig.transport.server[doc1]!.status, 'deleted');
    });

    test('a delete that cannot reach the server hides the document and waits',
        () async {
      final rig = newRig();
      await rig.saveOnPhone(doc1);
      await rig.run();
      rig.transport.failNext('remove', ToolkitFailure.unavailable);

      final split = await rig.sync.deleteFirst(<String>[doc1]);
      expect(split.pending, [doc1]);
      expect(split.deleteLocally, isEmpty);
      expect(rig.sync.isDeleting(doc1), isTrue);
      expect(rig.transport.server[doc1]!.status, 'ready');
      expect(rig.removedLocally, isEmpty, reason: 'not confirmed yet');

      // Not restored while it waits, even though the account still holds it.
      rig.local.removeWhere((d) => d.documentId == doc1);
      await rig.run();
      expect(rig.restored, isEmpty);

      // The retry time passes: the server confirms and the phone's copy goes.
      rig.now = rig.now.add(const Duration(hours: 2));
      await rig.library.syncDue();
      await rig.sync.settle();
      expect(rig.transport.server[doc1]!.status, 'deleted');
      expect(rig.removedLocally, [doc1]);
      expect(rig.sync.isDeleting(doc1), isFalse);
    });

    test('a rename reaches the account copy, and never throws', () async {
      final rig = newRig();
      await rig.saveOnPhone(doc1);
      await rig.run();
      await rig.sync.rename(doc1, 'Renamed');
      expect(rig.transport.server[doc1]!.title, 'Renamed');
      // An unreachable account is kept for later, not an error.
      rig.transport.failNext('rename', ToolkitFailure.unavailable);
      await rig.sync.rename(doc1, 'Again');
    });
  });

  group('what the user is told', () {
    test('the cloud off says nothing', () {
      expect(ToolkitCloudSummary.off.notice, isNull);
    });

    test('an account with nothing in it says nothing', () {
      expect(const ToolkitCloudSummary(enabled: true).notice, isNull);
    });

    test('each failure has one sentence', () {
      const cases = <ToolkitFailure, ToolkitCloudNotice>{
        ToolkitFailure.unavailable: ToolkitCloudNotice.offline,
        ToolkitFailure.interrupted: ToolkitCloudNotice.offline,
        ToolkitFailure.sessionSuperseded: ToolkitCloudNotice.signInAgain,
        ToolkitFailure.unauthorized: ToolkitCloudNotice.signInAgain,
        ToolkitFailure.forbidden: ToolkitCloudNotice.serverNotReady,
        ToolkitFailure.routeUnavailable: ToolkitCloudNotice.serverNotReady,
        ToolkitFailure.notConfigured: ToolkitCloudNotice.serverNotReady,
        ToolkitFailure.tooLarge: ToolkitCloudNotice.overLimit,
        ToolkitFailure.storageLimit: ToolkitCloudNotice.overLimit,
        ToolkitFailure.typeMismatch: ToolkitCloudNotice.attention,
      };
      cases.forEach((failure, notice) {
        expect(ToolkitCloudSummary.noticeForFailure(failure), notice,
            reason: '$failure');
      });
    });

    test('restoring wins, then a problem, then waiting, then all saved', () {
      expect(
          const ToolkitCloudSummary(
                  enabled: true, restoring: true, waiting: 2, saved: 1)
              .notice,
          ToolkitCloudNotice.restoring);
      expect(
          const ToolkitCloudSummary(
                  enabled: true,
                  unreachable: true,
                  failure: ToolkitFailure.forbidden,
                  saved: 3)
              .notice,
          ToolkitCloudNotice.serverNotReady);
      expect(const ToolkitCloudSummary(enabled: true, waiting: 2).notice,
          ToolkitCloudNotice.waiting);
      expect(const ToolkitCloudSummary(enabled: true, rejected: 1).notice,
          ToolkitCloudNotice.attention);
      expect(const ToolkitCloudSummary(enabled: true, saved: 4).notice,
          ToolkitCloudNotice.allSaved);
    });
  });
}
