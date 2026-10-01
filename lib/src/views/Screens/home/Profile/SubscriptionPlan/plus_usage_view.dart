import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/my_plan_usage_section.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';

/// Plan usage: how much of each section and Toolkit tool has been used.
///
/// The counters used to sit at the bottom of the plan screen, where they
/// competed with billing for attention. They are a secondary view, so they now
/// have a screen of their own under Subscription & Billing. Nothing about them
/// changed: the same isolated read of the legacy counters, and the same rule
/// that whether limits apply comes from the subscription presentation state.
class PlusUsageView extends StatelessWidget {
  const PlusUsageView({super.key, this.usageSection});

  /// Replaces the legacy usage section. Used by tests so the screen can be
  /// built without Firebase.
  final Widget? usageSection;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final onPlus = vm.status.isCurrentPlus;

    return PlusScreenScaffold(
      title: l10n.translate('plusUsageTitle'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            l10n.translate(onPlus ? 'plusUsagePlusBody' : 'plusUsageFreeBody'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
        ),
        usageSection ?? _UsageSlot(showLimits: !onPlus),
      ],
    );
  }
}

/// Builds the legacy usage section for the signed-in account, if any.
class _UsageSlot extends StatelessWidget {
  const _UsageSlot({required this.showLimits});

  final bool showLimits;

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthViewModel>().currentUserId;
    if (userId == null) return const SizedBox.shrink();
    return MyPlanUsageSection(userId: userId, showLimits: showLimits);
  }
}
