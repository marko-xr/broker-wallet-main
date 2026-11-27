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

/// Shows the subscription state and where it is managed. With the trusted
/// backend it adds the real controls of the provider that bills the account;
/// without it every store action stays disabled.
class ManageSubscriptionView extends StatelessWidget {
  const ManageSubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final store = loc.storeName(p);
    final platform = SubscriptionPlatformPolicy.current;
    final path =
        SubscriptionPlatformPolicy.managementPath(platform, p.provider);
    final showStore = SubscriptionPlatformPolicy.showsStoreDetails(platform, p);
    final live = showsLiveBilling(p);
    return SubscriptionPage(
      title: loc.translate('subManageSubscription'),
      children: [
        _stateCard(loc, p),
        const SizedBox(height: 12),
        if (showStore && !live) const SubNotConnectedNotice(),
        ..._ownershipNotice(loc, p, path, store),
        const SizedBox(height: 16),
        if (live && _isManaged(p))
          const LiveBillingSection(showHistory: false)
        else
          ..._storeActions(context, loc, p, store, path, platform),
        const SizedBox(height: 16),
        SettingsSectionCard(
          children: [
            if (showStore)
              SubNavTile(
                icon: Icons.event_busy_outlined,
                title: loc.translate('subCancelInfoTitle'),
                subtitle: loc.translate('subCancelInfoSubtitle'),
                onTap: () => context.push(SubscriptionRoutes.cancellation),
              ),
            SubNavTile(
              icon: Icons.receipt_long_outlined,
              title: loc.translate('billingPayments'),
              onTap: () => context.push('/billing-payments'),
            ),
            if (showStore && platform != SubscriptionPlatform.web)
              SubNavTile(
                icon: Icons.restore_rounded,
                title: loc.translate('restorePurchases'),
                onTap: () => context.push(SubscriptionRoutes.restore),
              ),
            SubNavTile(
              icon: Icons.compare_arrows_rounded,
              title: loc.translate('subCompareTitle'),
              onTap: () => context.push('/subscription'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stateCard(AppLocalizations loc, SubscriptionPresentation p) {
    final until = p.paidThrough;
    final dateText = until == null
        ? loc.translate('subPaidPeriodEnd')
        : loc.shortDate(until);
    switch (p.status) {
      case SubscriptionStatus.plusRenewing:
        final next = p.nextPaymentDate;
        return SubPlanHero(
          pill: loc.translate('subPillActive'),
          tone: SubTone.positive,
          tinted: true,
          title: loc.translate('subAutoRenewOnTitle'),
          body: loc.translate('subAutoRenewOnBody'),
          children: [
            SubInfoRow(
              label: loc.translate('subPlan'),
              value: loc.plusWithCycle(p),
            ),
            if (next != null)
              SubInfoRow(
                label: loc.translate('subNextCharge'),
                value: loc.shortDate(next),
              ),
          ],
        );
      case SubscriptionStatus.plusCancelScheduled:
        return SubPlanHero(
          pill: loc.translate('subPillAutoRenewOff'),
          tone: SubTone.positive,
          tinted: true,
          title: loc.fill('subCancelScheduledTitle', {'date': dateText}),
          body: loc.translate('subCancelScheduledBody'),
          children: [
            SubInfoRow(
              label: loc.translate('subPlan'),
              value: loc.plusWithCycle(p),
            ),
            SubInfoRow(
              label: loc.translate('subNextCharge'),
              value: loc.translate('subNoNextCharge'),
            ),
          ],
        );
      case SubscriptionStatus.expiredOverLimit:
      case SubscriptionStatus.expiredWithinFree:
        return SubPlanHero(
          pill: loc.translate('subPillExpired'),
          tone: SubTone.attention,
          title: loc.translate('subManageExpiredTitle'),
          body: loc.translate(
            p.status == SubscriptionStatus.expiredOverLimit
                ? 'subExpiredMessage'
                : 'subBackOnFreeBody',
          ),
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
      case SubscriptionStatus.free:
        return SubPlanHero(
          pill: loc.translate('subCurrentPlan'),
          title: loc.translate('subPlanFree'),
          body: loc.translate('subManageFreeBody'),
        );
      case SubscriptionStatus.loading:
      case SubscriptionStatus.unavailable:
      case SubscriptionStatus.offline:
        return SubPlanHero(
          pill: loc.translate('subPillUnknown'),
          title: loc.translate('subManageUnknownTitle'),
          body: loc.translate('subManageUnknownBody'),
        );
    }
  }

  bool _isManaged(SubscriptionPresentation p) =>
      p.hasVerifiedPlus ||
      p.status == SubscriptionStatus.paymentIssue ||
      p.status == SubscriptionStatus.activationPending;

  /// States who manages a subscription billed somewhere this device cannot
  /// reach. It offers no link, because no provider can act for another one.
  List<Widget> _ownershipNotice(
    AppLocalizations loc,
    SubscriptionPresentation p,
    ManagementPath path,
    String store,
  ) {
    if (!_isManaged(p)) return const [];
    final text = switch (path) {
      ManagementPath.otherStore =>
        loc.fill('subManagedInOtherStore', {'store': store}),
      ManagementPath.tapBilling => loc.translate('subManagedByTap'),
      ManagementPath.notOnThisDevice => loc.translate('subManagedNotHere'),
      ManagementPath.thisStore || ManagementPath.none => null,
    };
    if (text == null) return const [];
    return [
      const SizedBox(height: 12),
      SubNotice(icon: Icons.info_outline_rounded, text: text),
    ];
  }

  List<Widget> _storeActions(
    BuildContext context,
    AppLocalizations loc,
    SubscriptionPresentation p,
    String store,
    ManagementPath path,
    SubscriptionPlatform platform,
  ) {
    final purchaseJourney =
        SubscriptionPlatformPolicy.showsPurchaseJourney(platform);
    final expired = p.status == SubscriptionStatus.expiredOverLimit ||
        p.status == SubscriptionStatus.expiredWithinFree;
    if (expired) {
      return [
        SubPrimaryButton(
          label: loc.translate(
            purchaseJourney ? 'subReactivatePlus' : 'subViewPlusPlans',
          ),
          onPressed: () => context.push('/subscription'),
        ),
      ];
    }
    if (!_isManaged(p)) return const [];
    final canManageHere = path == ManagementPath.thisStore ||
        (path == ManagementPath.none && purchaseJourney);
    if (!canManageHere) return const [];
    return [
      SubPrimaryButton(
        label: loc.fill('subManageInStore', {'store': store}),
        onPressed: null,
      ),
      if (p.hasVerifiedPlus) ...[
        const SizedBox(height: 4),
        SubSecondaryButton(
          label: loc.translate('subChangeCycle'),
          onPressed: null,
        ),
      ],
    ];
  }
}
