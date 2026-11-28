import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/google_sign_in_flow.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart';

enum SignupMethod { phone, email }

class SignUpViewModel extends ChangeNotifier {
  /// [phoneAuthEnabled] overrides the build switch for tests only; the app
  /// always uses [phoneSignUpSupported].
  SignUpViewModel({bool? phoneAuthEnabled})
      : _phoneAuthEnabled = phoneAuthEnabled ?? phoneSignUpSupported;

  final bool _phoneAuthEnabled;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _googleInProgress = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _mounted = true;
  bool _disposed = false;

  bool _emailSent = false;
  bool get emailSent => _emailSent;

  bool _isResendingEmail = false;
  bool get isResendingEmail => _isResendingEmail;


  String? _verificationMessage;
  String? get verificationMessage => _verificationMessage;


  // Add getter for mounted state
  bool get mounted => _mounted;

  // Getters returning controller text.
  String get name => nameController.text;
  String get phone => phoneController.text;
  String get email => emailController.text;
  String get password => passwordController.text;
  String get confirmPassword => confirmPasswordController.text;
  /// Whether this build attempts phone registration (Supabase OTP).
  ///
  /// Off unless the build sets `PHONE_AUTH_ENABLED`; then [signUpWithPhone]
  /// keeps its existing "not available yet" message. This is a client switch
  /// only: the server's sign-up policy decides whether an account is created.
  ///
  /// This reports capability only. It deliberately does **not** hide the Phone
  /// tab: the product owner owns that UI.
  static bool get phoneSignUpSupported =>
      SupabaseConfig.useSupabaseAuth && SupabaseConfig.phoneAuthEnabled;

  /// The screen opens on Email. Opening on Phone instead is a product-owner
  /// UI decision that has not been made; the Phone tab stays selectable.
  static SignupMethod get initialSignupMethod => SignupMethod.email;

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
    if (!_disposed) notifyListeners();
  }

  void setEmail(String value) {
    if (emailController.text != value) {
      emailController.text = value;
      // A hint is about what was left in the field; typing makes it stale.
      _emailSuggestion = null;

      // Nothing is said while typing. Once an error is showing, it is checked
      // live, so it goes as soon as the address is valid.
      if (_emailError != null) {
        _emailError =
            EmailValidator.fieldErrorKey(value, rejectDisposable: true);
      }

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

  /// True while "Continue with Google" runs: the account picker, Supabase
  /// Auth and the device check.
  bool get isGoogleSignInInProgress => _googleInProgress;
  bool get showPassword => _showPassword;
  bool get showConfirmPassword => _showConfirmPassword;

  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  String? get nameError => _nameError;
  String? get phoneError => _phoneError;
  /// A localization key; the screen translates it.
  String? get emailError => _emailError;

  /// A likely-typo correction of the email, offered as a hint ("Did you
  /// mean …?") when the user leaves the field; null when there is none.
  String? get emailSuggestion => _emailSuggestion;
  String? _emailSuggestion;

  /// The user left the email field: its format is checked now.
  void emailFieldLeft() {
    final error = EmailValidator.fieldErrorKey(email, rejectDisposable: true);
    final suggestion =
        error == null ? EmailValidator.suggestedCorrection(email) : null;
    if (error == _emailError && suggestion == _emailSuggestion) return;
    _emailError = error;
    _emailSuggestion = suggestion;
    if (_mounted) notifyListeners();
  }

  /// The user accepted the "Did you mean …?" hint.
  void applyEmailSuggestion() {
    final suggestion = _emailSuggestion;
    if (suggestion == null) return;
    emailController.text = suggestion;
    _emailSuggestion = null;
    _emailError = null;
    if (_mounted) notifyListeners();
  }
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
      _emailError = 'emailRequired';
      isValid = false;
    } else {
      // Use EmailValidator for basic format check
      if (!EmailValidator.isValidFormat(email.trim())) {
        _emailError = 'emailInvalidFormat';
        isValid = false;
      } else if (EmailValidator.isDisposableEmail(email.trim())) {
        _emailError = 'emailDisposableNotAllowed';
        isValid = false;
      } else if (!EmailValidator.hasValidDomain(email.trim())) {
        _emailError = 'emailProviderNotAllowed';
        isValid = false;
      } else if (email.trim().length > 254) {
        _emailError = 'emailTooLong';
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
    if (_googleInProgress) return;
    if (!_validateEmailForm()) return;

    _setLoading(true);
    _clearErrors();

    try {
      // Debug log suppressed: STARTING SIGNUP PROCESS
      // Debug log suppressed: Email: ${email.trim()}
      // Debug log suppressed: Password length: ${password.length}

      // Email/password authentication goes through AuthViewModel (Supabase).
      // Phone registration is not available yet.
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

  /// Requests a phone sign-up code and, once it was sent, opens the code
  /// screen. Sending a code is not registration: the account is usable only
  /// after the code is verified and the session is authorized. The name is
  /// carried to the code screen and saved only after that, never sent with
  /// the code request.
  Future<void> signUpWithPhone(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final translate = loc.translate;
    final gateway =
        _phoneAuthEnabled ? context.read<AuthViewModel>().phoneSignIn : null;

    if (gateway == null) {
      _phoneError = translate('phoneSignUpUnavailable');
      _setLoading(false);
      _showToast(_phoneError!, Colors.orange);
      if (!_disposed) notifyListeners();
      return;
    }
    if (_isLoading || _googleInProgress) return;

    _clearErrors();
    var valid = true;
    final displayName = name.trim();
    if (displayName.isEmpty) {
      _nameError = translate('nameRequired');
      valid = false;
    }
    String? phoneE164;
    try {
      phoneE164 = PhoneNumberNormalizer.normalizeUaeMobile(phone);
    } on PhoneValidationException {
      _phoneError = translate('invalidUAEPhoneNumber');
      valid = false;
    }
    if (!valid || phoneE164 == null) {
      if (!_disposed) notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      await gateway.requestPhoneSignInCode(
        phoneE164: phoneE164,
        createAccount: true,
      );
      if (context.mounted) {
        unawaited(context.push(
          '/phone-otp',
          extra: PhoneOtpArgs(
            phoneNumber: phoneE164,
            isSignup: true,
            displayName: displayName,
            codeSentAt: DateTime.now(),
          ),
        ));
      }
    } on AuthFailure catch (e) {
      _phoneError =
          translate(PhoneOtpViewModel.errorKeyFor(e, isSignup: true));
    } catch (_) {
      _phoneError = translate('verificationFailed');
    } finally {
      if (!_disposed) _setLoading(false);
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

  /// "Continue with Google" from Sign-up. The same sign-in as on Login:
  /// Supabase Auth creates the account only when the Google account has none,
  /// so it can never create a second account for an existing one.
  Future<void> signUpWithGoogle(BuildContext context) async {
    if (_isLoading || _googleInProgress) return;
    final authVM = context.read<AuthViewModel>();
    _googleInProgress = true;
    if (!_disposed) notifyListeners();

    final result = await GoogleSignInFlow.run(authVM);

    if (!_disposed) {
      _googleInProgress = false;
      notifyListeners();
    }
    if (!context.mounted) return;
    GoogleSignInFlow.apply(
      context,
      result,
      showError: (message) => _showToast(message, Colors.red),
    );
  }

  @override
  void dispose() {
    _mounted = false;
    _disposed = true;
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}
