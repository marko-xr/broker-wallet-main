import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_store.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/viewmodels/private_media_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Owner private media (Supabase mode): the Offer media lifecycle run for
/// Owner records — through the Worker's Owner routes, the shared upload
/// queue (each task naming its parent), the Owner save and delete, and the
/// shared media form. Local only, against fakes; the Worker's own behaviour
/// is covered by `cloudflare/workers/r2-profile-upload/test/owner_media.test.mjs`.

const _account = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ownerRecord = 'a0a0a0a0-a0a0-4a0a-8a0a-a0a0a0a0a0a0';
const _offerRecord = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _mediaId = '22222222-2222-4222-8222-222222222222';

late Directory _root;
late Directory _tmp;
late Directory _docs;
var _seq = 0;

String _id() =>
    'c${(_seq++).toString().padLeft(7, '0')}-0000-4000-8000-000000000000';

sb.SupabaseClient _client() => sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

String _fakeJwt(String uid) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// A real client carrying a local session (no network), so the upload
/// service sees a genuine access token.
Future<sb.SupabaseClient> _signedInClient() async {
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((_) async => http.Response('{}', 200)),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode({
    'access_token': _fakeJwt(_account),
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000,
    'refresh_token': 'refresh',
    'user': {
      'id': _account,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'owner-media-test@example.test',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    },
  }));
  return client;
}

OwnerModel _owner({String? id}) => OwnerModel(
      id: id,
      userId: '',
      name: 'Owner',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: '',
      propertyLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrl: null,
      mediaUrls: const [],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

Future<OfferMediaDraft> _draft({String name = 'photo.jpg'}) async {
  final id = _id();
  final file = File('${_tmp.path}/$id.jpg');
  await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 0)]);
  return OfferMediaDraft(
    mediaObjectId: id,
    path: file.path,
    kind: OfferMediaKind.image,
    contentType: 'image/jpeg',
    byteLength: 64,
    displayName: name,
  );
}

/// A Media Worker for one parent: records every call and answers
/// authorize with "already attached", so an item completes at once.
class _Transport implements OfferMediaTransport {
  _Transport(this.name);

  final String name;
  final List<String> log = [];

  @override
  Future<OfferMediaAuthorization> authorizeUpload({
    required String offerId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    log.add('authorize:$offerId:$mediaObjectId');
    return OfferMediaAuthorization.ready(mediaObjectId: mediaObjectId);
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
    required int length,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Future<void>? cancel,
  }) async =>
      log.add('upload');

  @override
  Future<OfferMediaConfirmation> confirmUpload({
    required String offerId,
    required String mediaObjectId,
  }) async {
    log.add('confirm:$offerId:$mediaObjectId');
    return const OfferMediaConfirmation(ordinal: 0);
  }

  @override
  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  }) async {
    log.add('remove:$offerId:$mediaObjectId');
    return const OfferMediaRemoval();
  }
}

class _Queue {
  _Queue() {
    queue = OfferMediaUploadQueue(
      transport: () => offers,
      ownerTransport: () => owners,
      currentUserId: () => _account,
      openBox: () => Hive.openBox<dynamic>(boxName),
      documentsDirectory: () async => _docs,
      temporaryDirectory: () async => _tmp,
      offlineMedia: OfflineMediaService.instance,
      observeLifecycle: false,
    );
    _subscription = queue.completions.listen(completions.add);
  }

  final String boxName = 'owner_media_test_${_seq++}';
  final _Transport offers = _Transport('offers');
  final _Transport owners = _Transport('owners');
  final List<OfferMediaUploadCompleted> completions = [];
  late final OfferMediaUploadQueue queue;
  late final StreamSubscription<OfferMediaUploadCompleted> _subscription;

  Box<dynamic> get box => Hive.box<dynamic>(boxName);

  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await queue.idle;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!queue.isDraining) return;
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    queue.dispose();
    if (Hive.isBoxOpen(boxName)) await box.close();
  }
}

class _FakeEntities extends SupabaseCoreEntitiesService {
  _FakeEntities(this.log)
      : super(
          client: _client(),
          offerMedia: R2OfferMediaUploadService(
            httpClient: MockClient((_) async => http.Response('{}', 500)),
            supabaseClient: _client(),
          ),
          ownerMedia: R2OfferMediaUploadService(
            httpClient: MockClient((_) async => http.Response('{}', 500)),
            supabaseClient: _client(),
            parent: MediaParent.owner,
          ),
        );

  final List<String> log;
  final Map<String, OwnerModel> rows = {};

  @override
  String? get currentOwnerId => _account;

  @override
  Future<OwnerModel?> getOwner(String id) async {
    log.add('read');
    return rows[id];
  }

