import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/profile_feature_widgets.dart';
import 'package:flutter/material.dart';

class ExportDataView extends StatelessWidget {
  const ExportDataView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ProfileFeatureScaffold(
      title: loc.translate('exportData'),
      icon: Icons.download_rounded,
      statusTitle: loc.translate('exportUnavailable'),
      statusDescription: loc.translate('exportNotConnected'),
      children: [
        const SizedBox(height: 28),
        SettingsSectionHeader(title: loc.translate('exportYourData')),
        ProfileStatusCard(
          icon: Icons.folder_outlined,
          title: loc.translate('brokerWalletData'),
          description: loc.translate('exportDataExplanation'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.download_rounded),
            label: Text(loc.translate('exportData')),
          ),
        ),
      ],
    );
  }
}
