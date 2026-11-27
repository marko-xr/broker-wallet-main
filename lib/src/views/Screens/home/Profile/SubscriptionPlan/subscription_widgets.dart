import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum SubTone { neutral, positive, attention }

/// Readable tone colour: the accent mixed toward the text colour, so small
/// labels keep their contrast in both themes.
Color subToneColor(ColorScheme colors, SubTone tone) => switch (tone) {
      SubTone.neutral => colors.onSurface.withValues(alpha: 0.72),
      SubTone.positive => Color.lerp(colors.primary, colors.onSurface, 0.3)!,
      SubTone.attention => colors.error,
    };

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSample = SubscriptionScope.of(context).isSample;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SafeArea(
        // On a wide browser window the module keeps its phone-width column.
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: kIsWeb ? 640 : double.infinity,
            ),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                if (isSample) const _SampleBanner(),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SubNotice(
        icon: Icons.visibility_outlined,
        text: loc.translate('subSampleBanner'),
        tone: SubTone.attention,
      ),
    );
  }
}

class SubHeading extends StatelessWidget {
  const SubHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class SubSection extends StatelessWidget {
  const SubSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Semantics(
          header: true,
          child: SettingsSectionHeader(title: title),
        ),
      );
}

class SubBodyText extends StatelessWidget {
  const SubBodyText(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
        height: 1.45,
      ),
    );
  }
}

/// The module's card. The border width never changes between looks, so a
/// selection cannot resize it.
class SubCard extends StatelessWidget {
  const SubCard({
    super.key,
    required this.child,
    this.tinted = false,
    this.selected = false,
  });

  final Widget child;
  final bool tinted;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: subCardDecoration(colors, tinted: tinted, selected: selected),
      child: child,
    );
  }
}

BoxDecoration subCardDecoration(
  ColorScheme colors, {
  bool tinted = false,
  bool selected = false,
}) {
  return BoxDecoration(
    color: tinted ? colors.primary.withValues(alpha: 0.1) : colors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      width: 1.5,
      color: selected
          ? colors.primary
          : tinted
              ? Colors.transparent
              : colors.onSurface.withValues(alpha: 0.08),
    ),
  );
}

class SubPill extends StatelessWidget {
  const SubPill(this.label, {super.key, this.tone = SubTone.neutral});

  final String label;
  final SubTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = subToneColor(theme.colorScheme, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SubPlanHero extends StatelessWidget {
  const SubPlanHero({
    super.key,
    required this.pill,
    required this.title,
    required this.body,
    this.tone = SubTone.neutral,
    this.tinted = false,
    this.children = const [],
  });

  final String pill;
  final String title;
  final String body;
  final SubTone tone;
  final bool tinted;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SubCard(
      tinted: tinted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubPill(pill, tone: tone),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SubBodyText(body),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...children,
          ],
        ],
      ),
    );
  }
}

class SubInfoRow extends StatelessWidget {
  const SubInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Side by side would split words on narrow, large-text layouts.
            if (constraints.maxWidth / scale < 200) {
              return SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SubBodyText(label),
                    const SizedBox(height: 2),
                    Text(value, style: style),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SubBodyText(label)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(value, textAlign: TextAlign.end, style: style),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SubBullet extends StatelessWidget {
  const SubBullet(
    this.text, {
    super.key,
    this.icon = Icons.check_rounded,
    this.tone = SubTone.positive,
  });

  final String text;
  final IconData icon;
  final SubTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 20, color: subToneColor(colors, tone)),
          ),
          const SizedBox(width: 10),
          Expanded(child: SubBodyText(text)),
        ],
      ),
    );
  }
}

class SubNotice extends StatelessWidget {
  const SubNotice({
    super.key,
    required this.icon,
    required this.text,
    this.tone = SubTone.positive,
  });

