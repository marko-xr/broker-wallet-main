import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/services/auth_service.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/common/utils/phone_utils.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

enum LoginMethod { phone, email }

class SignInViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _disposed = false;
  String? _emailError;
  String? _passwordError;
  String? _phoneError;
  String _countryCode = '+971';
  /// Whether phone sign-in can actually complete.
  ///
  /// It is implemented only on the legacy Firebase backend; with Supabase as
  /// the auth authority a phone number is verified for an already signed-in
  /// account from Edit Profile instead.
  ///
  /// This reports capability only. It deliberately does **not** hide the Phone
  /// tab: the product owner owns that UI. Where sign-in cannot complete,
  /// [sendOTP] says so plainly rather than the screen pretending the option
  /// does not exist.
  static bool get phoneSignInSupported => !SupabaseConfig.useSupabaseAuth;

  /// Email is the initially selected method wherever phone sign-in cannot
  /// complete, so the screen never *opens* on a method that cannot finish.
  /// The Phone tab is still present and selectable.
  static LoginMethod get initialLoginMethod =>
      phoneSignInSupported ? LoginMethod.phone : LoginMethod.email;

  LoginMethod loginMethod = initialLoginMethod;
  bool _phoneFlowCompleted = false;

  // Getters
  bool get isLoading => _isLoading;
  bool get showPassword => _showPassword;
  String? get emailError => _emailError;
  String? get passwordError => _passwordError;
  String? get phoneError => _phoneError;
  String get countryCode => _countryCode;

  // Setters
  void setEmail(String value) {
    emailController.text = value;
    if (_emailError != null) _emailError = null;
    if (!_disposed) notifyListeners();
  }

  void setPassword(String value) {
    passwordController.text = value;
    if (_passwordError != null) _passwordError = null;
    if (!_disposed) notifyListeners();
  }

  void setPhone(String value) {
    phoneController.text = value;
    if (_phoneError != null) _phoneError = null;
    if (!_disposed) notifyListeners();
  }

  void setLoginMethod(LoginMethod method) {
    loginMethod = method;
    if (method != LoginMethod.phone && _phoneError != null) {
      _phoneError = null;
    }
    if (method == LoginMethod.phone) {
      _phoneFlowCompleted = false;
    }
    if (!_disposed) notifyListeners();
  }

  void togglePasswordVisibility() {
    _showPassword = !_showPassword;
    if (!_disposed) notifyListeners();
  }

  bool _validateEmailForm() {
    bool valid = true;
    _emailError = null;
    _passwordError = null;

    if (emailController.text.trim().isEmpty) {
      _emailError = 'Email is required';
      valid = false;
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
        .hasMatch(emailController.text.trim())) {
      _emailError = 'Please enter a valid email';
      valid = false;
    }

    if (passwordController.text.isEmpty) {
      _passwordError = 'Password is required';
      valid = false;
    }

    if (!_disposed) notifyListeners();
    return valid;
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

  Future<void> sendOTP(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final translate = loc.translate;

    if (!phoneSignInSupported) {
      _phoneError = translate('phoneSignInUnavailable');
      _showToast(_phoneError!, Colors.orange);
      if (!_disposed) notifyListeners();
      return;
    }

    final rawPhone = phoneController.text.trim();
    _phoneError = null;

    if (rawPhone.isEmpty) {
      _phoneError = translate('phoneNumberTooShort');
      if (!_disposed) notifyListeners();
      return;
    }

    if (!PhoneUtils.isValidUaeMobile(rawPhone)) {
      _phoneError = translate('authInvalidPhone');
      if (!_disposed) notifyListeners();
      return;
    }

    _isLoading = true;
    if (!_disposed) notifyListeners();

    try {
      final phoneE164 = PhoneUtils.toE164Uae(rawPhone);
      _phoneFlowCompleted = false;

      // Check if phone is registered BEFORE sending OTP
      bool isRegistered;
      try {
        isRegistered = await _authService.isPhoneRegistered(phoneE164);
      } catch (e) {
        _phoneError = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        _showToast(_phoneError!, Colors.red);
        if (!_disposed) notifyListeners();
        return;
      }

      if (!isRegistered) {
        final message = translate('phoneNotRegistered');
        _phoneError = message;
        _showToast(message, Colors.orange);
        _isLoading = false;
        if (!_disposed) notifyListeners();
        return;
      }

      await _authService.sendOtp(
        e164: phoneE164,
        onCodeSent: (_) {},
        onCodeSentWithToken: (verificationId, resendToken) {
          if (_phoneFlowCompleted) return;
          _showToast(translate('otpSent'), Colors.green);
          if (context.mounted) {
            context.go(
              '/phone-otp',
              extra: PhoneOtpArgs(
                phoneNumber: phoneE164,
                verificationId: verificationId,
                isSignup: false,
                resendToken: resendToken,
              ),
            );
          }
        },
        onAutoVerified: (credential) async {
          try {
            final result = await _authService.signInWithCredential(credential);
            await _handlePhoneCredential(
              context,
              result,
              phoneE164: phoneE164,
            );
          } catch (error) {
            _showToast(error.toString(), Colors.red);
          }
        },
        onFailed: (exception) {
          final message = _mapAuthError(loc, exception.code);
          _phoneError = message;
          _showToast(message, Colors.red);
          if (!_disposed) notifyListeners();
        },
        onTimeout: (_) {},
      );
    } catch (e) {
      _showToast(e.toString(), Colors.red);
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> signIn(BuildContext context) async {
    if (!_validateEmailForm()) return;

    _isLoading = true;
    if (!_disposed) notifyListeners();

    try {
      final normalizedEmail = emailController.text.trim();
      final authVM = context.read<AuthViewModel>();
      final user = await authVM.signInWithEmail(
        normalizedEmail,
        passwordController.text,
      );

      if (user == null) {
        throw const AuthFailure(
          code: AuthFailureCode.unknown,
          message: 'Sign in did not return a user.',
        );
      }

      if (!user.isEmailVerified) {
        if (context.mounted) {
          context.go('/email-verification', extra: normalizedEmail);
        }
        return;
      }

      // Preload map data in background for instant map loading. During the
      // migration this still targets Firebase and is intentionally non-blocking.
      MapDataCacheService().preloadMapData().catchError((e) {
        // Non-blocking - map will still work, just slower first load
      });

      if (context.mounted) {
        context.go('/home');
      }
    } on AuthFailure catch (e) {
      if (e.isEmailNotConfirmed) {
        if (context.mounted) {
          context.go(
            '/email-verification',
            extra: emailController.text.trim(),
          );
        }
      } else {
        _showToast(e.message, Colors.red);
      }
    } catch (e) {
      final message = e.toString();
      if (message.toLowerCase().contains('email not confirmed')) {
        if (context.mounted) {
          context.go(
            '/email-verification',
            extra: emailController.text.trim(),
          );
        }
      } else {
        _showToast(message, Colors.red);
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    _showToast('Google sign in coming soon', Colors.orange);
  }

  void forgotPassword(BuildContext context) {
    _showToast('Forgot password coming soon', Colors.orange);
  }

  Future<void> _handlePhoneCredential(
    BuildContext context,
    UserCredential credential, {
    required String phoneE164,
  }) async {
    if (!phoneSignInSupported) {
      _showToast(
        AppLocalizations.of(context).translate('phoneSignInUnavailable'),
        Colors.red,
      );
      return;
    }

    if (_phoneFlowCompleted) return;
    _phoneFlowCompleted = true;

    final loc = AppLocalizations.of(context);
    final user = credential.user;
    if (user == null) {
      _showToast(loc.translate('verificationFailed'), Colors.red);
      return;
    }

    await _authService.finalizePhoneUser(
      user: user,
      phoneE164: phoneE164,
      markAsSignup: false,
    );

    _showToast(loc.translate('otpVerifiedSuccess'), Colors.green);
    if (context.mounted) {
      context.go('/home');
    }
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

  @override
  void dispose() {
    _disposed = true;
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    super.dispose();
  }
}
