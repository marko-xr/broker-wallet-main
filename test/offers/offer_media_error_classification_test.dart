// Option C (tracker §7AZ, D-FOMF-2/3/4): which Worker answers may remove an
// Offer's or an Owner record's media from this device.
//
// Only two answers prove anything about the media: a well-formed 200 (the
// complete current set, even an empty one) and a 404 carrying the route's own
// not-found code (`offer_not_found` on /offer-media, `owner_not_found` on
// /owner-media), which the Worker sends only after its ownership query ran
// for the current session and found no row. Everything else removes nothing:
//  - 401 and any 403 (a `session_superseded` included) are about the session,
//    never the record: `unauthenticated`;
//  - a 404 without the route's code, a 400 or any other 4xx proves nothing:
//    `inconclusive` (and is not permission to show held media);
//  - a JSON 200 without a media list, or with any invalid or repeated entry,
//    is not the complete set: `inconclusive`, never a partial reconcile;
//  - timeouts, no connection, 5xx and a body that is not JSON: `transient`.
//
// Real Hive, files and private image cache; the Worker, Supabase and the
// private cache's network are test-controlled and count every request.
// Every wait is a Completer the test opens.
import 'dart:async';
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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _s1 = 'session-1';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

var _n = 0;
String _id() => 'cccccccc-cccc-4ccc-8ccc-${(++_n).toString().padLeft(12, '0')}';

String _key(String account, String media) =>
    offerMediaCacheKey(ownerId: account, mediaObjectId: media)!;

class _Response implements FileServiceResponse {
  _Response(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  String get fileExtension => '.png';
  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int? get contentLength => bytes.length;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 7));
  @override
  String? get eTag => null;
}

class _Transport extends FileService {
  final List<String> urls = [];
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    urls.add(url);
    return _Response(_png);
  }
}

