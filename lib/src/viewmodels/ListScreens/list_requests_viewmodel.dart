import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';

class RequestedListViewModel extends ChangeNotifier {
  final RequestService _requestService = RequestService();

  // Error state (used by UI when the StreamBuilder has an error)
  String? _error;
  String? get error => _error;

  // Requests list
  List<RequestModel> _requests = [];
  List<RequestModel> get requests => _requests;

  // Filter state for request type
  String? _selectedFilter; // null = all, 'rent' = rent only, 'sell' = sell only
  String? get selectedFilter => _selectedFilter;

  // Filter state for property status - determines which items to show
  bool _showInactiveOnly =
      false; // false = show active only, true = show inactive only
  bool get showInactiveOnly => _showInactiveOnly;

  // Stream of user requests
  late Stream<List<RequestModel>> _requestsStream;
  Stream<List<RequestModel>> get requestsStream => _requestsStream;

  // Filtered requests based on selected filters
  List<RequestModel> get filteredRequests {
    var filteredList = _requests;

    // First filter by status (active/inactive)
    if (_showInactiveOnly) {
      filteredList =
          filteredList.where((request) => request.status.isInactive).toList();
    } else {
      filteredList =
          filteredList.where((request) => request.status.isActive).toList();
    }

    // Then filter by request type if selected
    if (_selectedFilter != null) {
      filteredList = filteredList
          .where((request) => request.requestType == _selectedFilter)
          .toList();
    }

    return filteredList;
  }

  // Setter for requests (used by the view to update the list)
  set requests(List<RequestModel> newRequests) {
    _requests = newRequests;
  }

  RequestedListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _requestsStream = _requestService.getUserRequests().handleError((e) {
      _error = 'Unable to load requests. Please try again.';
      notifyListeners();
    });
  }

  Future<void> refreshRequests() async {
    // Recreate the stream to trigger listeners if needed.
    _initializeStream();
    notifyListeners();
  }

  Future<void> deleteRequest(String requestId, BuildContext context) async {
    try {
      await _requestService.deleteRequest(requestId);
      if (context.mounted) {
        _showToast('Request deleted successfully', Colors.green);
        await refreshRequests();
      }
    } catch (e) {
      if (context.mounted) {
        _showToast(
            'Unable to delete the request. Please try again.', Colors.red);
      }
    }
  }

  // Toggle filter for request type
  void toggleFilter(String requestType) {
    if (_selectedFilter == requestType) {
      // If the same filter is selected, clear it (show all)
      _selectedFilter = null;
    } else {
      // Set the new filter
      _selectedFilter = requestType;
    }
    notifyListeners();
  }

  // Clear filter (show all requests)
  void clearFilter() {
    _selectedFilter = null;
    notifyListeners();
  }

  // Toggle between active and inactive items
  void toggleStatusFilter() {
    _showInactiveOnly = !_showInactiveOnly;
    notifyListeners();
  }

  // Update request status
  Future<void> updateRequestStatus(
      String requestId, PropertyStatus newStatus) async {
    try {
      // Find the request to update
      final requestIndex = _requests.indexWhere((r) => r.id == requestId);
      if (requestIndex == -1) return;

      final request = _requests[requestIndex];
      final updatedRequest = request.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      // Update in Firestore
      await _requestService.updateRequest(requestId, updatedRequest);

      _showToast(
          'Request status updated to ${newStatus.displayName}', Colors.green);
      await refreshRequests();
    } catch (e) {
      _showToast('Unable to update the request. Please try again.', Colors.red);
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

  @override
  void dispose() {
    super.dispose();
  }
}
