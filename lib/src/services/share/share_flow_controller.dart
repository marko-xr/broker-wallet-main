import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/share/share_clipboard.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_media_batches.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';

/// The collaborators a share needs: where its files are prepared, how a private
/// photo or video is fetched, the native share sheet, the clipboard a batch's
/// message is copied to, and how the platform takes a chosen set of media.
class ShareEngine {
  const ShareEngine({
    required this.preparer,
    required this.fetcher,
    required this.launcher,
    this.clipboard,
    this.delivery = ShareDelivery.familyBatches,
  });

  final SharePreparer preparer;
  final ShareMediaFetcher fetcher;
  final ShareLauncher launcher;

  /// Where the message is copied when several photos or videos of one family are
  /// shared. Without one nothing is copied and nothing is promised.
  final ShareClipboard? clipboard;

  /// How the platform takes the chosen media: in homogeneous batches (Android),
  /// or the whole choice in one system share.
  final ShareDelivery delivery;
}

enum ShareFlowStatus {
  /// Waiting for the person to choose, or to continue a two-step share.
  idle,

  /// Fetching and naming the chosen files.
  preparing,

  /// The native share sheet is open.
  sharing,
}

/// How a call to [ShareFlowController.share] ended.
enum ShareFlowResult {
  /// The share sheet was used (or the platform cannot tell): the share is done.
  shared,

  /// The first step of a two-step share was handed to the share sheet. The other
  /// step is ready and the next call sends it; see
  /// [ShareFlowController.pendingFamily].
  stepShared,

  /// The person closed the share sheet without choosing an app. Not an error.
  dismissed,

  /// The files could not be prepared or the sheet could not be opened; see
  /// [ShareFlowController.failure].
  failed,

  /// The share was called off while it was being prepared.
  cancelled,

  /// A share was already under way, or a share sheet was already open.
  busy,

  /// Nothing was chosen, so nothing was started.
  nothingSelected,
}

/// What a person has chosen to share from one record, and the share itself.
///
/// It holds the choices (parts, and which photos and videos), refuses an empty
/// share, runs one share at a time, prepares the chosen files with their
/// professional names, opens the native share sheet and reports how it ended.
/// A share that cannot be prepared leaves the person where they were, with the
/// reason and the choices intact, so they can retry; nothing is ever sent with
/// some of the chosen files missing.
///
/// The photos and videos chosen in the media picker are the choice, once. What
/// the sheet is handed is decided in one place, [SharePayload]:
///
///  * no file is the message alone; one file goes with its message;
///  * several photos, or several videos, go as one homogeneous batch of exactly
///    those files, with no message in the request, and the message is copied to
///    the clipboard ONCE for the person to paste (a receiving app may repeat a
///    message that travels with several files, or drop it);
///  * photos and videos together are one choice shared in two steps, photos then
///    videos, each a homogeneous batch of the files that were chosen. Nothing
///    asks which family goes; the first step is launched by Share, and when the
///    person is back the second is launched by the next Share (Continue), never
///    by a timer and never while the first receiving app may still be open.
///
/// The choice is never changed by sharing: which families are done is tracked
/// separately. Changing the media choice starts over. A retry after a failed
/// second step sends only that step.
///
/// The clipboard is written at one moment only: once the first step's files are
/// ready and nothing is left that could call the share off, immediately before
/// the native sheet is opened, and once for the whole share. A share that cannot
/// be prepared, is called off, or finds a sheet already open never touches it.
/// After that moment the copy stays and the person's earlier clipboard is not
/// restored.
class ShareFlowController extends ChangeNotifier {
  ShareFlowController({
    required this.source,
    required this.labels,
    required this.engine,
    this.refreshLink,
    this.initialMediaKey,
  })  : _selected = <ShareSection>{
          ...source.defaultSelection.where((s) => s != ShareSection.media),
        },
        _mediaKeys = initialMediaKey == null
            ? <String>{...source.defaultMediaKeys}
            : <String>{
                if (source.media.any((item) => item.key == initialMediaKey))
                  initialMediaKey,
              };

  /// The key of the document in a [ShareFailure].
  static const String documentKey = 'document';

  final ShareSource source;
  final ShareLabels labels;
  final ShareEngine engine;

  /// Fetches a fresh link for a private video or photo whose link expired.
  final LinkRefresher? refreshLink;

  /// A viewer starts from its currently displayed item; a details screen uses
  /// the source's existing photo-first default.
  final String? initialMediaKey;

  final Set<ShareSection> _selected;
  final Set<String> _mediaKeys;
  final Set<String> _unavailableMedia = <String>{};
  bool _documentUnavailable = false;

  /// The families of a two-step share that were already handed to the share
  /// sheet. Progress only: the choice itself is [_mediaKeys].
  final Set<MediaFamily> _completed = <MediaFamily>{};

