import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

enum PhoneVerificationPhase {
  /// Nothing pending. Also the state a pending verification returns to when
  /// the session that started it ends.
  idle,

  /// Asking the backend to send a code.
  sending,

  /// A code was sent; waiting for the user to enter it.
  awaitingCode,

  /// Checking the entered code.
  verifying,

  /// The backend confirmed the number for this account.
  verified,
}

/// Creates the one-second ticker behind the resend countdown. Injectable so
/// tests can drive the countdown without real time passing.
typedef PeriodicTimerFactory = Timer Function(
  Duration period,
  void Function(Timer timer) onTick,
);

/// One phone-number verification for the signed-in account.
///
/// Owns only this flow's UI state: the number being verified, the phase, the
/// resend countdown and a localizable error. It never owns or asserts
/// verification itself — that is reported by Supabase and arrives through
/// [AuthViewModel] like every other change to the canonical user.
///
/// A pending verification belongs to the session that started it. If that
/// session ends or the account changes, the flow is abandoned at once, and a
/// result that arrives afterwards is discarded rather than applied.
class PhoneVerificationViewModel extends ChangeNotifier {
  PhoneVerificationViewModel({
    required AuthViewModel authViewModel,
    PhoneVerificationCapability? gateway,
    this.resendCooldown = const Duration(seconds: 60),
    PeriodicTimerFactory? timerFactory,
  })  : _auth = authViewModel,
        _gateway = gateway ?? authViewModel.phoneVerification,
        _timerFactory = timerFactory ?? Timer.periodic {
    _auth.addListener(_onAuthChanged);
  }

  /// Supabase Auth's default SMS OTP length. The existing `otpSentTo` copy in
  /// both locales already promises a 6-digit code.
  static const int codeLength = 6;

  /// Minimum wait before offering to **resend** a code.
  ///
  /// This is a resend cooldown and nothing else. It says nothing about whether
  /// the code already sent is still valid: OTP validity is decided solely by
  /// Supabase, which may accept a code long after this countdown ends. When
  /// it reaches zero the flow only re-enables Resend — it never marks the
  /// current code expired or blocks submitting it. An expired code is known
  /// only when Supabase rejects it.
  ///
  /// It is also user experience, not abuse protection. Supabase's own SMS rate
  /// limits and minimum resend interval are authoritative, and a rejection
  /// from them is reported honestly.
  final Duration resendCooldown;

  final AuthViewModel _auth;
  final PhoneVerificationCapability? _gateway;
  final PeriodicTimerFactory _timerFactory;

  PhoneVerificationPhase _phase = PhoneVerificationPhase.idle;
  String? _phoneE164;
  String? _ownerUid;
  String? _errorKey;
  bool _resending = false;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;
  bool _disposed = false;

  PhoneVerificationPhase get phase => _phase;

  /// The canonical number being verified.
  String? get phoneE164 => _phoneE164;

  /// An ARB key describing the last failure, or null. Never raw error text.
  String? get errorKey => _errorKey;

  bool get isResending => _resending;
  int get resendSecondsRemaining => _resendSecondsRemaining;

  /// Whether this backend can verify phone numbers at all.
  bool get isAvailable => _gateway != null;

  /// A server operation is in flight. Only one is ever allowed at a time.
  bool get isBusy =>
      _phase == PhoneVerificationPhase.sending ||
      _phase == PhoneVerificationPhase.verifying ||
      _resending;

  bool get canResend =>
      _phase == PhoneVerificationPhase.awaitingCode &&
      !_resending &&
      _resendSecondsRemaining == 0;

  /// Validates and normalizes [rawPhone], then asks the backend to send a
  /// code to it for the signed-in account. Returns whether a code was sent.
  ///
  /// Malformed numbers are rejected before any network call.
  Future<bool> sendCode(String rawPhone) async {
    if (isBusy || _phase == PhoneVerificationPhase.verified) return false;

    final gateway = _gateway;
    if (gateway == null) {
      _setError('phoneSmsUnavailable');
      return false;
    }

    final String phone;
    try {
      phone = PhoneNumberNormalizer.normalizeUaeMobile(rawPhone);
    } on PhoneValidationException {
      _setError('invalidUAEPhoneNumber');
      return false;
    }

    final uid = _auth.currentUserId;
    if (uid == null || _auth.status != AuthStatus.authenticated) {
      _setError('authSessionExpired');
      return false;
    }

    _ownerUid = uid;
    _phoneE164 = phone;
    _errorKey = null;
    _phase = PhoneVerificationPhase.sending;
    _notify();

    try {
      await gateway.requestPhoneVerification(phone);
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      _phase = PhoneVerificationPhase.idle;
      _errorKey = _sendErrorKeyFor(error);
      _notify();
      return false;
    }

    if (!_stillOwnedBy(uid)) return false;
    _phase = PhoneVerificationPhase.awaitingCode;
    _startCooldown();
    _notify();
    return true;
  }

  /// Requests a new code once the countdown has elapsed.
  Future<bool> resendCode() async {
    if (!canResend) return false;

    final uid = _ownerUid;
    final phone = _phoneE164;
    final gateway = _gateway;
    if (uid == null || phone == null || gateway == null) return false;
    if (!_stillOwnedBy(uid)) {
      _abandon('authSessionExpired');
      return false;
    }

    _resending = true;
    _errorKey = null;
    _notify();

    try {
      await gateway.resendPhoneVerification(phone);
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      _resending = false;
      _errorKey = _errorKeyFor(error);
      // Being told to slow down means waiting another full interval.
      if (error is AuthFailure && error.code == AuthFailureCode.tooManyRequests) {
        _startCooldown();
      }
      _notify();
      return false;
    }

    if (!_stillOwnedBy(uid)) return false;
    _resending = false;
    _startCooldown();
    _notify();
    return true;
  }

