// What one tool needs from Toolkit cloud documents, as ONE seam: queue a saved
// document, learn what the account holds, rename, delete, and bring a cloud-only
// document back onto this phone.
//
// It joins the pieces that already exist (upload coordinator and its journal,
// the cloud repository, the download service and the library reconciler) and
// adds no rule of its own about bytes: a document is "saved to the cloud" only
// when the coordinator says the server confirmed it, and nothing here deletes or
// rewrites a local file. A tool keeps working with no network and with this
// seam absent; every failure here is reported to the caller as a state or an
// exception, never as a reason to lose a local copy.
//
// One instance serves ONE account and ONE tool's documents.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_diagnostics.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_cloud_repository.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_library_reconciler.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_remote_cache.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

/// One document a tool holds on this phone, as it describes it.
@immutable
class ToolkitCloudLocalDocument {
  const ToolkitCloudLocalDocument({
    required this.documentId,
    required this.title,
    required this.sizeBytes,
    required this.sourceCreatedAt,
    this.pageCount,
    this.contentType = ToolkitContentType.pdf,
    this.fileMissing = false,
  });

  final String documentId;
  final String title;
  final int sizeBytes;
  final DateTime sourceCreatedAt;
  final int? pageCount;
  final ToolkitContentType contentType;

  /// The tool lists it but its file is no longer on the phone.
  final bool fileMissing;
}

/// What the account's cloud library says about the documents of one tool.
@immutable
class ToolkitCloudReconciliation {
  const ToolkitCloudReconciliation({
    required this.remoteOnly,
    required this.states,
    required this.remoteById,
  });

  /// In the cloud, not on this phone: shown, downloaded when the user opens it.
  final List<ToolkitDocumentMetadata> remoteOnly;

  /// The cloud's view of each document that IS on this phone.
  final Map<String, ToolkitDocumentSyncState> states;

  /// Everything the cloud lists for the tool, by id.
  final Map<String, ToolkitDocumentMetadata> remoteById;
}

enum ToolkitCloudDeleteResult {
  /// Gone from the cloud (or it was never there): the caller removes its local
  /// file now.
  deleted,

  /// The user's delete is recorded; it is finished when the server can be
  /// reached. The local file stays until then.
  pending,

  /// Not deleted; nothing changed.
  failed,
}

abstract interface class ToolkitCloudLibrary {
  String get accountId;

  /// Every state change of a queued document.
  Stream<ToolkitSyncUpdate> get updates;

  /// Ids whose delete the server confirmed in the background (a delete that was
  /// waiting for the network). The tool removes their local files.
  Stream<String> get deletions;

  /// The journal's record of a document, if it has one.
  ToolkitSyncEntry? entryFor(String documentId);

  /// Every record the journal holds for this account (all tools that share it).
  List<ToolkitSyncEntry> get entries;

  /// Reads the journal and resumes whatever is due. Never throws.
  Future<void> start();

  /// Records a document the tool just saved and starts uploading it. Idempotent
  /// on the id.
  Future<void> queue(ToolkitSyncEntry entry);

  /// Records, WITHOUT asking the network, every document in [local] that the
  /// journal does not know yet (a document just saved, or made before the cloud
  /// was on), so it is on the journal and uploaded as soon as the network allows,
  /// even if the app is closed first. Idempotent: an id already known is left
  /// alone, and the server treats a second upload of the same bytes as already
  /// confirmed. Returns how many were recorded. Never throws.
  Future<int> recordLocal({
    required ToolkitDocumentType type,
    required List<ToolkitCloudLocalDocument> local,
  });

  /// Compares [local] with the account's cloud library, queues local documents
  /// the cloud does not hold, and reports what the cloud holds that this phone
  /// does not. Throws [ToolkitDocumentException] when the cloud cannot be asked;
  /// the caller then keeps what it showed.
  Future<ToolkitCloudReconciliation> reconcile({
    required ToolkitDocumentType type,
    required List<ToolkitCloudLocalDocument> local,
  });

