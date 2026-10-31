// R-02: Home counts belong to the account they were read for.
//
// These tests drive the real HomeViewModel and CountCacheService with a fake
// count reader and a fake Supabase auth stream; nothing reaches the network.
import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

/// The canonical identity: the Supabase user id of the current session.
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

/// Each read waits until the test answers it.
class _Reads {
  final List<Completer<Map<String, int>>> pending = [];
  final List<Map<String, int>> fallbacks = [];

  Future<Map<String, int>> call(Map<String, int> fallback) {
    final read = Completer<Map<String, int>>();
    pending.add(read);
    fallbacks.add(Map<String, int>.from(fallback));
    return read.future;
  }
}

Map<String, int> _counts(int n) => {
      for (final type in CountCacheService.countTypes) type: n,
    };

AuthState _signedIn(String id) => AuthState(
      AuthChangeEvent.signedIn,
      Session(
        accessToken: 'test-token',
        tokenType: 'bearer',
        user: User(
          id: id,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );

const _signedOut = AuthState(AuthChangeEvent.signedOut, null);

int _shown(HomeViewModel vm, String key) =>
    vm.items.firstWhere((item) => item.labelKey == key).count ?? -1;

Map<String, int> _allShown(HomeViewModel vm) => {
      for (final type in CountCacheService.countTypes) type: _shown(vm, type),
    };

/// Lets a delivered read pass the view model's 100 ms debounce.
Future<void> _settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Repo repo;
  late _Reads reads;
  late StreamController<AuthState> auth;
  late CountCacheService cache;

  Future<void> start(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    cache = CountCacheService.forTesting();
    await cache.initialize();
    repo = _Repo();
    reads = _Reads();
    auth = StreamController<AuthState>.broadcast();
  }

  HomeViewModel openHome() {
    final vm = HomeViewModel(
      authRepository: repo,
      countCache: cache,
      readCounts: reads.call,
      authStateChanges: auth.stream,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Future<void> signIn(String id) async {
    repo.uid = id;
    auth.add(_signedIn(id));
    await pumpEventQueue();
  }

  Future<void> signOut() async {
    repo.uid = null;
    auth.add(_signedOut);
    await pumpEventQueue();
  }

  Future<Map<String, Object?>> storedFor(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(CountCacheService.countsKeyFor(id));
    return raw == null ? {} : json.decode(raw) as Map<String, Object?>;
  }

  tearDown(() => auth.close());

  group('two accounts on one device', () {
    test('a cold start shows only the signed-in account\'s own cached counts',
        () async {
      await start({
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(7)),
      });

      repo.uid = _bob;
      final bobHome = openHome();
      expect(_allShown(bobHome), _counts(0),
          reason: 'Bob must never see the counts cached for Alice');

      repo.uid = _alice;
      final aliceHome = openHome();
      expect(_allShown(aliceHome), _counts(7),
          reason: 'Alice still gets her own counts at once');
    });

    test('switching account shows the new account\'s counts, never the old',
        () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      reads.pending.single.complete(_counts(5));
      await _settle();
      expect(_shown(vm, 'offers'), 5);

      await signOut();
      await signIn(_bob);
      expect(_allShown(vm), _counts(0),
          reason: 'Bob has nothing cached, so Home starts from 0');
      expect(reads.fallbacks.last, _counts(0),
          reason: 'Bob\'s read must not fall back to Alice\'s counts');

      reads.pending.last.complete(_counts(1));
      await _settle();
      expect(_shown(vm, 'offers'), 1);
      expect(await storedFor(_alice), _counts(5));
      expect(await storedFor(_bob), _counts(1));
    });

    test('a direct switch with no sign-out in between also isolates counts',
        () async {
      await start({
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(4)),
      });
      repo.uid = _alice;
      final vm = openHome();
      expect(_shown(vm, 'offers'), 4);

      await signIn(_bob);
      expect(_allShown(vm), _counts(0));
    });
  });

  group('logout', () {
    test(
        'signing out shows 0 and keeps the account\'s own cache for its return',
        () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      reads.pending.single.complete(_counts(5));
      await _settle();

      await signOut();
      expect(_allShown(vm), _counts(0));
      expect(await storedFor(_alice), _counts(5));

      await signIn(_alice);
      expect(_shown(vm, 'offers'), 5,
          reason: 'Alice sees her own cached counts again at once');
    });
  });

  group('offline reopening', () {
    test('a failed read keeps the account\'s own cached counts', () async {
      await start({
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(4)),
      });
      repo.uid = _alice;
      final vm = openHome();
      reads.pending.single
          .completeError(Exception('offline'), StackTrace.empty);
      await _settle();
      expect(_allShown(vm), _counts(4));
    });

    test('an account with nothing cached stays at 0 when the read fails',
        () async {
      await start({
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(4)),
      });
      repo.uid = _bob;
      final vm = openHome();
      expect(reads.fallbacks.single, _counts(0));
      reads.pending.single
          .completeError(Exception('offline'), StackTrace.empty);
      await _settle();
      expect(_allShown(vm), _counts(0));
    });
  });

  group('late results of an old session', () {
    test('a read started for Alice cannot change what Bob sees', () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      final aliceRead = reads.pending.single;

      await signOut();
      await signIn(_bob);
      aliceRead.complete(_counts(9));
      await _settle();

      expect(_allShown(vm), _counts(0));
      expect(await storedFor(_bob), isEmpty,
          reason: 'Alice\'s counts are never stored as Bob\'s');
      expect(await storedFor(_alice), isEmpty,
          reason: 'a dropped read is not stored at all');

      reads.pending.last.complete(_counts(2));
      await _settle();
      expect(_shown(vm, 'offers'), 2);
    });

    test('an update still waiting to be shown is dropped on a switch',
        () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      reads.pending.single.complete(_counts(9));
      await pumpEventQueue(); // delivered, but inside the 100 ms debounce

      await signIn(_bob);
      await _settle();
      expect(_allShown(vm), _counts(0));
      expect(await storedFor(_bob), isEmpty);
    });

    test('a read from before a sign-out is dropped even for the same account',
        () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      final oldRead = reads.pending.single;

      await signOut();
      await signIn(_alice);
      oldRead.complete(_counts(9));
      await _settle();
      expect(_shown(vm, 'offers'), 0);

      reads.pending.last.complete(_counts(3));
      await _settle();
      expect(_shown(vm, 'offers'), 3);
    });

    test('a read that ends after Home is closed changes nothing', () async {
      await start({});
      repo.uid = _alice;
      final vm = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: reads.call,
        authStateChanges: auth.stream,
      );
      vm.dispose();
      reads.pending.single.complete(_counts(6));
      await _settle();
      expect(await storedFor(_alice), isEmpty);
    });
  });

  group('the old shared cache', () {
    test('is never adopted by an account and is left on disk', () async {
      await start({
        CountCacheService.legacyCountsKey: json.encode(_counts(7)),
        CountCacheService.legacyUpdatedKey: 1,
      });
      repo.uid = _alice;
      final vm = openHome();
      expect(_allShown(vm), _counts(0));
      expect(reads.fallbacks.single, _counts(0));

      reads.pending.single.complete(_counts(2));
      await _settle();
      expect(_shown(vm, 'offers'), 2);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CountCacheService.legacyCountsKey),
          json.encode(_counts(7)),
          reason: 'legacy data is not deleted automatically');
      expect(await storedFor(_alice), _counts(2));
    });

    test('clearLegacyCache removes only the old shared cache', () async {
      await start({
        CountCacheService.legacyCountsKey: json.encode(_counts(7)),
        CountCacheService.legacyUpdatedKey: 1,
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(3)),
        'languageCode': 'ar',
      });

      await cache.clearLegacyCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(),
          {CountCacheService.countsKeyFor(_alice), 'languageCode'});
      expect(cache.getAllCachedCounts(_alice), _counts(3));
    });
  });

  group('account deletion', () {
    test('clearAccount removes only that account\'s counts', () async {
      await start({
        CountCacheService.legacyCountsKey: json.encode(_counts(7)),
        CountCacheService.countsKeyFor(_alice): json.encode(_counts(3)),
        CountCacheService.countsKeyFor(_bob): json.encode(_counts(4)),
        'languageCode': 'ar',
      });
      await cache.updateCachedCounts(_alice, _counts(5));
      expect(cache.getAllCachedCounts(_alice), _counts(5));

      await cache.clearAccount(_alice);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {
        CountCacheService.legacyCountsKey,
        CountCacheService.countsKeyFor(_bob),
        'languageCode',
      });
      expect(cache.getAllCachedCounts(_alice), _counts(0),
          reason: 'nothing of the deleted account stays, in memory either');
      expect(cache.getAllCachedCounts(_bob), _counts(4));
    });
  });

  group('the cache itself', () {
    test('no account means 0, and a damaged entry counts as nothing', () async {
      await start({
        CountCacheService.countsKeyFor(_alice): 'not json',
      });
      expect(cache.getAllCachedCounts(null), _counts(0));
      expect(cache.getAllCachedCounts(''), _counts(0));
      expect(cache.getAllCachedCounts(_alice), _counts(0));
    });
  });
}
