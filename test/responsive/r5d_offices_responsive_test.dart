import 'dart:async';
import 'package:broker_wallet/src/common/enums/add_offices_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offices_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offices_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_offices_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/offices_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offices_view_details.dart';
import 'package:flutter/material.dart';
import 'r5d_entity_cases.dart';

class _Offices extends OfficeService {
  _Offices(this.stream, this.onRead);
  final Stream<List<OfficeModel>> stream;
  final VoidCallback onRead;
  @override
  Stream<List<OfficeModel>> getUserOffices() {
    onRead();
    return stream;
  }
}

OfficeModel _record(int i, bool mapped) => OfficeModel(
    id: '$i',
    userId: 'layout-user',
    officeName: 'Long office name اسم المكتب الطويل $i',
    managerName: 'Long manager name اسم المدير الطويل',
    countryCode: '+971',
    phoneNumber: '+971501234567',
    officeLocation: 'Long office address Dubai Marina عنوان المكتب',
    notes: 'Long office notes تفاصيل طويلة عن المكتب وإمكانية الوصول',
    pickUpLocation: 'Long pickup location موقع المكتب',
    pickUpAddress: 'Long pickup address عنوان طويل',
    pickUpLatitude: mapped ? 25.2 : null,
    pickUpLongitude: mapped ? 55.3 : null,
    createdAt: DateTime.utc(2026, 10, 28),
    updatedAt: DateTime.utc(2026, 10, 28));

void main() => entityCases<OfficeModel, AddOfficesViewModel>(
    name: 'Office',
    keyPrefix: 'office',
    mapSupported: true,
    record: _record,
    model: (edit) => AddOfficesViewModel(
        mode: edit == null ? AddOfficesMode.add : AddOfficesMode.edit,
        officeData: edit),
    form: (vm, edit) => AddOfficesView(
        viewModel: vm, mode: edit ? AddOfficesMode.edit : AddOfficesMode.add),
    list: (stream, onRead) => OfficesListView(
        createViewModel: () =>
            OfficesListViewModel(officeService: _Offices(stream, onRead))),
    details: (record, related) => OfficesDetailsView(
        office: record,
        relatedItemsService: related,
        mapPreview: const ColoredBox(
            color: Colors.transparent,
            child:
                Center(child: Icon(Icons.map, key: Key('local-map-preview'))))),
    setPhone: (vm, value) => vm.setPhone(value),
    phoneError: (vm) => vm.phoneError);
