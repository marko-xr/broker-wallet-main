import 'dart:io';

import 'package:broker_wallet/src/services/image_signature_detector.dart';

/// What an Offer media file is, decided from its bytes, never its name.
enum OfferMediaKind { image, video }

/// Why a file was refused as Offer media. Each value maps to exactly one
/// localized message (see [OfferMediaRejection.messageKey]).
enum OfferMediaRejection {
  unsupportedType('offerMediaUnsupportedType'),
  imageTooLarge('offerMediaImageTooLarge'),
  videoTooLarge('offerMediaVideoTooLarge'),
  videoTooLong('offerMediaVideoTooLong'),
  limitReached('offerMediaLimitReached'),
  interrupted('offerMediaUploadInterrupted'),

  /// The Media Worker refused this upload for good: its bytes did not match,
  /// or its id was already used for something else or removed.
  rejected('offerMediaUploadRejected'),

  /// The queued file is no longer on the device.
  fileMissing('offerMediaFileMissing');

  const OfferMediaRejection(this.messageKey);

  /// The ARB key of the user-facing explanation, in English and Arabic.
  final String messageKey;

  /// Maps the Media Worker's stable `code` field to a rejection.
  ///
  /// Only permanent refusals are mapped. A retryable answer such as
  /// `upload_incomplete` or `deletion_in_progress` deliberately stays
  /// unmapped, so it reaches the caller as a plain HTTP failure it can retry.
  static OfferMediaRejection? fromWorkerCode(Object? code) => switch (code) {
        'unsupported_media_type' => OfferMediaRejection.unsupportedType,
        'media_type_mismatch' => OfferMediaRejection.unsupportedType,
        'image_too_large' => OfferMediaRejection.imageTooLarge,
        'video_too_large' => OfferMediaRejection.videoTooLarge,
        'video_too_long' => OfferMediaRejection.videoTooLong,
        'offer_media_limit_reached' => OfferMediaRejection.limitReached,
        // The same refusal for an Owner record (see MediaParent.owner).
        'owner_media_limit_reached' => OfferMediaRejection.limitReached,
        'upload_rejected' => OfferMediaRejection.rejected,
        'idempotency_mismatch' => OfferMediaRejection.rejected,
        'media_id_conflict' => OfferMediaRejection.rejected,
        'media_mismatch' => OfferMediaRejection.rejected,
        'media_removed' => OfferMediaRejection.rejected,
        'invalid_state' => OfferMediaRejection.rejected,
        _ => null,
      };
}

/// The product rules for Offer media (owner decisions), shared by the picker,
/// the Add/Edit Offer screen and the uploader, and mirrored server-side by the
/// Media Worker (`OFFER_MEDIA_TYPES` / `MAX_MEDIA_PER_OFFER` in `worker.js`),
/// which is the authority: these client checks only refuse early, before any
/// byte is sent.
abstract final class OfferMediaPolicy {
  /// Images and videos together, including media already on the Offer.
  static const int maxItemsPerOffer = 10;
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const Duration maxVideoDuration = Duration(minutes: 3);

  /// The same one-second allowance the Worker grants, so a clip the camera
  /// reports as 3:00 is not refused here when the server would accept it.
  static const Duration maxVideoDurationAccepted =
      Duration(minutes: 3, seconds: 1);

  /// Enough leading bytes for every signature recognized here.
  static const int headerBytes = 64;

  /// What may be uploaded. HEIC/HEIF photos are not on this list: they are
  /// converted to JPEG on the device first (see `offer_media_selection.dart`),
  /// so no Offer photo depends on a platform being able to decode HEIF.
  static const Map<String, OfferMediaKind> contentTypes = {
    'image/jpeg': OfferMediaKind.image,
    'image/png': OfferMediaKind.image,
    'image/webp': OfferMediaKind.image,
    'video/mp4': OfferMediaKind.video,
    'video/quicktime': OfferMediaKind.video,
    'video/3gpp': OfferMediaKind.video,
  };

  static int maxBytesFor(OfferMediaKind kind) =>
      kind == OfferMediaKind.video ? maxVideoBytes : maxImageBytes;

  /// The real Content-Type of a file from its leading [header] bytes, or
  /// null when it is not an uploadable Offer media container.
  static String? resolveContentType(List<int> header) {
    final image = ImageSignatureDetector.detectMimeType(header);
    if (image != null) return image;
    return VideoSignatureDetector.detectMimeType(header);
  }

  /// Reads only the first [headerBytes] of [file] — never the whole file,
  /// which may be a 100 MB video.
  static Future<List<int>> readHeader(File file) async {
    final handle = await file.open();
    try {
      return await handle.read(headerBytes);
    } finally {
      await handle.close();
    }
  }

  /// Classifies [file] and checks its size, without reading it whole.
  static Future<OfferMediaCheck> check(File file) async {
    final length = await file.length();
    final contentType = resolveContentType(await readHeader(file));
    final kind = contentType == null ? null : contentTypes[contentType];
    if (contentType == null || kind == null || length < 1) {
      return const OfferMediaCheck.rejected(
          OfferMediaRejection.unsupportedType);
    }
    if (length > maxBytesFor(kind)) {
      return OfferMediaCheck.rejected(kind == OfferMediaKind.video
          ? OfferMediaRejection.videoTooLarge
          : OfferMediaRejection.imageTooLarge);
    }
    return OfferMediaCheck.accepted(contentType, kind, length);
  }

  /// How many more items an Offer can take. Never negative.
  static int remainingSlots(int itemsAlreadyOnOffer) {
    final remaining = maxItemsPerOffer - itemsAlreadyOnOffer;
    return remaining < 0 ? 0 : remaining;
  }
}

