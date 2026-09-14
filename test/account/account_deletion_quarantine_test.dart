import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/app.dart' show resolveAuthRedirect;
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/account_deletion_state_store.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

UserModel _user(String uid) => UserModel(
      uid: uid,
      name: 'Account $uid',
      email: '$uid@example.test',
      createdAt: DateTime.utc(2026),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'test',
        isActive: false,
        features: const [],
      ),
      preferences: const {},
    );

/// A Supabase-shaped auth repository: the restored session is replayed to the
/// first subscriber in the same way `SupabaseAuthRepository` publishes it, and
/// Supabase Auth's existence answer is under the test's control.
class _Repository implements AuthRepository, AccountExistenceProbe {
  _Repository({UserModel? restored}) : _currentUser = restored;

  final StreamController<UserModel?> _identity =
      StreamController<UserModel?>.broadcast();
  UserModel? _currentUser;

  Completer<AccountExistence>? pendingProbe;
  AccountExistence answer = AccountExistence.deleted;
  bool probeThrows = false;
  bool signOutKeepsSession = false;
  int probes = 0;
  int signOutCalls = 0;

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _identity.stream;
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  void emit(UserModel? user) {
    _currentUser = user;
    _identity.add(user);
  }

  @override
  Future<AccountExistence> probeCurrentAccount() async {
    probes++;
    if (probeThrows) throw StateError('offline');
    final pending = pendingProbe;
    if (pending != null) return pending.future;
    return answer;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutKeepsSession) {
      throw const AuthFailure(code: AuthFailureCode.network, message: 'x');
    }
    emit(null);
  }

  Future<void> dispose() => _identity.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Users implements UserRepository {
  int profileReads = 0;
  int profileSubscriptions = 0;

  @override
  Future<UserModel?> getUserById(String uid) async {
    profileReads++;
    return null;
  }

  @override
  Stream<UserModel?> getUserStream(String uid) {
    profileSubscriptions++;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationRepository {
  int watchCalls = 0;

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    watchCalls++;
    return const Stream.empty();
  }

  @override
  Stream<int> watchUnreadCount(String userId) {
    watchCalls++;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({UserModel? restored, String? marker})
      : repository = _Repository(restored: restored) {
    AccountDeletionStateStore.resetForTesting(ownerUid: marker);
  }

  final _Repository repository;
  final users = _Users();
  final notifications = _Notifications();
  late final AuthViewModel auth;
  late final NotificationViewModel feed;

  /// Where the router would send a user sitting on /home, sampled at every
  /// AuthViewModel notification.
  final homeDestinations = <String?>[];
  final statuses = <AuthStatus>[];

  void start() {
    auth = AuthViewModel(
      authRepository: repository,
      userRepository: users,
      deletedAccountCleaner: DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
      ),
    );
    feed = NotificationViewModel(repository: notifications);
    homeDestinations.add(_redirect('/home'));
    auth.addListener(() {
      homeDestinations.add(_redirect('/home'));
      statuses.add(auth.status);
      // Exactly what main.dart's ChangeNotifierProxyProvider passes.
      feed.attachUser(
        auth.isPasswordRecoveryActive ? null : auth.currentUser?.uid,
      );
    });
  }

  String? _redirect(String path) => resolveAuthRedirect(
        auth.status,
        path,
        passwordRecoveryActive: auth.isPasswordRecoveryActive,
      );

  /// True if any notification could have left the router on /home.
  bool get homeWasReachable => homeDestinations.any((d) => d == null);

  Future<void> dispose() async {
    feed.dispose();
    auth.dispose();
    await repository.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountDeletionStateStore.resetForTesting();
  });

  group('Account deletion reconciliation quarantine', () {
    test(
        '1-2. a restored session for the marked account never resolves to '
        'Home, at any notification', () async {
      final h = _Harness(restored: _user(_alice), marker: _alice);
      addTearDown(h.dispose);
      h.repository.pendingProbe = Completer<AccountExistence>();
      h.start();
      await pumpEventQueue();

      expect(h.auth.isAccountDeletionReconciling, isTrue);
      expect(h.auth.status, AuthStatus.unknown);
      expect(h.auth.isAuthenticated, isFalse);
      expect(h.auth.currentUser, isNull);
      for (final path in ['/home', '/profile', '/search', '/favorites']) {
        expect(h._redirect(path), '/', reason: path);
      }

      h.repository.pendingProbe!.complete(AccountExistence.deleted);
      await pumpEventQueue();

      expect(h.homeDestinations, isNotEmpty);
      expect(h.homeWasReachable, isFalse);
      expect(h.statuses.contains(AuthStatus.authenticated), isFalse);
      expect(h.auth.status, AuthStatus.unauthenticated);
      expect(h._redirect('/home'), '/welcome');
    });

    test(
        '4-5. no notification feed, profile read or profile subscription '
        'starts during or after reconciliation', () async {
      final h = _Harness(restored: _user(_alice), marker: _alice);
      addTearDown(h.dispose);
      h.repository.pendingProbe = Completer<AccountExistence>();
      h.start();
      await pumpEventQueue();

      expect(h.notifications.watchCalls, 0);
      expect(h.users.profileReads, 0);
      expect(h.users.profileSubscriptions, 0);

      h.repository.pendingProbe!.complete(AccountExistence.exists);
      await pumpEventQueue();

      expect(h.notifications.watchCalls, 0);
      expect(h.users.profileReads, 0);
      expect(h.users.profileSubscriptions, 0);
    });

    test('6. a deleted account ends logged out with its local data cleared',
        () async {
      SharedPreferences.setMockInitialValues({
        'account_deletion_pending_uid': _alice,
        'cached_profile_snapshot_v1': json.encode({'uid': _alice}),
        'languageCode': 'ar',
        'themeMode': 'dark',
      });
      final h = _Harness(restored: _user(_alice), marker: _alice)
        ..repository.answer = AccountExistence.deleted;
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(h.repository.signOutCalls, 1);
      expect(h.repository.currentUserId, isNull);
      expect(h.auth.status, AuthStatus.unauthenticated);
      expect(h.auth.isAccountDeletionReconciling, isFalse);
      expect(AccountDeletionStateStore.ownerUid, isNull);
      expect(prefs.getString('account_deletion_pending_uid'), isNull);
      expect(prefs.getString('cached_profile_snapshot_v1'), isNull);
      expect(prefs.getString('languageCode'), 'ar');
      expect(prefs.getString('themeMode'), 'dark');
      expect(h.homeWasReachable, isFalse);
    });

    test(
        '7. an account that still exists is signed out, not resumed on Home, '
        'and can sign in again normally', () async {
      final h = _Harness(restored: _user(_alice), marker: _alice)
        ..repository.answer = AccountExistence.exists;
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();

      expect(h.repository.signOutCalls, 1);
      expect(h.auth.status, AuthStatus.unauthenticated);
      expect(h.homeWasReachable, isFalse);
      expect(AccountDeletionStateStore.ownerUid, isNull);

      // 10. The stale marker is resolved: signing in again is ordinary.
      h.repository.emit(_user(_alice));
      await pumpEventQueue();
      expect(h.auth.isAuthenticated, isTrue);
      expect(h.auth.isAccountDeletionReconciling, isFalse);
      expect(h._redirect('/home'), isNull);
      expect(h.repository.probes, 1);
    });

    test('8. a network failure or an unanswered probe can never open Home',
        () async {
      for (final setUpProbe in <void Function(_Repository)>[
        (r) => r.answer = AccountExistence.unknown,
        (r) => r.probeThrows = true,
        (r) => r.answer = AccountExistence.sessionInvalid,
      ]) {
        AccountDeletionStateStore.resetForTesting(ownerUid: _alice);
        final h = _Harness(restored: _user(_alice), marker: _alice);
        setUpProbe(h.repository);
        h.start();
        await pumpEventQueue();

        expect(h.homeWasReachable, isFalse);
        expect(h.statuses.contains(AuthStatus.authenticated), isFalse);
        expect(h.auth.status, AuthStatus.unauthenticated);
        expect(h.repository.currentUserId, isNull);
        await h.dispose();
      }
    });

    test('a session that cannot be removed keeps the marker for next time',
        () async {
      final h = _Harness(restored: _user(_alice), marker: _alice)
        ..repository.answer = AccountExistence.unknown
        ..repository.signOutKeepsSession = true;
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();

      expect(h.auth.isAuthenticated, isFalse);
      expect(h.homeWasReachable, isFalse);
      expect(AccountDeletionStateStore.ownerUid, _alice);
    });

    test('9. a marker for account A never quarantines a sign-in of account B',
        () async {
      final h = _Harness(marker: _alice);
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();

      h.repository.emit(_user(_bob));
      await pumpEventQueue();

      expect(h.auth.isAccountDeletionReconciling, isFalse);
      expect(h.auth.isAuthenticated, isTrue);
      expect(h._redirect('/home'), isNull);
      expect(h.repository.probes, 0);
      expect(h.repository.signOutCalls, 0);
      expect(AccountDeletionStateStore.ownerUid, _alice,
          reason: 'the marker still guards A only');
    });

    test(
        '11. a late reconciliation for A never signs out B, who signed in '
        'meanwhile', () async {
      final h = _Harness(restored: _user(_alice), marker: _alice);
      addTearDown(h.dispose);
      h.repository.pendingProbe = Completer<AccountExistence>();
      h.start();
      await pumpEventQueue();
      expect(h.auth.isAccountDeletionReconciling, isTrue);

      // A's session goes away and B signs in while the probe is still open.
      h.repository.emit(null);
      await pumpEventQueue();
      h.repository.emit(_user(_bob));
      await pumpEventQueue();
      expect(h.auth.isAuthenticated, isTrue);

      h.repository.pendingProbe!.complete(AccountExistence.deleted);
      await pumpEventQueue();

      expect(h.repository.signOutCalls, 0);
      expect(h.auth.isAuthenticated, isTrue);
      expect(h.auth.currentUserId, _bob);
      expect(h.auth.isAccountDeletionReconciling, isFalse);
    });

    test(
        'an already signed-in account is not re-quarantined by its own '
        'in-app deletion flow', () async {
      final h = _Harness(restored: _user(_alice));
      addTearDown(h.dispose);
      h.start();
      await pumpEventQueue();
      expect(h.auth.isAuthenticated, isTrue);

      // The delete flow writes the marker, then a token refresh re-publishes A.
      AccountDeletionStateStore.resetForTesting(ownerUid: _alice);
      h.repository.emit(_user(_alice));
      await pumpEventQueue();

      expect(h.auth.isAuthenticated, isTrue);
      expect(h.auth.isAccountDeletionReconciling, isFalse);
      expect(h.repository.probes, 0);
    });

    test('repeated identity events during reconciliation start one probe',
        () async {
      final h = _Harness(restored: _user(_alice), marker: _alice);
      addTearDown(h.dispose);
      h.repository.pendingProbe = Completer<AccountExistence>();
      h.start();
      await pumpEventQueue();

      h.repository.emit(_user(_alice));
      h.repository.emit(_user(_alice));
      await pumpEventQueue();
      expect(h.repository.probes, 1);
      expect(h.auth.status, AuthStatus.unknown);

      h.repository.pendingProbe!.complete(AccountExistence.deleted);
      await pumpEventQueue();
      expect(h.auth.status, AuthStatus.unauthenticated);
    });

    test('no timer or delay is used to hold the quarantine', () {
      const files = [
        'lib/src/viewmodels/Signup-Login/auth_viewmodel.dart',
        'lib/src/services/account_deletion_state_store.dart',
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(source.contains('Future.delayed'), isFalse, reason: path);
        expect(RegExp(r'\bTimer\(').hasMatch(source), isFalse, reason: path);
      }
    });
  });

  testWidgets(
      '3. Home is never built while a marked session is reconciled, and the '
      'app lands on the logged-out entry', (tester) async {
    final h = _Harness(restored: _user(_alice), marker: _alice);
    h.repository.pendingProbe = Completer<AccountExistence>();
    h.start();
    var homeBuilds = 0;

    final router = GoRouter(
      initialLocation: '/',
      refreshListenable: h.auth,
      redirect: (context, state) => h._redirect(state.uri.path),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('BOOTSTRAP')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) {
            homeBuilds++;
            return const Scaffold(body: Text('HOME_SCREEN'));
          },
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, __) => const Scaffold(body: Text('WELCOME_SCREEN')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump();

    expect(find.text('BOOTSTRAP'), findsOneWidget);
    expect(homeBuilds, 0);
    expect(h.notifications.watchCalls, 0);

    h.repository.pendingProbe!.complete(AccountExistence.deleted);
    await tester.pumpAndSettle();

    expect(find.text('WELCOME_SCREEN'), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsNothing);
    expect(homeBuilds, 0);
    expect(h.notifications.watchCalls, 0);
    expect(h.users.profileSubscriptions, 0);

    router.dispose();
    await h.dispose();
  });
}
