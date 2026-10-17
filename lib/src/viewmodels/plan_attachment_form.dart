// The land / plot plan part of an Add/Edit Offer or Owner form.
//
// One optional plan per record, separate from the photo and video gallery (its
// own controller, its own Worker routes, never counted in the gallery's limit).
// The form shows one of: no plan; the plan on the server; a file picked in this
// session (waiting to be saved, or replacing the server's plan); the plan marked
// for removal; an upload in progress; or an upload that failed and can be
// retried.
//
// Nothing here changes the server until the record itself has been saved
// ([commit]): picking, replacing and removing are local choices, so cancelling
// the form never mutates hosted state. A failed replacement leaves the plan the
// record already had, and a failed upload never undoes the saved record: the
// form keeps the chosen file, says so, and retries under the same upload id.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_screening.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_workflow.dart';

/// What the form's plan section shows.
enum PlanDisplay {
  /// No plan, and nothing chosen.
  none,

  /// The plan the record has on the server.
  existing,

  /// The server's plan, which will be removed when the record is saved.
  removalPending,

  /// A file chosen for a record that has no plan yet.
  draft,

  /// A file chosen to replace the server's plan; the old one stays until the
  /// new one is confirmed.
  replacing,

  /// The change is being sent.
  working,

  /// The change was not completed; the record itself was saved.
  failed,
}

/// The plan section's state, as one value.
@immutable
class PlanAttachmentView {
  const PlanAttachmentView({
    required this.display,
    this.kind,
    this.displayName,
    this.byteLength,
    this.localPath,
    this.signedUrl,
    this.failure,
    this.hasServerPlan = false,
    this.isRemoval = false,
  });

  final PlanDisplay display;
  final PlanAttachmentKind? kind;
  final String? displayName;
  final int? byteLength;

  /// A chosen image on this phone (drawn from the file).
  final String? localPath;

  /// A still-fresh read link of the server's plan (memory only).
  final String? signedUrl;
  final PlanAttachmentFailure? failure;

  /// Whether the record has a plan on the server.
  final bool hasServerPlan;

  /// Whether the change being sent (or that failed) is the removal of the
  /// server's plan, rather than the upload of a chosen file.
  final bool isRemoval;

  bool get hasContent => display != PlanDisplay.none;
}

/// How [PlanAttachmentFormController.commit] ended.
enum PlanCommitStatus { nothing, done, failed }

@immutable
class PlanCommitOutcome {
  const PlanCommitOutcome.nothing()
      : status = PlanCommitStatus.nothing,
        failure = null;
  const PlanCommitOutcome.done()
      : status = PlanCommitStatus.done,
        failure = null;
  const PlanCommitOutcome.failed(PlanAttachmentFailure this.failure)
      : status = PlanCommitStatus.failed;

  final PlanCommitStatus status;
  final PlanAttachmentFailure? failure;

  /// Whether there is nothing left to retry.
  bool get isComplete => status != PlanCommitStatus.failed;
}

class PlanAttachmentFormController {
  PlanAttachmentFormController({
    required this.parent,
    required PlanAttachmentTransport transport,
    required PlanAttachmentWorkflow workflow,
    required PlanFileScreener screen,
    required VoidCallback onChanged,
    DateTime Function()? now,
  })  : _transport = transport,
        _workflow = workflow,
        _screen = screen,
        _onChanged = onChanged,
        _now = now ?? DateTime.now;

  final PlanParent parent;
  final PlanAttachmentTransport _transport;
  final PlanAttachmentWorkflow _workflow;
  final PlanFileScreener _screen;
  final VoidCallback _onChanged;
  final DateTime Function() _now;

  String? _recordId;
  PlanAttachmentRef? _existing;

  /// Whether [_existing] is what the server really holds. A new record cannot
  /// have a plan; an edited one is unknown until the first read answers.
  bool _existingResolved = false;
  PlanAttachmentDraft? _draft;

  /// The draft's upload id has been sent to the server at least once, so a
  /// withdrawal should tell it.
  bool _draftTouched = false;
  bool _removeRequested = false;
  bool _working = false;
  PlanAttachmentFailure? _failure;
  int _refreshGeneration = 0;
  bool _disposed = false;

  /// The record this plan belongs to, once it has an id.
  String? get recordId => _recordId;

