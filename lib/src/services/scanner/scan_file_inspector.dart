import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';

/// Counts the pages of a PDF from its own bytes. Throws for a file that is not
/// a readable PDF.
abstract interface class PdfPageCounter {
  int countPages(Uint8List bytes);
}

/// What a scanner file proved to be, from the file itself.
class InspectedScanFile {
  const InspectedScanFile({
    required this.kind,
    required this.size,
    required this.pageCount,
    this.width,
    this.height,
  });

  final ScanFileKind kind;
  final int size;

  /// The PDF's real page count; 1 for an image.
  final int pageCount;
  final int? width;
  final int? height;
}

/// Decides what a file is by reading it, never by trusting its name, its URI or
/// a page count someone reported. A PDF must carry its header and end marker
/// and parse with at least one page; a JPEG or PNG must carry its signature,
/// real dimensions and its end marker, which a half-written file lacks. Images
/// are checked from their first and last bytes only, so a large photo is never
/// loaded whole.
class ScanFileInspector {
  const ScanFileInspector({
    required this.pdfPages,
    this.maxBytes = 64 * 1024 * 1024,
  });

  final PdfPageCounter pdfPages;

  /// The largest file the Scanner opens.
  final int maxBytes;

  /// Throws a [ScannerException] (`missingOutput`, `emptyOutput`, `tooLarge`
  /// or `corruptOutput`) unless [file] is a complete PDF or JPEG/PNG.
  Future<InspectedScanFile> inspect(File file) async {
    final int size;
    try {
      if (!await file.exists()) {
        throw const ScannerException(ScannerFailure.missingOutput);
      }
      size = await file.length();
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.missingOutput);
    }
    if (size <= 0) throw const ScannerException(ScannerFailure.emptyOutput);
    if (size > maxBytes) throw const ScannerException(ScannerFailure.tooLarge);

    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.missingOutput);
    }
    try {
      final headLength = size < 65536 ? size : 65536;
      final head = await _readAt(handle, 0, headLength);
      final tailLength = size < 2048 ? size : 2048;
      final tail = await _readAt(handle, size - tailLength, tailLength);

      if (_isPdf(head)) {
        return await _inspectPdf(file, size, tail);
      }
      if (_startsWith(head, const <int>[0xFF, 0xD8, 0xFF])) {
        return _inspectJpeg(size, head, tail);
      }
      if (_startsWith(
          head, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
        return _inspectPng(size, head, tail);
      }
      throw const ScannerException(ScannerFailure.corruptOutput, 'type');
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.corruptOutput, 'read');
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> _readAt(
      RandomAccessFile handle, int from, int length) async {
    await handle.setPosition(from);
    return handle.read(length);
  }

  bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  int _indexOf(Uint8List bytes, List<int> pattern, {int from = 0}) {
    for (var i = from; i <= bytes.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  bool _isPdf(Uint8List head) {
    // The PDF header may follow a few bytes of junk, but not far into the file.
    final window = head.length > 1024 ? head.sublist(0, 1024) : head;
    return _indexOf(window, const <int>[0x25, 0x50, 0x44, 0x46, 0x2D]) >= 0;
  }

  Future<InspectedScanFile> _inspectPdf(
      File file, int size, Uint8List tail) async {
    // `%%EOF` ends every complete PDF; a file cut short does not have it.
    if (_indexOf(tail, const <int>[0x25, 0x25, 0x45, 0x4F, 0x46]) < 0) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'pdf-end');
    }
    final int pages;
    try {
      pages = pdfPages.countPages(await file.readAsBytes());
    } on ScannerException {
      rethrow;
    } catch (_) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'pdf-parse');
    }
    if (pages < 1) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'pdf-pages');
    }
    return InspectedScanFile(
        kind: ScanFileKind.pdf, size: size, pageCount: pages);
  }

  InspectedScanFile _inspectJpeg(int size, Uint8List head, Uint8List tail) {
    // A complete JPEG ends with the EOI marker (some cameras pad after it).
    final end = tail.length > 64 ? tail.sublist(tail.length - 64) : tail;
    if (_indexOf(end, const <int>[0xFF, 0xD9]) < 0) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'jpeg-end');
    }
    var i = 2;
    while (i + 9 < head.length) {
      if (head[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = head[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0x01) {
        i += 2;
        continue;
      }
      final length = (head[i + 2] << 8) | head[i + 3];
      final isFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        final height = (head[i + 5] << 8) | head[i + 6];
        final width = (head[i + 7] << 8) | head[i + 8];
        if (width < 1 || height < 1) break;
        return InspectedScanFile(
          kind: ScanFileKind.jpeg,
          size: size,
          pageCount: 1,
          width: width,
          height: height,
        );
      }
      if (length < 2) break;
      i += 2 + length;
    }
    throw const ScannerException(ScannerFailure.corruptOutput, 'jpeg-frame');
  }

  InspectedScanFile _inspectPng(int size, Uint8List head, Uint8List tail) {
    // IHDR is the first chunk: length 13, name, width, height.
    if (head.length < 24 ||
        _indexOf(head.sublist(12, 16), const <int>[0x49, 0x48, 0x44, 0x52]) !=
            0) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'png-header');
    }
    int u32(int at) =>
        (head[at] << 24) |
        (head[at + 1] << 16) |
        (head[at + 2] << 8) |
        head[at + 3];
    final width = u32(16);
    final height = u32(20);
    if (width < 1 || height < 1) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'png-size');
    }
    // IEND is the last chunk: its name sits 8 bytes before the end of the file.
    if (tail.length < 12 ||
        _indexOf(tail.sublist(tail.length - 8, tail.length - 4),
                const <int>[0x49, 0x45, 0x4E, 0x44]) !=
            0) {
      throw const ScannerException(ScannerFailure.corruptOutput, 'png-end');
    }
    return InspectedScanFile(
      kind: ScanFileKind.png,
      size: size,
      pageCount: 1,
      width: width,
      height: height,
    );
  }
}