/// How the Worker answers one request.
typedef _Answer = Future<http.Response> Function(http.Request request);

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, Object?> _item(String id, {String? url, String type = 'image'}) => {
      'mediaObjectId': id,
      'url': url ?? 'https://r2.example/$id.png?X-Amz-Signature=sig',
      'mediaType': type,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory support;
  late Directory temp;
  late _Transport transport;
  late PrivateMediaCache cache;
  PrivateMediaScope? scope;
  final supabaseCalls = <http.BaseRequest>[];
  final workerCalls = <http.Request>[];
  final privateRemoved = <String>[];
  late _Answer answer;
  late sb.SupabaseClient client;
  late SupabaseCoreEntitiesService core;

  String jwt(String uid) {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
  }

  Future<void> signIn(String uid) => client.auth.setInitialSession(jsonEncode({
        'access_token': jwt(uid),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'refresh',
        'user': {
          'id': uid,
          'aud': 'authenticated',
          'email': 'optionc@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));

  File file(String name) => File('${temp.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(_png);

  Future<void> mapped(String account, String media) async {
    final f = file('m-$account-$media.png');
    await OfflineMediaService.instance
        .mapMediaIdToLocalFile(_key(account, media), f.path);
  }

  Future<void> privateOnly(String media) async {
    final f = await cache.get(_key(_a, media),
        signedUrl: () async => 'https://r2.example/x.png?X-Amz-Signature=s');
    expect(f, isNotNull);
  }

  Future<void> catalogue(String record, List<String> ids) =>
      OfflineMediaService.instance.writeOfferMediaCatalog(
          ownerId: _a, offerId: record, mediaObjectIds: ids);

  List<String> catalogued(String record) => OfflineMediaService.instance
      .readOfferMediaCatalog(ownerId: _a, offerId: record);

  bool mappedNow(String account, String media) =>
      OfflineMediaService.instance
          .getLocalFilePathForMediaId(_key(account, media)) !=
      null;

  Future<bool> privateNow(String media) async =>
      await cache.cached(_key(_a, media)) != null;

  /// A bounded wait for work the app deliberately does not await (the
  /// catalogue reconcile after a valid answer); fails rather than hangs.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 5000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(done(), isTrue, reason: 'the removal did not finish');
  }

  setUpAll(() async {
    documents = Directory.systemTemp.createTempSync('optc_docs_');
    Hive.init(documents.path);
    OfflineMediaService.resolveDocumentsDirectory = () async => documents;
    OfflineMediaService.removeCachedBytes = (_) async {};
    await OfflineMediaService.instance.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      documents.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    OfflineMediaService.debugForgetDeletedAccounts();
    support = Directory.systemTemp.createTempSync('optc_support_');
    temp = Directory.systemTemp.createTempSync('optc_temp_');
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
    scope = const PrivateMediaScope(account: _a, session: _s1);
    cache = PrivateMediaCache(currentScope: () => scope, transport: transport);
    PrivateMediaImages.cache = () => cache;
    privateRemoved.clear();
    OfflineMediaService.removePrivateBytes = (key) async {
      await cache.forget(key);
      privateRemoved.add(key); // recorded once the bytes are gone
    };
    supabaseCalls.clear();
    workerCalls.clear();
    answer = (_) async => _json(200, {'media': <Object>[]});
    client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: MockClient((request) async {
        supabaseCalls.add(request);
        throw const SocketException('offline');
      }),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await signIn(_a);
    R2OfferMediaUploadService worker(MediaParent parent) =>
        R2OfferMediaUploadService(
          supabaseClient: client,
          parent: parent,
          httpClient: MockClient((request) {
            workerCalls.add(request);
            return answer(request);
          }),
        );
    core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: worker(MediaParent.offer),
      ownerMedia: worker(MediaParent.owner),
    );
  });

  tearDown(() async {
    OfflineMediaService.removePrivateBytes =
        (key) => PrivateMediaCache.instance.forget(key);
    await cache.dispose().timeout(const Duration(seconds: 2), onTimeout: () {});
    PrivateMediaImages.cache = () => PrivateMediaCache.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    for (final dir in [support, temp]) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  /// What a resolution ended as: `success` or the failure kind's name.
  Future<String> outcome(MediaParent parent, String record) async {
    try {
      final resolution = parent == MediaParent.offer
          ? await core.resolveOfferMedia(offerId: record, ownerId: _a)
          : await core.resolveOwnerMedia(ownerRecordId: record, ownerId: _a);
      expect(resolution.items, isNotNull);
      return 'success';
    } on OfferMediaException catch (error) {
      return error.kind.name;
    }
  }

  const ownCode = {
    MediaParent.offer: 'offer_not_found',
    MediaParent.owner: 'owner_not_found',
  };
  const otherCode = {
    MediaParent.offer: 'owner_not_found',
    MediaParent.owner: 'offer_not_found',
  };

  for (final parent in MediaParent.values) {
    group('${parent.name} route', () {
      /// A record whose two items the device holds: one through a mapping,
      /// one only in the private cache; the catalogue lists both.
      Future<(String, String, String)> held() async {
        final record = _id();
        final m = _id(), p = _id();
        await mapped(_a, m);
        await privateOnly(p);
        await catalogue(record, [m, p]);
        transport.urls.clear();
        return (record, m, p);
      }

      Future<void> expectKept(String record, String m, String p) async {
        await pumpEventQueue();
        expect(catalogued(record), [m, p], reason: 'catalogue kept');
        expect(mappedNow(_a, m), isTrue, reason: 'mapping kept');
        expect(await privateNow(p), isTrue, reason: 'private bytes kept');
        expect(privateRemoved, isEmpty);
        expect(transport.urls, isEmpty, reason: 'nothing downloaded');
        expect(workerCalls, hasLength(1), reason: 'one request, no retry');
      }

      final keeps = <String, (String, _Answer)>{
        '401': ('unauthenticated', (_) async => _json(401, {'error': 'x'})),
        '403 session_superseded': (
          'unauthenticated',
          (_) async => _json(403, {'error': 'x', 'code': 'session_superseded'}),
        ),
        '403 without a code': (
          'unauthenticated',
          (_) async => _json(403, {'error': 'Forbidden'}),
        ),
        '404 without a code (unknown route)': (
          'inconclusive',
          (_) async => _json(404, {'error': 'Not found'}),
        ),
        '404 with the other route\'s code': (
          'inconclusive',
          (_) async => _json(404, {'error': 'x', 'code': otherCode[parent]}),
        ),
        '404 with an unknown code': (
          'inconclusive',
          (_) async => _json(404, {'error': 'x', 'code': 'media_not_found'}),
        ),
        '400 invalid_request': (
          'inconclusive',
          (_) async => _json(400, {'error': 'x', 'code': 'invalid_request'}),
        ),
        '500': ('transient', (_) async => _json(500, {'error': 'x'})),
        '502': ('transient', (_) async => _json(502, {'error': 'x'})),
        '503 session_check_unavailable': (
          'transient',
          (_) async =>
              _json(503, {'error': 'x', 'code': 'session_check_unavailable'}),
        ),
        'a timeout': ('transient', (_) async => throw TimeoutException('x')),
        'no connection': (
          'transient',
          (_) async => throw const SocketException('offline'),
        ),
        'a 200 that is not JSON': (
          'transient',
          (_) async => http.Response('<html>portal</html>', 200),
        ),
        'a 200 with no media list': (
          'inconclusive',
          (_) async => _json(200, {'expiresInSeconds': 900}),
        ),
        'a 200 with a null media list': (
          'inconclusive',
          (_) async => _json(200, {'media': null}),
        ),
        'a 200 whose media is not a list': (
          'inconclusive',
          (_) async => _json(200, {
                'media': {'a': 1}
              }),
        ),
        'a 200 with one entry that is not an object': (
          'inconclusive',
          (_) async => _json(200, {
                'media': [_item(_id()), 'oops'],
              }),
        ),
        'a 200 with an entry missing its url': (
          'inconclusive',
          (_) async => _json(200, {
                'media': [
                  {'mediaObjectId': _id(), 'mediaType': 'image'},
                ],
              }),
        ),
        'a 200 with an entry with an empty url': (
          'inconclusive',
          (_) async => _json(200, {
                'media': [_item(_id(), url: '')],
              }),
        ),
        'a 200 with an entry missing its id': (
          'inconclusive',
          (_) async => _json(200, {
                'media': [
                  {'url': 'https://r2.example/x.png', 'mediaType': 'image'},
                ],
              }),
        ),
        'a 200 with a repeated id': (
          'inconclusive',
          (_) async {
            final dup = _id();
            return _json(200, {
              'media': [_item(dup), _item(dup)],
            });
          },
        ),
      };
      for (final MapEntry(key: name, value: (kind, reply)) in keeps.entries) {
        test('$name: $kind, and nothing held is removed', () async {
          final (record, m, p) = await held();
          answer = reply;
          expect(await outcome(parent, record), kind);
          await expectKept(record, m, p);
        });
      }

      test('a 200 with a valid entry beside an invalid one removes nothing',
          () async {
        final (record, m, p) = await held();
        answer = (_) async => _json(200, {
              'media': [_item(m), 'oops'],
            });
        expect(await outcome(parent, record), 'inconclusive');
        await expectKept(record, m, p);
      });

      test('the route\'s own not-found code removes this record\'s media',
          () async {
        final (record, m, p) = await held();
        await mapped(_b, m); // another account's copy of the same id
        answer =
            (_) async => _json(404, {'error': 'x', 'code': ownCode[parent]});
        expect(await outcome(parent, record), 'accessDenied');
        expect(catalogued(record), isEmpty);
        expect(mappedNow(_a, m), isFalse);
        expect(await privateNow(p), isFalse);
        expect(privateRemoved, containsAll([_key(_a, m), _key(_a, p)]));
        expect(mappedNow(_b, m), isTrue, reason: 'another account untouched');
        expect(transport.urls, isEmpty);
      });

      test('a valid empty list removes what the device held', () async {
        final (record, m, p) = await held();
        answer = (_) async => _json(200, {'media': <Object>[]});
        expect(await outcome(parent, record), 'success');
        // The app does not wait for the removal; the test waits for its end.
        await until(() => privateRemoved.contains(_key(_a, p)));
        expect(catalogued(record), isEmpty);
        expect(mappedNow(_a, m), isFalse);
        expect(await privateNow(p), isFalse);
      });

      test('a valid list removes exactly what it no longer lists', () async {
        final (record, m, p) = await held();
        answer = (_) async => _json(200, {
              'media': [_item(m)],
            });
        expect(await outcome(parent, record), 'success');
        await until(() => privateRemoved.contains(_key(_a, p)));
        expect(catalogued(record), [m]);
        expect(mappedNow(_a, m), isTrue);
        expect(await privateNow(p), isFalse);
        expect(privateRemoved, [_key(_a, p)]);
      });

      test('a valid list with no stated lifetime is still authoritative',
          () async {
        final (record, m, p) = await held();
        answer = (_) async => http.Response(
            jsonEncode({
              'media': [_item(m)],
            }),
            200);
        expect(await outcome(parent, record), 'success');
        // Wait for the whole reconcile, not only its first step (the
        // catalogue), so no removal is still running when the test ends.
        await until(() => privateRemoved.contains(_key(_a, p)));
        expect(catalogued(record), [m]);
        expect(await privateNow(p), isFalse);
      });

      test(
          'an inconclusive answer, then a valid empty list: gone everywhere, '
          'the previous copy included', () async {
        final record = _id();
        final m = _id(), p = _id();
        final original = file('orig-$m.png');
        await OfflineMediaService.instance
            .mapMediaIdToLocalFile(_key(_a, m), original.path);
        final copy = file('copy-$m.png');
        expect(
            await OfflineMediaService.instance.replaceMediaIdMapping(
                _key(_a, m),
                expected: original.path,
                replacement: copy.path,
                previous: original.path),
            isTrue);
        await privateOnly(p);
        await catalogue(record, [m, p]);
        answer = (_) async => _json(404, {'error': 'Not found'});
        expect(await outcome(parent, record), 'inconclusive');
        expect(catalogued(record), [m, p]);
        answer = (_) async => _json(200, {'media': <Object>[]});
        expect(await outcome(parent, record), 'success');
        await until(() => privateRemoved.contains(_key(_a, p)));
        copy.deleteSync();
        expect(
            OfflineMediaService.instance.usableLocalPathForMediaId(_key(_a, m)),
            isNull,
            reason: 'not even the previous copy is left to show');
        expect(await privateNow(p), isFalse);
        expect(
            await core
                .discoverHeldRecordMedia(record, ownerId: _a, ids: [m, p]),
            isEmpty,
            reason:
                'the emptied catalogue keeps saved ids from bringing it back');
      });
    });
  }

  group('accounts and sessions during a request', () {
    test(
        'a superseded session keeps the bytes but cannot read or fetch them; '
        'the next authorized session of the account can', () async {
      final record = _id();
      final p = _id();
      await privateOnly(p);
      await catalogue(record, [p]);
      transport.urls.clear();
      answer =
          (_) async => _json(403, {'error': 'x', 'code': 'session_superseded'});
      expect(await outcome(MediaParent.offer, record), 'unauthenticated');
      scope = null; // the Single Active Device gate has de-authorized it
      expect(PrivateMediaImages.canRead(_key(_a, p)), isFalse);
      expect(await PrivateMediaImages.heldInPrivateCache(_key(_a, p)), isNull);
      expect(
          await PrivateMediaImages.load(_key(_a, p),
              signedUrl: 'https://r2.example/p.png?X-Amz-Signature=s'),
          isNull);
      expect(transport.urls, isEmpty, reason: 'no fetch for that session');
      scope = const PrivateMediaScope(account: _a, session: 'session-2');
      expect(
          await PrivateMediaImages.heldInPrivateCache(_key(_a, p)), isNotNull,
          reason: 'kept, so the account need not download it again');
    });

    test('another account signs in during the request: nothing is removed',
        () async {
      final record = _id();
      final m = _id();
      await mapped(_a, m);
      await catalogue(record, [m]);
      final gate = Completer<void>();
      answer = (_) async {
        await gate.future;
        return _json(404, {'error': 'x', 'code': 'offer_not_found'});
      };
      final pending = outcome(MediaParent.offer, record);
      await pumpEventQueue();
      await signIn(_b);
      gate.complete();
      expect(await pending, 'transient');
      expect(catalogued(record), [m]);
      expect(mappedNow(_a, m), isTrue);
    });

    test('signed out during a valid answer: nothing is reconciled', () async {
      final record = _id();
      final m = _id();
      await mapped(_a, m);
      await catalogue(record, [m]);
      final gate = Completer<void>();
      answer = (_) async {
        await gate.future;
        return _json(200, {'media': <Object>[]});
      };
      final pending = outcome(MediaParent.offer, record)
          .catchError((Object _) => 'refused', test: (e) => e is StateError);
      await pumpEventQueue();
      await client.auth.signOut().catchError((Object _) {});
      gate.complete();
      await pending.catchError((Object _) => 'refused');
      await pumpEventQueue();
      expect(catalogued(record), [m]);
      expect(mappedNow(_a, m), isTrue);
    });

    test('after Delete Account cleanup a late answer brings nothing back',
        () async {
      final record = _id();
      final m = _id(), p = _id();
      await mapped(_a, m);
      await privateOnly(p);
      await catalogue(record, [m, p]);
      transport.urls.clear(); // the private copy above was its only fetch
      final gate = Completer<void>();
      answer = (_) async {
        await gate.future;
        return _json(200, {
          'media': [_item(m), _item(p)],
        });
      };
      final pending = outcome(MediaParent.offer, record);
      await pumpEventQueue();
      await OfflineMediaService.instance.forgetOfferMedia(ownerId: _a);
      gate.complete();
      await pending;
      // The late valid answer schedules its reconcile, which the deleted
      // account's guard (DA-MAP-1) turns into a no-op with no file work: the
      // catalogue write is refused and nothing is left to drop.
      await pumpEventQueue();
      expect(catalogued(record), isEmpty, reason: 'not even the ids come back');
      expect(mappedNow(_a, m), isFalse, reason: 'no mapping is recreated');
      expect(await privateNow(p), isFalse, reason: 'no bytes are recreated');
      expect(transport.urls, isEmpty, reason: 'resolving downloads nothing');
    });
  });

  // A removal the app schedules without waiting cannot be seen reliably by a
  // test that checks the device right after the answer. So the rows above
  // that expect nothing removed rely on this, checked deterministically: a
  // failure's removal is always finished before the answer is given, and the
  // only removal left running after an answer is the reconcile of a valid
  // list, scheduled only once the account was checked again.
  group('what may remove media, by construction', () {
    String core() =>
        File('lib/src/services/supabase_core_entities_service.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');

    test('a revocation removes before it answers; nothing else is scheduled',
        () {
      final source = core();
      int count(String text) => text.allMatches(source).length;
      expect(count('Future<void> _forgetOfferMediaLocally('), 1);
      expect(count('_forgetOfferMediaLocally('),
          1 + count('await _forgetOfferMediaLocally('),
          reason: 'every removal on a failure is awaited');
      expect(count('await _forgetOfferMediaLocally('), 1,
          reason: 'only the trusted not-found answer removes');
      expect(count('unawaited(_forgetOfferMediaLocally'), 0);
      expect(count('unawaited(_rememberOfferMediaCatalog('), 1,
          reason: 'one reconcile, for a valid list only');
      expect(count('reconcileOfferMediaCatalog('), 2,
          reason: 'only inside those two functions');
      expect(count('forgetOfferMediaItems('), 0,
          reason: 'no direct removal from this service');
    });

    test('the one scheduled reconcile follows the account check', () {
      final source = core();
      final check = source.indexOf(
          "'The authenticated account changed during media resolution.'");
      final reconcile = source.indexOf('unawaited(_rememberOfferMediaCatalog(');
      expect(check, greaterThan(0));
      expect(reconcile, greaterThan(check));
      final classify = source.indexOf('throw await _classifyMediaFailure(');
      final incomplete = source.indexOf('on R2OfferMediaContractException {');
      expect(classify, greaterThan(0));
      expect(incomplete, greaterThan(classify));
      expect(reconcile, greaterThan(incomplete),
          reason: 'every failure has thrown before the reconcile');
    });
  });

  group('the Worker client itself', () {
    late List<http.Response> replies;
    R2OfferMediaUploadService service(MediaParent parent) =>
        R2OfferMediaUploadService(
          supabaseClient: client,
          parent: parent,
          httpClient: MockClient((_) async => replies.removeAt(0)),
        );

    test('a 404 proves the record gone only with its own route\'s code', () {
      final offers = service(MediaParent.offer);
      final owners = service(MediaParent.owner);
      R2OfferMediaHttpException e(int status, [String? code]) =>
          R2OfferMediaHttpException(status, code: code);
      expect(offers.provesRecordGone(e(404, 'offer_not_found')), isTrue);
      expect(owners.provesRecordGone(e(404, 'owner_not_found')), isTrue);
      expect(offers.provesRecordGone(e(404, 'owner_not_found')), isFalse);
      expect(owners.provesRecordGone(e(404, 'offer_not_found')), isFalse);
      for (final status in [400, 401, 403, 404, 409, 500, 502, 503]) {
        expect(offers.provesRecordGone(e(status)), isFalse, reason: '$status');
      }
      expect(offers.provesRecordGone(e(403, 'offer_not_found')), isFalse);
      expect(offers.provesRecordGone(e(404, 'session_superseded')), isFalse);
    });

    test('401 and every 403 are session refusals, nothing else is', () {
      for (final status in [401, 403]) {
        expect(R2OfferMediaHttpException(status).isSessionRefused, isTrue);
      }
      for (final status in [400, 404, 409, 500, 502, 503]) {
        expect(R2OfferMediaHttpException(status).isSessionRefused, isFalse,
            reason: '$status');
      }
    });

    test('a list that is not the complete, well-formed set is refused whole',
        () async {
      final bad = <Object>[
        {'expiresInSeconds': 900},
        {'media': null},
        {'media': 'x'},
        {
          'media': [_item(_id()), 'oops'],
        },
        {
          'media': [
            {'mediaObjectId': _id()},
          ],
        },
        {
          'media': [
            {'url': 'https://r2.example/x.png'},
          ],
        },
        {
          'media': [
            {'mediaObjectId': '', 'url': 'https://r2.example/x.png'},
          ],
        },
        {
          'media': [
            {'mediaObjectId': 7, 'url': 'https://r2.example/x.png'},
          ],
        },
      ];
      for (final body in bad) {
        replies = [http.Response(jsonEncode(body), 200)];
        await expectLater(service(MediaParent.offer).getOfferMedia(_id()),
            throwsA(isA<R2OfferMediaContractException>()),
            reason: jsonEncode(body));
      }
      replies = [http.Response('<html>', 200)];
      await expectLater(service(MediaParent.offer).getOfferMedia(_id()),
          throwsA(isNot(isA<R2OfferMediaContractException>())),
          reason: 'an unreadable body stays a temporary failure');
    });

    test('a well-formed list is returned whole, in order', () async {
      final x = _id(), y = _id();
      replies = [
        http.Response(
            jsonEncode({
              'media': [_item(x), _item(y, type: 'video')],
            }),
            200),
      ];
      final items = await service(MediaParent.owner).getOfferMedia(_id());
      expect([for (final i in items) i.mediaObjectId], [x, y]);
      expect(items.last.mediaType, 'video');
    });
  });
}
