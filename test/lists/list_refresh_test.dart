// P2.5b: the offline lists read again by themselves — after a network
// failure (bounded retries) and when the app resumes — without losing the
// list on screen, without extra or overlapping reads, and never for an
// account that has gone or a session the server refused.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/entity_list_state.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_brokers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offices_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
final _when = DateTime.utc(2026);

RequestModel _request(String id, [String owner = _alice]) => RequestModel(
      id: id,
      userId: owner,
      requestType: 'rent',
      selectedCity: '',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: '',
      rooms: 0,
      bathrooms: 0,
      createdAt: _when,
      updatedAt: _when,
    );

/// A server whose every read is answered by the test.
class _Server<T> {
  final List<StreamController<List<T>>> reads = [];
  int get count => reads.length;
  StreamController<List<T>> get last => reads.last;

  Stream<List<T>> call() {
    final read = StreamController<List<T>>();
    reads.add(read);
    return read.stream;
  }

  /// A first read failing as the app's server stream does: error, then end.
  Future<void> failLast(
      [Object error = const SocketException('offline')]) async {
    last.addError(error);
    await last.close();
  }
}

class _Clock {
  DateTime value = DateTime.utc(2026, 1, 1, 12);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

Future<void> _settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await pumpEventQueue();
}

Future<void> _until(bool Function() done, [String what = 'condition']) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: what);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const cache = RequestsLocalCache();

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('list_refresh_test');
    Hive.init(root.path);
    EncryptedAccountListCache.debugStorageRoot = root.path;
  });

  tearDownAll(() async {
    await Hive.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final entity in root.listSync()) {
      for (var attempt = 0;; attempt++) {
        try {
          entity.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
  });

  /// One screen's list, its events, and the controls the test drives it by.
  ({
    _Server<RequestModel> server,
    StreamController<void> hints,
    _Clock clock,
    List<List<String?>> shown,
    List<Object> errors,
    StreamSubscription<List<RequestModel>> subscription,
  }) open({
    String? Function()? signedIn,
    bool Function()? active,
    List<Duration> retryDelays = const [
      Duration(milliseconds: 30),
      Duration(milliseconds: 60),
    ],
  }) {
    final server = _Server<RequestModel>();
    final hints = StreamController<void>.broadcast();
    final clock = _Clock();
    final shown = <List<String?>>[];
    final errors = <Object>[];
    final subscription = localFirstList<RequestModel>(
      server: server.call,
      cache: cache,
      currentUserId: signedIn ?? () => _alice,
      refreshSignals: hints.stream,
      retryDelays: retryDelays,
      now: clock.call,
      isAppActive: active,
    ).listen((items) => shown.add(items.map((r) => r.id).toList()),
        onError: errors.add);
    addTearDown(subscription.cancel);
    addTearDown(hints.close);
    return (
      server: server,
      hints: hints,
      clock: clock,
      shown: shown,
      errors: errors,
      subscription: subscription,
    );
  }

  Future<List<String?>?> saved() async =>
      (await cache.read(_alice))?.map((r) => r.id).toList();

  // ---------------------------------------------------------------------
  group('after a network failure', () {
    test(
        'a failed first read retries on its own and the list arrives, saved '
        'as an authenticated v2 list', () async {
      final list = open();
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _until(() => list.server.count == 2, 'a retry');

      list.server.last.add([_request('s1')]);
      await _settle();
      expect(list.shown.last, ['s1']);
      expect(await saved(), ['s1']);
      final stored = Hive.box<String>(RequestsLocalCache.boxNameForUid(_alice))
          .get('requests_v2');
      expect((json.decode(stored!) as Map)['v'], 2);
    });

    test(
        'the saved list stays on screen through failed retries, and the '
        'failure is passed on once', () async {
      await cache.write(_alice, [_request('saved')]);
      final list = open();
      await _until(() => list.server.count == 1);
      expect(list.shown, [
        ['saved']
      ]);

      await list.server.failLast();
      await _until(() => list.server.count == 2);
      await list.server.failLast();
      await _until(() => list.server.count == 3);
      await list.server.failLast();
      await _settle();

      expect(
          list.shown,
          [
            ['saved']
          ],
          reason: 'nothing replaced or cleared the saved list');
      expect(list.errors, hasLength(1));
      expect(await saved(), ['saved'], reason: 'the saved copy is kept');
    });

    test(
        'retries are bounded: one read per retry delay, then none until the '
        'app resumes', () async {
      final list = open();
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _until(() => list.server.count == 2);
      await list.server.failLast();
      await _until(() => list.server.count == 3);
      await list.server.failLast();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(list.server.count, 3, reason: 'two delays, two retries, no more');

      list.clock.advance(const Duration(minutes: 1));
      list.hints.add(null);
      await _until(() => list.server.count == 4, 'resume reads again');
    });

    test(
        'an authoritative empty list after a failure is shown and saved as '
        'empty', () async {
      await cache.write(_alice, [_request('saved')]);
      final list = open();
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _until(() => list.server.count == 2);
      list.server.last.add(const []);
      await _settle();
      expect(list.shown.last, isEmpty);
      expect(await saved(), isEmpty);
    });
  });

  group('when the app resumes', () {
    test('a list read long enough ago is read again; a fresh one is not',
        () async {
      final list = open();
      await _until(() => list.server.count == 1);
      list.server.last.add([_request('s1')]);
      await _settle();

      list.clock.advance(const Duration(seconds: 10));
      list.hints.add(null);
      await _settle();
      expect(list.server.count, 1, reason: 'read 10 s ago: still fresh');

      list.clock.advance(const Duration(seconds: 30));
      list.hints.add(null);
      await _until(() => list.server.count == 2, 'stale: read again');
      list.server.last.add([_request('s1'), _request('s2')]);
      await _settle();
      expect(list.shown.last, ['s1', 's2']);
      expect(await saved(), ['s1', 's2']);
    });

    test('rapid hints cause one read, and never two at once', () async {
      final list = open(retryDelays: const []);
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _settle();

      list.clock.advance(const Duration(seconds: 5));
      for (var i = 0; i < 6; i++) {
        list.hints.add(null);
      }
      await _settle();
      expect(list.server.count, 2, reason: 'one read for the burst');

      list.clock.advance(const Duration(seconds: 5));
      list.hints.add(null);
      await _settle();
      expect(list.server.count, 2, reason: 'the read is still in flight');
    });

    test('hints closer together than the gap count once', () async {
      final list = open(retryDelays: const []);
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _settle();
      list.clock.advance(const Duration(seconds: 5));
      list.hints.add(null);
      await _until(() => list.server.count == 2);
      await list.server.failLast();
      list.clock.advance(const Duration(seconds: 1));
      list.hints.add(null);
      await _settle();
      expect(list.server.count, 2, reason: 'within 2 s of the last read');
    });

    test('an identical list is not shown again', () async {
      final list = open();
      await _until(() => list.server.count == 1);
      list.server.last.add([_request('s1')]);
      await _settle();
      list.clock.advance(const Duration(minutes: 1));
      list.hints.add(null);
      await _until(() => list.server.count == 2);
      list.server.last.add([_request('s1')]);
      await _settle();
      expect(list.shown, [
        ['s1']
      ]);
    });
  });

  group('in the background', () {
    test(
        'a retry falling due in the background reads nothing; the resume '
        'reads instead', () async {
      var active = true;
      final list = open(active: () => active);
      await _until(() => list.server.count == 1);
      active = false;
      await list.server.failLast();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(list.server.count, 1, reason: 'no read while in the background');

      active = true;
      list.clock.advance(const Duration(seconds: 5));
      list.hints.add(null);
      await _until(() => list.server.count == 2, 'resume reads');
      list.server.last.add([_request('s1')]);
      await _settle();
      expect(list.shown.last, ['s1']);
    });

    test(
        'with retries used up in the foreground, nothing reads again until '
        'the app resumes (no "network is back" signal)', () async {
      final list = open();
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await _until(() => list.server.count == 2);
      await list.server.failLast();
      await _until(() => list.server.count == 3);
      await list.server.failLast();
      // The network "returns" here; nothing tells the list.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(list.server.count, 3);
      expect(list.errors, hasLength(1));
    });
  });

  group('never for a refused session or an account that has gone', () {
    for (final refused in <Object>[
      StateError('A Supabase session is required.'),
      Exception('session_superseded'),
    ]) {
      test(
          'a non-network failure (${refused.runtimeType}) stops retries and '
          'resume reads', () async {
        final list = open();
        await _until(() => list.server.count == 1);
        await list.server.failLast(refused);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        list.clock.advance(const Duration(minutes: 5));
        list.hints.add(null);
        await _settle();
        expect(list.server.count, 1);
        expect(list.errors, [refused]);
      });
    }

    test(
        'account switch: a pending retry reads nothing, and a late answer '
        'is neither shown nor saved', () async {
      String? signedIn = _alice;
      final list = open(signedIn: () => signedIn);
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      signedIn = _bob;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(list.server.count, 1, reason: 'the retry found another account');

      // A read in flight when the account changes.
      signedIn = _alice;
      final second = open(signedIn: () => signedIn);
      await _until(() => second.server.count == 1);
      signedIn = _bob;
      second.server.last.add([_request('late')]);
      await _settle();
      expect(second.shown, isEmpty);
      expect(await saved(), isNull);
    });

    test('logout: no reads after the account is signed out', () async {
      String? signedIn = _alice;
      final list = open(signedIn: () => signedIn);
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      signedIn = null;
      list.clock.advance(const Duration(minutes: 1));
      list.hints.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(list.server.count, 1);
    });

    test('a closed screen reads nothing more and its late answer is dropped',
        () async {
      final list = open();
      await _until(() => list.server.count == 1);
      await list.server.failLast();
      await list.subscription.cancel();
      list.clock.advance(const Duration(minutes: 1));
      list.hints.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(list.server.count, 1, reason: 'no retry, no resume read');
      expect(list.hints.hasListener, isFalse);
    });
  });

  // ---------------------------------------------------------------------
  group('the six list screens, with the shared refresh signal', () {
    Future<void> check<T>({
      required String name,
      required ChangeNotifier Function(String? Function() signedIn) open,
      required _Server<T> server,
      required T item,
      required Future<void> Function() hint,
    }) async {
      final vm = open(() => _alice);
      final list = vm as EntityListState<T>;
      addTearDown(vm.dispose);
      await _until(() => server.count == 1, '$name first read');
      await server.failLast();
      await _settle();
      expect(list.hasLoadError, isTrue, reason: '$name: nothing saved yet');

      // Hints within 2 s of a read count once; wait past that.
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await hint();
      await _until(() => server.count == 2, '$name read on the hint');
      server.last.add([item]);
      await _settle();
      expect(list.hasLoadError, isFalse, reason: name);
      expect(list.entities, hasLength(1), reason: name);
    }

    Future<void> six(Future<void> Function() hint) async {
      final requests = _Server<RequestModel>();
      await check(
        hint: hint,
        name: 'Requests',
        server: requests,
        item: _request('r1'),
        open: (who) => RequestedListViewModel(
            requestService: _RequestService(requests, who)),
      );
      final offers = _Server<OfferModel>();
      await check(
        hint: hint,
        name: 'Offers',
        server: offers,
        item: OfferModel(
          id: 'o1',
          userId: _alice,
          offerType: 'sell',
          selectedCity: '',
          selectedAreas: const [],
          location: '',
          phoneNumber: '',
          countryCode: '+971',
          minPrice: '',
          maxPrice: '',
          notes: '',
          specificPropertyType: '',
          rooms: 0,
          bathrooms: 0,
          pickUpLocation: '',
          pickUpLatitude: null,
          pickUpLongitude: null,
          pickUpAddress: '',
          uploadedFileName: '',
          createdAt: _when,
          updatedAt: _when,
          mediaUrls: const [],
        ),
        open: (who) =>
            OffersListViewModel(offerService: _OfferService(offers, who)),
      );
      final owners = _Server<OwnerModel>();
      await check(
        hint: hint,
        name: 'Owners',
        server: owners,
        item: OwnerModel(
          id: 'w1',
          userId: _alice,
          name: '',
          phoneNumber: '',
          countryCode: '+971',
          typeOfProperties: '',
          propertyLocation: '',
          notes: '',
          pickUpLocation: '',
          pickUpLatitude: null,
          pickUpLongitude: null,
          pickUpAddress: '',
          mediaUrls: const [],
          createdAt: _when,
          updatedAt: _when,
        ),
        open: (who) =>
            OwnersListViewModel(ownerService: _OwnerService(owners, who)),
      );
      final offices = _Server<OfficeModel>();
      await check(
        hint: hint,
        name: 'Offices',
        server: offices,
        item: OfficeModel(
          id: 'f1',
          userId: _alice,
          officeName: '',
          managerName: '',
          countryCode: '+971',
          phoneNumber: '',
          officeLocation: '',
          notes: '',
          pickUpLocation: '',
          pickUpAddress: '',
        ),
        open: (who) =>
            OfficesListViewModel(officeService: _OfficeService(offices, who)),
      );
      final brokers = _Server<BrokerModel>();
      await check(
        hint: hint,
        name: 'Brokers',
        server: brokers,
        item: BrokerModel(
          id: 'b1',
          userId: _alice,
          name: '',
          countryCode: '+971',
          phoneNumber: '',
          notes: '',
          createdAt: _when,
        ),
        open: (who) =>
            BrokersListViewModel(brokerService: _BrokerService(brokers, who)),
      );
      final watchmen = _Server<WatchmenModel>();
      await check(
        hint: hint,
        name: 'Watchmen',
        server: watchmen,
        item: WatchmenModel(
          id: 'm1',
          userId: _alice,
          name: '',
          countryCode: '+971',
          phoneNumber: '',
          buildingName: '',
          notes: '',
          buildingLocation: '',
          pickUpLocation: '',
          pickUpAddress: '',
        ),
        open: (who) => WatchmenListViewModel(
            watchmenService: _WatchmenService(watchmen, who)),
      );
    }

    test('each list recovers from a failed first read when the app resumes',
        () => six(() async => ListRefreshSignals.instance.debugResume()));

    test(
        'each list recovers when the network comes back, through the one '
        'shared connectivity listener', () async {
      final network = StreamController<List<ConnectivityResult>>.broadcast();
      addTearDown(network.close);
      var subscriptions = 0;
      ListRefreshSignals.instance.useConnectivity(() {
        subscriptions++;
        return network.stream;
      });
      await six(() async {
        network.add(const [ConnectivityResult.none]);
        network.add(const [ConnectivityResult.wifi]);
      });
      expect(subscriptions, 1, reason: 'one listener for the six lists');
    });
  });
}

class _RequestService extends RequestService {
  _RequestService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<RequestModel> server;
  @override
  Stream<List<RequestModel>> getUserRequests() => server();
}

class _OfferService extends OfferService {
  _OfferService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<OfferModel> server;
  @override
  Stream<List<OfferModel>> getUserOffers() => server();
}

class _OwnerService extends OwnerService {
  _OwnerService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<OwnerModel> server;
  @override
  Stream<List<OwnerModel>> getUserOwners() => server();
}

class _OfficeService extends OfficeService {
  _OfficeService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<OfficeModel> server;
  @override
  Stream<List<OfficeModel>> getUserOffices() => server();
}

class _BrokerService extends BrokerService {
  _BrokerService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<BrokerModel> server;
  @override
  Stream<List<BrokerModel>> getUserBrokers() => server();
}

class _WatchmenService extends WatchmenService {
  _WatchmenService(this.server, String? Function() who)
      : super(currentUserId: who);
  final _Server<WatchmenModel> server;
  @override
  Stream<List<WatchmenModel>> getUserWatchmen() => server();
}
