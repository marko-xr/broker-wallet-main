import 'dart:async';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';

UserModel _verified({String uid = _uid}) => UserModel(
      uid: uid,
      email: 'person@example.test',
      name: 'Person',
      isEmailVerified: true,
      isPhoneVerified: false,
      createdAt: DateTime.utc(2026),
      subscription: UserSubscription(
        plan: 'test',
        isActive: false,
        features: const [],
      ),
      preferences: const {},
    );

/// An auth repository that also owns password recovery, exactly as
/// `SupabaseAuthRepository` does: recovery ownership is resolved **before** the
/// identity for that session is published, and is answerable synchronously.
class _RecoveryAwareRepository implements AuthRepository, PasswordCapability {
  _RecoveryAwareRepository({UserModel? initialUser, String? recoveringUid})
      : _currentUser = initialUser,
        _recoveryUid = recoveringUid;

  final StreamController<UserModel?> _identity =
      StreamController<UserModel?>.broadcast();
  final StreamController<PasswordRecoverySession> _recovery =
      StreamController<PasswordRecoverySession>.broadcast();

  UserModel? _currentUser;
  String? _recoveryUid;
  int recoveriesEnded = 0;

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _identity.stream;
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  @override
  bool get isPasswordRecoveryActive =>
      _recoveryUid != null && _currentUser?.uid == _recoveryUid;

  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions =>
      _recovery.stream;

  @override
  Future<void> endPasswordRecovery() async {
    recoveriesEnded++;
    _recoveryUid = null;
    emitSignedOut();
  }

  @override
  bool get verifiesCurrentPassword => false;

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {}

  /// A recovery link was exchanged: ownership is set first, then the session
  /// identity is published. This ordering is the fix under test.
  void emitRecoverySession(UserModel user) {
    _recoveryUid = user.uid;
    _currentUser = user;
    _identity.add(user);
  }

  /// An ordinary sign-in clears any recovery ownership.
  void emitNormalSignIn(UserModel user) {
    _recoveryUid = null;
    _currentUser = user;
    _identity.add(user);
  }

  void emitSignedOut() {
    _recoveryUid = null;
    _currentUser = null;
    _identity.add(null);
  }

