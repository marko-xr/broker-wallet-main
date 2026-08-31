import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../../services/ScreenServices/owner_service.dart';

class OwnersListViewModel extends ChangeNotifier {
  final OwnerService _ownerService = OwnerService();

  // Loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Owners list
  List<OwnerModel> _owners = [];
  List<OwnerModel> get owners => _owners;

  // Stream subscription
  Stream<List<OwnerModel>>? _ownersStream;
  Stream<List<OwnerModel>>? get ownersStream => _ownersStream;

  OwnersListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _ownersStream = _ownerService.getUserOwners();
  }

  // Refresh owners
  Future<void> refreshOwners() async {
    // The stream will automatically update when data changes
    _initializeStream();
    notifyListeners();
  }

  // Delete an owner
  Future<void> deleteOwner(String ownerId, BuildContext context) async {
    try {
      await _ownerService.deleteOwner(ownerId);

      if (context.mounted) {
        _showToast('Owner deleted successfully', Colors.green);
        refreshOwners(); // Refresh the list after deletion
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Unable to delete the owner. Please try again.', Colors.red);
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
