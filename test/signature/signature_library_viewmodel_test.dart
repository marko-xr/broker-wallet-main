import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';

import 'signature_fixtures.dart';

void main() {
  late SignatureHarness h;

  tearDown(() async {
    await h.dispose();
  });

  /// Saves one signed document for the current account and returns it.
  Future<SignedDocument> saveOne(String title, {String tag = 'T'}) async {
    final file = await h.pdf('$title.pdf', tag, count: 2);
    final session = await h.session(file, name: '$title.pdf');
    await h.place(session);
    final outcome = await h.save(session, name: title);
    expect(outcome.isDone, isTrue, reason: '${outcome.failure}');
    session.dispose();
    await h.pumpFutures();
    return outcome.document!;
  }

  group('starting', () {
    test('loads the account, keeps the folder out of backup, counts legacy',
        () async {
      h = SignatureHarness(legacyCount: () async => 7);
      await h.viewModel.start();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.isLoading, isFalse);
      expect(h.backup.excluded, [p.join(h.base.path, 'signature_pdfs')]);
      expect(h.viewModel.legacyDocumentCount, 7);
    });

    test('signed out: nothing runs and no picker opens', () async {
      h = SignatureHarness(userId: () => null);
      await h.viewModel.start();
      expect((await h.viewModel.pickAndOpen()).failure,
          SignatureFailure.signedOut);
      expect(h.picker.picks, 0);
      final file = await h.pdf('a.pdf', 'A');
      expect((await h.open(file)).failure, SignatureFailure.signedOut);
      expect(h.usage.recorded, isEmpty);
    });

    test('an auth stream error is not a sign-out', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      await saveOne('Kept');
      h.addAuthError();
      await h.pumpFutures();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.documents, hasLength(1));
    });
  });

  group('opening a PDF', () {
    test(
        'a session opens when the auth stream can be listened to only once, '
        'and the next one opens after it closes', () async {
      // The real auth repository's stream is single-subscription: the library
      // listens to it, and so must every session without a second listen.
      h = SignatureHarness(singleSubscriptionAuth: true);
      await h.viewModel.start();
      final file = await h.pdf('a.pdf', 'A');
      final first = await h.open(file);
      expect(first.failure, isNull, reason: 'the first open');
      expect(h.viewModel.isEditing, isTrue);
      first.session!.dispose();
      await h.pumpFutures();
      expect(h.viewModel.isEditing, isFalse);
      final second = await h.open(file);
      expect(second.failure, isNull, reason: 'the open after closing');
      second.session!.dispose();
    });

    test('a session that cannot be built leaves the library usable', () async {
      // The library listens once (and works); building a session listens again
      // and fails. That is not the file's fault and must not lock the library.
      h = SignatureHarness(authStream: _ListensOnce());
      await h.viewModel.start();
      final file = await h.pdf('a.pdf', 'A');
      final outcome = await h.open(file);
      expect(outcome.failure, SignatureFailure.unexpected);
      expect(h.viewModel.isEditing, isFalse);
      expect(h.viewModel.isBusy, isFalse);
      // Still not blocked: the next try gets the same honest answer, not 'busy'.
      expect((await h.open(file)).failure, SignatureFailure.unexpected);
    });

    test('every problem file is refused with its own reason', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final empty = await writeFile(h.inputs, 'empty.pdf', <int>[]);
      final junk = await writeFile(h.inputs, 'junk.pdf', 'not a pdf'.codeUnits);
      final locked = await writeFile(h.inputs, 'locked.pdf',
          buildPdf('L', userPassword: 'u', ownerPassword: 'o'));
      final signed =
          await writeFile(h.inputs, 'signed.pdf', buildPdf('S', sign: true));
      final apart = await writeFile(h.inputs, 'apart.pdf',
          pdfWithBoxes(media: '[0 0 612 792]', crop: '[700 0 900 100]'));
      Future<SignatureFailure?> failure(PickedSignaturePdf picked) async =>
          (await h.viewModel.openPicked(picked)).failure;

      expect(
          await failure(
              PickedSignaturePdf(path: empty.path, name: 'empty.pdf')),
          SignatureFailure.emptySource);
      expect(
          await failure(PickedSignaturePdf(path: junk.path, name: 'junk.pdf')),
          SignatureFailure.corruptSource);
      expect(
          await failure(
              PickedSignaturePdf(path: locked.path, name: 'locked.pdf')),
          SignatureFailure.encryptedSource);
      expect(
          await failure(
              PickedSignaturePdf(path: signed.path, name: 'signed.pdf')),
          SignatureFailure.signedSource);
      expect(
          await failure(
              PickedSignaturePdf(path: apart.path, name: 'apart.pdf')),
          SignatureFailure.geometryUnsupported);
      expect(
          await failure(PickedSignaturePdf(
              path: p.join(h.inputs.path, 'gone.pdf'), name: 'gone.pdf')),
          SignatureFailure.missingSource);
      expect(
          await failure(const PickedSignaturePdf(path: '', name: 'cloud.pdf')),
          SignatureFailure.missingSource);
      // Nothing was left open or counted, and a good file still opens.
      expect(h.viewModel.isEditing, isFalse);
      expect(h.viewModel.isOpening, isFalse);
      expect(h.usage.recorded, isEmpty);
      final good = await h.pdf('good.pdf', 'G');
      expect((await h.open(good)).session, isNotNull);
    });

    test('a file over the size limit is refused', () async {
      h = SignatureHarness(
          executor: const InlineSignatureExecutor(maxSourceBytes: 100));
      await h.viewModel.start();
      final file = await h.pdf('big.pdf', 'B');
      expect((await h.open(file)).failure, SignatureFailure.tooLargeSource);
    });

    test('a good file starts one session; a second open waits for it',
        () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final file = await h.pdf('lease.pdf', 'L', count: 3);
      final first = await h.open(file, name: 'lease.pdf');
      final session = first.session!;
      expect(session.pageCount, 3);
      expect(session.sourceName, 'lease.pdf');
      expect(h.viewModel.isEditing, isTrue);
      expect(h.viewModel.isBusy, isTrue);
      expect((await h.open(file)).failure, SignatureFailure.busy);
      session.dispose();
      await h.pumpFutures();
      expect(h.viewModel.isEditing, isFalse);
      expect(h.picker.clears, 1,
          reason: 'the picker\'s private copy is removed when editing ends');
      expect((await h.open(file)).session, isNotNull);
    });

    test('the picked file is never written', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final file = await h.pdf('lease.pdf', 'L');
      final before = file.readAsBytesSync();
      final session = await h.session(file);
      await h.place(session);
      await session.buildDraft();
      expect(file.readAsBytesSync(), before);
    });

    test('a cancelled picker opens nothing', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      h.picker.next = null;
      final outcome = await h.viewModel.pickAndOpen();
      expect(outcome.cancelled, isTrue);
      expect(outcome.failure, isNull);
      expect(outcome.session, isNull);
      expect(h.picker.picks, 1);
      expect(h.viewModel.isOpening, isFalse);
    });

    test('a double tap on the picker opens one picker', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final file = await h.pdf('a.pdf', 'A');
      h.picker.gate = Completer<void>();
      h.picker.next = PickedSignaturePdf(path: file.path, name: 'a.pdf');
      final first = h.viewModel.pickAndOpen();
      final second = await h.viewModel.pickAndOpen();
      expect(second.failure, SignatureFailure.busy);
      expect(h.picker.picks, 1);
      h.picker.gate!.complete();
      final outcome = await first;
      expect(outcome.session, isNotNull);
      outcome.session!.dispose();
    });

    test('a pick that finishes for a previous account is dropped', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final file = await h.pdf('a.pdf', 'A');
      h.picker.gate = Completer<void>();
      h.picker.next = PickedSignaturePdf(path: file.path, name: 'a.pdf');
      final running = h.viewModel.pickAndOpen();
      await h.switchTo('user-b');
      h.picker.gate!.complete();
      final outcome = await running;
      expect(outcome.failure, SignatureFailure.accountChanged);
      expect(outcome.session, isNull);
      expect(h.viewModel.isEditing, isFalse);
    });
  });

  group('accounts', () {
    test('each account sees only its own documents, across switches', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final mine = await saveOne('Mine');
      await h.switchTo('user-b');
      expect(h.viewModel.documents, isEmpty);
      final theirs = await saveOne('Theirs', tag: 'U');
      expect(h.viewModel.documents.map((d) => d.id), [theirs.id]);
      await h.switchTo('user-a');
      expect(h.viewModel.documents.map((d) => d.id), [mine.id]);
      await h.switchTo(null);
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.userId, isNull);
      await h.switchTo('user-a');
      expect(h.viewModel.documents.map((d) => d.name), ['Mine']);
    });

    test('a switch clears the selection and the selection mode', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final doc = await saveOne('Mine');
      h.viewModel.enterSelectionMode();
      h.viewModel.toggleSelection(doc.id);
      expect(h.viewModel.selectedCount, 1);
      await h.switchTo('user-b');
      expect(h.viewModel.isSelectionMode, isFalse);
      expect(h.viewModel.selectedCount, 0);
      await h.switchTo('user-a');
      expect(h.viewModel.selectedCount, 0);
    });

    test('the stored folders are separate per account', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      await saveOne('Mine');
      await h.switchTo('user-b');
      await saveOne('Theirs', tag: 'U');
      final root = Directory(p.join(h.base.path, 'signature_pdfs'));
      final names = root.listSync().map((e) => p.basename(e.path)).toList()
        ..sort();
      expect(names, ['user-a', 'user-b']);
    });
  });

  group('the list', () {
    test('newest first, with real counts', () async {
      var tick = 0;
      h = SignatureHarness(
          clock: () => DateTime.utc(2026, 10, 18, 9, 0, tick++));
      await h.viewModel.start();
      await saveOne('First');
      await saveOne('Second');
      final names = h.viewModel.documents.map((d) => d.name).toList();
      expect(names, ['Second', 'First']);
      expect(h.viewModel.documents.first.pageCount, 2);
      expect(h.viewModel.documents.first.signatureCount, 1);
    });

    test('selection follows the document, not its place in the list', () async {
      var tick = 0;
      h = SignatureHarness(
          clock: () => DateTime.utc(2026, 10, 18, 9, 0, tick++));
      await h.viewModel.start();
      final a = await saveOne('A');
      final b = await saveOne('B');
      final c = await saveOne('C');
      h.viewModel.enterSelectionMode();
      h.viewModel.toggleSelection(b.id);
      h.viewModel.toggleSelection(c.id);
      expect(h.viewModel.selectedDocuments.map((d) => d.id), [c.id, b.id]);
      // Removing a document above and below does not move the selection.
      expect(await h.viewModel.delete([a.id]), isEmpty);
      expect(h.viewModel.selectedDocuments.map((d) => d.id), [c.id, b.id]);
      h.viewModel.toggleSelection(c.id);
      expect(h.viewModel.selectedDocuments.map((d) => d.id), [b.id]);
      h.viewModel.toggleSelection('unknown');
      expect(h.viewModel.selectedCount, 1);
      h.viewModel.exitSelectionMode();
      expect(h.viewModel.selectedCount, 0);
    });

    test(
        'a missing file stays listed, is marked, and cannot be opened or shared',
        () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final doc = await saveOne('Gone');
      final stored = File(p.join(
          h.base.path, 'signature_pdfs', 'user-a', 'files', doc.fileName));
      stored.deleteSync();
      await h.viewModel.refresh();
      expect(h.viewModel.documents.map((d) => d.id), [doc.id]);
      expect(h.viewModel.isMissing(doc.id), isTrue);
      expect(await h.viewModel.openableFile(doc), isNull);
      final share = await h.viewModel.prepareShare([doc.id]);
      expect(share.isShareable, isFalse);
      expect(share.unavailable, [doc.id]);
      await expectLater(
          h.viewModel.exportDocument(doc.id),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.fileMissing)));
      expect(h.exporter.names, isEmpty);
      expect(await h.viewModel.delete([doc.id]), isEmpty);
      expect(h.viewModel.documents, isEmpty);
    });
  });

  group('renaming and deleting', () {
    test('rename works by id and reports why it cannot', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final a = await saveOne('One');
      final b = await saveOne('Two');
      expect(await h.viewModel.rename(a.id, '  عقد جديد '), isNull);
      expect(h.viewModel.documentById(a.id)!.name, 'عقد جديد');
      expect(await h.viewModel.rename(b.id, 'عقد جديد'),
          SignatureFailure.nameInUse);
      expect(
          await h.viewModel.rename(b.id, '///'), SignatureFailure.invalidName);
      expect(
          await h.viewModel.rename('missing', 'X'), SignatureFailure.notFound);
      expect(h.viewModel.documentById(b.id)!.name, 'Two');
    });

    test('single and bulk delete remove exactly what was asked', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final a = await saveOne('A');
      final b = await saveOne('B');
      final c = await saveOne('C');
      final d = await saveOne('D');
      h.viewModel.enterSelectionMode();
      h.viewModel.toggleSelection(a.id);
      h.viewModel.toggleSelection(c.id);
      final failed = await h.viewModel
          .delete(h.viewModel.selectedDocuments.map((e) => e.id));
      expect(failed, isEmpty);
      expect(h.viewModel.documents.map((e) => e.id),
          unorderedEquals([b.id, d.id]));
      expect(h.viewModel.selectedCount, 0);
      expect(await h.viewModel.delete([b.id, 'ghost']), ['ghost']);
      expect(h.viewModel.documents.map((e) => e.id), [d.id]);
    });
  });

  group('sharing and exporting', () {
    test('a share carries copies named by title, never by internal id',
        () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final a = await saveOne('عقد الإيجار');
      final b = await saveOne('Lease');
      final share = await h.viewModel.prepareShare([a.id, b.id]);
      expect(share.isShareable, isTrue);
      expect(share.paths.map(p.basename), ['عقد الإيجار.pdf', 'Lease.pdf']);
      for (final path in share.paths) {
        expect(File(path).existsSync(), isTrue);
        expect(p.isWithin(h.temp.path, path), isTrue);
        expect(p.basename(path), isNot(contains(a.id)));
        expect(p.basename(path), isNot(contains('files')));
        expect(path.contains('signature_pdfs'), isFalse,
            reason: 'a private path never reaches another app');
      }
      // The copies are the documents.
      expect(
          File(share.paths.first).readAsBytesSync(),
          File(p.join(
                  h.base.path, 'signature_pdfs', 'user-a', 'files', a.fileName))
              .readAsBytesSync());
    });

    test('sharing a mix of good and missing files shares nothing', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final a = await saveOne('Good');
      final b = await saveOne('Bad');
      File(p.join(h.base.path, 'signature_pdfs', 'user-a', 'files', b.fileName))
          .deleteSync();
      final share = await h.viewModel.prepareShare([a.id, b.id]);
      expect(share.isShareable, isFalse);
      expect(share.paths, isEmpty);
      expect(share.unavailable, [b.id]);
      expect(Directory(p.join(h.temp.path, 'signature_share')).existsSync(),
          isFalse);
    });

    test('an unknown id is unavailable, not an error', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final share = await h.viewModel.prepareShare(['nope']);
      expect(share.isShareable, isFalse);
      expect(share.unavailable, ['nope']);
    });

    test('old shared copies are swept, recent ones are kept', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final doc = await saveOne('Shared');
      final share = await h.viewModel.prepareShare([doc.id]);
      final folder = Directory(p.dirname(share.paths.single));
      final preparer = SignatureSharePreparer(tempRoot: () async => h.temp);
      await preparer.sweepStale();
      expect(folder.existsSync(), isTrue, reason: 'it may still be in use');
      await preparer.sweepStale(
          now: DateTime.now().add(const Duration(hours: 3)));
      expect(folder.existsSync(), isFalse);
    });

    test('export uses the title as the file name and reports where it went',
        () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final doc = await saveOne('Lease');
      h.exporter.result = const ScannerExportResult.saved(
          ScannerExportDestination.downloads, 'Lease (1).pdf');
      final result = await h.viewModel.exportDocument(doc.id);
      expect(result.savedName, 'Lease (1).pdf');
      expect(h.exporter.names, ['Lease.pdf']);
    });

    test('an export that fails is a typed failure and leaves the document',
        () async {
      h = SignatureHarness();
      await h.viewModel.start();
      final doc = await saveOne('Lease');
      for (final kind in [
        SignatureFailure.permissionDenied,
        SignatureFailure.storageFull,
        SignatureFailure.exportFailed,
      ]) {
        h.exporter.failWith = SignatureException(kind);
        await expectLater(
            h.viewModel.exportDocument(doc.id),
            throwsA(
                isA<SignatureException>().having((e) => e.kind, 'kind', kind)));
      }
      expect(h.viewModel.documents.map((d) => d.id), [doc.id]);
      expect(h.viewModel.isWorking, isFalse);
    });

    test('an unknown document cannot be exported', () async {
      h = SignatureHarness();
      await h.viewModel.start();
      await expectLater(
          h.viewModel.exportDocument('nope'),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.notFound)));
    });
  });
}

/// A stream that accepts one listener and fails on the next, as a bug would.
class _ListensOnce extends Stream<String?> {
  bool _listened = false;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<String?> listen(void Function(String? event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    if (_listened) throw StateError('listened twice');
    _listened = true;
    return const Stream<String?>.empty().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