  /// Starts a form. For [editRecordId] the record's current plan is read, so it
  /// appears as soon as the server answers; a new record has none.
  void start({String? editRecordId}) {
    _recordId = editRecordId ?? _recordId;
    if (editRecordId == null) {
      _existing = null;
      _existingResolved = true;
      return;
    }
    unawaited(refresh());
  }

  void _notify() {
    if (!_disposed) _onChanged();
  }

  /// Whether the record has, or is about to have, a plan: what Save counts as
  /// the record's content.
  bool get hasPlan =>
      _draft != null || (_existing != null && !_removeRequested);

  /// Whether Save has something to send for the plan.
  bool get hasPendingChange =>
      _draft != null || (_removeRequested && _existing != null);

  /// True while a change is being sent.
  bool get isWorking => _working;

  PlanAttachmentFailure? get failure => _failure;

  PlanAttachmentView get view {
    final draft = _draft;
    final existing = _existing;
    final hasServerPlan = existing != null;
    if (_working) {
      return PlanAttachmentView(
        display: PlanDisplay.working,
        kind: draft?.kind ?? existing?.kind,
        displayName: draft?.displayName ?? existing?.displayName,
        byteLength: draft?.byteLength ?? existing?.byteLength,
        localPath: draft != null && draft.kind == PlanAttachmentKind.image
            ? draft.path
            : null,
        hasServerPlan: hasServerPlan,
        isRemoval: draft == null,
      );
    }
    if (_failure != null && hasPendingChange) {
      return PlanAttachmentView(
        display: PlanDisplay.failed,
        kind: draft?.kind ?? existing?.kind,
        displayName: draft?.displayName ?? existing?.displayName,
        byteLength: draft?.byteLength ?? existing?.byteLength,
        localPath: draft != null && draft.kind == PlanAttachmentKind.image
            ? draft.path
            : null,
        failure: _failure,
        hasServerPlan: hasServerPlan,
        isRemoval: draft == null,
      );
    }
    if (draft != null) {
      return PlanAttachmentView(
        display: hasServerPlan ? PlanDisplay.replacing : PlanDisplay.draft,
        kind: draft.kind,
        displayName: draft.displayName,
        byteLength: draft.byteLength,
        localPath: draft.kind == PlanAttachmentKind.image ? draft.path : null,
        hasServerPlan: hasServerPlan,
      );
    }
    if (existing != null) {
      return PlanAttachmentView(
        display: _removeRequested
            ? PlanDisplay.removalPending
            : PlanDisplay.existing,
        kind: existing.kind,
        displayName: existing.displayName,
        byteLength: existing.byteLength,
        signedUrl: existing.hasFreshUrl(_now()) ? existing.signedUrl : null,
        hasServerPlan: true,
      );
    }
    return const PlanAttachmentView(display: PlanDisplay.none);
  }

  /// Reads the record's plan from the server. Only the most recent read is
  /// applied; a failure keeps what the form already shows.
  Future<void> refresh() async {
    final recordId = _recordId;
    if (recordId == null || _disposed) return;
    final generation = ++_refreshGeneration;
    try {
      final current =
          await _transport.fetchCurrent(parent: parent, parentId: recordId);
      if (_disposed || generation != _refreshGeneration || _working) return;
      final previousId = _existing?.mediaObjectId;
      _existing = current;
      _existingResolved = true;
      // A removal was asked for one plan; if another replaced it meanwhile the
      // request no longer means anything.
      if (_removeRequested && current?.mediaObjectId != previousId) {
        _removeRequested = false;
      }
      _notify();
    } catch (_) {
      // Keep what the form already shows.
    }
  }

  /// Screens a picked [file]. Returns why it was refused, or null when it is now
  /// the form's chosen plan. A refused file changes nothing.
  Future<PlanAttachmentRejection?> addPicked(
    File file, {
    String? displayName,
  }) async {
    if (_disposed || _working) return null;
    final screening = await _screen(file, displayName: displayName);
    final draft = screening.draft;
    if (draft == null) return screening.rejection;
    if (_disposed) {
      _releaseDraft(draft, withdrawFromServer: false);
      return null;
    }
    final previous = _draft;
    if (previous != null) _releaseDraft(previous, withdrawFromServer: true);
    _draft = draft;
    _draftTouched = false;
    _removeRequested = false;
    _failure = null;
    _notify();
    return null;
  }

