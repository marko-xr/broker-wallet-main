// P4.2 (tracker §7AK): Offers, Owners, Offices, Brokers and Watchmen are read
// whole in pages, exactly as Requests are since P4.1 (§7AJ, whose own tests
// are in requests_keyset_pagination_test.dart): 500 rows a page, newest first
// (created_at, then id), each page after the last row of the one before, the
// first with an exact count, delivered only once the pages add up.
//
// The server is an emulation of PostgREST for one table at a time: owner and
// deleted filters, order, limit, the keyset filter, its own row cap
// (`max_rows`) and the exact count.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
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

/// One of the five lists: its table, the columns its rows carry, and how
/// the app reads it.
class _Entity<T> {
  const _Entity({
    required this.table,
    required this.prefix,
    required this.columns,
    required this.read,
    required this.single,
    required this.idOf,
    required this.cache,
    required this.localFirst,
  });

  final String table;
  final String prefix;
  final Map<String, dynamic> Function(int n) columns;
  final Stream<List<T>> Function(SupabaseCoreEntitiesService core) read;

  /// The single-record read, whose columns the list keeps.
  final Future<Object?> Function(SupabaseCoreEntitiesService core, String id)
      single;
  final String? Function(T item) idOf;
  final EncryptedAccountListCache<T> cache;
  final Stream<List<T>> Function(SupabaseCoreEntitiesService core) localFirst;

  String id(int n) => '${prefix}0000000-0000-4000-8000-'
      '${n.toString().padLeft(12, '0')}';

  Map<String, dynamic> row(
    int n, {
    String owner = _alice,
    DateTime? createdAt,
    String? deletedAt,
  }) =>
      {
        'id': id(n),
        'owner_id': owner,
        'phone_number': '50000${n.toString().padLeft(4, '0')}',
        'country_code': '+971',
        'notes': 'Record number $n',
        'created_at':
            _pgTime(createdAt ?? _base.add(Duration(microseconds: n * 1001))),
        'updated_at': _pgTime(_base),
        'deleted_at': deletedAt,
        ...columns(n),
      };
}

final _entities = <_Entity<Object?>>[
  _Entity(
    table: 'offers',
    prefix: '2',
    columns: (n) => {
      'offer_type': 'rent',
      'selected_city': 'Dubai',
      'location_text': 'Dubai Marina, Tower $n',
      'min_price': 1000 + n,
      'max_price': 2000 + n,
      'square_footage': 900,
      'property_type': 'residential',
      'specific_property_type': 'Apartment',
      'rooms': 2,
      'bathrooms': 2,
      'pickup_location_text': '',
      'pickup_address': '',
      'legacy_uploaded_file_name': '',
      'status': 'available',
      'offer_areas': [
        {'area': 'Marina', 'ordinal': 0},
      ],
    },
    read: (core) => core.getOffers(),
    single: (core, id) => core.getOfferMetadata(id),
    idOf: (item) => (item as dynamic).id as String?,
    cache: const OffersLocalCache(),
    localFirst: (core) => OfferService(
      coreEntities: () => core,
      currentUserId: () => _alice,
    ).watchUserOffersLocalFirst(),
  ),
  _Entity(
    table: 'owners',
    prefix: '3',
    columns: (n) => {
      'name': 'Owner $n',
      'property_type_text': 'Villa',
      'property_location': 'Dubai Hills',
      'pickup_location_text': '',
      'pickup_address': '',
    },
    read: (core) => core.getOwners(),
    single: (core, id) => core.getOwner(id),
    idOf: (item) => (item as dynamic).id as String?,
    cache: const OwnersLocalCache(),
    localFirst: (core) => OwnerService(
      coreEntities: () => core,
      currentUserId: () => _alice,
    ).watchUserOwnersLocalFirst(),
  ),
  _Entity(
    table: 'offices',
    prefix: '4',
    columns: (n) => {
      'office_name': 'Office $n',
      'manager_name': 'Manager $n',
      'office_location': 'Business Bay',
      'pickup_location_text': '',
      'pickup_address': '',
    },
    read: (core) => core.getOffices(),
    single: (core, id) => core.getOffice(id),
    idOf: (item) => (item as dynamic).id as String?,
    cache: const OfficesLocalCache(),
    localFirst: (core) => OfficeService(
      coreEntities: () => core,
      currentUserId: () => _alice,
    ).watchUserOfficesLocalFirst(),
  ),
  _Entity(
    table: 'brokers',
    prefix: '5',
    columns: (n) => {'name': 'Broker $n'},
    read: (core) => core.getBrokers(),
    single: (core, id) => core.getBroker(id),
    idOf: (item) => (item as dynamic).id as String?,
    cache: const BrokersLocalCache(),
    localFirst: (core) => BrokerService(
      coreEntities: () => core,
      currentUserId: () => _alice,
    ).watchUserBrokersLocalFirst(),
  ),
  _Entity(
    table: 'watchmen',
    prefix: '6',
    columns: (n) => {
      'name': 'Watchman $n',
      'building_name': 'Building $n',
      'building_location': 'JLT',
      'pickup_location_text': '',
      'pickup_address': '',
    },
    read: (core) => core.getWatchmen(),
    single: (core, id) => core.getWatchman(id),
    idOf: (item) => (item as dynamic).id as String?,
    cache: const WatchmenLocalCache(),
    localFirst: (core) => WatchmenService(
      coreEntities: () => core,
      currentUserId: () => _alice,
    ).watchUserWatchmenLocalFirst(),
  ),
];

