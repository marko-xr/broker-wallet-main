import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/entity_list_state.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_brokers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offices_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each of the six entity list view models on the shared list lifecycle:
/// it reads its service once, a delete keeps the list and removes only the
/// deleted item (the old code re-created the stream here, which blanked the
/// whole screen until a fresh read returned), and a failed delete brings the
/// item back.

/// Stands in for one service's list read and delete.
class _Source<M> {
  final StreamController<List<M>> controller = StreamController<List<M>>();
  int reads = 0;
  final List<String> deletes = [];
  Future<void> Function() onDelete = () async {};

  Stream<List<M>> read() {
    reads++;
    return controller.stream;
  }

  Future<void> delete(String id) {
    deletes.add(id);
    return onDelete();
  }
}

class _Owners extends OwnerService {
  _Owners(this.source);
  final _Source<OwnerModel> source;
  @override
  Stream<List<OwnerModel>> getUserOwners() => source.read();
  @override
  Future<void> deleteOwner(String ownerId) => source.delete(ownerId);
}

class _Offers extends OfferService {
  _Offers(this.source);
  final _Source<OfferModel> source;
  @override
  Stream<List<OfferModel>> getUserOffers() => source.read();
  @override
  Future<void> deleteOffer(String offerId) => source.delete(offerId);
}

class _Requests extends RequestService {
  _Requests(this.source);
  final _Source<RequestModel> source;
  @override
  Stream<List<RequestModel>> getUserRequests() => source.read();
  @override
  Future<void> deleteRequest(String requestId) => source.delete(requestId);
}

class _Offices extends OfficeService {
  _Offices(this.source);
  final _Source<OfficeModel> source;
  @override
  Stream<List<OfficeModel>> getUserOffices() => source.read();
  @override
  Future<void> deleteOffice(String officeId) => source.delete(officeId);
}

class _Brokers extends BrokerService {
  _Brokers(this.source);
  final _Source<BrokerModel> source;
  @override
  Stream<List<BrokerModel>> getUserBrokers() => source.read();
  @override
  Future<void> deleteBroker(String brokerId) => source.delete(brokerId);
}

class _Watchmen extends WatchmenService {
  _Watchmen(this.source);
  final _Source<WatchmenModel> source;
  @override
  Stream<List<WatchmenModel>> getUserWatchmen() => source.read();
  @override
  Future<void> deleteWatchmen(String watchmenId) => source.delete(watchmenId);
}

final _created = DateTime(2026, 9, 1);

OwnerModel _owner(String id) => OwnerModel(
      id: id,
      userId: 'u',
      name: 'Owner $id',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: '',
      propertyLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrl: null,
      mediaUrls: const [],
      createdAt: _created,
      updatedAt: _created,
    );

OfferModel _offer(String id) => OfferModel(
      id: id,
      userId: 'u',
      offerType: 'rent',
      selectedCity: '',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: '',
      rooms: 0,
      bathrooms: 0,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: _created,
      updatedAt: _created,
      mediaUrls: const [],
    );

RequestModel _request(String id) => RequestModel(
      id: id,
      userId: 'u',
      requestType: 'rent',
      selectedCity: '',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: '',
      rooms: 0,
      bathrooms: 0,
      createdAt: _created,
      updatedAt: _created,
    );

OfficeModel _office(String id) => OfficeModel(
      id: id,
      officeName: 'Office $id',
      managerName: '',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: _created,
    );

BrokerModel _broker(String id) => BrokerModel(
      id: id,
      name: 'Broker $id',
      countryCode: '+971',
      phoneNumber: '',
      notes: '',
      createdAt: _created,
    );

WatchmenModel _watchman(String id) => WatchmenModel(
      id: id,
      name: 'Watchman $id',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: '',
      notes: '',
      buildingLocation: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: _created,
    );

final _toasts = <String>[];

/// A mounted element to hand the view models as their BuildContext.
Future<BuildContext> _mountedContext(WidgetTester tester) async {
  const host = ValueKey('context-host');
  await tester.pumpWidget(const SizedBox(key: host));
  return tester.element(find.byKey(host));
}

