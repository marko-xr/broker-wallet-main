import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Saving an Offer with media (Supabase mode): the Offer row first, then
/// removals, then new items handed to the upload queue — never an upload,
/// never a wait, and every outcome reported as it went.
///
/// Local only, against fakes of the entity service and the Media Worker.

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _offerId = 'o1111111-1111-4111-8111-111111111111';

late Directory _root;
late Directory _tmp;
var _seq = 0;

sb.SupabaseClient _client() => sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

OfferModel _offer({String? id}) => OfferModel(
      id: id,
      userId: '',
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: 'note',
      specificPropertyType: '',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      status: PropertyStatus.available,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      mediaUrls: const [],
    );

class _FakeEntities extends SupabaseCoreEntitiesService {
  _FakeEntities(this.log, {this.owner = _owner})
      : super(
          client: _client(),
          offerMedia: R2OfferMediaUploadService(
            httpClient: MockClient((_) async => http.Response('{}', 500)),
            supabaseClient: _client(),
          ),
        );

  final List<String> log;
  final String? owner;
  final Map<String, OfferModel> rows = {};
  bool failSave = false;

  @override
  String? get currentOwnerId => owner;

  @override
  Future<OfferModel?> getOfferMetadata(String id) async {
    log.add('metadata');
    return rows[id];
  }

  @override
  Future<String> saveOffer(OfferModel model, {String? offerId}) async {
    log.add('save');
    if (failSave) throw StateError('row refused');
    rows[offerId!] = model.copyWith(id: offerId);
    return offerId;
  }

  @override
  Future<void> updateOffer(String id, OfferModel model) async {
    log.add('update');
    rows[id] = model.copyWith(id: id);
  }

  @override
  Future<void> deleteOffer(String id) async {
    log.add('delete');
    rows.remove(id);
  }
}

class _FakeRemover extends R2OfferMediaUploadService {
  _FakeRemover(this.log)
      : super(
          httpClient: MockClient((_) async => http.Response('{}', 500)),
          supabaseClient: _client(),
        );

  final List<String> log;
  final Set<String> failing = {};

  @override
  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  }) async {
    log.add('remove:$mediaObjectId');
    if (failing.contains(mediaObjectId)) {
      throw R2OfferMediaHttpException(502);
    }
    return const OfferMediaRemoval();
  }
}

/// A Media Worker that must never be reached: saving never uploads.
class _UnreachableTransport implements OfferMediaTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Saving an Offer must not call the Media Worker.');
}

class _Setup {
  _Setup() {
    queue = OfferMediaUploadQueue(
      transport: () => _UnreachableTransport(),
      currentUserId: () => _owner,
      openBox: () => Hive.openBox<dynamic>(boxName),
      documentsDirectory: () async => Directory('${_root.path}/docs'),
      temporaryDirectory: () async => _tmp,
      offlineMedia: OfflineMediaService.instance,
      observeLifecycle: false,
    );
    entities = _FakeEntities(log);
    remover = _FakeRemover(log);
    service = OfferService(
      offerMediaUpload: () => remover,
      uploadQueue: () => queue,
      coreEntities: () => entities,
    );
  }

  final String boxName = 'offer_save_test_${_seq++}';
  final List<String> log = [];
  late final OfferMediaUploadQueue queue;
  late final _FakeEntities entities;
  late final _FakeRemover remover;
  late final OfferService service;

  List<String> queuedIds() => [
        for (final task in queue.tasksFor(ownerId: _owner, offerId: _offerId))
          task.mediaObjectId,
      ];

  Future<void> dispose() async {
    queue.dispose();
    if (Hive.isBoxOpen(boxName)) await Hive.box<dynamic>(boxName).close();
  }
}

Future<OfferMediaDraft> _draft({bool exists = true}) async {
  final id =
      'd${(_seq++).toString().padLeft(7, '0')}-0000-4000-8000-000000000000';
  final file = File('${_tmp.path}/$id.jpg');
  if (exists) await file.writeAsBytes(List<int>.filled(32, 7));
  return OfferMediaDraft(
    mediaObjectId: id,
    path: file.path,
    kind: OfferMediaKind.image,
    contentType: 'image/jpeg',
    byteLength: 32,
    displayName: 'photo.jpg',
  );
}

