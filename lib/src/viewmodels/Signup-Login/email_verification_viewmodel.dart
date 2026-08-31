import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:broker_wallet/src/services/auth_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class EmailVerificationViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();

  // State variables
  bool _isLoading = false;
  bool _isCheckingVerification = false;
  bool _isResendingEmail = false;
  int _resendCooldownSeconds = 0;
  String? _errorMessage;
  String _email = '';

  // Timers
  Timer? _verificationCheckTimer;
  Timer? _resendCooldownTimer;

  // Getters
  bool get isLoading => _isLoading;
  bool get isCheckingVerification => _isCheckingVerification;
  bool get isResendingEmail => _isResendingEmail;
  int get resendCooldownSeconds => _resendCooldownSeconds;
  String? get errorMessage => _errorMessage;
  String get email => _email;
  bool get canResend => _resendCooldownSeconds == 0 && !_isResendingEmail;

  void initialize(String email) {
    _email = email;
    _startAutoVerificationCheck();
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _setCheckingVerification(bool checking) {
    _isCheckingVerification = checking;
    notifyListeners();
  }

  void _setResendingEmail(bool resending) {
    _isResendingEmail = resending;
    notifyListeners();
  }

  void _startAutoVerificationCheck() {
    // Check every 3 seconds for email verification
    _verificationCheckTimer?.cancel();
    _verificationCheckTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkEmailVerificationSilently();
    });
  }

  void _startResendCooldown() {
    _resendCooldownSeconds = 60; // 1 minute cooldown
    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        _resendCooldownSeconds = 0;
      } else {
        _resendCooldownSeconds--;
      }
      notifyListeners();
    });
  }

  Future<void> _checkEmailVerificationSilently() async {
    if (_isCheckingVerification) return;

    try {
      final user = await _authService.reloadAndGetUser();

      if (user?.emailVerified == true) {
        _verificationCheckTimer?.cancel();

        // Show success and navigate
        _showToast('Email verified successfully!', Colors.green);

        // Small delay to show the toast
        await Future.delayed(const Duration(milliseconds: 500));

        // Navigate using global navigator key to ensure navigation works
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.go('/home');
        }
      }
    } catch (e) {
      // Silent failure for background checks
    }
  }

  // Manual verification check (when user clicks "I've verified")
  Future<void> checkEmailVerification(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    if (_isCheckingVerification) return;

    _setCheckingVerification(true);

    try {
      final user = await _authService.reloadAndGetUser();

      if (user?.emailVerified == true) {
        _verificationCheckTimer?.cancel();
        _showToast(loc.translate('emailVerifiedSuccess'), Colors.green);

        if (context.mounted) {
          context.go('/home');
        }
      } else {
        _showToast(loc.translate('emailNotVerifiedYet'), Colors.orange);
      }
    } catch (e) {
      final message = _mapAuthError(loc, e.toString());
      _setError(message);
      _showToast(message, Colors.red);
    } finally {
      _setCheckingVerification(false);
    }
  }

  // Resend verification email
  Future<void> resendVerificationEmail(BuildContext context) async {
    if (!canResend) return;

    final loc = AppLocalizations.of(context);
    _setResendingEmail(true);

    try {
      await _authService.sendEmailVerification();
      _startResendCooldown();
      _showToast(loc.translate('verificationEmailSent'), Colors.green);
    } catch (e) {
      final message = _mapAuthError(loc, e.toString());
      _setError(message);
      _showToast(message, Colors.red);
    } finally {
      _setResendingEmail(false);
    }
  }

  // Open email app
  Future<void> openEmailApp(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    try {
      // Try to open default email app
      final Uri emailUri = Uri(scheme: 'mailto');

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        // Fallback: show instructions to manually check email
        _showToast(loc.translate('checkEmailManually'), Colors.blue);
      }
    } catch (e) {
      _showToast(loc.translate('checkEmailManually'), Colors.blue);
    }
  }

  String _mapAuthError(AppLocalizations loc, String errorCode) {
    if (errorCode.contains('too-many-requests')) {
      return loc.translate('authTooManyRequests');
    } else if (errorCode.contains('network-request-failed')) {
      return loc.translate('authNetworkFailed');
    } else if (errorCode.contains('user-not-found')) {
      return loc.translate('authUserNotFound');
    }
    return loc.translate('verificationFailed');
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
    _verificationCheckTimer?.cancel();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }
}

// Global navigator key for navigation from ViewModels
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
