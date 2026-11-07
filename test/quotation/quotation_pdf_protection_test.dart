// Q-2c-1 (the parts that are safe on their own; tracker §7AY): Quotation PDFs
// get a backup-excluded home (`<documents>/quotation_pdfs`), new PDFs are
// generated in its per-account work folder instead of the documents folder,
// the resolver opens only the signed-in account's PDFs and drops a download
// that ends under another account or session, and Delete Account removes the
// deleted account's work files and the documents-folder PDFs its verified
// saved Quotations list proves are its own — nothing else. Encryption at rest
// and migration wait for their own approval.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_files.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _qa1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const _qa2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const _qb1 = 'bbbbbbbb-0000-4000-8000-000000000001';
const _qx = 'cccccccc-0000-4000-8000-000000000001';
const _pdfA = 'dddddddd-0000-4000-8000-000000000001';
const _pdfOld = 'dddddddd-0000-4000-8000-000000000009';
const _pdfB = 'eeeeeeee-0000-4000-8000-000000000001';
final _pdfBytes = utf8.encode('%PDF-1.7 test');

QuotationModel _q(String id, String account, {String? pdf = _pdfA}) =>
    QuotationModel(
      id: id,
      userId: account,
      propertyTitle: 'Villa',
      officeName: 'Realtig',
      pdfMediaId: pdf,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class _Transport implements QuotationMediaTransport {
  int calls = 0;
  Future<void> Function()? beforeAnswer;

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async {
    calls++;
    await beforeAnswer?.call();
    return QuotationSignedMedia(
      quotationPdf: SignedQuotationMedia(
        mediaObjectId: _pdfA,
        contentType: 'application/pdf',
        url: 'https://media.example/signed',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

class _Remote implements QuotationRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

class _MemoryKeys implements AccountCacheKeyStore {
  final Map<String, List<int>> keys = {};
  @override
  Future<List<int>?> read(String uid) async => keys[uid];
  @override
  Future<void> write(String uid, List<int> key) async => keys[uid] = key;
  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class _Guard implements ScannerBackupGuard {
  final List<String> excluded = [];

  @override
  Future<bool> exclude(String path) async {
    excluded.add(path);
    return true;
  }
}

String _sep(List<String> parts) => parts.join(Platform.pathSeparator);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('q2c_docs_');
    Hive.init(docs.path);
    EncryptedAccountListCache.debugStorageRoot = docs.path;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    for (final uid in [_alice, _bob]) {
      for (var attempt = 0;; attempt++) {
        try {
          await Hive.deleteBoxFromDisk(QuotationsLocalCache.boxNameForUid(uid),
              path: _sep([docs.path, EncryptedAccountListCache.directoryName]));
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
    EncryptedAccountListCache.debugForgetProcessState();
    await Hive.close();
    for (var attempt = 0;; attempt++) {
      try {
        docs.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  File file(List<String> parts) => File(_sep([docs.path, ...parts]));

  File rootPdf(String name) => file([name])
    ..createSync(recursive: true)
    ..writeAsBytesSync(_pdfBytes);

  // -----------------------------------------------------------------------
  group('backup policy', () {
    const kept = [
      'app_flutter/offer_media',
      'app_flutter/offer_media_uploads.hive',
      'app_flutter/offer_media_uploads.lock',
      'app_flutter/scanner',
      'app_flutter/combine_pdfs',
      'app_flutter/image_to_pdf',
      'app_flutter/signature_pdfs',
      'app_flutter/offline_lists',
      'app_flutter/cached_favorites.hive',
      'app_flutter/cached_favorites.lock',
    ];
    const pdfs = '<exclude domain="root" path="app_flutter/quotation_pdfs" />';

    List<String> sections(String xml, String tag) => [
          for (final m
              in RegExp('<$tag>(.*?)</$tag>', dotAll: true).allMatches(xml))
            m.group(1)!
        ];

    void expectExcludes(String section, String where) {
      expect(section, contains(pdfs), reason: where);
      for (final path in kept) {
        expect(section, contains('<exclude domain="root" path="$path" />'),
            reason: '$where keeps $path');
      }
      expect(section,
          contains('<exclude domain="file" path="mlkit_docscan_ui_client" />'),
          reason: where);
    }

    test('Android ≤ 11 Auto Backup leaves the Quotation PDF folder out', () {
      final xml = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      final full = sections(xml, 'full-backup-content');
      expect(full, hasLength(1));
      expectExcludes(full.single, 'full-backup-content');
    });

    test('Android 12+ cloud backup and device transfer leave it out', () {
      final xml = File('android/app/src/main/res/xml/data_extraction_rules.xml')
          .readAsStringSync();
      final cloud = sections(xml, 'cloud-backup');
      final transfer = sections(xml, 'device-transfer');
      expect(cloud, hasLength(1));
      expect(transfer, hasLength(1));
      expectExcludes(cloud.single, 'cloud-backup');
      expectExcludes(transfer.single, 'device-transfer');
    });

    test('on iPhone the folder is marked when it is created', () async {
      final guard = _Guard();
      final files =
          QuotationPdfFiles(documents: () async => docs, backup: guard);
      await files.workFileFor(_q(_qa1, _alice));
      expect(guard.excluded, [
        _sep([docs.path, QuotationPdfFiles.rootFolderName])
      ]);
    });
  });

  // -----------------------------------------------------------------------
  group('a new PDF is generated in the account\'s work folder', () {
    test('never in the documents folder, which is backed up', () async {
      final files =
          QuotationPdfFiles(documents: () async => docs, backup: _Guard());
      final work = await files.workFileFor(_q(_qa1, _alice));
      expect(
          work.path,
          _sep([
            docs.path,
            'quotation_pdfs',
            '.work',
            _alice,
            'quotation_$_qa1.pdf'
          ]));
      expect(work.parent.existsSync(), isTrue);
      expect(docs.listSync().whereType<File>(), isEmpty);
    });

    test('an account id that is not plain cannot leave the work folder', () {
      final dir = QuotationPdfFiles.workDirectory(docs, '../../evil');
      expect(dir.parent.path, _sep([docs.path, 'quotation_pdfs', '.work']));
      expect(dir.path, isNot(contains('..')));
      expect(
          () => QuotationPdfFiles.workDirectory(docs, ''), throwsArgumentError);
    });

    test('the generator writes there and its content step is unchanged', () {
      final source = File(
              'lib/src/views/Screens/home/quotation/services/pdf_generation_service.dart')
          .readAsStringSync();
      expect(
          RegExp(r'^\s*final file = await QuotationPdfFiles\(\)\.workFileFor\(quotation\);\r?$',
                  multiLine: true)
              .hasMatch(source),
          isTrue,
          reason: 'the generated file is the work file itself');
      expect(RegExp(r'\bFile\(').allMatches(source).length, 2,
          reason: 'only the two office-logo reads; no other file is made '
              'for the generated PDF');
      expect(source, isNot(contains('getApplicationDocumentsDirectory')));
      expect(source, contains('final bytes = await pdf.save();'));
      expect(source, contains('await file.writeAsBytes(bytes);'));
    });
  });

  // -----------------------------------------------------------------------
  group('the resolver opens only the signed-in account\'s PDF', () {
    late _Transport transport;
    late QuotationPdfVault vault;
    String? signedIn;
    String? session;

    QuotationService service({http.Client? client}) => QuotationService(
          remote: _Remote(),
          mediaTransport: transport,
          pdfCache: QuotationPdfCache(directory: () async => docs),
          httpClient: client ??
              MockClient((_) async => http.Response.bytes(_pdfBytes, 200)),
          currentUserId: () => signedIn,
          sessionOf: () => session,
          pdfVault: vault,
        );

    setUp(() {
      vault = QuotationPdfVault(
        documents: () async => docs,
        temporary: () async => docs,
        keys: _MemoryKeys(),
        backup: _Guard(),
      );
      transport = _Transport();
      signedIn = _alice;
      session = 's1';
    });

    test('this account\'s saved (encrypted) copy opens with no request',
        () async {
      await vault.store(_alice, _qa1, _pdfA, Uint8List.fromList(_pdfBytes));
      final opened = await service().resolvePdfFile(_q(_qa1, _alice));
      expect(opened.readAsBytesSync(), _pdfBytes);
      expect(QuotationPdfVault.isViewingCopy(opened.path, docs.path), isTrue);
      expect(transport.calls, 0);
    });

    test('another account\'s Quotation is refused before any file or request',
        () async {
      rootPdf('quotation_${_qb1}_$_pdfA.pdf');
      await expectLater(
          service().resolvePdfFile(_q(_qb1, _bob)),
          throwsA(isA<QuotationMediaException>().having((e) => e.failure,
              'failure', QuotationMediaFailure.unauthorized)));
      expect(transport.calls, 0);
    });

    test('signed out ⇒ refused, nothing opened or asked', () async {
      rootPdf('quotation_${_qa1}_$_pdfA.pdf');
      signedIn = null;
      await expectLater(
          service().resolvePdfFile(_q(_qa1, _alice)),
          throwsA(isA<QuotationMediaException>().having(
              (e) => e.failure, 'failure', QuotationMediaFailure.notSignedIn)));
      expect(transport.calls, 0);
    });

    test('a download for this account and session is kept and opened',
        () async {
      final opened = await service().resolvePdfFile(_q(_qa1, _alice));
      // Q-2c-1b: kept encrypted for this account; a viewing copy opens.
      expect(await vault.read(_alice, _qa1, _pdfA), _pdfBytes);
      expect(file(['quotation_${_qa1}_$_pdfA.pdf']).existsSync(), isFalse);
      expect(QuotationPdfVault.isViewingCopy(opened.path, docs.path), isTrue);
      expect(opened.readAsBytesSync(), _pdfBytes);
      expect(transport.calls, 1);
    });

    for (final (label, change) in [
      ('the session is replaced (same account)', () => session = 's2'),
      ('another account signs in', () => signedIn = _bob),
      ('the account signs out', () => signedIn = null),
    ]) {
      test('$label during the download ⇒ nothing kept or opened', () async {
        transport.beforeAnswer = () async => change();
        await expectLater(
            service().resolvePdfFile(_q(_qa1, _alice)),
            throwsA(isA<QuotationMediaException>().having((e) => e.failure,
                'failure', QuotationMediaFailure.notSignedIn)));
        expect(file(['quotation_${_qa1}_$_pdfA.pdf']).existsSync(), isFalse);
      });
    }

    for (final (label, change) in [
      ('the session is replaced', () => session = 's2'),
      ('another account signs in', () => signedIn = _bob),
    ]) {
      test('$label while the PDF bytes download ⇒ nothing kept or opened',
          () async {
        final client = MockClient((_) async {
          change();
          return http.Response.bytes(_pdfBytes, 200);
        });
        await expectLater(
            service(client: client).resolvePdfFile(_q(_qa1, _alice)),
            throwsA(isA<QuotationMediaException>().having((e) => e.failure,
                'failure', QuotationMediaFailure.notSignedIn)));
        expect(file(['quotation_${_qa1}_$_pdfA.pdf']).existsSync(), isFalse);
      });
    }

    test(
        'an account switch while the server is asked ⇒ not even the current '
        'copy already on this device is opened', () async {
      // The list row names an older PDF; the server's current one is here.
      await vault.store(_alice, _qa1, _pdfA, Uint8List.fromList(_pdfBytes));
      transport.beforeAnswer = () async => signedIn = _bob;
      await expectLater(
          service().resolvePdfFile(_q(_qa1, _alice, pdf: _pdfOld)),
          throwsA(isA<QuotationMediaException>().having(
              (e) => e.failure, 'failure', QuotationMediaFailure.notSignedIn)));
    });

    test('after sign-out and the same account again, its PDF still opens',
        () async {
      await vault.store(_alice, _qa1, _pdfA, Uint8List.fromList(_pdfBytes));
      signedIn = null;
      session = null;
      signedIn = _alice;
      session = 's2';
      final opened = await service().resolvePdfFile(_q(_qa1, _alice));
      expect(opened.readAsBytesSync(), _pdfBytes);
      expect(transport.calls, 0);
    });
  });

  // -----------------------------------------------------------------------
  group('Delete Account', () {
    const cache = QuotationsLocalCache();

    DeletedAccountLocalDataCleaner cleaner() => DeletedAccountLocalDataCleaner(
          forgetProfileMedia: ({mediaIds}) async {},
          forgetOfferMedia: ({ownerId}) async =>
              const OfferMediaCleanupReport.empty(),
          purgeOfferMediaUploads: (_) async => 0,
          forgetQuotationPdfs: (uid) =>
              QuotationPdfFiles(documents: () async => docs, backup: _Guard())
                  .forgetAccount(uid),
        );

    Future<List<File>> unrelated() async {
      final files = [
        rootPdf('quotation_${_qb1}_$_pdfB.pdf'), // Bob's
        rootPdf('quotation_${_qx}_$_pdfA.pdf'), // nobody's proven
        rootPdf('quotation_1699999999999.pdf'), // an old unnamed one
        rootPdf('quotation_${_qa1}_$_pdfA.pdf.bak'), // not the pattern
        rootPdf('quotation_${_qa1}_${_pdfA}x.pdf'), // not the pattern
        rootPdf('other.pdf'),
        rootPdf(_sep(['offer_media', 'photo.jpg'])),
        rootPdf(_sep(['combine_pdfs', _alice, 'files', 'combined.pdf'])),
        rootPdf(_sep(['scanner', _alice, 'scan.pdf'])),
        rootPdf(_sep(['quotation_pdfs', '.work', _bob, 'quotation_$_qb1.pdf'])),
      ];
      await cache.write(_bob, [_q(_qb1, _bob, pdf: _pdfB)]);
      return files;
    }

    test('removes only the deleted account\'s proven PDFs and work files',
        () async {
      await cache
          .write(_alice, [_q(_qa1, _alice), _q(_qa2, _alice, pdf: null)]);
      final hers = [
        rootPdf('quotation_${_qa1}_$_pdfA.pdf'), // the bound PDF
        rootPdf('quotation_${_qa1}_$_pdfOld.pdf'), // an older one of hers
        rootPdf('quotation_$_qa2.pdf'), // a generation leftover of hers
        rootPdf(
            _sep(['quotation_pdfs', '.work', _alice, 'quotation_$_qa1.pdf'])),
      ];
      final others = await unrelated();

      await cleaner().clear(deletedUid: _alice, wasSignedInAccount: false);

      for (final f in hers) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
      expect(
          Directory(_sep([docs.path, 'quotation_pdfs', '.work', _alice]))
              .existsSync(),
          isFalse);
      for (final f in others) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
      expect(await cache.read(_alice), isNull, reason: 'her list is gone too');
      expect(await cache.read(_bob), hasLength(1));
    });

    test('an unreadable saved list proves nothing: her root PDFs stay',
        () async {
      await cache.write(_alice, [_q(_qa1, _alice)]);
      await Hive.box<String>(QuotationsLocalCache.boxNameForUid(_alice))
          .close();
      await const FlutterSecureStorage().write(
          key: SecureQuotationsCacheKeyStore.storageKeyFor(_alice),
          value: base64.encode(List<int>.generate(32, (i) => 3 * i)));
      final root = rootPdf('quotation_${_qa1}_$_pdfA.pdf');
      final work = rootPdf(
          _sep(['quotation_pdfs', '.work', _alice, 'quotation_$_qa1.pdf']));

      await cleaner().clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(root.existsSync(), isTrue, reason: 'ownership not proven');
      expect(work.existsSync(), isFalse, reason: 'her own work folder');
    });

    test('with no saved list nothing in the documents folder is touched',
        () async {
      final root = rootPdf('quotation_${_qa1}_$_pdfA.pdf');
      await cleaner().clear(deletedUid: _alice, wasSignedInAccount: true);
      expect(root.existsSync(), isTrue);
    });
  });
}
