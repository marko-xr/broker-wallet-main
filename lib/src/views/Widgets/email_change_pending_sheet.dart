import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart';
import 'package:flutter/material.dart';

/// The focused detail view for an email change that is waiting on confirmation.
///
/// Edit Profile only carries a one-line indicator; everything explanatory and
/// every recovery action lives here, so the settings screen stays a settings
/// screen. There is no "Cancel email change" action because Supabase exposes no
/// server-side cancellation — offering one would be a lie about backend state.
class EmailChangePendingSheet extends StatefulWidget {
  const EmailChangePendingSheet({
    super.key,
    required this.viewModel,
    this.onUseDifferentEmail,
  });

  final EmailChangeViewModel viewModel;

  /// Opens the request sheet again. A fresh request replaces the pending one
  /// server-side, so this is a real recovery path rather than a cancellation.
  final VoidCallback? onUseDifferentEmail;

  @override
  State<EmailChangePendingSheet> createState() =>
      _EmailChangePendingSheetState();
}

class _EmailChangePendingSheetState extends State<EmailChangePendingSheet> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onChanged);
    super.dispose();
  }

  /// Closes as soon as the change actually completes, so the sheet can never
  /// keep showing pending copy for a change that already landed.
  void _onChanged() {
    if (!mounted) return;
    if (widget.viewModel.justCompleted) {
      widget.viewModel.acknowledgeCompletion();
      Navigator.of(context).maybePop(true);
    }
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
        return Material(
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
                    loc.translate('emailChangePendingTitle'),
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TransitionCard(
                    from: vm.confirmedEmail,
                    to: vm.pendingEmail ?? '',
                    colors: colors,
                    texts: texts,
                    loc: loc,
                  ),
                  const SizedBox(height: 14),
                  _Bullet(
                    icon: Icons.mark_email_read_outlined,
                    text: loc.translate('emailChangeBothInboxes'),
                    colors: colors,
                    texts: texts,
                  ),
                  const SizedBox(height: 8),
                  _Bullet(
                    icon: Icons.verified_user_outlined,
                    text: loc.translate('emailChangeCanonicalGuidance'),
                    colors: colors,
                    texts: texts,
                  ),
                  if (vm.errorKey != null) ...[
                    const SizedBox(height: 14),
                    _Banner(
                      text: loc.translate(vm.errorKey!),
                      background: colors.errorContainer.withValues(alpha: 0.5),
                      foreground: colors.onErrorContainer,
                      icon: Icons.error_outline,
                      texts: texts,
                    ),
                  ] else if (vm.noticeKey != null) ...[
                    const SizedBox(height: 14),
                    _Banner(
                      text: loc.translate(vm.noticeKey!),
                      background: colors.primary.withValues(alpha: 0.10),
                      foreground: colors.primary,
                      icon: Icons.info_outline,
                      texts: texts,
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: vm.isBusy ? null : () => vm.checkStatus(),
                    child: vm.isCheckingStatus
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : Text(loc.translate('emailChangeCheckStatus')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed:
                        vm.canResend ? () => vm.resendEmailChange() : null,
                    child: Text(_resendLabel(vm, loc)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.translate('emailChangeResendReplacesLinks'),
                    textAlign: TextAlign.center,
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (widget.onUseDifferentEmail != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: vm.isBusy
                          ? null
                          : () {
                              Navigator.of(context).pop(false);
                              widget.onUseDifferentEmail!();
                            },
                      child: Text(loc.translate('emailChangeUseDifferent')),
                    ),
                  ],
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(loc.translate('close')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _resendLabel(EmailChangeViewModel vm, AppLocalizations loc) {
    if (vm.isResending) return loc.translate('resending');
    if (vm.resendSecondsRemaining > 0) {
      return loc
          .translate('resendEmailChangeIn')
          .replaceAll('{seconds}', '${vm.resendSecondsRemaining}');
    }
    return loc.translate('resendEmailChange');
  }
}

/// `current → new`, laid out so the confirmed address always reads as the one
/// that is still in force.
class _TransitionCard extends StatelessWidget {
  const _TransitionCard({
    required this.from,
    required this.to,
    required this.colors,
    required this.texts,
    required this.loc,
  });

  final String from;
  final String to;
  final ColorScheme colors;
  final TextTheme texts;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            label: loc.translate('currentEmail'),
            value: from,
            valueColor: colors.onSurface,
            badge: loc.translate('emailChangeActiveBadge'),
            badgeColor: colors.primary,
          ),
          Padding(
            padding:
                const EdgeInsetsDirectional.only(start: 2, top: 6, bottom: 6),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ),
          _row(
            label: loc.translate('newEmail'),
            value: to,
            valueColor: colors.onSurfaceVariant,
            badge: loc.translate('emailChangeAwaitingBadge'),
            badgeColor: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String label,
    required String value,
    required Color valueColor,
    required String badge,
    required Color badgeColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style:
                    texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: texts.labelSmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // An address is never Arabic text; forcing LTR keeps it readable in RTL.
        ForceDirectionality(
          direction: TextDirection.ltr,
          child: Text(
            value,
            style: texts.bodyLarge?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.text,
    required this.colors,
    required this.texts,
  });

  final IconData icon;
  final String text;
  final ColorScheme colors;
  final TextTheme texts;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.texts,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;
  final TextTheme texts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: texts.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
