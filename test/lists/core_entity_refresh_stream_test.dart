import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The shared refresh stream behind the six entity lists: it re-reads after
/// every core-entity mutation, and a failed re-read no longer ends it. The
/// list screens subscribe once, so a stream that ended on one transient
/// failure would leave a screen without updates until it was reopened.
///
/// It also listens for mutations before its first read — the earlier
/// `async*` version subscribed only after the first list was delivered and
/// dropped a mutation in that window — and a cancel stops it at once, where
/// the `async*` version stayed subscribed and read once more after its
/// screen had closed.

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

String _fakeJwt() {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _uid, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> _ownerRow(String id) => {
      'id': id,
      'owner_id': _uid,
      'name': 'Owner $id',
      'created_at': '2026-09-01T10:00:00Z',
      'updated_at': '2026-09-01T10:00:00Z',
    };

/// A signed-in client whose `owners` reads answer from [rows] as they were
/// when the read arrived, fail once when [failNextRead] is set, and wait for
/// [holdNextRead] (signalling [heldReadArrived]) when that is set.
class _Backend {
  List<Map<String, dynamic>> rows = [];
  bool failNextRead = false;
  Completer<void>? holdNextRead;
  final Completer<void> heldReadArrived = Completer<void>();
  int ownerReads = 0;

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/rest/v1/owners')) {
        ownerReads++;
        final answer = List<Map<String, dynamic>>.of(rows);
        final hold = holdNextRead;
        holdNextRead = null;
        if (hold != null) {
          heldReadArrived.complete();
          await hold.future;
        }
        if (failNextRead) {
          failNextRead = false;
          // 500, not 503: postgrest retries 503 and 520 by itself.
          return http.Response(
            jsonEncode({'message': 'temporarily unavailable'}),
            500,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(jsonEncode(answer), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() => client.auth.setInitialSession(jsonEncode({
        'access_token': _fakeJwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'refresh',
        'user': {
          'id': _uid,
          'aud': 'authenticated',
          'email': 'lists@example.test',
          'app_metadata': {'provider': 'email'},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-09-11T10:00:00Z',
        },
      }));
}

/// Records a stream's data and error events in order.
class _Recorder {
  _Recorder(Stream<List<String>> stream) {
    _subscription = stream.listen(
      _record,
      onError: (Object error, StackTrace _) => _record('error'),
    );
  }

  late final StreamSubscription<List<String>> _subscription;
  final List<Object> events = [];
  Completer<void>? _waiter;
  int _wanted = 0;

  void _record(Object event) {
    events.add(event);
    final waiter = _waiter;
    if (waiter != null && events.length >= _wanted) {
      _waiter = null;
      waiter.complete();
    }
  }

  Future<void> waitFor(int count) {
    if (events.length >= count) return Future<void>.value();
    _wanted = count;
    final waiter = _waiter = Completer<void>();
    return waiter.future.timeout(const Duration(seconds: 5));
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  late _Backend backend;
  late SupabaseCoreEntitiesService service;

  setUp(() async {
    backend = _Backend();
    await backend.signIn();
    service = SupabaseCoreEntitiesService(
      client: backend.client,
      offerMedia: R2OfferMediaUploadService(
        supabaseClient: backend.client,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
  });

  test('a failed re-read is reported and the next mutation reads again',
      () async {
    backend.rows = [_ownerRow('o1')];
    final recorder = _Recorder(service
        .getOwners()
        .map((owners) => [for (final owner in owners) owner.id ?? '']));
    addTearDown(recorder.cancel);

    await recorder.waitFor(1);
    expect(recorder.events, [
      ['o1']
    ]);

    backend.failNextRead = true;
    CoreEntityMutationNotifier.notify();
    await recorder.waitFor(2);
    expect(recorder.events.last, 'error');

    backend.rows = [_ownerRow('o1'), _ownerRow('o2')];
    CoreEntityMutationNotifier.notify();
    await recorder.waitFor(3);
    expect(recorder.events.last, ['o1', 'o2']);
    expect(backend.ownerReads, 3);
  });

  test('a mutation while the first read is in flight is not missed', () async {
    backend.rows = [_ownerRow('o1')];
    final hold = backend.holdNextRead = Completer<void>();
    final recorder = _Recorder(service
        .getOwners()
        .map((owners) => [for (final owner in owners) owner.id ?? '']));
    addTearDown(recorder.cancel);
    await backend.heldReadArrived.future;

    // A save lands after the first read reached the server.
    backend.rows = [_ownerRow('o1'), _ownerRow('o2')];
    CoreEntityMutationNotifier.notify();
    hold.complete();

    await recorder.waitFor(2);
    expect(recorder.events, [
      ['o1'],
      ['o1', 'o2'],
    ]);
    expect(backend.ownerReads, 2);
  });

  test('cancelling stops listening at once; no read after the screen closed',
      () async {
    backend.rows = [_ownerRow('o1')];
    final recorder = _Recorder(service
        .getOwners()
        .map((owners) => [for (final owner in owners) owner.id ?? '']));
    await recorder.waitFor(1);
    // Let the stream settle into waiting for the next mutation.
    await pumpEventQueue();

    // The async* version never completed this cancel: it stayed suspended
    // waiting for a mutation. The bound only turns that into a failure.
    await recorder.cancel().timeout(const Duration(seconds: 5));

    CoreEntityMutationNotifier.notify();
    await pumpEventQueue();
    expect(backend.ownerReads, 1);
    expect(recorder.events, [
      ['o1']
    ]);
  });
}
