import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfPageSize;
// The public API cannot say whether a loaded document was encrypted (a file
// with an empty user password opens without error), so the engine reads the
// library's own flag. Pinned by the protection tests.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart'
    show PdfDocumentHelper;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_layout.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_processor.dart';

/// The words the PDF itself shows (the cover page). The caller localizes them;
/// nothing here is read from a picture.
class ImagePdfTexts {
  const ImagePdfTexts(
      {this.coverTitle = '', this.coverLines = const <String>[]});

  final String coverTitle;
  final List<String> coverLines;
}

/// Everything a conversion needs, as plain data so it can cross to a worker
/// isolate.
class ImagePdfBuildJob {
  const ImagePdfBuildJob({
    required this.images,
    required this.settings,
    required this.outputPath,
    required this.timestamp,
    this.password,
    this.texts = const ImagePdfTexts(),
    this.unicodeFont,
  });

  /// The pictures, in page order.
  final List<ImageSpec> images;
  final ImagePdfSettings settings;

  /// Where the finished file is written. The caller owns this path; the engine
  /// writes it only when the PDF is complete and verified, and removes anything
  /// partial when something fails.
  final String outputPath;

  /// The one moment shown on the pages (and the cover) of this PDF.
  final DateTime timestamp;

  /// Set when the PDF is password protected. Used to encrypt and to verify the
  /// result; never written anywhere.
  final String? password;
  final ImagePdfTexts texts;

  /// The bundled Arabic font, needed only when a text is not plain Latin.
  final Uint8List? unicodeFont;
}

class ImagePdfBuildResult {
  const ImagePdfBuildResult({
    required this.pageCount,
    required this.imageCount,
    required this.size,
    required this.lowResolutionImages,
    required this.encrypted,
  });

  final int pageCount;
  final int imageCount;
  final int size;

  /// Pictures that print below about 100 pixels per inch at the size they are
  /// placed: they will look soft however the PDF is made.
  final int lowResolutionImages;
  final bool encrypted;
}

/// What a stored or fresh PDF file proved to be.
class ImagePdfFileInfo {
  const ImagePdfFileInfo({
    required this.size,
    required this.pageCount,
    required this.encrypted,
  });

  final int size;

  /// 0 when the file is password protected and no password was given.
  final int pageCount;
  final bool encrypted;
}

bool _isDiskFull(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 28 || code == 112;
}

const int _lowResolutionDpi = 100;

class _Fonts {
  _Fonts(this._unicode);

  final Uint8List? _unicode;
  final Map<String, PdfFont> _cache = <String, PdfFont>{};

  PdfFont of(String text, double size, {bool bold = false}) {
    final unicode = ImagePdfText.needsUnicodeFont(text);
    final key = '${unicode ? 'u' : 'l'}${bold ? 'b' : 'r'}$size';
    return _cache.putIfAbsent(key, () {
      if (!unicode) {
        return PdfStandardFont(PdfFontFamily.helvetica, size,
            style: bold ? PdfFontStyle.bold : PdfFontStyle.regular);
      }
      final data = _unicode;
      if (data == null) {
        throw const ImagePdfException(ImagePdfFailure.buildFailed,
            detail: 'font');
      }
      return PdfTrueTypeFont(data, size,
          style: bold ? PdfFontStyle.bold : PdfFontStyle.regular);
    });
  }

  static bool isRtl(String text) => text.runes.any((r) =>
      (r >= 0x0600 && r <= 0x06FF) ||
      (r >= 0x0750 && r <= 0x077F) ||
      (r >= 0xFB50 && r <= 0xFDFF) ||
      (r >= 0xFE70 && r <= 0xFEFF));

  static PdfStringFormat format(String text,
          {PdfTextAlignment alignment = PdfTextAlignment.left,
          PdfVerticalAlignment line = PdfVerticalAlignment.top}) =>
      PdfStringFormat(
        alignment: alignment,
        lineAlignment: line,
        textDirection:
            isRtl(text) ? PdfTextDirection.rightToLeft : PdfTextDirection.none,
      );
}

