import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/services/auth_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

class PhoneOtpViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();

  late PhoneOtpArgs _args;
  PhoneOtpArgs get args => _args;

  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsRemaining = 60;
  String? _errorMessage;
  bool _autoVerificationInProgress = false;

  Timer? _timer;
  bool _disposed = false;

  bool get isVerifying => _isVerifying || _autoVerificationInProgress;
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

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _args.verificationId,
        smsCode: trimmedCode,
      );

      if (_args.isLinkingPhone) {
        await _completePhoneLinking(context, credential);
      } else {
        final credentialResult =
            await _authService.signInWithCredential(credential);
        await _completePostVerification(context, credentialResult);
      }
    } catch (e) {
      final message = e.toString();
      _errorMessage = message;
      _showToast(message, Colors.red);
    } finally {
      _isVerifying = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resendCode(BuildContext? context,
      {bool isInitial = false}) async {
    if (!isInitial && (_secondsRemaining > 0 || _isResending)) return;

    final loc = context != null ? AppLocalizations.of(context) : null;

    _isResending = true;
    _errorMessage = null;
    if (!_disposed) notifyListeners();

    try {
      await _authService.sendOtp(
        e164: _args.phoneNumber,
        forceResendToken: _args.resendToken,
        timeout: const Duration(seconds: 120), // Increased timeout
        onCodeSent: (verificationId) {
          _args = _args.copyWith(verificationId: verificationId);
          if (!isInitial) {
            _startTimer(reset: true);
          }
        },
        onCodeSentWithToken: (verificationId, resendToken) {
          _args = _args.copyWith(
            verificationId: verificationId,
            resendToken: resendToken,
          );
          if (context != null && loc != null && !isInitial) {
            _showToast(loc.translate('otpResent'), Colors.green);
          }
        },
        onAutoVerified: (credential) async {
          _autoVerificationInProgress = true;
          if (!_disposed) notifyListeners();

          // Add small delay to allow UI to stabilize
          await Future.delayed(const Duration(milliseconds: 300));

          if (context != null && context.mounted) {
            await _handleAutoVerification(context, credential);
          } else {
            // Debug log suppressed: Auto-verification received but context not available
          }
        },
        onFailed: (exception) {
          final message = loc != null
              ? _mapAuthError(loc, exception.code)
              : 'Phone verification failed: ${exception.message}';
          _errorMessage = message;
          if (context != null) {
            _showToast(message, Colors.red);
          }
        },
        onTimeout: (verificationId) {
          _args = _args.copyWith(verificationId: verificationId);
          // Timeout is normal - don't show error
        },
      );
    } catch (e) {
      final message = e.toString();
      _errorMessage = message;
      if (context != null) {
        _showToast(message, Colors.red);
      }
    } finally {
      _isResending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _handleAutoVerification(
    BuildContext context,
    PhoneAuthCredential credential,
  ) async {
    try {
      // Debug log suppressed: Handling auto-verification

      if (_args.isLinkingPhone) {
        await _completePhoneLinking(context, credential);
      } else {
        await _completeWithCredential(context, credential);
      }
    } catch (e) {
      // Debug log suppressed: Auto-verification failed: $e
      _errorMessage = 'Auto-verification failed: $e';
      if (!_disposed) notifyListeners();
    } finally {
      _autoVerificationInProgress = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _completeWithCredential(
    BuildContext context,
    PhoneAuthCredential credential,
  ) async {
    _isVerifying = true;
    if (!_disposed) notifyListeners();

    try {
      final credentialResult =
          await _authService.signInWithCredential(credential);
      await _completePostVerification(context, credentialResult);
    } catch (e) {
      final message = e.toString();
      _errorMessage = message;
      _showToast(message, Colors.red);
    } finally {
      _isVerifying = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _completePhoneLinking(
    BuildContext context,
    PhoneAuthCredential credential,
  ) async {
    final loc = AppLocalizations.of(context);

    try {
      final user = await _authService.linkPhoneCredential(credential);
      final phoneNumber = user.phoneNumber ?? _args.phoneNumber;

      if (context.mounted) {
        final authViewModel = context.read<AuthViewModel>();
        await authViewModel.markPhoneVerified(phoneNumber: phoneNumber);
        await authViewModel.syncUserFromRepository();
      }

      _timer?.cancel();
      var successMessage = loc.translate('phoneLinkedSuccessMessage');
      if (successMessage.startsWith('**')) {
        successMessage = 'Phone number added and verified successfully!';
      }
      _showToast(successMessage, Colors.green);

      if (context.mounted) {
        context.go('/profile');
      }
    } catch (e) {
      _errorMessage = e.toString();
      _showToast(_errorMessage!, Colors.red);
    }
  }

  Future<void> _completePostVerification(
    BuildContext context,
    UserCredential credential,
  ) async {
    final loc = AppLocalizations.of(context);

    if (SupabaseConfig.useSupabaseAuth) {
      throw Exception('Phone sign-in is not supported with Supabase.');
    }

    final user = credential.user;
    if (user == null) {
      throw Exception(loc.translate('verificationFailed'));
    }

    await _authService.finalizePhoneUser(
      user: user,
      phoneE164: _args.phoneNumber,
      displayName: _args.displayName,
      markAsSignup: _args.isSignup,
    );

    // Debug log suppressed: Phone auth complete - waiting for auth state propagation...

    final authReady = await _waitForAuthReady(context);
    if (authReady) {
      // Debug log suppressed: AuthViewModel reports authenticated. Proceeding to home.
    } else {
      // Debug log suppressed: AuthViewModel did not report authenticated before timeout. Proceeding cautiously.
    }

    // Force a final sync to ensure auth state is current
    if (context.mounted) {
      final authViewModel = context.read<AuthViewModel>();
      await authViewModel.syncUserFromRepository();
    }

    _timer?.cancel();

    if (context.mounted) {
      final loc = AppLocalizations.of(context);
      _showToast(loc.translate('otpVerifiedSuccess'), Colors.green);

      final router = GoRouter.of(context);
      router.go('/home');
    }
  }

  Future<bool> _waitForAuthReady(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) return false;

    try {
      final authViewModel = context.read<AuthViewModel>();
      final authRepo = RepositoryProvider.instance.authRepository;
      final initialPhone = _args.phoneNumber.isNotEmpty
          ? _args.phoneNumber
          : (authRepo.currentUser?.phoneNumber ?? '');

      // First, mark phone as verified to ensure proper state
      if (initialPhone.isNotEmpty) {
        await authViewModel.markPhoneVerified(phoneNumber: initialPhone);
        // Debug log suppressed: Marked phone as verified: $initialPhone
      }

      const pollingInterval = Duration(milliseconds: 300);
      const maxAttempts = 10; // ~3 seconds total

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        // Force sync from repository first to get latest state
        await authViewModel.syncUserFromRepository();

        final isAuthenticated = authViewModel.isAuthenticated;
        final isPhoneVerified =
            authViewModel.currentUser?.isPhoneVerified == true;

        // Debug log suppressed: Auth check attempt ${attempt + 1}: authenticated=$isAuthenticated, phoneVerified=$isPhoneVerified

        if (isAuthenticated || isPhoneVerified) {
          // Debug log suppressed: AuthViewModel confirmed authentication on attempt ${attempt + 1}
          return true;
        }

        final currentRepoUser =
            authRepo.currentUser ?? await authRepo.reloadUser();
        if (currentRepoUser?.phoneNumber != null &&
            currentRepoUser!.phoneNumber!.isNotEmpty) {
          await authViewModel.markPhoneVerified(
              phoneNumber: currentRepoUser.phoneNumber!);

          if (authViewModel.isAuthenticated) {
            return true;
          }
        }

        await Future.delayed(pollingInterval);
        if (!context.mounted) return false;
      }

      // Debug log suppressed: Timed out waiting for AuthViewModel authentication
    } catch (e) {
      // Debug log suppressed: Failed to synchronize AuthViewModel after phone verification: $e
    }

    return false;
  }

  String _mapAuthError(AppLocalizations loc, String code) {
    switch (code) {
      case 'invalid-phone-number':
        return loc.translate('authInvalidPhone');
      case 'too-many-requests':
        return loc.translate('authTooManyRequests');
      case 'session-expired':
        return loc.translate('authSessionExpired');
      case 'quota-exceeded':
        return loc.translate('authQuotaExceeded');
      case 'network-request-failed':
        return loc.translate('authNetworkFailed');
      case 'captcha-check-failed':
        return loc.translate('authCaptchaFailed');
      case 'invalid-verification-code':
        return loc.translate('authInvalidOtp');
      default:
        return loc.translate('verificationFailed');
    }
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
