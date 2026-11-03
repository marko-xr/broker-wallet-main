// P3.1c: Home counts from a session the database no longer accepts.
//
// The database's session gate filters rows instead of failing, so a replaced
// (superseded) session counts 0 in every table, with no error (P3.0, §7Z).
// A zero that would replace a count shown now is trusted only once the
// existing session check confirms the session that made the read; every
// answer counts only for that account and session.
//
// The real HomeViewModel and CountCacheService, with a count reader and a
// session check the test answers; nothing reaches the network.
import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

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

/// The session check: counted, answered by the test (or at once).
class _Check {
  int calls = 0;
  final List<String?> sessions = [];
  bool? always;
  Object? throws;
  Completer<bool>? _pending;

  Future<bool>? call(String? session) {
    calls++;
    sessions.add(session);
    // A plain stack trace: the view model's existing catch prints it with
    // debugPrintStack, which asserts on test-zone (stack_trace) frames.
    if (throws != null) return Future<bool>.error(throws!, StackTrace.empty);
    if (always != null) return Future<bool>.value(always);
    return (_pending = Completer<bool>()).future;
  }

  void answer(bool current) => _pending!.complete(current);
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
  late _Check check;
  late StreamController<AuthState> auth;
  late CountCacheService cache;
  late String? session;

  Future<void> start(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    cache = CountCacheService.forTesting();
    await cache.initialize();
    repo = _Repo();
    reads = _Reads();
    check = _Check();
    session = 's1';
    auth = StreamController<AuthState>.broadcast();
  }

  /// Alice's cached counts are 4 in every tile.
  Future<void> startWithAliceAt4() =>
      start({CountCacheService.countsKeyFor(_alice): json.encode(_counts(4))});

