// Images to PDF with the documents the user's account holds: after a reinstall a
// PDF that only the account has is listed from its metadata, with no download,
// and a list the account could not give is never shown as an empty library.
// The server is the in-memory fake behind the transport seam; the view model, its
// store and the files are the real ones. (Fetching a file on open is covered by
// the shared object's tests and by the Scanner and Combine PDFs tests.)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

import '../toolkit_documents/toolkit_fakes.dart'
    show FakeServerDoc, FakeToolkitTransport, doc1, pdfBytes, sha;
import 'image_pdf_harness.dart';

Future<void> waitFor(bool Function() done, {String what = 'condition'}) async {
  for (var i = 0; i < 500; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('timed out waiting for $what');
}

void main() {
  final harnesses = <ImagePdfHarness>[];

  tearDown(() async {
    for (final h in harnesses) {
      await h.dispose();
    }
    harnesses.clear();
  });

  /// A phone for account `user-a` whose cloud is [transport].
  ImagePdfHarness make(FakeToolkitTransport transport) {
    late ImagePdfHarness harness;
    harness = ImagePdfHarness(
      cloudFactory: (accountId, files) => DefaultToolkitCloudLibrary(
        accountId: accountId,
        transport: transport,
        journal: InMemoryToolkitSyncJournal(),
        files: files,
        currentAccountId: () => harness.user,
      ),
    );
    harnesses.add(harness);
    return harness;
  }

  void hold(FakeToolkitTransport transport, String id, String title) {
    final bytes = pdfBytes(128);
    transport.server[id] = FakeServerDoc(
      type: ToolkitDocumentType.imageToPdf,
      title: title,
      size: bytes.length,
      sha: sha(bytes),
    )
      ..status = 'ready'
      ..bytes = Uint8List.fromList(bytes);
  }

  test('a PDF only the account holds is listed without being downloaded',
      () async {
    final transport = FakeToolkitTransport('user-a');
    hold(transport, doc1, 'Passport');
    final h = make(transport);
    await h.viewModel.start();
    await waitFor(() => h.viewModel.documents.isNotEmpty, what: 'the card');

    final listed = h.viewModel.documents.single;
    expect(listed.id, doc1);
    expect(listed.name, 'Passport');
    expect(h.viewModel.isCloudOnly(doc1), isTrue);
    expect(h.viewModel.isMissing(doc1), isFalse);
    expect(h.viewModel.loadFailed, isFalse);
    expect(transport.callCount('downloadToFile'), 0);
  });

  test('a list that could not be read is not shown as an empty library',
      () async {
    final transport = FakeToolkitTransport('user-a')
      ..failNext('listPage', ToolkitFailure.unavailable);
    final h = make(transport);
    await h.viewModel.start();
    await waitFor(() => h.viewModel.libraryUnavailable,
        what: 'the failed list');

    expect(h.viewModel.documents, isEmpty);
    expect(h.viewModel.isLoading, isFalse);
    expect(h.viewModel.loadFailed, isTrue);

    await h.viewModel.refresh();
    await waitFor(() => !h.viewModel.loadFailed, what: 'the retry');
  });

  test('a PDF only the account holds can be renamed and deleted there',
      () async {
    final transport = FakeToolkitTransport('user-a');
    hold(transport, doc1, 'Passport');
    final h = make(transport);
    await h.viewModel.start();
    await waitFor(() => h.viewModel.documents.isNotEmpty, what: 'the card');

    expect(await h.viewModel.rename(doc1, 'Contract'), isNull);
    expect(transport.server[doc1]!.title, 'Contract');
    expect(h.viewModel.documents.single.name, 'Contract');

    expect(await h.viewModel.delete(<String>[doc1]), isEmpty);
    expect(transport.server[doc1]!.status, 'deleted');
    expect(h.viewModel.documents, isEmpty);
    expect(transport.callCount('downloadToFile'), 0);
  });
}
