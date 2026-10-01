import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';

/// Small building blocks shared by every Plus screen. They use only the app
/// theme (colour scheme, text theme) so light, dark and RTL behave like the
/// rest of Broker Wallet.

class PlusCard extends StatelessWidget {
  const PlusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? colors.outline.withValues(alpha: 0.18),
        ),
      ),
      child: child,
    );
  }
}

class PlusSectionTitle extends StatelessWidget {
  const PlusSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// A quiet label above a group of rows ("Payment methods in Google Play"):
/// smaller and softer than [PlusSectionTitle], so a screen with several groups
/// reads as one calm list rather than a stack of headings.
class PlusSectionLabel extends StatelessWidget {
  const PlusSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// Full-width primary action. Shows a spinner and ignores taps while
/// [isLoading], which is what stops a repeated tap from doing anything twice.
class PlusPrimaryButton extends StatelessWidget {
  const PlusPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.primary.withValues(alpha: 0.3),
        disabledForegroundColor: colors.onPrimary.withValues(alpha: 0.85),
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onPrimary,
              ),
            )
          : Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
    );
  }
}

class PlusSecondaryButton extends StatelessWidget {
  const PlusSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }
}

/// Round icon holder used in headers and result screens.
class PlusIconBadge extends StatelessWidget {
  const PlusIconBadge({
    super.key,
    required this.icon,
    this.tone = PlusTone.positive,
    this.size = 72,
  });

  final IconData icon;
  final PlusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = plusToneColor(Theme.of(context).colorScheme, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
      ),
      child: Icon(icon, color: accent, size: size * 0.5),
    );
  }
}

/// Broker Wallet Plus identity block at the top of the paywall.
class PlusHero extends StatelessWidget {
  const PlusHero({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.12),
          ),
          child: Center(
            child: SvgPicture.asset(
              SvgIcon.premiumPlan,
              width: 28,
              height: 28,
              colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.translate('plusBrandName'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.translate('plusHeroSubtitle'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.75),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// A status or information card with an optional single action.
class PlusNoticeCard extends StatelessWidget {
  const PlusNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = PlusTone.neutral,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final PlusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = plusToneColor(colors, tone);
    final hasAction = actionLabel != null && onAction != null;

    // A payment problem is calm, not alarming: a faint tint and a soft edge.
    final attention = tone == PlusTone.attention;
    return PlusCard(
      backgroundColor: accent.withValues(alpha: attention ? 0.06 : 0.08),
      borderColor: accent.withValues(alpha: attention ? 0.28 : 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        body!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasAction) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown only while the debug preview is driving the screen.
class PlusPreviewBanner extends StatelessWidget {
  const PlusPreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science_outlined,
            size: 18,
            color: colors.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('plusPreviewNotice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label on one side, value on the other; wraps cleanly for long Arabic text
/// and large font scales.
class PlusDetailRow extends StatelessWidget {
  const PlusDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlusCheckRow extends StatelessWidget {
  const PlusCheckRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
