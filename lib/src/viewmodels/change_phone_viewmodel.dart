import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/phone_verification_viewmodel.dart'
    show PeriodicTimerFactory;

enum ChangePhonePhase {
  /// Nothing pending (also after the session that started it ended).
  idle,

  /// Asking the server to send the two codes.
  sending,

  /// Codes sent; waiting for the user to enter them.
  awaitingCodes,

  /// Checking the codes.
  verifying,

  /// The server changed the sign-in number.
  changed,
}

/// Changing a phone account's sign-in number (Model X).
///
/// Owns only this flow's UI state. Whether the number changed is decided by
/// the server (Worker + database grant + Auth Admin API) and arrives through
/// [PhoneNumberChangeCapability]; nothing here asserts it.
///
/// A pending change belongs to the session that started it. If that session
/// ends or the account changes, the flow is abandoned and a late result is
/// discarded.
class ChangePhoneViewModel extends ChangeNotifier {
  ChangePhoneViewModel({
    required AuthViewModel authViewModel,
    PhoneNumberChangeCapability? gateway,
    this.resendCooldown = const Duration(seconds: 60),
    PeriodicTimerFactory? timerFactory,
  })  : _auth = authViewModel,
        _gateway = gateway ?? authViewModel.phoneNumberChange,
        _timerFactory = timerFactory ?? Timer.periodic {
    _auth.addListener(_onAuthChanged);
  }

  /// Supabase's and the provider's codes are six digits here.
  static const int codeLength = 6;

  /// UX only; the servers' own limits are authoritative.
  final Duration resendCooldown;

  final AuthViewModel _auth;
  final PhoneNumberChangeCapability? _gateway;
  final PeriodicTimerFactory _timerFactory;

  ChangePhonePhase _phase = ChangePhonePhase.idle;
  String? _newPhone;
  String? _currentPhone;
  String? _ownerUid;
  String? _errorKey;
  bool _resending = false;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;
  bool _disposed = false;

  ChangePhonePhase get phase => _phase;
  String? get newPhoneE164 => _newPhone;

  /// The account's current sign-in number, for display only.
  String? get currentPhoneE164 => _currentPhone ?? _auth.signInPhoneE164;
  String? get errorKey => _errorKey;
  bool get isResending => _resending;
  int get resendSecondsRemaining => _resendSecondsRemaining;

  /// This account can change its sign-in number here (a phone account).
  bool get isAvailable => _gateway != null && _auth.signInPhoneE164 != null;

  /// The current-number code was accepted; only the new one is still needed.
  bool get currentNumberProven => _gateway?.currentNumberProven ?? false;

  bool get isBusy =>
      _phase == ChangePhonePhase.sending ||
      _phase == ChangePhonePhase.verifying ||
      _resending;

  bool get canResend =>
      _phase == ChangePhonePhase.awaitingCodes &&
      !_resending &&
      _resendSecondsRemaining == 0;

  /// Validates [rawPhone] and asks the server to send both codes.
  Future<bool> sendCodes(String rawPhone) async {
    if (isBusy || _phase == ChangePhonePhase.changed) return false;
    final gateway = _gateway;
    final current = _auth.signInPhoneE164;
    if (gateway == null || current == null) {
      _setError('phoneVerificationUnavailableNow');
      return false;
    }
    final String phone;
    try {
      phone = PhoneNumberNormalizer.normalizeUaeMobile(rawPhone);
    } on PhoneValidationException {
      _setError('invalidUAEPhoneNumber');
      return false;
    }
    if (phone == current) {
      _setError('changePhoneSameNumber');
      return false;
    }
    final uid = _auth.currentUserId;
    if (uid == null || _auth.status != AuthStatus.authenticated) {
      _setError('authSessionExpired');
      return false;
    }

    _ownerUid = uid;
    _newPhone = phone;
    _currentPhone = current;
    _errorKey = null;
    _phase = ChangePhonePhase.sending;
    _notify();
    try {
      await gateway.requestPhoneNumberChange(phone);
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      _phase = ChangePhonePhase.idle;
      _errorKey = _sendErrorKeyFor(error);
      _notify();
      return false;
    }
    if (!_stillOwnedBy(uid)) return false;
    _phase = ChangePhonePhase.awaitingCodes;
    _startCooldown();
    _notify();
    return true;
  }

