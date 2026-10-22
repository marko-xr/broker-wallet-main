// What a Toolkit tool needs to keep its documents in the signed-in user's account,
// in one object a view model owns:
//
//  * every document on the phone is recorded on the journal and uploaded (also
//    one made before the cloud was on, and one saved while offline);
//  * every document the account holds that this phone does not (a new phone, or a
//    reinstall) is LISTED from its metadata alone ([remoteOnly]), at once from the
//    copy of the last list and then from the account, so the tool shows it as an
//    ordinary card without downloading anything. The file is fetched, verified
//    and handed to the tool to store only when the user opens, shares or exports
//    that card ([ensureLocal]);
//  * a delete reaches the account first, and the phone's file goes only after the
//    server confirmed it (a delete that cannot reach the server is recorded and
//    finished later, and the document is hidden meanwhile);
//  * a rename reaches the account copy;
//  * the state is reported truthfully ([remoteStatus], [ToolkitCloudSummary]),
//    including WHY the account could not be reached, so a failed list is never
//    mistaken for an empty library.
//
// It owns no widgets and no file of the tool: the tool supplies what is on the
// phone ([localDocuments]) and how to store a downloaded file ([restoreOne]).
// It never deletes a local file itself.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_diagnostics.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';

/// Stores one downloaded document in the tool: download it with
/// `library.download(...)`, then add it to the tool's own store. True when it is
/// stored; false when it is not, and the user can open it again. An exception
/// is classified by [ToolkitCloudSync.ensureLocal] (a [ToolkitDocumentException]
/// names the reason).
typedef ToolkitRestoreOne = Future<bool> Function(
  ToolkitDocumentMetadata document,
  ToolkitCloudLibrary library,
);

/// How a request to have one account document on the phone ended.
enum ToolkitEnsureResult {
  /// The verified file is on the phone and listed by the tool's own store.
  ready,

  /// It could not be fetched now (no connection, a busy server, a download that
  /// did not verify). The card stays listed and opening it again retries.
  unavailable,

  /// The phone is out of storage space.
  storageFull,

  /// The account no longer holds it (deleted elsewhere): it is not listed any
  /// more.
  gone,
}

/// What is known about the account's list of one tool's documents.
enum ToolkitRemoteStatus {
  /// The account has not answered yet (the copy of the last list, if any, is
  /// what is shown).
  notAsked,

  /// The account's current list is known.
  loaded,

  /// The last attempt to read the list failed. Cards from the copy of the last
  /// list stay; with none, the screen must say the library could not be loaded
  /// and offer a retry, never show an empty library.
  unavailable,
}

/// Puts the documents the account holds but the phone does not among the
/// phone's, without touching the phone's order. Both lists are newest first
/// (creation time descending, then id), and the result is the same.
List<T> mergeToolkitDocuments<T>({
  required List<T> local,
  required List<ToolkitDocumentMetadata> remote,
  required String Function(T) idOf,
  required DateTime Function(T) createdAtOf,
  required T Function(ToolkitDocumentMetadata) fromRemote,
}) {
  if (remote.isEmpty) return local;
  final merged = <T>[];
  var i = 0;
  var j = 0;
  while (i < local.length || j < remote.length) {
    if (j >= remote.length) {
      merged.add(local[i++]);
      continue;
    }
    if (i >= local.length) {
      merged.add(fromRemote(remote[j++]));
      continue;
    }
    final byDate = createdAtOf(local[i]).compareTo(remote[j].sourceCreatedAt);
    final localFirst = byDate > 0 ||
        (byDate == 0 && idOf(local[i]).compareTo(remote[j].documentId) <= 0);
    merged.add(localFirst ? local[i++] : fromRemote(remote[j++]));
  }
  return merged;
}

/// What the user should be told about the account copy of a tool's documents.
enum ToolkitCloudNotice {
  /// Documents are being downloaded from the account.
  restoring,

