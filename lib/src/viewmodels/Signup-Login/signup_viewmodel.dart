import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/services/auth_service.dart';
import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/common/utils/phone_utils.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

enum SignupMethod { phone, email }

class SignUpViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _mounted = true;
  bool _disposed = false;

  bool _emailSent = false;
  bool get emailSent => _emailSent;

  bool _isResendingEmail = false;
  bool get isResendingEmail => _isResendingEmail;

  bool _phoneFlowCompleted = false;
  String? _pendingVerifiedPhone;

  String? _verificationMessage;
  String? get verificationMessage => _verificationMessage;

  Timer? _debounceTimer;

  // Add getter for mounted state
  bool get mounted => _mounted;

  // Getters returning controller text.
  String get name => nameController.text;
  String get phone => phoneController.text;
  String get email => emailController.text;
  String get password => passwordController.text;
  String get confirmPassword => confirmPasswordController.text;
  /// Whether phone registration can actually complete.
  ///
  /// It is implemented only on the legacy Firebase backend; with Supabase as
  /// the auth authority an account is created by email and a phone number is
  /// verified for it afterwards from Edit Profile.
  ///
  /// This reports capability only. It deliberately does **not** hide the Phone
  /// tab: the product owner owns that UI. Where registration cannot complete,
  /// [signUpWithPhone] says so plainly.
  static bool get phoneSignUpSupported => !SupabaseConfig.useSupabaseAuth;

  /// Email is the initially selected method wherever phone registration cannot
  /// complete, so the screen never *opens* on a method that cannot finish. The
  /// Phone tab is still present and selectable.
  static SignupMethod get initialSignupMethod =>
      phoneSignUpSupported ? SignupMethod.phone : SignupMethod.email;

  SignupMethod signupMethod = initialSignupMethod;

  // Setters updating controller text and notifying listeners.
  void setName(String value) {
    if (nameController.text != value) {
      nameController.text = value;
      notifyListeners();
    }
  }

  void setPhone(String value) {
    if (phoneController.text != value) {
      phoneController.text = value;
      notifyListeners();
    }
  }

  void setSignupMethod(SignupMethod method) {
    signupMethod = method;
    if (method == SignupMethod.phone) {
      _phoneFlowCompleted = false;
    }
    if (!_disposed) notifyListeners();
  }

  void setEmail(String value) {
    if (emailController.text != value) {
      emailController.text = value;

      // Clear previous error and debounce validation
      _emailError = null;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _validateEmailAsync(value);
      });

      notifyListeners();
    }
  }

  void setPassword(String value) {
    if (passwordController.text != value) {
      passwordController.text = value;
      notifyListeners();
    }
  }

  void setConfirmPassword(String value) {
    if (confirmPasswordController.text != value) {
      confirmPasswordController.text = value;
      notifyListeners();
    }
  }

  bool get isLoading => _isLoading;
  bool get showPassword => _showPassword;
  bool get showConfirmPassword => _showConfirmPassword;

  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  String? get nameError => _nameError;
  String? get phoneError => _phoneError;
  String? get emailError => _emailError;
  String? get passwordError => _passwordError;
  String? get confirmPasswordError => _confirmPasswordError;

  void togglePasswordVisibility() {
    _showPassword = !_showPassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _showConfirmPassword = !_showConfirmPassword;
    notifyListeners();
  }

  String _countryCode = '+971'; // Default country code, change as needed
  String get countryCode => _countryCode;

  // If you want to allow changing the country code, add a setter:
  void setCountryCode(String code) {
    _countryCode = code;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _clearErrors() {
    _nameError = null;
    _phoneError = null;
    _emailError = null;
    _passwordError = null;
    _confirmPasswordError = null;
  }

  Future<void> _validateEmailAsync(String email) async {
    if (email.trim().isEmpty || !_mounted) return;

    // Use the enhanced EmailValidator instead of basic regex
    try {
      final emailValidation = await EmailValidator.validateEmail(email.trim());
      if (!emailValidation.isValid) {
        _emailError = emailValidation.message;
        if (_mounted) {
          notifyListeners();
        }
      } else {
        _emailError = null;
        if (_mounted) {
          notifyListeners();
        }
      }
    } catch (e) {
      // Fallback to basic validation if API fails
      final emailRegex =
          RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(email.trim())) {
        _emailError = 'Please enter a valid email address';
        if (_mounted) {
          notifyListeners();
        }
      }
    }
  }

  bool _validateEmailForm() {
    bool isValid = true;

    // Clear previous errors.
    _clearErrors();

    // Validate name.
    if (name.trim().isEmpty) {
      _nameError = 'Name is required';
      isValid = false;
    }

    // Enhanced email validation - use synchronous validation here
    if (email.trim().isEmpty) {
      _emailError = 'Email is required';
      isValid = false;
    } else {
      // Use EmailValidator for basic format check
      if (!EmailValidator.isValidFormat(email.trim())) {
        _emailError = 'Please enter a valid email address';
        isValid = false;
      } else if (EmailValidator.isDisposableEmail(email.trim())) {
        _emailError = 'Disposable email addresses are not allowed';
        isValid = false;
      } else if (!EmailValidator.hasValidDomain(email.trim())) {
        _emailError =
            'Please use a valid email provider (Gmail, Yahoo, Outlook, etc.)';
        isValid = false;
      } else if (email.trim().length > 254) {
        _emailError = 'Email address is too long';
        isValid = false;
      }
    }

    // Validate password against the one canonical policy, so Sign-up, Change
    // Password and Reset Password can never disagree about what a valid
    // password is. The rules are the ones Sign-up already enforced; the
    // messages below are its existing strings, unchanged, because this is a
    // validation change and not a Sign-up UI change.
    final passwordValidation = PasswordPolicy.validate(password);
    if (!passwordValidation.isValid) {
      isValid = false;
      switch (passwordValidation.violation!) {
        case PasswordViolation.empty:
          _passwordError = 'Password is required';
        case PasswordViolation.tooLong:
          _passwordError = 'Password must be at most '
              '${PasswordPolicy.maxLengthBytes} characters';
        case PasswordViolation.requirementsUnmet:
          _passwordError = password.length < PasswordPolicy.minLength
              ? 'Password must be at least ${PasswordPolicy.minLength} characters'
              : 'Password must contain uppercase, lowercase, and numbers';
        case PasswordViolation.confirmationEmpty:
        case PasswordViolation.mismatch:
          // Reported by the confirmation field below, never here.
          break;
      }
    }

    // Validate confirm password.
    if (confirmPassword.isEmpty) {
      _confirmPasswordError = 'Please confirm your password';
      isValid = false;
    } else if (password != confirmPassword) {
      _confirmPasswordError = 'Passwords do not match';
      isValid = false;
    }

    notifyListeners();
    return isValid;
  }

