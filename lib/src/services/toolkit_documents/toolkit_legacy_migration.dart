// Chooses which of the documents already saved in the four tools' local,
// account-scoped folders may be queued for the cloud. Pure: it reads nothing,
// moves nothing and never touches a file. The migration itself (a later
// checkpoint) only feeds the eligible ones to the upload coordinator; the
// original local file stays exactly where it is until the cloud copy is
// verified, and even then removal is the user's own act.
//
// Rules
//  * Only the CURRENT signed-in account's documents are eligible: the tool's
//    folder (`<root>/<account>/`) must be that account's, AND its `index.json`
//    must record that same account as owner. A folder or index that names
//    another account, or none, is never uploaded under whoever happens to be
//    signed in ("legacy ownerless" files need a separate owner decision).
//  * A document needs the id its tool gave it (a UUID); that id is the cloud id,
//    so a retried migration finds the same document and never duplicates it.
//  * An id the cloud already holds is skipped, which makes the migration safe
//    to run again after any interruption.
//  * A file the cloud will not accept (not a PDF, above the size limit) is
//    reported, not hidden, and stays local.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';

enum ToolkitLegacyDecision {
  /// Queue it for the cloud.
  eligible,

  /// The cloud already has this id.
  alreadyInCloud,

  /// The index records no owner. Never assigned to whoever signs in; needs the
  /// owner's decision.
  ownerless,

  /// The folder or the index belongs to a different account.
  otherAccount,

  /// A format the cloud does not accept for that tool (anything but PDF, and
  /// JPEG / PNG from the Scanner). Reported, stays local.
  unsupportedType,

  /// Above the per-document size limit.
  tooLarge,

  /// The tool's id is not a canonical UUID, so it cannot be the cloud id.
  invalidId,

  /// The file is no longer on the phone.
  fileMissing,
}

@immutable
class ToolkitLegacyCandidate {
  const ToolkitLegacyCandidate({
    required this.type,
    required this.localId,
    required this.accountFolderName,
    required this.indexOwnerId,
    required this.contentType,
    required this.sizeBytes,
    required this.title,
    this.pageCount,
    this.createdAt,
    this.fileMissing = false,
  });

  final ToolkitDocumentType type;
  final String localId;

  /// The name of the `<root>/<account>/` folder the document was found in.
  final String accountFolderName;

  /// The `userId` its index.json records; null when there is none.
  final String? indexOwnerId;
  final String contentType;
  final int sizeBytes;
  final String title;
  final int? pageCount;
  final DateTime? createdAt;
  final bool fileMissing;
}

@immutable
class ToolkitLegacyPlan {
  const ToolkitLegacyPlan({required this.eligible, required this.skipped});

  final List<ToolkitLegacyCandidate> eligible;

  /// Every candidate that was not queued, with why, keyed by `<type>/<id>`.
  final Map<String, ToolkitLegacyDecision> skipped;

  int count(ToolkitLegacyDecision decision) =>
      skipped.values.where((d) => d == decision).length;
}

abstract final class ToolkitLegacyMigration {
  /// The folder name the stores give an account: the id when it is plain (a UUID
  /// is), otherwise `u_` and its hex. Mirrors the four stores'
  /// `accountDirectory`, so a folder is recognized by exactly their rule.
  static String accountFolderName(String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(userId);
    if (plain) return userId;
    final hex = utf8
        .encode(userId)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'u_$hex';
  }

  static ToolkitLegacyPlan plan({
    required String currentUserId,
    required Iterable<ToolkitLegacyCandidate> candidates,
    Set<String> idsAlreadyInCloud = const <String>{},
    int maxDocumentBytes = ToolkitDocumentLimits.defaultDocumentBytes,
    int maxImageBytes = ToolkitDocumentLimits.defaultImageBytes,
  }) {
    final folder = accountFolderName(currentUserId);
    final eligible = <ToolkitLegacyCandidate>[];
    final skipped = <String, ToolkitLegacyDecision>{};
    final seen = <String>{};
    for (final c in candidates) {
      final key = '${c.type.wireName}/${c.localId}';
      ToolkitLegacyDecision? decision;
      if (c.accountFolderName != folder) {
        decision = ToolkitLegacyDecision.otherAccount;
      } else if (c.indexOwnerId == null || c.indexOwnerId!.isEmpty) {
        decision = ToolkitLegacyDecision.ownerless;
      } else if (c.indexOwnerId != currentUserId) {
        decision = ToolkitLegacyDecision.otherAccount;
      } else if (!ToolkitDocumentIds.isCanonical(c.localId)) {
        decision = ToolkitLegacyDecision.invalidId;
      } else if (c.fileMissing) {
        decision = ToolkitLegacyDecision.fileMissing;
      } else if (ToolkitContentType.fromMime(c.contentType) == null ||
          !ToolkitContentType.fromMime(c.contentType)!.allowedFor(c.type)) {
        decision = ToolkitLegacyDecision.unsupportedType;
      } else if (c.sizeBytes < 1 ||
          c.sizeBytes >
              (ToolkitContentType.fromMime(c.contentType)!.isImage
                  ? maxImageBytes
                  : maxDocumentBytes)) {
        decision = ToolkitLegacyDecision.tooLarge;
      } else if (idsAlreadyInCloud.contains(c.localId) ||
          !seen.add(c.localId)) {
        // Already uploaded, or the same id listed twice.
        decision = ToolkitLegacyDecision.alreadyInCloud;
      }
      if (decision == null) {
        eligible.add(c);
      } else {
        skipped[key] = decision;
      }
    }
    return ToolkitLegacyPlan(eligible: eligible, skipped: skipped);
  }
}
