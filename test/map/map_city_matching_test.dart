// Which catalog city a record is in, for the map's City filter.
//
// A structured city (an Offer's) is read first. Everything else is a saved text,
// and the city is found in it by whole words, anywhere in it and in either of
// the app's languages: `Ajman, Al Jurf` and `Al Jurf, Ajman` are both Ajman. The
// match is conservative: no loose substrings, no guess when two unrelated cities
// are named, nothing geocoded, nothing stored is changed. Plain Dart.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/data/uae_city_matcher.dart';
import 'package:broker_wallet/src/constants/location_filter.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

/// The app's own labels for a catalog city, English and Arabic, straight from
/// the ARB files (the same ones the forms show).
Iterable<String> _appLabels(String city) {
  final key = UaeAreaCatalog.cityKey(city);
  return [
    for (final code in const ['en', 'ar'])
      if (_arb(code)[key] is String) _arb(code)[key] as String,
  ];
}

final UaeCityMatcher _english = UaeCityMatcher();
final UaeCityMatcher _bothLanguages = UaeCityMatcher(labelsOf: _appLabels);

/// What the app does with a vocabulary: reads text in either language.
final MapVocabulary _vocabulary = MapVocabulary(cityLabels: _appLabels);

final DateTime _now = DateTime(2026, 10, 7);

