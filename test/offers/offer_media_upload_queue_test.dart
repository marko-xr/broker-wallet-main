import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// The persistent Offer media upload queue, end to end against a fake Media
/// Worker that behaves like the real one: every step is idempotent on the
/// app-generated `mediaObjectId`, authorize creates at most one row per id,
/// and the Offer holds at most ten items.
///
/// Local only: the Worker, R2 and Supabase are simulated. Nothing here is
/// hosted, device or runtime verification.

const _ownerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ownerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _offer = 'o0000000-0000-4000-8000-000000000001';
const _otherOffer = 'o0000000-0000-4000-8000-000000000002';

late Directory _root;
late Directory _docs;
late Directory _tmp;
late Directory _elsewhere;
var _boxSeq = 0;
var _idSeq = 0;

String _id() {
  _idSeq += 1;
  return 'm${_idSeq.toString().padLeft(7, '0')}-0000-4000-8000-000000000000';
}

class _Lost implements Exception {
  const _Lost();
}

/// A Media Worker, R2 bucket and `media_objects` table in one, in memory.
class _FakeWorker implements OfferMediaTransport {
  static const int limit = OfferMediaPolicy.maxItemsPerOffer;
  final Map<String, String> status = {}; // id -> pending | ready | failed
  final Map<String, String> offerOf = {};
  final Map<String, List<int>> stored = {};
  final List<String> log = [];
  int rowsCreated = 0;

  final Map<String, List<Object>> _failures = {};
  final Set<String> _lostAnswers = {};

  /// The next [step] call for [id] throws [error] and changes nothing.
  void failNext(String step, String id, Object error) =>
      (_failures['$step:$id'] ??= <Object>[]).add(error);

  /// The next [step] call for [id] takes effect but its answer never arrives.
  void loseNextAnswer(String step, String id) => _lostAnswers.add('$step:$id');

  int count(String step, String id) =>
      log.where((entry) => entry == '$step:$id').length;

  void seedReady(String offerId, int n) {
    for (var i = 0; i < n; i++) {
      final id = 'seed-$offerId-$i';
      status[id] = 'ready';
      offerOf[id] = offerId;
    }
  }

  /// Runs at the start of every step, before any failure is thrown — e.g.
  /// to move the app to the background exactly while a transfer runs.
  void Function(String step, String id)? beforeStep;

  void _maybeFail(String step, String id) {
    beforeStep?.call(step, id);
    final queued = _failures['$step:$id'];
    if (queued != null && queued.isNotEmpty) throw queued.removeAt(0);
  }

  void _maybeLose(String step, String id) {
    if (_lostAnswers.remove('$step:$id')) throw const _Lost();
  }

  @override
  Future<OfferMediaAuthorization> authorizeUpload({
    required String offerId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    final id = mediaObjectId;
    log.add('authorize:$id');
    _maybeFail('authorize', id);
    final current = status[id];
    if (current == 'ready') {
      return OfferMediaAuthorization.ready(mediaObjectId: id);
    }
    if (current == 'failed') {
      throw const OfferMediaRejectedException(OfferMediaRejection.rejected);
    }
    if (current == null) {
      final used = status.entries
          .where((e) =>
              offerOf[e.key] == offerId &&
              (e.value == 'ready' || e.value == 'pending'))
          .length;
      if (used >= limit) {
        throw const OfferMediaRejectedException(
            OfferMediaRejection.limitReached);
      }
      status[id] = 'pending';
      offerOf[id] = offerId;
      rowsCreated += 1;
    }
    _maybeLose('authorize', id);
    return OfferMediaAuthorization.pending(
      mediaObjectId: id,
      presignedUrl: 'https://r2.example.test/put/$id',
    );
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
    required int length,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Future<void>? cancel,
  }) async {
    final id = presignedUrl.split('/').last;
    log.add('upload:$id');
    _maybeFail('upload', id);
    final bytes = await file.readAsBytes();
    onProgress?.call(bytes.length ~/ 2, length);
    onProgress?.call(bytes.length, length);
    stored[id] = bytes;
    _maybeLose('upload', id);
  }

