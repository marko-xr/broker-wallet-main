// Q-2b (D-Q3): a Quotation delete counts only once the server has confirmed
// it. PostgREST answers an update that changed no row with success — for a
// missing id, another account's row or a session the database no longer
// accepts alike — so before Q-2b such a "delete" succeeded silently. Now the
// update must return the row it changed; when it returns none, one read tells
// this account's already-deleted row (a success) from anything else (a
// failure, and the usual session check), as the six entity lists do since
// P3.1a. The hosted policy allows that read: `quotations_select_own` is
// `owner_id = auth.uid()` with no `deleted_at` filter (plus the session gate).
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _q = '00000000-0000-4000-8000-000000000001';
const _pdf = 'bbbbbbbb-bbbb-4bbb-8bbb-000000000001';

String _sessionJson(String uid) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': uid,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'session_id': 'a1a1a1a1-0000-4000-8000-000000000001',
      })}.sig';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'refresh',
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'email': '$uid@example.test',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    },
  });
}

/// PostgREST for the delete: the soft-delete update and the one read that
/// tells an already-deleted row apart.
class _Server {
  List<Object?> changed = const [];
  List<Object?> alreadyDeleted = const [];
  (int, Map<String, Object?>)? patchFailure;
  final List<http.Request> requests = [];

  late final MockClient client = MockClient((request) async {
    if (!request.url.path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, request: request);
    }
    requests.add(request);
    final failure = patchFailure;
    if (request.method == 'PATCH' && failure != null) {
      return http.Response(jsonEncode(failure.$2), failure.$1,
          headers: {'content-type': 'application/json'}, request: request);
    }
    final body = request.method == 'PATCH' ? changed : alreadyDeleted;
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'}, request: request);
  });
}

Future<(_Server, SupabaseQuotationService)> _start() async {
  final server = _Server();
  final client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: server.client,
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(_sessionJson(_alice));
  return (server, SupabaseQuotationService(client: client));
}

void main() {
  var sessionChecks = 0;
  setUp(() {
    sessionChecks = 0;
    ListSessionCheck.debugOverride = (_) {
      sessionChecks++;
      return Future<bool>.value(true);
    };
  });
  tearDown(() => ListSessionCheck.debugOverride = null);

  group('the soft delete', () {
    test('a changed row returned is the confirmation: one request', () async {
      final (server, remote) = await _start();
      server.changed = [
        {'id': _q}
      ];
      await remote.softDelete(_q);
      final patch = server.requests.single;
      expect(patch.method, 'PATCH');
      expect(patch.url.path, '/rest/v1/quotations');
      expect(patch.url.queryParameters,
          {'id': 'eq.$_q', 'deleted_at': 'is.null', 'select': 'id'});
      expect((jsonDecode(patch.body) as Map).keys, ['deleted_at']);
      expect(sessionChecks, 0);
    });

    test('no row changed, but this account\'s row is already deleted ⇒ done',
        () async {
      final (server, remote) = await _start();
      server.alreadyDeleted = [
        {'id': _q}
      ];
      await remote.softDelete(_q);
      expect(server.requests.map((r) => r.method), ['PATCH', 'GET']);
      final read = server.requests.last;
      expect(read.url.path, '/rest/v1/quotations');
      expect(read.url.queryParameters,
          {'select': 'id', 'id': 'eq.$_q', 'deleted_at': 'not.is.null'});
      expect(sessionChecks, 0);
    });

    test('no row changed and none deleted ⇒ refused, the session is checked',
        () async {
      final (server, remote) = await _start();
      await expectLater(
        remote.softDelete(_q),
        throwsA(isA<QuotationException>()
            .having((e) => e.failure, 'failure', QuotationFailure.notFound)),
      );
      expect(server.requests.map((r) => r.method), ['PATCH', 'GET']);
      await pumpEventQueue();
      expect(sessionChecks, 1, reason: 'a replaced session is signed out');
    });

    test('a refused update is still the permission failure', () async {
      final (server, remote) = await _start();
      server.patchFailure = (403, {'code': '42501', 'message': 'denied'});
      await expectLater(
        remote.softDelete(_q),
        throwsA(isA<QuotationException>().having(
            (e) => e.failure, 'failure', QuotationFailure.permissionDenied)),
      );
      expect(server.requests, hasLength(1));
    });
  });

  group('the Quotation service delete', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('q2b_delete_');
    });
    tearDown(() => dir.delete(recursive: true));

    File pdfCopy() => File('${dir.path}${Platform.pathSeparator}'
        'quotation_${_q}_$_pdf.pdf');

    Future<(QuotationService, _Server, List<Object?>)> service() async {
      final (server, remote) = await _start();
      await pdfCopy().writeAsBytes([1, 2, 3]);
      final signals = <Object?>[];
      final sub = CoreEntityMutationNotifier.changes.listen(signals.add);
      addTearDown(sub.cancel);
      return (
        QuotationService(
          remote: remote,
          pdfCache: QuotationPdfCache(directory: () async => dir),
          httpClient: MockClient((_) async => http.Response('', 404)),
        ),
        server,
        signals,
      );
    }

    test('unconfirmed ⇒ it fails, nothing refreshes, the PDF copy stays',
        () async {
      final (quotations, _, signals) = await service();
      await expectLater(
          quotations.deleteQuotation(_q), throwsA(isA<QuotationException>()));
      expect(signals, isEmpty);
      expect(pdfCopy().existsSync(), isTrue);
    });

    test('confirmed ⇒ the PDF copy goes and the list refreshes once', () async {
      final (quotations, server, signals) = await service();
      server.changed = [
        {'id': _q}
      ];
      await quotations.deleteQuotation(_q);
      expect(signals, hasLength(1));
      expect(pdfCopy().existsSync(), isFalse);
    });
  });
}
