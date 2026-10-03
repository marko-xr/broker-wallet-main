import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';

import 'share_fixtures.dart';

const String _linkA = 'https://store.example/obj-a?sig=aaa&exp=1';
const String _linkB = 'https://store.example/obj-b?sig=bbb&exp=2';

Future<ShareFailure> failureOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on ShareFailure catch (failure) {
    return failure;
  }
  fail('expected a ShareFailure');
}

void main() {
  late TempArea area;
  late FakeNet net;
  late Directory scratch;

  setUp(() {
    area = TempArea();
    net = FakeNet();
    scratch = Directory('${area.root.path}/scratch')..createSync();
  });
  tearDown(() => area.dispose());

  ShareMediaFetcher fetcher({
    Future<String?> Function(String key)? localPath,
    String? Function(String key)? cachedLink,
    int? maxImageBytes,
    int? maxVideoBytes,
  }) =>
      newFetcher(
        client: net.client(),
        localPath: localPath,
        cachedLink: cachedLink,
        maxImageBytes: maxImageBytes,
        maxVideoBytes: maxVideoBytes,
      );

  Future<FetchedShareFile> fetch(
    ShareMediaFetcher f,
    ShareMediaItem item, {
    LinkRefresher? refresh,
    ShareCancelToken? cancel,
  }) =>
      f
          .attachmentFor(item, baseName: 'x', refreshLink: refresh)
          .fetch(scratch, cancel ?? ShareCancelToken());

  ShareMediaItem photo(String id, {String? url, String? local}) => mediaItems(
          <OfferMediaRef>[mediaRef(id, signedUrl: url, localFilePath: local)])
      .single;

  group('bytes the phone already holds', () {
    test('a file the gallery already has is used as it is, with no network',
        () async {
      final file = area.writeCacheFile('held.jpg', jpegBytes());
      final result =
          await fetch(fetcher(), photo('a', url: _linkA, local: file.path));
      expect(result.file.path, file.path);
      expect(result.isTemporary, isFalse);
      expect(net.requested, isEmpty);
    });

    test('a file found by the media identity is used with no network',
        () async {
      final file = area.writeCacheFile('mapped.jpg', jpegBytes());
      String? askedFor;
      final result = await fetch(
        fetcher(localPath: (key) async {
          askedFor = key;
          return file.path;
        }),
        photo('a', url: _linkA),
      );
      expect(result.file.path, file.path);
      expect(result.isTemporary, isFalse);
      expect(askedFor, 'offer-media:user-1:a');
      expect(net.requested, isEmpty);
    });

    test('a lookup that fails, or names a missing file, falls through',
        () async {
      net.bodies[_linkA] = jpegBytes();
      final broken = await fetch(
        fetcher(localPath: (key) async => throw StateError('hive closed')),
        photo('a', url: _linkA),
      );
      expect(broken.isTemporary, isTrue);

      final missing = await fetch(
        fetcher(localPath: (key) async => '${area.root.path}/gone.jpg'),
        photo('a', url: _linkA),
      );
      expect(missing.isTemporary, isTrue);
      expect(net.requested, <String>[_linkA, _linkA]);
    });

    test('an empty local file is not used', () async {
      final empty = area.writeCacheFile('empty.jpg', <int>[]);
      net.bodies[_linkA] = jpegBytes();
      final result =
          await fetch(fetcher(), photo('a', url: _linkA, local: empty.path));
      expect(result.isTemporary, isTrue);
    });
  });

  group('downloading', () {
    test('streams the bytes into the share\'s own folder', () async {
      net.bodies[_linkA] = jpegBytes(5000);
      final result = await fetch(fetcher(), photo('a', url: _linkA));
      expect(result.isTemporary, isTrue);
      expect(result.file.parent.path, scratch.path);
      expect(result.file.readAsBytesSync(), jpegBytes(5000));
      expect(net.requested, <String>[_linkA]);
    });

    test('tries a link still known to be valid before the one it was given',
        () async {
      net.statuses[_linkA] = 403;
      net.bodies[_linkB] = jpegBytes();
      final result = await fetch(
        fetcher(cachedLink: (key) => _linkA),
        photo('a', url: _linkB),
      );
      expect(result.isTemporary, isTrue);
      expect(net.requested, <String>[_linkA, _linkB]);
    });

    test('never asks twice for the same link', () async {
      net.statuses[_linkA] = 403;
      final failure = await failureOf(() => fetch(
            fetcher(cachedLink: (key) => _linkA),
            photo('a', url: _linkA),
          ));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(net.requested, <String>[_linkA]);
    });

    test(
        'a refused link is replaced by a fresh one from the record\'s own path',
        () async {
      net.statuses[_linkA] = 403;
      net.bodies[_linkB] = mp4Bytes();
      final asked = <String>[];
      final result = await fetch(
        fetcher(),
        mediaItems(<OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkA)
        ]).single,
        refresh: (id) async {
          asked.add(id);
          return _linkB;
        },
      );
      expect(result.file.readAsBytesSync(), mp4Bytes());
      expect(asked, <String>['video-1']);
      expect(net.requested, <String>[_linkA, _linkB]);
    });

    test('an item with no link at all asks for one', () async {
      net.bodies[_linkB] = jpegBytes();
      final item = mediaItems(<OfferMediaRef>[mediaRef('only-id')]).single;
      final result =
          await fetch(fetcher(), item, refresh: (id) async => _linkB);
      expect(result.isTemporary, isTrue);
      expect(net.requested, <String>[_linkB]);
    });

    test('a fresh link that is refused too means the file is not available',
        () async {
      net.statuses[_linkA] = 403;
      net.statuses[_linkB] = 403;
      final failure = await failureOf(() => fetch(
            fetcher(),
            photo('a', url: _linkA),
            refresh: (id) async => _linkB,
          ));
      expect(failure.kind, ShareFailureKind.unavailable);
    });

    test('no fresh link could be had: a retry may help', () async {
      net.statuses[_linkA] = 403;
      final nothing = await failureOf(() => fetch(
            fetcher(),
            photo('a', url: _linkA),
            refresh: (id) async => null,
          ));
      expect(nothing.kind, ShareFailureKind.network);

      final threw = await failureOf(() => fetch(
            fetcher(),
            photo('a', url: _linkA),
            refresh: (id) async => throw StateError(_linkA),
          ));
      expect(threw.kind, ShareFailureKind.network);
      expect(threw.toString().contains('store.example'), isFalse);
    });

    test('a refused link and no way to ask for another is unavailable',
        () async {
      net.statuses[_linkA] = 403;
      final failure =
          await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
      expect(failure.kind, ShareFailureKind.unavailable);
    });

    test('a file that is gone is unavailable', () async {
      for (final status in <int>[404, 410]) {
        net.statuses[_linkA] = status;
        final failure =
            await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
        expect(failure.kind, ShareFailureKind.unavailable, reason: '$status');
      }
    });

    test('a server that is struggling is a failure a retry may fix', () async {
      for (final status in <int>[500, 502, 503, 408, 429]) {
        net.statuses[_linkA] = status;
        final failure =
            await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
        expect(failure.kind, ShareFailureKind.network, reason: '$status');
      }
    });

    test('any other refusal is unavailable', () async {
      net.statuses[_linkA] = 400;
      final failure =
          await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
      expect(failure.kind, ShareFailureKind.unavailable);
    });

    test('being offline is a network failure that carries no text', () async {
      for (final error in <Object>[
        const SocketException('connection refused https://store.example/x'),
        http.ClientException('failed', Uri.parse(_linkA)),
        TimeoutException('slow'),
      ]) {
        net.failures[_linkA] = error;
        final failure =
            await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
        expect(failure.kind, ShareFailureKind.network, reason: '$error');
        expect(failure.toString(), 'ShareFailure(network)');
      }
    });

    test('an empty answer is unavailable', () async {
      net.bodies[_linkA] = <int>[];
      final failure =
          await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
      expect(failure.kind, ShareFailureKind.unavailable);
    });

    test('only web links are fetched', () async {
      for (final link in <String>[
        'file:///etc/passwd',
        'content://media/external/1',
        'javascript:alert(1)',
        'not a link',
      ]) {
        final failure =
            await failureOf(() => fetch(fetcher(), photo('a', url: link)));
        expect(failure.kind, ShareFailureKind.unavailable, reason: link);
      }
      expect(net.requested, isEmpty);
    });
  });

  group('size ceiling', () {
    test('a file declared larger than a photo may be is refused unread',
        () async {
      net.bodies[_linkA] = List<int>.filled(2000, 1);
      final failure = await failureOf(
          () => fetch(fetcher(maxImageBytes: 1000), photo('a', url: _linkA)));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(scratch.listSync(), isEmpty);
    });

    test('the video ceiling applies to a video', () async {
      net.bodies[_linkA] = List<int>.filled(2000, 1);
      final video = mediaItems(
              <OfferMediaRef>[mediaRef('v', video: true, signedUrl: _linkA)])
          .single;
      final tooSmall =
          await failureOf(() => fetch(fetcher(maxVideoBytes: 1000), video));
      expect(tooSmall.kind, ShareFailureKind.unavailable);

      net.bodies[_linkA] = mp4Bytes(1200);
      final ok = await fetch(fetcher(maxVideoBytes: 5000), video);
      expect(ok.file.lengthSync(), mp4Bytes(1200).length);
    });

    test('a stream that never says its size is cut off, leaving no file',
        () async {
      // The client reports no length: the ceiling is enforced as bytes arrive.
      final unsized = MockClient.streaming((request, body) async {
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < 10; i++) {
            yield List<int>.filled(300, 1);
          }
        }

        return http.StreamedResponse(chunks(), 200);
      });
      final f = newFetcher(client: unsized, maxImageBytes: 1000);
      final failure = await failureOf(() => f
          .attachmentFor(photo('a', url: _linkA), baseName: 'x')
          .fetch(scratch, ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(scratch.listSync(), isEmpty);
    });
  });

  group('failing and stopping leave nothing behind', () {
    test('a failed download removes its partial file', () async {
      net.statuses[_linkA] = 500;
      await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
      expect(scratch.listSync(), isEmpty);
    });

    test('cancelling stops a download part-way and removes the partial file',
        () async {
      net.bodies[_linkA] = List<int>.filled(500, 1);
      final gate = Completer<List<int>>();
      net.held[_linkA] = gate;
      final token = ShareCancelToken();

      final pending = fetch(fetcher(), photo('a', url: _linkA), cancel: token);
      // Let the first chunk arrive, then call the share off and release the rest.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.cancel();
      gate.complete(List<int>.filled(500, 2));

      var cancelled = false;
      try {
        await pending;
      } on ShareCancelled {
        cancelled = true;
      }
      expect(cancelled, isTrue);
      expect(scratch.listSync(), isEmpty);
    });

    test('the link never reaches a failure or its text', () async {
      net.statuses[_linkA] = 404;
      final failure =
          await failureOf(() => fetch(fetcher(), photo('a', url: _linkA)));
      for (final text in <String>[failure.toString(), failure.kind.name]) {
        expect(text.contains('store.example'), isFalse);
        expect(text.contains('sig='), isFalse);
      }
    });
  });

  group('with the preparer', () {
    test('a downloaded photo and video are shared under their real types',
        () async {
      net.bodies[_linkA] = pngBytes();
      net.bodies[_linkB] = mp4Bytes();
      final f = fetcher();
      final items = mediaItems(<OfferMediaRef>[
        mediaRef('p', signedUrl: _linkA),
        mediaRef('v', video: true, signedUrl: _linkB),
      ]);
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        f.attachmentFor(items[0], baseName: 'Offer-01'),
        f.attachmentFor(items[1], baseName: 'Offer-02'),
      ], ShareCancelToken());

      expect(bundle.files.map((x) => x.name).toList(),
          <String>['Offer-01.png', 'Offer-02.mp4']);
      expect(bundle.files.map((x) => x.mimeType).toList(),
          <String>['image/png', 'video/mp4']);
      // Only the two named files are left in the folder: no partial downloads.
      expect(bundle.directory.listSync(), hasLength(2));
    });
  });
}
