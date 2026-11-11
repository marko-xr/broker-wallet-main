// M3b-1 (tracker §7AZ) measurement only, Windows test VM — NOT Samsung:
// what one screenful of 10 card photos costs through the private image path
// (Favorites, Search: `privateCache: true`) against the shared-cache path
// (Smart Map, unchanged), with controlled fakes.
//
// Scenarios: every photo held through a mapping; every photo only in the
// private cache (no mapping); nothing held but a link in hand. Counted:
// private-cache downloads, shared-cache downloads by link, shared-cache
// read-only looks, and the decode width of what is painted. A card itself
// never calls the Worker (its link comes from the screen's resolver), so
// Worker requests are 0 by construction here — not a claim about the whole
// Favorites or Search flow.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/views/Widgets/private_card_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _a = '11111111-1111-4111-8111-111111111111';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'cdcdcdcd-cdcd-4dcd-8dcd-${(++_n).toString().padLeft(12, '0')}';

class _Response implements FileServiceResponse {
  @override
  int get statusCode => 200;
  @override
  String get fileExtension => '.png';
  @override
  Stream<List<int>> get content => Stream.value(_png);
  @override
  int? get contentLength => _png.length;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 7));
  @override
  String? get eTag => null;
}

class _Transport extends FileService {
  int downloads = 0;
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    downloads++;
    return _Response();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('10 card photos: private path vs shared path (test VM)',
      (tester) async {
    late Directory documents, support, temp;
    late _Transport transport;
    late PrivateMediaCache cache;
    var sharedDownloads = 0, sharedLooks = 0;
    final lines = <String>[];

    await tester.runAsync(() async {
      documents = Directory.systemTemp.createTempSync('m3b1m_docs_');
      support = Directory.systemTemp.createTempSync('m3b1m_support_');
      temp = Directory.systemTemp.createTempSync('m3b1m_temp_');
      Hive.init(documents.path);
      OfflineMediaService.resolveDocumentsDirectory = () async => documents;
      OfflineMediaService.removeCachedBytes = (_) async {};
      await OfflineMediaService.instance.initialize();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => switch (call.method) {
          'getApplicationSupportDirectory' => support.path,
          'getTemporaryDirectory' => temp.path,
          'getApplicationDocumentsDirectory' => documents.path,
          _ => null,
        },
      );
      transport = _Transport();
      cache = PrivateMediaCache(
          currentScope: () =>
              const PrivateMediaScope(account: _a, session: 'session-1'),
          transport: transport);
      PrivateMediaImages.cache = () => cache;
      OfferMediaUrlCache.instance.clear();
      OfflineMediaService.fetchCachedBytes = (key, url) async {
        if (url == null) {
          sharedLooks++;
        } else {
          sharedDownloads++;
        }
        return null;
      };
    });

    Future<void> scenario(
      String name,
      Future<List<String>> Function() keys, {
      required bool privateCache,
      required bool withLink,
    }) async {
      late List<String> ids;
      await tester.runAsync(() async => ids = await keys());
      transport.downloads = 0;
      sharedDownloads = 0;
      sharedLooks = 0;
      final clock = Stopwatch()..start();
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: ListView(children: [
            for (final key in ids)
              SizedBox(
                width: 320,
                height: 180,
                child: PrivateCardMedia(
                  cacheKey: key,
                  isVideo: false,
                  signedUrl: withLink ? 'https://r2.example/$key.jpg' : null,
                  fallback: const SizedBox.expand(),
                  privateCache: privateCache,
                ),
              ),
          ]),
        ));
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await tester.pump();
        }
      });
      clock.stop();
      final widths = <int?>{
        for (final e in find.byType(Image).evaluate())
          if ((e.widget as Image).image case final ResizeImage r) r.width
      };
      lines.add('$name: privateDownloads=${transport.downloads} '
          'sharedDownloadsByLink=$sharedDownloads sharedReadOnlyLooks=$sharedLooks '
          'paintedImages=${find.byType(Image).evaluate().length} '
          'decodeWidths=$widths wallMs=${clock.elapsedMilliseconds}');
      await tester.pumpWidget(const SizedBox());
    }

    Future<List<String>> mappedKeys() async => [
          for (var i = 0; i < 10; i++)
            await () async {
              final key =
                  offerMediaCacheKey(ownerId: _a, mediaObjectId: _id())!;
              final f = File('${temp.path}${Platform.pathSeparator}${_n}.png')
                ..writeAsBytesSync(_png);
              await OfflineMediaService.instance
                  .mapMediaIdToLocalFile(key, f.path);
              return key;
            }(),
        ];

    Future<List<String>> privateOnlyKeys() async => [
          for (var i = 0; i < 10; i++)
            await () async {
              final key =
                  offerMediaCacheKey(ownerId: _a, mediaObjectId: _id())!;
              await cache.get(key,
                  signedUrl: () async => 'https://r2.example/x');
              return key;
            }(),
        ];

    Future<List<String>> missingKeys() async => [
          for (var i = 0; i < 10; i++)
            offerMediaCacheKey(ownerId: _a, mediaObjectId: _id())!,
        ];

    await scenario('held(mapping) private', mappedKeys,
        privateCache: true, withLink: true);
    await scenario('held(mapping) shared', mappedKeys,
        privateCache: false, withLink: true);
    await scenario('privateOnly private', privateOnlyKeys,
        privateCache: true, withLink: false);
    await scenario('missing+link private', missingKeys,
        privateCache: true, withLink: true);
    await scenario('missing+link shared', missingKeys,
        privateCache: false, withLink: true);

    // ignore: avoid_print
    print(lines.join('\n'));

    await tester.runAsync(() async {
      await cache.dispose();
      PrivateMediaImages.cache = () => PrivateMediaCache.instance;
      await Hive.close();
      for (final dir in [documents, support, temp]) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
