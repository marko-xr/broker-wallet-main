// P3.3: what the seven Home count requests download.
//
// A PostgREST stand-in answers the real SupabaseHomeCountsService the way
// PostgREST does: a GET with select returns the matching rows (one JSON
// object per row) plus a Content-Range count; a HEAD returns only the
// headers. Row numbers per table are set by each test; the byte sizes
// measured follow from them (they are not hosted data volumes).
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/supabase_home_counts_service.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _alice = '11111111-1111-4111-8111-111111111111';

/// The seven tables and the Home count each feeds.
const _keys = {
  'watchmen': 'watchmen',
  'brokers': 'brokers',
  'offers': 'offers',
  'offices': 'offices',
  'owners': 'owners',
  'requests': 'requested',
  'quotations': 'quotation',
};

String _uuid(int i) =>
    '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

class _PostgRest {
  /// Rows per table this session may see.
  Map<String, int> rows = {for (final t in _keys.keys) t: 0};

  /// How each answer goes wrong, when set: a status, or a header problem.
  int? status;
  String? contentRange; // overrides the header ('' removes it)

  final List<http.Request> requests = [];
  int bodyBytes = 0;

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      final table = request.url.pathSegments.last;
      requests.add(request);
      final n = rows[table] ?? 0;
      final range = contentRange ?? (n == 0 ? '*/0' : '0-${n - 1}/$n');
      final headers = {
        'content-type': 'application/json',
        if (range.isNotEmpty) 'content-range': range,
      };
      if (status != null) {
        final body = request.method == 'HEAD'
            ? ''
            : '{"code":"42501","message":"permission denied"}';
        bodyBytes += utf8.encode(body).length;
        return http.Response(body, status!, headers: headers, request: request);
      }
      // PostgREST: a HEAD has no body; a GET returns the selected columns of
      // every matching row.
      final body = request.method == 'HEAD'
          ? ''
          : jsonEncode([
              for (var i = 0; i < n; i++) {'id': _uuid(i)}
            ]);
      bodyBytes += utf8.encode(body).length;
      return http.Response(body, 200, headers: headers, request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );

  Future<void> signIn() {
    String part(Map<String, dynamic> v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    return client.auth.setInitialSession(jsonEncode({
      'access_token': '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${part({
            'sub': _alice,
            'exp': exp.millisecondsSinceEpoch ~/ 1000
          })}.sig',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _alice,
        'aud': 'authenticated',
        'email': 'alice@example.test',
        'app_metadata': {'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-11T10:00:00Z',
      },
    }));
  }
}

class _Repo implements AuthRepository {
  String? uid;
  @override
  String? get currentUserId => uid;
  @override
  UserModel? get currentUser => null;
  @override
  Stream<UserModel?> get authStateChanges => const Stream<UserModel?>.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PostgRest server;
  late SupabaseHomeCountsService counts;

  setUp(() async {
    server = _PostgRest();
    await server.signIn();
    counts = SupabaseHomeCountsService(client: server.client);
  });

  /// One Home count read: its counts, requests and downloaded body bytes.
  Future<Map<String, int>> read(String label,
      {Map<String, int> fallback = const {}}) async {
    server
      ..requests.clear()
      ..bodyBytes = 0;
    final result = await counts.getCounts(fallback: fallback);
    // ignore: avoid_print
    print('P3.3 MEASURED $label: ${server.requests.length} requests, '
        '${server.requests.map((r) => r.method).toSet().join('/')}, '
        '${server.bodyBytes} body bytes');
    return result;
  }

  group('request shape', () {
    test(
        'seven count-only HEAD requests, one per table, with exactly the '
        'existing filter (not deleted) and an exact count', () async {
      await read('shape (0 rows)');
      expect(server.requests, hasLength(7));
      expect(server.requests.map((r) => r.url.pathSegments.last).toSet(),
          _keys.keys.toSet());
      for (final r in server.requests) {
        final table = r.url.pathSegments.last;
        expect(r.method, 'HEAD', reason: table);
        expect(r.url.queryParameters, {'deleted_at': 'is.null'},
            reason: '$table: same filter, no columns selected');
        expect(r.headers['Prefer'], contains('count=exact'), reason: table);
      }
    });
  });

  group('payload', () {
    test(
        'no row is downloaded, whatever the tables hold (here 3, 250 and '
        '1000 rows)', () async {
      final bytes = <int, int>{};
      for (final n in [3, 250, 1000]) {
        server.rows = {for (final t in _keys.keys) t: n};
        await read('$n rows per table');
        bytes[n] = server.bodyBytes;
      }
      expect(bytes, {3: 0, 250: 0, 1000: 0});
    });
  });

  group('counts', () {
    test('each of the seven counts is the table\'s exact count', () async {
      server.rows = {
        'watchmen': 1,
        'brokers': 2,
        'offers': 3,
        'offices': 4,
        'owners': 5,
        'requests': 6,
        'quotations': 7,
      };
      final result = await read('seven distinct counts');
      expect(result, {
        'watchmen': 1,
        'brokers': 2,
        'offers': 3,
        'offices': 4,
        'owners': 5,
        'requested': 6,
        'quotation': 7,
      });
    });

    test('a legitimate zero is zero', () async {
      final result = await read('all zero', fallback: {
        for (final k in _keys.values) k: 9,
      });
      expect(result.values.toSet(), {0});
    });
  });

  group('answers that are not a count keep what is shown', () {
    final shown = {for (final k in _keys.values) k: 9};

    for (final bad in {
      'no Content-Range header': '',
      'an unknown total (*/*)': '*/*',
      'a malformed total': '*/many',
    }.entries) {
      test('${bad.key}: never read as zero', () async {
        server.rows = {for (final t in _keys.keys) t: 4};
        server.contentRange = bad.value;
        final result = await read(bad.key, fallback: shown);
        expect(result, shown);
      });
    }

    for (final status in [401, 403, 500]) {
      test('HTTP $status: what is shown stays', () async {
        server.status = status;
        final result = await read('HTTP $status', fallback: shown);
        expect(result, shown);
      });
    }
  });

  group('Home', () {
    test(
        'a superseded session\'s zeros (gate filters every row) do not '
        'replace shown counts; R-02 cache keeps them', () async {
      SharedPreferences.setMockInitialValues({
        CountCacheService.countsKeyFor(_alice):
            jsonEncode({for (final k in _keys.values) k: 4}),
      });
      final cache = CountCacheService.forTesting();
      await cache.initialize();
      final repo = _Repo()..uid = _alice;
      final vm = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: (fallback) => counts.getCounts(fallback: fallback),
        authStateChanges: server.client.auth.onAuthStateChange,
        confirmSession: (_) => Future<bool>.value(false),
        sessionOf: () => 's1',
      );
      addTearDown(vm.dispose);
      for (var i = 0; i < 3; i++) {
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(vm.items.firstWhere((i) => i.labelKey == 'offers').count, 4);
      expect(cache.getAllCachedCounts(_alice)['offers'], 4);
      expect(server.requests.every((r) => r.method == 'HEAD'), isTrue);
    });
  });
}
