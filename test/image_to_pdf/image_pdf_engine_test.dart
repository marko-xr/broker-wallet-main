import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfPageSize;

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_layout.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_processor.dart';

import 'image_pdf_fixtures.dart';
import 'pdf_inspector.dart';

const double mm = ImagePdfLayout.pointsPerMm;
final DateTime stamp = DateTime(2026, 10, 18, 14, 32);

/// Distinct, easily told apart colours.
const List<(int, int, int)> palette = <(int, int, int)>[
  (230, 30, 30),
  (30, 200, 60),
  (40, 60, 230),
  (240, 220, 30),
  (30, 220, 220),
  (220, 40, 220),
  (240, 140, 20),
];

img.Image solid(int w, int h, (int, int, int) c) =>
    img.Image(width: w, height: h)..clear(img.ColorRgb8(c.$1, c.$2, c.$3));

void main() {
  late PictureFolder folder;
  var outputCounter = 0;
  setUp(() => folder = PictureFolder.create());
  tearDown(() => folder.dispose());

  /// Writes a picture and returns it as the selection screen would hold it.
  ImageSpec picture(int index, {int w = 400, int h = 300, bool asPng = false}) {
    final image = solid(w, h, palette[index % palette.length]);
    final file = folder.write('p$index.${asPng ? 'png' : 'jpg'}',
        asPng ? png(image) : jpeg(image, quality: 95));
    return folder.spec(file, analyzeImageFile(file.path), id: 'p$index');
  }

  String outPath() => '${folder.directory.path}/out${outputCounter++}.pdf';

  ({ImagePdfBuildResult result, Uint8List bytes, PdfInspector inspect}) build(
    List<ImageSpec> images, {
    ImagePdfSettings settings = const ImagePdfSettings(),
    String? password,
    ImagePdfTexts texts = const ImagePdfTexts(),
    Uint8List? font,
    DateTime? when,
    bool Function()? isCancelled,
  }) {
    final path = outPath();
    final result = buildImagePdf(
      ImagePdfBuildJob(
        images: images,
        settings: settings,
        outputPath: path,
        timestamp: when ?? stamp,
        password: password,
        texts: texts,
        unicodeFont: font,
      ),
      isCancelled: isCancelled,
    );
    final bytes = File(path).readAsBytesSync();
    return (result: result, bytes: bytes, inspect: PdfInspector(bytes));
  }

  ImagePdfException? failureOf(void Function() action) {
    try {
      action();
    } on ImagePdfException catch (error) {
      return error;
    }
    return null;
  }

  String pageText(Uint8List bytes, int page, {String? password}) {
    final doc = PdfDocument(inputBytes: bytes, password: password);
    try {
      return PdfTextExtractor(doc)
          .extractText(startPageIndex: page, endPageIndex: page);
    } finally {
      doc.dispose();
    }
  }

  /// The colour at the middle of a drawn picture.
  (int, int, int) centre(PdfInspector inspect, DrawnImage drawn) {
    final image = inspect.image(drawn.objectId).decoded!;
    final p = image.getPixel(image.width ~/ 2, image.height ~/ 2);
    return (p.r.toInt(), p.g.toInt(), p.b.toInt());
  }

  bool sameColour((int, int, int) a, (int, int, int) b) =>
      (a.$1 - b.$1).abs() < 16 &&
      (a.$2 - b.$2).abs() < 16 &&
      (a.$3 - b.$3).abs() < 16;

  group('a PDF of pictures', () {
    test('one picture is one page, placed exactly where the plan says', () {
      final spec = picture(0);
      final made = build([spec]);
      expect(made.result.pageCount, 1);
      expect(made.result.imageCount, 1);
      expect(made.result.size, made.bytes.length);
      final page = made.inspect.pages.single;
      final plan = ImagePdfLayout.plan(
          const ImagePdfSettings(), [ImageDimensions(spec.width, spec.height)]);
      final planned = plan.pages.single;
      expect(page.width, closeTo(planned.width, 0.02));
      expect(page.height, closeTo(planned.height, 0.02));
      final drawn = page.images.single;
      final rect = planned.images.single.rect;
      expect(drawn.x, closeTo(rect.x, 0.02));
      expect(drawn.top, closeTo(rect.y, 0.02));
      expect(drawn.width, closeTo(rect.width, 0.02));
      expect(drawn.height, closeTo(rect.height, 0.02));
    });

    test('every picture is kept, in the order chosen', () {
      final specs = [for (var i = 0; i < 5; i++) picture(i)];
      final made = build(specs);
      expect(made.result.pageCount, 5);
      final pages = made.inspect.pages;
      expect(pages, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(pages[i].images, hasLength(1));
        expect(
            sameColour(
                centre(made.inspect, pages[i].images.single), palette[i]),
            isTrue,
            reason: 'page ${i + 1}');
      }
    });

    test('reordering, removing and adding follow the list given', () {
      final specs = [for (var i = 0; i < 4; i++) picture(i)];
      final reordered = build([specs[2], specs[0], specs[3], specs[1]]);
      final order = [
        for (final page in reordered.inspect.pages)
          palette.indexWhere((c) =>
              sameColour(centre(reordered.inspect, page.images.single), c))
      ];
      expect(order, [2, 0, 3, 1]);
      expect(build([specs[0], specs[1], specs[3]]).result.pageCount, 3);
      expect(build([...specs, picture(5)]).result.pageCount, 5);
    });

    test('the same picture twice is two pages (intentional duplicates stay)',
        () {
      final spec = picture(1);
      final made = build([spec, spec]);
      expect(made.result.pageCount, 2);
      expect(made.inspect.pages.every((p) => p.images.length == 1), isTrue);
    });

    test('the original files are not touched', () {
      final spec = picture(0);
      final before = File(spec.path).readAsBytesSync();
      final modified = File(spec.path).lastModifiedSync();
      build([spec],
          settings: const ImagePdfSettings(compression: CompressionLevel.none));
      build([spec]);
      expect(File(spec.path).readAsBytesSync(), before);
      expect(File(spec.path).lastModifiedSync(), modified);
    });
  });

  group('page sizes', () {
    final sizes = <PdfPageSize, (double, double)>{
      PdfPageSize.a3: (297, 420),
      PdfPageSize.a4: (210, 297),
      PdfPageSize.a5: (148, 210),
      PdfPageSize.letter: (215.9, 279.4),
      PdfPageSize.legal: (215.9, 355.6),
    };
    sizes.forEach((size, mmSize) {
      for (final landscape in [false, true]) {
        test('${size.name} ${landscape ? 'landscape' : 'portrait'}', () {
          final made = build([picture(0)],
              settings: ImagePdfSettings(
                  pageSize: size,
                  orientation: landscape
                      ? PdfOrientation.landscape
                      : PdfOrientation.portrait));
          final page = made.inspect.pages.single;
          final w = landscape ? mmSize.$2 : mmSize.$1;
          final h = landscape ? mmSize.$1 : mmSize.$2;
          expect(page.width, closeTo(w * mm, 0.05));
          expect(page.height, closeTo(h * mm, 0.05));
        });
      }
    });

    test('a custom size is read in points converted from millimetres', () {
      final made = build([picture(0)],
          settings: const ImagePdfSettings(
              pageSize: PdfPageSize.custom,
              customWidthMm: 120,
              customHeightMm: 180,
              orientation: PdfOrientation.portrait));
      final page = made.inspect.pages.single;
      expect(page.width, closeTo(120 * mm, 0.05));
      expect(page.height, closeTo(180 * mm, 0.05));
      final wide = build([picture(0)],
          settings: const ImagePdfSettings(
              pageSize: PdfPageSize.custom,
              customWidthMm: 180,
              customHeightMm: 120,
              orientation: PdfOrientation.landscape));
      expect(wide.inspect.pages.single.width, closeTo(180 * mm, 0.05));
    });

    test('Auto turns each page to its picture', () {
      final made = build([
        picture(0, w: 400, h: 300),
        picture(1, w: 300, h: 400),
        picture(2, w: 500, h: 500),
      ]);
      final pages = made.inspect.pages;
      expect(pages[0].width, greaterThan(pages[0].height));
      expect(pages[1].width, lessThan(pages[1].height));
      expect(pages[2].width, lessThan(pages[2].height));
    });
  });

  group('layouts', () {
    for (final layout in [
      PdfLayout.fitToPage,
      PdfLayout.centerFit,
      PdfLayout.originalSize,
    ]) {
      test('${layout.name}: drawn where planned, aspect kept, inside margins',
          () {
        final specs = [
          picture(0, w: 640, h: 480),
          picture(1, w: 300, h: 600),
        ];
        final settings = ImagePdfSettings(layout: layout, marginMm: 12);
        final made = build(specs, settings: settings);
        final plan = ImagePdfLayout.plan(settings, [
          for (final s in specs) ImageDimensions(s.width, s.height),
        ]);
        final pages = made.inspect.pages;
        for (var i = 0; i < 2; i++) {
          final drawn = pages[i].images.single;
          final rect = plan.pages[i].images.single.rect;
          expect(drawn.x, closeTo(rect.x, 0.03));
          expect(drawn.top, closeTo(rect.y, 0.03));
          expect(drawn.width, closeTo(rect.width, 0.03));
          expect(drawn.height, closeTo(rect.height, 0.03));
          expect(drawn.width / drawn.height,
              closeTo(specs[i].width / specs[i].height, 0.005));
          expect(drawn.x, greaterThanOrEqualTo(12 * mm - 0.05));
          expect(drawn.top, greaterThanOrEqualTo(12 * mm - 0.05));
          expect(
              drawn.right, lessThanOrEqualTo(pages[i].width - 12 * mm + 0.05));
          expect(drawn.bottom,
              lessThanOrEqualTo(pages[i].height - 12 * mm + 0.05));
        }
      });
    }

    test('Center Fit draws a frame, Fit to Page does not', () {
      final framed = build([picture(0)],
          settings: const ImagePdfSettings(layout: PdfLayout.centerFit));
      final plain = build([picture(0)]);
      bool hasStroke(PdfInspector i) =>
          RegExp(r'\bre\b[\s\S]*?\bS\b').hasMatch(i.pages.single.content);
      expect(hasStroke(framed.inspect), isTrue);
      expect(hasStroke(plain.inspect), isFalse);
    });

    test(
        'Original Size keeps a small picture small instead of filling the page',
        () {
      final spec = picture(0, w: 288, h: 192); // 3 x 2 in at 96 dpi
      final made = build([spec],
          settings: const ImagePdfSettings(layout: PdfLayout.originalSize));
      final drawn = made.inspect.pages.single.images.single;
      expect(drawn.width, closeTo(288 * 72 / 96, 0.05));
      expect(drawn.height, closeTo(192 * 72 / 96, 0.05));
    });

    test('Tile Multiple places several pictures per page, in reading order',
        () {
      final specs = [for (var i = 0; i < 7; i++) picture(i)];
      const settings = ImagePdfSettings(
          layout: PdfLayout.tileMultiple,
          tilesPerPage: 4,
          orientation: PdfOrientation.portrait,
          pageNumbers: true);
      final made = build(specs, settings: settings);
      expect(made.result.pageCount, 2);
      expect(made.result.imageCount, 7);
      final pages = made.inspect.pages;
      expect(pages[0].images, hasLength(4));
      expect(pages[1].images, hasLength(3));
      final plan = ImagePdfLayout.plan(settings, [
        for (final s in specs) ImageDimensions(s.width, s.height),
      ]);
      var index = 0;
      for (var p = 0; p < 2; p++) {
        for (var t = 0; t < pages[p].images.length; t++, index++) {
          final drawn = pages[p].images[t];
          final rect = plan.pages[p].images[t].rect;
          expect(drawn.x, closeTo(rect.x, 0.03), reason: 'tile $index');
          expect(drawn.top, closeTo(rect.y, 0.03));
          expect(drawn.width, closeTo(rect.width, 0.03));
          expect(
              sameColour(centre(made.inspect, drawn), palette[index]), isTrue,
              reason: 'tile $index shows picture $index');
        }
      }
      // Numbering counts pages, not pictures.
      expect(pageText(made.bytes, 0), contains('1 / 2'));
      expect(pageText(made.bytes, 1), contains('2 / 2'));
    });

    test('Tile Multiple with 2 and 6 per sheet', () {
      final specs = [for (var i = 0; i < 6; i++) picture(i)];
      final two = build(specs,
          settings: const ImagePdfSettings(
              layout: PdfLayout.tileMultiple, tilesPerPage: 2));
      expect(two.result.pageCount, 3);
      final six = build(specs,
          settings: const ImagePdfSettings(
              layout: PdfLayout.tileMultiple, tilesPerPage: 6));
      expect(six.result.pageCount, 1);
      expect(six.inspect.pages.single.images, hasLength(6));
    });
  });

  group('page numbers, date, watermark and cover page', () {
    test('page numbers read "n / total" on every picture page', () {
      final made = build([for (var i = 0; i < 3; i++) picture(i)],
          settings: const ImagePdfSettings(pageNumbers: true));
      expect(made.result.pageCount, 3);
      for (var i = 0; i < 3; i++) {
        expect(pageText(made.bytes, i), contains('${i + 1} / 3'));
      }
      final off = build([picture(0), picture(1)]);
      expect(pageText(off.bytes, 0).contains('/'), isFalse);
    });

    test('the date is one real moment on every page, never a size or a count',
        () {
      final made = build([for (var i = 0; i < 3; i++) picture(i)],
          settings: const ImagePdfSettings(timestamp: true));
      for (var i = 0; i < 3; i++) {
        final text = pageText(made.bytes, i);
        expect(text, contains('2026-10-18 14:32'));
        expect(text.contains('KB'), isFalse);
        expect(text.contains('×'), isFalse);
        expect(text.contains('Size'), isFalse);
      }
      final later = build([picture(0)],
          settings: const ImagePdfSettings(timestamp: true),
          when: DateTime(2027, 1, 2, 3, 4));
      expect(pageText(later.bytes, 0), contains('2027-01-02 03:04'));
      // Page numbers and the date sit together without hiding one another.
      final both = build([picture(0)],
          settings: const ImagePdfSettings(timestamp: true, pageNumbers: true));
      final text = pageText(both.bytes, 0);
      expect(text, contains('2026-10-18 14:32'));
      expect(text, contains('1 / 1'));
    });

    test('footer text never overlaps a picture', () {
      final made = build([picture(0, w: 100, h: 400)],
          settings: const ImagePdfSettings(
              pageNumbers: true,
              timestamp: true,
              orientation: PdfOrientation.portrait));
      final page = made.inspect.pages.single;
      final footerTop =
          page.height - 7 * mm - ImagePdfLayout.footerBandHeightPt;
      expect(page.images.single.bottom, lessThanOrEqualTo(footerTop + 0.05));
    });

    test('the watermark is drawn faintly on every picture page, and only then',
        () {
      final on = build([picture(0), picture(1)],
          settings: const ImagePdfSettings(watermark: true));
      for (final page in on.inspect.pages) {
        expect(page.content, contains('(Broker Wallet)'));
        expect(page.content, contains(' gs'));
      }
      expect(on.inspect.containsRaw('/CA 0.14'), isTrue);
      final off = build([picture(0)]);
      expect(
          off.inspect.pages.single.content.contains('Broker Wallet'), isFalse);
      expect(off.inspect.containsRaw('/CA 0.14'), isFalse);
    });

    test('a typed watermark replaces the default and keeps the page count', () {
      final made = build([picture(0), picture(1)],
          settings: const ImagePdfSettings(
              watermark: true, watermarkText: 'CONFIDENTIAL'));
      expect(made.result.pageCount, 2);
      for (final page in made.inspect.pages) {
        expect(page.content, contains('(CONFIDENTIAL)'));
        expect(page.content.contains('Broker Wallet'), isFalse);
      }
    });

    test(
        'an Arabic watermark embeds the bundled font; without it the build fails',
        () {
      const settings =
          ImagePdfSettings(watermark: true, watermarkText: 'سري للغاية');
      final made =
          build([picture(0)], settings: settings, font: arabicFontBytes());
      expect(made.result.pageCount, 1);
      expect(made.inspect.containsRaw('FontFile2'), isTrue);
      // The text is really on the page (the library draws nothing at all when
      // its bounds are too short for the font).
      expect(made.inspect.pages.single.content, contains('BT'));
      final error = failureOf(() => build([picture(0)], settings: settings));
      expect(error?.kind, ImagePdfFailure.buildFailed);
      expect(
          File('${folder.directory.path}/out${outputCounter - 1}.pdf')
              .existsSync(),
          isFalse);
    });

    test('no cover page appears just because a date or watermark is on', () {
      final made = build([picture(0), picture(1)],
          settings: const ImagePdfSettings(
              timestamp: true, watermark: true, pageNumbers: true));
      expect(made.result.pageCount, 2);
      expect(made.inspect.pages, hasLength(2));
      expect(made.inspect.pages.every((p) => p.images.length == 1), isTrue);
    });

    test('an explicit cover page is one extra first page with no picture', () {
      final made = build([picture(0), picture(1)],
          settings: const ImagePdfSettings(
              coverPage: true, pageNumbers: true, timestamp: true),
          texts: const ImagePdfTexts(
              coverTitle: 'Villa 12 documents', coverLines: ['2 images']));
      expect(made.result.pageCount, 3);
      expect(made.result.imageCount, 2);
      final pages = made.inspect.pages;
      expect(pages.first.images, isEmpty);
      expect(pages.skip(1).every((p) => p.images.length == 1), isTrue);
      final cover = pageText(made.bytes, 0);
      expect(cover, contains('Villa 12 documents'));
      expect(cover, contains('2 images'));
      expect(cover, contains('2026-10-18 14:32'));
      // The cover carries no page number; picture pages match the viewer.
      expect(cover.contains('/'), isFalse);
      expect(pageText(made.bytes, 1), contains('2 / 3'));
      expect(pageText(made.bytes, 2), contains('3 / 3'));
    });

    test('a cover page with an Arabic title uses the bundled font', () {
      final made = build([picture(0)],
          settings: const ImagePdfSettings(coverPage: true),
          texts: const ImagePdfTexts(coverTitle: 'عقد إيجار فيلا'),
          font: arabicFontBytes());
      expect(made.result.pageCount, 2);
      expect(made.inspect.containsRaw('FontFile2'), isTrue);
    });
  });

  group('password protection is real or absent', () {
    const settings = ImagePdfSettings(passwordProtect: true, pageNumbers: true);

    test('the file needs the password: right opens, wrong and none refuse', () {
      final made = build([picture(0), picture(1)],
          settings: settings, password: 'Secret-123');
      expect(made.result.encrypted, isTrue);
      expect(made.inspect.hasEncryptEntry, isTrue);
      // None.
      expect(
          () => PdfDocument(inputBytes: made.bytes),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'password')));
      // Wrong.
      expect(() => PdfDocument(inputBytes: made.bytes, password: 'Secret-124'),
          throwsA(isA<ArgumentError>()));
      // Right: both pages, with their numbers.
      final doc = PdfDocument(inputBytes: made.bytes, password: 'Secret-123');
      expect(doc.pages.count, 2);
      doc.dispose();
      expect(
          pageText(made.bytes, 1, password: 'Secret-123'), contains('2 / 2'));
    });

    test('the picture data is encrypted, not just flagged', () {
      final plain = build([picture(0)]);
      final secret =
          build([picture(0)], settings: settings, password: 'abcdef');
      // JPEG data of the unprotected file is plainly present; in the protected
      // file the same bytes do not appear.
      final jfif = plain.inspect.allImages.single.data.sublist(0, 24);
      bool contains(Uint8List haystack, Uint8List needle) {
        outer:
        for (var i = 0; i <= haystack.length - needle.length; i++) {
          for (var j = 0; j < needle.length; j++) {
            if (haystack[i + j] != needle[j]) continue outer;
          }
          return true;
        }
        return false;
      }

      expect(contains(plain.bytes, Uint8List.fromList(jfif)), isTrue);
      expect(contains(secret.bytes, Uint8List.fromList(jfif)), isFalse);
    });

    test('a file read back says whether it is protected', () {
      final made = build([picture(0)], settings: settings, password: 'abcdef');
      final path = '${folder.directory.path}/protected.pdf';
      File(path).writeAsBytesSync(made.bytes);
      final blind = analyzeImagePdf(path);
      expect(blind.encrypted, isTrue);
      expect(blind.pageCount, 0);
      final known = analyzeImagePdf(path, password: 'abcdef');
      expect(known.encrypted, isTrue);
      expect(known.pageCount, 1);
      final plain = build([picture(0)]);
      final plainPath = '${folder.directory.path}/plain.pdf';
      File(plainPath).writeAsBytesSync(plain.bytes);
      expect(analyzeImagePdf(plainPath).encrypted, isFalse);
      expect(analyzeImagePdf(plainPath).pageCount, 1);
      expect(plain.inspect.hasEncryptEntry, isFalse);
    });

    test('a missing, short or unusual password is refused before any work', () {
      final spec = picture(0);
      for (final bad in [null, '', 'abc', 'كلمة سر طويلة']) {
        final error =
            failureOf(() => build([spec], settings: settings, password: bad));
        expect(error?.kind, ImagePdfFailure.invalidPassword, reason: '$bad');
      }
    });

    test('a truncated protected file is not mistaken for a good one', () {
      final made = build([picture(0)], settings: settings, password: 'abcdef');
      final path = '${folder.directory.path}/cut.pdf';
      File(path)
          .writeAsBytesSync(made.bytes.sublist(0, made.bytes.length ~/ 2));
      expect(failureOf(() => analyzeImagePdf(path))?.kind,
          ImagePdfFailure.corruptSource);
    });

    test('Combine PDFs refuses a protected result and accepts an open one', () {
      final protectedPdf =
          build([picture(0)], settings: settings, password: 'abcdef');
      final protectedPath = '${folder.directory.path}/c1.pdf';
      File(protectedPath).writeAsBytesSync(protectedPdf.bytes);
      expect(
          () => analyzeCombinePdf(protectedPath, maxBytes: 1 << 28),
          throwsA(isA<CombinePdfException>().having(
              (e) => e.kind, 'kind', CombinePdfFailure.encryptedSource)));
      final openPdf = build([picture(0), picture(1)]);
      final openPath = '${folder.directory.path}/c2.pdf';
      File(openPath).writeAsBytesSync(openPdf.bytes);
      expect(analyzeCombinePdf(openPath, maxBytes: 1 << 28).pageCount, 2);
    });
  });

  group('privacy', () {
    final secrets = ['GPS', 'Exif', 'PrivateCameraMaker', 'PrivateCameraModel'];

    for (final level in CompressionLevel.values) {
      test('${level.name}: a geotagged photo leaves no location or camera data',
          () {
        final photos = <ImageSpec>[];
        for (final orientation in [null, 6, 3]) {
          final file = folder.write(
              'geo${orientation ?? 0}.jpg',
              jpeg(marked(200, 140),
                  orientation: orientation, privateMetadata: true));
          photos.add(folder.spec(file, analyzeImageFile(file.path)));
        }
        final made = build(photos,
            settings: ImagePdfSettings(compression: level, timestamp: true));
        for (final s in secrets) {
          expect(containsAscii(made.bytes, s), isFalse, reason: 'found $s');
        }
        // The creation date is the document's own, not the photo's.
        expect(made.inspect.containsRaw('/Creator (Broker Wallet)'), isTrue);
      });
    }

    test(
        'the source photos still carry the metadata (nothing was stripped in place)',
        () {
      final bytes = jpeg(marked(200, 140), privateMetadata: true);
      final file = folder.write('keep.jpg', bytes);
      build([folder.spec(file, analyzeImageFile(file.path))]);
      expect(
          containsAscii(
              File(file.path).readAsBytesSync(), 'PrivateCameraMaker'),
          isTrue);
    });
  });

  group('quality and compression in the PDF', () {
    test('None keeps an upright JPEG\'s own data; PNG stays lossless', () {
      final jpegBytes =
          jpeg(marked(300, 200), quality: 90, privateMetadata: true);
      final file = folder.write('k.jpg', jpegBytes);
      final spec = folder.spec(file, analyzeImageFile(file.path));
      final made = build([spec],
          settings: const ImagePdfSettings(compression: CompressionLevel.none));
      final embedded = made.inspect.allImages.single;
      expect(embedded.filter, 'DCTDecode');
      expect(embedded.data, ImagePdfFormats.stripJpegMetadata(jpegBytes));
      final pngSpec = picture(2, w: 120, h: 90, asPng: true);
      final lossless = build([pngSpec],
          settings: const ImagePdfSettings(compression: CompressionLevel.none));
      expect(lossless.inspect.allImages.single.filter, 'FlateDecode');
    });

    test(
        'quality sets the pixel width at the placed size, never above the original',
        () {
      final file = folder.write('big.png', png(solid(3000, 2000, palette[0])));
      final spec = folder.spec(file, analyzeImageFile(file.path));
      final widths = <ImageQuality, int>{};
      for (final q in ImageQuality.values) {
        final made = build([spec], settings: ImagePdfSettings(quality: q));
        widths[q] = made.inspect.allImages.single.width;
      }
      final low = widths[ImageQuality.low]!;
      final medium = widths[ImageQuality.medium]!;
      final high = widths[ImageQuality.high]!;
      final ultra = widths[ImageQuality.ultra]!;
      expect(low, lessThan(medium));
      expect(medium, lessThan(high));
      expect(high, lessThan(ultra));
      // Matches the plan: width in inches times dpi, capped at the original.
      final plan = ImagePdfLayout.plan(
          const ImagePdfSettings(), [ImageDimensions(3000, 2000)]);
      final inches = plan.pages.single.images.single.rect.width / 72;
      expect(low, closeTo(inches * 96, 1));
      expect(medium, closeTo(inches * 150, 1));
      expect(high, closeTo(inches * 200, 1));
      expect(ultra, 3000, reason: 'the original has fewer pixels than 300 dpi');
      // A small picture is never enlarged by a high quality setting.
      final small = picture(1, w: 400, h: 300);
      final kept = build([small],
          settings: const ImagePdfSettings(quality: ImageQuality.ultra));
      expect(kept.inspect.allImages.single.width, 400);
    });

    test('higher compression gives a smaller file for the same pictures', () {
      final random = math.Random(3);
      final noisy = img.Image(width: 900, height: 600);
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 900; x++) {
          noisy.setPixelRgb(
              x,
              y,
              (x * 255 ~/ 900 + random.nextInt(60)).clamp(0, 255),
              (y * 255 ~/ 600 + random.nextInt(60)).clamp(0, 255),
              random.nextInt(256));
        }
      }
      final file = folder.write('n.jpg', jpeg(noisy, quality: 99));
      final spec = folder.spec(file, analyzeImageFile(file.path));
      int sizeAt(CompressionLevel l) => build([spec],
              settings:
                  ImagePdfSettings(compression: l, quality: ImageQuality.ultra))
          .result
          .size;
      final sizes = [for (final l in CompressionLevel.values) sizeAt(l)];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason:
                '${CompressionLevel.values[i].name} < ${CompressionLevel.values[i - 1].name}');
      }
    });

    test('pictures printing below 100 dpi are counted', () {
      final tiny = picture(0, w: 120, h: 90);
      final fine = picture(1, w: 2400, h: 1800);
      final made = build([tiny, fine]);
      expect(made.result.lowResolutionImages, 1);
    });
  });

  group('all or nothing', () {
    test('a picture that vanished stops the whole PDF and leaves no file', () {
      final specs = [for (var i = 0; i < 3; i++) picture(i)];
      File(specs[1].path).deleteSync();
      final path = outPath();
      final error = failureOf(() => buildImagePdf(ImagePdfBuildJob(
          images: specs,
          settings: const ImagePdfSettings(),
          outputPath: path,
          timestamp: stamp)));
      expect(error?.kind, ImagePdfFailure.missingSource);
      expect(File(path).existsSync(), isFalse);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('a picture that changed after it was checked is refused by name', () {
      final specs = [picture(0), picture(1)];
      File(specs[1].path).writeAsBytesSync(jpeg(solid(10, 10, palette[3])));
      final error = failureOf(() => build(specs));
      expect(error?.kind, ImagePdfFailure.sourceChanged);
    });

    test('cancelling mid-way stores nothing', () {
      final specs = [for (var i = 0; i < 4; i++) picture(i)];
      var calls = 0;
      final path = outPath();
      final error = failureOf(() => buildImagePdf(
            ImagePdfBuildJob(
                images: specs,
                settings: const ImagePdfSettings(),
                outputPath: path,
                timestamp: stamp),
            isCancelled: () => ++calls > 3,
          ));
      expect(error?.kind, ImagePdfFailure.cancelled);
      expect(File(path).existsSync(), isFalse);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('an unwritable destination is a write failure, not a success', () {
      final error = failureOf(() => buildImagePdf(ImagePdfBuildJob(
          images: [picture(0)],
          settings: const ImagePdfSettings(),
          outputPath: '${folder.directory.path}/missing-dir/out.pdf',
          timestamp: stamp)));
      expect(error?.kind, ImagePdfFailure.writeFailed);
    });

    test('an existing file at the destination is not deleted by a failed build',
        () {
      final path = outPath();
      File(path).writeAsBytesSync([1, 2, 3]);
      final specs = [picture(0), picture(1)];
      File(specs[1].path).deleteSync();
      failureOf(() => buildImagePdf(ImagePdfBuildJob(
          images: specs,
          settings: const ImagePdfSettings(),
          outputPath: path,
          timestamp: stamp)));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('empty, oversized and out-of-range jobs are refused', () {
      expect(failureOf(() => build(const []))?.kind, ImagePdfFailure.noImages);
      final spec = picture(0);
      expect(failureOf(() => build([for (var i = 0; i < 101; i++) spec]))?.kind,
          ImagePdfFailure.tooManyImages);
      expect(
          failureOf(() =>
                  build([spec], settings: const ImagePdfSettings(marginMm: 99)))
              ?.kind,
          ImagePdfFailure.invalidSettings);
    });

    test('a finished PDF is read back and counted from the file itself', () {
      final made = build([for (var i = 0; i < 3; i++) picture(i)]);
      final path = '${folder.directory.path}/read.pdf';
      File(path).writeAsBytesSync(made.bytes);
      final info = analyzeImagePdf(path);
      expect(info.pageCount, 3);
      expect(info.size, made.bytes.length);
      expect(info.encrypted, isFalse);
      File(path).writeAsBytesSync(made.bytes.sublist(0, 200));
      expect(failureOf(() => analyzeImagePdf(path))?.kind,
          ImagePdfFailure.corruptSource);
      File(path).writeAsBytesSync(Uint8List.fromList('not a pdf'.codeUnits));
      expect(failureOf(() => analyzeImagePdf(path))?.kind,
          ImagePdfFailure.corruptSource);
      expect(failureOf(() => analyzeImagePdf('${path}x'))?.kind,
          ImagePdfFailure.missingSource);
    });
  });

  group('large and awkward pictures', () {
    test('a very wide panorama and a very tall strip fit without distortion',
        () {
      final wide = picture(0, w: 3000, h: 150);
      final tall = picture(1, w: 120, h: 2400);
      final made = build([wide, tall]);
      for (final entry in [(0, wide), (1, tall)]) {
        final drawn = made.inspect.pages[entry.$1].images.single;
        expect(drawn.width / drawn.height,
            closeTo(entry.$2.width / entry.$2.height, 0.02));
      }
    });

    test('a 24 megapixel photograph is processed and bounded by quality', () {
      final photo = img.Image(width: 6000, height: 4000)
        ..clear(img.ColorRgb8(90, 140, 200));
      final file =
          folder.write('huge.jpg', jpeg(photo, quality: 85, orientation: 6));
      final spec = folder.spec(file, analyzeImageFile(file.path));
      expect((spec.width, spec.height), (4000, 6000));
      final made = build([spec],
          settings: const ImagePdfSettings(quality: ImageQuality.medium));
      final embedded = made.inspect.allImages.single;
      expect(embedded.width, lessThan(1400));
      expect(embedded.height / embedded.width, closeTo(1.5, 0.01));
      expect(made.result.size, lessThan(400 * 1024));
    });
  });
}
