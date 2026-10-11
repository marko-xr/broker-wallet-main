import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/profile_feature_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyPlanView extends StatelessWidget {
  const MyPlanView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ProfileFeatureScaffold(
      title: loc.translate('myPlan'),
      icon: Icons.workspace_premium_outlined,
      statusTitle: loc.translate('planStatusUnavailable'),
      statusDescription: loc.translate('planInformationUnavailable'),
      children: [
        const SizedBox(height: 28),
        SettingsSectionHeader(title: loc.translate('planManagement')),
        SettingsSectionCard(
          children: [
            SettingsTile(
              grouped: true,
              iconAsset: SvgIcon.subscription,
              isSvg: true,
              title: loc.translate('subscriptions'),
              subtitle: loc.translate('viewSubscriptionOptions'),
              onTap: () => context.push('/subscription'),
            ),
          ],
        ),
      ],
    );
  }
}