  final IconData icon;
  final String text;
  final SubTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = subToneColor(theme.colorScheme, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared honest notice for any store action that does not exist yet.
class SubNotConnectedNotice extends StatelessWidget {
  const SubNotConnectedNotice({super.key, this.textKey = 'subStoreNotLinked'});

  final String textKey;

  @override
  Widget build(BuildContext context) => SubNotice(
        icon: Icons.info_outline_rounded,
        text: AppLocalizations.of(context).translate(textKey),
      );
}

class SubPrimaryButton extends StatelessWidget {
  const SubPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.animateLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Cross-fades the label when it changes, as the payment sheet's CTA does.
  final bool animateLabel;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, key: ValueKey(label), textAlign: TextAlign.center);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: animateLabel
            ? AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: text,
              )
            : text,
      ),
    );
  }
}

class SubSecondaryButton extends StatelessWidget {
  const SubSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onPressed,
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
}

/// A navigation row. Without [onTap] it reads as not yet available.
class SubNavTile extends StatelessWidget {
  const SubNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // The shared tile keeps a fixed icon column, so very large text would
    // split words. The limit stays local to this module's rows.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SettingsTile(
        grouped: true,
        iconAsset: SvgIcon.subscription,
        materialIcon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        hasTrailing: onTap == null,
        trailingWidget: onTap == null
            ? ExcludeSemantics(
                child: Icon(
                  Icons.lock_clock_outlined,
                  size: 20,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
              )
            : null,
      ),
    );
  }
}

/// Centered icon, title and explanation for a state screen.
class SubMessage extends StatelessWidget {
  const SubMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tone = SubTone.positive,
  });

  final IconData icon;
  final String title;
  final String body;
  final SubTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = subToneColor(theme.colorScheme, tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          SubBodyText(body, center: true),
        ],
      ),
    );
  }
}

/// Static placeholder bars for loading states.
class SubSkeleton extends StatelessWidget {
  const SubSkeleton({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Semantics(
      label: loc.translate('subLoading'),
      child: ExcludeSemantics(
        child: SubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: FractionallySizedBox(
                    widthFactor: i.isEven ? 0.8 : 0.55,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors.onSurface.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category's lifetime creation usage. A null [used] means no trusted
/// count exists and is never drawn as zero.
class SubUsageRow extends StatelessWidget {
  const SubUsageRow({
    super.key,
    required this.category,
    required this.used,
    this.showRemaining = false,
  });

  final UsageCategory category;
  final int? used;

  /// Words the count as what is left instead of what was used.
  final bool showRemaining;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const limit = SubscriptionPolicy.freeCreationsPerCategory;
    final count = used;
    final atLimit = count != null && count >= limit;
    final value = count == null
        ? loc.translate('subUsageNotAvailable')
        : showRemaining
            ? loc.fill('subRemainingOf', {
                'remaining': '${(limit - count).clamp(0, limit)}',
                'limit': '$limit',
              })
            : loc.fill('subUsedOf', {'used': '$count', 'limit': '$limit'});
    final name = loc.categoryName(category);
    return Semantics(
      label: '$name, $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface
                            .withValues(alpha: atLimit ? 1 : 0.7),
                        fontWeight: atLimit ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: count == null ? 0 : (count / limit).clamp(0.0, 1.0),
                  backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                  color: atLimit ? colors.onSurface : colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubUsageList extends StatelessWidget {
  const SubUsageList({
    super.key,
    required this.usage,
    this.showRemaining = false,
  });

  final UsageSnapshot usage;
  final bool showRemaining;

  @override
  Widget build(BuildContext context) => SubCard(
        child: Column(
          children: [
            for (final category in UsageCategory.values)
              SubUsageRow(
                category: category,
                used: usage.createdFor(category),
                showRemaining: showRemaining,
              ),
          ],
        ),
      );
}

/// Three segments: the per-item Free edit allowance.
class SubEditMeter extends StatelessWidget {
  const SubEditMeter({super.key, required this.used});

  final int used;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < SubscriptionPolicy.freeEditsPerItem; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < used
                    ? (used >= SubscriptionPolicy.freeEditsPerItem
                        ? colors.onSurface
                        : colors.primary)
                    : colors.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