/// Makes the PDF described by [job] at [job.outputPath] and returns what it
/// holds. All or nothing: the file is read back and checked (page count, every
/// page's size, the page numbers and the date, and, for a protected file, that
/// it really needs the password) before it replaces anything, and any failure
/// or cancel leaves no output behind. The pictures are only read.
///
/// Synchronous on purpose: it runs on a worker isolate, never on the UI one.
/// [isCancelled] is polled between pictures.
ImagePdfBuildResult buildImagePdf(
  ImagePdfBuildJob job, {
  bool Function()? isCancelled,
}) {
  final settings = job.settings;
  if (settings.validate() != null) {
    throw const ImagePdfException(ImagePdfFailure.invalidSettings);
  }
  if (job.images.isEmpty) {
    throw const ImagePdfException(ImagePdfFailure.noImages);
  }
  if (job.images.length > ImagePdfLimits.maxImages) {
    throw const ImagePdfException(ImagePdfFailure.tooManyImages);
  }
  final password = job.password;
  if (settings.passwordProtect) {
    if (password == null || !ImagePdfText.isValidPassword(password)) {
      throw const ImagePdfException(ImagePdfFailure.invalidPassword);
    }
  }
  void checkCancelled() {
    if (isCancelled != null && isCancelled()) {
      throw const ImagePdfException(ImagePdfFailure.cancelled);
    }
  }

  final dimensions = <ImageDimensions>[
    for (final image in job.images)
      ImageDimensions(image.width, image.height, dpi: image.dpi),
  ];
  final plan = ImagePdfLayout.plan(settings, dimensions);
  final fonts = _Fonts(job.unicodeFont);
  final dpi = ImagePdfLayout.dpiFor(settings.quality);
  final stamp = ImagePdfText.formatTimestamp(job.timestamp);
  var lowResolution = 0;
  var pictureBytes = 0;

  final document = PdfDocument();
  try {
    document.compressionLevel = PdfCompressionLevel.best;
    document.documentInformation.creator = 'Broker Wallet';
    document.documentInformation.producer = 'Broker Wallet';
    // UTC: the library writes a local offset with the wrong minutes.
    document.documentInformation.creationDate = job.timestamp.toUtc();
    document.pageSettings.margins.all = 0;

    for (var pageIndex = 0; pageIndex < plan.pages.length; pageIndex++) {
      checkCancelled();
      final planned = plan.pages[pageIndex];
      final section = document.sections!.add();
      section.pageSettings.margins.all = 0;
      section.pageSettings.orientation = planned.width > planned.height
          ? PdfPageOrientation.landscape
          : PdfPageOrientation.portrait;
      section.pageSettings.size = Size(planned.width, planned.height);
      final page = section.pages.add();
      final g = page.graphics;

      if (planned.isCover) {
        _drawCover(g, planned, plan.marginPt, job, fonts, stamp);
        continue;
      }
      for (final placed in planned.images) {
        checkCancelled();
        final spec = job.images[placed.imageIndex];
        final dim = dimensions[placed.imageIndex];
        final rect = placed.rect;
        if (ImagePdfLayout.effectiveDpi(dim, rect) < _lowResolutionDpi) {
          lowResolution++;
        }
        final ProcessedImage processed;
        try {
          processed = processImage(
            spec,
            compression: settings.compression,
            target: ImagePdfLayout.targetPixels(dim, rect, dpi),
          );
        } on ImagePdfException catch (error) {
          // Say which picture, so the screen can name it.
          throw ImagePdfException(error.kind,
              sourceId: spec.id, detail: error.detail);
        }
        pictureBytes += processed.bytes.length;
        if (pictureBytes > ImagePdfLimits.maxOutputBytes) {
          throw const ImagePdfException(ImagePdfFailure.outputTooLarge);
        }
        final PdfBitmap bitmap;
        try {
          bitmap = PdfBitmap(processed.bytes);
        } catch (_) {
          throw ImagePdfException(ImagePdfFailure.buildFailed,
              sourceId: spec.id, detail: 'embed');
        }
        g.drawImage(
            bitmap, Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height));
        if (settings.layout == PdfLayout.centerFit) {
          g.drawRectangle(
              pen: PdfPen(PdfColor(150, 150, 150), width: 0.5),
              bounds: Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height));
        }
      }
      if (settings.watermark) {
        _drawWatermark(g, planned, settings.effectiveWatermark, fonts);
      }
      if (settings.pageNumbers || settings.timestamp) {
        _drawFooter(g, planned, plan, pageIndex, settings, stamp, fonts);
      }
    }

    if (settings.passwordProtect) {
      final security = document.security;
      security.algorithm = PdfEncryptionAlgorithm.aesx256BitRevision6;
      security.userPassword = password!;
      security.ownerPassword = password;
    }
    checkCancelled();
    final bytes = Uint8List.fromList(document.saveSync());
    _verifyBuilt(bytes, plan, settings, stamp, password);
    _writeAtomically(job.outputPath, bytes);
    return ImagePdfBuildResult(
      pageCount: plan.pageCount,
      imageCount: job.images.length,
      size: bytes.length,
      lowResolutionImages: lowResolution,
      encrypted: settings.passwordProtect,
    );
  } on ImagePdfException {
    _removePart(job.outputPath);
    rethrow;
  } on FileSystemException catch (error) {
    _removePart(job.outputPath);
    throw mapImageFileError(error);
  } catch (_) {
    _removePart(job.outputPath);
    throw const ImagePdfException(ImagePdfFailure.buildFailed);
  } finally {
    document.dispose();
  }
}

