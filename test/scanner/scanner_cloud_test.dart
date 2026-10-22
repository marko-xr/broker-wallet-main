// The Scanner with the user's account copy (the same object every Toolkit tool
// uses): a saved scan is uploaded and confirmed, comes back on a new phone after
// a reinstall (same account, empty phone folder), is deleted from the account
// before the phone's file goes, and says why when the account cannot be used.
// The server is the in-memory fake behind the transport seam; the store, the view
// model and the files are the real ones.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';

import '../toolkit_documents/toolkit_fakes.dart';
import 'scanner_harness.dart';

void main() {
  final harnesses = <Harness>[];

  Harness newHarness() {
    final h = Harness();
    harnesses.add(h);
    return h;
  }

  tearDown(() async {
    for (final h in harnesses) {
      await h.close();
    }
    harnesses.clear();
  });

  /// The cloud factory of a phone: [transport] is the one account's server.
  ScannerCloudFactory cloudFor(Harness h, FakeToolkitTransport transport) {
    return (accountId, files) => DefaultToolkitCloudLibrary(
          accountId: accountId,
          transport: transport,
          journal: InMemoryToolkitSyncJournal(),
          files: files,
          currentAccountId: () => h.uid,
        );
  }

  Future<ScannerDocument> saveScan(
      Harness h, ScannerViewModel vm, String name) async {
    final path = await h.pdf(2, name);
    h.engine.handler = (_) => <String>[path];
    final start = await scanOnce(vm);
    expect(start.draft, isNotNull);
    final saved = await vm.saveDraft(name);
    expect(saved.isSaved, isTrue);
    return saved.documents.single;
  }

  File storedFile(Harness h, ScannerDocument document) => File(
      p.join(h.base.path, 'scanner', 'user-a', 'files', document.fileName));

  test('a saved scan is uploaded and confirmed', () async {
    final transport = FakeToolkitTransport('user-a');
    final h = newHarness();
    final vm = await h.started(cloudFactory: cloudFor(h, transport));

    final scan = await saveScan(h, vm, 'Lease');
    await vm.settle();

    final stored = transport.server[scan.id]!;
    expect(stored.status, 'ready');
    expect(stored.type, ToolkitDocumentType.scanner);
    expect(stored.title, 'Lease');
    expect(vm.cloudSummary.saved, 1);
    expect(vm.cloudSummary.notice, ToolkitCloudNotice.allSaved);
  });

  test('after a reinstall the account\'s scans are listed and open on demand',
      () async {
    final transport = FakeToolkitTransport('user-a');
    final first = newHarness();
    final vm1 = await first.started(cloudFactory: cloudFor(first, transport));
    final original = await saveScan(first, vm1, 'Lease');
    final originalBytes = storedFile(first, original).readAsBytesSync();
    await vm1.settle();
    expect(transport.server[original.id]!.status, 'ready');

    // A new phone folder, the same account.
    final second = newHarness();
    final vm2 = await second.started(cloudFactory: cloudFor(second, transport));
    await settle(() => vm2.documents.isNotEmpty);
    await vm2.settle();

    // The card is there from the account's metadata alone: no file yet.
    final listed = vm2.documents.single;
    expect(listed.id, original.id);
    expect(listed.name, 'Lease');
    expect(listed.pageCount, 2);
    expect(vm2.isCloudOnly(listed.id), isTrue);
    expect(vm2.isMissing(listed.id), isFalse);
    expect(storedFile(second, listed).existsSync(), isFalse);
    expect(transport.callCount('downloadToFile'), 0);

    // Opening it downloads, verifies and stores it; it is one card throughout.
    final file = await vm2.openableFile(listed);
    expect(file, isNotNull);
    expect(file!.readAsBytesSync(), originalBytes);
    expect(vm2.isCloudOnly(listed.id), isFalse);
    expect(vm2.documents.single.id, original.id);
    await vm2.settle();
    expect(vm2.cloudSummary.notice, ToolkitCloudNotice.allSaved);
    expect(transport.callCount('downloadToFile'), 1);
  });

  test('a library that could not be read is not shown as an empty one',
      () async {
    final transport = FakeToolkitTransport('user-a')
      ..failNext('listPage', ToolkitFailure.unavailable);
    final h = newHarness();
    final vm = await h.started(cloudFactory: cloudFor(h, transport));
    await settle(() => vm.libraryUnavailable);

    expect(vm.documents, isEmpty);
    expect(vm.isLoading, isFalse);
    expect(vm.loadFailed, isTrue);

    // Retry (the screen's button) with the account reachable again.
    await vm.refresh();
    await vm.settle();
    expect(vm.libraryUnavailable, isFalse);
    expect(vm.loadFailed, isFalse);
  });

  test('a failed download keeps the card and says it could not be fetched',
      () async {
    final transport = FakeToolkitTransport('user-a');
    final first = newHarness();
    final vm1 = await first.started(cloudFactory: cloudFor(first, transport));
    final original = await saveScan(first, vm1, 'Lease');
    await vm1.settle();

    final second = newHarness();
    final vm2 = await second.started(cloudFactory: cloudFor(second, transport));
    await settle(() => vm2.documents.isNotEmpty);
    await vm2.settle();
    transport.failNext('downloadToFile', ToolkitFailure.unavailable);

    expect(await vm2.openableFile(vm2.documents.single), isNull);
    expect(vm2.lastOpenFailure, ToolkitEnsureResult.unavailable);
    expect(vm2.documents.single.id, original.id, reason: 'still listed');
    expect(vm2.isCloudOnly(original.id), isTrue);

    // Opening it again works.
    expect(await vm2.openableFile(vm2.documents.single), isNotNull);
    expect(vm2.lastOpenFailure, isNull);
  });

  test('a scan that is only in the account can be shared, renamed and deleted',
      () async {
    final transport = FakeToolkitTransport('user-a');
    final first = newHarness();
    final vm1 = await first.started(cloudFactory: cloudFor(first, transport));
    final original = await saveScan(first, vm1, 'Lease');
    await vm1.settle();

    final second = newHarness();
    final vm2 = await second.started(cloudFactory: cloudFor(second, transport));
    await settle(() => vm2.documents.isNotEmpty);
    await vm2.settle();

    // Renamed in the account without fetching the file.
    expect(await vm2.rename(original.id, 'Contract'), isNull);
    expect(transport.server[original.id]!.title, 'Contract');
    expect(vm2.documents.single.name, 'Contract');
    expect(vm2.isCloudOnly(original.id), isTrue);
    expect(transport.callCount('downloadToFile'), 0);

    // Shared from a verified file on the phone, never a link.
    final shared = await vm2.prepareShare(<String>[original.id]);
    expect(shared.unavailable, isEmpty);
    expect(shared.paths, hasLength(1));
    expect(vm2.isCloudOnly(original.id), isFalse);

    // And a card that was never fetched is deleted from the account.
    await vm2.settle();
    final third = newHarness();
    final vm3 = await third.started(cloudFactory: cloudFor(third, transport));
    await settle(() => vm3.documents.isNotEmpty);
    expect(await vm3.delete(<String>[original.id]), isEmpty);
    expect(transport.server[original.id]!.status, 'deleted');
    expect(vm3.documents, isEmpty);
  });

  test('a delete reaches the account first, then the phone\'s file goes',
      () async {
    final transport = FakeToolkitTransport('user-a');
    final h = newHarness();
    final vm = await h.started(cloudFactory: cloudFor(h, transport));
    final scan = await saveScan(h, vm, 'Lease');
    await vm.settle();
    expect(transport.server[scan.id]!.status, 'ready');

    expect(await vm.delete(<String>[scan.id]), isEmpty);

    expect(transport.server[scan.id]!.status, 'deleted');
    expect(vm.documents, isEmpty);
    expect(storedFile(h, scan).existsSync(), isFalse);
  });

  test('a delete the server cannot confirm hides the scan and keeps its file',
      () async {
    final transport = FakeToolkitTransport('user-a');
    final h = newHarness();
    final vm = await h.started(cloudFactory: cloudFor(h, transport));
    final scan = await saveScan(h, vm, 'Lease');
    await vm.settle();
    transport.failNext('remove', ToolkitFailure.unavailable);

    expect(await vm.delete(<String>[scan.id]), isEmpty);

    expect(vm.documents, isEmpty, reason: 'no longer listed');
    expect(storedFile(h, scan).existsSync(), isTrue, reason: 'not confirmed');
    expect(transport.server[scan.id]!.status, 'ready');
  });

  test('says why the account cannot be used, and keeps the scan', () async {
    final transport = FakeToolkitTransport('user-a');
    final h = newHarness();
    final vm = await h.started(cloudFactory: cloudFor(h, transport));
    await vm.settle();
    transport
      ..failNext('listPage', ToolkitFailure.routeUnavailable, times: 4)
      ..failNext('authorize', ToolkitFailure.routeUnavailable, times: 4);

    final scan = await saveScan(h, vm, 'Lease');
    await vm.settle();

    expect(vm.documents.single.id, scan.id);
    expect(storedFile(h, scan).existsSync(), isTrue);
    expect(vm.cloudSummary.notice, ToolkitCloudNotice.serverNotReady);
  });

  test('a build without the account copy behaves exactly as before', () async {
    final h = newHarness();
    final vm = await h.started();
    final scan = await saveScan(h, vm, 'Lease');
    expect(vm.documents.single.id, scan.id);
    expect(vm.cloudSummary.notice, isNull);
    expect(vm.cloudSummary.enabled, isFalse);
    expect(await vm.delete(<String>[scan.id]), isEmpty);
    expect(vm.documents, isEmpty);
  });
}
