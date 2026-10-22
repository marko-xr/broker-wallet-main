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

  test('after a reinstall the account\'s scans come back', () async {
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

    final restored = vm2.documents.single;
    expect(restored.id, original.id);
    expect(restored.name, 'Lease');
    expect(restored.pageCount, 2);
    final file = await vm2.openableFile(restored);
    expect(file, isNotNull);
    expect(file!.readAsBytesSync(), originalBytes);
    expect(vm2.cloudSummary.notice, ToolkitCloudNotice.allSaved);
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
