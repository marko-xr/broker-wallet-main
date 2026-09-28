import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/offices_model.dart';
import '../../services/ScreenServices/office_service.dart';
import 'entity_list_state.dart';

class OfficesListViewModel extends ChangeNotifier
    with EntityListState<OfficeModel> {
  final OfficeService _officeService;

  // Loading state
  bool get isLoading => isInitialLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Offices list
  List<OfficeModel> get offices => entities;

  OfficesListViewModel({OfficeService? officeService})
      : _officeService = officeService ?? OfficeService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    listenToEntities(_officeService.getUserOffices());
  }

  @override
  String? entityIdOf(OfficeModel item) => item.id;

  @override
  String get debugListName => 'offices';

  // Delete an office
  Future<void> deleteOffice(String officeId, BuildContext context) async {
    final outcome = await deleteEntity(
        officeId, () => _officeService.deleteOffice(officeId));
    if (!context.mounted) return;
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast('Office deleted successfully', Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast('Unable to delete the office. Please try again.', Colors.red);
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
