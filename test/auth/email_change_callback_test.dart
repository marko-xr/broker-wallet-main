import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/auth_callback_coordinator.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';
const _oldEmail = 'old@example.test';
const _newEmail = 'new@example.test';

/// The three redirects Secure Email Change can produce, exactly as GoTrue
/// builds them.
final _intermediateCallback = Uri.parse(
  'brokerwallet://auth/callback'
  '?message=Confirmation+link+accepted.+Please+proceed+to+confirm+link+sent+to+the+other+email',
);
final _expiredCallback = Uri.parse(
  'brokerwallet://auth/callback'
  '?error=access_denied&error_code=otp_expired'
  '&error_description=Email+link+is+invalid+or+has+expired',
);
final _sessionCallback =
    Uri.parse('brokerwallet://auth/callback?code=pkce-auth-code');

/// An expired *password-recovery* link. Same parameters as [_expiredCallback],
/// different address. Email Change must leave it alone.
final _expiredRecoveryCallback = Uri.parse(
  'brokerwallet://auth/reset-password'
  '?error=access_denied&error_code=otp_expired'
  '&error_description=Email+link+is+invalid+or+has+expired',
);
final _implicitSessionCallback = Uri.parse(
  'brokerwallet://auth/callback#access_token=header.payload.sig&refresh_token=r'
  '&expires_in=3600&token_type=bearer',
);

EmailChangeState _pending({String uid = _uid}) => EmailChangeState(
      ownerUid: uid,
      confirmedEmail: _oldEmail,
      pendingEmail: _newEmail,
      requestedAt: DateTime.now().toUtc(),
    );

EmailChangeState _settled({String uid = _uid, String email = _newEmail}) =>
    EmailChangeState(ownerUid: uid, confirmedEmail: email);

class _Gateway implements EmailChangeCapability {
  _Gateway(this._state);

  final StreamController<EmailChangeState?> _events =
      StreamController<EmailChangeState?>.broadcast();
  EmailChangeState? _state;

  /// What the next authoritative read returns.
  EmailChangeState? refreshResult;
  Object? refreshError;
  int refreshes = 0;

  @override
  EmailChangeState? get currentEmailChange => _state;

  @override
  Stream<EmailChangeState?> get emailChangeChanges => _events.stream;

  @override
  Future<EmailChangeState> requestEmailChange(String newEmail) async =>
      _state = _pending();

  @override
  Future<EmailChangeState> resendEmailChange() async => _state!;

  @override
  Future<EmailChangeState?> refreshEmailChange() async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    return _state = refreshResult ?? _state;
  }

  Future<void> close() => _events.close();
}

/// Builds a view model with no lifecycle observer and no real deep-link plugin.
EmailChangeViewModel _viewModel(
  _Gateway gateway,
  Stream<AuthCallbackEvent> callbacks,
) =>
    EmailChangeViewModel(
      gateway: gateway,
      callbacks: callbacks,
      observeLifecycle: false,
      timerFactory: (_, __) => Timer(const Duration(days: 1), () {}),
    );