  @override
  Future<OfferMediaConfirmation> confirmUpload({
    required String offerId,
    required String mediaObjectId,
  }) async {
    final id = mediaObjectId;
    log.add('confirm:$id');
    _maybeFail('confirm', id);
    if (status[id] == 'ready') {
      _maybeLose('confirm', id);
      return const OfferMediaConfirmation(alreadyConfirmed: true);
    }
    if (status[id] == null) {
      throw R2OfferMediaHttpException(404, code: 'media_not_found');
    }
    if (stored[id] == null) {
      throw R2OfferMediaHttpException(409, code: 'upload_incomplete');
    }
    status[id] = 'ready';
    _maybeLose('confirm', id);
    return const OfferMediaConfirmation(ordinal: 0);
  }

  @override
  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  }) async {
    final id = mediaObjectId;
    log.add('remove:$id');
    _maybeFail('remove', id);
    final existed = status.remove(id) != null;
    stored.remove(id);
    return OfferMediaRemoval(alreadyRemoved: !existed);
  }
}

class _Harness {
  _Harness({
    String? boxName,
    List<Duration> backoff = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    _FakeWorker? worker,
  })  : boxName = boxName ?? 'offer_queue_test_${_boxSeq++}',
        worker = worker ?? _FakeWorker() {
    queue = OfferMediaUploadQueue(
      transport: () => this.worker,
      currentUserId: () => sessionUid,
      openBox: () => Hive.openBox<dynamic>(this.boxName),
      documentsDirectory: () async => _docs,
      temporaryDirectory: () async => _tmp,
      offlineMedia: OfflineMediaService.instance,
      backoff: backoff,
      observeLifecycle: false,
    );
    completions = [];
    _subscription = queue.completions.listen(completions.add);
  }

  final String boxName;
  final _FakeWorker worker;
  late final OfferMediaUploadQueue queue;
  late final List<OfferMediaUploadCompleted> completions;
  late final StreamSubscription<OfferMediaUploadCompleted> _subscription;
  String? sessionUid = _ownerA;

  Box<dynamic> get box => Hive.box<dynamic>(boxName);

  /// Waits until the queue has nothing left it can do on its own: no drain
  /// running and nothing changing for several consecutive checks.
  Future<void> settle() async {
    var previous = '';
    var stable = 0;
    for (var i = 0; i < 600; i++) {
      await queue.idle;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final snapshot = '${worker.log.length}|'
          '${Hive.isBoxOpen(boxName) ? box.toMap() : ''}|'
          '${completions.length}';
      if (!queue.isDraining && snapshot == previous) {
        stable += 1;
        if (stable >= 3) return;
      } else {
        stable = 0;
      }
      previous = snapshot;
    }
    fail('the upload queue did not settle');
  }

  Future<void> start([String owner = _ownerA]) async {
    sessionUid = owner;
    queue.setActiveOwner(owner);
    await settle();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    queue.dispose();
    if (Hive.isBoxOpen(boxName)) await box.close();
  }
}

Future<File> _pick(String name, {int size = 64, Directory? dir}) async {
  final file = File('${(dir ?? _tmp).path}/$name');
  await file.writeAsBytes(List<int>.generate(size, (i) => (i * 7) % 256));
  return file;
}

OfferMediaDraft _imageDraft(File file, {String? id}) => OfferMediaDraft(
      mediaObjectId: id ?? _id(),
      path: file.path,
      kind: OfferMediaKind.image,
      contentType: 'image/jpeg',
      byteLength: file.lengthSync(),
      displayName: file.uri.pathSegments.last,
    );

OfferMediaDraft _videoDraft(File file, {String? posterPath, String? id}) =>
    OfferMediaDraft(
      mediaObjectId: id ?? _id(),
      path: file.path,
      kind: OfferMediaKind.video,
      contentType: 'video/mp4',
      byteLength: file.lengthSync(),
      posterPath: posterPath,
      displayName: file.uri.pathSegments.last,
      durationMs: 42000,
    );

String _key(String owner, String id) =>
    offerMediaCacheKey(ownerId: owner, mediaObjectId: id)!;

/// The queue's own copies still on disk for [ids].
List<File> _pendingFilesFor(Iterable<String> ids) => _offerMediaDir.existsSync()
    ? _offerMediaDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.contains('_pending') && ids.any((id) => f.path.contains(id)))
        .toList()
    : const <File>[];

Directory get _offerMediaDir =>
    Directory('${_docs.path}/${OfflineMediaService.offerMediaDirectoryName}');

