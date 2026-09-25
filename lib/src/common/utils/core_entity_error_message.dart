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
    if (error is PhoneValidationException) {
      return 'Please enter a valid phone number.';
    }
    if (error is CoreEntityValidationException) {
      return error.message;
    }
    // The $entity itself is already saved by the time this is thrown, so the
    // generic save-failure message below would falsely claim total failure.
    // Never names a file, a path or a byte count — the exception carries
    // none. When every failed file was refused for the same user-actionable
    // reason, that reason is added as a second localized sentence.
    // Only these branches are localized; every other message in this class is
    // unchanged, pre-existing English-only technical debt.
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
      return 'Your session has expired. Please sign in again.';
    }
    if (error is AuthException ||
        (error is PostgrestException && error.code == '42501')) {
      return 'You do not have permission to save this $entity.';
    }
    if (error is TimeoutException ||
        error.runtimeType.toString().contains('SocketException') ||
        error.runtimeType.toString().contains('ClientException')) {
      return 'Check your internet connection and try again.';
    }
    if (error is PostgrestException) {
      return 'The $entity data could not be validated. Please check the form.';
    }
    return 'Unable to ${isUpdate ? 'update' : 'save'} the $entity. Please try again.';
  }
}
