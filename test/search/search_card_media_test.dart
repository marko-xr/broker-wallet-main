// The photo (or video frame) a Search result card shows for an Offer or an
// Owner. The list read carries no media links, so each card asks for its own;
// these tests pin which media is chosen, that the server is asked as little as
// possible and never for a card nobody can see, and that the cards draw it
// through the one widget Favorites uses.
//
// The resolver is plain Dart and is run for real against a fake source; the
// wiring checks read the files.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_card_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = 'account-1';

String _key(String mediaId) =>
    offerMediaCacheKey(ownerId: _account, mediaObjectId: mediaId)!;

OfferMediaRef _photo(String id, {bool onDevice = false}) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: _key(id),
      signedUrl: onDevice ? null : 'https://media.example/$id',
      localFilePath: onDevice ? '/device/$id.jpg' : null,
    );

OfferMediaRef _video(String id, {String? poster}) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: _key(id),
      signedUrl: 'https://media.example/$id',
      isVideo: true,
      posterPath: poster,
    );

OfferMediaResolution _resolution(List<OfferMediaRef> items) =>
    OfferMediaResolution(offerId: 'r', ownerId: _account, items: items);

class _FakeSource implements SearchCardMediaSource {
  @override
  String? accountId = _account;

  /// What this device holds, by `kind:id`.
  final Map<String, List<OfferMediaRef>> held = {};

  /// What the server answers, by `kind:id`; a missing entry is "no media".
  final Map<String, OfferMediaResolution?> answers = {};

  final Set<String> failing = {};
  bool heldThrows = false;

  /// With [gated], a request waits until its gate is opened.
  bool gated = false;
  final Map<String, Completer<void>> gates = {};

  final List<String> calls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  static String keyOf(CardMediaKind kind, String id) => '${kind.name}:$id';

  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) {
    if (heldThrows) throw StateError('catalogue unreadable');
    return held[keyOf(kind, recordId)] ?? const <OfferMediaRef>[];
  }

  @override
  Future<OfferMediaResolution?> resolve(
    CardMediaKind kind,
    String recordId,
    String accountId,
  ) async {
    final key = keyOf(kind, recordId);
    calls.add(key);
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    try {
      if (gated) {
        final gate = gates[key] = Completer<void>();
        await gate.future;
      }
      if (failing.contains(key)) throw StateError('offline');
      return answers.containsKey(key)
          ? answers[key]
          : _resolution(const <OfferMediaRef>[]);
    } finally {
      inFlight--;
    }
  }

  void open(CardMediaKind kind, String id) =>
      gates[keyOf(kind, id)]!.complete();
}

class _Clock {
  DateTime now = DateTime(2026, 10, 7, 12);
  void advance(Duration by) => now = now.add(by);
  DateTime call() => now;
}

