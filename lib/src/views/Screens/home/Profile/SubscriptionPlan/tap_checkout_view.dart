import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/payment_navigation.dart';
import 'package:broker_wallet/src/services/subscription/tap_card_host.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/viewmodels/tap_checkout_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_labels.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

enum TapCheckoutMode { pay, changeCard, returning }

/// Payment review, Tap's secure card component, and the server-confirmed result.
/// The card fields belong to Tap. This screen receives a one-time token, and
/// only the server can turn a payment into Plus.
class TapCheckoutView extends StatefulWidget {
  const TapCheckoutView.pay({super.key, required PlusBillingCycle this.cycle})
      : mode = TapCheckoutMode.pay;

  const TapCheckoutView.changeCard({super.key})
      : mode = TapCheckoutMode.changeCard,
        cycle = null;

  const TapCheckoutView.returning({super.key})
      : mode = TapCheckoutMode.returning,
        cycle = null;

  final TapCheckoutMode mode;
  final PlusBillingCycle? cycle;

  @override
  State<TapCheckoutView> createState() => _TapCheckoutViewState();
}

class _TapCheckoutViewState extends State<TapCheckoutView> {
  late final bool _allowed = SubscriptionPlatformPolicy.canStartCheckout(
    SubscriptionPlatformPolicy.current,
    PaymentOption.tapCard,
  );
  late final TapCheckoutController _controller;
  TapCardHost? _card;
  bool _cardMounted = false;
  bool _cardReady = false;
  bool _cardValid = false;
  bool _tokenFailed = false;
  bool _hasReturn = true;

  bool get _isPay => widget.mode == TapCheckoutMode.pay;
  bool get _isChange => widget.mode == TapCheckoutMode.changeCard;

  @override
  void initState() {
    super.initState();
    _controller = TapCheckoutController(
      billing: BillingServices.billing(),
      subscription: BillingServices.subscription(),
      openPage: openPaymentPage,
    )..addListener(_onStep);
    if (!_allowed) return;
    if (widget.mode == TapCheckoutMode.returning) {
      final id = PaymentReturnStore.take();
      if (id == null) {
        _hasReturn = false;
      } else {
        unawaited(_controller.confirm(id));
      }
      return;
    }
    _card = createTapCardHost();
    unawaited(_controller.prepare(widget.cycle ?? PlusBillingCycle.monthly));
  }

