// lib/src/views/profile/profile_view.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_tile.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/current_user_avatar.dart';
import 'package:broker_wallet/src/viewmodels/profile_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ProfileViewModel(
        themeVM: ctx.read<ThemeViewModel>(),
        localeVM: ctx.read<LocaleViewModel>(),
        authVM: ctx.read<AuthViewModel>(),
        context: context,
      ),
      child: Consumer2<ProfileViewModel, ThemeViewModel>(
        builder: (context, vm, themeVM, _) {
          final localization = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final texts = theme.textTheme;
          final resolvedName = vm.displayName.isNotEmpty
              ? vm.displayName
              : localization.translate('favoritesGuestUser');
          final email = vm.currentUser?.email.trim() ?? '';
          final phone = vm.currentUser?.phoneNumber?.trim() ?? '';
          final identity = email.isNotEmpty
              ? email
              : phone.isNotEmpty
                  ? phone
                  : localization.translate('profileIdentityUnavailable');

          // Show loading state while user data is being fetched
          if (vm.isLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              elevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              leadingWidth: 40,
              leading: const SizedBox(width: 40),
              title: Text(
                localization.translate('profile'),
                style: texts.headlineMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const CurrentUserAvatar(size: 64),
                              const SizedBox(height: 12),
                              Text(resolvedName, style: texts.titleLarge),
                              const SizedBox(height: 4),
                              Text(identity, style: texts.bodyMedium),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: vm.editProfile,
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      colors.primary.withValues(alpha: 0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  localization.translate('editProfile'),
                                  style: texts.labelLarge!
                                      .copyWith(color: colors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ===== Category 1: General Settings =====
                        SettingsSectionHeader(
                          title: localization.translate('generalSettings'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.language,
                              isSvg: true,
                              title: localization.translate('language'),
                              onTap: () => context.push('/language'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.theme,
                              isSvg: true,
                              title: localization.translate('theme'),
                              hasSwitch: true,
                              switchValue: themeVM.themeMode == ThemeMode.dark,
                              onSwitch: vm.toggleTheme,
                              switchLabel: themeVM.themeMode == ThemeMode.dark
                                  ? localization.translate('dark')
                                  : localization.translate('light'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.notifications,
                              isSvg: true,
                              title: localization.translate('notifications'),
                              onTap: () => context.push('/notification-settings'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // ===== Category 2: Plan & Billing =====
                        SettingsSectionHeader(
                          title: localization.translate('planBilling'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.premiumPlan,
                              isSvg: true,
                              title: localization.translate('myPlan'),
                              onTap: () => context.push('/my-plan'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.subscription,
                              isSvg: true,
                              title: localization.translate('subscriptions'),
                              onTap: () => context.push('/subscription'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.subscription,
                              isSvg: false,
                              materialIcon: Icons.receipt_long_rounded,
                              title: localization.translate('billingPayments'),
                              onTap: () => context.push('/billing-payments'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // ===== Category 3: Account & Security =====
                        SettingsSectionHeader(
                          title: localization.translate('accountSecurity'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.lockPassword,
                              isSvg: false,
                              materialIcon: Icons.shield_outlined,
                              title: localization.translate('security'),
                              subtitle: localization.translate('securityHint'),
                              onTap: () => context.push('/security'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.logOut,
                              isSvg: true,
                              title: localization.translate('logout'),
                              subtitle: vm.isLoggingOut
                                  ? localization.translate('signingOut')
                                  : null,
                              hasTrailing: vm.isLoggingOut,
                              trailingWidget: vm.isLoggingOut
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.primary,
                                      ),
                                    )
                                  : null,
                              onTap: vm.isLoggingOut ? null : vm.logout,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // ===== Category 4: Privacy & Data =====
                        SettingsSectionHeader(
                          title: localization.translate('privacyData'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.uploadMedia,
                              isSvg: false,
                              materialIcon: Icons.download_rounded,
                              title: localization.translate('exportData'),
                              onTap: () => context.push('/export-data'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.lockPassword,
                              isSvg: false,
                              materialIcon: Icons.privacy_tip_rounded,
                              title: localization.translate('privacyPolicy'),
                              onTap: () => context.push('/privacy-policy'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // ===== Category 5: Support =====
                        SettingsSectionHeader(
                          title: localization.translate('profileSupport'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.email,
                              isSvg: false,
                              materialIcon: Icons.mail_outline_rounded,
                              title: localization.translate('contactUs'),
                              onTap: () => context.push('/contact-us'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.feedback,
                              isSvg: true,
                              title: localization.translate('sendFeedback'),
                              onTap: () => context.push('/feedback'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // ===== Category 6: Legal & App =====
                        SettingsSectionHeader(
                          title: localization.translate('legalAndApp'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.lockPassword,
                              isSvg: false,
                              materialIcon: Icons.description_rounded,
                              title: localization.translate('termsConditions'),
                              onTap: () => context.push('/terms-conditions'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.subscription,
                              isSvg: false,
                              materialIcon: Icons.info_outline_rounded,
                              title:
                                  localization.translate('aboutBrokerWallet'),
                              onTap: () => context.push('/about'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.shareApp,
                              isSvg: true,
                              title: localization.translate('shareApp'),
                              onTap: vm.shareApp,
                            ),
                          ],
                        ),
                        const SizedBox(height: 96),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
