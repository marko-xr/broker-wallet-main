import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_scope.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _selectionMotion = Duration(milliseconds: 180);

/// Opens the sheet for a selected Plus plan. Android gets the payment-method
/// sheet; iPhone gets plan details only. Neither one starts a transaction.
Future<void> showSubscriptionPlanSheet(
  BuildContext context, {
  required PlusBillingCycle cycle,
  PaymentOption? initialOption,
  PaymentSheetState sheetState = PaymentSheetState.ready,
}) async {
  final presentation = SubscriptionScope.of(context);
  final platform = SubscriptionPlatformPolicy.current;
  final options = SubscriptionPlatformPolicy.paymentOptions(
    platform,
    presentation,
  );
  final canContinue = sheetState == PaymentSheetState.ready &&
      SubscriptionPlatformPolicy.canPreviewCheckout(presentation);
  // A sample never reaches a real payment.
  final storeAvailable = BillingServices.store().isAvailable;
  final realOptions = {
    if (sheetState == PaymentSheetState.ready && !presentation.isSample)
      for (final option in options)
        if (SubscriptionPlatformPolicy.canStartCheckout(
          platform,
          option,
          cardTestAllowed: SubscriptionPlatformPolicy.androidCardTestAllowed ||
              presentation.tapCardEligibilityVerified,
          storeAvailable: storeAvailable,
        ))
          option,
  };
  final colors = Theme.of(context).colorScheme;
  final request = await showModalBottomSheet<PaymentReviewRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim.withValues(alpha: 0.55),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => options.isEmpty
        ? PlanInfoSheet(cycle: cycle)
        : PaymentMethodSheet(
            cycle: cycle,
            options: options,
            initialOption: initialOption,
            sheetState: sheetState,
            canContinue: canContinue,
            realOptions: realOptions,
          ),
  );
  if (request == null || !context.mounted) return;
  if (realOptions.contains(request.option)) {
    final cycle =
        request.cycle == PlusBillingCycle.annual ? 'annual' : 'monthly';
    final route = request.option == PaymentOption.googlePlay
        ? SubscriptionRoutes.playCheckout
        : SubscriptionRoutes.checkout;
    await context.push('$route?cycle=$cycle');
    return;
  }
  if (!canContinue) return;
  await context.push(SubscriptionRoutes.flowState, extra: request);
}

PlanPrice _priceFor(PlusBillingCycle cycle) => cycle == PlusBillingCycle.annual
    ? SubscriptionPolicy.annualPrice
    : SubscriptionPolicy.monthlyPrice;

/// Android: selected plan, payment method, what happens next, one CTA.
class PaymentMethodSheet extends StatefulWidget {
  const PaymentMethodSheet({
    super.key,
    required this.cycle,
    required this.options,
    required this.canContinue,
    this.initialOption,
    this.sheetState = PaymentSheetState.ready,
    this.realOptions = const {},
  });

  final PlusBillingCycle cycle;
  final List<PaymentOption> options;

  /// True only for a labelled debug sample. It opens a sample review.
  final bool canContinue;

  /// The options that start a real, server-verified payment on this build.
  final Set<PaymentOption> realOptions;
  final PaymentOption? initialOption;
  final PaymentSheetState sheetState;

