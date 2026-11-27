import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Explains cancellation. It performs none: cancelling happens with the store.
class CancellationInfoView extends StatelessWidget {
  const CancellationInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final store = loc.storeName(p);
    final platform = SubscriptionPlatformPolicy.current;
    final path =
        SubscriptionPlatformPolicy.managementPath(platform, p.provider);
    final canOpenStore = path == ManagementPath.thisStore ||
        (path == ManagementPath.none &&
            SubscriptionPlatformPolicy.showsPurchaseJourney(platform));
    final until = p.paidThrough;
    final activeLine = p.hasVerifiedPlus && until != null
        ? loc.fill('subCancelActiveUntilDate', {'date': loc.shortDate(until)})
        : loc.translate('subCancelActiveUntilPaid');
    return SubscriptionPage(
      title: loc.translate('subCancelInfoTitle'),
      children: [
        SubHeading(loc.translate('subCancelHeading')),
        const SizedBox(height: 8),
        SubBodyText(activeLine),
        const SizedBox(height: 16),
        SubCard(
          child: Column(
            children: [
              SubBullet(loc.translate('subCancelNoRefund'),
                  icon: Icons.payments_outlined, tone: SubTone.neutral),
              SubBullet(loc.translate('subCancelNoNextBill'),
                  icon: Icons.event_available_outlined),
              SubBullet(loc.translate('subCancelRestrictions'),
                  icon: Icons.info_outline_rounded, tone: SubTone.neutral),
              SubBullet(loc.translate('subCancelRecordsSafe'),
                  icon: Icons.verified_user_outlined),
              SubBullet(loc.translate('subCancelDeleteApp'),
                  icon: Icons.phonelink_erase_outlined,
                  tone: SubTone.attention),
              SubBullet(loc.fill('subCancelWhere', {'store': store}),
                  icon: Icons.storefront_outlined, tone: SubTone.neutral),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SubBodyText(loc.translate('subCancelRefundRules')),
        const SizedBox(height: 16),
        const SubNotConnectedNotice(),
        const SizedBox(height: 16),
        if (canOpenStore) ...[
          SubPrimaryButton(
            label: loc.fill('subContinueToStore', {'store': store}),
            onPressed: null,
          ),
          const SizedBox(height: 4),
        ],
        SubSecondaryButton(
          label: loc.translate('subGoBack'),
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