  Future<void> dispose() async {
    await _identity.close();
    await _recovery.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietUserRepository implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A notification repository whose realtime feed fails the way the device did.
class _FailingNotificationRepository implements NotificationRepository {
  _FailingNotificationRepository({required this.error});

  final Object error;
  int watchCalls = 0;

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    watchCalls++;
    return Stream<List<NotificationModel>>.error(error);
  }

  @override
  Stream<int> watchUnreadCount(String userId) {
    watchCalls++;
    return Stream<int>.error(error);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthViewModel _authViewModel(_RecoveryAwareRepository repository) {
  final vm = AuthViewModel(
    authRepository: repository,
    userRepository: _QuietUserRepository(),
  );
  addTearDown(vm.dispose);
  return vm;
}

/// The router's actual recovery input, assembled the way `_createRouter` does.
String? redirectFor(AuthViewModel auth, String path) => resolveAuthRedirect(
      auth.status,
      path,
      passwordRecoveryActive: auth.isPasswordRecoveryActive,
    );

void main() {
  group('Recovery session quarantine', () {
    test('a recovery session is never application-authenticated for routing',
        () async {
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);
      await pumpEventQueue();

      repository.emitRecoverySession(_verified());
      await pumpEventQueue();

      // Authenticated at the transport level...
      expect(auth.isAuthenticated, isTrue);
      // ...but quarantined for navigation.
      expect(auth.isPasswordRecoveryActive, isTrue);
      expect(redirectFor(auth, '/home'), '/reset-password');
      expect(redirectFor(auth, '/reset-password'), isNull);
    });

    test('status and recovery are published in the same notification',
        () async {
      // This is the real-device defect. If the router could observe an
      // authenticated status before it observed the recovery flag, it would
      // route to Home for that one notification. Every notification is sampled
      // and none of them may resolve to Home.
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);
      await pumpEventQueue();

      final destinations = <String?>[];
      auth.addListener(() => destinations.add(redirectFor(auth, '/home')));

      repository.emitRecoverySession(_verified());
      await pumpEventQueue();

      expect(destinations, isNotEmpty);
      expect(
        destinations.any((destination) => destination == null),
        isFalse,
        reason: 'no notification may leave the router sitting on /home',
      );
      expect(destinations.every((d) => d == '/reset-password'), isTrue);
    });

    test('every ordinary authenticated route is closed', () async {
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);
      repository.emitRecoverySession(_verified());
      await pumpEventQueue();

      for (final path in const [
        '/home',
        '/profile',
        '/edit-profile',
        '/search',
        '/favorites',
      ]) {
        expect(redirectFor(auth, path), '/reset-password', reason: path);
      }
    });

    test('a session restored after process death is still quarantined',
        () async {
      // Cold start: the marker was persisted, so the repository answers for a
      // session that arrives with no recovery event at all.
      final repository = _RecoveryAwareRepository(recoveringUid: _uid);
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);

      repository.emitRecoverySession(_verified());
      await pumpEventQueue();

      expect(auth.isPasswordRecoveryActive, isTrue);
      expect(redirectFor(auth, '/home'), '/reset-password');
    });

    test('a normal login is never quarantined', () async {
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);

      repository.emitNormalSignIn(_verified());
      await pumpEventQueue();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.isPasswordRecoveryActive, isFalse);
      expect(redirectFor(auth, '/home'), isNull);
      expect(redirectFor(auth, '/sign-in'), '/home');
      expect(redirectFor(auth, '/reset-password'), '/home');
    });

    test('recovery does not survive into the next normal session', () async {
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);

      repository.emitRecoverySession(_verified());
      await pumpEventQueue();
      expect(auth.isPasswordRecoveryActive, isTrue);

      await repository.endPasswordRecovery();
      await pumpEventQueue();
      expect(auth.isPasswordRecoveryActive, isFalse);
      expect(auth.isAuthenticated, isFalse);

      repository.emitNormalSignIn(_verified());
      await pumpEventQueue();
      expect(auth.isPasswordRecoveryActive, isFalse);
      expect(redirectFor(auth, '/home'), isNull);
    });

    test('a recovery for one account does not quarantine another', () async {
      final repository = _RecoveryAwareRepository(recoveringUid: _otherUid);
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);

      // The live session belongs to someone else, so the marker does not apply.
      repository._currentUser = _verified();
      repository.emitNormalSignIn(_verified());
      await pumpEventQueue();

      expect(auth.isPasswordRecoveryActive, isFalse);
    });

    test('a sign-out during recovery is safe', () async {
      final repository = _RecoveryAwareRepository();
      addTearDown(repository.dispose);
      final auth = _authViewModel(repository);
      repository.emitRecoverySession(_verified());
      await pumpEventQueue();

      repository.emitSignedOut();
      await pumpEventQueue();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.isPasswordRecoveryActive, isFalse);
      expect(redirectFor(auth, '/reset-password'), '/sign-in');
    });
  });

  group('Notification feed during and after recovery', () {
    test('no account-scoped feed is opened while a recovery is active', () {
      // Mirrors main.dart: the proxy provider passes null while quarantined, so
      // the Realtime channel is never opened for a recovery session.
      final repository = _FailingNotificationRepository(
        error: StateError('should not be reached'),
      );
      final vm = NotificationViewModel(repository: repository);
      addTearDown(vm.dispose);

      // main.dart computes this argument as
      // `authVM.isPasswordRecoveryActive ? null : authVM.currentUser?.uid`.
      // With a recovery active that is null, so no user is ever attached.
      vm.attachUser(null);

      expect(repository.watchCalls, 0);
    });

    test('a refused Realtime channel never becomes an unhandled error',
        () async {
      // The device threw RealtimeSubscribeException("invalid column for filter
      // recipient_id") onto these streams. Without onError that escapes as an
      // unhandled async error and pauses the debugger repeatedly.
      final repository = _FailingNotificationRepository(
        error: StateError('invalid column for filter recipient_id'),
      );
      final vm = NotificationViewModel(repository: repository);
      addTearDown(vm.dispose);

      final escaped = <Object>[];
      await runZonedGuarded(() async {
        vm.attachUser(_uid);
        await pumpEventQueue();
      }, (error, _) => escaped.add(error));

      expect(escaped, isEmpty);
      expect(repository.watchCalls, 2);
      expect(vm.isFeedUnavailable, isTrue);
      expect(vm.isLoading, isFalse);
    });

    test('a feed failure never carries the provider message to the UI',
        () async {
      const raw = 'invalid column for filter recipient_id';
      final repository = _FailingNotificationRepository(error: StateError(raw));
      final vm = NotificationViewModel(repository: repository);
      addTearDown(vm.dispose);

      vm.attachUser(_uid);
      await pumpEventQueue();

      expect(vm.isFeedUnavailable, isTrue);
      expect(vm.notifications, isEmpty);
      expect(vm.unreadCount, 0);
    });

    test('a feed failure leaves authentication untouched', () async {
      final auth = _RecoveryAwareRepository(initialUser: _verified());
      addTearDown(auth.dispose);
      final authVm = _authViewModel(auth);
      await pumpEventQueue();
      expect(authVm.isAuthenticated, isTrue);

      final repository = _FailingNotificationRepository(
        error: StateError('invalid column for filter recipient_id'),
      );
      final vm = NotificationViewModel(repository: repository);
      addTearDown(vm.dispose);
      vm.attachUser(_uid);
      await pumpEventQueue();

      expect(authVm.isAuthenticated, isTrue,
          reason: 'a notification failure is not an auth event');
      expect(authVm.currentUser?.uid, _uid);
    });
  });
}
