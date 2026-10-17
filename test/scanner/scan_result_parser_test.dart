import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';

ScannerFailure? failureOf(void Function() action) {
  try {
    action();
  } on ScannerException catch (e) {
    return e.kind;
  }
  return null;
}

void main() {
  group('a cancelled scan', () {
    test('is null for PDF and for images, never an empty result', () {
      expect(ScanResultParser.parse(null, expected: ExportFormat.pdf), isNull);
      expect(
          ScanResultParser.parse(null, expected: ExportFormat.images), isNull);
    });
  });

  group('PDF results', () {
    test('Android map: URI and the scanner\'s reported page count', () {
      final output = ScanResultParser.parse(
        <String, Object?>{
          'pdfUri': 'file:///data/user/0/x/files/mlkit_docscan_ui_client/a.pdf',
          'pageCount': 3,
        },
        expected: ExportFormat.pdf,
      ) as ScanPdfOutput;
      expect(output.source.kind, ScanSourceKind.file);
      expect(output.reportedPageCount, 3);
    });

    test('a content:// PDF is a content source, not a path', () {
      final output = ScanResultParser.parse(
        <String, Object?>{'pdfUri': 'content://media/external/file/12'},
        expected: ExportFormat.pdf,
      ) as ScanPdfOutput;
      expect(output.source.kind, ScanSourceKind.content);
      expect(output.source.uri, 'content://media/external/file/12');
      expect(output.reportedPageCount, isNull);
    });

    test('iPhone: a bare path string is the PDF', () {
      final output = ScanResultParser.parse('/var/mobile/Documents/a.pdf',
          expected: ExportFormat.pdf) as ScanPdfOutput;
      expect(output.source.kind, ScanSourceKind.file);
      expect(output.source.localPath, '/var/mobile/Documents/a.pdf');
    });

    test('a reported count of 0 or a non-number is not trusted', () {
      for (final bad in <Object?>[0, -2, '3', 2.5, null]) {
        final output = ScanResultParser.parse(
          <String, Object?>{'pdfUri': '/tmp/a.pdf', 'pageCount': bad},
          expected: ExportFormat.pdf,
        ) as ScanPdfOutput;
        expect(output.reportedPageCount, isNull, reason: '$bad');
      }
    });

    test('images where a PDF was asked for are refused, never cut to page 1',
        () {
      expect(
          failureOf(() => ScanResultParser.parse(
                <String>['/tmp/1.jpg', '/tmp/2.jpg'],
                expected: ExportFormat.pdf,
              )),
          ScannerFailure.wrongFormat);
      expect(
          failureOf(() => ScanResultParser.parse(
                <String, Object?>{
                  'images': <String>['/tmp/1.jpg']
                },
                expected: ExportFormat.pdf,
              )),
          ScannerFailure.wrongFormat);
    });

    test('a map without a PDF, a non-string URI and odd types are malformed',
        () {
      for (final raw in <Object?>[
        <String, Object?>{},
        <String, Object?>{'pdfUri': 12},
        <String, Object?>{'pdfUri': ''},
        42,
        true,
      ]) {
        expect(
            failureOf(
                () => ScanResultParser.parse(raw, expected: ExportFormat.pdf)),
            ScannerFailure.malformedResult,
            reason: '$raw');
      }
    });
  });

  group('image results', () {
    test('a list of paths keeps every page, in order', () {
      final output = ScanResultParser.parse(
        <String>['/tmp/p0.png', '/tmp/p1.png', '/tmp/p2.png'],
        expected: ExportFormat.images,
      ) as ScanImagesOutput;
      expect(output.sources.map((s) => s.uri),
          <String>['/tmp/p0.png', '/tmp/p1.png', '/tmp/p2.png']);
    });

    test('Android map: images and count', () {
      final output = ScanResultParser.parse(
        <String, Object?>{
          'images': <String>['file:///a/1.jpg', 'file:///a/2.jpg'],
          'count': 2,
        },
        expected: ExportFormat.images,
      ) as ScanImagesOutput;
      expect(output.sources, hasLength(2));
      expect(output.reportedCount, 2);
    });

    test('older key names Uri and Count are still understood', () {
      final output = ScanResultParser.parse(
        <String, Object?>{
          'Uri': <String>[
            'file:///a/1.jpg',
            'file:///a/2.jpg',
            'file:///a/3.jpg'
          ],
          'Count': 3,
        },
        expected: ExportFormat.images,
      ) as ScanImagesOutput;
      expect(output.sources, hasLength(3));
      expect(output.reportedCount, 3);
    });

    test('content:// pages stay content sources, in order', () {
      final output = ScanResultParser.parse(
        <String, Object?>{
          'images': <String>[
            'content://media/1',
            'file:///a/2.jpg',
            'content://media/3'
          ],
        },
        expected: ExportFormat.images,
      ) as ScanImagesOutput;
      expect(output.sources.map((s) => s.kind), <ScanSourceKind>[
        ScanSourceKind.content,
        ScanSourceKind.file,
        ScanSourceKind.content,
      ]);
    });

    test('a single path string is one image page (it is not assumed a PDF)',
        () {
      final output =
          ScanResultParser.parse('/tmp/only.jpg', expected: ExportFormat.images)
              as ScanImagesOutput;
      expect(output.sources, hasLength(1));
    });

    test('a PDF where images were asked for is refused', () {
      expect(
          failureOf(() => ScanResultParser.parse(
                <String, Object?>{'pdfUri': '/tmp/a.pdf', 'pageCount': 2},
                expected: ExportFormat.images,
              )),
          ScannerFailure.wrongFormat);
    });

    test('an empty list and an empty map are an empty scan', () {
      expect(
          failureOf(() => ScanResultParser.parse(<String>[],
              expected: ExportFormat.images)),
          ScannerFailure.emptyOutput);
      expect(
          failureOf(() => ScanResultParser.parse(
                <String, Object?>{'images': <String>[]},
                expected: ExportFormat.images,
              )),
          ScannerFailure.emptyOutput);
    });

    test('one bad entry fails the whole scan instead of dropping a page', () {
      for (final bad in <Object?>[
        null,
        7,
        '',
        'https://example.com/a.jpg',
        'data:image/png;base64,AAAA',
        'relative/page.jpg',
      ]) {
        expect(
            failureOf(() => ScanResultParser.parse(
                  <Object?>['/tmp/ok.jpg', bad],
                  expected: ExportFormat.images,
                )),
            ScannerFailure.malformedResult,
            reason: '$bad');
      }
    });
  });

  group('sources', () {
    test('a file:// URI is decoded to the real path (spaces, %20)', () {
      final dir = Directory.systemTemp.createTempSync('bw_src');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'My Scan 1.pdf'))
        ..writeAsBytesSync([1]);
      final source = ScanSource.parse(file.uri.toString());
      expect(source.kind, ScanSourceKind.file);
      expect(source.localPath, file.path);
    });

    test('a content URI is never turned into a path by cutting its prefix', () {
      final source = ScanSource.parse('content://com.example/doc/9');
      expect(source.kind, ScanSourceKind.content);
      expect(source.localPath, 'content://com.example/doc/9');
    });

    test('POSIX and drive-letter absolute paths are accepted as files', () {
      expect(ScanSource.parse('/data/a.pdf').kind, ScanSourceKind.file);
      expect(ScanSource.parse(r'C:\data\a.pdf').kind, ScanSourceKind.file);
    });
  });
}
