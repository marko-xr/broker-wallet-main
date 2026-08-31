import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'services/quotation_service.dart';

class QuotationListViewModel extends ChangeNotifier {
  final QuotationService _quotationService = QuotationService();

  // Loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Quotations list
  List<QuotationModel> _quotations = [];
  List<QuotationModel> get quotations => _quotations;

  // Stream subscription
  Stream<List<QuotationModel>>? _quotationsStream;
  Stream<List<QuotationModel>>? get quotationsStream => _quotationsStream;

  QuotationListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _quotationsStream = _quotationService.getUserQuotations();
  }

  // Refresh quotations
  Future<void> refreshQuotations() async {
    // The stream will automatically update when data changes
    _initializeStream();
  }

  // Delete a quotation
  Future<void> deleteQuotation(String quotationId, BuildContext context) async {
    try {
      await _quotationService.deleteQuotation(quotationId);

      if (context.mounted) {
        _showToast('Quotation deleted successfully', Colors.green);
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Failed to delete quotation: ${e.toString()}', Colors.red);
      }
    }
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

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
