// Q-1b: the Quotations list re-reads itself only after a change that can
// alter it. Before Q-1b every core-entity mutation in the process (a Request,
// Offer, Owner, Office, Broker or Watchman save, edit or delete) re-read the
// whole paged Quotations list, though none of them can change a Quotation
// row: the list reads only `quotations` columns (no embedded resource), no
// foreign key or trigger links a Quotation to those six tables, and
// `office_name` is text stored on the Quotation itself.
//
// Every signal here comes from the real emitters (the six entity deletes,
// the Quotation save and delete) on one emulated PostgREST server, and every
// request the list sends is counted.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _s1 = 'a1a1a1a1-0000-4000-8000-000000000001';
const _s2 = 'a2a2a2a2-0000-4000-8000-000000000002';
const _other = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

String _sessionJson(String uid, String sessionId) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': uid,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'session_id': sessionId,
      })}.sig';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'refresh-$sessionId',
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

String _pgTime(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:'
      '${two(u.minute)}:${two(u.second)}+00:00';
}

String _qid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> _row(int n, {String owner = _alice}) => {
      'id': _qid(n),
      'owner_id': owner,
      'property_title': 'Villa $n',
      'property_type': 'Villa',
      'display_date': '01/10/2026',
      'total_amount': 120000.5 + n,
      'number_of_installments': 4,
      'office_name': 'Realtig',
      'currency_code': 'AED',
      'office_logo_media_id': null,
      'pdf_media_id': n.isEven
          ? 'bbbbbbbb-bbbb-4bbb-8bbb-${n.toString().padLeft(12, '0')}'
          : null,
      'version': 1,
      'created_at': _pgTime(DateTime.utc(2026).add(Duration(seconds: n))),
      'updated_at': _pgTime(DateTime.utc(2026).add(Duration(seconds: n))),
      'deleted_at': null,
    };

/// PostgREST for `quotations` (owner and deleted filters, order, limit,
/// keyset, row cap, exact count), the Quotation save RPC and soft deletes on
/// all seven tables.
class _Server {
  final List<Map<String, dynamic>> rows = [];
  int? maxRows = 1000; // the hosted cap (§7AL)
  bool failLists = false;
  bool gateClosed = false;
  Future<void> Function()? holdList;

  /// The Quotation save RPC: what it does to the rows.
  void Function()? onSave;

  final List<http.Request> listReads = [];
  final List<http.Request> requests = [];
  final List<String> deletedTables = [];
  int bodyBytes = 0;
  int inFlight = 0;

  static final _keyset = RegExp(
      r'^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([0-9a-f-]+)\)\)$');

  static final Map<String, DateTime> _times = {};
  static DateTime _time(Object? text) =>
      _times.putIfAbsent(text as String, () => DateTime.parse(text));

  static int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final t = _time(b['created_at']).compareTo(_time(a['created_at']));
    if (t != 0) return t;
    return (b['id'] as String).compareTo(a['id'] as String);
  }

  List<Map<String, dynamic>> _visible(Map<String, String> q) => [
        for (final row in rows)
          if ((q['owner_id'] == null ||
                  'eq.${row['owner_id']}' == q['owner_id']) &&
              (q['deleted_at'] != 'is.null' || row['deleted_at'] == null))
            row,
      ];

  static http.Response _json(Object body, http.Request request,
          {int status = 200, Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json', ...headers},
          request: request);

  late final MockClient client = MockClient((request) async {
    if (!request.url.path.startsWith('/rest/v1/')) {
      return http.Response('{}', 200, request: request);
    }
    requests.add(request);
    inFlight++;
    try {
      return await _answer(request);
    } finally {
      inFlight--;
    }
  });

  Future<http.Response> _answer(http.Request request) async {
    final url = request.url;
    final table = url.pathSegments.last;
    final q = url.queryParameters;
    if (url.path == '/rest/v1/rpc/save_quotation') {
      onSave?.call();
      return _json([
        {'quotation_id': _other, 'resulting_version': 2, 'outcome': 'ok'}
      ], request);
    }
    if (request.method == 'PATCH') {
      final id = q['id']!.substring(3);
      deletedTables.add(table);
      if (table == 'quotations') {
        for (final row in rows) {
          if (row['id'] == id)
            row['deleted_at'] = _pgTime(DateTime.utc(2026, 2));
        }
      }
      return _json([
        {'id': id}
      ], request);
    }
    if (table != 'quotations') return _json(const [], request);
    if (request.method == 'HEAD') {
      return http.Response('', 200,
          headers: {'content-range': '*/${_visible(q).length}'},
          request: request);
    }
    listReads.add(request);
    await holdList?.call();
    if (failLists) {
      return _json({'message': 'boom', 'code': 'XX000'}, request, status: 400);
    }
    var found = _visible(q)..sort(compare);
    final keyset = q['or'];
    if (keyset != null) {
      final m = _keyset.firstMatch(keyset)!;
      final cursorTime = DateTime.parse(m.group(1)!);
      final cursorId = m.group(3)!;
      found = [
        for (final row in found)
          if (_time(row['created_at']).isBefore(cursorTime) ||
              (_time(row['created_at']).isAtSameMomentAs(cursorTime) &&
                  (row['id'] as String).compareTo(cursorId) < 0))
            row,
      ];
    }
    final total = gateClosed ? 0 : found.length;
    var take = int.parse(q['limit'] ?? '$total');
    if (maxRows != null && maxRows! < take) take = maxRows!;
    final answer = gateClosed ? const [] : found.take(take).toList();
    final counting = (request.headers['Prefer'] ?? '').contains('count=exact');
    final range = answer.isEmpty
        ? '*/${counting ? total : '*'}'
        : '0-${answer.length - 1}/${counting ? total : '*'}';
    final body = jsonEncode(answer);
    bodyBytes += utf8.encode(body).length;
    return http.Response(body, answer.length < total ? 206 : 200,
        headers: {'content-type': 'application/json', 'content-range': range},
        request: request);
  }
}

