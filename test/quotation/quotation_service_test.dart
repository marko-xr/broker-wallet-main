// Tests for the Quotation service: the one place the Supabase aggregate, the
// private media workflow and the on-device PDF cache meet.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart'
    show AccountCacheKeyStore;
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';

const _q = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';
const _pdfA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _pdfB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final _pdfBytes = '%PDF-1.4\nhello\n%%EOF\n'.codeUnits;

QuotationModel _model({String? pdfMediaId}) => QuotationModel(
      id: _q,
      userId: 'u',
      propertyTitle: 'Villa',
      officeName: 'Realtig',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      pdfMediaId: pdfMediaId,
    );

class _FakeRemote implements QuotationRemote {
  final List<String> calls = [];
  QuotationModel? lastSaved;
  String? lastSavedId;
  int? lastExpectedVersion;
  Object? saveError;
  QuotationMediaState? mediaState;
  final StreamController<List<QuotationModel>> stream =
      StreamController<List<QuotationModel>>.broadcast();

  @override
  Future<QuotationSaveResult> save(QuotationModel quotation,
      {required String quotationId, int? expectedVersion}) async {
    calls.add('save');
    if (saveError != null) throw saveError!;
    lastSaved = quotation;
    lastSavedId = quotationId;
    lastExpectedVersion = expectedVersion;
    return QuotationSaveResult(
        quotationId: quotationId,
        version: (expectedVersion ?? 0) + 1,
        outcome: expectedVersion == null ? 'created' : 'updated');
  }

  @override
  Future<QuotationModel?> getQuotation(String quotationId) async => _model();

  @override
  Future<QuotationMediaState?> getMediaState(String quotationId) async {
    calls.add('getMediaState');
    return mediaState;
  }

  @override
  Future<String?> getMediaFileName(String mediaId) async => 'logo.png';

  @override
  Future<List<QuotationModel>> listQuotations() async => [_model()];

  @override
  Stream<List<QuotationModel>> watchQuotations() => stream.stream;

  @override
  Future<void> softDelete(String quotationId) async {
    calls.add('softDelete:$quotationId');
  }
}

class _FakeTransport implements QuotationMediaTransport {
  final List<String> calls = [];
  Object? uploadError;
  final List<Object> authorizeScript = [];
  QuotationSignedMedia signed = const QuotationSignedMedia();
  int fetchSignedCalls = 0;