  /// The user's Remove: a chosen file is dropped at once (the record keeps the
  /// plan it had); the server's plan is marked and removed when the record is
  /// saved.
  void removeSelection() {
    if (_disposed || _working) return;
    final draft = _draft;
    if (draft != null) {
      _draft = null;
      _failure = null;
      _releaseDraft(draft, withdrawFromServer: true);
      _draftTouched = false;
    } else if (_existing != null) {
      _removeRequested = true;
      _failure = null;
    } else {
      return;
    }
    _notify();
  }

  /// Takes back a removal that was marked but not yet saved.
  void keepExisting() {
    if (_disposed || _working || !_removeRequested) return;
    _removeRequested = false;
    _failure = null;
    _notify();
  }

  /// Sends what the form chose, after the record itself has been saved.
  ///
  /// Never throws. A failure is reported in the outcome and kept in [view] with
  /// the chosen file, so the record's own save is never undone and the same
  /// upload can be retried.
  Future<PlanCommitOutcome> commit({required String recordId}) async {
    _recordId = recordId;
    if (_disposed) return const PlanCommitOutcome.nothing();
    final draft = _draft;
    final removing = draft == null && _removeRequested && _existing != null;
    if (draft == null && !removing) return const PlanCommitOutcome.nothing();
    if (_working) {
      return const PlanCommitOutcome.failed(PlanAttachmentFailure.unknown);
    }

    _working = true;
    _failure = null;
    _notify();
    try {
      final expected = await _expectedMediaId(recordId);
      if (draft != null) {
        _draftTouched = true;
        final ref = await _workflow.upload(
          parent: parent,
          parentId: recordId,
          draft: draft,
          expectedMediaId: expected,
        );
        _existing = ref;
        _existingResolved = true;
        _draft = null;
        _draftTouched = false;
        _removeRequested = false;
        final owned = draft.ownedTempPath;
        if (owned != null) unawaited(deleteQuietly(owned));
      } else {
        await _workflow.remove(
          parent: parent,
          parentId: recordId,
          expectedMediaId: expected,
        );
        _existing = null;
        _existingResolved = true;
        _removeRequested = false;
      }
      _working = false;
      _notify();
      return const PlanCommitOutcome.done();
    } on PlanAttachmentException catch (error) {
      return _fail(error.failure);
    } catch (_) {
      return _fail(PlanAttachmentFailure.unknown);
    }
  }

  /// Sends the same change again (same upload id), once the record is saved.
  Future<PlanCommitOutcome> retry() async {
    final recordId = _recordId;
    if (recordId == null) return const PlanCommitOutcome.nothing();
    return commit(recordId: recordId);
  }

  Future<String?> _expectedMediaId(String recordId) async {
    if (_existingResolved) return _existing?.mediaObjectId;
    // Never guess what the plan is: an edit that could not read it yet asks
    // now, and fails (and can be retried) when the server cannot be reached.
    final current =
        await _transport.fetchCurrent(parent: parent, parentId: recordId);
    _existing = current;
    _existingResolved = true;
    return current?.mediaObjectId;
  }

  PlanCommitOutcome _fail(PlanAttachmentFailure failure) {
    _working = false;
    _failure = failure;
    if (failure == PlanAttachmentFailure.staleReplacement) {
      // The plan changed elsewhere: show what it is now. The next attempt
      // names it as the plan being replaced.
      _existingResolved = false;
      unawaited(refresh());
    }
    _notify();
    return PlanCommitOutcome.failed(failure);
  }

  /// Lets go of [draft]: the file the app made for it is deleted, and an upload
  /// the server already knows is withdrawn so it stops holding a place.
  void _releaseDraft(PlanAttachmentDraft draft,
      {required bool withdrawFromServer, bool deleteFiles = true}) {
    final owned = draft.ownedTempPath;
    if (deleteFiles && owned != null) unawaited(deleteQuietly(owned));
    final recordId = _recordId;
    if (withdrawFromServer && _draftTouched && recordId != null) {
      unawaited(_workflow.cancelCandidate(
        parent: parent,
        parentId: recordId,
        expectedMediaId: _existing?.mediaObjectId,
        mediaObjectId: draft.mediaObjectId,
      ));
    }
  }

  /// Ends the form. A chosen file that was never saved is dropped without
  /// touching the server's plan. An upload still being sent is left to finish:
  /// withdrawing it now would race the confirm that is about to attach it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final draft = _draft;
    if (draft != null) {
      _draft = null;
      _releaseDraft(draft,
          withdrawFromServer: !_working, deleteFiles: !_working);
    }
  }
}
