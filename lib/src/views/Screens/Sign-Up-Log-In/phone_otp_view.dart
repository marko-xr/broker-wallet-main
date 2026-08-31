import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/phone_otp_viewmodel.dart';

class PhoneOtpView extends StatefulWidget {
  final PhoneOtpArgs args;
  const PhoneOtpView({super.key, required this.args});

  @override
  State<PhoneOtpView> createState() => _PhoneOtpViewState();
}

class _PhoneOtpViewState extends State<PhoneOtpView> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _navigateBack(BuildContext context) {
    // Try to pop first, if that fails, navigate to appropriate fallback
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      // Fallback navigation based on the OTP args context
      final vm = Provider.of<PhoneOtpViewModel>(context, listen: false);
      if (vm.args.isSignup) {
        context.go('/sign-up');
      } else {
        context.go('/sign-in');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    final basePinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );

    return ChangeNotifierProvider(
      create: (_) => PhoneOtpViewModel()..initialize(widget.args),
      child: Consumer<PhoneOtpViewModel>(
        builder: (context, vm, _) {
          final errorPinTheme = basePinTheme.copyDecorationWith(
            border: Border.all(color: colors.error),
          );

          final focusedPinTheme = basePinTheme.copyDecorationWith(
            border: Border.all(color: colors.primary),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          );

          final subtitle = loc
              .translate('otpSentTo')
              .replaceFirst('{phone}', vm.args.formattedPhone);

          final timerLabel = vm.secondsRemaining > 0
              ? loc
                  .translate('resendCodeIn')
                  .replaceFirst('{seconds}', vm.secondsRemaining.toString())
              : loc.translate('didntReceiveCode');

          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.05),
                    colors.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => _navigateBack(context),
                        icon: Icon(Icons.arrow_back_rounded,
                            color: colors.primary, size: 28),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                height: 80,
                                width: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      colors.primary.withValues(alpha: 0.18),
                                      colors.primary.withValues(alpha: 0.45),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Icon(
                                  Icons.sms_rounded,
                                  color: colors.onPrimary,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                loc.translate('otpTitle'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.onSurface,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 32),
                              Pinput(
                                length: 6,
                                controller: _pinController,
                                focusNode: _pinFocusNode,
                                defaultPinTheme: basePinTheme,
                                focusedPinTheme: focusedPinTheme,
                                submittedPinTheme: focusedPinTheme,
                                errorPinTheme: errorPinTheme,
                                closeKeyboardWhenCompleted: true,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode
                                ],
                                keyboardType: TextInputType.number,
                                onChanged: (_) => vm.clearError(),
                                onCompleted: (value) =>
                                    vm.verifyCode(context, value),
                                forceErrorState: vm.errorMessage != null,
                              ),
                              if (vm.errorMessage != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  vm.errorMessage!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.error),
                                ),
                              ],
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: vm.isVerifying
                                      ? null
                                      : () => vm.verifyCode(
                                            context,
                                            _pinController.text,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                  child: vm.isVerifying
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.8,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          loc.translate('verifyAndContinue'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Column(
                                children: [
                                  Text(
                                    timerLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colors.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: vm.secondsRemaining == 0 &&
                                            !vm.isResending
                                        ? () => vm.resendCode(context)
                                        : null,
                                    icon: vm.isResending
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colors.primary,
                                            ),
                                          )
                                        : Icon(Icons.refresh_rounded,
                                            color: vm.secondsRemaining == 0
                                                ? colors.primary
                                                : colors.onSurface
                                                    .withValues(alpha: 0.4)),
                                    label: Text(
                                      vm.isResending
                                          ? loc.translate('resending')
                                          : loc.translate('resendCode'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: vm.secondsRemaining == 0
                                                ? colors.primary
                                                : colors.onSurface
                                                    .withValues(alpha: 0.4),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              TextButton(
                                onPressed: () => _navigateBack(context),
                                child: Text(
                                  loc.translate('changeNumber'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurface
                                            .withValues(alpha: 0.7),
                                        decoration: TextDecoration.underline,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
