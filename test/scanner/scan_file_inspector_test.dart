import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/syncfusion_pdf_page_counter.dart';

import 'scanner_fixtures.dart';

Future<ScannerFailure?> failureOf(Future<Object?> Function() action) async {
  try {
    await action();
  } on ScannerException catch (e) {
    return e.kind;
  }
  return null;
}

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir('inspect'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('PDF files', () {
    test('page count comes from the file: 1 page and 3 pages', () async {
      final one = await writeFile(dir, 'one.pdf', await pdfBytes(1));
      final three = await writeFile(dir, 'three.pdf', await pdfBytes(3));
      final inspector = testInspector();
      expect((await inspector.inspect(one)).pageCount, 1);
      final result = await inspector.inspect(three);
      expect(result.kind, ScanFileKind.pdf);
      expect(result.pageCount, 3);
      expect(result.size, await three.length());
    });

    test('the real Syncfusion counter agrees on 1, 3 and 5 pages', () async {
      const inspector = ScanFileInspector(pdfPages: SyncfusionPdfPageCounter());
      for (final pages in <int>[1, 3, 5]) {
        final file = await writeFile(dir, 'p$pages.pdf', await pdfBytes(pages));
        expect((await inspector.inspect(file)).pageCount, pages);
      }
    });

    test('a PDF cut short is corrupt, never a smaller success', () async {
      final bytes = await pdfBytes(3);
      final cut = await writeFile(
          dir, 'cut.pdf', bytes.sublist(0, (bytes.length * 0.6).floor()));
      expect(await failureOf(() => testInspector().inspect(cut)),
          ScannerFailure.corruptOutput);
    });

    test('text called .pdf is corrupt, whatever its name says', () async {
      final fake =
          await writeFile(dir, 'fake.pdf', 'not a pdf at all'.codeUnits);
      expect(await failureOf(() => testInspector().inspect(fake)),
          ScannerFailure.corruptOutput);
    });

    test('a PDF that its parser cannot read is corrupt', () async {
      final bytes = Uint8List.fromList(
          '%PDF-1.4\nnothing useful here\n%%EOF\n'.codeUnits);
      final file = await writeFile(dir, 'bad.pdf', bytes);
      expect(await failureOf(() => testInspector().inspect(file)),
          ScannerFailure.corruptOutput);
    });
  });

  group('image files', () {
    test('a JPEG proves its kind and size, whatever the name', () async {
      final file =
          await writeFile(dir, 'scan.pdf', jpegBytes(width: 40, height: 30));
      final result = await testInspector().inspect(file);
      expect(result.kind, ScanFileKind.jpeg);
      expect(result.pageCount, 1);
      expect(result.width, 40);
      expect(result.height, 30);
    });

    test('a PNG proves its kind and size', () async {
      final file =
          await writeFile(dir, 'scan.png', pngBytes(width: 20, height: 10));
      final result = await testInspector().inspect(file);
      expect(result.kind, ScanFileKind.png);
      expect(result.width, 20);
      expect(result.height, 10);
    });

    test('a truncated JPEG and a truncated PNG are corrupt', () async {
      final jpeg = jpegBytes();
      final png = pngBytes();
      final cutJpeg =
          await writeFile(dir, 'cut.jpg', jpeg.sublist(0, jpeg.length - 6));
      final cutPng =
          await writeFile(dir, 'cut.png', png.sublist(0, png.length - 20));
      expect(await failureOf(() => testInspector().inspect(cutJpeg)),
          ScannerFailure.corruptOutput);
      expect(await failureOf(() => testInspector().inspect(cutPng)),
          ScannerFailure.corruptOutput);
    });

    test('a file with an image signature but no frame is corrupt', () async {
      final file = await writeFile(dir, 'odd.jpg',
          <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xD9]);
      expect(await failureOf(() => testInspector().inspect(file)),
          ScannerFailure.corruptOutput);
    });
  });

  group('files that cannot be used', () {
    test('missing, empty and oversized files are told apart', () async {
      final empty = await writeFile(dir, 'empty.pdf', <int>[]);
      expect(await failureOf(() => testInspector().inspect(empty)),
          ScannerFailure.emptyOutput);
      expect(
          await failureOf(
              () => testInspector().inspect(File('${dir.path}/nope.pdf'))),
          ScannerFailure.missingOutput);
      final big =
          await writeFile(dir, 'big.jpg', jpegBytes(width: 64, height: 64));
      expect(await failureOf(() => testInspector(maxBytes: 100).inspect(big)),
          ScannerFailure.tooLarge);
    });

    test('a folder is not a file', () async {
      expect(await failureOf(() => testInspector().inspect(File(dir.path))),
          isNotNull);
    });
  });
}
