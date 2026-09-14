import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/delete_account_sheet.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SecurityView extends StatelessWidget {
  const SecurityView({super.key, this.user});

  /// Supplying a user is useful for isolated presentation tests. At runtime,
  /// identity always comes from the existing [AuthViewModel].
  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final currentUser = user ?? context.watch<AuthViewModel>().currentUser;
    final email = currentUser?.email.trim() ?? '';
    final phone = currentUser?.phoneNumber?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(loc.translate('securityCenter'), style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            SettingsSectionHeader(title: loc.translate('signInIdentity')),
            SettingsSectionCard(
              children: [
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.email,
                  materialIcon: Icons.alternate_email_rounded,
                  title: loc.translate('email'),
                  subtitle: email.isNotEmpty
                      ? email
                      : loc.translate('noEmailAdded'),
                  onTap: () => context.push('/edit-profile'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.profilePerson,
                  materialIcon: Icons.phone_outlined,
                  title: loc.translate('phoneNumber'),
                  subtitle:
                      phone.isNotEmpty ? phone : loc.translate('notAdded'),
                  onTap: () => context.push('/edit-profile'),
                ),
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.lockPassword,
                  isSvg: true,
                  title: loc.translate('password'),
                  subtitle: loc.translate('securityPasswordHint'),
                  onTap: () => context.push('/edit-profile'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SettingsSectionHeader(title: loc.translate('accountProtection')),
            SettingsSectionCard(
              children: [
                SettingsTile(
                  grouped: true,
                  iconAsset: SvgIcon.closeIcon,
                  materialIcon: Icons.delete_outline_rounded,
                  destructive: true,
                  title: loc.translate('deleteAccount'),
                  subtitle: loc.translate('deleteAccountHint'),
                  onTap: () => showDeleteAccountFlow(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
