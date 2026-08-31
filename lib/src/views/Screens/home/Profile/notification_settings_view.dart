import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_settings_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  late final NotificationSettingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = NotificationSettingsViewModel(
      authViewModel: context.read<AuthViewModel>(),
    )..initialize();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<NotificationSettingsViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)
                  .translate('notificationSettings')),
            ),
            body: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SwitchListTile.adaptive(
                        title: Text(AppLocalizations.of(context)
                            .translate('enableNotifications')),
                        subtitle: Text(
                          AppLocalizations.of(context)
                              .translate('turnOffToSilence'),
                        ),
                        value: vm.notificationsEnabled,
                        onChanged: vm.toggleMaster,
                      ),
                      const Divider(height: 32),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('offerRequestMatches'),
                        subtitle: AppLocalizations.of(context)
                            .translate('getAlertedWhenMatches'),
                        value: vm.toggles['matchAlerts'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('matchAlerts', value),
                      ),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('activeRequestReminders'),
                        subtitle: AppLocalizations.of(context)
                            .translate('remindMeAboutActiveRequests'),
                        value: vm.toggles['requestReminders'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('requestReminders', value),
                      ),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('openOfferReminders'),
                        subtitle: AppLocalizations.of(context)
                            .translate('followUpOnOffers'),
                        value: vm.toggles['offerReminders'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('offerReminders', value),
                      ),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('statusChanges'),
                        subtitle: AppLocalizations.of(context)
                            .translate('alertMeWhenStatusChanges'),
                        value: vm.toggles['statusReminders'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('statusReminders', value),
                      ),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('planAlerts'),
                        subtitle: AppLocalizations.of(context)
                            .translate('alertMeOnPlanChanges'),
                        value: vm.toggles['planAlerts'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('planAlerts', value),
                      ),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('appUpdates'),
                        subtitle: AppLocalizations.of(context)
                            .translate('alertMeOnNewVersions'),
                        value: vm.toggles['systemUpdates'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) =>
                            vm.toggleSetting('systemUpdates', value),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        AppLocalizations.of(context).translate('channels'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _ToggleTile(
                        title: AppLocalizations.of(context)
                            .translate('pushNotifications'),
                        subtitle: AppLocalizations.of(context)
                            .translate('showAlertsOnDevice'),
                        value: vm.toggles['push'] ?? true,
                        enabled: vm.notificationsEnabled,
                        onChanged: (value) => vm.toggleSetting('push', value),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: SwitchListTile.adaptive(
        title: Text(title),
        subtitle: Text(subtitle),
        value: enabled && value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
