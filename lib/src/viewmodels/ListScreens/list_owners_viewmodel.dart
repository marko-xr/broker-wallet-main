import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../../services/ScreenServices/owner_service.dart';
import 'entity_list_state.dart';

class OwnersListViewModel extends ChangeNotifier
    with EntityListState<OwnerModel> {
  final OwnerService _ownerService;

  // Loading state
  bool get isLoading => isInitialLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Owners list
  List<OwnerModel> get owners => entities;

  OwnersListViewModel({OwnerService? ownerService})
      : _ownerService = ownerService ?? OwnerService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    listenToEntities(_ownerService.getUserOwners());
  }

  @override
  String? entityIdOf(OwnerModel item) => item.id;

  @override
  String get debugListName => 'owners';

  // Delete an owner
  Future<void> deleteOwner(String ownerId, BuildContext context) async {
    final outcome =
        await deleteEntity(ownerId, () => _ownerService.deleteOwner(ownerId));
    if (!context.mounted) return;
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast('Owner deleted successfully', Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast('Unable to delete the owner. Please try again.', Colors.red);
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