OfferModel _offer({
  String city = 'Dubai',
  String location = '',
  String address = '',
  String pickUp = '',
}) =>
    OfferModel(
      id: 'o1',
      userId: 'u1',
      offerType: 'rent',
      selectedCity: city,
      selectedAreas: const <String>[],
      location: location,
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '100',
      maxPrice: '200',
      notes: '',
      specificPropertyType: 'Villa',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: pickUp,
      pickUpLatitude: 25.2,
      pickUpLongitude: 55.27,
      pickUpAddress: address,
      uploadedFileName: '',
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OwnerModel _owner({
  String propertyLocation = '',
  String address = '',
  String pickUp = '',
  double lat = 25.1,
  double lng = 55.2,
}) =>
    OwnerModel(
      id: 'w1',
      userId: 'u1',
      name: 'Sara',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: propertyLocation,
      notes: '',
      pickUpLocation: pickUp,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
      mediaUrls: const <String>[],
      createdAt: _now,
      updatedAt: _now,
    );

OfficeModel _office({
  String officeLocation = '',
  String address = '',
  String pickUp = '',
  double lat = 25.3,
  double lng = 55.3,
}) =>
    OfficeModel(
      id: 'f1',
      officeName: 'Palm Office',
      managerName: 'Ali',
      countryCode: '+971',
      phoneNumber: '',
      officeLocation: officeLocation,
      notes: '',
      pickUpLocation: pickUp,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
    );

WatchmenModel _watchman({
  String buildingLocation = '',
  String address = '',
  String pickUp = '',
  double lat = 25.4,
  double lng = 55.4,
}) =>
    WatchmenModel(
      id: 'm1',
      name: 'Omar',
      countryCode: '+971',
      phoneNumber: '',
      buildingName: 'Tower A',
      notes: '',
      buildingLocation: buildingLocation,
      pickUpLocation: pickUp,
      pickUpLatitude: lat,
      pickUpLongitude: lng,
      pickUpAddress: address,
    );

String? _officeCity(String text, {MapVocabulary? vocabulary}) =>
    MapLocationMapper.offices(
      [_office(officeLocation: text)],
      vocabulary: vocabulary ?? _vocabulary,
    ).single.city;

String? _watchmanCity(String text, {MapVocabulary? vocabulary}) =>
    MapLocationMapper.watchmen(
      [_watchman(buildingLocation: text)],
      vocabulary: vocabulary ?? _vocabulary,
    ).single.city;

String? _ownerCity(String text, {MapVocabulary? vocabulary}) =>
    MapLocationMapper.owners(
      [_owner(propertyLocation: text)],
      vocabulary: vocabulary ?? _vocabulary,
    ).single.city;

void main() {
  group('the name of a city on its own (a structured value)', () {
    test('the catalog spelling, case, spaces and hyphens do not matter', () {
      for (final written in [
        'Abu Dhabi',
        'abu dhabi',
        'ABU DHABI',
        '  Abu Dhabi  ',
        'Abu-Dhabi',
        'AbuDhabi',
        'abuDhabi', // the localization key
      ]) {
        expect(_english.canonical(written), 'Abu Dhabi', reason: written);
      }
    });

    test('the app\'s Arabic labels are read too, with their spelling variants',
        () {
      expect(_bothLanguages.canonical('دبي'), 'Dubai');
      expect(_bothLanguages.canonical('أبوظبي'), 'Abu Dhabi');
      expect(_bothLanguages.canonical('أبو ظبي'), 'Abu Dhabi');
      expect(_bothLanguages.canonical('ابوظبي'), 'Abu Dhabi');
      expect(_bothLanguages.canonical('رأس الخيمة'), 'Ras Al Khaimah');
      expect(_bothLanguages.canonical('راس الخيمه'), 'Ras Al Khaimah');
      expect(_bothLanguages.canonical('الفجيره'), 'Fujairah');
      expect(_bothLanguages.canonical('خور فكان'), 'Khor Fakkan');
      expect(_bothLanguages.canonical('خورفكان'), 'Khor Fakkan');
    });

    test('every catalog city is recognised by every label the app has', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        expect(_english.canonical(city), city);
        for (final label in _appLabels(city)) {
          expect(_bothLanguages.canonical(label), city, reason: label);
        }
      }
    });

    test('anything else is not a city: text around it, or a place in it', () {
      for (final other in [
        '',
        '   ',
        'Atlantis',
        'Dubai Marina',
        'Dubai, UAE',
        'Dubailand',
        'The city of Dubai and more words besides',
      ]) {
        expect(_english.canonical(other), isNull, reason: other);
      }
      expect(_english.canonical(null), isNull);
    });
  });

  group('a city named anywhere in a text', () {
    test('at the start, at the end, or in the middle', () {
      expect(_english.cityIn('Ajman, Al Jurf'), 'Ajman');
      expect(_english.cityIn('Al Jurf, Ajman'), 'Ajman');
      expect(_english.cityIn('Al Jurf, Ajman, United Arab Emirates'), 'Ajman');
      expect(_english.cityIn('Al Jurf Ajman'), 'Ajman');
      expect(_english.cityIn('Al Jurf 2 Ajman'), 'Ajman');
      expect(_english.cityIn('Ajman Free Zone'), 'Ajman');
    });

    test('the address styles the app meets', () {
      // A geocoder's address: area, city, emirate, country.
      expect(
        _english.cityIn('Jumeirah 1 - Dubai - United Arab Emirates'),
        'Dubai',
      );
      expect(
        _english.cityIn('Al Majaz 3, Sharjah, United Arab Emirates'),
        'Sharjah',
      );
      // The Owner form's own writing.
      expect(_english.cityIn('Dubai Marina, Dubai'), 'Dubai');
      expect(
        _english.cityIn('Dubai Marina, Dubai, Marina Gate tower 2'),
        'Dubai',
      );
      // Typed by hand.
      expect(
          _english.cityIn('near the mall in ras al khaimah'), 'Ras Al Khaimah');
      expect(_english.cityIn('Behind Fujairah  Mall'), 'Fujairah');
      expect(_english.cityIn("Ra's Al Khaimah, Al Nakheel"), 'Ras Al Khaimah');
      expect(_english.cityIn('UAQ'), isNull,
          reason: 'an abbreviation is no name');
    });

    test('Arabic text is read, with its commas and its variants', () {
      expect(_bothLanguages.cityIn('الجرف، عجمان'), 'Ajman');
      expect(_bothLanguages.cityIn('عجمان، الجرف'), 'Ajman');
      expect(_bothLanguages.cityIn('مرسى دبي'), 'Dubai');
      expect(_bothLanguages.cityIn('شارع الشيخ زايد، دبي'), 'Dubai');
      expect(_bothLanguages.cityIn('المجاز ٣، الشارقة'), 'Sharjah');
      expect(_bothLanguages.cityIn('العين، أبو ظبي'), 'Al Ain');
      expect(_bothLanguages.cityIn('بالقرب من الفجيره مول'), 'Fujairah');
    });

    test(
        'a city that is a whole part of the text beats one inside a longer '
        'part', () {
      expect(_english.cityIn('Dubai Marina, Sharjah'), 'Sharjah');
      expect(_english.cityIn('Sharjah Beach, Ajman'), 'Ajman');
    });

    test('no loose substrings: a name only counts as whole words', () {
      for (final text in [
        'Dubailand',
        'Dubailand, Villa 5',
        'Ajmanian Street',
        'Fujairahs',
        'Salain Road', // "alain" is not the word "al ain"
        'Sharjahan',
        'Dubaian Tower, Floor 2',
      ]) {
        expect(_english.cityIn(text), isNull, reason: text);
      }
      // "Ain Dubai" is a Dubai landmark: it must not become Al Ain.
      expect(_english.cityIn('Ain Dubai, Bluewaters'), 'Dubai');
      expect(_english.cityIn('Ain Dubai'), 'Dubai');
    });

    test('a road named after a city is not the city', () {
      expect(_english.cityIn('Sharjah Road'), isNull);
      expect(_english.cityIn('Dubai Street, Villa 5'), isNull);
      expect(_english.cityIn('Al Ain Road, Al Quoz'), isNull);
      expect(_bothLanguages.cityIn('طريق الشارقة'), isNull);
      expect(_bothLanguages.cityIn('شارع دبي'), isNull);
      // ...but the city named beside it still counts.
      expect(_english.cityIn('Sharjah Road, Ajman'), 'Ajman');
      expect(_english.cityIn('Al Ain Road, Dubai'), 'Dubai');
      expect(_english.cityIn('Abu Dhabi Corniche Road'), 'Abu Dhabi');
    });

    test('two unrelated cities named: no city, not a guess', () {
      expect(_english.cityIn('Dubai, Sharjah'), isNull);
      expect(_english.cityIn('Sharjah - Dubai'), isNull);
      expect(_english.cityIn('Ajman to Fujairah'), isNull);
    });

    test('a city inside another city\'s emirate: the inner one, either order',
        () {
      expect(
          _english.cityIn('Al Ain, Abu Dhabi, United Arab Emirates'), 'Al Ain');
      expect(_english.cityIn('Abu Dhabi, Al Ain'), 'Al Ain');
      expect(_english.cityIn('Al Jimi - Al Ain - Abu Dhabi'), 'Al Ain');
      expect(_english.cityIn('Khor Fakkan, Sharjah'), 'Khor Fakkan');
      expect(_english.cityIn('Sharjah - Khor Fakkan'), 'Khor Fakkan');
      // Only the pairs that really nest: these two are unrelated.
      expect(_english.cityIn('Al Ain, Sharjah'), isNull);
      expect(_english.cityIn('Khor Fakkan, Abu Dhabi'), isNull);
    });

    test('the nesting is between catalog cities only', () {
      // A guard on the matcher's one small table: a rename in the catalog
      // would otherwise silently break it.
      for (final pair in const {
        'Al Ain': 'Abu Dhabi',
        'Khor Fakkan': 'Sharjah',
      }.entries) {
        expect(UaeAreaCatalog.supportedCities, contains(pair.key));
        expect(UaeAreaCatalog.supportedCities, contains(pair.value));
      }
    });

    test('nothing, or nothing about a city, is no city', () {
      expect(_english.cityIn(null), isNull);
      expect(_english.cityIn(''), isNull);
      expect(_english.cityIn(' , , '), isNull);
      expect(_english.cityIn('Behind the mall'), isNull);
      expect(_english.cityIn('United Arab Emirates'), isNull);
      expect(_english.cityIn('12, 34'), isNull);
    });

    test('Arabic names are not read when the matcher only knows English', () {
      expect(_english.cityIn('الجرف، عجمان'), isNull);
    });
  });

  group('an Office\'s city (the location text need not start with it)', () {
    test('"City, Area" and "Area, City" are the same city', () {
      expect(_officeCity('Ajman, Al Jurf'), 'Ajman');
      expect(_officeCity('Al Jurf, Ajman'), 'Ajman');
    });

    test('other shapes of the same text', () {
      expect(_officeCity('Al Jurf Industrial Area, Ajman, UAE'), 'Ajman');
      expect(_officeCity('Office 12, Al Jurf - Ajman'), 'Ajman');
      expect(_officeCity('عجمان، الجرف'), 'Ajman');
      expect(_officeCity('الجرف، عجمان'), 'Ajman');
    });

    test('a text that names no city, and no address that does, is no city', () {
      expect(_officeCity('Behind the mall'), isNull);
    });

    test('the picker\'s address says it when the typed text does not', () {
      final place = MapLocationMapper.offices(
        [
          _office(
            officeLocation: 'Behind the mall',
            address: 'Al Jurf 1 - Ajman - United Arab Emirates',
          ),
        ],
        vocabulary: _vocabulary,
      ).single;
      expect(place.city, 'Ajman');
    });

    test('what was typed comes before the picker\'s address', () {
      final place = MapLocationMapper.offices(
        [
          _office(
            officeLocation: 'Dubai Marina, Dubai',
            address: 'Al Jurf 1 - Ajman - United Arab Emirates',
          ),
        ],
        vocabulary: _vocabulary,
      ).single;
      expect(place.city, 'Dubai');
    });
  });

  group('a Watchman\'s city', () {
    test('"City, Area" and "Area, City" are the same city', () {
      expect(_watchmanCity('Ajman, Al Jurf'), 'Ajman');
      expect(_watchmanCity('Al Jurf, Ajman'), 'Ajman');
    });

    test('Arabic, and the nested emirate pairs', () {
      expect(_watchmanCity('برج الخليج، عجمان'), 'Ajman');
      expect(_watchmanCity('Al Jimi, Al Ain, Abu Dhabi'), 'Al Ain');
    });

    test('a text that names no city is no city', () {
      expect(_watchmanCity('Marina'), isNull);
    });

    test('the picker\'s address, then the pin\'s own text, are read too', () {
      expect(
        MapLocationMapper.watchmen(
          [
            _watchman(
              buildingLocation: 'Tower A',
              address: 'Corniche, Fujairah, United Arab Emirates',
            ),
          ],
          vocabulary: _vocabulary,
        ).single.city,
        'Fujairah',
      );
      expect(
        MapLocationMapper.watchmen(
          [
            _watchman(
                buildingLocation: 'Tower A', pickUp: 'Khor Fakkan, Sharjah')
          ],
          vocabulary: _vocabulary,
        ).single.city,
        'Khor Fakkan',
      );
    });
  });

  group('an Owner\'s city', () {
    test('"Area, City" in the Owner form\'s own writing, in either order', () {
      expect(_ownerCity('Dubai Marina, Dubai'), 'Dubai');
      expect(_ownerCity('Dubai'), 'Dubai');
      expect(_ownerCity('Al Jurf, Ajman'), 'Ajman');
      expect(_ownerCity('Ajman, Al Jurf'), 'Ajman');
      expect(_ownerCity('مرسى دبي، دبي'), 'Dubai');
    });

    test('the form\'s own reader still comes first when it answers', () {
      // A vocabulary whose reader says Sharjah: it wins over what the words say.
      final vocabulary = MapVocabulary(
        cityOfText: (text) => 'Sharjah',
        cityLabels: _appLabels,
      );
      expect(_ownerCity('Al Jurf, Ajman', vocabulary: vocabulary), 'Sharjah');
      // When it does not answer, the words do.
      final silent = MapVocabulary(
        cityOfText: (text) => null,
        cityLabels: _appLabels,
      );
      expect(_ownerCity('Al Jurf, Ajman', vocabulary: silent), 'Ajman');
    });

    test('text that names no city is no city', () {
      expect(_ownerCity('Somewhere nice'), isNull);
    });
  });

  group('an Offer\'s city (structured first)', () {
    test('the selected city is used, however it is written', () {
      for (final written in ['Dubai', ' dubai ', 'DUBAI']) {
        final place = MapLocationMapper.offers(
          [_offer(city: written)],
          vocabulary: _vocabulary,
        ).single;
        expect(place.city, 'Dubai', reason: written);
      }
      expect(
        MapLocationMapper.offers(
          [_offer(city: 'دبي')],
          vocabulary: _vocabulary,
        ).single.city,
        'Dubai',
        reason: 'an Arabic label of the city is the city',
      );
    });

    test('the structured city wins over the address text', () {
      final place = MapLocationMapper.offers(
        [_offer(city: 'Dubai', address: 'Al Jurf, Ajman')],
        vocabulary: _vocabulary,
      ).single;
      expect(place.city, 'Dubai');
    });

    test('an older Offer with no usable city falls back to its text', () {
      final fromAddress = MapLocationMapper.offers(
        [_offer(city: '', address: 'Al Jurf, Ajman, United Arab Emirates')],
        vocabulary: _vocabulary,
      ).single;
      expect(fromAddress.city, 'Ajman');
      final fromLocation = MapLocationMapper.offers(
        [_offer(city: 'Atlantis', location: 'Al Jurf, Ajman')],
        vocabulary: _vocabulary,
      ).single;
      expect(fromLocation.city, 'Ajman');
    });

    test('with no vocabulary only the structured city is read', () {
      expect(MapLocationMapper.offers([_offer(city: '')]).single.city, isNull);
      expect(
        MapLocationMapper.offers(
          [_offer(city: '', address: 'Al Jurf, Ajman')],
        ).single.city,
        isNull,
        reason: 'text is read only when the app gives the map its vocabulary',
      );
      expect(MapLocationMapper.offers([_offer(city: 'Dubai')]).single.city,
          'Dubai');
    });
  });

  group('nothing is geocoded and nothing stored is changed', () {
    test('mapping leaves every record exactly as it was', () {
      final office = _office(officeLocation: 'Al Jurf, Ajman');
      final watchman = _watchman(buildingLocation: 'Al Jurf, Ajman');
      final owner = _owner(propertyLocation: 'Al Jurf, Ajman');
      final offer = _offer(city: '', address: 'Al Jurf, Ajman');
      MapLocationMapper.all(
        offers: [offer],
        owners: [owner],
        offices: [office],
        watchmen: [watchman],
        vocabulary: _vocabulary,
      );
      expect(office.officeLocation, 'Al Jurf, Ajman');
      expect(watchman.buildingLocation, 'Al Jurf, Ajman');
      expect(owner.propertyLocation, 'Al Jurf, Ajman');
      expect(offer.selectedCity, '');
      expect(offer.pickUpAddress, 'Al Jurf, Ajman');
    });

    test('the matcher is pure text: its file imports nothing but the catalog',
        () {
      final source =
          File('lib/src/common/data/uae_city_matcher.dart').readAsStringSync();
      final imports = RegExp(r"^import '([^']+)';", multiLine: true)
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();
      expect(imports, [
        'package:broker_wallet/src/common/data/uae_area_catalog.dart',
      ]);
      for (final network in ['http', 'geocoding', 'Future<', 'async']) {
        expect(source.contains(network), isFalse, reason: network);
      }
    });
  });

  group('the City filter finds them', () {
    // A record's city and its pin are two fields; the City filter shows a place
    // under a city only when its pin is not clearly in another one. These
    // places' pins are where their city says: in Ajman, and in Dubai.
    const ajmanLat = 25.405;
    const ajmanLng = 55.514;

    List<CachedLocationData> places() => MapLocationMapper.all(
          offers: [_offer(city: 'Dubai')],
          owners: [
            _owner(
              propertyLocation: 'Al Jurf, Ajman',
              lat: ajmanLat,
              lng: ajmanLng,
            ),
          ],
          offices: [
            _office(
              officeLocation: 'Al Jurf, Ajman',
              lat: ajmanLat,
              lng: ajmanLng,
            ),
          ],
          watchmen: [
            _watchman(
              buildingLocation: 'Ajman, Al Jurf',
              lat: ajmanLat,
              lng: ajmanLng,
            ),
          ],
          vocabulary: _vocabulary,
        );

    test('the Office, the Watchman and the Owner are all in Ajman', () {
      final controller = MapFilterController()..setRecords(places());
      controller.setCity('Ajman');
      expect(
        {for (final place in controller.visible) place.type},
        {
          LocationFilter.owners,
          LocationFilter.offices,
          LocationFilter.watchmen,
        },
      );
      controller.setCity('Dubai');
      expect(
        controller.visible.map((place) => place.type),
        [LocationFilter.offers],
      );
    });

    test('Office and Watchman in Ajman, whichever way round the text is', () {
      for (final text in ['Ajman, Al Jurf', 'Al Jurf, Ajman']) {
        final controller = MapFilterController()
          ..setRecords(
            MapLocationMapper.all(
              offices: [
                _office(officeLocation: text, lat: ajmanLat, lng: ajmanLng),
              ],
              watchmen: [
                _watchman(buildingLocation: text, lat: ajmanLat, lng: ajmanLng),
              ],
              vocabulary: _vocabulary,
            ),
          )
          ..setCity('Ajman');
        expect(controller.visible, hasLength(2), reason: text);
      }
    });
  });
}
