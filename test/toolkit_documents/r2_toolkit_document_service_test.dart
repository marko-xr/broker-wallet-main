// The Toolkit routes' Worker client: the exact bodies it sends, how it reads each
// answer, how Worker codes map to fixed failure categories, the account binding,
// and that no credential, signed URL or storage key ever reaches an error or a
// request that should not carry it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:broker_wallet/src/services/toolkit_documents/r2_toolkit_document_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

import 'toolkit_fakes.dart';

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

Future<sb.SupabaseClient> _signedIn(String uid,
    {bool withSession = true}) async {
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((_) async => http.Response('{}', 200)),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  if (withSession) {
    await client.auth.setInitialSession(jsonEncode({
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
        'email': 'toolkit-test@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-19T10:00:00Z',
      },
    }));
  }
  return client;
}

http.Response _json(Object body,
        [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...headers});

class _Worker {
  _Worker(this.respond);

  final http.Response Function(http.Request request) respond;
  final List<http.BaseRequest> requests = [];

  late final http.Client client = MockClient.streaming((request, body) async {
    final bytes = await body.toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    requests.add(copy);
    final response = respond(copy);
    return http.StreamedResponse(
        Stream<List<int>>.value(response.bodyBytes), response.statusCode,
        headers: response.headers);
  });

  Map<String, dynamic> bodyOf(http.BaseRequest r) =>
      jsonDecode((r as http.Request).body) as Map<String, dynamic>;
}

Future<R2ToolkitDocumentService> _service(_Worker worker,
        {String account = accountA,
        String? signedInAs,
        bool withSession = true}) async =>
    R2ToolkitDocumentService(
      accountId: account,
      httpClient: worker.client,
      supabaseClient:
          await _signedIn(signedInAs ?? account, withSession: withSession),
    );

Future<ToolkitDocumentException> _failureOf(
    Future<Object?> Function() run) async {
  try {
    await run();
  } on ToolkitDocumentException catch (error) {
    return error;
  }
  fail('expected a ToolkitDocumentException');
}

