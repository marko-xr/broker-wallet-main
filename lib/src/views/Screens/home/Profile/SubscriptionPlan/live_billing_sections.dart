import 'dart:async';

import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/subscription/billing_availability.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/payment_navigation.dart';
import 'package:broker_wallet/src/viewmodels/billing_center_controller.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Whether this build shows real billing data for this state.
bool showsLiveBilling(SubscriptionPresentation p) =>
    BillingAvailability.backendEnabled &&
    !p.isSample &&
    !p.isUnconfirmed &&
    SubscriptionPlatformPolicy.showsPurchaseJourney(
      SubscriptionPlatformPolicy.current,
    );

/// Card controls appear only where Tap may be presented: the web app, or a
/// debug build on isolated Staging. A store build on Android never shows them.
bool showsTapControls() =>
    SubscriptionPlatformPolicy.current == SubscriptionPlatform.web ||
    SubscriptionPlatformPolicy.androidCardTestAllowed;

/// The real billing view of the signed-in account.
class LiveBillingSection extends StatefulWidget {
  const LiveBillingSection({super.key, this.showHistory = true});

  final bool showHistory;

  @override
  State<LiveBillingSection> createState() => _LiveBillingSectionState();
}

class _LiveBillingSectionState extends State<LiveBillingSection> {
  late final BillingCenterController _controller =
      BillingCenterController(billing: BillingServices.billing());

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _setRenewal(BillingOverview overview, bool on) async {
    final loc = AppLocalizations.of(context);
    if (!on) {
      final until = overview.paidThrough;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(loc.translate('subTurnOffConfirmTitle')),
          content: Text(loc.fill('subTurnOffConfirmBody', {
            'date': until == null
                ? loc.translate('subPaidPeriodEnd')
                : loc.shortDate(until),
          })),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(loc.translate('subKeepRenewal')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(loc.translate('subTurnOffRenewal')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (await _controller.setAutoRenew(on) && mounted) {
      try {
        unawaited(context.read<SubscriptionStateController>().refresh());
      } on ProviderNotFoundException {
        // This section reloads its own data.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final overview = _controller.overview;
        if (_controller.isLoading && overview == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SubSkeleton(lines: 3),
          );
        }
        if (overview == null) {
          return Column(
            children: [
              SubNotice(
                icon: Icons.cloud_off_outlined,
                tone: SubTone.attention,
                text: loc.translate('subBillingLoadFailed'),
              ),
              SubSecondaryButton(
                label: loc.translate('tryAgain'),
                onPressed: _controller.load,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_controller.actionFailed) ...[
              SubNotice(
                icon: Icons.error_outline_rounded,
                tone: SubTone.attention,
                text: loc.translate('subActionFailed'),
              ),
              const SizedBox(height: 8),
            ],
            ..._providerControls(context, loc, overview),
            if (widget.showHistory) ..._history(context, loc, overview),
          ],
        );
      },
    );
  }

  List<Widget> _providerControls(
    BuildContext context,
    AppLocalizations loc,
    BillingOverview overview,
  ) {
    if (overview.provider == BillingProvider.googlePlay) {
      return [
        SubNotice(
          icon: Icons.storefront_outlined,
          text: loc.translate('subPlayManagedBody'),
        ),
        const SizedBox(height: 8),
        SubPrimaryButton(
          label: loc.translate('subOpenGooglePlay'),
          onPressed: () => unawaited(
            openGooglePlaySubscriptions(productId: overview.productId),
          ),
        ),
      ];
    }
    if (overview.provider != BillingProvider.tap || !showsTapControls()) {
      return const [];
    }
    final method = overview.paymentMethod;
    final active = const {'active', 'cancel_scheduled', 'billing_issue'}
        .contains(overview.state);
    return [
      SubSection(loc.translate('paymentMethod')),
      SubCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SubInfoRow(
              label: loc.translate('subBillingCard'),
              value: method?.lastFour == null
                  ? loc.translate('subBillingNoCard')
                  : loc.fill('subBillingCardLabel', {
                      'brand': method?.brand ?? '',
                      'last4': method!.lastFour!,
                    }).trim(),
            ),
            if (method?.expMonth != null && method?.expYear != null)
              SubInfoRow(
                label: loc.translate('subBillingCardExpiry'),
                value:
                    '${method!.expMonth.toString().padLeft(2, '0')}/${method.expYear}',
              ),
          ],
        ),
      ),
      if (overview.hasPaymentIssue) ...[
        const SizedBox(height: 8),
        SubNotice(
          icon: Icons.warning_amber_rounded,
          tone: SubTone.attention,
          text: loc.translate('subFixPaymentBody'),
        ),
      ],
      if (active && overview.canRenewOnFile) ...[
        const SizedBox(height: 10),
        SubPrimaryButton(
          label: loc.translate(
            overview.hasPaymentIssue ? 'subFixPayment' : 'subChangeCard',
          ),
          onPressed: _controller.isBusy
              ? null
              : () => context.push(SubscriptionRoutes.changeCard),
        ),
        SubSecondaryButton(
          label: loc.translate(
            overview.autoRenew ? 'subTurnOffRenewal' : 'subTurnOnRenewal',
          ),
          onPressed: _controller.isBusy
              ? null
              : () => _setRenewal(overview, !overview.autoRenew),
        ),
      ],
    ];
  }

