import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_selection.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_store.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_source_sheet.dart';

/// What one selection added to a private-media form.
class PrivateMediaPickOutcome {
  const PrivateMediaPickOutcome({
    required this.added,
    required this.duplicates,
    required this.rejections,
    required this.trimmedByLimit,
  });

  /// Files that entered the form.
  final int added;

  /// Files skipped because the form already had them.
  final int duplicates;

  /// Distinct reasons files were refused, one message each.
  final List<OfferMediaRejection> rejections;

  /// Valid files dropped because the record reached its item limit.
  final bool trimmedByLimit;
}

/// The private-media part of an Add/Edit form (Supabase mode): the same
/// behaviour the accepted Offer form has, for any record kind — used by the
/// Owner form ([MediaParent.owner]).
///
/// Identity-based, never URL-based. The form shows three kinds of item, in
/// this order: media already on the server, media in the upload queue, and
/// files picked in this session. Each is addressed by its `mediaObjectId`.
/// Removing a server item or cancelling a queued one takes effect on Save,
/// where the outcome is reported as it actually went; a picked file is simply
/// dropped.
///
/// Picking is the Offer's: the compact Camera / Gallery / Documents sheet, the
/// phone's own camera for a photo or a video, one combined Photo Picker
/// selection for Gallery, no app-made permission dialog, and every file
/// screened against the same rules (count, size, real type, video length,
/// HEIC to JPEG) before it enters the form.
class PrivateMediaForm {
  PrivateMediaForm({
    required PrivateMediaStore store,
    required VoidCallback onChanged,
    OfferMediaPicker? picker,
    Future<OfferMediaSource?> Function(BuildContext context, int remaining)?
        chooseSource,
  })  : _store = store,
        _onChanged = onChanged,
        _picker = picker ?? OfferMediaPicker(),
        _chooseSource = chooseSource;

  final PrivateMediaStore _store;
  final VoidCallback _onChanged;
  final OfferMediaPicker _picker;
  final Future<OfferMediaSource?> Function(BuildContext context, int remaining)?
      _chooseSource;

  MediaParent get parent => _store.parent;

  String? _recordId;
  List<OfferMediaRef> _existing = const <OfferMediaRef>[];
  int _refreshGeneration = 0;
  final Set<String> _removedExistingIds = <String>{};
  final List<OfferMediaDraft> _drafts = <OfferMediaDraft>[];
  final Set<String> _cancelledUploadIds = <String>{};
  bool _expanded = false;
  StreamSubscription<OfferMediaUploadCompleted>? _completions;
  bool _started = false;
  bool _disposed = false;

  /// The record this form's media belongs to, once it has an id: the record
  /// being edited, or a new record's id once Save gave it one.
  String? get recordId => _recordId;
  set recordId(String? value) => _recordId = value;

  /// This form while its record has no id yet (see [MediaPickOrigin]).
  final String _pickSession = const Uuid().v4();

  /// Which form a picker opened here belongs to: this account, this kind of
  /// record, and this record — or this form, until the record has an id.
  MediaPickOrigin? get _pickOrigin => MediaPickOrigin.of(
        accountId: _store.currentOwnerId,
        parent: parent,
        recordId: _recordId,
        formSessionId: _pickSession,
      );

  /// Starts following the upload queue and, for [editRecordId], shows the
  /// record's media: first what this device holds, then the server's list.
  void start({String? editRecordId}) {
    if (_started || _disposed) return;
    _started = true;
    _recordId = editRecordId ?? _recordId;
    _store.uploadChanges.addListener(_notify);
    _completions = _store.uploadCompletions.listen(
      _onUploadCompleted,
      onError: (Object _) {},
    );
    unawaited(_store.loadUploads().then((_) => _notify()));
    if (editRecordId != null) {
      if (_existing.isEmpty) _existing = _store.cachedMedia(editRecordId);
      unawaited(refresh());
    }
    unawaited(_recoverLostSelection());
  }

  void _notify() {
    if (!_disposed) _onChanged();
  }

