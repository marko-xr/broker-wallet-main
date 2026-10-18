import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/services/signature/signature_stamp_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';

/// A signed copy that has been written to the account's private work folder and
/// can be previewed. It is exactly the file that Save stores, so what the user
/// previews is what is saved. Any change to the items discards it.
class SignatureDraft {
  const SignatureDraft({
    required this.file,
    required this.size,
    required this.pageCount,
    required this.signatureCount,
    required this.itemCount,
    required this.appendedOnly,
  });

  final File file;
  final int size;
  final int pageCount;
  final int signatureCount;
  final int itemCount;

  /// The draft is the original file's bytes plus an appended update.
  final bool appendedOnly;
}

/// What saving did.
class SignatureSaveOutcome {
  const SignatureSaveOutcome.done(SignedDocument this.document)
      : failure = null;
  const SignatureSaveOutcome.failed(SignatureFailure this.failure)
      : document = null;

  final SignedDocument? document;
  final SignatureFailure? failure;

  bool get isDone => failure == null;
}

/// What adding a signature to more pages did.
class ApplyToPagesOutcome {
  const ApplyToPagesOutcome({required this.added, required this.skipped});

  /// Placements created.
  final int added;

  /// Pages that already carried this image and were left alone.
  final int skipped;
}

/// The editing session of one picked PDF: the images the user made, where each
/// is placed on which page, the undo history, the selection, and the steps that
/// turn the placements into a signed copy (draft, preview, save).
///
/// It owns no widgets. Placement is stored in each page's visible points, so it
/// does not depend on the screen. Every asynchronous step checks that the
/// signed-in account is still the one the session started for; a result for a
/// previous account is dropped, never stored.
class SignatureEditorViewModel extends ChangeNotifier {
  SignatureEditorViewModel({
    required this.sourcePath,
    required this.sourceName,
    required this.analysis,
    required SignatureExecutor executor,
    required SignatureStore store,
    required String userId,
    required String? Function() currentUserId,
    required Stream<String?> userIdChanges,
    required SignatureUsageRecorder usage,
    required StampRenderer renderer,
    String Function()? idGenerator,
    DateTime Function()? clock,
    Future<void> Function()? onSaved,
    Future<void> Function()? onClosed,
  })  : _executor = executor,
        _store = store,
        _userId = userId,
        _currentUserId = currentUserId,
        _usage = usage,
        _renderer = renderer,
        _newId = idGenerator ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _onSaved = onSaved,
        _onClosed = onClosed {
    _subscription = userIdChanges.listen(
      (uid) {
        if (uid != _userId && !_accountChanged) {
          _accountChanged = true;
          _token?.cancel();
          _notify();
        }
      },
      // An auth-stream error is not a sign-out: keep the current account.
      onError: (Object _, StackTrace __) {},
    );
  }

  /// The most items one document may carry, and how many undo steps are kept.
  static const int maxUndoSteps = 50;

  final String sourcePath;

  /// The picked file's own name, for the default title only.
  final String sourceName;
  final SignatureAnalysis analysis;

  final SignatureExecutor _executor;
  final SignatureStore _store;
  final String _userId;
  final String? Function() _currentUserId;
  final SignatureUsageRecorder _usage;
  final StampRenderer _renderer;
  final String Function() _newId;
  final DateTime Function() _clock;
  final Future<void> Function()? _onSaved;
  final Future<void> Function()? _onClosed;

  StreamSubscription<String?>? _subscription;
  SignatureCancelToken? _token;
  bool _disposed = false;
  bool _accountChanged = false;
  bool _building = false;
  bool _saving = false;

  final List<StampAsset> _assets = <StampAsset>[];
  List<PlacedStamp> _placements = const <PlacedStamp>[];
  final List<List<PlacedStamp>> _undo = <List<PlacedStamp>>[];
  final List<List<PlacedStamp>> _redo = <List<PlacedStamp>>[];
  List<PlacedStamp>? _editBefore;
  String? _selectedId;
  int _currentPage = 0;
  SignatureDraft? _draft;

  // ------------------------------------------------------------------ state

