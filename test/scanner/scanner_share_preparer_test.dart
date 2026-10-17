import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scanner_share_preparer.dart';

import 'scanner_fixtures.dart';

ScannerDocument doc(String id, String name, String ext) => ScannerDocument(
      id: id,
      fileName: '$id.$ext',
      name: name,
      scanType: ScanMode.document,
      format: ext == 'pdf' ? ExportFormat.pdf : ExportFormat.images,
      mimeType: ext == 'pdf' ? 'application/pdf' : 'image/jpeg',
      createdAt: DateTime.utc(2026, 10, 17),
      fileSize: 1,
      pageCount: 1,
    );

void main() {
  late Directory temp;
  late Directory stored;

  setUp(() {
    temp = makeTempDir('share_tmp');
    stored = makeTempDir('share_src');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
    stored.deleteSync(recursive: true);
  });

  test('a shared copy carries the document title, never the internal id',
      () async {
    final file = await writeFile(stored, 'id-9f3.pdf', await pdfBytes(1));
    final preparer = ScannerSharePreparer(tempRoot: () async => temp);
    final paths = await preparer
        .prepare([(document: doc('id-9f3', 'عقد إيجار', 'pdf'), file: file)]);
    expect(paths, hasLength(1));
    expect(p.basename(paths.single), 'عقد إيجار.pdf');
    expect(paths.single.contains('id-9f3'), isFalse);
    expect(await File(paths.single).length(), await file.length());
    expect(file.existsSync(), isTrue, reason: 'the stored file is untouched');
  });

  test('several documents keep their order and get distinct names', () async {
    final a = await writeFile(stored, 'a.pdf', await pdfBytes(1));
    final b = await writeFile(stored, 'b.pdf', await pdfBytes(2));
    final preparer = ScannerSharePreparer(tempRoot: () async => temp);
    // Two documents that would export under the same file name.
    final paths = await preparer.prepare([
      (document: doc('a', 'Plan', 'pdf'), file: a),
      (document: doc('b', 'plan', 'pdf'), file: b),
    ]);
    expect(
        paths.map(p.basename).toList(), <String>['Plan.pdf', 'plan (2).pdf']);
  });

  test('a failed copy leaves no share folder behind', () async {
    final preparer = ScannerSharePreparer(tempRoot: () async => temp);
    await expectLater(
      preparer.prepare([
        (
          document: doc('x', 'Missing', 'pdf'),
          file: File(p.join(stored.path, 'nope.pdf'))
        ),
      ]),
      throwsA(isA<FileSystemException>()),
    );
    expect(relativeFiles(temp), isEmpty);
    final root = Directory(p.join(temp.path, 'scanner_share'));
    expect(root.existsSync() ? root.listSync() : <FileSystemEntity>[], isEmpty);
  });

  test('stale share folders are swept; recent ones are kept', () async {
    final file = await writeFile(stored, 'a.pdf', await pdfBytes(1));
    final preparer = ScannerSharePreparer(tempRoot: () async => temp);
    final paths = await preparer
        .prepare([(document: doc('a', 'Fresh', 'pdf'), file: file)]);
    final fresh = Directory(p.dirname(paths.single));
    final stale = Directory(p.join(temp.path, 'scanner_share', 'old'))
      ..createSync(recursive: true);
    File(p.join(stale.path, 'Old.pdf')).writeAsBytesSync(<int>[1]);

    await preparer.sweepStale(
        now: DateTime.now().add(const Duration(minutes: 5)));
    expect(fresh.existsSync(), isTrue);
    expect(stale.existsSync(), isTrue);

    await preparer.sweepStale(
        now: DateTime.now().add(const Duration(hours: 3)));
    expect(fresh.existsSync(), isFalse);
    expect(stale.existsSync(), isFalse);
  });
}
