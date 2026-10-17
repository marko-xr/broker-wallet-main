// Tests for the plan routes' Worker client: the exact bodies it sends for an
// Offer and for an Owner record, how it reads each answer, how Worker codes map
// to fixed failure categories, and that no credential, signed URL or storage key
// ever reaches an error or a request that should not carry it.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/r2_plan_attachment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _offerId = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';
const _ownerId = '9c1b7e24-0d3a-4f58-8b6e-2a5d4c7f1e90';
const _mediaId = '22222222-2222-4222-8222-222222222222';
const _otherId = '33333333-3333-4333-8333-333333333333';
const _signedPut =
    'https://r2.example.test/bucket/key?X-Amz-Signature=secret-put';
const _signedGet =
    'https://r2.example.test/bucket/key?X-Amz-Signature=secret-get';

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
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'refresh',
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'plan-attachment-test@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-12T10:00:00Z',
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

Future<R2PlanAttachmentService> _service(_Worker worker,
        {bool withSession = true}) async =>
    R2PlanAttachmentService(
      httpClient: worker.client,
      supabaseClient: await _signedIn(withSession: withSession),
    );

Future<File> _tempFile(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('plan_service_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}file.bin');
  await file.writeAsBytes(bytes);
  return file;
}

Future<PlanAttachmentException> _failureOf(
    Future<Object?> Function() run) async {
  Object? caught;
  try {
    await run();
  } catch (error) {
    caught = error;
  }
  expect(caught, isA<PlanAttachmentException>());
  return caught! as PlanAttachmentException;
}

