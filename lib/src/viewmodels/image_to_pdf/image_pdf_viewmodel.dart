import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_executor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_layout.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_processor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_store.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

enum ImageItemStatus { checking, ready, failed }

/// One picture the user selected. [path] is the tool's own private copy; the
/// original (and the picker's copy of it) is never changed.
class ImagePdfItem {
  ImagePdfItem({
    required this.id,
    required this.path,
    required this.displayName,
    required this.size,
  });

  final String id;
  final String path;
  final String displayName;
  final int size;

  ImageItemStatus status = ImageItemStatus.checking;
  ImagePdfFailure? failure;
  ImageAnalysis? analysis;

  /// Another selected picture has exactly the same bytes. Both are kept: the
  /// user decides.
  bool possibleDuplicate = false;

  bool get isReady => status == ImageItemStatus.ready;

  ImageSpec? get spec {
    final a = analysis;
    if (a == null) return null;
    return ImageSpec(
      id: id,
      path: path,
      size: a.size,
      format: a.format,
      width: a.width,
      height: a.height,
      orientation: a.orientation,
      hasAlpha: a.hasAlpha,
      isBaselineJpeg: a.isBaselineJpeg,
      dpi: a.dpi,
    );
  }
}

/// A picked picture that was not added, and why.
class RejectedImage {
  const RejectedImage(this.name, this.failure);

  final String name;
  final ImagePdfFailure failure;
}

/// What picking and staging pictures did.
class AddImagesOutcome {
  const AddImagesOutcome({
    this.added = 0,
    this.possibleDuplicates = 0,
    this.rejected = const <RejectedImage>[],
    this.cancelled = false,
    this.failure,
  });

  const AddImagesOutcome.failed(ImagePdfFailure this.failure)
      : added = 0,
        possibleDuplicates = 0,
        rejected = const <RejectedImage>[],
        cancelled = false;

  final int added;

  /// Pictures added that match one already selected (kept, flagged).
  final int possibleDuplicates;
  final List<RejectedImage> rejected;

  /// The picker was closed without a choice.
  final bool cancelled;

  /// The whole action could not run (signed out, busy, camera denied...).
  final ImagePdfFailure? failure;
}

/// The finished, verified PDF that has not been saved yet. It is exactly the
/// file Save stores, so previewing it previews the saved PDF.
class ImagePdfDraft {
  const ImagePdfDraft({
    required this.file,
    required this.pageCount,
    required this.imageCount,
    required this.size,
    required this.lowResolutionImages,
    required this.encrypted,
    required this.builtAt,
  });

  final File file;
  final int pageCount;
  final int imageCount;
  final int size;
  final int lowResolutionImages;
  final bool encrypted;
  final DateTime builtAt;
}

/// The result of making (or reusing) the draft.
class DraftOutcome {
  const DraftOutcome.done(ImagePdfDraft this.draft)
      : failure = null,
        sourceName = null;
  const DraftOutcome.failed(ImagePdfFailure this.failure, {this.sourceName})
      : draft = null;

  final ImagePdfDraft? draft;
  final ImagePdfFailure? failure;

  /// The picture a failure is about, when it is about one.
  final String? sourceName;

  bool get isDone => failure == null;
}

/// The result of saving the draft.
class SaveOutcome {
  const SaveOutcome.done(ImagePdfDocument this.document) : failure = null;
  const SaveOutcome.failed(ImagePdfFailure this.failure) : document = null;

  final ImagePdfDocument? document;
  final ImagePdfFailure? failure;

  bool get isDone => failure == null;
}

/// Files ready to hand to the share sheet, or the documents that could not be
/// shared because their stored file is gone or damaged.
class ImagePdfSharePreparation {
  const ImagePdfSharePreparation(
      {required this.paths, required this.unavailable});

  final List<String> paths;
  final List<String> unavailable;

  bool get isShareable => unavailable.isEmpty && paths.isNotEmpty;
}

