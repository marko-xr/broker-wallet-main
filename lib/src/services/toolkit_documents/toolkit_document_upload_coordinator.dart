// Moves Toolkit documents from this phone into the user's cloud account, safely.
//
// What it guarantees:
//  * A document is "saved to the cloud" only after the SERVER confirmed the
//    stored bytes. Every earlier state says it is on this phone only.
//  * It never deletes, moves or rewrites a local file. The last verified local
//    copy stays until the server confirmed (and, for a delete, the user asked
//    for it); the coordinator has no way to remove a local file at all.
//  * Every step is idempotent on the document id, so a retry after any failure
//    (offline before the upload, a timeout after the server confirmed, a
//    force-stop mid-transfer, a duplicate request) never creates a second copy.
//  * Work survives restarts: it lives in a [ToolkitSyncJournal].
//  * It only acts for ONE account. If another account is signed in, it stops
//    before sending anything and leaves the entry as it was.
//  * A document deleted elsewhere is never uploaded again (see the
//    `documentDeleted` handling), and a delete requested here wins over an
//    upload in flight.
//
// There are no timers: the app calls [syncDue] when it starts, when the network
// returns and when the user signs in. Waiting is expressed as a `nextAttemptAt`
// in the journal.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_file_probe.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

/// Finds the local file of an entry in the tool's own store. It must never
/// create, move or delete anything.
abstract interface class ToolkitLocalFiles {
  /// The stored file, or null when it is no longer on the phone.
  Future<File?> resolve(ToolkitSyncEntry entry);
}

enum ToolkitSyncOutcome {
  /// Confirmed by the server just now.
  synced,

  /// Already confirmed earlier; nothing to do.
  alreadySynced,

  /// The server confirmed the removal.
  deleted,

  /// The attempt failed and will be retried (or waits for the user).
  retryScheduled,

  /// This document will not upload as it is (see the entry's `lastFailure`).
  rejected,

  /// Deleted from the account on another device; kept locally, never uploaded.
  remoteDeleted,

  /// Another phone took over the account: nothing more is sent from here.
  sessionPaused,

  /// A different account is signed in; the entry was left untouched.
  accountChanged,

  /// Its retry time has not come.
  notDue,

  /// No such entry.
  notFound,
}

@immutable
class ToolkitSyncUpdate {
  const ToolkitSyncUpdate(this.documentId, this.state, [this.failure]);

  final String documentId;
  final ToolkitDocumentSyncState state;
  final ToolkitFailure? failure;
}

class _AccountChanged implements Exception {
  const _AccountChanged();
}

class _DeleteRequested implements Exception {
  const _DeleteRequested();
}

class ToolkitDocumentUploadCoordinator {
  ToolkitDocumentUploadCoordinator({
    required this.accountId,
    required ToolkitDocumentTransport transport,
    required ToolkitSyncJournal journal,
    required ToolkitLocalFiles files,
    required String? Function() currentAccountId,
    DateTime Function()? clock,
    double Function()? jitter,
    ToolkitFileHasher? hasher,
    this.baseBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(hours: 1),
    this.maxAutoAttempts = 8,
    this.maxConcurrent = 2,
    this.maxDocumentBytes = ToolkitDocumentLimits.defaultDocumentBytes,
    this.maxImageBytes = ToolkitDocumentLimits.defaultImageBytes,
  })  : _transport = transport,
        _journal = journal,
        _files = files,
        _currentAccountId = currentAccountId,
        _clock = clock ?? DateTime.now,
        _jitter = jitter ?? (() => 0),
        _hasher = hasher ?? ToolkitSha256.hexOfFile {
    if (transport.accountId != accountId) {
      throw ArgumentError('The transport serves another account');
    }
  }

  final String accountId;
  final ToolkitDocumentTransport _transport;
  final ToolkitSyncJournal _journal;
  final ToolkitLocalFiles _files;
  final String? Function() _currentAccountId;
  final DateTime Function() _clock;
  final double Function() _jitter;
  final ToolkitFileHasher _hasher;

  final Duration baseBackoff;
  final Duration maxBackoff;