  /// Whether the message was already copied for the share in progress.
  bool _clipboardWritten = false;

  ShareFlowStatus _status = ShareFlowStatus.idle;
  ShareFailure? _failure;
  ShareCancelToken? _token;
  bool _disposed = false;
  bool _clipboardFailed = false;

  ShareFlowStatus get status => _status;

  /// A share is being prepared or its sheet is open: nothing may be started or
  /// changed. The one source of truth for "something is under way".
  bool get isBusy => _status != ShareFlowStatus.idle;

  /// Files are really being fetched and named. This is the only time anything
  /// is shown spinning: once the sheet is open there is nothing left to wait for.
  bool get isPreparing => _status == ShareFlowStatus.preparing;

  /// Why the last share could not go ahead, until the next choice or attempt.
  ShareFailure? get failure => _failure;

  /// The parts on offer, in display order. Only parts with something behind them.
  List<ShareSection> get sections => source.available;

  bool isSelected(ShareSection section) {
    switch (section) {
      case ShareSection.media:
        return _mediaKeys.isNotEmpty;
      case ShareSection.document:
        return !_documentUnavailable && _selected.contains(section);
      default:
        return _selected.contains(section);
    }
  }

  /// The document could not be had, so it is no longer offered as chosen.
  bool isUnavailable(ShareSection section) =>
      section == ShareSection.document && _documentUnavailable;

  bool isMediaSelected(String key) => _mediaKeys.contains(key);

  /// The item could not be had at the last attempt: it is shown as unavailable,
  /// never as chosen.
  bool isMediaUnavailable(String key) => _unavailableMedia.contains(key);

  /// The keys of the photos and videos that will be shared.
  Set<String> get selectedMediaKeys => Set<String>.unmodifiable(_mediaKeys);

  int get selectedMediaCount => _mediaKeys.length;

  int get totalMediaCount => source.media.length;

  /// How many of the chosen photos and videos are photos and videos. A summary
  /// for the dialog; it changes nothing about what is shared.
  int get selectedPhotoCount => mediaBatches.images.length;
  int get selectedVideoCount => mediaBatches.videos.length;

  /// The chosen photos and videos, in the record's own (gallery) order.
  Iterable<ShareMediaItem> get _selectedMedia => source.media.where(
        (item) =>
            _mediaKeys.contains(item.key) &&
            !_unavailableMedia.contains(item.key),
      );

  /// The choice told apart by kind: photos and videos, each in the order chosen.
  MediaBatches get mediaBatches => MediaBatches.of(_selectedMedia);

  /// Whether sharing what is chosen takes two steps: photos and videos are both
  /// chosen, on a platform that hands media over in homogeneous batches.
  bool get twoStepShare =>
      engine.delivery == ShareDelivery.familyBatches && mediaBatches.isMixed;

  /// Whether the first step of a two-step share was handed over and the other is
  /// waiting for the next Share.
  bool get hasPendingStep =>
      _completed.isNotEmpty &&
      twoStepShare &&
      _nextFamily(mediaBatches) != null;

  /// The family the next Share sends, once a step was already handed over; null
  /// before that and when the share is not in two steps.
  MediaFamily? get pendingFamily =>
      hasPendingStep ? _nextFamily(mediaBatches) : null;

  /// The parts that will be shared, media being one part however many files.
  Set<ShareSection> get selection => <ShareSection>{
        ..._selected.where(
          (s) => s != ShareSection.media && isSelected(s),
        ),
        if (_mediaKeys.isNotEmpty) ShareSection.media,
      };

  bool get hasSelection => selection.isNotEmpty;

  /// Whether the Share action may be used: something is chosen and nothing is
  /// under way.
  bool get canShare => hasSelection && !isBusy;

  /// Whether sharing what is chosen now will copy its message to the clipboard,
  /// so the dialog can say so before anything is shared: some family holds
  /// several photos or videos, there is a message, and the clipboard has not
  /// already refused a copy. Never when the platform takes the message with the
  /// files.
  bool get copiesDetails =>
      engine.delivery == ShareDelivery.familyBatches &&
      engine.clipboard != null &&
      !_clipboardFailed &&
      mediaBatches.hasSeveralInAFamily &&
      (source.composeText(selection, labels)?.trim().isNotEmpty ?? false);

  Iterable<String> get _selectableMedia => <String>[
        for (final item in source.media)
          if (!_unavailableMedia.contains(item.key)) item.key,
      ];

  bool _fullySelected(ShareSection section) {
    if (section == ShareSection.media) {
      final keys = _selectableMedia.toList();
      return keys.isNotEmpty && keys.every(_mediaKeys.contains);
    }
    return isSelected(section);
  }

