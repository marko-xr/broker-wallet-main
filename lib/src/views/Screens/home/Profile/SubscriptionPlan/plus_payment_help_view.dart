import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Payment method help: short answers to the usual payment questions, each with
/// the one screen that deals with it, and the way to reach Broker Wallet
/// support.
///
/// Topics open one at a time so the screen stays a short list. Every answer
/// ends in an action that leads to a real screen (add, manage, billing, backup,
/// subscription), and "Contact support" opens the existing Help & Support. It
/// invents no phone number, email address, ticket or chat. The Google Play
/// backup-payment-method topic is shown only on Google Play.
class PlusPaymentHelpView extends StatelessWidget {
  const PlusPaymentHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final store = vm.effectiveStore;
    final storeName = plusStoreName(l10n, store);

    final String addAnswerKey;
    final String changeAnswerKey;
    switch (store) {
      case PlusStore.googlePlay:
        addAnswerKey = 'plusPmAnswerAddGoogle';
        changeAnswerKey = 'plusPmAnswerChangeGoogle';
      case PlusStore.appStore:
        addAnswerKey = 'plusPmAnswerAddApple';
        changeAnswerKey = 'plusPmAnswerChangeApple';
      case PlusStore.unknown:
        addAnswerKey = 'plusPmAnswerAddGeneric';
        changeAnswerKey = 'plusPmAnswerChangeGeneric';
    }

    final topics = <_Topic>[
      _Topic(
        title: l10n.translate('plusPayAddTitle'),
        answer: l10n.translate(addAnswerKey),
        actionLabel: l10n.translate('plusPayAddTitle'),
        route: PlusRoutes.paymentMethodsAdd,
      ),
      _Topic(
        title: l10n.translate('plusPmHelpChange'),
        answer: l10n.translate(changeAnswerKey),
        actionLabel: l10n.translate('plusPayManageTitle'),
        route: PlusRoutes.paymentMethodsManage,
      ),
      _Topic(
        title: l10n.translate('plusPmHelpDeclined'),
        answer: l10n.plusText('plusPmAnswerDeclined', {'store': storeName}),
        actionLabel: l10n.translate('plusPayUpdateTitle'),
        route: PlusRoutes.paymentMethodsManage,
      ),
      _Topic(
        title: l10n.translate('plusPmHelpBillingIssue'),
        answer: l10n.plusText('plusPmAnswerBillingIssue', {
          'store': storeName,
        }),
        actionLabel: l10n.translate('plusPmManageBilling'),
        route: PlusRoutes.paymentMethodsBilling,
      ),
      // Google Play only. Apple has no backup payment method.
      if (store == PlusStore.googlePlay)
        _Topic(
          title: l10n.translate('plusPayBackupTitle'),
          answer: l10n.translate('plusPmAnswerBackup'),
          actionLabel: l10n.translate('plusPayBackupTitle'),
          route: PlusRoutes.paymentMethodsBackup,
        ),
      _Topic(
        title: l10n.translate('plusManageSubscription'),
        answer: l10n.plusText('plusPmAnswerManage', {'store': storeName}),
        actionLabel: l10n.translate('plusManageSubscription'),
        route: PlusRoutes.manage,
      ),
    ];

    return PlusScreenScaffold(
      title: l10n.translate('plusPmHelp'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            l10n.translate('plusPmHelpIntro'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
        ),
        SettingsSectionCard(
          children: [for (final topic in topics) _TopicTile(topic: topic)],
        ),
        const SizedBox(height: 16),
        SettingsSectionCard(
          children: [
            PlusActionRow(
              icon: Icons.support_agent_rounded,
              title: l10n.translate('plusContactSupport'),
              subtitle: l10n.translate('plusHelpSupportSubtitle'),
              onTap: () => context.push(PlusRoutes.support),
            ),
          ],
        ),
      ],
    );
  }
}

class _Topic {
  const _Topic({
    required this.title,
    required this.answer,
    required this.actionLabel,
    required this.route,
  });

  final String title;
  final String answer;
  final String actionLabel;
  final String route;
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});

  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Theme(
      // The card already draws the dividers between topics.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          topic.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        children: [
          Text(
            topic.answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.push(topic.route),
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(
                topic.actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