  /// Picks Android handed back after it stopped the app while a picker or the
  /// camera was open on this same form — this account, this kind of record,
  /// this record: screened and added like any other selection. Another form's
  /// pick is never adopted here.
  Future<void> _recoverLostSelection() async {
    try {
      final recovered = await _picker.recoverLostSelection(origin: _pickOrigin);
      if (recovered.isEmpty || _disposed) return;
      await addPicked(recovered);
    } catch (_) {
      // Nothing to recover is the normal case; a failure changes nothing.
    }
  }

  void _onUploadCompleted(OfferMediaUploadCompleted event) {
    if (_disposed || event.parent != parent || event.offerId != _recordId) {
      return;
    }
    // The item left the queue: show it as the server item it now is — from
    // the copy this device just adopted — until the refresh confirms it.
    if (!_existing.any((ref) => ref.mediaObjectId == event.mediaObjectId)) {
      final cacheKey = offerMediaCacheKey(
        ownerId: event.ownerId,
        mediaObjectId: event.mediaObjectId,
      );
      final offline = OfflineMediaService.instance;
      _existing = [
        ..._existing,
        OfferMediaRef(
          mediaObjectId: event.mediaObjectId,
          cacheKey: cacheKey,
          localFilePath: event.isVideo || cacheKey == null
              ? null
              : offline.getLocalFilePathForMediaId(cacheKey),
          isVideo: event.isVideo,
          posterPath: event.isVideo && cacheKey != null
              ? offline.getLocalFilePathForMediaId(
                  offerMediaPosterKey(cacheKey),
                )
              : null,
          durationMs: event.durationMs,
        ),
      ];
      _notify();
    }
    unawaited(refresh());
  }

  /// Replaces the server items with the authoritative list. Only the most
  /// recent refresh is applied, so an answer that predates an upload never
  /// hides it.
  Future<void> refresh() async {
    final recordId = _recordId;
    final ownerId = _store.currentOwnerId;
    if (recordId == null || ownerId == null || ownerId.isEmpty) return;
    final generation = ++_refreshGeneration;
    try {
      final resolution = await _store.resolveMedia(
        recordId: recordId,
        ownerId: ownerId,
      );
      if (_disposed || resolution == null || generation != _refreshGeneration) {
        return;
      }
      _existing = resolution.items;
      _notify();
    } catch (_) {
      // Keep what this device already gave the form.
    }
  }

  List<OfferMediaRef> get _pendingUploads {
    final recordId = _recordId;
    if (recordId == null) return const <OfferMediaRef>[];
    return _store.pendingMedia(recordId);
  }

  OfferMediaRef _draftRef(OfferMediaDraft draft) => OfferMediaRef(
        mediaObjectId: draft.mediaObjectId,
        cacheKey: null,
        localFilePath: draft.kind == OfferMediaKind.image ? draft.path : null,
        isVideo: draft.kind == OfferMediaKind.video,
        posterPath: draft.posterPath,
        durationMs: draft.durationMs,
        displayName: draft.displayName,
        byteLength: draft.byteLength,
      );

  /// The record's media as the form shows it.
  List<OfferMediaRef> get items {
    final shown = <String>{};
    return [
      for (final ref in _existing)
        if (!_removedExistingIds.contains(ref.mediaObjectId) &&
            shown.add(ref.mediaObjectId))
          ref,
      for (final ref in _pendingUploads)
        if (!_cancelledUploadIds.contains(ref.mediaObjectId) &&
            shown.add(ref.mediaObjectId))
          ref,
      for (final draft in _drafts)
        if (shown.add(draft.mediaObjectId)) _draftRef(draft),
    ];
  }

  /// Everything that would be on the record if it were saved now, except
  /// items refused for good: what the item limit counts, exactly as the
  /// Media Worker counts it server-side.
  int get currentCount => items
      .where((ref) => ref.uploadPhase != OfferMediaUploadPhase.permanentFailure)
      .length;

  /// How many more photos or videos the record can still take.
  int get remainingSlots => OfferMediaPolicy.remainingSlots(currentCount);

  /// Whether the count is over the limit (media added elsewhere since the
  /// form opened); Save refuses then.
  bool get isOverLimit => currentCount > parent.maxItems;

