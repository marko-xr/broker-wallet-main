import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_layout.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

const double mm = ImagePdfLayout.pointsPerMm;

ImageDimensions landscape([double? dpi]) =>
    ImageDimensions(4000, 3000, dpi: dpi);
ImageDimensions portrait([double? dpi]) =>
    ImageDimensions(3000, 4000, dpi: dpi);

void main() {
  group('page sizes are exact points', () {
    test('A3, A4, A5, Letter and Legal in portrait and landscape', () {
      final expected = <PdfPageSize, (double, double)>{
        PdfPageSize.a3: (297 * mm, 420 * mm),
        PdfPageSize.a4: (210 * mm, 297 * mm),
        PdfPageSize.a5: (148 * mm, 210 * mm),
        PdfPageSize.letter: (612, 792),
        PdfPageSize.legal: (612, 1008),
      };
      expected.forEach((size, dims) {
        final s = ImagePdfSettings(pageSize: size);
        final p = ImagePdfLayout.pageSize(s, false);
        expect(p.width, closeTo(dims.$1, 0.01), reason: '$size');
        expect(p.height, closeTo(dims.$2, 0.01), reason: '$size');
        final l = ImagePdfLayout.pageSize(s, true);
        expect(l.width, closeTo(dims.$2, 0.01));
        expect(l.height, closeTo(dims.$1, 0.01));
      });
      expect(595.28, closeTo(210 * mm, 0.01));
      expect(841.89, closeTo(297 * mm, 0.01));
    });

    test('a custom size is converted from millimetres and shorter side first',
        () {
      const s = ImagePdfSettings(
          pageSize: PdfPageSize.custom,
          customWidthMm: 300,
          customHeightMm: 200);
      final p = ImagePdfLayout.pageSize(s, false);
      expect(p.width, closeTo(200 * mm, 0.01));
      expect(p.height, closeTo(300 * mm, 0.01));
      final l = ImagePdfLayout.pageSize(s, true);
      expect(l.width, closeTo(300 * mm, 0.01));
    });

    test('unit conversion round-trips', () {
      expect(ImagePdfLayout.inchToMm(1), 25.4);
      expect(ImagePdfLayout.mmToInch(25.4), closeTo(1, 1e-12));
      expect(ImagePdfLayout.mmToPt(25.4), closeTo(72, 1e-9));
      expect(ImagePdfLayout.ptToMm(72), closeTo(25.4, 1e-9));
      expect(ImagePdfLayout.mmToPt(10), closeTo(28.3465, 1e-3));
    });
  });

  group('settings validation', () {
    test('custom sides, margin, tile count and watermark text are bounded', () {
      expect(const ImagePdfSettings().validate(), isNull);
      expect(
          const ImagePdfSettings(
                  pageSize: PdfPageSize.custom,
                  customWidthMm: 49,
                  customHeightMm: 300)
              .validate(),
          ImagePdfFailure.invalidSettings);
      expect(
          const ImagePdfSettings(
                  pageSize: PdfPageSize.custom,
                  customWidthMm: 100,
                  customHeightMm: 1001)
              .validate(),
          ImagePdfFailure.invalidSettings);
      expect(
          const ImagePdfSettings(
                  pageSize: PdfPageSize.custom,
                  customWidthMm: double.nan,
                  customHeightMm: 100)
              .validate(),
          ImagePdfFailure.invalidSettings);
      // A bad custom size does not matter while a preset is chosen.
      expect(
          const ImagePdfSettings(customWidthMm: 1, customHeightMm: 1)
              .validate(),
          isNull);
      expect(const ImagePdfSettings(marginMm: -1).validate(),
          ImagePdfFailure.invalidSettings);
      expect(const ImagePdfSettings(marginMm: 31).validate(),
          ImagePdfFailure.invalidSettings);
      expect(const ImagePdfSettings(tilesPerPage: 3).validate(),
          ImagePdfFailure.invalidSettings);
      expect(
          ImagePdfSettings(watermark: true, watermarkText: 'x' * 41).validate(),
          ImagePdfFailure.invalidSettings);
      expect(
          const ImagePdfSettings(watermark: true, watermarkText: '漢字')
              .validate(),
          ImagePdfFailure.invalidSettings);
      expect(
          const ImagePdfSettings(watermark: true, watermarkText: 'سري')
              .validate(),
          isNull);
    });

    test('text rules: renderable text, passwords, the timestamp and numbers',
        () {
      expect(ImagePdfText.isRenderable('Broker Wallet 2026'), isTrue);
      expect(ImagePdfText.isRenderable('عقد إيجار'), isTrue);
      expect(ImagePdfText.isRenderable('emoji 😀'), isFalse);
      expect(ImagePdfText.needsUnicodeFont('Plain'), isFalse);
      expect(ImagePdfText.needsUnicodeFont('عقد'), isTrue);
      expect(ImagePdfText.isValidPassword('abc123'), isTrue);
      expect(ImagePdfText.isValidPassword('abc12'), isFalse);
      expect(ImagePdfText.isValidPassword('كلمة سر طويلة'), isFalse);
      expect(ImagePdfText.isValidPassword('a' * 65), isFalse);
      expect(ImagePdfText.formatTimestamp(DateTime(2026, 3, 4, 5, 6)),
          '2026-03-04 05:06');
      expect(ImagePdfText.pageNumber(0, 5), '1 / 5');
      expect(const ImagePdfSettings().effectiveWatermark, 'Broker Wallet');
      expect(
          const ImagePdfSettings(watermarkText: '  Draft ').effectiveWatermark,
          'Draft');
    });
  });

  group('one picture per page', () {
    test('Fit to Page: contained, centred, aspect kept, inside the margins',
        () {
      const s =
          ImagePdfSettings(orientation: PdfOrientation.portrait, marginMm: 10);
      final plan = ImagePdfLayout.plan(s, [portrait()]);
      expect(plan.pageCount, 1);
      final page = plan.pages.single;
      final rect = page.images.single.rect;
      final margin = 10 * mm;
      expect(plan.marginPt, closeTo(margin, 1e-9));
      expect(rect.x, greaterThanOrEqualTo(margin - 1e-6));
      expect(rect.y, greaterThanOrEqualTo(margin - 1e-6));
      expect(rect.right, lessThanOrEqualTo(page.width - margin + 1e-6));
      expect(rect.bottom, lessThanOrEqualTo(page.height - margin + 1e-6));
      expect(rect.width / rect.height, closeTo(3000 / 4000, 1e-9));
      // Centred on the page.
      expect(rect.x + rect.width / 2, closeTo(page.width / 2, 1e-6));
      expect(rect.y + rect.height / 2, closeTo(page.height / 2, 1e-6));
    });

    test('a tall picture on a portrait page uses the full width or height', () {
      const s = ImagePdfSettings(orientation: PdfOrientation.portrait);
      final rect =
          ImagePdfLayout.plan(s, [portrait()]).pages.single.images.single.rect;
      final page = ImagePdfLayout.pageSize(s, false);
      final content = (
        page.width - 2 * ImagePdfLayout.mmToPt(7),
        page.height - 2 * ImagePdfLayout.mmToPt(7)
      );
      final fillsWidth = (rect.width - content.$1).abs() < 0.01;
      final fillsHeight = (rect.height - content.$2).abs() < 0.01;
      expect(fillsWidth || fillsHeight, isTrue);
    });

    test('Auto orientation follows each picture; fixed orientations do not',
        () {
      const auto = ImagePdfSettings();
      final plan = ImagePdfLayout.plan(auto, [landscape(), portrait()]);
      expect(plan.pages[0].width, greaterThan(plan.pages[0].height));
      expect(plan.pages[1].width, lessThan(plan.pages[1].height));
      final fixedP = ImagePdfLayout.plan(
          const ImagePdfSettings(orientation: PdfOrientation.portrait),
          [landscape(), portrait()]);
      expect(fixedP.pages.every((p) => p.width < p.height), isTrue);
      final fixedL = ImagePdfLayout.plan(
          const ImagePdfSettings(orientation: PdfOrientation.landscape),
          [landscape(), portrait()]);
      expect(fixedL.pages.every((p) => p.width > p.height), isTrue);
      // A square picture is portrait under Auto.
      final square =
          ImagePdfLayout.plan(auto, [const ImageDimensions(500, 500)]);
      expect(square.pages.single.width, lessThan(square.pages.single.height));
    });

    test('Center Fit never crops: it is the contained rectangle too', () {
      const fit = ImagePdfSettings(layout: PdfLayout.fitToPage);
      const center = ImagePdfSettings(layout: PdfLayout.centerFit);
      final a = ImagePdfLayout.plan(fit, [landscape()])
          .pages
          .single
          .images
          .single
          .rect;
      final b = ImagePdfLayout.plan(center, [landscape()])
          .pages
          .single
          .images
          .single
          .rect;
      expect(b.width, closeTo(a.width, 1e-9));
      expect(b.height, closeTo(a.height, 1e-9));
    });

    test('Original Size uses the picture\'s resolution and only shrinks', () {
      const s = ImagePdfSettings(
          layout: PdfLayout.originalSize, orientation: PdfOrientation.portrait);
      // 600 x 400 px at 300 dpi = 2 x 1.333 in: stays that size, centred.
      final small =
          ImagePdfLayout.plan(s, [const ImageDimensions(600, 400, dpi: 300)]);
      final r = small.pages.single.images.single.rect;
      expect(r.width, closeTo(2 * 72, 1e-6));
      expect(r.height, closeTo(400 * 72 / 300, 1e-6));
      final page = small.pages.single;
      expect(r.x + r.width / 2, closeTo(page.width / 2, 1e-6));
      // No resolution stated: 96 dpi.
      final plain = ImagePdfLayout.plan(s, [const ImageDimensions(480, 240)]);
      expect(plain.pages.single.images.single.rect.width,
          closeTo(480 * 72 / 96, 1e-6));
      // A photograph far larger than the page is shrunk to fit, never clipped.
      final big = ImagePdfLayout.plan(s, [portrait(72)]);
      final br = big.pages.single.images.single.rect;
      final bp = big.pages.single;
      expect(br.x, greaterThanOrEqualTo(big.marginPt - 1e-6));
      expect(br.right, lessThanOrEqualTo(bp.width - big.marginPt + 1e-6));
      expect(br.bottom, lessThanOrEqualTo(bp.height - big.marginPt + 1e-6));
      expect(br.width / br.height, closeTo(0.75, 1e-9));
    });

    test('Fit to Page may enlarge a small picture to the page', () {
      const s = ImagePdfSettings(orientation: PdfOrientation.portrait);
      final r = ImagePdfLayout.plan(s, [const ImageDimensions(100, 150)])
          .pages
          .single
          .images
          .single
          .rect;
      expect(r.width, greaterThan(400));
    });

    test('the margin is in millimetres converted to points and is capped', () {
      for (final margin in [0.0, 5.0, 10.0, 25.0]) {
        final plan = ImagePdfLayout.plan(
            ImagePdfSettings(
                marginMm: margin, orientation: PdfOrientation.portrait),
            [portrait()]);
        expect(plan.marginPt, closeTo(margin * mm, 1e-9));
      }
      // A small custom page keeps at least 40 % of its short side as content.
      const tiny = ImagePdfSettings(
          pageSize: PdfPageSize.custom,
          customWidthMm: 50,
          customHeightMm: 80,
          marginMm: 30);
      final plan = ImagePdfLayout.plan(tiny, [portrait()]);
      expect(plan.pages.single.width - 2 * plan.marginPt,
          greaterThanOrEqualTo(0.4 * 50 * mm - 1e-6));
    });
  });

  group('footer band', () {
    test('page numbers or a date reserve a strip no picture enters', () {
      const off = ImagePdfSettings(orientation: PdfOrientation.portrait);
      const on = ImagePdfSettings(
          orientation: PdfOrientation.portrait, pageNumbers: true);
      final a = ImagePdfLayout.plan(off, [const ImageDimensions(100, 400)]);
      final b = ImagePdfLayout.plan(on, [const ImageDimensions(100, 400)]);
      expect(a.footerBandPt, 0);
      expect(b.footerBandPt, ImagePdfLayout.footerBandHeightPt);
      final page = b.pages.single;
      final rect = page.images.single.rect;
      expect(rect.bottom,
          lessThanOrEqualTo(page.height - b.marginPt - b.footerBandPt + 1e-6));
      expect(const ImagePdfSettings(timestamp: true).validate(), isNull);
      expect(
          ImagePdfLayout.plan(
                  const ImagePdfSettings(timestamp: true), [portrait()])
              .footerBandPt,
          ImagePdfLayout.footerBandHeightPt);
    });
  });

  group('Tile Multiple', () {
    List<ImageDimensions> pics(int n) =>
        [for (var i = 0; i < n; i++) ImageDimensions(400 + i, 300)];

    test(
        'page count is ceil(pictures / tiles) and every picture is placed once',
        () {
      for (final per in [2, 4, 6]) {
        for (final n in [1, 2, 3, 5, 6, 7, 13]) {
          final plan = ImagePdfLayout.plan(
              ImagePdfSettings(
                  layout: PdfLayout.tileMultiple, tilesPerPage: per),
              pics(n));
          expect(plan.pageCount, (n / per).ceil(), reason: '$per/$n');
          final placed = [
            for (final page in plan.pages)
              for (final image in page.images) image.imageIndex
          ];
          expect(placed, List<int>.generate(n, (i) => i),
              reason: 'reading order $per/$n');
        }
      }
    });

    test('tiles are row by row, left to right, inside the margins and apart',
        () {
      const s = ImagePdfSettings(
          layout: PdfLayout.tileMultiple,
          tilesPerPage: 4,
          orientation: PdfOrientation.portrait);
      final plan = ImagePdfLayout.plan(s, pics(4));
      final page = plan.pages.single;
      final r = page.images.map((i) => i.rect).toList();
      // Rows: 0,1 then 2,3. Within a row the left one is first.
      expect(r[0].x, lessThan(r[1].x));
      expect(r[2].x, lessThan(r[3].x));
      expect(r[0].bottom, lessThanOrEqualTo(r[2].y + 1e-6));
      for (final rect in r) {
        expect(rect.x, greaterThanOrEqualTo(plan.marginPt - 1e-6));
        expect(
            rect.right, lessThanOrEqualTo(page.width - plan.marginPt + 1e-6));
        expect(
            rect.bottom, lessThanOrEqualTo(page.height - plan.marginPt + 1e-6));
      }
      for (var i = 0; i < r.length; i++) {
        for (var j = i + 1; j < r.length; j++) {
          final overlapX = r[i].x < r[j].right && r[j].x < r[i].right;
          final overlapY = r[i].y < r[j].bottom && r[j].y < r[i].bottom;
          expect(overlapX && overlapY, isFalse, reason: 'tiles $i and $j');
        }
      }
    });

    test('no tile is cropped or stretched', () {
      final plan = ImagePdfLayout.plan(
          const ImagePdfSettings(layout: PdfLayout.tileMultiple), [
        const ImageDimensions(1000, 500),
        const ImageDimensions(500, 1000),
        const ImageDimensions(300, 300),
        const ImageDimensions(1600, 900),
      ]);
      final ratios = [2.0, 0.5, 1.0, 1600 / 900];
      for (final page in plan.pages) {
        for (final image in page.images) {
          expect(image.rect.width / image.rect.height,
              closeTo(ratios[image.imageIndex], 1e-9));
        }
      }
    });

    test('grid shapes per orientation', () {
      List<int> columns(int per, PdfOrientation o) {
        final plan = ImagePdfLayout.plan(
            ImagePdfSettings(
                layout: PdfLayout.tileMultiple,
                tilesPerPage: per,
                orientation: o),
            pics(per));
        final xs = <double>{
          for (final i in plan.pages.single.images)
            (i.rect.x / 10).round() * 10.0
        };
        return [xs.length];
      }

      // 2 per sheet: one column stacked on a portrait sheet, two side by side
      // on a landscape one.
      expect(columns(2, PdfOrientation.portrait).single, 1);
      expect(
          columns(2, PdfOrientation.landscape).single, greaterThanOrEqualTo(2));
      expect(
          columns(4, PdfOrientation.portrait).single, greaterThanOrEqualTo(2));
    });

    test('Auto orientation turns the sheet to show its pictures larger', () {
      // Two wide pictures: stacked on a portrait sheet they are small side by
      // side on a landscape sheet they are not; both must be chosen by area.
      final wide = [
        const ImageDimensions(2000, 1000),
        const ImageDimensions(2000, 1000)
      ];
      final tall = [
        const ImageDimensions(1000, 2000),
        const ImageDimensions(1000, 2000)
      ];
      const s =
          ImagePdfSettings(layout: PdfLayout.tileMultiple, tilesPerPage: 2);
      final wideSheet = ImagePdfLayout.plan(s, wide).pages.single;
      final tallSheet = ImagePdfLayout.plan(s, tall).pages.single;
      expect(wideSheet.width, lessThan(wideSheet.height));
      expect(tallSheet.width, greaterThan(tallSheet.height));
    });
  });

  group('cover page', () {
    test('absent unless asked for; present once and first when asked', () {
      final off = ImagePdfLayout.plan(
          const ImagePdfSettings(
              timestamp: true, watermark: true, pageNumbers: true),
          [landscape(), portrait()]);
      expect(off.pageCount, 2);
      expect(off.pages.any((p) => p.isCover), isFalse);
      final on = ImagePdfLayout.plan(
          const ImagePdfSettings(coverPage: true), [landscape(), portrait()]);
      expect(on.pageCount, 3);
      expect(on.pages.first.isCover, isTrue);
      expect(on.pages.where((p) => p.isCover), hasLength(1));
      expect(on.pages.first.images, isEmpty);
      expect(on.imageCount, 2);
      // The cover takes the first picture page's size.
      expect(on.pages.first.width, on.pages[1].width);
      expect(on.pages.first.height, on.pages[1].height);
    });
  });

  group('resolution', () {
    test('print resolution per quality level', () {
      expect(
          ImageQuality.values.map(ImagePdfLayout.dpiFor), [96, 150, 200, 300]);
    });

    test('target pixels follow the placed size and never enlarge', () {
      final plan = ImagePdfLayout.plan(
          const ImagePdfSettings(orientation: PdfOrientation.landscape),
          [landscape()]);
      final rect = plan.pages.single.images.single.rect;
      final inches = rect.width / 72;
      final low = ImagePdfLayout.targetPixels(landscape(), rect, 96)!;
      final ultra = ImagePdfLayout.targetPixels(landscape(), rect, 300)!;
      expect(low.width, (inches * 96).round());
      expect(ultra.width, (inches * 300).round());
      expect(low.width, lessThan(ultra.width));
      expect(low.width / low.height, closeTo(4 / 3, 0.01));
      // Already smaller than the target: left alone.
      const small = ImageDimensions(800, 600);
      expect(ImagePdfLayout.targetPixels(small, rect, 300), isNull);
      // Within 2 % of the target: not resampled for nothing.
      final near = ImageDimensions(
          (inches * 300 * 1.01).round(), (inches * 300 * 0.75 * 1.01).round());
      expect(ImagePdfLayout.targetPixels(near, rect, 300), isNull);
    });

    test('tiles ask for fewer pixels than a full page', () {
      const dims = ImageDimensions(4000, 3000);
      final full = ImagePdfLayout.plan(
          const ImagePdfSettings(orientation: PdfOrientation.portrait), [dims]);
      final tiled = ImagePdfLayout.plan(
          const ImagePdfSettings(
              layout: PdfLayout.tileMultiple,
              tilesPerPage: 6,
              orientation: PdfOrientation.portrait),
          [dims]);
      final a = ImagePdfLayout.targetPixels(
          dims, full.pages.single.images.single.rect, 200)!;
      final b = ImagePdfLayout.targetPixels(
          dims, tiled.pages.single.images.single.rect, 200)!;
      expect(b.width, lessThan(a.width));
    });

    test('effective resolution of a placed picture', () {
      const dims = ImageDimensions(1000, 1000);
      final dpi =
          ImagePdfLayout.effectiveDpi(dims, const PlacedRect(0, 0, 720, 720));
      expect(dpi, closeTo(100, 1e-9));
    });
  });
}