  int get pageCount => analysis.pageCount;
  List<PageGeometry> get pages => analysis.pages;
  List<StampAsset> get assets => List<StampAsset>.unmodifiable(_assets);
  List<PlacedStamp> get placements => _placements;
  String? get selectedId => _selectedId;
  int get currentPage => _currentPage;
  SignatureDraft? get draft => _draft;
  bool get accountChanged => _accountChanged;
  bool get isBuilding => _building;
  bool get isSaving => _saving;
  bool get isBusy => _building || _saving;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasPlacements => _placements.isNotEmpty;

  /// The signatures the user drew in this session, for reuse.
  List<StampAsset> get signatureAssets => <StampAsset>[
        for (final a in _assets)
          if (a.kind == StampKind.signature) a
      ];

  /// The initials the user made in this session, for reuse.
  List<StampAsset> get initialsAssets => <StampAsset>[
        for (final a in _assets)
          if (a.kind == StampKind.initials) a
      ];

  StampAsset? assetById(String id) {
    for (final a in _assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  PlacedStamp? stampById(String id) {
    for (final s in _placements) {
      if (s.id == id) return s;
    }
    return null;
  }

  PlacedStamp? get selectedStamp {
    final id = _selectedId;
    return id == null ? null : stampById(id);
  }

  List<PlacedStamp> stampsOnPage(int pageIndex) => <PlacedStamp>[
        for (final s in _placements)
          if (s.pageIndex == pageIndex) s
      ];

  /// How many placements carry a signature or initials.
  int get signaturePlacementCount => _placements
      .where((s) => assetById(s.assetId)?.countsAsSignature ?? false)
      .length;

  /// The title a new signed copy gets unless the user types one.
  String suggestedName(String suffix) =>
      SignatureNaming.defaultName(sourceName, suffix, _clock());

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _token?.cancel();
    final draft = _draft;
    _draft = null;
    if (draft != null) unawaited(_store.releaseWorkFile(draft.file));
    final closed = _onClosed;
    if (closed != null) unawaited(closed());
    super.dispose();
  }

  // ------------------------------------------------------------ page checks

  /// Compares the page sizes the page renderer reports with the geometry read
  /// from the file. The editor lays its overlays on the renderer's bitmaps and
  /// the export places stamps by the file's geometry; if the two disagree by more
  /// than a point on any page, a placement could land elsewhere than shown, so
  /// the file is refused. Returns null when they agree.
  SignatureFailure? checkRendererSizes(List<RenderedPageSize> sizes,
      {double tolerance = 1.0}) {
    if (sizes.length != analysis.pageCount) {
      return SignatureFailure.geometryUnsupported;
    }
    for (var i = 0; i < sizes.length; i++) {
      final geometry = analysis.pages[i];
      if ((sizes[i].width - geometry.width).abs() > tolerance ||
          (sizes[i].height - geometry.height).abs() > tolerance) {
        return SignatureFailure.geometryUnsupported;
      }
    }
    return null;
  }

  // ------------------------------------------------------------- navigation

  void selectPage(int index) {
    if (index < 0 || index >= pageCount || index == _currentPage) return;
    _currentPage = index;
    final selected = selectedStamp;
    if (selected != null && selected.pageIndex != index) _selectedId = null;
    _notify();
  }

  void select(String? id) {
    if (id != null && stampById(id) == null) return;
    if (_selectedId == id) return;
    _selectedId = id;
    _notify();
  }

  // ----------------------------------------------------------------- assets

  /// Renders [drawing] as a signature or initials image and keeps it for reuse.
  /// Throws a [SignatureException] (`stampFailed`).
  Future<StampAsset> createDrawnAsset(
      StampKind kind, SignatureDrawing drawing) async {
    assert(kind == StampKind.signature || kind == StampKind.initials);
    final asset = await _renderer.renderDrawing(
        id: _newId(), kind: kind, drawing: drawing);
    if (_disposed) {
      throw const SignatureException(SignatureFailure.cancelled);
    }
    _assets.add(asset);
    _notify();
    return asset;
  }

  /// Renders a typed initials, date or text image. Throws a [SignatureException]
  /// (`stampFailed`).
  Future<StampAsset> createTextAsset(
      StampKind kind, String text, int colorValue) async {
    assert(kind != StampKind.signature);
    final asset = await _renderer.renderText(
        id: _newId(), kind: kind, text: text, colorValue: colorValue);
    if (_disposed) {
      throw const SignatureException(SignatureFailure.cancelled);
    }
    _assets.add(asset);
    _notify();
    return asset;
  }

  // ------------------------------------------------------------ placements

  void _push() {
    _undo.add(_placements);
    if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    _redo.clear();
  }

  void _changed() {
    _discardDraft();
    _notify();
  }

  /// Puts [asset] on [pageIndex] at its first size, in the middle of the page,
  /// and selects it. Returns the new placement, or throws a [SignatureException]
  /// (`tooManyItems`, `invalidPlacement`).
  PlacedStamp place(StampAsset asset, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pageCount) {
      throw const SignatureException(SignatureFailure.invalidPlacement,
          detail: 'page');
    }
    if (_placements.length >= SignatureLimits.maxItems) {
      throw const SignatureException(SignatureFailure.tooManyItems);
    }
    if (assetById(asset.id) == null) _assets.add(asset);
    final geometry = analysis.pages[pageIndex];
    final size = asset.kind == StampKind.signature
        ? StampSize.signature
        : asset.kind == StampKind.initials
            ? StampSize.initials
            : StampSize.line;
    final rect = StampLayout.initialPlacement(
      size: size,
      aspect: asset.aspect,
      pageW: geometry.width,
      pageH: geometry.height,
    );
    final stamp = PlacedStamp(
        id: _newId(), assetId: asset.id, pageIndex: pageIndex, rect: rect);
    _push();
    _placements = <PlacedStamp>[..._placements, stamp];
    _selectedId = stamp.id;
    _changed();
    return stamp;
  }

