import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_result_view.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Everything that happens after the user confirms the review: the four
/// progress steps, then exactly one of success, pending, cancelled or a
/// failure. The screen reads the view model's phase and nothing else, so a
/// real billing source drives it without any change here.
///
/// Rules this screen enforces:
///  * while a purchase is in progress it cannot be left, and it offers no
///    button that could start a second one;
///  * success is only shown for [PurchasePhase.success], which the view model
///    only reaches when the billing source backed it with an entitlement;
///  * failures are described in plain language, never as raw errors.
class PlusPurchaseProgressView extends StatelessWidget {
  const PlusPurchaseProgressView({super.key});

  /// Clears the finished result after the navigation has left this screen,
  /// so the screen never flashes an empty state while it transitions out.
  void _acknowledgeAfterFrame(PlusSubscriptionViewModel vm) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => vm.acknowledgePurchaseResult());
  }

  void _backToPlans(BuildContext context, PlusSubscriptionViewModel vm) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(PlusRoutes.paywall);
    }
    _acknowledgeAfterFrame(vm);
  }

  void _finishSuccess(BuildContext context, PlusSubscriptionViewModel vm) {
    final router = GoRouter.of(context);
    router.go('/profile');
    // Land on Subscription & Billing so the user sees Plus reflected, with
    // Profile beneath.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => router.push(PlusRoutes.billing));
    _acknowledgeAfterFrame(vm);
  }

  void _done(BuildContext context, PlusSubscriptionViewModel vm) {
    GoRouter.of(context).go('/profile');
    _acknowledgeAfterFrame(vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final phase = vm.purchasePhase;

    return PopScope(
      // Never leave mid-purchase.
      canPop: !phase.isInProgress,
      child: Scaffold(
        body: SafeArea(child: _content(context, vm, phase)),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    PlusSubscriptionViewModel vm,
    PurchasePhase phase,
  ) {
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, vm.effectiveStore);

    if (phase.isInProgress) {
      return _ProgressBody(phase: phase, storeName: storeName);
    }

    switch (phase) {
      case PurchasePhase.success:
        return PlusResultView(
          icon: Icons.check_rounded,
          tone: PlusTone.positive,
          popIn: true,
          title: l10n.translate('plusSuccessTitle'),
          body: l10n.translate('plusSuccessBody'),
          extra: vm.entitlement.isPreview ? const PlusPreviewBanner() : null,
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusContinue'),
              onPressed: () => _finishSuccess(context, vm),
            ),
          ],
        );
      case PurchasePhase.pending:
        return PlusResultView(
          icon: Icons.schedule_rounded,
          tone: PlusTone.neutral,
          title: l10n.translate('plusPendingTitle'),
          body: l10n.translate('plusPendingBody'),
          extra: PlusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlusCheckRow(l10n.translate('plusPendingPointLeave')),
                PlusCheckRow(l10n.translate('plusPendingPointUpdate')),
              ],
            ),
          ),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('done'),
              onPressed: () => _done(context, vm),
            ),
          ],
        );
      case PurchasePhase.cancelled:
        return PlusResultView(
          icon: Icons.cancel_outlined,
          tone: PlusTone.neutral,
          title: l10n.translate('plusCancelledTitle'),
          body: l10n.translate('plusCancelledBody'),
          actions: [
            PlusPrimaryButton(
              label: l10n.translate('plusBackToPlans'),
              onPressed: () => _backToPlans(context, vm),
            ),
            PlusSecondaryButton(
              label: l10n.translate('plusTryAgain'),
              onPressed: () => unawaited(vm.beginPurchase()),
            ),
          ],
        );
      case PurchasePhase.storeProblem:
        return _failure(
          context,
          vm,
          icon: Icons.cloud_off_rounded,
          title: l10n.translate('plusStoreProblemTitle'),
          body: l10n.plusText('plusStoreProblemBody', {'store': storeName}),
          offerSupport: false,
        );
      case PurchasePhase.networkProblem:
        return _failure(
          context,
          vm,
          icon: Icons.wifi_off_rounded,
          title: l10n.translate('plusNetworkTitle'),
          body: l10n.translate('plusNetworkBody'),
          offerSupport: false,
        );
      case PurchasePhase.verificationFailed:
        return _failure(
          context,
          vm,
          icon: Icons.gpp_maybe_outlined,
          title: l10n.translate('plusVerificationTitle'),
          body: l10n.translate('plusVerificationBody'),
          offerSupport: true,
        );
      case PurchasePhase.unknownFailure:
        return _failure(
          context,
          vm,
          icon: Icons.error_outline_rounded,
          title: l10n.translate('plusUnknownTitle'),
          body: l10n.translate('plusUnknownBody'),
          offerSupport: true,
        );
      case PurchasePhase.idle:
      case PurchasePhase.initiating:
      case PurchasePhase.waitingForStore:
      case PurchasePhase.verifying:
      case PurchasePhase.finalizing:
        // `idle` only exists between a result being cleared and this screen
        // leaving; the in-progress phases are handled above.
        return const SizedBox.shrink();
    }
  }

  Widget _failure(
    BuildContext context,
    PlusSubscriptionViewModel vm, {
    required IconData icon,
    required String title,
    required String body,
    required bool offerSupport,
  }) {
    final l10n = AppLocalizations.of(context);
    return PlusResultView(
      icon: icon,
      tone: PlusTone.attention,
      title: title,
      body: body,
      actions: [
        PlusPrimaryButton(
          label: l10n.translate('plusTryAgain'),
          onPressed: () => unawaited(vm.beginPurchase()),
        ),
        PlusSecondaryButton(
          label: l10n.translate('plusBackToPlans'),
          onPressed: () => _backToPlans(context, vm),
        ),
        if (offerSupport)
          TextButton(
            onPressed: () => context.push(PlusRoutes.support),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(
              l10n.translate('plusContactSupport'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.phase, required this.storeName});

  final PurchasePhase phase;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final current = phase.stepIndex;

    final steps = <String>[
      l10n.translate('plusStepInitiating'),
      l10n.plusText('plusStepWaitingStore', {'store': storeName}),
      l10n.translate('plusStepVerifying'),
      l10n.translate('plusStepFinalizing'),
    ];

    return Center(
      child: SingleChildScrollView(
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
                l10n.translate('plusProgressTitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('plusProgressHint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.8),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 32),
            for (var i = 0; i < steps.length; i++)
              _StepTile(
                label: steps[i],
                state: i < current
                    ? _StepState.done
                    : i == current
                        ? _StepState.current
                        : _StepState.upcoming,
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepTile extends StatelessWidget {
  const _StepTile({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Widget marker;
    switch (state) {
      case _StepState.done:
        marker = Icon(Icons.check_circle_rounded, color: colors.primary);
      case _StepState.current:
        marker = SizedBox(
          width: 24,
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.primary,
            ),
          ),
        );
      case _StepState.upcoming:
        marker = Icon(
          Icons.radio_button_unchecked_rounded,
          color: colors.onSurface.withValues(alpha: 0.35),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 24, height: 24, child: marker),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: state == _StepState.current
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: state == _StepState.upcoming
                    ? colors.onSurface.withValues(alpha: 0.55)
                    : colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