  HomeViewModel openHome() {
    final vm = HomeViewModel(
      authRepository: repo,
      countCache: cache,
      readCounts: reads.call,
      authStateChanges: auth.stream,
      confirmSession: check.call,
      sessionOf: () => session,
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

  // ---------------------------------------------------------------------
  group('zeros that replace nothing, or a confirmed session', () {
    test(
        'a legitimately empty account (zeros shown, zeros read) is shown as '
        'zero with no session check', () async {
      await start({});
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete(_counts(0));
      }
      await _settle();
      expect(_allShown(vm), _counts(0));
      expect(check.calls, 0);
    });

    test(
        'zeros that replace shown counts are shown and cached once the session '
        'is confirmed', () async {
      await startWithAliceAt4();
      check.always = true;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      reads.pending.last.complete(_counts(0));
      await _settle();
      expect(_allShown(vm), _counts(0));
      expect(await storedFor(_alice), _counts(0));
      expect(check.calls, greaterThanOrEqualTo(1));
      expect(check.sessions.toSet(), {'s1'});
    });

    test('counts that drop to no zero are never checked', () async {
      await startWithAliceAt4();
      check.always = false;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete(_counts(2));
      }
      await _settle();
      expect(_allShown(vm), _counts(2));
      expect(check.calls, 0);
    });

    test(
        'a mixed answer whose zeros were already zero is taken without a '
        'check', () async {
      await start({
        CountCacheService.countsKeyFor(_alice):
            json.encode({..._counts(4), 'offers': 0}),
      });
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete({..._counts(6), 'offers': 0});
      }
      await _settle();
      expect(_allShown(vm), {..._counts(6), 'offers': 0});
      expect(check.calls, 0);
    });
  });

  // ---------------------------------------------------------------------
  group('zeros the session check does not confirm', () {
    test(
        'a superseded session\'s all-zero answer keeps the shown and cached '
        'counts', () async {
      await startWithAliceAt4();
      check.always = false;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete(_counts(0));
      }
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(await storedFor(_alice), _counts(4));
      expect(check.calls, greaterThanOrEqualTo(1));
    });

    test(
        'a mixed answer that turns one shown count into 0 is checked and, '
        'unconfirmed, applied not at all', () async {
      await startWithAliceAt4();
      check.always = false;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete({..._counts(5), 'requested': 0});
      }
      await _settle();
      expect(_allShown(vm), _counts(4), reason: 'nothing of it, not partly');
      expect(await storedFor(_alice), _counts(4));
    });

    test('a network failure of the check keeps the shown and cached counts',
        () async {
      await startWithAliceAt4();
      check.throws = Exception('offline');
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.complete(_counts(0));
      }
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(await storedFor(_alice), _counts(4));
    });

    test(
        'a failed count read (network or authorization) keeps what is shown, '
        'as before, with no check', () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      for (final read in reads.pending) {
        read.completeError(
            const AuthException('JWT expired'), StackTrace.empty);
      }
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(check.calls, 0);
    });
  });

  // ---------------------------------------------------------------------
  group('the account and session that made the read', () {
    test(
        'an old-session answer after sign-out and sign-in to the same '
        'account is dropped', () async {
      await startWithAliceAt4();
      check.always = true;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      final old = reads.pending.length;
      await signOut();
      session = 's3';
      await signIn(_alice);
      for (final read in reads.pending.take(old)) {
        read.complete(_counts(9)); // answers to reads made under s1
      }
      await _settle();
      expect(_allShown(vm), isNot(_counts(9)));
      expect(await storedFor(_alice), isNot(_counts(9)));
    });

    test(
        'a session change with no sign-out event seen: the s1 answer is '
        'dropped', () async {
      await startWithAliceAt4();
      check.always = true;
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      session = 's3'; // e.g. a missed auth event
      for (final read in reads.pending) {
        read.complete(_counts(9));
      }
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(await storedFor(_alice), _counts(4));
    });

    test('the session changes while the check is pending: dropped', () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      reads.pending.last.complete(_counts(0));
      await pumpEventQueue();
      expect(check.sessions, ['s1']);
      session = 's3';
      check.answer(true);
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(await storedFor(_alice), _counts(4));
    });

    test(
        'the session changes during the 100 ms debounce of an answer that '
        'needed no check: dropped', () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      reads.pending.last.complete(_counts(9));
      await pumpEventQueue(); // scheduled, not yet shown
      session = 's3';
      await _settle();
      expect(_allShown(vm), _counts(4));
      expect(await storedFor(_alice), _counts(4));
    });

    test(
        'a late check for the old session does not cancel the newer '
        'session\'s update', () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      reads.pending.last.complete(_counts(0)); // s1: waits for its check
      await pumpEventQueue();
      session = 's3';
      unawaited(vm.refreshCounts()); // a read under s3
      await pumpEventQueue();
      reads.pending.last.complete(_counts(7)); // no zero: no check
      await pumpEventQueue();
      check.answer(true); // the s1 check answers within the debounce
      await _settle();
      expect(_allShown(vm), _counts(7));
      expect(await storedFor(_alice), _counts(7));
    });

    test(
        'another account signs in while a read or a check is pending: '
        'nothing of Alice\'s answer reaches Bob or Alice\'s cache', () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = openHome();
      await signIn(_alice);
      reads.pending.last.complete(_counts(0));
      await pumpEventQueue();
      session = 'sB';
      await signIn(_bob);
      check.answer(true);
      await _settle();
      expect(await storedFor(_alice), _counts(4));
      expect(_allShown(vm), _counts(0), reason: 'Bob has no cached counts');
      expect(await storedFor(_bob), isEmpty);
    });

    test('a Home screen closed while the check is pending changes nothing',
        () async {
      await startWithAliceAt4();
      repo.uid = _alice;
      final vm = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: reads.call,
        authStateChanges: auth.stream,
        confirmSession: check.call,
        sessionOf: () => session,
      );
      await signIn(_alice);
      reads.pending.last.complete(_counts(0));
      await pumpEventQueue();
      vm.dispose();
      check.answer(true);
      await _settle();
      expect(await storedFor(_alice), _counts(4));
    });
  });

  // ---------------------------------------------------------------------
  group('session checks are made only when needed', () {
    test(
        'one check per answer that would zero a shown count, none otherwise; '
        'the default check is the shared session check', () async {
      await startWithAliceAt4();
      var defaultChecks = 0;
      ListSessionCheck.debugOverride = (s) {
        defaultChecks++;
        return Future<bool>.value(true);
      };
      addTearDown(() => ListSessionCheck.debugOverride = null);
      repo.uid = _alice;
      final vm = HomeViewModel(
        authRepository: repo,
        countCache: cache,
        readCounts: reads.call,
        authStateChanges: auth.stream,
        sessionOf: () => session,
      );
      addTearDown(vm.dispose);
      await signIn(_alice);
      final answered = reads.pending.length;
      for (final read in reads.pending) {
        read.complete(_counts(4)); // unchanged: no zero replaces anything
      }
      await _settle();
      expect(defaultChecks, 0);

      unawaited(vm.refreshCounts());
      await pumpEventQueue();
      expect(reads.pending.length, answered + 1);
      reads.pending.last.complete(_counts(0));
      await _settle();
      expect(defaultChecks, 1);
      expect(_allShown(vm), _counts(0));
    });
  });
}
