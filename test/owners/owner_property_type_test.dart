// Owner property-type quick chips: suggestions above the existing free-text
// field. The text stays the only stored value; a chip merely shows as selected
// while the text still says what it says. Covers the matching rules, the chips
// working with the real Owner view-model, edit mode (a saved suggestion selects
// its chip, a custom historical value is shown exactly), English and Arabic/RTL,
// and that the screen keeps the free-text field and the backend stays free text.
//
// Local tests. The screen's own text field is private, so the form here wires a
// stand-in field to the real view-model exactly as the screen does.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_owners_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/property_type_chips.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

/// The owner's order of suggestions.
const _expectedOrder = <String>[
  'villa',
  'apartment',
  'townhouse',
  'studio',
  'penthouse',
  'duplex',
  'wholeBuilding',
  'residentialPlot',
  'commercialPlot',
  'land',
  'farm',
  'office',
  'shopRetail',
  'warehouse',
  'showRoom',
  'laborCamp',
  'hotel',
  'hotelApartment',
  'other',
];

OwnerModel _owner({String type = '', String location = ''}) => OwnerModel(
      id: 'o1',
      userId: '',
      name: 'Owner',
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: type,
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
AddOwnersViewModel _vm({String? saved}) {
  final edit = saved != null;
  final vm = AddOwnersViewModel(
    mode: edit ? AddOwnersMode.edit : AddOwnersMode.add,
    ownerId: edit ? 'o1' : null,
    ownerData: edit ? _owner(type: saved) : null,
    ownerService: OwnerService(),
    usesMediaQueue: false,
  );
  addTearDown(vm.dispose);
  return vm;
}

/// Mirrors the screen's text field: its controller follows the view-model's
/// text, and typing reports back to the view-model.
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

class _Form extends StatelessWidget {
  const _Form({required this.vm});

  final AddOwnersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PropertyTypeChips(
              value: vm.typeOfProperties,
              onSelected: vm.setTypeOfProperties,
              localization: localization,
            ),
            const SizedBox(height: 12),
            _SyncedField(
              value: vm.typeOfProperties,
              onChanged: vm.setTypeOfProperties,
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
      builder: (context, inner) => Directionality(
        textDirection:
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: inner ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: _Form(vm: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _chip(String key) =>
    find.byKey(ValueKey<String>('property-type-chip-$key'));

Finder _allChips() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('property-type-chip-');
    });

bool _isSelected(WidgetTester tester, String key) =>
    tester.widget<SelectableChip>(_chip(key)).isSelected;

List<String> _selectedKeys(WidgetTester tester) => [
      for (final key in _expectedOrder)
        if (_isSelected(tester, key)) key,
    ];

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _tapChip(WidgetTester tester, String key) async {
  await tester.ensureVisible(_chip(key));
  await tester.pump();
  await tester.tap(_chip(key));
  await tester.pump();
}

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
  });

  Iterable<String> labelsOfKey(String key) =>
      [en[key], ar[key]].whereType<String>();

  group('the suggestions', () {
    test('are the owner\'s list, in the owner\'s order', () {
      expect(
        OwnerPropertyTypes.options.map((o) => o.key).toList(),
        _expectedOrder,
      );
    });

    test('every suggestion has an English and an Arabic name', () {
      for (final option in OwnerPropertyTypes.options) {
        expect((en[option.key] as String?)?.trim(), isNotEmpty,
            reason: 'en ${option.key}');
        expect((ar[option.key] as String?)?.trim(), isNotEmpty,
            reason: 'ar ${option.key}');
        expect(RegExp(r'[؀-ۿ]').hasMatch(ar[option.key] as String), isTrue,
            reason: 'ar ${option.key} is Arabic');
        expect(en[option.key], isNot(contains('undefined')));
      }
    });

    test('the owner\'s wording is what the chips say', () {
      expect(en['wholeBuilding'], 'Whole Building');
      expect(en['residentialPlot'], 'Residential Plot');
      expect(en['commercialPlot'], 'Commercial Plot');
      expect(en['shopRetail'], 'Shop / Retail');
      expect(en['hotel'], 'Hotel');
      expect(en['hotelApartment'], 'Hotel Apartment');
      expect(ar['residentialPlot'], 'أرض سكنية');
      expect(ar['commercialPlot'], 'أرض تجارية');
      expect(ar['shopRetail'], 'محل / تجزئة');
      expect(ar['hotel'], 'فندق');
      expect(ar['hotelApartment'], 'شقة فندقية');
    });

    test('the project\'s existing property-type words are reused, not copied',
        () {
      // One canonical term each: these ARB keys already existed.
      for (final key in const [
        'villa',
        'apartment',
        'townhouse',
        'studio',
        'penthouse',
        'duplex',
        'wholeBuilding',
        'land',
        'farm',
        'office',
        'warehouse',
        'showRoom',
        'laborCamp',
        'other',
      ]) {
        expect(
            OwnerPropertyTypes.options.where((o) => o.key == key), hasLength(1),
            reason: key);
      }
      // A concept the project already named is never offered under a second key.
      final keys = OwnerPropertyTypes.options.map((o) => o.key).toSet();
      for (final duplicate in const [
        'flat',
        'labourCamp',
        'showroom',
        'hotelAndHotelApartment',
        'villaType',
      ]) {
        expect(keys.contains(duplicate), isFalse, reason: duplicate);
      }
    });

    test('no two suggestions answer to the same text', () {
      final owner = <String, String>{};
      for (final option in OwnerPropertyTypes.options) {
        final texts = <String>[
          ...labelsOfKey(option.key),
          ...option.aliases,
          for (final key in option.aliasKeys) ...labelsOfKey(key),
        ].map((t) => t.trim().toLowerCase());
        for (final text in texts) {
          final previous = owner[text];
          expect(previous == null || previous == option.key, isTrue,
              reason: '"$text" is both $previous and ${option.key}');
          owner[text] = option.key;
        }
      }
    });
  });

  group('matching saved text to a suggestion', () {
    OwnerPropertyType? match(String text) =>
        OwnerPropertyTypes.match(text, labelsOfKey: labelsOfKey);

    test('every suggestion matches its own English and Arabic name', () {
      for (final option in OwnerPropertyTypes.options) {
        expect(match(en[option.key] as String)?.key, option.key,
            reason: 'en ${option.key}');
        expect(match(ar[option.key] as String)?.key, option.key,
            reason: 'ar ${option.key}');
      }
    });

    test('case and extra spaces do not matter', () {
      expect(match('villa')?.key, 'villa');
      expect(match('  VILLA ')?.key, 'villa');
      expect(match('Whole   Building')?.key, 'wholeBuilding');
      expect(match('shop/retail')?.key, 'shopRetail');
      expect(match('SHOP  /  RETAIL')?.key, 'shopRetail');
    });

    test('older spellings the project already used still match', () {
      expect(match('Shop')?.key, 'shopRetail');
      expect(match('Retail')?.key, 'shopRetail');
      expect(match('Labour Camp')?.key, 'laborCamp');
      expect(match('Labor Camp')?.key, 'laborCamp');
      expect(match('سكن عمال')?.key, 'laborCamp');
      expect(match('Showroom')?.key, 'showRoom');
      expect(match('Show Room')?.key, 'showRoom');
      expect(match('بنتهاوس')?.key, 'penthouse');
      expect(match('بنت هاوس')?.key, 'penthouse');
    });

    test('hotel and hotel apartment stay distinct', () {
      expect(match('Hotel')?.key, 'hotel');
      expect(match('Hotel Apartment')?.key, 'hotelApartment');
      expect(match('Hotel & Hotel Apartment'), isNull,
          reason: 'the old combined wording says neither one');
    });

    test('anything else is the owner\'s own wording', () {
      for (final custom in const [
        '',
        '   ',
        'Villas',
        'Roof terrace',
        'Beachfront villa',
        'Villa and garden',
        'Apartment block',
        'مبنى',
      ]) {
        expect(match(custom), isNull, reason: '"$custom"');
      }
    });
  });

  group('the chips with the Owner view-model', () {
    testWidgets('all nineteen render, in order, with English names',
        (tester) async {
      await _pump(tester, _vm());

      expect(_allChips(), findsNWidgets(_expectedOrder.length));
      final order = _allChips()
          .evaluate()
          .map((e) => (e.widget.key! as ValueKey<String>).value)
          .map((k) => k.replaceFirst('property-type-chip-', ''))
          .toList();
      expect(order, _expectedOrder);
      for (final key in _expectedOrder) {
        expect(find.text(en[key] as String), findsOneWidget, reason: key);
      }
      expect(_selectedKeys(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Villa fills the field and selects Villa',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await _tapChip(tester, 'villa');

      expect(vm.typeOfProperties, 'Villa');
      expect(_fieldText(tester), 'Villa');
      expect(_selectedKeys(tester), ['villa']);
    });

    testWidgets('tapping Apartment replaces Villa', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await _tapChip(tester, 'villa');
      await _tapChip(tester, 'apartment');

      expect(vm.typeOfProperties, 'Apartment');
      expect(_fieldText(tester), 'Apartment');
      expect(_selectedKeys(tester), ['apartment']);
    });

    testWidgets('every chip puts its own name in the field', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      for (final key in _expectedOrder) {
        await _tapChip(tester, key);
        expect(vm.typeOfProperties, en[key], reason: key);
        expect(_fieldText(tester), en[key], reason: key);
        expect(_selectedKeys(tester), [key], reason: key);
      }
    });

    testWidgets('the field stays free text: custom wording is accepted as is',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await tester.enterText(find.byType(TextField), 'Roof terrace unit');
      await tester.pump();

      expect(vm.typeOfProperties, 'Roof terrace unit');
      expect(_selectedKeys(tester), isEmpty,
          reason: 'custom text selects no chip');
    });

    testWidgets('editing a suggestion into custom text drops the selection',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tapChip(tester, 'villa');
      expect(_selectedKeys(tester), ['villa']);

      await tester.enterText(find.byType(TextField), 'Villa with pool');
      await tester.pump();

      expect(vm.typeOfProperties, 'Villa with pool');
      expect(_selectedKeys(tester), isEmpty);
    });

    testWidgets('typing a suggestion\'s name by hand selects its chip',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);

      await tester.enterText(find.byType(TextField), 'office');
      await tester.pump();

      expect(vm.typeOfProperties, 'office',
          reason: 'what was typed is kept, not rewritten');
      expect(_selectedKeys(tester), ['office']);
    });

    testWidgets('clearing the text clears the selection', (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tapChip(tester, 'studio');
      expect(_selectedKeys(tester), ['studio']);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(vm.typeOfProperties, isEmpty);
      expect(_selectedKeys(tester), isEmpty);
    });

    testWidgets('a chip never stores a second value next to the text',
        (tester) async {
      final vm = _vm();
      await _pump(tester, vm);
      await _tapChip(tester, 'townhouse');

      // The one stored value is the text; the model built for saving carries
      // exactly it.
      expect(vm.typeOfProperties, 'Townhouse');
      await tester.enterText(find.byType(TextField), 'Townhouse (end unit)');
      await tester.pump();
      expect(vm.typeOfProperties, 'Townhouse (end unit)');
      expect(_selectedKeys(tester), isEmpty);
    });
  });

  group('edit mode', () {
    testWidgets('a saved suggestion shows its chip and the same text',
        (tester) async {
      final vm = _vm(saved: 'Villa');
      await _pump(tester, vm);

      expect(_selectedKeys(tester), ['villa']);
      expect(_fieldText(tester), 'Villa');
      expect(vm.typeOfProperties, 'Villa');
    });

    testWidgets('a custom historical value is shown exactly, nothing selected',
        (tester) async {
      const saved = 'Beachfront Villas (3 units)';
      final vm = _vm(saved: saved);
      await _pump(tester, vm);

      expect(_fieldText(tester), saved);
      expect(vm.typeOfProperties, saved,
          reason: 'not replaced and not normalized');
      expect(_selectedKeys(tester), isEmpty);
    });

    testWidgets('a value saved in Arabic selects the chip in an English app',
        (tester) async {
      final vm = _vm(saved: 'فيلا');
      await _pump(tester, vm);

      expect(_selectedKeys(tester), ['villa']);
      expect(_fieldText(tester), 'فيلا',
          reason: 'the saved text is shown as saved, not translated');
      expect(vm.typeOfProperties, 'فيلا');
    });

    testWidgets('a value saved in English selects the chip in an Arabic app',
        (tester) async {
      final vm = _vm(saved: 'Apartment');
      await _pump(tester, vm, locale: const Locale('ar'));

      expect(_selectedKeys(tester), ['apartment']);
      expect(_fieldText(tester), 'Apartment');
    });

    testWidgets('an older spelling selects the matching chip but is kept',
        (tester) async {
      final vm = _vm(saved: 'Labour Camp');
      await _pump(tester, vm);

      expect(_selectedKeys(tester), ['laborCamp']);
      expect(_fieldText(tester), 'Labour Camp');
      expect(vm.typeOfProperties, 'Labour Camp');
    });

    testWidgets('an empty saved value selects nothing', (tester) async {
      final vm = _vm(saved: '');
      await _pump(tester, vm);

      expect(_selectedKeys(tester), isEmpty);
      expect(_fieldText(tester), isEmpty);
    });
  });

  group('Arabic and RTL', () {
    testWidgets('the chips carry the Arabic names and flow from the right',
        (tester) async {
      await _pump(tester, _vm(), locale: const Locale('ar'));

      for (final key in _expectedOrder) {
        expect(find.text(ar[key] as String), findsOneWidget, reason: key);
      }
      expect(tester.getTopRight(_chip('villa')).dx, greaterThan(330),
          reason: 'the first chip sits at the right edge');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a chip writes the Arabic name', (tester) async {
      final vm = _vm();
      await _pump(tester, vm, locale: const Locale('ar'));

      await _tapChip(tester, 'villa');

      expect(vm.typeOfProperties, 'فيلا');
      expect(_fieldText(tester), 'فيلا');
      expect(_selectedKeys(tester), ['villa']);

      await _tapChip(tester, 'hotelApartment');
      expect(vm.typeOfProperties, 'شقة فندقية');
      expect(_selectedKeys(tester), ['hotelApartment']);
    });

    testWidgets('no overflow at a narrow width with large text',
        (tester) async {
      final vm = _vm();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: inner ?? const SizedBox.shrink(),
            ),
          ),
          home: Scaffold(body: _Form(vm: vm)),
        ),
      );
      await tester.pumpAndSettle();

      expect(_allChips(), findsNWidgets(_expectedOrder.length));
      expect(tester.takeException(), isNull);
    });
  });

  group('the Owner screen and the backend', () {
    const screen = 'lib/src/views/Screens/ViewAdd/add_owners_view.dart';

    test('the screen shows the chips above the existing free-text field', () {
      final source = File(screen).readAsStringSync();
      expect(source.contains('property_type_chips.dart'), isTrue);
      final chips = source.indexOf('PropertyTypeChips(');
      final field =
          source.indexOf("hint: localization.translate('enterPropertiesType')");
      expect(chips, greaterThan(0));
      expect(field, greaterThan(chips),
          reason: 'the text field still follows the chips');
      expect(source.contains('value: vm.typeOfProperties'), isTrue);
      expect(source.contains('onSelected: vm.setTypeOfProperties'), isTrue);
      expect(source.contains('onChanged: vm.setTypeOfProperties'), isTrue,
          reason: 'typing still goes straight to the view-model');
    });

    test('the view-model accepts any text for the property type', () {
      final source = File(
        'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart',
      ).readAsStringSync();
      final setter = RegExp(
        r'void setTypeOfProperties\(String v\) \{([^}]*)\}',
      ).firstMatch(source)!.group(1)!;
      expect(setter.contains('typeOfProperties = v;'), isTrue);
      expect(setter.contains('OwnerPropertyTypes'), isFalse,
          reason: 'the suggestions never restrict the field');
      expect(setter.contains('if ('), isFalse);
    });

    test('the database stores the property type as free text', () {
      final constrained = <String>[];
      for (final file in Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))) {
        for (final line in file.readAsLinesSync()) {
          final lower = line.toLowerCase();
          if (!lower.contains('property_type_text')) continue;
          if (lower.contains('check') ||
              lower.contains('constraint') ||
              lower.contains(' in (') ||
              lower.contains('enum')) {
            constrained.add('${file.path}: ${line.trim()}');
          }
        }
      }
      expect(constrained, isEmpty,
          reason: 'a CHECK or enum would reject custom property types');
    });

    test('the Owner model and save path carry the text untouched', () {
      final builder = File('lib/src/services/core_entity_payload_builder.dart')
          .readAsStringSync();
      expect(
          builder
              .contains("'property_type_text': model.typeOfProperties.trim()"),
          isTrue);
    });
  });
}
