// Phase 2 / P2.1: the Requests list reads this account's saved copy first.
//
// Real Hive in a temporary directory (never the app's boxes), the real
// RequestedListViewModel and RequestService, and a fake server stream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport;
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

RequestModel _request(
  String id,
  String owner, {
  PropertyStatus status = PropertyStatus.active,
  List<String> areas = const ['Marina'],
  String? propertyType = 'residential',
}) =>
    RequestModel(
      id: id,
      userId: owner,
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: areas,
      location: 'Tower 1',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '1000',
      maxPrice: '2000',
      squareFootage: '900',
      notes: 'note $id',
      propertyType: propertyType,
      specificPropertyType: 'apartment',
      rooms: 2,
      bathrooms: 1,
      status: status,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );

List<Object?> _fields(RequestModel r) => [
      r.id,
      r.userId,
      r.requestType,
      r.selectedCity,
      r.selectedAreas,
      r.location,
      r.phoneNumber,
      r.countryCode,
      r.minPrice,
      r.maxPrice,
      r.squareFootage,
      r.notes,
      r.propertyType,
      r.specificPropertyType,
      r.rooms,
      r.bathrooms,
      r.status,
      r.createdAt.toUtc(),
      r.updatedAt.toUtc(),
    ];

List<String?> _ids(List<RequestModel> requests) =>
    requests.map((r) => r.id).toList();

/// A key store that cannot be reached (locked Keystore, platform error).
class _UnavailableKeys implements RequestsCacheKeyStore {
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

/// The server side: one stream per screen subscription, answered by the test.
class _Requests extends RequestService {
  _Requests({required super.currentUserId, super.localCache});

  final List<StreamController<List<RequestModel>>> reads = [];

  StreamController<List<RequestModel>> get server => reads.single;

  @override
  Stream<List<RequestModel>> getUserRequests() {
    final read = StreamController<List<RequestModel>>();
    reads.add(read);
    return read.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const cache = RequestsLocalCache();
  String? signedIn;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('requests_local_first_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    signedIn = _alice;
  });

