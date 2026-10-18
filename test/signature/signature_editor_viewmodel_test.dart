import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';

import 'signature_fixtures.dart';

void main() {
  late SignatureHarness h;

  tearDown(() async {
    await h.dispose();
  });

  Future<SignatureEditorViewModel> open({
    String name = 'lease.pdf',
    int count = 3,
    List<PageSpec>? pages,
  }) async {
    await h.viewModel.start();
    final file = await h.pdf(name, 'L', count: count, pages: pages);
    return h.session(file, name: name);
  }

  Directory workDir([String user = 'user-a']) =>
      Directory(p.join(h.base.path, 'signature_pdfs', user, 'work'));

  List<String> workFiles() => relativeFiles(workDir());

  group('placing', () {
    test('a new item is centred on the chosen page, inside it, and selected',
        () async {
      h = SignatureHarness();
      final s = await open(pages: [a4, a4Landscape, a4]);
      final stamp = await h.place(s, page: 1);
      expect(stamp.pageIndex, 1);
      final geometry = s.pages[1];
      expect(stamp.rect.left, greaterThanOrEqualTo(0));
      expect(stamp.rect.right, lessThanOrEqualTo(geometry.width + 1e-9));
      expect(stamp.rect.bottom, lessThanOrEqualTo(geometry.height + 1e-9));
      expect(stamp.rect.centerX, closeTo(geometry.width / 2, 1e-9));
      expect(stamp.rect.centerY, closeTo(geometry.height / 2, 1e-9));
      expect(s.selectedId, stamp.id);
      expect(s.hasPlacements, isTrue);
      expect(s.stampsOnPage(1), [stamp]);
      expect(s.stampsOnPage(0), isEmpty);
    });

    test('the stamp keeps the proportions of its image', () async {
      h = SignatureHarness();
      final s = await open();
      for (final kind in StampKind.values) {
        final stamp = await h.place(s, kind: kind);
        final asset = s.assetById(stamp.assetId)!;
        expect(stamp.rect.aspect, closeTo(asset.aspect, 1e-9),
            reason: kind.name);
      }
    });

    test('a signature, initials and a line of text start at fitting sizes',
        () async {
      h = SignatureHarness();
      final s = await open();
      final signature = await h.place(s);
      final initials = await h.place(s, kind: StampKind.initials);
      final date = await h.place(s, kind: StampKind.date);
      expect(signature.rect.width, closeTo(595 * 0.28, 1e-6));
      expect(initials.rect.width, lessThan(signature.rect.width));
      expect(date.rect.height, closeTo(StampLayout.lineHeight, 1e-6));
    });

    test('the same image can be placed twice and the two stay independent',
        () async {
      h = SignatureHarness();
      final s = await open();
      final first = await h.place(s);
      final asset = s.assetById(first.assetId)!;
      final second = s.place(asset, 0);
      expect(second.id, isNot(first.id));
      expect(second.assetId, first.assetId);
      s.beginEdit();
      s.updateRect(first.id, const PageRect(10, 10, 120, 40));
      s.endEdit();
      expect(s.stampById(second.id)!.rect, second.rect);
      expect(s.stampById(first.id)!.rect, const PageRect(10, 10, 120, 40));
    });

    test('a page that does not exist is refused', () async {
      h = SignatureHarness();
      final s = await open();
      final asset = await s.createDrawnAsset(StampKind.signature, drawingOf());
      expect(
          () => s.place(asset, 7),
          throwsA(isA<SignatureException>().having(
              (e) => e.kind, 'kind', SignatureFailure.invalidPlacement)));
      expect(() => s.place(asset, -1), throwsA(isA<SignatureException>()));
      expect(s.hasPlacements, isFalse);
    });

    test('a document holds at most the allowed number of items', () async {
      h = SignatureHarness();
      final s = await open();
      final asset = await s.createDrawnAsset(StampKind.signature, drawingOf());
      for (var i = 0; i < SignatureLimits.maxItems; i++) {
        s.place(asset, 0);
      }
      expect(
          () => s.place(asset, 0),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.tooManyItems)));
      expect(s.placements.length, SignatureLimits.maxItems);
    });

    test('an image that cannot be made is a typed failure, not a crash',
        () async {
      h = SignatureHarness();
      final s = await open();
      h.stamps.failWith =
          const SignatureException(SignatureFailure.stampFailed);
      await expectLater(
          s.createDrawnAsset(StampKind.signature, drawingOf()),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.stampFailed)));
      expect(s.assets, isEmpty);
    });
  });

  group('moving, resizing and deleting', () {
    test('a drag is kept inside the page and is one undo step', () async {
      h = SignatureHarness();
      final s = await open();
      final stamp = await h.place(s);
      final start = stamp.rect;
      s.beginEdit();
      s.updateRect(stamp.id, start.translated(40, 0));
      s.updateRect(stamp.id, start.translated(80, 30));
      s.updateRect(stamp.id, const PageRect(-500, -500, 100, 33.3));
      s.endEdit();
      final moved = s.stampById(stamp.id)!.rect;
      expect(moved.left, 0);
      expect(moved.top, 0);
      expect(moved.width, closeTo(100, 1e-9));
      s.undo();
      expect(s.stampById(stamp.id)!.rect, start);
      s.redo();
      expect(s.stampById(stamp.id)!.rect, moved);
    });

    test('a drag that does not move anything adds no undo step', () async {
      h = SignatureHarness();
      final s = await open();
      final stamp = await h.place(s);
      s.undo(); // the placement itself
      expect(s.canUndo, isFalse);
      s.redo();
      expect(s.canUndo, isTrue);
      s.beginEdit();
      s.updateRect(stamp.id, stamp.rect);
      s.endEdit();
      s.undo();
      expect(s.hasPlacements, isFalse,
          reason: 'one undo undoes the placement, not an empty drag');
    });

    test('making an item bigger or smaller keeps its centre and proportions',
        () async {
      h = SignatureHarness();
      final s = await open();
      final stamp = await h.place(s);
      s.scaleBy(stamp.id, 1.5);
      final bigger = s.stampById(stamp.id)!.rect;
      expect(bigger.width, closeTo(stamp.rect.width * 1.5, 1e-9));
      expect(bigger.centerX, closeTo(stamp.rect.centerX, 1e-9));
      expect(bigger.centerY, closeTo(stamp.rect.centerY, 1e-9));
      expect(bigger.aspect, closeTo(stamp.rect.aspect, 1e-9));
      s.scaleBy(stamp.id, 0.0001);
      expect(s.stampById(stamp.id)!.rect.width, StampLayout.minWidth);
      s.scaleBy(stamp.id, 1000);
      expect(s.stampById(stamp.id)!.rect.right,
          lessThanOrEqualTo(s.pages[0].width + 1e-9));
    });

    test('deleting removes one item, can be undone, and leaves the others',
        () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      final b = await h.place(s, page: 1);
      s.delete(a.id);
      expect(s.placements.map((e) => e.id), [b.id]);
      expect(s.selectedId, b.id,
          reason: 'only the deleted item loses the selection');
      s.undo();
      expect(s.placements.map((e) => e.id), [a.id, b.id]);
      s.redo();
      expect(s.placements.map((e) => e.id), [b.id]);
      s.delete('missing');
      expect(s.placements.length, 1);
    });

    test(
        'selecting only works for items that exist, and a page change drops a selection from another page',
        () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      s.select('nope');
      expect(s.selectedId, a.id);
      s.select(null);
      expect(s.selectedId, isNull);
      s.select(a.id);
      s.selectPage(2);
      expect(s.currentPage, 2);
      expect(s.selectedId, isNull);
      s.selectPage(99);
      s.selectPage(-1);
      expect(s.currentPage, 2);
    });

    test('undo and redo walk through every change and keep a bounded history',
        () async {
      h = SignatureHarness();
      final s = await open();
      final asset = await s.createDrawnAsset(StampKind.signature, drawingOf());
      for (var i = 0; i < SignatureEditorViewModel.maxUndoSteps + 10; i++) {
        s.place(asset, i % 3);
      }
      var steps = 0;
      while (s.canUndo) {
        s.undo();
        steps++;
      }
      expect(steps, SignatureEditorViewModel.maxUndoSteps);
      while (s.canRedo) {
        s.redo();
      }
      expect(s.placements.length, SignatureEditorViewModel.maxUndoSteps + 10);
    });

    test('a new change clears what could be redone', () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      s.undo();
      expect(s.canRedo, isTrue);
      await h.place(s);
      expect(s.canRedo, isFalse);
      expect(s.stampById(a.id), isNull);
    });
  });

  group('replacing an image', () {
    test('only that item changes, keeping its width and centre', () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      final asset = s.assetById(a.assetId)!;
      final b = s.place(asset, 0);
      final fresh = await s.createDrawnAsset(
          StampKind.signature, drawingOf(colorValue: 0xFFFF0000));
      s.replaceImage(a.id, fresh);
      final changed = s.stampById(a.id)!;
      expect(changed.assetId, fresh.id);
      expect(changed.rect.width, closeTo(a.rect.width, 1e-9));
      expect(changed.rect.centerX, closeTo(a.rect.centerX, 1e-9));
      expect(s.stampById(b.id)!.assetId, asset.id,
          reason: 'another placement of the old image is not touched');
      s.undo();
      expect(s.stampById(a.id)!.assetId, asset.id);
    });

    test('a new proportion changes the height, not the width', () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      final initials =
          await s.createDrawnAsset(StampKind.initials, drawingOf());
      s.replaceImage(a.id, initials);
      final changed = s.stampById(a.id)!;
      expect(changed.rect.width, closeTo(a.rect.width, 1e-9));
      expect(changed.rect.aspect, closeTo(initials.aspect, 1e-9));
    });
  });

  group('using an image on other pages', () {
    test('only the pages named get it, at the same size and place', () async {
      h = SignatureHarness();
      final s = await open(count: 4, pages: [a4, a4Landscape, a4, a4]);
      final source = await h.place(s);
      final outcome = s.applyToPages(source.id, [1, 3]);
      expect(outcome.added, 2);
      expect(outcome.skipped, 0);
      expect(s.stampsOnPage(2), isEmpty,
          reason: 'a page that was not named is not stamped');
      final onLandscape = s.stampsOnPage(1).single;
      expect(onLandscape.assetId, source.assetId);
      expect(onLandscape.rect.width, closeTo(source.rect.width, 1e-9));
      final expected = StampLayout.carryToPage(
        rect: source.rect,
        fromPageW: s.pages[0].width,
        fromPageH: s.pages[0].height,
        toPageW: s.pages[1].width,
        toPageH: s.pages[1].height,
      );
      expect(onLandscape.rect.isCloseTo(expected, 1e-9), isTrue);
      expect(s.placements.length, 3);
    });

    test('a page that already has the image, or the source page, is skipped',
        () async {
      h = SignatureHarness();
      final s = await open();
      final source = await h.place(s);
      final asset = s.assetById(source.assetId)!;
      s.place(asset, 2);
      final outcome = s.applyToPages(source.id, [0, 1, 2]);
      expect(outcome.added, 1);
      expect(outcome.skipped, 1);
      expect(s.stampsOnPage(2).length, 1);
      expect(s.stampsOnPage(0).length, 1);
      // Doing it again adds nothing.
      expect(s.applyToPages(source.id, [1, 2]).added, 0);
    });

    test('the copies are independent of the original and of each other',
        () async {
      h = SignatureHarness();
      final s = await open();
      final source = await h.place(s);
      s.applyToPages(source.id, [1, 2]);
      final copy = s.stampsOnPage(1).single;
      s.beginEdit();
      s.updateRect(copy.id, const PageRect(30, 30, 100, 33.3));
      s.endEdit();
      expect(s.stampById(source.id)!.rect, source.rect);
      expect(s.stampsOnPage(2).single.rect,
          isNot(const PageRect(30, 30, 100, 33.3)));
    });

    test('it is one undo step, and refused past the limit', () async {
      h = SignatureHarness();
      final s = await open();
      final source = await h.place(s);
      s.applyToPages(source.id, [1, 2]);
      expect(s.placements.length, 3);
      s.undo();
      expect(s.placements.length, 1);
      final asset = s.assetById(source.assetId)!;
      for (var i = 0; i < SignatureLimits.maxItems - 1; i++) {
        s.place(asset, 0);
      }
      expect(
          () => s.applyToPages(source.id, [1]),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.tooManyItems)));
    });
  });

  group('the page the renderer shows', () {
    test('its sizes must match the file\'s own geometry', () async {
      h = SignatureHarness();
      final s = await open(pages: [a4, a4Landscape]);
      final exact = [
        for (final g in s.pages) RenderedPageSize(g.width, g.height),
      ];
      expect(s.checkRendererSizes(exact), isNull);
      // Within a point is the renderer's rounding.
      expect(
          s.checkRendererSizes([
            RenderedPageSize(exact[0].width + 0.5, exact[0].height - 0.5),
            exact[1],
          ]),
          isNull);
      // More than a point means a placement could land elsewhere than shown.
      expect(
          s.checkRendererSizes([
            RenderedPageSize(exact[0].width + 3, exact[0].height),
            exact[1],
          ]),
          SignatureFailure.geometryUnsupported);
      expect(s.checkRendererSizes([exact[0]]),
          SignatureFailure.geometryUnsupported);
      expect(
          s.checkRendererSizes([
            exact[0],
            RenderedPageSize(exact[1].height, exact[1].width),
          ]),
          SignatureFailure.geometryUnsupported,
          reason: 'a page shown turned the wrong way is refused');
    });
  });

  group('the draft (preview)', () {
    test('nothing to preview without an item', () async {
      h = SignatureHarness();
      final s = await open();
      expect(await s.buildDraft(), SignatureFailure.noPlacements);
      expect(s.draft, isNull);
    });

    test('the draft is the signed copy, in the account\'s own work folder',
        () async {
      h = SignatureHarness();
      final s = await open(pages: [a4, a4Landscape]);
      await h.place(s);
      await h.place(s, page: 1, kind: StampKind.date);
      expect(await s.buildDraft(), isNull);
      final draft = s.draft!;
      expect(draft.file.existsSync(), isTrue);
      expect(p.isWithin(workDir().path, draft.file.path), isTrue);
      expect(draft.size, draft.file.lengthSync());
      expect(draft.pageCount, 2);
      expect(draft.itemCount, 2);
      expect(draft.signatureCount, 1, reason: 'a date is not a signature');
      expect(draft.appendedOnly, isTrue);
    });

    test('what the draft draws is exactly where the editor placed it',
        () async {
      h = SignatureHarness();
      final s = await open(pages: [a4, a4Landscape]);
      final first = await h.place(s);
      final second = await h.place(s, page: 1, kind: StampKind.initials);
      s.beginEdit();
      s.updateRect(first.id, const PageRect(60, 90, 150, 50));
      s.endEdit();
      expect(await s.buildDraft(), isNull);
      final original = File(s.sourcePath).readAsBytesSync();
      final drawn =
          imagesDrawnByUpdate(s.draft!.file.readAsBytesSync(), original.length);
      final expected = <UserRect>[
        s.pages[0].userRectOf(const PageRect(60, 90, 150, 50)),
        s.pages[1].userRectOf(s.stampById(second.id)!.rect),
      ];
      expect(drawn.length, 2);
      for (final want in expected) {
        expect(drawn.any((d) => d.rect.isCloseTo(want, 0.02)), isTrue,
            reason: 'nothing drawn at $want');
      }
    });

    test('the original file is untouched by a draft', () async {
      h = SignatureHarness();
      final s = await open();
      final before = File(s.sourcePath).readAsBytesSync();
      await h.place(s);
      await s.buildDraft();
      expect(File(s.sourcePath).readAsBytesSync(), before);
    });

    test('a current draft is reused; any change discards it and its file',
        () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      h = SignatureHarness(executor: gated);
      final s = await open();
      final stamp = await h.place(s);
      expect(await s.buildDraft(), isNull);
      final first = s.draft!.file;
      expect(await s.buildDraft(), isNull);
      expect(gated.writes, 1, reason: 'a current draft is not rewritten');
      s.beginEdit();
      s.updateRect(stamp.id, stamp.rect.translated(20, 20));
      s.endEdit();
      expect(s.draft, isNull);
      expect(await eventually(() => !first.existsSync()), isTrue);
      expect(await s.buildDraft(), isNull);
      expect(gated.writes, 2);
      expect(s.draft!.file.path, isNot(first.path));
      expect(workFiles(), hasLength(1));
    });

    test('undo, delete and replace all discard the draft too', () async {
      h = SignatureHarness();
      final s = await open();
      final a = await h.place(s);
      await h.place(s);
      for (final change in <void Function()>[
        () => s.undo(),
        () => s.redo(),
        () => s.delete(a.id),
      ]) {
        expect(await s.buildDraft(), isNull);
        expect(s.draft, isNotNull);
        change();
        expect(s.draft, isNull);
      }
    });

    test('a second request while one is running is turned away', () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      h = SignatureHarness(executor: gated);
      final s = await open();
      await h.place(s);
      final first = s.buildDraft();
      await gated.started.future;
      expect(s.isBuilding, isTrue);
      expect(await s.buildDraft(), SignatureFailure.busy);
      gated.release!.complete();
      expect(await first, isNull);
      expect(gated.writes, 1);
      expect(s.isBuilding, isFalse);
    });

    test('cancelling stops the draft and leaves no file', () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      h = SignatureHarness(executor: gated);
      final s = await open();
      await h.place(s);
      final running = s.buildDraft();
      await gated.started.future;
      s.cancelBuild();
      gated.release!.complete();
      expect(await running, SignatureFailure.cancelled);
      expect(s.draft, isNull);
      expect(workFiles(), isEmpty);
      expect(h.usage.recorded, isEmpty);
    });

    test('an edit made while the draft was being written makes it stale',
        () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      h = SignatureHarness(executor: gated);
      final s = await open();
      final stamp = await h.place(s);
      final running = s.buildDraft();
      await gated.started.future;
      s.updateRect(stamp.id, stamp.rect.translated(30, 30));
      gated.release!.complete();
      expect(await running, SignatureFailure.cancelled);
      expect(s.draft, isNull);
      expect(workFiles(), isEmpty);
    });

    test('a switch of account while writing drops the result', () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      h = SignatureHarness(executor: gated);
      final s = await open();
      await h.place(s);
      final running = s.buildDraft();
      await gated.started.future;
      await h.switchTo('user-b');
      gated.release!.complete();
      expect(await running, SignatureFailure.accountChanged);
      expect(s.draft, isNull);
      expect(s.accountChanged, isTrue);
      expect(workFiles(), isEmpty);
      expect(relativeFiles(workDir('user-b')), isEmpty);
    });

    test('a source that went missing is a clear failure and no file', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      File(s.sourcePath).deleteSync();
      expect(await s.buildDraft(), SignatureFailure.missingSource);
      expect(s.draft, isNull);
      expect(workFiles(), isEmpty);
    });

    test('a source that changed is refused', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      final file = File(s.sourcePath);
      file.writeAsBytesSync(<int>[...file.readAsBytesSync(), 10]);
      expect(await s.buildDraft(), SignatureFailure.sourceChanged);
      expect(workFiles(), isEmpty);
    });

    test('closing the editor removes its draft', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      final file = s.draft!.file;
      s.dispose();
      expect(await eventually(() => !file.existsSync()), isTrue);
      expect(h.viewModel.isEditing, isFalse);
      expect(h.picker.clears, 1);
    });
  });

  group('saving', () {
    test('the saved document is exactly the previewed draft, counted once',
        () async {
      h = SignatureHarness();
      final s = await open(pages: [a4, a4Landscape]);
      await h.place(s);
      await h.place(s, page: 1, kind: StampKind.text);
      expect(await s.buildDraft(), isNull);
      final draftBytes = Uint8List.fromList(s.draft!.file.readAsBytesSync());
      final outcome =
          await s.save(name: 'Signed lease', allowNew: (uid) async => true);
      expect(outcome.isDone, isTrue);
      final doc = outcome.document!;
      expect(doc.name, 'Signed lease');
      expect(doc.pageCount, 2);
      expect(doc.signatureCount, 1);
      expect(doc.itemCount, 2);
      expect(doc.fileSize, draftBytes.length);
      // The listing now has it, and its stored bytes are the draft's.
      expect(h.viewModel.documents.map((d) => d.id), [doc.id]);
      final stored = await h.viewModel.openableFile(doc);
      expect(stored!.readAsBytesSync(), draftBytes);
      // Counted for this account, once; the draft file is gone.
      expect(h.usage.recorded, ['user-a']);
      expect(s.draft, isNull);
      expect(workFiles(), isEmpty);
    });

    test('a refused plan limit stores nothing and counts nothing', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      final outcome = await s.save(name: 'X', allowNew: (uid) async => false);
      expect(outcome.failure, SignatureFailure.quotaBlocked);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(s.draft, isNotNull, reason: 'the draft stays for another try');
    });

    test('a store that fails counts nothing and keeps the draft', () async {
      h = SignatureHarness(copier: (source, dest) async {
        throw const FileSystemException(
            'disk full', '', OSError('No space left on device', 28));
      });
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      final outcome = await s.save(name: 'X', allowNew: (uid) async => true);
      expect(outcome.failure, SignatureFailure.storageFull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(s.draft!.file.existsSync(), isTrue);
      expect(
          relativeFiles(
                  Directory(p.join(h.base.path, 'signature_pdfs', 'user-a')))
              .where((f) => f.startsWith('files/')),
          isEmpty);
    });

    test(
        'a draft whose file vanished cannot be retried; the next preview rewrites it',
        () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      s.draft!.file.deleteSync();
      final outcome = await s.save(name: 'X', allowNew: (uid) async => true);
      expect(outcome.isDone, isFalse);
      expect(h.usage.recorded, isEmpty);
      expect(s.draft, isNull);
      expect(await s.buildDraft(), isNull);
      expect((await s.save(name: 'X', allowNew: (uid) async => true)).isDone,
          isTrue);
      expect(h.usage.recorded, ['user-a']);
    });

    test('a double tap saves once', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      final gate = Completer<void>();
      final first = s.save(
          name: 'Once',
          allowNew: (uid) async {
            await gate.future;
            return true;
          });
      final second = await s.save(name: 'Twice', allowNew: (uid) async => true);
      expect(second.failure, SignatureFailure.busy);
      gate.complete();
      expect((await first).isDone, isTrue);
      expect(h.viewModel.documents.map((d) => d.name), ['Once']);
      expect(h.usage.recorded, ['user-a']);
    });

    test('it cannot start without a draft or while one is being written',
        () async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      h = SignatureHarness(executor: gated);
      final s = await open();
      await h.place(s);
      expect((await s.save(name: 'X', allowNew: (uid) async => true)).failure,
          SignatureFailure.noPlacements);
      final building = s.buildDraft();
      await gated.started.future;
      expect((await s.save(name: 'X', allowNew: (uid) async => true)).failure,
          SignatureFailure.busy);
      gated.release!.complete();
      await building;
    });

    test('a switch of account before saving stores and counts nothing',
        () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      await s.buildDraft();
      await h.switchTo('user-b');
      final outcome = await s.save(name: 'X', allowNew: (uid) async => true);
      expect(outcome.failure, SignatureFailure.accountChanged);
      expect(h.usage.recorded, isEmpty);
      expect(s.accountChanged, isTrue);
      expect(await s.buildDraft(), SignatureFailure.accountChanged);
      // Neither account has a document.
      expect(h.viewModel.documents, isEmpty);
      await h.switchTo('user-a');
      expect(h.viewModel.documents, isEmpty);
    });

    test('an auth stream error does not close the session', () async {
      h = SignatureHarness();
      final s = await open();
      await h.place(s);
      h.addAuthError();
      await h.pumpFutures();
      expect(s.accountChanged, isFalse);
      expect(await s.buildDraft(), isNull);
    });

    test('an empty title falls back to the picked name, and titles stay unique',
        () async {
      h = SignatureHarness();
      final s = await open(name: 'عقد الإيجار.pdf');
      await h.place(s);
      await s.buildDraft();
      final first = await s.save(name: '   ', allowNew: (uid) async => true);
      expect(first.document!.name, startsWith('عقد الإيجار'));
      await h.place(s);
      await s.buildDraft();
      final second = await s.save(
          name: first.document!.name, allowNew: (uid) async => true);
      expect(second.document!.name, '${first.document!.name} (2)');
    });

    test('the suggested title carries the picked name', () async {
      h = SignatureHarness();
      final s = await open(name: 'Lease Agreement.pdf');
      expect(s.suggestedName('signed'), 'Lease Agreement - signed');
    });
  });
}
