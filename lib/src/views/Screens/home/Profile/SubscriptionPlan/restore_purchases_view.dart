import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Restore Purchases. No store is connected, so the check action is disabled.
/// The restored state renders only inside a labelled debug sample.
class RestorePurchasesView extends StatelessWidget {
  const RestorePurchasesView({
    super.key,
    this.state = RestorePurchaseState.unavailable,
    this.onCheck,
    this.live = false,
  });

  /// True only when [state] is the server's answer, never a designed sample.
  final bool live;

  final RestorePurchaseState state;

  /// Asks the store and then the server. Null while no store is connected.
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = SubscriptionScope.of(context);
    final store = loc.storeName(p);
    final shown = state == RestorePurchaseState.restored && !p.isSample && !live
        ? RestorePurchaseState.unavailable
        : state;
    return SubscriptionPage(
      title: loc.translate('restorePurchases'),
      children: [
        if (shown == RestorePurchaseState.checking) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
        ],
        switch (shown) {
          RestorePurchaseState.ready => SubMessage(
              icon: Icons.restore_rounded,
              title: loc.translate('subRestoreReadyTitle'),
              body: loc.fill('subRestoreReadyBody', {'store': store}),
            ),
          RestorePurchaseState.checking => SubMessage(
              icon: Icons.manage_search_rounded,
              title: loc.translate('subRestoreCheckingTitle'),
              body: loc.fill('subRestoreCheckingBody', {'store': store}),
            ),
          RestorePurchaseState.nothingFound => SubMessage(
              icon: Icons.search_off_rounded,
              tone: SubTone.neutral,
              title: loc.translate('subRestoreNothingTitle'),
              body: loc.fill('subRestoreNothingBody', {'store': store}),
            ),
          RestorePurchaseState.unavailable => SubMessage(
              icon: Icons.cloud_off_outlined,
              tone: SubTone.neutral,
              title: loc.translate('subRestoreUnavailableTitle'),
              body: loc.translate('subRestoreUnavailableBody'),
            ),
          RestorePurchaseState.linkedToOtherAccount => SubMessage(
              icon: Icons.warning_amber_rounded,
              tone: SubTone.attention,
              title: loc.translate('subRestoreLinkedTitle'),
              body: loc.fill('subRestoreLinkedBody', {'store': store}),
            ),
          RestorePurchaseState.restored => SubMessage(
              icon: Icons.check_rounded,
              title: loc.translate('subRestoreDoneTitle'),
              body: loc.translate('subRestoreDoneBody'),
            ),
        },
        if (shown == RestorePurchaseState.ready ||
            shown == RestorePurchaseState.nothingFound ||
            shown == RestorePurchaseState.unavailable)
          SubPrimaryButton(
            label: loc.translate(
              shown == RestorePurchaseState.ready
                  ? 'subRestoreCheck'
                  : 'tryAgain',
            ),
            onPressed: onCheck,
          ),
        if (shown == RestorePurchaseState.restored)
          SubPrimaryButton(
            label: loc.translate('subViewMyPlan'),
            onPressed: () => context.push('/my-plan'),
          ),
        if (shown == RestorePurchaseState.linkedToOtherAccount ||
            shown == RestorePurchaseState.nothingFound ||
            shown == RestorePurchaseState.unavailable) ...[
          const SizedBox(height: 4),
          SubSecondaryButton(
            label: loc.translate('contactUs'),
            onPressed: () => context.push('/contact-us'),
          ),
        ],
      ],
    );
  }
}
