import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../data/models/ScreensModel/brokers_model.dart';
import '../../services/ScreenServices/broker_service.dart';
import 'entity_list_state.dart';

class BrokersListViewModel extends ChangeNotifier
    with EntityListState<BrokerModel> {
  final BrokerService _brokerService;

  bool get isLoading => isInitialLoading;

  String? _error;
  String? get error => _error;

  List<BrokerModel> get brokers => entities;

  BrokersListViewModel({BrokerService? brokerService})
      : _brokerService = brokerService ?? BrokerService() {
    // Subscribed once: the source re-reads after every mutation by itself.
    listenToEntities(_brokerService.getUserBrokers().map((brokers) {
      return brokers.map((broker) {
        if (broker.createdAt == null) {
          return broker.copyWith(createdAt: DateTime.now());
        }
        return broker;
      }).toList();
    }));
  }

  @override
  String? entityIdOf(BrokerModel item) => item.id;

  @override
  String get debugListName => 'brokers';

  Future<void> deleteBroker(String brokerId, BuildContext context) async {
    final outcome = await deleteEntity(
        brokerId, () => _brokerService.deleteBroker(brokerId));
    if (!context.mounted) return;
    if (outcome == EntityDeleteOutcome.deleted) {
      _showToast('Broker deleted successfully', Colors.green);
    } else if (outcome == EntityDeleteOutcome.failed) {
      _showToast('Unable to delete the broker. Please try again.', Colors.red);
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
