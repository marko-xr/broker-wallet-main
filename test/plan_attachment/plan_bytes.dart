// Small byte fixtures for the plan tests: the leading bytes that make each
// accepted plan type recognizable, padded to a believable size. They test file
// sniffing, never decoding.

import 'dart:convert';
import 'dart:io';

List<int> _pad(List<int> head, int length) => <int>[
      ...head,
      ...List<int>.filled(length > head.length ? length - head.length : 0, 7),
    ];

List<int> planJpegBytes([int length = 256]) =>
    _pad(<int>[0xff, 0xd8, 0xff, 0xe0], length);

List<int> planPngBytes([int length = 256]) =>
    _pad(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], length);

List<int> planPdfBytes([int length = 256]) =>
    _pad(utf8.encode('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n'), length);

/// A legacy Word file's OLE2 compound-file header.
List<int> planDocBytes([int length = 256]) =>
    _pad(<int>[0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1], length);

/// The start of a ZIP local file header whose first entry is [firstEntry].
List<int> planZipBytes(String firstEntry, {int flags = 0, int length = 256}) {
  final name = utf8.encode(firstEntry);
  final out = List<int>.filled(30 + name.length + 16, 0);
  out.setRange(0, 4, <int>[0x50, 0x4b, 0x03, 0x04]);
  out[6] = flags;
  out[26] = name.length & 0xff;
  out[27] = name.length >> 8;
  out.setRange(30, 30 + name.length, name);
  return _pad(out, length);
}

/// An Office Open XML package: its first entry is the content-types part.
List<int> planDocxBytes([int length = 256]) =>
    planZipBytes('[Content_Types].xml', length: length);

/// An ISO base-media box with a HEIC brand: a photo the app converts to JPEG.
List<int> planHeicBytes([int length = 256]) => _pad(<int>[
      0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, // size, "ftyp"
      0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0, // "heic", minor version
      0x6d, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63, // "mif1", "heic"
    ], length);

/// A temporary folder that a test removes itself.
class PlanTempDir {
  PlanTempDir() : directory = Directory.systemTemp.createTempSync('plan_test_');

  final Directory directory;

  File write(String name, List<int> bytes) {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  String get path => directory.path;

  void dispose() {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
  }
}
