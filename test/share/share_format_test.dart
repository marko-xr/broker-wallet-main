import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';

import 'share_fixtures.dart';

void main() {
  final en = labelsIn('en');
  final ar = labelsIn('ar');

  group('clean', () {
    test('trims, and drops empty text and stored placeholders', () {
      expect(ShareFormat.clean('  Villa  '), 'Villa');
      expect(ShareFormat.clean(''), isNull);
      expect(ShareFormat.clean('   '), isNull);
      expect(ShareFormat.clean(null), isNull);
      expect(ShareFormat.clean('null'), isNull);
      expect(ShareFormat.clean('NULL'), isNull);
      expect(ShareFormat.clean('undefined'), isNull);
      expect(ShareFormat.clean('N/A'), isNull);
    });
  });

  group('phone', () {
    test('is written the way the detail screens show it', () {
      expect(ShareFormat.phone('+971501234567', en), '+971 50 123 4567');
      expect(ShareFormat.phone('0501234567', en), '+971 50 123 4567');
      expect(ShareFormat.phone('971501234567', en), '+971 50 123 4567');
    });

    test('carries no invisible mark in English', () {
      final shown = ShareFormat.phone('+971501234567', en)!;
      expect(shown.contains('\u200E'), isFalse);
      expect(shown.contains('\u2066'), isFalse);
    });

    test('is kept in reading order inside an Arabic message', () {
      final shown = ShareFormat.phone('+971501234567', ar)!;
      expect(shown, '\u2066+971 50 123 4567\u2069');
      // The digits themselves are untouched.
      expect(
        shown.replaceAll(RegExp(r'[^0-9]'), ''),
        '971501234567',
      );
    });

    test('says nothing for a missing or number-less value', () {
      expect(ShareFormat.phone('', en), isNull);
      expect(ShareFormat.phone('   ', en), isNull);
      expect(ShareFormat.phone(null, en), isNull);
      expect(ShareFormat.phone('N/A', en), isNull);
      expect(ShareFormat.phone('call me', en), isNull);
    });
  });

  group('price', () {
    test('is a range when both ends are given', () {
      expect(
        ShareFormat.price(min: '1000000', max: '1500000', labels: en),
        'AED 1,000,000 - 1,500,000',
      );
    });

    test('is one amount when only one end or equal ends are given', () {
      expect(ShareFormat.price(min: '', max: '2500000', labels: en),
          'AED 2,500,000');
      expect(ShareFormat.price(min: '2500000', max: '', labels: en),
          'AED 2,500,000');
      expect(ShareFormat.price(min: '2500000', max: '2500000', labels: en),
          'AED 2,500,000');
    });

    test('never shows a raw number with a stray decimal', () {
      expect(ShareFormat.price(min: '', max: '2500000.0', labels: en),
          'AED 2,500,000');
      expect(
          ShareFormat.price(min: '', max: '1234.5', labels: en), 'AED 1,234.5');
    });

    test('reads amounts typed with separators', () {
      expect(ShareFormat.price(min: '', max: '2,500,000', labels: en),
          'AED 2,500,000');
      expect(ShareFormat.price(min: '', max: ' 2 500 000 ', labels: en),
          'AED 2,500,000');
    });

    test('puts the currency after the amount in Arabic, digits kept LTR', () {
      expect(
        ShareFormat.price(min: '', max: '2500000', labels: ar),
        '\u20662,500,000\u2069 ${arbLookup('ar', 'aed')}',
      );
    });

    test('says nothing when there is no price', () {
      expect(ShareFormat.price(min: '', max: '', labels: en), isNull);
      expect(ShareFormat.price(min: ' ', max: 'null', labels: en), isNull);
    });

    test('shows text that is not a number as typed, without a currency', () {
      expect(ShareFormat.price(min: '', max: 'Negotiable', labels: en),
          'Negotiable');
    });
  });

  group('money', () {
    test('uses the quotation\'s own currency, AED when none is set', () {
      expect(ShareFormat.money(120000, en), 'AED 120,000');
      expect(ShareFormat.money(120000, en, currencyCode: 'usd'), 'USD 120,000');
      expect(ShareFormat.money(120000.5, en, currencyCode: 'AED'),
          'AED 120,000.5');
    });

    test('does not invent AED for another currency in Arabic', () {
      expect(
        ShareFormat.money(10, ar, currencyCode: 'USD'),
        '\u206610\u2069 USD',
      );
      expect(
        ShareFormat.money(10, ar),
        '\u206610\u2069 ${arbLookup('ar', 'aed')}',
      );
    });

    test('says nothing for a missing amount', () {
      expect(ShareFormat.money(null, en), isNull);
      expect(ShareFormat.money(double.nan, en), isNull);
    });
  });

  group('number', () {
    test('groups digits and leaves other text alone', () {
      expect(ShareFormat.number('1800'), '1,800');
      expect(ShareFormat.number('1,800'), '1,800');
      expect(ShareFormat.number('about 1800'), 'about 1800');
      expect(ShareFormat.number(''), isNull);
    });
  });

  group('city', () {
    test('is localized for a catalog city in either language', () {
      expect(ShareFormat.city('Dubai', en), 'Dubai');
      expect(ShareFormat.city('Dubai', ar), arbLookup('ar', 'dubai'));
      expect(ShareFormat.city('Abu Dhabi', ar), arbLookup('ar', 'abuDhabi'));
      expect(ShareFormat.city('Ras Al Khaimah', ar),
          arbLookup('ar', 'rasAlKhaimah'));
    });

    test('recognizes older spellings of a catalog city', () {
      expect(ShareFormat.city('dubai', ar), arbLookup('ar', 'dubai'));
      expect(ShareFormat.city('abudhabi', ar), arbLookup('ar', 'abuDhabi'));
      expect(ShareFormat.city('ABU DHABI', en), 'Abu Dhabi');
      expect(ShareFormat.city('khorfakkan', ar), arbLookup('ar', 'khorFakkan'));
    });

    test('shows an unknown city as stored, never as a camel-case key', () {
      expect(ShareFormat.city('Atlantis', ar), 'Atlantis');
      expect(ShareFormat.city('Old Town', en), 'Old Town');
      expect(ShareFormat.city('someCityKey', en), 'Some City Key');
    });

    test('says nothing for an empty city', () {
      expect(ShareFormat.city('', en), isNull);
      expect(ShareFormat.city(null, en), isNull);
      expect(ShareFormat.city('null', en), isNull);
    });
  });

  group('areas — the shared UAE catalog, no second map', () {
    test('every catalog key is shown by the catalog\'s own name', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        for (final key in UaeAreaCatalog.areasFor(city)) {
          expect(ShareFormat.area(key, en), arbLookup('en', key),
              reason: '$city / $key in English');
          expect(ShareFormat.area(key, ar), arbLookup('ar', key),
              reason: '$city / $key in Arabic');
        }
      }
    });

    test('a key an older picker offered still has its name', () {
      for (final entry in UaeAreaCatalog.legacyOnlyAreas.entries) {
        for (final key in entry.value) {
          expect(ShareFormat.area(key, ar), arbLookup('ar', key),
              reason: '${entry.key} / $key');
        }
      }
    });

    test('an English name an older picker stored finds its catalog area', () {
      expect(
          ShareFormat.area('Dubai Marina', ar), arbLookup('ar', 'dubaiMarina'));
      expect(
          ShareFormat.area('dubai marina', ar), arbLookup('ar', 'dubaiMarina'));
      expect(ShareFormat.area('Jumeirah Village Circle', ar),
          arbLookup('ar', 'jvc'));
      // The catalog's name has a bracket the stored name does not.
      expect(ShareFormat.area('Jumeirah Beach Residence', ar),
          arbLookup('ar', 'jbr'));
    });

    test('an unknown stored value is shown safely', () {
      expect(ShareFormat.area('Some Old Area', en), 'Some Old Area');
      expect(ShareFormat.area('oldAreaKey', en), 'Old Area Key');
      expect(ShareFormat.area('منطقة قديمة', ar), 'منطقة قديمة');
    });

    test('a list keeps its order and shows each area once', () {
      expect(
        ShareFormat.areas(
            <String>['jbr', 'dubaiMarina', 'jbr', '', 'null'], ar),
        <String>[arbLookup('ar', 'jbr')!, arbLookup('ar', 'dubaiMarina')!],
      );
    });
  });

  group('property types', () {
    test('the main category is localized, or capitalized when unknown', () {
      expect(ShareFormat.mainPropertyType('residential', en), 'Residential');
      expect(ShareFormat.mainPropertyType('Commercial', ar),
          arbLookup('ar', 'commercial'));
      expect(ShareFormat.mainPropertyType('mixeduse', en), 'Mixeduse');
      expect(ShareFormat.mainPropertyType('', en), isNull);
    });

    test('the specific type is localized from the forms\' own list', () {
      expect(ShareFormat.propertyType('Villa', ar), arbLookup('ar', 'villa'));
      expect(ShareFormat.propertyType('office space', en), 'Office Space');
      expect(ShareFormat.propertyType('Office Space', ar),
          arbLookup('ar', 'officeSpace'));
      expect(ShareFormat.propertyType('Hotel & Hotel Apartment', ar),
          arbLookup('ar', 'hotelAndHotelApartment'));
      expect(ShareFormat.propertyType('hotel hotel apartment', en),
          'Hotel & Hotel Apartment');
    });

    test('a type the forms do not know is shown as stored', () {
      expect(ShareFormat.propertyType('Castle', en), 'Castle');
      expect(ShareFormat.propertyType('', en), isNull);
    });

    test('rooms and bathrooms belong to villas, apartments and studios', () {
      expect(ShareFormat.showsRoomsAndBathrooms('Villa'), isTrue);
      expect(ShareFormat.showsRoomsAndBathrooms('apartment'), isTrue);
      expect(ShareFormat.showsRoomsAndBathrooms('STUDIO'), isTrue);
      expect(ShareFormat.showsRoomsAndBathrooms('land'), isFalse);
      expect(ShareFormat.showsRoomsAndBathrooms(''), isFalse);
      expect(ShareFormat.showsRoomsAndBathrooms(null), isFalse);
    });
  });

  group('map', () {
    test('accepts the coordinates the detail screens accept', () {
      expect(ShareFormat.validLatLng(25.2, 55.27), isTrue);
      expect(ShareFormat.validLatLng(-33.9, 151.2), isTrue);
    });

    test('refuses an unset pin, a half pin and out-of-range values', () {
      expect(ShareFormat.validLatLng(null, null), isFalse);
      expect(ShareFormat.validLatLng(25.2, null), isFalse);
      expect(ShareFormat.validLatLng(0.0, 0.0), isFalse);
      expect(ShareFormat.validLatLng(91, 10), isFalse);
      expect(ShareFormat.validLatLng(10, 181), isFalse);
      expect(ShareFormat.validLatLng(double.nan, 10), isFalse);
    });

    test('the link is the public map link the detail screens open', () {
      expect(
        ShareFormat.mapLink(25.2, 55.27),
        'https://www.google.com/maps/search/?api=1&query=25.2,55.27',
      );
    });
  });

  group('file names', () {
    test('keep letters and digits and join them with hyphens', () {
      expect(ShareFormat.fileStem('Apartment 306'), 'Apartment-306');
      expect(
          ShareFormat.fileStem('  Marina   Gate  Tower '), 'Marina-Gate-Tower');
      expect(ShareFormat.fileStem('شقة 306'), 'شقة-306');
    });

    test('cannot carry a path, a dot trick or a line break', () {
      expect(ShareFormat.fileStem('../../etc/passwd'), 'etc-passwd');
      expect(ShareFormat.fileStem(r'..\..\secret.pdf'), 'secret-pdf');
      expect(
          ShareFormat.fileStem('a/b\\c:d*e?f"g<h>i|j'), 'a-b-c-d-e-f-g-h-i-j');
      expect(ShareFormat.fileStem('line\nbreak\r\n'), 'line-break');
      expect(ShareFormat.fileStem('.hidden'), 'hidden');
    });

    test('are bounded and may end up empty', () {
      expect(ShareFormat.fileStem('x' * 200, maxLength: 40).length, 40);
      expect(ShareFormat.fileStem('...///', maxLength: 40), '');
      expect(ShareFormat.fileStem(null), '');
      expect(ShareFormat.fileStem('null'), '');
    });
  });
}
