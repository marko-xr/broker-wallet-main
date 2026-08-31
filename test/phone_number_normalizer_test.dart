import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNumberNormalizer', () {
    test('removes UAE trunk prefix when combining country and local number',
        () {
      expect(
        PhoneNumberNormalizer.normalize(
          countryCode: '+971',
          phoneNumber: '055 288 5142',
        ),
        '+971552885142',
      );
    });

    test('accepts an already international formatted number', () {
      expect(
        PhoneNumberNormalizer.normalize(
          countryCode: '+971',
          phoneNumber: '+971 (55) 288-5142',
        ),
        '+971552885142',
      );
    });

    test('normalizes all supported UAE input shapes', () {
      for (final input in <String>[
        '0552885222',
        '055 288 5222',
        '552885222',
        '+971552885222',
        '+9710552885222',
      ]) {
        expect(
          PhoneNumberNormalizer.normalize(
            countryCode: '+971',
            phoneNumber: input,
          ),
          '+971552885222',
          reason: input,
        );
      }
    });

    test('does not duplicate a country code without a plus', () {
      expect(
        PhoneNumberNormalizer.normalize(
          countryCode: '+971',
          phoneNumber: '971552885142',
        ),
        '+971552885142',
      );
    });

    test('supports a non-UAE country code', () {
      expect(
        PhoneNumberNormalizer.normalize(
          countryCode: '+44',
          phoneNumber: '020 7946 0958',
        ),
        '+442079460958',
      );
    });

    test('rejects empty and malformed values before the API call', () {
      expect(
        () => PhoneNumberNormalizer.normalize(
          countryCode: '+971',
          phoneNumber: '123',
        ),
        throwsA(isA<PhoneValidationException>()),
      );
    });
  });
}
