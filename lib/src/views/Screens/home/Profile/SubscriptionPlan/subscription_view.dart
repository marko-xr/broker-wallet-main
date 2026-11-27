import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/plan_compare_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_plan_sheet.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Choose Your Plan. Selecting Plus opens a sheet: payment methods on Android,
/// plan details on iPhone. No state here can start or confirm a payment.
class SubscriptionView extends StatefulWidget {
  const SubscriptionView({super.key});

  @override
  State<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<SubscriptionView> {
  PlusBillingCycle _cycle = PlusBillingCycle.annual;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final platform = SubscriptionPlatformPolicy.current;
    final purchaseJourney =
        SubscriptionPlatformPolicy.showsPurchaseJourney(platform);
    // The web app takes real card payments once the trusted backend is on.
    final cardCheckoutLive = platform == SubscriptionPlatform.web &&
        SubscriptionPlatformPolicy.canStartCheckout(
          platform,
          PaymentOption.tapCard,
        );
    final isExpired = p.status == SubscriptionStatus.expiredOverLimit ||
        p.status == SubscriptionStatus.expiredWithinFree;
    // A pending or troubled subscription must never be offered a second
    // purchase: it is managed, not bought again.
    final hasSubscription = p.hasVerifiedPlus ||
        p.status == SubscriptionStatus.paymentIssue ||
        p.status == SubscriptionStatus.activationPending;
    return SubscriptionPage(
      title: loc.translate('subscriptions'),
      children: [
        SubHeading(
          loc.translate(hasSubscription ? 'subYourPlan' : 'choosePlan'),
        ),
        const SizedBox(height: 8),
        SubBodyText(loc.translate('subChooseIntro')),
        const SizedBox(height: 16),
        if (!hasSubscription && !cardCheckoutLive) ...[
          SubNotice(
            icon: Icons.info_outline_rounded,
            text: purchaseJourney
                ? loc.translate('subPurchasesNotConnected')
                : loc.translate('subPlatformInfoNotice'),
          ),
          const SizedBox(height: 12),
        ],
        _FreeCard(isCurrent: p.status == SubscriptionStatus.free),
        const SizedBox(height: 12),
        if (p.hasVerifiedPlus)
          _CurrentPlusCard(presentation: p)
        else if (hasSubscription)
          _UnconfirmedPlusCard(presentation: p)
        else
          _plusPlanCard(context, loc, p, purchaseJourney, isExpired),
        if (hasSubscription) ...[
          const SizedBox(height: 12),
          SettingsSectionCard(
            children: [
              SubNavTile(
                icon: Icons.tune_rounded,
                title: loc.translate('subManageSubscription'),
                subtitle: loc.translate('subManageSubtitle'),
                onTap: () => context.push(SubscriptionRoutes.manage),
              ),
            ],
          ),
        ],
        if (!hasSubscription) ...[
          if (p.status == SubscriptionStatus.free) ...[
            const SizedBox(height: 4),
            SubSecondaryButton(
              label: loc.translate('subContinueFree'),
              onPressed: () => context.pop(),
            ),
          ],
          if (purchaseJourney) ...[
            const SizedBox(height: 4),
            if (SubscriptionPlatformPolicy.showsRestore(platform))
              SubSecondaryButton(
                label: loc.translate('restorePurchases'),
                onPressed: () => context.push(SubscriptionRoutes.restore),
              ),
            const SizedBox(height: 8),
            SubBodyText(
              loc.translate(
                platform == SubscriptionPlatform.web
                    ? 'subRenewalDisclosureCard'
                    : 'subRenewalDisclosure',
              ),
              center: true,
            ),
          ],
        ],
        const SizedBox(height: 16),
        const PlanComparisonTable(compact: true),
        const SizedBox(height: 12),
        SettingsSectionCard(
          children: [
            SubNavTile(
              icon: Icons.compare_arrows_rounded,
              title: loc.translate('subCompareTitle'),
              subtitle: loc.translate('subCompareSubtitle'),
              onTap: () => context.push(SubscriptionRoutes.compare),
            ),
            SubNavTile(
              icon: Icons.help_outline_rounded,
              title: loc.translate('subHowLimitsTitle'),
              subtitle: loc.translate('subHowLimitsSubtitle'),
              onTap: () => context.push(SubscriptionRoutes.limits),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SettingsSectionHeader(title: loc.translate('legalAndApp')),
        SettingsSectionCard(
          children: [
            SubNavTile(
              icon: Icons.privacy_tip_rounded,
              title: loc.translate('privacyPolicy'),
              onTap: () => context.push('/privacy-policy'),
            ),
            SubNavTile(
              icon: Icons.description_rounded,
              title: loc.translate('termsConditions'),
              onTap: () => context.push('/terms-conditions'),
            ),
          ],
        ),
      ],
    );
  }

  /// The highlighted Plus card: features, billing choice and one CTA.
  Widget _plusPlanCard(
    BuildContext context,
    AppLocalizations loc,
    SubscriptionPresentation p,
    bool purchaseJourney,
    bool isExpired,
  ) {
    final theme = Theme.of(context);
    final pricesReady = p.prices == PriceDataState.reference ||
        p.prices == PriceDataState.store;
    final ctaLabel = !purchaseJourney
        ? loc.translate('subViewPlanDetails')
        : isExpired
            ? loc.translate('subReactivatePlus')
            : loc.fill('subContinueWithPlan', {'cycle': loc.cycleName(_cycle)});
    return SubCard(
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.translate('subPlanPlus'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              SubPill(loc.translate('unlimited'), tone: SubTone.positive),
            ],
          ),
          const SizedBox(height: 8),
          SubBullet(loc.translate('subPlusBulletCreations')),
          SubBullet(loc.translate('subPlusBulletEdits')),
          SubBullet(loc.translate('subPlusBulletAccess')),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              loc.translate('subChooseCycle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ..._priceSection(loc, p),
          if (pricesReady) ...[
            const SizedBox(height: 14),
            SubPrimaryButton(
              label: ctaLabel,
              animateLabel: true,
              onPressed: () =>
                  showSubscriptionPlanSheet(context, cycle: _cycle),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _priceSection(
    AppLocalizations loc,
    SubscriptionPresentation p,
  ) {
    switch (p.prices) {
      case PriceDataState.loading:
        return [
          SubBodyText(loc.translate('subPricesLoading')),
          const SizedBox(height: 12),
          const SubSkeleton(),
          const SizedBox(height: 12),
          const SubSkeleton(lines: 2),
        ];
      case PriceDataState.unavailable:
        return [
          SubMessage(
            icon: Icons.info_outline_rounded,
            title: loc.translate('subPricesUnavailableTitle'),
            body: loc.translate('subPricesUnavailableBody'),
          ),
          SubPrimaryButton(label: loc.translate('tryAgain'), onPressed: null),
        ];
      case PriceDataState.reference:
      case PriceDataState.store:
        return [
          _CycleOption(
            selected: _cycle == PlusBillingCycle.annual,
            title: loc.translate('subCycleAnnual'),
            price: loc.perYear(SubscriptionPolicy.annualPrice),
            note: loc.fill('subAnnualEquivalent', {
              'price': loc.aed(SubscriptionPolicy.annualMonthlyEquivalent),
            }),
            badge: loc.fill('subSavePercent', {
              'percent': '${SubscriptionPolicy.annualSavingPercent}',
            }),
            onTap: () => setState(() => _cycle = PlusBillingCycle.annual),
          ),
          const SizedBox(height: 10),
          _CycleOption(
            selected: _cycle == PlusBillingCycle.monthly,
            title: loc.translate('subCycleMonthly'),
            price: loc.perMonth(SubscriptionPolicy.monthlyPrice),
            note: loc.translate('subMonthlyNote'),
            onTap: () => setState(() => _cycle = PlusBillingCycle.monthly),
          ),
        ];
    }
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.isCurrent});

  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final texts = Theme.of(context).textTheme;
    return SubCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCurrent) ...[
            SubPill(loc.translate('subCurrentPlan')),
            const SizedBox(height: 8),
          ],
          Semantics(
            header: true,
            child: Text(loc.translate('subPlanFree'), style: texts.titleLarge),
          ),
          const SizedBox(height: 2),
          Text(
            loc.translate('subFreePrice'),
            style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SubBullet(loc.translate('subFreeBulletCreations')),
          SubBullet(loc.translate('subFreeBulletEdits')),
          SubBullet(loc.translate('subFreeBulletAccess')),
        ],
      ),
    );
  }
}

class _CurrentPlusCard extends StatelessWidget {
  const _CurrentPlusCard({required this.presentation});

  final SubscriptionPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = presentation;
    final until = p.paidThrough;
    final next = p.nextPaymentDate;
    final price = p.renewalPrice;
    final cycle = p.cycle;
    return SubPlanHero(
      pill: loc.translate('subCurrentPlan'),
      tone: SubTone.positive,
      tinted: true,
      title: loc.plusWithCycle(p),
      body: loc.translate('subPlusSummary'),
      children: [
        if (next != null)
          SubInfoRow(
            label: loc.translate('subRenewsOn'),
            value: loc.shortDate(next),
          )
        else if (until != null)
          SubInfoRow(
            label: loc.translate('subActiveUntil'),
            value: loc.shortDate(until),
          ),
        if (next != null && price != null && cycle != null)
          SubInfoRow(
            label: loc.translate('subRenewalPrice'),
            value: loc.cyclePrice(cycle, price),
          ),
      ],
    );
  }
}

/// A subscription the provider has not confirmed: never shown as active.
class _UnconfirmedPlusCard extends StatelessWidget {
  const _UnconfirmedPlusCard({required this.presentation});

  final SubscriptionPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isIssue = presentation.status == SubscriptionStatus.paymentIssue;
    return SubPlanHero(
      pill: loc.translate(isIssue ? 'subPillPaymentIssue' : 'subPillPending'),
      tone: isIssue ? SubTone.attention : SubTone.neutral,
      title: loc.translate(
        isIssue ? 'subPaymentIssueTitle' : 'subActivationPendingTitle',
      ),
      body: isIssue
          ? loc.paymentIssueBody(presentation)
          : loc.translate('subActivationPendingBody'),
    );
  }
}

class _CycleOption extends StatelessWidget {
  const _CycleOption({
    required this.selected,
    required this.title,
    required this.price,
    required this.note,
    required this.onTap,
    this.badge,
  });

  final bool selected;
  final String title;
  final String price;
  final String note;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(16);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [title, if (badge != null) badge!, price, note].join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: subCardDecoration(
              colors,
              tinted: selected,
              selected: selected,
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(title, style: theme.textTheme.titleSmall),
                              if (badge != null)
                                SubPill(badge!, tone: SubTone.positive),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          SubBodyText(note),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
