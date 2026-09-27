import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_diagnostics.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';

/// Where one queued Offer media item is in its life on this device.
enum OfferMediaTaskState {
  /// Saved on the device, waiting for its turn.
  queued,

  /// Asking the Worker for an upload URL (or learning it is already done).
  authorizing,

  /// Sending the bytes to private R2.
  uploading,

  /// Asking the Worker to verify the bytes and attach the item.
  confirming,

  /// A failure that can pass; retried automatically at `nextAttemptAt`.
  retryWait,

  /// Automatic retries are used up; waiting for the user's Retry.
  needsRetry,

  /// The Offer is full; waiting for a place to free up or the user's Retry.
  blocked,

  /// Refused for good (see `failure`); only Remove helps.
  failed,

  /// The user removed it; any server-side state is being withdrawn.
  cancelling,
}

/// One Offer media item on its way to the server.
///
/// [mediaObjectId] is the item's identity everywhere — this task, the
/// Worker, `media_objects`, the R2 key and the local cache — and every server
/// call is idempotent on it. That is why a task can be retried from any step,
/// after any failure or an app restart, without ever creating a second
/// object.
@immutable
class OfferMediaUploadTask {
  const OfferMediaUploadTask({
    required this.mediaObjectId,
    required this.ownerId,
    required this.offerId,
    required this.kind,
    required this.contentType,
    required this.byteLength,
    required this.localPath,
    required this.createdAt,
    this.posterPath,
    this.displayName,
    this.durationMs,
    this.state = OfferMediaTaskState.queued,
    this.attempts = 0,
    this.nextAttemptAt,
    this.failure,
    this.serverTouched = false,
    this.bytesUploaded = false,
    this.progress = 0,
  });

  final String mediaObjectId;
  final String ownerId;
  final String offerId;
  final OfferMediaKind kind;
  final String contentType;
  final int byteLength;

  /// The app-owned copy being uploaded (inside the backup-excluded
  /// `offer_media` directory, named with the owner's prefix).
  final String localPath;
  final DateTime createdAt;
  final String? posterPath;
  final String? displayName;
  final int? durationMs;
  final OfferMediaTaskState state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final OfferMediaRejection? failure;

  /// An authorize was sent at least once, so the server may hold a row for
  /// this id that a removal must withdraw.
  final bool serverTouched;

  /// The bytes reached R2 for the current server row, so a retry only needs
  /// to confirm — a 100 MB video is never sent twice for a lost response.
  final bool bytesUploaded;

  /// Fraction sent, in memory only.
  final double progress;

  /// What the Offer media UI shows for this item.
  ///
  /// An automatic retry that is still pending is [OfferMediaUploadPhase
  /// .retrying], not a failure asking for the user's Retry: presenting it as
  /// "tap Retry" while the queue is about to retry by itself is what made a
  /// passing interruption look like a dead upload.
  OfferMediaUploadPhase get phase => switch (state) {
        OfferMediaTaskState.queued => OfferMediaUploadPhase.queued,
        OfferMediaTaskState.cancelling => OfferMediaUploadPhase.queued,
        OfferMediaTaskState.authorizing ||
        OfferMediaTaskState.uploading =>
          OfferMediaUploadPhase.uploading,
        OfferMediaTaskState.confirming => OfferMediaUploadPhase.confirming,
        OfferMediaTaskState.retryWait => OfferMediaUploadPhase.retrying,
        OfferMediaTaskState.needsRetry ||
        OfferMediaTaskState.blocked =>
          OfferMediaUploadPhase.retryableFailure,
        OfferMediaTaskState.failed => OfferMediaUploadPhase.permanentFailure,
      };

  /// Whether this item still takes one of the Offer's places.
  bool get countsTowardLimit =>
      state != OfferMediaTaskState.failed &&
      state != OfferMediaTaskState.cancelling;

  /// Whether the user can retry it now.
  bool get isRetryable =>
      state == OfferMediaTaskState.retryWait ||
      state == OfferMediaTaskState.needsRetry ||
      state == OfferMediaTaskState.blocked;

  /// The item as the Offer media UI draws it: from its local file (a photo's
  /// bytes, or the video itself, which can be played from here before it
  /// reaches the server), with its upload state.
  ///
  /// [running] is false when nothing is processing this item right now; a
  /// step persisted as in progress is then shown as waiting, never as a
  /// percentage frozen since the app was last in the foreground.
  OfferMediaRef toRef({bool running = true}) {
    var shown = phase;
    if (!running &&
        (shown == OfferMediaUploadPhase.uploading ||
            shown == OfferMediaUploadPhase.confirming)) {
      shown = OfferMediaUploadPhase.queued;
    }
    final failed = shown == OfferMediaUploadPhase.retrying ||
        shown == OfferMediaUploadPhase.retryableFailure ||
        shown == OfferMediaUploadPhase.permanentFailure;
    return OfferMediaRef(
      mediaObjectId: mediaObjectId,
      cacheKey: offerMediaCacheKey(
        ownerId: ownerId,
        mediaObjectId: mediaObjectId,
      ),
      localFilePath: localPath,
      isVideo: kind == OfferMediaKind.video,
      posterPath: posterPath,
      durationMs: durationMs,
      uploadPhase: shown,
      progress: shown == OfferMediaUploadPhase.uploading &&
              state == OfferMediaTaskState.uploading
          ? progress
          : null,
      failureMessageKey: failed
          ? (state == OfferMediaTaskState.blocked
                  ? OfferMediaRejection.limitReached
                  : failure ?? OfferMediaRejection.interrupted)
              .messageKey
          : null,
      displayName: displayName,
      byteLength: byteLength,
    );
  }

