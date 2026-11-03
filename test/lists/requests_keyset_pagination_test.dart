// P4.1 (tracker §7AJ): the Requests list is read in pages of 500, newest
// first (created_at, then id), each page after the last row of the one
// before. The first page also asks for the exact number of rows; the list is
// delivered only once every page has arrived and adds up. A list that cannot
// be shown whole is never delivered at all.
//
// The server here is an emulation of PostgREST: it applies the owner and
// deleted filters, the order, the limit, the keyset filter, its own row cap
// (`max_rows`) and the exact count the way PostgREST does.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _s1 = 'a1a1a1a1-0000-4000-8000-000000000001';
const _s2 = 'a2a2a2a2-0000-4000-8000-000000000002';

String _sessionJson(String sessionId) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': _alice,
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
      'id': _alice,
      'aud': 'authenticated',
      'email': 'alice@example.test',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-11T10:00:00Z',
    },
  });
}

/// A timestamp as PostgreSQL prints a `timestamptz` in UTC: microseconds
/// with trailing zeros left out, and the `+00:00` offset.
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

String _id(int n) => '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _base = DateTime.utc(2026, 1, 1);

/// A Requests row with every column the list reads.
Map<String, dynamic> _row(
  int n, {
  String owner = _alice,
  DateTime? createdAt,
  String? deletedAt,
}) =>
    {
      'id': _id(n),
      'owner_id': owner,
      'request_type': 'rent',
      'selected_city': 'Dubai',
      'location_text': 'Dubai Marina, Tower $n',
      'phone_number': '50000${n.toString().padLeft(4, '0')}',
      'country_code': '+971',
      'min_price': 1000 + n,
      'max_price': 2000 + n,
      'square_footage': 900,
      'notes': 'Request number $n',
      'property_type': 'residential',
      'specific_property_type': 'Apartment',
      'rooms': 2,
      'bathrooms': 2,
      'status': 'active',
      'created_at':
          _pgTime(createdAt ?? _base.add(Duration(microseconds: n * 1001))),
      'updated_at': _pgTime(_base),
      'deleted_at': deletedAt,
      'request_areas': [
        {'area': 'Marina', 'ordinal': 0},
      ],
    };

/// PostgREST, emulated for the `requests` table.
class _Server {
  final List<Map<String, dynamic>> rows = [];

  /// The server's own cap on rows per answer (`max_rows`); null for none.
  int? maxRows;

  /// Called before each list page is answered, with its number (1-based).
  FutureOr<void> Function(int page)? beforePage;

  /// Overrides the Content-Range header of a page; '' removes it.
  String? Function(int page, String standard)? contentRange;

  /// A page answered with HTTP 500.
  int? failPage;

  /// From this page on, every request fails on the network (the client's
  /// own retries included).
  int? networkFailFrom;

  /// Pages answered with no rows, as the session gate answers a replaced
  /// session.
  bool Function(int page)? gateClosed;

  /// Ignores the keyset filter (a server that does not advance).
  bool ignoreCursor = false;

  /// Answers this page with the previous page's last row first.
  int? repeatLastRowOnPage;

  final List<http.Request> listReads = [];
  final List<http.Request> countReads = [];
  int bodyBytes = 0;
  int _page = 0;

  static final _keyset = RegExp(
      r'^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([0-9a-f-]+)\)\)$');

  void addRows(int count, {int from = 1}) {
    for (var n = from; n < from + count; n++) {
      rows.add(_row(n));
    }
  }

  /// Parsed once per distinct text, so 20,000 rows sort quickly.
  static final Map<String, DateTime> _times = {};
  static DateTime _time(Object? text) =>
      _times.putIfAbsent(text as String, () => DateTime.parse(text));

