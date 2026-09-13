import 'dart:async';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/auth_callback_coordinator.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _validPassword = 'Passw0rdd';

/// Password recovery has its own callback address; every other auth flow keeps
/// the general one. That separation is the whole ownership test.
final _recoverySessionCallback = Uri.parse(
  'brokerwallet://auth/reset-password?code=pkce-auth-code',
);
final _recoveryErrorCallback = Uri.parse(
  'brokerwallet://auth/reset-password'
  '?error=access_denied&error_code=otp_expired'
  '&error_description=Email+link+is+invalid+or+has+expired',
);

/// The same expired-link parameters, at the general auth address. GoTrue gives
/// an error redirect no reliable `type`, so this is exactly the callback that
/// must never be claimed by password recovery.
final _genericErrorCallback = Uri.parse(
  'brokerwallet://auth/callback'
  '?error=access_denied&error_code=otp_expired'
  '&error_description=Email+link+is+invalid+or+has+expired',
);
final _emailChangeErrorCallback = Uri.parse(
  'brokerwallet://auth/callback'
  '?error=access_denied&error_code=otp_expired&type=email_change',
);
final _emailChangeIntermediateCallback = Uri.parse(
  'brokerwallet://auth/callback'
  '?message=Confirmation+link+accepted.+Please+proceed+to+confirm+link+sent+to+the+other+email',
);
final _signupVerificationCallback = Uri.parse(
  'brokerwallet://auth/callback?code=pkce-auth-code&type=signup',
);

class _Gateway implements PasswordCapability {
  final StreamController<PasswordRecoverySession> _recovery =
      StreamController<PasswordRecoverySession>.broadcast();

  int changeCalls = 0;
  String? lastNewPassword;
  Object? failWith;
  Completer<void>? pending;

  @override
  bool get verifiesCurrentPassword => false;

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    changeCalls++;
    lastNewPassword = newPassword;
    if (pending != null) await pending!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions =>
      _recovery.stream;

  /// Mirrors the repository: recovery ownership is answerable synchronously,
  /// and ending a recovery signs the session out.
  bool recoveryActive = false;
  int recoveriesEnded = 0;
  _Session? session;

  @override
  bool get isPasswordRecoveryActive => recoveryActive;

  @override
  Future<void> endPasswordRecovery() async {
    recoveriesEnded++;
    recoveryActive = false;
    session?.uid = null;
  }