/// The outcome of [OfferMediaPolicy.check].
class OfferMediaCheck {
  const OfferMediaCheck.accepted(
      String this.contentType, OfferMediaKind this.kind, int this.length)
      : rejection = null;

  const OfferMediaCheck.rejected(OfferMediaRejection this.rejection)
      : contentType = null,
        kind = null,
        length = null;

  final String? contentType;
  final OfferMediaKind? kind;
  final int? length;
  final OfferMediaRejection? rejection;

  bool get isAccepted => rejection == null;
}

/// One file the user picked for an Offer, screened and ready to be saved.
///
/// [mediaObjectId] is generated once, on the device, when the file is picked,
/// and is the item's identity from then on — in the upload queue, the
/// Worker, `media_objects`, the R2 key and the local cache. It is what makes
/// retrying the same logical upload safe: however often it is retried, it can
/// never become a second object.
class OfferMediaDraft {
  const OfferMediaDraft({
    required this.mediaObjectId,
    required this.path,
    required this.kind,
    required this.contentType,
    required this.byteLength,
    this.posterPath,
    this.displayName,
    this.durationMs,
  });

  final String mediaObjectId;

  /// The file to upload: the picked file, or its JPEG conversion.
  final String path;
  final OfferMediaKind kind;
  final String contentType;
  final int byteLength;

  /// A still frame of a video, made on the device for immediate preview.
  final String? posterPath;
  final String? displayName;
  final int? durationMs;
}

/// Detects a video container from its real leading bytes.
///
/// The client-side counterpart of `detectOfferMediaMimeFromBytes` in the
/// Media Worker: ISO base-media files (`ftyp` box) whose major brand — or,
/// only when the major brand is unknown and the file is not a HEIF image, a
/// compatible brand — is an MP4, QuickTime or 3GPP brand. This proves the
/// container, not the codec inside it.
abstract final class VideoSignatureDetector {
  static const Set<String> _mp4Brands = {
    'isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', //
    'M4V ', 'M4VH', 'M4VP', 'dash', 'mmp4', 'MSNV', 'f4v ',
  };
  static const Set<String> _quickTimeBrands = {'qt  '};
  static const Set<String> _threeGppBrands = {
    '3gp4', '3gp5', '3gp6', '3gp7', '3ge6', '3ge7', '3gg6', //
  };
  static const Set<String> _heifBrands = {'heic', 'heix', 'hevc', 'hevx'};

  static String? detectMimeType(List<int> bytes) {
    if (bytes.length < 12 ||
        bytes[4] != 0x66 || // f
        bytes[5] != 0x74 || // t
        bytes[6] != 0x79 || // y
        bytes[7] != 0x70) {
      // p
      return null;
    }

    final major = _brandAt(bytes, 8);
    final byMajor = _mimeForBrand(major);
    if (byMajor != null) return byMajor;

    final boxSize =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final end =
        boxSize >= 16 && boxSize < bytes.length ? boxSize : bytes.length;
    final compatible = <String>[
      for (var offset = 16; offset + 4 <= end; offset += 4)
        _brandAt(bytes, offset),
    ];
    if (_heifBrands.contains(major.toLowerCase()) ||
        compatible.any((b) => _heifBrands.contains(b.toLowerCase()))) {
      return null;
    }
    for (final brand in compatible) {
      final mime = _mimeForBrand(brand);
      if (mime != null) return mime;
    }
    return null;
  }

  static String _brandAt(List<int> bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  static String? _mimeForBrand(String brand) {
    if (_mp4Brands.contains(brand)) return 'video/mp4';
    if (_quickTimeBrands.contains(brand)) return 'video/quicktime';
    if (_threeGppBrands.contains(brand)) return 'video/3gpp';
    return null;
  }
}

/// Recognizes a HEIC/HEIF still image, which the app converts to JPEG before
/// upload rather than relying on platform HEIF decoding for display.
abstract final class HeifSignatureDetector {
  static const Set<String> _brands = {
    'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1', //
  };

  /// True for an ISO base-media file whose major or compatible brands name a
  /// HEIF image, or — only when the bytes are not a recognizable video — a
  /// file named `.heic`/`.heif`.
  static bool isHeif(List<int> header, {String? path}) {
    if (VideoSignatureDetector.detectMimeType(header) != null) return false;
    if (header.length >= 12 &&
        header[4] == 0x66 &&
        header[5] == 0x74 &&
        header[6] == 0x79 &&
        header[7] == 0x70) {
      final boxSize =
          (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
      final end =
          boxSize >= 16 && boxSize < header.length ? boxSize : header.length;
      for (var offset = 8; offset + 4 <= end; offset += 4) {
        if (offset == 12) continue; // minor_version, not a brand
        final brand = String.fromCharCodes(header.sublist(offset, offset + 4));
        if (_brands.contains(brand.toLowerCase())) return true;
      }
    }
    final name = path?.replaceAll('\\', '/').split('/').last.toLowerCase();
    return name != null && (name.endsWith('.heic') || name.endsWith('.heif'));
  }
}

/// Thrown when the Offer itself saved but some of its attached media did not.
///
/// The Offer's own success is never rolled back for a media failure: losing
/// entered Offer data because one file failed would be worse than losing the
/// file. [rejection] is present only when every failure had the same
/// user-actionable reason, so the message can be specific without guessing.
class OfferMediaPartialUploadException implements Exception {
  const OfferMediaPartialUploadException({
    required this.failedCount,
    required this.totalCount,
    this.rejection,
  });

  final int failedCount;
  final int totalCount;
  final OfferMediaRejection? rejection;

  @override
  String toString() =>
      'OfferMediaPartialUploadException($failedCount/$totalCount)';
}