  static int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
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
    if (!url.path.startsWith('/rest/v1/requests')) {
      return http.Response('{}', 200, request: request);
    }
    final q = url.queryParameters;
    if (request.method == 'HEAD') {
      countReads.add(request);
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
    if (failPage == page) {
      return http.Response('{"message":"unavailable"}', 500,
          headers: {'content-type': 'application/json'}, request: request);
    }

    var found = _visible(q)..sort(_compare);
    final keyset = q['or'];
    if (keyset != null && !ignoreCursor) {
      final m = _keyset.firstMatch(keyset);
      if (m == null || m.group(1) != m.group(2)) {
        return http.Response('{"message":"bad keyset: $keyset"}', 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
      final DateTime cursorTime;
      try {
        cursorTime = DateTime.parse(m.group(1)!);
      } on FormatException {
        return http.Response('{"message":"bad time: ${m.group(1)}"}', 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
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
    var answer = found.take(take).toList();
    if (gateClosed?.call(page) ?? false) answer = [];
    final repeat = repeatLastRowOnPage;
    if (repeat == page && keyset != null) {
      final m = _keyset.firstMatch(keyset)!;
      final previous = rows.firstWhere((r) => r['id'] == m.group(3));
      answer = [previous, ...answer.take(answer.length - 1)];
    }

    final counting = (request.headers['Prefer'] ?? '').contains('count=exact');
    final shownTotal = (gateClosed?.call(page) ?? false) ? 0 : total;
    final standard = answer.isEmpty
        ? '*/${counting ? shownTotal : '*'}'
        : '0-${answer.length - 1}/${counting ? shownTotal : '*'}';
    final range = contentRange == null
        ? standard
        : (contentRange!(page, standard) ?? standard);
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

List<String> _ids(List<RequestModel> list) => [for (final r in list) r.id!];

/// The ids of rows newest first (created_at, then id), as the list shows them.
List<String> _expectedOrder(Iterable<Map<String, dynamic>> rows) =>
    [for (final row in rows.toList()..sort(_Server._compare)) row['id']];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late sb.SupabaseClient client;
  late SupabaseCoreEntitiesService core;

  Future<void> signIn(String session) =>
      client.auth.setInitialSession(_sessionJson(session));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ListSessionCheck.debugOverride = null;
    server = _Server();
    client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await signIn(_s1);
    core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: R2OfferMediaUploadService(
        supabaseClient: client,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
  });

  tearDown(() => ListSessionCheck.debugOverride = null);

  Future<List<RequestModel>> read() => core.getRequests().first;

  Matcher incomplete(CoreEntityListProblem problem) =>
      throwsA(isA<CoreEntityListIncomplete>()
          .having((e) => e.problem, 'problem', problem));

  group('pages', () {
    test(
        'the first page asks for 500 rows, newest first with the id as tie '
        'breaker, with the exact count and the same filters', () async {
      server.addRows(3);
      await read();
      final r = server.listReads.single;
      expect(r.url.queryParameters, {
        'select': isNotEmpty,
        'owner_id': 'eq.$_alice',
        'deleted_at': 'is.null',
        'order': 'created_at.desc.nullslast,id.desc.nullslast',
        'limit': '500',
      });
      expect(r.headers['Prefer'], contains('count=exact'));
    });

    for (final (count, pages) in [
      (0, 1),
      (1, 1),
      (499, 1),
      (500, 1),
      (501, 2),
      (1000, 2),
      (1200, 3),
    ]) {
      test('$count rows: $pages request(s), every row once, in order',
          () async {
        server.addRows(count);
        final list = await read();
        expect(server.listReads, hasLength(pages));
        expect(server.countReads, isEmpty);
        expect(_ids(list), _expectedOrder(server.rows));
      });
    }

    test(
        'each later page starts after the last row of the page before, by '
        'its exact time and id', () async {
      server.addRows(501);
      await read();
      final last = server.rows
          .firstWhere((r) => r['id'] == _expectedOrder(server.rows)[499]);
      final second = server.listReads[1].url.queryParameters;
      expect(second['or'],
          '(created_at.lt.${last['created_at']},and(created_at.eq.${last['created_at']},id.lt.${last['id']}))');
      expect(second['limit'], '500');
      expect(second['owner_id'], 'eq.$_alice');
      expect(second['deleted_at'], 'is.null');
      expect(server.listReads[1].headers['Prefer'] ?? '',
          isNot(contains('count=')),
          reason: 'only the first page counts');
      // The `+` of the time's offset is sent escaped, so the server does not
      // read it as a space.
      expect(server.listReads[1].url.query, contains('%2B00%3A00'));
    });

    test('1,200 rows from a server capped at 1,000: all 1,200', () async {
      server
        ..maxRows = 1000
        ..addRows(1200);
      final list = await read();
      expect(list, hasLength(1200));
      expect(server.listReads, hasLength(3));
    });

    test(
        'a server cap smaller than the page (300): short pages are not taken '
        'as the end; all 1,200 rows', () async {
      server
        ..maxRows = 300
        ..addRows(1200);
      final list = await read();
      expect(_ids(list), _expectedOrder(server.rows));
      expect(server.listReads, hasLength(4));
    });

    test(
        'rows created at the same instant are ordered by id and none is lost '
        'or repeated across pages', () async {
      final same = [
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 2),
        DateTime.utc(2026, 3, 3),
      ];
      for (var n = 1; n <= 1200; n++) {
        server.rows.add(_row(n, createdAt: same[n % 3]));
      }
      final list = await read();
      expect(_ids(list), _expectedOrder(server.rows));
      expect(_ids(list).toSet(), hasLength(1200));
    });

    test('other accounts\' and deleted rows are not part of the list',
        () async {
      server.addRows(600);
      server.rows
        ..add(_row(9001, owner: _bob))
        ..add(_row(9002, deletedAt: '2026-11-01T00:00:00+00:00'));
      final list = await read();
      expect(list, hasLength(600));
      expect(_ids(list), isNot(contains(_id(9001))));
      expect(_ids(list), isNot(contains(_id(9002))));
    });
  });

  group('the safety cap', () {
    test('more than 20,000 Requests: one request, then a completeness error',
        () async {
      server.addRows(20001);
      await expectLater(read(), incomplete(CoreEntityListProblem.tooLarge));
      expect(server.listReads, hasLength(1));
    });

    test('exactly 20,000 Requests are read whole (40 pages)', () async {
      server.addRows(20000);
      final list = await read();
      expect(list, hasLength(20000));
      expect(server.listReads, hasLength(40));
    });

    test(
        'a server cap so small that more than 40 pages are needed: a '
        'completeness error after 40, not the first rows', () async {
      server
        ..maxRows = 100
        ..addRows(4500);
      await expectLater(read(), incomplete(CoreEntityListProblem.tooLarge));
      expect(server.listReads, hasLength(40));
    });
  });

  group('failures', () {
    test('a server error on page 2 fails the whole read', () async {
      server
        ..addRows(1200)
        ..failPage = 2;
      await expectLater(read(), throwsA(isA<sb.PostgrestException>()));
      expect(server.listReads, hasLength(2), reason: 'page 3 never asked');
    });

    test(
        'a network failure on page 3 fails the whole read as a network '
        'failure (the list retries as before)', () async {
      server
        ..addRows(1200)
        ..networkFailFrom = 3;
      Object? error;
      try {
        await read();
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(isRetryableListError(error!), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    for (final (name, header) in [
      ('missing', ''),
      ('unknown (*)', '0-2/*'),
      ('malformed', '0-2/many'),
    ]) {
      test('a $name exact count: a completeness error, not a network one',
          () async {
        server
          ..addRows(3)
          ..contentRange = (page, _) => page == 1 ? header : null;
        Object? error;
        try {
          await read();
        } catch (e) {
          error = e;
        }
        expect(error, isA<CoreEntityListIncomplete>());
        expect((error! as CoreEntityListIncomplete).problem,
            CoreEntityListProblem.missingCount);
        expect(isRetryableListError(error), isFalse);
      });
    }

    test('a count smaller than the rows on the first page is refused',
        () async {
      server
        ..addRows(10)
        ..contentRange = (page, _) => page == 1 ? '0-9/5' : null;
      await expectLater(read(), incomplete(CoreEntityListProblem.badPage));
    });

    test('a row repeated across pages is refused', () async {
      server
        ..addRows(800)
        ..repeatLastRowOnPage = 2;
      await expectLater(read(), incomplete(CoreEntityListProblem.badPage));
    });

    test('a server that does not advance is refused at page 2', () async {
      server
        ..addRows(800)
        ..ignoreCursor = true;
      await expectLater(read(), incomplete(CoreEntityListProblem.badPage));
      expect(server.listReads, hasLength(2));
    });
  });

  group('sessions', () {
    test(
        'a session replaced during paging (later pages empty): not a short '
        'list — ListSessionNotCurrent once the database says so', () async {
      server
        ..addRows(1200)
        ..gateClosed = (page) => page >= 2;
      final sessions = <String?>[];
      ListSessionCheck.debugOverride = (session) {
        sessions.add(session);
        return Future<bool>.value(false);
      };
      await expectLater(read(), throwsA(isA<ListSessionNotCurrent>()));
      expect(sessions, [_s1], reason: 'asked about the read\'s own session');
      expect(server.countReads, isEmpty);
    });

    test(
        'signing out and back in to the same account during paging: no '
        'further page, and nothing delivered', () async {
      server
        ..addRows(1200)
        ..beforePage = (page) async {
          if (page == 2) await signIn(_s2);
        };
      await expectLater(read(), throwsA(isA<ListSessionNotCurrent>()));
      expect(server.listReads, hasLength(2));
    });

    test('signing out during paging: no further page', () async {
      server
        ..addRows(1200)
        ..beforePage = (page) async {
          if (page == 1) await client.auth.signOut();
        };
      await expectLater(read(), throwsA(isA<ListSessionNotCurrent>()));
      expect(server.listReads, hasLength(1));
    });

    test('closing the screen during a page: no further page is asked',
        () async {
      server.addRows(1200);
      final gate = Completer<void>();
      server.beforePage = (page) => page == 1 ? gate.future : null;
      final subscription = core.getRequests().listen((_) {}, onError: (_) {});
      await _until(() => server.listReads.isNotEmpty);
      await subscription.cancel();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.listReads, hasLength(1));
    });
  });

  group('changes during paging', () {
    test(
        'a Request added at the top while paging is not part of this list; '
        'the others are all there once', () async {
      server
        ..addRows(1200)
        ..beforePage = (page) {
          if (page == 2) server.rows.add(_row(5000));
        };
      final list = await read();
      expect(list, hasLength(1200));
      expect(_ids(list), isNot(contains(_id(5000))));
      expect(server.countReads, isEmpty);
    });

    test(
        'a Request not yet read deleted while paging: the totals are checked '
        'again and the list is accepted', () async {
      server.addRows(1200);
      final oldest = _expectedOrder(server.rows).last;
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(true);
      server.beforePage = (page) {
        if (page == 2) {
          server.rows.firstWhere((r) => r['id'] == oldest)['deleted_at'] =
              '2026-11-03T00:00:00+00:00';
        }
      };
      final list = await read();
      expect(list, hasLength(1199));
      expect(server.countReads, hasLength(1));
    });

    test(
        'an add and a delete that leave the totals contradicting the pages: '
        'read once more from the start, which adds up', () async {
      server.addRows(1200);
      final oldest = _expectedOrder(server.rows).last;
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(true);
      server.beforePage = (page) {
        if (page == 2) {
          server.rows.firstWhere((r) => r['id'] == oldest)['deleted_at'] =
              '2026-11-03T00:00:00+00:00';
          server.rows.add(_row(5000));
        }
      };
      final list = await read();
      expect(list, hasLength(1200)); // 1199 kept + the new one
      expect(_ids(list).first, _id(5000));
      expect(server.listReads, hasLength(7),
          reason: '3 pages and an empty 4th (a short page is not the end '
              'while rows are missing), then 3 again');
      expect(server.countReads, hasLength(1));
    });

    test(
        'changes on every page that never add up: a completeness error after '
        'one clean retry', () async {
      server.addRows(1200);
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(true);
      var next = 6000;
      server.beforePage = (page) {
        if (page.isEven) {
          final live =
              _expectedOrder(server.rows.where((r) => r['deleted_at'] == null));
          server.rows.firstWhere((r) => r['id'] == live.last)['deleted_at'] =
              '2026-11-03T00:00:00+00:00';
          server.rows.add(_row(next++));
        }
      };
      await expectLater(
          read(), incomplete(CoreEntityListProblem.changedDuringRead));
      expect(server.countReads, hasLength(2));
    });
  });

  group('the saved list (real encrypted cache)', () {
    late Directory root;
    const cache = RequestsLocalCache();

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('requests_keyset_test');
      Hive.init(root.path);
      EncryptedAccountListCache.debugStorageRoot = root.path;
    });

    tearDownAll(() async {
      await Hive.close();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    tearDown(() async {
      await Hive.close();
      EncryptedAccountListCache.debugForgetProcessState();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final entity in root.listSync()) {
        try {
          entity.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    RequestService requests() => RequestService(
          localCache: cache,
          currentUserId: () => _alice,
          coreEntities: () => core,
        );

    Future<List<List<RequestModel>>> openAndWait(
        bool Function(List<List<RequestModel>> lists, List<Object> errors) done,
        {List<Object>? errors}) async {
      final lists = <List<RequestModel>>[];
      final errs = errors ?? <Object>[];
      final sub = requests()
          .watchUserRequestsLocalFirst()
          .listen(lists.add, onError: errs.add);
      await _until(() => done(lists, errs));
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return lists;
    }

    /// The saved list once the save that follows a delivered list is done.
    Future<SavedList<RequestModel>> savedWith(int count) async {
      for (var i = 0; i < 200; i++) {
        final saved = await cache.readSaved(_alice);
        if (saved != null && saved.items.length == count) return saved;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('no saved list of $count');
    }

    test(
        'a later read that fails on page 2 leaves the saved list and its time '
        'exactly as they were', () async {
      server.addRows(1200);
      await openAndWait((lists, _) => lists.isNotEmpty);
      final before = await savedWith(1200);

      server
        ..rows.add(_row(5000))
        ..failPage = server.listReads.length + 2;
      final errors = <Object>[];
      final lists =
          await openAndWait((lists, errs) => errs.isNotEmpty, errors: errors);

      expect(lists.single, hasLength(1200), reason: 'the saved copy shown');
      expect(errors.single, isA<sb.PostgrestException>());
      final after = await cache.readSaved(_alice);
      expect(after!.items, hasLength(1200));
      expect(after.info.serverReadAt, before.info.serverReadAt);
    });

    test('an incomplete read (no count) does not replace the saved list',
        () async {
      server.addRows(1200);
      await openAndWait((lists, _) => lists.isNotEmpty);
      final before = await savedWith(1200);

      server
        ..rows.add(_row(5000))
        ..contentRange = (page, _) => '';
      final errors = <Object>[];
      await openAndWait((_, errs) => errs.isNotEmpty, errors: errors);
      expect(errors.single, isA<CoreEntityListIncomplete>());
      final after = await cache.readSaved(_alice);
      expect(after!.items, hasLength(1200));
      expect(after.info.serverReadAt, before.info.serverReadAt);
    });

    test(
        'a Request deleted on the server (and remembered) is not on any page; '
        'the whole list is shown and saved without it', () async {
      server.addRows(1200);
      final onPage3 = _expectedOrder(server.rows)[1100];
      server.rows.firstWhere((r) => r['id'] == onPage3)['deleted_at'] =
          '2026-11-03T00:00:00+00:00';
      await cache.rememberConfirmedDeletion(_alice, onPage3);
      final lists = await openAndWait((lists, _) => lists.isNotEmpty);
      expect(lists.last, hasLength(1199));
      final saved = await savedWith(1199);
      expect(_ids(saved.items), isNot(contains(onPage3)));
      expect(cache.isIntegrityBlocked(_alice), isFalse);
    });

    test(
        'a later page that still lists a Request confirmed deleted (a stale '
        'answer) shows it nowhere and saves nothing over the earlier list',
        () async {
      server.addRows(1200);
      await openAndWait((lists, _) => lists.isNotEmpty);
      final before = await savedWith(1200);

      final onPage3 = _expectedOrder(server.rows)[1100];
      await cache.rememberConfirmedDeletion(_alice, onPage3);
      final lists = await openAndWait(
          (lists, _) => lists.isNotEmpty && server.listReads.length >= 6);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      for (final list in lists) {
        expect(_ids(list), isNot(contains(onPage3)));
      }
      final after = await cache.readSaved(_alice);
      expect(after!.info.serverReadAt, before.info.serverReadAt,
          reason: 'the stale list was not saved');
      expect(_ids(after.items), isNot(contains(onPage3)));
      expect(after.info.hidesConfirmedDeletions, isTrue);
    });
  });

  test('measurements: requests and body bytes per read', () async {
    final lines = <String>[];
    for (final count in [0, 500, 1200, 10000]) {
      server = _Server()..addRows(count);
      client = sb.SupabaseClient(
        'https://unit-test.supabase.co',
        'unit-test-publishable-key',
        httpClient: server.client,
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      await signIn(_s1);
      core = SupabaseCoreEntitiesService(
        client: client,
        offerMedia: R2OfferMediaUploadService(
          supabaseClient: client,
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      final list = await read();
      expect(list, hasLength(count));
      lines.add('$count rows: ${server.listReads.length} request(s), '
          '${server.bodyBytes} body bytes, ${list.length} assembled');
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}
