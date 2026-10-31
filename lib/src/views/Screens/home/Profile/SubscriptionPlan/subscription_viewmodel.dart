import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

enum SubscriptionPlan { monthly, yearly }

class SubscriptionViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  SubscriptionViewModel({AuthRepository? authRepository})
      : _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository;

  SubscriptionPlan? _selectedPlan;
  bool _isLoading = false;
  bool _isTestMode = true; // Enable test mode for development

  String? get currentUserId => _authRepository.currentUserId;
  SubscriptionPlan? get selectedPlan => _selectedPlan;
  bool get isLoading => _isLoading;
  bool get isTestMode => _isTestMode;

  void selectPlan(SubscriptionPlan plan) {
    _selectedPlan = plan;
    notifyListeners();
  }

  /// PRODUCTION MODE: Real payment flow
  Future<void> subscribe(BuildContext context) async {
    if (_selectedPlan == null) return;

    final localization = AppLocalizations.of(context);

    // Show subscription confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmSubscription')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${localization.translate('plan')}: ${_selectedPlan == SubscriptionPlan.monthly ? localization.translate('monthlyPlan') : localization.translate('yearlyPlan')}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${localization.translate('price')}: ${_selectedPlan == SubscriptionPlan.monthly ? "15 AED/${localization.translate('month')}" : "120 AED/${localization.translate('year')}"}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(localization.translate('confirmSubscriptionMessage')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(localization.translate('subscribe')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Navigate to payment selection with the selected plan
      final planName =
          _selectedPlan == SubscriptionPlan.monthly ? 'monthly' : 'yearly';
      context.push('/payment-selection/$planName');
    }
  }
}