  /// Everything on the phone is in the account.
  allSaved,

  /// Some documents wait for their upload.
  waiting,

  /// The account cannot be reached now (no connection, or a busy server).
  offline,

  /// The session was refused or replaced: signing in again fixes it.
  signInAgain,

  /// The server answered but does not offer the cloud copy (or refused this
  /// build): nothing the user can fix on the phone.
  serverNotReady,

  /// Some documents are over a cloud limit and stay on the phone.
  overLimit,

  /// Some documents cannot be backed up for another reason.
  attention,
}

/// The state of one tool's documents in the account, for the screen's status line.
@immutable
class ToolkitCloudSummary {
  const ToolkitCloudSummary({
    required this.enabled,
    this.restoring = false,
    this.restoredCount = 0,
    this.restoreTotal = 0,
    this.unreachable = false,
    this.waiting = 0,
    this.rejected = 0,
    this.saved = 0,
    this.failure,
  });

  /// This build and this account use the cloud copy.
  final bool enabled;

  /// Documents are being downloaded; [restoredCount] of [restoreTotal] are done.
  final bool restoring;
  final int restoredCount;
  final int restoreTotal;

  /// The last attempt to ask the account failed (see [failure]).
  final bool unreachable;

  /// Documents on the phone not in the account yet.
  final int waiting;

  /// Documents that will not upload as they are (over a limit, not a valid file).
  final int rejected;

  /// Documents the server confirmed.
  final int saved;

  /// Why the account could not be reached, or why a document is waiting.
  final ToolkitFailure? failure;

  static const ToolkitCloudSummary off = ToolkitCloudSummary(enabled: false);

  /// The notice for [failure].
  static ToolkitCloudNotice noticeForFailure(ToolkitFailure failure) =>
      switch (failure) {
        ToolkitFailure.sessionSuperseded ||
        ToolkitFailure.unauthorized ||
        ToolkitFailure.notSignedIn ||
        ToolkitFailure.accountChanged =>
          ToolkitCloudNotice.signInAgain,
        ToolkitFailure.forbidden ||
        ToolkitFailure.routeUnavailable ||
        ToolkitFailure.notConfigured =>
          ToolkitCloudNotice.serverNotReady,
        ToolkitFailure.tooLarge ||
        ToolkitFailure.storageLimit ||
        ToolkitFailure.documentLimit =>
          ToolkitCloudNotice.overLimit,
        ToolkitFailure.unavailable ||
        ToolkitFailure.interrupted ||
        ToolkitFailure.rateLimited ||
        ToolkitFailure.tooManyPending =>
          ToolkitCloudNotice.offline,
        _ => ToolkitCloudNotice.attention,
      };

  /// The one sentence to show, or null when there is nothing worth saying (the
  /// cloud is off, or the account holds nothing and nothing is wrong).
  ToolkitCloudNotice? get notice {
    if (!enabled) return null;
    if (restoring) return ToolkitCloudNotice.restoring;
    final problem = failure;
    if (unreachable) {
      return noticeForFailure(problem ?? ToolkitFailure.unavailable);
    }
    if (waiting > 0) {
      return problem == null
          ? ToolkitCloudNotice.waiting
          : noticeForFailure(problem);
    }
    if (rejected > 0) {
      return problem == null
          ? ToolkitCloudNotice.attention
          : noticeForFailure(problem);
    }
    return saved == 0 ? null : ToolkitCloudNotice.allSaved;
  }
}

/// How a tool's delete request split up (see [ToolkitCloudSync.deleteFirst]).
@immutable
class ToolkitDeleteSplit {
  const ToolkitDeleteSplit({
    required this.deleteLocally,
    required this.pending,
    required this.failed,
  });

  /// The account's copy is gone (or never existed): remove the phone's file now.
  final List<String> deleteLocally;

  /// The delete is recorded and waits for the server: the document is hidden, and
  /// its file is removed when the confirmation arrives.
  final List<String> pending;

