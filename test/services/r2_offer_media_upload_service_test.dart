import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _offerId = '11111111-1111-4111-8111-111111111111';
const _mediaId = '22222222-2222-4222-8222-222222222222';

final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

img.Image _tinyImage() => img.Image(width: 2, height: 2);

String _fakeJwt(String uid) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _sessionJson(String uid) => {
      'access_token': _fakeJwt(uid),
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
        'role': 'authenticated',
        'email': 'offer-media-test@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    };

/// A real [sb.SupabaseClient] carrying a real session, set locally via
/// `setInitialSession` (no network call) — the same seam already used by
/// `test/auth/phone_verification_test.dart` — so
/// `R2OfferMediaUploadService._currentAuth()` sees a genuine access token.
Future<sb.SupabaseClient> _signedInClient() async {
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((_) async => http.Response('{}', 200)),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode(_sessionJson(_uid)));
  return client;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Records every request `R2OfferMediaUploadService` sends and answers the
/// Offer Media Worker's routes the way the Worker does for a valid request:
/// authorize echoes the app-generated `mediaObjectId` it was given.
class _WorkerBackend {
  _WorkerBackend({this.authorize, this.confirm, this.remove, this.list});

  final http.Response Function(Map<String, dynamic> body)? authorize;
  final http.Response Function(Map<String, dynamic> body)? confirm;
  final http.Response Function(Map<String, dynamic> body)? remove;
  final http.Response Function()? list;

  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (request.method == 'PUT') {
      return http.Response('', 200);
    }
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/offer-media')) {
      return list?.call() ?? _json({'media': []});
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/offer-media/authorize')) {
      return authorize?.call(body) ??
          _json({
            'status': 'pending',
            'presignedUrl': 'https://r2.example.test/signed-put',
            'mediaObjectId': body['mediaObjectId'],
            'mediaType': 'image',
            'expiresInSeconds': 300,
          });
    }
    if (path.endsWith('/offer-media/confirm')) {
      return confirm?.call(body) ??
          _json({
            'offerId': body['offerId'],
            'mediaObjectId': body['mediaObjectId'],
            'ordinal': 0,
          });
    }
    if (path.endsWith('/offer-media/remove')) {
      return remove?.call(body) ??
          _json({'offerId': body['offerId'], 'removed': true});
    }
    return http.Response('{}', 404);
  });

  http.Request get authorizeRequest =>
      requests.firstWhere((r) => r.url.path.endsWith('/offer-media/authorize'));

  http.Request get confirmRequest =>
      requests.firstWhere((r) => r.url.path.endsWith('/offer-media/confirm'));

  http.Request get putRequest => requests.firstWhere((r) => r.method == 'PUT');

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('offer_media_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

/// The first bytes of a real HEIC photo: an `ftyp` box with major brand
/// `heic` and compatible brands `mif1`, `heic`.
const List<int> _heicHeader = [
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // ....ftyp
  0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00, // heic....
  0x6d, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63, // mif1heic
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('R2OfferMediaUploadService — byte-signature content-type resolution',
      () {
    late _WorkerBackend backend;
    late R2OfferMediaUploadService service;

    setUp(() async {
      backend = _WorkerBackend();
      service = R2OfferMediaUploadService(
        httpClient: backend.client,
        supabaseClient: await _signedInClient(),
      );
    });

    test(
        'a file named photo.jpg containing real PNG bytes is classified as '
        'PNG', () async {
      final pngBytes = img.encodePng(_tinyImage());
      final file = await _writeTempFile('photo.jpg', pngBytes);

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      final authorizeBody =
          jsonDecode(backend.authorizeRequest.body) as Map<String, dynamic>;
      expect(authorizeBody['contentType'], 'image/png');
    });

    test(
        'a file named photo.webp containing real JPEG bytes is classified '
        'as JPEG', () async {
      final jpegBytes = img.encodeJpg(_tinyImage());
      final file = await _writeTempFile('photo.webp', jpegBytes);

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      final authorizeBody =
          jsonDecode(backend.authorizeRequest.body) as Map<String, dynamic>;
      expect(authorizeBody['contentType'], 'image/jpeg');
    });

    test('unrecognized bytes are rejected before any network request is made',
        () async {
      final garbage = List<int>.filled(30, 0x11);
      final file = await _writeTempFile('mystery.dat', garbage);

      await expectLater(
        service.uploadOfferMediaFile(offerId: _offerId, file: file),
        throwsA(isA<R2UploadException>()),
      );
      expect(backend.requests, isEmpty);
    });

    test('the rejection message names no file path or byte content',
        () async {
      final garbage = List<int>.filled(30, 0x11);
      final file = await _writeTempFile('mystery.dat', garbage);
      final privatePath = file.path;

      try {
        await service.uploadOfferMediaFile(offerId: _offerId, file: file);
        fail('expected an R2UploadException');
      } on R2UploadException catch (e) {
        expect(e, isA<OfferMediaRejectedException>());
        expect((e as OfferMediaRejectedException).rejection,
            OfferMediaRejection.unsupportedType);
        expect(e.message, 'Offer media was refused.');
        expect(e.message, isNot(contains(privatePath)));
        expect(e.message, isNot(contains('0x11')));
      }
    });

    test(
        'the detected MIME is used identically for authorization and the '
        'signed PUT', () async {
      final webpBytes = img.encodeWebP(_tinyImage());
      final file = await _writeTempFile('gallery.webp', webpBytes);

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      final authorizeBody =
          jsonDecode(backend.authorizeRequest.body) as Map<String, dynamic>;
      expect(authorizeBody['contentType'], 'image/webp');
      expect(backend.putRequest.headers['Content-Type'], 'image/webp');
    });

    test(
        'the original byte length is preserved through authorization and '
        'the PUT body', () async {
      final pngBytes = img.encodePng(_tinyImage());
      final file = await _writeTempFile('photo.png', pngBytes);

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      final authorizeBody =
          jsonDecode(backend.authorizeRequest.body) as Map<String, dynamic>;
      expect(authorizeBody['contentLength'], pngBytes.length);
      expect(backend.putRequest.bodyBytes.length, pngBytes.length);
    });

    test('the existing 10 MiB size limit is unchanged', () {
      expect(R2OfferMediaUploadService.maxImageBytes, 10 * 1024 * 1024);
    });

    test(
        'a HEIC photo is never uploaded as HEIC: it is refused before any '
        'request (the app converts HEIC to JPEG before it gets here)',
        () async {
      final heic = await _writeTempFile('photo.heic', _heicHeader);
      final unnamedHeic = await _writeTempFile('photo.jpg', _heicHeader);

      for (final file in [heic, unnamedHeic]) {
        await expectLater(
          service.uploadOfferMediaFile(offerId: _offerId, file: file),
          throwsA(isA<OfferMediaRejectedException>().having(
            (e) => e.rejection,
            'rejection',
            OfferMediaRejection.unsupportedType,
          )),
        );
      }
      expect(backend.requests, isEmpty);
      expect(R2OfferMediaUploadService.supportedContentTypes,
          isNot(contains('image/heic')));
    });

    test('a .heic name with real JPEG bytes is uploaded as the JPEG it is',
        () async {
      final file =
          await _writeTempFile('photo.heic', img.encodeJpg(_tinyImage()));

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      expect(backend.bodyOf(backend.authorizeRequest)['contentType'],
          'image/jpeg');
    });

    test('a genuinely valid JPEG upload still succeeds end to end', () async {
      final jpegBytes = img.encodeJpg(_tinyImage());
      final file = await _writeTempFile('camera.jpg', jpegBytes);

      final result =
          await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      expect(result.mediaObjectId, matches(_uuidV4));
      expect(result.kind, OfferMediaKind.image);
      expect(backend.requests.map((r) => r.url.path).toList(), [
        '/offer-media/authorize',
        '/signed-put',
        '/offer-media/confirm',
      ]);
    });
  });

  group('R2OfferMediaUploadService — one identity, idempotent steps', () {
    Future<R2OfferMediaUploadService> serviceFor(
            _WorkerBackend backend) async =>
        R2OfferMediaUploadService(
          httpClient: backend.client,
          supabaseClient: await _signedInClient(),
        );

    test(
        'the app-generated id is the one sent to authorize and to confirm, '
        'and the one returned', () async {
      final backend = _WorkerBackend();
      final service = await serviceFor(backend);
      final file =
          await _writeTempFile('camera.jpg', img.encodeJpg(_tinyImage()));

      final result = await service.uploadOfferMediaFile(
        offerId: _offerId,
        file: file,
        mediaObjectId: _mediaId,
      );

      expect(result.mediaObjectId, _mediaId);
      expect(
          backend.bodyOf(backend.authorizeRequest)['mediaObjectId'], _mediaId);
      expect(backend.bodyOf(backend.confirmRequest)['mediaObjectId'], _mediaId);
    });

    test(
        'retrying the same id after a lost confirm response sends the same '
        'id again and never a new one', () async {
      var confirms = 0;
      final backend = _WorkerBackend(confirm: (body) {
        confirms += 1;
        // The first confirm "succeeds" but its answer never arrives.
        if (confirms == 1) return http.Response('', 502);
        return _json({
          'offerId': body['offerId'],
          'mediaObjectId': body['mediaObjectId'],
          'ordinal': 0,
          'alreadyConfirmed': true,
        });
      });
      final service = await serviceFor(backend);

      await expectLater(
        service.confirmUpload(offerId: _offerId, mediaObjectId: _mediaId),
        throwsA(isA<R2OfferMediaHttpException>()),
      );
      final second = await service.confirmUpload(
          offerId: _offerId, mediaObjectId: _mediaId);

      expect(second.alreadyConfirmed, isTrue);
      final ids = [
        for (final r in backend.requests) backend.bodyOf(r)['mediaObjectId'],
      ];
      expect(ids, [_mediaId, _mediaId]);
    });

    test('an item already attached is not uploaded or confirmed again',
        () async {
      final backend = _WorkerBackend(
        authorize: (body) => _json({
          'status': 'ready',
          'mediaObjectId': body['mediaObjectId'],
        }),
      );
      final service = await serviceFor(backend);
      final file =
          await _writeTempFile('camera.jpg', img.encodeJpg(_tinyImage()));

      final result = await service.uploadOfferMediaFile(
        offerId: _offerId,
        file: file,
        mediaObjectId: _mediaId,
      );

      expect(result.mediaObjectId, _mediaId);
      expect(backend.requests.map((r) => r.url.path).toList(),
          ['/offer-media/authorize']);
    });

    test(
        'a Worker that answers with an id of its own is refused, so an '
        "item's identity can never change mid-upload", () async {
      final backend = _WorkerBackend(
        authorize: (_) => _json({
          'presignedUrl': 'https://r2.example.test/signed-put',
          'mediaObjectId': 'server-chosen-id',
        }),
      );
      final service = await serviceFor(backend);

      await expectLater(
        service.authorizeUpload(
          offerId: _offerId,
          mediaObjectId: _mediaId,
          contentType: 'image/jpeg',
          contentLength: 10,
        ),
        throwsA(isA<R2UploadException>()),
      );
      expect(backend.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('an uppercase echo of the same id is the same id', () async {
      final backend = _WorkerBackend(
        authorize: (body) => _json({
          'status': 'pending',
          'presignedUrl': 'https://r2.example.test/signed-put',
          'mediaObjectId': (body['mediaObjectId'] as String).toUpperCase(),
        }),
      );
      final service = await serviceFor(backend);

      final authorization = await service.authorizeUpload(
        offerId: _offerId,
        mediaObjectId: _mediaId,
        contentType: 'image/jpeg',
        contentLength: 10,
      );

      expect(authorization.mediaObjectId, _mediaId);
      expect(authorization.isAlreadyReady, isFalse);
    });

    test('permanent refusals map to their reason; retryable answers do not',
        () async {
      final cases = <(int, String, Object)>[
        (422, 'media_type_mismatch', OfferMediaRejection.unsupportedType),
        (422, 'video_too_long', OfferMediaRejection.videoTooLong),
        (409, 'offer_media_limit_reached', OfferMediaRejection.limitReached),
        (409, 'idempotency_mismatch', OfferMediaRejection.rejected),
        (409, 'upload_rejected', OfferMediaRejection.rejected),
        (410, 'media_removed', OfferMediaRejection.rejected),
        (409, 'upload_incomplete', 'http'),
        (409, 'deletion_in_progress', 'http'),
        (502, 'offer_media_limit_reached', 'http'),
      ];
      for (final (status, code, expected) in cases) {
        final backend = _WorkerBackend(
          confirm: (_) =>
              _json({'code': code, 'error': 'provider text'}, status),
        );
        final service = await serviceFor(backend);
        final matcher = expected is OfferMediaRejection
            ? isA<OfferMediaRejectedException>()
                .having((e) => e.rejection, 'rejection', expected)
            : isA<R2OfferMediaHttpException>()
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.code, 'code', code);
        await expectLater(
          service.confirmUpload(offerId: _offerId, mediaObjectId: _mediaId),
          throwsA(matcher),
          reason: '$status $code',
        );
      }
    });

    test("the Worker's own message text is never carried to the app", () async {
      final backend = _WorkerBackend(
        confirm: (_) => _json(
            {'code': 'upload_incomplete', 'error': 'r2 key profiles/x'}, 409),
      );
      final service = await serviceFor(backend);

      try {
        await service.confirmUpload(offerId: _offerId, mediaObjectId: _mediaId);
        fail('expected a failure');
      } on R2OfferMediaHttpException catch (e) {
        expect(e.message, isNot(contains('profiles/')));
        expect(e.toString(), isNot(contains('r2 key')));
      }
    });

    test('remove reports an item that was already removed', () async {
      final backend = _WorkerBackend(
        remove: (body) => _json({
          'offerId': body['offerId'],
          'removed': true,
          'alreadyRemoved': true,
        }),
      );
      final service = await serviceFor(backend);

      final removal =
          await service.removeMedia(offerId: _offerId, mediaObjectId: _mediaId);

      expect(removal.alreadyRemoved, isTrue);
      expect(
          backend.bodyOf(backend.requests.single)['mediaObjectId'], _mediaId);
    });
  });

  group('R2OfferMediaUploadService — reading media', () {
    test(
        'each item carries its kind, length and when its link stops '
        'working, estimated early', () async {
      final backend = _WorkerBackend(
        list: () => _json({
          'offerId': _offerId,
          'expiresInSeconds': 900,
          'media': [
            {
              'mediaObjectId': _mediaId,
              'role': 'gallery',
              'ordinal': 0,
              'mediaType': 'video',
              'durationMs': 42000,
              'url': 'https://r2.example.test/a.mp4?X-Amz-Signature=x',
            },
            {'mediaObjectId': 'missing-url'},
          ],
        }),
      );
      final service = R2OfferMediaUploadService(
        httpClient: backend.client,
        supabaseClient: await _signedInClient(),
      );
      final before = DateTime.now();

      final items = await service.getOfferMedia(_offerId);

      expect(items, hasLength(1));
      final item = items.single;
      expect(item.mediaObjectId, _mediaId);
      expect(item.mediaType, 'video');
      expect(item.durationMs, 42000);
      final expiresAt = item.expiresAt!;
      expect(
        expiresAt.isAfter(before.add(const Duration(seconds: 899))),
        isTrue,
      );
      expect(
        expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 901))),
        isTrue,
      );
    });
  });
}
