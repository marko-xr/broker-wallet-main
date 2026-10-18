import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_platform.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_plan.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

/// A picked file that was not added, and why.
class RejectedPdf {
  const RejectedPdf(this.name, this.failure);

  final String name;
  final CombinePdfFailure failure;
}

/// What picking and checking files did.
class AddFilesOutcome {
  const AddFilesOutcome({
    this.added = 0,
    this.duplicates = 0,
    this.rejected = const <RejectedPdf>[],
    this.cancelled = false,
    this.failure,
  });

  const AddFilesOutcome.failed(CombinePdfFailure this.failure)
      : added = 0,
        duplicates = 0,
        rejected = const <RejectedPdf>[],
        cancelled = false;

  final int added;

  /// Files that were already in the selection (not added a second time).
  final int duplicates;
  final List<RejectedPdf> rejected;

  /// The picker was closed without a choice.
  final bool cancelled;

  /// The whole action could not run (signed out, busy, account changed).
  final CombinePdfFailure? failure;
}

/// The result of a combine.
class CombineOutcome {
  const CombineOutcome.done(CombinedPdf this.document)
      : failure = null,
        sourceName = null;
  const CombineOutcome.failed(CombinePdfFailure this.failure, {this.sourceName})
      : document = null;

  final CombinedPdf? document;
  final CombinePdfFailure? failure;

  /// The selected file a failure is about, when it is about one.
  final String? sourceName;

  bool get isDone => failure == null;
}

/// Files ready to hand to the share sheet, or the documents that could not be
/// shared because their stored file is gone or damaged.
class CombineSharePreparation {
  const CombineSharePreparation(
      {required this.paths, required this.unavailable});

  final List<String> paths;
  final List<String> unavailable;

  bool get isShareable => unavailable.isEmpty && paths.isNotEmpty;
}

