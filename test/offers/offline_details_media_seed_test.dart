// M2-3b (tracker §7AZ, D-M2-3-1..4): how Offer Details
// (OfferDetailsLoadCoordinator) and Owner Details (PrivateMediaGalleryLoader)
// use the saved list's media identity — the screen half, with fakes.
//
//  - The first frame stays synchronous: the catalogue seed first; only when
//    it has nothing, the saved ids' held items.
//  - A read-only lookup may then add held items (private cache, no mapping),
//    merged in order, with one notification — only while no Worker answer,
//    no revocation and no disposal has happened.
//  - A Worker answer replaces everything (unchanged); a failure keeps what is
//    shown, discovered items included.
//  - Nothing here sends a request: the Worker is asked once per load, as
//    before.
import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/private_media_store.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/private_media_gallery_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _record = '22222222-2222-4222-8222-222222222222';

String _m(int n) => 'eeeeeeee-eeee-4eee-8eee-${n.toString().padLeft(12, '0')}';

OfferMediaRef _held(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: offerMediaCacheKey(ownerId: _owner, mediaObjectId: id),
      localFilePath: '/held/$id.jpg',
    );

OfferMediaRef _signed(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: offerMediaCacheKey(ownerId: _owner, mediaObjectId: id),
      signedUrl: 'https://r2.example/$id.jpg?X-Amz-Signature=fresh',
    );

OfferModel _offer({
  List<String> listed = const [],
  List<String> mediaUrls = const [],
  String owner = _owner,
}) =>
    OfferModel(
      id: _record,
      userId: owner,
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '1',
      maxPrice: '2',
      notes: '',
      specificPropertyType: '',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      status: PropertyStatus.available,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      mediaUrls: mediaUrls,
      listedMediaObjectIds: listed,
    );

/// The test's control over the media sources a screen draws from.
class _Sources {
  List<OfferMediaRef> catalogue = const [];
  List<OfferMediaRef> listed = const [];
  final listedCalls = <List<String>>[];
  final discoveryCalls = <List<String>>[];
  Completer<List<OfferMediaRef>> discovery = Completer();
  Completer<OfferMediaResolution?> worker = Completer();
  int workerCalls = 0;
  int changes = 0;

  List<OfferMediaRef> readCatalogue(String id) => catalogue;

  List<OfferMediaRef> readListed(String id,
      {required String ownerId, required List<String> ids}) {
    expect(id, _record);
    expect(ownerId, _owner);
    listedCalls.add(ids);
    return listed;
  }

  Future<List<OfferMediaRef>> discover(String id,
      {required String ownerId, required List<String> ids}) {
    expect(id, _record);
    discoveryCalls.add(ids);
    return discovery.future;
  }

  Future<OfferMediaResolution?> resolve(
      {required String offerId, required String ownerId}) {
    workerCalls++;
    return worker.future;
  }
}

class _Store implements PrivateMediaStore {
  _Store(this.s);
  final _Sources s;

  @override
  MediaParent get parent => MediaParent.owner;
  @override
  String? get currentOwnerId => _owner;
  @override
  List<OfferMediaRef> cachedMedia(String recordId) => s.catalogue;
  @override
  Future<OfferMediaResolution?> resolveMedia(
          {required String recordId, required String ownerId}) =>
      s.resolve(offerId: recordId, ownerId: ownerId);
  @override
  List<OfferMediaRef> pendingMedia(String recordId) => const [];
  @override
  Listenable get uploadChanges => ChangeNotifier();
  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions =>
      const Stream.empty();
  @override
  Future<void> loadUploads() async {}
  @override
  Future<void> retryUpload(String mediaObjectId) async {}
  @override
  Future<void> cancelUpload(String mediaObjectId) async {}
}

/// One details screen's media half, Offer or Owner, behind one interface.
abstract class _Screen {
  List<OfferMediaRef> get items;
  bool get hasRenderableMedia;
  Future<void> load();
  void dispose();
}

