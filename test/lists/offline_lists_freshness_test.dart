// P2.5c: when the server last returned each saved list, what a list screen is
// showing, and what is (not) known about a list's completeness.
//
// Real Hive in a temporary documents directory and the secure-storage test
// store. Lists reach the cache through the real local-first stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
final _when = DateTime.utc(2026);
final _t0 = DateTime.utc(2026, 11, 2, 8);
final _t1 = DateTime.utc(2026, 11, 2, 9, 30);

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

/// A server whose every read is a stream the test answers.
class _Server<T> {
  final List<StreamController<List<T>>> reads = [];
  Stream<List<T>> call() {
    final read = StreamController<List<T>>();
    reads.add(read);
    return read.stream;
  }
}

/// One list screen: what it was shown and told.
class _Screen<T> {
  final List<List<T>> lists = [];
  final List<Object> errors = [];
  final List<LocalListStatus> statuses = [];
  late final StreamSubscription<List<T>> subscription;
  LocalListStatus get status => statuses.last;
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timed out');
}

/// Opens a list screen on the real local-first stream, and waits until its
/// first server read has started.
Future<_Screen<T>> _open<T>(
  EncryptedAccountListCache<T> cache,
  _Server<T> server, {
  String? Function()? user,
  DateTime Function()? now,
  List<Duration> retryDelays = const [],
}) async {
  final screen = _Screen<T>();
  final before = server.reads.length;
  screen.subscription = localFirstList<T>(
    server: server.call,
    cache: cache,
    currentUserId: user ?? () => _alice,
    refreshSignals: const Stream<void>.empty(),
    retryDelays: retryDelays,
    now: now ?? () => _t0,
    isAppActive: () => true,
    onStatus: screen.statuses.add,
  ).listen(screen.lists.add, onError: screen.errors.add);
  await _until(() => server.reads.length > before);
  return screen;
}

/// What is saved once every write queued so far has finished.
Future<SavedList<T>?> _saved<T>(EncryptedAccountListCache<T> cache,
    [String uid = _alice]) async {
  await pumpEventQueue();
  return cache.readSaved(uid);
}

/// The record format, rebuilt independently of the code under test.
List<int> _lengthPrefixed(List<List<int>> parts) {
  final out = BytesBuilder();
  for (final part in parts) {
    out
      ..add((ByteData(4)..setUint32(0, part.length)).buffer.asUint8List())
      ..add(part);
  }
  return out.takeBytes();
}