  /// The state of the Select All box: true when every part is chosen in full,
  /// false when nothing is, null when some are.
  bool? get allState {
    final options =
        sections.where((s) => !isUnavailable(s)).toList(growable: false);
    if (options.isEmpty) return false;
    if (options.every(_fullySelected)) return true;
    if (options.every((s) => !isSelected(s))) return false;
    return null;
  }

  void toggleAll() {
    if (isBusy) return;
    if (allState == true) {
      _selected.clear();
      _mediaKeys.clear();
    } else {
      _selected
        ..clear()
        ..addAll(
          sections.where((s) => s != ShareSection.media && !isUnavailable(s)),
        );
      _mediaKeys
        ..clear()
        ..addAll(_selectableMedia);
    }
    _mediaChanged();
  }

  void toggleSection(ShareSection section) {
    if (isBusy || !sections.contains(section) || isUnavailable(section)) {
      return;
    }
    if (section == ShareSection.media) {
      if (_mediaKeys.isNotEmpty) {
        _mediaKeys.clear();
      } else {
        // Ticking Media chooses the photos; a record with only videos has none
        // to start with, so ticking it chooses those.
        final photos = source.defaultMediaKeys
            .where((key) => !_unavailableMedia.contains(key))
            .toSet();
        _mediaKeys.addAll(photos.isNotEmpty ? photos : _selectableMedia);
      }
      _mediaChanged();
      return;
    }
    if (!_selected.remove(section)) _selected.add(section);
    _changed();
  }

  void toggleMedia(String key) {
    if (isBusy || _unavailableMedia.contains(key)) return;
    if (!source.media.any((item) => item.key == key)) return;
    if (!_mediaKeys.remove(key)) _mediaKeys.add(key);
    _mediaChanged();
  }

  void selectAllMedia() {
    if (isBusy) return;
    _mediaKeys
      ..clear()
      ..addAll(_selectableMedia);
    _mediaChanged();
  }

  void clearMedia() {
    if (isBusy) return;
    _mediaKeys.clear();
    _mediaChanged();
  }

  /// Commits one picker session atomically. Cancel never calls this method.
  void replaceMediaSelection(Set<String> keys) {
    if (isBusy) return;
    final available = _selectableMedia.toSet();
    _mediaKeys
      ..clear()
      ..addAll(keys.where(available.contains));
    _mediaChanged();
  }

  /// Calls off a share that is being prepared. Safe at any time.
  void cancel() => _token?.cancel();

  /// Prepares what was chosen and opens the native share sheet.
  ///
  /// Only one share runs at a time: a second call while one is under way
  /// returns [ShareFlowResult.busy] and does nothing, so a double tap cannot
  /// start two downloads, two copies or two sheets.
  ///
  /// When photos and videos are both chosen (on a platform that hands media over
  /// in homogeneous batches) the first call prepares and shares the photos and
  /// returns [ShareFlowResult.stepShared]; the next call prepares and shares only
  /// the videos. A step that could not be handed over is retried alone, and the
  /// steps already handed over are never sent again.
  Future<ShareFlowResult> share({ShareOrigin? origin}) async {
    if (_disposed) return ShareFlowResult.cancelled;
    if (isBusy) return ShareFlowResult.busy;
    if (!hasSelection) return ShareFlowResult.nothingSelected;

    // Derived from the choice, which sharing never changes.
    final batches = mediaBatches;
    final inSteps =
        engine.delivery == ShareDelivery.familyBatches && batches.isMixed;
    MediaFamily? family;
    if (inSteps) {
      family = _nextFamily(batches);
      if (family == null) {
        // Every step was already handed over: this is a new share.
        _finishShare();
        family = batches.steps.first;
      }
    } else {
      _finishShare();
    }
    final media = family == null ? batches.master : batches.itemsOf(family);
    final firstStep = _completed.isEmpty;

    final token = ShareCancelToken();
    _token = token;
    _failure = null;
    _setStatus(ShareFlowStatus.preparing);

    ShareBundle? bundle;
    try {
      final chosen = selection;
      final text = source.composeText(chosen, labels);
      final attachments = _attachments(chosen, media, withDocument: firstStep);
      if (attachments.isNotEmpty) {
        // Only this step's own files, and no listener is told per file: the
        // status already says that files are being prepared, once.
        bundle = await engine.preparer.prepare(attachments, token);
      }
      if (token.isCancelled || _disposed) {
        await bundle?.discard();
        return ShareFlowResult.cancelled;
      }

      // What the sheet is handed is decided from the files that were really
      // prepared, in one place. A batch that turns out to mix photos and videos
      // (a record that misdescribed one of them) is never launched.
      final subject = labels.text(source.subjectKey);
      final payload = SharePayload.plan(
        delivery: engine.delivery,
        files: bundle?.files ?? const <PreparedShareFile>[],
        text: text,
        subject: subject.isEmpty ? null : subject,
      );
      if (!payload.isLaunchable) {
        throw const ShareFailure(ShareFailureKind.generic);
      }

      // A sheet that is already open would refuse this share: say so before
      // anything is copied.
      if (engine.launcher.isOpen) {
        await bundle?.discard();
        return ShareFlowResult.busy;
      }

      // From here the step is committed: the message is copied (once for the
      // whole share, and only when a family holds several files) and the sheet
      // is opened, with no point left at which it can still be called off.
      _setStatus(ShareFlowStatus.sharing);
      final copyText = _detailsToCopy(batches, text);
      if (copyText != null) await _copy(copyText);
      final outcome = await engine.launcher.launch(payload.toRequest(origin));
      if (outcome == null) {
        await bundle?.discard();
        return ShareFlowResult.busy;
      }
      if (outcome == ShareOutcome.dismissed) {
        // Nobody received the files, so they can go at once.
        await bundle?.discard();
        return ShareFlowResult.dismissed;
      }
      if (family != null) {
        _completed.add(family);
        if (_nextFamily(batches) != null) return ShareFlowResult.stepShared;
      }
      _finishShare();
      return ShareFlowResult.shared;
    } on ShareCancelled {
      await bundle?.discard();
      return ShareFlowResult.cancelled;
    } on ShareFailure catch (failure) {
      await bundle?.discard();
      _recordFailure(failure);
      return ShareFlowResult.failed;
    } catch (_) {
      await bundle?.discard();
      _recordFailure(const ShareFailure(ShareFailureKind.generic));
      return ShareFlowResult.failed;
    } finally {
      _token = null;
      // A share that ended before any step was handed over starts afresh next
      // time, including its copy.
      if (_completed.isEmpty) _clipboardWritten = false;
      _setStatus(ShareFlowStatus.idle);
    }
  }

