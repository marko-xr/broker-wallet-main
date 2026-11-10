// M2-3b (tracker §7AZ) measurement only, on the Windows test VM — NOT
// Samsung: the cost of finding held Offer/Owner Details media through the
// saved list's media identity.
//
// For 0, 1 and 10 media ids (10 is the Worker's per-record maximum), with
// every image's bytes held:
//   - first-frame seed (`listedRecordMedia`, synchronous): microseconds per
//     call, with bytes reached through a mapping;
//   - read-only lookup (`discoverHeldRecordMedia`), with the bytes only in
//     the private cache (no mapping): milliseconds per call;
//   - requests: Supabase/Worker calls and private-cache downloads (expected 0).
// Best of 20 runs after one warm-up. Nothing here is a device number.
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';
import 'package:broker_wallet/src/services/private_media_images.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'ffffffff-ffff-4fff-8fff-${(++_n).toString().padLeft(12, '0')}';

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

  test('seed and read-only lookup cost (Windows test VM)', () async {
    final documents = Directory.systemTemp.createTempSync('m23m_docs_');
    final support = Directory.systemTemp.createTempSync('m23m_support_');
    final temp = Directory.systemTemp.createTempSync('m23m_temp_');
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
    final transport = _Transport();
    final cache = PrivateMediaCache(
        currentScope: () =>
            const PrivateMediaScope(account: _a, session: 'session-1'),
        transport: transport);
    PrivateMediaImages.cache = () => cache;
    var requests = 0;
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((_) async {
        requests++;
        throw const SocketException('offline');
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    await client.auth.setInitialSession(jsonEncode({
      'access_token': '${part({'alg': 'HS256'})}.'
          '${part({'sub': _a, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.s',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'r',
      'user': {
        'id': _a,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));
    final core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: R2OfferMediaUploadService(
          supabaseClient: client,
          httpClient: MockClient((_) async {
            requests++;
            throw const SocketException('offline');
          })),
      ownerMedia: R2OfferMediaUploadService(
          supabaseClient: client,
          parent: MediaParent.owner,
          httpClient: MockClient((_) async {
            requests++;
            throw const SocketException('offline');
          })),
    );

    final lines = <String>[];
    for (final count in [0, 1, 10]) {
      // Mapped bytes, for the first-frame seed.
      final mappedRecord = _id();
      final mappedIds = [for (var i = 0; i < count; i++) _id()];
      for (final m in mappedIds) {
        final f = File('${temp.path}${Platform.pathSeparator}$m.png')
          ..writeAsBytesSync(_png);
        await OfflineMediaService.instance.mapMediaIdToLocalFile(
            offerMediaCacheKey(ownerId: _a, mediaObjectId: m)!, f.path);
      }
      // Private-cache-only bytes, for the lookup.
      final privateRecord = _id();
      final privateIds = [for (var i = 0; i < count; i++) _id()];
      for (final m in privateIds) {
        await cache.get(offerMediaCacheKey(ownerId: _a, mediaObjectId: m)!,
            signedUrl: () async => 'https://r2.example/x.png');
      }
      final downloadsBefore = transport.downloads;
      final requestsBefore = requests;

      core.listedRecordMedia(mappedRecord, ownerId: _a, ids: mappedIds);
      var seedBest = 1 << 30;
      var seedItems = 0;
      for (var run = 0; run < 20; run++) {
        final clock = Stopwatch()..start();
        seedItems = core
            .listedRecordMedia(mappedRecord, ownerId: _a, ids: mappedIds)
            .length;
        clock.stop();
        if (clock.elapsedMicroseconds < seedBest) {
          seedBest = clock.elapsedMicroseconds;
        }
      }

      await core.discoverHeldRecordMedia(privateRecord,
          ownerId: _a, ids: privateIds);
      var lookupBest = 1 << 30;
      var lookupItems = 0;
      for (var run = 0; run < 20; run++) {
        final clock = Stopwatch()..start();
        lookupItems = (await core.discoverHeldRecordMedia(privateRecord,
                ownerId: _a, ids: privateIds))
            .length;
        clock.stop();
        if (clock.elapsedMicroseconds < lookupBest) {
          lookupBest = clock.elapsedMicroseconds;
        }
      }
      expect(seedItems, count);
      expect(lookupItems, count);
      lines.add('ids=$count: seed=${seedBest}us (items=$seedItems) '
          'lookup=${(lookupBest / 1000).toStringAsFixed(2)}ms '
          '(items=$lookupItems) '
          'downloads=${transport.downloads - downloadsBefore} '
          'requests=${requests - requestsBefore}');
    }
    // ignore: avoid_print
    print(lines.join('\n'));

    await cache.dispose();
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    await Hive.close();
    for (final dir in [documents, support, temp]) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
