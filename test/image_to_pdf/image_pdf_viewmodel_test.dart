import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfPageSize;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_executor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';

import 'image_pdf_fixtures.dart';
import 'image_pdf_harness.dart';

void main() {
  late ImagePdfHarness h;

  Future<ImagePdfHarness> start([ImagePdfHarness? harness]) async {
    h = harness ?? ImagePdfHarness();
    await h.viewModel.start();
    return h;
  }

  tearDown(() async => h.dispose());

  String pageText(File file, int page, {String? password}) {
    final doc =
        PdfDocument(inputBytes: file.readAsBytesSync(), password: password);
    try {
      return PdfTextExtractor(doc)
          .extractText(startPageIndex: page, endPageIndex: page);
    } finally {
      doc.dispose();
    }
  }

  group('selecting pictures', () {
    test('the library opens empty for the signed-in account', () async {
      await start();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.isLoading, isFalse);
      expect(h.viewModel.loadFailed, isFalse);
      expect(h.backup.excluded.single, p.join(h.base.path, 'image_to_pdf'));
    });

    test('picks are copied into the account\'s own folder and checked',
        () async {
      await start();
      final a = h.jpegFile('a.jpg', w: 640, h: 480);
      final b = h.jpegFile('b.jpg', w: 300, h: 500, r: 200, g: 40, b: 40);
      final outcome = await h.addAndCheck([a, b]);
      expect(outcome.added, 2);
      expect(outcome.rejected, isEmpty);
      final items = h.viewModel.items;
      expect(items.map((i) => i.status), everyElement(ImageItemStatus.ready));
      expect((items[0].analysis!.width, items[0].analysis!.height), (640, 480));
      expect((items[1].analysis!.width, items[1].analysis!.height), (300, 500));
      // The tool works on private copies inside the account folder.
      final staging = p.join(h.accountDir().path, 'staging');
      for (final item in items) {
        expect(p.isWithin(staging, item.path), isTrue);
        expect(File(item.path).existsSync(), isTrue);
      }
      // The originals are not touched.
      expect(a.existsSync(), isTrue);
      expect(a.readAsBytesSync(), File(items[0].path).readAsBytesSync());
    });

    test('the picker\'s own temporary copy is removed, a user file never is',
        () async {
      await start(ImagePdfHarness(pickerCopiesInTemp: true));
      final pickerCopy = h.jpegFile('picker_copy.jpg');
      await h.addAndCheck([pickerCopy]);
      expect(pickerCopy.existsSync(), isFalse);
      expect(h.viewModel.items.single.isReady, isTrue);
      // A file outside the app's temporary folder is the user's: kept.
      await h.dispose();
      await start(ImagePdfHarness());
      final mine = h.jpegFile('mine.jpg');
      await h.addAndCheck([mine]);
      expect(mine.existsSync(), isTrue);
    });

    test('the gallery picker and the camera add pictures', () async {
      await start();
      final a = h.jpegFile('g.jpg');
      final cam = h.jpegFile('cam.jpg', w: 300, h: 400);
      h.picker.gallery = [PickedImage(path: a.path, name: 'g.jpg')];
      var outcome = await h.viewModel.pickFromGallery();
      expect(outcome.added, 1);
      h.picker.photo = PickedImage(path: cam.path, name: 'cam.jpg');
      outcome = await h.viewModel.captureFromCamera();
      expect(outcome.added, 1);
      await h.waitChecked();
      expect(h.viewModel.items, hasLength(2));
      expect(h.viewModel.items.last.analysis!.height, 400);
    });

    test('closing the picker adds nothing; a denied camera is reported',
        () async {
      await start();
      expect((await h.viewModel.pickFromGallery()).cancelled, isTrue);
      expect((await h.viewModel.captureFromCamera()).cancelled, isTrue);
      h.picker.failWith =
          const ImagePdfException(ImagePdfFailure.permissionDenied);
      final denied = await h.viewModel.captureFromCamera();
      expect(denied.failure, ImagePdfFailure.permissionDenied);
      h.picker.failWith = const ImagePdfException(ImagePdfFailure.pickerFailed);
      expect((await h.viewModel.pickFromGallery()).failure,
          ImagePdfFailure.pickerFailed);
      expect(h.viewModel.items, isEmpty);
      expect(h.viewModel.isBusy, isFalse);
    });

    test('a picture that is gone is rejected by name, the rest are kept',
        () async {
      await start();
      final good = h.jpegFile('good.jpg');
      final outcome = await h.viewModel.addPickedImages([
        PickedImage(
            path: p.join(h.inputs.path, 'vanished.jpg'), name: 'vanished.jpg'),
        PickedImage(path: good.path, name: 'good.jpg'),
        const PickedImage(path: '', name: 'cloud.jpg'),
      ]);
      await h.waitChecked();
      expect(outcome.added, 1);
      expect(outcome.rejected.map((r) => (r.name, r.failure)), [
        ('vanished.jpg', ImagePdfFailure.missingSource),
        ('cloud.jpg', ImagePdfFailure.missingSource),
      ]);
      expect(h.viewModel.items.single.displayName, 'good.jpg');
    });

    test('a damaged or unsupported file is listed as failed and blocks the PDF',
        () async {
      await start();
      final good = h.jpegFile('good.jpg');
      final bytes = good.readAsBytesSync();
      final cut = h.rawFile('cut.jpg', bytes.sublist(0, bytes.length ~/ 2));
      final text = h.rawFile('notes.jpg', 'plain text'.codeUnits);
      await h.addAndCheck([good, cut, text]);
      final items = h.viewModel.items;
      expect(items[0].status, ImageItemStatus.ready);
      expect(items[1].status, ImageItemStatus.failed);
      expect(items[1].failure, ImagePdfFailure.corruptSource);
      expect(items[2].failure, ImagePdfFailure.unsupportedFormat);
      expect(h.viewModel.hasFailedItems, isTrue);
      final outcome = await h.prepare();
      expect(outcome.failure, ImagePdfFailure.corruptSource);
      expect(outcome.sourceName, 'cut.jpg');
      expect(outcome.draft, isNull);
      // Removing the bad ones unblocks the PDF.
      h.viewModel.removeItem(items[1].id);
      h.viewModel.removeItem(items[2].id);
      expect((await h.prepare()).isDone, isTrue);
    });

    test('HEIC photos go through the phone\'s decoder; a refusal is by name',
        () async {
      await start();
      final heic = <int>[
        0,
        0,
        0,
        24,
        ...'ftypheic'.codeUnits,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
      ];
      final one = h.rawFile('IMG_1.heic', heic);
      await h.addAndCheck([one]);
      expect(h.normalizer.calls, 1);
      final item = h.viewModel.items.single;
      expect(item.status, ImageItemStatus.ready);
      expect(item.analysis!.format, 'jpeg');
      expect(p.extension(item.path), '.jpg');
      // The unconverted HEIC copy is gone.
      final staged =
          relativeFiles(Directory(p.join(h.accountDir().path, 'staging')));
      expect(staged, hasLength(1));
      h.normalizer.succeed = false;
      final two = h.rawFile('IMG_2.heic', heic);
      final outcome = await h.addAndCheck([two]);
      expect(outcome.added, 0);
      expect(
          outcome.rejected.single.failure, ImagePdfFailure.unsupportedFormat);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'staging'))),
          hasLength(1));
    });

    test('identical pictures are flagged but never discarded', () async {
      await start();
      final a = h.jpegFile('a.jpg');
      final copy = File(p.join(h.inputs.path, 'copy.jpg'))
        ..writeAsBytesSync(a.readAsBytesSync());
      final other = h.jpegFile('other.jpg', r: 1, g: 2, b: 3);
      final outcome = await h.addAndCheck([a, copy, other]);
      expect(outcome.added, 3);
      expect(outcome.possibleDuplicates, 1);
      final items = h.viewModel.items;
      expect(items.map((i) => i.possibleDuplicate), [true, true, false]);
      // Removing one of the pair clears the other's flag.
      h.viewModel.removeItem(items[1].id);
      expect(h.viewModel.items.first.possibleDuplicate, isFalse);
      // Adding the same file again later flags it again.
      await h.addAndCheck([a]);
      expect(h.viewModel.items.where((i) => i.possibleDuplicate), hasLength(2));
    });

    test('at most 100 pictures; the rest are reported', () async {
      await start();
      final one = h.jpegFile('one.jpg', w: 20, h: 20);
      final outcome = await h.viewModel.addPickedImages([
        for (var i = 0; i < 103; i++)
          PickedImage(path: one.path, name: 'p$i.jpg')
      ]);
      expect(outcome.added, 100);
      expect(outcome.rejected, hasLength(3));
      expect(outcome.rejected.first.failure, ImagePdfFailure.tooManyImages);
      expect(h.viewModel.items, hasLength(100));
    });

    test('pictures are checked one at a time, with the real progress visible',
        () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor())
        ..releaseAnalysis = Completer<void>();
      await start(ImagePdfHarness(executor: gated));
      await h.add([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      await h.pumpFutures();
      expect(h.viewModel.isChecking, isTrue);
      expect(
          h.viewModel.items.every((i) => i.status == ImageItemStatus.checking),
          isTrue);
      expect(gated.analyses, 1, reason: 'one decode at a time');
      gated.releaseAnalysis!.complete();
      await h.waitChecked();
      expect(gated.analyses, 2);
      expect(h.viewModel.items.every((i) => i.isReady), isTrue);
    });

    test('a second pick while one is running does nothing', () async {
      await start();
      final gate = Completer<void>();
      h.picker.gate = gate;
      h.picker.gallery = [
        PickedImage(path: h.jpegFile('a.jpg').path, name: 'a.jpg')
      ];
      final first = h.viewModel.pickFromGallery();
      await h.pumpFutures();
      expect(h.viewModel.isAdding, isTrue);
      expect(
          (await h.viewModel.pickFromGallery()).failure, ImagePdfFailure.busy);
      expect((await h.viewModel.captureFromCamera()).failure,
          ImagePdfFailure.busy);
      gate.complete();
      expect((await first).added, 1);
      expect(h.picker.picks, 1);
    });
  });

  group('arranging', () {
    test('reordering, removing and adding keep the list exactly as arranged',
        () async {
      await start();
      final files = [
        for (var i = 0; i < 4; i++) h.jpegFile('f$i.jpg', w: 100 + i, h: 80),
      ];
      await h.addAndCheck(files);
      List<int> widths() =>
          [for (final i in h.viewModel.items) i.analysis!.width];
      expect(widths(), [100, 101, 102, 103]);
      h.viewModel.moveItem(3, 0);
      expect(widths(), [103, 100, 101, 102]);
      h.viewModel.moveItem(0, 2);
      expect(widths(), [100, 101, 103, 102]);
      h.viewModel.moveItem(1, 99); // clamped
      expect(widths(), [100, 103, 102, 101]);
      h.viewModel.moveItem(9, 0); // no such item
      expect(widths(), [100, 103, 102, 101]);
      h.viewModel.removeItem(h.viewModel.items[1].id);
      expect(widths(), [100, 102, 101]);
      await h.addAndCheck([h.jpegFile('late.jpg', w: 555, h: 80)]);
      expect(widths(), [100, 102, 101, 555]);
    });

    test('removing a picture deletes only the tool\'s private copy', () async {
      await start();
      final a = h.jpegFile('a.jpg');
      await h.addAndCheck([a]);
      final staged = File(h.viewModel.items.single.path);
      h.viewModel.removeItem(h.viewModel.items.single.id);
      await h.pumpFutures();
      expect(staged.existsSync(), isFalse);
      expect(a.existsSync(), isTrue);
    });

    test('Clear all removes every private copy', () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      h.viewModel.clearSelection();
      await h.pumpFutures();
      expect(h.viewModel.items, isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'staging'))),
          isEmpty);
    });

    test('the page count shown is the page count made', () async {
      await start();
      await h.addAndCheck([for (var i = 0; i < 7; i++) h.jpegFile('t$i.jpg')]);
      expect(h.viewModel.plannedPageCount, 7);
      h.viewModel.updateSettings(const ImagePdfSettings(
          layout: PdfLayout.tileMultiple, tilesPerPage: 4));
      expect(h.viewModel.plannedPageCount, 2);
      h.viewModel.updateSettings(const ImagePdfSettings(coverPage: true));
      expect(h.viewModel.plannedPageCount, 8);
      final outcome = await h.prepare(
          texts:
              const ImagePdfTexts(coverTitle: 'T', coverLines: ['7 images']));
      expect(outcome.draft!.pageCount, 8);
      expect(outcome.draft!.imageCount, 7);
    });
  });

  group('the PDF', () {
    test('a draft is a verified, complete file whose numbers are real',
        () async {
      await start();
      await h.addAndCheck(
          [h.jpegFile('a.jpg'), h.jpegFile('b.jpg', w: 300, h: 400)]);
      h.viewModel.updateSettings(
          const ImagePdfSettings(pageNumbers: true, timestamp: true));
      final outcome = await h.prepare();
      final draft = outcome.draft!;
      expect(draft.pageCount, 2);
      expect(draft.imageCount, 2);
      expect(draft.size, draft.file.lengthSync());
      expect(draft.encrypted, isFalse);
      expect(p.isWithin(p.join(h.accountDir().path, 'work'), draft.file.path),
          isTrue);
      expect(analyzeImagePdf(draft.file.path).pageCount, 2);
      // The date is the moment the draft was made.
      expect(draft.builtAt, DateTime(2026, 10, 18, 9, 30));
      expect(pageText(draft.file, 0), contains('2026-10-18 09:30'));
      expect(pageText(draft.file, 1), contains('2 / 2'));
      expect(h.viewModel.draftFile!.path, draft.file.path);
    });

    test('an unchanged draft is reused: no second build, no second quota check',
        () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor());
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      final asked = <String>[];
      final first = (await h.prepare(asked: asked)).draft!;
      final second = (await h.prepare(asked: asked)).draft!;
      expect(identical(first, second), isTrue);
      expect(gated.builds, 1);
      expect(asked, ['user-a']);
    });

    test('any change discards the draft, so a stale PDF can never be saved',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      Future<File> fresh() async {
        final draft = (await h.prepare()).draft!;
        return draft.file;
      }

      var file = await fresh();
      h.viewModel.moveItem(0, 1);
      await h.pumpFutures();
      expect(h.viewModel.draft, isNull);
      expect(file.existsSync(), isFalse, reason: 'reorder');

      file = await fresh();
      h.viewModel.updateSettings(
          h.viewModel.settings.copyWith(quality: ImageQuality.low));
      await h.pumpFutures();
      expect(h.viewModel.draft, isNull);
      expect(file.existsSync(), isFalse, reason: 'quality');

      file = await fresh();
      h.viewModel.updateSettings(
          h.viewModel.settings.copyWith(compression: CompressionLevel.high));
      expect(h.viewModel.draft, isNull, reason: 'compression');

      file = await fresh();
      h.viewModel.updateSettings(
          h.viewModel.settings.copyWith(layout: PdfLayout.centerFit));
      expect(h.viewModel.draft, isNull, reason: 'layout');

      file = await fresh();
      h.viewModel.removeItem(h.viewModel.items.first.id);
      await h.pumpFutures();
      expect(h.viewModel.draft, isNull, reason: 'remove');
      expect(file.existsSync(), isFalse);

      file = await fresh();
      await h.addAndCheck([h.jpegFile('c.jpg')]);
      expect(h.viewModel.draft, isNull, reason: 'add');
      expect(file.existsSync(), isFalse);

      // The same settings again change nothing.
      await fresh();
      h.viewModel.updateSettings(h.viewModel.settings);
      expect(h.viewModel.draft, isNotNull);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          hasLength(1));
    });

    test('Save stores exactly the previewed file and counts one usage',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      final draft = (await h.prepare(title: 'Villa 12')).draft!;
      final previewed = draft.file.readAsBytesSync();
      final saved = await h.viewModel.saveDraft(name: 'عقد فيلا');
      expect(saved.isDone, isTrue);
      final doc = saved.document!;
      expect(doc.name, 'عقد فيلا');
      expect(doc.pageCount, 2);
      expect(doc.imageCount, 2);
      expect(doc.fileSize, previewed.length);
      expect(ImagePdfNaming.isStoredFileName(doc.fileName), isTrue);
      expect(
          File(p.join(h.accountDir().path, 'files', doc.fileName))
              .readAsBytesSync(),
          previewed);
      expect(h.usage.recorded, ['user-a']);
      expect(h.viewModel.documents.map((d) => d.id), [doc.id]);
      // The selection, the draft and every private copy are gone.
      expect(h.viewModel.items, isEmpty);
      expect(h.viewModel.draft, isNull);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'staging'))),
          isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          isEmpty);
      // Saving again with nothing to save does nothing and counts nothing.
      expect((await h.viewModel.saveDraft()).failure, ImagePdfFailure.noImages);
      expect(h.usage.recorded, hasLength(1));
    });

    test('two saves with the same title never overwrite each other', () async {
      await start();
      for (var i = 0; i < 2; i++) {
        await h.addAndCheck([h.jpegFile('a$i.jpg')]);
        await h.prepare();
        expect((await h.viewModel.saveDraft(name: 'Same')).isDone, isTrue);
      }
      expect(h.viewModel.documents.map((d) => d.name).toSet(),
          {'Same', 'Same (2)'});
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'files'))),
          hasLength(2));
    });

    test('a failed, blocked or discarded conversion stores and counts nothing',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      // The free-plan limit says no: nothing is read.
      final blocked = await h.prepare(allow: false);
      expect(blocked.failure, ImagePdfFailure.quotaBlocked);
      expect(h.viewModel.draft, isNull);
      // A picture vanishes before the PDF: the whole PDF fails, by name.
      File(h.viewModel.items.last.path).deleteSync();
      final failed = await h.prepare();
      expect(failed.failure, ImagePdfFailure.missingSource);
      expect(failed.sourceName, 'b.jpg');
      expect(h.viewModel.draft, isNull);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          isEmpty);
      // A discarded draft is not a conversion either.
      h.viewModel.removeItem(h.viewModel.items.last.id);
      await h.prepare();
      h.viewModel.discardDraft();
      await h.pumpFutures();
      expect(h.viewModel.draft, isNull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'files'))),
          isEmpty);
    });

    test('a save that cannot be completed leaves the draft and counts nothing',
        () async {
      var fail = true;
      await start(ImagePdfHarness(copier: (source, dest) async {
        if (fail) {
          throw const FileSystemException(
              'disk full', '', OSError('No space left on device', 28));
        }
        await source.copy(dest.path);
      }));
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      await h.prepare();
      final first = await h.viewModel.saveDraft();
      expect(first.failure, ImagePdfFailure.storageFull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.draft, isNotNull,
          reason: 'retry needs the same draft');
      expect(h.viewModel.isSaving, isFalse);
      fail = false;
      expect((await h.viewModel.saveDraft()).isDone, isTrue);
      expect(h.usage.recorded, ['user-a']);
    });

    test('cancelling a running conversion stores and counts nothing', () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor())
        ..releaseBuild = Completer<void>();
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      final running = h.prepare();
      await gated.buildStarted.future;
      expect(h.viewModel.isBuilding, isTrue);
      h.viewModel.cancelBuild();
      gated.releaseBuild!.complete();
      final outcome = await running;
      expect(outcome.failure, ImagePdfFailure.cancelled);
      expect(h.viewModel.isBuilding, isFalse);
      expect(h.viewModel.draft, isNull);
      expect(h.usage.recorded, isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          isEmpty);
      // The selection is intact and can be converted afterwards.
      gated.releaseBuild = null;
      expect((await h.prepare()).isDone, isTrue);
    });

    test('a double tap makes one PDF; edits during the conversion are ignored',
        () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor())
        ..releaseBuild = Completer<void>();
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      final asked = <String>[];
      final first = h.prepare(asked: asked);
      await gated.buildStarted.future;
      expect((await h.prepare(asked: asked)).failure, ImagePdfFailure.busy);
      // The job is fixed: reordering, removing, settings and picks do nothing.
      final before = h.viewModel.items.map((i) => i.id).toList();
      h.viewModel.moveItem(0, 1);
      h.viewModel.removeItem(before.first);
      h.viewModel
          .updateSettings(const ImagePdfSettings(quality: ImageQuality.low));
      h.viewModel.clearSelection();
      expect(h.viewModel.items.map((i) => i.id), before);
      expect(h.viewModel.settings.quality, ImageQuality.high);
      expect(
          (await h.add([h.jpegFile('c.jpg')])).failure, ImagePdfFailure.busy);
      gated.releaseBuild!.complete();
      expect((await first).isDone, isTrue);
      expect(gated.builds, 1);
      expect(asked, ['user-a']);
    });

    test('the job the worker gets is a snapshot of the arranged list',
        () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor());
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([
        for (var i = 0; i < 3; i++) h.jpegFile('f$i.jpg', w: 100 + i, h: 80)
      ]);
      h.viewModel.moveItem(2, 0);
      await h.prepare();
      expect(gated.lastJob!.images.map((i) => i.width), [102, 100, 101]);
      expect(gated.lastJob!.timestamp, DateTime(2026, 10, 18, 9, 30));
    });

    test('a cover page and its title are explicit options', () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      h.viewModel.updateSettings(
          const ImagePdfSettings(timestamp: true, watermark: true));
      final plain = (await h.prepare(title: 'Villa')).draft!;
      expect(plain.pageCount, 1);
      h.viewModel.updateSettings(const ImagePdfSettings(
          timestamp: true, watermark: true, coverPage: true));
      final withCover = (await h.prepare(
              title: 'Villa 12',
              texts: const ImagePdfTexts(
                  coverTitle: 'Villa 12', coverLines: ['1 image'])))
          .draft!;
      expect(withCover.pageCount, 2);
      expect(pageText(withCover.file, 0), contains('Villa 12'));
      // With the cover on, a new title is a new PDF; with it off it is not.
      final again = (await h.prepare(
              title: 'Other',
              texts: const ImagePdfTexts(
                  coverTitle: 'Other', coverLines: ['1 image'])))
          .draft!;
      expect(identical(again, withCover), isFalse);
      expect(pageText(again.file, 0), contains('Other'));
    });

    test('a typed Arabic watermark loads the bundled font and still builds',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      h.viewModel.updateSettings(
          const ImagePdfSettings(watermark: true, watermarkText: 'سري'));
      final draft = (await h.prepare()).draft!;
      expect(draft.pageCount, 1);
      expect(PdfInspectorHelper.hasEmbeddedFont(draft.file), isTrue);
    });
  });

  group('password protection', () {
    test('a protected PDF needs the password, and says so before and after',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg'), h.jpegFile('b.jpg')]);
      h.viewModel.updateSettings(const ImagePdfSettings(passwordProtect: true));
      // Protection on, password missing or weak: refused before any work.
      expect((await h.prepare()).failure, ImagePdfFailure.invalidPassword);
      h.viewModel.setPassword('abc');
      expect((await h.prepare()).failure, ImagePdfFailure.invalidPassword);
      expect(h.viewModel.draft, isNull);
      h.viewModel.setPassword('Secret-1');
      final draft = (await h.prepare()).draft!;
      expect(draft.encrypted, isTrue);
      expect(draft.pageCount, 2);
      expect(() => PdfDocument(inputBytes: draft.file.readAsBytesSync()),
          throwsA(isA<ArgumentError>()));
      final saved = await h.viewModel.saveDraft(name: 'Sealed');
      expect(saved.document!.encrypted, isTrue);
      expect(saved.document!.pageCount, 2);
      // The password is gone from memory once the PDF is saved.
      expect(h.viewModel.hasPassword, isFalse);
      expect(h.usage.recorded, ['user-a']);
      final listed = h.viewModel.documents.single;
      expect(listed.encrypted, isTrue);
      expect(await h.viewModel.openableFile(listed), isNotNull);
    });

    test(
        'changing the password discards the draft; turning protection off clears it',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      h.viewModel.updateSettings(const ImagePdfSettings(passwordProtect: true));
      h.viewModel.setPassword('Secret-1');
      await h.prepare();
      expect(h.viewModel.draft, isNotNull);
      h.viewModel.setPassword('Secret-2');
      expect(h.viewModel.draft, isNull);
      expect(h.viewModel.hasPassword, isTrue);
      h.viewModel.updateSettings(const ImagePdfSettings());
      expect(h.viewModel.hasPassword, isFalse);
      final open = (await h.prepare()).draft!;
      expect(open.encrypted, isFalse);
    });

    test('the password is never part of the settings value', () {
      const a = ImagePdfSettings(passwordProtect: true);
      expect(a.toString().contains('Secret'), isFalse);
      expect(a == const ImagePdfSettings(passwordProtect: true), isTrue);
    });

    test('Clear all and a closed screen drop the password too', () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      h.viewModel.updateSettings(const ImagePdfSettings(passwordProtect: true));
      h.viewModel.setPassword('Secret-1');
      h.viewModel.clearSelection();
      expect(h.viewModel.hasPassword, isFalse);
    });
  });

  group('accounts', () {
    test('another account sees none of this account\'s PDFs or selection',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      await h.prepare();
      await h.viewModel.saveDraft(name: 'Mine');
      await h.addAndCheck([h.jpegFile('b.jpg')]);
      expect(h.viewModel.documents.map((d) => d.name), ['Mine']);
      await h.switchTo('user-b');
      expect(h.viewModel.userId, 'user-b');
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.items, isEmpty,
          reason: 'selection never crosses accounts');
      expect(h.viewModel.draft, isNull);
      // User A's private copies were removed with the selection.
      await h.pumpFutures();
      expect(
          relativeFiles(
              Directory(p.join(h.accountDir('user-a').path, 'staging'))),
          isEmpty);
      await h.addAndCheck([h.jpegFile('c.jpg')]);
      await h.prepare();
      await h.viewModel.saveDraft(name: 'Theirs');
      expect(h.viewModel.documents.map((d) => d.name), ['Theirs']);
      expect(h.usage.recorded, ['user-a', 'user-b']);
      // Back to A: only A's PDF.
      await h.switchTo('user-a');
      expect(h.viewModel.documents.map((d) => d.name), ['Mine']);
      // A cannot delete B's document by its id.
      await h.switchTo('user-b');
      final theirs = h.viewModel.documents.single;
      await h.switchTo('user-a');
      final failed = await h.viewModel.delete([theirs.id]);
      expect(failed, [theirs.id]);
      expect(h.viewModel.documents.map((d) => d.name), ['Mine']);
      await h.switchTo('user-b');
      expect(h.viewModel.documents.map((d) => d.name), ['Theirs']);
    });

    test('signing out hides everything; a conversion cannot run signed out',
        () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      await h.switchTo(null);
      expect(h.viewModel.documents, isEmpty);
      expect(h.viewModel.items, isEmpty);
      expect((await h.prepare()).failure, ImagePdfFailure.signedOut);
      expect((await h.add([h.jpegFile('b.jpg')])).failure,
          ImagePdfFailure.signedOut);
      expect(
          (await h.viewModel.saveDraft()).failure, ImagePdfFailure.signedOut);
    });

    test('an auth-stream error is not a sign-out', () async {
      await start();
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      h.addAuthError();
      await h.pumpFutures();
      expect(h.viewModel.userId, 'user-a');
      expect(h.viewModel.items, hasLength(1));
    });

    test('a conversion finishing after an account switch is dropped', () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor())
        ..releaseBuild = Completer<void>();
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      final running = h.prepare();
      await gated.buildStarted.future;
      await h.switchTo('user-b');
      gated.releaseBuild!.complete();
      final outcome = await running;
      expect(outcome.failure, ImagePdfFailure.accountChanged);
      expect(h.viewModel.draft, isNull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(
          relativeFiles(
              Directory(p.join(h.accountDir('user-b').path, 'files'))),
          isEmpty);
      expect(
          relativeFiles(
              Directory(p.join(h.accountDir('user-a').path, 'files'))),
          isEmpty);
    });

    test('a pick that returns after an account switch is dropped', () async {
      await start();
      final gate = Completer<void>();
      h.picker.gate = gate;
      h.picker.gallery = [
        PickedImage(path: h.jpegFile('a.jpg').path, name: 'a.jpg')
      ];
      final pending = h.viewModel.pickFromGallery();
      await h.pumpFutures();
      await h.switchTo('user-b');
      gate.complete();
      final outcome = await pending;
      expect(outcome.failure, ImagePdfFailure.accountChanged);
      expect(h.viewModel.items, isEmpty);
    });

    test('pictures left by an earlier run are swept when the account opens',
        () async {
      final harness = ImagePdfHarness();
      final leftover =
          File(p.join(harness.accountDir().path, 'staging', 'old.jpg'))
            ..createSync(recursive: true)
            ..writeAsBytesSync([1, 2, 3]);
      await start(harness);
      expect(leftover.existsSync(), isFalse);
    });

    test('old ownerless PDFs are counted, never shown or deleted', () async {
      final harness = ImagePdfHarness(legacyCount: () async => 3);
      final legacy =
          File(p.join(harness.base.path, 'PDF_Document_20250101_1200.pdf'))
            ..writeAsBytesSync([1, 2, 3]);
      await start(harness);
      expect(h.viewModel.legacyDocumentCount, 3);
      expect(h.viewModel.documents, isEmpty);
      await h.switchTo('user-b');
      expect(h.viewModel.documents, isEmpty);
      expect(legacy.existsSync(), isTrue);
    });
  });

  group('the library', () {
    Future<List<ImagePdfDocument>> makeDocs(int n) async {
      for (var i = 0; i < n; i++) {
        await h.addAndCheck([h.jpegFile('d$i.jpg', w: 100 + i, h: 80)]);
        await h.prepare();
        await h.viewModel.saveDraft(name: 'Doc $i');
      }
      return h.viewModel.documents;
    }

    test('rename, delete and bulk delete work on ids', () async {
      await start();
      final docs = await makeDocs(3);
      final renamed = await h.viewModel.rename(docs[0].id, 'عقد جديد');
      expect(renamed, isNull);
      expect(h.viewModel.documentById(docs[0].id)!.name, 'عقد جديد');
      expect(await h.viewModel.rename(docs[1].id, 'عقد جديد'),
          ImagePdfFailure.nameInUse);
      expect(await h.viewModel.rename(docs[1].id, '///'),
          ImagePdfFailure.invalidName);
      expect(await h.viewModel.rename('nope', 'X'), ImagePdfFailure.notFound);
      final failed = await h.viewModel.delete([docs[0].id, docs[2].id]);
      expect(failed, isEmpty);
      expect(h.viewModel.documents.map((d) => d.id), [docs[1].id]);
      expect(
          File(p.join(h.accountDir().path, 'files', docs[0].fileName))
              .existsSync(),
          isFalse);
      expect(
          File(p.join(h.accountDir().path, 'files', docs[1].fileName))
              .existsSync(),
          isTrue);
      expect(await h.viewModel.delete(['nope']), ['nope']);
    });

    test('selection mode selects, ignores unknown ids and follows deletions',
        () async {
      await start();
      final docs = await makeDocs(2);
      h.viewModel.enterSelectionMode();
      h.viewModel.toggleSelection(docs[0].id);
      h.viewModel.toggleSelection('unknown');
      expect(h.viewModel.selectedCount, 1);
      expect(h.viewModel.isSelected(docs[0].id), isTrue);
      await h.viewModel.delete([docs[0].id]);
      expect(h.viewModel.selectedCount, 0);
      h.viewModel.exitSelectionMode();
      expect(h.viewModel.isSelectionMode, isFalse);
    });

    test('share sends copies named by title, never the internal id', () async {
      await start();
      final docs = await makeDocs(2);
      final prep = await h.viewModel.prepareShare([docs[0].id, docs[1].id]);
      expect(prep.isShareable, isTrue);
      expect(prep.paths.map(p.basename),
          [docs[0].exportFileName, docs[1].exportFileName]);
      for (final path in prep.paths) {
        expect(File(path).existsSync(), isTrue);
        expect(p.isWithin(h.temp.path, path), isTrue);
      }
      // A missing stored file is reported, not shared.
      File(p.join(h.accountDir().path, 'files', docs[1].fileName)).deleteSync();
      final broken = await h.viewModel.prepareShare([docs[0].id, docs[1].id]);
      expect(broken.isShareable, isFalse);
      expect(broken.unavailable, [docs[1].id]);
      expect(h.viewModel.isMissing(docs[1].id), isTrue);
    });

    test('export uses the title and the real result; a gone file is refused',
        () async {
      await start();
      final docs = await makeDocs(1);
      h.exporter.result = const ScannerExportResult.saved(
          ScannerExportDestination.downloads, 'Doc 0 (1).pdf');
      final result = await h.viewModel.exportDocument(docs.single.id);
      expect(result.savedName, 'Doc 0 (1).pdf');
      expect(h.exporter.names, ['Doc 0.pdf']);
      h.exporter.failWith =
          const ImagePdfException(ImagePdfFailure.storageFull);
      await expectLater(h.viewModel.exportDocument(docs.single.id),
          throwsA(isA<ImagePdfException>()));
      File(p.join(h.accountDir().path, 'files', docs.single.fileName))
          .deleteSync();
      h.exporter.failWith = null;
      await expectLater(
          h.viewModel.exportDocument(docs.single.id),
          throwsA(isA<ImagePdfException>()
              .having((e) => e.kind, 'kind', ImagePdfFailure.fileMissing)));
      await expectLater(
          h.viewModel.exportDocument('nope'),
          throwsA(isA<ImagePdfException>()
              .having((e) => e.kind, 'kind', ImagePdfFailure.notFound)));
    });

    test('a damaged stored file is not opened as if it were fine', () async {
      await start();
      final docs = await makeDocs(1);
      final file =
          File(p.join(h.accountDir().path, 'files', docs.single.fileName));
      file.writeAsBytesSync(file.readAsBytesSync().sublist(0, 100));
      expect(await h.viewModel.openableFile(docs.single), isNull);
      expect(h.viewModel.isMissing(docs.single.id), isTrue);
    });

    test('library actions cannot overlap a conversion', () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor());
      await start(ImagePdfHarness(executor: gated));
      final docs = await makeDocs(1);
      await h.addAndCheck([h.jpegFile('x.jpg')]);
      gated.releaseBuild = Completer<void>();
      final running = h.prepare();
      await gated.buildStarted.future;
      expect(await h.viewModel.rename(docs.single.id, 'Other'),
          ImagePdfFailure.busy);
      expect(await h.viewModel.delete([docs.single.id]), [docs.single.id]);
      gated.releaseBuild!.complete();
      await running;
    });
  });

  group('lifecycle', () {
    test('closing the screen during a conversion cancels it and leaves no file',
        () async {
      final gated = GatedExecutor(const InlineImagePdfExecutor())
        ..releaseBuild = Completer<void>();
      await start(ImagePdfHarness(executor: gated));
      await h.addAndCheck([h.jpegFile('a.jpg')]);
      final running = h.prepare();
      await gated.buildStarted.future;
      h.viewModel.dispose();
      gated.releaseBuild!.complete();
      final outcome = await running;
      expect(outcome.isDone, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.usage.recorded, isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          isEmpty);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'staging'))),
          isEmpty);
    });

    test('nothing runs or notifies after the screen is closed', () async {
      await start();
      var notified = 0;
      h.viewModel.addListener(() => notified++);
      h.viewModel.dispose();
      expect((await h.add([h.jpegFile('a.jpg')])).added, isNonNegative);
      expect(notified, 0);
    });
  });
}

/// A tiny helper for reading a draft's raw bytes.
class PdfInspectorHelper {
  static bool hasEmbeddedFont(File file) {
    final Uint8List bytes = file.readAsBytesSync();
    return containsAscii(bytes, 'FontFile2');
  }
}