  OfferMediaUploadTask copyWith({
    OfferMediaTaskState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    OfferMediaRejection? failure,
    bool clearFailure = false,
    bool? serverTouched,
    bool? bytesUploaded,
    double? progress,
  }) =>
      OfferMediaUploadTask(
        mediaObjectId: mediaObjectId,
        ownerId: ownerId,
        offerId: offerId,
        kind: kind,
        contentType: contentType,
        byteLength: byteLength,
        localPath: localPath,
        createdAt: createdAt,
        posterPath: posterPath,
        displayName: displayName,
        durationMs: durationMs,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        nextAttemptAt:
            clearNextAttemptAt ? null : nextAttemptAt ?? this.nextAttemptAt,
        failure: clearFailure ? null : failure ?? this.failure,
        serverTouched: serverTouched ?? this.serverTouched,
        bytesUploaded: bytesUploaded ?? this.bytesUploaded,
        progress: progress ?? this.progress,
      );

  /// What is persisted: ids, a local path and state. Never a URL or token.
  Map<String, Object?> toMap() => {
        'v': 1,
        'id': mediaObjectId,
        'owner': ownerId,
        'offer': offerId,
        'kind': kind.name,
        'contentType': contentType,
        'byteLength': byteLength,
        'localPath': localPath,
        'posterPath': posterPath,
        'displayName': displayName,
        'durationMs': durationMs,
        'state': state.name,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.microsecondsSinceEpoch,
        'failure': failure?.name,
        'serverTouched': serverTouched,
        'bytesUploaded': bytesUploaded,
        'createdAt': createdAt.microsecondsSinceEpoch,
      };

  /// Reads a persisted task; null for anything malformed or unknown.
  static OfferMediaUploadTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String? text(String key) {
      final value = raw[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    int? integer(String key) {
      final value = raw[key];
      return value is int ? value : null;
    }

    T? byName<T extends Enum>(List<T> values, String? name) {
      if (name == null) return null;
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final id = text('id');
    final owner = text('owner');
    final offer = text('offer');
    final kind = byName(OfferMediaKind.values, text('kind'));
    final contentType = text('contentType');
    final byteLength = integer('byteLength');
    final localPath = text('localPath');
    final state = byName(OfferMediaTaskState.values, text('state'));
    final createdAt = integer('createdAt');
    if (raw['v'] != 1 ||
        id == null ||
        owner == null ||
        offer == null ||
        kind == null ||
        contentType == null ||
        byteLength == null ||
        localPath == null ||
        state == null ||
        createdAt == null) {
      return null;
    }
    final next = integer('nextAttemptAt');
    return OfferMediaUploadTask(
      mediaObjectId: id,
      ownerId: owner,
      offerId: offer,
      kind: kind,
      contentType: contentType,
      byteLength: byteLength,
      localPath: localPath,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt),
      posterPath: text('posterPath'),
      displayName: text('displayName'),
      durationMs: integer('durationMs'),
      state: state,
      attempts: integer('attempts') ?? 0,
      nextAttemptAt:
          next == null ? null : DateTime.fromMicrosecondsSinceEpoch(next),
      failure: byName(OfferMediaRejection.values, text('failure')),
      serverTouched: raw['serverTouched'] == true,
      bytesUploaded: raw['bytesUploaded'] == true,
    );
  }
}

/// A queued item the server has now accepted and attached.
@immutable
class OfferMediaUploadCompleted {
  const OfferMediaUploadCompleted({
    required this.ownerId,
    required this.offerId,
    required this.mediaObjectId,
    this.isVideo = false,
    this.durationMs,
  });

  final String ownerId;
  final String offerId;
  final String mediaObjectId;
  final bool isVideo;
  final int? durationMs;
}

/// What [OfferMediaUploadQueue.enqueue] took on.
@immutable
class OfferMediaEnqueueResult {
  const OfferMediaEnqueueResult({
    required this.queued,
    required this.failedIds,
  });

  final List<OfferMediaUploadTask> queued;

  /// Drafts whose file could not be copied into the app's own storage.
  final List<String> failedIds;
}

/// The one Offer media upload manager on this device (Supabase mode).
///
/// Saving an Offer never waits for its media: each new file becomes a task
/// here, persisted with a durable local copy, and uploaded in the background
/// through the Media Worker — one at a time, oldest first, so an Offer's
/// items keep the order they were picked in. Tasks survive an app restart
/// and resume from the step they reached. The legacy Firebase
/// `FastMediaUploadService` is untouched and never sees these tasks: they
/// live in their own Hive box.
///
/// Uploads run only for the account set by [setActiveOwner], which the
/// application session keeps in step (see `OfferMediaSession`): never under
/// a password-recovery or deletion-quarantined session, and never another
/// account's task under the current account's token.
///
/// Uploads run only while the app is in the foreground. Since Android 15 an
/// app outside a valid process lifecycle has no network at all — every
/// request fails at once (device-verified on the Samsung test phone: the
/// app's uid is blocked `APP_BACKGROUND` whenever it is not in front). So the
/// queue starts nothing while the app is in the background, a transfer cut
/// off by leaving the app goes back to waiting without spending one of its
/// automatic retries, and everything resumes when the app returns. Nothing
/// here promises an upload while the app is suspended.
class OfferMediaUploadQueue extends ChangeNotifier with WidgetsBindingObserver {
  OfferMediaUploadQueue({
    OfferMediaTransport Function()? transport,
    String? Function()? currentUserId,
    Future<Box<dynamic>> Function()? openBox,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
    OfflineMediaService? offlineMedia,
    DateTime Function()? now,
    List<Duration>? backoff,
    bool observeLifecycle = true,
  })  : _transportFactory = transport ?? R2OfferMediaUploadService.new,
        _currentUserId = currentUserId ?? _supabaseUserId,
        _openBoxOverride = openBox,
        // The same directory OfflineMediaService adopts originals into and
        // sweeps by owner prefix on account deletion.
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _offlineMediaOverride = offlineMedia,
        _now = now ?? DateTime.now,
        _backoff = backoff ?? defaultBackoff,
        _observeLifecycle = observeLifecycle;

  static OfferMediaUploadQueue? _instance;
  static OfferMediaUploadQueue get instance =>
      _instance ??= OfferMediaUploadQueue();

  @visibleForTesting
  static set debugInstance(OfferMediaUploadQueue? queue) => _instance = queue;

