// What a Toolkit tool needs to keep its documents in the signed-in user's account,
// in one object a view model owns:
//
//  * every document on the phone is recorded on the journal and uploaded (also
//    one made before the cloud was on, and one saved while offline);
//  * every document the account holds that this phone does not (a new phone, or a
//    reinstall) is downloaded, verified and handed to the tool to store, so the
//    tool's own list shows it like any other;
//  * a delete reaches the account first, and the phone's file goes only after the
//    server confirmed it (a delete that cannot reach the server is recorded and
//    finished later, and the document is hidden meanwhile);
//  * a rename reaches the account copy;
//  * the state is reported truthfully ([ToolkitCloudSummary]), including WHY the
//    account could not be reached, so a failure is never a silent "nothing
//    happened".
//
// It owns no widgets and no file of the tool: the tool supplies what is on the
// phone ([localDocuments]) and how to store a downloaded file ([restoreOne]).
// It never deletes a local file itself.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';

/// Stores one downloaded document in the tool: download it with
/// `library.download(...)`, then add it to the tool's own store. True when it is
/// stored; false (or an exception) when it is not, and it is tried again later.
typedef ToolkitRestoreOne = Future<bool> Function(
  ToolkitDocumentMetadata document,
  ToolkitCloudLibrary library,
);

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
  bool _restoring = false;
  int _restoreDone = 0;
  int _restoreTotal = 0;
  final Set<Future<void>> _background = <Future<void>>{};

  /// A restore is running.
  bool get isRestoring => _restoring;

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
    unawaited(_library.start());
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
      await _restore(result.remoteOnly);
    } on ToolkitDocumentException catch (error) {
      if (_disposed) return;
      _unreachable = true;
      _unreachableFailure = error.failure;
    } catch (_) {
      if (_disposed) return;
      _unreachable = true;
      _unreachableFailure = ToolkitFailure.unavailable;
    }
    _changed();
  }

  /// Brings [missing] (in the account, not on the phone) onto the phone, newest
  /// first. A document that cannot be stored now is left for the next pass; three
  /// failures in a row stop this pass (the connection or the account is the
  /// problem, not one file).
  Future<void> _restore(List<ToolkitDocumentMetadata> missing) async {
    if (missing.isEmpty) return;
    final todo = List<ToolkitDocumentMetadata>.of(missing)
      ..sort((a, b) => b.sourceCreatedAt.compareTo(a.sourceCreatedAt));
    _restoring = true;
    _restoreDone = 0;
    _restoreTotal = todo.length;
    _changed();
    var failuresInARow = 0;
    try {
      for (final document in todo) {
        if (_disposed || failuresInARow >= 3) break;
        var stored = false;
        try {
          stored = await _restoreOne(document, _library);
        } catch (_) {
          stored = false;
        }
        if (stored) {
          failuresInARow = 0;
          _restoreDone++;
          final refreshed = _onRestoredOne;
          if (refreshed != null) {
            try {
              await refreshed();
            } catch (_) {}
          }
        } else {
          failuresInARow++;
        }
        _changed();
      }
    } finally {
      _restoring = false;
    }
    // What was just stored is on the phone but not yet on the journal: one more
    // pass records it (the server confirms it as already held).
    if (_restoreDone > 0) _again = true;
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
        restoring: _restoring,
        restoredCount: _restoreDone,
        restoreTotal: _restoreTotal,
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
