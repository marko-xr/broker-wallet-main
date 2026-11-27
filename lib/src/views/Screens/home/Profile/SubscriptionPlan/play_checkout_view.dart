import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/subscription/billing_availability.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/viewmodels/subscription_checkout_controller.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

enum _PlayStep { loading, ready, unavailable, buying, done }

/// Review with Google Play's own price, Google Play's purchase sheet, then the
/// server's verdict. The store answer alone never shows Plus as active.
class PlayCheckoutView extends StatefulWidget {
  const PlayCheckoutView({super.key, required this.cycle});

  final PlusBillingCycle cycle;

  @override
  State<PlayCheckoutView> createState() => _PlayCheckoutViewState();
}

class _PlayCheckoutViewState extends State<PlayCheckoutView> {
  final StorePurchaseGateway _store = BillingServices.store();
  _PlayStep _step = _PlayStep.loading;
  StoreProduct? _product;
  CheckoutResult? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_store.isAvailable || !BillingAvailability.backendEnabled) {
      setState(() => _step = _PlayStep.unavailable);
      return;
    }
    List<StoreProduct> products;
    try {
      products = await _store.loadProducts();
    } catch (_) {
      products = const [];
    }
    if (!mounted) return;
    final match = products.where((p) => p.cycle == widget.cycle);
    setState(() {
      _product = match.isEmpty ? null : match.first;
      _step = _product == null ? _PlayStep.unavailable : _PlayStep.ready;
    });
  }

  Future<void> _buy() async {
    setState(() => _step = _PlayStep.buying);
    final result = await SubscriptionCheckoutController(
      store: _store,
      backend: BillingServices.subscription(),
      billing: BillingServices.billing(),
    ).purchase(widget.cycle);
    if (!mounted) return;
    if (result == CheckoutResult.activated) {
      try {
        unawaited(context.read<SubscriptionStateController>().refresh());
      } on ProviderNotFoundException {
        // Nothing else on screen depends on the shared state.
      }
    }
    setState(() {
      _result = result;
      _step = _PlayStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SubscriptionPage(
      title: loc.translate('subCheckoutTitle'),
      children: switch (_step) {
        _PlayStep.loading || _PlayStep.buying => [
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            SubBodyText(
              loc.translate(_step == _PlayStep.loading
                  ? 'subPayLoading'
                  : 'subCheckoutConfirmingTitle'),
              center: true,
            ),
          ],
        _PlayStep.unavailable => [
            SubMessage(
              icon: Icons.cloud_off_outlined,
              tone: SubTone.neutral,
              title: loc.translate('subPlayUnavailableTitle'),
              body: loc.translate('subPlayUnavailableBody'),
            ),
            SubSecondaryButton(
              label: loc.translate('subBackToPlans'),
              onPressed: () => context.pop(),
            ),
          ],
        _PlayStep.ready => _review(context, loc, _product!),
        _PlayStep.done => _outcome(context, loc, _result!),
      },
    );
  }

  List<Widget> _review(
    BuildContext context,
    AppLocalizations loc,
    StoreProduct product,
  ) {
    final theme = Theme.of(context);
    final annual = widget.cycle == PlusBillingCycle.annual;
    return [
      SubCard(
        tinted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SubBodyText(loc.translate('subPaySelectedPlan')),
            const SizedBox(height: 4),
            Text(
              loc.fill('subBrokerPlusWithCycle', {
                'cycle': loc.cycleName(widget.cycle),
              }),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            // Google Play's own price for this account and country.
            Text(product.priceLabel, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SubBullet(
        loc.translate('subPayGoogleSecure'),
        icon: Icons.lock_outline_rounded,
      ),
      SubBullet(
        loc.fill(annual ? 'subPayRenewalAnnual' : 'subPayRenewalMonthly', {
          'price': product.priceLabel,
        }),
        icon: Icons.autorenew_rounded,
        tone: SubTone.neutral,
      ),
      SubBullet(
        loc.translate('subPayCancelGoogle'),
        icon: Icons.event_busy_outlined,
        tone: SubTone.neutral,
      ),
      const SizedBox(height: 14),
      SubPrimaryButton(
        label: loc.translate('subContinueGoogle'),
        onPressed: _buy,
      ),
      SubSecondaryButton(
        label: loc.translate('subBackToPlans'),
        onPressed: () => context.pop(),
      ),
    ];
  }

  List<Widget> _outcome(
    BuildContext context,
    AppLocalizations loc,
    CheckoutResult result,
  ) {
    final store = loc.translate('subProviderGooglePlay');
    final (icon, tone, title, body) = switch (result) {
      CheckoutResult.activated => (
          Icons.check_rounded,
          SubTone.positive,
          loc.translate('subFlowSuccessTitle'),
          loc.translate('subFlowSuccessBody'),
        ),
      CheckoutResult.activationPending => (
          Icons.hourglass_top_rounded,
          SubTone.neutral,
          loc.translate('subPlayActivationPendingTitle'),
          loc.translate('subPlayActivationPendingBody'),
        ),
      CheckoutResult.purchasePending => (
          Icons.hourglass_top_rounded,
          SubTone.neutral,
          loc.translate('subFlowPendingTitle'),
          loc.fill('subFlowPendingBody', {'store': store}),
        ),
      CheckoutResult.cancelled => (
          Icons.close_rounded,
          SubTone.neutral,
          loc.translate('subFlowCanceledTitle'),
          loc.translate('subFlowCanceledBody'),
        ),
      CheckoutResult.linkedToOtherAccount => (
          Icons.warning_amber_rounded,
          SubTone.attention,
          loc.translate('subFlowMismatchTitle'),
          loc.fill('subFlowMismatchBody', {'store': store}),
        ),
      CheckoutResult.unavailable || CheckoutResult.nothingToRestore => (
          Icons.cloud_off_outlined,
          SubTone.neutral,
          loc.translate('subPlayUnavailableTitle'),
          loc.translate('subPlayUnavailableBody'),
        ),
      CheckoutResult.failed => (
          Icons.error_outline_rounded,
          SubTone.attention,
          loc.translate('subFlowFailedTitle'),
          loc.translate('subFlowFailedBody'),
        ),
    };
    return [
      SubMessage(icon: icon, tone: tone, title: title, body: body),
      SubPrimaryButton(
        label: loc.translate('subViewMyPlan'),
        onPressed: () => context.go('/my-plan'),
      ),
      if (result == CheckoutResult.failed ||
          result == CheckoutResult.linkedToOtherAccount)
        SubSecondaryButton(
          label: loc.translate('contactUs'),
          onPressed: () => context.push('/contact-us'),
        ),
    ];
  }
}
