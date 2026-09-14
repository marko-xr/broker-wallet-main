import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/delete_account_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _password = 'Correct-Horse-9';

UserModel _user(String uid, {String? mediaId}) => UserModel(
      uid: uid,
      name: 'Account $uid',
      email: '$uid@example.test',
      createdAt: DateTime.utc(2026),
      isEmailVerified: true,
      isPhoneVerified: false,
      profileMediaId: mediaId,
      subscription: UserSubscription(
        plan: 'test',
        isActive: false,
        features: const [],
      ),
      preferences: const {},
    );

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _Session implements AccountDeletionSession {
  _Session({this.currentUserId, this.isPasswordRecoveryActive = false});

  @override
  String? currentUserId;

  @override
  bool isPasswordRecoveryActive;

  final List<String> completed = [];
  final List<String> reconciled = [];
  AccountDeletionConvergence convergence = AccountDeletionConvergence.none;

  @override
  Future<void> completeAccountDeletion(String deletedUid) async {
    completed.add(deletedUid);
    if (currentUserId == deletedUid) currentUserId = null;
  }

  @override
  Future<AccountDeletionConvergence> reconcileAccountDeletion(
    String uid,
  ) async {
    reconciled.add(uid);
    if (convergence != AccountDeletionConvergence.none) {
      await completeAccountDeletion(uid);
    }
    return convergence;
  }
}

class _Gateway implements AccountDeletionGateway {
  _Gateway({this.failWith});

  AccountDeletionFailure? failWith;
  Completer<void>? hold;
  final List<String> expectedUids = [];
  final List<String> passwords = [];
  void Function()? duringRequest;

  int get calls => expectedUids.length;

  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async {
    expectedUids.add(expectedUid);
    passwords.add(password);
    duringRequest?.call();
    if (hold != null) await hold!.future;
    if (failWith != null) throw failWith!;
  }
}

class _Markers implements AccountDeletionMarkers {
  _Markers(this.events);

  final List<String> events;

  @override
  Future<void> remember(String uid) async => events.add('remember:$uid');

  @override
  Future<void> forgetIfOwnedBy(String uid) async => events.add('forget:$uid');
}

class _AuthRepository implements AuthRepository {
  _AuthRepository({UserModel? user, this.failSignOut = false})
      : _currentUser = user;

  final StreamController<UserModel?> _controller =
      StreamController<UserModel?>.broadcast();
  UserModel? _currentUser;
  bool failSignOut;
  int signOutCalls = 0;

  @override
  Stream<UserModel?> get authStateChanges => _controller.stream;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  void emit(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    // Mirrors the pinned gotrue: the local session is removed first.
    _currentUser = null;
    _controller.add(null);
    if (failSignOut) {
      throw const AuthFailure(code: AuthFailureCode.network, message: 'x');
    }
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UserRepository implements UserRepository {
  Completer<UserModel?>? pendingProfile;

  @override
  Future<UserModel?> getUserById(String uid) =>
      pendingProfile?.future ?? Future<UserModel?>.value(null);

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaForgetter {
  final List<Iterable<String>?> calls = [];

  Future<void> call({Iterable<String>? mediaIds}) async {
    calls.add(mediaIds?.toList());
  }
}

DeleteAccountViewModel _confirmingViewModel(
  _Gateway gateway,
  AccountDeletionSession session, {
  List<String>? markerEvents,
}) {
  final vm = DeleteAccountViewModel(
    gateway: gateway,
    session: session,
    markers: _Markers(markerEvents ?? []),
  );
  vm.continueToConfirmation();
  vm.setAcknowledged(true);
  return vm;
}

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PasswordRecoveryStateStore.resetForTesting();
  });

