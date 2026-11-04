// P4.4 (tracker §7AO): which records are favorites — six lists, one per
// type — read whole, in keyset pages, on a PostgREST-faithful stand-in.
//
// FU-FAV-META-EMPTY: a metadata read that fails, comes back cut, or comes
// back empty under a session the database no longer accepts must never be
// answered as "this account has no favorites".
import 'dart:convert';

import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart'
    show CoreEntityListIncomplete, CoreEntityListProblem;
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _sessionA = '11111111-1111-4111-8111-111111111111';
const _sessionB = '22222222-2222-4222-8222-222222222222';

const _tables = {
  'offers': 'favorite_offers',
  'requests': 'favorite_requests',
  'owners': 'favorite_owners',
  'offices': 'favorite_offices',
  'brokers': 'favorite_brokers',
  'watchmen': 'favorite_watchmen',
};

class _Fav {
  _Fav(this.owner, this.target, DateTime at)
      : time = at.toUtc(),
        at = at.toUtc().toIso8601String().replaceFirst('Z', '+00:00');
  final String owner;
  final String target;
  final DateTime time;

  /// As PostgREST writes a timestamptz: microseconds and "+00:00".
  final String at;

  Map<String, dynamic> get json => {'target_id': target, 'added_at': at};
}

/// [n] favorites of [owner], newest first, every [tieEvery] sharing a time.
List<_Fav> favs(int n, {String owner = _uid, int tieEvery = 1, int seed = 0}) {
  final base = DateTime.utc(2026, 11, 1, 12).microsecondsSinceEpoch;
  return [
    for (var i = 0; i < n; i++)
      _Fav(
        owner,
        '${(seed + 3).toRadixString(16).padLeft(8, '0')}-0000-4000-8000-'
        '${((i * 7919) % 1000000).toString().padLeft(6, '0')}'
        '${i.toString().padLeft(6, '0')}',
        DateTime.fromMicrosecondsSinceEpoch(
            base - (i ~/ tieEvery) * 1234567 - 89,
            isUtc: true),
      ),
  ];
}

int _compare(_Fav a, _Fav b) {
  final byTime = b.time.compareTo(a.time);
  return byTime != 0 ? byTime : b.target.compareTo(a.target);
}

final _keyset = RegExp(
    r'^\(added_at\.lt\.(.+),and\(added_at\.eq\.(.+),target_id\.lt\.([0-9a-f-]+)\)\)$');

class _Server {
  _Server([Map<String, List<_Fav>> data = const {}]) {
    for (final table in _tables.values) {
      rows[table] = [...?data[table]]..sort(_compare);
    }
  }

  final Map<String, List<_Fav>> rows = {};
  final List<http.Request> requests = [];
  final Map<String, int> pages = {};
  int? maxRows;
  int inFlight = 0;
  int maxInFlight = 0;

  /// Hooks, each per table and per page number (1-based) of that table.
  void Function(String table, int page)? beforePage;
  bool Function(String table, int page)? failPage;
  bool Function(String table, int page)? networkFail;
  bool Function(String table, int page)? gateClosed;
  bool Function(String table, int page)? ignoreCursor;
  bool Function(String table, int page)? repeatPreviousRow;
  String? Function(String table, int page, String standard)? contentRange;

  List<http.Request> of(String table) => [
        for (final r in requests)
          if (r.url.pathSegments.last == table) r
      ];

