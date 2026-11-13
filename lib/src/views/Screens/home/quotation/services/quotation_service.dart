// The Quotation feature's service: persistence on the hosted Supabase
// aggregate (`save_quotation`) and private media on the Media Worker / R2.
//
// This replaces the former Firestore / Firebase Storage implementation. The
// Quotation is no longer stored in, or read from, Firebase: identity is the
// canonical Supabase session, the aggregate is saved atomically with an
// optimistic version, the office logo and the generated PDF are private media
// referenced only by stable media id, and a delete is the soft `deleted_at`
// path. Firebase mode (USE_SUPABASE_AUTH=false) no longer has a Quotation
// backend: the list is empty and saving fails.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_workflow.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:http/http.dart' as http;

import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:uuid/uuid.dart';

class QuotationService {
  /// Every collaborator is optional so the feature can be exercised without a
  /// network; the defaults are lazy and touch neither Supabase nor the disk
  /// until used.
  QuotationService({
    QuotationRemote? remote,
    QuotationMediaTransport? mediaTransport,
    QuotationPdfCache? pdfCache,
    http.Client? httpClient,
    Uuid? uuid,
    QuotationsLocalCache localCache = const QuotationsLocalCache(),
    String? Function()? currentUserId,
    String? Function()? sessionOf,
    QuotationPdfVault? pdfVault,
  }) : this._(
          remote ?? SupabaseQuotationService(),
          mediaTransport ?? R2QuotationMediaService(),
          pdfCache ?? QuotationPdfCache(),
          AppAccessPolicy.guard(httpClient ?? http.Client()),
          uuid ?? const Uuid(),
          localCache,
          currentUserId,
          sessionOf,
          pdfVault ?? QuotationPdfVault(),
        );

  QuotationService._(
    this._remote,
    this._transport,
    this._pdfCache,
    this._http,
    this._uuid,
    this._localCache,
    this._currentUserIdOverride,
    this._sessionOf,
    this._vault,
  ) : _media = QuotationMediaWorkflow(_transport);

  final QuotationRemote _remote;
  final QuotationMediaTransport _transport;
  final QuotationMediaWorkflow _media;

  /// The documents-folder copies of earlier versions (unencrypted): read
  /// for migration and as the fallback below, never written to again.
  final QuotationPdfCache _pdfCache;

  /// This device's encrypted, per-account copies (Q-2c-1b).
  final QuotationPdfVault _vault;
  final http.Client _http;
  final Uuid _uuid;
  final QuotationsLocalCache _localCache;
  final String? Function()? _currentUserIdOverride;

  /// The session a read or delete is made under; by default the app
  /// session's (see [localFirstList]).
  final String? Function()? _sessionOf;

  /// The canonical signed-in account, or null when there is none (or no
  /// auth repository yet).
  String? _currentUserId() {
    final override = _currentUserIdOverride;
    if (override != null) return override();
    try {
      return RepositoryProvider.instance.authRepository.currentUserId;
    } catch (_) {
      return null;
    }
  }

  static const Duration _downloadTimeout = Duration(seconds: 60);

  int _mutationBatchDepth = 0;
  bool _mutationSignalPending = false;

  /// Tells the lists and counts to refresh. Inside [batchMutations] the signal
  /// is held back so one save sends one refresh instead of one per step.
  void _signalMutation() {
    if (_mutationBatchDepth > 0) {
      _mutationSignalPending = true;
    } else {
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
    }
  }

  /// Runs [action], then sends a single refresh signal if any mutation inside
  /// it succeeded (including when [action] ends in an error). A Quotation save
  /// is up to three mutations (aggregate, logo, PDF); each signal makes every
  /// open list, Home and Search re-read from the backend.
  Future<T> batchMutations<T>(Future<T> Function() action) async {
    _mutationBatchDepth++;
    try {
      return await action();
    } finally {
      _mutationBatchDepth--;
      if (_mutationBatchDepth == 0 && _mutationSignalPending) {
        _mutationSignalPending = false;
        CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      }
    }
  }

  /// A new Quotation id. The client chooses it, so a create that is retried
  /// after a lost answer replays the same Quotation instead of making another.
  String generateNewQuotationId() => _uuid.v4();

  // -------------------------------------------------------------------------
  // Aggregate
  // -------------------------------------------------------------------------