  group('Delete Account confirmation', () {
    test('nothing is sent from the review step or without acknowledgement',
        () async {
      final gateway = _Gateway();
      final session = _Session(currentUserId: _alice);
      final vm = DeleteAccountViewModel(gateway: gateway, session: session);
      addTearDown(vm.dispose);

      expect(vm.step, DeleteAccountStep.review);
      expect(await vm.submit(password: _password), isFalse);

      vm.continueToConfirmation();
      expect(vm.step, DeleteAccountStep.confirm);
      expect(await vm.submit(password: _password), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorAcknowledge');

      expect(gateway.calls, 0);
      expect(session.completed, isEmpty);
    });

    test('an empty password is refused without a server call', () async {
      final gateway = _Gateway();
      final vm = _confirmingViewModel(gateway, _Session(currentUserId: _alice));
      addTearDown(vm.dispose);

      expect(await vm.submit(password: ''), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorPasswordRequired');
      expect(gateway.calls, 0);
    });

    test('a rejected password deletes nothing and ends no session', () async {
      final gateway = _Gateway(
        failWith: const AccountDeletionFailure(
          AccountDeletionFailureCode.reauthenticationFailed,
        ),
      );
      final session = _Session(currentUserId: _alice);
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      expect(await vm.submit(password: 'wrong'), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorPassword');
      expect(vm.step, DeleteAccountStep.confirm,
          reason: 'retry stays possible');
      expect(session.completed, isEmpty);
      expect(session.currentUserId, _alice);
    });

    test('a double tap sends exactly one request', () async {
      final gateway = _Gateway()..hold = Completer<void>();
      final session = _Session(currentUserId: _alice);
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      final first = vm.submit(password: _password);
      expect(vm.isDeleting, isTrue);
      final second = await vm.submit(password: _password);
      expect(second, isFalse);

      gateway.hold!.complete();
      expect(await first, isTrue);
      expect(gateway.calls, 1);
      expect(session.completed, [_alice]);
    });

    test('the account captured at the start is the only one ever deleted',
        () async {
      final gateway = _Gateway();
      final session = _Session(currentUserId: _alice);
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      expect(await vm.submit(password: _password), isTrue);
      expect(gateway.expectedUids, [_alice]);
      expect(session.completed, [_alice]);
      expect(vm.step, DeleteAccountStep.completed);
    });

    test('switching account before submitting aborts without a request',
        () async {
      final gateway = _Gateway();
      final session = _Session(currentUserId: _alice);
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      session.currentUserId = _bob;
      expect(await vm.submit(password: _password), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorAccountChanged');
      expect(gateway.calls, 0);
      expect(session.completed, isEmpty);
    });

    test('signing out during confirmation aborts without a request', () async {
      final gateway = _Gateway();
      final session = _Session(currentUserId: _alice);
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      session.currentUserId = null;
      expect(await vm.submit(password: _password), isFalse);
      expect(gateway.calls, 0);
    });

    test(
        'an account switch during the request still completes only the '
        'deleted account', () async {
      final gateway = _Gateway();
      final session = _Session(currentUserId: _alice);
      gateway.duringRequest = () => session.currentUserId = _bob;
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      expect(await vm.submit(password: _password), isTrue);
      expect(session.completed, [_alice]);
      expect(session.currentUserId, _bob, reason: 'the other account is kept');
    });

    test('a password-recovery session cannot start or submit a deletion',
        () async {
      final gateway = _Gateway();
      final session = _Session(
        currentUserId: _alice,
        isPasswordRecoveryActive: true,
      );
      final vm = DeleteAccountViewModel(gateway: gateway, session: session);
      addTearDown(vm.dispose);

      expect(vm.canStart, isFalse);
      vm.continueToConfirmation();
      expect(vm.step, DeleteAccountStep.review);

      session.isPasswordRecoveryActive = false;
      vm.continueToConfirmation();
      vm.setAcknowledged(true);
      session.isPasswordRecoveryActive = true;
      expect(await vm.submit(password: _password), isFalse);
      expect(gateway.calls, 0);
    });

    test(
        'the pending-deletion marker is written before the request and '
        'cleared when nothing can have been deleted', () async {
      for (final code in accountDeletionNotAttempted) {
        final events = <String>[];
        final gateway = _Gateway(failWith: AccountDeletionFailure(code));
        gateway.duringRequest = () => events.add('request');
        final session = _Session(currentUserId: _alice);
        final vm = _confirmingViewModel(gateway, session, markerEvents: events);

        expect(await vm.submit(password: _password), isFalse, reason: '$code');
        expect(events, ['remember:$_alice', 'request', 'forget:$_alice'],
            reason: '$code');
        expect(session.reconciled, isEmpty, reason: '$code');
        expect(session.completed, isEmpty, reason: '$code');
        vm.dispose();
      }
    });

    test(
        'an unknown outcome is never treated as a deletion without Supabase '
        'Auth saying so', () async {
      for (final code in [
        AccountDeletionFailureCode.network,
        AccountDeletionFailureCode.unknown,
        AccountDeletionFailureCode.deletionPending,
        AccountDeletionFailureCode.deletionInProgress,
        AccountDeletionFailureCode.sessionExpired,
      ]) {
        final events = <String>[];
        final gateway = _Gateway(failWith: AccountDeletionFailure(code));
        final session = _Session(currentUserId: _alice);
        final vm = _confirmingViewModel(gateway, session, markerEvents: events);

        expect(await vm.submit(password: _password), isFalse, reason: '$code');
        expect(session.reconciled, [_alice], reason: '$code');
        expect(session.completed, isEmpty, reason: '$code');
        expect(events, ['remember:$_alice'], reason: 'marker kept for $code');
        expect(vm.step, DeleteAccountStep.confirm, reason: '$code');
        vm.dispose();
      }
    });

    test(
        'a lost success response completes once Supabase Auth reports the '
        'account gone', () async {
      final gateway = _Gateway(
        failWith: const AccountDeletionFailure(
          AccountDeletionFailureCode.network,
        ),
      );
      final session = _Session(currentUserId: _alice)
        ..convergence = AccountDeletionConvergence.deleted;
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      expect(await vm.submit(password: _password), isTrue);
      expect(vm.step, DeleteAccountStep.completed);
      expect(session.completed, [_alice]);
    });

    test('a rejected session ends the flow without claiming a deletion',
        () async {
      final gateway = _Gateway(
        failWith: const AccountDeletionFailure(
          AccountDeletionFailureCode.network,
        ),
      );
      final session = _Session(currentUserId: _alice)
        ..convergence = AccountDeletionConvergence.sessionEnded;
      final vm = _confirmingViewModel(gateway, session);
      addTearDown(vm.dispose);

      expect(await vm.submit(password: _password), isFalse);
      expect(vm.errorKey, 'deleteAccountErrorSession');
      expect(vm.isCompleted, isFalse);
      expect(vm.endedUnconfirmed, isTrue);
      expect(session.completed, [_alice], reason: 'the session was ended');
    });

    test('every failure maps to a key present in English and Arabic', () {
      final en = json.decode(
        File('lib/src/common/localization/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final ar = json.decode(
        File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = {
        for (final code in AccountDeletionFailureCode.values)
          deleteAccountErrorKey(code),
        'deleteAccountErrorAcknowledge',
        'deleteAccountErrorPasswordRequired',
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
        expect(ar[key], isNot(en[key]), reason: 'ar $key is translated');
      }
    });
  });

  group('Worker gateway', () {
    test('sends only the live token and the password — never a user id',
        () async {
      late http.Request sent;
      final gateway = WorkerAccountDeletionGateway(
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
              '{"status":"deleted","mediaObjectsRemoved":1}', 200);
        }),
        readCredentials: () => const AccountDeletionCredentials(
          userId: _alice,
          accessToken: 'live-token',
        ),
      );

      await gateway.deleteAccount(expectedUid: _alice, password: _password);

      expect(sent.method, 'POST');
      expect(sent.url.path, '/account/delete');
      expect(sent.headers['Authorization'], 'Bearer live-token');
      final body = json.decode(sent.body) as Map<String, dynamic>;
      expect(body.keys, ['password']);
      expect(sent.body.contains(_alice), isFalse);
    });

    test('a session that is no longer the expected account sends nothing',
        () async {
      var requests = 0;
      final gateway = WorkerAccountDeletionGateway(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        readCredentials: () => const AccountDeletionCredentials(
          userId: _bob,
          accessToken: 'bob-token',
        ),
      );

      await expectLater(
        gateway.deleteAccount(expectedUid: _alice, password: _password),
        throwsA(isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.accountChanged,
        )),
      );
      expect(requests, 0);
    });

    test('no session sends nothing', () async {
      var requests = 0;
      final gateway = WorkerAccountDeletionGateway(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        readCredentials: () => null,
      );

      await expectLater(
        gateway.deleteAccount(expectedUid: _alice, password: _password),
        throwsA(isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.sessionExpired,
        )),
      );
      expect(requests, 0);
    });

    test('a transport failure is a retryable network outcome', () async {
      final gateway = WorkerAccountDeletionGateway(
        httpClient: MockClient((_) async => throw http.ClientException('x')),
        readCredentials: () => const AccountDeletionCredentials(
          userId: _alice,
          accessToken: 'live-token',
        ),
      );
      await expectLater(
        gateway.deleteAccount(expectedUid: _alice, password: _password),
        throwsA(isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.network,
        )),
      );
    });

    test('server codes map to fixed outcomes and raw text is discarded', () {
      AccountDeletionFailureCode codeOf(int status, String body) {
        try {
          interpretAccountDeletionResponse(status, body);
        } on AccountDeletionFailure catch (failure) {
          return failure.code;
        }
        fail('expected a failure for $status $body');
      }

      expect(
        () => interpretAccountDeletionResponse(200, '{"status":"deleted"}'),
        returnsNormally,
      );
      // The server no longer vouches for a deleted account's token, so no
      // such response can count as a completed deletion.
      expect(codeOf(410, '{"error":"already_deleted"}'),
          AccountDeletionFailureCode.unknown);
      expect(codeOf(409, '{"error":"deletion_in_progress"}'),
          AccountDeletionFailureCode.deletionInProgress);
      expect(codeOf(503, '{"error":"deletion_pending"}'),
          AccountDeletionFailureCode.deletionPending);
      expect(codeOf(403, '{"error":"reauthentication_failed"}'),
          AccountDeletionFailureCode.reauthenticationFailed);
      expect(codeOf(409, '{"error":"reauthentication_unsupported"}'),
          AccountDeletionFailureCode.reauthenticationUnsupported);
      expect(codeOf(403, '{"error":"account_mismatch"}'),
          AccountDeletionFailureCode.accountChanged);
      expect(codeOf(403, '{"error":"recovery_session"}'),
          AccountDeletionFailureCode.recoverySession);
      expect(codeOf(502, '{"error":"media_cleanup_failed"}'),
          AccountDeletionFailureCode.mediaCleanupFailed);
      expect(codeOf(502, '{"error":"server_delete_failed"}'),
          AccountDeletionFailureCode.serverDeleteFailed);
      expect(codeOf(429, '{"error":"rate_limited"}'),
          AccountDeletionFailureCode.rateLimited);
      expect(codeOf(401, 'Unauthorized'),
          AccountDeletionFailureCode.sessionExpired);
      expect(codeOf(404, '{"error":"Not found"}'),
          AccountDeletionFailureCode.unavailable);
      // A 200 without the exact success marker is not a deletion.
      expect(
          codeOf(200, '{"status":"ok"}'), AccountDeletionFailureCode.unknown);
      // Raw admin / Postgres text never becomes an outcome of its own.
      expect(
        codeOf(500,
            '{"error":"Database error deleting user: violates foreign key sb_secret_x"}'),
        AccountDeletionFailureCode.network,
      );
      final failure = AccountDeletionFailure(
        codeOf(500, '{"error":"Database error deleting user"}'),
      );
      expect(failure.toString().contains('Database'), isFalse);
    });
  });

