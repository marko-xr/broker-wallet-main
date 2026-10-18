import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:syncfusion_flutter_pdf/pdf.dart';
// The public API cannot say whether a loaded document was encrypted (a file
// with an empty user password opens without error), and a combined copy of an
// owner-protected file would silently drop its protection, so the engine reads
// the library's own flag. Pinned by the encrypted-file tests.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart'
    show PdfDocumentHelper;

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';

/// What a PDF proved to be, read from the file itself.
class CombineAnalysis {
  const CombineAnalysis({
    required this.size,
    required this.pageCount,
    required this.features,
  });

  final int size;
  final int pageCount;
  final CombineFeatures features;
}

/// Everything the combine needs, as plain data so it can cross to a worker
/// isolate.
class CombineMergeJob {
  const CombineMergeJob({
    required this.sources,
    required this.pages,
    required this.outputPath,
  });

  final List<CombineSource> sources;
  final List<CombinePageRef> pages;

  /// Where the combined file is written. The caller owns this path; the engine
  /// writes it only when the combined file is complete, and removes it when
  /// anything fails.
  final String outputPath;
}

class CombineMergeResult {
  const CombineMergeResult({required this.pageCount, required this.size});

  final int pageCount;
  final int size;
}

bool _isDiskFull(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 28 || code == 112;
}

/// Reads [path] and decides whether it is a PDF the Combine tool may use.
/// Throws a [CombinePdfException] (`missingSource`, `emptySource`,
/// `tooLargeSource`, `corruptSource`, `encryptedSource`). A signed PDF is
/// reported through [CombineFeatures.hasSignatures], not thrown, so the caller
/// can decide (Combine refuses it; a stored combined file is only inspected).
///
/// Synchronous on purpose: it runs on a worker isolate, never on the UI one.
CombineAnalysis analyzeCombinePdf(String path, {required int maxBytes}) {
  final file = File(path);
  final int size;
  try {
    if (!file.existsSync()) {
      throw const CombinePdfException(CombinePdfFailure.missingSource);
    }
    size = file.lengthSync();
  } on FileSystemException {
    throw const CombinePdfException(CombinePdfFailure.missingSource);
  }
  if (size <= 0) {
    throw const CombinePdfException(CombinePdfFailure.emptySource);
  }
  if (size > maxBytes) {
    throw const CombinePdfException(CombinePdfFailure.tooLargeSource);
  }
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    throw const CombinePdfException(CombinePdfFailure.missingSource);
  }
  final window = bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes;
  if (!_hasPdfHeader(window)) {
    throw const CombinePdfException(CombinePdfFailure.corruptSource,
        detail: 'header');
  }
  final document = _open(bytes);
  try {
    final count = document.pages.count;
    if (count < 1) {
      throw const CombinePdfException(CombinePdfFailure.corruptSource,
          detail: 'pages');
    }
    for (var i = 0; i < count; i++) {
      final Size pageSize;
      try {
        pageSize = document.pages[i].size;
      } catch (_) {
        throw const CombinePdfException(CombinePdfFailure.corruptSource,
            detail: 'page');
      }
      if (pageSize.width <= 0 || pageSize.height <= 0) {
        throw const CombinePdfException(CombinePdfFailure.corruptSource,
            detail: 'page-size');
      }
    }
    return CombineAnalysis(
      size: size,
      pageCount: count,
      features: _detectFeatures(document),
    );
  } on CombinePdfException {
    rethrow;
  } catch (_) {
    throw const CombinePdfException(CombinePdfFailure.corruptSource,
        detail: 'read');
  } finally {
    document.dispose();
  }
}