  /// Starts a drag or resize: the state before it is what Undo returns to.
  void beginEdit() {
    _editBefore ??= _placements;
  }

  /// Moves or resizes [id] to [rect] (kept inside the page) without adding an
  /// undo step; call [endEdit] when the gesture ends.
  void updateRect(String id, PageRect rect) {
    final index = _placements.indexWhere((s) => s.id == id);
    if (index < 0 || !rect.isFinite) return;
    final stamp = _placements[index];
    final geometry = analysis.pages[stamp.pageIndex];
    final next = StampLayout.clamp(rect, geometry.width, geometry.height);
    if (next == stamp.rect) return;
    _placements = <PlacedStamp>[
      for (var i = 0; i < _placements.length; i++)
        i == index ? stamp.copyWith(rect: next) : _placements[i],
    ];
    _changed();
  }

  /// Ends a drag or resize. When something changed, one undo step covers it.
  void endEdit() {
    final before = _editBefore;
    _editBefore = null;
    if (before == null) return;
    if (!listEquals(before, _placements)) {
      _undo.add(before);
      if (_undo.length > maxUndoSteps) _undo.removeAt(0);
      _redo.clear();
      _notify();
    }
  }

  /// Makes [id] [factor] times as wide (and as high), about its centre.
  void scaleBy(String id, double factor) {
    final stamp = stampById(id);
    if (stamp == null) return;
    final geometry = analysis.pages[stamp.pageIndex];
    beginEdit();
    updateRect(
        id,
        StampLayout.scaleAroundCenter(
            stamp.rect, factor, geometry.width, geometry.height));
    endEdit();
  }

  /// Removes one placed item. Its image stays available for reuse.
  void delete(String id) {
    if (stampById(id) == null) return;
    _push();
    _placements = <PlacedStamp>[
      for (final s in _placements)
        if (s.id != id) s
    ];
    if (_selectedId == id) _selectedId = null;
    _changed();
  }

