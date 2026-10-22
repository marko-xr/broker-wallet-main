// The shared vocabulary of Toolkit cloud documents: the documents of Scanner,
// Combine PDFs, Images to PDF and Document Signature as account data. Every tool
// stores PDFs; the Scanner may also store its JPEG / PNG scans, as the original
// bytes.
//
// All four tools (Scanner, Combine PDFs, Images to PDF, Document Signature) keep
// their documents in the user's account as well as on the phone, in every build:
// the owner turned it on by default on 2026-10-21 (the app is not released and
// every account is a test account), and `--dart-define=TOOLKIT_CLOUD_DOCUMENTS=false`
// is the kill switch (see [ToolkitCloudDocumentsFeature.isActive]). The local
// store stays the working copy and works without a network.
//
// Identity: a document's id is the UUID its tool already gives it locally. It is
// the same id in the local store, the database row and the private object key,
// so a retry can never create a second copy and a copy can be matched across
// devices. The storage key is never part of these types.

import 'package:flutter/foundation.dart';

/// Whether the cloud document foundation may be used at all. Compile-time, ON
/// unless a build sets `--dart-define=TOOLKIT_CLOUD_DOCUMENTS=false` (the kill
/// switch for a build that must keep Toolkit documents on the phone only).
abstract final class ToolkitCloudDocumentsFeature {
  static const bool enabled = bool.fromEnvironment(
    'TOOLKIT_CLOUD_DOCUMENTS',
    defaultValue: true,
  );

  /// Whether the tools use the cloud in this build: every build (debug, profile
  /// and release) unless the kill switch is set. Only the staging address and
  /// gate key stay debug-only (see `R2Config.toolkitWorkerUrl`).
  static bool get isActive => enabled;
}

/// The tool a document came from. [wireName] is the Worker's and the
/// database's `document_type`; [localStoreRoot] is the folder name of that
/// tool's existing local store (`<base>/<root>/<account>/`), used only to
/// recognize files for the one-time migration of existing documents.
enum ToolkitDocumentType {
  scanner('scanner', 'scanner'),
  combinePdfs('combine_pdfs', 'combine_pdfs'),
  imageToPdf('image_to_pdf', 'image_to_pdf'),
  signature('signature', 'signature_pdfs');

  const ToolkitDocumentType(this.wireName, this.localStoreRoot);

  final String wireName;
  final String localStoreRoot;

  static ToolkitDocumentType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// The binary format of a stored document. Separate from the source tool
/// ([ToolkitDocumentType]): every tool produces PDFs, only the Scanner may also
/// store its JPEG / PNG scans, kept as the original bytes (nothing is converted).
/// [extension] is the one extension a file of this format is stored and exported
/// with; the server derives the object key from it and never from a client name.
enum ToolkitContentType {
  pdf('application/pdf', 'pdf', 250 * 1024 * 1024),
  jpeg('image/jpeg', 'jpg', 64 * 1024 * 1024),
  png('image/png', 'png', 64 * 1024 * 1024);

  const ToolkitContentType(this.mime, this.extension, this.hardMaxBytes);

  final String mime;
  final String extension;

  /// The size no configuration can exceed (the database enforces it too).
  final int hardMaxBytes;

  bool get isImage => this != pdf;

  /// Whether `tool` may store this format.
  bool allowedFor(ToolkitDocumentType tool) =>
      this == pdf || tool == ToolkitDocumentType.scanner;

  static ToolkitContentType? fromMime(Object? value) {
    for (final type in values) {
      if (type.mime == value) return type;
    }
    return null;
  }

  /// The format a file's leading bytes identify, or null.
  static ToolkitContentType? detect(List<int> head) {
    if (_isPdfHead(head)) return pdf;
    if (_startsWith(head, const [0xff, 0xd8, 0xff])) return jpeg;
    if (_startsWith(head, _pngSignature)) return png;
    return null;
  }

  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  ];
  static const List<int> _pngIend = [
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82, //
  ];

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _isPdfHead(List<int> b) =>
      b.length >= 8 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46 &&
      b[4] == 0x2d &&
      (b[5] == 0x31 || b[5] == 0x32) &&
      b[6] == 0x2e &&
      b[7] >= 0x30 &&
      b[7] <= 0x39;