  @override
  Future<String> saveOwner(OwnerModel model, {String? ownerRecordId}) async {
    log.add('save');
    rows[ownerRecordId!] = model.copyWith(id: ownerRecordId);
    return ownerRecordId;
  }

  @override
  Future<void> updateOwner(String id, OwnerModel model) async {
    log.add('update');
    rows[id] = model.copyWith(id: id);
  }

  @override
  Future<void> deleteOwner(String id) async {
    log.add('delete');
    rows.remove(id);
  }
}

class _FakeOwnerRemover extends R2OfferMediaUploadService {
  _FakeOwnerRemover(this.log)
      : super(
          httpClient: MockClient((_) async => http.Response('{}', 500)),
          supabaseClient: _client(),
          parent: MediaParent.owner,
        );

  final List<String> log;

  @override
  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  }) async {
    log.add('remove:${parent.name}:$offerId:$mediaObjectId');
    return const OfferMediaRemoval();
  }
}

/// A store for the media form: fixed cached and server media, nothing
/// queued.
class _FakeStore implements PrivateMediaStore {
  _FakeStore({this.cached = const []});

  final List<OfferMediaRef> cached;
  final _changes = ChangeNotifier();
  final _completions = StreamController<OfferMediaUploadCompleted>.broadcast();

  @override
  MediaParent get parent => MediaParent.owner;

  @override
  String? get currentOwnerId => _account;

  @override
  List<OfferMediaRef> cachedMedia(String recordId) => cached;

  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async =>
      OfferMediaResolution(offerId: recordId, ownerId: ownerId, items: cached);

  @override
  List<OfferMediaRef> pendingMedia(String recordId) => const [];

  @override
  Listenable get uploadChanges => _changes;

  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions =>
      _completions.stream;

  @override
  Future<void> loadUploads() async {}

  @override
  Future<void> retryUpload(String mediaObjectId) async {}

  @override
  Future<void> cancelUpload(String mediaObjectId) async {}
}