  group('Completing a deletion in AuthViewModel', () {
    Future<AuthViewModel> signedIn(
      _AuthRepository repo,
      _UserRepository users,
      _MediaForgetter media,
    ) async {
      final vm = AuthViewModel(
        authRepository: repo,
        userRepository: users,
        deletedAccountCleaner:
            DeletedAccountLocalDataCleaner(forgetProfileMedia: media.call),
      );
      repo.emit(repo.currentUser);
      await Future<void>.delayed(Duration.zero);
      return vm;
    }

    test(
        'clears the deleted account\'s local data and keeps language and '
        'theme', () async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'ar',
        'themeMode': 'dark',
        'cached_profile_snapshot_v1': json.encode({'uid': _alice}),
        'cached_user_model': '{}',
        'is_authenticated': true,
        'cached_item_counts': '{"offers":3}',
        'counts_last_updated': 1,
        'password_recovery_owner_uid': _alice,
        'signed_documents_list': <String>['device-document'],
      });
      PasswordRecoveryStateStore.resetForTesting(ownerUid: _alice);

      final repo = _AuthRepository(user: _user(_alice, mediaId: 'media-1'));
      final media = _MediaForgetter();
      final vm = await signedIn(repo, _UserRepository(), media);
      addTearDown(() async {
        vm.dispose();
        await repo.dispose();
      });
      expect(vm.isAuthenticated, isTrue);

      await vm.completeAccountDeletion(_alice);

      final prefs = await SharedPreferences.getInstance();
      expect(vm.isAuthenticated, isFalse);
      expect(vm.currentUser, isNull);
      expect(repo.signOutCalls, 1);
      expect(prefs.getString('cached_profile_snapshot_v1'), isNull);
      expect(prefs.getString('cached_user_model'), isNull);
      expect(prefs.getBool('is_authenticated'), isFalse);
      expect(prefs.getString('cached_item_counts'), isNull);
      expect(prefs.getString('password_recovery_owner_uid'), isNull);
      expect(PasswordRecoveryStateStore.ownerUid, isNull);
      expect(media.calls, [null], reason: 'all avatar caches are cleared');

      // Device preferences and device-local documents survive.
      expect(prefs.getString('languageCode'), 'ar');
      expect(prefs.getString('themeMode'), 'dark');
      expect(prefs.getStringList('signed_documents_list'), ['device-document']);
    });

    test('a sign-out that cannot reach the server still ends local state',
        () async {
      final repo = _AuthRepository(user: _user(_alice), failSignOut: true);
      final vm = await signedIn(repo, _UserRepository(), _MediaForgetter());
      addTearDown(() async {
        vm.dispose();
        await repo.dispose();
      });

      await vm.completeAccountDeletion(_alice);

      expect(vm.isAuthenticated, isFalse);
      expect(vm.status, AuthStatus.unauthenticated);
      expect(vm.isLoading, isFalse);
    });

    test('a different signed-in account is never signed out or wiped',
        () async {
      SharedPreferences.setMockInitialValues({
        'cached_profile_snapshot_v1': json.encode({'uid': _bob}),
        'cached_item_counts': '{"offers":7}',
      });
      final repo = _AuthRepository(user: _user(_bob));
      final media = _MediaForgetter();
      final vm = await signedIn(repo, _UserRepository(), media);
      addTearDown(() async {
        vm.dispose();
        await repo.dispose();
      });

      await vm.completeAccountDeletion(_alice);

      final prefs = await SharedPreferences.getInstance();
      expect(repo.signOutCalls, 0);
      expect(vm.isAuthenticated, isTrue);
      expect(vm.currentUserId, _bob);
      expect(prefs.getString('cached_profile_snapshot_v1'), isNotNull);
      expect(prefs.getString('cached_item_counts'), '{"offers":7}');
      expect(media.calls.single, isEmpty,
          reason: 'only the deleted account\'s own avatar ids, of which '
              'none are known here');
    });

    test('a late profile read cannot resurrect the deleted account', () async {
      final users = _UserRepository()..pendingProfile = Completer<UserModel?>();
      final repo = _AuthRepository(user: _user(_alice));
      final vm = await signedIn(repo, users, _MediaForgetter());
      addTearDown(() async {
        vm.dispose();
        await repo.dispose();
      });
      expect(vm.profileHydration, ProfileHydrationStatus.resolving);

      await vm.completeAccountDeletion(_alice);
      users.pendingProfile!.complete(_user(_alice, mediaId: 'late-media'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(vm.currentUser, isNull);
      expect(vm.isAuthenticated, isFalse);
      expect(
        await OfflineAuthService.instance.getProfileSnapshot(_alice),
        isNull,
      );
    });

    test('completing twice is harmless', () async {
      final repo = _AuthRepository(user: _user(_alice));
      final vm = await signedIn(repo, _UserRepository(), _MediaForgetter());
      addTearDown(() async {
        vm.dispose();
        await repo.dispose();
      });

      await vm.completeAccountDeletion(_alice);
      await vm.completeAccountDeletion(_alice);
      expect(vm.isAuthenticated, isFalse);
      expect(repo.signOutCalls, 1);
    });
  });

  group('Deletion job migration and hosted validation script', () {
    const migrationPath =
        'supabase/migrations/20260913000100_account_deletion_jobs.sql';
    const scriptPath =
        'supabase/validation/account_deletion_cascade_validation.sql';
    late String migration;
    late String script;

    setUpAll(() {
      migration =
          File(migrationPath).readAsStringSync().replaceAll('\r\n', '\n');
      script = File(scriptPath).readAsStringSync().replaceAll('\r\n', '\n');
    });

    String normalized(String sql) => sql
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line != 'begin;' && line != 'commit;')
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    test(
        'the migration is service-role only, has no foreign key and keeps '
        'no personal data', () {
      expect(migration, contains('user_id uuid primary key,'));
      expect(migration.toLowerCase().contains('references'), isFalse);
      expect(
          migration,
          contains(
              'alter table public.account_deletion_jobs enable row level security;'));
      expect(migration.contains('create policy'), isFalse);
      for (final role in ['public', 'anon', 'authenticated']) {
        expect(
            migration,
            contains(
                'revoke all on table public.account_deletion_jobs from $role;'));
      }
      expect(migration, contains('to service_role;'));
      // The finalization time is stamped by the Worker's cron on Cloudflare's
      // clock, never defaulted from the database clock.
      expect(migration, contains('  cleanup_not_before timestamptz,\n'));
      expect(migration.contains('interval'), isFalse);
      expect(migration, contains('  bucket text not null,\n'));
      expect(migration,
          contains('check (cleanup_not_before is null or status in'));
      expect(migration, contains('(bucket, status, cleanup_not_before)'));
      for (final column in [
        'email',
        'phone',
        'name text',
        'object_key',
        'token'
      ]) {
        expect(RegExp('^\\s+$column', multiLine: true).hasMatch(migration),
            isFalse,
            reason: column);
      }
    });

    test('the script installs the migration from its exact file text', () {
      const tag = r'$migration_20260913000100$';
      final quote = RegExp.escape(tag);
      final match = RegExp('$quote\\n([\\s\\S]*?)$quote;').firstMatch(script);
      expect(match, isNotNull);
      expect(normalized(match!.group(1)!), normalized(migration));
    });

    test('opens one transaction, never commits, and ends by rolling back', () {
      final statements = script
          .split('\n')
          .where(
              (line) => line.trim().isNotEmpty && !line.trim().startsWith('--'))
          .toList();
      expect(statements.first.trim(), 'begin;');
      expect(statements.last.trim(), 'rollback;');
      expect(
        RegExp(r'^\s*(commit|end\s+transaction)\s*;',
                multiLine: true, caseSensitive: false)
            .hasMatch(script),
        isFalse,
      );
      expect(
        RegExp(r'^\s*rollback\s*;', multiLine: true, caseSensitive: false)
            .allMatches(script),
        hasLength(1),
      );
      expect(
          script, contains("message = 'account_deletion_validation_rollback'"));
      expect(
        script.indexOf("message = 'account_deletion_validation_rollback'"),
        lessThan(script.indexOf('7. Post-checks')),
      );
    });

    test('deletes and writes only reserved synthetic identities', () {
      expect(script, contains("set local lock_timeout = '3s'"));
      expect(script, contains("'@account-deletion-validation.invalid'"));
      final deletes = RegExp(r'delete from (\S+) where ([^;]+);')
          .allMatches(script)
          .map((match) => '${match.group(1)} ${match.group(2)}')
          .toList();
      expect(deletes, isNotEmpty);
      for (final statement in deletes) {
        expect(statement, 'auth.users id = user_a', reason: statement);
      }
      expect(
          RegExp(r'\bupdate\s+auth\.', caseSensitive: false).hasMatch(script),
          isFalse);
      for (final ids in RegExp(r"constant uuid := '([0-9a-f-]+)'")
          .allMatches(script)
          .map((match) => match.group(1)!)) {
        expect(ids, startsWith('de1e7e00-0000-4000-8000-'));
      }
      expect(script,
          contains("'pre: the reserved test ids and emails are unused'"));
    });
  });

  group('Security boundaries in source', () {
    test('Flutter holds no server secret and never calls the admin API', () {
      const forbidden = [
        'sb_secret_',
        'service_role',
        'SUPABASE_SECRET_KEY',
        'R2_SECRET_ACCESS_KEY',
        'R2_ACCESS_KEY_ID',
        'auth.admin',
        '/admin/users',
      ];
      for (final file in _dartFiles('lib')) {
        final source = file.readAsStringSync();
        for (final value in forbidden) {
          expect(source.contains(value), isFalse,
              reason: '${file.path} contains $value');
        }
      }
    });

    test('the deletion code logs nothing', () {
      const files = [
        'lib/src/services/account_deletion_service.dart',
        'lib/src/services/deleted_account_local_data_cleaner.dart',
        'lib/src/viewmodels/delete_account_viewmodel.dart',
        'lib/src/views/Widgets/delete_account_sheet.dart',
      ];
      final logging = RegExp(r'\b(print|debugPrint|log)\s*\(');
      for (final path in files) {
        expect(logging.hasMatch(File(path).readAsStringSync()), isFalse,
            reason: path);
      }
    });

    test('the Worker endpoint derives the account from the token only', () {
      final worker = File(
        'cloudflare/workers/r2-profile-upload/account_deletion.js',
      ).readAsStringSync();
      expect(worker, contains('/auth/v1/user'));
      expect(worker, contains('owner_id=eq.\${encodeURIComponent(userId)}'));
      expect(worker, contains('should_soft_delete: false'));
      // The id used for deletion is the verified identity's, never the body's.
      expect(worker, contains('const userId = identity.id;'));
      // A rejected token's subject is never read to choose an account.
      expect(worker.contains('.sub'), isFalse);
      expect(worker.contains('already_deleted'), isFalse);
    });

    test('the upload Worker checks the quarantine before signing a PUT URL',
        () {
      final worker = File('cloudflare/workers/r2-profile-upload/worker.js')
          .readAsStringSync();
      final authorize = worker.substring(
        worker.indexOf('async function handleAuthorize'),
        worker.indexOf('async function handleConfirm'),
      );
      final checkedAt = authorize.indexOf('const quarantineCheckedAt');
      final check = authorize.indexOf('await assertUploadsAllowed(userId');
      final sign = authorize.indexOf('await createPresignedR2Url(');
      final bound = authorize.indexOf(
        'assertPresignedWithin(presignedUrl, quarantineCheckedAt + MAX_SIGNING_DELAY_MS)',
      );
      expect(checkedAt, greaterThan(-1));
      expect(checkedAt < check && check < sign && sign < bound, isTrue);
      expect(worker, contains('runDeletionFinalizer(env)'));
      expect(
        File('cloudflare/workers/r2-profile-upload/wrangler.toml')
            .readAsStringSync(),
        contains('crons = ["*/5 * * * *"]'),
      );
    });

    test(
        'Profile keeps its rows and order; only the Delete Account action '
        'changed', () {
      final source =
          File('lib/src/views/Screens/home/Profile/profile_view.dart')
              .readAsStringSync();
      // Every title/subtitle key in file order, captured from the approved
      // version of this screen before Delete Account was wired.
      final titles = RegExp(r"title:\s*localization\.translate\('(\w+)'\)")
          .allMatches(source)
          .map((match) => match.group(1))
          .toList();
      expect(titles, [
        'generalSettings',
        'language',
        'theme',
        'notifications',
        'accountBilling',
        'subscription',
        'myPlan',
        'viewQuotaUsage',
        'supportInformation',
        'helpSupport',
        'helpSupport',
        'privacyPolicy',
        'privacyPolicy',
        'termsConditions',
        'termsConditions',
        'aboutBrokerWallet',
        'contactUs',
        'contactUs',
        'feedBack',
        'shareApp',
        'privacySecurityAccount',
        'security',
        'securityHint',
        'security',
        'exportData',
        'exportDataHint',
        'exportData',
        'deleteAccount',
        'deleteAccountHint',
        'logout',
      ]);
      expect(source, contains('onTap: () => showDeleteAccountFlow(context)'));
      expect(source.contains('deleteAccountUnavailable'), isFalse);
      expect(source, contains('onTap: vm.isLoggingOut ? null : vm.logout'));
      expect(
        RegExp(r'destructive: true').allMatches(source).length,
        1,
        reason: 'the existing destructive treatment is unchanged',
      );
    });
  });
}
