// The snapshot source behind the Home filters: one read per kind of record, all
// started at once, and an answer only when every one of them has arrived. Fake
// streams stand in for the services; the records are the app's real models.

import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/data/models/unified_item_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_data_source.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime created = DateTime.utc(2026, 10, 1, 8);

RequestModel request(String id) => RequestModel(
      id: id,
      userId: 'user',
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '100',
      maxPrice: '200',
      notes: '',
      specificPropertyType: 'Studio',
      rooms: 1,
      bathrooms: 1,
      createdAt: created,
      updatedAt: created,
    );

OfferModel offer(String id) => OfferModel(
      id: id,
      userId: 'user',
      offerType: 'sell',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '300',
      maxPrice: '400',
      notes: '',
      specificPropertyType: 'Villa',
      rooms: 3,
      bathrooms: 2,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: created,
      updatedAt: created,
      mediaUrls: const [],
    );

OwnerModel owner(String id) => OwnerModel(
      id: id,
      userId: 'user',
      name: 'Owner',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: '',
      propertyLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      mediaUrls: const [],
      createdAt: created,
      updatedAt: created,
    );

BrokerModel broker(String id) => BrokerModel(
      id: id,
      name: 'Broker',
      countryCode: '+971',
      phoneNumber: '',
      notes: '',
      createdAt: created,
      updatedAt: created,
    );

OfficeModel office(String id) => OfficeModel(
      id: id,
      officeName: 'Office',
      managerName: 'Manager',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: created,
      updatedAt: created,
    );

WatchmenModel watchman(String id) => WatchmenModel(
      id: id,
      name: 'Watchman',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: 'Tower',
      notes: '',
      buildingLocation: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: created,
      updatedAt: created,
    );

/// One record stream, as a service would hand it out: it can be listened to
/// once, and it says whether anyone is.
class Feed<T> {
  Feed() {
    controller = StreamController<List<T>>(onListen: () => listens++);
  }

  late final StreamController<List<T>> controller;
  int listens = 0;

  Stream<List<T>> call() => controller.stream;
  bool get isListening => controller.hasListener;
  void answer(List<T> rows) => controller.add(rows);
  void fail(Object error) => controller.addError(error);
}

class Feeds {
  final requests = Feed<RequestModel>();
  final offers = Feed<OfferModel>();
  final brokers = Feed<BrokerModel>();
  final owners = Feed<OwnerModel>();
  final offices = Feed<OfficeModel>();
  final watchmen = Feed<WatchmenModel>();

  List<int> get listens => [
        requests.listens,
        offers.listens,
        brokers.listens,
        owners.listens,
        offices.listens,
        watchmen.listens,
      ];

  SnapshotHomeFilterDataSource get source => SnapshotHomeFilterDataSource(
        requests: requests.call,
        offers: offers.call,
        brokers: brokers.call,
        owners: owners.call,
        offices: offices.call,
        watchmen: watchmen.call,
      );

  void answerAll() {
    requests.answer([request('r1')]);
    offers.answer([offer('o1'), offer('o2')]);
    brokers.answer([broker('b1')]);
    owners.answer([owner('w1')]);
    offices.answer([office('f1')]);
    watchmen.answer([watchman('m1')]);
  }
}

List<String> ids(List<UnifiedItemModel> items) =>
    [for (final item in items) item.id];