  static const String boxName = 'offer_media_uploads';

  /// Automatic retry delays; after the last, the user's Retry is needed.
  static const List<Duration> defaultBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  static final RegExp _unsafeFileSegment = RegExp(r'[^A-Za-z0-9_-]');

  final OfferMediaTransport Function() _transportFactory;
  final String? Function() _currentUserId;
  final Future<Box<dynamic>> Function()? _openBoxOverride;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final OfflineMediaService? _offlineMediaOverride;
  final DateTime Function() _now;
  final List<Duration> _backoff;
  final bool _observeLifecycle;

  final Map<String, OfferMediaUploadTask> _tasks = {};
  final StreamController<OfferMediaUploadCompleted> _completions =
      StreamController<OfferMediaUploadCompleted>.broadcast();
  OfferMediaTransport? _transport;
  Box<dynamic>? _box;
  Future<void>? _opening;
  String? _activeOwner;
  Future<void>? _draining;
  Timer? _wakeTimer;
  _InFlight? _inFlight;
  bool _observing = false;
  bool _disposed = false;
  DateTime? _lastProgressNotice;
  int _sequence = 0;

  /// Whether the app is in the foreground, where Android lets it use the
  /// network. Starts true: a queue that does not observe the lifecycle (a
  /// test, or before the binding reports) behaves as it always did.
  bool _inForeground = true;

  /// When the app last came back from the background: Android may still be
  /// restoring its network access for a moment afterwards.
  DateTime? _foregroundSince;

  /// The task being processed right now, if any.
  String? _runningId;

  /// A request that fails this soon after returning to the foreground is
  /// treated as the platform restoring network access, not as the item's
  /// failure.
  static const Duration _resumeGrace = Duration(seconds: 5);

  OfflineMediaService get _offlineMedia =>
      _offlineMediaOverride ?? OfflineMediaService.instance;

  OfferMediaTransport get _transportInstance =>
      _transport ??= _transportFactory();

  /// Emits each item the server has accepted.
  Stream<OfferMediaUploadCompleted> get completions => _completions.stream;

  String? get activeOwner => _activeOwner;

  /// Completes when no task is being processed.
  Future<void> get idle => _draining ?? Future<void>.value();

  /// Whether a task is being processed right now.
  @visibleForTesting
  bool get isDraining => _draining != null;

  /// Whether the queue considers the app to be in the foreground.
  bool get isInForeground => _inForeground;

  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Opens the queue's box in the app's documents directory — the directory
  /// `Hive.initFlutter()` makes Hive's home — named explicitly, so a device
  /// without it fails here as an ordinary error rather than inside Hive,
  /// which also reports a failed open as an error nobody can handle.
  Future<Box<dynamic>> _openDefaultBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    final directory = await _documentsDirectory();
    return Hive.openBox(boxName, path: directory.path);
  }

