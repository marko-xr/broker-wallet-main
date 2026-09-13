import 'dart:async';

import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/auth_callback_coordinator.dart';
import 'package:flutter/widgets.dart';

typedef EmailChangeTimerFactory = Timer Function(
  Duration period,
  void Function(Timer timer) callback,
);

/// Presentation state for Supabase's authenticated email-change flow.
///
/// Nothing is persisted locally: confirmed and pending addresses are derived
/// from the current Supabase User. The backend remains authoritative for
/// confirmation, expiry, rate limiting, and whether one or both mailboxes must
/// approve the change.
///
/// Secure Email Change makes the *callback* ambiguous — the first of the two
/// confirmations returns an informational redirect that carries no session — so
/// this view model never reads an outcome out of the link itself. A callback is
/// only a trigger to re-read the authoritative Supabase user; what that read
/// returns is the single source of truth for what the user is told.
class EmailChangeViewModel extends ChangeNotifier with WidgetsBindingObserver {
  EmailChangeViewModel({
    required EmailChangeCapability? gateway,
    this.resendCooldown = const Duration(seconds: 60),
    EmailChangeTimerFactory? timerFactory,
    DateTime Function()? now,
    Stream<AuthCallbackEvent>? callbacks,
    bool observeLifecycle = true,
  })  : _gateway = gateway,
        _timerFactory = timerFactory ?? Timer.periodic,
        _now = now ?? DateTime.now,
        _observeLifecycle = observeLifecycle {
    _applyState(gateway?.currentEmailChange);
    if (gateway == null) return;

    _subscription = gateway.emailChangeChanges.listen(
      _applyState,
      onError: (_) {},
    );
    _callbackSubscription =
        (callbacks ?? AuthCallbackCoordinator.instance.events).listen(
      _handleAuthCallback,
      onError: (_) {},
    );
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    unawaited(_refresh());
  }

  final EmailChangeCapability? _gateway;
  final EmailChangeTimerFactory _timerFactory;
  final DateTime Function() _now;
  final bool _observeLifecycle;
  final Duration resendCooldown;

  /// Guards against re-reading the user on every incidental resume.
  static const Duration _resumeRefreshInterval = Duration(seconds: 3);

  StreamSubscription<EmailChangeState?>? _subscription;
  StreamSubscription<AuthCallbackEvent>? _callbackSubscription;
  Timer? _resendTimer;
  EmailChangeState? _state;
  bool _requesting = false;
  bool _resending = false;
  bool _checkingStatus = false;
  bool _justCompleted = false;
  int _resendSecondsRemaining = 0;
  String? _errorKey;
  String? _noticeKey;
  DateTime? _lastResumeRefresh;
  bool _disposed = false;

  EmailChangeState? get state => _state;
  bool get isAvailable => _gateway != null;
  bool get isPending => _state?.isPending ?? false;
  String get confirmedEmail => _state?.confirmedEmail ?? '';
  String? get pendingEmail => _state?.pendingEmail;
  bool get isRequesting => _requesting;
  bool get isResending => _resending;
  bool get isCheckingStatus => _checkingStatus;
  bool get isBusy => _requesting || _resending || _checkingStatus;
  int get resendSecondsRemaining => _resendSecondsRemaining;
  bool get canResend => isPending && !isBusy && _resendSecondsRemaining == 0;
  String? get errorKey => _errorKey;
  String? get noticeKey => _noticeKey;

  /// True for one read cycle after a confirmed change completed, so the pending
  /// sheet can close itself instead of showing stale pending copy.
  bool get justCompleted => _justCompleted;

  void acknowledgeCompletion() {
    if (!_justCompleted) return;
    _justCompleted = false;
    _notify();
  }

  Future<void> _refresh() async {
    final gateway = _gateway;
    if (gateway == null) return;
    try {
      final refreshed = await gateway.refreshEmailChange();
      _applyState(refreshed);
    } catch (_) {
      // A route-open refresh is best effort. The locally restored Supabase
      // session remains the safe source until the shared auth stream updates.
    }
  }

