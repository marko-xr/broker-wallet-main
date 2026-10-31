import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_reset_request_sheet.dart';

enum LoginMethod { phone, email }

class SignInViewModel extends ChangeNotifier {

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
        // The app-lifetime Welcome dialog owns a genuine displacement notice.
        // Other expired sessions retain an ordinary, localized sign-in error.
        if (e.code == AuthFailureCode.sessionExpired &&
            context.mounted &&
            context.read<AuthViewModel>().wasCurrentSignInSuperseded) {
          return;
        }
        final key = switch (e.code) {
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
