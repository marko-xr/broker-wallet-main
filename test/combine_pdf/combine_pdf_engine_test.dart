import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_plan.dart';

import 'combine_fixtures.dart';

CombineFailureMatcher throwsCombine(CombinePdfFailure kind) =>
    CombineFailureMatcher(kind);

class CombineFailureMatcher extends Matcher {
  const CombineFailureMatcher(this.kind);

  final CombinePdfFailure kind;

  @override
  Description describe(Description description) =>
      description.add('a CombinePdfException of kind ${kind.name}');

  @override
  bool matches(Object? item, Map matchState) {
    if (item is! Function) return false;
    try {
      (item as dynamic)();
    } catch (error) {
      return error is CombinePdfException && error.kind == kind;
    }
    return false;
  }
}

Future<CombineMergeJob> jobFor(
  Directory dir,
  CombinePlan plan, {
  String output = 'out.pdf',
}) async {
  return CombineMergeJob(
    sources: plan.sources,
    pages: plan.pages,
    outputPath: p.join(dir.path, output),
  );
}

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir('engine'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<CombinePlan> planOf(List<File> files) async {
    final plan = CombinePlan();
    for (final file in files) {
      plan.addSource(await sourceOf(file));
    }
    return plan;
  }

  group('checking a file', () {
    test('reads the real page count and finds no special features', () async {
      final file = await writeFile(dir, 'a.pdf', buildPdf('A', count: 4));
      final analysis = analyzeCombinePdf(file.path, maxBytes: 1 << 26);
      expect(analysis.pageCount, 4);
      expect(analysis.size, file.lengthSync());
      expect(analysis.features.hasSignatures, isFalse);
      expect(analysis.features.changesOnCombine, isFalse);
    });

    test('a missing, empty, oversized or non-PDF file is told apart', () async {
      expect(
          () => analyzeCombinePdf(p.join(dir.path, 'none.pdf'),
              maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.missingSource));
      final empty = await writeFile(dir, 'empty.pdf', <int>[]);
      expect(() => analyzeCombinePdf(empty.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.emptySource));
      final big = await writeFile(dir, 'big.pdf', buildPdf('B'));
      expect(() => analyzeCombinePdf(big.path, maxBytes: 100),
          throwsCombine(CombinePdfFailure.tooLargeSource));
      final text = await writeFile(dir, 'text.pdf', 'just some text'.codeUnits);
      expect(() => analyzeCombinePdf(text.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.corruptSource));
      expect(() => analyzeCombinePdf(dir.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.missingSource));
    });

    test('a truncated or damaged PDF is corrupt, never partly accepted',
        () async {
      final good = buildPdf('C', count: 5);
      final cut =
          await writeFile(dir, 'cut.pdf', good.sublist(0, good.length ~/ 2));
      expect(() => analyzeCombinePdf(cut.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.corruptSource));
      final header = await writeFile(dir, 'header.pdf',
          Uint8List.fromList('%PDF-1.7\n${'x' * 300}\n%%EOF'.codeUnits));
      expect(() => analyzeCombinePdf(header.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.corruptSource));
    });

    test('password-protected PDFs are refused, with or without a user password',
        () async {
      final locked = await writeFile(dir, 'locked.pdf',
          buildPdf('L', userPassword: 'secret', ownerPassword: 'owner'));
      expect(() => analyzeCombinePdf(locked.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.encryptedSource));
      // Opens without any password, but is encrypted: copying its pages would
      // silently drop the owner's protection.
      final ownerOnly = await writeFile(
          dir, 'owner.pdf', buildPdf('O', ownerPassword: 'owner'));
      expect(() => analyzeCombinePdf(ownerOnly.path, maxBytes: 1 << 26),
          throwsCombine(CombinePdfFailure.encryptedSource));
    });

    test('a signed PDF is reported as signed; other structures are flagged',
        () async {
      final signed =
          await writeFile(dir, 'signed.pdf', buildPdf('S', sign: true));
      expect(
          analyzeCombinePdf(signed.path, maxBytes: 1 << 26)
              .features
              .hasSignatures,
          isTrue);
      final rich = await writeFile(dir, 'rich.pdf',
          buildPdf('R', form: true, link: true, bookmark: true, markup: true));
      final features = analyzeCombinePdf(rich.path, maxBytes: 1 << 26).features;
      expect(features.hasSignatures, isFalse);
      expect(features.hasFormFields, isTrue);
      expect(features.hasAnnotations, isTrue);
      expect(features.hasBookmarks, isTrue);
      expect(features.changesOnCombine, isTrue);
    });
  });

  group('combining', () {
    test('two files keep every page, in the chosen order', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 3));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 2));
      final plan = await planOf([a, b]);
      final result = runCombineMerge(await jobFor(dir, plan));
      expect(result.pageCount, 5);
      final facts =
          readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync());
      expect(facts.pageCount, 5);
      expect(facts.texts, [
        'A page 1',
        'A page 2',
        'A page 3',
        'B page 1',
        'B page 2',
      ]);
      expect(result.size, File(p.join(dir.path, 'out.pdf')).lengthSync());
    });

    test('moving the second file first puts its pages first', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 2));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 2));
      final plan = await planOf([a, b])
        ..moveSource(1, 0);
      runCombineMerge(await jobFor(dir, plan));
      expect(readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync()).texts,
          ['B page 1', 'B page 2', 'A page 1', 'A page 2']);
    });

    test('four files combine in selection order with the right page total',
        () async {
      final files = [
        for (final tag in ['A', 'B', 'C', 'D'])
          await writeFile(dir, '$tag.pdf', buildPdf(tag, count: 2)),
      ];
      final plan = await planOf(files);
      expect(plan.totalPages, 8);
      final result = runCombineMerge(await jobFor(dir, plan));
      expect(result.pageCount, 8);
      expect(
          readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync()).texts, [
        for (final tag in ['A', 'B', 'C', 'D'])
          for (final n in [1, 2]) '$tag page $n'
      ]);
    });

    test('a page range, removed pages, reordering and rotation are applied',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 4));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 4));
      final plan = await planOf([a, b]);
      plan.selectRange(plan.sources[0].id, 2, 3); // A2 A3
      plan.removePage(plan.pages.indexWhere(
          (e) => e.sourceId == plan.sources[1].id && e.pageIndex == 1)); // -B2
      // Now: A2 A3 B1 B3 B4. Move B4 to the front, rotate A3 and B1.
      plan.movePage(4, 0);
      plan.rotatePage(2, 1); // A3
      plan.rotatePage(3, 3); // B1 turned back by one quarter
      expect(plan.totalPages, 5);
      runCombineMerge(await jobFor(dir, plan));
      final facts =
          readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync());
      expect(facts.texts,
          ['B page 4', 'A page 2', 'A page 3', 'B page 1', 'B page 3']);
      expect(facts.rotations, [0, 0, 1, 3, 0]);
    });

    test('mixed sizes, orientations and rotated pages keep their geometry',
        () async {
      const tall = PageSpec(300, 500, rotate: PdfPageRotateAngle.rotateAngle90);
      const big = PageSpec(1000, 1500);
      final a = await writeFile(
          dir, 'a.pdf', buildPdf('A', pages: [a4, a4Landscape, tall]));
      final b = await writeFile(
          dir, 'b.pdf', buildPdf('B', pages: [big, a4Landscape]));
      final plan = await planOf([a, b]);
      runCombineMerge(await jobFor(dir, plan));
      final facts =
          readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync());
      expect(facts.sizes, [
        const Size(595, 842),
        const Size(842, 595),
        const Size(300, 500),
        const Size(1000, 1500),
        const Size(842, 595),
      ]);
      expect(facts.rotations, [0, 0, 1, 0, 0]);
      expect(facts.texts.last, 'B page 2');
    });

    test('a page with a CropBox keeps its visible area and text position',
        () async {
      for (final rotate in [0, 90]) {
        final source =
            await writeFile(dir, 'crop$rotate.pdf', cropBoxPdf(rotate: rotate));
        final other =
            await writeFile(dir, 'other$rotate.pdf', buildPdf('O', count: 1));
        final plan = await planOf([source, other]);
        final out = 'crop_out_$rotate.pdf';
        runCombineMerge(await jobFor(dir, plan, output: out));
        final before = PdfDocument(inputBytes: source.readAsBytesSync());
        final after = PdfDocument(
            inputBytes: File(p.join(dir.path, out)).readAsBytesSync());
        expect(after.pages[0].size, before.pages[0].size,
            reason: 'rotate $rotate');
        expect(after.pages[0].size, const Size(400, 500));
        expect(after.pages[0].rotation.index, before.pages[0].rotation.index);
        final lineBefore =
            PdfTextExtractor(before).extractTextLines(startPageIndex: 0).first;
        final lineAfter =
            PdfTextExtractor(after).extractTextLines(startPageIndex: 0).first;
        expect(lineAfter.text, lineBefore.text);
        for (final edge in [
          [lineAfter.bounds.left, lineBefore.bounds.left],
          [lineAfter.bounds.top, lineBefore.bounds.top],
          [lineAfter.bounds.right, lineBefore.bounds.right],
          [lineAfter.bounds.bottom, lineBefore.bounds.bottom],
        ]) {
          expect(edge[0], closeTo(edge[1], 0.01), reason: 'rotate $rotate');
        }
        before.dispose();
        after.dispose();
      }
    });

    test('text stays searchable and an embedded font stays embedded', () async {
      final font =
          File('assets/fonts/Noto_Sans/NotoSans-VariableFont_wdth,wght.ttf')
              .readAsBytesSync();
      final a = await writeFile(
          dir, 'a.pdf', buildPdf('Embedded', count: 2, fontBytes: font));
      final b = await writeFile(dir, 'b.pdf', buildPdf('Plain', count: 1));
      final sourceBytes = a.readAsBytesSync();
      expect(String.fromCharCodes(sourceBytes).contains('FontFile2'), isTrue,
          reason: 'the fixture must embed a font program');
      final plan = await planOf([a, b]);
      runCombineMerge(await jobFor(dir, plan));
      final outBytes = File(p.join(dir.path, 'out.pdf')).readAsBytesSync();
      expect(String.fromCharCodes(outBytes).contains('FontFile2'), isTrue,
          reason: 'the combined file carries the font program');
      expect(readPdf(outBytes).texts,
          ['Embedded page 1', 'Embedded page 2', 'Plain page 1']);
    });

    test(
        'form values are flattened onto the page; links, annotations and '
        'bookmarks are not carried (documented limit)', () async {
      final rich = await writeFile(
          dir,
          'rich.pdf',
          buildPdf('R',
              count: 2, form: true, link: true, bookmark: true, markup: true));
      final plain = await writeFile(dir, 'plain.pdf', buildPdf('P', count: 1));
      final source = readPdf(rich.readAsBytesSync());
      expect(source.formFieldCount, 1);
      expect(source.bookmarkCount, 1);
      expect(source.annotationCount, greaterThan(0));
      final plan = await planOf([rich, plain]);
      runCombineMerge(await jobFor(dir, plan));
      final out = readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync());
      expect(out.pageCount, 3);
      // The field is gone as a field, but its value is page content now.
      expect(out.formFieldCount, 0);
      expect(out.texts.first, contains('filled value'));
      // Links, annotation objects and bookmarks do not survive a page template.
      expect(out.annotationCount, 0);
      expect(out.bookmarkCount, 0);
    });

    test('the originals are never changed', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', form: true));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final beforeA = a.readAsBytesSync();
      final beforeB = b.readAsBytesSync();
      final modifiedA = a.lastModifiedSync();
      final plan = await planOf([a, b]);
      runCombineMerge(await jobFor(dir, plan));
      expect(a.readAsBytesSync(), beforeA);
      expect(b.readAsBytesSync(), beforeB);
      expect(a.lastModifiedSync(), modifiedA);
    });
  });

  group('all or nothing', () {
    Future<void> expectNothingWritten(String name) async {
      expect(File(p.join(dir.path, name)).existsSync(), isFalse);
      expect(relativeFiles(dir).where((f) => f.startsWith('out')).toList(),
          isEmpty);
    }

    test('a source that turned corrupt after selection fails the whole combine',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final c = await writeFile(dir, 'c.pdf', buildPdf('C'));
      final plan = await planOf([a, b, c]);
      final original = c.readAsBytesSync();
      // Same length, so only reading it can tell.
      c.writeAsBytesSync(
          Uint8List(original.length)..setAll(0, original.reversed));
      try {
        runCombineMerge(await jobFor(dir, plan));
        fail('expected a failure');
      } on CombinePdfException catch (error) {
        expect(error.kind, CombinePdfFailure.corruptSource);
        expect(error.sourceId, plan.sources[2].id);
      }
      await expectNothingWritten('out.pdf');
    });

    test('a file that changed size or vanished is named, nothing is written',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final plan = await planOf([a, b]);
      b.writeAsBytesSync(buildPdf('B', count: 5));
      expect(
          () => runCombineMerge(CombineMergeJob(
              sources: plan.sources,
              pages: plan.pages,
              outputPath: p.join(dir.path, 'out.pdf'))),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.sourceChanged)
              .having((e) => e.sourceId, 'sourceId', plan.sources[1].id)));
      await expectNothingWritten('out.pdf');
      b.deleteSync();
      expect(
          () => runCombineMerge(CombineMergeJob(
              sources: plan.sources,
              pages: plan.pages,
              outputPath: p.join(dir.path, 'out.pdf'))),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.missingSource)));
      await expectNothingWritten('out.pdf');
    });

    test('a page that no longer exists in its source is not skipped', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 2));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 2));
      final plan = await planOf([a, b]);
      final pages = [
        ...plan.pages,
        CombinePageRef(sourceId: plan.sources[1].id, pageIndex: 9),
      ];
      expect(
          () => runCombineMerge(CombineMergeJob(
              sources: plan.sources,
              pages: pages,
              outputPath: p.join(dir.path, 'out.pdf'))),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.sourceChanged)));
      await expectNothingWritten('out.pdf');
    });

    test('a signed or encrypted source met at combine time is refused',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final plan = await planOf([a, b]);
      // The files are swapped for protected ones of a different size, then the
      // recorded size is made to match, as a stale selection would not.
      final signed = buildPdf('B', sign: true);
      b.writeAsBytesSync(signed);
      final staleSigned = CombineSource(
          id: plan.sources[1].id,
          path: b.path,
          displayName: 'b.pdf',
          size: signed.length,
          pageCount: 3);
      expect(
          () => runCombineMerge(CombineMergeJob(
              sources: [plan.sources[0], staleSigned],
              pages: plan.pages,
              outputPath: p.join(dir.path, 'out.pdf'))),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.signedSource)));
      final locked = buildPdf('B', userPassword: 'u', ownerPassword: 'o');
      b.writeAsBytesSync(locked);
      final staleLocked = CombineSource(
          id: plan.sources[1].id,
          path: b.path,
          displayName: 'b.pdf',
          size: locked.length,
          pageCount: 3);
      expect(
          () => runCombineMerge(CombineMergeJob(
              sources: [plan.sources[0], staleLocked],
              pages: plan.pages,
              outputPath: p.join(dir.path, 'out.pdf'))),
          throwsA(isA<CombinePdfException>().having(
              (e) => e.kind, 'kind', CombinePdfFailure.encryptedSource)));
      await expectNothingWritten('out.pdf');
    });

    test('cancelling stops the combine and leaves no output', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 5));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 5));
      final plan = await planOf([a, b]);
      var calls = 0;
      expect(
          () => runCombineMerge(await_jobSync(dir, plan),
              isCancelled: () => ++calls > 3),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.cancelled)));
      await expectNothingWritten('out.pdf');
    });

    test('an unwritable output path fails without claiming success', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final plan = await planOf([a, b]);
      // A folder where the file should go cannot be written as a file.
      Directory(p.join(dir.path, 'out.pdf')).createSync();
      expect(() => runCombineMerge(await_jobSync(dir, plan)),
          throwsA(isA<CombinePdfException>()));
    });
  });

  group('the combined file is checked before it is accepted', () {
    CombineExpectedPage page(Size size, int rotation, String? text) =>
        CombineExpectedPage(size, rotation, text);

    test('a missing page, a reordered page and a wrong rotation are caught',
        () async {
      final bytes = buildPdf('X', count: 3);
      final file = await writeFile(dir, 'x.pdf', bytes);
      const size = Size(595, 842);
      final right = [
        page(size, 0, 'X page 1'),
        page(size, 0, 'X page 2'),
        page(size, 0, 'X page 3'),
      ];
      verifyCombineOutput(file, right); // the control passes

      // One page too many expected: the output is missing a page.
      expect(
          () =>
              verifyCombineOutput(file, [...right, page(size, 0, 'X page 4')]),
          throwsCombine(CombinePdfFailure.outputInvalid));
      // One page fewer expected: the output has an extra page.
      expect(() => verifyCombineOutput(file, right.sublist(0, 2)),
          throwsCombine(CombinePdfFailure.outputInvalid));
      // Two pages in the wrong order.
      expect(() => verifyCombineOutput(file, [right[1], right[0], right[2]]),
          throwsCombine(CombinePdfFailure.outputInvalid));
      // A page that should have been turned.
      expect(
          () => verifyCombineOutput(
              file, [right[0], page(size, 1, 'X page 2'), right[2]]),
          throwsCombine(CombinePdfFailure.outputInvalid));
      // A page of the wrong size.
      expect(
          () => verifyCombineOutput(file,
              [right[0], page(const Size(100, 100), 0, 'X page 2'), right[2]]),
          throwsCombine(CombinePdfFailure.outputInvalid));
    });

    test('a truncated or empty output is never accepted', () async {
      final bytes = buildPdf('X', count: 2);
      final cut =
          await writeFile(dir, 'cut.pdf', bytes.sublist(0, bytes.length ~/ 2));
      final empty = await writeFile(dir, 'empty.pdf', <int>[]);
      const size = Size(595, 842);
      final expected = [
        CombineExpectedPage(size, 0, 'X page 1'),
        CombineExpectedPage(size, 0, 'X page 2'),
      ];
      expect(() => verifyCombineOutput(cut, expected),
          throwsCombine(CombinePdfFailure.outputInvalid));
      expect(() => verifyCombineOutput(empty, expected),
          throwsCombine(CombinePdfFailure.outputInvalid));
    });
  });

  group('the executor', () {
    test('the inline executor combines and honours a cancelled token',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final plan = await planOf([a, b]);
      const executor = InlineCombineExecutor();
      final token = CombineCancelToken()..cancel();
      await expectLater(
          executor.merge(await jobFor(dir, plan), token),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.cancelled)));
      final ok =
          await executor.merge(await jobFor(dir, plan), CombineCancelToken());
      expect(ok.pageCount, 6);
    });

    test('the isolate executor combines on a worker isolate', () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 2));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 2));
      final plan = await planOf([a, b]);
      const executor = IsolateCombineExecutor();
      final analysis = await executor.analyze(a.path);
      expect(analysis.pageCount, 2);
      await expectLater(
          executor.analyze(p.join(dir.path, 'none.pdf')),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.missingSource)));
      final result =
          await executor.merge(await jobFor(dir, plan), CombineCancelToken());
      expect(result.pageCount, 4);
      expect(readPdf(File(p.join(dir.path, 'out.pdf')).readAsBytesSync()).texts,
          ['A page 1', 'A page 2', 'B page 1', 'B page 2']);
    });

    test('the isolate executor reports a failure as a CombinePdfException',
        () async {
      final a = await writeFile(dir, 'a.pdf', buildPdf('A'));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B'));
      final plan = await planOf([a, b]);
      b.deleteSync();
      await expectLater(
          const IsolateCombineExecutor()
              .merge(await jobFor(dir, plan), CombineCancelToken()),
          throwsA(isA<CombinePdfException>()
              .having((e) => e.kind, 'kind', CombinePdfFailure.missingSource)
              .having((e) => e.sourceId, 'sourceId', plan.sources[1].id)));
      expect(File(p.join(dir.path, 'out.pdf')).existsSync(), isFalse);
    });

    test('cancelling stops a running isolate combine at once', () async {
      // Enough pages that the combine is still running when it is cancelled.
      final a = await writeFile(dir, 'a.pdf', buildPdf('A', count: 150));
      final b = await writeFile(dir, 'b.pdf', buildPdf('B', count: 150));
      final plan = await planOf([a, b]);
      final token = CombineCancelToken();
      final future =
          const IsolateCombineExecutor().merge(await jobFor(dir, plan), token);
      final outcome = future.then<Object?>((r) => r, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      token.cancel();
      final result = await outcome;
      expect(result, isA<CombinePdfException>());
      expect((result as CombinePdfException).kind, CombinePdfFailure.cancelled);
    });
  });
}

CombineMergeJob await_jobSync(Directory dir, CombinePlan plan) {
  return CombineMergeJob(
    sources: plan.sources,
    pages: plan.pages,
    outputPath: p.join(dir.path, 'out.pdf'),
  );
}
