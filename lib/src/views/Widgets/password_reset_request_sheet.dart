import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_form_field.dart';
import 'package:flutter/material.dart';

/// Asks for the address a password-reset link should go to.
///
/// The confirmation is deliberately the same sentence whether or not an account
/// exists for the address. Saying "no account found" here would turn this sheet
/// into an account-discovery tool for anyone who can open the app.
class PasswordResetRequestSheet extends StatefulWidget {
  const PasswordResetRequestSheet({
    super.key,
    required this.viewModel,
    this.initialEmail = '',
  });

  final PasswordResetRequestViewModel viewModel;
  final String initialEmail;

  @override
  State<PasswordResetRequestSheet> createState() =>
      _PasswordResetRequestSheetState();
}

class _PasswordResetRequestSheetState extends State<PasswordResetRequestSheet> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Material(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (vm.hasSent)
                      ..._sentContent(context, colors, texts, loc)
                    else
                      ..._formContent(context, vm, colors, texts, loc),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _formContent(
    BuildContext context,
    PasswordResetRequestViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return [
      Text(
        loc.translate('forgotPasswordTitle'),
        style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        loc.translate('forgotPasswordDescription'),
        style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      Text(loc.translate('email'), style: texts.labelLarge),
      const SizedBox(height: 6),
      ForceDirectionality(
        direction: TextDirection.ltr,
        child: TextField(
          controller: _emailController,
          enabled: !vm.isSubmitting,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          decoration: InputDecoration(
            hintText: loc.translate('enterEmail'),
            prefixIcon: const Icon(Icons.alternate_email),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: vm.isSubmitting ? null : (_) => _submit(),
        ),
      ),
      if (vm.errorKey != null) ...[
        const SizedBox(height: 12),
        PasswordErrorLine(messageKey: vm.errorKey!),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: vm.isSubmitting ? null : _submit,
        child: vm.isSubmitting
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimary,
                ),
              )
            : Text(loc.translate('sendResetLink')),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed:
            vm.isSubmitting ? null : () => Navigator.of(context).pop(false),
        child: Text(loc.translate('cancel')),
      ),
    ];
  }

  List<Widget> _sentContent(
    BuildContext context,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return [
      Icon(Icons.mark_email_read_outlined, size: 40, color: colors.primary),
      const SizedBox(height: 12),
      Text(
        loc.translate('passwordResetSentTitle'),
        textAlign: TextAlign.center,
        style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        loc.translate('passwordResetGenericSuccess'),
        textAlign: TextAlign.center,
        style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(loc.translate('done')),
      ),
    ];
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await widget.viewModel.submit(_emailController.text);
  }
}
