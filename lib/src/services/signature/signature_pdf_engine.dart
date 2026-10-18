import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
// The public API cannot say whether a loaded document was encrypted (a file
// with an empty user password opens without error), and a signed copy of an
// owner-protected file would silently carry on without its protection, so the
// engine reads the library's own flag. Pinned by the encrypted-file tests.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart'
    show PdfDocumentHelper;
// A page's boxes and rotation are read from its own dictionary, because the
// public `PdfPage.size` ignores the rotation, mixes the CropBox and MediaBox up
// and has no origin. See `readPageGeometry`.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart'
    show PdfPageHelper;
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart'
    show PdfArray;
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart'
    show PdfDictionary;
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart'
    show PdfNumber;
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart'
    show PdfCrossTable;
// The library draws on a loaded page in a coordinate system of its own, set up
// by a translation that depends on the page's boxes. The engine reads that
// translation back and cancels it, so a stamp is written in the page's plain
// user space, where the geometry model says where it goes.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/graphics/pdf_graphics.dart'
    show PdfGraphicsHelper;

import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';

bool _isDiskFull(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 28 || code == 112;
}

// ---------------------------------------------------------------- PNG helpers

/// The size and colour type of a PNG, read from its header without decoding it.
class PngHeader {
  const PngHeader(this.width, this.height, this.colorType);

  final int width;
  final int height;

  /// 0 grey, 2 RGB, 3 palette, 4 grey with alpha, 6 RGB with alpha.
  final int colorType;

  bool get hasAlphaChannel => colorType == 4 || colorType == 6;
}

/// The header of [bytes] when they begin like a PNG, otherwise null.
PngHeader? readPngHeader(Uint8List bytes) {
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 26) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  // The first chunk must be IHDR.
  if (data.getUint32(12) != 0x49484452) return null;
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return null;
  return PngHeader(width, height, bytes[25]);
}

/// [png] turned so that, drawn upright on a page whose `/Rotate` is
/// [pageRotation], it looks upright to a person looking at the page. A page
/// shown turned clockwise needs its content drawn turned the other way.
Uint8List stampPngForPageRotation(Uint8List png, int pageRotation) {
  if (pageRotation == 0) return png;
  final decoded = img.decodePng(png);
  if (decoded == null) {
    throw const SignatureException(SignatureFailure.stampFailed,
        detail: 'decode');
  }
  final turned = img.copyRotate(decoded, angle: (360 - pageRotation) % 360);
  return Uint8List.fromList(img.encodePng(turned));
}

// ----------------------------------------------------------------- analysis

/// Whether [bytes] hold a certificate based digital signature: a `/ByteRange`
/// entry, which every signature dictionary has. It is read from the raw bytes
/// so a signature the PDF library does not list as a field is still found. A
/// file that only mentions the word in text is refused too, which is the safe
/// way to be wrong.
bool bytesContainSignatureMarker(Uint8List bytes) {
  const marker = <int>[
    0x2F,
    0x42,
    0x79,
    0x74,
    0x65,
    0x52,
    0x61,
    0x6E,
    0x67,
    0x65,
  ];
  final last = bytes.length - marker.length;
  for (var i = 0; i <= last; i++) {
    if (bytes[i] != 0x2F) continue;
    var j = 1;
    while (j < marker.length && bytes[i + j] == marker[j]) {
      j++;
    }
    if (j == marker.length) return true;
  }
  return false;
}

bool _hasPdfHeader(Uint8List bytes) {
  const marker = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  final end = bytes.length > 1024 ? 1024 : bytes.length;
  for (var i = 0; i <= end - marker.length; i++) {
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

/// Opens [bytes] or throws `encryptedSource` (a password is needed, or the file
/// is encrypted even though it opens without one) or `corruptSource`.
PdfDocument _open(Uint8List bytes) {
  final PdfDocument document;
  try {
    document = PdfDocument(inputBytes: bytes);
  } on ArgumentError catch (error) {
    if (error.name == 'password') {
      throw const SignatureException(SignatureFailure.encryptedSource);
    }
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'parse');
  } catch (_) {
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'parse');
  }
  if (PdfDocumentHelper.getHelper(document).isEncrypted) {
    document.dispose();
    throw const SignatureException(SignatureFailure.encryptedSource);
  }
  return document;
}