  /// Nothing changed.
  final List<String> failed;
}

class ToolkitCloudSync {
  ToolkitCloudSync({
    required this.type,
    required ToolkitCloudLibrary library,
    required List<ToolkitCloudLocalDocument> Function() localDocuments,
    required ToolkitRestoreOne restoreOne,
    required Future<void> Function(String id) removeLocal,
    required void Function() onChanged,
    Future<void> Function()? onRestoredOne,
    Duration syncInterval = const Duration(seconds: 60),
  })  : _library = library,
        _localDocuments = localDocuments,
        _restoreOne = restoreOne,
        _removeLocal = removeLocal,
        _onChanged = onChanged,
        _onRestoredOne = onRestoredOne,
        _syncInterval = syncInterval;

  final ToolkitDocumentType type;
  final ToolkitCloudLibrary _library;
  final List<ToolkitCloudLocalDocument> Function() _localDocuments;
  final ToolkitRestoreOne _restoreOne;
  final Future<void> Function(String id) _removeLocal;
  final void Function() _onChanged;
  final Future<void> Function()? _onRestoredOne;
  final Duration _syncInterval;

  StreamSubscription<ToolkitSyncUpdate>? _updates;
  StreamSubscription<String>? _deletions;
  Timer? _timer;
  bool _disposed = false;
  bool _running = false;
  bool _again = false;
  bool _unreachable = false;
  ToolkitFailure? _unreachableFailure;
  final Set<Future<void>> _background = <Future<void>>{};

  // The account's documents the phone may lack, newest first: from the copy of
  // the last list until the account answers, then from its current list.
  List<ToolkitDocumentMetadata> _remote = const <ToolkitDocumentMetadata>[];
  Map<String, ToolkitDocumentMetadata> _remoteById =
      const <String, ToolkitDocumentMetadata>{};
  ToolkitRemoteStatus _remoteStatus = ToolkitRemoteStatus.notAsked;
  final Map<String, Future<ToolkitEnsureResult>> _fetching =
      <String, Future<ToolkitEnsureResult>>{};

  /// A document is being fetched from the account for the user.
  bool get isFetching => _fetching.isNotEmpty;

  /// Whether [id] is being fetched from the account now.
  bool isFetchingDocument(String id) => _fetching.containsKey(id);

  /// What is known about the account's list. See [ToolkitRemoteStatus].
  ToolkitRemoteStatus get remoteStatus => _remoteStatus;

  /// The documents the account holds that the phone does not list, newest first.
  /// Their cards are shown from this metadata alone; the file is fetched by
  /// [ensureLocal] when the user opens one. A document whose delete is waiting
  /// for the server is left out.
  List<ToolkitDocumentMetadata> get remoteOnly {
    if (_remote.isEmpty) return _remote;
    final onPhone = <String>{
      for (final d in _localDocuments()) d.documentId,
    };
    return <ToolkitDocumentMetadata>[
      for (final d in _remote)
        if (!onPhone.contains(d.documentId) && !isDeleting(d.documentId)) d,
    ];
  }

  /// Whether [id] is a document of the account that the phone does not list.
  bool isRemoteOnly(String id) => remoteOnly.any((d) => d.documentId == id);

  // -------------------------------------------------------------- lifecycle

  /// Starts listening and keeps the journal's retries going while it lives.
  void start() {
    _updates = _library.updates.listen((_) => _changed());
    _deletions = _library.deletions.listen((id) {
      _track(_removeLocalThenNotify(id));
    });
    // Nothing is sent before it is due; this only lets a retry whose wait has
    // passed run without the user doing anything, and asks the account again.
    _timer = Timer.periodic(_syncInterval, (_) {
      if (_disposed) return;
      unawaited(_library.syncDue());
      requestSync();
    });
    final started = _library.start();
    unawaited(started);
    // The cards of the last list appear before the account answers (after the
    // journal is read, so a delete that is waiting for the server stays hidden).
    _track(started.then((_) => _showCached()));
  }

