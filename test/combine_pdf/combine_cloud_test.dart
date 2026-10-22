// Combine PDFs with the account's cloud copy (checkpoint C3): a combined PDF is
// kept on the phone first, uploaded and confirmed afterwards, and listed, opened,
// renamed and deleted through the same library after a "reinstall" (a new phone
// folder with the same account). The server is the in-memory fake behind the
// transport seam; the files, the store and the view model are the real ones.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

import '../toolkit_documents/toolkit_fakes.dart';
import 'combine_fixtures.dart';

Future<void> waitFor(bool Function() done, {String what = 'condition'}) async {
  for (var i = 0; i < 500; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('timed out waiting for $what');
}

void main() {
  final harnesses = <CombineHarness>[];
  var now = DateTime.utc(2026, 10, 22, 9);

  tearDown(() async {
    for (final h in harnesses) {
      await h.dispose();
    }
    harnesses.clear();
    now = DateTime.utc(2026, 10, 22, 9);
  });

  /// A Combine screen's logic wired to [transport] as its cloud, for [user].
  CombineHarness make(
    FakeToolkitTransport transport, {
    String user = accountA,
    List<DefaultToolkitCloudLibrary>? libraries,
  }) {
    late CombineHarness harness;
    var counter = 0;
    harness = CombineHarness(
      initialUser: user,
      idGenerator: () =>
          'a0000000-0000-4000-8000-${(counter++).toString().padLeft(12, '0')}',
      cloudFactory: (accountId, store, files) {
        final library = DefaultToolkitCloudLibrary(
          accountId: accountId,
          transport: transport,
          journal: InMemoryToolkitSyncJournal(),
          files: files,
          currentAccountId: () => harness.user,
          clock: () => now,
        );
        libraries?.add(library);
        return library;
      },
    );
    harnesses.add(harness);
    return harness;
  }

  Future<CombinedPdf> combineOne(CombineHarness h) async {
    await h.add([
      await h.pdf('a.pdf', 'A'),
      await h.pdf('b.pdf', 'B', count: 2),
    ]);
    final outcome = await h.combine(name: 'Lease pack');
    expect(outcome.isDone, isTrue);
    return outcome.document!;
  }

  bool saved(CombineHarness h, String id) =>
      h.viewModel.cloudStateOf(id) == ToolkitDocumentSyncState.savedToCloud;

  test('a build without the cloud keeps the tool exactly local', () async {
    final h = CombineHarness();
    harnesses.add(h);
    await h.viewModel.start();
    final doc = await combineOne(h);
    expect(h.viewModel.cloudEnabled, isFalse);
    expect(h.viewModel.cloudStateOf(doc.id), isNull);
    expect(h.viewModel.documents, hasLength(1));
  });

  group('saving', () {
    test('is saved on the phone, then uploaded and confirmed', () async {
      final transport = FakeToolkitTransport(accountA);
      final h = make(transport);
      await h.viewModel.start();
      expect(h.viewModel.cloudEnabled, isTrue);

      final doc = await combineOne(h);
      // The phone's copy exists whatever the cloud does.
      final local = await h.viewModel.openableFile(doc);
      expect(local, isNotNull);

      await waitFor(() => saved(h, doc.id), what: 'cloud confirmation');
      final stored = transport.server[doc.id]!;
      expect(stored.status, 'ready');
      expect(stored.type, ToolkitDocumentType.combinePdfs);
      expect(stored.title, 'Lease pack');
      expect(stored.sha, ToolkitSha256.hexOfBytes(local!.readAsBytesSync()));
    });

    test('while the cloud is unreachable it stays local and says so', () async {
      final transport = FakeToolkitTransport(accountA);
      transport.failNext('authorize', ToolkitFailure.unavailable);
      final h = make(transport);
      await h.viewModel.start();

      final doc = await combineOne(h);
      await waitFor(
        () =>
            h.viewModel.cloudStateOf(doc.id) ==
            ToolkitDocumentSyncState.syncFailedRetryable,
        what: 'a retryable failure',
      );
      expect(saved(h, doc.id), isFalse);
      expect(transport.server.containsKey(doc.id), isFalse);
      expect(await h.viewModel.openableFile(doc), isNotNull);

      expect(h.viewModel.canRetryBackup(doc.id), isTrue);
      await h.viewModel.retryBackup(doc.id);
      await waitFor(() => saved(h, doc.id), what: 'the retry to confirm');
      expect(transport.server[doc.id]!.status, 'ready');
    });
  });

  group('after a reinstall (same account, empty phone)', () {
    test('lists the document, downloads it once, and verifies it', () async {
      final transport = FakeToolkitTransport(accountA);
      final first = make(transport);
      await first.viewModel.start();
      final original = await combineOne(first);
      await waitFor(() => saved(first, original.id));
      final originalBytes =
          (await first.viewModel.openableFile(original))!.readAsBytesSync();

      final second = make(transport);
      await second.viewModel.start();
      await waitFor(
        () => second.viewModel.documents.any((d) => d.id == original.id),
        what: 'the cloud document to be listed',
      );
      final listed = second.viewModel.documents.single;
      expect(listed.name, 'Lease pack');
      expect(second.viewModel.cloudStateOf(listed.id),
          ToolkitDocumentSyncState.downloadRequired);
      expect(transport.downloadCalls, 0);

      final file = await second.viewModel.openableFile(listed);
      expect(file, isNotNull);
      expect(file!.readAsBytesSync(), originalBytes);
      expect(transport.downloadCalls, 1);
      expect(second.viewModel.documents, hasLength(1));

      // Now an ordinary local document that the cloud confirms; no second download.
      await waitFor(() => saved(second, listed.id), what: 'confirmation');
      expect(
          await second.viewModel
              .openableFile(second.viewModel.documentById(listed.id)!),
          isNotNull);
      expect(transport.downloadCalls, 1);
    });

    test('a corrupted download stores nothing and leaves it listed', () async {
      final transport = FakeToolkitTransport(accountA);
      final first = make(transport);
      await first.viewModel.start();
      final original = await combineOne(first);
      await waitFor(() => saved(first, original.id));

      final second = make(transport);
      await second.viewModel.start();
      await waitFor(
          () => second.viewModel.documents.any((d) => d.id == original.id));
      transport.downloadOverride = Uint8List.fromList(pdfBytes());

      final file = await second.viewModel
          .openableFile(second.viewModel.documents.single);
      expect(file, isNull);
      expect(
          second.viewModel.lastOpenFailure, CombinePdfFailure.cloudUnavailable);
      expect(second.viewModel.cloudStateOf(original.id),
          ToolkitDocumentSyncState.downloadRequired);
      final files = Directory(
          p.join(second.base.path, 'combine_pdfs', accountA, 'files'));
      expect(!files.existsSync() || files.listSync().isEmpty, isTrue);

      // The next attempt, with the real bytes, works.
      transport.downloadOverride = null;
      expect(
          await second.viewModel
              .openableFile(second.viewModel.documents.single),
          isNotNull);
    });

    test('a cloud-only document can be renamed there', () async {
      final transport = FakeToolkitTransport(accountA);
      final first = make(transport);
      await first.viewModel.start();
      final original = await combineOne(first);
      await waitFor(() => saved(first, original.id));

      final second = make(transport);
      await second.viewModel.start();
      await waitFor(
          () => second.viewModel.documents.any((d) => d.id == original.id));
      expect(await second.viewModel.rename(original.id, 'Renamed'), isNull);
      expect(transport.server[original.id]!.title, 'Renamed');
      expect(second.viewModel.documents.single.name, 'Renamed');

      final file = await second.viewModel
          .openableFile(second.viewModel.documents.single);
      expect(file, isNotNull);
      expect(second.viewModel.documentById(original.id)!.name, 'Renamed');
    });

    test('a different account on the same phone sees none of it', () async {
      final transport = FakeToolkitTransport(accountA);
      final first = make(transport);
      await first.viewModel.start();
      final original = await combineOne(first);
      await waitFor(() => saved(first, original.id));

      // The transport belongs to account A: for B the cloud copy is not set up.
      final other = make(transport, user: accountB);
      await other.viewModel.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(other.viewModel.cloudEnabled, isFalse);
      expect(other.viewModel.documents, isEmpty);
    });
  });

  group('rename and delete', () {
    test('a rename on the phone reaches the cloud copy', () async {
      final transport = FakeToolkitTransport(accountA);
      final h = make(transport);
      await h.viewModel.start();
      final doc = await combineOne(h);
      await waitFor(() => saved(h, doc.id));

      expect(await h.viewModel.rename(doc.id, 'Mine'), isNull);
      expect(h.viewModel.documentById(doc.id)!.name, 'Mine');
      expect(transport.server[doc.id]!.title, 'Mine');
    });

    test('a delete removes the cloud copy first, then the phone\'s', () async {
      final transport = FakeToolkitTransport(accountA);
      final h = make(transport);
      await h.viewModel.start();
      final doc = await combineOne(h);
      await waitFor(() => saved(h, doc.id));

      expect(await h.viewModel.delete(<String>[doc.id]), isEmpty);
      expect(transport.server[doc.id]!.status, 'deleted');
      expect(h.viewModel.documents, isEmpty);
      expect(
          File(p.join(h.base.path, 'combine_pdfs', accountA, 'files',
                  '${doc.id}.pdf'))
              .existsSync(),
          isFalse);
    });

    test('a delete made offline keeps the file until the server confirms',
        () async {
      final transport = FakeToolkitTransport(accountA);
      final libraries = <DefaultToolkitCloudLibrary>[];
      final h = make(transport, libraries: libraries);
      await h.viewModel.start();
      final doc = await combineOne(h);
      await waitFor(() => saved(h, doc.id));
      final path = p.join(
          h.base.path, 'combine_pdfs', accountA, 'files', '${doc.id}.pdf');

      transport.failNext('remove', ToolkitFailure.unavailable);
      expect(await h.viewModel.delete(<String>[doc.id]), isEmpty);
      expect(h.viewModel.documents, isEmpty, reason: 'no longer listed');
      expect(File(path).existsSync(), isTrue, reason: 'not confirmed yet');
      expect(transport.server[doc.id]!.status, 'ready');

      // The retry time passes and the journal runs what is due.
      now = now.add(const Duration(hours: 2));
      await libraries.single.syncDue();
      await waitFor(() => !File(path).existsSync(), what: 'the local removal');
      // The file going away is only the middle of the removal: the index is
      // rewritten and the list reloaded after it. Wait for the end of it, so the
      // assertions (and the folder's deletion) never race a write in flight.
      await h.viewModel.settle();
      expect(transport.server[doc.id]!.status, 'deleted');
      expect(h.viewModel.documents, isEmpty);
      expect(libraries.single.entryFor(doc.id), isNull,
          reason: 'the journal forgot the confirmed delete');
    });
  });
}
