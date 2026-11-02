// P2.5b-2: the offline lists also read again when the network comes back —
// one shared connectivity listener, a hint only on "no network → network",
// debounced, and every list keeps its own guards (one read at a time, the
// foreground only, the signed-in account only, nothing after closing).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _none = [ConnectivityResult.none];
const _wifi = [ConnectivityResult.wifi];
const _mobile = [ConnectivityResult.mobile];
const _debounce = Duration(milliseconds: 30);
final _when = DateTime.utc(2026);

RequestModel _request(String id) => RequestModel(
      id: id,
      userId: _alice,
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

/// The device's connectivity, driven by the test.
class _Network {
  final controller = StreamController<List<ConnectivityResult>>.broadcast();
  int subscriptions = 0;

  Stream<List<ConnectivityResult>> call() {
    subscriptions++;
    return controller.stream;
  }

  void report(List<ConnectivityResult> state) => controller.add(state);
}

/// A server whose every read is answered by the test.
class _Server {
  final List<StreamController<List<RequestModel>>> reads = [];
  int get count => reads.length;
  StreamController<List<RequestModel>> get last => reads.last;

  Stream<List<RequestModel>> call() {
    final read = StreamController<List<RequestModel>>();
    reads.add(read);
    return read.stream;
  }

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

Future<void> _settle([int ms = 100]) async {
  await pumpEventQueue();
  await Future<void>.delayed(Duration(milliseconds: ms));
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
    root = Directory.systemTemp.createTempSync('list_connectivity_test');
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

  ({ListRefreshSignals signals, _Network network}) newSignals() {
    final network = _Network();
    addTearDown(network.controller.close);
    return (
      signals: ListRefreshSignals.forTesting(
        connectivity: network.call,
        reconnectDebounce: _debounce,
      ),
      network: network,
    );
  }

  /// Counts the hints [signals] sends while the test listens.
  List<int> countHints(ListRefreshSignals signals) {
    final count = [0];
    final listening = signals.hints.listen((_) => count[0]++);
    addTearDown(listening.cancel);
    return count;
  }

  // ---------------------------------------------------------------------
  group('the shared connectivity signal', () {
    test(
        'the state at subscription is not a hint; "none → network" is, '
        'once', () async {
      final s = newSignals();
      final hints = countHints(s.signals);
      s.network.report(_wifi);
      await _settle();
      expect(hints[0], 0, reason: 'online at subscription: no change');

      s.network.report(_none);
      s.network.report(_wifi);
      await _settle();
      expect(hints[0], 1);
    });

    test('moving between networks is not a return', () async {
      final s = newSignals();
      final hints = countHints(s.signals);
      s.network.report(_wifi);
      s.network.report(_mobile);
      s.network.report([ConnectivityResult.wifi, ConnectivityResult.mobile]);
      await _settle();
      expect(hints[0], 0);
    });

    test('rapid drops and returns within the debounce count once', () async {
      final s = newSignals();
      final hints = countHints(s.signals);
      s.network.report(_none);
      for (var i = 0; i < 5; i++) {
        s.network.report(_wifi);
        s.network.report(_none);
        s.network.report(_mobile);
      }
      await _settle();
      expect(hints[0], 1);
    });

    test('a return that drops again before the debounce ends is no hint',
        () async {
      final s = newSignals();
      final hints = countHints(s.signals);
      s.network.report(_none);
      s.network.report(_wifi);
      s.network.report(_none);
      await _settle();
      expect(hints[0], 0);
    });

    test(
        'one connectivity subscription for every listener, dropped with the '
        'last one; a new one starts from an unknown state', () async {
      final s = newSignals();
      final a = s.signals.hints.listen((_) {});
      final b = s.signals.hints.listen((_) {});
      expect(s.network.subscriptions, 1);
      expect(s.network.controller.hasListener, isTrue);
      s.network.report(_none); // offline when the lists close
      await _settle();
      await a.cancel();
      expect(s.network.controller.hasListener, isTrue);
      await b.cancel();
      expect(s.network.controller.hasListener, isFalse);

      final hints = countHints(s.signals);
      expect(s.network.subscriptions, 2);
      s.network.report(_wifi);
      await _settle();
      expect(hints[0], 0, reason: 'first event after re-attaching');
    });

    test('a pending return is dropped when the last listener leaves', () async {
      final s = newSignals();
      var hints = 0;
      final listening = s.signals.hints.listen((_) => hints++);
      s.network.report(_none);
      s.network.report(_wifi);
      await pumpEventQueue(); // the return is seen; its debounce is running
      await listening.cancel();
      // A list opened before the old debounce would have ended.
      final next = countHints(s.signals);
      await _settle();
      expect(hints, 0);
      expect(next[0], 0, reason: 'no stale return for the new listener');
    });

    test(
        'a failing connectivity source sends no hints and does not stop '
        'resume hints', () async {
      final s = newSignals();
      final hints = countHints(s.signals);
      s.network.controller.addError(StateError('no plugin'));
      await _settle();
      s.signals.debugResume();
      await _settle();
      expect(hints[0], 1);
    });

    test('without useConnectivity there is no connectivity subscription',
        () async {
      final signals =
          ListRefreshSignals.forTesting(reconnectDebounce: _debounce);
      final network = _Network();
      addTearDown(network.controller.close);
      final hints = countHints(signals);
      expect(network.subscriptions, 0);

      signals.useConnectivity(network.call);
      expect(network.subscriptions, 1, reason: 'starts at once when needed');
      network.report(_none);
      network.report(_wifi);
      await _settle();
      expect(hints[0], 1);
    });
  });

  // ---------------------------------------------------------------------
  group('a list, when the network comes back', () {
    ({
      _Server server,
      _Clock clock,
      List<List<String?>> shown,
      List<Object> errors,
      StreamSubscription<List<RequestModel>> subscription,
    }) open(
      ListRefreshSignals signals, {
      String? Function()? signedIn,
      bool Function()? active,
      List<Duration> retryDelays = const [
        Duration(milliseconds: 30),
        Duration(milliseconds: 60),
      ],
    }) {
      final server = _Server();
      final clock = _Clock();
      final shown = <List<String?>>[];
      final errors = <Object>[];
      final subscription = localFirstList<RequestModel>(
        server: server.call,
        cache: cache,
        currentUserId: signedIn ?? () => _alice,
        refreshSignals: signals.hints,
        retryDelays: retryDelays,
        now: clock.call,
        isAppActive: active,
      ).listen((items) => shown.add(items.map((r) => r.id).toList()),
          onError: errors.add);
      addTearDown(subscription.cancel);
      return (
        server: server,
        clock: clock,
        shown: shown,
        errors: errors,
        subscription: subscription,
      );
    }

    /// Fails the first read and every retry, so the retries are used up.
    Future<void> exhaust(_Server server) async {
      await _until(() => server.count == 1);
      await server.failLast();
      await _until(() => server.count == 2);
      await server.failLast();
      await _until(() => server.count == 3);
      await server.failLast();
      await _settle(150);
      expect(server.count, 3, reason: 'retries used up');
    }

    test(
        'after the retries are used up, the return reads once; the list '
        'arrives and is saved as v2', () async {
      final s = newSignals();
      final list = open(s.signals);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await exhaust(list.server);

      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _until(() => list.server.count == 4, 'read on return');
      list.server.last.add([_request('s1')]);
      await _settle();
      expect(list.shown.last, ['s1']);
      expect((await cache.read(_alice))?.map((r) => r.id), ['s1']);
      final stored = Hive.box<String>(RequestsLocalCache.boxNameForUid(_alice))
          .get('requests_v2');
      expect((json.decode(stored!) as Map)['v'], 2);
      expect(list.server.count, 4, reason: 'exactly one read');
    });

    test(
        'opening the list sends no extra read for the state at '
        'subscription', () async {
      final s = newSignals();
      final list = open(s.signals);
      await _until(() => list.server.count == 1);
      s.network.report(_wifi);
      list.server.last.add([_request('s1')]);
      await _settle();
      s.network.report(_mobile);
      await _settle();
      expect(list.server.count, 1);
    });

    test('a fresh list is not read again when the network returns', () async {
      final s = newSignals();
      final list = open(s.signals);
      await _until(() => list.server.count == 1);
      s.network.report(_wifi);
      list.server.last.add([_request('s1')]);
      await _settle();
      list.clock.advance(const Duration(seconds: 10));
      s.network.report(_none);
      s.network.report(_wifi);
      await _settle();
      expect(list.server.count, 1, reason: 'read 10 s ago');
    });

    test('rapid connectivity changes cause one read, never two at once',
        () async {
      final s = newSignals();
      final list = open(s.signals, retryDelays: const []);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await list.server.failLast();
      await _settle();

      list.clock.advance(const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        s.network.report(_wifi);
        s.network.report(_none);
      }
      s.network.report(_mobile);
      await _settle();
      expect(list.server.count, 2);

      // Another return while that read is still in flight.
      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_none);
      s.network.report(_wifi);
      await _settle();
      expect(list.server.count, 2, reason: 'one read in flight');
    });

    test('lists open together share the one signal and each reads once',
        () async {
      final s = newSignals();
      final first = open(s.signals, retryDelays: const []);
      final second = open(s.signals, retryDelays: const []);
      await _until(() => first.server.count == 1 && second.server.count == 1);
      expect(s.network.subscriptions, 1, reason: "one listener for both");
      s.network.report(_none);
      await first.server.failLast();
      await second.server.failLast();
      await _settle();

      first.clock.advance(const Duration(seconds: 5));
      second.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _settle();
      expect(first.server.count, 2);
      expect(second.server.count, 2);
    });

    test('in the background the return reads nothing; the resume does',
        () async {
      final s = newSignals();
      var active = true;
      final list = open(s.signals, active: () => active, retryDelays: const []);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await list.server.failLast();
      await _settle();

      active = false;
      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _settle();
      expect(list.server.count, 1, reason: 'in the background');

      active = true;
      s.signals.debugResume();
      await _until(() => list.server.count == 2, 'resume reads');
    });

    test('account switch or logout: the return reads nothing', () async {
      for (final next in <String?>[_bob, null]) {
        final s = newSignals();
        String? signedIn = _alice;
        final list =
            open(s.signals, signedIn: () => signedIn, retryDelays: const []);
        await _until(() => list.server.count == 1);
        s.network.report(_none);
        await list.server.failLast();
        await _settle();

        signedIn = next;
        list.clock.advance(const Duration(seconds: 5));
        s.network.report(_wifi);
        await _settle();
        expect(list.server.count, 1, reason: 'signed in: $next');
        expect(list.shown, isEmpty);
      }
    });

    test(
        'a failed read after the return keeps the saved list; the failure '
        'is not passed on again', () async {
      await cache.write(_alice, [_request('saved')]);
      final s = newSignals();
      final list = open(s.signals, retryDelays: const []);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await list.server.failLast();
      await _settle();
      expect(list.errors, hasLength(1));

      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi); // connected, but no Internet yet
      await _until(() => list.server.count == 2);
      await list.server.failLast(TimeoutException('no route'));
      await _settle();
      expect(list.shown, [
        ['saved']
      ]);
      expect(list.errors, hasLength(1));
      expect((await cache.read(_alice))?.map((r) => r.id), ['saved']);
    });

    test('a refused session stops the list: later returns read nothing',
        () async {
      final s = newSignals();
      final list = open(s.signals);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await list.server.failLast(Exception('session_superseded'));
      await _settle();

      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _settle();
      s.network.report(_none);
      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _settle();
      expect(list.server.count, 1);
    });

    test('a closed screen reads nothing and drops the connectivity listener',
        () async {
      final s = newSignals();
      final list = open(s.signals);
      await _until(() => list.server.count == 1);
      s.network.report(_none);
      await list.server.failLast();
      await list.subscription.cancel();
      expect(s.network.controller.hasListener, isFalse);

      list.clock.advance(const Duration(seconds: 5));
      s.network.report(_wifi);
      await _settle(200);
      expect(list.server.count, 1);
    });
  });
}