OfferMediaRef _serverRef(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: offerMediaCacheKey(ownerId: _account, mediaObjectId: id),
      signedUrl: 'https://r2.example.test/get/$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('owner_media_test_');
    _tmp = await Directory('${_root.path}/tmp').create();
    _docs = await Directory('${_root.path}/docs').create();
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

  group('the Owner media routes', () {
    test(
        'an Owner upload service calls /owner-media/* with ownerRecordId, '
        'never an Offer route', () async {
      final requests = <http.Request>[];
      final service = R2OfferMediaUploadService(
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'media': []}), 200);
          }
          if (path.endsWith('/authorize')) {
            return http.Response(
                jsonEncode({'status': 'ready', 'mediaObjectId': _mediaId}),
                200);
          }
          return http.Response(jsonEncode({'removed': true}), 200);
        }),
        supabaseClient: await _signedInClient(),
        parent: MediaParent.owner,
      );

      await service.authorizeUpload(
        offerId: _ownerRecord,
        mediaObjectId: _mediaId,
        contentType: 'image/jpeg',
        contentLength: 64,
      );
      await service.confirmUpload(
          offerId: _ownerRecord, mediaObjectId: _mediaId);
      await service.removeMedia(offerId: _ownerRecord, mediaObjectId: _mediaId);
      await service.getOfferMedia(_ownerRecord);

      expect(requests.map((r) => r.url.path), [
        endsWith('/owner-media/authorize'),
        endsWith('/owner-media/confirm'),
        endsWith('/owner-media/remove'),
        endsWith('/owner-media'),
      ]);
      for (final request in requests.where((r) => r.method == 'POST')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['ownerRecordId'], _ownerRecord);
        expect(body.containsKey('offerId'), isFalse);
      }
      expect(
          requests.last.url.queryParameters, {'ownerRecordId': _ownerRecord});
    });

    test('an Offer upload service is unchanged: /offer-media with offerId', () {
      final service = R2OfferMediaUploadService(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        supabaseClient: _client(),
      );
      expect(service.parent, MediaParent.offer);
      expect(MediaParent.offer.routePrefix, '/offer-media');
      expect(MediaParent.offer.idField, 'offerId');
    });

    test('the Worker\'s Owner limit refusal is the limit, worded for an Owner',
        () {
      expect(OfferMediaRejection.fromWorkerCode('owner_media_limit_reached'),
          OfferMediaRejection.limitReached);
      expect(MediaParent.owner.messageKeyFor(OfferMediaRejection.limitReached),
          'ownerMediaLimitReached');
      expect(MediaParent.offer.messageKeyFor(OfferMediaRejection.limitReached),
          'offerMediaLimitReached');
      expect(MediaParent.owner.messageKeyFor(OfferMediaRejection.videoTooLong),
          OfferMediaRejection.videoTooLong.messageKey,
          reason: 'every other message is shared');
      expect(MediaParent.owner.maxItems, OfferMediaPolicy.maxItemsPerOffer);
    });
  });

  group('the shared upload queue', () {
    test(
        'an Owner item goes through the Owner routes only, completes as an '
        'Owner item and is persisted as one', () async {
      final q = _Queue();
      addTearDown(q.dispose);
      final draft = await _draft();

      q.queue.setActiveOwner(_account);
      await q.queue.enqueue(
        ownerId: _account,
        offerId: _ownerRecord,
        drafts: [draft],
        parent: MediaParent.owner,
      );
      await q.settle();

      expect(q.owners.log, ['authorize:$_ownerRecord:${draft.mediaObjectId}']);
      expect(q.offers.log, isEmpty, reason: 'no Offer route was called');
      expect(q.completions.single.parent, MediaParent.owner);
      expect(q.completions.single.offerId, _ownerRecord);
    });

    test(
        'Owner and Offer items are kept apart: listed, blocked and forgotten '
        'per parent', () async {
      final q = _Queue();
      addTearDown(q.dispose);
      final ownerDraft = await _draft();
      final offerDraft = await _draft();

      // Not active: nothing uploads, the tasks stay queued.
      await q.queue.enqueue(
        ownerId: _account,
        offerId: _ownerRecord,
        drafts: [ownerDraft],
        parent: MediaParent.owner,
      );
      await q.queue.enqueue(
        ownerId: _account,
        offerId: _offerRecord,
        drafts: [offerDraft],
      );

      expect(
          q.queue
              .pendingRefsFor(
                  ownerId: _account,
                  offerId: _ownerRecord,
                  parent: MediaParent.owner)
              .map((r) => r.mediaObjectId),
          [ownerDraft.mediaObjectId]);
      expect(
          q.queue
              .pendingRefsFor(ownerId: _account, offerId: _ownerRecord)
              .isEmpty,
          isTrue,
          reason: 'an Offer screen never shows an Owner item');

      // Persisted: an Owner task names its parent; an Offer task is stored
      // exactly as before.
      final ownerRow = q.box.get(ownerDraft.mediaObjectId) as Map;
      final offerRow = q.box.get(offerDraft.mediaObjectId) as Map;
      expect(ownerRow['parent'], 'owner');
      expect(offerRow.containsKey('parent'), isFalse);
      expect(OfferMediaUploadTask.fromMap(ownerRow)!.parent, MediaParent.owner);
      expect(OfferMediaUploadTask.fromMap(offerRow)!.parent, MediaParent.offer);

      await q.queue.forgetRecord(
        ownerId: _account,
        recordId: _ownerRecord,
        parent: MediaParent.owner,
      );
      expect(
          q.queue.tasksFor(
              ownerId: _account,
              offerId: _ownerRecord,
              parent: MediaParent.owner),
          isEmpty);
      expect(
          q.queue
              .tasksFor(ownerId: _account, offerId: _offerRecord)
              .map((t) => t.mediaObjectId),
          [offerDraft.mediaObjectId],
          reason: 'forgetting an Owner never touches an Offer item');
    });

    test('a blocked Owner item names a full Owner, not a full Offer', () {
      final task = OfferMediaUploadTask(
        mediaObjectId: _mediaId,
        ownerId: _account,
        offerId: _ownerRecord,
        parent: MediaParent.owner,
        kind: OfferMediaKind.image,
        contentType: 'image/jpeg',
        byteLength: 64,
        localPath: '${_docs.path}/offer_media/x_pending.jpg',
        createdAt: DateTime(2026, 9, 28),
        state: OfferMediaTaskState.blocked,
        failure: OfferMediaRejection.limitReached,
      );
      expect(task.toRef().failureMessageKey, 'ownerMediaLimitReached');
    });
  });

  group('saving and deleting an Owner', () {
    late List<String> log;
    late _Queue q;
    late _FakeEntities entities;
    late OwnerService service;

    setUp(() {
      log = [];
      q = _Queue();
      entities = _FakeEntities(log);
      service = OwnerService(
        ownerMediaUpload: () => _FakeOwnerRemover(log),
        uploadQueue: () => q.queue,
        coreEntities: () => entities,
      );
    });

    tearDown(() => q.dispose());

    test(
        'a new Owner is saved first; its media is queued as Owner media and '
        'not uploaded', () async {
      final drafts = [await _draft(), await _draft()];

      final result = await service.saveOwnerWithMedia(
        owner: _owner(),
        ownerRecordId: _ownerRecord,
        newMedia: drafts,
      );

      expect(log, ['read', 'save']);
      expect(result.ownerRecordId, _ownerRecord);
      expect(result.queuedCount, 2);
      expect(result.isComplete, isTrue);
      final pending = service.pendingMedia(_ownerRecord);
      expect(pending.map((r) => r.mediaObjectId),
          drafts.map((d) => d.mediaObjectId));
      expect(pending.map((r) => r.uploadPhase),
          everyElement(OfferMediaUploadPhase.queued),
          reason: 'queued is never presented as uploaded');
      expect(q.owners.log, isEmpty);
      expect(q.offers.log, isEmpty);
    });

    test(
        'an existing Owner is updated; removals go through the Owner routes '
        'before new items are queued', () async {
      entities.rows[_ownerRecord] = _owner(id: _ownerRecord);
      final draft = await _draft();

      final result = await service.saveOwnerWithMedia(
        owner: _owner(id: _ownerRecord),
        ownerRecordId: _ownerRecord,
        newMedia: [draft],
        removedMediaIds: const ['gone-1'],
      );

      expect(log, ['read', 'update', 'remove:owner:$_ownerRecord:gone-1']);
      expect(result.isComplete, isTrue);
      expect(service.pendingMedia(_ownerRecord).single.mediaObjectId,
          draft.mediaObjectId);
    });

    test(
        "deleting an Owner forgets its queued items, and nothing of an "
        "Offer's", () async {
      final ownerDraft = await _draft();
      final offerDraft = await _draft();
      await service.saveOwnerWithMedia(
        owner: _owner(),
        ownerRecordId: _ownerRecord,
        newMedia: [ownerDraft],
      );
      await q.queue.enqueue(
        ownerId: _account,
        offerId: _offerRecord,
        drafts: [offerDraft],
      );

      await service.deleteOwner(_ownerRecord);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.pendingMedia(_ownerRecord), isEmpty);
      expect(
          q.queue
              .tasksFor(ownerId: _account, offerId: _offerRecord)
              .map((t) => t.mediaObjectId),
          [offerDraft.mediaObjectId]);
    });

    test('Owner completions are the only ones an Owner screen hears', () async {
      final heard = <OfferMediaUploadCompleted>[];
      final subscription = service.uploadCompletions.listen(heard.add);
      addTearDown(subscription.cancel);
      q.queue.setActiveOwner(_account);

      await q.queue.enqueue(
        ownerId: _account,
        offerId: _offerRecord,
        drafts: [await _draft()],
      );
      await q.queue.enqueue(
        ownerId: _account,
        offerId: _ownerRecord,
        drafts: [await _draft()],
        parent: MediaParent.owner,
      );
      await q.settle();

      expect(q.completions.length, 2);
      expect(heard.map((e) => e.parent), [MediaParent.owner]);
    });
  });

  group('the shared media form', () {
    test(
        'an Edit form shows the Owner\'s media first; a server item removed '
        'is kept for Save, a picked file is dropped at once', () async {
      final form = PrivateMediaForm(
        store: _FakeStore(cached: [_serverRef('s1'), _serverRef('s2')]),
        onChanged: () {},
      );
      addTearDown(form.dispose);
      form.start(editRecordId: _ownerRecord);

      final photo = File('${_tmp.path}/pick_${_seq++}.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 0)]);
      final outcome = await form.addPicked([photo]);
      expect(outcome.added, 1);
      expect(form.items.map((r) => r.mediaObjectId).take(2), ['s1', 's2']);
      expect(form.items, hasLength(3));

      form.removeAt(0); // the server item s1: removed on Save
      form.removeAt(1); // the picked file: gone now
      expect(form.items.map((r) => r.mediaObjectId), ['s2']);
      expect(form.removedIds, ['s1']);
      expect(form.drafts, isEmpty);

      form.applySaveResult(
        removed: const ['s1'],
        cancelled: const [],
        failedRemovalIds: const [],
        failedToQueueIds: const [],
      );
      expect(form.removedIds, isEmpty);
      expect(form.items.map((r) => r.mediaObjectId), ['s2']);
    });

    test('ten items fill an Owner; more is over the limit', () {
      final full = PrivateMediaForm(
        store: _FakeStore(
            cached: [for (var i = 0; i < 10; i++) _serverRef('f$i')]),
        onChanged: () {},
      );
      addTearDown(full.dispose);
      full.start(editRecordId: _ownerRecord);
      expect(full.remainingSlots, 0);
      expect(full.isOverLimit, isFalse);

      final over = PrivateMediaForm(
        store: _FakeStore(
            cached: [for (var i = 0; i < 11; i++) _serverRef('o$i')]),
        onChanged: () {},
      );
      addTearDown(over.dispose);
      over.start(editRecordId: _ownerRecord);
      expect(over.isOverLimit, isTrue);
      expect(over.parent.limitReachedKey, 'ownerMediaLimitReached');
    });
  });
}