  /// After this many failed attempts the document waits for the user's retry.
  final int maxAutoAttempts;
  final int maxConcurrent;
  final int maxDocumentBytes;
  final int maxImageBytes;

  final Map<String, ToolkitSyncEntry> _entries = <String, ToolkitSyncEntry>{};
  final Map<String, Future<ToolkitSyncOutcome>> _running =
      <String, Future<ToolkitSyncOutcome>>{};
  final StreamController<ToolkitSyncUpdate> _updates =
      StreamController<ToolkitSyncUpdate>.broadcast();
  Future<void> _journalTail = Future<void>.value();
  bool _disposed = false;

  Stream<ToolkitSyncUpdate> get updates => _updates.stream;

  List<ToolkitSyncEntry> get entries => List.unmodifiable(_entries.values);

  ToolkitSyncEntry? entryFor(String documentId) => _entries[documentId];

  // ------------------------------------------------------------------ setup

  /// Reads the journal. An entry that was mid-transfer when the app stopped
  /// goes back to waiting; entries of another account are not loaded.
  Future<void> load() async {
    final stored = await _journal.load();
    _entries.clear();
    for (final entry in stored) {
      if (entry.accountId != accountId) continue;
      final interrupted =
          entry.state == ToolkitDocumentSyncState.syncInProgress;
      _entries[entry.documentId] = interrupted
          ? entry.copyWith(
              state: ToolkitDocumentSyncState.savedLocallyPendingSync,
              clearNextAttempt: true,
            )
          : entry;
    }
  }

  /// Queues a document for the cloud. Idempotent on the id: an id already
  /// known (waiting, confirmed or rejected) is returned as it is, so saving
  /// twice, or re-queueing after a restart, cannot start a second upload.
  Future<ToolkitSyncEntry> enqueue(ToolkitSyncEntry entry) async {
    if (entry.accountId != accountId) {
      throw ArgumentError('The document belongs to another account');
    }
    if (!ToolkitDocumentIds.isCanonical(entry.documentId)) {
      throw ArgumentError('The document id is not a canonical UUID');
    }
    if (!entry.contentType.allowedFor(entry.type)) {
      throw ArgumentError('This tool cannot store that format');
    }
    final known = _entries[entry.documentId];
    if (known != null) return known;
    final fresh = entry.copyWith(
      title: ToolkitDocumentTitles.sanitize(entry.title),
      state: ToolkitDocumentSyncState.savedLocallyPendingSync,
      attempts: 0,
      clearNextAttempt: true,
      clearFailure: true,
    );
    return _store(fresh);
  }

  // ------------------------------------------------------------------- sync

  /// Uploads (or finishes) one document. Single flight: a second call while one
  /// is running joins it.
  Future<ToolkitSyncOutcome> sync(String documentId, {bool manual = false}) {
    final running = _running[documentId];
    if (running != null) return running;
    final run = _run(documentId, manual: manual);
    _running[documentId] = run;
    return run.whenComplete(() => _running.remove(documentId));
  }

  /// The user asked to try again now: forgets the failure count and the wait.
  ///
  /// [acknowledgeStale] is the user's explicit decision to back up a document that
  /// predates the account's deletion history ([ToolkitFailure.staleDocument]); it
  /// is never set automatically.
  Future<ToolkitSyncOutcome> retry(
    String documentId, {
    bool acknowledgeStale = false,
  }) async {
    final entry = _entries[documentId];
    if (entry == null) return ToolkitSyncOutcome.notFound;
    if (entry.state == ToolkitDocumentSyncState.syncRejected ||
        entry.state == ToolkitDocumentSyncState.syncFailedRetryable) {
      await _store(entry.copyWith(
        staleAcknowledged: acknowledgeStale ? true : null,
        state: ToolkitDocumentSyncState.savedLocallyPendingSync,
        attempts: 0,
        clearNextAttempt: true,
        clearFailure: true,
      ));
    }
    return sync(documentId, manual: true);
  }

