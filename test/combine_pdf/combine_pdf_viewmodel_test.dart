import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_platform.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

import 'combine_fixtures.dart';

/// Runs the real combine but reports a result the file does not match, the way
/// a faulty engine would.
class LyingExecutor implements CombineExecutor {
  LyingExecutor(this.inner);

  final CombineExecutor inner;

  @override
  Future<CombineAnalysis> analyze(String path, {int? maxBytes}) =>
      inner.analyze(path, maxBytes: maxBytes);

  @override
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token) async {
    final real = await inner.merge(job, token);
    return CombineMergeResult(pageCount: real.pageCount + 1, size: real.size);
  }
}

class FailingExecutor implements CombineExecutor {
  FailingExecutor(this.inner, this.failure);

  final CombineExecutor inner;
  final CombinePdfFailure failure;

  @override
  Future<CombineAnalysis> analyze(String path, {int? maxBytes}) =>
      inner.analyze(path, maxBytes: maxBytes);

  @override
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token) async {
    throw CombinePdfException(failure);
  }
}

Future<List<String>> storedTexts(CombineHarness h, CombinedPdf doc) async {
  final file = await h.viewModel.openableFile(doc);
  return readPdf(file!.readAsBytesSync()).texts;
}

void main() {
  late CombineHarness h;

  tearDown(() async {
    await h.dispose();
  });

  Future<List<File>> twoFiles() async => [
        await h.pdf('a.pdf', 'A'),
        await h.pdf('b.pdf', 'B', count: 2),
      ];

  group('starting', () {
    test('loads the account, keeps the folder out of backup, counts legacy',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.isLoading, isFalse);
      expect(h.backup.excluded, [p.join(h.base.path, 'combine_pdfs')]);
    });

    test('signed out: nothing runs and no picker opens', () async {
      h = CombineHarness(userId: () => null);
      await h.viewModel.start();
      expect(
          (await h.viewModel.pickFiles()).failure, CombinePdfFailure.signedOut);
      expect(h.picker.picks, 0);
      expect((await h.combine()).failure, CombinePdfFailure.signedOut);
      expect(h.usage.recorded, isEmpty);
    });
  });

  group('choosing files', () {
    test('every problem file is named with its reason; good files are added',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      final good = await h.pdf('good.pdf', 'G');
      final empty = await writeFile(h.inputs, 'empty.pdf', <int>[]);
      final junk = await writeFile(h.inputs, 'junk.pdf', 'not a pdf'.codeUnits);
      final locked = await writeFile(h.inputs, 'locked.pdf',
          buildPdf('L', userPassword: 'u', ownerPassword: 'o'));
      final signed =
          await writeFile(h.inputs, 'signed.pdf', buildPdf('S', sign: true));
      final outcome = await h.viewModel.addPickedFiles([
        PickedPdf(path: good.path, name: 'good.pdf'),
        PickedPdf(path: empty.path, name: 'empty.pdf'),
        PickedPdf(path: junk.path, name: 'junk.pdf'),
        PickedPdf(path: locked.path, name: 'locked.pdf'),
        PickedPdf(path: signed.path, name: 'signed.pdf'),
        PickedPdf(path: p.join(h.inputs.path, 'gone.pdf'), name: 'gone.pdf'),
        const PickedPdf(path: '', name: 'cloud-only.pdf'),
      ]);
      expect(outcome.added, 1);
      expect({
        for (final r in outcome.rejected) r.name: r.failure
      }, {
        'empty.pdf': CombinePdfFailure.emptySource,
        'junk.pdf': CombinePdfFailure.corruptSource,
        'locked.pdf': CombinePdfFailure.encryptedSource,
        'signed.pdf': CombinePdfFailure.signedSource,
        'gone.pdf': CombinePdfFailure.missingSource,
        'cloud-only.pdf': CombinePdfFailure.missingSource,
      });
      expect(h.viewModel.plan.sources.map((s) => s.displayName), ['good.pdf']);
      expect(h.viewModel.plan.totalPages, 3);
    });

    test('a file picked twice is reported, not silently dropped or doubled',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      final a = await h.pdf('a.pdf', 'A');
      expect((await h.add([a])).added, 1);
      final again = await h.add([a]);
      expect(again.added, 0);
      expect(again.duplicates, 1);
      expect(h.viewModel.plan.sources, hasLength(1));
    });

    test('cancelling the picker changes nothing', () async {
      h = CombineHarness();
      await h.viewModel.start();
      h.picker.next = null;
      final outcome = await h.viewModel.pickFiles();
      expect(outcome.cancelled, isTrue);
      expect(h.viewModel.plan.isEmpty, isTrue);
      expect(h.viewModel.isChecking, isFalse);
    });

    test('a pick that finishes after an account switch is dropped', () async {
      h = CombineHarness();
      await h.viewModel.start();
      final a = await h.pdf('a.pdf', 'A');
      h.picker.next = [PickedPdf(path: a.path, name: 'a.pdf')];
      h.picker.gate = Completer<void>();
      final pending = h.viewModel.pickFiles();
      await h.pumpFutures();
      await h.switchTo('user-b');
      h.picker.gate!.complete();
      final outcome = await pending;
      expect(outcome.failure, CombinePdfFailure.accountChanged);
      expect(h.viewModel.plan.isEmpty, isTrue);
    });
  });

  group('combining', () {
    test('combines two files into one stored document, counted once', () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final outcome = await h.combine(name: 'عقد الإيجار');
      expect(outcome.isDone, isTrue);
      final doc = outcome.document!;
      expect(doc.name, 'عقد الإيجار');
      expect(doc.pageCount, 5);
      expect(h.viewModel.documents.map((d) => d.id), [doc.id]);
      expect(await storedTexts(h, doc),
          ['A page 1', 'A page 2', 'A page 3', 'B page 1', 'B page 2']);
      expect(h.usage.recorded, ['user-a']);
      // The selection is spent, the picker's copies are released and no work
      // file is left behind.
      expect(h.viewModel.plan.isEmpty, isTrue);
      expect(h.picker.clears, greaterThan(0));
      final dir = CombinePdfStore.accountDirectory(h.base, 'user-a');
      expect(relativeFiles(dir).where((f) => f.startsWith('work/')), isEmpty);
      expect(h.viewModel.isMerging, isFalse);
    });

    test('page edits reach the stored file; a blank name gets the default',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final vm = h.viewModel;
      final bId = vm.plan.sources[1].id;
      vm.selectRange(vm.plan.sources[0].id, 2, 3);
      vm.removePage(vm.plan.pages.indexWhere((e) => e.sourceId == bId));
      vm.movePage(2, 0);
      expect(vm.plan.totalPages, 3);
      final outcome = await h.combine(name: '   ');
      expect(outcome.document!.name, 'combined_20261018_0930');
      expect(await storedTexts(h, outcome.document!),
          ['B page 2', 'A page 2', 'A page 3']);
    });

    test('a combine that cannot run says why and counts nothing', () async {
      h = CombineHarness();
      await h.viewModel.start();
      final a = await h.pdf('a.pdf', 'A');
      await h.add([a]);
      expect((await h.combine()).failure, CombinePdfFailure.tooFewFiles);
      final b = await h.pdf('b.pdf', 'B');
      await h.add([b]);
      final vm = h.viewModel;
      for (var i = 0; i < 3; i++) {
        vm.removePage(0);
      }
      final blocked = await h.combine();
      expect(blocked.failure, CombinePdfFailure.fileHasNoPages);
      expect(blocked.sourceName, 'a.pdf');
      expect(h.usage.recorded, isEmpty);
      expect(vm.documents, isEmpty);
    });

    test('a refused plan limit stores nothing, counts nothing, keeps the plan',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final outcome = await h.combine(allow: false);
      expect(outcome.failure, CombinePdfFailure.quotaBlocked);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.plan.sources, hasLength(2));
      expect(h.viewModel.isMerging, isFalse);
    });

    test(
        'a failed combine names the file, stores nothing, counts nothing, and '
        'a retry works', () async {
      h = CombineHarness();
      await h.viewModel.start();
      final files = await twoFiles();
      await h.add(files);
      final saved = files[1].readAsBytesSync();
      files[1].deleteSync();
      final failed = await h.combine();
      expect(failed.failure, CombinePdfFailure.missingSource);
      expect(failed.sourceName, 'b.pdf');
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.plan.sources, hasLength(2));
      // The user restores the file and tries again.
      files[1].writeAsBytesSync(saved);
      final retry = await h.combine();
      expect(retry.isDone, isTrue);
      expect(h.usage.recorded, ['user-a']);
      expect(h.viewModel.documents, hasLength(1));
    });

    test('a combine whose result does not match its file is never listed',
        () async {
      h = CombineHarness(
          executor: LyingExecutor(const InlineCombineExecutor()));
      await h.viewModel.start();
      await h.add(await twoFiles());
      final outcome = await h.combine();
      expect(outcome.failure, CombinePdfFailure.writeFailed);
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      final dir = CombinePdfStore.accountDirectory(h.base, 'user-a');
      expect(relativeFiles(dir).where((f) => f.endsWith('.pdf')), isEmpty);
    });

    test('a full phone fails the combine and the save, with nothing counted',
        () async {
      h = CombineHarness(
          executor: FailingExecutor(
              const InlineCombineExecutor(), CombinePdfFailure.storageFull));
      await h.viewModel.start();
      await h.add(await twoFiles());
      expect((await h.combine()).failure, CombinePdfFailure.storageFull);
      expect(h.usage.recorded, isEmpty);
      await h.dispose();

      h = CombineHarness(copier: (source, dest) async {
        throw const FileSystemException(
            'full', '', OSError('No space left on device', 28));
      });
      await h.viewModel.start();
      await h.add(await twoFiles());
      expect((await h.combine()).failure, CombinePdfFailure.storageFull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
    });
  });

  group('while a combine is running', () {
    late GatedExecutor gated;

    Future<void> prepare() async {
      gated = GatedExecutor(const InlineCombineExecutor())
        ..release = Completer<void>();
      h = CombineHarness(executor: gated);
      await h.viewModel.start();
      await h.add(await twoFiles());
    }

    test('a second tap does nothing; the plan cannot change underneath it',
        () async {
      await prepare();
      final first = h.combine();
      await gated.started.future;
      expect(h.viewModel.isMerging, isTrue);
      expect((await h.combine()).failure, CombinePdfFailure.busy);
      expect((await h.viewModel.pickFiles()).failure, CombinePdfFailure.busy);
      h.viewModel.removePage(0);
      h.viewModel.removeSource(h.viewModel.plan.sources.first.id);
      expect(h.viewModel.plan.totalPages, 5);
      gated.release!.complete();
      expect((await first).isDone, isTrue);
      expect(gated.merges, 1);
      expect(h.usage.recorded, ['user-a']);
    });

    test('cancelling stores nothing and counts nothing', () async {
      await prepare();
      final running = h.combine();
      await gated.started.future;
      h.viewModel.cancelCombine();
      gated.release!.complete();
      final outcome = await running;
      expect(outcome.failure, CombinePdfFailure.cancelled);
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.isMerging, isFalse);
      expect(h.viewModel.plan.sources, hasLength(2));
      final dir = CombinePdfStore.accountDirectory(h.base, 'user-a');
      expect(relativeFiles(dir).where((f) => f.startsWith('work/')), isEmpty);
    });

    test('switching account drops the result and never stores it', () async {
      await prepare();
      final running = h.combine();
      await gated.started.future;
      await h.switchTo('user-b');
      gated.release!.complete();
      final outcome = await running;
      expect(outcome.failure, CombinePdfFailure.accountChanged);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.userId, 'user-b');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.plan.isEmpty, isTrue);
      await h.switchTo('user-a');
      expect(h.viewModel.documents, isEmpty);
    });

    test('leaving the screen stops the combine and leaves nothing behind',
        () async {
      await prepare();
      final running = h.combine();
      await gated.started.future;
      h.viewModel.dispose();
      gated.release!.complete();
      final outcome = await running;
      expect(outcome.isDone, isFalse);
      expect(h.usage.recorded, isEmpty);
      final dir = CombinePdfStore.accountDirectory(h.base, 'user-a');
      expect(relativeFiles(dir).where((f) => f.endsWith('.pdf')), isEmpty);
    });
  });

  group('accounts', () {
    test('each account sees only its own documents, in both directions',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final mine = (await h.combine(name: 'Mine')).document!;
      await h.switchTo('user-b');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.plan.isEmpty, isTrue);
      expect(h.viewModel.documentById(mine.id), isNull);
      await h.add([await h.pdf('c.pdf', 'C'), await h.pdf('d.pdf', 'D')]);
      final theirs = (await h.combine(name: 'Theirs')).document!;
      expect(h.viewModel.documents.map((d) => d.name), ['Theirs']);
      await h.switchTo('user-a');
      expect(h.viewModel.documents.map((d) => d.name), ['Mine']);
      expect(h.viewModel.documentById(theirs.id), isNull);
      expect(h.usage.recorded, ['user-a', 'user-b']);
    });

    test('an auth-stream error is not a sign-out', () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      await h.combine();
      h.addAuthError();
      await h.pumpFutures();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.documents, hasLength(1));
    });

    test('signing out clears the list and the selection', () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      await h.combine();
      await h.add([await h.pdf('c.pdf', 'C')]);
      await h.switchTo(null);
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.plan.isEmpty, isTrue);
      expect(h.viewModel.userId, isNull);
    });
  });

  group('the list', () {
    Future<List<CombinedPdf>> three() async {
      final docs = <CombinedPdf>[];
      for (final tag in ['One', 'Two', 'Three']) {
        await h.add([
          await h.pdf('$tag-1.pdf', tag, count: 1),
          await h.pdf('$tag-2.pdf', tag, count: 1),
        ]);
        docs.add((await h.combine(name: tag)).document!);
      }
      return docs;
    }

    test(
        'rename and delete work on ids, and bulk delete removes only the '
        'selected', () async {
      h = CombineHarness();
      await h.viewModel.start();
      final docs = await three();
      expect(await h.viewModel.rename(docs[0].id, 'Two'),
          CombinePdfFailure.nameInUse);
      expect(await h.viewModel.rename(docs[0].id, 'Renamed ✓'), isNull);
      expect(h.viewModel.documentById(docs[0].id)!.name, 'Renamed ✓');
      expect(await h.viewModel.rename('nope', 'X'), CombinePdfFailure.notFound);

      h.viewModel.enterSelectionMode();
      h.viewModel.toggleSelection(docs[0].id);
      h.viewModel.toggleSelection(docs[2].id);
      h.viewModel.toggleSelection('unknown');
      expect(h.viewModel.selectedCount, 2);
      final failed = await h.viewModel
          .delete(h.viewModel.selectedDocuments.map((d) => d.id));
      expect(failed, isEmpty);
      expect(h.viewModel.documents.map((d) => d.id), [docs[1].id]);
      expect(h.viewModel.selectedCount, 0);
      // Deleting an id that is already gone is reported, not hidden.
      expect(await h.viewModel.delete([docs[0].id]), [docs[0].id]);
    });

    test('share copies are named by title (Arabic too), never by internal id',
        () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final doc = (await h.combine(name: 'عقد البيع')).document!;
      final prep = await h.viewModel.prepareShare([doc.id]);
      expect(prep.isShareable, isTrue);
      expect(p.basename(prep.paths.single), 'عقد البيع.pdf');
      expect(p.basename(prep.paths.single), isNot(contains(doc.id)));
      expect(File(prep.paths.single).lengthSync(), doc.fileSize);
      // The stored file is the one in the account folder, untouched.
      expect(await h.viewModel.openableFile(doc), isNotNull);
    });

    test('a missing or damaged file blocks sharing and exporting', () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final doc = (await h.combine(name: 'Gone')).document!;
      final stored = await h.viewModel.openableFile(doc);
      stored!.writeAsBytesSync(stored.readAsBytesSync().sublist(0, 40));
      final prep = await h.viewModel.prepareShare([doc.id]);
      expect(prep.isShareable, isFalse);
      expect(prep.unavailable, [doc.id]);
      expect(h.viewModel.isMissing(doc.id), isTrue);
      await expectLater(
          h.viewModel.exportDocument(doc.id),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.fileMissing)));
      expect(h.exporter.names, isEmpty);
    });

    test(
        'export hands the platform the title, reports where it went and '
        'passes failures through', () async {
      h = CombineHarness();
      await h.viewModel.start();
      await h.add(await twoFiles());
      final doc = (await h.combine(name: 'Lease')).document!;
      final result = await h.viewModel.exportDocument(doc.id);
      expect(result.destination, ScannerExportDestination.downloads);
      expect(h.exporter.names, ['Lease.pdf']);
      h.exporter.failWith =
          const CombinePdfException(CombinePdfFailure.permissionDenied);
      await expectLater(
          h.viewModel.exportDocument(doc.id),
          throwsA(isA<CombinePdfException>().having(
              (e) => e.kind, 'kind', CombinePdfFailure.permissionDenied)));
      expect(h.viewModel.isWorking, isFalse);
      await expectLater(
          h.viewModel.exportDocument('nope'),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.notFound)));
    });
  });

  group('platform wrappers', () {
    const channel = MethodChannel('combine_test_file_saver');
    final calls = <MethodCall>[];

    PlatformCombinePdfExporter exporterFor({
      bool android = true,
      int sdk = 33,
      bool permission = true,
      Future<String?> Function(String, Uint8List)? saveToFiles,
    }) {
      return PlatformCombinePdfExporter(PlatformScannerExporter(
        isAndroid: android,
        androidSdk: () async => sdk,
        requestLegacyStoragePermission: () async => permission,
        saveToFiles: saveToFiles ?? (name, bytes) async => null,
        channel: channel,
      ));
    }

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void answer(Future<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    late File file;
    setUp(() async {
      file = await writeFile(makeTempDir('exp'), 'x.pdf', buildPdf('X'));
    });
    tearDown(() => file.parent.deleteSync(recursive: true));

    test('Android streams the stored file to Downloads under the title',
        () async {
      answer((call) async => {'success': true, 'displayName': 'Lease (1).pdf'});
      final result = await exporterFor().export('Lease.pdf', file);
      expect(result.savedName, 'Lease (1).pdf');
      expect(result.destination, ScannerExportDestination.downloads);
      expect(calls.single.method, 'exportFileToDownloads');
      expect(calls.single.arguments, {
        'sourcePath': file.path,
        'fileName': 'Lease.pdf',
        'mimeType': 'application/pdf',
      });
    });

    test('the platform failures become Combine failures', () async {
      for (final (code, expected) in [
        ('PERMISSION_DENIED', CombinePdfFailure.permissionDenied),
        ('STORAGE_FULL', CombinePdfFailure.storageFull),
        ('WRITE_FAILED', CombinePdfFailure.exportFailed),
      ]) {
        answer((call) async => throw PlatformException(code: code));
        await expectLater(
            exporterFor().export('x.pdf', file),
            throwsA(isA<CombinePdfException>()
                .having((e) => e.kind, 'kind', expected)),
            reason: code);
      }
      answer((call) async => {'success': false});
      await expectLater(
          exporterFor().export('x.pdf', file),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.exportFailed)));
    });

    test('Android 9 and below needs the legacy permission first', () async {
      answer((call) async => {'success': true, 'displayName': 'x.pdf'});
      await expectLater(
          exporterFor(sdk: 28, permission: false).export('x.pdf', file),
          throwsA(isA<CombinePdfException>().having(
              (e) => e.kind, 'kind', CombinePdfFailure.permissionDenied)));
      expect(calls, isEmpty);
      await exporterFor(sdk: 28).export('x.pdf', file);
      expect(calls, hasLength(1));
    });

    test('iPhone asks the Files sheet; closing it reports nothing saved',
        () async {
      var asked = '';
      final closed = await exporterFor(
        android: false,
        saveToFiles: (name, bytes) async {
          asked = name;
          return null;
        },
      ).export('Lease.pdf', file);
      expect(closed.cancelled, isTrue);
      expect(asked, 'Lease.pdf');
      final saved = await exporterFor(
        android: false,
        saveToFiles: (name, bytes) async => '/private/Files/Lease.pdf',
      ).export('Lease.pdf', file);
      expect(saved.destination, ScannerExportDestination.files);
      expect(saved.savedName, 'Lease.pdf');
    });
  });
}
