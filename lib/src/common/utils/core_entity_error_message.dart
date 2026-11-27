import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_number_normalizer.dart';
import '../../services/core_entity_payload_builder.dart';
import '../../services/offer_media_policy.dart';

/// Converts technical persistence errors into messages safe for end users.
class CoreEntityErrorMessage {
  CoreEntityErrorMessage._();

  static String save(
    Object error,
    String entity, {
    required bool isUpdate,
    String Function(String key)? translate,
  }) {
    // With [translate] every message is the localized one; without it, the
    // English text below (unchanged) is returned.
    String localized(String key, String english,
        [Map<String, String> params = const {}]) {
      if (translate == null) return english;
      var text = translate(key);
      final values = {'entity': entity, ...params};
      values.forEach((name, value) => text = text.replaceAll('{$name}', value));
      return text;
    }

    if (error is PhoneValidationException) {
      return localized(
          'saveErrorInvalidPhone', 'Please enter a valid phone number.');
    }
    if (error is CoreEntityValidationException) {
      final key = error.messageKey;
      return key == null
          ? error.message
          : localized(key, error.message, error.params);
    }
    // The $entity itself is already saved by the time this is thrown, so the
    // generic save-failure message below would falsely claim total failure.
    // Never names a file, a path or a byte count — the exception carries
    // none. When every failed file was refused for the same user-actionable
    // reason, that reason is added as a second localized sentence.
    if (error is OfferMediaPartialUploadException) {
      if (translate != null) {
        final partial = translate('offerSavedMediaPartialFailure');
        final reason = error.rejection;
        return reason == null
            ? partial
            : '$partial ${translate(reason.messageKey)}';
      }
      return 'The $entity was saved, but one or more photos or videos could '
          'not be uploaded. Edit the $entity to retry.';
    }
    // The pre-typed-exception form, kept so an older in-flight failure path
    // still maps to the same message rather than the generic one.
    if (error is StateError &&
        error.message.contains('photo(s) failed to upload')) {
      if (translate != null) {
        return translate('offerSavedMediaPartialFailure');
      }
      return 'The $entity was saved, but one or more photos or videos could '
          'not be uploaded. Edit the $entity to retry.';
    }
    if (error is StateError && error.message.contains('session')) {
      return localized('saveErrorSessionExpired',
          'Your session has expired. Please sign in again.');
    }
    // The server's quota decisions. Each is exact, and none saved anything.
    if (error is PostgrestException) {
      switch (error.code) {
        case 'PBQ01':
          return localized('quotaCreationLimitReached',
              'You have used all 5 Free creations in this section.');
        case 'PBQ02':
          return localized('quotaEditLimitReached',
              'You have used all 3 Free edits for this item.');
        case 'PBQ03':
          return localized('quotaAccountReadOnly',
              'Your plan has ended and this account is over the Free limits, so adding and editing are paused.');
        case 'PBQ06':
          return localized('quotaCheckUnavailable',
              'Your plan could not be verified. Nothing was saved. Please try again.');
      }
    }
    if (error is AuthException ||
        (error is PostgrestException && error.code == '42501')) {
      return localized('saveErrorNoPermission',
          'You do not have permission to save this $entity.');
    }
    if (error is TimeoutException ||
        error.runtimeType.toString().contains('SocketException') ||
        error.runtimeType.toString().contains('ClientException')) {
      return localized('saveErrorNoConnection',
          'Check your internet connection and try again.');
    }
    if (error is PostgrestException) {
      return localized('saveErrorInvalidData',
          'The $entity data could not be validated. Please check the form.');
    }
    return localized(isUpdate ? 'updateErrorGeneric' : 'saveErrorGeneric',
        'Unable to ${isUpdate ? 'update' : 'save'} the $entity. Please try again.');
  }
}