  /// Runs everything that is due, [maxConcurrent] at a time.
  Future<Map<String, ToolkitSyncOutcome>> syncDue() async {
    final now = _clock();
    final due = _entries.values
        .where((e) => _isDue(e, now))
        .map((e) => e.documentId)
        .toList()
      ..sort();
    final results = <String, ToolkitSyncOutcome>{};
    for (var i = 0; i < due.length; i += maxConcurrent) {
      final batch = due.skip(i).take(maxConcurrent).toList();
      final outcomes = await Future.wait(batch.map(sync));
      for (var j = 0; j < batch.length; j++) {
        results[batch[j]] = outcomes[j];
      }
    }
    return results;
  }

  bool _isDue(ToolkitSyncEntry entry, DateTime now) {
    final waiting = entry.state.needsSync || entry.titlePending;
    if (!waiting || entry.state == ToolkitDocumentSyncState.syncInProgress) {
      return false;
    }
    // A document whose automatic retries ran out waits for the user.
    if (entry.state == ToolkitDocumentSyncState.syncFailedRetryable &&
        entry.nextAttemptAt == null) {
      return false;
    }
    // Another phone took over the account: nothing is sent until the user signs
    // in again here (see [resumeAfterSignIn]).
    if (entry.lastFailure == ToolkitFailure.sessionSuperseded) return false;
    final at = entry.nextAttemptAt;
    return at == null || !at.isAfter(now);
  }

  /// The user signed in again on this phone: entries paused by a replaced
  /// session may run again.
  Future<void> resumeAfterSignIn() async {
    for (final entry in _entries.values.toList()) {
      if (entry.lastFailure == ToolkitFailure.sessionSuperseded) {
        await _store(
            entry.copyWith(clearFailure: true, clearNextAttempt: true));
      }
    }
  }

  // ----------------------------------------------------------------- delete

  /// The user deleted this document. The removal is confirmed by the server
  /// before the entry is forgotten, and it wins over an upload in flight. The
  /// local file is the library's to remove, after [ToolkitSyncOutcome.deleted].
  Future<ToolkitSyncOutcome> requestDelete(String documentId) async {
    final entry = _entries[documentId];
    if (entry == null) return ToolkitSyncOutcome.notFound;
    await _store(entry.copyWith(
      state: ToolkitDocumentSyncState.deletePending,
      deleteRequested: true,
      clearNextAttempt: true,
    ));
    return sync(documentId, manual: true);
  }

  // ----------------------------------------------------------------- rename

  /// Changes the title the user wants. For a document that is not in the cloud
  /// yet the new title is simply what will be uploaded; for a confirmed one it
  /// is sent now, and kept pending (and retried) if that fails.
  ///
  /// Conflict policy: a rename never touches the document's bytes, so a rename
  /// made here and one made elsewhere cannot lose content. A stale version is
  /// retried ONCE against the version the server reports, so the title the user
  /// typed last wins; the server's version counter still orders every change.
  Future<void> rename(String documentId, String title) async {
    final entry = _entries[documentId];
    if (entry == null) throw StateError('Unknown document');
    final problem = ToolkitDocumentTitles.problemWith(title);
    if (problem != null) throw ArgumentError('Invalid title: $problem');
    final updated = await _store(entry.copyWith(title: title));
    if (updated.isCloudConfirmed && !updated.deleteRequested) {
      await _syncTitle(documentId);
    }
  }

  // ------------------------------------------------------------------ guts

