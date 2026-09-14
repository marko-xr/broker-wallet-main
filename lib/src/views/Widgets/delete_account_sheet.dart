import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/delete_account_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_form_field.dart';

/// Opens the Delete Account flow for the signed-in account.
///
/// The flow is a sheet over the Profile tab. When the server has deleted the
/// account, `AuthViewModel` ends the session and GoRouter's existing redirect
/// moves the app to the logged-out entry, which also removes this sheet.
Future<void> showDeleteAccountFlow(
  BuildContext context, {
  AccountDeletionGateway? gateway,
}) async {
  final authViewModel = context.read<AuthViewModel>();
  final localization = AppLocalizations.of(context);
  final deletedMessage = localization.translate('deleteAccountDeletedToast');
  final unconfirmedMessage =
      localization.translate('deleteAccountUnconfirmedToast');
  final viewModel = DeleteAccountViewModel(
    gateway: gateway ?? WorkerAccountDeletionGateway(),
    session: authViewModel,
  );

  try {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Drag-to-dismiss bypasses PopScope, so it is off. The barrier still
      // closes the sheet, through PopScope, whenever no deletion is running.
      enableDrag: false,
      builder: (_) => DeleteAccountSheet(
        viewModel: viewModel,
        email: authViewModel.currentUser?.email ?? '',
      ),
    );
    if (viewModel.isCompleted) {
      Fluttertoast.showToast(msg: deletedMessage);
    } else if (viewModel.endedUnconfirmed) {
      Fluttertoast.showToast(msg: unconfirmedMessage);
    }
  } finally {
    viewModel.dispose();
  }
}

/// Two deliberate steps: what will be deleted, then password plus an explicit
/// acknowledgement. No single tap can delete an account.
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({
    super.key,
    required this.viewModel,
    required this.email,
  });

  final DeleteAccountViewModel viewModel;
  final String email;

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return PopScope(
          canPop: !vm.isDeleting,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Material(
              color: colors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
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
                      if (vm.step == DeleteAccountStep.review)
                        _ReviewStep(viewModel: vm)
                      else
                        _confirmStep(context, vm),
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

  Widget _confirmStep(BuildContext context, DeleteAccountViewModel vm) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);
    final canSubmit = !vm.isDeleting &&
        vm.acknowledged &&
        _passwordController.text.isNotEmpty;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            loc.translate('deleteAccountConfirmTitle'),
            style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            loc.translate('deleteAccountConfirmDescription'),
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (widget.email.isNotEmpty) ...[
            const SizedBox(height: 4),
            ForceDirectionality(
              direction: TextDirection.ltr,
              child: Text(
                widget.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: Directionality.of(context) == TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left,
                style: texts.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          PasswordFormField(
            controller: _passwordController,
            label: loc.translate('password'),
            hint: loc.translate('enterPassword'),
            autofillHints: const [AutofillHints.password],
            enabled: !vm.isDeleting,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              vm.clearError();
              setState(() {});
            },
            onSubmitted: canSubmit ? (_) => _submit() : null,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: vm.acknowledged,
            onChanged:
                vm.isDeleting ? null : (value) => vm.setAcknowledged(value!),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: colors.error,
            title: Text(
              loc.translate('deleteAccountAcknowledge'),
              style: texts.bodySmall?.copyWith(color: colors.onSurface),
            ),
          ),
          if (vm.errorKey != null) ...[
            const SizedBox(height: 4),
            PasswordErrorLine(messageKey: vm.errorKey!),
          ],
          if (vm.isDeleting) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.error,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.translate('deleteAccountDeleting'),
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: canSubmit ? _submit : null,
            child: vm.isDeleting
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onError,
                    ),
                  )
                : Text(loc.translate('deleteAccountConfirmButton')),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: vm.isDeleting ? null : vm.backToReview,
            child: Text(loc.translate('deleteAccountBack')),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final password = _passwordController.text;
    final deleted = await widget.viewModel.submit(password: password);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
      return;
    }
    if (widget.viewModel.errorKey == 'deleteAccountErrorPassword') {
      _passwordController.clear();
      setState(() {});
    }
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.viewModel});

  final DeleteAccountViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_outline_rounded, color: colors.error),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          loc.translate('deleteAccountTitle'),
          style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          loc.translate('deleteAccountIntro'),
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _DeletedItem(
          icon: Icons.person_outline_rounded,
          text: loc.translate('deleteAccountItemProfile'),
        ),
        _DeletedItem(
          icon: Icons.home_work_outlined,
          text: loc.translate('deleteAccountItemListings'),
        ),
        _DeletedItem(
          icon: Icons.favorite_border_rounded,
          text: loc.translate('deleteAccountItemActivity'),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: colors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.translate('deleteAccountIrreversible'),
                  style: texts.bodySmall?.copyWith(
                    color: colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          loc.translate('deleteAccountSubscriptionNote'),
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (viewModel.errorKey != null) ...[
          const SizedBox(height: 12),
          PasswordErrorLine(messageKey: viewModel.errorKey!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: viewModel.continueToConfirmation,
          child: Text(loc.translate('deleteAccountContinue')),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(false),
          child: Text(loc.translate('cancel')),
        ),
      ],
    );
  }
}

class _DeletedItem extends StatelessWidget {
  const _DeletedItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
