import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Staging subscription test control in My Plan.
///
/// Drawn only in a debug build pointed at a Staging backend, for an account
/// the server says is allowlisted. It holds no state of its own: the switch
/// shows what the server last confirmed, and every action is the server's to
/// accept or refuse. Hiding it is a convenience; the protection is server-side.
class SubscriptionTestModeSection extends StatelessWidget {
  const SubscriptionTestModeSection({super.key});

  static bool get buildAllows =>
      kDebugMode &&
      SupabaseConfig.subscriptionBackendEnabled &&
      SupabaseConfig.isStagingBackend;

  @override
  Widget build(BuildContext context) {
    if (!buildAllows) return const SizedBox.shrink();
    final controller = context.watch<SubscriptionStateController>();
    final state = controller.serverState;
    if (state == null || !state.testModeAvailable) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _TestModeCard(controller: controller, state: state),
    );
  }
}

class _TestModeCard extends StatelessWidget {
  const _TestModeCard({required this.controller, required this.state});

  final SubscriptionStateController controller;
  final SubscriptionServerState state;

  Future<void> _confirmReset(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(loc.translate('stagingTestResetUsage')),
        content: Text(loc.translate('stagingTestResetConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(loc.translate('notNow')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(loc.translate('stagingTestResetAction')),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.runTestAction('reset_usage');
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = controller.testBusy;
    final on = state.testPlusOn;
    return SubCard(
      // The list tiles paint their ink on this, above the card's background.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  loc.translate('stagingTestModeTitle'),
                  style: theme.textTheme.titleSmall,
                ),
                SubPill(
                  loc.translate('stagingTestBadge'),
                  tone: SubTone.attention,
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: busy
                  ? null
                  : (next) =>
                      controller.runTestAction(next ? 'plus_on' : 'plus_off'),
              title: Text(
                loc.translate(
                  on ? 'stagingTestOnBody' : 'stagingTestOffBody',
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (controller.testError != null)
              SubNotice(
                icon: Icons.error_outline_rounded,
                tone: SubTone.attention,
                text: loc.translate('stagingTestRefused'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                loc.translate('stagingTestAdvanced'),
                style: theme.textTheme.bodyMedium,
              ),
              children: [
                SubSecondaryButton(
                  label: loc.translate('stagingTestCanceled'),
                  onPressed: busy
                      ? null
                      : () => controller.runTestAction('auto_renew_off'),
                ),
                const SizedBox(height: 8),
                SubSecondaryButton(
                  label: loc.translate('stagingTestExpired'),
                  onPressed:
                      busy ? null : () => controller.runTestAction('expired'),
                ),
                const SizedBox(height: 8),
                SubSecondaryButton(
                  label: loc.translate('stagingTestResetUsage'),
                  onPressed: busy ? null : () => _confirmReset(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