  Future<ToolkitSyncOutcome> _run(
    String documentId, {
    required bool manual,
  }) async {
    final found = _entries[documentId];
    if (found == null) return ToolkitSyncOutcome.notFound;
    var entry = found;
    if (_currentAccountId() != accountId) {
      return ToolkitSyncOutcome.accountChanged;
    }

    if (!entry.deleteRequested) {
      if (entry.state == ToolkitDocumentSyncState.remoteDeleted) {
        return ToolkitSyncOutcome.remoteDeleted;
      }
      if (entry.state == ToolkitDocumentSyncState.syncRejected && !manual) {
        return ToolkitSyncOutcome.rejected;
      }
      if (entry.isCloudConfirmed) {
        if (!entry.titlePending) return ToolkitSyncOutcome.alreadySynced;
        return _guard(entry, () async {
          await _syncTitle(documentId, failHard: true);
          return ToolkitSyncOutcome.alreadySynced;
        });
      }
    }
    final at = entry.nextAttemptAt;
    if (!manual && at != null && at.isAfter(_clock())) {
      return ToolkitSyncOutcome.notDue;
    }

    return _guard(entry, () async {
      if (entry.deleteRequested) return _finishDelete(entry);
      entry = await _store(entry.copyWith(
        state: ToolkitDocumentSyncState.syncInProgress,
        clearFailure: true,
      ));
      final file = await _verifiedLocalFile(entry);
      entry = await _withHash(entry, file);
      _checkpoint(documentId);

      final authorization = await _transport.authorize(
        documentId: documentId,
        type: entry.type,
        contentType: entry.contentType,
        title: _entries[documentId]!.title,
        contentLength: entry.sizeBytes,
        pageCount: entry.pageCount,
        contentSha256: entry.contentSha256!,
        sourceCreatedAt: entry.sourceCreatedAt,
        acknowledgeStale: _entries[documentId]!.staleAcknowledged,
      );
      final titleSent = _entries[documentId]!.title;
      _checkpoint(documentId);

      var version = _entries[documentId]!.cloudVersion;
      if (!authorization.alreadyConfirmed) {
        await _transport.uploadBytes(
          presignedUrl: authorization.presignedUrl!,
          file: file,
          contentType: entry.contentType,
          headers: authorization.uploadHeaders,
        );
        _checkpoint(documentId);
        final confirmation = await _transport.confirm(documentId: documentId);
        version = confirmation.version;
      }

      // Only now, with the server's confirmation in hand, is it saved.
      await _store(_entries[documentId]!.copyWith(
        state: ToolkitDocumentSyncState.savedToCloud,
        cloudConfirmedAt: _clock().toUtc(),
        confirmedTitle: titleSent,
        cloudVersion: version,
        attempts: 0,
        clearNextAttempt: true,
        clearFailure: true,
      ));
      if (_entries[documentId]!.deleteRequested) {
        // Deleted while the confirmation was in flight: the delete wins.
        return _finishDelete(_entries[documentId]!);
      }
      if (_entries[documentId]!.titlePending) {
        // A rename made during the upload: send it now, but the document is
        // already safe; a failure here leaves the title pending for later.
        try {
          await _syncTitle(documentId, failHard: true);
        } on ToolkitDocumentException {
          // Stays pending; the next sync completes it.
        }
      }
      return ToolkitSyncOutcome.synced;
    });
  }

  /// Runs [body] and turns every way it can stop into a stored state.
  Future<ToolkitSyncOutcome> _guard(
    ToolkitSyncEntry entry,
    Future<ToolkitSyncOutcome> Function() body,
  ) async {
    try {
      return await body();
    } on _AccountChanged {
      await _restoreWaiting(entry.documentId);
      return ToolkitSyncOutcome.accountChanged;
    } on _DeleteRequested {
      final current = _entries[entry.documentId];
      if (current == null) return ToolkitSyncOutcome.notFound;
      try {
        return await _finishDelete(current);
      } on ToolkitDocumentException catch (error) {
        return _fail(current.documentId, error);
      } on _AccountChanged {
        return ToolkitSyncOutcome.accountChanged;
      } on _DeleteRequested {
        return ToolkitSyncOutcome.retryScheduled;
      }
    } on ToolkitDocumentException catch (error) {
      return _fail(entry.documentId, error);
    }
  }

  /// Account and delete checks between network steps.
  void _checkpoint(String documentId) {
    if (_currentAccountId() != accountId) throw const _AccountChanged();
    if (_entries[documentId]?.deleteRequested ?? false) {
      throw const _DeleteRequested();
    }
  }

  Future<File> _verifiedLocalFile(ToolkitSyncEntry entry) async {
    final File? file;
    try {
      file = await _files.resolve(entry);
    } on FileSystemException {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }
    if (file == null) {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }
    if (length != entry.sizeBytes) {
      throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
    }
    if (length >
        (entry.contentType.isImage ? maxImageBytes : maxDocumentBytes)) {
      throw const ToolkitDocumentException(ToolkitFailure.tooLarge);
    }
    // The bytes must be a complete file of the declared format: a truncated file,
    // or one whose content is not what its type says, is never uploaded.
    if (!await ToolkitFileProbe.isCompleteContainer(file, entry.contentType)) {
      throw const ToolkitDocumentException(ToolkitFailure.typeMismatch);
    }
    return file;
  }

