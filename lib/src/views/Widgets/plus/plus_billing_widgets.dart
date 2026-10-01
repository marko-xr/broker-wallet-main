import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// A row inside a grouped settings card on the Subscription & Billing screens.
///
/// Used both for actions (with [onTap], shown with a direction-aware chevron)
/// and for information (without it). Unlike the Profile `SettingsTile` its
/// title and subtitle may wrap, so long Arabic strings and large text scales
/// are never cut off, and its height follows its content.
class PlusActionRow extends StatelessWidget {
  const PlusActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tone = PlusTone.positive,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null makes the row informational: no ripple, no chevron, not a button.
  final VoidCallback? onTap;
  final PlusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = plusToneColor(colors, tone);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: colors.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// A small status pill. [onFilled] draws it for use on the primary-coloured
/// plan summary, where tinted-on-surface colours would not read.
class PlusStatusChip extends StatelessWidget {
  const PlusStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.onFilled = false,
  });

  final String label;
  final PlusTone tone;
  final IconData? icon;
  final bool onFilled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = plusToneColor(colors, tone);
    final foreground = onFilled ? colors.onPrimary : accent;
    final background = onFilled
        ? colors.onPrimary.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;
}

/// The top of Subscription & Billing: which plan the user has, whether it is
/// active, how it is billed and when it renews or ends, in at most three short
/// lines. Everything shown is something the state actually supplied; nothing
/// here is a fixed example, a price or a date.
///
/// Free reads as an intentional plan (an icon, its name, one sentence), not as
/// missing data. An expired plan shows only when it ended, since nothing is
/// billed any more.
class PlusPlanSummaryCard extends StatelessWidget {
  const PlusPlanSummaryCard({
    super.key,
    required this.state,
    required this.store,
  });

  final SubscriptionUiState state;
  final PlusStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final status = state.status;
    final isFree = status == SubscriptionStatus.free;
    final isExpired = status == SubscriptionStatus.expired;
    final onPlus = status.isCurrentPlus;
    final tone = plusStatusTone(status);

    final foreground = onPlus ? colors.onPrimary : colors.onSurface;
    final soft = foreground.withValues(alpha: onPlus ? 0.9 : 0.75);

    final period = state.period;
    final dateLine = plusHeroDateLine(context, l10n, state);
    final billed = !isFree && !isExpired;
    final facts = <_Fact>[
      if (billed && period != null)
        _Fact(
          Icons.sell_outlined,
          plusPeriodPriceLine(l10n, period, state.billingPeriodPrice),
        ),
      if (dateLine != null) _Fact(Icons.event_outlined, dateLine),
      if (billed)
        _Fact(
          Icons.storefront_outlined,
          l10n.plusText('plusBilledThrough', {
            'store': plusStoreName(l10n, store),
          }),
        ),
    ];

    // A cancelled plan is still active: say so, then that it will not renew,
    // instead of one chip that reads like an ending.
    final cancelledActive = status == SubscriptionStatus.cancelledActive;
    final chipStatus = cancelledActive ? SubscriptionStatus.active : status;
    final chips = <Widget>[
      if (!isFree)
        PlusStatusChip(
          label: plusStatusLabel(l10n, chipStatus),
          tone: cancelledActive ? PlusTone.positive : tone,
          icon: plusStatusIcon(chipStatus),
          onFilled: onPlus,
        ),
      if (cancelledActive)
        PlusStatusChip(
          label: plusStatusLabel(l10n, SubscriptionStatus.cancelledActive),
          tone: PlusTone.neutral,
          icon: Icons.autorenew_rounded,
          onFilled: true,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: onPlus ? colors.primary : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: onPlus
            ? null
            : Border.all(color: colors.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: onPlus
                      ? colors.onPrimary.withValues(alpha: 0.18)
                      : plusToneColor(colors, tone).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  onPlus
                      ? Icons.workspace_premium_rounded
                      : Icons.workspace_premium_outlined,
                  color:
                      onPlus ? colors.onPrimary : plusToneColor(colors, tone),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFree
                          ? l10n.translate('freePlan')
                          : l10n.translate('plusBrandName'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: foreground,
                      ),
                    ),
                    if (isFree) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.translate('plusFreeHeroBody'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: soft,
                          height: 1.4,
                        ),
                      ),
                    ] else if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: chips),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: foreground.withValues(alpha: onPlus ? 0.25 : 0.12),
            ),
            const SizedBox(height: 8),
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(fact.icon, size: 18, color: soft),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fact.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Icon, title and a short explanation at the top of a task screen (payment
/// methods, billing history), so the screen says whose it is before it lists
/// anything to do.
class PlusInfoHeader extends StatelessWidget {
  const PlusInfoHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PlusCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlusIconBadge(icon: icon, size: 48, tone: PlusTone.positive),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
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

/// A short note under a group of rows (for example "Broker Wallet never sees
/// your card details"). Quiet and small on purpose.
class PlusFootnote extends StatelessWidget {
  const PlusFootnote(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered step of "how to do this in the store", with the number in a
/// round marker so a list of steps reads in order at a glance.
class PlusStepRow extends StatelessWidget {
  const PlusStepRow({super.key, required this.number, required this.text});

  final int number;
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
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.12),
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
