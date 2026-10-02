// The shared UAE area catalog behind the Add Request and Add Offer forms:
// completeness for every supported city, product-priority ordering (never
// alphabetical), stable keys (older records keep working), localization in
// both languages, and that Request and Offer consume this one source.
//
// These are source/data checks. They prove the shape of the catalog and the
// wiring, not how the screens look on a device.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String language) => jsonDecode(
      File('lib/src/common/localization/app_$language.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

/// The area keys the previous per-screen pickers offered, per city. Every one
/// may be stored in an existing Request or Offer, so every one must keep
/// resolving.
const Map<String, List<String>> _previouslyOffered = {
  'Dubai': [
    'jumeirah',
    'alBarsha',
    'deira',
    'karama',
    'mirdif',
    'discoveryGardens',
    'burDubai',
    'jvc',
    'downtownDubai',
    'businessBay',
  ],
  'Abu Dhabi': [
    'alReemIsland',
    'alRahaBeach',
    'khalifaCity',
    'mohammedBinZayedCity',
    'baniyas',
    'alShamkha',
    'alMuroor',
    'alMaqtaa',
    'mussafah',
    'alBateen',
  ],
  'Sharjah': [
    'alNahdaSharjah',
    'muwaileh',
    'alMajaz',
    'alQasimia',
    'alTaawun',
    'abuShagara',
    'alYarmook',
    'alButina',
    'alKhan',
    'alFalah',
  ],
  'Ajman': [
    'alNuaimia',
    'alRashidiya',
    'alRawda',
    'alHelio',
    'alJurf',
    'alHamidiya',
    'alZahra',
    'alMowaihat',
    'emiratesCity',
    'ajmanIndustrialArea',
  ],
  'Ras Al Khaimah': [
    'alDhait',
    'alMairid',
    'alQurm',
    'alNakheel',
    'seihAlUraibi',
    'alJazeeraAlHamra',
    'alRams',
    'alUraibi',
    'alMamourah',
    'khuzam',
  ],
  'Fujairah': [
    'alFaseel',
    'madhab',
    'murbah',
    'qalaatAlFujairah',
    'dibbaFujairah',
    'alGurfa',
    'sakamkam',
    'alTawyeen',
    'dadna',
    'alBidya',
  ],
  'Umm Al Quwain': [
    'alRaafa',
    'alSalama',
    'alRamlah',
    'alMuroorUAQ',
    'alKhorUAQ',
    'alHadarah',
    'alHaditha',
    'falajAlMualla',
    'ummaquwainIndustrialArea',
    'alShabiya',
  ],
  'Al Ain': [
    'alJimi',
    'alAinIndustrialArea',
    'alMuwaiji',
    'alAmeriya',
    'alHili',
    'alMarkhaniya',
    'alYahar',
    'alQattara',
    'alKhabisi',
    'zakhir',
  ],
};

/// The market-prominence anchors each city's list must lead with: every one of
/// these sits inside the first [take] entries, and before every [later] area.
/// (Not every rank position is pinned — ordering is a product judgement.)
class _Priority {
  const _Priority(this.anchors, this.take, this.later);
  final List<String> anchors;
  final int take;
  final List<String> later;
}

const Map<String, _Priority> _priorities = {
  'Dubai': _Priority(
    [
      'dubaiMarina',
      'downtownDubai',
      'businessBay',
      'jvc',
      'dubaiHillsEstate',
      'palmJumeirah',
      'jlt',
      'arabianRanches',
      'dubaiCreekHarbour',
      'jbr',
      'mohammedBinRashidCity',
      'alFurjan',
      'arjan',
      'damacHills',
      'dubaiSouth',
      'townSquare',
    ],
    16,
    ['mirdif', 'deira', 'alQuoz', 'jebelAli', 'horAlAnz'],
  ),
  'Abu Dhabi': _Priority(
    [
      'yasIsland',
      'alReemIsland',
      'saadiyatIsland',
      'alRahaBeach',
      'abuDhabiCorniche',
      'alMaryahIsland',
      'khalifaCity',
      'alReef',
      'mohammedBinZayedCity',
      'masdarCity',
      'alKhalidiyah',
      'touristClubArea',
      'alMushrif',
      'alMuroor',
      'alBateen',
    ],
    17,
    ['alShamkha', 'alWathba', 'mussafah'],
  ),
  'Sharjah': _Priority(
    [
      'aljada',
      'muwailehCommercial',
      'muwaileh',
      'alMajaz',
      'alKhan',
      'alTaawun',
      'alNahdaSharjah',
      'alQasba',
      'alZahia',
      'alRahmaniya',
      'tilalCity',
      'sharjahSustainableCity',
    ],
    14,
    ['alSweihat', 'alBarashi', 'alSajaa'],
  ),
  'Ajman': _Priority(
    [
      'alNuaimia',
      'alRashidiya',
      'alRawda',
      'ajmanDowntown',
      'alYasmeen',
      'alMowaihat',
      'ajmanCorniche',
      'alZorah',
      'alJurf',
      'alZahya',
      'emiratesCity',
    ],
    12,
    ['alOwan', 'alSawan', 'ajmanIndustrialArea'],
  ),
  'Ras Al Khaimah': _Priority(
    [
      'alHamraVillage',
      'alMarjanIsland',
      'minaAlArab',
      'alNakheel',
      'alDhait',
      'alSeer',
      'alMamourah',
      'alMairid',
    ],
    9,
    ['alKharran', 'alJuwais', 'shamal'],
  ),
  'Fujairah': _Priority(
    [
      'sharm',
      'alFaseel',
      'sakamkam',
      'fujairahCityCorniche',
      'alHayl',
      'madhab',
      'merashid',
      'murbah',
      'dibbaFujairah',
      'alAqah',
    ],
    11,
    ['alBithnah', 'masafi', 'thoban'],
  ),
  'Umm Al Quwain': _Priority(
    [
      'uaqOldTown',
      'alSalama',
      'alRamlah',
      'alRaas',
      'alRaudahUAQ',
      'alHumrah',
      'alRiqqah',
      'alMaidan',
    ],
    9,
    ['kingFaisalRoad', 'ummaquwainIndustrialArea'],
  ),
  'Al Ain': _Priority(
    [
      'alJimi',
      'alMuwaiji',
      'alHili',
      'alFoah',
      'alBateenAlAin',
      'alMaqam',
      'alSarooj',
      'alTowayya',
      'alKhabisi',
      'falajHazza',
      'alMutarad',
      'alMutawaa',
      'alMarkhaniya',
      'zakhir',
      'alYahar',
    ],
    17,
    ['sweihan', 'alMasoudi', 'alAmeriya'],
  ),
  'Khor Fakkan': _Priority(
    ['alMudaifi', 'hayawa', 'alKhaledya', 'zubara'],
    5,
    ['wadiShis', 'hatim'],
  ),
};

final RegExp _arabicLetters = RegExp(r'[؀-ۿ]');

String _read(String path) => File(path).readAsStringSync();

void main() {
  final en = _arb('en');
  final ar = _arb('ar');

  group('every supported city has a catalog', () {
    test('the nine supported cities, each with areas', () {
      expect(UaeAreaCatalog.supportedCities, hasLength(9));
      expect(
        UaeAreaCatalog.supportedCities.toSet(),
        {
          'Dubai',
          'Abu Dhabi',
          'Sharjah',
          'Ajman',
          'Ras Al Khaimah',
          'Fujairah',
          'Umm Al Quwain',
          'Al Ain',
          'Khor Fakkan',
        },
      );
      for (final city in UaeAreaCatalog.supportedCities) {
        expect(UaeAreaCatalog.areasFor(city), isNotEmpty, reason: city);
      }
    });

    test('Khor Fakkan, which had no areas before, has a proper list', () {
      final areas = UaeAreaCatalog.areasFor('Khor Fakkan');
      expect(areas.length, greaterThanOrEqualTo(10));
      expect(
        areas,
        containsAll(<String>[
          'alMudaifi',
          'hayawa',
          'alKhaledya',
          'zubara',
          'alHaray',
          'alBurdi',
          'nahwa',
          'wadiShis',
        ]),
      );
    });

    test('the catalog is substantially more complete than the old ten', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        expect(UaeAreaCatalog.areasFor(city).length,
            greaterThanOrEqualTo(city == 'Khor Fakkan' ? 10 : 15),
            reason: city);
      }
      expect(UaeAreaCatalog.areasFor('Dubai').length, greaterThan(60));
    });

    test('an unknown city has no areas rather than throwing', () {
      expect(UaeAreaCatalog.areasFor('Atlantis'), isEmpty);
      expect(UaeAreaCatalog.areasFor(''), isEmpty);
      expect(UaeAreaCatalog.isOffered('Atlantis', 'jvc'), isFalse);
    });

    test('the Request and Offer forms list exactly the supported cities', () {
      final listed = RegExp(r'cities\s*=\s*\[([^\]]*)\]');
      for (final path in const [
        'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      ]) {
        final match = listed.firstMatch(_read(path))!;
        final cities = RegExp(r'"([^"]+)"')
            .allMatches(match.group(1)!)
            .map((m) => m.group(1)!)
            .toSet();
        expect(cities, UaeAreaCatalog.supportedCities.toSet(), reason: path);
      }
    });
  });

  group('stable, unambiguous keys', () {
    test('no duplicate key inside a city, none shared between cities', () {
      final owner = <String, String>{};
      for (final city in UaeAreaCatalog.supportedCities) {
        final areas = UaeAreaCatalog.areasFor(city);
        expect(areas.toSet().length, areas.length, reason: '$city has dupes');
        for (final key in areas) {
          expect(owner.containsKey(key), isFalse,
              reason: '$key is in ${owner[key]} and $city');
          owner[key] = city;
        }
      }
    });

    test('keys are plain camelCase identifiers', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        for (final key in UaeAreaCatalog.areasFor(city)) {
          expect(RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(key), isTrue,
              reason: key);
        }
      }
    });

    test('every key an older picker offered still resolves, in its own city',
        () {
      for (final entry in _previouslyOffered.entries) {
        for (final key in entry.value) {
          expect(UaeAreaCatalog.isSupported(key), isTrue,
              reason: '${entry.key}: $key');
          final stillOffered = UaeAreaCatalog.isOffered(entry.key, key);
          final legacy =
              (UaeAreaCatalog.legacyOnlyAreas[entry.key] ?? const <String>[])
                  .contains(key);
          expect(stillOffered || legacy, isTrue,
              reason: '${entry.key}: $key was dropped without being kept');
        }
      }
    });

    test('keys no longer offered are legacy-only and never also offered', () {
      for (final entry in UaeAreaCatalog.legacyOnlyAreas.entries) {
        for (final key in entry.value) {
          expect(UaeAreaCatalog.isSupported(key), isTrue);
          expect(UaeAreaCatalog.isOffered(entry.key, key), isFalse,
              reason: '$key is both legacy-only and offered');
        }
      }
    });

    test('a key nobody ever offered is not "supported"', () {
      expect(UaeAreaCatalog.isSupported('definitelyNotAnArea'), isFalse);
      expect(UaeAreaCatalog.isSupported(''), isFalse);
    });
  });

  group('priority ordering', () {
    for (final entry in _priorities.entries) {
      test('${entry.key} leads with its highest-prominence areas', () {
        final areas = UaeAreaCatalog.areasFor(entry.key);
        final head = areas.take(entry.value.take).toList();
        expect(head, containsAll(entry.value.anchors),
            reason: '${entry.key}: an anchor fell out of the first '
                '${entry.value.take}');
        for (final later in entry.value.later) {
          expect(areas, contains(later), reason: later);
          final laterIndex = areas.indexOf(later);
          for (final anchor in entry.value.anchors) {
            expect(areas.indexOf(anchor), lessThan(laterIndex),
                reason: '$anchor must rank above $later in ${entry.key}');
          }
        }
      });
    }

    test('the order is a priority order, not alphabetical', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final areas = UaeAreaCatalog.areasFor(city);
        final labels = areas.map((k) => (en[k] as String).toLowerCase());
        final sorted = labels.toList()..sort();
        expect(labels.toList(), isNot(orderedEquals(sorted)),
            reason: '$city is alphabetical');
      }
    });

    test('Dubai spot checks that guard against a re-sort', () {
      final dubai = UaeAreaCatalog.areasFor('Dubai');
      expect(dubai.first, 'dubaiMarina');
      expect(dubai.indexOf('dubaiMarina'), lessThan(dubai.indexOf('alBarsha')));
      expect(dubai.indexOf('palmJumeirah'), lessThan(dubai.indexOf('deira')));
      expect(dubai.indexOf('jvc'), lessThan(dubai.indexOf('burDubai')));
    });
  });

  group('localization', () {
    List<String> everyKey() => [
          for (final city in UaeAreaCatalog.supportedCities)
            ...UaeAreaCatalog.areasFor(city),
          for (final keys in UaeAreaCatalog.legacyOnlyAreas.values) ...keys,
        ];

    test('every area key has English and Arabic text', () {
      for (final key in everyKey()) {
        expect((en[key] as String?)?.trim(), isNotEmpty, reason: 'en $key');
        expect((ar[key] as String?)?.trim(), isNotEmpty, reason: 'ar $key');
      }
    });

    test('no camelCase key or placeholder can reach the user', () {
      for (final key in everyKey()) {
        final label = en[key] as String;
        expect(label, isNot(key), reason: key);
        expect(label, isNot(contains('undefined')), reason: key);
        expect(label.startsWith('** '), isFalse, reason: key);
        expect(RegExp(r'^[A-Z0-9]').hasMatch(label), isTrue,
            reason: '$key reads "$label"');
      }
    });

    test('the Arabic names are Arabic text', () {
      for (final key in everyKey()) {
        expect(_arabicLetters.hasMatch(ar[key] as String), isTrue,
            reason: 'ar $key');
      }
    });

    test('two areas of one city never share an English name', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final seen = <String, String>{};
        for (final key in UaeAreaCatalog.areasFor(city)) {
          final label = en[key] as String;
          expect(seen.containsKey(label), isFalse,
              reason: '$city: "$label" is both ${seen[label]} and $key');
          seen[label] = key;
        }
      }
    });

    test('the Show more / Show less labels exist in both languages', () {
      for (final key in const ['showMore', 'showLess']) {
        expect((en[key] as String?)?.trim(), isNotEmpty, reason: 'en $key');
        expect((ar[key] as String?)?.trim(), isNotEmpty, reason: 'ar $key');
        expect(ar[key], isNot(en[key]), reason: '$key is translated');
        expect(_arabicLetters.hasMatch(ar[key] as String), isTrue);
      }
      expect(en['showMore'], 'Show more');
      expect(en['showLess'], 'Show less');
      expect(ar['showMore'], 'عرض المزيد');
      expect(ar['showLess'], 'عرض أقل');
    });
  });

  group('Request and Offer share one catalog and one component', () {
    const requestView = 'lib/src/views/Screens/ViewAdd/add_requested_view.dart';
    const offerView = 'lib/src/views/Screens/ViewAdd/add_offers_view.dart';
    const widgetFile = 'lib/src/views/Widgets/expandable_area_chips.dart';

    test('both screens use the shared expandable widget', () {
      for (final path in const [requestView, offerView]) {
        final source = _read(path);
        expect(source.contains('expandable_area_chips.dart'), isTrue,
            reason: path);
        expect(source.contains('ExpandableAreaChips('), isTrue, reason: path);
        expect(source.contains('selectedAreas: vm.selectedAreas'), isTrue,
            reason: path);
        expect(source.contains('onToggleArea: vm.selectArea'), isTrue,
            reason: path);
      }
    });

    test('neither screen keeps a private per-city area list', () {
      for (final path in const [requestView, offerView]) {
        final source = _read(path);
        expect(source.contains('_getResidentialAreas'), isFalse, reason: path);
        for (final key in const ['"alBarsha"', '"alReemIsland"', '"alJimi"']) {
          expect(source.contains(key), isFalse,
              reason: '$path still hard-codes $key');
        }
      }
    });

    test('nothing in lib still defines a per-screen area switch', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('_getResidentialAreas'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });

    test('the widget takes its areas from the one catalog', () {
      final source = _read(widgetFile);
      expect(source.contains('UaeAreaCatalog.areasFor('), isTrue);
      expect(source.contains('uae_area_catalog.dart'), isTrue);
    });

    test('the selection rule is unchanged: at most three areas', () {
      for (final path in const [
        'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      ]) {
        expect(_read(path).contains('selectedAreas.length < 3'), isTrue,
            reason: path);
      }
    });
  });
}
