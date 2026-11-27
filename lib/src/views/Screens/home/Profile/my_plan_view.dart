import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/subscription_backend_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/subscription_test_mode_section.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// My Plan for every presentation state. An unconfirmed status is shown as
/// unknown: it is never treated as Free or as active Plus.
class MyPlanView extends StatelessWidget {
  const MyPlanView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    return SubscriptionPage(
      title: loc.translate('myPlan'),
      children: [
        const SubscriptionStateRefresher(),
        _hero(loc, p),
        if (!p.isSample) const SubscriptionTestModeSection(),
        ..._stateDetails(context, loc, p),
        if (kDebugMode && !p.isSample) ...[
          const SizedBox(height: 12),
          SubSecondaryButton(
            label: loc.translate('subPreviewTitle'),
            onPressed: () => context.push(SubscriptionRoutes.preview),
          ),
        ],
      ],
    );
  }

  Widget _hero(AppLocalizations loc, SubscriptionPresentation p) {
    final until = p.paidThrough;
    switch (p.status) {
      case SubscriptionStatus.loading:
        return SubPlanHero(
          pill: loc.translate('subPillUnknown'),
          title: loc.translate('subStatusChecking'),
          body: loc.translate('subCheckingBody'),
        );
      case SubscriptionStatus.offline:
        return SubPlanHero(
          pill: loc.translate('subPillUnknown'),
          title: loc.translate('subOfflineTitle'),
          body: loc.translate('subOfflineBody'),
        );
      case SubscriptionStatus.unavailable:
        return SubPlanHero(
          pill: loc.translate('subPillUnknown'),
          title: loc.translate('planStatusUnavailable'),
          body: loc.translate('planInformationUnavailable'),
        );
      case SubscriptionStatus.free:
        return SubPlanHero(
          pill: loc.translate('subCurrentPlan'),
          title: loc.translate('subPlanFree'),
          body: loc.translate('subFreeSummary'),
        );
      case SubscriptionStatus.plusRenewing:
        return SubPlanHero(
          pill: loc.translate('subPillActive'),
          tone: SubTone.positive,
          tinted: true,
          title: loc.plusWithCycle(p),
          body: loc.translate('subPlusSummary'),
        );
      case SubscriptionStatus.plusCancelScheduled:
        return SubPlanHero(
          pill: loc.translate('subPillAutoRenewOff'),
          tone: SubTone.positive,
          tinted: true,
          title: loc.fill('subCancelScheduledTitle', {
            'date': until == null
                ? loc.translate('subPaidPeriodEnd')
                : loc.shortDate(until),
          }),
          body: loc.translate('subCancelScheduledBody'),
        );
      case SubscriptionStatus.paymentIssue:
        return SubPlanHero(
          pill: loc.translate('subPillPaymentIssue'),
          tone: SubTone.attention,
          title: loc.translate('subPaymentIssueTitle'),
          body: loc.paymentIssueBody(p),
        );
      case SubscriptionStatus.activationPending:
        return SubPlanHero(
          pill: loc.translate('subPillPending'),
          title: loc.translate('subActivationPendingTitle'),
          body: loc.translate('subActivationPendingBody'),
        );
      case SubscriptionStatus.expiredOverLimit:
        return SubPlanHero(
          pill: loc.translate('subPillExpired'),
          tone: SubTone.attention,
          title: loc.translate('subExpiredTitle'),
          body: loc.translate('subExpiredMessage'),
        );
      case SubscriptionStatus.expiredWithinFree:
        return SubPlanHero(
          pill: loc.translate('subPillBackOnFree'),
          title: loc.translate('subBackOnFreeTitle'),
          body: loc.translate('subBackOnFreeBody'),
        );
    }
  }

  List<Widget> _stateDetails(
    BuildContext context,
    AppLocalizations loc,
    SubscriptionPresentation p,
  ) {
    final platform = SubscriptionPlatformPolicy.current;
    final purchaseJourney =
        SubscriptionPlatformPolicy.showsPurchaseJourney(platform);
    final showStore = SubscriptionPlatformPolicy.showsStoreDetails(platform, p);
    switch (p.status) {
      case SubscriptionStatus.loading:
      case SubscriptionStatus.unavailable:
      case SubscriptionStatus.offline:
        return [
          const SizedBox(height: 12),
          const _AllowanceCards(),
          SubSection(loc.translate('subUsageCreations')),
          SubUsageList(usage: p.usage),
          const SizedBox(height: 16),
          _links(context, loc),
        ];
      case SubscriptionStatus.free:
        return [
          const SizedBox(height: 12),
          const _AllowanceCards(),
          SubSection(loc.translate('subUsageCreations')),
          SubUsageList(usage: p.usage),
          const SizedBox(height: 20),
          SubPrimaryButton(
            label: loc.translate(
              purchaseJourney ? 'subUpgradeToPlus' : 'subViewPlusPlans',
            ),
            onPressed: () => context.push('/subscription'),
          ),
          const SizedBox(height: 16),
          _links(context, loc),
        ];
      case SubscriptionStatus.plusRenewing:
      case SubscriptionStatus.plusCancelScheduled:
      case SubscriptionStatus.paymentIssue:
      case SubscriptionStatus.activationPending:
        return [
          const SizedBox(height: 12),
          _PlusDetails(presentation: p),
          const SizedBox(height: 12),
          SettingsSectionCard(
            children: [
              SubNavTile(
                icon: Icons.tune_rounded,
                title: loc.translate('subManageSubscription'),
                subtitle: loc.translate('subManageSubtitle'),
                onTap: () => context.push(SubscriptionRoutes.manage),
              ),
              SubNavTile(
                icon: Icons.receipt_long_outlined,
                title: loc.translate('billingPayments'),
                subtitle:
                    showStore ? loc.translate('subBillingSubtitle') : null,
                onTap: () => context.push('/billing-payments'),
              ),
              if (showStore)
                SubNavTile(
                  icon: Icons.restore_rounded,
                  title: loc.translate('restorePurchases'),
                  onTap: () => context.push(SubscriptionRoutes.restore),
                ),
              SubNavTile(
                icon: Icons.support_agent_rounded,
                title: loc.translate('subSubscriptionHelp'),
                onTap: () => context.push('/contact-us'),
              ),
            ],
          ),
        ];
      case SubscriptionStatus.expiredOverLimit:
        return [
          const SizedBox(height: 12),
          SubCard(
            child: Column(
              children: [
                SubBullet(loc.translate('subReadOnlyRetained')),
                SubBullet(loc.translate('subReadOnlyAccess')),
                SubBullet(loc.translate('subReadOnlyCreationPaused'),
                    icon: Icons.pause_circle_outline_rounded,
                    tone: SubTone.attention),
                SubBullet(loc.translate('subReadOnlyEditingPaused'),
                    icon: Icons.pause_circle_outline_rounded,
                    tone: SubTone.attention),
                SubBullet(loc.translate('subReadOnlyReactivate'),
                    icon: Icons.autorenew_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._reactivation(context, loc, purchaseJourney),
          SubSection(loc.translate('subUsageCreations')),
          SubUsageList(usage: p.usage),
          const SizedBox(height: 16),
          _links(context, loc),
        ];
      case SubscriptionStatus.expiredWithinFree:
        return [
          const SizedBox(height: 12),
          const _AllowanceCards(),
          SubSection(loc.translate('subRemainingAllowances')),
          SubUsageList(usage: p.usage, showRemaining: true),
          const SizedBox(height: 20),
          ..._reactivation(context, loc, purchaseJourney),
          const SizedBox(height: 16),
          _links(context, loc),
        ];
    }
  }

  /// Leads to the plans screen. Reactivation itself needs a verified provider.
  List<Widget> _reactivation(
    BuildContext context,
    AppLocalizations loc,
    bool purchaseJourney,
  ) {
    return [
      SubPrimaryButton(
        label: loc.translate(
          purchaseJourney ? 'subReactivatePlus' : 'subViewPlusPlans',
        ),
        onPressed: () => context.push('/subscription'),
      ),
      const SizedBox(height: 8),
      SubNotConnectedNotice(
        textKey: purchaseJourney
            ? 'subPurchasesNotConnected'
            : 'subPlatformInfoNotice',
      ),
    ];
  }

  Widget _links(BuildContext context, AppLocalizations loc) {
    return SettingsSectionCard(
      children: [
        SubNavTile(
          icon: Icons.card_membership_outlined,
          title: loc.translate('subscriptions'),
          subtitle: loc.translate('viewSubscriptionOptions'),
          onTap: () => context.push('/subscription'),
        ),
        SubNavTile(
          icon: Icons.bar_chart_rounded,
          title: loc.translate('subUsageTitle'),
          subtitle: loc.translate('subUsageSubtitle'),
          onTap: () => context.push(SubscriptionRoutes.usage),
        ),
        SubNavTile(
          icon: Icons.help_outline_rounded,
          title: loc.translate('subHowLimitsTitle'),
          subtitle: loc.translate('subHowLimitsSubtitle'),
          onTap: () => context.push(SubscriptionRoutes.limits),
        ),
        SubNavTile(
          icon: Icons.tune_rounded,
          title: loc.translate('subManageSubscription'),
          onTap: () => context.push(SubscriptionRoutes.manage),
        ),
        SubNavTile(
          icon: Icons.receipt_long_outlined,
          title: loc.translate('billingPayments'),
          onTap: () => context.push('/billing-payments'),
        ),
      ],
    );
  }
}

/// The two different Free allowances, side by side in meaning.
class _AllowanceCards extends StatelessWidget {
  const _AllowanceCards();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SubCard(
      child: Column(
        children: [
          SubBullet(
            loc.translate('subAllowanceCreations'),
            icon: Icons.add_circle_outline_rounded,
          ),
          SubBullet(
            loc.translate('subAllowanceEdits'),
            icon: Icons.edit_outlined,
          ),
        ],
      ),
    );
  }
}

class _PlusDetails extends StatelessWidget {
  const _PlusDetails({required this.presentation});

  final SubscriptionPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = presentation;
    final started = p.startedAt;
    final until = p.paidThrough;
    final next = p.nextPaymentDate;
    final price = p.renewalPrice;
    final cycle = p.cycle;
    final provider = p.provider;
    final String renewal = switch (p.status) {
      SubscriptionStatus.plusRenewing => loc.translate('subAutoRenewOn'),
      SubscriptionStatus.plusCancelScheduled =>
        loc.translate('subAutoRenewOff'),
      SubscriptionStatus.paymentIssue => loc.translate('subPillPaymentIssue'),
      _ => loc.translate('subPillPending'),
    };
    return SubCard(
      child: Column(
        children: [
          SubInfoRow(label: loc.translate('subRenewal'), value: renewal),
          if (cycle != null)
            SubInfoRow(
              label: loc.translate('subBillingCycle'),
              value: loc.cycleName(cycle),
            ),
          if (started != null)
            SubInfoRow(
              label: loc.translate('subStartedOn'),
              value: loc.shortDate(started),
            ),
          if (p.status == SubscriptionStatus.plusCancelScheduled &&
              until != null)
            SubInfoRow(
              label: loc.translate('subActiveUntil'),
              value: loc.shortDate(until),
            ),
          if (p.status == SubscriptionStatus.plusCancelScheduled)
            SubInfoRow(
              label: loc.translate('subNextCharge'),
              value: loc.translate('subNoNextCharge'),
            ),
          if (next != null)
            SubInfoRow(
              label: loc.translate('subNextCharge'),
              value: loc.shortDate(next),
            ),
          if (next != null && price != null && cycle != null)
            SubInfoRow(
              label: loc.translate('subRenewalPrice'),
              value: loc.cyclePrice(cycle, price),
            ),
          if (provider != null &&
              !SubscriptionPlatformPolicy.hidesProvider(
                SubscriptionPlatformPolicy.current,
                provider,
              ))
            SubInfoRow(
              label: loc.translate('subBilledThrough'),
              value: loc.providerName(provider),
            ),
        ],
      ),
    );
  }
}
