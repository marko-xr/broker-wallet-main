import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_engine.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/scanner/scanner_share_preparer.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_recorder.dart';

/// One verified page of a scan waiting for the user's review.
class DraftPage {
  const DraftPage(this.staged, this.inspected);

  final StagedScanFile staged;
  final InspectedScanFile inspected;

  File get file => staged.file;
}

/// A scan that has been read and verified but not yet stored: what the review
/// screen shows. It belongs to one account.
class ScanDraft {
  const ScanDraft({
    required this.id,
    required this.userId,
    required this.epoch,
    required this.format,
    required this.scanType,
    required this.pages,
  });

  final String id;
  final String userId;
  final int epoch;
  final ExportFormat format;
  final ScanMode scanType;
  final List<DraftPage> pages;

  /// The real number of pages: a PDF's own page count, or the image files.
  int get pageCount => format == ExportFormat.pdf
      ? pages.first.inspected.pageCount
      : pages.length;

  int get totalBytes =>
      pages.fold<int>(0, (sum, page) => sum + page.inspected.size);
}

/// The result of asking the scanner for a scan.
class ScanStartResult {
  const ScanStartResult.draft(ScanDraft this.draft)
      : cancelled = false,
        failure = null;
  const ScanStartResult.cancelled()
      : draft = null,
        cancelled = true,
        failure = null;
  const ScanStartResult.failed(ScannerFailure this.failure)
      : draft = null,
        cancelled = false;

  final ScanDraft? draft;
  final bool cancelled;
  final ScannerFailure? failure;
}

/// The result of saving a reviewed scan.
class ScanSaveResult {
  const ScanSaveResult.saved(this.documents) : failure = null;
  const ScanSaveResult.failed(ScannerFailure this.failure)
      : documents = const [];

  final List<ScannerDocument> documents;
  final ScannerFailure? failure;

  bool get isSaved => failure == null;
}

/// Files ready to hand to the share sheet, or the documents that could not be
/// shared because their stored file is gone or damaged.
class SharePreparation {
  const SharePreparation({required this.paths, required this.unavailable});

  final List<String> paths;
  final List<String> unavailable;

  bool get isShareable => unavailable.isEmpty && paths.isNotEmpty;
}

