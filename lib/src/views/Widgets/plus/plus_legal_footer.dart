import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';

/// Subscription disclosure, legal links and (optionally) Restore purchases.
///
/// Shown on the paywall and the purchase review so the terms of a
/// subscription are never further than a scroll away from the action. (The
/// Subscription & Billing hub reaches the same information through its Legal
/// screen.)
class PlusLegalFooter extends StatelessWidget {
  const PlusLegalFooter({
    super.key,
    required this.store,
    this.showRestore = false,
  });

  final PlusStore store;
  final bool showRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, store);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('plusSubscriptionInfoTitle'),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.plusText('plusSubscriptionInfoBody', {'store': storeName}),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.7),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            _FooterLink(
              label: l10n.translate('termsConditions'),
              onTap: () => context.push(PlusRoutes.terms),
            ),
            _FooterLink(
              label: l10n.translate('privacyPolicy'),
              onTap: () => context.push(PlusRoutes.privacy),
            ),
            if (showRestore)
              _FooterLink(
                label: l10n.translate('plusRestorePurchases'),
                onTap: () => context.push(PlusRoutes.restore),
              ),
          ],
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
