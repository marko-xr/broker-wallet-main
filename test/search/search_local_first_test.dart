// P4.5a: Search answers from this account's saved (encrypted) lists first,
// then from the server.
//
// Part 1 drives SearchViewModel with a data source the test controls.
// Part 2 drives the real DefaultSearchDataSource against the real encrypted
// list caches (Hive in a temporary directory, the secure-storage test store)
// and server lists the test controls.
import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_data_source.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_engine.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_fixtures.dart';

const _all = {
  SearchResultType.request,
  SearchResultType.offer,
  SearchResultType.owner,
  SearchResultType.office,
  SearchResultType.broker,
  SearchResultType.watchmen,
};

SearchData _six({String owner = 'Ahmed Saeed', String prefix = ''}) =>
    SearchData(
      requests: [request(id: '${prefix}r1', specific: 'Penthouse Request')],
      offers: [offer(id: '${prefix}f1', specific: 'Villa Offer')],
      owners: [owner_(id: '${prefix}o1', name: owner)],
      offices: [office(id: '${prefix}c1', name: 'Marina Office')],
      brokers: [broker(id: '${prefix}b1', name: 'Broker Khalid')],
      watchmen: [watchman(id: '${prefix}w1', name: 'Watchman Ali')],
    );

// `owner` is also a named parameter above; keep the fixture reachable.
OwnerModel owner_({String? id, String name = ''}) => owner(id: id, name: name);

/// A data source the test drives, with the local-first capability.
class _Source implements SearchDataSource, LocalFirstSearchSource {
  _Source({required this.server, required this.saved});

  SearchData server;
  SavedSearchData saved;
  String? userId = 'u1';
  String? session = 's1';

  /// Saved data per account, when a test switches accounts.
  final Map<String, SavedSearchData> savedFor = {};

  Object? serverFailure;
  bool manual = false;
  final List<Completer<SearchData>> pending = [];

  int loads = 0;
  int savedLoads = 0;
  int cancels = 0;

  @override
  String? get currentUserId => userId;

  @override
  String? get currentSessionId => session;

  @override
  Future<SearchData> load() {
    loads++;
    final failure = serverFailure;
    if (failure != null) return Future<SearchData>.error(failure);
    if (manual) {
      final c = Completer<SearchData>();
      pending.add(c);
      return c.future;
    }
    return Future<SearchData>.value(server);
  }

  @override
  Future<SavedSearchData> loadSaved() async {
    savedLoads++;
    final uid = userId;
    if (uid == null) return SavedSearchData.none;
    return savedFor[uid] ?? saved;
  }

  @override
  void cancelReads() {
    cancels++;
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('read cancelled'));
    }
    pending.clear();
  }
}

