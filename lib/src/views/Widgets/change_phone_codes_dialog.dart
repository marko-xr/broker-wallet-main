import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/change_phone_viewmodel.dart';

/// Code step of Change Phone: the code sent to the current number and the
/// code sent to the new number, in the same dialog style as Add Phone's code
/// step. Pops `true` only when the server changed the number.
///
/// Presentation only: validation, single-flight, the resend countdown and
/// session ownership belong to [ChangePhoneViewModel].
class ChangePhoneCodesDialog extends StatefulWidget {
  const ChangePhoneCodesDialog({super.key});

  @override
  State<ChangePhoneCodesDialog> createState() => _ChangePhoneCodesDialogState();
}

class _ChangePhoneCodesDialogState extends State<ChangePhoneCodesDialog> {
  /// U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE.
  static const int _ltrIsolate = 0x2066;
  static const int _popDirectionalIsolate = 0x2069;

  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    super.dispose();
  }

  String _isolated(String? phone) => '${String.fromCharCode(_ltrIsolate)}'
      '${phone ?? ''}'
      '${String.fromCharCode(_popDirectionalIsolate)}';

  Future<void> _verify(ChangePhoneViewModel vm) async {
    final changed = await vm.verify(
      currentCode: _currentController.text,
      newCode: _newController.text,
    );
    if (changed && mounted) _close(true);
  }

  Future<void> _resend(ChangePhoneViewModel vm) async {
    final colors = Theme.of(context).colorScheme;
    final sentMessage = AppLocalizations.of(context).translate('otpResent');
    final resent = await vm.resendCodes();
    if (!resent || !mounted) return;
    _currentController.clear();
    _newController.clear();
    setState(() {});
    Fluttertoast.showToast(
      msg: sentMessage,
      backgroundColor: colors.primary,
      textColor: colors.onPrimary,
    );
  }

  void _close(bool changed) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(changed);
  }

  Widget _codeField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required bool enabled,
    required bool autofocus,
    required VoidCallback onSubmit,
  }) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(ChangePhoneViewModel.codeLength),
          ],
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 8),
          decoration: InputDecoration(
            labelText: loc.translate('enterOTP'),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => onSubmit(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChangePhoneViewModel>();
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final awaiting = vm.phase == ChangePhonePhase.awaitingCodes;
    final verifying = vm.phase == ChangePhonePhase.verifying;
    final needsCurrent = !vm.currentNumberProven;
    const length = ChangePhoneViewModel.codeLength;
    final complete = _newController.text.length == length &&
        (!needsCurrent || _currentController.text.length == length);
    final error = vm.errorKey == null ? null : loc.translate(vm.errorKey!);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(loc.translate('changePhoneNumber')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (needsCurrent) ...[
              _codeField(
                context: context,
                controller: _currentController,
                label: loc
                    .translate('changePhoneCurrentCode')
                    .replaceAll('{phone}', _isolated(vm.currentPhoneE164)),
                enabled: awaiting || verifying,
                autofocus: true,
                onSubmit: () => _verify(vm),
              ),
              const SizedBox(height: 16),
            ],
            _codeField(
              context: context,
              controller: _newController,
              label: loc
                  .translate('changePhoneNewCode')
                  .replaceAll('{phone}', _isolated(vm.newPhoneE164)),
              enabled: awaiting || verifying,
              autofocus: !needsCurrent,
              onSubmit: () => _verify(vm),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _ResendControl(vm: vm, onResend: () => _resend(vm)),
            ),
          ],
        ),
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
          onPressed:
              awaiting && !vm.isBusy && complete ? () => _verify(vm) : null,
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

  final ChangePhoneViewModel vm;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    if (vm.phase != ChangePhonePhase.awaitingCodes &&
        vm.phase != ChangePhonePhase.verifying) {
      return const SizedBox.shrink();
    }
    if (vm.isResending) return Text(loc.translate('resending'), style: muted);
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
