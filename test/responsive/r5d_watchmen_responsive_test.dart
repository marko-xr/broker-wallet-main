import 'dart:async';
import 'package:broker_wallet/src/common/enums/add_watchmen_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_watchmen_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_watchmen_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/watchmen_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/watchmen_view_details.dart';
import 'package:flutter/material.dart';
import 'r5d_entity_cases.dart';

class _Watchmen extends WatchmenService {
  _Watchmen(this.stream, this.onRead);
  final Stream<List<WatchmenModel>> stream;
  final VoidCallback onRead;
  @override
  Stream<List<WatchmenModel>> getUserWatchmen() {
    onRead();
    return stream;
  }
}

WatchmenModel _record(int i, bool mapped) => WatchmenModel(
    id: '$i',
    userId: 'layout-user',
    name: 'Long watchman name اسم الحارس الطويل $i',
    buildingName: 'Long building name اسم المبنى الطويل',
    countryCode: '+971',
    phoneNumber: '+971501234567',
    buildingLocation: 'Long building address Dubai Marina عنوان المبنى',
    notes: 'Long watchman notes تفاصيل طويلة عن الحارس وإمكانية التواصل',
    pickUpLocation: 'Long pickup location موقع المبنى',
    pickUpAddress: 'Long pickup address عنوان طويل',
    pickUpLatitude: mapped ? 25.2 : null,
    pickUpLongitude: mapped ? 55.3 : null,
    createdAt: DateTime.utc(2026, 10, 28),
    updatedAt: DateTime.utc(2026, 10, 28));

void main() => entityCases<WatchmenModel, AddWatchmenViewModel>(
    name: 'Watchmen',
    keyPrefix: 'watchmen',
    mapSupported: true,
    record: _record,
    model: (edit) => AddWatchmenViewModel(
        mode: edit == null ? AddWatchmenMode.add : AddWatchmenMode.edit,
        watchmenData: edit),
    form: (vm, edit) => AddWatchmenView(
        viewModel: vm, mode: edit ? AddWatchmenMode.edit : AddWatchmenMode.add),
    list: (stream, onRead) => WatchmenListView(
        createViewModel: () =>
            WatchmenListViewModel(watchmenService: _Watchmen(stream, onRead))),
    details: (record, related) => WatchmenDetailsView(
        watchmen: record,
        relatedItemsService: related,
        mapPreview: const ColoredBox(
            color: Colors.transparent,
            child:
                Center(child: Icon(Icons.map, key: Key('local-map-preview'))))),
    setPhone: (vm, value) => vm.setPhone(value),
    phoneError: (vm) => vm.phoneError);
