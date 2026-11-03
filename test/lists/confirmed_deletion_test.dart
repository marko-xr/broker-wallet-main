// P3.1d (FU-P2.5E-CRUD-STALE): a record whose deletion the server has
// confirmed never comes back in an offline list — not from the saved copy,
// not from a late server answer that started before the delete, not after a
// restart. Deletion markers ("tombstones") are an authenticated overlay in
// the account's encrypted box; the saved v2 list stays exactly what the
// server returned (D-3), and its time is never advanced by a marker.
//
// Real Hive in a temporary documents directory, the secure-storage test
// store and the real local-first stream.
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
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
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
final _when = DateTime.utc(2026);
final _t0 = DateTime.utc(2026, 11, 3, 8);
final _t1 = DateTime.utc(2026, 11, 3, 9);
const _marker = 'requests_deleted_v1';

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
  late final StreamSubscription<List<T>> subscription;
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
  DateTime Function()? now,
  String? Function()? user,
}) async {
  final screen = _Screen<T>();
  final before = server.reads.length;
  screen.subscription = localFirstList<T>(
    server: server.call,
    cache: cache,
    currentUserId: user ?? () => _alice,
    refreshSignals: const Stream<void>.empty(),
    retryDelays: const [],
    now: now ?? () => _t1,
    isAppActive: () => true,
    confirmEmptyList: (_) => Future<bool>.value(true),
    sessionOf: () => 's1',
  ).listen(screen.lists.add, onError: screen.errors.add);
  await _until(() => server.reads.length > before);
  return screen;
}

Future<SavedList<T>?> _saved<T>(EncryptedAccountListCache<T> cache,
    [String uid = _alice]) async {
  await pumpEventQueue();
  return cache.readSaved(uid);
}