  /// New codes for both numbers, once the countdown has elapsed. The server
  /// replaces the previous verification, so older codes stop working.
  Future<bool> resendCodes() async {
    if (!canResend) return false;
    final uid = _ownerUid;
    final phone = _newPhone;
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
      await gateway.requestPhoneNumberChange(phone);
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      _resending = false;
      _errorKey = _errorKeyFor(error);
      if (error is AuthFailure &&
          error.code == AuthFailureCode.tooManyRequests) {
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

  /// Submits the codes. [currentCode] is not needed once
  /// [currentNumberProven]. Returns true only when the server changed the
  /// number for the account that started this flow.
  Future<bool> verify({
    required String currentCode,
    required String newCode,
  }) async {
    if (_phase != ChangePhonePhase.awaitingCodes || _resending) return false;
    final needsCurrent = !currentNumberProven;
    final current = currentCode.trim();
    final fresh = newCode.trim();
    final pattern = RegExp('^[0-9]{$codeLength}\$');
    if ((needsCurrent && !pattern.hasMatch(current)) ||
        !pattern.hasMatch(fresh)) {
      _setError('otpInvalid');
      return false;
    }
    final uid = _ownerUid;
    final phone = _newPhone;
    final gateway = _gateway;
    if (uid == null || phone == null || gateway == null) return false;
    if (!_stillOwnedBy(uid)) {
      _abandon('authSessionExpired');
      return false;
    }

    _phase = ChangePhonePhase.verifying;
    _errorKey = null;
    _notify();
    final UserModel changed;
    try {
      changed = await gateway.confirmPhoneNumberChange(
        newPhoneE164: phone,
        newCode: fresh,
        currentCode: needsCurrent ? current : null,
      );
    } catch (error) {
      if (!_stillOwnedBy(uid)) return false;
      if (error is AuthFailure &&
          error.code == AuthFailureCode.sessionExpired) {
        _abandon('authSessionExpired');
        return false;
      }
      _phase = ChangePhonePhase.awaitingCodes;
      _errorKey = _errorKeyFor(error);
      _notify();
      return false;
    }
    if (!_stillOwnedBy(uid) || changed.uid != uid) {
      if (!_disposed) _abandon('authSessionExpired');
      return false;
    }
    _stopCooldown();
    _phase = ChangePhonePhase.changed;
    _notify();
    unawaited(_auth.syncUserFromRepository());
    return true;
  }

  void cancel() => _abandon(null);

  void _onAuthChanged() {
    final uid = _ownerUid;
    if (uid == null || _phase == ChangePhonePhase.changed) return;
    if (!_sessionMatches(uid)) _abandon('authSessionExpired');
  }

  bool _sessionMatches(String uid) =>
      _auth.currentUserId == uid && _auth.status == AuthStatus.authenticated;

  bool _stillOwnedBy(String uid) =>
      !_disposed && _ownerUid == uid && _sessionMatches(uid);

  void _abandon(String? errorKey) {
    _stopCooldown();
    _ownerUid = null;
    _newPhone = null;
    _resending = false;
    _phase = ChangePhonePhase.idle;
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
      case AuthFailureCode.invalidCurrentPassword:
        return 'changePhoneCurrentCodeInvalid';
      case AuthFailureCode.tooManyRequests:
        return 'authTooManyRequests';
      case AuthFailureCode.network:
        return 'authNetworkFailed';
      case AuthFailureCode.sessionExpired:
      case AuthFailureCode.accountChanged:
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

  static String _sendErrorKeyFor(Object error) {
    final key = _errorKeyFor(error);
    return key == 'verificationFailed'
        ? 'phoneVerificationUnavailableNow'
        : key;
  }

  /// Every ARB key this view model can surface.
  static const Set<String> surfacedErrorKeys = {
    'phoneVerificationUnavailableNow',
    'invalidUAEPhoneNumber',
    'changePhoneSameNumber',
    'phoneCodeInvalidOrExpired',
    'changePhoneCurrentCodeInvalid',
    'authTooManyRequests',
    'authNetworkFailed',
    'authSessionExpired',
    'authPhoneExists',
    'phoneSmsUnavailable',
    'verificationFailed',
    'otpInvalid',
  };

  void _startCooldown() {
    _stopCooldown();
    final seconds = resendCooldown.inSeconds;
    if (seconds <= 0) return;
    _resendSecondsRemaining = seconds;
    _resendTimer = _timerFactory(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _resendSecondsRemaining =
          _resendSecondsRemaining > 0 ? _resendSecondsRemaining - 1 : 0;
      if (_resendSecondsRemaining == 0) {
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
    _stopCooldown();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
