import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';

enum PaymentMethod { creditCard, applePay, googlePay, paypal }

class PaymentViewModel extends ChangeNotifier {
  PaymentMethod? _selectedPaymentMethod;
  bool _isProcessing = false;

  PaymentMethod? get selectedPaymentMethod => _selectedPaymentMethod;
  bool get isProcessing => _isProcessing;

  void selectPaymentMethod(PaymentMethod method) {
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  Future<void> proceedToPayment(
      BuildContext context, SubscriptionPlan plan) async {
    if (_selectedPaymentMethod == null) return;

    switch (_selectedPaymentMethod!) {
      case PaymentMethod.creditCard:
        // For now, simulate credit card processing
        await _processCreditCard(context, plan);
        break;
      case PaymentMethod.applePay:
        await _processApplePay(context, plan);
        break;
      case PaymentMethod.googlePay:
        await _processGooglePay(context, plan);
        break;
      case PaymentMethod.paypal:
        await _processPayPal(context, plan);
        break;
    }
  }

  Future<void> _processCreditCard(
      BuildContext context, SubscriptionPlan plan) async {
    _isProcessing = true;
    notifyListeners();

    // Simulate credit card processing
    await Future.delayed(const Duration(seconds: 2));

    _isProcessing = false;
    notifyListeners();

    // Show success and navigate
    _showSuccessAndNavigate(context);
  }

  Future<void> _processApplePay(
      BuildContext context, SubscriptionPlan plan) async {
    _isProcessing = true;
    notifyListeners();

    // Simulate Apple Pay processing
    await Future.delayed(const Duration(seconds: 2));

    _isProcessing = false;
    notifyListeners();

    // Show success and navigate
    _showSuccessAndNavigate(context);
  }

  Future<void> _processGooglePay(
      BuildContext context, SubscriptionPlan plan) async {
    _isProcessing = true;
    notifyListeners();

    // Simulate Google Pay processing
    await Future.delayed(const Duration(seconds: 2));

    _isProcessing = false;
    notifyListeners();

    // Show success and navigate
    _showSuccessAndNavigate(context);
  }

  Future<void> _processPayPal(
      BuildContext context, SubscriptionPlan plan) async {
    _isProcessing = true;
    notifyListeners();

    // Simulate PayPal processing
    await Future.delayed(const Duration(seconds: 3));

    _isProcessing = false;
    notifyListeners();

    // Show success and navigate
    _showSuccessAndNavigate(context);
  }

  void _showSuccessAndNavigate(BuildContext context) {
    if (!context.mounted) return;

    final localization = AppLocalizations.of(context);

    _showToast(localization.translate('paymentSuccessMessage'), Colors.green);

    // Navigate back to profile using go instead of pop
    context.go('/profile');
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }
}
