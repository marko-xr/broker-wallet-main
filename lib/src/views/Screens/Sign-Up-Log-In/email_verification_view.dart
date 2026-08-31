import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';

class EmailVerificationView extends StatefulWidget {
  final String email;

  const EmailVerificationView({
    super.key,
    required this.email,
  });

  @override
  State<EmailVerificationView> createState() => _EmailVerificationViewState();
}

class _EmailVerificationViewState extends State<EmailVerificationView> {
  Timer? _timer;
  bool _isCheckingVerification = false;

// Call this in initState:
  @override
  void initState() {
    super.initState();
    _startEmailVerificationCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startEmailVerificationCheck() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _checkEmailVerificationSilently();
    });
  }

  Future<void> _checkEmailVerificationSilently() async {
    if (_isCheckingVerification) return;

    _isCheckingVerification = true;

    try {
      final authVM = context.read<AuthViewModel>();

      // Silently check verification status
      await authVM.checkEmailVerificationStatus();

      if (authVM.isAuthenticated && authVM.isEmailVerified) {
        _timer?.cancel();
        if (mounted) {
          // Show success message
          _showToast('Email verified successfully!', Colors.green);

          // Navigate to home after a brief delay
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            context.go('/home');
          }
        }
      }
    } catch (e) {
    } finally {
      _isCheckingVerification = false;
    }
  }

  Future<void> _checkEmailVerification() async {
    if (_isCheckingVerification) return;

    _isCheckingVerification = true;

    try {
      final authVM = context.read<AuthViewModel>();

      // Check verification status using repository pattern
      await authVM.checkEmailVerificationStatus();

      if (authVM.isAuthenticated && authVM.isEmailVerified) {
        _timer?.cancel();
        if (mounted) {
          // Show success message
          _showToast('Email verified successfully!', Colors.green);

          // Navigate to home after a brief delay to show the success message
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            context.go('/home');
          }
        }
      } else {
        if (mounted) {
          _showToast(
              'Email not verified yet. Please check your email and click the verification link.',
              Colors.orange);
        }
      }
    } catch (e) {
      if (mounted) {
        _showToast(
            'Error checking verification status: ${e.toString()}', Colors.red);
      }
    } finally {
      _isCheckingVerification = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ChangeNotifierProvider(
      create: (_) => SignUpViewModel(),
      child: Consumer<SignUpViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              leading: const BackArrowButton(),
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Email verification icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      size: 60,
                      color: colors.primary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'Verify Your Email',
                    style: AppTextStyles.appBarTitle.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'We\'ve sent a verification link to',
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    widget.email,
                    style: AppTextStyles.bodyText.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Please check your inbox and click the verification link to continue.',
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Checking verification status
                  if (_isCheckingVerification) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Checking verification status...',
                          style: AppTextStyles.bodyText.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Resend email button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: vm.isResendingEmail
                          ? null
                          : () => vm.resendVerificationEmail(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: vm.isResendingEmail
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            )
                          : Text(
                              'Resend Verification Email',
                              style: AppTextStyles.buttonText.copyWith(
                                color: colors.primary,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Manual check button
                  TextButton(
                    onPressed: _checkEmailVerification,
                    child: Text(
                      'I\'ve verified my email',
                      style: AppTextStyles.bodyText.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Help text
                  Text(
                    'Didn\'t receive the email? Check your spam folder or try resending.',
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showToast(String message, Color backgroundColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
}
