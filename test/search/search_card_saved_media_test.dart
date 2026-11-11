// M3b-2 (tracker §7AZ, D-M3-3): Search Offer and Owner cards find photos this
// device already holds through the saved list's media identity
// (`listedMediaObjectIds`) and a read-only local lookup before asking the
// Worker to sign anything.
//
// Precedence under test:
//  - a fresh Worker answer is the authority, and is the only thing remembered;
//  - a catalogue entry for the record (even an empty one) wins over the saved
//    ids, which are never merged with it;
//  - only with no catalogue entry do the saved ids name what is held;
//  - empty saved ids mean "unknown", never "no media";
//  - the read-only lookup runs inside the same three-at-a-time limit, and its
//    result is never remembered as a Worker answer;
//  - after a Worker failure only what the catalogue and session still allow is
//    shown, so a 403/404 is never undone by an earlier lookup.
// The feature is switched on by Search alone: a resolver built without it (as
// Smart Map builds its own) behaves exactly as before.
//
// The resolver runs for real against a fake source whose catalogue and lookup
// follow the service rules (the real services are pinned in
// search_card_saved_media_services_test.dart). Every wait is a Completer the
// test opens; nothing sleeps.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_result_card.dart';
import 'package:broker_wallet/src/Views/Widgets/private_card_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../responsive/r2_test_fakes.dart';
import '../responsive/responsive_harness.dart';
import 'search_fixtures.dart' as fixtures;

const _account = 'account-1';
const _other = 'account-2';

String _key(String media, {String account = _account}) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

/// How a Worker request ends in the fake.
enum _Ends { answer, transient, denied }

/// A source that keeps the service rules: the catalogue seed holds only what
/// is on the device; the saved ids are used only when the record has no
/// catalogue entry and only for the signed-in account; the lookup follows the
/// catalogue when there is one, else the saved ids, and also finds bytes held
/// only in the private cache. A denied Worker answer empties the record's
/// catalogue entry before it fails, as `_forgetOfferMediaLocally` does.
class _Source implements SearchCardMediaSource, SearchCardHeldMedia {
  @override
  String? accountId = _account;

  /// Catalogue entries by `kind:id` (present even when empty).
  final Map<String, List<String>> catalogue = {};

  /// Media whose bytes (through a mapping) or poster are on the device now.
  final Map<String, OfferMediaRef> held = {};

  /// Media whose bytes are only in the private cache, with no mapping.
  final Map<String, OfferMediaRef> privateOnly = {};

  /// What the Worker answers, by `kind:id`; missing = no media.
  final Map<String, List<OfferMediaRef>> worker = {};
  final Map<String, _Ends> ends = {};

  bool gateWorker = false;
  bool gateLookup = false;
  final Map<String, Completer<void>> workerGates = {};
  final Map<String, Completer<void>> lookupGates = {};

  bool listedThrows = false;
  bool lookupThrows = false;

  final List<String> workerCalls = [];
  final List<(String, List<String>)> listedCalls = [];
  final List<(String, List<String>)> lookupCalls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  static String keyOf(CardMediaKind kind, String id) => '${kind.name}:$id';

  void _enter() {
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
  }

