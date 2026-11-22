import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/phone_verification_viewmodel.dart'
    show PeriodicTimerFactory;

/// What a verification attempt achieved. Anything but [none] means the account
/// is signed in **and** the app has granted it access.
enum PhoneOtpOutcome { none, signedIn, signedInToExistingAccount }

/// The phone code step of phone sign-in and phone sign-up.
///
/// Owns only this screen's state: the countdown, one verification at a time,
/// and a localizable error key. It never decides access. The repository
/// publishes the identity only after the session passed the Single Active
/// Device claim, and this view model reports success only once
/// [AuthViewModel] has actually become authenticated for that same account —
/// so nothing navigates to Home on a session the server did not accept.
class PhoneOtpViewModel extends ChangeNotifier {
  PhoneOtpViewModel({
    AuthViewModel? authViewModel,
    PhoneSignInCapability? gateway,
    bool? enabled,
    this.resendCooldown = const Duration(seconds: 60),
    this.accessTimeout = const Duration(seconds: 15),
    PeriodicTimerFactory? timerFactory,
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _gateway = gateway ?? authViewModel?.phoneSignIn,
        _enabled = enabled ?? SupabaseConfig.phoneAuthEnabled,
        _timerFactory = timerFactory ?? Timer.periodic,
        _clock = clock ?? DateTime.now;

  /// Supabase Auth's default SMS code length; the existing `otpSentTo` copy
  /// promises a 6-digit code.
  static const int codeLength = 6;

  /// Minimum wait before offering a resend. User experience only: Supabase's
  /// own limits are authoritative and their refusals are reported.
  final Duration resendCooldown;

  /// How long a verified sign-in may take to become an authenticated app
  /// identity before the attempt is reported as a session-check failure.
  final Duration accessTimeout;

  final AuthViewModel? _auth;
  final PhoneSignInCapability? _gateway;
  final bool _enabled;
  final PeriodicTimerFactory _timerFactory;
  final DateTime Function() _clock;

  PhoneOtpArgs _args = PhoneOtpArgs.empty();
  PhoneOtpArgs get args => _args;

  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsRemaining = 0;
  String? _errorKey;
  Timer? _timer;
  bool _disposed = false;
  bool _completed = false;

  /// A sign-up whose session is already established but whose name could not
  /// be saved yet. Verifying again retries only the name.
  String? _pendingNameUid;

  bool get isVerifying => _isVerifying;
  bool get isResending => _isResending;
  int get secondsRemaining => _secondsRemaining;

  /// An ARB key describing the last failure, or null. Never raw error text.
  String? get errorKey => _errorKey;

  /// Whether this build and backend can complete phone sign-in at all.
  bool get isAvailable => _enabled && _auth != null && _gateway != null;

  bool get canResend =>
      isAvailable &&
      _secondsRemaining == 0 &&
      !_isResending &&
      !_isVerifying &&
      !_completed &&
      _pendingNameUid == null;

  String get _unavailableKey =>
      _args.isSignup ? 'phoneSignUpUnavailable' : 'phoneSignInUnavailable';

  void initialize(PhoneOtpArgs args) {
    _args = args;
    final sentAt = args.codeSentAt;
    var remaining = sentAt == null
        ? resendCooldown
        : resendCooldown - _clock().difference(sentAt);
    if (remaining.isNegative) remaining = Duration.zero;
    if (remaining > resendCooldown) remaining = resendCooldown;
    _startCountdown(remaining);
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    _notify();
  }

  /// Verifies [rawCode]. Returns a signed-in outcome only once the account is
  /// signed in and authorized; on any failure the screen stays where it is.
  /// A second call while one is in flight is ignored.
  Future<PhoneOtpOutcome> verifyCode(String rawCode) async {
    if (_isVerifying || _isResending || _completed) return PhoneOtpOutcome.none;

    final auth = _auth;
    final gateway = _gateway;
    if (!isAvailable ||
        auth == null ||
        gateway == null ||
        _args.phoneNumber.isEmpty) {
      _setError(_unavailableKey);
      return PhoneOtpOutcome.none;
    }

    final code = rawCode.trim();
    if (_pendingNameUid == null &&
        !RegExp('^[0-9]{$codeLength}\$').hasMatch(code)) {
      _setError('otpInvalid');
      return PhoneOtpOutcome.none;
    }

    _isVerifying = true;
    _errorKey = null;
    _notify();

    try {
      var uid = _pendingNameUid;
      var existed = false;
      if (uid == null) {
        final result = await auth.verifyPhoneSignIn(
          phoneE164: _args.phoneNumber,
          code: code,
        );
        if (_disposed) return PhoneOtpOutcome.none;
        uid = result.user.uid;
        existed = result.accountExisted;
        if (!await _accessGranted(auth, uid)) {
          if (!_disposed) _errorKey = 'appSessionCheckFailed';
          return PhoneOtpOutcome.none;
        }
      } else if (!_signedInAs(auth, uid)) {
        _pendingNameUid = null;
        _errorKey = 'authSessionExpired';
        return PhoneOtpOutcome.none;
      }

      final name = _args.displayName?.trim() ?? '';
      if (_args.isSignup && !existed && name.isNotEmpty) {
        try {
          await gateway.completePhoneSignUpName(expectedUid: uid, name: name);
        } catch (_) {
          if (_disposed) return PhoneOtpOutcome.none;
          // The session stays; Verify retries only the name.
          _pendingNameUid = uid;
          _errorKey = 'profileSaveFailed';
          return PhoneOtpOutcome.none;
        }
        unawaited(auth.syncUserFromRepository());
      }

      if (_disposed) return PhoneOtpOutcome.none;
      if (!_signedInAs(auth, uid)) {
        _pendingNameUid = null;
        _errorKey = 'authSessionExpired';
        return PhoneOtpOutcome.none;
      }
      _pendingNameUid = null;
      _completed = true;
      _stopCountdown();
      return _args.isSignup && existed
          ? PhoneOtpOutcome.signedInToExistingAccount
          : PhoneOtpOutcome.signedIn;
    } on AuthFailure catch (failure) {
      if (!_disposed) {
        _errorKey = errorKeyFor(failure, isSignup: _args.isSignup);
      }
      return PhoneOtpOutcome.none;
    } catch (_) {
      if (!_disposed) _errorKey = 'verificationFailed';
      return PhoneOtpOutcome.none;
    } finally {
      _isVerifying = false;
      _notify();
    }
  }

  /// Requests a new code once the countdown has elapsed. A new code replaces
  /// the previous one on the server.
  Future<bool> resendCode() async {
    if (!canResend) return false;
    final gateway = _gateway!;

    _isResending = true;
    _errorKey = null;
    _notify();

    try {
      await gateway.requestPhoneSignInCode(
        phoneE164: _args.phoneNumber,
        createAccount: _args.isSignup,
      );
      if (_disposed) return false;
      _startCountdown(resendCooldown);
      return true;
    } on AuthFailure catch (failure) {
      if (_disposed) return false;
      _errorKey = errorKeyFor(failure, isSignup: _args.isSignup);
      // Being told to slow down means waiting another full interval.
      if (failure.code == AuthFailureCode.tooManyRequests) {
        _startCountdown(resendCooldown);
      }
      return false;
    } catch (_) {
      if (!_disposed) _errorKey = 'verificationFailed';
      return false;
    } finally {
      _isResending = false;
      _notify();
    }
  }

  /// Waits until [auth] reports [uid] as the authenticated account. A
  /// different account appearing, or the wait running out, is a refusal.
  Future<bool> _accessGranted(AuthViewModel auth, String uid) async {
    if (_signedInAs(auth, uid)) return true;
    final granted = Completer<bool>();
    void onChange() {
      if (granted.isCompleted) return;
      if (_signedInAs(auth, uid)) {
        granted.complete(true);
      } else if (auth.currentUserId != null && auth.currentUserId != uid) {
        granted.complete(false);
      }
    }

    auth.addListener(onChange);
    try {
      return await granted.future.timeout(
        accessTimeout,
        onTimeout: () => _signedInAs(auth, uid),
      );
    } finally {
      auth.removeListener(onChange);
    }
  }

  static bool _signedInAs(AuthViewModel auth, String uid) =>
      auth.currentUserId == uid && auth.status == AuthStatus.authenticated;

  /// Maps a failure to an ARB key. Raw text never leaves this method. Shared
  /// with the Login and Sign-up view models for the code request step.
  static String errorKeyFor(AuthFailure failure, {required bool isSignup}) {
    switch (failure.code) {
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
      case AuthFailureCode.appSessionUnavailable:
        return 'appSessionCheckFailed';
      case AuthFailureCode.smsUnavailable:
        return 'phoneSmsUnavailable';
      case AuthFailureCode.phoneNotRegistered:
        return 'phoneNotRegistered';
      case AuthFailureCode.phoneAuthNotAllowed:
      case AuthFailureCode.providerUnavailable:
        return isSignup ? 'phoneSignUpUnavailable' : 'phoneSignInUnavailable';
      case AuthFailureCode.captchaFailed:
        return 'authCaptchaFailed';
      case AuthFailureCode.userDisabled:
        return 'authUserDisabled';
      default:
        return 'verificationFailed';
    }
  }

  /// Every ARB key the phone sign-in flow can surface. Public so tests can
  /// assert each one exists in both locales.
  static const Set<String> surfacedKeys = {
    'invalidUAEPhoneNumber',
    'phoneCodeInvalidOrExpired',
    'authTooManyRequests',
    'authNetworkFailed',
    'authSessionExpired',
    'appSessionCheckFailed',
    'phoneSmsUnavailable',
    'phoneNotRegistered',
    'phoneSignUpUnavailable',
    'phoneSignInUnavailable',
    'authCaptchaFailed',
    'authUserDisabled',
    'verificationFailed',
    'otpInvalid',
    'profileSaveFailed',
    'phoneAccountExistsSignedIn',
    'otpResent',
    'nameRequired',
  };

  void _setError(String key) {
    _errorKey = key;
    _notify();
  }

  void _startCountdown(Duration duration) {
    _timer?.cancel();
    _timer = null;
    _secondsRemaining = (duration.inMilliseconds / 1000).ceil();
    if (_secondsRemaining <= 0) {
      _secondsRemaining = 0;
      return;
    }
    _timer = _timerFactory(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _secondsRemaining -= 1;
      if (_secondsRemaining <= 0) {
        _secondsRemaining = 0;
        timer.cancel();
        _timer = null;
      }
      _notify();
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
    _secondsRemaining = 0;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