class _OfferScreen implements _Screen {
  _OfferScreen(_Sources s, OfferModel offer, {bool wired = true})
      : c = OfferDetailsLoadCoordinator(
          initialOffer: offer,
          initialMetadataResolved: true,
          loadMetadata: (_) async => offer,
          resolveMedia: s.resolve,
          readCachedMedia: s.readCatalogue,
          readListedMedia: wired ? s.readListed : null,
          discoverHeldMedia: wired ? s.discover : null,
          onChanged: () => s.changes++,
        );
  final OfferDetailsLoadCoordinator c;
  @override
  List<OfferMediaRef> get items => c.mediaItems;
  @override
  bool get hasRenderableMedia => c.hasRenderableMedia;
  @override
  Future<void> load() => c.load();
  @override
  void dispose() => c.dispose();
}

class _OwnerScreen implements _Screen {
  _OwnerScreen(_Sources s, List<String> listed,
      {bool wired = true, String owner = _owner})
      : l = PrivateMediaGalleryLoader(
          recordId: _record,
          store: _Store(s),
          recordOwnerId: owner,
          listedMediaObjectIds: listed,
          readListedMedia: wired ? s.readListed : null,
          discoverHeldMedia: wired ? s.discover : null,
          onChanged: () => s.changes++,
        );
  final PrivateMediaGalleryLoader l;
  @override
  List<OfferMediaRef> get items => l.displayItems;
  @override
  bool get hasRenderableMedia => l.hasRenderableMedia;
  @override
  Future<void> load() => l.load();
  @override
  void dispose() => l.dispose();
}

List<String> _ids(List<OfferMediaRef> refs) =>
    [for (final r in refs) r.mediaObjectId];

