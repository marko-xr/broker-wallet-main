import 'dart:io';

import 'package:broker_wallet/src/services/details_contact_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final valid = <(String, String, String)>[
    ('0501234567', '+971', '+971501234567'),
    ('50 123 4567', '+971', '+971501234567'),
    ('+971 (50) 123-4567', '+971', '+971501234567'),
    ('971501234567', '+971', '+971501234567'),
    ('+9710501234567', '+971', '+971501234567'),
    ('00971 50 123 4567', '+971', '+971501234567'),
    ('04 123 4567', '+971', '+97141234567'),
    ('020 7946 0958', '+44', '+442079460958'),
    ('442079460958', '+44', '+442079460958'),
    ('0044 20 7946 0958', '+971', '+442079460958'),
    ('+1 (202) 555-0123', '+971', '+12025550123'),
    ('+39 (06) 6982', '+39', '+39066982'),
    ('\u200E+971 50 123 4567', '+971', '+971501234567'),
  ];
  for (final value in valid) {
    test('normalizes ${value.$1} with ${value.$2}', () {
      expect(
          DetailsContactActions.normalizePhone(value.$1, countryCode: value.$2),
          value.$3);
    });
  }
  for (final phone in [
    '',
    '   ',
    '+',
    '123',
    '+97112345',
    '+97150123456',
    '+9715012345678',
    '+0123456789',
    '++971501234567',
    '971+501234567',
    'abc0501234567',
    '0501234567 ext 1',
    '+1234567890123456'
  ]) {
    test('rejects invalid input $phone without launching', () async {
      var calls = 0;
      Future<bool> launcher(Uri uri, {required LaunchMode mode}) async {
        calls++;
        return true;
      }

      expect(DetailsContactActions.normalizePhone(phone), isNull);
      expect(await DetailsContactActions.call(phone, launcher: launcher),
          ContactLaunchResult.invalidPhone);
      expect(
          await DetailsContactActions.whatsApp(phone,
              message: 'unchanged', launcher: launcher),
          ContactLaunchResult.invalidPhone);
      expect(calls, 0);
    });
  }
  test('rejects malformed supplied country code', () {
    expect(
        DetailsContactActions.normalizePhone('501234567', countryCode: 'abc'),
        isNull);
  });
  test('dialer receives canonical tel URI and platform-default launch mode',
      () async {
    expect(
        await DetailsContactActions.call('020 7946 0958', countryCode: '+44',
            launcher: (uri, {required mode}) async {
          expect(uri.scheme, 'tel');
          expect(uri.path, '+442079460958');
          expect(mode, LaunchMode.platformDefault);
          return true;
        }),
        ContactLaunchResult.opened);
  });
  for (final outcome in [
    false,
    PlatformException(code: 'blocked'),
    Exception('unavailable')
  ]) {
    test('dialer reports failure on $outcome', () async {
      expect(
          await DetailsContactActions.call('+971501234567',
              launcher: (_, {required mode}) async {
            if (outcome is Exception) throw outcome;
            return false;
          }),
          ContactLaunchResult.failed);
    });
  }
  for (final message in [
    'Hello Ali & Co + 50%? # "quoted"\nNew line',
    'مرحبًا أحمد & علي + ٥٠٪؟ # "نص"\nسطر جديد'
  ]) {
    test('all WhatsApp fallbacks encode message exactly once: $message',
        () async {
      final uris = <Uri>[];
      final result = await DetailsContactActions.whatsApp('0501234567',
          message: message, launcher: (uri, {required mode}) async {
        uris.add(uri);
        expect(mode, LaunchMode.externalApplication);
        expect(uri.queryParameters['text'], message);
        if (uri.host == 'wa.me') {
          expect(uri.path, '/971501234567');
        } else {
          expect(uri.queryParameters['phone'], '971501234567');
        }
        return false;
      });
      expect(result, ContactLaunchResult.failed);
      expect(uris.map((uri) => uri.host),
          ['api.whatsapp.com', 'wa.me', 'web.whatsapp.com']);
    });
  }
  for (final message in [null, '']) {
    test('WhatsApp with no message opens the chat empty: $message', () async {
      final uris = <Uri>[];
      final result = await DetailsContactActions.whatsApp('0501234567',
          message: message, launcher: (uri, {required mode}) async {
        uris.add(uri);
        return false;
      });
      expect(result, ContactLaunchResult.failed);
      expect(uris.map((uri) => uri.toString()), [
        'https://api.whatsapp.com/send?phone=971501234567',
        'https://wa.me/971501234567',
        'https://web.whatsapp.com/send?phone=971501234567',
      ]);
    });
  }
  test('the Details screens open WhatsApp with no pre-filled message', () {
    for (final name in [
      'offers',
      'requested',
      'owners',
      'brokers',
      'offices',
      'watchmen'
    ]) {
      final source =
          File('lib/src/views/Screens/ViewDetails/${name}_view_details.dart')
              .readAsStringSync();
      expect(source.contains('DetailsContactActions.whatsApp('), isTrue,
          reason: name);
      expect(source.contains('whatsAppBusinessMessage'), isFalse, reason: name);
      expect(source.contains('message:'), isFalse, reason: name);
    }
  });
  for (final successAt in [0, 1, 2]) {
    test('WhatsApp stops after successful destination $successAt', () async {
      var calls = 0;
      expect(
          await DetailsContactActions.whatsApp('+442079460958',
              message: 'Hello',
              launcher: (uri, {required mode}) async => calls++ == successAt),
          ContactLaunchResult.opened);
      expect(calls, successAt + 1);
    });
  }
  test('WhatsApp retries after exception and succeeds at next destination',
      () async {
    var calls = 0;
    expect(
        await DetailsContactActions.whatsApp('+971501234567', message: 'Hello',
            launcher: (_, {required mode}) async {
          if (calls++ == 0) throw PlatformException(code: 'unavailable');
          return true;
        }),
        ContactLaunchResult.opened);
    expect(calls, 2);
  });
  test('WhatsApp reports failure when all destinations throw', () async {
    var calls = 0;
    expect(
        await DetailsContactActions.whatsApp('+971501234567', message: 'Hello',
            launcher: (_, {required mode}) async {
          calls++;
          throw PlatformException(code: 'unavailable');
        }),
        ContactLaunchResult.failed);
    expect(calls, 3);
  });
}
