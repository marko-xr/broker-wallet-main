// P4.4 (tracker §7AO), FU-FAV-META-EMPTY: the Favorites screen with the REAL
// FavoriteService metadata read (only its device cache is replaced) on a
// PostgREST-faithful stand-in. A metadata read that fails, or comes back
// empty under a session the database does not confirm, must never become
// "no favorites" — on screen or in the saved cache.
import 'dart:convert';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _session = '11111111-1111-4111-8111-111111111111';

String _offerId(int n) =>
    'c0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// favorite_offers rows: [offers] newest first; every other list empty.
class _Backend {
  _Backend(this.offers);

  List<String> offers;
  bool Function(String table, int page)? fail;
  void Function(String table, int page)? onPage;
  final List<http.Request> requests = [];
  final Map<String, int> pages = {};

  String _at(int i) => DateTime.utc(2026, 11, 1)
      .subtract(Duration(minutes: i))
      .toIso8601String()
      .replaceFirst('Z', '+00:00');

  late final sb.SupabaseClient client = sb.SupabaseClient(
    'https://unit-test.supabase.co',
    'unit-test-publishable-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      final table = request.url.pathSegments.last;
      final page = pages[table] = (pages[table] ?? 0) + 1;
      onPage?.call(table, page);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (fail?.call(table, page) ?? false) {
        return http.Response('{"message":"unavailable"}', 500,
            headers: {'content-type': 'application/json'}, request: request);
      }
      var rows = table == 'favorite_offers'
          ? [
              for (final (i, id) in offers.indexed)
                {'target_id': id, 'added_at': _at(i)}
            ]
          : <Map<String, String>>[];
      final total = rows.length;
      final or = request.url.queryParameters['or'];
      if (or != null) {
        final last = RegExp(r'target_id\.lt\.([0-9a-f-]+)').firstMatch(or)!;
        rows = rows
            .skipWhile((r) => r['target_id'] != last.group(1))
            .skip(1)
            .toList();
      }
      rows = rows.take(500).toList();
      final counting =
          (request.headers['Prefer'] ?? '').contains('count=exact');
      final range = rows.isEmpty
          ? '*/${counting ? total : '*'}'
          : '0-${rows.length - 1}/${counting ? total : '*'}';
      return http.Response(jsonEncode(rows), 200,
          headers: {'content-type': 'application/json', 'content-range': range},
          request: request);
    }),
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
}

/// The real metadata read; the device cache is a list in memory.
class _Service extends FavoriteService {
  _Service(_Backend backend, {this.cached = const []})
      : super(
          client: backend.client,
          currentUserId: () => _uid,
          currentSessionId: () => _session,
        );

  final List<FavoriteItem> cached;
  final List<List<FavoriteItem>> cacheWrites = [];

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() => List.of(cached);

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {
    cacheWrites.add(List.of(favorites));
  }
}

class _Offers extends OfferService {
  @override
  Future<List<OfferModel>> getOffersByIds(
    List<String> offerIds, {
    bool Function()? stop,
  }) async =>
      [for (final id in offerIds) _offer(id)];
}

OfferModel _offer(String id) {
  final now = DateTime(2026, 1, 1);
  return OfferModel(
    id: id,
    userId: _uid,
    offerType: 'rent',
    selectedCity: 'Dubai',
    selectedAreas: const ['Marina'],
    location: 'Dubai Marina',
    phoneNumber: '500000000',
    countryCode: '+971',
    minPrice: '1000',
    maxPrice: '2000',
    notes: '',
    specificPropertyType: 'Apartment',
    rooms: 1,
    bathrooms: 1,
    pickUpLocation: '',
    pickUpLatitude: 0,
    pickUpLongitude: 0,
    pickUpAddress: '',
    uploadedFileName: '',
    createdAt: now,
    updatedAt: now,
    mediaUrls: const [],
  );
}

