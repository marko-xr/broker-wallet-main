import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_stamp_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_account_files.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_download_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';

/// Builds the cloud library of one signed-in account for Document Signature, or
/// returns null when this build keeps the tool local. [files] finds the stored
/// files and the folder of the journal.
typedef SignatureCloudFactory = ToolkitCloudLibrary? Function(
  String accountId,
  ToolkitAccountFiles files,
);

/// What picking and opening a PDF did.
class SignatureOpenOutcome {
  const SignatureOpenOutcome.opened(SignatureEditorViewModel this.session)
      : failure = null,
        cancelled = false;
  const SignatureOpenOutcome.failed(SignatureFailure this.failure)
      : session = null,
        cancelled = false;
  const SignatureOpenOutcome.cancelled()
      : session = null,
        failure = null,
        cancelled = true;

  /// The editing session, when the file was opened. The caller owns it and
  /// disposes it when the editor closes.
  final SignatureEditorViewModel? session;
  final SignatureFailure? failure;

  /// The picker was closed without a choice.
  final bool cancelled;
}

/// Files ready to hand to the share sheet, or the documents that could not be
/// shared because their stored file is gone or damaged.
class SignatureSharePreparation {
  const SignatureSharePreparation(
      {required this.paths, required this.unavailable});

  final List<String> paths;
  final List<String> unavailable;

  bool get isShareable => unavailable.isEmpty && paths.isNotEmpty;
}