void _removePart(String path) {
  try {
    final part = File('$path.part');
    if (part.existsSync()) part.deleteSync();
  } catch (_) {}
}

void _writeAtomically(String path, Uint8List bytes) {
  final part = File('$path.part');
  try {
    part.writeAsBytesSync(bytes, flush: true);
    if (part.lengthSync() != bytes.length) {
      throw const ImagePdfException(ImagePdfFailure.writeFailed,
          detail: 'length');
    }
    part.renameSync(path);
  } on FileSystemException catch (error) {
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
    throw _isDiskFull(error)
        ? const ImagePdfException(ImagePdfFailure.storageFull)
        : const ImagePdfException(ImagePdfFailure.writeFailed, detail: 'io');
  }
}

/// The height a text needs when laid out in [width]. The library draws nothing
/// at all when the given bounds are shorter than one line (a tall Arabic font
/// needs about 1.7 times its size), so bounds are always taken from this.
double _heightOf(PdfFont font, String text, double width) =>
    font.measureString(text, layoutArea: Size(width, 0)).height + 4;

void _drawCover(PdfGraphics g, PlannedPage page, double margin,
    ImagePdfBuildJob job, _Fonts fonts, String stamp) {
  final side = math.max(margin, ImagePdfLayout.mmToPt(15));
  final width = page.width - 2 * side;
  var title = job.texts.coverTitle.trim();
  if (title.isEmpty || !ImagePdfText.isRenderable(title)) {
    title = ImagePdfSettings.defaultWatermark;
  }
  final titleFont = fonts.of(title, 28, bold: true);
  var y = page.height * 0.28;
  final titleHeight = _heightOf(titleFont, title, width);
  g.drawString(title, titleFont,
      brush: PdfSolidBrush(PdfColor(30, 30, 30)),
      bounds: Rect.fromLTWH(side, y, width, titleHeight),
      format: _Fonts.format(title, alignment: PdfTextAlignment.center));
  y += titleHeight + 14;
  final lines = <String>[
    ...job.texts.coverLines,
    if (job.settings.timestamp) stamp,
  ];
  for (final line in lines) {
    final text = line.trim();
    if (text.isEmpty || !ImagePdfText.isRenderable(text)) continue;
    final font = fonts.of(text, 14);
    final height = _heightOf(font, text, width);
    g.drawString(text, font,
        brush: PdfSolidBrush(PdfColor(90, 90, 90)),
        bounds: Rect.fromLTWH(side, y, width, height),
        format: _Fonts.format(text, alignment: PdfTextAlignment.center));
    y += height + 6;
  }
  const brand = ImagePdfSettings.defaultWatermark;
  final brandFont = fonts.of(brand, 10);
  final brandHeight = _heightOf(brandFont, brand, width);
  g.drawString(brand, brandFont,
      brush: PdfSolidBrush(PdfColor(140, 140, 140)),
      bounds: Rect.fromLTWH(
          side, page.height - side - brandHeight, width, brandHeight),
      format: _Fonts.format(brand, alignment: PdfTextAlignment.center));
}