/// The value of an already dereferenced PDF number, or null for anything else
/// (including a value that is not a finite number).
double? _numberOf(Object? primitive) {
  if (primitive is PdfNumber && primitive.value != null) {
    final value = primitive.value!.toDouble();
    return value.isFinite ? value : null;
  }
  return null;
}

PdfBox? _readBox(PdfDictionary dictionary, String key) {
  final primitive = dictionary.getValue(key, 'Parent');
  if (primitive is! PdfArray || primitive.count < 4) return null;
  final numbers = <double>[];
  for (var i = 0; i < 4; i++) {
    final value = _numberOf(PdfCrossTable.dereference(primitive[i]));
    if (value == null) return null;
    numbers.add(value);
  }
  return PdfBox.fromCorners(numbers[0], numbers[1], numbers[2], numbers[3]);
}

/// The boxes and rotation of [page], read from the page's own dictionary
/// (inherited from its parents when it has none). Follows what a viewer shows: a
/// CropBox with no area counts as absent, and the visible page is the CropBox
/// clipped to the MediaBox. Throws `corruptSource` for a page with no MediaBox
/// and `geometryUnsupported` when the boxes cannot give a page.
PageGeometry readPageGeometry(PdfPage page) {
  final dictionary = PdfPageHelper.getHelper(page).dictionary;
  if (dictionary == null) {
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'page');
  }
  final media = _readBox(dictionary, 'MediaBox');
  if (media == null || !media.isValid) {
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'media-box');
  }
  var crop = _readBox(dictionary, 'CropBox');
  if (crop != null && !crop.isValid) crop = null;
  final rotate = _numberOf(dictionary.getValue('Rotate', 'Parent'));
  final geometry = PageGeometry(
    mediaBox: media,
    cropBox: crop,
    rotation: PageGeometry.normalizeRotation(rotate ?? 0),
  );
  if (!geometry.hasUsableBoxes) {
    throw const SignatureException(SignatureFailure.geometryUnsupported,
        detail: 'boxes');
  }
  return geometry;
}

class _Counts {
  const _Counts(this.formFieldCount, this.annotationCounts, this.signed,
      this.hasFields, this.hasAnnotations);

  final int formFieldCount;
  final List<int> annotationCounts;
  final bool signed;
  final bool hasFields;
  final bool hasAnnotations;
}

/// Reads the form fields and annotations of [document]. Must only be used on a
/// document that will never be saved: reading the form makes the library parse
/// (and, on a save, rewrite) the form.
_Counts _countStructure(PdfDocument document, Uint8List bytes) {
  var signed = bytesContainSignatureMarker(bytes);
  var fieldCount = 0;
  var hasFields = false;
  try {
    final fields = document.form.fields;
    fieldCount = fields.count;
    for (var i = 0; i < fields.count; i++) {
      final field = fields[i];
      if (field is PdfSignatureField && field.isSigned) {
        signed = true;
      } else {
        hasFields = true;
      }
    }
  } catch (_) {
    // A form that cannot be read is treated as present: the signed copy then
    // has to match it exactly, and the raw check above still finds signatures.
    hasFields = true;
  }
  final annotationCounts = <int>[];
  var hasAnnotations = false;
  for (var i = 0; i < document.pages.count; i++) {
    int count;
    try {
      count = document.pages[i].annotations.count;
    } catch (_) {
      count = 0;
    }
    annotationCounts.add(count);
    if (count > 0) hasAnnotations = true;
  }
  return _Counts(
      fieldCount, annotationCounts, signed, hasFields, hasAnnotations);
}

