import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/utils/core_entity_error_message.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _enMessage = 'The offer was saved, but one or more photos could not be '
    'uploaded. Edit the offer to retry.';
const _arMessage =
    'تم حفظ العرض، لكن تعذّر رفع صورة واحدة أو أكثر. يمكنك تعديل العرض '
    'لإعادة المحاولة.';

String Function(String) _fakeTranslate(Map<String, String> table) =>
    (key) => table[key] ?? '** $key not found';

void main() {
  group('CoreEntityErrorMessage.save — Offer Media partial-upload mapping',
      () {
    test(
        'maps the known partial-upload StateError to the English fallback '
        'when no translator is supplied', () {
      final error = StateError(
        'Offer saved, but 1 of 2 photo(s) failed to upload (bad.gif). '
        'Edit the offer to retry.',
      );

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, _enMessage);
      expect(message, isNot(contains('Unable to')));
    });

    test('returns the English translated message when an English translator '
        'is supplied', () {
      final error = StateError(
        'Offer saved, but 1 of 1 photo(s) failed to upload (x.jpg). '
        'Edit the offer to retry.',
      );
      final translate = _fakeTranslate({
        'offerSavedMediaPartialFailure': _enMessage,
      });

      final message = CoreEntityErrorMessage.save(
        error,
        'offer',
        isUpdate: true,
        translate: translate,
      );

      expect(message, _enMessage);
    });

    test('returns the Arabic translated message when an Arabic translator '
        'is supplied', () {
      final error = StateError(
        'Offer saved, but 1 of 1 photo(s) failed to upload (x.jpg). '
        'Edit the offer to retry.',
      );
      final translate = _fakeTranslate({
        'offerSavedMediaPartialFailure': _arMessage,
      });

      final message = CoreEntityErrorMessage.save(
        error,
        'offer',
        isUpdate: true,
        translate: translate,
      );

      expect(message, _arMessage);
    });

    test('does not leak the raw failed file name into the user message', () {
      final error = StateError(
        'Offer saved, but 1 of 1 photo(s) failed to upload '
        '(secret_path_fragment.png). Edit the offer to retry.',
      );

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: false);

      expect(message, isNot(contains('secret_path_fragment')));
    });

    test(
        'does not leak a filesystem path, R2 object key, or signed-URL-'
        'shaped fragment even when present in the underlying exception', () {
      final error = StateError(
        'Offer saved, but 1 of 1 photo(s) failed to upload '
        '(C:/Users/owner/Pictures/secret.png?X-Amz-Signature=abc123). '
        'Edit the offer to retry.',
      );

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, _enMessage);
      expect(message, isNot(contains('Users')));
      expect(message, isNot(contains('X-Amz-Signature')));
      expect(message, isNot(contains('secret.png')));
    });

    test('an ordinary session StateError keeps its existing mapping', () {
      final error = StateError('A Supabase session is required.');

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, 'Your session has expired. Please sign in again.');
    });

    test('an unrelated StateError still falls through to the generic message',
        () {
      final error = StateError(
        'Media mutation is disabled until the Cloudflare R2 migration '
        'batch is applied.',
      );

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, 'Unable to update the offer. Please try again.');
    });

    test('an ordinary total-failure StateError still reports total failure',
        () {
      final error = StateError('Unexpected null offer id.');

      final createMessage =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: false);
      final updateMessage =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(createMessage, 'Unable to save the offer. Please try again.');
      expect(updateMessage, 'Unable to update the offer. Please try again.');
    });

    test('validation errors are unchanged', () {
      final error = PhoneValidationException('bad phone');

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, 'Please enter a valid phone number.');
    });

    test('permission errors (Postgrest 42501) are unchanged', () {
      final error = PostgrestException(message: 'denied', code: '42501');

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, 'You do not have permission to save this offer.');
    });

    test('network timeout errors are unchanged', () {
      final error = TimeoutException('timed out');

      final message =
          CoreEntityErrorMessage.save(error, 'offer', isUpdate: true);

      expect(message, 'Check your internet connection and try again.');
    });
  });

  group('offerSavedMediaPartialFailure ARB key', () {
    Map<String, dynamic> loadArb(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    test('exists with a non-empty value in both app_en.arb and app_ar.arb',
        () {
      final en = loadArb('lib/src/common/localization/app_en.arb');
      final ar = loadArb('lib/src/common/localization/app_ar.arb');

      expect(en['offerSavedMediaPartialFailure'], _enMessage);
      expect(ar['offerSavedMediaPartialFailure'], isNotEmpty);
      expect(ar['offerSavedMediaPartialFailure'], isNot(_enMessage));
    });
  });
}