class _Harness {
  _Harness._(this.server, this.client, this.dir);

  final _Server server;
  final sb.SupabaseClient client;
  final Directory dir;

  late final SupabaseQuotationService remote =
      SupabaseQuotationService(client: client);
  late final QuotationService quotations = QuotationService(
    remote: remote,
    pdfCache: QuotationPdfCache(directory: () async => dir),
    httpClient: MockClient((_) async => http.Response('', 404)),
  );
  late final SupabaseCoreEntitiesService entities = SupabaseCoreEntitiesService(
    client: client,
    offerMedia: R2OfferMediaUploadService(
      supabaseClient: client,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
  );

  int failuresShown = 0;
  late final QuotationListViewModel vm = QuotationListViewModel(
    quotationService: quotations,
    toast: (_, __) {},
  )..onRefreshFailed = () {
      failuresShown++;
      return true;
    };

  final List<List<QuotationModel>> lists = [];
  final List<Object> errors = [];
  StreamSubscription<List<QuotationModel>>? _sub;

  static Future<_Harness> start({int rows = 0, String uid = _alice}) async {
    final server = _Server();
    for (var n = 1; n <= rows; n++) {
      server.rows.add(_row(n));
    }
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(_sessionJson(uid, _s1));
    final dir = await Directory.systemTemp.createTemp('q1b_');
    addTearDown(() => dir.delete(recursive: true));
    final h = _Harness._(server, client, dir);
    addTearDown(() => h._sub?.cancel());
    return h;
  }

  /// The screen opens the list (its ViewModel's stream) and the first read
  /// finishes.
  Future<void> open() async {
    listen(vm.quotationsStream!);
    await settle(server);
  }

  void listen(Stream<List<QuotationModel>> stream) {
    _sub = stream.listen(lists.add, onError: errors.add);
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// One of each of the six other kinds deleted, as the six list screens do.
  Future<void> deleteOneOfEachOtherKind({bool settleEach = false}) async {
    for (final delete in [
      entities.deleteRequest,
      entities.deleteOffer,
      entities.deleteOwner,
      entities.deleteOffice,
      entities.deleteBroker,
      entities.deleteWatchman,
    ]) {
      await delete(_other);
      if (settleEach) await settle(server);
    }
  }

  int get reads => server.listReads.length;
}

/// Waits until no request is in flight and none has started for a while.
Future<void> settle(_Server s) async {
  var quiet = 0;
  var seen = -1;
  for (var i = 0; i < 4000 && quiet < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final now = s.requests.length;
    if (s.inFlight == 0 && now == seen) {
      quiet++;
    } else {
      quiet = 0;
      seen = now;
    }
  }
}

QuotationModel _form(String title) => QuotationModel(
      id: _other,
      userId: _alice,
      propertyTitle: title,
      officeName: 'Realtig',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

String _source(String path) => File(path).readAsStringSync();

void main() {
  setUp(() => ListSessionCheck.debugOverride = (_) => Future<bool>.value(true));
  tearDown(() => ListSessionCheck.debugOverride = null);

  group('what the list depends on', () {
    test('the list reads only Quotation columns, from quotations alone',
        () async {
      expect(QuotationSupabaseMapper.listColumns, isNot(contains('(')),
          reason: 'no embedded resource: nothing read from another table');
      final h = await _Harness.start(rows: 1200);
      await h.open();
      expect(h.server.requests.map((r) => r.url.path).toSet(),
          {'/rest/v1/quotations'});
      expect(h.lists.single, hasLength(1200));
    });

    test('every emitter in lib/ says what it changed', () {
      final bare = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file
            .readAsStringSync()
            .contains('CoreEntityMutationNotifier.notify()')) {
          bare.add(file.path);
        }
      }
      expect(bare, isEmpty);
    });

    test('each of the six entity saves and edits names its own kind', () {
      final text =
          _source('lib/src/services/supabase_core_entities_service.dart');
      final next = RegExp(r'\n  (Future|Stream)<');
      for (final (entity, kind) in [
        ('Request', 'request'),
        ('Offer', 'offer'),
        ('Owner', 'owner'),
        ('Office', 'office'),
        ('Broker', 'broker'),
        ('Watchman', 'watchman'),
      ]) {
        for (final verb in ['save', 'update']) {
          final start =
              text.indexOf(RegExp('Future<[A-Za-z]+> $verb$entity\\('));
          expect(start, isNonNegative, reason: '$verb$entity');
          final end = text.indexOf(next, start + 1);
          final body = text.substring(start, end);
          expect(
              RegExp(r'CoreEntityMutationNotifier\.notify\(([^)]*)\)')
                  .allMatches(body)
                  .map((m) => m.group(1))
                  .toList(),
              ['CoreEntityKind.$kind'],
              reason: '$verb$entity signals once, as a $kind change');
        }
      }
    });

    test('each of the six entity deletes names its own kind', () {
      final text =
          _source('lib/src/services/supabase_core_entities_service.dart');
      for (final (table, kind) in [
        ('requests', 'request'),
        ('offers', 'offer'),
        ('owners', 'owner'),
        ('offices', 'office'),
        ('brokers', 'broker'),
        ('watchmen', 'watchman'),
      ]) {
        expect(
            RegExp("_softDeleteAndNotify\\(\\s*'$table',\\s*id,\\s*CoreEntityKind\\.$kind\\)")
                .hasMatch(text),
            isTrue,
            reason: table);
      }
      expect(text, contains('CoreEntityMutationNotifier.notify(kind);'));
    });

    test('every Quotation mutation signal is a Quotation change', () {
      final text = _source(
          'lib/src/views/Screens/home/quotation/services/quotation_service.dart');
      final calls = RegExp(r'CoreEntityMutationNotifier\.notify\(([^)]*)\)')
          .allMatches(text)
          .map((m) => m.group(1))
          .toList();
      expect(calls, ['CoreEntityKind.quotation', 'CoreEntityKind.quotation'],
          reason: 'the single signal and the batched one');
    });

    test('the list listens only to changes that may touch Quotations', () {
      final text = _source(
          'lib/src/views/Screens/home/quotation/services/supabase_quotation_service.dart');
      expect(
          text,
          contains(
              'CoreEntityMutationNotifier.changesTo(CoreEntityKind.quotation)'));
      expect(
          text, isNot(contains('CoreEntityMutationNotifier.changes.listen')));
    });
  });

  group('request counts', () {
    test('six other kinds changing ⇒ no Quotations read at all', () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      expect(h.reads, 3, reason: '1,200 rows: three pages to open');
      await h.deleteOneOfEachOtherKind();
      await settle(h.server);
      expect(h.server.deletedTables,
          ['requests', 'offers', 'owners', 'offices', 'brokers', 'watchmen']);
      expect(h.reads, 3, reason: 'none of the six can change a Quotation');
      expect(h.lists, hasLength(1));
      expect(h.errors, isEmpty);
    });

    test('a Quotation created, edited and deleted ⇒ one whole re-read each',
        () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();

      h.server.onSave = () => h.server.rows.add(_row(1201));
      await h.quotations
          .saveQuotation(_form('Villa 1201'), quotationId: _other);
      await settle(h.server);
      expect(h.reads, 6);
      expect(h.lists.last, hasLength(1201));
      expect(h.lists.last.first.propertyTitle, 'Villa 1201');

      h.server.onSave = () {
        h.server.rows.last['property_title'] = 'Villa 1201 edited';
        h.server.rows.last['total_amount'] = 99.75;
      };
      await h.quotations.saveQuotation(_form('Villa 1201 edited'),
          quotationId: _other, expectedVersion: 1);
      await settle(h.server);
      expect(h.reads, 9);
      expect(h.lists.last.first.propertyTitle, 'Villa 1201 edited');
      expect(h.lists.last.first.totalAmount, 99.75);

      await h.quotations.deleteQuotation(_qid(1201));
      await settle(h.server);
      expect(h.reads, 12);
      expect(h.lists.last, hasLength(1200));
      expect(h.lists.last.map((q) => q.id), isNot(contains(_qid(1201))));
      expect(h.lists, hasLength(4));
    });

    test('one batched Quotation save (aggregate + more) ⇒ one re-read',
        () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      await h.quotations.batchMutations(() async {
        await h.quotations.saveQuotation(_form('A'), quotationId: _other);
        await h.quotations
            .saveQuotation(_form('B'), quotationId: _other, expectedVersion: 2);
      });
      await settle(h.server);
      expect(h.reads, 2);
    });

