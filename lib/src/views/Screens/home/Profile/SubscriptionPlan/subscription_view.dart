import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/profile_feature_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The single customer-facing plan selection surface. Store products are not
/// connected yet, so no plan or purchase action can be offered as available.
class SubscriptionView extends StatelessWidget {
  const SubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final texts = Theme.of(context).textTheme;
    return ProfileFeatureScaffold(
      title: loc.translate('subscriptions'),
      icon: Icons.workspace_premium_outlined,
      statusTitle: loc.translate('subscriptionPlansUnavailable'),
      statusDescription: loc.translate('storeProductsNotConnected'),
      children: [
        const SizedBox(height: 28),
        SettingsSectionHeader(title: loc.translate('planOptions')),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              loc.translate('planOptionsAwaitStore'),
              style: texts.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: null,
            child: Text(loc.translate('subscribe')),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: null,
            child: Text(loc.translate('restorePurchases')),
          ),
        ),
        const SizedBox(height: 28),
        SettingsSectionHeader(title: loc.translate('legalAndApp')),
        SettingsSectionCard(
          children: [
            SettingsTile(
              grouped: true,
              iconAsset: SvgIcon.lockPassword,
              isSvg: false,
              materialIcon: Icons.privacy_tip_rounded,
              title: loc.translate('privacyPolicy'),
              onTap: () => context.push('/privacy-policy'),
            ),
            SettingsTile(
              grouped: true,
              iconAsset: SvgIcon.lockPassword,
              isSvg: false,
              materialIcon: Icons.description_rounded,
              title: loc.translate('termsConditions'),
              onTap: () => context.push('/terms-conditions'),
            ),
          ],
        ),
      ],
    );
  }
}
