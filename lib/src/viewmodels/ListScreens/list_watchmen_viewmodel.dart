import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../data/models/ScreensModel/watchmen_model.dart';
import '../../services/ScreenServices/watchmen_service.dart';

class WatchmenListViewModel extends ChangeNotifier {
  final WatchmenService _watchmenService = WatchmenService();

  // Loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Watchmen list
  List<WatchmenModel> _watchmen = [];
  List<WatchmenModel> get watchmen => _watchmen;

  // Stream subscription
  Stream<List<WatchmenModel>>? _watchmenStream;
  Stream<List<WatchmenModel>>? get watchmenStream => _watchmenStream;

  WatchmenListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _watchmenStream = _watchmenService.getUserWatchmen();
  }

  // Refresh watchmen
  Future<void> refreshWatchmen() async {
    // The stream will automatically update when data changes
    _initializeStream();
    notifyListeners();
  }

  // Delete a watchmen
  Future<void> deleteWatchmen(String watchmenId, BuildContext context) async {
    try {
      await _watchmenService.deleteWatchmen(watchmenId);

      if (context.mounted) {
        _showToast('Watchmen deleted successfully', Colors.green);
        await refreshWatchmen();
      }
    } catch (e) {
      if (context.mounted) {
        _showToast(
            'Unable to delete the watchman. Please try again.', Colors.red);
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