  /// Loads persisted tasks. Safe to call repeatedly.
  Future<void> ensureOpen() async {
    if (_box != null) return;
    _opening ??= () async {
      final box = await (_openBoxOverride ?? _openDefaultBox)();
      for (final key in box.keys.toList()) {
        final task = OfferMediaUploadTask.fromMap(box.get(key));
        if (task == null) {
          await box.delete(key);
          continue;
        }
        _tasks[task.mediaObjectId] = task;
      }
      // Before the box is published, so no enqueue can be copying a file
      // the sweep would take for an orphan.
      await _sweepRetiredCopies();
      _box = box;
    }();
    try {
      await _opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  /// Visible tasks of [ownerId] for [offerId], oldest first. Synchronous.
  List<OfferMediaUploadTask> tasksFor({
    required String? ownerId,
    required String? offerId,
  }) {
    if (ownerId == null || offerId == null) return const [];
    final tasks = _tasks.values
        .where((task) =>
            task.ownerId == ownerId &&
            task.offerId == offerId &&
            task.state != OfferMediaTaskState.cancelling)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks;
  }

  /// [tasksFor], as the refs the Offer media UI draws.
  List<OfferMediaRef> pendingRefsFor({
    required String? ownerId,
    required String? offerId,
  }) =>
      [
        for (final task in tasksFor(ownerId: ownerId, offerId: offerId))
          task.toRef(running: task.mediaObjectId == _runningId),
      ];

  /// Sets which account may upload. Null pauses everything; a different
  /// account's in-flight transfer is stopped before its next step.
  void setActiveOwner(String? ownerId) {
    final owner = ownerId == null || ownerId.trim().isEmpty ? null : ownerId;
    if (owner == _activeOwner) return;
    _activeOwner = owner;
    final inFlight = _inFlight;
    if (inFlight != null && inFlight.ownerId != owner) inFlight.cancel();
    _wakeTimer?.cancel();
    if (owner != null) unawaited(_activate());
    if (!_disposed) notifyListeners();
  }

  Future<void> _activate() async {
    try {
      await ensureOpen();
    } catch (_) {
      return; // No storage: nothing persisted can run; enqueue will report it.
    }
    _startObserving();
    final owner = _activeOwner;
    if (owner != null) await _resumeTransient(owner);
    await _drain();
  }

  /// A new chance for everything that failed only for a reason that can
  /// pass: an item whose automatic retries ran out on a lost connection is
  /// queued again, and a scheduled retry runs now. Called when the app starts
  /// (or the account signs in) and when it returns from the background —
  /// the moments conditions most likely changed. Refusals, a full Offer and
  /// a missing file are left for the user.
  Future<void> _resumeTransient(String owner) async {
    final waiting = _tasks.values
        .where((task) =>
            task.ownerId == owner &&
            (task.state == OfferMediaTaskState.retryWait ||
                (task.state == OfferMediaTaskState.needsRetry &&
                    (task.failure == null ||
                        task.failure == OfferMediaRejection.interrupted))))
        .toList();
    for (final task in waiting) {
      OfferMediaDiagnostics.log('resume', id: task.mediaObjectId, fields: {
        'from': task.state.name,
        'attempts': task.attempts,
      });
      await _write(task.state == OfferMediaTaskState.needsRetry
          ? task.copyWith(
              state: OfferMediaTaskState.queued,
              attempts: 0,
              clearNextAttemptAt: true,
              clearFailure: true,
            )
          : task.copyWith(clearNextAttemptAt: true));
    }
  }

  /// Takes [drafts] on for [offerId]: copies each file into app-owned storage
  /// and persists a task, then starts uploading. Idempotent per
  /// `mediaObjectId`: a draft already queued is not queued again.
  Future<OfferMediaEnqueueResult> enqueue({
    required String ownerId,
    required String offerId,
    required List<OfferMediaDraft> drafts,
  }) async {
    await ensureOpen();
    // A file named by more than one draft (the same file picked twice) is
    // copied for each rather than moved away from the next.
    final uses = <String, int>{};
    for (final draft in drafts) {
      for (final path in [draft.path, draft.posterPath]) {
        if (path != null) uses[path] = (uses[path] ?? 0) + 1;
      }
    }
    bool movable(String path) => (uses[path] ?? 0) < 2;

    final queued = <OfferMediaUploadTask>[];
    final failedIds = <String>[];
    for (final draft in drafts) {
      final existing = _tasks[draft.mediaObjectId];
      if (existing != null) {
        queued.add(existing);
        continue;
      }
      try {
        final localPath = await _takeDurableCopy(
          ownerId,
          draft.mediaObjectId,
          draft.path,
          suffix: '_pending',
          allowMove: movable(draft.path),
        );
        String? posterPath;
        final poster = draft.posterPath;
        if (poster != null && await File(poster).exists()) {
          try {
            posterPath = await _takeDurableCopy(
              ownerId,
              draft.mediaObjectId,
              poster,
              suffix: '_pending_poster',
              allowMove: movable(poster),
            );
          } catch (_) {
            posterPath = null; // A missing preview never blocks the upload.
          }
        }
        final task = OfferMediaUploadTask(
          mediaObjectId: draft.mediaObjectId,
          ownerId: ownerId,
          offerId: offerId,
          kind: draft.kind,
          contentType: draft.contentType,
          byteLength: draft.byteLength,
          localPath: localPath,
          posterPath: posterPath,
          displayName: draft.displayName,
          durationMs: draft.durationMs,
          // Strictly increasing, so a batch keeps the order it was picked in.
          createdAt: _now().add(Duration(microseconds: _sequence++)),
        );
        _tasks[task.mediaObjectId] = task;
        await _box!.put(task.mediaObjectId, task.toMap());
        queued.add(task);
        OfferMediaDiagnostics.log('enqueued', id: task.mediaObjectId, fields: {
          'kind': task.kind.name,
          'type': task.contentType,
          'bytes': task.byteLength,
          'durationMs': task.durationMs,
          'poster': task.posterPath != null,
        });
      } catch (error) {
        OfferMediaDiagnostics.log('enqueue-failed',
            id: draft.mediaObjectId,
            fields: {'cause': OfferMediaDiagnostics.categorize(error)});
        failedIds.add(draft.mediaObjectId);
      }
    }
    if (!_disposed) notifyListeners();
    unawaited(_drain());
    return OfferMediaEnqueueResult(queued: queued, failedIds: failedIds);
  }

  /// The user's Retry for an item that failed for a reason that can pass.
  Future<void> retry(String mediaObjectId) async {
    final task = _tasks[mediaObjectId];
    if (task == null || !task.isRetryable) return;
    await _write(task.copyWith(
      state: OfferMediaTaskState.queued,
      attempts: 0,
      clearNextAttemptAt: true,
      clearFailure: true,
    ));
    unawaited(_drain());
  }

  /// The user removed a queued item. Its upload stops, and any row the
  /// server already holds for it is withdrawn so it no longer takes a place.
  Future<void> cancel(String mediaObjectId) async {
    final task = _tasks[mediaObjectId];
    if (task == null || task.state == OfferMediaTaskState.cancelling) return;
    await _write(task.copyWith(
      state: OfferMediaTaskState.cancelling,
      attempts: 0,
      clearNextAttemptAt: true,
    ));
    final inFlight = _inFlight;
    if (inFlight != null && inFlight.mediaObjectId == mediaObjectId) {
      inFlight.cancel();
    }
    unawaited(_drain());
  }

  /// A place on [offerId] was freed: items that found the Offer full try
  /// again, in the order they were picked.
  Future<void> releaseBlocked({
    required String ownerId,
    required String offerId,
  }) async {
    final waiting = _tasks.values
        .where((task) =>
            task.ownerId == ownerId &&
            task.offerId == offerId &&
            task.state == OfferMediaTaskState.blocked)
        .toList();
    if (waiting.isEmpty) return;
    for (final task in waiting) {
      await _write(task.copyWith(
        state: OfferMediaTaskState.queued,
        clearFailure: true,
      ));
    }
    unawaited(_drain());
  }

  /// The Offer itself was deleted: its tasks and their files go, with no
  /// server call. Whatever the server held is removed by its own cleanup.
  Future<void> forgetOffer({
    required String ownerId,
    required String offerId,
  }) async {
    try {
      await ensureOpen();
    } catch (_) {
      return;
    }
    final doomed = _tasks.values
        .where((task) => task.ownerId == ownerId && task.offerId == offerId)
        .toList();
    for (final task in doomed) {
      _cancelInFlightFor(task.mediaObjectId);
      await _drop(task);
    }
  }

  /// Account deletion: every task of [ownerId] and its files go.
  /// Returns how many tasks could not be removed completely.
  Future<int> purgeOwner(String ownerId) async {
    try {
      await ensureOpen();
    } catch (_) {
      return 1;
    }
    var failures = 0;
    final doomed =
        _tasks.values.where((task) => task.ownerId == ownerId).toList();
    for (final task in doomed) {
      _cancelInFlightFor(task.mediaObjectId);
      if (!await _drop(task)) failures += 1;
    }
    return failures;
  }

  void _cancelInFlightFor(String mediaObjectId) {
    final inFlight = _inFlight;
    if (inFlight != null && inFlight.mediaObjectId == mediaObjectId) {
      inFlight.cancel();
    }
  }

  // -------------------------------------------------------------------------
  // Processing
  // -------------------------------------------------------------------------

  Future<void> _drain() {
    final running = _draining;
    if (running != null) return running;
    final future = _drainLoop();
    _draining = future;
    return future.whenComplete(() {
      _draining = null;
      _armWakeTimer();
    });
  }

  Future<void> _drainLoop() async {
    _wakeTimer?.cancel();
    while (!_disposed) {
      final owner = _activeOwner;
      if (owner == null || _box == null) return;
      // No network while the app is in the background: resumed on return.
      if (!_inForeground) return;
      // The session may already belong to someone else while the change is
      // still on its way here: never run a task under another account.
      if (_currentUserId() != owner) return;
      final task = _nextRunnable(owner);
      if (task == null) return;
      _runningId = task.mediaObjectId;
      final bool progressed;
      try {
        progressed = await _run(task, owner);
      } finally {
        _runningId = null;
      }
      if (!progressed) {
        if (!_disposed) notifyListeners();
        return;
      }
    }
  }

  OfferMediaUploadTask? _nextRunnable(String owner) {
    final now = _now();
    final runnable = _tasks.values
        .where((task) => task.ownerId == owner && _isDue(task, now))
        .toList()
      ..sort((a, b) {
        // Withdrawals first: they free places the next uploads may need.
        final aCancel = a.state == OfferMediaTaskState.cancelling ? 0 : 1;
        final bCancel = b.state == OfferMediaTaskState.cancelling ? 0 : 1;
        if (aCancel != bCancel) return aCancel - bCancel;
        return a.createdAt.compareTo(b.createdAt);
      });
    return runnable.isEmpty ? null : runnable.first;
  }

  bool _isDue(OfferMediaUploadTask task, DateTime now) {
    switch (task.state) {
      case OfferMediaTaskState.queued:
      case OfferMediaTaskState.authorizing:
      case OfferMediaTaskState.uploading:
      case OfferMediaTaskState.confirming:
        return true;
      case OfferMediaTaskState.retryWait:
      case OfferMediaTaskState.cancelling:
        final at = task.nextAttemptAt;
        return at == null || !at.isAfter(now);
      case OfferMediaTaskState.needsRetry:
      case OfferMediaTaskState.blocked:
      case OfferMediaTaskState.failed:
        return false;
    }
  }

  bool _mayCall(String owner) =>
      !_disposed &&
      _inForeground &&
      _activeOwner == owner &&
      _currentUserId() == owner;

  /// Whether a transport failure right now is explained by the app's
  /// lifecycle — it is in the background, or has only just come back —
  /// rather than by the item or the network.
  bool _interruptedByLifecycle() {
    if (!_inForeground) return true;
    final since = _foregroundSince;
    return since != null && _now().difference(since) < _resumeGrace;
  }

  /// Puts [id] back to waiting after a transfer the app's lifecycle cut off,
  /// without spending an automatic retry. Returns false so the drain stops:
  /// the next items would only fail the same way.
  Future<bool> _pauseForLifecycle(
    String id,
    _Stage stage,
    String? cause,
    Stopwatch clock,
  ) async {
    OfferMediaDiagnostics.log('paused', id: id, fields: {
      'stage': stage.name,
      'cause': cause,
      'foreground': _inForeground,
      'elapsedMs': clock.elapsedMilliseconds,
    });
    await _settle(
      id,
      (t) => _inForeground
          // Just back: Android may still be restoring network access.
          ? t.copyWith(
              state: OfferMediaTaskState.retryWait,
              nextAttemptAt: _now().add(const Duration(seconds: 2)),
            )
          : t.copyWith(
              state: OfferMediaTaskState.queued,
              clearNextAttemptAt: true,
              clearFailure: true,
            ),
    );
    return false;
  }

  /// Runs [task] as far as it can go. False when nothing could be attempted
  /// (the session changed), so the drain stops instead of spinning.
  Future<bool> _run(OfferMediaUploadTask task, String owner) async {
    if (task.state == OfferMediaTaskState.cancelling) {
      return _withdraw(task, owner);
    }
    final id = task.mediaObjectId;
    final file = File(task.localPath);
    if (!await file.exists()) {
      await _settle(
          id,
          (t) => t.copyWith(
                state: OfferMediaTaskState.failed,
                failure: OfferMediaRejection.fileMissing,
              ));
      return true;
    }
    if (!_mayCall(owner)) return false;

    final transport = _transportInstance;
    var stage = _Stage.authorize;
    final total = Stopwatch()..start();
    final step = Stopwatch()..start();
    OfferMediaDiagnostics.log('start', id: id, fields: {
      'kind': task.kind.name,
      'bytes': task.byteLength,
      'attempt': task.attempts + 1,
      'resume': task.bytesUploaded ? 'confirm' : 'authorize',
    });
    try {
      if (!task.bytesUploaded) {
        final authorizing = await _settle(
          id,
          (t) => t.copyWith(
            state: OfferMediaTaskState.authorizing,
            serverTouched: true,
          ),
        );
        if (authorizing == null) return true;
        final authorization = await transport.authorizeUpload(
          offerId: task.offerId,
          mediaObjectId: id,
          contentType: task.contentType,
          contentLength: task.byteLength,
          originalFileName: task.displayName,
        );
        OfferMediaDiagnostics.log('authorized', id: id, fields: {
          'elapsedMs': step.elapsedMilliseconds,
          'alreadyReady': authorization.isAlreadyReady,
        });
        if (authorization.isAlreadyReady) {
          await _complete(id, owner);
          return true;
        }
        if (!_mayCall(owner)) {
          // Left the app between the steps: nothing was sent yet.
          await _settle(
            id,
            (t) => t.copyWith(state: OfferMediaTaskState.queued),
          );
          return false;
        }

        stage = _Stage.upload;
        final uploading = await _settle(
          id,
          (t) => t.copyWith(state: OfferMediaTaskState.uploading, progress: 0),
        );
        if (uploading == null) return true;
        final inFlight = _InFlight(id, owner);
        _inFlight = inFlight;
        step.reset();
        try {
          await transport.uploadBytes(
            presignedUrl: authorization.presignedUrl!,
            file: file,
            contentType: task.contentType,
            length: task.byteLength,
            onProgress: (sent, total) => _onProgress(id, sent, total),
            cancel: inFlight.cancelled,
          );
        } finally {
          if (identical(_inFlight, inFlight)) _inFlight = null;
        }
        final putMs = step.elapsedMilliseconds;
        OfferMediaDiagnostics.log('put-done', id: id, fields: {
          'bytes': task.byteLength,
          'elapsedMs': putMs,
          'kbps': putMs <= 0 ? null : (task.byteLength * 8 / putMs).round(),
        });
        final uploaded = await _settle(
          id,
          (t) => t.copyWith(
            state: OfferMediaTaskState.confirming,
            bytesUploaded: true,
            progress: 1,
          ),
        );
        if (uploaded == null) return true;
      } else {
        final confirming = await _settle(
          id,
          (t) => t.copyWith(state: OfferMediaTaskState.confirming),
        );
        if (confirming == null) return true;
      }

      stage = _Stage.confirm;
      if (!_mayCall(owner)) return false;
      step.reset();
      final confirmation = await transport.confirmUpload(
        offerId: task.offerId,
        mediaObjectId: id,
      );
      OfferMediaDiagnostics.log('confirmed', id: id, fields: {
        'elapsedMs': step.elapsedMilliseconds,
        'totalMs': total.elapsedMilliseconds,
        'alreadyConfirmed': confirmation.alreadyConfirmed,
      });
      await _complete(id, owner);
      return true;
    } on OfferMediaRejectedException catch (error) {
      if (_activeOwner != owner) return false;
      if (error.rejection == OfferMediaRejection.interrupted &&
          _interruptedByLifecycle()) {
        return _pauseForLifecycle(id, stage, error.cause, total);
      }
      _logFailure(id, stage, error.cause ?? error.rejection.name, total);
      await _onRefused(id, error.rejection, stage);
      return true;
    } on R2OfferMediaHttpException catch (error) {
      // The server answered, so the network works: never a lifecycle pause.
      if (_activeOwner != owner) return false;
      _logFailure(id, stage, '${error.cause}:${error.code}', total);
      await _onHttpFailure(id, owner, error, stage);
      return true;
    } catch (error) {
      if (_activeOwner != owner) return false;
      final cause = error is R2UploadException
          ? error.cause
          : OfferMediaDiagnostics.categorize(error);
      if (_interruptedByLifecycle()) {
        return _pauseForLifecycle(id, stage, cause, total);
      }
      _logFailure(id, stage, cause, total);
      await _retryLater(id, OfferMediaRejection.interrupted);
      return true;
    }
  }

  void _logFailure(String id, _Stage stage, String? cause, Stopwatch clock) {
    OfferMediaDiagnostics.log('failed', id: id, fields: {
      'stage': stage.name,
      'cause': cause,
      'elapsedMs': clock.elapsedMilliseconds,
    });
  }

  Future<void> _onRefused(
    String id,
    OfferMediaRejection rejection,
    _Stage stage,
  ) async {
    if (rejection == OfferMediaRejection.interrupted) {
      // The transfer stopped; the same id is simply uploaded again.
      await _retryLater(id, rejection, restartUpload: true);
    } else if (rejection == OfferMediaRejection.limitReached &&
        stage == _Stage.authorize) {
      // Nothing was created: the item can still go on once a place frees.
      await _settle(
          id,
          (t) => t.copyWith(
                state: OfferMediaTaskState.blocked,
                failure: rejection,
              ));
    } else {
      await _settle(
          id,
          (t) => t.copyWith(
                state: OfferMediaTaskState.failed,
                failure: rejection,
              ));
    }
  }

  Future<void> _onHttpFailure(
    String id,
    String owner,
    R2OfferMediaHttpException error,
    _Stage stage,
  ) async {
    final code = error.code;
    if (error.isUnauthenticated) {
      // A session problem, not the item's: wait without using up retries.
      await _settle(
          id,
          (t) => t.copyWith(
                state: OfferMediaTaskState.retryWait,
                nextAttemptAt: _now().add(const Duration(seconds: 15)),
              ));
    } else if (code == 'upload_incomplete' ||
        (code == 'media_not_found' && stage == _Stage.confirm)) {
      // The server has no bytes (or no row) for this id: send them again.
      await _retryLater(id, OfferMediaRejection.interrupted,
          restartUpload: true);
    } else if (code == 'deletion_in_progress') {
      await _settle(
          id,
          (t) => t.copyWith(
                state: OfferMediaTaskState.retryWait,
                nextAttemptAt: _now().add(const Duration(minutes: 10)),
              ));
    } else if (error.statusCode == 404 && _currentUserId() == owner) {
      // Authoritative for this account: the Offer is gone. Nothing to show.
      final task = _tasks[id];
      if (task != null) await _drop(task);
    } else {
      await _retryLater(id, OfferMediaRejection.interrupted);
    }
  }

  Future<void> _retryLater(
    String id,
    OfferMediaRejection reason, {
    bool restartUpload = false,
  }) async {
    await _settle(id, (t) {
      final attempts = t.attempts + 1;
      final exhausted = attempts > _backoff.length;
      OfferMediaDiagnostics.log(exhausted ? 'needs-retry' : 'retry-scheduled',
          id: id,
          fields: {
            'attempts': attempts,
            'reason': reason.name,
            'delayMs': exhausted ? null : _backoff[attempts - 1].inMilliseconds,
          });
      if (exhausted) {
        return t.copyWith(
          state: OfferMediaTaskState.needsRetry,
          attempts: attempts,
          failure: reason,
          clearNextAttemptAt: true,
          bytesUploaded: restartUpload ? false : null,
        );
      }
      return t.copyWith(
        state: OfferMediaTaskState.retryWait,
        attempts: attempts,
        failure: reason,
        nextAttemptAt: _now().add(_backoff[attempts - 1]),
        bytesUploaded: restartUpload ? false : null,
      );
    });
  }

  /// Withdraws a removed item. True when it could be attempted.
  Future<bool> _withdraw(OfferMediaUploadTask task, String owner) async {
    if (!task.serverTouched) {
      await _drop(task);
      return true;
    }
    if (!_mayCall(owner)) return false;
    try {
      await _transportInstance.removeMedia(
        offerId: task.offerId,
        mediaObjectId: task.mediaObjectId,
      );
      // It may have become ready (and adopted) just before the removal.
      await _offlineMedia.forgetOfferMediaItems(
        ownerId: owner,
        mediaObjectIds: [task.mediaObjectId],
      );
      await _drop(task);
      await releaseBlocked(ownerId: owner, offerId: task.offerId);
    } on R2OfferMediaHttpException catch (error) {
      if (error.statusCode == 404 && _currentUserId() == owner) {
        await _drop(task); // The Offer is gone; the server cleans up its own.
      } else {
        await _withdrawLater(task);
      }
    } on OfferMediaRejectedException {
      // Nothing of ours to withdraw under this id.
      await _drop(task);
    } catch (_) {
      await _withdrawLater(task);
    }
    return true;
  }

  Future<void> _withdrawLater(OfferMediaUploadTask task) async {
    final attempts = task.attempts + 1;
    final delay = _backoff[(attempts - 1).clamp(0, _backoff.length - 1)];
    await _write(task.copyWith(
      attempts: attempts,
      nextAttemptAt: _now().add(delay),
    ));
  }

  /// The server accepted the item: keep its bytes as the local copy under its
  /// stable identity (images; a video keeps only its still frame), remember
  /// it for the Offer, and retire the task.
  ///
  /// A video's own local copy is not deleted here: it may be playing from
  /// that file at this very moment. It is retired instead and removed the
  /// next time the queue opens (see [_sweepRetiredCopies]); it keeps the
  /// account's file-name prefix, so the account-deletion sweep removes it
  /// too. It is never adopted as a cached copy of the server video.
  Future<void> _complete(String id, String owner) async {
    final task = _tasks[id];
    if (task == null || task.state == OfferMediaTaskState.cancelling) {
      return; // Removed meanwhile: the withdrawal removes the attached item.
    }
    final cacheKey = offerMediaCacheKey(ownerId: owner, mediaObjectId: id);
    if (cacheKey != null) {
      try {
        if (task.kind == OfferMediaKind.image) {
          await _offlineMedia.adoptLocalFileForMediaId(
            cacheKey,
            task.localPath,
            directoryName: OfflineMediaService.offerMediaDirectoryName,
          );
        } else if (task.posterPath != null) {
          await _offlineMedia.adoptLocalFileForMediaId(
            offerMediaPosterKey(cacheKey),
            task.posterPath!,
            directoryName: OfflineMediaService.offerMediaDirectoryName,
          );
        }
        await _offlineMedia.appendToOfferMediaCatalog(
          ownerId: owner,
          offerId: task.offerId,
          mediaObjectId: id,
        );
      } catch (_) {
        // Best effort: without it the item is downloaded once, not lost.
      }
    }
    // Announced before the task goes, so a screen can show the item as the
    // server item it now is without a frame in which it is neither.
    if (!_disposed) {
      _completions.add(OfferMediaUploadCompleted(
        ownerId: owner,
        offerId: task.offerId,
        mediaObjectId: id,
        isVideo: task.kind == OfferMediaKind.video,
        durationMs: task.durationMs,
      ));
    }
    await _drop(task, retireVideoCopy: true);
  }

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------

  /// Applies [change] to the stored task unless the user removed it
  /// meanwhile; a removal always wins. Returns the new task, or null.
  Future<OfferMediaUploadTask?> _settle(
    String id,
    OfferMediaUploadTask Function(OfferMediaUploadTask task) change,
  ) async {
    final current = _tasks[id];
    if (current == null || current.state == OfferMediaTaskState.cancelling) {
      return null;
    }
    final next = change(current);
    await _write(next);
    return next;
  }

  Future<void> _write(OfferMediaUploadTask task) async {
    _tasks[task.mediaObjectId] = task;
    try {
      await _box?.put(task.mediaObjectId, task.toMap());
    } catch (_) {
      // The in-memory state still drives this session.
    }
    if (!_disposed) notifyListeners();
  }

  /// Removes a task and its app-owned files. True when nothing was left.
  ///
  /// With [retireVideoCopy], a video's own local copy stays on disk until the
  /// queue next opens (see [_complete]).
  Future<bool> _drop(
    OfferMediaUploadTask task, {
    bool retireVideoCopy = false,
  }) async {
    _tasks.remove(task.mediaObjectId);
    var clean = true;
    try {
      await _box?.delete(task.mediaObjectId);
    } catch (_) {
      clean = false;
    }
    final keep = retireVideoCopy && task.kind == OfferMediaKind.video
        ? task.localPath
        : null;
    for (final path in [task.localPath, task.posterPath]) {
      if (path == null || path == keep || !_isAppOwned(path)) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        clean = false;
      }
    }
    if (!_disposed) notifyListeners();
    return clean;
  }

  void _onProgress(String id, int sent, int total) {
    final task = _tasks[id];
    if (task == null || task.state != OfferMediaTaskState.uploading) return;
    final fraction = total <= 0 ? 0.0 : (sent / total).clamp(0.0, 1.0);
    _tasks[id] = task.copyWith(progress: fraction);
    final now = _now();
    final last = _lastProgressNotice;
    if (fraction >= 1 ||
        last == null ||
        now.difference(last) >= const Duration(milliseconds: 150)) {
      _lastProgressNotice = now;
      if (!_disposed) notifyListeners();
    }
  }

  /// Copies [source] into the backup-excluded `offer_media` directory under
  /// the owner's file-name prefix, which is what the account-deletion sweep
  /// removes. A file in the app's own temporary directory (where the pickers
  /// leave their copies) is moved instead of copied: a 100 MB video is then
  /// not duplicated. Anything else is copied and never touched.
  Future<String> _takeDurableCopy(
    String ownerId,
    String mediaObjectId,
    String source, {
    required String suffix,
    bool allowMove = true,
  }) async {
    final cacheKey =
        offerMediaCacheKey(ownerId: ownerId, mediaObjectId: mediaObjectId);
    if (cacheKey == null) throw ArgumentError('owner and media id required');
    final directory = Directory(
      '${(await _documentsDirectory()).path}/'
      '${OfflineMediaService.offerMediaDirectoryName}',
    );
    await directory.create(recursive: true);
    final name = source.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 ? name.substring(dot).toLowerCase() : '';
    final target = File(
      '${directory.path}/'
      '${cacheKey.replaceAll(_unsafeFileSegment, '_')}$suffix$extension',
    );
    if (await target.exists()) return target.path;

    final file = File(source);
    var inTemporary = false;
    if (allowMove) {
      try {
        final temporary = (await _temporaryDirectory()).path;
        inTemporary = _isInside(file.path, temporary);
      } catch (_) {
        inTemporary = false;
      }
    }
    if (inTemporary) {
      try {
        return (await file.rename(target.path)).path;
      } on FileSystemException {
        // A different volume: fall back to copying.
      }
    }
    return (await file.copy(target.path)).path;
  }

  /// Removes the queue's own copies that no task refers to any more: videos
  /// retired after their upload (see [_complete]) and anything an
  /// interrupted run left behind. Only `_pending` copies in the queue's
  /// directory are candidates, so an adopted original is never touched, and
  /// a copy any task — of any account on this device — still names is kept.
  Future<void> _sweepRetiredCopies() async {
    try {
      final directory = Directory(
        '${(await _documentsDirectory()).path}/'
        '${OfflineMediaService.offerMediaDirectoryName}',
      );
      if (!await directory.exists()) return;
      String normalize(String path) => path.replaceAll('\\', '/');
      final referenced = <String>{
        for (final task in _tasks.values) ...[
          normalize(task.localPath),
          if (task.posterPath != null) normalize(task.posterPath!),
        ],
      };
      var removed = 0;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) continue;
        final path = normalize(entry.path);
        final name = path.split('/').last;
        if (!name.contains('_pending') || referenced.contains(path)) continue;
        try {
          await entry.delete();
          removed += 1;
        } catch (_) {
          // Retried on the next open.
        }
      }
      if (removed > 0) {
        OfferMediaDiagnostics.log('retired-copies-removed',
            fields: {'count': removed});
      }
    } catch (_) {
      // Housekeeping only: never blocks the queue from opening.
    }
  }

  static bool _isInside(String path, String directory) {
    final normalizedPath = path.replaceAll('\\', '/');
    var normalizedDirectory = directory.replaceAll('\\', '/');
    if (!normalizedDirectory.endsWith('/')) normalizedDirectory += '/';
    return normalizedPath.startsWith(normalizedDirectory);
  }

  static bool _isAppOwned(String path) => path
      .replaceAll('\\', '/')
      .contains('/${OfflineMediaService.offerMediaDirectoryName}/');

  // -------------------------------------------------------------------------
  // Scheduling
  // -------------------------------------------------------------------------

  void _armWakeTimer() {
    _wakeTimer?.cancel();
    final owner = _activeOwner;
    // In the background a timer could only fire into a blocked network (or
    // not at all, once Android freezes the app): the return resumes instead.
    if (_disposed || owner == null || !_inForeground) return;
    DateTime? earliest;
    for (final task in _tasks.values) {
      if (task.ownerId != owner) continue;
      if (task.state != OfferMediaTaskState.retryWait &&
          task.state != OfferMediaTaskState.cancelling) {
        continue;
      }
      final at = task.nextAttemptAt;
      if (at == null) continue;
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    if (earliest == null) return;
    final delay = earliest.difference(_now());
    _wakeTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_drain()),
    );
  }

  void _startObserving() {
    if (!_observeLifecycle || _observing) return;
    try {
      final binding = WidgetsBinding.instance;
      binding.addObserver(this);
      _observing = true;
      final current = binding.lifecycleState;
      if (current != null && _isBackground(current)) _inForeground = false;
    } catch (_) {
      // No binding (e.g. a plain Dart test): resume on the other triggers.
    }
  }

  static bool _isBackground(AppLifecycleState state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;

  /// Follows the app in and out of the foreground. `inactive` changes
  /// nothing: it is the brief state on the way in either direction (and
  /// while a system sheet covers the app), during which it keeps its network.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final returning = !_inForeground;
      _inForeground = true;
      if (returning) {
        _foregroundSince = _now();
        OfferMediaDiagnostics.log('lifecycle', fields: {'state': 'foreground'});
        unawaited(_resumeAfterBackground());
      } else {
        unawaited(_drain());
      }
    } else if (_isBackground(state) && _inForeground) {
      _inForeground = false;
      _wakeTimer?.cancel();
      OfferMediaDiagnostics.log('lifecycle', fields: {
        'state': 'background',
        'inFlight': _inFlight == null ? null : 'yes',
      });
      // A transfer already under way is left to finish if Android allows it;
      // if it is cut off, it goes back to waiting (see _pauseForLifecycle).
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _resumeAfterBackground() async {
    final owner = _activeOwner;
    if (owner != null && _box != null) await _resumeTransient(owner);
    await _drain();
  }

  @override
  void dispose() {
    _disposed = true;
    _wakeTimer?.cancel();
    _inFlight?.cancel();
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    unawaited(_completions.close());
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }
}

enum _Stage { authorize, upload, confirm }

class _InFlight {
  _InFlight(this.mediaObjectId, this.ownerId);

  final String mediaObjectId;
  final String ownerId;
  final Completer<void> _cancel = Completer<void>();

  Future<void> get cancelled => _cancel.future;

  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }
}