  List<Widget> _history(
    BuildContext context,
    AppLocalizations loc,
    BillingOverview overview,
  ) {
    return [
      SubSection(loc.translate('purchaseHistory')),
      if (overview.history.isEmpty)
        SubCard(child: SubBodyText(loc.translate('subHistoryEmpty')))
      else
        SettingsSectionCard(
          children: [
            for (final entry in overview.history)
              SubNavTile(
                icon: Icons.receipt_outlined,
                title: loc.fill('subHistoryItem', {
                  'cycle': loc.cycleName(entry.cycle),
                  'amount': '${entry.currency} ${entry.amount}',
                }),
                subtitle:
                    '${loc.shortDate(entry.at)} · ${loc.translate(_statusKey(entry.status))}',
                onTap: () => _showReceipt(context, loc, entry),
              ),
          ],
        ),
    ];
  }

  static String _statusKey(BillingEntryStatus status) => switch (status) {
        BillingEntryStatus.processing => 'subHistoryProcessing',
        BillingEntryStatus.paid => 'subHistoryPaid',
        BillingEntryStatus.failed => 'subHistoryFailed',
        BillingEntryStatus.refunded => 'subHistoryRefunded',
      };

  void _showReceipt(
    BuildContext context,
    AppLocalizations loc,
    BillingHistoryEntry entry,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.translate('subReceiptTitle'),
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            for (final document in entry.documents) ...[
              const SizedBox(height: 12),
              _TaxDocumentCard(document: document),
            ],
            const SizedBox(height: 10),
            SubInfoRow(
              label: loc.translate('subPlan'),
              value: loc.fill('subBrokerPlusWithCycle', {
                'cycle': loc.cycleName(entry.cycle),
              }),
            ),
            SubInfoRow(
              label: loc.translate('subReceiptAmount'),
              value: '${entry.currency} ${entry.amount}',
            ),
            SubInfoRow(
              label: loc.translate('subReceiptDate'),
              value: loc.shortDate(entry.at),
            ),
            SubInfoRow(
              label: loc.translate('status'),
              value: loc.translate(_statusKey(entry.status)),
            ),
            SubInfoRow(
              label: loc.translate('subReceiptReference'),
              value: entry.id.split('-').first.toUpperCase(),
            ),
            if (entry.documents.isEmpty) ...[
              const SizedBox(height: 8),
              SubBodyText(loc.translate('subReceiptNote')),
            ],
            const SizedBox(height: 8),
            SubSecondaryButton(
              label: loc.translate('subClose'),
              onPressed: () => Navigator.of(sheet).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every field a UAE simplified tax invoice carries, as the server issued it.
class _TaxDocumentCard extends StatelessWidget {
  const _TaxDocumentCard({required this.document});

  final BillingTaxDocument document;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    String aed(int fils) => 'AED ${BillingTaxDocument.money(fils)}';
    final rate = document.vatRateBasisPoints % 100 == 0
        ? '${document.vatRateBasisPoints ~/ 100}%'
        : '${document.vatRateBasisPoints / 100}%';
    return SubCard(
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.translate(document.isCreditNote
                ? 'subCreditNoteTitle'
                : 'subTaxInvoiceTitle'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SubInfoRow(
            label: loc.translate('subInvoiceNumber'),
            value: document.number,
          ),
          SubInfoRow(
            label: loc.translate('subReceiptDate'),
            value: loc.shortDate(document.issuedAt),
          ),
          SubInfoRow(
            label: loc.translate('subInvoiceSupplier'),
            value: '${document.supplier}\n${document.address}',
          ),
          SubInfoRow(
              label: loc.translate('subInvoiceTrn'), value: document.trn),
          SubInfoRow(
            label: loc.translate('subInvoiceNet'),
            value: aed(document.netFils),
          ),
          SubInfoRow(
            label: loc.fill('subInvoiceVat', {'rate': rate}),
            value: aed(document.vatFils),
          ),
          SubInfoRow(
            label: loc.translate('subInvoiceTotal'),
            value: aed(document.totalFils),
          ),
        ],
      ),
    );
  }
}