  @override
  State<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<PaymentMethodSheet> {
  late PaymentOption _selected = widget.options.contains(widget.initialOption)
      ? widget.initialOption!
      : widget.options.first;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final ready = widget.sheetState == PaymentSheetState.ready;
    final isReal = widget.realOptions.contains(_selected);
    return _SheetShell(
      header: _SheetHeader(title: loc.translate('subPayTitle')),
      content: [
        _PlanSummary(cycle: widget.cycle),
        const SizedBox(height: 16),
        ...switch (widget.sheetState) {
          PaymentSheetState.loading => [
              SubBodyText(loc.translate('subPayLoading')),
              const SizedBox(height: 10),
              const SubSkeleton(lines: 4),
            ],
          PaymentSheetState.providerUnavailable => [
              SubMessage(
                icon: Icons.cloud_off_outlined,
                tone: SubTone.attention,
                title: loc.translate('subPayProviderUnavailableTitle'),
                body: loc.fill('subPayProviderUnavailableBody', {
                  'provider': loc.paymentProviderName(_selected),
                }),
              ),
            ],
          PaymentSheetState.ready => [
              Semantics(
                header: true,
                child: Text(
                  loc.translate('paymentMethod'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              _PaymentTiles(
                options: widget.options,
                selected: _selected,
                onSelect: (option) => setState(() => _selected = option),
              ),
              const SizedBox(height: 14),
              _OptionDetails(
                options: widget.options,
                selected: _selected,
                cycle: widget.cycle,
              ),
            ],
        },
        const SizedBox(height: 10),
        if (!isReal)
          SubNotConnectedNotice(
            textKey:
                widget.canContinue ? 'subPayPreviewOnly' : 'subPayNotConnected',
          ),
      ],
      footer: [
        SubPrimaryButton(
          animateLabel: true,
          label: loc.translate(
            _selected == PaymentOption.googlePlay
                ? 'subContinueGoogle'
                : 'subContinueCard',
          ),
          onPressed: ready && (widget.canContinue || isReal)
              ? () => Navigator.of(context).pop(
                    PaymentReviewRequest(
                      cycle: widget.cycle,
                      option: _selected,
                    ),
                  )
              : null,
        ),
        SubSecondaryButton(
          label: loc.translate('subBackToPlans'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// iPhone: plan details only, with one acknowledgment and no payment step.
class PlanInfoSheet extends StatelessWidget {
  const PlanInfoSheet({super.key, required this.cycle});

  final PlusBillingCycle cycle;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _SheetShell(
      content: [
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                size: 30,
                color: subToneColor(colors, SubTone.positive),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            loc.fill('subBrokerPlusWithCycle', {
              'cycle': loc.cycleName(cycle),
            }),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loc.cyclePrice(cycle, _priceFor(cycle)),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: subToneColor(colors, SubTone.positive),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        SubBullet(loc.translate('subPlusBulletCreations')),
        SubBullet(loc.translate('subPlusBulletEdits')),
        SubBullet(loc.translate('subPlusBulletAccess')),
        const SizedBox(height: 10),
        SubBodyText(loc.translate('subPlatformInfoNotice'), center: true),
      ],
      footer: [
        SubPrimaryButton(
          label: loc.translate('subGotIt'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Handle, optional header, scrollable content and footer. The footer stays
/// pinned unless large text needs the whole sheet to scroll.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.content,
    required this.footer,
    this.header,
  });

  final Widget? header;
  final List<Widget> content;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final pinned = MediaQuery.textScalerOf(context).scale(100) / 100 <= 1.3;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              if (pinned && header != null)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 6),
                  child: header,
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!pinned && header != null) ...[
                        header!,
                        const SizedBox(height: 6),
                      ],
                      ...content,
                      if (!pinned) ...[const SizedBox(height: 12), ...footer],
                    ],
                  ),
                ),
              ),
              if (pinned)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child:
                      Column(mainAxisSize: MainAxisSize.min, children: footer),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        IconButton(
          tooltip: loc.translate('subClose'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.cycle});

  final PlusBillingCycle cycle;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final annual = cycle == PlusBillingCycle.annual;
    return SubCard(
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubBodyText(loc.translate('subPaySelectedPlan')),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                loc.fill('subBrokerPlusWithCycle', {
                  'cycle': loc.cycleName(cycle),
                }),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (annual)
                SubPill(
                  loc.fill('subSavePercent', {
                    'percent': '${SubscriptionPolicy.annualSavingPercent}',
                  }),
                  tone: SubTone.positive,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            loc.cyclePrice(cycle, _priceFor(cycle)),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          SubBodyText(
            annual
                ? loc.fill('subAnnualEquivalent', {
                    'price':
                        loc.aed(SubscriptionPolicy.annualMonthlyEquivalent),
                  })
                : loc.translate('subMonthlyNote'),
          ),
        ],
      ),
    );
  }
}

/// Two tiles side by side, or stacked when large text needs the width.
class _PaymentTiles extends StatelessWidget {
  const _PaymentTiles({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<PaymentOption> options;
  final PaymentOption selected;
  final ValueChanged<PaymentOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final tiles = [
      for (final option in options)
        _PaymentTile(
          option: option,
          selected: option == selected,
          onTap: () => onSelect(option),
        ),
    ];
    if (tiles.length == 1) {
      return SizedBox(width: double.infinity, child: tiles.single);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth / (tiles.length * scale) < 125) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [tiles.first, const SizedBox(height: 10), tiles.last],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles.first),
              const SizedBox(width: 10),
              Expanded(child: tiles.last),
            ],
          ),
        );
      },
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PaymentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isPlay = option == PaymentOption.googlePlay;
    final title =
        loc.translate(isPlay ? 'subProviderGooglePlay' : 'subPayCardTitle');
    final subtitle =
        loc.translate(isPlay ? 'subPayGoogleTile' : 'subProviderTap');
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '$title, $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            AnimatedContainer(
              duration: _selectionMotion,
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(12),
              decoration: subCardDecoration(
                colors,
                tinted: selected,
                selected: selected,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isPlay
                            ? Icons.play_circle_outline_rounded
                            : Icons.credit_card_rounded,
                        size: 24,
                        color: selected
                            ? subToneColor(colors, SubTone.positive)
                            : colors.onSurface.withValues(alpha: 0.7),
                      ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: _selectionMotion,
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          key: ValueKey(selected),
                          size: 20,
                          color: selected
                              ? colors.primary
                              : colors.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SubBodyText(subtitle),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: InkWell(borderRadius: radius, onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All options are laid out together, so the sheet keeps the height of the
/// tallest one and a selection cross-fades instead of resizing it.
class _OptionDetails extends StatelessWidget {
  const _OptionDetails({
    required this.options,
    required this.selected,
    required this.cycle,
  });

  final List<PaymentOption> options;
  final PaymentOption selected;
  final PlusBillingCycle cycle;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final price = loc.aed(_priceFor(cycle));
    final renewal = loc.fill(
      cycle == PlusBillingCycle.annual
          ? 'subPayRenewalAnnual'
          : 'subPayRenewalMonthly',
      {'price': price},
    );
    return Stack(
      children: [
        for (final option in options)
          AnimatedOpacity(
            opacity: option == selected ? 1 : 0,
            duration: _selectionMotion,
            child: ExcludeSemantics(
              excluding: option != selected,
              child: Column(
                children: [
                  SubBullet(
                    loc.translate(
                      option == PaymentOption.googlePlay
                          ? 'subPayGoogleBody'
                          : 'subPayCardBody',
                    ),
                    icon: Icons.storefront_outlined,
                    tone: SubTone.neutral,
                  ),
                  SubBullet(
                    loc.translate(
                      option == PaymentOption.googlePlay
                          ? 'subPayGoogleSecure'
                          : 'subPayCardSecure',
                    ),
                    icon: Icons.lock_outline_rounded,
                  ),
                  SubBullet(
                    renewal,
                    icon: Icons.autorenew_rounded,
                    tone: SubTone.neutral,
                  ),
                  SubBullet(
                    loc.translate(
                      option == PaymentOption.googlePlay
                          ? 'subPayCancelGoogle'
                          : 'subPayCancelCard',
                    ),
                    icon: Icons.event_busy_outlined,
                    tone: SubTone.neutral,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
