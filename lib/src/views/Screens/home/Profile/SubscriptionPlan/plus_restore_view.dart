import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_result_view.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Restore purchases: the path an iOS user (and anyone reinstalling) needs to
/// recover a subscription they already own.
///
/// Restoring never creates an entitlement. It asks the billing source what
/// the store account already holds, and the view model applies that answer
/// only if the source reports a Plus entitlement; otherwise the user is told
/// nothing was found.
class PlusRestoreView extends StatefulWidget {
  const PlusRestoreView({super.key});

  @override
  State<PlusRestoreView> createState() => _PlusRestoreViewState();
}

class _PlusRestoreViewState extends State<PlusRestoreView> {
  @override
  void initState() {
    super.initState();
    // Always open on the intro, not on a previous visit's result.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PlusSubscriptionViewModel>().resetRestore();
    });
  }

  void _leave(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(
          l10n.translate('plusRestorePurchases'),
          style: theme.textTheme.titleLarge,
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: _content(context, vm)),
    );
  }

  Widget _content(BuildContext context, PlusSubscriptionViewModel vm) {
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, vm.effectiveStore);

    switch (vm.restorePhase) {
      case RestorePhase.idle:
        return PlusResultView(
          icon: Icons.restore_rounded,
          tone: PlusTone.neutral,
          title: l10n.translate('plusRestoreTitle'),
          body: l10n.plusText('plusRestoreIntro', {'store': storeName}),
          extra: PlusNoticeCard(
            icon: Icons.info_outline_rounded,
            title: l10n.translate('plusRestoreNoChargeTitle'),
            body: l10n.translate('plusRestoreNoChargeBody'),
          ),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusRestorePurchases'),
              onPressed: () => unawaited(vm.restorePurchases()),
            ),
          ],
        );
      case RestorePhase.restoring:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.plusText('plusRestoring', {'store': storeName}),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      case RestorePhase.restored:
        return PlusResultView(
          icon: Icons.check_rounded,
          tone: PlusTone.positive,
          popIn: true,
          title: l10n.translate('plusRestoreSuccessTitle'),
          body: l10n.translate('plusRestoreSuccessBody'),
          extra: vm.entitlement.isPreview ? const PlusPreviewBanner() : null,
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusContinue'),
              onPressed: () => _leave(context),
            ),
          ],
        );
      case RestorePhase.nothingFound:
        return PlusResultView(
          icon: Icons.search_off_rounded,
          tone: PlusTone.neutral,
          title: l10n.translate('plusRestoreNothingTitle'),
          body: l10n.plusText('plusRestoreNothingBody', {'store': storeName}),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('done'),
              onPressed: () => _leave(context),
            ),
            PlusSecondaryButton(
              label: l10n.translate('plusContactSupport'),
              onPressed: () => context.push(PlusRoutes.support),
            ),
          ],
        );
      case RestorePhase.conflict:
        return PlusResultView(
          icon: Icons.manage_accounts_outlined,
          tone: PlusTone.attention,
          title: l10n.translate('plusRestoreConflictTitle'),
          body: l10n.translate('plusRestoreConflictBody'),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusContactSupport'),
              onPressed: () => context.push(PlusRoutes.support),
            ),
            PlusSecondaryButton(
              label: l10n.translate('done'),
              onPressed: () => _leave(context),
            ),
          ],
        );
      case RestorePhase.failed:
        return PlusResultView(
          icon: Icons.error_outline_rounded,
          tone: PlusTone.attention,
          title: l10n.translate('plusRestoreFailedTitle'),
          body: l10n.translate('plusRestoreFailedBody'),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusTryAgain'),
              onPressed: () => unawaited(vm.restorePurchases()),
            ),
            PlusSecondaryButton(
              label: l10n.translate('done'),
              onPressed: () => _leave(context),
            ),
          ],
        );
      case RestorePhase.unavailable:
        return PlusResultView(
          icon: Icons.schedule_rounded,
          tone: PlusTone.neutral,
          title: l10n.translate('plusRestoreUnavailableTitle'),
          body: l10n.translate('plusRestoreUnavailableBody'),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('done'),
              onPressed: () => _leave(context),
            ),
          ],
        );
    }
  }
}
