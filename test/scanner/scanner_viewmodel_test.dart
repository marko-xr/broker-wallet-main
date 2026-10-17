import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';

import 'scanner_fixtures.dart';
import 'scanner_harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  group('scan → review → save', () {
    test('a one-page PDF is verified, reviewed and saved', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => <String, Object?>{
            'pdfUri': Uri.file(path).toString(),
            'pageCount': 1
          };

      final result = await scanOnce(vm);
      expect(result.draft, isNotNull);
      expect(result.draft!.pageCount, 1);
      expect(vm.draft, same(result.draft));

      final saved = await vm.saveDraft('Title deed');
      expect(saved.isSaved, isTrue);
      expect(vm.documents.single.name, 'Title deed');
      expect(vm.documents.single.pageCount, 1);
      expect(vm.draft, isNull);
      expect(h.usage.recorded, <String>['user-a']);
      expect(h.outputFiles(), isEmpty,
          reason: 'the scanner\'s own output is removed');
    });

    test(
        'a multi-page PDF keeps every page; the page count is the file\'s, '
        'not the scanner\'s claim', () async {
      final vm = await h.started();
      final path = await h.pdf(3);
      h.engine.handler =
          (_) => <String, Object?>{'pdfUri': path, 'pageCount': 1};
      final result = await scanOnce(vm);
      expect(result.draft!.pageCount, 3);
      await vm.saveDraft('Lease');
      expect(vm.documents.single.pageCount, 3);
      final store = ScannerDocumentStore(
        accountDir: ScannerDocumentStore.accountDirectory(h.base, 'user-a'),
        userId: 'user-a',
        inspector: testInspector(),
      );
      expect(await store.isIntact(vm.documents.single), isTrue);
    });

    test('image output: every page, in order, one usage for the whole scan',
        () async {
      final vm = await h.started();
      vm.selectExportFormat(ExportFormat.images);
      final pages = <String>[for (var i = 0; i < 4; i++) await h.jpeg(i)];
      h.engine.handler = (_) => <String, Object?>{'images': pages, 'count': 4};

      final result = await scanOnce(vm);
      expect(result.draft!.pageCount, 4);
      expect(h.engine.lastFormat, ExportFormat.images);
      await vm.saveDraft('Plot plan');
      expect(vm.documents.map((d) => d.name), <String>[
        'Plot plan_page_1',
        'Plot plan_page_2',
        'Plot plan_page_3',
        'Plot plan_page_4'
      ]);
      expect(vm.documents.every((d) => d.extension == 'jpg'), isTrue);
      expect(h.usage.recorded, hasLength(1), reason: 'one scan, one use');
    });

    test(
        'one damaged page fails the whole scan: nothing saved, nothing '
        'counted, nothing left behind', () async {
      final vm = await h.started();
      vm.selectExportFormat(ExportFormat.images);
      final good1 = await h.jpeg(1);
      final bad =
          (await writeFile(h.output, 'bad.jpg', jpegBytes().sublist(0, 30)))
              .path;
      final good3 = await h.jpeg(3);
      h.engine.handler = (_) => <String>[good1, bad, good3];
      final result = await scanOnce(vm);
      expect(result.failure, ScannerFailure.corruptOutput);
      expect(vm.draft, isNull);
      expect(vm.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(relativeFiles(h.staging), isEmpty);
      expect(vm.isScanning, isFalse);
    });

    test(
        'a PDF where images were asked for, and images named in a PDF '
        'request, are wrong-format failures', () async {
      final vm = await h.started();
      final pdfPath = await h.pdf(1);
      vm.selectExportFormat(ExportFormat.images);
      h.engine.handler = (_) => <String>[pdfPath];
      expect((await scanOnce(vm)).failure, ScannerFailure.wrongFormat);

      vm.selectExportFormat(ExportFormat.pdf);
      final jpegPath = await h.jpeg(1);
      h.engine.handler = (_) => <String, Object?>{'pdfUri': jpegPath};
      expect((await scanOnce(vm)).failure, ScannerFailure.wrongFormat);

      h.engine.handler = (_) => <String>[jpegPath];
      expect((await scanOnce(vm)).failure, ScannerFailure.wrongFormat);
      expect(vm.documents, isEmpty);
    });

    test('cancelling is not a failure and saves nothing', () async {
      final vm = await h.started();
      h.engine.handler = (_) => null;
      final result = await scanOnce(vm);
      expect(result.cancelled, isTrue);
      expect(result.draft, isNull);
      expect(vm.isScanning, isFalse);
      expect(h.usage.recorded, isEmpty);
    });

    test('a scanner failure is reported and the screen is usable again',
        () async {
      final vm = await h.started();
      h.engine.handler =
          (_) => throw const ScannerException(ScannerFailure.engineFailed);
      expect((await scanOnce(vm)).failure, ScannerFailure.engineFailed);
      expect(vm.isScanning, isFalse);
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      expect((await scanOnce(vm)).draft, isNotNull);
    });

    test('malformed scanner answers are refused', () async {
      final vm = await h.started();
      for (final raw in <Object?>[42, <String, Object?>{}, '']) {
        h.engine.handler = (_) => raw;
        expect((await scanOnce(vm)).failure, ScannerFailure.malformedResult,
            reason: '$raw');
      }
    });

    test('a file outside the scanner\'s folders is refused, not read',
        () async {
      final vm = await h.started();
      final stray = await writeFile(h.root, 'stray.pdf', await pdfBytes(1));
      h.engine.handler = (_) => stray.path;
      expect((await scanOnce(vm)).failure, ScannerFailure.untrustedSource);
      expect(stray.existsSync(), isTrue);
    });

    test('the page limit and format asked of the scanner are the chosen ones',
        () async {
      final vm = await h.started();
      vm.maxPages = 10;
      h.engine.handler = (_) => null;
      await scanOnce(vm);
      expect(h.engine.lastMaxPages, 10);
      expect(h.engine.lastFormat, ExportFormat.pdf);
      vm.maxPages = 500;
      expect(vm.maxPages, 50, reason: 'bounded');
    });

    test('the plan limit stops the scan before the scanner opens', () async {
      final vm = await h.started();
      h.engine.handler = (_) => null;
      final result = await vm.startScan(allowNewScan: (_) async => false);
      expect(result.failure, ScannerFailure.quotaBlocked);
      expect(h.engine.calls, 0);
      expect(vm.isScanning, isFalse);
    });

    test('a signed-out session cannot scan', () async {
      h.uid = null;
      final vm = await h.started();
      h.engine.handler = (_) => null;
      expect((await scanOnce(vm)).failure, ScannerFailure.signedOut);
      expect(h.engine.calls, 0);
    });
  });

  group('double taps and retries', () {
    test('a second scan tap while one is open does nothing', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.gate = Completer<void>();
      h.engine.handler = (_) => path;
      final first = scanOnce(vm);
      final second = await scanOnce(vm);
      expect(second.failure, ScannerFailure.busy);
      h.engine.gate!.complete();
      expect((await first).draft, isNotNull);
      expect(h.engine.calls, 1);
      // And no new scan while the first is still under review.
      expect((await scanOnce(vm)).failure, ScannerFailure.busy);
    });

    test('Save twice quickly saves once', () async {
      final vm = await h.started();
      final path = await h.pdf(2);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      final a = vm.saveDraft('Once');
      final b = vm.saveDraft('Once');
      expect((await b).failure, ScannerFailure.busy);
      expect((await a).isSaved, isTrue);
      expect(vm.documents, hasLength(1));
      expect(h.usage.recorded, hasLength(1));
    });

    test('a failed save keeps the scan for a retry and counts nothing',
        () async {
      var failing = true;
      final vm = await h.started(copier: (source, destination) async {
        if (failing) {
          throw const FileSystemException(
              'No space', '', OSError('ENOSPC', 28));
        }
        await source.copy(destination.path);
      });
      final path = await h.pdf(2);
      h.engine.handler = (_) => path;
      await scanOnce(vm);

      final failed = await vm.saveDraft('Retry me');
      expect(failed.failure, ScannerFailure.storageFull);
      expect(vm.draft, isNotNull, reason: 'the scan is still there');
      expect(vm.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(vm.isSaving, isFalse);

      failing = false;
      final saved = await vm.saveDraft('Retry me');
      expect(saved.isSaved, isTrue);
      expect(vm.documents.single.name, 'Retry me');
      expect(h.usage.recorded, hasLength(1));
      expect(vm.draft, isNull);
    });

    test('discarding a scan removes its temporary files and saves nothing',
        () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      expect(h.outputFiles(), isNotEmpty);
      await vm.discardDraft();
      expect(vm.draft, isNull);
      expect(h.outputFiles(), isEmpty);
      expect(vm.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
    });

    test('saving with no name uses the default title', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      await vm.saveDraft('   ');
      expect(vm.documents.single.name, startsWith('document_scan_'));
    });
  });

  group('accounts', () {
    test('Account B does not see Account A\'s scans; A sees them again',
        () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      await vm.saveDraft('A only');
      expect(vm.documents.map((d) => d.name), <String>['A only']);

      await h.switchTo(vm, 'user-b');
      expect(vm.userId, 'user-b');
      expect(vm.documents, isEmpty);

      await h.switchTo(vm, 'user-a');
      expect(vm.documents.map((d) => d.name), <String>['A only']);
    });

    test('a cold restart reloads the same account\'s documents', () async {
      final first = await h.started();
      final path = await h.pdf(2);
      h.engine.handler = (_) => path;
      await scanOnce(first);
      await first.saveDraft('Survives');
      first.dispose();
      final second = await h.started();
      expect(second.documents.single.name, 'Survives');
      expect(second.documents.single.pageCount, 2);
    });

    test(
        'a scan finishing after the account changed is dropped, not shown '
        'to the new account', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.gate = Completer<void>();
      h.engine.handler = (_) => path;
      final pending = scanOnce(vm);
      await settle(() => h.engine.calls == 1);
      await h.switchTo(vm, 'user-b');
      h.engine.gate!.complete();
      final result = await pending;
      expect(result.failure, ScannerFailure.accountChanged);
      expect(vm.draft, isNull);
      expect(vm.documents, isEmpty);
      expect(h.outputFiles(), isEmpty);
      expect(h.usage.recorded, isEmpty);
      // Nothing was written into either account.
      final a = ScannerDocumentStore.accountDirectory(h.base, 'user-a');
      final b = ScannerDocumentStore.accountDirectory(h.base, 'user-b');
      expect(relativeFiles(a).where((f) => f.endsWith('.pdf')), isEmpty);
      expect(relativeFiles(b).where((f) => f.endsWith('.pdf')), isEmpty);
    });

    test('a scan under review is dropped when the account changes', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      expect(vm.draft, isNotNull);
      await h.switchTo(vm, 'user-b');
      expect(vm.draft, isNull);
      await settle(() => h.outputFiles().isEmpty);
      expect((await vm.saveDraft('late')).isSaved, isFalse);
      expect(vm.documents, isEmpty);
    });

    test('an auth-stream error is not a sign-out; a null identity is',
        () async {
      final vm = await h.started();
      h.auth.addError(StateError('deep-link failed'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(vm.userId, 'user-a');
      await h.switchTo(vm, null);
      expect(vm.userId, isNull);
      h.engine.handler = (_) => null;
      expect((await scanOnce(vm)).failure, ScannerFailure.signedOut);
    });

    test('old global documents are counted but never listed', () async {
      h.legacy = 4;
      final vm = await h.started();
      expect(vm.legacyDocumentCount, 4);
      expect(vm.documents, isEmpty);
    });
  });

  group('lifecycle', () {
    test(
        'a scan finishing after the screen is gone completes quietly and '
        'cleans up', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.gate = Completer<void>();
      h.engine.handler = (_) => path;
      final pending = scanOnce(vm);
      await settle(() => h.engine.calls == 1);
      vm.dispose();
      h.engine.gate!.complete();
      final result = await pending;
      expect(result.draft, isNull);
      expect(result.failure, ScannerFailure.accountChanged);
      expect(h.outputFiles(), isEmpty);
    });

    test('leaving with a scan under review removes its files', () async {
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      vm.dispose();
      await settle(() => h.outputFiles().isEmpty);
    });
  });

  group('library', () {
    Future<List<ScannerDocument>> seed(
        ScannerViewModel vm, List<String> names) async {
      for (final name in names) {
        final path = await h.pdf(1, name);
        h.engine.handler = (_) => path;
        await scanOnce(vm);
        await vm.saveDraft(name);
      }
      return vm.documents;
    }

    test('selection follows ids: deleting another document does not move it',
        () async {
      final vm = await h.started();
      await seed(vm, <String>['A', 'B', 'C']);
      final byName = {for (final d in vm.documents) d.name: d};
      vm.enterSelectionMode();
      vm.toggleSelection(byName['B']!.id);
      expect(vm.selectedDocuments.map((d) => d.name), <String>['B']);

      final failed = await vm.delete(<String>[byName['A']!.id]);
      expect(failed, isEmpty);
      expect(vm.selectedDocuments.map((d) => d.name), <String>['B']);
      expect(vm.documents.map((d) => d.name).toSet(), <String>{'B', 'C'});

      vm.toggleSelection('not-a-document');
      expect(vm.selectedCount, 1);
      vm.exitSelectionMode();
      expect(vm.selectedCount, 0);
      expect(vm.isSelectionMode, isFalse);
    });

    test('bulk delete removes exactly the selected documents', () async {
      final vm = await h.started();
      await seed(vm, <String>['A', 'B', 'C', 'D']);
      final byName = {for (final d in vm.documents) d.name: d};
      vm.enterSelectionMode();
      vm.toggleSelection(byName['A']!.id);
      vm.toggleSelection(byName['C']!.id);
      final failed =
          await vm.delete(vm.selectedDocuments.map((d) => d.id).toList());
      expect(failed, isEmpty);
      expect(vm.documents.map((d) => d.name).toSet(), <String>{'B', 'D'});
      expect(vm.selectedCount, 0);
    });

    test('rename succeeds, and a clash or an empty name is reported', () async {
      final vm = await h.started();
      await seed(vm, <String>['One', 'Two']);
      final one = vm.documents.firstWhere((d) => d.name == 'One');
      expect(await vm.rename(one.id, 'Renamed'), isNull);
      expect(
          vm.documents.map((d) => d.name).toSet(), <String>{'Renamed', 'Two'});
      expect(await vm.rename(one.id, 'two'), ScannerFailure.nameInUse);
      expect(await vm.rename(one.id, '  '), ScannerFailure.invalidName);
      expect(await vm.rename('ghost', 'X'), ScannerFailure.notFound);
    });

    test('a share carries title-named copies, and a missing file blocks it',
        () async {
      final vm = await h.started();
      await seed(vm, <String>['Contract', 'Plan']);
      final ids = vm.documents.map((d) => d.id).toList();
      final prep = await vm.prepareShare(ids);
      expect(prep.isShareable, isTrue);
      expect(prep.paths.map(p.basename).toSet(),
          <String>{'Contract.pdf', 'Plan.pdf'});
      expect(prep.paths.any((path) => path.contains('user-a')), isFalse);

      final store = ScannerDocumentStore(
        accountDir: ScannerDocumentStore.accountDirectory(h.base, 'user-a'),
        userId: 'user-a',
        inspector: testInspector(),
      );
      store.fileOf(vm.documents.first).deleteSync();
      final blocked = await vm.prepareShare(ids);
      expect(blocked.isShareable, isFalse);
      expect(blocked.unavailable, hasLength(1));
      expect(vm.isMissing(vm.documents.first.id), isTrue);
    });

    test(
        'export hands the stored file to the exporter; a missing file or a '
        'failing exporter is an error, not a success', () async {
      final vm = await h.started();
      await seed(vm, <String>['Deed']);
      final doc = vm.documents.single;
      final result = await vm.exportDocument(doc.id);
      expect(result.destination, ScannerExportDestination.downloads);
      expect(h.exporter.exportedNames, <String>['Deed.pdf']);
      expect(h.exporter.exportedPaths.single.contains(doc.fileName), isTrue);
      expect(vm.isWorking, isFalse);

      h.exporter.failure = const ScannerException(ScannerFailure.exportFailed);
      await expectLater(
          vm.exportDocument(doc.id),
          throwsA(isA<ScannerException>()
              .having((e) => e.kind, 'kind', ScannerFailure.exportFailed)));
      expect(vm.isWorking, isFalse);

      h.exporter.failure = null;
      final store = ScannerDocumentStore(
        accountDir: ScannerDocumentStore.accountDirectory(h.base, 'user-a'),
        userId: 'user-a',
        inspector: testInspector(),
      );
      store.fileOf(doc).deleteSync();
      await expectLater(
          vm.exportDocument(doc.id),
          throwsA(isA<ScannerException>()
              .having((e) => e.kind, 'kind', ScannerFailure.fileMissing)));
      expect(h.exporter.exportedNames, hasLength(1));
    });

    test('opening a document whose file is gone returns nothing and flags it',
        () async {
      final vm = await h.started();
      await seed(vm, <String>['Deed']);
      final doc = vm.documents.single;
      expect(await vm.openableFile(doc), isNotNull);
      final store = ScannerDocumentStore(
        accountDir: ScannerDocumentStore.accountDirectory(h.base, 'user-a'),
        userId: 'user-a',
        inspector: testInspector(),
      );
      store.fileOf(doc).deleteSync();
      expect(await vm.openableFile(doc), isNull);
      expect(vm.isMissing(doc.id), isTrue);
    });
  });
}