/// Reads [path] and decides whether it is a PDF the Signature tool may open.
/// Throws a [SignatureException] (`missingSource`, `emptySource`,
/// `tooLargeSource`, `corruptSource`, `encryptedSource`, `tooManyPages`,
/// `geometryUnsupported`). A signed PDF is reported through
/// [SignatureFeatures.hasSignatures], not thrown, so the caller can decide: the
/// editor refuses it, while a stored copy is only inspected.
///
/// Synchronous on purpose: it runs on a worker isolate, never on the UI one.
SignatureAnalysis analyzeSignaturePdf(String path, {required int maxBytes}) {
  final file = File(path);
  final int size;
  try {
    if (!file.existsSync()) {
      throw const SignatureException(SignatureFailure.missingSource);
    }
    size = file.lengthSync();
  } on FileSystemException {
    throw const SignatureException(SignatureFailure.missingSource);
  }
  if (size <= 0) {
    throw const SignatureException(SignatureFailure.emptySource);
  }
  if (size > maxBytes) {
    throw const SignatureException(SignatureFailure.tooLargeSource);
  }
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    throw const SignatureException(SignatureFailure.missingSource);
  }
  if (!_hasPdfHeader(bytes)) {
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'header');
  }
  final document = _open(bytes);
  try {
    final count = document.pages.count;
    if (count < 1) {
      throw const SignatureException(SignatureFailure.corruptSource,
          detail: 'pages');
    }
    if (count > SignatureLimits.maxPages) {
      throw const SignatureException(SignatureFailure.tooManyPages);
    }
    final pages = <PageGeometry>[];
    for (var i = 0; i < count; i++) {
      pages.add(readPageGeometry(document.pages[i]));
    }
    final counts = _countStructure(document, bytes);
    return SignatureAnalysis(
      size: size,
      pageCount: count,
      pages: pages,
      features: SignatureFeatures(
        hasSignatures: counts.signed,
        hasFormFields: counts.hasFields,
        hasAnnotations: counts.hasAnnotations,
      ),
      formFieldCount: counts.formFieldCount,
      annotationCounts: counts.annotationCounts,
    );
  } on SignatureException {
    rethrow;
  } catch (_) {
    throw const SignatureException(SignatureFailure.corruptSource,
        detail: 'read');
  } finally {
    document.dispose();
  }
}

// -------------------------------------------------------------------- writing

/// One item to write: which image, which page, and the rectangle it covers in
/// the page's visible points.
class SignatureWritePlacement {
  const SignatureWritePlacement({
    required this.pageIndex,
    required this.imageIndex,
    required this.rect,
  });

  final int pageIndex;

  /// Index into [SignatureWriteJob.images].
  final int imageIndex;
  final PageRect rect;
}

/// Everything the write needs, as plain data so it can cross to a worker
/// isolate.
class SignatureWriteJob {
  const SignatureWriteJob({
    required this.sourcePath,
    required this.source,
    required this.images,
    required this.placements,
    required this.outputPath,
  });

  final String sourcePath;

  /// What the source proved to be when it was opened. The write refuses a file
  /// that has changed since.
  final SignatureAnalysis source;

  /// The PNG of each distinct stamp, upright and transparent.
  final List<Uint8List> images;
  final List<SignatureWritePlacement> placements;

  /// Where the signed copy is written. The caller owns this path; the engine
  /// writes it only when the copy is complete and verified, and removes it when
  /// anything fails.
  final String outputPath;
}

class SignatureWriteResult {
  const SignatureWriteResult({
    required this.size,
    required this.pageCount,
    required this.placementCount,
    required this.appendedOnly,
  });

  final int size;
  final int pageCount;
  final int placementCount;

  /// The signed copy is the original file's bytes followed by an appended update:
  /// nothing of the original was rewritten.
  final bool appendedOnly;
}

void _validatePlacements(SignatureWriteJob job) {
  if (job.placements.isEmpty) {
    throw const SignatureException(SignatureFailure.noPlacements);
  }
  if (job.placements.length > SignatureLimits.maxItems) {
    throw const SignatureException(SignatureFailure.tooManyItems);
  }
  for (final placement in job.placements) {
    if (placement.pageIndex < 0 ||
        placement.pageIndex >= job.source.pageCount ||
        placement.imageIndex < 0 ||
        placement.imageIndex >= job.images.length) {
      throw const SignatureException(SignatureFailure.invalidPlacement,
          detail: 'index');
    }
    final geometry = job.source.pages[placement.pageIndex];
    final rect = placement.rect;
    const slack = 0.01;
    if (!rect.isFinite ||
        rect.width < 1 ||
        rect.height < 1 ||
        rect.left < -slack ||
        rect.top < -slack ||
        rect.right > geometry.width + slack ||
        rect.bottom > geometry.height + slack) {
      throw const SignatureException(SignatureFailure.invalidPlacement,
          detail: 'bounds');
    }
  }
}