bool _hasPdfHeader(Uint8List window) {
  const marker = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  for (var i = 0; i <= window.length - marker.length; i++) {
    var match = true;
    for (var j = 0; j < marker.length; j++) {
      if (window[i + j] != marker[j]) {
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
      throw const CombinePdfException(CombinePdfFailure.encryptedSource);
    }
    throw const CombinePdfException(CombinePdfFailure.corruptSource,
        detail: 'parse');
  } catch (_) {
    throw const CombinePdfException(CombinePdfFailure.corruptSource,
        detail: 'parse');
  }
  if (PdfDocumentHelper.getHelper(document).isEncrypted) {
    document.dispose();
    throw const CombinePdfException(CombinePdfFailure.encryptedSource);
  }
  return document;
}

CombineFeatures _detectFeatures(PdfDocument document) {
  var signed = false;
  var forms = false;
  final fields = document.form.fields;
  for (var i = 0; i < fields.count; i++) {
    final field = fields[i];
    if (field is PdfSignatureField && field.isSigned) {
      signed = true;
    } else {
      forms = true;
    }
  }
  var annotations = false;
  for (var i = 0; i < document.pages.count && !annotations; i++) {
    if (document.pages[i].annotations.count > 0) annotations = true;
  }
  return CombineFeatures(
    hasSignatures: signed,
    hasFormFields: forms,
    hasAnnotations: annotations,
    hasBookmarks: document.bookmarks.count > 0,
  );
}

/// What one page of the combined file must look like, known before it is
/// written.
class CombineExpectedPage {
  const CombineExpectedPage(this.size, this.rotation, this.fingerprint);

  final Size size;
  final int rotation;

  /// The first words of the page's text, or null when the page has none that
  /// could be read. Compared after the combine to prove the pages are in order.
  final String? fingerprint;
}

/// The first words of a page's text, or null when it has none that can be read.
@visibleForTesting
String? pageTextFingerprint(PdfTextExtractor extractor, int pageIndex) {
  try {
    final text = extractor
        .extractText(startPageIndex: pageIndex, endPageIndex: pageIndex)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    return text.length > 80 ? text.substring(0, 80) : text;
  } catch (_) {
    return null;
  }
}

/// Combines the pages of [job] into one PDF at [CombineMergeJob.outputPath].
///
/// All or nothing: the combined file is written only after every page was
/// copied, it is read back and checked (page count, each page's size and
/// rotation, and the text of each page against its source page), and any
/// failure leaves no output behind. A page is never skipped; a source that
/// changed, a page that cannot be read or a check that fails ends the combine.
///
/// Page content is copied with Syncfusion's `createTemplate`, which carries the
/// page's content stream and resources: text stays selectable and searchable,
/// fonts stay embedded, and the page keeps its size and rotation. It does NOT
/// carry interactive structures, so form fields and annotations are flattened
/// onto the page first, and links and bookmarks are not kept (a signed source
/// is refused before this point). The sources are never written to.
///
/// [isCancelled] is checked between pages (on a worker isolate the caller
/// stops the isolate instead).
CombineMergeResult runCombineMerge(
  CombineMergeJob job, {
  bool Function()? isCancelled,
}) {
  final output = File(job.outputPath);
  PdfDocument? combined;
  PdfDocument? current;
  PdfTextExtractor? currentText;
  String? currentId;
  final byId = <String, CombineSource>{
    for (final source in job.sources) source.id: source,
  };
  final expected = <CombineExpectedPage>[];
  try {
    if (job.pages.isEmpty) {
      throw const CombinePdfException(CombinePdfFailure.noPages);
    }
    combined = PdfDocument();
    combined.pageSettings.margins.all = 0;
    for (final ref in job.pages) {
      if (isCancelled?.call() ?? false) {
        throw const CombinePdfException(CombinePdfFailure.cancelled);
      }
      final source = byId[ref.sourceId];
      if (source == null) {
        throw const CombinePdfException(CombinePdfFailure.mergeFailed,
            detail: 'source');
      }
      if (currentId != ref.sourceId) {
        current?.dispose();
        current = null;
        currentText = null;
        current = _openSource(source);
        currentText = PdfTextExtractor(current);
        currentId = ref.sourceId;
      }
      if (ref.pageIndex < 0 || ref.pageIndex >= current!.pages.count) {
        throw CombinePdfException(CombinePdfFailure.sourceChanged,
            sourceId: source.id);
      }
      final page = current.pages[ref.pageIndex];
      final size = page.size;
      final rotation = (page.rotation.index + ref.quarterTurns) % 4;
      final section = combined.sections!.add();
      section.pageSettings.margins.all = 0;
      section.pageSettings.orientation = size.width > size.height
          ? PdfPageOrientation.landscape
          : PdfPageOrientation.portrait;
      section.pageSettings.size = size;
      section.pageSettings.rotate = PdfPageRotateAngle.values[rotation];
      final target = section.pages.add();
      target.graphics.drawPdfTemplate(page.createTemplate(), Offset.zero, size);
      expected.add(CombineExpectedPage(
          size, rotation, pageTextFingerprint(currentText!, ref.pageIndex)));
    }
    current?.dispose();
    current = null;
    if (isCancelled?.call() ?? false) {
      throw const CombinePdfException(CombinePdfFailure.cancelled);
    }
    final List<int> bytes = combined.saveSync();
    combined.dispose();
    combined = null;
    try {
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw CombinePdfException(_isDiskFull(error)
          ? CombinePdfFailure.storageFull
          : CombinePdfFailure.writeFailed);
    }
    verifyCombineOutput(output, expected);
    return CombineMergeResult(
        pageCount: expected.length, size: output.lengthSync());
  } on CombinePdfException {
    _quietDelete(output);
    rethrow;
  } catch (_) {
    _quietDelete(output);
    throw const CombinePdfException(CombinePdfFailure.mergeFailed);
  } finally {
    current?.dispose();
    combined?.dispose();
  }
}

/// Opens a selected file for the combine, re-checking that it is still the file
/// the user selected, and flattens its form fields so their values stay on the
/// page (a page template does not carry fields).
PdfDocument _openSource(CombineSource source) {
  final file = File(source.path);
  final Uint8List bytes;
  try {
    if (!file.existsSync()) {
      throw CombinePdfException(CombinePdfFailure.missingSource,
          sourceId: source.id);
    }
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    throw CombinePdfException(CombinePdfFailure.missingSource,
        sourceId: source.id);
  }
  if (bytes.length != source.size) {
    throw CombinePdfException(CombinePdfFailure.sourceChanged,
        sourceId: source.id);
  }
  final PdfDocument document;
  try {
    document = _open(bytes);
  } on CombinePdfException catch (error) {
    throw CombinePdfException(error.kind,
        sourceId: source.id, detail: error.detail);
  }
  var handedOver = false;
  try {
    if (document.pages.count != source.pageCount) {
      throw CombinePdfException(CombinePdfFailure.sourceChanged,
          sourceId: source.id);
    }
    final features = _detectFeatures(document);
    if (features.hasSignatures) {
      throw CombinePdfException(CombinePdfFailure.signedSource,
          sourceId: source.id);
    }
    if (features.hasFormFields || features.hasAnnotations) {
      handedOver = true;
      return _flattened(document);
    }
    return document;
  } catch (_) {
    if (!handedOver) document.dispose();
    rethrow;
  }
}

/// Flattens the form fields and annotations of [document] and returns a fresh
/// document made from the result. Flattening only takes effect when the
/// document is saved (a page template made from the in-memory document would
/// still lack the field values), so the document is saved and read again. The
/// source file on disk is untouched; this is a copy in memory.
PdfDocument _flattened(PdfDocument document) {
  try {
    document.form.flattenAllFields();
    for (var i = 0; i < document.pages.count; i++) {
      document.pages[i].annotations.flattenAllAnnotations();
    }
    final bytes = Uint8List.fromList(document.saveSync());
    return _open(bytes);
  } finally {
    document.dispose();
  }
}

/// Reads the finished file back and checks it against: page count,
/// each page's size and rotation, and its text. Throws `outputInvalid`.
@visibleForTesting
void verifyCombineOutput(File output, List<CombineExpectedPage> expected) {
  final Uint8List bytes;
  try {
    bytes = output.readAsBytesSync();
  } on FileSystemException {
    throw const CombinePdfException(CombinePdfFailure.outputInvalid,
        detail: 'read');
  }
  final PdfDocument document;
  try {
    document = PdfDocument(inputBytes: bytes);
  } catch (_) {
    throw const CombinePdfException(CombinePdfFailure.outputInvalid,
        detail: 'parse');
  }
  try {
    if (document.pages.count != expected.length) {
      throw const CombinePdfException(CombinePdfFailure.outputInvalid,
          detail: 'count');
    }
    // Fields were flattened onto their pages; none may be left in the result.
    if (document.form.fields.count != 0) {
      throw const CombinePdfException(CombinePdfFailure.outputInvalid,
          detail: 'form');
    }
    final extractor = PdfTextExtractor(document);
    for (var i = 0; i < expected.length; i++) {
      final page = document.pages[i];
      final want = expected[i];
      final size = page.size;
      if ((size.width - want.size.width).abs() > 0.5 ||
          (size.height - want.size.height).abs() > 0.5 ||
          page.rotation.index != want.rotation) {
        throw const CombinePdfException(CombinePdfFailure.outputInvalid,
            detail: 'page');
      }
      final fingerprint = want.fingerprint;
      if (fingerprint != null &&
          pageTextFingerprint(extractor, i) != fingerprint) {
        throw const CombinePdfException(CombinePdfFailure.outputInvalid,
            detail: 'order');
      }
    }
  } on CombinePdfException {
    rethrow;
  } catch (_) {
    throw const CombinePdfException(CombinePdfFailure.outputInvalid,
        detail: 'check');
  } finally {
    document.dispose();
  }
}

void _quietDelete(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
