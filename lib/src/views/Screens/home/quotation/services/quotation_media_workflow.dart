// The upload / removal sequences for a Quotation's two private media slots.
//
//   upload:  authorize → signed PUT → trusted confirm
//
// The bound media is only ever replaced by the server's atomic confirm, so a
// failed or interrupted replacement leaves the previously bound logo or PDF
// exactly as it was. Nothing here marks media as bound until confirm answers.
//
// Every call is checked server-side against `expectedMediaId` (what the caller
// believes the slot holds), so a stale operation is refused rather than
// overwriting a newer one.

import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/services/image_signature_detector.dart';
import 'package:uuid/uuid.dart';

/// A local logo file that passed the pre-check.
class QuotationLogoCheck {
  const QuotationLogoCheck({required this.contentType, required this.length});

  final String contentType;
  final int length;
}

/// The result of a confirmed upload.
class QuotationMediaBinding {
  const QuotationMediaBinding({
    required this.mediaObjectId,
    this.previousMediaId,
    this.resultingVersion,
  });

  /// The media now bound to the slot.
  final String mediaObjectId;

  /// The media it replaced, if any.
  final String? previousMediaId;

  /// The Quotation's version after the slot changed, when the server said.
  final int? resultingVersion;
}

class QuotationMediaWorkflow {
  QuotationMediaWorkflow(this._transport, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final QuotationMediaTransport _transport;
  final Uuid _uuid;

  static const int maxLogoBytes = 10 * 1024 * 1024;
  static const int maxPdfBytes = 20 * 1024 * 1024;

  /// Checks a picked logo before anything is sent: JPEG, PNG or WebP by its
  /// real leading bytes (never its name), within the size limit.
  ///
  /// Throws [QuotationMediaException] with `unsupportedType` or `tooLarge`.
  static Future<QuotationLogoCheck> checkLogo(File file) async {
    final int length;
    final List<int> header;
    try {
      length = await file.length();
      final chunks = await file
          .openRead(0, ImageSignatureDetector.minimumBytesNeeded)
          .toList();
      header = [for (final chunk in chunks) ...chunk];
    } on FileSystemException {
      throw const QuotationMediaException(QuotationMediaFailure.unsupportedType);
    }
    final contentType = ImageSignatureDetector.detectMimeType(header);
    if (length < 1 || contentType == null) {
      throw const QuotationMediaException(QuotationMediaFailure.unsupportedType);
    }
    if (length > maxLogoBytes) {
      throw const QuotationMediaException(QuotationMediaFailure.tooLarge);
    }
    return QuotationLogoCheck(contentType: contentType, length: length);
  }

  /// Uploads [file] as the Quotation's office logo and binds it.
  ///
  /// [mediaObjectId] is this logo's identity. A caller that retries the same
  /// logo passes the same id: a retry after a lost confirm response then
  /// resolves to the already-bound media instead of failing as stale.
  Future<QuotationMediaBinding> uploadLogo({
    required String quotationId,
    required File file,
    required String? expectedMediaId,
    required String mediaObjectId,
    String? originalFileName,
  }) async {
    final check = await checkLogo(file);
    return _upload(
      quotationId: quotationId,
      role: QuotationMediaRole.officeLogo,
      file: file,
      contentType: check.contentType,
      length: check.length,
      expectedMediaId: expectedMediaId,
      mediaObjectId: mediaObjectId,
      originalFileName: originalFileName,
    );
  }

  /// Uploads the generated [file] as the Quotation's PDF and binds it.
  ///
  /// A PDF is derived from the Quotation as just saved, so when another
  /// operation changed the slot in between, [currentExpected] reads the slot as
  /// the server now holds it and the upload is retried once against that.
  Future<QuotationMediaBinding> uploadPdf({
    required String quotationId,
    required File file,
    required String? expectedMediaId,
    required Future<String?> Function() currentExpected,
  }) async {
    final length = await file.length();
    if (length < 1 || length > maxPdfBytes) {
      throw const QuotationMediaException(QuotationMediaFailure.tooLarge);
    }
    Future<QuotationMediaBinding> attempt(String? expected) => _upload(
          quotationId: quotationId,
          role: QuotationMediaRole.quotationPdf,
          file: file,
          contentType: 'application/pdf',
          length: length,
          expectedMediaId: expected,
          mediaObjectId: _uuid.v4(),
          originalFileName: 'quotation.pdf',
        );
    try {
      return await attempt(expectedMediaId);
    } on QuotationMediaException catch (error) {
      if (error.failure != QuotationMediaFailure.staleReplacement) rethrow;
      final fresh = await currentExpected();
      if (fresh == expectedMediaId) rethrow; // nothing changed: do not loop
      return attempt(fresh);
    }
  }

  /// Removes the bound office logo (idempotent when the slot is empty).
  Future<QuotationMediaRemoval> removeLogo({
    required String quotationId,
    required String? expectedMediaId,
  }) {
    return _transport.remove(
      quotationId: quotationId,
      role: QuotationMediaRole.officeLogo,
      expectedMediaId: expectedMediaId,
    );
  }

  Future<QuotationMediaBinding> _upload({
    required String quotationId,
    required QuotationMediaRole role,
    required File file,
    required String contentType,
    required int length,
    required String? expectedMediaId,
    required String mediaObjectId,
    String? originalFileName,
  }) async {
    final QuotationMediaAuthorization authorization;
    try {
      authorization = await _transport.authorize(
        quotationId: quotationId,
        role: role,
        expectedMediaId: expectedMediaId,
        mediaObjectId: mediaObjectId,
        contentType: contentType,
        contentLength: length,
        originalFileName: originalFileName,
      );
    } on QuotationMediaException catch (error) {
      if (error.failure == QuotationMediaFailure.staleReplacement) {
        // An earlier attempt with this same id may have been confirmed whose
        // answer was lost. Confirm is idempotent on the id: if it reports the
        // id already bound, this upload is done; otherwise the slot really did
        // change and the original refusal stands.
        final done = await _alreadyConfirmed(
            quotationId, role, mediaObjectId, expectedMediaId);
        if (done != null) return done;
      }
      rethrow;
    }

    if (authorization.isAlreadyReady) {
      return QuotationMediaBinding(mediaObjectId: mediaObjectId);
    }
    await _transport.uploadBytes(
      presignedUrl: authorization.presignedUrl!,
      file: file,
      contentType: contentType,
    );
    final confirmation = await _transport.confirm(
      quotationId: quotationId,
      role: role,
      mediaObjectId: mediaObjectId,
      expectedMediaId: expectedMediaId,
    );
    return QuotationMediaBinding(
      mediaObjectId: mediaObjectId,
      previousMediaId: confirmation.previousMediaId,
      resultingVersion: confirmation.resultingVersion,
    );
  }

  Future<QuotationMediaBinding?> _alreadyConfirmed(
    String quotationId,
    QuotationMediaRole role,
    String mediaObjectId,
    String? expectedMediaId,
  ) async {
    try {
      final confirmation = await _transport.confirm(
        quotationId: quotationId,
        role: role,
        mediaObjectId: mediaObjectId,
        expectedMediaId: expectedMediaId,
      );
      if (!confirmation.alreadyConfirmed) return null;
      return QuotationMediaBinding(
        mediaObjectId: mediaObjectId,
        previousMediaId: confirmation.previousMediaId,
        resultingVersion: confirmation.resultingVersion,
      );
    } on QuotationMediaException {
      return null;
    }
  }
}
