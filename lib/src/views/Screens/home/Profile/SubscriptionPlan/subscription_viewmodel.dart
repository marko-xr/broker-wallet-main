import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/quota_sync_service.dart';

enum SubscriptionPlan { monthly, yearly }

class SubscriptionViewModel extends ChangeNotifier {
  SubscriptionPlan? _selectedPlan;
  bool _isLoading = false;
  bool _isTestMode = true; // Enable test mode for development

  SubscriptionPlan? get selectedPlan => _selectedPlan;
  bool get isLoading => _isLoading;
  bool get isTestMode => _isTestMode;

  void selectPlan(SubscriptionPlan plan) {
    _selectedPlan = plan;
    notifyListeners();
  }

  /// TEST MODE: Subscribe without payment (for testing quota system)
  Future<void> testSubscribe(BuildContext context) async {
    if (_selectedPlan == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Fluttertoast.showToast(
          msg: 'Please login first',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }

      final planName =
          _selectedPlan == SubscriptionPlan.monthly ? 'monthly' : 'yearly';
      final expiresAt = _selectedPlan == SubscriptionPlan.monthly
          ? DateTime.now().add(const Duration(days: 30))
          : DateTime.now().add(const Duration(days: 365));

      // Update user subscription in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'plan': planName,
        'subscription': {
          'plan': planName,
          'isActive': true,
          'expiresAt': Timestamp.fromDate(expiresAt),
          'features': [
            'unlimited_items',
            'priority_support',
            'advanced_analytics'
          ],
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔄 Force immediate quota sync to update UI
      try {
        await QuotaSyncService().syncUserQuota();
      } catch (e) {
      }

      // ⏱️ Small delay to ensure Firestore stream propagates
      await Future.delayed(const Duration(milliseconds: 300));

      Fluttertoast.showToast(
        msg: '✅ Subscribed to $planName plan! Enjoy unlimited items.',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );

      if (context.mounted) {
        context.pop(); // Return to profile - stream will auto-update UI
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Subscription failed: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// TEST MODE: Unsubscribe (revert to free plan)
  Future<void> testUnsubscribe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe?'),
        content: const Text(
          'This will revert you to the FREE plan with 5 items per section limit.\n\n'
          '(This is for testing only)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _isLoading = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Revert to free plan
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'plan': 'free',
        'subscription': {
          'plan': 'free',
          'isActive': false,
          'expiresAt': null,
          'features': [],
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔄 Force immediate quota sync to update UI
      try {
        await QuotaSyncService().syncUserQuota();
      } catch (e) {
      }

      // ⏱️ Small delay to ensure Firestore stream propagates
      await Future.delayed(const Duration(milliseconds: 300));

      Fluttertoast.showToast(
        msg: '✅ Unsubscribed - Reverted to FREE plan (3 items per section)',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );

      if (context.mounted) {
        context.pop(); // Return to profile - stream will auto-update UI
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Unsubscribe failed: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