  /// What the last successful list of [type] held, kept on the phone, so a screen
  /// can show its cards at once. A convenience copy of metadata only: the next
  /// [reconcile] replaces it, and nothing is opened from it without an
  /// authorized download. Empty when there is none. Never throws.
  Future<List<ToolkitDocumentMetadata>> cachedRemote(ToolkitDocumentType type);

  /// Runs every upload, rename and delete that is due. Never throws.
  Future<void> syncDue();

  /// Completes when no sync started by [start], [queue], [reconcile] or
  /// [syncDue] is still running. It does not wait for work that is only waiting
  /// for its retry time. For the tool's own shutdown and for tests, so nothing is
  /// still reading or writing a file when its folder is removed.
  Future<void> idle();

  /// The user asked to try this document again now.
  Future<ToolkitSyncOutcome> retry(String documentId);

  /// Sends a new title. A document that is not in the cloud yet simply keeps it
  /// for its upload; a failure to reach the cloud is kept and retried, not
  /// thrown, when the journal knows the document. Throws
  /// [ToolkitDocumentException] only for a cloud-only document.
  Future<void> rename(String documentId, String title);

  /// Deletes the document from the account; see [ToolkitCloudDeleteResult].
  Future<ToolkitCloudDeleteResult> delete(String documentId);

  /// Downloads [document] to [target] as a verified file (see
  /// [ToolkitDocumentDownloadService]). Throws [ToolkitDocumentException].
  Future<ToolkitDownloadResult> download({
    required ToolkitDocumentMetadata document,
    required File target,
  });

  /// Stops this library. A library shared by several screens (see
  /// [DefaultToolkitCloudLibrary.shared]) ignores it: the screens that use it come
  /// and go, the work in flight must not.
  Future<void> dispose();
}

class DefaultToolkitCloudLibrary implements ToolkitCloudLibrary {
  /// [shared] marks a library that several screens of one account use (the tool's
  /// list screen, and an editor opened from it): it must keep running when one of
  /// them is closed, so [dispose] does nothing for it and only [shutdown] stops it.
  DefaultToolkitCloudLibrary({
    required this.accountId,
    required ToolkitDocumentTransport transport,
    required ToolkitSyncJournal journal,
    required ToolkitLocalFiles files,
    required String? Function() currentAccountId,
    ToolkitFileHasher? hasher,
    ToolkitFreeSpaceProbe? freeSpace,
    DateTime Function()? clock,
    ToolkitRemoteCache? remoteCache,
    this.shared = false,
  })  : _remoteCache = remoteCache,
        _coordinator = ToolkitDocumentUploadCoordinator(
          accountId: accountId,
          transport: transport,
          journal: journal,
          files: files,
          currentAccountId: currentAccountId,
          hasher: hasher,
          clock: clock,
        ),
        _repository = RemoteToolkitDocumentCloudRepository(transport),
        _downloads = ToolkitDocumentDownloadService(
          transport: transport,
          freeSpace: freeSpace,
          hasher: hasher,
        );

  @override
  final String accountId;

  /// See the constructor.
  final bool shared;

  final ToolkitRemoteCache? _remoteCache;
  final ToolkitDocumentUploadCoordinator _coordinator;
  final ToolkitDocumentCloudRepository _repository;
  final ToolkitDocumentDownloadService _downloads;

  final StreamController<String> _deletions =
      StreamController<String>.broadcast();
  Map<String, ToolkitDocumentMetadata> _remoteById =
      <String, ToolkitDocumentMetadata>{};
  bool _listedOnce = false;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;
  Future<void>? _loading;
  final Set<Future<void>> _syncRuns = <Future<void>>{};

  /// The journal is read once, before anything else acts: an operation that ran
  /// on an empty, not yet loaded journal could record a document a second time
  /// and overwrite what an earlier run had confirmed.
  Future<void> _ensureLoaded() => _loading ??= _loadJournal();

