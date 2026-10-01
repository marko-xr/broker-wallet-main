import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/common/routes/plus_routes.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/viewmodels/plus_subscription_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_billing_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_payment_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_screen_scaffold.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';
import 'package:broker_wallet/src/views/Widgets/settings_section_card.dart';

/// Add payment method: a full screen with the weight of a checkout step, but
/// not a card form.
///
/// A large provider visual says who the user is about to deal with, three short
/// lines say what to know (what is billed through the provider, that the method
/// is added securely in their account, and that Broker Wallet never receives or
/// stores card details), and one large pinned action continues to the store,
/// with a quiet secondary action under it.
///
/// There is no field for a card number, expiry, CVV, cardholder name or postal
/// code, and there never will be: the credential UI is the store's. "Continue"
/// opens the short hand-off step ([showPlusHandoff]), which gives the exact
/// steps because no official, verified link to a store account's payment
/// methods is assumed; it does not claim the store was opened.
///
/// FUTURE SEAM: once Google Play Billing is integrated, Google's own purchase
/// sheet shows the user's eligible saved payment methods and the option to add
/// one. Broker Wallet will not list or simulate them; this screen stays the
/// explanation that comes before it.
class PlusAddPaymentMethodView extends StatelessWidget {
  const PlusAddPaymentMethodView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlusSubscriptionViewModel>();
    final l10n = AppLocalizations.of(context);
    final state = vm.entitlement;
    final store = vm.effectiveStore;
    final isApple = store == PlusStore.appStore;
    final storeName = plusStoreName(l10n, store);

    final String billedKey;
    final String secureKey;
    switch (store) {
      case PlusStore.googlePlay:
        billedKey = 'plusAddLineBilledGoogle';
        secureKey = 'plusAddLineSecureGoogle';
      case PlusStore.appStore:
        billedKey = 'plusAddLineBilledApple';
        secureKey = 'plusAddLineSecureApple';
      case PlusStore.unknown:
        billedKey = 'plusAddLineBilledGeneric';
        secureKey = 'plusAddLineSecureGeneric';
    }

    final continueLabel = isApple
        ? l10n.translate('plusContinueToApple')
        : l10n.plusText('plusContinueToStore', {'store': storeName});

    return PlusScreenScaffold(
      title: l10n.translate('plusPayAddTitle'),
      bottom: PlusBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlusPrimaryButton(
              label: continueLabel,
              onPressed: () => showPlusHandoff(
                context,
                state: state,
                store: store,
                action: PlusManageAction.addPaymentMethod,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => context.push(PlusRoutes.paymentMethodsHelp),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(
                l10n.translate(isApple ? 'plusAddHelpApple' : 'plusAddHowTo'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      children: [
        if (state.isPreview) ...[
          const PlusPreviewBanner(),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        PlusProviderHero(store: store),
        const SizedBox(height: 24),
        PlusIconLine(
          icon: Icons.receipt_long_outlined,
          text: l10n.translate(billedKey),
        ),
        PlusIconLine(
          icon: Icons.verified_user_outlined,
          text: l10n.translate(secureKey),
        ),
        PlusIconLine(
          icon: Icons.lock_outline_rounded,
          text: l10n.translate('plusAddLineNoCard'),
        ),
        // Apple: the subscription itself is managed in the App Store, a
        // separate task from adding a payment method.
        if (isApple && state.status.isCurrentPlus) ...[
          const SizedBox(height: 16),
          SettingsSectionCard(
            children: [
              PlusActionRow(
                icon: Icons.receipt_long_outlined,
                tone: PlusTone.neutral,
                title: l10n.plusText('plusPmManageSubscription', {
                  'store': storeName,
                }),
                onTap: () => context.push(PlusRoutes.paymentMethodsBilling),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
