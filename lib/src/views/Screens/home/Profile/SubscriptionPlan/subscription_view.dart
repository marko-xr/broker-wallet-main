import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';

class SubscriptionView extends StatelessWidget {
  const SubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SubscriptionViewModel(),
      child: Consumer<SubscriptionViewModel>(
        builder: (context, vm, _) {
          final localization = AppLocalizations.of(context);
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final texts = theme.textTheme;

          return Scaffold(
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                localization.translate('subscription'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    localization.translate('choosePlan'),
                    style: texts.headlineMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localization.translate('unlockAllFeatures'),
                    style: texts.bodyLarge!.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Subscription Plans
                  Expanded(
                    child: Column(
                      children: [
                        // Monthly Plan
                        _buildPlanCard(
                          context: context,
                          title: localization.translate('monthlyPlan'),
                          price: '15 AED',
                          period: localization.translate('perMonth'),
                          isSelected:
                              vm.selectedPlan == SubscriptionPlan.monthly,
                          onTap: () => vm.selectPlan(SubscriptionPlan.monthly),
                          colors: colors,
                          texts: texts,
                        ),
                        const SizedBox(height: 16),

                        // Yearly Plan
                        _buildPlanCard(
                          context: context,
                          title: localization.translate('yearlyPlan'),
                          price: '120 AED',
                          period: localization.translate('perYear'),
                          discount: localization.translate('save33'),
                          isSelected:
                              vm.selectedPlan == SubscriptionPlan.yearly,
                          onTap: () => vm.selectPlan(SubscriptionPlan.yearly),
                          colors: colors,
                          texts: texts,
                          isRecommended: true,
                        ),
                        const SizedBox(height: 32),

                        // Features List
                        _buildFeaturesList(
                            context, localization, colors, texts),
                      ],
                    ),
                  ),

                  // Subscribe Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: vm.isLoading
                          ? null
                          : (vm.selectedPlan != null
                              ? () => vm.isTestMode
                                  ? vm.testSubscribe(context)
                                  : vm.subscribe(context)
                              : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: vm.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              vm.isTestMode
                                  ? '🧪 Test Subscribe'
                                  : localization.translate('subscribeNow'),
                              style: texts.titleMedium!.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Test Unsubscribe Button
                  if (vm.isTestMode)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: vm.isLoading
                            ? null
                            : () => vm.testUnsubscribe(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: colors.error),
                        ),
                        child: Text(
                          '🧪 Test Unsubscribe (Revert to Free)',
                          style: texts.titleMedium!.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard({
    required BuildContext context,
    required String title,
    required String price,
    required String period,
    String? discount,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colors,
    required TextTheme texts,
    bool isRecommended = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colors.primary
                : colors.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            if (isRecommended)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppLocalizations.of(context).translate('recommended'),
                  style: texts.labelSmall!.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (isRecommended) const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: texts.titleLarge!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (discount != null)
                      Text(
                        discount,
                        style: texts.bodySmall!.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: texts.headlineSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    Text(
                      period,
                      style: texts.bodySmall!.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesList(
    BuildContext context,
    AppLocalizations localization,
    ColorScheme colors,
    TextTheme texts,
  ) {
    final features = [
      localization.translate('unlimitedProperties'),
      localization.translate('prioritySupport'),
      localization.translate('exportReports'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localization.translate('includedFeatures'),
          style: texts.titleMedium!.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...features
            .map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: colors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature,
                          style: texts.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ],
    );
  }
}
