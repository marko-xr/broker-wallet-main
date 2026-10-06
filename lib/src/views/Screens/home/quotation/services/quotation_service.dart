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
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_workflow.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:http/http.dart' as http;
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
  }) : this._(
          remote ?? SupabaseQuotationService(),
          mediaTransport ?? R2QuotationMediaService(),
          pdfCache ?? QuotationPdfCache(),
          httpClient ?? http.Client(),
          uuid ?? const Uuid(),
        );

  QuotationService._(
    this._remote,
    this._transport,
    this._pdfCache,
    this._http,
    this._uuid,
  ) : _media = QuotationMediaWorkflow(_transport);

  final QuotationRemote _remote;
  final QuotationMediaTransport _transport;
  final QuotationMediaWorkflow _media;
  final QuotationPdfCache _pdfCache;
  final http.Client _http;
  final Uuid _uuid;

  static const Duration _downloadTimeout = Duration(seconds: 60);

  int _mutationBatchDepth = 0;
  bool _mutationSignalPending = false;

  /// Tells the lists and counts to refresh. Inside [batchMutations] the signal
  /// is held back so one save sends one refresh instead of one per step.
  void _signalMutation() {
    if (_mutationBatchDepth > 0) {
      _mutationSignalPending = true;
    } else {
      CoreEntityMutationNotifier.notify();
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
        CoreEntityMutationNotifier.notify();
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
  Future<void> deleteQuotation(String quotationId) async {
    await _remote.softDelete(quotationId);
    await _pdfCache.purge(quotationId);
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
    final binding = await _media.uploadPdf(
      quotationId: quotationId,
      file: pdf,
      expectedMediaId: expectedMediaId,
      currentExpected: () async =>
          (await _remote.getMediaState(quotationId))?.pdfMediaId,
    );
    try {
      await _pdfCache.adopt(pdf, quotationId, binding.mediaObjectId);
    } catch (_) {
      // The PDF is bound; a missing local copy is fetched on first open. The
      // generated file is private user data and is not left behind.
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
  Future<File> resolvePdfFile(QuotationModel quotation) async {
    final quotationId = quotation.id;
    final boundId = quotation.pdfMediaId;
    if (quotationId == null || boundId == null || boundId.isEmpty) {
      throw const QuotationMediaException(QuotationMediaFailure.unknown);
    }
    final cached = await _pdfCache.existing(quotationId, boundId);
    if (cached != null) return cached;

    final signed = await _transport.fetchSigned(quotationId);
    final pdf = signed.quotationPdf;
    if (pdf == null) {
      throw const QuotationMediaException(QuotationMediaFailure.unknown);
    }
    // The server's current PDF wins over a possibly older list row.
    final current = await _pdfCache.existing(quotationId, pdf.mediaObjectId);
    if (current != null) return current;

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
    return _pdfCache.write(quotationId, pdf.mediaObjectId, response.bodyBytes);
  }

  /// A short-lived signed URL for the bound office logo, or null when there is
  /// none. Used immediately to draw the PDF and never stored.
  Future<SignedQuotationMedia?> signedOfficeLogo(String quotationId) async {
    final signed = await _transport.fetchSigned(quotationId);
    return signed.officeLogo;
  }
}
