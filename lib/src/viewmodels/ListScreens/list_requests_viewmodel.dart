import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'entity_list_state.dart';

class RequestedListViewModel extends ChangeNotifier
    with EntityListState<RequestModel> {
  final RequestService _requestService;

  // Error state (shown when the first load fails)
  String? get error =>
      hasLoadError ? 'Unable to load requests. Please try again.' : null;

  // Requests list
  List<RequestModel> get requests => entities;

  // Filter state for request type
  String? _selectedFilter; // null = all, 'rent' = rent only, 'sell' = sell only
  String? get selectedFilter => _selectedFilter;

  // Filter state for property status - determines which items to show
  bool _showInactiveOnly =
      false; // false = show active only, true = show inactive only
  bool get showInactiveOnly => _showInactiveOnly;

  // Filtered requests based on selected filters
  List<RequestModel> get filteredRequests {
    var filteredList = requests;

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

  RequestedListViewModel({RequestService? requestService})
      : _requestService = requestService ?? RequestService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    listenToEntities(_requestService.getUserRequests());
  }

  @override
  String? entityIdOf(RequestModel item) => item.id;

  @override
  String get debugListName => 'requests';

  Future<void> deleteRequest(String requestId, BuildContext context) async {
    final outcome = await deleteEntity(
        requestId, () => _requestService.deleteRequest(requestId));
    if (!context.mounted) return;
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast('Request deleted successfully', Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast('Unable to delete the request. Please try again.', Colors.red);
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
      final requestIndex = requests.indexWhere((r) => r.id == requestId);
      if (requestIndex == -1) return;

      final request = requests[requestIndex];
      final updatedRequest = request.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
      );

      // Update in Firestore
      await _requestService.updateRequest(requestId, updatedRequest);

      // The list re-reads by itself after the update; it stays on screen
      // meanwhile.
      _showToast(
          'Request status updated to ${newStatus.displayName}', Colors.green);
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