  /// Verifies the file against its recorded hash, or records it the first time,
  /// so what is uploaded is exactly what the tool saved.
  Future<ToolkitSyncEntry> _withHash(ToolkitSyncEntry entry, File file) async {
    final String actual;
    try {
      actual = await _hasher(file);
    } on FileSystemException {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }
    final recorded = entry.contentSha256;
    if (recorded != null && recorded != actual) {
      throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
    }
    return recorded == null
        ? _store(_entries[entry.documentId]!.copyWith(contentSha256: actual))
        : entry;
  }

  Future<ToolkitSyncOutcome> _finishDelete(ToolkitSyncEntry entry) async {
    await _store(entry.copyWith(state: ToolkitDocumentSyncState.deletePending));
    if (_currentAccountId() != accountId) throw const _AccountChanged();
    await _transport.remove(documentId: entry.documentId);
    await _forget(entry.documentId);
    return ToolkitSyncOutcome.deleted;
  }

  /// Sends a pending rename. [failHard] rethrows a transport failure.
  Future<void> _syncTitle(String documentId, {bool failHard = false}) async {
    final first = _entries[documentId];
    if (first == null || !first.titlePending) return;
    try {
      var version = first.cloudVersion ?? 1;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final result = await _transport.rename(
            documentId: documentId,
            // The title the user wants now, which may have changed since.
            title: _entries[documentId]?.title ?? first.title,
            expectedVersion: version,
          );
          await _store(_entries[documentId]!.copyWith(
            confirmedTitle: result.title,
            cloudVersion: result.version,
          ));
          return;
        } on ToolkitDocumentException catch (error) {
          final current = error.currentVersion;
          if (error.failure == ToolkitFailure.staleVersion &&
              current != null &&
              attempt == 0) {
            // Retried once against what the server now holds.
            version = current;
            continue;
          }
          rethrow;
        }
      }
    } on ToolkitDocumentException catch (error) {
      if (error.failure == ToolkitFailure.documentDeleted) {
        await _store(_entries[documentId]!
            .copyWith(state: ToolkitDocumentSyncState.remoteDeleted));
        return;
      }
      if (failHard) rethrow;
    }
  }

  Future<ToolkitSyncOutcome> _fail(
    String documentId,
    ToolkitDocumentException error,
  ) async {
    final entry = _entries[documentId];
    if (entry == null) return ToolkitSyncOutcome.notFound;
    switch (error.failure) {
      case ToolkitFailure.accountChanged:
      case ToolkitFailure.notSignedIn:
        await _restoreWaiting(documentId);
        return ToolkitSyncOutcome.accountChanged;
      case ToolkitFailure.sessionSuperseded:
        await _store(entry.copyWith(
          state: ToolkitDocumentSyncState.savedLocallyPendingSync,
          lastFailure: error.failure,
          clearNextAttempt: true,
        ));
        return ToolkitSyncOutcome.sessionPaused;
      case ToolkitFailure.documentDeleted:
        return _afterDeletedAnswer(entry);
      default:
        break;
    }
    if (entry.isCloudConfirmed && !entry.deleteRequested) {
      // The document is already safe in the cloud; only a pending rename failed.
      // It stays "saved" and the rename is retried later.
      final attempts = entry.attempts + 1;
      await _store(entry.copyWith(
        attempts: attempts,
        lastFailure: error.failure,
        nextAttemptAt: attempts >= maxAutoAttempts
            ? null
            : _clock().add(_backoff(attempts, error.retryAfter)),
        clearNextAttempt: attempts >= maxAutoAttempts,
      ));
      return ToolkitSyncOutcome.retryScheduled;
    }
    if (error.failure.rejectsDocument) {
      await _store(entry.copyWith(
        state: ToolkitDocumentSyncState.syncRejected,
        lastFailure: error.failure,
        clearNextAttempt: true,
      ));
      return ToolkitSyncOutcome.rejected;
    }
    // Everything else may pass: wait, with a growing delay, then ask the user.
    final attempts = entry.attempts + 1;
    final wait = _backoff(attempts, error.retryAfter);
    await _store(entry.copyWith(
      state: entry.deleteRequested
          ? ToolkitDocumentSyncState.deletePending
          : ToolkitDocumentSyncState.syncFailedRetryable,
      attempts: attempts,
      lastFailure: error.failure,
      nextAttemptAt: attempts >= maxAutoAttempts ? null : _clock().add(wait),
      clearNextAttempt: attempts >= maxAutoAttempts,
    ));
    return ToolkitSyncOutcome.retryScheduled;
  }

  /// The server answered "deleted" to an upload step. That is only believed
  /// when the status endpoint agrees: a sweep that removes an idle upload can
  /// answer "deleted" for an instant, and then the row is simply gone.
  Future<ToolkitSyncOutcome> _afterDeletedAnswer(ToolkitSyncEntry entry) async {
    try {
      final statuses = await _transport.statuses(<String>[entry.documentId]);
      final state = statuses.byId[entry.documentId];
      if (state == ToolkitRemoteState.deleted) {
        await _store(entry.copyWith(
          state: ToolkitDocumentSyncState.remoteDeleted,
          clearNextAttempt: true,
        ));
        return ToolkitSyncOutcome.remoteDeleted;
      }
    } on ToolkitDocumentException {
      // Cannot tell: treat as a failure that may pass, never as a deletion.
    }
    final attempts = entry.attempts + 1;
    await _store(entry.copyWith(
      state: ToolkitDocumentSyncState.syncFailedRetryable,
      attempts: attempts,
      lastFailure: ToolkitFailure.documentDeleted,
      nextAttemptAt: attempts >= maxAutoAttempts
          ? null
          : _clock().add(_backoff(attempts, null)),
      clearNextAttempt: attempts >= maxAutoAttempts,
    ));
    return ToolkitSyncOutcome.retryScheduled;
  }

  Duration _backoff(int attempts, Duration? serverAsked) {
    final exponent = attempts - 1 > 20 ? 20 : attempts - 1;
    var wait = baseBackoff * (1 << exponent);
    if (wait > maxBackoff) wait = maxBackoff;
    wait +=
        Duration(milliseconds: (wait.inMilliseconds * 0.2 * _jitter()).round());
    if (serverAsked != null && serverAsked > wait) wait = serverAsked;
    return wait;
  }

  Future<void> _restoreWaiting(String documentId) async {
    final entry = _entries[documentId];
    if (entry == null) return;
    if (entry.state == ToolkitDocumentSyncState.syncInProgress) {
      await _store(entry.copyWith(
        state: ToolkitDocumentSyncState.savedLocallyPendingSync,
      ));
    }
  }

  // ---------------------------------------------------------------- storage

  /// Records [entry] in memory and durably. If the journal cannot be written the
  /// previous entry is restored and the error is rethrown, so memory never claims
  /// work the journal would lose at the next restart.
  Future<ToolkitSyncEntry> _store(ToolkitSyncEntry entry) async {
    final previous = _entries[entry.documentId];
    _entries[entry.documentId] = entry;
    try {
      await _serial(() => _journal.save(entry));
    } catch (_) {
      if (previous == null) {
        _entries.remove(entry.documentId);
      } else {
        _entries[entry.documentId] = previous;
      }
      rethrow;
    }
    _emit(ToolkitSyncUpdate(entry.documentId, entry.state, entry.lastFailure));
    return entry;
  }

  Future<void> _forget(String documentId) async {
    _entries.remove(documentId);
    await _serial(() => _journal.remove(documentId));
  }

  Future<void> _serial(Future<void> Function() action) {
    final run = _journalTail.then((_) => action());
    _journalTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  void _emit(ToolkitSyncUpdate update) {
    if (!_disposed && !_updates.isClosed) _updates.add(update);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _updates.close();
  }
}
