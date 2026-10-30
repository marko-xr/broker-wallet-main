import 'dart:async';

import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:flutter/material.dart';

class LocalQuotationService implements QuotationService {
  LocalQuotationService() {
    events = StreamController<List<QuotationModel>>.broadcast(
        onListen: () => subscriptions++);
  }
  late final StreamController<List<QuotationModel>> events;
  int streamReads = 0;
  int subscriptions = 0;
  int unexpectedCalls = 0;
  @override
  Stream<List<QuotationModel>> getUserQuotations() {
    streamReads++;
    return events.stream.map((rows) => rows);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError(
        'Unexpected quotation service call: ${invocation.memberName}');
  }
}

class _LocalAuth implements AuthRepository {
  @override
  String get currentUserId => 'layout-only';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth call: ${invocation.memberName}');
}

/// Production calculations and row mutations, with every external boundary
/// replaced. Save is only a callback counter; no PDF, file or server is used.
class LayoutQuotationForm extends AddQuotationViewModel {
  LayoutQuotationForm(this.local, {bool edit = false})
      : super(
          quotationService: local,
          authRepository: _LocalAuth(),
          editQuotationId: edit ? 'layout-edit' : null,
          pdfGenerator: (_, {locale}) async =>
              throw StateError('No PDF generation'),
          logoPicker: () async => throw StateError('No file picker'),
          creationGate: (_) async => throw StateError('No creation gate'),
          toast: (_, __) => throw StateError('No platform toast'),
        );
  final LocalQuotationService local;
  int saves = 0;
  int loads = 0;
  int adminAdds = 0;
  int smartOpens = 0;
  bool busy = false;
  bool processing = false;
  bool loadingEdit = false;
  bool failedEdit = false;
  @override
  bool get isLoading => busy;
  @override
  bool get isProcessingLogoBackground => processing;
  @override
  bool get isLoadingExisting => loadingEdit;
  @override
  bool get loadFailed => failedEdit;
  @override
  Future<void> save(BuildContext context) async {
    saves++;
  }

  @override
  Future<void> loadForEdit() async {
    loads++;
  }

  @override
  void addAdministrativeFeeRow() {
    adminAdds++;
    super.addAdministrativeFeeRow();
  }

  @override
  void triggerInitialSmartCalculation() {
    smartOpens++;
    super.triggerInitialSmartCalculation();
  }
}

QuotationListViewModel localQuotationList(LocalQuotationService service) =>
    QuotationListViewModel(
        quotationService: service,
        toast: (_, __) => throw StateError('No platform toast'));

const longQuotationTitle =
    'برج المرسى شقة واسعة جداً Long quotation property title for responsive layout';

List<QuotationModel> quotationFixtures() => List.generate(
    5,
    (i) => QuotationModel(
          id: 'local-$i',
          userId: 'layout-only',
          propertyTitle: '$longQuotationTitle $i',
          officeName: 'مكتب عقارات طويل الاسم Long real estate office name',
          propertyType: 'شقة فاخرة Luxury apartment with a long description',
          date: '2026-10-30',
          totalAmount: 9876543210.25,
          numberOfInstallments: 120,
          pdfMediaId: i.isEven ? 'fixture-present-$i' : null,
          createdAt: DateTime(2026, 10, 30),
          updatedAt: DateTime(2026, 10, 30),
        ));

void fillQuotationForm(LayoutQuotationForm vm) {
  vm.propertyTitle = longQuotationTitle;
  vm.propertyType = 'شقة واسعة Apartment';
  vm.officeName = 'مكتب عقارات طويل الاسم Long real estate office';
  vm.date = '2026-10-30';
  vm.startDate = '2026-11-01';
  vm.endDate = '2027-10-31';
  vm.totalAmount = '9876543210.25';
  vm.numberOfInstallments = '12';
  vm.govMunicipality = '987654.25';
  vm.govElectricity = '123456.50';
  vm.officeLogoFileName = 'اسم شعار مكتب طويل جداً long-office-logo-name.png';
  vm.customWelcomeMessage = List.filled(8, longQuotationTitle).join(' ');
  vm.administrativeFees.addAll(List.generate(
      3,
      (i) => AdministrativeFeeRowVM(
          title: 'رسوم إدارية طويلة Long administration fee $i',
          amount: '1234567.25')));
  vm.downpayments.addAll(List.generate(
      4,
      (i) => DownpaymentRowVM(
          method: 'bankTransfer',
          number: '${i + 1}',
          date: '2026-11-01',
          amount: '98765432.25')));
}