  /// Whether all items are shown rather than the first few.
  bool get expanded => _expanded;

  /// How many items the media grid shows: the first three, or all of them
  /// once "+N more" was tapped.
  int get displayCount {
    const collapsed = 3;
    if (!_expanded) return collapsed;
    final count = items.length;
    return count > collapsed ? count : collapsed;
  }

  void showAll() {
    _expanded = true;
    _notify();
  }

  /// Removes the item at [index] of [items]: a picked file at once; a server
  /// item or a queued upload when the record is saved.
  void removeAt(int index) {
    final current = items;
    if (index < 0 || index >= current.length) return;
    final ref = current[index];
    final draftIndex =
        _drafts.indexWhere((draft) => draft.mediaObjectId == ref.mediaObjectId);
    if (draftIndex >= 0) {
      _drafts.removeAt(draftIndex);
    } else if (ref.uploadPhase != null) {
      _cancelledUploadIds.add(ref.mediaObjectId);
    } else {
      _removedExistingIds.add(ref.mediaObjectId);
    }
    _notify();
  }

  /// Like removing each item: picked files go now, the rest on Save.
  void clearAll() {
    for (final ref in items) {
      if (ref.uploadPhase != null) {
        _cancelledUploadIds.add(ref.mediaObjectId);
      } else if (!_drafts.any((d) => d.mediaObjectId == ref.mediaObjectId)) {
        _removedExistingIds.add(ref.mediaObjectId);
      }
    }
    _drafts.clear();
    _notify();
  }

  /// Retries the queued upload at [index] of [items].
  void retryAt(int index) {
    final current = items;
    if (index < 0 || index >= current.length) return;
    final ref = current[index];
    if (ref.uploadPhase != OfferMediaUploadPhase.retryableFailure &&
        ref.uploadPhase != OfferMediaUploadPhase.retrying) {
      return;
    }
    unawaited(_store.retryUpload(ref.mediaObjectId));
  }