/// PostgREST, emulated for one table.
class _Server {
  _Server(this.table);

  final String table;
  final List<Map<String, dynamic>> rows = [];
  int? maxRows;
  FutureOr<void> Function(int page)? beforePage;
  String? Function(int page)? contentRange;
  int? networkFailFrom;
  bool Function(int page)? gateClosed;
  bool ignoreCursor = false;
  int? repeatLastRowOnPage;

  final List<http.Request> listReads = [];
  final List<http.Request> singleReads = [];
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
    if (!url.path.startsWith('/rest/v1/$table')) {
      return http.Response('{}', 200, request: request);
    }
    final q = url.queryParameters;
    if (request.method == 'HEAD') {
      return http.Response('', 200,
          headers: {'content-range': '*/${_visible(q).length}'},
          request: request);
    }
    if ((q['id'] ?? '').startsWith('eq.')) {
      singleReads.add(request);
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
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
    if (keyset != null && !ignoreCursor) {
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

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('entity_keyset_test');
    Hive.init(root.path);
    EncryptedAccountListCache.debugStorageRoot = root.path;
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final entity in _entities) {
    _entityTests(entity, () => root);
  }

  test('measurements: requests and body bytes per read, per list', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final lines = <String>[];
    for (final entity in _entities) {
      for (final count in [0, 500, 1200, 10000]) {
        final h = await _Harness.start(entity);
        for (var n = 1; n <= count; n++) {
          h.server.rows.add(entity.row(n));
        }
        final list = await entity.read(h.core).first;
        expect(list, hasLength(count));
        lines.add('${entity.table} $count rows: '
            '${h.server.listReads.length} request(s), '
            '${h.server.bodyBytes} body bytes');
      }
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}

/// A signed-in client on the emulated server, and the service on it.
class _Harness {
  _Harness._(this.server, this.client, this.core, this.mediaCalls);

  final _Server server;
  final sb.SupabaseClient client;
  final SupabaseCoreEntitiesService core;
  final List<http.BaseRequest> mediaCalls;

  static Future<_Harness> start(_Entity<Object?> entity) async {
    final server = _Server(entity.table);
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(_sessionJson(_alice, _s1));
    final mediaCalls = <http.BaseRequest>[];
    MockClient media() => MockClient((request) async {
          mediaCalls.add(request);
          return http.Response('{"media":[]}', 200, request: request);
        });
    final core = SupabaseCoreEntitiesService(
      client: client,
      offerMedia: R2OfferMediaUploadService(
          supabaseClient: client, httpClient: media()),
      ownerMedia: R2OfferMediaUploadService(
        supabaseClient: client,
        httpClient: media(),
        parent: MediaParent.owner,
      ),
    );
    return _Harness._(server, client, core, mediaCalls);
  }
}

void _entityTests(_Entity<Object?> entity, Directory Function() root) {
  group(entity.table, () {
    late _Harness h;
    late _Server server;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      ListSessionCheck.debugOverride = null;
      h = await _Harness.start(entity);
      server = h.server;
    });

    tearDown(() => ListSessionCheck.debugOverride = null);

    void addRows(int count) {
      for (var n = 1; n <= count; n++) {
        server.rows.add(entity.row(n));
      }
    }

    Future<List<Object?>> read() => entity.read(h.core).first;
    List<String?> ids(List<Object?> list) =>
        [for (final x in list) entity.idOf(x)];
    List<Object?> expected() =>
        [for (final r in server.rows.toList()..sort(_Server.compare)) r['id']];

    Future<Object?> failure() async {
      try {
        await read();
      } catch (e) {
        return e;
      }
      return null;
    }

    Matcher incomplete(CoreEntityListProblem problem) =>
        isA<CoreEntityListIncomplete>()
            .having((e) => e.problem, 'problem', problem);

    test(
        'pages of 500, newest first with the id as tie breaker, an exact '
        'count, and the same filters and columns as before', () async {
      addRows(3);
      await read();
      await entity.single(h.core, entity.id(1));
      final list = server.listReads.single;
      final q = list.url.queryParameters;
      expect(q['owner_id'], 'eq.$_alice');
      expect(q['deleted_at'], 'is.null');
      expect(q['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(q['limit'], '500');
      expect(q.containsKey('offset'), isFalse);
      expect(list.headers['Prefer'], contains('count=exact'));
      expect(
          q['select'], server.singleReads.single.url.queryParameters['select'],
          reason: 'the same columns as the single-record read');
    });

    for (final (count, pages) in [
      (0, 1),
      (499, 1),
      (500, 1),
      (501, 2),
      (1200, 3),
    ]) {
      test('$count rows: $pages request(s), every row once, in order',
          () async {
        addRows(count);
        final list = await read();
        expect(server.listReads, hasLength(pages));
        expect(ids(list), expected());
      });
    }

    test('1,200 rows from a server capped at 1,000, and at 300: all 1,200',
        () async {
      addRows(1200);
      server.maxRows = 1000;
      expect(await read(), hasLength(1200));
      expect(server.listReads, hasLength(3));
      final h2 = await _Harness.start(entity);
      for (var n = 1; n <= 1200; n++) {
        h2.server.rows.add(entity.row(n));
      }
      h2.server.maxRows = 300;
      expect(await entity.read(h2.core).first, hasLength(1200));
      expect(h2.server.listReads, hasLength(4));
    });

    test('rows created at the same instant: ordered by id, none lost or twice',
        () async {
      final same = [DateTime.utc(2026, 3, 1), DateTime.utc(2026, 3, 2)];
      for (var n = 1; n <= 1200; n++) {
        server.rows.add(entity.row(n, createdAt: same[n % 2]));
      }
      final list = await read();
      expect(ids(list), expected());
      expect(ids(list).toSet(), hasLength(1200));
    });

    test('other accounts\' and deleted rows are not in the list', () async {
      addRows(600);
      server.rows
        ..add(entity.row(9001, owner: _bob))
        ..add(entity.row(9002, deletedAt: '2026-11-01T00:00:00+00:00'));
      final list = await read();
      expect(list, hasLength(600));
    });

    test(
        'reading the list asks the media service for nothing (media stays '
        'per record)', () async {
      addRows(1200);
      await read();
      expect(h.mediaCalls, isEmpty);
    });

    for (final header in ['', '0-2/*', '0-2/many']) {
      test('count "$header": a completeness error, not a network one',
          () async {
        addRows(3);
        server.contentRange = (page) => page == 1 ? header : null;
        final error = await failure();
        expect(error, incomplete(CoreEntityListProblem.missingCount));
        expect(isRetryableListError(error!), isFalse);
      });
    }

    test('a network failure on page 2 fails the whole read as a network one',
        () async {
      addRows(1200);
      server.networkFailFrom = 2;
      final error = await failure();
      expect(error, isNotNull);
      expect(isRetryableListError(error!), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a repeated row, or a server that does not advance, is refused',
        () async {
      addRows(800);
      server.repeatLastRowOnPage = 2;
      expect(await failure(), incomplete(CoreEntityListProblem.badPage));
      final h2 = await _Harness.start(entity);
      for (var n = 1; n <= 800; n++) {
        h2.server.rows.add(entity.row(n));
      }
      h2.server.ignoreCursor = true;
      Object? error;
      try {
        await entity.read(h2.core).first;
      } catch (e) {
        error = e;
      }
      expect(error, incomplete(CoreEntityListProblem.badPage));
      expect(h2.server.listReads, hasLength(2));
    });

    test(
        'a session replaced during paging: ListSessionNotCurrent, not a '
        'short list', () async {
      addRows(1200);
      server.gateClosed = (page) => page >= 2;
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(false);
      expect(await failure(), isA<ListSessionNotCurrent>());
    });

    test(
        'the same account signing in again, or another account, during '
        'paging: no further page', () async {
      addRows(1200);
      server.beforePage = (page) async {
        if (page == 2) {
          await h.client.auth.setInitialSession(_sessionJson(_alice, _s2));
        }
      };
      expect(await failure(), isA<ListSessionNotCurrent>());
      expect(server.listReads, hasLength(2));

      final h2 = await _Harness.start(entity);
      for (var n = 1; n <= 1200; n++) {
        h2.server.rows.add(entity.row(n));
      }
      h2.server.beforePage = (page) async {
        if (page == 1) {
          await h2.client.auth.setInitialSession(_sessionJson(_bob, _s2));
        }
      };
      Object? error;
      try {
        await entity.read(h2.core).first;
      } catch (e) {
        error = e;
      }
      expect(error, isA<ListSessionNotCurrent>());
      expect(h2.server.listReads, hasLength(1));
    });

    test('closing the screen during a page: no further page', () async {
      addRows(1200);
      final gate = Completer<void>();
      server.beforePage = (page) => page == 1 ? gate.future : null;
      final sub = entity.read(h.core).listen((_) {}, onError: (_) {});
      await _until(() => server.listReads.isNotEmpty);
      await sub.cancel();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.listReads, hasLength(1));
    });

    test('more than 20,000 rows: a completeness error after one request',
        () async {
      addRows(20001);
      expect(await failure(), incomplete(CoreEntityListProblem.tooLarge));
      expect(server.listReads, hasLength(1));
    });

    group('the saved list (real encrypted cache)', () {
      tearDown(() async {
        await Hive.close();
        EncryptedAccountListCache.debugForgetProcessState();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        for (final e in root().listSync()) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      Future<List<List<Object?>>> open(
          bool Function(List<List<Object?>> lists, List<Object> errors) done,
          {List<Object>? errors}) async {
        final lists = <List<Object?>>[];
        final errs = errors ?? <Object>[];
        final sub =
            entity.localFirst(h.core).listen(lists.add, onError: errs.add);
        await _until(() => done(lists, errs));
        await sub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return lists;
      }

      Future<SavedList<Object?>> savedWith(int count) async {
        for (var i = 0; i < 200; i++) {
          final saved = await entity.cache.readSaved(_alice);
          if (saved != null && saved.items.length == count) return saved;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('no saved list of $count');
      }

      test(
          'a later read failing on page 2, or without a count, leaves the '
          'saved list and its time as they were', () async {
        addRows(1200);
        await open((lists, _) => lists.isNotEmpty);
        final before = await savedWith(1200);

        // The next read's page 2 repeats a row of page 1.
        server.rows.add(entity.row(5000));
        server.repeatLastRowOnPage = server.listReads.length + 2;
        final errors = <Object>[];
        final lists = await open((_, errs) => errs.isNotEmpty, errors: errors);
        expect(lists.single, hasLength(1200), reason: 'the saved copy shown');
        expect(errors.single, incomplete(CoreEntityListProblem.badPage));
        var after = await entity.cache.readSaved(_alice);
        expect(after!.items, hasLength(1200));
        expect(after.info.serverReadAt, before.info.serverReadAt);

        server
          ..repeatLastRowOnPage = null
          ..contentRange = (page) => '';
        final errors2 = <Object>[];
        await open((_, errs) => errs.isNotEmpty, errors: errors2);
        expect(errors2.single, incomplete(CoreEntityListProblem.missingCount));
        after = await entity.cache.readSaved(_alice);
        expect(after!.items, hasLength(1200));
        expect(after.info.serverReadAt, before.info.serverReadAt);
      });

      test(
          'a record confirmed deleted: hidden on every page; a stale page '
          'that still lists it saves nothing over the earlier list', () async {
        addRows(1200);
        await open((lists, _) => lists.isNotEmpty);
        final before = await savedWith(1200);

        final onPage3 = expected()[1100] as String;
        await entity.cache.rememberConfirmedDeletion(_alice, onPage3);
        final reads = server.listReads.length;
        final lists = await open((lists, _) =>
            lists.isNotEmpty && server.listReads.length >= reads + 3);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        for (final list in lists) {
          expect(ids(list), isNot(contains(onPage3)));
        }
        final after = await entity.cache.readSaved(_alice);
        expect(after!.info.serverReadAt, before.info.serverReadAt);
        expect(ids(after.items), isNot(contains(onPage3)));
        expect(entity.cache.isIntegrityBlocked(_alice), isFalse);
      });
    });
  });
}
