import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Changes the password of the signed-in account.
///
/// Focused on exactly one job. It asks for the current password only when the
/// backend will actually check it, so the form never demands a secret that
/// would be discarded server-side.
///
/// Nothing typed here is stored, cached or logged: the controllers are disposed
/// with the sheet and the values go nowhere but the Supabase Auth call.
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key, required this.viewModel});

  final ChangePasswordViewModel viewModel;

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
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
                child: AutofillGroup(
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
                        loc.translate('changePassword'),
                        style: texts.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        loc.translate('changePasswordDescription'),
                        style: texts.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (vm.requiresCurrentPassword) ...[
                        PasswordFormField(
                          controller: _currentController,
                          label: loc.translate('currentPassword'),
                          hint: loc.translate('enterCurrentPassword'),
                          autofillHints: const [AutofillHints.password],
                          enabled: !vm.isSubmitting,
                          autofocus: true,
                          onChanged: (_) => vm.clearError(),
                        ),
                        const SizedBox(height: 14),
                      ],
                      PasswordFormField(
                        controller: _newController,
                        label: loc.translate('newPassword'),
                        hint: loc.translate('enterNewPassword'),
                        autofillHints: const [AutofillHints.newPassword],
                        enabled: !vm.isSubmitting,
                        autofocus: !vm.requiresCurrentPassword,
                        onChanged: (_) {
                          vm.clearError();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      PasswordRequirementChecklist(
                        password: _newController.text,
                      ),
                      const SizedBox(height: 14),
                      PasswordFormField(
                        controller: _confirmController,
                        label: loc.translate('confirmNewPassword'),
                        hint: loc.translate('enterConfirmNewPassword'),
                        autofillHints: const [AutofillHints.newPassword],
                        enabled: !vm.isSubmitting,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => vm.clearError(),
                        onSubmitted: vm.isSubmitting ? null : (_) => _submit(),
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
                            : Text(loc.translate('updatePassword')),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: vm.isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(loc.translate('cancel')),
                      ),
                    ],
                  ),
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
    final succeeded = await widget.viewModel.submit(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
      confirmPassword: _confirmController.text,
    );
    if (!succeeded || !mounted) return;
    // The password manager is told the change landed only after Supabase
    // confirmed it, so a saved credential can never get ahead of the account.
    TextInput.finishAutofillContext();
    Navigator.of(context).pop(true);
  }
}