  tearDown(() async {
    for (final uid in [_alice, _bob]) {
      // A box that failed to open is closed by Hive without waiting; on
      // Windows its file stays locked for a moment.
      for (var attempt = 0;; attempt++) {
        try {
          await Hive.deleteBoxFromDisk(RequestsLocalCache.boxNameForUid(uid));
          break;
        } on FileSystemException {
          if (attempt == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    }
  });

  File boxFile(String uid) => File('${tempDir.path}${Platform.pathSeparator}'
      '${RequestsLocalCache.boxNameForUid(uid)}.hive');

  Future<void> closeBox(String uid) async {
    final name = RequestsLocalCache.boxNameForUid(uid);
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
  }

  Future<String?> secureKey(String uid) => const FlutterSecureStorage()
      .read(key: SecureRequestsCacheKeyStore.storageKeyFor(uid));

  RequestedListViewModel openRequests(_Requests service) {
    final vm = RequestedListViewModel(requestService: service);
    addTearDown(vm.dispose);
    return vm;
  }

  _Requests service() => _Requests(currentUserId: () => signedIn);

  /// The saved copy is read from disk first; wait until the screen has gone
  /// on to ask the server.
  Future<void> untilServerRead(_Requests requests) async {
    for (var i = 0; i < 400 && requests.reads.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(requests.reads, isNotEmpty, reason: 'the server is still asked');
    await pumpEventQueue();
  }

  group('offline reading', () {
    test('with the network down, the account\'s saved Requests stay shown',
        () async {
      await cache
          .write(_alice, [_request('a1', _alice), _request('a2', _alice)]);
      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(_ids(vm.requests), ['a1', 'a2'],
          reason: 'the saved copy shows before the server answers');

      requests.server.addError(const SocketException('offline'));
      await requests.server.close();
      await pumpEventQueue();

      expect(vm.hasLoadError, isFalse);
      expect(_ids(vm.requests), ['a1', 'a2']);
      expect(_ids((await cache.read(_alice))!), ['a1', 'a2'],
          reason: 'a failed read never discards the saved copy');
    });

    test('with nothing saved, a network failure still shows the load error',
        () async {
      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(vm.isInitialLoading, isTrue);

      requests.server.addError(const SocketException('offline'));
      await requests.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
    });

    test('the server list replaces the saved copy and is saved for next time',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);

      requests.server.add([_request('a1', _alice), _request('a3', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.requests), ['a1', 'a3']);
      expect(_ids((await cache.read(_alice))!), ['a1', 'a3']);

      requests.server.add(const []);
      await pumpEventQueue();
      expect(vm.requests, isEmpty);
      expect(await cache.read(_alice), isEmpty,
          reason: 'requests removed on the server leave the saved copy too');
    });
  });

  group('account isolation', () {
    test('one account never sees another account\'s saved Requests', () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      signedIn = _bob;
      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(vm.isInitialLoading, isTrue);
      expect(vm.requests, isEmpty);

      requests.server.addError(const SocketException('offline'));
      await requests.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue);
      expect(vm.requests, isEmpty);
    });

    test('rows owned by another account are never saved', () async {
      await cache.write(_alice, [_request('a1', _alice), _request('b1', _bob)]);
      // The stored list itself (decrypted; the box is open with its key),
      // not only what a read lets through.
      final stored = Hive.box<String>(RequestsLocalCache.boxNameForUid(_alice))
          .get('requests_v1')!;
      expect(stored.contains(_bob), isFalse);
      expect(stored.contains('b1'), isFalse);
      expect(_ids((await cache.read(_alice))!), ['a1']);
    });

    test('rows owned by another account are never read back', () async {
      // Rows written by the cache itself: Alice's, then Bob's planted in
      // Alice's box as if the stored list had been mixed up.
      await cache.write(_alice, [_request('a1', _alice)]);
      await cache.write(_bob, [_request('b1', _bob)]);
      final aliceBox =
          await Hive.openBox<String>(RequestsLocalCache.boxNameForUid(_alice));
      final bobBox =
          await Hive.openBox<String>(RequestsLocalCache.boxNameForUid(_bob));
      final mixed = [
        ...json.decode(aliceBox.get('requests_v1')!) as List,
        ...json.decode(bobBox.get('requests_v1')!) as List,
      ];
      await aliceBox.put('requests_v1', json.encode(mixed));
      expect(_ids((await cache.read(_alice))!), ['a1']);
    });

    test('nothing is saved once the account has changed', () async {
      final requests = service();
      openRequests(requests);
      await untilServerRead(requests);

      signedIn = _bob;
      requests.server.add([_request('a9', _alice)]);
      await pumpEventQueue();

      expect(await cache.read(_alice), isNull);
      expect(await cache.read(_bob), isNull);
    });

    test('a saved copy is not shown if the account changed while reading it',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      var calls = 0;
      final requests = _Requests(
        currentUserId: () => calls++ == 0 ? _alice : _bob,
      );
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(vm.requests, isEmpty);
      expect(vm.isInitialLoading, isTrue);
    });

    test('with no signed-in account nothing is read or saved', () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      signedIn = null;
      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(vm.isInitialLoading, isTrue);

      requests.server.add([_request('a2', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.requests), ['a2']);
      expect(_ids((await cache.read(_alice))!), ['a1']);
    });
  });

