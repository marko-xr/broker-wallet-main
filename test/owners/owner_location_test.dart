// Owner property location on the shared UAE catalog.
//
// An Owner has ONE location, stored as a single free-text value. Choosing a
// city and area from the shared catalog writes `Area, City` into that text and
// reads it back on edit; older, free-typed locations are left exactly as they
// are. These tests cover: the codec that does the writing and reading, the
// Owner view-model's single-choice behaviour, the shared city/area picker as the
// Owner uses it (three rows, Show more/less, replace-on-select, reset on city
// change, English and Arabic/RTL), edit mode, legacy values, and that Request,
// Offer and Owner share one catalog and one component.
//
// Local tests. The screen's own text field is private, so the form here wires a
// stand-in field and the real picker to the real view-model exactly as the
// screen does.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_owners_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';
import 'package:broker_wallet/src/views/Widgets/uae_city_area_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

/// A codec that reads the ARB files straight from disk, independent of
/// [AppLocalizations]' own cache.
late final OwnerLocationCodec codec;

String? _lookup(String language, String key) {
  final table = language == 'en'
      ? en
      : language == 'ar'
          ? ar
          : const <String, dynamic>{};
  return table[key] as String?;
}

OwnerModel _owner({String location = ''}) => OwnerModel(
      id: 'o1',
      userId: '',
      name: 'Owner',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: '',
      propertyLocation: location,
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrl: null,
      mediaUrls: const [],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

/// The real Owner view-model, in add mode or (with [saved]) edit mode.
AddOwnersViewModel _vm({String? saved, OwnerLocationCodec? withCodec}) {
  final edit = saved != null;
  final vm = AddOwnersViewModel(
    mode: edit ? AddOwnersMode.edit : AddOwnersMode.add,
    ownerId: edit ? 'o1' : null,
    ownerData: edit ? _owner(location: saved) : null,
    ownerService: OwnerService(),
    usesMediaQueue: false,
    locationCodec: withCodec ?? codec,
  );
  addTearDown(vm.dispose);
  return vm;
}

/// Mirrors the screen's location text field: its controller follows the
/// view-model's text, and typing reports back to the view-model.
class _SyncedField extends StatefulWidget {
  const _SyncedField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<_SyncedField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_SyncedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(controller: _controller, onChanged: widget.onChanged);
}

/// The Owner form's location section: the shared picker, wired to the
/// view-model as the screen wires it, above the text field.
class _Form extends StatelessWidget {
  const _Form({required this.vm});

  final AddOwnersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final language = localization.locale.languageCode;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UaeCityAreaPicker(
              cities: vm.locationCities,
              selectedCity: vm.locationCity,
              onCityChanged: (city) => vm.selectLocationCity(city, language),
              selectedAreas: vm.locationAreaKeys,
              onToggleArea: (areaKey) =>
                  vm.toggleLocationArea(areaKey, language),
              maxSelectedAreas: 1,
              localization: localization,
            ),
            const SizedBox(height: 12),
            _SyncedField(
              value: vm.propertyLocation,
              onChanged: vm.setPropertyLocation,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  AddOwnersViewModel vm, {
  Locale locale = const Locale('en'),
  double width = 360,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: inner ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(body: _Form(vm: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cityChip(String city) =>
    find.byKey(ValueKey<String>('city-chip-$city'));

Finder _areaChip(String areaKey) =>
    find.byKey(ValueKey<String>('area-chip-$areaKey'));

Finder _areaChips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('area-chip-');
    });

Finder _cityChips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('city-chip-');
    });

const _toggle = ValueKey<String>('area-chips-toggle');
const _pill = ValueKey<String>('city-pill');
const _pillClear = ValueKey<String>('city-pill-clear');

bool _selected(WidgetTester tester, String areaKey) =>
    tester.widget<SelectableChip>(_areaChip(areaKey)).isSelected;

List<String> _areaKeysShown() => _areaChips()
    .evaluate()
    .map((e) => (e.widget.key! as ValueKey<String>).value)
    .map((k) => k.replaceFirst('area-chip-', ''))
    .toList();

/// How many visual rows the area chips occupy: distinct top edges.
int _areaRows(WidgetTester tester) {
  final finder = _areaChips();
  final tops = <int>{};
  for (var i = 0; i < finder.evaluate().length; i++) {
    tops.add((tester.getTopLeft(finder.at(i)).dy * 10).round());
  }
  return tops.length;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Serve the ARB files from disk so the tests assert on the real strings.
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    codec = OwnerLocationCodec(lookup: _lookup);
  });

  group('the Owner uses the one shared catalog', () {
    test('the Owner offers exactly the nine supported cities', () {
      final vm = _vm();
      expect(vm.locationCities, same(UaeAreaCatalog.supportedCities));
      expect(vm.locationCities, hasLength(9));
      expect(
        vm.locationCities.toSet(),
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
    });

    test('Request and Offer offer the same cities', () {
      final listed = RegExp(r'cities\s*=\s*\[([^\]]*)\]');
      for (final path in const [
        'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      ]) {
        final cities = RegExp(r'"([^"]+)"')
            .allMatches(listed.firstMatch(_read(path))!.group(1)!)
            .map((m) => m.group(1)!)
            .toSet();
        expect(cities, UaeAreaCatalog.supportedCities.toSet(), reason: path);
      }
    });

    test('every city has a localized name and its areas', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        final key = UaeAreaCatalog.cityKey(city);
        expect(key, isNot(city), reason: '$city has its own localization key');
        expect((en[key] as String?)?.trim(), isNotEmpty, reason: 'en $city');
        expect((ar[key] as String?)?.trim(), isNotEmpty, reason: 'ar $city');
        expect(UaeAreaCatalog.areasFor(city), isNotEmpty, reason: city);
      }
      expect(UaeAreaCatalog.areasFor('Khor Fakkan'), contains('alMudaifi'));
    });

    test('an area belongs to exactly its own city', () {
      expect(UaeAreaCatalog.isAreaOf('Dubai', 'dubaiMarina'), isTrue);
      expect(UaeAreaCatalog.isAreaOf('Sharjah', 'dubaiMarina'), isFalse);
      expect(UaeAreaCatalog.isAreaOf('Dubai', 'notAnArea'), isFalse);
      expect(UaeAreaCatalog.isAreaOf('Atlantis', 'dubaiMarina'), isFalse);
      // An area an older picker offered and the catalog dropped still belongs
      // to its city.
      expect(UaeAreaCatalog.isAreaOf('Umm Al Quwain', 'alShabiya'), isTrue);
      expect(UaeAreaCatalog.isAreaOf('Fujairah', 'alShabiya'), isFalse);
    });

    test('the Owner screen uses the shared picker, not a list of its own', () {
      final screen =
          _read('lib/src/views/Screens/ViewAdd/add_owners_view.dart');
      expect(screen.contains('uae_city_area_picker.dart'), isTrue);
      expect(screen.contains('UaeCityAreaPicker('), isTrue);
      expect(screen.contains('cities: vm.locationCities'), isTrue);
      expect(screen.contains('maxSelectedAreas: 1'), isTrue,
          reason: 'an Owner has one location, not Request\'s three');
      expect(screen.contains('_getResidentialAreas'), isFalse);
      expect(screen.contains('ExpandableAreaChips'), isFalse,
          reason: 'the picker composes the shared widget; the screen does not');
    });

    test('the shared picker composes the one shared area widget', () {
      final picker = _read('lib/src/views/Widgets/uae_city_area_picker.dart');
      expect(picker.contains('ExpandableAreaChips('), isTrue);
      expect(picker.contains('UaeAreaCatalog.cityKey('), isTrue);
    });

    test('no Owner file holds an area list or an area key of its own', () {
      final files = <String>[
        'lib/src/views/Screens/ViewAdd/add_owners_view.dart',
        'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart',
        'lib/src/views/Widgets/uae_city_area_picker.dart',
        'lib/src/common/data/owner_location_codec.dart',
      ];
      final everyKey = <String>{
        for (final city in UaeAreaCatalog.supportedCities)
          ...UaeAreaCatalog.areasFor(city),
        for (final keys in UaeAreaCatalog.legacyOnlyAreas.values) ...keys,
      };
      for (final path in files) {
        final source = _read(path);
        for (final key in everyKey) {
          expect(
              source.contains("'$key'") || source.contains('"$key"'), isFalse,
              reason: '$path hard-codes the area key $key');
        }
      }
    });

    test('exactly one file defines the per-city area lists', () {
      final owners = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) {
            final source = f.readAsStringSync();
            return source.contains("'dubaiHillsEstate'") ||
                source.contains("'yasIsland'") ||
                source.contains("'alMudaifi'") ||
                source.contains("'aljada'");
          })
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      expect(owners, ['lib/src/common/data/uae_area_catalog.dart']);
    });

    test('Request, Offer and Owner all reach the catalog', () {
      for (final path in const [
        'lib/src/views/Screens/ViewAdd/add_requested_view.dart',
        'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
      ]) {
        expect(_read(path).contains('ExpandableAreaChips('), isTrue,
            reason: path);
      }
      expect(
        _read('lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart')
            .contains('UaeAreaCatalog.'),
        isTrue,
      );
    });

    test('Request and Offer still allow three areas, Owner one', () {
      for (final path in const [
        'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
        'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      ]) {
        expect(_read(path).contains('selectedAreas.length < 3'), isTrue,
            reason: path);
      }
      final vm = _vm();
      vm.selectLocationCity('Dubai', 'en');
      vm.toggleLocationArea('dubaiMarina', 'en');
      vm.toggleLocationArea('palmJumeirah', 'en');
      expect(vm.locationAreaKeys, ['palmJumeirah']);
    });
  });

  group('the codec', () {
    test('every city and area survives writing and reading, both languages',
        () {
      for (final language in const ['en', 'ar']) {
        for (final city in UaeAreaCatalog.supportedCities) {
          final cityOnly = codec.decode(
            codec.encode(city: city, language: language),
          );
          expect(cityOnly?.city, city, reason: '$city/$language');
          expect(cityOnly?.areaKey, isNull);
          expect(cityOnly?.detail, isEmpty);

          final areaKeys = <String>[
            ...UaeAreaCatalog.areasFor(city),
            ...?UaeAreaCatalog.legacyOnlyAreas[city],
          ];
          for (final areaKey in areaKeys) {
            final text = codec.encode(
              city: city,
              areaKey: areaKey,
              language: language,
            );
            final parts = codec.decode(text);
            expect(parts?.city, city, reason: '"$text"');
            expect(parts?.areaKey, areaKey, reason: '"$text"');
            expect(parts?.detail, isEmpty, reason: '"$text"');

            final withDetail = codec.encode(
              city: city,
              areaKey: areaKey,
              language: language,
              detail: 'Villa 12',
            );
            expect(codec.decode(withDetail)?.areaKey, areaKey);
            expect(codec.decode(withDetail)?.detail, 'Villa 12');
            expect(
              codec.detailOf(withDetail, city: city, areaKey: areaKey),
              'Villa 12',
            );
          }
        }
      }
    });

    test('a location is plain readable text, area first', () {
      expect(
        codec.encode(city: 'Dubai', areaKey: 'dubaiMarina', language: 'en'),
        'Dubai Marina, Dubai',
      );
      expect(codec.encode(city: 'Sharjah', language: 'en'), 'Sharjah');
      expect(
        codec.encode(city: 'Dubai', areaKey: 'dubaiMarina', language: 'ar'),
        '${ar['dubaiMarina']}, ${ar['dubai']}',
      );
      expect(
        codec.encode(
          city: 'Ajman',
          areaKey: 'alZorah',
          language: 'en',
          detail: 'Villa 3',
        ),
        'Al Zorah, Ajman, Villa 3',
      );
    });

    test('no two choices write the same text, so reading is never ambiguous',
        () {
      final seen = <String, String>{};
      for (final language in const ['en', 'ar']) {
        for (final city in UaeAreaCatalog.supportedCities) {
          final areaKeys = <String>[
            ...UaeAreaCatalog.areasFor(city),
            ...?UaeAreaCatalog.legacyOnlyAreas[city],
          ];
          for (final areaKey in <String?>[null, ...areaKeys]) {
            final text = codec
                .encode(city: city, areaKey: areaKey, language: language)
                .toLowerCase();
            final who = '$city/$areaKey';
            expect(seen[text] == null || seen[text] == who, isTrue,
                reason: '"$text" is both ${seen[text]} and $who');
            seen[text] = who;
          }
        }
      }
    });

    test('a name never contains the comma that separates the parts', () {
      for (final city in UaeAreaCatalog.supportedCities) {
        for (final key in <String>[
          UaeAreaCatalog.cityKey(city),
          ...UaeAreaCatalog.areasFor(city),
          ...?UaeAreaCatalog.legacyOnlyAreas[city],
        ]) {
          for (final table in [en, ar]) {
            final label = table[key] as String;
            expect(label.contains(',') || label.contains('،'), isFalse,
                reason: '$key: "$label"');
          }
        }
      }
    });

    test('Arabic text is read back in an English app, and the reverse', () {
      final arabic = codec.encode(
        city: 'Dubai',
        areaKey: 'dubaiHillsEstate',
        language: 'ar',
        detail: 'x',
      );
      expect(codec.decode(arabic)?.areaKey, 'dubaiHillsEstate');
      expect(
        codec.detailOf(arabic, city: 'Dubai', areaKey: 'dubaiHillsEstate'),
        'x',
      );
    });

    test('text that is not a choice is never mistaken for one', () {
      for (final custom in const [
        '',
        '   ',
        'Dubai Marina',
        'Dubai Marinas, Dubai',
        'Dubaiville',
        'Near the old souk',
        'Marina Gate, Dubai',
        'Dubai Marina, Sharjah',
        'Dubai Marina،Dubai',
      ]) {
        expect(codec.decode(custom), isNull, reason: '"$custom"');
      }
    });

    test(
        'reading ignores case and spacing around the comma and finds the '
        'detail', () {
      for (final spaced in const [
        ' dubai marina, DUBAI, near the metro ',
        'Dubai Marina, Dubai , near the metro',
        'DUBAI MARINA, dubai ,   near the metro',
      ]) {
        final parts = codec.decode(spaced);
        expect(parts?.city, 'Dubai', reason: '"$spaced"');
        expect(parts?.areaKey, 'dubaiMarina', reason: '"$spaced"');
        expect(parts?.detail, 'near the metro', reason: '"$spaced"');
      }
      final cityThenWords = codec.decode('Dubai, Palm Jumeirah');
      expect(cityThenWords?.city, 'Dubai');
      expect(cityThenWords?.areaKey, isNull);
      expect(cityThenWords?.detail, 'Palm Jumeirah');
    });

    test('same-named areas of different cities stay apart', () {
      expect(codec.decode('Al Nahda, Dubai')?.areaKey, 'alNahdaDubai');
      expect(codec.decode('Al Nahda, Sharjah')?.areaKey, 'alNahdaSharjah');
      expect(codec.decode('Al Ain Industrial Area, Al Ain')?.areaKey,
          'alAinIndustrialArea');
      expect(codec.decode('Al Ain')?.areaKey, isNull);
    });

    test('a language that is not loaded never matches and never throws', () {
      final englishOnly = OwnerLocationCodec(
        lookup: (language, key) => language == 'en' ? en[key] as String? : null,
      );
      expect(englishOnly.decode('Dubai Marina, Dubai')?.areaKey, 'dubaiMarina');
      expect(
          englishOnly.decode('${ar['dubaiMarina']}, ${ar['dubai']}'), isNull);
      expect(
        englishOnly.encode(
            city: 'Dubai', areaKey: 'dubaiMarina', language: 'ar'),
        'Dubai Marina, Dubai',
        reason: 'writing falls back to English rather than showing a key',
      );
    });

    test('the default codec reads the app\'s preloaded languages', () {
      final appCodec = OwnerLocationCodec();
      expect(appCodec.decode('Yas Island, Abu Dhabi')?.areaKey, 'yasIsland');
      expect(
        appCodec.decode('${ar['yasIsland']}, ${ar['abuDhabi']}, x')?.detail,
        'x',
      );
    });
  });

  group('the Owner view-model: one city, one area', () {
    test('choosing a city and an area writes plain text', () {
      final vm = _vm();
      var notified = 0;
      vm.addListener(() => notified++);

      vm.selectLocationCity('Dubai', 'en');
      expect(vm.propertyLocation, 'Dubai');
      expect(vm.locationCity, 'Dubai');
      expect(vm.locationAreaKeys, isEmpty);

      vm.toggleLocationArea('dubaiMarina', 'en');
      expect(vm.propertyLocation, 'Dubai Marina, Dubai');
      expect(vm.locationAreaKeys, ['dubaiMarina']);
      expect(notified, 2);
      expect(vm.hasAnyContent, isTrue, reason: 'Save becomes available');
    });

    test('another area REPLACES the first: never more than one', () {
      final vm = _vm();
      vm.selectLocationCity('Dubai', 'en');
      vm.toggleLocationArea('dubaiMarina', 'en');
      vm.toggleLocationArea('downtownDubai', 'en');
      vm.toggleLocationArea('businessBay', 'en');

      expect(vm.locationAreaKeys, ['businessBay']);
      expect(vm.propertyLocation, 'Business Bay, Dubai');
    });

    test('choosing the chosen area again clears it, keeping the city', () {
      final vm = _vm();
      vm.selectLocationCity('Dubai', 'en');
      vm.toggleLocationArea('dubaiMarina', 'en');
      vm.toggleLocationArea('dubaiMarina', 'en');

      expect(vm.locationAreaKeys, isEmpty);
      expect(vm.locationCity, 'Dubai');
      expect(vm.propertyLocation, 'Dubai');
    });

    test('changing the city clears the area and never keeps it in the text',
        () {
      final vm = _vm();
      vm.selectLocationCity('Sharjah', 'en');
      vm.toggleLocationArea('aljada', 'en');
      expect(vm.propertyLocation, 'Aljada, Sharjah');

      vm.selectLocationCity('', 'en'); // the pill's clear button
      expect(vm.locationCity, isEmpty);
      expect(vm.locationAreaKeys, isEmpty);
      expect(vm.propertyLocation, isEmpty);

      vm.selectLocationCity('Ajman', 'en');
      expect(vm.locationCity, 'Ajman');
      expect(vm.locationAreaKeys, isEmpty);
      expect(vm.propertyLocation, 'Ajman');
      expect(vm.propertyLocation.contains('Aljada'), isFalse);
    });

    test(
        'an area of another city, an unknown area and an unknown city are '
        'refused', () {
      final vm = _vm();
      vm.selectLocationCity('Ajman', 'en');

      vm.toggleLocationArea('dubaiMarina', 'en');
      vm.toggleLocationArea('notAnArea', 'en');
      expect(vm.locationAreaKeys, isEmpty);
      expect(vm.propertyLocation, 'Ajman');

      vm.selectLocationCity('Atlantis', 'en');
      expect(vm.locationCity, 'Ajman');
    });

    test('an area cannot be chosen before a city', () {
      final vm = _vm();
      vm.toggleLocationArea('dubaiMarina', 'en');
      expect(vm.locationAreaKeys, isEmpty);
      expect(vm.propertyLocation, isEmpty);
    });

    test('words the owner adds after the choice stay when the choice changes',
        () {
      final vm = _vm();
      vm.selectLocationCity('Dubai', 'en');
      vm.toggleLocationArea('dubaiMarina', 'en');
      vm.setPropertyLocation('${vm.propertyLocation}, Marina Gate tower 2');

      expect(vm.locationCity, 'Dubai', reason: 'appending keeps the chips');
      expect(vm.locationAreaKeys, ['dubaiMarina']);

      vm.toggleLocationArea('palmJumeirah', 'en');
      expect(vm.propertyLocation, 'Palm Jumeirah, Dubai, Marina Gate tower 2');

      vm.selectLocationCity('', 'en');
      expect(vm.propertyLocation, 'Marina Gate tower 2',
          reason: 'clearing removes the choice, not the owner\'s own words');
    });

    test('typing never creates a choice, and clears one the text stops saying',
        () {
      final typed = _vm();
      for (final ch in 'Dubai Marina, Tower 5'.split('')) {
        typed.setPropertyLocation('${typed.propertyLocation}$ch');
      }
      expect(typed.locationCity, isEmpty);
      expect(typed.locationAreaKeys, isEmpty);
      expect(typed.propertyLocation, 'Dubai Marina, Tower 5');

      final broken = _vm();
      broken.selectLocationCity('Dubai', 'en');
      broken.toggleLocationArea('dubaiMarina', 'en');
      broken.setPropertyLocation('Dubai Marina, Duba');
      expect(broken.locationCity, isEmpty);
      expect(broken.locationAreaKeys, isEmpty);
      expect(broken.propertyLocation, 'Dubai Marina, Duba',
          reason: 'the text itself is untouched');

      final cleared = _vm();
      cleared.selectLocationCity('Dubai', 'en');
      cleared.setPropertyLocation('');
      expect(cleared.locationCity, isEmpty);

      final wordAfterCity = _vm();
      wordAfterCity.selectLocationCity('Dubai', 'en');
      wordAfterCity.setPropertyLocation('Dubai Marina');
      expect(wordAfterCity.locationCity, isEmpty);
    });

    test('with nothing chosen, clearing leaves the owner\'s own text alone',
        () {
      final vm = _vm(saved: 'Near the old souk');
      vm.selectLocationCity('', 'en');
      expect(vm.propertyLocation, 'Near the old souk');
    });

    test('a choice replaces custom text, and the text is then the choice', () {
      final vm = _vm(saved: 'Near the old souk');
      vm.selectLocationCity('Sharjah', 'en');
      expect(vm.propertyLocation, 'Sharjah');
      expect(vm.locationCity, 'Sharjah');
    });

    test('the text is written in the language in use', () {
      final vm = _vm();
      vm.selectLocationCity('Dubai', 'ar');
      vm.toggleLocationArea('dubaiMarina', 'ar');
      expect(vm.propertyLocation, '${ar['dubaiMarina']}, ${ar['dubai']}');

      // Reopened in English, the same text still shows the same choice and an
      // edit is written in English.
      final reopened = _vm(saved: vm.propertyLocation);
      expect(reopened.locationCity, 'Dubai');
      expect(reopened.locationAreaKeys, ['dubaiMarina']);
      reopened.toggleLocationArea('downtownDubai', 'en');
      expect(reopened.propertyLocation, 'Downtown Dubai, Dubai');
    });
  });

  group('edit mode', () {
    test('a saved city and area are restored, the text is not rewritten', () {
      final vm = _vm(saved: 'Dubai Marina, Dubai');
      expect(vm.locationCity, 'Dubai');
      expect(vm.locationAreaKeys, ['dubaiMarina']);
      expect(vm.propertyLocation, 'Dubai Marina, Dubai');
    });

    test('city only, area with a detail, and a different city all restore', () {
      final cityOnly = _vm(saved: 'Dubai');
      expect(cityOnly.locationCity, 'Dubai');
      expect(cityOnly.locationAreaKeys, isEmpty);

      final withDetail = _vm(saved: 'Yas Island, Abu Dhabi, villa 7');
      expect(withDetail.locationCity, 'Abu Dhabi');
      expect(withDetail.locationAreaKeys, ['yasIsland']);
      expect(withDetail.propertyLocation, 'Yas Island, Abu Dhabi, villa 7');

      final khorFakkan = _vm(saved: 'Al Mudaifi, Khor Fakkan');
      expect(khorFakkan.locationCity, 'Khor Fakkan');
      expect(khorFakkan.locationAreaKeys, ['alMudaifi']);
    });

    test('an area far down the catalog is restored', () {
      final dubai = UaeAreaCatalog.areasFor('Dubai');
      expect(dubai.indexOf('horAlAnz'), greaterThan(60));
      final vm = _vm(saved: 'Hor Al Anz, Dubai');
      expect(vm.locationCity, 'Dubai');
      expect(vm.locationAreaKeys, ['horAlAnz']);
    });

    test('an area an older picker offered still restores', () {
      expect(UaeAreaCatalog.isOffered('Umm Al Quwain', 'alShabiya'), isFalse);
      final vm = _vm(saved: 'Al Shabiya, Umm Al Quwain');
      expect(vm.locationCity, 'Umm Al Quwain');
      expect(vm.locationAreaKeys, ['alShabiya']);
    });

    test('a location the owner typed is kept exactly and shows no choice', () {
      for (final typed in const [
        'Near the old souk',
        'Palm Jumeirah Frond K, Dubai',
        'Dubai Marina',
        'جميرا بالقرب من الشاطئ',
      ]) {
        final vm = _vm(saved: typed);
        expect(vm.locationCity, isEmpty, reason: typed);
        expect(vm.locationAreaKeys, isEmpty, reason: typed);
        expect(vm.propertyLocation, typed, reason: 'never normalized');
        vm.setPropertyLocation(vm.propertyLocation);
        expect(vm.propertyLocation, typed);
      }
    });

    test('an empty saved location shows no choice', () {
      final vm = _vm(saved: '');
      expect(vm.locationCity, isEmpty);
      expect(vm.propertyLocation, isEmpty);
    });

    test('the app\'s own codec restores a saved choice too', () {
      final vm = AddOwnersViewModel(
        mode: AddOwnersMode.edit,
        ownerId: 'o1',
        ownerData: _owner(location: 'Al Reef, Abu Dhabi'),
        ownerService: OwnerService(),
        usesMediaQueue: false,
      );
      addTearDown(vm.dispose);
      expect(vm.locationCity, 'Abu Dhabi');
      expect(vm.locationAreaKeys, ['alReef']);
    });
  });

  group('the shared picker as the Owner uses it', () {
    testWidgets('all nine cities are offered, with localized names',
        (tester) async {
      await _pump(tester, _vm());

      expect(_cityChips(), findsNWidgets(9));
      for (final city in UaeAreaCatalog.supportedCities) {
        expect(_cityChip(city), findsOneWidget, reason: city);
        expect(find.text(en[UaeAreaCatalog.cityKey(city)] as String),
            findsOneWidget,
            reason: city);
      }
      expect(_areaChips(), findsNothing,
          reason: 'areas appear once a city is chosen');
    });

    testWidgets('choosing Khor Fakkan shows its own areas', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await _tap(tester, _cityChip('Khor Fakkan'));

      expect(vm.locationCity, 'Khor Fakkan');
      expect(find.byKey(_pill), findsOneWidget);
      expect(_areaChip('alMudaifi'), findsOneWidget);
      expect(find.text(en['alMudaifi'] as String), findsOneWidget);
      expect(_cityChips(), findsNothing);
    });

    testWidgets(
        'the areas come in the catalog\'s priority order, three rows '
        'collapsed', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));

      final dubai = UaeAreaCatalog.areasFor('Dubai');
      final shown = _areaKeysShown();
      expect(shown, isNotEmpty);
      expect(shown.length, lessThan(dubai.length));
      expect(shown, dubai.take(shown.length).toList(),
          reason: 'the order is the catalog\'s, never re-sorted');
      expect(shown.first, 'dubaiMarina');
      expect(_areaRows(tester), 3);
      expect(find.text(en['showMore'] as String), findsOneWidget);
    });

    testWidgets('Show more reveals every area, Show less collapses again',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));
      final collapsed = _areaChips().evaluate().length;

      await _tap(tester, find.byKey(_toggle));
      expect(
          _areaChips(), findsNWidgets(UaeAreaCatalog.areasFor('Dubai').length));
      expect(find.text(en['showLess'] as String), findsOneWidget);

      await _tap(tester, find.byKey(_toggle));
      expect(_areaChips(), findsNWidgets(collapsed));
      expect(_areaRows(tester), 3);
      expect(find.text(en['showMore'] as String), findsOneWidget);
    });

    testWidgets('a narrow screen still shows exactly three rows',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm, width: 320);
      await _tap(tester, _cityChip('Abu Dhabi'));

      expect(_areaRows(tester), 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing an area writes it into the text field',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await _tap(tester, _cityChip('Dubai'));
      expect(_fieldText(tester), 'Dubai');
      await _tap(tester, _areaChip('dubaiMarina'));

      expect(vm.locationAreaKeys, ['dubaiMarina']);
      expect(_fieldText(tester), 'Dubai Marina, Dubai');
      expect(_selected(tester, 'dubaiMarina'), isTrue);
    });

    testWidgets('a second area replaces the first and no chip is dimmed',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));

      await _tap(tester, _areaChip('dubaiMarina'));
      for (final key in _areaKeysShown()) {
        expect(tester.widget<SelectableChip>(_areaChip(key)).isEnabled, isTrue,
            reason: '$key must stay tappable: one location, replace on select');
      }

      await _tap(tester, _areaChip('downtownDubai'));
      expect(vm.locationAreaKeys, ['downtownDubai']);
      expect(_fieldText(tester), 'Downtown Dubai, Dubai');
      expect(_selected(tester, 'downtownDubai'), isTrue);
      expect(_selected(tester, 'dubaiMarina'), isFalse);
    });

    testWidgets('tapping the chosen area clears it', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));
      await _tap(tester, _areaChip('dubaiMarina'));
      await _tap(tester, _areaChip('dubaiMarina'));

      expect(vm.locationAreaKeys, isEmpty);
      expect(_fieldText(tester), 'Dubai');
      expect(_selected(tester, 'dubaiMarina'), isFalse);
    });

    testWidgets(
        'changing the city starts over: collapsed, new areas, no old '
        'area', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));
      await _tap(tester, find.byKey(_toggle)); // expand Dubai
      await _tap(tester, _areaChip('dubaiMarina'));

      await _tap(tester, find.byKey(_pillClear));
      expect(vm.locationCity, isEmpty);
      expect(vm.locationAreaKeys, isEmpty);
      expect(_fieldText(tester), isEmpty);
      expect(_cityChips(), findsNWidgets(9));
      expect(_areaChips(), findsNothing);

      await _tap(tester, _cityChip('Sharjah'));
      final sharjah = UaeAreaCatalog.areasFor('Sharjah');
      expect(vm.locationCity, 'Sharjah');
      expect(_fieldText(tester), 'Sharjah');
      expect(find.text(en['showMore'] as String), findsOneWidget,
          reason: 'the new city starts collapsed');
      expect(_areaKeysShown().first, sharjah.first);
      expect(_areaChip('dubaiMarina'), findsNothing);
      expect(_areaRows(tester), 3);
      for (final key in _areaKeysShown()) {
        expect(_selected(tester, key), isFalse, reason: key);
      }
    });

    testWidgets(
        'typing detail after the choice keeps it; custom text clears it',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tap(tester, _cityChip('Dubai'));
      await _tap(tester, _areaChip('dubaiMarina'));

      await tester.enterText(
        find.byType(TextField),
        'Dubai Marina, Dubai, Marina Gate 2',
      );
      await tester.pump();
      expect(find.byKey(_pill), findsOneWidget);
      expect(_selected(tester, 'dubaiMarina'), isTrue);
      expect(vm.propertyLocation, 'Dubai Marina, Dubai, Marina Gate 2');

      await tester.enterText(find.byType(TextField), 'Marina Gate 2');
      await tester.pump();
      expect(find.byKey(_pill), findsNothing);
      expect(_cityChips(), findsNWidgets(9));
      expect(vm.propertyLocation, 'Marina Gate 2');
    });

    testWidgets('edit mode: the saved city and area show as chosen',
        (tester) async {
      final vm = _vm(saved: 'Dubai Marina, Dubai');
      await _pump(tester, vm);

      expect(find.byKey(_pill), findsOneWidget);
      expect(find.text(en['dubai'] as String), findsOneWidget);
      expect(_selected(tester, 'dubaiMarina'), isTrue);
      expect(_fieldText(tester), 'Dubai Marina, Dubai');
      expect(_areaRows(tester), 3);
    });

    testWidgets('edit mode: a saved area far down the list is still shown',
        (tester) async {
      final vm = _vm(saved: 'Hor Al Anz, Dubai');
      await _pump(tester, vm, width: 320);

      expect(_areaChip('horAlAnz'), findsOneWidget);
      expect(_selected(tester, 'horAlAnz'), isTrue);
      expect(_areaRows(tester), lessThanOrEqualTo(3));
      expect(find.text(en['showMore'] as String), findsOneWidget);
    });

    testWidgets('edit mode: an area an older picker offered is still shown',
        (tester) async {
      final vm = _vm(saved: 'Al Shabiya, Umm Al Quwain');
      await _pump(tester, vm);

      expect(_areaChip('alShabiya'), findsOneWidget);
      expect(_selected(tester, 'alShabiya'), isTrue);
      expect(find.text(en['alShabiya'] as String), findsOneWidget);
    });

    testWidgets(
        'edit mode: typed text shows no choice and stays exactly as '
        'saved', (tester) async {
      final vm = _vm(saved: 'Near the old souk');
      await _pump(tester, vm);

      expect(find.byKey(_pill), findsNothing);
      expect(_cityChips(), findsNWidgets(9));
      expect(_fieldText(tester), 'Near the old souk');
      expect(vm.propertyLocation, 'Near the old souk');
    });

    testWidgets('Arabic: Arabic names, RTL, three rows, writes Arabic text',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm, locale: const Locale('ar'), textScale: 1.3);

      expect(_cityChips(), findsNWidgets(9));
      for (final city in UaeAreaCatalog.supportedCities) {
        expect(find.text(ar[UaeAreaCatalog.cityKey(city)] as String),
            findsOneWidget,
            reason: city);
      }
      expect(tester.getTopRight(_cityChip('Dubai')).dx, greaterThan(330),
          reason: 'the first city sits at the right edge');

      await _tap(tester, _cityChip('Dubai'));
      expect(_areaRows(tester), 3);
      expect(find.text(ar['showMore'] as String), findsOneWidget);

      await _tap(tester, _areaChip('dubaiMarina'));
      expect(_fieldText(tester), '${ar['dubaiMarina']}, ${ar['dubai']}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic: a location saved in English restores its choice',
        (tester) async {
      final vm = _vm(saved: 'Dubai Marina, Dubai');
      await _pump(tester, vm, locale: const Locale('ar'));

      expect(find.text(ar['dubai'] as String), findsOneWidget);
      expect(_selected(tester, 'dubaiMarina'), isTrue);
      expect(_fieldText(tester), 'Dubai Marina, Dubai',
          reason: 'the saved text is shown as saved');
    });

    testWidgets('every city lays out in Arabic without overflow',
        (tester) async {
      for (final city in UaeAreaCatalog.supportedCities) {
        final vm = _vm();
        await _pump(tester, vm, locale: const Locale('ar'), width: 320);
        await _tap(tester, _cityChip(city));
        expect(tester.takeException(), isNull, reason: city);
        expect(_areaRows(tester), lessThanOrEqualTo(3), reason: city);
      }
    });
  });

  group('the screen still has its free-text location field', () {
    test('the picker sits above the existing field, which stays editable', () {
      final screen =
          _read('lib/src/views/Screens/ViewAdd/add_owners_view.dart');
      final picker = screen.indexOf('UaeCityAreaPicker(');
      final field =
          screen.indexOf("localization.translate('enterPropertyLocation')");
      expect(picker, greaterThan(0));
      expect(field, greaterThan(picker),
          reason: 'the text field still follows the picker');
      expect(screen.contains('value: vm.propertyLocation'), isTrue);
      expect(screen.contains('onChanged: vm.setPropertyLocation'), isTrue);
    });

    test('the persisted value is still the one text field, free of any enum',
        () {
      final builder =
          _read('lib/src/services/core_entity_payload_builder.dart');
      expect(
        builder.contains("'property_location': model.propertyLocation.trim()"),
        isTrue,
      );
      for (final file in Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))) {
        for (final line in file.readAsLinesSync()) {
          final lower = line.toLowerCase();
          if (!lower.contains('property_location')) continue;
          expect(
            lower.contains('check') ||
                lower.contains('constraint') ||
                lower.contains(' in (') ||
                lower.contains('enum'),
            isFalse,
            reason: '${file.path}: $line',
          );
        }
      }
    });
  });
}
