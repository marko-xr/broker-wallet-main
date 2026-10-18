import 'dart:math' as math;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

/// A rectangle in PDF points, measured from the page's top-left corner.
class PlacedRect {
  const PlacedRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get area => width * height;

  @override
  String toString() => 'PlacedRect($x, $y, $width x $height)';
}

/// One picture on one page.
class PlacedImage {
  const PlacedImage(this.imageIndex, this.rect);

  /// Index into the list of pictures the plan was made for.
  final int imageIndex;
  final PlacedRect rect;
}

/// One page of the PDF, before anything is drawn.
class PlannedPage {
  const PlannedPage({
    required this.width,
    required this.height,
    required this.images,
    this.isCover = false,
  });

  /// Points.
  final double width;
  final double height;
  final List<PlacedImage> images;
  final bool isCover;
}

/// Every page of the PDF and the geometry the footers are drawn with.
class ImagePdfPlan {
  const ImagePdfPlan({
    required this.pages,
    required this.marginPt,
    required this.footerBandPt,
  });

  final List<PlannedPage> pages;
  final double marginPt;

  /// The strip at the bottom of every picture page that holds the page number
  /// and the date; 0 when neither is on. Pictures are placed above it, so a
  /// footer never covers one.
  final double footerBandPt;

  int get pageCount => pages.length;
  int get imageCount =>
      pages.fold<int>(0, (sum, page) => sum + page.images.length);
}

/// What the planner needs to know about a picture: its upright pixel size and
/// its own resolution.
class ImageDimensions {
  const ImageDimensions(this.width, this.height, {this.dpi});

  final int width;
  final int height;
  final double? dpi;

  bool get isLandscape => width > height;
}

/// The pure page geometry: page sizes, orientation, margins and where each
/// picture goes. It draws nothing and reads no file, so every layout rule is
/// testable without a PDF.
class ImagePdfLayout {
  const ImagePdfLayout._();

  /// Points per millimetre (a PDF point is 1/72 inch).
  static const double pointsPerMm = 72 / 25.4;

  /// Resolution the page assumes for a picture that states none.
  static const double defaultDpi = 96;

  /// Gap between neighbouring pictures of a tile sheet, in points.
  static const double tileGutterPt = 8;

  /// Height of the footer strip, in points.
  static const double footerBandHeightPt = 22;

  /// The smallest share of the page's shorter side the content area keeps.
  static const double minContentShare = 0.4;

  static double mmToPt(double mm) => mm * pointsPerMm;
  static double ptToMm(double pt) => pt / pointsPerMm;
  static double inchToMm(double inch) => inch * 25.4;
  static double mmToInch(double mm) => mm / 25.4;

  /// The portrait size (width <= height) of [size] in points.
  static ({double width, double height}) portraitSize(ImagePdfSettings s) {
    final double wMm;
    final double hMm;
    switch (s.pageSize) {
      case PdfPageSize.a3:
        wMm = 297;
        hMm = 420;
      case PdfPageSize.a4:
        wMm = 210;
        hMm = 297;
      case PdfPageSize.a5:
        wMm = 148;
        hMm = 210;
      case PdfPageSize.letter:
        wMm = inchToMm(8.5);
        hMm = inchToMm(11);
      case PdfPageSize.legal:
        wMm = inchToMm(8.5);
        hMm = inchToMm(14);
      case PdfPageSize.custom:
        wMm = math.min(s.customWidthMm, s.customHeightMm);
        hMm = math.max(s.customWidthMm, s.customHeightMm);
    }
    return (width: mmToPt(wMm), height: mmToPt(hMm));
  }

  /// The page size, in points, with [landscape] applied.
  static ({double width, double height}) pageSize(
      ImagePdfSettings s, bool landscape) {
    final portrait = portraitSize(s);
    return landscape
        ? (width: portrait.height, height: portrait.width)
        : portrait;
  }

  /// The margin in points, held so the content area keeps at least
  /// [minContentShare] of the page's shorter side.
  static double marginPt(
      ImagePdfSettings s, double pageWidth, double pageHeight) {
    final wanted = mmToPt(s.marginMm);
    final shorter = math.min(pageWidth, pageHeight);
    final most = shorter * (1 - minContentShare) / 2;
    return math.min(wanted, most);
  }

  /// Whether a single picture's page is landscape under [orientation].
  static bool _landscapeFor(PdfOrientation orientation, ImageDimensions image) {
    switch (orientation) {
      case PdfOrientation.portrait:
        return false;
      case PdfOrientation.landscape:
        return true;
      case PdfOrientation.auto:
        return image.isLandscape;
    }
  }

  /// Plans every page for [images] (in the order the user arranged them).
  static ImagePdfPlan plan(
    ImagePdfSettings settings,
    List<ImageDimensions> images,
  ) {
    final footer =
        (settings.pageNumbers || settings.timestamp) ? footerBandHeightPt : 0.0;
    final pages = <PlannedPage>[];
    var margin = 0.0;

    PlannedPage fitPage(int index, ImageDimensions image) {
      final landscape = _landscapeFor(settings.orientation, image);
      final size = pageSize(settings, landscape);
      margin = marginPt(settings, size.width, size.height);
      final content = _contentRect(size.width, size.height, margin, footer);
      final rect = settings.layout == PdfLayout.originalSize
          ? _originalRect(content, image)
          : _containRect(
              content, image.width.toDouble(), image.height.toDouble());
      return PlannedPage(
        width: size.width,
        height: size.height,
        images: <PlacedImage>[PlacedImage(index, rect)],
      );
    }

    if (images.isNotEmpty && settings.layout != PdfLayout.tileMultiple) {
      for (var i = 0; i < images.length; i++) {
        pages.add(fitPage(i, images[i]));
      }
    } else if (images.isNotEmpty) {
      final per = settings.tilesPerPage;
      for (var start = 0; start < images.length; start += per) {
        final end = math.min(start + per, images.length);
        pages.add(_tilePage(settings, images, start, end, footer, (m) {
          margin = m;
        }));
      }
    }

    if (settings.coverPage) {
      // The cover takes the first picture page's size, so a document that is
      // all landscape does not open on a portrait sheet.
      final first = pages.isEmpty
          ? pageSize(settings, settings.orientation == PdfOrientation.landscape)
          : (width: pages.first.width, height: pages.first.height);
      pages.insert(
          0,
          PlannedPage(
            width: first.width,
            height: first.height,
            images: const <PlacedImage>[],
            isCover: true,
          ));
    }
    if (pages.isEmpty) {
      margin = marginPt(settings, 1, 1);
    }
    return ImagePdfPlan(pages: pages, marginPt: margin, footerBandPt: footer);
  }

