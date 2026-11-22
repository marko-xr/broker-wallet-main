import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_reset_request_sheet.dart';

enum LoginMethod { phone, email }

class SignInViewModel extends ChangeNotifier {
  /// [phoneAuthEnabled] overrides the build switch for tests only; the app
  /// always uses [phoneSignInSupported].
  SignInViewModel({bool? phoneAuthEnabled})
      : _phoneAuthEnabled = phoneAuthEnabled ?? phoneSignInSupported;

  final bool _phoneAuthEnabled;

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
  /// Whether this build attempts phone sign-in (Supabase OTP).
  ///
  /// Off unless the build sets `PHONE_AUTH_ENABLED`; then [sendOTP] keeps its
  /// existing "not available yet" message. This is a client switch only: the
  /// server decides whether a phone sign-in can actually happen.
  ///
  /// This reports capability only. It deliberately does **not** hide the Phone
  /// tab: the product owner owns that UI.
  static bool get phoneSignInSupported =>
      SupabaseConfig.useSupabaseAuth && SupabaseConfig.phoneAuthEnabled;

  /// The screen opens on Email. Opening on Phone instead is a product-owner
  /// UI decision that has not been made; the Phone tab stays selectable.
  static LoginMethod get initialLoginMethod => LoginMethod.email;

  LoginMethod loginMethod = initialLoginMethod;

  // Getters
  bool get isLoading => _isLoading;
  bool get showPassword => _showPassword;
  /// A localization key; the screen translates it.
  String? get emailError => _emailError;

  /// A likely-typo correction of the email, offered as a hint ("Did you
  /// mean …?") when the user leaves the field; null when there is none.
  String? get emailSuggestion => _emailSuggestion;
  String? _emailSuggestion;
  String? get passwordError => _passwordError;
  String? get phoneError => _phoneError;
  String get countryCode => _countryCode;

  // Setters
  void setEmail(String value) {
    emailController.text = value;
    // A hint is about what was left in the field; typing makes it stale.
    _emailSuggestion = null;
    // Nothing is said while typing. Once an error is showing, it is checked
    // live, so it goes as soon as the address is valid.
    if (_emailError != null) {
      _emailError = EmailValidator.fieldErrorKey(value);
    }
    if (!_disposed) notifyListeners();
  }

  /// The user left the email field: its format is checked now.
  void emailFieldLeft() {
    final error = EmailValidator.fieldErrorKey(emailController.text);
    final suggestion = error == null
        ? EmailValidator.suggestedCorrection(emailController.text)
        : null;
    if (error == _emailError && suggestion == _emailSuggestion) return;
    _emailError = error;
    _emailSuggestion = suggestion;
    if (!_disposed) notifyListeners();
  }

  /// The user accepted the "Did you mean …?" hint.
  void applyEmailSuggestion() {
    final suggestion = _emailSuggestion;
    if (suggestion == null) return;
    emailController.text = suggestion;
    _emailSuggestion = null;
    _emailError = null;
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
      _emailError = 'emailRequired';
      valid = false;
    } else if (!EmailValidator.isValidFormat(emailController.text.trim())) {
      _emailError = 'emailInvalidFormat';
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

  /// Requests a phone sign-in code and, once it was sent, opens the code
  /// screen. Never creates an account: an unknown number is reported.
  Future<void> sendOTP(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final translate = loc.translate;
    final gateway =
        _phoneAuthEnabled ? context.read<AuthViewModel>().phoneSignIn : null;

    if (gateway == null) {
      _phoneError = translate('phoneSignInUnavailable');
      _showToast(_phoneError!, Colors.orange);
      if (!_disposed) notifyListeners();
      return;
    }
    if (_isLoading) return;

    final String phone;
    try {
      phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneController.text);
    } on PhoneValidationException {
      _phoneError = translate('invalidUAEPhoneNumber');
      if (!_disposed) notifyListeners();
      return;
    }

    _isLoading = true;
    _phoneError = null;
    if (!_disposed) notifyListeners();

    try {
      await gateway.requestPhoneSignInCode(
        phoneE164: phone,
        createAccount: false,
      );
      if (context.mounted) {
        unawaited(context.push(
          '/phone-otp',
          extra: PhoneOtpArgs(
            phoneNumber: phone,
            isSignup: false,
            codeSentAt: DateTime.now(),
          ),
        ));
      }
    } on AuthFailure catch (e) {
      _phoneError =
          translate(PhoneOtpViewModel.errorKeyFor(e, isSignup: false));
    } catch (_) {
      _phoneError = translate('verificationFailed');
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

      // Preload map data in background for instant map loading. It is
      // intentionally non-blocking.
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
        // The app-lifetime Welcome dialog owns a genuine displacement notice.
        // Other expired sessions retain an ordinary, localized sign-in error.
        if (e.code == AuthFailureCode.sessionExpired &&
            context.mounted &&
            context.read<AuthViewModel>().wasCurrentSignInSuperseded) {
          return;
        }
        final key = switch (e.code) {
          AuthFailureCode.invalidCredentials => 'authInvalidCredentials',
          AuthFailureCode.appSessionUnavailable => 'appSessionCheckFailed',
          AuthFailureCode.sessionExpired => 'authSessionExpired',
          _ => null,
        };
        if (context.mounted) {
          _showToast(
            key == null ? e.message : AppLocalizations.of(context).translate(key),
            Colors.red,
          );
        }
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

  /// Opens the password-reset request sheet.
  ///
  /// This is the Login screen's existing "Forgot password?" action, which until
  /// now only reported that the feature was unavailable. Nothing about the
  /// Login layout changes: only what this action does.
  ///
  /// The typed email is carried in as a convenience. It is never used to look
  /// the account up, and the sheet reports the same outcome whether or not the
  /// address belongs to an account.
  Future<void> forgotPassword(BuildContext context) async {
    final repository = RepositoryProvider.instance.authRepository;
    final gateway = passwordCapabilityOf(repository);
    if (gateway == null) {
      _showToast(
        AppLocalizations.of(context).translate('passwordResetUnavailable'),
        Colors.red,
      );
      return;
    }

    final initialEmail = emailController.text.trim();
    final viewModel = PasswordResetRequestViewModel(gateway: gateway);
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PasswordResetRequestSheet(
        viewModel: viewModel,
        initialEmail: initialEmail,
      ),
    );
    viewModel.dispose();
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