  /// Submits [rawCode]. Returns true only when the backend has confirmed the
  /// number for the account that started this flow.
  ///
  /// A second submission while one is in flight is ignored. On a recoverable
  /// failure the flow stays on the code step so the user can correct or
  /// re-request the code.
  Future<bool> verifyCode(String rawCode) async {
    if (_phase != PhoneVerificationPhase.awaitingCode || _resending) {
      return false;
    }

    final code = rawCode.trim();
    if (!RegExp('^[0-9]{$codeLength}\$').hasMatch(code)) {
      _setError('otpInvalid');
      return false;
    }

    final uid = _ownerUid;
    final phone = _phoneE164;
    final gateway = _gateway;
    if (uid == null || phone == null || gateway == null) return false;
    if (!_stillOwnedBy(uid)) {
      _abandon('authSessionExpired');
      return false;
    }

    _phase = PhoneVerificationPhase.verifying;
    _errorKey = null;
    _notify();

    final UserModel confirmed;
    try {
      confirmed = await gateway.confirmPhoneVerification(
        phoneE164: phone,
        code: code,
      );
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      if (error is AuthFailure &&
          error.code == AuthFailureCode.sessionExpired) {
        _abandon('authSessionExpired');
        return false;
      }
      _phase = PhoneVerificationPhase.awaitingCode;
      _errorKey = _errorKeyFor(error);
      _notify();
      return false;
    }

    // The confirmation must be for the account that asked for it, and that
    // account must still be the one signed in.
    if (!_stillOwnedBy(uid) || confirmed.uid != uid) {
      if (!_disposed) _abandon('authSessionExpired');
      return false;
    }

    _stopCooldown();
    _phase = PhoneVerificationPhase.verified;
    _notify();

    // Pull the profile row the database trigger has just updated, so every
    // screen shows the confirmed number without waiting for realtime. This is
    // presentation catch-up, not the source of the verified state.
    unawaited(_auth.syncUserFromRepository());
    return true;
  }

  /// The user dismissed the flow.
  void cancel() => _abandon(null);

  void _onAuthChanged() {
    final uid = _ownerUid;
    if (uid == null || _phase == PhoneVerificationPhase.verified) return;
    if (!_sessionMatches(uid)) {
      _abandon('authSessionExpired');
    }
  }

  bool _sessionMatches(String uid) =>
      _auth.currentUserId == uid && _auth.status == AuthStatus.authenticated;

  bool _stillOwnedBy(String uid) =>
      !_disposed && _ownerUid == uid && _sessionMatches(uid);

  void _abandon(String? errorKey) {
    _stopCooldown();
    _ownerUid = null;
    _phoneE164 = null;
    _resending = false;
    _phase = PhoneVerificationPhase.idle;
    _errorKey = errorKey;
    _notify();
  }

  void _setError(String key) {
    _errorKey = key;
    _notify();
  }

  /// Maps a failure to an ARB key. Raw text never leaves this method.
  static String _errorKeyFor(Object error) {
    if (error is! AuthFailure) return 'verificationFailed';
    switch (error.code) {
      case AuthFailureCode.invalidPhoneNumber:
        return 'invalidUAEPhoneNumber';
      case AuthFailureCode.otpInvalidOrExpired:
        return 'phoneCodeInvalidOrExpired';
      case AuthFailureCode.tooManyRequests:
        return 'authTooManyRequests';
      case AuthFailureCode.network:
        return 'authNetworkFailed';
      case AuthFailureCode.sessionExpired:
        return 'authSessionExpired';
      case AuthFailureCode.phoneAlreadyInUse:
        return 'authPhoneExists';
      case AuthFailureCode.smsUnavailable:
      case AuthFailureCode.providerUnavailable:
        return 'phoneSmsUnavailable';
      default:
        return 'verificationFailed';
    }
  }

  /// Starting a verification can be refused server-side for reasons that must
  /// not be disclosed — most importantly, the database guard that keeps two
  /// accounts from holding the same pending number reaches the client only as
  /// Supabase Auth's generic server error. An unexplained refusal at this
  /// step therefore gets a neutral "not right now" message rather than
  /// "try again", which would invite retries that keep failing.
  static String _sendErrorKeyFor(Object error) {
    final key = _errorKeyFor(error);
    return key == 'verificationFailed' ? 'phoneVerificationUnavailableNow' : key;
  }

  /// Every ARB key this view model can surface. Kept public so tests can
  /// assert each one exists in both locales.
  static const Set<String> surfacedErrorKeys = {
    'phoneVerificationUnavailableNow',
    'invalidUAEPhoneNumber',
    'phoneCodeInvalidOrExpired',
    'authTooManyRequests',
    'authNetworkFailed',
    'authSessionExpired',
    'authPhoneExists',
    'phoneSmsUnavailable',
    'verificationFailed',
    'otpInvalid',
  };

  void _startCooldown() {
    _resendTimer?.cancel();
    _resendSecondsRemaining = resendCooldown.inSeconds;
    if (_resendSecondsRemaining <= 0) {
      _resendSecondsRemaining = 0;
      return;
    }
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resendTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
