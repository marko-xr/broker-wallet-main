import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/ios_web_activation_preview.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_plan_sheet.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Debug-only gallery for reviewing every designed state. Its route is not
/// registered outside debug builds, and each sample carries a visible banner.
class SubscriptionPreviewView extends StatefulWidget {
  const SubscriptionPreviewView({super.key});

  @override
  State<SubscriptionPreviewView> createState() =>
      _SubscriptionPreviewViewState();
}

class _SubscriptionPreviewViewState extends State<SubscriptionPreviewView> {
  @override
  void dispose() {
    _clearPreview();
    super.dispose();
  }

  void _clearPreview() {
    SubscriptionScope.debugPreview = null;
    SubscriptionPlatformPolicy.debugOverride = null;
  }

  /// Holds the sample and platform only while the previewed screen is open.
  Future<void> _withPreview(
    SubscriptionPresentation sample,
    SubscriptionPlatform? platform,
    Future<void> Function() show,
  ) async {
    SubscriptionScope.debugPreview = sample;
    SubscriptionPlatformPolicy.debugOverride = platform;
    try {
      await show();
    } finally {
      _clearPreview();
    }
  }

  Future<void> _open(
    SubscriptionPresentation sample,
    String route, {
    Object? extra,
    SubscriptionPlatform? platform,
  }) =>
      _withPreview(
        sample,
        platform,
        () async => context.push(route, extra: extra),
      );

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    Widget tile(
      String label,
      SubscriptionPresentation sample,
      String route, {
      Object? extra,
      SubscriptionPlatform? platform,
    }) =>
        SubNavTile(
          icon: Icons.visibility_outlined,
          title: label,
          onTap: () => _open(sample, route, extra: extra, platform: platform),
        );
    Widget sheet(
      String label,
      SubscriptionPlatform platform,
      PlusBillingCycle cycle, {
      PaymentOption? option,
      PaymentSheetState state = PaymentSheetState.ready,
      SubscriptionPresentation sample = SubscriptionSamples.free,
    }) =>
        SubNavTile(
          icon: Icons.vertical_align_top_rounded,
          title: label,
          onTap: () => _withPreview(
            sample,
            platform,
            () => showSubscriptionPlanSheet(
              context,
              cycle: cycle,
              initialOption: option,
              sheetState: state,
            ),
          ),
        );
    const android = SubscriptionPlatform.android;
    const iphone = SubscriptionPlatform.ios;
    const annual = PlusBillingCycle.annual;
    const monthly = PlusBillingCycle.monthly;
    const play = PaymentOption.googlePlay;
    const card = PaymentOption.tapCard;
    return SubscriptionPage(
      title: loc.translate('subPreviewTitle'),
      children: [
        SubNotice(
          icon: Icons.visibility_outlined,
          text: loc.translate('subSampleBanner'),
          tone: SubTone.attention,
        ),
        SubSection(loc.translate('subPreviewAndroidSheet')),
        SettingsSectionCard(
          children: [
            tile('Android plans', SubscriptionSamples.free, '/subscription',
                platform: android),
            sheet('Annual, Google Play selected', android, annual,
                option: play),
            sheet('Annual, Card selected', android, annual, option: card),
            sheet('Monthly, Google Play selected', android, monthly,
                option: play),
            sheet('Monthly, Card selected', android, monthly, option: card),
            sheet('Payment options loading', android, annual,
                state: PaymentSheetState.loading),
            sheet('Payment provider unavailable', android, annual,
                state: PaymentSheetState.providerUnavailable),
            sheet('Production gate: Google Play only', android, annual,
                sample: const SubscriptionPresentation.unavailable()),
          ],
        ),
        SubSection(loc.translate('subPreviewAndroidReview')),
        SettingsSectionCard(
          children: [
            for (final (label, cycle, option) in const [
              ('Annual, Google Play', annual, play),
              ('Annual, Card', annual, card),
              ('Monthly, Google Play', monthly, play),
              ('Monthly, Card', monthly, card),
            ])
              tile(
                label,
                SubscriptionSamples.free,
                SubscriptionRoutes.flowState,
                platform: android,
                extra: PaymentReviewRequest(cycle: cycle, option: option),
              ),
          ],
        ),
        SubSection(loc.translate('subPreviewIphone')),
        SettingsSectionCard(
          children: [
            SubNavTile(
              icon: Icons.block_rounded,
              title: 'Proposed web-activation sheet (blocked for App Store)',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                builder: (_) => const IosWebActivationPreviewSheet(),
              ),
            ),
          ],
        ),
        SettingsSectionCard(
          children: [
            tile('iPhone plans', SubscriptionSamples.free, '/subscription',
                platform: iphone),
            sheet('Plan information, Annual', iphone, annual),
            sheet('Plan information, Monthly', iphone, monthly),
            tile('My Plan, Free', SubscriptionSamples.free, '/my-plan',
                platform: iphone),
            tile('My Plan, Plus billed elsewhere',
                SubscriptionSamples.tapManaged, '/my-plan',
                platform: iphone),
            tile('Manage, Plus billed elsewhere',
                SubscriptionSamples.tapManaged, SubscriptionRoutes.manage,
                platform: iphone),
            tile('Billing, Free', SubscriptionSamples.free, '/billing-payments',
                platform: iphone),
          ],
        ),
        SubSection(loc.translate('myPlan')),
        SettingsSectionCard(
          children: [
            for (final (label, sample) in SubscriptionSamples.plans)
              tile(label, sample, '/my-plan'),
          ],
        ),
        SubSection(loc.translate('subManageSubscription')),
        SettingsSectionCard(
          children: [
            for (final (label, sample) in SubscriptionSamples.plans)
              tile(label, sample, SubscriptionRoutes.manage),
          ],
        ),
        SubSection(loc.translate('billingPayments')),
        SettingsSectionCard(
          children: [
            tile('Plus renewing', SubscriptionSamples.renewing,
                '/billing-payments'),
            tile('Auto-renewal off', SubscriptionSamples.cancelScheduled,
                '/billing-payments'),
            tile('Free', SubscriptionSamples.free, '/billing-payments'),
            tile('Billed by Tap Payments', SubscriptionSamples.tapManaged,
                '/billing-payments',
                platform: android),
            tile('Billed by App Store', SubscriptionSamples.renewingAppStore,
                '/billing-payments',
                platform: android),
          ],
        ),
        SubSection(loc.translate('subUsageTitle')),
        SettingsSectionCard(
          children: [
            tile('Populated', SubscriptionSamples.free,
                SubscriptionRoutes.usage),
            tile('Empty', SubscriptionSamples.freeEmpty,
                SubscriptionRoutes.usage),
            tile('Loading', SubscriptionSamples.freeLoading,
                SubscriptionRoutes.usage),
            tile('Unavailable', SubscriptionSamples.freeUnavailable,
                SubscriptionRoutes.usage),
          ],
        ),
        SubSection(loc.translate('restorePurchases')),
        SettingsSectionCard(
          children: [
            for (final state in RestorePurchaseState.values)
              tile(state.name, SubscriptionSamples.free,
                  SubscriptionRoutes.restore,
                  extra: state),
          ],
        ),
        SubSection(loc.translate('subPreviewFlows')),
        SettingsSectionCard(
          children: [
            for (final state in SubscriptionFlowState.values)
              tile(state.name, SubscriptionSamples.renewing,
                  SubscriptionRoutes.flowState,
                  extra: state),
          ],
        ),
      ],
    );
  }
}