  void add(String table, _Fav fav) => rows[table]!
    ..add(fav)
    ..sort(_compare);

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient(_handle),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<http.Response> _handle(http.Request request) async {
    final table = request.url.pathSegments.last;
    final q = request.url.queryParameters;
    final owner = q['owner_id'];
    List<_Fav> visible() => [
          for (final f in rows[table] ?? const <_Fav>[])
            if (owner == null || 'eq.${f.owner}' == owner) f
        ];
    if (request.method == 'HEAD') {
      requests.add(request);
      // The session gate hides rows from a count too.
      final closed = gateClosed?.call(table, (pages[table] ?? 0) + 1) ?? false;
      return http.Response('', 200,
          headers: {'content-range': '*/${closed ? 0 : visible().length}'},
          request: request);
    }
    final page = pages[table] = (pages[table] ?? 0) + 1;
    beforePage?.call(table, page);
    var found = visible();
    requests.add(request);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    inFlight--;
    if (networkFail?.call(table, page) ?? false) {
      pages[table] = page - 1; // the library's own retries ask again
      throw http.ClientException('connection reset', request.url);
    }
    if (failPage?.call(table, page) ?? false) {
      return http.Response('{"message":"unavailable"}', 500,
          headers: {'content-type': 'application/json'}, request: request);
    }
    final or = q['or'];
    if (or != null && !(ignoreCursor?.call(table, page) ?? false)) {
      final m = _keyset.firstMatch(or);
      if (m == null || m.group(1) != m.group(2)) {
        return http.Response('{"message":"bad keyset"}', 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final at = DateTime.parse(m.group(1)!);
      final id = m.group(3)!;
      found = [
        for (final f in found)
          if (f.time.isBefore(at) ||
              (f.time.isAtSameMomentAs(at) && f.target.compareTo(id) < 0))
            f
      ];
    }
    final total = found.length;
    var take = int.parse(q['limit'] ?? '$total');
    if (maxRows != null && maxRows! < take) take = maxRows!;
    final closed = gateClosed?.call(table, page) ?? false;
    var answer = closed ? <_Fav>[] : found.take(take).toList();
    if ((repeatPreviousRow?.call(table, page) ?? false) && or != null) {
      final m = _keyset.firstMatch(or)!;
      final previous = rows[table]!.firstWhere((f) => f.target == m.group(3));
      answer = [previous, ...answer.take(answer.length - 1)];
    }
    final counting = (request.headers['Prefer'] ?? '').contains('count=exact');
    final shown = closed ? 0 : total;
    final standard = answer.isEmpty
        ? '*/${counting ? shown : '*'}'
        : '0-${answer.length - 1}/${counting ? shown : '*'}';
    final range = contentRange == null
        ? standard
        : (contentRange!(table, page, standard) ?? standard);
    return http.Response(jsonEncode([for (final f in answer) f.json]),
        answer.length < shown ? 206 : 200,
        headers: {
          'content-type': 'application/json',
          if (range.isNotEmpty) 'content-range': range,
        },
        request: request);
  }
}

List<String> _ids(List<FavoriteMetadata> list) =>
    [for (final m in list) m.itemId];
List<String> _expected(List<_Fav> list) => [
      for (final f in [...list]..sort(_compare)) f.target
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? account;
  late String? session;
  late List<String?> confirmed;
  late Future<bool>? Function(String? session) confirm;

  FavoriteService serviceFor(_Server server) => FavoriteService(
        client: server.client,
        currentUserId: () => account,
        currentSessionId: () => session,
      );

  setUp(() {
    account = _uid;
    session = _sessionA;
    confirmed = [];
    confirm = (_) => Future<bool>.value(true);
    ListSessionCheck.debugOverride = (s) {
      confirmed.add(s);
      return confirm(s);
    };
  });
  tearDown(() => ListSessionCheck.debugOverride = null);

  Future<Object?> failureOf(Future<void> Function() read) async {
    try {
      await read();
    } catch (error) {
      return error;
    }
    return null;
  }

  group('page shape', () {
    test(
        'each first page: owner filter, added_at DESC then target_id DESC, '
        '500 rows, exact count', () async {
      final server = _Server({'favorite_offers': favs(3)});
      await serviceFor(server).getAllFavoritesWithMetadata();

      expect(server.requests, hasLength(6));
      for (final r in server.requests) {
        expect(r.method, 'GET');
        expect(r.url.queryParameters, {
          'select': 'target_id,added_at',
          'owner_id': 'eq.$_uid',
          'order': 'added_at.desc.nullslast,target_id.desc.nullslast',
          'limit': '500',
        });
        expect(r.headers['Prefer'], contains('count=exact'));
      }
      expect(server.requests.map((r) => r.url.pathSegments.last).toSet(),
          _tables.values.toSet());
    });

    test('the six types are asked for together, as in P3.4', () async {
      final server = _Server();
      await serviceFor(server).getAllFavoritesWithMetadata();
      expect(server.maxInFlight, 6);
    });

    test('the next page starts after the raw added_at text and target_id',
        () async {
      final rows = favs(501);
      final server = _Server({'favorite_offers': rows});
      await serviceFor(server).getAllFavoritesWithMetadata();

      final second = server.of('favorite_offers')[1];
      final last = ([...rows]..sort(_compare))[499];
      expect(second.url.queryParameters['or'],
          '(added_at.lt.${last.at},and(added_at.eq.${last.at},target_id.lt.${last.target}))');
      expect(second.url.query, contains('%2B00%3A00'),
          reason: 'the "+" of the offset must be encoded');
      expect(second.headers['Prefer'] ?? '', isNot(contains('count=')));
    });
  });

  group('complete lists', () {
    for (final (n, requests) in [
      (0, 1),
      (1, 1),
      (499, 1),
      (500, 1),
      (501, 2),
      (1000, 2),
      (1200, 3),
    ]) {
      test(
          '$n favorite Offers ⇒ $requests request(s), every one once, '
          'in order', () async {
        final rows = favs(n);
        final server = _Server({'favorite_offers': rows});
        final read = await serviceFor(server).getAllFavoritesWithMetadata();

        expect(server.of('favorite_offers'), hasLength(requests));
        expect(_ids(read['offers']!), _expected(rows));
        expect(read['offers']!.every((m) => m.type == 'offers'), isTrue);
        expect(read.keys.toSet(), _tables.keys.toSet());
      });
    }

    test('1,200 favorites from a server capped at 1,000 rows: all of them',
        () async {
      final rows = favs(1200);
      final server = _Server({'favorite_owners': rows})..maxRows = 1000;
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(_ids(read['owners']!), _expected(rows));
    });

    test('a server cap below the page size is not the end of the list',
        () async {
      final rows = favs(1200);
      final server = _Server({'favorite_brokers': rows})..maxRows = 300;
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(_ids(read['brokers']!), _expected(rows));
      expect(server.of('favorite_brokers'), hasLength(4));
    });

    test('many favorites added at the same moment, across page boundaries',
        () async {
      final rows = favs(1200, tieEvery: 400); // three distinct times
      final server = _Server({'favorite_watchmen': rows});
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      final ids = _ids(read['watchmen']!);
      expect(ids, _expected(rows));
      expect(ids.toSet(), hasLength(1200));
    });

    test('every type at once, each whole and only this account\'s', () async {
      final data = {
        for (final (i, table) in _tables.values.indexed)
          table: [
            ...favs([0, 7, 500, 501, 1200, 2][i], seed: i),
            ...favs(4, owner: _other, seed: 9),
          ],
      };
      final server = _Server(data);
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      for (final type in _tables.keys) {
        expect(
            _ids(read[type]!),
            _expected(
                data[_tables[type]]!.where((f) => f.owner == _uid).toList()),
            reason: type);
      }
      for (final r in server.requests) {
        expect(r.url.queryParameters['owner_id'], 'eq.$_uid');
      }
    });

    test('the time each was added is kept to the microsecond', () async {
      final rows = favs(2);
      final server = _Server({'favorite_offers': rows});
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(read['offers']!.first.addedAt, rows.first.time);
    });

    test('measurement: requests per read, before and after', () async {
      // Before (HEAD e9aa961): one request per type, whatever the size, and
      // a server cap of 1,000 cut the list silently.
      final sizes = {
        'favorite_offers': 0,
        'favorite_requests': 10,
        'favorite_owners': 500,
        'favorite_offices': 501,
        'favorite_brokers': 1200,
        'favorite_watchmen': 10000,
      };
      final server = _Server({
        for (final (i, e) in sizes.entries.indexed)
          e.key: favs(e.value, seed: i)
      })
        ..maxRows = 1000;
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      final perTable = {
        for (final t in sizes.keys) t: server.of(t).length,
      };
      expect(perTable, {
        'favorite_offers': 1,
        'favorite_requests': 1,
        'favorite_owners': 1,
        'favorite_offices': 2,
        'favorite_brokers': 3,
        'favorite_watchmen': 20,
      });
      for (final (i, type) in _tables.keys.indexed) {
        expect(read[type], hasLength(sizes.values.elementAt(i)), reason: type);
      }
      // ignore: avoid_print
      print('P4.4 measurement: requests per table $perTable '
          '(before: 1 each, cut at 1,000); confirm calls ${confirmed.length}');
    });
  });

  group('FU-FAV-META-EMPTY: a failed read is never "no favorites"', () {
    test('one type that cannot be read fails the whole read (no partial map)',
        () async {
      final server = _Server({'favorite_offers': favs(3)})
        ..failPage = (t, _) => t == 'favorite_owners';
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<sb.PostgrestException>());
    });

    test('a server error on page 2 fails the read', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..failPage = (t, p) => t == 'favorite_offers' && p == 2;
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<sb.PostgrestException>());
    });

    test(
        'a network failure on page 2 (after the library\'s own retries) '
        'fails the read', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..networkFail = (t, p) => t == 'favorite_offers' && p >= 2;
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isNotNull);
      expect(error, isNot(isA<CoreEntityListIncomplete>()));
    }, timeout: const Timeout(Duration(seconds: 40)));

    for (final range in ['', '0-2/*', '0-2/x']) {
      test('first page with Content-Range "$range" ⇒ missingCount', () async {
        final server = _Server({'favorite_offers': favs(3)})
          ..contentRange = (t, p, s) => t == 'favorite_offers' ? range : null;
        final error = await failureOf(
            () => serviceFor(server).getAllFavoritesWithMetadata());
        expect(error, isA<CoreEntityListIncomplete>());
        expect((error as CoreEntityListIncomplete).problem,
            CoreEntityListProblem.missingCount);
      });
    }

    test('nobody signed in ⇒ the read fails and nothing is asked', () async {
      account = null;
      final server = _Server();
      final error = await failureOf(() => serviceFor(server)
          .getAllFavoritesWithMetadata()
          .timeout(const Duration(seconds: 8)));
      expect(error, isNotNull, reason: 'was {}: "no favorites"');
      expect(server.requests, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test(
        'every list empty under a session the database does not confirm '
        '(replaced by another device) ⇒ not trusted', () async {
      confirm = (_) => Future<bool>.value(false);
      final server = _Server();
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
      expect(confirmed, [_sessionA], reason: 'asked once, for this session');
    });

    test('an empty list confirmed by the database is a real empty list',
        () async {
      final server = _Server({'favorite_offers': favs(2)});
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(read['requests'], isEmpty);
      expect(read['offers'], hasLength(2));
      expect(confirmed, [_sessionA]);
    });

    test('no application session to ask about ⇒ an empty list is taken as is',
        () async {
      confirm = (_) => null;
      final read = await serviceFor(_Server()).getAllFavoritesWithMetadata();
      expect(read.values.every((l) => l.isEmpty), isTrue);
    });

    test('the confirmation itself cannot be made ⇒ the read fails', () async {
      confirm = (_) => Future<bool>.error(StateError('offline'));
      final error = await failureOf(
          () => serviceFor(_Server()).getAllFavoritesWithMetadata());
      expect(error, isA<StateError>());
    });

    test('no list empty ⇒ nothing extra is asked', () async {
      final server = _Server({
        for (final t in _tables.values) t: favs(2),
      });
      await serviceFor(server).getAllFavoritesWithMetadata();
      expect(confirmed, isEmpty);
    });
  });

  group('account and session', () {
    test(
        'session replaced after page 1 (later pages come back empty) ⇒ '
        'ListSessionNotCurrent, not a short list', () async {
      confirm = (_) => Future<bool>.value(false);
      final server = _Server({'favorite_offers': favs(1200)})
        ..gateClosed = (t, p) => t == 'favorite_offers' && p >= 2;
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
      expect(confirmed, contains(_sessionA));
      // Recognised at once: no count again, no second read from the start.
      final offers = server.of('favorite_offers');
      expect(offers.where((r) => r.method == 'HEAD'), isEmpty);
      expect(offers, hasLength(2));
    });

    test('signed out after page 1 ⇒ no page 2', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..beforePage = (t, p) {
          if (t == 'favorite_offers' && p == 1) account = null;
        };
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
      expect(server.of('favorite_offers'), hasLength(1));
    });

    test('another account signed in after page 1 ⇒ no page 2', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..beforePage = (t, p) {
          if (t == 'favorite_offers' && p == 1) account = _other;
        };
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
      expect(server.of('favorite_offers'), hasLength(1));
    });

    test(
        'the same account signed in again (new session) after page 1 ⇒ '
        'no page 2', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..beforePage = (t, p) {
          if (t == 'favorite_offers' && p == 1) session = _sessionB;
        };
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
      expect(server.of('favorite_offers'), hasLength(1));
    });

    test(
        'reads cancelled while page 1 is in flight ⇒ that request completes, '
        'no further page, the read fails; a later read is whole', () async {
      final server = _Server({'favorite_offers': favs(1200)});
      final service = serviceFor(server);
      server.beforePage = (t, p) {
        if (t == 'favorite_offers' && p == 1) service.cancelMetadataReads();
      };
      final error = await failureOf(service.getAllFavoritesWithMetadata);
      expect(error, isNotNull);
      expect(error, isNot(isA<CoreEntityListIncomplete>()));
      expect(server.of('favorite_offers'), hasLength(1));
      expect(confirmed, isEmpty, reason: 'no session check either');

      server.beforePage = null;
      final read = await service.getAllFavoritesWithMetadata();
      expect(read['offers'], hasLength(1200));
    });

    test('a new session while every list came back empty ⇒ not trusted',
        () async {
      final server = _Server()
        ..beforePage = (t, p) {
          if (t == 'favorite_watchmen') session = _sessionB;
        };
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect(error, isA<ListSessionNotCurrent>());
    });
  });

  group('bounds and bad pages', () {
    test('more than 20,000 favorites of one type ⇒ tooLarge after one request',
        () async {
      final server = _Server({'favorite_offers': favs(20001)});
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect((error as CoreEntityListIncomplete).problem,
          CoreEntityListProblem.tooLarge);
      expect(server.of('favorite_offers'), hasLength(1));
    });

    test('exactly 20,000 ⇒ 40 pages, all of them', () async {
      final rows = favs(20000);
      final server = _Server({'favorite_offers': rows});
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(read['offers'], hasLength(20000));
      expect(server.of('favorite_offers'), hasLength(40));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a server cap of 100 and 4,500 favorites ⇒ tooLarge after 40 pages',
        () async {
      final server = _Server({'favorite_offers': favs(4500)})..maxRows = 100;
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect((error as CoreEntityListIncomplete).problem,
          CoreEntityListProblem.tooLarge);
      expect(server.of('favorite_offers'), hasLength(40));
    });

    test('a page that repeats the row before it ⇒ badPage', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..repeatPreviousRow = (t, p) => t == 'favorite_offers' && p == 2;
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect((error as CoreEntityListIncomplete).problem,
          CoreEntityListProblem.badPage);
    });

    test('a server that ignores the cursor ⇒ badPage', () async {
      final server = _Server({'favorite_offers': favs(1200)})
        ..ignoreCursor = (t, p) => t == 'favorite_offers';
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect((error as CoreEntityListIncomplete).problem,
          CoreEntityListProblem.badPage);
    });

    test(
        'a favorite removed before its page was read ⇒ counted again, '
        'and the rest is accepted', () async {
      final rows = favs(1200);
      final server = _Server({'favorite_offers': rows});
      final gone = ([...rows]..sort(_compare))[900];
      server.beforePage = (t, p) {
        if (t == 'favorite_offers' && p == 2) {
          server.rows[t]!.removeWhere((f) => f.target == gone.target);
        }
      };
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(read['offers'], hasLength(1199));
      expect(_ids(read['offers']!), isNot(contains(gone.target)));
      expect(confirmed, isNotEmpty);
      expect(confirmed, everyElement(_sessionA));
      final heads = [
        for (final r in server.of('favorite_offers'))
          if (r.method == 'HEAD') r
      ];
      expect(heads, hasLength(1));
      expect(heads.single.url.queryParameters['owner_id'], 'eq.$_uid');
    });

    test(
        'one added on top and one removed below while reading ⇒ read once '
        'more from the start', () async {
      final rows = favs(1200);
      final server = _Server({'favorite_offers': rows});
      final gone = ([...rows]..sort(_compare))[900];
      server.beforePage = (t, p) {
        if (t == 'favorite_offers' && p == 2) {
          server.rows[t]!.removeWhere((f) => f.target == gone.target);
          server.add(
              t,
              _Fav(_uid, 'ffffffff-0000-4000-8000-000000000001',
                  DateTime.utc(2027, 1, 1)));
        }
      };
      final read = await serviceFor(server).getAllFavoritesWithMetadata();
      expect(read['offers'], hasLength(1200));
      expect(
          _ids(read['offers']!).first, 'ffffffff-0000-4000-8000-000000000001');
    });

    test('a list that changes on every read ⇒ changedDuringRead', () async {
      final rows = favs(1200);
      final server = _Server({'favorite_offers': rows});
      var k = 0;
      server.beforePage = (t, p) {
        if (t == 'favorite_offers' && p >= 2) {
          final list = server.rows[t]!;
          list.removeAt(list.length - 1);
          server.add(
              t,
              _Fav(
                  _uid,
                  'ffffffff-0000-4000-8000-${(++k).toString().padLeft(12, '0')}',
                  DateTime.utc(2027, 1, 1).add(Duration(seconds: k))));
        }
      };
      final error = await failureOf(
          () => serviceFor(server).getAllFavoritesWithMetadata());
      expect((error as CoreEntityListIncomplete).problem,
          CoreEntityListProblem.changedDuringRead);
    });
  });
}
