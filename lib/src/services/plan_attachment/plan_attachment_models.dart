// The land / plot plan (Arabic: مخطط الأرض / مخطط القطعة) of an Offer or an Owner
// record, as the app knows it.
//
// One plan per record: an image, or a PDF / DOC / DOCX document. It is its own
// attachment, never an item of the record's photo and video gallery, and it is
// identified only by its stable media id: a signed link is transport that lives
// in memory for a few minutes, and the storage key is never part of any of
// these types.

import 'package:flutter/foundation.dart';

/// The records a plan can belong to, each with its own Media Worker routes.
/// The Worker refuses a plan under the wrong record or the wrong kind of
/// record, so neither can reach the other's file.
enum PlanParent {
  offer(routePrefix: '/offer-plan', idField: 'offerId'),
  owner(routePrefix: '/owner-plan', idField: 'ownerRecordId');

  const PlanParent({required this.routePrefix, required this.idField});

  /// `<prefix>/authorize`, `<prefix>/confirm`, `<prefix>` (read) and
  /// `<prefix>/remove`.
  final String routePrefix;

  /// The request field (and read query parameter) naming the record.
  final String idField;
}

/// The content types a plan may have; the same table as the Worker's
/// `PLAN_MEDIA_TYPES` and the database's `plan_attachment_rules`.
abstract final class PlanContentTypes {
  static const String jpeg = 'image/jpeg';
  static const String png = 'image/png';
  static const String webp = 'image/webp';
  static const String pdf = 'application/pdf';
  static const String doc = 'application/msword';
  static const String docx =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static const Set<String> images = {jpeg, png, webp};
  static const Set<String> all = {jpeg, png, webp, pdf, doc, docx};

  /// The file extension a plan of [contentType] is stored and shared with.
  static String? extensionOf(String contentType) => switch (contentType) {
        PlanContentTypes.jpeg => 'jpg',
        PlanContentTypes.png => 'png',
        PlanContentTypes.webp => 'webp',
        PlanContentTypes.pdf => 'pdf',
        PlanContentTypes.doc => 'doc',
        PlanContentTypes.docx => 'docx',
        _ => null,
      };
}

/// What a plan file is, which decides how it is shown and opened.
enum PlanAttachmentKind {
  /// A photo or scan: shown in the app's full-screen image viewer.
  image,

  /// A PDF: opened in Broker Wallet's own PDF viewer.
  pdf,

  /// A Word document (DOC or DOCX). There is no in-app Word renderer: it is
  /// opened by another app on the phone, or shared.
  word;

  bool get isDocument => this != image;

  /// The kind of an accepted plan content type; null for anything else.
  static PlanAttachmentKind? fromContentType(String? contentType) =>
      switch (contentType) {
        PlanContentTypes.jpeg ||
        PlanContentTypes.png ||
        PlanContentTypes.webp =>
          PlanAttachmentKind.image,
        PlanContentTypes.pdf => PlanAttachmentKind.pdf,
        PlanContentTypes.doc ||
        PlanContentTypes.docx =>
          PlanAttachmentKind.word,
        _ => null,
      };
}

/// The plan a record has on the server.
///
/// [signedUrl] is transport only: it is kept in memory, is never persisted or
/// shown, and stops working at [signedUrlExpiresAt].
@immutable
class PlanAttachmentRef {
  const PlanAttachmentRef({
    required this.mediaObjectId,
    required this.kind,
    required this.contentType,
    this.displayName,
    this.byteLength,
    this.signedUrl,
    this.signedUrlExpiresAt,
  });

  /// The plan's stable identity.
  final String mediaObjectId;
  final PlanAttachmentKind kind;
  final String contentType;

  /// The file's own name as the user chose it (never a storage key).
  final String? displayName;
  final int? byteLength;
  final String? signedUrl;
  final DateTime? signedUrlExpiresAt;

  /// Whether [signedUrl] is still good for at least [margin] longer.
  bool hasFreshUrl(DateTime now,
      {Duration margin = const Duration(seconds: 30)}) {
    final url = signedUrl;
    final expiresAt = signedUrlExpiresAt;
    if (url == null || url.isEmpty || expiresAt == null) return false;
    return expiresAt.isAfter(now.add(margin));
  }

  /// The same plan without its (possibly expired) link.
  PlanAttachmentRef withoutUrl() => PlanAttachmentRef(
        mediaObjectId: mediaObjectId,
        kind: kind,
        contentType: contentType,
        displayName: displayName,
        byteLength: byteLength,
      );

  @override
  bool operator ==(Object other) =>
      other is PlanAttachmentRef &&
      other.mediaObjectId == mediaObjectId &&
      other.kind == kind &&
      other.contentType == contentType &&
      other.displayName == displayName &&
      other.byteLength == byteLength &&
      other.signedUrl == signedUrl &&
      other.signedUrlExpiresAt == signedUrlExpiresAt;

