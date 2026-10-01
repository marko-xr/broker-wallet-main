import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/services/subscription/debug_plus_billing_gateway.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_manage_sheet.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_secure_checkout_sheet.dart';

// DEBUG-ONLY. Nothing in this file is reachable in a release or profile
// build: every entry point checks `kDebugMode`, which is a compile-time
// constant, so the code is removed from release builds.
//
// It drives the *presentation* of the Plus screens so each state can be
// inspected before real billing exists. It does not create entitlement: the
// state it sets lives in memory, is marked as preview, is never persisted or
// sent anywhere, and the production gateway ignores it. Strings are
// intentionally English literals: this is a developer tool, not product UI.

/// App-bar action that opens the preview sheet. Renders nothing outside debug
/// builds.
class PlusDebugButton extends StatelessWidget {
  const PlusDebugButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Plus preview (debug)',
      icon: const Icon(Icons.science_outlined),
      onPressed: () => PlusDebugPreviewSheet.show(context),
    );
  }
}

class PlusDebugPreviewSheet extends StatefulWidget {
  const PlusDebugPreviewSheet({super.key, required this.hostContext});

  /// The screen the sheet was opened from. The hand-off sheets the preview can
  /// open are shown from it once this sheet has closed.
  final BuildContext hostContext;

  static Future<void> show(BuildContext context) {
    if (!kDebugMode) return Future<void>.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PlusDebugPreviewSheet(hostContext: context),
    );
  }

  @override
  State<PlusDebugPreviewSheet> createState() => _PlusDebugPreviewSheetState();
}

class _PlusDebugPreviewSheetState extends State<PlusDebugPreviewSheet> {
  SubscriptionPeriod _period = SubscriptionPeriod.annual;

  static const _entitlementLabels = <SubscriptionStatus, String>{
    SubscriptionStatus.free: 'Free',
    SubscriptionStatus.trial: 'Trial',
    SubscriptionStatus.active: 'Active',
    SubscriptionStatus.cancelledActive: 'Cancelled, still active',
    SubscriptionStatus.gracePeriod: 'Grace period',
    SubscriptionStatus.billingIssue: 'Billing issue',
    SubscriptionStatus.expired: 'Expired',
  };

  static const _offeringLabels = <DebugOfferingMode, String>{
    DebugOfferingMode.both: 'Monthly + annual',
    DebugOfferingMode.monthlyOnly: 'Monthly only',
    DebugOfferingMode.annualOnly: 'Annual only',
    DebugOfferingMode.none: 'None (unavailable)',
  };

  static const _purchaseOutcomes = <PurchasePhase, String>{
    PurchasePhase.success: 'Success',
    PurchasePhase.pending: 'Pending',
    PurchasePhase.cancelled: 'Cancelled',
    PurchasePhase.storeProblem: 'Store problem',
    PurchasePhase.networkProblem: 'Network',
    PurchasePhase.verificationFailed: 'Verification failed',
    PurchasePhase.unknownFailure: 'Unknown failure',
  };

  static const _purchaseJumps = <PurchasePhase, String>{
    PurchasePhase.waitingForStore: 'Processing',
    PurchasePhase.success: 'Success',
    PurchasePhase.pending: 'Pending',
    PurchasePhase.cancelled: 'Cancelled',
    PurchasePhase.storeProblem: 'Store problem',
    PurchasePhase.networkProblem: 'Network',
    PurchasePhase.verificationFailed: 'Verification failed',
    PurchasePhase.unknownFailure: 'Unknown failure',
  };

  static const _restoreOutcomes = <RestorePhase, String>{
    RestorePhase.restored: 'Restored',
    RestorePhase.nothingFound: 'Nothing found',
    RestorePhase.conflict: 'Conflict',
    RestorePhase.failed: 'Error',
    RestorePhase.unavailable: 'Unavailable',
  };

  static const _restoreJumps = <RestorePhase, String>{
    RestorePhase.restoring: 'Restoring',
    RestorePhase.restored: 'Restored',
    RestorePhase.nothingFound: 'Nothing found',
    RestorePhase.conflict: 'Conflict',
    RestorePhase.failed: 'Error',
    RestorePhase.unavailable: 'Unavailable',
  };

  static const _screens = <String, String>{
    PlusRoutes.billing: 'Subscription & Billing',
    PlusRoutes.manage: 'Manage subscription',
    PlusRoutes.changePeriod: 'Change billing period',
    PlusRoutes.paymentDetails: 'Payment details',
    PlusRoutes.paymentMethods: 'Payment method',
    PlusRoutes.paymentMethodsAdd: 'Add payment method',
    PlusRoutes.paymentMethodsManage: 'Manage payment methods',
    PlusRoutes.paymentMethodsBackup: 'Backup payment methods',
    PlusRoutes.paymentMethodsBilling: 'Manage billing',
    PlusRoutes.paymentMethodsHelp: 'Payment method help',
    PlusRoutes.history: 'Billing history (empty)',
    PlusRoutes.help: 'Subscription help',
    PlusRoutes.legal: 'Legal',
    PlusRoutes.usage: 'Plan usage',
    PlusRoutes.paywall: 'Paywall',
    PlusRoutes.review: 'Purchase review',
  };

  static const _handoffs = <PlusManageAction, String>{
    PlusManageAction.addPaymentMethod: 'Add / change payment method',
    PlusManageAction.updatePaymentMethod: 'Update payment method',
    PlusManageAction.managePaymentMethods: 'Manage payment methods',
    PlusManageAction.backupPaymentMethods: 'Backup payment methods',
    PlusManageAction.manage: 'Manage in store',
    PlusManageAction.changePeriod: 'Change billing period',
    PlusManageAction.resubscribe: 'Resubscribe',
  };

