import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = jsonDecode(
    File('lib/src/common/localization/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ar = jsonDecode(
    File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final view = File(
    'lib/src/views/Screens/home/Profile/legal_information_view.dart',
  ).readAsStringSync();
  final routes = File('lib/app.dart').readAsStringSync();

  test('V2 privacy and terms sections exist in both languages', () {
    for (final locale in [en, ar]) {
      for (final prefix in ['legalPrivacy', 'legalTerms']) {
        expect(locale['${prefix}Intro'], isA<String>());
        final count = prefix == 'legalPrivacy' ? 9 : 11;
        for (var section = 1; section <= count; section++) {
          expect(locale['${prefix}${section}Title'], isA<String>());
          expect(locale['${prefix}${section}Body'], isA<String>());
        }
      }
      expect(locale['privacyPolicyPlaceholder'], isNull);
      expect(locale['termsConditionsPlaceholder'], isNull);
      expect(locale['legalContentPending'], isNull);
      expect(locale['legalContentAvailableBeforeRelease'], isNull);
    }
  });

  test('published app text contains no internal markers or invented facts', () {
    final legalText = [en, ar]
        .expand((locale) => locale.entries.where(
              (entry) => entry.key.startsWith('legalPrivacy') ||
                  entry.key.startsWith('legalTerms'),
            ))
        .map((entry) => entry.value.toString())
        .join('\n');

    for (final marker in [
      '[insert at publication]',
      '[يُدرج عند النشر]',
      'OWNER_DECISION_REQUIRED',
      'REVIEW NOTES',
      '#a-privacy-policy',
      'final published Terms',
      'النسخة النهائية المنشورة',
      'Effective date:',
      'تاريخ السريان:',
      'Firebase',
      'we do not sell personal data',
      'competent court',
      'المحكمة أو الجهة المختصة',
    ]) {
      expect(legalText, isNot(contains(marker)), reason: marker);
    }
    expect(legalText, contains('NMO Digital'));
    expect(legalText, contains('brokerwallet@nmodigital.com'));
    expect(legalText, contains('محفظة الوسيط'));
  });

  test('age statements agree in English and Arabic', () {
    for (final locale in [en, ar]) {
      final privacyAge = locale['legalPrivacy8Body'] as String;
      final termsAge = locale['legalTerms1Body'] as String;
      expect(privacyAge, contains('14'));
      expect(termsAge, contains('14'));
      expect(privacyAge, isNot(contains('18')));
      expect(termsAge, isNot(contains('18')));
    }
    expect(en['legalPrivacy8Body'], isNot(contains('not intended for children')));
    expect(ar['legalPrivacy8Body'], isNot(contains('وليست موجهة للأطفال')));
  });

  test('legal view uses the internal privacy route and direction safe text', () {
    expect(routes, contains("path: '/privacy-policy'"));
    expect(view, contains("context.push('/privacy-policy')"));
    expect(view, contains('TapGestureRecognizer'));
    expect(view, contains('legalTermsPrivacyReference'));
    expect(view, contains(r'\u2066brokerwallet@nmodigital.com\u2069'));
    expect(view, contains('ListView('));
    expect(view, contains('Theme.of(context)'));
    expect(RegExp(r'textAlign: TextAlign.justify').allMatches(view).length, 3);
  });
}
