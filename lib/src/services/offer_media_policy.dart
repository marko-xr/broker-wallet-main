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
  interrupted('offerMediaUploadInterrupted');

  const OfferMediaRejection(this.messageKey);

  /// The ARB key of the user-facing explanation, in English and Arabic.
  final String messageKey;

  /// Maps the Media Worker's stable `code` field to a rejection.
  static OfferMediaRejection? fromWorkerCode(Object? code) => switch (code) {
        'unsupported_media_type' => OfferMediaRejection.unsupportedType,
        'image_too_large' => OfferMediaRejection.imageTooLarge,
        'video_too_large' => OfferMediaRejection.videoTooLarge,
        'video_too_long' => OfferMediaRejection.videoTooLong,
        'offer_media_limit_reached' => OfferMediaRejection.limitReached,
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

  /// Enough leading bytes for every signature recognized here.
  static const int headerBytes = 64;

  static const Map<String, OfferMediaKind> contentTypes = {
    'image/jpeg': OfferMediaKind.image,
    'image/png': OfferMediaKind.image,
    'image/webp': OfferMediaKind.image,
    'image/heic': OfferMediaKind.image,
    'video/mp4': OfferMediaKind.video,
    'video/quicktime': OfferMediaKind.video,
    'video/3gpp': OfferMediaKind.video,
  };

  static int maxBytesFor(OfferMediaKind kind) =>
      kind == OfferMediaKind.video ? maxVideoBytes : maxImageBytes;

  /// The real Content-Type of a file from its leading [header] bytes, or
  /// null when it is not a supported Offer media container.
  ///
  /// HEIC is the one deliberate exception, unchanged from before videos were
  /// supported: its byte signature is not detected client-side, so a
  /// `.heic`-named file keeps the extension-trusted classification (the
  /// Worker still verifies its real bytes on confirm).
  static String? resolveContentType(String path, List<int> header) {
    final image = ImageSignatureDetector.detectMimeType(header);
    if (image != null) return image;
    final video = VideoSignatureDetector.detectMimeType(header);
    if (video != null) return video;
    if (_extension(path) == 'heic') return 'image/heic';
    return null;
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
  /// Returns the rejection, or null when the file may be uploaded.
  static Future<OfferMediaCheck> check(File file) async {
    final length = await file.length();
    final contentType = resolveContentType(file.path, await readHeader(file));
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

  static String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    return name.contains('.') ? name.split('.').last.toLowerCase() : '';
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