/// The Scanner screen's logic: the signed-in account's documents, the scan →
/// review → save pipeline, and the library actions. It owns no widgets.
///
/// Every asynchronous step checks that the screen is still alive and that the
/// signed-in account is still the one the step started for; a result for a
/// previous account is dropped, never shown. Only one scan or save runs at a
/// time, so a double tap does nothing.
class ScannerViewModel extends ChangeNotifier {
  ScannerViewModel({
    required ScannerEngine engine,
    required Future<Directory> Function() baseDirectory,
    required ScanSourceStager stager,
    required ScanFileInspector inspector,
    required ScannerUsageRecorder usage,
    required ScannerSharePreparer sharePreparer,
    required ScannerExporter exporter,
    required ScannerBackupGuard backup,
    required String? Function() currentUserId,
    required Stream<String?> userIdChanges,
    Future<int> Function()? legacyDocumentCount,
    ScannerFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _engine = engine,
        _baseDirectory = baseDirectory,
        _stager = stager,
        _inspector = inspector,
        _usage = usage,
        _sharePreparer = sharePreparer,
        _exporter = exporter,
        _backup = backup,
        _currentUserId = currentUserId,
        _userIdChanges = userIdChanges,
        _legacyDocumentCount = legacyDocumentCount,
        _copier = copier,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator;

  final ScannerEngine _engine;
  final Future<Directory> Function() _baseDirectory;
  final ScanSourceStager _stager;
  final ScanFileInspector _inspector;
  final ScannerUsageRecorder _usage;
  final ScannerSharePreparer _sharePreparer;
  final ScannerExporter _exporter;
  final ScannerBackupGuard _backup;
  final String? Function() _currentUserId;
  final Stream<String?> _userIdChanges;
  final Future<int> Function()? _legacyDocumentCount;
  final ScannerFileCopier? _copier;
  final DateTime Function() _clock;
  final String Function()? _idGenerator;

  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  ScannerDocumentStore? _store;

  List<ScannerDocument> _documents = const <ScannerDocument>[];
  Set<String> _missing = const <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _scanning = false;
  bool _saving = false;
  bool _working = false;
  ScanDraft? _draft;
  int _legacyCount = 0;

  // Settings. The scanner decides crop, rotation, retake, filters and image
  // quality itself in its own screen; these are the options the Scanner can
  // really pass on: the kind of output and the page limit. The mode is a label.
  ScanMode _scanMode = ScanMode.document;
  ExportFormat _exportFormat = ExportFormat.pdf;
  int _maxPages = defaultMaxPages;

  static const int defaultMaxPages = 5;
  static const List<int> maxPageChoices = <int>[1, 5, 10, 20];

  List<ScannerDocument> get documents => _documents;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;
  bool get isScanning => _scanning;
  bool get isSaving => _saving;

  /// A library action (rename, delete, share, export) is running.
  bool get isWorking => _working;
  bool get isBusy => _scanning || _saving || _working;
  ScanDraft? get draft => _draft;
  bool get isSelectionMode => _selectionMode;
  int get legacyDocumentCount => _legacyCount;
  int get maxPages => _maxPages;
  String? get userId => _userId;

  bool isMissing(String id) => _missing.contains(id);
  bool isSelected(String id) => _selected.contains(id);
  int get selectedCount => _selected.length;

  /// The selected documents, resolved against the current list, so a change of
  /// order or an earlier delete can never point an action at another document.
  List<ScannerDocument> get selectedDocuments => <ScannerDocument>[
        for (final d in _documents)
          if (_selected.contains(d.id)) d
      ];

  ScanMode get scanMode => _scanMode;
  ExportFormat get exportFormat => _exportFormat;

  set maxPages(int value) {
    _maxPages = value.clamp(1, 50);
    _notify();
  }

  void selectScanMode(ScanMode mode) {
    _scanMode = mode;
    _notify();
  }

  void selectExportFormat(ExportFormat format) {
    _exportFormat = format;
    _notify();
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
    _disposed = true;
    _subscription?.cancel();
    final draft = _draft;
    _draft = null;
    if (draft != null && !_saving) unawaited(_cleanupDraft(draft));
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _switchTo(String? uid) async {
    if (_disposed) return;
    if (uid == _userId && (uid == null || _store != null)) return;
    _epoch++;
    final epoch = _epoch;
    final stale = _draft;
    if (stale != null && !_saving) {
      _draft = null;
      unawaited(_cleanupDraft(stale));
    }
    _userId = uid;
    _store = null;
    _documents = const <ScannerDocument>[];
    _missing = const <String>{};
    _selected.clear();
    _selectionMode = false;
    _loadFailed = false;
    _loading = uid != null;
    _notify();
    if (uid == null) return;
    try {
      final base = await _baseDirectory();
      // Scans stay out of cloud and device backup (iPhone needs the folder
      // marked; Android's rules name it). Best effort and never fatal.
      try {
        final scannerRoot = Directory(p.join(base.path, 'scanner'));
        await scannerRoot.create(recursive: true);
        await _backup.exclude(scannerRoot.path);
      } catch (_) {}
      if (_disposed || epoch != _epoch) return;
      _store = ScannerDocumentStore(
        accountDir: ScannerDocumentStore.accountDirectory(base, uid),
        userId: uid,
        inspector: _inspector,
        copier: _copier,
        clock: _clock,
        idGenerator: _idGenerator,
      );
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

  // --------------------------------------------------------------- scanning

  String get suggestedName => ScannerNaming.defaultName(scanMode, _clock());

  /// Opens the scanner and verifies what it returns. [allowNewScan] is asked
  /// first (the plan-limit check); the scanner is not opened when it says no.
  Future<ScanStartResult> startScan({
    required Future<bool> Function(String userId) allowNewScan,
  }) async {
    if (_scanning || _saving || _draft != null) {
      return const ScanStartResult.failed(ScannerFailure.busy);
    }
    final uid = _userId;
    if (uid == null || _store == null || _currentUserId() != uid) {
      return const ScanStartResult.failed(ScannerFailure.signedOut);
    }
    final epoch = _epoch;
    _scanning = true;
    _notify();
    final operationId = const Uuid().v4();
    final staged = <StagedScanFile>[];
    try {
      if (!await allowNewScan(uid)) {
        return const ScanStartResult.failed(ScannerFailure.quotaBlocked);
      }
      if (_disposed || epoch != _epoch) {
        return const ScanStartResult.failed(ScannerFailure.accountChanged);
      }
      final format = exportFormat;
      final raw = await _engine.scan(
        format: format,
        maxPages: _maxPages,
      );
      final output = ScanResultParser.parse(raw, expected: format);
      if (output == null) return const ScanStartResult.cancelled();

      final sources = switch (output) {
        ScanPdfOutput(:final source) => <ScanSource>[source],
        ScanImagesOutput(:final sources) => sources,
      };
      final pages = <DraftPage>[];
      for (var i = 0; i < sources.length; i++) {
        final file =
            await _stager.stage(sources[i], operationId: operationId, index: i);
        staged.add(file);
        if (file.isScannerOutput) {
          try {
            await _backup.exclude(file.file.path);
          } catch (_) {}
        }
        final inspected = await _inspector.inspect(file.file);
        if (inspected.kind.format != format) {
          throw const ScannerException(ScannerFailure.wrongFormat, 'file');
        }
        pages.add(DraftPage(file, inspected));
      }
      if (_disposed || epoch != _epoch || _currentUserId() != uid) {
        await _releaseAll(staged, operationId);
        return const ScanStartResult.failed(ScannerFailure.accountChanged);
      }
      final draft = ScanDraft(
        id: operationId,
        userId: uid,
        epoch: epoch,
        format: format,
        scanType: scanMode,
        pages: pages,
      );
      _draft = draft;
      return ScanStartResult.draft(draft);
    } on ScannerException catch (error) {
      await _releaseAll(staged, operationId);
      return ScanStartResult.failed(error.kind);
    } catch (_) {
      await _releaseAll(staged, operationId);
      return const ScanStartResult.failed(ScannerFailure.corruptOutput);
    } finally {
      _scanning = false;
      _notify();
    }
  }

  /// Stores the reviewed scan under [name]. On failure the draft is kept, so
  /// the same scan can be saved again; on success the scanner's temporary files
  /// are removed and the usage is recorded once.
  Future<ScanSaveResult> saveDraft(String? name) async {
    final draft = _draft;
    if (draft == null) {
      return const ScanSaveResult.failed(ScannerFailure.notFound);
    }
    if (_saving) return const ScanSaveResult.failed(ScannerFailure.busy);
    final store = _store;
    if (store == null ||
        _userId != draft.userId ||
        draft.epoch != _epoch ||
        _currentUserId() != draft.userId) {
      await discardDraft();
      return const ScanSaveResult.failed(ScannerFailure.accountChanged);
    }
    _saving = true;
    _notify();
    final epoch = _epoch;
    final base = ScannerNaming.sanitizeDisplayName(name ?? '') ??
        ScannerNaming.defaultName(draft.scanType, _clock());
    final batchId = const Uuid().v4();
    final items = <ScannerNewDocument>[
      for (var i = 0; i < draft.pages.length; i++)
        ScannerNewDocument(
          source: draft.pages[i].file,
          inspected: draft.pages[i].inspected,
          name: draft.pages.length == 1 ? base : '${base}_page_${i + 1}',
          scanType: draft.scanType,
          batchId: draft.format == ExportFormat.images ? batchId : null,
          batchIndex: i,
        ),
    ];
    try {
      final saved = await store.add(items);
      // The scan is stored for this account, whatever happened meanwhile.
      try {
        await _usage.recordScan(draft.userId);
      } catch (_) {}
      if (identical(_draft, draft)) _draft = null;
      await _cleanupDraft(draft);
      if (!_disposed && epoch == _epoch) {
        await refresh();
      }
      return ScanSaveResult.saved(saved);
    } on ScannerException catch (error) {
      return ScanSaveResult.failed(error.kind);
    } catch (_) {
      return const ScanSaveResult.failed(ScannerFailure.writeFailed);
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// Drops the scan under review and removes its temporary files.
  Future<void> discardDraft() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    _draft = null;
    _notify();
    await _cleanupDraft(draft);
  }

  Future<void> _cleanupDraft(ScanDraft draft) =>
      _releaseAll(draft.pages.map((p) => p.staged), draft.id);

  Future<void> _releaseAll(
      Iterable<StagedScanFile> files, String operationId) async {
    for (final file in files) {
      await _stager.release(file);
    }
    await _stager.releaseOperation(operationId);
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

  ScannerDocument? documentById(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The stored file of [document] when it is the complete file that was saved,
  /// otherwise null (the caller reports it missing).
  Future<File?> openableFile(ScannerDocument document) async {
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

  /// Renames [id]. Returns null on success or the reason it failed.
  Future<ScannerFailure?> rename(String id, String newName) async {
    final store = _store;
    if (store == null) return ScannerFailure.signedOut;
    if (_working) return ScannerFailure.busy;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      await store.rename(id, newName);
      if (_disposed || epoch != _epoch) return ScannerFailure.accountChanged;
      await refresh();
      return null;
    } on ScannerException catch (error) {
      return error.kind;
    } catch (_) {
      return ScannerFailure.writeFailed;
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
    if (store == null || _working) return wanted;
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
  Future<SharePreparation> prepareShare(Iterable<String> ids) async {
    final store = _store;
    if (store == null) {
      return const SharePreparation(paths: <String>[], unavailable: <String>[]);
    }
    final epoch = _epoch;
    final files = <({ScannerDocument document, File file})>[];
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
    if (_disposed || epoch != _epoch) {
      return const SharePreparation(paths: <String>[], unavailable: <String>[]);
    }
    _notify();
    if (unavailable.isNotEmpty || files.isEmpty) {
      return SharePreparation(
          paths: const <String>[], unavailable: unavailable);
    }
    final paths = await _sharePreparer.prepare(files);
    return SharePreparation(paths: paths, unavailable: const <String>[]);
  }

  /// Exports one document to Downloads (Android) or the Files app (iPhone).
  /// Throws a [ScannerException] when it did not work.
  Future<ScannerExportResult> exportDocument(String id) async {
    final store = _store;
    final document = documentById(id);
    if (store == null || document == null) {
      throw const ScannerException(ScannerFailure.notFound);
    }
    if (_working) throw const ScannerException(ScannerFailure.busy);
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      if (!await store.isIntact(document)) {
        _missing = <String>{..._missing, id};
        throw const ScannerException(ScannerFailure.fileMissing);
      }
      if (_disposed || epoch != _epoch) {
        throw const ScannerException(ScannerFailure.accountChanged);
      }
      return await _exporter.export(document, store.fileOf(document));
    } finally {
      _working = false;
      _notify();
    }
  }
}