  /// Keys are account-scoped: an item is only ever found under the key of
  /// the signed-in account (as `offerMediaCacheKey` and `canRead` ensure).
  OfferMediaRef? _mine(OfferMediaRef? ref, String? account) {
    if (ref == null || account == null) return null;
    return ref.cacheKey == _key(ref.mediaObjectId, account: account)
        ? ref
        : null;
  }

  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) {
    final ids = catalogue[keyOf(kind, recordId)] ?? const <String>[];
    return [
      for (final id in ids)
        if (_mine(held[id], accountId) case final ref?) ref,
    ];
  }

  @override
  List<OfferMediaRef> listed(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  ) {
    listedCalls.add((keyOf(kind, recordId), List.of(ids)));
    if (listedThrows) throw StateError('unreadable');
    if (accountId != this.accountId) return const [];
    if (catalogue.containsKey(keyOf(kind, recordId))) return const [];
    return [
      for (final id in ids)
        if (_mine(held[id], accountId) case final ref?) ref,
    ];
  }

  @override
  Future<List<OfferMediaRef>> discover(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  ) async {
    final key = keyOf(kind, recordId);
    lookupCalls.add((key, List.of(ids)));
    _enter();
    try {
      if (gateLookup) {
        final gate = lookupGates[key] = Completer<void>();
        await gate.future;
      }
      if (lookupThrows) throw StateError('unreadable');
      if (accountId != this.accountId) return const [];
      final order = catalogue[key] ?? ids;
      return [
        for (final id in order)
          if (_mine(held[id] ?? privateOnly[id], accountId) case final ref?)
            ref,
      ];
    } finally {
      inFlight--;
    }
  }

  @override
  Future<OfferMediaResolution?> resolve(
    CardMediaKind kind,
    String recordId,
    String accountId,
  ) async {
    final key = keyOf(kind, recordId);
    workerCalls.add(key);
    _enter();
    try {
      if (gateWorker) {
        final gate = workerGates[key] = Completer<void>();
        await gate.future;
      }
      switch (ends[key] ?? _Ends.answer) {
        case _Ends.transient:
          throw StateError('offline');
        case _Ends.denied:
          catalogue[key] = const <String>[];
          throw StateError('access denied');
        case _Ends.answer:
          final items = worker[key] ?? const <OfferMediaRef>[];
          catalogue[key] = [for (final r in items) r.mediaObjectId];
          return OfferMediaResolution(
              offerId: recordId, ownerId: accountId, items: items);
      }
    } finally {
      inFlight--;
    }
  }
}

OfferMediaRef _heldPhoto(String id) => OfferMediaRef(
    mediaObjectId: id, cacheKey: _key(id), localFilePath: '/held/$id.jpg');

OfferMediaRef _heldPoster(String id) => OfferMediaRef(
    mediaObjectId: id,
    cacheKey: _key(id),
    isVideo: true,
    posterPath: '/held/$id.poster.jpg');

OfferMediaRef _linked(String id, {bool video = false}) => OfferMediaRef(
    mediaObjectId: id,
    cacheKey: _key(id),
    signedUrl: 'https://media.example/$id',
    isVideo: video);

SearchCardMediaResolver _search(_Source source, {int maxConcurrent = 3}) =>
    SearchCardMediaResolver(
      source: source,
      heldMedia: source,
      maxConcurrent: maxConcurrent,
    );

