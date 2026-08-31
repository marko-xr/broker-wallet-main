import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../data/models/ScreensModel/brokers_model.dart';
import '../../services/ScreenServices/broker_service.dart';

class BrokersListViewModel extends ChangeNotifier {
  final BrokerService _brokerService = BrokerService();

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<BrokerModel> _brokers = [];
  List<BrokerModel> get brokers => _brokers;

  Stream<List<BrokerModel>>? _brokersStream;
  Stream<List<BrokerModel>>? get brokersStream => _brokersStream;

  BrokersListViewModel() {
    _initializeStream();
  }

  void _initializeStream() {
    _brokersStream = _brokerService.getUserBrokers().map((brokers) {
      return brokers.map((broker) {
        if (broker.createdAt == null) {
          return broker.copyWith(createdAt: DateTime.now());
        }
        return broker;
      }).toList();
    });
  }

  Future<void> refreshBrokers() async {
    _initializeStream();
    notifyListeners();
  }

  Future<void> deleteBroker(String brokerId, BuildContext context) async {
    try {
      await _brokerService.deleteBroker(brokerId);
      await refreshBrokers();

      if (context.mounted) {
        _showToast('Broker deleted successfully', Colors.green);
      }
    } catch (e) {
      if (context.mounted) {
        _showToast(
            'Unable to delete the broker. Please try again.', Colors.red);
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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