void main() {
  test('constructing it reads nothing', () {
    final feeds = Feeds();
    final source = feeds.source;
    expect(source, isNotNull);
    expect(feeds.listens, [0, 0, 0, 0, 0, 0]);
  });

  test('reads every kind at once, and answers only when the last one arrives',
      () async {
    final feeds = Feeds();
    var answered = false;
    final future = feeds.source.load(HomeFilterRules.filterable).then((rows) {
      answered = true;
      return rows;
    });
    await pumpEventQueue();
    expect(feeds.listens, [1, 1, 1, 1, 1, 1],
        reason: 'all six reads start before any answer is in');

    feeds.requests.answer([request('r1')]);
    feeds.offers.answer([offer('o1')]);
    feeds.brokers.answer([broker('b1')]);
    feeds.owners.answer([owner('w1')]);
    feeds.offices.answer([office('f1')]);
    await pumpEventQueue();
    expect(answered, isFalse, reason: 'five of six is not an answer');

    feeds.watchmen.answer([watchman('m1')]);
    final rows = await future;
    expect(answered, isTrue);
    expect(ids(rows), ['r1', 'o1', 'b1', 'w1', 'f1', 'm1']);
  });

  test('the records come back as the unified kinds, in the fixed order',
      () async {
    final feeds = Feeds();
    final future = feeds.source.load(HomeFilterRules.filterable);
    await pumpEventQueue();
    feeds.answerAll();
    final rows = await future;
    expect([
      for (final row in rows) row.type
    ], [
      ItemType.request,
      ItemType.offer,
      ItemType.offer,
      ItemType.broker,
      ItemType.owner,
      ItemType.office,
      ItemType.watchmen,
    ]);
    // The unified record keeps the model it was made from.
    expect(rows.first.originalModel, isA<RequestModel>());
  });

  test('reads only the kinds it is asked for', () async {
    final feeds = Feeds();
    final future =
        feeds.source.load(HomeFilterRules.typesFor(HomeFilterKind.lessPrice));
    await pumpEventQueue();
    expect(feeds.listens, [1, 1, 0, 0, 0, 0],
        reason: 'Less Price reads Requests and Offers, nothing else');

    feeds.requests.answer([request('r1')]);
    feeds.offers.answer([offer('o1')]);
    expect(ids(await future), ['r1', 'o1']);
    expect(feeds.listens, [1, 1, 0, 0, 0, 0]);
  });

  test('never reads quotations: asked for alone, it reads nothing', () async {
    final feeds = Feeds();
    expect(await feeds.source.load([ItemType.quotation]), isEmpty);
    expect(feeds.listens, [0, 0, 0, 0, 0, 0]);

    // Mixed in with real kinds, only the real ones are read.
    final future = feeds.source.load([ItemType.quotation, ItemType.owner]);
    await pumpEventQueue();
    expect(feeds.listens, [0, 0, 0, 1, 0, 0]);
    feeds.owners.answer([owner('w1')]);
    expect(ids(await future), ['w1']);
  });

  test('one read that fails fails the whole load, and no part is used',
      () async {
    final feeds = Feeds();
    final outcome = feeds.source
        .load(HomeFilterRules.filterable)
        .then<Object?>((_) => null, onError: (Object error) => error);
    await pumpEventQueue();

    feeds.requests.answer([request('r1')]);
    feeds.offers.answer([offer('o1')]);
    feeds.owners.fail(StateError('owners could not be read'));
    final error = await outcome;
    expect(error, isA<StateError>());
  });

  test(
      'a stream that cannot even be opened fails the load, it does not throw '
      'out of load()', () async {
    final feeds = Feeds();
    final source = SnapshotHomeFilterDataSource(
      requests: () => throw StateError('A Supabase session is required.'),
      offers: feeds.offers.call,
      brokers: feeds.brokers.call,
      owners: feeds.owners.call,
      offices: feeds.offices.call,
      watchmen: feeds.watchmen.call,
    );
    final outcome = source
        .load(HomeFilterRules.filterable)
        .then<Object?>((_) => null, onError: (Object error) => error);
    expect(await outcome, isA<StateError>());
  });

  test('takes one snapshot and lets go: nothing stays subscribed', () async {
    final feeds = Feeds();
    final future = feeds.source.load(HomeFilterRules.filterable);
    await pumpEventQueue();
    expect(feeds.requests.isListening, isTrue);
    feeds.answerAll();
    await future;
    await pumpEventQueue();
    expect(feeds.requests.isListening, isFalse);
    expect(feeds.offers.isListening, isFalse);
    expect(feeds.brokers.isListening, isFalse);
    expect(feeds.owners.isListening, isFalse);
    expect(feeds.offices.isListening, isFalse);
    expect(feeds.watchmen.isListening, isFalse);
    expect(feeds.listens, [1, 1, 1, 1, 1, 1], reason: 'each read once');
  });

  test('an empty snapshot is an answer', () async {
    final feeds = Feeds();
    final future = feeds.source.load(HomeFilterRules.filterable);
    await pumpEventQueue();
    feeds.requests.answer([]);
    feeds.offers.answer([]);
    feeds.brokers.answer([]);
    feeds.owners.answer([]);
    feeds.offices.answer([]);
    feeds.watchmen.answer([]);
    expect(await future, isEmpty);
  });
}
