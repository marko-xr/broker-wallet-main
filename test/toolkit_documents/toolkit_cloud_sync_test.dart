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
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_remote_cache.dart';

import 'toolkit_fakes.dart';

/// One tool's phone side (a list of documents and their files) wired to the
/// account copy.
class Rig {
  Rig(this.transport, {ToolkitRemoteCache? cache}) {
    dir = Directory.systemTemp.createTempSync('toolkit_sync_rig_');
    library = DefaultToolkitCloudLibrary(
      accountId: accountA,
      transport: transport,
      journal: InMemoryToolkitSyncJournal(),
      files: TempLocalFiles(dir),
      currentAccountId: () => accountA,
      clock: () => now,
      remoteCache: cache,
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
  Rig newRig([FakeToolkitTransport? transport, ToolkitRemoteCache? cache]) {
    final rig = Rig(transport ?? FakeToolkitTransport(accountA), cache: cache);
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

  group('listing and opening after a reinstall', () {
    test('lists what the account holds without downloading anything', () async {
      final rig = newRig();
      rig.holdInAccount(doc1, title: 'Passport');
      expect(rig.local, isEmpty);

      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.notAsked);
      await rig.run();

      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded);
      final listed = rig.sync.remoteOnly;
      expect(listed.single.documentId, doc1);
      expect(listed.single.title, 'Passport');
      expect(rig.sync.isRemoteOnly(doc1), isTrue);
      // The card needs no file: nothing was fetched or stored.
      expect(rig.restored, isEmpty);
      expect(rig.local, isEmpty);
      expect(rig.transport.callCount('downloadTicket'), 0);
      expect(rig.transport.callCount('downloadToFile'), 0);
    });

    test('opening a listed document downloads, verifies and stores it once',
        () async {
      final rig = newRig();
      final bytes = rig.holdInAccount(doc1, title: 'Passport');
      await rig.run();

      final result = await rig.sync.ensureLocal(doc1);

      expect(result, ToolkitEnsureResult.ready);
      expect(rig.restored, [doc1]);
      expect(rig.local.single.title, 'Passport');
      expect(File('${rig.dir.path}/$doc1').readAsBytesSync(), bytes);
      expect(rig.sync.isFetching, isFalse);
      // It is an ordinary phone document now, and no longer a listed-only one.
      expect(rig.sync.isRemoteOnly(doc1), isFalse);
      expect(rig.sync.remoteOnly, isEmpty);
      // The next pass records it and the server confirms it as already held.
      await rig.run();
      await rig.run();
      expect(rig.sync.summary().saved, 1);
      expect(rig.restored, [doc1]);
      expect(rig.transport.callCount('downloadToFile'), 1);
    });

    test('two requests for one document share one download', () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      final results = await Future.wait(<Future<ToolkitEnsureResult>>[
        rig.sync.ensureLocal(doc1),
        rig.sync.ensureLocal(doc1),
      ]);
      expect(results, everyElement(ToolkitEnsureResult.ready));
      expect(rig.restored, [doc1]);
      expect(rig.transport.callCount('downloadToFile'), 1);
    });

    test('lists the newest document first', () async {
      final rig = newRig();
      rig.holdInAccount(doc1, title: 'Old');
      rig.holdInAccount(doc2, title: 'New');
      rig.transport.server[doc1]!.created = DateTime.utc(2026, 10, 1);
      rig.transport.server[doc2]!.created = DateTime.utc(2026, 10, 15);
      await rig.run();
      expect(rig.sync.remoteOnly.map((d) => d.documentId), [doc2, doc1]);
    });

    test('a failed download keeps the document listed and opening retries',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      rig.transport.failNext('downloadToFile', ToolkitFailure.unavailable);

      expect(await rig.sync.ensureLocal(doc1), ToolkitEnsureResult.unavailable);
      expect(rig.sync.isRemoteOnly(doc1), isTrue, reason: 'still listed');
      expect(rig.restored, isEmpty);
      expect(rig.local, isEmpty);

      expect(await rig.sync.ensureLocal(doc1), ToolkitEnsureResult.ready);
      expect(rig.restored, [doc1]);
    });

    test('a download that does not verify is never stored', () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      final tampered = Uint8List.fromList(pdfBytes(128));
      tampered[40] ^= 1;
      rig.transport.downloadOverride = tampered;

      expect(await rig.sync.ensureLocal(doc1), ToolkitEnsureResult.unavailable);
      expect(rig.restored, isEmpty);
      expect(rig.sync.isRemoteOnly(doc1), isTrue);
    });