void main() {
  final kinds =
      <(String, _Screen Function(_Sources, List<String>, {bool wired}))>[
    (
      'Offer',
      (s, listed, {bool wired = true}) =>
          _OfferScreen(s, _offer(listed: listed), wired: wired),
    ),
    (
      'Owner',
      (s, listed, {bool wired = true}) => _OwnerScreen(s, listed, wired: wired),
    ),
  ];

  for (final (kind, open) in kinds) {
    group(kind, () {
      late _Sources s;
      setUp(() => s = _Sources());

      test('no catalogue: the saved ids\' held items draw on the first frame',
          () {
        final saved = [_m(3), _m(1), _m(2)];
        s.listed = [_held(_m(3)), _held(_m(1))];
        final screen = open(s, saved);
        expect(s.listedCalls, [saved]);
        expect(_ids(screen.items), [_m(3), _m(1)]);
        expect(screen.hasRenderableMedia, isTrue);
        expect(s.workerCalls, 0, reason: 'nothing asked yet');
      });

      test('a catalogue seed wins: saved ids are not even read', () {
        s.catalogue = [_held(_m(9))];
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1)]);
        expect(s.listedCalls, isEmpty);
        expect(_ids(screen.items), [_m(9)]);
      });

      test('no saved ids: exactly today\'s behaviour', () {
        final screen = open(s, const []);
        expect(screen.items, isEmpty);
        expect(screen.hasRenderableMedia, isFalse);
      });

      test('not wired (tests, Firebase): exactly today\'s behaviour', () {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1)], wired: false);
        expect(screen.items, isEmpty);
        expect(s.listedCalls, isEmpty);
        expect(s.discoveryCalls, isEmpty);
      });

      test('the lookup adds held items in order, with one notification',
          () async {
        s.listed = [_held(_m(2))];
        final screen = open(s, [_m(1), _m(2), _m(3)]);
        expect(_ids(screen.items), [_m(2)]);
        final before = s.changes;
        s.discovery.complete([_held(_m(1)), _held(_m(2)), _held(_m(3))]);
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(1), _m(2), _m(3)]);
        expect(s.changes - before, 1, reason: 'one rebuild, not one per item');
      });

      test('the lookup keeps an item the seed had (same object, no flicker)',
          () async {
        final seeded = _held(_m(2));
        s.listed = [seeded];
        final screen = open(s, [_m(1), _m(2)]);
        s.discovery.complete([_held(_m(1)), _held(_m(2))]);
        await pumpEventQueue();
        expect(identical(screen.items[1], seeded), isTrue);
      });

      test('a lookup that finds nothing new changes nothing', () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1)]);
        final before = s.changes;
        s.discovery.complete([_held(_m(1))]);
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(1)]);
        expect(s.changes, before);
      });

      test('a Worker failure keeps the local and discovered images', () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1), _m(2)]);
        final loading = screen.load();
        s.worker.completeError(
            const OfferMediaException(OfferMediaFailureKind.transient));
        await loading;
        s.discovery.complete([_held(_m(1)), _held(_m(2))]);
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(1), _m(2)]);
      });

      // Option C (D-FOMF-3/4): an answer that proves nothing is not a
      // revocation; what the screen already shows stays.
      test('an inconclusive Worker answer keeps the local images', () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1)]);
        final loading = screen.load();
        s.worker.completeError(
            const OfferMediaException(OfferMediaFailureKind.inconclusive));
        await loading;
        s.discovery.complete([_held(_m(1))]);
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(1)]);
      });

      test('a Worker answer replaces everything; a later lookup is ignored',
          () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1), _m(2)]);
        final loading = screen.load();
        s.worker.complete(OfferMediaResolution(
            offerId: _record, ownerId: _owner, items: [_signed(_m(5))]));
        await loading;
        expect(_ids(screen.items), [_m(5)]);
        // The older lookup now answers with the stale saved ids.
        s.discovery.complete([_held(_m(1)), _held(_m(2))]);
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(5)],
            reason: 'media the Worker no longer lists is not brought back');
      });

      test('a revocation clears everything; a later lookup is ignored',
          () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1)]);
        final loading = screen.load();
        s.worker.completeError(
            const OfferMediaException(OfferMediaFailureKind.accessDenied));
        await loading;
        expect(screen.items, isEmpty);
        s.discovery.complete([_held(_m(1))]);
        await pumpEventQueue();
        expect(screen.items, isEmpty);
      });

      test('a closed screen hears nothing from a late lookup', () async {
        s.listed = const [];
        final screen = open(s, [_m(1)]);
        final before = s.changes;
        screen.dispose();
        s.discovery.complete([_held(_m(1))]);
        await pumpEventQueue();
        expect(s.changes, before);
        expect(screen.items, isEmpty, reason: 'and nothing is merged');
      });

      test('a failed lookup changes nothing', () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1), _m(2)]);
        s.discovery.completeError(StateError('disk'));
        await pumpEventQueue();
        expect(_ids(screen.items), [_m(1)]);
      });

      test('the lookup sends nothing: the Worker is asked once per load',
          () async {
        s.listed = [_held(_m(1))];
        final screen = open(s, [_m(1), _m(2)]);
        s.discovery.complete([_held(_m(1)), _held(_m(2))]);
        await pumpEventQueue();
        expect(s.workerCalls, 0);
        unawaited(screen.load());
        await pumpEventQueue();
        expect(s.workerCalls, 1);
        expect(s.discoveryCalls, hasLength(1), reason: 'once per screen');
      });
    });
  }

  test('Offer: a model that carries links keeps its links; no lookup', () {
    final s = _Sources();
    final screen = _OfferScreen(
        s, _offer(listed: [_m(1)], mediaUrls: const ['https://e.test/a.jpg']));
    expect(s.listedCalls, isEmpty);
    expect(s.discoveryCalls, isEmpty);
    expect(screen.items.single.signedUrl, 'https://e.test/a.jpg');
  });
}
