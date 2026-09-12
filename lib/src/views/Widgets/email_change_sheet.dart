import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart';
import 'package:flutter/material.dart';

/// Collects a replacement address for an already signed-in Supabase account.
///
/// The current address stays read-only and authoritative until Supabase reports
/// that the change has completed. This sheet never asks for or handles a
/// password because email-change confirmation is owned by Supabase Auth.
///
/// It closes as soon as the request is accepted: the pending state belongs to
/// the pending sheet, not to a form that would otherwise sit there looking
/// editable while the backend is already waiting on two mailboxes.
class EmailChangeSheet extends StatefulWidget {
  const EmailChangeSheet({
    super.key,
    required this.viewModel,
  });

  final EmailChangeViewModel viewModel;

  @override
  State<EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<EmailChangeSheet> {
  final _emailController = TextEditingController();

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
                    Text(
                      loc.translate('changeEmail'),
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _CurrentEmailRow(
                      email: vm.confirmedEmail,
                      colors: colors,
                      texts: texts,
                      loc: loc,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      loc.translate('newEmail'),
                      style: texts.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    ForceDirectionality(
                      direction: TextDirection.ltr,
                      child: TextField(
                        controller: _emailController,
                        enabled: !vm.isBusy,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          hintText: loc.translate('enterNewEmail'),
                          prefixIcon: const Icon(Icons.alternate_email),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: vm.isBusy ? null : (_) => _submit(),
                      ),
                    ),
                    if (vm.errorKey != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: colors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loc.translate(vm.errorKey!),
                              style: texts.bodySmall
                                  ?.copyWith(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.translate('emailChangeMailboxGuidance'),
                            style: texts.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: vm.isBusy ? null : _submit,
                      child: vm.isRequesting
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : Text(loc.translate('emailChangeSubmit')),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: vm.isBusy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(loc.translate('cancel')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final succeeded =
        await widget.viewModel.requestEmailChange(_emailController.text);
    if (succeeded && mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _CurrentEmailRow extends StatelessWidget {
  const _CurrentEmailRow({
    required this.email,
    required this.colors,
    required this.texts,
    required this.loc,
  });

  final String email;
  final ColorScheme colors;
  final TextTheme texts;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.translate('currentEmail'),
                  style:
                      texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                ForceDirectionality(
                  direction: TextDirection.ltr,
                  child: Text(
                    email,
                    style: texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