  /// Creates ([expectedVersion] null) or updates the Quotation atomically.
  /// Throws [QuotationException] (version conflict, deleted, invalid data, …)
  /// or `QuotationValidationException` for a form that can never be saved.
  Future<QuotationSaveResult> saveQuotation(
    QuotationModel quotation, {
    required String quotationId,
    int? expectedVersion,
  }) async {
    final result = await _remote.save(
      quotation,
      quotationId: quotationId,
      expectedVersion: expectedVersion,
    );
    _signalMutation();
    return result;
  }

  /// The signed-in account's live Quotations, newest first, refreshed after
  /// every mutation in this process.
  Stream<List<QuotationModel>> getUserQuotations() {
    if (!SupabaseConfig.useSupabaseAuth) return Stream.value(const []);
    return _remote.watchQuotations();
  }

  /// The Quotations screen's list: this account's encrypted saved copy at
  /// once (when there is one), then the server's whole list
  /// ([getUserQuotations]), which replaces it and is saved for next time. A
  /// failed read keeps what is shown. The saved copy is a historical snapshot
  /// of server values for reading only: nothing is calculated, saved,
  /// generated or decided from it. [getUserQuotations] stays server-only.
  Stream<List<QuotationModel>> watchUserQuotationsLocalFirst() {
    if (!SupabaseConfig.useSupabaseAuth) return getUserQuotations();
    return localFirstList(
      // Each whole server list is also the evidence that moves this
      // account's earlier unencrypted PDFs into its encrypted store.
      server: () {
        // Viewing copies an earlier run left (a crash, or a share that never
        // said it ended) go at this run's first sweep (final review R3).
        unawaited(_vault.sweepViewingCopies().catchError((Object _) {}));
        return getUserQuotations().map((rows) {
          unawaited(_migrateQuietly(rows));
          return rows;
        });
      },
      cache: _localCache,
      currentUserId: _currentUserId,
      sessionOf: _sessionOf,
      isRetryable: isRetryableListFailure,
    );
  }

  /// A network failure of the Quotations list, worth reading again for: the
  /// list's own network category as well as the general ones.
  static bool isRetryableListFailure(Object error) =>
      isRetryableListError(error) ||
      (error is QuotationException &&
          error.failure == QuotationFailure.network);

  /// The whole Quotation, or null when it does not exist or was deleted.
  Future<QuotationModel?> getQuotationById(String quotationId) =>
      _remote.getQuotation(quotationId);

  /// The version and bound media ids as the server holds them now.
  Future<QuotationMediaState?> getMediaState(String quotationId) =>
      _remote.getMediaState(quotationId);

  /// The name the account gave a bound media object, or null when unknown.
  Future<String?> getMediaFileName(String mediaId) =>
      _remote.getMediaFileName(mediaId);

  /// Soft-deletes the Quotation and forgets this device's copy of its PDF.
  /// Once the server has confirmed the delete (and only then), the saved list
  /// remembers it, so it is never shown again offline.
  Future<void> deleteQuotation(String quotationId) async {
    await deleteThenRemember(
      cache: _localCache,
      id: quotationId,
      currentUserId: _currentUserId,
      sessionOf: _sessionOf,
      delete: () => _remote.softDelete(quotationId),
    );
    await _pdfCache.purge(quotationId);
    final uid = _currentUserId();
    if (uid != null && uid.isNotEmpty) {
      try {
        await _vault.purge(uid, quotationId);
      } catch (_) {}
    }
    _signalMutation();
  }

  // -------------------------------------------------------------------------
  // Private media
  // -------------------------------------------------------------------------

  /// Uploads and binds [file] as the office logo. See
  /// [QuotationMediaWorkflow.uploadLogo].
  Future<QuotationMediaBinding> uploadOfficeLogo({
    required String quotationId,
    required File file,
    required String? expectedMediaId,
    required String mediaObjectId,
    String? originalFileName,
  }) async {
    final binding = await _media.uploadLogo(
      quotationId: quotationId,
      file: file,
      expectedMediaId: expectedMediaId,
      mediaObjectId: mediaObjectId,
      originalFileName: originalFileName,
    );
    _signalMutation();
    return binding;
  }

  /// Removes the bound office logo.
  Future<QuotationMediaRemoval> removeOfficeLogo({
    required String quotationId,
    required String? expectedMediaId,
  }) async {
    final removal = await _media.removeLogo(
      quotationId: quotationId,
      expectedMediaId: expectedMediaId,
    );
    _signalMutation();
    return removal;
  }