    test('a document deleted on another phone drops off when it is opened',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      rig.transport.server[doc1]!.status = 'deleted';

      expect(await rig.sync.ensureLocal(doc1), ToolkitEnsureResult.gone);
      expect(rig.sync.isRemoteOnly(doc1), isFalse);
      expect(rig.sync.remoteOnly, isEmpty);
      expect(rig.restored, isEmpty);
    });

    test('a document deleted on another phone is not listed at all', () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      rig.transport.server[doc1]!.status = 'deleted';
      await rig.run();
      expect(rig.sync.remoteOnly, isEmpty);
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded);
    });

    test('an unreachable account is "unavailable", never an empty library',
        () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      rig.transport.failNext('listPage', ToolkitFailure.unavailable);
      await rig.run();
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.unavailable);
      expect(rig.sync.remoteOnly, isEmpty);
      expect(rig.sync.summary().notice, ToolkitCloudNotice.offline);
      // The next pass, with the account reachable again, lists it.
      await rig.run();
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded);
      expect(rig.sync.remoteOnly.single.documentId, doc1);
      expect(rig.sync.summary().unreachable, isFalse);
    });

    test('a list that fails after a good one keeps an empty account empty',
        () async {
      final rig = newRig();
      await rig.run();
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded);
      expect(rig.sync.remoteOnly, isEmpty);

      rig.transport.failNext('listPage', ToolkitFailure.unavailable);
      await rig.run();
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded,
          reason: 'the last answer was "nothing", and it is still the answer');
      expect(rig.sync.summary().unreachable, isTrue);
    });

    test('the last list is shown at once and stays when the account is down',
        () async {
      final cache = InMemoryToolkitRemoteCache();
      final first = newRig(null, cache);
      first.holdInAccount(doc1, title: 'Passport');
      await first.run();
      expect((await cache.read(ToolkitDocumentType.scanner)).single.title,
          'Passport');

      // A later visit (or the reinstalled app's second launch) with no network.
      final transport = FakeToolkitTransport(accountA)
        ..failNext('listPage', ToolkitFailure.unavailable, times: 3);
      final second = newRig(transport, cache);
      second.sync.start();
      await second.sync.settle();
      expect(second.sync.remoteStatus, ToolkitRemoteStatus.notAsked);
      expect(second.sync.remoteOnly.single.title, 'Passport');

      await second.run();
      expect(second.sync.remoteStatus, ToolkitRemoteStatus.unavailable);
      expect(second.sync.remoteOnly.single.title, 'Passport',
          reason: 'a failed list never empties the cards already shown');
    });

    test('a card shown from the last list can still be deleted for real',
        () async {
      final cache = InMemoryToolkitRemoteCache();
      final first = newRig(null, cache);
      final transport = first.transport;
      first.holdInAccount(doc1);
      await first.run();

      // Same account and server, a new screen that has not listed yet.
      final second = Rig(transport, cache: cache);
      rigs.add(second);
      second.sync.start();
      await second.sync.settle();
      expect(second.sync.remoteOnly.single.documentId, doc1);

      final split = await second.sync.deleteFirst(<String>[doc1]);
      expect(split.deleteLocally, [doc1]);
      expect(transport.server[doc1]!.status, 'deleted');
    });

    test('a failed status lookup does not hide the account\'s documents',
        () async {
      final rig = newRig();
      await rig.saveOnPhone(doc1);
      rig.holdInAccount(doc2, title: 'From another phone');
      rig.transport
        ..failNext('authorize', ToolkitFailure.unavailable, times: 5)
        ..failNext('statuses', ToolkitFailure.unavailable, times: 5);
      await rig.run();
      expect(rig.sync.remoteStatus, ToolkitRemoteStatus.loaded);
      expect(rig.sync.remoteOnly.map((d) => d.documentId), [doc2]);
    });

    test('a listed document can be renamed in the account', () async {
      final rig = newRig();
      rig.holdInAccount(doc1, title: 'Old name');
      await rig.run();
      expect(await rig.sync.renameRemoteOnly(doc1, 'New name'), isTrue);
      expect(rig.transport.server[doc1]!.title, 'New name');
      expect(rig.sync.remoteOnly.single.title, 'New name');

      rig.transport.failNext('rename', ToolkitFailure.unavailable);
      expect(await rig.sync.renameRemoteOnly(doc1, 'Another'), isFalse);
      expect(rig.sync.remoteOnly.single.title, 'New name');
    });

    test('a deleted listed document stops being listed', () async {
      final rig = newRig();
      rig.holdInAccount(doc1);
      await rig.run();
      final split = await rig.sync.deleteFirst(<String>[doc1]);
      expect(split.deleteLocally, [doc1]);
      rig.sync.removeRemoteOnly(split.deleteLocally);
      expect(rig.sync.remoteOnly, isEmpty);
      expect(rig.transport.server[doc1]!.status, 'deleted');
    });
  });

  group('merging the account\'s documents among the phone\'s', () {
    ToolkitDocumentMetadata remote(String id, DateTime created) =>
        ToolkitDocumentMetadata(
          documentId: id,
          type: ToolkitDocumentType.scanner,
          contentType: ToolkitContentType.pdf,
          title: 'r-$id',
          sizeBytes: 10,
          contentSha256: 'a' * 64,
          sourceCreatedAt: created,
          createdAt: created,
          version: 1,
        );

    List<String> merge(
        List<(String, DateTime)> local, List<ToolkitDocumentMetadata> remote) {
      return mergeToolkitDocuments<(String, DateTime)>(
        local: local,
        remote: remote,
        idOf: (d) => d.$1,
        createdAtOf: (d) => d.$2,
        fromRemote: (m) => (m.documentId, m.sourceCreatedAt),
      ).map((d) => d.$1).toList();
    }

    test('nothing to add leaves the phone\'s list exactly as it is', () {
      final local = [
        ('b', DateTime.utc(2026, 10, 2)),
        ('a', DateTime.utc(2026, 10, 3))
      ];
      final merged = mergeToolkitDocuments<(String, DateTime)>(
        local: local,
        remote: const <ToolkitDocumentMetadata>[],
        idOf: (d) => d.$1,
        createdAtOf: (d) => d.$2,
        fromRemote: (m) => (m.documentId, m.sourceCreatedAt),
      );
      expect(identical(merged, local), isTrue);
    });

    test('keeps the phone\'s order and places each by date, newest first', () {
      expect(
        merge(
          [
            ('l1', DateTime.utc(2026, 10, 20)),
            ('l2', DateTime.utc(2026, 10, 10)),
            ('l3', DateTime.utc(2026, 10, 1)),
          ],
          [
            remote('r1', DateTime.utc(2026, 10, 25)),
            remote('r2', DateTime.utc(2026, 10, 15)),
            remote('r3', DateTime.utc(2026, 9, 1)),
          ],
        ),
        ['r1', 'l1', 'r2', 'l2', 'l3', 'r3'],
      );
    });

    test('a tie on the date is broken by id, as the stores do', () {
      expect(
        merge(
          [('b', DateTime.utc(2026, 10, 1))],
          [
            remote('a', DateTime.utc(2026, 10, 1)),
            remote('c', DateTime.utc(2026, 10, 1))
          ],
        ),
        ['a', 'b', 'c'],
      );
    });

    test('an empty phone lists the account\'s documents alone', () {
      expect(
        merge(const [], [remote('x', DateTime.utc(2026, 10, 2))]),
        ['x'],
      );
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