void _drawWatermark(
    PdfGraphics g, PlannedPage page, String text, _Fonts fonts) {
  // Size the text so it spans about 60 % of the page diagonal.
  final reference = fonts.of(text, 100);
  final measured = reference.measureString(text).width;
  final diagonal =
      math.sqrt(page.width * page.width + page.height * page.height);
  final size = measured <= 0
      ? 40.0
      : (100 * diagonal * 0.6 / measured).clamp(14.0, 72.0).toDouble();
  final font = fonts.of(text, size, bold: true);
  final box = font.measureString(text);
  final width = box.width + 24;
  final height = box.height + 12;
  final state = g.save();
  g.setTransparency(0.14);
  g.translateTransform(page.width / 2, page.height / 2);
  g.rotateTransform(-45);
  g.drawString(text, font,
      brush: PdfSolidBrush(PdfColor(90, 90, 90)),
      bounds: Rect.fromLTWH(-width / 2, -height / 2, width, height),
      format: _Fonts.format(text,
          alignment: PdfTextAlignment.center,
          line: PdfVerticalAlignment.middle));
  g.restore(state);
}

void _drawFooter(PdfGraphics g, PlannedPage page, ImagePdfPlan plan,
    int pageIndex, ImagePdfSettings settings, String stamp, _Fonts fonts) {
  final margin = math.max(plan.marginPt, ImagePdfLayout.mmToPt(4));
  final y = page.height - plan.marginPt - plan.footerBandPt + 6;
  final font = fonts.of('0', 9);
  final brush = PdfSolidBrush(PdfColor(90, 90, 90));
  final inner = page.width - 2 * margin;
  if (settings.timestamp) {
    g.drawString(stamp, font,
        brush: brush,
        bounds: Rect.fromLTWH(margin, y, inner / 2, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.left));
  }
  if (settings.pageNumbers) {
    g.drawString(ImagePdfText.pageNumber(pageIndex, plan.pageCount), font,
        brush: brush,
        bounds: Rect.fromLTWH(margin + inner / 2, y, inner / 2, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
  }
}

/// Reads the just-built PDF back and checks it against the plan. Throws
/// `outputInvalid` for any mismatch.
void _verifyBuilt(Uint8List bytes, ImagePdfPlan plan, ImagePdfSettings settings,
    String stamp, String? password) {
  const invalid = ImagePdfException(ImagePdfFailure.outputInvalid);
  if (settings.passwordProtect) {
    // It must refuse to open without the password...
    try {
      PdfDocument(inputBytes: bytes).dispose();
      throw const ImagePdfException(ImagePdfFailure.outputInvalid,
          detail: 'open-without-password');
    } on ArgumentError catch (error) {
      if (error.name != 'password') throw invalid;
    }
  }
  final PdfDocument document;
  try {
    document = settings.passwordProtect
        ? PdfDocument(inputBytes: bytes, password: password)
        : PdfDocument(inputBytes: bytes);
  } catch (_) {
    throw invalid;
  }
  try {
    if (settings.passwordProtect &&
        !PdfDocumentHelper.getHelper(document).isEncrypted) {
      throw const ImagePdfException(ImagePdfFailure.outputInvalid,
          detail: 'not-encrypted');
    }
    if (document.pages.count != plan.pageCount) {
      throw const ImagePdfException(ImagePdfFailure.outputInvalid,
          detail: 'pages');
    }
    final extractor = PdfTextExtractor(document);
    for (var i = 0; i < plan.pageCount; i++) {
      final planned = plan.pages[i];
      final size = document.pages[i].size;
      if ((size.width - planned.width).abs() > 1.0 ||
          (size.height - planned.height).abs() > 1.0) {
        throw const ImagePdfException(ImagePdfFailure.outputInvalid,
            detail: 'size');
      }
      if (planned.isCover) continue;
      if (settings.pageNumbers || settings.timestamp) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (settings.pageNumbers &&
            !text.contains(ImagePdfText.pageNumber(i, plan.pageCount))) {
          throw const ImagePdfException(ImagePdfFailure.outputInvalid,
              detail: 'number');
        }
        if (settings.timestamp && !text.contains(stamp)) {
          throw const ImagePdfException(ImagePdfFailure.outputInvalid,
              detail: 'stamp');
        }
      }
    }
  } on ImagePdfException {
    rethrow;
  } catch (_) {
    throw invalid;
  } finally {
    document.dispose();
  }
}

/// Reads [path] and says what PDF it is: its size, its page count and whether
/// it is password protected. A protected file cannot be counted without its
/// password, so [password] is optional; without it only the file's shape is
/// checked (header, end marker, the encryption entry). Throws an
/// [ImagePdfException] (`missingSource`, `emptySource`, `corruptSource`).
///
/// Synchronous on purpose: it runs on a worker isolate.
ImagePdfFileInfo analyzeImagePdf(String path, {String? password}) {
  final file = File(path);
  final Uint8List bytes;
  try {
    if (!file.existsSync()) {
      throw const ImagePdfException(ImagePdfFailure.missingSource);
    }
    if (file.lengthSync() <= 0) {
      throw const ImagePdfException(ImagePdfFailure.emptySource);
    }
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    throw const ImagePdfException(ImagePdfFailure.missingSource);
  }
  if (!_hasPdfHeader(bytes)) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'header');
  }
  PdfDocument document;
  try {
    document = password == null
        ? PdfDocument(inputBytes: bytes)
        : PdfDocument(inputBytes: bytes, password: password);
  } on ArgumentError catch (error) {
    if (error.name == 'password') {
      if (!_looksComplete(bytes)) {
        throw const ImagePdfException(ImagePdfFailure.corruptSource,
            detail: 'truncated');
      }
      return ImagePdfFileInfo(
          size: bytes.length, pageCount: 0, encrypted: true);
    }
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'parse');
  } catch (_) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'parse');
  }
  try {
    final count = document.pages.count;
    if (count < 1) {
      throw const ImagePdfException(ImagePdfFailure.corruptSource,
          detail: 'pages');
    }
    for (var i = 0; i < count; i++) {
      final Size size;
      try {
        size = document.pages[i].size;
      } catch (_) {
        throw const ImagePdfException(ImagePdfFailure.corruptSource,
            detail: 'page');
      }
      if (size.width <= 0 || size.height <= 0) {
        throw const ImagePdfException(ImagePdfFailure.corruptSource,
            detail: 'page-size');
      }
    }
    return ImagePdfFileInfo(
      size: bytes.length,
      pageCount: count,
      encrypted: PdfDocumentHelper.getHelper(document).isEncrypted,
    );
  } on ImagePdfException {
    rethrow;
  } catch (_) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'read');
  } finally {
    document.dispose();
  }
}

bool _hasPdfHeader(Uint8List bytes) {
  const marker = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  final limit = math.min(bytes.length, 1024) - marker.length;
  for (var i = 0; i <= limit; i++) {
    var match = true;
    for (var j = 0; j < marker.length; j++) {
      if (bytes[i + j] != marker[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// The end of a complete PDF carries `%%EOF` near its last bytes.
bool _looksComplete(Uint8List bytes) {
  final start = math.max(0, bytes.length - 1100);
  final tail = String.fromCharCodes(bytes.sublist(start));
  return tail.contains('%%EOF');
}
