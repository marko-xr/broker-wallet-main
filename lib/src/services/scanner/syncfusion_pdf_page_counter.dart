import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';

/// The production [PdfPageCounter]: Syncfusion's PDF parser, already part of
/// the app. It reads the PDF's own page tree, so the count is the file's, not
/// anything a scanner reported.
class SyncfusionPdfPageCounter implements PdfPageCounter {
  const SyncfusionPdfPageCounter();

  @override
  int countPages(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return document.pages.count;
    } finally {
      document.dispose();
    }
  }
}
