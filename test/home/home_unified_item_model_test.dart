// What the Home filters read from a record: its own creation time — or the plain
// fact that it has none — and its price as a number. Uses the app's real models.

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/data/models/unified_item_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime created = DateTime.utc(2026, 10, 1, 8);

RequestModel request({String min = '', String max = ''}) => RequestModel(
      id: 'request-1',
      userId: 'user',
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: min,
      maxPrice: max,
      notes: '',
      specificPropertyType: 'Studio',
      rooms: 1,
      bathrooms: 1,
      createdAt: created,
      updatedAt: created,
    );

OfferModel offer({String min = '', String max = ''}) => OfferModel(
      id: 'offer-1',
      userId: 'user',
      offerType: 'sell',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: min,
      maxPrice: max,
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

OwnerModel owner() => OwnerModel(
      id: 'owner-1',
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

BrokerModel broker({DateTime? at}) => BrokerModel(
      id: 'broker-1',
      name: 'Broker',
      countryCode: '+971',
      phoneNumber: '',
      notes: '',
      createdAt: at,
      updatedAt: at,
    );

OfficeModel office({DateTime? at}) => OfficeModel(
      id: 'office-1',
      officeName: 'Office',
      managerName: 'Manager',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: at,
      updatedAt: at,
    );

WatchmenModel watchman({DateTime? at}) => WatchmenModel(
      id: 'watchman-1',
      name: 'Watchman',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: 'Tower',
      notes: '',
      buildingLocation: '',
      pickUpLocation: '',
      pickUpAddress: '',
      createdAt: at,
      updatedAt: at,
    );

void main() {
  group('prices are read as numbers', () {
    test('plain digits', () {
      final item =
          UnifiedItemModel.fromRequest(request(min: '1500000', max: '2000000'));
      expect(item.minPrice, 1500000);
      expect(item.maxPrice, 2000000);
      expect(item.averagePrice, 1750000);
    });

    test('with thousands separators, as the forms accept them', () {
      final item =
          UnifiedItemModel.fromOffer(offer(min: '1,500,000', max: '2,000,000'));
      expect(item.minPrice, 1500000);
      expect(item.maxPrice, 2000000);
    });

    test('with stray spaces', () {
      final item = UnifiedItemModel.fromOffer(offer(min: '  250 '));
      expect(item.minPrice, 250);
    });

    test('with decimals, as Supabase stores them', () {
      final item = UnifiedItemModel.fromRequest(request(max: '99999.5'));
      expect(item.maxPrice, 99999.5);
    });

    test('text that is not a finite, non-negative number is no price', () {
      for (final text in ['', '   ', 'abc', '-5', 'NaN', 'Infinity', '1,2,x']) {
        final item = UnifiedItemModel.fromOffer(offer(min: text, max: text));
        expect(item.minPrice, isNull, reason: '"$text"');
        expect(item.maxPrice, isNull, reason: '"$text"');
        expect(item.averagePrice, isNull, reason: '"$text"');
      }
    });

    test('the average is of both ends, or the one that is there', () {
      expect(
          UnifiedItemModel.fromRequest(request(min: '100', max: '300'))
              .averagePrice,
          200);
      expect(
          UnifiedItemModel.fromRequest(request(min: '150')).averagePrice, 150);
      expect(
          UnifiedItemModel.fromRequest(request(max: '250')).averagePrice, 250);
      expect(UnifiedItemModel.fromRequest(request()).averagePrice, isNull);
    });

    test('the price text shown on a card is unchanged', () {
      expect(UnifiedItemModel.fromRequest(request(min: '1', max: '2')).price,
          '1 - 2 AED');
      expect(
          UnifiedItemModel.fromRequest(request(min: '1')).price, 'From 1 AED');
      expect(
          UnifiedItemModel.fromRequest(request(max: '2')).price, 'Up to 2 AED');
      expect(UnifiedItemModel.fromRequest(request()).price, isNull);
    });
  });

  group('creation time', () {
    test('a Request, an Offer and an Owner always carry their own', () {
      for (final item in [
        UnifiedItemModel.fromRequest(request()),
        UnifiedItemModel.fromOffer(offer()),
        UnifiedItemModel.fromOwner(owner()),
      ]) {
        expect(item.hasCreatedAt, isTrue, reason: item.type.name);
        expect(item.createdAt, created, reason: item.type.name);
      }
    });

    test('a Broker, an Office and a Watchman with one carry it', () {
      for (final item in [
        UnifiedItemModel.fromBroker(broker(at: created)),
        UnifiedItemModel.fromOffice(office(at: created)),
        UnifiedItemModel.fromWatchmen(watchman(at: created)),
      ]) {
        expect(item.hasCreatedAt, isTrue, reason: item.type.name);
        expect(item.createdAt, created, reason: item.type.name);
      }
    });

    test('a Broker, an Office and a Watchman without one say so', () {
      for (final item in [
        UnifiedItemModel.fromBroker(broker()),
        UnifiedItemModel.fromOffice(office()),
        UnifiedItemModel.fromWatchmen(watchman()),
      ]) {
        expect(item.hasCreatedAt, isFalse, reason: item.type.name);
      }
    });

    test('and are never counted as recent for it, however they are drawn', () {
      // Without a time of its own the record is drawn with today's date, which
      // must not make it look newly added.
      final now = DateTime.now();
      final items = [
        UnifiedItemModel.fromBroker(broker()),
        UnifiedItemModel.fromOffice(office()),
        UnifiedItemModel.fromWatchmen(watchman()),
      ];
      for (final item in items) {
        expect(now.difference(item.createdAt).inMinutes.abs(), lessThan(5),
            reason: '${item.type.name} is drawn with today\'s date');
      }
      for (final kind in [
        HomeFilterKind.recentlyAdded,
        HomeFilterKind.thisWeek,
      ]) {
        expect(HomeFilterRules.apply(kind, items, now: now), isEmpty,
            reason: kind.name);
      }

      final known = [
        UnifiedItemModel.fromBroker(
            broker(at: now.subtract(const Duration(hours: 1)))),
      ];
      expect(
        HomeFilterRules.apply(HomeFilterKind.recentlyAdded, known, now: now),
        hasLength(1),
      );
    });
  });
}
