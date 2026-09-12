// lib/src/views/Screens/home/Profile/about_broker_wallet_view.dart
//
// Displays only real, already-known app identity information (name,
// tagline, installed version read from the platform). No company/legal
// details are invented here.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';

class AboutBrokerWalletView extends StatelessWidget {
  const AboutBrokerWalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title:
            Text(loc.translate('aboutBrokerWallet'), style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppImages.mainAppIcon,
                  width: 72,
                  height: 72,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded,
                        color: colors.primary, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  loc.translate('appName'),
                  style: texts.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  loc.translate('appTagline'),
                  style: texts.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final versionText = snapshot.hasData
                        ? '${loc.translate('appVersion').split(' ').first} '
                            '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                        : loc.translate('appVersion');
                    return Text(
                      versionText,
                      style: texts.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