  /// Gives the placed item [id] a new image, keeping its width and centre. Only
  /// this item changes; other placements of the old image are not touched.
  void replaceImage(String id, StampAsset asset) {
    final stamp = stampById(id);
    if (stamp == null) return;
    if (assetById(asset.id) == null) _assets.add(asset);
    final geometry = analysis.pages[stamp.pageIndex];
    final width = stamp.rect.width;
    final height = width / asset.aspect;
    final rect = StampLayout.clamp(
      PageRect(stamp.rect.centerX - width / 2, stamp.rect.centerY - height / 2,
          width, height),
      geometry.width,
      geometry.height,
    );
    _push();
    _placements = <PlacedStamp>[
      for (final s in _placements)
        s.id == id ? s.copyWith(assetId: asset.id, rect: rect) : s,
    ];
    _changed();
  }

  /// Puts the image of placed item [id] on each of [pages] as well, at the same
  /// size and the same place on the page. A page that already carries this image
  /// is left alone (no accidental duplicates); every other page is an explicit
  /// choice of the caller. The new items are independent of each other.
  ApplyToPagesOutcome applyToPages(String id, Iterable<int> pages) {
    final source = stampById(id);
    if (source == null) return const ApplyToPagesOutcome(added: 0, skipped: 0);
    final from = analysis.pages[source.pageIndex];
    final created = <PlacedStamp>[];
    var skipped = 0;
    for (final page in pages.toSet().toList()..sort()) {
      if (page < 0 || page >= pageCount || page == source.pageIndex) continue;
      final already = _placements
              .any((s) => s.pageIndex == page && s.assetId == source.assetId) ||
          created.any((s) => s.pageIndex == page);
      if (already) {
        skipped++;
        continue;
      }
      if (_placements.length + created.length >= SignatureLimits.maxItems) {
        throw const SignatureException(SignatureFailure.tooManyItems);
      }
      final to = analysis.pages[page];
      created.add(PlacedStamp(
        id: _newId(),
        assetId: source.assetId,
        pageIndex: page,
        rect: StampLayout.carryToPage(
          rect: source.rect,
          fromPageW: from.width,
          fromPageH: from.height,
          toPageW: to.width,
          toPageH: to.height,
        ),
      ));
    }
    if (created.isEmpty) {
      return ApplyToPagesOutcome(added: 0, skipped: skipped);
    }
    _push();
    _placements = <PlacedStamp>[..._placements, ...created];
    _changed();
    return ApplyToPagesOutcome(added: created.length, skipped: skipped);
  }

  void undo() {
    if (_undo.isEmpty || isBusy) return;
    _redo.add(_placements);
    _placements = _undo.removeLast();
    _afterHistoryStep();
  }

  void redo() {
    if (_redo.isEmpty || isBusy) return;
    _undo.add(_placements);
    _placements = _redo.removeLast();
    _afterHistoryStep();
  }

  void _afterHistoryStep() {
    if (_selectedId != null && stampById(_selectedId!) == null) {
      _selectedId = null;
    }
    _changed();
  }

  // ------------------------------------------------------------------ draft

  void _discardDraft() {
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    unawaited(_store.releaseWorkFile(draft.file));
  }

  SignatureFailure? get _accountProblem {
    if (_accountChanged || _currentUserId() != _userId) {
      return SignatureFailure.accountChanged;
    }
    return null;
  }

