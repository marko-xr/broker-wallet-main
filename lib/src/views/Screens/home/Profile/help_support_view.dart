import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HelpSupportView extends StatelessWidget {
  const HelpSupportView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(loc.translate('helpSupport'), style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            SettingsSectionHeader(
              title: loc.translate('helpAccountSecurity'),
            ),
            SettingsSectionCard(
              children: [
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.profilePerson,
                  isSvg: true,
                  title: loc.translate('editProfile'),
                  subtitle: loc.translate('helpEditProfileHint'),
                  onTap: () => context.push('/edit-profile'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.lockPassword,
                  materialIcon: Icons.shield_outlined,
                  title: loc.translate('security'),
                  subtitle: loc.translate('securityHint'),
                  onTap: () => context.push('/security'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SettingsSectionHeader(title: loc.translate('helpFeedback')),
            SettingsSectionCard(
              children: [
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.feedback,
                  isSvg: true,
                  title: loc.translate('sendFeedback'),
                  subtitle: loc.translate('sendFeedbackHint'),
                  onTap: () => context.push('/feedback'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.email,
                  materialIcon: Icons.mail_outline_rounded,
                  title: loc.translate('contactUs'),
                  subtitle: loc.translate('contactUsHint'),
                  onTap: () => context.push('/contact-us'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SettingsSectionHeader(
              title: loc.translate('helpLegalInformation'),
            ),
            SettingsSectionCard(
              children: [
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.lockPassword,
                  materialIcon: Icons.privacy_tip_outlined,
                  title: loc.translate('privacyPolicy'),
                  onTap: () => context.push('/privacy-policy'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.lockPassword,
                  materialIcon: Icons.description_outlined,
                  title: loc.translate('termsConditions'),
                  onTap: () => context.push('/terms-conditions'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.subscription,
                  materialIcon: Icons.info_outline_rounded,
                  title: loc.translate('aboutBrokerWallet'),
                  onTap: () => context.push('/about'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
