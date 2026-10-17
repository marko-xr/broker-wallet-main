import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';

import 'scanner_fixtures.dart';

class FakeContentReader implements ContentUriReader {
  FakeContentReader({this.bytes, this.error});

  final List<int>? bytes;
  final Object? error;
  final List<String> requested = <String>[];

  @override
  Future<void> copyContentUri(String uri, File destination) async {
    requested.add(uri);
    if (error != null) {
      // A half-written destination, as a dying copy would leave.
      await destination.writeAsBytes(<int>[1, 2, 3]);
      throw error!;
    }
    await destination.writeAsBytes(bytes!);
  }
}

Future<ScannerFailure?> stageFailure(
    ScanSourceStager stager, ScanSource source) async {
  try {
    await stager.stage(source, operationId: 'op', index: 0);
  } on ScannerException catch (e) {
    return e.kind;
  }
  return null;
}

void main() {
  late Directory root;
  late Directory trusted;
  late Directory outside;
  late Directory store;
  late Directory output;
  late Directory staging;

  ScanSourceStager build({ContentUriReader? reader, Directory? flat}) {
    return ScanSourceStager(
      roots: () async => ScannerRoots(
        stagingDir: staging,
        trusted: <Directory>[trusted],
        denied: <Directory>[store],
        scannerOutputDirs: <Directory>[output],
        scannerOutputFlatDirs: flat == null ? <Directory>[] : <Directory>[flat],
      ),
      contentReader: reader,
    );
  }

  setUp(() {
    root = makeTempDir('stager');
    trusted = Directory(p.join(root.path, 'trusted'))..createSync();
    outside = Directory(p.join(root.path, 'outside'))..createSync();
    store = Directory(p.join(trusted.path, 'scanner'))..createSync();
    output = Directory(p.join(trusted.path, 'mlkit'))..createSync();
    staging = Directory(p.join(root.path, 'staging'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('file sources', () {
    test('a file inside a trusted folder is read in place (file:// and path)',
        () async {
      final file = await writeFile(output, 'a b.pdf', await pdfBytes(1));
      final stager = build();
      final viaUri = await stager.stage(ScanSource.parse(file.uri.toString()),
          operationId: 'op', index: 0);
      final viaPath = await stager.stage(ScanSource.parse(file.path),
          operationId: 'op', index: 0);
      expect(viaUri.file.existsSync(), isTrue);
      expect(viaUri.isTemporaryCopy, isFalse);
      expect(viaUri.isScannerOutput, isTrue);
      expect(await viaPath.file.length(), await file.length());
    });

    test('a path outside every trusted folder is refused and never opened',
        () async {
      final stray = await writeFile(outside, 'secret.pdf', await pdfBytes(1));
      expect(await stageFailure(build(), ScanSource.parse(stray.path)),
          ScannerFailure.untrustedSource);
    });

    test('.. segments cannot climb out of a trusted folder', () async {
      final stray = await writeFile(outside, 'secret.pdf', await pdfBytes(1));
      final sneaky = p.join(trusted.path, '..', 'outside', 'secret.pdf');
      expect(await stageFailure(build(), ScanSource.parse(sneaky)),
          ScannerFailure.untrustedSource);
      expect(stray.existsSync(), isTrue);
    });

    test('the Scanner\'s own store is never a scan source', () async {
      final own = await writeFile(store, 'u/files/id.pdf', await pdfBytes(1));
      expect(await stageFailure(build(), ScanSource.parse(own.path)),
          ScannerFailure.untrustedSource);
    });

    test('a missing file and a folder are reported as missing', () async {
      expect(
          await stageFailure(
              build(), ScanSource.parse(p.join(trusted.path, 'gone.pdf'))),
          ScannerFailure.missingOutput);
      expect(await stageFailure(build(), ScanSource.parse(output.path)),
          ScannerFailure.missingOutput);
    });
  });

  group('content sources', () {
    test('are copied through the platform into the staging folder', () async {
      final reader = FakeContentReader(bytes: await pdfBytes(2));
      final stager = build(reader: reader);
      final staged = await stager.stage(ScanSource.parse('content://media/42'),
          operationId: 'op', index: 3);
      expect(reader.requested, <String>['content://media/42']);
      expect(staged.isTemporaryCopy, isTrue);
      expect(staged.file.path.startsWith(staging.path), isTrue);
      expect(await staged.file.length(), greaterThan(0));
      await stager.release(staged);
      expect(staged.file.existsSync(), isFalse);
    });

    test('a failed copy leaves no half-written file and is reported', () async {
      final reader = FakeContentReader(error: const FileSystemException('x'));
      final stager = build(reader: reader);
      expect(await stageFailure(stager, ScanSource.parse('content://media/1')),
          ScannerFailure.missingOutput);
      expect(relativeFiles(staging), isEmpty);
    });

    test('a full disk during the copy is reported as storage full', () async {
      final reader = FakeContentReader(
          error: const FileSystemException('x', '', OSError('No space', 28)));
      expect(
          await stageFailure(
              build(reader: reader), ScanSource.parse('content://media/1')),
          ScannerFailure.storageFull);
    });

    test('without a platform reader a content URI is refused', () async {
      expect(await stageFailure(build(), ScanSource.parse('content://media/1')),
          ScannerFailure.untrustedSource);
    });
  });

  group('cleanup', () {
    test('only the scanner\'s own output is deleted after use', () async {
      final scannerFile =
          await writeFile(output, 'scan.pdf', await pdfBytes(1));
      final other = await writeFile(trusted, 'keep.pdf', await pdfBytes(1));
      final stager = build();
      final a = await stager.stage(ScanSource.parse(scannerFile.path),
          operationId: 'op', index: 0);
      final b = await stager.stage(ScanSource.parse(other.path),
          operationId: 'op', index: 1);
      await stager.release(a);
      await stager.release(b);
      expect(scannerFile.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('date-named files directly in a flat scanner folder count as output',
        () async {
      final documents = Directory(p.join(trusted.path, 'docs'))..createSync();
      final scanned =
          await writeFile(documents, '20261017-143201-0.png', pngBytes());
      final legacy = await writeFile(
          documents, 'document_scan_20261017_1432.pdf', await pdfBytes(1));
      final stager = build(flat: documents);
      final a = await stager.stage(ScanSource.parse(scanned.path),
          operationId: 'op', index: 0);
      final b = await stager.stage(ScanSource.parse(legacy.path),
          operationId: 'op', index: 1);
      expect(a.isScannerOutput, isTrue);
      expect(b.isScannerOutput, isFalse);
      await stager.release(a);
      await stager.release(b);
      expect(scanned.existsSync(), isFalse);
      expect(legacy.existsSync(), isTrue);
    });

    test('releaseOperation removes the staging folder of one scan', () async {
      final reader = FakeContentReader(bytes: await pdfBytes(1));
      final stager = build(reader: reader);
      await stager.stage(ScanSource.parse('content://media/1'),
          operationId: 'op', index: 0);
      await stager.releaseOperation('op');
      expect(Directory(p.join(staging.path, 'op')).existsSync(), isFalse);
    });
  });
}
