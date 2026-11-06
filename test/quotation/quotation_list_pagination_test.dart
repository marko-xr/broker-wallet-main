// Q-1a: the Quotations list is read whole, in pages, as the six entity lists
// are since P4 (tracker §7AJ/§7AK): 500 rows a page, newest first
// (created_at, then id), each page after the last row of the one before, the
// first with an exact count, returned only once the pages add up. Before
// Q-1a it was one request with no limit, cut short at the hosted `max_rows`
// (1,000) without a word.
//
// The server is an emulation of PostgREST for `quotations`: owner and
// deleted filters, order, limit, the keyset filter, its own row cap and the
// exact count.
import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _s1 = 'a1a1a1a1-0000-4000-8000-000000000001';
const _s2 = 'a2a2a2a2-0000-4000-8000-000000000002';

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

/// A `timestamptz` as PostgreSQL prints it in UTC.
String _pgTime(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  var fraction = '';
  final micros = u.millisecond * 1000 + u.microsecond;
  if (micros != 0) {
    fraction = '.${micros.toString().padLeft(6, '0')}'
        .replaceFirst(RegExp(r'0+$'), '');
  }
  return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:'
      '${two(u.minute)}:${two(u.second)}$fraction+00:00';
}

final _base = DateTime.utc(2026, 1, 1);

/// Quotation [n], one second newer than n-1 unless [sameTime] is given.
Map<String, dynamic> _row(int n,
        {String owner = _alice, DateTime? sameTime, String? deletedAt}) =>
    {
      'id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
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
      'version': 1 + n % 3,
      'created_at': _pgTime(sameTime ?? _base.add(Duration(seconds: n))),
      'updated_at': _pgTime(_base.add(Duration(seconds: n))),
      'deleted_at': deletedAt,
    };

class _Server {
  final List<Map<String, dynamic>> rows = [];
  int? maxRows;
  FutureOr<void> Function(int page)? beforePage;
  String? Function(int page)? contentRange;
  int? networkFailFrom;
  bool Function(int page)? gateClosed;
  int? repeatLastRowOnPage;

  final List<http.Request> listReads = [];
  final List<http.Request> heads = [];
  int bodyBytes = 0;
  int _page = 0;

  static final _keyset = RegExp(
      r'^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([0-9a-f-]+)\)\)$');

  static final Map<String, DateTime> _times = {};
  static DateTime _time(Object? text) =>
      _times.putIfAbsent(text as String, () => DateTime.parse(text));