  static int _u32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Whether [head] (the first bytes) and [tail] (the last min(size, 1024) bytes)
  /// of a file of [size] bytes are a complete container of this format. The same
  /// rule as the Worker's `hasValidFraming`: it proves the container is what it
  /// claims and is not truncated, not that the pages or pixels decode.
  bool hasValidFraming(List<int> head, List<int> tail, int size) {
    if (detect(head) != this) return false;
    switch (this) {
      case pdf:
        if (size < 16) return false;
        return String.fromCharCodes(tail).contains('%%EOF');
      case jpeg:
        if (size < 4) return false;
        var end = tail.length;
        var zeros = 0;
        while (end > 0 && tail[end - 1] == 0 && zeros < 16) {
          end--;
          zeros++;
        }
        return end >= 2 && tail[end - 2] == 0xff && tail[end - 1] == 0xd9;
      case png:
        if (size < 57 || head.length < 24) return false;
        if (_u32(head, 8) != 13 ||
            head[12] != 0x49 ||
            head[13] != 0x48 ||
            head[14] != 0x44 ||
            head[15] != 0x52) {
          return false;
        }
        final width = _u32(head, 16);
        final height = _u32(head, 20);
        if (width < 1 || height < 1 || width > 100000 || height > 100000) {
          return false;
        }
        if (tail.length < _pngIend.length) return false;
        for (var i = 0; i < _pngIend.length; i++) {
          if (tail[tail.length - _pngIend.length + i] != _pngIend[i]) {
            return false;
          }
        }
        return true;
    }
  }
}

/// Anti-abuse and storage-safety limits, mirrored from the Worker's defaults
/// (`TOOLKIT_LIMIT_DEFAULTS`) so the app can refuse an impossible document
/// before spending bandwidth. The server remains the authority, and its
/// configured limits are reported with the first page of the list. None of this
/// is a subscription quota.
abstract final class ToolkitDocumentLimits {
  // The RECOMMENDED initial profile, pending the owner's approval of the numbers.
  static const int defaultDocumentBytes = 50 * 1024 * 1024;
  static const int defaultImageBytes = 25 * 1024 * 1024;

  /// The ceiling no configuration can exceed (the database enforces it too).
  static const int hardDocumentBytes = 250 * 1024 * 1024;
  static const int defaultAccountBytes = 1024 * 1024 * 1024;
  static const int defaultAccountDocuments = 1000;
  static const int maxTitleLength = 200;
  static const int listPageSize = 50;
  static const int statusBatchSize = 50;

  /// The size limit for [type] (the default profile).
  static int defaultBytesFor(ToolkitContentType type) =>
      type.isImage ? defaultImageBytes : defaultDocumentBytes;
}

/// The one accepted spelling of a document id: a lower-case UUID, the form the
/// database and the Worker produce.
abstract final class ToolkitDocumentIds {
  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isCanonical(String? id) => id != null && _pattern.hasMatch(id);
}

/// What the server accepts as a title: 1 to 200 characters, no surrounding
/// space, no control characters and no bidi override or isolate controls.
abstract final class ToolkitDocumentTitles {
  static bool _isUnsafe(int rune) =>
      rune <= 0x1f ||
      rune == 0x7f ||
      (rune >= 0x202a && rune <= 0x202e) ||
      (rune >= 0x2066 && rune <= 0x2069);

  /// Null when [title] is acceptable, otherwise a short English reason (for
  /// logs and tests, never shown to users).
  static String? problemWith(String title) {
    if (title.isEmpty) return 'empty';
    if (title != title.trim()) return 'surrounding whitespace';
    if (title.runes.length > ToolkitDocumentLimits.maxTitleLength) {
      return 'too long';
    }
    if (title.runes.any(_isUnsafe)) return 'unsafe character';
    return null;
  }

  /// A title the server accepts, made from a local name: unsafe characters
  /// dropped, whitespace trimmed, cut to the limit, [fallback] when nothing is
  /// left. Arabic and other scripts, and the harmless direction marks, are kept.
  static String sanitize(String name, {String fallback = 'Document'}) {
    final kept = String.fromCharCodes(name.runes.where((r) => !_isUnsafe(r)));
    var title = kept.trim();
    if (title.runes.length > ToolkitDocumentLimits.maxTitleLength) {
      title = String.fromCharCodes(
        title.runes.take(ToolkitDocumentLimits.maxTitleLength),
      ).trim();
    }
    return title.isEmpty ? fallback : title;
  }
}

/// How the user-facing library should describe one document. Names follow the
/// product decision (SAVED_TO_CLOUD, SAVED_LOCALLY_PENDING_SYNC, ...); two
/// states are added that the failure model needs.
///
/// A cloud-save success is only ever shown for [savedToCloud] (or a document
/// whose copy is in the cloud), and [savedToCloud] is only ever set after the
/// server confirmed the stored bytes.
enum ToolkitDocumentSyncState {
  /// Verified in the cloud, with a verified local copy.
  savedToCloud,