Uint8List _readSource(SignatureWriteJob job) {
  final file = File(job.sourcePath);
  try {
    if (!file.existsSync()) {
      throw const SignatureException(SignatureFailure.missingSource);
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length != job.source.size) {
      throw const SignatureException(SignatureFailure.sourceChanged);
    }
    return bytes;
  } on FileSystemException {
    throw const SignatureException(SignatureFailure.missingSource);
  }
}

/// Writes every placement of [job] onto its page and saves the result at
/// [SignatureWriteJob.outputPath].
///
/// The signed copy is an incremental update: the PDF library keeps the original
/// file's bytes and appends the changed objects after them, so every page that
/// was not touched, every form field, link, annotation and font is exactly as it
/// was. The source file itself is never written. Each stamp is added as page
/// content after the page's own content (the library encloses the original in a
/// save/restore pair first), so it sits on top and cannot be altered by what the
/// original page left in the graphics state.
///
/// Placement is exact: a placement is a rectangle of the visible page, the page's
/// [PageGeometry] turns it into user space, the stamp image is turned to match
/// the page's rotation, and the library's own coordinate set-up is cancelled so
/// the rectangle lands exactly there.
///
/// All or nothing: the copy is verified before the call returns (page count, each
/// page's boxes and rotation, form fields, annotations per page, no encryption or
/// signature) and any failure leaves no output behind. [isCancelled] is checked
/// between pages (on a worker isolate the caller stops the isolate instead).
SignatureWriteResult runSignatureWrite(
  SignatureWriteJob job, {
  bool Function()? isCancelled,
}) {
  final output = File(job.outputPath);
  PdfDocument? document;
  try {
    _validatePlacements(job);
    final sourceBytes = _readSource(job);
    if (bytesContainSignatureMarker(sourceBytes)) {
      throw const SignatureException(SignatureFailure.signedSource);
    }
    document = _open(sourceBytes);
    if (document.pages.count != job.source.pageCount) {
      throw const SignatureException(SignatureFailure.sourceChanged);
    }
    final byPage = <int, List<SignatureWritePlacement>>{};
    for (final placement in job.placements) {
      byPage
          .putIfAbsent(placement.pageIndex, () => <SignatureWritePlacement>[])
          .add(placement);
    }
    final bitmaps = <String, PdfBitmap>{};
    final pageIndexes = byPage.keys.toList()..sort();
    for (final pageIndex in pageIndexes) {
      if (isCancelled?.call() ?? false) {
        throw const SignatureException(SignatureFailure.cancelled);
      }
      final page = document.pages[pageIndex];
      final geometry = readPageGeometry(page);
      if (!geometry.isCloseTo(job.source.pages[pageIndex])) {
        throw const SignatureException(SignatureFailure.sourceChanged);
      }
      final graphics = page.graphics;
      final matrix = PdfGraphicsHelper.getHelper(graphics).matrix.matrix;
      final offsetX = matrix.elements[4];
      final offsetY = matrix.elements[5];
      final clientHeight = graphics.clientSize.height;
      final state = graphics.save();
      // Back to the page's plain user space.
      graphics.translateTransform(-offsetX, offsetY);
      for (final placement in byPage[pageIndex]!) {
        final key = '${placement.imageIndex}:${geometry.rotation}';
        final bitmap = bitmaps[key] ??= PdfBitmap(stampPngForPageRotation(
            job.images[placement.imageIndex], geometry.rotation));
        final user = geometry.userRectOf(placement.rect);
        // The library places an image at y = -(top) in this space, and moves it
        // by the client height when that is negative.
        final y = -user.top - (clientHeight < 0 ? clientHeight : 0.0);
        graphics.drawImage(
            bitmap, Rect.fromLTWH(user.left, y, user.width, user.height));
      }
      graphics.restore(state);
    }
    if (isCancelled?.call() ?? false) {
      throw const SignatureException(SignatureFailure.cancelled);
    }
    final List<int> bytes = document.saveSync();
    document.dispose();
    document = null;
    try {
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw SignatureException(_isDiskFull(error)
          ? SignatureFailure.storageFull
          : SignatureFailure.writeFailed);
    }
    final appendedOnly = verifySignatureOutput(
      output: output,
      source: job.source,
      sourceBytes: sourceBytes,
    );
    return SignatureWriteResult(
      size: output.lengthSync(),
      pageCount: job.source.pageCount,
      placementCount: job.placements.length,
      appendedOnly: appendedOnly,
    );
  } on SignatureException {
    _quietDelete(output);
    rethrow;
  } catch (_) {
    _quietDelete(output);
    throw const SignatureException(SignatureFailure.writeFailed);
  } finally {
    document?.dispose();
  }
}

