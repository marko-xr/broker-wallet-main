import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// The Broker Wallet-owned step before anything is done in the store: manage
/// or cancel the subscription, change its billing period, resubscribe, or add,
/// change or fix a payment method.
///
/// Broker Wallet has no cancellation, plan-change or payment logic of its own,
/// and it never holds a card: the subscription and its payment method belong
/// to the App Store or Google Play. This sheet explains what is about to
/// happen and where, shows the exact steps, and — only where a link is known
/// to be safe ([plusManagementUri]) — offers "Continue to <store>". Where no
/// such link exists it says so by giving the steps and a plain "Done", rather
/// than a button that pretends to go somewhere. It never claims that anything
/// was changed. Deleting a Broker Wallet account does not cancel the store
/// subscription, and the sheet says so wherever cancelling is involved.
class PlusManageSheet extends StatelessWidget {
  const PlusManageSheet({
    super.key,
    required this.store,
    this.action = PlusManageAction.manage,
    this.managementUri,
  });

  final PlusStore store;
  final PlusManageAction action;

  /// A management link from the billing source, when it supplied one.
  final Uri? managementUri;

  static Future<void> show(
    BuildContext context, {
    required PlusStore store,
    PlusManageAction action = PlusManageAction.manage,
    Uri? managementUri,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlusManageSheet(
        store: store,
        action: action,
        managementUri: managementUri,
      ),
    );
  }

  /// Cancelling or renewing is involved, so these carry the account-deletion
  /// reminder; billing period and payment-method sheets do not.
  bool get _carriesDeletionNote =>
      action == PlusManageAction.manage ||
      action == PlusManageAction.resubscribe;

  String _title(AppLocalizations l10n, String storeName) {
    switch (action) {
      case PlusManageAction.manage:
        return l10n.plusText('plusManageTitle', {'store': storeName});
      case PlusManageAction.changePeriod:
        return l10n.plusText('plusChangePeriodTitle', {'store': storeName});
      case PlusManageAction.resubscribe:
        return l10n.plusText('plusResubscribeTitle', {'store': storeName});
      case PlusManageAction.addPaymentMethod:
        return l10n.translate('plusPayAddTitle');
      case PlusManageAction.managePaymentMethods:
        return l10n.translate('plusPayManageTitle');
      case PlusManageAction.backupPaymentMethods:
        return l10n.translate('plusPayBackupTitle');
      case PlusManageAction.updatePaymentMethod:
        return l10n.translate('plusPayUpdateTitle');
    }
  }

  String _intro(AppLocalizations l10n, String storeName) {
    if (action.isPaymentMethodAction) {
      switch (store) {
        case PlusStore.googlePlay:
          return l10n.translate('plusPayIntroGoogle');
        case PlusStore.appStore:
          return l10n.translate('plusPayIntroApple');
        case PlusStore.unknown:
          return l10n.translate('plusPayIntroGeneric');
      }
    }
    if (action == PlusManageAction.changePeriod) {
      return l10n.plusText('plusChangePeriodIntro', {'store': storeName});
    }
    return l10n.plusText('plusManageIntro', {'store': storeName});
  }

  List<String> _stepKeys() {
    switch (store) {
      case PlusStore.googlePlay:
        switch (action) {
          case PlusManageAction.manage:
          case PlusManageAction.changePeriod:
          case PlusManageAction.resubscribe:
            return const [
              'plusManageStepAndroid1',
              'plusManageStepAndroid2',
              'plusManageStepAndroid3',
            ];
          case PlusManageAction.addPaymentMethod:
            return const [
              'plusManageStepAndroid1',
              'plusPayStepAndroidMethods',
              'plusPayStepAndroidAdd',
            ];
          case PlusManageAction.managePaymentMethods:
            return const [
              'plusManageStepAndroid1',
              'plusPayStepAndroidMethods',
              'plusPayStepAndroidManage',
            ];
          case PlusManageAction.backupPaymentMethods:
            return const [
              'plusManageStepAndroid1',
              'plusManageStepAndroid2',
              'plusPayStepAndroidBackup',
            ];
          case PlusManageAction.updatePaymentMethod:
            return const [
              'plusManageStepAndroid1',
              'plusManageStepAndroid2',
              'plusPayStepAndroidUpdate',
            ];
        }
      case PlusStore.appStore:
        if (action.isPaymentMethodAction) {
          return const [
            'plusManageStepIos1',
            'plusPayStepIosPayment',
            'plusPayStepIosAdd',
          ];
        }
        return const [
          'plusManageStepIos1',
          'plusManageStepIos2',
          'plusManageStepIos3',
        ];
      case PlusStore.unknown:
        if (action.isPaymentMethodAction) {
          return const ['plusManageStepGeneric1', 'plusPayStepGenericPayment'];
        }
        return const ['plusManageStepGeneric1', 'plusManageStepGeneric2'];
    }
  }

  Future<void> _openStore(BuildContext context, Uri uri) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.translate('plusManageOpenFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, store);
    final uri = plusManagementUri(store, action, supplied: managementUri);
    final steps = [for (final key in _stepKeys()) l10n.translate(key)];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _title(l10n, storeName),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _intro(l10n, storeName),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.8),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < steps.length; i++)
                PlusStepRow(number: i + 1, text: steps[i]),
              if (action == PlusManageAction.resubscribe) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.translate('plusResubscribeHint'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
              if (action.isPaymentMethodAction) ...[
                const SizedBox(height: 12),
                if (uri != null) ...[
                  Text(
                    l10n.plusText('plusPayContinueNote', {'store': storeName}),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                PlusFootnote(
                  l10n.translate('plusPaySafetyNote'),
                  icon: Icons.lock_outline_rounded,
                ),
              ],
              if (_carriesDeletionNote) ...[
                const SizedBox(height: 16),
                PlusNoticeCard(
                  icon: Icons.info_outline_rounded,
                  title: l10n.translate('plusDeleteAccountNoteTitle'),
                  body: l10n.plusText(
                    'plusDeleteAccountNote',
                    {'store': storeName},
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (uri != null) ...[
                PlusPrimaryButton(
                  label: l10n.plusText('plusContinueToStore', {
                    'store': storeName,
                  }),
                  onPressed: () => _openStore(context, uri),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: colors.onSurface.withValues(alpha: 0.75),
                  ),
                  child: Text(
                    l10n.translate('notNow'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ] else
                PlusPrimaryButton(
                  label: l10n.translate('done'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
