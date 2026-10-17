import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_engine.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

import 'scanner_fixtures.dart';

ScannerDocument sampleDoc({String name = 'Lease', String ext = 'pdf'}) =>
    ScannerDocument(
      id: 'id1',
      fileName: 'id1.$ext',
      name: name,
      scanType: ScanMode.document,
      format: ext == 'pdf' ? ExportFormat.pdf : ExportFormat.images,
      mimeType: ext == 'pdf' ? 'application/pdf' : 'image/jpeg',
      createdAt: DateTime.utc(2026, 10, 17),
      fileSize: 3,
      pageCount: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('the native scanner engine (flutter_doc_scanner 0.0.21)', () {
    const channel = MethodChannel('flutter_doc_scanner');
    final calls = <MethodCall>[];

    void answer(Future<Object?> Function(MethodCall call) handler) {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
        'PDF on Android: URI and the scanner\'s page count are passed on, and '
        'the page limit is the chosen one', () async {
      answer((call) async => <String, Object?>{
            'pdfUri': 'file:///files/mlkit_docscan_ui_client/a.pdf',
            'pageCount': 3,
          });
      final raw = await FlutterDocScannerEngine()
          .scan(format: ExportFormat.pdf, maxPages: 7);
      expect(raw, <String, Object?>{
        'pdfUri': 'file:///files/mlkit_docscan_ui_client/a.pdf',
        'pageCount': 3,
      });
      expect(calls.single.method, 'getScannedDocumentAsPdf');
      expect((calls.single.arguments as Map)['page'], 7);
      final parsed = ScanResultParser.parse(raw, expected: ExportFormat.pdf)
          as ScanPdfOutput;
      expect(parsed.reportedPageCount, 3);
    });

    test('PDF on iPhone: a bare path has no page count to report', () async {
      answer((call) async => '/var/mobile/Documents/20261017-101010.pdf');
      final raw = await FlutterDocScannerEngine()
          .scan(format: ExportFormat.pdf, maxPages: 5);
      expect(raw, <String, Object?>{
        'pdfUri': '/var/mobile/Documents/20261017-101010.pdf',
      });
    });

    test('images on Android (map) and on iPhone (list) both give every page',
        () async {
      answer((call) async => <String, Object?>{
            'images': <String>['file:///a/1.jpg', 'file:///a/2.jpg'],
            'count': 2,
            'Uri': <String>['file:///a/1.jpg', 'file:///a/2.jpg'],
            'Count': 2,
          });
      var raw = await FlutterDocScannerEngine()
          .scan(format: ExportFormat.images, maxPages: 5);
      expect(raw, <String, Object?>{
        'images': <String>['file:///a/1.jpg', 'file:///a/2.jpg'],
      });
      expect(calls.single.method, 'getScannedDocumentAsImages');

      answer((call) async => <String>['/d/0.png', '/d/1.png', '/d/2.png']);
      raw = await FlutterDocScannerEngine()
          .scan(format: ExportFormat.images, maxPages: 5);
      expect(
          (raw as Map)['images'], <String>['/d/0.png', '/d/1.png', '/d/2.png']);
    });

    test('a cancelled scan is null, whichever way the plugin says it',
        () async {
      answer((call) async => null);
      expect(
          await FlutterDocScannerEngine()
              .scan(format: ExportFormat.pdf, maxPages: 5),
          isNull);
      answer((call) async => throw PlatformException(code: 'CANCELLED'));
      expect(
          await FlutterDocScannerEngine()
              .scan(format: ExportFormat.images, maxPages: 5),
          isNull);
    });

    test('plugin errors become scanner failures without platform text',
        () async {
      Future<ScannerFailure?> kindFor(PlatformException error) async {
        answer((call) async => throw error);
        try {
          await FlutterDocScannerEngine()
              .scan(format: ExportFormat.pdf, maxPages: 5);
        } on ScannerException catch (e) {
          return e.kind;
        }
        return null;
      }

      expect(
          await kindFor(PlatformException(
              code: 'SCAN_FAILED', message: '/data/user/0/secret/path.pdf')),
          ScannerFailure.engineFailed);
      expect(await kindFor(PlatformException(code: 'SCAN_IN_PROGRESS')),
          ScannerFailure.busy);
      expect(await kindFor(PlatformException(code: 'NO_ACTIVITY')),
          ScannerFailure.engineFailed);
      expect(await kindFor(PlatformException(code: 'SCAN_ERROR')),
          ScannerFailure.engineFailed);
    });

    test('a PDF answer with no URI is a malformed result', () async {
      answer((call) async => <String, Object?>{'pageCount': 2});
      await expectLater(
          FlutterDocScannerEngine().scan(format: ExportFormat.pdf, maxPages: 5),
          throwsA(isA<ScannerException>()
              .having((e) => e.kind, 'kind', ScannerFailure.malformedResult)));
    });
  });

  group('exporting a document', () {
    const channel = MethodChannel('file_saver');
    final calls = <MethodCall>[];
    late Directory dir;
    late File stored;

    setUp(() async {
      calls.clear();
      dir = makeTempDir('export');
      stored = await writeFile(dir, 'id1.pdf', await pdfBytes(1));
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });

    void answer(Future<Object?> Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    PlatformScannerExporter android({
      int sdk = 34,
      bool permission = true,
      List<String>? asked,
    }) =>
        PlatformScannerExporter(
          isAndroid: true,
          androidSdk: () async => sdk,
          requestLegacyStoragePermission: () async {
            asked?.add('storage');
            return permission;
          },
          saveToFiles: (name, bytes) async =>
              fail('Files sheet is iPhone only'),
        );

    test(
        'Android 10+: streams the file by path to Downloads, with no byte '
        'array and no storage permission', () async {
      final asked = <String>[];
      answer((call) async => <String, Object?>{
            'success': true,
            'uri': 'content://media/external/downloads/9',
            'displayName': 'Lease (1).pdf',
          });
      final result = await android(asked: asked).export(sampleDoc(), stored);
      expect(result.destination, ScannerExportDestination.downloads);
      expect(result.savedName, 'Lease (1).pdf',
          reason: 'the name the phone really used is reported');
      expect(asked, isEmpty);
      expect(calls.single.method, 'exportFileToDownloads');
      final args = calls.single.arguments as Map;
      expect(args['sourcePath'], stored.path);
      expect(args['fileName'], 'Lease.pdf');
      expect(args['mimeType'], 'application/pdf');
      expect(args.containsKey('fileBytes'), isFalse);
    });

    test(
        'Android 9 and below ask for the legacy storage permission first, '
        'and stop when it is refused', () async {
      final asked = <String>[];
      answer((call) async => <String, Object?>{
            'success': true,
            'displayName': 'Lease.pdf',
          });
      await android(sdk: 28, asked: asked).export(sampleDoc(), stored);
      expect(asked, <String>['storage']);

      calls.clear();
      await expectLater(
          android(sdk: 26, permission: false).export(sampleDoc(), stored),
          throwsA(isA<ScannerException>()
              .having((e) => e.kind, 'kind', ScannerFailure.permissionDenied)));
      expect(calls, isEmpty, reason: 'nothing was written');
    });

    test('a reply that is not a clear success is a failure, never "saved"',
        () async {
      for (final reply in <Object?>[
        null,
        <String, Object?>{'success': false},
        <String, Object?>{'success': true},
        'ok',
      ]) {
        answer((call) async => reply);
        await expectLater(
            android().export(sampleDoc(), stored),
            throwsA(isA<ScannerException>()
                .having((e) => e.kind, 'kind', ScannerFailure.exportFailed)),
            reason: '$reply');
      }
    });

    test('native errors map to storage full, permission and export failures',
        () async {
      Future<ScannerFailure> kindFor(String code) async {
        answer((call) async => throw PlatformException(code: code));
        try {
          await android().export(sampleDoc(), stored);
        } on ScannerException catch (e) {
          return e.kind;
        }
        throw StateError('no error');
      }

      expect(await kindFor('STORAGE_FULL'), ScannerFailure.storageFull);
      expect(
          await kindFor('PERMISSION_DENIED'), ScannerFailure.permissionDenied);
      expect(await kindFor('EXPORT_FAILED'), ScannerFailure.exportFailed);
      expect(await kindFor('SOURCE_INVALID'), ScannerFailure.exportFailed);
    });

    test(
        'iPhone: the Files sheet gets the file under its title; closing it is '
        'a cancel, not a save', () async {
      String? gotName;
      Uint8List? gotBytes;
      final saved = PlatformScannerExporter(
        isAndroid: false,
        androidSdk: () async => fail('not Android'),
        requestLegacyStoragePermission: () async => fail('not Android'),
        saveToFiles: (name, bytes) async {
          gotName = name;
          gotBytes = bytes;
          return '/private/var/mobile/Containers/Lease.pdf';
        },
      );
      final result = await saved.export(sampleDoc(), stored);
      expect(result.destination, ScannerExportDestination.files);
      expect(result.savedName, 'Lease.pdf');
      expect(gotName, 'Lease.pdf');
      expect(gotBytes, await stored.readAsBytes());
      expect(calls, isEmpty, reason: 'no Android channel on iPhone');

      final closed = PlatformScannerExporter(
        isAndroid: false,
        androidSdk: () async => 0,
        requestLegacyStoragePermission: () async => false,
        saveToFiles: (name, bytes) async => null,
      );
      expect((await closed.export(sampleDoc(), stored)).cancelled, isTrue);
    });

    test('the content-URI reader copies through the platform', () async {
      answer((call) async => <String, Object?>{'success': true, 'bytes': 5});
      await PlatformContentUriReader()
          .copyContentUri('content://media/1', File('${dir.path}/page.tmp'));
      expect(calls.single.method, 'copyContentUriToFile');
      expect((calls.single.arguments as Map)['uri'], 'content://media/1');

      answer((call) async => <String, Object?>{'success': false});
      await expectLater(
          PlatformContentUriReader().copyContentUri(
              'content://media/1', File('${dir.path}/page.tmp')),
          throwsA(isA<FileSystemException>()));
    });
  });
}