String _sealRecord(List<int> boxKey, String uid, String listKey, String body) {
  final mac = Hmac(sha256, boxKey)
      .convert(utf8.encode('broker_wallet/offline_lists/v2/mac'))
      .bytes;
  final tag = Hmac(sha256, mac)
      .convert(_lengthPrefixed([
        utf8.encode('bw-offline-list-sync'),
        utf8.encode('1'),
        utf8.encode(listKey),
        utf8.encode(uid),
        utf8.encode(body),
      ]))
      .bytes;
  return json.encode({'v': 1, 'p': body, 't': base64Url.encode(tag)});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const cache = RequestsLocalCache();
  final aliceBox = RequestsLocalCache.boxNameForUid(_alice);
  const record = 'requests_sync_v1';

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('offline_lists_freshness_test');
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

  Box<String> box(String name) => Hive.box<String>(name);

  Future<List<int>> aliceKey() async =>
      base64.decode((await const FlutterSecureStorage()
          .read(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice)))!);

  /// One server list for Alice on a fresh screen, read at [at].
  Future<void> serverList(List<RequestModel> list, {DateTime? at}) async {
    final server = _Server<RequestModel>();
    final screen = await _open(cache, server, now: () => at ?? _t0);
    server.reads.last.add(list);
    await _saved(cache);
    await screen.subscription.cancel();
  }

  // ---------------------------------------------------------------------
  group('what is saved, and when', () {
    test(
        'no saved list is nothing; an authoritative empty server list is '
        'saved as empty, with its time', () async {
      expect(await cache.readSaved(_alice), isNull);
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server);
      expect(screen.status.showing, LocalListSource.nothing);
      expect(screen.status.refreshing, isTrue);
      expect(screen.status.lastServerReadAt, isNull);

      server.reads.last.add(const []);
      final saved = await _saved(cache);
      expect(saved, isNotNull, reason: 'an empty list is not a missing one');
      expect(saved!.items, isEmpty);
      expect(saved.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.lists, [isEmpty]);
      expect(screen.status.showing, LocalListSource.server);
      expect(screen.status.refreshing, isFalse);
      expect(screen.status.lastReadFailed, isFalse);
      expect(screen.status.lastServerReadAt, _t0);
      await screen.subscription.cancel();
    });

    test(
        'the time is stored in UTC with the exact list it describes, and '
        'survives a restart', () async {
      final local = DateTime(2026, 11, 2, 12, 15); // device local time
      await serverList([_request('s1')], at: local);

      final envelope =
          Map<String, Object?>.from(json.decode(box(aliceBox).get(record)!));
      expect(envelope.keys.toSet(), {'v', 'p', 't'});
      expect(envelope['v'], 1);
      final body = envelope['p']! as String;
      expect(box(aliceBox).get(record),
          _sealRecord(await aliceKey(), _alice, 'requests_v1', body),
          reason: 'tag under the derived key, own label, length-prefixed');
      final fields = Map<String, Object?>.from(json.decode(body));
      final listTag =
          (json.decode(box(aliceBox).get('requests_v2')!) as Map)['t'];
      expect(fields, {
        'serverReadAt': local.toUtc().toIso8601String(),
        'completeness': 'unknown',
        'list': listTag,
      });

      await Hive.close();
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['s1']);
      expect(saved.info.serverReadAt, local.toUtc());
      expect(saved.info.serverReadAt!.isUtc, isTrue);
    });

    test(
        'a failed refresh keeps the saved list and its time, and the screen '
        'says the copy is shown and the read failed', () async {
      await serverList([_request('s1')], at: _t0);

      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      expect(screen.status.showing, LocalListSource.savedCopy);
      expect(screen.status.refreshing, isTrue);
      expect(screen.status.lastServerReadAt, _t0);

      server.reads.last.addError(const SocketException('offline'));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['s1']);
      expect(saved.info.serverReadAt, _t0, reason: 'a failure never advances');
      expect(screen.lists.map(_ids), [
        ['s1']
      ]);
      expect(screen.errors, hasLength(1));
      expect(screen.status.showing, LocalListSource.savedCopy);
      expect(screen.status.refreshing, isFalse);
      expect(screen.status.lastReadFailed, isTrue);
      expect(screen.status.lastServerReadAt, _t0);
      await screen.subscription.cancel();
    });

    test('with no saved list, a failed read is not an empty list', () async {
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server);
      server.reads.last.addError(const SocketException('offline'));
      await pumpEventQueue();
      expect(screen.lists, isEmpty);
      expect(screen.errors, hasLength(1));
      expect(screen.status.showing, LocalListSource.nothing);
      expect(screen.status.lastReadFailed, isTrue);
      expect(await cache.readSaved(_alice), isNull);
      await screen.subscription.cancel();
    });

    test(
        'a later list on the same screen (the re-read after an add, edit or '
        'delete) replaces the saved list and advances its time', () async {
      var clock = _t0;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => clock);
      server.reads.last.add([_request('a1'), _request('a2')]);
      expect((await _saved(cache))!.info.serverReadAt, _t0);

      clock = _t1;
      server.reads.last.add([_request('a1')]); // a2 deleted
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t1);
      expect(screen.status.lastServerReadAt, _t1);
      await screen.subscription.cancel();
    });

    test(
        'a session the server refuses stops the list; the saved list and its '
        'time stay', () async {
      await serverList([_request('s1')], at: _t0);
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      server.reads.last.addError(StateError('session_superseded'));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['s1']);
      expect(saved.info.serverReadAt, _t0);
      expect(screen.status.lastReadFailed, isTrue);
      await screen.subscription.cancel();
    });

    test('deleting the account removes the list and its time', () async {
      await serverList([_request('s1')]);
      await cache.forgetAccount(_alice);
      expect(await cache.readSaved(_alice), isNull);
      await serverList([_request('s2')], at: _t1);
      final saved = await cache.readSaved(_alice);
      expect(saved!.info.serverReadAt, _t1);
    });
  });

  // ---------------------------------------------------------------------
  group('earlier lists and records', () {
    test(
        'an earlier v1 list reads as unauthenticated with no time; the first '
        'server list replaces it with a timed v2 list', () async {
      await cache.write(_alice, [_request('v1a')]);
      final b = box(aliceBox);
      final payload = (json.decode(b.get('requests_v2')!) as Map)['p'];
      await b.delete('requests_v2');
      await b.put('requests_v1', payload as String);
      await Hive.close();

      final earlier = await cache.readSaved(_alice);
      expect(_ids(earlier!.items), ['v1a']);
      expect(earlier.info.authenticated, isFalse);
      expect(earlier.info.serverReadAt, isNull);

      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      expect(screen.status.showing, LocalListSource.savedCopy);
      expect(screen.status.lastServerReadAt, isNull);
      server.reads.last.add([_request('s1')]);
      final saved = await _saved(cache);
      expect(saved!.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, _t1);
      expect(box(aliceBox).containsKey('requests_v1'), isFalse);
      await screen.subscription.cancel();
    });

    test(
        'a v2 list saved before times were recorded still reads, with no '
        'time', () async {
      await cache.write(_alice, [_request('a1')]);
      expect(box(aliceBox).containsKey(record), isFalse);
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.authenticated, isTrue);
      expect(saved.info.serverReadAt, isNull);
    });

    test(
        'a write without a time that changes the list leaves the time '
        'unknown; the same list keeps its time', () async {
      await serverList([_request('a1')], at: _t0);
      await cache.write(_alice, [_request('a1')]);
      expect((await cache.readSaved(_alice))!.info.serverReadAt, _t0);
      await cache.write(_alice, [_request('a2')]);
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['a2']);
      expect(saved.info.serverReadAt, isNull);
    });

    test('a damaged or forged record never gives a time, nor hides the list',
        () async {
      await serverList([_request('a1')], at: _t0);
      final key = await aliceKey();
      final good = box(aliceBox).get(record)!;
      final envelope = Map<String, Object?>.from(json.decode(good));
      final body = envelope['p']! as String;
      final fields = Map<String, Object?>.from(json.decode(body));
      String resealed(Map<String, Object?> f) =>
          _sealRecord(key, _alice, 'requests_v1', json.encode(f));
      final tag = base64Url.decode(envelope['t']! as String);

      final variants = <String, String>{
        'tag changed': json.encode({
          ...envelope,
          't': base64Url.encode([...tag]..[0] ^= 1)
        }),
        'not JSON': 'not json',
        'version 2': json.encode({...envelope, 'v': 2}),
        'extra field': json.encode({...envelope, 'x': 1}),
        'no tag': json.encode({'v': 1, 'p': body}),
        'body changed, old tag':
            json.encode({...envelope, 'p': body.replaceFirst('08', '09')}),
        'another list': resealed({...fields, 'list': 'AAAA'}),
        'time not UTC':
            resealed({...fields, 'serverReadAt': '2026-11-02T08:00:00'}),
        'time not a string': resealed({...fields, 'serverReadAt': 1}),
        'time unreadable': resealed({...fields, 'serverReadAt': 'soon'}),
        'body a list': _sealRecord(key, _alice, 'requests_v1', '[]'),
      };
      expect((await cache.readSaved(_alice))!.info.serverReadAt, _t0,
          reason: 'the untouched record is valid');
      for (final variant in variants.entries) {
        await box(aliceBox).put(record, variant.value);
        final saved = await cache.readSaved(_alice);
        expect(_ids(saved?.items), ['a1'], reason: variant.key);
        expect(saved!.info.serverReadAt, isNull, reason: variant.key);
      }
    });

    test('a record is bound to its account and cannot pass for a list',
        () async {
      await serverList([_request('a1')], at: _t0);
      final aliceRecord = box(aliceBox).get(record)!;
      final aliceList = box(aliceBox).get('requests_v2')!;

      // Bob's own valid record, under Bob's account, in Alice's box.
      final key = await aliceKey();
      final listTag = (json.decode(aliceList) as Map)['t'];
      await box(aliceBox).put(
          record,
          _sealRecord(
              key,
              _bob,
              'requests_v1',
              json.encode({
                'serverReadAt': _t1.toIso8601String(),
                'completeness': 'unknown',
                'list': listTag,
              })));
      expect((await cache.readSaved(_alice))!.info.serverReadAt, isNull);

      // A list where the record goes, and a record where the list goes.
      await box(aliceBox).put(record, aliceList);
      expect((await cache.readSaved(_alice))!.info.serverReadAt, isNull);
      await box(aliceBox).put('requests_v2', aliceRecord);
      expect(await cache.readSaved(_alice), isNull);
    });

    test(
        'an older record put back beside a newer list gives no time; an older '
        'list put back with its own record reads as that older copy', () async {
      await serverList([_request('a1')], at: _t0);
      final oldList = box(aliceBox).get('requests_v2')!;
      final oldRecord = box(aliceBox).get(record)!;
      await serverList([_request('a2')], at: _t1);

      await box(aliceBox).put(record, oldRecord);
      final mixed = await cache.readSaved(_alice);
      expect(_ids(mixed!.items), ['a2']);
      expect(mixed.info.serverReadAt, isNull);

      // A replay of a whole older copy is not detected (known limit); it
      // reads as what it is: that copy, with that copy's time.
      await box(aliceBox).put('requests_v2', oldList);
      final replayed = await cache.readSaved(_alice);
      expect(_ids(replayed!.items), ['a1']);
      expect(replayed.info.serverReadAt, _t0);
    });
  });

  // ---------------------------------------------------------------------
  group('the device clock', () {
    test('a time after now (the clock set back) has no age', () {
      final info = SavedListInfo(authenticated: true, serverReadAt: _t1);
      expect(info.ageAt(_t1.add(const Duration(minutes: 5))),
          const Duration(minutes: 5));
      expect(info.ageAt(_t1), Duration.zero);
      expect(info.ageAt(_t0), isNull);
      expect(const SavedListInfo(authenticated: true).ageAt(_t1), isNull);
    });

    test(
        'a clock set back between reads still records the newer read: the '
        'latest server list wins, not the largest time', () async {
      await serverList([_request('a1')], at: _t1);
      await serverList([_request('a2')], at: _t0); // clock set back
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['a2']);
      expect(saved.info.serverReadAt, _t0);
    });
  });

  // ---------------------------------------------------------------------
  group('accounts, closing and late answers', () {
    test(
        'an answer that arrives after the account changed records nothing '
        'for either account', () async {
      await serverList([_request('a1')], at: _t0);
      var user = _alice;
      final server = _Server<RequestModel>();
      final screen =
          await _open(cache, server, user: () => user, now: () => _t1);
      final reported = screen.statuses.length;
      user = _bob;
      server.reads.last.add([_request('late')]);

      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
      expect(await cache.readSaved(_bob), isNull);
      expect(screen.statuses, hasLength(reported), reason: 'no more status');
      await screen.subscription.cancel();
    });

    test('a screen closed before the server answers records nothing', () async {
      await serverList([_request('a1')], at: _t0);
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => _t1);
      await screen.subscription.cancel();
      server.reads.last.add([_request('late')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t0);
    });

    test(
        'a box recovered after its key was lost carries the time of the '
        'server list that recovered it', () async {
      await serverList([_request('a1')], at: _t0);
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      expect(await cache.readSaved(_alice), isNull);

      await serverList([_request('s1')], at: _t1);
      final saved = await cache.readSaved(_alice);
      expect(_ids(saved!.items), ['s1']);
      expect(saved.info.serverReadAt, _t1);
    });
  });

  // ---------------------------------------------------------------------
  // P2.5e: what the saved copy holds after a successful add, edit or delete
  // whose re-read fails. These record current behaviour (a known, bounded
  // gap), not a fix: the copy is never changed locally, so it stays the
  // last server list, with that list's time.
  group('after a successful change whose re-read fails (known limit)', () {
    test(
        'a deleted record stays in the saved copy, with the time from before '
        'the delete, and a later screen offline shows it', () async {
      var clock = _t0;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server, now: () => clock);
      server.reads.last.add([_request('a1'), _request('a2')]);
      await _saved(cache);

      // The delete of a2 is accepted; the re-read that follows it fails.
      clock = _t1;
      server.reads.last.addError(const SocketException('offline'));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1', 'a2']);
      expect(saved.info.serverReadAt, _t0, reason: 'from before the delete');
      expect(screen.status.lastReadFailed, isTrue);
      await screen.subscription.cancel();

      final offline = _Server<RequestModel>();
      final later = await _open(cache, offline, now: () => _t1);
      expect(_ids(later.lists.single), ['a1', 'a2']);
      expect(later.status.showing, LocalListSource.savedCopy);
      expect(later.status.lastServerReadAt, _t0);
      await later.subscription.cancel();
    });

    test(
        'the next successful read on the same screen (a retry) removes it '
        'and advances the time', () async {
      var clock = _t0;
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server,
          now: () => clock, retryDelays: const [Duration(milliseconds: 10)]);
      server.reads.last.add([_request('a1'), _request('a2')]);
      await _saved(cache);

      clock = _t1;
      server.reads.last.addError(const SocketException('offline'));
      await _until(() => server.reads.length == 2); // the retry
      server.reads.last.add([_request('a1')]);
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.info.serverReadAt, _t1);
      expect(screen.status.showing, LocalListSource.server);
      expect(screen.status.lastReadFailed, isFalse);
      await screen.subscription.cancel();
    });

    test(
        'an added record is missing and an edited one is unchanged until the '
        'next successful read: the copy shows less, never invented data',
        () async {
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server);
      server.reads.last.add([_request('a1')]);
      await _saved(cache);
      server.reads.last.addError(const SocketException('offline'));
      final saved = await _saved(cache);
      expect(_ids(saved!.items), ['a1']);
      expect(saved.items.single.notes, 'note a1');
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('completeness', () {
    test('is unknown whatever the size, also for exactly 1000 rows', () async {
      final server = _Server<RequestModel>();
      final screen = await _open(cache, server);
      server.reads.last.add([for (var i = 0; i < 1000; i++) _request('r$i')]);
      final saved = await _saved(cache);
      expect(saved!.items, hasLength(1000));
      expect(saved.info.completeness, ListCompleteness.unknown);
      expect(screen.status.completeness, ListCompleteness.unknown);
      expect(ListCompleteness.values, [ListCompleteness.unknown]);
      await screen.subscription.cancel();
    });
  });

  // ---------------------------------------------------------------------
  group('all six lists, through their own screens\' services', () {
    test(
        'each records the time of its server list, and a failed refresh '
        'keeps both', () async {
      final requests = _Requests();
      final offers = _Offers();
      final owners = _Owners();
      final offices = _Offices();
      final brokers = _Brokers();
      final watchmen = _Watchmen();
      await _checkWiring<RequestModel>(
          'requests',
          const RequestsLocalCache(),
          requests.watchUserRequestsLocalFirst,
          requests.reads,
          [_request('r1')]);
      await _checkWiring<OfferModel>('offers', const OffersLocalCache(),
          offers.watchUserOffersLocalFirst, offers.reads, [
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
      await _checkWiring<OwnerModel>('owners', const OwnersLocalCache(),
          owners.watchUserOwnersLocalFirst, owners.reads, [
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
      await _checkWiring<OfficeModel>('offices', const OfficesLocalCache(),
          offices.watchUserOfficesLocalFirst, offices.reads, [
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
      await _checkWiring<BrokerModel>('brokers', const BrokersLocalCache(),
          brokers.watchUserBrokersLocalFirst, brokers.reads, [
        BrokerModel(
          id: 'b1',
          userId: _alice,
          name: '',
          countryCode: '+971',
          phoneNumber: '',
          notes: '',
        ),
      ]);
      await _checkWiring<WatchmenModel>('watchmen', const WatchmenLocalCache(),
          watchmen.watchUserWatchmenLocalFirst, watchmen.reads, [
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

/// Through a screen's real service (real clock): a server list is saved
/// with a time between before and after, under `<entity>_sync_v1`; a failed
/// refresh on a new screen keeps the list and its time.
Future<void> _checkWiring<T>(
  String entity,
  EncryptedAccountListCache<T> cache,
  Stream<List<T>> Function() watch,
  List<StreamController<List<T>>> reads,
  List<T> items,
) async {
  final before = DateTime.now().toUtc();
  final first = watch().listen((_) {}, onError: (_) {});
  await _until(() => reads.length == 1);
  reads.last.add(items);
  final saved = await _saved(cache);
  final after = DateTime.now().toUtc();
  final at = saved!.info.serverReadAt;
  expect(at, isNotNull, reason: entity);
  expect(!at!.isBefore(before) && !at.isAfter(after), isTrue, reason: entity);
  expect(saved.items, hasLength(items.length), reason: entity);
  expect(
      Hive.box<String>(cache.boxNameOf(_alice))
          .containsKey('${entity}_sync_v1'),
      isTrue,
      reason: entity);
  await first.cancel();

  final second = watch().listen((_) {}, onError: (_) {});
  await _until(() => reads.length == 2);
  reads.last.addError(const SocketException('offline'));
  final kept = await _saved(cache);
  expect(kept!.items, hasLength(items.length), reason: entity);
  expect(kept.info.serverReadAt, at, reason: entity);
  await second.cancel();
}

class _Requests extends RequestService {
  _Requests() : super(currentUserId: () => _alice);
  final List<StreamController<List<RequestModel>>> reads = [];
  @override
  Stream<List<RequestModel>> getUserRequests() => _next(reads);
}

class _Offers extends OfferService {
  _Offers() : super(currentUserId: () => _alice);
  final List<StreamController<List<OfferModel>>> reads = [];
  @override
  Stream<List<OfferModel>> getUserOffers() => _next(reads);
}

class _Owners extends OwnerService {
  _Owners() : super(currentUserId: () => _alice);
  final List<StreamController<List<OwnerModel>>> reads = [];
  @override
  Stream<List<OwnerModel>> getUserOwners() => _next(reads);
}

class _Offices extends OfficeService {
  _Offices() : super(currentUserId: () => _alice);
  final List<StreamController<List<OfficeModel>>> reads = [];
  @override
  Stream<List<OfficeModel>> getUserOffices() => _next(reads);
}

class _Brokers extends BrokerService {
  _Brokers() : super(currentUserId: () => _alice);
  final List<StreamController<List<BrokerModel>>> reads = [];
  @override
  Stream<List<BrokerModel>> getUserBrokers() => _next(reads);
}

class _Watchmen extends WatchmenService {
  _Watchmen() : super(currentUserId: () => _alice);
  final List<StreamController<List<WatchmenModel>>> reads = [];
  @override
  Stream<List<WatchmenModel>> getUserWatchmen() => _next(reads);
}

/// A new server read the test answers, kept in [reads].
Stream<List<T>> _next<T>(List<StreamController<List<T>>> reads) {
  final read = StreamController<List<T>>();
  reads.add(read);
  return read.stream;
}