  Future<void> _loadJournal() async {
    try {
      await _coordinator.load();
      await _coordinator.resumeAfterSignIn();
    } catch (_) {
      // A damaged journal was set aside by the journal itself; the documents are
      // untouched and the next reconcile queues whatever never reached the cloud.
    }
  }

  @override
  Stream<ToolkitSyncUpdate> get updates => _coordinator.updates;

  @override
  Stream<String> get deletions => _deletions.stream;

  @override
  ToolkitSyncEntry? entryFor(String documentId) =>
      _coordinator.entryFor(documentId);

  @override
  List<ToolkitSyncEntry> get entries => _coordinator.entries;

  @override
  Future<void> start() async {
    await _ensureLoaded();
    unawaited(syncDue());
  }

  @override
  Future<int> recordLocal({
    required ToolkitDocumentType type,
    required List<ToolkitCloudLocalDocument> local,
  }) async {
    try {
      await _ensureLoaded();
      var recorded = 0;
      for (final doc in local) {
        if (doc.fileMissing ||
            !ToolkitDocumentIds.isCanonical(doc.documentId) ||
            _coordinator.entryFor(doc.documentId) != null) {
          continue;
        }
        try {
          await _coordinator.enqueue(_entryOf(type, doc));
          recorded++;
        } catch (_) {
          // This one is tried again by the next call; the others go on.
        }
      }
      if (recorded > 0) unawaited(syncDue());
      return recorded;
    } catch (_) {
      return 0;
    }
  }

  ToolkitSyncEntry _entryOf(
    ToolkitDocumentType type,
    ToolkitCloudLocalDocument doc,
  ) =>
      ToolkitSyncEntry(
        documentId: doc.documentId,
        accountId: accountId,
        type: type,
        contentType: doc.contentType,
        title: ToolkitDocumentTitles.sanitize(doc.title),
        sizeBytes: doc.sizeBytes,
        localRef: doc.documentId,
        sourceCreatedAt: doc.sourceCreatedAt,
        pageCount: doc.pageCount,
      );

  @override
  Future<void> queue(ToolkitSyncEntry entry) async {
    await _ensureLoaded();
    await _coordinator.enqueue(entry);
    unawaited(syncDue());
  }

  @override
  Future<List<ToolkitDocumentMetadata>> cachedRemote(
    ToolkitDocumentType type,
  ) async {
    final cache = _remoteCache;
    if (cache == null) return const <ToolkitDocumentMetadata>[];
    try {
      final documents = await cache.read(type);
      // A card shown from the copy can be renamed or deleted before the first
      // list of this session arrives: the library must know it by then.
      if (!_listedOnce && _remoteById.isEmpty) {
        _remoteById = <String, ToolkitDocumentMetadata>{
          for (final d in documents) d.documentId: d,
        };
      }
      return documents;
    } catch (error) {
      ToolkitDiagnostics.report('cache-read-failed', type: type, error: error);
      return const <ToolkitDocumentMetadata>[];
    }
  }

  @override
  Future<void> syncDue() {
    if (_disposed) return Future<void>.value();
    // Registered at once (not after the first await), so [idle] sees a sync that
    // has been asked for but has not started yet.
    final run = _syncDue();
    _syncRuns.add(run);
    return run.whenComplete(() => _syncRuns.remove(run));
  }

