import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/phone_verification_viewmodel.dart';

/// Code-entry step of a phone verification. Pops `true` only when the backend
/// has confirmed the number; `false` when the user leaves.
///
/// Presentation only: every decision — validation, single-flight, the resend
/// countdown, session ownership — belongs to [PhoneVerificationViewModel].
/// It closes only itself; it never navigates anywhere else.
class PhoneOtpDialog extends StatefulWidget {
  const PhoneOtpDialog({super.key});

  @override
  State<PhoneOtpDialog> createState() => _PhoneOtpDialogState();
}

class _PhoneOtpDialogState extends State<PhoneOtpDialog> {
  /// U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE.
  static const int _ltrIsolate = 0x2066;
  static const int _popDirectionalIsolate = 0x2069;

  final _codeController = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify(PhoneVerificationViewModel vm) async {
    // The typed code is kept on failure so it can be corrected, not retyped.
    final verified = await vm.verifyCode(_codeController.text);
    if (verified && mounted) _close(true);
  }

  Future<void> _resend(PhoneVerificationViewModel vm) async {
    final colors = Theme.of(context).colorScheme;
    final sentMessage = AppLocalizations.of(context).translate('otpResent');
    final resent = await vm.resendCode();
    if (!resent || !mounted) return;
    _codeController.clear();
    setState(() {});
    Fluttertoast.showToast(
      msg: sentMessage,
      backgroundColor: colors.primary,
      textColor: colors.onPrimary,
    );
  }

  void _close(bool verified) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(verified);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PhoneVerificationViewModel>();
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final awaitingCode = vm.phase == PhoneVerificationPhase.awaitingCode;
    final verifying = vm.phase == PhoneVerificationPhase.verifying;
    final codeComplete =
        _codeController.text.length == PhoneVerificationViewModel.codeLength;

    // Wrapped in a left-to-right isolate so the number reads correctly inside
    // Arabic text.
    final phone = '${String.fromCharCode(_ltrIsolate)}'
        '${vm.phoneE164 ?? ''}'
        '${String.fromCharCode(_popDirectionalIsolate)}';
    final error = vm.errorKey == null ? null : loc.translate(vm.errorKey!);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(loc.translate('verifyPhoneNumber')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.translate('otpSentTo').replaceAll('{phone}', phone),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: true,
            enabled: awaitingCode || verifying,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            // Digits only, capped at the code length. Pasting "123-456" or a
            // whole SMS line keeps just the digits.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                PhoneVerificationViewModel.codeLength,
              ),
            ],
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 8),
            decoration: InputDecoration(
              labelText: loc.translate('enterOTP'),
              counterText: '',
              errorText: error,
              errorMaxLines: 3,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() {});
              if (value.length == PhoneVerificationViewModel.codeLength) {
                _verify(vm);
              }
            },
            onSubmitted: (_) => _verify(vm),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ResendControl(
              vm: vm,
              onResend: () => _resend(vm),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: verifying
              ? null
              : () {
                  vm.cancel();
                  _close(false);
                },
          child: Text(loc.translate('cancel')),
        ),
        ElevatedButton(
          onPressed: awaitingCode && !vm.isBusy && codeComplete
              ? () => _verify(vm)
              : null,
          child: verifying
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onPrimary,
                  ),
                )
              : Text(loc.translate('verify')),
        ),
      ],
    );
  }
}

class _ResendControl extends StatelessWidget {
  const _ResendControl({required this.vm, required this.onResend});

  final PhoneVerificationViewModel vm;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    if (vm.phase != PhoneVerificationPhase.awaitingCode &&
        vm.phase != PhoneVerificationPhase.verifying) {
      return const SizedBox.shrink();
    }
    if (vm.isResending) {
      return Text(loc.translate('resending'), style: muted);
    }
    if (vm.resendSecondsRemaining > 0) {
      return Text(
        loc
            .translate('resendCodeIn')
            .replaceAll('{seconds}', '${vm.resendSecondsRemaining}'),
        style: muted,
      );
    }
    return TextButton(
      onPressed: vm.canResend ? onResend : null,
      child: Text(loc.translate('resendCode')),
    );
  }
}
