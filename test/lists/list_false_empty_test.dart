// P3.1b (F-SAD-EMPTY): an empty server list is trusted only once the
// database confirms the session is still the account's current one.
//
// The database's session gate filters rows instead of failing, so a session
// that another device has replaced reads every list as empty (P3.0, §7Z). A
// list with rows proves the gate let the read through; only an empty one is
// checked. Real Hive in a temporary documents directory, the secure-storage
// test store and the real local-first stream.
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
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
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
final _when = DateTime.utc(2026);
final _t0 = DateTime.utc(2026, 11, 2, 8);
final _t1 = DateTime.utc(2026, 11, 2, 9);

RequestModel _request(String id, [String owner = _alice]) => RequestModel(
      id: id,
      userId: owner,
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: '',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: 'note $id',
      specificPropertyType: '',
      rooms: 0,
      bathrooms: 0,
      createdAt: _when,
      updatedAt: _when,
    );

List<String?> _ids(List<RequestModel>? requests) =>
    requests?.map((r) => r.id).toList() ?? const ['<nothing>'];

const _s1 = 'a1a1a1a1-0000-4000-8000-000000000001';
const _s3 = 'a3a3a3a3-0000-4000-8000-000000000003';

/// A stored Supabase session for Alice whose access token carries
/// [sessionId]; [issued] makes each token distinct, as a refresh does.
String _sessionJson(String sessionId, {required int issued}) {
  String part(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({
        'sub': _alice,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'iat': issued,
        'session_id': sessionId,
      })}.sig';
  return jsonEncode({
    'access_token': token,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'refresh-$issued',
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

class _Server<T> {
  final List<StreamController<List<T>>> reads = [];
  Stream<List<T>> call() {
    final read = StreamController<List<T>>();
    reads.add(read);
    return read.stream;
  }
}

class _Screen<T> {
  final List<List<T>> lists = [];
  final List<Object> errors = [];
  final List<LocalListStatus> statuses = [];
  late final StreamSubscription<List<T>> subscription;
  LocalListStatus get status => statuses.last;
}

/// A session check the test answers: each call waits for [answer] (or the
/// next value set on it) and is counted.
class _Check {
  int calls = 0;
  final List<String?> sessions = [];
  Completer<bool>? _pending;

  /// Answers every call at once with this, when set.
  bool? always;
  Object? throws;

  Future<bool>? call(String? session) {
    calls++;
    sessions.add(session);
    if (throws != null) return Future<bool>.error(throws!);
    if (always != null) return Future<bool>.value(always);
    return (_pending = Completer<bool>()).future;
  }

  void answer(bool current) => _pending!.complete(current);
}

/// The real Requests key store, whose next read can be held so a save waits
/// at a known point.
class _GatedKeys implements AccountCacheKeyStore {
  final _real = const SecureRequestsCacheKeyStore();
  Completer<void>? hold;
  final Completer<void> held = Completer<void>();
  int writes = 0;

  @override
  Future<List<int>?> read(String uid) async {
    final gate = hold;
    hold = null;
    if (gate != null) {
      if (!held.isCompleted) held.complete();
      await gate.future;
    }
    return _real.read(uid);
  }

  @override
  Future<void> write(String uid, List<int> key) {
    writes++;
    return _real.write(uid, key);
  }

  @override
  Future<void> delete(String uid) => _real.delete(uid);
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

Future<_Screen<T>> _open<T>(
  EncryptedAccountListCache<T> cache,
  _Server<T> server, {
  required _Check check,
  String? Function()? user,
  DateTime Function()? now,
  List<Duration> retryDelays = const [],
  Stream<void>? hints,
  String? Function()? session,
}) async {
  final screen = _Screen<T>();
  final before = server.reads.length;
  screen.subscription = localFirstList<T>(
    server: server.call,
    cache: cache,
    currentUserId: user ?? () => _alice,
    refreshSignals: hints ?? const Stream<void>.empty(),
    retryDelays: retryDelays,
    now: now ?? () => _t1,
    isAppActive: () => true,
    onStatus: screen.statuses.add,
    confirmEmptyList: check.call,
    sessionOf: session ?? () => 's1',
  ).listen(screen.lists.add, onError: screen.errors.add);
  await _until(() => server.reads.length > before);
  return screen;
}

Future<SavedList<T>?> _saved<T>(EncryptedAccountListCache<T> cache,
    [String uid = _alice]) async {
  await pumpEventQueue();
  return cache.readSaved(uid);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const cache = RequestsLocalCache();

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('list_false_empty_test');
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
    ListSessionCheck.debugOverride = null;
  });

  tearDown(() async {
    ListSessionCheck.debugOverride = null;
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

  /// Alice's saved copy, from a server list at [_t0].
  Future<void> savedCopy(List<RequestModel> list) async {
    final server = _Server<RequestModel>();
    final screen = await _open(cache, server,
        check: _Check()..always = true, now: () => _t0);
    server.reads.last.add(list);
    await _saved(cache);
    await screen.subscription.cancel();
  }

  // ---------------------------------------------------------------------
  group('the session is confirmed current', () {
    test('a legitimately empty list replaces the saved copy, with its time',
        () async {
      await savedCopy([_request('a1')]);
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);

      final saved = await _saved(cache);
      expect(saved!.items, isEmpty);
      expect(saved.info.serverReadAt, _t1);
      expect(screen.lists.map(_ids), [
        ['a1'],
        <String>[]
      ]);
      expect(screen.status.showing, LocalListSource.server);
      expect(screen.status.lastReadFailed, isFalse);
      expect(check.calls, 1);
      await screen.subscription.cancel();
    });

    test('with no saved copy, an empty list is shown and saved as empty',
        () async {
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);
      final saved = await _saved(cache);
      expect(saved!.items, isEmpty);
      expect(screen.lists, [isEmpty]);
      await screen.subscription.cancel();
    });

    test('a list with rows is never checked: the gate already let it through',
        () async {
      final check = _Check()..always = false;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add([_request('a1')]);
      server.reads.last.add([_request('a1'), _request('a2')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1', 'a2']);
      expect(check.calls, 0);
      await screen.subscription.cancel();
    });

    test('while the check runs, the screen keeps what it shows', () async {
      await savedCopy([_request('a1')]);
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);
      await pumpEventQueue();
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      expect(screen.status.refreshing, isTrue);
      check.answer(true);
      await _saved(cache);
      expect(screen.lists.last, isEmpty);
      await screen.subscription.cancel();
    });

    test(
        'a refresh hint during the check starts no second read: the list is '
        'still refreshing', () async {
      var clock = _t1;
      final hints = StreamController<void>();
      addTearDown(hints.close);
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, now: () => clock, hints: hints.stream);
      server.reads.last.add(const []);
      await pumpEventQueue();
      clock = _t1.add(const Duration(minutes: 5)); // past every hint gap
      hints.add(null);
      await pumpEventQueue();
      expect(server.reads, hasLength(1));
      check.answer(true);
      await _saved(cache);
      expect(screen.lists, [isEmpty]);
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('the session is not confirmed', () {
    test(
        'a superseded session\'s empty list does not replace the saved copy, '
        'nor its time, and is not shown', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      final check = _Check()..always = false;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1', 'a2']);
      expect(saved.info.serverReadAt, _t0, reason: 'no false freshness');
      expect(screen.lists.map(_ids), [
        ['a1', 'a2']
      ]);
      expect(screen.errors.single, isA<ListSessionNotCurrent>());
      expect(screen.status.showing, LocalListSource.savedCopy);
      expect(screen.status.lastReadFailed, isTrue);
      expect(screen.status.refreshing, isFalse);
      expect(screen.status.lastServerReadAt, _t0);
      await screen.subscription.cancel();
    });

    test('with no saved copy, nothing is shown and nothing is saved', () async {
      final check = _Check()..always = false;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);
      expect(await _saved(cache), isNull);
      expect(screen.lists, isEmpty);
      expect(screen.errors.single, isA<ListSessionNotCurrent>());
      expect(screen.status.showing, LocalListSource.nothing);
      await screen.subscription.cancel();
    });

    test(
        'a network failure during the check keeps the copy and reads again; '
        'a confirmed empty list then replaces it', () async {
      await savedCopy([_request('a1')]);
      final check = _Check()..throws = const SocketException('offline');
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, retryDelays: const [Duration(milliseconds: 10)]);
      server.reads.last.add(const []);
      await _until(() => server.reads.length == 2); // the retry

      var saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.errors.single, isA<SocketException>());
      expect(screen.status.lastReadFailed, isTrue);

      check
        ..throws = null
        ..always = true;
      server.reads.last.add(const []);
      saved = await _saved(cache);
      expect(saved!.items, isEmpty);
      expect(saved.info.serverReadAt, _t1);
      await screen.subscription.cancel();
    });

    test('any other failure of the check stops the list and keeps the copy',
        () async {
      await savedCopy([_request('a1')]);
      final check = _Check()..throws = StateError('rpc refused');
      final server = _Server<RequestModel>(); // no retries configured anyway
      final screen = await _open(cache, server,
          check: check, retryDelays: const [Duration(milliseconds: 10)]);
      server.reads.last.add(const []);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(server.reads, hasLength(1), reason: 'no retry after a refusal');
      expect(screen.errors.single, isA<StateError>());
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('the account, the screen and newer lists during the check', () {
    test(
        'the account changes during the check: nothing is shown or saved for '
        'either account', () async {
      await savedCopy([_request('a1')]);
      var user = _alice;
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check, user: () => user);
      server.reads.last.add(const []);
      await pumpEventQueue();
      final reported = screen.statuses.length;
      user = _bob;
      check.answer(true);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(await cache.readSaved(_bob), isNull);
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      expect(screen.statuses, hasLength(reported));
      await screen.subscription.cancel();
    });

    test('signed out during the check: nothing is shown or saved', () async {
      await savedCopy([_request('a1')]);
      String? user = _alice;
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check, user: () => user);
      server.reads.last.add(const []);
      await pumpEventQueue();
      user = null;
      check.answer(true);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(screen.lists, hasLength(1));
      await screen.subscription.cancel();
    });

    test('a screen closed during the check saves nothing', () async {
      await savedCopy([_request('a1')]);
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);
      await pumpEventQueue();
      await screen.subscription.cancel();
      check.answer(true);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
    });

    test(
        'a newer list that arrives during the check wins; the older empty '
        'answer is dropped', () async {
      await savedCopy([_request('a1')]);
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      server.reads.last.add(const []);
      await pumpEventQueue();
      server.reads.last.add([_request('a2')]); // a re-read after a mutation
      await pumpEventQueue();
      check.answer(true);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a2']);
      expect(screen.lists.map(_ids), [
        ['a1'],
        ['a2']
      ]);
      await screen.subscription.cancel();
    });

    test('a source that ends during the check still ends after it', () async {
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check);
      var done = false;
      final ended = screen.subscription.asFuture<void>().then((_) {
        done = true;
      });
      server.reads.last
        ..add(const [])
        ..close();
      await pumpEventQueue();
      expect(done, isFalse, reason: 'not before the check answers');
      check.answer(true);
      await ended.timeout(const Duration(seconds: 2));
      expect(screen.lists, [isEmpty]);
      expect((await _saved(cache))!.items, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // F-SAD-EMPTY-ABA: an answer counts only for the session that asked for
  // it. Alice's list is read under s1; s1 is replaced, she signs out and
  // signs in again to the same account (s3); the answer to the s1 read
  // arrives only then.
  group('the session that started the read', () {
    test(
        'a late EMPTY answer to an s1 read, after sign-out and sign-in to the '
        'same account as s3, is dropped: the copy and its time stay', () async {
      await savedCopy([_request('a1')]);
      String? user = _alice;
      var session = 's1';
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, user: () => user, session: () => session);
      user = null; // signed out
      await pumpEventQueue();
      user = _alice; // signed in again, as a new session
      session = 's3';
      server.reads.last.add(const []); // the s1 answer, late

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0, reason: 'no false freshness');
      expect(check.calls, 0, reason: 'no check for another session');
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      expect(screen.errors, isEmpty);
      await screen.subscription.cancel();
    });

    test('a late NONEMPTY answer to an s1 read is dropped the same way',
        () async {
      await savedCopy([_request('a1')]);
      String? user = _alice;
      var session = 's1';
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, user: () => user, session: () => session);
      user = null;
      await pumpEventQueue();
      user = _alice;
      session = 's3';
      server.reads.last.add([_request('late')]);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      expect(check.calls, 0, reason: 'rows are never checked');
      await screen.subscription.cancel();
    });

    test(
        'the session changes while the check is pending: its answer, even '
        '"current", is dropped', () async {
      await savedCopy([_request('a1')]);
      var session = 's1';
      final check = _Check();
      final server = _Server<RequestModel>();
      final screen =
          await _open(cache, server, check: check, session: () => session);
      server.reads.last.add(const []);
      await pumpEventQueue();
      expect(check.sessions, ['s1'], reason: 'asked about s1, the asker');
      session = 's3';
      check.answer(true);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      await screen.subscription.cancel();
    });

    test(
        'a token refresh keeps the session: the empty answer is checked for '
        'that session and accepted, a list with rows is accepted', () async {
      await savedCopy([_request('a1')]);
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, session: () => 's1'); // same session_id throughout
      server.reads.last.add(const []);
      expect((await _saved(cache))!.items, isEmpty);
      expect(check.sessions, ['s1']);
      server.reads.last.add([_request('a2')]);
      expect(_ids((await _saved(cache))!.items), ['a2']);
      await screen.subscription.cancel();
    });

    test(
        'another account signs in before an s1 answer arrives: nothing is '
        'shown or saved for either account', () async {
      await savedCopy([_request('a1')]);
      String? user = _alice;
      var session = 's1';
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check, user: () => user, session: () => session);
      user = _bob;
      session = 's2';
      server.reads.last.add([_request('late')]);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(await cache.readSaved(_bob), isNull);
      expect(screen.lists, hasLength(1));
      await screen.subscription.cancel();
    });

    test('signed out while the read is pending: its answer is dropped',
        () async {
      await savedCopy([_request('a1')]);
      String? user = _alice;
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, check: check, user: () => user);
      user = null;
      server.reads.last.add([_request('late')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.lists, hasLength(1));
      await screen.subscription.cancel();
    });

    test(
        'a late s1 failure after the new session neither shows an error nor '
        'stops anything for s3: it is dropped', () async {
      await savedCopy([_request('a1')]);
      var session = 's1';
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen =
          await _open(cache, server, check: check, session: () => session);
      session = 's3';
      server.reads.last.addError(StateError('session_superseded'));
      await pumpEventQueue();
      expect(screen.errors, isEmpty);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      await screen.subscription.cancel();
    });

    /// Alice's box exists but its key is gone (unreadable: D-2 territory). A
    /// server list read under s1 is accepted and its save queued; the save
    /// is held at the key store while [between] runs, then let go.
    Future<
            ({
              _GatedKeys keys,
              List<int> before,
              File file,
              RequestsLocalCache gated
            })>
        recoveryRace(
            void Function() between, String? Function() session) async {
      await savedCopy([_request('a1')]);
      await Hive.close();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      final sep = Platform.pathSeparator;
      final file = File('${root.path}$sep'
          '${EncryptedAccountListCache.directoryName}$sep'
          '${RequestsLocalCache.boxNameForUid(_alice)}.hive');
      final before = file.readAsBytesSync();

      final keys = _GatedKeys();
      final gated = RequestsLocalCache(keyStore: keys);
      final server = _Server<RequestModel>();
      final screen = await _open(gated, server,
          check: _Check()..always = true, session: session);
      final gate = Completer<void>();
      keys.hold = gate;
      server.reads.last.add([_request('fresh')]); // accepted under s1
      await keys.held.future.timeout(const Duration(seconds: 2));
      between();
      gate.complete();
      await _saved(gated); // the queued save has run
      await screen.subscription.cancel();
      return (keys: keys, before: before, file: file, gated: gated);
    }

    test(
        'D-2: a server list read under s1 cannot recover the unreadable box '
        'once the user has signed out and in again as s3: no new key, the '
        'box untouched, no list and no time', () async {
      var session = 's1';
      final r = await recoveryRace(() => session = 's3', () => session);

      expect(r.keys.writes, 0, reason: 'no new key');
      expect(
          await const FlutterSecureStorage()
              .read(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice)),
          isNull);
      await Hive.close();
      expect(r.file.readAsBytesSync(), r.before, reason: 'box untouched');
      final spare = Directory('${root.path}${Platform.pathSeparator}'
          '${EncryptedAccountListCache.directoryName}'
          '${Platform.pathSeparator}'
          '${EncryptedAccountListCache.recoveryDirectoryName}');
      expect(spare.existsSync() ? spare.listSync() : const [], isEmpty,
          reason: 'nothing built or set aside');
      expect(await r.gated.readSaved(_alice), isNull,
          reason: 'no list and no time from the stale session');
    });

    test(
        'control: the same server list with the session unchanged does '
        'recover the box (new key, list and time saved)', () async {
      final r = await recoveryRace(() {}, () => 's1');
      expect(r.keys.writes, 1, reason: 'a new key');
      final saved = await r.gated.readSaved(_alice);
      expect(_ids(saved!.items), ['fresh']);
      expect(saved.info.serverReadAt, _t1);
    });

    test(
        'a read started under s3 after a retry is checked for s3 and '
        'accepted', () async {
      await savedCopy([_request('a1')]);
      var session = 's1';
      final check = _Check()..always = true;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          check: check,
          session: () => session,
          retryDelays: const [Duration(milliseconds: 10)]);
      server.reads.last.addError(const SocketException('offline')); // s1
      await pumpEventQueue(); // the failure arrives while s1 is current
      session = 's3';
      await _until(() => server.reads.length == 2); // the retry, under s3
      server.reads.last.add(const []);
      expect((await _saved(cache))!.items, isEmpty);
      expect(check.sessions, ['s3']);
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('the shared check', () {
    test(
        'one check in flight per session is shared; another session, or a '
        'later call, checks again', () async {
      var validations = 0;
      final gates = <Completer<bool>>[];
      Future<bool> validate() {
        validations++;
        return (gates..add(Completer<bool>())).last.future;
      }

      final first = ListSessionCheck.shared('s1', validate);
      final second = ListSessionCheck.shared('s1', validate);
      expect(validations, 1);
      final other = ListSessionCheck.shared('s2', validate);
      expect(validations, 2, reason: 'never shared across sessions');
      gates[0].complete(true);
      gates[1].complete(false);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await other, isFalse);

      final later = ListSessionCheck.shared('s1', validate);
      expect(validations, 3, reason: 'no decision kept after it answered');
      gates[2].complete(false);
      expect(await later, isFalse);
    });

    test(
        'only the current session is ever validated: an earlier session is '
        'answered false without asking, so it can neither be confirmed nor '
        'start a sign-out of the newer one', () async {
      var validations = 0;
      Future<bool> validate() async {
        validations++;
        return true;
      }

      expect(
          await ListSessionCheck.bound('s1', current: 's3', validate: validate),
          isFalse);
      expect(
          await ListSessionCheck.bound(null, current: 's3', validate: validate),
          isFalse);
      expect(validations, 0);
      expect(
          await ListSessionCheck.bound('s3', current: 's3', validate: validate),
          isTrue);
      expect(validations, 1);
    });

    test('a failed check is not kept either', () async {
      var validations = 0;
      Future<bool> fails() async {
        validations++;
        throw const SocketException('offline');
      }

      await expectLater(ListSessionCheck.shared('s1', fails),
          throwsA(isA<SocketException>()));
      await expectLater(ListSessionCheck.shared('s1', fails),
          throwsA(isA<SocketException>()));
      expect(validations, 2);
    });

    test('a session with no id is never confirmed', () async {
      var validations = 0;
      expect(
          await ListSessionCheck.shared(null, () async {
            validations++;
            return true;
          }),
          isFalse);
      expect(validations, 0);
    });

    test(
        'with no app-session coordinator (no Supabase app session) there is '
        'no session and nothing to ask', () async {
      expect(AppSessionCoordinator.active, isNull);
      expect(ListSessionCheck.currentSession(), isNull);
      expect(ListSessionCheck.confirmFor(null), isNull);
    });

    test(
        'the session is the access token\'s session_id: a token refresh '
        'keeps it, a new sign-in changes it; only the current session is '
        'ever asked about, and an unauthorized one costs no request', () async {
      var rpcs = 0;
      final client = sb.SupabaseClient(
        'https://unit-test.supabase.co',
        'unit-test-publishable-key',
        httpClient: MockClient((r) async {
          if (r.url.path.contains('/rpc/')) rpcs++;
          return http.Response('true', 200,
              headers: {'content-type': 'application/json'});
        }),
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      final coordinator = AppSessionCoordinator(client, onSuperseded: () {});
      addTearDown(coordinator.dispose);
      expect(AppSessionCoordinator.active, same(coordinator));
      expect(ListSessionCheck.currentSession(), isNull, reason: 'signed out');
      expect(await ListSessionCheck.confirmFor(null), isFalse);

      await client.auth.setInitialSession(_sessionJson(_s1, issued: 1));
      expect(ListSessionCheck.currentSession(), _s1);
      await client.auth.setInitialSession(_sessionJson(_s1, issued: 2));
      expect(ListSessionCheck.currentSession(), _s1,
          reason: 'a refreshed token keeps its session');
      await client.auth.setInitialSession(_sessionJson(_s3, issued: 3));
      expect(ListSessionCheck.currentSession(), _s3,
          reason: 'a new sign-in is a new session');

      expect(await ListSessionCheck.confirmFor(_s1), isFalse,
          reason: 'an earlier session is never confirmed');
      // The coordinator has not authorized s3 here, so validateNow answers
      // false without asking the database.
      expect(await ListSessionCheck.confirmFor(_s3), isFalse);
      expect(rpcs, 0);
    });
  });

  // ---------------------------------------------------------------------
  group('all six lists, through their own screens\' services', () {
    test(
        'an unconfirmed empty list keeps each saved copy and its time; a '
        'confirmed one replaces it; lists with rows are never checked',
        () async {
      await _six<RequestModel>('requests', const RequestsLocalCache(),
          () => _Requests().also, [_request('r1')]);
      await _six<OfferModel>(
          'offers', const OffersLocalCache(), () => _Offers().also, [
        OfferModel(
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
      ]);
      await _six<OwnerModel>(
          'owners', const OwnersLocalCache(), () => _Owners().also, [
        OwnerModel(
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
      ]);
      await _six<OfficeModel>(
          'offices', const OfficesLocalCache(), () => _Offices().also, [
        OfficeModel(
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
      ]);
      await _six<BrokerModel>(
          'brokers', const BrokersLocalCache(), () => _Brokers().also, [
        BrokerModel(
          id: 'b1',
          userId: _alice,
          name: '',
          countryCode: '+971',
          phoneNumber: '',
          notes: '',
        ),
      ]);
      await _six<WatchmenModel>(
          'watchmen', const WatchmenLocalCache(), () => _Watchmen().also, [
        WatchmenModel(
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
      ]);
    });
  });
}

/// A screen's real service: its local-first list and the reads it made.
typedef _Wired<T> = (
  Stream<List<T>> Function() watch,
  List<StreamController<List<T>>> reads
);

/// Through [wire]'s real service and the default session check (set through
/// [ListSessionCheck.debugOverride]): a list with rows is saved without a
/// check; an unconfirmed empty list then keeps it and its time; a confirmed
/// empty list replaces it.
Future<void> _six<T>(
  String entity,
  EncryptedAccountListCache<T> cache,
  _Wired<T> Function() wire,
  List<T> items,
) async {
  var checks = 0;
  var current = false;
  ListSessionCheck.debugOverride = (_) {
    checks++;
    return Future<bool>.value(current);
  };
  final (watch, reads) = wire();

  Future<SavedList<T>?> read(List<T> answer) async {
    final before = reads.length;
    final screen = watch().listen((_) {}, onError: (_) {});
    await _until(() => reads.length > before);
    reads.last.add(answer);
    final saved = await _saved(cache);
    await screen.cancel();
    return saved;
  }

  final first = await read(items);
  expect(first!.items, hasLength(1), reason: entity);
  expect(checks, 0, reason: '$entity: rows are not checked');
  final at = first.info.serverReadAt;
  expect(at, isNotNull, reason: entity);

  final kept = await read(<T>[]);
  expect(checks, 1, reason: entity);
  expect(kept!.items, hasLength(1), reason: '$entity: copy kept');
  expect(kept.info.serverReadAt, at, reason: '$entity: no false freshness');

  current = true;
  final replaced = await read(<T>[]);
  expect(checks, 2, reason: entity);
  expect(replaced!.items, isEmpty, reason: '$entity: confirmed empty');
  ListSessionCheck.debugOverride = null;
}

Stream<List<T>> _next<T>(List<StreamController<List<T>>> reads) {
  final read = StreamController<List<T>>();
  reads.add(read);
  return read.stream;
}

class _Requests extends RequestService {
  _Requests() : super(currentUserId: () => _alice);
  final List<StreamController<List<RequestModel>>> reads = [];
  _Wired<RequestModel> get also => (watchUserRequestsLocalFirst, reads);
  @override
  Stream<List<RequestModel>> getUserRequests() => _next(reads);
}

class _Offers extends OfferService {
  _Offers() : super(currentUserId: () => _alice);
  final List<StreamController<List<OfferModel>>> reads = [];
  _Wired<OfferModel> get also => (watchUserOffersLocalFirst, reads);
  @override
  Stream<List<OfferModel>> getUserOffers() => _next(reads);
}

class _Owners extends OwnerService {
  _Owners() : super(currentUserId: () => _alice);
  final List<StreamController<List<OwnerModel>>> reads = [];
  _Wired<OwnerModel> get also => (watchUserOwnersLocalFirst, reads);
  @override
  Stream<List<OwnerModel>> getUserOwners() => _next(reads);
}

class _Offices extends OfficeService {
  _Offices() : super(currentUserId: () => _alice);
  final List<StreamController<List<OfficeModel>>> reads = [];
  _Wired<OfficeModel> get also => (watchUserOfficesLocalFirst, reads);
  @override
  Stream<List<OfficeModel>> getUserOffices() => _next(reads);
}

class _Brokers extends BrokerService {
  _Brokers() : super(currentUserId: () => _alice);
  final List<StreamController<List<BrokerModel>>> reads = [];
  _Wired<BrokerModel> get also => (watchUserBrokersLocalFirst, reads);
  @override
  Stream<List<BrokerModel>> getUserBrokers() => _next(reads);
}

class _Watchmen extends WatchmenService {
  _Watchmen() : super(currentUserId: () => _alice);
  final List<StreamController<List<WatchmenModel>>> reads = [];
  _Wired<WatchmenModel> get also => (watchUserWatchmenLocalFirst, reads);
  @override
  Stream<List<WatchmenModel>> getUserWatchmen() => _next(reads);
}
