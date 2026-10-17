import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';

/// Counts the page objects in a PDF made by the `pdf` package. A stand-in for
/// the Syncfusion parser so most tests need no PDF library of their own; one
/// test runs the real Syncfusion counter against the same files.
class CountingPdfPageCounter implements PdfPageCounter {
  const CountingPdfPageCounter();

  @override
  int countPages(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final pages = RegExp(r'/Type\s*/Page(?![A-Za-z])').allMatches(text).length;
    if (pages == 0) throw const FormatException('no pages');
    return pages;
  }
}

ScanFileInspector testInspector({int maxBytes = 64 * 1024 * 1024}) =>
    ScanFileInspector(
        pdfPages: const CountingPdfPageCounter(), maxBytes: maxBytes);

/// A real PDF of [pages] pages.
Future<Uint8List> pdfBytes(int pages) async {
  final document = pw.Document();
  for (var i = 1; i <= pages; i++) {
    document.addPage(pw.Page(
      build: (context) => pw.Center(child: pw.Text('Page $i')),
    ));
  }
  return document.save();
}

/// A real JPEG. [seed] changes the pixels so two pages differ.
Uint8List jpegBytes({int width = 16, int height = 12, int seed = 0}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(40 + seed * 20, 90, 160));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

/// A real PNG.
Uint8List pngBytes({int width = 16, int height = 12, int seed = 0}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 40 + seed * 20, 90));
  return Uint8List.fromList(img.encodePng(image));
}

Future<File> writeFile(Directory dir, String name, List<int> bytes) async {
  final file = File(p.join(dir.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// A fresh, empty temporary folder.
Directory makeTempDir(String prefix) =>
    Directory.systemTemp.createTempSync('bw_scanner_$prefix');

/// Lists every file under [dir] as paths relative to it, sorted.
List<String> relativeFiles(Directory dir) {
  if (!dir.existsSync()) return <String>[];
  final names = <String>[
    for (final item in dir.listSync(recursive: true, followLinks: false))
      if (item is File) p.relative(item.path, from: dir.path),
  ];
  names.sort();
  return names;
}