  @override
  int get hashCode => Object.hash(mediaObjectId, kind, contentType, displayName,
      byteLength, signedUrl, signedUrlExpiresAt);
}

/// A file the user chose for a plan, screened and waiting to be saved.
///
/// [mediaObjectId] is generated once, when the file is accepted, and is this
/// upload's identity for good: authorize, upload and confirm are all idempotent
/// on it, so retrying can never create a second object.
@immutable
class PlanAttachmentDraft {
  const PlanAttachmentDraft({
    required this.mediaObjectId,
    required this.path,
    required this.kind,
    required this.contentType,
    required this.byteLength,
    this.displayName,
    this.ownedTempPath,
  });

  final String mediaObjectId;

  /// The file to upload: the picked file, or its JPEG conversion.
  final String path;
  final PlanAttachmentKind kind;
  final String contentType;
  final int byteLength;
  final String? displayName;

  /// A file the app itself made for this draft (a HEIC photo converted to
  /// JPEG), which is deleted once the draft is uploaded or discarded. Never a
  /// file the user picked.
  final String? ownedTempPath;
}

/// Why a file was refused as a plan before anything was sent. Each value maps
/// to exactly one localized message.
enum PlanAttachmentRejection {
  unsupportedType('planAttachmentUnsupportedType'),
  imageTooLarge('planAttachmentImageTooLarge'),
  documentTooLarge('planAttachmentDocumentTooLarge'),
  unreadable('planAttachmentFileUnreadable');

  const PlanAttachmentRejection(this.messageKey);

  /// The ARB key of the user-facing explanation, in English and Arabic.
  final String messageKey;
}

/// Why a plan operation did not complete. A fixed category: never provider
/// text, a URL, an object key or a file path.
enum PlanAttachmentFailure {
  /// No active Supabase session.
  notSignedIn,

  /// The Worker refused the session (401).
  unauthorized,

  /// Another device signed in; the app signs this one out.
  sessionSuperseded,

  /// The record does not exist, is not this account's, or was deleted.
  parentNotFound,

  /// The plan is no longer what the caller expected: it changed elsewhere.
  staleReplacement,

  /// The file is not an accepted plan type.
  unsupportedType,
  imageTooLarge,
  documentTooLarge,

  /// The uploaded bytes are not the type that was declared.
  typeMismatch,

  /// The bytes had not arrived when confirm ran.
  uploadIncomplete,

  /// Private storage or the Worker refused this upload.
  uploadRejected,

  /// This upload was withdrawn or retired.
  mediaRemoved,

  /// Too many uploads are waiting for this record.
  tooManyPending,

  /// The connection dropped or timed out; nothing was confirmed.
  interrupted,

  /// The media service is unreachable or failing.
  unavailable,

  /// The media service answered with something this client cannot use.
  invalidResponse,

  /// The Worker address is not configured.
  notConfigured,

  /// The file could not be read from this phone.
  fileUnavailable,

  /// Anything else.
  unknown;

  /// Whether the same request may succeed if simply repeated.
  bool get isRetryable => switch (this) {
        PlanAttachmentFailure.interrupted ||
        PlanAttachmentFailure.unavailable ||
        PlanAttachmentFailure.uploadIncomplete ||
        PlanAttachmentFailure.uploadRejected ||
        PlanAttachmentFailure.staleReplacement ||
        PlanAttachmentFailure.tooManyPending ||
        PlanAttachmentFailure.unknown =>
          true,
        _ => false,
      };

  /// The ARB key of the sentence explaining this failure.
  String get messageKey => switch (this) {
        PlanAttachmentFailure.staleReplacement =>
          'planAttachmentChangedElsewhere',
        PlanAttachmentFailure.unsupportedType ||
        PlanAttachmentFailure.typeMismatch =>
          'planAttachmentUnsupportedType',
        PlanAttachmentFailure.imageTooLarge => 'planAttachmentImageTooLarge',
        PlanAttachmentFailure.documentTooLarge =>
          'planAttachmentDocumentTooLarge',
        PlanAttachmentFailure.fileUnavailable => 'planAttachmentFileUnreadable',
        PlanAttachmentFailure.parentNotFound => 'planAttachmentRecordMissing',
        _ => 'planAttachmentUploadFailed',
      };
}

class PlanAttachmentException implements Exception {
  const PlanAttachmentException(
    this.failure, {
    this.statusCode,
    this.workerCode,
  });

  final PlanAttachmentFailure failure;

  /// The Worker's HTTP status, when it answered.
  final int? statusCode;

  /// The Worker's stable `code`, when it sent one.
  final String? workerCode;

  bool get isRetryable => failure.isRetryable;

  @override
  String toString() => 'PlanAttachmentException(${failure.name}'
      '${statusCode == null ? '' : ', $statusCode'})';
}
