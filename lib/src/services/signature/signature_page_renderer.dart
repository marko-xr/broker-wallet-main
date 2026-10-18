import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as pdfrx;
// An extension is not applied through a prefixed import, so the one the
// renderer needs (`PdfImage.createImage`) is imported by name as well.
import 'package:pdfrx/pdfrx.dart' show PdfImageExt;

import 'package:broker_wallet/src/services/signature/signature_models.dart';

/// Draws the pages of one PDF as bitmaps for the editor. The editor places its
/// overlays on top of these bitmaps in the page's own coordinates, so the
/// bitmap's size and the geometry the export uses must agree: the editor checks
/// the sizes returned by [open] against the file's own geometry and refuses a
/// file where they differ.
abstract interface class SignaturePageRenderer {
  /// Opens [path] and returns the visible size of every page. Throws a
  /// [SignatureException] (`encryptedSource`, `corruptSource`).
  Future<List<RenderedPageSize>> open(String path);

  /// Page [pageIndex] drawn [pixelWidth] pixels wide (the height follows the
  /// page), or null when it could not be drawn. The caller owns the image and
  /// disposes it.
  Future<ui.Image?> render(int pageIndex, {required int pixelWidth});

  /// Releases the document. Safe to call twice.
  Future<void> dispose();
}

/// PDFium (through pdfrx) draws the page exactly as a viewer does: boxes,
/// rotation, annotations and form fields included.
class PdfrxSignaturePageRenderer implements SignaturePageRenderer {
  pdfrx.PdfDocument? _document;
  bool _disposed = false;

  @override
  Future<List<RenderedPageSize>> open(String path) async {
    await pdfrx.pdfrxFlutterInitialize();
    final pdfrx.PdfDocument document;
    try {
      document = await pdfrx.PdfDocument.openFile(path);
    } on pdfrx.PdfPasswordException {
      throw const SignatureException(SignatureFailure.encryptedSource);
    } catch (_) {
      throw const SignatureException(SignatureFailure.corruptSource,
          detail: 'render-open');
    }
    if (_disposed) {
      await document.dispose();
      throw const SignatureException(SignatureFailure.cancelled);
    }
    _document = document;
    return <RenderedPageSize>[
      for (final page in document.pages)
        RenderedPageSize(page.width, page.height),
    ];
  }

  @override
  Future<ui.Image?> render(int pageIndex, {required int pixelWidth}) async {
    final document = _document;
    if (document == null ||
        pageIndex < 0 ||
        pageIndex >= document.pages.length) {
      return null;
    }
    final page = document.pages[pageIndex];
    final width = pixelWidth.toDouble();
    final height = page.height * width / page.width;
    try {
      final image = await page.render(fullWidth: width, fullHeight: height);
      if (image == null) return null;
      try {
        return await image.createImage();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final document = _document;
    _document = null;
    if (document != null) {
      try {
        await document.dispose();
      } catch (_) {}
    }
  }
}
