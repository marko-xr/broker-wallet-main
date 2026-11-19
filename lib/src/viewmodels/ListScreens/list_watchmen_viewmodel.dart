import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../common/localization/localization_delegate.dart';
import '../../data/models/ScreensModel/watchmen_model.dart';
import '../../services/ScreenServices/watchmen_service.dart';
import 'entity_list_state.dart';

class WatchmenListViewModel extends ChangeNotifier
    with EntityListState<WatchmenModel> {
  final WatchmenService _watchmenService;

  // Loading state
  bool get isLoading => isInitialLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Watchmen list
  List<WatchmenModel> get watchmen => entities;

  WatchmenListViewModel({WatchmenService? watchmenService})
      : _watchmenService = watchmenService ?? WatchmenService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    // This account's saved copy shows first, so the list is there offline.
    listenToEntities(_watchmenService.watchUserWatchmenLocalFirst());
  }

  @override
  String? entityIdOf(WatchmenModel item) => item.id;

  @override
  String get debugListName => 'watchmen';

  // Delete a watchmen
  Future<void> deleteWatchmen(String watchmenId, BuildContext context) async {
    final outcome = await deleteEntity(
        watchmenId, () => _watchmenService.deleteWatchmen(watchmenId));
    if (!context.mounted) return;
    final loc = AppLocalizations.of(context);
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast(loc.translate('watchmenDeletedSuccessfully'), Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast(loc.translate('unableToDeleteWatchman'), Colors.red);
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
