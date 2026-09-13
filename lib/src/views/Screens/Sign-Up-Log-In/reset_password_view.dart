import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/password_form_field.dart';
import 'package:broker_wallet/src/views/Widgets/password_reset_request_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

/// The destination of a Supabase password-recovery link.
///
/// It is reachable only while [PasswordRecoveryViewModel.holdsRoute] is true,
/// which only a real `AuthChangeEvent.passwordRecovery` or a failed recovery
/// callback can make true. Ordinary authenticated navigation cannot open it,
/// and it releases the route the moment the recovery resolves.
///
/// The screen never mentions a token, a link URL or a provider message. A dead
/// link produces a localized explanation and a way forward, not a dead end.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
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
    final vm = context.watch<PasswordRecoveryViewModel>();

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: colors.surface,
        centerTitle: true,
        title:
            Text(loc.translate('resetPasswordTitle'), style: texts.titleLarge),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: switch (vm.phase) {
            PasswordRecoveryPhase.active =>
              _buildForm(context, vm, colors, texts, loc),
            PasswordRecoveryPhase.linkFailed =>
              _buildLinkFailed(context, vm, colors, texts, loc),
            PasswordRecoveryPhase.completed =>
              _buildCompleted(context, vm, colors, texts, loc),
            // Every phase is named deliberately: without an active recovery
            // there is no form to offer, so none can be built. The router is
            // already redirecting away from this route.
            PasswordRecoveryPhase.none => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    PasswordRecoveryViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_reset_outlined, size: 44, color: colors.primary),
          const SizedBox(height: 14),
          Text(
            loc.translate('resetPasswordHeadline'),
            textAlign: TextAlign.center,
            style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            loc.translate('resetPasswordDescription'),
            textAlign: TextAlign.center,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          PasswordFormField(
            controller: _newController,
            label: loc.translate('newPassword'),
            hint: loc.translate('enterNewPassword'),
            autofillHints: const [AutofillHints.newPassword],
            enabled: !vm.isSubmitting,
            autofocus: true,
            onChanged: (_) {
              vm.clearError();
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          PasswordRequirementChecklist(password: _newController.text),
          const SizedBox(height: 14),
          PasswordFormField(
            controller: _confirmController,
            label: loc.translate('confirmNewPassword'),
            hint: loc.translate('enterConfirmNewPassword'),
            autofillHints: const [AutofillHints.newPassword],
            enabled: !vm.isSubmitting,
            textInputAction: TextInputAction.done,
            onChanged: (_) => vm.clearError(),
            onSubmitted: vm.isSubmitting ? null : (_) => _submit(vm),
          ),
          if (vm.errorKey != null) ...[
            const SizedBox(height: 12),
            PasswordErrorLine(messageKey: vm.errorKey!),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: vm.isSubmitting ? null : () => _submit(vm),
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
          // The only way out of a recovery without setting a password. It is
          // the same secondary action the failed-link state already offers, and
          // it signs the recovery session out rather than abandoning it.
          TextButton(
            onPressed: vm.isSubmitting ? null : vm.dismiss,
            child: Text(loc.translate('backToLogin')),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkFailed(
    BuildContext context,
    PasswordRecoveryViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.link_off_rounded, size: 44, color: colors.error),
        const SizedBox(height: 14),
        Text(
          loc.translate('resetLinkExpiredTitle'),
          textAlign: TextAlign.center,
          style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          loc.translate(vm.errorKey ?? 'resetLinkExpiredMessage'),
          textAlign: TextAlign.center,
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => _openResetRequest(context),
          child: Text(loc.translate('requestNewResetLink')),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: vm.dismiss,
          child: Text(loc.translate('backToLogin')),
        ),
      ],
    );
  }

  Widget _buildCompleted(
    BuildContext context,
    PasswordRecoveryViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.verified_outlined, size: 44, color: colors.primary),
        const SizedBox(height: 14),
        Text(
          loc.translate('resetPasswordSuccessTitle'),
          textAlign: TextAlign.center,
          style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          loc.translate('resetPasswordSuccessMessage'),
          textAlign: TextAlign.center,
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: vm.dismiss,
          child: Text(loc.translate('continueLabel')),
        ),
      ],
    );
  }

  Future<void> _submit(PasswordRecoveryViewModel vm) async {
    FocusScope.of(context).unfocus();
    // Resolved while this route is certainly alive. A successful reset signs
    // the recovery session out, so GoRouter moves to Sign In and disposes this
    // screen; the toast needs no context and survives that.
    final message = AppLocalizations.of(
      context,
    ).translate('passwordResetSignInPrompt');

    final succeeded = await vm.submitNewPassword(
      newPassword: _newController.text,
      confirmPassword: _confirmController.text,
    );
    if (!succeeded) return;
    TextInput.finishAutofillContext();
    Fluttertoast.showToast(
      msg: message,
      backgroundColor: Colors.green,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  Future<void> _openResetRequest(BuildContext context) async {
    final repository = RepositoryProvider.instance.authRepository;
    final viewModel = PasswordResetRequestViewModel(
      gateway: passwordCapabilityOf(repository),
    );
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PasswordResetRequestSheet(viewModel: viewModel),
    );
    viewModel.dispose();
  }
}