List<String> _keys(SearchViewModel vm) =>
    [for (final r in vm.searchResults) r.stableKey];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchViewModel — saved copy first', () {
    late DateTime now;
    SearchViewModel vmFor(_Source source) {
      final vm = SearchViewModel(
        dataSource: source,
        engine: newEngine(),
        debounce: const Duration(milliseconds: 5),
        dataChanges: const Stream<void>.empty(),
        clock: () => now,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    Future<void> search(SearchViewModel vm, String q) async {
      vm.submitQuery(q);
      await pumpEventQueue();
    }

    setUp(() => now = DateTime(2026, 11, 5, 9));

    test('offline: the saved records answer, no error', () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      await search(vm, 'ahmed');

      expect(_keys(vm), hasLength(1));
      expect(vm.searchResults.single.type, SearchResultType.owner);
      expect(vm.errorKind, isNull);
      expect(vm.resultsFromSavedCopy, isTrue);
      expect(source.loads, 1);
    });

    test('no saved copy and offline: the network error, as before', () async {
      final source = _Source(server: _six(), saved: SavedSearchData.none)
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      await search(vm, 'ahmed');

      expect(vm.searchResults, isEmpty);
      expect(vm.errorKind, SearchErrorKind.network);
    });

    test(
        'one kind saved, five missing: its results show; a miss is not '
        '"nothing found"', () async {
      final owners = SearchData(owners: [owner_(id: 'o1', name: 'Ahmed')]);
      final source = _Source(
          server: const SearchData(),
          saved: SavedSearchData(owners, {SearchResultType.owner}))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      await search(vm, 'ahmed');
      expect(_keys(vm), hasLength(1));
      expect(vm.savedCoverage, {SearchResultType.owner});

      await search(vm, 'nothing-matches-this');
      expect(vm.searchResults, isEmpty);
      expect(vm.errorKind, SearchErrorKind.network,
          reason: 'five kinds were never searched');

      vm.submitQuery('ahmed');
      await pumpEventQueue();
      vm.toggleFilter(2); // Offers — not saved on this device; searches again
      await pumpEventQueue();
      expect(vm.searchResults, isEmpty);
      expect(vm.errorKind, SearchErrorKind.network);
    });

    test('all six saved, offline: a miss is a real "nothing found"', () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      await search(vm, 'nothing-matches-this');

      expect(vm.searchResults, isEmpty);
      expect(vm.hasAnswer, isTrue);
      expect(vm.errorKind, isNull);
    });

    test(
        'the saved answer shows before the server answers, then the '
        'server replaces it', () async {
      final source = _Source(
          server: _six(owner: 'Ahmed New', prefix: 's-'),
          saved: SavedSearchData(_six(owner: 'Ahmed Old'), _all))
        ..manual = true;
      final vm = vmFor(source);

      vm.submitQuery('ahmed');
      await pumpEventQueue();
      expect(vm.searchResults.single.title, 'Ahmed Old');
      expect(vm.isLoading, isFalse);
      expect(vm.resultsFromSavedCopy, isTrue);

      source.pending.single.complete(source.server);
      await pumpEventQueue();
      expect(vm.searchResults.single.title, 'Ahmed New');
      expect(vm.resultsFromSavedCopy, isFalse);
    });

    test('a server failure after the saved answer keeps it', () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all))
        ..manual = true;
      final vm = vmFor(source);

      vm.submitQuery('ahmed');
      await pumpEventQueue();
      source.pending.single.completeError(const SocketException('lost'));
      await pumpEventQueue();

      expect(_keys(vm), hasLength(1));
      expect(vm.errorKind, isNull);
    });

    test('an authoritative empty server answer replaces the saved one',
        () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all));
      final vm = vmFor(source);

      await search(vm, 'ahmed');

      expect(vm.searchResults, isEmpty);
      expect(vm.hasAnswer, isTrue);
      expect(vm.resultsFromSavedCopy, isFalse);
    });

    test('another account: the first account\'s copy is never searched',
        () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all))
        ..serverFailure = const SocketException('offline');
      source.savedFor['u2'] = SavedSearchData.none;
      final vm = vmFor(source);
      await search(vm, 'ahmed');
      expect(_keys(vm), hasLength(1));

      source.userId = 'u2';
      await search(vm, 'ahmed');

      expect(vm.searchResults, isEmpty);
      expect(vm.errorKind, SearchErrorKind.network);
    });

    test('signed out: nothing is searched', () async {
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(_six(), _all))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);
      await search(vm, 'ahmed');

      source.userId = null;
      await search(vm, 'ahmed');

      expect(vm.searchResults, isEmpty);
    });

    test('a new session of the same account reads again', () async {
      final source = _Source(server: _six(), saved: SavedSearchData.none);
      final vm = vmFor(source);
      await search(vm, 'ahmed');
      expect(source.loads, 1);

      source.session = 's2';
      await search(vm, 'ahmed');

      expect(source.loads, 2, reason: 'records of session s1 are not reused');
      expect(source.savedLoads, 2);
    });

    test('a server answer for an earlier session is dropped', () async {
      final source = _Source(
          server: _six(owner: 'Ahmed Late', prefix: 'late-'),
          saved: SavedSearchData(_six(owner: 'Ahmed Saved'), _all))
        ..manual = true;
      final vm = vmFor(source);
      vm.submitQuery('ahmed');
      await pumpEventQueue();

      source.session = 's2'; // sign-out and sign-in, same account
      await search(vm, 'ahmed'); // the saved lists, read again for s2
      expect(vm.resultsFromSavedCopy, isTrue);
      source.pending.single.complete(source.server);
      await pumpEventQueue();

      expect(vm.searchResults.single.title, 'Ahmed Saved');
      expect(vm.resultsFromSavedCopy, isTrue,
          reason: 'the s2 records are not replaced by an s1 answer');
    });

    test('a read cut off by a new session does not hold the next one back',
        () async {
      final source =
          _Source(server: _six(), saved: SavedSearchData(_six(), _all))
            ..manual = true;
      final vm = vmFor(source);
      vm.submitQuery('ahmed');
      await pumpEventQueue();

      source.session = 's2';
      source.pending.single.completeError(const SocketException('cut off'));
      await pumpEventQueue();
      source.manual = false;
      await search(vm, 'ahmed');

      expect(source.loads, 2, reason: 'no back-off from the s1 failure');
      expect(vm.resultsFromSavedCopy, isFalse);
    });

    test('closing Search stops its server read', () async {
      final source = _Source(server: _six(), saved: SavedSearchData.none)
        ..manual = true;
      final vm = SearchViewModel(
        dataSource: source,
        engine: newEngine(),
        dataChanges: const Stream<void>.empty(),
      );
      vm.submitQuery('ahmed');
      await pumpEventQueue();

      vm.dispose();
      await pumpEventQueue();

      expect(source.cancels, 1);
      expect(vm.searchResults, isEmpty);
    });

    test('rapid typing reads once; later searches reuse the records', () async {
      final source = _Source(server: _six(), saved: SavedSearchData.none);
      final vm = vmFor(source);
      for (final q in ['a', 'ah', 'ahm', 'ahme', 'ahmed']) {
        vm.updateQuery(q);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();
      expect(source.loads, 1);
      expect(source.savedLoads, 1);

      for (final q in ['khalid', 'villa', 'marina', 'ahmed']) {
        await search(vm, q);
      }
      expect(source.loads, 1);
    });

    test('after a failed server read the next one waits, unless Retry',
        () async {
      final source =
          _Source(server: _six(), saved: SavedSearchData(_six(), _all))
            ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);
      await search(vm, 'ahmed');
      await search(vm, 'khalid');
      await search(vm, 'villa');
      expect(source.loads, 1, reason: 'no read on every search while offline');

      now = now.add(const Duration(seconds: 31));
      await search(vm, 'ahmed');
      expect(source.loads, 2);

      vm.retry();
      await pumpEventQueue();
      expect(source.loads, 3);
    });

    test('filters, ordering and Arabic match exactly as the server copy',
        () async {
      final data = SearchData(
        owners: [
          owner_(id: 'o1', name: 'أحمد سعيد'),
          owner_(id: 'o2', name: 'Ahmed Saeed'),
          owner_(id: 'o3', name: 'Saeed Ahmed'),
        ],
        offices: [office(id: 'c1', name: 'مكتب أحمد')],
        brokers: [broker(id: 'b1', name: 'Ahmed Broker')],
      );
      Future<List<String>> answer(SavedSearchData saved, SearchData server,
          String q, int filter) async {
        final source = _Source(server: server, saved: saved);
        if (saved.isEmpty) {
          source.serverFailure = null;
        } else {
          source.serverFailure = const SocketException('offline');
        }
        final vm = vmFor(source);
        if (filter != 0) vm.toggleFilter(filter);
        await search(vm, q);
        return _keys(vm);
      }

      for (final q in ['ahmed', 'أحمد', 'saeed']) {
        for (final filter in [0, 3, 4, 5]) {
          final fromServer =
              await answer(SavedSearchData.none, data, q, filter);
          final fromSaved = await answer(
              SavedSearchData(data, _all), const SearchData(), q, filter);
          expect(fromSaved, fromServer, reason: '$q / filter $filter');
        }
      }
    });

    test('a result keeps its saved record for navigation', () async {
      final saved = _six();
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(saved, _all))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      await search(vm, 'ahmed');

      expect(vm.searchResults.single.data, same(saved.owners.single));
    });

    test('large saved copy: one read, measured local search time', () async {
      const perKind = 2000;
      final data = SearchData(
        requests: [for (var i = 0; i < perKind; i++) request(id: 'r$i')],
        offers: [for (var i = 0; i < perKind; i++) offer(id: 'f$i')],
        owners: [
          for (var i = 0; i < perKind; i++) owner_(id: 'o$i', name: 'Owner $i')
        ],
        offices: [
          for (var i = 0; i < perKind; i++) office(id: 'c$i', name: 'Office $i')
        ],
        brokers: [
          for (var i = 0; i < perKind; i++) broker(id: 'b$i', name: 'Broker $i')
        ],
        watchmen: [
          for (var i = 0; i < perKind; i++)
            watchman(id: 'w$i', name: 'Watchman $i')
        ],
      );
      final source = _Source(
          server: const SearchData(), saved: SavedSearchData(data, _all))
        ..serverFailure = const SocketException('offline');
      final vm = vmFor(source);

      final first = Stopwatch()..start();
      await search(vm, 'owner 1999');
      first.stop();
      final later = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        await search(vm, 'broker ${i * 7}');
      }
      later.stop();

      expect(vm.searchResults, isNotEmpty);
      expect(source.savedLoads, 1);
      expect(source.loads, 1);
      debugPrint('[SearchCost] ${perKind * 6} saved records: first search '
          '(read+index+search) ${first.elapsedMilliseconds} ms; 20 later '
          'searches ${later.elapsedMilliseconds} ms in all');
    });
  });

  group('DefaultSearchDataSource — saved lists', () {
    late Directory tempDir;
    String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
        '${EncryptedAccountListCache.directoryName}';
    String? signedIn;
    String? session;

    DefaultSearchDataSource source({SearchServerLists? server}) =>
        DefaultSearchDataSource(
          currentUserId: () => signedIn,
          currentSession: () => session,
          serverLists: server,
          confirmEmptyList: (_) => null,
        );

    Future<void> saveAll(String uid, {Set<String> only = const {}}) async {
      bool want(String k) => only.isEmpty || only.contains(k);
      if (want('requests')) {
        await const RequestsLocalCache()
            .write(uid, [request(id: 'r1').copyWith(userId: uid)]);
      }
      if (want('offers')) {
        await const OffersLocalCache()
            .write(uid, [offer(id: 'f1').copyWith(userId: uid)]);
      }
      if (want('owners')) {
        await const OwnersLocalCache().write(uid, [
          owner_(id: 'o1', name: 'Ahmed').copyWith(userId: uid),
          owner_(id: 'o2', name: 'Khalid').copyWith(userId: uid),
        ]);
      }
      if (want('offices')) {
        await const OfficesLocalCache()
            .write(uid, [office(id: 'c1').copyWith(userId: uid)]);
      }
      if (want('brokers')) {
        await const BrokersLocalCache()
            .write(uid, [broker(id: 'b1').copyWith(userId: uid)]);
      }
      if (want('watchmen')) {
        await const WatchmenLocalCache()
            .write(uid, [watchman(id: 'w1').copyWith(userId: uid)]);
      }
    }

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('search_local_first');
      Hive.init(tempDir.path);
      EncryptedAccountListCache.debugStorageRoot = tempDir.path;
    });

    tearDownAll(() async {
      await Hive.close();
      EncryptedAccountListCache.debugStorageRoot = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      EncryptedAccountListCache.debugForgetProcessState();
      signedIn = 'u1';
      session = 's1';
    });

    tearDown(() async {
      for (final uid in ['u1', 'u2']) {
        for (final name in [
          RequestsLocalCache.boxNameForUid(uid),
          OffersLocalCache.boxNameForUid(uid),
          OwnersLocalCache.boxNameForUid(uid),
          OfficesLocalCache.boxNameForUid(uid),
          BrokersLocalCache.boxNameForUid(uid),
          WatchmenLocalCache.boxNameForUid(uid),
        ]) {
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
      }
    });

    test('all six saved: all six are read, each the account\'s own', () async {
      await saveAll('u1');

      final saved = await source().loadSaved();

      expect(saved.covered, _all);
      expect([for (final o in saved.data.owners) o.id], ['o1', 'o2']);
      expect(saved.data.requests.single.userId, 'u1');
      expect(saved.data.watchmen.single.id, 'w1');
    });

    test('one kind saved: only it is covered; the rest are not "empty"',
        () async {
      await saveAll('u1', only: {'owners'});

      final saved = await source().loadSaved();

      expect(saved.covered, {SearchResultType.owner});
      expect(saved.data.requests, isEmpty);
    });

    test('nothing saved: nothing covered', () async {
      expect((await source().loadSaved()).isEmpty, isTrue);
    });

    test('another account\'s lists are never read', () async {
      await saveAll('u2');

      expect((await source().loadSaved()).isEmpty, isTrue);
      signedIn = 'u2';
      expect((await source().loadSaved()).covered, _all);
    });

    test('a record the server confirmed deleted is not searched', () async {
      await saveAll('u1', only: {'owners'});
      await const OwnersLocalCache().rememberConfirmedDeletion('u1', 'o1');

      final saved = await source().loadSaved();

      expect([for (final o in saved.data.owners) o.id], ['o2']);
    });

    test('a list that fails its integrity check is not covered', () async {
      await saveAll('u1', only: {'owners', 'brokers'});
      await Hive.box<String>(OwnersLocalCache.boxNameForUid('u1'))
          .put('owners_v2', '{"v":2,"p":"[]","t":"forged"}');

      final saved = await source().loadSaved();

      expect(saved.covered, {SearchResultType.broker},
          reason: 'not an authoritative empty Owners list');
    });

    test('an unreadable list (wrong key) is not covered', () async {
      await saveAll('u1', only: {'owners'});
      await Hive.box<String>(OwnersLocalCache.boxNameForUid('u1')).close();
      await const FlutterSecureStorage().write(
          key: 'owners_cache_key_v1_u1',
          value: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');

      expect((await source().loadSaved()).isEmpty, isTrue);
    });

    test(
        'signed out, or the account/session changed during the read: '
        'nothing', () async {
      await saveAll('u1');
      signedIn = null;
      expect((await source().loadSaved()).isEmpty, isTrue);

      signedIn = 'u1';
      var calls = 0;
      final switching = DefaultSearchDataSource(
        currentUserId: () => signedIn,
        currentSession: () => calls++ == 0 ? 's1' : 's2',
      );
      expect((await switching.loadSaved()).isEmpty, isTrue);
    });
  });

  group('DefaultSearchDataSource — server lists', () {
    /// Six server lists; each read is a stream the test answers.
    late List<StreamController<List<Object>>> reads;
    late List<bool> cancelled;

    SearchServerLists lists() {
      reads = [];
      cancelled = [];
      Stream<List<T>> next<T>() {
        final i = reads.length;
        cancelled.add(false);
        final c =
            StreamController<List<Object>>(onCancel: () => cancelled[i] = true);
        reads.add(c);
        return c.stream.map((rows) => rows.cast<T>());
      }

      return SearchServerLists(
        requests: next<RequestModel>,
        offers: next<OfferModel>,
        owners: next<OwnerModel>,
        offices: next<OfficeModel>,
        brokers: next<BrokerModel>,
        watchmen: next<WatchmenModel>,
      );
    }

    void answerAll() {
      reads[0].add([request(id: 'r1')]);
      reads[1].add([offer(id: 'f1')]);
      reads[2].add([owner_(id: 'o1', name: 'Ahmed')]);
      reads[3].add([office(id: 'c1')]);
      reads[4].add([broker(id: 'b1')]);
      reads[5].add([watchman(id: 'w1')]);
    }

    DefaultSearchDataSource source(SearchServerLists server,
            {Future<bool>? Function(String?)? confirm}) =>
        DefaultSearchDataSource(
          currentUserId: () => 'u1',
          currentSession: () => 's1',
          serverLists: server,
          confirmEmptyList: confirm ?? (_) => null,
        );

    test('the six lists are read once each and then let go', () async {
      final data = source(lists()).load();
      await pumpEventQueue();
      expect(reads, hasLength(6));
      answerAll();

      final loaded = await data;

      expect(loaded.owners.single.id, 'o1');
      expect(cancelled, everyElement(isTrue));
    });

    test(
        'one list failing (a later page) fails the load and stops the '
        'other five', () async {
      final data = source(lists()).load();
      await pumpEventQueue();
      reads[2].addError(const SocketException('page 2'));

      await expectLater(data, throwsA(isA<SocketException>()));
      expect(cancelled, everyElement(isTrue));
    });

    test('closing Search cancels the reads; nothing is returned', () async {
      final src = source(lists());
      final data = src.load();
      await pumpEventQueue();

      src.cancelReads();

      await expectLater(data, throwsA(anything));
      expect(cancelled, everyElement(isTrue));
    });

    test('an empty list is accepted only once the session is confirmed',
        () async {
      for (final (answer, accepted) in [
        (Future<bool>.value(true), true),
        (Future<bool>.value(false), false),
        (null, true), // no app session: no gate, as the list screens do
      ]) {
        var asked = 0;
        final data = source(lists(), confirm: (_) {
          asked++;
          return answer;
        }).load();
        await pumpEventQueue();
        for (final r in reads) {
          r.add(const []);
        }
        if (accepted) {
          expect((await data).owners, isEmpty);
        } else {
          await expectLater(data, throwsA(isA<ListSessionNotCurrent>()));
        }
        expect(asked, 1);
      }
    });

    test('lists with rows need no session check', () async {
      var asked = 0;
      final data = source(lists(), confirm: (_) {
        asked++;
        return Future<bool>.value(true);
      }).load();
      await pumpEventQueue();
      answerAll();
      await data;
      expect(asked, 0);
    });
  });

  group('wiring: the real data source with the view model', () {
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('search_local_wiring');
      Hive.init(tempDir.path);
      EncryptedAccountListCache.debugStorageRoot = tempDir.path;
    });

    tearDownAll(() async {
      await Hive.close();
      EncryptedAccountListCache.debugStorageRoot = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('saved Owners answer while every server read fails', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await const OwnersLocalCache()
          .write('u1', [owner_(id: 'o1', name: 'Ahmed')]);
      Stream<List<T>> fail<T>() =>
          Stream<List<T>>.error(const SocketException('offline'));
      final vm = SearchViewModel(
        dataSource: DefaultSearchDataSource(
          currentUserId: () => 'u1',
          currentSession: () => null,
          serverLists: SearchServerLists(
            requests: fail<RequestModel>,
            offers: fail<OfferModel>,
            owners: fail<OwnerModel>,
            offices: fail<OfficeModel>,
            brokers: fail<BrokerModel>,
            watchmen: fail<WatchmenModel>,
          ),
        ),
        engine: newEngine(),
        dataChanges: const Stream<void>.empty(),
      );
      addTearDown(vm.dispose);

      vm.submitQuery('ahmed');
      for (var i = 0; i < 20 && vm.searchResults.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(vm.searchResults.single.id, 'o1');
      expect(vm.errorKind, isNull);
      expect(vm.savedCoverage, {SearchResultType.owner});
    });
  });
}