  /// Uploads and binds the generated [pdf], then keeps it as this device's
  /// copy of exactly that media object. The generated file is consumed.
  Future<QuotationMediaBinding> publishPdf({
    required String quotationId,
    required File pdf,
    required String? expectedMediaId,
  }) async {
    final uid = _currentUserId();
    final sessionNow = _sessionOf ?? ListSessionCheck.currentSession;
    final session = sessionNow();
    final binding = await _media.uploadPdf(
      quotationId: quotationId,
      file: pdf,
      expectedMediaId: expectedMediaId,
      currentExpected: () async =>
          (await _remote.getMediaState(quotationId))?.pdfMediaId,
    );
    // The bound PDF becomes this account's encrypted copy (Q-2c-1b) — only
    // for the account and session that published it. Earlier unencrypted
    // copies of this Quotation go once it is in place. On any failure the
    // PDF stays bound and is fetched on first open. The generated file is
    // private user data and is never left behind.
    try {
      if (uid != null &&
          uid.isNotEmpty &&
          _currentUserId() == uid &&
          sessionNow() == session) {
        await _vault.store(
            uid, quotationId, binding.mediaObjectId, await pdf.readAsBytes());
        await _pdfCache.purge(quotationId);
        await _pdfCache.removeGenerated(quotationId);
      }
    } catch (_) {
      // Kept as before: nothing local, the bound PDF is fetched when opened.
    } finally {
      try {
        if (await pdf.exists()) await pdf.delete();
      } catch (_) {}
    }
    _signalMutation();
    return binding;
  }

  /// A local file for the Quotation's bound PDF: this device's copy of that
  /// exact media object when it has one, otherwise downloaded once through a
  /// fresh short-lived signed URL (which is never kept).
  ///
  /// Only the signed-in account's Quotation is opened (Q-2c-1): another
  /// account's, or none, is refused before any file or request. A download
  /// that ends under another account or session is neither kept nor opened.
  Future<File> resolvePdfFile(QuotationModel quotation) async {
    final quotationId = quotation.id;
    final boundId = quotation.pdfMediaId;
    if (quotationId == null || boundId == null || boundId.isEmpty) {
      throw const QuotationMediaException(QuotationMediaFailure.unknown);
    }
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) {
      throw const QuotationMediaException(QuotationMediaFailure.notSignedIn);
    }
    if (quotation.userId != uid) {
      throw const QuotationMediaException(QuotationMediaFailure.unauthorized);
    }
    final sessionNow = _sessionOf ?? ListSessionCheck.currentSession;
    final session = sessionNow();
    void stillTheReader() {
      if (_currentUserId() != uid || sessionNow() != session) {
        throw const QuotationMediaException(QuotationMediaFailure.notSignedIn);
      }
    }

    final local = await _localPdf(uid, quotationId, boundId, stillTheReader);
    if (local != null) return local;

    final signed = await _transport.fetchSigned(quotationId);
    stillTheReader();
    final pdf = signed.quotationPdf;
    if (pdf == null) {
      throw const QuotationMediaException(QuotationMediaFailure.unknown);
    }
    // The server's current PDF wins over a possibly older list row.
    final currentId = pdf.mediaObjectId;
    if (currentId != boundId) {
      final current =
          await _localPdf(uid, quotationId, currentId, stillTheReader);
      if (current != null) return current;
    }

