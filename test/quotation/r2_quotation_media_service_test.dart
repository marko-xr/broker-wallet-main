// Tests for the Quotation media Worker client: the exact bodies it sends, how
// it reads each answer, how Worker codes map to fixed failure categories, and
// that no credential, signed URL or key ever reaches an error.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _quotationId = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';
const _mediaId = '22222222-2222-4222-8222-222222222222';
const _otherId = '33333333-3333-4333-8333-333333333333';
const _signedPut = 'https://r2.example.test/bucket/key?X-Amz-Signature=secret-put';
const _signedGet = 'https://r2.example.test/bucket/key?X-Amz-Signature=secret-get';

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
        'email': 'quotation-media-test@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    };

Future<sb.SupabaseClient> _signedIn({bool withSession = true}) async {
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((_) async => http.Response('{}', 200)),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  if (withSession) {
    await client.auth.setInitialSession(jsonEncode(_sessionJson(_uid)));
  }
  return client;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Records every request and answers it with [respond].
class _Worker {
  _Worker(this.respond);

  final http.Response Function(http.Request request) respond;
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return respond(request);
  });

  Map<String, dynamic> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;
}

Future<R2QuotationMediaService> _service(_Worker worker,
        {bool withSession = true}) async =>
    R2QuotationMediaService(
      httpClient: worker.client,
      supabaseClient: await _signedIn(withSession: withSession),
    );