  group('the saved copy', () {
    test('keeps every field exactly', () async {
      final original = _request(
        'a1',
        _alice,
        status: PropertyStatus.fulfilled,
        areas: const ['JLT', 'Marina', 'الخليج التجاري'],
        propertyType: null,
      ).copyWith(notes: 'ملاحظة\nسطر ثان');
      expect(original.propertyType, isNull);
      await cache.write(_alice, [original]);
      final read = (await cache.read(_alice))!.single;
      expect(_fields(read), _fields(original));
    });

    test('a damaged entry counts as nothing saved', () async {
      await cache.write(_alice, [_request('a0', _alice)]);
      // The box is open and encrypted; store a list that does not decode.
      await Hive.box<String>(RequestsLocalCache.boxNameForUid(_alice))
          .put('requests_v1', '{not json');
      expect(await cache.read(_alice), isNull);

      final requests = service();
      final vm = openRequests(requests);
      await untilServerRead(requests);
      expect(vm.isInitialLoading, isTrue);
      requests.server.add([_request('a1', _alice)]);
      await pumpEventQueue();
      expect(_ids(vm.requests), ['a1']);
    });

    test('closing the screen while the copy is read starts no server read',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      final requests = service();
      final subscription =
          requests.watchUserRequestsLocalFirst().listen((_) {});
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests.reads, isEmpty);
    });
  });

  group('account deletion', () {
    test('removes the deleted account\'s saved Requests and no one else\'s',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await cache.write(_bob, [_request('b1', _bob)]);

      await DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
        forgetOfferMedia: ({ownerId}) async =>
            const OfferMediaCleanupReport.empty(),
        purgeOfferMediaUploads: (_) async => 0,
      ).clear(deletedUid: _alice, wasSignedInAccount: false);

      expect(
        await Hive.boxExists(RequestsLocalCache.boxNameForUid(_alice)),
        isFalse,
      );
      expect(await secureKey(_alice), isNull,
          reason: 'the deleted account\'s key goes with its box');
      expect(await secureKey(_bob), isNotNull);
      expect(_ids((await cache.read(_bob))!), ['b1']);
    });
  });

  group('encryption and keys', () {
    test(
        'the saved copy is encrypted on disk and its key is only in secure '
        'storage', () async {
      await cache.write(_alice, [
        _request('a1', _alice).copyWith(
          phoneNumber: '509876543',
          notes: 'SECRET-NOTE-123',
        ),
      ]);
      await closeBox(_alice);

      final onDisk = latin1.decode(boxFile(_alice).readAsBytesSync());
      for (final secret in ['509876543', 'SECRET-NOTE-123', 'Marina', _alice]) {
        expect(onDisk.contains(secret), isFalse, reason: '"$secret" in clear');
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty,
          reason: 'no key or data in SharedPreferences');
      final key = await secureKey(_alice);
      expect(base64.decode(key!), hasLength(32));

      // After a restart (box closed) the stored key opens it again.
      final read = (await cache.read(_alice))!.single;
      expect(read.notes, 'SECRET-NOTE-123');
    });

    test('each account has its own key', () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await cache.write(_bob, [_request('b1', _bob)]);
      expect(await secureKey(_alice), isNot(await secureKey(_bob)));
    });

    test(
        'with key storage unavailable nothing is read or written, and '
        'nothing is stored unencrypted', () async {
      final broken = RequestsLocalCache(keyStore: _UnavailableKeys());
      await broken.write(_alice, [_request('a1', _alice)]);
      expect(
        await Hive.boxExists(RequestsLocalCache.boxNameForUid(_alice)),
        isFalse,
      );
      expect(await broken.read(_alice), isNull);

      final requests =
          _Requests(currentUserId: () => signedIn, localCache: broken);
      final vm = openRequests(requests);
      await untilServerRead(requests);
      requests.server.addError(const SocketException('offline'));
      await requests.server.close();
      await pumpEventQueue();
      expect(vm.hasLoadError, isTrue, reason: 'as before the cache existed');
    });

    test(
        'a box whose key went missing is never read, overwritten or given a '
        'new key', () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage()
          .delete(key: SecureRequestsCacheKeyStore.storageKeyFor(_alice));
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_request('a2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), isNull);
    });

    test('a box under another key cannot be read and is left unchanged',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await closeBox(_alice);
      final otherKey = base64.encode(List<int>.generate(32, (i) => i));
      await const FlutterSecureStorage().write(
        key: SecureRequestsCacheKeyStore.storageKeyFor(_alice),
        value: otherKey,
      );
      final before = boxFile(_alice).readAsBytesSync();

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_request('a2', _alice)]);

      expect(boxFile(_alice).readAsBytesSync(), before);
      expect(await secureKey(_alice), otherKey, reason: 'never replaced');
    });

    test('a corrupted box counts as nothing saved and is left unchanged',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await closeBox(_alice);
      final bytes = boxFile(_alice).readAsBytesSync();
      for (var i = 8; i < bytes.length; i += 3) {
        bytes[i] = bytes[i] ^ 0x5a;
      }
      boxFile(_alice).writeAsBytesSync(bytes);

      expect(await cache.read(_alice), isNull);
      await cache.write(_alice, [_request('a2', _alice)]);
      expect(boxFile(_alice).readAsBytesSync(), bytes);
    });

    test('two first saves at once create one key and stay readable', () async {
      await Future.wait([
        cache.write(_alice, [_request('a1', _alice)]),
        cache.write(_alice, [_request('a2', _alice)]),
      ]);
      expect(_ids((await cache.read(_alice))!), ['a2']);
      await closeBox(_alice);
      expect(_ids((await cache.read(_alice))!), ['a2'],
          reason: 'still readable with the one stored key after a restart');
    });

    test('after logout the copy is shown only when the same account is back',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);

      signedIn = null;
      final signedOut = service();
      final first = openRequests(signedOut);
      await untilServerRead(signedOut);
      expect(first.requests, isEmpty);

      signedIn = _alice;
      final back = service();
      final second = openRequests(back);
      await untilServerRead(back);
      expect(_ids(second.requests), ['a1']);
    });
  });

  group('guarded open', () {
    /// Runs [body] in a zone of its own and returns the unhandled errors
    /// that reached that zone — what the app's error handling would see.
    Future<List<Object>> reachingTheApp(Future<void> Function() body) {
      final reached = <Object>[];
      final done = Completer<List<Object>>();
      runZonedGuarded(() async {
        await body();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        done.complete(reached);
      }, (error, _) => reached.add(error));
      return done.future;
    }

    Future<Object?> failureOf(Future<Object?> Function() open) async {
      try {
        await EncryptedAccountListCache.guardedOpen(open);
        return null;
      } catch (error) {
        return error;
      }
    }

    test('the duplicate arriving after the failure is dropped', () async {
      final failure = StateError('open failed');
      final reached = await reachingTheApp(() async {
        final got = await failureOf(() async {
          // Hive's second, unlistened report of the same failure, later.
          unawaited(Future<void>.delayed(
              const Duration(milliseconds: 10), () => throw failure));
          throw failure;
        });
        expect(got, same(failure));
      });
      expect(reached, isEmpty);
    });

    test('the duplicate arriving before the failure is dropped', () async {
      final failure = StateError('open failed');
      final reached = await reachingTheApp(() async {
        final got = await failureOf(() async {
          scheduleMicrotask(() => throw failure);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw failure;
        });
        expect(got, same(failure));
      });
      expect(reached, isEmpty);
    });

    test('an unrelated error during a failed open still reaches the app',
        () async {
      final failure = StateError('open failed');
      final unrelated = ArgumentError('something else');
      final reached = await reachingTheApp(() async {
        await failureOf(() async {
          scheduleMicrotask(() => throw unrelated);
          scheduleMicrotask(() => throw failure);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw failure;
        });
      });
      expect(reached, [same(unrelated)]);
    });

    test('an error after a successful open still reaches the app', () async {
      final later = StateError('later failure');
      final reached = await reachingTheApp(() async {
        final value = await EncryptedAccountListCache.guardedOpen(() async {
          unawaited(Future<void>.delayed(
              const Duration(milliseconds: 10), () => throw later));
          return 42;
        });
        expect(value, 42);
      });
      expect(reached, [same(later)]);
    });

    test('only one duplicate is ever dropped', () async {
      final failure = StateError('open failed');
      final reached = await reachingTheApp(() async {
        await failureOf(() async {
          unawaited(Future<void>.delayed(
              const Duration(milliseconds: 5), () => throw failure));
          unawaited(Future<void>.delayed(
              const Duration(milliseconds: 10), () => throw failure));
          throw failure;
        });
      });
      expect(reached, [same(failure)]);
    });

    test('a real wrong-key open fails closed with nothing reaching the app',
        () async {
      await cache.write(_alice, [_request('a1', _alice)]);
      await closeBox(_alice);
      await const FlutterSecureStorage().write(
        key: SecureRequestsCacheKeyStore.storageKeyFor(_alice),
        value: base64.encode(List<int>.generate(32, (i) => 255 - i)),
      );
      final reached = await reachingTheApp(() async {
        expect(await cache.read(_alice), isNull);
      });
      expect(reached, isEmpty);
    });
  });
}