void main() {
  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('offer_save_test_');
    _tmp = await Directory('${_root.path}/tmp').create();
    await Directory('${_root.path}/docs').create();
    Hive.init('${_root.path}/hive');
    OfflineMediaService.fetchCachedBytes = (_, __) async => null;
    OfflineMediaService.removeCachedBytes = (_) async {};
    OfflineMediaService.resolveDocumentsDirectory =
        () async => Directory('${_root.path}/docs');
    await OfflineMediaService.instance.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await _root.delete(recursive: true);
    } catch (_) {}
  });

  test(
      'a new Offer is saved first; its media is queued, in order, and not '
      'uploaded', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final drafts = [await _draft(), await _draft()];

    final result = await s.service.saveOfferWithMedia(
      offer: _offer(),
      offerId: _offerId,
      newMedia: drafts,
    );

    expect(s.log, ['metadata', 'save']);
    expect(s.entities.rows.containsKey(_offerId), isTrue);
    expect(result.offerId, _offerId);
    expect(result.queuedCount, 2);
    expect(result.isComplete, isTrue);
    expect(s.queuedIds(), drafts.map((d) => d.mediaObjectId));
    final refs = s.service.pendingOfferMedia(_offerId);
    expect(refs.map((r) => r.uploadPhase),
        everyElement(OfferMediaUploadPhase.queued),
        reason: 'queued is never presented as uploaded');
  });

  test(
      'an existing Offer is updated; removals run before new items are '
      'queued, and a failed one is reported without stopping the rest',
      () async {
    final s = _Setup();
    addTearDown(s.dispose);
    s.entities.rows[_offerId] = _offer(id: _offerId);
    s.remover.failing.add('keep-me');
    final draft = await _draft();

    final result = await s.service.saveOfferWithMedia(
      offer: _offer(id: _offerId),
      offerId: _offerId,
      newMedia: [draft],
      removedMediaIds: const ['gone-1', 'keep-me', 'gone-2'],
    );

    expect(s.log, [
      'metadata',
      'update',
      'remove:gone-1',
      'remove:keep-me',
      'remove:gone-2',
    ]);
    expect(result.failedRemovalIds, ['keep-me']);
    expect(result.isComplete, isFalse);
    expect(result.queuedCount, 1);
    expect(s.queuedIds(), [draft.mediaObjectId]);
  });

  test('saving again after a partial failure duplicates nothing', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final drafts = [await _draft(), await _draft()];

    await s.service.saveOfferWithMedia(
        offer: _offer(), offerId: _offerId, newMedia: drafts);
    final again = await s.service.saveOfferWithMedia(
        offer: _offer(), offerId: _offerId, newMedia: drafts);

    expect(s.queuedIds(), drafts.map((d) => d.mediaObjectId));
    expect(again.queuedCount, 2);
    expect(s.log, ['metadata', 'save', 'metadata', 'update'],
        reason: 'the second save updates the Offer it created');
  });

  test(
      'a file that cannot be taken into app storage is reported; the Offer '
      'and the other items are still saved', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final good = await _draft();
    final missing = await _draft(exists: false);

    final result = await s.service.saveOfferWithMedia(
      offer: _offer(),
      offerId: _offerId,
      newMedia: [good, missing],
    );

    expect(s.entities.rows.containsKey(_offerId), isTrue);
    expect(result.failedToQueueIds, [missing.mediaObjectId]);
    expect(result.queuedCount, 1);
    expect(s.queuedIds(), [good.mediaObjectId]);
  });

  test('an upload removed in the form is withdrawn on save', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final draft = await _draft();
    await s.service.saveOfferWithMedia(
        offer: _offer(), offerId: _offerId, newMedia: [draft]);

    await s.service.saveOfferWithMedia(
      offer: _offer(),
      offerId: _offerId,
      cancelledUploadIds: [draft.mediaObjectId],
    );

    expect(s.queuedIds(), isEmpty);
    expect(s.service.pendingOfferMedia(_offerId), isEmpty);
  });

  test('an Offer row that fails to save queues and removes nothing', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    s.entities.failSave = true;

    await expectLater(
      s.service.saveOfferWithMedia(
        offer: _offer(),
        offerId: _offerId,
        newMedia: [await _draft()],
        removedMediaIds: const ['x'],
      ),
      throwsStateError,
    );

    expect(s.log, ['metadata', 'save']);
    expect(s.queuedIds(), isEmpty);
  });

  test('without a session nothing is saved', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final service = OfferService(
      offerMediaUpload: () => s.remover,
      uploadQueue: () => s.queue,
      coreEntities: () => _FakeEntities(s.log, owner: null),
    );

    await expectLater(
      service.saveOfferWithMedia(offer: _offer(), offerId: _offerId),
      throwsStateError,
    );
    expect(s.log, isEmpty);
  });

  test('a removal frees places for items that found the Offer full', () async {
    final s = _Setup();
    addTearDown(s.dispose);
    final box = await Hive.openBox<dynamic>(s.boxName);
    final waiting = OfferMediaUploadTask(
      mediaObjectId: 'w0000000-0000-4000-8000-000000000000',
      ownerId: _owner,
      offerId: _offerId,
      kind: OfferMediaKind.image,
      contentType: 'image/jpeg',
      byteLength: 32,
      localPath: '${_root.path}/docs/offer_media/waiting.jpg',
      createdAt: DateTime(2026, 9, 1),
      state: OfferMediaTaskState.blocked,
      failure: OfferMediaRejection.limitReached,
      serverTouched: true,
    );
    await box.put(waiting.mediaObjectId, waiting.toMap());
    await s.queue.ensureOpen();
    s.entities.rows[_offerId] = _offer(id: _offerId);

    await s.service.saveOfferWithMedia(
      offer: _offer(id: _offerId),
      offerId: _offerId,
      removedMediaIds: const ['old'],
    );

    final task = s.queue.tasksFor(ownerId: _owner, offerId: _offerId).single;
    expect(task.state, OfferMediaTaskState.queued);
    expect(task.failure, isNull);
  });

  test("deleting an Offer forgets its queued items and this device's copies",
      () async {
    final s = _Setup();
    addTearDown(s.dispose);
    await s.service.saveOfferWithMedia(
        offer: _offer(), offerId: _offerId, newMedia: [await _draft()]);
    expect(s.queuedIds(), hasLength(1));

    await s.service.deleteOffer(_offerId);
    for (var i = 0; i < 20 && s.queuedIds().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(s.log.last, 'delete');
    expect(s.queuedIds(), isEmpty);
  });

  test('the legacy fast-save entry never uploads files in Supabase mode',
      () async {
    final s = _Setup();
    addTearDown(s.dispose);

    await expectLater(
      s.service.saveOfferWithMediaFast(
        offer: _offer(),
        mediaFiles: [File('${_tmp.path}/any.jpg')],
        offerId: _offerId,
      ),
      throwsStateError,
    );
    expect(s.log, isEmpty);
  });
}