FavoriteItem _card(String id, int minutesAgo) => FavoriteItem(
      id: id,
      type: 'offers',
      title: 'Offer $id',
      subtitle: '',
      addedAt:
          DateTime.utc(2026, 11, 1).subtract(Duration(minutes: minutesAgo)),
    );

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 400; i++) {
    if (done()) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> _shown(FavoritesViewModel vm) =>
    [for (final f in vm.displayFavorites) f.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool? confirmAnswer;
  setUp(() {
    confirmAnswer = true;
    ListSessionCheck.debugOverride =
        (_) => confirmAnswer == null ? null : Future<bool>.value(confirmAnswer);
  });
  tearDown(() => ListSessionCheck.debugOverride = null);

  FavoritesViewModel build(_Service service) =>
      FavoritesViewModel(favoriteService: service, offerService: _Offers());

  test(
      'first visit, one type cannot be read: the screen\'s error state, not '
      '"no favorites", and nothing is saved', () async {
    final backend = _Backend([_offerId(1)])
      ..fail = (t, _) => t == 'favorite_owners';
    final service = _Service(backend);
    final vm = build(service);
    await _settle(() => !vm.isLoading && backend.requests.length >= 6);

    expect(vm.error, isNotNull, reason: 'was null: shown as "no favorites"');
    expect(vm.displayFavorites, isEmpty);
    expect(service.cacheWrites, isEmpty, reason: 'was [[]]: cache emptied');
    vm.dispose();
  });

  test(
      'cards on screen and a refresh that cannot read the list: the cards '
      'stay and the saved cache is not replaced', () async {
    final backend = _Backend([_offerId(1), _offerId(2)])
      ..fail = (t, _) => t == 'favorite_requests';
    final service = _Service(backend,
        cached: [_card(_offerId(1), 0), _card(_offerId(2), 1)]);
    final vm = build(service);
    await _settle(() => backend.requests.length >= 6);

    expect(_shown(vm), [_offerId(1), _offerId(2)]);
    expect(service.cacheWrites, isEmpty, reason: 'was [[]]');

    backend.requests.clear();
    await vm.refresh();
    expect(_shown(vm), [_offerId(1), _offerId(2)]);
    expect(service.cacheWrites, isEmpty);
    vm.dispose();
  });

  test(
      'every list empty under a session the database does not confirm: not '
      '"no favorites", and the cards on screen stay', () async {
    confirmAnswer = false;
    final backend = _Backend(const []);
    final service = _Service(backend, cached: [_card(_offerId(1), 0)]);
    final vm = build(service);
    await _settle(() => backend.requests.length >= 6);

    expect(_shown(vm), [_offerId(1)]);
    expect(service.cacheWrites, isEmpty, reason: 'was [[]]');
    vm.dispose();
  });

  test(
      'a page after the first that cannot be read: the cards stay, nothing '
      'is saved', () async {
    final ids = [for (var i = 0; i < 600; i++) _offerId(i)];
    final backend = _Backend(ids)
      ..fail = (t, p) => t == 'favorite_offers' && p == 2;
    final service = _Service(backend, cached: [_card(_offerId(0), 0)]);
    final vm = build(service);
    await _settle(() => (backend.pages['favorite_offers'] ?? 0) >= 2);

    expect(_shown(vm), [_offerId(0)]);
    expect(service.cacheWrites, isEmpty);
    vm.dispose();
  });

  test(
      'after a failed first visit, a refresh that the database confirms empty '
      'shows "no favorites" and saves it', () async {
    final backend = _Backend(const [])..fail = (t, _) => true;
    final service = _Service(backend);
    final vm = build(service);
    await _settle(() => !vm.isLoading && backend.requests.length >= 6);
    expect(vm.error, isNotNull);

    backend.fail = null;
    await vm.refresh();
    expect(vm.error, isNull, reason: 'a confirmed answer replaces the error');
    expect(vm.hasNoFavorites, isTrue);
    expect(service.cacheWrites, [isEmpty]);
    vm.dispose();
  });

  test('600 favorites: every card, in order, one batched record read',
      () async {
    final ids = [for (var i = 0; i < 600; i++) _offerId(i)];
    final backend = _Backend(ids);
    final service = _Service(backend);
    final vm = build(service);
    await _settle(() => !vm.isLoading && service.cacheWrites.isNotEmpty);

    expect(_shown(vm), ids);
    expect(vm.error, isNull);
    expect(service.cacheWrites.single.map((f) => f.id), ids);
    expect(backend.pages['favorite_offers'], 2);
    vm.dispose();
  });

  test(
      'closed while page 1 is in flight: no further page and no session '
      'check are asked for, nothing is saved', () async {
    final ids = [for (var i = 0; i < 1200; i++) _offerId(i)];
    final backend = _Backend(ids);
    final service = _Service(backend);
    late FavoritesViewModel vm;
    var asked = 0;
    ListSessionCheck.debugOverride = (_) {
      asked++;
      return Future<bool>.value(true);
    };
    backend.onPage = (table, page) {
      if (table == 'favorite_offers' && page == 1) vm.dispose();
    };
    vm = build(service);
    await _settle(() => false);

    expect(backend.pages['favorite_offers'], 1,
        reason: 'was 3: pages kept '
            'being read for a closed screen');
    expect(asked, 0, reason: 'was 1');
    expect(service.cacheWrites, isEmpty);

    // The same service still reads whole afterwards (a new read).
    backend.onPage = null;
    final read = await service.getAllFavoritesWithMetadata();
    expect(read['offers'], hasLength(1200));
  });

  test('closed while the list is read: nothing is shown or saved later',
      () async {
    final backend = _Backend([_offerId(1)]);
    final service = _Service(backend);
    final vm = build(service);
    var notified = 0;
    vm.addListener(() => notified++);
    vm.dispose();
    await _settle(() => backend.requests.length >= 6);
    expect(service.cacheWrites, isEmpty);
    expect(notified, 0);
  });
}
