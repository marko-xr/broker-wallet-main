import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/offices_model.dart';
import '../../services/ScreenServices/office_service.dart';

class OfficesListViewModel extends ChangeNotifier {
  final OfficeService _officeService = OfficeService();

  // Loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Offices list
  List<OfficeModel> _offices = [];
  List<OfficeModel> get offices => _offices;

  // Stream subscription
  Stream<List<OfficeModel>>? _officesStream;
  Stream<List<OfficeModel>>? get officesStream => _officesStream;

  OfficesListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _officesStream = _officeService.getUserOffices();
  }

  // Refresh offices
  Future<void> refreshOffices() async {
    // The stream will automatically update when data changes
    _initializeStream();
    notifyListeners();
  }

  // Delete an office
  Future<void> deleteOffice(String officeId, BuildContext context) async {
    try {
      await _officeService.deleteOffice(officeId);

      if (context.mounted) {
        _showToast('Office deleted successfully', Colors.green);
        refreshOffices(); // Refresh the list after deletion
      }
    } catch (e) {
      if (context.mounted) {
        _showToast(
            'Unable to delete the office. Please try again.', Colors.red);
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