/// The Images to PDF screen's logic: the signed-in account's PDFs, the pending
/// selection (pictures, order, settings), the draft and its saving. It owns no
/// widgets.
///
/// Every asynchronous step checks that the screen is still alive and that the
/// signed-in account is still the one the step started for; a result for a
/// previous account is dropped, never shown or stored. Only one conversion,
/// pick or library action runs at a time, so a double tap does nothing. Any
/// change to the pictures, their order or the settings discards the draft, so a
/// stale PDF can never be previewed or saved.
class ImagePdfViewModel extends ChangeNotifier {
  ImagePdfViewModel({
    required ImagePdfExecutor executor,
    required Future<Directory> Function() baseDirectory,
    required ImagePdfImagePicker picker,
    required ImagePdfImageNormalizer normalizer,
    required ImagePdfUsageRecorder usage,
    required ImagePdfSharePreparer sharePreparer,
    required ImagePdfExporter exporter,
    required ScannerBackupGuard backup,
    required String? Function() currentUserId,
    required Stream<String?> userIdChanges,
    Future<Uint8List?> Function()? loadUnicodeFont,
    Future<Directory> Function()? tempRoot,
    Future<int> Function()? legacyDocumentCount,
    ImagePdfFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _executor = executor,
        _baseDirectory = baseDirectory,
        _picker = picker,
        _normalizer = normalizer,
        _usage = usage,
        _sharePreparer = sharePreparer,
        _exporter = exporter,
        _backup = backup,
        _currentUserId = currentUserId,
        _userIdChanges = userIdChanges,
        _loadUnicodeFont = loadUnicodeFont,
        _tempRoot = tempRoot,
        _legacyDocumentCount = legacyDocumentCount,
        _copier = copier,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator;

  final ImagePdfExecutor _executor;
  final Future<Directory> Function() _baseDirectory;
  final ImagePdfImagePicker _picker;
  final ImagePdfImageNormalizer _normalizer;
  final ImagePdfUsageRecorder _usage;
  final ImagePdfSharePreparer _sharePreparer;
  final ImagePdfExporter _exporter;
  final ScannerBackupGuard _backup;
  final String? Function() _currentUserId;
  final Stream<String?> _userIdChanges;
  final Future<Uint8List?> Function()? _loadUnicodeFont;
  final Future<Directory> Function()? _tempRoot;
  final Future<int> Function()? _legacyDocumentCount;
  final ImagePdfFileCopier? _copier;
  final DateTime Function() _clock;
  final String Function()? _idGenerator;

  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  ImagePdfStore? _store;

  final List<ImagePdfItem> _items = <ImagePdfItem>[];
  ImagePdfSettings _settings = const ImagePdfSettings();
  String _password = '';
  ImagePdfDraft? _draft;
  String? _draftTitle;
  String? _draftCoverKey;

  List<ImagePdfDocument> _documents = const <ImagePdfDocument>[];
  Set<String> _missing = const <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _adding = false;
  bool _building = false;
  bool _saving = false;
  bool _working = false;
  bool _analysisRunning = false;
  int _legacyCount = 0;
  ImagePdfCancelToken? _token;
  final Set<String> _recoveredPaths = <String>{};

  List<ImagePdfItem> get items => List<ImagePdfItem>.unmodifiable(_items);
  ImagePdfSettings get settings => _settings;
  ImagePdfDraft? get draft => _draft;
  List<ImagePdfDocument> get documents => _documents;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;

  /// Pictures are being picked or copied.
  bool get isAdding => _adding;

  /// The PDF is being made.
  bool get isBuilding => _building;

  /// The draft is being stored.
  bool get isSaving => _saving;

  /// A library action (rename, delete, share, export) is running.
  bool get isWorking => _working;
  bool get isBusy => _adding || _building || _saving || _working;

  /// Some pictures are still being read and checked.
  bool get isChecking =>
      _items.any((i) => i.status == ImageItemStatus.checking);
  bool get hasFailedItems =>
      _items.any((i) => i.status == ImageItemStatus.failed);
  bool get isSelectionMode => _selectionMode;
  int get legacyDocumentCount => _legacyCount;
  String? get userId => _userId;
  bool get hasPassword => _password.isNotEmpty;

  bool isMissing(String id) => _missing.contains(id);
  bool isSelected(String id) => _selected.contains(id);
  int get selectedCount => _selected.length;

  List<ImagePdfDocument> get selectedDocuments => <ImagePdfDocument>[
        for (final d in _documents)
          if (_selected.contains(d.id)) d
      ];

  /// The title a new PDF gets unless the user types one.
  String get suggestedName => ImagePdfNaming.defaultName(_clock());

  /// The pages the PDF will have for the pictures checked so far, from the same
  /// plan the engine builds with. Null until at least one picture is ready.
  int? get plannedPageCount {
    final dims = <ImageDimensions>[
      for (final item in _items)
        if (item.analysis != null)
          ImageDimensions(item.analysis!.width, item.analysis!.height,
              dpi: item.analysis!.dpi),
    ];
    if (dims.isEmpty || _settings.validate() != null) return null;
    return ImagePdfLayout.plan(_settings, dims).pageCount;
  }

  // -------------------------------------------------------------- lifecycle

  Future<void> start() async {
    _subscription = _userIdChanges.listen(
      (uid) => unawaited(_switchTo(uid)),
      // An auth-stream error is not a sign-out: keep the current account.
      onError: (Object _, StackTrace __) {},
    );
    await _switchTo(_currentUserId());
    unawaited(_sharePreparer.sweepStale());
    final counter = _legacyDocumentCount;
    if (counter != null) {
      try {
        final count = await counter();
        if (_disposed) return;
        _legacyCount = count;
        _notify();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _token?.cancel();
    _password = '';
    _releaseEverything();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Deletes the draft and every staged picture of the current selection
  /// (best effort, not awaited).
  void _releaseEverything() {
    final store = _store;
    final staged = <String>[for (final i in _items) i.path];
    final draft = _draft;
    _items.clear();
    _draft = null;
    _draftTitle = null;
    _draftCoverKey = null;
    if (store == null) return;
    if (draft != null) unawaited(store.releaseWorkFile(draft.file));
    for (final path in staged) {
      unawaited(_quietDelete(File(path)));
    }
  }

  Future<void> _switchTo(String? uid) async {
    if (_disposed) return;
    if (uid == _userId && (uid == null || _store != null)) return;
    _epoch++;
    final epoch = _epoch;
    _token?.cancel();
    _password = '';
    _releaseEverything();
    _userId = uid;
    _store = null;
    _documents = const <ImagePdfDocument>[];
    _missing = const <String>{};
    _selected.clear();
    _selectionMode = false;
    _loadFailed = false;
    _loading = uid != null;
    _notify();
    if (uid == null) return;
    try {
      final base = await _baseDirectory();
      // The account's PDFs stay out of cloud and device backup (iPhone needs the
      // folder marked; Android's rules name it). Best effort and never fatal.
      try {
        final root = Directory(p.join(base.path, ImagePdfStore.rootFolderName));
        await root.create(recursive: true);
        await _backup.exclude(root.path);
      } catch (_) {}
      if (_disposed || epoch != _epoch) return;
      final store = ImagePdfStore(
        accountDir: ImagePdfStore.accountDirectory(base, uid),
        userId: uid,
        verify: (file) => _executor.analyzePdf(file.path),
        copier: _copier,
        clock: _clock,
        idGenerator: _idGenerator,
      );
      // A selection does not survive the app: copies left by an earlier run
      // belong to nobody.
      await store.sweepStaging();
      if (_disposed || epoch != _epoch) return;
      _store = store;
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loading = false;
      _loadFailed = true;
      _notify();
      return;
    }
    await refresh();
  }

  /// Reloads the signed-in account's documents from disk.
  Future<void> refresh() async {
    final store = _store;
    final epoch = _epoch;
    if (store == null) return;
    try {
      final library = await store.load();
      if (_disposed || epoch != _epoch) return;
      _documents = library.documents;
      _missing = library.missingIds;
      _loadFailed = false;
      final ids = _documents.map((d) => d.id).toSet();
      _selected.removeWhere((id) => !ids.contains(id));
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loadFailed = true;
    }
    _loading = false;
    _notify();
  }

  // ------------------------------------------------------------- the draft

  /// Drops the draft (and its file) because something it was made from changed.
  void _invalidateDraft() {
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    _draftTitle = null;
    _draftCoverKey = null;
    final store = _store;
    if (store != null) unawaited(store.releaseWorkFile(draft.file));
  }

  /// Replaces the settings. Discards the draft when anything changed.
  void updateSettings(ImagePdfSettings next) {
    if (_building || _saving) return;
    if (next == _settings) return;
    _settings = next;
    if (!next.passwordProtect) _password = '';
    _invalidateDraft();
    _notify();
  }

  /// Sets the password for the next PDF. It lives only in memory, is never
  /// logged or stored, and is cleared after the PDF is saved or discarded.
  void setPassword(String value) {
    if (_building || _saving) return;
    if (value == _password) return;
    _password = value;
    if (_settings.passwordProtect) _invalidateDraft();
    _notify();
  }

  // ---------------------------------------------------------- the selection

  /// Opens the gallery picker and adds the chosen pictures.
  Future<AddImagesOutcome> pickFromGallery() async {
    final early = _canStartSelection();
    if (early != null) return AddImagesOutcome.failed(early);
    final epoch = _epoch;
    _adding = true;
    _notify();
    try {
      final List<PickedImage>? picked;
      try {
        picked = await _picker.pickFromGallery();
      } on ImagePdfException catch (error) {
        return AddImagesOutcome.failed(error.kind);
      }
      if (_disposed || epoch != _epoch) {
        return const AddImagesOutcome.failed(ImagePdfFailure.accountChanged);
      }
      if (picked == null) return const AddImagesOutcome(cancelled: true);
      return await _addPicked(picked, epoch);
    } catch (_) {
      return const AddImagesOutcome.failed(ImagePdfFailure.pickerFailed);
    } finally {
      _adding = false;
      _notify();
    }
  }

  /// Takes a photo with the phone's camera app and adds it.
  Future<AddImagesOutcome> captureFromCamera() async {
    final early = _canStartSelection();
    if (early != null) return AddImagesOutcome.failed(early);
    final epoch = _epoch;
    _adding = true;
    _notify();
    try {
      final PickedImage? photo;
      try {
        photo = await _picker.capturePhoto();
      } on ImagePdfException catch (error) {
        return AddImagesOutcome.failed(error.kind);
      }
      if (_disposed || epoch != _epoch) {
        return const AddImagesOutcome.failed(ImagePdfFailure.accountChanged);
      }
      if (photo == null) return const AddImagesOutcome(cancelled: true);
      return await _addPicked(<PickedImage>[photo], epoch);
    } catch (_) {
      return const AddImagesOutcome.failed(ImagePdfFailure.pickerFailed);
    } finally {
      _adding = false;
      _notify();
    }
  }

  /// Adds the pictures a picker of this tool had returned just before Android
  /// stopped the app (see [ImagePdfImagePicker.recoverLostPicks]): only for the
  /// signed-in account that opened the picker, once, in the order picked, as an
  /// ordinary add. Nothing is converted, saved or counted. Null when there is
  /// nothing to recover or another action is running (the pictures then stay
  /// kept for the next opening).
  Future<AddImagesOutcome?> recoverLostPicks() async {
    if (_canStartSelection() != null) return null;
    final epoch = _epoch;
    _adding = true;
    _notify();
    try {
      final lost = await _picker.recoverLostPicks();
      if (_disposed || epoch != _epoch) return null;
      // Never the same file twice, even if recovery is asked for twice.
      final fresh = <PickedImage>[
        for (final picked in lost)
          if (_recoveredPaths.add(picked.path)) picked,
      ];
      if (fresh.isEmpty) return null;
      return await _addPicked(fresh, epoch);
    } catch (_) {
      return null;
    } finally {
      _adding = false;
      _notify();
    }
  }

  /// Adds already-picked pictures (the pickers' own entry point, and tests').
  Future<AddImagesOutcome> addPickedImages(List<PickedImage> picked) async {
    final early = _canStartSelection();
    if (early != null) return AddImagesOutcome.failed(early);
    final epoch = _epoch;
    _adding = true;
    _notify();
    try {
      return await _addPicked(picked, epoch);
    } finally {
      _adding = false;
      _notify();
    }
  }

  ImagePdfFailure? _canStartSelection() {
    if (_adding || _building || _saving || _working) {
      return ImagePdfFailure.busy;
    }
    final uid = _userId;
    if (uid == null || _store == null || _currentUserId() != uid) {
      return ImagePdfFailure.signedOut;
    }
    return null;
  }

  Future<AddImagesOutcome> _addPicked(
      List<PickedImage> picked, int epoch) async {
    final store = _store!;
    var added = 0;
    var duplicates = 0;
    final rejected = <RejectedImage>[];
    for (final file in picked) {
      if (_items.length >= ImagePdfLimits.maxImages) {
        rejected.add(RejectedImage(file.name, ImagePdfFailure.tooManyImages));
        continue;
      }
      final source = File(file.path);
      File? staged;
      try {
        if (file.path.isEmpty || !await source.exists()) {
          rejected.add(RejectedImage(file.name, ImagePdfFailure.missingSource));
          continue;
        }
        staged = await store.newStagingFile(_extensionOf(file.name));
        await source.copy(staged.path);
        if (_disposed || epoch != _epoch) {
          await _quietDelete(staged);
          return const AddImagesOutcome.failed(ImagePdfFailure.accountChanged);
        }
        if (await _isHeic(staged)) {
          final jpeg = await store.newStagingFile('jpg');
          final converted = await _normalizer.heicToJpeg(staged, jpeg);
          await _quietDelete(staged);
          staged = converted;
          if (staged == null) {
            await _quietDelete(jpeg);
            rejected.add(
                RejectedImage(file.name, ImagePdfFailure.unsupportedFormat));
            continue;
          }
          if (_disposed || epoch != _epoch) {
            await _quietDelete(staged);
            return const AddImagesOutcome.failed(
                ImagePdfFailure.accountChanged);
          }
        }
        final size = await staged.length();
        final item = ImagePdfItem(
          id: const Uuid().v4(),
          path: staged.path,
          displayName: file.name,
          size: size,
        );
        final twin = await _findTwin(item, epoch);
        if (_disposed || epoch != _epoch) {
          await _quietDelete(staged);
          return const AddImagesOutcome.failed(ImagePdfFailure.accountChanged);
        }
        if (twin != null) {
          item.possibleDuplicate = true;
          twin.possibleDuplicate = true;
          duplicates++;
        }
        _items.add(item);
        _invalidateDraft();
        added++;
        unawaited(_deletePickerCopy(source));
        _notify();
      } on FileSystemException catch (error) {
        if (staged != null) await _quietDelete(staged);
        final code = error.osError?.errorCode;
        rejected.add(RejectedImage(
            file.name,
            code == 28 || code == 112
                ? ImagePdfFailure.storageFull
                : ImagePdfFailure.missingSource));
      } catch (_) {
        if (staged != null) await _quietDelete(staged);
        rejected.add(RejectedImage(file.name, ImagePdfFailure.missingSource));
      }
    }
    unawaited(_pumpAnalysis(epoch));
    return AddImagesOutcome(
        added: added, possibleDuplicates: duplicates, rejected: rejected);
  }

  String _extensionOf(String name) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'img';
  }

  Future<bool> _isHeic(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final head = await handle.read(32);
      return ImagePdfFormats.sniff(Uint8List.fromList(head)) == 'heic';
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  /// An already selected picture with exactly the same bytes as [item].
  Future<ImagePdfItem?> _findTwin(ImagePdfItem item, int epoch) async {
    for (final other in List<ImagePdfItem>.of(_items)) {
      if (other.size != item.size) continue;
      if (await _sameBytes(File(other.path), File(item.path))) return other;
      if (_disposed || epoch != _epoch) return null;
    }
    return null;
  }

  static Future<bool> _sameBytes(File a, File b) async {
    RandomAccessFile? first;
    RandomAccessFile? second;
    try {
      first = await a.open();
      second = await b.open();
      const chunk = 64 * 1024;
      while (true) {
        final x = await first.read(chunk);
        final y = await second.read(chunk);
        if (x.length != y.length) return false;
        if (x.isEmpty) return true;
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
      }
    } catch (_) {
      return false;
    } finally {
      await first?.close();
      await second?.close();
    }
  }

  /// Removes the picker's own copy once ours exists, when it is in the app's
  /// temporary folder (so it is the plugin's copy and not the user's file).
  Future<void> _deletePickerCopy(File source) async {
    final root = _tempRoot;
    if (root == null) return;
    try {
      final temp = (await root()).path;
      if (p.isWithin(temp, source.path)) await _quietDelete(source);
    } catch (_) {}
  }

  /// Reads and checks the pictures that are waiting, one at a time (a decode
  /// holds a whole photograph in memory, so they are never run side by side).
  Future<void> _pumpAnalysis(int epoch) async {
    if (_analysisRunning) return;
    _analysisRunning = true;
    try {
      while (!_disposed && epoch == _epoch) {
        ImagePdfItem? next;
        for (final item in _items) {
          if (item.status == ImageItemStatus.checking) {
            next = item;
            break;
          }
        }
        if (next == null) break;
        try {
          final analysis = await _executor.analyzeImage(next.path);
          if (_disposed || epoch != _epoch) return;
          if (!_items.contains(next)) continue;
          next.analysis = analysis;
          next.status = ImageItemStatus.ready;
        } on ImagePdfException catch (error) {
          if (_disposed || epoch != _epoch) return;
          if (!_items.contains(next)) continue;
          next.status = ImageItemStatus.failed;
          next.failure = error.kind;
        } catch (_) {
          if (_disposed || epoch != _epoch) return;
          if (!_items.contains(next)) continue;
          next.status = ImageItemStatus.failed;
          next.failure = ImagePdfFailure.corruptSource;
        }
        _invalidateDraft();
        _notify();
      }
    } finally {
      _analysisRunning = false;
    }
    // Pictures added while the last one was being checked.
    if (!_disposed &&
        epoch == _epoch &&
        _items.any((i) => i.status == ImageItemStatus.checking)) {
      unawaited(_pumpAnalysis(epoch));
    }
  }

  bool get _planLocked => _building || _saving;

  void removeItem(String id) {
    if (_planLocked) return;
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    unawaited(_quietDelete(File(item.path)));
    _refreshDuplicateFlags();
    _invalidateDraft();
    _notify();
  }

  void moveItem(int oldIndex, int newIndex) {
    if (_planLocked) return;
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    final target = newIndex.clamp(0, _items.length - 1);
    if (target == oldIndex) return;
    _items.insert(target, _items.removeAt(oldIndex));
    _invalidateDraft();
    _notify();
  }

  /// A flag stays only while another picture with the same bytes remains.
  void _refreshDuplicateFlags() {
    for (final item in _items) {
      if (!item.possibleDuplicate) continue;
      item.possibleDuplicate = _items.any((o) =>
          !identical(o, item) && o.size == item.size && o.possibleDuplicate);
    }
  }

  void clearSelection() {
    if (_planLocked) return;
    _password = '';
    _releaseEverything();
    _notify();
  }

  // ----------------------------------------------------------- make the PDF

  /// Makes the PDF of the pending selection as a draft and returns it, or
  /// returns the existing draft when nothing it was made from has changed.
  /// [allowNewConversion] is asked first when a new draft has to be made (the
  /// plan-limit check); nothing is read when it says no. A failure or cancel
  /// stores nothing and counts nothing.
  Future<DraftOutcome> prepareDraft({
    required String title,
    required ImagePdfTexts coverTexts,
    required Future<bool> Function(String userId) allowNewConversion,
  }) async {
    if (_building || _adding || _saving || _working) {
      return const DraftOutcome.failed(ImagePdfFailure.busy);
    }
    final uid = _userId;
    final store = _store;
    if (uid == null || store == null || _currentUserId() != uid) {
      return const DraftOutcome.failed(ImagePdfFailure.signedOut);
    }
    if (_items.isEmpty) {
      return const DraftOutcome.failed(ImagePdfFailure.noImages);
    }
    for (final item in _items) {
      if (item.status == ImageItemStatus.failed) {
        return DraftOutcome.failed(
            item.failure ?? ImagePdfFailure.corruptSource,
            sourceName: item.displayName);
      }
    }
    if (isChecking) {
      return const DraftOutcome.failed(ImagePdfFailure.imagesNotReady);
    }
    final invalid = _settings.validate();
    if (invalid != null) return DraftOutcome.failed(invalid);
    if (_settings.passwordProtect && !ImagePdfText.isValidPassword(_password)) {
      return const DraftOutcome.failed(ImagePdfFailure.invalidPassword);
    }
    final coverKey = _settings.coverPage
        ? '$title|${coverTexts.coverLines.join('|')}'
        : null;
    final existing = _draft;
    if (existing != null && coverKey == _draftCoverKey) {
      return DraftOutcome.done(existing);
    }
    _invalidateDraft();

    final epoch = _epoch;
    final token = ImagePdfCancelToken();
    _token = token;
    _building = true;
    _notify();
    File? work;
    var keepWork = false;
    // Snapshot: the selection is locked while building, but the job must not
    // change underneath the worker.
    final specs = <ImageSpec>[
      for (final item in _items) item.spec!,
    ];
    try {
      if (!await allowNewConversion(uid)) {
        return const DraftOutcome.failed(ImagePdfFailure.quotaBlocked);
      }
      if (_disposed || epoch != _epoch) {
        return const DraftOutcome.failed(ImagePdfFailure.accountChanged);
      }
      if (token.isCancelled) {
        return const DraftOutcome.failed(ImagePdfFailure.cancelled);
      }
      Uint8List? font;
      if (_needsUnicodeFont(coverTexts)) {
        font = await _loadUnicodeFont?.call();
        if (_disposed || epoch != _epoch) {
          return const DraftOutcome.failed(ImagePdfFailure.accountChanged);
        }
        if (font == null) {
          return const DraftOutcome.failed(ImagePdfFailure.buildFailed);
        }
      }
      work = await store.newWorkFile();
      final builtAt = _clock();
      final result = await _executor.build(
        ImagePdfBuildJob(
          images: specs,
          settings: _settings,
          outputPath: work.path,
          timestamp: builtAt,
          password: _settings.passwordProtect ? _password : null,
          texts: coverTexts,
          unicodeFont: font,
        ),
        token,
      );
      if (_disposed || epoch != _epoch || _currentUserId() != uid) {
        return const DraftOutcome.failed(ImagePdfFailure.accountChanged);
      }
      final made = ImagePdfDraft(
        file: work,
        pageCount: result.pageCount,
        imageCount: result.imageCount,
        size: result.size,
        lowResolutionImages: result.lowResolutionImages,
        encrypted: result.encrypted,
        builtAt: builtAt,
      );
      _draft = made;
      _draftTitle = title;
      _draftCoverKey = coverKey;
      keepWork = true;
      return DraftOutcome.done(made);
    } on ImagePdfException catch (error) {
      if (_disposed || epoch != _epoch) {
        return const DraftOutcome.failed(ImagePdfFailure.accountChanged);
      }
      String? name;
      if (error.sourceId != null) {
        for (final item in _items) {
          if (item.id == error.sourceId) name = item.displayName;
        }
      }
      return DraftOutcome.failed(error.kind, sourceName: name);
    } catch (_) {
      if (_disposed || epoch != _epoch) {
        return const DraftOutcome.failed(ImagePdfFailure.accountChanged);
      }
      return const DraftOutcome.failed(ImagePdfFailure.buildFailed);
    } finally {
      if (work != null && !keepWork) await store.releaseWorkFile(work);
      _building = false;
      if (identical(_token, token)) _token = null;
      _notify();
    }
  }

  bool _needsUnicodeFont(ImagePdfTexts texts) {
    final candidates = <String>[
      if (_settings.watermark) _settings.effectiveWatermark,
      if (_settings.coverPage) ...<String>[
        texts.coverTitle,
        ...texts.coverLines
      ],
    ];
    return candidates.any(ImagePdfText.needsUnicodeFont);
  }

  /// Stops a running conversion. Nothing is stored or counted.
  void cancelBuild() => _token?.cancel();

  /// Throws the draft away without saving.
  void discardDraft() {
    if (_building || _saving) return;
    _invalidateDraft();
    _notify();
  }

  /// Stores the current draft as a PDF of the signed-in account under [name],
  /// then clears the selection. The stored file is the draft itself, copied and
  /// read back before it is listed; the usage is counted once, after that.
  Future<SaveOutcome> saveDraft({String? name}) async {
    if (_saving || _building || _adding || _working) {
      return const SaveOutcome.failed(ImagePdfFailure.busy);
    }
    final uid = _userId;
    final store = _store;
    final draft = _draft;
    if (uid == null || store == null || _currentUserId() != uid) {
      return const SaveOutcome.failed(ImagePdfFailure.signedOut);
    }
    if (draft == null) {
      return const SaveOutcome.failed(ImagePdfFailure.noImages);
    }
    final epoch = _epoch;
    _saving = true;
    _notify();
    try {
      final base =
          ImagePdfNaming.sanitizeDisplayName(name ?? _draftTitle ?? '') ??
              ImagePdfNaming.defaultName(_clock());
      final stored = await store.add(
        source: draft.file,
        name: base,
        expected: ImagePdfFileInfo(
            size: draft.size,
            pageCount: draft.pageCount,
            encrypted: draft.encrypted),
        pageCount: draft.pageCount,
        imageCount: draft.imageCount,
      );
      // The PDF is stored for the account that made it; count it exactly once.
      try {
        await _usage.recordConversion(uid);
      } catch (_) {}
      if (_disposed || epoch != _epoch) {
        return const SaveOutcome.failed(ImagePdfFailure.accountChanged);
      }
      _password = '';
      _releaseEverything();
      await refresh();
      return SaveOutcome.done(stored);
    } on ImagePdfException catch (error) {
      if (_disposed || epoch != _epoch) {
        return const SaveOutcome.failed(ImagePdfFailure.accountChanged);
      }
      return SaveOutcome.failed(error.kind);
    } catch (_) {
      if (_disposed || epoch != _epoch) {
        return const SaveOutcome.failed(ImagePdfFailure.accountChanged);
      }
      return const SaveOutcome.failed(ImagePdfFailure.writeFailed);
    } finally {
      _saving = false;
      _notify();
    }
  }

  // ---------------------------------------------------------------- library

  void enterSelectionMode() {
    _selectionMode = true;
    _selected.clear();
    _notify();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selected.clear();
    _notify();
  }

  void toggleSelection(String id) {
    if (!_documents.any((d) => d.id == id)) return;
    if (!_selected.remove(id)) _selected.add(id);
    _notify();
  }

  ImagePdfDocument? documentById(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The stored file of [document] when it is the complete file that was saved,
  /// otherwise null (the caller reports it missing).
  Future<File?> openableFile(ImagePdfDocument document) async {
    final store = _store;
    if (store == null || _userId == null) return null;
    final epoch = _epoch;
    final intact = await store.isIntact(document);
    if (_disposed || epoch != _epoch) return null;
    if (!intact) {
      if (!_missing.contains(document.id)) {
        _missing = <String>{..._missing, document.id};
        _notify();
      }
      return null;
    }
    return store.fileOf(document);
  }

  /// The draft's file when it is still the current draft, for the PDF viewer.
  File? get draftFile => _draft?.file;

  /// Renames [id]. Returns null on success or the reason it failed.
  Future<ImagePdfFailure?> rename(String id, String newName) async {
    final store = _store;
    if (store == null) return ImagePdfFailure.signedOut;
    if (_working || _building || _saving) return ImagePdfFailure.busy;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      await store.rename(id, newName);
      if (_disposed || epoch != _epoch) return ImagePdfFailure.accountChanged;
      await refresh();
      return null;
    } on ImagePdfException catch (error) {
      return error.kind;
    } catch (_) {
      return ImagePdfFailure.writeFailed;
    } finally {
      _working = false;
      _notify();
    }
  }

  /// Deletes the documents with these ids and nothing else. Returns the ids
  /// that could not be removed.
  Future<List<String>> delete(Iterable<String> ids) async {
    final store = _store;
    final wanted = ids.toList();
    if (store == null || _working || _building || _saving) return wanted;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      final outcome = await store.delete(wanted);
      if (_disposed || epoch != _epoch) return const <String>[];
      _selected.removeAll(outcome.deleted);
      await refresh();
      return <String>[...outcome.failed, ...outcome.notFound];
    } catch (_) {
      return wanted;
    } finally {
      _working = false;
      _notify();
    }
  }

  /// Copies the chosen documents, under their titles, for the share sheet.
  Future<ImagePdfSharePreparation> prepareShare(Iterable<String> ids) async {
    final store = _store;
    const nothing =
        ImagePdfSharePreparation(paths: <String>[], unavailable: <String>[]);
    if (store == null) return nothing;
    final epoch = _epoch;
    final files = <({ImagePdfDocument document, File file})>[];
    final unavailable = <String>[];
    for (final id in ids) {
      final document = documentById(id);
      if (document == null) {
        unavailable.add(id);
        continue;
      }
      if (await store.isIntact(document)) {
        files.add((document: document, file: store.fileOf(document)));
      } else {
        unavailable.add(id);
        _missing = <String>{..._missing, id};
      }
    }
    if (_disposed || epoch != _epoch) return nothing;
    _notify();
    if (unavailable.isNotEmpty || files.isEmpty) {
      return ImagePdfSharePreparation(
          paths: const <String>[], unavailable: unavailable);
    }
    final paths = await _sharePreparer.prepare(files);
    if (_disposed || epoch != _epoch) return nothing;
    return ImagePdfSharePreparation(
        paths: paths, unavailable: const <String>[]);
  }

  /// Exports one document to Downloads (Android) or the Files app (iPhone).
  /// Throws an [ImagePdfException] when it did not work.
  Future<ScannerExportResult> exportDocument(String id) async {
    final store = _store;
    final document = documentById(id);
    if (store == null || document == null) {
      throw const ImagePdfException(ImagePdfFailure.notFound);
    }
    if (_working || _building || _saving) {
      throw const ImagePdfException(ImagePdfFailure.busy);
    }
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      if (!await store.isIntact(document)) {
        _missing = <String>{..._missing, id};
        throw const ImagePdfException(ImagePdfFailure.fileMissing);
      }
      if (_disposed || epoch != _epoch) {
        throw const ImagePdfException(ImagePdfFailure.accountChanged);
      }
      return await _exporter.export(
          document.exportFileName, store.fileOf(document));
    } finally {
      _working = false;
      _notify();
    }
  }

  static Future<void> _quietDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