/// The Document Signature screen's logic: the signed-in account's signed
/// documents (list, selection, rename, delete, share, export) and the opening of
/// a picked PDF into an editing session. It owns no widgets.
///
/// Every asynchronous step checks that the screen is still alive and that the
/// signed-in account is still the one the step started for; a result for a
/// previous account is dropped, never shown or stored. Only one open or library
/// action runs at a time, so a double tap does nothing.
class SignatureLibraryViewModel extends ChangeNotifier {
  SignatureLibraryViewModel({
    required SignatureExecutor executor,
    required Future<Directory> Function() baseDirectory,
    required SignaturePdfPicker picker,
    required SignatureUsageRecorder usage,
    required SignatureSharePreparer sharePreparer,
    required SignaturePdfExporter exporter,
    required ScannerBackupGuard backup,
    required StampRenderer stampRenderer,
    required String? Function() currentUserId,
    required Stream<String?> userIdChanges,
    Future<int> Function()? legacyDocumentCount,
    SignatureCloudFactory? cloudFactory,
    Duration cloudSyncInterval = const Duration(seconds: 60),
    SignatureFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _cloudFactory = cloudFactory,
        _cloudSyncInterval = cloudSyncInterval,
        _executor = executor,
        _baseDirectory = baseDirectory,
        _picker = picker,
        _usage = usage,
        _sharePreparer = sharePreparer,
        _exporter = exporter,
        _backup = backup,
        _stampRenderer = stampRenderer,
        _currentUserId = currentUserId,
        // The account stream is listened to by this view model and by every
        // editing session it opens. The real auth repository's stream can be
        // listened to only once, so it is shared here.
        _userIdChanges = userIdChanges.isBroadcast
            ? userIdChanges
            : userIdChanges.asBroadcastStream(),
        _legacyDocumentCount = legacyDocumentCount,
        _copier = copier,
        _clock = clock,
        _idGenerator = idGenerator;

  final SignatureExecutor _executor;
  final Future<Directory> Function() _baseDirectory;
  final SignaturePdfPicker _picker;
  final SignatureUsageRecorder _usage;
  final SignatureSharePreparer _sharePreparer;
  final SignaturePdfExporter _exporter;
  final ScannerBackupGuard _backup;
  final StampRenderer _stampRenderer;
  final String? Function() _currentUserId;
  final Stream<String?> _userIdChanges;
  final Future<int> Function()? _legacyDocumentCount;
  final SignatureCloudFactory? _cloudFactory;
  final Duration _cloudSyncInterval;
  final SignatureFileCopier? _copier;
  final DateTime Function()? _clock;
  final String Function()? _idGenerator;

  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  SignatureStore? _store;

  // The account copy of the documents (null: this build keeps the tool local).
  ToolkitCloudSync? _cloud;

  // What the store holds, and what the screen lists: the same, minus a document
  // whose delete the user asked for and the server has not confirmed yet.
  List<SignedDocument> _visible = const <SignedDocument>[];
  List<SignedDocument> _documents = const <SignedDocument>[];
  Set<String> _missing = const <String>{};
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _opening = false;
  bool _working = false;
  bool _editing = false;
  int _legacyCount = 0;

  List<SignedDocument> get documents => _visible;

  /// The state of the documents in the user's account, for the status line.
  ToolkitCloudSummary get cloudSummary =>
      _cloud?.summary() ?? ToolkitCloudSummary.off;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;

  /// A PDF is being picked or checked.
  bool get isOpening => _opening;

  /// A library action (rename, delete, share, export) is running.
  bool get isWorking => _working;

  /// An editing session is open.
  bool get isEditing => _editing;
  bool get isBusy => _opening || _working || _editing;
  bool get isSelectionMode => _selectionMode;

  /// Documents an earlier version saved, which carry no owner: counted, never
  /// shown, moved or deleted.
  int get legacyDocumentCount => _legacyCount;
  String? get userId => _userId;

  bool isMissing(String id) => _missing.contains(id);
  bool isSelected(String id) => _selected.contains(id);
  int get selectedCount => _selected.length;

  List<SignedDocument> get selectedDocuments => <SignedDocument>[
        for (final d in _documents)
          if (_selected.contains(d.id)) d
      ];

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
    _detachCloud();
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
    _userId = uid;
    _store = null;
    _detachCloud();
    _visible = const <SignedDocument>[];
    _documents = const <SignedDocument>[];
    _missing = const <String>{};
    _selected.clear();
    _selectionMode = false;
    _loadFailed = false;
    _loading = uid != null;
    _notify();
    if (uid == null) return;
    try {
      final base = await _baseDirectory();
      // Signed documents stay out of cloud and device backup (iPhone needs the
      // folder marked; Android's rules name it). Best effort and never fatal.
      try {
        final root =
            Directory(p.join(base.path, SignatureStore.rootFolderName));
        await root.create(recursive: true);
        await _backup.exclude(root.path);
      } catch (_) {}
      if (_disposed || epoch != _epoch) return;
      _store = SignatureStore(
        accountDir: SignatureStore.accountDirectory(base, uid),
        userId: uid,
        verify: (file) => _executor.analyze(file.path,
            maxBytes: SignatureLimits.maxStoredBytes),
        copier: _copier,
        clock: _clock,
        idGenerator: _idGenerator,
      );
      _attachCloud(uid, epoch);
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loading = false;
      _loadFailed = true;
      _notify();
      return;
    }
    await refresh();
  }

  /// Reloads the signed-in account's documents from disk, then (unless [cloud] is
  /// false) compares them with the user's account in the background: what the
  /// account lacks is uploaded, what this phone lacks is downloaded. A document
  /// just signed and saved reaches here through the editor's `onSaved`.
  Future<void> refresh({bool cloud = true}) async {
    final store = _store;
    final epoch = _epoch;
    if (store == null) return;
    try {
      final library = await store.load();
      if (_disposed || epoch != _epoch) return;
      _documents = library.documents;
      _missing = library.missingIds;
      _loadFailed = false;
      _rebuildVisible();
      final ids = _documents.map((d) => d.id).toSet();
      _selected.removeWhere((id) => !ids.contains(id));
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _loadFailed = true;
    }
    _loading = false;
    _notify();
    if (cloud && !_loadFailed) _cloud?.requestSync();
  }

  // ------------------------------------------------------- the account copy

  void _rebuildVisible() {
    final cloud = _cloud;
    _visible = cloud == null
        ? _documents
        : <SignedDocument>[
            for (final d in _documents)
              if (!cloud.isDeleting(d.id)) d,
          ];
  }

  void _attachCloud(String uid, int epoch) {
    final makeCloud = _cloudFactory;
    final store = _store;
    if (makeCloud == null || store == null) return;
    try {
      final files = ToolkitAccountFiles(store.accountDir);
      final library = makeCloud(uid, files);
      if (library == null) return;
      _cloud = ToolkitCloudSync(
        type: ToolkitDocumentType.signature,
        library: library,
        syncInterval: _cloudSyncInterval,
        localDocuments: _cloudLocalDocuments,
        restoreOne: (document, lib) => _restoreOne(document, lib, epoch),
        removeLocal: (id) => _removeLocalAfterCloudDelete(id, epoch),
        onChanged: () {
          if (_disposed || epoch != _epoch) return;
          _rebuildVisible();
          _notify();
        },
        onRestoredOne: () async {
          if (!_disposed && epoch == _epoch) await refresh(cloud: false);
        },
      )..start();
    } catch (_) {
      // The cloud copy is optional and never blocks the local library.
    }
  }

  void _detachCloud() {
    _cloud?.dispose();
    _cloud = null;
  }

  List<ToolkitCloudLocalDocument> _cloudLocalDocuments() =>
      <ToolkitCloudLocalDocument>[
        for (final d in _documents)
          ToolkitCloudLocalDocument(
            documentId: d.id,
            title: d.name,
            sizeBytes: d.fileSize,
            sourceCreatedAt: d.createdAt,
            pageCount: d.pageCount >= 1 ? d.pageCount : null,
            fileMissing: _missing.contains(d.id),
          ),
      ];

  /// Downloads one document of the account that this phone lacks and stores it.
  Future<bool> _restoreOne(
    ToolkitDocumentMetadata document,
    ToolkitCloudLibrary library,
    int epoch,
  ) async {
    final store = _store;
    if (store == null || _disposed || epoch != _epoch) return false;
    final target = ToolkitAccountFiles(store.accountDir)
        .restoreFile(document.documentId, document.contentType.extension);
    if (target == null) return false;
    final result = await library.download(document: document, target: target);
    if (_disposed || epoch != _epoch) return false;
    if (result == ToolkitDownloadResult.conflict) {
      // A leftover in the download folder that is not this document: never used,
      // removed, so the next attempt downloads again.
      try {
        await target.delete();
      } catch (_) {}
      return false;
    }
    await store.restoreFromCloud(
      id: document.documentId,
      source: target,
      name: document.title,
      createdAt: document.sourceCreatedAt,
      expectedSize: document.sizeBytes,
    );
    return true;
  }

  /// A delete that waited for the network was confirmed by the server: the
  /// phone's copy goes now (and only now).
  Future<void> _removeLocalAfterCloudDelete(String id, int epoch) async {
    final store = _store;
    if (store == null || !_documents.any((d) => d.id == id)) return;
    try {
      await store.delete(<String>[id]);
    } catch (_) {
      // Still listed; the user can delete it again.
    }
    if (_disposed || epoch != _epoch) return;
    await refresh(cloud: false);
  }

  /// The user asked to try the account copy again now.
  Future<void> retryCloud() async {
    final cloud = _cloud;
    if (cloud != null) await cloud.retryNow();
  }

  /// Completes when the account copy has no work in flight (for tests, so no file
  /// is open when a folder is removed).
  @visibleForTesting
  Future<void> settle() async {
    final cloud = _cloud;
    if (cloud != null) await cloud.settle();
  }

  // ---------------------------------------------------------------- opening

  SignatureFailure? _canStart() {
    if (_opening || _working || _editing) return SignatureFailure.busy;
    final uid = _userId;
    if (uid == null || _store == null || _currentUserId() != uid) {
      return SignatureFailure.signedOut;
    }
    return null;
  }

  /// Opens the system picker, checks the chosen PDF and, when it can be signed,
  /// starts an editing session for it.
  Future<SignatureOpenOutcome> pickAndOpen() async {
    final early = _canStart();
    if (early != null) return SignatureOpenOutcome.failed(early);
    final epoch = _epoch;
    _opening = true;
    _notify();
    try {
      final PickedSignaturePdf? picked;
      try {
        picked = await _picker.pick();
      } catch (_) {
        return const SignatureOpenOutcome.failed(
            SignatureFailure.missingSource);
      }
      if (_disposed || epoch != _epoch) {
        return const SignatureOpenOutcome.failed(
            SignatureFailure.accountChanged);
      }
      if (picked == null) return const SignatureOpenOutcome.cancelled();
      return await _open(picked, epoch);
    } finally {
      _opening = false;
      _notify();
    }
  }

  /// Opens an already-picked file (the picker's own entry point, and tests').
  Future<SignatureOpenOutcome> openPicked(PickedSignaturePdf picked) async {
    final early = _canStart();
    if (early != null) return SignatureOpenOutcome.failed(early);
    final epoch = _epoch;
    _opening = true;
    _notify();
    try {
      return await _open(picked, epoch);
    } finally {
      _opening = false;
      _notify();
    }
  }

  Future<SignatureOpenOutcome> _open(
      PickedSignaturePdf picked, int epoch) async {
    final store = _store;
    final uid = _userId;
    if (store == null || uid == null) {
      return const SignatureOpenOutcome.failed(SignatureFailure.signedOut);
    }
    if (picked.path.isEmpty) {
      return const SignatureOpenOutcome.failed(SignatureFailure.missingSource);
    }
    final SignatureAnalysis analysis;
    try {
      analysis = await _executor.analyze(picked.path);
    } on SignatureException catch (error) {
      if (_disposed || epoch != _epoch) {
        return const SignatureOpenOutcome.failed(
            SignatureFailure.accountChanged);
      }
      return SignatureOpenOutcome.failed(error.kind);
    } catch (_) {
      if (_disposed || epoch != _epoch) {
        return const SignatureOpenOutcome.failed(
            SignatureFailure.accountChanged);
      }
      return const SignatureOpenOutcome.failed(SignatureFailure.corruptSource);
    }
    if (_disposed || epoch != _epoch || _currentUserId() != uid) {
      return const SignatureOpenOutcome.failed(SignatureFailure.accountChanged);
    }
    // A digitally signed file is refused: anything added after the signature
    // could invalidate it, and a visible stamp must not look like it kept it.
    if (analysis.features.hasSignatures) {
      return const SignatureOpenOutcome.failed(SignatureFailure.signedSource);
    }
    final SignatureEditorViewModel session;
    try {
      session = SignatureEditorViewModel(
        sourcePath: picked.path,
        sourceName: picked.name,
        analysis: analysis,
        executor: _executor,
        store: store,
        userId: uid,
        currentUserId: _currentUserId,
        userIdChanges: _userIdChanges,
        usage: _usage,
        renderer: _stampRenderer,
        idGenerator: _idGenerator,
        clock: _clock,
        onSaved: () async {
          if (!_disposed && epoch == _epoch) await refresh();
        },
        onClosed: () async {
          _editing = false;
          _notify();
          await _picker.clearPickedCopies();
        },
      );
    } catch (_) {
      // Nothing was opened, so the library must not stay marked as editing: that
      // would keep its upload button off for good.
      return const SignatureOpenOutcome.failed(SignatureFailure.unexpected);
    }
    _editing = true;
    return SignatureOpenOutcome.opened(session);
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

  SignedDocument? documentById(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The stored file of [document] when it is the complete file that was saved,
  /// otherwise null (the caller reports it missing).
  Future<File?> openableFile(SignedDocument document) async {
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
  Future<SignatureFailure?> rename(String id, String newName) async {
    final store = _store;
    if (store == null) return SignatureFailure.signedOut;
    if (_working) return SignatureFailure.busy;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      final updated = await store.rename(id, newName);
      if (_disposed || epoch != _epoch) return SignatureFailure.accountChanged;
      // The phone's title is the user's; the account copy follows, and a failure
      // to reach the account is kept and retried, never shown as a rename error.
      await _cloud?.rename(id, updated.name);
      await refresh();
      return null;
    } on SignatureException catch (error) {
      return error.kind;
    } catch (_) {
      return SignatureFailure.writeFailed;
    } finally {
      _working = false;
      _notify();
    }
  }

  /// Deletes the documents with these ids and nothing else. Returns the ids that
  /// could not be removed.
  Future<List<String>> delete(Iterable<String> ids) async {
    final store = _store;
    final wanted = ids.toList();
    if (store == null || _working) return wanted;
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      // With an account copy, the account's copy goes first and the phone's file
      // only after the server confirmed it. A delete the server cannot be asked
      // about now is recorded and finished later: the document is hidden, and its
      // file is removed when the confirmation arrives.
      var onPhone = wanted;
      var notDeletedInCloud = const <String>[];
      final cloud = _cloud;
      if (cloud != null) {
        final split = await cloud.deleteFirst(wanted);
        if (_disposed || epoch != _epoch) return const <String>[];
        onPhone = split.deleteLocally;
        notDeletedInCloud = split.failed;
      }
      final outcome = onPhone.isEmpty
          ? const SignatureDeleteOutcome(
              deleted: <String>[], failed: <String>[], notFound: <String>[])
          : await store.delete(onPhone);
      if (_disposed || epoch != _epoch) return const <String>[];
      _selected.removeAll(outcome.deleted);
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

  /// Copies the chosen documents, under their titles, for the share sheet. Only
  /// documents whose stored file is intact are shared.
  Future<SignatureSharePreparation> prepareShare(Iterable<String> ids) async {
    final store = _store;
    const nothing =
        SignatureSharePreparation(paths: <String>[], unavailable: <String>[]);
    if (store == null) return nothing;
    final epoch = _epoch;
    final files = <({SignedDocument document, File file})>[];
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
      return SignatureSharePreparation(
          paths: const <String>[], unavailable: unavailable);
    }
    final paths = await _sharePreparer.prepare(files);
    if (_disposed || epoch != _epoch) return nothing;
    return SignatureSharePreparation(
        paths: paths, unavailable: const <String>[]);
  }

  /// Exports one document to Downloads (Android) or the Files app (iPhone).
  /// Throws a [SignatureException] when it did not work.
  Future<ScannerExportResult> exportDocument(String id) async {
    final store = _store;
    final document = documentById(id);
    if (store == null || document == null) {
      throw const SignatureException(SignatureFailure.notFound);
    }
    if (_working) {
      throw const SignatureException(SignatureFailure.busy);
    }
    final epoch = _epoch;
    _working = true;
    _notify();
    try {
      if (!await store.isIntact(document)) {
        _missing = <String>{..._missing, id};
        throw const SignatureException(SignatureFailure.fileMissing);
      }
      if (_disposed || epoch != _epoch) {
        throw const SignatureException(SignatureFailure.accountChanged);
      }
      return await _exporter.export(
          document.exportFileName, store.fileOf(document));
    } finally {
      _working = false;
      _notify();
    }
  }
}