void main() {
  group('Auth callback classification', () {
    test('a session-bearing callback stays with Supabase', () {
      expect(classifyAuthCallback(_sessionCallback), AuthCallbackKind.session);
      expect(
        classifyAuthCallback(_implicitSessionCallback),
        AuthCallbackKind.session,
        reason: 'implicit flow returns its parameters in the fragment',
      );
      expect(supabaseShouldExchangeAuthCallback(_sessionCallback), isTrue);
      expect(
        supabaseShouldExchangeAuthCallback(_implicitSessionCallback),
        isTrue,
        reason: 'signup verification and magic links must not regress',
      );
    });

    test('an error callback is never exchanged for a session', () {
      // This is the reproduced runtime defect: exchanging this URI is what
      // threw AuthException(otp_expired) out of getSessionFromUrl.
      expect(classifyAuthCallback(_expiredCallback), AuthCallbackKind.error);
      expect(supabaseShouldExchangeAuthCallback(_expiredCallback), isFalse);
    });

    test('an intermediate secure-email-change callback is not a session', () {
      expect(
        classifyAuthCallback(_intermediateCallback),
        AuthCallbackKind.informational,
      );
      expect(
          supabaseShouldExchangeAuthCallback(_intermediateCallback), isFalse);
    });

    test('only error codes are carried, never provider prose', () {
      final event = describeAuthCallback(_expiredCallback);
      expect(event.kind, AuthCallbackKind.error);
      expect(event.error, 'access_denied');
      expect(event.errorCode, 'otp_expired');
      expect(event.toString(), isNot(contains('invalid or has expired')));
      expect(
        describeAuthCallback(_intermediateCallback).toString(),
        isNot(contains('Confirmation link accepted')),
      );
    });
  });

  group('Auth callback coordinator', () {
    test('publishes callbacks Supabase declined and ignores the rest',
        () async {
      final links = StreamController<Uri>();
      final coordinator = AuthCallbackCoordinator.forTesting(links.stream);
      final seen = <AuthCallbackKind>[];
      coordinator.events.listen((e) => seen.add(e.kind));
      await coordinator.start();

      links
        ..add(_sessionCallback)
        ..add(_expiredCallback)
        ..add(_intermediateCallback);
      await pumpEventQueue();

      expect(seen, [AuthCallbackKind.error, AuthCallbackKind.informational]);
      await coordinator.dispose();
      await links.close();
    });

    test('duplicate delivery of the same URI is idempotent', () async {
      final links = StreamController<Uri>();
      final coordinator = AuthCallbackCoordinator.forTesting(links.stream);
      var count = 0;
      coordinator.events.listen((_) => count++);
      await coordinator.start();

      links
        ..add(_expiredCallback)
        ..add(_expiredCallback)
        ..add(_expiredCallback);
      await pumpEventQueue();

      expect(count, 1, reason: 'the OS can redeliver the launching intent');
      await coordinator.dispose();
      await links.close();
    });
  });

  group('Email change callback handling', () {
    test('an intermediate callback refreshes state and reports it truthfully',
        () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      // Still pending afterwards: one mailbox approved, one has not.
      gateway.refreshResult = _pending();
      callbacks
          .add(const AuthCallbackEvent(kind: AuthCallbackKind.informational));
      await pumpEventQueue();

      expect(vm.isPending, isTrue);
      expect(vm.noticeKey, 'emailChangePartiallyConfirmed');
      expect(vm.errorKey, isNull);
      expect(vm.confirmedEmail, _oldEmail,
          reason: 'the confirmed email stays canonical while pending');

      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('an expired-link callback maps to a safe localized key, no crash',
        () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = _pending();
      callbacks.add(describeAuthCallback(_expiredCallback));
      await pumpEventQueue();

      expect(vm.errorKey, 'emailChangeLinkExpired');
      expect(vm.isPending, isTrue,
          reason: 'a dead link does not cancel the pending change');
      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('no raw AuthException text can reach the UI', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshError = const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'secret-provider-text',
      );
      callbacks.add(describeAuthCallback(_expiredCallback));
      await pumpEventQueue();

      for (final key in [vm.errorKey, vm.noticeKey]) {
        expect(key ?? '', isNot(contains('secret-provider-text')));
        expect(key ?? '', isNot(contains('AuthException')));
      }
      expect(vm.errorKey, 'emailChangeLinkExpired');
      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('a final confirmation clears pending and reports success once',
        () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();
      expect(vm.isPending, isTrue);

      gateway.refreshResult = _settled();
      callbacks.add(const AuthCallbackEvent(kind: AuthCallbackKind.unknown));
      await pumpEventQueue();

      expect(vm.isPending, isFalse);
      expect(vm.confirmedEmail, _newEmail);
      expect(vm.noticeKey, 'emailChangeCompleted');
      expect(vm.justCompleted, isTrue);

      vm.acknowledgeCompletion();
      expect(vm.justCompleted, isFalse,
          reason: 'success feedback is shown exactly once');

      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('a session callback is ignored here — Supabase owns it', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();
      final before = gateway.refreshes;

      callbacks.add(const AuthCallbackEvent(kind: AuthCallbackKind.session));
      await pumpEventQueue();

      expect(gateway.refreshes, before);
      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('a callback resolving to another account is never applied', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = _settled(uid: _otherUid, email: 'other@x.test');
      callbacks
          .add(const AuthCallbackEvent(kind: AuthCallbackKind.informational));
      await pumpEventQueue();

      expect(vm.confirmedEmail, _oldEmail);
      expect(vm.isPending, isTrue);
      expect(vm.noticeKey, isNot('emailChangeCompleted'));
      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('a callback after logout cannot resurrect pending state', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = null;
      gateway._state = null;
      callbacks
          .add(const AuthCallbackEvent(kind: AuthCallbackKind.informational));
      await pumpEventQueue();

      expect(vm.isPending, isFalse);
      expect(vm.pendingEmail, isNull);
      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });
  });

  group('Check status', () {
    test('refreshes authoritative state and completes cleanly', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = _settled();
      expect(await vm.checkStatus(), isTrue);
      expect(vm.isPending, isFalse);
      expect(vm.confirmedEmail, _newEmail);
      expect(vm.noticeKey, 'emailChangeCompleted');

      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('still pending gives neutral feedback, never a false success',
        () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = _pending();
      expect(await vm.checkStatus(), isTrue);
      expect(vm.isPending, isTrue);
      expect(vm.noticeKey, 'emailChangeStillPending');
      expect(vm.errorKey, isNull);

      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });

    test('an account switch during the check is rejected', () async {
      final gateway = _Gateway(_pending());
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      final vm = _viewModel(gateway, callbacks.stream);
      await pumpEventQueue();

      gateway.refreshResult = _settled(uid: _otherUid);
      expect(await vm.checkStatus(), isFalse);
      expect(vm.errorKey, 'emailChangeAccountChanged');

      vm.dispose();
      await callbacks.close();
      await gateway.close();
    });
  });

  group('Runtime-defect guards', () {
    test('every auth stream listener handles errors', () {
      // Supabase reports each AuthException its deep-link observer catches by
      // republishing it on onAuthStateChange. A listener without onError turns
      // that into an unhandled async error, which is how an expired email link
      // crashed the app.
      const sources = [
        'lib/src/repositories/supabase_auth_repository.dart',
        'lib/src/viewmodels/home_viewmodel.dart',
        'lib/src/services/notification_service.dart',
        'lib/src/views/Screens/home/favorites/favorites_service.dart',
        'lib/src/viewmodels/Signup-Login/auth_viewmodel.dart',
      ];
      for (final path in sources) {
        final source = File(path).readAsStringSync();
        final listens = 'authStateChanges'.allMatches(source).length;
        if (listens == 0) continue;
        expect(
          source,
          contains('onError'),
          reason: '$path subscribes to auth state without an error handler',
        );
      }
    });

    test('automatic URI detection is narrowed, not disabled', () {
      final bootstrap = File('lib/src/services/supabase_bootstrap_service.dart')
          .readAsStringSync();
      expect(bootstrap, contains('detectSessionInUriPredicate'));
      expect(
        bootstrap,
        isNot(contains('detectSessionInUri: false')),
        reason: 'signup verification relies on Supabase exchanging its link',
      );
    });

    test('the callback layer never logs or carries sensitive link data', () {
      final coordinator =
          File('lib/src/services/auth_callback_coordinator.dart')
              .readAsStringSync();
      for (final forbidden in ['print(', 'debugPrint', 'log(']) {
        expect(coordinator, isNot(contains(forbidden)), reason: forbidden);
      }
      // The parameter names may be *read* to classify a link, but no token and
      // no provider prose may be carried out of it.
      final event = describeAuthCallback(
        Uri.parse(
          'brokerwallet://auth/callback?error=access_denied'
          '&error_code=otp_expired&error_description=Email+link+is+invalid'
          '&token_hash=super-secret-hash',
        ),
      );
      expect(event.toString(), isNot(contains('super-secret-hash')));
      expect(event.toString(), isNot(contains('Email link is invalid')));
      expect(event.error, 'access_denied');
      expect(event.errorCode, 'otp_expired');
    });

    test('an expired password-recovery callback is left to password recovery',
        () async {
      // Before recovery had its own address this callback was
      // indistinguishable from an expired email-change link, so it surfaced
      // here as an email-change failure. It must now be ignored entirely.
      final gateway = _Gateway(_pending());
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = _viewModel(gateway, callbacks.stream);
      addTearDown(vm.dispose);
      await pumpEventQueue();

      final refreshesBefore = gateway.refreshes;
      callbacks.add(describeAuthCallback(_expiredRecoveryCallback));
      await pumpEventQueue();

      expect(vm.errorKey, isNull);
      expect(vm.noticeKey, isNull);
      expect(gateway.refreshes, refreshesBefore,
          reason: 'a callback at another flow address must not even trigger '
              'an authoritative re-read here');
      expect(vm.isPending, isTrue);
    });

    test('an expired email-change callback is still handled here', () async {
      // The other half of the same guarantee: narrowing ownership must not
      // stop Email Change from reporting its own dead link.
      final gateway = _Gateway(_pending());
      addTearDown(gateway.close);
      final callbacks = StreamController<AuthCallbackEvent>.broadcast();
      addTearDown(callbacks.close);
      final vm = _viewModel(gateway, callbacks.stream);
      addTearDown(vm.dispose);
      await pumpEventQueue();

      callbacks.add(describeAuthCallback(_expiredCallback));
      await pumpEventQueue();

      expect(vm.errorKey, 'emailChangeLinkExpired');
    });

    test('no fake server cancellation exists anywhere in the flow', () {
      for (final path in [
        'lib/src/repositories/auth_repository.dart',
        'lib/src/viewmodels/email_change_viewmodel.dart',
        'lib/src/Views/Widgets/email_change_pending_sheet.dart',
      ]) {
        expect(File(path).readAsStringSync(),
            isNot(contains('cancelEmailChange')));
      }
    });
  });
}