  @override
  Future<QuotationMediaAuthorization> authorize({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    calls.add('authorize:${role.wireName}:${expectedMediaId ?? 'null'}');
    if (authorizeScript.isNotEmpty) throw authorizeScript.removeAt(0);
    return QuotationMediaAuthorization.pending(
        mediaObjectId: mediaObjectId, presignedUrl: 'https://signed.example/put');
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) async {
    calls.add('upload');
    onUpload?.call();
    if (uploadError != null) throw uploadError!;
  }

  /// Runs while the upload is in flight (Q-2c-1b: a session change).
  void Function()? onUpload;

  @override
  Future<QuotationMediaConfirmation> confirm({
    required String quotationId,
    required QuotationMediaRole role,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    calls.add('confirm:${role.wireName}');
    return const QuotationMediaConfirmation(resultingVersion: 4);
  }

  @override
  Future<QuotationMediaRemoval> remove({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
  }) async {
    calls.add('remove:${role.wireName}');
    return const QuotationMediaRemoval(resultingVersion: 5);
  }

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async {
    fetchSignedCalls++;
    return signed;
  }
}

/// Master keys in memory (Q-2c-1b).
class _Keys implements AccountCacheKeyStore {
  final Map<String, List<int>> keys = {};
  @override
  Future<List<int>?> read(String uid) async => keys[uid];
  @override
  Future<void> write(String uid, List<int> key) async => keys[uid] = key;
  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class _NoBackupGuard implements ScannerBackupGuard {
  @override
  Future<bool> exclude(String path) async => true;
}

class _Harness {
  _Harness(this.dir, {http.Client? httpClient, String? Function()? sessionOf}) {
    vault = QuotationPdfVault(
      documents: () async => dir,
      temporary: () async => dir,
      keys: _Keys(),
      backup: _NoBackupGuard(),
    );
    service = QuotationService(
      remote: remote,
      mediaTransport: transport,
      pdfCache: QuotationPdfCache(directory: () async => dir),
      httpClient: httpClient,
      // The account the test Quotations belong to (Q-2c-1: the resolver
      // opens only the signed-in account's PDFs).
      currentUserId: () => 'u',
      sessionOf: sessionOf,
      pdfVault: vault,
    );
  }

  final Directory dir;
  late final QuotationPdfVault vault;
  final _FakeRemote remote = _FakeRemote();
  final _FakeTransport transport = _FakeTransport();
  late final QuotationService service;

  File cached(String quotationId, String mediaId) => File(
      '${dir.path}${Platform.pathSeparator}quotation_${quotationId}_$mediaId.pdf');

  Future<File> generatedPdf() async {
    final file = File('${dir.path}${Platform.pathSeparator}quotation_$_q.pdf');
    await file.writeAsBytes(_pdfBytes);
    return file;
  }
}

Future<_Harness> _harness(
    {http.Client? httpClient, String? Function()? sessionOf}) async {
  final dir = await Directory.systemTemp.createTemp('quotation_service_test_');
  addTearDown(() => dir.delete(recursive: true));
  return _Harness(dir, httpClient: httpClient, sessionOf: sessionOf);
}

/// Counts the process-wide refresh signals the service emits.
class _Signals {
  _Signals() {
    _sub = CoreEntityMutationNotifier.changes.listen((_) => count++);
  }
  int count = 0;
  late final StreamSubscription<void> _sub;
  Future<void> close() => _sub.cancel();
}

void main() {
  group('aggregate', () {
    test('a new Quotation id is a fresh UUID v4 every time', () async {
      final h = await _harness();
      final a = h.service.generateNewQuotationId();
      final b = h.service.generateNewQuotationId();
      expect(Uuid.isValidUUID(fromString: a), isTrue);
      expect(a, isNot(b));
    });

    test('save passes the id and expected version through and refreshes lists',
        () async {
      final h = await _harness();
      final signals = _Signals();
      addTearDown(signals.close);

      final created = await h.service.saveQuotation(_model(), quotationId: _q);
      expect(h.remote.lastSavedId, _q);
      expect(h.remote.lastExpectedVersion, isNull);
      expect(created.outcome, 'created');

      final updated = await h.service
          .saveQuotation(_model(), quotationId: _q, expectedVersion: 3);
      expect(h.remote.lastExpectedVersion, 3);
      expect(updated.version, 4);
      expect(signals.count, 2);
    });

    test('a failed save does not signal a refresh and surfaces the failure',
        () async {
      final h = await _harness();
      h.remote.saveError =
          const QuotationException(QuotationFailure.versionConflict);
      final signals = _Signals();
      addTearDown(signals.close);

      await expectLater(
        h.service.saveQuotation(_model(), quotationId: _q, expectedVersion: 1),
        throwsA(isA<QuotationException>().having(
            (e) => e.failure, 'failure', QuotationFailure.versionConflict)),
      );
      expect(signals.count, 0);
    });

    test('batched mutations send one refresh after the last one', () async {
      final h = await _harness();
      final signals = _Signals();
      addTearDown(signals.close);
      final pdf = await h.generatedPdf();

      await h.service.batchMutations(() async {
        await h.service.saveQuotation(_model(), quotationId: _q);
        expect(signals.count, 0, reason: 'held back until the batch ends');
        await h.service.publishPdf(
            quotationId: _q, pdf: pdf, expectedMediaId: null);
        expect(signals.count, 0);
      });

      expect(signals.count, 1);
    });

    test('a batch that changed nothing sends no refresh, and an error still ends it',
        () async {
      final h = await _harness();
      final signals = _Signals();
      addTearDown(signals.close);

      h.remote.saveError =
          const QuotationException(QuotationFailure.versionConflict);
      await expectLater(
        h.service.batchMutations(() =>
            h.service.saveQuotation(_model(), quotationId: _q)),
        throwsA(isA<QuotationException>()),
      );
      expect(signals.count, 0);

      h.remote.saveError = null;
      await expectLater(
        h.service.batchMutations(() async {
          await h.service.saveQuotation(_model(), quotationId: _q);
          throw StateError('later step failed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(signals.count, 1, reason: 'the saved aggregate is still announced');

      await h.service.saveQuotation(_model(), quotationId: _q);
      expect(signals.count, 2, reason: 'outside a batch every mutation signals');
    });

    test('the list is the backend stream (Supabase mode)', () async {
      final h = await _harness();
      final first = h.service.getUserQuotations().first;
      h.remote.stream.add([_model()]);
      expect((await first).single.propertyTitle, 'Villa');
    });

    test('delete is the soft path, forgets this device\'s PDF copy and refreshes',
        () async {
      final h = await _harness();
      await h.cached(_q, _pdfA).writeAsBytes(_pdfBytes);
      final other = File('${h.dir.path}${Platform.pathSeparator}'
          'quotation_other-quotation_$_pdfA.pdf');
      await other.writeAsBytes(_pdfBytes);
      final signals = _Signals();
      addTearDown(signals.close);

      await h.service.deleteQuotation(_q);

      expect(h.remote.calls, ['softDelete:$_q']);
      expect(await h.cached(_q, _pdfA).exists(), isFalse);
      expect(await other.exists(), isTrue,
          reason: 'only this Quotation\'s copies are removed');
      expect(signals.count, 1);
    });
  });

  group('publishing the PDF', () {
    test('binds the PDF, then keeps it as this device\'s copy of that media id',
        () async {
      final h = await _harness();
      final pdf = await h.generatedPdf();
      final signals = _Signals();
      addTearDown(signals.close);
      // An earlier unencrypted copy of this Quotation in the documents
      // folder, and one of another Quotation.
      final older = h.cached(_q, _pdfB)..writeAsBytesSync(_pdfBytes);
      final another = h.cached('3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a45', _pdfA)
        ..writeAsBytesSync(_pdfBytes);

      final binding = await h.service
          .publishPdf(quotationId: _q, pdf: pdf, expectedMediaId: _pdfA);
      expect(older.existsSync(), isFalse,
          reason: 'its plaintext copies go once the encrypted one is in place');
      expect(another.existsSync(), isTrue);

      expect(h.transport.calls,
          ['authorize:quotation_pdf:$_pdfA', 'upload', 'confirm:quotation_pdf']);
      expect(binding.resultingVersion, 4);
      // Q-2c-1b: kept encrypted for this account, not as a plain file in
      // the (backed-up) documents folder.
      expect(await h.vault.read('u', _q, binding.mediaObjectId), _pdfBytes);
      expect(await h.cached(_q, binding.mediaObjectId).exists(), isFalse);
      expect(await pdf.exists(), isFalse, reason: 'the generated file is consumed');
      expect(signals.count, 1);
    });

    test(
        'a session change during the upload: bound, but kept for no one '
        '(Q-2c-1b)', () async {
      var session = 's1';
      final h = await _harness(sessionOf: () => session);
      h.transport.onUpload = () => session = 's2';
      final pdf = await h.generatedPdf();

      final binding = await h.service
          .publishPdf(quotationId: _q, pdf: pdf, expectedMediaId: _pdfA);

      expect(await h.vault.versionsOf('u', _q), isEmpty);
      expect(await h.cached(_q, binding.mediaObjectId).exists(), isFalse);
      expect(await pdf.exists(), isFalse, reason: 'never left behind');
    });

    test('a failed upload keeps nothing in the cache and binds nothing', () async {
      final h = await _harness();
      h.transport.uploadError =
          const QuotationMediaException(QuotationMediaFailure.interrupted);
      final pdf = await h.generatedPdf();

      await expectLater(
        h.service.publishPdf(quotationId: _q, pdf: pdf, expectedMediaId: _pdfA),
        throwsA(isA<QuotationMediaException>()),
      );

      expect(h.transport.calls, ['authorize:quotation_pdf:$_pdfA', 'upload']);
      final cached = h.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('quotation_${_q}_'));
      expect(cached, isEmpty);
      expect(await h.vault.versionsOf('u', _q), isEmpty);
    });

    test('a slot that moved is re-read from the server and retried once',
        () async {
      final h = await _harness();
      h.transport.authorizeScript.add(const QuotationMediaException(
          QuotationMediaFailure.staleReplacement,
          statusCode: 409));
      h.remote.mediaState =
          const QuotationMediaState(version: 6, pdfMediaId: _pdfB);
      final pdf = await h.generatedPdf();

      await h.service
          .publishPdf(quotationId: _q, pdf: pdf, expectedMediaId: _pdfA);

      expect(h.remote.calls, contains('getMediaState'));
      expect(
        h.transport.calls.where((c) => c.startsWith('authorize')).toList(),
        ['authorize:quotation_pdf:$_pdfA', 'authorize:quotation_pdf:$_pdfB'],
      );
    });
  });

  group('opening a PDF', () {
    test('this device\'s copy of the exact media object opens with no network',
        () async {
      final h = await _harness();
      // Q-2c-1b: this device's copy is the account's encrypted one.
      await h.vault.store('u', _q, _pdfA, Uint8List.fromList(_pdfBytes));

      final file = await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));

      expect(await file.readAsBytes(), _pdfBytes);
      expect(QuotationPdfVault.isViewingCopy(file.path, h.dir.path), isTrue);
      expect(h.transport.fetchSignedCalls, 0);
    });

    test(
        'a plaintext copy an earlier version left is never opened in its '
        'place (final review R1)', () async {
      final h = await _harness(
        httpClient:
            MockClient((_) async => http.Response.bytes(_pdfBytes, 200)),
      );
      h.transport.signed = QuotationSignedMedia(
        quotationPdf: SignedQuotationMedia(
          mediaObjectId: _pdfA,
          contentType: 'application/pdf',
          url: 'https://signed.example/get',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );
      await h
          .cached(_q, _pdfA)
          .writeAsBytes('%PDF-1.4\nforged\n%%EOF\n'.codeUnits);

      final file = await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));

      expect(await file.readAsBytes(), _pdfBytes, reason: 'the server\'s copy');
      expect(h.transport.fetchSignedCalls, 1);
    });

    test('without a copy it downloads once through a fresh signed link and caches it',
        () async {
      final downloads = <Uri>[];
      final h = await _harness(
        httpClient: MockClient((request) async {
          downloads.add(request.url);
          return http.Response.bytes(_pdfBytes, 200);
        }),
      );
      h.transport.signed = QuotationSignedMedia(
        quotationPdf: SignedQuotationMedia(
          mediaObjectId: _pdfA,
          contentType: 'application/pdf',
          url: 'https://signed.example/get?X-Amz-Signature=abc',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );

      final file = await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));

      expect(await file.readAsBytes(), _pdfBytes);
      // Q-2c-1b: kept encrypted under the stable media id; what opens is a
      // temporary viewing copy, never named by the signed URL.
      expect(await h.vault.read('u', _q, _pdfA), _pdfBytes);
      expect(QuotationPdfVault.isViewingCopy(file.path, h.dir.path), isTrue);
      expect(await h.cached(_q, _pdfA).exists(), isFalse);
      expect(downloads, hasLength(1));
      expect(file.path.contains('X-Amz'), isFalse);

      // The second open is local: no new signed link, no new download.
      await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));
      expect(h.transport.fetchSignedCalls, 1);
      expect(downloads, hasLength(1));
    });

    test('a PDF regenerated elsewhere wins over an older list row', () async {
      final h = await _harness(
        httpClient: MockClient((_) async => http.Response.bytes(_pdfBytes, 200)),
      );
      h.transport.signed = QuotationSignedMedia(
        quotationPdf: SignedQuotationMedia(
          mediaObjectId: _pdfB,
          contentType: 'application/pdf',
          url: 'https://signed.example/get',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );

      // The list row still names the previous PDF (_pdfA); this device holds
      // no copy of it, and the server's current PDF is _pdfB.
      final file = await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));

      // Q-2c-1b: the server's current PDF is what is kept and opened.
      expect(await h.vault.read('u', _q, _pdfB), _pdfBytes);
      expect(await h.vault.versionsOf('u', _q), {_pdfB});
      expect(await file.readAsBytes(), _pdfBytes);
    });

    test('an expired or failing download is a clean failure and caches nothing',
        () async {
      final h = await _harness(
        httpClient: MockClient((_) async => http.Response('denied', 403)),
      );
      h.transport.signed = QuotationSignedMedia(
        quotationPdf: SignedQuotationMedia(
          mediaObjectId: _pdfA,
          contentType: 'application/pdf',
          url: 'https://signed.example/get?X-Amz-Signature=expired',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );

      Object? caught;
      try {
        await h.service.resolvePdfFile(_model(pdfMediaId: _pdfA));
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<QuotationMediaException>());
      expect((caught! as QuotationMediaException).failure,
          QuotationMediaFailure.unavailable);
      expect(caught.toString().contains('expired'), isFalse,
          reason: 'the signed URL never reaches an error');
      expect(await h.cached(_q, _pdfA).exists(), isFalse);
      expect(await h.vault.versionsOf('u', _q), isEmpty);
    });

    test('a Quotation with no bound PDF cannot be opened', () async {
      final h = await _harness();
      await expectLater(
        h.service.resolvePdfFile(_model()),
        throwsA(isA<QuotationMediaException>()),
      );
      expect(h.transport.fetchSignedCalls, 0);
    });
  });

  group('office logo', () {
    test('a signed logo URL is fetched on demand and only when one is bound',
        () async {
      final h = await _harness();
      expect(await h.service.signedOfficeLogo(_q), isNull);

      h.transport.signed = QuotationSignedMedia(
        officeLogo: SignedQuotationMedia(
          mediaObjectId: _pdfA,
          contentType: 'image/png',
          url: 'https://signed.example/logo',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );
      expect((await h.service.signedOfficeLogo(_q))!.url,
          'https://signed.example/logo');
    });

    test('removing the logo goes through the trusted route and refreshes lists',
        () async {
      final h = await _harness();
      final signals = _Signals();
      addTearDown(signals.close);

      final removal = await h.service
          .removeOfficeLogo(quotationId: _q, expectedMediaId: _pdfA);

      expect(h.transport.calls, ['remove:office_logo']);
      expect(removal.resultingVersion, 5);
      expect(signals.count, 1);
    });
  });
}