Future<File> _tempFile(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('quotation_media_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}file.bin');
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  group('authorize', () {
    test('posts the contract body with a bearer token and a null expected id',
        () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
            'mediaType': 'image',
            'expiresInSeconds': 300,
          }));
      final service = await _service(worker);

      final result = await service.authorize(
        quotationId: _quotationId,
        role: QuotationMediaRole.officeLogo,
        expectedMediaId: null,
        mediaObjectId: _mediaId,
        contentType: 'image/png',
        contentLength: 1234,
        originalFileName: 'logo.png',
      );

      expect(result.isAlreadyReady, isFalse);
      expect(result.mediaObjectId, _mediaId);
      expect(result.presignedUrl, _signedPut);

      final request = worker.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/quotation-media/authorize');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.headers['Content-Type'], contains('application/json'));
      final body = worker.bodyOf(request);
      expect(body, {
        'quotationId': _quotationId,
        'role': 'office_logo',
        'expectedMediaId': null,
        'mediaObjectId': _mediaId,
        'contentType': 'image/png',
        'contentLength': 1234,
        'originalFileName': 'logo.png',
      });
      expect(body.containsKey('expectedMediaId'), isTrue,
          reason: 'the Worker requires the key, with null for an empty slot');
    });

    test('names the PDF role quotation_pdf and passes the expected media id',
        () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
          }));
      final service = await _service(worker);
      await service.authorize(
        quotationId: _quotationId,
        role: QuotationMediaRole.quotationPdf,
        expectedMediaId: _otherId,
        mediaObjectId: _mediaId,
        contentType: 'application/pdf',
        contentLength: 50,
      );

      final body = worker.bodyOf(worker.requests.single);
      expect(body['role'], 'quotation_pdf');
      expect(body['expectedMediaId'], _otherId);
      expect(body.containsKey('originalFileName'), isFalse);
    });

    test('an id that is already bound answers ready (nothing to upload)',
        () async {
      final worker = _Worker((r) =>
          _json({'status': 'ready', 'mediaObjectId': _mediaId}));
      final service = await _service(worker);
      final result = await service.authorize(
        quotationId: _quotationId,
        role: QuotationMediaRole.officeLogo,
        expectedMediaId: _mediaId,
        mediaObjectId: _mediaId,
        contentType: 'image/jpeg',
        contentLength: 1,
      );
      expect(result.isAlreadyReady, isTrue);
      expect(result.presignedUrl, isNull);
    });

    test('an answer for a different media id is not accepted', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _otherId,
          }));
      final service = await _service(worker);
      await expectLater(
        service.authorize(
          quotationId: _quotationId,
          role: QuotationMediaRole.officeLogo,
          expectedMediaId: null,
          mediaObjectId: _mediaId,
          contentType: 'image/jpeg',
          contentLength: 1,
        ),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.invalidResponse)),
      );
    });

    test('a pending answer without a signed URL is not accepted', () async {
      final worker = _Worker((r) =>
          _json({'status': 'pending', 'mediaObjectId': _mediaId}));
      final service = await _service(worker);
      await expectLater(
        service.authorize(
          quotationId: _quotationId,
          role: QuotationMediaRole.officeLogo,
          expectedMediaId: null,
          mediaObjectId: _mediaId,
          contentType: 'image/jpeg',
          contentLength: 1,
        ),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.invalidResponse)),
      );
    });
  });

  group('signed upload', () {
    test('PUTs the exact bytes to the signed URL without the account token',
        () async {
      final worker = _Worker((r) => http.Response('', 200));
      final service = await _service(worker);
      final file = await _tempFile([1, 2, 3, 4, 5]);

      await service.uploadBytes(
        presignedUrl: _signedPut,
        file: file,
        contentType: 'image/png',
      );

      final request = worker.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.toString(), _signedPut);
      expect(request.headers['Content-Type'], 'image/png');
      expect(request.bodyBytes, [1, 2, 3, 4, 5]);
      expect(request.headers.containsKey('Authorization'), isFalse,
          reason: 'the Supabase token must never be sent to storage');
    });

    test('a refused signature is uploadRejected and never exposes the URL',
        () async {
      final worker = _Worker((r) => http.Response('<Error/>', 403));
      final service = await _service(worker);
      final file = await _tempFile([1]);

      Object? caught;
      try {
        await service.uploadBytes(
            presignedUrl: _signedPut, file: file, contentType: 'image/png');
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<QuotationMediaException>());
      final failure = caught! as QuotationMediaException;
      expect(failure.failure, QuotationMediaFailure.uploadRejected);
      expect(failure.statusCode, 403);
      expect(failure.isRetryable, isTrue);
      expect(failure.toString().contains('secret-put'), isFalse);
      expect(failure.toString().contains('r2.example.test'), isFalse);
    });

    test('a dropped connection is interrupted (nothing was confirmed)', () async {
      final service = R2QuotationMediaService(
        httpClient: MockClient((_) async => throw const SocketException('x')),
        supabaseClient: await _signedIn(),
      );
      final file = await _tempFile([1]);
      await expectLater(
        service.uploadBytes(
            presignedUrl: _signedPut, file: file, contentType: 'image/png'),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.interrupted)),
      );
    });
  });

  group('confirm and remove', () {
    test('confirm sends the expected media id and reads the replacement result',
        () async {
      final worker = _Worker((r) => _json({
            'quotationId': _quotationId,
            'role': 'office_logo',
            'mediaObjectId': _mediaId,
            'previousMediaId': _otherId,
            'resultingVersion': 9,
          }));
      final service = await _service(worker);

      final result = await service.confirm(
        quotationId: _quotationId,
        role: QuotationMediaRole.officeLogo,
        mediaObjectId: _mediaId,
        expectedMediaId: _otherId,
      );

      expect(worker.requests.single.url.path, '/quotation-media/confirm');
      expect(worker.bodyOf(worker.requests.single), {
        'quotationId': _quotationId,
        'role': 'office_logo',
        'mediaObjectId': _mediaId,
        'expectedMediaId': _otherId,
      });
      expect(result.previousMediaId, _otherId);
      expect(result.resultingVersion, 9);
      expect(result.alreadyConfirmed, isFalse);
    });

    test('a repeated confirm is idempotent (alreadyConfirmed)', () async {
      final worker = _Worker((r) => _json({
            'quotationId': _quotationId,
            'role': 'office_logo',
            'mediaObjectId': _mediaId,
            'alreadyConfirmed': true,
          }));
      final service = await _service(worker);
      final result = await service.confirm(
        quotationId: _quotationId,
        role: QuotationMediaRole.officeLogo,
        mediaObjectId: _mediaId,
        expectedMediaId: null,
      );
      expect(result.alreadyConfirmed, isTrue);
      expect(result.resultingVersion, isNull);
    });

    test('remove names the slot by its expected id', () async {
      final worker = _Worker((r) => _json({
            'removed': true,
            'previousMediaId': _mediaId,
            'resultingVersion': 11,
          }));
      final service = await _service(worker);

      final result = await service.remove(
        quotationId: _quotationId,
        role: QuotationMediaRole.officeLogo,
        expectedMediaId: _mediaId,
      );

      expect(worker.requests.single.url.path, '/quotation-media/remove');
      expect(worker.bodyOf(worker.requests.single), {
        'quotationId': _quotationId,
        'role': 'office_logo',
        'expectedMediaId': _mediaId,
      });
      expect(result.previousMediaId, _mediaId);
      expect(result.resultingVersion, 11);
    });
  });

  group('signed read', () {
    test('lists the bound media with fresh signed URLs and an early expiry',
        () async {
      final worker = _Worker((r) => _json({
            'quotationId': _quotationId,
            'media': {
              'office_logo': {
                'mediaObjectId': _mediaId,
                'contentType': 'image/png',
                'url': _signedGet,
              },
              'quotation_pdf': null,
            },
            'expiresInSeconds': 900,
          }));
      final service = await _service(worker);

      final before = DateTime.now();
      final signed = await service.fetchSigned(_quotationId);

      final request = worker.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/quotation-media');
      expect(request.url.queryParameters['quotationId'], _quotationId);
      expect(request.headers['Authorization'], startsWith('Bearer '));

      expect(signed.officeLogo!.mediaObjectId, _mediaId);
      expect(signed.officeLogo!.contentType, 'image/png');
      expect(signed.officeLogo!.url, _signedGet);
      expect(signed.quotationPdf, isNull);
      expect(
        signed.officeLogo!.expiresAt
            .isBefore(before.add(const Duration(seconds: 901))),
        isTrue,
        reason: 'measured from the request, so it can only err early',
      );
    });

    test('an answer without a media map is not accepted', () async {
      final worker = _Worker((r) => _json({'quotationId': _quotationId}));
      final service = await _service(worker);
      await expectLater(
        service.fetchSigned(_quotationId),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.invalidResponse)),
      );
    });
  });

  group('failures', () {
    test('Worker codes and statuses map to fixed categories', () {
      QuotationMediaFailure of(int status, [String? code]) =>
          R2QuotationMediaService.failureFor(status, code);

      expect(of(409, 'stale_replacement'), QuotationMediaFailure.staleReplacement);
      expect(of(404, 'quotation_not_found'), QuotationMediaFailure.quotationNotFound);
      expect(of(400, 'unsupported_media_type'), QuotationMediaFailure.unsupportedType);
      expect(of(400, 'media_too_large'), QuotationMediaFailure.tooLarge);
      expect(of(422, 'media_type_mismatch'), QuotationMediaFailure.typeMismatch);
      expect(of(409, 'upload_incomplete'), QuotationMediaFailure.uploadIncomplete);
      expect(of(401), QuotationMediaFailure.unauthorized);
      expect(of(502), QuotationMediaFailure.unavailable);
      expect(of(500, 'anything'), QuotationMediaFailure.unavailable);
      expect(of(418), QuotationMediaFailure.unknown);
    });

    test('a stale replacement carries its stable code and is not retryable',
        () async {
      final worker = _Worker((r) => _json(
          {'error': 'free text', 'code': 'stale_replacement'}, 409));
      final service = await _service(worker);

      Object? caught;
      try {
        await service.confirm(
          quotationId: _quotationId,
          role: QuotationMediaRole.officeLogo,
          mediaObjectId: _mediaId,
          expectedMediaId: null,
        );
      } catch (error) {
        caught = error;
      }
      final failure = caught! as QuotationMediaException;
      expect(failure.failure, QuotationMediaFailure.staleReplacement);
      expect(failure.statusCode, 409);
      expect(failure.workerCode, 'stale_replacement');
      expect(failure.isRetryable, isFalse);
      expect(failure.toString().contains('free text'), isFalse,
          reason: 'the Worker message is provider text and is never kept');
    });

    test('an unreachable service is unavailable and names no host', () async {
      final service = R2QuotationMediaService(
        httpClient: MockClient((_) async =>
            throw http.ClientException('failed host lookup: media-api.example')),
        supabaseClient: await _signedIn(),
      );
      Object? caught;
      try {
        await service.fetchSigned(_quotationId);
      } catch (error) {
        caught = error;
      }
      final failure = caught! as QuotationMediaException;
      expect(failure.failure, QuotationMediaFailure.unavailable);
      expect(failure.toString().contains('media-api'), isFalse);
      expect(failure.isRetryable, isTrue);
    });

    test('without a session nothing is sent', () async {
      final worker = _Worker((r) => _json({}));
      final service = await _service(worker, withSession: false);
      await expectLater(
        service.remove(
          quotationId: _quotationId,
          role: QuotationMediaRole.officeLogo,
          expectedMediaId: null,
        ),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.notSignedIn)),
      );
      expect(worker.requests, isEmpty);
    });

    test('a non-JSON answer is an invalid response, not a crash', () async {
      final worker = _Worker((r) => http.Response('<html>oops</html>', 200));
      final service = await _service(worker);
      await expectLater(
        service.confirm(
          quotationId: _quotationId,
          role: QuotationMediaRole.officeLogo,
          mediaObjectId: _mediaId,
          expectedMediaId: null,
        ),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.invalidResponse)),
      );
    });
  });
}