  void emit(String ownerUid) {
    recoveryActive = true;
    _recovery.add(
      PasswordRecoverySession(
        ownerUid: ownerUid,
        startedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> close() => _recovery.close();
}

class _Session implements AuthRepository {
  _Session(this.uid);

  String? uid;

  @override
  String? get currentUserId => uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({String? sessionUid = _uid})
      : gateway = _Gateway(),
        session = _Session(sessionUid),
        callbacks = StreamController<AuthCallbackEvent>.broadcast() {
    gateway.session = session;
    vm = PasswordRecoveryViewModel(
      gateway: gateway,
      authRepository: session,
      callbacks: callbacks.stream,
    );
  }

  final _Gateway gateway;
  final _Session session;
  final StreamController<AuthCallbackEvent> callbacks;
  late final PasswordRecoveryViewModel vm;

  /// Delivers [uri] the way the coordinator would: session-bearing callbacks
  /// are consumed by Supabase and never published.
  Future<void> deliver(Uri uri) async {
    if (classifyAuthCallback(uri) == AuthCallbackKind.session) return;
    callbacks.add(describeAuthCallback(uri));
    await pumpEventQueue();
  }

  Future<void> emitRecovery([String ownerUid = _uid]) async {
    gateway.emit(ownerUid);
    await pumpEventQueue();
  }

  Future<void> close() async {
    vm.dispose();
    await callbacks.close();
    await gateway.close();
  }
}

_Harness harness({String? sessionUid = _uid}) {
  final h = _Harness(sessionUid: sessionUid);
  addTearDown(h.close);
  return h;
}

void main() {
  group('Dedicated recovery callback address', () {
    test('the two callback addresses are distinct and share scheme and host',
        () {
      final general = Uri.parse(SupabaseConfig.authCallbackUri);
      final recovery = Uri.parse(SupabaseConfig.passwordRecoveryCallbackUri);

      expect(recovery, isNot(general));
      // Same scheme and host means the existing Android intent filter
      // (scheme + host, no path) and the iOS URL scheme already accept it.
      expect(recovery.scheme, general.scheme);
      expect(recovery.host, general.host);
      expect(recovery.path, isNot(general.path));
    });

    test('only the recovery address is recognised as password recovery', () {
      expect(isPasswordRecoveryCallback(_recoverySessionCallback), isTrue);
      expect(isPasswordRecoveryCallback(_recoveryErrorCallback), isTrue);
      expect(isPasswordRecoveryCallback(_genericErrorCallback), isFalse);
      expect(isPasswordRecoveryCallback(_emailChangeErrorCallback), isFalse);
      expect(isPasswordRecoveryCallback(_signupVerificationCallback), isFalse);
    });

    test('the address match tolerates OS case folding and a trailing slash',
        () {
      expect(
        isPasswordRecoveryCallback(
          Uri.parse('BROKERWALLET://AUTH/reset-password?error=x'),
        ),
        isTrue,
      );
      expect(
        isPasswordRecoveryCallback(
          Uri.parse('brokerwallet://auth/reset-password/?error=x'),
        ),
        isTrue,
      );
    });

    test('a look-alike path is not accepted', () {
      for (final uri in const [
        'brokerwallet://auth/reset-password-x?error=x',
        'brokerwallet://auth/callback/reset-password?error=x',
        'brokerwallet://other/reset-password?error=x',
      ]) {
        expect(
          isPasswordRecoveryCallback(Uri.parse(uri)),
          isFalse,
          reason: uri,
        );
      }
    });

    test('a valid recovery link is session-bearing, so Supabase owns it', () {
      expect(
        classifyAuthCallback(_recoverySessionCallback),
        AuthCallbackKind.session,
      );
      expect(
          supabaseShouldExchangeAuthCallback(_recoverySessionCallback), isTrue);
    });

    test('an expired recovery link is an error callback the app owns', () {
      expect(
        classifyAuthCallback(_recoveryErrorCallback),
        AuthCallbackKind.error,
      );
      expect(
        supabaseShouldExchangeAuthCallback(_recoveryErrorCallback),
        isFalse,
      );
      final event = describeAuthCallback(_recoveryErrorCallback);
      expect(event.isPasswordRecovery, isTrue);
      expect(event.errorCode, 'otp_expired');
    });

    test('the provider description is dropped at the boundary', () {
      final event = describeAuthCallback(_recoveryErrorCallback);
      expect(event.toString(), isNot(contains('invalid or has expired')));
      expect(event.toString(), isNot(contains('error_description')));
    });

    test('no token or code from the link survives into the event', () {
      final event = describeAuthCallback(
        Uri.parse(
          'brokerwallet://auth/reset-password?error=access_denied'
          '&error_code=otp_expired&token=secret-recovery-token'
          '#access_token=header.payload.sig&refresh_token=secret-refresh',
        ),
      );
      final rendered = event.toString();
      for (final secret in const [
        'secret-recovery-token',
        'header.payload.sig',
        'secret-refresh',
      ]) {
        expect(rendered, isNot(contains(secret)), reason: secret);
      }
    });

    test('a Supabase recovery session starts the flow', () async {
      final h = harness();
      expect(h.vm.phase, PasswordRecoveryPhase.none);

      await h.emitRecovery();

      expect(h.vm.phase, PasswordRecoveryPhase.active);
      expect(h.vm.recoveryUid, _uid);
      // A live recovery *session* is held by the repository, which publishes it
      // with the session itself. This class only holds the route for the
      // session-less failure state.
      expect(h.gateway.isPasswordRecoveryActive, isTrue);
      expect(h.vm.holdsRoute, isFalse);
    });

    test('the recovery account comes from the session, not the link', () async {
      final h = harness();
      await h.emitRecovery(_otherUid);
      expect(h.vm.recoveryUid, _otherUid);
    });
  });

  group('Collisions with other auth callbacks', () {
    test('an Email Change error callback does not start a recovery', () async {
      final h = harness();
      await h.deliver(_emailChangeErrorCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
    });

    test('the Secure Email Change intermediate callback is ignored', () async {
      final h = harness();
      await h.deliver(_emailChangeIntermediateCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.none);
    });

    test('a signup verification callback never reaches recovery', () async {
      final h = harness();
      // Session-bearing: Supabase consumes it, the coordinator never sees it.
      await h.deliver(_signupVerificationCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.none);
    });

    test(
        'an error at the general auth address is never claimed, whenever it '
        'arrives', () async {
      // The parameters are identical to an expired recovery link; only the
      // address differs. Under the previous time-based rule this callback was
      // claimed whenever a reset had been requested recently, which is exactly
      // the misclassification this address split removes. No amount of elapsed
      // time, and no ordering, changes the outcome now.
      final h = harness();
      await h.deliver(_genericErrorCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.none);

      await h.deliver(_genericErrorCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
      expect(h.vm.errorKey, isNull);
    });

    test('recovery ownership needs no clock and no stored request state', () {
      // The view model takes a gateway, a session and a callback stream, and
      // nothing else. There is no marker, no timestamp and no injectable clock
      // left to base a classification on.
      final vm = PasswordRecoveryViewModel(
        gateway: null,
        authRepository: null,
      );
      addTearDown(vm.dispose);
      expect(vm.phase, PasswordRecoveryPhase.none);
    });
  });

  group('Expired and duplicate links', () {
    test('an expired recovery link produces a safe explained state', () async {
      final h = harness();
      await h.deliver(_recoveryErrorCallback);

      expect(h.vm.phase, PasswordRecoveryPhase.linkFailed);
      expect(h.vm.errorKey, 'resetLinkExpiredMessage');
      expect(h.vm.holdsRoute, isTrue);
      expect(h.vm.recoveryUid, isNull);
    });

    test('a duplicate recovery session does not restart the flow', () async {
      final h = harness();
      await h.emitRecovery();
      final startedWith = h.vm.recoveryUid;

      var notifications = 0;
      h.vm.addListener(() => notifications++);
      await h.emitRecovery();

      expect(notifications, 0);
      expect(h.vm.recoveryUid, startedWith);
      expect(h.vm.phase, PasswordRecoveryPhase.active);
    });

    test('a recovery restored after process death is still a recovery',
        () async {
      // No `passwordRecovery` event: the session came back from storage and
      // announced itself as an ordinary `initialSession`. The repository is the
      // one that still knows, so the screen must follow it.
      final h = harness();
      h.gateway.recoveryActive = true;

      expect(h.vm.phase, PasswordRecoveryPhase.active);
      expect(h.vm.recoveryUid, _uid);
    });

    test('a duplicate link after completion keeps the confirmation', () async {
      final h = harness();
      await h.emitRecovery();
      await h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      expect(h.vm.phase, PasswordRecoveryPhase.completed);

      await h.emitRecovery();
      expect(h.vm.phase, PasswordRecoveryPhase.completed);

      await h.deliver(_recoveryErrorCallback);
      expect(h.vm.phase, PasswordRecoveryPhase.completed);
      expect(h.gateway.changeCalls, 1);
    });

    test('a recovery for a different account replaces the previous one',
        () async {
      final h = harness();
      await h.emitRecovery();
      await h.emitRecovery(_otherUid);
      expect(h.vm.recoveryUid, _otherUid);
      expect(h.vm.phase, PasswordRecoveryPhase.active);
    });
  });

  group('Setting the new password', () {
    test('a valid reset reaches Supabase and completes', () async {
      final h = harness();
      await h.emitRecovery();

      expect(
        await h.vm.submitNewPassword(
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isTrue,
      );
      expect(h.gateway.changeCalls, 1);
      expect(h.gateway.lastNewPassword, _validPassword);
      expect(h.vm.phase, PasswordRecoveryPhase.completed);
    });

    test('submitting without an active recovery is refused', () async {
      final h = harness();
      expect(
        await h.vm.submitNewPassword(
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(h.gateway.changeCalls, 0);
    });

    test('a policy failure makes no network call', () async {
      final h = harness();
      await h.emitRecovery();

      expect(
        await h.vm.submitNewPassword(
          newPassword: 'weak',
          confirmPassword: 'weak',
        ),
        isFalse,
      );
      expect(h.gateway.changeCalls, 0);
      expect(h.vm.errorKey, 'passwordDoesNotMeetRequirements');
    });

    test('a mismatch is reported without a network call', () async {
      final h = harness();
      await h.emitRecovery();

      expect(
        await h.vm.submitNewPassword(
          newPassword: _validPassword,
          confirmPassword: 'Passw0rde',
        ),
        isFalse,
      );
      expect(h.gateway.changeCalls, 0);
      expect(h.vm.errorKey, 'passwordsDoNotMatch');
    });

    test('a duplicate submit while one is in flight is refused', () async {
      final h = harness();
      h.gateway.pending = Completer<void>();
      await h.emitRecovery();

      final first = h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      await pumpEventQueue();
      final second = await h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      expect(second, isFalse);
      h.gateway.pending!.complete();
      expect(await first, isTrue);
      expect(h.gateway.changeCalls, 1);
    });

    test('a session that no longer matches the recovery is refused', () async {
      final h = harness();
      await h.emitRecovery();
      h.session.uid = _otherUid;

      expect(
        await h.vm.submitNewPassword(
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isFalse,
      );
      expect(h.gateway.changeCalls, 0);
      expect(h.vm.errorKey, 'passwordChangeAccountChanged');
    });

    test('an account switch during the request is not reported as success',
        () async {
      final h = harness();
      h.gateway.pending = Completer<void>();
      await h.emitRecovery();

      final submitted = h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      await pumpEventQueue();
      h.session.uid = _otherUid;
      h.gateway.pending!.complete();

      expect(await submitted, isFalse);
      expect(h.vm.phase, isNot(PasswordRecoveryPhase.completed));
      expect(h.vm.errorKey, 'passwordChangeAccountChanged');
    });

    test('a backend failure is mapped, never surfaced raw', () async {
      final h = harness();
      h.gateway.failWith = const AuthFailure(
        code: AuthFailureCode.otpInvalidOrExpired,
        message: 'internal only',
      );
      await h.emitRecovery();

      await h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );
      expect(h.vm.errorKey, 'resetLinkExpiredMessage');
      expect(h.vm.phase, PasswordRecoveryPhase.active);
    });

    test('a successful reset signs the recovery session out', () async {
      final h = harness();
      await h.emitRecovery();

      expect(
        await h.vm.submitNewPassword(
          newPassword: _validPassword,
          confirmPassword: _validPassword,
        ),
        isTrue,
      );

      // The session that existed only to set a password is gone, so the router
      // resolves to Sign In rather than keeping the user logged in.
      expect(h.gateway.recoveriesEnded, 1);
      expect(h.gateway.isPasswordRecoveryActive, isFalse);
      expect(h.session.uid, isNull);
      expect(h.vm.holdsRoute, isFalse);
      expect(
        resolveAuthRedirect(AuthStatus.unauthenticated, '/reset-password'),
        '/sign-in',
      );
    });

    test('cancelling signs the recovery session out', () async {
      final h = harness();
      await h.emitRecovery();

      await h.vm.dismiss();

      expect(h.gateway.recoveriesEnded, 1);
      expect(h.gateway.isPasswordRecoveryActive, isFalse);
      expect(h.session.uid, isNull, reason: 'no hidden session may remain');
      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
      expect(
        resolveAuthRedirect(AuthStatus.unauthenticated, '/reset-password'),
        '/sign-in',
      );
    });

    test('cancelling a dead link needs no sign-out', () async {
      final h = harness();
      await h.deliver(_recoveryErrorCallback);
      expect(h.vm.holdsRoute, isTrue);

      await h.vm.dismiss();

      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
    });

    test('recovery state cannot leak into a later normal login', () async {
      final h = harness();
      await h.emitRecovery();
      await h.vm.dismiss();

      // A normal login afterwards is an ordinary session: no gate, no reset
      // screen, and the router behaves exactly as it always did.
      h.session.uid = _uid;
      expect(h.gateway.isPasswordRecoveryActive, isFalse);
      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
      expect(resolveAuthRedirect(AuthStatus.authenticated, '/home'), isNull);
      expect(
          resolveAuthRedirect(AuthStatus.authenticated, '/sign-in'), '/home');
    });

    test('dismissing releases the route and clears the marker', () async {
      final h = harness();
      await h.emitRecovery();
      await h.vm.submitNewPassword(
        newPassword: _validPassword,
        confirmPassword: _validPassword,
      );

      await h.vm.dismiss();
      expect(h.vm.phase, PasswordRecoveryPhase.none);
      expect(h.vm.holdsRoute, isFalse);
      expect(h.vm.recoveryUid, isNull);
    });
  });

  group('Router authority', () {
    test('an active recovery forces the reset screen from anywhere', () {
      for (final path in const ['/home', '/profile', '/welcome', '/sign-in']) {
        expect(
          resolveAuthRedirect(
            AuthStatus.authenticated,
            path,
            passwordRecoveryActive: true,
          ),
          '/reset-password',
          reason: path,
        );
      }
    });

    test('the reset screen is left alone while recovery is active', () {
      expect(
        resolveAuthRedirect(
          AuthStatus.authenticated,
          '/reset-password',
          passwordRecoveryActive: true,
        ),
        isNull,
      );
    });

    test('the reset screen cannot be opened by ordinary navigation', () {
      expect(
        resolveAuthRedirect(AuthStatus.authenticated, '/reset-password'),
        '/home',
      );
      // Sign In, not Welcome: a finished or cancelled recovery leaves a user
      // whose next step is to use the password they just set.
      expect(
        resolveAuthRedirect(AuthStatus.unauthenticated, '/reset-password'),
        '/sign-in',
      );
    });

    test('the recovery gate outranks the bootstrap gate', () {
      // Recovery is known before bootstrap resolves - it is restored from the
      // persisted marker - so deferring it to bootstrap is what allowed Home to
      // appear for a frame on a real device.
      expect(
        resolveAuthRedirect(
          AuthStatus.unknown,
          '/home',
          passwordRecoveryActive: true,
        ),
        '/reset-password',
      );
      expect(
        resolveAuthRedirect(
          AuthStatus.unknown,
          '/',
          passwordRecoveryActive: true,
        ),
        '/reset-password',
      );
      // Without recovery the bootstrap gate behaves exactly as before.
      expect(resolveAuthRedirect(AuthStatus.unknown, '/home'), '/');
      expect(resolveAuthRedirect(AuthStatus.unknown, '/'), isNull);
    });

    test('every ordinary authenticated route is closed during recovery', () {
      for (final path in const [
        '/home',
        '/profile',
        '/edit-profile',
        '/search',
        '/favorites',
        '/notifications',
        '/subscription',
        '/toolkit-list',
      ]) {
        expect(
          resolveAuthRedirect(
            AuthStatus.authenticated,
            path,
            passwordRecoveryActive: true,
          ),
          '/reset-password',
          reason: path,
        );
      }
    });

    test('a recovery session never resolves to Home at any bootstrap state',
        () {
      for (final status in AuthStatus.values) {
        expect(
          resolveAuthRedirect(
            status,
            '/home',
            passwordRecoveryActive: true,
          ),
          isNot('/home'),
          reason: status.name,
        );
      }
    });

    test('recovery does not disturb any other routing decision', () {
      expect(
          resolveAuthRedirect(AuthStatus.authenticated, '/sign-in'), '/home');
      expect(
        resolveAuthRedirect(AuthStatus.unauthenticated, '/home'),
        '/welcome',
      );
      expect(
        resolveAuthRedirect(AuthStatus.authenticated, '/email-verification'),
        isNull,
      );
      expect(
        resolveAuthRedirect(AuthStatus.authenticated, '/edit-profile'),
        isNull,
      );
    });
  });
}
