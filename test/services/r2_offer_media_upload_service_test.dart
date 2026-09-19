import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _offerId = '11111111-1111-4111-8111-111111111111';

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

/// Records every request `R2OfferMediaUploadService` sends and answers the
/// Offer Media Worker's three routes with the minimum realistic response
/// each needs, exactly like the deployed Worker would for a valid request.
class _WorkerBackend {
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (request.method == 'PUT') {
      return http.Response('', 200);
    }
    if (request.url.path.endsWith('/offer-media/authorize')) {
      return http.Response(
        jsonEncode({
          'presignedUrl': 'https://r2.example.test/signed-put',
          'mediaObjectId': 'mock-media-object-id',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/offer-media/confirm')) {
      return http.Response(
        jsonEncode(
            {'offerId': _offerId, 'mediaObjectId': 'mock-media-object-id'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });

  http.Request get authorizeRequest =>
      requests.firstWhere((r) => r.url.path.endsWith('/offer-media/authorize'));

  http.Request get putRequest =>
      requests.firstWhere((r) => r.method == 'PUT');
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('offer_media_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

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
        expect(e.message, 'Unsupported offer image type.');
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
        'a .heic file is still classified as image/heic exactly as before, '
        'regardless of its actual byte content — proves no regression',
        () async {
      // The byte-signature detector does not recognize HEIC (out of scope
      // for this checkpoint); this file's bytes do not matter here, since
      // the pre-existing behavior never inspected HEIC bytes either.
      final arbitraryBytes = List<int>.filled(40, 0x00);
      final file = await _writeTempFile('photo.heic', arbitraryBytes);

      await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      final authorizeBody =
          jsonDecode(backend.authorizeRequest.body) as Map<String, dynamic>;
      expect(authorizeBody['contentType'], 'image/heic');
    });

    test('a genuinely valid JPEG upload still succeeds end to end', () async {
      final jpegBytes = img.encodeJpg(_tinyImage());
      final file = await _writeTempFile('camera.jpg', jpegBytes);

      final result =
          await service.uploadOfferMediaFile(offerId: _offerId, file: file);

      expect(result.mediaObjectId, 'mock-media-object-id');
      expect(backend.requests.map((r) => r.url.path).toList(), [
        '/offer-media/authorize',
        '/signed-put',
        '/offer-media/confirm',
      ]);
    });
  });
}