    test('a signal that does not say what changed still re-reads', () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      CoreEntityMutationNotifier.notify();
      await settle(h.server);
      expect(h.reads, 2, reason: 'unknown ⇒ treated as possibly a Quotation');
    });

    test('many signals during one read ⇒ exactly one more read', () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      final gate = Completer<void>();
      h.server.holdList = () => gate.future;
      await h.quotations.deleteQuotation(_qid(1)); // read 2 starts, held
      await h.quotations.deleteQuotation(_qid(2));
      await h.quotations.deleteQuotation(_qid(3));
      await h.deleteOneOfEachOtherKind();
      h.server.holdList = null;
      gate.complete();
      await settle(h.server);
      expect(h.reads, 3 + 3 + 3,
          reason: 'the held read, then one read for everything after it');
      expect(h.lists.last, hasLength(1197));
    });

    test('only other kinds during a read ⇒ no extra read', () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      final gate = Completer<void>();
      h.server.holdList = () => gate.future;
      await h.quotations.deleteQuotation(_qid(1)); // read 2 starts, held
      await h.deleteOneOfEachOtherKind();
      h.server.holdList = null;
      gate.complete();
      await settle(h.server);
      expect(h.reads, 3 + 3);
      expect(h.lists.last, hasLength(1199));
    });

    test('the explicit refresh still reads the whole list', () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      await h.close();
      h.server.rows.add(_row(1201));
      await h.vm.refreshQuotations();
      h.listen(h.vm.quotationsStream!);
      await settle(h.server);
      expect(h.reads, 6);
      expect(h.lists.last, hasLength(1201));
    });

    test('measurements: list requests before/after per scenario', () async {
      final lines = <String>[];
      for (final count in [0, 3, 1200, 10000]) {
        final h = await _Harness.start(rows: count);
        await h.open();
        final open = h.reads;
        final openBytes = h.server.bodyBytes;
        // Six separate edits, as a person makes them: each one settles.
        await h.deleteOneOfEachOtherKind(settleEach: true);
        final afterSix = h.reads - open;
        final sixBytes = h.server.bodyBytes - openBytes;
        h.server.rows.add(_row(count + 1));
        await h.quotations.deleteQuotation(_qid(count + 1));
        await settle(h.server);
        final afterQuotation = h.reads - open - afterSix;
        lines.add('quotations $count rows: open $open request(s); '
            'six other-kind deletes ⇒ $afterSix list request(s), '
            '$sixBytes body bytes; one Quotation delete ⇒ '
            '$afterQuotation list request(s)');
      }
      // ignore: avoid_print
      print(lines.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('failures', () {
    test('a failed re-read keeps the list and is said once per run', () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      h.server.failLists = true;
      await h.quotations.deleteQuotation(_qid(1));
      await settle(h.server);
      expect(h.failuresShown, 1);
      await h.quotations.deleteQuotation(_qid(2));
      await settle(h.server);
      expect(h.failuresShown, 1, reason: 'not again in the same run');
      final reads = h.reads;
      await h.deleteOneOfEachOtherKind();
      await settle(h.server);
      expect(h.reads, reads, reason: 'other kinds cause no read to fail');
      expect(h.failuresShown, 1);
      expect(h.errors, isEmpty, reason: 'the shown list is never replaced');
      expect(h.lists, hasLength(1));

      h.server.failLists = false;
      CoreEntityMutationNotifier.notify();
      await settle(h.server);
      expect(h.lists.last, hasLength(1));
      h.server.failLists = true;
      await h.quotations.deleteQuotation(_qid(3));
      await settle(h.server);
      expect(h.failuresShown, 2, reason: 'a success re-arms it');
    });

    test('a failed first read is still the error state', () async {
      final h = await _Harness.start(rows: 3);
      h.server.failLists = true;
      await h.open();
      expect(h.lists, isEmpty);
      expect(h.errors, hasLength(1));
      expect(h.failuresShown, 0);
    });

    test('a superseded session ⇒ refused, the shown list kept', () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      var asked = 0;
      ListSessionCheck.debugOverride = (_) {
        asked++;
        return Future<bool>.value(false);
      };
      h.server.gateClosed = true;
      await h.deleteOneOfEachOtherKind();
      await settle(h.server);
      expect(asked, 0, reason: 'no read, so no session check');
      await h.quotations.deleteQuotation(_qid(1));
      await settle(h.server);
      expect(asked, 1);
      expect(h.failuresShown, 1);
      expect(h.lists, hasLength(1));
      expect(h.lists.single, hasLength(3), reason: 'never a false empty list');
    });
  });

  group('account and session', () {
    test('another account signs in: only its own list, on a Quotation change',
        () async {
      final h = await _Harness.start(rows: 2);
      h.server.rows.add(_row(50, owner: _bob));
      await h.open();
      expect(h.lists.single, hasLength(2));
      await h.client.auth.setInitialSession(_sessionJson(_bob, _s2));
      await h.deleteOneOfEachOtherKind();
      await settle(h.server);
      expect(h.reads, 1);
      await h.quotations.deleteQuotation(_other);
      await settle(h.server);
      expect(h.reads, 2);
      expect(
          h.server.listReads.last.url.queryParameters['owner_id'], 'eq.$_bob');
      expect(h.lists.last.map((q) => q.userId), [_bob]);
    });

    test('an account switch during a paged read ⇒ the old result is dropped',
        () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      final gate = Completer<void>();
      h.server.holdList = () => gate.future;
      await h.quotations.deleteQuotation(_qid(1)); // page 1 of re-read, held
      await h.client.auth.setInitialSession(_sessionJson(_bob, _s2));
      h.server.holdList = null;
      gate.complete();
      await settle(h.server);
      expect(h.reads, 4, reason: 'no page 2 for the old account');
      expect(h.lists, hasLength(1), reason: 'nothing of the old account late');
    });

    test('sign-out, then the same account again: no read while signed out',
        () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      await h.client.auth.signOut();
      final requests = h.server.requests.length;
      CoreEntityMutationNotifier.notify(); // an unknown change while out
      await settle(h.server);
      expect(h.server.requests.length, requests,
          reason: 'no session ⇒ no request at all');
      expect(h.lists, hasLength(1));
      expect(h.errors, isEmpty);

      await h.client.auth.setInitialSession(_sessionJson(_alice, _s2));
      await h.deleteOneOfEachOtherKind();
      await settle(h.server);
      expect(h.reads, 1);
      await h.quotations.deleteQuotation(_qid(1));
      await settle(h.server);
      expect(h.reads, 2);
      expect(h.lists.last, hasLength(2));
    });
  });

  group('the screen closes', () {
    test('after it closes nothing reads, whatever changes', () async {
      final h = await _Harness.start(rows: 3);
      await h.open();
      await h.close();
      await h.deleteOneOfEachOtherKind();
      await h.quotations.deleteQuotation(_qid(1));
      CoreEntityMutationNotifier.notify();
      await settle(h.server);
      expect(h.reads, 1);
    });

    test('closing during a re-read stops it before the next page', () async {
      final h = await _Harness.start(rows: 1200);
      await h.open();
      final gate = Completer<void>();
      h.server.holdList = () => gate.future;
      await h.quotations.deleteQuotation(_qid(1));
      await h.close();
      h.server.holdList = null;
      gate.complete();
      await settle(h.server);
      expect(h.reads, 4);
      expect(h.lists, hasLength(1));
    });
  });

  test('the card fields after a re-read map exactly as before', () async {
    final h = await _Harness.start(rows: 3);
    await h.open();
    h.server.rows.add(_row(4));
    await h.quotations.deleteQuotation(_qid(2));
    await settle(h.server);
    final newest = h.lists.last.first;
    expect(newest.propertyTitle, 'Villa 4');
    expect(newest.totalAmount, 120004.5);
    expect(newest.numberOfInstallments, 4);
    expect(newest.currencyCode, 'AED');
    expect(newest.officeName, 'Realtig');
    expect(newest.hasPdf, isTrue);
    expect(h.lists.last.last.hasPdf, isFalse);
    expect(newest.version, 1);
  });
}
