import 'dart:async';
import 'package:broker_wallet/src/common/enums/add_brokers_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_brokers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_brokers_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_brokers_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/brokers_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/brokers_view_details.dart';
import 'package:flutter/material.dart';
import 'r5d_entity_cases.dart';

class _Brokers extends BrokerService {
  _Brokers(this.stream, this.onRead);
  final Stream<List<BrokerModel>> stream;
  final VoidCallback onRead;
  @override
  Stream<List<BrokerModel>> getUserBrokers() {
    onRead();
    return stream;
  }
}

BrokerModel _record(int i, bool mapped) => BrokerModel(
    id: '$i',
    userId: 'layout-user',
    name: 'Long broker name اسم الوسيط الطويل $i',
    countryCode: '+971',
    phoneNumber: '+971501234567',
    notes: 'Long broker notes تفاصيل طويلة عن الوسيط وإمكانية التواصل',
    createdAt: DateTime.utc(2026, 10, 28),
    updatedAt: DateTime.utc(2026, 10, 28));

void main() => entityCases<BrokerModel, AddBrokersViewModel>(
    name: 'Broker',
    keyPrefix: 'broker',
    record: _record,
    model: (edit) => AddBrokersViewModel(
        mode: edit == null ? AddBrokersMode.add : AddBrokersMode.edit,
        brokerData: edit),
    form: (vm, edit) => AddBrokersView(
        viewModel: vm, mode: edit ? AddBrokersMode.edit : AddBrokersMode.add),
    list: (stream, onRead) => BrokersListView(
        createViewModel: () =>
            BrokersListViewModel(brokerService: _Brokers(stream, onRead))),
    details: (record, related) =>
        BrokersDetailsView(broker: record, relatedItemsService: related),
    setPhone: (vm, value) => vm.setPhone(value),
    phoneError: (vm) => vm.phoneError);