  /// Shows the copy of the account's last list, unless the account has already
  /// answered. A copy that cannot be read is simply no copy.
  Future<void> _showCached() async {
    final cached = await _library.cachedRemote(type);
    if (_disposed ||
        cached.isEmpty ||
        _remoteStatus == ToolkitRemoteStatus.loaded) {
      return;
    }
    _setRemote(cached);
    _changed();
  }

  /// Stops this object. A shared library keeps running (see
  /// [ToolkitCloudLibrary.dispose]).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_updates?.cancel());
    unawaited(_deletions?.cancel());
    _updates = null;
    _deletions = null;
    unawaited(_library.dispose());
  }

  void _changed() {
    if (!_disposed) _onChanged();
  }

  void _track(Future<void> work) {
    _background.add(work);
    unawaited(
      work.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _background.remove(work);
      }),
    );
  }

  Future<void> _removeLocalThenNotify(String id) async {
    try {
      await _removeLocal(id);
    } catch (_) {
      // Still listed; the user can delete it again.
    }
    _changed();
  }

  /// Completes when nothing this object started is still running. For tests and
  /// shutdown, so no file is open when a folder is removed.
  Future<void> settle() async {
    while (true) {
      final pending = _background.toList();
      if (pending.isNotEmpty) {
        await Future.wait(pending);
        continue;
      }
      await _library.idle();
      if (_background.isEmpty) return;
    }
  }

  // ------------------------------------------------------------------- sync

  /// Compares the phone with the account, uploads what the account lacks and
  /// downloads what the phone lacks. Single flight: a request made while one is
  /// running makes it run once more when it ends.
  void requestSync() {
    if (_disposed) return;
    _track(_run());
  }

  Future<void> _run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _once();
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _once() async {
    final local = _localDocuments();
    try {
      // Journal first (no network): a document saved offline is queued at once.
      await _library.recordLocal(type: type, local: local);
      final result = await _library.reconcile(type: type, local: local);
      if (_disposed) return;
      _unreachable = false;
      _unreachableFailure = null;
      _setRemote(result.remoteOnly);
      _remoteStatus = ToolkitRemoteStatus.loaded;
    } on ToolkitDocumentException catch (error) {
      if (_disposed) return;
      // The library has already named the step that failed.
      _unreachable = true;
      _unreachableFailure = error.failure;
      _markUnavailable();
    } catch (error) {
      if (_disposed) return;
      _unreachable = true;
      _unreachableFailure = ToolkitFailure.unavailable;
      _markUnavailable();
      ToolkitDiagnostics.report('sync-failed', type: type, error: error);
    }
    _changed();
  }

  /// A list that failed after an earlier one succeeded does not make the
  /// library "unavailable": what the account said last is still the best answer
  /// (an account with no documents stays an empty library, not an error).
  void _markUnavailable() {
    if (_remoteStatus != ToolkitRemoteStatus.loaded) {
      _remoteStatus = ToolkitRemoteStatus.unavailable;
    }
  }

  /// Keeps [documents] (newest first) as the account's documents the phone may
  /// lack. Pure bookkeeping: nothing is downloaded.
  void _setRemote(List<ToolkitDocumentMetadata> documents) {
    final sorted = List<ToolkitDocumentMetadata>.of(documents)
      ..sort((a, b) {
        final byDate = b.sourceCreatedAt.compareTo(a.sourceCreatedAt);
        return byDate != 0 ? byDate : a.documentId.compareTo(b.documentId);
      });
    _remote = List<ToolkitDocumentMetadata>.unmodifiable(sorted);
    _remoteById = <String, ToolkitDocumentMetadata>{
      for (final d in sorted) d.documentId: d,
    };
  }

  void _forget(Iterable<String> ids) {
    final gone = ids.toSet();
    if (gone.isEmpty) return;
    _setRemote(<ToolkitDocumentMetadata>[
      for (final d in _remote)
        if (!gone.contains(d.documentId)) d,
    ]);
  }

  // ------------------------------------------------------------ opening

  /// Brings the account's document [id] onto the phone for the user who opened,
  /// shared or exported its card: downloads it, verifies it and hands it to the
  /// tool's store ([restoreOne]). A document that is already on the phone is not
  /// touched (the caller asks only for [isRemoteOnly] ones). Two requests for one
  /// id share one download. A failure keeps the card listed, so the user can try
  /// again, and is reported to [ToolkitDiagnostics] by its category.
  Future<ToolkitEnsureResult> ensureLocal(String id) {
    final running = _fetching[id];
    if (running != null) return running;
    final run = _ensure(id);
    _fetching[id] = run;
    _changed();
    final tracked = run.whenComplete(() {
      _fetching.remove(id);
      _changed();
    });
    _track(tracked.then<void>((_) {}, onError: (Object _) {}));
    return tracked;
  }

  Future<ToolkitEnsureResult> _ensure(String id) async {
    final document = _remoteById[id];
    if (document == null || _disposed) return ToolkitEnsureResult.gone;
    try {
      final stored = await _restoreOne(document, _library);
      if (_disposed) return ToolkitEnsureResult.unavailable;
      if (!stored) {
        ToolkitDiagnostics.report('open-not-stored',
            type: type, documentId: id);
        return ToolkitEnsureResult.unavailable;
      }
      _forget(<String>[id]);
      final refreshed = _onRestoredOne;
      if (refreshed != null) {
        try {
          await refreshed();
        } catch (error) {
          ToolkitDiagnostics.report('open-refresh-failed',
              type: type, documentId: id, error: error);
        }
      }
      // The file is on the phone but not yet on the journal: one more pass
      // records it (the server confirms it as already held, nothing is sent).
      requestSync();
      return ToolkitEnsureResult.ready;
    } on ToolkitDocumentException catch (error) {
      ToolkitDiagnostics.report('open-failed',
          type: type, documentId: id, error: error);
      switch (error.failure) {
        case ToolkitFailure.documentDeleted:
        case ToolkitFailure.documentNotFound:
          _forget(<String>[id]);
          return ToolkitEnsureResult.gone;
        case ToolkitFailure.insufficientStorage:
          return ToolkitEnsureResult.storageFull;
        default:
          return ToolkitEnsureResult.unavailable;
      }
    } catch (error) {
      ToolkitDiagnostics.report('open-failed',
          type: type, documentId: id, error: error);
      return ToolkitEnsureResult.unavailable;
    }
  }

  /// Takes ids out of the list of documents the phone may lack (their delete was
  /// confirmed by the account).
  void removeRemoteOnly(Iterable<String> ids) {
    _forget(ids);
    _changed();
  }

  /// Renames a document that only the account holds. True when the account took
  /// the new title; false when it could not be reached now (nothing changed).
  Future<bool> renameRemoteOnly(String id, String title) async {
    final clean = ToolkitDocumentTitles.sanitize(title);
    try {
      await _library.rename(id, clean);
    } catch (error) {
      ToolkitDiagnostics.report('rename-failed',
          type: type, documentId: id, error: error);
      return false;
    }
    final known = _remoteById[id];
    if (known != null) {
      _setRemote(<ToolkitDocumentMetadata>[
        for (final d in _remote)
          d.documentId == id ? d.copyWith(title: clean) : d,
      ]);
    }
    _changed();
    return true;
  }

  // ---------------------------------------------------------------- actions

  /// Whether the user's delete of [id] is recorded and waiting for the server.
  bool isDeleting(String id) {
    final entry = _library.entryFor(id);
    return entry != null &&
        entry.deleteRequested &&
        entry.state == ToolkitDocumentSyncState.deletePending;
  }

  /// Sends the delete of [ids] to the account FIRST. The caller removes the
  /// phone's file only for [ToolkitDeleteSplit.deleteLocally].
  Future<ToolkitDeleteSplit> deleteFirst(List<String> ids) async {
    final deleteLocally = <String>[];
    final pending = <String>[];
    final failed = <String>[];
    for (final id in ids) {
      final ToolkitCloudDeleteResult result;
      try {
        result = await _library.delete(id);
      } catch (_) {
        failed.add(id);
        continue;
      }
      switch (result) {
        case ToolkitCloudDeleteResult.deleted:
          deleteLocally.add(id);
        case ToolkitCloudDeleteResult.pending:
          pending.add(id);
        case ToolkitCloudDeleteResult.failed:
          failed.add(id);
      }
    }
    _changed();
    return ToolkitDeleteSplit(
      deleteLocally: deleteLocally,
      pending: pending,
      failed: failed,
    );
  }

  /// Sends a new title to the account copy. Never throws: the phone's title is
  /// the user's, and a failure to reach the account is kept and retried.
  Future<void> rename(String id, String title) async {
    try {
      await _library.rename(id, ToolkitDocumentTitles.sanitize(title));
    } catch (_) {}
  }

  /// The user asked to try again now: every document that is waiting is retried.
  Future<void> retryNow() async {
    for (final entry in _library.entries) {
      if (entry.type != type) continue;
      final waiting =
          entry.state == ToolkitDocumentSyncState.syncFailedRetryable ||
              entry.state == ToolkitDocumentSyncState.savedLocallyPendingSync;
      if (!waiting) continue;
      try {
        await _library.retry(entry.documentId);
      } catch (_) {}
    }
    requestSync();
  }

  // ---------------------------------------------------------------- summary

  /// What the screen's status line says now.
  ToolkitCloudSummary summary() => summarizeToolkitCloud(
        library: _library,
        documentIds: <String>[
          for (final d in _localDocuments()) d.documentId,
        ],
        restoring: isFetching,
        unreachable: _unreachable,
        unreachableFailure: _unreachableFailure,
      );
}