  /// Closes this sheet, then opens a store hand-off sheet over the screen it
  /// came from.
  void _showHandoff(PlusSubscriptionViewModel vm, PlusManageAction action) {
    final host = widget.hostContext;
    final store = vm.effectiveStore;
    final managementUri = vm.entitlement.managementUri;
    Navigator.of(context).pop();
    if (!host.mounted) return;
    PlusManageSheet.show(
      host,
      store: store,
      action: action,
      managementUri: managementUri,
    );
  }

  void _showSecureCheckout(PlusSubscriptionViewModel vm) {
    final host = widget.hostContext;
    final store = vm.effectiveStore;
    Navigator.of(context).pop();
    if (!host.mounted) return;
    PlusSecureCheckoutSheet.show(host, store: store, isPreview: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final vm = context.watch<PlusSubscriptionViewModel>();
    final config = vm.debugPreviewConfig;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plus preview (debug only)',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Changes what the screens display, in this session only. It is '
              'never real entitlement, is not saved, and does not exist in '
              'release builds.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _section('Current plan state', [
              for (final entry in _entitlementLabels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: vm.status == entry.key,
                  onSelected: (_) => vm.debugApplyEntitlement(
                    DebugPlusPreviewData.entitlementFor(
                      entry.key,
                      period: _period,
                      store: vm.debugStore,
                    ),
                  ),
                ),
            ]),
            _section('Billed through (store wording)', [
              for (final store in const [
                PlusStore.googlePlay,
                PlusStore.appStore,
              ])
                ChoiceChip(
                  label: Text(
                    store == PlusStore.googlePlay ? 'Google Play' : 'App Store',
                  ),
                  selected: vm.effectiveStore == store,
                  onSelected: (_) {
                    vm.debugSetStore(store);
                    if (vm.status != SubscriptionStatus.free) {
                      vm.debugApplyEntitlement(
                        DebugPlusPreviewData.entitlementFor(
                          vm.status,
                          period: _period,
                          store: store,
                        ),
                      );
                    }
                  },
                ),
            ]),
            _section('Billing period of that state', [
              for (final period in SubscriptionPeriod.values)
                ChoiceChip(
                  label: Text(period.name),
                  selected: _period == period,
                  onSelected: (_) {
                    setState(() => _period = period);
                    if (vm.status != SubscriptionStatus.free) {
                      vm.debugApplyEntitlement(
                        DebugPlusPreviewData.entitlementFor(
                          vm.status,
                          period: period,
                          store: vm.debugStore,
                        ),
                      );
                    }
                  },
                ),
            ]),
            if (config != null) ...[
              _section('Plans offered', [
                for (final entry in _offeringLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: config.offeringMode == entry.key,
                    onSelected: (_) {
                      config.offeringMode = entry.key;
                      vm.debugReloadOffering();
                    },
                  ),
                FilterChip(
                  label: const Text('7-day free trial'),
                  selected: config.trialDays > 0,
                  onSelected: (on) {
                    config.trialDays =
                        on ? DebugPlusPreviewData.previewTrialDays : 0;
                    vm.debugReloadOffering();
                  },
                ),
              ]),
              _section('Next purchase ends in', [
                for (final entry in _purchaseOutcomes.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: config.purchaseOutcome == entry.key,
                    onSelected: (_) =>
                        setState(() => config.purchaseOutcome = entry.key),
                  ),
              ]),
              _section('Next restore ends in', [
                for (final entry in _restoreOutcomes.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: config.restoreOutcome == entry.key,
                    onSelected: (_) =>
                        setState(() => config.restoreOutcome = entry.key),
                  ),
              ]),
            ],
            _section('Open a screen', [
              for (final entry in _screens.entries)
                ActionChip(
                  label: Text(entry.value),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push(entry.key);
                  },
                ),
            ]),
            _section('Open a store hand-off sheet', [
              for (final entry in _handoffs.entries)
                ActionChip(
                  label: Text(entry.value),
                  onPressed: () => _showHandoff(vm, entry.key),
                ),
              ActionChip(
                label: const Text('Secure checkout'),
                onPressed: () => _showSecureCheckout(vm),
              ),
            ]),
            _section('Show purchase screen state', [
              for (final entry in _purchaseJumps.entries)
                ActionChip(
                  label: Text(entry.value),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    vm.debugShowPurchasePhase(entry.key);
                    Navigator.of(context).pop();
                    router.push(PlusRoutes.purchase);
                  },
                ),
            ]),
            _section('Show restore screen state', [
              for (final entry in _restoreJumps.entries)
                ActionChip(
                  label: Text(entry.value),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    vm.debugShowRestorePhase(entry.key);
                    Navigator.of(context).pop();
                    router.push(PlusRoutes.restore);
                  },
                ),
            ]),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                vm.debugReset();
                if (config != null) {
                  config
                    ..offeringMode = DebugOfferingMode.both
                    ..trialDays = 0
                    ..purchaseOutcome = PurchasePhase.success
                    ..restoreOutcome = RestorePhase.restored;
                  vm.debugReloadOffering();
                }
                setState(() => _period = SubscriptionPeriod.annual);
              },
              child: const Text('Reset preview to Free'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: chips),
        ],
      ),
    );
  }
}