  /// Saved on this phone only. NOT yet protected against reinstalling the app or
  /// losing the phone.
  savedLocallyPendingSync,

  /// Being uploaded (or its confirmation is pending).
  syncInProgress,

  /// The last attempt failed for a reason that may pass (offline, timeout, a
  /// busy server). It is retried with a growing delay, or by the user.
  syncFailedRetryable,

  /// Not uploadable as it is (too large, the cloud limit is reached, the file
  /// is not a valid PDF). Stays on this phone; retrying cannot help until the
  /// reason changes.
  syncRejected,

  /// In the cloud but not on this phone (a new phone, or a reinstall): it is
  /// downloaded, verified, when the user opens it.
  downloadRequired,

  /// A download or its verification failed; nothing damaged was kept.
  downloadFailed,

  /// The user deleted it; the removal has not been confirmed by the server yet.
  deletePending,

  /// Deleted from the account on another device. The local copy is kept until
  /// the user decides; it is never uploaded again.
  remoteDeleted;

  /// Safe in the cloud: the document survives losing this phone.
  bool get isCloudBacked =>
      this == savedToCloud ||
      this == downloadRequired ||
      this == downloadFailed;

  /// A copy of the file exists on this phone.
  bool get hasLocalCopy => this != downloadRequired && this != downloadFailed;

  /// Work is waiting to be done for this document.
  bool get needsSync =>
      this == savedLocallyPendingSync ||
      this == syncInProgress ||
      this == syncFailedRetryable ||
      this == deletePending;
}

/// What the server knows about a document the app asked about.
enum ToolkitRemoteState {
  /// Verified in the cloud.
  ready,

  /// An upload was authorized but is not confirmed.
  pending,

  /// Deleted (or being deleted). Never to be brought back.
  deleted,

  /// No record in this account: never uploaded, or a tombstone old enough to
  /// have been purged. This is NOT proof the document never existed.
  unknown;

  static ToolkitRemoteState? fromWire(Object? value) => switch (value) {
        'ready' => ready,
        'pending' => pending,
        'deleted' => deleted,
        _ => null,
      };
}

/// One document of the account, as the Worker lists it.
@immutable
class ToolkitDocumentMetadata {
  const ToolkitDocumentMetadata({
    required this.documentId,
    required this.type,
    required this.contentType,
    required this.title,
    required this.sizeBytes,
    required this.contentSha256,
    required this.sourceCreatedAt,
    required this.createdAt,
    required this.version,
    this.pageCount,
    this.sha256Verified = false,
  });

  final String documentId;

  /// The source tool.
  final ToolkitDocumentType type;

  /// The binary format (a separate field from the tool).
  final ToolkitContentType contentType;
  final String title;
  final int sizeBytes;
  final int? pageCount;

  /// Lower-case hex SHA-256 of the file as the DEVICE calculated it. A claim
  /// until proven: see [sha256Verified]. The app always checks a download
  /// against it.
  final String contentSha256;

  /// True only when the Worker itself hashed the stored object and found it equal
  /// to [contentSha256]. False means "device-declared only", not "wrong".
  final bool sha256Verified;

  /// When the device made the document (the device's own clock).
  final DateTime sourceCreatedAt;

  /// When the server recorded it.
  final DateTime createdAt;

  /// Changes on every server-side change; a rename names the version it saw.
  final int version;

