import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/common/utils/phone_utils.dart';
import 'package:broker_wallet/src/common/utils/uae_phone_input.dart';
import 'package:broker_wallet/src/views/Widgets/input_phone_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

final _formatter = UaeNationalPhoneInputFormatter();

TextEditingValue _v(String text, [int? caret]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    );

/// Applies [typed] as the new field value, as the framework would.
TextEditingValue _edit(TextEditingValue old, String typed, [int? caret]) =>
    _formatter.formatEditUpdate(old, _v(typed, caret));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final file = File(utf8.decode(message!.buffer.asUint8List()));
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  group('UaePhoneInput.nationalDigits', () {
    const expected = '501234567';
    for (final raw in [
      '501234567',
      '0501234567',
      '+971501234567',
      '971501234567',
      '00971501234567',
      '+9710501234567',
      '+971 50 123 4567',
      '050-123-4567',
      '٠٥٠١٢٣٤٥٦٧', // Arabic-Indic
      '۰۵۰۱۲۳۴۵۶۷', // Eastern Arabic-Indic
      '+٩٧١٥٠١٢٣٤٥٦٧',
    ]) {
      test('normalizes $raw', () {
        expect(UaePhoneInput.nationalDigits(raw), expected);
      });
    }

    test('refuses another country instead of mangling it', () {
      expect(UaePhoneInput.nationalDigits('+966501234567'), isNull);
      expect(UaePhoneInput.nationalDigits('00966501234567'), isNull);
    });
  });

  group('app contract', () {
    test('toLocalTrunk keeps the 05XXXXXXXX form', () {
      expect(UaePhoneInput.toLocalTrunk('50 123 4567'), '0501234567');
      expect(UaePhoneInput.toLocalTrunk('5'), '05');
      expect(UaePhoneInput.toLocalTrunk(''), '');
    });

    test('local trunk feeds the existing E.164 paths without double prefix',
        () {
      for (final raw in ['501234567', '+971501234567', '00971501234567']) {
        final local = UaePhoneInput.toLocalTrunk(UaePhoneInput.displayFor(raw));
        expect(local, '0501234567');
        expect(PhoneUtils.toE164Uae(local), '+971501234567');
        expect(PhoneNumberNormalizer.normalizeUaeMobile(local),
            '+971501234567');
      }
    });

    test('prefilled stored values display as the national number', () {
      expect(UaePhoneInput.displayFor('0501234567'), '50 123 4567');
      expect(UaePhoneInput.displayFor('+971501234567'), '50 123 4567');
      expect(UaePhoneInput.displayFor(''), '');
    });

    test('a landline keeps its digits (validation stays with the caller)', () {
      expect(UaePhoneInput.toLocalTrunk(UaePhoneInput.displayFor('042345678')),
          '042345678');
    });
  });

  group('UaeNationalPhoneInputFormatter', () {
    test('groups typed digits and places the caret', () {
      var value = const TextEditingValue();
      for (final ch in '501234567'.split('')) {
        value = _edit(value, value.text + ch);
      }
      expect(value.text, '50 123 4567');
      expect(value.selection.extentOffset, value.text.length);
    });

    test('a typed trunk zero is dropped', () {
      expect(_edit(const TextEditingValue(), '0').text, '');
      expect(_edit(const TextEditingValue(), '05').text, '5');
    });

    test('pastes every common format whole', () {
      for (final raw in [
        '0501234567',
        '+971501234567',
        '971501234567',
        '00971501234567',
        '+9710501234567',
        '+971 50 123 4567',
        '٠٥٠١٢٣٤٥٦٧',
      ]) {
        expect(_edit(const TextEditingValue(), raw).text, '50 123 4567',
            reason: raw);
      }
    });

    test('rejects letters and symbols', () {
      expect(_edit(_v('5'), '5a').text, '5');
      expect(_edit(_v('5'), '5#*').text, '5');
    });

    test('does not truncate: a tenth digit or oversized paste is refused', () {
      final full = _v('50 123 4567');
      expect(_edit(full, '50 123 45678').text, '50 123 4567');
      expect(_edit(const TextEditingValue(), '+9715012345678').text, '');
    });

    test('a foreign-country paste is refused', () {
      expect(_edit(const TextEditingValue(), '+966501234567').text, '');
    });

    test('incomplete input stays incomplete', () {
      expect(_edit(const TextEditingValue(), '+97150').text, '50');
    });

    test('caret follows an insertion in the middle', () {
      // "5 123" -> user types 0 after the first digit.
      final out = _edit(_v('51 234', 1), '501 234', 2);
      expect(out.text, '50 123 4');
      expect(out.selection.extentOffset, 2);
    });

    test('caret after deletion stays by the deleted digit', () {
      // Delete the "2" in "50 123 4567" (offset 4 -> 3).
      final out = _edit(_v('50 123 4567', 5), '50 13 4567', 4);
      expect(out.text, '50 134 567');
      expect(out.selection.extentOffset, 4);
    });

    test('a pasted full number replaces a selection', () {
      final out = _edit(_v('50 123 4567'), '+971521234567');
      expect(out.text, '52 123 4567');
    });
  });

  group('PhoneInputWidget layout', () {
    Future<void> pumpField(
      WidgetTester tester, {
      required Locale locale,
      String value = '',
      List<String>? changes,
    }) async {
      tester.view.physicalSize = const Size(360, 800);
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LABEL', key: ValueKey('label')),
                    PhoneInputWidget(
                      countryCode: '+971',
                      value: value,
                      onChanged: (v) => changes?.add(v),
                      localization: AppLocalizations.of(context),
                      validateInternally: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final code in ['ar', 'en']) {
      testWidgets('[$code] code left of the number, no flag or parentheses',
          (tester) async {
        await pumpField(tester, locale: Locale(code));

        final codeLeft = tester.getTopLeft(find.text('+971')).dx;
        final fieldLeft = tester.getTopLeft(find.byType(TextField)).dx;
        expect(codeLeft, lessThan(fieldLeft));
        expect(codeLeft, lessThan(60)); // physical left edge of the field
        expect(find.textContaining('('), findsNothing);
        expect(find.byType(SvgPicture), findsNothing);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textDirection, TextDirection.ltr);
        expect(field.textAlign, TextAlign.left);
        expect(field.keyboardType, TextInputType.phone);
        expect(find.text('5X XXX XXXX'), findsOneWidget);
      });
    }

    testWidgets('label follows the screen direction in Arabic and English',
        (tester) async {
      await pumpField(tester, locale: const Locale('ar'));
      // The column is start-aligned; in RTL the label sits at the right.
      expect(tester.getTopRight(find.byKey(const ValueKey('label'))).dx,
          closeTo(344, 1));
      await pumpField(tester, locale: const Locale('en'));
      expect(tester.getTopLeft(find.byKey(const ValueKey('label'))).dx,
          closeTo(16, 1));
    });

    testWidgets('emits the local trunk form and shows prefilled values',
        (tester) async {
      final changes = <String>[];
      await pumpField(
        tester,
        locale: const Locale('ar'),
        value: '+971501234567',
        changes: changes,
      );
      expect(find.text('50 123 4567'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '٥٢١٢٣٤٥٦٧');
      await tester.pump();
      expect(changes.last, '0521234567');
      expect(find.text('52 123 4567'), findsOneWidget);
    });
  });
}