/// The Combine PDFs screen's logic: the signed-in account's combined documents,
/// the pending selection (files, page ranges, order, rotation) and the combine
/// itself. It owns no widgets.
///
/// Every asynchronous step checks that the screen is still alive and that the
/// signed-in account is still the one the step started for; a result for a
/// previous account is dropped, never shown or stored. Only one combine, pick
/// or library action runs at a time, so a double tap does nothing.
class CombinePdfViewModel extends ChangeNotifier {
  CombinePdfViewModel({
    required CombineExecutor executor,
    required Future<Directory> Function() baseDirectory,
    required CombinePdfPicker picker,
    required CombineUsageRecorder usage,
    required CombineSharePreparer sharePreparer,
    required CombinePdfExporter exporter,
    required ScannerBackupGuard backup,
    required String? Function() currentUserId,
    required Stream<String?> userIdChanges,
    Future<int> Function()? legacyDocumentCount,
    CombineFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _executor = executor,
        _baseDirectory = baseDirectory,
        _picker = picker,
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

  final CombineExecutor _executor;
  final Future<Directory> Function() _baseDirectory;
  final CombinePdfPicker _picker;
  final CombineUsageRecorder _usage;
  final CombineSharePreparer _sharePreparer;
  final CombinePdfExporter _exporter;
  final ScannerBackupGuard _backup;
  final String? Function() _currentUserId;
  final Stream<String?> _userIdChanges;
  final Future<int> Function()? _legacyDocumentCount;
  final CombineFileCopier? _copier;
  final DateTime Function() _clock;
  final String Function()? _idGenerator;

  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  CombinePdfStore? _store;

  final CombinePlan _plan = CombinePlan();
  List<CombinedPdf> _documents = const <CombinedPdf>[];
  Set<String> _missing = const <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _checking = false;
  bool _merging = false;
  bool _working = false;
  int _legacyCount = 0;
  CombineCancelToken? _token;

  CombinePlan get plan => _plan;
  List<CombinedPdf> get documents => _documents;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;

  /// Files are being picked or checked.
  bool get isChecking => _checking;

  /// A combine is running.
  bool get isMerging => _merging;

  /// A library action (rename, delete, share, export) is running.
  bool get isWorking => _working;
  bool get isBusy => _checking || _merging || _working;
  bool get isSelectionMode => _selectionMode;
  int get legacyDocumentCount => _legacyCount;
  String? get userId => _userId;

  bool isMissing(String id) => _missing.contains(id);
  bool isSelected(String id) => _selected.contains(id);
  int get selectedCount => _selected.length;

  List<CombinedPdf> get selectedDocuments => <CombinedPdf>[
        for (final d in _documents)
          if (_selected.contains(d.id)) d
      ];

  /// The title a new combined PDF gets unless the user types one.
  String get suggestedName => CombineNaming.defaultName(_clock());

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
    if (!_plan.isEmpty) unawaited(_picker.clearPickedCopies());
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
    _token?.cancel();
    if (!_plan.isEmpty) {
      _plan.clear();
      unawaited(_picker.clearPickedCopies());
    }
    _userId = uid;
    _store = null;
    _documents = const <CombinedPdf>[];
    _missing = const <String>{};
    _selected.clear();
    _selectionMode = false;
    _loadFailed = false;
    _loading = uid != null;
    _notify();
    if (uid == null) return;
    try {
      final base = await _baseDirectory();
      // Combined PDFs stay out of cloud and device backup (iPhone needs the
      // folder marked; Android's rules name it). Best effort and never fatal.
      try {
        final root =
            Directory(p.join(base.path, CombinePdfStore.rootFolderName));
        await root.create(recursive: true);
        await _backup.exclude(root.path);
      } catch (_) {}
      if (_disposed || epoch != _epoch) return;
      _store = CombinePdfStore(
        accountDir: CombinePdfStore.accountDirectory(base, uid),
        userId: uid,
        verify: (file) => _executor.analyze(file.path,
            maxBytes: CombineLimits.maxTotalSourceBytes * 2),
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

  // ---------------------------------------------------------- the selection

  /// Opens the system picker and adds the chosen PDFs.
  Future<AddFilesOutcome> pickFiles() async {
    final early = _canStartSelection();
    if (early != null) return AddFilesOutcome.failed(early);
    final epoch = _epoch;
    _checking = true;
    _notify();
    try {
      final picked = await _picker.pick();
      if (_disposed || epoch != _epoch) {
        return const AddFilesOutcome.failed(CombinePdfFailure.accountChanged);
      }
      if (picked == null) return const AddFilesOutcome(cancelled: true);
      return await _addPicked(picked, epoch);
    } catch (_) {
      return const AddFilesOutcome.failed(CombinePdfFailure.missingSource);
    } finally {
      _checking = false;
      _notify();
    }
  }

  /// Adds already-picked files (the picker's own entry point, and tests').
  Future<AddFilesOutcome> addPickedFiles(List<PickedPdf> picked) async {
    final early = _canStartSelection();
    if (early != null) return AddFilesOutcome.failed(early);
    final epoch = _epoch;
    _checking = true;
    _notify();
    try {
      return await _addPicked(picked, epoch);
    } finally {
      _checking = false;
      _notify();
    }
  }

  CombinePdfFailure? _canStartSelection() {
    if (_checking || _merging || _working) return CombinePdfFailure.busy;
    final uid = _userId;
    if (uid == null || _store == null || _currentUserId() != uid) {
      return CombinePdfFailure.signedOut;
    }
    return null;
  }

  Future<AddFilesOutcome> _addPicked(List<PickedPdf> picked, int epoch) async {
    var added = 0;
    var duplicates = 0;
    final rejected = <RejectedPdf>[];
    for (final file in picked) {
      if (file.path.isEmpty) {
        rejected.add(RejectedPdf(file.name, CombinePdfFailure.missingSource));
        continue;
      }
      if (_plan.containsPath(file.path)) {
        duplicates++;
        continue;
      }
      if (_plan.sources.length >= CombineLimits.maxSources) {
        rejected
            .add(RejectedPdf(file.name, CombinePdfFailure.selectionTooLarge));
        continue;
      }
      try {
        final analysis = await _executor.analyze(file.path);
        if (_disposed || epoch != _epoch) {
          return const AddFilesOutcome.failed(CombinePdfFailure.accountChanged);
        }
        if (analysis.features.hasSignatures) {
          rejected.add(RejectedPdf(file.name, CombinePdfFailure.signedSource));
          continue;
        }
        if (_plan.totalSourceBytes + analysis.size >
            CombineLimits.maxTotalSourceBytes) {
          rejected
              .add(RejectedPdf(file.name, CombinePdfFailure.selectionTooLarge));
          continue;
        }
        final ok = _plan.addSource(CombineSource(
          id: const Uuid().v4(),
          path: file.path,
          displayName: file.name,
          size: analysis.size,
          pageCount: analysis.pageCount,
          features: analysis.features,
        ));
        if (ok) {
          added++;
        } else {
          duplicates++;
        }
        _notify();
      } on CombinePdfException catch (error) {
        if (_disposed || epoch != _epoch) {
          return const AddFilesOutcome.failed(CombinePdfFailure.accountChanged);
        }
        rejected.add(RejectedPdf(file.name, error.kind));
      } catch (_) {
        if (_disposed || epoch != _epoch) {
          return const AddFilesOutcome.failed(CombinePdfFailure.accountChanged);
        }
        rejected.add(RejectedPdf(file.name, CombinePdfFailure.corruptSource));
      }
    }
    return AddFilesOutcome(
        added: added, duplicates: duplicates, rejected: rejected);
  }

  bool get _planLocked => _merging || _checking;

  void removeSource(String sourceId) {
    if (_planLocked) return;
    _plan.removeSource(sourceId);
    if (_plan.isEmpty) unawaited(_picker.clearPickedCopies());
    _notify();
  }

  void moveSource(int oldIndex, int newIndex) {
    if (_planLocked) return;
    _plan.moveSource(oldIndex, newIndex);
    _notify();
  }

  void selectRange(String sourceId, int from, int to) {
    if (_planLocked) return;
    _plan.selectRange(sourceId, from, to);
    _notify();
  }

  void useAllPages(String sourceId) {
    if (_planLocked) return;
    _plan.useAllPages(sourceId);
    _notify();
  }

  void movePage(int oldIndex, int newIndex) {
    if (_planLocked) return;
    _plan.movePage(oldIndex, newIndex);
    _notify();
  }

  void removePage(int index) {
    if (_planLocked) return;
    _plan.removePage(index);
    _notify();
  }

  void rotatePage(int index, int quarterTurns) {
    if (_planLocked) return;
    _plan.rotatePage(index, quarterTurns);
    _notify();
  }

  void clearSelection() {
    if (_planLocked) return;
    _plan.clear();
    unawaited(_picker.clearPickedCopies());
    _notify();
  }

  // ---------------------------------------------------------------- combine

  /// Combines the pending selection into one PDF titled [name].
  /// [allowNewCombine] is asked first (the plan-limit check); nothing is read
  /// when it says no. A failure or cancel stores nothing and counts nothing.
  Future<CombineOutcome> combine({
    String? name,
    required Future<bool> Function(String userId) allowNewCombine,
  }) async {
    if (_merging || _checking || _working) {
      return const CombineOutcome.failed(CombinePdfFailure.busy);
    }
    final uid = _userId;
    final store = _store;
    if (uid == null || store == null || _currentUserId() != uid) {
      return const CombineOutcome.failed(CombinePdfFailure.signedOut);
    }
    final blocker = _plan.blocker;
    if (blocker != null) {
      final emptyId = _plan.firstEmptySourceId;
      return CombineOutcome.failed(blocker,
          sourceName:
              blocker == CombinePdfFailure.fileHasNoPages && emptyId != null
                  ? _plan.sourceById(emptyId)?.displayName
                  : null);
    }
    final epoch = _epoch;
    final token = CombineCancelToken();
    _token = token;
    _merging = true;
    _notify();
    File? work;
    // Snapshot: the plan is locked while merging, but the job must not change.
    final sources = _plan.sources;
    final pages = _plan.pages;
    try {
      if (!await allowNewCombine(uid)) {
        return const CombineOutcome.failed(CombinePdfFailure.quotaBlocked);
      }
      if (_disposed || epoch != _epoch) {
        return const CombineOutcome.failed(CombinePdfFailure.accountChanged);
      }
      if (token.isCancelled) {
        return const CombineOutcome.failed(CombinePdfFailure.cancelled);
      }
      work = await store.newWorkFile();
      final result = await _executor.merge(
        CombineMergeJob(sources: sources, pages: pages, outputPath: work.path),
        token,
      );
      if (_disposed || epoch != _epoch || _currentUserId() != uid) {
        return const CombineOutcome.failed(CombinePdfFailure.accountChanged);
      }
      final base = CombineNaming.sanitizeDisplayName(name ?? '') ??
          CombineNaming.defaultName(_clock());
      final stored = await store.add(
        source: work,
        name: base,
        expected: CombineAnalysis(
            size: result.size,
            pageCount: result.pageCount,
            features: const CombineFeatures()),
      );
      // The combined PDF is stored for this account; count it exactly once.
      try {
        await _usage.recordCombine(uid);
      } catch (_) {}
      if (!_disposed && epoch == _epoch) {
        _plan.clear();
        unawaited(_picker.clearPickedCopies());
        await refresh();
      }
      return CombineOutcome.done(stored);
    } on CombinePdfException catch (error) {
      if (_disposed || epoch != _epoch) {
        return const CombineOutcome.failed(CombinePdfFailure.accountChanged);
      }
      return CombineOutcome.failed(error.kind,
          sourceName: error.sourceId == null
              ? null
              : _plan.sourceById(error.sourceId!)?.displayName);
    } catch (_) {
      if (_disposed || epoch != _epoch) {
        return const CombineOutcome.failed(CombinePdfFailure.accountChanged);
      }
      return const CombineOutcome.failed(CombinePdfFailure.mergeFailed);
    } finally {
      if (work != null) await store.releaseWorkFile(work);
      _merging = false;
      if (identical(_token, token)) _token = null;
      _notify();
    }
  }

  /// Stops a running combine. Nothing is stored or counted.
  void cancelCombine() => _token?.cancel();

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

  CombinedPdf? documentById(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The stored file of [document] when it is the complete file that was saved,
  /// otherwise null (the caller reports it missing).
  Future<File?> openableFile(CombinedPdf document) async {
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
  Future<CombinePdfFailure?> rename(String id, String newName) async {
    final store = _store;
    if (store == null) return CombinePdfFailure.signedOut;
    if (_working || _merging) return CombinePdfFailure.busy;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      await store.rename(id, newName);
      if (_disposed || epoch != _epoch) return CombinePdfFailure.accountChanged;
      await refresh();
      return null;
    } on CombinePdfException catch (error) {
      return error.kind;
    } catch (_) {
      return CombinePdfFailure.writeFailed;
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
    if (store == null || _working || _merging) return wanted;
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
  Future<CombineSharePreparation> prepareShare(Iterable<String> ids) async {
    final store = _store;
    const nothing =
        CombineSharePreparation(paths: <String>[], unavailable: <String>[]);
    if (store == null) return nothing;
    final epoch = _epoch;
    final files = <({CombinedPdf document, File file})>[];
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
      return CombineSharePreparation(
          paths: const <String>[], unavailable: unavailable);
    }
    final paths = await _sharePreparer.prepare(files);
    if (_disposed || epoch != _epoch) return nothing;
    return CombineSharePreparation(paths: paths, unavailable: const <String>[]);
  }

  /// Exports one document to Downloads (Android) or the Files app (iPhone).
  /// Throws a [CombinePdfException] when it did not work.
  Future<ScannerExportResult> exportDocument(String id) async {
    final store = _store;
    final document = documentById(id);
    if (store == null || document == null) {
      throw const CombinePdfException(CombinePdfFailure.notFound);
    }
    if (_working || _merging) {
      throw const CombinePdfException(CombinePdfFailure.busy);
    }
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      if (!await store.isIntact(document)) {
        _missing = <String>{..._missing, id};
        throw const CombinePdfException(CombinePdfFailure.fileMissing);
      }
      if (_disposed || epoch != _epoch) {
        throw const CombinePdfException(CombinePdfFailure.accountChanged);
      }
      return await _exporter.export(
          document.exportFileName, store.fileOf(document));
    } finally {
      _working = false;
      _notify();
    }
  }
}