/// Counts the documents on the phone ([documentIds]) by what [library]'s journal
/// says about each: confirmed by the server, waiting (not on the journal yet, or
/// waiting for its upload) or rejected (it will not upload as it is). A document
/// whose delete is recorded, or that was deleted elsewhere, is not counted.
ToolkitCloudSummary summarizeToolkitCloud({
  required ToolkitCloudLibrary library,
  required Iterable<String> documentIds,
  bool restoring = false,
  int restoredCount = 0,
  int restoreTotal = 0,
  bool unreachable = false,
  ToolkitFailure? unreachableFailure,
}) {
  var saved = 0;
  var waiting = 0;
  var rejected = 0;
  ToolkitFailure? failure = unreachableFailure;
  for (final id in documentIds) {
    final entry = library.entryFor(id);
    if (entry == null) {
      waiting++;
      continue;
    }
    if (entry.deleteRequested &&
        entry.state == ToolkitDocumentSyncState.deletePending) {
      continue;
    }
    if (entry.isCloudConfirmed &&
        entry.state == ToolkitDocumentSyncState.savedToCloud) {
      saved++;
      continue;
    }
    if (entry.state == ToolkitDocumentSyncState.remoteDeleted) continue;
    if (entry.state == ToolkitDocumentSyncState.syncRejected) {
      rejected++;
    } else {
      waiting++;
    }
    failure ??= entry.lastFailure;
  }
  return ToolkitCloudSummary(
    enabled: true,
    restoring: restoring,
    restoredCount: restoredCount,
    restoreTotal: restoreTotal,
    unreachable: unreachable,
    waiting: waiting,
    rejected: rejected,
    saved: saved,
    failure: failure,
  );
}