void _describe<M, VM extends EntityListState<M>>({
  required String name,
  required M Function(String id) model,
  required VM Function(_Source<M> source) create,
  required Future<void> Function(VM vm, String id, BuildContext context) delete,
  required String deletedToast,
  required String failedToast,
}) {
  group(name, () {
    late _Source<M> source;
    late VM vm;

    List<String?> ids() =>
        [for (final item in vm.entities) vm.entityIdOf(item)];

    Future<void> showList(WidgetTester tester, List<String> list) async {
      source = _Source<M>();
      vm = create(source);
      addTearDown(vm.dispose);
      source.controller.add([for (final id in list) model(id)]);
      await tester.pump();
    }

    testWidgets('reads its service once and shows the list', (tester) async {
      await showList(tester, ['1', '2']);

      expect(source.reads, 1);
      expect(vm.isInitialLoading, isFalse);
      expect(ids(), ['1', '2']);
    });

    testWidgets('a delete keeps the list and removes only that item',
        (tester) async {
      final context = await _mountedContext(tester);
      await showList(tester, ['1', '2']);
      _toasts.clear();

      final remote = Completer<void>();
      source.onDelete = () => remote.future;
      final pending = delete(vm, '1', context);
      await tester.pump();

      // In flight: the whole list is still there, only item 1 is marked.
      expect(vm.isInitialLoading, isFalse);
      expect(ids(), ['1', '2']);
      expect(vm.isDeleting('1'), isTrue);
      expect(vm.isDeleting('2'), isFalse);

      // A second request for the same item runs nothing.
      await delete(vm, '1', context);
      expect(source.deletes, ['1']);

      remote.complete();
      await pending;
      await tester.pump();

      expect(ids(), ['2']);
      expect(vm.isDeleting('1'), isFalse);
      expect(source.reads, 1, reason: 'the list is never re-subscribed');
      expect(_toasts, [deletedToast]);
    });

    testWidgets('a failed delete brings the item back', (tester) async {
      final context = await _mountedContext(tester);
      await showList(tester, ['1', '2']);
      _toasts.clear();

      source.onDelete = () async => throw Exception('offline');
      await delete(vm, '1', context);
      await tester.pump();

      expect(ids(), ['1', '2']);
      expect(vm.isDeleting('1'), isFalse);
      expect(_toasts, [failedToast]);
    });

    testWidgets('deleting the last item leaves a genuinely empty list',
        (tester) async {
      final context = await _mountedContext(tester);
      await showList(tester, ['1']);

      await delete(vm, '1', context);
      await tester.pump();

      expect(vm.entities, isEmpty);
      expect(vm.isInitialLoading, isFalse);
      expect(vm.hasLoadError, isFalse);
    });
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') {
          _toasts.add((call.arguments as Map)['msg'] as String);
        }
        return true;
      },
    );
  });

  _describe<RequestModel, RequestedListViewModel>(
    name: 'Requests',
    model: _request,
    create: (source) =>
        RequestedListViewModel(requestService: _Requests(source)),
    delete: (vm, id, context) => vm.deleteRequest(id, context),
    deletedToast: 'Request deleted successfully',
    failedToast: 'Unable to delete the request. Please try again.',
  );

  _describe<OfferModel, OffersListViewModel>(
    name: 'Offers',
    model: _offer,
    create: (source) => OffersListViewModel(offerService: _Offers(source)),
    delete: (vm, id, context) => vm.deleteOffer(id, context),
    deletedToast: 'Offer deleted successfully',
    failedToast: 'Unable to delete the offer. Please try again.',
  );

  _describe<OwnerModel, OwnersListViewModel>(
    name: 'Owners',
    model: _owner,
    create: (source) => OwnersListViewModel(ownerService: _Owners(source)),
    delete: (vm, id, context) => vm.deleteOwner(id, context),
    deletedToast: 'Owner deleted successfully',
    failedToast: 'Unable to delete the owner. Please try again.',
  );

  _describe<OfficeModel, OfficesListViewModel>(
    name: 'Offices',
    model: _office,
    create: (source) => OfficesListViewModel(officeService: _Offices(source)),
    delete: (vm, id, context) => vm.deleteOffice(id, context),
    deletedToast: 'Office deleted successfully',
    failedToast: 'Unable to delete the office. Please try again.',
  );

  _describe<BrokerModel, BrokersListViewModel>(
    name: 'Brokers',
    model: _broker,
    create: (source) => BrokersListViewModel(brokerService: _Brokers(source)),
    delete: (vm, id, context) => vm.deleteBroker(id, context),
    deletedToast: 'Broker deleted successfully',
    failedToast: 'Unable to delete the broker. Please try again.',
  );

  _describe<WatchmenModel, WatchmenListViewModel>(
    name: 'Watchmen',
    model: _watchman,
    create: (source) =>
        WatchmenListViewModel(watchmenService: _Watchmen(source)),
    delete: (vm, id, context) => vm.deleteWatchmen(id, context),
    deletedToast: 'Watchmen deleted successfully',
    failedToast: 'Unable to delete the watchman. Please try again.',
  );
}