  /// Reads one entry of the Worker's `documents` array. Strict: anything that
  /// is not exactly the contract throws a [FormatException].
  factory ToolkitDocumentMetadata.fromWorkerJson(Object? json) {
    if (json is! Map) throw const FormatException('document is not an object');
    final id = json['documentId'];
    final type = ToolkitDocumentType.fromWire(json['documentType']);
    final contentType = ToolkitContentType.fromMime(json['contentType']);
    final title = json['title'];
    final size = json['sizeBytes'];
    final version = json['version'];
    final pages = json['pageCount'];
    final sha = json['contentSha256'];
    final verified = json['sha256Verified'];
    final source = DateTime.tryParse('${json['sourceCreatedAt']}');
    final created = DateTime.tryParse('${json['createdAt']}');
    if (id is! String ||
        !ToolkitDocumentIds.isCanonical(id) ||
        type == null ||
        contentType == null ||
        !contentType.allowedFor(type) ||
        title is! String ||
        ToolkitDocumentTitles.problemWith(title) != null ||
        size is! int ||
        size < 1 ||
        size > contentType.hardMaxBytes ||
        version is! int ||
        version < 1 ||
        (pages != null && (pages is! int || pages < 1)) ||
        (contentType.isImage && pages != null && pages != 1) ||
        sha is! String ||
        !_sha256.hasMatch(sha) ||
        verified is! bool ||
        source == null ||
        created == null) {
      throw const FormatException('document does not match the contract');
    }
    return ToolkitDocumentMetadata(
      documentId: id,
      type: type,
      contentType: contentType,
      title: title,
      sizeBytes: size,
      pageCount: pages as int?,
      contentSha256: sha,
      sha256Verified: verified,
      sourceCreatedAt: source.toUtc(),
      createdAt: created.toUtc(),
      version: version,
    );
  }

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// The Worker's own spelling of this document, so a copy kept on the phone
  /// (see `ToolkitRemoteCache`) is read back by the same strict
  /// [ToolkitDocumentMetadata.fromWorkerJson] and can never be looser than the
  /// server's contract.
  Map<String, Object?> toWorkerJson() => <String, Object?>{
        'documentId': documentId,
        'documentType': type.wireName,
        'contentType': contentType.mime,
        'title': title,
        'sizeBytes': sizeBytes,
        'pageCount': pageCount,
        'contentSha256': contentSha256,
        'sha256Verified': sha256Verified,
        'sourceCreatedAt': sourceCreatedAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'version': version,
      };

  ToolkitDocumentMetadata copyWith({String? title, int? version}) =>
      ToolkitDocumentMetadata(
        documentId: documentId,
        type: type,
        contentType: contentType,
        title: title ?? this.title,
        sizeBytes: sizeBytes,
        pageCount: pageCount,
        contentSha256: contentSha256,
        sha256Verified: sha256Verified,
        sourceCreatedAt: sourceCreatedAt,
        createdAt: createdAt,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) =>
      other is ToolkitDocumentMetadata &&
      other.documentId == documentId &&
      other.type == type &&
      other.contentType == contentType &&
      other.title == title &&
      other.sizeBytes == sizeBytes &&
      other.pageCount == pageCount &&
      other.contentSha256 == contentSha256 &&
      other.sha256Verified == sha256Verified &&
      other.sourceCreatedAt == sourceCreatedAt &&
      other.createdAt == createdAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
        documentId,
        type,
        contentType,
        title,
        sizeBytes,
        pageCount,
        contentSha256,
        sha256Verified,
        sourceCreatedAt,
        createdAt,
        version,
      );
}

/// What the account holds and may hold, reported with the first page of a list.
@immutable
class ToolkitDocumentUsage {
  const ToolkitDocumentUsage({
    required this.readyCount,
    required this.readyBytes,
    required this.pendingCount,
    required this.pendingBytes,
    this.documentBytesLimit,
    this.imageBytesLimit,
    this.accountBytesLimit,
    this.accountDocumentsLimit,
  });

  final int readyCount;
  final int readyBytes;
  final int pendingCount;
  final int pendingBytes;
  final int? documentBytesLimit;
  final int? imageBytesLimit;
  final int? accountBytesLimit;
  final int? accountDocumentsLimit;
}

/// One page of the account's documents. [nextCursor] is opaque; null on the
/// last page. [usage] is present on the first page only.
@immutable
class ToolkitDocumentPage {
  const ToolkitDocumentPage({
    required this.documents,
    required this.nextCursor,
    this.usage,
  });

  final List<ToolkitDocumentMetadata> documents;
  final String? nextCursor;
  final ToolkitDocumentUsage? usage;
}

/// A short-lived signed read for one document, with what its download must
/// match. Transport only: the URL is never stored or logged.
@immutable
class ToolkitDownloadTicket {
  const ToolkitDownloadTicket({
    required this.documentId,
    required this.type,
    required this.contentType,
    required this.title,
    required this.sizeBytes,
    required this.contentSha256,
    required this.version,
    required this.url,
    required this.expiresAt,
    this.pageCount,
    this.sha256Verified = false,
  });

  final String documentId;
  final ToolkitDocumentType type;
  final ToolkitContentType contentType;
  final String title;

  /// The exact size the downloaded file must have.
  final int sizeBytes;
  final int version;
  final int? pageCount;

  /// The hash the downloaded file must have (device-calculated; see
  /// [ToolkitDocumentMetadata.sha256Verified]).
  final String contentSha256;
  final bool sha256Verified;
  final String url;
  final DateTime expiresAt;
}