  /// The first family of [batches], in the fixed order, not yet handed over.
  MediaFamily? _nextFamily(MediaBatches batches) {
    for (final family in batches.steps) {
      if (!_completed.contains(family)) return family;
    }
    return null;
  }

  /// The message to copy now, or null: once for the whole share, only on a
  /// platform that hands media over in batches, and only when some family holds
  /// several files (a single file carries its own message).
  String? _detailsToCopy(MediaBatches batches, String? text) {
    if (engine.delivery != ShareDelivery.familyBatches) return null;
    if (engine.clipboard == null || _clipboardWritten) return null;
    if (!batches.hasSeveralInAFamily) return null;
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  /// Puts [text] on the clipboard. A missing, failing or throwing clipboard
  /// never stops the share; one that refused is remembered, so the dialog stops
  /// promising a copy. Either way the share counts as copied: it is not tried
  /// again for the second step.
  Future<void> _copy(String text) async {
    _clipboardWritten = true;
    final clipboard = engine.clipboard;
    if (clipboard == null) return;
    var copied = false;
    try {
      copied = await clipboard.copy(text);
    } catch (_) {
      copied = false;
    }
    if (!copied) _clipboardFailed = true;
  }

  List<ShareAttachment> _attachments(
    Set<ShareSection> chosen,
    List<ShareMediaItem> media, {
    required bool withDocument,
  }) {
    final attachments = <ShareAttachment>[];
    var position = 0;
    for (final item in media) {
      position++;
      attachments.add(engine.fetcher.attachmentFor(
        item,
        baseName: source.mediaBaseName(item, position, chosen, labels),
        refreshLink: refreshLink,
      ));
    }
    final document = source.document;
    if (withDocument &&
        document != null &&
        chosen.contains(ShareSection.document)) {
      attachments.add(ShareAttachment(
        key: documentKey,
        kind: ShareAttachmentKind.pdf,
        baseName: document.fileBaseName,
        fetch: (scratch, cancel) async =>
            FetchedShareFile(await document.fetch()),
      ));
    }
    return attachments;
  }

  void _recordFailure(ShareFailure failure) {
    _failure = failure;
    if (failure.kind == ShareFailureKind.unavailable) {
      // What could not be had is shown as unavailable and left out of the
      // choice, so sharing again is an explicit decision to go on without it.
      for (final key in failure.failedKeys) {
        if (key == documentKey) {
          _documentUnavailable = true;
          _selected.remove(ShareSection.document);
        } else {
          _unavailableMedia.add(key);
          _mediaKeys.remove(key);
        }
      }
      // A step that has nothing left to send is over.
      if (_completed.isNotEmpty && _nextFamily(mediaBatches) == null) {
        _finishShare();
      }
    }
  }

  /// A share is over (or a new one begins): no step is done and nothing was
  /// copied for it.
  void _finishShare() {
    _completed.clear();
    _clipboardWritten = false;
  }

  void _setStatus(ShareFlowStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    _failure = null;
    if (!_disposed) notifyListeners();
  }

  /// The media choice changed, so a share in progress starts over.
  void _mediaChanged() {
    _finishShare();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
