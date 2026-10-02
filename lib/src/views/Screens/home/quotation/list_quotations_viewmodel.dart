import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'services/quotation_service.dart';

class QuotationListViewModel extends ChangeNotifier {
  QuotationListViewModel({
    QuotationService? quotationService,
    void Function(String message, Color color)? toast,
  })  : _quotationService = quotationService ?? QuotationService(),
        _toast = toast ?? _showPlatformToast {
    _initializeStream();
  }

  final QuotationService _quotationService;
  final void Function(String message, Color color) _toast;

  // Loading state
  final bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Quotations list
  final List<QuotationModel> _quotations = [];
  List<QuotationModel> get quotations => _quotations;

  // Stream subscription
  Stream<List<QuotationModel>>? _quotationsStream;
  Stream<List<QuotationModel>>? get quotationsStream => _quotationsStream;

  void _initializeStream() {
    _quotationsStream = _quotationService.getUserQuotations();
  }

  // Refresh quotations
  Future<void> refreshQuotations() async {
    // The stream refreshes itself after every mutation
    _initializeStream();
  }

  /// A local file for the Quotation's PDF: this device's copy of that exact
  /// media object, or one download through a fresh short-lived signed link.
  /// Throws when it cannot be had.
  Future<File> resolvePdf(QuotationModel quotation) =>
      _quotationService.resolvePdfFile(quotation);

  // Delete a quotation (soft delete: the row is hidden, never destroyed here)
  Future<void> deleteQuotation(String quotationId, BuildContext context) async {
    final loc = AppLocalizations.of(context);
    try {
      await _quotationService.deleteQuotation(quotationId);

      if (context.mounted) {
        _toast('Quotation deleted successfully', Colors.green);
      }
    } catch (_) {
      if (context.mounted) {
        _toast(loc.translate('quotationDeleteFailed'), Colors.red);
      }
    }
  }

  static void _showPlatformToast(String message, Color bgColor) {
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
