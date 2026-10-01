import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/subscription/plus_benefit_catalog.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Reusable "this needs Broker Wallet Plus" prompt.
///
/// It only asks; it never navigates or unlocks anything. [show] resolves to
/// true when the user chose to upgrade, and the caller opens the paywall
/// (`PlusNavigation.openPaywall`). That keeps the sheet usable from any
/// existing upgrade entry point without it knowing about routing.
class UpgradeToPlusSheet extends StatelessWidget {
  const UpgradeToPlusSheet({
    super.key,
    required this.title,
    required this.message,
    this.benefit,
  });

  /// What the user ran into, e.g. "Free plan limit reached".
  final String title;

  /// A concise explanation of why Plus is being offered here.
  final String message;

  /// Overrides the default benefit lines with one specific to the feature.
  final String? benefit;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? benefit,
  }) async {
    final upgrade = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpgradeToPlusSheet(
        title: title,
        message: message,
        benefit: benefit,
      ),
    );
    return upgrade ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final benefitLines = benefit != null
        ? <String>[benefit!]
        : [for (final key in PlusCatalog.highlightKeys) l10n.translate(key)];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: PlusIconBadge(
                  icon: Icons.workspace_premium_rounded,
                  size: 64,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.8),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              PlusCard(
                backgroundColor: colors.primary.withValues(alpha: 0.08),
                borderColor: colors.primary.withValues(alpha: 0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('plusBrandName'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final line in benefitLines) PlusCheckRow(line),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PlusPrimaryButton(
                label: l10n.translate('plusUpgradeToPlus'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: colors.onSurface.withValues(alpha: 0.75),
                ),
                child: Text(
                  l10n.translate('notNow'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
