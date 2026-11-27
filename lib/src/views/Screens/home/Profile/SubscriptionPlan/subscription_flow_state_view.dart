import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Designed purchase-flow states for a future store integration. Nothing here
/// charges or activates anything, and success renders only in a debug sample.
class SubscriptionFlowStateView extends StatelessWidget {
  const SubscriptionFlowStateView({
    super.key,
    required this.state,
    this.request,
  });

  final SubscriptionFlowState state;

  /// The plan and payment method chosen in the debug payment sheet.
  final PaymentReviewRequest? request;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final store = loc.storeName(p);
    final purchaseJourney = SubscriptionPlatformPolicy.showsPurchaseJourney(
      SubscriptionPlatformPolicy.current,
    );
    final shown =
        state == SubscriptionFlowState.activationSuccess && !p.isSample
            ? SubscriptionFlowState.verificationFailed
            : state == SubscriptionFlowState.purchaseReview && !purchaseJourney
                ? SubscriptionFlowState.providerUnavailable
                : state;
    return SubscriptionPage(
      title: loc.translate(
        shown == SubscriptionFlowState.purchaseReview
            ? 'subReviewTitle'
            : 'subscriptions',
      ),
      children: switch (shown) {
        SubscriptionFlowState.priceLoading => [
            SubHeading(loc.translate('choosePlan')),
            const SizedBox(height: 8),
            SubBodyText(loc.translate('subPricesLoading')),
            const SizedBox(height: 16),
            const SubSkeleton(),
            const SizedBox(height: 12),
            const SubSkeleton(lines: 2),
            const SizedBox(height: 20),
            SubPrimaryButton(
              label: loc.translate('subSubscribeToPlus'),
              onPressed: null,
            ),
          ],
        SubscriptionFlowState.pricesUnavailable => [
            SubMessage(
              icon: Icons.info_outline_rounded,
              title: loc.translate('subPricesUnavailableTitle'),
              body: loc.translate('subPricesUnavailableBody'),
            ),
            SubPrimaryButton(label: loc.translate('tryAgain'), onPressed: null),
          ],
        SubscriptionFlowState.purchaseReview => _review(context, loc, p),
        SubscriptionFlowState.providerUnavailable => [
            SubMessage(
              icon: Icons.cloud_off_outlined,
              tone: SubTone.attention,
              title: loc.translate('subPayProviderUnavailableTitle'),
              body: loc.fill('subPayProviderUnavailableBody', {
                'provider': store,
              }),
            ),
            SubPrimaryButton(label: loc.translate('tryAgain'), onPressed: null),
          ],
        SubscriptionFlowState.purchaseCanceled => _message(
            context,
            icon: Icons.close_rounded,
            tone: SubTone.neutral,
            title: loc.translate('subFlowCanceledTitle'),
            body: loc.translate('subFlowCanceledBody'),
            primary: loc.translate('subBackToPlans'),
            route: '/subscription',
          ),
        SubscriptionFlowState.purchasePending => _message(
            context,
            icon: Icons.schedule_rounded,
            title: loc.translate('subFlowPendingTitle'),
            body: loc.fill('subFlowPendingBody', {'store': store}),
            primary: loc.translate('subViewMyPlan'),
            route: '/my-plan',
          ),
        SubscriptionFlowState.purchaseFailed => _message(
            context,
            icon: Icons.error_outline_rounded,
            tone: SubTone.attention,
            title: loc.translate('subFlowFailedTitle'),
            body: loc.translate('subFlowFailedBody'),
            primary: loc.translate('subBackToPlans'),
            route: '/subscription',
          ),
        SubscriptionFlowState.activationPending => _message(
            context,
            icon: Icons.schedule_rounded,
            title: loc.translate('subActivationPendingTitle'),
            body: loc.translate('subActivationPendingBody'),
            primary: loc.translate('subViewMyPlan'),
            route: '/my-plan',
          ),
        SubscriptionFlowState.activationSuccess => _message(
            context,
            icon: Icons.check_rounded,
            title: loc.translate('subFlowSuccessTitle'),
            body: loc.translate('subFlowSuccessBody'),
            primary: loc.translate('subViewMyPlan'),
            route: '/my-plan',
          ),
        SubscriptionFlowState.verificationFailed => _message(
            context,
            icon: Icons.gpp_maybe_outlined,
            tone: SubTone.attention,
            title: loc.translate('subFlowVerifyTitle'),
            body: loc.translate('subFlowVerifyBody'),
            primary: loc.translate('contactUs'),
            route: '/contact-us',
          ),
        SubscriptionFlowState.entitlementMismatch => _message(
            context,
            icon: Icons.manage_accounts_outlined,
            tone: SubTone.attention,
            title: loc.translate('subFlowMismatchTitle'),
            body: loc.fill('subFlowMismatchBody', {'store': store}),
            primary: loc.translate('contactUs'),
            route: '/contact-us',
          ),
      },
    );
  }

  /// The sample order summary. The renewal date stays unknown on purpose: only
  /// a provider can confirm it, and the final action is always disabled.
  List<Widget> _review(
    BuildContext context,
    AppLocalizations loc,
    SubscriptionPresentation p,
  ) {
    final cycle = request?.cycle ?? p.cycle ?? PlusBillingCycle.annual;
    final option = request?.option ?? PaymentOption.googlePlay;
    final isPlay = option == PaymentOption.googlePlay;
    final annual = cycle == PlusBillingCycle.annual;
    final price = annual
        ? SubscriptionPolicy.annualPrice
        : SubscriptionPolicy.monthlyPrice;
    final priceText = loc.cyclePrice(cycle, price);
    final provider = loc.paymentProviderName(option);
    return [
      SubPlanHero(
        pill: loc.translate('subPlanPlus'),
        tone: SubTone.positive,
        tinted: true,
        title: loc.fill('subBrokerPlusWithCycle', {
          'cycle': loc.cycleName(cycle),
        }),
        body: loc.translate('subPlusSummary'),
      ),
      const SizedBox(height: 12),
      SubCard(
        child: Column(
          children: [
            SubInfoRow(
              label: loc.translate('subBillingCycle'),
              value: loc.cycleName(cycle),
            ),
            SubInfoRow(
              label: loc.translate('subDueToday'),
              value: loc.aed(price),
            ),
            SubInfoRow(
              label: loc.translate('subReviewNextRenewalDate'),
              value: loc.translate('subReviewDateAfterConfirm'),
            ),
            SubInfoRow(
              label: loc.translate('subReviewNextAmount'),
              value: priceText,
            ),
            SubInfoRow(
              label: loc.translate('subReviewProvider'),
              value: provider,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SubBullet(
        loc.fill(annual ? 'subPayRenewalAnnual' : 'subPayRenewalMonthly', {
          'price': loc.aed(price),
        }),
        icon: Icons.autorenew_rounded,
        tone: SubTone.neutral,
      ),
      SubBullet(
        loc.translate(isPlay ? 'subPayCancelGoogle' : 'subPayCancelCard'),
        icon: Icons.event_busy_outlined,
        tone: SubTone.neutral,
      ),
      SubBullet(
        loc.fill('subReviewStoreCharge', {
          'store': isPlay
              ? loc.translate('subProviderGooglePlay')
              : loc.translate('subProviderTap'),
        }),
        icon: Icons.storefront_outlined,
        tone: SubTone.neutral,
      ),
      const SizedBox(height: 12),
      const SubNotConnectedNotice(textKey: 'subReviewNoCharge'),
      const SizedBox(height: 16),
      SubPrimaryButton(
        label: loc.fill('subSubscribeWithPrice', {'price': priceText}),
        onPressed: null,
      ),
      const SizedBox(height: 10),
      SubBodyText(loc.translate('subReviewLegal'), center: true),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            onPressed: () => context.push('/terms-conditions'),
            child: Text(loc.translate('termsConditions')),
          ),
          TextButton(
            onPressed: () => context.push('/privacy-policy'),
            child: Text(loc.translate('privacyPolicy')),
          ),
        ],
      ),
    ];
  }

  List<Widget> _message(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required String primary,
    required String route,
    SubTone tone = SubTone.positive,
  }) {
    return [
      SubMessage(icon: icon, title: title, body: body, tone: tone),
      SubPrimaryButton(label: primary, onPressed: () => context.push(route)),
    ];
  }
}
