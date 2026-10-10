// What the map shows. The places come from the user's own records, whatever
// backend holds them, through one mapper: which records are places, what each
// place says, and that nothing English is baked in. Plain Dart.

import 'dart:async';

import 'package:broker_wallet/src/common/utils/coalesced_runner.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 7);

OfferModel _offer({
  String? id = 'o1',
  double? lat = 25.2,
  double? lng = 55.27,
  String specific = 'Villa',
  String offerType = 'rent',
  String city = 'Dubai',
  String address = '',
  String location = '',
  String phone = '+971501234567',
  String? mediaUrl,
  List<String> mediaUrls = const <String>[],
}) =>
    OfferModel(
      id: id,
      userId: 'u1',
      offerType: offerType,
      selectedCity: city,
      selectedAreas: const <String>[],
      location: '',
      phoneNumber: phone,
      countryCode: '+971',
      minPrice: '100',
      maxPrice: '200',
      notes: '',
      specificPropertyType: specific,
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: location,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
      uploadedFileName: '',
      mediaUrl: mediaUrl,
      mediaUrls: mediaUrls,
      createdAt: _now,
      updatedAt: _now,
    );

OwnerModel _owner({
  String? id = 'w1',
  double? lat = 25.1,
  double? lng = 55.2,
  String name = 'Sara',
  String address = '',
  String location = '',
  String type = 'Villa',
  String propertyLocation = 'Dubai',
}) =>
    OwnerModel(
      id: id,
      userId: 'u1',
      name: name,
      phoneNumber: '0501112222',
      countryCode: '+971',
      typeOfProperties: type,
      propertyLocation: propertyLocation,
      notes: '',
      pickUpLocation: location,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OfficeModel _office({
  String? id = 'f1',
  double? lat = 25.3,
  double? lng = 55.3,
  String name = 'Palm Office',
  String officeLocation = 'Dubai',
}) =>
    OfficeModel(
      id: id,
      officeName: name,
      managerName: 'Ali',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: officeLocation,
      notes: '',
      pickUpLocation: 'Office tower',
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

WatchmenModel _watchman({
  String? id = 'm1',
  double? lat = 25.4,
  double? lng = 55.4,
  String location = '',
  String building = 'Tower A',
  String buildingLocation = 'Marina',
}) =>
    WatchmenModel(
      id: id,
      name: 'Omar',
      countryCode: '+971',
      phoneNumber: '0509998888',
      buildingName: building,
      notes: '',
      buildingLocation: buildingLocation,
      pickUpLocation: location,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: '',
    );

void main() {
  group('which records are places', () {
    test('a record with an id and a usable position is a place', () {
      final places = MapLocationMapper.offers([_offer()]);
      expect(places, hasLength(1));
      expect(places.single.id, 'o1');
      expect(places.single.type, LocationFilter.offers);
      expect(places.single.latitude, 25.2);
      expect(places.single.longitude, 55.27);
    });

    test('no position, a half position or an impossible one: not a place', () {
      expect(MapLocationMapper.offers([_offer(lat: null)]), isEmpty);
      expect(MapLocationMapper.offers([_offer(lng: null)]), isEmpty);
      expect(MapLocationMapper.offers([_offer(lat: 91)]), isEmpty);
      expect(MapLocationMapper.offers([_offer(lng: -181)]), isEmpty);
      expect(MapLocationMapper.offers([_offer(lat: double.nan)]), isEmpty);
      expect(MapLocationMapper.offers([_offer(lng: double.infinity)]), isEmpty);
    });

    test(
        'the (0, 0) of an unset pin is not a place; a real zero is a coordinate',
        () {
      expect(MapLocationMapper.offers([_offer(lat: 0, lng: 0)]), isEmpty);
      // The detail screens' rule: only both zero means "unset". A zero with a
      // real other half is a usable coordinate. Whether the map can show it is
      // the separate question of the UAE (test/map/map_uae_sanity_test.dart),
      // which a pin at latitude 0 does not pass.
      expect(MapLocationMapper.isUsableCoordinate(0, 0), isFalse);
      expect(MapLocationMapper.isUsableCoordinate(0, 55), isTrue);
      expect(MapLocationMapper.isUsableCoordinate(25, 0), isTrue);
    });

    test(
      'a record without an id is skipped: its details could not be opened',
      () {
        expect(MapLocationMapper.offers([_offer(id: null)]), isEmpty);
        expect(MapLocationMapper.owners([_owner(id: '   ')]), isEmpty);
        expect(MapLocationMapper.offices([_office(id: '')]), isEmpty);
        expect(MapLocationMapper.watchmen([_watchman(id: null)]), isEmpty);
      },
    );

    test('every kind is read, in the order of the map\'s chips', () {
      final places = MapLocationMapper.all(
        offers: [_offer()],
        owners: [_owner()],
        offices: [_office()],
        watchmen: [_watchman()],
      );
      expect(
        [for (final p in places) p.type],
        [
          LocationFilter.offers,
          LocationFilter.owners,
          LocationFilter.offices,
          LocationFilter.watchmen,
        ],
      );
      expect([for (final p in places) p.id], ['o1', 'w1', 'f1', 'm1']);
    });
  });

  group('what a place says', () {
    test('an empty stored address does not hide the next one', () {
      // Supabase stores "" (not null) for a missing field: the first answer
      // that says something wins.
      final place = MapLocationMapper.offers([
        _offer(address: '', location: 'Marina Walk'),
      ]).single;
      expect(place.address, 'Marina Walk');
      expect(
        MapLocationMapper.offers([
          _offer(address: ' Sheikh Zayed Rd ', location: 'Marina Walk'),
        ]).single.address,
        'Sheikh Zayed Rd',
      );
    });

    test('a watchman falls back to the building\'s location', () {
      final place = MapLocationMapper.watchmen([
        _watchman(location: '', buildingLocation: 'Marina'),
      ]).single;
      expect(place.address, 'Marina');
      expect(
        MapLocationMapper.watchmen([
          _watchman(location: 'Gate 2', buildingLocation: 'Marina'),
        ]).single.address,
        'Gate 2',
      );
    });

    test('nothing to say is empty, never an English placeholder', () {
      final offer = MapLocationMapper.offers([_offer(specific: '')]).single;
      final owner = MapLocationMapper.owners([_owner(name: '')]).single;
      final office = MapLocationMapper.offices([_office(name: '  ')]).single;
      for (final place in [offer, owner, office]) {
        expect(place.title, isEmpty);
        for (final english in [
          'Property Offer',
          'Property Owner',
          'Real Estate Office',
          'Building Watchman',
          'No address',
        ]) {
          expect(place.title.contains(english), isFalse);
          expect(place.address.contains(english), isFalse);
        }
      }
      expect(
        MapLocationMapper.owners([_owner()]).single.address,
        isEmpty,
        reason: 'an owner with no address says none',
      );
    });

    test('titles are what the record calls itself', () {
      expect(
        MapLocationMapper.offers([_offer(specific: ' Villa ')]).single.title,
        'Villa',
      );
      expect(
        MapLocationMapper.owners([_owner(name: 'Sara')]).single.title,
        'Sara',
      );
      expect(
        MapLocationMapper.offices([_office()]).single.title,
        'Palm Office',
      );
      expect(MapLocationMapper.watchmen([_watchman()]).single.title, 'Omar');
    });

    test('a blank phone is no phone', () {
      expect(MapLocationMapper.offices([_office()]).single.phoneNumber, isNull);
      expect(
        MapLocationMapper.offers([_offer(phone: '  ')]).single.phoneNumber,
        isNull,
      );
      expect(
        MapLocationMapper.offers([_offer()]).single.phoneNumber,
        '+971501234567',
      );
    });

    test(
      'plain media URLs (the Firebase backend) are kept, blanks dropped',
      () {
        final place = MapLocationMapper.offers([
          _offer(
            mediaUrl: 'https://x/a.jpg',
            mediaUrls: ['https://x/a.jpg', ' '],
          ),
        ]).single;
        expect(place.mediaUrl, 'https://x/a.jpg');
        expect(place.mediaUrls, ['https://x/a.jpg']);
        final none = MapLocationMapper.offers([_offer()]).single;
        expect(none.mediaUrl, isNull);
        expect(none.mediaUrls, isEmpty);
      },
    );

    test('the details the cards use are carried along', () {
      final offer = MapLocationMapper.offers([_offer()]).single;
      expect(offer.additionalData['offerType'], 'rent');
      expect(offer.additionalData['city'], 'Dubai');
      final office = MapLocationMapper.offices([_office()]).single;
      expect(office.additionalData['managerName'], 'Ali');
    });
  });

  group('the small address line', () {
    test('the area and the city: the last two meaningful parts', () {
      expect(
        MapLocationMapper.areaAndCity(
          'Marina Walk, Dubai Marina, Dubai, United Arab Emirates',
        ),
        'Dubai Marina, Dubai',
      );
      expect(
        MapLocationMapper.areaAndCity('Business Bay, Dubai'),
        'Business Bay, Dubai',
      );
    });

    test('street words and numbers are dropped, as words', () {
      expect(
        MapLocationMapper.areaAndCity('12 Sheikh Zayed St, Downtown, Dubai'),
        'Downtown, Dubai',
      );
      expect(
        MapLocationMapper.areaAndCity('Al Wasl Street, Jumeirah, Dubai'),
        'Jumeirah, Dubai',
      );
    });

    test('an area that merely contains the letters "st" is kept', () {
      // It used to be dropped: "Investments" and "Studio" contain "st".
      expect(
        MapLocationMapper.areaAndCity('Dubai Investments Park, Dubai'),
        'Dubai Investments Park, Dubai',
      );
      expect(
        MapLocationMapper.areaAndCity('Dubai Studio City, Dubai'),
        'Dubai Studio City, Dubai',
      );
      expect(
        MapLocationMapper.areaAndCity('Dubai Sports City, Dubai'),
        'Dubai Sports City, Dubai',
      );
    });

    test('with only one meaningful part, that part', () {
      expect(MapLocationMapper.areaAndCity('Dubai, UAE'), 'Dubai');
    });

    test('with nothing meaningful, the end of the address as it is', () {
      expect(MapLocationMapper.areaAndCity('12, 34, UAE'), '34, UAE');
      expect(MapLocationMapper.areaAndCity('UAE'), 'UAE');
    });

    test('empty is empty', () {
      expect(MapLocationMapper.areaAndCity(''), '');
      expect(MapLocationMapper.areaAndCity(' , , '), ' , , ');
    });
  });

  group('what the filters look at', () {
    // The app's own sources, standing in for the ARB-backed ones.
    final vocabulary = MapVocabulary(
      offerPropertyKey: (stored) => MapPropertyTypes.canonicalKey(
        stored,
        const ['apartment', 'villa', 'fullFloor', 'hotelAndHotelApartment'],
      ),
      ownerPropertyKey: (stored) {
        final wanted = stored.trim().toLowerCase();
        return const {'villa': 'villa', 'shop/retail': 'shopRetail'}[wanted];
      },
      cityOfText: (text) {
        final lower = text.toLowerCase();
        for (final city in const ['Dubai', 'Abu Dhabi']) {
          final wanted = city.toLowerCase();
          if (lower == wanted || lower.endsWith(', $wanted')) return city;
        }
        return null;
      },
    );

    test('the selector\'s kinds are exactly the kinds the mapper produces', () {
      final places = MapLocationMapper.all(
        offers: [_offer()],
        owners: [_owner()],
        offices: [_office()],
        watchmen: [_watchman()],
      );
      expect({
        for (final place in places) place.type,
      }, MapEntityTypes.all.toSet());
      expect(MapEntityTypes.all, hasLength(4));
    });

    test('an Offer\'s city is the catalog\'s spelling', () {
      expect(
        MapLocationMapper.offers([_offer(city: 'Dubai')]).single.city,
        'Dubai',
      );
      expect(
        MapLocationMapper.offers([_offer(city: ' abu dhabi ')]).single.city,
        'Abu Dhabi',
      );
      expect(
        MapLocationMapper.offers([_offer(city: 'Atlantis')]).single.city,
        isNull,
        reason: 'not a catalog city: not filterable',
      );
      expect(MapLocationMapper.offers([_offer(city: '')]).single.city, isNull);
    });

    test('an Offer\'s transaction is its stored rent or sell', () {
      CachedLocationData offer(String type) =>
          MapLocationMapper.offers([_offer(offerType: type)]).single;
      expect(offer('rent').transaction, MapTransaction.rent);
      expect(offer('sell').transaction, MapTransaction.sale);
      expect(
        offer('for rent').transaction,
        isNull,
        reason: 'free text is never read',
      );
    });

    test('an Offer\'s property type is the form\'s key', () {
      CachedLocationData offer(String specific) => MapLocationMapper.offers([
            _offer(specific: specific),
          ], vocabulary: vocabulary)
              .single;
      expect(offer('Villa').propertyType, 'villa');
      expect(offer(' villa ').propertyType, 'villa');
      expect(offer('Full Floor').propertyType, 'fullFloor');
      expect(
        offer('Hotel & Hotel Apartment').propertyType,
        'hotelAndHotelApartment',
      );
      expect(
        offer('Hotel Hotel Apartment').propertyType,
        'hotelAndHotelApartment',
      );
      expect(offer('Spaceship').propertyType, isNull);
      expect(offer('').propertyType, isNull);
    });

    test(
      'an Owner has a city and a type from its own saved text, no transaction',
      () {
        final owner = MapLocationMapper.owners([
          _owner(type: 'Villa', propertyLocation: 'Marina, Abu Dhabi'),
        ], vocabulary: vocabulary)
            .single;
        expect(owner.city, 'Abu Dhabi');
        expect(owner.propertyType, 'villa');
        expect(owner.transaction, isNull);
        final own = MapLocationMapper.owners([
          _owner(type: 'Castle', propertyLocation: 'Somewhere nice'),
        ], vocabulary: vocabulary)
            .single;
        expect(own.city, isNull);
        expect(
          own.propertyType,
          isNull,
          reason: 'the owner\'s own wording is not a canonical type',
        );
      },
    );

    test('an Office and a Watchman have no type and no transaction', () {
      final office = MapLocationMapper.offices([
        _office(),
      ], vocabulary: vocabulary)
          .single;
      final watchman = MapLocationMapper.watchmen([
        _watchman(),
      ], vocabulary: vocabulary)
          .single;
      for (final place in [office, watchman]) {
        expect(place.propertyType, isNull);
        expect(place.transaction, isNull);
      }
    });

    test(
      'an Office has a city only when its location text starts with one',
      () {
        CachedLocationData office(String text) => MapLocationMapper.offices([
              _office(officeLocation: text),
            ], vocabulary: vocabulary)
                .single;
        expect(office('Dubai').city, 'Dubai');
        expect(office('Behind the mall').city, isNull);
      },
    );

    test(
      'without a vocabulary only the Offer\'s city and transaction are known',
      () {
        final offer = MapLocationMapper.offers([_offer()]).single;
        expect(offer.city, 'Dubai');
        expect(offer.transaction, MapTransaction.rent);
        expect(offer.propertyType, isNull);
        expect(MapLocationMapper.owners([_owner()]).single.city, isNull);
      },
    );

    test('a place is keyed by its kind and its id', () {
      expect(
        MapLocationMapper.offers([_offer(id: 'x')]).single.key,
        'offers:x',
      );
      expect(
        MapLocationMapper.owners([_owner(id: 'x')]).single.key,
        'owners:x',
      );
    });
  });

  group('reloading one at a time', () {
    test('runs the task, and a quiet request runs it once', () async {
      var runs = 0;
      final runner = CoalescedRunner(() async => runs++);
      await runner.run();
      expect(runs, 1);
      expect(runner.isRunning, isFalse);
      await runner.run();
      expect(runs, 2);
    });

    test(
      'a burst of requests during a run costs exactly one more run',
      () async {
        var runs = 0;
        final gates = <Completer<void>>[];
        final runner = CoalescedRunner(() async {
          runs++;
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
        });
        final first = runner.run();
        await pumpEventQueue();
        expect(runs, 1);
        expect(runner.isRunning, isTrue);

        // Five requests while it runs: none starts a parallel run.
        final joined = [for (var i = 0; i < 5; i++) runner.run()];
        await pumpEventQueue();
        expect(runs, 1);

        gates[0].complete();
        await pumpEventQueue();
        expect(runs, 2, reason: 'one more run, for the latest state');
        gates[1].complete();
        await first;
        await Future.wait(joined);
        expect(runs, 2);
        expect(runner.isRunning, isFalse);
      },
    );

    test('a request during the extra run asks for yet another', () async {
      var runs = 0;
      final gates = <Completer<void>>[];
      final runner = CoalescedRunner(() async {
        runs++;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      });
      final done = runner.run();
      await pumpEventQueue();
      runner.run();
      gates[0].complete();
      await pumpEventQueue();
      expect(runs, 2);
      runner.run(); // while the extra run is going
      gates[1].complete();
      await pumpEventQueue();
      expect(runs, 3);
      gates[2].complete();
      await done;
      expect(runs, 3);
    });

    test('a task that throws does not wedge the runner', () async {
      var runs = 0;
      final runner = CoalescedRunner(() async {
        runs++;
        if (runs == 1) throw StateError('boom');
      });
      Object? caught;
      try {
        await runner.run();
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<StateError>());
      expect(runner.isRunning, isFalse);
      await runner.run();
      expect(runs, 2);
    });
  });
}
