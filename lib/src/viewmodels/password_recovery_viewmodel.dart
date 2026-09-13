import 'dart:async';

import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/auth_callback_coordinator.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart'
    show authFailureCodeForCallbackError;
import 'package:flutter/foundation.dart';

/// Where a password recovery currently stands.
enum PasswordRecoveryPhase {
  /// No recovery is in progress. The router behaves exactly as before.
  none,

  /// Supabase exchanged a recovery link and the account may now set a new
  /// password. This is the only phase in which `/reset-password` accepts input.
  active,

  /// A recovery link came back dead - expired, already used, or otherwise
  /// refused. The screen explains it and offers a new link.
  linkFailed,

  /// The password was changed. Held briefly so the user sees the confirmation
  /// rather than being thrown back into the app mid-sentence.
  completed,
}

/// Owns password-recovery *context*.
///
/// Supabase gives a recovery link a real session, indistinguishable from an
/// ordinary sign-in once it exists. The one moment the difference is visible is
/// `AuthChangeEvent.passwordRecovery`, which the repository republishes as a
/// [PasswordRecoverySession]. This view model captures that moment and holds it
/// until the reset finishes, which is what makes `/reset-password` reachable
/// only through a real recovery and never by ordinary authenticated navigation.
///
/// It is not a second auth authority. It never creates, refreshes or
/// invalidates a session, never reads a token, and takes the account id from
/// the session Supabase built - never from the link. GoRouter remains the
/// navigation authority; this class only supplies one input to it.
///
/// Collision safety is structural rather than heuristic:
///
///  * a recovery callback carries a session, so Supabase exchanges it and
///    [AuthCallbackCoordinator] never sees it - it cannot be mistaken for the
///    Email Change callbacks, which are exactly the ones Supabase declined;
///  * signup verification and the final Email Change confirmation are
///    session-bearing too, but GoTrue emits `signedIn`/`userUpdated` for them,
///    never `passwordRecovery`, so neither can start a recovery here;
///  * a recovery link that *failed* is never exchanged and carries no event at
///    all, so it is recognised by the address it arrived at. Supabase is told
///    to send recovery links to their own callback and nothing else is, so no
///    timing and no provider-supplied `type` takes part in that decision.
class PasswordRecoveryViewModel extends ChangeNotifier {
  PasswordRecoveryViewModel({
    required PasswordCapability? gateway,
    required AuthRepository? authRepository,
    Stream<AuthCallbackEvent>? callbacks,
  })  : _gateway = gateway,
        _authRepository = authRepository {
    if (gateway == null) return;
    _recoverySubscription = gateway.passwordRecoverySessions.listen(
      _handleRecoverySession,
      onError: (Object _) {},
    );
    _callbackSubscription =
        (callbacks ?? AuthCallbackCoordinator.instance.events).listen(
      _handleAuthCallback,
      onError: (Object _) {},
    );
  }

  final PasswordCapability? _gateway;
  final AuthRepository? _authRepository;

  StreamSubscription<PasswordRecoverySession>? _recoverySubscription;
  StreamSubscription<AuthCallbackEvent>? _callbackSubscription;

  PasswordRecoveryPhase _phase = PasswordRecoveryPhase.none;
  String? _recoveryUid;
  String? _errorKey;
  bool _submitting = false;
  bool _disposed = false;

  /// The phase the screen should render.
  ///
  /// Falls back to the repository when this instance never saw the starting
  /// event. That happens on a cold start: the process died holding a recovery
  /// session, and on the next launch the session is restored with
  /// `initialSession` and no `passwordRecovery` event to observe. The
  /// repository still knows, from its persisted owner id, so the screen is
  /// driven from the same single source the router uses.
  PasswordRecoveryPhase get phase {
    if (_phase == PasswordRecoveryPhase.none &&
        (_gateway?.isPasswordRecoveryActive ?? false)) {
      return PasswordRecoveryPhase.active;
    }
    return _phase;
  }

  /// The account the recovery session belongs to. Authoritative: it came from
  /// the session Supabase created, not from the link, and on a restored
  /// recovery it comes from the live session the repository has vouched for.
  String? get recoveryUid {
    final observed = _recoveryUid;
    if (observed != null) return observed;
    if (_gateway?.isPasswordRecoveryActive ?? false) {
      return _authRepository?.currentUserId;
    }
    return null;
  }

  String? get errorKey => _errorKey;
  bool get isSubmitting => _submitting;
  bool get isAvailable => _gateway != null;

  /// True while this class alone must hold `/reset-password`.
  ///
  /// Only the session-less phases count. A live recovery session is answered
  /// by `AuthViewModel.isPasswordRecoveryActive`, which is published atomically
  /// with the session; a completed reset deliberately releases the route so the
  /// router can send the user to Sign In.
  bool get holdsRoute => phase == PasswordRecoveryPhase.linkFailed;

