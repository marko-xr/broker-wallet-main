// The Media Worker operations Toolkit cloud documents consist of, as a seam: the
// coordinator, the repository and the download service are exercised against a
// fake; the app uses [R2ToolkitDocumentService].
//
// Every call is bound to ONE account (the transport's `accountId`). If the
// signed-in account is not that one, a call fails with
// [ToolkitFailure.accountChanged] before anything is sent, so a document of one
// account can never be authorized, uploaded or listed under another.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';

/// Why a Toolkit document operation did not complete. Fixed categories: the
/// Worker's free text, URLs, keys and file names never reach an exception.
enum ToolkitFailure {
  notConfigured,
  notSignedIn,

  /// The signed-in account is not the one this operation belongs to.
  accountChanged,

  /// The access token was refused (expired). Refresh it and try again.
  unauthorized,

  /// The Worker answered 403 with no stable code. On a staging Worker that is its
  /// access gate refusing a request without the right key; it says nothing about
  /// the document, which stays on the phone and is tried again.
  forbidden,

  /// The Worker answered 404 with no stable code: the Toolkit routes are not
  /// enabled on that Worker (production ships them off) or the address is wrong.
  /// It says nothing about the document.
  routeUnavailable,

  /// Another phone signed in to this account. Nothing may be sent from this
  /// session any more (Single Active Device).
  sessionSuperseded,

  /// Offline, unreachable, a server error or a session check that could not be
  /// answered. Retry later.
  unavailable,

  /// A timeout or a connection cut mid-transfer. Retry later.
  interrupted,

  /// Too many requests; wait (see `retryAfter`).
  rateLimited,
  tooManyPending,
  deletionInProgress,

  /// Over the per-document size limit.
  tooLarge,

  /// Only PDFs of the four tools are accepted.
  unsupported,
  storageLimit,
  documentLimit,

  /// The Worker refused the request as malformed.
  invalidRequest,

  /// The bytes have not arrived at the confirmation step.
  uploadIncomplete,

  /// The signed upload was refused, or the stored bytes were rejected.
  uploadRejected,
  typeMismatch,

  /// The id was used for a different file, or belongs to someone else.
  idConflict,
  documentDeleted,
  documentNotFound,
  staleVersion,

  /// The id has no record in the account and the device made the document before
  /// the account's deletion-history window: it may be a deleted document whose
  /// tombstone was purged. It is NOT re-created until the user explicitly
  /// acknowledges (authorize with `acknowledgeStale`).
  staleDocument,

  /// The cloud record exists but its file is missing from storage.
  objectMissing,

  /// The cloud file no longer matches its record.
  objectChanged,
  invalidResponse,

  /// The local file is missing or unreadable.
  fileUnavailable,

  /// Not enough free space on the phone.
  insufficientStorage,

  /// A downloaded or local file does not match its recorded size or hash.
  integrityMismatch,
  unknown;

  /// Whether trying the same operation again later can succeed without the user
  /// changing anything.
  bool get isRetryable => switch (this) {
        unavailable ||
        interrupted ||
        rateLimited ||
        tooManyPending ||
        unauthorized ||
        uploadIncomplete ||
        uploadRejected ||
        objectMissing =>
          true,
        _ => false,
      };

  /// Whether this document will not upload as it is, whatever is retried.
  bool get rejectsDocument => switch (this) {
        tooLarge ||
        unsupported ||
        storageLimit ||
        documentLimit ||
        typeMismatch ||
        idConflict ||
        fileUnavailable ||
        integrityMismatch ||
        staleDocument ||
        deletionInProgress ||
        invalidRequest =>
          true,
        _ => false,
      };
}

class ToolkitDocumentException implements Exception {
  const ToolkitDocumentException(
    this.failure, {
    this.statusCode,
    this.workerCode,
    this.retryAfter,
    this.currentTitle,
    this.currentVersion,
  });

  final ToolkitFailure failure;
  final int? statusCode;

  /// The Worker's stable `code`, when it sent one.
  final String? workerCode;

  /// How long the Worker asked the caller to wait.
  final Duration? retryAfter;

  /// For [ToolkitFailure.staleVersion]: the title and version now on record.
  final String? currentTitle;
  final int? currentVersion;

  @override
  String toString() => 'ToolkitDocumentException($failure)';
}

/// What `authorize` answered.
@immutable
class ToolkitUploadAuthorization {
  const ToolkitUploadAuthorization.pending({
    required this.documentId,
    required String this.presignedUrl,
    this.uploadHeaders = const {},
  }) : alreadyConfirmed = false;

  const ToolkitUploadAuthorization.alreadyConfirmed({required this.documentId})
      : presignedUrl = null,
        uploadHeaders = const {},
        alreadyConfirmed = true;

  final String documentId;

  /// The short-lived signed PUT. Transport only: never stored or logged.
  final String? presignedUrl;

  /// Headers the PUT must carry exactly: they are part of the signature. Today only
  /// `If-None-Match: *`, which makes the signed URL write-once.
  final Map<String, String> uploadHeaders;

  /// The document is already in the cloud: there is nothing to upload.
  final bool alreadyConfirmed;
}

@immutable
class ToolkitConfirmation {
  const ToolkitConfirmation({
    required this.version,
    this.alreadyConfirmed = false,
    this.sha256Verified = false,
  });

  final int version;
  final bool alreadyConfirmed;

  /// The Worker hashed the stored object and it matched the device's digest.
  final bool sha256Verified;
}

@immutable
class ToolkitRenameResult {
  const ToolkitRenameResult({required this.title, required this.version});

  final String title;
  final int version;
}

@immutable
class ToolkitRemoveResult {
  const ToolkitRemoveResult({
    this.alreadyRemoved = false,
    this.cleanupPending = false,
  });

  /// The server had no live record (already deleted, or never uploaded).
  final bool alreadyRemoved;

  /// The record is gone for every read; the server is still finishing the
  /// removal of the stored file.
  final bool cleanupPending;
}

@immutable
class ToolkitRemoteStatuses {
  const ToolkitRemoteStatuses(this.byId);

  /// Every id asked about, with what the server knows.
  final Map<String, ToolkitRemoteState> byId;
}

abstract interface class ToolkitDocumentTransport {
  /// The account this transport serves.
  String get accountId;

  Future<ToolkitUploadAuthorization> authorize({
    required String documentId,
    required ToolkitDocumentType type,
    required ToolkitContentType contentType,
    required String title,
    required int contentLength,
    required String contentSha256,
    required DateTime sourceCreatedAt,
    int? pageCount,
    bool acknowledgeStale = false,
  });

  /// PUTs [file] to the signed [presignedUrl], sending [headers] as signed. Returns
  /// normally also when the object already exists (the write-once PUT answers 412): the
  /// confirm then decides whether that object is the right one.
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required ToolkitContentType contentType,
    Map<String, String> headers = const {},
  });

  Future<ToolkitConfirmation> confirm({required String documentId});

  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit,
    ToolkitDocumentType? type,
  });

  Future<ToolkitRemoteStatuses> statuses(List<String> documentIds);

  Future<ToolkitDownloadTicket> downloadTicket(String documentId);

  /// Streams the signed [url] into [target], refusing more than [maxBytes].
  Future<void> downloadToFile({
    required String url,
    required File target,
    required int maxBytes,
  });

  /// Renames; [expectedVersion] is the version the caller last saw. A stale one
  /// throws [ToolkitFailure.staleVersion] carrying the current title and version.
  Future<ToolkitRenameResult> rename({
    required String documentId,
    required String title,
    required int expectedVersion,
  });

  Future<ToolkitRemoveResult> remove({required String documentId});
}
