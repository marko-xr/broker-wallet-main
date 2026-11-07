// Q-2b: the Quotations list shows this account's encrypted saved copy first,
// then the server's whole (Q-1a paged) list, which replaces it and is saved.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// QuotationsLocalCache, QuotationService, SupabaseQuotationService and
// QuotationListViewModel, the secure-storage test store, and one emulated
// PostgREST server. A network failure takes the client's own GET retries
// (supabase 2.16.1 `from()` keeps them on: 1 + 2 + 4 s) before the list
// sees it, so offline cases wait for the screen's outcome itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/favorites_local_cache.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:flutter/services.dart';
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

/// The 12 fields the saved copy keeps (tracker §7AX, D-Q1/D-Q2).
const _savedFields = {
  'id',
  'userId',
  'propertyTitle',
  'propertyType',
  'date',
  'totalAmount',
  'numberOfInstallments',
  'currencyCode',
  'officeName',
  'pdfMediaId',
  'createdAt',
  'updatedAt',
};

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
  final micros = u.millisecond * 1000 + u.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:'
      '${two(u.minute)}:${two(u.second)}$fraction+00:00';
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
      'office_logo_media_id': 'cccccccc-cccc-4ccc-8ccc-000000000001',
      'pdf_media_id': n.isEven
          ? 'bbbbbbbb-bbbb-4bbb-8bbb-${n.toString().padLeft(12, '0')}'
          : null,
      'version': 3,
      'created_at': _pgTime(DateTime.utc(2026).add(Duration(seconds: n))),
      'updated_at': _pgTime(DateTime.utc(2026, 2).add(Duration(seconds: n))),
      'deleted_at': null,
    };

/// PostgREST for `quotations`: owner and deleted filters, order, limit,
/// keyset, row cap, exact count, the soft delete and its confirming read.
class _Server {
  final List<Map<String, dynamic>> rows = [];
  int? maxRows = 1000; // the hosted cap (§7AL)
  bool networkDown = false;
  bool failLaterPages = false;
  bool gateClosed = false;
  bool deletesConfirm = true;
  Future<void> Function()? holdList;

  final List<http.Request> listReads = [];
  final List<http.Request> requests = [];
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
    final q = url.queryParameters;
    if (networkDown) throw http.ClientException('offline', url);
    if (url.path != '/rest/v1/quotations') return _json(const [], request);
    if (request.method == 'PATCH') {
      final id = q['id']!.substring(3);
      if (!deletesConfirm) return _json(const [], request);
      for (final row in rows) {
        if (row['id'] == id) row['deleted_at'] = _pgTime(DateTime.utc(2026, 3));
      }
      return _json([
        {'id': id}
      ], request);
    }
    if (q['deleted_at'] == 'not.is.null') {
      return _json([
        for (final row in rows)
          if ('eq.${row['id']}' == q['id'] && row['deleted_at'] != null)
            {'id': row['id']}
      ], request);
    }
    if (request.method == 'HEAD') {
      return http.Response('', 200,
          headers: {'content-range': '*/${_visible(q).length}'},
          request: request);
    }
    listReads.add(request);
    await holdList?.call();
    final keyset = q['or'];
    if (keyset != null && failLaterPages) {
      return _json({'message': 'boom', 'code': 'XX000'}, request, status: 400);
    }
    var found = _visible(q)..sort(compare);
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
    return http.Response(jsonEncode(answer), answer.length < total ? 206 : 200,
        headers: {'content-type': 'application/json', 'content-range': range},
        request: request);
  }
}

class _App {
  _App._(this.server, this.client, this.dir);

  final _Server server;
  final sb.SupabaseClient client;
  final Directory dir;

  late final SupabaseQuotationService remote =
      SupabaseQuotationService(client: client);

  /// The account's encrypted PDF copies (Q-2c-1b), in this test's folder.
  late final QuotationPdfVault vault = QuotationPdfVault(
    documents: () async => dir,
    temporary: () async => dir,
    keys: _VaultKeys(),
    backup: _NoBackupGuard(),
  );