void main() {
  group('authorize', () {
    test('an Offer: posts the contract body with a bearer token', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
            'mediaType': 'pdf',
            'expiresInSeconds': 300,
          }));
      final service = await _service(worker);

      final result = await service.authorize(
        parent: PlanParent.offer,
        parentId: _offerId,
        expectedMediaId: null,
        mediaObjectId: _mediaId,
        contentType: 'application/pdf',
        contentLength: 1234,
        originalFileName: 'Plot 14 plan.pdf',
      );

      expect(result.isAlreadyReady, isFalse);
      expect(result.mediaObjectId, _mediaId);
      expect(result.presignedUrl, _signedPut);

      final request = worker.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/offer-plan/authorize');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.headers['Content-Type'], contains('application/json'));
      final body = worker.bodyOf(request);
      expect(body, {
        'offerId': _offerId,
        'expectedMediaId': null,
        'mediaObjectId': _mediaId,
        'contentType': 'application/pdf',
        'contentLength': 1234,
        'originalFileName': 'Plot 14 plan.pdf',
      });
      expect(body.containsKey('expectedMediaId'), isTrue,
          reason: 'the Worker requires the key, with null for "no plan"');
    });

    test('an Owner: its own route and its own id field', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
          }));
      final service = await _service(worker);
      await service.authorize(
        parent: PlanParent.owner,
        parentId: _ownerId,
        expectedMediaId: _otherId,
        mediaObjectId: _mediaId,
        contentType: 'image/jpeg',
        contentLength: 50,
      );

      final request = worker.requests.single;
      expect(request.url.path, '/owner-plan/authorize');
      final body = worker.bodyOf(request);
      expect(body['ownerRecordId'], _ownerId);
      expect(body.containsKey('offerId'), isFalse);
      expect(body['expectedMediaId'], _otherId);
      expect(body.containsKey('originalFileName'), isFalse,
          reason: 'no name was given, so none is sent');
    });

    test('an empty file name is not sent', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
          }));
      final service = await _service(worker);
      await service.authorize(
        parent: PlanParent.offer,
        parentId: _offerId,
        expectedMediaId: null,
        mediaObjectId: _mediaId,
        contentType: 'image/png',
        contentLength: 5,
        originalFileName: '',
      );
      expect(
          worker.bodyOf(worker.requests.single).containsKey('originalFileName'),
          isFalse);
    });

    test('never sends a storage key, a bucket or a link of its own', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'presignedUrl': _signedPut,
            'mediaObjectId': _mediaId,
          }));
      final service = await _service(worker);
      await service.authorize(
        parent: PlanParent.offer,
        parentId: _offerId,
        expectedMediaId: null,
        mediaObjectId: _mediaId,
        contentType: 'application/pdf',
        contentLength: 10,
      );
      final sent = worker.requests.single.body;
      for (final forbidden in [
        'objectKey',
        'object_key',
        'bucket',
        'url',
        'http'
      ]) {
        expect(sent.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('an id that is already the plan answers ready (nothing to upload)',
        () async {
      final worker =
          _Worker((r) => _json({'status': 'ready', 'mediaObjectId': _mediaId}));
      final service = await _service(worker);
      final result = await service.authorize(
        parent: PlanParent.offer,
        parentId: _offerId,
        expectedMediaId: _mediaId,
        mediaObjectId: _mediaId,
        contentType: 'application/pdf',
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
      final failure = await _failureOf(() => service.authorize(
            parent: PlanParent.offer,
            parentId: _offerId,
            expectedMediaId: null,
            mediaObjectId: _mediaId,
            contentType: 'application/pdf',
            contentLength: 1,
          ));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
    });

    test('a pending answer without a signed URL is not accepted', () async {
      final worker = _Worker(
          (r) => _json({'status': 'pending', 'mediaObjectId': _mediaId}));
      final service = await _service(worker);
      final failure = await _failureOf(() => service.authorize(
            parent: PlanParent.owner,
            parentId: _ownerId,
            expectedMediaId: null,
            mediaObjectId: _mediaId,
            contentType: 'application/pdf',
            contentLength: 1,
          ));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
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
        contentType: 'application/pdf',
      );

      final request = worker.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.toString(), _signedPut);
      expect(request.headers['Content-Type'], 'application/pdf');
      expect(request.bodyBytes, [1, 2, 3, 4, 5]);
      expect(request.headers.containsKey('Authorization'), isFalse,
          reason: 'the Supabase token must never be sent to storage');
    });

    test('a refused signature is uploadRejected and never exposes the URL',
        () async {
      final worker = _Worker((r) => http.Response('<Error/>', 403));
      final service = await _service(worker);
      final file = await _tempFile([1]);

      final failure = await _failureOf(() => service.uploadBytes(
          presignedUrl: _signedPut, file: file, contentType: 'image/png'));
      expect(failure.failure, PlanAttachmentFailure.uploadRejected);
      expect(failure.statusCode, 403);
      expect(failure.isRetryable, isTrue);
      expect(failure.toString().contains('secret-put'), isFalse);
      expect(failure.toString().contains('r2.example.test'), isFalse);
    });

    test('a dropped connection is interrupted (nothing was confirmed)',
        () async {
      final service = R2PlanAttachmentService(
        httpClient: MockClient((_) async => throw const SocketException('x')),
        supabaseClient: await _signedIn(),
      );
      final file = await _tempFile([1]);
      final failure = await _failureOf(() => service.uploadBytes(
          presignedUrl: _signedPut, file: file, contentType: 'image/png'));
      expect(failure.failure, PlanAttachmentFailure.interrupted);
    });

    test('a file that is gone is reported before anything is sent', () async {
      final worker = _Worker((r) => http.Response('', 200));
      final service = await _service(worker);
      final file = await _tempFile([1]);
      await file.delete();
      final failure = await _failureOf(() => service.uploadBytes(
          presignedUrl: _signedPut, file: file, contentType: 'image/png'));
      expect(failure.failure, PlanAttachmentFailure.fileUnavailable);
      expect(worker.requests, isEmpty);
    });
  });

  group('confirm and remove', () {
    test('confirm names the plan it replaces and reads the result', () async {
      final worker = _Worker((r) => _json({
            'offerId': _offerId,
            'mediaObjectId': _mediaId,
            'previousMediaId': _otherId,
            'cleanupPending': true,
          }));
      final service = await _service(worker);

      final result = await service.confirm(
        parent: PlanParent.offer,
        parentId: _offerId,
        mediaObjectId: _mediaId,
        expectedMediaId: _otherId,
      );

      final request = worker.requests.single;
      expect(request.url.path, '/offer-plan/confirm');
      expect(worker.bodyOf(request), {
        'offerId': _offerId,
        'mediaObjectId': _mediaId,
        'expectedMediaId': _otherId,
      });
      expect(result.previousMediaId, _otherId);
      expect(result.alreadyConfirmed, isFalse);
      expect(result.cleanupPending, isTrue);
    });

    test('an Owner confirm uses the Owner route and field', () async {
      final worker = _Worker((r) => _json({
            'ownerRecordId': _ownerId,
            'mediaObjectId': _mediaId,
          }));
      final service = await _service(worker);
      await service.confirm(
        parent: PlanParent.owner,
        parentId: _ownerId,
        mediaObjectId: _mediaId,
        expectedMediaId: null,
      );
      final request = worker.requests.single;
      expect(request.url.path, '/owner-plan/confirm');
      expect(worker.bodyOf(request), {
        'ownerRecordId': _ownerId,
        'mediaObjectId': _mediaId,
        'expectedMediaId': null,
      });
    });

    test('a repeated confirm is idempotent (alreadyConfirmed)', () async {
      final worker = _Worker((r) => _json({
            'offerId': _offerId,
            'mediaObjectId': _mediaId,
            'alreadyConfirmed': true,
          }));
      final service = await _service(worker);
      final result = await service.confirm(
        parent: PlanParent.offer,
        parentId: _offerId,
        mediaObjectId: _mediaId,
        expectedMediaId: null,
      );
      expect(result.alreadyConfirmed, isTrue);
      expect(result.previousMediaId, isNull);
    });

    test('remove names the plan by its expected id', () async {
      final worker = _Worker((r) => _json({
            'removed': true,
            'ownerRecordId': _ownerId,
            'previousMediaId': _mediaId,
          }));
      final service = await _service(worker);

      final result = await service.remove(
        parent: PlanParent.owner,
        parentId: _ownerId,
        expectedMediaId: _mediaId,
      );

      final request = worker.requests.single;
      expect(request.url.path, '/owner-plan/remove');
      expect(worker.bodyOf(request), {
        'ownerRecordId': _ownerId,
        'expectedMediaId': _mediaId,
      });
      expect(result.previousMediaId, _mediaId);
      expect(result.alreadyRemoved, isFalse);
    });

    test('withdrawing an unattached upload names it', () async {
      final worker = _Worker((r) => _json({
            'removed': true,
            'offerId': _offerId,
            'mediaObjectId': _mediaId,
            'alreadyRemoved': true,
          }));
      final service = await _service(worker);
      final result = await service.remove(
        parent: PlanParent.offer,
        parentId: _offerId,
        expectedMediaId: null,
        mediaObjectId: _mediaId,
      );
      expect(worker.bodyOf(worker.requests.single), {
        'offerId': _offerId,
        'expectedMediaId': null,
        'mediaObjectId': _mediaId,
      });
      expect(result.alreadyRemoved, isTrue);
    });
  });

  group('signed read', () {
    test('an Offer\'s plan: a fresh signed link with an early expiry',
        () async {
      final worker = _Worker((r) => _json({
            'offerId': _offerId,
            'plan': {
              'mediaObjectId': _mediaId,
              'contentType': 'application/pdf',
              'kind': 'document',
              'fileName': 'Plot 14 plan.pdf',
              'sizeBytes': 4096,
              'url': _signedGet,
            },
            'expiresInSeconds': 900,
          }));
      final service = await _service(worker);

      final before = DateTime.now();
      final plan = await service.fetchCurrent(
          parent: PlanParent.offer, parentId: _offerId);

      final request = worker.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/offer-plan');
      expect(request.url.queryParameters, {'offerId': _offerId});
      expect(request.headers['Authorization'], startsWith('Bearer '));

      expect(plan, isNotNull);
      expect(plan!.mediaObjectId, _mediaId);
      expect(plan.kind, PlanAttachmentKind.pdf);
      expect(plan.contentType, 'application/pdf');
      expect(plan.displayName, 'Plot 14 plan.pdf');
      expect(plan.byteLength, 4096);
      expect(plan.signedUrl, _signedGet);
      expect(
        plan.signedUrlExpiresAt!
            .isBefore(before.add(const Duration(seconds: 901))),
        isTrue,
        reason: 'measured from the request, so it can only err early',
      );
      expect(plan.hasFreshUrl(DateTime.now()), isTrue);
    });

    test('an Owner\'s plan is read from its own route', () async {
      final worker = _Worker((r) => _json({
            'ownerRecordId': _ownerId,
            'plan': {
              'mediaObjectId': _mediaId,
              'contentType':
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'kind': 'document',
              'fileName': null,
              'sizeBytes': null,
              'url': _signedGet,
            },
            'expiresInSeconds': 900,
          }));
      final service = await _service(worker);
      final plan = await service.fetchCurrent(
          parent: PlanParent.owner, parentId: _ownerId);
      final request = worker.requests.single;
      expect(request.url.path, '/owner-plan');
      expect(request.url.queryParameters, {'ownerRecordId': _ownerId});
      expect(plan!.kind, PlanAttachmentKind.word);
      expect(plan.displayName, isNull);
      expect(plan.byteLength, isNull);
    });

    test('a record without a plan answers null', () async {
      final worker = _Worker((r) => _json({'offerId': _offerId, 'plan': null}));
      final service = await _service(worker);
      expect(
          await service.fetchCurrent(
              parent: PlanParent.offer, parentId: _offerId),
          isNull);
    });

    test('an answer without a plan key is not accepted', () async {
      final worker = _Worker((r) => _json({'offerId': _offerId}));
      final service = await _service(worker);
      final failure = await _failureOf(() =>
          service.fetchCurrent(parent: PlanParent.offer, parentId: _offerId));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
    });

    test('a plan of an unknown type or without an id is not accepted',
        () async {
      for (final plan in <Object?>[
        {
          'mediaObjectId': _mediaId,
          'contentType': 'application/zip',
          'url': _signedGet
        },
        {
          'mediaObjectId': _mediaId,
          'contentType': 'image/gif',
          'url': _signedGet
        },
        {
          'mediaObjectId': '',
          'contentType': 'application/pdf',
          'url': _signedGet
        },
        {'contentType': 'application/pdf', 'url': _signedGet},
        'a string',
        42,
      ]) {
        final worker = _Worker((r) => _json({'plan': plan}));
        final service = await _service(worker);
        final failure = await _failureOf(() =>
            service.fetchCurrent(parent: PlanParent.offer, parentId: _offerId));
        expect(failure.failure, PlanAttachmentFailure.invalidResponse,
            reason: '$plan');
      }
    });
  });

  group('download', () {
    test('writes the stream to the target and keeps nothing else', () async {
      final bytes = List<int>.generate(2000, (i) => i % 251);
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream.value(bytes), 200,
              contentLength: bytes.length));
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');

      await service.download(url: _signedGet, target: target, maxBytes: 5000);
      expect(await target.readAsBytes(), bytes);
    });

    test('never sends the account token to storage', () async {
      http.BaseRequest? seen;
      final client = MockClient.streaming((request, body) async {
        seen = request;
        return http.StreamedResponse(Stream.value([1]), 200, contentLength: 1);
      });
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');
      await service.download(url: _signedGet, target: target, maxBytes: 100);
      expect(seen!.headers.containsKey('Authorization'), isFalse);
    });

    test('refuses a file larger than the limit it was given, by its size',
        () async {
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream.value(List<int>.filled(10, 1)), 200,
              contentLength: 10));
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');
      final failure = await _failureOf(
          () => service.download(url: _signedGet, target: target, maxBytes: 5));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
      expect(target.existsSync(), isFalse);
    });

    test(
        'refuses a stream that outgrows its limit and removes the partial file',
        () async {
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(
              Stream.fromIterable(
                  [List<int>.filled(4, 1), List<int>.filled(4, 2)]),
              200));
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');
      final failure = await _failureOf(
          () => service.download(url: _signedGet, target: target, maxBytes: 6));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
      expect(target.existsSync(), isFalse);
    });

    test('a refused link is unavailable and names no URL', () async {
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream.value(<int>[]), 403));
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');
      final failure = await _failureOf(() =>
          service.download(url: _signedGet, target: target, maxBytes: 100));
      expect(failure.failure, PlanAttachmentFailure.unavailable);
      expect(failure.statusCode, 403);
      expect(failure.toString().contains('secret-get'), isFalse);
      expect(failure.toString().contains('r2.example.test'), isFalse);
      expect(target.existsSync(), isFalse);
    });

    test('a dropped connection is unavailable and names no host', () async {
      final client = MockClient.streaming((request, body) async =>
          throw http.ClientException('failed host lookup: r2.example.test'));
      final service = R2PlanAttachmentService(
          httpClient: client, supabaseClient: await _signedIn());
      final target = File('${(await _tempFile([
            0
          ])).parent.path}${Platform.pathSeparator}out.bin');
      final failure = await _failureOf(() =>
          service.download(url: _signedGet, target: target, maxBytes: 100));
      expect(failure.failure, PlanAttachmentFailure.unavailable);
      expect(failure.toString().contains('r2.example'), isFalse);
    });
  });

  group('failures', () {
    test('Worker codes and statuses map to fixed categories', () {
      PlanAttachmentFailure of(int status, [String? code]) =>
          R2PlanAttachmentService.failureFor(status, code);

      expect(
          of(409, 'stale_replacement'), PlanAttachmentFailure.staleReplacement);
      expect(of(404, 'offer_not_found'), PlanAttachmentFailure.parentNotFound);
      expect(of(404, 'owner_not_found'), PlanAttachmentFailure.parentNotFound);
      expect(of(400, 'unsupported_media_type'),
          PlanAttachmentFailure.unsupportedType);
      expect(of(400, 'image_too_large'), PlanAttachmentFailure.imageTooLarge);
      expect(of(400, 'document_too_large'),
          PlanAttachmentFailure.documentTooLarge);
      expect(
          of(422, 'media_type_mismatch'), PlanAttachmentFailure.typeMismatch);
      expect(
          of(409, 'upload_incomplete'), PlanAttachmentFailure.uploadIncomplete);
      expect(of(409, 'upload_rejected'), PlanAttachmentFailure.uploadRejected);
      expect(of(409, 'media_mismatch'), PlanAttachmentFailure.uploadRejected);
      expect(of(409, 'invalid_state'), PlanAttachmentFailure.uploadRejected);
      expect(of(410, 'media_removed'), PlanAttachmentFailure.mediaRemoved);
      expect(
          of(429, 'plan_upload_limit'), PlanAttachmentFailure.tooManyPending);
      expect(of(409, 'session_superseded'),
          PlanAttachmentFailure.sessionSuperseded);
      expect(of(503, 'session_check_unavailable'),
          PlanAttachmentFailure.unavailable);
      expect(of(401), PlanAttachmentFailure.unauthorized);
      expect(of(502), PlanAttachmentFailure.unavailable);
      expect(of(500, 'anything'), PlanAttachmentFailure.unavailable);
      expect(of(418), PlanAttachmentFailure.unknown);
    });

    test('every category explains itself with one localized key', () {
      for (final failure in PlanAttachmentFailure.values) {
        expect(failure.messageKey, startsWith('planAttachment'));
      }
    });

    test(
        'a stale replacement carries its stable code and the Worker text is never kept',
        () async {
      final worker = _Worker((r) =>
          _json({'error': 'free text', 'code': 'stale_replacement'}, 409));
      final service = await _service(worker);

      final failure = await _failureOf(() => service.confirm(
            parent: PlanParent.offer,
            parentId: _offerId,
            mediaObjectId: _mediaId,
            expectedMediaId: null,
          ));
      expect(failure.failure, PlanAttachmentFailure.staleReplacement);
      expect(failure.statusCode, 409);
      expect(failure.workerCode, 'stale_replacement');
      expect(failure.toString().contains('free text'), isFalse,
          reason: 'the Worker message is provider text and is never kept');
    });

    test('a displaced session is reported as such', () async {
      final worker = _Worker(
          (r) => _json({'error': 'x', 'code': 'session_superseded'}, 409));
      final service = await _service(worker);
      final failure = await _failureOf(() =>
          service.fetchCurrent(parent: PlanParent.owner, parentId: _ownerId));
      expect(failure.failure, PlanAttachmentFailure.sessionSuperseded);
      expect(failure.isRetryable, isFalse);
    });

    test('an unreachable service is unavailable and names no host', () async {
      final service = R2PlanAttachmentService(
        httpClient: MockClient((_) async => throw http.ClientException(
            'failed host lookup: media-api.example')),
        supabaseClient: await _signedIn(),
      );
      final failure = await _failureOf(() =>
          service.fetchCurrent(parent: PlanParent.offer, parentId: _offerId));
      expect(failure.failure, PlanAttachmentFailure.unavailable);
      expect(failure.toString().contains('media-api'), isFalse);
      expect(failure.isRetryable, isTrue);
    });

    test('without a session nothing is sent', () async {
      final worker = _Worker((r) => _json({}));
      final service = await _service(worker, withSession: false);
      for (final call in <Future<Object?> Function()>[
        () => service.remove(
            parent: PlanParent.offer,
            parentId: _offerId,
            expectedMediaId: null),
        () =>
            service.fetchCurrent(parent: PlanParent.owner, parentId: _ownerId),
        () => service.confirm(
            parent: PlanParent.owner,
            parentId: _ownerId,
            mediaObjectId: _mediaId,
            expectedMediaId: null),
      ]) {
        final failure = await _failureOf(call);
        expect(failure.failure, PlanAttachmentFailure.notSignedIn);
      }
      expect(worker.requests, isEmpty);
    });

    test('a non-JSON answer is an invalid response, not a crash', () async {
      final worker = _Worker((r) => http.Response('<html>oops</html>', 200));
      final service = await _service(worker);
      final failure = await _failureOf(() => service.confirm(
            parent: PlanParent.offer,
            parentId: _offerId,
            mediaObjectId: _mediaId,
            expectedMediaId: null,
          ));
      expect(failure.failure, PlanAttachmentFailure.invalidResponse);
    });

    test('no error text carries a link, a key, a token or an id', () async {
      final worker = _Worker((r) => _json({
            'error': 'token $_signedGet profiles/$_uid/offer-plans/x',
            'code': 'invalid_state'
          }, 409));
      final service = await _service(worker);
      final failure = await _failureOf(() => service.authorize(
            parent: PlanParent.offer,
            parentId: _offerId,
            expectedMediaId: null,
            mediaObjectId: _mediaId,
            contentType: 'application/pdf',
            contentLength: 1,
          ));
      final text = failure.toString();
      for (final secret in [
        'secret-get',
        'r2.example',
        'profiles/',
        _uid,
        _offerId,
        _mediaId
      ]) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    });
  });
}