/// Reads the finished file back and checks it against what the source proved to
/// be: readable, not encrypted, not signed, the same pages with the same boxes
/// and rotation, the same form fields and the same annotations on every page.
/// Returns whether the file is the source's bytes followed by an appended update.
/// Throws `outputInvalid`.
bool verifySignatureOutput({
  required File output,
  required SignatureAnalysis source,
  Uint8List? sourceBytes,
}) {
  final Uint8List bytes;
  try {
    bytes = output.readAsBytesSync();
  } on FileSystemException {
    throw const SignatureException(SignatureFailure.outputInvalid,
        detail: 'read');
  }
  if (bytesContainSignatureMarker(bytes) &&
      !(sourceBytes != null && bytesContainSignatureMarker(sourceBytes))) {
    throw const SignatureException(SignatureFailure.outputInvalid,
        detail: 'signature');
  }
  final PdfDocument document;
  try {
    document = PdfDocument(inputBytes: bytes);
  } catch (_) {
    throw const SignatureException(SignatureFailure.outputInvalid,
        detail: 'parse');
  }
  try {
    if (PdfDocumentHelper.getHelper(document).isEncrypted) {
      throw const SignatureException(SignatureFailure.outputInvalid,
          detail: 'encrypted');
    }
    if (document.pages.count != source.pageCount) {
      throw const SignatureException(SignatureFailure.outputInvalid,
          detail: 'count');
    }
    for (var i = 0; i < source.pageCount; i++) {
      final PageGeometry geometry;
      try {
        geometry = readPageGeometry(document.pages[i]);
      } on SignatureException {
        throw const SignatureException(SignatureFailure.outputInvalid,
            detail: 'geometry');
      }
      if (!geometry.isCloseTo(source.pages[i])) {
        throw const SignatureException(SignatureFailure.outputInvalid,
            detail: 'geometry');
      }
    }
    final counts = _countStructure(document, bytes);
    if (counts.formFieldCount != source.formFieldCount) {
      throw const SignatureException(SignatureFailure.outputInvalid,
          detail: 'form');
    }
    if (counts.annotationCounts.length != source.annotationCounts.length) {
      throw const SignatureException(SignatureFailure.outputInvalid,
          detail: 'annotations');
    }
    for (var i = 0; i < counts.annotationCounts.length; i++) {
      if (counts.annotationCounts[i] != source.annotationCounts[i]) {
        throw const SignatureException(SignatureFailure.outputInvalid,
            detail: 'annotations');
      }
    }
  } on SignatureException {
    rethrow;
  } catch (_) {
    throw const SignatureException(SignatureFailure.outputInvalid,
        detail: 'check');
  } finally {
    document.dispose();
  }
  if (sourceBytes == null || bytes.length <= sourceBytes.length) return false;
  for (var i = 0; i < sourceBytes.length; i++) {
    if (bytes[i] != sourceBytes[i]) return false;
  }
  return true;
}

void _quietDelete(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
