import 'package:flutter/material.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/payment_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';

class PaymentSelectionView extends StatelessWidget {
  final SubscriptionPlan selectedPlan;

  const PaymentSelectionView({
    super.key,
    required this.selectedPlan,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PaymentViewModel(),
      child: Consumer<PaymentViewModel>(
        builder: (context, vm, _) {
          final localization = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final texts = theme.textTheme;

          return Scaffold(
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                localization.translate('paymentMethod'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localization.translate('orderSummary'),
                              style: texts.titleMedium!.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedPlan == SubscriptionPlan.monthly
                                      ? localization.translate('monthlyPlan')
                                      : localization.translate('yearlyPlan'),
                                  style: texts.bodyLarge,
                                ),
                                Text(
                                  selectedPlan == SubscriptionPlan.monthly
                                      ? '15 AED'
                                      : '120 AED',
                                  style: texts.titleMedium!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                            if (selectedPlan == SubscriptionPlan.yearly) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    localization.translate('discount'),
                                    style: texts.bodyMedium!.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                  Text(
                                    '-60 AED',
                                    style: texts.bodyMedium!.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  localization.translate('total'),
                                  style: texts.titleMedium!.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  selectedPlan == SubscriptionPlan.monthly
                                      ? '15 AED'
                                      : '120 AED',
                                  style: texts.titleLarge!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Payment Methods
                      Text(
                        localization.translate('selectPaymentMethod'),
                        style: texts.titleMedium!.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: ListView(
                          children: [
                            _buildPaymentOption(
                              context: context,
                              title: localization.translate('creditCard'),
                              subtitle:
                                  localization.translate('visaMastercard'),
                              icon: Icons.credit_card,
                              paymentMethod: PaymentMethod.creditCard,
                              isSelected: vm.selectedPaymentMethod ==
                                  PaymentMethod.creditCard,
                              onTap: vm.isProcessing
                                  ? null
                                  : () => vm.selectPaymentMethod(
                                      PaymentMethod.creditCard),
                              colors: colors,
                              texts: texts,
                            ),
                            _buildPaymentOption(
                              context: context,
                              title: 'Apple Pay',
                              subtitle:
                                  localization.translate('payWithApplePay'),
                              icon: Icons.apple,
                              paymentMethod: PaymentMethod.applePay,
                              isSelected: vm.selectedPaymentMethod ==
                                  PaymentMethod.applePay,
                              onTap: vm.isProcessing
                                  ? null
                                  : () => vm.selectPaymentMethod(
                                      PaymentMethod.applePay),
                              colors: colors,
                              texts: texts,
                            ),
                            _buildPaymentOption(
                              context: context,
                              title: 'Google Pay',
                              subtitle:
                                  localization.translate('payWithGooglePay'),
                              icon: Icons.android,
                              paymentMethod: PaymentMethod.googlePay,
                              isSelected: vm.selectedPaymentMethod ==
                                  PaymentMethod.googlePay,
                              onTap: vm.isProcessing
                                  ? null
                                  : () => vm.selectPaymentMethod(
                                      PaymentMethod.googlePay),
                              colors: colors,
                              texts: texts,
                            ),
                            _buildPaymentOption(
                              context: context,
                              title: 'PayPal',
                              subtitle: localization.translate('payWithPaypal'),
                              icon: Icons.payment,
                              paymentMethod: PaymentMethod.paypal,
                              isSelected: vm.selectedPaymentMethod ==
                                  PaymentMethod.paypal,
                              onTap: vm.isProcessing
                                  ? null
                                  : () => vm.selectPaymentMethod(
                                      PaymentMethod.paypal),
                              colors: colors,
                              texts: texts,
                            ),
                          ],
                        ),
                      ),

                      // Continue Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (vm.selectedPaymentMethod != null &&
                                  !vm.isProcessing)
                              ? () => vm.proceedToPayment(context, selectedPlan)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: vm.isProcessing
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimary,
                                  ),
                                )
                              : Text(
                                  localization.translate('continueToPayment'),
                                  style: texts.titleMedium!.copyWith(
                                    color: colors.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          localization.translate('securePayment'),
                          style: texts.bodySmall!.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Loading overlay
                if (vm.isProcessing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required PaymentMethod paymentMethod,
    required bool isSelected,
    required VoidCallback? onTap,
    required ColorScheme colors,
    required TextTheme texts,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: colors.primary,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: texts.titleMedium,
        ),
        subtitle: Text(
          subtitle,
          style: texts.bodySmall!.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Radio<PaymentMethod>(
          value: paymentMethod,
          groupValue: isSelected ? paymentMethod : null,
          onChanged: onTap != null ? (value) => onTap() : null,
          activeColor: colors.primary,
        ),
        tileColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? colors.primary
                : colors.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