SearchCardMediaResolver _resolver(
  _FakeSource source, {
  _Clock? clock,
  int maxConcurrent = 3,
}) =>
    SearchCardMediaResolver(
      source: source,
      clock: (clock ?? _Clock()).call,
      maxConcurrent: maxConcurrent,
    );

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('which media a card shows', () {
    test('a video that comes first never hides the photo behind it', () async {
      final source = _FakeSource()
        ..answers['offer:o1'] = _resolution([_video('v1'), _photo('p1')]);
      final media = await _resolver(source).resolve(CardMediaKind.offer, 'o1');
      expect(media, isNotNull);
      expect(media!.cacheKey, _key('p1'));
      expect(media.isVideo, isFalse);
    });

    test('only videos: the first video\'s frame', () async {
      final source = _FakeSource()
        ..answers['offer:o1'] = _resolution([_video('v1'), _video('v2')]);
      final media = await _resolver(source).resolve(CardMediaKind.offer, 'o1');
      expect(media!.cacheKey, _key('v1'));
      expect(media.isVideo, isTrue);
    });

    test('the first photo, when several come in the server\'s order', () async {
      final source = _FakeSource()
        ..answers['owner:w1'] =
            _resolution([_video('v1'), _photo('p1'), _photo('p2')]);
      final media = await _resolver(source).resolve(CardMediaKind.owner, 'w1');
      expect(media!.cacheKey, _key('p1'));
    });

    test('an Owner is asked about as an Owner, an Offer as an Offer', () async {
      final source = _FakeSource()
        ..answers['owner:w1'] = _resolution([_photo('p1')])
        ..answers['offer:o1'] = _resolution([_photo('p2')]);
      final resolver = _resolver(source);
      await resolver.resolve(CardMediaKind.owner, 'w1');
      await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(source.calls, ['owner:w1', 'offer:o1']);
    });

    test('a record with no media draws nothing, and that is remembered',
        () async {
      final source = _FakeSource();
      final resolver = _resolver(source);
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull);
      expect(source.calls, ['offer:o1']);
    });

    test('the Firebase backend (no media stage) draws nothing from here',
        () async {
      final source = _FakeSource()..answers['offer:o1'] = null;
      final resolver = _resolver(source);
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      expect(source.calls, hasLength(1));
    });

    test('no session and no id: nothing is asked', () async {
      final source = _FakeSource()..accountId = null;
      final resolver = _resolver(source);
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      source.accountId = '  ';
      expect(await resolver.resolve(CardMediaKind.offer, 'o1'), isNull);
      source.accountId = _account;
      expect(await resolver.resolve(CardMediaKind.offer, '   '), isNull);
      expect(resolver.current(CardMediaKind.offer, ''), isNull);
      expect(source.calls, isEmpty);
    });
  });

  group('what this device already holds', () {
    test('a photo it holds is the picture, and nothing is asked', () async {
      final source = _FakeSource()
        ..held['offer:o1'] = [_photo('p1', onDevice: true)];
      final resolver = _resolver(source);
      expect(resolver.current(CardMediaKind.offer, 'o1')!.cacheKey, _key('p1'));
      final media = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(media!.cacheKey, _key('p1'));
      expect(source.calls, isEmpty);
    });

    test(
        'only a video frame held: it draws at once, then the server may '
        'find a photo', () async {
      final source = _FakeSource()
        ..held['offer:o1'] = [_video('v1', poster: '/device/v1.jpg')]
        ..answers['offer:o1'] = _resolution([_video('v1'), _photo('p9')]);
      final resolver = _resolver(source);

      final first = resolver.current(CardMediaKind.offer, 'o1');
      expect(first!.isVideo, isTrue);
      expect(first.posterPath, '/device/v1.jpg');

      final media = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(media!.cacheKey, _key('p9'));
      expect(media.isVideo, isFalse);
      expect(source.calls, ['offer:o1']);
      // From now on the card starts with the photo.
      expect(resolver.current(CardMediaKind.offer, 'o1')!.cacheKey, _key('p9'));
    });

    test('an unreadable catalogue is the same as holding nothing', () async {
      final source = _FakeSource()
        ..heldThrows = true
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source);
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull);
      final media = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(media!.cacheKey, _key('p1'));
    });
  });

  group('asking the server as little as possible', () {
    test('cards asking about the same record share one request', () async {
      final source = _FakeSource()
        ..gated = true
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source);
      final a = resolver.resolve(CardMediaKind.offer, 'o1');
      final b = resolver.resolve(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      source.open(CardMediaKind.offer, 'o1');
      final answers = await Future.wait([a, b]);
      expect(source.calls, hasLength(1));
      expect(answers[0]!.cacheKey, _key('p1'));
      expect(answers[1]!.cacheKey, _key('p1'));
    });

    test('an answer is remembered for a while, then asked again', () async {
      final clock = _Clock();
      final source = _FakeSource()
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source, clock: clock);
      await resolver.resolve(CardMediaKind.offer, 'o1');
      clock.advance(const Duration(minutes: 4, seconds: 59));
      await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(source.calls, hasLength(1));
      clock.advance(const Duration(seconds: 1));
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull,
          reason: 'an old answer is not trusted for the first frame');
      await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(source.calls, hasLength(2));
    });

    test('a clock that went back does not keep an answer alive', () async {
      final clock = _Clock();
      final source = _FakeSource()
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source, clock: clock);
      await resolver.resolve(CardMediaKind.offer, 'o1');
      clock.advance(const Duration(hours: -2));
      await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(source.calls, hasLength(2));
    });

    test('when the records are read again, nothing is remembered', () async {
      final source = _FakeSource()
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source);
      await resolver.resolve(CardMediaKind.offer, 'o1');
      resolver.invalidate();
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull);
      source.answers['offer:o1'] = _resolution([_photo('p2')]);
      final media = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(media!.cacheKey, _key('p2'));
      expect(source.calls, hasLength(2));
    });

    test('a request that was running during the re-read is shown, not kept',
        () async {
      final source = _FakeSource()
        ..gated = true
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source);
      final pending = resolver.resolve(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      resolver.invalidate();
      source.open(CardMediaKind.offer, 'o1');
      expect((await pending)!.cacheKey, _key('p1'));
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull);
    });

    test('another account signing in drops what was asked for the first',
        () async {
      final source = _FakeSource()
        ..gated = true
        ..answers['offer:o1'] = _resolution([_photo('p1')]);
      final resolver = _resolver(source);
      final pending = resolver.resolve(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      source.accountId = 'someone-else';
      source.open(CardMediaKind.offer, 'o1');
      expect(await pending, isNull);
      expect(resolver.current(CardMediaKind.offer, 'o1'), isNull);
    });
  });

  group('a failure', () {
    test('keeps what the device holds, and is not retried at once', () async {
      final clock = _Clock();
      final source = _FakeSource()
        ..failing.add('offer:o1')
        ..held['offer:o1'] = [_video('v1', poster: '/device/v1.jpg')];
      final resolver = _resolver(source, clock: clock);

      final media = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(media!.isVideo, isTrue);
      expect(media.posterPath, '/device/v1.jpg');

      // Scrolled away and back: no second request while it is fresh.
      final again = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(again!.cacheKey, _key('v1'));
      expect(source.calls, hasLength(1));

      clock.advance(const Duration(seconds: 30));
      source.failing.clear();
      source.answers['offer:o1'] = _resolution([_photo('p1')]);
      final healed = await resolver.resolve(CardMediaKind.offer, 'o1');
      expect(healed!.cacheKey, _key('p1'));
      expect(source.calls, hasLength(2));
    });

    test('with nothing held, the card simply keeps its icon', () async {
      final source = _FakeSource()..failing.add('owner:w1');
      final resolver = _resolver(source);
      expect(await resolver.resolve(CardMediaKind.owner, 'w1'), isNull);
      expect(resolver.current(CardMediaKind.owner, 'w1'), isNull);
    });
  });

  group('only what is on screen is asked, a few at a time', () {
    test('at most maxConcurrent at once, in the order the cards asked',
        () async {
      final source = _FakeSource()..gated = true;
      for (var i = 1; i <= 5; i++) {
        source.answers['offer:o$i'] = _resolution([_photo('p$i')]);
      }
      final resolver = _resolver(source, maxConcurrent: 2);
      final results = [
        for (var i = 1; i <= 5; i++)
          resolver.resolve(CardMediaKind.offer, 'o$i'),
      ];
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2']);

      source.open(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2', 'offer:o3']);

      for (var i = 2; i <= 5; i++) {
        await pumpEventQueue();
        source.open(CardMediaKind.offer, 'o$i');
      }
      final done = await Future.wait(results);
      expect(source.calls, [for (var i = 1; i <= 5; i++) 'offer:o$i']);
      expect(source.maxInFlight, 2);
      expect([for (final m in done) m!.cacheKey],
          [for (var i = 1; i <= 5; i++) _key('p$i')]);
    });

    test('a freed slot goes to the next in line; a newcomer still waits',
        () async {
      final source = _FakeSource()..gated = true;
      for (var i = 1; i <= 4; i++) {
        source.answers['offer:o$i'] = _resolution([_photo('p$i')]);
      }
      final resolver = _resolver(source, maxConcurrent: 2);
      final first = resolver.resolve(CardMediaKind.offer, 'o1');
      final second = resolver.resolve(CardMediaKind.offer, 'o2');
      final queued = resolver.resolve(CardMediaKind.offer, 'o3');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2']);

      source.open(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2', 'offer:o3'],
          reason: 'the slot went to the record that was waiting');

      // Two are running again (o2 and o3), so this one waits.
      final newcomer = resolver.resolve(CardMediaKind.offer, 'o4');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2', 'offer:o3']);

      source.open(CardMediaKind.offer, 'o2');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o2', 'offer:o3', 'offer:o4']);
      source.open(CardMediaKind.offer, 'o3');
      source.open(CardMediaKind.offer, 'o4');
      await Future.wait([first, second, queued, newcomer]);
      expect(source.maxInFlight, 2);
    });

    test('a card that scrolled away before its turn costs no request',
        () async {
      final source = _FakeSource()..gated = true;
      for (final id in ['o1', 'o2', 'o3']) {
        source.answers['offer:$id'] = _resolution([_photo('p-$id')]);
      }
      final resolver = _resolver(source, maxConcurrent: 1);
      var stillThere = true;
      final first = resolver.resolve(CardMediaKind.offer, 'o1');
      final gone = resolver.resolve(CardMediaKind.offer, 'o2',
          isWanted: () => stillThere);
      final last = resolver.resolve(CardMediaKind.offer, 'o3');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1']);

      stillThere = false;
      source.open(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      expect(source.calls, ['offer:o1', 'offer:o3'],
          reason: 'o2 was skipped without a request');
      source.open(CardMediaKind.offer, 'o3');

      expect((await first)!.cacheKey, _key('p-o1'));
      expect(await gone, isNull);
      expect((await last)!.cacheKey, _key('p-o3'));
      expect(source.calls, isNot(contains('offer:o2')));
    });

    test('a skipped record is asked about when a card wants it again',
        () async {
      final source = _FakeSource()
        ..gated = true
        ..answers['offer:o1'] = _resolution([_photo('p1')])
        ..answers['offer:o2'] = _resolution([_photo('p2')]);
      final resolver = _resolver(source, maxConcurrent: 1);
      final blocker = resolver.resolve(CardMediaKind.offer, 'o1');
      var firstCardThere = true;
      final firstCard = resolver.resolve(CardMediaKind.offer, 'o2',
          isWanted: () => firstCardThere);
      // The first card leaves, and another card for the same record arrives
      // while it is still waiting: the request must still happen.
      firstCardThere = false;
      final secondCard = resolver.resolve(CardMediaKind.offer, 'o2');
      await pumpEventQueue();
      source.open(CardMediaKind.offer, 'o1');
      await pumpEventQueue();
      source.open(CardMediaKind.offer, 'o2');
      await blocker;
      expect((await secondCard)!.cacheKey, _key('p2'));
      expect((await firstCard)!.cacheKey, _key('p2'),
          reason: 'they shared the one request');
      expect(source.calls, ['offer:o1', 'offer:o2']);
    });

    test('a record skipped once is asked about when a card wants it later',
        () async {
      final source = _FakeSource()
        ..gated = true
        ..answers['offer:o1'] = _resolution([_photo('p1')])
        ..answers['offer:o2'] = _resolution([_photo('p2')]);
      final resolver = _resolver(source, maxConcurrent: 1);
      final blocker = resolver.resolve(CardMediaKind.offer, 'o1');
      final skipped =
          resolver.resolve(CardMediaKind.offer, 'o2', isWanted: () => false);
      await pumpEventQueue();
      source.open(CardMediaKind.offer, 'o1');
      await blocker;
      expect(await skipped, isNull);
      expect(source.calls, ['offer:o1']);

      // The card is back on screen: now it is asked.
      final back = resolver.resolve(CardMediaKind.offer, 'o2');
      await pumpEventQueue();
      source.open(CardMediaKind.offer, 'o2');
      expect((await back)!.cacheKey, _key('p2'));
      expect(source.calls, ['offer:o1', 'offer:o2']);
    });
  });

  group('the cards draw it, through the one widget Favorites uses', () {
    const card =
        'lib/src/views/Screens/home/search/widgets/search_result_card.dart';
    const view = 'lib/src/views/Screens/home/search/search_view.dart';
    const viewModel = 'lib/src/views/Screens/home/search/search_viewmodel.dart';
    const shared = 'lib/src/views/Widgets/private_card_media.dart';
    const favoritesCard =
        'lib/src/views/Screens/home/favorites/favorites_card.dart';
    const resolverFile =
        'lib/src/views/Screens/home/search/search_card_media.dart';

    test('the card asks for its own media, and only while it is there', () {
      final source = _squash(_read(card));
      expect(source.contains('final SearchCardMediaResolver? mediaResolver;'),
          isTrue);
      expect(source.contains('_media = resolver.current(kind, id);'), isTrue,
          reason: 'what is known is drawn on the first frame');
      expect(
          source
              .contains('isWanted: () => mounted && request == _mediaRequest,'),
          isTrue,
          reason: 'a card that is gone costs no request');
      expect(
          source.contains('if (!mounted || request != _mediaRequest) return;'),
          isTrue,
          reason: 'a late answer for another result is ignored');
      // Only Offers and Owners have private media.
      expect(
          source.contains(
              'case SearchResultType.offer: return CardMediaKind.offer; '
              'case SearchResultType.owner: return CardMediaKind.owner;'),
          isTrue);
      expect(
          source.contains('case SearchResultType.request: '
              'case SearchResultType.office: '
              'case SearchResultType.broker: '
              'case SearchResultType.watchmen: '
              'return null;'),
          isTrue,
          reason: 'Requests, Offices, Brokers and Watchmen have no private '
              'media');
    });

    test('the picture is the shared widget, ahead of the plain link', () {
      final source = _squash(_read(card));
      expect(source.contains('media: _media,'), isTrue);
      expect(
          source.contains('final media = widget.media; if (media != null) { '
              'return PrivateCardMedia( cacheKey: media.cacheKey, '
              'isVideo: media.isVideo, signedUrl: media.signedUrl, '
              'posterPath: media.posterPath,'),
          isTrue);
      expect(source.contains('if (widget.media == null) _checkImageCache();'),
          isTrue,
          reason: 'a private picture is not probed as a plain URL');
    });

    test('Search hands every card the view model\'s resolver', () {
      expect(_squash(_read(view)).contains('mediaResolver: vm.cardMedia,'),
          isTrue);
    });

    test('the view model forgets what was asked whenever it reads again', () {
      final source = _squash(_read(viewModel));
      expect(
          source.contains('_corpus = _engine.index(data); '
              'cardMedia.invalidate();'),
          isTrue);
      expect(
          source.contains(
              'SearchCardMediaResolver(source: DefaultSearchCardMediaSource())'),
          isTrue);
    });

    test('Favorites draws the same widget and no longer has its own copy', () {
      final source = _read(favoritesCard);
      expect(
          _squash(source).contains('return PrivateCardMedia( '
              'cacheKey: media.cacheKey, isVideo: media.isVideo, '
              'signedUrl: media.signedUrl, posterPath: media.posterPath,'),
          isTrue);
      for (final gone in [
        'OfferVideoPoster',
        '_keepPhotoOnDevice',
        '_buildPrivateMedia',
        'ensureMediaIdCached',
      ]) {
        expect(source.contains(gone), isFalse, reason: gone);
      }
    });

    test('the shared widget keeps the rules Favorites was built on', () {
      final source = _squash(_read(shared));
      // A photo is cached by identity, never by its link; bytes held win.
      expect(
          source.contains(
              'imageUrl: widget.signedUrl ?? \'\', cacheKey: widget.cacheKey,'),
          isTrue,
          reason: 'the photo is cached under its identity, not its link');
      expect(source.contains('cacheKey: widget.cacheKey,'), isTrue);
      expect(
          source.contains('OfflineMediaService.instance.ensureMediaIdCached('),
          isTrue,
          reason: 'the photo is kept on the device for the next open');
      expect(
          source.contains(
              'if (widget.isVideo || url == null || url.isEmpty) return;'),
          isTrue,
          reason: 'a video is never downloaded to be kept');
      // A video shows its still frame with a play mark, never as a photo.
      expect(source.contains('return OfferVideoPoster('), isTrue);
      expect(source.contains('Icons.play_circle_fill_rounded'), isTrue);
    });

    test(
        'no media type crosses the shared widget, so no import spelling can '
        'make two of them', () {
      // `Views` and `views` are different libraries to Dart, and the analyzer
      // reads each file under its spelling on disk (`views`) while the app
      // reaches the Favorites files as `Views`. A type that crossed a
      // relative import on one side and an explicit one on the other failed
      // to compile in one of the two. The shared widget takes plain values.
      final source = _read(shared);
      expect(source.contains('FavoriteCardMedia'), isFalse);
      expect(source.contains('favorite_card_media'), isFalse);
      expect(source.contains('/Screens/'), isFalse,
          reason: 'a shared widget does not reach into a screen\'s files');
      expect(
          RegExp(r"^import '([^']+)';", multiLine: true)
              .allMatches(source)
              .map((m) => m.group(1)!)
              .toList(),
          [
            'dart:async',
            'package:broker_wallet/src/services/offline_media_service.dart',
            'package:broker_wallet/src/views/Widgets/offer_video_poster.dart',
            'package:flutter/material.dart',
          ]);
    });

    test('the Search card names its media type and its resolver one way', () {
      // Both come from one spelling (`Views`, as the card's other imports), so
      // what the resolver returns is the type the card holds.
      final source = _read(card);
      expect(
          source.contains(
              "package:broker_wallet/src/Views/Screens/home/favorites/favorite_card_media.dart"),
          isTrue);
      expect(
          source.contains(
              "package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart"),
          isTrue);
      expect(
          source.contains(
              "package:broker_wallet/src/views/Screens/home/favorites/favorite_card_media.dart"),
          isFalse);
      expect(
          source.contains(
              "package:broker_wallet/src/views/Screens/home/search/search_card_media.dart"),
          isFalse);
    });

    test('the resolver is plain Dart: no widgets, no services', () {
      final source = _read(resolverFile);
      final imports = RegExp(r"^import '([^']+)';", multiLine: true)
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();
      expect(imports, [
        'dart:async',
        'dart:collection',
        'package:broker_wallet/src/services/offer_media_cache_identity.dart',
        '../favorites/favorite_card_media.dart',
      ]);
    });

    test('the plain URL path stays for records that carry one', () {
      final engine =
          _read('lib/src/views/Screens/home/search/search_engine.dart');
      expect(
          engine.contains(
              'imageUrl: o.mediaUrls.isNotEmpty ? o.mediaUrls.first : o.mediaUrl,'),
          isTrue);
    });
  });
}