  late final QuotationService quotations = QuotationService(
    remote: remote,
    pdfCache: QuotationPdfCache(directory: () async => dir),
    pdfVault: vault,
    httpClient: MockClient((_) async => http.Response('', 404)),
    currentUserId: () => client.auth.currentUser?.id,
    sessionOf: () =>
        AppSessionCoordinator.sessionId(client.auth.currentSession),
  );

  static Future<_App> start({int rows = 0, String uid = _alice}) async {
    final server = _Server();
    for (var n = 1; n <= rows; n++) {
      server.rows.add(_row(n, owner: uid));
    }
    final client = sb.SupabaseClient(
      'https://unit-test.supabase.co',
      'unit-test-publishable-key',
      httpClient: server.client,
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.setInitialSession(_sessionJson(uid, _s1));
    final dir = await Directory.systemTemp.createTemp('q2b_pdf_');
    addTearDown(() => dir.delete(recursive: true));
    return _App._(server, client, dir);
  }

  int get reads => server.listReads.length;

  Future<void> signIn(String uid, String session) =>
      client.auth.setInitialSession(_sessionJson(uid, session));
}

/// One open Quotations screen: the real ViewModel and what it delivers.
class _Screen {
  _Screen(_App app) {
    vm = QuotationListViewModel(
      quotationService: app.quotations,
      toast: (_, __) {},
    )..onRefreshFailed = () {
        failuresShown++;
        return true;
      };
    subscription = vm.quotationsStream!.listen(lists.add, onError: errors.add);
  }

  late final QuotationListViewModel vm;
  late final StreamSubscription<List<QuotationModel>> subscription;
  final List<List<QuotationModel>> lists = [];
  final List<Object> errors = [];
  int failuresShown = 0;

  List<String?> get shown => lists.last.map((q) => q.id).toList();