    final http.Response response;
    try {
      response = await _http.get(Uri.parse(pdf.url)).timeout(_downloadTimeout);
    } on TimeoutException {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    } catch (_) {
      throw const QuotationMediaException(QuotationMediaFailure.unavailable);
    }
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      // Includes an expired link: the next call fetches a fresh one.
      throw QuotationMediaException(
        QuotationMediaFailure.unavailable,
        statusCode: response.statusCode,
      );
    }
    stillTheReader();
    // An authorized download of the current PDF: it becomes this account's
    // encrypted copy, replacing its other versions, and the earlier
    // unencrypted copies of this Quotation go.
    try {
      await _vault.store(uid, quotationId, currentId, response.bodyBytes);
    } catch (_) {
      throw const QuotationMediaException(QuotationMediaFailure.unavailable);
    }
    try {
      await _pdfCache.purge(quotationId);
      await _pdfCache.removeGenerated(quotationId);
    } catch (_) {}
    final view = await _localPdf(uid, quotationId, currentId, stillTheReader);
    if (view == null) {
      throw const QuotationMediaException(QuotationMediaFailure.unavailable);
    }
    return view;
  }

  /// A plain file of [uid]'s PDF [mediaId] to open: a viewing copy of its
  /// authentic encrypted copy, or null. Nothing else is ever opened: an
  /// unencrypted copy an earlier version left in the documents folder is
  /// not authenticated, so it is reached only through [migrateLegacyPdfs]
  /// on server evidence (final review R1); an encrypted copy that is not
  /// authentic (a lost key, damage) is not opened either. Either way the PDF
  /// then comes from the server.
  Future<File?> _localPdf(String uid, String quotationId, String mediaId,
      void Function() stillTheReader) async {
    final File? view;
    try {
      view = await _vault.openForViewing(uid, quotationId, mediaId);
    } catch (_) {
      return null;
    }
    if (view == null) return null;
    try {
      stillTheReader();
    } catch (_) {
      await _vault.release(view);
      rethrow;
    }
    return view;
  }

  /// Ends what [resolvePdfFile] opened: a viewing copy is removed; any other
  /// file is left as it is.
  Future<void> releasePdfFile(File file) async {
    try {
      await _vault.release(file);
    } catch (_) {}
  }

  Future<void> _migrateQuietly(List<QuotationModel> serverRows) async {
    try {
      await migrateLegacyPdfs(serverRows);
    } catch (_) {
      // Nothing is lost: an unmigrated file stays where it is.
    }
  }

  /// Moves this account's earlier unencrypted PDFs into its encrypted store,
  /// on the evidence of [serverRows] — a whole server list read for the
  /// signed-in account (Q-2c-1b, D-P2/D-P3). For each row of this account
  /// with a bound PDF, the documents-folder copy of exactly that media id is
  /// sealed, read back, compared and reopened; only then are this
  /// Quotation's unencrypted copies (that one, older versions and a
  /// generation leftover) removed. Left untouched: a file that does not look
  /// like a whole PDF, a Quotation whose store already holds another version
  /// (never put an older one beside it), a copy that differs from the
  /// encrypted one, rows of another account and anything not named by a row.
  /// Stops when the account or session changes. Safe to repeat after an
  /// interruption: a copy already sealed is compared, not sealed again.
  Future<void> migrateLegacyPdfs(List<QuotationModel> serverRows) async {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return;
    final sessionNow = _sessionOf ?? ListSessionCheck.currentSession;
    final session = sessionNow();
    bool still() => _currentUserId() == uid && sessionNow() == session;
    for (final row in serverRows) {
      if (!still()) return;
      final quotationId = row.id;
      final mediaId = row.pdfMediaId;
      if (row.userId != uid ||
          quotationId == null ||
          mediaId == null ||
          mediaId.isEmpty) {
        continue;
      }
      final legacy = await _pdfCache.existing(quotationId, mediaId);
      var sealed = await _vault.read(uid, quotationId, mediaId);
      if (sealed == null) {
        if (legacy == null) continue;
        if ((await _vault.versionsOf(uid, quotationId)).isNotEmpty) continue;
        final bytes = await legacy.readAsBytes();
        if (!_looksLikeWholePdf(bytes)) continue;
        if (!still()) return;
        try {
          await _vault.store(uid, quotationId, mediaId, bytes,
              replaceOthers: false);
        } catch (_) {
          continue; // the original stays; the next list tries again
        }
        sealed = await _vault.read(uid, quotationId, mediaId);
        if (sealed == null || !listEquals(sealed, bytes)) continue;
      } else if (legacy != null &&
          !listEquals(await legacy.readAsBytes(), sealed)) {
        continue; // not the same PDF: nothing is assumed, nothing removed
      }
      if (!still()) return;
      await _pdfCache.purge(quotationId);
      await _pdfCache.removeGenerated(quotationId);
    }
  }

  /// Starts as a PDF and ends with its end-of-file marker: not truncated.
  static bool _looksLikeWholePdf(List<int> bytes) {
    if (bytes.length < 16) return false;
    const head = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-
    for (var i = 0; i < head.length; i++) {
      if (bytes[i] != head[i]) return false;
    }
    final tail = latin1.decode(
        bytes.sublist(bytes.length > 1024 ? bytes.length - 1024 : 0),
        allowInvalid: true);
    return tail.contains('%%EOF');
  }

  /// A short-lived signed URL for the bound office logo, or null when there is
  /// none. Used immediately to draw the PDF and never stored.
  Future<SignedQuotationMedia?> signedOfficeLogo(String quotationId) async {
    final signed = await _transport.fetchSigned(quotationId);
    return signed.officeLogo;
  }
}
