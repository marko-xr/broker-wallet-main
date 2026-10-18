import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfPageRotateAngle;

import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';

import 'signature_fixtures.dart';

class _Stamped {
  _Stamped(this.source, this.original, this.analysis, this.result, this.output);

  final File source;
  final Uint8List original;
  final SignatureAnalysis analysis;
  final SignatureWriteResult result;
  final Uint8List output;

  List<DrawnImage> get drawn => imagesDrawnByUpdate(output, original.length);
}

/// Where in the page's alpha plane the only opaque pixel of the stamp is, found
/// in the update's image streams (an alpha plane is [width] x [height] bytes).
({int x, int y})? alphaMark(
    Uint8List output, int originalLength, int width, int height) {
  for (final stream in appendedStreams(output, originalLength)) {
    if (stream.length != width * height) continue;
    final bytes = stream.codeUnits;
    final on = <int>[
      for (var i = 0; i < bytes.length; i++)
        if (bytes[i] != 0) i,
    ];
    if (on.length == 1 && bytes[on.first] == 255) {
      return (x: on.first % width, y: on.first ~/ width);
    }
  }
  return null;
}

void main() {
  late Directory dir;
  var counter = 0;

  setUp(() => dir = makeTempDir('engine'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<File> save(String name, List<int> bytes) =>
      writeFile(dir, name, bytes);

  Future<_Stamped> stamp(
    List<int> pdf,
    List<({int page, PageRect rect})> placements, {
    Uint8List? png,
  }) async {
    final source = await save('in${counter++}.pdf', pdf);
    final original = source.readAsBytesSync();
    final analysis = analysisOf(source);
    final outPath = p.join(dir.path, 'out${counter++}.pdf');
    final result = runSignatureWrite(
        jobFor(source, outPath, placements, png: png, analysis: analysis));
    return _Stamped(
        source, original, analysis, result, File(outPath).readAsBytesSync());
  }

  void expectRects(List<DrawnImage> drawn, List<UserRect> expected,
      {double eps = 0.02}) {
    expect(drawn.length, expected.length);
    int byPlace(UserRect a, UserRect b) {
      final c = a.left.compareTo(b.left);
      return c != 0 ? c : a.bottom.compareTo(b.bottom);
    }

    final got = [for (final d in drawn) d.rect]..sort(byPlace);
    final want = [...expected]..sort(byPlace);
    for (var i = 0; i < want.length; i++) {
      expect(got[i].isCloseTo(want[i], eps), isTrue,
          reason: 'image $i is at ${got[i]}, wanted ${want[i]}');
    }
    for (final d in drawn) {
      expect(d.axisAligned, isTrue, reason: 'the image must be upright');
    }
  }

  group('reading a PDF', () {
    test('a plain PDF: pages, sizes, no rotation, nothing special', () async {
      final file = await save('plain.pdf', buildPdf('A', count: 3));
      final analysis = analysisOf(file);
      expect(analysis.pageCount, 3);
      expect(analysis.size, file.lengthSync());
      for (final geometry in analysis.pages) {
        expect(geometry.width, closeTo(595, 0.01));
        expect(geometry.height, closeTo(842, 0.01));
        expect(geometry.rotation, 0);
        expect(geometry.cropBox, isNull);
      }
      expect(analysis.features.hasSignatures, isFalse);
      expect(analysis.features.hasFormFields, isFalse);
      expect(analysis.features.hasAnnotations, isFalse);
      expect(analysis.formFieldCount, 0);
      expect(analysis.annotationCounts, <int>[0, 0, 0]);
    });

    test('pages of different sizes and orientations keep their own geometry',
        () async {
      final specs = <PageSpec>[
        a4,
        a4Landscape,
        const PageSpec(612, 792),
        const PageSpec(842, 1191),
        const PageSpec(612, 1008),
        const PageSpec(333, 777),
      ];
      final file = await save('mixed.pdf', buildPdf('M', pages: specs));
      final analysis = analysisOf(file);
      expect(analysis.pageCount, specs.length);
      for (var i = 0; i < specs.length; i++) {
        expect(analysis.pages[i].width, closeTo(specs[i].width, 0.01),
            reason: 'page $i');
        expect(analysis.pages[i].height, closeTo(specs[i].height, 0.01),
            reason: 'page $i');
      }
    });

    test('a rotated page reports its rotation and the turned visible size',
        () async {
      final turns = <PdfPageRotateAngle, int>{
        PdfPageRotateAngle.rotateAngle90: 90,
        PdfPageRotateAngle.rotateAngle180: 180,
        PdfPageRotateAngle.rotateAngle270: 270,
      };
      for (final entry in turns.entries) {
        final file = await save('rot${entry.value}.pdf',
            buildPdf('R', pages: [PageSpec(595, 842, rotate: entry.key)]));
        final geometry = analysisOf(file).pages.single;
        expect(geometry.rotation, entry.value);
        final swapped = entry.value == 90 || entry.value == 270;
        expect(geometry.width, closeTo(swapped ? 842 : 595, 0.01));
        expect(geometry.height, closeTo(swapped ? 595 : 842, 0.01));
      }
    });

    test('a CropBox with an origin, alone and with rotation', () async {
      for (final rotate in [0, 90, 180, 270, -90, 450]) {
        final file = await save('crop$rotate.pdf', cropBoxPdf(rotate: rotate));
        final geometry = analysisOf(file).pages.single;
        expect(geometry.mediaBox, const PdfBox(0, 0, 612, 792));
        expect(geometry.cropBox, const PdfBox(100, 100, 500, 600));
        expect(geometry.rotation, PageGeometry.normalizeRotation(rotate));
        final swapped = geometry.rotation == 90 || geometry.rotation == 270;
        expect(geometry.width, swapped ? 500 : 400);
        expect(geometry.height, swapped ? 400 : 500);
      }
    });

    test('boxes and rotation inherited from the page tree are found', () async {
      final file = await save(
          'inherit.pdf',
          pdfWithBoxes(
              media: '[0 0 300 400]',
              crop: '[10 20 210 320]',
              rotate: 90,
              inherit: true));
      final geometry = analysisOf(file).pages.single;
      expect(geometry.mediaBox, const PdfBox(0, 0, 300, 400));
      expect(geometry.cropBox, const PdfBox(10, 20, 210, 320));
      expect(geometry.rotation, 90);
      expect(geometry.width, 300);
      expect(geometry.height, 200);
    });

    test('a CropBox bigger than the MediaBox is clipped, a flat one ignored',
        () async {
      final big = analysisOf(await save(
              'big.pdf',
              pdfWithBoxes(
                  media: '[0 0 612 792]', crop: '[-100 -100 900 900]')))
          .pages
          .single;
      expect(big.width, 612);
      expect(big.height, 792);
      final flat = analysisOf(await save('flat.pdf',
              pdfWithBoxes(media: '[0 0 612 792]', crop: '[50 50 50 600]')))
          .pages
          .single;
      expect(flat.cropBox, isNull);
      expect(flat.width, 612);
    });

    test('corners in either order give the same page', () async {
      final geometry = analysisOf(
              await save('reversed.pdf', pdfWithBoxes(media: '[612 792 0 0]')))
          .pages
          .single;
      expect(geometry.mediaBox, const PdfBox(0, 0, 612, 792));
    });

    test('a CropBox that shares nothing with the MediaBox is refused',
        () async {
      final file = await save('apart.pdf',
          pdfWithBoxes(media: '[0 0 612 792]', crop: '[700 0 900 100]'));
      expect(
          () => analysisOf(file),
          throwsA(isA<SignatureException>().having(
              (e) => e.kind, 'kind', SignatureFailure.geometryUnsupported)));
    });

    test('a page with no MediaBox is refused as damaged', () async {
      final file = await save('nobox.pdf', pdfWithBoxes(media: null));
      expect(
          () => analysisOf(file),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.corruptSource)));
    });

    test('links, forms and markup are noticed and counted', () async {
      final bytes =
          buildPdf('F', count: 2, link: true, form: true, markup: true);
      final file = await save('features.pdf', bytes);
      final analysis = analysisOf(file);
      expect(analysis.features.hasFormFields, isTrue);
      expect(analysis.features.hasAnnotations, isTrue);
      expect(analysis.features.hasSignatures, isFalse);
      expect(analysis.formFieldCount, 1);
      final facts = readPdf(bytes);
      expect(analysis.annotationCounts.fold<int>(0, (a, b) => a + b),
          facts.annotationCount);
    });

    test('an existing digital signature is detected', () async {
      final file = await save('signed.pdf', buildPdf('S', sign: true));
      expect(analysisOf(file).features.hasSignatures, isTrue);
      expect(bytesContainSignatureMarker(file.readAsBytesSync()), isTrue);
    });

    test('the signature marker is found anywhere, and only when it is there',
        () {
      Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);
      expect(bytesContainSignatureMarker(bytes('/ByteRange')), isTrue);
      expect(bytesContainSignatureMarker(bytes('xx /ByteRange [0 1 2 3] yy')),
          isTrue);
      expect(bytesContainSignatureMarker(bytes('xx /ByteRang')), isFalse);
      expect(bytesContainSignatureMarker(bytes('/Byte/ByteRange')), isTrue);
      expect(bytesContainSignatureMarker(Uint8List(0)), isFalse);
      expect(bytesContainSignatureMarker(buildPdf('P')), isFalse);
    });

    test('a protected PDF is refused, with or without a user password',
        () async {
      for (final locked in [
        buildPdf('L', userPassword: 'u', ownerPassword: 'o'),
        buildPdf('L', ownerPassword: 'o'),
      ]) {
        final file = await save('locked${counter++}.pdf', locked);
        expect(
            () => analysisOf(file),
            throwsA(isA<SignatureException>().having(
                (e) => e.kind, 'kind', SignatureFailure.encryptedSource)));
      }
    });

    test('empty, missing, damaged and oversized files are refused', () async {
      SignatureFailure? kindOf(void Function() action) {
        try {
          action();
        } on SignatureException catch (e) {
          return e.kind;
        }
        return null;
      }

      final empty = await save('empty.pdf', <int>[]);
      expect(kindOf(() => analysisOf(empty)), SignatureFailure.emptySource);
      expect(kindOf(() => analysisOf(File(p.join(dir.path, 'gone.pdf')))),
          SignatureFailure.missingSource);
      final junk = await save('junk.pdf', 'not a pdf at all'.codeUnits);
      expect(kindOf(() => analysisOf(junk)), SignatureFailure.corruptSource);
      final headerOnly =
          await save('header.pdf', '%PDF-1.4\nnothing else'.codeUnits);
      expect(
          kindOf(() => analysisOf(headerOnly)), SignatureFailure.corruptSource);
      final big = await save('big.pdf', buildPdf('B'));
      expect(kindOf(() => analyzeSignaturePdf(big.path, maxBytes: 10)),
          SignatureFailure.tooLargeSource);
    });
  });

  group('writing: where a stamp lands', () {
    test('on an upright A4 page, exactly where the geometry says', () async {
      const rect = PageRect(100, 150, 180, 60);
      final s = await stamp(buildPdf('A', count: 3), [(page: 0, rect: rect)]);
      expectRects(s.drawn, [s.analysis.pages[0].userRectOf(rect)]);
      // 100 from the left edge, 150 down from the top of an 842 high page.
      expect(s.drawn.single.rect.left, closeTo(100, 0.02));
      expect(s.drawn.single.rect.top, closeTo(842 - 150, 0.02));
      expect(s.drawn.single.rect.width, closeTo(180, 0.02));
      expect(s.drawn.single.rect.height, closeTo(60, 0.02));
    });

    final specs = <String, PageSpec>{
      'A3': const PageSpec(842, 1191),
      'A4': a4,
      'A4 landscape': a4Landscape,
      'Letter': const PageSpec(612, 792),
      'Legal': const PageSpec(612, 1008),
      'an arbitrary size': const PageSpec(333, 777),
    };
    specs.forEach((name, spec) {
      test('on $name, in each corner and in the middle', () async {
        final w = spec.width;
        final h = spec.height;
        final rects = <PageRect>[
          PageRect(0, 0, w * 0.25, w * 0.08),
          PageRect(w * 0.75, 0, w * 0.25, w * 0.08),
          PageRect(0, h - w * 0.08, w * 0.25, w * 0.08),
          PageRect(w * 0.75, h - w * 0.08, w * 0.25, w * 0.08),
          PageRect(w * 0.375, h * 0.5, w * 0.25, w * 0.08),
        ];
        final s = await stamp(buildPdf('S', pages: [spec]),
            [for (final r in rects) (page: 0, rect: r)]);
        expectRects(s.drawn,
            [for (final r in rects) s.analysis.pages[0].userRectOf(r)]);
      });
    });

    test('on a page turned 90, 180 and 270 degrees', () async {
      const rect = PageRect(50, 100, 200, 80);
      for (final angle in [
        PdfPageRotateAngle.rotateAngle90,
        PdfPageRotateAngle.rotateAngle180,
        PdfPageRotateAngle.rotateAngle270,
      ]) {
        final s = await stamp(
            buildPdf('R', pages: [PageSpec(595, 842, rotate: angle)]),
            [(page: 0, rect: rect)]);
        final geometry = s.analysis.pages[0];
        expectRects(s.drawn, [geometry.userRectOf(rect)]);
        // A quarter turn swaps the stamp's width and height in user space.
        final swapped = geometry.rotation == 90 || geometry.rotation == 270;
        expect(s.drawn.single.rect.width, closeTo(swapped ? 80 : 200, 0.02));
        expect(s.drawn.single.rect.height, closeTo(swapped ? 200 : 80, 0.02));
      }
    });

    test('with a CropBox that has an origin, on every rotation', () async {
      const rect = PageRect(20, 30, 100, 40);
      for (final rotate in [0, 90, 180, 270]) {
        final s =
            await stamp(cropBoxPdf(rotate: rotate), [(page: 0, rect: rect)]);
        final geometry = s.analysis.pages[0];
        final expected = geometry.userRectOf(rect);
        expectRects(s.drawn, [expected]);
        // Inside the visible box, whatever the rotation.
        final box = geometry.box;
        expect(expected.left, greaterThanOrEqualTo(box.left - 0.001));
        expect(expected.bottom, greaterThanOrEqualTo(box.bottom - 0.001));
        expect(expected.right, lessThanOrEqualTo(box.right + 0.001));
        expect(expected.top, lessThanOrEqualTo(box.top + 0.001));
      }
    });

    test('with boxes inherited from the page tree', () async {
      const rect = PageRect(10, 10, 60, 20);
      final s = await stamp(
          pdfWithBoxes(
              media: '[0 0 300 400]',
              crop: '[10 20 210 320]',
              rotate: 90,
              inherit: true),
          [(page: 0, rect: rect)]);
      expectRects(s.drawn, [s.analysis.pages[0].userRectOf(rect)]);
    });

    test('with a MediaBox that does not start at the origin', () async {
      const rect = PageRect(30, 40, 100, 50);
      final s = await stamp(
          pdfWithBoxes(media: '[-50 -80 550 720]'), [(page: 0, rect: rect)]);
      expectRects(s.drawn, [s.analysis.pages[0].userRectOf(rect)]);
      // The top of the page is y = 720, 40 points above the stamp's top edge.
      expect(s.drawn.single.rect.top, closeTo(720 - 40, 0.02));
      expect(s.drawn.single.rect.left, closeTo(-50 + 30, 0.02));
    });

    test('with a MediaBox whose corners are written the other way round',
        () async {
      const rect = PageRect(30, 40, 100, 50);
      final s = await stamp(
          pdfWithBoxes(media: '[612 792 0 0]'), [(page: 0, rect: rect)]);
      expectRects(s.drawn, [s.analysis.pages[0].userRectOf(rect)]);
      expect(s.drawn.single.rect.top, closeTo(792 - 40, 0.02));
    });

    test('keeping the stamp\'s proportions exactly', () async {
      const rect = PageRect(60, 80, 150, 50);
      for (final angle in [
        PdfPageRotateAngle.rotateAngle0,
        PdfPageRotateAngle.rotateAngle90,
      ]) {
        final s = await stamp(
            buildPdf('P', pages: [PageSpec(595, 842, rotate: angle)]),
            [(page: 0, rect: rect)]);
        final image = s.drawn.single.rect;
        final upright = angle == PdfPageRotateAngle.rotateAngle0;
        expect(
            upright ? image.width / image.height : image.height / image.width,
            closeTo(rect.aspect, 1e-3));
      }
    });

    test('several stamps on one page stay independent', () async {
      const rects = [
        PageRect(40, 60, 150, 50),
        PageRect(300, 300, 90, 30),
        PageRect(100, 700, 200, 70),
      ];
      final s = await stamp(
          buildPdf('M', count: 2), [for (final r in rects) (page: 1, rect: r)]);
      expectRects(
          s.drawn, [for (final r in rects) s.analysis.pages[1].userRectOf(r)]);
    });

    test('different placements on different pages, of different sizes',
        () async {
      const first = PageRect(40, 60, 150, 50);
      const third = PageRect(300, 300, 200, 60);
      final s = await stamp(
          buildPdf('D', pages: [a4, a4Landscape, const PageSpec(612, 792)]),
          [(page: 0, rect: first), (page: 2, rect: third)]);
      expectRects(s.drawn, [
        s.analysis.pages[0].userRectOf(first),
        s.analysis.pages[2].userRectOf(third),
      ]);
      // The page in between was not touched.
      expect(readPdf(s.output).texts[1], readPdf(s.original).texts[1]);
    });

    test('only the pages that were chosen are changed', () async {
      final s = await stamp(buildPdf('C', count: 3),
          [(page: 1, rect: const PageRect(40, 60, 150, 50))]);
      expect(s.drawn.length, 1);
      final before = readPdf(s.original);
      final after = readPdf(s.output);
      expect(after.pageCount, before.pageCount);
      expect(after.texts, before.texts);
    });
  });

  group('writing: the stamp image is turned to match the page', () {
    test('a PNG is turned the other way from the page', () {
      final png = markedPng();
      expect(identical(stampPngForPageRotation(png, 0), png), isTrue);
      final r90 = markOf(stampPngForPageRotation(png, 90));
      expect((r90.width, r90.height, r90.x, r90.y), (2, 4, 0, 3));
      final r180 = markOf(stampPngForPageRotation(png, 180));
      expect((r180.width, r180.height, r180.x, r180.y), (4, 2, 3, 1));
      final r270 = markOf(stampPngForPageRotation(png, 270));
      expect((r270.width, r270.height, r270.x, r270.y), (2, 4, 1, 0));
    });

    test('a damaged image is a failure, not a corrupt page', () {
      expect(
          () => stampPngForPageRotation(Uint8List.fromList([1, 2, 3]), 90),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.stampFailed)));
    });

    test('the image embedded in the saved page is the turned one', () async {
      // The mark of a 4 x 2 stamp, found in the alpha plane the file carries,
      // for each rotation of the page.
      const expected = <int, ({int w, int h, int x, int y})>{
        0: (w: 4, h: 2, x: 0, y: 0),
        90: (w: 2, h: 4, x: 0, y: 3),
        180: (w: 4, h: 2, x: 3, y: 1),
        270: (w: 2, h: 4, x: 1, y: 0),
      };
      final angles = <int, PdfPageRotateAngle>{
        0: PdfPageRotateAngle.rotateAngle0,
        90: PdfPageRotateAngle.rotateAngle90,
        180: PdfPageRotateAngle.rotateAngle180,
        270: PdfPageRotateAngle.rotateAngle270,
      };
      for (final entry in expected.entries) {
        final s = await stamp(
          buildPdf('T',
              pages: [PageSpec(595, 842, rotate: angles[entry.key]!)]),
          [(page: 0, rect: const PageRect(50, 100, 100, 50))],
          png: markedPng(),
        );
        final mark = alphaMark(
            s.output, s.original.length, entry.value.w, entry.value.h);
        expect(mark, isNotNull, reason: 'rotation ${entry.key}');
        expect((mark!.x, mark.y), (entry.value.x, entry.value.y),
            reason: 'rotation ${entry.key}');
      }
    });

    test('the engine gets its image through the rotation function', () {
      final source =
          File('lib/src/services/signature/signature_pdf_engine.dart')
              .readAsStringSync();
      expect(source, contains('stampPngForPageRotation('));
      expect(source, contains('geometry.rotation'));
    });
  });

  group('writing: what is kept', () {
    test('the original bytes come first and only an update is appended',
        () async {
      for (final bytes in [
        buildPdf('A', count: 3),
        buildPdf('B', count: 2, link: true, form: true, markup: true),
        cropBoxPdf(rotate: 90),
        buildPdf('C', pages: [a4, a4Landscape]),
      ]) {
        final s = await stamp(bytes, [
          (page: 0, rect: const PageRect(20, 30, 100, 40)),
        ]);
        expect(s.result.appendedOnly, isTrue);
        expect(s.output.length, greaterThan(s.original.length));
        expect(s.output.sublist(0, s.original.length), s.original);
      }
    });

    test('the source file itself is never written', () async {
      final s = await stamp(buildPdf('A', count: 2),
          [(page: 0, rect: const PageRect(20, 30, 100, 40))]);
      expect(s.source.readAsBytesSync(), s.original);
    });

    test('links, form fields, markup, bookmarks and text are all still there',
        () async {
      final bytes = buildPdf('K',
          count: 3, link: true, form: true, markup: true, bookmark: true);
      final s = await stamp(bytes, [
        (page: 0, rect: const PageRect(20, 300, 100, 40)),
        (page: 2, rect: const PageRect(20, 300, 100, 40)),
      ]);
      final before = readPdf(s.original);
      final after = readPdf(s.output);
      expect(after.pageCount, before.pageCount);
      expect(after.annotationCount, before.annotationCount);
      expect(after.formFieldCount, before.formFieldCount);
      expect(after.bookmarkCount, before.bookmarkCount);
      expect(after.texts, before.texts);
      expect(after.sizes, before.sizes);
      expect(after.rotations, before.rotations);
      expect(s.result.pageCount, 3);
      expect(s.result.placementCount, 2);
      expect(s.result.size, s.output.length);
    });

    test('the output is a PDF the library reads, with every page intact',
        () async {
      final s = await stamp(buildPdf('V', count: 4, pages: [a4, a4, a4, a4]),
          [(page: 3, rect: const PageRect(20, 30, 100, 40))]);
      final analysis = analyzeSignaturePdf(
          (await save('check.pdf', s.output)).path,
          maxBytes: testMaxBytes);
      expect(analysis.pageCount, 4);
      expect(analysis.features.hasSignatures, isFalse);
    });
  });

  group('writing: what is refused', () {
    PageRect good() => const PageRect(20, 30, 100, 40);

    Future<void> expectRefused(
      SignatureWriteJob Function(File source, String out) build,
      SignatureFailure kind, {
      List<int>? pdf,
    }) async {
      final source =
          await save('r${counter++}.pdf', pdf ?? buildPdf('A', count: 2));
      final out = p.join(dir.path, 'refused${counter++}.pdf');
      expect(
          () => runSignatureWrite(build(source, out)),
          throwsA(
              isA<SignatureException>().having((e) => e.kind, 'kind', kind)));
      expect(File(out).existsSync(), isFalse, reason: 'no output may remain');
    }

    test('a placement outside its page, too small, or not a number', () async {
      for (final rect in <PageRect>[
        const PageRect(500, 30, 100, 40),
        const PageRect(20, 820, 100, 40),
        const PageRect(-20, 30, 100, 40),
        const PageRect(20, 30, 0.5, 40),
        const PageRect(20, 30, 100, 0),
        const PageRect(double.nan, 30, 100, 40),
        const PageRect(20, 30, double.infinity, 40),
      ]) {
        await expectRefused(
            (source, out) => jobFor(source, out, [(page: 0, rect: rect)]),
            SignatureFailure.invalidPlacement);
      }
    });

    test('a page or an image that does not exist', () async {
      await expectRefused(
          (source, out) => jobFor(source, out, [(page: 2, rect: good())]),
          SignatureFailure.invalidPlacement);
      await expectRefused(
          (source, out) => jobFor(source, out, [(page: -1, rect: good())]),
          SignatureFailure.invalidPlacement);
      await expectRefused(
          (source, out) => SignatureWriteJob(
                sourcePath: source.path,
                source: analysisOf(source),
                images: <Uint8List>[stampPng()],
                placements: <SignatureWritePlacement>[
                  SignatureWritePlacement(
                      pageIndex: 0, imageIndex: 3, rect: good()),
                ],
                outputPath: out,
              ),
          SignatureFailure.invalidPlacement);
    });

    test('nothing to place, and more items than a document may carry',
        () async {
      await expectRefused((source, out) => jobFor(source, out, const []),
          SignatureFailure.noPlacements);
      await expectRefused(
          (source, out) => jobFor(source, out, [
                for (var i = 0; i < SignatureLimits.maxItems + 1; i++)
                  (page: 0, rect: good()),
              ]),
          SignatureFailure.tooManyItems);
    });

    test('a signed PDF and a protected PDF', () async {
      final signed = buildPdf('S', sign: true);
      await expectRefused(
          (source, out) => SignatureWriteJob(
                sourcePath: source.path,
                source: SignatureAnalysis(
                  size: source.lengthSync(),
                  pageCount: 1,
                  pages: const [
                    PageGeometry(mediaBox: PdfBox(0, 0, 595, 842)),
                  ],
                  features: const SignatureFeatures(),
                ),
                images: <Uint8List>[stampPng()],
                placements: <SignatureWritePlacement>[
                  SignatureWritePlacement(
                      pageIndex: 0, imageIndex: 0, rect: good()),
                ],
                outputPath: out,
              ),
          SignatureFailure.signedSource,
          pdf: signed);
      final locked = buildPdf('L', userPassword: 'u', ownerPassword: 'o');
      await expectRefused(
          (source, out) => SignatureWriteJob(
                sourcePath: source.path,
                source: SignatureAnalysis(
                  size: source.lengthSync(),
                  pageCount: 1,
                  pages: const [
                    PageGeometry(mediaBox: PdfBox(0, 0, 595, 842)),
                  ],
                  features: const SignatureFeatures(),
                ),
                images: <Uint8List>[stampPng()],
                placements: <SignatureWritePlacement>[
                  SignatureWritePlacement(
                      pageIndex: 0, imageIndex: 0, rect: good()),
                ],
                outputPath: out,
              ),
          SignatureFailure.encryptedSource,
          pdf: locked);
    });

    test('a source that changed or vanished after it was opened', () async {
      final source = await save('changing.pdf', buildPdf('A', count: 2));
      final analysis = analysisOf(source);
      final out = p.join(dir.path, 'changed.pdf');
      // A file that grew is not the file that was opened.
      await source.writeAsBytes(<int>[...source.readAsBytesSync(), 10, 10]);
      expect(
          () => runSignatureWrite(jobFor(source, out, [(page: 0, rect: good())],
              analysis: analysis)),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.sourceChanged)));
      await source.delete();
      expect(
          () => runSignatureWrite(jobFor(source, out, [(page: 0, rect: good())],
              analysis: analysis)),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.missingSource)));
      expect(File(out).existsSync(), isFalse);
    });

    test('a page whose geometry is not what the editor showed', () async {
      final source = await save('geometry.pdf', buildPdf('A', count: 2));
      final real = analysisOf(source);
      final wrong = SignatureAnalysis(
        size: real.size,
        pageCount: real.pageCount,
        pages: const [
          PageGeometry(mediaBox: PdfBox(0, 0, 842, 1191)),
          PageGeometry(mediaBox: PdfBox(0, 0, 595, 842)),
        ],
        features: real.features,
        formFieldCount: real.formFieldCount,
        annotationCounts: real.annotationCounts,
      );
      final out = p.join(dir.path, 'wrong.pdf');
      expect(
          () => runSignatureWrite(
              jobFor(source, out, [(page: 0, rect: good())], analysis: wrong)),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.sourceChanged)));
      expect(File(out).existsSync(), isFalse);
    });

    test('a cancel stops the write and leaves nothing', () async {
      final source = await save('cancel.pdf', buildPdf('A', count: 2));
      final out = p.join(dir.path, 'cancelled.pdf');
      expect(
          () => runSignatureWrite(
              jobFor(source, out, [(page: 0, rect: good())]),
              isCancelled: () => true),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.cancelled)));
      expect(File(out).existsSync(), isFalse);
    });

    test('an output place that cannot be written is a failure with no file',
        () async {
      final source = await save('nowhere.pdf', buildPdf('A', count: 2));
      final blocker = await save('blocker', <int>[1]);
      final out = p.join(blocker.path, 'inside.pdf');
      expect(
          () =>
              runSignatureWrite(jobFor(source, out, [(page: 0, rect: good())])),
          throwsA(isA<SignatureException>()));
      expect(File(out).existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
    });
  });

  group('verifying a signed copy', () {
    SignatureAnalysis analysisOfBytes(List<int> bytes) {
      final file = File(p.join(dir.path, 'v${counter++}.pdf'))
        ..writeAsBytesSync(bytes);
      return analysisOf(file);
    }

    File fileOf(List<int> bytes) =>
        File(p.join(dir.path, 'o${counter++}.pdf'))..writeAsBytesSync(bytes);

    void expectInvalid(void Function() action, String detail) {
      expect(
          action,
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.outputInvalid)
              .having((e) => e.detail, 'detail', detail)));
    }

    test('a copy that matches its source passes', () {
      final bytes = buildPdf('A', count: 2, link: true, form: true);
      final source = analysisOfBytes(bytes);
      expect(
          verifySignatureOutput(
              output: fileOf(bytes),
              source: source,
              sourceBytes: Uint8List.fromList(bytes)),
          isFalse,
          reason: 'identical bytes are not an appended update');
    });

    test('a lost page, a changed page size, a lost link or a lost field fails',
        () {
      final source = analysisOfBytes(
          buildPdf('A', count: 3, link: true, form: true, markup: true));
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A',
                  count: 2, link: true, form: true, markup: true)),
              source: source),
          'count');
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A',
                  pages: [a4Landscape, a4Landscape, a4Landscape],
                  link: true,
                  form: true,
                  markup: true)),
              source: source),
          'geometry');
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A', count: 3, form: true)),
              source: source),
          'annotations');
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A', count: 3, link: true, markup: true)),
              source: source),
          'form');
    });

    test('a copy that is protected, signed or unreadable fails', () {
      final plain = buildPdf('A', count: 1);
      final source = analysisOfBytes(plain);
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A', count: 1, ownerPassword: 'o')),
              source: source),
          'encrypted');
      expectInvalid(
          () => verifySignatureOutput(
              output: fileOf(buildPdf('A', count: 1, sign: true)),
              source: source),
          'signature');
      expect(
          () => verifySignatureOutput(
              output: fileOf('%PDF-1.4 nothing'.codeUnits), source: source),
          throwsA(isA<SignatureException>()
              .having((e) => e.kind, 'kind', SignatureFailure.outputInvalid)));
      expectInvalid(
          () => verifySignatureOutput(
              output: File(p.join(dir.path, 'absent.pdf')), source: source),
          'read');
    });
  });
}