  /// Writes the signed copy to the account's work folder so it can be previewed.
  /// Returns null on success (see [draft]) or the reason it failed. A draft that
  /// is already current is reused. Nothing is stored or counted.
  Future<SignatureFailure?> buildDraft() async {
    if (_building || _saving) return SignatureFailure.busy;
    final problem = _accountProblem;
    if (problem != null) return problem;
    if (_placements.isEmpty) return SignatureFailure.noPlacements;
    if (_draft != null) return null;
    final token = SignatureCancelToken();
    _token = token;
    _building = true;
    _notify();
    File? work;
    try {
      final snapshot = _placements;
      final usedAssets = <String>[];
      for (final stamp in snapshot) {
        if (!usedAssets.contains(stamp.assetId)) usedAssets.add(stamp.assetId);
      }
      final images = <Uint8List>[];
      for (final id in usedAssets) {
        final asset = assetById(id);
        if (asset == null) {
          return SignatureFailure.invalidPlacement;
        }
        images.add(asset.png);
      }
      work = await _store.newWorkFile();
      final result = await _executor.write(
        SignatureWriteJob(
          sourcePath: sourcePath,
          source: analysis,
          images: images,
          placements: <SignatureWritePlacement>[
            for (final s in snapshot)
              SignatureWritePlacement(
                pageIndex: s.pageIndex,
                imageIndex: usedAssets.indexOf(s.assetId),
                rect: s.rect,
              ),
          ],
          outputPath: work.path,
        ),
        token,
      );
      if (_disposed || _accountProblem != null) {
        return SignatureFailure.accountChanged;
      }
      if (!listEquals(snapshot, _placements)) {
        // The items changed while the draft was being written: it is stale.
        return SignatureFailure.cancelled;
      }
      _draft = SignatureDraft(
        file: work,
        size: result.size,
        pageCount: result.pageCount,
        signatureCount: signaturePlacementCount,
        itemCount: snapshot.length,
        appendedOnly: result.appendedOnly,
      );
      work = null;
      return null;
    } on SignatureException catch (error) {
      if (_disposed) return SignatureFailure.cancelled;
      if (_accountChanged) return SignatureFailure.accountChanged;
      return error.kind;
    } catch (_) {
      return SignatureFailure.writeFailed;
    } finally {
      if (work != null) await _store.releaseWorkFile(work);
      _building = false;
      if (identical(_token, token)) _token = null;
      _notify();
    }
  }

  /// Stops a draft that is being written. Nothing is stored or counted.
  void cancelBuild() => _token?.cancel();

  /// Stores the current draft under [name] and counts it once. [allowNew] is the
  /// plan-limit question, asked first; nothing is stored when it says no. The
  /// document is stored (verified byte for byte against the draft) before it is
  /// counted, and a failure or a cancel counts nothing.
  Future<SignatureSaveOutcome> save({
    required String name,
    required Future<bool> Function(String userId) allowNew,
  }) async {
    if (_saving || _building) {
      return const SignatureSaveOutcome.failed(SignatureFailure.busy);
    }
    final problem = _accountProblem;
    if (problem != null) return SignatureSaveOutcome.failed(problem);
    final draft = _draft;
    if (draft == null) {
      return const SignatureSaveOutcome.failed(SignatureFailure.noPlacements);
    }
    _saving = true;
    _notify();
    try {
      if (!await allowNew(_userId)) {
        return const SignatureSaveOutcome.failed(SignatureFailure.quotaBlocked);
      }
      if (_disposed || _accountProblem != null) {
        return const SignatureSaveOutcome.failed(
            SignatureFailure.accountChanged);
      }
      final title = SignatureNaming.sanitizeDisplayName(name) ??
          SignatureNaming.defaultName(sourceName, 'signed', _clock());
      final stored = await _store.add(
        source: draft.file,
        name: title,
        size: draft.size,
        pageCount: draft.pageCount,
        signatureCount: draft.signatureCount,
        itemCount: draft.itemCount,
      );
      // The document is stored for this account; count it exactly once.
      try {
        await _usage.recordSignedDocument(_userId);
      } catch (_) {}
      _draft = null;
      await _store.releaseWorkFile(draft.file);
      final saved = _onSaved;
      if (saved != null) {
        try {
          await saved();
        } catch (_) {}
      }
      return SignatureSaveOutcome.done(stored);
    } on SignatureException catch (error) {
      await _dropDraftIfGone(draft);
      if (_disposed || _accountChanged) {
        return const SignatureSaveOutcome.failed(
            SignatureFailure.accountChanged);
      }
      return SignatureSaveOutcome.failed(error.kind);
    } catch (_) {
      await _dropDraftIfGone(draft);
      return const SignatureSaveOutcome.failed(SignatureFailure.writeFailed);
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// A draft whose file is no longer there cannot be retried; forget it so the
  /// next preview writes a new one.
  Future<void> _dropDraftIfGone(SignatureDraft draft) async {
    try {
      if (!await draft.file.exists() && identical(_draft, draft)) {
        _draft = null;
      }
    } catch (_) {}
  }

  /// Drops the draft (the user went back to editing).
  void discardDraft() {
    if (_draft == null) return;
    _discardDraft();
    _notify();
  }
}