/// Built the way Smart Map builds its own: no saved-ids lookup.
SearchCardMediaResolver _mapLike(_Source source) =>
    SearchCardMediaResolver(source: source);

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  for (final kind in CardMediaKind.values) {
    group('${kind.name}: what the card shows', () {
      late _Source source;
      setUp(() => source = _Source());

      test('no catalogue: a held saved id draws at once, with no Worker',
          () async {
        source.held['m1'] = _heldPhoto('m1');
        final resolver = _search(source);
        final now = resolver.current(kind, 'r1', listedIds: const ['m1']);
        expect(now?.cacheKey, _key('m1'));
        expect(now?.isVideo, isFalse);
        final media =
            await resolver.resolve(kind, 'r1', listedIds: const ['m1']);
        expect(media?.cacheKey, _key('m1'));
        expect(source.workerCalls, isEmpty, reason: 'nothing to sign');
        expect(source.lookupCalls, isEmpty,
            reason: 'held at once: no lookup is needed either');
      });

      test('the first drawable photo in saved order, past missing bytes',
          () async {
        source.held['v1'] = _heldPoster('v1');
        source.held['p2'] = _heldPhoto('p2');
        source.held['p3'] = _heldPhoto('p3');
        final resolver = _search(source);
        const saved = ['gone', 'v1', 'p2', 'p3'];
        expect(resolver.current(kind, 'r1', listedIds: saved)?.cacheKey,
            _key('p2'),
            reason: 'a photo before a video frame; an id with no bytes is '
                'skipped');
        expect((await resolver.resolve(kind, 'r1', listedIds: saved))?.cacheKey,
            _key('p2'));
        expect(source.workerCalls, isEmpty);
      });

      test('a catalogue with a held photo wins; saved ids are not merged',
          () async {
        source.catalogue[_Source.keyOf(kind, 'r1')] = ['fromWorker'];
        source.held['fromWorker'] = _heldPhoto('fromWorker');
        source.held['fromList'] = _heldPhoto('fromList');
        final resolver = _search(source);
        expect(
            resolver
                .current(kind, 'r1', listedIds: const ['fromList'])?.cacheKey,
            _key('fromWorker'));
        expect(
            (await resolver.resolve(kind, 'r1', listedIds: const ['fromList']))
                ?.cacheKey,
            _key('fromWorker'));
        expect(source.listedCalls, isEmpty,
            reason: 'the saved ids are not even read');
        expect(source.workerCalls, isEmpty);
      });

      test('an empty catalogue entry also wins: saved ids give nothing',
          () async {
        source.catalogue[_Source.keyOf(kind, 'r1')] = const [];
        source.held['fromList'] = _heldPhoto('fromList');
        final resolver = _search(source);
        expect(resolver.current(kind, 'r1', listedIds: const ['fromList']),
            isNull);
        expect(
            await resolver.resolve(kind, 'r1', listedIds: const ['fromList']),
            isNull);
        expect(source.workerCalls, [_Source.keyOf(kind, 'r1')],
            reason: 'nothing held under the catalogue: the Worker is asked');
      });

      test('empty saved ids are unknown, not "no media": the Worker is asked',
          () async {
        source.worker[_Source.keyOf(kind, 'r1')] = [_linked('w1')];
        final resolver = _search(source);
        expect(resolver.current(kind, 'r1'), isNull);
        final media = await resolver.resolve(kind, 'r1');
        expect(media?.cacheKey, _key('w1'));
        expect(source.workerCalls, [_Source.keyOf(kind, 'r1')]);
      });

      test('bytes only in the private cache: found by the lookup, no Worker',
          () async {
        source.privateOnly['p1'] = _heldPhoto('p1');
        final resolver = _search(source);
        expect(resolver.current(kind, 'r1', listedIds: const ['p1']), isNull,
            reason: 'the first frame sees only mapped bytes');
        final media =
            await resolver.resolve(kind, 'r1', listedIds: const ['p1']);
        expect(media?.cacheKey, _key('p1'));
        expect(source.lookupCalls, hasLength(1));
        expect(source.workerCalls, isEmpty);
      });

      test('a catalogued item held only in the private cache: no Worker',
          () async {
        source.catalogue[_Source.keyOf(kind, 'r1')] = ['c1'];
        source.privateOnly['c1'] = _heldPhoto('c1');
        source.privateOnly['fromList'] = _heldPhoto('fromList');
        final resolver = _search(source);
        final media =
            await resolver.resolve(kind, 'r1', listedIds: const ['fromList']);
        expect(media?.cacheKey, _key('c1'),
            reason: 'the lookup follows the catalogue, not the saved ids');
        expect(source.workerCalls, isEmpty);
      });

      test('a local find is never remembered as a Worker answer', () async {
        source.privateOnly['p1'] = _heldPhoto('p1');
        source.worker[_Source.keyOf(kind, 'r1')] = [_linked('w1')];
        final resolver = _search(source);
        expect(
            (await resolver.resolve(kind, 'r1', listedIds: const ['p1']))
                ?.cacheKey,
            _key('p1'));
        // The private copy is evicted: nothing local is held any more.
        source.privateOnly.clear();
        expect(resolver.current(kind, 'r1', listedIds: const ['p1']), isNull,
            reason: 'the earlier local find is not kept in memory');
        final again =
            await resolver.resolve(kind, 'r1', listedIds: const ['p1']);
        expect(again?.cacheKey, _key('w1'),
            reason: 'with nothing held the Worker is asked as before');
        expect(source.lookupCalls, hasLength(2));
        expect(source.workerCalls, [_Source.keyOf(kind, 'r1')]);
      });

      test('nothing held: the Worker answer is shown and remembered alone',
          () async {
        source.worker[_Source.keyOf(kind, 'r1')] = [_linked('w1')];
        final resolver = _search(source);
        final media =
            await resolver.resolve(kind, 'r1', listedIds: const ['s1']);
        expect(media?.cacheKey, _key('w1'));
        expect(source.lookupCalls, hasLength(1),
            reason: 'the device is looked at before the Worker');
        expect(source.workerCalls, hasLength(1));
        // A saved id's bytes arrive later: the fresh answer still wins.
        source.held['s1'] = _heldPhoto('s1');
        expect(resolver.current(kind, 'r1', listedIds: const ['s1'])?.cacheKey,
            _key('w1'));
        expect(
            (await resolver.resolve(kind, 'r1', listedIds: const ['s1']))
                ?.cacheKey,
            _key('w1'));
        expect(source.workerCalls, hasLength(1));
      });

      test('the Worker says the photo is gone: it does not come back',
          () async {
        source.worker[_Source.keyOf(kind, 'r1')] = const [];
        final resolver = _search(source);
        expect(await resolver.resolve(kind, 'r1', listedIds: const ['s1']),
            isNull);
        // Bytes for the removed id turn up later (a late copy): not shown.
        source.held['s1'] = _heldPhoto('s1');
        source.privateOnly['s1'] = _heldPhoto('s1');
        expect(resolver.current(kind, 'r1', listedIds: const ['s1']), isNull);
        expect(await resolver.resolve(kind, 'r1', listedIds: const ['s1']),
            isNull);
      });

      for (final status in ['403', '404']) {
        test('a $status after a held video frame shows nothing afterwards',
            () async {
          // Only a video frame is held, so the Worker is still asked.
          source.held['v1'] = _heldPoster('v1');
          source.ends[_Source.keyOf(kind, 'r1')] = _Ends.denied;
          final resolver = _search(source);
          expect(resolver.current(kind, 'r1', listedIds: const ['v1'])?.isVideo,
              isTrue);
          final media =
              await resolver.resolve(kind, 'r1', listedIds: const ['v1']);
          expect(media, isNull,
              reason: 'the lookup before the request is not reused');
          expect(resolver.current(kind, 'r1', listedIds: const ['v1']), isNull,
              reason: 'the emptied catalogue now wins over the saved ids');
          expect(await resolver.resolve(kind, 'r1', listedIds: const ['v1']),
              isNull);
          expect(source.workerCalls, hasLength(1),
              reason: 'the failure is left alone for its back-off');
        });
      }

      test('an ordinary failure keeps what the device still holds', () async {
        source.held['v1'] = _heldPoster('v1');
        source.ends[_Source.keyOf(kind, 'r1')] = _Ends.transient;
        final resolver = _search(source);
        final media =
            await resolver.resolve(kind, 'r1', listedIds: const ['v1']);
        expect(media?.cacheKey, _key('v1'));
        expect(media?.isVideo, isTrue);
      });

      test('a lookup or saved-id read that throws costs nothing but itself',
          () async {
        source.listedThrows = true;
        source.lookupThrows = true;
        source.worker[_Source.keyOf(kind, 'r1')] = [_linked('w1')];
        final resolver = _search(source);
        expect(resolver.current(kind, 'r1', listedIds: const ['m1']), isNull);
        expect(
            (await resolver.resolve(kind, 'r1', listedIds: const ['m1']))
                ?.cacheKey,
            _key('w1'));
      });
    });
  }

  group('accounts, sessions and cards that are gone', () {
    late _Source source;
    setUp(() => source = _Source());

    test('another account signs in during the lookup: nothing, no Worker',
        () async {
      source.gateLookup = true;
      source.privateOnly['p1'] = _heldPhoto('p1');
      final resolver = _search(source);
      final pending =
          resolver.resolve(CardMediaKind.offer, 'r1', listedIds: const ['p1']);
      await pumpEventQueue();
      source.accountId = _other;
      source.lookupGates['offer:r1']!.complete();
      expect(await pending, isNull);
      expect(source.workerCalls, isEmpty);
    });

    test('a saved id of another account draws nothing', () async {
      source.held['m1'] = _heldPhoto('m1');
      source.accountId = _other;
      final resolver = _search(source);
      expect(
          resolver.current(CardMediaKind.offer, 'r1', listedIds: const ['m1']),
          isNull);
    });

    test('signed out: nothing is read and nothing is asked', () async {
      source.held['m1'] = _heldPhoto('m1');
      source.accountId = null;
      final resolver = _search(source);
      expect(
          resolver.current(CardMediaKind.offer, 'r1', listedIds: const ['m1']),
          isNull);
      expect(
          await resolver
              .resolve(CardMediaKind.offer, 'r1', listedIds: const ['m1']),
          isNull);
      expect(source.lookupCalls, isEmpty);
      expect(source.workerCalls, isEmpty);
    });

    test('a card gone before its turn: no lookup and no Worker', () async {
      final resolver = _search(source, maxConcurrent: 1);
      source.gateLookup = true;
      final first = resolver.resolve(CardMediaKind.offer, 'a');
      final second =
          resolver.resolve(CardMediaKind.offer, 'b', isWanted: () => false);
      await pumpEventQueue();
      source.lookupGates['offer:a']!.complete();
      await first;
      expect(await second, isNull);
      expect(source.lookupCalls.map((c) => c.$1), ['offer:a']);
    });

    test('a card scrolled away during the lookup: no Worker request', () async {
      var wanted = true;
      source.gateLookup = true;
      final resolver = _search(source);
      final pending = resolver.resolve(CardMediaKind.offer, 'r1',
          isWanted: () => wanted, listedIds: const ['s1']);
      await pumpEventQueue();
      wanted = false;
      source.lookupGates['offer:r1']!.complete();
      expect(await pending, isNull);
      expect(source.workerCalls, isEmpty);
    });
  });

  group('three at a time, shared, the lookup included', () {
    test('lookups and Worker requests together never exceed three', () async {
      final source = _Source()
        ..gateLookup = true
        ..gateWorker = true;
      final resolver = _search(source);
      final results = [
        for (var i = 0; i < 6; i++)
          resolver.resolve(CardMediaKind.offer, 'r$i', listedIds: ['s$i']),
      ];
      await pumpEventQueue();
      expect(source.lookupCalls, hasLength(3));
      expect(source.maxInFlight, 3);
      // Each lookup finds nothing and goes on to the Worker in its own slot.
      for (var i = 0; i < 3; i++) {
        source.lookupGates['offer:r$i']!.complete();
      }
      await pumpEventQueue();
      expect(source.workerCalls, hasLength(3));
      expect(source.lookupCalls, hasLength(3),
          reason: 'no new lookup until a slot is free');
      for (var i = 0; i < 3; i++) {
        source.workerGates['offer:r$i']!.complete();
      }
      await pumpEventQueue();
      for (var i = 3; i < 6; i++) {
        source.lookupGates['offer:r$i']!.complete();
      }
      await pumpEventQueue();
      for (var i = 3; i < 6; i++) {
        source.workerGates['offer:r$i']!.complete();
      }
      await Future.wait(results);
      expect(source.maxInFlight, 3);
      expect(source.workerCalls, hasLength(6));
    });

    test('two cards of one record share one lookup and one answer', () async {
      final source = _Source()..gateLookup = true;
      source.privateOnly['p1'] = _heldPhoto('p1');
      final resolver = _search(source);
      final one =
          resolver.resolve(CardMediaKind.owner, 'r1', listedIds: const ['p1']);
      final two =
          resolver.resolve(CardMediaKind.owner, 'r1', listedIds: const ['p1']);
      await pumpEventQueue();
      source.lookupGates['owner:r1']!.complete();
      expect((await one)?.cacheKey, _key('p1'));
      expect((await two)?.cacheKey, _key('p1'));
      expect(source.lookupCalls, hasLength(1));
      expect(source.workerCalls, isEmpty);
    });
  });

  group('without the Search setting (as Smart Map builds it)', () {
    test('saved ids and the lookup are never used; the Worker is asked',
        () async {
      final source = _Source();
      source.held['m1'] = _heldPhoto('m1');
      source.privateOnly['p1'] = _heldPhoto('p1');
      source.worker['offer:r1'] = [_linked('w1')];
      final resolver = _mapLike(source);
      expect(
          resolver.current(CardMediaKind.offer, 'r1',
              listedIds: const ['m1', 'p1']),
          isNull);
      final media = await resolver
          .resolve(CardMediaKind.offer, 'r1', listedIds: const ['m1', 'p1']);
      expect(media?.cacheKey, _key('w1'));
      expect(source.listedCalls, isEmpty);
      expect(source.lookupCalls, isEmpty);
      expect(source.workerCalls, ['offer:r1']);
    });

    test('its catalogue seed still skips the Worker, as before', () async {
      final source = _Source();
      source.catalogue['owner:r1'] = ['c1'];
      source.held['c1'] = _heldPhoto('c1');
      final resolver = _mapLike(source);
      expect((await resolver.resolve(CardMediaKind.owner, 'r1'))?.cacheKey,
          _key('c1'));
      expect(source.workerCalls, isEmpty);
    });
  });

  group('the Search cards pass the saved ids', () {
    setUpAll(prepareResponsiveAssets);
    late _Source source;
    late SearchCardMediaResolver resolver;
    setUp(() {
      source = _Source();
      resolver = _search(source);
      // The image itself never touches files here.
      PrivateMediaImages.debugLoad = (_, __) async => null;
    });
    tearDown(() => PrivateMediaImages.debugLoad = null);

    /// The cards of [results]; a later value of [results] is the same list
    /// read again (the page itself is built once, as a route is).
    Future<void> pumpCards(
        WidgetTester tester, ValueNotifier<List<SearchResult>> results) async {
      final optimistic =
          OptimisticFavoritesService(favoriteService: QuietFavoriteService());
      addTearDown(optimistic.dispose);
      await pumpResponsive(
        tester,
        const ResponsiveCase(Size(400, 900)),
        home: withR2ScreenProviders(
          Scaffold(
            body: ValueListenableBuilder<List<SearchResult>>(
              valueListenable: results,
              builder: (context, shown, _) => ListView(
                children: [
                  for (final r in shown)
                    SizedBox(
                      height: 260,
                      child: SearchResultCard(
                        key: ValueKey(r.stableKey),
                        result: r,
                        onTap: () {},
                        mediaResolver: resolver,
                      ),
                    ),
                ],
              ),
            ),
          ),
          favorites: optimistic,
        ),
      );
      await tester.pump();
    }

    SearchResult result(SearchResultType type, String id, Object data) =>
        SearchResult(
          id: id,
          title: 't',
          subtitle: 's',
          tinytitle: 'x',
          type: type,
          data: data,
          searchQuery: '',
        );

    testWidgets('an Offer card: its saved ids, and the held photo drawn',
        (tester) async {
      source.held['m1'] = _heldPhoto('m1');
      final offer = fixtures
          .offer(id: 'o1')
          .copyWith(listedMediaObjectIds: const ['gone', 'm1']);
      await pumpCards(
          tester, ValueNotifier([result(SearchResultType.offer, 'o1', offer)]));
      expect(source.listedCalls.first.$1, 'offer:o1');
      expect(source.listedCalls.first.$2, ['gone', 'm1']);
      final media =
          tester.widget<PrivateCardMedia>(find.byType(PrivateCardMedia));
      expect(media.cacheKey, _key('m1'));
      expect(source.workerCalls, isEmpty);
    });

    testWidgets('an Owner card: its saved ids reach the lookup',
        (tester) async {
      source.privateOnly['p1'] = _heldPhoto('p1');
      final owner =
          fixtures.owner(id: 'w1').copyWith(listedMediaObjectIds: ['p1']);
      await pumpCards(
          tester, ValueNotifier([result(SearchResultType.owner, 'w1', owner)]));
      await tester.pump();
      expect(source.lookupCalls.single.$1, 'owner:w1');
      expect(source.lookupCalls.single.$2, ['p1']);
      expect(source.workerCalls, isEmpty);
      expect(
          tester
              .widget<PrivateCardMedia>(find.byType(PrivateCardMedia))
              .cacheKey,
          _key('p1'));
    });

    testWidgets('Requests, Offices, Brokers and Watchmen ask nothing',
        (tester) async {
      await pumpCards(
          tester,
          ValueNotifier([
            result(SearchResultType.request, 'q1', fixtures.request(id: 'q1')),
            result(SearchResultType.office, 'f1', fixtures.office(id: 'f1')),
            result(SearchResultType.broker, 'b1', fixtures.broker(id: 'b1')),
            result(
                SearchResultType.watchmen, 'h1', fixtures.watchman(id: 'h1')),
          ]));
      expect(source.listedCalls, isEmpty);
      expect(source.lookupCalls, isEmpty);
      expect(source.workerCalls, isEmpty);
      expect(find.byType(PrivateCardMedia), findsNothing);
    });

    testWidgets('the same record read again with other ids is asked again',
        (tester) async {
      final before =
          fixtures.offer(id: 'o1').copyWith(listedMediaObjectIds: ['a']);
      final results =
          ValueNotifier([result(SearchResultType.offer, 'o1', before)]);
      addTearDown(results.dispose);
      source.held['a'] = _heldPhoto('a');
      await pumpCards(tester, results);
      expect(
          tester
              .widget<PrivateCardMedia>(find.byType(PrivateCardMedia))
              .cacheKey,
          _key('a'));
      source.held['b'] = _heldPhoto('b');
      final after =
          fixtures.offer(id: 'o1').copyWith(listedMediaObjectIds: ['b']);
      results.value = [result(SearchResultType.offer, 'o1', after)];
      await tester.pump();
      expect(source.listedCalls.last.$1, 'offer:o1');
      expect(source.listedCalls.last.$2, ['b']);
      expect(source.workerCalls, isEmpty);
      expect(
          tester
              .widget<PrivateCardMedia>(find.byType(PrivateCardMedia))
              .cacheKey,
          _key('b'));
    });

    testWidgets('a card closed during the lookup asks the Worker nothing',
        (tester) async {
      source.gateLookup = true;
      final offer =
          fixtures.offer(id: 'o1').copyWith(listedMediaObjectIds: ['s1']);
      await pumpCards(
          tester, ValueNotifier([result(SearchResultType.offer, 'o1', offer)]));
      await tester.pumpWidget(const SizedBox());
      source.lookupGates['offer:o1']!.complete();
      await tester.pump();
      expect(source.workerCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photo found after its card closed is not drawn into it',
        (tester) async {
      source.gateLookup = true;
      source.privateOnly['p1'] = _heldPhoto('p1');
      final offer =
          fixtures.offer(id: 'o1').copyWith(listedMediaObjectIds: ['p1']);
      await pumpCards(
          tester, ValueNotifier([result(SearchResultType.offer, 'o1', offer)]));
      expect(find.byType(PrivateCardMedia), findsNothing);
      await tester.pumpWidget(const SizedBox());
      source.lookupGates['offer:o1']!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'no setState on a card that is gone');
      expect(source.workerCalls, isEmpty);
    });
  });

  group('wiring', () {
    const resolverFile =
        'lib/src/views/Screens/home/search/search_card_media.dart';
    const sourceFile =
        'lib/src/views/Screens/home/search/search_card_media_source.dart';
    const viewModel = 'lib/src/views/Screens/home/search/search_viewmodel.dart';
    const card =
        'lib/src/views/Screens/home/search/widgets/search_result_card.dart';
    const mapViewModel = 'lib/src/views/Screens/home/map/map_viewmodel.dart';
    const mapView = 'lib/src/views/Screens/home/map/map_view.dart';

    test('Search alone switches the saved-ids lookup on', () {
      final vm = _squash(_read(viewModel));
      expect(
          vm.contains('final media = DefaultSearchCardMediaSource(); '
              'return SearchCardMediaResolver(source: media, heldMedia: media);'),
          isTrue);
      final map = _squash(_read(mapViewModel));
      expect(
          map.contains(
              'SearchCardMediaResolver(source: DefaultSearchCardMediaSource())'),
          isTrue,
          reason: 'Smart Map keeps its resolver exactly as before');
      for (final path in [mapViewModel, mapView]) {
        final text = _read(path);
        expect(text.contains('heldMedia'), isFalse, reason: path);
        expect(text.contains('listedIds'), isFalse, reason: path);
        expect(text.contains('listedMediaObjectIds'), isFalse, reason: path);
      }
    });

    test('the setting is typed, off by default, never a runtime type test', () {
      final text = _squash(_read(resolverFile));
      expect(text.contains('SearchCardHeldMedia? heldMedia,'), isTrue);
      expect(text.contains('is SearchCardHeldMedia'), isFalse);
      expect(text.contains('as SearchCardHeldMedia'), isFalse);
      expect(
          _squash(_read(sourceFile))
              .contains('class DefaultSearchCardMediaSource implements '
                  'SearchCardMediaSource, SearchCardHeldMedia {'),
          isTrue);
    });

    test('the lookup goes only to the existing read-only service helpers', () {
      final text = _read(sourceFile);
      for (final call in [
        '_offers.listedOfferMedia(',
        '_offers.discoverHeldOfferMedia(',
        '_owners.listedMedia(',
        '_owners.discoverHeldMedia(',
      ]) {
        expect(text.contains(call), isTrue, reason: call);
      }
      for (final path in [resolverFile, sourceFile]) {
        final text = _read(path);
        for (final banned in [
          'DefaultCacheManager',
          'getSingleFile',
          'mapMediaIdToLocalFile',
          'writeOfferMediaCatalog',
          'reconcileOfferMediaCatalog',
          'http.',
        ]) {
          expect(text.contains(banned), isFalse, reason: '$path: $banned');
        }
      }
    });

    test('the card hands Offer and Owner saved ids to both calls', () {
      final text = _squash(_read(card));
      expect(
          text.contains('_media = resolver.current(kind, id, listedIds: ids);'),
          isTrue);
      expect(text.contains('listedIds: ids,'), isTrue);
      expect(
          text.contains('if (data is OfferModel) return '
              'data.listedMediaObjectIds; '
              'if (data is OwnerModel) return data.listedMediaObjectIds;'),
          isTrue);
    });
  });
}
