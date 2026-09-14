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
import 'package:broker_wallet/src/views/Widgets/delete_account_sheet.dart';
import 'package:broker_wallet/src/viewmodels/profile_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/data/models/info_placeholder_args.dart';

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
                              Text(vm.currentUser?.email ?? 'user@example.com',
                                  style: texts.bodyMedium),
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
                              subtitle: localization
                                  .translate('notificationsSettingsHint'),
                              hasSwitch: true,
                              switchValue: vm.notificationsEnabled,
                              onSwitch: vm.toggleNotifications,
                              onTap: () =>
                                  context.push('/notification-settings'),
                            ),
                          ],
                        ),

                        // ===== Category 2: Account & Billing =====
                        const SizedBox(height: 28),
                        SettingsSectionHeader(
                          title: localization.translate('accountBilling'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.premiumPlan,
                              isSvg: true,
                              title: localization.translate('subscription'),
                              subtitle: vm.isSubscribed
                                  ? '⭐ ${localization.translate('plusPlan')} - ${_getLocalizedPlanName(context, vm.currentUser?.subscription.plan ?? 'premium')}'
                                  : '${localization.translate('freePlan')} - ${localization.translate('upgradeToPremium')}',
                              hasTrailing: true,
                              trailingWidget: vm.isSubscribed
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                      ],
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        localization.translate('upgrade'),
                                        style: texts.labelSmall!.copyWith(
                                          color: colors.onPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                              onTap: () => context.push('/subscription'),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.premiumPlan,
                              isSvg: true,
                              title: localization.translate('myPlan'),
                              subtitle:
                                  localization.translate('viewQuotaUsage'),
                              onTap: () => context.push('/my-plan'),
                            ),
                          ],
                        ),

                        // ===== Category 3: Support & Information =====
                        const SizedBox(height: 28),
                        SettingsSectionHeader(
                          title: localization.translate('supportInformation'),
                        ),
                        SettingsSectionCard(
                          children: [
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.feedback,
                              isSvg: false,
                              materialIcon: Icons.support_agent_rounded,
                              title: localization.translate('helpSupport'),
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title: localization.translate('helpSupport'),
                                message: localization
                                    .translate('helpSupportPlaceholder'),
                                icon: Icons.support_agent_rounded,
                              ),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.lockPassword,
                              isSvg: false,
                              materialIcon: Icons.privacy_tip_rounded,
                              title: localization.translate('privacyPolicy'),
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title: localization.translate('privacyPolicy'),
                                message: localization
                                    .translate('privacyPolicyPlaceholder'),
                                icon: Icons.privacy_tip_rounded,
                              ),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.lockPassword,
                              isSvg: false,
                              materialIcon: Icons.description_rounded,
                              title: localization.translate('termsConditions'),
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title:
                                    localization.translate('termsConditions'),
                                message: localization
                                    .translate('termsConditionsPlaceholder'),
                                icon: Icons.description_rounded,
                              ),
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
                              iconAsset: SvgIcon.email,
                              isSvg: false,
                              materialIcon: Icons.mail_outline_rounded,
                              title: localization.translate('contactUs'),
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title: localization.translate('contactUs'),
                                message: localization
                                    .translate('contactUsPlaceholder'),
                                icon: Icons.mail_outline_rounded,
                              ),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.feedback,
                              isSvg: true,
                              title: localization.translate('feedBack'),
                              onTap: () => context.push('/feedback'),
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

                        // ===== Category 4: Privacy, Security & Account =====
                        const SizedBox(height: 28),
                        SettingsSectionHeader(
                          title:
                              localization.translate('privacySecurityAccount'),
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
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title: localization.translate('security'),
                                message: localization
                                    .translate('securityPlaceholder'),
                                icon: Icons.shield_outlined,
                              ),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.uploadMedia,
                              isSvg: false,
                              materialIcon: Icons.download_rounded,
                              title: localization.translate('exportData'),
                              subtitle:
                                  localization.translate('exportDataHint'),
                              onTap: () => _openInfoPlaceholder(
                                context,
                                title: localization.translate('exportData'),
                                message: localization
                                    .translate('exportDataPlaceholder'),
                                icon: Icons.download_rounded,
                              ),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.closeIcon,
                              isSvg: false,
                              materialIcon: Icons.delete_outline_rounded,
                              destructive: true,
                              title: localization.translate('deleteAccount'),
                              subtitle:
                                  localization.translate('deleteAccountHint'),
                              onTap: () => showDeleteAccountFlow(context),
                            ),
                            SettingsTile(
                              grouped: true,
                              iconAsset: SvgIcon.logOut,
                              isSvg: true,
                              title: localization.translate('logout'),
                              subtitle:
                                  vm.isLoggingOut ? 'Signing out...' : null,
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
                        const SizedBox(height: 32),
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

  /// Helper function to get localized plan name
  String _getLocalizedPlanName(BuildContext context, String plan) {
    final localization = AppLocalizations.of(context);
    final planLower = plan.toLowerCase();

    if (planLower == 'monthly') {
      return localization.translate('monthly');
    } else if (planLower == 'yearly') {
      return localization.translate('yearly');
    } else {
      // Fallback for 'premium' or any other plan type
      return localization.translate('premiumPlan');
    }
  }

  /// Navigates to the shared "not available yet" screen for
  /// Support & Information / Privacy-Security rows whose real
  /// implementation is deferred to a later checkpoint. Never invents
  /// policy, legal, or contact content — see [InfoPlaceholderView].
  void _openInfoPlaceholder(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) {
    context.push(
      '/info-placeholder',
      extra: InfoPlaceholderArgs(title: title, message: message, icon: icon),
    );
  }
}