void main() {
  group('requests', () {
    test('authorize sends exactly the document\'s facts and no owner or key',
        () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'documentId': doc1,
            'presignedUrl': _signedPut,
            'expiresInSeconds': 300,
          }));
      final service = await _service(worker);
      final result = await service.authorize(
        documentId: doc1,
        type: ToolkitDocumentType.combinePdfs,
        contentType: ToolkitContentType.pdf,
        title: 'Merged',
        contentLength: 1234,
        pageCount: 5,
        contentSha256: 'a' * 64,
        sourceCreatedAt: DateTime.utc(2026, 10, 19, 8, 30),
      );
      expect(result.presignedUrl, _signedPut);
      expect(result.alreadyConfirmed, isFalse);
      final request = worker.requests.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.path, '/toolkit-documents/authorize');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(worker.bodyOf(request), {
        'documentId': doc1,
        'documentType': 'combine_pdfs',
        'title': 'Merged',
        'contentType': 'application/pdf',
        'contentLength': 1234,
        'pageCount': 5,
        'contentSha256': 'a' * 64,
        'sourceCreatedAt': '2026-10-19T08:30:00.000Z',
      });
    });

    test('authorize answers "already confirmed" for a ready document',
        () async {
      final worker = _Worker((r) => _json(
          {'status': 'ready', 'documentId': doc1, 'alreadyConfirmed': true}));
      final result = await (await _service(worker)).authorize(
          documentId: doc1,
          type: ToolkitDocumentType.scanner,
          title: 't',
          contentLength: 5,
          contentType: ToolkitContentType.pdf,
          contentSha256: 'a' * 64,
          sourceCreatedAt: DateTime.utc(2026));
      expect(result.alreadyConfirmed, isTrue);
      expect(result.presignedUrl, isNull);
    });

    test('an answer for another id or without a URL is invalid', () async {
      for (final body in [
        {'status': 'pending', 'documentId': doc2, 'presignedUrl': _signedPut},
        {'status': 'pending', 'documentId': doc1},
        {'status': 'weird', 'documentId': doc1, 'presignedUrl': _signedPut},
        {'documentId': doc1},
      ]) {
        final service = await _service(_Worker((r) => _json(body)));
        final error = await _failureOf(() => service.authorize(
            documentId: doc1,
            type: ToolkitDocumentType.scanner,
            title: 't',
            contentLength: 5,
            contentType: ToolkitContentType.pdf,
            contentSha256: 'a' * 64,
            sourceCreatedAt: DateTime.utc(2026)));
        expect(error.failure, ToolkitFailure.invalidResponse, reason: '$body');
      }
    });

    test(
        'confirm, rename and remove post only the document id and their own fields',
        () async {
      final worker = _Worker((r) => switch (r.url.path) {
            '/toolkit-documents/confirm' =>
              _json({'documentId': doc1, 'version': 3}),
            '/toolkit-documents/rename' =>
              _json({'documentId': doc1, 'title': 'New', 'version': 4}),
            _ => _json(
                {'removed': true, 'documentId': doc1, 'cleanupPending': true}),
          });
      final service = await _service(worker);
      final confirmation = await service.confirm(documentId: doc1);
      expect((confirmation.version, confirmation.alreadyConfirmed), (3, false));
      final renamed = await service.rename(
          documentId: doc1, title: 'New', expectedVersion: 3);
      expect((renamed.title, renamed.version), ('New', 4));
      final removed = await service.remove(documentId: doc1);
      expect((removed.cleanupPending, removed.alreadyRemoved), (true, false));
      expect(worker.requests.map((r) => worker.bodyOf(r)), [
        {'documentId': doc1},
        {'documentId': doc1, 'title': 'New', 'expectedVersion': 3},
        {'documentId': doc1},
      ]);
    });

    test(
        'list sends its paging as a query and reads documents, cursor and usage',
        () async {
      final worker = _Worker((r) => _json({
            'documents': [
              {
                'documentId': doc1,
                'documentType': 'scanner',
                'contentType': 'image/jpeg',
                'title': 'Scan',
                'sizeBytes': 10,
                'pageCount': 1,
                'contentSha256': 'd' * 64,
                'sha256Verified': true,
                'sourceCreatedAt': '2026-10-19T08:00:00.000Z',
                'createdAt': '2026-10-19T08:00:01.000Z',
                'version': 2,
              }
            ],
            'nextCursor': 'abc',
            'usage': {
              'readyCount': 1,
              'readyBytes': 10,
              'pendingCount': 0,
              'pendingBytes': 0
            },
            'limits': {
              'documentBytes': 100,
              'accountBytes': 1000,
              'accountDocuments': 5
            },
          }));
      final page = await (await _service(worker)).listPage(
          cursor: 'prev', limit: 25, type: ToolkitDocumentType.scanner);
      expect(page.documents.single.documentId, doc1);
      expect(page.nextCursor, 'abc');
      expect(page.usage!.readyBytes, 10);
      expect(page.usage!.accountDocumentsLimit, 5);
      final request = worker.requests.single as http.Request;
      expect(request.method, 'GET');
      expect(request.url.path, '/toolkit-documents');
      expect(request.url.queryParameters,
          {'limit': '25', 'cursor': 'prev', 'documentType': 'scanner'});
    });

    test('a list that is off the contract is invalid, never partially used',
        () async {
      for (final body in [
        {'documents': 'x'},
        {
          'documents': [
            {'documentId': 'nope'}
          ],
          'nextCursor': null
        },
        {'documents': [], 'nextCursor': ''},
        {'documents': [], 'nextCursor': 5},
        {
          'documents': [],
          'nextCursor': null,
          'usage': {'readyCount': -1}
        },
      ]) {
        final service = await _service(_Worker((r) => _json(body)));
        final error = await _failureOf(() => service.listPage());
        expect(error.failure, ToolkitFailure.invalidResponse, reason: '$body');
      }
    });

    test('status covers every id asked about and nothing else', () async {
      final ok = _Worker((r) => _json({
            'documents': [
              {'documentId': doc1, 'state': 'ready', 'version': 2},
              {'documentId': doc2, 'state': 'deleted', 'version': 3},
            ],
            'unknownIds': [doc3],
          }));
      final statuses = await (await _service(ok)).statuses([doc1, doc2, doc3]);
      expect(statuses.byId, {
        doc1: ToolkitRemoteState.ready,
        doc2: ToolkitRemoteState.deleted,
        doc3: ToolkitRemoteState.unknown,
      });
      final service = await _service(ok);
      expect((await _failureOf(() => service.statuses([doc1, doc2]))).failure,
          ToolkitFailure.invalidResponse,
          reason: 'an unexpected id came back');
      expect(
          (await _failureOf(() => service.statuses([doc1, doc2, doc3, doc4])))
              .failure,
          ToolkitFailure.invalidResponse,
          reason: 'an asked id was not answered');
      expect((await _failureOf(() => service.statuses([]))).failure,
          ToolkitFailure.invalidRequest);
      expect((await _failureOf(() => service.statuses(['nope']))).failure,
          ToolkitFailure.invalidRequest);
      expect(ok.requests.length, 3, reason: 'bad requests were not sent');
    });

    test('a download ticket must match the document asked for', () async {
      final good = {
        'documentId': doc1,
        'documentType': 'signature',
        'contentType': 'application/pdf',
        'title': 'Signed',
        'sizeBytes': 99,
        'pageCount': 2,
        'contentSha256': 'b' * 64,
        'sha256Verified': true,
        'version': 4,
        'url': _signedGet,
        'expiresInSeconds': 900,
      };
      final service = await _service(_Worker((r) => _json(good)));
      final ticket = await service.downloadTicket(doc1);
      expect((ticket.sizeBytes, ticket.contentSha256, ticket.type),
          (99, 'b' * 64, ToolkitDocumentType.signature));
      expect(
          ticket.expiresAt
              .isAfter(DateTime.now().add(const Duration(minutes: 14))),
          isTrue);
      expect(
          ticket.expiresAt
              .isBefore(DateTime.now().add(const Duration(minutes: 16))),
          isTrue);
      for (final change in [
        {'documentId': doc2},
        {'sizeBytes': 0},
        {'url': null},
        {'documentType': 'notes'},
        {'contentSha256': 'XYZ'},
      ]) {
        final bad = _Worker((r) => _json({...good, ...change}));
        final error = await _failureOf(
            () async => (await _service(bad)).downloadTicket(doc1));
        expect(error.failure, ToolkitFailure.invalidResponse,
            reason: '$change');
      }
    });
  });

  group('account binding', () {
    test('another signed-in account fails before anything is sent', () async {
      final worker = _Worker((r) => _json({}));
      final service =
          await _service(worker, account: accountA, signedInAs: accountB);
      for (final run in <Future<Object?> Function()>[
        () => service.authorize(
            documentId: doc1,
            type: ToolkitDocumentType.scanner,
            title: 't',
            contentLength: 5,
            contentType: ToolkitContentType.pdf,
            contentSha256: 'a' * 64,
            sourceCreatedAt: DateTime.utc(2026)),
        () => service.confirm(documentId: doc1),
        () => service.listPage(),
        () => service.statuses([doc1]),
        () => service.downloadTicket(doc1),
        () => service.rename(documentId: doc1, title: 't', expectedVersion: 1),
        () => service.remove(documentId: doc1),
      ]) {
        expect((await _failureOf(run)).failure, ToolkitFailure.accountChanged);
      }
      expect(worker.requests, isEmpty);
    });

    test('nobody signed in is its own failure', () async {
      final worker = _Worker((r) => _json({}));
      final service = await _service(worker, withSession: false);
      expect((await _failureOf(() => service.listPage())).failure,
          ToolkitFailure.notSignedIn);
      expect(worker.requests, isEmpty);
    });

    test('the upload also refuses a different account', () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.pdf')..writeAsBytesSync(pdfBytes());
      final worker = _Worker((r) => http.Response('', 200));
      final service =
          await _service(worker, account: accountA, signedInAs: accountB);
      expect(
          (await _failureOf(() => service.uploadBytes(
                  presignedUrl: _signedPut,
                  file: file,
                  contentType: ToolkitContentType.pdf)))
              .failure,
          ToolkitFailure.accountChanged);
      expect(worker.requests, isEmpty);
    });
  });

  group('failures', () {
    test('Worker codes map to fixed categories', () {
      final cases = <String, ToolkitFailure>{
        'unsupported_media_type': ToolkitFailure.unsupported,
        'unsupported_document_type': ToolkitFailure.unsupported,
        'document_too_large': ToolkitFailure.tooLarge,
        'invalid_request': ToolkitFailure.invalidRequest,
        'invalid_title': ToolkitFailure.invalidRequest,
        'document_deleted': ToolkitFailure.documentDeleted,
        'document_not_found': ToolkitFailure.documentNotFound,
        'document_id_unavailable': ToolkitFailure.idConflict,
        'idempotency_mismatch': ToolkitFailure.idConflict,
        'document_mismatch': ToolkitFailure.idConflict,
        'storage_limit_reached': ToolkitFailure.storageLimit,
        'document_limit_reached': ToolkitFailure.documentLimit,
        'too_many_pending_uploads': ToolkitFailure.tooManyPending,
        'rate_limited': ToolkitFailure.rateLimited,
        'upload_incomplete': ToolkitFailure.uploadIncomplete,
        'upload_rejected': ToolkitFailure.uploadRejected,
        'media_type_mismatch': ToolkitFailure.typeMismatch,
        'stale_version': ToolkitFailure.staleVersion,
        'object_missing': ToolkitFailure.objectMissing,
        'object_changed': ToolkitFailure.objectChanged,
        'deletion_in_progress': ToolkitFailure.deletionInProgress,
        'session_superseded': ToolkitFailure.sessionSuperseded,
        'session_check_unavailable': ToolkitFailure.unavailable,
        'document_not_ready': ToolkitFailure.unavailable,
      };
      cases.forEach((code, failure) {
        expect(R2ToolkitDocumentService.failureFor(409, code), failure,
            reason: code);
      });
      expect(R2ToolkitDocumentService.failureFor(401, null),
          ToolkitFailure.unauthorized);
      expect(R2ToolkitDocumentService.failureFor(429, null),
          ToolkitFailure.rateLimited);
      expect(R2ToolkitDocumentService.failureFor(503, null),
          ToolkitFailure.unavailable);
      expect(R2ToolkitDocumentService.failureFor(418, 'surprise'),
          ToolkitFailure.unknown);
    });

    test('retry and rejection classes are disjoint and sensible', () {
      for (final failure in ToolkitFailure.values) {
        expect(failure.isRetryable && failure.rejectsDocument, isFalse,
            reason: '$failure');
      }
      expect(ToolkitFailure.unavailable.isRetryable, isTrue);
      expect(ToolkitFailure.rateLimited.isRetryable, isTrue);
      expect(ToolkitFailure.tooLarge.rejectsDocument, isTrue);
      expect(ToolkitFailure.documentDeleted.isRetryable, isFalse);
      expect(ToolkitFailure.documentDeleted.rejectsDocument, isFalse);
    });

    test('a refusal carries its code, status, Retry-After and stale details',
        () async {
      final worker = _Worker((r) => _json(
            {
              'error': 'free text with profiles/secret/key',
              'code': 'stale_version',
              'currentTitle': 'Now',
              'currentVersion': 9
            },
            409,
            {'retry-after': '120'},
          ));
      final service = await _service(worker);
      final error = await _failureOf(() =>
          service.rename(documentId: doc1, title: 'x', expectedVersion: 1));
      expect(error.failure, ToolkitFailure.staleVersion);
      expect(error.statusCode, 409);
      expect(error.workerCode, 'stale_version');
      expect(error.retryAfter, const Duration(minutes: 2));
      expect(error.currentTitle, 'Now');
      expect(error.currentVersion, 9);
      expect(error.toString(), isNot(contains('secret')));
    });

    test('network trouble reads as unavailable or interrupted, without the URL',
        () async {
      final refused = R2ToolkitDocumentService(
        accountId: accountA,
        httpClient: MockClient((r) async =>
            throw const SocketException('refused https://secret.example/x')),
        supabaseClient: await _signedIn(accountA),
      );
      final error = await _failureOf(() => refused.listPage());
      expect(error.failure, ToolkitFailure.unavailable);
      expect(error.toString(), isNot(contains('secret')));

      final garbage = await _service(
          _Worker((r) => http.Response('<html>oops</html>', 200)));
      expect((await _failureOf(() => garbage.listPage())).failure,
          ToolkitFailure.invalidResponse);
      final serverError =
          await _service(_Worker((r) => http.Response('', 502)));
      expect((await _failureOf(() => serverError.listPage())).failure,
          ToolkitFailure.unavailable);
    });
  });

  group('transfers', () {
    test('upload streams the file with the PDF type and its exact length',
        () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = pdfBytes(5000);
      final file = File('${dir.path}/f.pdf')..writeAsBytesSync(bytes);
      final worker = _Worker((r) => http.Response('', 200));
      final service = await _service(worker);
      await service.uploadBytes(
          presignedUrl: _signedPut,
          file: file,
          contentType: ToolkitContentType.pdf);
      final request = worker.requests.single as http.Request;
      expect(request.method, 'PUT');
      expect(request.url.toString(), _signedPut);
      expect(request.headers['Content-Type'], 'application/pdf');
      expect(request.headers.containsKey('Authorization'), isFalse,
          reason: 'the signed URL is the credential');
      expect(request.bodyBytes, bytes);
    });

    test('a refused upload is "rejected" and a missing file is "unavailable"',
        () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.pdf')..writeAsBytesSync(pdfBytes());
      final refused = await _service(_Worker((r) => http.Response('', 403)));
      final error = await _failureOf(() => refused.uploadBytes(
          presignedUrl: _signedPut,
          file: file,
          contentType: ToolkitContentType.pdf));
      expect((error.failure, error.statusCode),
          (ToolkitFailure.uploadRejected, 403));
      expect(error.toString(), isNot(contains('Signature')));

      final missing = await _service(_Worker((r) => http.Response('', 200)));
      expect(
          (await _failureOf(() => missing.uploadBytes(
                  presignedUrl: _signedPut,
                  file: File('${dir.path}/none.pdf'),
                  contentType: ToolkitContentType.pdf)))
              .failure,
          ToolkitFailure.fileUnavailable);
    });

    test(
        'download streams into the target, refusing more than the allowed size',
        () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = pdfBytes(300);
      final service =
          await _service(_Worker((r) => http.Response.bytes(bytes, 200)));
      final target = File('${dir.path}/a.pdf.part');
      await service.downloadToFile(
          url: _signedGet, target: target, maxBytes: bytes.length);
      expect(await target.readAsBytes(), bytes);

      final tooBig = File('${dir.path}/b.pdf.part');
      final error = await _failureOf(() => service.downloadToFile(
          url: _signedGet, target: tooBig, maxBytes: bytes.length - 1));
      expect(error.failure, ToolkitFailure.integrityMismatch);
      expect(await tooBig.exists(), isFalse,
          reason: 'a partial file is removed');

      final gone = await _service(_Worker((r) => http.Response('', 403)));
      final denied = File('${dir.path}/c.pdf.part');
      expect(
          (await _failureOf(() => gone.downloadToFile(
                  url: _signedGet, target: denied, maxBytes: 99)))
              .failure,
          ToolkitFailure.unavailable);
      expect(await denied.exists(), isFalse);
    });

    test('a full disk is told apart from other file errors', () {
      expect(
          R2ToolkitDocumentService.isDiskFull(
              const FileSystemException('x', 'p', OSError('no space', 28))),
          isTrue);
      expect(
          R2ToolkitDocumentService.isDiskFull(
              const FileSystemException('x', 'p', OSError('disk full', 112))),
          isTrue);
      expect(
          R2ToolkitDocumentService.isDiskFull(
              const FileSystemException('x', 'p', OSError('denied', 13))),
          isFalse);
      expect(
          R2ToolkitDocumentService.isDiskFull(const FileSystemException('x')),
          isFalse);
    });
  });

  test('the Worker path never carries an object key from the client', () async {
    final worker = _Worker((r) => _json(
        {'status': 'pending', 'documentId': doc1, 'presignedUrl': _signedPut}));
    final service = await _service(worker);
    await service.authorize(
        documentId: doc1,
        type: ToolkitDocumentType.scanner,
        title: 't',
        contentLength: 5,
        contentType: ToolkitContentType.pdf,
        contentSha256: 'a' * 64,
        sourceCreatedAt: DateTime.utc(2026));
    for (final request in worker.requests) {
      expect(request.url.toString(), isNot(contains('profiles/')));
      expect((request as http.Request).body, isNot(contains('profiles/')));
      expect(request.body, isNot(contains('objectKey')));
    }
    // Typed bytes are only ever sent to the signed URL.
    expect(Uint8List(0), isEmpty);
  });

  group('C1.1 formats, integrity and stale documents', () {
    test(
        'authorize sends the format, the digest and the creation time, never a key',
        () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'documentId': doc1,
            'presignedUrl': _signedPut
          }));
      final service = await _service(worker);
      await service.authorize(
        documentId: doc1,
        type: ToolkitDocumentType.scanner,
        contentType: ToolkitContentType.jpeg,
        title: 'Page 1',
        contentLength: 4321,
        pageCount: 1,
        contentSha256: 'c' * 64,
        sourceCreatedAt: DateTime.utc(2026, 10, 19, 8),
      );
      final body = worker.bodyOf(worker.requests.single);
      expect(body, {
        'documentId': doc1,
        'documentType': 'scanner',
        'title': 'Page 1',
        'contentType': 'image/jpeg',
        'contentLength': 4321,
        'contentSha256': 'c' * 64,
        'sourceCreatedAt': '2026-10-19T08:00:00.000Z',
        'pageCount': 1,
      });
      expect(body.containsKey('acknowledgeStale'), isFalse,
          reason: 'never sent unless the user chose it');
    });

    test('an explicit acknowledgement is sent only when asked for', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'documentId': doc1,
            'presignedUrl': _signedPut
          }));
      await (await _service(worker)).authorize(
        documentId: doc1,
        type: ToolkitDocumentType.scanner,
        contentType: ToolkitContentType.png,
        title: 't',
        contentLength: 5,
        contentSha256: 'a' * 64,
        sourceCreatedAt: DateTime.utc(2026),
        acknowledgeStale: true,
      );
      expect(worker.bodyOf(worker.requests.single)['acknowledgeStale'], isTrue);
    });

    test('a format the tool may not store never reaches the network', () async {
      final worker = _Worker((r) => _json({}));
      final service = await _service(worker);
      for (final tool in [
        ToolkitDocumentType.combinePdfs,
        ToolkitDocumentType.imageToPdf,
        ToolkitDocumentType.signature
      ]) {
        final error = await _failureOf(() => service.authorize(
            documentId: doc1,
            type: tool,
            contentType: ToolkitContentType.png,
            title: 't',
            contentLength: 5,
            contentSha256: 'a' * 64,
            sourceCreatedAt: DateTime.utc(2026)));
        expect(error.failure, ToolkitFailure.unsupported, reason: '$tool');
      }
      expect(worker.requests, isEmpty);
    });

    test('the upload is labelled with the exact format of the document',
        () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.bin')..writeAsBytesSync(pngBytes());
      final worker = _Worker((r) => http.Response('', 200));
      await (await _service(worker)).uploadBytes(
          presignedUrl: _signedPut,
          file: file,
          contentType: ToolkitContentType.png);
      expect((worker.requests.single as http.Request).headers['Content-Type'],
          'image/png');
    });

    test('stale, integrity and deletion codes map to their own categories', () {
      expect(R2ToolkitDocumentService.failureFor(409, 'stale_document'),
          ToolkitFailure.staleDocument);
      expect(R2ToolkitDocumentService.failureFor(422, 'integrity_mismatch'),
          ToolkitFailure.integrityMismatch);
      expect(R2ToolkitDocumentService.failureFor(409, 'deletion_in_progress'),
          ToolkitFailure.deletionInProgress);
      expect(ToolkitFailure.staleDocument.rejectsDocument, isTrue);
      expect(ToolkitFailure.staleDocument.isRetryable, isFalse);
      expect(ToolkitFailure.deletionInProgress.rejectsDocument, isTrue);
    });

    test('confirm reports whether the Worker verified the digest', () async {
      for (final verified in [true, false]) {
        final service = await _service(_Worker((r) => _json(
            {'documentId': doc1, 'version': 3, 'sha256Verified': verified})));
        expect(
            (await service.confirm(documentId: doc1)).sha256Verified, verified);
      }
      final plain = await _service(
          _Worker((r) => _json({'documentId': doc1, 'version': 3})));
      expect((await plain.confirm(documentId: doc1)).sha256Verified, isFalse,
          reason: 'absent means not verified');
    });

    test('a ticket needs a known format and a digest, and carries the flag',
        () async {
      final good = {
        'documentId': doc1,
        'documentType': 'scanner',
        'contentType': 'image/png',
        'title': 'Page',
        'sizeBytes': 99,
        'pageCount': 1,
        'contentSha256': 'b' * 64,
        'sha256Verified': true,
        'version': 4,
        'url': _signedGet,
        'expiresInSeconds': 900,
      };
      final ticket = await (await _service(_Worker((r) => _json(good))))
          .downloadTicket(doc1);
      expect((ticket.contentType, ticket.sha256Verified),
          (ToolkitContentType.png, true));
      for (final change in <Map<String, Object?>>[
        {'contentType': 'image/gif'},
        {'contentType': null},
        {'documentType': 'signature'},
        {'contentSha256': null},
        {'sizeBytes': 70 * 1024 * 1024},
      ]) {
        final bad = _Worker((r) => _json({...good, ...change}));
        final error = await _failureOf(
            () async => (await _service(bad)).downloadTicket(doc1));
        expect(error.failure, ToolkitFailure.invalidResponse,
            reason: '$change');
      }
    });

    test('a list entry without a digest or a format is refused', () async {
      Map<String, Object?> entry() => {
            'documentId': doc1,
            'documentType': 'scanner',
            'contentType': 'image/jpeg',
            'title': 'Scan',
            'sizeBytes': 10,
            'pageCount': 1,
            'contentSha256': 'd' * 64,
            'sha256Verified': false,
            'sourceCreatedAt': '2026-10-19T08:00:00.000Z',
            'createdAt': '2026-10-19T08:00:01.000Z',
            'version': 2,
          };
      for (final key in ['contentSha256', 'contentType', 'sha256Verified']) {
        final service = await _service(_Worker((r) => _json({
              'documents': [entry()..[key] = null],
              'nextCursor': null
            })));
        final error = await _failureOf(() => service.listPage());
        expect(error.failure, ToolkitFailure.invalidResponse, reason: key);
      }
    });
  });

  group('write-once PUT (C2B)', () {
    Future<File> tempPdf() async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      return File('${dir.path}/f.pdf')..writeAsBytesSync(pdfBytes());
    }

    test('authorize carries the signed upload headers to the caller', () async {
      final worker = _Worker((r) => _json({
            'status': 'pending',
            'documentId': doc1,
            'presignedUrl': _signedPut,
            'uploadHeaders': {'If-None-Match': '*'},
            'expiresInSeconds': 300,
          }));
      final result = await (await _service(worker)).authorize(
        documentId: doc1,
        type: ToolkitDocumentType.scanner,
        contentType: ToolkitContentType.pdf,
        title: 'Scan',
        contentLength: 10,
        contentSha256: 'a' * 64,
        sourceCreatedAt: DateTime.utc(2026, 10, 19),
      );
      expect(result.uploadHeaders, {'If-None-Match': '*'});
    });

    test('no upload headers means none are sent; unknown ones are refused',
        () async {
      Future<Object?> authorizeWith(Object? headers) async {
        final worker = _Worker((r) => _json({
              'status': 'pending',
              'documentId': doc1,
              'presignedUrl': _signedPut,
              if (headers != null) 'uploadHeaders': headers,
            }));
        return (await _service(worker)).authorize(
          documentId: doc1,
          type: ToolkitDocumentType.scanner,
          contentType: ToolkitContentType.pdf,
          title: 'Scan',
          contentLength: 10,
          contentSha256: 'a' * 64,
          sourceCreatedAt: DateTime.utc(2026, 10, 19),
        );
      }

      expect(
          (await authorizeWith(null) as ToolkitUploadAuthorization)
              .uploadHeaders,
          isEmpty);
      for (final bad in <Object>[
        {'X-Other': '1'},
        {'If-None-Match': 'abc'},
        {'If-None-Match': '*', 'X-Other': '1'},
        ['If-None-Match'],
        'If-None-Match: *',
      ]) {
        final error = await _failureOf(() => authorizeWith(bad));
        expect(error.failure, ToolkitFailure.invalidResponse, reason: '$bad');
      }
    });

    test('the PUT sends exactly the signed header with the file type',
        () async {
      final file = await tempPdf();
      final worker = _Worker((r) => http.Response('', 200));
      await (await _service(worker)).uploadBytes(
        presignedUrl: _signedPut,
        file: file,
        contentType: ToolkitContentType.pdf,
        headers: const {'If-None-Match': '*'},
      );
      final request = worker.requests.single as http.Request;
      expect(request.headers['If-None-Match'], '*');
      expect(request.headers['Content-Type'], 'application/pdf');
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('412 on a write-once PUT means "already stored": the confirm decides',
        () async {
      final file = await tempPdf();
      final worker = _Worker((r) => http.Response('', 412));
      await (await _service(worker)).uploadBytes(
        presignedUrl: _signedPut,
        file: file,
        contentType: ToolkitContentType.pdf,
        headers: const {'If-None-Match': '*'},
      );
      expect(worker.requests, hasLength(1));
    });

    test('412 without the write-once header, 403 and 5xx are still failures',
        () async {
      final file = await tempPdf();
      for (final status in [403, 412, 500]) {
        final headers = status == 412
            ? const <String, String>{}
            : const {'If-None-Match': '*'};
        final service =
            await _service(_Worker((r) => http.Response('', status)));
        final error = await _failureOf(() => service.uploadBytes(
            presignedUrl: _signedPut,
            file: file,
            contentType: ToolkitContentType.pdf,
            headers: headers));
        expect((error.failure, error.statusCode),
            (ToolkitFailure.uploadRejected, status));
      }
    });

    test('a cleanup in progress is a retryable wait, with the Worker\'s delay',
        () async {
      final worker = _Worker((r) => _json(
          {
            'error': 'Upload cleanup is in progress',
            'code': 'document_cleanup_in_progress'
          },
          503,
          {'retry-after': '60'}));
      final error =
          await _failureOf(() async => (await _service(worker)).authorize(
                documentId: doc1,
                type: ToolkitDocumentType.scanner,
                contentType: ToolkitContentType.pdf,
                title: 'Scan',
                contentLength: 10,
                contentSha256: 'a' * 64,
                sourceCreatedAt: DateTime.utc(2026, 10, 19),
              ));
      expect(error.failure, ToolkitFailure.unavailable);
      expect(error.failure.isRetryable, isTrue);
      expect(error.retryAfter, const Duration(seconds: 60));
    });
  });

  group('environment (C3 staging build)', () {
    Future<R2ToolkitDocumentService> staging(_Worker worker,
            {String? key = 'gate-key'}) async =>
        R2ToolkitDocumentService(
          accountId: accountA,
          httpClient: worker.client,
          supabaseClient: await _signedIn(accountA),
          workerUrl: 'https://staging.example.test',
          stagingKey: key,
        );

    test('Toolkit routes use the Toolkit address and carry the gate key',
        () async {
      final worker = _Worker((r) => _json({
            'documents': <Object>[],
            'nextCursor': null,
          }));
      final service = await staging(worker);
      await service.listPage();
      final request = worker.requests.single as http.Request;
      expect(request.url.host, 'staging.example.test');
      expect(request.url.path, '/toolkit-documents');
      expect(request.headers['X-Broker-Wallet-Staging-Key'], 'gate-key');
      expect(request.headers['Authorization'], startsWith('Bearer '));
    });

    test('the signed storage URLs never receive the gate key', () async {
      final dir = await Directory.systemTemp.createTemp('toolkit_svc_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/f.pdf')..writeAsBytesSync(pdfBytes());
      final worker = _Worker((r) => http.Response('', 200));
      final service = await staging(worker);
      await service.uploadBytes(
          presignedUrl: _signedPut,
          file: file,
          contentType: ToolkitContentType.pdf);
      await service.downloadToFile(
          url: _signedGet, target: File('${dir.path}/out.pdf'), maxBytes: 1024);
      expect(worker.requests, hasLength(2));
      for (final request in worker.requests) {
        expect(
            request.headers.keys
                .map((k) => k.toLowerCase())
                .contains('x-broker-wallet-staging-key'),
            isFalse,
            reason: request.method);
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
    });

    test('no gate key is sent when none was given', () async {
      final worker = _Worker((r) => _json({
            'documents': <Object>[],
            'nextCursor': null,
          }));
      final service = await staging(worker, key: '');
      await service.listPage();
      expect(
          (worker.requests.single as http.Request)
              .headers
              .containsKey('X-Broker-Wallet-Staging-Key'),
          isFalse);
    });

    test('with no address nothing leaves the phone', () async {
      final worker = _Worker((r) => http.Response('{}', 200));
      final service = R2ToolkitDocumentService(
        accountId: accountA,
        httpClient: worker.client,
        supabaseClient: await _signedIn(accountA),
        workerUrl: '',
      );
      final error = await _failureOf(() => service.listPage());
      expect(error.failure, ToolkitFailure.notConfigured);
      expect(worker.requests, isEmpty);
    });

    test('a refusal without a code names the gate or the disabled route', () {
      expect(R2ToolkitDocumentService.failureFor(403, null),
          ToolkitFailure.forbidden);
      expect(R2ToolkitDocumentService.failureFor(404, null),
          ToolkitFailure.routeUnavailable);
      // A coded answer keeps its own meaning.
      expect(R2ToolkitDocumentService.failureFor(403, 'session_superseded'),
          ToolkitFailure.sessionSuperseded);
      expect(R2ToolkitDocumentService.failureFor(404, 'document_not_found'),
          ToolkitFailure.documentNotFound);
      // Neither is a fault of the document, so neither rejects it.
      expect(ToolkitFailure.forbidden.rejectsDocument, isFalse);
      expect(ToolkitFailure.routeUnavailable.rejectsDocument, isFalse);
    });
  });
}