  Future<void> close() => subscription.cancel();
}

/// Waits until nothing is in flight and nothing has started for a while,
/// and every queued box operation of [uid] has ended.
Future<void> _settle(_Server s, [String uid = _alice]) async {
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
  await const QuotationsLocalCache().debugSettled(uid);
}

/// Long enough for a network failure to come through the client's retries.
const _offline = 3000;

Future<void> _until(bool Function() done, {int tries = 800}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

QuotationModel _full(String id, String account,
        {double? total = 120000.5,
        int? installments = 4,
        String? currency = 'AED',
        String? pdf = 'bbbbbbbb-bbbb-4bbb-8bbb-000000000001',
        String? type = 'Villa',
        String? date = '01/10/2026'}) =>
    QuotationModel(
      id: id,
      userId: account,
      propertyTitle: 'Villa $id',
      propertyType: type,
      parking: true,
      subtitle: 'subtitle secret',
      date: date,
      startDate: '01/11/2026',
      endDate: '01/11/2027',
      currencyCode: currency,
      professionalFee: 5000,
      totalAmount: total,
      numberOfInstallments: installments,
      paymentType: 'cheque',
      insuranceAmount: 2000,
      insuranceReturnable: true,
      officeName: 'Realtig',
      officeLogoUrl: 'https://signed.example/logo?token=secret',
      customNote: 'note secret',
      welcomeMessageMode: WelcomeMessageMode.custom,
      customWelcomeMessage: 'welcome secret',
      downpayments: [
        DownpaymentItem(
            method: PaymentMethod.cheque, number: 1, amount: 30000.25)
      ],
      governmentFees: GovernmentFees(percentOfTotalRent: 2, total: 2400),
      administrativeFees: AdministrativeFees(
          fees: [AdministrativeFeeItem(title: 'Ejari', amount: 220)]),
      version: 7,
      officeLogoMediaId: 'cccccccc-cccc-4ccc-8ccc-000000000009',
      pdfMediaId: pdf,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6, 7, 8),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';
  const cache = QuotationsLocalCache();

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('quotations_local_first');
    Hive.init(tempDir.path);
    EncryptedAccountListCache.debugStorageRoot = tempDir.path;
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ListSessionCheck.debugOverride = (_) => Future<bool>.value(true);
  });

  tearDown(() async {
    ListSessionCheck.debugOverride = null;
    final names = [
      for (final uid in [_alice, _bob]) ...[
        QuotationsLocalCache.boxNameForUid(uid),
        OfficesLocalCache.boxNameForUid(uid),
      ],
    ];
    for (final name in names) {
      // A box that failed to open is closed by Hive without waiting; on
      // Windows its file stays locked for a moment.
      for (var attempt = 0;; attempt++) {
        try {
          await Hive.deleteBoxFromDisk(name, path: listsDir());
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
    EncryptedAccountListCache.debugForgetProcessState();
  });

  Box<String> box(String uid) =>
      Hive.box<String>(QuotationsLocalCache.boxNameForUid(uid));

  Map<String, Object?> envelope(String uid) => Map<String, Object?>.from(
      json.decode(box(uid).get('quotations_v2')!) as Map);

  List<Map<String, dynamic>> payload(String uid) => [
        for (final e in json.decode(envelope(uid)['p']! as String) as List)
          Map<String, dynamic>.from(e as Map)
      ];

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureQuotationsCacheKeyStore.storageKeyFor(uid));

  Future<void> restart() async {
    await pumpEventQueue();
    await cache.debugSettled(_alice);
    await Hive.close();
    EncryptedAccountListCache.debugForgetProcessState();
  }

  List<String?> ids(List<QuotationModel>? list) =>
      (list ?? const []).map((q) => q.id).toList();

  // -----------------------------------------------------------------------
  group('the saved copy', () {
    test('keeps exactly the 12 approved fields — no fees, notes, links',
        () async {
      await cache.write(_alice, [_full('q1', _alice)]);
      final stored = payload(_alice).single;
      expect(stored.keys.toSet(), _savedFields);
      final text = envelope(_alice)['p']! as String;
      for (final secret in [
        'secret',
        'Ejari',
        '30000.25',
        'cccccccc-cccc-4ccc-8ccc-000000000009',
        'signed.example',
        'cheque',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('financial, nullable and time values come back exactly, in order',
        () async {
      final list = [
        _full('q1', _alice, total: 0.1, installments: 1, currency: 'USD'),
        _full('q2', _alice, total: 0.7),
        _full('q3', _alice, total: 999999999999.99),
        _full('q4', _alice, total: 0),
        _full('q5', _alice,
            total: null,
            installments: null,
            currency: null,
            pdf: null,
            type: null,
            date: null),
      ];
      await cache.write(_alice, list);
      await restart();
      final back = (await cache.read(_alice))!;
      expect(ids(back), ['q1', 'q2', 'q3', 'q4', 'q5']);
      for (var i = 0; i < list.length; i++) {
        final a = list[i], b = back[i];
        expect(b.totalAmount, a.totalAmount);
        expect(b.numberOfInstallments, a.numberOfInstallments);
        expect(b.currencyCode, a.currencyCode);
        expect(b.pdfMediaId, a.pdfMediaId);
        expect(b.hasPdf, a.hasPdf);
        expect(b.propertyTitle, a.propertyTitle);
        expect(b.propertyType, a.propertyType);
        expect(b.date, a.date);
        expect(b.officeName, a.officeName);
        expect(b.userId, _alice);
        expect(b.createdAt.toUtc(), a.createdAt.toUtc());
        expect(b.updatedAt.toUtc(), a.updatedAt.toUtc());
        // Never kept: the rest of the aggregate.
        expect(b.version, isNull);
        expect(b.officeLogoMediaId, isNull);
        expect(b.officeLogoUrl, isNull);
        expect(b.professionalFee, isNull);
        expect(b.downpayments, isEmpty);
        expect(b.customNote, isNull);
      }
      expect(back[2].totalAmount!.toStringAsFixed(2), '999999999999.99');
      expect(back[0].totalAmount, 0.1);
    });

    test('its own box and key, in the backup-excluded folder', () async {
      await cache.write(_alice, [_full('q1', _alice)]);
      expect(QuotationsLocalCache.boxNameForUid(_alice),
          'cached_quotations_$_alice');
      expect(SecureQuotationsCacheKeyStore.storageKeyFor(_alice),
          'quotations_cache_key_v1_$_alice');
      expect(await secureKey(_alice), isNotNull);
      expect(
          await Hive.boxExists(QuotationsLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isTrue);
      final names = {
        QuotationsLocalCache.boxNameForUid(_alice),
        RequestsLocalCache.boxNameForUid(_alice),
        OffersLocalCache.boxNameForUid(_alice),
        OwnersLocalCache.boxNameForUid(_alice),
        OfficesLocalCache.boxNameForUid(_alice),
        BrokersLocalCache.boxNameForUid(_alice),
        WatchmenLocalCache.boxNameForUid(_alice),
        FavoritesLocalCache.boxNameForUid(_alice),
      };
      expect(names, hasLength(8));
      final keys = {
        SecureQuotationsCacheKeyStore.storageKeyFor(_alice),
        SecureOfficesCacheKeyStore.storageKeyFor(_alice),
        SecureFavoritesCacheKeyStore.storageKeyFor(_alice),
      };
      expect(keys, hasLength(3));
    });

    test('the six lists and Favorites are untouched by a Quotations write',
        () async {
      const offices = OfficesLocalCache();
      await offices.write(_alice, [
        OfficeModel(
          id: 'f1',
          userId: _alice,
          officeName: 'Office',
          managerName: 'Manager',
          countryCode: '+971',
          phoneNumber: '503334455',
          officeLocation: 'Business Bay',
          notes: '',
          pickUpLocation: '',
          pickUpAddress: '',
        ),
      ]);
      final officeKey = await const FlutterSecureStorage()
          .read(key: SecureOfficesCacheKeyStore.storageKeyFor(_alice));
      await cache.write(_alice, [_full('q1', _alice)]);
      expect(
          await const FlutterSecureStorage()
              .read(key: SecureOfficesCacheKeyStore.storageKeyFor(_alice)),
          officeKey);
      expect((await offices.read(_alice))!.single.id, 'f1');
      expect(await secureKey(_alice), isNot(officeKey));
    });

    test('another account\'s records, or none, are never saved or read',
        () async {
      await cache.write(_alice, [
        _full('q1', _alice),
        _full('q2', _bob),
        _full('q3', ''),
      ]);
      expect(ids(await cache.read(_alice)), ['q1']);
      expect(await cache.read(_bob), isNull);
      await cache.write(_bob, [_full('b1', _bob)]);
      expect(ids(await cache.read(_bob)), ['b1']);
      expect(ids(await cache.read(_alice)), ['q1']);
      expect(await secureKey(_alice), isNot(await secureKey(_bob)));
    });

    test('an unavailable key store: nothing written, nothing read', () async {
      final broken = QuotationsLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_full('q1', _alice)]);
      expect(
          await Hive.boxExists(QuotationsLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await broken.read(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_full('q1', _alice)]);
      await box(_alice).close();
      final otherKey = base64.encode(List<int>.generate(32, (i) => 5 * i));
      await const FlutterSecureStorage().write(
          key: SecureQuotationsCacheKeyStore.storageKeyFor(_alice),
          value: otherKey);
      final file = File('${listsDir()}${Platform.pathSeparator}'
          '${QuotationsLocalCache.boxNameForUid(_alice)}.hive');
      final before = file.readAsBytesSync();
      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_full('q2', _alice)]);
      expect(file.readAsBytesSync(), before,
          reason: 'only a verified server read may recover it (D-2)');
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });
  });

  // -----------------------------------------------------------------------
  group('the screen', () {
    test('a whole paged server list is saved; reopened offline it shows first',
        () async {
      final app = await _App.start(rows: 1200);
      final online = _Screen(app);
      await _settle(app.server);
      expect(app.reads, 3, reason: 'Q-1a: three pages of 500');
      expect(online.lists.single, hasLength(1200));
      expect(payload(_alice), hasLength(1200));
      await online.close();
      await restart();

      app.server.networkDown = true;
      final offline = _Screen(app);
      await _until(() => offline.lists.isNotEmpty);
      expect(offline.lists.single, hasLength(1200));
      expect(offline.lists.single.first.id, _qid(1200), reason: 'order kept');
      await _until(() => offline.failuresShown > 0, tries: _offline);
      expect(offline.lists, hasLength(1), reason: 'the saved list stays');
      expect(offline.errors, isEmpty, reason: 'never the error state');
      expect(offline.failuresShown, 1, reason: 'the existing toast, once');
      await offline.close();
    });

    test('nothing saved and offline ⇒ the existing error state, no toast',
        () async {
      final app = await _App.start(rows: 3);
      app.server.networkDown = true;
      final screen = _Screen(app);
      await _until(() => screen.errors.isNotEmpty, tries: _offline);
      expect(screen.lists, isEmpty);
      expect(screen.errors, hasLength(1));
      expect(screen.errors.single, isA<QuotationException>());
      expect(screen.failuresShown, 0);
      await screen.close();
    });

    test('a failed second page saves nothing; the saved list stays', () async {
      final app = await _App.start(rows: 1200);
      await cache.write(_alice, [_full('old', _alice)]);
      app.server.failLaterPages = true;
      final screen = _Screen(app);
      await _settle(app.server);
      expect(ids(screen.lists.single), ['old']);
      expect(screen.failuresShown, 1);
      expect(payload(_alice).single['id'], 'old');
      await screen.close();
    });

    test('a confirmed empty server list is saved empty and shown', () async {
      final app = await _App.start();
      await cache.write(_alice, [_full('old', _alice)]);
      final screen = _Screen(app);
      await _settle(app.server);
      expect(screen.lists.last, isEmpty);
      expect(payload(_alice), isEmpty);
      await screen.close();
    });

    test('measured: an empty list asks the session check twice, not more',
        () async {
      var asked = 0;
      ListSessionCheck.debugOverride = (_) {
        asked++;
        return Future<bool>.value(true);
      };
      final app = await _App.start();
      final screen = _Screen(app);
      await _settle(app.server);
      expect(screen.lists.single, isEmpty);
      expect(asked, 2, reason: 'the Q-1a reader, then localFirstList');
      app.server.rows.add(_row(1));
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      await _settle(app.server);
      expect(asked, 2, reason: 'a list with rows is never checked');
      await screen.close();
    });

    test('an empty list from a replaced session is neither saved nor shown',
        () async {
      final app = await _App.start(rows: 2);
      await cache.write(_alice, [_full('old', _alice)]);
      ListSessionCheck.debugOverride = (_) => Future<bool>.value(false);
      app.server.gateClosed = true;
      final screen = _Screen(app);
      await _settle(app.server);
      expect(ids(screen.lists.single), ['old']);
      expect(payload(_alice).single['id'], 'old');
      await screen.close();
    });

    test('another account never sees the saved copy of the first', () async {
      final app = await _App.start(rows: 2);
      final first = _Screen(app);
      await _settle(app.server);
      await first.close();
      await app.signIn(_bob, _s2);
      app.server.networkDown = true;
      final second = _Screen(app);
      await _until(() => second.errors.isNotEmpty, tries: _offline);
      expect(second.lists, isEmpty);
      expect(second.errors, hasLength(1));
      expect(await cache.read(_bob), isNull);
      await second.close();
    });

    test('signed out: no saved copy is read or shown', () async {
      final app = await _App.start(rows: 2);
      final first = _Screen(app);
      await _settle(app.server);
      await first.close();
      await app.client.auth.signOut();
      final screen = _Screen(app);
      await _settle(app.server);
      expect(screen.lists, isEmpty);
      expect(screen.errors.single, isA<QuotationException>());
      await screen.close();
    });

    for (final (label, to) in [
      ('another account signs in', (_bob, _s2)),
      ('the same account signs in again', (_alice, _s2)),
    ]) {
      test('$label during a read ⇒ the late answer is dropped, not saved',
          () async {
        final app = await _App.start(rows: 3);
        await cache.write(_alice, [_full('old', _alice)]);
        final gate = Completer<void>();
        app.server.holdList = () => gate.future;
        final screen = _Screen(app);
        await _until(() => app.reads == 1);
        await app.signIn(to.$1, to.$2);
        app.server.holdList = null;
        gate.complete();
        await _settle(app.server);
        expect(ids(screen.lists.single), ['old'], reason: 'nothing late');
        expect(payload(_alice).single['id'], 'old');
        expect(await cache.read(_bob), isNull);
        await screen.close();
      });
    }

    test('a screen closed during a read saves nothing', () async {
      final app = await _App.start(rows: 3);
      await cache.write(_alice, [_full('old', _alice)]);
      final gate = Completer<void>();
      app.server.holdList = () => gate.future;
      final screen = _Screen(app);
      await _until(() => app.reads == 1);
      await screen.close();
      app.server.holdList = null;
      gate.complete();
      await _settle(app.server);
      expect(payload(_alice).single['id'], 'old');
    });

    test('Q-1b: a Quotation change re-reads and saves; other kinds do not',
        () async {
      final app = await _App.start(rows: 2);
      final screen = _Screen(app);
      await _settle(app.server);
      final before = box(_alice).get('quotations_v2');
      for (final kind in CoreEntityKind.values) {
        if (kind != CoreEntityKind.quotation) {
          CoreEntityMutationNotifier.notify(kind);
        }
      }
      await _settle(app.server);
      expect(app.reads, 1);
      expect(box(_alice).get('quotations_v2'), before);
      app.server.rows.add(_row(3));
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      await _settle(app.server);
      expect(app.reads, 2);
      expect(payload(_alice), hasLength(3));
      await screen.close();
    });

    test('many changes during one read ⇒ one more read, the last list saved',
        () async {
      final app = await _App.start(rows: 1200);
      final screen = _Screen(app);
      await _settle(app.server);
      final gate = Completer<void>();
      app.server.holdList = () => gate.future;
      app.server.rows.add(_row(1201));
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      await _until(() => app.reads == 4);
      app.server.rows.add(_row(1202));
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
      app.server.holdList = null;
      gate.complete();
      await _settle(app.server);
      expect(app.reads, 3 + 3 + 3);
      expect(payload(_alice), hasLength(1202));
      expect(screen.lists.last, hasLength(1202));
      await screen.close();
    });

    test('offline, then the app resumes with the network back ⇒ it recovers',
        () async {
      final app = await _App.start(rows: 2);
      await cache.write(_alice, [_full('old', _alice)]);
      app.server.networkDown = true;
      final screen = _Screen(app);
      await _until(() => screen.failuresShown > 0, tries: _offline);
      expect(ids(screen.lists.single), ['old']);
      app.server.networkDown = false;
      // The failed read began over two seconds ago (the client's own
      // retries), so this resume is not too close to it to count.
      ListRefreshSignals.instance.debugResume();
      await _until(() => screen.lists.length > 1);
      await _settle(app.server);
      expect(screen.lists.last, hasLength(2));
      expect(payload(_alice), hasLength(2));
      await screen.close();
    });
  });

  // -----------------------------------------------------------------------
  group('network failures are retried for Quotations only', () {
    Future<int> readsAfterFailure(Object failure,
        {bool Function(Object)? isRetryable}) async {
      var reads = 0;
      final stream = localFirstList<QuotationModel>(
        server: () {
          reads++;
          return reads == 1
              ? Stream<List<QuotationModel>>.error(failure)
              : Stream.value([_full('q1', _alice)]);
        },
        cache: cache,
        currentUserId: () => _alice,
        refreshSignals: const Stream<void>.empty(),
        retryDelays: const [Duration(milliseconds: 5)],
        isAppActive: () => true,
        sessionOf: () => _s1,
        isRetryable: isRetryable,
      );
      final sub = stream.listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();
      return reads;
    }

    const network = QuotationException(QuotationFailure.network);
    const other = QuotationException(QuotationFailure.unknown);

    test('the default (the six lists) does not retry a Quotation failure',
        () async {
      expect(await readsAfterFailure(network), 1);
      expect(await readsAfterFailure(const SocketException('x')), 2);
    });

    test('the Quotations check retries a network failure only', () async {
      const check = QuotationService.isRetryableListFailure;
      expect(await readsAfterFailure(network, isRetryable: check), 2);
      expect(await readsAfterFailure(other, isRetryable: check), 1);
      expect(
          await readsAfterFailure(const SocketException('x'),
              isRetryable: check),
          2);
    });
  });

  // -----------------------------------------------------------------------
  group('deletes and their markers', () {
    test('a confirmed delete stays deleted offline', () async {
      final app = await _App.start(rows: 3);
      final screen = _Screen(app);
      await _settle(app.server);
      await screen.close();
      final gate = Completer<void>();
      app.server.holdList = () => gate.future; // the re-read never answers
      await app.quotations.deleteQuotation(_qid(2));
      await restart();
      app.server.holdList = null;
      gate.complete();
      app.server.networkDown = true;
      final offline = _Screen(app);
      await _until(() => offline.lists.isNotEmpty);
      expect(ids(offline.lists.single), [_qid(3), _qid(1)]);
      await offline.close();
      await _settle(app.server);
    });

    test('an unconfirmed delete fails and marks nothing', () async {
      final app = await _App.start(rows: 3);
      final screen = _Screen(app);
      await _settle(app.server);
      await screen.close();
      app.server.deletesConfirm = false;
      await expectLater(app.quotations.deleteQuotation(_qid(2)),
          throwsA(isA<QuotationException>()));
      await restart();
      await cache.readSaved(_alice); // opens the box again
      expect(box(_alice).get('quotations_deleted_v1'), isNull);
      app.server.networkDown = true;
      final offline = _Screen(app);
      await _until(() => offline.lists.isNotEmpty);
      expect(ids(offline.lists.single), [_qid(3), _qid(2), _qid(1)]);
      await offline.close();
    });

    test('damaged markers block the list: no list, one error, no read',
        () async {
      final app = await _App.start(rows: 3);
      final screen = _Screen(app);
      await _settle(app.server);
      await screen.close();
      await app.quotations.deleteQuotation(_qid(2));
      await _settle(app.server);
      final sealed = Map<String, Object?>.from(
          json.decode(box(_alice).get('quotations_deleted_v1')!) as Map);
      final tag = base64Url.decode(sealed['t']! as String);
      await box(_alice).put(
          'quotations_deleted_v1',
          json.encode({
            ...sealed,
            't': base64Url.encode([...tag]..[0] ^= 1)
          }));
      await restart();
      final reads = app.reads;
      final blocked = _Screen(app);
      await _until(() => blocked.errors.isNotEmpty);
      await _settle(app.server);
      expect(blocked.lists, isEmpty);
      expect(blocked.errors.single, isA<ListIntegrityBlocked>());
      expect(app.reads, reads);
      await blocked.close();
    });

    test('a damaged list reads as nothing; a verified server read recovers',
        () async {
      final app = await _App.start(rows: 2);
      await cache.write(_alice, [_full('old', _alice)]);
      final sealed = envelope(_alice);
      final tag = base64Url.decode(sealed['t']! as String);
      await box(_alice).put(
          'quotations_v2',
          json.encode({
            ...sealed,
            't': base64Url.encode([...tag]..[0] ^= 1)
          }));
      expect(await cache.read(_alice), isNull);
      final screen = _Screen(app);
      await _settle(app.server);
      expect(screen.lists.single, hasLength(2), reason: 'never the forged');
      expect(ids(await cache.read(_alice)), [_qid(2), _qid(1)]);
      await screen.close();
    });
  });

  // -----------------------------------------------------------------------
  group('what does not change', () {
    test('Home\'s getUserQuotations stays server-only and saves nothing',
        () async {
      final app = await _App.start(rows: 2);
      await cache.write(_alice, [_full('old', _alice)]);
      final before = box(_alice).get('quotations_v2');
      expect(ids(await app.quotations.getUserQuotations().first),
          [_qid(2), _qid(1)]);
      app.server.networkDown = true;
      await expectLater(app.quotations.getUserQuotations().first,
          throwsA(isA<QuotationException>()));
      await cache.debugSettled(_alice);
      expect(box(_alice).get('quotations_v2'), before);
    });

    test('a saved card opens its already-downloaded PDF with no request',
        () async {
      final app = await _App.start(rows: 2);
      final screen = _Screen(app);
      await _settle(app.server);
      await screen.close();
      await restart();
      final saved = (await cache.read(_alice))!.first; // Villa 2: has a PDF
      // Q-2c-1b: this device's copy is the account's encrypted one.
      await app.vault.store(_alice, saved.id!, saved.pdfMediaId!,
          Uint8List.fromList([37, 80, 68, 70]));
      app.server.networkDown = true;
      final requests = app.server.requests.length;
      final opened = await app.quotations.resolvePdfFile(saved);
      expect(opened.readAsBytesSync(), [37, 80, 68, 70]);
      expect(
          QuotationPdfVault.isViewingCopy(opened.path, app.dir.path), isTrue);
      expect(app.server.requests.length, requests);
      expect(saved.totalAmount, 120002.5, reason: 'the server value');
    });

    test('Delete Account removes this account\'s Quotations box and key only',
        () async {
      await cache.write(_alice, [_full('q1', _alice)]);
      await cache.write(_bob, [_full('b1', _bob)]);
      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);
      expect(
          await Hive.boxExists(QuotationsLocalCache.boxNameForUid(_alice),
              path: listsDir()),
          isFalse);
      expect(await secureKey(_alice), isNull);
      expect(await secureKey(_bob), isNotNull);
      expect(ids(await cache.read(_bob)), ['b1']);
    });
  });

  test('measurements: saved-copy size and time (test VM, not a device)',
      () async {
    final lines = <String>[];
    for (final count in [100, 1200, 10000, 20000]) {
      final list = [
        for (var n = count; n >= 1; n--)
          _full(_qid(n), _alice, total: 120000.5 + n)
      ];
      final write = Stopwatch()..start();
      await cache.write(_alice, list);
      write.stop();
      final bytes = utf8.encode(envelope(_alice)['p']! as String).length;
      await restart();
      final read = Stopwatch()..start();
      final back = await cache.read(_alice);
      read.stop();
      expect(back, hasLength(count));
      lines.add('quotations $count: payload $bytes B, write '
          '${write.elapsedMilliseconds} ms, cold read '
          '${read.elapsedMilliseconds} ms');
      await restart();
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _VaultKeys implements AccountCacheKeyStore {
  final Map<String, List<int>> keys = {};
  @override
  Future<List<int>?> read(String uid) async => keys[uid];
  @override
  Future<void> write(String uid, List<int> key) async => keys[uid] = key;
  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class _NoBackupGuard implements ScannerBackupGuard {
  @override
  Future<bool> exclude(String path) async => true;
}

class _UnavailableKeys implements AccountCacheKeyStore {
  @override
  Future<List<int>?> read(String uid) async =>
      throw PlatformException(code: 'keystore-unavailable');

  @override
  Future<void> write(String uid, List<int> key) async =>
      throw PlatformException(code: 'keystore-unavailable');

  @override
  Future<void> delete(String uid) async =>
      throw PlatformException(code: 'keystore-unavailable');
}
