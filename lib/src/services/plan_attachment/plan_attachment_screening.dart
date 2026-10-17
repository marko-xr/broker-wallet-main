// Screens a file the user picked for a plan, before anything is sent.
//
// Local and cheap: only the file's first bytes are read. A HEIC / HEIF photo is
// converted to JPEG on the device (by [convertHeif], the gallery's own
// converter), so no plan image depends on a platform being able to decode HEIF.
// An accepted file gets its `mediaObjectId` here, once: from this moment it is
// this upload's identity.

import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';

/// Converts a HEIC / HEIF photo to a JPEG file, or returns null when it cannot.
typedef PlanHeifConverter = Future<File?> Function(File source);

/// What screening a picked file decided: a draft ready to save, or why not.
class PlanAttachmentScreening {
  const PlanAttachmentScreening.accepted(PlanAttachmentDraft this.draft)
      : rejection = null;

  const PlanAttachmentScreening.rejected(PlanAttachmentRejection this.rejection)
      : draft = null;

  final PlanAttachmentDraft? draft;
  final PlanAttachmentRejection? rejection;

  bool get isAccepted => draft != null;
}

/// The signature of the screening the form controller uses; a seam for tests.
typedef PlanFileScreener = Future<PlanAttachmentScreening> Function(
  File picked, {
  String? displayName,
});

Future<PlanAttachmentScreening> screenPlanFile(
  File picked, {
  String? displayName,
  PlanHeifConverter? convertHeif,
  String Function()? newMediaObjectId,
}) async {
  var file = picked;
  String? ownedTempPath;
  try {
    final header = await OfferMediaPolicy.readHeader(picked);
    if (HeifSignatureDetector.isHeif(header, path: picked.path)) {
      final converter = convertHeif;
      final converted = converter == null ? null : await converter(picked);
      if (converted == null) {
        return const PlanAttachmentScreening.rejected(
            PlanAttachmentRejection.unsupportedType);
      }
      file = converted;
      ownedTempPath = converted.path;
    }
  } on FileSystemException {
    return const PlanAttachmentScreening.rejected(
        PlanAttachmentRejection.unreadable);
  }

  final check = await PlanAttachmentPolicy.check(file);
  if (!check.isAccepted) {
    if (ownedTempPath != null) await deleteQuietly(ownedTempPath);
    return PlanAttachmentScreening.rejected(check.rejection!);
  }
  final cleanName = displayName?.trim();
  return PlanAttachmentScreening.accepted(PlanAttachmentDraft(
    mediaObjectId: (newMediaObjectId ?? () => const Uuid().v4())(),
    path: file.path,
    kind: check.kind!,
    contentType: check.contentType!,
    byteLength: check.length!,
    displayName: cleanName == null || cleanName.isEmpty ? null : cleanName,
    ownedTempPath: ownedTempPath,
  ));
}

/// Deletes the file at [path] when there is one. Never throws.
Future<void> deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A leftover temporary file is harmless; never fail the caller for it.
  }
}