  /// Requirements [password] has not met yet, for the on-screen checklist.
  Set<PasswordRequirement> unmetRequirements(String password) =>
      PasswordPolicy.unmetRequirements(password);

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// A recovery session arrived.
  ///
  /// Idempotent by account: the OS can deliver the same intent twice, and a
  /// second event for the same account must not restart the flow or wipe what
  /// the user has already typed. A recovery for a *different* account does
  /// replace the state, because the session itself has already changed hands
  /// and continuing to offer the previous account a reset would be wrong.
  void _handleRecoverySession(PasswordRecoverySession session) {
    // A recovery that arrives after this one completed is the same link being
    // opened twice. The confirmation stays on screen.
    if (_phase == PasswordRecoveryPhase.completed) return;
    if (_phase == PasswordRecoveryPhase.active &&
        _recoveryUid == session.ownerUid) {
      return;
    }

    _recoveryUid = session.ownerUid;
    _phase = PasswordRecoveryPhase.active;
    _errorKey = null;
    _notify();
  }

  /// A callback Supabase declined to exchange.
  ///
  /// Only an *error* callback can belong to a dead recovery link; a
  /// session-bearing one never reaches here at all. Ownership is then decided
  /// by one deterministic question, did it arrive at the password-recovery
  /// address, so a callback at the general auth address is never claimed here,
  /// whatever it carries and whenever it arrives.
  void _handleAuthCallback(AuthCallbackEvent event) {
    if (!isAvailable) return;
    if (event.kind != AuthCallbackKind.error) return;
    if (!event.isPasswordRecovery) return;
    // A reset that already succeeded is not reopened by a late duplicate link.
    if (_phase == PasswordRecoveryPhase.completed) return;

    _failLink(event);
  }

  void _failLink(AuthCallbackEvent event) {
    _phase = PasswordRecoveryPhase.linkFailed;
    _recoveryUid = null;
    _errorKey = changePasswordErrorKey(
      authFailureCodeForCallbackError(event.error, event.errorCode),
    );
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Sets the new password for the recovery session.
  ///
  /// Refused unless a recovery is genuinely active *and* the live session still
  /// belongs to the account the recovery started on, so a late result can never
  /// land on another account.
  Future<bool> submitNewPassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (_submitting) return false;

    final gateway = _gateway;
    if (gateway == null || phase != PasswordRecoveryPhase.active) {
      _fail('passwordChangeSessionExpired');
      return false;
    }

    final validation = PasswordPolicy.validatePair(
      password: newPassword,
      confirmation: confirmPassword,
    );
    if (!validation.isValid) {
      _fail(validation.messageKey!);
      return false;
    }

    final ownerUid = recoveryUid;
    if (ownerUid == null || _authRepository?.currentUserId != ownerUid) {
      _fail(changePasswordErrorKey(AuthFailureCode.accountChanged));
      return false;
    }

    _errorKey = null;
    _submitting = true;
    _notify();
    try {
      // No current password: the recovery session is the proof of ownership,
      // and the user reached this screen precisely because they have none.
      await gateway.changePassword(newPassword: newPassword);
      if (_authRepository?.currentUserId != ownerUid) {
        _fail(changePasswordErrorKey(AuthFailureCode.accountChanged));
        return false;
      }
      // The recovery session existed only to get here. It is signed out rather
      // than kept, so the new password is proved by using it: the user lands on
      // Sign In, not on Home with a session they never authenticated for.
      _phase = PasswordRecoveryPhase.completed;
      _recoveryUid = null;
      await gateway.endPasswordRecovery();
      return true;
    } on AuthFailure catch (failure) {
      _fail(changePasswordErrorKey(failure.code));
      return false;
    } catch (_) {
      _fail(changePasswordErrorKey(AuthFailureCode.unknown));
      return false;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  /// Cancels the recovery and releases the route.
  ///
  /// Cancelling signs the recovery session out. Leaving it alive would be the
  /// same defect as routing to Home: a session that exists only to set a
  /// password must never become an ordinary logged-in session. GoRouter then
  /// resolves the destination from the authoritative session, which is Sign In.
  Future<void> dismiss() async {
    final wasIdle = _phase == PasswordRecoveryPhase.none &&
        !(_gateway?.isPasswordRecoveryActive ?? false);
    _phase = PasswordRecoveryPhase.none;
    _recoveryUid = null;
    _errorKey = null;
    _notify();
    if (wasIdle) return;
    await _gateway?.endPasswordRecovery();
    _notify();
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    _notify();
  }

  void _fail(String key) {
    _errorKey = key;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_recoverySubscription?.cancel());
    unawaited(_callbackSubscription?.cancel());
    super.dispose();
  }
}
