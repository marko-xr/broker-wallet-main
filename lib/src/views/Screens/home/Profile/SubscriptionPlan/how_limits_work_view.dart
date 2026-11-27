import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';

class HowLimitsWorkView extends StatelessWidget {
  const HowLimitsWorkView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    String t(String key) => loc.translate(key);
    return SubscriptionPage(
      title: t('subHowLimitsTitle'),
      children: [
        SubHeading(t('subHowLimitsTitle')),
        const SizedBox(height: 8),
        SubBodyText(t('subLimitsIntro')),
        _LimitSection(
          icon: Icons.add_circle_outline_rounded,
          title: t('subLimitsCreationTitle'),
          body: t('subLimitsCreationBody'),
          bullets: [
            t('subLimitsCreationCategories'),
            t('subLimitsCreationIndependent'),
          ],
        ),
        _LimitSection(
          icon: Icons.delete_outline_rounded,
          title: t('subLimitsDeleteTitle'),
          body: t('subLimitsDeleteBody'),
          example: t('subLimitsDeleteExample'),
        ),
        _LimitSection(
          icon: Icons.edit_outlined,
          title: t('subLimitsEditsTitle'),
          body: t('subLimitsEditsBody'),
          example: t('subLimitsEditsExample'),
          bullets: [
            t('subLimitsEditsCounts'),
            t('subLimitsEditsNotCounted'),
            t('subLimitsEditsNoChange'),
          ],
        ),
        _LimitSection(
          icon: Icons.document_scanner_outlined,
          title: t('subLimitsToolkitTitle'),
          body: t('subLimitsToolkitBody'),
          bullets: [
            t('subLimitsToolkitBlocked'),
            t('subLimitsToolkitKeep'),
            t('subLimitsToolkitDelete'),
            t('subLimitsToolkitEdits'),
            t('subLimitsToolkitFailed'),
          ],
        ),
        _LimitSection(
          icon: Icons.workspace_premium_outlined,
          title: t('subLimitsPlusTitle'),
          body: t('subLimitsPlusBody'),
          bullets: [t('subLimitsPlusEdits')],
        ),
        _LimitSection(
          icon: Icons.history_toggle_off_rounded,
          title: t('subLimitsExpiryTitle'),
          body: t('subExpiredMessage'),
          bullets: [
            t('subLimitsExpiryKeep'),
            t('subLimitsExpiryWithin'),
          ],
        ),
        _LimitSection(
          icon: Icons.verified_user_outlined,
          title: t('subLimitsAlwaysTitle'),
          body: t('subLimitsAlwaysBody'),
        ),
      ],
    );
  }
}

class _LimitSection extends StatelessWidget {
  const _LimitSection({
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const [],
    this.example,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
  final String? example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 22, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SubBodyText(body),
            if (example != null) ...[
              const SizedBox(height: 10),
              SubNotice(icon: Icons.lightbulb_outline_rounded, text: example!),
            ],
            if (bullets.isNotEmpty) const SizedBox(height: 6),
            for (final bullet in bullets) SubBullet(bullet),
          ],
        ),
      ),
    );
  }
}
