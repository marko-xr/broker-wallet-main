import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/core_entity_payload_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '00000000-0000-4000-8000-000000000001';
  const ownerId = '00000000-0000-4000-8000-000000000002';

  OfferModel offer({
    String phone = '',
    String minPrice = '',
    String maxPrice = '',
    String squareFootage = '',
    double? latitude,
    double? longitude,
  }) =>
      OfferModel(
        userId: '',
        offerType: 'rent',
        selectedCity: 'Dubai',
        selectedAreas: const [],
        location: '',
        phoneNumber: phone,
        countryCode: '+971',
        minPrice: minPrice,
        maxPrice: maxPrice,
        squareFootage: squareFootage,
        notes: '',
        propertyType: null,
        specificPropertyType: '',
        rooms: 0,
        bathrooms: 0,
        pickUpLocation: '',
        pickUpLatitude: latitude,
        pickUpLongitude: longitude,
        pickUpAddress: '',
        uploadedFileName: '',
        mediaUrls: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('offer without phone sends null E.164 and null blank numerics', () {
    final payload = CoreEntityPayloadBuilder.offer(
      offer(),
      id: id,
      ownerId: ownerId,
    );
    expect(payload['phone_e164'], isNull);
    expect(payload['min_price'], isNull);
    expect(payload['max_price'], isNull);
    expect(payload['square_footage'], isNull);
    expect(payload['status'], 'available');
    expect(payload['pickup_latitude'], isNull);
    expect(payload['pickup_longitude'], isNull);
  });

  test('offer UAE phone is canonical', () {
    final payload = CoreEntityPayloadBuilder.offer(
      offer(phone: '055 288 5222'),
      id: id,
      ownerId: ownerId,
    );
    expect(payload['phone_e164'], '+971552885222');
  });

  test('paired coordinates are preserved', () {
    final payload = CoreEntityPayloadBuilder.offer(
      offer(latitude: 25.2048, longitude: 55.2708),
      id: id,
      ownerId: ownerId,
    );
    expect(payload['pickup_latitude'], 25.2048);
    expect(payload['pickup_longitude'], 55.2708);
  });

  test('a partial coordinate pair is rejected before PostgREST', () {
    expect(
      () => CoreEntityPayloadBuilder.offer(
        offer(latitude: 25.2048),
        id: id,
        ownerId: ownerId,
      ),
      throwsA(isA<CoreEntityValidationException>()),
    );
  });

  test('broker without phone sends null E.164', () {
    final payload = CoreEntityPayloadBuilder.broker(
      BrokerModel(
        name: 'Broker',
        countryCode: '+971',
        phoneNumber: '',
        notes: '',
      ),
      id: id,
      ownerId: ownerId,
    );
    expect(payload['phone_e164'], isNull);
  });

  test('watchman without phone sends null E.164', () {
    final payload = CoreEntityPayloadBuilder.watchman(
      WatchmenModel(
        name: 'Watchman',
        countryCode: '+971',
        phoneNumber: '',
        buildingName: '',
        notes: '',
        buildingLocation: '',
        pickUpLocation: '',
        pickUpAddress: '',
      ),
      id: id,
      ownerId: ownerId,
    );
    expect(payload['phone_e164'], isNull);
  });

  test('duplicate and blank areas are removed', () {
    expect(
      CoreEntityPayloadBuilder.areas([' Marina ', '', 'Marina', 'Downtown']),
      ['Marina', 'Downtown'],
    );
  });
}
