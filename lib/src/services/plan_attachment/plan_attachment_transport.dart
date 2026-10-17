// The Media Worker operations a plan change consists of, as a seam: the workflow
// and the form controller are exercised against a fake, the app uses
// [R2PlanAttachmentService].
//
// Every authorize, confirm and remove names the media id the caller believes the
// plan is (`expectedMediaId`, null for "no plan"); the server refuses with
// `stale_replacement` when that is no longer true, so an older operation can
// never overwrite a newer one.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';

/// What `<prefix>/authorize` answered.
@immutable
class PlanAuthorization {
  const PlanAuthorization.pending({
    required this.mediaObjectId,
    required String this.presignedUrl,
  }) : isAlreadyReady = false;

  const PlanAuthorization.ready({required this.mediaObjectId})
      : presignedUrl = null,
        isAlreadyReady = true;

  final String mediaObjectId;

  /// The short-lived signed PUT. Transport only: never stored.
  final String? presignedUrl;

  /// The id is already the record's plan, so there is nothing to upload.
  final bool isAlreadyReady;
}

/// What `<prefix>/confirm` answered.
@immutable
class PlanConfirmation {
  const PlanConfirmation({
    this.previousMediaId,
    this.alreadyConfirmed = false,
    this.cleanupPending = false,
  });

  /// The plan this one replaced, if any.
  final String? previousMediaId;
  final bool alreadyConfirmed;

  /// The replaced file is still being retired by the server.
  final bool cleanupPending;
}

/// What `<prefix>/remove` answered.
@immutable
class PlanRemoval {
  const PlanRemoval({
    this.previousMediaId,
    this.alreadyRemoved = false,
    this.cleanupPending = false,
  });

  final String? previousMediaId;
  final bool alreadyRemoved;
  final bool cleanupPending;
}

abstract interface class PlanAttachmentTransport {
  Future<PlanAuthorization> authorize({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  });

  /// PUTs [file] to the signed [presignedUrl].
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  });

  Future<PlanConfirmation> confirm({
    required PlanParent parent,
    required String parentId,
    required String mediaObjectId,
    required String? expectedMediaId,
  });

  /// Removes the current plan ([mediaObjectId] null), or cancels the not yet
  /// attached upload [mediaObjectId].
  Future<PlanRemoval> remove({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    String? mediaObjectId,
  });

  /// The record's current plan with a fresh signed read link, or null when it
  /// has none.
  Future<PlanAttachmentRef?> fetchCurrent({
    required PlanParent parent,
    required String parentId,
  });

  /// Downloads the signed [url] into [target], refusing more than [maxBytes].
  Future<void> download({
    required String url,
    required File target,
    required int maxBytes,
  });
}
