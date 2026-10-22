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
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';

/// Builds the cloud library of one signed-in account, or returns null when this
/// build keeps the tool local. [store] is the account's local store and [files]
/// finds its stored files for the uploader.
typedef CombineCloudFactory = ToolkitCloudLibrary? Function(
  String accountId,
  CombinePdfStore store,
  ToolkitLocalFiles files,
);

/// Finds the stored file of a document for the cloud uploader. It only looks; it
/// never creates, moves or deletes.
class _StoredCombineFiles implements ToolkitLocalFiles {
  const _StoredCombineFiles(this._store);

  final CombinePdfStore _store;

  @override
  Future<File?> resolve(ToolkitSyncEntry entry) async {
    final file = _store.fileForId(entry.localRef);
    if (file == null || !await file.exists()) return null;
    return file;
  }
}

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
    CombineCloudFactory? cloudFactory,
    Duration cloudSyncInterval = const Duration(seconds: 60),
    CombineFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _executor = executor,
        _cloudFactory = cloudFactory,
        _cloudSyncInterval = cloudSyncInterval,
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
  final CombineCloudFactory? _cloudFactory;
  final Duration _cloudSyncInterval;
  final CombineFileCopier? _copier;
  final DateTime Function() _clock;
  final String Function()? _idGenerator;

  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  CombinePdfStore? _store;

  // The account's cloud copy (null: this build keeps the tool local).
  ToolkitCloudLibrary? _cloud;
  StreamSubscription<ToolkitSyncUpdate>? _cloudUpdates;
  StreamSubscription<String>? _cloudDeletions;
  Timer? _cloudTimer;
  bool _reconciling = false;
  bool _cloudUnreachable = false;
  ToolkitFailure? _cloudFailure;
  Map<String, ToolkitDocumentSyncState> _cloudStates =
      const <String, ToolkitDocumentSyncState>{};
  Map<String, ToolkitDocumentMetadata> _remoteById =
      const <String, ToolkitDocumentMetadata>{};
  List<CombinedPdf> _remoteOnly = const <CombinedPdf>[];
  Set<String> _remoteOnlyIds = const <String>{};
  String? _downloadingId;
  CombinePdfFailure? _openFailure;

  // Work the view model started and does not wait for itself (the cloud
  // comparison after a refresh, the removal of a file once the server confirmed
  // a delete). [settle] waits for it, so nothing still touches the account's
  // folder when it is removed.
  final Set<Future<void>> _background = <Future<void>>{};

  final CombinePlan _plan = CombinePlan();

  // What the phone holds, and what the screen lists: the phone's documents plus
  // the ones that are only in the account's cloud.
  List<CombinedPdf> _localDocuments = const <CombinedPdf>[];
  List<CombinedPdf> _documents = const <CombinedPdf>[];
  Set<String> _missing = const <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _checking = false;
  bool _picking = false;
  int _checkDone = 0;
  int _checkTotal = 0;
  bool _merging = false;
  bool _working = false;
  int _legacyCount = 0;
  CombineCancelToken? _token;

  CombinePlan get plan => _plan;
  List<CombinedPdf> get documents => _documents;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;

  /// Files are being picked or checked. The selection is locked meanwhile.
  bool get isChecking => _checking;

  /// The system picker is open. Nothing is shown for this: the picker is the
  /// feedback, and no screen of the other tools adds a card behind it.
  bool get isPicking => _picking;

  /// The chosen files came back from the picker and are being read and checked.
  bool get isCheckingFiles => _checking && !_picking;

  /// Files already checked and files chosen, for the real "X of Y" count.
  int get checkedCount => _checkDone;
  int get chosenCount => _checkTotal;

  /// A combine is running.
  bool get isMerging => _merging;

  /// A library action (rename, delete, share, export) is running.
  bool get isWorking => _working;
  bool get isBusy => _checking || _merging || _working || isDownloading;
  bool get isSelectionMode => _selectionMode;
  int get legacyDocumentCount => _legacyCount;
  String? get userId => _userId;

  /// This build keeps the account's documents in its cloud as well.
  bool get cloudEnabled => _cloud != null;

  /// A document is being brought from the account's cloud onto this phone.
  bool get isDownloading => _downloadingId != null;

  /// The last attempt to ask the account's cloud failed, so documents that are
  /// only in the cloud may not be listed right now.
  bool get cloudUnreachable => _cloudUnreachable;

  /// The state of the documents in the user's account, for the status line. It
  /// says WHY the account could not be reached when that is the case.
  ToolkitCloudSummary get cloudSummary {
    final cloud = _cloud;
    if (cloud == null) return ToolkitCloudSummary.off;
    return summarizeToolkitCloud(
      library: cloud,
      documentIds: <String>[
        for (final d in _localDocuments)
          if (!_isDeleting(cloud, d.id)) d.id,
      ],
      restoring: isDownloading,
      unreachable: _cloudUnreachable,
      unreachableFailure: _cloudFailure,
    );
  }

  /// The user asked to try the account copy again now.
  Future<void> retryCloud() async {
    final cloud = _cloud;
    if (cloud == null) return;
    for (final entry in cloud.entries) {
      if (entry.type != ToolkitDocumentType.combinePdfs) continue;
      final waiting =
          entry.state == ToolkitDocumentSyncState.syncFailedRetryable ||
              entry.state == ToolkitDocumentSyncState.savedLocallyPendingSync;
      if (!waiting) continue;
      try {
        await cloud.retry(entry.documentId);
      } catch (_) {}
    }
    await refresh();
  }

  /// Why the last [openableFile], [prepareShare] or [exportDocument] could not
  /// bring a cloud document onto the phone; null when it did not try or worked.
  CombinePdfFailure? get lastOpenFailure => _openFailure;

  /// How the library should describe [id]; null when this build has no cloud.
  /// "Saved to cloud" is only ever answered for a document the server confirmed.
  ToolkitDocumentSyncState? cloudStateOf(String id) {
    final cloud = _cloud;
    if (cloud == null) return null;
    if (_remoteOnlyIds.contains(id)) {
      return ToolkitDocumentSyncState.downloadRequired;
    }
    final seen = _cloudStates[id];
    final entry = cloud.entryFor(id);
    if (seen == ToolkitDocumentSyncState.remoteDeleted ||
        seen == ToolkitDocumentSyncState.downloadFailed) {
      return seen;
    }
    if (entry != null &&
        entry.isCloudConfirmed &&
        entry.state == ToolkitDocumentSyncState.savedToCloud) {
      return ToolkitDocumentSyncState.savedToCloud;
    }
    if (seen == ToolkitDocumentSyncState.savedToCloud) return seen;
    return entry?.state ??
        seen ??
        ToolkitDocumentSyncState.savedLocallyPendingSync;
  }

  /// Whether "back up now" can do something for [id].
  bool canRetryBackup(String id) {
    final state = cloudStateOf(id);
    return state == ToolkitDocumentSyncState.syncFailedRetryable ||
        state == ToolkitDocumentSyncState.savedLocallyPendingSync;
  }

  bool isDownloadingDocument(String id) => _downloadingId == id;

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
    _detachCloud();
    if (!_plan.isEmpty) unawaited(_picker.clearPickedCopies());
    super.dispose();
  }

  void _detachCloud() {
    _cloudTimer?.cancel();
    _cloudTimer = null;
    unawaited(_cloudUpdates?.cancel());
    unawaited(_cloudDeletions?.cancel());
    _cloudUpdates = null;
    _cloudDeletions = null;
    final cloud = _cloud;
    _cloud = null;
    _reconciling = false;
    _cloudUnreachable = false;
    _cloudFailure = null;
    _cloudStates = const <String, ToolkitDocumentSyncState>{};
    _remoteById = const <String, ToolkitDocumentMetadata>{};
    _remoteOnly = const <CombinedPdf>[];
    _remoteOnlyIds = const <String>{};
    _downloadingId = null;
    if (cloud != null) unawaited(cloud.dispose());
  }

  void _attachCloud(ToolkitCloudLibrary cloud, int epoch) {
    _cloud = cloud;
    _cloudUpdates = cloud.updates.listen((_) {
      if (_disposed || epoch != _epoch) return;
      _merge();
      _notify();
    });
    _cloudDeletions = cloud.deletions.listen((id) {
      if (_disposed || epoch != _epoch) return;
      _track(_removeLocalAfterCloudDelete(id, epoch));
    });
    // Nothing is sent until it is due; this only asks the journal again, so a
    // retry whose wait has passed runs without the user doing anything.
    _cloudTimer = Timer.periodic(_cloudSyncInterval, (_) {
      if (!_disposed && epoch == _epoch) unawaited(cloud.syncDue());
    });
    unawaited(cloud.start());
  }

  void _track(Future<void> work) {
    _background.add(work);
    unawaited(
      work.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _background.remove(work);
      }),
    );
  }

  /// Completes when the view model and its cloud copy have no work in flight:
  /// the cloud comparison, a sync that was started, a removal after a confirmed
  /// delete. It does not wait for work that only waits for its retry time. For
  /// tests and shutdown, so no file is open when a folder is deleted.
  @visibleForTesting
  Future<void> settle() async {
    while (true) {
      final pending = _background.toList();
      if (pending.isNotEmpty) {
        await Future.wait(pending);
        continue;
      }
      final cloud = _cloud;
      if (cloud != null) await cloud.idle();
      if (_background.isEmpty) return;
    }
  }

  /// A delete that waited for the network was confirmed by the server: the
  /// phone's copy goes now (and only now).
  Future<void> _removeLocalAfterCloudDelete(String id, int epoch) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.delete(<String>[id]);
    } catch (_) {
      // Still listed; the next sync of the journal finds nothing to do, and the
      // user can delete it again.
    }
    if (_disposed || epoch != _epoch) return;
    await refresh();
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
    _detachCloud();
    _localDocuments = const <CombinedPdf>[];
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
      // The cloud copy is optional and never blocks the local library: a build
      // without it, or a failure to set it up, leaves the tool exactly as it was.
      final makeCloud = _cloudFactory;
      final store = _store;
      if (makeCloud != null && store != null) {
        try {
          final cloud = makeCloud(uid, store, _StoredCombineFiles(store));
          if (cloud != null) _attachCloud(cloud, epoch);
        } catch (_) {}
      }
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loading = false;
      _loadFailed = true;
      _notify();
      return;
    }
    await refresh();
  }

  /// Reloads the signed-in account's documents from disk, then asks the account's
  /// cloud what it holds (in the background, so the local list shows at once).
  Future<void> refresh() async {
    final store = _store;
    final epoch = _epoch;
    if (store == null) return;
    try {
      final library = await store.load();
      if (_disposed || epoch != _epoch) return;
      _localDocuments = library.documents;
      _missing = library.missingIds;
      _loadFailed = false;
      _merge();
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loadFailed = true;
    }
    _loading = false;
    _notify();
    if (_cloud != null && !_loadFailed) _track(_reconcile(epoch));
  }

  /// Rebuilds the listed documents from the phone's and the cloud-only ones. A
  /// document whose delete the user asked for is not listed any more, although
  /// its file stays until the server confirms the delete.
  void _merge() {
    final cloud = _cloud;
    final listed = <CombinedPdf>[
      for (final d in _localDocuments)
        if (!_isDeleting(cloud, d.id)) d,
    ];
    final localIds = <String>{for (final d in _localDocuments) d.id};
    final onlyCloud = <CombinedPdf>[
      for (final d in _remoteOnly)
        if (!localIds.contains(d.id)) d,
    ];
    _remoteOnlyIds = <String>{for (final d in onlyCloud) d.id};
    final merged = <CombinedPdf>[...listed, ...onlyCloud]..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    _documents = merged;
    final ids = merged.map((d) => d.id).toSet();
    _selected.removeWhere((id) => !ids.contains(id));
  }

  static bool _isDeleting(ToolkitCloudLibrary? cloud, String id) {
    final entry = cloud?.entryFor(id);
    return entry != null &&
        entry.deleteRequested &&
        entry.state == ToolkitDocumentSyncState.deletePending;
  }

  CombinedPdf _listedFromCloud(ToolkitDocumentMetadata m) => CombinedPdf(
        id: m.documentId,
        fileName: '${m.documentId}.pdf',
        name: m.title,
        createdAt: m.sourceCreatedAt,
        fileSize: m.sizeBytes,
        pageCount: m.pageCount ?? 1,
      );

  /// Compares the phone's documents with the account's cloud library. A failure
  /// keeps what was shown and says the cloud could not be reached.
  Future<void> _reconcile(int epoch) async {
    final cloud = _cloud;
    if (cloud == null || _reconciling) return;
    _reconciling = true;
    try {
      final result = await cloud.reconcile(
        type: ToolkitDocumentType.combinePdfs,
        local: <ToolkitCloudLocalDocument>[
          for (final d in _localDocuments)
            ToolkitCloudLocalDocument(
              documentId: d.id,
              title: d.name,
              sizeBytes: d.fileSize,
              pageCount: d.pageCount,
              sourceCreatedAt: d.createdAt,
              fileMissing: _missing.contains(d.id),
            ),
        ],
      );
      if (_disposed || epoch != _epoch) return;
      _cloudStates = result.states;
      _remoteById = result.remoteById;
      _remoteOnly = <CombinedPdf>[
        for (final m in result.remoteOnly) _listedFromCloud(m),
      ];
      _cloudUnreachable = false;
      _cloudFailure = null;
    } on ToolkitDocumentException catch (error) {
      if (_disposed || epoch != _epoch) return;
      _cloudUnreachable = true;
      _cloudFailure = error.failure;
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _cloudUnreachable = true;
      _cloudFailure = ToolkitFailure.unavailable;
    } finally {
      _reconciling = false;
    }
    _merge();
    _notify();
  }

  /// Asks the cloud again now (a pull to refresh, or coming back to the screen).
  Future<void> syncNow() async {
    final cloud = _cloud;
    if (cloud == null) return;
    unawaited(cloud.syncDue());
    await refresh();
  }

  /// The user asked to back this document up again now.
  Future<void> retryBackup(String id) async {
    final cloud = _cloud;
    if (cloud == null) return;
    try {
      await cloud.retry(id);
    } catch (_) {}
    _notify();
  }

  // ---------------------------------------------------------- the selection

  /// Opens the system picker and adds the chosen PDFs.
  Future<AddFilesOutcome> pickFiles() async {
    final early = _canStartSelection();
    if (early != null) return AddFilesOutcome.failed(early);
    final epoch = _epoch;
    _checking = true;
    _picking = true;
    _notify();
    try {
      final List<PickedPdf>? picked;
      try {
        picked = await _picker.pick();
      } finally {
        _picking = false;
      }
      if (_disposed || epoch != _epoch) {
        return const AddFilesOutcome.failed(CombinePdfFailure.accountChanged);
      }
      if (picked == null) return const AddFilesOutcome(cancelled: true);
      _notify();
      return await _addPicked(picked, epoch);
    } catch (_) {
      return const AddFilesOutcome.failed(CombinePdfFailure.missingSource);
    } finally {
      _checking = false;
      _picking = false;
      _checkDone = 0;
      _checkTotal = 0;
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
      _checkDone = 0;
      _checkTotal = 0;
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
    _checkTotal = picked.length;
    for (var index = 0; index < picked.length; index++) {
      final file = picked[index];
      // Files before this one are finished (added, a duplicate or rejected).
      _checkDone = index;
      _notify();
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
      // The phone's copy is saved either way. Queueing it for the account's cloud
      // never fails the combine: until the server confirms it, the document is
      // shown as saved on this phone only.
      final cloud = _cloud;
      if (cloud != null && !_disposed && epoch == _epoch) {
        try {
          await cloud.queue(ToolkitSyncEntry(
            documentId: stored.id,
            accountId: uid,
            type: ToolkitDocumentType.combinePdfs,
            contentType: ToolkitContentType.pdf,
            title: ToolkitDocumentTitles.sanitize(stored.name),
            sizeBytes: stored.fileSize,
            localRef: stored.id,
            sourceCreatedAt: stored.createdAt,
            pageCount: stored.pageCount,
          ));
        } catch (_) {}
      }
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
    _openFailure = null;
    // A document that is only in the account's cloud is downloaded, verified and
    // stored first; from then on it is an ordinary local document.
    if (!await _ensureLocal(document)) return null;
    if (_disposed || epoch != _epoch) return null;
    final current = documentById(document.id) ?? document;
    final intact = await store.isIntact(current);
    if (_disposed || epoch != _epoch) return null;
    if (!intact) {
      if (!_missing.contains(document.id)) {
        _missing = <String>{..._missing, document.id};
        _notify();
      }
      return null;
    }
    return store.fileOf(current);
  }

  /// Brings [document] onto the phone when it is only in the account's cloud (or
  /// its file is gone but the cloud has it). True when a verified local file
  /// exists afterwards; false sets [lastOpenFailure]. Never touches a document
  /// that is already on the phone.
  Future<bool> _ensureLocal(CombinedPdf document) async {
    final id = document.id;
    final remote = _remoteById[id];
    final needs = _remoteOnlyIds.contains(id) ||
        (_missing.contains(id) && remote != null);
    if (!needs) return true;
    final cloud = _cloud;
    final store = _store;
    final target = store?.restoreFileFor(id);
    if (cloud == null || store == null || remote == null || target == null) {
      _openFailure = CombinePdfFailure.cloudUnavailable;
      return false;
    }
    if (_downloadingId != null) {
      _openFailure = CombinePdfFailure.busy;
      return false;
    }
    final epoch = _epoch;
    _downloadingId = id;
    _notify();
    try {
      final result = await cloud.download(document: remote, target: target);
      if (_disposed || epoch != _epoch) return false;
      if (result == ToolkitDownloadResult.conflict) {
        // A leftover in the download folder that is not this document: never
        // used, removed, and the next try downloads again.
        await store.discardRestoreFile(id);
        _openFailure = CombinePdfFailure.cloudUnavailable;
        return false;
      }
      await store.restoreFromCloud(
        id: id,
        source: target,
        name: remote.title,
        createdAt: remote.sourceCreatedAt,
        expectedSize: remote.sizeBytes,
      );
      if (_disposed || epoch != _epoch) return false;
      _remoteOnly = <CombinedPdf>[
        for (final d in _remoteOnly)
          if (d.id != id) d,
      ];
      await refresh();
      return true;
    } on ToolkitDocumentException catch (error) {
      _openFailure = error.failure == ToolkitFailure.insufficientStorage
          ? CombinePdfFailure.storageFull
          : CombinePdfFailure.cloudUnavailable;
      return false;
    } on CombinePdfException catch (error) {
      _openFailure = error.kind == CombinePdfFailure.storageFull
          ? CombinePdfFailure.storageFull
          : CombinePdfFailure.cloudUnavailable;
      return false;
    } catch (_) {
      _openFailure = CombinePdfFailure.cloudUnavailable;
      return false;
    } finally {
      if (_downloadingId == id) _downloadingId = null;
      _notify();
    }
  }

  /// Renames [id]. Returns null on success or the reason it failed.
  Future<CombinePdfFailure?> rename(String id, String newName) async {
    final store = _store;
    if (store == null) return CombinePdfFailure.signedOut;
    if (_working || _merging || isDownloading) return CombinePdfFailure.busy;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      final cloud = _cloud;
      if (_remoteOnlyIds.contains(id)) {
        // Only in the account's cloud: the title is changed there.
        final name = CombineNaming.sanitizeDisplayName(newName);
        if (cloud == null) return CombinePdfFailure.notFound;
        if (name == null) return CombinePdfFailure.invalidName;
        final clash = _documents.any(
            (d) => d.id != id && d.name.toLowerCase() == name.toLowerCase());
        if (clash) return CombinePdfFailure.nameInUse;
        try {
          await cloud.rename(id, ToolkitDocumentTitles.sanitize(name));
        } catch (_) {
          return CombinePdfFailure.cloudUnavailable;
        }
        if (_disposed || epoch != _epoch) {
          return CombinePdfFailure.accountChanged;
        }
        _remoteOnly = <CombinedPdf>[
          for (final d in _remoteOnly) d.id == id ? d.copyWith(name: name) : d,
        ];
        final known = _remoteById[id];
        if (known != null) {
          _remoteById = <String, ToolkitDocumentMetadata>{
            ..._remoteById,
            id: known.copyWith(title: ToolkitDocumentTitles.sanitize(name)),
          };
        }
        _merge();
        return null;
      }
      final updated = await store.rename(id, newName);
      if (_disposed || epoch != _epoch) return CombinePdfFailure.accountChanged;
      if (cloud != null) {
        // The phone's title is the user's; the cloud copy follows, and a failure
        // to reach it is kept and retried by the journal, never shown as an
        // error of the rename.
        try {
          await cloud.rename(id, ToolkitDocumentTitles.sanitize(updated.name));
        } catch (_) {}
      }
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
  ///
  /// With a cloud copy the account's copy goes first, and the phone's file only
  /// after the server confirmed it. If the server cannot be reached the delete is
  /// recorded and finished later: the document is no longer listed, and its file
  /// is removed when the confirmation arrives.
  Future<List<String>> delete(Iterable<String> ids) async {
    final store = _store;
    final wanted = ids.toList();
    if (store == null || _working || _merging || isDownloading) return wanted;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      final cloud = _cloud;
      var onPhone = wanted;
      final notDeletedInCloud = <String>[];
      final goneFromCloudOnly = <String>{};
      if (cloud != null) {
        onPhone = <String>[];
        for (final id in wanted) {
          final result = await cloud.delete(id);
          if (_disposed || epoch != _epoch) return const <String>[];
          switch (result) {
            case ToolkitCloudDeleteResult.deleted:
              if (_remoteOnlyIds.contains(id)) {
                goneFromCloudOnly.add(id);
              } else {
                onPhone.add(id);
              }
            case ToolkitCloudDeleteResult.pending:
              break;
            case ToolkitCloudDeleteResult.failed:
              notDeletedInCloud.add(id);
          }
        }
      }
      final outcome = onPhone.isEmpty
          ? const CombineDeleteOutcome(
              deleted: <String>[], failed: <String>[], notFound: <String>[])
          : await store.delete(onPhone);
      if (_disposed || epoch != _epoch) return const <String>[];
      _selected.removeAll(outcome.deleted);
      _selected.removeAll(goneFromCloudOnly);
      if (goneFromCloudOnly.isNotEmpty) {
        _remoteOnly = <CombinedPdf>[
          for (final d in _remoteOnly)
            if (!goneFromCloudOnly.contains(d.id)) d,
        ];
      }
      await refresh();
      return <String>[
        ...outcome.failed,
        ...outcome.notFound,
        ...notDeletedInCloud,
      ];
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
    _openFailure = null;
    for (final id in ids) {
      var document = documentById(id);
      if (document == null) {
        unavailable.add(id);
        continue;
      }
      // Sharing always uses a verified file on the phone, never a cloud link.
      if (!await _ensureLocal(document)) {
        unavailable.add(id);
        continue;
      }
      if (_disposed || epoch != _epoch) return nothing;
      document = documentById(id) ?? document;
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
    var document = documentById(id);
    if (store == null || document == null) {
      throw const CombinePdfException(CombinePdfFailure.notFound);
    }
    if (_working || _merging || isDownloading) {
      throw const CombinePdfException(CombinePdfFailure.busy);
    }
    final epoch = _epoch;
    _working = true;
    _openFailure = null;
    _notify();
    try {
      if (!await _ensureLocal(document)) {
        throw CombinePdfException(
            _openFailure ?? CombinePdfFailure.cloudUnavailable);
      }
      if (_disposed || epoch != _epoch) {
        throw const CombinePdfException(CombinePdfFailure.accountChanged);
      }
      document = documentById(id) ?? document;
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
