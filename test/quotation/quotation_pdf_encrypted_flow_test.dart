// Q-2c-1b: the Quotation service keeps PDFs in the per-account encrypted
// store (QuotationPdfVault), moves this account's earlier unencrypted copies
// into it only on the evidence of a whole server list, opens a temporary
// plain copy for viewing and removes it after, and Delete Account removes the
// account's encrypted copies and key through its real defaults.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _q1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const _q2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const _m0 = 'dddddddd-0000-4000-8000-000000000000';
const _m1 = 'dddddddd-0000-4000-8000-000000000001';
const _m2 = 'dddddddd-0000-4000-8000-000000000002';

Uint8List _pdf(String text) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$text\nendobj\n%%EOF\n'));

QuotationModel _row(String id, String account, String? pdf) => QuotationModel(
      id: id,
      userId: account,
      propertyTitle: 'Villa',
      officeName: 'Realtig',
      pdfMediaId: pdf,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class _Keys implements AccountCacheKeyStore {
  final Map<String, List<int>> keys = {};
  @override
  Future<List<int>?> read(String uid) async => keys[uid];
  @override
  Future<void> write(String uid, List<int> key) async => keys[uid] = key;
  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class _Guard implements ScannerBackupGuard {
  @override
  Future<bool> exclude(String path) async => true;
}

class _Transport implements QuotationMediaTransport {
  int fetches = 0;
  String current = _m1;
  bool offline = false;

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async {
    fetches++;
    if (offline) {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    }
    return QuotationSignedMedia(
      quotationPdf: SignedQuotationMedia(
        mediaObjectId: current,
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
  final StreamController<List<QuotationModel>> lists =
      StreamController<List<QuotationModel>>.broadcast();

  @override
  Stream<List<QuotationModel>> watchQuotations() => lists.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

String _sep(List<String> parts) => parts.join(Platform.pathSeparator);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late Directory temp;
  late _Keys keys;
  late _Transport transport;
  late _Remote remote;
  String? signedIn;
  String? session;
  var downloads = 0;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('q2c1b_flow_docs_');
    temp = Directory.systemTemp.createTempSync('q2c1b_flow_tmp_');
    Hive.init(docs.path);
    EncryptedAccountListCache.debugStorageRoot = docs.path;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ListSessionCheck.debugOverride = (_) => Future<bool>.value(true);
    keys = _Keys();
    transport = _Transport();
    remote = _Remote();
    signedIn = _alice;
    session = 's1';
    downloads = 0;
    QuotationPdfVault.debugWrite = null;
    QuotationPdfVault.debugAfterWrite = null;
    QuotationPdfVault.debugNewProcess();
  });

  tearDown(() async {
    QuotationPdfVault.debugWrite = null;
    QuotationPdfVault.debugAfterWrite = null;
    ListSessionCheck.debugOverride = null;
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
    for (final d in [docs, temp]) {
      for (var attempt = 0;; attempt++) {
        try {
          if (d.existsSync()) d.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
  });

  QuotationPdfVault vault() => QuotationPdfVault(
        documents: () async => docs,
        temporary: () async => temp,
        keys: keys,
        backup: _Guard(),
      );

  QuotationService service({http.Client? client}) => QuotationService(
        remote: remote,
        mediaTransport: transport,
        pdfCache: QuotationPdfCache(directory: () async => docs),
        pdfVault: vault(),
        httpClient: client ??
            MockClient((_) async {
              downloads++;
              return http.Response.bytes(_pdf('server'), 200);
            }),
        currentUserId: () => signedIn,
        sessionOf: () => session,
      );

  File root(String name) => File(_sep([docs.path, name]));

  File legacy(String name, List<int> bytes) =>
      root(name)..writeAsBytesSync(bytes);

  List<String> rootFiles() => [
        for (final f in docs.listSync().whereType<File>())
          f.uri.pathSegments.last
      ];

  // -----------------------------------------------------------------------
  group('opening', () {
    test('after a restart it opens offline, and the viewing copy goes after',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf('kept'));
      final quotations = service(); // a new process: new instances
      final opened = await quotations.resolvePdfFile(_row(_q1, _alice, _m1));
      expect(opened.readAsBytesSync(), _pdf('kept'));
      expect(transport.fetches, 0);
      expect(downloads, 0);
      expect(QuotationPdfVault.isViewingCopy(opened.path, temp.path), isTrue);
      await quotations.releasePdfFile(opened);
      expect(opened.existsSync(), isFalse);
    });

    test('a damaged encrypted copy never falls back to plaintext', () async {
      await vault().store(_alice, _q1, _m1, _pdf('kept'));
      final file =
          File(_sep([docs.path, 'quotation_pdfs', _alice, '${_q1}_$_m1.bwqp']));
      final bytes = file.readAsBytesSync();
      bytes[50] ^= 1;
      file.writeAsBytesSync(bytes);
      legacy('quotation_${_q1}_$_m1.pdf', _pdf('untrusted plaintext'));
      final opened = await service().resolvePdfFile(_row(_q1, _alice, _m1));
      expect(opened.readAsBytesSync(), _pdf('server'),
          reason: 'only an authorized download replaces it');
      expect(transport.fetches, 1);
      expect(await vault().read(_alice, _q1, _m1), _pdf('server'));
      expect(rootFiles(), isEmpty);
    });

    test('a lost key: the PDF comes again only from the server', () async {
      await vault().store(_alice, _q1, _m1, _pdf('kept'));
      keys.keys.remove(_alice);
      final opened = await service().resolvePdfFile(_row(_q1, _alice, _m1));
      expect(opened.readAsBytesSync(), _pdf('server'));
      expect(downloads, 1);
    });

    // Final review (R1): an unmigrated plaintext copy is not authenticated, so
    // the resolver never opens it; only migration on server evidence can
    // turn it into an encrypted copy.
    test(
        'an unmigrated plaintext copy is never opened: it comes from the '
        'server', () async {
      final old = legacy('quotation_${_q1}_$_m1.pdf', _pdf('old'));
      final opened = await service().resolvePdfFile(_row(_q1, _alice, _m1));
      expect(opened.readAsBytesSync(), _pdf('server'));
      expect(transport.fetches, 1);
      expect(QuotationPdfVault.isViewingCopy(opened.path, temp.path), isTrue);
      expect(old.existsSync(), isFalse,
          reason: 'replaced by the authorized copy');
    });

    test('offline, an unmigrated plaintext copy stays unopened and untouched',
        () async {
      final old = legacy('quotation_${_q1}_$_m1.pdf', _pdf('old'));
      final cut = legacy(
          'quotation_${_q2}_$_m2.pdf', utf8.encode('%PDF-1.7\nhalf a file'));
      transport.offline = true;
      for (final row in [_row(_q1, _alice, _m1), _row(_q2, _alice, _m2)]) {
        await expectLater(service().resolvePdfFile(row),
            throwsA(isA<QuotationMediaException>()));
      }
      expect(old.readAsBytesSync(), _pdf('old'));
      expect(cut.existsSync(), isTrue);
    });

    test('a newer server PDF is kept; the older copy is not shown as current',
        () async {
      await vault().store(_alice, _q1, _m0, _pdf('older'));
      transport.current = _m1;
      final opened = await service().resolvePdfFile(_row(_q1, _alice, _m2));
      expect(opened.readAsBytesSync(), _pdf('server'));
      expect(await vault().versionsOf(_alice, _q1), {_m1});
    });
  });

  // -----------------------------------------------------------------------
  group('moving earlier unencrypted PDFs', () {
    test('proven by the server list: sealed, verified, then the plaintext goes',
        () async {
      legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      legacy('quotation_${_q1}_$_m0.pdf', _pdf('older'));
      legacy('quotation_$_q1.pdf', _pdf('leftover'));
      await service().migrateLegacyPdfs([_row(_q1, _alice, _m1)]);
      expect(await vault().read(_alice, _q1, _m1), _pdf('current'));
      expect(rootFiles(), isEmpty);
      final opened = await service().resolvePdfFile(_row(_q1, _alice, _m1));
      expect(opened.readAsBytesSync(), _pdf('current'));
      expect(transport.fetches, 0);
    });

    test('a truncated or non-PDF file is left untouched', () async {
      final cut = legacy('quotation_${_q1}_$_m1.pdf',
          utf8.encode('%PDF-1.7\nhalf a file without its end'));
      final junk =
          legacy('quotation_${_q2}_$_m2.pdf', utf8.encode('not a pdf'));
      await service()
          .migrateLegacyPdfs([_row(_q1, _alice, _m1), _row(_q2, _alice, _m2)]);
      expect(cut.existsSync(), isTrue);
      expect(junk.existsSync(), isTrue);
      expect(await vault().versionsOf(_alice, _q1), isEmpty);
    });

    test(
        'an interrupted move (full disk) keeps the original; the next list '
        'completes it', () async {
      final original = legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      QuotationPdfVault.debugWrite = (file, bytes) async =>
          throw const FileSystemException('No space left on device');
      await service().migrateLegacyPdfs([_row(_q1, _alice, _m1)]);
      expect(original.existsSync(), isTrue);
      expect(await vault().versionsOf(_alice, _q1), isEmpty);
      QuotationPdfVault.debugWrite = null;
      await service().migrateLegacyPdfs([_row(_q1, _alice, _m1)]);
      expect(original.existsSync(), isFalse);
      expect(await vault().read(_alice, _q1, _m1), _pdf('current'));
    });

    test(
        'a restart after sealing, before removing: identical ⇒ removed, '
        'different ⇒ both kept', () async {
      await vault().store(_alice, _q1, _m1, _pdf('current'));
      final same = legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      await vault().store(_alice, _q2, _m2, _pdf('sealed'));
      final differs = legacy('quotation_${_q2}_$_m2.pdf', _pdf('changed'));
      await service()
          .migrateLegacyPdfs([_row(_q1, _alice, _m1), _row(_q2, _alice, _m2)]);
      expect(same.existsSync(), isFalse);
      expect(differs.existsSync(), isTrue);
      expect(await vault().read(_alice, _q2, _m2), _pdf('sealed'));
    });

    test('never an older copy beside another version already kept', () async {
      await vault().store(_alice, _q1, _m2, _pdf('another'));
      final original = legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      await service().migrateLegacyPdfs([_row(_q1, _alice, _m1)]);
      expect(original.existsSync(), isTrue);
      expect(await vault().versionsOf(_alice, _q1), {_m2});
    });

    test(
        'nothing for rows of another account, rows without a PDF, or names '
        'no row gives', () async {
      final bobs = legacy('quotation_${_q1}_$_m1.pdf', _pdf('bob'));
      final none = legacy('quotation_$_q2.pdf', _pdf('leftover'));
      final unknown = legacy('quotation_${_q2}_$_m0.pdf', _pdf('unknown'));
      await service()
          .migrateLegacyPdfs([_row(_q1, _bob, _m1), _row(_q2, _alice, null)]);
      for (final f in [bobs, none, unknown]) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
      expect(await vault().versionsOf(_alice, _q1), isEmpty);
    });

    test('the session changes during the move ⇒ the original is not removed',
        () async {
      final original = legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      QuotationPdfVault.debugAfterWrite = (_) async => session = 's2';
      await service().migrateLegacyPdfs([_row(_q1, _alice, _m1)]);
      expect(original.existsSync(), isTrue);
    });

    test(
        'opening the Quotations screen sweeps an earlier run\'s viewing copies',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf('kept'));
      final left = (await vault().openForViewing(_alice, _q1, _m1))!;
      QuotationPdfVault.debugNewProcess(); // the app starts again
      final sub = service()
          .watchUserQuotationsLocalFirst()
          .listen((_) {}, onError: (_) {});
      addTearDown(sub.cancel);
      for (var i = 0; i < 400 && left.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(left.existsSync(), isFalse);
    });

    test('a whole server list on the Quotations screen starts the move',
        () async {
      final original = legacy('quotation_${_q1}_$_m1.pdf', _pdf('current'));
      final sub = service()
          .watchUserQuotationsLocalFirst()
          .listen((_) {}, onError: (_) {});
      addTearDown(sub.cancel);
      for (var i = 0; i < 200 && !remote.lists.hasListener; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      remote.lists.add([_row(_q1, _alice, _m1)]);
      for (var i = 0; i < 400 && original.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(original.existsSync(), isFalse);
      expect(await vault().read(_alice, _q1, _m1), _pdf('current'));
    });
  });

  // -----------------------------------------------------------------------
  test(
      'Delete Account, through its real defaults, removes only that '
      'account\'s encrypted copies, key and viewing copies', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => switch (call.method) {
                  'getApplicationDocumentsDirectory' => docs.path,
                  'getTemporaryDirectory' => temp.path,
                  _ => null,
                });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    final real = QuotationPdfVault(backup: _Guard());
    await real.store(_alice, _q1, _m1, _pdf('alice'));
    await real.store(_bob, _q2, _m2, _pdf('bob'));
    final aliceView = (await real.openForViewing(_alice, _q1, _m1))!;
    final bobView = (await real.openForViewing(_bob, _q2, _m2))!;

    await DeletedAccountLocalDataCleaner(
      forgetProfileMedia: ({mediaIds}) async {},
      forgetOfferMedia: ({ownerId}) async =>
          const OfferMediaCleanupReport.empty(),
      purgeOfferMediaUploads: (_) async => 0,
    ).clear(deletedUid: _alice, wasSignedInAccount: false);

    expect(Directory(_sep([docs.path, 'quotation_pdfs', _alice])).existsSync(),
        isFalse);
    expect(
        await const FlutterSecureStorage()
            .read(key: SecureQuotationPdfKeyStore.storageKeyFor(_alice)),
        isNull);
    expect(aliceView.existsSync(), isFalse);
    expect(bobView.existsSync(), isTrue);
    expect(await real.read(_bob, _q2, _m2), _pdf('bob'));
  });
}
