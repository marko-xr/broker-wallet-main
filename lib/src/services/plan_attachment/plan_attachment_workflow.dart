// The upload and removal sequences of a record's plan.
//
//   upload:  authorize -> signed PUT -> trusted confirm
//
// The record's plan is only ever replaced by the server's atomic confirm, so a
// failed or interrupted replacement leaves the previous plan exactly as it was:
// nothing here marks a plan as attached until confirm answers. Every call is
// checked server-side against `expectedMediaId` (what the caller believes the
// plan is), so a stale operation is refused rather than overwriting a newer one.
//
// The draft's `mediaObjectId` is this upload's identity. Authorize and confirm
// are idempotent on it, so a retry after any failure, including a lost answer,
// resolves to the same object instead of creating a second one.

import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';

class PlanAttachmentWorkflow {
  PlanAttachmentWorkflow(this._transport);

  final PlanAttachmentTransport _transport;

  /// Uploads [draft] as [parent]'s plan and attaches it, replacing the plan the
  /// caller believes is [expectedMediaId] (null: there is none).
  ///
  /// Throws a [PlanAttachmentException]; whatever it is, the record's current
  /// plan is unchanged unless this returned.
  Future<PlanAttachmentRef> upload({
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentDraft draft,
    required String? expectedMediaId,
  }) async {
    final file = File(draft.path);
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.fileUnavailable);
    }
    if (length < 1 || length != draft.byteLength) {
      // Changed or removed since it was screened: never upload something that
      // is no longer the file that was accepted.
      throw const PlanAttachmentException(
          PlanAttachmentFailure.fileUnavailable);
    }

    final authorization = await _transport.authorize(
      parent: parent,
      parentId: parentId,
      expectedMediaId: expectedMediaId,
      mediaObjectId: draft.mediaObjectId,
      contentType: draft.contentType,
      contentLength: length,
      originalFileName: draft.displayName,
    );
    if (!authorization.isAlreadyReady) {
      await _transport.uploadBytes(
        presignedUrl: authorization.presignedUrl!,
        file: file,
        contentType: draft.contentType,
      );
      await _transport.confirm(
        parent: parent,
        parentId: parentId,
        mediaObjectId: draft.mediaObjectId,
        expectedMediaId: expectedMediaId,
      );
    }
    return PlanAttachmentRef(
      mediaObjectId: draft.mediaObjectId,
      kind: draft.kind,
      contentType: draft.contentType,
      displayName: draft.displayName,
      byteLength: draft.byteLength,
    );
  }

  /// Removes the plan the caller believes is [expectedMediaId]. Idempotent when
  /// the record already has none.
  Future<void> remove({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
  }) async {
    await _transport.remove(
      parent: parent,
      parentId: parentId,
      expectedMediaId: expectedMediaId,
    );
  }

  /// Withdraws an upload that was authorized but never confirmed, so it stops
  /// holding one of the record's few waiting places. Best effort: the server's
  /// own cleanup removes an abandoned upload after a day.
  Future<void> cancelCandidate({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    required String mediaObjectId,
  }) async {
    try {
      await _transport.remove(
        parent: parent,
        parentId: parentId,
        expectedMediaId: expectedMediaId,
        mediaObjectId: mediaObjectId,
      );
    } catch (_) {
      // Never fail the caller for tidying up.
    }
  }
}