/// Sample values for the gallery and widget tests. They are always marked
/// [SubscriptionPresentation.isSample] and are never a real account.
abstract final class SubscriptionSamples {
  static const _counts = {
    UsageCategory.owners: 3,
    UsageCategory.offers: 5,
    UsageCategory.requests: 2,
    UsageCategory.watchmen: 0,
    UsageCategory.offices: 1,
    UsageCategory.brokers: 5,
    UsageCategory.quotations: 4,
    UsageCategory.scanner: 5,
    UsageCategory.signature: 1,
    UsageCategory.imagesToPdf: 0,
    UsageCategory.combinePdfs: 2,
  };

  static const _items = [
    ItemEditUsage(
      category: UsageCategory.owners,
      title: 'Sample Owner A',
      editsUsed: 2,
    ),
    ItemEditUsage(
      category: UsageCategory.owners,
      title: 'Sample Owner B',
      editsUsed: 3,
    ),
  ];

  static const _usage = UsageSnapshot(
    state: UsageDataState.populated,
    created: _counts,
    items: _items,
  );

  static const free = SubscriptionPresentation(
    status: SubscriptionStatus.free,
    usage: _usage,
    isSample: true,
  );

  static const freeEmpty = SubscriptionPresentation(
    status: SubscriptionStatus.free,
    usage: UsageSnapshot(state: UsageDataState.empty),
    isSample: true,
  );