  void _onStep() {
    if (!mounted) return;
    setState(() {});
    final step = _controller.step;
    if (step == TapCheckoutStep.ready && !_cardMounted && _card != null) {
      _cardMounted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _mountCard());
    }
    if (step == TapCheckoutStep.activated ||
        step == TapCheckoutStep.cardUpdated) {
      try {
        unawaited(context.read<SubscriptionStateController>().refresh());
      } on ProviderNotFoundException {
        // Nothing else on screen depends on the shared state.
      }
    }
  }

  Future<void> _mountCard() async {
    final session = _controller.session;
    final card = _card;
    if (!mounted || session == null || card == null) return;
    final locale = Localizations.localeOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await card.mount(
        TapCardConfig(
          publicKey: session.publicKey,
          amount: _isChange ? 1 : session.amount,
          currency: session.currency,
          arabic: locale.languageCode == 'ar',
          dark: dark,
        ),
        onReady: () {
          if (mounted) setState(() => _cardReady = true);
        },
        onValidity: (valid) {
          if (mounted) setState(() => _cardValid = valid);
        },
        onFailure: () {
          if (mounted && !_cardReady) _controller.cardFormFailed();
        },
      );
    } catch (_) {
      if (mounted) _controller.cardFormFailed();
    }
  }

  Future<void> _submit() async {
    final card = _card;
    setState(() => _tokenFailed = false);
    String? token;
    if (card != null) {
      _controller.beginTokenizing();
      try {
        token = await card.tokenize();
      } catch (_) {
        if (!mounted) return;
        _controller.tokenFailed();
        setState(() => _tokenFailed = true);
        return;
      }
    }
    if (_isChange) {
      await _controller.changeCard(cardToken: token);
    } else {
      await _controller.pay(widget.cycle!, cardToken: token);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStep);
    _controller.dispose();
    _card?.dispose();
    super.dispose();
  }

  PlanPrice get _price => widget.cycle == PlusBillingCycle.annual
      ? SubscriptionPolicy.annualPrice
      : SubscriptionPolicy.monthlyPrice;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = loc.translate(switch (widget.mode) {
      TapCheckoutMode.pay => 'subCheckoutTitle',
      TapCheckoutMode.changeCard => 'subChangeCardTitle',
      TapCheckoutMode.returning => 'subReturnTitle',
    });
    if (!_allowed) {
      return SubscriptionPage(
        title: title,
        children: [
          SubMessage(
            icon: Icons.cloud_off_outlined,
            tone: SubTone.neutral,
            title: loc.translate('subCheckoutUnavailableTitle'),
            body: loc.translate('subCheckoutUnavailableBody'),
          ),
        ],
      );
    }
    if (!_hasReturn) {
      return SubscriptionPage(
        title: title,
        children: [
          SubMessage(
            icon: Icons.receipt_long_outlined,
            tone: SubTone.neutral,
            title: loc.translate('subReturnNothingTitle'),
            body: loc.translate('subReturnNothingBody'),
          ),
          SubPrimaryButton(
            label: loc.translate('subViewMyPlan'),
            onPressed: () => context.go('/my-plan'),
          ),
        ],
      );
    }
    final step = _controller.step;
    return SubscriptionPage(
      title: title,
      children: switch (step) {
        TapCheckoutStep.preparing => [
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            SubBodyText(loc.translate('subCheckoutLoadingCard'), center: true),
          ],
        TapCheckoutStep.ready || TapCheckoutStep.paying => _form(loc, step),
        TapCheckoutStep.unavailable => _result(
            loc,
            icon: Icons.cloud_off_outlined,
            tone: SubTone.attention,
            title: 'subCheckoutUnavailableTitle',
            body: 'subCheckoutUnavailableBody',
          ),
        TapCheckoutStep.confirming => [
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            SubMessage(
              icon: Icons.verified_user_outlined,
              title: loc.translate('subCheckoutConfirmingTitle'),
              body: loc.translate('subCheckoutConfirmingBody'),
            ),
          ],
        TapCheckoutStep.activated => _result(
            loc,
            icon: Icons.check_rounded,
            title: 'subFlowSuccessTitle',
            body: 'subFlowSuccessBody',
            primary: 'subViewMyPlan',
          ),
        TapCheckoutStep.cardUpdated => _result(
            loc,
            icon: Icons.credit_score_rounded,
            title: 'subCardUpdatedTitle',
            body: 'subCardUpdatedBody',
            primary: 'subViewMyPlan',
          ),
        TapCheckoutStep.pending => [
            SubMessage(
              icon: Icons.hourglass_top_rounded,
              tone: SubTone.neutral,
              title: loc.translate('subReturnPendingTitle'),
              body: loc.translate('subReturnPendingBody'),
            ),
            if (_controller.startedId != null)
              SubPrimaryButton(
                label: loc.translate('subReturnCheckAgain'),
                onPressed: () => _controller.confirm(_controller.startedId!),
              ),
            SubSecondaryButton(
              label: loc.translate('subViewMyPlan'),
              onPressed: () => context.go('/my-plan'),
            ),
          ],
        TapCheckoutStep.failed => _result(
            loc,
            icon: Icons.error_outline_rounded,
            tone: SubTone.attention,
            title: 'subFlowFailedTitle',
            body: 'subFlowFailedBody',
            support: true,
          ),
        TapCheckoutStep.phoneRequired => _result(
            loc,
            icon: Icons.phone_iphone_rounded,
            tone: SubTone.attention,
            title: 'subCheckoutPhoneTitle',
            body: 'subCheckoutPhoneBody',
          ),
        TapCheckoutStep.alreadyPlus => _result(
            loc,
            icon: Icons.workspace_premium_outlined,
            title: 'subCheckoutAlreadyPlusTitle',
            body: 'subCheckoutAlreadyPlusBody',
            primary: 'subViewMyPlan',
          ),
      },
    );
  }

  List<Widget> _result(
    AppLocalizations loc, {
    required IconData icon,
    required String title,
    required String body,
    SubTone tone = SubTone.positive,
    String? primary,
    bool support = false,
  }) =>
      [
        SubMessage(
          icon: icon,
          tone: tone,
          title: loc.translate(title),
          body: loc.translate(body),
        ),
        if (primary != null)
          SubPrimaryButton(
            label: loc.translate(primary),
            onPressed: () => context.go('/my-plan'),
          ),
        if (support)
          SubSecondaryButton(
            label: loc.translate('contactUs'),
            onPressed: () => context.push('/contact-us'),
          ),
        if (primary == null)
          SubSecondaryButton(
            label: loc.translate('subBackToPlans'),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/subscription'),
          ),
      ];

  List<Widget> _form(AppLocalizations loc, TapCheckoutStep step) {
    final paying = step == TapCheckoutStep.paying;
    final card = _card;
    final canSubmit = !paying && (card == null || (_cardReady && _cardValid));
    final cycle = widget.cycle;
    return [
      if (_isPay && cycle != null) ...[
        SubCard(
          tinted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SubBodyText(loc.translate('subPaySelectedPlan')),
              const SizedBox(height: 4),
              Text(
                loc.fill('subBrokerPlusWithCycle', {
                  'cycle': loc.cycleName(cycle),
                }),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                loc.cyclePrice(cycle, _price),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_isChange) ...[
        SubNotice(
          icon: Icons.info_outline_rounded,
          text: loc.translate('subChangeCardNote'),
        ),
        const SizedBox(height: 12),
      ],
      if (card != null) ...[
        SubSection(loc.translate('subCheckoutCardHeading')),
        SubCard(
          child: Stack(
            children: [
              // Tap draws its own fields inside this element.
              SizedBox(height: 240, child: card.view()),
              if (!_cardReady)
                const Positioned.fill(
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
      SubBullet(
        loc.translate('subPayCardSecure'),
        icon: Icons.lock_outline_rounded,
      ),
      if (_isPay && cycle != null) ...[
        SubBullet(
          loc.fill(
            cycle == PlusBillingCycle.annual
                ? 'subPayRenewalAnnual'
                : 'subPayRenewalMonthly',
            {'price': loc.aed(_price)},
          ),
          icon: Icons.autorenew_rounded,
          tone: SubTone.neutral,
        ),
        SubBullet(
          loc.translate('subPayCancelCard'),
          icon: Icons.event_busy_outlined,
          tone: SubTone.neutral,
        ),
      ],
      if (_tokenFailed) ...[
        const SizedBox(height: 8),
        SubNotice(
          icon: Icons.error_outline_rounded,
          tone: SubTone.attention,
          text: loc.translate('subCheckoutCardError'),
        ),
      ],
      const SizedBox(height: 14),
      SubPrimaryButton(
        animateLabel: true,
        label: paying
            ? loc.translate('subCheckoutProcessing')
            : _isChange
                ? loc.translate('subChangeCardConfirm')
                : card == null
                    ? loc.translate('subCheckoutOpenSecure')
                    : loc.fill('subCheckoutPay', {'price': loc.aed(_price)}),
        onPressed: canSubmit ? _submit : null,
      ),
      SubSecondaryButton(
        label: loc.translate('subBackToPlans'),
        onPressed: paying
            ? null
            : () =>
                context.canPop() ? context.pop() : context.go('/subscription'),
      ),
    ];
  }
}