void main() {
  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('offer_upload_queue_test_');
    _docs = await Directory('${_root.path}/docs').create();
    _tmp = await Directory('${_root.path}/tmp').create();
    _elsewhere = await Directory('${_root.path}/gallery').create();
    Hive.init('${_root.path}/hive');
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.resolveDocumentsDirectory = () async => _docs;
    await OfflineMediaService.instance.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _root.delete(recursive: true);
    } catch (_) {}
  });

  group('image and video lifecycle', () {
    test(
        'an image is sent once, confirmed, kept under its identity and '
        'announced', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final picked = await _pick('photo.jpg', size: 300);
      final bytes = await picked.readAsBytes();
      final draft = _imageDraft(picked);
      final id = draft.mediaObjectId;

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      // The picker's temporary copy is taken, not duplicated.
      expect(picked.existsSync(), isFalse);
      expect(
          h.queue
              .pendingRefsFor(ownerId: _ownerA, offerId: _offer)
              .single
              .uploadPhase,
          OfferMediaUploadPhase.queued);

      await h.start();

      expect(h.worker.log, ['authorize:$id', 'upload:$id', 'confirm:$id']);
      expect(h.worker.status[id], 'ready');
      expect(h.worker.stored[id], bytes);
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), isEmpty);
      expect(h.box.isEmpty, isTrue);
      expect(h.completions.single.mediaObjectId, id);
      expect(h.completions.single.isVideo, isFalse);

      final adopted = OfflineMediaService.instance
          .getLocalFilePathForMediaId(_key(_ownerA, id));
      expect(adopted, isNotNull);
      expect(File(adopted!).readAsBytesSync(), bytes);
      expect(
          OfflineMediaService.instance
              .readOfferMediaCatalog(ownerId: _ownerA, offerId: _offer),
          contains(id));
      expect(_pendingFilesFor([id]), isEmpty);
    });

    test('a video keeps only its still frame, under its poster key', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final video = await _pick('clip.mp4', size: 2048);
      final poster = await _pick('clip-poster.jpg', size: 100);
      final draft = _videoDraft(video, posterPath: poster.path);
      final id = draft.mediaObjectId;

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      final pending =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(pending.isVideo, isTrue);
      expect(pending.hasPoster, isTrue);
      expect(pending.durationMs, 42000);

      await h.start();

      expect(h.worker.status[id], 'ready');
      expect(h.completions.single.isVideo, isTrue);
      expect(h.completions.single.durationMs, 42000);
      final key = _key(_ownerA, id);
      expect(
          OfflineMediaService.instance.getLocalFilePathForMediaId(key), isNull);
      final posterPath = OfflineMediaService.instance
          .getLocalFilePathForMediaId(offerMediaPosterKey(key));
      expect(posterPath, isNotNull);
      expect(File(posterPath!).existsSync(), isTrue);
      // The video's own copy may be playing right now, so it is retired, not
      // deleted: only it remains, and the next time the queue opens it goes.
      final retired = _pendingFilesFor([id]);
      expect(retired, hasLength(1));
      expect(retired.single.path, endsWith('.mp4'));

      final reopened = _Harness(boxName: h.boxName);
      addTearDown(reopened.dispose);
      await reopened.queue.ensureOpen();
      expect(_pendingFilesFor([id]), isEmpty);
      expect(File(posterPath).existsSync(), isTrue,
          reason: 'the adopted still frame is never swept');
    });

    test('photos and videos go in the order they were picked', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final drafts = [
        _imageDraft(await _pick('a.jpg')),
        _videoDraft(await _pick('b.mp4')),
        _imageDraft(await _pick('c.jpg')),
      ];

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: drafts);
      expect(
        h.queue
            .pendingRefsFor(ownerId: _ownerA, offerId: _offer)
            .map((r) => r.mediaObjectId),
        drafts.map((d) => d.mediaObjectId),
      );
      await h.start();

      expect(
        h.worker.log.where((e) => e.startsWith('confirm:')),
        [for (final d in drafts) 'confirm:${d.mediaObjectId}'],
      );
      expect(h.completions.map((c) => c.mediaObjectId),
          drafts.map((d) => d.mediaObjectId));
    });
  });

  group('one identity, never a second object', () {
    test('the same draft queued twice is one task and one server row',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('once.jpg'));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      final again = await h.queue
          .enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      expect(again.failedIds, isEmpty);
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), hasLength(1));

      await h.start();

      expect(h.worker.rowsCreated, 1);
      expect(h.worker.count('authorize', draft.mediaObjectId), 1);
      expect(h.completions, hasLength(1));
    });

    test(
        'a lost confirm answer is followed by another confirm of the same '
        'id — the bytes are not sent again', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('lost.jpg'));
      final id = draft.mediaObjectId;
      h.worker.loseNextAnswer('confirm', id);

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.worker.log,
          ['authorize:$id', 'upload:$id', 'confirm:$id', 'confirm:$id']);
      expect(h.worker.rowsCreated, 1);
      expect(h.worker.status[id], 'ready');
      expect(h.completions, hasLength(1));
    });

    test(
        'an interrupted transfer is resumed under the same id and the '
        'server creates nothing new', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('flaky.jpg'));
      final id = draft.mediaObjectId;
      h.worker.failNext('upload', id,
          const OfferMediaRejectedException(OfferMediaRejection.interrupted));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.worker.count('authorize', id), 2);
      expect(h.worker.count('upload', id), 2);
      expect(h.worker.rowsCreated, 1);
      expect(h.worker.status[id], 'ready');
    });

    test('an item attached by an earlier attempt is not sent again', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('done.jpg'));
      final id = draft.mediaObjectId;
      h.worker.status[id] = 'ready';
      h.worker.offerOf[id] = _offer;

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.worker.log, ['authorize:$id']);
      expect(h.completions.single.mediaObjectId, id);
    });

    test('the server losing the bytes means sending them again', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('gone.jpg'));
      final id = draft.mediaObjectId;
      h.worker.failNext('confirm', id,
          R2OfferMediaHttpException(409, code: 'upload_incomplete'));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.worker.count('upload', id), 2);
      expect(h.worker.rowsCreated, 1);
      expect(h.worker.status[id], 'ready');
    });
  });

  group('restart and resume', () {
    test('queued items survive a restart and upload in order afterwards',
        () async {
      final name = 'offer_queue_restart_${_boxSeq++}';
      final first = _Harness(boxName: name);
      final drafts = [
        _imageDraft(await _pick('r1.jpg')),
        _imageDraft(await _pick('r2.jpg')),
      ];
      await first.queue
          .enqueue(ownerId: _ownerA, offerId: _offer, drafts: drafts);
      expect(first.worker.log, isEmpty, reason: 'no owner was active');
      await first.dispose();

      final second = _Harness(boxName: name, worker: first.worker);
      addTearDown(second.dispose);
      await second.queue.ensureOpen();
      expect(
        second.queue
            .tasksFor(ownerId: _ownerA, offerId: _offer)
            .map((t) => t.mediaObjectId),
        drafts.map((d) => d.mediaObjectId),
      );

      await second.start();

      expect(second.worker.rowsCreated, 2);
      expect(second.completions.map((c) => c.mediaObjectId),
          drafts.map((d) => d.mediaObjectId));
    });

    test(
        'an item whose bytes had already reached R2 before the restart is '
        'only confirmed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final id = _id();
      final copy = await _pick('offer-media_${id}_pending.jpg',
          dir: await _offerMediaDir.create(recursive: true));
      final task = OfferMediaUploadTask(
        mediaObjectId: id,
        ownerId: _ownerA,
        offerId: _offer,
        kind: OfferMediaKind.image,
        contentType: 'image/jpeg',
        byteLength: copy.lengthSync(),
        localPath: copy.path,
        createdAt: DateTime.now(),
        state: OfferMediaTaskState.confirming,
        serverTouched: true,
        bytesUploaded: true,
      );
      await Hive.openBox<dynamic>(h.boxName);
      await h.box.put(id, task.toMap());
      h.worker.status[id] = 'pending';
      h.worker.offerOf[id] = _offer;
      h.worker.stored[id] = copy.readAsBytesSync();

      await h.start();

      expect(h.worker.log, ['confirm:$id']);
      expect(h.worker.status[id], 'ready');
    });

    test('an unreadable stored entry is discarded, not fatal', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await Hive.openBox<dynamic>(h.boxName);
      await h.box.put('junk', {'v': 99, 'id': 'x'});
      await h.box.put('junk2', 'not a map');

      await h.queue.ensureOpen();

      expect(h.box.isEmpty, isTrue);
    });
  });

  group('partial failure', () {
    test(
        'one refused item neither stops nor repeats the others, and says '
        'why it failed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final drafts = [
        _imageDraft(await _pick('p1.jpg')),
        _imageDraft(await _pick('p2.jpg')),
        _imageDraft(await _pick('p3.jpg')),
      ];
      final refused = drafts[1].mediaObjectId;
      h.worker.failNext(
          'confirm',
          refused,
          const OfferMediaRejectedException(
              OfferMediaRejection.unsupportedType));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: drafts);
      await h.start();

      expect(h.worker.count('upload', drafts[0].mediaObjectId), 1);
      expect(h.worker.count('upload', drafts[2].mediaObjectId), 1);
      expect(h.worker.status[drafts[0].mediaObjectId], 'ready');
      expect(h.worker.status[drafts[2].mediaObjectId], 'ready');
      final left = h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer);
      expect(left.single.mediaObjectId, refused);
      expect(left.single.uploadPhase, OfferMediaUploadPhase.permanentFailure);
      expect(left.single.failureMessageKey, 'offerMediaUnsupportedType');
    });

    test('automatic retries end in a Retry the user can press', () async {
      final h = _Harness(backoff: const [Duration.zero, Duration.zero]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('retry.jpg'));
      final id = draft.mediaObjectId;
      for (var i = 0; i < 3; i++) {
        h.worker.failNext('authorize', id, R2OfferMediaHttpException(502));
      }

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final waiting =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(waiting.uploadPhase, OfferMediaUploadPhase.retryableFailure);
      expect(waiting.failureMessageKey, 'offerMediaUploadInterrupted');
      expect(h.worker.count('authorize', id), 3);

      await h.queue.retry(id);
      await h.settle();

      expect(h.worker.status[id], 'ready');
      expect(h.worker.rowsCreated, 1);
    });

    test('a rejected session waits without spending retries', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('session.jpg'));
      h.worker.failNext(
          'authorize', draft.mediaObjectId, R2OfferMediaHttpException(401));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final stored = h.box.get(draft.mediaObjectId) as Map;
      expect(stored['state'], OfferMediaTaskState.retryWait.name);
      expect(stored['attempts'], 0);
      final next =
          DateTime.fromMicrosecondsSinceEpoch(stored['nextAttemptAt'] as int);
      expect(next.isAfter(DateTime.now().add(const Duration(seconds: 10))),
          isTrue);
    });

    test('a queued file that vanished is reported and never sent', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('vanish.jpg'));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      File(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single.localPath)
          .deleteSync();
      await h.start();

      expect(h.worker.log, isEmpty);
      final ref = h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer);
      expect(ref.single.uploadPhase, OfferMediaUploadPhase.permanentFailure);
      expect(ref.single.failureMessageKey, 'offerMediaFileMissing');
    });

    test("an Offer that is gone drops its items instead of retrying", () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('deleted.jpg'));
      h.worker.failNext('authorize', draft.mediaObjectId,
          R2OfferMediaHttpException(404, code: 'offer_not_found'));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), isEmpty);
      expect(h.worker.count('authorize', draft.mediaObjectId), 1);
      expect(_pendingFilesFor([draft.mediaObjectId]), isEmpty);
    });
  });

  group('the ten-item limit', () {
    test(
        'an eleventh item is not lost: it waits for a place and goes on once '
        'one is freed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.worker.seedReady(_offer, 10);
      final draft = _imageDraft(await _pick('eleventh.jpg'));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final blocked =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(blocked.uploadPhase, OfferMediaUploadPhase.retryableFailure);
      expect(blocked.failureMessageKey, 'offerMediaLimitReached');
      expect(h.worker.rowsCreated, 0);

      h.worker.status.remove('seed-$_offer-0');
      await h.queue.releaseBlocked(ownerId: _ownerA, offerId: _offer);
      await h.settle();

      expect(h.worker.status[draft.mediaObjectId], 'ready');
      expect(h.worker.status.values.where((s) => s == 'ready'), hasLength(10));
    });

    test('a full Offer does not block a different Offer', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.worker.seedReady(_offer, 10);
      final other = _imageDraft(await _pick('other.jpg'));

      await h.queue
          .enqueue(ownerId: _ownerA, offerId: _otherOffer, drafts: [other]);
      await h.start();

      expect(h.worker.status[other.mediaObjectId], 'ready');
    });
  });

  group('remove', () {
    test('an item the server never saw is dropped without a server call',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('never.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);

      await h.queue.cancel(draft.mediaObjectId);
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), isEmpty,
          reason: 'a removed item is not shown while it is withdrawn');
      await h.start();

      expect(h.worker.log, isEmpty);
      expect(h.box.isEmpty, isTrue);
      expect(_pendingFilesFor([draft.mediaObjectId]), isEmpty);
    });

    test(
        'an item the server holds is withdrawn there, and a failed '
        'withdrawal is retried', () async {
      final h = _Harness(backoff: const [Duration.zero, Duration.zero]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('withdraw.jpg'));
      final id = draft.mediaObjectId;
      // Authorized, then the transfer keeps failing: the server holds a row.
      for (var i = 0; i < 3; i++) {
        h.worker.failNext('upload', id,
            const OfferMediaRejectedException(OfferMediaRejection.interrupted));
      }
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();
      expect(h.worker.status[id], 'pending');

      h.worker.failNext('remove', id, R2OfferMediaHttpException(502));
      await h.queue.cancel(id);
      await h.settle();

      expect(h.worker.count('remove', id), 2);
      expect(h.worker.status.containsKey(id), isFalse);
      expect(h.box.isEmpty, isTrue);
      expect(_pendingFilesFor([id]), isEmpty);
    });

    test('removing an item frees its place for one that was waiting', () async {
      final h = _Harness(backoff: const [Duration.zero, Duration.zero]);
      addTearDown(h.dispose);
      h.worker.seedReady(_offer, 9);
      final first = _imageDraft(await _pick('tenth.jpg'));
      for (var i = 0; i < 3; i++) {
        h.worker.failNext('upload', first.mediaObjectId,
            const OfferMediaRejectedException(OfferMediaRejection.interrupted));
      }
      final second = _imageDraft(await _pick('waiting.jpg'));
      await h.queue
          .enqueue(ownerId: _ownerA, offerId: _offer, drafts: [first, second]);
      await h.start();
      expect(
          h.queue
              .pendingRefsFor(ownerId: _ownerA, offerId: _offer)
              .last
              .failureMessageKey,
          'offerMediaLimitReached');

      await h.queue.cancel(first.mediaObjectId);
      await h.settle();

      expect(h.worker.status[second.mediaObjectId], 'ready');
      expect(h.worker.status.containsKey(first.mediaObjectId), isFalse);
    });
  });

  group('whose uploads run', () {
    test('nothing runs without an active owner or under another session',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('mine.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.settle();
      expect(h.worker.log, isEmpty, reason: 'no active owner');

      // The app says A, but the live session already belongs to B.
      h.sessionUid = _ownerB;
      h.queue.setActiveOwner(_ownerA);
      await h.settle();
      expect(h.worker.log, isEmpty);

      // B's session never runs A's work, and does not even list it.
      h.queue.setActiveOwner(_ownerB);
      await h.settle();
      expect(h.worker.log, isEmpty);
      expect(h.queue.tasksFor(ownerId: _ownerB, offerId: _offer), isEmpty);

      await h.start(_ownerA);
      expect(h.worker.status[draft.mediaObjectId], 'ready');
    });

    test('signing out pauses the queue; signing back in resumes it', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('pause.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);

      h.queue.setActiveOwner(null);
      h.sessionUid = null;
      await h.settle();
      expect(h.worker.log, isEmpty);

      await h.start(_ownerA);
      expect(h.worker.status[draft.mediaObjectId], 'ready');
    });

    test("account deletion removes that account's queue and files only",
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final mine = _imageDraft(await _pick('a1.jpg'));
      final theirs = _imageDraft(await _pick('b1.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [mine]);
      await h.queue
          .enqueue(ownerId: _ownerB, offerId: _offer, drafts: [theirs]);
      final theirPath =
          h.queue.tasksFor(ownerId: _ownerB, offerId: _offer).single.localPath;

      final failures = await h.queue.purgeOwner(_ownerA);

      expect(failures, 0);
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), isEmpty);
      expect(h.box.containsKey(mine.mediaObjectId), isFalse);
      expect(h.queue.tasksFor(ownerId: _ownerB, offerId: _offer), hasLength(1));
      expect(File(theirPath).existsSync(), isTrue);
      expect(h.worker.log, isEmpty);
      await h.queue.purgeOwner(_ownerB);
    });

    test("a deleted Offer's items are forgotten without a server call",
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final gone = _imageDraft(await _pick('gone1.jpg'));
      final kept = _imageDraft(await _pick('kept1.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [gone]);
      await h.queue
          .enqueue(ownerId: _ownerA, offerId: _otherOffer, drafts: [kept]);

      await h.queue.forgetOffer(ownerId: _ownerA, offerId: _offer);
      await h.start();

      expect(
          h.worker.log.where((e) => e.endsWith(gone.mediaObjectId)), isEmpty);
      expect(h.worker.status[kept.mediaObjectId], 'ready');
    });
  });

  group('local storage', () {
    test('what is stored is ids, a local path and state — never a link',
        () async {
      final h = _Harness(backoff: const [Duration.zero, Duration.zero]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('store.jpg'));
      h.worker.failNext('upload', draft.mediaObjectId,
          const OfferMediaRejectedException(OfferMediaRejection.interrupted));
      h.worker.failNext('upload', draft.mediaObjectId,
          const OfferMediaRejectedException(OfferMediaRejection.interrupted));
      h.worker.failNext('upload', draft.mediaObjectId,
          const OfferMediaRejectedException(OfferMediaRejection.interrupted));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final stored = h.box.get(draft.mediaObjectId) as Map;
      expect(
        stored.keys.toSet(),
        {
          'v', 'id', 'owner', 'offer', 'kind', 'contentType', 'byteLength', //
          'localPath', 'posterPath', 'displayName', 'durationMs', 'state',
          'attempts', 'nextAttemptAt', 'failure', 'serverTouched',
          'bytesUploaded', 'createdAt',
        },
      );
      expect(stored.toString(), isNot(contains('https://')));
      expect(stored.toString(), isNot(contains('r2.example.test')));
    });

    test(
        'the queued copy lives in the backup-excluded directory under the '
        "owner's prefix, which account deletion sweeps", () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('prefix.jpg'));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);

      final path =
          h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single.localPath;
      final name = path.replaceAll('\\', '/').split('/').last;
      expect(path.replaceAll('\\', '/'),
          contains('/${OfflineMediaService.offerMediaDirectoryName}/'));
      expect(name, startsWith('offer-media_${_ownerA}_'));
      await h.queue.purgeOwner(_ownerA);
    });

    test('a file outside the app\'s temporary directory is copied, not moved',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final original = await _pick('camera-roll.jpg', dir: _elsewhere);
      await h.queue.enqueue(
          ownerId: _ownerA, offerId: _offer, drafts: [_imageDraft(original)]);

      expect(original.existsSync(), isTrue);
      await h.queue.purgeOwner(_ownerA);
      expect(original.existsSync(), isTrue);
    });

    test('one file picked twice is copied for each item, not moved away',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final picked = await _pick('twice.jpg');
      final drafts = [_imageDraft(picked), _imageDraft(picked)];

      final result = await h.queue
          .enqueue(ownerId: _ownerA, offerId: _offer, drafts: drafts);

      expect(result.failedIds, isEmpty);
      expect(result.queued, hasLength(2));
      await h.start();
      expect(h.worker.status.values.where((s) => s == 'ready'), hasLength(2));
    });
  });

  // Android 15+ gives an app outside a valid process lifecycle no network:
  // every request fails at once. Device evidence (Samsung, Android 16): four
  // videos failed at authorize in ~20 ms each, repeatedly, while the app was
  // in the background, and all uploaded in ~4 s each once it returned.
  group('app lifecycle', () {
    test('nothing starts in the background; everything resumes on return',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('bg.jpg'));
      h.queue.didChangeAppLifecycleState(AppLifecycleState.paused);

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      expect(h.worker.log, isEmpty);
      final waiting =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(waiting.uploadPhase, OfferMediaUploadPhase.queued);

      h.queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.settle();

      expect(h.worker.status[draft.mediaObjectId], 'ready');
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer), isEmpty);
    });

    test(
        'a transfer cut off by leaving the app waits again without spending '
        'a retry, and finishes on return with the same row', () async {
      final h = _Harness(backoff: const [Duration.zero]);
      addTearDown(h.dispose);
      final draft = _videoDraft(await _pick('cut.mp4', size: 512));
      final id = draft.mediaObjectId;
      h.worker.beforeStep = (step, stepId) {
        if (step == 'upload' && stepId == id) {
          h.queue.didChangeAppLifecycleState(AppLifecycleState.paused);
        }
      };
      h.worker.failNext(
        'upload',
        id,
        const OfferMediaRejectedException(OfferMediaRejection.interrupted,
            cause: 'dns'),
      );

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final task = h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single;
      expect(task.state, OfferMediaTaskState.queued);
      expect(task.attempts, 0, reason: 'leaving the app is not a failure');
      expect(task.failure, isNull);

      h.worker.beforeStep = null;
      h.queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.settle();

      expect(h.worker.status[id], 'ready');
      expect(h.worker.rowsCreated, 1);
      expect(h.worker.count('upload', id), 2);
    });

    test('a failure just after returning does not spend a retry', () async {
      final h = _Harness(backoff: const [Duration.zero]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('back.jpg'));
      final id = draft.mediaObjectId;
      h.queue.didChangeAppLifecycleState(AppLifecycleState.paused);
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();
      h.worker.failNext(
        'authorize',
        id,
        const R2UploadException('unreachable', cause: 'dns'),
      );

      h.queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.settle();

      final task = h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single;
      expect(task.state, OfferMediaTaskState.retryWait);
      expect(task.attempts, 0);
      expect(task.toRef().uploadPhase, OfferMediaUploadPhase.retrying);
    });

    test(
        'an upload whose automatic retries ran out resumes by itself when '
        'the app returns', () async {
      final h = _Harness(backoff: const [Duration.zero, Duration.zero]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('exhausted.jpg'));
      final id = draft.mediaObjectId;
      for (var i = 0; i < 3; i++) {
        h.worker.failNext('authorize', id, R2OfferMediaHttpException(502));
      }
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();
      expect(h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single.state,
          OfferMediaTaskState.needsRetry);

      h.queue.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.settle();

      expect(h.worker.status[id], 'ready');
      expect(h.worker.rowsCreated, 1);
    });

    test('a refused item is not resumed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('refused.jpg'));
      final id = draft.mediaObjectId;
      h.worker.failNext('confirm', id,
          const OfferMediaRejectedException(OfferMediaRejection.rejected));
      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      h.queue.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.settle();

      final task = h.queue.tasksFor(ownerId: _ownerA, offerId: _offer).single;
      expect(task.state, OfferMediaTaskState.failed);
      expect(h.worker.count('confirm', id), 1);
    });
  });

  group('what the UI is told', () {
    test('a pending automatic retry reads as retrying, not as a failure',
        () async {
      final h = _Harness(backoff: const [Duration(minutes: 5)]);
      addTearDown(h.dispose);
      final draft = _imageDraft(await _pick('later.jpg'));
      h.worker.failNext(
          'authorize', draft.mediaObjectId, R2OfferMediaHttpException(503));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);
      await h.start();

      final ref =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(ref.uploadPhase, OfferMediaUploadPhase.retrying);
    });

    test('a video still uploading carries its local copy, to be played',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = _videoDraft(await _pick('local.mp4', size: 256));

      await h.queue.enqueue(ownerId: _ownerA, offerId: _offer, drafts: [draft]);

      final ref =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(ref.isVideo, isTrue);
      expect(ref.localFilePath, isNotNull);
      expect(File(ref.localFilePath!).existsSync(), isTrue);
    });

    test(
        'a step stored as in progress that nothing is running shows as '
        'waiting, never as a frozen percentage', () async {
      final boxName = 'offer_queue_test_frozen_${_boxSeq++}';
      final box = await Hive.openBox<dynamic>(boxName);
      final local = await _pick('frozen.jpg');
      final task = OfferMediaUploadTask(
        mediaObjectId: _id(),
        ownerId: _ownerA,
        offerId: _offer,
        kind: OfferMediaKind.image,
        contentType: 'image/jpeg',
        byteLength: local.lengthSync(),
        localPath: local.path,
        createdAt: DateTime.now(),
        state: OfferMediaTaskState.uploading,
        progress: 0.37,
      );
      await box.put(task.mediaObjectId, task.toMap());

      final h = _Harness(boxName: boxName);
      addTearDown(h.dispose);
      await h.queue.ensureOpen();

      final ref =
          h.queue.pendingRefsFor(ownerId: _ownerA, offerId: _offer).single;
      expect(ref.uploadPhase, OfferMediaUploadPhase.queued);
      expect(ref.progress, isNull);
    });
  });
}