  // ---------------------------------------------------------------------------
  // Deep-link callbacks
  // ---------------------------------------------------------------------------

  /// Reacts to an auth callback Supabase declined to exchange.
  ///
  /// Session-bearing callbacks are absent here by construction: Supabase
  /// exchanges those itself and the resulting user reaches this view model
  /// through the shared auth-event pipeline, not through this path.
  void _handleAuthCallback(AuthCallbackEvent event) {
    if (!isAvailable) return;
    // Password recovery has its own callback address. A callback that arrived
    // there is never this flow's, so an expired recovery link can no longer
    // surface as an email-change error.
    if (event.isPasswordRecovery) return;

    switch (event.kind) {
      case AuthCallbackKind.session:
        return;
      case AuthCallbackKind.error:
        // The link failed. Report it from the code alone — the provider's
        // `error_description` is never surfaced — then still re-read the
        // authoritative state, because a *different* link may have succeeded.
        _errorKey = emailChangeErrorKey(
          authFailureCodeForCallbackError(event.error, event.errorCode),
        );
        _noticeKey = null;
        _notify();
        unawaited(_reconcileAfterCallback(announcePending: false));
      case AuthCallbackKind.informational:
        unawaited(_reconcileAfterCallback(announcePending: true));
      case AuthCallbackKind.unknown:
        unawaited(_reconcileAfterCallback(announcePending: false));
    }
  }

  /// Re-reads Supabase and describes the result truthfully.
  ///
  /// [announcePending] is set only for an informational callback, which is the
  /// redirect Secure Email Change uses to acknowledge one of its two
  /// confirmations. Even then the wording is chosen from the *authoritative*
  /// state that comes back, never from the link.
  Future<void> _reconcileAfterCallback({required bool announcePending}) async {
    final gateway = _gateway;
    if (gateway == null) return;

    final beforeUid = _state?.ownerUid ?? gateway.currentEmailChange?.ownerUid;
    final wasPending = isPending;

    // An error the callback itself reported is the actionable one — the user
    // tapped a dead link. If the follow-up read then also fails, replacing that
    // with a vaguer "try again" would hide the cause, so the specific message
    // wins.
    final callbackError = _errorKey;

    final EmailChangeState? refreshed;
    try {
      refreshed = await gateway.refreshEmailChange();
    } on AuthFailure catch (failure) {
      if (callbackError == null) _setFailure(failure.code);
      return;
    } catch (_) {
      if (callbackError == null) _setFailure(AuthFailureCode.unknown);
      return;
    }

    // A callback that resolves against a different account must never be
    // applied to the account now signed in.
    if (refreshed != null &&
        beforeUid != null &&
        refreshed.ownerUid != beforeUid) {
      return;
    }

    _applyState(refreshed);

    if (wasPending && !isPending) {
      _completeSuccessfully();
      return;
    }
    if (isPending && _errorKey == null) {
      _noticeKey = announcePending
          ? 'emailChangePartiallyConfirmed'
          : 'emailChangeStillPending';
      _notify();
    }
  }

