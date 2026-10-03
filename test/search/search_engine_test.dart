// What Search finds and in what order: matching (every word, any field, any
// order), the bilingual names of cities, areas, property types and deal types,
// phone numbers written any common way, ranking, the type filter, duplicates and
// a stable order. Pure Dart over the real English and Arabic strings.

import 'dart:math';

import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/utils/search_text.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_engine.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_fixtures.dart';

final SearchEngine _engine = newEngine();

SearchCorpus _corpus(SearchData data) => _engine.index(data);

List<SearchResult> _find(
  SearchCorpus corpus,
  String query, {
  SearchResultType? type,
}) =>
    _engine.search(
      corpus,
      tokens: SearchText.tokens(query),
      displayQuery: SearchText.collapse(query),
      type: type,
    );

List<String> _ids(List<SearchResult> results) =>
    results.map((r) => r.id).toList();

String _en(String key) => enArb[key] as String;
String _ar(String key) => arArb[key] as String;

void main() {
  group('matching', () {
    test('a name matches in any case', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'Ahmed Khan'),
      ]));
      expect(_ids(_find(corpus, 'ahmed')), ['o1']);
      expect(_ids(_find(corpus, 'AHMED')), ['o1']);
      expect(_ids(_find(corpus, 'kHaN')), ['o1']);
    });

    test('a word matches inside a field', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'Abdulrahman'),
      ]));
      expect(_ids(_find(corpus, 'rahman')), ['o1']);
    });

    test('surrounding and repeated spaces change nothing', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'Ahmed Khan'),
      ]));
      final plain = _ids(_find(corpus, 'ahmed khan'));
      expect(plain, ['o1']);
      expect(_ids(_find(corpus, '  ahmed   khan  ')), plain);
      expect(_ids(_find(corpus, 'ahmed khan ')), plain);
    });

    test('a query with no words finds nothing', () {
      final corpus = _corpus(SearchData(owners: [owner(id: 'o1', name: 'A')]));
      expect(_find(corpus, ''), isEmpty);
      expect(_find(corpus, '   '), isEmpty);
      expect(_find(corpus, '...'), isEmpty);
    });

    test('every word must match, in any order, across fields', () {
      final corpus = _corpus(SearchData(requests: [
        request(
          id: 'r1',
          city: 'Dubai',
          propertyType: 'residential',
          specific: 'Villa',
        ),
        request(id: 'r2', city: 'Abu Dhabi', specific: 'Villa'),
        request(id: 'r3', city: 'Dubai', specific: 'Studio'),
      ]));
      expect(_ids(_find(corpus, 'villa dubai')), ['r1']);
      expect(_ids(_find(corpus, 'dubai villa')), ['r1']);
      expect(_ids(_find(corpus, 'villa')).toSet(), {'r1', 'r2'});
      expect(_find(corpus, 'villa sharjah'), isEmpty);
    });

    test('punctuation between words is not part of them', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', propertyLocation: 'Marina Gate, Dubai'),
      ]));
      expect(_ids(_find(corpus, 'marina, dubai')), ['o1']);
      expect(_ids(_find(corpus, 'dubai.')), ['o1']);
    });

    test('Arabic: Alef variants, diacritics and tatweel find the same name',
        () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'أحمد'),
        owner(id: 'o2', name: 'مُحَمَّد'),
      ]));
      for (final query in ['أحمد', 'احمد', 'إحمد', 'آحمد', 'احـمد', 'اَحمد']) {
        expect(_ids(_find(corpus, query)), ['o1'], reason: query);
      }
      for (final query in ['محمد', 'مُحمّد', 'مـحـمـد']) {
        expect(_ids(_find(corpus, query)), ['o2'], reason: query);
      }
    });

    test('Arabic: Teh Marbuta and Yeh variants', () {
      final corpus = _corpus(SearchData(offices: [
        office(id: 'f1', name: 'مكتب الشارقة', location: 'دبى'),
      ]));
      expect(_ids(_find(corpus, 'الشارقه')), ['f1']);
      expect(_ids(_find(corpus, 'دبي')), ['f1']);
    });

    test('Arabic: unrelated names are not made to match', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'مؤمن'),
        owner(id: 'o2', name: 'عمر'),
      ]));
      expect(_find(corpus, 'مومن'), isEmpty);
      expect(_find(corpus, 'امر'), isEmpty);
    });

    test('stored text is never rewritten', () {
      final model = owner(id: 'o1', name: 'أَحمد  Khan');
      final result = _find(_corpus(SearchData(owners: [model])), 'احمد').single;
      expect(identical(result.data, model), isTrue);
      expect(result.title, 'أَحمد  Khan');
    });
  });

  group('phone numbers', () {
    final corpus = _corpus(SearchData(
      owners: [owner(id: 'o1', name: 'A', phone: '501234567')],
      offices: [office(id: 'f1', name: 'B', phone: '971509998888')],
      brokers: [broker(id: 'b1', name: 'C', phone: '0507776666')],
    ));

    test('found as stored, local, and international', () {
      expect(_ids(_find(corpus, '501234567')), ['o1']);
      expect(_ids(_find(corpus, '0501234567')), ['o1']);
      expect(_ids(_find(corpus, '971501234567')), ['o1']);
      expect(_ids(_find(corpus, '+971501234567')), ['o1']);
    });

    test('a number stored with its country code is found locally', () {
      expect(_ids(_find(corpus, '0509998888')), ['f1']);
      expect(_ids(_find(corpus, '509998888')), ['f1']);
    });

    test('a number stored with a leading zero is found internationally', () {
      expect(_ids(_find(corpus, '971507776666')), ['b1']);
      expect(_ids(_find(corpus, '507776666')), ['b1']);
    });

    test('a fragment finds the number', () {
      expect(_ids(_find(corpus, '12345')), ['o1']);
      expect(_ids(_find(corpus, '9998')), ['f1']);
    });

    test('Arabic-Indic digits find the same numbers', () {
      expect(_ids(_find(corpus, '٠٥٠١٢٣٤٥٦٧')), ['o1']);
      expect(_ids(_find(corpus, '١٢٣٤٥')), ['o1']);
    });

    test('one digit is not a phone search', () {
      // A single digit would match nearly every number.
      expect(_find(corpus, '5'), isEmpty);
    });

    test('a number that is not there finds nothing', () {
      expect(_find(corpus, '0501234560'), isEmpty);
      expect(_find(corpus, '99999'), isEmpty);
    });

    test('a number does not match the middle of a price', () {
      final data = _corpus(SearchData(requests: [
        request(
            id: 'r1',
            minPrice: '15000',
            maxPrice: '20500',
            squareFootage: '1050'),
      ]));
      expect(_find(data, '05'), isEmpty, reason: '05 is in 1050 and 20500');
      expect(_ids(_find(data, '1500')), ['r1'], reason: 'the start of 15000');
      expect(_find(data, '5000'), isEmpty, reason: 'the end of 15000');
      expect(_ids(_find(data, '1050')), ['r1']);
    });

    test('a decimal is not read as part of the number', () {
      final data = _corpus(SearchData(requests: [
        request(id: 'r1', squareFootage: '1,200.5', minPrice: '2500.75'),
      ]));
      expect(_ids(_find(data, '1200')), ['r1'], reason: 'the whole part');
      expect(_find(data, '12005'), isEmpty, reason: 'not 1200 and a half');
      expect(_ids(_find(data, '2500')), ['r1']);
      expect(_find(data, '250075'), isEmpty);
    });

    test('a number is compared by its digits, not as text', () {
      final data = _corpus(SearchData(requests: [
        request(id: 'r1', minPrice: '900'),
        request(id: 'r2', minPrice: '1000'),
      ]));
      // Matched by digits from the start: 900 is not 1000 however they sort.
      expect(_ids(_find(data, '900')), ['r1']);
      expect(_ids(_find(data, '1000')), ['r2']);
      expect(_ids(_find(data, '90')), ['r1'], reason: 'the start of 900');
    });
  });

  group('bilingual names', () {
    final dubaiAreas = UaeAreaCatalog.areasFor('Dubai');
    final areaKey = dubaiAreas.first;

    test('a stored city is found by its English and Arabic name', () {
      final corpus = _corpus(SearchData(requests: [
        request(id: 'r1', city: 'Dubai'),
      ]));
      expect(_ids(_find(corpus, _en('dubai'))), ['r1']);
      expect(_ids(_find(corpus, _ar('dubai'))), ['r1']);
    });

    test('every supported city is found by its Arabic name', () {
      // The old search knew seven of the nine: Al Ain and Khor Fakkan were
      // missing.
      for (final city in UaeAreaCatalog.supportedCities) {
        final corpus = _corpus(SearchData(offers: [
          offer(id: 'x', city: city),
        ]));
        final arabic = _ar(UaeAreaCatalog.cityKey(city));
        final english = _en(UaeAreaCatalog.cityKey(city));
        expect(_ids(_find(corpus, arabic)), ['x'], reason: '$city ($arabic)');
        expect(_ids(_find(corpus, english)), ['x'], reason: '$city ($english)');
      }
    });

    test('a stored area key is found by its names, not by its key', () {
      final corpus = _corpus(SearchData(requests: [
        request(id: 'r1', city: 'Dubai', areas: [areaKey]),
      ]));
      expect(_ids(_find(corpus, _en(areaKey))), ['r1']);
      expect(_ids(_find(corpus, _ar(areaKey))), ['r1']);
    });

    test('a stored area the catalog does not know is searched as typed', () {
      final corpus = _corpus(SearchData(offers: [
        offer(id: 'o1', city: 'Dubai', areas: ['My Own Spot']),
      ]));
      expect(_ids(_find(corpus, 'own spot')), ['o1']);
    });

    test('a city and an area together, in the other language', () {
      final corpus = _corpus(SearchData(requests: [
        request(id: 'r1', city: 'Dubai', areas: [areaKey]),
        request(id: 'r2', city: 'Abu Dhabi'),
      ]));
      final query = '${_ar(areaKey)} ${_ar('dubai')}';
      expect(_ids(_find(corpus, query)), ['r1']);
    });

    test('a property type is found in both languages', () {
      final corpus = _corpus(SearchData(requests: [
        request(id: 'r1', propertyType: 'residential', specific: 'Villa'),
        request(id: 'r2', propertyType: 'commercial', specific: 'Office Space'),
      ]));
      expect(_ids(_find(corpus, _ar('villa'))), ['r1']);
      expect(_ids(_find(corpus, 'villa')), ['r1']);
      expect(_ids(_find(corpus, _ar('residential'))), ['r1']);
      expect(_ids(_find(corpus, _ar('commercial'))), ['r2']);
      expect(_ids(_find(corpus, _en('officeSpace'))), ['r2']);
      expect(_ids(_find(corpus, _ar('officeSpace'))), ['r2']);
    });

    test('a deal type is found in both languages', () {
      final corpus = _corpus(SearchData(
        requests: [request(id: 'r1', type: 'rent')],
        offers: [offer(id: 'o1', type: 'sell')],
      ));
      expect(_ids(_find(corpus, _ar('rent'))), ['r1']);
      expect(_ids(_find(corpus, 'rent')), ['r1']);
      expect(_ids(_find(corpus, _ar('sale'))), ['o1']);
      expect(_ids(_find(corpus, 'sale')), ['o1']);
      expect(_ids(_find(corpus, 'sell')), ['o1']);
    });

    test('an Owner property type typed in either language is found in both',
        () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', typeOfProperties: _ar('villa')),
        owner(id: 'o2', typeOfProperties: _en('apartment')),
      ]));
      expect(_ids(_find(corpus, 'villa')), ['o1']);
      expect(_ids(_find(corpus, _ar('villa'))), ['o1']);
      expect(_ids(_find(corpus, _ar('apartment'))), ['o2']);
      expect(_ids(_find(corpus, 'apartment')), ['o2']);
    });

    test('an Owner own wording is searched as written', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', typeOfProperties: 'Seaside chalet'),
      ]));
      expect(_ids(_find(corpus, 'chalet')), ['o1']);
      expect(_find(corpus, _ar('villa')), isEmpty);
    });

    test('an Owner location the app wrote is found in the other language', () {
      final codec = OwnerLocationCodec(lookup: arbLookup);
      final saved = codec.encode(
        city: 'Dubai',
        areaKey: areaKey,
        language: 'ar',
      );
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', propertyLocation: saved),
      ]));
      expect(_ids(_find(corpus, saved)), ['o1']);
      expect(_ids(_find(corpus, _en(areaKey))), ['o1']);
      expect(_ids(_find(corpus, _en('dubai'))), ['o1']);
    });

    test('an Owner location typed by hand is searched as written', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', propertyLocation: 'Behind the old souk'),
      ]));
      expect(_ids(_find(corpus, 'old souk')), ['o1']);
    });

    test('every stored property vocabulary key exists in both languages', () {
      for (final key in SearchEngine.propertyTypeLocalizationKeys) {
        expect(enArb[key], isA<String>(), reason: 'en: $key');
        expect(arArb[key], isA<String>(), reason: 'ar: $key');
      }
      for (final key in const ['rent', 'sale']) {
        expect(enArb[key], isA<String>(), reason: 'en: $key');
        expect(arArb[key], isA<String>(), reason: 'ar: $key');
      }
    });
  });

  group('ranking', () {
    test('exact, then prefix, then word-prefix, then contains', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'contains', name: 'Misam'),
        owner(id: 'word', name: 'Abu Sam'),
        owner(id: 'prefix', name: 'Samir'),
        owner(id: 'exact', name: 'Sam'),
      ]));
      expect(
          _ids(_find(corpus, 'sam')), ['exact', 'prefix', 'word', 'contains']);
    });

    test('a name outranks a place outranks a note', () {
      final corpus = _corpus(SearchData(
        owners: [
          owner(id: 'note', name: 'Zed', notes: 'friend of marina'),
          owner(id: 'place', name: 'Yan', propertyLocation: 'marina'),
          owner(id: 'name', name: 'Marina'),
        ],
      ));
      expect(_ids(_find(corpus, 'marina')), ['name', 'place', 'note']);
    });

    test('a record that matches in its name beats weak matches in other types',
        () {
      final corpus = _corpus(SearchData(
        requests: [request(id: 'r1', notes: 'asked about ali')],
        offers: [offer(id: 'f1', notes: 'ali')],
        owners: [owner(id: 'o1', name: 'Ali')],
      ));
      expect(_ids(_find(corpus, 'ali')).first, 'o1');
    });

    test('a multi-word query written as a phrase ranks above scattered words',
        () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'scattered', name: 'Marina Dubai Tower'),
        owner(id: 'phrase', name: 'Dubai Marina Tower'),
      ]));
      expect(_ids(_find(corpus, 'dubai marina')), ['phrase', 'scattered']);
    });

    test('equal matches are ordered by type, then title, then id', () {
      final corpus = _corpus(SearchData(
        owners: [
          owner(id: 'o2', name: 'Sam Brown'),
          owner(id: 'o1', name: 'Sam Brown'),
          owner(id: 'o3', name: 'Sam Adams'),
        ],
        offices: [office(id: 'f1', name: 'Sam Brown')],
        brokers: [broker(id: 'b1', name: 'Sam Brown')],
      ));
      // All equal on score; owners before offices before brokers, then by
      // title, then by id.
      expect(_ids(_find(corpus, 'sam brown')), ['o1', 'o2', 'f1', 'b1']);
      // "sam" starts every title equally; "Sam Adams" sorts before "Sam Brown".
      expect(_ids(_find(corpus, 'sam')), ['o3', 'o1', 'o2', 'f1', 'b1']);
    });

    test('the order does not depend on the order the data arrived in', () {
      final owners = [
        for (var i = 0; i < 12; i++) owner(id: 'o$i', name: 'Sam $i'),
      ];
      final offices = [
        for (var i = 0; i < 6; i++) office(id: 'f$i', name: 'Sam office $i'),
      ];
      final brokers = [
        for (var i = 0; i < 6; i++) broker(id: 'b$i', name: 'Samir $i'),
      ];
      final expected = _ids(_find(
        _corpus(SearchData(owners: owners, offices: offices, brokers: brokers)),
        'sam',
      ));
      expect(expected, hasLength(24));
      for (var seed = 1; seed <= 5; seed++) {
        final random = Random(seed);
        final shuffled = _ids(_find(
          _corpus(SearchData(
            owners: [...owners]..shuffle(random),
            offices: [...offices]..shuffle(random),
            brokers: [...brokers]..shuffle(random),
          )),
          'sam',
        ));
        expect(shuffled, expected, reason: 'seed $seed');
      }
    });

    test('searching twice gives the same answer', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'Sam'),
        owner(id: 'o2', name: 'Samir'),
      ]));
      expect(_ids(_find(corpus, 'sam')), _ids(_find(corpus, 'sam')));
    });
  });

  group('the type filter', () {
    final corpus = _corpus(SearchData(
      requests: [request(id: 'r1', city: 'Dubai')],
      offers: [offer(id: 'f1', city: 'Dubai')],
      owners: [owner(id: 'o1', name: 'Dubai Owner')],
      offices: [office(id: 'e1', name: 'Dubai Office')],
      brokers: [broker(id: 'b1', name: 'Dubai Broker')],
      watchmen: [watchman(id: 'w1', name: 'Dubai Guard')],
    ));

    test('without a filter every type is found', () {
      expect(_find(corpus, 'dubai'), hasLength(6));
    });

    test('with a filter only that type is found', () {
      for (final entry in {
        SearchResultType.request: 'r1',
        SearchResultType.offer: 'f1',
        SearchResultType.owner: 'o1',
        SearchResultType.office: 'e1',
        SearchResultType.broker: 'b1',
        SearchResultType.watchmen: 'w1',
      }.entries) {
        final results = _find(corpus, 'dubai', type: entry.key);
        expect(_ids(results), [entry.value], reason: entry.key.name);
        expect(results.single.type, entry.key);
      }
    });

    test('a filter with nothing of that type gives nothing', () {
      final onlyOwners =
          _corpus(SearchData(owners: [owner(id: 'o1', name: 'X')]));
      expect(_find(onlyOwners, 'x', type: SearchResultType.office), isEmpty);
    });
  });

  group('duplicates', () {
    test('the same record twice is one result', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: 'o1', name: 'Sam'),
        owner(id: 'o1', name: 'Sam'),
        owner(id: ' o1 ', name: 'Sam'),
      ]));
      expect(_find(corpus, 'sam'), hasLength(1));
    });

    test('a record matching in several fields is still one result', () {
      final corpus = _corpus(SearchData(owners: [
        owner(
          id: 'o1',
          name: 'Dubai',
          propertyLocation: 'Dubai',
          notes: 'dubai',
        ),
      ]));
      expect(_find(corpus, 'dubai'), hasLength(1));
    });

    test('different types with the same id are different records', () {
      final corpus = _corpus(SearchData(
        owners: [owner(id: 'same', name: 'Sam')],
        offices: [office(id: 'same', name: 'Sam')],
        brokers: [broker(id: 'same', name: 'Sam')],
      ));
      final results = _find(corpus, 'sam');
      expect(results, hasLength(3));
      expect(results.map((r) => r.stableKey).toSet(), hasLength(3));
    });

    test('records with no id are kept, each with a key of its own', () {
      final corpus = _corpus(SearchData(owners: [
        owner(id: null, name: 'Sam One'),
        owner(id: '', name: 'Sam Two'),
        owner(id: '  ', name: 'Sam Three'),
      ]));
      final results = _find(corpus, 'sam');
      expect(results, hasLength(3));
      expect(results.map((r) => r.stableKey).toSet(), hasLength(3));
    });

    test('a result key is its type and id', () {
      final corpus =
          _corpus(SearchData(owners: [owner(id: 'o9', name: 'Sam')]));
      expect(_find(corpus, 'sam').single.stableKey, 'owner:o9');
    });
  });

  group('results', () {
    test('every result carries the query it answers', () {
      final corpus =
          _corpus(SearchData(owners: [owner(id: 'o1', name: 'Sam')]));
      final results = _find(corpus, '  SAM   ');
      expect(results.single.searchQuery, 'SAM');
    });

    test('the answer cannot be changed', () {
      final corpus =
          _corpus(SearchData(owners: [owner(id: 'o1', name: 'Sam')]));
      expect(() => _find(corpus, 'sam').add(_find(corpus, 'sam').first),
          throwsUnsupportedError);
    });

    test('nothing matching gives an empty answer, not an error', () {
      final corpus =
          _corpus(SearchData(owners: [owner(id: 'o1', name: 'Sam')]));
      expect(_find(corpus, 'nobody'), isEmpty);
    });

    test('an empty corpus gives an empty answer', () {
      expect(_find(_corpus(const SearchData()), 'anything'), isEmpty);
      expect(_corpus(const SearchData()).length, 0);
    });

    test('a record with every field empty does not break the index', () {
      final corpus = _corpus(SearchData(
        requests: [request(id: 'r1', city: '')],
        offers: [offer(id: 'o1', city: '')],
        owners: [owner(id: 'w1')],
        offices: [office(id: 'f1')],
        brokers: [broker(id: 'b1')],
        watchmen: [watchman(id: 'm1')],
      ));
      expect(corpus.length, 6);
      expect(_find(corpus, 'x'), isEmpty);
    });
  });
}