// Update your signUp method with more detailed logging:

  // Replace your entire signUp method with this:

  Future<void> signUp(BuildContext context) async {
    if (!_validateEmailForm()) return;

    _setLoading(true);
    _clearErrors();

    try {
      // Debug log suppressed: STARTING SIGNUP PROCESS
      // Debug log suppressed: Email: ${email.trim()}
      // Debug log suppressed: Password length: ${password.length}

      // Email/password authentication now goes through AuthViewModel so the
      // same UI can use Firebase by default or Supabase behind the migration
      // feature flag. Phone authentication remains on the legacy AuthService.
      final user = await context.read<AuthViewModel>().signUpWithEmail(
            email.trim(),
            password,
            name.trim(),
          );

      if (user != null) {
        _emailSent = true;
        _verificationMessage =
            'A verification email has been sent to ${email.trim()}. Please check your inbox and spam folder.';

        if (context.mounted) {
          context.go('/email-verification', extra: email.trim());
        }
      }
    } on AuthFailure catch (e) {
      if (context.mounted) {
        _showToast(e.message, Colors.red);
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Failed to create account: ${e.toString()}', Colors.red);
      }
    } finally {
      _setLoading(false);
    }
  }

// Also update the resend method with better error handling
  Future<void> resendVerificationEmail(BuildContext context,
      {VoidCallback? onAlreadyVerified}) async {
    _isResendingEmail = true;
    notifyListeners();

    try {
      final authVM = context.read<AuthViewModel>();
      await authVM.checkEmailVerificationStatus();

      if (authVM.isEmailVerified) {
        if (context.mounted) {
          _showToast('Email is already verified!', Colors.green);
          if (onAlreadyVerified != null) {
            onAlreadyVerified();
          } else {
            context.go('/home');
          }
        }
        return;
      }

      await authVM.sendEmailVerification();
      _verificationMessage = 'Verification email sent again to ${email.trim()}';

      if (context.mounted) {
        _showToast('Verification email sent. Check your inbox.', Colors.green);
      }
    } on AuthFailure catch (e) {
      if (context.mounted) {
        _showToast(e.message, Colors.red);
      }
    } catch (e) {
      // Debug log suppressed: Error resending email: $e

      String errorMessage = 'Failed to send verification email.';
      if (e.toString().contains('too-many-requests')) {
        errorMessage =
            'Too many requests. Please wait a minute before trying again.';
      } else if (e.toString().contains('unauthorized-domain')) {
        errorMessage =
            'Email configuration issue. Using default email service.';
      } else if (e.toString().contains('rate-limited')) {
        errorMessage = 'Please wait before requesting another email.';
      } else if (e.toString().contains('user-not-found')) {
        errorMessage = 'User not found. Please sign up again.';
        if (context.mounted) {
          context.go('/sign-up');
        }
      }

      if (context.mounted) {
        _showToast(errorMessage, Colors.red);
      }
    } finally {
      _isResendingEmail = false;
      notifyListeners();
    }
  }

  // Debug method - remove in production
  Future<void> debugCheckCollections() async {
    await _authService.debugLookupCollections();
  }

  // Test method to verify phone number normalization
  Future<void> debugTestPhoneNormalization(String testPhone) async {
    try {
      final e164 = PhoneUtils.toE164Uae(testPhone);
      // Debug log suppressed: Test phone: $testPhone → E164: $e164
      await _authService.isPhoneRegistered(
          e164); // result intentionally discarded in test helper
      // Debug log suppressed: Registration check result: (discarded)
    } catch (e) {
      // Debug log suppressed: Test error: $e
    }
  }

  Future<void> signUpWithPhone(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final translate = loc.translate;

    if (!phoneSignUpSupported) {
      _phoneError = translate('phoneSignUpUnavailable');
      _setLoading(false);
      _showToast(_phoneError!, Colors.orange);
      if (!_disposed) notifyListeners();
      return;
    }

    if (!_validatePhoneSignup(loc)) {
      return;
    }

    _setLoading(true);

    try {
      final trimmedName = name.trim();
      final localPhone = phoneController.text.trim();
      final phoneE164 = PhoneUtils.toE164Uae(localPhone);

      // Check if phone is already registered BEFORE sending OTP
      // Debug log suppressed: Starting phone registration check for: $phoneE164
      // Debug log suppressed: Local phone: $localPhone
      // Debug log suppressed: E164 phone: $phoneE164

      // Check if phone is already registered
      // Debug log suppressed: Now checking if phone is registered...
      bool isRegistered;
      try {
        isRegistered = await _authService.isPhoneRegistered(phoneE164);
        // Debug log suppressed: Phone registration check result: $isRegistered
        // Debug log suppressed: Validation check completed
      } catch (e) {
        // Debug log suppressed: Error checking phone registration: $e
        _phoneError = e.toString().replaceAll('Exception: ', '');
        _setLoading(false);
        _showToast(_phoneError!, Colors.red);
        if (!_disposed) notifyListeners();
        return;
      }

      if (isRegistered) {
        // Debug log suppressed: Phone already registered, blocking signup
        final message = translate('phoneAlreadyRegistered');
        _phoneError = message;
        _setLoading(false);

        // Show toast message
        _showToast(message, Colors.orange);

        // Update UI with error
        if (!_disposed) notifyListeners();

        // Show error dialog for more visibility
        if (context.mounted) {
          _showErrorDialog(
            context,
            translate('accountExists'),
            '$message\n\n${translate('pleaseSignIn')}',
          );
        }

        // CRITICAL: Return here to prevent OTP navigation
        return;
      }

      // Debug log suppressed: Phone not registered, proceeding with OTP
      _phoneFlowCompleted = false;

      await _authService.sendOtp(
        e164: phoneE164,
        onCodeSent: (_) {},
        onCodeSentWithToken: (verificationId, resendToken) {
          _showToast(translate('otpSent'), Colors.green);
          if (context.mounted) {
            context.go(
              '/phone-otp',
              extra: PhoneOtpArgs(
                phoneNumber: phoneE164,
                verificationId: verificationId,
                isSignup: true,
                displayName: trimmedName,
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
              isSignup: true,
              name: trimmedName,
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
      // Debug log suppressed: Error in signUpWithPhone: $e
      _showToast(translate('errorOccurred'), Colors.red);
    } finally {
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  bool _validatePhoneSignup(AppLocalizations loc) {
    bool isValid = true;
    _nameError = null;
    _phoneError = null;

    final translate = loc.translate;
    final trimmedName = name.trim();
    final rawPhone = phoneController.text.trim();

    if (trimmedName.isEmpty) {
      _nameError = translate('nameRequired');
      isValid = false;
    }

    if (rawPhone.isEmpty) {
      _phoneError = translate('phoneNumberTooShort');
      isValid = false;
    } else if (!PhoneUtils.isValidUaeMobile(rawPhone)) {
      _phoneError = translate('authInvalidPhone');
      isValid = false;
    }

    notifyListeners();
    return isValid;
  }

  Future<void> _handlePhoneCredential(
    BuildContext context,
    UserCredential credential, {
    required bool isSignup,
    String? name,
    required String phoneE164,
  }) async {
    if (!phoneSignUpSupported) {
      _showToast(
        AppLocalizations.of(context).translate('phoneSignUpUnavailable'),
        Colors.red,
      );
      return;
    }

    if (_phoneFlowCompleted) return;
    _phoneFlowCompleted = true;

    final loc = AppLocalizations.of(context);
    _pendingVerifiedPhone = phoneE164;
    final user = credential.user;
    if (user == null) {
      _phoneFlowCompleted = false;
      throw Exception(loc.translate('verificationFailed'));
    }

    // Update user profile with phone info
    await _authService.finalizePhoneUser(
      user: user,
      phoneE164: phoneE164,
      displayName: name,
      markAsSignup: isSignup,
    );

    // Wait for AuthViewModel to observe updated phone verification state
    final authReady = await _waitForAuthReady(context);
    if (authReady) {
      // Debug log suppressed: Legacy SignUpViewModel: AuthViewModel confirmed authentication
    } else {
      // Debug log suppressed: Legacy SignUpViewModel: AuthViewModel did not confirm authentication before timeout
    }

    _showToast(loc.translate('otpVerifiedSuccess'), Colors.green);

    if (context.mounted) {
      final router = GoRouter.of(context);
      router.go('/home');
    }

    _pendingVerifiedPhone = null;
  }

  Future<bool> _waitForAuthReady(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 400));

    if (!context.mounted) return false;

    try {
      final authViewModel = context.read<AuthViewModel>();
      final authRepo = RepositoryProvider.instance.authRepository;
      final initialPhone = _pendingVerifiedPhone ??
          authRepo.currentUser?.phoneNumber ??
          authViewModel.currentUser?.phoneNumber ??
          '';

      if (initialPhone.isNotEmpty) {
        await authViewModel.markPhoneVerified(phoneNumber: initialPhone);
      }

      const pollingInterval = Duration(milliseconds: 200);
      const maxAttempts = 15;

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (authViewModel.isAuthenticated ||
            authViewModel.currentUser?.isPhoneVerified == true) {
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

        await authViewModel.syncUserFromRepository();

        await Future.delayed(pollingInterval);
        if (!context.mounted) return false;
      }
    } catch (e) {
      // Debug log suppressed: Failed to synchronize AuthViewModel after phone signup: $e
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

  Future<void> signUpWithGoogle(BuildContext context) async {
    _showToast('Google sign up coming soon', Colors.orange);
  }

  void _showErrorDialog(BuildContext context, String title, String message) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _disposed = true;
    _debounceTimer?.cancel();
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