  void _completeSuccessfully() {
    _errorKey = null;
    _noticeKey = 'emailChangeCompleted';
    _justCompleted = true;
    _stopCooldown();
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Returning from the mail app is the common case, and the first Secure
    // Email Change confirmation produces no session event at all — so a resume
    // has to re-read state. It is throttled, and only runs while something is
    // actually pending, so an ordinary resume costs nothing.
    if (!isPending || isBusy) return;
    final last = _lastResumeRefresh;
    final now = _now();
    if (last != null && now.difference(last) < _resumeRefreshInterval) return;
    _lastResumeRefresh = now;
    unawaited(_reconcileAfterCallback(announcePending: false));
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Explicit "Check status" action for the pending sheet.
  Future<bool> checkStatus() async {
    final gateway = _gateway;
    if (gateway == null || _checkingStatus) return false;
    final ownerUid = _state?.ownerUid ?? gateway.currentEmailChange?.ownerUid;

    _errorKey = null;
    _noticeKey = null;
    _checkingStatus = true;
    _notify();
    try {
      final refreshed = await gateway.refreshEmailChange();
      if (refreshed != null &&
          ownerUid != null &&
          refreshed.ownerUid != ownerUid) {
        _setFailure(AuthFailureCode.accountChanged);
        return false;
      }
      final wasPending = isPending;
      _applyState(refreshed);
      if (wasPending && !isPending) {
        _completeSuccessfully();
        return true;
      }
      _noticeKey = isPending ? 'emailChangeStillPending' : null;
      return isPending;
    } on AuthFailure catch (failure) {
      _setFailure(failure.code);
      return false;
    } catch (_) {
      _setFailure(AuthFailureCode.unknown);
      return false;
    } finally {
      _checkingStatus = false;
      _notify();
    }
  }

  Future<bool> requestEmailChange(String value) async {
    if (isBusy) return false;
    _errorKey = null;
    _noticeKey = null;

    final gateway = _gateway;
    final current = _state ?? gateway?.currentEmailChange;
    if (gateway == null) {
      _setFailure(AuthFailureCode.providerUnavailable);
      return false;
    }
    if (current == null || current.ownerUid.isEmpty) {
      _setFailure(AuthFailureCode.sessionExpired);
      return false;
    }

    final normalizedEmail = value.trim().toLowerCase();
    if (!EmailValidator.isValidFormat(normalizedEmail)) {
      _setFailure(AuthFailureCode.invalidEmail);
      return false;
    }
    if (normalizedEmail == current.confirmedEmail.trim().toLowerCase()) {
      _setFailure(AuthFailureCode.sameEmail);
      return false;
    }

    final ownerUid = current.ownerUid;
    _requesting = true;
    _notify();
    try {
      final result = await gateway.requestEmailChange(normalizedEmail);
      final live = gateway.currentEmailChange;
      if (result.ownerUid != ownerUid ||
          live == null ||
          live.ownerUid != ownerUid) {
        _setFailure(AuthFailureCode.accountChanged);
        return false;
      }

      _applyState(result);
      _noticeKey =
          result.isPending ? 'emailChangeRequestSent' : 'emailChangeCompleted';
      if (result.isPending) {
        _startCooldown(resendCooldown.inSeconds);
      }
      return true;
    } on AuthFailure catch (failure) {
      _setFailure(failure.code);
      return false;
    } catch (_) {
      _setFailure(AuthFailureCode.unknown);
      return false;
    } finally {
      _requesting = false;
      _notify();
    }
  }

  Future<bool> resendEmailChange() async {
    if (!canResend) return false;
    final gateway = _gateway;
    final ownerUid = _state?.ownerUid;
    if (gateway == null || ownerUid == null) {
      _setFailure(AuthFailureCode.sessionExpired);
      return false;
    }

    _errorKey = null;
    _noticeKey = null;
    _resending = true;
    _notify();
    try {
      final result = await gateway.resendEmailChange();
      final live = gateway.currentEmailChange;
      if (result.ownerUid != ownerUid ||
          live == null ||
          live.ownerUid != ownerUid) {
        _setFailure(AuthFailureCode.accountChanged);
        return false;
      }
      _applyState(result);
      _noticeKey = 'emailChangeResent';
      _startCooldown(resendCooldown.inSeconds);
      return true;
    } on AuthFailure catch (failure) {
      _setFailure(failure.code);
      if (failure.code == AuthFailureCode.tooManyRequests) {
        _startCooldown(resendCooldown.inSeconds);
      }
      return false;
    } catch (_) {
      _setFailure(AuthFailureCode.unknown);
      return false;
    } finally {
      _resending = false;
      _notify();
    }
  }

  void clearMessages() {
    if (_errorKey == null && _noticeKey == null) return;
    _errorKey = null;
    _noticeKey = null;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // State plumbing
  // ---------------------------------------------------------------------------

  void _applyState(EmailChangeState? next) {
    final previous = _state;
    _state = next;
    final pendingChanged = previous?.ownerUid != next?.ownerUid ||
        previous?.pendingEmail != next?.pendingEmail ||
        previous?.requestedAt != next?.requestedAt;
    if (pendingChanged) {
      _syncCooldown(next);
    }
    // Signing out, or switching account, must not leave another account's
    // pending copy on screen.
    if (previous != null && next?.ownerUid != previous.ownerUid) {
      _errorKey = null;
      _noticeKey = null;
      _justCompleted = false;
    }
    _notify();
  }

  void _syncCooldown(EmailChangeState? state) {
    if (state == null || !state.isPending) {
      _stopCooldown();
      return;
    }
    final requestedAt = state.requestedAt;
    if (requestedAt == null) return;
    final elapsed = _now().toUtc().difference(requestedAt.toUtc()).inSeconds;
    final remaining = resendCooldown.inSeconds - elapsed;
    if (remaining > 0) {
      _startCooldown(remaining);
    } else {
      _stopCooldown();
    }
  }

  void _startCooldown(int seconds) {
    _resendTimer?.cancel();
    _resendSecondsRemaining = seconds < 0 ? 0 : seconds;
    if (_resendSecondsRemaining == 0) return;
    _resendTimer = _timerFactory(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _resendSecondsRemaining -= 1;
      if (_resendSecondsRemaining <= 0) {
        _resendSecondsRemaining = 0;
        timer.cancel();
        _resendTimer = null;
      }
      _notify();
    });
  }

  void _stopCooldown() {
    _resendTimer?.cancel();
    _resendTimer = null;
    _resendSecondsRemaining = 0;
  }

  void _setFailure(AuthFailureCode code) {
    _noticeKey = null;
    _errorKey = emailChangeErrorKey(code);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observeLifecycle && _gateway != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _resendTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_callbackSubscription?.cancel());
    super.dispose();
  }
}

