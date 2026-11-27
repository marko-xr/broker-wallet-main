import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/live_billing_sections.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Billing overview. Payment data comes only from the trusted server; without
/// it nothing is shown, and no history or invoice is ever invented here.
class BillingPaymentsView extends StatelessWidget {
  const BillingPaymentsView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final store = loc.storeName(p);
    final platform = SubscriptionPlatformPolicy.current;
    final showStore = SubscriptionPlatformPolicy.showsStoreDetails(platform, p);
    final live = showsLiveBilling(p);
    final showRestore =
        showStore && SubscriptionPlatformPolicy.showsRestore(platform);
    return SubscriptionPage(
      title: loc.translate('billingPayments'),
      children: [
        if (p.isUnconfirmed || p.provider == null)
          SubPlanHero(
            pill: loc.translate('subPillUnknown'),
            title: loc.translate('billingUnavailable'),
            body: showStore
                ? loc.translate('billingStoreExplanation')
                : loc.translate('subBillingNoPurchaseHere'),
          )
        else
          _Summary(presentation: p),
        const SizedBox(height: 12),
        if (live) ...[
          const LiveBillingSection(),
          SubSection(loc.translate('subRefundHelpTitle')),
          SubCard(child: SubBodyText(loc.translate('subCancelRefundRules'))),
          const SizedBox(height: 16),
        ] else if (showStore) ...[
          const SubNotConnectedNotice(),
          SubSection(loc.translate('purchaseHistory')),
          SettingsSectionCard(
            children: [
              SubNavTile(
                icon: Icons.history_rounded,
                title: loc.translate('purchaseHistoryUnavailable'),
                subtitle: loc.translate('purchaseHistoryStoreExplanation'),
              ),
              SubNavTile(
                icon: Icons.receipt_outlined,
                title: loc.translate('subReceipts'),
                subtitle: loc.fill('subIssuedByStore', {'store': store}),
              ),
              SubNavTile(
                icon: Icons.credit_card_outlined,
                title: loc.translate('paymentMethod'),
                subtitle: loc.fill('subManagedByStore', {'store': store}),
              ),
            ],
          ),
          SubSection(loc.translate('subRefundHelpTitle')),
          SubCard(child: SubBodyText(loc.translate('subCancelRefundRules'))),
          const SizedBox(height: 16),
        ],
        SettingsSectionCard(
          children: [
            if (showRestore)
              SubNavTile(
                icon: Icons.restore_rounded,
                title: loc.translate('restorePurchases'),
                onTap: () => context.push(SubscriptionRoutes.restore),
              ),
            SubNavTile(
              icon: Icons.tune_rounded,
              title: loc.translate('subManageSubscription'),
              onTap: () => context.push(SubscriptionRoutes.manage),
            ),
            SubNavTile(
              icon: Icons.card_membership_outlined,
              title: loc.translate('subscriptions'),
              onTap: () => context.push('/subscription'),
            ),
            SubNavTile(
              icon: Icons.support_agent_rounded,
              title: loc.translate('subSubscriptionHelp'),
              onTap: () => context.push('/contact-us'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.presentation});

  final SubscriptionPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = presentation;
    final provider = p.provider!;
    final cycle = p.cycle;
    final next = p.nextPaymentDate;
    final price = p.renewalPrice;
    return SubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              loc.plusWithCycle(p),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          if (!SubscriptionPlatformPolicy.hidesProvider(
            SubscriptionPlatformPolicy.current,
            provider,
          ))
            SubInfoRow(
              label: loc.translate('subBilledThrough'),
              value: loc.providerName(provider),
            ),
          SubInfoRow(
            label: loc.translate('status'),
            value: loc.billingStatus(p),
          ),
          if (cycle != null)
            SubInfoRow(
              label: loc.translate('subBillingCycle'),
              value: loc.cycleName(cycle),
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
        ],
      ),
    );
  }
}