  /// The "+": the attachment sheet (Camera / Gallery / Documents), then the
  /// chosen picker, then the same screening as ever. Dismissing the sheet or
  /// cancelling a picker changes nothing.
  Future<void> select(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // The record is already full: say so instead of opening a picker whose
    // every result would be discarded.
    final remaining = remainingSlots;
    if (remaining == 0) {
      _toast(loc.translate(parent.limitReachedKey), Colors.red);
      return;
    }

    final List<File> picked;
    try {
      final chooser = _chooseSource;
      final source = chooser != null
          ? await chooser(context, remaining)
          : await showOfferMediaSourceSheet(
              context,
              remaining: remaining,
              documentsUnavailableKey: parent.documentsUnavailableKey,
            );
      if (source == null || !context.mounted) return;
      final origin = _pickOrigin;
      switch (source) {
        case OfferMediaSource.gallery:
          picked = await _picker.pickFromGallery(
            limit: remaining,
            origin: origin,
          );
        case OfferMediaSource.cameraPhoto:
          final photo = await _picker.capturePhoto(origin: origin);
          picked = [if (photo != null) photo];
        case OfferMediaSource.cameraVideo:
          final video = await _picker.recordVideo(
            maxDuration: OfferMediaPolicy.maxVideoDuration,
            origin: origin,
          );
          picked = [if (video != null) video];
      }
    } on OfferMediaPickerException catch (error) {
      if (context.mounted) _explainCameraRefusal(context, error.failure);
      return;
    } catch (_) {
      if (context.mounted) {
        _toast(loc.translate('offerMediaPickerFailed'), Colors.red);
      }
      return;
    }
    if (picked.isEmpty) return; // Cancelled in the picker.

    final outcome = await addPicked(picked);
    if (!context.mounted) return;
    for (final rejection in outcome.rejections) {
      _toast(loc.translate(parent.messageKeyFor(rejection)), Colors.red);
    }
    if (outcome.trimmedByLimit) {
      _toast(loc.translate(parent.limitTrimmedKey), Colors.red);
    }
    if (outcome.duplicates > 0) {
      _toast(loc.translate('offerMediaAlreadyAdded'), Colors.orange);
    }
    if (outcome.added > 0) {
      Fluttertoast.showToast(
        msg: loc
            .translate('offerMediaAdded')
            .replaceAll('{count}', '${outcome.added}'),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  /// The camera permission was refused: say so in words, and when only the
  /// system settings can change it, offer to open them.
  void _explainCameraRefusal(
    BuildContext context,
    OfferMediaPickerFailure failure,
  ) {
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (failure == OfferMediaPickerFailure.cameraPermanentlyDenied &&
        messenger != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(loc.translate('cameraPermissionPermanentlyDenied')),
        action: SnackBarAction(
          label: loc.translate('openSettings'),
          onPressed: () => unawaited(openAppSettings()),
        ),
      ));
      return;
    }
    _toast(loc.translate('cameraPermissionDenied'), Colors.red);
  }

  /// Adds freshly picked files: files already in the form (same name and
  /// size as an item picked earlier and not yet uploaded) are skipped, and
  /// the rest are screened against the media rules before anything enters
  /// the form. Each accepted file keeps the `mediaObjectId` it was given here
  /// for good; the upload queue copies it into the app's own storage on Save.
  Future<PrivateMediaPickOutcome> addPicked(List<File> picked) async {
    final seen = <String>{
      for (final draft in _drafts)
        if (_pickKey(draft.displayName, draft.byteLength) case final key?) key,
      for (final ref in _pendingUploads)
        if (_pickKey(ref.displayName, ref.byteLength) case final key?) key,
    };
    final fresh = <File>[];
    var duplicates = 0;
    for (final file in picked) {
      int? length;
      try {
        length = await file.length();
      } catch (_) {
        length = null; // Unreadable: screening refuses it.
      }
      final key = _pickKey(_fileName(file.path), length);
      if (key != null && !seen.add(key)) {
        duplicates += 1;
        continue;
      }
      fresh.add(file);
    }

    final screened = fresh.isEmpty
        ? const OfferMediaSelectionResult(
            accepted: [], rejections: [], trimmedByLimit: false)
        : await screenOfferMediaSelection(
            candidates: fresh,
            itemsAlreadyOnOffer: currentCount,
          );
    if (!_disposed) {
      _drafts.addAll(screened.accepted);
      if (screened.accepted.isNotEmpty) _notify();
    }
    return PrivateMediaPickOutcome(
      added: _disposed ? 0 : screened.accepted.length,
      duplicates: duplicates,
      rejections: screened.rejections,
      trimmedByLimit: screened.trimmedByLimit,
    );
  }

  static String _fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  static String? _pickKey(String? name, int? length) =>
      name == null || name.isEmpty || length == null ? null : '$name|$length';

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  /// New files to hand to the upload queue on Save.
  List<OfferMediaDraft> get drafts => List<OfferMediaDraft>.of(_drafts);

  /// Server items the user removed in this session.
  List<String> get removedIds => List<String>.of(_removedExistingIds);

  /// Queued items the user removed in this session.
  List<String> get cancelledIds => List<String>.of(_cancelledUploadIds);

  /// What went through on Save leaves the form's own lists (queued items now
  /// show from the queue); what did not stays for the next Save.
  void applySaveResult({
    required List<String> removed,
    required List<String> cancelled,
    required List<String> failedRemovalIds,
    required List<String> failedToQueueIds,
  }) {
    final notQueued = failedToQueueIds.toSet();
    _drafts.removeWhere((draft) => !notQueued.contains(draft.mediaObjectId));
    final notRemoved = failedRemovalIds.toSet();
    final removedNow = {
      for (final id in removed)
        if (!notRemoved.contains(id)) id,
    };
    _existing = [
      for (final ref in _existing)
        if (!removedNow.contains(ref.mediaObjectId)) ref,
    ];
    _removedExistingIds.removeAll(removedNow);
    _cancelledUploadIds.removeAll(cancelled);
    _notify();
  }

  void _toast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: color,
      textColor: Colors.white,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      _store.uploadChanges.removeListener(_notify);
      unawaited(_completions?.cancel());
    }
  }
}