/// Maps an auth callback's error *codes* to a domain failure.
///
/// Only Supabase's `error` and `error_code` are consulted. The provider's
/// `error_description` never participates, so no backend prose can influence
/// what the user is shown.
AuthFailureCode authFailureCodeForCallbackError(
  String? error,
  String? errorCode,
) {
  switch (errorCode) {
    case 'otp_expired':
    case 'flow_state_expired':
    case 'flow_state_not_found':
      return AuthFailureCode.otpInvalidOrExpired;
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
    case 'too_many_requests':
      return AuthFailureCode.tooManyRequests;
    case 'email_exists':
    case 'user_already_exists':
      return AuthFailureCode.emailAlreadyInUse;
    case 'validation_failed':
    case 'email_address_invalid':
      return AuthFailureCode.invalidEmail;
    case 'session_not_found':
    case 'session_expired':
    case 'bad_jwt':
    case 'user_not_found':
      return AuthFailureCode.sessionExpired;
  }
  if (error == 'access_denied') {
    // GoTrue pairs `access_denied` with an expired or already-consumed link.
    return AuthFailureCode.otpInvalidOrExpired;
  }
  if (error == 'server_error' || error == 'temporarily_unavailable') {
    return AuthFailureCode.network;
  }
  return AuthFailureCode.unknown;
}

String emailChangeErrorKey(AuthFailureCode code) {
  switch (code) {
    case AuthFailureCode.invalidEmail:
      return 'emailChangeInvalidEmail';
    case AuthFailureCode.sameEmail:
      return 'emailSameAsCurrent';
    case AuthFailureCode.emailAlreadyInUse:
      return 'emailChangeAlreadyInUse';
    case AuthFailureCode.tooManyRequests:
      return 'emailChangeRateLimited';
    case AuthFailureCode.network:
      return 'emailChangeNetworkError';
    case AuthFailureCode.otpInvalidOrExpired:
      return 'emailChangeLinkExpired';
    case AuthFailureCode.sessionExpired:
      return 'emailChangeSessionExpired';
    case AuthFailureCode.accountChanged:
      return 'emailChangeAccountChanged';
    case AuthFailureCode.noPendingEmailChange:
      return 'emailChangeNoPending';
    case AuthFailureCode.providerUnavailable:
    case AuthFailureCode.operationNotAllowed:
      return 'emailChangeUnavailable';
    default:
      return 'emailChangeFailed';
  }
}