  static PlacedRect _contentRect(
      double width, double height, double margin, double footer) {
    return PlacedRect(
        margin, margin, width - 2 * margin, height - 2 * margin - footer);
  }

  /// The largest rectangle with the picture's shape that fits in [box],
  /// centred. Never crops; may enlarge a small picture to fill the box.
  static PlacedRect _containRect(PlacedRect box, double w, double h) {
    final scale = math.min(box.width / w, box.height / h);
    final width = w * scale;
    final height = h * scale;
    return PlacedRect(box.x + (box.width - width) / 2,
        box.y + (box.height - height) / 2, width, height);
  }

  /// The picture at its own physical size (pixels / its resolution), centred,
  /// and only shrunk when that would not fit the content area.
  static PlacedRect _originalRect(PlacedRect box, ImageDimensions image) {
    final dpi = image.dpi ?? defaultDpi;
    final naturalW = image.width * 72 / dpi;
    final naturalH = image.height * 72 / dpi;
    final scale =
        math.min(1.0, math.min(box.width / naturalW, box.height / naturalH));
    final width = naturalW * scale;
    final height = naturalH * scale;
    return PlacedRect(box.x + (box.width - width) / 2,
        box.y + (box.height - height) / 2, width, height);
  }

  static ({int cols, int rows}) _grid(int per, bool landscape) {
    switch (per) {
      case 2:
        return landscape ? (cols: 2, rows: 1) : (cols: 1, rows: 2);
      case 4:
        return (cols: 2, rows: 2);
      default:
        return landscape ? (cols: 3, rows: 2) : (cols: 2, rows: 3);
    }
  }

  static PlannedPage _tilePage(
    ImagePdfSettings s,
    List<ImageDimensions> images,
    int start,
    int end,
    double footer,
    void Function(double margin) setMargin,
  ) {
    PlannedPage layout(bool landscape) {
      final size = pageSize(s, landscape);
      final margin = marginPt(s, size.width, size.height);
      setMargin(margin);
      final content = _contentRect(size.width, size.height, margin, footer);
      final grid = _grid(s.tilesPerPage, landscape);
      final cellW =
          (content.width - tileGutterPt * (grid.cols - 1)) / grid.cols;
      final cellH =
          (content.height - tileGutterPt * (grid.rows - 1)) / grid.rows;
      final placed = <PlacedImage>[];
      for (var i = start; i < end; i++) {
        final slot = i - start;
        // Reading order: left to right, then top to bottom.
        final col = slot % grid.cols;
        final row = slot ~/ grid.cols;
        final cell = PlacedRect(
          content.x + col * (cellW + tileGutterPt),
          content.y + row * (cellH + tileGutterPt),
          cellW,
          cellH,
        );
        placed.add(PlacedImage(
            i,
            _containRect(cell, images[i].width.toDouble(),
                images[i].height.toDouble())));
      }
      return PlannedPage(
          width: size.width, height: size.height, images: placed);
    }

    switch (s.orientation) {
      case PdfOrientation.portrait:
        return layout(false);
      case PdfOrientation.landscape:
        return layout(true);
      case PdfOrientation.auto:
        // The sheet turns whichever way shows this sheet's pictures larger.
        final portrait = layout(false);
        final landscape = layout(true);
        double shown(PlannedPage page) =>
            page.images.fold<double>(0, (sum, p) => sum + p.rect.area);
        return shown(landscape) > shown(portrait) ? landscape : portrait;
    }
  }

  /// The resolution, in pixels per inch, the picture [placed] on a page would
  /// have if it were not resampled.
  static double effectiveDpi(ImageDimensions image, PlacedRect placed) {
    final inches = placed.width / 72;
    return inches <= 0 ? 0 : image.width / inches;
  }

  /// The pixel size a picture should be resampled to so that it has at most
  /// [dpi] pixels per inch at the size it is [placed] (never above its own
  /// pixels). Null when no resampling is needed (the difference is under 2 %).
  static ({int width, int height})? targetPixels(
      ImageDimensions image, PlacedRect placed, int dpi) {
    final wantW = placed.width / 72 * dpi;
    final wantH = placed.height / 72 * dpi;
    final scale =
        math.min(1.0, math.min(wantW / image.width, wantH / image.height));
    if (scale >= 0.98) return null;
    return (
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
    );
  }

  /// Print resolution per quality level.
  static int dpiFor(ImageQuality quality) {
    switch (quality) {
      case ImageQuality.low:
        return 96;
      case ImageQuality.medium:
        return 150;
      case ImageQuality.high:
        return 200;
      case ImageQuality.ultra:
        return 300;
    }
  }
}
