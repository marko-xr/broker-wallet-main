// Decides what a signed-in phone should do with each Toolkit document by
// comparing what it has (its journal and local files) with what the account's
// cloud library lists. Pure: no I/O, so the conflict policy is one readable
// table and is tested as such.
//
// Conflict policy
//  1. A document is identified by its id alone. The bytes of an id never change
//     (a document is written once), so there is no "newer copy" to prefer: the
//     only real conflicts are a damaged copy and a deletion.
//  2. Cloud and local with the same id and matching size/hash: in sync.
//  3. Cloud and local with the same id but different bytes: a conflict. NEITHER
//     side is overwritten; the library keeps the local file, offers the cloud
//     copy as a separate download, and the user decides.
//  4. In the cloud, not on this phone: [downloadRequired]. Opening it downloads
//     a verified copy.
//  5. On this phone, never in the cloud: waits for upload. It is only ever
//     uploaded when the journal says it never reached the cloud.
//  6. On this phone, confirmed before, and the cloud now says deleted: it was
//     deleted on another device. It is NEVER uploaded again; the local copy is
//     kept until the user decides ([remoteDeleted]).
//  7. On this phone, confirmed before, and the cloud has no record at all
//     (a tombstone purged after its retention): not resurrected either. A
//     document that once reached the cloud and is gone is treated as removed.
//  8. A stale local cache never overwrites the cloud: nothing here writes to the
//     cloud except an upload of a document that never reached it.

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';

/// What this phone has for one document id.
@immutable
class ToolkitLocalDocument {
  const ToolkitLocalDocument({
    required this.documentId,
    required this.sizeBytes,
    this.contentSha256,
    this.fileMissing = false,
  });

  final String documentId;
  final int sizeBytes;
  final String? contentSha256;

  /// The tool's store lists it but its file is no longer on the phone.
  final bool fileMissing;
}

enum ToolkitReconcileAction {
  /// Nothing to do.
  none,

  /// Upload it (it never reached the cloud).
  upload,

  /// Download it when the user opens it.
  downloadOnOpen,

  /// Keep the local file, never upload it; ask the user.
  keepLocalDeletedRemotely,

  /// Neither copy is touched; the user decides.
  conflict,

  /// The local file is gone and there is no cloud copy: nothing can be done.
  lost,
}

@immutable
class ToolkitReconcileItem {
  const ToolkitReconcileItem(this.documentId, this.state, this.action);

  final String documentId;
  final ToolkitDocumentSyncState state;
  final ToolkitReconcileAction action;

  @override
  String toString() => '$documentId: $state / $action';
}

abstract final class ToolkitLibraryReconciler {
  /// [remote] is the account's complete ready listing; [remoteStates] answers
  /// for ids that are local but not in [remote] (from the status endpoint); an id
  /// missing from it is treated as `unknown`.
  static List<ToolkitReconcileItem> reconcile({
    required Iterable<ToolkitLocalDocument> local,
    required Iterable<ToolkitSyncEntry> journal,
    required Iterable<ToolkitDocumentMetadata> remote,
    Map<String, ToolkitRemoteState> remoteStates =
        const <String, ToolkitRemoteState>{},
  }) {
    final remoteById = {for (final d in remote) d.documentId: d};
    final journalById = {for (final e in journal) e.documentId: e};
    final localById = {for (final d in local) d.documentId: d};
    final items = <ToolkitReconcileItem>[];

    for (final doc in localById.values) {
      final cloud = remoteById[doc.documentId];
      final entry = journalById[doc.documentId];
      if (cloud != null) {
        if (doc.fileMissing) {
          items.add(ToolkitReconcileItem(
            doc.documentId,
            ToolkitDocumentSyncState.downloadRequired,
            ToolkitReconcileAction.downloadOnOpen,
          ));
        } else if (_sameBytes(doc, cloud)) {
          items.add(ToolkitReconcileItem(
            doc.documentId,
            ToolkitDocumentSyncState.savedToCloud,
            ToolkitReconcileAction.none,
          ));
        } else {
          items.add(ToolkitReconcileItem(
            doc.documentId,
            ToolkitDocumentSyncState.downloadFailed,
            ToolkitReconcileAction.conflict,
          ));
        }
        continue;
      }
      if (doc.fileMissing) {
        items.add(ToolkitReconcileItem(
          doc.documentId,
          ToolkitDocumentSyncState.syncRejected,
          ToolkitReconcileAction.lost,
        ));
        continue;
      }
      final remoteState =
          remoteStates[doc.documentId] ?? ToolkitRemoteState.unknown;
      final reachedCloudBefore = entry?.isCloudConfirmed ?? false;
      if (remoteState == ToolkitRemoteState.deleted || reachedCloudBefore) {
        // Deleted elsewhere (or confirmed once and gone since): never uploaded
        // again.
        items.add(ToolkitReconcileItem(
          doc.documentId,
          ToolkitDocumentSyncState.remoteDeleted,
          ToolkitReconcileAction.keepLocalDeletedRemotely,
        ));
      } else {
        items.add(ToolkitReconcileItem(
          doc.documentId,
          entry?.state ?? ToolkitDocumentSyncState.savedLocallyPendingSync,
          ToolkitReconcileAction.upload,
        ));
      }
    }

    for (final cloud in remoteById.values) {
      if (localById.containsKey(cloud.documentId)) continue;
      items.add(ToolkitReconcileItem(
        cloud.documentId,
        ToolkitDocumentSyncState.downloadRequired,
        ToolkitReconcileAction.downloadOnOpen,
      ));
    }
    items.sort((a, b) => a.documentId.compareTo(b.documentId));
    return items;
  }

  static bool _sameBytes(
      ToolkitLocalDocument local, ToolkitDocumentMetadata cloud) {
    if (local.sizeBytes != cloud.sizeBytes) return false;
    final a = local.contentSha256;
    final b = cloud.contentSha256;
    // The cloud always has the device's digest. A local file whose digest is not
    // known yet is compared by size only; the library hashes it before relying on
    // that (the download service always verifies).
    return a == null || a == b;
  }
}