  static const freeLoading = SubscriptionPresentation(
    status: SubscriptionStatus.free,
    usage: UsageSnapshot(state: UsageDataState.loading),
    isSample: true,
  );

  static const freeUnavailable = SubscriptionPresentation(
    status: SubscriptionStatus.free,
    usage: UsageSnapshot.unavailable(),
    isSample: true,
  );

  static final renewing = SubscriptionPresentation(
    status: SubscriptionStatus.plusRenewing,
    cycle: PlusBillingCycle.annual,
    provider: BillingProvider.googlePlay,
    startedAt: DateTime(2027, 1, 1),
    paidThrough: DateTime(2028, 1, 1),
    nextChargeAt: DateTime(2028, 1, 1),
    renewalPrice: SubscriptionPolicy.annualPrice,
    isSample: true,
  );

  static final renewingAppStore = SubscriptionPresentation(
    status: SubscriptionStatus.plusRenewing,
    cycle: PlusBillingCycle.annual,
    provider: BillingProvider.appStore,
    startedAt: DateTime(2027, 1, 1),
    paidThrough: DateTime(2028, 1, 1),
    nextChargeAt: DateTime(2028, 1, 1),
    renewalPrice: SubscriptionPolicy.annualPrice,
    isSample: true,
  );

  static final tapManaged = SubscriptionPresentation(
    status: SubscriptionStatus.plusRenewing,
    cycle: PlusBillingCycle.monthly,
    provider: BillingProvider.tap,
    startedAt: DateTime(2027, 1, 1),
    paidThrough: DateTime(2027, 2, 1),
    nextChargeAt: DateTime(2027, 2, 1),
    renewalPrice: SubscriptionPolicy.monthlyPrice,
    isSample: true,
  );

  static final cancelScheduled = SubscriptionPresentation(
    status: SubscriptionStatus.plusCancelScheduled,
    cycle: PlusBillingCycle.monthly,
    provider: BillingProvider.googlePlay,
    startedAt: DateTime(2027, 1, 1),
    paidThrough: DateTime(2027, 2, 1),
    renewalPrice: SubscriptionPolicy.monthlyPrice,
    isSample: true,
  );

  static const expiredOverLimit = SubscriptionPresentation(
    status: SubscriptionStatus.expiredOverLimit,
    provider: BillingProvider.googlePlay,
    usage: UsageSnapshot(
      state: UsageDataState.populated,
      created: {
        UsageCategory.offers: 50,
        UsageCategory.owners: 80,
        UsageCategory.quotations: 30,
        UsageCategory.requests: 12,
        UsageCategory.watchmen: 2,
        UsageCategory.offices: 7,
        UsageCategory.brokers: 9,
        UsageCategory.scanner: 6,
        UsageCategory.signature: 1,
        UsageCategory.imagesToPdf: 0,
        UsageCategory.combinePdfs: 3,
      },
    ),
    isSample: true,
  );

  static const expiredWithinFree = SubscriptionPresentation(
    status: SubscriptionStatus.expiredWithinFree,
    provider: BillingProvider.googlePlay,
    usage: _usage,
    isSample: true,
  );

  static const paymentIssue = SubscriptionPresentation(
    status: SubscriptionStatus.paymentIssue,
    cycle: PlusBillingCycle.monthly,
    provider: BillingProvider.googlePlay,
    isSample: true,
  );

  static const activationPending = SubscriptionPresentation(
    status: SubscriptionStatus.activationPending,
    cycle: PlusBillingCycle.annual,
    provider: BillingProvider.googlePlay,
    isSample: true,
  );

  static const unknown = SubscriptionPresentation(
    status: SubscriptionStatus.unavailable,
    isSample: true,
  );

  static const offline = SubscriptionPresentation(
    status: SubscriptionStatus.offline,
    isSample: true,
  );

  static List<(String, SubscriptionPresentation)> get plans => [
        ('Free', free),
        ('Plus, auto-renewal on', renewing),
        ('Plus, auto-renewal off', cancelScheduled),
        ('Plus, billed by App Store', renewingAppStore),
        ('Plus, billed by Tap Payments', tapManaged),
        ('Payment issue', paymentIssue),
        ('Activation pending', activationPending),
        ('Expired, over limit (read-only)', expiredOverLimit),
        ('Returned to Free, within limits', expiredWithinFree),
        ('Unknown', unknown),
        ('Offline', offline),
      ];
}
