// What may be a land / plot plan, decided from a file's own leading bytes.
//
// The client-side counterpart of `detectPlanMimeFromBytes` and `PLAN_MEDIA_TYPES`
// in the Media Worker, which is the authority: these checks only spare the user
// a doomed upload. Images keep the EXISTING accepted image contract — the same
// JPEG / PNG / WebP detector and the same size limit as the gallery
// ([OfferMediaPolicy]) — rather than a second one; HEIC photos are converted to
// JPEG first, exactly as for the gallery.

import 'dart:io';

import 'package:broker_wallet/src/services/image_signature_detector.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';

/// The outcome of [PlanAttachmentPolicy.check].
class PlanAttachmentCheck {
  const PlanAttachmentCheck.accepted(
      String this.contentType, PlanAttachmentKind this.kind, int this.length)
      : rejection = null;

  const PlanAttachmentCheck.rejected(PlanAttachmentRejection this.rejection)
      : contentType = null,
        kind = null,
        length = null;

  final String? contentType;
  final PlanAttachmentKind? kind;
  final int? length;
  final PlanAttachmentRejection? rejection;

  bool get isAccepted => rejection == null;
}

abstract final class PlanAttachmentPolicy {
  /// The gallery's own image limit: one image contract for the whole app.
  static const int maxImageBytes = OfferMediaPolicy.maxImageBytes;

  /// A document (PDF, DOC, DOCX) of exactly this many bytes is accepted.
  static const int maxDocumentBytes = 25 * 1024 * 1024;

  /// Enough leading bytes for every signature recognized here.
  static const int headerBytes = OfferMediaPolicy.headerBytes;

  /// The extensions the Files picker offers. Only a hint to the system picker:
  /// what a file really is comes from its bytes.
  static const List<String> pickerExtensions = [
    'pdf',
    'doc',
    'docx',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  ];

  static int maxBytesFor(PlanAttachmentKind kind) =>
      kind == PlanAttachmentKind.image ? maxImageBytes : maxDocumentBytes;

  /// The real content type of a plan file from its leading [header] bytes, or
  /// null when it is not an accepted plan type.
  ///
  /// A document is proven by its container: `%PDF-`, the OLE2 compound-file
  /// header of a legacy Word file, or a ZIP whose first entry is an Office Open
  /// XML part. That proves the container, not the application inside it.
  static String? detectContentType(List<int> header) {
    final image = ImageSignatureDetector.detectMimeType(header);
    if (image != null) return image;
    if (_isPdf(header)) return PlanContentTypes.pdf;
    if (_isOleCompoundFile(header)) return PlanContentTypes.doc;
    if (_isOfficeOpenXmlPackage(header)) return PlanContentTypes.docx;
    return null;
  }

  /// Classifies [file] and checks its size, without reading it whole.
  static Future<PlanAttachmentCheck> check(File file) async {
    final int length;
    final List<int> header;
    try {
      length = await file.length();
      header = await OfferMediaPolicy.readHeader(file);
    } on FileSystemException {
      return const PlanAttachmentCheck.rejected(
          PlanAttachmentRejection.unreadable);
    }
    if (length < 1) {
      return const PlanAttachmentCheck.rejected(
          PlanAttachmentRejection.unreadable);
    }
    final contentType = detectContentType(header);
    final kind = PlanAttachmentKind.fromContentType(contentType);
    if (contentType == null ||
        kind == null ||
        !_extensionAgrees(file.path, contentType)) {
      return const PlanAttachmentCheck.rejected(
          PlanAttachmentRejection.unsupportedType);
    }
    if (length > maxBytesFor(kind)) {
      return PlanAttachmentCheck.rejected(kind == PlanAttachmentKind.image
          ? PlanAttachmentRejection.imageTooLarge
          : PlanAttachmentRejection.documentTooLarge);
    }
    return PlanAttachmentCheck.accepted(contentType, kind, length);
  }

  /// A document whose name says it is something else (a spreadsheet or an
  /// archive, which share the Word containers' bytes) is refused. Images are
  /// decided by their bytes alone, as the gallery decides them.
  static bool _extensionAgrees(String path, String contentType) {
    final extension = extensionOf(path);
    switch (contentType) {
      case PlanContentTypes.pdf:
        return extension.isEmpty || extension == 'pdf';
      case PlanContentTypes.doc:
      case PlanContentTypes.docx:
        return extension.isEmpty || extension == 'doc' || extension == 'docx';
      default:
        return true;
    }
  }

  /// The lower-case extension of [path]'s file name, or an empty string.
  static String extensionOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static bool _isPdf(List<int> header) =>
      header.length >= 8 &&
      header[0] == 0x25 && // %
      header[1] == 0x50 && // P
      header[2] == 0x44 && // D
      header[3] == 0x46 && // F
      header[4] == 0x2d && // -
      (header[5] == 0x31 || header[5] == 0x32) && // 1 or 2
      header[6] == 0x2e && // .
      header[7] >= 0x30 &&
      header[7] <= 0x39;

  static bool _isOleCompoundFile(List<int> header) =>
      header.length >= 8 &&
      header[0] == 0xd0 &&
      header[1] == 0xcf &&
      header[2] == 0x11 &&
      header[3] == 0xe0 &&
      header[4] == 0xa1 &&
      header[5] == 0xb1 &&
      header[6] == 0x1a &&
      header[7] == 0xe1;

  static bool _isOfficeOpenXmlPackage(List<int> header) {
    if (header.length < 30 ||
        header[0] != 0x50 || // P
        header[1] != 0x4b || // K
        header[2] != 0x03 ||
        header[3] != 0x04 ||
        (header[6] & 0x01) != 0) {
      // Not a ZIP local file header, or its first entry is encrypted.
      return false;
    }
    final nameLength = header[26] | (header[27] << 8);
    if (nameLength <= 0 || 30 + nameLength > header.length) return false;
    final name = String.fromCharCodes(header.sublist(30, 30 + nameLength));
    return name == '[Content_Types].xml' ||
        name == '_rels/.rels' ||
        name.startsWith('word/') ||
        name.startsWith('docProps/');
  }
}
