import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

void main() {
  group('SHA-256', () {
    test('matches the published test vectors', () {
      expect(ToolkitSha256.hexOfBytes(<int>[]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(ToolkitSha256.hexOfBytes('abc'.codeUnits),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
          ToolkitSha256.hexOfBytes(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'
                  .codeUnits),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(ToolkitSha256.hexOfBytes(List<int>.filled(1000000, 0x61)),
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });

    test('padding boundaries (55, 56, 63, 64, 65 bytes) match', () {
      const known = <int, String>{
        55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
        56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
        63: '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34',
        64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
        65: '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0',
      };
      known.forEach((length, digest) {
        expect(ToolkitSha256.hexOfBytes(List<int>.filled(length, 0x61)), digest,
            reason: '$length bytes');
      });
    });

    test('chunked input equals one-shot input', () {
      final data = List<int>.generate(10007, (i) => (i * 31) % 251);
      final whole = ToolkitSha256.hexOfBytes(data);
      for (final chunk in [1, 7, 63, 64, 65, 1000]) {
        final hash = ToolkitSha256();
        for (var i = 0; i < data.length; i += chunk) {
          hash.add(data.sublist(
              i, i + chunk > data.length ? data.length : i + chunk));
        }
        expect(hash.closeHex(), whole, reason: 'chunk $chunk');
      }
    });

    test('a closed hash cannot be reused, and a file hashes as a stream',
        () async {
      final hash = ToolkitSha256()..add('abc'.codeUnits);
      hash.closeHex();
      expect(() => hash.add([1]), throwsStateError);
      expect(hash.closeHex, throwsStateError);

      final dir = await Directory.systemTemp.createTemp('toolkit_sha_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.bin')..writeAsBytesSync('abc'.codeUnits);
      expect(await ToolkitSha256.hexOfFile(file),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('tool identity', () {
    test(
        'wire names are the database values; local roots are the four stores\'',
        () {
      expect(ToolkitDocumentType.values.map((t) => t.wireName),
          ['scanner', 'combine_pdfs', 'image_to_pdf', 'signature']);
      expect(
          ToolkitDocumentType.fromWire('scanner'), ToolkitDocumentType.scanner);
      expect(ToolkitDocumentType.fromWire('Scanner'), isNull);
      expect(ToolkitDocumentType.fromWire(null), isNull);
    });

    test('each local store root matches the real store\'s account directory',
        () {
      final base = Directory.systemTemp;
      const user = '550e8400-e29b-41d4-a716-446655440000';
      String root(Directory d) => p.basename(p.dirname(d.path));
      expect(root(ScannerDocumentStore.accountDirectory(base, user)),
          ToolkitDocumentType.scanner.localStoreRoot);
      expect(root(CombinePdfStore.accountDirectory(base, user)),
          ToolkitDocumentType.combinePdfs.localStoreRoot);
      expect(root(ImagePdfStore.accountDirectory(base, user)),
          ToolkitDocumentType.imageToPdf.localStoreRoot);
      expect(root(SignatureStore.accountDirectory(base, user)),
          ToolkitDocumentType.signature.localStoreRoot);
    });
  });

  group('ids and titles', () {
    test('only canonical lower-case UUIDs are document ids', () {
      expect(
          ToolkitDocumentIds.isCanonical(
              'd0c00001-0000-4000-8000-000000000001'),
          isTrue);
      for (final bad in [
        null,
        '',
        'id0',
        'D0C00001-0000-4000-8000-000000000001',
        'd0c00001-0000-4000-8000-00000000000',
        'd0c00001-0000-6000-8000-000000000001',
        '../d0c00001-0000-4000-8000-000000000001',
      ]) {
        expect(ToolkitDocumentIds.isCanonical(bad), isFalse, reason: '$bad');
      }
    });

    test('title rules match the server', () {
      expect(ToolkitDocumentTitles.problemWith('عقد إيجار'), isNull);
      expect(ToolkitDocumentTitles.problemWith('a' * 200), isNull);
      expect(ToolkitDocumentTitles.problemWith('a' * 201), 'too long');
      expect(ToolkitDocumentTitles.problemWith(''), 'empty');
      expect(ToolkitDocumentTitles.problemWith(' x'), 'surrounding whitespace');
      for (final bad in [
        'a\u0000b',
        'a\tb',
        'a\u202Eb',
        'a\u2066b',
        'a\u007Fb'
      ]) {
        expect(ToolkitDocumentTitles.problemWith(bad), 'unsafe character',
            reason: bad);
      }
      // A harmless direction mark is kept.
      expect(ToolkitDocumentTitles.problemWith('a‏b'), isNull);
    });

    test('sanitize makes any local name acceptable', () {
      expect(
          ToolkitDocumentTitles.sanitize('  Lease\u202E.pdf\n '), 'Lease.pdf');
      expect(ToolkitDocumentTitles.sanitize('\u202E\u2066'), 'Document');
      expect(ToolkitDocumentTitles.sanitize('', fallback: 'Scan'), 'Scan');
      final long = ToolkitDocumentTitles.sanitize('ب' * 300);
      expect(long.runes.length, 200);
      for (final raw in ['x', ' y ', 'a\u0001b', 'ـ' * 250, '😀' * 250]) {
        expect(
            ToolkitDocumentTitles.problemWith(
                ToolkitDocumentTitles.sanitize(raw)),
            isNull,
            reason: raw);
      }
    });
  });

  group('metadata contract', () {
    Map<String, Object?> valid() => {
          'documentId': 'd0c00001-0000-4000-8000-000000000001',
          'documentType': 'signature',
          'contentType': 'application/pdf',
          'title': 'Signed lease',
          'sizeBytes': 1234,
          'pageCount': 3,
          'contentSha256': 'a' * 64,
          'sha256Verified': false,
          'sourceCreatedAt': '2026-10-19T08:00:00.000Z',
          'createdAt': '2026-10-19T08:00:05.123456+00:00',
          'version': 2,
        };

    test('reads exactly the Worker\'s shape', () {
      final doc = ToolkitDocumentMetadata.fromWorkerJson(valid());
      expect(doc.type, ToolkitDocumentType.signature);
      expect(doc.sizeBytes, 1234);
      expect(doc.pageCount, 3);
      expect(doc.createdAt.isUtc, isTrue);
      expect(doc.copyWith(title: 'x', version: 5).version, 5);
      expect(doc, ToolkitDocumentMetadata.fromWorkerJson(valid()));
    });

    test('the page count may be null; the digest and the format may not', () {
      final doc =
          ToolkitDocumentMetadata.fromWorkerJson(valid()..['pageCount'] = null);
      expect(doc.pageCount, isNull);
      for (final key in ['contentSha256', 'contentType', 'sha256Verified']) {
        expect(
            () => ToolkitDocumentMetadata.fromWorkerJson(valid()..[key] = null),
            throwsFormatException,
            reason: key);
      }
    });

    test('anything off the contract is refused', () {
      final cases = <String, Object?>{
        'documentId': 'nope',
        'documentType': 'notes',
        'title': ' padded',
        'sizeBytes': 0,
        'pageCount': 0,
        'contentSha256': 'ABC',
        'sourceCreatedAt': 'yesterday',
        'createdAt': null,
        'version': 0,
      };
      cases.forEach((key, value) {
        final json = valid()..[key] = value;
        expect(() => ToolkitDocumentMetadata.fromWorkerJson(json),
            throwsFormatException,
            reason: key);
      });
      expect(() => ToolkitDocumentMetadata.fromWorkerJson('x'),
          throwsFormatException);
      expect(
          () => ToolkitDocumentMetadata.fromWorkerJson(
              valid()..['sizeBytes'] = '12'),
          throwsFormatException);
    });
  });

  group('states', () {
    test(
        'only confirmed states are cloud backed, and only some have a local copy',
        () {
      for (final state in ToolkitDocumentSyncState.values) {
        final backed = {
          ToolkitDocumentSyncState.savedToCloud,
          ToolkitDocumentSyncState.downloadRequired,
          ToolkitDocumentSyncState.downloadFailed,
        };
        expect(state.isCloudBacked, backed.contains(state), reason: '$state');
      }
      expect(ToolkitDocumentSyncState.savedLocallyPendingSync.isCloudBacked,
          isFalse);
      expect(ToolkitDocumentSyncState.syncInProgress.isCloudBacked, isFalse);
      expect(ToolkitDocumentSyncState.downloadRequired.hasLocalCopy, isFalse);
      expect(ToolkitDocumentSyncState.savedLocallyPendingSync.hasLocalCopy,
          isTrue);
      expect(ToolkitDocumentSyncState.deletePending.needsSync, isTrue);
      expect(ToolkitDocumentSyncState.syncRejected.needsSync, isFalse);
      expect(ToolkitDocumentSyncState.remoteDeleted.needsSync, isFalse);
    });

    test('the foundation is on unless a build turns it off', () {
      expect(ToolkitCloudDocumentsFeature.enabled, isTrue);
    });
  });
}
