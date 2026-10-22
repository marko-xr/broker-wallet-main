// Write-once signed PUT, seen from the upload coordinator: the signed header reaches the transport, an
// object that is already stored is never replaced, and the confirm - not the PUT - decides what happens
// next. Against the scripted in-memory server in toolkit_fakes.dart (a model, not R2).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';

import 'toolkit_fakes.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test('the signed header from authorize reaches the PUT', () async {
    await h.add(doc1);
    expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.synced);
    expect(h.transport.lastUploadHeaders, {'If-None-Match': '*'});
  });

  test(
      'lost PUT answer: the object is already stored, the retried PUT keeps it and the confirm completes',
      () async {
    await h.add(doc1);
    final local = await h.files.fileFor('$doc1.pdf').readAsBytes();
    // The first attempt's PUT arrived; the device never saw the answer.
    h.transport.server[doc1] = FakeServerDoc(
        type: ToolkitDocumentType.scanner,
        title: 'Doc',
        size: local.length,
        sha: sha(local))
      ..bytes = Uint8List.fromList(local);
    final stored = h.transport.server[doc1]!.bytes;

    expect(await h.coordinator.sync(doc1), ToolkitSyncOutcome.synced);
    expect(identical(h.transport.server[doc1]!.bytes, stored), isTrue,
        reason: 'write-once: the stored object was not replaced');
    expect(h.transport.calls, ['authorize', 'uploadBytes', 'confirm']);
    expect(h.coordinator.entryFor(doc1)!.isCloudConfirmed, isTrue);
  });

  test('a ready document is never uploaded again (lost confirm answer)',
      () async {
    await h.add(doc1);
    h.transport.loseConfirmResponse = true;
    await h.coordinator.sync(doc1);
    expect(h.transport.server[doc1]!.status, 'ready');
    h.transport.calls.clear();
    expect(await h.coordinator.sync(doc1, manual: true),
        ToolkitSyncOutcome.synced);
    expect(h.transport.callCount('uploadBytes'), 0,
        reason: 'the server said it is already in the cloud');
  });

  test('a rejected confirm after an existing object is retried, not saved',
      () async {
    await h.add(doc1);
    final local = await h.files.fileFor('$doc1.pdf').readAsBytes();
    h.transport.server[doc1] = FakeServerDoc(
        type: ToolkitDocumentType.scanner,
        title: 'Doc',
        size: local.length,
        sha: sha(local))
      ..bytes = Uint8List.fromList(local);
    h.transport.failNext('confirm', ToolkitFailure.uploadRejected);
    final outcome = await h.coordinator.sync(doc1);
    expect(outcome, ToolkitSyncOutcome.retryScheduled);
    expect(h.coordinator.entryFor(doc1)!.isCloudConfirmed, isFalse);
  });
}
