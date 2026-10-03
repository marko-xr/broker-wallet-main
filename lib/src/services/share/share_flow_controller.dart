import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';

/// The collaborators a share needs: where its files are prepared, how a private
/// photo or video is fetched, and the native share sheet.
class ShareEngine {
  const ShareEngine({
    required this.preparer,
    required this.fetcher,
    required this.launcher,
  });

  final SharePreparer preparer;
  final ShareMediaFetcher fetcher;
  final ShareLauncher launcher;
}

enum ShareFlowStatus {
  /// Waiting for the person to choose.
  idle,

  /// Fetching and naming the chosen files.
  preparing,

  /// The native share sheet is open.
  sharing,
}

/// How a call to [ShareFlowController.share] ended.
enum ShareFlowResult {
  /// The share sheet was used (or the platform cannot tell): the flow is done.
  shared,

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
class ShareFlowController extends ChangeNotifier {
  ShareFlowController({
    required this.source,
    required this.labels,
    required this.engine,
    this.refreshLink,
  })  : _selected = <ShareSection>{
          ...source.defaultSelection.where((s) => s != ShareSection.media),
        },
        _mediaKeys = <String>{...source.defaultMediaKeys};

  /// The key of the document in a [ShareFailure].
  static const String documentKey = 'document';

  final ShareSource source;
  final ShareLabels labels;
  final ShareEngine engine;

  /// Fetches a fresh link for a private video or photo whose link expired.
  final LinkRefresher? refreshLink;

  final Set<ShareSection> _selected;
  final Set<String> _mediaKeys;
  final Set<String> _unavailableMedia = <String>{};
  bool _documentUnavailable = false;

  ShareFlowStatus _status = ShareFlowStatus.idle;
  ShareFailure? _failure;
  ShareCancelToken? _token;
  bool _disposed = false;

  ShareFlowStatus get status => _status;

  /// A share is being prepared or its sheet is open.
  bool get isBusy => _status != ShareFlowStatus.idle;

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
    _changed();
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
    } else if (!_selected.remove(section)) {
      _selected.add(section);
    }
    _changed();
  }

  void toggleMedia(String key) {
    if (isBusy || _unavailableMedia.contains(key)) return;
    if (!source.media.any((item) => item.key == key)) return;
    if (!_mediaKeys.remove(key)) _mediaKeys.add(key);
    _changed();
  }

  void selectAllMedia() {
    if (isBusy) return;
    _mediaKeys
      ..clear()
      ..addAll(_selectableMedia);
    _changed();
  }

  void clearMedia() {
    if (isBusy) return;
    _mediaKeys.clear();
    _changed();
  }

  /// Calls off a share that is being prepared. Safe at any time.
  void cancel() => _token?.cancel();

  /// Prepares what was chosen and opens the native share sheet.
  ///
  /// Only one share runs at a time: a second call while one is under way
  /// returns [ShareFlowResult.busy] and does nothing, so a double tap cannot
  /// start two downloads or open two sheets.
  Future<ShareFlowResult> share({ShareOrigin? origin}) async {
    if (_disposed) return ShareFlowResult.cancelled;
    if (isBusy) return ShareFlowResult.busy;
    if (!hasSelection) return ShareFlowResult.nothingSelected;

    final token = ShareCancelToken();
    _token = token;
    _failure = null;
    _setStatus(ShareFlowStatus.preparing);

    ShareBundle? bundle;
    try {
      final chosen = selection;
      final text = source.composeText(chosen, labels);
      final attachments = _attachments(chosen);
      if (attachments.isNotEmpty) {
        bundle = await engine.preparer.prepare(attachments, token);
      }
      if (token.isCancelled || _disposed) {
        await bundle?.discard();
        return ShareFlowResult.cancelled;
      }

      _setStatus(ShareFlowStatus.sharing);
      final subject = labels.text(source.subjectKey);
      final outcome = await engine.launcher.launch(ShareRequest(
        text: text,
        subject: subject.isEmpty ? null : subject,
        files: bundle?.files ?? const <PreparedShareFile>[],
        origin: origin,
      ));
      if (outcome == null) {
        await bundle?.discard();
        return ShareFlowResult.busy;
      }
      if (outcome == ShareOutcome.dismissed) {
        // Nobody received the files, so they can go at once.
        await bundle?.discard();
        return ShareFlowResult.dismissed;
      }
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
      _setStatus(ShareFlowStatus.idle);
    }
  }

  List<ShareAttachment> _attachments(Set<ShareSection> chosen) {
    final attachments = <ShareAttachment>[];
    var position = 0;
    for (final item in source.media) {
      if (!_mediaKeys.contains(item.key)) continue;
      position++;
      attachments.add(engine.fetcher.attachmentFor(
        item,
        baseName: source.mediaBaseName(item, position, chosen, labels),
        refreshLink: refreshLink,
      ));
    }
    final document = source.document;
    if (document != null && chosen.contains(ShareSection.document)) {
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
    }
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

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