  static int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTime = _time(b['created_at']).compareTo(_time(a['created_at']));
    if (byTime != 0) return byTime;
    return (b['id'] as String).compareTo(a['id'] as String);
  }

  List<Map<String, dynamic>> _visible(Map<String, String> q) {
    final owner = q['owner_id'];
    return [
      for (final row in rows)
        if ((owner == null || 'eq.${row['owner_id']}' == owner) &&
            (q['deleted_at'] != 'is.null' || row['deleted_at'] == null))
          row,
    ];
  }

  late final MockClient client = MockClient((request) async {
    final url = request.url;
    if (url.path != '/rest/v1/quotations') {
      return http.Response('{}', 200, request: request);
    }
    final q = url.queryParameters;
    if (request.method == 'HEAD') {
      heads.add(request);
      return http.Response('', 200,
          headers: {'content-range': '*/${_visible(q).length}'},
          request: request);
    }
    listReads.add(request);
    final page = ++_page;
    await beforePage?.call(page);
    final failFrom = networkFailFrom;
    if (failFrom != null && page >= failFrom) {
      throw http.ClientException('connection reset', url);
    }
    var found = _visible(q)..sort(compare);
    final keyset = q['or'];
    if (keyset != null) {
      final m = _keyset.firstMatch(keyset);
      if (m == null || m.group(1) != m.group(2)) {
        return http.Response('{"message":"bad keyset"}', 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
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
    final total = found.length;
    var take = int.parse(q['limit'] ?? '$total');
    final cap = maxRows;
    if (cap != null && cap < take) take = cap;
    final closed = gateClosed?.call(page) ?? false;
    var answer = closed ? <Map<String, dynamic>>[] : found.take(take).toList();
    if (repeatLastRowOnPage == page && keyset != null) {
      final previous = rows
          .firstWhere((r) => r['id'] == _keyset.firstMatch(keyset)!.group(3));
      answer = [previous, ...answer.take(answer.length - 1)];
    }
    final counting = (request.headers['Prefer'] ?? '').contains('count=exact');
    final shownTotal = closed ? 0 : total;
    final standard = answer.isEmpty
        ? '*/${counting ? shownTotal : '*'}'
        : '0-${answer.length - 1}/${counting ? shownTotal : '*'}';
    final range = contentRange?.call(page) ?? standard;
    final body = jsonEncode(answer);
    bodyBytes += utf8.encode(body).length;
    return http.Response(body, answer.length < shownTotal ? 206 : 200,
        headers: {
          'content-type': 'application/json',
          if (range.isNotEmpty) 'content-range': range,
        },
        request: request);
  });
}

class _Harness {
  _Harness(this.server, this.client, this.service);

  final _Server server;
  final sb.SupabaseClient client;
  final SupabaseQuotationService service;

  static Future<_Harness> start([String uid = _alice]) async {
    final server = _Server();
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(_sessionJson(uid, _s1));
    return _Harness(server, client, SupabaseQuotationService(client: client));
  }

  void add(int count, {int from = 1}) {
    for (var n = from; n < from + count; n++) {
      server.rows.add(_row(n));
    }
  }
}

List<String> _ids(List<QuotationModel> list) => [for (final q in list) q.id!];

List<String> _expectedIds(_Server s) {
  final rows = [
    for (final r in s.rows)
      if (r['owner_id'] == _alice && r['deleted_at'] == null) r
  ]..sort(_Server.compare);
  return [for (final r in rows) r['id'] as String];
}

Future<void> _until(bool Function() done, {int tries = 400}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

void main() {
  tearDown(() => ListSessionCheck.debugOverride = null);

  group('the whole list, in pages', () {
    for (final (count, requests) in [
      (0, 1),
      (1, 1),
      (499, 1),
      (500, 1),
      (501, 2),
      (1000, 2),
      (1200, 3),
      (10000, 20),
    ]) {
      test('$count quotations ⇒ all of them, in order, $requests request(s)',
          () async {
        final h = await _Harness.start();
        h.add(count);
        h.server.maxRows = 1000; // the hosted cap (§7AL)

        final list = await h.service.listQuotations();

        expect(_ids(list), _expectedIds(h.server));
        expect(h.server.listReads, hasLength(requests));
        for (final r in h.server.listReads) {
          final q = r.url.queryParameters;
          expect(q['owner_id'], 'eq.$_alice');
          expect(q['deleted_at'], 'is.null');
          expect(q['order'], startsWith('created_at.desc'));
          expect(q['order'], contains('id.desc'));
          expect(q['limit'], '500');
          expect(q['select'], isNot(contains('quotation_downpayments')));
        }
        expect(h.server.listReads.first.headers['Prefer'],
            contains('count=exact'));
      });
    }

    test('the same time on many rows, across a page edge: each once', () async {
      final h = await _Harness.start();
      final t = DateTime.utc(2026, 5, 5, 12);
      for (var n = 1; n <= 1100; n++) {
        h.server.rows.add(_row(n, sameTime: n >= 450 && n <= 560 ? t : null));
      }
      final list = await h.service.listQuotations();
      expect(_ids(list), _expectedIds(h.server));
      expect(_ids(list).toSet(), hasLength(1100));
    });

    test('deleted and other accounts\' rows are never listed', () async {
      final h = await _Harness.start();
      h.add(10);
      h.server.rows
        ..add(_row(11, deletedAt: _pgTime(_base)))
        ..add(_row(12, owner: _bob));
      final list = await h.service.listQuotations();
      expect(list, hasLength(10));
    });

    test('the header fields map exactly as before (cards, PDF, totals)',
        () async {
      final h = await _Harness.start();
      h.add(2);
      final list = await h.service.listQuotations();
      final newest = list.first;
      expect(newest.propertyTitle, 'Villa 2');
      expect(newest.totalAmount, 120002.5);
      expect(newest.numberOfInstallments, 4);
      expect(newest.currencyCode, 'AED');
      expect(newest.officeName, 'Realtig');
      expect(newest.hasPdf, isTrue);
      expect(list.last.hasPdf, isFalse);
      expect(newest.version, 1 + 2 % 3);
    });
  });

  group('never a partial or false list', () {
    Future<void> expectFails(_Harness h, [QuotationFailure? failure]) async {
      await expectLater(
        h.service.listQuotations(),
        throwsA(isA<QuotationException>()
            .having((e) => e.failure, 'failure', failure ?? anything)),
      );
    }

    test('more than 20,000 ⇒ refused after one request', () async {
      final h = await _Harness.start();
      h.add(20001);
      await expectFails(h);
      expect(h.server.listReads, hasLength(1));
    });

    test('a page that repeats a row ⇒ refused', () async {
      final h = await _Harness.start();
      h.add(1200);
      h.server.repeatLastRowOnPage = 2;
      await expectFails(h);
    });

    for (final range in ['', '0-499/*', 'garbage']) {
      test('a first page without a usable count ("$range") ⇒ refused',
          () async {
        final h = await _Harness.start();
        h.add(600);
        h.server.contentRange = (page) => page == 1 ? range : null;
        await expectFails(h);
      });
    }

    test('page 2 fails on the network ⇒ a network failure, nothing returned',
        () async {
      final h = await _Harness.start();
      h.add(1200);
      h.server.networkFailFrom = 2;
      await expectFails(h, QuotationFailure.network);
    });

    test('a row deleted between pages ⇒ recounted, the rest returned',
        () async {
      final h = await _Harness.start();
      h.add(1200);
      h.server.beforePage = (page) {
        if (page == 2)
          h.server.rows.removeWhere((r) => r['property_title'] == 'Villa 3');
      };
      final list = await h.service.listQuotations();
      expect(list, hasLength(1199));
      expect(h.server.heads, hasLength(1));
    });

    test('an empty list is taken only once the session is confirmed', () async {
      for (final (answer, accepted) in [
        (Future<bool>.value(true), true),
        (Future<bool>.value(false), false),
        (null, true), // no app session: no gate, as the lists do
      ]) {
        var asked = 0;
        ListSessionCheck.debugOverride = (_) {
          asked++;
          return answer;
        };
        final h = await _Harness.start();
        if (accepted) {
          expect(await h.service.listQuotations(), isEmpty);
        } else {
          await expectFails(h);
        }
        expect(asked, 1);
      }
    });

    test('a list with rows needs no session check', () async {
      var asked = 0;
      ListSessionCheck.debugOverride = (_) {
        asked++;
        return Future<bool>.value(true);
      };
      final h = await _Harness.start();
      h.add(3);
      await h.service.listQuotations();
      expect(asked, 0);
    });

    for (final (label, change) in [
      (
        'another account signs in',
        (sb.SupabaseClient c) =>
            c.auth.setInitialSession(_sessionJson(_bob, _s2))
      ),
      (
        'the same account signs in again (a new session)',
        (sb.SupabaseClient c) =>
            c.auth.setInitialSession(_sessionJson(_alice, _s2))
      ),
    ]) {
      test('$label after page 1 ⇒ no page 2, nothing returned', () async {
        final h = await _Harness.start();
        h.add(1200);
        h.server.beforePage = (page) async {
          if (page == 1) {
            // Answer page 1, then switch before the next request.
            scheduleMicrotask(() => change(h.client));
          }
        };
        await expectFails(h);
        expect(h.server.listReads, hasLength(1));
      });
    }

    test('a superseded session (its pages come back empty) ⇒ refused',
        () async {
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(false);
      final h = await _Harness.start();
      h.add(1200);
      h.server.gateClosed = (page) => page >= 2;
      await expectFails(h);
    });
  });

  group('the screen stream', () {
    test('a closed screen reads no further page', () async {
      final h = await _Harness.start();
      h.add(1200);
      final gate = Completer<void>();
      h.server.beforePage = (page) => page == 1 ? gate.future : null;
      final sub = h.service.watchQuotations().listen((_) {}, onError: (_) {});
      await _until(() => h.server.listReads.isNotEmpty);
      await sub.cancel();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.server.listReads, hasLength(1));
    });

    test('a failed re-read is an error event; the stream goes on', () async {
      final h = await _Harness.start();
      h.add(600);
      final lists = <int>[];
      final errors = <Object>[];
      final sub = h.service
          .watchQuotations()
          .listen((l) => lists.add(l.length), onError: errors.add);
      await _until(() => lists.isNotEmpty);
      h.server.networkFailFrom = h.server.listReads.length + 2;
      CoreEntityMutationNotifier.notify();
      // The client retries a failed GET a few times, with a back-off.
      await _until(() => errors.isNotEmpty, tries: 4000);
      h.server.networkFailFrom = null;
      h.add(1, from: 601);
      CoreEntityMutationNotifier.notify();
      await _until(() => lists.length == 2);
      expect(lists, [600, 601]);
      await sub.cancel();
    });
  });

  test('measurements: requests and body bytes per read', () async {
    final lines = <String>[];
    for (final count in [0, 100, 1000, 1200, 5000, 10000]) {
      final h = await _Harness.start();
      h.add(count);
      h.server.maxRows = 1000;
      final watch = Stopwatch()..start();
      final list = await h.service.listQuotations();
      watch.stop();
      lines.add('quotations $count rows: ${list.length} returned, '
          '${h.server.listReads.length} request(s), '
          '${h.server.bodyBytes} body bytes, ${watch.elapsedMilliseconds} ms');
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}
