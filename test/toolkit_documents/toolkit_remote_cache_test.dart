// The copy of the account's last document list (what lets a tool show its cards
// the moment its screen opens) and the internal diagnostics that keep a quiet
// failure findable. Neither is ever shown to a user, and neither may hold a
// signed URL, a storage key, a path or raw error text.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_diagnostics.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_remote_cache.dart';

import 'toolkit_fakes.dart';

ToolkitDocumentMetadata metadata(
  String id, {
  ToolkitDocumentType type = ToolkitDocumentType.scanner,
  String title = 'Lease',
}) =>
    ToolkitDocumentMetadata(
      documentId: id,
      type: type,
      contentType: ToolkitContentType.pdf,
      title: title,
      sizeBytes: 1234,
      pageCount: 2,
      contentSha256: 'c' * 64,
      sourceCreatedAt: DateTime.utc(2026, 10, 21, 19, 44, 40),
      createdAt: DateTime.utc(2026, 10, 21, 19, 45, 9),
      version: 3,
    );

void main() {
  group('FileToolkitRemoteCache', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('toolkit_cache_'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileToolkitRemoteCache cacheFor(String account) =>
        FileToolkitRemoteCache(directory: dir, accountId: account);

    File onlyFile() => dir.listSync().whereType<File>().single;

    test('nothing stored reads as nothing, never as an error', () async {
      expect(
          await cacheFor(accountA).read(ToolkitDocumentType.scanner), isEmpty);
    });

    test('gives back exactly what the Worker listed', () async {
      final cache = cacheFor(accountA);
      final listed = [metadata(doc1, title: 'Passport'), metadata(doc2)];
      await cache.write(ToolkitDocumentType.scanner, listed);
      expect(await cache.read(ToolkitDocumentType.scanner), listed);
      // Written again (a newer list) it replaces the old one, not adds to it.
      await cache.write(ToolkitDocumentType.scanner, [metadata(doc2)]);
      expect(await cache.read(ToolkitDocumentType.scanner), [metadata(doc2)]);
    });

    test('is kept per tool and per account', () async {
      await cacheFor(accountA)
          .write(ToolkitDocumentType.scanner, [metadata(doc1)]);
      expect(await cacheFor(accountA).read(ToolkitDocumentType.combinePdfs),
          isEmpty);
      expect(
          await cacheFor(accountB).read(ToolkitDocumentType.scanner), isEmpty);
    });

    test('a file of another account is never read as this one\'s', () async {
      await cacheFor(accountA)
          .write(ToolkitDocumentType.scanner, [metadata(doc1)]);
      final file = onlyFile();
      final other = File(file.path.replaceAll(accountA, accountB));
      await file.rename(other.path);
      expect(
          await cacheFor(accountB).read(ToolkitDocumentType.scanner), isEmpty,
          reason: 'the account named inside the file must match');
    });

    test('a damaged file is ignored, and the next list replaces it', () async {
      final cache = cacheFor(accountA);
      await cache.write(ToolkitDocumentType.scanner, [metadata(doc1)]);
      await onlyFile().writeAsString('{ not json');
      expect(await cache.read(ToolkitDocumentType.scanner), isEmpty);
      await cache.write(ToolkitDocumentType.scanner, [metadata(doc2)]);
      expect(await cache.read(ToolkitDocumentType.scanner), [metadata(doc2)]);
    });

    test('one entry that no longer fits the contract is dropped alone',
        () async {
      final cache = cacheFor(accountA);
      await cache.write(ToolkitDocumentType.scanner, [metadata(doc1)]);
      final file = onlyFile();
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      (json['documents'] as List).add(<String, Object?>{
        ...metadata(doc2).toWorkerJson(),
        'sizeBytes': 0,
      });
      await file.writeAsString(jsonEncode(json));
      expect(await cache.read(ToolkitDocumentType.scanner), [metadata(doc1)]);
    });

    test('holds metadata only: no URL, key or path', () async {
      await cacheFor(accountA)
          .write(ToolkitDocumentType.scanner, [metadata(doc1)]);
      final text = await onlyFile().readAsString();
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('profiles/')));
      expect(text, isNot(contains(dir.path)));
      expect(text, isNot(contains('url')));
    });
  });

  group('ToolkitDiagnostics', () {
    final lines = <String>[];
    setUp(() {
      lines.clear();
      ToolkitDiagnostics.sink = lines.add;
    });
    tearDown(() => ToolkitDiagnostics.sink = null);

    test('names a document by the last six characters of its id only', () {
      ToolkitDiagnostics.report(
        'open-failed',
        type: ToolkitDocumentType.signature,
        documentId: doc1,
        error: const ToolkitDocumentException(
          ToolkitFailure.objectChanged,
          statusCode: 409,
          workerCode: 'object_changed',
        ),
      );
      final line = lines.single;
      expect(line, contains('step=open-failed'));
      expect(line, contains('tool=signature'));
      expect(line, contains('doc=${doc1.substring(doc1.length - 6)}'));
      expect(line, isNot(contains(doc1)));
      expect(line, contains('failure=objectChanged'));
      expect(line, contains('status=409'));
      expect(line, contains('code=object_changed'));
    });

    test('never prints raw error text, which can carry a signed URL', () {
      ToolkitDiagnostics.report(
        'open-failed',
        error: Exception('GET https://signed.example.test/get/x?sig=secret'),
      );
      final line = lines.single;
      expect(line, contains('error='));
      expect(line, isNot(contains('signed.example')));
      expect(line, isNot(contains('secret')));
      expect(line, isNot(contains('http')));
    });

    test('a Worker code that is not a plain identifier is dropped', () {
      ToolkitDiagnostics.report(
        'list-failed',
        error: const ToolkitDocumentException(
          ToolkitFailure.unknown,
          workerCode: 'https://evil.test/?token=1',
        ),
      );
      expect(lines.single, isNot(contains('code=')));
      expect(lines.single, isNot(contains('evil')));
    });
  });
}