/// The server confirms the delete (or fails with [fails]).
Future<void> _delete<T>(EncryptedAccountListCache<T> cache, String id,
    {Object? fails,
    String? Function()? user,
    String? Function()? session,
    void Function()? during}) {
  return deleteThenRemember<T>(
    cache: cache,
    id: id,
    currentUserId: user ?? () => _alice,
    sessionOf: session ?? () => 's1',
    delete: () async {
      during?.call();
      if (fails != null) throw fails;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const cache = RequestsLocalCache();
  final aliceBox = RequestsLocalCache.boxNameForUid(_alice);

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('confirmed_deletion_test');
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
    EncryptedAccountListCache.debugForgetProcessState();
  });

  tearDown(() async {
    await Hive.close();
    EncryptedAccountListCache.debugForgetProcessState();
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

  Box<String> box() => Hive.box<String>(aliceBox);

  /// Alice's saved copy, from a server list at [_t0].
  Future<void> savedCopy(List<RequestModel> list) async {
    final server = _Server<RequestModel>();
    final screen = await _open(cache, server, now: () => _t0);
    server.reads.last.add(list);
    await _saved(cache);
    await screen.subscription.cancel();
  }

  /// A new process: nothing kept in memory, the box closed.
  Future<void> restart() async {
    await pumpEventQueue();
    await cache.readSaved(_alice); // let queued work finish
    await Hive.close();
    EncryptedAccountListCache.debugForgetProcessState();
  }

  // ---------------------------------------------------------------------
  group('a confirmed deletion stays deleted offline', () {
    test(
        'verified delete, then the refresh fails: the copy and a later '
        'offline screen do not show it; the saved list and its time are the '
        'server\'s', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      final rawBefore = box().get('requests_v2');
      final syncBefore = box().get('requests_sync_v1');
      await _delete(cache, 'a2');

      final server = _Server<RequestModel>();
      final screen = await _open(cache, server);
      server.reads.last.addError(const SocketException('offline'));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0, reason: 'no new refresh claimed');
      expect(saved.info.hidesConfirmedDeletions, isTrue);
      expect(screen.lists.map(_ids), [
        ['a1']
      ]);
      expect(box().get('requests_v2'), rawBefore, reason: 'D-3: v2 untouched');
      expect(box().get('requests_sync_v1'), syncBefore);
      await screen.subscription.cancel();
    });

    test('after a restart the marker still hides it', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      await _delete(cache, 'a2');
      await restart();
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
    });

    test(
        'an already-deleted record (P3.1a) and a fresh one are both '
        'remembered; an earlier v1 copy is filtered too', () async {
      await cache.write(_alice, [_request('a1'), _request('a2')]);
      final payload = (json.decode(box().get('requests_v2')!) as Map)['p'];
      await box().delete('requests_v2');
      await box().put('requests_v1', payload as String);
      await _delete(cache, 'a2');
      await restart();
      final saved = await cache.readSaved(_alice);
      expect(saved!.info.authenticated, isFalse);
      expect(_ids(saved.items), ['a1']);
    });
  });

  // ---------------------------------------------------------------------
  group('server answers around the delete', () {
    test(
        'an answer that started before the delete and arrives after it is '
        'shown without the record and is not saved', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      final rawBefore = box().get('requests_v2');
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      await _delete(cache, 'a2'); // the read above is still in flight
      server.reads.last.add([_request('a1'), _request('a2')]); // stale

      final saved = await _saved(cache);
      expect(screen.lists.last.map((r) => r.id), ['a1']);
      expect(box().get('requests_v2'), rawBefore, reason: 'stale: not saved');
      expect(saved!.info.serverReadAt, _t0, reason: 'not a new refresh');
      expect(_ids(saved.items), ['a1']);
      await screen.subscription.cancel();
    });

    test(
        'a later server list without the record is saved; its marker is kept '
        '(a list may be cut short by the server row cap, so absence proves '
        'nothing)', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      await _delete(cache, 'a2');
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      server.reads.last.add([_request('a1')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t1);
      expect(box().containsKey(_marker), isTrue, reason: 'not retired');
      await screen.subscription.cancel();
    });

    test(
        'concurrent deletes and a refresh: both markers are kept, no update '
        'is lost', () async {
      await savedCopy([_request('a1'), _request('a2'), _request('a3')]);
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      await Future.wait([
        _delete(cache, 'a2'),
        _delete(cache, 'a3'),
        Future(() => server.reads.last.add([_request('a1')])),
      ]);
      await restart();
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['a1']);
      // Both markers survived the race: an old copy with both is filtered.
      await cache
          .write(_alice, [_request('a1'), _request('a2'), _request('a3')]);
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1']);
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('no marker without a confirmed delete for this account and session',
      () {
    test('a delete the server did not confirm, or that failed, marks nothing',
        () async {
      await savedCopy([_request('a1'), _request('a2')]);
      for (final failure in <Object>[
        const CoreEntityNotDeleted(),
        const SocketException('offline'),
        const sb.PostgrestException(
            message: 'permission denied', code: '42501'),
      ]) {
        await expectLater(
            _delete(cache, 'a2', fails: failure), throwsA(same(failure)));
      }
      await restart();
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1', 'a2']);
      expect(Hive.box<String>(aliceBox).containsKey(_marker), isFalse);
    });

    test('the account changes during the delete: no marker for either',
        () async {
      await savedCopy([_request('a1'), _request('a2')]);
      String? user = _alice;
      await _delete(cache, 'a2', user: () => user, during: () => user = _bob);
      await restart();
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1', 'a2']);
      expect(await cache.readSaved(_bob), isNull);
    });

    test(
        'a sign-out and sign-in to the same account during the delete: no '
        'marker', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      var session = 's1';
      await _delete(cache, 'a2',
          session: () => session, during: () => session = 's3');
      await restart();
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1', 'a2']);
    });
  });

  // ---------------------------------------------------------------------
  // Strict policy (owner decision, §7AE-1): markers that cannot be read
  // block that list for that account. Nothing replaces, resets or deletes
  // them automatically — no server list is evidence enough, as a lagging
  // read could still hold a record whose deletion they recorded.
  group('unreadable markers block the list (strict)', () {
    /// Alice's Requests: a1 and a2 saved, a2's deletion confirmed, then the
    /// marker record damaged (its tag changed) and the app restarted.
    Future<Map<String, String?>> blockedAlice() async {
      await savedCopy([_request('a1'), _request('a2')]);
      await _delete(cache, 'a2');
      final sealed =
          Map<String, Object?>.from(json.decode(box().get(_marker)!) as Map);
      final tag = base64Url.decode(sealed['t']! as String);
      await box().put(
          _marker,
          json.encode({
            ...sealed,
            't': base64Url.encode([...tag]..[0] ^= 1)
          }));
      await restart();
      await cache.readSaved(_alice); // opens the box again
      return {
        for (final key in ['requests_v2', 'requests_sync_v1', _marker])
          key: box().get(key),
      };
    }

    Map<String, String?> now() => {
          for (final key in ['requests_v2', 'requests_sync_v1', _marker])
            key: box().get(key),
        };

    test(
        'after a restart the copy is withheld and the reopened screen gets '
        'one integrity error: no list, no server read, no endless loading',
        () async {
      await blockedAlice();
      expect(await cache.readSaved(_alice), isNull);
      final server = _Server<RequestModel>();
      final screen = _Screen<RequestModel>();
      screen.subscription = localFirstList<RequestModel>(
        server: server.call,
        cache: cache,
        currentUserId: () => _alice,
        refreshSignals: const Stream<void>.empty(),
        retryDelays: const [Duration(milliseconds: 5)],
        isAppActive: () => true,
        confirmEmptyList: (_) => Future<bool>.value(true),
        sessionOf: () => 's1',
      ).listen(screen.lists.add, onError: screen.errors.add);
      await _until(() => screen.errors.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(screen.errors.single, isA<ListIntegrityBlocked>());
      expect(screen.lists, isEmpty);
      expect(server.reads, isEmpty, reason: 'nothing to show it in');
      await screen.subscription.cancel();
    });

    test(
        'a valid server list — even one holding the deleted record — is not '
        'saved, and the markers, the list and its time stay byte for byte',
        () async {
      final before = await blockedAlice();
      await cache.write(_alice, [_request('a1')], serverReadAt: _t1);
      await cache.write(_alice, [_request('a1'), _request('a2')],
          serverReadAt: _t1); // stale: holds a2
      expect(now(), before, reason: 'nothing replaced, nothing advanced');
      expect(await cache.readSaved(_alice), isNull);
    });

    test('a list already being read when the block is found is not shown',
        () async {
      await savedCopy([_request('a1'), _request('a2')]);
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      await box().put(_marker, 'damaged'); // found by the next save
      await cache.write(_alice, [_request('a1')], serverReadAt: _t1);
      expect(cache.isIntegrityBlocked(_alice), isTrue);
      server.reads.last.add([_request('a1'), _request('a2')]);
      await pumpEventQueue();
      expect(
          screen.lists.map(_ids),
          [
            ['a1', 'a2']
          ],
          reason: 'only the copy shown before the block');
      expect(screen.errors.single, isA<ListIntegrityBlocked>());
      await screen.subscription.cancel();
    });

    test(
        'blocked, then the box key is lost in the same run: no D-2 recovery '
        'replaces the box (it would destroy the damaged markers)', () async {
      await blockedAlice();
      await Hive.close(); // the block stays known for this run
      final sep = Platform.pathSeparator;
      final file = File('${root.path}$sep'
          '${EncryptedAccountListCache.directoryName}$sep$aliceBox.hive');
      final bytes = file.readAsBytesSync();
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      await cache.write(_alice, [_request('a1')],
          serverReadAt: _t1, mayRecover: () => true);
      expect(file.readAsBytesSync(), bytes, reason: 'box not replaced');
      expect(
          await const FlutterSecureStorage()
              .read(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice)),
          isNull,
          reason: 'no new key');
    });

    test(
        'a new confirmed delete does not touch the damaged record or the '
        'list', () async {
      final before = await blockedAlice();
      await _delete(cache, 'a1');
      expect(now(), before);
      await restart();
      expect(await cache.readSaved(_alice), isNull, reason: 'still blocked');
    });

    test(
        'other accounts and Alice\'s other lists stay usable; Bob is never '
        'blocked by Alice\'s markers', () async {
      const offers = OffersLocalCache();
      await offers.write(_alice, []);
      await blockedAlice();
      await cache.write(_bob, [_request('b1', _bob)], serverReadAt: _t1);
      expect(_ids((await cache.readSaved(_bob))!.items), ['b1']);
      expect(cache.isIntegrityBlocked(_bob), isFalse);
      expect(await offers.readSaved(_alice), isNotNull);
      expect(offers.isIntegrityBlocked(_alice), isFalse);
    });

    test('Delete Account removes the block with the account\'s data', () async {
      await blockedAlice();
      await cache.forgetAccount(_alice);
      expect(cache.isIntegrityBlocked(_alice), isFalse);
      await cache.write(_alice, [_request('a9')], serverReadAt: _t1);
      expect(_ids((await cache.readSaved(_alice))!.items), ['a9']);
    });
  });

  // ---------------------------------------------------------------------
  group('damaged, missing or forged markers fail safe', () {
    test(
        'markers that are not JSON, belong to another account, or sit in the '
        'list\'s place are refused', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      await _delete(cache, 'a2');
      final good = box().get(_marker)!;
      final list = box().get('requests_v2')!;
      for (final bad in ['not json', list, '{"v":1,"p":"{}","t":"AAAA"}']) {
        await box().put(_marker, bad);
        await restart();
        expect(await cache.readSaved(_alice), isNull, reason: bad);
      }
      // A marker in the list's place is not a list.
      await box().put('requests_v2', good);
      await restart();
      expect(await cache.readSaved(_alice), isNull);
    });

    test(
        'a marker made for another account under the SAME box key is refused: '
        'the account is part of what the tag covers', () async {
      final shared = RequestsLocalCache(keyStore: _OneKeyForAll());
      await shared.write(_alice, [_request('a1'), _request('a2')]);
      await shared.write(_bob, [_request('b1', _bob)]);
      await deleteThenRemember<RequestModel>(
          cache: shared,
          id: 'a2',
          currentUserId: () => _bob,
          sessionOf: () => 's1',
          delete: () async {});
      final bobs = Hive.box<String>(RequestsLocalCache.boxNameForUid(_bob))
          .get(_marker)!;
      await box().put(_marker, bobs);
      await restart();
      expect(await shared.readSaved(_alice), isNull);
    });

    test('Bob\'s valid marker copied into Alice\'s box is refused', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      await cache.write(_bob, [_request('b1', _bob), _request('a2', _bob)]);
      await _delete(cache, 'a2', user: () => _bob);
      final bobs = Hive.box<String>(RequestsLocalCache.boxNameForUid(_bob))
          .get(_marker)!;
      await box().put(_marker, bobs);
      await restart();
      expect(await cache.readSaved(_alice), isNull,
          reason: 'not Alice\'s: withheld, never trusted');
    });

    test(
        'with no saved box yet, the marker lives for this run: a stale answer '
        'with the record is shown without it and not saved', () async {
      await _delete(cache, 'a2'); // nothing cached yet
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      server.reads.last.add([_request('a1'), _request('a2')]);
      await pumpEventQueue();
      expect(screen.lists.last.map((r) => r.id), ['a1']);
      expect(await cache.readSaved(_alice), isNull, reason: 'stale: unsaved');
      server.reads.last.add([_request('a1')]);
      expect(_ids((await _saved(cache))!.items), ['a1']);
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('capacity', () {
    // The real limit is 1000; a small one keeps the test quick.
    setUp(() => EncryptedAccountListCache.maxConfirmedDeletions = 5);
    tearDown(() => EncryptedAccountListCache.maxConfirmedDeletions =
        EncryptedAccountListCache.defaultMaxConfirmedDeletions);

    test('the production limit is 1000 markers per list and account', () {
      expect(EncryptedAccountListCache.defaultMaxConfirmedDeletions, 1000);
    });

    test(
        'at the marker limit no marker is dropped; a deletion that cannot be '
        'marked removes a copy that holds it, and is never saved back',
        () async {
      final limit = EncryptedAccountListCache.maxConfirmedDeletions;
      await savedCopy([_request('a1'), _request('a2')]);
      for (var i = 0; i < limit; i++) {
        await _delete(cache, 'old$i');
      }
      await restart();
      // An old copy holding every marked record still hides them all.
      await cache.write(_alice, [
        _request('a1'),
        _request('a2'),
        _request('old0'),
        _request('old${limit - 1}'),
      ]);
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1', 'a2']);

      await _delete(cache, 'a2'); // over the limit, and in the copy
      expect(await _saved(cache), isNull, reason: 'copy removed, not shown');
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      server.reads.last.add([_request('a1'), _request('a2')]); // stale
      await pumpEventQueue();
      expect(screen.lists.last.map((r) => r.id), ['a1']);
      expect(await cache.readSaved(_alice), isNull, reason: 'not saved back');
      server.reads.last.add([_request('a1'), _request('old0')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1'], reason: 'old markers all kept');
      await screen.subscription.cancel();
    });

    test(
        'removing Alice\'s Requests copy at the limit touches no other list '
        'and no other account; after a restart it stays removed', () async {
      final limit = EncryptedAccountListCache.maxConfirmedDeletions;
      const offers = OffersLocalCache();
      await savedCopy([_request('a1'), _request('a2')]);
      await offers.write(_alice, []);
      await cache.write(_bob, [_request('b1', _bob), _request('a2', _bob)]);
      final offersBefore =
          Hive.box<String>(OffersLocalCache.boxNameForUid(_alice))
              .get('offers_v2');
      final bobBefore = Hive.box<String>(RequestsLocalCache.boxNameForUid(_bob))
          .get('requests_v2');
      for (var i = 0; i < limit; i++) {
        await _delete(cache, 'old$i');
      }
      await _delete(cache, 'a2'); // over the limit, held by the copy
      await restart();
      expect(await cache.readSaved(_alice), isNull,
          reason: 'stays removed: a2 cannot come back offline');
      expect(await offers.readSaved(_alice), isNotNull);
      expect(
          Hive.box<String>(OffersLocalCache.boxNameForUid(_alice))
              .get('offers_v2'),
          offersBefore);
      expect(_ids((await cache.readSaved(_bob))!.items), ['b1', 'a2'],
          reason: 'Bob\'s own a2 is not Alice\'s deletion');
      expect(
          Hive.box<String>(RequestsLocalCache.boxNameForUid(_bob))
              .get('requests_v2'),
          bobBefore);
    });

    test(
        'over the limit, a deletion not in the copy leaves the copy in '
        'place', () async {
      final limit = EncryptedAccountListCache.maxConfirmedDeletions;
      await savedCopy([_request('a1')]);
      for (var i = 0; i < limit; i++) {
        await _delete(cache, 'old$i');
      }
      await _delete(cache, 'elsewhere');
      expect(_ids((await _saved(cache))!.items), ['a1']);
    });
  });

  // ---------------------------------------------------------------------
  group('accounts', () {
    test('Delete Account removes that account\'s markers only', () async {
      await savedCopy([_request('a1'), _request('a2')]);
      await _delete(cache, 'a2');
      await cache.write(_bob, [_request('b1', _bob), _request('b2', _bob)]);
      await _delete(cache, 'b2', user: () => _bob);
      await cache.forgetAccount(_alice);
      await restart();
      await cache.write(_alice, [_request('a1'), _request('a2')]);
      expect(_ids((await cache.readSaved(_alice))!.items), ['a1', 'a2'],
          reason: 'Alice\'s marker went with her account');
      expect(_ids((await cache.readSaved(_bob))!.items), ['b1']);
    });
  });

  // ---------------------------------------------------------------------
  test(
      'invariant: nothing in the app or the migrations clears deleted_at, so '
      'a confirmed soft delete is final', () {
    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync());
    final undelete = RegExp(r"'deleted_at'\s*:\s*null");
    expect(dart.where(undelete.hasMatch), isEmpty);
    final sql = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync().toLowerCase());
    expect(sql.where((s) => s.contains(RegExp(r'set\s+deleted_at\s*=\s*null'))),
        isEmpty);
  });

  // ---------------------------------------------------------------------
  group('all six lists, through their own screens\' services', () {
    test(
        'each remembers a confirmed delete and hides it after a failed '
        'refresh; an unconfirmed delete hides nothing', () async {
      final core = _Core();
      await _six<RequestModel>(
          'requests',
          const RequestsLocalCache(),
          RequestService(currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserRequestsLocalFirst(),
          (s, id) => s.deleteRequest(id),
          (id) => _request(id),
          (r) => r.id,
          core);
      await _six<OfferModel>(
          'offers',
          const OffersLocalCache(),
          OfferService(currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserOffersLocalFirst(),
          (s, id) => s.deleteOffer(id),
          (id) => OfferModel(
                id: id,
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
          (o) => o.id,
          core);
      await _six<OwnerModel>(
          'owners',
          const OwnersLocalCache(),
          OwnerService(currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserOwnersLocalFirst(),
          (s, id) => s.deleteOwner(id),
          (id) => OwnerModel(
                id: id,
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
          (o) => o.id,
          core);
      await _six<OfficeModel>(
          'offices',
          const OfficesLocalCache(),
          OfficeService(currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserOfficesLocalFirst(),
          (s, id) => s.deleteOffice(id),
          (id) => OfficeModel(
                id: id,
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
          (o) => o.id,
          core);
      await _six<BrokerModel>(
          'brokers',
          const BrokersLocalCache(),
          BrokerService(currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserBrokersLocalFirst(),
          (s, id) => s.deleteBroker(id),
          (id) => BrokerModel(
                id: id,
                userId: _alice,
                name: '',
                countryCode: '+971',
                phoneNumber: '',
                notes: '',
              ),
          (b) => b.id,
          core);
      await _six<WatchmenModel>(
          'watchmen',
          const WatchmenLocalCache(),
          WatchmenService(
              currentUserId: () => _alice, coreEntities: () => core),
          (s) => s.watchUserWatchmenLocalFirst(),
          (s, id) => s.deleteWatchmen(id),
          (id) => WatchmenModel(
                id: id,
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
          (w) => w.id,
          core);
    });
  });
}

/// One box key for every account (never so in the app): only the tag's own
/// binding to the account can then tell two accounts' markers apart.
class _OneKeyForAll implements AccountCacheKeyStore {
  static final List<int> _key = List<int>.generate(32, (i) => i);
  @override
  Future<List<int>?> read(String uid) async => _key;
  @override
  Future<void> write(String uid, List<int> key) async {}
  @override
  Future<void> delete(String uid) async {}
}

/// The core entity service, with its server reads and deletes answered by the
/// test: a list read answers [answer]; a delete succeeds unless [refuse].
class _Core extends SupabaseCoreEntitiesService {
  _Core() : this._(_client());

  _Core._(sb.SupabaseClient client)
      : super(
          client: client,
          offerMedia: R2OfferMediaUploadService(
            supabaseClient: client,
            httpClient: MockClient((_) async => http.Response('{}', 200)),
          ),
        );

  static sb.SupabaseClient _client() => sb.SupabaseClient(
      'https://unit-test.supabase.co', 'unit-test-publishable-key',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false));

  List<Object> answer = const [];
  bool fail = false;
  bool refuse = false;

  Stream<List<T>> _read<T>() => fail
      ? Stream<List<T>>.error(const SocketException('offline'))
      : Stream<List<T>>.value(answer.cast<T>());

  Future<void> _del() async {
    if (refuse) throw const CoreEntityNotDeleted();
  }

  @override
  Stream<List<RequestModel>> getRequests() => _read();
  @override
  Stream<List<OfferModel>> getOffers() => _read();
  @override
  Stream<List<OwnerModel>> getOwners() => _read();
  @override
  Stream<List<OfficeModel>> getOffices() => _read();
  @override
  Stream<List<BrokerModel>> getBrokers() => _read();
  @override
  Stream<List<WatchmenModel>> getWatchmen() => _read();
  @override
  Future<void> deleteRequest(String id) => _del();
  @override
  Future<void> deleteOffer(String id) => _del();
  @override
  Future<void> deleteOwner(String id) => _del();
  @override
  Future<void> deleteOffice(String id) => _del();
  @override
  Future<void> deleteBroker(String id) => _del();
  @override
  Future<void> deleteWatchman(String id) => _del();
}

/// Through [service]: a list is saved, a delete is confirmed (or refused),
/// the next refresh fails, and the reopened offline list is checked.
Future<void> _six<T extends Object>(
  String entity,
  EncryptedAccountListCache<T> cache,
  dynamic service,
  Stream<List<T>> Function(dynamic) watch,
  Future<void> Function(dynamic, String) delete,
  T Function(String) make,
  String? Function(T) idOf,
  _Core core,
) async {
  Future<List<String?>> openOnce() async {
    final shown = <List<T>>[];
    final sub = watch(service).listen(shown.add, onError: (_) {});
    await _until(() => shown.isNotEmpty || core.fail);
    await pumpEventQueue();
    await sub.cancel();
    final saved = await cache.readSaved(_alice);
    return saved?.items.map(idOf).toList() ?? const ['<nothing>'];
  }

  core
    ..fail = false
    ..refuse = false
    ..answer = [make('x1'), make('x2'), make('x3')];
  expect(await openOnce(), ['x1', 'x2', 'x3'], reason: entity);

  await delete(service, 'x2'); // confirmed
  core.refuse = true;
  await expectLater(delete(service, 'x3'), throwsA(isA<CoreEntityNotDeleted>()),
      reason: entity);
  core.fail = true; // the refresh after the delete fails
  expect(await openOnce(), ['x1', 'x3'], reason: '$entity: x2 hidden only');
}
