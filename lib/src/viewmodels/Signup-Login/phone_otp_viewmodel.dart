import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';

class PhoneOtpViewModel extends ChangeNotifier {
  late PhoneOtpArgs _args;
  PhoneOtpArgs get args => _args;

  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsRemaining = 60;
  String? _errorMessage;

  Timer? _timer;
  bool _disposed = false;

  bool get isVerifying => _isVerifying;
  bool get isResending => _isResending;
  int get secondsRemaining => _secondsRemaining;
  String? get errorMessage => _errorMessage;

  void initialize(PhoneOtpArgs args) {
    _args = args;
    _startTimer(reset: true);

    // If we don't have a verification ID, we need to send the initial OTP
    // This handles cases where the OTP screen is reached directly
    if (_args.verificationId.isEmpty && _args.phoneNumber.isNotEmpty) {
      // Debug log suppressed: No verification ID provided, will send OTP on screen load
      // Don't send immediately - wait for screen to be built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendInitialOtp();
      });
    }
  }

  Future<void> _sendInitialOtp() async {
    try {
      // Debug log suppressed: Sending initial OTP to: ${_args.phoneNumber}
      await resendCode(null, isInitial: true);
    } catch (e) {
      // Debug log suppressed: Error sending initial OTP: $e
      _errorMessage = 'Failed to send verification code. Please try again.';
      if (!_disposed) notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      if (!_disposed) notifyListeners();
    }
  }

  void _startTimer({bool reset = false}) {
    _timer?.cancel();
    if (reset) {
      _secondsRemaining = 60;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _secondsRemaining = 0;
      } else {
        _secondsRemaining--;
      }
      if (!_disposed) notifyListeners();
    });
  }

  /// The existing "not available yet" message for this flow. Phone sign-in and
  /// sign-up are not enabled with Supabase, so this screen reports that instead
  /// of verifying anything.
  String _unavailableMessage(AppLocalizations loc) => loc.translate(
        _args.isSignup ? 'phoneSignUpUnavailable' : 'phoneSignInUnavailable',
      );

  Future<void> verifyCode(BuildContext context, String code) async {
    final loc = AppLocalizations.of(context);
    final trimmedCode = code.trim();

    if (trimmedCode.length != 6) {
      _errorMessage = loc.translate('otpInvalid');
      if (!_disposed) notifyListeners();
      return;
    }

    _isVerifying = true;
    _errorMessage = null;
    if (!_disposed) notifyListeners();

    final message = _unavailableMessage(loc);
    _errorMessage = message;
    _showToast(message, Colors.orange);
    _isVerifying = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> resendCode(BuildContext? context,
      {bool isInitial = false}) async {
    if (!isInitial && (_secondsRemaining > 0 || _isResending)) return;

    final loc = context != null ? AppLocalizations.of(context) : null;

    _isResending = true;
    _errorMessage = null;
    if (!_disposed) notifyListeners();

    final message = loc != null
        ? _unavailableMessage(loc)
        : 'Failed to send verification code. Please try again.';
    _errorMessage = message;
    if (context != null) {
      _showToast(message, Colors.orange);
    }
    _isResending = false;
    if (!_disposed) notifyListeners();
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
