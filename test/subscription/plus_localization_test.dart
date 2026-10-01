import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _load(String lang) {
  final raw = json.decode(
    File('lib/src/common/localization/app_$lang.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return {
    for (final entry in raw.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}

/// Every key in file order, duplicates included (JSON decoding hides them).
List<String> _rawKeys(String lang) {
  final pattern = RegExp(r'^\s*"([^"]+)"\s*:');
  return [
    for (final line
        in File('lib/src/common/localization/app_$lang.arb').readAsLinesSync())
      if (pattern.firstMatch(line) != null) pattern.firstMatch(line)!.group(1)!,
  ];
}

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

bool _isPlusKey(String key) =>
    key == 'freePlanShort' || RegExp(r'^plus[A-Z]').hasMatch(key);

void main() {
  final en = _load('en');
  final ar = _load('ar');

  // Brand/store names, and one pure format pattern ("{period} • {price}"),
  // that are deliberately the same in both languages.
  const sameInBothLanguages = {
    'plusStoreAppStore',
    'plusStoreGooglePlay',
    'plusPeriodPriceLine',
  };

  test('every Plus key used by the app exists in English and Arabic', () {
    final referenced = <String>{};
    final literal = RegExp(r"'(plus[A-Z][A-Za-z0-9]*|freePlanShort)'");
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final match in literal.allMatches(entity.readAsStringSync())) {
        referenced.add(match.group(1)!);
      }
    }

    expect(referenced, isNotEmpty);
    expect(referenced.where((k) => !en.containsKey(k)), isEmpty,
        reason: 'missing in app_en.arb');
    expect(referenced.where((k) => !ar.containsKey(k)), isEmpty,
        reason: 'missing in app_ar.arb');
  });

  test('English and Arabic define exactly the same Plus keys', () {
    final enPlus = en.keys.where(_isPlusKey).toSet();
    final arPlus = ar.keys.where(_isPlusKey).toSet();
    expect(enPlus.difference(arPlus), isEmpty, reason: 'only in English');
    expect(arPlus.difference(enPlus), isEmpty, reason: 'only in Arabic');
  });

  test('every Plus string uses the same placeholders in both languages', () {
    for (final key in en.keys.where(_isPlusKey)) {
      expect(
        _placeholders(ar[key] ?? ''),
        _placeholders(en[key]!),
        reason: key,
      );
    }
  });

  test('Arabic Plus strings are real translations', () {
    final arabicLetters = RegExp(r'[؀-ۿ]');
    for (final key in en.keys.where(_isPlusKey)) {
      if (sameInBothLanguages.contains(key)) continue;
      expect(ar[key], isNot(en[key]), reason: '$key is untranslated');
      expect(arabicLetters.hasMatch(ar[key]!), isTrue,
          reason: '$key has no Arabic text');
    }
  });

  test('no Plus string hard-codes a price or currency', () {
    for (final lang in [en, ar]) {
      for (final key in lang.keys.where(_isPlusKey)) {
        expect(lang[key], isNot(contains('AED')), reason: key);
        expect(lang[key], isNot(contains('درهم')), reason: key);
        expect(
          RegExp(r'\d+\s*%?\s*(off|خصم)').hasMatch(lang[key]!),
          isFalse,
          reason: '$key looks like a fixed discount',
        );
      }
    }
  });

  test('the old hard-coded pricing strings are gone', () {
    for (final lang in [en, ar]) {
      expect(lang.containsKey('premiumPricing'), isFalse);
      expect(lang.containsKey('save33'), isFalse);
    }
  });

  test('the Plus keys and the cleaned subscription keys are defined once', () {
    const cleaned = {
      'subscription',
      'paymentMethod',
      'upgradeToPremium',
      'prioritySupport',
    };
    for (final lang in ['en', 'ar']) {
      final counts = <String, int>{};
      for (final key in _rawKeys(lang)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
      for (final key in counts.keys) {
        if (_isPlusKey(key) || cleaned.contains(key)) {
          expect(counts[key], 1, reason: '$lang defines "$key" more than once');
        }
      }
    }
  });

  test('the My Plan section title is no longer misspelled', () {
    expect(en['mainSections'], 'Main Sections');
  });
}