  Future<void> _syncDue() async {
    await _ensureLoaded();
    if (_disposed) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final results = await _coordinator.syncDue();
        for (final result in results.entries) {
          if (result.value == ToolkitSyncOutcome.deleted &&
              !_deletions.isClosed) {
            _deletions.add(result.key);
          }
        }
      } while (_syncAgain && !_disposed);
    } catch (_) {
      // Whatever failed is still in the journal and is tried again later.
    } finally {
      _syncing = false;
    }
  }

  @override
  Future<void> idle() async {
    await _ensureLoaded();
    while (_syncRuns.isNotEmpty) {
      await Future.wait(_syncRuns.toList());
    }
  }

  @override
  Future<ToolkitSyncOutcome> retry(String documentId) async {
    await _ensureLoaded();
    final outcome = await _coordinator.retry(documentId);
    if (outcome == ToolkitSyncOutcome.deleted && !_deletions.isClosed) {
      _deletions.add(documentId);
    }
    return outcome;
  }

  @override
  Future<ToolkitCloudReconciliation> reconcile({
    required ToolkitDocumentType type,
    required List<ToolkitCloudLocalDocument> local,
  }) async {
    await _ensureLoaded();
    final ToolkitDocumentListing listing;
    try {
      listing = await _repository.listAll(type: type);
    } catch (error) {
      // The caller keeps what it showed; the category stays findable here.
      ToolkitDiagnostics.report('list-failed', type: type, error: error);
      rethrow;
    }
    final remote = listing.documents;
    _listedOnce = true;
    ToolkitDiagnostics.report('list-ok', type: type, count: remote.length);
    await _rememberRemote(type, remote);
    final remoteIds = <String>{for (final d in remote) d.documentId};

    // A delete the user asked for is not a document to upload or to show. A local
    // id that is not a canonical UUID can never be a cloud id: that one document
    // is reported as not backed up, and must not stop the others (a single
    // unusable id would otherwise fail the whole status request).
    final unusable = <String>{
      for (final d in local)
        if (!ToolkitDocumentIds.isCanonical(d.documentId)) d.documentId,
    };
    final live = <ToolkitCloudLocalDocument>[
      for (final d in local)
        if (!_isDeleting(d.documentId) && !unusable.contains(d.documentId)) d,
    ];
    final liveById = <String, ToolkitCloudLocalDocument>{
      for (final d in live) d.documentId: d,
    };
    final notListed = <String>[
      for (final d in live)
        if (!remoteIds.contains(d.documentId)) d.documentId,
    ];
    // What the cloud says about a local document it did not list decides whether
    // that document is uploaded or was deleted elsewhere. If that question cannot
    // be answered now, the account's own documents are still reported (they do
    // not depend on it) and the local ones are simply not queued this time.
    var statusKnown = true;
    Map<String, ToolkitRemoteState> remoteStates =
        const <String, ToolkitRemoteState>{};
    if (notListed.isNotEmpty) {
      try {
        remoteStates = await _repository.statuses(notListed);
      } catch (error) {
        statusKnown = false;
        ToolkitDiagnostics.report('status-failed', type: type, error: error);
      }
    }

    final items = ToolkitLibraryReconciler.reconcile(
      local: <ToolkitLocalDocument>[
        for (final d in live)
          ToolkitLocalDocument(
            documentId: d.documentId,
            sizeBytes: d.sizeBytes,
            fileMissing: d.fileMissing,
          ),
      ],
      journal: _coordinator.entries,
      remote: remote,
      remoteStates: remoteStates,
    );

    final states = <String, ToolkitDocumentSyncState>{
      for (final id in unusable) id: ToolkitDocumentSyncState.syncRejected,
    };
    final remoteOnly = <ToolkitDocumentMetadata>[];
    final remoteById = <String, ToolkitDocumentMetadata>{
      for (final d in remote) d.documentId: d,
    };
    var queuedAny = false;
    for (final item in items) {
      final doc = liveById[item.documentId];
      if (doc == null) {
        final cloud = remoteById[item.documentId];
        if (cloud != null && !_isDeleting(item.documentId)) {
          remoteOnly.add(cloud);
        }
        continue;
      }
      var state = item.state;
      if (!remoteIds.contains(doc.documentId) &&
          remoteStates[doc.documentId] == ToolkitRemoteState.ready) {
        // The listing was read just before this document was confirmed.
        state = ToolkitDocumentSyncState.savedToCloud;
      }
      states[doc.documentId] = state;

      final needsRecord = !doc.fileMissing &&
          (statusKnown || remoteIds.contains(doc.documentId)) &&
          _coordinator.entryFor(doc.documentId) == null &&
          (item.action == ToolkitReconcileAction.upload ||
              item.action == ToolkitReconcileAction.none);
      if (needsRecord) {
        // Not on the journal: a document made before the cloud was on, or one
        // whose journal was lost. Recording it uploads it, or, when the cloud
        // already holds these bytes, just confirms it. One document that cannot
        // be recorded now (the journal could not be written) is tried again at
        // the next reconcile and never fails the rest.
        try {
          await _coordinator.enqueue(_entryOf(type, doc));
          queuedAny = true;
        } catch (_) {
          continue;
        }
      }
    }
    _remoteById = remoteById;
    if (queuedAny) unawaited(syncDue());
    return ToolkitCloudReconciliation(
      remoteOnly: remoteOnly,
      states: states,
      remoteById: Map<String, ToolkitDocumentMetadata>.unmodifiable(remoteById),
    );
  }

  bool _isDeleting(String documentId) {
    final entry = _coordinator.entryFor(documentId);
    return entry != null &&
        entry.deleteRequested &&
        entry.state == ToolkitDocumentSyncState.deletePending;
  }

  Future<void> _rememberRemote(
    ToolkitDocumentType type,
    List<ToolkitDocumentMetadata> remote,
  ) async {
    final cache = _remoteCache;
    if (cache == null) return;
    try {
      await cache.write(type, remote);
    } catch (error) {
      ToolkitDiagnostics.report('cache-write-failed', type: type, error: error);
    }
  }

  @override
  Future<void> rename(String documentId, String title) async {
    await _ensureLoaded();
    final entry = _coordinator.entryFor(documentId);
    if (entry != null) {
      await _coordinator.rename(documentId, title);
      return;
    }
    final cloud = _remoteById[documentId];
    if (cloud == null) return;
    final result = await _repository.rename(document: cloud, title: title);
    _remoteById = <String, ToolkitDocumentMetadata>{
      ..._remoteById,
      documentId: cloud.copyWith(title: result.title, version: result.version),
    };
  }

  @override
  Future<ToolkitCloudDeleteResult> delete(String documentId) async {
    await _ensureLoaded();
    try {
      final entry = _coordinator.entryFor(documentId);
      if (entry != null) {
        final outcome = await _coordinator.requestDelete(documentId);
        switch (outcome) {
          case ToolkitSyncOutcome.deleted:
            return ToolkitCloudDeleteResult.deleted;
          case ToolkitSyncOutcome.retryScheduled:
          case ToolkitSyncOutcome.sessionPaused:
          case ToolkitSyncOutcome.notDue:
            return ToolkitCloudDeleteResult.pending;
          case ToolkitSyncOutcome.synced:
          case ToolkitSyncOutcome.alreadySynced:
          case ToolkitSyncOutcome.rejected:
          case ToolkitSyncOutcome.remoteDeleted:
          case ToolkitSyncOutcome.accountChanged:
          case ToolkitSyncOutcome.notFound:
            return ToolkitCloudDeleteResult.failed;
        }
      }
      if (_remoteById.containsKey(documentId)) {
        await _repository.remove(documentId);
        _remoteById = <String, ToolkitDocumentMetadata>{
          for (final e in _remoteById.entries)
            if (e.key != documentId) e.key: e.value,
        };
      }
      return ToolkitCloudDeleteResult.deleted;
    } on ToolkitDocumentException {
      return ToolkitCloudDeleteResult.failed;
    }
  }

  @override
  Future<ToolkitDownloadResult> download({
    required ToolkitDocumentMetadata document,
    required File target,
  }) =>
      _downloads.ensureLocalCopy(
        documentId: document.documentId,
        target: target,
        known: document,
      );

  @override
  Future<void> dispose() async {
    if (shared) return;
    await shutdown();
  }

  /// Stops the library for good (a shared one when its account is no longer the
  /// signed-in one). Work already in flight finishes; nothing new starts.
  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    await _coordinator.dispose();
    await _deletions.close();
  }
}
